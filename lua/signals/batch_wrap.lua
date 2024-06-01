local batch = require("signals.batch")

local function batch_wrap(fn)
    return function(...)
        local args = { ... }
        return batch(function()
            return fn(unpack(args))
        end)
    end
end

return batch_wrap
