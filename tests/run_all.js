// tests/repro_*.lua をすべて実行し、まとめて結果を表示します。
//
// 実行方法: npm test
// (pretest で node tests/gen_res.js が自動実行され、本番データから
//  res/area_track.lua / res/signal.lua を作り直してから走ります)
//
// 各テストファイルは lua コマンドの別プロセスとして実行するため、
// 1ファイルの中の状態が他のテストファイルに漏れることはありません。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

process.chdir(path.join(__dirname, ".."));

const dir = "tests";
const files = fs.readdirSync(dir)
    .filter((f) => /^repro_.*\.lua$/.test(f))
    .sort();

if (files.length === 0) {
    console.log("tests/repro_*.lua が見つかりませんでした。");
    process.exit(0);
}

const results = files.map((file) => {
    const rel = path.join(dir, file);
    const proc = spawnSync("lua", [rel], { encoding: "utf8" });
    return {
        file: rel,
        ok: proc.status === 0,
        output: (proc.stdout || "") + (proc.stderr || ""),
    };
});

console.log("=".repeat(60));
for (const r of results) {
    console.log(`[${r.ok ? "PASS" : "FAIL"}] ${r.file}`);
    if (!r.ok) {
        // 失敗時は [NG] 行と集計行、Luaのエラー行だけ抜き出して表示する
        r.output.split("\n")
            .filter((l) => l.includes("[NG]") || l.includes("アサーション") || l.includes("lua:"))
            .forEach((l) => console.log("    " + l));
    }
}
console.log("=".repeat(60));

const passCount = results.filter((r) => r.ok).length;
console.log(`${passCount} / ${results.length} 件のテストファイルが成功しました`);

if (passCount !== results.length) {
    process.exit(1);
}
