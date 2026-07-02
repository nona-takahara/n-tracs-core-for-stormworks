# N-TRACS Core 仕様詳解

このドキュメントは `src/n_tracs_core/` の実装を自然言語で記述したものです。ISSUES.md の問題点を検討・修正する際の仕様参照として使用してください。

---

## 1. 全体概念

N-TRACS Core は**継電連動装置**をソフトウェアでモデル化したものです。現実の鉄道連動装置と同様に、以下の3種類のオブジェクトが互いの状態を参照しながら毎ループ（ティック）ごとに状態遷移します。

| クラス | 現実の対応物 | 役割 |
|--------|-------------|------|
| `Track` | 軌道回路 | 列車在線の検知と進路鎖錠状態の管理 |
| `Signal` | 進路てこ＋信号機 | 進路の設定・鎖錠・現示の計算 |
| `Switch` | 転てつ機 | 分岐器の転換要求と鎖錠の管理 |

これらはすべて `Ntracs` オブジェクト（DBオブジェクト）に登録され、`Ntracs:process(deltaTicks)` の呼び出し1回で全オブジェクトのステップを処理します。処理順は **Track → Signal → Switch** の順です。

---

## 2. ティックごとの処理フロー

各オブジェクトには `before_process()` と `process()` の2フェーズがあります。

```
[外部] Track:before_process(isShort)  ← 在線情報を注入
[外部] Signal:before_process()         ← nextAspect を aspect に確定
[外部] Switch:before_process(K)        ← 実位置(K)を注入

[Ntracs:process()]
  Track:process()  ← 鎖錠状態の更新
  Signal:process() ← てこリレー・鎖錠・現示計算
  Switch:process() ← （現状は空）
```

`before_process()` は `process()` より先に、SoyaBridge側が呼び出します。`process()` 内では `before_process()` で注入された情報を参照します。

---

## 3. Track（抽象軌道回路）

### 3.1 状態（BookType）とデュアルフィールド構造

軌道回路は **メインフィールド**（`book`）と**サブフィールド**（`bookDest`）の2つの予約フィールドを持ちます。これにより、1つのトラックが同時に2種類の予約（例：「前進路の着点」かつ「次進路の発点」）を保持できます。

#### メインフィールド（`book`）

| 状態 | 値 | 意味 | 解除条件 |
|------|----|------|----------|
| `NoBook` | 0 | 予約なし（初期状態） | — |
| `Temporary` | 1 | 仮予約 | 関連てこの入力が切れたとき |
| `RouteLock` | 2 | 進路鎖錠 | 在線なし かつ ひとつ前の区間が解除済み |
| `Start` | 3 | 発点鎖錠（**新規**） | ひとつ前の Signal.ASR が扛上したとき（在線有無問わず） |

#### サブフィールド（`bookDest`）

| 状態 | 値 | 意味 | 解除条件 |
|------|----|------|----------|
| `NoBook` | 0 | 予約なし | — |
| `DestinationActive` | 4 | 着点鎖錠・過走防護中 | タイマー満了 → `DestinationExpired` に遷移 |
| `RouteOver` | 5 | 過走防護鎖錠 | 在線なし かつ ひとつ前の区間が解除済み |
| `DestinationExpired` | 6 | 着点鎖錠・過走防護解除（**新規**） | 在線なし かつ ひとつ前の区間が解除済み |

```
[メイン]
NoBook → Temporary → RouteLock → NoBook（順次解除）
NoBook → Temporary → Start     → NoBook（Signal.ASR扛上で解除）

[サブ]
NoBook → DestinationActive → DestinationExpired → NoBook
NoBook → RouteOver                              → NoBook
```

#### 上書きルール（別てこが予約する場合）

| 上書き元（メイン） | サブの対象 | 条件 |
|---|---|---|
| 発点（仮予約→確定） | `DestinationExpired` | 方向問わず |
| 発点（仮予約→確定） | `DestinationActive` | **同一方向のみ** |
| 進路鎖錠（確定） | `RouteOver` | **同一方向のみ** |

逆方向の `DestinationActive` には発点は上書き**不可**。タイマー切れ（`DestinationExpired`）を待つ必要があります。

### 3.2 `beforeRouteLockItem`（鎖錠連鎖）

