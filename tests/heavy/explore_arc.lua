-- 列車を「2軸の車両」として本番の路線で動かし、ARCが動けなくなる組み合わせ(デッドロック)を探す。
-- 実行(リポジトリルートから、駅ごとに数分かかる): lua tests/heavy/explore_arc.lua [駅=NHB|TKM|SNH|NMC] [軸距m=15] [速度m/周期=4] [本数 [件数=300 [seed]]]
-- 前提は docs/arc.md の「シミュレーションの前提」を参照。pnpm test には含めない。速度の仮定(既定 4 m/周期)は、制御開始点の測定(tests/heavy/measure_start_points.lua、110 km/h)と揃っていない(tests/README.md の「ARC のシミュレーション」を参照)。
-- 指令値は先頭の軸がいる軌道回路にだけ載る(実機では先頭車の前側の検知ブロックのダイアルにだけ送る)。
--
-- 欠陥の基準: すべての列車が止まらず動こうとしているのに、ARCのせいで固まること。
--   1本が動かず固まっていて、ほかの列車がそれに塞がれるのは正常(その列車がどくまでロックされる)。
--   そのため、ここでは協調する列車(進めるなら必ず進む)だけで動かし、固まったものを全部拾う。
--   警報あり: ARCが検知して指令に知らせる(手動介入で解く)。警報なし: ARCが黙って固まる(直す対象)
package.path = "./?.lua;" .. package.path
local h = require("tests.harness")
local LEN = require("tests.heavy.track_lengths")

local SPEED = 4      -- 1周期(6tick)に進む距離[m]
local MARGIN = 2     -- 停止位置: 進路の終端の手前[m]
-- 固まったとみなすまでの周期数。res/arc.lua の wait の最大(60 秒 = 600 周期)より長くする。短いと正常な待ちを固まったと誤判定する
local IDLE = 700
local function raw(pp, b, st, pl) return pp * 100000 + b * 10000 + 1000 + st * 10 + pl end

local M = {}

-- 列車の型 -------------------------------------------------------------------
-- start: 最初にいる軌道回路。init: 最初からそこにいる(あとから現れない)。
-- phases[i]: そのときの指令値(b: 上下、st: 行先の駅コード、pl: 番線)と、着く軌道回路(goal)。
--   dwell: 着いてから次の段階までの周期数。exit: 着いたら消える。jump: 掘戸町での手動の折り返し
local function T(name, start, init, phases) return { name = name, start = start, init = init, phases = phases } end
local function P(b, st, pl, goal, dwell, extra)
  local g = {}
  for _, t in ipairs(goal) do g[t] = true end
  local p = { b = b, st = st, pl = pl, goal = g, dwell = dwell }
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end
local RETURN = P(2, 3, 0, { "NHB5LT" }, 0, { exit = true }) -- 掘戸町から北港止まりで戻る

