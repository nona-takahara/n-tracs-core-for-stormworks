local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local Ntracs       = require("src.n_tracs_core.ntracs")
local Area         = require("src.n_tracs_soyabridge.area")
local TrackBridge  = require("src.n_tracs_soyabridge.track_bridge")
local Track        = require("src.n_tracs_core.track")
local Lever        = require("src.n_tracs_core.lever")
local SwitchBridge = require("src.n_tracs_soyabridge.switch_bridge")
local Switch       = require("src.n_tracs_core.switch")
local VehicleInfo  = require("src.n_tracs_soyabridge.vehicle_info")
---@class SoyaBridge:NtracsObject
---@field nt Ntracs
---@field areas Area[]
---@field leverAlias table<string, string> key: Alias to val: Real name
---@field trackBridge TrackBridge[]
---@field switchBridge SwitchBridge[]
---@field pointList PointSetter[]
---@field vehicleTable VehicleInfo[]
---@field defaultArea number
local SoyaBridge   = {}

function SoyaBridge.new()
    local obj = NtracsObject.createInstance({}, SoyaBridge)
    obj.nt = Ntracs.new()
    obj.areas = {}
    obj.trackBridge = {}
    obj.switchBridge = {}
    obj.pointList = {}
    obj.vehicleTable = {}

    return obj
end

function SoyaBridge:setArea(id, vertexs, leftVertexId, leftAreaIds, rightAreaIds, updateCallback)
    self.areas[id] = Area.new(id, vertexs, leftVertexId, leftAreaIds, rightAreaIds, updateCallback)
end

function SoyaBridge:createTrack(trackName, areaIds)
    self.trackBridge[trackName] = TrackBridge.new(trackName, areaIds)
    self.nt.tracks[trackName] = Track.new(trackName)
end

function SoyaBridge:createLever(name, startTrack, destination, switches, routeLock, overrunLock, signalTrack, direction,
                                approachTrack, lockTime, overrunTime, updateCallback)
    self.nt.levers[name] = Lever.new(name, startTrack, destination, switches, routeLock, overrunLock, signalTrack,
        direction, approachTrack, lockTime, overrunTime, updateCallback)
end

function SoyaBridge:createAutoSignal(name, track, direction, updateCallback)
    self.nt.levers[name] = AutoSignal.new(name, track, direction, updateCallback)
end

function SoyaBridge:createSwitch(name, pointNames, relatedTracks, isSite)
    self.switchBridge[name] = SwitchBridge.new(name, pointNames)
    self.nt.switches[name] = Switch.new(name, isSite or false, relatedTracks)
    for _, v in pairs(pointNames) do
        self.pointList[v] = (self.switchBridge[name]):getPointSetter(v)
    end
end

function SoyaBridge:beforeDateUpdate()
    for _, area in pairs(self.areas) do
        area:initializeForProcess()
    end
end

function SoyaBridge:getVehicleData()
    for vehicle_id, data in pairs(self.vehicleTable) do
        if data.axles then
            for _, axle in ipairs(data.axles) do
                axle:getPosition()
            end
        end

        if data.points then
            -- 個々の実装はbridge側に移すこと
            for _, setter in ipairs(data.points) do
                local dial, ss = server.getVehicleDial(vehicle_id, setter.pointName .. "K")
                if ss then
                    setter.set(dial.value)
                    --else
                    --ARCを実装したら 0 にするようにする。
                    --setter.set(0)
                end
            end
        end
    end

    -- CTCデータ取得
    if CTC_AVAILABLE and CTC then
        GetCtcState()
    end
end

function SoyaBridge:trackShort()
    for _, data in pairs(self.vehicleTable) do
        if data.axles then
            for _, axle in ipairs(data.axles) do
                axle:search(self)
            end
        end
    end
end

function SoyaBridge:beforeProcess()
    self.nt:beforeProcess(
        function(lever) end,
        function(track)
            return self.trackBridge[track.itemName]:isInAxle()
        end,
        function(switch)
            return self.switchBridge[switch.itemName]:getState()
        end)
end

function SoyaBridge:process(deltaTicks)
    self.nt:process(deltaTicks)
end

function SoyaBridge:beforeBroadcast()
    for _, area in pairs(self.areas) do
        area.cbdata = area.updateCallback and area.updateCallback(area, 6)
    end
end

function SoyaBridge:broadcast(sign)
    for _, data in pairs(self.vehicleTable) do
        data:send(sign, self)
    end

    if CTC_AVAILABLE and CTC then
        SendCtcData(sign)
    end
end

function SoyaBridge:loadVehicle(vehicle_id)
    self.vehicleTable[vehicle_id] = VehicleInfo.new(vehicle_id, self)
end

function SoyaBridge:despawnVehicle(vehicle_id)
    self.vehicleTable[vehicle_id] = nil
end

function SoyaBridge:chargeBattery(isCheatBattery)
    for _, vehicle in pairs(SYS.vehicleTable) do
        vehicle:chargeBattery(isCheatBattery)
    end
end

return SoyaBridge
