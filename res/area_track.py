import os
import json

os.chdir(os.path.dirname(__file__))


def area_track_lua_code(area, vertexes):
    if len(area["vertexes"])==0:
        return ""
    listVertex = "{" + ",".join(["{" + f"x={vertexes[id]['x']},z={vertexes[id]['z']}" + "}" for id in area["vertexes"]]) + "}"
    #listVertex = "{" + ",".join([f"V[{id}]" for id in area["vertexes"]]) + "}"
    listRelated = "{" + ",".join([f"AreaGetter\"{id}\"" for id in area["related"]]) + "}"
    return f"Area.overWrite(AreaGetter\"{area['name']}\",{listVertex},{area['left_vertex_inner_id']+1},{listRelated},{area['callback'] or 'function()end'})"

# @class Area
# @field name string
# @field vertexs Vector2d[] @反時計回りにエリアの頂点を定義
# @field leftVertexId number
# @field axles Axle[] @左から順に車軸情報
# @field nodeToArea Area[] @隣り合うエリア・ポリゴンへの参照

with (open("area_track.json", "rb") as json_f, open("area_track.lua", "w") as lua_f):
    data = json.load(json_f)
    v = data["vertexes"]

    vv = {}
    for vx in v:
        vv[vx['name']] = vx

    for a in data["areas"]:
        print(area_track_lua_code(a, vv), file = lua_f)