本予約状態では `beforeRouteLockItem` に「ひとつ前のオブジェクト名」が設定されます。これにより進路鎖錠が**前方から順番に解除される連鎖**を実現しています。

連鎖の始点は **Signal**（てこ自身の名前）、以降は各 `routeLock` 軌道の名前が順番に設定されます。

```
Signal(てこ) → routeLock[1] → routeLock[2] → ... → destination(サブ) → overrunLock(サブ)
                ↑
              ここにメインの発点は含まれない（発点の前の要素 = Signal）
```

**発点（`Start`）の特殊性**：発点は解除チェーンの上流（始端）に位置するため、連鎖には組み込まれません。発点の `beforeRouteLockItem = Signal名` とし、Signal.ASR を直接参照して解除します。

### 3.3 `CheckUnlockRouteLock(item, nt)`

「ひとつ前のオブジェクトが解除済みか」を判定するグローバル関数です。

- `item == nil` → `true`（始点なので常に解除可能）
- `item` が Track → `track:under_route_lock_b()` を返す
- `item` が Signal → `signal.ASR`（てこのASRリレー状態）を返す
- どちらでもない → `false`

### 3.4 `under_route_lock_b()`

Track が「鎖錠の連鎖を次に渡してよいか」を返すメソッドです。**サブフィールド**（`bookDest`）の状態が優先されます。

```lua
function Track:under_route_lock_b()
    if self.bookDest == BookType.DestinationExpired then return true end
    if self.bookDest == BookType.DestinationActive  then return false end
    if self.bookDest == BookType.RouteOver          then return false end
    -- サブ = 予約なし → メインで判断
    return self.book == BookType.NoBook or self.book == BookType.Temporary
end
```

`DestinationExpired`（過走防護タイマー満了）→ `true`：下流の `RouteOver` 等が解除可能になります。

### 3.5 タイマー（DestinationActive / DestinationExpired）

`DestinationActive` 状態のタイマーは**在線開始時（`short` が false→true に変化したとき）に初めてカウントダウンを開始**します（旧設計のroute commit時開始から変更）。

タイマーが `-1` 以下になると `DestinationExpired` に遷移します。`DestinationExpired` の解除条件は `RouteLock` と同じです（在線なし かつ `CheckUnlockRouteLock` 成立）。

### 3.6 仮予約の適合条件

#### 進路鎖錠・着点・過走防護トラック用（`is_ready_for_book_temporary`）

```
メイン == NoBook
  または  メイン == Temporary(同てこ)
  または  メイン == Start(同方向)
AND
サブ == NoBook  または  サブ == RouteOver(同方向)
```

`メイン == Start(同方向)` の許容は継続進行（前方進路の着点トラックが後方進路の発点トラックと同一）に対応するためのものです。前方信号が既に発点として `Start` を書き込んだトラックに対し、後方信号が同一方向で着点仮予約を行えるようにします。この節は `is_booked_temporary`（本予約確定チェック）にも同様に存在します。方向が一致する場合のみ許容し、**対向方向は排除**します（対向進路が同時に進行現示を得るのを防ぐ安全上の要件）。`book_temporary()` は `book == NoBook` のときのみ書き込むため他てこの `Start` を上書きせず、`book_destination()` も `Temporary`（同一てこ）のときのみ `book` をクリアするため、既存の `Start` 予約は保持されます。

#### 発点トラック用（`is_ready_for_book_start`）

```
メイン == NoBook  または  メイン == Temporary(同てこ)  または  メイン == Start(同てこ)
AND
サブ == NoBook
  または  サブ == DestinationExpired（方向問わず）
  または  サブ == DestinationActive（同方向のみ）
```

---

## 4. Signal（進路てこ）

Signal は継電連動装置の**進路てこ＋信号機リレー群**に相当します。

### 4.1 主要フィールド

| フィールド | 説明 |
|-----------|------|
| `input` | てこの物理的な操作状態（true=反位） |
| `HR` | 信号扛上リレー。true のとき信号は進行現示可能 |
| `ASR` | 自動復位リレー。true のとき進路・転てつ機操作が可能 |
| `MSlR` | 時素リレー。接近・保留鎖錠のタイマーを制御 |
| `TSSlR` | 進入確認リレー。列車が進路に進入したことを示す |
| `aspect` | 現在の信号現示（0=停止、前ティックの `nextAspect`） |
| `nextAspect` | 今ティックで計算した次の信号現示 |
| `timerTick` | 接近・保留鎖錠のタイマー値 |

