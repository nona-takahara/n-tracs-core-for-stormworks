# テストケースの書き方

実地テスト（Stormworks上での実運用）で見つかったバグを、ゲームを介さずに
Lua単体で再現・固定化するためのしくみです。ロジック層(`src/n_tracs_core`)は
`server` などのStormworks APIに依存していないため、`lua` コマンドだけで
本番と同じ信号・軌道回路の組み合わせを動かせます。

## 準備

```sh
pnpm install      # toml パッケージなどdevDependenciesの取得(初回のみ)
node tests/gen_res.js
```

`tests/gen_res.js` は `res/area_track.json` / `res/signal.toml`（実際の運用データ）
から `res/area_track.lua` / `res/signal.lua` を生成します。中身は `pnpm build`
と同じジェネレータを使っているため本番ビルドと同一です。圧縮や `dist/` への配置は
行わないぶん高速です。生成物なので `.gitignore` 済み・コミット不要ですが、
`res/area_track.json` や `res/signal.toml` を編集した後は再実行してください。

## 実行

1ファイルだけ実行する場合:

```sh
lua tests/repro_arc.lua
```

失敗すると `os.exit(1)` するので、そのままCIの合否判定にも使えます。

`tests/repro_*.lua` を全部まとめて実行してサマリを見たい場合:

```sh
pnpm test
```

`pretest` で `tests/gen_res.js` が自動実行されてから、`tests/run_all.js` が
`tests/repro_*.lua` を1本ずつ別プロセスとして実行し、最後に

```
[PASS] tests/repro_arc.lua
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
- `tests/template.lua` — 上記を使った最小のひな形。`tests/repro_*.lua` としてコピーして使う（ひな形自体は `pnpm test` で実行しない）
- `tests/run_all.js` — `tests/repro_*.lua` を一括実行してサマリを表示する（`pnpm test`）
- `tests/heavy/` — 時間のかかるテストと、外部ツールの検証

## テストの層

| 層 | 実行 | 確かめること |
|---|---|---|
| ビルド内チェック | `pnpm build` | 手作業で作って渡すデータの誤り |
| 軽いテスト | `pnpm test` | ロジックとツールチェーンの誤り |
| フルテスト | `pnpm test:full` | 軽いテストに加えて、minify 後のスクリプトと ARC の総当たり |

時間のかかるテストは、たいてい疑い深すぎるので、`tests/heavy/` に分けて、本当に必要なときだけ実行する。外部ツールの検証を自動で実行するのは、フルテストのときだけである。`tests/heavy/sim_ats.lua` と `tests/heavy/measure_start_points.lua` は合否を出さない道具で、フルテストにも含めない。

## ARC のシミュレーション

ARC の規則は `docs/arc.md`、前提と確定した事項は Docs「宗弥急行 ARC 制御仕様」の末尾にある。

| ファイル | 役割 | 実行 |
|---|---|---|
| `tests/repro_arc.lua` | ARC の規則の確認（`pnpm test`） | `lua tests/repro_arc.lua` |
| `tests/heavy/explore_arc.lua` | 複数列車を動かし、動けなくなる組み合わせ（警報あり・なし）を探す運転シミュレーション。列車は現示に従って一定速度（既定 4 m/周期＝約 144 km/h）で進む。警報なしで固まるか、上限に達すると失敗する | `lua tests/heavy/explore_arc.lua 駅` |
| `tests/heavy/measure_start_points.lua` | 1 本の列車を流し、信号の現示から制御開始点を決める現示シミュレーション。110 km/h、実効視認距離＝制動距離＋10 秒 | `lua tests/heavy/measure_start_points.lua [km/h] [軸距] [Y] [余裕秒] [減速度]` |
| `tests/heavy/gen_track_lengths.js` | エディタのデータから軌道回路の実長を求め、`tests/heavy/track_lengths.lua` を作る（生成物は直接編集しない） | `node tests/heavy/gen_track_lengths.js [--report]` |

- 運転シミュレーションと現示シミュレーションは、別々のモデルで動く。速度の仮定が揃っていない（運転は 144 km/h 相当、現示は 110 km/h）。ARC の確定には現示シミュレーションを使い、運転シミュレーションは「ARC が黙って固まらない」ことの確認に使った。
- 2 つを 1 つの複数列車・加減速ありのモデルにまとめる構想がある。こちらは複数列車の単純な表引きのモデル、`runcurve-planner` は 1 列車の熟練運転士モデル、という分担である。まとめるときに、ブレーキなど手書きの定数（`measure_start_points.lua` の `BRAKE`、現示ごとの速度）を、`runcurve-planner` の車両特性から生成した表に替える。他リポジトリは読むだけにする。

## 既知の注意点

リポジトリ直下の `test.lua` は `WAK1R` / `WAK1RT` という信号機・軌道回路を参照して
いますが、現在の `res/signal.toml` / `res/area_track.json` にはこれらは存在しません
（路線データが更新され、参照先が失われたと見られます）。そのまま実行はできないため、
新しくテストを書く際は本ディレクトリのひな形を使うか、`res/signal.toml` に実在する
信号機名で組み立ててください。

## ATS のシミュレーション

`tests/heavy/sim_ats.lua` は、ATS の地上側(Area の callback が先頭の軸へ送る H0)を、運転士モデルを持つ列車で確かめる。
運転士役は信号現示だけを見て先読み制動し、ATS は H0 だけを独立に見る。単独走行、後追い、折り返し・入換を走らせる。
使い方と前提は、ファイルの冒頭に書いてある。
