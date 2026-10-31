-- 制御開始点(start_point)を、信号現示のシミュレーションで求める。
-- 実行(リポジトリルートから): lua tests/heavy/measure_start_points.lua [速度km/h=110] [軸距m=15] [Yの速度km/h=55] [余裕秒=10] [制限用の減速度m/s^2=0.7]
--
-- 方法:
--   1. 一定の速度で走る列車を、進路に沿って1本流す(信号には従わない。減速しない)。
--   2. 信号の最上位の現示(進路を全部先に開いた状態の値)が指示する速度 L まで落とすのに要する制動距離 B(L 以上の速度なら 0)に、
--      余裕秒(10秒)で進む距離を足した距離が、その信号の実効的な視認距離。
--      運転士は、現示が見えたらその現示に備えて制動する。ブレーキが間に合う限界の余裕秒前までに、
--      現示が最上位に変化していること(先頭軸が信号の「B + 余裕」手前から信号に着くまで最小の現示が最上位であること)を求める。
--      信号は、始点の軌道回路の末端と、進路の最初の軌道回路(signal_track の先頭)の間にある。
--      現示と指示速度: R=0、YY(1)=25、Y(2)=引数(55か45)、YG(3)=75、G(4)=速度引数。制動は制限用の減速度(既定 0.7 m/s^2)。R も制限制動(停止位置に向かう制動だけが停止制動)。
--   3. 制御開始点の候補を、場内の始点の軌道回路から1つずつ上流へずらして、同じ測定をする。
--   4. 通過したすべての信号が、実効的な視認距離の中で最上位の現示を出し続けている候補のうち、いちばん下流のものを採る。
--      最上位現示は、進路を全部先に開いた状態(開始点を最も上流に置いた測定)で記録した値。
--      進行が出ない進路(終着など)は、その状態で出る最上位の現示になる。
package.path = "./?.lua;" .. package.path
local h = require("tests.harness")
local LEN = require("tests.heavy.track_lengths")

local KMH = tonumber(arg and arg[1]) or 110
local SPEED = KMH / 3.6 * 0.1                 -- 1周期(6 tick = 0.1 秒)に進む距離[m]
local D = tonumber(arg and arg[2]) or 15
local Y_KMH = tonumber(arg and arg[3]) or 55  -- Y の指示速度[km/h]
local MARGIN_S = tonumber(arg and arg[4]) or 10 -- 余裕[秒]。ブレーキが間に合う限界の MARGIN_S 秒前までに、現示が変化していること
local MARGIN = SPEED / 0.1 * MARGIN_S         -- 余裕を距離にした値[m]
local VIS_REF = 400                           -- 最上位の現示を調べるときだけに使う窓[m]。最上位は、全進路を先に開いた状態の値
local ASPECT_KMH = { [0] = 0, [1] = 25, [2] = Y_KMH, [3] = 75, [4] = KMH }
local BRAKE = tonumber(arg and arg[5]) or 0.7 -- 制限用の減速度[m/s^2]。R への制動も制限制動

---指示速度 L まで、走行速度から落とすのに要する距離[m]
local function brake_distance(aspect)
  local l = ASPECT_KMH[aspect] or KMH
  if l >= KMH then return 0 end
  local v, w = KMH / 3.6, l / 3.6
  return (v * v - w * w) / (2 * BRAKE)
end
local function raw(b, st, pl) return 11 * 100000 + b * 10000 + 1000 + st * 10 + (pl or 0) end

