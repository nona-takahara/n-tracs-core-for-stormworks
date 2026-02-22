---@alias NtracsSymbol string

---@class NtracsObject
---@field name string クラス名です
---@field itemName string
local NtracsObject = {}

---@return NtracsObject
function NtracsObject.new()
    local obj = NtracsObject.create_instance({}, NtracsObject)
    obj.name = "NtracsObject"
    return obj
end

---@generic T: NtracsObject
---@param target any
---@param classObj T
---@return T
function NtracsObject.create_instance(target, classObj)
    for k, v in pairs(classObj) do
        if k ~= "new" and type(v) == "function" then
            target[k] = v
        end
    end
    target.__ntracs_class = classObj
    return target
end

---@param target any
---@param classObj any
---@return boolean
function NtracsObject.is_instance(target, classObj)
    return type(target) == "table" and target.__ntracs_class == classObj
end

---@generic T: NtracsObject
---@param target any
---@param classObj T
---@return T
function NtracsObject.ensure_instance(target, classObj)
    if type(target) ~= "table" then
        error("target is not table")
    end
    if NtracsObject.is_instance(target, classObj) then
        return target
    end
    return NtracsObject.create_instance(target, classObj)
end

---@return string
function NtracsObject:to_str()
    error("to_str is not defined")
end

return NtracsObject
