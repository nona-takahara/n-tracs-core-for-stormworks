ADDON_NAME = "N-TRACS Soya Express Wayside Signals"
ADDON_SHORT_NAME = "SoyaExpress WS"
ADDON_VERSION = "v1.1.2"
CTC_VERSION = "SoyaWS-2"

SYS = require("src.n_tracs_soyabridge.soyabridge").new()
require("res.area_track")(SYS)
require("res.signal")(SYS)
require("res.switch")(SYS)
require("res.signal_alias")()
require("res.crossing")()
require("res.ctc")()

SYS.defaultArea = 2
--Lever.setInput(LEVERS["WAK1R"], true, false)
--Lever.setInput(LEVERS["WAK4L"], true, false)
--Lever.setInput(LEVERS["SGN1R"], true, false)
--Lever.setInput(LEVERS["SGN2R"], true, false)
--Lever.setInput(LEVERS["SGN5L"], true, false)

-- Stormworksを騙す。関数の後にコンマを入れないと認識してくれないようである。
FAKE_PROPERTY =
[[
g_savedata = {
	recommendedSettings = property.checkbox("Start with no wind and damage", true),
	cheatBattery = property.checkbox("Enable cheat_battery feature", true),
}
--]]

_ENV["g_savedata"] = {
	recommendedSettings = property.checkbox("Start with no wind and damage", true),
	cheatBattery = property.checkbox("Enable cheat_battery feature", true)
}

function onCreate(is_world_create)
	if is_world_create and _ENV["g_savedata"].recommendedSettings then
		server.setGameSetting("vehicle_damage", false)
		server.setGameSetting("player_damage", false)
		server.setGameSetting("npc_damage", false)
		local starttile = server.getStartTile()
		local weather = server.getWeather(matrix.translation(starttile.x, starttile.y, starttile.z))
		server.setGameSetting("override_weather", true)
		server.setWeather(weather.fog, weather.rain, 0)
	end

	if not _ENV["g_savedata"].ui_id then
		AddMapLabels(0)
	end
end

function onDestroy()
	local playerlist = server.getPlayers()
	local ui_id = _ENV["g_savedata"].ui_id
	if ui_id then
		for _, v in pairs(playerlist) do
			server.removeMapID(v.id, ui_id)
		end
	end
	_ENV["g_savedata"] = nil
end

function onPlayerJoin(steam_id, name, peer_id, is_admin, is_auth)
	AddMapLabels(peer_id)
end

function onPlayerLeave(steam_id, name, peer_id, is_admin, is_auth)
	if _ENV["g_savedata"].ui_id then
		server.removeMapID(peer_id, _ENV["g_savedata"].ui_id)
	end
end

---[Stormworks] onTick function.
-- 1 Tickごとに呼び出されます.
function onTick()
	TickCounter = (TickCounter or 0) + 1

	-- 毎Tick実行しないとsignal_batを3に充電できない
	SYS:chargeBattery(_ENV["g_savedata"].cheatBattery)

	Phase = ((Phase or 0) + 1) % 6
	if Phase == 1 then
		SYS:beforeDateUpdate()
		SYS:getVehicleData()
	elseif Phase == 2 then
		SYS:trackShort()
		-- CTC取得データの変換
		--if CTC_AVAILABLE and CTC_ACTIVE then
		--	SetCtcState()
		--end
	elseif Phase == 3 then
		SYS:beforeProcess()
	elseif Phase == 4 then
		SYS:process(6)
		-- BridgeCrossing(6)
	elseif Phase == 5 then
		SYS:beforeBroadcast()
		-- CTCデータ生成
		--if CTC_AVAILABLE and CTC then
		--    MakeCtcData()
		--end
	elseif Phase == 0 then
		-- 全ての情報を配信するフェーズ
		SendingSign = (SendingSign or -1) * -1
		SYS:broadcast(SendingSign)

		while #DELAY_ANNOUNE > 0 do
			local calls = table.remove(DELAY_ANNOUNE, 1)
			if type(calls) == "function" then
				calls()
			end
		end
	end
end

function onVehicleLoad(vehicle_id)
	SYS:loadVehicle(vehicle_id)
end

function onVehicleDespawn(vehicle_id)
	SYS:despawnVehicle(vehicle_id)
end

function onButtonPress(vehicle_id, peer_id, button_name)
	if button_name == "N-TRACS RESET" then
		SYS:loadVehicle(vehicle_id)
	end

	--if button_name == "Activate CTC" then
	--	CTC = vehicle_id
	--end
end