-- 測る「一連の動き」。path: 先頭軸が通る軌道回路の順(最初は十分に上流)。
local TARGETS = {
  { st = "NHB", seq = "down_through", raw = raw(2, 5), path = { "HLT1LT", "HLT_NHB1T", "NHB5LT", "NHB21T", "NHB22AT", "NHB5RT" } },
  { st = "NHB", seq = "down_terminal", raw = raw(2, 3), path = { "HLT1LT", "HLT_NHB1T", "NHB5LT" } },
  { st = "NHB", seq = "up_through", raw = raw(1, 2),
    path = { "TKM_NHB4T", "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T", "NHB13RT", "NHB23T", "NHB22AT", "NHB21T", "NHB5LT", "HLT_NHB1T" } },
  { st = "NHB", seq = "up_terminal", raw = raw(1, 3, 4), label = "4番着",
    path = { "TKM_NHB4T", "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T", "NHB13RT", "NHB23T", "NHB22AT", "NHB21T", "NHB4LT" } },
  { st = "NHB", seq = "up_terminal", raw = raw(1, 3, 3), label = "3番着",
    path = { "TKM_NHB4T", "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T", "NHB13RT", "NHB23T", "NHB22AT", "NHB21T", "NHB5LT" } },
  { st = "TKM", seq = "down_through", raw = raw(2, 5),
    path = { "NHB_TKM5T", "NHB_TKM4T", "NHB_TKM3T", "NHB_TKM2T", "NHB_TKM1T", "TKM1RT", "TKM21AT", "TKM3RT" } },
  { st = "TKM", seq = "down_terminal", raw = raw(2, 4),
    path = { "NHB_TKM5T", "NHB_TKM4T", "NHB_TKM3T", "NHB_TKM2T", "NHB_TKM1T", "TKM1RT" } },
  { st = "TKM", seq = "up_through", raw = raw(1, 3),
    path = { "SGN_TKM4T", "SGN_TKM3T", "SGN_TKM2T", "SGN_TKM1T", "TKM4LT", "TKM21BT", "TKM22T", "TKM2T", "TKM2LT" } },
  { st = "TKM", seq = "up_terminal", raw = raw(1, 4),
    path = { "SGN_TKM4T", "SGN_TKM3T", "SGN_TKM2T", "SGN_TKM1T", "TKM4LT", "TKM21BT", "TKM22T", "TKM2T" } },
  { st = "SNH", seq = "down_arrive", raw = raw(2, 6),
    path = { "SGN_SNH4T", "SGN_SNH3T", "SGN_SNH2T", "SGN_SNH1T", "SNH1RT" } },
  { st = "SNH", seq = "up_arrive", raw = raw(1, 3),
    path = { "NMC_SNH4T", "NMC_SNH3T", "NMC_SNH2T", "NMC_SNH1T", "SNH21BT", "SNH4LT" } },
  { st = "NMC", seq = "down_terminal", raw = raw(2, 6, 0), label = "1・2番ホーム着",
    path = { "SNH_NMC4T", "SNH_NMC3T", "SNH_NMC2T", "SNH_NMC1T", "NMC11T", "NMC1RT" } },
  { st = "NMC", seq = "down_terminal", raw = raw(2, 6, 3), label = "3番ホーム着",
    path = { "SNH_NMC4T", "SNH_NMC3T", "SNH_NMC2T", "SNH_NMC1T", "NMC11T", "NMC2RT" } },
}

local function find_seq(sw, st, id)
  for _, s in ipairs(sw.arc.stations[st].sequences) do
    if s.id == id then return s end
  end
end

