// 軌道回路の長さ[m]を、storm-n-tracs-editor-line のプロジェクトとセグメントDBから求め、tests/heavy/track_lengths.lua を作る。
// 実行(リポジトリルートから): node tests/heavy/gen_track_lengths.js [プロジェクトのJSON] [--report]
// 既定のプロジェクトは ../storm-n-tracs-editor-line/examples/soya-express.project.json (読むだけで、書き換えない)。
//
// 長さの決め方(キロ程の決め方は docs/project-format.md、正本は Rust の mileage.rs。ここは同じ規則を JavaScript で持つ):
//   - セグメントの実長は、折れ線の xz の距離の和。
//   - セグメントの端のキロ程: 値、+/-(反対の端に実長を足す・引く)、名前の引き継ぎ、`+#L@名前` などの端指定の引き継ぎ。
//   - 区間の位置は、キロ程なら両端のキロ程の間を実長へ比例で換算し、`n#L`/`n#R` ならそのセグメントの端からの長さ。
//   - 軌道回路の区間は、端の位置が同じ点でつながるものを一つの木とみなし、その最長の道(直径)を長さにする。
//     分岐を含むときは、どの枝を通るかが路線によるので、最長の枝を通る長さ(推論)になる。分岐を含む軌道回路は、出力に印を付ける。
//   - 木が複数に分かれる軌道回路(交差する線路をまたぐ軌道回路など)は、最長の木の道を長さにする。
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const report = process.argv.includes("--report");
const projectPath = path.resolve(args[0] || path.join(__dirname, "..", "..", "..", "storm-n-tracs-editor-line", "examples", "soya-express.project.json"));
const project = JSON.parse(fs.readFileSync(projectPath, "utf8"));
const segmentsPath = path.resolve(path.dirname(projectPath), project.segment_db);
const db = JSON.parse(fs.readFileSync(segmentsPath, "utf8"));

const nodes = new Map(db.raw_nodes.map((n) => [n.id, n.point]));
const edges = new Map(db.raw_edges.map((e) => [e.id, e]));
const dist = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);

// セグメント: 物理の始端・終端のノードと実長
const segs = new Map();
for (const s of db.segments) {
  let first = null;
  let last = null;
  let len = 0;
  for (const ed of s.edges) {
    const e = edges.get(ed.edge_id);
    const a = ed.direction === "reverse" ? e.end_node_id : e.start_node_id;
    const b = ed.direction === "reverse" ? e.start_node_id : e.end_node_id;
    if (first === null) first = a;
    last = b;
    len += dist(nodes.get(a), nodes.get(b));
  }
  segs.set(s.id, { ...s, startNode: first, endNode: last, len, kp: {} });
}
const byName = new Map([...segs.values()].map((s) => [s.name, s]));

const parseValue = (t) => {
  const m = /^(-?\d+)k(\d+(?:\.\d+)?)$/.exec(t);
  if (m) return Number(m[1]) * 1000 + Number(m[2]);
  return /^-?\d+(?:\.\d+)?$/.test(t.replace(/,/g, "")) ? Number(t.replace(/,/g, "")) : null;
};
const otherEnd = (e) => (e === "start" ? "end" : "start");
const nodeOf = (s, e) => (e === "start" ? s.startNode : s.endNode);
// L(up側)の端が、物理の始端か終端か
const physOfSide = (s, side) => (side === "L" ? s.up_end : otherEnd(s.up_end));

const visiting = new Set();
function kpAt(s, e) {
  if (s.kp[e] !== undefined) return s.kp[e];
  const key = s.id + e;
  if (visiting.has(key)) throw new Error(`キロ程の循環: ${s.name}`);
  visiting.add(key);
  const t = String(s.mileage[e]).trim();
  let v;
  if (t === "+" || t === "-") {
    v = kpAt(s, otherEnd(e)) + (t === "+" ? s.len : -s.len);
  } else if (parseValue(t) !== null) {
    v = parseValue(t);
  } else if (t.includes("@")) {
    const m = /^([+-]?)(\d*(?:\.\d+)?)#([LR])@(.+)$/.exec(t);
    if (!m) throw new Error(`解釈できないキロ程: ${t}`);
    const o = byName.get(m[4]);
    const oe = physOfSide(o, m[3]);
    const d = dist(nodes.get(nodeOf(o, oe)), nodes.get(nodeOf(s, e)));
    v = kpAt(o, oe) + (m[1] === "+" ? d : m[1] === "-" ? -d : 0);
  } else {
    const o = byName.get(t);
    if (!o) throw new Error(`不明な引き継ぎ先: ${t}`);
    const me = nodeOf(s, e);
    let oe = ["start", "end"].find((x) => nodeOf(o, x) === me);
    if (!oe) {
      const p = nodes.get(me);
      oe = dist(p, nodes.get(o.startNode)) <= dist(p, nodes.get(o.endNode)) ? "start" : "end";
    }
    v = kpAt(o, oe);
  }
  visiting.delete(key);
  s.kp[e] = v;
  return v;
}

// 区間の端の位置 -> セグメントの物理始端からの距離[m]
function posOf(s, t) {
  const str = String(t);
  const m = /^(\d*(?:\.\d+)?)#([LR])$/.exec(str);
  if (m) {
    const fromPhys = physOfSide(s, m[2]);
    return fromPhys === "start" ? Number(m[1]) : s.len - Number(m[1]);
  }
  const k = parseValue(str);
  if (k === null) throw new Error(`解釈できない位置: ${str}`);
  const k0 = kpAt(s, "start");
  const k1 = kpAt(s, "end");
  return ((k - k0) / (k1 - k0)) * s.len;
}

