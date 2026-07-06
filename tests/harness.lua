-- N-TRACS テスト用ハーネス
--
-- Stormworks実機を介さずに、本番の路線構成(res/area_track.json, res/signal.toml)を
-- そのままロードしてロジックを検証するためのヘルパーです。
--
-- 事前準備: リポジトリルートで `node tests/gen_res.js` を実行し、res/area_track.lua と
-- res/signal.lua を最新の本番データから生成してください。
-- (両ファイルは .gitignore 対象のビルド生成物です。commit しないでください)
--
-- 実行方法（リポジトリルートから）: lua tests/repro_xxx.lua

local SoyaBridge = require("src.n_tracs_soyabridge.soya_bridge")

local M = {}

---本番構成一式(area_track, signal, switch, signal_alias)を読み込んだ SoyaBridge を作成します。
---@return SoyaBridge
function M.new_production_sw()
    local sw = SoyaBridge.new()
    require("res.area_track")(sw)
    require("res.signal")(sw)
    require("res.switch")(sw)
    require("res.signal_alias")(sw)
    return sw
end

---車両を使わず、在線状態を直接指定してテストを進めるための before_process 代替です。
---(SoyaBridge:before_process() は実車のaxle位置から在線を算出するため、車両を
--- スポーンさせないテストでは使えません。test.lua と同じ考え方です)
---@param sw SoyaBridge
---@param shortMap table<string, boolean> 在線させたい抽象軌道回路名の集合(true=在線)
local function before_process(sw, shortMap)
    shortMap = shortMap or {}
    for name, v in pairs(sw.nt.track) do
        v:before_process(shortMap[name] or false)
    end
    for _, v in pairs(sw.nt.switch) do
        v:before_process(v.W ~= 0 and v.W or v.K)
    end
    for _, v in pairs(sw.nt.signal) do
        v:before_process()
    end
end
M.before_process = before_process

---1サイクル進めます。script.lua の onTick は6tickごとに
---before_process -> process(6) の順で1サイクルとして処理しているため、
---本ハーネスの1回の tick() 呼び出しは実機の6tick・1サイクルに相当します。
---@param sw SoyaBridge
---@param shortMap table<string, boolean>
function M.tick(sw, shortMap)
    before_process(sw, shortMap)
    sw:process(6)
end

---ソフトアサート用チェッカー。途中で止めず失敗をすべて記録し、最後にまとめて
---報告します。「Nサイクル目時点の状態」を何箇所も確認したいテストに向いています。
local Checker = {}
Checker.__index = Checker

function M.new_checker()
    return setmetatable({ failed = 0, total = 0 }, Checker)
end

---@param label string どの時点・何を確認しているかが分かる説明
---@param actual any
---@param expected any
function Checker:check(label, actual, expected)
    self.total = self.total + 1
    if actual ~= expected then
        self.failed = self.failed + 1
        print(string.format("[NG] %s (expected=%s, actual=%s)", label, tostring(expected), tostring(actual)))
    else
        print(string.format("[OK] %s", label))
    end
end

---@return boolean success
function Checker:report()
    if self.failed > 0 then
        print(string.format("\n%d / %d 件のアサーションが失敗しました", self.failed, self.total))
        os.exit(1)
    else
        print(string.format("\n%d 件のアサーションはすべて成功しました", self.total))
    end
    return self.failed == 0
end

return M
