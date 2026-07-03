// Generates a draft (scaffold) of res/layout.toml from the real interlocking
// data (area_track.json / signal.toml / switch.lua). See res/layout.toml's
// header comment for the target schema.
//
// This is intentionally a *best effort* generator: the goal is a topologically
// correct, non-crashing draft that a human can then hand-tune -- not a
// pixel-perfect reproduction of a hand-drawn diagram. Ambiguous decisions are
// resolved with the simplest option and flagged with "# TODO: 要手直し".

const STATION_TRACK_RE = /^([A-Z]+)\d/;
const INTERSTATION_TRACK_RE = /^[A-Z]+_[A-Z]+\d/;

// ---------------------------------------------------------------------------
// switch.lua parsing (name-only, just enough to map switch id -> track ids)
// ---------------------------------------------------------------------------
function parseSwitchLua(src) {
    const switches = []; // { name, tracks: [..] }
    const re = /create_(?:switch|traffic_direction_switch)\(\s*"([^"]+)"\s*,\s*\{([^}]*)\}(?:\s*,\s*\{([^}]*)\})?\s*\)/g;
    let m;
    while ((m = re.exec(src))) {
        const name = m[1];
        // the *last* brace-group present is always the track list: for
        // create_switch it's the 3rd arg, for create_traffic_direction_switch
        // it's the 2nd (and only) arg.
        const trackGroup = m[3] !== undefined ? m[3] : m[2];
        const tracks = trackGroup
            .split(",")
            .map(s => s.trim().replace(/^"|"$/g, ""))
            .filter(Boolean);
        switches.push({ name, tracks });
    }
    return switches;
}

// ---------------------------------------------------------------------------
// area_track.json processing
// ---------------------------------------------------------------------------
function buildTrackGraph(areaTrackObj) {
    const areaByName = new Map(areaTrackObj.areas.map(a => [a.name, a]));
    const areaTrackName = new Map();
    areaTrackObj.tracks.forEach(t => {
        t.areas.forEach(a => areaTrackName.set(a.name, t.name));
    });

    const trackUp = new Map(); // track -> Set(upTrack)
    areaTrackObj.tracks.forEach(t => trackUp.set(t.name, new Set()));
    areaTrackObj.tracks.forEach(t => {
        t.areas.forEach(a => {
            const area = areaByName.get(a.name);
            if (!area) return;
            (area.uparea || []).forEach(upAreaName => {
                const upTrack = areaTrackName.get(upAreaName);
                if (upTrack && upTrack !== t.name) trackUp.get(t.name).add(upTrack);
            });
        });
    });

    const trackDown = new Map();
    areaTrackObj.tracks.forEach(t => trackDown.set(t.name, new Set()));
    trackUp.forEach((ups, t) => ups.forEach(u => trackDown.get(u).add(t)));

    // track -> representative (x,z) point, from the average of its areas' vertexes
    const vertexByName = new Map(areaTrackObj.vertexes.map(v => [v.name, v]));
    const trackPoint = new Map();
    areaTrackObj.tracks.forEach(t => {
        const pts = [];
        t.areas.forEach(a => {
            const area = areaByName.get(a.name);
            if (!area || !area.vertexes) return;
            area.vertexes.forEach(vn => {
                const v = vertexByName.get(vn);
                if (v) pts.push(v);
            });
        });
        if (pts.length > 0) {
            const x = pts.reduce((s, p) => s + p.x, 0) / pts.length;
            const z = pts.reduce((s, p) => s + p.z, 0) / pts.length;
            trackPoint.set(t.name, { x, z });
        }
    });

    return { trackUp, trackDown, trackPoint, trackNames: areaTrackObj.tracks.map(t => t.name) };
}

function stationCodeOf(trackName) {
    const m = trackName.match(STATION_TRACK_RE);
    return m ? m[1] : null;
}

function isInterstation(trackName) {
    return INTERSTATION_TRACK_RE.test(trackName);
}