M.TYPES = {
  -- 北港・掘戸町 -----------------------------------------------------------
  D_thru = T("下り通し", "HLT1LT", true, { P(2, 5, 0, { "NHB5RT" }, 0, { exit = true }) }),
  D_term = T("下り終着→3番折り返し上り→掘戸町", "HLT1LT", true, {
    P(2, 3, 0, { "NHB5LT" }, 3), P(1, 2, 0, { "HLT_NHB1T" }, 2, { jump = "HLT1LT" }), RETURN }),
  D_term_dn = T("下り終着→3番→下り出発", "HLT1LT", true, {
    P(2, 3, 0, { "NHB5LT" }, 3), P(2, 5, 0, { "NHB5RT" }, 0, { exit = true }) }),
  U_thru = T("上り通し(掘戸町で折り返し)", "TKM_NHB1T", false, {
    P(1, 2, 0, { "HLT_NHB1T" }, 2, { jump = "HLT1LT" }), RETURN }),
  U_term = T("上り終着(自動)→折り返し下り", "TKM_NHB1T", false, {
    P(1, 3, 0, { "NHB5LT", "NHB4LT" }, 3), P(2, 5, 0, { "NHB5RT" }, 0, { exit = true }) }),
  U_term3 = T("上り終着(3番指定)→折り返し下り", "TKM_NHB1T", false, {
    P(1, 3, 3, { "NHB5LT" }, 3), P(2, 5, 0, { "NHB5RT" }, 0, { exit = true }) }),
  S3_up = T("3番始発 上り(掘戸町で折り返し)", "NHB5LT", true, {
    P(1, 2, 0, { "HLT_NHB1T" }, 2, { jump = "HLT1LT" }), RETURN }),
  S3_down = T("3番始発 下り", "NHB5LT", true, { P(2, 5, 0, { "NHB5RT" }, 0, { exit = true }) }),

  -- 北港の構内入換(NHB13RT 発着。外からの進入は NHB4L・NHB5L を使うので、ここでは使わない) -------------
  NH_y4 = T("北港 構内入換 NHB13RT→4番→NHB13RT", "NHB13RT", true, { P(1, 3, 4, { "NHB4LT" }, 2), P(2, 3, 9, { "NHB13RT" }, 0, { exit = true }) }),
  NH_y3 = T("北港 構内入換 NHB13RT→3番→NHB13RT", "NHB13RT", true, { P(1, 3, 3, { "NHB5LT" }, 2), P(2, 3, 9, { "NHB13RT" }, 0, { exit = true }) }),
  NH_y2 = T("北港 構内入換 NHB13RT→2番→NHB13RT", "NHB13RT", true, { P(1, 3, 2, { "NHB6LT" }, 2), P(2, 3, 9, { "NHB13RT" }, 0, { exit = true }) }),
  NH_y1 = T("北港 構内入換 NHB13RT→1番→NHB13RT", "NHB13RT", true, { P(1, 3, 1, { "NHB14LT" }, 2), P(2, 3, 9, { "NHB13RT" }, 0, { exit = true }) }),
  NH_o4 = T("北港 構内入換 4番→NHB13RT", "NHB4LT", true, { P(2, 3, 9, { "NHB13RT" }, 0, { exit = true }) }),
  NH_o2 = T("北港 構内入換 2番→NHB13RT", "NHB6LT", true, { P(2, 3, 9, { "NHB13RT" }, 0, { exit = true }) }),
  NH_o1 = T("北港 構内入換 1番→NHB13RT", "NHB14LT", true, { P(2, 3, 9, { "NHB13RT" }, 0, { exit = true }) }),

  -- 高見が丘 -----------------------------------------------------------------
  TK_dn_thru = T("高見が丘 下り通し", "NHB_TKM1T", false, { P(2, 5, 0, { "TKM3RT" }, 0, { exit = true }) }),
  TK_up_thru = T("高見が丘 上り通し", "SGN_TKM1T", false, { P(1, 3, 0, { "TKM2LT" }, 0, { exit = true }) }),
  TK_dn_term_dep = T("高見が丘 下り終着(1番)→下り出発", "NHB_TKM1T", false, {
    P(2, 4, 0, { "TKM1RT" }, 2), P(2, 5, 0, { "TKM3RT" }, 0, { exit = true }) }),
  TK_up_term_dep = T("高見が丘 上り終着(2番)→上り出発", "SGN_TKM1T", false, {
    P(1, 4, 0, { "TKM2T" }, 2), P(1, 3, 0, { "TKM2LT" }, 0, { exit = true }) }),
  -- 下り終着してから、北港方向へ折り返す(1番→側1→引き上げ線→側2→2番→上り出発)
  TK_dn_turn = T("高見が丘 下り終着→北港方向へ折り返し", "NHB_TKM1T", false, {
    P(2, 4, 0, { "TKM1RT" }, 2), P(2, 4, 9, { "TKM11RT" }, 1), P(2, 4, 9, { "TKM15RT" }, 1),
    P(1, 4, 2, { "TKM12RT" }, 1), P(1, 4, 2, { "TKM2T" }, 2), P(1, 3, 0, { "TKM2LT" }, 0, { exit = true }) }),
  -- 上り終着してから、潮凪浜方向へ折り返す(2番→側2→引き上げ線→側1→1番→下り出発)
  TK_up_turn = T("高見が丘 上り終着→潮凪浜方向へ折り返し", "SGN_TKM1T", false, {
    P(1, 4, 0, { "TKM2T" }, 2), P(2, 4, 9, { "TKM12RT" }, 1), P(2, 4, 9, { "TKM15RT" }, 1),
    P(1, 4, 1, { "TKM11RT" }, 1), P(1, 4, 1, { "TKM1RT" }, 2), P(2, 5, 0, { "TKM3RT" }, 0, { exit = true }) }),
  TK_p1_start = T("高見が丘 1番始発 下り", "TKM1RT", true, { P(2, 5, 0, { "TKM3RT" }, 0, { exit = true }) }),
  TK_p2_start = T("高見が丘 2番始発 上り", "TKM2T", true, { P(1, 3, 0, { "TKM2LT" }, 0, { exit = true }) }),
  TK_yard_start = T("高見が丘 引き上げ線から2番へ→上り出発", "TKM15RT", true, {
    P(1, 4, 2, { "TKM12RT" }, 1), P(1, 4, 2, { "TKM2T" }, 2), P(1, 3, 0, { "TKM2LT" }, 0, { exit = true }) }),
  TK_s1_start = T("高見が丘 側1から1番へ→下り出発", "TKM11RT", true, {
    P(1, 4, 1, { "TKM1RT" }, 2), P(2, 5, 0, { "TKM3RT" }, 0, { exit = true }) }),

  -- 潮凪浜 ---------------------------------------------------------------------
  SN_dn_arr_dep = T("潮凪浜 下り到着(南江町ゆき)→出発", "SGN_SNH1T", false, {
    P(2, 6, 0, { "SNH1RT" }, 2), P(2, 6, 0, { "SNH_NMC4T" }, 0, { exit = true }) }),
  SN_up_arr_dep = T("潮凪浜 上り到着(北港ゆき)→出発", "NMC_SNH1T", false, {
    P(1, 3, 0, { "SNH4LT" }, 2), P(1, 3, 0, { "SNH2LT" }, 0, { exit = true }) }),
  -- 下り終着して、9番を通って2番へ折り返し、上り出発
  SN_dn_turn = T("潮凪浜 下り終着→9番→2番→上り出発", "SGN_SNH1T", false, {
    P(2, 5, 0, { "SNH1RT" }, 2), P(2, 5, 9, { "SNH3RT" }, 1), P(1, 5, 2, { "SNH4LT" }, 2),
    P(1, 3, 0, { "SNH2LT" }, 0, { exit = true }) }),
  -- 上り終着して、9番を通って1番へ折り返し、下り出発
  SN_up_turn = T("潮凪浜 上り終着→9番→1番→下り出発", "NMC_SNH1T", false, {
    P(1, 5, 0, { "SNH4LT" }, 2), P(2, 5, 9, { "SNH3RT" }, 1), P(1, 5, 1, { "SNH1RT" }, 2),
    P(2, 6, 0, { "SNH_NMC4T" }, 0, { exit = true }) }),
  SN_loop = T("潮凪浜 上り終着→8番(ループ方面)→2番→上り出発", "NMC_SNH1T", false, {
    P(1, 5, 0, { "SNH4LT" }, 1), P(1, 5, 8, { "SNH13LT" }, 1), P(2, 5, 2, { "SNH4LT" }, 1),
    P(1, 3, 0, { "SNH2LT" }, 0, { exit = true }) }),
  SN_p1_start = T("潮凪浜 1番始発 下り", "SNH1RT", true, { P(2, 6, 0, { "SNH_NMC4T" }, 0, { exit = true }) }),
  SN_p2_start = T("潮凪浜 2番始発 下り(9番経由)", "SNH4LT", true, { P(2, 6, 0, { "SNH_NMC4T" }, 0, { exit = true }) }),
  SN_p2_up = T("潮凪浜 2番始発 上り", "SNH4LT", true, { P(1, 3, 0, { "SNH2LT" }, 0, { exit = true }) }),
  SN_yard_start = T("潮凪浜 9番から1番へ→下り出発", "SNH3RT", true, {
    P(1, 5, 1, { "SNH1RT" }, 1), P(2, 6, 0, { "SNH_NMC4T" }, 0, { exit = true }) }),

  -- 南江町 ---------------------------------------------------------------------
  NM_term = T("南江町 下り終着(自動)→上り出発", "SNH_NMC1T", false, {
    P(2, 6, 0, { "NMC1RT", "NMC2RT" }, 2), P(1, 3, 0, { "NMC_SNH4T" }, 0, { exit = true }) }),
  NM_term3 = T("南江町 下り終着(3番指定)→上り出発", "SNH_NMC1T", false, {
    P(2, 6, 3, { "NMC2RT" }, 2), P(1, 3, 0, { "NMC_SNH4T" }, 0, { exit = true }) }),
  NM_p12_start = T("南江町 1・2番始発 上り", "NMC1RT", true, { P(1, 3, 0, { "NMC_SNH4T" }, 0, { exit = true }) }),
  NM_p3_start = T("南江町 3番始発 上り", "NMC2RT", true, { P(1, 3, 0, { "NMC_SNH4T" }, 0, { exit = true }) }),
}

