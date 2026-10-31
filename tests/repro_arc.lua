-- ARC の駅データ(res/arc.lua)を、本番の路線構成の上で動かす検証。
-- 列車は「指令値と在線する軌道回路」で表し、ARC の判定(Arc:process)を script.lua と同じ順序で回す。
local h = require("tests.harness")
local c = h.new_checker()

---@return table sim
local function new_sim()
    local sw = h.new_production_sw()
    require("res.arc")(sw)
    local sim = { sw = sw, trains = {}, others = {} }
    -- 軌道回路ごとの指令値を、列車から引く
    sw.arc.probe = function(id)
        for _, t in pairs(sim.trains) do
            if t.tracks[id] then return t.raw end
        end
        return 0
    end
    function sim.set(key, raw, tracks)
        local set = {}
        for _, id in ipairs(tracks) do set[id] = true end
        sim.trains[key] = { raw = raw, tracks = set }
    end
    function sim.block(tracks) -- ARC指令値を持たない在線(他の列車・車両)
        sim.others = {}
        for _, id in ipairs(tracks) do sim.others[id] = true end
    end
    function sim.step(n)
        for _ = 1, n or 1 do
            local occ = {}
            for id in pairs(sim.others) do occ[id] = true end
            for _, t in pairs(sim.trains) do
                for id in pairs(t.tracks) do occ[id] = true end
            end
            h.tick(sw, occ)
            sw:arc_process()
        end
    end
    function sim.locked(lever) return sw.nt:get_signal(lever):isRouteLocked(sw.nt) end
    function sim.req(station, key) return sw.arc.stations[station].requests[key] end
    function sim.owner(name) return sw.arc.reservations[name].owner end
    return sim
end

---指令値: 運行番号 pp、上下 b、種別 tt、行先の駅コード st、番線 pl
local function raw(pp, b, st, pl) return pp * 100000 + b * 10000 + 1000 + st * 10 + pl end

local function adopted(sim, station, key)
    local r = sim.req(station, key)
    return r and r.opt and r.opt.signal or nil
end

-- 1. 北港: 上り終着(自動)は4番(NHB4L)
do
    local s = new_sim()
    s.set(11, raw(11, 1, 3, 0), { "TKM_NHB1T" })
    s.step(3)
    c:check("北港 上り終着・自動: NHB4Lを採用", adopted(s, "NHB", 11), "NHB4L")
    c:check("北港 上り終着・自動: NHB4Lが鎖錠", s.locked("NHB4L"), true)
    c:check("北港 上り終着・自動: NHB5Lは要求しない", s.locked("NHB5L"), false)
    s.set(11, raw(11, 1, 3, 0), { "NHB13RT" })
    s.step(3)
    c:check("北港 上り終着・自動: 信号の内方(NHB13RT)に入ると要求を消す", s.req("NHB", 11), nil)
end

-- 2. 北港: 4番がふさがっていれば3番(NHB5L)
do
    local s = new_sim()
    s.block({ "NHB4LT" })
    s.set(11, raw(11, 1, 3, 0), { "TKM_NHB1T" })
    s.step(3)
    c:check("北港 上り終着・4番在線: NHB5Lを採用", adopted(s, "NHB", 11), "NHB5L")
    c:check("北港 上り終着・4番在線: 予約資源は取らない", s.owner("HLT"), nil)
end

-- 3. 北港: 4番指定の上り終着は、3番に当てない
do
    local s = new_sim()
    s.block({ "NHB4LT" })
    s.set(11, raw(11, 1, 3, 4), { "TKM_NHB1T" })
    s.step(3)
    c:check("北港 上り終着・4番指定で在線: 何も採用しない", adopted(s, "NHB", 11), nil)
end

-- 4. 掘戸町 → 北港 → 潮凪浜方(下り通し): 掘戸町の出発で予約資源を取り、北港の場内・出発へ
do
    local s = new_sim()
    s.set(12, raw(12, 2, 5, 0), { "HLT1LT" })
    s.step(3)
    c:check("掘戸町 下り出発: HLT1Rを採用", adopted(s, "HLT", 12), "HLT1R")
    c:check("掘戸町 下り出発: 掘戸線予約資源を取る", s.owner("HLT"), 12)
    s.set(12, raw(12, 2, 5, 0), { "HLT_NHB1T" })
    s.step(3)
    c:check("北港 下り通し・場内: NHB2Rを採用", adopted(s, "NHB", 12), "NHB2R")
    s.set(12, raw(12, 2, 5, 0), { "NHB5LT" })
    s.step(3)
    c:check("北港 下り通し・出発: NHB5Rを採用", adopted(s, "NHB", 12), "NHB5R")
    c:check("北港 下り通し: 3番に入って掘戸線予約資源を放す", s.owner("HLT"), nil)
