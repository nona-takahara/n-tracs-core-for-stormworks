// テスト実行前に res/area_track.lua と res/signal.lua を、実際の運用データ
// (res/area_track.json, res/signal.toml) から生成します。
//
// npm run build (index.js) と同じジェネレータ (build/generate_area_track.js,
// build/generate_signal.js) を使うため、生成される内容は本番ビルドと同一です。
// storm-lua-minify によるスクリプト圧縮や dist/ への配置、NTRACS_SW_DIR への
// コピーは行いません。テストの実行だけが目的のためです。
//
// 使い方: node tests/gen_res.js  (このあと Lua 側で require("res.area_track") /
// require("res.signal") が本番構成をロードできるようになります)
const fs = require("fs");
const path = require("path");
const toml = require("toml");
const generateAreaTrack = require("../build/generate_area_track");
const { generateSignal, buildControlsMap, detectControlsCycle } = require("../build/generate_signal");

process.chdir(path.join(__dirname, ".."));

async function main() {
    const [signalSrc, areaTrackSrc] = await Promise.all([
        fs.promises.readFile("res/signal.toml", "utf8"),
        fs.promises.readFile("res/area_track.json", "utf8"),
    ]);

    const signalObj = toml.parse(signalSrc);
    detectControlsCycle(buildControlsMap(signalObj));

    await Promise.all([
        fs.promises.writeFile("res/area_track.lua", generateAreaTrack(JSON.parse(areaTrackSrc))),
        fs.promises.writeFile("res/signal.lua", generateSignal(signalObj)),
    ]);

    console.log("Generated res/area_track.lua and res/signal.lua from production data.");
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
