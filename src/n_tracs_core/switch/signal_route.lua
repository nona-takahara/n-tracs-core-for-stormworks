local SetRoute = require("src.n_tracs_core.switch.set_route")
---@enum SignalRoute
local t = {
    Normal = SetRoute.Normal,
    Reverse = SetRoute.Reverse,
    Indefinite = SetRoute.Indefinite,
    Onewaynormal = 11,
    Onewayreverse = -11,
    Bothway = 21
}
return t
