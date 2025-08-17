local sw = require("src.n_tracs_soyabridge.soya_bridge").new()

require("res.utils")
require("res.area_track")(sw)
require("res.signal")(sw)
require("res.switch")(sw)
require("res.signal_alias")(sw)
local crossing = require("res.crossing")(sw)

local json = require("temp.json")

function before_process()
    for k, v in pairs(sw.nt.track) do
        v:before_process(false)
    end

    for k, v in pairs(sw.nt.switch) do
        v:before_process(v.W ~= 0 and v.W or v.K)
    end

    for _, v in pairs(sw.nt.signal) do
        v:before_process()
    end
end

sw.nt:get_signal("NHB5R"):setInput(true)
sw.nt:get_signal("WAK1R").auto_reset = false
sw.nt:get_signal("WAK1R"):setInput(true)
before_process()
sw:process(6)


for i = 1, 5 do
    before_process()
    sw:process(6)
end


for i = 1, 5 do
    before_process()

    sw.nt:get_track("WAK1RT"):before_process(true)

    sw:process(6)
end

before_process()
sw:process(6)


print(json.stringify(sw.nt))
