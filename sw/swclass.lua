-- Stormworks Classes

---@class SWServer
---@field setGameSetting fun(gameSetting: SWGameSetting, value)
---@field getStartTile fun():SWTileData
---@field getWeather fun(transform_matrix: SWMatrix):SWWather
---@field setWeather fun(fog: number, rain: number, wind: number)
---@field getPlayers fun(): table<number, SWPlayer>
---@field removeMapID fun(peer_id: number, ui_id: number)
---@field getVehiclePos fun(vehicle_id: number): SWMatrix, boolean
---@field getVehiclePos fun(vehicle_id: number, voxel_x: number, voxel_y: number, voxel_z: number): SWMatrix, boolean
---@field getVehicleDial fun(vehicle_id: number, dial_name: string): SWVehicleDialData
---@field setVehicleKeypad fun(vehicle_id: number, keypad_name: string, value: number)
---@field setVehicleKeypad fun(vehicle_id: number, keypad_name: string, value: number, value2: number)
---@field setVehicleBattery fun(vehicle_id: number, battery_name: string, amount: number)
---@field getVehicleComponents fun(vehicle_id: number): SWLoadedVehicleData
server = {}

---@class SWMatrix
---@field translation fun(x: number, y: number, z: number):SWMatrix
---@field position fun(matrix1: SWMatrix): number, number, number
matrix = {}

---@class SWTileData
---@field name string
---@field x number
---@field y number
---@field z number

---@class SWWather
---@field fog number 0-1
---@field rain number 0-1
---@field snow number 0-1
---@field wind number 0-1
---@field temp number 0-1

---@class SWPlayer
---@field id number
---@field name string
---@field admin boolean
---@field auth boolean
---@field steam_id string stringじゃないかも
---@field object_id number

---@class SWUser
---@field name string
---@field steam_id string

---@class SWVehicleData
---@field tags_full string
---@field tags string[]
---@field group_id number
---@field transform SWMatrix
---@field simulating boolean
---@field editable boolean
---@field invulnerable boolean
---@field static boolean
---@field name string
---@field authors SWUser

---@class SWLoadedVehicleData
---@field voxels number
---@field mass number
---@field characters number[]
---@field components SWLoadedVehicleComponetData

---@class SWLoadedVehicleComponetData
---@field signs SWVehicleSignData[]
---@field buttons SWVehicleButtonData[]
---@field dials SWVehicleDialData[]

---@class SWVehicleComponetData
---@field name string
---@field pos Vector3d

---@class SWVehicleSignData: SWVehicleComponetData

---@class SWVehicleButtonData: SWVehicleComponetData
---@field on boolean

---@class SWVehicleDialData: SWVehicleComponetData
---@field value number
---@field value2 number


---@alias SWGameSetting
---| "third_person"
---| "third_person_vehicle"
---| "vehicle_damage"
---| "player_damage"
---| "npc_damage"
---| "sharks"
---| "fast_travel"
---| "teleport_vehicle"
---| "rogue_mode"
---| "auto_refuel"
---| "megalodon"
---| "map_show_players"
---| "map_show_vehicles"
---| "show_3d_waypoints"
---| "show_name_plates"
---| "day_length"
---| "infinite_money"
---| "settings_menu"
---| "unlock_all_islands"
---| "infinite_batteries"
---| "infinite_fuel"
---| "engine_overheating"
---| "no_clip"
---| "map_teleport"
---| "cleanup_vehicle"
---| "clear_fow"
---| "vehicle_spawning"
---| "photo_mode"
---| "respawning"
---| "settings_menu_lock"
---| "despawn_on_leave"
---| "unlock_all_components"
---| "override_weather"
