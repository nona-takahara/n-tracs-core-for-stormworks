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
---@field private beforeRouteLockItem string
---@field private short boolean
---@field private bookDest BookType
---@field private destRelatedLever string
---@field private destDirection RouteDirection
---@field private destBeforeRouteLockItem string
---@field private destTimer number
---@field private destTimerStarted boolean
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
    obj.beforeRouteLockItem = nil
    obj.bookDest = BookType.NoBook
    obj.destRelatedLever = nil
    obj.destDirection = RouteDirection.None
    obj.destBeforeRouteLockItem = nil
    obj.destTimer = 0
    obj.destTimerStarted = false
    return obj
end

---@param lever string
---@param nt Ntracs
function Track:book_temporary(lever, nt)
    if self.book == BookType.NoBook then
        self.relatedLever = lever
        self.book = BookType.Temporary
        self.direction = nt:get_signal(lever).direction
    end
end

---@param lever string
---@param nt Ntracs
function Track:book_start_temporary(lever, nt)
    if self.book == BookType.NoBook then
        self.book = BookType.Temporary
        self.relatedLever = lever
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
---@param nt Ntracs
function Track:book_start(lever, nt)
    local dir = nt:get_signal(lever).direction
    local subOk = (self.bookDest == BookType.NoBook)
        or (self.bookDest == BookType.DestinationExpired)
        or (self.bookDest == BookType.DestinationActive and self.destDirection == dir)
    if self.book == BookType.Temporary and self.relatedLever == lever and subOk then
        self.book = BookType.Start
        self.beforeRouteLockItem = lever
    end
end

---@param lever string
---@param routeLockBefore string
---@param nt Ntracs
function Track:book_destination(lever, routeLockBefore, nt)
    if self.book == BookType.Temporary and self.relatedLever == lever then
        self.book = BookType.NoBook
        self.relatedLever = nil
    end
    self.bookDest = BookType.DestinationActive
    self.destRelatedLever = lever
    self.destBeforeRouteLockItem = routeLockBefore
    self.destDirection = nt:get_signal(lever).direction
    self.destTimer = nt:get_signal(lever).overrunTime
    self.destTimerStarted = false
end

---@param lever string
---@param nt Ntracs
function Track:book_over_run(lever, nt)
    self.bookDest = BookType.RouteOver
    self.destRelatedLever = lever
    self.destBeforeRouteLockItem = nt:get_signal(lever).destination
    self.destDirection = nt:get_signal(lever).direction
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_ready_for_book_temporary(lever, nt)
    local dir = nt:get_signal(lever).direction
    local mainOk = (self.book == BookType.NoBook)
        or (self.book == BookType.Temporary and self.relatedLever == lever)
        or (self.book == BookType.Start and self.direction == dir)
    if not mainOk then return false end
    return (self.bookDest == BookType.NoBook)
        or (self.bookDest == BookType.RouteOver and self.destDirection == dir)
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_ready_for_book_start(lever, nt)
    local dir = nt:get_signal(lever).direction
    local mainOk = (self.book == BookType.NoBook)
        or (self.book == BookType.Temporary and self.relatedLever == lever)
        or (self.book == BookType.Start and self.relatedLever == lever)
    if not mainOk then return false end
    return (self.bookDest == BookType.NoBook)
        or (self.bookDest == BookType.DestinationExpired)
        or (self.bookDest == BookType.DestinationActive and self.destDirection == dir)
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_booked_temporary(lever, nt)
    local dir = nt:get_signal(lever).direction
    return (self.book == BookType.Temporary and self.relatedLever == lever)
        or (self.book == BookType.Start and self.direction == dir)
        or (self.bookDest == BookType.RouteOver and self.destDirection == dir)
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_booked_start(lever, nt)
    local dir = nt:get_signal(lever).direction
    return (self.book == BookType.Temporary and self.relatedLever == lever)
        or (self.book == BookType.Start and self.relatedLever == lever)
        or (self.bookDest == BookType.DestinationExpired)
        or (self.bookDest == BookType.DestinationActive and self.destDirection == dir)
end

---@param lever string
---@return boolean
function Track:is_route_lock(lever)
    return self.book == BookType.RouteLock and self.relatedLever == lever
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_over_run_lock(lever, nt)
    local dir = nt:get_signal(lever).direction
    if self.bookDest == BookType.RouteOver and self.destRelatedLever == lever then
        return true
    end
    if self.book == BookType.RouteLock and self.direction == dir then
        return true
    end
    if self.bookDest == BookType.RouteOver and self.destDirection == dir then
        local owner = nt:get_signal_may_nil(self.destRelatedLever)
        if owner and type(owner.is_opening_lever) == "function" and owner:is_opening_lever() then
            return true
        end
    end
    return false
