-- N-TRACS Core [SwitchRoute]
local NtracsObject = require("src.n_tracs_core.n_tracs_object")

---転てつ器と開通方向の情報セットを扱います
---@class SwitchRoute:NtracsObject
---@field private rswitch string 関連転てつ器
---@field private target SignalRoute 開通希望方向
local SwitchRoute = {}

---転てつ器と開通方向の情報セットを作成します
---@param rswitch string
---@param target SignalRoute
---@return SwitchRoute
function SwitchRoute.new(rswitch, target)
    local obj = NtracsObject.createInstance(NtracsObject.new(), SwitchRoute)
    obj.name = "SwitchRoute"
    obj.rswitch = rswitch
    obj.target = target
    return obj
end

---開通方向が希望のものと同じか調べます
---@param nt Ntracs
---@return boolean
function SwitchRoute:isTargetRoute(nt)
    return nt.switches[self.rswitch]:getRealRoute() == self.target
end

---開通希望方向に転換します
---@param nt Ntracs
function SwitchRoute:moveToTarget(nt)
    nt.switches[self.rswitch]:move(self.target, nt)
end

---@param nt Ntracs
---@return Switch
function SwitchRoute:getRelatedSwitch(nt)
    return nt.switches[self.rswitch]
end

return SwitchRoute
