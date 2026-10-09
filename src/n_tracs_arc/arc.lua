-- N-TRACS ARC (Automatic Route Control)
-- 駅ごとの設定(res/arc.lua)に従い、列車のARC指令値から進路要求を自動で出す。
-- 設計は docs/arc.md を参照。

local ArcValue = require("src.n_tracs_arc.arc_value")
local BookType = require("src.n_tracs_core.track.book_type")

---@class ArcOption 「動き」の進路の選び方。先に書いたものから、準備できたものを使う
---@field signal string 進路を要求するてこ
---@field platform number|nil この選択肢が行き先とする番線。ARC指令値で番線が指定されたときの絞り込みに使う
---@field uses string[]|nil 使う資源名
---@field dest string|nil 着線(資源名)
---@field reserve {name: string, mode: "hold"|"take"|"free"}|nil 予約資源。hold: 持っていること、take: 採用時に取る、free: 空いているときだけ使う(取らない)

---@class ArcMove 「動き」
---@field class number ソートのクラス(小さいほど優先)
---@field start_point string|nil 制御開始点(軌道回路ID)。列車がここを過ぎるまで採用しない
---@field from string|nil 出発元のホーム(資源名)。制御開始点がなければ、ここに停車していることが準備の条件になる
---@field enter string[] 信号の内方(軌道回路ID)。列車がここに現れたら「動き」は済んだ
---@field options ArcOption[]

---@class ArcSequence 「一連の動き」
---@field id string
---@field match {at: string[], b: number|nil, dest: "terminal"|"through"|"unspecified"|nil, pullin: boolean|nil, category: number[]|nil, class: number[]|nil}
---@field moves ArcMove[]

---@class ArcRequest
---@field pp number
---@field seq ArcSequence
---@field idx number 今の「動き」
---@field reg number 登録番号
---@field arc ArcValue 登録時(採用前は毎tick)のARC指令値
---@field promote boolean 繰り上げの印
---@field excluded boolean 除外の印
---@field adopted "requested"|"locked"|nil 採用の印
---@field opt ArcOption|nil 採用した選択肢
---@field passed boolean 今の「動き」の制御開始点を過ぎたか

---@class ArcStation
---@field code number
---@field running boolean
---@field resources table<string, string[]>
---@field sequences ArcSequence[]
---@field requests table<number, ArcRequest> key: 運行番号
---@field next_reg number
---@field blocked_dest table<string, boolean> 前回の判定で、着線が空かず待った候補の着線
---@field alerts string[] 動けなくなる組み合わせの警報(毎tick作り直す)

---@class Arc
---@field nt Ntracs
---@field probe fun(track_id: string): number, number 軌道回路上のARC指令値と速さ(m/s)
---@field stop_speed number
---@field stations table<string, ArcStation>
---@field reservations table<string, {release: {at: string[], b: number|nil}[], owner: number|nil}>
---@field watch string[] 観測する軌道回路
local Arc = {}
Arc.__index = Arc

local function set_of(list)
    local s = {}
    for _, v in ipairs(list or {}) do s[v] = true end
    return s
end

local function contains(list, v)
    for _, x in ipairs(list) do
        if x == v then return true end
    end
    return false
end

