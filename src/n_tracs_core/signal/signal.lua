-- N-TRACS Core [Lever]

local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local SignalBase = require("src.n_tracs_core.signal.signal_base")
local SwitchRoute = require("src.n_tracs_core.signal.switch_route")

---てこに関する操作を行います
---@class Signal:SignalBase
---@field private input boolean てこの入力状態
---@field private auto_reset boolean てこを自動復位するかフラグ
---@field private ASR boolean
---@field private MSlR boolean
---@field private timerTick number
---@field private TSSlR boolean
---@field startTrack string 進路てこ区間の始点
---@field destination string 進路てこ区間の終点
---@field private switches SwitchRoute[]
---@field private routeLock string[]
---@field private approachTrack string[]
---@field private overrunLock string[]
---@field private signalTrack string[]
---@field private controls string[]
---@field lockTime number [CONSTANT]接近・保留鎖錠の時間(Tick)
---@field overrunTime number [CONSTANT]過走防護鎖錠の時間(Tick)
---@field private overrunLockFallback boolean 過走防護区間の仮予約に失敗しても本予約を進めるフラグ(TOML opt-in)
---@field HyR boolean 警戒信号現示リレー。HRがtrueかつ過走防護が完全には成立していない(フォールバックで通した)場合にtrue
---@field aspect number
local Signal = {}

