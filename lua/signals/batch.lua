local utils = require("signals.utils")

local function batch(fn)
    if utils.is_batching() then
        return fn()
    end

    utils.start_batch()
    local ok, result = pcall(fn)
    utils.end_batch()

    if not ok then
        error(result, 2)
    end

    return result
end

return batch
