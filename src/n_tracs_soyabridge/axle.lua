local Area = require "src.n_tracs_soyabridge.area"
local NtracsObject = require "src.n_tracs_core.n_tracs_object"
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
---@field area Area | nil @現在のエリア
---@field sending number[]
---@field arc number

---輪軸を初期化します
---@param vehicle_id number
---@param name string
---@param voxelPos Vector3d | nil
---@return Axle
function Axle.new(vehicle_id, name, voxelPos)
    local obj = NtracsObject.createInstance({}, Axle)
    obj.vehicle_id = vehicle_id
    obj.name = "Axle"
    obj.itemName = name
    obj.voxel_pos = voxelPos
    obj.real_pos = { x = 0, z = 0 }
    obj.area = DEFAULT_AREA
    obj.arc = 0
    return obj
end

---輪軸のStormworks座標を取得します
---@param self Axle
function Axle:initializeForProcess()
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
end

---輪軸の現在地を更新します
---@param sys SoyaBridge
function Axle:search(sys)
    self.area = self.area or DEFAULT_AREA

    ---@type number[]
    local queue = {}
    local front = 1

    ---@type Area
    local targetArea
    local found = false

    table.insert(queue, self.area)
    -- BFS
    while front <= #queue do
        targetArea = sys.areas[queue[front]]

        if targetArea:isInArea(self.real_pos) then
            found = true
            break
        end

        -- 隣接エリアをキューに追加
        for _, adjacentArea in ipairs(targetArea.nodeToArea) do
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
        self.area = targetArea
        targetArea:insertAxle(self)
    end
end

---@param sendingSign number
function Axle:send(sendingSign)
    local sending = self.sending or { 0, 0, 0 }
    server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_I1", sending[1] or 0)
    server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_I2", (sending[2] or 0) * sendingSign)
    if sending[2] == 0 or sending[2] == 14 then
        server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_H0", 0)
    else
        server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_H0", sending[1] or 1)
    end
    server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_H1", sendingSign)
    server.setVehicleKeypad(self.vehicle_id, self.itemName .. "_H2", sending[3])
    self.sending = { 0, 0, 0 }
end

return Axle