### 4.2 各リレーの条件

#### TSSlR（進入確認リレー）
```
TSSlR = NOT(HR) AND NOT(ASR) AND isEnterRoute
```
列車が防護区間に進入したことを示す。HR落下後、進入前は false。

#### ASR（自動復位リレー）
```
ASR = NOT(HR) AND NOT(ZR) AND (接近なし OR TSSlR OR 既にASR OR タイマー終了)
```
ASRが true のときに限り、進路設定・転てつ機操作が可能。  
**落下条件**：信号が進行（HR=true）または進路鎖錠が成立（ZR=true）  
**扛上条件**：信号停止 かつ 進路鎖錠不可（てこ入力OFF or 分岐器条件不成立）のとき、接近なし or 進入済み or タイマー終了

#### MSlR（時素リレー / 接近・保留鎖錠タイマー）
```
MSlR = NOT(HR) AND NOT(ZR) AND NOT(ASR) AND NOT(isEnterRoute) AND (タイマー未作動 OR 既にMSlR)
```
MSlR が true の間 `timerTick` がインクリメントされる。  
`timerTick >= lockTime` になると `isTimerEnd()` が true となり ASR が扛上できる。

#### HR（信号扛上リレー）
```
HR = ZR AND isLocked AND checkWLR AND NOT(TSSlR) AND NOT(ASR) AND isNoShort
```
- `ZR`：てこ入力あり かつ 分岐器が正当方向（`checkSwitches`）
- `isLocked`：routeLock・overrunLock 全区間が RouteLock 状態
- `checkWLR`：関連分岐器が全て転換可能（in_track に在線なし・鎖錠なし）
- `NOT(TSSlR)`：列車未進入
- `NOT(ASR)`：進路鎖錠が成立中
- `isNoShort`：signalTrack に在線なし

### 4.3 進路設定のシーケンス

1. **てこ反位**（`setInput(true)`）
2. **分岐器転換**（`siteSwitchAssert` 成立時）：R が true になり `switch:move()` を呼ぶ
3. **仮予約**（`ZR` が true かつ `bookTemporary` 成功）：発点・routeLock・着点・overrunLock をすべて `Temporary`（または発点サブ互換確認）に。全区間のチェックがアトミックで行われ、1つでも不成立なら全体をスキップ。
4. **本予約確定**（`NOT(ASR)` かつ `isBookedTemporary` 成立）：発点→`Start`（メイン）、routeLock→`RouteLock`（メイン）、着点→`DestinationActive`（サブ）、overrunLock→`RouteOver`（サブ）に格上げ
5. **HR扛上**（鎖錠完成・全条件成立）→ 信号進行現示
6. **列車進入**（`isEnterRoute` が true）→ `TSSlR` が上がり、次ティックで `input = false`（自動復位）
7. **進路解除**（列車通過後、`CheckUnlockRouteLock` 連鎖で順次 `NoBook` に）
   - 発点：Signal.ASR 扛上で即時解除（在線有無問わず）
   - routeLock：在線なし かつ 前要素解除済み
   - DestinationActive：列車到達でタイマー開始 → タイマー満了 → `DestinationExpired` → 在線なし かつ 前要素解除済み → NoBook

#### 仮予約チェック順序（`bookTemporary`）

```
発点 is_ready_for_book_start? → routeLock(各) is_ready_for_book_temporary?
→ 着点 is_ready_for_book_temporary? → overrunLock(各) is_ready_for_book_temporary?
→ 全通過なら順に書き込み
```

対向進路の排他はこのチェックで実現されます。例：NHB2R が仮予約を試みたとき、発点（HLT_NHB1T）のサブが `DestinationActive(逆方向)` であれば `is_ready_for_book_start` が false を返し仮予約全体がスキップされます。

### 4.4 `isEnterRoute()` の動作

防護区間への列車進入を判定します。

