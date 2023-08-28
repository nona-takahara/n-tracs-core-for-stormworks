require('src.utils.complex')

---@class Area
Area = Area or {}

---@class Area
---@field name string
---@field vertexs Vector2d[] @反時計回りにエリアの頂点を定義
---@field axleModeFlag number @上り下りのフラグ設定
---@field nodeToArea Area[] @隣り合うエリア・ポリゴンへの参照
---@field leftVertexId number
---@field rightVertexId number
---@field upAxle Axle[] @左から順に車軸情報
---@field downAxle Axle[] @左から順に車軸情報



---comment
function Area.clear(self)
    self.upAxle = {}
    self.downAxle = {}
end

---comment
---@param pos Vector2d
---@return boolean
function Area.isInArea(self, pos)
    local polygon, x, z = self.vertexs, pos.x, pos.z
    local n = #polygon
    local prod = Complex.new(1, 0)
    for i, v0 in ipairs(polygon) do
        local v1 = polygon[i % n + 1]
        prod = Complex.mul(prod,
            Complex.halfArgument(
                Complex.mul(
                    Complex.new(v1.x - x, v1.z - z),
                    Complex.conjugate(Complex.new(v0.x - x, v0.z - z))
                )
            )
        )
    end
    return prod.re < 0
end

function Len2(v1, v2)
	return (v1.x - v2.x) * (v1.x - v2.x) + (v1.z - v2.z) * (v1.z - v2.z)
end

---comment
---@param axle any
function Area.insertAxle(self, axle)
    local lv = self.vertexs[self.leftVertexId]
    local lself = Len2(lv, axle.real_pos)
    local i = 0

    if self.axleModeFlag == AxleMode.Up or self.axleModeFlag == AxleMode.Both then
        for index, value in ipairs(self.upAxle) do
            local l = Len2(lv, value.real_pos)
            if lself > l then
                i = index
            else
                break
            end
        end

        table.insert(self.upAxle, i + 1, axle)
    end

    if self.axleModeFlag == AxleMode.Down or self.axleModeFlag == AxleMode.Both then
        i = 0
        for index, value in ipairs(self.downAxle) do
            local l = Len2(lv, value.real_pos)
            if lself > l then
                i = index
            else
                break
            end
        end

        table.insert(self.downAxle, i + 1, axle)
    end
end
