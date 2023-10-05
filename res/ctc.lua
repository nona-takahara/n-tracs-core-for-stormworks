CTC = nil
CTC_ACTIVE = false
CTC_DATA = { IN = {}, OUT = {} }

CTC_IN = CTC_IN or {}
CTC_OUT = CTC_OUT or {}

CTC_IN.SIG_TABLE = {
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
CTC_IN.RESET_TABLE = {
    CTC1 = 23, CTC3 = 4, CTC5 = 4, CTC7 = 14
}
CTC_IN.SWITCH_TABLE = {
    CTC1 = { [25] = "NHB21", [27] = "NHB22", [29] = "NHB31" },
    CTC3 = { [6] = "WAK11", [8] = "WAK12" },
    CTC5 = { [6] = "SGN11", [8] = "SGN12" },
    CTC7 = { [16] = "SNH21", [18] = "SNH22" },
}


CTC_OUT.TRACK_TABLE_FULL = {
    CTC10 = { [1] = "NHB4LT", [3] = "NHB5LT", [5] = "NHB6LT", [7] = "NHB21T", [9] = "NHB22T", [11] = "NHB13RT" },
    CTC30 = { [1] = "WAK1RAT", [3] = "WAK1RBT", [5] = "WAK12T", [7] = "WAK11T", [9] = "WAK4LT" },
    CTC50 = { [1] = "SGN1RAT", [3] = "SGN1RBT", [5] = "SGN12T", [7] = "SGN11T", [9] = "SGN4LT" },
    CTC70 = {
        [1] = "SNH1RT",
        [3] = "SNH22T",
        [5] = "SNH13LT",
        [7] = "SNH4LT",
        [9] = "SNH21AT",
        [11] = "SNH21BT",
        [13] = "SNH3RT"
    }
}

CTC_OUT.TRACK_TABLE_MIN = {
    CTC20 = { "NHB_WAK1T", "WAK_NHB1T" },
    CTC40 = { "WAK_SNG5T", "WAK_SNG4T", "WAK_SNG3T", "WAK_SNG2T", "WAK_SNG1T" },
    CTC41 = { "SGN_WAK6T", "SGN_WAK5T", "SGN_WAK4T", "SGN_WAK3T", "SGN_WAK2T", "SGN_WAK1T" },
    CTC60 = {
        [1] = "SGN_SNH5T",
        [2] = "SGN_SNH4T",
        [3] = "SGN_SNH3T",
        [4] = "SGN_SNH2T",
        [5] = "SGN_SNH1T",
        [18] = "SNH_SGN4T",
        [19] = "SNH_SGN3T",
        [20] = "SNH_SGN2T",
        [21] = "SNH_SGN1T"
    }
}

CTC_OUT.SWITCH_TABLE = {
    CTC10 = { [25] = "NHB21", [27] = "NHB22", [29] = "NHB31" },
    CTC30 = { [11] = "WAK11", [13] = "WAK12" },
    CTC50 = { [11] = "SGN11", [13] = "SGN12" },
    CTC70 = { [15] = "SNH21", [17] = "SNH22" }
}

-- 現示部1ビット
CTC_OUT.SIGNAL_TABLE_G = {
    CTC11 = {
        [1] = "NHB4L",
        [9] = "NHB11L",
        [11] = "NHB12L",
        [13] = "NHB13L",
        [18] = "NHB11R",
        [23] = "NHB12R",
        [25] = "NHB13R"
    },
    CTC70 = { [19] = "SNH1R", [21] = "SNH13R", [23] = "SNH13RZ", [25] = "SNH13L", [27] = "SNH11R", [29] = "SNH12R" }
}

-- 現示部2ビット
CTC_OUT.SIGNAL_TABLE_YG = {
    CTC11 = { [3] = "NHB5L", [6] = "NHB6L", [15] = "NHB4R", [20] = "NHB5R" },
    CTC20 = { [3] = "WAK_NHB1" },
    CTC30 = { [15] = "WAK1R", [18] = "WAK2R", [21] = "WAK3L", [24] = "WAK4L" },
    CTC40 = { [6] = "WAK_SGN4", [9] = "WAK_SGN3", [12] = "WAK_SGN2", [15] = "WAK_SGN1" },
    CTC41 = { [7] = "SGN_WAK5", [10] = "SGN_WAK4", [13] = "SGN_WAK3", [16] = "SGN_WAK2", [19] = "SGN_WAK1" },
    CTC50 = { [15] = "SGN1R", [18] = "SGN2R", [21] = "SGN3L", [24] = "SGN4L" },
    CTC60 = {
        [6] = "SGN_SNH4",
        [9] = "SGN_SNH3",
        [12] = "SGN_SNH2",
        [15] = "SGN_SNH1",
        [22] = "SNH_SGN3",
        [25] = "SNH_SGN2",
        [28] = "SNH_SGN1"
    },
    CTC71 = { [1] = "SNH2L", [4] = "SNH3R", [7] = "SNH4R" }
}

-- 将来に備えて用意
CTC_OUT.SIGNAL_TABLE_YY = {

}

function GetCtcState()
    local v, ss = server.getVehicleButton(CTC, "Activate CTC")
    CTC_ACTIVE = (ss and v) or false

    for k, _ in pairs(CTC_IN.SIG_TABLE) do
        local vv, ss = server.getVehicleDial(CTC, k)

        if ss then
            ---@diagnostic disable-next-line: param-type-mismatch
            CTC_DATA.IN[k] = decode30(vv)
        end
    end
end

function SetCtcState()
    for k, _ in pairs(CTC_IN.SIG_TABLE) do
        local ctc_v = CTC_DATA.IN[k] or 0
        local rst = Getbit(ctc_v, CTC_IN.RESET_TABLE[k]) == 1

        for i, lvnm in pairs(CTC_IN.SIG_TABLE[k]) do
            ---@type Lever
            ---@diagnostic disable-next-line: assign-type-mismatch
            local lv = LEVERS[lvnm]
            if lv then
                if rst then
                    Lever.setInput(lv, false, false)
                elseif Getbit(ctc_v, i) == 1 then
                    Lever.setInput(lv, true,
                        not (lvnm == "WAK1R" or lvnm == "WAK4L" or lvnm == "SGN1R" or lvnm == "SGN4L"))
                end
            end
        end

        for i, swnm in pairs(CTC_IN.SWITCH_TABLE[k]) do
            local sw = SWITCHES[swnm]
            if sw then
                if Getbit(ctc_v, i) == 1 then
                    Switch.move(sw, TargetRoute.Normal)
                elseif Getbit(ctc_v, i + 1) == 1 then
                    Switch.move(sw, TargetRoute.Reverse)
                end
            end
        end
    end
end

function MakeCtcData()
    for k, v in pairs(CTC_OUT.TRACK_TABLE_FULL) do
        local vv = CTC_DATA.OUT[k] or 0
        for i, n in pairs(v) do
            local tr = TRACKS[n]
            if tr then
                vv = Setbit(vv, i, TRACKS[n].isShort and 1 or 0)
                vv = Setbit(vv, i + 1, Track.isLocked(TRACKS[n], true) and 1 or 0)
            end
        end
        CTC_DATA.OUT[k] = vv
    end

    for k, v in pairs(CTC_OUT.TRACK_TABLE_MIN) do
        local vv = CTC_DATA.OUT[k] or 0
        for i, n in pairs(v) do
            local tr = TRACKS[n]
            if tr then
                vv = Setbit(vv, i, tr.isShort and 1 or 0)
            end
        end
        CTC_DATA.OUT[k] = vv
    end

    for k, v in pairs(CTC_OUT.SWITCH_TABLE) do
        local vv = CTC_DATA.OUT[k] or 0
        for i, n in pairs(v) do
            local sk = SWITCHES[n]
            if sk then
                vv = Setbit(vv, i, sk.K == TargetRoute.Normal and 1 or 0)
                vv = Setbit(vv, i + 1, sk.K == TargetRoute.Reverse and 1 or 0)
            end
        end
        CTC_DATA.OUT[k] = vv
    end

    for k, v in pairs(CTC_OUT.SIGNAL_TABLE_G) do
        local vv = CTC_DATA.OUT[k] or 0
        for i, n in pairs(v) do
            local lv = LEVERS[n]
            if lv then
                vv = Setbit(vv, i, lv.input and 1 or 0)
                vv = Setbit(vv, i + 1, lv.aspect > 0 and 1 or 0)
            end
        end
        CTC_DATA.OUT[k] = vv
    end

    for k, v in pairs(CTC_OUT.SIGNAL_TABLE_YG) do
        local vv = CTC_DATA.OUT[k] or 0
        for i, n in pairs(v) do
            local lv = LEVERS[n]
            if lv then
                local ab = math.max(lv.aspect - 1, 0)
                vv = Setbit(vv, i, lv.input and 1 or 0)
                vv = Setbit(vv, i + 1, (ab % 2) == 1 and 1 or 0)
                vv = Setbit(vv, i + 2, (ab // 2) == 1 and 1 or 0)
            end
        end
        CTC_DATA.OUT[k] = vv
    end

    for k, v in pairs(CTC_OUT.SIGNAL_TABLE_YY) do
        local vv = CTC_DATA.OUT[k] or 0
        for i, n in pairs(v) do
            local lv = LEVERS[n]
            if lv then
                local ab = math.max(lv.aspect, 0)
                vv = Setbit(vv, i, lv.input and 1 or 0)
                vv = Setbit(vv, i + 1, (ab % 2) == 1 and 1 or 0)
                vv = Setbit(vv, i + 2, (ab // 2) == 1 and 1 or 0)
            end
        end
        CTC_DATA.OUT[k] = vv
    end
end

function SendCtcData(SendingSign)
    for k, v in pairs(CTC_DATA.OUT) do
        server.setVehicleKeypad(CTC, k, encode30(v))
        CTC_DATA.OUT[k] = 0
    end
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

function Getbit(v, b)
    return (v >> (b - 1)) & 1
end

---comments
---@param t integer
---@param b integer
---@param v integer
---@return integer
function Setbit(t, b, v)
    if v then
        t = t & ~(1 << (b - 1))
    else
        t = t | ~(1 << (b - 1))
    end
    return v
end
