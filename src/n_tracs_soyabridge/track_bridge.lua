local NtracsObject = require("src.n_tracs_core.n_tracs_object")
---@class TrackBridge
local TrackBridge = {}

---@class TrackBridge:NtracsObject
---@field name string
---@field itemName string
---@field areas Area[]

---@param itemName string
---@param areas Area[]
---@return TrackBridge
function TrackBridge.new(itemName, areas)
    local obj = NtracsObject.create_instance({}, TrackBridge)
    obj.name = "TrackBridge"
    obj.itemName = itemName
    obj.areas = areas
    return obj
end

---エリア群の中に輪軸が存在するか判定します
---@return boolean
function TrackBridge:isInAxle()
    for _, area in ipairs(self.areas) do
        if #(area.axles) > 0 then return true end
    end
    return false
end

return TrackBridge
