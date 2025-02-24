---@param sys SoyaBridge
return function(sys)
    sys:setLeverAlias("aNHB_3d", "NHB5R") -- 3番線 潮凪浜方
    --sys:setLeverAlias("aNHB_3u")=LEVERS["") -- 3番線 掘戸方
    sys:setLeverAlias("aNHB_4d", "NHB4R") -- 4番線 潮凪浜方
    sys:setLeverAlias("aAKA_D", "WAK_SGN4")
    sys:setLeverAlias("aAKA_U", "WAK4L")
    sys:setLeverAlias("aONL_D", "WAK_SGN1")
    sys:setLeverAlias("aONL_U", "SGN_WAK3")
    sys:setLeverAlias("aSGN_D", "SGN2R")
    --sys:setLeverAlias("aSGN_DS", "SGN3R")
    sys:setLeverAlias("aSGN_U", "SGN_WAK5")
    sys:setLeverAlias("aKGM_D", "SGN_SNH1")
    sys:setLeverAlias("aKGM_U", "SNH_SGN2")
    --sys:setLeverAlias("aSNH_D", "") -- 2番線 入守山方
    sys:setLeverAlias("aSNH_U", "SNH2L") -- 1番線 掘戸方
    --sys:setLeverAlias("aSNH_Ud", "") -- 1番線 入守山方
end
