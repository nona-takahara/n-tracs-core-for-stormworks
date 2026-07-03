const TILE_SIZE = 40;

const PORTS = {
    L: [0,           TILE_SIZE / 2],
    R: [TILE_SIZE,   TILE_SIZE / 2],
    U: [TILE_SIZE / 2, 0],
    D: [TILE_SIZE / 2, TILE_SIZE],
};

const TILE_PATHS = {
    LR: ['L', 'R'], RL: ['L', 'R'],
    UD: ['U', 'D'], DU: ['U', 'D'],
    LD: ['L', 'D'], DL: ['L', 'D'],
    LU: ['L', 'U'], UL: ['L', 'U'],
    RD: ['R', 'D'], DR: ['R', 'D'],
    RU: ['R', 'U'], UR: ['R', 'U'],
};

const SIDE_TO_PORT   = { left: 'L', right: 'R', up: 'U', down: 'D' };
const OUTWARD_DIR    = { L: [-1, 0], R: [1, 0], U: [0, -1], D: [0, 1] };

const STROKE_BASE    = `stroke="black" stroke-width="3" stroke-linecap="round"`;
const STROKE_REVERSE = `stroke="#aaa" stroke-width="3" stroke-linecap="round" stroke-dasharray="4,2"`;

function parseGridRow(rowString) {
    return rowString.trim().split(/\s+/);
}

function portKeyOf(side) {
    return SIDE_TO_PORT[side] || (side ? side[0].toUpperCase() : undefined);
}

// -----------------------------------------------------------------------
// Station-code-based id shortening, shared by switch number labels and
// track circuit labels: "NHB21" (station "NHB") -> "21", but an id that
// doesn't start with the station code + a digit (e.g. an inter-station
// track like "HLT_NHB1T") is left untouched.
// -----------------------------------------------------------------------
function shortenId(fullId, stationCode) {
    if (fullId.startsWith(stationCode) && /[0-9]/.test(fullId[stationCode.length] || '')) {
        return fullId.slice(stationCode.length);
    }
    return fullId;
}

function drawPath(portA, portB, x0, y0, style) {
    const x1 = x0 + PORTS[portA][0];
    const y1 = y0 + PORTS[portA][1];
    const x2 = x0 + PORTS[portB][0];
    const y2 = y0 + PORTS[portB][1];
    return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" ${style}/>`;
}

function renderTile(type, col, row, stationY) {
    if (type === '.' || !TILE_PATHS[type]) return '';
    const x0 = col * TILE_SIZE;
    const y0 = stationY + row * TILE_SIZE;
    const [a, b] = TILE_PATHS[type];
    return drawPath(a, b, x0, y0, STROKE_BASE);
}

function renderSwitchTile(col, row, stationY, switchDef) {
    const x0 = col * TILE_SIZE;
    const y0 = stationY + row * TILE_SIZE;
    const out = [];
    const revPorts = TILE_PATHS[switchDef.reverse];
    const norPorts = TILE_PATHS[switchDef.normal];
    if (revPorts) out.push(drawPath(revPorts[0], revPorts[1], x0, y0, STROKE_REVERSE));
    if (norPorts) out.push(drawPath(norPorts[0], norPorts[1], x0, y0, STROKE_BASE));
    return out.join('');
}

// Ports a tile occupies, for connectivity/adjacency purposes. For a SW tile
// this is the union of its normal and reverse paths (it physically touches
// every port either route uses).
function tilePorts(type, switchDef) {
    if (type === 'SW') {
        const s = new Set();
        if (switchDef) {
            (TILE_PATHS[switchDef.normal] || []).forEach(p => s.add(p));
            (TILE_PATHS[switchDef.reverse] || []).forEach(p => s.add(p));
        }
        return s;
    }
    return new Set(TILE_PATHS[type] || []);
}

