import os
import tomllib

os.chdir(os.path.dirname(__file__))

def lever_lua_code(name, data):
    return ""

with (open("signal.toml", "rb") as toml_f, open("signal.lua", "w") as lua_f):
    data = tomllib.load(toml_f)
    for k, v in data.items():
        print(lever_lua_code(k, v), file = lua_f)
