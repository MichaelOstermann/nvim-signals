local utils = require("signals.utils")

local Effect = {}

local refs = {}

local function __tostring(effect)
    return "Effect<" .. effect.location .. ">"
end

local function effect(computation)
    local effect = setmetatable({
        type = "effect",
        dirty = true,
        disposed = false,
        location = utils.get_location(),
        computation = computation,
        first_pass = true,
        sources = setmetatable({}, { __mode = "v" }),
        versions = setmetatable({}, { __mode = "k" }),
    }, {
        __index = Effect,
        __tostring = __tostring,
    })

    refs[effect] = true

    local ok, err = pcall(function()
        effect:__execute()
    end)

    if not ok then
        effect:dispose()
        error(err, 2)
    end

    return effect
end

Effect.dispose = function(effect)
    if effect.disposed then
        return
    end
    effect.disposed = true
    effect.computation = nil
    utils.clear_sources(effect)
    refs[effect] = nil
end

Effect.__on_dirty = function(effect)
    if effect.disposed then
        return
    end
    effect.dirty = true
    utils.queue_effect(effect)
end

Effect.__execute = function(effect)
    if effect.disposed then
        return
    end
    if not effect.dirty then
        return
    end

    effect.dirty = false

    if not utils.did_sources_change(effect) then
        return
    end
    utils.clear_sources(effect)

    local dispose_on_read = utils.track_reads(function(node)
        if effect.disposed then
            return
        end
        utils.add_source(effect, node)
    end)

    local ok, result = pcall(function()
        effect.computation(effect)
    end)
    dispose_on_read()

    if not ok then
        error(result, 2)
    end
end

return effect