-- 場内の手前の閉塞(自動信号が守る軌道回路)。列車は制御開始点より上流から、この区間を一定の速度で走って入ってくる
local APPROACH = {
  TKM_NHB1T = { "TKM_NHB4T", "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T" },
  NHB_TKM1T = { "NHB_TKM4T", "NHB_TKM3T", "NHB_TKM2T", "NHB_TKM1T" },
  SGN_TKM1T = { "SGN_TKM4T", "SGN_TKM3T", "SGN_TKM2T", "SGN_TKM1T" },
  SGN_SNH1T = { "SGN_SNH4T", "SGN_SNH3T", "SGN_SNH2T", "SGN_SNH1T" },
  NMC_SNH1T = { "NMC_SNH4T", "NMC_SNH3T", "NMC_SNH2T", "NMC_SNH1T" },
  SNH_NMC1T = { "SNH_NMC4T", "SNH_NMC3T", "SNH_NMC2T", "SNH_NMC1T" },
}
for _, ty in pairs(M.TYPES) do
  if not ty.init and APPROACH[ty.start] then
    ty.approach = APPROACH[ty.start]
    ty.start = ty.approach[1]
  end
end

M.STATIONS = {
  NHB = { order = { "D_thru", "D_term", "D_term_dn", "U_thru", "U_term", "U_term3", "S3_up", "S3_down",
                    "NH_y4", "NH_y3", "NH_y2", "NH_y1", "NH_o4", "NH_o2", "NH_o1" },
          probes = { "U_thru", "D_thru", "U_term" } },
  TKM = { order = { "TK_dn_thru", "TK_up_thru", "TK_dn_term_dep", "TK_up_term_dep", "TK_dn_turn", "TK_up_turn",
                    "TK_p1_start", "TK_p2_start", "TK_yard_start", "TK_s1_start" },
          probes = { "TK_dn_thru", "TK_up_thru" } },
  SNH = { order = { "SN_dn_arr_dep", "SN_up_arr_dep", "SN_dn_turn", "SN_up_turn", "SN_loop",
                    "SN_p1_start", "SN_p2_start", "SN_p2_up", "SN_yard_start" },
          probes = { "SN_dn_arr_dep", "SN_up_arr_dep" } },
  NMC = { order = { "NM_term", "NM_term3", "NM_p12_start", "NM_p3_start" },
          probes = { "NM_term", "NM_p12_start" } },
}

