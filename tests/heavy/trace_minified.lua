-- minify 後のスクリプトを、決まった場面で動かし、Stormworks へ出した呼び出しの記録を標準出力に書く。
-- 単独では使わず、tests/heavy/diff_minified.js から呼ばれる(2つの minify 結果の記録を比べる)。
-- 実行: lua tests/heavy/trace_minified.lua <script.min.lua> <scenario.lua>
-- scenario.lua は diff_minified.js が作る。看板の名前、信号の名前、エリアの重心を持つ。
local script_path, scenario_path = arg[1], arg[2]
local scenario = dofile(scenario_path)

local lines = {}
local function serialize(value, depth)
    local t = type(value)
    if t == "number" then
        return string.format("%.6g", value)
    elseif t == "table" then
        if (depth or 0) > 3 then return "{…}" end
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = tostring(k) .. "=" .. serialize(value[k], (depth or 0) + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "function" then
        return "<function>"
    end
    return tostring(value)
end
local function log(name, ...)
    local args = table.pack(...)
    local parts = {}
    for i = 1, args.n do parts[i] = serialize(args[i]) end
    lines[#lines + 1] = name .. "(" .. table.concat(parts, ", ") .. ")"
end

-- Lua 5.3 は文字列キーの pairs の順を、実行ごとに変える。順序に左右される処理(競合する進路の
-- 勝敗など)が、同じスクリプトでも毎回違う記録を作ってしまうので、キーの並びで固定する。
-- スクリプトより先に差し替える。minify 後のスクリプトは、読み込み時にこの pairs を取り込む。
do
    local raw_next = next
    local function key_less(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end
    pairs = function(t)
        local keys, rest = {}, {}
        for k in raw_next, t do
            local kt = type(k)
            if kt == "number" or kt == "string" then keys[#keys + 1] = k else rest[#rest + 1] = k end
        end
        table.sort(keys, key_less)
        for _, k in ipairs(rest) do keys[#keys + 1] = k end
        local i = 0
        return function()
            while true do
                i = i + 1
                local k = keys[i]
                if k == nil then return nil end
                local v = t[k]
                if v ~= nil then return k, v end
            end
        end, t, nil
    end
end

local VEHICLE_ID = 1
local tick = 0

-- 列車の位置。axle ごとに、通過するエリアの重心を順に巡る。
local function train_position(offset)
    local path = scenario.path
    local index = math.floor((tick - 10) / scenario.ticks_per_area) + 1 - offset
    if index < 1 then index = 1 end
    if index > #path then index = #path end
    return path[index]
end

local sign_list = {}
for i, name in ipairs(scenario.signs) do sign_list[i] = { name = name, pos = { x = 0, y = 0, z = 0 } } end
sign_list[#sign_list + 1] = { name = "TRAIN1", pos = { x = 0, y = 0, z = 0 } }
sign_list[#sign_list + 1] = { name = "TRAIN2", pos = { x = 0, y = 0, z = 2 } }
local buttons = { { name = "N-TRACS RESET" } }
for _, name in ipairs(scenario.signs) do buttons[#buttons + 1] = { name = name .. "_ARC_L" } end
for _, name in ipairs(scenario.signs) do buttons[#buttons + 1] = { name = name .. "_ASPECT" } end
local components = { components = {
    signs = sign_list, buttons = buttons,
    dials = {}, batteries = {}, seats = {}, sliders = {}, indicators = {}, guns = {}, rope_hooks = {}, hoppers = {},
} }

local impl = {
    getVehicleComponents = function() return components, true end,
    getVehiclePos = function(_, vx, vy, vz)
        local p = train_position(vz and vz > 0 and 1 or 0)
        return { x = p.x + (vx or 0), y = (vy or 0), z = p.z + (vz or 0) }, true
    end,
    getVehicleDial = function(_, name)
        name = name or ""
        -- ARC 指令値(7桁: 運行番号2 + 路線1 + 種別2 + 行先駅1 + 番線1)。列車ごとに別の運行番号を持たせる
        if name == "TRAIN1_ARC" then return { value = 1111033 }, true end
        if name == "TRAIN2_ARC" then return { value = 1111033 }, true end
        -- 転てつ器のK(実位置)は、要求どおりに戻る想定で 1 とする
        return { value = name:sub(-1) == "K" and 1 or 0 }, true
    end,
    getPlayers = function() return { { id = 0, name = "Host", admin = true, auth = true, steam_id = 1 } } end,
    getPlayerCharacterID = function() return 5, true end,
    getCharacterVehicle = function() return VEHICLE_ID, true end,
    getStartTile = function() return { x = 0, y = 0, z = 0 } end,
    getWeather = function() return { fog = 0, rain = 0 } end,
}
server = setmetatable({}, { __index = function(_, name)
    return function(...)
        log("server." .. name, ...)
        local f = impl[name]
        if f then return f(...) end
        return nil
    end
end })
property = setmetatable({}, { __index = function(_, name)
    return function(label, default) log("property." .. name, label, default); return default end
end })
matrix = {
    position = function(m) return m.x, m.y, m.z end,
    translation = function(x, y, z) return { x = x, y = y, z = z } end,
}
debug = debug or {}
debug.log = function(message) log("debug.log", message) end

assert(loadfile(script_path))()

local function command(peer, text)
    local words = {}
    for w in text:gmatch("%S+") do words[#words + 1] = w end
    log("-- command", text)
    onCustomCommand(text, peer, true, true, table.unpack(words))
end

onCreate(true)
onPlayerJoin(1, "Host", 0, true, true)
local set_queue = {}
for _, name in ipairs(scenario.levers) do set_queue[#set_queue + 1] = name end
local reset_queue = {}

for i = 1, scenario.ticks do
    tick = i
    if i == 5 then onVehicleLoad(VEHICLE_ID) end
    if i == 8 then command(0, "?nt version") end
    -- ?nt help は pairs(COMMANDS) の順に出す。短縮するとキーの並びが変わる場合があるので、場面に入れない
    if i == 40 then onButtonPress(VEHICLE_ID, 0, "N-TRACS RESET") end
    -- 信号は1つずつ設定して解除する。同時に設定すると、同じ軌道回路を取り合う進路の勝敗が
    -- pairs の順で決まり、実行ごとに結果が変わってしまう
    if i >= 20 and i % 12 == 0 and #reset_queue > 0 then
        command(0, "?nt reset " .. table.remove(reset_queue, 1))
    end
    if i >= 20 and i % 12 == 6 then
        local name = table.remove(set_queue, 1)
        if name then
            command(0, "?nt set " .. name)
            command(0, "?nt aspect " .. name)
            reset_queue[#reset_queue + 1] = name
        end
    end
    if i == 100 then command(0, "?nt arc " .. scenario.arc_station .. " list") end
    if i == 101 then command(0, "?nt arc " .. scenario.arc_station .. " start") end
    if i == 150 then command(0, "?nt arc " .. scenario.arc_station .. " stop") end
    if i == 160 then command(0, "?nt unknown_command") end
    log("-- tick", i)
    onTick(1)
end
onVehicleDespawn(VEHICLE_ID)
onPlayerLeave(1, "Host", 0, true, true)
onDestroy()

for _, line in ipairs(lines) do print(line) end
