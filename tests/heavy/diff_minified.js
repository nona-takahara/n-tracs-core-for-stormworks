// 2つの minify 結果を同じ場面で動かし、Stormworks へ出した呼び出しの記録が同じかを比べる。
// フィールド名の短縮など、名前を変える最適化が動作を変えていないかを確かめるための道具。
//
// 実行(リポジトリルートから):
//   pnpm test:minify-diff                                         基準と候補を自分でビルドして比べる(要: 先に pnpm build)
//   node tests/heavy/diff_minified.js <基準.min.lua> <候補.min.lua>   作ってある2つの出力を比べる
// 基準は `--no-field-renaming`(field名を変えない)、候補は `--assume-closed-field-names` を付けて作る。
// 記録が違えば非0で終了する。
//
// 入っている storm-lua-minify が `--assume-closed-field-names` を持たない版(0.9.1 など)のときは、
// 引数なしの実行は「SKIP」と表示して成功で終わる。別の版を試すときは、環境変数 STORM_LUA_MINIFY_CLI に
// その dist/cli.js のパスを指定する。
//
// 記録を取る場面は tests/heavy/trace_minified.lua にある。路線の看板名、信号名、エリアの重心は、
// res/area_track.json と res/signal.toml から作る。
// ?nt debug の出力は、オブジェクトのキーそのものを文字列にするため、短縮すれば変わる。この比較の対象にしない。
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const toml = require("toml");

process.chdir(path.join(__dirname, "..", ".."));

// index.js が minify に渡すフラグと同じにする(index.js を変えたら、ここも合わせる)
const MINIFY_FLAGS = ["-m", "--no-unused-export-removal", "--no-function-specialization", "--no-progress"];

function minifyCli() {
    return process.env.STORM_LUA_MINIFY_CLI
        || path.join("node_modules", "storm-lua-minify", "dist", "cli.js");
}

function supportsClosedFieldNames(cli) {
    const help = spawnSync(process.execPath, [cli, "--help"], { encoding: "utf8" });
    return help.status === 0 && help.stdout.includes("assume-closed-field-names");
}

// 基準(field名を変えない)と候補(名前単位で短縮)を作り、それぞれ一時ディレクトリへ移す。
// 戻り値が undefined のときは、使える minify がなく、比較を飛ばす。
function buildPair(directory) {
    const cli = minifyCli();
    if (!fs.existsSync(cli)) {
        console.error(`storm-lua-minify の CLI が見つかりません: ${cli}`);
        process.exit(2);
    }
    if (!supportsClosedFieldNames(cli)) {
        console.log(`[SKIP] ${cli} は --assume-closed-field-names を持たないため、minify 結果の比較を飛ばします`);
        return undefined;
    }
    if (!fs.existsSync("res/build_info.lua")) {
        console.error("res/build_info.lua がありません。先に pnpm build を実行してください");
        process.exit(2);
    }
    const out = {};
    for (const [name, extra] of [
        ["reference", ["--no-field-renaming"]],
        // セーブデータのキーは g_savedata を経由する読み書きなら自動で守られるが、念のため明示する
        ["candidate", ["--assume-closed-field-names",
            "--never-rename-field", "ui_id", "--never-rename-field", "cheatBattery", "--never-rename-field", "recommendedSettings"]],
    ]) {
        const run = spawnSync(process.execPath, [cli, ...MINIFY_FLAGS, ...extra, "script.lua"], { encoding: "utf8" });
        const produced = "script.min.lua";
        try {
            if (run.status !== 0 || !fs.existsSync(produced)) {
                console.error(`minify に失敗しました(${name}):\n${run.stderr}`);
                process.exit(1);
            }
            out[name] = path.join(directory, `${name}.min.lua`);
            fs.copyFileSync(produced, out[name]);
        } finally {
            // minify が置く出力は、リポジトリ直下に残さない
            fs.rmSync(produced, { force: true });
            fs.rmSync("script.lua.map", { force: true });
        }
    }
    return out;
}

const given = process.argv.slice(2);
if (given.length !== 0 && given.length !== 2) {
    console.error("使い方: node tests/heavy/diff_minified.js [<基準.min.lua> <候補.min.lua>]");
    process.exit(2);
}

function luaString(s) {
    return JSON.stringify(s);
}

