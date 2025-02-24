---@alias NtracsSymbol string

---@class NtracsObject
---@field name string クラス名です
---@field itemName string
local NtracsObject = {}

---@return NtracsObject
function NtracsObject.new()
    local obj = NtracsObject.createInstance({}, NtracsObject)
    obj.name = "NtracsObject"
    return obj
end

---@generic T: NtracsObject
---@param target any
---@param classObj T
---@return T
function NtracsObject.createInstance(target, classObj)
    for k, v in pairs(classObj) do
        if k ~= "new" and type(v) == "function" then
            target[k] = v
        end
    end
    return target
end

return NtracsObject
