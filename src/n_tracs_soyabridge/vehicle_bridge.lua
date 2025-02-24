local NtracsObject = require "src.n_tracs_core.n_tracs_object"
---@class VehicleBridge
---@field levers Lever[]
---@field tracks Track[]
---@field points PointSetter[]
---@field arc_send boolean
---@field alias string[]
local VehicleBridge = {}

---@param vehicle_id number
---@param vdata SWVehicleData
---@return VehicleBridge | nil
function VehicleBridge.new(vehicle_id, vdata)
    if not vdata then return nil end
    local f = false
    local bridges = NtracsObject.createInstance({ tracks = {}, levers = {}, points = {}, arc_send = false, alias = {} },
        VehicleBridge)

    for _, button in ipairs(vdata.components.buttons) do
        if button.name == "Activate CTC" then
            CTC = vehicle_id
        end

        if button.name == "N-TRACS RESET" then
            f = true
        end

        -- 駅の実装負担軽減：宛先ペインタブルが無くても送信
        if button.name then
            local v, _ = (button.name):gsub("_ASPECT", "")
            if BRIDGE_LEVER_ALIAS[v] then
                f = true
                table.insert(bridges.alias, v)
            end
        end
    end
    if not f then return nil end

    for _, sign in ipairs(vdata.components.signs) do
        if TRACKS[sign.name] then
            table.insert(bridges.tracks, TRACKS[sign.name])
            if not bridges.arc_send then
                for _, dial in ipairs(vdata.components.buttons) do
                    if dial.name == sign.name .. "_ARC_L" then
                        bridges.arc_send = true
                        break
                    end
                    if dial.name == sign.name .. "_ARC_R" then
                        bridges.arc_send = true
                        break
                    end
                end
            end
        end
        if POINTLIST[sign.name] then
            table.insert(bridges.points, POINTLIST[sign.name])
        end
        if LEVERS[sign.name] then
            table.insert(bridges.levers, LEVERS[sign.name])
        end
    end

    return bridges
end

---comments
---@param vehicle_id number
function VehicleBridge:send(vehicle_id)
    for _, lever in ipairs(self.levers) do
        local sending = lever.aspect
        server.setVehicleKeypad(vehicle_id, lever.itemName .. "_ASPECT", sending * SendingSign)
    end

    for _, alias in ipairs(self.alias) do
        local sending = BRIDGE_LEVER_ALIAS[alias].aspect
        server.setVehicleKeypad(vehicle_id, alias .. "_ASPECT", sending * SendingSign)
    end

    for _, track in ipairs(self.tracks) do
        local sending = 1 - (track.short and 1 or 0)
        server.setVehicleKeypad(vehicle_id, track.itemName .. "R", sending * SendingSign)
        if self.arc_send then
            local right_arc = nil
            for _, area in ipairs(BRIDGE_TRACK[track.itemName].areas) do
                if #area.axles > 0 then
                    if right_arc == nil then
                        server.setVehicleKeypad(vehicle_id, track.itemName .. "_ARC_L", area.axles[1].arc * SendingSign)
                    end
                    right_arc = area.axles[#area.axles].arc
                end
            end
            if right_arc ~= nil then
                server.setVehicleKeypad(vehicle_id, track.itemName .. "_ARC_R", right_arc * SendingSign)
            else
                server.setVehicleKeypad(vehicle_id, track.itemName .. "_ARC_L", 0)
                server.setVehicleKeypad(vehicle_id, track.itemName .. "_ARC_R", 0)
            end
        end
    end

    for _, point in ipairs(self.points) do
        if SWITCHES[point.switchName].W ~= TargetRoute.Indefinite then
            server.setVehicleKeypad(vehicle_id, point.switchName .. "W", SWITCHES[point.switchName].W)
        end

        local sending = Switch.getWLR(SWITCHES[point.switchName]) and 1 or 0
        server.setVehicleKeypad(vehicle_id, point.switchName .. "WLR", sending * SendingSign)
    end
end
