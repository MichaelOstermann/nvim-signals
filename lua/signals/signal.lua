local utils = require("signals.utils")

local Signal = {}

local function __tostring(signal)
    return "Signal<" .. signal.location .. ">(" .. vim.inspect(signal.value) .. ")"
end

local function signal(initialValue)
    return setmetatable({
        type = "signal",
        version = 0,
        location = utils.get_location(),
        value = initialValue,
        targets = setmetatable({}, { __mode = "k" }),
    }, {
        __index = Signal,
        __tostring = __tostring,
    })
end

Signal.peek = function(signal)
    return signal.value
end

Signal.get = function(signal)
    utils.on_read(signal)
    return signal.value
end

Signal.is = function(signal, value)
    return signal:get() == value
end

Signal.map = function(signal, fn)
    return signal:set(fn(signal:peek()))
end

Signal.set = function(signal, value)
    if signal.value ~= value then
        utils.on_write(signal)
        if utils.has_cycle() then
            error("cycle detected", 2)
        end
        signal.value = value
        signal.version = signal.version + 1
        utils.start_batch()
        utils.mark_as_dirty(signal)
        utils.end_batch()
    end

    return signal
end

return signal
