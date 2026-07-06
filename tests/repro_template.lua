local h = require("tests.harness")

-- 本番構成一式をロードします(実際のゲーム内と同じ信号機・軌道回路・転てつ器)
local sw = h.new_production_sw()
local c = h.new_checker()

-- 在線(車両がその抽象軌道回路上にいる)状態は、テスト側でこの table を書き換えて
-- 明示的に指定します。実車を使わないため、この table が「今どこに車両がいるか」の
-- 唯一の情報源になります。詳しくは tests/harness.lua の before_process を参照してください。
local short = { NHB13RT = true }

-- c1
h.tick(sw, short)
c:check("cycle1: 何もしていないのでHRは落下", sw.nt:get_signal("NHB12L").HR, false)

-- c2
sw.nt:get_signal("NHB12L"):setInput(true)
h.tick(sw, short)

-- c3
h.tick(sw, short)
c:check("cycle3: 進路成立、注意信号現示リレー扛上", sw.nt:get_signal("NHB12L").HR, true)

-- c4
h.tick(sw, short)
c:check("cycle4: 引き続き変化なし", sw.nt:get_signal("NHB12L").HR, true)

-- c5
short = { NHB13RT = true, NHB23T = true }
h.tick(sw, short)
c:check("cycle5: 内方進入。注意信号現示リレー落下", sw.nt:get_signal("NHB12L").HR, false)

-- c6
h.tick(sw, short)
c:check("cycle6: 引き続き落下", sw.nt:get_signal("NHB12L").HR, false)

-- c7
short = { NHB13RT = true, NHB23T = true, NHB22AT = true }
h.tick(sw, short)
c:check("cycle7: 内方第2トラック短絡、TSSlR扛上", sw.nt:get_signal("NHB12L").TSSlR, true)

-- c8
h.tick(sw, short)
c:check("cycle8: TSSlRによって入力キャンセル", sw.nt:get_signal("NHB12L").input, false)

c:report()
