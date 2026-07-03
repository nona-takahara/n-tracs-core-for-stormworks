---@param sw SoyaBridge
return function(sw)
    sw:set_lever_alias("aHLT_D", "HLT1R")
    sw:set_lever_alias("aNHB_3d", "NHB5R") -- 3番線 潮凪浜方
    sw:set_lever_alias("aNHB_3u", "NHB2L") -- 3番線 掘戸方
    sw:set_lever_alias("aNHB_4d", "NHB4R") -- 4番線 潮凪浜方
    sw:set_lever_alias("aAKA_D", "NHB_TKM2")
    sw:set_lever_alias("aAKA_U", "TKM_NHB2")
    sw:set_lever_alias("aTKM_D", "TKM3R")
    sw:set_lever_alias("aTKM_U", "TKM2L")
    sw:set_lever_alias("aONL_D", "TKM_SGN2")
    sw:set_lever_alias("aONL_U", "SGN_TKM2")
    sw:set_lever_alias("aSGN_D", "SGN1R")
    sw:set_lever_alias("aSGN_U", "SGN_TKM4")
    sw:set_lever_alias("aKGM_D", "SGN_SNH2")
    sw:set_lever_alias("aKGM_U", "SNH_SGN2")
    --sys:setLeverAlias("aSNH_D", "") -- 2番線 入守山方
    sw:set_lever_alias("aSNH_U", "SNH2L") -- 1番線 掘戸方
    --sys:setLeverAlias("aSNH_Ud", "") -- 1番線 入守山方]]
end
