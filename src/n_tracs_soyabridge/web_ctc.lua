-- Web CTC との HTTP 通信
-- 連動装置の事実を、変化したものを先に、残りを巡回で、同じコンピュータのサーバーへ送る。
-- サーバーからのコマンドは応答に載って届く。仕様は Claude Doc「ビークル／Web CTC卓 通信仕様（下書き）」の Web 卓の節。

local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local SetRoute = require("src.n_tracs_core.switch.set_route")

-- 開発者が決める値。PORT 以外は実測前の仮置きで、実測してから入れ直す
local DEFAULT_PORT = 8131      -- tools/webctc_logger.js の既定値と同じにする
local TIMEOUT_TICKS = 600      -- 仮置き。応答を待つ時間
local BUDGET_CHARS = 2000      -- 仮置き。1 回のリクエストの URL の字数
local BACKOFF_MIN_TICKS = 60   -- 仮置き。失敗が続いたときの間隔の初期値（倍々に延ばす）
local BACKOFF_MAX_TICKS = 1800 -- 仮置き。間隔の上限
local CYCLIC_RATIO = 0.25      -- 仮置き。巡回の分の最低割合

local WRAP = 1000000
local MARKER = "N-TRACS for Stormworks/1"
local PATH = "/ntracs/v1/state"
local TAIL = "&end=1"

