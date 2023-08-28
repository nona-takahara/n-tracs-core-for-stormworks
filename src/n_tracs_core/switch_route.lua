-- N-TRACS Core [SwitchRoute]

---転てつ器と開通方向の情報セットを扱います
---@class SwitchRoute
---@field private rswitch Switch 関連転てつ器
---@field private target TargetRoute 開通希望方向
SwitchRoute = SwitchRoute or {}

---転てつ器と開通方向の情報セットを作成します
---@param rswitch Switch
---@param target TargetRoute
---@return SwitchRoute
function SwitchRoute.new(rswitch, target)
    return {
        name = "SwitchRoute",
        rswitch = rswitch,
        target = target
    }
end

---開通方向が希望のものと同じか調べます
---@param self SwitchRoute
---@return boolean
function SwitchRoute.isTargetRoute(self)
    return Switch.getRealRoute(self.rswitch) == self.target
end

---開通希望方向に転換します
function SwitchRoute.moveToTarget(self)
    Switch.move(self.rswitch, self.target)
end

---comment
---@return Switch
function SwitchRoute.getRelatedSwitch(self)
    return self.rswitch
end
