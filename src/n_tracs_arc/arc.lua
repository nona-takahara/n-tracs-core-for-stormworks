-- N-TRACS ARC (Automatic Route Control)
-- 駅ごとの設定(res/arc.lua)に従い、列車のARC指令値から進路要求を自動で出す。
-- 設計は docs/implementation/arc.md、仕様の判断(D1〜)は Docs「ARC 仕様書(草案)」を参照。

-- Stormworksのアドオン環境では setmetatable / assert / error / pcall / select / require(実行時) が使えない。
-- 使える標準関数は docs/implementation/stormworks-lua.md を参照。
-- 設定の誤りは、ビルド時(pnpm build)に src/n_tracs_arc/arc_check.lua で検出する。実行時には設定を検査せず、何も表示しない。
local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local BookType = require("src.n_tracs_core.track.book_type")

---@class ArcOption 「動き」の進路の選び方。先に書いたものから、準備できたものを使う
---@field signal string 進路を要求するてこ
---@field accept (fun(arc: any): boolean)|nil この選択肢を使ってよい指令値か。省略すると常に使ってよい
---@field uses string[]|nil 使う資源名
---@field dest string|nil 着線(資源名)
---@field reserve {name: string, mode: "hold"|"take"|"free"}|nil 予約資源。hold: 持っていること、take: 採用時に取る、free: 空いているときだけ使う(取らない)
---@field settle boolean|nil 最後の「動き」の選択肢だけに置く(dest が必要)。この進路で到着した列車は、先頭軸が着線に入るまで「入線中」として、新しい要求を登録しない。着線に入った時点から、次の「動き」の wait を数える

---@class ArcMove 「動き」
---@field class number ソートのクラス(小さいほど優先)
---@field start_point string|nil 制御開始点(軌道回路ID)。列車がここを過ぎるまで採用しない
---@field start_delay number|nil 秒。列車が制御開始点に現れてから、この秒数がたつまで採用しない(先出しも同じ)。軌道回路が長く、間に制御開始点を置けないときに使う
---@field early {start_point: string, accept: fun(arc: any): boolean}|nil 指令値が accept に合う列車だけ、制御開始点を start_point に置き換える(速い種別に、現示を早く出すため)
---@field from string|nil 出発元のホーム(資源名)。制御開始点がなければ、列車がここの軌道回路に入っていることが準備の条件になる
---@field enter string[] 信号の内方(軌道回路ID)。列車がここに現れたら「動き」は済んだ
---@field wait number|nil 秒。直前の到着(settle)で着線に先頭軸が入ってから、この秒数が過ぎるまで採用しない。到着の記録がない列車には効かない
---@field options ArcOption[]

---@class ArcSequence 「一連の動き」
---@field id string
---@field match {at: string[], accept: fun(arc: any, station_code: number): boolean} at: 登録点(第1の「動き」の制御開始点も登録点として扱う)。accept: この「一連の動き」で扱う指令値か
---@field moves ArcMove[]

---@class ArcRequest
---@field key number|string 列車の識別子(train_idの戻り値)
---@field seq ArcSequence
---@field idx number 今の「動き」
---@field reg number 登録番号
---@field arc any 登録時(採用前は毎周期)のARC指令値
---@field promote boolean 繰り上げの印
---@field excluded boolean 除外の印
---@field seen table<string, number> 登録以降に列車が現れた軌道回路と、最初に現れた時刻(tick)
---@field pre {adopted: "requested"|"locked", opt: ArcOption, since: number}|nil 先出しした次の「動き」の採用(一連の動きの中で、今の「動き」が済む前に出す)
---@field adopted "requested"|"locked"|nil 採用の印
---@field opt ArcOption|nil 採用した選択肢
---@field since number|nil 要求済みにした時刻(tick)
---@field passed boolean 今の「動き」の制御開始点を過ぎ、時素もたったか
---@field took table<string, boolean>|nil この要求が取った予約資源
---@field missing number|nil 列車を観測できなくなった時刻(tick)

