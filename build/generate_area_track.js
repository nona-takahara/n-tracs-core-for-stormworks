function generateAreaTrack(obj) {
    const luaBegin = `-- Generated at ${new Date().toLocaleDateString()} ${new Date().toLocaleTimeString()}
---@param s SoyaBridge
return function(s)
local ca,ct,utils=s.create_area,s.create_track,require("res.utils")
`;
    const luaEnd = "\nend\n";

    // 座標は 0.1 単位に切り捨てた整数で持つ(Lua 側で /10 して復元する)
    const vx = new Map();
    obj.vertexes.forEach((p) => {
        vx.set(p.name, { x: Math.floor(p.x * 10), z: Math.floor(p.z * 10) });
    });

    // 原点からの差分を頂点順に並べる。先頭の頂点は原点との差分(=絶対値)になる
    const packVertexes = (names) => {
        let px = 0, pz = 0;
        return names.map((k) => {
            const v = vx.get(k);
            const d = `${v.x - px},${v.z - pz}`;
            px = v.x;
            pz = v.z;
            return d;
        }).join(",");
    };

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
        createArea.push(`ca(s,${a.name},` +
            `{${packVertexes(a.vertexes)}},${a.left_vertex_inner_id + 1},` +
            `{${a.uparea.join(",")}},` +
            `{${a.downarea.join(",")}},` +
            `${a.callback || "function()end"})`);
    });

    const createTrack = Array();
    tr.forEach((t, k) => {
        createTrack.push(`ct(s,"${k}",{${t.areas.map((a) => a.name).join(",")}})`);
    });

    return luaBegin + createArea.join("\n") + "\n" + createTrack.join("\n") + luaEnd;
}

module.exports = generateAreaTrack;