---@param config table res/arc.lua の内容
---@param nt Ntracs
---@param probe fun(track_id: string): number, number
---@return Arc
function Arc.new(config, nt, probe)
    local self = setmetatable({}, Arc)
    self.nt = nt
    self.probe = probe
    self.stop_speed = config.stop_speed or 0.5
    self.stations = {}
    self.reservations = {}
    for name, r in pairs(config.reservations or {}) do
        self.reservations[name] = { release = r.release or {}, owner = nil }
    end

    local watch = {}
    local function add_watch(id)
        if id then watch[id] = true end
    end

    for name, st in pairs(config.stations or {}) do
        local station = {
            code = st.code,
            running = st.running ~= false,
            resources = st.resources or {},
            sequences = st.sequences or {},
            requests = {},
            next_reg = 1,
            blocked_dest = {},
            alerts = {},
        }
        self.stations[name] = station
        self:validate(name, station)
        for _, seq in ipairs(station.sequences) do
            for _, t in ipairs(seq.match.at) do add_watch(t) end
            for _, move in ipairs(seq.moves) do
                add_watch(move.start_point)
                for _, t in ipairs(move.enter) do add_watch(t) end
                if move.from then
                    for _, t in ipairs(station.resources[move.from]) do add_watch(t) end
                end
            end
        end
    end
    for _, r in pairs(self.reservations) do
        for _, rel in ipairs(r.release) do
            for _, t in ipairs(rel.at) do add_watch(t) end
        end
    end

    self.watch = {}
    for id in pairs(watch) do table.insert(self.watch, id) end
    table.sort(self.watch)
    return self
end

---設定が参照するものが存在することを確認する。誤りがあればerrorで止まる
---@private
---@param name string
---@param st ArcStation
function Arc:validate(name, st)
    local function fail(msg) error("[ARC:" .. name .. "] " .. msg) end
    for res, tracks in pairs(st.resources) do
        for _, t in ipairs(tracks) do
            if not self.nt:get_track_may_nil(t) then fail("resource " .. res .. ": track " .. t .. " is not found") end
        end
    end
    local function check_track(t, what)
        if not self.nt:get_track_may_nil(t) then fail(what .. ": track " .. tostring(t) .. " is not found") end
    end
    local function check_res(r, what)
        if not st.resources[r] then fail(what .. ": resource " .. tostring(r) .. " is not defined") end
    end
    for _, seq in ipairs(st.sequences) do
        local at = "sequence " .. seq.id
        if #seq.moves == 0 then fail(at .. " has no moves") end
        for _, t in ipairs(seq.match.at) do check_track(t, at .. " match.at") end
        for i, move in ipairs(seq.moves) do
            local mv = at .. " move " .. i
            if type(move.class) ~= "number" then fail(mv .. ": class is required") end
            if #move.options == 0 then fail(mv .. " has no options") end
            if move.start_point then check_track(move.start_point, mv .. " start_point") end
            if move.from then check_res(move.from, mv .. " from") end
            for _, t in ipairs(move.enter) do check_track(t, mv .. " enter") end
            for _, opt in ipairs(move.options) do
                local sig = self.nt:get_signal_may_nil(opt.signal)
                if not sig then fail(mv .. ": signal " .. tostring(opt.signal) .. " is not found") end
                if type(sig.isRouteLocked) ~= "function" then fail(mv .. ": signal " .. opt.signal .. " is not a route lever") end
                for _, r in ipairs(opt.uses or {}) do check_res(r, mv .. " uses") end
                if opt.dest then check_res(opt.dest, mv .. " dest") end
                if opt.reserve then
                    if not self.reservations[opt.reserve.name] then fail(mv .. ": reservation " .. tostring(opt.reserve.name) .. " is not defined") end
                    if opt.reserve.mode ~= "hold" and opt.reserve.mode ~= "take" and opt.reserve.mode ~= "free" then fail(mv .. ": reserve.mode must be hold, take or free") end
                end
            end
        end
    end
end

-- 観測 ---------------------------------------------------------------------

---観測した列車。key: 運行番号
---@param self Arc
---@return table<number, {arc: ArcValue, tracks: table<string, number>}> tracks: 在線している軌道回路 → 速さ
local function observe(self)
    local obs = {}
    for _, id in ipairs(self.watch) do
        local raw, speed = self.probe(id)
        local v = ArcValue.parse(raw)
        if v and v.pp > 0 then
            local o = obs[v.pp]
            if not o then
                o = { arc = v, tracks = {} }
                obs[v.pp] = o
            end
            o.tracks[id] = speed or 0
        end
    end
    return obs
end

