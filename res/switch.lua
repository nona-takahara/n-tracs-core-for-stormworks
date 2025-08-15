---@param sw SoyaBridge
return function(sw)
    sw:create_switch("NHB21", { "NHB21" }, { "NHB21T" })
    sw:create_switch("NHB22", { "NHB22a", "NHB22b" }, { "NHB21T", "NHB22T" })
    sw:create_switch("NHB31", { "NHB31" }, { "NHB22T" }, true)

    sw:create_switch("WAK11", { "WAK11" }, { "WAK1RT", "WAK11T" })
    sw:create_switch("WAK12", { "WAK12" }, { "WAK12T" })

    sw:create_switch("SGN21", { "SGN21" }, { "SGN2RT", "SGN21T" })
    sw:create_switch("SGN22", { "SGN22" }, { "SGN22T" })

    sw:create_switch("SNH21", { "SNH21a", "SNH21b" }, { "SNH21AT", "SNH21BT" })
    sw:create_switch("SNH22", { "SNH22" }, { "SNH22T" })
end
