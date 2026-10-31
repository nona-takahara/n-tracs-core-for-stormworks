-- N-TRACS ARC (Automatic Route Control)
-- 駅ごとの設定(res/arc.lua)に従い、列車のARC指令値から進路要求を自動で出す。
-- 設計は docs/arc.md を参照。

-- Stormworksのアドオン環境では setmetatable / assert / error / pcall / select / require(実行時) が使えない。
-- 使える標準関数は docs/stormworks-lua.md を参照。
-- 設定の誤りは、ビルド時(npm run build)に src/n_tracs_arc/arc_check.lua で検出する。実行時には設定を検査せず、何も表示しない。
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
---@field arc any 登録時(採用前は毎tick)のARC指令値
---@field promote boolean 繰り上げの印
---@field excluded boolean 除外の印
---@field seen table<string, boolean> 登録以降に列車が現れた軌道回路(制御開始点を過ぎたかの記憶)
---@field pre {adopted: "requested"|"locked", opt: ArcOption}|nil 先出しした次の「動き」の採用(一連の動きの中で、今の「動き」が済む前に出す)
---@field adopted "requested"|"locked"|nil 採用の印
---@field opt ArcOption|nil 採用した選択肢
---@field passed boolean 今の「動き」の制御開始点を過ぎたか

---@class ArcStation
---@field code number
---@field running boolean
---@field resources table<string, string[]>
---@field sequences ArcSequence[]
---@field requests table<number|string, ArcRequest> key: 列車の識別子
---@field next_reg number
---@field arriving table<number|string, {dest: string, at: number|nil}> 到着(settle)して入線中の列車。at: 先頭軸が着線に入った周期(まだ入っていなければ nil)
---@field blocked_dest table<string, boolean> 前回の判定で、着線が空かず待った候補の着線
---@field wait_edges table<number|string, number|string> 待ち一覧に先に入った競合相手に追い越せなかった列車 -> その相手(毎tick作り直す)
---@field alerts string[] 動けなくなる組み合わせの警報(毎tick作り直す)

---@class Arc
---@field nt Ntracs
---@field probe fun(track_id: string): number 軌道回路上のARC指令値(0は指令値なし)
---@field parse fun(raw: any): any|nil 軌道回路上の指令値(Axleの値)を分解する。nilを返した指令値は扱わない。戻り値は元の値 raw を持つ(列選の表示に使う)。分解した値の形は設定が決める
---@field train_id fun(arc: any): number|string|nil 列車の識別子。nilを返した指令値は扱わない
---@field stations table<string, ArcStation>
---@field reservations table<string, {release: {at: string[], b: number|nil}[], owner: number|nil}>
---@field watch string[] 観測する軌道回路(すべて)
---@field clock number 周期の数(process の呼び出し回数)
local Arc = {}

-- process は 6 tick(0.1 秒)に 1 回呼ばれる。設定の秒を周期に直す
local CYCLES_PER_SECOND = 10

---@param config table res/arc.lua の内容
---@param nt Ntracs
---@param probe fun(track_id: string): number
---@return Arc
function Arc.new(config, nt, probe)
    local self = NtracsObject.create_instance({}, Arc)
    self.nt = nt
    self.probe = probe
    self.parse = config.parse
    self.train_id = config.train_id
    self.stations = {}
    self.reservations = {}
    self.clock = 0
    for name, r in pairs(config.reservations or {}) do
        self.reservations[name] = { release = r.release or {}, owner = nil }
    end

    for name, st in pairs(config.stations or {}) do
        local station = {
            code = st.code,
            running = st.running ~= false,
            resources = st.resources or {},
            sequences = st.sequences or {},
            requests = {},
            arriving = {},
            next_reg = 1,
            blocked_dest = {},
            wait_edges = {},
            alerts = {},
        }
        self.stations[name] = station
    end

    -- 列車がどこにいても追えるよう、すべての軌道回路を観測する。
    -- 設定に出てくる軌道回路だけを見ると、駅の中で観測外の軌道回路を通る間に「列車がいなくなった」と判断してしまう
    self.watch = {}
    ---@diagnostic disable-next-line: invisible
    for id in pairs(nt.track) do table.insert(self.watch, id) end
    table.sort(self.watch)
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

-- 観測 ---------------------------------------------------------------------

---観測した列車。key: 列車の識別子
---@param self Arc
---@return table<number|string, {arc: any, tracks: table<string, boolean>}> tracks: 指令値が現れた軌道回路
local function observe(self)
    local obs = {}
    for _, id in ipairs(self.watch) do
        local v = self.parse(self.probe(id))
        local key = v and self.train_id(v)
        if key ~= nil then
            local o = obs[key]
            if not o then
                o = { arc = v, tracks = {} }
                obs[key] = o
            end
            o.tracks[id] = true
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