---資源が塞がっているか。在線があるか、lever以外のてこが予約しているとき塞がっている
---@param self Arc
---@param station ArcStation
---@param res string
---@param lever string 判定する進路のてこ(自分の予約は塞がりに数えない)
local function resource_busy(self, station, res, lever)
    for _, id in ipairs(station.resources[res]) do
        local t = self.nt:get_track(id)
        if t:is_short() then return true end
        ---@diagnostic disable-next-line: invisible
        if t.book ~= BookType.NoBook and t.relatedLever ~= lever then return true end
        ---@diagnostic disable-next-line: invisible
        if t.bookDest ~= BookType.NoBook and t.destRelatedLever ~= lever then return true end
    end
    return false
end

-- 受付 ---------------------------------------------------------------------

---@param station ArcStation
---@param arc ArcValue
---@param tracks table<string, number>
---@return ArcSequence|nil
local function find_sequence(station, arc, tracks)
    local kind = "unspecified"
    if arc.station == station.code then
        kind = "terminal"
    elseif arc.station ~= 0 then
        kind = "through"
    end
    for _, seq in ipairs(station.sequences) do
        local m = seq.match
        local ok = (m.b == nil or m.b == arc.b)
            and (m.dest == nil or m.dest == kind)
            and (m.pullin == nil or m.pullin == (arc.platform == 9))
            and (m.category == nil or contains(m.category, arc.category))
            and (m.class == nil or contains(m.class, arc.class))
        if ok then
            for _, t in ipairs(m.at) do
                if tracks[t] then return seq end
            end
        end
    end
    return nil
end

---@param station ArcStation
---@param obs table
local function accept(station, obs)
    for pp, o in pairs(obs) do
        local seq = find_sequence(station, o.arc, o.tracks)
        local req = station.requests[pp]
        if req == nil then
            if seq then
                station.requests[pp] = {
                    pp = pp, seq = seq, idx = 1, reg = station.next_reg, arc = o.arc,
                    promote = false, excluded = false, adopted = nil, opt = nil, passed = false,
                }
                station.next_reg = station.next_reg + 1
            end
        elseif req.adopted == nil then
            req.arc = o.arc
            -- 最初の「動き」にいるうちは「一連の動き」を書き換えてよい。途中からは書き換えない
            if req.idx == 1 then
                if seq == nil then
                    station.requests[pp] = nil
                elseif seq ~= req.seq then
                    req.seq = seq
                    req.passed = false
                end
            end
        end
    end
    -- ARC指令値が消えた、または列車がいなくなった要求
    for pp, req in pairs(station.requests) do
        if obs[pp] == nil and (req.adopted == nil or req.excluded) then
            station.requests[pp] = nil
        end
    end
end

-- 「動き」の更新 -------------------------------------------------------------

---@param self Arc
---@param station ArcStation
---@param obs table
local function update_moves(self, station, obs)
    for pp, req in pairs(station.requests) do
        local move = req.seq.moves[req.idx]

        if req.adopted == nil and obs[pp] and not req.passed then
            -- 制御開始点を過ぎたかは、現れた記憶で持つ(短い軌道回路を飛ばしても取りこぼさない)
            req.passed = move.start_point == nil or obs[pp].tracks[move.start_point] ~= nil
        end

        if req.adopted then
            local entered = false
            for _, t in ipairs(move.enter) do
                if obs[pp] and obs[pp].tracks[t] then entered = true end
            end
            ---@diagnostic disable-next-line: invisible
            local locked = self.nt:get_signal(req.opt.signal):isRouteLocked(self.nt)

            if req.adopted == "requested" and locked then
                req.adopted = "locked"
            elseif req.adopted == "requested" and not entered then
                -- 次の周期になっても鎖錠されていない: N-TRACSが受け付けなかったとみなして候補に戻す
                req.adopted = nil
                req.opt = nil
            end

            if req.adopted == "locked" then
                if entered then
                    if req.seq.moves[req.idx + 1] then
                        req.idx = req.idx + 1
                        req.adopted = nil
                        req.opt = nil
                        req.passed = false
                    else
                        station.requests[pp] = nil
                    end
                elseif not locked then
                    req.excluded = true
                    req.adopted = nil
                    req.opt = nil
                end
            end
        end
    end
