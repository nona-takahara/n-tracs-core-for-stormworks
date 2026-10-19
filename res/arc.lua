-- ARC (自動進路制御) の駅データ。書式は src/n_tracs_arc/arc.lua の型注釈(ArcSequence / ArcMove / ArcOption)を参照。
-- 駅データは未定義(stations が空)のとき、ARCは何もしない。
local value = require("res.arc_value")

---@param sw SoyaBridge
return function(sw)
    sw:create_arc({
        -- 指令値の分解と、列車の見分け方。路線の指令の形式に合わせて差し替える
        parse = value.parse,
        train_id = value.train_id,
        -- 複数の駅が共有する予約資源。release: 持ち主がat上に現れ、b(指令値の上下線)が一致したら放す
        reservations = {},
        stations = {},
    })
end
