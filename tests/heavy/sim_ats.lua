-- ATS(地上側の速度信号 H0)のシミュレーションラン。運転士モデルを持つ。
-- 実行(リポジトリルートから): node tests/gen_res.js && lua tests/heavy/sim_ats.lua   (約 1 分。pnpm test には含めない)
-- 確認用の環境変数: ATS_DEBUG=1 (止まったときの信号の状態を出す)、ATS_ONLY=<番号> (単独走行の1経路だけ)、
--                  ATS_TB=<番号> (折り返しの1本だけ。ほかの走行は回さない)
--
-- 列車を ARC の「一連の動き」に沿って流す。運転士役と ATS は、独立に動く。
--   - 運転士役(先読み制動): 見るのは信号の現示だけ。ATS の値(H0)は見ない。
--     前方の信号の現示が指示する速度に、信号の位置で間に合うように制動する(視認距離は十分に長くしてある)。
--     信号を通り過ぎた後は、通り過ぎた時の現示の速度を、次の信号まで守る。R の信号は手前で止まり、開いたら再発進する。
--     停車駅ではホームの端の手前に止まり、停車秒数がたったら指令値を書き換えて発車する。
--     発車する列車は、出発信号の現示の速度を、ホームの軌道回路から守る(出発側の符号が出発信号そのものの現示のため)。
--     列車の見る信号は、経路に合う進路の信号だけ。同じ入口の進路が複数あるときは、いちばん遠くまで行く進路の組を見る。
--   - ATS: 本番の Area の callback が、先頭の軸に送る H0 だけを見る。超えた分(v - H0)を測り、EPS(0.5 km/h)を超えたら作動とみなす。
--     「やや高い速度で作動」する余裕は入れていない(想定走行速度は ATS の値 - 5 km/h で、ここでは指示速度ちょうどで走るので厳しい側)。
--     H0 を受けないとき(E 扱い)は、別に数える。経路の最初の軌道回路(列車が現れるだけ)は判定しない。
-- 走らせるもの: 単独走行(パターン A〜D。C・D は速度表を変えた参考)、後追い(先行が停車・停止して遅れる)、折り返し・入換(7 本)。
-- 限界: 軸の位置は Area の多角形の長さ(頂点の最大距離)で決める。分岐を含む軌道回路では、枝の Area も数えるので、実際より少し長い。
--       信号の位置は、その信号が守る軌道回路の最初の Area の始端(重複区間があるときは、共有する Area の始端)。
--       手書きの既存10本の Track での作動は [既存] を付けて分けて出す。
package.path = "./?.lua;" .. package.path
local h = require("tests.harness")
local DEBUG = os.getenv("ATS_DEBUG") ~= nil
local ONLY = tonumber(os.getenv("ATS_ONLY") or "")
local TB_ONLY = tonumber(os.getenv("ATS_TB") or "") -- 折り返しだけ、その番号の1本を回す(確認用)

local D = 15       -- 先頭軸と後尾軸の距離[m]
local DT = 0.1     -- 1周期[s](6 tick)
local EPS = 0.5    -- 数値の丸めの許容[km/h]
-- 手書きの既存の記述(今回の生成の対象外)。結果には [既存] を付けて分ける
local EXIST = { NHB4LT = 1, NHB5LT = 1, NHB6LT = 1, NHB14LT = 1, NHB13RT = 1, NHB21T = 1, NHB22AT = 1, NHB23T = 1, HLT1LT = 1, HLT_NHB1T = 1 }

local function raw(b, st, pl) return 11 * 100000 + b * 10000 + 1000 + st * 10 + (pl or 0) end

