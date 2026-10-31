// フルテスト(pnpm test:full)。軽いテスト、配置なしのビルドと minify 後のスモーク、ARC の総当たりを実行する。
// 総当たりは駅ごとに数分かかるので、並列に回す。
const path = require("path");
const { spawn } = require("child_process");

process.chdir(path.join(__dirname, "..", ".."));

const STATIONS = ["NHB", "TKM", "SNH", "NMC"];
// 空にしておくと、.env の値が使われず、ビルドが配置しない
const NO_DEPLOY = { ...process.env, NTRACS_SW_DIR: "" };

function run(label, cmd, args, env = process.env) {
    return new Promise((resolve) => {
        const proc = spawn(cmd, args, { env });
        let output = "";
        proc.stdout.on("data", (d) => { output += d; });
        proc.stderr.on("data", (d) => { output += d; });
        proc.on("error", (e) => resolve({ label, ok: false, output: String(e) }));
        proc.on("close", (code) => resolve({ label, ok: code === 0, output }));
    });
}

function report(result) {
    console.log(`[${result.ok ? "PASS" : "FAIL"}] ${result.label}`);
    if (!result.ok) console.log(result.output);
    return result.ok;
}

async function main() {
    const steps = [
        ["テスト用データの生成", "node", ["tests/gen_res.js"]],
        ["軽いテスト", "node", ["tests/run_all.js"]],
        ["配置なしのビルド", "node", ["index.js"], NO_DEPLOY],
        ["minify 後のスモーク", "lua", ["tests/heavy/smoke_minified.lua"]],
    ];
    let ok = true;
    for (const [label, cmd, args, env] of steps) {
        ok = report(await run(label, cmd, args, env)) && ok;
    }
    const explored = await Promise.all(STATIONS.map((station) =>
        run(`ARC の総当たり ${station}`, "lua", ["tests/heavy/explore_arc.lua", station])));
    for (const result of explored) ok = report(result) && ok;
    if (!ok) process.exit(1);
}

main();
