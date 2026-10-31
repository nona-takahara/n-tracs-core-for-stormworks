-- Area の callback を、ブロックの木から組み立てる関数群。
-- res/area_track.lua が使う。呼び出しの形は build/compile_send.js が作る。
--
-- 木の読み方: 並んだブロックを順に調べ、条件が成り立ったものを選ぶ。
-- 選ばれたブロックは、子のどれも選ばれなければ自分の行を送る。
-- B は選ばれたら同じ並びの残りを調べず、P は調べ続ける(/through)。
local Utils = require("res.utils")

---@param s SoyaBridge
return function(s)
    local function level(blocks, area, track, dt)
        local hit = false
        for _, block in ipairs(blocks) do
            local chosen, stop = block(area, track, dt)
            hit = hit or chosen
            if stop then break end
        end
        return hit
    end

    local function block_of(stop)
        return function(condition, row, ...)
            local children = { ... }
            return function(area, track, dt)
                if condition(track, dt) then
                    if not level(children, area, track, dt) and row then row(area, track) end
                    return true, stop
                end
            end
        end
    end

    -- 名前のどれかについて test が成り立つか、を調べる条件を作る関数を返す
    local function any_of(test)
        return function(...)
            local names = { ... }
            return function(track)
                for _, name in ipairs(names) do
                    if test(name, track) then return true end
                end
                return false
            end
        end
    end

    return
        block_of(true),  -- B
        block_of(false), -- P
        function(track, ...) -- C
            local blocks = { ... }
            return function(self, _, dt) level(blocks, self, track, dt) end
        end,
        function(data) -- R
            return function(area, track)
                if Utils.isTrackRightAxle(s, area, track) then Utils.SendRightAxle(area, data) end
            end
        end,
        function(data) -- L
            return function(area, track)
                if Utils.isTrackLeftAxle(s, area, track) then Utils.SendLeftAxle(area, data) end
            end
        end,
        function(data) -- Z
            return function(area) Utils.SendAllAxle(area, data) end
        end,
        any_of, -- A
        function(test) -- U: 比較の右辺の値を受け取る条件
            return function(value, ...)
                return any_of(function(name, track) return test(name, track, value) end)(...)
            end
        end,
        function(...) -- K: 照査点(キー, hold の tick の並び)のどれかが作動中か
            local pairs_ = { ... }
            return function(track, dt)
                local tr = s.nt:get_track(track)
                for i = 1, #pairs_, 2 do
                    local t = tr:get_timer(pairs_[i])
                    if t > 0 and t < pairs_[i + 1] + dt then return true end
                end
                return false
            end
        end,
        -- W: 照査点を軸が横切るのを見て、タイマーを始め直す。
        -- 作動中は進め、点を toward の向きに over 以上の速さで、Area の幅の線分を横切った軸があれば、0 に戻して1周期分進める。
        function(track, key, hold, x, z, tx, tz, over, half)
            return function(area, dt)
                local tr = s.nt:get_track(track)
                local t = tr:get_timer(key)
                if t > 0 and t < hold + dt then tr:advance_timer(key, dt) end
                for _, a in ipairs(area.axles) do
                    local d = a.delta_pos
                    if d and a.velocity >= over then
                        local p, q = a.real_pos, dt / 60
                        local bx, bz = p.x - d.x * q - x, p.z - d.z * q - z
                        local ax, az = p.x - x, p.z - z
                        local before, after = bx * tx + bz * tz, ax * tx + az * tz
                        if before < 0 and after >= 0 then
                            local sb, sa = bz * tx - bx * tz, az * tx - ax * tz
                            local side = sb + (sa - sb) * before / (before - after)
                            if side >= -half and side <= half then
                                tr:reset_timer(key)
                                tr:advance_timer(key, dt)
                            end
                        end
                    end
                end
            end
        end,
        function(track, watchers, ...) -- D: C の前に、照査点の監視を動かす
            local blocks = { ... }
            return function(self, _, dt)
                for _, watch in ipairs(watchers) do watch(self, dt) end
                level(blocks, self, track, dt)
            end
        end
end