// -----------------------------------------------------------------------
// Signal glyph registry. Each glyph function receives the (already
// shift-translated) anchor point, the outward-facing unit direction the
// signal faces, and the (unshortened) lever name, and returns SVG markup.
// Adding a new signal type is just adding one entry here.
//
// Label placement is direction-aware so the lever name never overlaps the
// head symbol: for a horizontally-facing signal the label is set beside
// the head (anchored away from it, not centered on it); for a vertically
// facing signal it stays centered above/below the head.
// -----------------------------------------------------------------------
function signalLabel(hx, hy, dx, dy, headSize, lever) {
    let x, y, anchor;
    if (dx !== 0) {
        anchor = dx > 0 ? 'start' : 'end';
        x = hx + dx * (headSize + 4);
        y = hy + 2.5;
    } else {
        anchor = 'middle';
        x = hx;
        y = hy + dy * (headSize + 9) + (dy > 0 ? 0 : -1);
    }
    return `<text x="${x}" y="${y}" font-size="7" text-anchor="${anchor}" fill="#333">${lever}</text>`;
}

function mainSignalGlyph(ax, ay, dx, dy, lever) {
    const MAST_LEN = 10;
    const HEAD_R   = 4;
    const isH      = dx !== 0;

    const mx = ax + dx * 6;
    const my = ay + dy * 6;
    const mastLine = isH
        ? `<line x1="${mx}" y1="${my - MAST_LEN / 2}" x2="${mx}" y2="${my + MAST_LEN / 2}" stroke="black" stroke-width="1.5"/>`
        : `<line x1="${mx - MAST_LEN / 2}" y1="${my}" x2="${mx + MAST_LEN / 2}" y2="${my}" stroke="black" stroke-width="1.5"/>`;

    const hx = mx + dx * (HEAD_R + 2);
    const hy = my + dy * (HEAD_R + 2);
    const head = `<circle cx="${hx}" cy="${hy}" r="${HEAD_R}" fill="white" stroke="black" stroke-width="1.5"/>`;

    const label = signalLabel(hx, hy, dx, dy, HEAD_R, lever);

    return mastLine + head + label;
}

function shuntSignalGlyph(ax, ay, dx, dy, lever) {
    const MAST_LEN = 8;
    const HEAD_HALF = 3;
    const isH = dx !== 0;

    const mx = ax + dx * 5;
    const my = ay + dy * 5;
    const mastLine = isH
        ? `<line x1="${mx}" y1="${my - MAST_LEN / 2}" x2="${mx}" y2="${my + MAST_LEN / 2}" stroke="black" stroke-width="1.5"/>`
        : `<line x1="${mx - MAST_LEN / 2}" y1="${my}" x2="${mx + MAST_LEN / 2}" y2="${my}" stroke="black" stroke-width="1.5"/>`;

    const hx = mx + dx * (HEAD_HALF + 2);
    const hy = my + dy * (HEAD_HALF + 2);
    const head = `<rect x="${hx - HEAD_HALF}" y="${hy - HEAD_HALF}" width="${HEAD_HALF * 2}" height="${HEAD_HALF * 2}" fill="white" stroke="black" stroke-width="1.5"/>`;

    const label = signalLabel(hx, hy, dx, dy, HEAD_HALF, lever);

    return mastLine + head + label;
}

const SIGNAL_GLYPHS = {
    main:  mainSignalGlyph,
    shunt: shuntSignalGlyph,
};

function renderSignal(sigDef, stationY) {
    const { lever, at, shift, type } = sigDef;
    const glyphFn = SIGNAL_GLYPHS[type || 'main'];
    if (!glyphFn) return ''; // unreachable if validated first

    const portKey = portKeyOf(at.side);
    const [portDx, portDy] = PORTS[portKey];
    const shiftX = ((shift && shift.x) || 0) * TILE_SIZE;
    const shiftY = ((shift && shift.y) || 0) * TILE_SIZE;

    const ax = at.col * TILE_SIZE + portDx + shiftX;
    const ay = stationY + at.row * TILE_SIZE + portDy + shiftY;
    const [dx, dy] = OUTWARD_DIR[portKey];

    return glyphFn(ax, ay, dx, dy, lever);
}

