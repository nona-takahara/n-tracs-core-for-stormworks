---@type SignalBase[]
LEVERS = LEVERS or {}
function LeverGetter(name)
    if not LEVERS[name] then
        ---@diagnostic disable-next-line: missing-fields
        LEVERS[name] = { name = "N/A" }
    end
    return LEVERS[name]
end

---@type Switch[]
SWITCHES = SWITCHES or {}
function SwitchGetter(name)
    if not SWITCHES[name] then
        ---@diagnostic disable-next-line: missing-fields
        SWITCHES[name] = { name = "N/A" }
    end
    return SWITCHES[name]
end

---@type Track[]
TRACKS = TRACKS or {}
function TrackGetter(name)
    local n = tostring(name)
    if not TRACKS[n] then
        ---@diagnostic disable-next-line: missing-fields
        TRACKS[n] = { name = "N/A" }
    end
    return TRACKS[n]
end

---@type Area[]
AREAS = AREAS or {}
function AreaGetter(name)
    if not AREAS[name] then
        ---@diagnostic disable-next-line: missing-fields
        AREAS[name] = { name = "N/A" }
    end
    return AREAS[name]
end

function AreasGetter(name)
    local r = {}
    for i, v in ipairs(name) do
        r[i] = AreaGetter(v)
    end
    return r
end

---@type TrackBridge[]
BRIDGE_TRACK = BRIDGE_TRACK or {}
function CreateTrack(name, arealist)
    BRIDGE_TRACK[name] = TrackBridge.overWrite(BRIDGE_TRACK[name], name, arealist)
    TRACKS[name] = Track.overWrite(TRACKS[name], name)
end

---@type SwitchBridge[]
BRIDGE_SWITCH = BRIDGE_SWITCH or {}
---comments
---@param itemName string
---@param pointNames string[]
---@param relatedTracks Track[]
---@param isSite boolean | nil
function CreateSwitch(itemName, pointNames, relatedTracks, isSite)
    BRIDGE_SWITCH[itemName] = SwitchBridge.overWrite(BRIDGE_SWITCH[itemName], itemName, pointNames)
    SWITCHES[itemName] = Switch.overWrite(SWITCHES[itemName], itemName, isSite or false, relatedTracks)
end

---comments
---@param area Area
---@param sending number[]
function SendLeftAxle(area, sending)
    if area.axles and #(area.axles) > 0 then
        area.axles[1].sending = sending
    end
end

---comments
---@param area Area
---@param sending number[]
function SendRightAxle(area, sending)
    if area.axles and #(area.axles) > 0 then
        area.axles[#(area.axles)].sending = sending
    end
end

---comments
---@param area Area
---@param sending number[]
function SendAllAxle(area, sending)
    for _, v in ipairs(area.axles) do
        v.sending = sending
    end
end

function TrackInformation(trackName, area, direction)
    local t = TRACKS[trackName]
    local lv = t.relatedLever and t.relatedLever.itemName
    local trackArea = BRIDGE_TRACK[trackName].areas
    local begins = 1
    local ends = #trackArea
    local step = 1

    if direction == RouteDirection.Right or t.direction == RouteDirection.Right then
        begins = #trackArea
        ends = 1
        step = -1
    end

    for i = begins, ends, step do
        local tarea = trackArea[i]
        if tarea == area then
            break
        elseif tarea.axles and #(tarea.axles) > 0 then
            return lv, t.direction, false, t.book
        end
    end
    return lv, t.direction, true, t.book
end

function GetLeftTrackArea(trackName, area)
    local trackArea = BRIDGE_TRACK[trackName].areas
    for i = 0, #trackArea - 1 do
        if trackArea[i + 1] == area then return trackArea[i] end
    end
    return nil
end

function GetRightTrackArea(trackName, area)
    local trackArea = BRIDGE_TRACK[trackName].areas
    for i = 1, #trackArea - 1 do
        if trackArea[i] == area then return trackArea[i + 1] end
    end
    return nil
end

---@param aspect number
---@return function
function StandardAspectCallback_2nd(aspect)
    return (function(self)
        if self.HR then
            return aspect
        else
            return 0
        end
    end)
end

---@param nextSignal string
---@return function
function StandardAspectCallback_3rd_G_Y_R(nextSignal)
    return (function(self)
        if self.HR then
            if LEVERS[nextSignal].aspect >= 2 and self.aspect >= 2 then
                return 4
            else
                return 2
            end
        else
            return 0
        end
    end)
end

---@param nextSignals string[]
---@return function
function StandardAspectCallback_3rd_multi(nextSignals)
    return (function(self)
        if self.HR then
            if self.aspect >= 2 then
                for _, s in ipairs(nextSignals) do
                    if LEVERS[s].aspect >= 2 then
                        return 4
                    end
                end
            end
            return 2
        else
            return 0
        end
    end)
end

---@alias ATStable number[]

---@type ATStable
ATS_Gh = { 110, 4 }
---@type ATStable
ATS_G = { 100, 4 }
---@type ATStable
ATS_YGh = { 80, 4 }
---@type ATStable
ATS_YG = { 70, 4 }
---@type ATStable
ATS_Y = { 50, 4 }
---@type ATStable
ATS_YY = { 30, 4 }
---@type ATStable
ATS_T = { 15, 4 }
---@type ATStable
ATS_R = { 0, 4 }
---@type ATStable
ATS_N = { 0, 0 }
---@type ATStable
ATS_E = { -1, 14 }

---@type ATStable
ATS_P60 = { 17, 18 }
---@type ATStable
ATS_P40 = { 14, 17 }
---@type ATStable
ATS_P25 = { 12, 16 }
---@type ATStable
ATS_PEP = { 6, 15 }

---@param trackName string
---@param relatedLever string
---@param direction RouteDirection
---@param up ATStable
---@param other ATStable
---@return function
function StandardATS(trackName, relatedLever, direction, up, other)
    return (function(self)
        local lv, dd, ff, book = TrackInformation(trackName, self, direction)
        if ff then
            if LEVERS[relatedLever].aspect >= 2 then
                SendRightAxle(self, up)
            else
                SendRightAxle(self, other)
            end
        end
    end)
end

---@param trackName string
---@param relatedLevers string[]
---@param direction RouteDirection
---@param up ATStable
---@param other ATStable
---@return function
function StandardATS_multi(trackName, relatedLevers, direction, up, other)
    return (function(self)
        local lv, dd, ff, book = TrackInformation(trackName, self, direction)
        if ff then
            for _, v in ipairs(relatedLevers) do
                if LEVERS[v].aspect >= 2 then
                    SendRightAxle(self, up)
                    return
                end
            end
            SendRightAxle(self, other)
        end
    end)
end

function error(message)
    debug.log("[N-TRACS] ERROR: " .. tostring(message))
end

function Dbglog(message)
    debug.log("[N-TRACS] DEBUG: " .. tostring(message))
end
