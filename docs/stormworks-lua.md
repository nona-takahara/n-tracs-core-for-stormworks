# Stormworks アドオンの Lua 環境

Stormworks のアドオンは、標準の Lua 5.3 から一部の関数を削った環境で動きます。
このリポジトリの Lua を書くときは、ここにある制限を前提にしてください。
内容は、アドオン環境で実際に見える関数を調べた結果にもとづきます。

## 使えるもの

| 区分 | 使える関数 |
|---|---|
| 基本関数 | `type` `tostring` `tonumber` `pairs` `ipairs` `next` |
| `table` | `insert` `remove` `sort` `concat` `unpack` `pack` `move` |
| `string` | Lua 5.3 の標準関数すべて（`format` `find` `match` `gsub` `gmatch` `sub` `pack` `unpack` など） |
| `math` | Lua 5.3 の標準関数すべて（`floor` `sqrt` `type` `tointeger` `random` など） |
| `debug` | `debug.log` のみ |

言語機能（`//` による整数除算、整数と浮動小数点数の区別など）は Lua 5.3 のとおりです。

## 使えないもの

| 使えない関数 | 代わりの書き方 |
|---|---|
| `setmetatable` `getmetatable` `rawget` `rawset` `rawequal` `rawlen` | クラスは `NtracsObject.create_instance` で作ります。クラスの関数をインスタンスにコピーする方式です |
| `assert` `error` `pcall` `xpcall` | 設定の誤りはビルド時に検出します（下記）。実行時の例外は捕まえられません |
| `select` | 可変長引数は `table.pack` か、引数をテーブルで受けます |
| `require`（実行時） | ビルド時に `storm-lua-minify` が1つのファイルにまとめるため、通常どおり書いて構いません |
| `load` `loadfile` `dofile` `collectgarbage` `print` | なし |
| `os` `io` `utf8` `coroutine` | なし |

`script.lua` は `error` が無いときだけ、ログを出して処理を続けるだけの代替関数を定義します。
`error` を呼んでもスクリプトは止まらず、その先の状態は保証されません。
呼び出しの後に整合した状態が残る書き方をしてください。

## 設定の誤りの扱い

実行時に `assert` や `error` で落とす設計にはしません。
設定の誤りはビルド時（`npm run build`）に検出して、ビルドを止めます。

- 検査のコードはアドオンに同梱しません。`script.lua` から `require` されないファイルに置きます。
- 検査は通常の Lua 5.3 で動かします。ビルド環境に Lua 5.3 が必要です。見つからない場合は警告を出して検査を飛ばします。
- 例: ARC の設定は `build/check_arc.lua` が `src/n_tracs_arc/arc_check.lua` を呼んで検査します。

実行時には、設定が正しいものとして動きます。

## 文字列は ASCII だけにする

minify 後のスクリプトに残る文字列は、ASCII の範囲に限ります。
日本語などの非 ASCII 文字は、コメントには書けますが、文字列リテラルには書けません。コメントは minify で取り除かれるためです。

- 資源名、駅名、予約資源名、てこの ID など、コードの中で文字列として持つ名前は、英数字と記号だけにします。
- 表示用の日本語は、コメントに書くか、ASCII の名前と対応させて書きます。
- 例: ARC の資源名は `"3番"` ではなく `"P3"` のように書き、日本語の意味はコメントで補います。
