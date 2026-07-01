local SetRoute = require("src.n_tracs_core.switch.set_route")
local NtracsObject = require("src.n_tracs_core.n_tracs_object")
---@class SwitchBridge
local SwitchBridge = {}

---@class SwitchBridge:NtracsObject
---@field name string
---@field itemName string
---@field points table<string,SetRoute>

---@class PointSetter
---@field name string
---@field pointName string
---@field switchName string
---@field set function

-- 役割：複数ビークルからなるSwitchを束ねる

function SwitchBridge.new(itemName, pointlist)
    local obj = NtracsObject.create_instance({}, SwitchBridge)
    obj.name = "SwitchBridge"
    obj.itemName = itemName
    local par = {}
    for _, key in ipairs(pointlist) do
        par[key] = SetRoute.Indefinite
    end
    obj.points = par
    return obj
end

---@param name string
---@return PointSetter
function SwitchBridge:get_point_setter(name)
    return {
        name = "PointSetter",
        pointName = name,
        switchName = self.itemName,
        set = function(state)
            self.points[name] = state
        end
    }
end

---@return SetRoute
function SwitchBridge:get_state()
    ---@type SetRoute | nil
    local s = nil
    for _, value in pairs(self.points) do
        if s == nil then s = value end
        if s ~= value then return SetRoute.Indefinite end
    end
    return s or SetRoute.Indefinite
end

return SwitchBridge
