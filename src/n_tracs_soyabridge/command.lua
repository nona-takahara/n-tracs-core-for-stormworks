---@class Command
---@field admin boolean
---@field auth boolean
---@field description string
---@field command function

local json = require("src.utils.json")
local SetRoute = require("src.n_tracs_core.switch.set_route")

-- サーバーの応答に載って届いたコマンドの peer。結果はチャットに出さず、ログにだけ残す
local REMOTE_PEER = -2

---@param sw SoyaBridge
---@return {COMMANDS: table<string, Command>, DELAY_ANNOUNE: function[], Announce: fun(message: string, peer_id: integer), run_remote: fun(line: string)}
return function(sw)
    ---@type table<string,Command>
    local COMMANDS = {}

    local DELAY_ANNOUNE = {}
    local Announce

    COMMANDS["help"] = {
        admin = false,
        auth = false,
        description = "Get help for usage of " .. ADDON_NAME,
        command = (function(_, is_admin, is_auth, peer_id)
            for key, cmd in pairs(COMMANDS) do
                if (not cmd.admin or (cmd.admin and is_admin)) and (not cmd.auth or (cmd.auth and is_auth)) then
                    Announce("?nt " .. key .. ": " .. cmd.description, peer_id)
                end
            end
        end)
    }

    COMMANDS["version"] = {
        admin = false,
        auth = false,
        description = "Get version of " .. ADDON_SHORT_NAME,
        command = (function(_, is_admin, is_auth, peer_id)
            Announce(ADDON_NAME .. " " .. ADDON_VERSION, peer_id)
        end)
    }


    COMMANDS["aspect"] = {
        admin = false,
        auth = false,
        description = "Get aspect of signal",
        command = (function(args, is_admin, is_auth, peer_id)
            local nm = args[2]
            if sw.nt:get_signal_may_nil(nm) then
                table.insert(DELAY_ANNOUNE, function()
                    Announce("Singal \"" .. nm .. "\" aspect: " .. tostring(sw.nt:get_signal(nm).aspect), peer_id)
                end)
            else
                Announce("ERROR! " .. "Singal \"" .. nm .. "\" is not found", peer_id)
            end
        end)
    }

    COMMANDS["set"] = {
        admin = true,
        auth = false,
        description = "Set signal",
        command = (function(args, is_admin, is_auth, peer_id)
            local nm = args[2]
            if sw.nt:get_signal_may_nil(nm) then
                if type(sw.nt:get_signal(nm).setInput) == "function" then
                    ---@diagnostic disable-next-line: param-type-mismatch
                    sw.nt:get_signal(nm):setInput(true, sw.nt)
                    Announce("Singal \"" .. nm .. "\" has set", peer_id)
                else
                    Announce("WARNING " .. "Singal \"" .. nm .. "\" cannot set", peer_id)
                end
            else
                Announce("ERROR! " .. "Singal \"" .. nm .. "\" is not found", peer_id)
            end
        end)
    }

    COMMANDS["reset"] = {
        admin = true,
        auth = false,
        description = "Reset signal",
        command = (function(args, is_admin, is_auth, peer_id)
            local nm = args[2]
            if sw.nt:get_signal_may_nil(nm) then
                if type(sw.nt:get_signal(nm).setInput) == "function" then
                    ---@diagnostic disable-next-line: param-type-mismatch
                    sw.nt:get_signal(nm):setInput(false, sw.nt)
                    Announce("Singal \"" .. nm .. "\" has reset", peer_id)
                else
                    Announce("WARNING " .. "Singal \"" .. nm .. "\" cannot reset", peer_id)
                end
            else
                Announce("ERROR! " .. "Singal \"" .. nm .. "\" is not found", peer_id)
            end
        end)
    }

    COMMANDS["switch"] = {
        admin = true,
        auth = false,
        description = "Request a switch position: switch <ID> normal|reverse",
        command = (function(args, is_admin, is_auth, peer_id)
            -- minify がフィールド名を書き換えるので、実行時の文字列で表を引かずに比べる
            local target = (args[3] == "normal" and SetRoute.Normal) or (args[3] == "reverse" and SetRoute.Reverse) or nil
            -- 方向てこの仮想転てつ機は対象にしない。方向てこ(set)で動かす
            if not sw.switch_bridge[args[2] or ""] then
                Announce("ERROR! Switch \"" .. tostring(args[2]) .. "\" is not found", peer_id)
            elseif not target then
                Announce("ERROR! usage: ?nt " .. COMMANDS["switch"].description, peer_id)
            else
                sw:request_switch(args[2], target)
                Announce("Switch \"" .. args[2] .. "\" requested " .. args[3], peer_id)
            end
        end)
    }

    COMMANDS["web"] = {
        admin = true,
        auth = false,
        description = "Web CTC: web on|off|port <number>|status",
        command = (function(args, is_admin, is_auth, peer_id)
            local web, g, op = sw.web, _ENV["g_savedata"], args[2]
            if not web then
                Announce("ERROR! Web CTC is not available", peer_id)
                return
            end
            if op == "on" or op == "off" then
                g.webCtc = op == "on"
                web:reset()
            elseif op == "port" then
                local p = tonumber(args[3] or "")
                if not p or p ~= math.floor(p) or p < 1 or p > 65535 then
                    Announce("ERROR! usage: ?nt web port <1-65535>", peer_id)
                    return
                end
                g.webCtcPort = math.floor(p)
                web:reset()
            elseif op ~= "status" then
                Announce("ERROR! usage: ?nt " .. COMMANDS["web"].description, peer_id)
                return
            end
            Announce(web:status(), peer_id)
        end)
    }

    COMMANDS["debug"] = {
        admin = true,
        auth = false,
        description = "Get " .. ADDON_SHORT_NAME .. " item information for debug",
        command = (function(args, is_admin, is_auth, peer_id)
            local nm = args[2]
            local tostr = (json and json.stringify) or tostring
            if sw.nt:get_signal_may_nil(nm) then
                table.insert(DELAY_ANNOUNE, function()
                    Announce("Singal \"" .. nm .. "\" aspect: " .. tostr(sw.nt:get_signal(nm)), peer_id)
                end)
            end
            if sw.nt:get_switch_may_nil(nm) then
                table.insert(DELAY_ANNOUNE, function()
                    Announce("Switch \"" .. nm .. "\" route: " .. tostr(sw.nt:get_switch(nm)),
                        peer_id)
                end)
            end
            if sw.nt:get_track_may_nil(nm) then
                table.insert(DELAY_ANNOUNE, function()
                    Announce("Track \"" .. nm .. "\" route: " .. tostr(sw.nt:get_track(nm)),
                        peer_id)
                end)
            end
        end)
    }

    COMMANDS["arc"] = {
        admin = true,
        auth = false,
        description = "ARC: arc <station> start|stop|list | arc <station> promote|restore|remove <train> | arc release <reservation>",
        command = (function(args, is_admin, is_auth, peer_id)
            local arc = sw.arc
            if not arc then
                Announce("ERROR! ARC is not configured", peer_id)
                return
            end
            if args[2] == "release" then
                if arc.reservations[args[3]] then
                    arc:release(args[3])
                    Announce("ARC reservation \"" .. args[3] .. "\" released", peer_id)
                else
                    Announce("ERROR! reservation \"" .. tostring(args[3]) .. "\" is not found", peer_id)
                end
                return
            end
            local st = arc:get_station(args[2])
            if not st then
                Announce("ERROR! ARC station \"" .. tostring(args[2]) .. "\" is not found", peer_id)
                return
            end
            local op, key = args[3], tonumber(args[4]) or args[4]
            if op == "start" or op == "stop" then
                arc:set_running(args[2], op == "start")
                Announce("ARC " .. args[2] .. " " .. (op == "start" and "running" or "stopped"), peer_id)
            elseif op == "list" then
                table.insert(DELAY_ANNOUNE, function()
                    local lines = {}
                    for rkey, req in pairs(st.requests) do
                        table.insert(lines, rkey .. ":" .. req.seq.id .. "#" .. req.idx ..
                            (req.adopted and ("/" .. req.adopted) or "") .. (req.excluded and "/excluded" or ""))
                    end
                    table.sort(lines)
                    Announce(args[2] .. (st.running and "" or " (stopped)") .. " requests: " .. table.concat(lines, ", "), peer_id)
                    for _, a in ipairs(st.alerts) do
                        Announce("WARNING! deadlock " .. args[2] .. ": " .. a, peer_id)
                    end
                    for _, a in ipairs(st.stalled) do
                        Announce("WARNING! not locked " .. args[2] .. ": " .. a, peer_id)
                    end
                end)
            elseif (op == "promote" or op == "restore" or op == "remove") and key then
                local ok = arc[op](arc, args[2], key)
                Announce("ARC " .. args[2] .. " " .. op .. " " .. key .. (ok and ": done" or ": request not found"), peer_id)
            else
                Announce("ERROR! usage: " .. COMMANDS["arc"].description, peer_id)
            end
        end)
    }

    COMMANDS["ctc"] = {
        admin = false,
        auth = false,
        description = "Get version of CTC " .. ADDON_SHORT_NAME,
        command = (function(_, is_admin, is_auth, peer_id)
            Announce(ADDON_NAME .. " CTC " .. CTC_VERSION, peer_id)
        end)
    }

    COMMANDS["register"] = {
        admin = false,
        auth = true,
        description = "Manually register the vehicle you are sitting in in " .. ADDON_SHORT_NAME,
        command = (function(_, is_admin, is_auth, peer_id)
            local object_id, is_success = server.getPlayerCharacterID(peer_id)
            if is_success then
                local vehicle_id = server.getCharacterVehicle(object_id)
                sw:load_vehicle(vehicle_id)
                Announce("Your train is registered", peer_id)
                -- 登録のついでに、車軸(TRAINで始まる名前のペインタブル)の現在の座標を出す。エリアの位置と見比べるため
                local info = sw.vehicle_table[vehicle_id]
                if info and #info.axles > 0 then
                    for _, axle in ipairs(info.axles) do
                        Announce(string.format("axle %s pos(%.1f, %.1f, %.1f)", tostring(axle.itemName),
                            axle.real_pos.x, axle.real_pos.y, axle.real_pos.z), peer_id)
                    end
                else
                    Announce("no axle (paintable sign/indicator named TRAIN*) found in this vehicle", peer_id)
                end
            else
                Announce("ERROR! Something went wrong and it's not completed", peer_id)
            end
        end)
    }

    COMMANDS["unregister"] = {
        admin = true,
        auth = false,
        description = "Manually remove the vehicle you are sitting in from the system (DANGEROUS!)",
        command = (function(_, is_admin, is_auth, peer_id)
            local object_id, is_success = server.getPlayerCharacterID(peer_id)
            if is_admin and is_success then
                sw:despawn_vehicle(server.getCharacterVehicle(object_id))
                Announce("Your train is deleted", peer_id)
            else
                Announce("ERROR! Something went wrong and it's not completed", peer_id)
            end
        end)
    }

    COMMANDS["enable_cheat_battery"] = {
        admin = true,
        auth = false,
        description = "Enable constant full charge to cheat_battery",
        command = (function(_, is_admin, is_auth, peer_id)
            _ENV["g_savedata"].cheatBattery = true
            Announce("cheat_battery by " .. ADDON_SHORT_NAME .. " is enabled", peer_id)
        end)
    }

    COMMANDS["disable_cheat_battery"] = {
        admin = true,
        auth = false,
        description = "Disable constant full charge to cheat_battery",
        command = (function(_, is_admin, is_auth, peer_id)
            _ENV["g_savedata"].cheatBattery = false
            Announce("cheat_battery by " .. ADDON_SHORT_NAME .. " is disabled", peer_id)
        end)
    }

    COMMANDS["remap_markers"] = {
        admin = false,
        auth = false,
        description = "Redraw map markers",
        command = (function(_, is_admin, is_auth, peer_id)
            local playerlist = server.getPlayers()
            local ui_id = _ENV["g_savedata"].ui_id
            if ui_id then
                for _, v in pairs(playerlist) do
                    server.removeMapID(v.id, ui_id)
                end
            end
            _ENV["g_savedata"].ui_id = nil
            for _, v in pairs(playerlist) do
                AddMapLabels(v.id)
            end
        end)
    }

    Announce = function(message, peer_id)
        if peer_id ~= REMOTE_PEER then
            server.announce("[" .. ADDON_SHORT_NAME .. "]", message, peer_id)
        end
        dlog("[" .. ADDON_SHORT_NAME .. "]:" .. message)
    end

    ---サーバーの応答に載って届いたコマンドを、管理者として実行します。誰に許すかはサーバーが判定します
    ---web は実行しません。サーバーが自分で送信を止めたり、ポートを変えたりできないようにするためです
    ---@param line string
    local function run_remote(line)
        local args = {}
        for a in line:gmatch("%S+") do args[#args + 1] = a end
        local cmd = COMMANDS[args[1] or ""]
        if args[1] == "web" or not cmd then
            dlog("[" .. ADDON_SHORT_NAME .. "]:Web CTC: skipped \"" .. line .. "\"")
            return
        end
        cmd.command(args, true, true, REMOTE_PEER)
    end

    return {
        COMMANDS = COMMANDS,
        DELAY_ANNOUNE = DELAY_ANNOUNE,
        Announce = Announce,
        run_remote = run_remote
    }
end
