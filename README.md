# N-TRACS Soya Express

N-TRACSは、[Nona Takahara](https://github.com/nona-takahara)によるホビーユース・非産業利用向けの汎用鉄道用連動装置ソフトウェアです。

宗弥急行（Soya Express）は、[Nanaha Asme](https://twitter.com/AsmeNanaha)による[Stormworks](https://store.steampowered.com/app/573090/Stormworks_Build_and_Rescue/)向け鉄道路線プロジェクトです。

N-TRACS Soya Expressは、Stormworks Lua with LifeBoatAPI用に移植されたN-TRACSと、宗弥急行専用機能を実現するための周辺ソフトウェアで構成されるソフトウェアです。

本ソフトウェアはMITライセンスで提供されます。

生命や財産の安全が関わる場面で利用される場合も、ライセンス文書の通り、無保証で提供されます。この点に留意してご利用いただくようお願い申し上げます。

## Download
Steamワークショップにて公開後、リンクを掲載します。

## Release Note
まだリリースがありません。

## How to Build a Coding Environment
本ソフトウェアの開発・ビルド環境は以下の通りです。過不足があれば修正されます。

- [Visual Studio Code](https://code.visualstudio.com/)
- [Stormworks Lua with LifeBoatAPI](https://marketplace.visualstudio.com/items?itemName=NameousChangey.lifeboatapi) Extension
- Python 3.11以降
<!-- tomllibを使用するため -->

ワークスペースを作成し、設定の`Lua.workspace.library`に以下のディレクトリに対する**絶対パス**を設定してください
- この`README.md`があるディレクトリ
- このリポジトリの`/_build/libs/`
- LifeBoat APIの`/assets/lua/Common/`
- LifeBoat APIの`/assets/lua/Addon/`

GitHub Desktopを使用している場合の具体的な`.code-workspace`の設定は以下のようになります。
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
コミットメッセージは日本語でOKです。