// ---------------------------------------------------------------------------
// Per-station subgraph
// ---------------------------------------------------------------------------
function buildStationSubgraph(code, graph) {
    const internal = new Set(graph.trackNames.filter(n => stationCodeOf(n) === code));
    if (internal.size === 0) return null;

    const stub = new Set();
    internal.forEach(t => {
        (graph.trackUp.get(t) || new Set()).forEach(u => { if (!internal.has(u)) stub.add(u); });
        (graph.trackDown.get(t) || new Set()).forEach(d => { if (!internal.has(d)) stub.add(d); });
    });

    const nodes = new Set([...internal, ...stub]);
    const preds = new Map(); // node -> [predNode...] (array, deterministic order)
    const succs = new Map();
    nodes.forEach(n => { preds.set(n, []); succs.set(n, []); });
    nodes.forEach(n => {
        const ups = graph.trackUp.get(n) || new Set();
        ups.forEach(u => {
            if (nodes.has(u)) {
                preds.get(n).push(u);
                succs.get(u).push(n);
            }
        });
    });

    return { code, internal, stub, nodes, preds, succs };
}

// ---------------------------------------------------------------------------
// Topological order (Kahn's algorithm; tolerant of leftover/cyclic nodes)
// ---------------------------------------------------------------------------
function topoOrder(sub) {
    const indeg = new Map();
    sub.nodes.forEach(n => indeg.set(n, sub.preds.get(n).length));
    const queue = [...sub.nodes].filter(n => indeg.get(n) === 0).sort();
    const order = [];
    const seen = new Set();
    while (queue.length > 0) {
        const n = queue.shift();
        if (seen.has(n)) continue;
        seen.add(n);
        order.push(n);
        sub.succs.get(n).forEach(s => {
            indeg.set(s, indeg.get(s) - 1);
            if (indeg.get(s) === 0) queue.push(s);
        });
    }
    const notes = [];
    if (order.length < sub.nodes.size) {
        // cycle (shouldn't normally happen for a rail corridor) -- append
        // remaining nodes in arbitrary but deterministic order so the
        // generator never crashes.
        const remaining = [...sub.nodes].filter(n => !seen.has(n)).sort();
        notes.push(`cycle detected involving: ${remaining.join(", ")} (assigned arbitrary order)`);
        order.push(...remaining);
    }
    return { order, notes };
}

// ---------------------------------------------------------------------------
// switch id lookup + normal/reverse voting via signal.toml
// ---------------------------------------------------------------------------
function buildSwitchIndex(switchDefs) {
    const byTrack = new Map(); // track -> [switchName...]
    switchDefs.forEach(sw => {
        sw.tracks.forEach(t => {
            if (!byTrack.has(t)) byTrack.set(t, []);
            byTrack.get(t).push(sw.name);
        });
    });
    return byTrack;
}

function touchedTracksOfLever(lever) {
    const s = new Set();
    if (lever.start) s.add(lever.start);
    if (lever.destination) s.add(lever.destination);
    (lever.route_lock || []).forEach(t => s.add(t));
    (lever.signal_track || []).forEach(t => s.add(t));
    (lever.approach_track || []).forEach(t => s.add(t));
    return s;
}

function makePrimaryPicker(signalObj, switchByTrack) {
    const levers = Object.values(signalObj).filter(v => v && typeof v === "object" && v.start);
    return function primaryOf(hubTrack, candidates) {
        const switchIds = switchByTrack.get(hubTrack) || [];
        if (candidates.length <= 1 || switchIds.length === 0) {
            return { pick: candidates[0], fallback: true };
        }
        const scores = candidates.map(() => 0);
        levers.forEach(lever => {
            (lever.switches || []).forEach(swUse => {
                if (!switchIds.includes(swUse.sw)) return;
                const touched = touchedTracksOfLever(lever);
                candidates.forEach((c, i) => {
                    if (touched.has(c)) scores[i] += swUse.t === "normal" ? 1 : swUse.t === "reverse" ? -1 : 0;
                });
            });
        });
        const maxScore = Math.max(...scores);
        const winners = scores.reduce((acc, s, i) => (s === maxScore ? [...acc, i] : acc), []);
        if (maxScore <= 0 || winners.length !== 1) {
            return { pick: candidates[0], fallback: true };
        }
        return { pick: candidates[winners[0]], fallback: false };
    };
}

