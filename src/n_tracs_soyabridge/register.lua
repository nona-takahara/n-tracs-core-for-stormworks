---@class VehicleInfo
---@field axles Axle[] | nil
---@field bridges VehicleBridge | nil

---@class VehicleBridge
---@field levers Lever[]
---@field tracks Track[]
---@field points PointSetter[]
---@field arc_send boolean
---@field alias string[]

---@type VehicleInfo[]
VehicleTable = {}

function onVehicleLoad(vehicle_id)
	local vdata, s = oldGetVehicleData(vehicle_id)
	if not s then return end

	VehicleTable[vehicle_id] = {
		axles = LoadAxles(vehicle_id, vdata, false),
		bridges = LoadBridgeDatas(vehicle_id, vdata)
	}
end

function onVehicleDespawn(vehicle_id)
	VehicleTable[vehicle_id] = nil
	if vehicle_id == CTC then
		CTC = nil
		CTC_ACTIVE = false
	end
end

function onButtonPress(vehicle_id, peer_id, button_name)
	if button_name == "N-TRACS RESET" then
		local vdata, s = oldGetVehicleData(vehicle_id)
		if not s then return end

		VehicleTable[vehicle_id] = VehicleTable[vehicle_id] or {}
		VehicleTable[vehicle_id].bridges = LoadBridgeDatas(vehicle_id, vdata)
	end

	if button_name == "Activate CTC" then
		CTC = vehicle_id
	end
end

---comments
---@param vehicle_id number
---@param vdata SWVehicleData
---@return VehicleBridge | nil
function LoadBridgeDatas(vehicle_id, vdata)
	if not vdata then return nil end
	local f = false
	---@type VehicleBridge
	local bridges = {tracks = {}, levers = {}, points = {}, arc_send = false, alias = {}}

	for _, button in ipairs(vdata.components.buttons) do
		if button.name == "Activate CTC" then
			CTC = vehicle_id
		end

		if button.name == "N-TRACS RESET" then
			f = true
		end

		-- 駅の実装負担軽減：宛先ペインタブルが無くても送信
		local v, _ = (button.name):gsub("_ASPECT", "")
		if BRIDGE_LEVER_ALIAS[v] then
			f = true
			table.insert(bridges.alias, v)
		end
	end
    if not f then return nil end

	for _, sign in ipairs(vdata.components.signs) do
		if TRACKS[sign.name] then
			table.insert(bridges.tracks, TRACKS[sign.name])
			if not bridges.arc_send then
				for _, dial in ipairs(vdata.components.buttons) do
					if dial.name == sign.name .. "_ARC_L" then
						bridges.arc_send = true
						break
					end
					if dial.name == sign.name .. "_ARC_R" then
						bridges.arc_send = true
						break
					end
				end
			end
		end
		if POINTLIST[sign.name] then
			table.insert(bridges.points, POINTLIST[sign.name])
		end
		if LEVERS[sign.name] then
			table.insert(bridges.levers, LEVERS[sign.name])
		end
	end

	return bridges
end

---comments
---@param vehicle_id number
---@param bridge VehicleBridge
function SendBridge(vehicle_id, bridge)
	for _, lever in ipairs(bridge.levers) do
		local sending = lever.aspect
		server.setVehicleKeypad(vehicle_id, lever.itemName .. "_ASPECT", sending * SendingSign)
	end

	for _, alias in ipairs(bridge.alias) do
		local sending = BRIDGE_LEVER_ALIAS[alias].aspect
		server.setVehicleKeypad(vehicle_id, alias .. "_ASPECT", sending * SendingSign)
	end

	for _, track in ipairs(bridge.tracks) do
		local sending = 1 - (track.isShort and 1 or 0)
		server.setVehicleKeypad(vehicle_id, track.itemName .. "R", sending * SendingSign)
		if bridge.arc_send then
			local right_arc = nil
			for _, area in ipairs(BRIDGE_TRACK[track.itemName].areas) do
				if #area.axles > 0 then
					if right_arc == nil then
						server.setVehicleKeypad(vehicle_id, track.itemName .. "_ARC_L", area.axles[1].arc * SendingSign)
					end
					right_arc = area.axles[#area.axles].arc
				end
			end
			if right_arc ~= nil then
				server.setVehicleKeypad(vehicle_id, track.itemName .. "_ARC_R", right_arc * SendingSign)
			else
				server.setVehicleKeypad(vehicle_id, track.itemName .. "_ARC_L", 0)
				server.setVehicleKeypad(vehicle_id, track.itemName .. "_ARC_R", 0)
			end
		end
	end

	for _, point in ipairs(bridge.points) do
		if SWITCHES[point.switchName].W ~= TargetRoute.Indefinite then
			server.setVehicleKeypad(vehicle_id, point.switchName .. "W", SWITCHES[point.switchName].W)
		end

		local sending = Switch.getWLR(SWITCHES[point.switchName]) and 1 or 0
		server.setVehicleKeypad(vehicle_id, point.switchName .. "WLR", sending * SendingSign)
	end
end

---@return SWVehicleData, boolean
---@diagnostic disable-next-line: lowercase-global
function oldGetVehicleData(vehicle_id)
	local vd, ss1 = server.getVehicleData(vehicle_id)
	local lvd, ss2 = server["getVehicleComponents"](vehicle_id)
	if ss1 and ss2 then
		---@type SWVehicleData
		local r = {
			tags_full = vd.tags_full,
			tags = vd.tags,
			---@diagnostic disable-next-line: assign-type-mismatch
			filename = nil,
			transform = vd.transform,
			simulating = vd.simulating,
			mass = lvd.mass,
			voxels = vd.voxels,
			editable = vd.editable,
			invulnerable = vd.invulnerable,
			static = vd.static,
			components = lvd.components
		}
		return r, true
	else
		---@diagnostic disable-next-line: return-type-mismatch
		return nil, false
	end
end
