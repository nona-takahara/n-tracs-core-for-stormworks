const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
require('dotenv').config();

process.chdir(__dirname);

if (fs.statSync("res/area_track.json").mtime > fs.statSync("res/area_track.lua").mtime) {
    console.log(execSync("python res/area_track.py").toString());
}

if (fs.statSync("res/signal.toml").mtime > fs.statSync("res/signal.lua").mtime) {
    console.log(execSync("python res/signal.py").toString());
}

console.log(execSync("npx storm-lua-minify script.lua").toString());
if (!fs.existsSync("dist")) {
    fs.mkdirSync("dist");
}

fs.copyFileSync("script.lua.map", "dist/script.lua.map");
fs.copyFileSync("script.min.lua", "dist/script.min.lua");

if(process.env.NTRACS_SW_DIR) {
    fs.copyFileSync("script.min.lua", path.join(process.env.NTRACS_SW_DIR, "script.lua"));
}

fs.rmSync("script.lua.map");
fs.rmSync("script.min.lua");

console.log("Copied! "+ (new Date().toLocaleTimeString()));
