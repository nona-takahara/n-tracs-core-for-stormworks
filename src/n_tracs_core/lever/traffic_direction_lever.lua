-- 運転方向てこ

local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local SignalBase   = require("src.n_tracs_core.lever.signal_base")


---@class TrafficDirectionLever:SignalBase
---@field myFrDirection SetRoute
---@field isAcceptLever boolean
---@field myFrName string
---@field anotherFrName string
---@field pairLeverName string
---@field private input boolean
local TrafficDirectionLever = {}

---@param name string
---@param pairLeverName string
---@param myFrDirection SetRoute
---@param isAcceptLever boolean
---@param myFrName string
---@param anotherFrName string
---@return TrafficDirectionLever
function TrafficDirectionLever.new(name, pairLeverName, myFrDirection, isAcceptLever, myFrName, anotherFrName)
    local obj = NtracsObject.createInstance(SignalBase.new, TrafficDirectionLever)
    obj.name = "TrafficDirectionLever"
    obj.itemName = name
    obj.pairLeverName = pairLeverName
    obj.isAcceptLever = isAcceptLever
    obj.myFrDirection = myFrDirection
    obj.myFrName = myFrName
    obj.anotherFrName = anotherFrName
    obj.input = false
    return obj
end

---@param deltaTick number
---@param nt Ntracs
function TrafficDirectionLever:process(deltaTick, nt)
    --TODO: 総括制御条件を入れる（自身のsetInputを呼ぶ）
    if self.input then
        if self.isAcceptLever then
            --NOTE: てっ査鎖錠条件はmove関数で照査されるため、これを区間内在線判定に使用
            nt:get_switch(self.myFrName):move(self.myFrDirection, nt)
        elseif nt:get_switch(self.anotherFrName):getRealRoute() == self.myFrDirection then
            nt:get_switch(self.myFrName):move(self.myFrDirection, nt)
        end
    end
end

---@param input boolean
---@param nt Ntracs
function TrafficDirectionLever:setInput(input, nt)
    --trueなら自分とペアのInputを一緒に倒す
    if input then
        self.input = true

        ---@diagnostic disable-next-line: inject-field
        nt:get_signal(self.pairLeverName):setInput(false)
    end
end

function TrafficDirectionLever:beforeProcess()

end

return TrafficDirectionLever
