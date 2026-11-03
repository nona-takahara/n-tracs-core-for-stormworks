// 合成データを本番ジェネレータで Lua に変換する。Lua の回帰テストから呼ぶ。
const generateAreaTrack = require("../../build/generate_area_track");
const definitions = `axle TRAIN
  GO: 12 34
condition ready(NAME) = nt:get_signal(NAME).HR
condition unused(NAME) = nt:get_signal(NAME).HR
`;
const send = (name, cell, watch = false) =>
    (watch ? "check gate: at=0,0 toward=1,0 over=0km/h hold=0.2s\n" : "")
    + `set\n  row ~ ALL: ${cell}\nready(${name}): row`;
const part = (text) => ({ track: "TRACK", kind_id: "TRAIN", send: text });
const custom = "function(self,nt,dt) s.customCalls=(s.customCalls or 0)+1; return dt end";
const specs = [
    { send_parts: [part(send("C", "GO"))] },
    { send_parts: [part(send("D", "GO", true))] },
    { send_parts: [part(send("NO_SEND", "-").replace("ready(", "unused("))] },
    { send_parts: [part(send("NO_SEND_WATCH", "-", true).replace("ready(", "unused("))] },
    { callback: custom, send_parts: [part("--!lua\nanything")] },
    { callback: custom, send_parts: [part(send("C", "GO")), part(send("D", "GO"))] },
    { callback: custom },
    // nil 行も条件に一致すれば後続の送信を抑止する。
    { send_parts: [part("set\n  stop ~ ALL: -\n  go ~ ALL: GO\nready(STOP): stop\nready(GO): go")] },
    // nil 行の子が選ばれると、親の送信を抑止する。
    { send_parts: [part("set\n  go ~ ALL: GO\n  stop ~ ALL: -\nready(PARENT): go\n  ready(CHILD): stop")] },
    // 子の行を省略した場合、親の行を継承する。
    { send_parts: [part("set\n  go ~ ALL: GO\nready(PARENT): go\n  ready(CHILD):")] },
    // 変換途中で未対応の条件が見つかった場合も元の Lua に戻す。
    { callback: custom, send_parts: [part("set\n  row ~ ALL: GO\nready(C): row\nunknown(): row")] },
];
const obj = {
    send_definitions: definitions, geometry_half_width: 4,
    vertexes: [{ name: 1, x: 0, z: 0 }, { name: 2, x: 1, z: 0 }, { name: 3, x: 0, z: 1 }],
    areas: specs.map((spec, i) => ({
        name: i + 1, vertexes: [1, 2, 3], left_vertex_inner_id: 0, uparea: [],
        callback: "function()end", ...spec,
    })),
    tracks: [{ name: "TRACK", areas: specs.map((_, i) => ({ name: i + 1 })) }],
};
const noDefinitions = structuredClone(obj);
delete noDefinitions.send_definitions;
noDefinitions.areas = [{ ...noDefinitions.areas[0], callback: custom }];
noDefinitions.tracks[0].areas = [{ name: 1 }];
const wrap = (text) => `(function()\n${text}\nend)()`;
process.stdout.write(`return { compact=${wrap(generateAreaTrack(obj))}, no_definitions=${wrap(generateAreaTrack(noDefinitions))} }`);