- `routeLock` が空 かつ `signalTrack[1]` あり → `signalTrack[1]` の在線で判定
- `routeLock` が空 かつ `signalTrack` も空 → 常に `true`（進入済みとみなす）
- `routeLock[1]` のみ → `routeLock[1]` の在線で判定
- `routeLock[2]` 以上あり → `routeLock[1] AND routeLock[2]` 双方の在線で判定

### 4.5 `updateCallback`

`HR` が true の場合に限り `updateCallback` の戻り値が `nextAspect` に採用されます。`HR` が false なら `nextAspect = 0`（停止）に強制されます。

`res/utils.lua` に標準的なコールバックファクトリが定義されています：

| 関数 | 現示数 | 動作 |
|------|--------|------|
| `StandardAspectCallback_2nd` | 2現示 | `HR=true` → 指定aspect、停止 |
| `StandardAspectCallback_3rd_G_Y_R` | 3現示 | 次信号が進行中かつ自信号も進行中なら4、そうでなければ2 |
| `StandardAspectCallback_3rd_multi` | 3現示（複数次信号） | 次信号のいずれかが進行中かつ自信号も進行中なら4 |

`aspect` は前ティックの値（`before_process()` で確定）、`nextAspect` は今ティックの計算値です。次信号の `aspect` を参照することで1ティック遅れの連動現示を実現しています。

### 4.6 総括制御（`controls`）

`controls` に列挙されたてこに対して、自てこの `setInput()` が多段に連鎖します（A→B→C のような多段制御が機能します）。

`controls` グラフの循環（A→B→A など）はビルド時（`generate_signal.js`）に DFS で検出されてエラーになります。このためランタイムでは循環による無限ループは発生しません。

### 4.7 過走防護フォールバック（`overrunLockFallback` / `HyR`）

過走防護区間（`overrunLock`）が仮予約できない場合、通常はてこ全体の仮予約が失敗し、信号は停止現示のまま固まります。`overrunLockFallback`（TOML: `overrun_lock_fallback = true`）を有効にした信号てこに限り、過走防護区間の仮予約が失敗しても発点・進路鎖錠・着点の本予約は進行させます。現示番号（何を出すか）はコア側では決めず、`update_callback` 側で `lever.HR`・`lever.HyR` を参照して決定します（コアは `nextAspect` を数値としてクランプすることはせず、`HR`・`HyR` がともに false のときのみ強制的に 0 にします）。

#### `bookTemporary` の変更点

過走防護区間だけを別枠でチェックするようにし、オール・オア・ナッシングの対象から外します。

```
発点 is_ready_for_book_start? → routeLock(各) is_ready_for_book_temporary?
→ 着点 is_ready_for_book_temporary?              ← ここまでは従来通りアトミック
→ overrunLock(各) is_ready_for_book_temporary?    ← 結果を overrunReady に記録するのみ
→ overrunReady が false かつ overrunLockFallback が false → 全体スキップ（従来通り）
→ それ以外は発点・routeLock・着点を書き込み
→ overrunReady が true のときだけ overrunLock も書き込む（フォールバック時は過走防護区間を空けておく）
```

`overrunLockFallback` が有効でも `overrunReady` が false の場合、過走防護区間の `book_temporary()` 呼び出しは一切行いません。これにより、他進路や開通てこ（6.7節参照）がその区間を引き続き利用できます。

#### `isBookedTemporary` の変更点

`overrunLockFallback` が true の信号は、`isBookedTemporary` で過走防護区間の成否チェックをスキップし、常に成立したものとして扱います（発点・routeLock・着点の判定は従来通り必須）。これにより、過走防護区間の仮予約が成立していなくても本予約への格上げ（発点・進路鎖錠・着点）が進みます。

一方、`isLocked`（`HR` の判定に使われる）は `overrunLockFallback` の有無に関わらず一切変更していません。`isLocked` は内部で `isRouteLocked`（発点・進路鎖錠・着点のみ）と `isOverrunProtected`（過走防護区間のみ）の論理積として再構成しましたが、意味的には元の実装と完全に同一です。

#### 本予約確定時の安全ガード

`Signal:process()` の本予約格上げブロックでは、過走防護区間への `book_over_run()` 呼び出しに以下のガードを追加しています。

