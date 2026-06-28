const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const toml = require("toml");
const generateAreaTrack = require("./build/generate_area_track");
const { generateSignal, buildControlsMap, detectControlsCycle } = require("./build/generate_signal");
require('dotenv').config();

process.chdir(__dirname);

function isLua53Available() {
    try {
        execSync("lua53 -v", { stdio: "pipe" });
        return true;
    } catch {
        return false;
    }
}

function checkLuaSyntax(filePath) {
    try {
        execSync(`lua53 -e "assert(loadfile('${filePath}'))"`, { stdio: "pipe" });
    } catch (e) {
        throw new Error(`Lua syntax error in ${filePath}:\n${e.stderr.toString()}`);
    }
}

function checkCrossReferences(signalObj, areaTrackObj) {
    const registeredTracks = new Set(areaTrackObj.tracks.map(t => t.name));
    const errors = [];

    Object.entries(signalObj).forEach(([signalName, data]) => {
        const refs = [];

        if (data.auto !== true) {
            refs.push({ id: data.start,       field: "start" });
            refs.push({ id: data.destination, field: "destination" });
            (data.approach_track || []).forEach(id => refs.push({ id, field: "approach_track" }));
            (data.route_lock     || []).forEach(id => refs.push({ id, field: "route_lock" }));
            (data.overrun_lock   || []).forEach(id => refs.push({ id, field: "overrun_lock" }));
        }
        (data.signal_track || []).forEach(id => refs.push({ id, field: "signal_track" }));

        refs.forEach(({ id, field }) => {
            if (id && !registeredTracks.has(id)) {
                errors.push(`[${signalName}] ${field}: track '${id}' not in area_track.json`);
            }
        });
    });

    if (errors.length > 0) {
        console.error("Cross-reference check failed:\n" + errors.join("\n"));
    } else {
        console.log("Cross-reference check: OK");
    }
}

async function main() {
    const [signalSrc, areaTrackSrc] = await Promise.all([
        fs.promises.readFile("res/signal.toml",     "utf8"),
        fs.promises.readFile("res/area_track.json", "utf8"),
    ]);
    const signalObj = toml.parse(signalSrc);
    checkCrossReferences(signalObj, JSON.parse(areaTrackSrc));

    if (isStale("res/signal.lua", "res/signal.toml")) {
        detectControlsCycle(buildControlsMap(signalObj));
        console.log("Controls cycle check: OK");
    }

    await Promise.all([
        generateIfStale("res/area_track.lua", "res/area_track.json", "utf8", (val) => generateAreaTrack(JSON.parse(val))),
        generateIfStale("res/signal.lua", "res/signal.toml", "utf8", (val) => generateSignal(toml.parse(val)))
    ]);

    if (isLua53Available()) {
        checkLuaSyntax("res/area_track.lua");
        checkLuaSyntax("res/signal.lua");
        console.log("Lua syntax check: OK");
    } else {
        console.warn("lua53 not found — Lua syntax check skipped");
    }

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

function isStale(dstPath, srcPath) {
    return !fs.existsSync(dstPath) || fs.statSync(srcPath).mtime > fs.statSync(dstPath).mtime;
}

async function generateIfStale(dstPath, srcPath, readOption, thenBuild) {
    if (isStale(dstPath, srcPath)) {
        const val = await fs.promises.readFile(srcPath, readOption);
        const out = await thenBuild(val);
        await fs.promises.writeFile(dstPath, out);
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
