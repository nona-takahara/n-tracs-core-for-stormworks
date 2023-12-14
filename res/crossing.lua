function BridgeCrossing(deltaTicks)
    CrossingShionagihama(deltaTicks)
    CrossingOhmori()
end

ShortingTicks_SNH_CA1 = 0
ShortingTicks_SNH_CB1 = 0
function CrossingShionagihama(deltaTicks)
    local t_ca1 = TrackGetter("SNH_CA1")
    local t_ca2 = TrackGetter("SNH_CA2")
    local t_ca3 = TrackGetter("SNH_CA3")

    local t_cb1 = TrackGetter("SNH_CB1")
    local t_cb2 = TrackGetter("SNH_CB2")
    -- local t_cb3 = TrackGetter("SNH_CB3")

    local t_21a = TrackGetter("SNH21AT")
    local t_21b = TrackGetter("SNH21BT")
    local t_22 = TrackGetter("SNH22T")
    local t_4L = TrackGetter("SNH4LT")

    -- 右行（時間条件あり）下本
    local dr1 = false
    if t_ca1.isShort and t_ca1.relatedLever == LEVERS["SNH1R"] then
        dr1 = ShortingTicks_SNH_CA1 < (45 * 60)
        ShortingTicks_SNH_CA1 = ShortingTicks_SNH_CA1 + deltaTicks
    else
        ShortingTicks_SNH_CA1 = 0
    end

    -- 右行（時間条件あり）上本
    local dr2 = false
    if t_cb1.isShort and (t_22.relatedLever == LEVERS["SNH13R"] or t_4L.relatedLever == LEVERS["SNH13R"]) then
        dr2 = ShortingTicks_SNH_CB1 < (45 * 60)
        ShortingTicks_SNH_CB1 = ShortingTicks_SNH_CB1 + deltaTicks
    else
        ShortingTicks_SNH_CB1 = 0
    end

    -- 右行（時間条件なし）下本
    local dr3 = t_ca1.isShort and (LEVERS["SNH3R"].HR or LEVERS["SNH11R"].HR)

    -- 右行（時間条件なし）上本
    local dr4 = t_cb1.isShort and (LEVERS["SNH4R"].HR or LEVERS["SNH12R"].HR)

    -- 左行 引き上げ線停車中
    local dl1 = (t_ca3.isShort and (LEVERS["SNH11L"].HR or LEVERS["SNH12L"].HR or LEVERS["SNH12LZ"].HR))

    -- 左行 わたり線上
    local dl2 =
        (t_21a.isShort and t_21a.direction == RouteDirection.Left) or
        (t_21b.isShort and t_21b.direction == RouteDirection.Left)

    -- 4Lの制御
    local dl3 = false

    local unknown_train = t_cb2.isShort or t_ca2.isShort

    local rets = {left = dl1 or dl2 or dl3, right = dr1 or dr2 or dr3}
    if rets.left or rets.right then
        return rets
    else
        return {left = unknown_train, right = unknown_train}
    end
end

function CrossingOhmori()
    local t_21a = TrackGetter("SNH21AT")
    local t_21b = TrackGetter("SNH21BT")
    local t_oc = TrackGetter("SNH_OC")

    local l = LEVERS["SNH11L"].HR or LEVERS["SNH12L"].HR or LEVERS["SNH12LZ"].HR or LEVERS["SNH4LZ"].HR
    l =
        l or (t_21a.isShort and t_21a.direction == RouteDirection.Left) or
        (t_oc.isShort and t_21b.direction == RouteDirection.Left)
    -- 4L進行での接近条件がまだ入っていない。

    local r = LEVERS["SNH3R"].HR or LEVERS["SNH4R"].HR or LEVERS["SNH11R"].HR or LEVERS["SNH12R"].HR
    r =
        r or (t_21a.isShort and t_21a.direction == RouteDirection.Right) or
        (t_21b.isShort and t_21b.direction == RouteDirection.Right)

    local unknown_train = (not (l or r)) and (t_oc.isShort or t_21a.isShort)

    return {
        left = l or unknown_train,
        right = r or unknown_train
    }
end
