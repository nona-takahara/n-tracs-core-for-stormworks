-- N-TRACS Core [Switch]
local NtracsObject           = require("src.n_tracs_core.n_tracs_object")
local SetRoute               = require("src.n_tracs_core.switch.set_route")

---転てつ器に関する情報です
---@class TrafficDirectionSwitch:Switch
---@field W SetRoute
---@field isSite true
---@field private relatedTracks string[]
local TrafficDirectionSwitch = {}

---転てつ器情報を作成します
---@param itemName string 転てつ器名称
---@param relatedTracks string[] てっ査鎖錠を行う抽象軌道回路
---@return Switch
function TrafficDirectionSwitch.new(itemName, relatedTracks)
    local obj = NtracsObject.create_instance({}, TrafficDirectionSwitch)
    obj.name = "TrafficDirectionSwitch"
    obj.itemName = itemName
    obj.W = SetRoute.Indefinite
    obj.isSite = true
    obj.relatedTracks = relatedTracks
    return obj
end

---現在の開通方向を取得します
---@return SetRoute
function TrafficDirectionSwitch:getRealRoute()
    return self.W
end

---@param target SetRoute
---@param nt Ntracs
function TrafficDirectionSwitch:move(target, nt)
    for _, value in ipairs(self.relatedTracks) do
        if nt:get_track(value):is_short() or nt:get_track(value):is_locked(not self.isSite) then
            return
        end
    end
    self.W = target
end

---Signal.checkWLR から呼ばれる。仮想方向分岐器は信号のWLR条件に関与しないため常にfalseを返す。
---転換可否は move() 内で独自に判定する。
---@param nt Ntracs
---@return boolean
function TrafficDirectionSwitch:getWLR(nt)
    return false
end

---processの実行前に呼び出してください。現在の状態を設定します
---@param currentState SetRoute 現在の開通方向
function TrafficDirectionSwitch:before_process(currentState)
    -- note: 実位置の変更は、moveと同じ安全チェックが原則になりそう。Kってリセットされるっけ？
    self.K = self.W -- 仮想分岐器: 実位置=指令位置（物理フィードバックなし）
end

---毎ループごとに呼び出してください
---@param deltaTick number
---@param nt Ntracs
function TrafficDirectionSwitch:process(deltaTick, nt)
end

return TrafficDirectionSwitch
