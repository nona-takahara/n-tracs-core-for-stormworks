-- ARC (自動進路制御) の駅データ。書式と設計は docs/arc.md を参照。
-- 駅データは未定義(stations が空)のとき、ARCは何もしない。
---@param sw SoyaBridge
return function(sw)
    sw:create_arc({
        -- 速さがこの値(m/s)以下なら停車とみなす
        stop_speed = 0.5,
        -- 複数の駅が共有する予約資源。release: 持ち主がat上に現れ、b(指令値の上下線)が一致したら放す
        reservations = {},
        stations = {},
    })
end