---@class ArcStation
---@field code number
---@field running boolean
---@field resources table<string, string[]>
---@field sequences ArcSequence[]
---@field registration_index table<string, number[]> 登録点から設定順の sequence 番号への索引
---@field sequence_order table<ArcSequence, number> sequence の設定順
---@field seq_tracks table<ArcSequence, table<string, boolean>> 「一連の動き」に関わる軌道回路。列車がこの外に出たら、通り抜けたとみなす
---@field requests table<number|string, ArcRequest> key: 列車の識別子
---@field next_reg number
---@field arriving table<number|string, {dest: string, at: number|nil, seq: ArcSequence, missing: number|nil}> 到着(settle)して入線中の列車。at: 先頭軸が着線に入った時刻(tick。まだ入っていなければ nil)
---@field blocked_dest table<string, boolean> 前回の判定で、着線が空かず待った候補の着線
---@field wait_edges table<number|string, number|string> 待ち一覧に先に入った競合相手に追い越せなかった列車 -> その相手(毎周期作り直す)
---@field alerts string[] 動けなくなる組み合わせの警報(毎周期作り直す)
---@field stalled string[] 要求済みのまま、長く鎖錠されない要求(毎周期作り直す)。「列車の識別子:てこ」

---@class Arc
---@field nt Ntracs
---@field read fun(): {[1]: string, [2]: number}[] 指令値を持つ車軸がいる軌道回路と、その指令値(0は含めない)
---@field parse fun(raw: any): any|nil 軌道回路上の指令値(Axleの値)を分解する。nilを返した指令値は扱わない。戻り値は元の値 raw を持つ(列選の表示に使う)。分解した値の形は設定が決める
---@field train_id fun(arc: any): number|string|nil 列車の識別子。nilを返した指令値は扱わない
---@field tps number 1秒あたりのtick数(Soya Bridge が渡す)
---@field stations table<string, ArcStation>
---@field reservations table<string, {release: {at: string[], b: number|nil}[], owner: number|nil, missing: number|nil}>
---@field takers {name: string, start: string, signal: string, enter: string[], seq: ArcSequence, code: number, locked: boolean}[] 予約資源を取る(take)選択肢
---@field prev table<number|string, table<string, boolean>> 前の周期に列車が現れた軌道回路
---@field clock number 経過時間(tick。process に渡された値の合計)
local Arc = {}

-- 仕様の判断で決めた秒数
local VANISH_SECONDS = 1 -- D4: この秒数続けて観測できなければ、列車は存在しなくなった
local STALL_SECONDS = 10 -- D11: 要求済みのまま、この秒数鎖錠されなければ stalled に載せる

