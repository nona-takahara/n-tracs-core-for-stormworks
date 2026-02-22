function generateSignal(obj) {
    const out = [];
    out.push('local SignalRoute = require("src.n_tracs_core.switch.signal_route")');
    out.push('local SwitchRoute = require("src.n_tracs_core.signal.switch_route")');
    out.push('local RouteDirection = require("src.n_tracs_core.signal.route_direction")');
    out.push("---@param s SoyaBridge");
    out.push("return function(s)");
    out.push("local cas,cs,sr=s.create_auto_signal,s.create_signal,SwitchRoute.new");

    Object.entries(obj).forEach(([name, data]) => {
        out.push(leverLuaCode(name, data));
    });

    out.push("end");
    return out.join("\n") + "\n";
}

function leverLuaCode(name, data) {
    if (data.auto === true) {
        return autoLeverLuaCode(name, data);
    }
    return absoluteLeverLuaCode(name, data);
}

function absoluteLeverLuaCode(name, data) {
    const switchesMake = (data.switches || []).map(
        (v) => `sr("${v.sw}",SignalRoute.${capitalize(v.t)})`
    );
    const routeLockMake = (data.route_lock || []).map((v) => `"${v}"`);
    const overrunLockMake = (data.overrun_lock || []).map((v) => `"${v}"`);
    const signalTrackMake = (data.signal_track || []).map((v) => `"${v}"`);
    const approachTrackMake = (data.approach_track || []).map((v) => `"${v}"`);

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
        `${data.update_callback}` +
        ")";
}

function autoLeverLuaCode(name, data) {
    const signalTrackMake = (data.signal_track || []).map((v) => `"${v}"`);
    return "cas(s," +
        `"${name}",` +
        `{${signalTrackMake.join(",")}},` +
        `RouteDirection.${capitalize(data.direction)},` +
        `${data.update_callback}` +
        ")";
}

function capitalize(str) {
    if (!str || typeof str !== "string") {
        return str;
    }
    return str.charAt(0).toUpperCase() + str.slice(1);
}

module.exports = generateSignal;