// ---------------------------------------------------------------------------
// Column assignment
// ---------------------------------------------------------------------------
function assignColumns(sub, order) {
    const col = new Map();
    order.forEach(n => {
        const preds = sub.preds.get(n);
        if (preds.length === 0) {
            col.set(n, 0);
            return;
        }
        let c = 0;
        const indeg = preds.length;
        preds.forEach(p => {
            const outdeg = sub.succs.get(p).length;
            // Reserve one column per extra branch on *either* side of this
            // edge (the predecessor's own diverge cascade, plus this node's
            // merge cascade), so a switch that is simultaneously a diverge
            // source and part of another merge doesn't collide with itself.
            const weight = 1 + (outdeg > 1 ? outdeg - 1 : 0) + (indeg > 1 ? indeg - 1 : 0);
            c = Math.max(c, col.get(p) + weight);
        });
        col.set(n, c);
    });
    return col;
}

// ---------------------------------------------------------------------------
// Lane (row-group) assignment -- graph driven for correctness; PCA is used
// later only to decide the *order* of lanes (top-to-bottom).
// ---------------------------------------------------------------------------
function assignLanes(sub, order, primaryOf) {
    const lane = new Map();
    const fallbackNotes = [];
    let laneCounter = 0;

    order.forEach(n => {
        const preds = sub.preds.get(n);
        if (preds.length === 0) {
            lane.set(n, laneCounter++);
        } else if (preds.length === 1 && sub.succs.get(preds[0]).length === 1) {
            lane.set(n, lane.get(preds[0]));
        } else if (preds.length === 1) {
            // one of several successors of preds[0] (a diverge)
            const p = preds[0];
            const { pick, fallback } = primaryOf(p, sub.succs.get(p));
            if (fallback) fallbackNotes.push(`diverge at "${p}": normal/reverse not determined from signal.toml, assumed "${pick}" = normal`);
            lane.set(n, pick === n ? lane.get(p) : laneCounter++);
        } else {
            // merge
            const { pick, fallback } = primaryOf(n, preds);
            if (fallback) fallbackNotes.push(`merge into "${n}": normal/reverse not determined from signal.toml, assumed "${pick}" = normal`);
            lane.set(n, lane.get(pick));
        }
    });

    return { lane, fallbackNotes };
}

// ---------------------------------------------------------------------------
// PCA-based lateral offset, used only to order lanes top-to-bottom
// ---------------------------------------------------------------------------
function laneOrderFromPCA(sub, lane, graph) {
    const pts = [];
    sub.nodes.forEach(n => {
        const p = graph.trackPoint.get(n);
        if (p) pts.push(p);
    });
    if (pts.length === 0) {
        // no coordinate data at all -- fall back to lane-id order
        const lanes = [...new Set(lane.values())].sort((a, b) => a - b);
        const rank = new Map(lanes.map((l, i) => [l, i]));
        return rank;
    }
    const cx = pts.reduce((s, p) => s + p.x, 0) / pts.length;
    const cz = pts.reduce((s, p) => s + p.z, 0) / pts.length;
    let sxx = 0, szz = 0, sxz = 0;
    pts.forEach(p => {
        const dx = p.x - cx, dz = p.z - cz;
        sxx += dx * dx; szz += dz * dz; sxz += dx * dz;
    });
    sxx /= pts.length; szz /= pts.length; sxz /= pts.length;
    const theta = 0.5 * Math.atan2(2 * sxz, sxx - szz);
    const perp = [-Math.sin(theta), Math.cos(theta)];

    const laneOffsets = new Map(); // lane -> {sum,count}
    sub.nodes.forEach(n => {
        const p = graph.trackPoint.get(n);
        const l = lane.get(n);
        if (!laneOffsets.has(l)) laneOffsets.set(l, { sum: 0, count: 0 });
        if (p) {
            const off = (p.x - cx) * perp[0] + (p.z - cz) * perp[1];
            laneOffsets.get(l).sum += off;
            laneOffsets.get(l).count += 1;
        }
    });

    const lanes = [...laneOffsets.keys()];
    lanes.sort((a, b) => {
        const oa = laneOffsets.get(a).count ? laneOffsets.get(a).sum / laneOffsets.get(a).count : 0;
        const ob = laneOffsets.get(b).count ? laneOffsets.get(b).sum / laneOffsets.get(b).count : 0;
        return oa - ob;
    });
    const rank = new Map(lanes.map((l, i) => [l, i]));
    return rank;
}