-- 列車の位置 -----------------------------------------------------------------
local function new_hist(track) return { { t = track, len = LEN[track] } } end
local function total(hist) local s = 0 for _, g in ipairs(hist) do s = s + g.len end return s end
local function track_at(hist, s)
  local acc = 0
  for _, g in ipairs(hist) do
    if s < acc + g.len then return g.t, acc end
    acc = acc + g.len
  end
  return hist[#hist].t, acc - hist[#hist].len
end
local function index_at(hist, s)
  local acc = 0
  for i, g in ipairs(hist) do
    if s < acc + g.len then return i end
    acc = acc + g.len
  end
  return #hist
end
---先頭軸と後尾軸がいる軌道回路
local function occ_set(t)
  return (track_at(t.hist, t.sf)), (track_at(t.hist, math.max(0, t.sf - t.d)))
end

---総当たりで1つの組み合わせを動かす。
---@return string kind ok | stuck(動けなくなった) | timeout
---@return table info
function M.run(types, offsets, opts)
  opts = opts or {}
  local d = opts.d or 15
  local sw = h.new_production_sw()
  require("res.arc")(sw)
  if opts.patch then opts.patch(sw) end
  local trains = {}
  local function add(ty, at, id)
    local def = M.TYPES[ty]
    -- 最初からホームなどにいる型は、すぐ現れ、holdの周期まで指令値を出さずに待つ(到着する列車と出会う時機を変えるため)
    trains[#trains + 1] = { id = id or (10 + #trains + 1), ty = def, phase = 1, d = d, at = def.init and 1 or at,
      hold = def.init and at or nil, dwell = 0, state = "absent" }
    return trains[#trains]
  end
  for i, ty in ipairs(types) do add(ty, offsets[i]) end

  local function occupied_by_other(track, me)
    for _, t in ipairs(trains) do
      if t ~= me and t.state ~= "absent" and t.state ~= "done" then
        local f, r = occ_set(t)
        if f == track or r == track then return true end
      end
    end
    return false
  end
  sw.arc.probe = function(id)
    for _, t in ipairs(trains) do
      if t.state ~= "absent" and t.state ~= "done" and not t.silent and (occ_set(t)) == id then
        local p = t.ty.phases[t.phase]
        return raw(os.getenv("NOPP") and 0 or t.id, p.b, p.st, p.pl or 0)
      end
    end
    return 0
  end

  local idle, trace = 0, {}
  local probes = nil
  local function note(step, t, what) trace[#trace + 1] = string.format("%d:T%d %s", step, t.id, what) end
  local function summary()
    local where = {}
    for _, t in ipairs(trains) do
      if not t.probe then
        local f = t.hist and track_at(t.hist, t.sf) or "-"
        where[#where + 1] = string.format("T%d(%s)@%s[%s]", t.id, t.ty.name, f, t.state)
      end
    end
    return table.concat(where, " ")
  end
  local function alert_count()
    local n = 0
    for _, st in pairs(sw.arc.stations) do n = n + #st.alerts end
    return n
  end

  for step = 1, opts.max_steps or 6000 do
    local progress = false
    for _, t in ipairs(trains) do
      local p = t.ty.phases[t.phase]
      t.silent = t.hold ~= nil and step < t.hold
      if t.silent then
        -- 待機中: 指令値を出さず、動かない
        if t.state == "absent" and not occupied_by_other(t.ty.start, t) then
          t.hist = new_hist(t.ty.start); t.sf = LEN[t.ty.start] - MARGIN; t.state = "wait"
        end
        progress = true
      elseif t.state == "absent" then
        if step >= t.at and not occupied_by_other(t.ty.start, t) then
          if t.ty.approach then
            -- 進入の区間を一定の速度で走って入ってくる(信号には従わない)
            t.hist = {}
            for _, x in ipairs(t.ty.approach) do t.hist[#t.hist + 1] = { t = x, len = LEN[x] } end
            t.sf = t.d + 5
            t.target = total(t.hist) - MARGIN
            t.state = "run"
          else
            t.hist = new_hist(t.ty.start)
            t.sf = LEN[t.ty.start] - MARGIN
            t.state = "wait"
          end
          progress = true
        end
      elseif t.state == "wait" then
        local f = track_at(t.hist, t.sf)
        if p.goal[f] and t.at_goal then
          if t.dwell < (p.dwell or 0) then t.dwell = t.dwell + 1; progress = true
          elseif p.exit then t.state = "done"; progress = true; note(step, t, "完了")
          elseif p.jump then
            if not occupied_by_other(p.jump, t) then
              t.hist = new_hist(p.jump); t.sf = LEN[p.jump] - MARGIN
              t.phase = t.phase + 1; t.dwell = 0; t.at_goal = false; progress = true
              note(step, t, "掘戸町で折り返し")
            end
          else
            t.phase = t.phase + 1; t.dwell = 0; t.at_goal = false; progress = true
          end
        else
          -- 運転士は信号現示に従う: 先頭軸のいる軌道回路を始点とする信号が、進行系の現示を出していれば進む
          local found
          for name, sg in pairs(sw.nt.signal) do
            if sg.startTrack == f and ((sg.aspect or 0) > 0 or sg.HR) then found = name; break end
          end
          if found then
            local sg = sw.nt:get_signal(found)
            local route = {}
            for _, x in ipairs(sg.signalTrack) do if x ~= f then route[#route + 1] = x end end
            -- 折り返し: 進路の最初の軌道回路が、いま来た軌道回路(先頭軸の1つ手前)と同じなら、向きを変える。
            -- 向きは進路てこの direction ではなく、配線のつながりで決める
            local fi = index_at(t.hist, t.sf)
            if fi > 1 and route[1] == t.hist[fi - 1].t then
              local tot = total(t.hist)
              local nsf = tot - math.max(0, t.sf - t.d)
              if nsf >= tot then nsf = tot - 0.1 end
              local rev = {}
              for i = #t.hist, 1, -1 do rev[#rev + 1] = t.hist[i] end
              local idx = index_at(rev, nsf)
              local nh = {}
              for i = 1, idx do nh[#nh + 1] = rev[i] end
              t.hist, t.sf = nh, nsf
              note(step, t, "折り返し@" .. f)
            end
            for _, x in ipairs(route) do t.hist[#t.hist + 1] = { t = x, len = LEN[x] } end
            t.target = total(t.hist) - MARGIN
            t.state = "run"; progress = true
            note(step, t, found)
          end
        end
      elseif t.state == "run" then
        local ns = math.min(t.sf + (opts.speed or SPEED), t.target)
        local cur, nxt = index_at(t.hist, t.sf), index_at(t.hist, ns)
        if nxt ~= cur and occupied_by_other(t.hist[nxt].t, t) then ns = t.sf end
        if ns ~= t.sf then t.sf = ns; progress = true end
        if t.sf >= t.target - 1e-6 then t.state = "wait"; t.at_goal = true; progress = true end
      end
    end

    local occ, alldone = {}, true
    for _, t in ipairs(trains) do
      if t.state ~= "done" then alldone = false end
      if t.state ~= "absent" and t.state ~= "done" then
        local f, r = occ_set(t); occ[f] = true; occ[r] = true
      end
    end
    h.tick(sw, occ)
    sw:arc_process()
    if alldone then return "ok", { step = step, trace = trace } end
    if progress then idle = 0 else idle = idle + 1 end

    -- 動けなくなった局面を分類する: 通しの列車を1本ずつ流す(同時に流すと、始点の軌道回路を取り合って互いを邪魔する)
    local function start_next_probe()
      probes.i = probes.i + 1
      local name = opts.station and M.STATIONS[opts.station].probes[probes.i]
      if not name then return false end
      local pt = add(name, step + 1, 90 + probes.i)
      pt.probe = true
      probes.cur = pt
      idle = 0
      return true
    end
    local function classify()
      return probes.flowed > 0 and "squat" or "deadlock",
        { where = summary(), alerts = alert_count(), flowed = probes.flowed, trace = trace }
    end
    if probes and probes.cur and probes.cur.state == "done" then
      -- 1本でも通り抜けられれば、全方向のブロックは続いていない(居座り)
      probes.flowed = probes.flowed + 1
      return classify()
    end
    if idle >= (opts.idle or IDLE) then
      if probes == nil then
        if not opts.station then return "stuck", { where = summary(), alerts = alert_count(), trace = trace } end
        probes = { i = 0, flowed = 0 }
        start_next_probe()
      else
        -- いま流している判定の列車は通り抜けられなかった。取り除いて、次を流す
        if probes.cur then probes.cur.state = "done"; probes.cur = nil end
        if not start_next_probe() then return classify() end
      end
    end
  end
  return "timeout", { where = summary(), trace = trace }
end

---駅の型の組み合わせ(2本)を総当たりで動かす
function M.sweep(label, station, opts, o)
  o = o or {}
  local offs = o.offsets or { 1, 25, 80 }
  local holds = o.holds or { 1, 500, 900 }
  opts = opts or {}
  local order = M.STATIONS[station].order
  local count = { ok = 0, squat = 0, deadlock = 0, timeout = 0, stuck = 0, alerted = 0 }
  local bad = {}
  local total_ = 0
  local function try(types, os_)
    total_ = total_ + 1
    local kind, info = M.run(types, os_, opts)
    count[kind] = count[kind] + 1
    if kind == "stuck" and (info.alerts or 0) > 0 then count.alerted = count.alerted + 1 end
    if kind ~= "ok" then bad[#bad + 1] = { kind = kind, types = types, offs = os_, info = info } end
  end
  for _, a in ipairs(order) do
    try({ a }, { M.TYPES[a].init and 1 or 1 })
    for _, b in ipairs(order) do
      local ta, tb = M.TYPES[a], M.TYPES[b]
      if not (ta.init and tb.init and ta.start == tb.start) then
        for _, off in ipairs(tb.init and holds or offs) do
          if ta.init then
            for _, h1 in ipairs(holds) do try({ a, b }, { h1, off }) end
          else
            try({ a, b }, { 1, off })
          end
        end
      end
    end
  end
  print(string.format("== %s: %d 通り: 完走 %d / 固まった %d(警報あり %d・なし %d) / 上限到達 %d",
    label, total_, count.ok, count.stuck, count.alerted, count.stuck - count.alerted, count.timeout))
  return bad, count
end

---駅の型から n 本を乱数で選んで動かす(n 本の組み合わせは数が多いので全探索はしない)。結果は再現できる(seed)
function M.random_sweep(label, station, n, samples, seed, opts)
  opts = opts or {}
  opts.station = station
  local order = M.STATIONS[station].order
  local offs = { 1, 10, 30, 60, 100 }
  local x = seed or 12345
  local function rnd(m) x = (x * 1103515245 + 12345) % 2147483648; return x % m + 1 end
  local count = { ok = 0, squat = 0, deadlock = 0, timeout = 0, stuck = 0 }
  local bad = {}
  for _ = 1, samples do
    local types, os_, starts = {}, {}, {}
    for i = 1, n do
      local name = order[rnd(#order)]
      local ty = M.TYPES[name]
      types[i] = name
      -- 最初からいる型は同じ軌道回路に重ねない(開始は周期1)
      os_[i] = ty.init and 1 or offs[rnd(#offs)]
      if ty.init then
        if starts[ty.start] then types[i] = nil end
        starts[ty.start] = true
      end
    end
    local clean, clean_os = {}, {}
    for i = 1, n do if types[i] then clean[#clean + 1] = types[i]; clean_os[#clean_os + 1] = os_[i] end end
    local kind, info = M.run(clean, clean_os, opts)
    count[kind] = count[kind] + 1
    if kind ~= "ok" then bad[#bad + 1] = { kind = kind, types = clean, offs = clean_os, info = info } end
  end
  print(string.format("== %s: %d 通り: 完走 %d / 居座り %d / デッドロック %d / 上限到達 %d",
    label, samples, count.ok, count.squat, count.deadlock, count.timeout))
  return bad, count
end

-- 直接実行したとき: 総当たりを回して、動けなくなった組み合わせを表示する
if arg and arg[0] and arg[0]:match("explore_arc%.lua$") then
  local station = arg[1] or "NHB"
  local d, speed = tonumber(arg[2]) or 15, tonumber(arg[3]) or 4
  local n = tonumber(arg[4])
  local bad
  if n then
    local samples = tonumber(arg[5]) or 300
    bad = M.random_sweep(string.format("%s %d本・軸距%dm・速度%dm/周期", station, n, d, speed), station, n, samples, tonumber(arg[6]),
      { idle = IDLE, max_steps = 8000, d = d, speed = speed })
  else
    bad = M.sweep(string.format("%s 軸距%dm・速度%dm/周期", station, d, speed), station,
      { idle = IDLE, max_steps = 8000, d = d, speed = speed })
  end
  local failed = false -- 警報なしで固まる、または上限に達するのは失敗
  for _, kind in ipairs({ "stuck", "timeout" }) do
    for _, b in ipairs(bad) do
      if b.kind == kind then
        if kind == "timeout" or (b.info.alerts or 0) == 0 then failed = true end
        print(string.format("  [%s] %s offs=%s -> %s (警報%s)", kind, table.concat(b.types, "+"), table.concat(b.offs, ","),
          b.info.where or "", (b.info.alerts or 0) > 0 and "あり" or "なし"))
      end
    end
  end
  os.exit(failed and 1 or 0)
end

return M
