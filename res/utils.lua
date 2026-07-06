local BookType = require("src.n_tracs_core.track.book_type")
local json     = require("src.utils.json")
local Utils    = {}

---@param aspect number
---@return function
function Utils.StandardAspectCallback_2nd(aspect)
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
function Utils.StandardAspectCallback_3rd_G_Y_R(nextSignal)
    return (function(self, nt)
        if self.HR then
            local sig = nt:get_signal_may_nil(nextSignal)
            if sig and sig.aspect >= 2 and self.aspect >= 2 then
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
function Utils.StandardAspectCallback_3rd_multi(nextSignals)
    return (function(self, nt)
        if self.HR then
            if self.aspect >= 2 then
                for _, s in ipairs(nextSignals) do
                    local sig = nt:get_signal_may_nil(s)
                    if sig and sig.aspect >= 2 then
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

---@param area Area
---@param data number[]
function Utils.SendLeftAxle(area, data)
    local p = Utils.GetLeftAxle(area)
    if p then
        for i, _ in ipairs(data) do
            p.sending[i] = data[i]
        end
    end
end

---@param area Area
---@param data number[]
function Utils.SendRightAxle(area, data)
    local p = Utils.GetRightAxle(area)
    if p then
        for i, _ in ipairs(data) do
            p.sending[i] = data[i]
        end
    end
end

---@param area Area
---@param data number[]
function Utils.SendAllAxle(area, data)
    if area.axles and #area.axles > 0 then
        for p, _ in ipairs(area.axles) do
            for i, _ in ipairs(data) do
                area.axles[p].sending[i] = data[i]
            end
        end
    end
end

function Utils.GetLeftAxle(area)
    return area.axles and area.axles[1]
end

function Utils.GetRightAxle(area)
    return area.axles and area.axles[#area.axles]
end

function Utils.ATS_E() return { 0, 0 } end

function Utils.ATS_Ea() return { 0, 1 } end

function Utils.ATS_R() return { 1, 2 } end

function Utils.ATS_T() return { 18, 4 } end

function Utils.ATS_YY() return { 30, 6 } end

function Utils.ATS_Y() return { 50, 8 } end

function Utils.ATS_Yh() return { 60, 9 } end

function Utils.ATS_YG() return { 70, 10 } end

function Utils.ATS_YGh() return { 80, 11 } end

function Utils.ATS_G() return { 100, 12 } end

function Utils.ATS_Gh() return { 112, 13 } end

function Utils.someRouteLock(nt, track_name)
    return nt:get_track(track_name).book == BookType.RouteLock
end

function Utils.someDestination(nt, track_name)
    return (
        nt:get_track(track_name).bookDest == BookType.DestinationActive or
        nt:get_track(track_name).bookDest == BookType.DestinationExpired
    )
end

---自分より左のtrack areaにaxleがなければtrue
---@param s SoyaBridge
---@param area Area
---@param track_name string
function Utils.isTrackLeftAxle(s, area, track_name)
    local p = s.track_bridge[track_name]
    if p then
        for _, a in ipairs(p.area_ids) do
            if a == area.itemName then
                return true
            end
            if #(s.areas[a].axles) > 0 then
                return false
            end
        end
    end
    return false
end

---自分より右のtrack areaにaxleがなければtrue
---@param s SoyaBridge
---@param area Area
---@param track_name string
function Utils.isTrackRightAxle(s, area, track_name)
    local p = s.track_bridge[track_name]
    if p then
        local l = #(p.area_ids)
        for i = l, 1, -1 do
            local a = p.area_ids[i]
            if a == area.itemName then
                return true
            end
            if #(s.areas[a].axles) > 0 then
                return false
            end
        end
    end
    return false
end

return Utils
