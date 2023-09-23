---@class VehicleInfo
---@field axles Axle[] | nil
---@field bridges VehicleBridge | nil

---@class VehicleBridge
---@field levers Lever[]
---@field tracks Track[]
---@field points PointSetter[]

---@type VehicleInfo[]
VehicleTable = {}

function onVehicleLoad(vehicle_id)
	local vdata, s = server.getVehicleData(vehicle_id)
	if not s then return end

	VehicleTable[vehicle_id] = {
		axles = LoadAxles(vehicle_id, vdata, false),
		bridges = LoadBridgeDatas(vdata)
	}
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
	--[[
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

---comments
---@param vdata SWVehicleData
---@return VehicleBridge | nil
function LoadBridgeDatas(vdata)
	if not vdata then return nil end
	local f = false

	for _, button in ipairs(vdata.components.buttons) do
		if button.name == "N-TRACS RESET" then
			f = true
			break
		end
	end
	if not f then return nil end

	---@type VehicleBridge
	local bridges = { tracks = {}, levers = {}, points = {} }
	for _, sign in ipairs(vdata.components.signs) do
		if TRACKS[sign.name] then
			table.insert(bridges.tracks, TRACKS[sign.name])
		end
		if POINTLIST[sign.name] then
			table.insert(bridges.points, POINTLIST[sign.name])
		end
		if LEVERS[sign.name] then
			table.insert(bridges.levers, LEVERS[sign.name])
		end
	end

	--[[
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
	]]
	return bridges
end

---comments
---@param vehicle_id number
---@param bridge VehicleBridge
function SendBridge(vehicle_id, bridge)
	for _, lever in ipairs(bridge.levers) do
		local sending = lever.aspect
		server.setVehicleKeypad(vehicle_id, lever.itemName .. "_ASPECT", sending * SendingSign)
		if lever.itemName == "WAK_SGN1" then
			server.setVehicleKeypad(vehicle_id, "ATS", AREAS["23"].cbdata or 0)
		end
	end

	for _, track in ipairs(bridge.tracks) do
		local sending = 1 - (track.isShort and 1 or 0)
		server.setVehicleKeypad(vehicle_id, track.itemName .. "R", sending * SendingSign)
	end

	for _, point in ipairs(bridge.points) do
		server.setVehicleKeypad(vehicle_id, point.switchName .. "W", SWITCHES[point.switchName].W)

		local sending = Switch.getWLR(SWITCHES[point.switchName]) and 1 or 0
		server.setVehicleKeypad(vehicle_id, point.switchName .. "WLR", sending * SendingSign)
	end
end
