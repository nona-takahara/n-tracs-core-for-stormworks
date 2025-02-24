local NtracsObject = require "src.n_tracs_core.n_tracs_object"
local Axle         = require "src.n_tracs_soyabridge.axle"
local SetRoute     = require "src.n_tracs_core.set_route"
---@class VehicleInfo:NtracsObject
---@field vehicle_id number
---@field axles Axle[] | nil
---@field levers string[]
---@field tracks string[]
---@field points PointSetter[]
---@field arc_send boolean
---@field alias string[]
local VehicleInfo  = {}

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

---@param vehicle_id number
---@param sys SoyaBridge
---@return VehicleInfo | nil
function VehicleInfo.new(vehicle_id, sys)
    local vdata, s = server.getVehicleComponents(vehicle_id)
    if not s then return nil end

    local obj = NtracsObject.createInstance({}, VehicleInfo)
    local f = false
    obj.vehicle_id = vehicle_id
    obj.axles = LoadAxles(vehicle_id, vdata, false)
    obj.levers = {}
    obj.tracks = {}
    obj.points = {}
    obj.arc_send = false
    obj.alias = {}

    for _, button in ipairs(vdata.components.buttons) do
        --if button.name == "Activate CTC" then
        --    CTC = vehicle_id
        --end

        if button.name == "N-TRACS RESET" then
            f = true
        end

        -- 駅の実装負担軽減：宛先ペインタブルが無くても送信
        if button.name then
            local v, _ = (button.name):gsub("_ASPECT", "")
            if sys.leverAlias[v] then
                f = true
                table.insert(obj.alias, v)
            end
        end
    end
    if not f then return obj end

    for _, sign in ipairs(vdata.components.signs) do
        if sys.nt.tracks[sign.name] then
            table.insert(obj.tracks, sign.name)
            if not obj.arc_send then
                for _, dial in ipairs(vdata.components.buttons) do
                    if dial.name == sign.name .. "_ARC_L" then
                        obj.arc_send = true
                        break
                    end
                    if dial.name == sign.name .. "_ARC_R" then
                        obj.arc_send = true
                        break
                    end
                end
            end
        end
        if sys.pointList[sign.name] then
            table.insert(obj.points, sys.pointList[sign.name])
        end
        if sys.nt.levers[sign.name] then
            table.insert(obj.levers, sign.name)
        end
    end
    return obj
end

---@param sign number
---@param sys SoyaBridge
function VehicleInfo:send(sign, sys)
    for _, lever in ipairs(self.levers) do
        local sending = sys.nt.levers[lever].aspect
        server.setVehicleKeypad(self.vehicle_id, lever .. "_ASPECT", sending * SendingSign)
    end

    for _, alias in ipairs(self.alias) do
        local sending = sys.nt.levers[sys.leverAlias[alias]].aspect
        server.setVehicleKeypad(self.vehicle_id, alias .. "_ASPECT", sending * SendingSign)
    end

    for _, track in ipairs(self.tracks) do
        local sending = 1 - (sys.nt.tracks[track]:isShort() and 1 or 0)
        server.setVehicleKeypad(self.vehicle_id, track .. "R", sending * SendingSign)
        if self.arc_send then
            local right_arc = nil
            for _, area in ipairs(sys.trackBridge[track].areas) do
                if #area.axles > 0 then
                    if right_arc == nil then
                        server.setVehicleKeypad(self.vehicle_id, track .. "_ARC_L", area.axles[1].arc * SendingSign)
                    end
                    right_arc = area.axles[#area.axles].arc
                end
            end
            if right_arc ~= nil then
                server.setVehicleKeypad(self.vehicle_id, track .. "_ARC_R", right_arc * SendingSign)
            else
                server.setVehicleKeypad(self.vehicle_id, track .. "_ARC_L", 0)
                server.setVehicleKeypad(self.vehicle_id, track .. "_ARC_R", 0)
            end
        end
    end

    for _, point in ipairs(self.points) do
        if sys.nt.switches[point.switchName].W ~= SetRoute.Indefinite then
            server.setVehicleKeypad(self.vehicle_id, point.switchName .. "W", sys.nt.switches[point.switchName].W)
        end
    end
end

function VehicleInfo:chargeBattery(isCheatBattery)
    if isCheatBattery then
        server.setVehicleBattery(self.vehicle_id, "signal_bat", 3)
        server.setVehicleBattery(self.vehicle_id, "cheat_battery", 1)
    else
        server.setVehicleBattery(self.vehicle_id, "signal_bat", 3)
    end
end

return VehicleInfo
