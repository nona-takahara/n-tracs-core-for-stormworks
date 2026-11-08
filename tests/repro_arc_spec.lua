-- ARC 仕様書(草案)の判断 D2〜D16 を、本番の設定の上で確かめる。
-- 列車は「指令値を載せる先頭軸の軌道回路(head)」と「在線する軌道回路(body)」で表す。
-- 実機と同じく、指令値は先頭軸の軌道回路にだけ載り、車体の在線は指令値を持たない。
local h = require("tests.harness")
local c = h.new_checker()

local function new_sim()
    local sw = h.new_production_sw()
    require("res.arc")(sw)
    local sim = { sw = sw, trains = {}, others = {} }
    h.set_arc_probe(sw, function(id)
        for _, t in pairs(sim.trains) do
            if t.head == id then return t.raw end
        end
        return 0
    end)
    ---@param body string[]|nil 先頭軸以外に在線する軌道回路
    function sim.set(key, raw, head, body)
        sim.trains[key] = { raw = raw, head = head, body = body or {} }
    end
    function sim.remove(key) sim.trains[key] = nil end
    function sim.block(tracks) -- 指令値を持たない在線(他の列車・車両)
        sim.others = {}
        for _, id in ipairs(tracks) do sim.others[id] = true end
    end
    ---@param dt number|nil ARC に渡す経過 tick(既定 6)
    function sim.step(n, dt)
        for _ = 1, n or 1 do
            local occ = {}
            for id in pairs(sim.others) do occ[id] = true end
            for _, t in pairs(sim.trains) do
                occ[t.head] = true
                for _, id in ipairs(t.body) do occ[id] = true end
            end
            h.tick(sw, occ)
            sw:arc_process(dt or 6)
        end
    end
    function sim.locked(lever) return sw.nt:get_signal(lever):isRouteLocked(sw.nt) end
    function sim.req(station, key) return sw.arc.stations[station].requests[key] end
    function sim.owner(name) return sw.arc.reservations[name].owner end
    function sim.cancel(lever) sw.nt:get_signal(lever):setInput(false, sw.nt) end
    ---n 周期のうち、一度でも鎖錠されたか
    function sim.ever_locked(lever, n, dt)
        local got = false
        for _ = 1, n do
            sim.step(1, dt)
            if sim.locked(lever) then got = true end
        end
        return got
    end
    return sim
end

---指令値: 運行番号 pp、上下 b、行先の駅コード st、番線 pl
local function raw(pp, b, st, pl) return pp * 100000 + b * 10000 + 1000 + st * 10 + (pl or 0) end
local DOWN_THROUGH = raw(10, 2, 5) -- 掘戸町 → 北港 → 潮凪浜方の下り通し

---掘戸町のホームから、ARC が HLT1R を出して掘戸線に入るまで
local function depart_horuto(s, key, v)
    s.set(key, v, "HLT1LT")
    s.step(5)
    s.set(key, v, "HLT_NHB1T", { "HLT1LT" })
    s.step(3)
    s.set(key, v, "HLT_NHB1T")
    s.step(1)
end

-- D2・D3: 古い要求が「HLT_NHB1T を見た」記憶を持ったまま残り、列車が掘戸町のホームにいる間に NHB2R・NHB5R を出す
do
    local s = new_sim()
    -- 先頭軸が掘戸線に出たが、予約資源の持ち主がいないので NHB2R は出ない(北港に要求だけが残る)
    s.set(10, DOWN_THROUGH, "HLT_NHB1T")
    s.step(10)
    c:check("D3 前提: 北港に下り通しの要求がある", s.req("NHB", 10) ~= nil, true)
    -- 列車が掘戸町のホームへ戻る。北港の要求の軌道回路の外なので、通り抜けたとみなして消す
    s.set(10, DOWN_THROUGH, "HLT1LT")
    local early = s.ever_locked("NHB2R", 10) or s.locked("NHB5R")
    c:check("D3: 掘戸町のホームにいる間は NHB2R・NHB5R を出さない", early, false)
    c:check("D3: 掘戸町のホームに戻ったら北港の古い要求は消える", s.req("NHB", 10) == nil, true)
end

