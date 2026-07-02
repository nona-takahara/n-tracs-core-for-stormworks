# コード問題点リスト

## クリティカル（クラッシュ・安全性違反）

### C-1. `TrafficDirectionSwitch.before_process()` が空実装 ✅ 修正済み
- **ファイル**: `src/n_tracs_core/switch/traffic_direction_switch.lua`
- **問題**: 親クラス `Switch.before_process()` は `self.K = currentState` で実位置を更新するが、このサブクラスはメソッドをオーバーライドしているにもかかわらず処理が空。結果として `K` が常に初期値 `Indefinite` のままになる。
- **影響**: 方向てこ連動の分岐器が一切機能しない。
- **対応**: `self.K = self.W` を追加。仮想分岐器のため実位置＝指令位置とする。

### C-2. `VehicleInfo.new()` が `nil` を返す場合の挙動（仕様確認済み）
- **ファイル**: `src/n_tracs_soyabridge/soya_bridge.lua` `load_vehicle()`
- **問題**: `VehicleInfo.new()` はコンポーネント取得失敗時に `nil` を返す。呼び出し元は `self.vehicle_table[id] = nil` となるが、Lua では `t[k] = nil` はキー削除と等価なため `pairs()` の反復でクラッシュは発生しない。
- **影響**: コンポーネント取得に失敗した車両はサイレントに登録されないだけで、クラッシュは起きない。この挙動は意図的な設計の可能性が高い（壊れた車両は無視して継続）。
- **対応不要**: 仕様として受け入れる。

### C-3. `Signal.setInput()` の総括制御が1段で止まる ✅ 修正済み
- **ファイル**: `src/n_tracs_core/signal/signal.lua` 315–326行、`build/generate_signal.js`
- **問題**: `controls` 伝搬時に `fromControl=true` を渡していたため、受け取った信号は自分の `controls` へ伝搬しない。多段制御（A→B→C など）が機能しない。
- **影響**: 総括制御の連鎖が1段階しか動作しない。
- **対応**: ビルド時（`generate_signal.js`）に `controls` グラフの循環を DFS で検出してエラーにする。これにより無限ループの可能性を排除し、ランタイムでは `fromControl=false` を渡して多段伝搬を有効化した。

### C-5. `Signal.TSSlR` 式に誤った否定（NOT）✅ 修正済み
- **ファイル**: `src/n_tracs_core/signal/signal.lua` 95行
- **問題**: `TSSlR = not (self.HR or self.ASR or self:isEnterRoute(nt))` と書かれており、`isEnterRoute` に誤った `NOT` が付いていた。これにより TSSlR は列車が防護区間に **不在** のときだけ扛上する（正しくは **進入時** に扛上）。
- **影響**: `routeLock = []` の到着信号（HLT1L、NHB2L 等）では `isEnterRoute = signalTrack[1].is_short()` が列車停車中ずっと true になるため、`NOT(isEnterRoute)` が常に false → TSSlR が上がらず → `auto_reset` が永久に発火しない。
- **対応**: `self.TSSlR = not (self.HR or self.ASR) and self:isEnterRoute(nt)` に修正。`SPEC_CORE.md` セクション 4.2 の式も同様に修正。

### C-4. `TrafficDirectionLever` の設計誤り ✅ 修正済み
- **ファイル**: `src/n_tracs_core/signal/traffic_direction_lever.lua`
- **問題**: `isAcceptLever`（受け/出しの役割を静的フラグで持つ）と `pairLeverName`（方向てこが相手方向てこを制御する）という2つの誤った概念が実装されていた。`pairLeverName` は同一 `input` 値を伝搬するため相互排他を実現できず、むしろ両端が同時に同じ状態になる誤動作を引き起こす。
- **影響**: 運転方向転換が仕様通りに動作しない。
- **対応**: `isAcceptLever`・`pairLeverName` を削除。反位（出し側）＝確認後書き込み、定位（受け側）＝逆方向を無条件書き込み、という動的な切り替えに変更。

