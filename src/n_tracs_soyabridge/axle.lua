---@class Axle
Axle = Axle or {}

---@class Vector3d
---@field x number
---@field y number
---@field z number

---@class Vector2d
---@field x number
---@field z number

---@enum AxleMode
AxleMode = {
    NoChange = 0,
    Up = 1,
    Down = 2,
    Both = 3
}

---@class Axle
---@field name string
---@field vehicle_id number @車軸のあるビークルID
---@field voxel_pos Vector3d @車軸のボクセル
---@field real_pos Vector2d @実際の位置
---@field hasRealPosSending boolean @実際の位置の送信機能があるか
---@field area Area | nil @現在のエリア
---@field mode number @下り1・上り-1
---@field sending number[]
---@field arc number

function Axle.new(vehicle_id, name, voxelPos)
    return {
        vehicle_id = vehicle_id,
        name = name,
        voxel_pos = voxelPos or { x = 0, y = 0, z = 0 },
        real_pos = { x = 0, z = 0},
        area = DEFAULT_AREA,
        mode = 0,
        arc = 0
    }
end

---comment
---@param self Axle
function Axle.refresh(self)
    if self.hasRealPosSending then
        local dialData, ss = server.getVehicleDial(self.vehicle_id, self.name .. "_POS")
        if ss then
            self.real_pos = { x = dialData.value, z = dialData.value2 }
        end
    else
        local mtx, ss = server.getVehiclePos(self.vehicle_id)
        if ss then
            local x, y, z = matrix.multiplyXYZW(mtx, self.voxel_pos.x, self.voxel_pos.y, self.voxel_pos.z, 1)
            self.real_pos = { x = x, z = z }
        end
    end

    local dialArc, ss = server.getVehicleDial(self.vehicle_id, self.name .. "_ARC")
    if ss then
        self.arc = dialArc.value
    end
end

function Axle.search(self)
    ---@type Area[]
    local q = {}
    ---@type Area
    local a
    local top = 1
    local found = false

    self.area = self.area or DEFAULT_AREA

    -- BFS
    table.insert(q, self.area)
    q[1].bfsFootmark = true
    while #(q) >= top do
        a = q[top]
        top = top + 1
        if Area.isInArea(a, self.real_pos)then
            found = true
            break
        else
            for _, aa in ipairs(a.nodeToArea) do
                if aa.bfsFootmark == false then
                    aa.bfsFootmark = true
                    table.insert(q, aa)
                end
            end
        end
    end

    for _, v in ipairs(q) do
        v.bfsFootmark = false
    end

    if found then
        self.area = a
        if a.axleModeFlag ~= AxleMode.NoChange then
            self.mode = a.axleModeFlag
        end
        Area.insertAxle(a, self)
    end
end