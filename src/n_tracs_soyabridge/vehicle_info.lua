local NtracsObject = require "src.n_tracs_core.n_tracs_object"
---@class VehicleInfo
---@field axles Axle[] | nil
---@field bridges VehicleBridge | nil
local VehicleInfo = {}

---@return SWVehicleData, boolean
---@diagnostic disable-next-line: lowercase-global
local function oldGetVehicleData(vehicle_id)
    local vd, ss1 = server.getVehicleData(vehicle_id)
    local lvd, ss2 = server["getVehicleComponents"](vehicle_id)
    if ss1 and ss2 then
        ---@type SWVehicleData
        local r = {
            tags_full = vd.tags_full,
            tags = vd.tags,
            ---@diagnostic disable-next-line: assign-type-mismatch
            filename = nil,
            transform = vd.transform,
            simulating = vd.simulating,
            mass = lvd.mass,
            voxels = vd.voxels,
            editable = vd.editable,
            invulnerable = vd.invulnerable,
            static = vd.static,
            components = lvd.components
        }
        return r, true
    else
        ---@diagnostic disable-next-line: return-type-mismatch
        return nil, false
    end
end

---@param vehicle_id number
---@param vdata SWVehicleData
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
    local vdata, s = oldGetVehicleData(vehicle_id)
    if not s then return nil end
    local obj = NtracsObject.createInstance({}, VehicleInfo)
    obj.axles = LoadAxles(vehicle_id, vdata, false)
    obj.bridges = LoadBridgeDatas(vehicle_id, vdata)
    return obj
end

return VehicleInfo
