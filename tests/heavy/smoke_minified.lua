-- minify 後のスクリプトが動くことを確かめる。外部ツール(storm-lua-minify)の検証なので、フルテストだけで実行する。
-- 実行(リポジトリルートから、ビルドのあとで): lua tests/heavy/smoke_minified.lua [スクリプト=dist/script.min.lua]
-- 最小のスタブで車両を1台読み込み、onTick を回す。落ちる、または車軸が車両IDを失っていれば失敗する。
local VEHICLE_ID = 1
local TICKS = 60

local function noop() return nil end
local components = {
    components = {
        signs = { { name = "TRAIN1", pos = { x = 0, y = 0, z = 0 } } },
        dials = {}, buttons = {}, batteries = {}, seats = {}, sliders = {}, indicators = {}, guns = {}, rope_hooks = {}, hoppers = {},
    },
}
local calls, wrong_id = 0, 0

server = setmetatable({
    getVehicleComponents = function() return components, true end,
    getVehiclePos = function(id)
        calls = calls + 1
        if id ~= VEHICLE_ID then wrong_id = wrong_id + 1 end
        return "M", true
    end,
    getVehicleDial = function() return { value = 0 }, true end,
    getPlayers = function() return {} end,
}, { __index = function() return noop end })
property = setmetatable({}, { __index = function() return function(_, default) return default end end })
matrix = setmetatable({ position = function() return 1350, 0, -3751 end }, { __index = function() return noop end })

assert(loadfile(arg[1] or "dist/script.min.lua"))()
onCreate(false)
for _ = 1, TICKS do onTick(1) end
onVehicleLoad(VEHICLE_ID)
for _ = 1, TICKS do onTick(1) end

print(string.format("getVehiclePos %d 回 / 車両IDの誤り %d 回", calls, wrong_id))
if calls == 0 or wrong_id > 0 then os.exit(1) end
