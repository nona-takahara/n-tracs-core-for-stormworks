local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local Ntracs       = require("src.n_tracs_core.ntracs")
local Area         = require("src.n_tracs_soyabridge.area")
local TrackBridge  = require("src.n_tracs_soyabridge.track_bridge")
local Track        = require("src.n_tracs_core.track.track")
local Lever        = require("src.n_tracs_core.lever.lever")
local SwitchBridge = require("src.n_tracs_soyabridge.switch_bridge")
local Switch       = require("src.n_tracs_core.switch.switch")
local VehicleInfo  = require("src.n_tracs_soyabridge.vehicle_info")
local AutoSignal   = require("src.n_tracs_core.lever.auto_signal")
---@class SoyaBridge:NtracsObject
---@field nt Ntracs
---@field areas table<number, Area>
---@field leverAlias table<string, string> key: Alias to val: Real name
---@field trackBridge table<string, TrackBridge>
---@field switchBridge table<string, SwitchBridge>
---@field pointList table<string, PointSetter>
---@field vehicleTable table<number, VehicleInfo>
---@field defaultArea number
local SoyaBridge   = {}

---@return SoyaBridge
function SoyaBridge.new()
    local obj = NtracsObject.createInstance({}, SoyaBridge)
    obj.nt = Ntracs.new()
    obj.areas = {}
    obj.trackBridge = {}
    obj.switchBridge = {}
    obj.pointList = {}
    obj.vehicleTable = {}
    obj.leverAlias = {}

    return obj
end

---@param id number
---@param vertexs Vector2d[]
---@param leftVertexId number
---@param leftAreaIds number[]
---@param rightAreaIds number[]
---@param updateCallback fun(self: Area, deltaTick?: number): any
function SoyaBridge:setArea(id, vertexs, leftVertexId, leftAreaIds, rightAreaIds, updateCallback)
    self.areas[id] = Area.new(id, vertexs, leftVertexId, leftAreaIds, rightAreaIds, updateCallback)
end

---@param trackName string
---@param areaIds number[]
function SoyaBridge:createTrack(trackName, areaIds)
    self.trackBridge[trackName] = TrackBridge.new(trackName, areaIds)
    self.nt.tracks[trackName] = Track.new(trackName)
end

---@param name string てこ名称
---@param startTrack string 進路てこ区間の始点
---@param destination string 進路てこ区間の終点
---@param switches SwitchRoute[] 関連する転てつ器と開通方向の組み合わせ情報
---@param routeLock string[] 進路鎖錠を行う抽象軌道回路
---@param overrunLock string[] 過走防護を行う抽象軌道回路
---@param signalTrack string[] 信号現示に関連する抽象軌道回路
---@param direction RouteDirection 進路てこの方向
---@param approachTrack string[] 接近鎖錠を行う抽象軌道回路。保留鎖錠の場合は空テーブル
---@param lockTime number 接近・保留鎖錠の時間(Tick)
---@param overrunTime number 過走防護鎖錠の時間(Tick)
---@param updateCallback fun(lever: Lever, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
function SoyaBridge:createLever(name, startTrack, destination, switches, routeLock, overrunLock, signalTrack, direction,
                                approachTrack, lockTime, overrunTime, updateCallback)
    self.nt.levers[name] = Lever.new(name, startTrack, destination, switches, routeLock, overrunLock, signalTrack,
        direction, approachTrack, lockTime, overrunTime, updateCallback)
end

---@param name string てこ名称
---@param direction RouteDirection 進路てこの方向
---@param updateCallback fun(lever: Lever, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
function SoyaBridge:createAutoSignal(name, track, direction, updateCallback)
    self.nt.levers[name] = AutoSignal.new(name, track, direction, updateCallback)
end

---@param name string
---@param pointNames string[]
---@param relatedTracks string[]
---@param isSite boolean | nil
function SoyaBridge:createSwitch(name, pointNames, relatedTracks, isSite)
    self.switchBridge[name] = SwitchBridge.new(name, pointNames)
    self.nt.switches[name] = Switch.new(name, isSite or false, relatedTracks)
    for _, v in pairs(pointNames) do
        self.pointList[v] = (self.switchBridge[name]):getPointSetter(v)
    end
end

---@param alias string
---@param target string
function SoyaBridge:setLeverAlias(alias, target)
    self.leverAlias[alias] = target
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
    --if CTC_AVAILABLE and CTC then
    --    GetCtcState()
    --end
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

---@param deltaTicks number
function SoyaBridge:process(deltaTicks)
    self.nt:process(deltaTicks)
end

function SoyaBridge:beforeBroadcast()
    for _, area in pairs(self.areas) do
        area.cbdata = area.updateCallback and area.updateCallback(area, 6)
    end
end

---@param sign number
function SoyaBridge:broadcast(sign)
    for _, data in pairs(self.vehicleTable) do
        data:send(sign, self)
    end

    --if CTC_AVAILABLE and CTC then
    --    SendCtcData(sign)
    --end
end

---@param vehicle_id number
function SoyaBridge:loadVehicle(vehicle_id)
    self.vehicleTable[vehicle_id] = VehicleInfo.new(vehicle_id, self)
end

---@param vehicle_id number
function SoyaBridge:despawnVehicle(vehicle_id)
    self.vehicleTable[vehicle_id] = nil
end

---@param isCheatBattery boolean
function SoyaBridge:chargeBattery(isCheatBattery)
    for _, vehicle in pairs(self.vehicleTable) do
        vehicle:chargeBattery(isCheatBattery)
    end
end

return SoyaBridge
