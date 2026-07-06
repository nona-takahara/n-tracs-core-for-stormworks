# テストケースの書き方

実地テスト（Stormworks上での実運用）で見つかったバグを、ゲームを介さずに
Lua単体で再現・固定化するためのしくみです。ロジック層(`src/n_tracs_core`)は
`server` などのStormworks APIに依存していないため、`lua` コマンドだけで
本番と同じ信号・軌道回路の組み合わせを動かせます。

## 準備

```sh
npm install       # toml パッケージなどdevDependenciesの取得(初回のみ)
node tests/gen_res.js
```

`tests/gen_res.js` は `res/area_track.json` / `res/signal.toml`（実際の運用データ）
から `res/area_track.lua` / `res/signal.lua` を生成します。中身は `npm run build`
と同じジェネレータを使っているため本番ビルドと同一です。圧縮や `dist/` への配置は
行わないぶん高速です。生成物なので `.gitignore` 済み・コミット不要ですが、
`res/area_track.json` や `res/signal.toml` を編集した後は再実行してください。

## 実行

1ファイルだけ実行する場合:

```sh
lua tests/repro_template.lua
```

失敗すると `os.exit(1)` するので、そのままCIの合否判定にも使えます。

`tests/repro_*.lua` を全部まとめて実行してサマリを見たい場合:

```sh
npm test
```

`pretest` で `tests/gen_res.js` が自動実行されてから、`tests/run_all.js` が
`tests/repro_*.lua` を1本ずつ別プロセスとして実行し、最後に

```
[PASS] tests/repro_template.lua
[FAIL] tests/repro_xxxx.lua
    [NG] cycle3: ... (expected=true, actual=false)
    1 / 5 件のアサーションが失敗しました
============================================================
4 / 5 件のテストファイルが成功しました
```

のような一覧を表示します。失敗したファイルの `[NG]` 行だけを抜き出して表示
するので、まとめて実行してもどこが壊れているかすぐわかります。1件でも失敗
すれば非0終了するので、CIにもそのまま組み込めます。

## 書き方のコツ

- **本番データをそのまま読み込む。** `tests/harness.lua` の `new_production_sw()` は
  `res/area_track.lua` / `res/signal.lua` / `res/switch.lua` / `res/signal_alias.lua`
  を script.lua と同じ順序でロードします。信号機・軌道回路の名前は本番と同じもの
  （`NHB5R`、`NHB5RT` など）がそのまま使えるので、実地テストの状況をID単位で
  忠実に再現できます。ただし本当に必要な範囲だけをシナリオに登場させ、
  無関係な信号機・進路には触れないようにする（＝関与する分だけ最小化する）と、
  assertが読みやすくなり、Claudeに渡したときの原因特定も速くなります。
- **在線は手動で切り替える。** 実車の代わりに `short` という
  `table<track_id, boolean>` を自分で書き換え、`h.tick(sw, short)` に渡します。
  `SoyaBridge:before_process()` は実車のaxle位置から在線を計算するため、車両を
  スポーンさせないテストではそのまま使えません（`test.lua` と同じ考え方です）。
- **1回の `tick()` が1論理サイクル。** `script.lua` の `onTick` は6tickごとに
  `before_process` → `process(6)` を1回実行する構成になっています
  （`Phase = (Phase + 1) % 6` を参照）。`h.tick()` はこれ1回分に相当するので、
  「6サイクルごとに在線を切り替える」＝「`h.tick()` を呼ぶたびに `short` を
  更新する」と考えて問題ありません。
- **assertはソフトアサートで積み上げる。** `h.new_checker()` が返す `Checker` の
  `check(label, actual, expected)` は失敗しても止まらず記録だけして継続します。
  1件失敗した時点で打ち切られると、後続のサイクルで状態がどう壊れていくのか
  わからなくなるため、時系列で複数の時点を確認するテストとは相性が悪いです。
  最後に `report()` を呼ぶと集計し、1件でも失敗していれば非0終了します。
- **`aspect` は1サイクル遅れる。** `Signal:process()` は次の現示を `nextAspect` に
  貯めるだけで、実際に `aspect` へ反映されるのは次の `before_process()` 時です。
  「このサイクルでHRが扛上したのに、まだ`aspect`が0のまま」は多くの場合バグでは
  なく仕様なので、assertを書く前に一度 `print` で実際の値の推移を確認することを
  おすすめします。
- **失敗する状態のまま提出してよい。** 目的はバグの固定化なので、現状のコードで
  `check()` が `[NG]` になるテストをそのまま用意し、「このテストが通るように直して
  ほしい」という形でClaudeに渡すのが最も伝わりやすいです。

## ファイル構成

- `tests/gen_res.js` — 本番データから `res/area_track.lua` / `res/signal.lua` を生成
- `tests/harness.lua` — `new_production_sw()` / `tick()` / `new_checker()` を提供
- `tests/repro_template.lua` — 上記を使った最小のひな形（コピーして使ってください）
- `tests/run_all.js` — `tests/repro_*.lua` を一括実行してサマリを表示する（`npm test`）

## 既知の注意点

リポジトリ直下の `test.lua` は `WAK1R` / `WAK1RT` という信号機・軌道回路を参照して
いますが、現在の `res/signal.toml` / `res/area_track.json` にはこれらは存在しません
（路線データが更新され、参照先が失われたと見られます）。そのまま実行はできないため、
新しくテストを書く際は本ディレクトリのひな形を使うか、`res/signal.toml` に実在する
信号機名で組み立ててください。
