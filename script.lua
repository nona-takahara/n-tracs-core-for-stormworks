-- N-TRACS 宗弥急行 Wayside Signal

-- 1. Load N-TRACS Core
require("src.n_tracs_core")

-- 2. Load settings
require("res.area_track")
require("res.signal")

-- 3. Load bridge
require("src.n_tracs_soyabridge")

---[Stormworks] onTick function.
-- 1 Tickごとに呼び出されます.
function onTick()
	TickCounter = TickCounter + 1

	-- 毎Tick実行
	for vehicle_id, _ in pairs(VehicleTable) do
		server.setVehicleBattery(vehicle_id, "signal_bat", 3)
	end

	Phase = (Phase + 1) % 6
	if Phase == 1 then
		-- データの初期化及びビークルデータの取得フェーズ
		for _, area in ipairs(AREAS) do
			Area.initializeForProcess(area)
		end

		for _, data in pairs(VehicleTable) do
			if data.axles then
				for _, axle in ipairs(data.axles) do
					Axle.initializeForProcess(axle)
				end
			end
		end
	elseif Phase == 2 then
		-- 取得データをCoreに処理させるのに適した状態に変換するフェーズ

	elseif Phase == 3 then
		-- Coreで処理するフェーズ
		for _, track in ipairs(TRACKS) do
			Track.process(track, 6)
		end

		for _, lever in ipairs(LEVERS) do
			Lever.process(lever, 6)
		end
	elseif Phase == 4 then
		-- Coreで処理したデータを配信用に加工するフェーズ その1
	elseif Phase == 5 then
		-- Coreで処理したデータを配信用に加工するフェーズ その2
	elseif Phase == 0 then
		-- 全ての情報を配信するフェーズ
	end
end