end

-- 5. 北港: 掘戸線予約資源を他の列車が持つとき、3番着の上り終着は待つ(4番がふさがっている場合)
do
    local s = new_sim()
    s.block({ "NHB4LT" })
    s.sw.arc.reservations.HLT.owner = 99
    s.set(11, raw(11, 1, 3, 0), { "TKM_NHB1T" })
    s.step(3)
    c:check("北港 上り終着: 予約資源が他の列車のとき3番は使わない", adopted(s, "NHB", 11), nil)
end

-- 6. 高見が丘: 下り通し(場内 → 出発)
do
    local s = new_sim()
    s.set(21, raw(21, 2, 5, 0), { "NHB_TKM1T" })
    s.step(3)
    c:check("高見が丘 下り通し・場内: TKM1Rを採用", adopted(s, "TKM", 21), "TKM1R")
    s.set(21, raw(21, 2, 5, 0), { "TKM1RT" })
    s.step(3)
    c:check("高見が丘 下り通し・出発: TKM3Rを採用", adopted(s, "TKM", 21), "TKM3R")
end

-- 7. 高見が丘: 上り終着(2番)
do
    local s = new_sim()
    s.set(22, raw(22, 1, 4, 0), { "SGN_TKM1T" })
    s.step(3)
    c:check("高見が丘 上り終着: TKM4Lを採用", adopted(s, "TKM", 22), "TKM4L")
end

-- 8. 高見が丘: 側2 → 2番の入換は、2番に上りの列車がいる間は待つ
do
    local s = new_sim()
    s.block({ "TKM2T" })
    s.set(23, raw(23, 1, 4, 2), { "TKM12RT" })
    s.step(3)
    c:check("高見が丘 側2→2番: 2番在線なら採用しない", adopted(s, "TKM", 23), nil)
    s.block({})
    s.step(3)
    c:check("高見が丘 側2→2番: 2番が空いたらTKM12Lを採用", adopted(s, "TKM", 23), "TKM12L")
end

-- 10. 南江町: 下り終着(自動は1・2番ホーム)と3番指定
do
    local s = new_sim()
    s.set(41, raw(41, 2, 6, 0), { "SNH_NMC1T" })
    s.step(3)
    c:check("南江町 下り終着・自動: NMC1Rを採用", adopted(s, "NMC", 41), "NMC1R")
    local t = new_sim()
    t.set(42, raw(42, 2, 6, 3), { "SNH_NMC1T" })
    t.step(3)
    c:check("南江町 下り終着・3番指定: NMC2Rを採用", adopted(t, "NMC", 42), "NMC2R")
end

