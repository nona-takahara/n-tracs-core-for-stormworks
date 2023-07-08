-- N-TRACS Core [Track]

---[package]予約ステートです
---@enum BookType
BookType = {
    NoBook = 0,
    Temporary = 1,
    RouteLock = 2,
    Destination = 3,
    RouteOver = 4
}

---軌道回路に関するものです
---@class Track:NtracsObject
---@field private relatedLever Lever | nil
---@field private book BookType
---@field private direction RouteDirection
---@field private timer number
---@field private beforeRouteLockItem Track | Lever | nil
---@field private isShort boolean
Track = Track or {}

---抽象軌道回路データを作成します
---@param itemName string 抽象軌道回路名称です
---@return Track
function Track.new(itemName)
    return {
        name = "Track",
        itemName = itemName,
        relatedLever = nil,
        book = BookType.NoBook,
        direction = RouteDirection.None,
        timer = 0,
        beforeRouteLockItem = nil
    }
end

---[package]
---@package
---@param lever Lever
function Track:bookTemporary(lever)
    if self.book ~= BookType.RouteOver then
        self.relatedLever = lever
        self.book = BookType.Temporary
        self.direction = lever.direction
    end
end

---[package]
---@package
---@param lever Lever
function Track:bookRouteLock(lever, routeLockBefore)
    self.relatedLever = lever
    self.beforeRouteLockItem = routeLockBefore
    self.book = BookType.RouteLock
    self.direction = lever.direction
end

---[package]
---@package
---@param lever Lever
function Track:bookDestination(lever, routeLockBefore)
    self.relatedLever = lever
    self.beforeRouteLockItem = routeLockBefore
    self.book = BookType.Destination
    self.direction = lever.direction
    self.timer = lever.overrunTime
end

---[package]
---@package
---@param lever Lever
function Track:bookOverrun(lever)
    self.relatedLever = lever
    self.beforeRouteLockItem = lever.destination
    self.book = BookType.RouteOver
    self.direction = lever.direction
end

---[package]
---@package
---@param lever Lever
---@return boolean
function Track:isReadyToBookTemporary(lever)
    return (self.book == BookType.NoBook) or (self.book == BookType.Temporary and self.relatedLever == lever) or
        (self.book == BookType.RouteOver and self.direction == lever.direction)
end

---[package]
---@package
---@param lever Lever
---@return boolean
function Track:isRouteLock(lever)
    return self.relatedLever == lever and self.book == BookType.RouteLock
end

---[package]
---@package
---@param lever Lever
---@return boolean
function Track:isOverrunLock(lever)
    return (self.relatedLever == lever and self.book == BookType.RouteOver) or
    (self.book == BookType.RouteLock and self.direction == lever.direction)
end

---[package]
---@package
---@param temporaryIsNotLocked boolean
---@return boolean
function Track:isLocked(temporaryIsNotLocked)
    if temporaryIsNotLocked then
        return (self.book ~= BookType.NoBook) and (self.book ~= BookType.Temporary)
    else
        return self.book ~= BookType.NoBook
    end
end

---[package]
---@package
---@return boolean
function Track:underRouteLock_n()
    return (self.book == BookType.Destination and self.timer < 0) or
    (self.book == BookType.NoBook or self.book == BookType.Temporary)
end


---[private]
---@private
---@param item nil | NtracsObject
---@return boolean
function Track.checkUnlockRouteLock(item)
    if item == nil then return true end
    if item.name == "Track" then
        --Track型が確定しているためエラー回避
        ---@diagnostic disable-next-line
        return Track.underRouteLock_n(item)
    elseif item.name == "Lever" then
        --Lever型が確定しているためエラー回避
        ---@diagnostic disable-next-line
        return Lever.underRouteLock_n(item)
    end
    return false
end

---抽象軌道回路内に在線があればtrueを返却します
---@return boolean
function Track:isShort()
    return self.isShort
end

---processを呼び出す前に実行してください。状態を設定します
---@param isShort boolean
function Track:beforeProcess(isShort)
    self.isShort = isShort
end

---毎ループごとに呼び出してください
---@param deltaTick number
function Track:process(deltaTick)
    if self.book == BookType.RouteLock or self.book == BookType.RouteOver then
        if (not self.isShort) and Track.checkUnlockRouteLock(self.beforeRouteLockItem) then
            self.book = BookType.NoBook
        end
    elseif self.book == BookType.Destination then
        if Track.checkUnlockRouteLock(self.beforeRouteLockItem) then
            self.timer = math.max(self.timer - deltaTick, -1)
            if not self.isShort then
                self.book = BookType.NoBook
            end
        end
    elseif self.book == BookType.NoBook then
        -- do nothing
    elseif self.book == BookType.Temporary then
        if not Lever.getInput(self.relatedLever) then
            self.book = BookType.NoBook
        end
    else
        error("Book mode is wrong")
    end
end
