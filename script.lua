-- N-TRACS 宗弥急行 Wayside Signal

-- 1. Load N-TRACS Core
require("src.n_tracs_core")

-- 2. Load settings
require("res.areas")
require("res.levers")

-- 3. Load bridge
require("src.n_tracs_soyabridge")

---[Stormworks] onTick function.
-- 1 Tickごとに呼び出されます.
function onTick()
	TickCounter = TickCounter + 1

	for vehicle_id, _ in pairs(VehicleTable) do
		server.setVehicleBattery(vehicle_id, "signal_bat", 3)
	end

	Phase = (Phase + 1) % 6
	if Phase == 1 then
		for _, area in ipairs(AREAS) do
			Area.clear(area)
		end

		for _, data in pairs(VehicleTable) do
			if data.axles then
				for _, axle in ipairs(data.axles) do
					Axle.refresh(axle)
				end
			end
		end
	elseif Phase == 2 then

	elseif Phase == 3 then
		for _, track in ipairs(TRACKS) do
			Track.process(track, 6)
		end

		for _, lever in ipairs(LEVERS) do
			Lever.process(lever, 6)
		end
	elseif Phase == 4 then
		-- N-TRACS 宗弥急行シリーズではここでATC信号を作成
	elseif Phase == 5 then
		-- N-TRACS 宗弥急行シリーズではここで追加情報を作成
	elseif Phase == 0 then
		-- N-TRACS 宗弥急行シリーズではここで全ての情報を送信
	end
end