---てこ構造体のインスタンスを作成します
---@param itemName string てこ名称
---@param startTrack string 進路てこ区間の始点
---@param destination string 進路てこ区間の終点
---@param switches SwitchRoute[] 関連する転てつ器と開通方向の組み合わせ情報
---@param routeLock string[] 進路鎖錠を行う抽象軌道回路
---@param overrunLock string[] 過走防護を行う抽象軌道回路
---@param signalTrack string[] 信号現示に関連する抽象軌道回路
---@param direction RouteDirection 進路てこの方向
---@param approachTrack string[] 接近鎖錠を行う抽象軌道回路。保留鎖錠の場合は空テーブル
---@param lockTime number 接近・保留鎖錠の時間(Tick)
---@param overrunTime number 過走防護鎖錠の時間(Tick)
---@param overrunLockFallback boolean 過走防護区間が仮予約できなくても本予約を進めるか
---@param controls string[]|nil このてこが総括制御するてこ名一覧
---@param updateCallback fun(lever: Signal, nt: Ntracs, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
---@return Signal
function Signal.new(itemName, startTrack, destination, switches, routeLock, overrunLock,
                    signalTrack, direction, approachTrack, lockTime, overrunTime, overrunLockFallback, controls, updateCallback)
    local obj = NtracsObject.create_instance(SignalBase.new(), Signal)
    obj.name = "Lever"
    obj.itemName = itemName
    obj.input = false
    obj.ASR = true
    obj.MSlR = false
    obj.timerTick = 0
    obj.TSSlR = false
    obj.HR = false
    obj.aspect = 0
    obj.nextAspect = 0
    obj.startTrack = startTrack
    obj.destination = destination
    obj.switches = switches
    obj.approachTrack = approachTrack
    obj.routeLock = routeLock
    obj.overrunLock = overrunLock
    obj.signalTrack = signalTrack
    obj.controls = controls or {}
    obj.direction = direction
    obj.lockTime = lockTime
    obj.overrunTime = overrunTime
    obj.overrunLockFallback = overrunLockFallback
    obj.HyR = false
    obj.updateCallback = updateCallback
    obj.auto_reset = true
    return obj
end

---毎ループごとに呼び出してください
---@param deltaTick number
---@param nt Ntracs
function Signal:process(deltaTick, nt)
    -- 自動復位モードであり、かつ復位条件を満たす場合
    if self.auto_reset and self.TSSlR then
        self.input = false
    end

    -- てこリレー（閉路鎖錠条件と、総括制御条件を加える必要あり）
    local R = self:getInput() and self:siteSwitchAssert(nt)
    if R then
        for _, rswitch in ipairs(self.switches) do
            nt:get_switch(rswitch.switch):move(rswitch.target, nt)
        end
    end

    -- 進路鎖錠を行えるか確認
    local ZR = self:getInput() and self:checkSwitches(nt)
    if ZR then
        self:bookTemporary(nt)
    end
    -- バックチェックは仮予約機能で代用
    self.TSSlR = not (self.HR or self.ASR) and self:isEnterRoute(nt)

    -- ASRが扛上しているときだけ、この進路に関係する進路や転轍機が操作可能
    -- 「落下中は進路区分鎖錠を行う」と同義
    -- ASR落下条件: 信号が進行 または 進路鎖錠した
    -- ASR扛上条件: 信号が停止 かつ 進路鎖錠不可能 のとき、接近なし or 進入済み or タイマー終了
    self.ASR =
        (not self.HR) and (not ZR) and
        (self:isNoApproach(nt) or self.TSSlR or self.ASR or self:isTimerEnd())

    -- 時素リレー動作は「特開平04-154475」にて、既存の回路で確認
    -- R接点：動作開始で落下
    -- N接点：動作完了で扛上
    self.MSlR =
        (not self.HR) and
        (not ZR) and
        (not self.ASR) and
        (not self:isEnterRoute(nt)) and
        ((not self:isTimerRunning()) or self.MSlR);

    if self.MSlR then
        self.timerTick = self.timerTick + deltaTick
    else
        self.timerTick = 0
    end

    if (not self.ASR) and self:isBookedTemporary(nt) then
        nt:get_track(self.startTrack):book_start(self.itemName, nt)
        -- routeLockの前段(beforeRouteLockItem)に発点トラック(self.startTrack)を使ってはならない。
        -- 発点トラックが前の進路の着点でもある場合(同一トラックが着点→発点)、前の進路の
        -- 過走防護タイマーが切れてbookDest=DestinationExpiredになると、under_route_lock_b()が
        -- trueを返す。この時、列車は発点に在線中(startTrack.short=true)だが、routeLock区間は
        -- まだ不在線(short=false)なので解放条件が成立し、進路鎖錠が在線中に誤解放される。
        -- 前段を信号機自身にすることで、Signal.ASR(信号が赤に戻った)でのみ解放される。
        local routeLockBefore = self.itemName
        for _, track in ipairs(self.routeLock) do
            nt:get_track(track):book_route_lock(self.itemName, routeLockBefore, nt)
            routeLockBefore = track
        end
        nt:get_track(self.destination):book_destination(self.itemName, routeLockBefore, nt)
        for _, track in ipairs(self.overrunLock) do
            local t = nt:get_track(track)
            if t:is_booked_temporary(self.itemName, nt) and not t:is_over_run_lock(self.itemName, nt) then
                t:book_over_run(self.itemName, nt)
            end
        end
    end

    self.HR =
        ZR and
        self:isLocked(nt) and
        self:checkWLR(nt) and
        (not self.TSSlR) and
        (not self.ASR) and
        self:isNoShort(nt)

    self.HyR = self.HR and (not self:isOverrunProtected(nt))

    self.nextAspect = self:updateCallback(nt, deltaTick)
    if not self.HR then
        self.nextAspect = 0
    end
end

---現場扱いのてこが正当方向に転換しているか調べます
---@private
---@param nt Ntracs
---@return boolean
function Signal:siteSwitchAssert(nt)
    for _, sw in ipairs(self.switches) do
        if nt:get_switch(sw.switch).isSite and nt:get_switch(sw.switch).K ~= sw.target then
            return false
        end
    end
    return true
end

---進路鎖錠と過走防護区間が正常に予約できたか確認します
---@private
---@param nt Ntracs
---@return boolean
function Signal:isBookedTemporary(nt)
    if not nt:get_track(self.startTrack):is_booked_start(self.itemName, nt) then
        return false
    end
    for _, value in ipairs(self.routeLock) do
        if not nt:get_track(value):is_booked_temporary(self.itemName, nt) then
            return false
        end
    end
    if not nt:get_track(self.destination):is_booked_temporary(self.itemName, nt) then
        return false
    end
    if self.overrunLockFallback then
        return true
    end
    for _, value in ipairs(self.overrunLock) do
        if not nt:get_track(value):is_booked_temporary(self.itemName, nt) then
            return false
        end
    end
    return true
end

---予約できる限り仮予約します
---@private
---@param nt Ntracs
---@param self Signal
function Signal:bookTemporary(nt)
    if not nt:get_track(self.startTrack):is_ready_for_book_start(self.itemName, nt) then
        return
    end
    for _, value in ipairs(self.routeLock) do
        if not nt:get_track(value):is_ready_for_book_temporary(self.itemName, nt) then
            return
        end
    end
    if not nt:get_track(self.destination):is_ready_for_book_temporary(self.itemName, nt) then
        return
    end

    local overrunReady = true
    for _, value in ipairs(self.overrunLock) do
        if not nt:get_track(value):is_ready_for_book_temporary(self.itemName, nt) then
            overrunReady = false
            break
        end
    end
    if (not overrunReady) and (not self.overrunLockFallback) then
        return
    end

    if self.startTrack then nt:get_track(self.startTrack):book_start_temporary(self.itemName, nt) end
    for _, value in ipairs(self.routeLock) do
        nt:get_track(value):book_temporary(self.itemName, nt)
    end
    nt:get_track(self.destination):book_temporary(self.itemName, nt)
    if overrunReady then
        for _, value in ipairs(self.overrunLock) do
            nt:get_track(value):book_temporary(self.itemName, nt)
        end
    end
end

---すべてのSwitchが正当な方向に転換しているか確認します
---@private
---@param nt Ntracs
---@return boolean
function Signal:checkSwitches(nt)
    for _, value in ipairs(self.switches) do
        if value:check(nt) then
            return false
        end
    end
    return true
end

---@private
---@return boolean
function Signal:isTimerRunning()
    return self.MSlR and self.timerTick < self.lockTime
end

---@private
---@return boolean
function Signal:isTimerEnd()
    return self.MSlR and self.timerTick >= self.lockTime
end

---進路鎖錠が成立していたらfalseを返します
---@return boolean
function Signal:under_route_lock_b()
    return self.ASR
end

---列車が防護区間にに進入したか確認します
---@private
---@param nt Ntracs
---@return boolean
function Signal:isEnterRoute(nt)
    if self.routeLock[1] == nil then
        if self.signalTrack[1] ~= nil then
            return nt:get_track(self.signalTrack[1]):is_short()
        else
            return true
        end
    else
        if self.routeLock[2] == nil then
            return nt:get_track(self.routeLock[1]):is_short()
        else
            return nt:get_track(self.routeLock[1]):is_short() and nt:get_track(self.routeLock[2]):is_short()
        end
    end
end

---過走防護区間が完全に鎖錠できているか確認します(開通テコ経由の保護を含みます)
---@private
---@param nt Ntracs
---@return boolean
function Signal:isOverrunProtected(nt)
    for _, value in ipairs(self.overrunLock) do
        if not nt:get_track(value):is_over_run_lock(self.itemName, nt) then
            return false
        end
    end
    return true
end

---進路鎖錠と過走防護区間をロックできたか確認します
---@private
---@param nt Ntracs
---@return boolean
function Signal:isLocked(nt)
    if not nt:get_track(self.startTrack):is_start_locked(self.itemName, nt) then
        return false
    end
    for _, value in ipairs(self.routeLock) do
        if not nt:get_track(value):is_route_lock(self.itemName) then
            return false
        end
    end
    if not nt:get_track(self.destination):is_destination_locked(self.itemName) then
        return false
    end
    return self:isOverrunProtected(nt) or self.overrunLockFallback
end

---すべての転轍機が鎖錠できたか確認します
---@private
---@param nt Ntracs
---@return boolean
function Signal:checkWLR(nt)
    for _, rswitch in ipairs(self.switches) do
        if nt:get_switch(rswitch.switch):getWLR(nt) then
            return false
        end
    end
    return true
end

---isNoShort
---@private
---@param nt Ntracs
---@return boolean
function Signal:isNoShort(nt)
    for _, value in ipairs(self.signalTrack) do
        if nt:get_track(value):is_short() then
            return false
        end
    end
    return true
end

---@private
---@param nt Ntracs
---@return boolean
function Signal:isNoApproach(nt)
    for _, value in ipairs(self.approachTrack) do
        if nt:get_track(value):is_short() then
            return false
        end
    end
    return true
end

---継電連動装置の進路てこの物理的状態に相当する情報を設定します
---@param input boolean
---@param nt Ntracs|nil
---@param fromControl boolean|nil
function Signal:setInput(input, nt, fromControl)
    self.input = input
    if fromControl or (not nt) then
        return
    end
    -- controlsの循環はビルド時(generate_signal.js)に検出されるため、ここでの cycle guard は不要
    for _, signalName in ipairs(self.controls) do
        local signal = nt:get_signal_may_nil(signalName)
        if signal and signal ~= self and type(signal.setInput) == "function" then
            signal:setInput(input, nt, false)
        end
    end
end

---継電連動装置の進路リレー相当の情報を返却します
---@return boolean
function Signal:getInput()
    return self.input
end

---processを呼び出す前に呼び出してください。現在の状態を設定します
function Signal:before_process()
    self.aspect = self.nextAspect
end

return Signal
