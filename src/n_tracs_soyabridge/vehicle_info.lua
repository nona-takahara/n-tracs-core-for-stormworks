local NtracsObject  = require "src.n_tracs_core.n_tracs_object"
local VehicleBridge = require "src.n_tracs_soyabridge.vehicle_bridge"
local Axle          = require "src.n_tracs_soyabridge.axle"
---@class VehicleInfo:NtracsObject
---@field vehicle_id number
---@field axles Axle[] | nil
---@field bridges VehicleBridge | nil
local VehicleInfo   = {}

---@param vehicle_id number
---@param vdata SWLoadedVehicleData
---@param forceRegister boolean
---@return Axle[] | nil
local function LoadAxles(vehicle_id, vdata, forceRegister)
    ---@type Axle[]
    local axles = {}
    for _, sign in ipairs(vdata.components.signs) do
        if sign.name:find("TRAIN") == 1 then
            table.insert(axles, Axle.new(vehicle_id, sign.name, { x = sign.pos.x, y = sign.pos.y, z = sign.pos.z }))
        end
    end

    if forceRegister and #axles == 0 then
        axles = { [1] = Axle.new(vehicle_id, "", nil) }
    end
    return axles
end

function VehicleInfo.new(vehicle_id)
    local vdata, s = server.getVehicleComponents(vehicle_id)
    if not s then return nil end

    local obj = NtracsObject.createInstance({}, VehicleInfo)
    obj.axles = LoadAxles(vehicle_id, vdata, false)
    obj.bridges = VehicleBridge.new(vdata)
    obj.vehicle_id = vehicle_id
    return obj
end

function VehicleInfo:send(sign)
    if self.axles then
        for _, axle in pairs(self.axles) do
            axle:send(sign)
        end
    end
    if self.bridges then
        self.bridges:send(self.vehicle_id)
    end
end

function VehicleInfo:chargeBattery(isCheatBattery)
    self.bridges:chargeBattery(self.vehicle_id, isCheatBattery)
end

return VehicleInfo
