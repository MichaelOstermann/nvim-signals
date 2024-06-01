local utils = require("signals.utils")

local function untracked(fn)
    local dispose = utils.track_reads(nil)
    local ok, result = pcall(fn)
    dispose()
    if ok then
        return result
    else
        error(result, 2)
    end
end

return untracked
