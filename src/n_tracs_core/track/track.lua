-- N-TRACS Core [Track]
local NtracsObject   = require("src.n_tracs_core.n_tracs_object")
local BookType       = require("src.n_tracs_core.track.book_type")
local RouteDirection = require("src.n_tracs_core.signal.route_direction")
local Signal         = require("src.n_tracs_core.signal.signal")
local Switch         = require("src.n_tracs_core.switch.switch")

---軌道回路に関するものです
---@class Track:NtracsObject
---@field relatedLever string
---@field book BookType
---@field direction RouteDirection
---@field private timer number
---@field private beforeRouteLockItem string
---@field private short boolean
local Track          = {}

---抽象軌道回路データを作成します
---@param itemName string 抽象軌道回路名称です
---@return Track
function Track.new(itemName)
    local obj = NtracsObject.create_instance(NtracsObject.new(), Track)
    obj.name = "Track"
    obj.itemName = itemName
    obj.relatedLever = nil
    obj.book = BookType.NoBook
    obj.direction = RouteDirection.None
    obj.timer = 0
    obj.beforeRouteLockItem = nil
    return obj
end

---@param lever string
---@param nt Ntracs
function Track:book_temporary(lever, nt)
    if self.book ~= BookType.RouteOver then
        self.relatedLever = lever
        self.book = BookType.Temporary
        self.direction = nt:get_signal(lever).direction
    end
end

---@param lever string
---@param routeLockBefore string
---@param nt Ntracs
function Track:book_route_lock(lever, routeLockBefore, nt)
    self.relatedLever = lever
    self.beforeRouteLockItem = routeLockBefore
    self.book = BookType.RouteLock
    self.direction = nt:get_signal(lever).direction
end

---@param lever string
---@param routeLockBefore string
---@param nt Ntracs
function Track:book_destination(lever, routeLockBefore, nt)
    self.relatedLever = lever
    self.beforeRouteLockItem = routeLockBefore
    self.book = BookType.Destination
    self.direction = nt:get_signal(lever).direction
    self.timer = nt:get_signal(lever).overrunTime
end

---@param lever string
---@param nt Ntracs
function Track:book_over_run(lever, nt)
    self.relatedLever = lever
    self.beforeRouteLockItem = nt:get_signal(lever).destination
    self.book = BookType.RouteOver
    self.direction = nt:get_signal(lever).direction
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_ready_for_book_temporary(lever, nt)
    return (self.book == BookType.NoBook) or (self.book == BookType.Temporary and self.relatedLever == lever) or
        (self.book == BookType.RouteOver and self.direction == nt:get_signal(lever).direction)
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_booked_temporary(lever, nt)
    return (self.book == BookType.Temporary and self.relatedLever == lever) or
        (self.book == BookType.RouteOver and self.direction == nt:get_signal(lever).direction)
end

---@param lever string
---@return boolean
function Track:is_route_lock(lever)
    return self.relatedLever == lever and self.book == BookType.RouteLock
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_over_run_lock(lever, nt)
    return (self.relatedLever == lever and self.book == BookType.RouteOver) or
        (self.book == BookType.RouteLock and self.direction == nt:get_signal(lever).direction)
end

---@param temporaryIsNotLocked boolean
---@return boolean
function Track:is_locked(temporaryIsNotLocked)
    if temporaryIsNotLocked then
        return (self.book ~= BookType.NoBook) and (self.book ~= BookType.Temporary)
    else
        return self.book ~= BookType.NoBook
    end
end

---@return boolean
function Track:under_route_lock_b()
    return (self.book == BookType.Destination and self.timer < 0) or
        (self.book == BookType.NoBook or self.book == BookType.Temporary)
end

---ポリモーフィズム的に取り扱う。ひとつ前のNtracsObjectを調べる。
---@param item string
---@param nt Ntracs
---@return boolean
function CheckUnlockRouteLock(item, nt)
    if item == nil then return true end
    local item_obj = nt:get_track_may_nil(item) or nt:get_signal_may_nil(item)
    return (item_obj and item_obj:under_route_lock_b()) or false
end

---抽象軌道回路内に在線があればtrueを返却します
---@return boolean
function Track:is_short()
    return self.short
end

---processを呼び出す前に実行してください。状態を設定します
---@param isShort boolean
function Track:before_process(isShort)
    self.short = isShort
end

---毎ループごとに呼び出してください
---@param deltaTick number
---@param nt Ntracs
function Track:process(deltaTick, nt)
    if self.book == BookType.RouteLock or self.book == BookType.RouteOver then
        if (not self.short) and CheckUnlockRouteLock(self.beforeRouteLockItem, nt) then
            self.book = BookType.NoBook
        end
    elseif self.book == BookType.Destination then
        if CheckUnlockRouteLock(self.beforeRouteLockItem, nt) then
            self.timer = math.max(self.timer - deltaTick, -1)
            if not self.short then
                self.book = BookType.NoBook
            end
        end
    elseif self.book == BookType.NoBook then
        -- do nothing
    elseif self.book == BookType.Temporary then
        if not nt:get_signal(self.relatedLever):getInput() then
            self.book = BookType.NoBook
        end
    else
        if self.itemName then
            error("Book mode is wrong: " .. tostring(self.itemName))
        end
    end
end

return Track
