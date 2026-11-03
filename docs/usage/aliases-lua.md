# signal_alias.lua リファレンス

[文書一覧](../README.md) · [コア仕様](../../SPEC_CORE.md)

エイリアスは、Add-on Luaの外部から信号を参照するための名前です。内部のてこ名と外部から使う名前を分け、システムの更新で内部IDが変わっても、駅側からは同じ名前で同じ信号を参照し続けられるようにします。対応付けはSoya Bridgeが保持し、`res/signal_alias.lua` に設定します。[構成と分離方針](../implementation/architecture.md) も参照してください。

```lua
---@param sw SoyaBridge
return function(sw)
    sw:set_lever_alias("aNHB_3d", "NHB5R")
    sw:set_lever_alias("aNHB_4d", "NHB4R")
    -- ...
end
```

---

## `sw:set_lever_alias(alias, lever_id)`

| 引数 | 型 | 説明 |
|---|---|---|
| `alias` | string | Add-on Luaの外部から参照する名前 |
| `lever_id` | string | 対応先となる内部の信号・てこ名 |

内部の信号・てこ名を変更した場合は、この対応付けを更新します。外部から使うエイリアス名を維持することで、駅側の参照名を変更せずに済みます。

## 現在の現示送信での利用

[VehicleInfo](../../src/n_tracs_soyabridge/vehicle_info.lua) は、ビークルのボタン・Dial/Keypad名からエイリアスを認識し、対応先の信号の現示を `<エイリアス名>_ASPECT` へ送ります。例えば、上記の `aNHB_3d` は `NHB5R` の現示を `aNHB_3d_ASPECT` で受け取るための名前です。

この対応表は現示送信時の参照先を解決するもので、CoreのてこID自体を変更するものではありません。内部IDを直接使う参照には、エイリアスの登録は不要です。
