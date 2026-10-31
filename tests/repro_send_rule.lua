-- res/area_track.lua の短くした callback が、エディタの書き出した元の Lua
-- (res/area_track_plain.lua)と同じ値を、同じ軸へ送ることを確かめる。
-- 信号・てこ・転てつ器・軸の位置と速さ・照査点のタイマーを乱数で振り、同じ状態で両方を動かして比べる。
package.path = "./?.lua;" .. package.path
local h = require("tests.harness")
local SetRoute = require("src.n_tracs_core.switch.set_route")
local BookType = require("src.n_tracs_core.track.book_type")

local ROUNDS = 600
local c = h.new_checker()

-- 状態は名前ごとに、1回の試行の中で一度だけ決める。両方の callback が同じ値を読む
local state
-- Track ごとに、条件で比べられるてこの名前。{ relatedLever = { [track] = { name... } }, destRelatedLever = ... }
local levers = { relatedLever = {}, destRelatedLever = {} }
local function pick(names)
    return names[math.random(#names)]
end
local function memo(kind, name, make)
    local key = kind .. ":" .. name
    if state[key] == nil then state[key] = make() end
    return state[key]
end

local function new_stage()
    local nt = {}
    local log = {} -- この舞台のタイマー操作。両方の callback で同じ並びになるはず
    function nt:get_signal(name)
        return memo("signal", name, function()
            return { aspect = math.random(0, 4), HR = math.random() < 0.5 }
        end)
    end
    function nt:get_track(name)
        local base = memo("track", name, function()
            local book = { BookType.NoBook, BookType.RouteLock }
            local dest = { BookType.NoBook, BookType.DestinationActive, BookType.DestinationExpired }
            return {
                relatedLever = pick(levers.relatedLever[name] or { "NONE" }),
                destRelatedLever = pick(levers.destRelatedLever[name] or { "NONE" }),
                book = pick(book),
                bookDest = pick(dest),
                timers = {},
            }
        end)
        -- 値は両方の舞台で共有し、タイマーの操作だけ舞台ごとに記録する
        local track = setmetatable({}, { __index = base })
        function track:get_timer(key)
            local t = base.timers
            if t[key] == nil then t[key] = pick({ 0, 0, 1, 6, 100, 174, 180, 185, 400 }) end
            return t[key]
        end
        function track:advance_timer(key, dt) log[#log + 1] = "a" .. key .. dt end
        function track:reset_timer(key) log[#log + 1] = "r" .. key end
        return track
    end
    function nt:get_switch(name)
        local route = memo("switch", name, function()
            return math.random() < 0.5 and SetRoute.Normal or SetRoute.Reverse
        end)
        return { getRealRoute = function() return route end }
    end
    local s = { nt = nt, areas = {}, track_bridge = {}, log = log }
    function s.create_area(_, id, _, _, _, _, callback)
        s.areas[id] = { itemName = id, axles = {}, callback = callback }
    end
    function s.create_track(_, name, area_ids)
        s.track_bridge[name] = { area_ids = area_ids }
    end
    return s
end

local function chunk_of(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("a")
    f:close()
    return assert(load(text, path))(), text
end

local compact = chunk_of("res/area_track.lua")
local plain, plain_text = chunk_of("res/area_track_plain.lua")

for _, field in ipairs({ "relatedLever", "destRelatedLever" }) do
    local pattern = 'nt:get_track%("([%w_]+)"%)%.' .. field .. ' == "([%w_]+)"'
    for track, name in plain_text:gmatch(pattern) do
        local list = levers[field][track] or { "NONE" }
        levers[field][track] = list
        list[#list + 1] = name
    end
end

local a, b = new_stage(), new_stage()
compact(a)
plain(b)

-- 軸は1回だけ振り、両方の舞台へ同じ値で置く。照査点(x 1345〜1368、z -3751 付近)のまわりに置く
local function make_axles(count)
    local axles = {}
    for i = 1, count do
        local axle = { real_pos = { x = 1344 + math.random() * 26, z = -3751 + (math.random() - 0.5) * 10 } }
        if math.random() < 0.9 then
            local speed = math.random() * 20 -- 1周期(0.1 秒)に動く距離が、照査点をまたげる幅になるように速くする
            axle.delta_pos = { x = -speed * (0.5 + math.random()), z = (math.random() - 0.5) * 0.3 }
            axle.velocity = speed
        end
        axles[i] = axle
    end
    return axles
end

local function put_axles(s, id, specs)
    local axles = {}
    for i, spec in ipairs(specs) do
        axles[i] = { sending = {}, real_pos = spec.real_pos, delta_pos = spec.delta_pos, velocity = spec.velocity }
    end
    s.areas[id].axles = axles
end

local function sent(s, id)
    local out = {}
    for i, axle in ipairs(s.areas[id].axles) do
        out[i] = table.concat(axle.sending, ",")
    end
    -- タイマーの操作も並べて比べる。読んだあとは空にする
    local ops = table.concat(s.log, ";")
    for i = #s.log, 1, -1 do s.log[i] = nil end
    return table.concat(out, "|") .. "#" .. ops
end

math.randomseed(20261031)
local ids = {}
for id in pairs(b.areas) do ids[#ids + 1] = id end
table.sort(ids)

local compared, differ, nonempty, timed, restarted = 0, 0, 0, 0, 0
for _ = 1, ROUNDS do
    state = {}
    local density = pick({ 0.02, 0.1, 0.5 })
    for _, id in ipairs(ids) do
        -- 軸を置きすぎると、先頭の軸の判定が端の Area でしか成り立たず、送信まで届かない
        local count = math.random() < density and math.random(1, 2) or 0
        local specs = make_axles(count)
        put_axles(a, id, specs)
        put_axles(b, id, specs)
    end
    for _, id in ipairs(ids) do
        a.areas[id].callback(a.areas[id], a.nt, 6)
        b.areas[id].callback(b.areas[id], b.nt, 6)
        local x, y = sent(a, id), sent(b, id)
        compared = compared + 1
        if x ~= y then
            differ = differ + 1
            c:check("Area " .. tostring(id), x, y)
        end
        if y:match("^[^#]*%d") then nonempty = nonempty + 1 end
        if y:find("#.") then timed = timed + 1 end
        if y:find(";r") or y:find("#r") then restarted = restarted + 1 end
    end
end

print(string.format("比較 %d 回 / 値を送った回 %d / タイマーを操作した回 %d / 照査点を横切った回 %d / 不一致 %d", compared, nonempty, timed, restarted, differ))
c:check("不一致がない", differ, 0)
c:check("値を送る場面を通っている", nonempty > 0, true)
c:check("タイマーを進める場面を通っている", timed > 0, true)
c:check("照査点を横切る場面を通っている", restarted > 0, true)
c:report()
