-- N-TRACS Core [Switch]
local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local SetRoute     = require("src.n_tracs_core.switch.set_route")

---転てつ器に関する情報です
---@class Switch:NtracsObject
---@field W SetRoute
---@field private K SetRoute
---@field isSite boolean
---@field private relatedTracks string[]
local Switch       = {}

---転てつ器情報を作成します
---@param itemName string 転てつ器名称
---@param isSite boolean 現場扱いの転てつ器ならばtrue
---@param relatedTracks string[] てっ査鎖錠を行う抽象軌道回路
---@return Switch
function Switch.new(itemName, isSite, relatedTracks)
    local obj = NtracsObject.createInstance({}, Switch)
    obj.name = "Switch"
    obj.itemName = itemName
    obj.W = SetRoute.Indefinite
    obj.K = SetRoute.Indefinite
    obj.isSite = isSite
    obj.relatedTracks = relatedTracks
    return obj
end

---現在の開通方向を取得します
---@return SetRoute
function Switch:getRealRoute()
    return self.K
end

---@param target SetRoute
---@param nt Ntracs
function Switch:move(target, nt)
    if self:getWLR(nt) then
        self.W = target
    end
end

---転換可能であればtrueを返却します
---@param nt Ntracs
---@return boolean
function Switch:getWLR(nt)
    for _, value in ipairs(self.relatedTracks) do
        if nt:get_track(value):is_short() or nt:get_track(value):is_locked(not self.isSite) then
            return false
        end
    end
    return true
end

---processの実行前に呼び出してください。現在の状態を設定します
---@param currentState SetRoute 現在の開通方向
function Switch:beforeProcess(currentState)
    self.K = currentState
    self.W = SetRoute.Indefinite
end

---毎ループごとに呼び出してください
---@param deltaTick number
---@param nt Ntracs
function Switch:process(deltaTick, nt)
end

return Switch
