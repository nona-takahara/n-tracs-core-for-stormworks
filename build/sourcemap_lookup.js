// minify 後のスクリプトの行(・桁)から、元のファイルと行を調べる。
// 使い方: node build/sourcemap_lookup.js <行> [桁] [--map dist/script.lua.map]
// 行は 1 始まり、桁は 0 始まり(省略時は行内の各トークンの対応先を一覧する)。
const fs = require("fs");
const { SourceMapConsumer } = require("source-map");

const args = process.argv.slice(2);
const mapIdx = args.indexOf("--map");
const mapPath = mapIdx >= 0 ? args.splice(mapIdx, 2)[1] : "dist/script.lua.map";
const line = Number(args[0]);
const column = args[1] === undefined ? undefined : Number(args[1]);
if (!Number.isInteger(line)) {
    console.error("usage: node build/sourcemap_lookup.js <line> [column] [--map <path>]");
    process.exit(1);
}

function show(pos) {
    if (pos.source === null) return "(対応なし)";
    const text = pos.source && fs.existsSync(pos.source)
        ? (fs.readFileSync(pos.source, "utf8").split(/\r?\n/)[pos.line - 1] || "").trim()
        : "";
    return `${pos.source}:${pos.line}:${pos.column}  ${text.slice(0, 120)}`;
}

(async () => {
    const consumer = await new SourceMapConsumer(JSON.parse(fs.readFileSync(mapPath, "utf8")));
    if (column !== undefined) {
        console.log(show(consumer.originalPositionFor({ line, column })));
    } else {
        const seen = new Set();
        consumer.eachMapping((m) => {
            if (m.generatedLine !== line) return;
            const out = show({ source: m.source, line: m.originalLine, column: m.originalColumn });
            if (!seen.has(out)) {
                seen.add(out);
                console.log(`col ${m.generatedColumn}: ${out}`);
            }
        });
        if (seen.size === 0) console.log("この行に対応するマッピングがありません");
    }
    consumer.destroy && consumer.destroy();
})();