```lua
for _, track in ipairs(self.overrunLock) do
    local t = nt:get_track(track)
    if t:is_booked_temporary(self.itemName, nt) and not t:is_over_run_lock(self.itemName, nt) then
        t:book_over_run(self.itemName, nt)
    end
end
```

- `is_booked_temporary`：自分が確かにその区間を仮予約できている場合のみ本予約に格上げする（フォールバックで見送った区間は対象外）。
- `not is_over_run_lock`：既に（開通てこ経由などで）保護が成立している区間は、所有権を奪って `book_over_run()` を呼び直さない（6.7節参照）。

#### HR / HyR（信号扛上リレー / 警戒信号現示リレー）

`HR` は元の定義から一切緩めていません。`signal.toml` に記載された `overrunLock` の全区間が予約できている場合にのみ true になります（`overrunLockFallback` の有無に関わらず同一の判定です）。

`HyR`（警戒信号現示リレー）は次のように定義される、`HR` とは独立した新設のリレーです。

```
baseOk = ZR AND checkWLR AND (NOT TSSlR) AND (NOT ASR) AND isNoShort   -- 過走防護の成否を含まない共通条件
HR     = baseOk AND isLocked(nt)                                       -- isLocked = isRouteLocked AND isOverrunProtected(元の定義のまま)
HyR    = HR OR (baseOk AND overrunLockFallback AND isRouteLocked(nt))
```

`HR` が成立していれば `HyR` は論理和の左辺により必ず true になります（`HR=true` かつ `HyR=false` という組み合わせは構造的に存在しません）。加えて、`overrunLockFallback` が有効な信号てこに限り、過走防護区間が予約できていなくても、進路鎖錠（発点・進路鎖錠・着点、`isRouteLocked`）さえ成立していれば `HyR` が true になります。

コア側の処理は `HyR` を上記の通り計算すること以上は行いません（`nextAspect` を数値としてクランプすることはしません）。ただし最終的な強制停止条件は `HR` 単独ではなく `HR OR HyR` に変更されています。

```lua
self.nextAspect = self:updateCallback(nt, deltaTick)
if not (self.HR or self.HyR) then
    self.nextAspect = 0
end
```

`update_callback` は `lever.HR`・`lever.HyR` の両方を参照して現示番号を自分で決定します。典型的な書き方は次の通りです。

```lua
update_callback = 'function(lever, nt, dt) if lever.HR then return 4 elseif lever.HyR then return 1 else return 0 end end'
```

### 4.8 AutoSignal

`Signal` の簡略版で、てこ入力・進路鎖錠機能を持たず、**在線なし（signalTrack全て空）→ HR=true** の単純なルールで現示を計算します。`HR` は `new()` では初期化されず、初回 `process()` で設定されます。

---

## 5. Switch（転てつ機）

### 5.1 フィールド

| フィールド | 説明 |
|-----------|------|
| `W` | 要求位置（Wanted）。`move()` で設定、毎ティック `before_process()` でリセット |
| `K` | 実位置（Known/Actual）。`before_process()` で外部から注入 |
| `isSite` | 現場扱い（true）か連動扱い（false）か |

### 5.2 `before_process(currentState)`

毎ティック、SoyaBridge が実際の分岐器位置を `K` に注入し、`W` を `Indefinite` にリセットします。

### 5.3 `move(target, nt)`

`getWLR(nt)` が true（転換可能）のとき `W = target` を設定します。W は SoyaBridge が読み取り、ゲームの分岐器制御コマンドに変換します。

### 5.4 `getWLR(nt)`（転換可能条件）

関連軌道（`relatedTracks`）のいずれかが：
- 在線中（`is_short()`）、または
- 鎖錠中（`is_locked(not isSite)`）

であれば `false`（転換不可）。全て空のとき `true`。  
`isSite = true` の場合、`is_locked(false)` → `Temporary` も鎖錠とみなします。  
`isSite = false` の場合、`is_locked(true)` → `Temporary` は鎖錠とみなしません。

### 5.5 `checkSwitches()`（Signal側から呼ばれる）

`SwitchRoute:check(nt)` は `K != target` のとき `true`（異常）を返します。`checkSwitches()` は全て `false`（正常）のとき `true` を返します。つまり「全分岐器が要求方向に転換済み」の確認です。

---

## 6. 運転方向制御（TrafficDirectionLever と TrafficDirectionSwitch）

