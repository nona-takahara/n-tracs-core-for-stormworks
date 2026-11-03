# ドキュメント一覧

[プロジェクトの README](../README.md) に戻る。

文書は、実装を変更するためのものと、利用・`res` の設定を書き換えるためのものに分けています。目的に応じて、次の一覧から参照してください。

## 実装・検査（implementation）

Core・Soya Bridge・ARCの内部処理、ジェネレータ、実行環境と検証を扱います。実装の変更時に参照する文書です。

| 文書 | 内容 |
|---|---|
| [構成と分離方針](implementation/architecture.md) | Core・Soya Bridge・宗弥急行の設定データの責務と現在の結び付き |
| [N-TRACS Core 仕様詳解](../SPEC_CORE.md) | 予約・鎖錠・現示・運転方向制御の内部条件と、設計意図の確認課題 |
| [軌道回路予約方式と本実装](implementation/track-reservation.md) | 予約モデルの概要、競合判定と状態管理 |
| [Soya Bridge](implementation/soya-bridge.md) | ゲーム内の設備とCoreの接続、現在のアドオンの実行周期 |
| [ARCの実装](implementation/arc.md) | 観測・候補検索、要求と採用、資源・警報・指令値の送信処理 |
| [ARCの検査](implementation/arc-check.md) | ビルド時の設定検査、回帰テスト、運転シミュレーションと計測 |
| [Areaの送信ルール](implementation/area-send-rules.md) | 送信条件の生成、空Areaの処理、照査点の監視 |
| [StormworksのLua環境](implementation/stormworks-lua.md) | Luaを実装する際の使用可能な関数と実行時の制限 |
| [テストの実行と書き方](../tests/README.md) | Windows側pnpm、回帰テスト、minify後の検証、運転シミュレーション |

## 利用・res設定（usage）

指令値や操作、駅・路線・設備の設定を扱います。設定項目の意味や変更方法は、こちらを参照してください。

| 文書 | 主な対象 |
|---|---|
| [ARCの利用](usage/arc-usage.md) | 指令値、駅ごとの進路・資源・待ち時間、停止・再開と手動操作 |
| [Areaと軌道回路](usage/area-track.md) | `res/area_track.json` の編集と自動生成されるLuaの扱い |
| [信号・てこ](usage/signal-toml.md) | `res/signal.toml`、総括制御、現示コールバック |
| [転てつ器](usage/switch-lua.md) | `res/switch.lua`、関連軌道回路、現場扱いの設定 |
| [エイリアス](usage/aliases-lua.md) | `res/signal_alias.lua`、Add-on Luaの外部から参照する名前 |

自動生成される `res/area_track.lua` と `res/signal.lua` は直接編集しません。設定の変更で内部の判定条件や検査方法を確認する必要がある場合は、実装・検査の文書を参照してください。
