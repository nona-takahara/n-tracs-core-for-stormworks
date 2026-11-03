local NtracsObject = require("src.n_tracs_core.n_tracs_object")
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

--[[#
## [PNPOLY](https://www.wrfranklin.org/Research/Short_Notes/pnpoly.html)

Copyright (c) 1970-2003, Wm. Randolph Franklin

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimers.
    2. Redistributions in binary form must reproduce the above copyright notice in the documentation and/or other materials provided with the distribution.
    3. The name of W. Randolph Franklin may not be used to endorse or promote products derived from this Software without specific prior written permission. 

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
]]
--- 渡された座標がエリア内にあるか判定します。
---@param pos Vector2d
---@return boolean
function Area:is_in_area(pos)
    -- Luaは1始まりのため、Cからの移植にあたり読み替えが必要。注意
    local vert, testx, testz, c, i = self.vertexs, pos.x, pos.z, false, 1
    local nvert = #vert
    local j = nvert
    while i <= nvert do
        if (
            ((vert[i].z>testz) ~= (vert[j].z>testz)) and
	        (testx < (vert[j].x-vert[i].x) * (testz-vert[i].z) / (vert[j].z-vert[i].z) + vert[i].x)
        ) then
            c = not c;
        end
        -- j = i++ //後置インクリメント
        j = i
        i = i + 1
    end
    return c
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