### 6.1 設計の目的

単線区間では上下列車が同一の線路を共用するため、一度に1方向の列車しか在線させてはならない。N-TRACS Core はこれを「方向てこ（TrafficDirectionLever）」と「仮想方向分岐器（TrafficDirectionSwitch）」の組み合わせで実現します。

### 6.2 仮想方向分岐器（TrafficDirectionSwitch）の役割

`TrafficDirectionSwitch` は**物理的な転てつ機ではなく、現在の運転方向を保持するソフトウェアレジスタ**です。区間の両端（駅A・駅B）にそれぞれ1つ置かれます。

通常の `Switch` との違い：

| | Switch（通常） | TrafficDirectionSwitch（仮想） |
|--|--------------|-------------------------------|
| `getRealRoute()` | `K`（物理フィードバック）を返す | `W`（最後に指令した方向）を返す |
| `before_process()` | `K = currentState`, `W = Indefinite` にリセット | `K = W` のみ（`W` はリセットしない） |

`W` をリセットしないのは意図的です。仮想方向分岐器は**一度方向が設定されたら保持し続ける**必要があります。物理フィードバックがないため `K = W`（実位置＝指令位置）とします。

**設定上の制約**：仮想方向回線は両端のスイッチで **同じ方向値を使う** 必要があります。例：A→B 方向を Reverse で表すなら A側・B側ともに Reverse を使います。両端で異なる値を使うと出し側のチェックが永遠に成立しません。

### 6.3 方向てこ（TrafficDirectionLever）の設計方針

- **反位＝出し側**、**定位＝受け側**という1方向専用のてこ
- 受け/出しの役割はてこ自体が持たず、現在のてこ位置（反位/定位）によって動的に決まる
- 閉塞区間の両端に1本ずつ配置し、操作員または信号てこの総括制御によって操作される

`process()` の動作：

**定位（input=false）= 受け側**：逆方向（`-myFrDirection`）を無条件で自端スイッチに書き込む。
```
myFrName.move(-myFrDirection)
```
受け側が逆方向を書き込むことで、出し側チェックが成立する値をセットします。

**反位（input=true）= 出し側**：相手端スイッチが `myFrDirection` を向いていることを確認してから書き込む。
```
if anotherFrName.getRealRoute() == myFrDirection then
    myFrName.move(myFrDirection)
end
```
てっ査鎖錠は `move()` 内の `getWLR()` が担います（中間在線中は転換不可）。

`SetRoute` の値は `Normal=1`, `Reverse=-1` なので `-myFrDirection` が対向方向を表します。

### 6.4 動作シーケンス（総括制御なし）

現在 B→A 方向で運転中（A が定位・B が反位）の状態から A→B に転換する例：

| ティック | A（myFrDirection=Normal） | B（myFrDirection=Reverse） |
|---------|--------------------------|--------------------------|
| 転換前 | 定位: switchA に -Normal=Reverse を書き続ける | 反位: switchA==Reverse を確認→switchB に Reverse を書き続ける |
| 転換操作 | A が反位になる | B が定位になる |
| 転換後 | 反位: switchB==Normal を確認→成立→switchA に Normal を書く | 定位: switchB に -Reverse=Normal を書き始める |

B が定位になると switchB に Normal が書かれ始め、A の確認チェックが成立します。

### 6.5 総括制御による方向てこ操作

信号てこの `controls` に両端の方向てこを登録することで、信号てこ1操作で両端の方向てこを同時制御できます。

### 6.6 出発信号てこと仮想方向分岐器の組み合わせ

#### checkWLR との関係

`Signal.checkWLR()` は `switches[]` に列挙した分岐器の `getWLR()` が**すべて false**（転換不可）のとき `true` を返し、HR 扛上を許可します。これは「信号を開く前に分岐器が鎖錠されていること」を保証するための条件です。

`TrafficDirectionSwitch.getWLR()` は**常に false を返します**。物理分岐器とは異なり、仮想方向分岐器は「在線・鎖錠がないと転換可能」という WLR 条件を信号に課しません。`checkWLR()` は常に通過します。

代わりに、転換の棄却は `move()` 内で独自に判定します。在線・鎖錠があれば `W` の書き換えを行いません。

