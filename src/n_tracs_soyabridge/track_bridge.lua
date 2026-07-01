local NtracsObject = require("src.n_tracs_core.n_tracs_object")
---@class TrackBridge
local TrackBridge = {}

---@class TrackBridge:NtracsObject
---@field name string
---@field itemName string
---@field area_ids number[]

---@param itemName string
---@param area_ids number[]
---@return TrackBridge
function TrackBridge.new(itemName, area_ids)
    local obj = NtracsObject.create_instance({}, TrackBridge)
    obj.name = "TrackBridge"
    obj.itemName = itemName
    obj.area_ids = area_ids
    return obj
end

---エリア群の中に輪軸が存在するか判定します
---@param sw SoyaBridge
---@return boolean
function TrackBridge:is_in_axle(sw)
    for _, area in ipairs(self.area_ids) do
        if sw.areas[area] and #(sw.areas[area].axles) > 0 then return true end
        --if #(sw.areas[area].axles) > 0 then return true end
    end
    return false
end

return TrackBridge
