---@param aspect number
---@return function
function StandardAspectCallback_2nd(aspect)
    return (function(self)
        if self.HR then
            return aspect
        else
            return 0
        end
    end)
end

---@param nextSignal string
---@return function
function StandardAspectCallback_3rd_G_Y_R(nextSignal)
    return (function(self, nt)
        if self.HR then
            if nt:get_signal(nextSignal).aspect >= 2 and self.aspect >= 2 then
                return 4
            else
                return 2
            end
        else
            return 0
        end
    end)
end

---@param nextSignals string[]
---@return function
function StandardAspectCallback_3rd_multi(nextSignals)
    return (function(self, nt)
        if self.HR then
            if self.aspect >= 2 then
                for _, s in ipairs(nextSignals) do
                    if nt:get_signal(s).aspect >= 2 then
                        return 4
                    end
                end
            end
            return 2
        else
            return 0
        end
    end)
end

error = error or function(message)
    debug.log("[N-TRACS] ERROR: " .. tostring(message))
end

Dbglog = function(message)
    debug.log("[N-TRACS] DEBUG: " .. tostring(message))
end
