local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local Complex      = require("src.utils.complex")
---@class Area
local Area         = {}

---@class Area:NtracsObject
---@field name string
---@field itemName number
---@field vertexs Vector2d[] @反時計回りにエリアの頂点を定義
---@field leftVertexId number
---@field axles Axle[] @左から順に車軸情報
---@field leftAreaIds number[] @隣り合うエリア・ポリゴンへの参照
---@field rightAreaIds number[] @隣り合うエリア・ポリゴンへの参照
---@field relatedTracks string[]
---@field updateCallback fun(self: Area, nt: Ntracs, deltaTick?: number): any
---@field cbdata any @コールバック関数で使えるデータ

---@param name number
---@param vertexs Vector2d[] @反時計回りにエリアの頂点を定義
---@param leftVertexId number
---@param leftAreaIds number[] @隣り合うエリア・ポリゴンへの参照
---@param rightAreaIds number[] @隣り合うエリア・ポリゴンへの参照
---@param updateCallback fun(self: Area, nt: Ntracs, deltaTick?: number): any @コールバック関数で使えるデータ
---@return Area
function Area.new(name, vertexs, leftVertexId, leftAreaIds, rightAreaIds, updateCallback)
    local obj = NtracsObject.create_instance(NtracsObject.new(), Area)
    obj.name = "Area"
    obj.itemName = name
    obj.vertexs = vertexs
    obj.leftVertexId = leftVertexId
    obj.leftAreaIds = leftAreaIds
    obj.rightAreaIds = rightAreaIds
    obj.relatedTracks = {}
    obj.axles = {}
    obj.updateCallback = updateCallback
    return obj
end

--- Areaの状態を初期化します。
---@param self Area
function Area:initialize_for_process()
    self.axles = {}
end

--- 渡された座標がエリア内にあるか判定します。
---@param pos Vector2d
---@return boolean
function Area:is_in_area(pos)
    local polygon, x, z = self.vertexs, pos.x, pos.z
    local n = #polygon
    local prod = Complex.new(1, 0)
    for i, v0 in ipairs(polygon) do
        local v1 = polygon[i % n + 1]
        prod = Complex.mul(prod,
            Complex.half_argument(
                Complex.mul(
                    Complex.new(v1.x - x, v1.z - z),
                    Complex.conjugate(Complex.new(v0.x - x, v0.z - z))
                )
            )
        )
    end
    return prod.re < 0
end

---@param v1 Vector2d | Vector3d
---@param v2 Vector2d | Vector3d
---@return number
local function len2(v1, v2)
    return (v1.x - v2.x) * (v1.x - v2.x) + (v1.z - v2.z) * (v1.z - v2.z)
end

---渡された輪軸を、上下線フラグに基づいて順番通り挿入します
---@param axle Axle
function Area:insert_axle(axle)
    local lv = self.vertexs[self.leftVertexId]
    local lself = len2(lv, axle.real_pos)
    local i = #self.axles

    for index, value in ipairs(self.axles) do
        if lself <= len2(lv, value.real_pos) then
            i = index - 1
            break
        end
    end
    table.insert(self.axles, i + 1, axle)
end

return Area