---@param config table res/arc.lua の内容
---@param nt Ntracs
---@param read fun(): {[1]: string, [2]: number}[] 指令値を持つ車軸がいる軌道回路と、その指令値
---@param tps number|nil 1秒あたりのtick数(省略すると60)
---@return Arc
function Arc.new(config, nt, read, tps)
    local self = NtracsObject.create_instance({}, Arc)
    self.nt = nt
    self.read = read
    self.tps = tps or 60
    self.parse = config.parse
    self.train_id = config.train_id
    self.stations = {}
    self.reservations = {}
    self.takers = {}
    self.prev = {}
    self.clock = 0
    for name, r in pairs(config.reservations or {}) do
        self.reservations[name] = { release = r.release or {}, owner = nil, missing = nil }
    end

    for name, st in pairs(config.stations or {}) do
        local station = {
            code = st.code,
            running = st.running ~= false,
            resources = st.resources or {},
            sequences = st.sequences or {},
            registration_index = {},
            sequence_order = {},
            seq_tracks = {},
            requests = {},
            arriving = {},
            next_reg = 1,
            blocked_dest = {},
            wait_edges = {},
            alerts = {},
            stalled = {},
        }
        local resources = station.resources
        for i, seq in ipairs(station.sequences) do
            station.sequence_order[seq] = i
            local points = { table.unpack(seq.match.at) }
            local first = seq.moves[1]
            if first.start_point then table.insert(points, first.start_point) end
            if first.early then table.insert(points, first.early.start_point) end
            for _, id in ipairs(points) do
                local candidates = station.registration_index[id]
                if not candidates then
                    candidates = {}
                    station.registration_index[id] = candidates
                end
                if candidates[#candidates] ~= i then table.insert(candidates, i) end
            end

            -- 「一連の動き」に関わる軌道回路(D3)。設定に書いた軌道回路に、選択肢の進路の軌道回路を Core から加える
            local set = {}
            local function add_all(list)
                for _, t in ipairs(list or {}) do set[t] = true end
            end
            add_all(points)
            for _, move in ipairs(seq.moves) do
                if move.start_point then set[move.start_point] = true end
                if move.early then set[move.early.start_point] = true end
                add_all(move.enter)
                if move.from then add_all(resources[move.from]) end
                for _, opt in ipairs(move.options) do
                    for _, r in ipairs(opt.uses or {}) do add_all(resources[r]) end
                    if opt.dest then add_all(resources[opt.dest]) end
                    local sg = nt:get_signal(opt.signal)
                    ---@diagnostic disable-next-line: invisible
                    local start = sg.startTrack
                    if start then set[start] = true end
                    ---@diagnostic disable-next-line: invisible
                    add_all(sg.signalTrack)
                    ---@diagnostic disable-next-line: invisible
                    add_all(sg.routeLock)
                    if opt.reserve and opt.reserve.mode == "take" and start then
                        table.insert(self.takers, {
                            name = opt.reserve.name, start = start, signal = opt.signal, enter = move.enter,
                            seq = seq, code = st.code, locked = false,
                        })
                    end
                end
            end
            station.seq_tracks[seq] = set
        end
        self.stations[name] = station
    end
    return self
end

---列車の指令値に応じた制御開始点。early に合う列車は、early の制御開始点
---@param move ArcMove
---@param arc any
---@return string|nil
local function start_of(move, arc)
    if move.early and move.early.accept(arc) then return move.early.start_point end
    return move.start_point
end

---「動き」の制御開始点を過ぎ、時素(start_delay)もたったか。制御開始点のない「動き」は常に過ぎている。
---制御開始点を過ぎたかの判定は、すべてここを通す(登録・次の「動き」への移行・先出し・一連の動きの書き換え)
---@param self Arc
---@param req ArcRequest
---@param move ArcMove
---@return boolean
local function start_passed(self, req, move)
    local sp = start_of(move, req.arc)
    if sp == nil then return true end
    local t = req.seen[sp]
    return t ~= nil and self.clock - t >= (move.start_delay or 0) * self.tps
end

---軌道回路の集合 set と、列車が現れた軌道回路 tracks が重なるか
---@param set table<string, boolean>
---@param tracks table<string, boolean>
local function overlaps(set, tracks)
    for t in pairs(tracks) do
        if set[t] then return true end
    end
    return false
end

---要求が取った予約資源を戻す(D5)。正常に完了したときは呼ばない(予約資源は次の駅まで持ち越す)
---@param self Arc
---@param req ArcRequest
local function give_back(self, req)
    for name in pairs(req.took or {}) do
        local r = self.reservations[name]
        if r.owner == req.key then r.owner = nil end
    end
    req.took = nil
end

-- 観測 ---------------------------------------------------------------------

---観測した列車。key: 列車の識別子。
---全軌道回路を走査せず、指令値を持つ車軸(列車ごとに先頭の1本)がいる軌道回路だけを読む。どこにいる列車も見つかる点は全走査と同じ
---@param self Arc
---@return table<number|string, {arc: any, tracks: table<string, boolean>}> tracks: 指令値が現れた軌道回路
---@return table<string, {key: number|string, order: number}> 軌道回路の観測列車
local function observe(self)
    local obs = {}
    for _, r in ipairs(self.read()) do
        local v = self.parse(r[2])
        local key = v and self.train_id(v)
        if key ~= nil then
            local o = obs[key]
            if not o then
                o = { arc = v, tracks = {} }
                obs[key] = o
            end
            o.tracks[r[1]] = true
        end
    end
    -- 元の pairs(obs) の走査順も記録する。複数の列車が資源を塞ぐ場合の警報の選択を保つ。
    local by_track = {}
    local order = 0
    for key, o in pairs(obs) do
        order = order + 1
        local occupant = { key = key, order = order }
        for id in pairs(o.tracks) do by_track[id] = occupant end
    end
    return obs, by_track
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

---列車の「一連の動き」を探す。登録点にいるか、今の「一連の動き」(current)であることが条件
---@param station ArcStation
---@param arc any
---@param tracks table<string, boolean>
---@param current ArcSequence|nil
---@return ArcSequence|nil
local function find_sequence(station, arc, tracks, current)
    local candidates, seen = {}, {}
    local function add(i)
        if i and not seen[i] then
            seen[i] = true
            table.insert(candidates, i)
        end
    end
    add(station.sequence_order[current])
    for id in pairs(tracks) do
        for _, i in ipairs(station.registration_index[id] or {}) do add(i) end
    end
    table.sort(candidates)
    for _, i in ipairs(candidates) do
        local seq = station.sequences[i]
        if seq.match.accept(arc, station.code) then return seq end
    end
    return nil
end

---登録した位置が、その列車の制御開始点を過ぎているか。登録点は制御開始点を含むので、通常は過ぎている。
---速い種別のために一区間手前(early)で登録された、制御開始点が手前でない列車だけは、まだ過ぎていない
---@param seq ArcSequence
---@param o {arc: any, tracks: table<string, boolean>}
local function registered_past_start(seq, o)
    local first = seq.moves[1]
    local sp = start_of(first, o.arc)
    if first.early and sp ~= first.early.start_point and o.tracks[first.early.start_point] and not o.tracks[sp or ""] then
        return false
    end
    return true
end

---制御開始点より下流の登録点で登録された列車は、制御開始点を登録の時点で過ぎたとみなす(時素はそこから数える)
---@param self Arc
---@param req ArcRequest
---@param o {arc: any, tracks: table<string, boolean>}
local function mark_registered(self, req, o)
    local sp = start_of(req.seq.moves[1], o.arc)
    if sp and req.seen[sp] == nil and registered_past_start(req.seq, o) then req.seen[sp] = self.clock end
end

---到着(settle)して入線中の列車を更新する。先頭軸が着線に入った時刻を記録する。
---列車が到着の「一連の動き」の軌道回路の外に出たとき(通り抜けた)と、存在しなくなったときは記録を消す(D2・D3・D4)
---@param self Arc
---@param station ArcStation
---@param obs table
local function update_arriving(self, station, obs)
    for key, a in pairs(station.arriving) do
        local o = obs[key]
        if o == nil then
            a.missing = a.missing or self.clock
            if self.clock - a.missing >= VANISH_SECONDS * self.tps then station.arriving[key] = nil end
        else
            a.missing = nil
            if a.at == nil then
                for _, t in ipairs(station.resources[a.dest]) do
                    if o.tracks[t] then a.at = self.clock end
                end
            end
            if not overlaps(station.seq_tracks[a.seq], o.tracks) then station.arriving[key] = nil end
        end
    end
end

---@param self Arc
---@param station ArcStation
---@param obs table
local function accept(self, station, obs)
    for key, o in pairs(obs) do
        local req = station.requests[key]
        local seq = find_sequence(station, o.arc, o.tracks, req and req.seq)
        if req == nil then
            -- 入線中の列車(先頭軸がまだ着線に入っていない)は、登録しない。
            -- 到着の進路が通る軌道回路に、入換の登録点(北港の NHB13RT など)があるため
            local a = station.arriving[key]
            if seq and not (a and a.at == nil) then
                req = {
                    key = key, seq = seq, idx = 1, reg = station.next_reg, arc = o.arc,
                    promote = false, excluded = false, adopted = nil, opt = nil, passed = false,
                    seen = {}, pre = nil,
                }
                mark_registered(self, req, o)
                station.requests[key] = req
                station.next_reg = station.next_reg + 1
            end
        elseif req.adopted == nil then
            req.arc = o.arc
            -- 最初の「動き」にいるうちは「一連の動き」を書き換えてよい。途中からは書き換えない
            if req.idx == 1 then
                if seq == nil then
                    station.requests[key] = nil
                elseif seq ~= req.seq then
                    -- 指令値が変わった: 新しい指示なので、除外は持ち越さない(D6)。新しい登録点にいるので、制御開始点を過ぎている
                    req.seq = seq
                    req.excluded = false
                    local sp = start_of(seq.moves[1], o.arc)
                    if sp and req.seen[sp] == nil then req.seen[sp] = self.clock end
                end
            end
        end
    end
end

-- 「動き」の更新 -------------------------------------------------------------

---@param self Arc
---@param station ArcStation
---@param obs table
local function update_moves(self, station, obs)
    for key, req in pairs(station.requests) do
        local move = req.seq.moves[req.idx]
        local o = obs[key]

        -- 制御開始点を過ぎたかは、現れた記憶で持つ(短い軌道回路を飛ばしても取りこぼさない)。時素のため、最初に現れた時刻だけを残す
        if o then
            for t in pairs(o.tracks) do
                if req.seen[t] == nil then req.seen[t] = self.clock end
            end
        end
        if req.adopted == nil then req.passed = start_passed(self, req, move) end

        -- 先出しした次の「動き」の鎖錠を確かめる。要求済みのまま鎖錠されないときは待つ(D11)。鎖錠が解けたら取り消されたとみなす
        if req.pre then
            ---@diagnostic disable-next-line: invisible
            local pre_locked = self.nt:get_signal(req.pre.opt.signal):isRouteLocked(self.nt)
            if req.pre.adopted == "requested" then
                if pre_locked then req.pre.adopted = "locked" end
            elseif not pre_locked then
                req.pre = nil
            end
        end

        if req.adopted then
            local entered = false
            for _, t in ipairs(move.enter) do
                if o and o.tracks[t] then entered = true end
            end
            ---@diagnostic disable-next-line: invisible
            local locked = self.nt:get_signal(req.opt.signal):isRouteLocked(self.nt)

            if entered then
                -- 内方に入った: 「動き」は済んだ。要求済みのまま鎖錠を確かめられなかった場合も同じ(D16)
                local nxt = req.seq.moves[req.idx + 1]
                if nxt then
                    req.idx = req.idx + 1
                    if req.pre then
                        -- 先出しした次の「動き」を引き継ぐ
                        req.adopted = req.pre.adopted
                        req.opt = req.pre.opt
                        req.since = req.pre.since
                        req.pre = nil
                    else
                        req.adopted = nil
                        req.opt = nil
                        req.since = nil
                    end
                    req.passed = start_passed(self, req, nxt)
                else
                    -- 正常に完了した。取った予約資源は次の駅まで持ち越すので、戻さない
                    station.requests[key] = nil
                    if req.opt.settle and req.opt.dest then
                        station.arriving[key] = { dest = req.opt.dest, at = nil, seq = req.seq }
                    end
                end
            elseif req.adopted == "requested" then
                -- 鎖錠されるまで待つ。入力は戻さず、候補にも戻さない(D11)
                if locked then req.adopted = "locked" end
            elseif not locked then
                -- 鎖錠された進路が、列車が入る前に解けた: 人が取り消したとみなして除外し、取った予約資源を戻す(D5)
                req.excluded = true
                req.adopted = nil
                req.opt = nil
                req.since = nil
                req.pre = nil
                give_back(self, req)
            end
        end
    end
end

---古い要求を消す(D2・D3・D4)。列車が「一連の動き」の軌道回路の外に現れたら通り抜けた、
---VANISH_SECONDS 続けて観測できなければ存在しなくなった。採用済みの要求も消すが、進路は取り消さない(D11)
---@param self Arc
---@param station ArcStation
---@param obs table
local function expire(self, station, obs)
    for key, req in pairs(station.requests) do
        local o = obs[key]
        local gone
        if o == nil then
            req.missing = req.missing or self.clock
            gone = self.clock - req.missing >= VANISH_SECONDS * self.tps
        else
            req.missing = nil
            gone = not overlaps(station.seq_tracks[req.seq], o.tracks)
        end
        if gone then
            station.requests[key] = nil
            give_back(self, req)
        end
    end
end

-- 予約資源 --------------------------------------------------------------------

---予約資源を放す。持ち主が解放の条件の軌道回路に現れたとき、または持ち主が存在しなくなったとき(D2)
---@param self Arc
---@param obs table
local function release_reservations(self, obs)
    for _, r in pairs(self.reservations) do
        if r.owner == nil then
            r.missing = nil
        else
            local o = obs[r.owner]
            if o then
                r.missing = nil
                for _, rel in ipairs(r.release) do
                    if rel.b == nil or rel.b == o.arc.b then
                        for _, t in ipairs(rel.at) do
                            if o.tracks[t] then r.owner = nil end
                        end
                    end
                end
            else
                r.missing = r.missing or self.clock
                if self.clock - r.missing >= VANISH_SECONDS * self.tps then
                    r.owner = nil
                    r.missing = nil
                end
            end
        end
    end
end

---持ち主のいない予約資源を、観測した事実から取り込む(D7)。
---予約資源を取る(take)選択肢の進路が鎖錠されていて、列車がその始点から内方へ進み、その「一連の動き」に合う指令値を持つとき、その列車を持ち主にする。
---人が手動で開通させた進路でも、予約資源の記録を実際の列車に合わせるため
---@param self Arc
---@param obs table
local function adopt_reservations(self, obs)
    for _, tk in ipairs(self.takers) do
        ---@diagnostic disable-next-line: invisible
        local locked = self.nt:get_signal(tk.signal):isRouteLocked(self.nt)
        local r = self.reservations[tk.name]
        if r.owner == nil and (locked or tk.locked) then
            for key, o in pairs(obs) do
                local p = self.prev[key]
                if r.owner == nil and p and p[tk.start] then
                    for _, t in ipairs(tk.enter) do
                        if o.tracks[t] and tk.seq.match.accept(o.arc, tk.code) then r.owner = key end
                    end
                end
            end
        end
        tk.locked = locked
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
    if opt.accept and not opt.accept(req.arc) then
        return false
    end
    -- このてこの進路がすでに鎖錠されているときは、ほかの列車の進路が使われている最中なので待つ。
    -- 採用前の要求は自分では鎖錠していない。これを見ないと、自分のてこの予約は塞がりに数えないため、
    -- 先行列車が向かっている着線を空きとみなして、同じてこを重ねて採用してしまう
    ---@diagnostic disable-next-line: invisible
    if self.nt:get_signal(opt.signal):isRouteLocked(self.nt) then
        return false
    end
    if opt.dest and (claimed[opt.dest] or resource_busy(self, station, opt.dest, opt.signal)) then
        return false, opt.dest
    end
    if opt.reserve then
        local owner = self.reservations[opt.reserve.name].owner
        if opt.reserve.mode == "hold" then
            if owner ~= req.key then return false end
        elseif opt.reserve.mode == "free" then
            if owner ~= nil then return false end
        elseif owner ~= nil and owner ~= req.key then
            return false
        end
    end
    return true
end

---資源の軌道回路に在線している、ほかの列車の識別子の集合
---@param station ArcStation
---@param by_track table
---@param uses string[]
---@param key number|string 自分(数えない)
---@return table<number|string, boolean>
local function occupants(station, by_track, uses, key)
    local set = {}
    for _, r in ipairs(uses) do
        for _, t in ipairs(station.resources[r]) do
            local other = by_track[t]
            if other and other.key ~= key then set[other.key] = true end
        end
    end
    return set
end

---@param self Arc
---@param station ArcStation
---@param obs table
---@param by_track table
local function judge(self, station, obs, by_track)
    -- 候補を集める
    local cands = {}
    for _, req in pairs(station.requests) do
        if req.adopted ~= nil and req.pre == nil and not req.excluded then
            -- 先出し: 今の「動き」が採用されている間に、次の「動き」を候補にする。次の「動き」の制御開始点を過ぎ、時素もたったことが条件。
            -- 通しの出発は、場内信号を通るときに開いていないと、場内が注意を出す
            local nxt = req.seq.moves[req.idx + 1]
            if nxt and start_of(nxt, req.arc) and start_passed(self, req, nxt) then
                table.insert(cands, { req = req, move = nxt, pre = true })
            end
        elseif req.adopted == nil and not req.excluded and req.passed then
            local move = req.seq.moves[req.idx]
            local ok = true
            -- 制御開始点のない出発の「動き」は、列車がホームの軌道回路に入っていることが条件
            if move.from and not start_of(move, req.arc) then
                ok = false
                local o = obs[req.key]
                if o then
                    for _, t in ipairs(station.resources[move.from]) do
                        if o.tracks[t] then ok = true end
                    end
                end
            end
            -- 到着の直後の「動き」は、着線に入ってから wait 秒たつまで待つ
            local a = station.arriving[req.key]
            if ok and move.wait and a and (a.at == nil or self.clock - a.at < move.wait * self.tps) then
                ok = false
            end
            if ok then table.insert(cands, { req = req, move = move, pre = false }) end
        end
    end

    -- ソート: 繰り上げ、クラス、着線を空ける補正、登録番号
    local function sort_key(c)
        local req, move = c.req, c.move
        local correction = (move.from and station.blocked_dest[move.from]) and 0 or 1
        return req.promote and 0 or 1, move.class, correction, req.reg
    end
    table.sort(cands, function(a, b)
        local a1, a2, a3, a4 = sort_key(a)
        local b1, b2, b3, b4 = sort_key(b)
        if a1 ~= b1 then return a1 < b1 end
        if a2 ~= b2 then return a2 < b2 end
        if a3 ~= b3 then return a3 < b3 end
        return a4 < b4
    end)

    -- 鎖錠中とみなす資源・着線: 採用済みの進路 + この周期で採用した進路
    local busy_now, claimed = {}, {}
    for _, req in pairs(station.requests) do
        for _, o in ipairs({ req.adopted and req.opt or false, req.pre and req.pre.opt or false }) do
            if o then
                for _, r in ipairs(o.uses or {}) do busy_now[r] = true end
                if o.dest then claimed[o.dest] = true end
            end
        end
    end

    local waiting = {}        -- 待ち一覧: 資源名 -> その資源を待っている先頭の列車
    local wait_edges = {}     -- 待ち一覧のせいで追い越せなかった列車 -> 待ち一覧にいる列車
    local blocked_by = {}     -- 在線の列車に資源を塞がれて待ち一覧に入った列車 -> 塞いでいる列車の集合
    local blocked_dest = {}
    for _, c in ipairs(cands) do
        local req, move = c.req, c.move
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
            if conflict then blocked_by[req.key] = occupants(station, by_track, uses, req.key) end
            if chosen.reserve and chosen.reserve.mode == "take" then
                uses = { table.unpack(uses) }
                table.insert(uses, "reserve:" .. chosen.reserve.name)
            end
            if not conflict then
                for _, r in ipairs(uses) do
                    local w = waiting[r]
                    -- 待ち一覧の先頭が、この列車が在線して資源を塞いでいるせいで待っているときは、この列車を止めない。
                    -- 止めると、待っている側が、待っている当の列車を塞ぐ循環になる。実際に資源が重なる場合は、上の判定が止める
                    if w and not (blocked_by[w] and blocked_by[w][req.key]) then
                        conflict = true
                        wait_edges[req.key] = w
                    end
                end
            end

            if conflict then
                for _, r in ipairs(uses) do
                    if not waiting[r] then waiting[r] = req.key end
                end
            else
                self.nt:get_signal(chosen.signal):setInput(true, self.nt)
                if chosen.reserve and chosen.reserve.mode == "take" then
                    self.reservations[chosen.reserve.name].owner = req.key
                    req.took = req.took or {}
                    req.took[chosen.reserve.name] = true
                end
                for _, r in ipairs(chosen.uses or {}) do busy_now[r] = true end
                if chosen.dest then claimed[chosen.dest] = true end
                if c.pre then
                    req.pre = { adopted = "requested", opt = chosen, since = self.clock }
                else
                    req.adopted = "requested"
                    req.opt = chosen
                    req.since = self.clock
                    req.promote = false
                    station.arriving[req.key] = nil
                end
            end
        end
    end
    station.blocked_dest = blocked_dest
    station.wait_edges = wait_edges
end

-- 動けなくなる組み合わせの検知 --------------------------------------------------

---資源を塞ぐ他の列車のうち、元の観測走査で最後に現れたもの。
local function last_occupant(station, by_track, res, key)
    local last
    for _, id in ipairs(station.resources[res]) do
        local other = by_track[id]
        if other and other.key ~= key and (not last or other.order > last.order) then last = other end
    end
    return last and last.key
end

---準備できていない要求が、着線にいる列車の要求を待っているとみなし、待ちの輪を探す
---@param self Arc
---@param station ArcStation
---@param by_track table
local function detect_deadlock(self, station, by_track)
    station.alerts = {}
    local waits_for = {}
    for key, req in pairs(station.requests) do
        if req.adopted == nil and not req.excluded then
            local move = req.seq.moves[req.idx]
            for _, opt in ipairs(move.options) do
                if opt.dest then
                    local other = last_occupant(station, by_track, opt.dest, key)
                    if other ~= nil then waits_for[key] = other end
                end
                -- 使う資源の軌道回路に他の列車がいるときは、その列車を待っているとみなす
                for _, res in ipairs(opt.uses or {}) do
                    local other = last_occupant(station, by_track, res, key)
                    if other ~= nil then waits_for[key] = other end
                end
                -- 予約資源を他の列車が持っているときは、その持ち主を待っているとみなす
                if opt.reserve and opt.reserve.mode ~= "free" then
                    local owner = self.reservations[opt.reserve.name].owner
                    if owner ~= nil and owner ~= key then waits_for[key] = owner end
                end
            end
        end
    end
    -- 待ち一覧に先に入った競合相手に追い越せない列車は、その相手を待っているとみなす
    for key, other in pairs(station.wait_edges) do
        if waits_for[key] == nil and station.requests[key] and station.requests[other] then waits_for[key] = other end
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
            table.sort(ring, function(a, b) return tostring(a) < tostring(b) end)
            local text = table.concat(ring, "<->")
            if not reported[text] then
                reported[text] = true
                table.insert(station.alerts, text)
            end
        end
    end
end

---要求済みのまま STALL_SECONDS 鎖錠されない要求の一覧を作る(D11)
---@param self Arc
---@param station ArcStation
local function detect_stalled(self, station)
    local list = {}
    for key, req in pairs(station.requests) do
        for _, a in ipairs({ req.adopted == "requested" and req or false, req.pre and req.pre.adopted == "requested" and req.pre or false }) do
            if a and self.clock - a.since >= STALL_SECONDS * self.tps then
                table.insert(list, tostring(key) .. ":" .. a.opt.signal)
            end
        end
    end
    table.sort(list)
    station.stalled = list
end

-- 周期処理 -------------------------------------------------------------------

---N-TRACSの演算結果が確定したあと、次の演算の前に呼ぶ
---@param dt number 前回の呼び出しからの経過時間(tick)。呼び出しの間隔は前提にしない(D10)
function Arc:process(dt)
    self.clock = self.clock + dt
    local obs, by_track = observe(self)
    release_reservations(self, obs)
    adopt_reservations(self, obs)
    for _, station in pairs(self.stations) do
        update_arriving(self, station, obs)
        accept(self, station, obs)
        update_moves(self, station, obs)
        expire(self, station, obs)
        if station.running then
            judge(self, station, obs, by_track)
        end
        detect_deadlock(self, station, by_track)
        detect_stalled(self, station)
    end
    local prev = {}
    for key, o in pairs(obs) do prev[key] = o.tracks end
    self.prev = prev
end

---採用されている「動き」(先出しを含む)の信号機ごとに、採用に使った列車の指令値(raw)を返す。列選の表示に使う。
---採用後は指令値を更新しないので、ARC が採用に使った値になる。採用された「動き」が済む(内方に列車が入る)と消える。
---到着の直後で wait の「動き」を待っている要求(認識しているが、まだ発行していない)も、その信号機に載せる
---@return table<string, number> てこ名 -> 指令値
function Arc:adopted_values()
    local values = {}
    for _, station in pairs(self.stations) do
        for _, req in pairs(station.requests) do
            if req.adopted and req.opt then values[req.opt.signal] = req.arc.raw or 0 end
            if req.pre and req.pre.adopted and req.pre.opt then values[req.pre.opt.signal] = req.arc.raw or 0 end
            if req.adopted == nil and not req.excluded and station.arriving[req.key] then
                local move = req.seq.moves[req.idx]
                if move.wait and #move.options == 1 then values[move.options[1].signal] = req.arc.raw or 0 end
            end
        end
    end
    return values
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
---@param key number|string
---@return boolean
function Arc:promote(name, key)
    local req = self.stations[name].requests[key]
    if req then req.promote = true end
    return req ~= nil
end

---除外した要求を戻す
---@param name string
---@param key number|string
---@return boolean
function Arc:restore(name, key)
    local req = self.stations[name].requests[key]
    if req then req.excluded = false end
    return req ~= nil
end

---要求を削除する。その要求が取った予約資源は戻す
---@param name string
---@param key number|string
---@return boolean
function Arc:remove(name, key)
    local req = self.stations[name].requests[key]
    self.stations[name].requests[key] = nil
    if req then give_back(self, req) end
    return req ~= nil
end

---予約資源を手動で放す
---@param name string
function Arc:release(name)
    self.reservations[name].owner = nil
    self.reservations[name].missing = nil
end

return Arc
