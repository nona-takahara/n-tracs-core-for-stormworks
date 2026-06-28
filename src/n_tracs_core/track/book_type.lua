---@enum BookType
local t = {
    NoBook = 0,      -- 予約なし
    Temporary = 1,   -- 仮予約
    RouteLock = 2,   -- 進路鎖錠
    Destination = 3, -- 着点
    RouteOver = 4    -- 過走防護
}
return t
