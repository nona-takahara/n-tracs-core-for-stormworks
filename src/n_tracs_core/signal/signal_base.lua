-- N-TRACS Core [Signal Base]

---てこに関する操作を行います
---@class SignalBase:NtracsObject
---@field HR boolean
---@field aspect number
---@field protected nextAspect number
---@field direction RouteDirection [CONSTANT]進路てこの方向
---@field protected updateCallback fun(lever: SignalBase, nt: Ntracs, deltaTick: number):number
---@field cbdata any
local SignalBase = {}

local NtracsObject = require("src.n_tracs_core.n_tracs_object")

function SignalBase.new()
    local obj = NtracsObject.create_instance({}, SignalBase)
    obj.name = "SignalBase"
    return obj
end

---@param deltaTick number
---@param nt Ntracs
function SignalBase:process(deltaTick, nt)
    error("Abstract Class SignalBase")
end

function SignalBase:before_process()
    error("Abstract Class SignalBase")
end

return SignalBase
