# N-TRACS 仕様詳解

このドキュメントは、[src/n_tracs_core/](src/n_tracs_core) の現在の実装を説明します。実装の変更案ではなく、状態の読み書きと判定条件を確かめるための参照資料です。

N-TRACS は、宗弥急行の路線設定も Stormworks の入出力も、固定の仕様として持ちません。それらは Soya Bridge の責務で、[構成と分離方針](docs/implementation/architecture.md) と [Soya Bridge の文書](docs/implementation/soya-bridge.md) に分けて書いています。リレーの名称には実装上の識別子を併記し、本文では状態と判定条件を説明します。実装と設計意図の確認課題は第10章にまとめています。

| 関連文書 | 内容 |
|---|---|
| [ドキュメント一覧](docs/README.md) | 設定・実装・検証の文書への入口 |
| [軌道回路予約方式と本実装](docs/implementation/track-reservation.md) | 予約による競合判定、状態管理、N-TRACS と Soya Bridge の分担 |
| [構成と分離方針](docs/implementation/architecture.md) | N-TRACS・Soya Bridge・res の責務と現在の結び付き |
| [Soya Bridge](docs/implementation/soya-bridge.md) | 宗弥急行固有の設定処理と Stormworks 連携 |
| [信号・てこの設定](docs/usage/signal-toml.md) | TOML の項目と総括制御の設定 |
| [転てつ器の設定](docs/usage/switch-lua.md) | 通常の転てつ器と関連軌道回路 |
| [Area と軌道回路](docs/usage/area-track.md) | 在線検知に使う領域の設定 |
| [Area の送信ルール](docs/implementation/area-send-rules.md) | コールバックと照査点のタイマー監視 |
| [ARCの実装](docs/implementation/arc.md) | コアの演算後に進路要求を出す自動制御 |
| [Lua 実行環境](docs/implementation/stormworks-lua.md) | Stormworks の関数制限 |
| [テストの実行と書き方](tests/README.md) | 本番設定を使う回帰テスト |

---

## 1. 全体概念

N-TRACS は、継電連動装置の一部を軌道回路予約方式のアイデアで実装することで、連動ロジックを簡易にソフトウェアで実装したものです。リレーの名称を使う状態変数も持ちますが、進路の鎖錠は、軌道回路に対応づけた予約で管理します。次の3種類のオブジェクトが、互いの状態を参照しながら、演算周期ごとに状態を更新します。

| クラス | 現実の対応物 | 役割 |
|--------|-------------|------|
| `Track` | 軌道回路 | 列車在線の検知と、進路鎖錠状態の管理 |
| `Signal` | 進路てこ＋信号機 | 進路の設定・鎖錠・現示の計算 |
| `Switch` | 転てつ機 | 分岐器の転換要求と鎖錠の管理 |

これらはすべて `Ntracs` オブジェクト（DB オブジェクト）に登録されます。`Ntracs:process(deltaTicks)` を1回呼ぶと、全オブジェクトのステップを Track → Signal → Switch の順に処理します。

`Track` は区間ごとの予約を持ち、`Signal` と `Switch` が、その予約を参照して進路の設定、現示、転換の可否を判断します。予約は使用中か空きかの区別だけではありません。用途と方向によっては、共用できる場合があります。

予約の競合チェックは、本実装で扱う状態と用途に合わせて単純化しています。予約状態と方向などに応じた適合判定を関数に分け、仮予約から本予約への移行と、前要素を参照した予約の解放を行います。概要は [軌道回路予約方式と本実装](docs/implementation/track-reservation.md)、具体的な条件は3.6節と4.7節にあります。

---

## 2. 演算周期と処理フロー