end

-- 予約資源の解放 --------------------------------------------------------------

---@param self Arc
---@param obs table
local function release_reservations(self, obs)
    for _, r in pairs(self.reservations) do
        local o = r.owner and obs[r.owner]
        if o then
            for _, rel in ipairs(r.release) do
                if rel.b == nil or rel.b == o.arc.b then
                    for _, t in ipairs(rel.at) do
                        if o.tracks[t] then r.owner = nil end
                    end
                end
            end
        end
    end
end

-- 判定 ---------------------------------------------------------------------

---ある選択肢が準備できているか
---@param self Arc
---@param station ArcStation
---@param req ArcRequest
---@param opt ArcOption
---@param claimed table<string, boolean> 鎖錠中(採用済み)の進路の着線
---@return boolean ready
---@return string|nil blocked_dest 着線がふさがっているときだけ、その着線
local function option_ready(self, station, req, opt, claimed)
    if opt.platform and req.arc.platform ~= 0 and req.arc.platform ~= 9 and opt.platform ~= req.arc.platform then
        return false
    end
    if opt.dest and (claimed[opt.dest] or resource_busy(self, station, opt.dest, opt.signal)) then
        return false, opt.dest
    end
    if opt.reserve then
        local owner = self.reservations[opt.reserve.name].owner
        if opt.reserve.mode == "hold" then
            if owner ~= req.pp then return false end
        elseif opt.reserve.mode == "free" then
            if owner ~= nil then return false end
        elseif owner ~= nil and owner ~= req.pp then
            return false
        end
    end
    return true
end

---@param self Arc
---@param station ArcStation
---@param obs table
local function judge(self, station, obs)
    -- 候補を集める
    local cands = {}
    for _, req in pairs(station.requests) do
        if req.adopted == nil and not req.excluded and req.passed then
            local move = req.seq.moves[req.idx]
            local ok = true
            -- 制御開始点のない出発の「動き」は、ホームに停車していることが条件
            if move.from and not move.start_point then
                ok = false
                local o = obs[req.pp]
                if o then
                    for _, t in ipairs(station.resources[move.from]) do
                        if o.tracks[t] and o.tracks[t] <= self.stop_speed then ok = true end
                    end
                end
            end
            if ok then table.insert(cands, req) end
        end
    end

    -- ソート: 繰り上げ、クラス、着線を空ける補正、登録番号
    local function key(req)
        local move = req.seq.moves[req.idx]
        local correction = (move.from and station.blocked_dest[move.from]) and 0 or 1
        return req.promote and 0 or 1, move.class, correction, req.reg
    end
    table.sort(cands, function(a, b)
        local a1, a2, a3, a4 = key(a)
        local b1, b2, b3, b4 = key(b)
        if a1 ~= b1 then return a1 < b1 end
        if a2 ~= b2 then return a2 < b2 end
        if a3 ~= b3 then return a3 < b3 end
        return a4 < b4
    end)

    -- 鎖錠中とみなす資源・着線: 採用済みの進路 + このtickで採用した進路
    local busy_now, claimed = {}, {}
    for _, req in pairs(station.requests) do
        if req.adopted and req.opt then
            for _, r in ipairs(req.opt.uses or {}) do busy_now[r] = true end
            if req.opt.dest then claimed[req.opt.dest] = true end
        end
    end

    local waiting = {}        -- 待ち一覧: 資源名の集合
    local blocked_dest = {}
    for _, req in ipairs(cands) do
        local move = req.seq.moves[req.idx]
        local chosen
        for _, opt in ipairs(move.options) do
            local ok, blocked = option_ready(self, station, req, opt, claimed)
            if ok then
                chosen = opt
                break
            elseif blocked then
                blocked_dest[blocked] = true
            end
        end

        if chosen then
            local conflict = false
            local uses = chosen.uses or {}
            for _, r in ipairs(uses) do
                if busy_now[r] or resource_busy(self, station, r, chosen.signal) then conflict = true end
            end
            if chosen.reserve and chosen.reserve.mode == "take" then
                uses = { table.unpack(uses) }
                table.insert(uses, "reserve:" .. chosen.reserve.name)
            end
            if not conflict then
                for _, r in ipairs(uses) do
                    if waiting[r] then conflict = true end
                end
            end

            if conflict then
                for _, r in ipairs(uses) do waiting[r] = true end
            else
                self.nt:get_signal(chosen.signal):setInput(true, self.nt)
                if chosen.reserve and chosen.reserve.mode == "take" then
                    self.reservations[chosen.reserve.name].owner = req.pp
                end
                for _, r in ipairs(chosen.uses or {}) do busy_now[r] = true end
                if chosen.dest then claimed[chosen.dest] = true end
                req.adopted = "requested"
                req.opt = chosen
                req.promote = false
            end
        end
    end
    station.blocked_dest = blocked_dest
