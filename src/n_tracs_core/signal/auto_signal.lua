-- N-TRACS Core [Auto Signal]

local NtracsOjbect = require("src.n_tracs_core.n_tracs_object")

---てこに関する操作を行います
---@class AutoSignal:SignalBase
---@field private signalTrack string[]
local AutoSignal   = {}

---てこ構造体のインスタンスを作成します
---@param itemName string てこ名称
---@param signalTrack string[] 信号現示に関連する抽象軌道回路
---@param direction RouteDirection 進路てこの方向
---@param updateCallback fun(lever: Signal, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
---@return AutoSignal
function AutoSignal.new(itemName, signalTrack, direction, updateCallback)
    local obj = NtracsOjbect.create_instance({}, AutoSignal)
    obj.name = "AutoSignal"
    obj.itemName = itemName
    obj.aspect = 0
    obj.nextAspect = 0
    obj.signalTrack = signalTrack
    obj.direction = direction
    obj.updateCallback = updateCallback
    return obj
end

---信号現示を返します
---@return number
function AutoSignal:getAspect()
    return self.aspect
end

---processを呼び出す前に呼び出してください。現在の状態を設定します
function AutoSignal:beforeProcess()
    self.aspect = self.nextAspect
end

---@param nt Ntracs
---@return boolean
function AutoSignal:is_no_short(nt)
    for _, track in ipairs(self.signalTrack) do
        if nt:get_track(track):is_short() then
            return false
        end
    end
    return true
end

---毎ループごとに呼び出してください
---@param deltaTick number
---@param nt Ntracs
function AutoSignal:process(deltaTick, nt)
    self.HR = self:is_no_short(nt)
    self.nextAspect = self:updateCallback(deltaTick)
    if not self.HR then
        self.nextAspect = 0
    end
end

return AutoSignal
