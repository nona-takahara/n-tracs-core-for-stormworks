// Web CTC の通信を受けて、連動装置の状態をログに残すだけのサーバー。挙動の確認に使う。
// 仕様は Claude Doc「ビークル／Web CTC卓 通信仕様（下書き）」の Web 卓の節。
//
// 実行方法: node tools/webctc_logger.js [ポート番号]
//   Stormworks を動かしている Windows 側で実行する（アドオンは同じコンピュータの localhost へ送るため）。
//   ポートの既定値は src/n_tracs_soyabridge/web_ctc.lua の DEFAULT_PORT と同じにする。
//
// ログは logs/webctc/ に、起動ごとに 1 ファイル作る。届いた値をすべて書くと行数が多くなるので、
// 値が変わった事実だけを書く（差分）。初めて届いた値も変化として書くので、先頭から読み直せば
// 任意の時点の状態を再現できる。
//   <時刻> s=<通し番号> c=<周回番号> <キー>=<値> ...   値が変わった事実
//   <時刻> # <出来事>                                  読み込み直し・版の変化・番号の飛び・切れた URL など
// コマンドは返さない。応答は 1 行目の印だけである。

const http = require("http");
const fs = require("fs");
const path = require("path");

const DEFAULT_PORT = 8131; // src/n_tracs_soyabridge/web_ctc.lua の DEFAULT_PORT と同じにする
const PATH = "/ntracs/v1/state";
const MARKER = "N-TRACS for Stormworks/1";
const WRAP = 1000000;
const HEADER_KEYS = new Set(["v", "b", "s", "c", "end"]);

const port = Number(process.argv[2] || DEFAULT_PORT);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error(`ポート番号が正しくありません: ${process.argv[2]}`);
    process.exit(1);
}

const logDir = path.join(__dirname, "..", "logs", "webctc");
fs.mkdirSync(logDir, { recursive: true });
const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..*$/, "").replace("T", "-");
const logFile = path.join(logDir, `${stamp}.log`);
const log = fs.createWriteStream(logFile, { flags: "a" });

const state = new Map(); // キー -> 最後に届いた値
let last = null; // { b, v, s } 直前の要求の見出し

function write(line) {
    log.write(`${new Date().toISOString()} ${line}\n`);
}

function event(text) {
    write(`# ${text}`);
    console.log(`# ${text}`);
}

function decode(s) {
    try {
        return decodeURIComponent(s);
    } catch {
        return null;
    }
}

// クエリを順序を保って読む。末尾の印がなければ、最後の組は途中で切れているかもしれないので捨てる
function parse(query) {
    const pairs = [];
    for (const part of query.split("&")) {
        if (part === "") continue;
        const i = part.indexOf("=");
        const key = decode(i < 0 ? part : part.slice(0, i));
        const value = decode(i < 0 ? "" : part.slice(i + 1));
        if (key === null || value === null) return null;
        pairs.push([key, value]);
    }
    return pairs;
}

function handle(url) {
    const q = url.indexOf("?");
    const pairs = q < 0 ? null : parse(url.slice(q + 1));
    if (!pairs) {
        event(`読めない要求: ${url.slice(0, 200)}`);
        return;
    }
    const head = Object.fromEntries(pairs.filter(([k]) => HEADER_KEYS.has(k)));
    let facts = pairs.filter(([k]) => !HEADER_KEYS.has(k));
    if (head.end !== "1") {
        event(`末尾の印がない（URL が途中で切れた疑い）: s=${head.s} 長さ=${url.length}`);
        facts = facts.slice(0, -1);
    }

    const s = Number(head.s);
    if (!last || last.b !== head.b) {
        event(`アドオンの読み込み: b=${head.b} v=${head.v}`);
    } else {
        if (last.v !== head.v) event(`版の変化: ${last.v} -> ${head.v}`);
        const expected = (last.s + 1) % WRAP;
        if (s !== expected) event(`通し番号の飛び: ${expected} を待っていたが ${head.s} が届いた`);
    }
    last = { b: head.b, v: head.v, s };

    const changed = [];
    for (const [k, v] of facts) {
        if (state.get(k) !== v) {
            state.set(k, v);
            changed.push(`${k}=${v}`);
        }
    }
    if (changed.length > 0) write(`s=${head.s} c=${head.c} ${changed.join(" ")}`);
}

function serve(host) {
    const server = http.createServer((req, res) => {
        if (req.method === "GET" && req.url.startsWith(PATH)) {
            handle(req.url);
            res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
            res.end(`${MARKER}\n`);
        } else {
            res.writeHead(404);
            res.end();
        }
    });
    server.on("error", (e) => console.error(`${host}:${port} で待ち受けられません: ${e.message}`));
    // このコンピュータの中からだけ受ける。LAN には公開しない
    server.listen(port, host, () => console.log(`待ち受け中: http://${host.includes(":") ? `[${host}]` : host}:${port}${PATH}`));
}

serve("127.0.0.1");
serve("::1");
console.log(`ログ: ${logFile}`);
event(`サーバー起動 port=${port}`);