local function enc(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function bit(b)
    return b and 1 or 0
end

local SWITCH_K = { [SetRoute.Normal] = 1, [SetRoute.Reverse] = 2 }

---@class WebCtc:NtracsObject
local WebCtc = {}

---@param sw SoyaBridge
---@param version string 路線のデータの版（CTC_VERSION）
---@param run_line fun(line: string) 応答に載ったコマンドを 1 行ずつ実行する
---@return WebCtc
function WebCtc.new(sw, version, run_line)
    -- Stormworks では setmetatable が使えないので、クラスの関数をインスタンスに写す
    local self = NtracsObject.create_instance({}, WebCtc)
    self.name = "WebCtc"
    self.sw = sw
    self.version = version
    self.run_line = run_line
    self.area_track = sw:area_to_tracks()
    self.arc_of = {}
    self.last = {}  -- キー -> 前回送った値
    self.since = {} -- キー -> 前回送った値と違うと最初に見た時刻
    self.cursor = 1
    self.seq = 0
    self.cycle = 0
    self.clock = 0
    self.next_at = 0
    self.fails = 0
    self.connected = false

    -- 事実の一覧。キーの順に並べ、巡回はこの順に進む
    local facts, arc_of, nt = {}, self.arc_of, sw.nt
    local function add(key, read) facts[#facts + 1] = { key = key, read = read } end
    for id, t in pairs(nt.track) do
        add("track." .. id .. ".short", function() return bit(t:is_short()) end)
        add("track." .. id .. ".locked", function() return bit(t:is_locked(true)) end)
        add("track." .. id .. ".arc", function() return arc_of[id] or 0 end)
    end
    for id, s in pairs(nt.switch) do
        add("switch." .. id .. ".k", function() return SWITCH_K[s:getRealRoute()] or 0 end)
    end
    for id, g in pairs(nt.signal) do
        add("signal." .. id .. ".aspect", function() return g.aspect or 0 end)
        if g.getInput then
            add("signal." .. id .. ".input", function() return bit(g:getInput()) end)
        end
    end
    table.sort(facts, function(a, b) return a.key < b.key end)
    self.facts = facts
    return self
end

---@return boolean
function WebCtc:enabled()
    local g = _ENV["g_savedata"]
    return g ~= nil and g.webCtc == true
end

---@return integer
function WebCtc:port()
    local g = _ENV["g_savedata"]
    return (g and g.webCtcPort) or DEFAULT_PORT
end

---オン・オフやポートを変えたときに、接続の状態を初めからにする
function WebCtc:reset()
    self.waiting = nil
    self.connected = false
    self.fails = 0
    self.next_at = self.clock
end

---@return string
function WebCtc:status()
    if not self:enabled() then return "Web CTC: OFF" end
    local head = "Web CTC: ON (port " .. self:port() .. "): "
    if self.connected then return head .. "connected" end
    return head ..
        "server not found. Start the Web CTC server on the computer hosting this game, or check the port number."
end

---配信のフェーズで呼ぶ
---@param dt number 前回の呼び出しからの経過時間(tick)
function WebCtc:tick(dt)
    self.clock = self.clock + dt
    if not self:enabled() then return end
    if self.waiting then
        if self.clock - self.waiting.at < TIMEOUT_TICKS then return end
        self:failed("no reply", self.waiting.facts)
    end
    if self.clock >= self.next_at then self:send() end
end

function WebCtc:send()
    self.boot = self.boot or math.floor(server.getTimeMillisec()) % WRAP
    self.seq = (self.seq + 1) % WRAP
    local head = PATH .. "?v=" .. enc(self.version) .. "&b=" .. self.boot .. "&s=" .. self.seq .. "&c=" .. self.cycle
    -- つながっていないあいだは事実を載せない
    local parts = self.connected and self:pick(BUDGET_CHARS - #head - #TAIL) or {}
    local port = self:port()
    self.waiting = { b = self.boot, s = self.seq, port = port, at = self.clock, facts = #parts > 0 }
    server.httpGet(port, head .. table.concat(parts) .. TAIL)
end

---1 回に載せる事実を選ぶ。変化したものを古い順に先に詰め、残りを巡回で埋める
---@param budget integer 事実に使える字数
---@return string[]
function WebCtc:pick(budget)
    local arc_of = self.arc_of
    for k in pairs(arc_of) do arc_of[k] = nil end
    for _, r in ipairs(self.sw:arc_readings(self.area_track)) do
        arc_of[r[1]] = math.max(arc_of[r[1]] or 0, r[2])
    end

    local facts, last, since, now, changed = self.facts, self.last, self.since, {}, {}
    for i, f in ipairs(facts) do
        local v = math.floor(f.read())
        now[i] = v
        if v ~= last[f.key] then
            since[f.key] = since[f.key] or self.clock
            changed[#changed + 1] = i
        else
            since[f.key] = nil
        end
    end
    table.sort(changed, function(a, b)
        local x, y = since[facts[a].key], since[facts[b].key]
        if x ~= y then return x < y end
        return a < b
    end)

    local parts, used, taken, limit = {}, 0, {}, budget - math.floor(budget * CYCLIC_RATIO)
    local function put(i)
        local s = "&" .. enc(facts[i].key) .. "=" .. now[i]
        if used + #s > limit then return false end
        parts[#parts + 1] = s
        used = used + #s
        taken[i] = true
        last[facts[i].key] = now[i]
        since[facts[i].key] = nil
        return true
    end
    for _, i in ipairs(changed) do
        if not put(i) then break end
    end
    limit = budget
    for _ = 1, #facts do
        local i = self.cursor
        if not taken[i] and not put(i) then break end
        self.cursor = i % #facts + 1
        if self.cursor == 1 then self.cycle = (self.cycle + 1) % WRAP end
    end
    return parts
end

function WebCtc:succeeded()
    if not self.connected then dlog("Web CTC: connected (port " .. self:port() .. ")") end
    self.connected = true
    self.fails = 0
    self.next_at = self.clock
end

---@param reason string
---@param with_facts boolean 失敗したリクエストに事実を載せていたか
function WebCtc:failed(reason, with_facts)
    self.waiting = nil
    if self.connected or self.fails == 0 or with_facts then
        -- 事実を載せたときだけ失敗するなら、URL の字数の予算が大きすぎる疑いがある
        dlog("Web CTC: request failed (port " .. self:port() .. (with_facts and ", with facts" or "") .. "): " ..
            tostring(reason):sub(1, 80))
    end
    self.connected = false
    self.fails = self.fails + 1
    self.next_at = self.clock + math.min(BACKOFF_MIN_TICKS * 2 ^ (self.fails - 1), BACKOFF_MAX_TICKS)
end

---httpReply から呼ぶ
---@param port integer
---@param request string
---@param reply string
function WebCtc:on_reply(port, request, reply)
    if not self:enabled() or port ~= self:port() or request:sub(1, #PATH) ~= PATH then return end
    reply = reply or ""
    local lines = {}
    for line in (reply .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    local ok = lines[1] == MARKER

    local w = self.waiting
    if w and w.b == tonumber(request:match("[?&]b=(%d+)")) and w.s == tonumber(request:match("[?&]s=(%d+)")) then
        self.waiting = nil
        if ok then self:succeeded() else self:failed(reply, w.facts) end
    end
    -- 遅れて届いた応答でも、印があればコマンドは実行する。サーバーは届けたつもりでいるため
    if ok then
        for i = 2, #lines do
            if lines[i] ~= "" then self.run_line(lines[i]) end
        end
    end
end

return WebCtc
