---@class Complex
Complex = Complex or {}

---複素数
---@class Complex
---@field re number @実部
---@field im number @虚部

function Complex.new(re, im)
    return {
        re = re,
        im = im
    }
end

---共役
---@params self Complex
---@returns Complex
function Complex.conjugate(self)
    return {
        re = self.re,
        im = -self.im
    }
end

---乗算
---@params self Complex
---@params b Complex
---@returns Complex
function Complex.mul(self, b)
    return {
        re = self.re * b.re - self.im * b.im,
        im = self.re * b.im + b.re * self.im
    }
end

---1/2乗
---@params self Complex
---@return Complex
function Complex.sqrt(self)
    local r = math.sqrt(self.re ^ 2 + self.im ^ 2);
    local sign = 0
    if self.im > 0 then
        sign = 1
    elseif self.im < 0 then
        sign = -1
    end
    return {
        re = math.sqrt((self.re + r) / 2),
        im = sign * math.sqrt((-self.re + r) / 2)
    }
end
