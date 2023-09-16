---@class Axle
Axle = Axle or {}

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
    return {
        vehicle_id = vehicle_id,
        name = "Axle",
        itemName = name,
        voxel_pos = voxelPos,
        real_pos = { x = 0, z = 0 },
        area = DEFAULT_AREA,
        arc = 0
    }
end

---輪軸のStormworks座標を取得します
---@param self Axle
function Axle.initializeForProcess(self)
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
---@param self Axle
function Axle.search(self)
    self.area = self.area or DEFAULT_AREA

    ---@type Area[]
    local queue = {}
    local front = 1
    ---@type Area
    local targetArea
    local found = false

    table.insert(queue, self.area)

    -- BFS
    while front <= #queue do
        targetArea = queue[front]

        if Area.isInArea(targetArea, self.real_pos) then
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
        Area.insertAxle(targetArea, self)
    end
end
