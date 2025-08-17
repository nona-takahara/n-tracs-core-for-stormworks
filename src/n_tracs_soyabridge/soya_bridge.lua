local NtracsObject   = require("src.n_tracs_core.n_tracs_object")
local Ntracs         = require("src.n_tracs_core.ntracs")
local Area           = require("src.n_tracs_soyabridge.area")
local TrackBridge    = require("src.n_tracs_soyabridge.track_bridge")
local Track          = require("src.n_tracs_core.track.track")
local Signal         = require("src.n_tracs_core.signal.signal")
local SwitchBridge   = require("src.n_tracs_soyabridge.switch_bridge")
local RouteDirection = require("src.n_tracs_core.signal.route_direction")
local Switch         = require("src.n_tracs_core.switch.switch")
local VehicleInfo    = require("src.n_tracs_soyabridge.vehicle_info")
local AutoSignal     = require("src.n_tracs_core.signal.auto_signal")
---@class SoyaBridge:NtracsObject
---@field nt Ntracs
---@field areas table<number, Area>
---@field lever_alias table<string, string> key: Alias to val: Real name
---@field track_bridge table<string, TrackBridge>
---@field switch_bridge table<string, SwitchBridge>
---@field points table<string, PointSetter>
---@field vehicle_table table<number, VehicleInfo>
---@field default_area number
local SoyaBridge     = {}

---@return SoyaBridge
function SoyaBridge.new()
    local obj = NtracsObject.create_instance({}, SoyaBridge)
    obj.nt = Ntracs.new()
    obj.areas = {}
    obj.track_bridge = {}
    obj.switch_bridge = {}
    obj.points = {}
    obj.vehicle_table = {}
    obj.lever_alias = {}

    return obj
end

---@param id number
---@param vertexs Vector2d[]
---@param left_vertex_id number
---@param left_area_ids number[]
---@param right_area_ids number[]
---@param update_callback fun(self: Area, deltaTick?: number): any
function SoyaBridge:create_area(id, vertexs, left_vertex_id, left_area_ids, right_area_ids, update_callback)
    self.areas[id] = Area.new(id, vertexs, left_vertex_id, left_area_ids, right_area_ids, update_callback)
end

---@param track_id string
---@param area_ids number[]
function SoyaBridge:create_track(track_id, area_ids)
    self.track_bridge[track_id] = TrackBridge.new(track_id, area_ids)
    for _, v in pairs(area_ids) do
        if self.areas[v] then table.insert(self.areas[v].relatedTracks, track_id) end
    end
    self.nt:crate_track(track_id)
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
---@param lockTime number 接近・保留鎖錠の時間(sec)
---@param overrunTime number 過走防護鎖錠の時間(sec)
---@param updateCallback fun(lever: Signal, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
function SoyaBridge:create_signal(name, startTrack, destination, switches, routeLock, overrunLock, signalTrack, direction,
                                  approachTrack, lockTime, overrunTime, updateCallback)
    self.nt:create_signal(name, startTrack, destination, switches, routeLock, overrunLock, signalTrack,
        direction, approachTrack, lockTime * 60, overrunTime * 60, updateCallback)
end

---@param name string てこ名称
---@param direction RouteDirection 進路てこの方向
---@param updateCallback fun(lever: Signal, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
function SoyaBridge:create_auto_signal(name, track, direction, updateCallback)
    self.nt:create_auto_signal(name, track, direction, updateCallback)
end

---@param name string
---@param points string[]
---@param related_tracks string[]
---@param is_site boolean | nil
function SoyaBridge:create_switch(name, points, related_tracks, is_site)
    self.switch_bridge[name] = SwitchBridge.new(name, points)
    self.nt:create_switch(name, is_site or false, related_tracks)
    for _, v in pairs(points) do
        self.points[v] = (self.switch_bridge[name]):get_point_setter(v)
    end
end

---@param alias string
---@param target string
function SoyaBridge:set_lever_alias(alias, target)
    self.lever_alias[alias] = target
end

function SoyaBridge:get_vehicle_data()
    for _, area in pairs(self.areas) do
        area:initialize_for_process()
    end

    for _, data in pairs(self.vehicle_table) do
        data:get_vehicle_data()
    end
end

function SoyaBridge:before_process()
    for _, v in pairs(sw.vehicle_table) do
        for _, a in ipairs(v.axles) do
            a:search(self)
        end
    end

    for k, v in pairs(self.track_bridge) do
        self.nt:get_track(k):before_process(v:is_in_axle(self))
    end

    for k, v in pairs(self.switch_bridge) do
        self.nt:get_switch(k):before_process(v:get_state())
    end

    for _, v in pairs(self.nt.signal) do
        v:before_process()
    end
end

---@param deltaTicks number
function SoyaBridge:process(deltaTicks)
    self.nt:process(deltaTicks)
end

---@param deltaTicks number
function SoyaBridge:before_broadcast(deltaTicks)
    -- Areaのコールバック
    for _, area in pairs(self.areas) do
        area.cbdata = area.updateCallback and area.updateCallback(area, deltaTicks)
    end
end

---@param sign number
function SoyaBridge:broadcast(sign)
    for _, data in pairs(self.vehicle_table) do
        data:send(sign, self)
    end
end

---@param vehicle_id number
function SoyaBridge:load_vehicle(vehicle_id)
    self.vehicle_table[vehicle_id] = VehicleInfo.new(vehicle_id, self)
end

---@param vehicle_id number
function SoyaBridge:despawn_vehicle(vehicle_id)
    self.vehicle_table[vehicle_id] = nil
end

---@param isCheatBattery boolean
function SoyaBridge:charge_battery(isCheatBattery)
    for _, vehicle in pairs(self.vehicle_table) do
        vehicle:charge_battery(isCheatBattery)
    end
end

return SoyaBridge
