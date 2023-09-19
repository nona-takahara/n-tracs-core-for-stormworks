---@class Command
---@field admin boolean
---@field auth boolean
---@field description string
---@field command function

---@type table<string,Command>
COMMANDS = {}

COMMANDS["help"] = {
    admin = false,
    auth = false,
    description = "Get help for usage of N-TRACS Soya Express Wayside Signals",
    command = (function(_, is_admin, is_auth, peer_id)
        for key, cmd in pairs(COMMANDS) do
            if (not cmd.admin or (cmd.admin and is_admin)) and (not cmd.auth or (cmd.auth and is_auth)) then
                Announce("?nt " .. key .. ": " .. cmd.description, peer_id)
            end
        end
    end)
}

function Announce(message, peer_id)
    server.announce("[Soya Express WS]", message, peer_id)
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
        end
    end

    if command == "?help" then
        Announce("For more help, use ?nt help", peer_id)
    end
end