---列車を1本流し、境界を通るときの信号の現示を記録する
---@return table[] crossings {track, name, aspect, min}  先頭軸がtrackに入った瞬間の、入口の信号と現示(minは次の境界までの最小)
local function run(target, starts, win)
  local sw = h.new_production_sw()
  require("res.arc")(sw)
  local seq = find_seq(sw, target.st, target.seq)
  for i, mv in ipairs(seq.moves) do mv.start_point = starts[i] end
  local path = target.path
  -- 登録点は、最初の「動き」の制御開始点から場内の始点の軌道回路まで。登録点に上流の軌道回路が残っていると、
  -- 列車がそこで登録された時点で制御開始点を過ぎたとみなされ、候補を変えても進路が早く開いてしまう
  do
    local first = sw.nt:get_signal(seq.moves[1].options[1].signal).startTrack
    local from, to
    for i, t in ipairs(path) do
      if t == starts[1] then from = i end
      if t == first then to = i end
    end
    local at = {}
    if from and to then
      for i = from, to do at[#at + 1] = path[i] end
      seq.match.at = at
    end
  end
  local cum, acc = {}, 0
  for i, t in ipairs(path) do cum[i] = acc; acc = acc + LEN[t] end
  local total = acc - 2
  local function idx_at(s) for i = #path, 1, -1 do if s >= cum[i] then return i end end return 1 end
  local sf = 0
  -- 先頭軸の軌道回路にだけ指令値を載せる
  sw.arc.probe = function(id) return id == path[idx_at(sf)] and target.raw or 0 end

  -- 軌道回路 path[i] の入口を守る信号
  local guard = {}
  for i = 2, #path do
    for name, sg in pairs(sw.nt.signal) do
      local first = sg.signalTrack and sg.signalTrack[1]
      if first == path[i] and (sg.startTrack == path[i - 1] or sg.startTrack == nil) then
        guard[i] = guard[i] or {}
        table.insert(guard[i], name)
      end
    end
  end
  for i = 2, #path do
    -- 自動信号など startTrack を持たない信号は、signalTrack の先頭だけで決まる
    if guard[i] == nil then
      for name, sg in pairs(sw.nt.signal) do
        if sg.signalTrack and sg.signalTrack[1] == path[i] and sg.startTrack == nil then
          guard[i] = guard[i] or {}
          table.insert(guard[i], name)
        end
      end
    end
  end

  -- 信号ごとの記録: 視認する位置(信号の VIS m 手前。進路の先頭より手前にはならない)から信号に着くまでの最小の現示
  local recs = {}
  for i = 2, #path do
    for _, name in ipairs(guard[i] or {}) do
      recs[#recs + 1] = { index = i, track = path[i], name = name, pos = cum[i], vis = math.max(0, cum[i] - (win and win[i .. ":" .. name] or VIS_REF)), key = i .. ":" .. name }
    end
  end
  local out = recs
  while sf < total do
    sf = math.min(sf + SPEED, total)
    local fi = idx_at(sf)
    local ri = idx_at(math.max(0, sf - D))
    h.tick(sw, { [path[fi]] = true, [path[ri]] = true })
    sw:arc_process()
    for _, r in ipairs(recs) do
      if sf >= r.vis and sf < r.pos then
        local v = sw.nt:get_signal(r.name).aspect
        if r.aspect == nil or v < r.aspect then r.aspect = v end
      end
    end
  end
  for _, r in ipairs(recs) do r.aspect = r.aspect or 0 end
  return out
end

---通過したすべての信号が、実効的な視認距離の中で最上位を出しているか
local function all_top(rec, top)
  for _, r in ipairs(rec) do
    local t = top[r.key]
    if t and t > 0 and r.aspect < t then return false end
  end
  return true
end

local function index_of(path, t) for i, x in ipairs(path) do if x == t then return i end end end

local results = {}
for _, target in ipairs(TARGETS) do
  local sw = h.new_production_sw()
  require("res.arc")(sw)
  local seq = find_seq(sw, target.st, target.seq)
  local nmoves = #seq.moves
  local far = target.path[1]
  -- 各「動き」の候補: 場内(最初の「動き」)の始点の軌道回路から、上流へ
  local first_lever = sw.nt:get_signal(seq.moves[1].options[1].signal)
  local base = index_of(target.path, first_lever.startTrack)
  local cands = {}
  for i = base, 1, -1 do cands[#cands + 1] = i end

  -- 最上位現示: 開始点をすべて最も上流に置いた測定
  local starts = {}
  for m = 1, nmoves do starts[m] = far end
  local ref = run(target, starts)
  local top, win = {}, {}
  for _, r in ipairs(ref) do
    top[r.key] = r.aspect
    win[r.key] = brake_distance(r.aspect) + MARGIN
  end

  local chosen = {}
  for m = nmoves, 1, -1 do   -- 後ろの「動き」(出発)から決める
    local pick
    for _, ci in ipairs(cands) do
      local s2 = {}
      for k = 1, nmoves do s2[k] = chosen[k] or far end
      s2[m] = target.path[ci]
      if all_top(run(target, s2, win), top) then pick = ci; break end
    end
    chosen[m] = target.path[pick or 1]
    if not pick then print("  [注意] 動き" .. m .. ": どの候補でも最上位にならない。最も上流を採る") end
  end
  -- 決めた組み合わせで、もう一度確かめる
  local rec = run(target, chosen, win)
  local worst = all_top(rec, top)
  results[#results + 1] = { target = target, chosen = chosen, ok = worst, top = top, rec = rec }
  io.write(string.format("%s %s%s: ", target.st, target.seq, target.label and ("(" .. target.label .. ")") or ""))
  local parts = {}
  for m = 1, nmoves do parts[#parts + 1] = string.format("動き%d の制御開始点=%s", m, chosen[m]) end
  print(table.concat(parts, "、") .. (worst and "" or "  [確認の測定でも最上位が出続けない]"))
  local asp = {}
  for _, r in ipairs(rec) do if (top[r.index .. ":" .. r.name] or 0) > 0 then asp[#asp + 1] = string.format("%s(%s)=%d/%d[窓%.0fm]", r.name, r.track, r.aspect, top[r.key], win[r.key]) end end
  print("    通過した信号の現示/最上位: " .. table.concat(asp, " "))
end