```
Signal.checkWLR() → TrafficDirectionSwitch.getWLR() = false（常に）→ checkWLR 通過
方向転換要求     → TrafficDirectionSwitch.move()
                   → 区間在線 or 鎖錠あり → 棄却（W 変更なし）
                   → 区間空き           → W 更新（転換）
```

#### signal.toml の記述パターン

```toml
[NHB2L]
start       = "NHB5LT"
destination = "HLT_NHB1T"
direction   = "right"
switches    = [{ sw = "NHB_HLT_FR", t = "reverse" }]  # 自駅側方向分岐器の位置確認
route_lock  = []
...
extra_controls = ["NHB1L"]                          # 方向てこを総括制御
```

`route_lock` は空でよい。`destination` が Destination 状態に遷移した時点で `TrafficDirectionSwitch.move()` が棄却され、列車通過まで方向転換できなくなります。

#### 鎖錠の時系列

| 状態 | 単線区間（destination/サブ） | 方向分岐器 |
|------|---------------------------|-----------|
| 出発前（てこ定位） | NoBook | 転換可 |
| てこ反位・仮予約フェーズ | Temporary（メイン） | 転換不可（is_locked により move() 棄却） |
| 本予約確定後 | DestinationActive（サブ） | **転換不可** |
| 列車到達・過走防護タイマー計測中 | DestinationActive（在線・タイマー進行中） | 転換不可 |
| タイマー満了 | DestinationExpired | 転換不可（サブに予約残存） |
| 列車通過後・前要素解除済み | NoBook（サブ・メイン共） | 転換可 |

逆方向進路（対向）は `DestinationActive` の間は発点仮予約が `is_ready_for_book_start` でブロックされます。タイマー満了（`DestinationExpired`）後は逆方向の発点でも上書き可能になります。

### 6.7 開通てこ（OpeningLever）

`OpeningLever` は信号を現示しない新しいてこ種別です。TOML固定方向で、指定した過走防護区間（`overrun_lock` と同じ意味の抽象軌道回路群）を「デフォルトで開通させておく」ことを宣言します。

- `Signal.new()` が `SignalBase.new()` をベースにミックスインするのと同様、`OpeningLever.new()` も `NtracsObject.create_instance(SignalBase.new(), OpeningLever)` を使い、`SignalBase` の機能（`process`/`before_process` の抽象定義など）をベースにします。
- `process()` は毎ティック、対象の各 `overrun_lock` トラックについて `Track:is_claimable_for_opening(itemName)`（空き、または既に自分自身が保持している）を確認し、成立していれば `Track:book_opening(itemName, nt)` で `bookDest` を `RouteOver` に書き込みます。`book` フィールド（メイン）には一切触れません。
- `under_route_lock_b()` は常に `false` を返します。これにより、開通てこが保持している区間は在線解除だけでは自動的に解放されません（実信号機の本予約で明示的に上書きされるまで保持し続けます）。
- `is_opening_lever()` は `true` を返します。これは他のオブジェクトから「このてこが開通てこかどうか」を判別するための目印メソッドです。

#### 所有権の非対称性（上書きされる場合・されない場合）

開通てこが `RouteOver` で保持している区間は、**その区間を実際の進路（`route_lock`/`destination`）として使う内方の信号機**には自然に上書きされますが、**その区間を過走防護区間（`overrun_lock`）として使うだけの外方の信号機**には所有権を奪われません。

- **上書きされる（内方信号機が `destination` として使う場合）**：`Signal:process()` の本予約確定ブロックは `nt:get_track(self.destination):book_destination(...)` を無条件に呼び出します。`book_destination()` は `bookDest` を無条件で `DestinationActive` に書き換えるため、開通てこの `RouteOver` 予約は自然に明け渡されます。
- **上書きされない（外方信号機が `overrun_lock` として使うだけの場合）**：4.7節で述べた安全ガード（`is_booked_temporary and not is_over_run_lock` のときのみ `book_over_run()` を呼ぶ）により、既に `is_over_run_lock` が成立している区間には `book_over_run()` を呼びません。開通てこが保持する区間に対して `is_over_run_lock` が成立するよう、`Track:is_over_run_lock()` を以下のように拡張しています。

