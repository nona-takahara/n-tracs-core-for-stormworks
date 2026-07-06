-- 実地テストで判明したバグを再現するためのテストケース ひな形
--
-- 事前準備（初回だけ / signal.toml, area_track.json を更新した後も）:
--   node tests/gen_res.js
--
-- 実行方法（リポジトリルートから）:
--   lua tests/repro_template.lua
--
-- 使い方:
--   1. このファイルをコピーして tests/repro_<issue番号や現象名>.lua を作る
--   2. 本番の信号機/軌道回路名（NHB5R, WAK1RT など。res/signal.toml, res/area_track.json
--      に実在する名前）を使い、バグが起きた状況を組み立てる
--   3. 各サイクルの直後に check() で「そのときどうなっているべきか」を書く
--      (現状のコードでは失敗する = バグを再現できている、という状態でよい)
--   4. これをそのまま Claude への修正依頼に添付する

local h = require("tests.harness")

-- 本番構成一式をロードします(実際のゲーム内と同じ信号機・軌道回路・転てつ器)
local sw = h.new_production_sw()
local c = h.new_checker()

-- 在線(車両がその抽象軌道回路上にいる)状態は、テスト側でこの table を書き換えて
-- 明示的に指定します。実車を使わないため、この table が「今どこに車両がいるか」の
-- 唯一の情報源になります。詳しくは tests/harness.lua の before_process を参照してください。
local short = {}

----------------------------------------------------------------
-- スタートのtick: てこを操作してから最初の1サイクルを進めます
----------------------------------------------------------------
sw.nt:get_signal("NHB5R"):setInput(true)
h.tick(sw, short)

c:check("cycle1: 直後はまだ進路鎖錠が済んでいないのでHRは扛上しない",
    sw.nt:get_signal("NHB5R").HR, false)

----------------------------------------------------------------
-- 以後、6サイクル(script.luaのonTickが6回=1論理サイクルに相当。h.tick()の
-- 1回呼び出しがこれと同じ)ごとに在線状態を切り替えながら、その時々の状態を確認します
----------------------------------------------------------------

-- 1サイクル目: 在線なしのまま進める → 進路鎖錠が成立してHRが扛上する想定
h.tick(sw, short)
c:check("cycle2: 進路鎖錠成立でHRが扛上する", sw.nt:get_signal("NHB5R").HR, true)

-- 2サイクル目: 列車が着点(NHB5RT)に進入(在線あり)
short["NHB5RT"] = true
h.tick(sw, short)
c:check("cycle3: 在線した瞬間にHRは停止に落ちる", sw.nt:get_signal("NHB5R").HR, false)

-- 3サイクル目: 列車が引き続き在線
h.tick(sw, short)
c:check("cycle4: 在線が続く間、HRは停止のまま", sw.nt:get_signal("NHB5R").HR, false)

-- 4サイクル目: 列車が抜けて非在線に戻る
short["NHB5RT"] = false
h.tick(sw, short)
c:check("cycle5: 通過直後、進路鎖錠が生き残っていればHRが再び扛上する",
    sw.nt:get_signal("NHB5R").HR, true)

c:report()
