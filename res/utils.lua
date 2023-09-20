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
    if not TRACKS[name] then
        ---@diagnostic disable-next-line: missing-fields
        TRACKS[name] = { name = "N/A" }
    end
    return TRACKS[name]
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
