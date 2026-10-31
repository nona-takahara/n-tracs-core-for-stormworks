-- ARC (自動進路制御) の駅データ。書式は src/n_tracs_arc/arc.lua の型注釈(ArcSequence / ArcMove / ArcOption)を参照。
-- 仕様は Docs「宗弥急行 ARC 制御仕様」。
-- 文字列(資源名・id)はminify後も残るのでASCIIだけにする。日本語の意味はコメントで補う。
local value = require("res.arc_value")

-- 駅コード(行先の十の位)。https://nonasaba.net/sw-train-docs/support/Soya-Express-ARC.html
local CODE_HLT = 2 -- 掘戸町の駅コードは2で確定。この駅では終着を見ないので、値は使われない
local CODE_NHB = 3
local CODE_TKM = 4
local CODE_SNH = 5
local CODE_NMC = 6

-- 到着の直後の入換が、着線に先頭軸が入ってから待つ秒数
local WAIT_NHB_DOWN = 60 -- 北港 下り到着(NHB2R)のあと
local WAIT_SNH_DOWN = 60 -- 潮凪浜 下り到着(SNH1R)のあと
local WAIT_TKM_DOWN = 30 -- 高見が丘 下り到着(TKM1R)のあと
local WAIT_SNH_UP = 30 -- 潮凪浜 上り到着(SNH4L)のあと

---キー名を文字列として実行時に使う表(駅名・資源名・予約資源名)は、この関数で作る。
---minify は、表の定数のキー(HLT = ... も ["HLT"] = ... も)を短縮してしまい、`stations["NHB"]` のような文字列での参照が合わなくなる。
---キーを実行時に代入すれば短縮されない
---@param ... any キー, 値, キー, 値, ...
---@return table
local function dict(...)
    local t, a = {}, { ... }
    for i = 1, #a, 2 do t[a[i]] = a[i + 1] end
    return t
end

-- 指令値の判定 -----------------------------------------------------------------
-- 上り=b==1(北港・掘戸町方面へ向かう)、下り=b==2(潮凪浜・南江町方面へ向かう)
local function down(arc) return arc.b == 2 end
local function up(arc) return arc.b == 1 end
---その駅が行先(終着)の指令値。行先なし(駅コード0)も終着として扱う(ホームには着けるが、次の駅へは出発しない)
local function terminal(arc, code) return arc.station == code or arc.station == 0 end
---その駅を通過して先へ行く指令値
local function through(arc, code) return arc.station ~= 0 and arc.station ~= code end
---番線の指定が合うか(0は自動選択。8・9は入換用の指定なので、駅への到着では自動選択と同じに扱う)
local function platform(arc, ...)
    if arc.platform == 0 or arc.platform >= 8 then return true end
    for _, p in ipairs({ ... }) do
        if arc.platform == p then return true end
    end
    return false
end
---入換の行き先: その駅の指定した番線(9は同一方向の引き上げ線)と、動きの向き(b: 1が上り=L、2が下り=R)
local function shunt_to(p, b)
    return function(arc, code) return arc.station == code and arc.platform == p and arc.b == b end
end

-- 書式の短縮 ---------------------------------------------------------------------
---選択肢が一つの「動き」
---@param class number
---@param signal string
---@param enter string[]
---@param o table|nil from / start_point / wait(ArcMove)と uses / dest / reserve / accept / settle(ArcOption)
local function move(class, signal, enter, o)
    o = o or {}
    return {
        class = class, enter = enter, from = o.from, start_point = o.start_point, wait = o.wait,
        options = { { signal = signal, uses = o.uses, dest = o.dest, reserve = o.reserve, accept = o.accept, settle = o.settle } },
    }
end

---@param id string
---@param at string[]
---@param accept fun(arc: any, code: number): boolean
---@param moves table[]
local function seq(id, at, accept, moves)
    return { id = id, match = { at = at, accept = accept }, moves = moves }
end

local function down_through(arc, code) return down(arc) and through(arc, code) end
local function up_through(arc, code) return up(arc) and through(arc, code) end
local function down_terminal(arc, code) return down(arc) and terminal(arc, code) end
local function up_terminal(arc, code) return up(arc) and terminal(arc, code) end

