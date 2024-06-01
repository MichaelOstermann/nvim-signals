<div align="center">

<h1>nvim-signals</h1>

**Bringing reactivity as seen in Solid, Vue, Angular, Preact and others to Neovim!**

</div>

<!-- panvimdoc-ignore-start -->

# 🚀 Example

```lua
-----------------------------------------------------------------------------------
-- Signals describe values that change over time:
-----------------------------------------------------------------------------------

local diagnostics = signal({})
local current_mode = signal(nil)
local current_buf = signal(nil)
local current_row = signal(0)
local current_col = signal(0)

-----------------------------------------------------------------------------------
-- Using autocommands to keep our signals up-to-date. These do not have to be aware
-- of what other modules would be interested in updates, instead they can subscribe
-- to changes:
-----------------------------------------------------------------------------------

vim.api.nvim_create_autocommand("DiagnosticChanged", {
    callback = function()
        diagnostics:set(vim.diagnostic.get(nil))
    end
})

vim.api.nvim_create_autocommand("ModeChanged", {
    callback = function()
        current_mode:set(vim.api.nvim_get_mode().mode)
    end
})

vim.api.nvim_create_autocommand("BufEnter", {
    callback = function(event)
        current_buf:set(event.buf)
    end
})

vim.api.nvim_create_autocommand({ "CursorMoved", "CursorMovedI" }, {
    callback = batch_wrap(function()
        local pos = vim.api.nvim_win_get_cursor(0)
        current_row:set(pos[1])
        current_col:set(pos[1])
    end)
})

-----------------------------------------------------------------------------------
-- Computeds allow you to compose signals to create derived state. They feature
-- automatic dependency management, and lazy evaluation:
-----------------------------------------------------------------------------------

local current_buf_diagnostics = computed(function()
    return vim.tbl_filter(function(diagnostic)
        return diagnostic.bufnr == current_buf:get()
    end, diagnostics:get())
end)

local current_row_diagnostics = computed(function()
    local row = current_row:get() - 1
    return vim.tbl_filter(function(diagnostic)
        return diagnostic.lnum <= row and diagnostic.end_lnum >= row
    end, current_buf_diagnostics:get())
end)

local current_col_diagnostics = computed(function()
    local col = current_col:get()
    return vim.tbl_filter(function(diagnostic)
        return diagnostic.col <= col and diagnostic.end_col >= col
    end, current_row_diagnostics:get())
end)

local current_col_diagnostic = computed(function()
    return current_col_diagnostics:get()[1]
end)

local show_diagnostics = computed(function()
    return current_mode:is("n")
end)

-----------------------------------------------------------------------------------
-- Effects allow you to react to changes in signals and computeds. They are eagerly
-- evaluated and only execute when their dependencies have changed:
-----------------------------------------------------------------------------------

-- Prints the diagnostics at the current row/col whenever they change:
effect(function()
    print(vim.inspect(current_col_diagnostics:get()))
end)

-- Adds the message of the first diagnostic at the current/row col, unless we don't
-- want to show it. If `show_diagnostics` is `true`, this effect will rerun whenever
-- `show_diagnostics` or `current_col_diagnostic` changed. If it is `false`, it will
-- only rerun when `show_diagnostics` changed:
effect(function()
    if show_diagnostics:is(true) and current_col_diagnostic:get() then
        vim.o.statusline = current_col_diagnostic:get().message
    else
        vim.o.statusline = " "
    end
end)
```

<!-- panvimdoc-ignore-end -->

<!-- panvimdoc-ignore-start -->

# 🔎 Overview

