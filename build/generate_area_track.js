const SendCompiler = require("./compile_send");

/**
 * @param {object} obj area_track.json の中身
 * @param {{ plain?: boolean }} [options] plain のときは callback を元の Lua のまま書き出す(比較テスト用)
 */
function generateAreaTrack(obj, options = {}) {
    const plain = !!options.plain;
    // 同じ callback は1つの関数を共有する。ローカル変数の数の上限(200)に当たらないよう、テーブルに置く
    const rows = new Map();
    const shared = new Map();
    const sharedDefs = [];
    // コンパイルできない記述の Area は、エディタが書き出した callback の Lua をそのまま使う
    const compiler = obj.send_definitions ? new SendCompiler(obj.send_definitions, rows, obj.geometry_half_width) : null;
    const compiled = (area) => {
        const parts = area.send_parts;
        return compiler && parts && parts.length === 1 ? compiler.compile(parts[0]) : null;
    };
    const callbackOf = (area) => {
        const text = area.callback;
        if (!text) return "function()end";
        if (plain) return text;
        const body = compiled(area) || text;
        if (!shared.has(body)) {
            shared.set(body, `F[${shared.size + 1}]`);
            sharedDefs.push(`${shared.get(body)}=${body}`);
        }
        return shared.get(body);
    };

    const luaHeader = `-- Generated at ${new Date().toLocaleDateString()} ${new Date().toLocaleTimeString()}
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
            `${callbackOf(a)})`);
    });

    const createTrack = Array();
    tr.forEach((t, k) => {
        createTrack.push(`ct(s,"${k}",{${t.areas.map((a) => a.name).join(",")}})`);
    });

    const rowDefs = [...rows].map(([key, name]) => `local ${name}=${key}`);
    const luaRules = plain ? "" : [
        `local B,P,C,R,L,Z,A,U,K,W,D=require("src.n_tracs_soyabridge.send_rule")(s)`,
        "local nt,F=s.nt,{}",
        ...rowDefs,
        ...(compiler ? compiler.wordDefinitions() : []),
        ...sharedDefs,
    ].join("\n") + "\n";
    return luaHeader + luaRules + createArea.join("\n") + "\n" + createTrack.join("\n") + luaEnd;
}

module.exports = generateAreaTrack;
