-- N-TRACS Core [Switch]
local NtracsObject           = require("src.n_tracs_core.n_tracs_object")
local SetRoute               = require("src.n_tracs_core.switch.set_route")
local Switch                 = require("src.n_tracs_core.switch.switch")

---転てつ器に関する情報です
---@class TrafficDirectionSwitch:Switch
---@field W SetRoute
---@field isSite true
---@field private relatedTracks string[]
local TrafficDirectionSwitch = {}

---転てつ器情報を作成します
---@param itemName string 転てつ器名称
---@param relatedTracks string[] てっ査鎖錠を行う抽象軌道回路
---@return Switch
function TrafficDirectionSwitch.new(itemName, relatedTracks)
    local obj = NtracsObject.create_instance({}, TrafficDirectionSwitch)
    obj.name = "TrafficDirectionSwitch"
    obj.itemName = itemName
    obj.W = SetRoute.Indefinite
    obj.isSite = true
    obj.relatedTracks = relatedTracks
    return obj
end

---現在の開通方向を取得します
---@return SetRoute
function TrafficDirectionSwitch:getRealRoute()
    return self.W
end

---@param target SetRoute
---@param nt Ntracs
function TrafficDirectionSwitch:move(target, nt)
    if self:getWLR(nt) then
        self.W = target
    end
end

---転換可能であればtrueを返却します
---@param nt Ntracs
---@return boolean
function TrafficDirectionSwitch:getWLR(nt)
    for _, value in ipairs(self.relatedTracks) do
        if nt:get_track(value):is_short() or nt:get_track(value):is_locked(not self.isSite) then
            return false
        end
    end
    return true
end

---processの実行前に呼び出してください。現在の状態を設定します
---@param currentState SetRoute 現在の開通方向
function TrafficDirectionSwitch:beforeProcess(currentState)
end

---毎ループごとに呼び出してください
---@param deltaTick number
---@param nt Ntracs
function TrafficDirectionSwitch:process(deltaTick, nt)
end

return TrafficDirectionSwitch
