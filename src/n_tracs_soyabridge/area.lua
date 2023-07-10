---@type Area
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
---@param self Area
function Area.clear(self)
    self.upAxle = {}
    self.downAxle = {}
end

---comment
---@param self Area
---@param pos Vector2d
---@return boolean
function Area.isInArea(self, pos)
    local polygon, x, z = self.vertexs, pos.x, pos.z

    local f, vt
    f = false
    for i = 1, (#polygon - 1) do
        if ((polygon[i].z <= z) and polygon[i + 1].z > z)
            or ((polygon[i].z > z) and polygon[i + 1].z <= z) then
            vt = (z - polygon[i].z) / (polygon[i + 1].z - polygon[i].z)
            if x < (polygon[i].x + (vt * (polygon[i + 1].x - polygon[i].x))) then
                f = not f
            end
        end
    end
    if ((polygon[#polygon].z <= z) and polygon[1].z > z)
        or ((polygon[#polygon].z > z) and polygon[1].z <= z) then
        vt = (z - polygon[#polygon].z) / (polygon[1].z - polygon[#polygon].z)
        if x < (polygon[#polygon].x + (vt * (polygon[1].x - polygon[#polygon].x))) then
            f = not f
        end
    end
    return f
end

function Len2(v1, v2)
	return (v1.x - v2.x) * (v1.x - v2.x) + (v1.z - v2.z) * (v1.z - v2.z)
end

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
