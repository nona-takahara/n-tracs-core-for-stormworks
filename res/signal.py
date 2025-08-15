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
            '{switch="' + v["sw"] + '",target=SignalRoute.' + v["t"].capitalize()+'}')

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

    rets = 'sw:create_signal(' + \
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
        "function()end)"
    # f'{data["update_callback"]}' +\
    # ')'

    return rets


def auto_lever_lua_code(name, data):
    signalTrackMake = []
    for v in data["signal_track"]:
        signalTrackMake.append(f'"{v}"')

    rets = 'sw:create_auto_signal(' +\
        f'"{name}",' +\
        '{' + ','.join(signalTrackMake) + '},' +\
        f'RouteDirection.{data["direction"].capitalize()},' +\
        "function()end)"
    # f'{data["update_callback"]}' +\
    # ')'
    return rets


with (open("signal.toml", "rb") as toml_f, open("signal.lua", "w", encoding="utf-8") as lua_f):
    data = tomllib.load(toml_f)

    print('''local SignalRoute = require("src.n_tracs_core.switch.signal_route")
local RouteDirection = require("src.n_tracs_core.signal.route_direction")''', file=lua_f)
    print("---@param sw SoyaBridge", file=lua_f)
    print("return function(sw)", file=lua_f)

    for k, v in data.items():
        print(lever_lua_code(k, v), file=lua_f)

    print("end", file=lua_f)
