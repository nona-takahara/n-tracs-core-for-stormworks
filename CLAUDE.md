# CLAUDE.md

このファイルは、このリポジトリで作業する Claude Code（claude.ai/code）への案内です。

## プロジェクトの概要

**Stormworks** 向けに移植した N-TRACS（鉄道連動システム）です。Sawyer Island の模型鉄道「宗弥急行（Soya Express）」の地上信号、軌道回路、転てつ器を制御します。中核のロジックは Lua で、ビルドの仕組みは Node.js で書かれています。

## ビルド

```bash
pnpm build
```

`node index.js` が実行され、次のことを行います。

1. `res/area_track.json` から `res/area_track.lua` を再生成する（古い場合のみ）
2. `res/signal.toml` から `res/signal.lua` を再生成する（古い場合のみ）。`controlled_by` のグラフを DFS で調べ、循環があればビルドエラーにする
3. 手作業のデータを検査する。相互参照、経路の連続性、転てつ器の設定、ARC の設定（`build/check_arc.lua`）を調べ、誤りがあればビルドを止める
4. `storm-lua-minify` で `script.lua` を `dist/script.min.lua` に minify し、131,071 字の上限を超えていれば警告する
5. `.env` に `NTRACS_SW_DIR` があれば、出力を Stormworks のミッションディレクトリへコピーする

Windows 側の `pnpm` を使います。npm は使いません。

## テスト

- ビルド内チェック（`pnpm build`）は、手作業で作って渡すデータの誤りを検出します。
- `pnpm test` は、ロジックとツールチェーンの誤りを見る軽いテスト（`tests/repro_*.lua`）を実行します。
- `pnpm test:full` は、軽いテストに加えて、`tests/heavy/` の重いテストと外部ツールの検証を実行します。外部ツールの検証を自動で実行するのは、このときだけです。重いテストは、本当に必要な箇所以外では実行しません。

詳しくは `tests/README.md` を参照してください。

## アーキテクチャ

3 つの層と、ARC（`src/n_tracs_arc/`。設定は `res/arc.lua`、詳細は `docs/arc.md`）からなります。

### 第 1 層: N-TRACS コア（`src/n_tracs_core/`）

フレームワークに依存しない鉄道のロジックです。`ntracs.lua` が全信号機、軌道回路、転てつ器のデータベースを持ち、`process()` のループを動かします。主な概念は次のとおりです。

- **Track**（`track/track.lua`）: 論理的な軌道回路。予約の状態は `book_type.lua` にあり、遷移は `SPEC_CORE.md` にある
- **Signal**（`signal/signal.lua`）: てこで操作する信号機。進路鎖錠、ASR（Automatic Signal Reset）、過走防護を持つ。`controls[]` で親てこの操作を波及させる（多段可。循環はビルド時に検査する）
- **Switch**（`switch/switch.lua`）: 転てつ機。W（要求）と K（実際）の位置を持つ
- **TrafficDirectionSwitch**（`switch/traffic_direction_switch.lua`）: 単線の双方向制御に使う、ソフトウェア上の仮想レジスタ。W は tick をまたいで保持し、K は W に従う（物理的な応答はない）
- **TrafficDirectionLever**（`signal/traffic_direction_lever.lua`）: 反位は送り側で、相手端を確認してから `myFrDirection` を書く。定位は受け側で、無条件に `-myFrDirection` を書く。両端で同じ方向の値を使う必要がある

領域の仕様全体は `SPEC_CORE.md` に、既知の問題と状況は `ISSUES.md` にあります。

### 第 2 層: Soya Bridge（`src/n_tracs_soyabridge/`）

N-TRACS コアのオブジェクトを Stormworks のゲーム内オブジェクトに対応づける統合層です。

- `soya_bridge.lua`: `Ntracs` のインスタンスを作り、エリア、車両、ブリッジを管理する
- `track_bridge.lua`: 論理的な軌道回路を、マップ上のエリアに対応づける
- `switch_bridge.lua`: 論理的な転てつ器を、車両の操作に対応づける
- `vehicle_info.lua`: `TRAIN*` という名前の看板から車軸の位置を読み、信号の現示を車両のダイヤルで送り返す
- `area.lua`: 複素数の計算（`src/utils/complex.lua`）で点と多角形の内外を判定し、列車の在線を調べる

### 第 3 層: エントリポイントと設定

- **`script.lua`**: Stormworks アドオンのエントリポイント。ライフサイクルのフック（`onCreate`、`onTick` など）を実装する
- **`res/area_track.lua`** と **`res/signal.lua`**: JSON と TOML からの自動生成。直接編集しない
- **`res/switch.lua`**、**`res/signal_alias.lua`**、**`res/crossing.lua`**、**`res/arc.lua`**、**`res/utils.lua`**: 手書きの設定
- **`res/ctc.lua`**: 旧 CTC の実装。`script.lua` からは参照されていない

### `onTick` の 6 段階

1. Stormworks から車両の部品データを取得する
2. エリアを初期化し、車軸を探す（列車の検知）
3. `Ntracs.process()` を実行し、軌道回路、信号機、転てつ器を評価する
4. エリアのコールバックを実行する
5. 信号の現示を車両へ送る
6. 遅延コマンドを実行する

ARC は `script.lua` の Phase 4 で実行します（`before_broadcast` のあとの `sw:arc_process()`）。

## 設定ファイル

| ファイル | 作り方 | 用途 |
|------|--------|---------|
| `res/area_track.json` | 半自動（`storm-n-tracs-editor-line`） | エリアの多角形の頂点と、軌道回路との対応。`docs/area-track.md` を参照 |
| `res/signal.toml` | 手書き | 信号機とてこの定義（進路、コールバックを含む）。`docs/signal-toml.md` を参照 |
| `res/switch.lua` | 手書き | 転てつ器の定義。`docs/switch-lua.md` を参照 |
| `res/signal_alias.lua` | 手書き | CTC の別名とてこ ID の対応。`docs/aliases-lua.md` を参照 |
| `res/area_track.lua` | 生成 | 編集しない |
| `res/signal.lua` | 生成 | 編集しない |

## 環境

`template.env` を `.env` にコピーし、`NTRACS_SW_DIR` に Stormworks のミッションディレクトリを設定すると、ビルド時に自動で配置されます。

## Lua の実行環境

Lua の実行環境は Stormworks 内の **Lua 5.3** です。`server`、`property`、`matrix` などのグローバルと、Stormworks のライフサイクル関数を使えます。
