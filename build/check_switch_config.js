// signal.toml / switch.lua の転てつ器まわりの記述ミスをビルド時に検出する。
// toml パーサはインラインテーブルの重複キーを黙って後勝ちにするため、原文を直接調べる。

// 1行内のインラインテーブル { ... } で、同じキーが2回以上出ていないか。
function checkInlineTableDuplicateKeys(signalSrc) {
    const errors = [];
    signalSrc.split(/\r?\n/).forEach((rawLine, i) => {
        const line = rawLine
            .replace(/"(?:[^"\\]|\\.)*"|'[^']*'/g, '""') // 文字列の中身を潰す
            .replace(/#.*$/, "");
        for (const m of line.matchAll(/\{([^{}]*)\}/g)) {
            const seen = new Set();
            for (const k of m[1].matchAll(/(?:^|,)\s*([A-Za-z0-9_-]+)\s*=/g)) {
                if (seen.has(k[1])) {
                    errors.push(`signal.toml:${i + 1}: インラインテーブル内でキー '${k[1]}' が重複しています(後ろの値だけが有効になります): ${rawLine.trim()}`);
                }
                seen.add(k[1]);
            }
        }
    });
    return errors;
}

// switch.lua から転てつ器IDと関連trackを取り出す。
function parseSwitchLua(switchSrc) {
    const src = switchSrc.replace(/--.*$/gm, "");
    const strings = (s) => [...s.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
    const switches = new Map(); // id -> related tracks
    for (const m of src.matchAll(/create_switch\(\s*"([^"]+)"\s*,\s*\{[^}]*\}\s*,\s*\{([^}]*)\}/g)) {
        switches.set(m[1], strings(m[2]));
    }
    for (const m of src.matchAll(/create_traffic_direction_switch\(\s*"([^"]+)"\s*,\s*\{([^}]*)\}/g)) {
        switches.set(m[1], strings(m[2]));
    }
    return switches;
}

// signal.toml の switches が switch.lua に定義済みか、同じ転てつ器を1進路で二重に指定していないか、
// switch.lua の関連 track が area_track.json にあるか。
function checkSwitchReferences(signalObj, switchSrc, areaTrackObj) {
    const errors = [];
    const defined = parseSwitchLua(switchSrc);
    const tracks = new Set(areaTrackObj.tracks.map((t) => t.name));

    defined.forEach((related, id) => {
        related.forEach((t) => {
            if (!tracks.has(t)) errors.push(`switch.lua: 転てつ器 '${id}' の関連track '${t}' が area_track.json にありません`);
        });
    });

    Object.entries(signalObj).forEach(([name, data]) => {
        const used = new Set();
        (data.switches || []).forEach((s) => {
            if (!defined.has(s.sw)) {
                errors.push(`[${name}] switches: 転てつ器 '${s.sw}' が switch.lua に定義されていません`);
            }
            if (used.has(s.sw)) {
                errors.push(`[${name}] switches: 転てつ器 '${s.sw}' が重複して指定されています`);
            }
            used.add(s.sw);
        });
    });
    return errors;
}

module.exports = { checkInlineTableDuplicateKeys, parseSwitchLua, checkSwitchReferences };
