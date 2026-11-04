# Soya Bridgeの実装

[文書一覧](../README.md) · [構成と分離方針](architecture.md) · [コア仕様](../../SPEC_CORE.md)

Soya Bridge は、宗弥急行の設定と Stormworks の観測・出力を Core に接続する。実装は [src/n_tracs_soyabridge/](../../src/n_tracs_soyabridge/) にあり、ARC は現在 [src/n_tracs_arc/](../../src/n_tracs_arc/) にある。

## Coreとの接続

Lua ファイル名は、別の記載がなければ `src/n_tracs_soyabridge/` 内を指す。

| 処理 | 主な実装 | Core との受渡し |
|---|---|---|
| 軸位置と Area の対応 | `axle.lua`、`area.lua` | Area 内の検知点から在線情報を作る |
| 軌道回路の接続 | `track_bridge.lua` | `Track:before_process(isShort)` |
| 転てつ器の接続 | `switch_bridge.lua` | 実位置を `Switch:before_process(K)` に渡す |
| ビークルの部品取得・送信 | `vehicle_info.lua` | 現示・指令値・転換要求などを、ゲーム内の入出力に対応づける |
| 信号の現示反映 | `soya_bridge.lua` の `before_process()` | 各信号の `before_process()` で、`nextAspect` を `aspect` に反映する |
| Area へのコールバック | `soya_bridge.lua` の `before_broadcast()` | [送信ルール](area-send-rules.md) を実行し、戻り値を `area.cbdata` に保存する |
| 自動進路要求 | `arc_process()` | [ARC](arc.md) を更新し、てこ入力と `arc_values` を更新する |

## 初期化と設定の適用

[script.lua](../../script.lua) は `SoyaBridge.new()` のあと、Area・軌道回路、信号、転てつ器、エイリアス、ARC の順に設定を適用する。その後に、踏切とコマンドを組み立てる。

`create_arc()` は、構築時の軌道回路一覧と駅の登録点から索引を作る。軌道回路と信号を定義したあとに呼び、構築後は定義や駅の sequences を変えない。定義を変えるときは、再構築が前提になる。

### 宗弥急行の設定データ

| 設定 | 文書 |
|---|---|
| Area・軌道回路 | [area_track](../usage/area-track.md) |
| 信号・てこ・現示コールバック | [signal.toml](../usage/signal-toml.md) |
| 転てつ器・運転方向制御 | [switch.lua](../usage/switch-lua.md) |
| Add-on の Lua の外から参照する信号の別名 | [signal_alias.lua](../usage/aliases-lua.md) |
| ARC の指令値形式・駅・動き・資源 | [ARCの利用](../usage/arc-usage.md) |

`res/utils.lua` の現示コールバックと送信関数も、設定側の実装である。Core との分離で残る依存は [構成と分離方針](architecture.md#将来の分離と残る依存) にある。

## 時間と指令値の受渡し

- `create_signal()` の `lockTime`・`overrunTime` は秒で受け取り、60倍して Core に tick で渡す。Core の API を直接呼ぶ場合とは単位が違う。
- `create_area()` は、生成データの差分座標を累積し、10で割って頂点座標を復元する。
- `track_arc()` は、対応する Area を順に調べ、最初に見つけた0以外の軸の指令値を返す。複数の指令値を一覧で返す API ではない。該当がなければ0を返す。
- `arc_process()` は、`Arc:process()` のあとに `Arc:adopted_values()` を呼び、信号ごとの送信値を更新する。

## 現在のアドオンの実行周期

`script.lua` は、毎ゲーム tick に Phase を進め、6 tick ごとに Core を1回演算する。Core と Area には `deltaTicks = 6` を渡す。60 tick/秒を基準にすると、1演算周期は0.1秒に相当する。

| Phase | 処理 |
|---|---|
| 1 | Area の軸一覧を初期化し、ビークルのデータを取得する |
| 2 | 軸の Area 探索。在線・転てつ器の実位置・前周期の現示を反映する |
| 3 | Core 演算、踏切処理 |
| 4 | Area のコールバック。その後に ARC の更新と進路要求 |
| 5 | 送信符号を反転して配信し、遅延コマンドを実行する |
| 0 | 上の段階処理を行わない |

- バッテリーの充電処理は、全 tick で呼ぶ。
- Core 演算のあとに予約された共通タイマー操作とてこ入力は、次の Core 演算で処理する。
- Phase 4 で作った Area の送信値と ARC の送信値は、Phase 5 で配信する。

ARC は内部で10呼出し/秒を仮定している。Phase 構成や呼出し間隔を変えるときは、Core に渡す tick 幅に加えて、ARC の秒から周期数への換算も変更する必要がある。
