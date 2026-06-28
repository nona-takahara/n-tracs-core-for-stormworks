ADDON_NAME = "N-TRACS Soya Express Wayside Signals"
ADDON_SHORT_NAME = "SoyaExpress WS"
ADDON_VERSION = "v2.0.0-beta4"
CTC_VERSION = "SoyaWS-3"

error = error or function(message)
	debug.log("[N-TRACS] ERROR: " .. tostring(message))
end

dlog = function(message)
	debug.log("[N-TRACS] DEBUG: " .. tostring(message))
end

local soya_bridge = require("src.n_tracs_soyabridge.soya_bridge")
local sw = soya_bridge.new()
local apply_area_track = require("res.area_track")
local apply_signal = require("res.signal")
local apply_switch = require("res.switch")
local apply_signal_alias = require("res.signal_alias")
local crossing_factory = require("res.crossing")
local apply_command = require("src.n_tracs_soyabridge.command")

apply_area_track(sw)
apply_signal(sw)
apply_switch(sw)
apply_signal_alias(sw)

local crossing = crossing_factory(sw)
local command_module = apply_command(sw)

dofile("res.maplabel")

sw.default_area = 2

g_savedata = {
	recommendedSettings = property.checkbox("Start with no wind and damage", true),
	cheatBattery = property.checkbox("Enable cheat_battery feature", true),
}

function onCreate(is_world_create)
	if is_world_create and g_savedata.recommendedSettings then
		server.setGameSetting("vehicle_damage", false)
		server.setGameSetting("player_damage", false)
		server.setGameSetting("npc_damage", false)
		local starttile = server.getStartTile()
		local weather = server.getWeather(matrix.translation(starttile.x, starttile.y, starttile.z))
		server.setGameSetting("override_weather", true)
		server.setWeather(weather.fog, weather.rain, 0)
	end

	if not g_savedata.ui_id then
		AddMapLabels(0)
	end
end

function onDestroy()
	local playerlist = server.getPlayers()
	local ui_id = g_savedata.ui_id
	if ui_id then
		for _, v in pairs(playerlist) do
			server.removeMapID(v.id, ui_id)
		end
	end
	g_savedata = nil
end

function onPlayerJoin(steam_id, name, peer_id, is_admin, is_auth)
	AddMapLabels(peer_id)
end

function onPlayerLeave(steam_id, name, peer_id, is_admin, is_auth)
	if g_savedata.ui_id then
		server.removeMapID(peer_id, g_savedata.ui_id)
	end
end

---[Stormworks] onTick function.
-- 1 Tickごとに呼び出されます.
function onTick()
	TickCounter = (TickCounter or 0) + 1

	-- 毎Tick実行しないとsignal_batを3に充電できない
	sw:charge_battery(g_savedata.cheatBattery)

	Phase = ((Phase or 0) + 1) % 6
	if Phase == 1 then
		sw:get_vehicle_data(6)
	elseif Phase == 2 then
		sw:before_process()
	elseif Phase == 3 then
		sw:process(6)
		crossing(6, sw)
	elseif Phase == 4 then
		sw:before_broadcast(6)
	elseif Phase == 5 then
		-- 全ての情報を配信するフェーズ
		SendingSign = (SendingSign or -1) * -1
		sw:broadcast(SendingSign)

		while #command_module.DELAY_ANNOUNE > 0 do
			local calls = table.remove(command_module.DELAY_ANNOUNE, 1)
			if type(calls) == "function" then
				calls()
			end
		end
	end
end

---@diagnostic disable-next-line: lowercase-global
function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, ...)
	if command == "?ntracs" or command == "?nt" then
		local args = { ... }
		if command_module.COMMANDS[args[1]] then
			local cmd = command_module.COMMANDS[args[1]]
			if (not cmd.admin or (cmd.admin and is_admin)) and (not cmd.auth or (cmd.auth and is_auth)) then
				cmd.command(args, is_admin, is_auth, peer_id)
			end
		else
			command_module.Announce(
				"ERROR! " .. ADDON_SHORT_NAME .. " command '" .. tostring(args[1]) .. "' is not found", peer_id)
		end
	end

	if command == "?help" then
		command_module.Announce("For more help, use ?nt help", peer_id)
	end
end

function onVehicleLoad(vehicle_id)
	sw:load_vehicle(vehicle_id)
end

function onVehicleDespawn(vehicle_id)
	sw:despawn_vehicle(vehicle_id)
end

function onButtonPress(vehicle_id, peer_id, button_name)
	if button_name == "N-TRACS RESET" then
		sw:load_vehicle(vehicle_id)
	end

	--if button_name == "Activate CTC" then
	--	CTC = vehicle_id
	--end
end