// -----------------------------------------------------------------------
// Bumpers (車止め): a short bar across the track, perpendicular to the
// facing port, at the exact port point of the given tile/side.
// -----------------------------------------------------------------------
function renderBumper(bumperDef, stationY) {
    const { at } = bumperDef;
    const portKey = portKeyOf(at.side);
    const [portDx, portDy] = PORTS[portKey];
    const x = at.col * TILE_SIZE + portDx;
    const y = stationY + at.row * TILE_SIZE + portDy;
    const LEN = 14;
    const isH = portKey === 'L' || portKey === 'R';
    return isH
        ? `<line x1="${x}" y1="${y - LEN / 2}" x2="${x}" y2="${y + LEN / 2}" stroke="black" stroke-width="3"/>`
        : `<line x1="${x - LEN / 2}" y1="${y}" x2="${x + LEN / 2}" y2="${y}" stroke="black" stroke-width="3"/>`;
}

// -----------------------------------------------------------------------
// Fouling marks (車両接触限界標識): a small X. Coordinate convention shared
// with signals' shift and platforms: x = col*TILE_SIZE, y = stationY +
// row*TILE_SIZE (row/col taken as free tile-unit coordinates, so e.g.
// col=7.5 sits at the horizontal center of grid column 7).
// -----------------------------------------------------------------------
function renderFoulingMark(fm, stationY) {
    const { at } = fm;
    const x = at.col * TILE_SIZE;
    const y = stationY + at.row * TILE_SIZE;
    const S = 4;
    return (
        `<line x1="${x - S}" y1="${y - S}" x2="${x + S}" y2="${y + S}" stroke="black" stroke-width="1.5"/>` +
        `<line x1="${x - S}" y1="${y + S}" x2="${x + S}" y2="${y - S}" stroke="black" stroke-width="1.5"/>`
    );
}

// -----------------------------------------------------------------------
// Platforms: free-form rect + label. Same tile-unit coordinate convention
// as fouling marks: at.row/at.col is the rect's top-left corner, width and
// height are also in tile units.
// -----------------------------------------------------------------------
function renderPlatform(platform, stationY) {
    const { at } = platform;
    const x = at.col * TILE_SIZE;
    const y = stationY + at.row * TILE_SIZE;
    const w = at.width * TILE_SIZE;
    const h = at.height * TILE_SIZE;
    const cx = x + w / 2;
    const cy = y + h / 2;
    return [
        `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="rgba(100,160,255,0.18)" stroke="#99b" stroke-width="1"/>`,
        `<text x="${cx}" y="${cy + 3}" font-size="9" text-anchor="middle" fill="#336">${platform.name}</text>`,
    ].join('');
}

// -----------------------------------------------------------------------
// Switch number labels (#3): short label ("21") placed on the side
// opposite to where the reverse route diverges vertically, unless
// overridden by an explicit label_side.
// -----------------------------------------------------------------------
function switchLabelSide(switchDef) {
    if (switchDef.label_side) {
        return portKeyOf(switchDef.label_side);
    }
    const revPorts = TILE_PATHS[switchDef.reverse] || [];
    if (revPorts.includes('U')) return 'D';
    if (revPorts.includes('D')) return 'U';
    return 'U';
}

function renderSwitchLabel(row, col, switchDef, stationY, stationCode) {
    const short = shortenId(switchDef.id, stationCode);
    const side = switchLabelSide(switchDef);
    const [dx, dy] = OUTWARD_DIR[side];
    const cx = col * TILE_SIZE + TILE_SIZE / 2;
    const cy = stationY + row * TILE_SIZE + TILE_SIZE / 2;
    const dist = TILE_SIZE / 2 + 10;

    // Up/down placement centers the label horizontally, clear of the line
    // above/below it. Left/right placement must also clear the (horizontal)
    // line vertically, so it doesn't sit directly on the stroke.
    let lx, ly, anchor;
    if (dy !== 0) {
        lx = cx;
        ly = cy + dy * dist + 3;
        anchor = 'middle';
    } else {
        lx = cx + dx * dist;
        ly = cy - 6;
        anchor = dx > 0 ? 'start' : 'end';
    }
    return `<text x="${lx}" y="${ly}" font-size="7" text-anchor="${anchor}" fill="#333">${short}</text>`;
}

