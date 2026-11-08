-- Web CTC の HTTP 通信（src/n_tracs_soyabridge/web_ctc.lua）を、server.httpGet を差し替えて確かめる。
-- 応答は httpReply の代わりに web:on_reply を直接呼んで返す。
-- 実行方法（リポジトリルートから）: lua tests/repro_web_ctc.lua

local h = require("tests.harness")
local SetRoute = require("src.n_tracs_core.switch.set_route")

-- Stormworks のグローバルを差し替える
ADDON_NAME, ADDON_SHORT_NAME, ADDON_VERSION, CTC_VERSION = "test", "test", "v0", "TEST-1"
dlog = function() end
local sent, announced = {}, {}
server = {
    httpGet = function(port, req) sent[#sent + 1] = { port = port, req = req } end,
    getTimeMillisec = function() return 123456789 end,
    announce = function(_, msg, peer) announced[#announced + 1] = { msg = msg, peer = peer } end,
    getPlayerCharacterID = function() return 0, false end,
}
g_savedata = {}

local WebCtc = require("src.n_tracs_soyabridge.web_ctc")
local apply_command = require("src.n_tracs_soyabridge.command")

local sw = h.new_production_sw()
local cmd = apply_command(sw)
local web = WebCtc.new(sw, CTC_VERSION, cmd.run_remote)
sw.web = web
local c = h.new_checker()

local MARKER = "N-TRACS for Stormworks/1"
local function chat(...) cmd.COMMANDS[(...)].command({ ... }, true, true, 0) end
local function last() return sent[#sent] end
local function answer(text, r) r = r or last(); web:on_reply(r.port, r.req, text) end
---条件を満たすまで tick を進める。進めた回数を返す（max を超えたら nil）
local function run_until(pred, max)
    for i = 1, max do
        web:tick(6)
        if pred() then return i end
    end
end
local function new_request()
    local n = #sent
    return function() return #sent > n end
end

-- 既定は無効
web:tick(6)
c:check("無効のあいだは送らない", #sent, 0)

-- 有効にすると、まず事実を載せない要求を送る
chat("web", "on")
c:check("web on で有効になる", g_savedata.webCtc, true)
web:tick(6)
c:check("有効にした最初の tick で送る", #sent, 1)
c:check("既定のポート", last().port, 8131)
c:check("つながる前は事実を載せない", last().req:match("^/ntracs/v1/state%?v=TEST%-1&b=%d+&s=1&c=0&end=1$") ~= nil, true)

-- サーバーがない: 印のない応答は失敗。間隔を延ばして、すぐには送らない
answer("connect(): Connection refused")
c:check("印のない応答ではつながらない", web.connected, false)
local n = #sent
web:tick(6)
c:check("失敗の直後は送らない", #sent, n)
c:check("間隔をおいて送り直す", run_until(new_request(), 400) ~= nil, true)
c:check("status はサーバーが見つからないと言う", web:status():find("server not found", 1, true) ~= nil, true)

-- 失敗が続くと間隔が延びる
answer("")
local gap1 = run_until(new_request(), 400)
answer("")
local gap2 = run_until(new_request(), 400)
c:check("失敗が続くと間隔が延びる", gap1 ~= nil and gap2 ~= nil and gap2 > gap1, true)

-- 応答が返らない: 待ち時間を過ぎたら失敗として扱い、また送る
c:check("応答がなくても、いずれ送り直す", run_until(new_request(), 2000) ~= nil, true)

-- サーバーが起動した: 印のある応答でつながり、次から事実を載せる
answer(MARKER .. "\r\n")
c:check("CRLF の印でもつながる", web.connected, true)
c:check("status はつながっていると言う", web:status():find("connected", 1, true) ~= nil, true)
web:tick(6)
c:check("つながったら事実を載せる", last().req:match("&c=%d+&[%w_.]+=%d+") ~= nil, true)
c:check("末尾の印で終わる", last().req:sub(-6), "&end=1")

-- 1 周すると全事実が届き、周回番号が進む
local seen, too_long = {}, 0
local function collect(r)
    if #r.req > 2000 then too_long = too_long + 1 end
    for k in r.req:gmatch("&([%w_.]+)=") do seen[k] = true end
end
collect(last())
for _ = 1, 50 do
    answer(MARKER)
    web:tick(6)
    collect(last())
    if web.cycle >= 1 then break end
end
local missing = 0
for _, f in ipairs(web.facts) do
    if not seen[f.key] then missing = missing + 1 end
end
c:check("1 周で全事実を送る", missing, 0)
c:check("周回番号が進む", web.cycle, 1)
c:check("URL は字数の予算に収まる", too_long, 0)

-- 変化した事実を先に送る。応答に載ったコマンドはチャットに出さない
answer(MARKER)
local before = #announced
answer(MARKER .. "\nset NHB12L\nweb off\nnosuchcommand x\n", { port = 8131, req = "/ntracs/v1/state?b=1&s=1" })
c:check("応答のコマンドを実行する", sw.nt:get_signal("NHB12L"):getInput(), true)
c:check("応答のコマンドの結果はチャットに出さない", #announced, before)
c:check("応答の web コマンドは実行しない", g_savedata.webCtc, true)
web:tick(6)
c:check("変化した事実を先頭に載せる", last().req:match("&c=%d+&([^&]+)"), "signal.NHB12L.input=1")

-- 遅れて届いた応答: 送信の状態には使わないが、コマンドは実行する
local late = last()
c:check("待ち時間を過ぎると失敗になる", run_until(function() return not web.connected end, 2000) ~= nil, true)
answer(MARKER .. "\nset NHB12R", late)
c:check("遅れた応答ではつながったことにしない", web.connected, false)
c:check("遅れた応答のコマンドは実行する", sw.nt:get_signal("NHB12R"):getInput(), true)

-- 無効にした後の応答は捨てる
web:tick(6)
chat("web", "off")
answer(MARKER .. "\nset NHB11L")
c:check("無効にした後の応答のコマンドは実行しない", sw.nt:get_signal("NHB11L"):getInput(), false)
n = #sent
for _ = 1, 100 do web:tick(6) end
c:check("無効のあいだは送らない（再）", #sent, n)

-- ポートの設定
chat("web", "port", "70000")
c:check("範囲外のポートは受け付けない", g_savedata.webCtcPort, nil)
chat("web", "port", "9000")
chat("web", "on")
web:tick(6)
c:check("設定したポートへ送る", last().port, 9000)
answer(MARKER .. "\nset NHB11L", { port = 8131, req = last().req })
c:check("前のポートの応答は捨てる", sw.nt:get_signal("NHB11L"):getInput(), false)

-- 通し番号は 999999 の次に 0 へ戻る
answer(MARKER)
web.seq = 999999
web:tick(6)
c:check("通し番号は一巡する", last().req:match("&s=(%d+)"), "0")

-- 転てつ機の要求は、次の process の直前に反映する。上で扛上させた NHB の進路と関係しない転てつ機で確かめる
chat("switch", "TKM21", "reverse")
c:check("要求を預かる", sw.switch_requests["TKM21"], SetRoute.Reverse)
h.tick(sw, {})
c:check("process で要求位置に反映する", sw.nt:get_switch("TKM21").W, SetRoute.Reverse)
c:check("反映した要求は消す", sw.switch_requests["TKM21"], nil)
chat("switch", "HLT_NHB_FR", "reverse")
c:check("方向てこの仮想転てつ機は受け付けない", sw.switch_requests["HLT_NHB_FR"], nil)
chat("switch", "TKM21", "sideways")
c:check("向きの誤りは受け付けない", sw.switch_requests["TKM21"], nil)

c:report()
