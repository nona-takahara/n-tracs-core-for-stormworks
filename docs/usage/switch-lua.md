# switch.lua リファレンス

[文書一覧](../README.md) · [コア仕様](../../SPEC_CORE.md)

このリファレンスの `sw` は Soya Bridge のインスタンスです。宗弥急行の設備をゲーム内の転てつ器と Core に対応させる設定 API を説明しており、Core の `Ntracs:create_switch()` とは引数が異なります。 [構成と分離方針](../implementation/architecture.md) も参照してください。

`res/switch.lua` は転てつ器を定義するファイルです。W は転てつ制御リレー、K は転てつ表示リレーとして扱います。W の磁気保持はビークル側で行い、Core からは電流相当の制御出力を渡します。K は有極3位リレーの定位・無励磁・反位に対応させ、KN / KR を個別に設ける代わりに直接参照します。Kの値0は、表示が定位・反位のいずれとも確定できない場合も含みます。値と判定条件は [コア仕様の第5章](../../SPEC_CORE.md#5-switch転てつ機) を参照してください。

```lua
---@param sw SoyaBridge
return function(sw)
    sw:create_switch("NHB21", { "NHB21" },          { "NHB21T" })
    sw:create_switch("NHB22", { "NHB22a", "NHB22b" }, { "NHB21T", "NHB22T" })
    sw:create_switch("NHB31", { "NHB31" },          { "NHB22T" }, true)
end
```

---

## `sw:create_switch(id, points, related_tracks, is_site?)`

| 引数 | 型 | 説明 |
|---|---|---|
| `id` | string | 転てつ器ID。signal.toml の `switches[].sw` と一致させる |
| `points` | string[] | Stormworks ビークル上のコントロール名リスト。転てつ器の物理トングに対応するコントロールを列挙する |
| `related_tracks` | string[] | てっ査鎖錠の対象となる軌道回路名リスト |
| `is_site` | boolean? | 現場扱いフラグ（省略時 `false`） |
