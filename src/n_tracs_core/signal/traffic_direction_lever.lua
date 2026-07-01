-- 運転方向てこ

local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local SignalBase = require("src.n_tracs_core.signal.signal_base")


---@class TrafficDirectionLever:SignalBase
---@field myFrDirection SetRoute
---@field myFrName string
---@field anotherFrName string
---@field private input boolean
local TrafficDirectionLever = {}

---@param name string
---@param myFrDirection SetRoute 反位方向（出し側として書き込む値）。両端で同じ値を使うこと
---@param myFrName string 自端の仮想方向スイッチ名
---@param anotherFrName string 相手端の仮想方向スイッチ名
---@return TrafficDirectionLever
function TrafficDirectionLever.new(name, myFrDirection, myFrName, anotherFrName)
    local obj = NtracsObject.create_instance(SignalBase.new(), TrafficDirectionLever)
    obj.name = "TrafficDirectionLever"
    obj.itemName = name
    obj.myFrDirection = myFrDirection
    obj.myFrName = myFrName
    obj.anotherFrName = anotherFrName
    obj.input = false
    return obj
end

---@param deltaTick number
---@param nt Ntracs
function TrafficDirectionLever:process(deltaTick, nt)
    if self.input then
        -- 反位 = 出し側: 相手端が同方向を向いていることを確認してから書き込む
        if nt:get_switch(self.anotherFrName):getRealRoute() == self.myFrDirection then
            nt:get_switch(self.myFrName):move(self.myFrDirection, nt)
        end
    else
        -- 定位 = 受け側: 逆方向を書き込む（出し側チェックが成立する値をセット）
        nt:get_switch(self.myFrName):move(-self.myFrDirection, nt)
    end
end

---@param input boolean
---@param nt Ntracs|nil
---@param fromControl boolean|nil
function TrafficDirectionLever:setInput(input, nt, fromControl)
    self.input = input
end

function TrafficDirectionLever:before_process()

end

return TrafficDirectionLever
