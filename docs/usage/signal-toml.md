# signal.toml リファレンス

[文書一覧](../README.md) · [コア仕様](../../SPEC_CORE.md)

このファイル形式は、Soya Bridge が宗弥急行の信号・てこを組み立てるための設定です。Core は TOML を直接読みません。現示番号や現示コールバックはプロジェクト側の規約であり、Core の固定仕様とは区別します。 [構成と分離方針](../implementation/architecture.md) も参照してください。

`res/signal.toml` は信号てこと自動信号を定義するファイルです。ビルド時に `res/signal.lua` として生成されます（直接編集不可）。

信号IDは `[セクション名]` で決まります。命名規則は `<駅略称><番線><方向>` を推奨します（例: `NHB4R`、`SNH_SGN1`）。

## 半自動の信号機

```toml
[SIGNAL_ID]
start       = "軌道回路ID"       # 必須
destination = "軌道回路ID"       # 必須
direction   = "right"            # 必須: "left" | "right"
switches    = [{ sw = "転てつ器ID", t = "normal" }]  # 必須（なければ []）

route_lock       = ["軌道回路ID", ...]  # 必須（なければ []）
overrun_lock     = ["軌道回路ID", ...]  # 必須（なければ []）
overrun_lock_time = 0                  # 必須: 過走防護タイマー（秒）

signal_track     = ["軌道回路ID", ...]  # 必須
approach_track   = ["軌道回路ID", ...]  # 必須（なければ []）
approach_lock_time = 20                # 必須: 接近タイマー（秒）

update_callback  = 'u.StandardAspectCallback_2nd(2)'  # 必須

# 以下はオプション
overrun_lock_fallback = false     # 無指定ならばfalse
controlled_by  = ["信号ID", ...]  # 総括制御元（循環不可、ビルド時チェックあり）
extra_controls = ["信号ID", ...]  # 総括制御先（TOML外のてこ用。循環チェック対象外）
```

### 各フィールドの意味

