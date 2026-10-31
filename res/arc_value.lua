-- 宗弥急行プロジェクト線のARC指令値(7桁: pp b tt dd)の分解
-- 路線ごとに指令の形式が異なるときは、別のparse/train_idを res/arc.lua に渡す
-- 値の意味は https://nonasaba.net/sw-train-docs/support/Soya-Express-ARC.html

---@class ArcValue
---@field raw number 元の値
---@field pp number 運行番号(0は未指定)
---@field b number 路線/上下線 (1: 北港・掘戸町方面, 2: 潮凪浜・南江町方面)
---@field class number 種別の十の位 (0: 無指定, 1: 各停, ...)
---@field category number 種別の一の位を分類した値 (0: 一般旅客, 1: 試運転, 2: 臨時, 3: 回送, 4: その他)
---@field station number 行先の駅コード(十の位, 0は無指定)
---@field platform number 行先の番線(一の位, 0は自動選択, 9は同一方向の引き上げ線)

local M = {}

---@param raw number|nil
---@return ArcValue|nil 0・nil・負の値のときはnil
function M.parse(raw)
    if type(raw) ~= "number" or raw <= 0 then return nil end
    local v = math.floor(raw)
    local tt = (v // 100) % 100
    local unit = tt % 10
    return {
        raw = v,
        pp = v // 100000,
        b = (v // 10000) % 10,
        class = tt // 10,
        category = (unit >= 1 and unit <= 4) and unit or 0,
        station = (v % 100) // 10,
        platform = v % 10,
    }
end

---列車の識別子は運行番号(pp)。運行番号が0(指定なし)の列車は扱わない(nilを返す)
---@param arc ArcValue
---@return number|nil
function M.train_id(arc)
    if arc.pp > 0 then return arc.pp end
    return nil
end

return M
