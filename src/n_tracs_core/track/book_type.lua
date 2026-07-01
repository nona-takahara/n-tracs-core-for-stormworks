---@enum BookType
local t = {
    NoBook            = 0, -- 予約なし
    Temporary         = 1, -- 仮予約
    RouteLock         = 2, -- 進路鎖錠
    Start             = 3, -- 発点
    DestinationActive = 4, -- 着点（過走防護中）
    RouteOver         = 5, -- 過走防護
    DestinationExpired = 6, -- 着点（過走防護解除）
}
return t
