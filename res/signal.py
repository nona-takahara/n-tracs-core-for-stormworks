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
    switchesMake=[]
    for v in data["switches"]:
        switchesMake.append(f'SwitchRoute.new(SwitchGetter("{v["sw"]}"),TargetRoute.{v["t"].capitalize()})')
    
    routeLockMake=[]
    for v in data["route_lock"]:
        routeLockMake.append(f'TrackGetter("{v}")')

    overrunLockMake=[]
    for v in data["overrun_lock"]:
        overrunLockMake.append(f'TrackGetter("{v}")')

    signalTrackMake=[]
    for v in data["signal_track"]:
        signalTrackMake.append(f'TrackGetter("{v}")')

    approachTrackMake=[]
    for v in data["approach_track"]:
        approachTrackMake.append(f'TrackGetter("{v}")')

    rets = 'Lever.overWrite(' + \
        f'LeverGetter("{name}"),' +\
        f'"{name}",' +\
        f'TrackGetter("{data["start"]}"),' + \
        f'TrackGetter("{data["destination"]}"),' + \
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

    return rets

def auto_lever_lua_code(name, data):
    signalTrackMake=[]
    for v in data["signal_track"]:
        signalTrackMake.append(f'TrackGetter("{v}")')

    rets = 'AutoSignal.overWrite(' +\
    f'LeverGetter("{name}"),' +\
        f'"{name}",' +\
        '{' + ','.join(signalTrackMake) + '},' +\
        f'RouteDirection.{data["direction"].capitalize()},' +\
        f'{data["update_callback"]}' +\
    ')'
    return rets

with (open("signal.toml", "rb") as toml_f, open("signal.lua", "w") as lua_f):
    data = tomllib.load(toml_f)
    for k, v in data.items():
        print(lever_lua_code(k, v), file = lua_f)
