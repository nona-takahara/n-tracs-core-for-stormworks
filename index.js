const { execSync, spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const toml = require("toml");
const generateAreaTrack = require("./build/generate_area_track");
const { generateSignal, buildControlsMap, detectControlsCycle } = require("./build/generate_signal");
const { checkRouteTrackContinuity } = require("./build/check_route_continuity");
const { checkInlineTableDuplicateKeys, checkSwitchReferences } = require("./build/check_switch_config");
require('dotenv').config();

process.chdir(__dirname);

function findLua() {
    for (const cmd of ["lua53", "lua5.3", "lua"]) {
        try {
            if (/Lua 5\.3/.test(execSync(`${cmd} -v`, { stdio: "pipe" }).toString())) return cmd;
        } catch { /* 次の候補へ */ }
    }
    return null;
}

function checkLuaSyntax(filePath, lua) {
    try {
        execSync(`${lua} -e "assert(loadfile('${filePath}'))"`, { stdio: "pipe" });
    } catch (e) {
        throw new Error(`Lua syntax error in ${filePath}:\n${e.stderr.toString()}`);
    }
}

// ARC設定の誤りはビルド時にここで検出する(Stormworksの実行時には検査しない)
function checkArcConfig() {
    const lua = findLua();
    if (!lua) {
        console.warn("Lua 5.3 not found — ARC config check skipped");
        return;
    }
    const proc = spawnSync(lua, ["build/check_arc.lua"], { encoding: "utf8" });
    if (proc.status !== 0) {
        throw new Error("ARC config check failed:\n" + proc.stderr);
    }
    console.log("ARC config check: OK");
}

// script.lua の ADDON_VERSION と storm-lua-minify のバージョンを、保存されるコメントとして
// res/build_info.lua に書く。script.lua の先頭の dofile で展開され、minify 後の先頭に残る
// (行番号対応を崩さないよう、minify 後のコードには直接書き込まない)。
function generateBuildInfo() {
    const scriptSrc = fs.readFileSync("script.lua", "utf8");
    const match = scriptSrc.match(/^ADDON_VERSION\s*=\s*"([^"]+)"/m);
    if (!match) {
        throw new Error("script.lua から ADDON_VERSION を読み取れません");
    }
    const minifyVersion = require("storm-lua-minify/package.json").version;
    // 先頭の --# が、minify に削除されないコメントの印
    const text = `--# N-TRACS ${match[1]} / storm-lua-minify ${minifyVersion}\n`;
    if (!fs.existsSync("res/build_info.lua") || fs.readFileSync("res/build_info.lua", "utf8") !== text) {
        fs.writeFileSync("res/build_info.lua", text);
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

function detectOpeningLeverConflicts(signalObj) {
    const owner = {};
    const errors = [];
    Object.entries(signalObj).forEach(([name, data]) => {
        if (data.opening_lever !== true) return;
        (data.overrun_lock || []).forEach((track) => {
            if (owner[track]) {
                errors.push(`開通てこの対象区間が重複しています: '${track}' は '${owner[track]}' と '${name}' の両方に指定されています`);
            } else {
                owner[track] = name;
            }
        });
    });
    if (errors.length > 0) {
        throw new Error(errors.join("\n"));
    }
}

async function main() {
    const [signalSrc, areaTrackSrc] = await Promise.all([
        fs.promises.readFile("res/signal.toml",     "utf8"),
        fs.promises.readFile("res/area_track.json", "utf8"),
    ]);
    const signalObj = toml.parse(signalSrc);
    const areaTrackObj = JSON.parse(areaTrackSrc);
    const switchSrc = await fs.promises.readFile("res/switch.lua", "utf8");
    const switchErrors = [
        ...checkInlineTableDuplicateKeys(signalSrc),
        ...checkSwitchReferences(signalObj, switchSrc, areaTrackObj),
    ];
    if (switchErrors.length > 0) {
        throw new Error("Switch config check failed:\n" + switchErrors.join("\n"));
    }
    console.log("Switch config check: OK");
    checkCrossReferences(signalObj, areaTrackObj);
    checkRouteTrackContinuity(signalObj, areaTrackObj);
    detectOpeningLeverConflicts(signalObj);

    if (isStale("res/signal.lua", "res/signal.toml")) {
        detectControlsCycle(buildControlsMap(signalObj));
        console.log("Controls cycle check: OK");
    }

    await Promise.all([
        generateIfStale("res/area_track.lua", "res/area_track.json", "utf8", (val) => generateAreaTrack(JSON.parse(val))),
        generateIfStale("res/signal.lua", "res/signal.toml", "utf8", (val) => generateSignal(toml.parse(val)))
    ]);

    checkArcConfig();

    const lua = findLua();
    if (lua) {
        checkLuaSyntax("res/area_track.lua", lua);
        checkLuaSyntax("res/signal.lua", lua);
        console.log("Lua syntax check: OK");
    } else {
        console.warn("Lua 5.3 not found — Lua syntax check skipped");
    }

    // 一時対処: unused-export-removal が、require 先モジュールの使われている export を誤って消すため切る
    console.log(execSync("npx storm-lua-minify -m --no-unused-export-removal script.lua").toString());
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
