function generateAreaTrack(obj) {
    const luaBegin = `-- Generated at ${new Date().toLocaleDateString()} ${new Date().toLocaleTimeString()}
---@param s SoyaBridge
return function(s)
local ca,ct,utils=s.create_area,s.create_track,require("res.utils")
`;
    const luaEnd = "\nend\n";

    const vx = new Map();
    obj.vertexes.forEach((p) => {
        vx.set(p.name, { x: Math.floor(p.x * 10) / 10, z: Math.floor(p.z * 10) / 10 });
    });

    const ar = new Map();
    obj.areas.forEach((p) => {
        p.downarea = Array();
        ar.set(p.name, p);
    });
    ar.forEach((v) => {
        v.uparea.forEach((k2) => {
            const p = ar.get(k2);
            if (p) {
                p.downarea.push(v.name);
            }
        });
    });

    const tr = new Map();
    obj.tracks.forEach((p) => {
        tr.set(p.name, p);
    });

    const createArea = Array();
    ar.forEach((a) => {
        createArea.push(`ca(s,${a.name.replace("Area_", "")},` +
            `{${a.vertexes.map((k) => {
                const v = vx.get(k);
                return `{x=${v.x},z=${v.z}}`;
            }).join(",")}},${a.left_vertex_inner_id + 1},` +
            `{${a.uparea.map((s) => s.replace("Area_", "")).join(",")}},` +
            `{${a.downarea.map((s) => s.replace("Area_", "")).join(",")}},` +
            `${a.callback || "function()end"})`);
    });

    const createTrack = Array();
    tr.forEach((t, k) => {
        createTrack.push(`ct(s,"${k}",{${t.areas.map((a) => a.name.replace("Area_", "")).join(",")}})`);
    });

    return luaBegin + createArea.join("\n") + "\n" + createTrack.join("\n") + luaEnd;
}

module.exports = generateAreaTrack;
