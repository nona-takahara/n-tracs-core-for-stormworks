local SetRoute = require("src.n_tracs_core.switch.set_route")
---@enum SignalRoute
local t = {
    Normal = SetRoute.Normal,
    Reverse = SetRoute.Reverse,
    Indefinite = SetRoute.Indefinite,
    -- 片鎖錠など各種条件をここに
}
return t
