-- ARC設定(res/arc.lua)の検査。index.js から、リポジトリルートで実行する。
-- 事前に res/area_track.lua と res/signal.lua が生成されている必要がある。誤りがあれば終了コード1で終わる。
package.path = "./?.lua;" .. package.path

local SoyaBridge = require("src.n_tracs_soyabridge.soya_bridge")
local ArcCheck = require("src.n_tracs_arc.arc_check")

local sw = SoyaBridge.new()
require("res.area_track")(sw)
require("res.signal")(sw)
require("res.switch")(sw)
require("res.signal_alias")(sw)

-- Arc本体は作らず、設定だけを受け取る
local config
require("res.arc")({ create_arc = function(_, c) config = c end })
if not config then
    io.stderr:write("res/arc.lua did not call sw:create_arc\n")
    os.exit(1)
end

local errors = ArcCheck.check(config, sw.nt)
if #errors > 0 then
    io.stderr:write(table.concat(errors, "\n") .. "\n")
    os.exit(1)
end
