CTC = nil
CTC_ACTIVE = false
CTC_DATA = {}
---@type table<table<string>>
CTC_IN_SIG_TABLE = {
    CTC1 = {
        "NHB4L", "NHB5L", "NHB6L", "NHB11L", "NHB12L", "NHB13L",
        "NHB4R", "NHB11R", "NHB5R", "NHB12R", "NHB13R"
    },
    CTC3 = {
        "WAK1R", "WAK2R", "WAK3L", "WAK4L"
    },
    CTC5 = {
        "SGN1R", "SGN2R", "SGN3L", "SGN4L"
    },
    CTC7 = {
        "SNH1R", "SNH13R", "SNH13RZ", "SNH13L", "SNH11R", "SNH12R", "SNH2L",
        "SNH3R", "SNH4R", "SNH11L", "SNH12L", "SNH12LZ", "SNH4L", "SNH4LZ"
    }
}
CTC_IN_RESET_TABLE = {
    CTC1 = 23, CTC3 = 4, CTC5 = 4, CTC7 = 14
}
CTC_IN_SWITCH_TABLE = {
    CTC1 = { [25] = "NHB21", [27] = "NHB22", [29] = "NHB31" },
    CTC3 = { [6] = "WAK11", [8] = "WAK12" },
    CTC5 = { [6] = "SGN11", [8] = "SGN12" },
    CTC7 = { [16] = "SNH21", [18] = "SNH22" },
}

function GetCtcState()
    local v, ss = server.getVehicleButton(CTC, "Activate CTC")
    CTC_ACTIVE = (ss and v) or false

    for k, _ in pairs(CTC_IN_SIG_TABLE) do
        ---@diagnostic disable-next-line: param-type-mismatch
        CTC_DATA[k] = decode30(server.getVehicleDial(CTC, k))
    end
end

function SetCtcState()
    for k, tbl in pairs(CTC_IN_SIG_TABLE) do
        for i, lvnm in pairs(tbl) do
            ---@type Lever
            ---@diagnostic disable-next-line: assign-type-mismatch
            local lv = LEVERS[lvnm]
            if lv then
                --Lever.setInput(lv, )
            end
        end
    end
end

function MakeCtcData()
end

function SendCtcData(SendingSign)
end

--
---@diagnostic disable-next-line: lowercase-global
function encode30(p)
    local n = ('f'):unpack(('I3B'):pack(p & 0xFFFFFF, 66 + 128 * (p >> 29 & 1) + (p >> 24 & 31)))
    return n
end

-- 第1戻り値：指数部が有効かどうか
---@diagnostic disable-next-line: lowercase-global
function decode30(n)
    local p, h = ('I3B'):unpack(('f'):pack(n))
    local v = 66 <= h and h <= 126 or 194 <= h and h <= 254
    return v, v and (h - 66 >> 2 & 32 | h - 66 & 31) << 24 | p or 0
end
