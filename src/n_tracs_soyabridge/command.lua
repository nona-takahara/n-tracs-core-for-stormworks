---@class Command
---@field admin boolean
---@field auth boolean
---@field description string
---@field command function

---@type table<string,Command>
COMMANDS = {}

DELAY_ANNOUNE = {}

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
        if LEVERS[nm] then
            table.insert(DELAY_ANNOUNE, function()
                Announce("Singal \"" .. nm .. "\" aspect: " .. tostring(LEVERS[nm].aspect), peer_id)
            end)
        else
            Announce("Singal \"" .. nm .. "\" is not found", peer_id)
        end
    end)
}

COMMANDS["set"] = {
    admin = true,
    auth = false,
    description = "Set signal",
    command = (function(args, is_admin, is_auth, peer_id)
        local nm = args[2]
        if LEVERS[nm] then
            if LEVERS[nm].name == "Lever" then
                ---@diagnostic disable-next-line: param-type-mismatch
                Lever.setInput(LEVERS[nm], true, not (nm == "WAK1R" or nm == "WAK4L" or nm == "SGN1R" or nm == "SGN4L"))
                Announce("Singal \"" .. nm .. "\" has set", peer_id)
            else
                Announce("Singal \"" .. nm .. "\" cannot set", peer_id)
            end
        else
            Announce("Singal \"" .. nm .. "\" is not found", peer_id)
        end
    end)
}

COMMANDS["reset"] = {
    admin = true,
    auth = false,
    description = "Reset signal",
    command = (function(args, is_admin, is_auth, peer_id)
        local nm = args[2]
        if LEVERS[nm] then
            if LEVERS[nm].name == "Lever" then
                ---@diagnostic disable-next-line: param-type-mismatch
                Lever.setInput(LEVERS[nm], false, false)
                Announce("Singal \"" .. nm .. "\" has reset", peer_id)
            else
                Announce("Singal \"" .. nm .. "\" cannot reset", peer_id)
            end
        else
            Announce("Singal \"" .. nm .. "\" is not found", peer_id)
        end
    end)
}

COMMANDS["debug"] = {
    admin = true,
    auth = false,
    description = "Get " .. ADDON_SHORT_NAME .. " item information for debug",
    command = (function(args, is_admin, is_auth, peer_id)
        local nm = args[2]
        if LEVERS[nm] then
            table.insert(DELAY_ANNOUNE, function()
                Announce("Singal \"" .. nm .. "\" aspect: " .. tostring(LEVERS[nm].aspect), peer_id)
            end)
        end
        if SWITCHES[nm] then
            table.insert(DELAY_ANNOUNE, function()
                Announce("Switch \"" .. nm .. "\" route: " .. tostring(Switch.getRealRoute(SWITCHES[nm])), peer_id)
            end)
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
            onVehicleLoad(server.getCharacterVehicle(object_id))
            Announce("Your train is registered", peer_id)
        else
            Announce("Something went wrong and it's not completed", peer_id)
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
            onVehicleDespawn(server.getCharacterVehicle(object_id))
            Announce("Your train is deleted", peer_id)
        else
            Announce("Something went wrong and it's not completed", peer_id)
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


function Announce(message, peer_id)
    server.announce("[" .. ADDON_SHORT_NAME .. "]", message, peer_id)
end

---@diagnostic disable-next-line: lowercase-global
function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, ...)
    if command == "?ntracs" or command == "?nt" then
        local args = { ... }
        if COMMANDS[args[1]] then
            local cmd = COMMANDS[args[1]]
            if (not cmd.admin or (cmd.admin and is_admin)) and (not cmd.auth or (cmd.auth and is_auth)) then
                cmd.command(args, is_admin, is_auth, peer_id)
            end
        else
            Announce(ADDON_SHORT_NAME .. " command '" .. tostring(args[1]) .. "' is not found", peer_id)
        end
    end

    if command == "?help" then
        Announce("For more help, use ?nt help", peer_id)
    end
end