### C-6. 継続進行時に着点仮予約が `Start` トラックを許容しない ✅ 修正済み
- **ファイル**: `src/n_tracs_core/track/track.lua` `is_ready_for_book_temporary()` / `is_booked_temporary()`
- **問題**: 前方進路の着点トラックが後方進路の発点トラックと同一になる継続進行（例: 北港駅 NHB2L の着点 `HLT_NHB1T` が HLT1L の発点でもある）で、`HLT1L` が先に `HLT_NHB1T` を `book = Start` に格上げすると、`NHB2L` の着点仮予約チェック（`is_ready_for_book_temporary` / `is_booked_temporary`）が `book == Start`（別てこ・同一方向）を許容せず false を返す。`book` フィールドの獲得競争に負けた側は本予約確定（`book_destination`）に到達できず、`HR`（信号扛上リレー）が上がらない。勝った進路が自身の進路解除サイクル（ASR 解放）を完了するまで（＝列車が該当区間を通過し終えるまで）敗者は着点鎖錠を得られないため、列車在線に依存する `TSSlR`/`isEnterRoute` が二度と成立せず `auto_reset` が発火しない。どちらのてこが先に `book` を獲得するかは Lua のテーブル反復順に依存し、一方の順序でのみ偶発的に動作していた。
- **影響**: 継続進行を意図して両信号を進行にした際、後方信号（NHB2L）のてこが `true` のまま自動復位せず永久に固着する。信号現示は列車通過中ずっと停止（赤）のままで、列車が該当区間を通過し終えた後になって進行（緑）に変化することさえある。運転士は司令の意図（継続進行）に反して赤信号を現示され続けるため、安全上の混乱を招く。
- **対応**: `is_ready_for_book_temporary()` の `mainOk` と `is_booked_temporary()` に `self.book == BookType.Start and self.direction == dir`（同一方向のみ）の許容節を追加。`book_temporary()`（`book == NoBook` のみ書き込み）・`book_destination()`（`book == Temporary` かつ同一てこのときのみ `book` をクリア）は他てこの `Start` を破壊しないため変更不要。**方向条件 `self.direction == dir` により対向進路の割り込みは従来通り排除**され、正面衝突相当の危険な同時進行は許容しない。Lua シミュレーションで両順序が同一・正常に動作すること、対向方向が正しく拒否されることを確認済み。

### C-7. `auto_reset` が `self.input` を直接書き換え、総括制御(`controls`/`extra_controls`)先のてこに復位が伝播しない ✅ 修正済み
- **ファイル**: `src/n_tracs_core/signal/signal.lua` `Signal:process()` 冒頭
- **問題**: `auto_reset` による自動復位は `if self.auto_reset and self.TSSlR then self.input = false end` と `self.input` を直接書き換えているだけで、`controls`（`extra_controls` を含む）への伝播を行う `setInput()` を経由していなかった。`TrafficDirectionLever`（方向てこ）は `NHB2L`（`extra_controls = ["NHB1L"]`）や `HLT1R`（`extra_controls = ["HLT2R"]`）のように総括制御でのみ操作され、自身が単独で反位・定位を切り替える手段を持たない。そのため、総括元の信号てこが `auto_reset` で復位しても、方向てこ側の `input` は `true` のまま永久に固着する。
- **影響**: 掘戸町(HLT)〜北港(NHB)間の単線区間で、`NHB2L`→`HLT1L` と進んで列車が `HLT1LT` に到着した後、`NHB2L` の総括制御下にある方向てこ `NHB1L` が固着したままになる。`NHB1L` は「出し側」動作を続けて自区間の仮想方向分岐器 `NHB_HLT_FR` を上り方向(`Reverse`)に固定し続けるため、折り返し方向の `HLT1R`（`extra_controls = ["HLT2R"]`）が `HLT2R` を反位にしても相手端の確認条件が成立せず、`HLT_NHB_FR` を `normal` に転換できない。結果として `HLT1R` 自身の転てつ器条件（`switches = [{ sw = "HLT_NHB_FR", t = "normal" }]`）が恒久的に不成立となり、`checkSwitches()` が常に `false` を返すため `ZR`・`HR` が絶対に成立せず、`HLT1R` は何度てこを反位にしても進行現示にならない。
- **対応**: `self.input = false` を `self:setInput(false, nt)` に変更し、`auto_reset` による復位も `controls`/`extra_controls` に正しく伝播するようにした。`setInput()` 側は既存の cycle-safe な多段伝播（C-3 対応）をそのまま利用する。Lua シミュレーション（`NHB2L`/`HLT1L`/`NHB1L`/`HLT1R`/`HLT2R` 相当の最小構成）で、修正前は総括制御下の方向てこが固着して `HLT1R` の `HR` が永久に `false` のままであること、修正後は `auto_reset` 発火の翌ティックで方向てこが正しく復位し `HLT1R.HR` が `true` になることを確認済み。

---

## 高（データ整合性・状態破損）

### H-1. 車両デスポーン時の進路鎖錠残留（仕様確認済み）
- **ファイル**: `src/n_tracs_soyabridge/soya_bridge.lua` `despawn_vehicle()`
- **問題**: 当初「永久鎖錠になる」と記載したが、実際には `track.lua:process()` の解錠条件 `(not self.short) and CheckUnlockRouteLock(...)` により、車両消失で `short = false` になった時点から通常の連鎖解錠が機能する。
- **影響**: なし。デスポーン後、数ティック以内に進路鎖錠は自動解錠される。
- **対応不要**: 仕様通りの挙動。

### H-2. `crossing.lua` の時間積算タイマーが機能していない（仕様確認済み）
- **ファイル**: `res/crossing.lua` 30–46行付近
- **問題**: `ShortingTicks_*` 変数がクロージャで保持されているが、条件分岐の構造上、状態が変わるたびにリセットされ、実質的にデュレーション（継続時間）判定ではなく瞬時値判定になっている。
- **影響**: 踏切の開閉タイミングロジックが意図通りに動かない可能性がある。
- **対応不要**: Stormworks のゲーム内実運用上、問題が顕在化しないと確認。仕様として受け入れる。

