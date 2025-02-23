-- N-TRACS Core [Signal Base]

---てこに関する操作を行います
---@class SignalBase:NtracsObject
---@field HR boolean
---@field aspect number
---@field protected nextAspect number
---@field direction RouteDirection [CONSTANT]進路てこの方向
---@field protected updateCallback fun(lever: SignalBase, deltaTick: number):number
---@field cbdata any
local SignalBase = {}

local NtracsObject = require("src.n_tracs_core.n_tracs_object")

function SignalBase.new()
    local obj = NtracsObject.createInstance(NtracsObject.new(), SignalBase)
    obj.name = "SignalBase"
    return obj
end

function SignalBase.process(self, deltaTick)
    error("Abstract Class SignalBase")
end

function SignalBase.beforeProcess(self)
    error("Abstract Class SignalBase")
end

return SignalBase
