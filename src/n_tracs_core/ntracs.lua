local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local Signal = require("src.n_tracs_core.signal.signal")
local Track = require("src.n_tracs_core.track.track")
local AutoSignal = require("src.n_tracs_core.signal.auto_signal")
local Switch = require("src.n_tracs_core.switch.switch")

---@class Ntracs:NtracsObject
---@field private signal Signal[]
---@field private track Track[]
---@field private switch Switch[]
local Ntracs = {}

function Ntracs.new()
    local obj = NtracsObject.create_instance({}, Ntracs)

    obj.signal = {}
    obj.track = {}
    obj.switch = {}

    return obj
end

function Ntracs:to_str()
    return "N-TRACS DB Object"
end

function Ntracs:calculate_signal()

end

---N-TRACSオブジェクトの依存関係にエラーがないか確認します。エラーがある場合はerror関数で止まります
function Ntracs:assert()

end

---信号機を取得します
---@param signal_id string
---@return Signal
function Ntracs:get_signal(signal_id)
    return (type(signal_id) == "string" and self.signal[signal_id]) or
        error(debug.traceback(tostring(signal_id) .. " is not found."))
end

---論理軌道回路を取得します
---@param track_id string
---@return Track
function Ntracs:get_track(track_id)
    return (type(track_id) == "string" and self.track[track_id]) or
        error(debug.traceback(tostring(track_id) .. " is not found."))
end

---論理分岐器を取得します
---@param switch_id string
---@return Switch
function Ntracs:get_switch(switch_id)
    return (type(switch_id) == "string" and self.switch[switch_id]) or
        error(debug.traceback(tostring(switch_id) .. " is not found."))
end

---信号機を取得します
---@param signal_id string
---@return Signal | nil
function Ntracs:get_signal_may_nil(signal_id)
    return self.signal[signal_id]
end

---論理軌道回路を取得します
---@param track_id string
---@return Track | nil
function Ntracs:get_track_may_nil(track_id)
    return self.track[track_id]
end

---論理分岐器を取得します
---@param switch_id string
---@return Switch | nil
function Ntracs:get_switch_may_nil(switch_id)
    return self.switch[switch_id]
end

function Ntracs:create_signal(signal_id, startTrack, destination, switches, routeLock, overrunLock,
                              signalTrack, direction, approachTrack, lockTime, overrunTime, controls, updateCallback)
    if self.signal[signal_id] then error(signal_id .. " is defined") end
    self.signal[signal_id] = Signal.new(signal_id, startTrack, destination, switches, routeLock, overrunLock,
        signalTrack, direction, approachTrack, lockTime, overrunTime, controls, updateCallback)
end

function Ntracs:create_auto_signal(signal_id, track, direction, updateCallback)
    if self.signal[signal_id] then error(signal_id .. " is defined") end
    self.signal[signal_id] = AutoSignal.new(signal_id, track, direction, updateCallback)
end

---@param track_id string
function Ntracs:crate_track(track_id)
    if self.track[track_id] then error(track_id .. " is defined") end
    self.track[track_id] = Track.new(track_id)
end

---@param switch_id string 転てつ器名称
---@param is_site boolean 現場扱いの転てつ器ならばtrue
---@param related_tracks string[] てっ査鎖錠を行う抽象軌道回路
function Ntracs:create_switch(switch_id, is_site, related_tracks)
    if self.switch[switch_id] then error(switch_id .. " is defined") end
    self.switch[switch_id] = Switch.new(switch_id, is_site, related_tracks)
end

---@param deltaTicks number
function Ntracs:process(deltaTicks)
    for _, v in pairs(self.track) do
        v:process(deltaTicks, self)
    end

    for _, v in pairs(self.signal) do
        v:process(deltaTicks, self)
    end

    for _, v in pairs(self.switch) do
        v:process(deltaTicks, self)
    end
end

return Ntracs
