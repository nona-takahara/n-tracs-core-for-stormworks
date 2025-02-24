local SetRoute = require("src.n_tracs_core.set_route")
local NtracsObject = require("src.n_tracs_core.n_tracs_object")
---@class SwitchBridge
local SwitchBridge = {}

---@class SwitchBridge:NtracsObject
---@field name string
---@field itemName string
---@field pointAndRoute table<string,SetRoute>

---@class PointSetter
---@field name string
---@field pointName string
---@field switchName string
---@field set function

-- 役割：複数ビークルからなるSwitchを束ねる

function SwitchBridge.new(itemName, pointlist)
    local obj = NtracsObject.createInstance({}, SwitchBridge)
    obj.name = "SwitchBridge"
    obj.itemName = itemName
    local par = {}
    for _, key in ipairs(pointlist) do
        par[key] = SetRoute.Indefinite
    end
    obj.pointAndRoute = par
    return obj
end

---@param name string
---@return PointSetter
function SwitchBridge:getPointSetter(name)
    return {
        name = "PointSetter",
        pointName = name,
        switchName = self.itemName,
        set = function(state)
            self.pointAndRoute[name] = state
        end
    }
end

---@return SetRoute
function SwitchBridge:getState()
    ---@type SetRoute | nil
    local s = nil
    for _, value in pairs(self.pointAndRoute) do
        if s == nil then s = value end
        if s ~= value then return SetRoute.Indefinite end
    end
    return s or SetRoute.Indefinite
end

return SwitchBridge
