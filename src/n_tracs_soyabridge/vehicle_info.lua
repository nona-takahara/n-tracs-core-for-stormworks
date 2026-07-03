local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local Axle         = require("src.n_tracs_soyabridge.axle")
local SetRoute     = require("src.n_tracs_core.switch.set_route")
---@class VehicleInfo:NtracsObject
---@field vehicle_id number
---@field axles Axle[]
---@field signals string[]
---@field tracks string[]
---@field points PointSetter[]
---@field arc_send boolean
---@field alias string[]
local VehicleInfo  = {}

---@param vehicle_id number
---@param vdata SWLoadedVehicleData
---@param forceRegister boolean
---@return Axle[]
local function load_axles(vehicle_id, vdata, forceRegister)
    ---@type Axle[]
    local axles = {}
    for _, sign in ipairs(vdata.components.signs) do
        if sign.name:find("TRAIN") == 1 then
            local a = Axle.new(vehicle_id, sign.name, { x = sign.pos.x, y = sign.pos.y, z = sign.pos.z })
            a:get_position(0)
            a:clear_velocity()
            table.insert(axles, a)
        end
    end

    if forceRegister and #axles == 0 then
        axles = { [1] = Axle.new(vehicle_id, "", nil) }
    end
    return axles
end

---@param vehicle_id number
---@param sw SoyaBridge
---@return VehicleInfo | nil
function VehicleInfo.new(vehicle_id, sw)
    local vdata, s = server.getVehicleComponents(vehicle_id)
    if not s then return nil end

    local obj = NtracsObject.create_instance({}, VehicleInfo)
    local f = false
    obj.vehicle_id = vehicle_id
    obj.axles = load_axles(vehicle_id, vdata, false)
    obj.signals = {}
    obj.tracks = {}
    obj.points = {}
    obj.arc_send = false
    obj.alias = {}

    for _, button in ipairs(vdata.components.buttons) do
        if button.name == "N-TRACS RESET" then
            f = true
        end

        -- 駅の実装負担軽減：宛先ペインタブルが無くても送信
        if button.name then
            local v, _ = (button.name):gsub("_ASPECT", "")
            if sw.lever_alias[v] then
                f = true
                table.insert(obj.alias, v)
            end
        end
    end
    if not f then return obj end

    for _, sign in ipairs(vdata.components.signs) do
        if sw.nt:get_track_may_nil(sign.name) then
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
        if sw.points[sign.name] then
            table.insert(obj.points, sw.points[sign.name])
        end
        if sw.nt:get_signal_may_nil(sign.name) then
            table.insert(obj.signals, sign.name)
        end
    end
    return obj
end

---@param sign number
---@param sw SoyaBridge
function VehicleInfo:send(sign, sw)
    for _, lever in ipairs(self.signals) do
        local sending = sw.nt:get_signal(lever).aspect
        server.setVehicleKeypad(self.vehicle_id, lever .. "_ASPECT", sending * sign)
    end

    for _, alias in ipairs(self.alias) do
        local sending = sw.nt:get_signal(sw.lever_alias[alias]).aspect
        server.setVehicleKeypad(self.vehicle_id, alias .. "_ASPECT", sending * sign)
    end

    for _, track in ipairs(self.tracks) do
        local sending = 1 - (sw.nt:get_track(track):is_short() and 1 or 0)
        server.setVehicleKeypad(self.vehicle_id, track .. "R", sending * sign)
        if self.arc_send then
            local right_arc = nil
            for _, area in ipairs(sw.track_bridge[track].area_ids) do
                -- NOTE: このnilチェック(sw.areas[area])は本来不要
                if sw.areas[area] and #sw.areas[area].axles > 0 then
                    if right_arc == nil then
                        server.setVehicleKeypad(self.vehicle_id, track .. "_ARC_L",
                            sw.areas[area].axles[1].arc * sign)
                    end
                    right_arc = sw.areas[area].axles[#sw.areas[area].axles].arc
                end
            end
            if right_arc ~= nil then
                server.setVehicleKeypad(self.vehicle_id, track .. "_ARC_R", right_arc * sign)
            else
                server.setVehicleKeypad(self.vehicle_id, track .. "_ARC_L", 0)
                server.setVehicleKeypad(self.vehicle_id, track .. "_ARC_R", 0)
            end
        end
    end

    for _, point in ipairs(self.points) do
        if sw.nt:get_switch(point.switchName).W ~= SetRoute.Indefinite then
            server.setVehicleKeypad(self.vehicle_id, point.switchName .. "W", sw.nt:get_switch(point.switchName).W)
        end
    end

    for _, axle in ipairs(self.axles) do
        axle:send(sign)
    end
end

function VehicleInfo:get_vehicle_data(dt)
    if self.axles then
        for _, axle in ipairs(self.axles) do
            axle:get_position(dt)
        end
    end

    if self.points then
        for _, setter in ipairs(self.points) do
            local dial, ss = server.getVehicleDial(self.vehicle_id, setter.pointName .. "K")
            if ss then
                setter.set(dial.value)
                --else
                --ARCを実装したら 0 にするようにする。
                --setter.set(0)
            end
        end
    end
end

function VehicleInfo:charge_battery(isCheatBattery)
    if isCheatBattery then
        server.setVehicleBattery(self.vehicle_id, "signal_bat", 3)
        server.setVehicleBattery(self.vehicle_id, "cheat_battery", 1)
        server.setVehicleBattery(self.vehicle_id, "cheat_battery1", 1)
        server.setVehicleBattery(self.vehicle_id, "cheat_battery2", 2)
    else
        server.setVehicleBattery(self.vehicle_id, "signal_bat", 3)
    end
end

return VehicleInfo