-- D6・D3: 取消で除外された要求が、1 編成(列車が観測され続ける)でも残り続けない
do
    local s = new_sim()
    depart_horuto(s, 10, DOWN_THROUGH)
    s.step(3)
    c:check("D6 前提: NHB2R を採用して鎖錠", s.locked("NHB2R"), true)
    s.cancel("NHB2R")
    s.step(400)
    local r = s.req("NHB", 10)
    c:check("D6 前提: 進路を取り消すと除外", r and r.excluded, true)
    -- 手動で 3 番に入れて北港を出ていく
    s.set(10, DOWN_THROUGH, "NHB5LT", { "HLT_NHB1T" }); s.step(3)
    s.set(10, DOWN_THROUGH, "NHB5LT"); s.step(10)
    s.set(10, DOWN_THROUGH, "NHB_TKM5T"); s.step(10)
    c:check("D3: 北港を通り抜けたら除外された要求は消える", s.req("NHB", 10) == nil, true)
    -- 同じ運行番号で、再び掘戸町から下りで来る
    depart_horuto(s, 10, DOWN_THROUGH)
    c:check("D6: 2 回目は NHB2R を採用する", s.ever_locked("NHB2R", 10), true)
end

-- D6: 除外された要求は、指令値が変わって「一連の動き」が書き換わったら解除する
do
    local s = new_sim()
    depart_horuto(s, 10, DOWN_THROUGH)
    s.step(3)
    s.cancel("NHB2R")
    s.step(400)
    c:check("D6 前提: 除外", s.req("NHB", 10) and s.req("NHB", 10).excluded, true)
    s.set(10, raw(10, 2, 3), "HLT_NHB1T") -- 行先を北港に変える(下り終着)
    s.step(3)
    local r = s.req("NHB", 10)
    c:check("D6: 書き換わった一連の動き", r and r.seq.id, "down_terminal")
    c:check("D6: 書き換わったら除外を解除", r and r.excluded, false)
end

-- D7: 掘戸町の HLT1R を ARC より先に手動で開通させても、掘戸線に入った列車を予約資源の持ち主にする
do
    local s = new_sim()
    s.sw.arc:set_running("HLT", false) -- ARC には出させない
    s.set(10, DOWN_THROUGH, "HLT1LT")
    s.sw.nt:get_signal("HLT1R"):setInput(true, s.sw.nt)
    s.step(5)
    c:check("D7 前提: 手動の HLT1R が鎖錠", s.locked("HLT1R"), true)
    c:check("D7 前提: 持ち主はいない", s.owner("HLT"), nil)
    s.set(10, DOWN_THROUGH, "HLT_NHB1T", { "HLT1LT" }); s.step(3)
    s.set(10, DOWN_THROUGH, "HLT_NHB1T"); s.step(1)
    c:check("D7: 信号を越えて掘戸線に入った列車を持ち主にする", s.owner("HLT"), 10)
    c:check("D7: 北港の NHB2R を採用する", s.ever_locked("NHB2R", 10), true)
end

-- D7: 信号を越えずに内方に現れた列車(引き上げ線から 3 番へ行く入換など)は持ち主にしない
do
    local s = new_sim()
    s.set(10, raw(10, 1, 2), "NHB13RT") -- 引き上げ線にいる、掘戸町行きの上り(入換出発)
    s.step(10)
    c:check("D7: 始点を通らずに内方にいる列車は持ち主にしない", s.owner("HLT"), nil)
end

-- D5: 予約資源を取った要求が、人の取消で除外になったら、予約資源を戻す
do
    local s = new_sim()
    s.set(10, DOWN_THROUGH, "HLT1LT")
    s.step(5)
    c:check("D5 前提: HLT1R を採用して予約資源を取る", s.owner("HLT"), 10)
    s.cancel("HLT1R")
    s.step(10)
    local r = s.req("HLT", 10)
    c:check("D5 前提: 除外", r and r.excluded, true)
    c:check("D5: 除外になったら予約資源を戻す", s.owner("HLT"), nil)
end

-- D5: 正常に完了したときは予約資源を戻さない(掘戸町で取り、北港の 3 番まで持ち越す)
do
    local s = new_sim()
    depart_horuto(s, 10, DOWN_THROUGH)
    c:check("D5: 掘戸町の要求が済んでも予約資源は持ち越す", s.owner("HLT"), 10)
end

-- D14: 北港の下り通しの出発(NHB5R)は、HLT_NHB1T に入ってから時素(仮 30 秒)のあとに先出しする
local function delay_case(dt, label)
    local s = new_sim()
    s.set(10, DOWN_THROUGH, "HLT1LT")
    s.step(5, dt)
    s.set(10, DOWN_THROUGH, "HLT_NHB1T", { "HLT1LT" })
    s.step(1, dt)
    s.set(10, DOWN_THROUGH, "HLT_NHB1T")
    local per_s = 60 / dt -- 1 秒あたりの呼び出し回数
    local before = s.ever_locked("NHB5R", math.floor(29 * per_s) - 1, dt)
    c:check("D14" .. label .. ": NHB2R は先に出る", s.locked("NHB2R"), true)
    c:check("D14" .. label .. ": 29 秒までは NHB5R を出さない", before, false)
    c:check("D14" .. label .. ": 31 秒までに NHB5R を出す", s.ever_locked("NHB5R", 2 * per_s, dt), true)