// ---------------------------------------------------------------------------
// Grid rendering
// ---------------------------------------------------------------------------
function renderStationGrid(sub, col, row, switchByTrack, primaryOf, notes) {
    const numRows = new Set(row.values()).size;
    const numCols = Math.max(...[...col.values()]) + 1;
    const grid = Array.from({ length: numRows }, () => Array(numCols).fill("."));
    const switches = {};
    const tileTracks = {};

    // base pass: every node gets a plain through tile on its own cell
    sub.nodes.forEach(n => {
        const r = row.get(n), c = col.get(n);
        grid[r][c] = "LR";
        tileTracks[`${r},${c}`] = n;
    });

    // trackId is optional: when given, every tile filled in by this call
    // (and any tile that doesn't already have one) is tagged with it in
    // tileTracks, so the new "every non-'.' tile needs tile_tracks" layout
    // rule (see build/generate_diagram.js validateLayout) is satisfied even
    // though these filler tiles don't correspond 1:1 to a graph node.
    function fillLR(r, cFrom, cTo, trackId) {
        for (let c = cFrom; c <= cTo; c++) {
            if (grid[r][c] === ".") grid[r][c] = "LR";
            if (trackId && !tileTracks[`${r},${c}`]) tileTracks[`${r},${c}`] = trackId;
        }
    }

    let switchSeq = 0;
    function nextSwitchId(hubTrack, k) {
        const ids = switchByTrack.get(hubTrack) || [];
        if (ids.length > 0) return ids[k % ids.length];
        switchSeq++;
        notes.push(`no switch.lua entry found for track "${hubTrack}"; using placeholder id`);
        return `${hubTrack}_SW${switchSeq}`;
    }

    // merges (indegree > 1), cascaded pairwise. The "trunk" carries the
    // primary predecessor's lane all the way to v; every other predecessor
    // joins in via its own switch column (and a diagonal connector tile).
    sub.nodes.forEach(v => {
        const preds = sub.preds.get(v);
        if (preds.length <= 1) return;
        const { pick: primary, fallback } = primaryOf(v, preds);
        if (fallback) notes.push(`merge into "${v}": switch normal/reverse guessed (no clear signal.toml evidence)`);
        const others = preds.filter(p => p !== primary);
        const trunkRow = row.get(v);
        let prevTrunkCol = col.get(primary);

        others.forEach((otherPred, k) => {
            const switchCol = col.get(v) - (others.length - k);
            const otherRow = row.get(otherPred);
            const id = nextSwitchId(v, k);

            fillLR(trunkRow, prevTrunkCol + 1, switchCol - 1, primary);
            fillLR(otherRow, col.get(otherPred) + 1, switchCol - 1, otherPred);

            const otherBelow = otherRow > trunkRow;
            const diagType = otherBelow ? "LU" : "LD";
            const reverseType = otherBelow ? "RD" : "UR";

            grid[trunkRow][switchCol] = "SW";
            switches[`${trunkRow},${switchCol}`] = { id, normal: "LR", reverse: reverseType };
            tileTracks[`${trunkRow},${switchCol}`] = v;
            grid[otherRow][switchCol] = diagType;
            tileTracks[`${otherRow},${switchCol}`] = otherPred;
            prevTrunkCol = switchCol;
        });
        // final stretch from the last cascade switch column up to v itself
        fillLR(trunkRow, prevTrunkCol + 1, col.get(v) - 1, v);
    });

    // diverges (outdegree > 1), cascaded pairwise
    sub.nodes.forEach(u => {
        const succs = sub.succs.get(u);
        if (succs.length <= 1) return;
        const { pick: primary, fallback } = primaryOf(u, succs);
        if (fallback) notes.push(`diverge from "${u}": switch normal/reverse guessed (no clear signal.toml evidence)`);
        const others = succs.filter(s => s !== primary);
        const trunkRow = row.get(u);
        let prevTrunkCol = col.get(u);

        others.forEach((otherSucc, k) => {
            const switchCol = col.get(u) + 1 + k;
            const otherRow = row.get(otherSucc);
            const id = nextSwitchId(u, k);

            fillLR(trunkRow, prevTrunkCol + 1, switchCol - 1, u);

            const otherBelow = otherRow > trunkRow;
            const diagType = otherBelow ? "UR" : "DR";
            const reverseType = otherBelow ? "LD" : "LU";

            grid[trunkRow][switchCol] = "SW";
            switches[`${trunkRow},${switchCol}`] = { id, normal: "LR", reverse: reverseType };
            tileTracks[`${trunkRow},${switchCol}`] = u;
            grid[otherRow][switchCol] = diagType;
            tileTracks[`${otherRow},${switchCol}`] = otherSucc;

            fillLR(otherRow, switchCol + 1, col.get(otherSucc) - 1, otherSucc);
            prevTrunkCol = switchCol;
        });
        fillLR(trunkRow, prevTrunkCol + 1, col.get(primary) - 1, primary);
    });

    return { grid, switches, tileTracks, numRows, numCols };
}

