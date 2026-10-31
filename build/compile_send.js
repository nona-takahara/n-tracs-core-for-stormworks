// エディタが Area ごとに書き出す送信データの記述(send_parts の send)を、
// ブロックの木を組み立てる短い呼び出しにコンパイルする。
// 組み立てに使う関数は src/n_tracs_soyabridge/send_rule.lua にある。
// 記述の文法はエディタの docs/axle-send-dsl.md と同じで、set だけは sub track を解決済みの1列になっている。
//
// 記述の検査はエディタが書いた時点で行うので、ここでは繰り返さない。
// タイマー、Lua の区画は扱わない。それらを含む記述は null を返し、呼び出し側は Area の callback をそのまま使う。

class Unsupported extends Error {}

function stripComment(line) {
    return line.replace(/(^|\s)--.*$/, "").trimEnd();
}

function contentLines(text) {
    return text.split("\n").map(stripComment).filter((l) => l.trim());
}

const lua = (name) => `"${name}"`;

function parseDefinitions(text) {
    const defs = { axles: new Map(), aspects: new Map(), conditions: new Map() };
    let table = null;
    for (const line of contentLines(text)) {
        let m;
        if ((m = line.match(/^axle\s+(\S+)$/))) {
            table = new Map();
            defs.axles.set(m[1], table);
        } else if (/^aspect$/.test(line)) {
            table = defs.aspects;
        } else if ((m = line.match(/^condition\s+([^\s(]+)\((NAME)?\)\s*=\s*(.*)$/))) {
            table = null;
            defs.conditions.set(m[1], { named: !!m[2], expr: m[3] });
        } else if ((m = line.match(/^\s+(\S+):\s*(.*)$/)) && table && m[1] !== "sends") {
            const values = m[2].trim().split(/\s+/);
            table.set(m[1], table === defs.aspects ? values[0] : values);
        }
    }
    return defs;
}

// check 名前: 項目=値 ... を読む。hold は必ず要る。
// at、toward、over は、照査点を持つ Area の記述にだけある(エディタが座標へ解決した形: at=x,z toward=x,z over=25km/h)
function parseCheck(line) {
    const m = line.match(/^check\s+(\S+):\s*(.*)$/);
    if (!m) throw new Unsupported();
    const items = new Map();
    for (const item of m[2].trim().split(/\s+/)) {
        const kv = item.match(/^(at|toward|over|hold)=(\S+)$/);
        if (!kv || items.has(kv[1])) throw new Unsupported();
        items.set(kv[1], kv[2]);
    }
    const hold = (items.get("hold") || "").match(/^([0-9.]+)s$/);
    if (!hold || !(Number(hold[1]) > 0)) throw new Unsupported();
    const check = { name: m[1], hold: Number(hold[1]) * 60, watch: null };
    if (items.size > 1) {
        const pair = (text) => {
            const v = (text || "").split(",").map(Number);
            if (v.length !== 2 || v.some((n) => !Number.isFinite(n))) throw new Unsupported();
            return v;
        };
        const over = (items.get("over") || "").match(/^([0-9.e+-]+)km\/h$/);
        if (items.size !== 4 || !over) throw new Unsupported();
        check.watch = { point: pair(items.get("at")), toward: pair(items.get("toward")), over: Number(over[1]) / 3.6 };
    }
    return check;
}

// 送る行の表と、ブロックの木にする
function parseSend(text) {
    if (/^--!/m.test(text)) throw new Unsupported();
    const rows = new Map();
    const checks = [];
    const root = { children: [] };
    const stack = [{ depth: -1, block: root }];
    let inSet = false;
    for (const line of contentLines(text)) {
        let m;
        if (/^set$/.test(line)) {
            inSet = true;
        } else if (/^check\s/.test(line)) {
            inSet = false;
            checks.push(parseCheck(line));
        } else if (inSet && (m = line.match(/^\s+(\S+)\s*~\s*(L|R|ALL):\s*(\S+)$/))) {
            rows.set(m[1], { dest: m[2], cell: m[3] });
        } else if ((m = line.match(/^( *)(.*):\s*(\S+)?\s*(\/through)?$/))) {
            inSet = false;
            if (m[3] === "/through") {
                m[4] = m[3];
                m[3] = undefined;
            }
            const depth = m[1].length / 2;
            while (stack[stack.length - 1].depth >= depth) stack.pop();
            const block = { condition: m[2].trim(), row: m[3] || null, through: !!m[4], children: [] };
            stack[stack.length - 1].block.children.push(block);
            stack.push({ depth, block });
        } else {
            throw new Unsupported(); // count、stay など
        }
    }
    return { rows, checks, blocks: root.children };
}

const COMPARE = /^([^\s(]+)\(([^)]*)\)(?:\s*(==|!=|>=|<=|>|<)\s*(\S+))?$/;

class SendCompiler {
    /**
     * @param {string} definitions send_definitions の文字列
     * @param {Map<string, string>} rows 送る行のキー → 変数名。使う行を足す
     * @param {number} [halfWidth] Area の半幅(m)。照査点の線の長さに使う
     */
    constructor(definitions, rows, halfWidth) {
        this.halfWidth = halfWidth;
        this.defs = parseDefinitions(definitions);
        this.rows = rows;
        this.words = new Map();
    }

    // 条件の語1つを Lua の関数1つにする。同じ語は1つの関数を共有する
    word(name, op) {
        const key = `${name} ${op || ""}`;
        if (!this.words.has(key)) {
            const def = this.defs.conditions.get(name);
            if (!def) throw new Unsupported();
            const variable = `w${this.words.size}`;
            const luaOp = op === "!=" ? "~=" : op;
            let body;
            if (op && def.named) body = `U(function(NAME,TRACK,VALUE) return (${def.expr}) ${luaOp} VALUE end)`;
            else if (def.named) body = `A(function(NAME,TRACK) return ${def.expr} end)`;
            else if (!op) body = `function(TRACK) return ${def.expr} end`;
            else throw new Unsupported();
            this.words.set(key, { variable, body });
        }
        return this.words.get(key).variable;
    }

    // 照査点のどれかが作動中か。Track のタイマー check:<番号> が、始まっていて hold を過ぎていない間
    tripped(names, send) {
        if (!names.length) throw new Unsupported();
        const args = names.map((name) => {
            const index = send.checks.findIndex((c) => c.name === name);
            if (index < 0) throw new Unsupported();
            return `${lua(`check:${index}`)},${send.checks[index].hold}`;
        });
        return `K(${args.join(",")})`;
    }

    condition(text, send) {
        const m = text.match(COMPARE);
        if (!m) throw new Unsupported(); // タイマーの比較など
        if (m[1] === "tripped" && !this.defs.conditions.has("tripped")) {
            if (m[3]) throw new Unsupported();
            return this.tripped(m[2].trim().split(/\s+/).filter(Boolean), send);
        }
        const def = this.defs.conditions.get(m[1]);
        const names = m[2].trim() ? m[2].trim().split(/\s+/) : [];
        if (!def || def.named !== names.length > 0) throw new Unsupported();
        const fn = this.word(m[1], m[3]);
        const quoted = names.map(lua);
        if (m[3]) {
            const value = this.defs.aspects.get(m[4]);
            if (value === undefined) throw new Unsupported();
            return `${fn}(${[value, ...quoted].join(",")})`;
        }
        return def.named ? `${fn}(${quoted.join(",")})` : fn;
    }

    row(send, axle, name) {
        const row = name && send.rows.get(name);
        if (!row || row.cell === "-") return "nil";
        const values = axle && axle.get(row.cell);
        if (!values) throw new Unsupported();
        const key = `${{ L: "L", R: "R", ALL: "Z" }[row.dest]}{${values.join(",")}}`;
        if (!this.rows.has(key)) this.rows.set(key, `q${this.rows.size}`);
        return this.rows.get(key);
    }

    block(block, send, axle, inherited) {
        const name = block.row || inherited;
        const args = [this.condition(block.condition, send), this.row(send, axle, name)];
        block.children.forEach((c) => args.push(this.block(c, send, axle, name)));
        return `${block.through ? "P" : "B"}(${args.join(",")})`;
    }

    // 照査点を軸が横切るのを見て、タイマーを始め直す関数
    watcher(track, check, index) {
        const w = check.watch;
        if (!w) return null;
        if (!(this.halfWidth > 0)) throw new Unsupported();
        const args = [lua(track), lua(`check:${index}`), check.hold, ...w.point, ...w.toward, w.over, this.halfWidth];
        return `W(${args.join(",")})`;
    }

    /**
     * @param {{ track: string, kind_id: string, send?: string }} part send_parts の要素
     * @returns {string | null} callback の式。扱えない記述なら null
     */
    compile(part) {
        if (typeof part.send !== "string") return null;
        const before = { rows: new Map(this.rows), words: new Map(this.words) };
        try {
            const send = parseSend(part.send);
            const axle = this.defs.axles.get(part.kind_id);
            const blocks = send.blocks.map((b) => this.block(b, send, axle, null));
            const watchers = send.checks.map((c, i) => this.watcher(part.track, c, i)).filter(Boolean);
            if (!watchers.length) return `C(${[lua(part.track), ...blocks].join(",")})`;
            return `D(${[lua(part.track), `{${watchers.join(",")}}`, ...blocks].join(",")})`;
        } catch (e) {
            if (!(e instanceof Unsupported)) throw e;
            this.rows.clear();
            before.rows.forEach((v, k) => this.rows.set(k, v));
            this.words = before.words;
            return null;
        }
    }

    // 使った条件の語の定義。callback より前に置く
    wordDefinitions() {
        return [...this.words.values()].map((w) => `local ${w.variable}=${w.body}`);
    }
}

module.exports = SendCompiler;
