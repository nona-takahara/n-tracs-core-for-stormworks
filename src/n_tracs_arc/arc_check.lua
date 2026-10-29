-- ARC設定(res/arc.lua)の検査。ビルド時に build/check_arc.lua から呼ぶ。アドオンには同梱しない(script.luaからrequireしない)。
-- Stormworksでは error が使えないので、誤りは文字列の一覧で返す。

local M = {}

---設定が参照するもの(軌道回路・てこ・資源・予約)が存在し、形が正しいことを確認する
---@param config table res/arc.lua の設定
---@param nt Ntracs
---@return string[] errors 空なら誤りなし
function M.check(config, nt)
    local errors = {}
    local function add(msg) table.insert(errors, msg) end

    if type(config.parse) ~= "function" then add("config.parse must be a function") end
    if type(config.train_id) ~= "function" then add("config.train_id must be a function") end

    local reservations = config.reservations or {}

    for name, st in pairs(config.stations or {}) do
        local function fail(msg) add("[ARC:" .. name .. "] " .. msg) end
        local resources = st.resources or {}
        local function check_track(t, what)
            if not nt:get_track_may_nil(t) then fail(what .. ": track " .. tostring(t) .. " is not found") end
        end
        local function check_res(r, what)
            if not resources[r] then fail(what .. ": resource " .. tostring(r) .. " is not defined") end
        end

        for res, tracks in pairs(resources) do
            for _, t in ipairs(tracks) do check_track(t, "resource " .. res) end
        end
        for _, seq in ipairs(st.sequences or {}) do
            local at = "sequence " .. tostring(seq.id)
            if type(seq.moves) ~= "table" or #seq.moves == 0 then
                fail(at .. " has no moves")
            elseif type(seq.match) ~= "table" or type(seq.match.at) ~= "table" or type(seq.match.accept) ~= "function" then
                fail(at .. ": match.at (table) and match.accept (function) are required")
            else
                for _, t in ipairs(seq.match.at) do check_track(t, at .. " match.at") end
                for i, move in ipairs(seq.moves) do
                    local mv = at .. " move " .. i
                    if type(move.class) ~= "number" then fail(mv .. ": class is required") end
                    if type(move.enter) ~= "table" then
                        fail(mv .. ": enter is required")
                    else
                        for _, t in ipairs(move.enter) do check_track(t, mv .. " enter") end
                    end
                    if move.start_point then check_track(move.start_point, mv .. " start_point") end
                    if move.from then check_res(move.from, mv .. " from") end
                    if type(move.options) ~= "table" or #move.options == 0 then
                        fail(mv .. " has no options")
                    else
                        for _, opt in ipairs(move.options) do
                            local sig = nt:get_signal_may_nil(opt.signal)
                            if not sig then
                                fail(mv .. ": signal " .. tostring(opt.signal) .. " is not found")
                            elseif type(sig.isRouteLocked) ~= "function" then
                                fail(mv .. ": signal " .. opt.signal .. " is not a route lever")
                            end
                            for _, r in ipairs(opt.uses or {}) do check_res(r, mv .. " uses") end
                            if opt.dest then check_res(opt.dest, mv .. " dest") end
                            if opt.reserve then
                                if not reservations[opt.reserve.name] then
                                    fail(mv .. ": reservation " .. tostring(opt.reserve.name) .. " is not defined")
                                end
                                local mode = opt.reserve.mode
                                if mode ~= "hold" and mode ~= "take" and mode ~= "free" then
                                    fail(mv .. ": reserve.mode must be hold, take or free")
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return errors
end

return M
