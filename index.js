const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
require('dotenv').config();

process.chdir(__dirname);

function main() {
    const ad = "res/area_track.lua", as = "res/area_track.json";
    if (!fs.existsSync(ad) || fs.statSync(as).mtime > fs.statSync(ad).mtime) {
        fs.writeFileSync(ad, area_track(JSON.parse(fs.readFileSync(as))));
    }

    const sd = "res/area_track.lua", ss = "res/area_track.json";
    if (!fs.existsSync(sd) || fs.statSync(ss).mtime > fs.statSync(sd).mtime) {
        console.log(execSync("python res/signal.py").toString());
    }

    console.log(execSync("npx storm-lua-minify -m script.lua").toString());
    if (!fs.existsSync("dist")) {
        fs.mkdirSync("dist");
    }

    fs.copyFileSync("script.lua.map", "dist/script.lua.map");
    fs.copyFileSync("script.min.lua", "dist/script.min.lua");

    if (process.env.NTRACS_SW_DIR) {
        fs.copyFileSync("script.min.lua", path.join(process.env.NTRACS_SW_DIR, "script.lua"));
    }

    fs.rmSync("script.lua.map");
    fs.rmSync("script.min.lua");

    console.log("Copied! " + (new Date().toLocaleTimeString()));
}

function area_track(obj) {
    const lua_begin = `-- Generated at ${new Date().toLocaleDateString()} ${new Date().toLocaleTimeString()}
---@param s SoyaBridge
return function(s)
local ca,ct,utils=s.create_area,s.create_track,require("res.utils")
`;
    const lua_end = "\nend\n";

    const vx = new Map();
    obj.vertexes.forEach((p) => {
        vx.set(p.name, ((p)=>({x: Math.floor(p.x*10)/10, z: Math.floor(p.z*10)/10}))(p));
    });

    const ar = new Map();
    obj.areas.forEach((p) => {
        p.downarea = Array();
        ar.set(p.name, p);
    })
    ar.forEach((v) => {
        v.uparea.forEach((k2) => {
            const p = ar.get(k2);
            if (p) {
                p.downarea.push(v.name);
            }
        })
    })

    const tr = new Map();
    obj.tracks.forEach((p) => {
        tr.set(p.name, p);
    })

    const create_area = Array();
    ar.forEach((a) => {
        create_area.push(`ca(s,${a.name.replace("Area_", "")},` +
            `{${a.vertexes.map((k) => {
                const v = vx.get(k);
                return `{x=${v.x},z=${v.z}}`;
            }).join(",")}},${a.left_vertex_inner_id + 1},` +
            `{${a.uparea.map((s) => s.replace("Area_", "")).join(",")}},` +
            `{${a.downarea.map((s) => s.replace("Area_", "")).join(",")}},` + 
            `${a.callback || "function()end"})`);
    });

    const create_track = Array();
    tr.forEach((t,k) => {
        create_track.push(`ct(s,"${k}",{${t.areas.map((a) => a.name.replace("Area_", "")).join(",")}})`);
    })

    return lua_begin + create_area.join("\n") + "\n" + create_track.join("\n") + lua_end;
}

main();
