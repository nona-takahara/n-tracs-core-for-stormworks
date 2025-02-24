local NtracsObject           = require("src.n_tracs_core.n_tracs_object")
local TrafficDirectionLever  = require("src.n_tracs_core.lever.traffic_direction_lever")
local SetRoute               = require("src.n_tracs_core.switch.set_route")
local TrafficDirectionSwitch = require("src.n_tracs_core.switch.traffic_direction_switch")

---@class Ntracs:NtracsObject
---@field levers table<string,SignalBase>
---@field tracks table<string,Track>
---@field switches table<string,Switch>
local Ntracs                 = {}

function Ntracs.new()
    local obj = NtracsObject.createInstance({}, Ntracs)
    obj.levers = {}
    obj.tracks = {}
    obj.switches = {}

    return obj
end

---@param updateLever fun(lever: SignalBase):nil 戻り値は入力
---@param updateTrack fun(track: Track):boolean 戻り値は在線状況
---@param updateSwitch fun(switch: Switch):SetRoute 戻り値は現在の状況
function Ntracs:beforeProcess(updateLever, updateTrack, updateSwitch)
    for _, track in pairs(self.tracks) do
        track:beforeProcess(updateTrack(track))
    end

    for _, switch in pairs(self.switches) do
        switch:beforeProcess(updateSwitch(switch))
    end

    for _, lever in pairs(self.levers) do
        lever:beforeProcess(updateLever(lever))
    end
end

function Ntracs:process(deltaTicks)
    for _, track in pairs(self.tracks) do
        track:process(deltaTicks)
    end

    for _, lever in pairs(self.levers) do
        lever:process(deltaTicks, self)
    end
end

---単線自動閉そく用のてこ・リレーを一括生成します
---@param lever1 string
---@param fr1 string
---@param lever2 string
---@param fr2 string
---@param tracks string[]
function Ntracs:createSingleLineBlock(lever1, fr1, lever2, fr2, tracks)
    local lever1L, lever1R, lever2L, lever2R = lever1 .. "L", lever1 .. "R", lever2 .. "L", lever2 .. "R"
    self.levers[lever1L] = TrafficDirectionLever.new(lever1L, lever1R, SetRoute.Normal, true, fr1, fr2)
    self.levers[lever1R] = TrafficDirectionLever.new(lever1R, lever1L, SetRoute.Reverse, false, fr1, fr2)

    self.levers[lever2L] = TrafficDirectionLever.new(lever2L, lever2R, SetRoute.Normal, false, fr2, fr1)
    self.levers[lever2R] = TrafficDirectionLever.new(lever2R, lever2L, SetRoute.Reverse, true, fr2, fr1)

    self.switches[fr1] = TrafficDirectionSwitch.new(fr1, tracks)
    self.switches[fr2] = TrafficDirectionSwitch.new(fr2, tracks)
end

return Ntracs
