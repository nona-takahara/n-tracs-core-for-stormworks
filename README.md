# N-TRACS Soya Express Wayside Signals

N-TRACS は、[Nona Takahara](https://github.com/nona-takahara) によるホビー向けの汎用鉄道用連動装置ソフトウェアです。

宗弥急行（Soya Express）は、[Nanaha Asme](https://twitter.com/AsmeNanaha) による [Stormworks](https://store.steampowered.com/app/573090/Stormworks_Build_and_Rescue/) 向け鉄道路線プロジェクトです。

N-TRACS Soya Express Wayside Signals は、Stormworks Lua with LifeBoatAPI 用に移植された N-TRACS と、宗弥急行専用機能を実現するための周辺ソフトウェアで構成されるソフトウェアです。

本ソフトウェアは MIT ライセンスで提供されます。

生命や財産の安全が関わる場面で利用される場合も、ライセンス文書の通り、無保証で提供されます。この点に留意してご利用いただくようお願い申し上げます。

## Download

[Steam ワークショップ](https://steamcommunity.com/sharedfiles/filedetails/?id=3125923553)よりサブスクライブしてください。

## Release Note

- v1.0.0
  - 正式リリース
- v1.0.1
  - 一部の信号機の設定ミスを修正
- v1.0.2
  - 駅アドオンの進行信号現示反応標識との連携を改善
  - ATS の移行準備機能を追加

## How to Build a Coding Environment

本ソフトウェアの開発・ビルド環境は以下の通りです。過不足があれば修正されます。

- [Visual Studio Code](https://code.visualstudio.com/)
- [Stormworks Lua with LifeBoatAPI](https://marketplace.visualstudio.com/items?itemName=NameousChangey.lifeboatapi) Extension
- Python 3.11 以降
<!-- tomllibを使用するため -->

ワークスペースを作成し、設定の`Lua.workspace.library`に以下のディレクトリに対する**絶対パス**を設定してください

- この`README.md`があるディレクトリ
- このリポジトリの`/_build/libs/`
- LifeBoat API の`/assets/lua/Common/`
- LifeBoat API の`/assets/lua/Addon/`

GitHub Desktop を使用している場合の具体的な`.code-workspace`の設定は以下のようになります。

```json
"settings": {
    "Lua.workspace.library": [
        "c:/Users/<USERNAME>/Documents/GitHub/n-tracs-soya-express/",
        "c:/Users/<USERNAME>/.vscode/extensions/nameouschangey.lifeboatapi-0.0.33/assets/lua/Common/",
        "c:/Users/<USERNAME>/.vscode/extensions/nameouschangey.lifeboatapi-0.0.33/assets/lua/Addon/",
        "c:/Users/<USERNAME>/Documents/GitHub/n-tracs-soya-express/_build/libs/"
    ]
}
```

## How to Contribute

コミットメッセージは日本語で OK です。
