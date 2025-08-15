NtracsObject = require("src.n_tracs_core.n_tracs_object")

---@class Ntracs:NtracsObject
---@field private signal Signal[]
---@field private track Track[]
---@field private switch Switch[]
local Ntracs = {}

function Ntracs.new()
    local obj = NtracsObject.createInstance({}, Ntracs)

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

return Ntracs
