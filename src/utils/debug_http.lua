-- Author: <Authorname> (Please change this in user settings, Ctrl+Comma)
-- GitHub: <GithubLink>
-- Workshop: <WorkshopLink>
--
--- Developed using LifeBoatAPI - Stormworks Lua plugin for VSCode - https://code.visualstudio.com/download (search "Stormworks Lua with LifeboatAPI" extension)
--- If you have any issues, please report them here: https://github.com/nameouschangey/STORMWORKS_VSCodeExtension/issues - by Nameous Changey

__DEBUGLOGS = __DEBUGLOGS or {}
__HTTPCALL = false

function debuglog(str)
    table.insert(__DEBUGLOGS, "LOG|" .. tostring(str))
    server.announce("[DEBUG]", tostring(str))
    if not __HTTPCALL then SendLogHttp() end
end

function error(str)
    table.insert(__DEBUGLOGS, "ERR|" .. tostring(str))
    if not __HTTPCALL then SendLogHttp() end
end

function SendLogHttp()
    __HTTPCALL = true
    local counter = 0
    local req = ""
    for index, value in ipairs(__DEBUGLOGS) do
        req = req .. "&m"..tostring(index).."="..urlencode(value)
        counter = index
    end
    __DEBUGLOGS = {}
    server.httpGet(3000, "/luaapi?l="..tostring(counter)..req)
end

function httpReply(port, request, reply)
    __HTTPCALL = false
end

function char_to_hex(c)
    return string.format("%%%02X", string.byte(c))
end

function urlencode(url)
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w ])", char_to_hex)
    url = url:gsub(" ", "+")
    return url
end

-- ref: https://gist.github.com/ignisdesign/4323051
-- ref: http://stackoverflow.com/questions/20282054/how-to-urldecode-a-request-uri-string-in-lua
-- to encode table as parameters, see https://github.com/stuartpb/tvtropes-lua/blob/master/urlencode.lua