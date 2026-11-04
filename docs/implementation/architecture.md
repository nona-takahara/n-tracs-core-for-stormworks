# Core・Soya Bridge・設定データの責務

[文書一覧](../README.md) · [コア仕様](../../SPEC_CORE.md)

## 責務と現在の配置

| 区分 | 責務 | 現在の配置 | 詳細 |
|---|---|---|---|
| N-TRACS Core | 軌道回路予約、鎖錠、てこ、転てつ器、現示の許可条件 | `src/n_tracs_core/` | [コア仕様](../../SPEC_CORE.md)、[予約モデル](track-reservation.md) |
| Soya Bridge | 宗弥急行固有の設定処理と Stormworks 連携。設備・車軸・地上領域と Core の接続、自動進路制御 | `src/n_tracs_soyabridge/`、`src/n_tracs_arc/` | [Soya Bridge](soya-bridge.md)、[ARC](arc.md)、[送信ルール](area-send-rules.md) |
| 設定データ | 路線・設備・進路・資源、指令値の形式、現示コールバック | `res/` | [利用・res設定](../README.md#利用res設定usage) |
| 組み立て・実行周期 | 設定の適用、Stormworks のイベント、各処理の呼出し | `script.lua` | [実行周期](soya-bridge.md#現在のアドオンの実行周期) |
| 生成・検査 | 設定の変換、参照検査、minify | `build/`、`index.js` | [ARCの検査](arc-check.md)、[Lua環境](stormworks-lua.md) |

Core は、ゲーム内の検知方法も路線データも持たない。呼び出し側から渡された状態と時間幅で演算する。Soya Bridge は宗弥急行固有の処理を含む統合層で、`res` はその具体的な設定を持つ。

## ARCの実装・検査・利用

| 区分 | 役割 | 文書 |
|---|---|---|
| 実装 | `src/n_tracs_arc/arc.lua`。観測、要求の更新、進路要求。Core 演算のあとに Soya Bridge が呼ぶ | [ARCの実装](arc.md) |
| 検査 | `build/check_arc.lua`、`src/n_tracs_arc/arc_check.lua`、`tests/`。検査モジュールはアドオンの実行時に読み込まない | [ARCの検査](arc-check.md) |
| 利用 | `res/arc.lua`、`res/arc_value.lua`。指令値・駅・動き・資源の設定と操作 | [ARCの利用](../usage/arc-usage.md) |

ARC は Core のてこ入力を操作する。要求の採用は ARC が、予約・鎖錠・現示の成立判定は Core が担当する。

## 将来の分離と残る依存

Core、Soya Bridge、`res` を分離する計画があり、ARC は Soya Bridge に含める。現在の `src/n_tracs_arc/` は移動前の配置で、分離後のパッケージ構成は未確定である。

分離するときは、次の依存を整理する必要がある。

- `src/n_tracs_soyabridge/send_rule.lua` から `res/utils.lua` への参照
- ジェネレータが使う `res` の形式・出力先と、Core・Soya Bridge のモジュールパス
- `script.lua` による、設定と実行周期の組み立て
- `tests/harness.lua` と本番設定の回帰テストが、Core・Soya Bridge・`res` を同時に読み込む点

Core の仕様変更と宗弥急行の設定変更は、分けて扱う。実行間隔・現示番号・指令値の形式を変えるときは、それらを前提にしている Bridge・ARC・テストも確認する。
