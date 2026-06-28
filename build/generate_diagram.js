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

function renderSignal(sigDef, stationY) {
    const { lever, at } = sigDef;
    const portKey = SIDE_TO_PORT[at.side] || at.side[0].toUpperCase();
    const [portDx, portDy] = PORTS[portKey];
    const ax = at.col * TILE_SIZE + portDx;
    const ay = stationY + at.row * TILE_SIZE + portDy;
    const [dx, dy] = OUTWARD_DIR[portKey];

    const MAST_LEN = 10;
    const HEAD_R   = 4;
    const isH      = dx !== 0;

    // Mast: perpendicular to facing direction, at 6px outside tile edge
    const mx = ax + dx * 6;
    const my = ay + dy * 6;
    const mastLine = isH
        ? `<line x1="${mx}" y1="${my - MAST_LEN/2}" x2="${mx}" y2="${my + MAST_LEN/2}" stroke="black" stroke-width="1.5"/>`
        : `<line x1="${mx - MAST_LEN/2}" y1="${my}" x2="${mx + MAST_LEN/2}" y2="${my}" stroke="black" stroke-width="1.5"/>`;

    // Head circle: outward from mast
    const hx = mx + dx * (HEAD_R + 2);
    const hy = my + dy * (HEAD_R + 2);
    const head = `<circle cx="${hx}" cy="${hy}" r="${HEAD_R}" fill="white" stroke="black" stroke-width="1.5"/>`;

    // Label: outward from head
    const lx = mx + dx * (HEAD_R * 2 + 8);
    const ly = my + dy * (HEAD_R * 2 + 8) + 3;
    const label = `<text x="${lx}" y="${ly}" font-size="7" text-anchor="middle" fill="#333">${lever}</text>`;

    return mastLine + head + label;
}

function renderPlatform(platform, stationY) {
    const minCol = Math.min(...platform.cols);
    const maxCol = Math.max(...platform.cols);
    const x  = minCol * TILE_SIZE;
    const y  = stationY + platform.row * TILE_SIZE;
    const w  = (maxCol - minCol + 1) * TILE_SIZE;
    const h  = TILE_SIZE;
    const cx = x + w / 2;
    const cy = y + h / 2;
    return [
        `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="rgba(100,160,255,0.18)" stroke="#99b" stroke-width="1"/>`,
        `<text x="${cx}" y="${cy + 4}" font-size="9" text-anchor="middle" fill="#336">${platform.name}</text>`,
    ].join('');
}

function renderStation(stationName, stationData, stationY) {
    const gridRows  = (stationData.grid    || []).map(parseGridRow);
    const switches  = stationData.switches  || {};
    const tileTracks = stationData.tile_tracks || {};
    const signals   = stationData.signals   || [];
    const platforms = stationData.platforms || [];

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

    // Track ID labels
    for (const [key, trackId] of Object.entries(tileTracks)) {
        const [row, col] = key.split(',').map(Number);
        const lx = col * TILE_SIZE + TILE_SIZE / 2;
        const ly = stationY + row * TILE_SIZE + TILE_SIZE - 3;
        parts.push(`<text x="${lx}" y="${ly}" font-size="6" text-anchor="middle" fill="#888">${trackId}</text>`);
    }

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

function validateLayout(layoutObj, signalObj, areaTrackObj) {
    const registeredTracks = new Set(areaTrackObj.tracks.map(t => t.name));
    const registeredLevers = new Set(Object.keys(signalObj));
    const errors = [];

    for (const [stationName, stationData] of Object.entries(layoutObj)) {
        const gridRows   = (stationData.grid || []).map(parseGridRow);
        const switches   = stationData.switches   || {};
        const tileTracks = stationData.tile_tracks || {};
        const signals    = stationData.signals    || [];

        // SW tile positions from grid
        const gridSwPositions = new Set();
        for (let row = 0; row < gridRows.length; row++) {
            for (let col = 0; col < gridRows[row].length; col++) {
                if (gridRows[row][col] === 'SW') gridSwPositions.add(`${row},${col}`);
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

        // Rule 4: signal lever IDs must exist in signal.toml
        for (const sigDef of signals) {
            if (!registeredLevers.has(sigDef.lever))
                errors.push(`[${stationName}.signals] lever '${sigDef.lever}' not in signal.toml`);
        }
    }

    return errors;
}

module.exports = { validateLayout, generateDiagram };