// -----------------------------------------------------------------------
// Track circuit boundary ticks (#5, automatic): where two adjacent,
// connected tiles belong to different circuits, draw a short tick
// perpendicular to the line at their shared port point.
// -----------------------------------------------------------------------
function renderCircuitBoundaries(gridRows, switches, tileTracks, stationY) {
    const parts = [];
    const numRows = gridRows.length;

    function typeAt(r, c) {
        return (gridRows[r] && gridRows[r][c]) || '.';
    }
    function portsAt(r, c) {
        const type = typeAt(r, c);
        if (type === '.') return new Set();
        return tilePorts(type, switches[`${r},${c}`]);
    }
    function trackAt(r, c) {
        return tileTracks[`${r},${c}`];
    }

    for (let row = 0; row < numRows; row++) {
        const numCols = gridRows[row].length;
        for (let col = 0; col < numCols; col++) {
            // Horizontal neighbor (this col, col+1)
            if (col + 1 < numCols) {
                const a = typeAt(row, col), b = typeAt(row, col + 1);
                if (a !== '.' && b !== '.') {
                    const pa = portsAt(row, col), pb = portsAt(row, col + 1);
                    if (pa.has('R') && pb.has('L')) {
                        const ta = trackAt(row, col), tb = trackAt(row, col + 1);
                        if (ta && tb && ta !== tb) {
                            const x = (col + 1) * TILE_SIZE;
                            const y = stationY + row * TILE_SIZE + TILE_SIZE / 2;
                            parts.push(`<line x1="${x}" y1="${y - 4}" x2="${x}" y2="${y + 4}" stroke="black" stroke-width="1.5"/>`);
                        }
                    }
                }
            }
            // Vertical neighbor (this row, row+1)
            if (row + 1 < numRows) {
                const a = typeAt(row, col), b = typeAt(row + 1, col);
                if (a !== '.' && b !== '.') {
                    const pa = portsAt(row, col), pb = portsAt(row + 1, col);
                    if (pa.has('D') && pb.has('U')) {
                        const ta = trackAt(row, col), tb = trackAt(row + 1, col);
                        if (ta && tb && ta !== tb) {
                            const x = col * TILE_SIZE + TILE_SIZE / 2;
                            const y = stationY + (row + 1) * TILE_SIZE;
                            parts.push(`<line x1="${x - 4}" y1="${y}" x2="${x + 4}" y2="${y}" stroke="black" stroke-width="1.5"/>`);
                        }
                    }
                }
            }
        }
    }
    return parts.join('');
}

// -----------------------------------------------------------------------
// Track circuit labels (#5, automatic): "(21T)" drawn on top of the line,
// white-fringed for legibility, at the representative tile of each
// circuit's most common row (overridable per circuit).
// -----------------------------------------------------------------------
function computeTrackLabelPositions(tileTracks, overrides) {
    const groups = new Map();
    for (const [key, trackId] of Object.entries(tileTracks)) {
        const [row, col] = key.split(',').map(Number);
        if (!groups.has(trackId)) groups.set(trackId, []);
        groups.get(trackId).push({ row, col });
    }

    const labels = [];
    for (const [trackId, tiles] of groups.entries()) {
        if (overrides && overrides[trackId]) {
            labels.push({ trackId, row: overrides[trackId].row, col: overrides[trackId].col });
            continue;
        }
        const rowCounts = new Map();
        tiles.forEach(t => rowCounts.set(t.row, (rowCounts.get(t.row) || 0) + 1));
        let modeRow, modeCount = -1;
        for (const [r, c] of rowCounts.entries()) {
            if (c > modeCount || (c === modeCount && r < modeRow)) { modeRow = r; modeCount = c; }
        }
        const rowTiles = tiles.filter(t => t.row === modeRow).sort((a, b) => a.col - b.col);
        const repCol = rowTiles[Math.floor((rowTiles.length - 1) / 2)].col;
        labels.push({ trackId, row: modeRow + 0.5, col: repCol + 0.5 });
    }
    return labels;
}

function renderTrackLabel(label, stationY, stationCode) {
    const x = label.col * TILE_SIZE;
    const y = stationY + label.row * TILE_SIZE;
    const short = shortenId(label.trackId, stationCode);
    // Opaque backing rect: the paint-order white fringe alone leaves pinhole
    // gaps between glyphs where the track line shows through as dots.
    const text = `(${short})`;
    const w = text.length * 4.3 + 2;
    const rect = `<rect x="${x - w / 2}" y="${y - 4.5}" width="${w}" height="9" fill="white"/>`;
    return rect + `<text x="${x}" y="${y + 2.5}" font-size="7" text-anchor="middle" fill="#555">${text}</text>`;
}

