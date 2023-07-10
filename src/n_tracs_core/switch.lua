-- N-TRACS Core [Switch]

---@enum TargetRoute
TargetRoute = {
    Normal = 1,
    Reverse = 2,
    Indefinite = 0
}

---転てつ器に関する情報です
---@class Switch:NtracsObject
---@field private W TargetRoute
---@field private K TargetRoute
---@field private isSite boolean
---@field private relatedTracks Track[]
Switch = Switch or {}

---転てつ器情報を作成します
---@param itemName string 転てつ器名称
---@param isSite boolean 現場扱いの転てつ器ならばtrue
---@param relatedTracks Track[] てっ査鎖錠を行う抽象軌道回路
---@return Switch
function Switch.new(itemName, isSite, relatedTracks)
    return Switch.overWrite({}, itemName, isSite, relatedTracks)
end

---転てつ器情報を作成します
---@param baseObject table ベースとなるオブジェクト
---@param itemName string 転てつ器名称
---@param isSite boolean 現場扱いの転てつ器ならばtrue
---@param relatedTracks Track[] てっ査鎖錠を行う抽象軌道回路
---@return Switch
function Switch.overWrite(baseObject, itemName, isSite, relatedTracks)
    baseObject.name = "Switch"
    baseObject.itemName = itemName
    baseObject.W = TargetRoute.Indefinite
    baseObject.K = TargetRoute.Indefinite
    baseObject.isSite = isSite
    baseObject.relatedTracks = relatedTracks
    return baseObject
end

---現在の開通方向を取得します
---@return TargetRoute
function Switch:getRealRoute()
    return self.K
end

---[package]
---@package
---@param target TargetRoute
function Switch:move(target)
    if Switch.getWLR(self) then
        self.W = target
    end
end

---転換可能であればtrueを返却します
---@return boolean
function Switch:getWLR()
    for _, value in ipairs(self.relatedTracks) do
        if Track.isShort(value) or Track.isLocked(value, not self.isSite) then
            return false
        end
    end
    return true
end

---processの実行前に呼び出してください。現在の状態を設定します
---@param currentState TargetRoute 現在の開通方向
function Switch:beforeProcess(currentState)
    self.K = currentState
end

---毎ループごとに呼び出してください
---@param deltaTick number
function Switch:process(deltaTick)
end