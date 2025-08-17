local Area = require("src.n_tracs_soyabridge.area")
local NtracsObject = require("src.n_tracs_core.n_tracs_object")
---@class Axle:NtracsObject
local Axle = {}

---@class Vector3d
---@field x number
---@field y number
---@field z number

---@class Vector2d
---@field x number
---@field z number

---@class Axle
---@field name string
---@field itemName string
---@field vehicle_id number @車軸のあるビークルID
---@field voxel_pos Vector3d | nil @車軸のボクセル
---@field real_pos Vector2d @実際の位置
---@field area number | nil @現在のエリア
---@field sending number[]
---@field arc number
---@field disable_short boolean

---輪軸を初期化します
---@param vehicle_id number
---@param name string
---@param voxelPos Vector3d | nil
---@return Axle
function Axle.new(vehicle_id, name, voxelPos)
    local obj = NtracsObject.create_instance({}, Axle)
    obj.vehicle_id = vehicle_id
    obj.name = "Axle"
    obj.itemName = name
    obj.voxel_pos = voxelPos
    obj.real_pos = { x = 0, z = 0 }
    obj.area = nil
    obj.arc = 0
    obj.disable_short = false
    return obj
end

---輪軸のStormworks座標を取得します
---@param self Axle
function Axle:get_position()
    ---@type SWMatrix
    local mtx
    ---@type boolean
    local ss
    if self.voxel_pos == nil then
        ---@diagnostic disable-next-line: missing-parameter
        mtx, ss = server.getVehiclePos(self.vehicle_id)
    else
        mtx, ss = server.getVehiclePos(self.vehicle_id, self.voxel_pos.x, self.voxel_pos.y, self.voxel_pos.z)
    end

    if ss then
        local x, y, z = matrix.position(mtx)
        self.real_pos = { x = x, z = z }
    end

    ---@type SWVehicleDialData
    local dialArc
    dialArc, ss = server.getVehicleDial(self.vehicle_id, self.itemName .. "_ARC")
    if ss then
        self.arc = dialArc.value
    end

    ---@type SWVehicleDialData
    local dial_disable_short
    dial_disable_short, ss = server.getVehicleDial(self.vehicle_id, "TRAIN_SHORT")
    if ss then
        self.disable_short = dial_disable_short.value == 1
    end
end

---輪軸の現在地を更新します
---@param sw SoyaBridge
function Axle:search(sw)
    self.area = self.area or sw.default_area
    if self.disable_short then
        self.area = nil
        return
    end

    ---@type number[]
    local queue = {}
    local front = 1

    ---@type Area
    local targetArea
    local found = false

    table.insert(queue, self.area)
    -- BFS
    while front <= #queue do
        targetArea = sw.areas[queue[front]]

        if targetArea:is_in_area(self.real_pos) then
            found = true
            break
        end

        -- 隣接エリアをキューに追加
        for _, adjacentArea in ipairs(targetArea.leftAreaIds) do
            -- 重複チェック
            local alreadyExist = false
            for _, a in ipairs(queue) do
                if a == adjacentArea then
                    alreadyExist = true
                    break
                end
            end

            if not alreadyExist then
                table.insert(queue, adjacentArea)
            end
        end

        for _, adjacentArea in ipairs(targetArea.rightAreaIds) do
            -- 重複チェック
            local alreadyExist = false
            for _, a in ipairs(queue) do
                if a == adjacentArea then
                    alreadyExist = true
                    break
                end
            end

            if not alreadyExist then
                table.insert(queue, adjacentArea)
            end
        end

        front = front + 1
    end

    if found then
        self.area = targetArea.itemName
        targetArea:insert_axle(self)
    else
        self.area = nil
    end
end

---@param sign number
function Axle:send(sign)
    local sending = self.sending or { 0, 0 }
    server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_H0", sending[1])
    server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_H1", 1 * sign)
    server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_H2", sending[2])
    self.sending = { 0, 0 }
end

return Axle