-- tests/heavy/measure_start_points.lua と同じ「一連の動き」。path: 先頭軸が通る軌道回路の順
local TARGETS = {
  { st = "NHB", seq = "down_through", raw = raw(2, 5), path = { "HLT1LT", "HLT_NHB1T", "NHB5LT", "NHB21T", "NHB22AT", "NHB5RT", "NHB_TKM5T", "NHB_TKM4T", "NHB_TKM3T" } },
  { st = "NHB", seq = "down_terminal", raw = raw(2, 3), stop = true, path = { "HLT1LT", "HLT_NHB1T", "NHB5LT" } },
  { st = "NHB", seq = "up_through", raw = raw(1, 2),
    path = { "TKM_NHB4T", "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T", "NHB13RT", "NHB23T", "NHB22AT", "NHB21T", "NHB5LT", "HLT_NHB1T" } },
  { st = "NHB", seq = "up_terminal", raw = raw(1, 3, 4), label = "4番着", stop = true,
    path = { "TKM_NHB4T", "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T", "NHB13RT", "NHB23T", "NHB22AT", "NHB21T", "NHB4LT" } },
  { st = "NHB", seq = "up_terminal", raw = raw(1, 3, 3), label = "3番着", stop = true,
    path = { "TKM_NHB4T", "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T", "NHB13RT", "NHB23T", "NHB22AT", "NHB21T", "NHB5LT" } },
  { st = "TKM", seq = "down_through", raw = raw(2, 5), lead_stop = { track = "TKM1RT", arr = raw(2, 4), dep = raw(2, 5) },
    path = { "NHB_TKM5T", "NHB_TKM4T", "NHB_TKM3T", "NHB_TKM2T", "NHB_TKM1T", "TKM1RT", "TKM21AT", "TKM3RT", "TKM_SGN3T" } },
  { st = "TKM", seq = "down_terminal", raw = raw(2, 4), stop = true,
    path = { "NHB_TKM5T", "NHB_TKM4T", "NHB_TKM3T", "NHB_TKM2T", "NHB_TKM1T", "TKM1RT" } },
  { st = "TKM", seq = "up_through", raw = raw(1, 3), lead_stop = { track = "TKM2T", arr = raw(1, 4, 2), dep = raw(1, 3) },
    path = { "SGN_TKM4T", "SGN_TKM3T", "SGN_TKM2T", "SGN_TKM1T", "TKM4LT", "TKM21BT", "TKM22T", "TKM2T", "TKM2LT", "TKM_NHB4T", "TKM_NHB3T" } },
  { st = "TKM", seq = "up_terminal", raw = raw(1, 4), stop = true,
    path = { "SGN_TKM4T", "SGN_TKM3T", "SGN_TKM2T", "SGN_TKM1T", "TKM4LT", "TKM21BT", "TKM22T", "TKM2T" } },
  { st = "SNH", seq = "down_arrive", raw = raw(2, 6), stop = true,
    path = { "SGN_SNH4T", "SGN_SNH3T", "SGN_SNH2T", "SGN_SNH1T", "SNH1RT" } },
  { st = "SNH", seq = "up_arrive", raw = raw(1, 3), stop = true,
    path = { "NMC_SNH4T", "NMC_SNH3T", "NMC_SNH2T", "NMC_SNH1T", "SNH21BT", "SNH4LT" } },
  { st = "NMC", seq = "down_terminal", raw = raw(2, 6, 0), label = "1・2番ホーム着", stop = true,
    path = { "SNH_NMC4T", "SNH_NMC3T", "SNH_NMC2T", "SNH_NMC1T", "NMC11T", "NMC1RT" } },
  { st = "NMC", seq = "down_terminal", raw = raw(2, 6, 3), label = "3番ホーム着", stop = true,
    path = { "SNH_NMC4T", "SNH_NMC3T", "SNH_NMC2T", "SNH_NMC1T", "NMC11T", "NMC2RT" } },
}

-- 試すパターン。drv: 現示→運転士が守る速度[km/h]、vmax: 最高速度、look: 視認距離[m]、brake: 制動の減速度[m/s^2]
local ATS_TABLE = { [0] = 0, [1] = 30, [2] = 50, [3] = 70, [4] = 100 }
local ARC_TABLE = { [0] = 0, [1] = 25, [2] = 55, [3] = 75, [4] = 110 }
local PATTERNS = {
  { name = "A 基準(ATSの表どおりの速度で、間に合うように制動)", drv = ATS_TABLE, vmax = 100, look = 1500, brake = 0.7 },
  { name = "B 弱い制動(0.5 m/s^2)", drv = ATS_TABLE, vmax = 100, look = 1500, brake = 0.5 },
  { name = "C G を 110 km/h で走る(参考)", drv = { [0] = 0, [1] = 30, [2] = 50, [3] = 70, [4] = 110 }, vmax = 110, look = 1500, brake = 0.7 },
  { name = "D ARCの速度表(YY25/Y55/YG75/G110)で走る(参考)", drv = ARC_TABLE, vmax = 110, look = 1500, brake = 0.7 },
}