function buildScenario() {
    const areaTrack = JSON.parse(fs.readFileSync("res/area_track.json", "utf8"));
    const signals = toml.parse(fs.readFileSync("res/signal.toml", "utf8"));
    const vertexByName = new Map(areaTrack.vertexes.map((v) => [v.name, v]));

    // 列車は、エリアの重心を順に通る。隣り合う番号のエリアを使うので、在線がおおむね連続して動く
    const path = areaTrack.areas.map((area) => {
        const vs = area.vertexes.map((n) => vertexByName.get(n)).filter(Boolean);
        return {
            x: vs.reduce((s, v) => s + v.x, 0) / vs.length,
            z: vs.reduce((s, v) => s + v.z, 0) / vs.length,
        };
    });

    const names = new Set(areaTrack.tracks.map((t) => t.name));
    const levers = Object.keys(signals).filter((name) => signals[name] && signals[name].auto !== true);
    Object.keys(signals).forEach((name) => names.add(name));
    // 転てつ器の名前を拾う(看板に転てつ器の名前を付ければ、K の読み取りと W の送信が動く)
    const switchSource = fs.readFileSync("res/switch.lua", "utf8");
    // 交通方向てこ(create_traffic_direction_*)は現示を持たないので、看板に付けない
    for (const line of switchSource.split("\n").filter((l) => /sw:create_switch\(/.test(l)))
        for (const m of line.matchAll(/"([A-Za-z0-9_]+)"/g)) names.add(m[1]);

    const list = (items) => "{" + items.map(luaString).join(",") + "}";
    const pathLua = "{" + path.map((p) => `{x=${p.x},z=${p.z}}`).join(",") + "}";
    return [
        "return {",
        `  signs = ${list([...names])},`,
        `  levers = ${list(levers)},`,
        `  path = ${pathLua},`,
        "  ticks_per_area = 9,",
        "  ticks = 1200,",
        '  arc_station = "NHB",',
        "}",
        "",
    ].join("\n");
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ntracs-diff-"));
const scenarioPath = path.join(dir, "scenario.lua");

let reference;
let candidate;
if (given.length === 2) {
    [reference, candidate] = given;
} else {
    const pair = buildPair(dir);
    if (!pair) {
        fs.rmSync(dir, { recursive: true, force: true });
        process.exit(0);
    }
    ({ reference, candidate } = pair);
}
fs.writeFileSync(scenarioPath, buildScenario());

function trace(script) {
    const proc = spawnSync("lua", ["tests/heavy/trace_minified.lua", script, scenarioPath], {
        encoding: "utf8",
        maxBuffer: 1 << 28,
    });
    if (proc.status !== 0) {
        console.error(`${script} の実行に失敗しました:\n${proc.stderr}`);
        process.exit(1);
    }
    return proc.stdout.split("\n");
}

// Lua 5.3 は文字列キーの並びを実行ごとに変える(pairs の順)。同じ tick に出た呼び出しは順序を問わず、
// 「-- tick N」で区切った塊ごとに並べ替えて比べる。tick をまたぐ順序、コマンドの前後は保たれる。
function normalize(lines) {
    const out = [];
    let block = [];
    const flush = () => { out.push(...block.sort()); block = []; };
    for (const line of lines) {
        if (line.startsWith("-- ")) { flush(); out.push(line); } else block.push(line);
    }
    flush();
    return out;
}
const a = normalize(trace(reference));
const b = normalize(trace(candidate));
fs.rmSync(dir, { recursive: true, force: true });

const serverCalls = a.filter((l) => l.startsWith("server.")).length;
let diffAt = -1;
for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if (a[i] !== b[i]) { diffAt = i; break; }
}
console.log(`記録 ${a.length} 行 / server 呼び出し ${serverCalls} 回`);
if (serverCalls < 100) {
    console.error("記録が少なすぎます。場面が動いていない可能性があります。");
    process.exit(1);
}
if (diffAt < 0) {
    console.log("一致しました");
} else {
    console.error(`${diffAt + 1} 行目から違います`);
    for (let i = Math.max(0, diffAt - 2); i < diffAt + 5; i++) {
        console.error(`  基準: ${a[i]}\n  候補: ${b[i]}`);
    }
    process.exit(1);
}
