local NtracsObject = require("src.n_tracs_core.n_tracs_object")

---@class Ntracs:NtracsObject
---@field levers table<string,SignalBase>
---@field tracks table<string,Track>
---@field switches table<string,Switch>
local Ntracs = {}

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
        lever:process(deltaTicks)
    end
end

return Ntracs
