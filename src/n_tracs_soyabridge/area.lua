require('src.utils.complex')

---@class Area
Area = Area or {}

---@class Area
---@field name string
---@field itemName string
---@field vertexs Vector2d[] @反時計回りにエリアの頂点を定義
---@field leftVertexId number
---@field axles Axle[] @左から順に車軸情報
---@field nodeToArea Area[] @隣り合うエリア・ポリゴンへの参照
---@field updateCallback function
---@field cbdata any @コールバック関数で使えるデータ

function Area.overWrite(baseObject, name, vertexs, leftVertexId, nodeToArea, updateCallback)
    baseObject = baseObject or {}
    baseObject.name = "Area"
    baseObject.itemName = name
    baseObject.vertexs = vertexs
    baseObject.leftVertexId = leftVertexId
    baseObject.nodeToArea = nodeToArea
    baseObject.updateCallback = updateCallback
    return baseObject
end

--- Areaの状態を初期化します。
---@param self Area
function Area.initializeForProcess(self)
    self.axles = {}
end

--- 渡された座標がエリア内にあるか判定します。
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

---渡された輪軸を、上下線フラグに基づいて順番通り挿入します
---@param axle Axle
function Area.insertAxle(self, axle)
    local lv = self.vertexs[self.leftVertexId]
    local lself = Len2(lv, axle.real_pos)
    local i = 0

    for index, value in ipairs(self.axles) do
        local l = Len2(lv, value.real_pos)
        if lself > l then
            i = index
        else
            break
        end
    end
    table.insert(self.axles, i + 1, axle)
end