---列車の「一連の動き」を探す。登録点にいるか、今の「一連の動き」(current)であることが条件
---@param station ArcStation
---@param arc any
---@param tracks table<string, boolean>
---@param current ArcSequence|nil
---@return ArcSequence|nil
local function find_sequence(station, arc, tracks, current)
    for _, seq in ipairs(station.sequences) do
        local first = seq.moves[1]
        local here = seq == current or tracks[first.start_point or ""] or tracks[first.early and first.early.start_point or ""]
        if not here then
            for _, t in ipairs(seq.match.at) do
                if tracks[t] then here = true end
            end
        end
        if here and seq.match.accept(arc, station.code) then return seq end
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

---到着(settle)して入線中の列車を更新する。先頭軸が着線に入った周期を記録し、列車が観測から消えたら記録を消す
---@param station ArcStation
---@param obs table
---@param clock number
local function update_arriving(station, obs, clock)
    for key, a in pairs(station.arriving) do
        local o = obs[key]
        if o == nil then
            station.arriving[key] = nil
        elseif a.at == nil then
            for _, t in ipairs(station.resources[a.dest]) do
                if o.tracks[t] then a.at = clock end
            end
        end
    end
end

---@param station ArcStation
---@param obs table
local function accept(station, obs)
    for key, o in pairs(obs) do
        local req = station.requests[key]
        local seq = find_sequence(station, o.arc, o.tracks, req and req.seq)
        if req == nil then
            -- 入線中の列車(先頭軸がまだ着線に入っていない)は、登録しない。
            -- 到着の進路が通る軌道回路に、入換の登録点(北港の NHB13RT など)があるため
            local a = station.arriving[key]
            if seq and not (a and a.at == nil) then
                station.requests[key] = {
                    key = key, seq = seq, idx = 1, reg = station.next_reg, arc = o.arc,
                    -- 登録点は制御開始点を含む。制御開始点より下流の登録点で登録された列車は、制御開始点を過ぎている
                    promote = false, excluded = false, adopted = nil, opt = nil, passed = registered_past_start(seq, o),
                    seen = {}, pre = nil,
                }
                station.next_reg = station.next_reg + 1
            end
        elseif req.adopted == nil then
            req.arc = o.arc
            -- 最初の「動き」にいるうちは「一連の動き」を書き換えてよい。途中からは書き換えない
            if req.idx == 1 then
                if seq == nil then
                    station.requests[key] = nil
                elseif seq ~= req.seq then
                    req.seq = seq
                    req.passed = true
                end
            end
        end
    end
    -- ARC指令値が消えた、または列車がいなくなった要求
    for key, req in pairs(station.requests) do
        if obs[key] == nil and (req.adopted == nil or req.excluded) then
            station.requests[key] = nil
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

        if obs[key] then
            for t in pairs(obs[key].tracks) do req.seen[t] = true end
        end

        if req.adopted == nil and obs[key] and not req.passed then
            -- 制御開始点を過ぎたかは、現れた記憶で持つ(短い軌道回路を飛ばしても取りこぼさない)
            local sp = start_of(move, req.arc)
            req.passed = sp == nil or req.seen[sp] ~= nil
        end

        -- 先出しした次の「動き」の鎖錠を確かめる
        if req.pre then
            ---@diagnostic disable-next-line: invisible
            local pre_locked = self.nt:get_signal(req.pre.opt.signal):isRouteLocked(self.nt)
            if req.pre.adopted == "requested" and pre_locked then
                req.pre.adopted = "locked"
            elseif not pre_locked then
                -- 鎖錠されなかった、または解けた: 先出しを取り消す(今の「動き」が済んだあとで、通常どおり判定し直す)
                req.pre = nil
            end
        end

        if req.adopted then
            local entered = false
            for _, t in ipairs(move.enter) do
                if obs[key] and obs[key].tracks[t] then entered = true end
            end
            ---@diagnostic disable-next-line: invisible
            local locked = self.nt:get_signal(req.opt.signal):isRouteLocked(self.nt)

            if req.adopted == "requested" and locked then
                req.adopted = "locked"
            elseif req.adopted == "requested" and not entered then
                -- 次の周期になっても鎖錠されていない: N-TRACSが受け付けなかったとみなして候補に戻す
                req.adopted = nil
                req.opt = nil
                req.pre = nil
            end

            if req.adopted == "locked" then
                if entered then
                    local nxt = req.seq.moves[req.idx + 1]
                    if nxt then
                        req.idx = req.idx + 1
                        if req.pre then
                            -- 先出しした次の「動き」を引き継ぐ
                            req.adopted = req.pre.adopted
                            req.opt = req.pre.opt
                            req.pre = nil
                            req.passed = true
                        else
                            req.adopted = nil
                            req.opt = nil
                            local sp = start_of(nxt, req.arc)
                            req.passed = sp == nil or req.seen[sp] ~= nil
                        end
                    else
                        station.requests[key] = nil
                        if req.opt.settle and req.opt.dest then
                            station.arriving[key] = { dest = req.opt.dest, at = nil }
                        end
                    end
                elseif not locked then
                    req.excluded = true
                    req.adopted = nil
                    req.opt = nil
                    req.pre = nil
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
---@param obs table
---@param uses string[]
---@param key number|string 自分(数えない)
---@return table<number|string, boolean>
local function occupants(station, obs, uses, key)
    local set = {}
    for _, r in ipairs(uses) do
        for _, t in ipairs(station.resources[r]) do
            for other, o in pairs(obs) do
                if other ~= key and o.tracks[t] then set[other] = true end
            end
        end
    end
    return set
