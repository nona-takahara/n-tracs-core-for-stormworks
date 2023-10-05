-- N-TRACS Core [Lever]

---てこに関する操作を行います
---@class Lever:SignalBase
---@field private input boolean てこの入力状態
---@field private autoReset boolean てこを自動復位するかフラグ
---@field private ASR boolean
---@field private MSlR boolean
---@field private timerCount number
---@field private TSSlR boolean
---@field startTrack Track 進路てこ区間の始点
---@field destination Track 進路てこ区間の終点
---@field private switches SwitchRoute[]
---@field private routeLock Track[]
---@field private approachTrack Track[]
---@field private overrunLock Track[]
---@field private signalTrack Track[]
---@field lockTime number [CONSTANT]接近・保留鎖錠の時間(Tick)
---@field overrunTime number [CONSTANT]過走防護鎖錠の時間(Tick)
Lever = Lever or {}

---てこ構造体のインスタンスを作成します
---@param itemName string てこ名称
---@param startTrack Track 進路てこ区間の始点
---@param destination Track 進路てこ区間の終点
---@param switches SwitchRoute[] 関連する転てつ器と開通方向の組み合わせ情報
---@param routeLock Track[] 進路鎖錠を行う抽象軌道回路
---@param overrunLock Track[] 過走防護を行う抽象軌道回路
---@param signalTrack Track[] 信号現示に関連する抽象軌道回路
---@param direction RouteDirection 進路てこの方向
---@param approachTrack Track[] 接近鎖錠を行う抽象軌道回路。保留鎖錠の場合は空テーブル
---@param lockTime number 接近・保留鎖錠の時間(Tick)
---@param overrunTime number 過走防護鎖錠の時間(Tick)
---@param updateCallback fun(lever: Lever, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
---@return Lever
function Lever.new(itemName, startTrack, destination, switches, routeLock, overrunLock,
                   signalTrack, direction, approachTrack, lockTime, overrunTime, updateCallback)
    return Lever.overWrite({}, itemName, startTrack, destination, switches, routeLock, overrunLock,
        signalTrack, direction, approachTrack, lockTime, overrunTime, updateCallback)
end

---てこ構造体のインスタンスを作成します
---@param baseObject table ベースとなるオブジェクト
---@param itemName string てこ名称
---@param startTrack Track 進路てこ区間の始点
---@param destination Track 進路てこ区間の終点
---@param switches SwitchRoute[] 関連する転てつ器と開通方向の組み合わせ情報
---@param routeLock Track[] 進路鎖錠を行う抽象軌道回路
---@param overrunLock Track[] 過走防護を行う抽象軌道回路
---@param signalTrack Track[] 信号現示に関連する抽象軌道回路
---@param direction RouteDirection 進路てこの方向
---@param approachTrack Track[] 接近鎖錠を行う抽象軌道回路。保留鎖錠の場合は空テーブル
---@param lockTime number 接近・保留鎖錠の時間(Tick)
---@param overrunTime number 過走防護鎖錠の時間(Tick)
---@param updateCallback fun(lever: Lever, deltaTick: number):number 信号現示コールバック。新しい信号現示(>=0, 0は停止)を返す関数です
---@return Lever
function Lever.overWrite(baseObject, itemName, startTrack, destination, switches, routeLock, overrunLock,
                         signalTrack, direction, approachTrack, lockTime, overrunTime, updateCallback)
    baseObject.name = "Lever"
    baseObject.itemName = itemName
    baseObject.input = false
    baseObject.ASR = true
    baseObject.MSlR = false
    baseObject.timerCount = 0
    baseObject.TSSlR = false
    baseObject.HR = false
    baseObject.aspect = 0
    baseObject.nextAspect = 0
    baseObject.startTrack = startTrack
    baseObject.destination = destination
    baseObject.switches = switches
    baseObject.approachTrack = approachTrack
    baseObject.routeLock = routeLock
    baseObject.overrunLock = overrunLock
    baseObject.signalTrack = signalTrack
    baseObject.direction = direction
    baseObject.lockTime = lockTime
    baseObject.overrunTime = overrunTime
    baseObject.updateCallback = updateCallback
    baseObject.autoReset = false
    return baseObject
end

---現場扱いのてこが正当方向に転換しているか調べます
---@private
---@return boolean
function Lever.siteSwitchAssert(self)
    for _, value in ipairs(self.switches) do
        if SwitchRoute.getRelatedSwitch(value).isSite and not SwitchRoute.isTargetRoute(value) then
            return false
        end
    end
    return true
end

---@private
---@return boolean
function Lever.isReadyToBookTemporary(self)
    for _, value in ipairs(self.routeLock) do
        if not Track.isReadyToBookTemporary(value, self) then
            return false
        end
    end
    for _, value in ipairs(self.overrunLock) do
        if not Track.isReadyToBookTemporary(value, self) then
            return false
        end
    end
    return true
end

---BookTemporary
---@private
---@param self Lever
function Lever.bookTemporary(self)
    for _, value in ipairs(self.routeLock) do
        Track.bookTemporary(value, self)
    end
    for _, value in ipairs(self.overrunLock) do
        Track.bookTemporary(value, self)
    end
end

---CheckSwitches
---@private
---@return boolean
function Lever.checkSwitches(self)
    for _, value in ipairs(self.switches) do
        if not SwitchRoute.isTargetRoute(value) then
            return false
        end
    end
    return true
end

---@private
---@return boolean
function Lever.isTimerRunning(self)
    return self.MSlR and self.timerCount < self.lockTime
end

---@private
---@return boolean
function Lever.isTimerEnd(self)
    return self.MSlR and self.timerCount >= self.lockTime
end

---進路鎖錠が成立していたらfalseを返します
---@return boolean
function Lever.underRouteLock_n(self)
    return self.ASR
end

---isEnterRoute
---@private
---@return boolean
function Lever.isEnterRoute(self, forTSSlR)
    if self.routeLock[1] == nil then
        return false
    else
        if self.routeLock[2] == nil or not forTSSlR then
            return Track.isShort(self.routeLock[1])
        else
            return Track.isShort(self.routeLock[1]) and Track.isShort(self.routeLock[2])
        end
    end
end

---isReserved
---@private
---@return boolean
function Lever.isReserved(self)
    for _, value in ipairs(self.routeLock) do
        if not Track.isRouteLock(value, self) then
            return false
        end
    end
    for _, value in ipairs(self.overrunLock) do
        if not Track.isOverrunLock(value, self) then
            return false
        end
    end
    return true
end

---checkWLR
---@private
---@return boolean
function Lever.checkWLR(self)
    for _, value in ipairs(self.switches) do
        local rswitch = SwitchRoute.getRelatedSwitch(value)
        if Switch.getWLR(rswitch) then
            return false
        end
    end
    return true
end

---isNoShort
---@private
---@return boolean
function Lever.isNoShort(self)
    for _, value in ipairs(self.signalTrack) do
        if Track.isShort(value) then
            return false
        end
    end
    return true
end

---@private
---@return boolean
function Lever.isNoApproach(self)
    for _, value in ipairs(self.approachTrack) do
        if Track.isShort(value) then
            return false
        end
    end
    return true
end

---継電連動装置の進路てこの物理的状態に相当する情報を設定します
---@param input boolean
---@param autoReset boolean
function Lever.setInput(self, input, autoReset)
    self.input = input
    self.autoReset = input and (not (not autoReset))
end

---継電連動装置の進路リレー相当の情報を返却します
---@return boolean
function Lever.getInput(self)
    return self.input and Lever.siteSwitchAssert(self)
end

---processを呼び出す前に呼び出してください。現在の状態を設定します
function Lever.beforeProcess(self)
    self.aspect = self.nextAspect
end

---毎ループごとに呼び出してください
---@param deltaTick number
function Lever.process(self, deltaTick)
    if (Lever.getInput(self) and Lever.isReadyToBookTemporary(self)) then
        for _, rswitch in ipairs(self.switches) do
            SwitchRoute.moveToTarget(rswitch)
        end
        Lever.bookTemporary(self)
    end
    local ZR = Lever.getInput(self) and Lever.checkSwitches(self)

    if self.autoReset and self.TSSlR then
        self.input = false
        self.autoReset = false
    end

    self.TSSlR =
        (not self.HR) and (not self.ASR) and (Lever.isEnterRoute(self, true) or self.TSSlR)

    -- たぶん接近鎖錠条件が欠落している(TODO)
    self.ASR =
        (not self.HR) and (not ZR) and
        (Lever.isNoApproach(self) or self.TSSlR or self.ASR or Lever.isTimerEnd(self))

    -- 時素リレー動作は「特開平04-154475」にて、既存の回路で確認
    -- R接点：動作開始で落下
    -- N接点：動作完了で扛上
    self.MSlR =
        (not self.HR) and
        (not ZR) and
        (not self.ASR) and
        (not Lever.isEnterRoute(self, false)) and
        ((not Lever.isTimerRunning(self)) or self.MSlR);

    if self.MSlR then
        self.timerCount = self.timerCount + deltaTick
    else
        self.timerCount = 0
    end

    if not self.ASR then
        -- 進路鎖錠の連鎖の始点は信号てこであるため、thisを代入する。
        ---@type Lever | Track
        local routeLockBefore = self
        for _, track in ipairs(self.routeLock) do
            Track.bookRouteLock(track, self, routeLockBefore);
            routeLockBefore = track;
        end
        Track.bookDestination(self.destination, self, routeLockBefore);
        for _, track in ipairs(self.overrunLock) do
            Track.bookOverrun(track, self)
        end
    end
    if self.itemName == "NHB13R" then
        Announce(ZR and "true" or "false", -1)
        Announce(Lever.isReserved(self) and "true" or "false", -1)
        Announce(Lever.checkWLR(self) and "true" or "false", -1)
    end

    self.HR =
        ZR and
        Lever.isReserved(self) and
        Lever.checkWLR(self) and
        (not Lever.TSSlR) and
        (not Lever.ASR) and
        Lever.isNoShort(self)

    self.nextAspect = self.updateCallback(self, deltaTick)
    if not self.HR then
        self.nextAspect = 0
    end
end
