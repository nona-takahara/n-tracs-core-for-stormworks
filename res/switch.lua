local SetRoute = require("src.n_tracs_core.switch.set_route")
---@param sw SoyaBridge
return function(sw)
    sw:create_switch("NHB21", { "NHB21" }, { "NHB21T" })
    sw:create_switch("NHB22", { "NHB22a", "NHB22b" }, { "NHB22AT", "NHB23T" })
    sw:create_switch("NHB23", { "NHB23" }, { "NHB23T" })

    sw:create_switch("TKM21", { "TKM21" }, { "TKM21AT" })
    sw:create_switch("TKM22", { "TKM22" }, { "TKM22T" })
    sw:create_switch("TKM23", { "TKM23a", "TKM23b" }, { "TKM23AT", "TKM23BT" })

    sw:create_switch("SNH21", { "SNH21a", "SNH21b" }, { "SNH21AT", "SNH21BT" })
    sw:create_switch("SNH22", { "SNH22" }, { "SNH22T" })

    sw:create_traffic_direction_switch("HLT_NHB_FR", { "HLT_NHB1T" })
    sw:create_traffic_direction_switch("NHB_HLT_FR", { "HLT_NHB1T" })
    sw:create_traffic_direction_lever("HLT2R", SetRoute.Normal, "HLT_NHB_FR", "NHB_HLT_FR")  -- 下りがNormal
    sw:create_traffic_direction_lever("NHB1L", SetRoute.Reverse, "NHB_HLT_FR", "HLT_NHB_FR") -- 上りがReverse
end