`Ntracs:process(deltaTicks)` の1回を「演算周期」、`deltaTicks` の時間単位を「tick」と呼びます。N-TRACS は、呼び出し元が渡す時間幅で演算し、呼び出し間隔を自分では決めません。現在のアドオンは6 tick の周期で呼びます。Phase の順序は [Soya Bridge の実行周期](docs/implementation/soya-bridge.md#現在のアドオンの実行周期) にあります。

呼び出し側は、演算の前に次の状態を反映します。

1. `Track:before_process(isShort)` で在線情報を設定する。
2. `Switch:before_process(K)` で、通常の転てつ器の実位置を設定し、要求位置をリセットする。仮想方向分岐器は要求位置を保持する（第6章）。
3. `Signal:before_process()` と `AutoSignal:before_process()` で、`nextAspect` を `aspect` に反映する。

その後、[Ntracs:process](src/n_tracs_core/ntracs.lua) が次の順に処理します。

```text
Track:process(deltaTicks, nt)    共通タイマーの反映、予約・鎖錠の更新
Signal等:process(deltaTicks, nt) 進路要求、予約、リレー、次の現示の計算
Switch等:process(deltaTicks, nt) 通常・仮想とも現在は空の処理
```

同じ種類のオブジェクトは `pairs` で走査するため、名前順・配置順は保証されません。状態の変更はその場で共有され、後に処理されるオブジェクトから見えます。周期の開始時の状態だけを参照する仕組みではありません。

コア演算のあとに呼び出し側が行ったタイマー操作の予約や進路要求は、次のコア演算で処理します。Area の送信、ARC、ゲームへの配信は、コアの処理順に含めません。

---

## 3. Track（抽象軌道回路）

### 3.1 状態（BookType）とデュアルフィールド構造

実装は [track.lua](src/n_tracs_core/track/track.lua) と [book_type.lua](src/n_tracs_core/track/book_type.lua) です。

軌道回路は、メインフィールド（`book`）とサブフィールド（`bookDest`）の2つの予約フィールドを持ちます。これにより、1つの軌道回路が、同時に2種類の予約（例：前進路の着点と、次進路の発点）を保持できます。

#### メインフィールド（`book`）

| 状態 | 値 | 意味 | 解除条件（解錠条件） |
|------|----|------|----------|
| `NoBook` | 0 | 予約なし（初期状態） | なし |
| `Temporary` | 1 | 仮予約 | 関連てこの入力が切れたとき |
| `RouteLock` | 2 | 進路鎖錠 | 在線なし、かつ、ひとつ前の区間が解除済み |
| `Start` | 3 | 発点予約 | ASR が扛上したとき（在線の有無は問わない） |

#### サブフィールド（`bookDest`）

| 状態 | 値 | 意味 | 解除条件 |
|------|----|------|----------|
| `NoBook` | 0 | 予約なし | なし |
| `DestinationActive` | 4 | 着点予約（過走防護中） | 在線中のタイマー満了で `DestinationExpired` になる。非在線で前要素が解除済みなら、直接 `NoBook` になる |
| `RouteOver` | 5 | 過走防護区間の本予約 | 在線なし、かつ、ひとつ前の区間が解除済み |
| `DestinationExpired` | 6 | 着点予約（過走防護解除） | 在線なし、かつ、ひとつ前の区間が解除済み |

```text
[メイン]
NoBook → Temporary → RouteLock → NoBook（順次解錠）
NoBook → Temporary → Start     → NoBook（ASR 扛上で解除）

[サブ]
NoBook → DestinationActive → DestinationExpired → NoBook
                 └── 非在線かつ前要素解錠済み ───→ NoBook
NoBook → RouteOver                              → NoBook
```

#### 異なる役割の予約を併存させる条件

次の表は、異なる役割の予約を、同じ軌道回路で併存させられる条件です。

| メインに追加する役割 | 既存のサブ予約 | 条件 |
|---|---|---|
| 発点（仮予約→確定） | `DestinationExpired` | 方向を問わない |
| 発点（仮予約→確定） | `DestinationActive` | 同一方向のみ |
| 進路鎖錠（確定） | `RouteOver` | 同一方向のみ |

発点の予約は、既存のサブ予約を消して書き換える処理ではありません。`book_start()` は、条件が合えばメインを `Start` にし、サブを維持します。逆方向の `DestinationActive` は、発点として利用できません。`DestinationExpired` に進むか、サブ予約が解除されるまで待ちます。

### 3.2 `beforeRouteLockItem`（自分を抑える予約/鎖錠条件の参照）

本予約状態では、`beforeRouteLockItem` に「ひとつ前のオブジェクト名」が設定されます。メインの解除にはこのフィールドを、サブの解除には `destBeforeRouteLockItem` を使い、前要素の状態を参照して解除します。

進路鎖錠の始点は ASR を参照するため Signal（てこ自身の名前）で、以降は各 `routeLock` 軌道の名前が順に設定されます。なお、発点（`Start`）は、`routeLock` の解錠チェーンには組み込まれません。

```text
Signal(てこ) → routeLock[1] → routeLock[2] → ... → destination(サブ)
                                                       ├→ overrunLock[1](サブ)
                                                       └→ overrunLock[2](サブ) …
```

### 3.3 `CheckUnlockRouteLock(item, nt)`

「ひとつ前のオブジェクトが解除/解錠済みか」を判定するグローバル関数です。

- `item == nil`：`true`（始点なので常に解除できる）
- `item` が Track：`track:under_route_lock_b()` を返す
- `item` が通常の Signal：`signal:under_route_lock_b()`、すなわち `signal.ASR` を返す
- 名前の参照先が軌道回路にもてこにもない：`false`

### 3.4 `under_route_lock_b()`

その Track が、次の Track を解除/解錠できる状態ならば true を返すメソッドです。サブフィールド（`bookDest`）の状態を優先します。

```lua
function Track:under_route_lock_b()
    if self.bookDest == BookType.DestinationExpired then return true end
    if self.bookDest == BookType.DestinationActive  then return false end
    if self.bookDest == BookType.RouteOver          then return false end
    -- サブ = 予約なし → メインで判断
    return self.book == BookType.NoBook or self.book == BookType.Temporary
end
```

`DestinationExpired`（過走防護タイマー満了）は `true` を返し、下流の `RouteOver` などを解除できるようにします。

### 3.5 過走防護タイマー（DestinationActive / DestinationExpired）

過走防護区間の転てつ器を鎖錠する目的を、N-TRACS では、区間の予約と時間条件の設定で扱います。本書で「過走防護鎖錠」と呼ぶのは、この設定手法です。設定項目は `overrun_lock` と `overrun_lock_time`、対応する予約状態は `RouteOver` です。

`book_destination()` は、`destTimer = overrunTime`、`destTimerStarted = false` にします。`DestinationActive` の演算では、次の処理をします。

- 在線中だけ `destTimer = max(destTimer - deltaTick, -1)` として時間を減らす。`destTimerStarted` は在線時に `true` にするが、このフラグで減算の継続を判定してはいない。
- 減算後の値が0未満なら `DestinationExpired` に進む。0ちょうどでは進まない。
- 非在線で前要素が解除済みなら、タイマーの満了を待たず、`DestinationActive` から直接 `NoBook` にする。

このため、一度在線したあと、常に減算を続けるタイマーではありません。非在線で予約が残っている間は減算しません。`DestinationExpired` の解除条件も、非在線かつ `CheckUnlockRouteLock` の成立です。

### 3.6 仮予約の適合条件

#### 進路鎖錠・着点・過走防護トラック用（`is_ready_for_book_temporary`）

```text
メイン == NoBook
  または  メイン == Temporary(同てこ)
  または  メイン == Start(同方向)
AND
サブ == NoBook  または  サブ == RouteOver(同方向)
```

`メイン == Start(同方向)` を許すのは、同じ方向に接続する二つの進路で、一方の着点と他方の発点が同じ軌道回路になる場合のためです。前方の信号がすでに発点として `Start` を書き込んだ軌道回路に、後方の信号が同一方向で着点の仮予約を行えます。`is_booked_temporary`（本予約確定のチェック）にも、同様の条件があります。

対向方向は仮予約の時点で排除します。`book_temporary()` は `book == NoBook` のときだけ書き込むので、他てこの `Start` を上書きしません。`book_destination()` も `Temporary`（同一てこ）のときだけ `book` をクリアするため、既存の `Start` 予約は保持されます。

#### 発点トラック用（`is_ready_for_book_start`）

```text
メイン == NoBook  または  メイン == Temporary(同てこ)  または  メイン == Start(同てこ)
AND
サブ == NoBook
  または  サブ == DestinationExpired（方向を問わない）
  または  サブ == DestinationActive（同方向のみ）
```

#### 仮予約の適合判定と本予約前の確認の違い

`is_ready_for_*` は、仮予約を書き込んでよいかを調べます。`book_temporary()` と `book_start_temporary()` 自体は、メインが `NoBook` のときだけ書き込みます。互換性のある既存予約を、必ず `Temporary` に書き換えるわけではありません。

本予約前の `is_booked_temporary()` は、次のいずれかで成立します。

- メインが自てこの `Temporary`
- メインが同方向の `Start`
- サブが同方向の `RouteOver`

`is_booked_start()` は、メインが自てこの `Temporary` または `Start`、あるいはサブが `DestinationExpired` または同方向の `DestinationActive` なら成立します。どちらも、適合判定と同じ式ではありません。呼び出し順は4.3節にあります。

### 3.7 共通タイマー

Area のコールバックや踏切の連動から使う、軌道回路ごとの経過 tick 計です。`key` の文字列で、1つの軌道回路に複数持てます。予約状態の過走防護タイマー（3.5節）とは独立しています。

- `track:advance_timer(key, deltaTick)`：進める予約。同じ演算周期に何か所から呼んでも、進むのは最初の1回分だけ。
- `track:reset_timer(key)`：0 に戻す予約。
- `track:get_timer(key)`：現在値（tick）。一度も進めていなければ0。

予約は、次の `Track:process`（毎演算周期、全軌道回路に呼ばれる）で反映します。同じ演算周期の間は `get_timer` の値が変わらず、同じ軌道回路の複数の Area コールバックは、同じ値を読みます。

反映は `(リセット予約があれば0、なければ現在値) + (進める予約があれば deltaTick)` で、呼び出し順に依存しません。同じ演算周期にリセットと進める予約が両方あると、0から1回分進んだ値になります（計り直し）。

```lua
-- Area callback の例：在線が続く間だけ進め、離れたら戻す
if track:is_short() then track:advance_timer("hold", deltaTicks) else track:reset_timer("hold") end
local expired = track:get_timer("hold") >= 45 * 60
```

## 4. Signal（進路てこ）

Signal は、継電連動装置の進路てこと信号機リレー群に相当します。実装は [signal.lua](src/n_tracs_core/signal/signal.lua)、宗弥急行での設定例は [signal.toml リファレンス](docs/usage/signal-toml.md) にあります。

### 4.1 主要フィールド

リレー状態は、原則として true を扛上、false を落下に対応させます。

| フィールド | 説明 |
|-----------|------|
| `input` | てこ入力（true=反位）。操作・自動復位・総括制御で変更する |
| `HR` | 信号制御リレー（注意信号用）。進路鎖錠と過走防護の双方が成立したときの、現示の許可条件。減速信号用と進行信号用は本システムでは定義しない（コールバックを使う） |
| `HyR` | 信号制御リレー（警戒信号用）。過走防護フォールバック時の現示許可にも使い、`HR=true` のときは常に true |
| `ASR` | 接近鎖錠リレー。進路鎖錠の最も初点側の軌道回路がてこ側の条件として参照する。本予約への格上げ処理は、これの落下時に行う |
| `MSlR` | 接近鎖錠補助リレー。接近・保留鎖錠のタイマーを制御する |
| `TSSlR` | 接近解錠軌道保持リレー。本実装では、列車の進路への進入を示す状態を保持する |
| `aspect` | 現在の信号現示（0=停止。前の演算周期の `nextAspect`） |
| `nextAspect` | 今回の演算周期で計算した、次の信号現示 |
| `timerTick` | 接近・保留鎖錠のタイマー値（tick） |
| `auto_reset` | 保存済みの `TSSlR` に応じて入力を自動復位するか。初期値は true |

### 4.2 各リレーの条件

次の式は、`Signal:process()` 内の代入順に読みます。

- `TSSlR` の計算は、更新前の `HR` と `ASR` を参照する。
- `ASR` の計算は、更新前の `HR` と、更新後の `TSSlR` を参照する。
- `MSlR` は、更新後の `ASR` を参照する。
- `HR` と `HyR` は、本予約の処理後に更新する。

てこリレー（資料上の LR / RR）は、本実装ではローカル変数 `R` で表します。`R = getInput() AND siteSwitchAssert(nt)` で、`input` はその判定に使うてこの入力値です。

進路照査リレーを表す `ZR` は、`getInput() AND checkSwitches(nt)` というローカル変数です。予約の成功を示す値ではなく、てこ入力と転換方向が条件に合うことを示します。HR が扛上するのは、ZR に加えて、ASR の落下や進路鎖錠などの条件が成立したときです。進路鎖錠リレー（TLSR / TRSR）は、独立したリレーとしては実装せず、軌道回路の予約で代用しています。

#### TSSlR（接近解錠軌道保持リレー）

```text
TSSlR = NOT(HR) AND NOT(ASR) AND isEnterRoute
```

列車が進路内方に進入したことを示します。HR の落下後、進入前は false です。

#### ASR（接近鎖錠リレー）

```text
ASR = NOT(HR) AND NOT(ZR) AND (接近なし OR TSSlR OR 既にASR OR タイマー終了)
```

`Signal:under_route_lock_b()` は ASR を返し、発点予約の解除・進路鎖錠の解錠条件としてこの値を参照します。てこ入力と分岐器の転換可否は、それぞれ別の処理でも判定します。

- 落下条件：更新前の `HR=true` または `ZR=true`
- 扛上条件：信号が停止で、進路鎖錠が不可（てこ入力が OFF、または分岐器の条件が不成立）のとき、接近なし、進入済み、タイマー終了のいずれか

#### MSlR（接近鎖錠補助リレー）

```text
MSlR = NOT(HR) AND NOT(ZR) AND NOT(ASR) AND NOT(isEnterRoute) AND (NOT(isTimerRunning()) OR 更新前のMSlR)
```

MSlR が true の間は `timerTick` を加算します。`timerTick >= lockTime` になると `isTimerEnd()` が true になり、ASR が扛上できます。

#### HR（信号制御リレー）

```text
HR = ZR AND isLocked AND checkWLR AND NOT(TSSlR) AND NOT(ASR) AND isNoShort
```

- `ZR`：てこ入力があり、かつ分岐器が設定方向と一致している。
- `isLocked`：発点・進路鎖錠・着点の成立（`isRouteLocked`）と、過走防護の成立（`isOverrunProtected`）の両方。
- `checkWLR`：関連する全分岐器の `getWLR()` が false。通常の転てつ器では、転てつ鎖錠リレー（WLR）の落下、つまり転換を止める状態に対応する。仮想方向分岐器では常に成立する（6.6節）。
- `NOT(TSSlR)`、`NOT(ASR)`：各リレーが false。これらだけで全区間の鎖錠成立を表すわけではない。
- `isNoShort`：signalTrack に在線がない。

### 4.3 進路設定のシーケンス

1. **てこ反位**（`setInput(true)`）
2. **分岐器転換**（`siteSwitchAssert` 成立時）：R が true になり、`switch:move()` を呼ぶ。
3. **仮予約**（`ZR` が true で、`bookTemporary` が成功）：発点・routeLock・着点の適合を先に調べ、過走防護の成否とフォールバック設定も確認する。必要条件が揃ったときだけ、仮予約を書き込む。互換性のある既存予約は保持される（3.6節）。
4. **本予約確定**（`NOT(ASR)` かつ `isBookedTemporary` 成立）：発点を `Start`（メイン）、routeLock を `RouteLock`（メイン）、着点を `DestinationActive`（サブ）に格上げする。過走防護区間は、4.7節の条件で `RouteOver`（サブ）にする。
5. **HR 扛上**（鎖錠が完成し、全条件が成立）：進行を指示する信号の現示を許可する。現示番号はコールバックが決める。HyR による警戒現示の扱いは4.7節にある。
6. **列車進入**：更新前の `HR` と `ASR` がともに false で、`isEnterRoute` が true になると `TSSlR` が上がる。`auto_reset=true` なら、その次の演算周期の冒頭で `setInput(false, nt)` が呼ばれ、`input = false` になる（自動復位）。`setInput()` を経由するので、`controls` と `extra_controls` で総括制御しているてこ（方向てこなど）にも、復位が伝わる。
7. **進路鎖錠の解錠**（列車の通過後、`CheckUnlockRouteLock` によって順に `NoBook` になる）
   - 発点：`Track:process()` が Signal.ASR の true を確認すると解除する（在線の有無は問わない）。Track の演算が先なので、今回更新した ASR は次の周期から参照する。
   - routeLock：在線なし、かつ、前要素が解除済み。
   - DestinationActive：在線中の減算で満了すれば `DestinationExpired`。非在線で前要素が解除済みなら、満了前でも `NoBook`（3.5節）。

#### 仮予約チェック順序（`bookTemporary`）

```text
発点 is_ready_for_book_start? → routeLock(各) is_ready_for_book_temporary?
→ 着点 is_ready_for_book_temporary? → overrunLock(各) is_ready_for_book_temporary?
→ 必要条件が通れば順に書き込み（過走防護フォールバックの例外は4.7節）
```

対向進路の排他は、このチェックで実現します。例えば、ある進路が仮予約を試みたとき、その発点のサブが `DestinationActive`（逆方向）なら、`is_ready_for_book_start` が false を返し、仮予約全体をスキップします。

### 4.4 `isEnterRoute()` の動作

防護区間への列車の進入を判定します。

- `routeLock` が空で `signalTrack[1]` がある：`signalTrack[1]` の在線で判定する。
- `routeLock` が空で `signalTrack` も空：常に `true`（進入済みとみなす）。
- `routeLock[1]` だけがある：`routeLock[1]` の在線で判定する。
- `routeLock[2]` 以上がある：`routeLock[1] AND routeLock[2]` の双方の在線で判定する。

### 4.5 `updateCallback`

`updateCallback` は、毎演算周期、`HR` と `HyR` の成否にかかわらず呼びます。戻り値をいったん `nextAspect` に保存し、`HR` と `HyR` がともに false のときだけ0（停止）にします。

`HR=false, HyR=true` のときは、コールバックの戻り値を維持します。ただし、標準のコールバックは `HR` だけを参照します。フォールバック時の現示を使うには、`HyR` も参照するコールバックが必要です（4.7節）。

宗弥急行側の `res/utils.lua` に、コアへ渡すコールバックの実装例があります。次の関数群は、N-TRACS Core の組み込み機能ではありません。

| 関数 | 現示数 | 動作 |
|------|--------|------|
| `StandardAspectCallback_2nd` | 2現示 | `HR=true` なら指定の aspect、そうでなければ停止 |
| `StandardAspectCallback_3rd_G_Y_R` | 3現示 | 次信号と自信号の `aspect` がともに2以上なら4、そうでなければ2 |
| `StandardAspectCallback_3rd_multi` | 3現示（複数の次信号） | 次信号のいずれかと自信号の `aspect` がともに2以上なら4、そうでなければ2 |

`aspect` は前の演算周期の値（`before_process()` で確定）、`nextAspect` は今回の演算周期の計算値です。次信号の `aspect` を参照するので、連動する現示は1演算周期遅れます。

### 4.6 総括制御（`controls`）

自てこの `setInput()` は、`controls` に列挙されたてこに、多段に作用します（A→B→C のような多段制御が機能します）。

総括制御が働くのは、`setInput(input, nt)` に `nt` を渡したときです。`nt` を省略したときと、`fromControl=true` のときは、自分の入力だけを変更します。自動復位も `setInput(false, nt)` を経由するため、総括制御先へ伝わります。

ビルド時の DFS は、`controlled_by` から組み立てたグラフの循環を検出します。`extra_controls` は、その後に追加されるので、循環検査の対象外です。実行時に循環を止める仕組みはないため、`extra_controls` でも循環を作らないでください。設定方法は [総括制御のリファレンス](docs/usage/signal-toml.md#総括制御) にあります。

### 4.7 過走防護フォールバック（`overrunLockFallback` / `HyR`）

TOML で `overrun_lock_fallback = true` を指定した信号は、過走防護区間を仮予約できなくても、発点・進路鎖錠・着点の予約を進めます。

#### 仮予約と本予約の範囲

1. `bookTemporary()` は、発点・routeLock・着点の適合をすべて確認する。ここが不成立なら、書き込まない。
2. 過走防護区間の適合をまとめて確認し、`overrunReady` に保存する。
3. `overrunReady=false` でフォールバックが無効なら、全体を書き込まない。
4. それ以外は、発点・routeLock・着点を仮予約し、`overrunReady=true` のときだけ過走防護区間も仮予約する。

本予約前の `isBookedTemporary()` も、フォールバックが有効なら過走防護区間の確認を省きます。ただし、過走防護を実際に書き込むときは、各区間に次の条件を適用します。

```lua
if t:is_booked_temporary(self.itemName, nt) and not t:is_over_run_lock(self.itemName, nt) then
    t:book_over_run(self.itemName, nt)
end
```

`is_booked_temporary()` は、3.6節の互換性のある予約を含む確認です。自てこの `Temporary` とは限りません。`is_over_run_lock()` が成立済みの区間には、予約を書き直しません。

#### 進路鎖錠と過走防護の成立条件

- `isRouteLocked()`：発点は `is_start_locked()`、routeLock の各区間は自てこの `RouteLock`、着点は自てこの `DestinationActive` または `DestinationExpired` であること。
- `is_start_locked()`：自てこの `Start`、サブが `DestinationExpired`、サブが同方向の `DestinationActive` のいずれか。サブの条件では、所有てこ名を比較しない。
- `isOverrunProtected()`：過走防護の全区間で `is_over_run_lock()` が成立すること。
- `is_over_run_lock()`：自てこの `RouteOver`、または同方向のメイン `RouteLock`。
- `isLocked()`：`isRouteLocked()` と `isOverrunProtected()` の両方。

#### HR / HyR と現示

```text
baseOk = ZR AND checkWLR AND NOT(TSSlR) AND NOT(ASR) AND isNoShort
HR     = baseOk AND isLocked(nt)
HyR    = HR OR (baseOk AND overrunLockFallback AND isRouteLocked(nt))
```

`HR=true` なら `HyR` も必ず true で、両者は排他的ではありません。設計上の現示との対応は次のとおりです。

- 両方が落下：停止
- HR が落下、HyR が扛上：警戒
- 両方が扛上：注意現示以上

フォールバックが有効なら、過走防護が成立していなくても、`baseOk` と `isRouteLocked()` が成立すれば `HyR=true` になります。`HR` 自体の条件は緩めません。

設計者が説明した目的は、過走防護をかけない状態で、警戒現示による進入を認めることです。本実装では、過走防護区間を予約できない場合でも、進路自体の鎖錠と共通条件が成立すれば、HyR の扛上を認めます。対象は、フォールバックを明示的に有効にした進路です。警戒現示での進入という考え方を、予約・鎖錠モデルに取り入れた設計であり、過走余裕距離や安全側線の有無を自動で判定する機能ではありません。

コアは、フォールバック時の現示番号を決めません。`updateCallback` を呼び、`HR` と `HyR` がともに false のときだけ、戻り値にかかわらず `nextAspect=0` にします。次のコールバックは、`HR=true` なら4、`HyR` だけが true なら1を返す例です。

```toml
update_callback = 'function(lever, nt, dt) if lever.HR then return 4 elseif lever.HyR then return 1 else return 0 end end'
```

### 4.8 AutoSignal

[auto_signal.lua](src/n_tracs_core/signal/auto_signal.lua) は、てこ入力も進路予約も行わず、次の条件で `HR` を計算します。

```text
HR = signalTrack がすべて非在線 AND switches がすべて設定方向と一致
```

`HR`、`aspect`、`nextAspect` の初期値は、それぞれ false、0、0 です。`updateCallback` は毎周期呼び、`HR=false` のときだけ `nextAspect=0` にします。`HyR` によるフォールバックはありません。

---

## 5. Switch（転てつ機）

### 5.1 フィールド

実装は [switch.lua](src/n_tracs_core/switch/switch.lua)、設定は [転てつ器のリファレンス](docs/usage/switch-lua.md) にあります。

| フィールド | 説明 |
|-----------|------|
| `W` | 転てつ制御リレー。転換しようとする方向を表す要求位置。`move()` で設定し、毎演算周期 `before_process()` でリセットする |
| `K` | 転てつ表示リレー。有極3位リレーの定位・無励磁・反位に対応する実位置。`before_process()` で外部から注入する |
| `isSite` | 現場扱い（true）か、連動扱い（false）か |

### 5.2 `before_process(currentState)`

毎演算周期、SoyaBridge が実際の分岐器位置を `K` に注入し、`W` を `Indefinite` にリセットします。W は磁気保持リレーなので、保持はビークル側の役割とし、N-TRACS は電流相当の制御出力を渡す設計です。K は、定位・反位の表示リレー（KN / KR）を個別に設ける代わりに、直接読む実装です。

### 5.3 `move(target, nt)`

`getWLR(nt)` が true（WLR 扛上、転換可能）のとき、`W = target` を設定します。SoyaBridge が W を読み取り、ゲームの分岐器制御コマンドに変換します。

### 5.4 `getWLR(nt)`（転換可能条件）

関連軌道（`relatedTracks`）のいずれかが次のどちらかであれば、`false`（WLR 落下、転換不可）を返します。

- 在線中（`is_short()`）
- 鎖錠中（`is_locked(not isSite)`）

どの区間にも当てはまらなければ、`true`（WLR 扛上、転換可能）です。

- `isSite = true`：`is_locked(false)` なので、`Temporary` も鎖錠とみなす。
- `isSite = false`：`is_locked(true)` なので、`Temporary` は鎖錠とみなさない。

どちらの場合も、`is_locked()` の対象はメインの `book` だけです。サブの `bookDest` は、この判定に含めません。

### 5.5 `checkSwitches()`（Signal 側から呼ばれる）

`SwitchRoute:check(nt)` は、`getRealRoute() != target` のとき `true`（不一致）を返します。通常の Switch では、`getRealRoute()` は `K` を返します。`checkSwitches()` は、全部が `false`（正常）のときに `true` を返します。つまり、全分岐器が要求方向に転換済みであることの確認です。

---

## 6. 運転方向制御（TrafficDirectionLever と TrafficDirectionSwitch）

### 6.1 設計の目的

実装は [traffic_direction_lever.lua](src/n_tracs_core/signal/traffic_direction_lever.lua) と [traffic_direction_switch.lua](src/n_tracs_core/switch/traffic_direction_switch.lua) です。

単線区間では、上下列車が同じ線路を共用するため、一度に1方向の列車しか在線させてはなりません。N-TRACS は、これを「方向てこ（TrafficDirectionLever）」と「仮想方向分岐器（TrafficDirectionSwitch）」の組み合わせで実現します。

### 6.2 仮想方向分岐器（TrafficDirectionSwitch）の役割

`TrafficDirectionSwitch` は、物理的な転てつ機ではなく、運転方向リレー（FR）を表すソフトウェアのレジスタです。区間の両端（駅 A、駅 B）に、それぞれ1つ置きます。

通常の `Switch` との違いは次のとおりです。

| | Switch（通常） | TrafficDirectionSwitch（仮想） |
|--|--------------|-------------------------------|
| `getRealRoute()` | `K`（物理フィードバック）を返す | `W`（最後に指令した方向）を返す |
| `before_process()` | `K = currentState` にし、`W = Indefinite` にリセットする | `K = W` にするだけで、`W` はリセットしない |

FR と W は磁気保持リレーのように扱い、定位か反位かを指定して状態を保持します。操作のたびに状態を反転する方式ではありません。通常の W の保持はビークル側ですが、仮想方向分岐器では N-TRACS の中に保持します。

`W` をリセットしないのは意図的です。仮想方向分岐器は、一度設定された方向を保持し続ける必要があります。物理フィードバックがないので、`K = W`（実位置＝指令位置）とします。

**方向値の区別**：ある運転方向を表すとき、両端のスイッチの `W` は、同じ値に揃えます。一方、両端のてこの `myFrDirection` は、それぞれが出し側になる向きを表します。片端が出し側、他端が受け側という通常の組み合わせでは、両てこに互いに逆符号の値を設定します。

例えば [res/switch.lua](res/switch.lua) は、掘戸町の `HLT2R` を `Normal`、北港の `NHB1L` を `Reverse` にしています。A が出し側のとき、B の受け側が書く `-B.myFrDirection` と `A.myFrDirection` が一致すれば、確認が成立します。

コンストラクタの引数コメントにある「両端で同じ値」と、この二つの値の区別は、確認候補です（第10章）。

### 6.3 方向てこ（TrafficDirectionLever）の設計方針

- 反位が出し側、定位が受け側という、1方向専用のてこ。
- 受け側と出し側の役割は、てこ自体は持たず、現在のてこ位置（反位か定位か）で動的に決まる。
- 閉そく区間の両端に1本ずつ配置し、操作員の操作、または信号てこの総括制御で操作する。

`process()` の動作は次のとおりです。

**定位（input=false）＝受け側**：逆方向（`-myFrDirection`）を自端のスイッチに要求します。相手端の方向確認は行いません。ただし、`move()` による在線・鎖錠での棄却は適用されます。

```text
myFrName.move(-myFrDirection)
```

受け側が逆方向を書き込むことで、出し側のチェックが成立する値を設定します。

**反位（input=true）＝出し側**：相手端のスイッチが `myFrDirection` を向いていることを確認してから書き込みます。

```text
if anotherFrName.getRealRoute() == myFrDirection then
    myFrName.move(myFrDirection)
end
```

`SetRoute` の値は `Normal=1`、`Reverse=-1` なので、`-myFrDirection` が対向方向を表します。

### 6.4 動作シーケンス（総括制御なし）

現在、B→A 方向で運転中（A が定位、B が反位）の状態から、A→B に転換する例です。

| 段階 | A（myFrDirection=Normal） | B（myFrDirection=Reverse） |
|---------|--------------------------|--------------------------|
| 転換前 | 定位：switchA に -Normal=Reverse を書き続ける | 反位：switchA==Reverse を確認し、switchB に Reverse を書き続ける |
| 転換操作 | A が反位になる | B が定位になる |
| 転換後 | 反位：switchB==Normal を確認して成立し、switchA に Normal を書く | 定位：switchB に -Reverse=Normal を書き始める |

この例は、関連区間の在線とメイン予約がなく、`move()` が要求を受け付ける場合です。B が定位になると switchB に Normal が書かれ始め、A の確認チェックが成立します。同種のオブジェクトの処理順は固定ではないので、両端の更新が同じ演算周期に収まるとは限りません。

### 6.5 総括制御による方向てこ操作

信号てこの `controls` に方向てこを登録すると、その信号てこの操作と自動復位が方向てこに伝わります。対象は設定によります。本番の `NHB2L` は、`extra_controls = ["NHB1L"]` として、北港側の方向てこを操作します。

総括制御は、同じ真偽値を渡します。相手端のてこを、自動で逆の位置にする機能はありません。両端の方向てこを同じ信号の制御先に入れると、両方に同じ値が渡ります。反位と定位の組み合わせは、設定と操作で成立させます。

### 6.6 出発信号てこと仮想方向分岐器の組み合わせ

#### checkWLR との関係

`Signal.checkWLR()` は、`switches[]` に列挙した分岐器の `getWLR()` がすべて false のときに `true` を返します。通常の転てつ器では、WLR の落下（転換不可）を確認し、HR 扛上の条件の一つにします。仮想方向分岐器だけは例外です。

`TrafficDirectionSwitch.getWLR()` は、常に false （落下、鎖錠されている）を返します。物理分岐器と違い、「在線・鎖錠がなければ転換できる」という WLR 条件を、信号に課しません。`checkWLR()` は常に通過します。

その代わり、転換の棄却は `move()` の中で独自に判定します。仮想方向分岐器の `move()` は、公開メソッドの `getWLR()` を呼ばず、関連軌道回路の在線とメイン予約を直接確認します。在線か鎖錠があれば、`W` を書き換えません。

```text
Signal.checkWLR() → TrafficDirectionSwitch.getWLR() = false（常に）→ checkWLR 通過
方向転換要求     → TrafficDirectionSwitch.move()
                   → 区間在線 or 鎖錠あり → 棄却（W 変更なし）
                   → 区間空き           → W 更新（転換）
```

#### 宗弥急行の signal.toml 設定例（参考）

```toml
[NHB2L]
start       = "NHB5LT"
destination = "HLT_NHB1T"
direction   = "left"
switches    = [{ sw = "NHB_HLT_FR", t = "reverse" }]  # 自駅側方向分岐器の位置確認
route_lock  = []
# その他の項目は res/signal.toml を参照
extra_controls = ["NHB1L"]                          # 方向てこを総括制御
```

`route_lock` が空でも、発点・着点の予約と方向確認で進路を構成できます。`destination` のサブ予約があるというだけの理由で、仮想方向分岐器の `move()` が棄却されることはありません。

#### 転換を止める判定の範囲

[Track:is_locked](src/n_tracs_core/track/track.lua) は、メインの `book` だけを調べ、`bookDest` は調べません。通常の転てつ器の `getWLR()` も、仮想方向分岐器の `move()` も、この関数と在線を使います。

| 対象軌道回路の状態 | 仮想方向分岐器の `move()` |
|---|---|
| 在線中 | 棄却 |
| 非在線で、メインが `Temporary` / `RouteLock` / `Start` | 棄却（`isSite=true` のため、仮予約も数える） |
| 非在線で、メインが `NoBook`、サブだけに予約がある | この判定では棄却しない |
| 非在線で、メイン・サブとも予約なし | 転換要求を書き込む |

一方、対向進路の発点予約は、逆方向の `DestinationActive` を `is_ready_for_book_start()` が拒否します。進路予約の適合判定と、分岐器の転換可否の判定は、別の条件です。

サブ予約だけが残るときの転換可否を、意図した仕様としてどう位置づけるかは、第10章の確認候補です。この見直しでは、実装を変更していません。

### 6.7 開通てこ（OpeningLever）

`OpeningLever`（[opening_lever.lua](src/n_tracs_core/signal/opening_lever.lua)）として仮実装されていますが、機能・実装に誤りがある可能性が高いため、現状 SPEC_CORE には記載していません。

---

## 7. 方向を表す値

[SetRoute](src/n_tracs_core/switch/set_route.lua) は、`Normal=1`、`Reverse=-1`、`Indefinite=0` です。通常の転てつ器の位置と、仮想方向分岐器の運転方向に使います。通常の転てつ器では、`Normal` と `Reverse` が定位と反位に対応します。`Indefinite` は、表示の未確定・不一致や、通常の W の転換要求なしにも使うため、ブラ（無励磁）そのものとは完全には対応しません。

[RouteDirection](src/n_tracs_core/signal/route_direction.lua) は、`None=0`、`Left=1`、`Right=2` です。信号と軌道回路の予約方向に使います。`SetRoute` とは別の列挙値なので、同じ数値でも用途を区別します。

本システムの「運転方向」は、FR に対応する仮想方向分岐器と方向てこが設定する、単線区間の方向を指します。`RouteDirection` のコメントにある「進行方向」は、信号・進路予約の向きを表す値です。列車の現在の移動方向を、速度から算出した値ではありません。本書では、運転方向と進行方向を区別して使います。

[SignalRoute](src/n_tracs_core/switch/signal_route.lua) は、`SetRoute` と同じ3値に加えて、`Onewaynormal=11`、`Onewayreverse=-11`、`Bothway=21` を定義しています。ただし、`SwitchRoute:check()` は、`getRealRoute()` と `target` の単純な一致判定です。拡張値を Normal や Reverse に読み替える処理はありません。

---

## 8. 信号現示の数値体系

### N-TRACS が扱う条件

コアは、`nextAspect=0` を停止として強制する場合があります。0以外の現示番号を一律に分類する処理は持ちません。番号の意味は、コールバックと送信先の規約で決まります。

### 宗弥急行プロジェクトの設定（参考）

宗弥急行プロジェクトでは、次の対応を使います。プロジェクト固有の設定であり、N-TRACS Core 全体で固定された現示番号の定義ではありません。同じ番号でも、信号機の種類によって意味が異なります。

| 値 | 宗弥急行プロジェクトでの現示 |
|---|---|
| 0 | 停止現示 |
| 1 | 警戒信号、二位式の入換信号機の進行現示、三位式の入換信号機の注意現示、または誘導信号機の誘導信号の現示 |
| 2 | 注意信号、または三位式の入換信号機の進行現示 |
| 3 | 減速信号 |
| 4 | 進行信号 |

「進行を指示する信号の現示」は、進行信号だけでなく、停止以外の警戒・注意・減速・進行を含みます。「誘導進行」は、「誘導信号機が誘導信号を現示している」ことを表す喚呼の省略表現です。宗弥急行プロジェクトには入換標識がないので、同プロジェクトで「入換進行」といえば、「入換信号機が進行現示を示している」ことを指します。これらの喚呼を、独立した信号の正式名称としては扱いません。

宗弥急行側の [res/utils.lua](res/utils.lua) に置かれた標準コールバックの動作は、次のとおりです。

- `StandardAspectCallback_2nd(aspect)`：`HR=true` のとき、引数の値を返す。
- 3現示コールバック：`HR=false` なら0を返す。自信号と対象の次信号の現在現示がともに2以上なら4、それ以外は2を返す。

設定例は [信号現示コールバック](docs/usage/signal-toml.md#コールバック関数) にあります。

---

## 9. 設計上の制約

1. **状態を持つ逐次更新**：各 `process()` は、予約、リレー、タイマーをその場で変更します。時間を進めるため、同じ入力で繰り返し呼んでも結果が変わらない「冪等な関数」ではありません。同種のオブジェクトの処理順も保証しません。
2. **進路鎖錠の解錠の参照**：前要素の名前が軌道回路にもてこにも見つからなければ、`CheckUnlockRouteLock` は false を返します。設定の相互参照は、ビルド時に確認します。
3. **前処理と演算の区別**：`before_process()` は、在線・実位置・現示を反映します。`process()` は、それらに加えて、その周期中に他のオブジェクトが更新した予約や方向も参照します。
4. **現示の反映時期**：今回の演算で計算した `nextAspect` は、次の `before_process()` で `aspect` に反映します。さらに進行方向の先の信号の `aspect` で現示を決定する場合は、前周期の確定値を参照します。
5. **時間の単位**：`lockTime`、`overrunTime`、共通タイマーは tick 単位です。演算回数とは区別し、1周期で渡す `deltaTicks` を加減算します。
6. **関数の呼び出し前提**：`book_route_lock()` や `book_destination()` は、呼び出し側の予約確認を前提に書き込みます。各書き込み関数を単独で呼んでも、Signal の一連の判定と同じ保証は得られません。

## 10. 実装課題

以下は、未実装であるか、現状の実装が誤っているか、意図通りでない可能性があると認めている点です。

- **閉路鎖錠**: 未実装
- **保留鎖錠**: 未実装（接近鎖錠用のフィールドで接近区間をなしにすると無時素で解錠してしまうので注意）
- **運転方向てこ**: 両端のスイッチが保持する値と、両端のてこに設定する `myFrDirection` を区別します。「両端で同じ値」とするコンストラクタのコメントは、本番設定と動作例に合うか確認が必要です。
- **鎖錠の範囲**: `is_locked()` がメイン予約だけを見ることと、サブ予約だけが残るときの分岐器の転換可否を、意図した制御としてどう説明するか、確認が必要です。
- **開通てこ**: 実装はされているが、挙動が完全に誤っている
