-- N-TRACS Core [SwitchRoute]

---転てつ器と開通方向の情報セットを扱います
---@class SwitchRoute:NtracsObject
---@field private rswitch Switch 関連転てつ器
---@field private target TargetRoute 開通希望方向
SwitchRoute = SwitchRoute or {}

---転てつ器と開通方向の情報セットを作成します
---@param rswitch Switch
---@param target TargetRoute
---@return SwitchRoute
function SwitchRoute.new(rswitch, target)
    local obj = CreateInstance(NtracsObject.new(), SwitchRoute)
    obj.name = "SwitchRoute"
    obj.rswitch = rswitch
    obj.target = target
    return obj
end

---開通方向が希望のものと同じか調べます
---@param self SwitchRoute
---@return boolean
function SwitchRoute.isTargetRoute(self)
    return (self.rswitch):getRealRoute() == self.target
end

---開通希望方向に転換します
function SwitchRoute.moveToTarget(self)
    (self.rswitch):move(self.target)
end

---comment
---@return Switch
function SwitchRoute.getRelatedSwitch(self)
    return self.rswitch
end
