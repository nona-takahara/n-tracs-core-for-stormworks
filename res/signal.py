import os
import tomllib

os.chdir(os.path.dirname(__file__))


def lever_lua_code(name, data):
    try:
        if data["auto"] == True:
            return auto_lever_lua_code(name, data)
        return absolute_lever_lua_code(name, data)
    except:
        return absolute_lever_lua_code(name, data)


def absolute_lever_lua_code(name, data):
    switchesMake = []
    for v in data["switches"]:
        switchesMake.append(
            'sr("' + v["sw"] + '",SignalRoute.' + v["t"].capitalize()+')')

    routeLockMake = []
    for v in data["route_lock"]:
        routeLockMake.append(f'"{v}"')

    overrunLockMake = []
    for v in data["overrun_lock"]:
        overrunLockMake.append(f'"{v}"')

    signalTrackMake = []
    for v in data["signal_track"]:
        signalTrackMake.append(f'"{v}"')

    approachTrackMake = []
    for v in data["approach_track"]:
        approachTrackMake.append(f'"{v}"')

    rets = 'cs(s,' + \
        f'"{name}",' +\
        f'"{data["start"]}",' + \
        f'"{data["destination"]}",' + \
        '{' + f'{",".join(switchesMake)}' + '},' + \
        '{' + ','.join(routeLockMake) + '},' +\
        '{' + ','.join(overrunLockMake) + '},' +\
        '{' + ','.join(signalTrackMake) + '},' +\
        f'RouteDirection.{data["direction"].capitalize()},' +\
        '{' + ','.join(approachTrackMake) + '},' +\
        f'{data["approach_lock_time"]},' +\
        f'{data["overrun_lock_time"]},' +\
        f'{data["update_callback"]}' +\
        ')'
        #"function()end)"

    return rets


def auto_lever_lua_code(name, data):
    signalTrackMake = []
    for v in data["signal_track"]:
        signalTrackMake.append(f'"{v}"')

    rets = 'cas(s,' +\
        f'"{name}",' +\
        '{' + ','.join(signalTrackMake) + '},' +\
        f'RouteDirection.{data["direction"].capitalize()},' +\
        f'{data["update_callback"]}' +\
        ')'
    #    "function()end)"
    return rets


with (open("signal.toml", "rb") as toml_f, open("signal.lua", "w", encoding="utf-8") as lua_f):
    data = tomllib.load(toml_f)

    print('''local SignalRoute = require("src.n_tracs_core.switch.signal_route")
local SwitchRoute = require("src.n_tracs_core.signal.switch_route")
local RouteDirection = require("src.n_tracs_core.signal.route_direction")''', file=lua_f)
    print("---@param s SoyaBridge", file=lua_f)
    print("return function(s)", file=lua_f)
    print("local cas,cs,sr=s.create_auto_signal,s.create_signal,SwitchRoute.new", file=lua_f)

    for k, v in data.items():
        print(lever_lua_code(k, v), file=lua_f)

    print("end", file=lua_f)
