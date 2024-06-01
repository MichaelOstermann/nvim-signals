local M = {}

local on_read = nil
local on_write = nil
local batch_depth = 0
local batch_iteration = 0
local queue = {}

M.track_reads = function(fn)
    local prev = on_read
    on_read = fn
    return function()
        on_read = prev
    end
end

M.track_writes = function(fn)
    local prev = on_write
    on_write = fn
    return function()
        on_write = prev
    end
end

M.on_read = function(node)
    if on_read then
        on_read(node)
    end
end

M.on_write = function(node)
    if on_write then
        on_write(node)
    end
end

M.did_sources_change = function(node)
    if node.first_pass then
        node.first_pass = false
        return true
    end

    local computeds = {}

    for _, source in ipairs(node.sources) do
        if source.type == "signal" then
            local prev_version = node.versions[source]
            local next_version = source.version
            if prev_version ~= next_version then
                return true
            end
        elseif source.type == "computed" then
            table.insert(computeds, source)
        end
    end

    for _, computed in ipairs(computeds) do
        computed:__refresh()
        local prev_version = node.versions[computed]
        local next_version = computed.version
        if prev_version ~= next_version then
            return true
        end
    end

    return false
end

M.clear_sources = function(node)
    for _, source in ipairs(node.sources) do
        M.remove_target(source, node)
    end

    node.sources = {}
    node.versions = {}
end

M.add_source = function(node, source)
    if node.versions[source] then
        return
    end
    node.versions[source] = source.version
    table.insert(node.sources, source)
    M.add_target(source, node)
end

M.has_targets = function(node)
    if not node.targets then
        return false
    end
    for _ in pairs(node) do
        return true
    end
    return false
end

M.add_target = function(node, target)
    if not node.targets[target] then
        node.targets[target] = true
    end
end

M.remove_target = function(node, target)
    if node.targets[target] then
        node.targets[target] = nil
    end
end

M.mark_as_dirty = function(node)
    local stack = { node.targets }

    while true do
        local targets = table.remove(stack, 1)
        if not targets then
            return
        end

        for target in pairs(targets) do
            target:__on_dirty()
            if M.has_targets(target) then
                table.insert(stack, target.targets)
            end
        end
    end
end

M.is_batching = function()
    return batch_depth > 0
end

M.start_batch = function()
    batch_depth = batch_depth + 1
end

M.end_batch = function()
    batch_depth = batch_depth - 1
    if batch_depth > 0 then
        return
    end

    local err

    while #queue > 0 do
        local effect = table.remove(queue, 1)
        if effect then
            batch_iteration = batch_iteration + 1
            local ok, result = pcall(function()
                effect:__execute()
            end)
            err = result or err
        end
    end

    batch_iteration = 0

    if err then
        error(err, 2)
    end
end

M.queue_effect = function(effect)
    table.insert(queue, effect)
end

M.has_cycle = function()
    return batch_iteration > 100
end

M.get_location = function(stack_level)
    local info = debug.getinfo(stack_level or 3)
    return info.short_src .. ":" .. info.currentline
end

return M
