-- ARC (自動進路制御) の駅データ。書式と設計は docs/arc.md を参照。
-- 駅データは未定義(stations が空)のとき、ARCは何もしない。
---@param sw SoyaBridge
return function(sw)
    sw:create_arc({
        -- 省略すると運行番号(pp)が1以上の指令値だけを、運行番号で見分けて扱う。
        -- 変えるときは、列車を見分ける値を返す(nilを返した指令値は扱わない): train_id = function(arc) ... end
        -- 複数の駅が共有する予約資源。release: 持ち主がat上に現れ、b(指令値の上下線)が一致したら放す
        reservations = {},
        stations = {},
    })
end
