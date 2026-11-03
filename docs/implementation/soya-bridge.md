# Soya Bridgeの実装

[文書一覧](../README.md) · [構成と分離方針](architecture.md) · [コア仕様](../../SPEC_CORE.md)

Soya Bridgeは宗弥急行の設定とStormworksの観測・出力をCoreに接続する。実装は [src/n_tracs_soyabridge/](../../src/n_tracs_soyabridge/)、ARCは現在 [src/n_tracs_arc/](../../src/n_tracs_arc/) にある。

## Coreとの接続

| 処理 | 主な実装 | Coreとの受渡し |
|---|---|---|
| 軸位置とAreaの対応 | `axle.lua`、`area.lua` | Area内の検知点から在線情報を作る |
| 軌道回路の接続 | `track_bridge.lua` | `Track:before_process(isShort)` |
| 転てつ器の接続 | `switch_bridge.lua` | 実位置を `Switch:before_process(K)` に渡す |
| ビークルの部品取得・送信 | `vehicle_info.lua` | 現示・指令値・転換要求などをゲーム内の入出力へ対応づける |
| 信号の現示反映 | `soya_bridge.lua` の `before_process()` | 各信号の `before_process()` で `nextAspect` を `aspect` に反映する |
| Areaへのコールバック | `soya_bridge.lua` の `before_broadcast()` | [送信ルール](area-send-rules.md)を実行し、戻り値を `area.cbdata` に保存する |
| 自動進路要求 | `arc_process()` | [ARC](arc.md)を更新し、てこ入力と `arc_values` を更新する |

Luaファイル名は別記がない限り `src/n_tracs_soyabridge/` 内を指す。

## 初期化と設定の適用

[script.lua](../../script.lua) は `SoyaBridge.new()` の後、Area・軌道回路、信号、転てつ器、エイリアス、ARCの順に設定を適用し、その後に踏切・コマンドを組み立てる。

`create_arc()` は構築時の軌道回路一覧と駅の登録点から索引を作る。軌道回路・信号の定義後に呼び、構築後に定義や駅のsequencesを変更しない。定義を変更する場合は再構築を前提とする。

### 宗弥急行の設定データ

| 設定 | 文書 |
|---|---|
| Area・軌道回路 | [area_track](../usage/area-track.md) |
| 信号・てこ・現示コールバック | [signal.toml](../usage/signal-toml.md) |
| 転てつ器・運転方向制御 | [switch.lua](../usage/switch-lua.md) |
| Add-on Lua外部から参照する信号の別名 | [signal_alias.lua](../usage/aliases-lua.md) |
| ARCの指令値形式・駅・動き・資源 | [ARCの利用](../usage/arc-usage.md) |

`res/utils.lua` の現示コールバックや送信関数も設定側の実装である。Coreとの分離に残る依存は [構成と分離方針](architecture.md#将来の分離と残る依存) を参照。

## 時間と指令値の受渡し

- `create_signal()` の `lockTime`・`overrunTime` は秒で受け、60倍してCoreへtickで渡す。CoreのAPIを直接呼ぶ場合とは単位が異なる。
- `create_area()` は生成データの差分座標を累積し、10で割って頂点座標を復元する。
- `track_arc()` は対応するAreaを順に調べ、最初に見つけた非0の軸の指令値を返す。複数の指令値を一覧で返すAPIではない。該当がなければ0を返す。
- `arc_process()` は `Arc:process()` の後に `Arc:adopted_values()` を呼び、信号ごとの送信値を更新する。

## 現在のアドオンの実行周期

`script.lua` は毎ゲームtickにPhaseを進め、6 tickごとにCoreを1回演算する。Core・Areaには `deltaTicks = 6` を渡す。60 tick/秒を基準に1演算周期は0.1秒相当。

| Phase | 処理 |
|---|---|
| 1 | Areaの軸一覧を初期化し、ビークルのデータを取得する |
| 2 | 軸のArea探索、在線・転てつ器実位置・前周期の現示の反映 |
| 3 | Core演算、踏切処理 |
| 4 | Areaのコールバック、その後にARCの更新・進路要求 |
| 5 | 送信符号を反転して配信し、遅延コマンドを実行する |
| 0 | 上記の段階処理を行わない |

バッテリーの充電処理は全tickで呼ぶ。Core演算後に予約された共通タイマー操作やてこ入力は、次のCore演算で処理する。Phase 4で作ったArea送信値・ARC送信値は、Phase 5で配信する。

ARCは内部で10呼出し/秒を仮定する。Phase構成や呼出し間隔を変える場合、Coreへ渡すtick幅に加え、ARCの秒から周期数への換算も変更対象になる。
