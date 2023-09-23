-- N-TRACS 宗弥急行 Wayside Signal

-- 1. Load N-TRACS Core
require("src.n_tracs_core")

-- 2. Load bridge
require("src.n_tracs_soyabridge")

require("src.utils.debug_http")

-- 3. Load settings
require("res.utils")
require("res.area_track")
require("res.signal")

DEFAULT_AREA = AreaGetter("2")

CreateSwitch("NHB21", { "NHB21" }, { TrackGetter("NHB21T") })
CreateSwitch("NHB22", { "NHB22a", "NHB22b" }, { TrackGetter("NHB21T"), TrackGetter("NHB22T") })
--CreateSwitch("NHB31", { "NHB31" }, { TrackGetter("NHB22T") }, true)

CreateSwitch("WAK11", { "WAK11" }, { TrackGetter("WAK1RBT"), TrackGetter("WAK11T") })
CreateSwitch("WAK12", { "WAK12" }, { TrackGetter("WAK12T") })

CreateSwitch("SGN11", { "SGN11" }, { TrackGetter("SGN1RBT"), TrackGetter("SGN11T") })
CreateSwitch("SGN12", { "SGN12" }, { TrackGetter("SGN12T") })

CreateSwitch("SNH21", { "SNH21a", "SNH21b" }, { TrackGetter("SNH21AT"), TrackGetter("SNH21BT") })
CreateSwitch("SNH22", { "SNH22" }, { TrackGetter("SNH22T") })

---@type PointSetter[]
POINTLIST = {}
for _, data in pairs(BRIDGE_SWITCH) do
	for key, _ in pairs(data.pointAndRoute) do
		POINTLIST[key] = SwitchBridge.getPointSetter(data, key)
	end
end

---[Stormworks] onTick function.
-- 1 Tickごとに呼び出されます.
---@diagnostic disable-next-line: lowercase-global
function onTick()
	TickCounter = (TickCounter or 0) + 1

	-- 毎Tick実行
	for vehicle_id, _ in pairs(VehicleTable) do
		server.setVehicleBattery(vehicle_id, "signal_bat", 3)
		server.setVehicleBattery(vehicle_id, "cheat_battery", 1)
	end

	Phase = ((Phase or 0) + 1) % 6
	if Phase == 1 then
		-- データの初期化及びビークルデータの取得フェーズ
		for _, area in pairs(AREAS) do
			Area.initializeForProcess(area)
		end

		for vehicle_id, data in pairs(VehicleTable) do
			if data.axles then
				for _, axle in ipairs(data.axles) do
					Axle.initializeForProcess(axle)
				end
			end

			if data.bridges then
				for _, setter in ipairs(data.bridges.points) do
					local dial, ss = server.getVehicleDial(vehicle_id, setter.pointName .. "K")
					if ss then
						setter.set(dial.value)
					end
				end
			end
		end
	elseif Phase == 2 then
		-- 取得データをCoreに処理させるのに適した状態に変換するフェーズ
		--debuglog("Before AXLE")
		for _, data in pairs(VehicleTable) do
			if data.axles then
				for _, axle in ipairs(data.axles) do
					Axle.search(axle)
				end
			end
		end
		--debuglog("Before BRIDGE TRACK")
		for _, data in pairs(BRIDGE_TRACK) do
			Track.beforeProcess(TRACKS[data.itemName], TrackBridge.isInAxle(data))
		end
		--debuglog("Before BRIDGE SWITCH")
		-- 方向てこなどの処理が必要な場合はここまでの段階でBRIDGE_SWITCHに入れておく
		for _, data in pairs(BRIDGE_SWITCH) do
			Switch.beforeProcess(SWITCHES[data.itemName], SwitchBridge.getState(data))
		end

		for _, data in pairs(LEVERS) do
			SignalBase.beforeProcess(data)
		end
	elseif Phase == 3 then
		-- Coreで処理するフェーズ
		for _, track in pairs(TRACKS) do
			Track.process(track, 6)
		end

		for _, lever in pairs(LEVERS) do
			SignalBase.process(lever, 6)
		end
	elseif Phase == 4 then
		-- Coreで処理したデータを配信用に加工するフェーズ その1
		for _, area in pairs(AREAS) do
			area.cbdata = area.updateCallback(area, 6)
		end
	elseif Phase == 5 then
		-- Coreで処理したデータを配信用に加工するフェーズ その2
	elseif Phase == 0 then
		-- 全ての情報を配信するフェーズ
		SendingSign = (SendingSign or -1) * -1
		for vehicle_id, data in pairs(VehicleTable) do
			if data.axles then
				for _, axle in ipairs(data.axles) do
					Axle.send(axle)
				end
			end

			if data.bridges then
				SendBridge(vehicle_id, data.bridges)
			end
		end

		while #DELAY_ANNOUNE > 0 do
			local calls = table.remove(DELAY_ANNOUNE, 1)
			if type(calls) == "function" then calls() end
		end
	end
end
