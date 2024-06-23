---@class NtracsObject
---@field name string クラス名です
---@field itemName string
NtracsObject = NtracsObject or {}

function NtracsObject.new()
    local obj = CreateInstance({}, NtracsObject)
    obj.name = "NtracsObject"
    return obj
end

---@generic T: any
---@param target any
---@param classObj T
---@return T
function CreateInstance(target, classObj)
    for k, v in pairs(classObj) do
        if k ~= "new" and type(v) == "function" then
            target[k] = v
        end
    end
    return target
end