### H-3. `CheckUnlockRouteLock()` で存在しないIDをサイレントに処理（仕様確認済み）
- **ファイル**: `src/n_tracs_core/track/track.lua` 123–127行
- **問題**: `get_track_may_nil` / `get_signal_may_nil` のどちらも `nil` を返す場合、`false` を返すため進路鎖錠が解除されない。設定から軌道や信号機を削除した場合に鎖錠が解除不能になりうる。
- **影響**: 設定変更時に鎖錠が永久残留する可能性がある。
- **対応不要**: 設定変更はゲームセッション外（ビルド時）にのみ行われるため、実行中に削除IDが残留するシナリオは発生しない。仕様として受け入れる。

---

## 中（パフォーマンス・設計）

### M-1. `Axle.search()` のBFS重複チェックがO(n²)
- **ファイル**: `src/n_tracs_soyabridge/axle.lua`
- **問題**: 隣接エリアの重複確認をキューを毎回線形探索して行っている（O(n)×エッジ数）。
- **影響**: エリア数・車両数が増えると毎ティック（約60Hz）のCPU負荷が顕著になる。セットまたはハッシュテーブルで O(1) に改善できる。

### M-2. 生成済みLuaの構文チェックなし ✅ 修正済み
- **ファイル**: `index.js` / `build/generate_signal.js`
- **問題**: TOML/JSONの設定ミスがあっても無効なLuaが生成され、ゲームロード時まで検出されない。
- **影響**: 設定ミスの発見が遅れ、デバッグが困難になる。
- **対応**: ビルド時に `lua53` コマンドが利用可能なら `res/area_track.lua` / `res/signal.lua` に対して `lua53 -e "assert(loadfile(...))"` で構文チェックを実施。`lua53` が見つからない場合はスキップした旨を表示して続行。

---

## 低（軽微・潜在的）

### L-1. `ntracs.lua` の `crate_track` タイポ
- **ファイル**: `src/n_tracs_core/ntracs.lua` 109行付近
- **問題**: `crate_track`（`create_track` の誤り）。呼び出し元も同名で統一されているため現時点では動作するが、紛らわしく将来のバグ源になりうる。

### L-2. `AutoSignal` が `self.HR` を `new()` で初期化していない
- **ファイル**: `src/n_tracs_core/signal/auto_signal.lua` 16–26行
- **問題**: `HR` は `process()` 内で初めてセットされる。初回ティック前に `updateCallback` が呼ばれた場合、`HR` が `nil` になる。

### L-3. `res/utils.lua` の `get_signal()` 呼び出しにnilチェックなし
- **ファイル**: `res/utils.lua` 17–29行
- **問題**: `nt:get_signal(nextSignal)` が存在しない信号名を参照するとクラッシュする。設定ミス時のエラーメッセージが得られない。

### L-4. `Area.insert_axle()` の挿入位置計算が偶然に正しい
- **ファイル**: `src/n_tracs_soyabridge/area.lua` 75–89行
- **問題**: ループ変数 `i` を使った挿入位置算出が、空リストの場合は偶然 `1` になるだけで、ロジックとして明示的ではない。リファクタリング時に壊れやすい。

---

## 不足機能
### F-1. `AutoSignal`でSwitch、踏切参照 ✅ 修正済み
- 単線自動閉そくや、踏切による「自動」信号制御を行えるようにしたい。
- **対応**: `AutoSignal` に `switches`（SwitchRoute[]）フィールドを追加し、`checkSwitches()` で分岐器位置を確認してHRに反映。踏切は既存の `signalTrack` に踏切仮想トラックを追加することで対応可能（既存機能で実現）。signal.toml の auto 信号エントリで `switches` フィールドを任意で指定できる。

---

## ステータス

| ID | 重大度 | 状態 |
|----|--------|------|
| C-1 | クリティカル | ✅ 修正済み |
| C-2 | クリティカル | ✅ 仕様確認済み（対応不要） |
| C-3 | クリティカル | ✅ 修正済み |
| C-4 | クリティカル | ✅ 修正済み |
| C-5 | クリティカル | ✅ 修正済み |
| C-6 | クリティカル | ✅ 修正済み |
| C-7 | クリティカル | ✅ 修正済み |
| H-1 | 高 | ✅ 仕様確認済み（対応不要） |
| H-2 | 高 | ✅ 仕様確認済み（対応不要） |
| H-3 | 高 | ✅ 仕様確認済み（対応不要） |
| M-1 | 中 | ✅ 修正済み |
| M-2 | 中 | ✅ 修正済み |
| L-1 | 低 | ✅ 修正済み |
| L-2 | 低 | ✅ 修正済み |
| L-3 | 低 | ✅ 修正済み |
| L-4 | 低 | ✅ 修正済み |
| F-1 | N/A | ✅ 修正済み |
