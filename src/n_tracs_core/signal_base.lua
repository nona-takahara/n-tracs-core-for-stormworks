-- N-TRACS Core [Signal Base]

---列車・車両の進行方向を表現します
---@enum RouteDirection
RouteDirection = {
    None = 0,
    Left = 1,
    Right = 2
}

---てこに関する操作を行います
---@class SignalBase:NtracsObject
---@field HR boolean
---@field protected aspect number
---@field protected nextAspect number
---@field direction RouteDirection [CONSTANT]進路てこの方向
---@field protected updateCallback fun(lever: SignalBase, deltaTick: number):number
---@field cbdata any
SignalBase = SignalBase or {}

function SignalBase.process(self, deltaTick)
    if self.name=="Lever" then
        ---@diagnostic disable-next-line: param-type-mismatch
        Lever.process(self, deltaTick)
    elseif self.name=="AutoSignal" then
        ---@diagnostic disable-next-line: param-type-mismatch
        AutoSignal.process(self, deltaTick)
    end
end

function SignalBase.beforeProcess(self)
    if self.name=="Lever" then
        ---@diagnostic disable-next-line: param-type-mismatch
        Lever.beforeProcess(self)
    elseif self.name=="AutoSignal" then
        ---@diagnostic disable-next-line: param-type-mismatch
        AutoSignal.beforeProcess(self)
    end
end