`overrun_lock`・`overrun_lock_time` は、N-TRACSで過走防護区間の予約と時間条件を設定する項目です。本書では、この設定手法を「過走防護鎖錠」と呼びます。予約状態と解放条件は [コア仕様の3.5節](../../SPEC_CORE.md#35-過走防護タイマーdestinationactive--destinationexpired) を参照してください。

| フィールド | 型 | 説明 |
|---|---|---|
| `start` | string | てこの直前の軌道回路ID。接近鎖錠の検査にも使われる |
| `destination` | string | 進路の着点となる軌道回路名。過走防護区間は `overrun_lock` で別に指定する |
| `direction` | string | 列車の進行方向。`"right"` または `"left"` |
| `switches` | array | 開通に必要な転てつ器条件。`t` は `"normal"`（定位）または `"reverse"`（反位） |
| `route_lock` | array | 進路鎖錠する軌道回路リスト。start〜destinationの間の軌道回路を列挙する。本システムでは自動的に1軌道回路ごとに解錠する進路区分鎖錠となる。 |
| `overrun_lock` | array | 着点より先の過走防護区間として予約・鎖錠する軌道回路リスト |
| `overrun_lock_time` | number | 着点の在線中に減算する過走防護タイマーの初期値（秒）。0でも解錠全体が即時完了するという意味ではない。減算・満了・予約解放の条件は [コア仕様の3.5節](../../SPEC_CORE.md#35-過走防護タイマーdestinationactive--destinationexpired) を参照 |
| `signal_track` | array | 信号制御欄。在線で停止現示を強制する軌道回路リスト。通常は route_lock + destination を含める |
| `approach_track` | array | 接近鎖錠の区間とする軌道回路リスト |
| `approach_lock_time` | number | 接近・保留鎖錠の時素（秒）。時素を設けない場合は0を指定する（項目省略とは異なる）。保留鎖錠は[現状バグがある](../../SPEC_CORE.md#保留鎖錠) |
| `overrun_lock_fallback` | boolean | 省略時false。**trueなら過走防護区間を予約できない場合も、進路自体の鎖錠などが成立すればHyRのみが扛上する**。falseならばHyRはHRと同じ値となる。HyRを利用するには、現状では `update_callback` での定義が必須 |
| `update_callback` | string | 信号現示を返すLua式。[コールバック一覧](#コールバック関数)を参照 |
| `controlled_by` | array | このてこを総括制御する上位信号IDリスト（省略可）。[→総括制御](#総括制御) |
| `extra_controls` | array | このてこが総括制御する下位信号IDリスト（省略可）。TOML外のてこ用。[→総括制御](#総括制御) |

`approach_lock_time` と `overrun_lock_time` の設定単位は秒です。

### 総括制御

あるてこを操作したとき、連動して別のてこも同時に操作する機能です。`Signal:setInput()` が `controls[]` に登録されたてこへ再帰的に伝播します（A→B→C の多段制御も動作します）。

#### `controlled_by`（被制御側に書く・推奨）

```toml
[NHB1L]               # 被制御てこ
controlled_by = ["NHB2L"]   # NHB2L が NHB1L を制御する
...

[NHB2L]               # 制御てこ（controlled_by の記述は不要）
...
```

**被制御側に書く**のが基本です。ビルド時に `controlled_by` グラフの循環（A→B→A など）を DFS で検出し、循環があればビルドエラーになります。

#### `extra_controls`（制御側に書く・TOML外てこ用）

`controlled_by` は被制御てこが TOML に存在しないと書けません。`switch.lua` で定義する `TrafficDirectionLever`（方向てこ）など TOML 外のオブジェクトを総括制御したい場合は、**制御側に** `extra_controls` を使います。

```toml
[NHB2L]               # 制御てこ
extra_controls = ["NHB1L"]   # NHB1L（switch.luaで定義されたTrafficDirectionLever）を制御する
...
```

> **注意**: `extra_controls` に列挙した名前は DFS 循環チェックの対象外です。`TrafficDirectionLever` はリーフノード（自身に controls を持たない）なので循環は起きませんが、別の `Signal` 名を誤って書いた場合は循環が検出されません。

#### どちらを使うか

| 状況 | 使うフィールド |
|---|---|
| 被制御てこが TOML に存在する | `controlled_by`（被制御側に記述）|
| 被制御てこが `switch.lua` など TOML 外に存在する | `extra_controls`（制御側に記述）|

両方を同時に使うことも可能です。同一てこ名が両方から導出されても重複は自動的に除去されます。

## 自動の信号機

```toml
[SIGNAL_ID]
auto      = true
direction = "right"                    # 必須: "left" | "right"
signal_track = ["軌道回路ID", ...]     # 必須
update_callback = 'u.StandardAspectCallback_3rd_G_Y_R("次信号ID")'  # 必須

# 以下はオプション
switches  = [{ sw = "転てつ器ID", t = "normal" }]  # 転てつ器開通方向が不一致なら停止現示
```

`auto = true` のエントリは進路鎖錠を持たず、`signal_track` の在線と `switches` の位置のみで HR（信号制御リレー）の扛上・落下を決定します。`switches` は運転方向リレー（仮想転てつ器として実装されている）の参照に使用できます。

## コールバック関数

`update_callback` に指定できる組み込み関数は `res/utils.lua` に定義されています。

### `u.StandardAspectCallback_2nd(aspect)`

HR（信号制御リレー）が扛上（true）しているとき常に `aspect` を返す固定現示コールバックです。本システムでは、リレー状態のtrueは扛上、falseは落下に対応します。

```toml
update_callback = 'u.StandardAspectCallback_2nd(2)'  # HR時は常に注意現示(2)
```

| 引数 | 説明 |
|---|---|
| `aspect` | HR扛上時に返す現示コード |

### `u.StandardAspectCallback_3rd_G_Y_R(nextSignal)`

一般的な主信号機用の、次信号を参照する3現示コールバックです。自信号と次信号の両方が `aspect >= 2` のとき進行(4)、それ以外は注意(2)を返します。

```toml
update_callback = 'u.StandardAspectCallback_3rd_G_Y_R("NEXT_SIGNAL_ID")'
```

| 引数 | 説明 |
|---|---|
| `nextSignal` | 参照する次信号のID |

### `u.StandardAspectCallback_3rd_multi(nextSignals)`

`StandardAspectCallback_3rd_G_Y_R` の複数信号版です。`nextSignals` のいずれかが `aspect >= 2` なら進行(4)を返します。

```toml
update_callback = 'u.StandardAspectCallback_3rd_multi({"NEXT1", "NEXT2"})'
```

### インライン関数

`update_callback` には任意のLuaクロージャをそのまま書けます。複数行は `"""..."""` を使います。

```toml
update_callback = """
function(self, nt)
    if self.HR then
        if nt:get_signal("NEXT").HR and self.aspect >= 2 then
            return 3
        else
            return 2
        end
    else
        return 0
    end
end
"""
```

注意信号用の信号制御リレーである HR のほかに、警戒信号用の信号制御リレー相当の HyR を定義しています。

なお、現示はコールバック関数で定義することにしているため、進行信号用の DR や、減速信号用の DyR はありません。また、標準コールバックは HR のみを参照するため、HyR だけが扛上していても停止を返します。成立条件と設計目的は [コア仕様の4.7節](../../SPEC_CORE.md#47-過走防護フォールバックoverrunlockfallback--hyr) を参照してください。

コールバックの引数は `(self: Signal|AutoSignal, nt: Ntracs, deltaTick: number)` です。`self.HR`、`self.aspect`、`nt:get_signal(id)`、`nt:get_track(id)` などを参照できます。

### 現示コードの定義（宗弥急行WS）

以下は宗弥急行WS固有の対応であり、Core 共通の番号定義ではありません。信号機の種類ごとに現示を読み分けます。

| 値 | 宗弥急行WSでの信号現示 |
|---|---|
| 0 | 停止信号 |
| 1 | 警戒信号、二位式の入換信号機の進行信号、三位式の入換信号機の注意信号、誘導信号機の誘導信号 |
| 2 | 注意信号、三位式の入換信号機の進行信号 |
| 3 | 減速信号 |
| 4 | 進行信号 |
