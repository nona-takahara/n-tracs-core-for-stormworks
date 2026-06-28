const fs   = require("fs");
const path = require("path");
const toml = require("toml");
const { validateLayout, generateDiagram } = require("./build/generate_diagram");

process.chdir(__dirname);

async function main() {
    const [layoutSrc, signalSrc, areaTrackSrc] = await Promise.all([
        fs.promises.readFile("res/layout.toml",     "utf8"),
        fs.promises.readFile("res/signal.toml",     "utf8"),
        fs.promises.readFile("res/area_track.json", "utf8"),
    ]);

    const layoutObj    = toml.parse(layoutSrc);
    const signalObj    = toml.parse(signalSrc);
    const areaTrackObj = JSON.parse(areaTrackSrc);

    const errors = validateLayout(layoutObj, signalObj, areaTrackObj);
    if (errors.length > 0) {
        console.error("Layout validation failed:\n" + errors.join("\n"));
        process.exit(1);
    }
    console.log("Layout validation: OK");

    await fs.promises.mkdir("dist", { recursive: true });
    const outPath = path.join("dist", "diagram.html");
    await fs.promises.writeFile(outPath, generateDiagram(layoutObj));
    console.log(`Generated ${outPath}`);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