end

-- 動けなくなる組み合わせの検知 --------------------------------------------------

---準備できていない要求が、着線にいる列車の要求を待っているとみなし、待ちの輪を探す
---@param self Arc
---@param station ArcStation
---@param obs table
local function detect_deadlock(self, station, obs)
    station.alerts = {}
    local waits_for = {}
    for pp, req in pairs(station.requests) do
        if req.adopted == nil and not req.excluded then
            local move = req.seq.moves[req.idx]
            for _, opt in ipairs(move.options) do
                if opt.dest then
                    for other, o in pairs(obs) do
                        if other ~= pp then
                            for _, t in ipairs(station.resources[opt.dest]) do
                                if o.tracks[t] then waits_for[pp] = other end
                            end
                        end
                    end
                end
            end
        end
    end
    local reported = {}
    for start in pairs(waits_for) do
        local seen, cur = {}, start
        while cur and not seen[cur] do
            seen[cur] = true
            cur = waits_for[cur]
        end
        if cur == start then
            local ring = { cur }
            local n = waits_for[cur]
            while n ~= cur do
                table.insert(ring, n)
                n = waits_for[n]
            end
            table.sort(ring)
            local text = table.concat(ring, "<->")
            if not reported[text] then
                reported[text] = true
                table.insert(station.alerts, text)
            end
        end
    end
end

-- 周期処理 -------------------------------------------------------------------

---N-TRACSの演算結果が確定したあと、次の演算の前に呼ぶ
function Arc:process()
    local obs = observe(self)
    release_reservations(self, obs)
    for _, station in pairs(self.stations) do
        accept(station, obs)
        update_moves(self, station, obs)
        if station.running then
            judge(self, station, obs)
        end
        detect_deadlock(self, station, obs)
    end
end

-- 外からの操作 -----------------------------------------------------------------

---@param name string
---@return ArcStation|nil
function Arc:get_station(name)
    return self.stations[name]
end

---駅のARCを停止・再開する。停止中も受付と「動き」の更新は続く
---@param name string
---@param running boolean
function Arc:set_running(name, running)
    self.stations[name].running = running
end

---要求を一回限り先頭に繰り上げる
---@param name string
---@param pp number
---@return boolean
function Arc:promote(name, pp)
    local req = self.stations[name].requests[pp]
    if req then req.promote = true end
    return req ~= nil
end

---除外した要求を戻す
---@param name string
---@param pp number
---@return boolean
function Arc:restore(name, pp)
    local req = self.stations[name].requests[pp]
    if req then req.excluded = false end
    return req ~= nil
end

---要求を削除する
---@param name string
---@param pp number
---@return boolean
function Arc:remove(name, pp)
    local req = self.stations[name].requests[pp]
    self.stations[name].requests[pp] = nil
    return req ~= nil
end

---予約資源を手動で放す
---@param name string
function Arc:release(name)
    self.reservations[name].owner = nil
end

return Arc
