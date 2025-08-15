local sw = require("src.n_tracs_soyabridge.soya_bridge").new()

require("res.area_track")(sw)
require("res.signal")(sw)
require("res.switch")(sw)
require("res.signal_alias")(sw)
local crossing = require("res.crossing")(sw)