---@param sw SoyaBridge
return function(sw)
    -- 掘戸町 -------------------------------------------------------------
    -- 資源: P1=ホーム(HLT1LT)。下り出発で掘戸線予約資源を取る
    -- 北港の3番に列車がいても出してよい(3番からは下り出発しかできず、掘戸線を使わないため)
    local hlt = {
        code = CODE_HLT,
        resources = dict( "P1", { "HLT1LT" } ),
        sequences = {
            seq("down_depart", { "HLT1LT" }, down_through, {
                move(3, "HLT1R", { "HLT_NHB1T" }, { from = "P1", reserve = { name = "HLT", mode = "take" } }),
            }),
        },
    }

    -- 北港 ---------------------------------------------------------------
    -- 資源: P3=3番(NHB5LT)、P4=4番(NHB4LT)、SINGLE=単線部分(NHB21T, NHB22AT)、XOVER=渡り(NHB23T)、
    --       UPMAIN=上り本線の北港側の最初の閉塞(NHB13RT)、HLT=掘戸線(HLT_NHB1T)、
    --       HLT_P1=掘戸町のホーム(HLT1LT。上り出発の着線として、空いているときだけ出す)
    -- 「使う資源」は、そのてこの route_lock と一致させる(下り出発は NHB21T, NHB22AT だけ。上り到着はこれに NHB23T, NHB13RT が加わる)
    -- 予約資源 HLT=掘戸線予約資源。1番(NHB14LT)・2番(NHB6LT)は留置線で、構内入換だけを扱う。掘戸町から列車を出してよいので、3番の列車は予約資源を取れないと上り出発ができない
    -- 制御開始点(start_point)は tests/measure_start_points.lua で測った(場内と、一連の動きの出発だけ。停車中の出発と入換には要らない)。
    -- 信号は約400m手前で視認され制動が手配されるので、startの軌道回路が短いと、さらに上流になる
    local nhb = {
        code = CODE_NHB,
        resources = dict(
            "P3", { "NHB5LT" },
            "P4", { "NHB4LT" },
            "P2", { "NHB6LT" },
            "P1", { "NHB14LT" },
            "SINGLE", { "NHB21T", "NHB22AT" },
            "XOVER", { "NHB23T" },
            "UPMAIN", { "NHB13RT" },
            "HLT", { "HLT_NHB1T" },
            "HLT_P1", { "HLT1LT" }
        ),
        sequences = {
            seq("down_through", { "HLT_NHB1T" }, down_through, {
                move(1, "NHB2R", { "NHB5LT" }, { start_point = "HLT_NHB1T", dest = "P3", reserve = { name = "HLT", mode = "hold" } }),
                move(1, "NHB5R", { "NHB21T" }, { start_point = "HLT_NHB1T", uses = { "SINGLE" } }),
            }),
            seq("up_through", { "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T" }, up_through, {
                -- 掘戸町のホーム(HLT_P1)に列車がいるときは予約資源を取らない。取ると、その列車は予約資源を待ち、
                -- 上り列車は掘戸町のホームを待って、互いに動けなくなる(route_lock にはない、デッドロックを避けるための例外)
                move(1, "NHB5L", { "NHB13RT" }, { start_point = "TKM_NHB3T", uses = { "UPMAIN", "SINGLE", "XOVER", "HLT_P1" }, dest = "P3", reserve = { name = "HLT", mode = "take" } }),
                move(1, "NHB2L", { "HLT_NHB1T" }, { start_point = "TKM_NHB1T", uses = { "HLT" }, dest = "HLT_P1", reserve = { name = "HLT", mode = "hold" } }),
            }),
            seq("down_terminal", { "HLT_NHB1T" }, down_terminal, {
                move(2, "NHB2R", { "NHB5LT" }, { start_point = "HLT_NHB1T", dest = "P3", reserve = { name = "HLT", mode = "hold" }, settle = true }),
            }),
            seq("up_terminal", { "TKM_NHB3T", "TKM_NHB2T", "TKM_NHB1T" }, up_terminal, {
                {
                    -- 4番を先に当てる。3番は掘戸線予約資源が空いているときだけ
                    class = 2, enter = { "NHB13RT" }, start_point = "TKM_NHB3T",
                    options = {
                        { signal = "NHB4L", uses = { "UPMAIN", "SINGLE", "XOVER" }, dest = "P4", settle = true, accept = function(arc) return platform(arc, 4) end },
                        {
                            signal = "NHB5L", uses = { "UPMAIN", "SINGLE", "XOVER" }, dest = "P3", reserve = { name = "HLT", mode = "free" }, settle = true,
                            accept = function(arc) return platform(arc, 3) end,
                        },
                    },
                },
            }),
            seq("down_depart_p3", { "NHB5LT" }, down_through, {
                move(3, "NHB5R", { "NHB21T" }, { from = "P3", uses = { "SINGLE" } }),
            }),
            seq("down_depart_p4", { "NHB4LT" }, down_through, {
                move(3, "NHB4R", { "NHB21T" }, { from = "P4", uses = { "SINGLE" } }),
            }),
            -- 構内入換: NHB13RT 発着。駅の外からの進入は上の NHB4L・NHB5L(TKM_NHB1T 発)を使う。
            -- NHB13RT にいる列車は NHB11L〜14L だけが出る(NHB4L・NHB5L は出ない)。行先は指令値の北港の番線(1〜4)で、9 は NHB13RT 側
            seq("yard_to_p4", { "NHB13RT" }, shunt_to(4, 1), {
                move(4, "NHB11L", { "NHB23T" }, { uses = { "XOVER", "SINGLE" }, dest = "P4" }),
            }),
            seq("yard_to_p3", { "NHB13RT" }, shunt_to(3, 1), {
                move(4, "NHB12L", { "NHB23T" }, { uses = { "XOVER", "SINGLE" }, dest = "P3", reserve = { name = "HLT", mode = "free" } }),
            }),
            seq("yard_to_p2", { "NHB13RT" }, shunt_to(2, 1), {
                move(4, "NHB13L", { "NHB23T" }, { uses = { "XOVER" }, dest = "P2" }),
            }),
            seq("yard_to_p1", { "NHB13RT" }, shunt_to(1, 1), {
                move(4, "NHB14L", { "NHB23T" }, { uses = { "XOVER" }, dest = "P1" }),
            }),
            seq("p4_to_yard", { "NHB4LT" }, shunt_to(9, 2), {
                move(5, "NHB11R", { "NHB21T" }, { from = "P4", uses = { "SINGLE", "XOVER" }, dest = "UPMAIN" }),
            }),
            seq("p3_to_yard", { "NHB5LT" }, shunt_to(9, 2), {
                move(5, "NHB12R", { "NHB21T" }, { from = "P3", uses = { "SINGLE", "XOVER" }, dest = "UPMAIN", wait = WAIT_NHB_DOWN }),
            }),
            seq("p2_to_yard", { "NHB6LT" }, shunt_to(9, 2), {
                move(5, "NHB13R", { "NHB23T" }, { from = "P2", uses = { "XOVER" }, dest = "UPMAIN" }),
            }),
            seq("p1_to_yard", { "NHB14LT" }, shunt_to(9, 2), {
                move(5, "NHB14R", { "NHB23T" }, { from = "P1", uses = { "XOVER" }, dest = "UPMAIN" }),
            }),
            -- 引き上げ線 → 3番。停車後は、同じ指令値が上り出発(up_depart)になる。
            -- 外から入る上り通しは、NHB13RT に入った時点で「一連の動き」の途中なので、ここでは登録されない
            seq("yard_to_p3_depart", { "NHB13RT" }, up_through, {
                move(4, "NHB12L", { "NHB23T" }, { uses = { "XOVER", "SINGLE" }, dest = "P3", reserve = { name = "HLT", mode = "free" } }),
            }),
            -- 北港始発の掘戸町ゆき。掘戸町から列車が出て予約資源が取れないときは、3番からは下り出発しかできない
            seq("up_depart", { "NHB5LT" }, up_through, {
                move(3, "NHB2L", { "HLT_NHB1T" }, { from = "P3", uses = { "HLT" }, dest = "HLT_P1", reserve = { name = "HLT", mode = "take" } }),
            }),
        },
    }

    -- 高見が丘 -----------------------------------------------------------
    -- 資源: P1=1番(TKM1RT)、P2=2番(TKM2T)、W1(TKM21AT)、X(TKM21BT)、W2(TKM22T)、W3A(TKM23AT)、W3B(TKM23BT)、
    --       S1=側1(TKM11RT)、S2=側2(TKM12RT)、YARD=引き上げ線(TKM15RT)、DNMAIN=下り本線潮方(TKM3RT)、
    --       UPAPP=上り本線の手前の閉塞(TKM4LT。上り到着の route_lock に入っている)
    -- 電留(TKM13RT)との出入りはARCでは取らない
    -- 入換の行き先は、指令値の「高見が丘の番線」で決める(1・2: その番線へ、9: 引き上げ線方向)
    local tkm = {
        code = CODE_TKM,
        resources = dict(
            "P1", { "TKM1RT" }, "P2", { "TKM2T" },
            "W1", { "TKM21AT" }, "X", { "TKM21BT" }, "W2", { "TKM22T" },
            "W3A", { "TKM23AT" }, "W3B", { "TKM23BT" },
            "S1", { "TKM11RT" }, "S2", { "TKM12RT" }, "YARD", { "TKM15RT" },
            "DNMAIN", { "TKM3RT" }, "UPAPP", { "TKM4LT" }
        ),
        sequences = {
            seq("down_through", { "NHB_TKM3T", "NHB_TKM2T", "NHB_TKM1T" }, down_through, {
                move(1, "TKM1R", { "TKM1RT" }, { start_point = "NHB_TKM3T", dest = "P1" }),
                move(1, "TKM3R", { "TKM21AT" }, { start_point = "NHB_TKM1T", uses = { "W1", "DNMAIN" } }),
            }),
            seq("up_through", { "SGN_TKM3T", "SGN_TKM2T", "SGN_TKM1T" }, up_through, {
                move(1, "TKM4L", { "TKM4LT" }, { start_point = "SGN_TKM3T", uses = { "UPAPP", "X", "W2" }, dest = "P2" }),
                move(1, "TKM2L", { "TKM2LT" }, { start_point = "SGN_TKM1T" }),
            }),
            seq("down_terminal", { "NHB_TKM3T", "NHB_TKM2T", "NHB_TKM1T" }, function(arc, code) return down_terminal(arc, code) and platform(arc, 1) end, {
                move(2, "TKM1R", { "TKM1RT" }, { start_point = "NHB_TKM3T", dest = "P1", settle = true }),
            }),
            seq("up_terminal", { "SGN_TKM3T", "SGN_TKM2T", "SGN_TKM1T" }, function(arc, code) return up_terminal(arc, code) and platform(arc, 2) end, {
                move(2, "TKM4L", { "TKM4LT" }, { start_point = "SGN_TKM3T", uses = { "UPAPP", "X", "W2" }, dest = "P2" }),
            }),
            seq("down_depart", { "TKM1RT" }, down_through, {
                move(3, "TKM3R", { "TKM21AT" }, { from = "P1", uses = { "W1", "DNMAIN" } }),
            }),
            seq("up_depart", { "TKM2T" }, up_through, {
                move(3, "TKM2L", { "TKM2LT" }, { from = "P2" }),
            }),
            -- 側線 → ホーム(据え付け)
            seq("s2_to_p2", { "TKM12RT" }, shunt_to(2, 1), {
                move(4, "TKM12L", { "TKM22T" }, { uses = { "W2" }, dest = "P2" }),
            }),
            seq("s1_to_p1", { "TKM11RT" }, shunt_to(1, 1), {
                move(4, "TKM11L", { "TKM21BT" }, { uses = { "X", "W1" }, dest = "P1" }),
            }),
            -- 引き上げ線 → 側線
            seq("yard_to_s2", { "TKM15RT" }, shunt_to(2, 1), {
                move(4, "TKM15L", { "TKM23BT" }, { uses = { "W3B" }, dest = "S2" }),
            }),
            seq("yard_to_s1", { "TKM15RT" }, shunt_to(1, 1), {
                move(4, "TKM14L", { "TKM23BT" }, { uses = { "W3B", "W3A" }, dest = "S1" }),
            }),
            -- 引き上げ線 → 側2 → 2番。停車後は、同じ指令値が上り出発(up_depart)になる
            seq("yard_to_p2_depart", { "TKM15RT" }, up_through, {
                move(4, "TKM15L", { "TKM23BT" }, { uses = { "W3B" }, dest = "S2" }),
                move(4, "TKM12L", { "TKM22T" }, { from = "S2", uses = { "W2" }, dest = "P2" }),
            }),
            -- ホーム → 側線(引き上げ線へ向かう)
            seq("p1_to_s1", { "TKM1RT" }, shunt_to(9, 2), {
                move(5, "TKM11R", { "TKM21AT" }, { from = "P1", uses = { "W1", "X" }, dest = "S1", wait = WAIT_TKM_DOWN }),
            }),
            seq("p2_to_s2", { "TKM2T" }, shunt_to(9, 2), {
                move(5, "TKM12R", { "TKM22T" }, { from = "P2", uses = { "W2" }, dest = "S2" }),
            }),
            -- 側線 → 引き上げ線
            seq("s1_to_yard", { "TKM11RT" }, shunt_to(9, 2), {
                move(5, "TKM14R", { "TKM23AT" }, { uses = { "W3A", "W3B" }, dest = "YARD" }),
            }),
            seq("s2_to_yard", { "TKM12RT" }, shunt_to(9, 2), {
                move(5, "TKM15R", { "TKM23BT" }, { uses = { "W3B" }, dest = "YARD" }),
            }),
        },
    }

    -- 潮凪浜 -------------------------------------------------------------
    -- 番線: 下り本線=1番(SNH1RT)、上り本線=2番(SNH4LT)、引き上げ=9番(SNH3RT)、ループ方面の途中(13L/R)=8番(SNH13LT)
    -- 資源: P1=1番、P2=2番、L8=8番、DN=下り方引き上げ線(9番)、WA(SNH21AT)、WB(SNH21BT)、WL(SNH22T)
    -- 通しの「動き」は置かない。すべての列車が到着の「動き」で停車し、出発は停車後の指令値で行う
    local snh = {
        code = CODE_SNH,
        resources = dict(
            "P1", { "SNH1RT" }, "P2", { "SNH4LT" }, "L8", { "SNH13LT" },
            "WA", { "SNH21AT" }, "WB", { "SNH21BT" }, "DN", { "SNH3RT" }, "WL", { "SNH22T" }
        ),
        sequences = {
            -- 番線の桁は行先の駅の番線なので、見るのは潮凪浜が終着のときだけ(先の駅ゆきの列車の番線は見ない)
            seq("down_arrive", { "SGN_SNH2T", "SGN_SNH1T" }, function(arc, code) return down(arc) and (through(arc, code) or platform(arc, 1)) end, {
                move(2, "SNH1R", { "SNH1RT" }, { start_point = "SGN_SNH3T", dest = "P1", settle = true }),
            }),
            seq("up_arrive", { "NMC_SNH2T", "NMC_SNH1T" }, function(arc, code) return up(arc) and (through(arc, code) or platform(arc, 2)) end, {
                move(2, "SNH4L", { "SNH21BT" }, { start_point = "NMC_SNH2T", uses = { "WB" }, dest = "P2", settle = true }),
            }),
            seq("down_depart_p1", { "SNH1RT" }, down_through, {
                move(3, "SNH3R", { "SNH21AT" }, { from = "P1", uses = { "WA", "DN" } }),
            }),
            seq("down_depart_p2", { "SNH4LT" }, down_through, {
                move(3, "SNH4R", { "SNH21BT" }, { from = "P2", uses = { "WB", "WA", "DN" } }),
            }),
            seq("up_depart", { "SNH4LT" }, up_through, {
                move(3, "SNH2L", { "SNH22T" }, { from = "P2", uses = { "WL" } }),
            }),
            -- 入換: 下り方引き上げ線(9番)を介した折り返しと、ループ方面(8番)
            seq("yard_to_p1", { "SNH3RT" }, shunt_to(1, 1), {
                move(4, "SNH11L", { "SNH21AT" }, { uses = { "WA" }, dest = "P1" }),
            }),
            seq("yard_to_p2", { "SNH3RT" }, shunt_to(2, 1), {
                move(4, "SNH12L", { "SNH21AT" }, { uses = { "WA", "WB" }, dest = "P2" }),
            }),
            -- 引き上げ線 → 2番。停車後は、同じ指令値が上り出発(up_depart)になる
            seq("yard_to_p2_depart", { "SNH3RT" }, up_through, {
                move(4, "SNH12L", { "SNH21AT" }, { uses = { "WA", "WB" }, dest = "P2" }),
            }),
            seq("p1_to_yard", { "SNH1RT" }, shunt_to(9, 2), {
                move(5, "SNH11R", { "SNH21AT" }, { from = "P1", uses = { "WA" }, dest = "DN", wait = WAIT_SNH_DOWN }),
            }),
            seq("p2_to_yard", { "SNH4LT" }, shunt_to(9, 2), {
                move(5, "SNH12R", { "SNH21BT" }, { from = "P2", uses = { "WB", "WA" }, dest = "DN" }),
            }),
            seq("p2_to_loop", { "SNH4LT" }, shunt_to(8, 1), {
                move(5, "SNH13L", { "SNH22T" }, { from = "P2", uses = { "WL" }, dest = "L8", wait = WAIT_SNH_UP }),
            }),
            seq("loop_to_p2", { "SNH13LT" }, shunt_to(2, 2), {
                move(4, "SNH13R", { "SNH22T" }, { uses = { "WL" }, dest = "P2" }),
            }),
            -- 引き上げ・電留線 → 2番。停車後は、同じ指令値が下り出発(down_depart_p2)になる
            seq("loop_to_p2_depart", { "SNH13LT" }, down_through, {
                move(4, "SNH13R", { "SNH22T" }, { uses = { "WL" }, dest = "P2" }),
            }),
        },
    }

    -- 南江町 -------------------------------------------------------------
    -- 資源: P12=1・2番ホーム(NMC1RT。1L/R)、P3=3番ホーム(NMC2RT。2L/R)、WN=分岐(NMC11T)、EXIT=上り方(NMC1LT)
    local nmc = {
        code = CODE_NMC,
        resources = dict(
            "P12", { "NMC1RT" }, "P3", { "NMC2RT" },
            "WN", { "NMC11T" }, "EXIT", { "NMC1LT" }
        ),
        sequences = {
            seq("down_terminal", { "SNH_NMC2T", "SNH_NMC1T" }, down_terminal, {
                {
                    class = 2, enter = { "NMC11T" }, start_point = "SNH_NMC2T",
                    options = {
                        { signal = "NMC1R", uses = { "WN" }, dest = "P12", accept = function(arc) return platform(arc, 1, 2) end },
                        { signal = "NMC2R", uses = { "WN" }, dest = "P3", accept = function(arc) return platform(arc, 3) end },
                    },
                },
            }),
            seq("up_depart_p12", { "NMC1RT" }, up_through, {
                move(3, "NMC1L", { "NMC11T" }, { from = "P12", uses = { "WN", "EXIT" } }),
            }),
            seq("up_depart_p3", { "NMC2RT" }, up_through, {
                move(3, "NMC2L", { "NMC11T" }, { from = "P3", uses = { "WN", "EXIT" } }),
            }),
        },
    }

    sw:create_arc({
        -- 指令値の分解と、列車の見分け方。路線の指令の形式に合わせて差し替える
        parse = value.parse,
        train_id = value.train_id,
        -- 複数の駅が共有する予約資源。release: 持ち主がat上に現れ、b(指令値の上下線)が一致したら放す
        reservations = dict(
            -- 掘戸線予約資源: 下りで北港の3番に入り、掘戸線を抜けたとき放す
            "HLT", { release = { { at = { "NHB5LT" }, b = 2 } } }
        ),
        stations = dict("HLT", hlt, "NHB", nhb, "TKM", tkm, "SNH", snh, "NMC", nmc),
    })
end