function renderStation(stationName, stationData, stationY) {
    const gridRows      = (stationData.grid    || []).map(parseGridRow);
    const switches      = stationData.switches  || {};
    const tileTracks    = stationData.tile_tracks || {};
    const signals       = stationData.signals   || [];
    const platforms     = stationData.platforms || [];
    const bumpers       = stationData.bumpers   || [];
    const foulingMarks  = stationData.fouling_marks || [];
    const labelOverrides = stationData.track_label_overrides || {};

    const numRows = gridRows.length;
    const numCols = gridRows.length > 0 ? Math.max(...gridRows.map(r => r.length)) : 0;

    const parts = [];

    // Station label
    parts.push(`<text x="0" y="${stationY - 6}" font-size="12" font-weight="bold" fill="#111">${stationName}</text>`);

    // Platforms (behind tracks)
    for (const p of platforms) parts.push(renderPlatform(p, stationY));

    // Tiles
    for (let row = 0; row < gridRows.length; row++) {
        for (let col = 0; col < gridRows[row].length; col++) {
            const type = gridRows[row][col];
            if (type === 'SW') {
                const sw = switches[`${row},${col}`];
                if (sw) parts.push(renderSwitchTile(col, row, stationY, sw));
            } else {
                parts.push(renderTile(type, col, row, stationY));
            }
        }
    }

    // Switch number labels
    for (const [key, sw] of Object.entries(switches)) {
        const [row, col] = key.split(',').map(Number);
        parts.push(renderSwitchLabel(row, col, sw, stationY, stationName));
    }

    // Circuit boundary ticks (automatic)
    parts.push(renderCircuitBoundaries(gridRows, switches, tileTracks, stationY));

    // Track circuit labels (automatic, on top of the line)
    for (const label of computeTrackLabelPositions(tileTracks, labelOverrides)) {
        parts.push(renderTrackLabel(label, stationY, stationName));
    }

    // Bumpers
    for (const b of bumpers) parts.push(renderBumper(b, stationY));

    // Fouling marks
    for (const fm of foulingMarks) parts.push(renderFoulingMark(fm, stationY));

    // Signal symbols (on top of everything)
    for (const sig of signals) parts.push(renderSignal(sig, stationY));

    return { svg: parts.join('\n'), height: numRows * TILE_SIZE, numCols };
}

function generateDiagram(layoutObj) {
    const PADDING  = { top: 30, left: 10, right: 10 };
    const GAP      = 40;
    let currentY   = PADDING.top;
    let maxCols    = 0;
    const svgParts = [];

    for (const [name, data] of Object.entries(layoutObj)) {
        const { svg, height, numCols } = renderStation(name, data, currentY);
        svgParts.push(svg);
        maxCols   = Math.max(maxCols, numCols);
        currentY += height + GAP;
    }

    const svgW = maxCols * TILE_SIZE + PADDING.left + PADDING.right;
    const svgH = currentY;

    return `<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <title>連動図表</title>
  <style>
    body { font-family: sans-serif; background: #f0f0f0; padding: 20px; }
    svg  { display: block; background: #fff; border: 1px solid #bbb; }
    svg text { font-family: monospace; }
  </style>
</head>
<body>
  <svg xmlns="http://www.w3.org/2000/svg"
       width="${svgW}" height="${svgH}"
       viewBox="0 0 ${svgW} ${svgH}">
    <g transform="translate(${PADDING.left}, 0)">
${svgParts.join('\n')}
    </g>
  </svg>
</body>
</html>`;
}

function inBoundsRC(row, col, numRows, numCols) {
    return row >= -1 && row <= numRows + 1 && col >= -1 && col <= numCols + 1;
}

