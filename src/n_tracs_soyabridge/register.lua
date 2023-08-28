---@class VehicleInfo
---@field axles Axle[] | nil
---@field bridges any

---@type VehicleInfo[]
VehicleTable = {}

function onVehicleLoad(vehicle_id)
	local vdata, s = server.getVehicleData(vehicle_id)
	if not s then return end

	VehicleTable[vehicle_id] = { axles = LoadAxles(vehicle_id, vdata, false),
		bridges = LoadBridgeDatas(vdata) }
end

function onVehicleDespawn(vehicle_id)
	VehicleTable[vehicle_id] = nil
end

function onButtonPress(vehicle_id, peer_id, button_name)
	if button_name == "N-TRACS RESET" then
		local vdata, s = server.getVehicleData(vehicle_id)
		if not s then return end

		VehicleTable[vehicle_id] = VehicleTable[vehicle_id] or {}
		VehicleTable[vehicle_id].bridges = LoadBridgeDatas(vdata)
	end
	--[[]
    if button_name == "ENABLE CTC" then
		local state, s = server.getVehicleButton(vehicle_id, button_name)
		if state.on then
			CTC = vehicle_id
		else
			CTC = nil
		end
	end
	]]
end

---comment
---@param vehicle_id number
---@param vdata SWVehicleData
---@param forceRegister boolean
---@return Axle[] | nil
function LoadAxles(vehicle_id, vdata, forceRegister)
	---@type Axle[]
	local axles = {}
	for _, sign in ipairs(vdata.components.signs) do
		if sign.name:find("TRAIN") == 1 then
			table.insert(axles,
				Axle.new(vehicle_id, sign.name, { x = sign.pos.x, y = sign.pos.y, z = sign.pos.z }))
		end
	end

	if forceRegister and #axles == 0 then
		axles = { [1] = Axle.new(vehicle_id, "", nil) }
	end
	return axles
end

function LoadBridgeDatas(vdata)
	if not vdata then return end
	local f = false

	for _, button in ipairs(vdata.components.buttons) do
		if button.name == "N-TRACS RESET" then
			f = true
		end
	end
	if not f then return end

	local bridges = { tracks = {}, levers = {}, switches = {}, bridge = { levers = {}, cross = {} } }
	for _, sign in ipairs(vdata.components.signs) do
		if TRACKS[sign.name] then
			table.insert(bridges.tracks, TRACKS[sign.name])
		end
		if SWITCH[sign.name] then
			table.insert(bridges.switches, SWITCH[sign.name])
		end
		if LEVERS[sign.name] then
			table.insert(bridges.levers, LEVERS[sign.name])
		end
	end

	for _, button in ipairs(vdata.components.buttons) do
		local v, _ = (button.name):gsub("_ASPECT", "")
		if BRIDGE_LEVER_ALIAS[v] then
			table.insert(bridges.bridge.levers, v)
		end

		v, _ = (button.name):gsub("CR", "")
		if BRIDGE_CROSS[v] then
			table.insert(bridges.bridge.cross, v)
		end
	end
	return bridges
end
