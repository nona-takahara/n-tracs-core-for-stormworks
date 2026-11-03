# area_track リファレンス

[文書一覧](../README.md) · [コア仕様](../../SPEC_CORE.md)

Area の形状と軌道回路との対応は、宗弥急行の路線データです。Soya Bridge がこのデータと軸の位置から在線を判定し、Core には論理軌道回路の在線情報を渡します。Core 自体は Area の形状を扱いません。 [構成と分離方針](../implementation/architecture.md) も参照してください。

## ファイル構成

| ファイル | 管理方法 |
|---|---|
| `res/area_track.json` | **Storm N-TRACS Editor (旧版)** で編集または **Storm N-TRACS Editor Line** で生成する。手書きは非推奨 |
| `res/area_track.lua` | ビルド時に `area_track.json` から自動生成。直接編集不可 |

エリアポリゴンの頂点座標やトラックとエリアの対応付けはすべて Storm N-TRACS Editor 上で行い、エクスポートした JSON をリポジトリに配置してください。

## ビルドの動作

`pnpm build` 実行時、`area_track.json` の更新日時が `area_track.lua` より新しい場合のみ再生成されます。JSON を更新したら必ずビルドを実行してください。