```lua
function Track:is_over_run_lock(lever, nt)
    local dir = nt:get_signal(lever).direction
    if self.bookDest == BookType.RouteOver and self.destRelatedLever == lever then
        return true
    end
    if self.book == BookType.RouteLock and self.direction == dir then
        return true
    end
    -- 開通てこが方向一致で保持している場合も鎖錠成立とみなす
    if self.bookDest == BookType.RouteOver and self.destDirection == dir then
        local owner = nt:get_signal_may_nil(self.destRelatedLever)
        if owner and type(owner.is_opening_lever) == "function" and owner:is_opening_lever() then
            return true
        end
    end
    return false
end
```

`type(owner.is_opening_lever) == "function"` のガードは、`destRelatedLever` が偶然 `is_opening_lever` を持たないオブジェクトを指していてもエラーにしないための防御です（`Signal:setInput()` の `type(signal.setInput) == "function"` と同じパターン）。`AutoSignal` は `NtracsObject.create_instance({}, AutoSignal)` と素の `{}` をベースにしており `SignalBase` の関数を継承しないため、`is_opening_lever` を持ちません。

#### `Track:book_opening()` が専用関数である理由

既存の `book_over_run()` をそのまま流用すると、`destBeforeRouteLockItem` に `nt:get_signal(lever).destination` を設定しようとして `nil` になります（開通てこには `destination` フィールドが存在しないため）。`destBeforeRouteLockItem` が `nil` だと `CheckUnlockRouteLock` が `true` を返し、非在線時に毎ティック自動解放されてしまいます。そこで開通てこ専用の `book_opening()` を新設し、`destBeforeRouteLockItem` に開通てこ自身（`lever`）を設定します。`OpeningLever:under_route_lock_b()` が常に `false` を返すため、`CheckUnlockRouteLock` は常に `false` となり、実信号機に明示的に上書きされるまで保持され続けます。

```lua
function Track:book_opening(lever, nt)
    self.bookDest = BookType.RouteOver
    self.destRelatedLever = lever
    self.destBeforeRouteLockItem = lever
    self.destDirection = nt:get_signal(lever).direction
end
```

#### TOML設定例

```toml
[XXXX_OPL]
opening_lever = true
direction = "right"
overrun_lock = ["XXX1T", "XXX2T"]
```

ビルド時（`build/generate_signal.js`）に `data.opening_lever === true` のエントリは `SoyaBridge:create_opening_lever()` を呼ぶ専用コードに変換されます。`index.js` の `detectOpeningLeverConflicts()` は、複数の開通てこが同一トラックを対象区間として重複宣言していないかをビルド時に検証します。

---

## 7. SignalRoute の拡張値

`SwitchRoute.check()` では `K != target` で判定しているため、`SignalRoute` の拡張値（`Onewaynormal`, `Onewayreverse`, `Bothway`）は **`SetRoute`（1/-1/0）と数値が一致しない** ため、通常の `checkSwitches()` では正しく比較できません。これらの値の用途は現状コードからは不明です。

---

## 8. 信号現示の数値体系

コールバックが返す数値の意味はゲーム側（SoyaBridge）が解釈しますが、`res/utils.lua` の実装から以下が読み取れます。

| 値 | 意味（推定） |
|----|------------|
| 0 | 停止（赤） |
| 2 | 注意（黄）または進行（2現示の場合） |
| 4 | 進行（青/緑） |

---

## 9. 主要な設計上の特徴・制約

1. **ステートレスな更新関数**：各オブジェクトの状態遷移は `process()` の冪等性を前提としています。同一入力・同一状態から必ず同一の次状態が得られます。

2. **連鎖解除の依存性**：進路鎖錠の解除は `beforeRouteLockItem` を辿る連鎖で行われます。中間の軌道が欠落すると鎖錠が永久に解除されません（H-3）。

3. **before_process の責務**：`before_process()` は「外部の物理状態をコアに注入する」フェーズです。`process()` はこの注入済み値だけを読みます。これにより1ティック以内でコアが一貫した状態を持ちます。

4. **`aspect` の1ティック遅延**：`updateCallback` が参照する `self.aspect` は前ティックの確定値です。次信号の `aspect` も同様に前ティックの値です。これは連鎖現示（黄→青の伝播）が1ティック遅れることを意味します。設計上許容されています。