// ---------------------------------------------------------------------------
// Signals
// ---------------------------------------------------------------------------
function collectSignals(code, sub, col, row, signalObj) {
    const signals = [];
    const seen = new Set(); // dedupe by (track,side): several levers can share one physical signal
    const re = new RegExp(`^${code}\\d`);
    Object.entries(signalObj).forEach(([leverName, lever]) => {
        if (!lever || typeof lever !== "object" || !lever.start) return;
        if (!re.test(leverName)) return;
        if (!lever.direction || (lever.direction !== "left" && lever.direction !== "right")) return;
        const startTrack = lever.start;
        if (!sub.nodes.has(startTrack)) return;
        const key = `${startTrack}|${lever.direction}`;
        if (seen.has(key)) return;
        seen.add(key);
        signals.push({
            lever: leverName,
            at: { row: row.get(startTrack), col: col.get(startTrack), side: lever.direction },
        });
    });
    signals.sort((a, b) => (a.at.row - b.at.row) || (a.at.col - b.at.col));
    return signals;
}

// ---------------------------------------------------------------------------
// TOML serialization (hand-rolled -- only needs to cover this schema)
// ---------------------------------------------------------------------------
function tomlString(s) {
    return `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function serializeStation(code, gridRender, signals, notes) {
    const lines = [];
    lines.push(`[${code}]`);
    if (notes.length > 0) {
        notes.forEach(n => lines.push(`# TODO: 要手直し -- ${n}`));
    }
    lines.push("grid = [");
    gridRender.grid.forEach((rowArr, i) => {
        const comma = i === gridRender.grid.length - 1 ? "" : ",";
        lines.push(`  ${tomlString(rowArr.join("  "))}${comma}`);
    });
    lines.push("]");
    lines.push("");

    const switchKeys = Object.keys(gridRender.switches);
    if (switchKeys.length > 0) {
        lines.push(`[${code}.switches]`);
        switchKeys.forEach(k => {
            const sw = gridRender.switches[k];
            lines.push(`${tomlString(k)} = { id = ${tomlString(sw.id)}, normal = ${tomlString(sw.normal)}, reverse = ${tomlString(sw.reverse)} }`);
        });
        lines.push("");
    }

    const tileTrackKeys = Object.keys(gridRender.tileTracks);
    if (tileTrackKeys.length > 0) {
        lines.push(`[${code}.tile_tracks]`);
        tileTrackKeys.forEach(k => {
            lines.push(`${tomlString(k)} = ${tomlString(gridRender.tileTracks[k])}`);
        });
        lines.push("");
    }

    signals.forEach(sig => {
        lines.push(`[[${code}.signals]]`);
        lines.push(`lever = ${tomlString(sig.lever)}`);
        lines.push(`at = { row = ${sig.at.row}, col = ${sig.at.col}, side = ${tomlString(sig.at.side)} }`);
        lines.push("");
    });

    return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Top level