local function dist2(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end
local function area_len(area)
  local vs, m = area.vertexs, 0
  for i = 1, #vs do for j = i + 1, #vs do local d = dist2(vs[i], vs[j]); if d > m then m = d end end end
  return m
end

local function find_seq(sw, st, id)
  for _, s in ipairs(sw.arc.stations[st].sequences) do
    if s.id == id then return s end
  end
end

---経路の向き(R=右、L=左)を、隣り合う軌道回路の Area の並びから決める
local function direction(sw, path)
  local a, b = sw.track_bridge[path[1]].area_ids, sw.track_bridge[path[2]].area_ids
  if a[#a] == b[1] then return "R" end
  if b[#b] == a[1] then return "L" end
  for _, r in ipairs(sw.areas[a[#a]].rightAreaIds) do if r == b[1] then return "R" end end
  return "L"
end

---経路に沿った Area の並びと、各軌道回路の入口の位置を作る
local function build_path(sw, path, dir)
  local seq, placed, entry, pos = {}, {}, {}, 0
  for i, t in ipairs(path) do
    local ids = {}
    for k, a in ipairs(sw.track_bridge[t].area_ids) do ids[k] = a end
    if dir == "L" then
      for k = 1, #ids // 2 do ids[k], ids[#ids - k + 1] = ids[#ids - k + 1], ids[k] end
    end
    for k, a in ipairs(ids) do
      if placed[a] then
        if k == 1 then entry[i] = placed[a].start end
      else
        local len = area_len(sw.areas[a])
        local e = { id = a, start = pos, len = len }
        seq[#seq + 1] = e
        placed[a] = e
        if k == 1 then entry[i] = pos end
        pos = pos + len
      end
    end
  end
  return seq, entry, pos
end

local function area_at(seq, x)
  for i = #seq, 1, -1 do if x >= seq[i].start then return seq[i] end end
  return seq[1]
end

---列車を流す。specs: 列車ごとの { name, front0[m], v0[km/h], vmax[km/h], raw, hold = { pos, secs } }。最初の列車が先行、最後の列車が後追い。
---@return table[] 列車ごとの結果
local function simulate(target, pat, specs, sw_in)
  local sw = sw_in
  if not sw then
    sw = h.new_production_sw()
    require("res.arc")(sw)
  end
  local path = target.path
  local dir = direction(sw, path)
  local seq, entry, total = build_path(sw, path, dir)
  local drive_end = total - 2

  -- Area → 所属する軌道回路
  local owners = {}
  for tid, br in pairs(sw.track_bridge) do
    for _, a in ipairs(br.area_ids) do owners[a] = owners[a] or {}; table.insert(owners[a], tid) end
  end
  local function track_index(x) for i = #path, 1, -1 do if x >= entry[i] then return i end end return 1 end

  -- 軌道回路 path[i] の入口を守る信号。経路に合う進路の信号だけ(同じ場所から出る別の進路の信号は、障害として見ない)
  local index_of = {}
  for i, tid in ipairs(path) do index_of[tid] = i end
  local function on_path(sg, i)
    for k, tid in ipairs(sg.routeLock or {}) do
      if path[i + k - 1] ~= tid then return false end
    end
    if sg.destination then
      local di = index_of[sg.destination]
      if di == nil or di < i then return false end
    end
    return true
  end
  local guards, cand = {}, {}
  for i = 2, #path do
    for name, sg in pairs(sw.nt.signal) do
      local first = sg.signalTrack and sg.signalTrack[1]
      if first == path[i] and (sg.startTrack == path[i - 1] or sg.startTrack == nil) and on_path(sg, i) then
        cand[#cand + 1] = { name = name, pos = entry[i], i = i, sg = sg }
      end
    end
  end
  -- 通し進路の内側にある信号(進路の途中の軌道回路から出る入換の信号など)は、その進路を通る列車の障害にならない
  for _, c in ipairs(cand) do
    local inner = false
    for _, o in ipairs(cand) do
      if o.i < c.i and c.sg.startTrack then
        for _, tid in ipairs(o.sg.routeLock or {}) do if tid == c.sg.startTrack then inner = true end end
      end
    end
    if not inner then c.keep = true end
  end
  -- 入口ごとに、いちばん遠い行き先の信号の組(行き先が同じ信号は組にする)。自動信号(startTrack なし)は1本だけ
  local by_entry = {}
  for _, c in ipairs(cand) do
    if c.keep then
      local far = c.sg.destination and index_of[c.sg.destination] or 0
      local e = by_entry[c.i]
      if e == nil or far > e.far then by_entry[c.i] = { far = far, pos = c.pos, names = { c.name } }
      elseif far == e.far then table.insert(e.names, c.name) end
    end
  end
  for i = 2, #path do
    if by_entry[i] then guards[#guards + 1] = { names = by_entry[i].names, pos = by_entry[i].pos } end
  end
  table.sort(guards, function(a, b) return a.pos < b.pos end)

  local trains = {}
  for k, sp in ipairs(specs) do
    local tr = {
      name = sp.name, front = type(sp.front0) == "function" and sp.front0(entry, total) or sp.front0, v = (sp.v0 or 0) / 3.6, vmax = sp.vmax or pat.vmax, raw = sp.raw, hold = sp.hold and { pos = sp.hold.pos, secs = sp.hold.secs, t = 0 } or nil,
      stop = sp.stop and { pos = (type(sp.stop.pos) == "function" and sp.stop.pos(entry, total)) or (type(sp.stop.pos) == "number" and sp.stop.pos) or ((entry[index_of[sp.stop.track] + 1] or total) - 20), secs = sp.stop.secs, raw_dep = sp.stop.raw_dep, t = 0, done = false } or nil,
      fa = { sending = {} }, ra = { sending = {} }, active = true, stopt = 0, latched = nil, g = {}, braking = false, brakes = 0, waited = 0,
      check_first = sp.check_first, violations = {}, nocode = {}, min_margin = nil, worst = nil, cur_vio = nil, stopped_at = nil, done = false, min_gap = nil,
    }
    for gi, g in ipairs(guards) do tr.g[gi] = { passed = false } end
    trains[k] = tr
  end
  sw.arc.probe = function(id)
    for _, tr in ipairs(trains) do
      if tr.active and id == path[track_index(tr.front)] then return tr.raw end
    end
    return 0
  end

  local t, steps = 0, 0
  while steps < 40000 do
    local any = false
    for _, tr in ipairs(trains) do if tr.active then any = true end end
    if not any then break end
    steps = steps + 1

    -- 軸を Area に置く。在線は、前後の軸とその間の Area の軌道回路
    for _, a in pairs(sw.areas) do a.axles = {} end
    local short = {}
    local per_area = {}
    for _, tr in ipairs(trains) do
      if tr.active then
        tr.fa.sending, tr.ra.sending = {}, {}
        local af, ar = area_at(seq, tr.front), area_at(seq, math.max(0, tr.front - D))
        per_area[af.id] = per_area[af.id] or {}; table.insert(per_area[af.id], { ax = tr.fa, s = tr.front })
        per_area[ar.id] = per_area[ar.id] or {}; table.insert(per_area[ar.id], { ax = tr.ra, s = tr.front - D })
        for _, e in ipairs(seq) do
          if e.start + e.len > tr.front - D and e.start <= tr.front then
            for _, tid in ipairs(owners[e.id] or {}) do short[tid] = true end
          end
        end
      end
    end
    for id, list in pairs(per_area) do
      table.sort(list, function(a, b) if dir == "R" then return a.s < b.s else return a.s > b.s end end)
      local axles = {}
      for _, x in ipairs(list) do axles[#axles + 1] = x.ax end
      sw.areas[id].axles = axles
    end
    h.tick(sw, short)
    sw:arc_process()
    sw:before_broadcast(6)

    for k, tr in ipairs(trains) do
      if tr.active then
        -- 運転士役: 信号の現示だけを見る
        local vdes = tr.vmax / 3.6
        for gi, g in ipairs(guards) do
          local st = tr.g[gi]
          if not st.passed then
            local d = g.pos - tr.front
            if d <= 0 then
              st.passed = true
              tr.latched = st.seen or st.last
            else
              local a = 0
              for _, nm in ipairs(g.names) do a = math.max(a, sw.nt:get_signal(nm).aspect) end
              st.last = a
              if d <= pat.look then
                st.seen = a
                local vt = pat.drv[a] / 3.6
                local dd = d
                if a == 0 then dd = d - 5 end
                local lim = math.sqrt(vt * vt + 2 * pat.brake * math.max(0, dd))
                if lim < vdes then vdes = lim end
              end
            end
          end
        end
        if tr.latched then vdes = math.min(vdes, pat.drv[tr.latched] / 3.6) end
        if tr.check_first and tr.v < 0.05 and not tr.moved then
          for gi, g in ipairs(guards) do
            if not tr.g[gi].passed then
              if tr.g[gi].last == 0 then vdes = 0 end
              break
            end
          end
        end
        -- 発車する列車は、出発信号の現示の速度を、ホームの軌道回路から守る(出発側の符号は、出発信号そのものの現示のため)
        if tr.check_first then
          for gi, g in ipairs(guards) do
            if not tr.g[gi].passed then
              local ga = tr.g[gi].last
              if ga and ga > 0 then vdes = math.min(vdes, pat.drv[ga] / 3.6) end
              break
            end
          end
        end
        if tr.v > 0.05 then tr.moved = true end
        if target.stop then vdes = math.min(vdes, math.sqrt(2 * pat.brake * math.max(0, drive_end - tr.front))) end
        if tr.hold and not tr.hold.done then
          vdes = math.min(vdes, math.sqrt(2 * pat.brake * math.max(0, tr.hold.pos - tr.front)))
          if tr.front >= tr.hold.pos - 1 and tr.v < 0.2 then
            tr.hold.t = tr.hold.t + DT
            if tr.hold.t >= tr.hold.secs then tr.hold.done = true end
          end
        end

        -- 停車駅: ホームの端の手前に止まり、停車秒数がたったら、指令値を出発のものに書き換える
        if tr.stop and not tr.stop.done then
          vdes = math.min(vdes, math.sqrt(2 * pat.brake * math.max(0, tr.stop.pos - tr.front)))
          if tr.front >= tr.stop.pos - 1 and tr.v < 0.2 then
            tr.stop.t = tr.stop.t + DT
            if tr.stop.t >= tr.stop.secs then tr.stop.done = true; tr.raw = tr.stop.raw_dep end
          end
        end

        -- ATS: 先頭の軸に送られた H0 だけを見る(運転士役とは独立)
        local vk = tr.v * 3.6
        local h0 = tr.fa.sending[1]
        local where = path[track_index(tr.front)]
        local ai = area_at(seq, tr.front)
        -- 経路の最初の軌道回路は、列車がそこに現れるだけ(通り過ぎた信号がない)なので、判定しない
        if tr.v > 0.3 and (where ~= path[1] or tr.check_first) then
          if h0 == nil or h0 == 0 then
            tr.nocode[where] = (tr.nocode[where] or 0) + 1
          else
            local margin = h0 - vk
            if tr.min_margin == nil or margin < tr.min_margin then tr.min_margin = margin; tr.worst = { track = where, area = ai.id, v = vk, h0 = h0 } end
            if margin < -EPS then
              if not tr.cur_vio then
                tr.cur_vio = { track = where, area = ai.id, over = -margin, v = vk, h0 = h0, t = t }
                table.insert(tr.violations, tr.cur_vio)
              elseif -margin > tr.cur_vio.over then tr.cur_vio.over = -margin; tr.cur_vio.v = vk end
            else
              tr.cur_vio = nil
            end
          end
        end

        -- 走行
        local v0 = tr.v
        if tr.v < vdes then tr.v = math.min(vdes, tr.v + 0.8 * DT) else tr.v = math.max(vdes, tr.v - pat.brake * DT) end
        local decel = (v0 - tr.v) / DT
        if decel > 0.3 and not tr.braking then tr.brakes = tr.brakes + 1; tr.braking = true
        elseif decel < 0.05 then tr.braking = false end
        tr.front = tr.front + tr.v * DT
        if k > 1 then
          local lead = trains[k - 1]
          if lead.active then
            local gap = lead.front - D - tr.front
            if tr.min_gap == nil or gap < tr.min_gap then tr.min_gap = gap end
          end
        end
        if tr.front >= drive_end - 0.01 and target.stop and tr.v < 0.2 then tr.active = false; tr.done = true end
        if tr.front >= total then tr.active = false; tr.done = true end
        -- 信号が開くのを待って止まっているのは正常。120 秒動かなければ、止まったとみなす
        local dwelling = tr.stop and not tr.stop.done and tr.front >= tr.stop.pos - 1
        if tr.v < 0.05 and not dwelling then tr.stopt = tr.stopt + DT; tr.waited = tr.waited + DT
        elseif not dwelling then tr.stopt = 0 end
        if DEBUG and tr.stopt > 10 and not tr.dbg then
          tr.dbg = true
          local parts = {}
          for gi, g in ipairs(guards) do
            if not tr.g[gi].passed and g.pos - tr.front < 600 then
              local sg = sw.nt:get_signal(g.names[1])
              parts[#parts + 1] = string.format("%s(あと%.0fm)=asp%d HR=%s", table.concat(g.names, "/"), g.pos - tr.front, sg.aspect, tostring(sg.HR))
            end
          end
          print(string.format("  [DEBUG t=%.0f %s 停止中 在線=%s] %s", t, tr.name, path[track_index(tr.front)], table.concat(parts, " ")))
          local av = sw.arc_values or {}
          local ks = {}
          for k, vv in pairs(av) do ks[#ks + 1] = k .. "=" .. tostring(vv) end
          print("  [DEBUG arc採用値] " .. table.concat(ks, " "))
        end
        if tr.stopt > 120 then tr.stopped_at = path[track_index(tr.front)]; tr.active = false end
      end
    end
    t = t + DT
  end
  for _, tr in ipairs(trains) do tr.time = t end
  return trains, sw
end

local function describe(tr)
  local status
  if #tr.violations == 0 then
    status = string.format("ATS照査なし 最小余裕=%.1f km/h", tr.min_margin or 0)
    if tr.worst then status = status .. string.format("(%s %.0f/%d)", tr.worst.track, tr.worst.v, tr.worst.h0) end
  else
    local parts = {}
    for i = 1, math.min(#tr.violations, 4) do
      local x = tr.violations[i]
      parts[#parts + 1] = string.format("%s%s(Area%s) %.0f>%d km/h [+%.1f]", x.track, EXIST[x.track] and "[既存]" or "", x.area, x.v, x.h0, x.over)
    end
    status = string.format("ATS作動 %d か所: %s", #tr.violations, table.concat(parts, " / "))
  end
  local nc = {}
  for k, n in pairs(tr.nocode) do nc[#nc + 1] = string.format("%s%s:%d", k, EXIST[k] and "[既存]" or "", n) end
  table.sort(nc)
  local tail = ""
  if not tr.done then tail = tail .. string.format("  [未到達: %s で停止]", tr.stopped_at or "?") end
  if #nc > 0 then tail = tail .. "  [H0なし(走行中) " .. table.concat(nc, " ") .. "]" end
  return status .. tail
end
local function gen_violations(tr)
  local n = 0
  for _, x in ipairs(tr.violations) do if not EXIST[x.track] then n = n + 1 end end
  return n
end

local total_runs, clean_runs, clean_gen = 0, 0, 0
local function count(tr)
  total_runs = total_runs + 1
  if #tr.violations == 0 then clean_runs = clean_runs + 1 end
  if gen_violations(tr) == 0 then clean_gen = clean_gen + 1 end
end

-- 1. 単独走行
for _, pat in ipairs(TB_ONLY and {} or PATTERNS) do
  print(string.format("\n===== 単独走行 パターン %s =====", pat.name))
  for ti, target in ipairs(TARGETS) do
   if not ONLY or ti == ONLY then
    local tr = simulate(target, pat, { { name = "列車", front0 = D, v0 = 45, raw = target.raw } })[1]
    count(tr)
    local label = string.format("%s %s%s", target.st, target.seq, target.label and ("(" .. target.label .. ")") or "")
    print(string.format("  %-34s %s", label, describe(tr)))
   end
  end
end

-- 2. 後追い: 後追い(区間急行)は、信号現示と停車駅の情報に従って、できるだけ詰めて走る。
--    先行(準急)が遅れていて(駅で長く停車する、途中で止まる、遅い)、後追いが詰まったり離されたりして、制動と加速を繰り返す。
--    後追いは先行の1〜2閉そく先を目標に出発し、あとは信号現示だけで走る(間隔は固定しない)。先行は後追いより先に出ている。
local FOLLOW_TARGETS = { 6, 8, 1, 3 } -- TARGETS の番号(終着で止まらない通し運転)
local FOLLOW = {
  { name = "先行が駅に30秒停車", dwell = 30 },
  { name = "先行が駅に60秒停車", dwell = 60 },
  { name = "先行が駅に120秒停車(遅れ)", dwell = 120 },
  { name = "先行が80km/hで走り、駅に60秒停車", dwell = 60, lead_vmax = 80 },
  { name = "先行が途中で60秒停止", hold_secs = 60 },
  { name = "先行が途中で120秒停止", hold_secs = 120 },
}
local fpat = PATTERNS[1]
for _, tn in ipairs(TB_ONLY and {} or FOLLOW_TARGETS) do
  local target = TARGETS[tn]
  local label = string.format("%s %s%s", target.st, target.seq, target.label and ("(" .. target.label .. ")") or "")
  print(string.format("\n===== 後追い %s =====", label))
  for _, fc in ipairs(FOLLOW) do
    local skip = (fc.dwell and not target.lead_stop)
    if not skip then
      local sw0 = h.new_production_sw()
      local dir = direction(sw0, target.path)
      local _, _, total = build_path(sw0, target.path, dir)
      local lead = { name = "先行", front0 = function(entry) return entry[3] + 50 end, v0 = 40, vmax = fc.lead_vmax or 100, raw = target.raw + 100000 }
      if fc.dwell then
        lead.raw = target.lead_stop.arr + 100000
        lead.stop = { track = target.lead_stop.track, secs = fc.dwell, raw_dep = target.lead_stop.dep + 100000 }
      end
      if fc.hold_secs then lead.hold = { pos = total * 0.55, secs = fc.hold_secs } end
      local trs = simulate(target, fpat, { lead, { name = "後追い", front0 = D, v0 = 45, vmax = 100, raw = target.raw } })
      count(trs[2])
      local f = trs[2]
      print(string.format("  %-34s 後追い: %s", fc.name, describe(f)))
      print(string.format("  %-34s   制動 %d 回 / 信号待ち計 %.0f 秒 / 先行との最小車間 %.0f m / 先行: %s", "", f.brakes, f.waited, f.min_gap or -1, #trs[1].violations == 0 and "ATS照査なし" or "ATS作動"))
    end
  end
end
-- 3. 折り返し: 到着の向きで止まり、先頭の軸を入れ替えて、反対向きに出発する。
--    ARC の状態は続ける。停車中は到着の指令値のまま、停車秒数がたったら出発の指令値に書き換える。
--    折り返しの Track 自身も、ATS の判定に含める(出発側の記述はその Track にある)。
local TURNBACKS = {
  { name = "北港 4番(上りで着いて下りで出る)", dwell = 30,
    arrive = TARGETS[4],
    depart = { st = "NHB", seq = "down_depart_p4", raw = raw(2, 5), path = { "NHB4LT", "NHB21T", "NHB22AT", "NHB5RT", "NHB_TKM5T", "NHB_TKM4T", "NHB_TKM3T" } } },
  { name = "北港 3番(上りで着いて下りで出る)", dwell = 30,
    arrive = TARGETS[5],
    depart = { st = "NHB", seq = "down_depart_p3", raw = raw(2, 5), path = { "NHB5LT", "NHB21T", "NHB22AT", "NHB5RT", "NHB_TKM5T", "NHB_TKM4T", "NHB_TKM3T" } } },
  { name = "北港 3番(下りで着いて上りで出る)", dwell = 30,
    arrive = TARGETS[2],
    depart = { st = "NHB", seq = "up_depart", raw = raw(1, 2), stop = true, path = { "NHB5LT", "HLT_NHB1T" } } },
  { name = "潮凪浜 2番(上りで着いて下りで出る)", dwell = 30,
    arrive = { st = "SNH", seq = "up_arrive", raw = raw(1, 5, 2), stop = true, path = TARGETS[11].path },
    depart = { st = "SNH", seq = "down_depart_p2", raw = raw(2, 6), path = { "SNH4LT", "SNH21BT", "SNH21AT", "SNH3RT", "SNH_NMC4T", "SNH_NMC3T", "SNH_NMC2T" } } },
  { name = "南江町 1・2番ホーム(下りで着いて上りで出る)", dwell = 30,
    arrive = TARGETS[12],
    depart = { st = "NMC", seq = "up_depart_p12", raw = raw(1, 5), path = { "NMC1RT", "NMC11T", "NMC1LT", "NMC_SNH4T", "NMC_SNH3T", "NMC_SNH2T" } } },
  { name = "南江町 3番ホーム(下りで着いて上りで出る)", dwell = 30,
    arrive = TARGETS[13],
    depart = { st = "NMC", seq = "up_depart_p3", raw = raw(1, 5), path = { "NMC2RT", "NMC11T", "NMC1LT", "NMC_SNH4T", "NMC_SNH3T", "NMC_SNH2T" } } },
}
---段をつないで流す。各段は、前の段が止まった位置から、先頭の軸を入れ替えて(flip)、または同じ向きのまま続けて出る。
---phases: { target, flip, dwell }。停車中は前の段の指令値のまま、停車秒数がたったら、その段の指令値に書き換える
local function run_chain(phases, pat)
  local sw, prev_raw
  local results = {}
  for k, ph in ipairs(phases) do
    local t = ph.target
    local spec
    if k == 1 then
      spec = { name = "列車", front0 = D, v0 = 45, raw = t.raw }
    else
      local f0 = ph.flip and (D + 2) or function(entry) return entry[2] - 2 end
      spec = { name = "列車", front0 = f0, v0 = 0, vmax = 100, raw = prev_raw, check_first = true,
               stop = { track = t.path[1], pos = f0, secs = ph.dwell or 30, raw_dep = t.raw } }
    end
    local trs
    trs, sw = simulate(t, pat, { spec }, sw)
    results[k] = trs[1]
    prev_raw = t.raw
  end
  return results
end

-- 潮凪浜: 2番に上りで着き、2xx59(下り・潮凪浜の引き上げ線)で入換えて、1xxxx(上り)で戻り、上りで出発する
local SNH_SHUNT = {
  { label = "到着(2番、潮凪浜止まり)", target = { st = "SNH", seq = "up_arrive", raw = raw(1, 5, 2), stop = true, path = TARGETS[11].path } },
  { label = "入換(2xx59 で引き上げ線へ)", flip = true, target = { st = "SNH", seq = "p2_to_yard", raw = raw(2, 5, 9), stop = true, path = { "SNH4LT", "SNH21BT", "SNH21AT", "SNH3RT" } } },
  { label = "戻り(1xxxx で2番へ)", flip = true, target = { st = "SNH", seq = "yard_to_p2_depart", raw = raw(1, 3), stop = true, path = { "SNH3RT", "SNH21AT", "SNH21BT", "SNH4LT" } } },
  { label = "上り出発", flip = false, target = { st = "SNH", seq = "up_depart", raw = raw(1, 3), path = { "SNH4LT", "SNH22T", "SNH2LT", "SNH_SGN3T", "SNH_SGN2T" } } },
}

for _, pat in ipairs({ PATTERNS[1], PATTERNS[2] }) do
  print(string.format("\n===== 折り返し パターン %s =====", pat.name))
  if not TB_ONLY or TB_ONLY == 7 then
    local phases = {}
    for k, ph in ipairs(SNH_SHUNT) do phases[k] = ph end
    local rs = run_chain(phases, pat)
    print("  潮凪浜 入換(2xx59 で引き上げ線へ、1xxxx で戻って上り出発)")
    for k, r in ipairs(rs) do
      count(r)
      print(string.format("    %-26s %s", SNH_SHUNT[k].label .. ":", describe(r)))
    end
  end
  for ti, tb in ipairs(TURNBACKS) do
   if not TB_ONLY or TB_ONLY == ti then
    -- 到着
    local a_trs, sw = simulate(tb.arrive, pat, { { name = "列車", front0 = D, v0 = 45, raw = tb.arrive.raw } })
    local a = a_trs[1]
    -- 出発: 到着で止まった位置の先頭が、反対向きの経路の始端から D + 2 m の所に来る(後尾が先頭になる)
    local dep = tb.depart
    local d_trs = simulate(dep, pat, { { name = "列車", front0 = D + 2, v0 = 0, vmax = 100, raw = tb.arrive.raw, check_first = true,
      stop = { track = dep.path[1], pos = D + 2, secs = tb.dwell, raw_dep = dep.raw } } }, sw)
    local d = d_trs[1]
    count(a); count(d)
    print(string.format("  %s", tb.name))
    print(string.format("    到着: %s", describe(a)))
    print(string.format("    出発: %s", describe(d)))
   end
  end
end
print(string.format("\n%d 走行(後追いは後追いだけ数える)中、ATS照査に当たらなかった走行は %d(既存10本での作動を除くと %d)", total_runs, clean_runs, clean_gen))
