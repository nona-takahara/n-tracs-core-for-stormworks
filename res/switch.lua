---@param sys SoyaBridge
return function(sys)
    sys:createSwitch("NHB21", { "NHB21" }, { "NHB21T" })
    sys:createSwitch("NHB22", { "NHB22a", "NHB22b" }, { "NHB21T", "NHB22T" })
    sys:createSwitch("NHB31", { "NHB31" }, { "NHB22T" }, true)

    sys:createSwitch("WAK11", { "WAK11" }, { "WAK1RT", "WAK11T" })
    sys:createSwitch("WAK12", { "WAK12" }, { "WAK12T" })

    sys:createSwitch("SGN21", { "SGN21" }, { "SGN2RT", "SGN21T" })
    sys:createSwitch("SGN22", { "SGN22" }, { "SGN22T" })

    sys:createSwitch("SNH21", { "SNH21a", "SNH21b" }, { "SNH21AT", "SNH21BT" })
    sys:createSwitch("SNH22", { "SNH22" }, { "SNH22T" })
end
