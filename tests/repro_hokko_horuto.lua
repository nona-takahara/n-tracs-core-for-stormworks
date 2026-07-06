local h = require("tests.harness")
local sw = h.new_production_sw()
local c = h.new_checker()

local short = { NHB5LT = true }

-- c1
h.tick(sw, short)
c:check("cycle1: 何もしていないのでNHB2L HRは落下", sw.nt:get_signal("NHB2L").HR, false)
c:check("cycle1: 何もしていないのでHLT1L HRは落下", sw.nt:get_signal("HLT1L").HR, false)

-- c2
sw.nt:get_signal("NHB2L"):setInput(true, sw.nt)
h.tick(sw, short)

-- c3
h.tick(sw, short)

-- c4
h.tick(sw, short)
c:check("cycle4: 進路成立、NHB2L 注意信号現示リレー扛上", sw.nt:get_signal("NHB2L").HR, true)

-- c5
h.tick(sw, short)
c:check("cycle5: 引き続き変化なし", sw.nt:get_signal("NHB2L").HR, true)

-- c6
short = { NHB5LT = true, HLT_NHB1T = true }
h.tick(sw, short)
c:check("cycle6: 内方進入。NHB2L 注意信号現示リレー落下", sw.nt:get_signal("NHB2L").HR, false)

-- c7,8
h.tick(sw, short)
h.tick(sw, short)
c:check("cycle8: 期待としてはauto_resetが効いてNHB2Lの入力が切れる", sw.nt:get_signal("NHB2L").input, false)

-- c9
short = { HLT_NHB1T = true }
h.tick(sw, short)

-- c10,11
sw.nt:get_signal("HLT1L"):setInput(true, sw.nt)
h.tick(sw, short)
h.tick(sw, short)
c:check("cycle11: 進路成立、HLT1L 注意信号現示リレー扛上", sw.nt:get_signal("HLT1L").HR, true)

-- c12
short = { HLT_NHB1T = true, HLT1LT = true }
h.tick(sw, short)
c:check("cycle12: 内方進入。HLT1L 注意信号現示リレー落下", sw.nt:get_signal("HLT1L").HR, false)

-- c13
h.tick(sw, short)
c:check("cycle13: 内方進入。HLT1L 進入保持リレー扛上", sw.nt:get_signal("HLT1L").TSSlR, true)

-- c14
h.tick(sw, short)
c:check("cycle14: 期待としてはauto_resetが効いてHLT1Lの入力が切れる", sw.nt:get_signal("HLT1L").input, false)

-- c15,16,17
short = { HLT1LT = true }
h.tick(sw, short)
sw.nt:get_signal("HLT1R"):setInput(true, sw.nt)
h.tick(sw, short)
h.tick(sw, short)
c:check("cycle17: 進路成立、HLT1R 注意信号現示リレー扛上", sw.nt:get_signal("HLT1R").HR, true)

-- c18.19その他のパターン検証
sw.nt:get_signal("HLT1L"):setInput(true, sw.nt)
sw.nt:get_signal("NHB2L"):setInput(true, sw.nt)
h.tick(sw, short)
h.tick(sw, short)
c:check("cycle19: 進路成立、HLT1R 注意信号現示リレー扛上", sw.nt:get_signal("HLT1R").HR, true)
c:check("cycle19: 進路不成立(HLT1L)", sw.nt:get_signal("HLT1L").HR, false)
c:check("cycle19: 進路不成立(NHB2L)", sw.nt:get_signal("NHB2L").HR, false)

c:report()
