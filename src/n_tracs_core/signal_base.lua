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
---@field aspect number
---@field protected nextAspect number
---@field direction RouteDirection [CONSTANT]進路てこの方向
---@field protected updateCallback fun(lever: SignalBase, deltaTick: number):number
---@field cbdata any
SignalBase = SignalBase or {}

function SignalBase.new()
    local obj = CreateInstance(NtracsObject.new(), SignalBase)
    obj.name = "SignalBase"
    return obj
end

function SignalBase.process(self, deltaTick)
    error("Abstract Class SignalBase")
end

function SignalBase.beforeProcess(self)
    error("Abstract Class SignalBase")
end
