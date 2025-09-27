ADDON_NAME = "N-TRACS Soya Express Wayside Signals"
ADDON_SHORT_NAME = "SoyaExpress WS"
ADDON_VERSION = "v1.1.2"
CTC_VERSION = "SoyaWS-2"

dofile("res.utils")

--コマンド部分の修正が済むまで一時的にsysをglobalにする
local _ = require("src.n_tracs_soyabridge.soya_bridge"); sw = _.new();
_ = require("res.area_track"); _(sw);
_ = require("res.signal"); _(sw);
_ = require("res.switch"); _(sw);
_ = require("res.signal_alias"); _(sw);
_ = require("res.crossing");
local crossing = _(sw);

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
		sw:get_vehicle_data()
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

		while #DELAY_ANNOUNE > 0 do
			local calls = table.remove(DELAY_ANNOUNE, 1)
			if type(calls) == "function" then
				calls()
			end
		end
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

dofile("src.n_tracs_soyabridge.command") -- TODO: 今後修正せねばならない
