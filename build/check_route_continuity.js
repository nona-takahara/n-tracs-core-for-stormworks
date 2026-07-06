// area_track.json の area 同士の隣接関係(uparea/downarea)から track 同士の
// 隣接関係を求め、signal.toml の各進路(route_lock)・信号(signal_track)が
// track を飛ばすことなく start から destination まで繋がっているかを検証する。

function buildTrackAdjacency(areaTrackObj) {
    const areas = new Map();
    areaTrackObj.areas.forEach((a) => areas.set(a.name, a));

    const downarea = new Map();
    areaTrackObj.areas.forEach((a) => {
        (a.uparea || []).forEach((upName) => {
            if (!areas.has(upName)) return;
            if (!downarea.has(upName)) downarea.set(upName, []);
            downarea.get(upName).push(a.name);
        });
    });

    const areaToTracks = new Map();
    areaTrackObj.tracks.forEach((t) => {
        t.areas.forEach((a) => {
            if (!areaToTracks.has(a.name)) areaToTracks.set(a.name, []);
            areaToTracks.get(a.name).push(t.name);
        });
    });

    const adjacency = new Map();
    const addEdge = (a, b) => {
        if (a === b) return;
        if (!adjacency.has(a)) adjacency.set(a, new Set());
        if (!adjacency.has(b)) adjacency.set(b, new Set());
        adjacency.get(a).add(b);
        adjacency.get(b).add(a);
    };

    areaTrackObj.areas.forEach((a) => {
        const myTracks = areaToTracks.get(a.name) || [];
        if (myTracks.length === 0) return;
        const neighbors = [...(a.uparea || []), ...(downarea.get(a.name) || [])];
        neighbors.forEach((nb) => {
            const nbTracks = areaToTracks.get(nb) || [];
            myTracks.forEach((mt) => nbTracks.forEach((nt) => addEdge(mt, nt)));
        });
    });

    return adjacency;
}

function isAdjacent(adjacency, a, b) {
    if (a === b) return true;
    return adjacency.has(a) && adjacency.get(a).has(b);
}

function findChainBreaks(adjacency, chain) {
    const breaks = [];
    for (let i = 0; i < chain.length - 1; i++) {
        if (!isAdjacent(adjacency, chain[i], chain[i + 1])) {
            breaks.push([chain[i], chain[i + 1]]);
        }
    }
    return breaks;
}

function checkRouteTrackContinuity(signalObj, areaTrackObj) {
    const adjacency = buildTrackAdjacency(areaTrackObj);
    const errors = [];

    Object.entries(signalObj).forEach(([name, data]) => {
        if (data.opening_lever === true) return;

        if (data.auto === true) {
            const chain = data.signal_track || [];
            findChainBreaks(adjacency, chain).forEach(([a, b]) => {
                errors.push(`[${name}] signal_track: '${a}' と '${b}' の間が隣接track一覧に見つかりません (${chain.join(" -> ")})`);
            });
            return;
        }

        if (!data.start || !data.destination) return;

        const routeChain = [data.start, ...(data.route_lock || []), data.destination];
        findChainBreaks(adjacency, routeChain).forEach(([a, b]) => {
            errors.push(`[${name}] route_lock: '${a}' と '${b}' の間が隣接track一覧に見つかりません (start=${data.start} -> destination=${data.destination}, chain=${routeChain.join(" -> ")})`);
        });

        if (data.signal_track && data.signal_track.length > 0) {
            const signalChain = [data.start, ...data.signal_track];
            findChainBreaks(adjacency, signalChain).forEach(([a, b]) => {
                errors.push(`[${name}] signal_track: '${a}' と '${b}' の間が隣接track一覧に見つかりません (start=${data.start}, chain=${signalChain.join(" -> ")})`);
            });
        }
    });

    if (errors.length > 0) {
        console.error("Route track continuity check failed:\n" + errors.join("\n"));
    } else {
        console.log("Route track continuity check: OK");
    }

    return errors;
}

module.exports = { checkRouteTrackContinuity, buildTrackAdjacency };
