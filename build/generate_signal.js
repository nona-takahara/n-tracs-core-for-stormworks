function generateSignal(obj) {
    const out = [];
    const controlsMap = buildControlsMap(obj);
    out.push('local SignalRoute = require("src.n_tracs_core.switch.signal_route")');
    out.push('local SwitchRoute = require("src.n_tracs_core.signal.switch_route")');
    out.push('local RouteDirection = require("src.n_tracs_core.signal.route_direction")');
    out.push('local u = require("res.utils")');
    out.push("---@param s SoyaBridge");
    out.push("return function(s)");
    out.push("local cas,cs,sr=s.create_auto_signal,s.create_signal,SwitchRoute.new");

    Object.entries(obj).forEach(([name, data]) => {
        out.push(leverLuaCode(name, data, controlsMap[name] || []));
    });

    out.push("end");
    return out.join("\n") + "\n";
}

function leverLuaCode(name, data, controls) {
    if (data.auto === true) {
        return autoLeverLuaCode(name, data);
    }
    return absoluteLeverLuaCode(name, data, controls);
}

function absoluteLeverLuaCode(name, data, controls) {
    const switchesMake = (data.switches || []).map(
        (v) => `sr("${v.sw}",SignalRoute.${capitalize(v.t)})`
    );
    const routeLockMake = (data.route_lock || []).map((v) => `"${v}"`);
    const overrunLockMake = (data.overrun_lock || []).map((v) => `"${v}"`);
    const signalTrackMake = (data.signal_track || []).map((v) => `"${v}"`);
    const approachTrackMake = (data.approach_track || []).map((v) => `"${v}"`);
    // extra_controls: TOML外のてこ（TrafficDirectionLeverなど）を総括制御対象に追加する。
    // DFSの循環検出対象外のため、循環チェックは行われない（リーフノードであることが前提）。
    const allControls = [...new Set([...controls, ...(data.extra_controls || [])])];
    const controlsMake = allControls.map((v) => `"${v}"`);

    return "cs(s," +
        `"${name}",` +
        `"${data.start}",` +
        `"${data.destination}",` +
        `{${switchesMake.join(",")}},` +
        `{${routeLockMake.join(",")}},` +
        `{${overrunLockMake.join(",")}},` +
        `{${signalTrackMake.join(",")}},` +
        `RouteDirection.${capitalize(data.direction)},` +
        `{${approachTrackMake.join(",")}},` +
        `${data.approach_lock_time},` +
        `${data.overrun_lock_time},` +
        `{${controlsMake.join(",")}},` +
        `${data.update_callback}` +
        ")";
}

function autoLeverLuaCode(name, data) {
    const signalTrackMake = (data.signal_track || []).map((v) => `"${v}"`);
    const switchesMake = (data.switches || []).map(
        (v) => `sr("${v.sw}",SignalRoute.${capitalize(v.t)})`
    );
    return "cas(s," +
        `"${name}",` +
        `{${signalTrackMake.join(",")}},` +
        `RouteDirection.${capitalize(data.direction)},` +
        `{${switchesMake.join(",")}},` +
        `${data.update_callback}` +
        ")";
}

function capitalize(str) {
    if (!str || typeof str !== "string") {
        return str;
    }
    return str.charAt(0).toUpperCase() + str.slice(1);
}

function detectControlsCycle(controlsMap) {
    // DFS cycle detection on the controls directed graph.
    // Build-time check guarantees setInput propagation cannot loop infinitely at runtime.
    const WHITE = 0, GRAY = 1, BLACK = 2;
    const color = {};
    Object.keys(controlsMap).forEach(k => color[k] = WHITE);

    function dfs(node, path) {
        color[node] = GRAY;
        for (const neighbor of (controlsMap[node] || [])) {
            if (color[neighbor] === GRAY) {
                throw new Error(
                    `controls に循環が検出されました: ${[...path, node, neighbor].join(" -> ")}`
                );
            }
            if (color[neighbor] === WHITE) {
                dfs(neighbor, [...path, node]);
            }
        }
        color[node] = BLACK;
    }

    Object.keys(controlsMap).forEach(k => {
        if (color[k] === WHITE) dfs(k, []);
    });
}

function buildControlsMap(obj) {
    const controlsMap = {};
    Object.keys(obj).forEach((name) => {
        controlsMap[name] = [];
    });
    Object.entries(obj).forEach(([targetName, data]) => {
        const controllers = data.controlled_by || [];
        controllers.forEach((controllerName) => {
            controlsMap[controllerName] = controlsMap[controllerName] || [];
            controlsMap[controllerName].push(targetName);
        });
    });
    return controlsMap;
}

module.exports = { generateSignal, buildControlsMap, detectControlsCycle };
