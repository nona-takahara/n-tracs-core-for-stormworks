-- N-TRACS Core [Lever]

local NtracsObject = require("src.n_tracs_core.n_tracs_object")
local SignalBase = require("src.n_tracs_core.signal.signal_base")

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
---@field lockTime number [CONSTANT]接近・保留鎖錠の時間(Tick)
---@field overrunTime number [CONSTANT]過走防護鎖錠の時間(Tick)
---@field aspect number
local Signal = {}

---転てつ器と開通方向の情報セットを扱います
---@class SwitchRoute
---@field switch string 関連転てつ器
---@field target SignalRoute 開通希望方向

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
---@param updateCallback fun(lever: Signal, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
---@return Signal
function Signal.new(itemName, startTrack, destination, switches, routeLock, overrunLock,
                    signalTrack, direction, approachTrack, lockTime, overrunTime, updateCallback)
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
    obj.direction = direction
    obj.lockTime = lockTime
    obj.overrunTime = overrunTime
    obj.updateCallback = updateCallback
    obj.auto_reset = false
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

    self.TSSlR = not (self.HR or self.ASR or self:isEnterRoute(nt))

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
        -- 進路鎖錠の連鎖の始点は信号てこであるため、thisを代入する。
        local routeLockBefore = self.itemName
        for _, track in ipairs(self.routeLock) do
            nt:get_track(track):book_route_lock(self.itemName, routeLockBefore, nt)
            routeLockBefore = track
        end
        nt:get_track(self.destination):book_destination(self.itemName, routeLockBefore, nt)
        for _, track in ipairs(self.overrunLock) do
            nt:get_track(track):book_over_run(self.itemName, nt)
        end
    end

    self.HR =
        ZR and
        self:isLocked(nt) and
        self:checkWLR(nt) and
        (not Signal.TSSlR) and
        (not Signal.ASR) and
        self:isNoShort(nt)

    self.nextAspect = self:updateCallback(deltaTick)
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
        if nt:get_switch(sw.switch).isSite and not nt:get_switch(sw.switch).K == sw.target then
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
    for _, value in ipairs(self.routeLock) do
        if not nt:get_track(value):is_booked_temporary(self.itemName, nt) then
            return false
        end
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
    for _, value in ipairs(self.routeLock) do
        if not nt:get_track(value):is_ready_for_book_temporary(self.itemName, nt) then
            return
        end
    end
    for _, value in ipairs(self.overrunLock) do
        if not nt:get_track(value):is_ready_for_book_temporary(self.itemName, nt) then
            return
        end
    end

    for _, value in ipairs(self.routeLock) do
        nt:get_track(value):book_temporary(self.itemName, nt)
    end
    for _, value in ipairs(self.overrunLock) do
        nt:get_track(value):book_temporary(self.itemName, nt)
    end
end

---すべてのSwitchが正当な方向に転換しているか確認します
---@private
---@param nt Ntracs
---@return boolean
function Signal:checkSwitches(nt)
    for _, value in ipairs(self.switches) do
        if nt:get_switch(value.switch).K ~= value.target then
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

---進路鎖錠と過走防護区間をロックできたか確認します
---@private
---@param nt Ntracs
---@return boolean
function Signal:isLocked(nt)
    for _, value in ipairs(self.routeLock) do
        if not nt:get_track(value):is_route_lock(self.itemName) then
            return false
        end
    end
    for _, value in ipairs(self.overrunLock) do
        if not nt:get_track(value):is_over_run_lock(self.itemName, nt) then
            return false
        end
    end
    return true
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
function Signal:setInput(input)
    self.input = input
end

---継電連動装置の進路リレー相当の情報を返却します
---@return boolean
function Signal:getInput()
    return self.input
end

---processを呼び出す前に呼び出してください。現在の状態を設定します
function Signal:beforeProcess(nt)
    self.aspect = self.nextAspect
end

return Signal
