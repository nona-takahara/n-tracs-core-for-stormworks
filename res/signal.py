import os
import tomllib

os.chdir(os.path.dirname(__file__))

with open("signal.toml", "rb") as f:
    data = tomllib.load(f)
    for k, v in data.items():
        print(k, v)
