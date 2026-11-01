// フルテスト(pnpm test:full)。軽いテスト、配置なしのビルドと minify 後のスモーク、minify 結果の比較、ARC の総当たりを実行する。
// 方針: 目的別に test:何々 を作り、test:full はそれらを呼ぶ。今は minify 結果の比較(test:minify-diff)だけがこの形で、
// 他の工程は、まだここに直接書いてある。
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
        // pnpm test:minify-diff と同じ。pnpm を経由しないのは、Windows で pnpm の起動に shell が要るため
        ["minify 結果の比較 (test:minify-diff)", "node", ["tests/heavy/diff_minified.js"]],
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
