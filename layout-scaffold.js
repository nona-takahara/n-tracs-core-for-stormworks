const fs   = require("fs");
const path = require("path");
const toml = require("toml");
const { generateLayoutScaffold } = require("./build/generate_layout_scaffold");
const { validateLayout, generateDiagram } = require("./build/generate_diagram");

process.chdir(__dirname);

async function main() {
    const [signalSrc, areaTrackSrc, switchLuaSrc] = await Promise.all([
        fs.promises.readFile("res/signal.toml",     "utf8"),
        fs.promises.readFile("res/area_track.json", "utf8"),
        fs.promises.readFile("res/switch.lua",      "utf8"),
    ]);

    const signalObj    = toml.parse(signalSrc);
    const areaTrackObj = JSON.parse(areaTrackSrc);

    const { toml: scaffoldToml, notes } = generateLayoutScaffold(areaTrackObj, signalObj, switchLuaSrc);

    await fs.promises.mkdir("dist", { recursive: true });
    const outPath = path.join("dist", "layout.scaffold.toml");
    await fs.promises.writeFile(outPath, scaffoldToml);
    console.log(`Generated ${outPath}`);

    for (const [code, codeNotes] of Object.entries(notes)) {
        if (codeNotes.length > 0) {
            console.log(`\n[${code}] TODO notes:`);
            codeNotes.forEach(n => console.log(`  - ${n}`));
        }
    }

    // Sanity-check: the scaffold must itself be valid TOML.
    const scaffoldObj = toml.parse(scaffoldToml);

    // Run it through the same validation the hand-written layout.toml uses.
    const errors = validateLayout(scaffoldObj, signalObj, areaTrackObj);
    if (errors.length > 0) {
        console.log("\nLayout validation (scaffold) found issues:");
        errors.forEach(e => console.log(`  - ${e}`));
    } else {
        console.log("\nLayout validation (scaffold): OK");
    }

    // Also render it to HTML so we can eyeball the result.
    const htmlPath = path.join("dist", "diagram.scaffold.html");
    await fs.promises.writeFile(htmlPath, generateDiagram(scaffoldObj));
    console.log(`Generated ${htmlPath}`);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
