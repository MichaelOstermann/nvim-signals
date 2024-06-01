local utils = require("signals.utils")

local Computed = {}

local function __tostring(computed)
    local _, value = pcall(function()
        return computed:peek()
    end)
    return "Computed<" .. computed.location .. ">(" .. vim.inspect(value) .. ")"
end

local function computed(computation)
    return setmetatable({
        type = "computed",
        error = nil,
        dirty = true,
        running = false,
        version = 0,
        location = utils.get_location(),
        computation = computation,
        targets = setmetatable({}, { __mode = "k" }),
        first_pass = true,
        sources = setmetatable({}, { __mode = "v" }),
        versions = setmetatable({}, { __mode = "k" }),
    }, {
        __index = Computed,
        __tostring = __tostring,
    })
end

Computed.peek = function(computed)
    if computed.running then
        error("cycle detected", 2)
    end
    computed:__refresh()
    if computed.error then
        error(computed.error, 2)
    end
    return computed.value
end

Computed.get = function(computed)
    if computed.running then
        error("cycle detected", 2)
    end
    computed:__refresh()
    utils.on_read(computed)
    if computed.error then
        error(computed.error, 2)
    end
    return computed.value
end

Computed.is = function(computed, value)
    return computed:get() == value
end

Computed.set = function(computed)
    error("attempt to write to " .. tostring(computed), 2)
end

Computed.__on_dirty = function(computed)
    computed.dirty = true
end

Computed.__refresh = function(computed)
    if not computed.dirty then
        return
    end

    computed.dirty = false

    if not utils.did_sources_change(computed) then
        return
    end

    utils.clear_sources(computed)

    local dispose_on_read = utils.track_reads(function(node)
        utils.add_source(computed, node)
    end)

    local dispose_on_write = utils.track_writes(function(node)
        error("attempt to write to " .. tostring(node) .. " during " .. tostring(computed), 4)
    end)

    computed.running = true
    local ok, result = pcall(computed.computation)
    computed.running = false
    computed.global_version = utils.global_version
    dispose_on_read()
    dispose_on_write()

    if ok then
        computed.error = false
        if computed.value ~= result then
            computed.value = result
            computed.version = computed.version + 1
        end
    end

    if not ok then
        computed.error = result
    end
end

return computed