// ---------------------------------------------------------------------------
function generateLayoutScaffold(areaTrackObj, signalObj, switchLuaSrc) {
    const graph = buildTrackGraph(areaTrackObj);
    const switchDefs = parseSwitchLua(switchLuaSrc);
    const switchByTrack = buildSwitchIndex(switchDefs);
    const primaryOf = makePrimaryPicker(signalObj, switchByTrack);

    const codes = [...new Set(graph.trackNames.map(stationCodeOf).filter(Boolean))].sort();

    const allNotes = {}; // code -> [note...]
    const stationSections = [];

    codes.forEach(code => {
        const sub = buildStationSubgraph(code, graph);
        if (!sub) return;
        const notes = [];

        const { order, notes: topoNotes } = topoOrder(sub);
        notes.push(...topoNotes);

        const col = assignColumns(sub, order);
        const { lane, fallbackNotes } = assignLanes(sub, order, primaryOf);
        notes.push(...fallbackNotes);

        const rank = laneOrderFromPCA(sub, lane, graph);
        const row = new Map();
        sub.nodes.forEach(n => row.set(n, rank.get(lane.get(n))));

        const gridRender = renderStationGrid(sub, col, row, switchByTrack, primaryOf, notes);
        const signals = collectSignals(code, sub, col, row, signalObj);

        // note any interstation stub tracks included, for the report
        sub.stub.forEach(t => {
            if (isInterstation(t)) notes.push(`stub tile for interstation track "${t}" (adjacent block section, not part of ${code} itself)`);
            else notes.push(`stub tile for track "${t}" belonging to a neighboring station`);
        });

        allNotes[code] = notes;
        stationSections.push(serializeStation(code, gridRender, signals, notes));
    });

    const header = [
        "# 自動生成された下書き (layout-scaffold.js / build/generate_layout_scaffold.js)",
        "# res/area_track.json, res/signal.toml, res/switch.lua から機械的に生成しています。",
        "# このファイルをそのまま res/layout.toml として使うのではなく、内容を確認・手直ししてから",
        "# 取り込んでください。特に `# TODO: 要手直し` が付いている箇所は要確認です。",
        "# platforms は未出力です (手作業で追加してください)。",
        "",
    ].join("\n");

    const toml = header + stationSections.join("\n");
    return { toml, notes: allNotes };
}

module.exports = {
    generateLayoutScaffold,
    // exported for testing
    parseSwitchLua,
    buildTrackGraph,
    stationCodeOf,
    isInterstation,
    buildStationSubgraph,
    topoOrder,
    assignColumns,
    assignLanes,
    laneOrderFromPCA,
    buildSwitchIndex,
    makePrimaryPicker,
    renderStationGrid,
};