// 位置が端から1 mm以内ならその端のノード、そうでなければ区間内の点
function vertexOf(s, p) {
  if (Math.abs(p) <= 0.001) return s.startNode;
  if (Math.abs(p - s.len) <= 0.001) return s.endNode;
  return `${s.id}@${(Math.round(p * 10) / 10).toFixed(1)}`; // 0.1 m にそろえて、同じ点でつながる区間を同じ頂点にする
}

function treeDiameter(adj, start) {
  const far = (src) => {
    const d = new Map([[src, 0]]);
    const q = [src];
    let best = src;
    while (q.length) {
      const u = q.shift();
      for (const [v, w] of adj.get(u)) {
        if (!d.has(v)) {
          d.set(v, d.get(u) + w);
          q.push(v);
          if (d.get(v) > d.get(best)) best = v;
        }
      }
    }
    return { best, d, seen: d };
  };
  const a = far(start);
  const b = far(a.best);
  return { len: b.d.get(b.best), seen: a.seen };
}

// 別のセグメントの端が 1.5 m 以内に並ぶ(キロ程の継ぎ目の隙間)ときは、同じ点としてつなぐ
const SNAP = 1.5;
const rootOf = new Map();
const find = (v) => {
  while (rootOf.has(v) && rootOf.get(v) !== v) v = rootOf.get(v);
  return v;
};
const snapNodes = [...nodes.keys()];
function snapKey(v) {
  if (!nodes.has(v)) return v;
  return find(v);
}
{
  // 軌道回路の区間が使う端のノードだけを対象にする
  const used = new Set();
  for (const t of project.tracks) {
    for (const st of t.sub_tracks) {
      for (const sec of st.sections) {
        const s = segs.get(sec.segment_id);
        used.add(s.startNode);
        used.add(s.endNode);
      }
    }
  }
  const list = [...used];
  for (const v of list) rootOf.set(v, v);
  for (let i = 0; i < list.length; i++) {
    for (let j = i + 1; j < list.length; j++) {
      if (dist(nodes.get(list[i]), nodes.get(list[j])) <= SNAP) {
        const a = find(list[i]);
        const b = find(list[j]);
        if (a !== b) rootOf.set(a, b);
      }
    }
  }
}

const result = new Map();
for (const t of project.tracks) {
  const adj = new Map();
  const add = (u, v, w) => {
    if (!adj.has(u)) adj.set(u, []);
    if (!adj.has(v)) adj.set(v, []);
    adj.get(u).push([v, w]);
    adj.get(v).push([u, w]);
  };
  let total = 0;
  let nsec = 0;
  for (const st of t.sub_tracks) {
    for (const sec of st.sections) {
      const s = segs.get(sec.segment_id);
      let a, b;
      try {
        a = posOf(s, sec.start);
        b = posOf(s, sec.end);
      } catch (err) {
        console.error(`警告: ${t.id}: ${err.message}`);
        continue;
      }
      const w = Math.abs(b - a);
      total += w;
      nsec += 1;
      add(snapKey(vertexOf(s, a)), snapKey(vertexOf(s, b)), w);
    }
  }
  const seen = new Set();
  let sum = 0;
  let trees = 0;
  let branch = false;
  for (const u of adj.keys()) {
    if (seen.has(u)) continue;
    const dm = treeDiameter(adj, u);
    for (const v of dm.seen.keys()) seen.add(v);
    sum = Math.max(sum, dm.len);
    trees += 1;
    for (const v of dm.seen.keys()) if (adj.get(v).length >= 3) branch = true;
  }
  result.set(t.id, { len: sum, total, trees, branch, sections: nsec });
}

// 出力
const rows = [...result.entries()].sort((x, y) => (x[0] < y[0] ? -1 : 1));
if (report) {
  const old = fs.existsSync(path.join(__dirname, "track_lengths.lua")) ? fs.readFileSync(path.join(__dirname, "track_lengths.lua"), "utf8") : "";
  const est = new Map([...old.matchAll(/^\s*([A-Za-z0-9_]+) = ([0-9.]+),/gm)].map((m) => [m[1], Number(m[2])]));
  for (const [id, r] of rows) {
    const e = est.get(id);
    console.log(`${id.padEnd(10)} ${r.len.toFixed(1).padStart(8)} (和 ${r.total.toFixed(1).padStart(8)}${r.branch ? " 分岐" : ""}${r.trees > 1 ? ` 木${r.trees}` : ""})` + (e === undefined ? "" : `  概算 ${e.toFixed(1).padStart(8)}  比 ${(r.len / e).toFixed(2)}`));
  }
  process.exit(0);
}
const lines = [
  "-- 軌道回路の長さ[m]。tests/heavy/gen_track_lengths.js が storm-n-tracs-editor-line のプロジェクトとセグメントDBから作る。直接編集しない。",
  "-- ARCのシミュレーション(tests/heavy/explore_arc.lua、tests/heavy/measure_start_points.lua)で列車の軸の位置を決めるために使う。",
  "-- 分岐を含む軌道回路は、最長の枝を通る長さ(どの枝を通るかは路線によるため、推論)。印は `-- 分岐` の行。",
  "return {",
];
for (const [id, r] of rows) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(id)) continue;
  lines.push(`    ${id} = ${r.len.toFixed(1)},${r.branch ? " -- 分岐" : ""}`);
}
lines.push("}", "");
fs.writeFileSync(path.join(__dirname, "track_lengths.lua"), lines.join("\r\n"));
console.log(`tests/heavy/track_lengths.lua を書きました (${rows.length} 本)`);
