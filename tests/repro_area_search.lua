-- 前回 Area の直接判定と、AABB を使う BFS が探索順・在線を保つことを確認する。
local Area = require("src.n_tracs_soyabridge.area")
local Axle = require("src.n_tracs_soyabridge.axle")
local c = require("tests.harness").new_checker()
local function square(id, x, left, right)
    return Area.new(id, {
        { x=x, z=0 }, { x=x+10, z=0 }, { x=x+10, z=10 }, { x=x, z=10 },
    }, 1, left, right, nil)
end
local sw = { default_area=1, areas={
    [1]=square(1,0,{3},{2}),
    [2]=square(2,10,{1},{}),
    [3]=square(3,10,{1},{}), -- 2 と重なる。1 の左側候補なので、2 より先に選ばれる。
    [4]=square(4,30,{},{}),  -- 接続していない Area
} }
local function clear()
    for _,a in pairs(sw.areas) do a:initialize_for_process() end
end
local function axle(previous,x,z)
    local a=Axle.new(1,"TRAIN",nil)
    a.area=previous; a.real_pos={x=x,z=z or 5}
    return a
end
local first=sw.areas[1]
c:check("スカラーの最小X",first.min_x,0)
c:check("スカラーの最大X",first.max_x,10)
c:check("スカラーの最小Z",first.min_z,0)
c:check("スカラーの最大Z",first.max_z,10)
local polygon=first.pnpoly
local area_check=first.is_in_area
local polygonCalls,areaCalls=0,0
first.pnpoly=function(self,p) polygonCalls=polygonCalls+1; return polygon(self,p) end
first.is_in_area=function(self,p) areaCalls=areaCalls+1; return area_check(self,p) end
local a=axle(1,7)
a:search(sw)
c:check("前回と同じ Area 内で継続",a.area,1)
c:check("前回 Area の多角形判定は一度だけ",polygonCalls,1)
c:check("前回 Area の AABB を省く",areaCalls,0)
c:check("直接判定でも軸を登録",#first.axles,1)
local b=axle(1,3)
b:search(sw)
c:check("直接判定でも左からの軸順を維持",first.axles[1]==b and first.axles[2]==a,true)

clear(); polygonCalls,areaCalls=0,0
a.real_pos.x=15
a:search(sw)
c:check("重なる候補は従来の左→右の BFS 順で選択",a.area,3)
c:check("前回 Area の多角形を再判定しない",polygonCalls,1)
c:check("前回 Area を BFS 内で再判定しない",areaCalls,0)
c:check("移動先にだけ登録",#first.axles==0 and sw.areas[3].axles[1]==a,true)

clear(); polygonCalls,areaCalls=0,0
a=axle(nil,15)
a:search(sw)
c:check("前回不明なら default_area から BFS",a.area,3)
c:check("default_area の候補に AABB を使う",areaCalls,1)
c:check("矩形外なら default_area の多角形を調べない",polygonCalls,0)

clear()
a=axle(1,100)
a:search(sw)
c:check("全候補外なら Area を未確定にする",a.area,nil)
a.real_pos.x=5
a:search(sw)
c:check("エリア外から再進入するとすぐ検出",a.area,1)

clear()
a=axle(1,35)
a:search(sw)
c:check("接続していない Area を探索に追加しない",a.area,nil)
clear(); polygonCalls,areaCalls=0,0
a=axle(1,5)
a.disable_short=true
a:search(sw)
c:check("disable_short なら所属を消す",a.area,nil)
c:check("disable_short なら判定しない",polygonCalls+areaCalls,0)
c:check("disable_short なら軸を登録しない",#first.axles,0)

for _,p in ipairs({{x=0,z=0},{x=10,z=5},{x=5,z=10},{x=-0.000001,z=5},{x=10.000001,z=5}}) do
    c:check("矩形境界でも元の多角形判定と同値 x="..p.x.." z="..p.z,
        first:is_in_area(p),polygon(first,p))
end
c:report()
