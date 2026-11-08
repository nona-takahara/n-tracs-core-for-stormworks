-- 登録候補の索引が、設定順・early・現在の要求と駅間の観測を保つことを確かめる。
local Arc = require("src.n_tracs_arc.arc")
local c = require("tests.harness").new_checker()
local values, calls = {}, {}
local nt = { track = {} }
for _, id in ipairs({ "A", "B", "C", "EARLY", "START", "BETWEEN", "END" }) do nt.track[id] = {} end
local function sequence(id, at, start, early)
    return {
        id = id,
        match = { at = at, accept = function(v, code)
            calls[#calls + 1] = id
            return v.allowed[id] and code == 7
        end },
        moves = { { class = 1, start_point = start,
            early = early and { start_point = early, accept = function(v) return v.fast end },
            enter = { "END" }, options = {} } },
    }
end
local seqs = {
    sequence("first", { "B", "A", "A" }, "START", "EARLY"),
    sequence("second", { "A", "C" }),
    sequence("third", { "C" }),
}
---軌道回路ごとの指令値 probe(id) から、ARC が読む一覧(指令値を持つ軌道回路と、その指令値)を作る
local function reader(ids, probe)
    return function()
        local out = {}
        for _, id in ipairs(ids) do
            local v = probe(id)
            if v and v ~= 0 then out[#out + 1] = { id, v } end
        end
        return out
    end
end
local arc = Arc.new({
    parse = function(v) return v ~= 0 and v or nil end,
    train_id = function(v) return v.key end,
    stations = { S = { code = 7, running = false, sequences = seqs } },
}, nt, reader({ "A", "B", "C", "EARLY", "START", "BETWEEN", "END" }, function(id) return values[id] or 0 end))
local station = arc.stations.S
local function step(tracks, allowed, fast)
    values, calls = {}, {}
    local v = { key = "train", allowed = allowed, fast = fast }
    for _, id in ipairs(tracks) do values[id] = v end
    arc:process(6)
    return station.requests.train
end
local r = step({ "A", "B", "C" }, { second = true, third = true })
c:check("重複した登録点を設定順に一度ずつ判定", table.concat(calls, ","), "first,second")
c:check("先に設定した適合候補を登録", r.seq.id, "second")
r = step({ "END" }, { second = true })
c:check("一連の動きの軌道回路の上では、登録点を離れても現在の要求を継続", r.seq.id, "second")
c:check("停止中も指令値を更新", r.arc.allowed.second, true)
r = step({ "BETWEEN" }, { second = true })
c:check("一連の動きの軌道回路の外に出たら、通り抜けたとみなして要求を消す(D3)", r, nil)
r = step({ "EARLY" }, { first = true, second = true }, false)
c:check("現在の要求より先の候補が優先", r.seq.id, "first")
station.requests.train = nil
r = step({ "EARLY" }, { first = true }, false)
c:check("earlyで登録した通常列車は開始点未通過", r.passed, false)
r = step({ "START" }, { first = true }, false)
c:check("開始点に達すると通過済み", r.passed, true)
station.requests.train = nil
r = step({ "EARLY" }, { first = true }, true)
c:check("early対象列車はearlyで通過済み", r.passed, true)
r = step({ "BETWEEN" }, {})
c:check("指令変更で適合しなくなった要求を削除", r, nil)
r = step({ "BETWEEN" }, { first = true })
c:check("駅間の列車は新規登録しない", r, nil)

-- 登録点の組み合わせと指令値を総当たりし、設定順の検索結果と比較する。
local points = { "A", "B", "C", "EARLY", "START", "BETWEEN" }
for mask = 0, 63 do
    local tracks, present = {}, {}
    for i, id in ipairs(points) do
        if mask & (1 << (i - 1)) ~= 0 then tracks[#tracks + 1] = id; present[id] = true end
    end
    for flags = 0, 7 do
        local allowed, expected = {}, nil
        for i, seq in ipairs(seqs) do allowed[seq.id] = flags & (1 << (i - 1)) ~= 0 end
        for _, seq in ipairs(seqs) do
            local move = seq.moves[1]
            local here = present[move.start_point] or (move.early and present[move.early.start_point])
            for _, id in ipairs(seq.match.at) do here = here or present[id] end
            if here and allowed[seq.id] then expected = seq.id; break end
        end
        station.requests.train = nil
        local req = step(tracks, allowed)
        c:check("登録点=" .. mask .. " 指令=" .. flags, req and req.seq.id, expected)
    end
end
-- 同じ資源を複数列車が塞ぐ場合も、従来の観測順で警報の相手を選ぶ。
-- 資源内の軌道回路順を逆転させても、警報の輪は変わらない。
for _, reverse in ipairs({ false, true }) do
    local occupied = { A = { key = 1 }, B = { key = "two" }, C = { key = 3 } }
    local observations = {}
    for _, id in ipairs({ "A", "B", "C" }) do observations[occupied[id].key] = true end
    local last
    for key in pairs(observations) do last = key end
    local routes = {}
    for _, id in ipairs({ "A", "B", "C" }) do
        routes[#routes + 1] = {
            id = id, match = { at = { id }, accept = function() return true end },
            moves = { { class = 1, enter = { "END" }, options = { { signal = "unused", dest = "ALL" } } } },
        }
    end
    local deadlock = Arc.new({
        parse = function(v) return v ~= 0 and v or nil end,
        train_id = function(v) return v.key end,
        stations = { S = { running = false, sequences = routes,
            resources = { ALL = reverse and { "C", "B", "A" } or { "A", "B", "C" } } } },
    }, {
        track = { A = {}, B = {}, C = {} },
        get_signal = function() return { signalTrack = {}, routeLock = {} } end,
    }, reader({ "A", "B", "C" }, function(id) return occupied[id] end))
    deadlock:process(6)
    local penultimate
    for key in pairs(observations) do if key ~= last then penultimate = key end end
    local ring = { last, penultimate }
    table.sort(ring, function(a, b) return tostring(a) < tostring(b) end)
    c:check("停止中も複数在線の警報を継続 reverse=" .. tostring(reverse),
        table.concat(deadlock.stations.S.alerts, ","), table.concat(ring, "<->"))
    occupied = {}
    deadlock.read = function() return {} end
    deadlock:process(6)
    c:check("在線消失で警報を解除", #deadlock.stations.S.alerts, 0)
end
c:report()
