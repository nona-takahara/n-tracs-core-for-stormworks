const fs = require("node:fs");
const luaparse = require("luaparse");
const luamin = require("./src-js/luamin");

const f = fs.readFileSync("script.lua").toString();


const ast = luaparse.parse(f, {
    comments: true,
    scope: true,
    locations: true,
    luaVersion: '5.3'
})
console.log(JSON.stringify({"ast": ast, "code": luamin.minify(ast)}));