-- 11. 動けなくなる組み合わせ: 側1と引き上げ線で互いを待つとき、警報が出る
do
    local s = new_sim()
    s.set(51, raw(51, 2, 4, 9), { "TKM11RT" }) -- 側1 → 引き上げ線
    s.set(52, raw(52, 1, 4, 1), { "TKM15RT" }) -- 引き上げ線 → 側1(→1番)
    s.step(4)
    local alerts = s.sw.arc.stations.TKM.alerts
    c:check("高見が丘 側1⇄引き上げ線: 警報が1件出る", #alerts, 1)
end

-- 12. 行先なし(駅コード0)は終着として扱い、ホームには着けるが次の駅へは出発しない
do
    local s = new_sim()
    s.set(61, raw(61, 1, 0, 0), { "TKM_NHB1T" })
    s.step(3)
    c:check("北港 上り・行先なし: 終着としてNHB4Lを採用", adopted(s, "NHB", 61), "NHB4L")
    local t = new_sim()
    t.set(62, raw(62, 2, 0, 0), { "NHB5LT" })
    t.step(3)
    c:check("北港 3番・行先なし: 下り出発は採用しない", adopted(t, "NHB", 62), nil)
end

-- 13. 同じてこの進路が先行列車のために鎖錠されている間は、後続の要求は待つ
do
    local s = new_sim()
    s.set(71, raw(71, 1, 3, 0), { "TKM_NHB1T" })
    s.step(3)
    c:check("北港 先行列車: NHB4Lを採用", adopted(s, "NHB", 71), "NHB4L")
    s.set(71, raw(71, 1, 3, 0), { "NHB13RT" })
    s.set(72, raw(72, 1, 3, 0), { "TKM_NHB1T" })
    s.step(2)
    c:check("北港 後続列車: 先行列車の進路が鎖錠されている間は採用しない", adopted(s, "NHB", 72), nil)
end

-- 14. 潮凪浜: 通しはなく、行先が先の駅の列車も到着の「動き」で停車する。8番(ループ方面)との入換
do
    local s = new_sim()
    s.set(81, raw(81, 2, 6, 0), { "SGN_SNH1T" })
    s.step(3)
    c:check("潮凪浜 行先が南江町の下り列車: SNH1Rで到着する", adopted(s, "SNH", 81), "SNH1R")
    local t = new_sim()
    t.set(82, raw(82, 1, 5, 8), { "SNH4LT" })
    t.step(3)
    c:check("潮凪浜 2番 → 8番: SNH13Lを採用", adopted(t, "SNH", 82), "SNH13L")
    local u = new_sim()
    u.set(83, raw(83, 2, 5, 2), { "SNH13LT" })
    u.step(3)
    c:check("潮凪浜 8番 → 2番: SNH13Rを採用", adopted(u, "SNH", 83), "SNH13R")
end

-- 15. 「使う資源」は、そのてこの route_lock と一致させる。上り本線の最初の閉塞(NHB13RT)や渡り(NHB23T)に
--     別の列車がいても、下り出発(NHB5R)は待たない。進路が実際に通る単線部分(NHB22AT)にいるときだけ待つ
do
    for _, other in ipairs({ "NHB13RT", "NHB23T" }) do
        local s = new_sim()
        s.block({ other })
        s.set(91, raw(91, 2, 5, 0), { "NHB5LT" })
        s.step(4)
        c:check("北港 3番の下り出発: " .. other .. " に別の列車がいても NHB5R を採用", adopted(s, "NHB", 91), "NHB5R")
    end
    local s = new_sim()
    s.block({ "NHB22AT" })
    s.set(92, raw(92, 2, 5, 0), { "NHB5LT" })
    s.step(4)
    c:check("北港 3番の下り出発: NHB22AT に別の列車がいれば待つ", adopted(s, "NHB", 92), nil)
end

-- 16. 潮凪浜: 番線の桁は行先の駅の番線。先の駅ゆきの列車は、その番線によらず潮凪浜で到着する
do
    local s = new_sim()
    s.set(101, raw(101, 2, 6, 3), { "SGN_SNH1T" }) -- 南江町3番ゆき
    s.step(3)
    c:check("潮凪浜 南江町3番ゆきの下り列車: SNH1Rで到着する", adopted(s, "SNH", 101), "SNH1R")
    local u = new_sim()
    u.set(102, raw(102, 1, 3, 4), { "NMC_SNH1T" }) -- 北港4番ゆき
    u.step(3)
    c:check("潮凪浜 北港4番ゆきの上り列車: SNH4Lで到着する", adopted(u, "SNH", 102), "SNH4L")
    local v = new_sim()
    v.set(103, raw(103, 2, 5, 2), { "SGN_SNH1T" }) -- 潮凪浜止まりで、上り本線(2番)を指定
    v.step(3)
    c:check("潮凪浜 潮凪浜止まりの下り列車が2番を指定: 到着しない", adopted(v, "SNH", 103), nil)
end

-- 17. 掘戸町のホーム(HLT1LT)に列車がいるときは、北港の上り通しは予約資源を取らない(取ると互いに動けなくなる)
do
    local s = new_sim()
    s.block({ "HLT1LT" })
    s.set(111, raw(111, 1, 2, 0), { "TKM_NHB1T" })
    s.step(4)
    c:check("北港 上り通し: 掘戸町ホームに列車がいる間は採用しない", adopted(s, "NHB", 111), nil)
    s.block({})
    s.step(3)
    c:check("北港 上り通し: 掘戸町ホームが空いたら NHB5L を採用", adopted(s, "NHB", 111), "NHB5L")
end

-- 18. 待ち一覧の循環: 2番始発の下り出発(9番を通る)が、9番にいる入換列車を待つとき、
--     入換列車(9番 → 1番。WA と1番だけを使う)を待ち一覧で止めない
do
    local s = new_sim()
    s.set(121, raw(121, 2, 6, 0), { "SNH4LT" }) -- 2番始発の下り出発(9番を通る)
    s.set(122, raw(122, 1, 5, 1), { "SNH3RT" }) -- 9番から1番へ
    s.step(8)
    c:check("潮凪浜 9番の入換列車: 下り出発の待ち一覧に止められず SNH11L を採用", adopted(s, "SNH", 122), "SNH11L")
    c:check("潮凪浜 2番の下り出発: 9番の列車がいる間は採用しない", adopted(s, "SNH", 121), nil)
    c:check("潮凪浜 循環が切れたので警報は出ない", #s.sw.arc.stations.SNH.alerts, 0)
end

-- 19. 互いを待つ組み合わせの警報: 2番の列車は9番へ、9番の列車は2番へ向かう(入れ替えはできない)
do
    local s = new_sim()
    s.set(131, raw(131, 2, 5, 9), { "SNH4LT" }) -- 2番 → 9番
    s.set(132, raw(132, 1, 5, 2), { "SNH3RT" }) -- 9番 → 2番
    s.step(8)
    c:check("潮凪浜 2番と9番の入れ替え: 互いを待つので警報が1件出る", #s.sw.arc.stations.SNH.alerts, 1)
end

-- 20. 北港の構内入換: NHB13RT 発着。NHB13RT にいる列車は NHB11L〜14L だけが出る(NHB4L・NHB5L は出ない)
do
    for _, c1 in ipairs({ { 4, "NHB11L" }, { 3, "NHB12L" }, { 2, "NHB13L" }, { 1, "NHB14L" } }) do
        local s = new_sim()
        s.set(141, raw(141, 1, 3, c1[1]), { "NHB13RT" })
        s.step(4)
        c:check("北港 NHB13RT から" .. c1[1] .. "番へ: " .. c1[2] .. " を採用", adopted(s, "NHB", 141), c1[2])
        c:check("北港 NHB13RT から" .. c1[1] .. "番へ: NHB4L・NHB5L は出ない", s.locked("NHB4L") or s.locked("NHB5L"), false)
    end
    for _, c2 in ipairs({ { "NHB4LT", "NHB11R" }, { "NHB5LT", "NHB12R" }, { "NHB6LT", "NHB13R" }, { "NHB14LT", "NHB14R" } }) do
        local s = new_sim()
        s.set(142, raw(142, 2, 3, 9), { c2[1] })
        s.step(4)
        c:check("北港 " .. c2[1] .. " から NHB13RT へ: " .. c2[2] .. " を採用", adopted(s, "NHB", 142), c2[2])
    end
end

-- 21. 入換の上下の別(b)は、動きの向きと一致する(1が上り=L、2が下り=R)。逆の値の入換は採用しない
do
    local s = new_sim()
    s.set(151, raw(151, 2, 3, 4), { "NHB13RT" }) -- 4番へ向かう入換(L)なのに、下り(2)
    s.step(4)
    c:check("北港 NHB13RT から4番へ: 上下の別が下り(2)だと NHB11L を採用しない", adopted(s, "NHB", 151), nil)
    local u = new_sim()
    u.set(152, raw(152, 1, 3, 9), { "NHB4LT" }) -- NHB13RT 側へ向かう入換(R)なのに、上り(1)
    u.step(4)
    c:check("北港 4番から NHB13RT へ: 上下の別が上り(1)だと NHB11R を採用しない", adopted(u, "NHB", 152), nil)
end

-- 22. 運行番号(pp)が0の列車は扱わない(要求を登録せず、進路も出さない)。運行番号のある列車は、同時にいても通常どおり扱う
do
    local function count(s)
        local n = 0
        for _ in pairs(s.sw.arc.stations["NHB"].requests) do n = n + 1 end
        return n
    end
    local s = new_sim()
    s.set("a", raw(0, 1, 3, 0), { "TKM_NHB1T" })
    s.step(3)
    c:check("運行番号なし 北港 上り終着: 要求を登録しない", count(s), 0)
    c:check("運行番号なし 北港 上り終着: NHB4L・NHB5Lを出さない", s.locked("NHB4L") or s.locked("NHB5L"), false)
    local t = new_sim()
    t.set("b", raw(0, 1, 3, 4), { "NHB13RT" }) -- 入換
    t.step(4)
    c:check("運行番号なし 北港 NHB13RT から4番へ: NHB11L を出さない", t.locked("NHB11L"), false)
    local u = new_sim()
    u.set("c", raw(0, 1, 3, 0), { "TKM_NHB1T" })
    u.set("d", raw(7, 1, 3, 0), { "TKM_NHB2T" })
    u.step(3)
    c:check("運行番号なしが同時にいても、運行番号ありだけ扱う", u.req("NHB", 7) ~= nil and count(u) == 1, true)
end

-- 23. 引き上げ・電留線にいる列車に通常の出発値が付いていたら、ホームへの入換として扱う(「一連の動き」の通しではない)
--     ホームに着いたあとは、同じ値が出発になる。引き上げ線は外からの通しが通らないので、通しの途中の列車は拾わない
do
    local cases = {
        { "北港 NHB13RT(上り)", "NHB", "NHB13RT", raw(161, 1, 2, 0), "NHB12L", "NHB5LT", "NHB2L", "NHB23T" },
        { "高見が丘 TKM15RT(上り)", "TKM", "TKM15RT", raw(162, 1, 2, 0), "TKM15L", nil, nil },
        { "潮凪浜 SNH3RT(上り)", "SNH", "SNH3RT", raw(163, 1, 4, 0), "SNH12L", "SNH4LT", "SNH2L", "SNH21AT" },
        { "潮凪浜 SNH13LT(下り)", "SNH", "SNH13LT", raw(164, 2, 6, 0), "SNH13R", "SNH4LT", "SNH4R", "SNH22T" },
    }
    for _, k in ipairs(cases) do
        local s = new_sim()
        s.set(k[4] // 100000, k[4], { k[3] })
        s.step(4)
        c:check(k[1] .. ": 出発値のままホームへの入換 " .. k[5] .. " を採用", adopted(s, k[2], k[4] // 100000), k[5])
        if k[6] then
            s.set(k[4] // 100000, k[4], { k[8] })
            s.step(3)
            s.set(k[4] // 100000, k[4], { k[6] })
            s.step(6)
            c:check(k[1] .. ": ホームに着いたあと、同じ値で " .. k[7] .. " を採用", adopted(s, k[2], k[4] // 100000), k[7])
        end
    end
    -- 高見が丘は、側2(TKM15L)のあと 2番(TKM12L)、2番から上り出発(TKM2L)の順
    local s = new_sim()
    s.set(162, raw(162, 1, 2, 0), { "TKM15RT" })
    s.step(4)
    s.set(162, raw(162, 1, 2, 0), { "TKM23BT", "TKM12RT" })
    s.step(6)
    c:check("高見が丘 側2に入ると 次は TKM12L を採用", adopted(s, "TKM", 162), "TKM12L")
    s.set(162, raw(162, 1, 2, 0), { "TKM22T" })
    s.step(3)
    s.set(162, raw(162, 1, 2, 0), { "TKM2T" })
    s.step(6)
    c:check("高見が丘 2番に着いたあと、同じ値で TKM2L を採用", adopted(s, "TKM", 162), "TKM2L")
end

-- 24. 列選: 採用されている「動き」の信号機に、採用に使った列車の指令値(raw)が載る。先出しも含む。「動き」が済むと消える
do
    local s = new_sim()
    local v = raw(171, 1, 3, 0)
    s.set(171, v, { "TKM_NHB1T" })
    s.step(3)
    c:check("列選: 採用された NHB4L に指令値が載る", s.sw.arc:adopted_values()["NHB4L"], v)
    s.set(171, v, { "NHB13RT" })
    s.step(3)
    c:check("列選: 内方に入ると消える", s.sw.arc:adopted_values()["NHB4L"], nil)

    -- 北港の下り通し: 掘戸町の出発で予約資源を取ったあと、場内(NHB2R)が採用されている間に、出発(NHB5R)を先出しする
    local t = new_sim()
    local w = raw(172, 2, 5, 0)
    t.set(172, w, { "HLT1LT" })
    t.step(3)
    t.set(172, w, { "HLT_NHB1T" })
    local pre
    for _ = 1, 12 do
        t.step(1)
        local vals = t.sw.arc:adopted_values()
        if vals["NHB2R"] and vals["NHB5R"] and not pre then pre = vals["NHB5R"] end
    end
    c:check("列選: 下り通しの場内(NHB2R)の採用中に、先出しの出発(NHB5R)にも指令値が載る", pre, w)
    c:check("列選: 採用のない信号機は載らない", t.sw.arc:adopted_values()["NHB4R"], nil)
end

-- 25. 制御開始点は、信号現示の測定(110 km/h、ブレーキが間に合う限界の10秒前までに現示が変化していること)で決めた位置。
--     制御開始点の手前では採用せず、制御開始点で採用する
do
    local function value(pp, dir, cls, st) return pp * 100000 + dir * 10000 + cls * 1000 + st * 10 end
    local cases = {
        { "高見が丘 下り通し", "TKM", "NHB_TKM3T", "NHB_TKM4T", 2, 5 },
        { "北港 上り終着", "NHB", "TKM_NHB3T", "TKM_NHB4T", 1, 3 },
    }
    for _, k in ipairs(cases) do
        for _, cls in ipairs({ 1 }) do
            local s = new_sim()
            local v = value(181 + cls, k[5], cls, k[6])
            s.set(181 + cls, v, { k[4] })
            s.step(4)
            c:check(k[1] .. " 種別" .. cls .. ": 制御開始点の手前(" .. k[4] .. ")では採用しない", adopted(s, k[2], 181 + cls) ~= nil, false)
            s.set(181 + cls, v, { k[3] })
            s.step(4)
            c:check(k[1] .. " 種別" .. cls .. ": 制御開始点(" .. k[3] .. ")で採用する", adopted(s, k[2], 181 + cls) ~= nil, true)
        end
    end
end

-- 26. 到着の直後の入換: 着線に先頭軸が入ってから wait 秒(潮凪浜の下りは60秒=600周期)たつまで採用しない
do
    local s = new_sim()
    s.set(261, raw(261, 2, 5, 9), { "SGN_SNH1T" })
    s.step(3)
    c:check("潮凪浜 下り到着(9指定): 到着はSNH1R", adopted(s, "SNH", 261), "SNH1R")
    s.set(261, raw(261, 2, 5, 9), { "SNH1RT" })
    s.step(3)
    c:check("潮凪浜 到着の直後: 入換は待つ(採用しない)", adopted(s, "SNH", 261), nil)
    c:check("潮凪浜 待ちの間も、入換の信号機(SNH11R)に指令値を載せる", s.sw.arc:adopted_values()["SNH11R"], raw(261, 2, 5, 9))
    s.step(590)
    c:check("潮凪浜 到着の59秒後: まだ待つ", adopted(s, "SNH", 261), nil)
    s.step(30)
    c:check("潮凪浜 到着の60秒後: 入換SNH11Rを採用", adopted(s, "SNH", 261), "SNH11R")
    c:check("潮凪浜 採用後も指令値を載せ続ける", s.sw.arc:adopted_values()["SNH11R"], raw(261, 2, 5, 9))
    s.set(261, raw(261, 2, 5, 9), { "SNH21AT" })
    s.step(6)
    c:check("潮凪浜 内方に列車が入ると指令値は消える", s.sw.arc:adopted_values()["SNH11R"], nil)
end

-- 27. 到着の進路が通る入換の登録点(北港のNHB13RT)では、入線中の列車を入換として登録しない
do
    local s = new_sim()
    s.set(271, raw(271, 1, 3, 4), { "TKM_NHB1T" })
    s.step(3)
    s.set(271, raw(271, 1, 3, 4), { "NHB13RT" })
    s.step(3)
    c:check("北港 上り到着(4番): NHB13RTでは入換を登録しない", s.req("NHB", 271), nil)
    s.set(271, raw(271, 1, 3, 4), { "NHB4LT" })
    s.step(3)
    c:check("北港 4番に入ったあとも、上り終着なので要求なし", s.req("NHB", 271), nil)
end

-- 28. 到着の記録がない列車(最初からその場所にいる)は、待たずに入換が採用される
do
    local s = new_sim()
    s.set(281, raw(281, 2, 5, 9), { "SNH1RT" })
    s.step(3)
    c:check("潮凪浜 1番にいた列車の入換は待たない", adopted(s, "SNH", 281), "SNH11R")
    local t = new_sim()
    t.set(282, raw(282, 2, 5, 9), { "SNH1RT" })
    t.step(1)
    c:check("潮凪浜 到着の記録がない列車は、待ちの値を載せない(採用の値だけ)", t.sw.arc:adopted_values()["SNH11R"] ~= nil and adopted(t, "SNH", 282) == nil, false)
end

c:report()