end

---@param self Arc
---@param station ArcStation
---@param obs table
local function judge(self, station, obs)
    -- 候補を集める
    local cands = {}
    for _, req in pairs(station.requests) do
        if req.adopted ~= nil and req.pre == nil and not req.excluded then
            -- 先出し: 今の「動き」が採用されている間に、次の「動き」を候補にする。次の「動き」の制御開始点を過ぎていることが条件。
            -- 通しの出発は、場内信号を通るときに開いていないと、場内が注意を出す
            local nxt = req.seq.moves[req.idx + 1]
            local nsp = nxt and start_of(nxt, req.arc)
            if nsp and req.seen[nsp] then
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
            if ok and move.wait and a and (a.at == nil or self.clock - a.at < move.wait * CYCLES_PER_SECOND) then
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

    -- 鎖錠中とみなす資源・着線: 採用済みの進路 + このtickで採用した進路
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
            if conflict then blocked_by[req.key] = occupants(station, obs, uses, req.key) end
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
                end
                for _, r in ipairs(chosen.uses or {}) do busy_now[r] = true end
                if chosen.dest then claimed[chosen.dest] = true end
                if c.pre then
                    req.pre = { adopted = "requested", opt = chosen }
                else
                    req.adopted = "requested"
                    req.opt = chosen
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

---準備できていない要求が、着線にいる列車の要求を待っているとみなし、待ちの輪を探す
---@param self Arc
---@param station ArcStation
---@param obs table
local function detect_deadlock(self, station, obs)
    station.alerts = {}
    local waits_for = {}
    for key, req in pairs(station.requests) do
        if req.adopted == nil and not req.excluded then
            local move = req.seq.moves[req.idx]
            for _, opt in ipairs(move.options) do
                if opt.dest then
                    for other, o in pairs(obs) do
                        if other ~= key then
                            for _, t in ipairs(station.resources[opt.dest]) do
                                if o.tracks[t] then waits_for[key] = other end
                            end
                        end
                    end
                end
                -- 使う資源の軌道回路に他の列車がいるときは、その列車を待っているとみなす
                for _, res in ipairs(opt.uses or {}) do
                    for other, o in pairs(obs) do
                        if other ~= key then
                            for _, t in ipairs(station.resources[res]) do
                                if o.tracks[t] then waits_for[key] = other end
                            end
                        end
                    end
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

-- 周期処理 -------------------------------------------------------------------

---N-TRACSの演算結果が確定したあと、次の演算の前に呼ぶ
function Arc:process()
    self.clock = self.clock + 1
    local obs = observe(self)
    release_reservations(self, obs)
    for _, station in pairs(self.stations) do
        update_arriving(station, obs, self.clock)
        accept(station, obs)
        update_moves(self, station, obs)
        if station.running then
            judge(self, station, obs)
        end
        detect_deadlock(self, station, obs)
    end
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

---要求を削除する
---@param name string
---@param key number|string
---@return boolean
function Arc:remove(name, key)
    local req = self.stations[name].requests[key]
    self.stations[name].requests[key] = nil
    return req ~= nil
end

---予約資源を手動で放す
---@param name string
function Arc:release(name)
    self.reservations[name].owner = nil
end

return Arc
