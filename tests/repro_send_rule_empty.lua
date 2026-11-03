-- 空 Area の条件評価省略と、ジェネレータによる送信先のない条件木の除去を確認する。
local h = require("tests.harness")
local SoyaBridge = require("src.n_tracs_soyabridge.soya_bridge")
local c = h.new_checker()
local pipe = assert(io.popen("node tests/fixtures/generate_empty_send_rules.js", "r"))
local source = pipe:read("a")
local ok = pipe:close()
assert(ok, "fixture generation failed")
local fixture = assert(load(source, "empty send rules"))()
local sw = SoyaBridge.new()
local signalReads, enabled = {}, {}
local watchBeforeCondition
sw.nt.get_signal = function(_, name)
    signalReads[#signalReads + 1] = name
    if name == "D" then
        local op = sw.nt:get_track("TRACK").timerOps["check:0"]
        watchBeforeCondition = op and op.reset
    end
    return { HR = enabled[name] ~= false }
end
fixture.compact(sw)
c:check("生成物から送信先のない条件を除去", source:find("NO_SEND", 1, true), nil)
local track = sw.nt:get_track("TRACK")
local function callback(id)
    return sw.areas[id].updateCallback(sw.areas[id], sw.nt, 6)
end
local function occupy(id, pos)
    local axle = { sending = {}, real_pos = { x = pos or 0, z = 0 }, delta_pos = { x = 20, z = 0 }, velocity = 20 }
    sw.areas[id].axles = { axle }
    return axle
end
local function sent(axle) return table.concat(axle.sending, ",") end
local function update()
    track:before_process(false)
    track:process(sw.nt, 6)
end

-- C は空なら信号条件を一度も読まず、占有されれば毎周期送信する。
callback(1)
c:check("C: 空 Area は信号条件を読まない", #signalReads, 0)
local axle = occupy(1)
callback(1)
c:check("C: 在線時に送信", sent(axle), "12,34")
axle.sending = {}
callback(1)
c:check("C: 同じ値でも次周期の送信を継続", sent(axle), "12,34")
sw.areas[1].axles = {}
signalReads = {}
callback(1)
c:check("C: 在線消失後は再び条件を読まない", #signalReads, 0)

-- D は空でも監視を動かす。境界の直前・到達時・超過後を複数周期で確認する。
callback(2)
update()
c:check("D: 未始動のタイマーを勝手に始めない", track:get_timer("check:0"), 0)
track.timers["check:0"] = 6
callback(2)
c:check("D: 空 Area の送信条件は読まない", #signalReads, 0)
update()
c:check("D: 空でもタイマーは進む", track:get_timer("check:0"), 12)
callback(2)
update()
c:check("D: hold 到達時も従来の条件で進む", track:get_timer("check:0"), 18)
callback(2)
update()
c:check("D: hold 超過後は進めない", track:get_timer("check:0"), 18)
axle = occupy(2, 1) -- 前周期 x=-1 → 現周期 x=1。照査点を横切る。
callback(2)
c:check("D: 在線時は条件評価と送信を行う", sent(axle), "12,34")
c:check("D: 送信条件を読む前に照査点の監視を行う", watchBeforeCondition, true)
update()
c:check("D: 照査点通過でタイマーを再始動", track:get_timer("check:0"), 6)
sw.areas[2].axles = {}
callback(2)
update()
c:check("D: 列車が去ったあともタイマーが進む", track:get_timer("check:0"), 12)

-- 生成時に送信のない木を除去しても、監視は残る。
signalReads = {}
callback(3)
occupy(3)
callback(3)
c:check("送信先のない C は在線の有無によらず条件を読まない", #signalReads, 0)
track.timers["check:0"] = 6
callback(4)
update()
c:check("送信先のない D も空 Area でタイマーを進める", track:get_timer("check:0"), 12)
occupy(4, 1)
callback(4)
update()
c:check("送信先のない D も照査点通過を監視", track:get_timer("check:0"), 6)
c:check("送信先のない D は条件を読まない", #signalReads, 0)

-- 途中の nil 行は、後続・親の送信を抑止するため残す。
axle = occupy(8)
callback(8)
c:check("nil 行に一致すると後続を送信しない", sent(axle), "")
enabled.STOP = false
callback(8)
c:check("nil 行に不一致なら後続を送信", sent(axle), "12,34")
axle = occupy(9)
callback(9)
c:check("nil 行の子に一致すると親を送信しない", sent(axle), "")
enabled.CHILD = false
callback(9)
c:check("子が不一致なら親を送信", sent(axle), "12,34")
axle = occupy(10)
enabled.CHILD = true
callback(10)
c:check("行を省略した子は親の送信を継承", sent(axle), "12,34")

-- before_broadcast 全体は止めない。任意 Lua、複数 part、メタデータなしは空でも呼ぶ。
for _, area in pairs(sw.areas) do area.axles = {} end
sw.customCalls = 0
sw:before_broadcast(6)
c:check("空 Area でも任意 Lua 等のコールバックをすべて実行", sw.customCalls, 4)
c:check("任意コールバックの戻り値を cbdata に保存", sw.areas[5].cbdata, 6)
local other = SoyaBridge.new()
fixture.no_definitions(other)
other:before_broadcast(6)
c:check("send_definitions がない場合も元のコールバックを実行", other.customCalls, 1)

c:report()