end
delay_case(6, "")
-- D10: 呼び出しの間隔が変わっても、秒は script.lua から受け取った経過 tick で数える
delay_case(12, "(D10: 0.2 秒ごとの呼び出し)")

-- D11: 「要求済み」で鎖錠されなくても候補に戻さず、待ち続ける。10 秒鎖錠されなければ一覧に載せる
do
    local s = new_sim()
    s.set(10, raw(10, 2, 5), "NHB4LT")
    s.step(1)
    c:check("D11 前提: NHB4R を要求", s.req("NHB", 10) and s.req("NHB", 10).adopted, "requested")
    s.block({ "NHB21T" }) -- 入力の直後に別の車両が入り、進路が鎖錠できない
    s.step(30)
    c:check("D11: 鎖錠されなくても要求済みのまま", s.req("NHB", 10) and s.req("NHB", 10).adopted, "requested")
    s.step(80)
    local stalled = s.sw.arc.stations.NHB.stalled or {}
    c:check("D11: 10 秒鎖錠されない要求を一覧に載せる", #stalled, 1)
    s.block({})
    s.step(5)
    c:check("D11: 鎖錠されたら鎖錠済み", s.req("NHB", 10) and s.req("NHB", 10).adopted, "locked")
    c:check("D11: 鎖錠されたら一覧から消える", #(s.sw.arc.stations.NHB.stalled or {}), 0)
end

-- D4: 「存在しなくなった」は 1 秒続けて観測されないとき。採用済みの要求も消す
do
    local s = new_sim()
    s.set(10, raw(10, 2, 5), "NHB4LT")
    s.step(3)
    c:check("D4 前提: NHB4R を採用", s.req("NHB", 10) and s.req("NHB", 10).adopted, "locked")
    s.set(10, raw(10, 2, 5), "NHB4LT")
    s.trains[10].raw = 0 -- 指令値が一瞬どこにも載らない(在線は残る)
    s.step(5)
    s.trains[10].raw = raw(10, 2, 5)
    s.step(1)
    c:check("D4: 0.5 秒の欠落では消さない", s.req("NHB", 10) ~= nil, true)
    s.trains[10].raw = 0
    s.step(15)
    c:check("D4: 1 秒を超えて観測されなければ、採用済みでも消す", s.req("NHB", 10) == nil, true)
end

-- D2: 予約資源の持ち主が存在しなくなったら放す
do
    local s = new_sim()
    s.set(10, DOWN_THROUGH, "HLT1LT")
    s.step(5)
    c:check("D2 前提: 持ち主", s.owner("HLT"), 10)
    s.remove(10)
    s.step(15)
    c:check("D2: 持ち主が存在しなくなったら放す", s.owner("HLT"), nil)
end

-- 観測: 全軌道回路を走査せず車軸の側から引いても(Soya Bridge の arc_readings)、全走査と同じ軌道回路で列車を見つける。
-- 境目のエリアは複数の軌道回路に属するので、その全部で見つかること
do
    local sw = h.new_production_sw()
    require("res.arc")(sw)
    local area_ids = {}
    for _, bridge in pairs(sw.track_bridge) do
        for _, a in ipairs(bridge.area_ids) do area_ids[a] = true end
    end
    ---以前の全走査: 軌道回路ごとに、そのエリアの車軸から指令値を探す
    local function full_scan()
        local found = {}
        for track_id, bridge in pairs(sw.track_bridge) do
            for _, a in ipairs(bridge.area_ids) do
                for _, axle in ipairs(sw.areas[a] and sw.areas[a].axles or {}) do
                    if axle.arc ~= 0 then found[track_id] = true end
                end
            end
        end
        return found
    end
    local mismatches, checked = 0, 0
    for a in pairs(area_ids) do
        if sw.areas[a] then
            local axle = { arc = 1234567, area = a }
            sw.areas[a].axles = { axle }
            sw.vehicle_table = { [1] = { axles = { axle } } }
            local expected = full_scan()
            local got = {}
            for _, r in ipairs(sw.arc.read()) do got[r[1]] = true end
            for t in pairs(expected) do if not got[t] then mismatches = mismatches + 1 end end
            for t in pairs(got) do if not expected[t] then mismatches = mismatches + 1 end end
            sw.areas[a].axles = {}
            checked = checked + 1
        end
    end
    sw.vehicle_table = {}
    c:check("観測: 全エリアで、車軸からの逆引きが全走査と同じ軌道回路を返す(" .. checked .. " エリア)", mismatches, 0)
end

c:report()
