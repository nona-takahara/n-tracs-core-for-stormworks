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
---@params a Complex
---@returns Complex
function Complex.conjugate(a)
    return {
        re = a.re,
        im = -a.im
    }
end

---乗算
---@params a Complex
---@params b Complex
---@returns Complex
function Complex.mul(a, b)
    return {
        re = a.re * b.re - a.im * b.im,
        im = a.re * b.im + b.re * a.im
    }
end

---偏角1/2倍、絶対値1/2乗の値を求める 偏角は-90度～0度～90度の範囲になる
---@params a Complex
---@return Complex
function Complex.halfArgument(a)
    local r = math.sqrt(a.re ^ 2 + a.im ^ 2)
    local sign = 0
    if a.im > 0 then
        sign = 1
    elseif a.im < 0 then
        sign = -1
    end
    return {
        re = math.sqrt((a.re + r) / 2),
        im = sign * math.sqrt((-a.re + r) / 2)
    }
end
