-- N-TRACS Core [Opening Lever] 開通てこ
-- 信号を現示せず、過走防護区間のデフォルト開通方向をTOML固定であらかじめ宣言します。
-- 実際にこの区間を進路(route_lock/destination)として使う信号機の本予約によって自然に明け渡されますが、
-- この区間を過走防護区間(overrun_lock)として使うだけの信号機には、所有権を奪われません
-- (Track:is_over_run_lockの拡張により、方向一致だけで保護成立とみなされるため)。

local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local SignalBase = require("src.n_tracs_core.signal.signal_base")

---@class OpeningLever:SignalBase
---@field direction RouteDirection
---@field private overrunLock string[]
local OpeningLever = {}

---@param itemName string てこ名称
---@param direction RouteDirection 既定で開通させる方向
---@param overrunLock string[] 開通方向を宣言する対象の抽象軌道回路
---@return OpeningLever
function OpeningLever.new(itemName, direction, overrunLock)
    local obj = NtracsObject.create_instance(SignalBase.new(), OpeningLever)
    obj.name = "OpeningLever"
    obj.itemName = itemName
    obj.direction = direction
    obj.overrunLock = overrunLock
    return obj
end

---毎ループごとに呼び出してください
---@param deltaTick number
---@param nt Ntracs
function OpeningLever:process(deltaTick, nt)
    for _, trackName in ipairs(self.overrunLock) do
        local track = nt:get_track(trackName)
        if track:is_claimable_for_opening(self.itemName) then
            track:book_opening(self.itemName, nt)
        end
    end
end

function OpeningLever:before_process()
end

---進路鎖錠が成立していたらfalseを返します(開通てこは在線解除だけでは自動解放しないため常にfalse)
---@return boolean
function OpeningLever:under_route_lock_b()
    return false
end

---このてこが開通てこであることを示します
---@return boolean
function OpeningLever:is_opening_lever()
    return true
end

return OpeningLever
