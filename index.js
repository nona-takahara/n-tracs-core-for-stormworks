const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const toml = require("toml");
const generateAreaTrack = require("./build/generate_area_track");
const generateSignal = require("./build/generate_signal");
require('dotenv').config();

process.chdir(__dirname);

async function main() {
    await generateIfStale("res/area_track.lua", "res/area_track.json", "utf8", (val) => generateAreaTrack(JSON.parse(val)));
    await generateIfStale("res/signal.lua", "res/signal.toml", "utf8", (val) => generateSignal(toml.parse(val)));

    console.log(execSync("npx storm-lua-minify -m script.lua").toString());
    if (!fs.existsSync("dist")) {
        fs.mkdirSync("dist");
    }

    fs.copyFileSync("script.lua.map", "dist/script.lua.map");
    fs.copyFileSync("script.min.lua", "dist/script.min.lua");

    if (process.env.NTRACS_SW_DIR) {
        fs.copyFileSync("script.min.lua", path.join(process.env.NTRACS_SW_DIR, "script.lua"));
    }

    fs.rmSync("script.lua.map");
    fs.rmSync("script.min.lua");

    console.log("Copied! " + (new Date().toLocaleTimeString()));
}

async function generateIfStale(dstPath, srcPath, readOption, thenBuild) {
    if (!fs.existsSync(dstPath) || fs.statSync(srcPath).mtime > fs.statSync(dstPath).mtime) {
        await fs.promises.readFile(srcPath, readOption)
            .then(thenBuild)
            .then((out) => fs.promises.writeFile(dstPath, out));
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
