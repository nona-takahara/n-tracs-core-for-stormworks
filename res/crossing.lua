local RouteDirection = require "src.n_tracs_core.signal.route_direction"
-- 連動が関連する踏切
---@param nt SoyaBridge
return function(nt)
    nt:create_track("SNH_DC", {})
    nt:create_track("SNH_UC", {})
    nt:create_track("OMR_DC", {})
    nt:create_track("OMR_UC", {})

    local ShortingTicks_SNH_CA1 = 0
    local ShortingTicks_SNH_CB1 = 0
    ---@param deltaTicks number
    ---@param nt SoyaBridge
    ---@return table
    local function CrossingShionagihama(deltaTicks, nt)
        local t_ca1 = nt.nt:get_track("SNH_CA1")
        local t_ca2 = nt.nt:get_track("SNH_CA2")
        local t_ca3 = nt.nt:get_track("SNH_CA3")

        local t_cb1 = nt.nt:get_track("SNH_CB1")
        local t_cb2 = nt.nt:get_track("SNH_CB2")
        -- local t_cb3 = nt.nt:get_track("SNH_CB3")

        local t_1R = nt.nt:get_track("SNH1RT")
        local t_21a = nt.nt:get_track("SNH21AT")
        local t_21b = nt.nt:get_track("SNH21BT")
        local t_22 = nt.nt:get_track("SNH22T")
        local t_4L = nt.nt:get_track("SNH4LT")

        -- 右行（時間条件あり）下本
        local dr1 = false
        if t_ca1:is_short() and t_1R.relatedLever == "SNH1R" then
            dr1 = ShortingTicks_SNH_CA1 < (45 * 60)
            ShortingTicks_SNH_CA1 = ShortingTicks_SNH_CA1 + deltaTicks
        else
            ShortingTicks_SNH_CA1 = 0
        end

        -- 右行（時間条件あり）上本
        local dr2 = false
        if t_cb1:is_short() and (t_22.relatedLever == "SNH13R" or t_4L.relatedLever == "SNH13R") then
            dr2 = ShortingTicks_SNH_CB1 < (45 * 60)
            ShortingTicks_SNH_CB1 = ShortingTicks_SNH_CB1 + deltaTicks
        else
            ShortingTicks_SNH_CB1 = 0
        end

        -- 右行（時間条件なし）下本
        local dr3 = t_ca1:is_short() and (
        --nt.nt:get_signal("SNH3R"].HR or
            nt.nt:get_signal("SNH11R").HR)

        -- 右行（時間条件なし）上本
        local dr4 = t_cb1:is_short() and (
        --nt.nt:get_signal("SNH4R"].HR or
            nt.nt:get_signal("SNH12R").HR)

        -- 左行 引き上げ線停車中
        local dl1 = (t_ca3:is_short() and (nt.nt:get_signal("SNH11L").HR or nt.nt:get_signal("SNH12L").HR or nt.nt:get_signal("SNH12LZ").HR))

        -- 左行 わたり線上
        local dl2 =
            (t_21a:is_short() and t_21a.direction == RouteDirection.Left) or
            (t_21b:is_short() and t_21b.direction == RouteDirection.Left)

        -- 4Lの制御
        local dl3 = false

        local unknown_train = t_cb2:is_short() or t_ca2:is_short()

        local rets = { left = dl1 or dl2 or dl3, right = dr1 or dr2 or dr3 or dr4 }
        if rets.left or rets.right then
            return rets
        else
            return { left = unknown_train, right = unknown_train }
        end
    end

    ---@param sys SoyaBridge
    ---@return table
    local function CrossingOhmori(sys)
        local t_21a = nt.nt:get_track("SNH21AT")
        local t_21b = nt.nt:get_track("SNH21BT")
        local t_oc = nt.nt:get_track("SNH_OC")

        local l = nt.nt:get_signal("SNH11L").HR or nt.nt:get_signal("SNH12L").HR or
            nt.nt:get_signal("SNH12LZ")
            .HR -- or nt.nt:get_signal("SNH4LZ").HR
        l =
            l or (t_21a:is_short() and t_21a.direction == RouteDirection.Left) or
            (t_oc:is_short() and t_21b.direction == RouteDirection.Left)
        -- 4L進行での接近条件がまだ入っていない。

        local r = nt.nt:get_signal("SNH11R").HR or
            nt.nt:get_signal("SNH12R")
            .HR --or nt.nt:get_signal("SNH3R").HR or nt.nt:get_signal("SNH4R").HR
        r =
            r or (t_21a:is_short() and t_21a.direction == RouteDirection.Right) or
            (t_21b:is_short() and t_21b.direction == RouteDirection.Right)

        local unknown_train = (not (l or r)) and (t_oc:is_short() or t_21a:is_short())

        return {
            left = l or unknown_train,
            right = r or unknown_train
        }
    end

    -- メインループから呼び出される関数
    ---@param deltaTicks number
    ---@param sys SoyaBridge
    return function(deltaTicks, sys)
        local r
        r = CrossingShionagihama(deltaTicks, sys)
        sys.trackBridge["SNH_DC"].isInAxle = function() return r.right end
        sys.trackBridge["SNH_UC"].isInAxle = function() return r.left end

        r = CrossingOhmori(sys)
        sys.trackBridge["OMR_DC"].isInAxle = function() return r.right end
        sys.trackBridge["OMR_UC"].isInAxle = function() return r.left end
    end
end
