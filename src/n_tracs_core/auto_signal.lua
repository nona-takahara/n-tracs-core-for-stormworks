-- N-TRACS Core [Auto Signal]

---列車・車両の進行方向を表現します
---@enum RouteDirection
RouteDirection = {
    None = 0,
    Left = 1,
    Right = 2
}

---てこに関する操作を行います
---@class AutoSignal:SignalBase
---@field private signalTrack Track[]
AutoSignal = AutoSignal or {}

---てこ構造体のインスタンスを作成します
---@return AutoSignal
function AutoSignal.new()
    local obj = CreateInstance(SignalBase.new(), AutoSignal)
    obj.name = "AutoSignal"
    return obj
end

---てこ構造体のインスタンスを作成します
---@param self SignalBase
---@param itemName string てこ名称
---@param signalTrack Track[] 信号現示に関連する抽象軌道回路
---@param direction RouteDirection 進路てこの方向
---@param updateCallback fun(lever: Lever, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
---@return AutoSignal
function AutoSignal.overWrite(self, itemName, signalTrack, direction, updateCallback)
    self = CreateInstance(self, AutoSignal)
    self.name = "AutoSignal"
    self.itemName = itemName
    self.aspect = 0
    self.nextAspect = 0
    self.signalTrack = signalTrack
    self.direction = direction
    self.updateCallback = updateCallback
    return self
end

---信号現示を返します
---@return number
function AutoSignal.getAspect(self)
    return self.aspect
end

---processを呼び出す前に呼び出してください。現在の状態を設定します
function AutoSignal.beforeProcess(self)
    self.aspect = self.nextAspect
end

function AutoSignal.isNoShort(self)
    for _, track in ipairs(self.signalTrack) do
        if track:isShort() then
            return false
        end
    end
    return true
end

---毎ループごとに呼び出してください
---@param deltaTick number
function AutoSignal.process(self, deltaTick)
    self.HR = self:isNoShort()
    self.nextAspect = self:updateCallback(deltaTick)
    if not self.HR then
        self.nextAspect = 0
    end
end
