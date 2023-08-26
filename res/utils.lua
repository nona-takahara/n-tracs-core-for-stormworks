---@type Lever[]
LEVERS = LEVERS or {}
function LeverGetter(name)
    if not LEVERS[name] then
        ---@diagnostic disable-next-line: missing-fields
        LEVERS[name] = {}
    end
    return LEVERS[name]
end

---@type Switch[]
SWITCHES = SWITCHES or {}
function SwitchGetter(name)
    if not SWITCHES[name] then
        ---@diagnostic disable-next-line: missing-fields
        SWITCHES[name] = {}
    end
    return SWITCHES[name]
end

---@type Track[]
TRACKS = TRACKS or {}
function TrackGetter(name)
    if not TRACKS[name] then
        ---@diagnostic disable-next-line: missing-fields
        TRACKS[name] = {}
    end
    return TRACKS[name]
end

---@type Area[]
AREAS = AREAS or {}
function AreaGetter(name)
    if not AREAS[name] then
        ---@diagnostic disable-next-line: missing-fields
        AREAS[name] = {}
    end
    return AREAS[name]
end
