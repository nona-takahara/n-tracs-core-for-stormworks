-- N-TRACS Core [Switch]

---@enum TargetRoute
TargetRoute = {
    Normal = 1,
    Reverse = -1,
    Indefinite = 0
}

---転てつ器に関する情報です
---@class Switch:NtracsObject
---@field W TargetRoute
---@field private K TargetRoute
---@field isSite boolean
---@field private relatedTracks Track[]
Switch = Switch or {}

---転てつ器情報を作成します
---@param itemName string 転てつ器名称
---@param isSite boolean 現場扱いの転てつ器ならばtrue
---@param relatedTracks Track[] てっ査鎖錠を行う抽象軌道回路
---@return Switch
function Switch.new()
    local obj = CreateInstance(NtracsObject.new(), Switch)
    obj.name = "Switch"
    return obj
end

---転てつ器情報を作成します
---@param itemName string 転てつ器名称
---@param isSite boolean 現場扱いの転てつ器ならばtrue
---@param relatedTracks Track[] てっ査鎖錠を行う抽象軌道回路
---@return Switch
function Switch.overWrite(self, itemName, isSite, relatedTracks)
    self = self or {}
    self.name = "Switch"
    self.itemName = itemName
    self.W = TargetRoute.Indefinite
    self.K = TargetRoute.Indefinite
    self.isSite = isSite
    self.relatedTracks = relatedTracks
    return self
end

---現在の開通方向を取得します
---@return TargetRoute
function Switch.getRealRoute(self)
    return self.K
end

---[package]
---@package
---@param target TargetRoute
function Switch.move(self, target)
    if Switch.getWLR(self) then
        self.W = target
    end
end

---転換可能であればtrueを返却します
---@return boolean
function Switch.getWLR(self)
    for _, value in ipairs(self.relatedTracks) do
        if value:isShort() or value:isLocked(not self.isSite) then
            return false
        end
    end
    return true
end

---processの実行前に呼び出してください。現在の状態を設定します
---@param currentState TargetRoute 現在の開通方向
function Switch.beforeProcess(self, currentState)
    self.K = currentState
    self.W = TargetRoute.Indefinite
end

---毎ループごとに呼び出してください
---@param deltaTick number
function Switch.process(self, deltaTick)
end
