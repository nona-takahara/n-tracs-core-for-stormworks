const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const toml = require("toml");
const generateAreaTrack = require("./build/generate_area_track");
const generateSignal = require("./build/generate_signal");
require('dotenv').config();

process.chdir(__dirname);

async function main() {
    await Promise.all([
        generateIfStale("res/area_track.lua", "res/area_track.json", "utf8", (val) => generateAreaTrack(JSON.parse(val))),
        generateIfStale("res/signal.lua", "res/signal.toml", "utf8", (val) => generateSignal(toml.parse(val)))
    ]);

    console.log(execSync("npx storm-lua-minify -m script.lua").toString());
    await fs.promises.mkdir("dist", { recursive: true });

    const copyTasks = [
        fs.promises.copyFile("script.lua.map", "dist/script.lua.map"),
        fs.promises.copyFile("script.min.lua", "dist/script.min.lua")
    ];
    if (process.env.NTRACS_SW_DIR) {
        copyTasks.push(fs.promises.copyFile("script.min.lua", path.join(process.env.NTRACS_SW_DIR, "script.lua")));
    }
    await Promise.all(copyTasks);

    await Promise.all([
        fs.promises.rm("script.lua.map"),
        fs.promises.rm("script.min.lua")
    ]);

    console.log("Copied! " + (new Date().toLocaleTimeString()));
}

async function generateIfStale(dstPath, srcPath, readOption, thenBuild) {
    if (!fs.existsSync(dstPath) || fs.statSync(srcPath).mtime > fs.statSync(dstPath).mtime) {
        const val = await fs.promises.readFile(srcPath, readOption);
        const out = await thenBuild(val);
        await fs.promises.writeFile(dstPath, out);
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
