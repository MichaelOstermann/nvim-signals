-- Ported from: https://github.com/preactjs/signals/blob/main/packages/core/test/signal.test.tsx
local signal = require("signals.signal")
local effect = require("signals.effect")
local computed = require("signals.computed")
local batch = require("signals.batch")
local spy = require("luassert.spy")

describe("effect()", function()
    it("should run the callback immediately", function()
        local s = signal(1)
        local cb = spy.new(function()
            s:get()
        end)
        effect(cb)
        assert.spy(cb).was.called(1)
    end)

    it("should subscribe to signals", function()
        local s = signal(1)
        local cb = spy.new(function()
            s:get()
        end)
        effect(cb)
        cb:clear()
        s:set(2)
        assert.spy(cb).was.called(1)
    end)

    it("should subscribe to multiple signals", function()
        local a = signal(0)
        local b = signal(0)
        local cb = spy.new(function()
            a:get()
            b:get()
        end)
        effect(cb)
        cb:clear()
        a:set(1)
        b:set(1)
        assert.spy(cb).was.called(2)
    end)

    it("should dispose of subscriptions", function()
        local a = signal(0)
        local b = signal(0)
        local cb = spy.new(function()
            a:get()
            b:get()
        end)
        local e = effect(cb)
        cb:clear()
        e:dispose()
        assert.spy(cb).was_not_called()
        a:set(1)
        b:set(1)
        assert.spy(cb).was_not_called()
    end)

    it("should conditionally unsubscribe from signals", function()
        local a = signal(0)
        local b = signal(0)
        local cond = signal(true)
        local cb = spy.new(function()
            if cond:get() then
                a:get()
            else
                b:get()
            end
        end)
        effect(cb)
        assert.spy(cb).was.called(1)
        b:set(1)
        assert.spy(cb).was.called(1)
        cond:set(false)
        assert.spy(cb).was.called(2)
        cb:clear()
        a:set(1)
        assert.spy(cb).was_not_called()
    end)

    it(
        "should not recompute if the effect has been notified about changes, but no direct dependency has actually changed",
        function()
            local s = signal(0)
            local c = computed(function()
                s:get()
                return 0
            end)
            local cb = spy.new(function()
                c:get()
            end)
            effect(cb)
            assert.spy(cb).was.called(1)
            cb:clear()
            s:set(1)
            assert.spy(cb).was_not_called()
        end
    )

    it("should not recompute dependencies unnecessarily", function()
        local a = signal(0)
        local b = signal(0)
        local cb = spy.new(function()
            b:get()
        end)
        local c = computed(cb)
        effect(function()
            if a:get() == 0 then
                c:get()
            end
        end)
        assert.spy(cb).was.called(1)
        batch(function()
            b:set(1)
            a:set(1)
        end)
        assert.spy(cb).was.called(1)
    end)

    it("should not recompute dependencies out of order", function()
        local a = signal(1)
        local b = signal(1)
        local c = signal(1)
        local cb = spy.new(function()
            c:get()
        end)
        local d = computed(cb)
        effect(function()
            if a:get() > 0 then
                b:get()
                d:get()
            else
                b:get()
            end
        end)
        cb:clear()
        batch(function()
            a:set(2)
            b:set(2)
            c:set(2)
        end)
        assert.spy(cb).was.called(1)
        cb:clear()
        batch(function()
            a:set(-1)
            b:set(-1)
            c:set(-1)
        end)
        assert.spy(cb).was_not_called()
    end)

    it("should recompute if a dependency changes during computation after becoming a dependency", function()
        local s = signal(0)
        local cb = spy.new(function()
            if s:get() == 0 then
                s:set(s:get() + 1)
            end
        end)
        effect(cb)
        assert.spy(cb).was.called(2)
    end)

    it("should not subscribe to anything if first run throws", function()
        local s = signal(0)
        local cb = spy.new(function()
            s:get()
            error("Whoops")
        end)
        assert.error_matches(function()
            effect(cb)
        end, "Whoops")
        assert.spy(cb).was.called(1)
        s:set(1)
        assert.spy(cb).was.called(1)
    end)

    it("should throw on cycles", function()
        local i = 0
        local a = signal(0)
        assert.error_matches(function()
            effect(function()
                -- Prevent test suite from spinning if limit is not hit
                i = i + 1
                if i > 200 then
                    error("Test failed")
                end
                a:get()
                a:set(i)
            end)
        end, "cycle detected")
    end)

    it("should allow disposing the effect multiple times", function()
        local e = effect(function() end)
        e:dispose()
        assert.has_no.errors(function()
            e:dispose()
        end)
    end)

    it("should allow disposing a running effect", function()
        local s = signal(0)
        local cb = spy.new(function() end)
        effect(function(e)
            if s:get() == 1 then
                e:dispose()
                cb()
            end
        end)
        assert.spy(cb).was_not_called()
        s:set(1)
        assert.spy(cb).was.called(1)
        s:set(2)
        assert.spy(cb).was.called(1)
    end)

    it("should not run if it's first been triggered and then disposed in a batch", function()
        local s = signal(0)
        local cb = spy.new(function()
            s:get()
        end)
        local e = effect(cb)
        cb:clear()
        batch(function()
            s:set(1)
            e:dispose()
        end)
        assert.spy(cb).was_not_called()
    end)

    it("should not run if it's been triggered, disposed and then triggered again in a batch", function()
        local s = signal(0)
        local cb = spy.new(function()
            s:get()
        end)
        local e = effect(cb)
        cb:clear()
        batch(function()
            s:set(1)
            e:dispose()
            s:set(2)
        end)
        assert.spy(cb).was_not_called()
    end)

    it("should not rerun parent effect if a nested child effect's signal's value changes", function()
        local parent_signal = signal(0)
        local child_signal = signal(0)
        local parent_effect = spy.new(function()
            parent_signal:get()
        end)
        local child_effect = spy.new(function()
            child_signal:get()
        end)

        effect(function()
            parent_effect()
            effect(child_effect)
        end)

        assert.spy(parent_effect).was.called(1)
        assert.spy(child_effect).was.called(1)

        child_signal:set(1)

        assert.spy(parent_effect).was.called(1)
        assert.spy(child_effect).was.called(2)

        parent_signal:set(1)

        assert.spy(parent_effect).was.called(2)
        assert.spy(child_effect).was.called(3)
    end)
end)