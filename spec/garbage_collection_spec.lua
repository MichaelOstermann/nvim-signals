-- Ported from: https://github.com/preactjs/signals/blob/main/packages/core/test/signal.test.tsx
local signal = require("signals.signal")
local effect = require("signals.effect")
local computed = require("signals.computed")
local spy = require("luassert.spy")

describe("gc:", function()
    it("should be garbage collectable if nothing is listening to its changes", function()
        local s = signal(0)
        local t = setmetatable({
            computed(function()
                return s:get()
            end),
        }, { __mode = "v" })
        collectgarbage()
        assert.are.equal(t[1], nil)
    end)

    it("should be garbage collectable after it has lost all of its listeners", function()
        local s = signal(0)
        local t = setmetatable({
            computed(function()
                return s:get()
            end),
        }, { __mode = "v" })
        local e = effect(function()
            t[1]:get()
        end)
        e:dispose()
        collectgarbage()
        assert.are.equal(t[1], nil)
    end)
end)
