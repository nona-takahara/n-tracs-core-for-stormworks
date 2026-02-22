local NtracsObject = require("src.n_tracs_core.n_tracs_object")

---転てつ器と開通方向の情報セットを扱います
---@class SwitchRoute:NtracsObject
---@field switch string 関連転てつ器
---@field target SignalRoute 開通希望方向
local SwitchRoute = {}

---@param switch string
---@param target SignalRoute
---@return SwitchRoute
function SwitchRoute.new(switch, target)
    local obj = NtracsObject.create_instance({}, SwitchRoute)
    obj.name = "SwitchRoute"
    obj.switch = switch
    obj.target = target
    return obj
end

---@param nt Ntracs
function SwitchRoute:check(nt)
    return nt:get_switch(self.switch).K ~= self.target
end

return SwitchRoute
