---@class TrackBridge
TrackBridge = TrackBridge or {}

---@class TrackBridge
---@field name string
---@field itemName string
---@field areas Area[]


---@param itemName string
---@param areas Area[]
---@return TrackBridge
function TrackBridge.new(itemName, areas)
    return TrackBridge.overWrite(nil, itemName, areas)
end

---
---@param baseObject any
---@param itemName string
---@param areas Area[]
---@return TrackBridge
function TrackBridge.overWrite(baseObject, itemName, areas)
    baseObject = baseObject or {}
    baseObject.name = "TrackBridge"
    baseObject.itemName = itemName
    baseObject.areas = areas
    return baseObject
end

---エリア群の中に輪軸が存在するか判定します
---@param self TrackBridge
---@return boolean
function TrackBridge.isInAxle(self)
    for _, area in ipairs(self.areas) do
        if #(area.axles) > 0 then return true end
    end
    return false
end
