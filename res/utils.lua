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
function CrateTrack(name, arealist)
    BRIDGE_TRACK[name] = TrackBridge.overWrite(BRIDGE_TRACK[name], name, arealist)
    TRACKS[name] = Track.overWrite(TRACKS[name], name)
end

---@type SwitchBridge[]
BRIDGE_SWITCH = BRIDGE_SWITCH or {}
