---@class SwitchBridge
SwitchBridge = SwitchBridge or {}

---@class SwitchBridge
---@field name string
---@field itemName string
---@field pointAndRoute table<string,TargetRoute>

---@class PointSetter
---@field name string
---@field pointName string
---@field switchName string
---@field set function

-- 役割：複数ビークルからなるSwitchを束ねる

---comments
---@param self SwitchBridge
---@param name string
---@return PointSetter
function SwitchBridge.getPointSetter(self, name)
    return {
        name = "PointSetter",
        pointName = name,
        switchName = self.itemName,
        set = function (state)
            self.pointAndRoute[name] = state
        end
    }
end

---comments
---@param self SwitchBridge
---@return TargetRoute
function SwitchBridge.getState(self)
    ---@type TargetRoute | nil
    local s = nil
    for _, value in pairs(self.pointAndRoute) do
        if s == nil then s = value end
        if s ~= value then return TargetRoute.Indefinite end
    end
    return s or TargetRoute.Indefinite
end