function validateLayout(layoutObj, signalObj, areaTrackObj) {
    const registeredTracks = new Set(areaTrackObj.tracks.map(t => t.name));
    const registeredLevers = new Set(Object.keys(signalObj));
    const knownSignalTypes = Object.keys(SIGNAL_GLYPHS);
    const errors = [];

    for (const [stationName, stationData] of Object.entries(layoutObj)) {
        const gridRows   = (stationData.grid || []).map(parseGridRow);
        const switches   = stationData.switches   || {};
        const tileTracks = stationData.tile_tracks || {};
        const signals    = stationData.signals    || [];
        const bumpers    = stationData.bumpers    || [];
        const foulingMarks = stationData.fouling_marks || [];
        const platforms  = stationData.platforms || [];

        const numRows = gridRows.length;
        const numCols = gridRows.length > 0 ? Math.max(...gridRows.map(r => r.length)) : 0;

        // SW tile positions from grid
        const gridSwPositions = new Set();
        const gridTrackPositions = new Set(); // any non-'.' tile
        for (let row = 0; row < gridRows.length; row++) {
            for (let col = 0; col < gridRows[row].length; col++) {
                const type = gridRows[row][col];
                if (type === 'SW') gridSwPositions.add(`${row},${col}`);
                if (type !== '.') gridTrackPositions.add(`${row},${col}`);
            }
        }
        const switchKeys = new Set(Object.keys(switches));

        // Rule 1: SW tiles must have switches entry
        for (const pos of gridSwPositions) {
            if (!switchKeys.has(pos))
                errors.push(`[${stationName}] SW tile at (${pos}) has no entry in [${stationName}.switches]`);
        }

        // Rule 2: switches entries must be on SW tiles
        for (const pos of switchKeys) {
            if (!gridSwPositions.has(pos))
                errors.push(`[${stationName}.switches] entry "${pos}" is not a SW tile in the grid`);
        }

        // Rule 3: tile_tracks IDs must exist in area_track.json
        for (const [, trackId] of Object.entries(tileTracks)) {
            if (!registeredTracks.has(trackId))
                errors.push(`[${stationName}.tile_tracks] track '${trackId}' not in area_track.json`);
        }

        // Rule 3b: every track tile must have a tile_tracks entry, and every
        // tile_tracks entry must point at a real track tile (not '.').
        const tileTrackKeys = new Set(Object.keys(tileTracks));
        for (const pos of gridTrackPositions) {
            if (!tileTrackKeys.has(pos))
                errors.push(`[${stationName}.tile_tracks] tile (${pos}) has no track circuit assigned`);
        }
        for (const pos of tileTrackKeys) {
            if (!gridTrackPositions.has(pos))
                errors.push(`[${stationName}.tile_tracks] entry "${pos}" is not a track tile in the grid (must not target '.')`);
        }

        // Rule 4: signal lever IDs must exist in signal.toml, and signal
        // type must be a known glyph.
        for (const sigDef of signals) {
            if (!registeredLevers.has(sigDef.lever))
                errors.push(`[${stationName}.signals] lever '${sigDef.lever}' not in signal.toml`);
            const type = sigDef.type || 'main';
            if (!SIGNAL_GLYPHS[type])
                errors.push(`[${stationName}.signals] lever '${sigDef.lever}' has unknown type '${type}' (known types: ${knownSignalTypes.join(', ')})`);
            if (!inBoundsRC(sigDef.at.row, sigDef.at.col, numRows, numCols))
                errors.push(`[${stationName}.signals] lever '${sigDef.lever}' position (${sigDef.at.row},${sigDef.at.col}) is out of grid bounds`);
        }

        // Rule 5: bumpers must be within grid bounds
        for (const b of bumpers) {
            if (!inBoundsRC(b.at.row, b.at.col, numRows, numCols))
                errors.push(`[${stationName}.bumpers] position (${b.at.row},${b.at.col}) is out of grid bounds`);
        }

        // Rule 6: fouling marks must be within grid bounds
        for (const fm of foulingMarks) {
            if (!inBoundsRC(fm.at.row, fm.at.col, numRows, numCols))
                errors.push(`[${stationName}.fouling_marks] position (${fm.at.row},${fm.at.col}) is out of grid bounds`);
        }

        // Rule 7: platforms must be within grid bounds
        for (const p of platforms) {
            if (!inBoundsRC(p.at.row, p.at.col, numRows, numCols))
                errors.push(`[${stationName}.platforms] '${p.name}' position (${p.at.row},${p.at.col}) is out of grid bounds`);
        }
    }

    return errors;
}

module.exports = { validateLayout, generateDiagram };