- [Introduction](#introduction)
    - [What are Signals?](#what-are-signals)
    - [Creating Signals](#creating-signals)
    - [Effects](#effects)
    - [Branching Dependencies](#branching-dependencies)
    - [Circumventing Dependency Tracking](#circumventing-dependency-tracking)
    - [Batching Updates](#batching-updates)
    - [Computeds](#computeds)
- [Installation](#installation)
- [Usage](#usage)
- [API](#api)
    - [`signal()`](#signal)
    - [`signal:get()`](#signalget)
    - [`signal:peek()`](#signalpeek)
    - [`signal:set()`](#signalset)
    - [`signal:is()`](#signalis)
    - [`signal:map()`](#signalmap)
    - [`computed()`](#computed)
    - [`computed:get()`](#computedget)
    - [`computed:peek()`](#computedpeek)
    - [`computed:is()`](#computedis)
    - [`effect()`](#effect)
    - [`effect:dispose()`](#effectdispose)
    - [`batch()`](#batch)
    - [`batch_wrap()`](#batch_wrap)
    - [`untracked()`](#untracked)
    - [`untracked_wrap()`](#untracked_wrap)
- [Notes](#notes)
    - [Garbage Collection](#garbage-collection)

<!-- panvimdoc-ignore-end -->

<!-- panvimdoc-ignore-start -->

# 📖 Introduction

> [!NOTE]
> If you are already familiar with signals, you can [skip](#installation) this section!

---

- [What are Signals?](#what-are-signals)
- [Creating Signals](#creating-signals)
- [Effects](#effects)
- [Branching Dependencies](#branching-dependencies)
- [Circumventing Dependency Tracking](#circumventing-dependency-tracking)
- [Batching Updates](#batching-updates)
- [Computeds](#computeds)

## What are Signals?

Signals are a simple and easy-to-use primitive to describe values that change over time, compose them, and react to when they change.

As an example, think of how your statusline is dependent on values that change over time: the cursor position, the mode, buffer name, git status, LSP status, diagnostics, etc. Often times you will be fine wiring the right autocommands with a `vim.cmd("redrawstatus")` and calling it a day.

Sometimes however you can find yourself in a situation where you are orchestrating state via custom user autocommands or lua pub-sub implementations, some of which may mutate state across modules to keep them up-to-date, adding missing autocommands when things do not update correctly, removing others when they become obsolete, trying to avoid redrawing several times in quick succession, caching derived state to avoid unnecessary computations, etc.

This is not limited to the statusline - any value that changes over time that has some form of effect can become a source of complexity, this is especially true if you are building something on the scale of telescope or nvim-tree!

This is where signals can help out a lot, let's take a look at some examples:

## Creating Signals

To get started, we need to create some signals:

```lua
local signal = require("signals.signal")

-- The total height of the UI:
local lines = signal(vim.o.lines)
-- The total width of the UI:
local columns = signal(vim.o.columns)
```

We can read what each of those signals currently contain:

```lua
-- Example: 40
print(lines:get())
-- Example: 180
print(columns:get())
```

We can also update them:

```lua
vim.api.nvim_create_autocommand("VimResized", {
    callback = function()
        -- Update these signals whenever the UI gets resized:
        lines:set(vim.o.lines)
        columns:set(vim.o.columns)
    end,
})
```

## Effects

Next, you probably would like to do something whenever those values change - this is called an "effect":

```lua
local effect = require("signals.effect")

effect(function()
    print(lines:get())
    print(columns:get())
end)
```

The above will print the value of `lines` and `columns` whenever they change!

The amazing thing about this is that signals feature automatic dependency management, meaning effects will track what signals you accessed and subscribe to them, triggering the surrounding effect whenever they change.

Once you have your signals set up, you can "just use them" and not worry about anything else.

Here might be a more appropiate example that refreshes the dimensions and position of a window whenever necessary:

```lua
local config = {
    -- 50% of the available width & height:
    width = 0.5,
    height = 0.5,
    -- Positioned at the center:
    x = 0.5,
    y = 0.5,
    -- With these additional constraints:
    max_width = 100,
    min_width = 50,
    max_height = 100,
    min_height = 50,
}

effect(function()
    local width = math.min(math.max(math.ceil(columns:get() * config.width), config.min_width), config.max_width)
    local col = math.ceil((columns:get() - width) * config.x)
    
    local height = math.min(math.max(math.ceil(lines:get() * config.height), config.min_height), config.max_height)
    local row = math.ceil((lines:get() - height) * config.y)

    vim.api.nvim_win_set_config(win_id, {
        border = "none",
        relative = "editor",
        style = "minimal",
        width = width,
        height = height,
        row = row,
        col = col,
    })
end)
```

## Branching Dependencies

One interesting attribute of effects is that they continuously keep tracking what you use and update their dependencies as a result.

Let's say we wanted to temporarily freeze the position of our imaginary window:

```lua
local freeze = signal(false)

effect(function()
    if freeze:get() then return end
    -- All the other stuff from before
end)
```

Starting off, our window will stay up-to-date whenever we resize our UI. Let's flip the switch:

```lua
freeze:set(true)
```

As you can imagine, our window will no longer update. Additionally, our effect will no longer react to changes made to `columns` and `lines`, those signals have been kicked out from the list of dependencies, our effect is now only interested in the value of `freeze`.

If we flip it back again:

```lua
freeze:set(false)
```

We are where we started again.

## Circumventing Dependency Tracking

Sometimes you want to read from signals, without subscribing to them. You can use `signal:peek()` for single cases:

```lua
effect(function()
    -- Will print the current value of `lines`, but our surrounding effect will not
    -- react to changes made:
    print(lines:peek())
end)
```

And for more difficult scenarios, `untracked` should do the trick:

```lua
local untracked = require("signals.untracked")

local function gcd(a, b)
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end

local function get_aspect_ratio()
    local divisor = gcd(columns:get(), lines:get())
    return string.format(
        "%d:%d",
        columns:get() / divisor,
        lines:get() / divisor
    )
end

effect(function()
    -- get_aspect_ratio is using `:get()` and we don't want to migrate to `:peek()`,
    -- however we do not want this effect to setup subscriptions. For cases like these,
    -- `untracked` is coming in clutch:
    local result = untracked(get_aspect_ratio)
    -- Example: "2:1"
    print(result)
end)
```

## Batching Updates

An earlier example depicted this:

```lua
vim.api.nvim_create_autocommand("VimResized", {
    callback = function()
        lines:set(vim.o.lines)
        columns:set(vim.o.columns)
    end,
})

effect(function()
    print(lines:get())
    print(columns:get())
end)
```

What this will actually do is trigger the effect twice, once for each of the updated signals.

You can use `batch` to combine several updates into a single one:

```lua
local batch = require("signals.batch")

vim.api.nvim_create_autocommand("VimResized", {
    callback = function()
        batch(function()
            lines:set(vim.o.lines)
            columns:set(vim.o.columns)
        end)
    end,
})
```

Our effect will now refresh only once! Note that nested batches will work just fine:

```lua
local function a()
    batch(function()
        signal1:set(...)
        signal2:set(...)
    end)
end

local function b()
    -- This batch call will not conflict with the one declared in a(),
    -- all updates done here will be batched together!
    batch(function()
        a()
        signal3:set(...)
    end)
end

b()
```

## Computeds

Let's say you had a signal that represents how many files have a dirty git status in your repository:

```lua
local dirty_files_count = signal(0)
```

And you would like to display an icon in your statusline for when you have any dirty files at all:

```lua
effect(function()
    vim.o.statusline = dirty_files_count:get() > 0 and "⚠" or ""
end)
```

You will come to find that your statusline will refresh more often than necessary:

```lua
dirty_files_count:set(1) -- This is fine
dirty_files_count:set(2) -- The effect runs, but is unnecessary
dirty_files_count:set(3) -- The effect runs, but is unnecessary
dirty_files_count:set(4) -- The effect runs, but is unnecessary
```

For cases like these, this is where computeds come in:

```lua
local computed = require("signals.computed")

local dirty_files_count = signal(0)

local is_dirty = computed(function()
    return dirty_files_count:get() > 0
end)

effect(function()
    vim.o.statusline = is_dirty:get() > 0 and "⚠" or ""
end)
```

Now our statusline refreshes only when absolutely necessary, because our effect only runs when the returned value of `is_dirty` actually changed as a result of updating `dirty_files_count`.

One major difference to effects is that computeds are lazily evaluated, meaning they only refresh their state when you ask for it:

```lua
local dirty_files_count = signal(0)

local is_dirty = computed(function()
    return dirty_files_count:get() > 0
end)

-- The computed does not actually run until we ask for its current state:
print(is_dirty:get())

-- These will cause the computed to get marked as dirty only:
dirty_files_count:set(1)
dirty_files_count:set(2)
dirty_files_count:set(3)

-- The computed refreshes now since its dependencies have changed in the meantime:
print(is_dirty:get())

-- This returns from cache, as nothing changed in the meantime:
print(is_dirty:get())
```

<!-- panvimdoc-ignore-end -->

<!-- panvimdoc-ignore-start -->

# 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "michaelostermann/nvim-signals",
  lazy = true
}
```

<!-- panvimdoc-ignore-end -->

# 🚀 Usage

There are two ways provided to start using signals, pick whichever you prefer:

```lua
local s = require("signals")

s.signal
s.computed
s.effect
```

```lua
local signal = require("signals.signal")
local computed = require("signals.computed")
local effect = require("signals.effect")
```

# 🛠️ API

<!-- panvimdoc-ignore-start -->

- [`signal()`](#signal)
- [`signal:get()`](#signalget)
- [`signal:peek()`](#signalpeek)
- [`signal:set()`](#signalset)
- [`signal:is()`](#signalis)
- [`signal:map()`](#signalmap)
- [`computed()`](#computed)
- [`computed:get()`](#computedget)
- [`computed:peek()`](#computedpeek)
- [`computed:is()`](#computedis)
- [`effect()`](#effect)
- [`effect:dispose()`](#effectdispose)
- [`batch()`](#batch)
- [`batch_wrap()`](#batch_wrap)
- [`untracked()`](#untracked)
- [`untracked_wrap()`](#untracked_wrap)

<!-- panvimdoc-ignore-end -->

### `signal()`

Creates a new signal.

```lua
local signal = require("signals.signal")

local example = signal(0)
```

### `signal:get()`

Retrieves the current value of a signal.

Signals accessed this way will be added to the dependencies of the current computed or effect, if any. Use `signal:peek()` or `untracked()` if you would like to avoid this behaviour.

```lua
local signal = require("signals.signal")

local example = signal(0)

-- 0
print(example:get())
```

### `signal:peek()`

Like `signal:get()`, but will not become a dependency of effects or computeds.

```lua
local signal = require("signals.signal")

local example = signal(0)

-- 0
print(example:peek())
```

### `signal:set()`

Updates the current value of a signal. If the value changed (`==`), dependent computeds will get marked as dirty and effects will get scheduled for execution.

```lua
local signal = require("signals.signal")

local example = signal(0)

-- Effects and computeds using this signal will be informed about the change.
example:set(1)

-- 1
print(example:get())

-- The value did not change, so this has no side-effects.
example:set(1)
```

### `signal:is()`

An alias for `signal:get() == value`.

```lua
local signal = require("signals.signal")

local example = signal(0)

-- true
print(example:is(0))
-- false
print(example:is(1))
```

### `signal:map()`

An alias for `signal:set(fn(signal:peek()))`.

```lua
local signal = require("signals.signal")

local example = signal(0)

example:map(function(value)
    return value + 1
end)

-- 1
print(example:get())
```

### `computed()`

Creates a new computed, allowing you to combine the values of signals and other computeds.

```lua
local signal = require("signals.signal")
local computed = require("signals.computed")

local a = signal(1)
local b = signal(2)

local example = computed(function()
    return a:get() + b:get()
end)
```

### `computed:get()`

Retrieves the current value of a computed. This will cause the computation to refresh if its dependencies have changed since last time, otherwise the cached result is returned.

Computeds accessed this way will be added to the dependencies of the parent computed or current effect, if any. Use `computed:peek()` or `untracked()` if you would like to avoid this behaviour.

```lua
local signal = require("signals.signal")
local computed = require("signals.computed")

local a = signal(1)
local b = signal(2)

local example = computed(function()
    return a:get() + b:get()
end)

-- 3
print(example:get())
```

### `computed:peek()`

Like `computed:get()`, but will not become a dependency of effects or computeds.

```lua
local signal = require("signals.signal")
local computed = require("signals.computed")

local a = signal(1)
local b = signal(2)

local example = computed(function()
    return a:get() + b:get()
end)

-- 3
print(example:peek())
```

### `computed:is()`

An alias for `computed:get() == value`.

```lua
local signal = require("signals.signal")
local computed = require("signals.computed")

local a = signal(1)
local b = signal(2)

local example = computed(function()
    return a:get() + b:get()
end)

-- true
print(example:is(3))
-- false
print(example:is(4))
```

### `effect()`

Creates a new effect, allowing you to react to changes made to signals or computeds.

```lua
local signal = require("signals.signal")
local effect = require("signals.effect")

local a = signal(1)

effect(function()
    print(a:get())
end)
```

### `effect:dispose()`

Stops the effect from observing signals, allowing it to be garbage collected.

```lua
local signal = require("signals.signal")
local effect = require("signals.effect")

local a = signal(1)

local example = effect(function()
    print(a:get())
end)

example:dispose()
```

### `batch()`

Allows you to batch multiple signal updates into a single one.

Note that it is not necessary to use `batch` inside effects!

```lua
local signal = require("signals.signal")
local batch = require("signals.batch")

local a = signal(0)
local b = signal(0)

local result = batch(function()
    a:set(1)
    b:set(1)
    return a:get() + b:get()
end)

-- 2
print(result)
```

### `batch_wrap()`

Takes a function and decorates it with `batch()`, similar to `vim.schedule_wrap`.

```lua
local signal = require("signals.signal")
local batch_wrap = require("signals.batch_wrap")

local a = signal(0)
local b = signal(0)

local shippit = batch_wrap(function(left, right)
    a:set(left)
    b:set(right)
    return a:get() + b:get()
end)

-- 2
print(shippit(1, 1))
```

### `untracked()`

Prevents signals and computeds accessed within the provided function to get added as dependencies to the current computed or effect, if any.

```lua
local signal = require("signals.signal")
local effect = require("signals.effect")
local untracked = require("signals.untracked")

local a = signal(1)
local b = signal(1)

effect(function()
    print(a:get())
    
    local result = untracked(function()
        return a:get() + b:get()
    end)
    
    print(result)
end)

-- Prints 2 and 3
a:set(2)

-- Effect does not react
b:set(2)

-- Prints 3 and 5
a:set(3)
```

### `untracked_wrap()`

Takes a function and decorates it with `untracked()`, similar to `vim.schedule_wrap`.

```lua
local signal = require("signals.signal")
local effect = require("signals.effect")
local untracked_wrap = require("signals.untracked_wrap")

local a = signal(1)
local b = signal(1)

local example = untracked_wrap(function(value)
    return value + b:get()
end)

effect(function()
    print(a:get())
    print(example(a:get()))
end)

-- Prints 2 and 3
a:set(2)

-- Effect does not react
b:set(2)

-- Prints 3 and 5
a:set(3)
```

# 📘 Notes

## Garbage Collection

Any signal implementation has to implement something that at least somewhat resembles a graph data-structure. Some bookkeeping has to be done by maintaining references to signals, computeds and effects, in order to be able to determine dependencies and dependents.

Both dependencies and dependents are stored in [weak tables](https://www.lua.org/pil/17.html). This means that signals, and more importantly computeds, will get garbage collected once they become unreachable, otherwise they are retained in memory forever.

If you are storing signals or computeds somewhere, for example in tables to be able to relate them to specific buffers/windows, please take care to dereference them when no longer needed.

Effects are stored internally in a table, to prevent them from being immediately garbage collected. This means that effects live forever, and most definitely will keep references to signals and other computeds, preventing any them from being cleaned up.

Any effect that is no longer needed has to be removed by calling `effect:dispose()`, which will allow them to be garbage collected, including their dependencies if they became unreachable.