end

---開通てこが当該区間を(再)宣言できる状態か確認します。空き、または既に自分自身が保持している場合のみtrueです。
---@param lever string
---@return boolean
function Track:is_claimable_for_opening(lever)
    return self.bookDest == BookType.NoBook
        or (self.bookDest == BookType.RouteOver and self.destRelatedLever == lever)
end

---開通てこによる過走防護方向の予約(bookDestのみ変更)。
---destBeforeRouteLockItemに開通てこ自身(lever)を設定することで、under_route_lock_b()が常にfalseを返す
---開通てこの性質を利用し、在線解除だけでは自動的に解放されないようにします(実信号機の本予約で明示的に
---book_over_run()が呼ばれるまで保持し続けます)。既存のbook_over_run()をそのまま流用すると
---destBeforeRouteLockItemがnt:get_signal(lever).destinationを参照しようとしてnilになり
---(開通てこにはdestinationフィールドが存在しないため)、非在線時に毎ティック自動解放されてしまうため、
---専用の関数として新設しています。
---@param lever string
---@param nt Ntracs
function Track:book_opening(lever, nt)
    self.bookDest = BookType.RouteOver
    self.destRelatedLever = lever
    self.destBeforeRouteLockItem = lever
    self.destDirection = nt:get_signal(lever).direction
end

---@param lever string
---@return boolean
function Track:is_destination_locked(lever)
    return self.destRelatedLever == lever
        and (self.bookDest == BookType.DestinationActive
            or self.bookDest == BookType.DestinationExpired)
end

---@param lever string
---@param nt Ntracs
---@return boolean
function Track:is_start_locked(lever, nt)
    local dir = nt:get_signal(lever).direction
    return (self.book == BookType.Start and self.relatedLever == lever)
        or (self.bookDest == BookType.DestinationExpired)
        or (self.bookDest == BookType.DestinationActive and self.destDirection == dir)
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
    if self.bookDest == BookType.DestinationExpired then return true end
    if self.bookDest == BookType.DestinationActive then return false end
    if self.bookDest == BookType.RouteOver then return false end
    return self.book == BookType.NoBook or self.book == BookType.Temporary
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
    if self.book == BookType.RouteLock then
        if (not self.short) and CheckUnlockRouteLock(self.beforeRouteLockItem, nt) then
            self.book = BookType.NoBook
        end
    elseif self.book == BookType.Start then
        if CheckUnlockRouteLock(self.beforeRouteLockItem, nt) then
            self.book = BookType.NoBook
        end
    elseif self.book == BookType.Temporary then
        if not nt:get_signal(self.relatedLever):getInput() then
            self.book = BookType.NoBook
        end
    elseif self.book == BookType.NoBook then
        -- do nothing
    else
        if self.itemName then
            error("Book mode is wrong (main): " .. tostring(self.itemName))
        end
    end

    if self.bookDest == BookType.DestinationActive then
        if self.short then
            if not self.destTimerStarted then self.destTimerStarted = true end
            self.destTimer = math.max(self.destTimer - deltaTick, -1)
            if self.destTimer < 0 then
                self.bookDest = BookType.DestinationExpired
            end
        end

        if (not self.short) and CheckUnlockRouteLock(self.destBeforeRouteLockItem, nt) then
            self.bookDest = BookType.NoBook
        end
    elseif self.bookDest == BookType.DestinationExpired then
        if (not self.short) and CheckUnlockRouteLock(self.destBeforeRouteLockItem, nt) then
            self.bookDest = BookType.NoBook
        end
    elseif self.bookDest == BookType.RouteOver then
        if (not self.short) and CheckUnlockRouteLock(self.destBeforeRouteLockItem, nt) then
            self.bookDest = BookType.NoBook
        end
    end

    if self.book == BookType.NoBook then
        self.relatedLever = ""
        self.beforeRouteLockItem = ""
        self.direction = RouteDirection.None
    end
    if self.bookDest == BookType.NoBook then
        self.destRelatedLever = ""
        self.destBeforeRouteLockItem = ""
        self.destDirection = RouteDirection.None
        self.destTimer = -1
    end
end

return Track
