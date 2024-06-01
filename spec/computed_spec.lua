-- Ported from: https://github.com/preactjs/signals/blob/main/packages/core/test/signal.test.tsx
local signal = require("signals.signal")
local effect = require("signals.effect")
local computed = require("signals.computed")
local batch = require("signals.batch")
local spy = require("luassert.spy")

describe("computed()", function()
    it("should return value", function()
        local a = signal("a")
        local b = signal("b")
        local c = computed(function()
            return a:get() .. b:get()
        end)
        assert.are.equal(c:get(), "ab")
    end)

    it("should return updated value", function()
        local a = signal("a")
        local b = signal("b")
        local c = computed(function()
            return a:get() .. b:get()
        end)
        assert.are.equal(c:get(), "ab")
        a:set("aa")
        assert.are.equal(c:get(), "aab")
    end)

    it("should be lazily computed on demand", function()
        local a = signal("a")
        local b = signal("b")
        local cb = spy.new(function()
            return a:get() .. b:get()
        end)
        local c = computed(cb)
        assert.spy(cb).was_not_called()
        c:get()
        assert.spy(cb).was.called(1)
        a:set("x")
        b:set("y")
        assert.spy(cb).was.called(1)
        c:get()
        assert.spy(cb).was.called(2)
    end)

    it("should be computed only when a dependency has changed at some point", function()
        local a = signal("a")
        local cb = spy.new(function()
            return a:get()
        end)
        local c = computed(cb)
        c:get()
        assert.spy(cb).was.called(1)
        a:set("a")
        c:get()
        assert.spy(cb).was.called(1)
    end)

    it("should throw if a signal is being written to during computation", function()
        local a = signal(0)
        local cb = spy.new(function()
            a:set(a:get() + 1)
        end)
        local c = computed(cb)
        assert.error_matches(function()
            c:get()
        end, "attempt to write to Signal<.*>%(.+%) during Computed<.*>%(.+%)")
    end)

    it("should conditionally unsubscribe from signals", function()
        local a = signal("a")
        local b = signal("b")
        local cond = signal(true)
        local cb = spy.new(function()
            return cond:get() and a:get() or b:get()
        end)
        local c = computed(cb)
        assert.are.equal(c:get(), "a")
        assert.spy(cb).was.called(1)
        b:set("bb")
        assert.are.equal(c:get(), "a")
        assert.spy(cb).was.called(1)
        cond:set(false)
        assert.are.equal(c:get(), "bb")
        assert.spy(cb).was.called(2)
        cb:clear()
        a:set("aaa")
        assert.are.equal(c:get(), "bb")
        assert.spy(cb).was_not_called()
    end)

    it("should propagate notifications even right after first subscription", function()
        local a = signal(0)
        local b = computed(function()
            return a:get()
        end)
        local c = computed(function()
            return b:get()
        end)
        c:get()
        local cb = spy.new(function()
            return c:get()
        end)
        effect(cb)
        assert.spy(cb).was.called(1)
        cb:clear()
        a:set(1)
        assert.spy(cb).was.called(1)
    end)

    it("should get marked as outdated right after first subscription", function()
        local s = signal(0)
        local c = computed(function()
            return s:get()
        end)
        c:get()
        s:set(1)
        effect(function()
            c:get()
        end)
        assert.are.equal(c:get(), 1)
    end)

    it("should propagate notification to other listeners after one listener is disposed", function()
        local s = signal(0)
        local c = computed(function()
            return s:get()
        end)
        local spy1 = spy.new(function()
            return c:get()
        end)
        local spy2 = spy.new(function()
            return c:get()
        end)
        local spy3 = spy.new(function()
            return c:get()
        end)
        effect(spy1)
        local e = effect(spy2)
        effect(spy3)
        assert.spy(spy1).was.called(1)
        assert.spy(spy2).was.called(1)
        assert.spy(spy3).was.called(1)
        e:dispose()
        s:set(1)
        assert.spy(spy1).was.called(2)
        assert.spy(spy2).was.called(1)
        assert.spy(spy3).was.called(2)
    end)

    it("should not recompute dependencies out of order", function()
        local a = signal(1)
        local b = signal(1)
        local c = signal(1)
        local cb = spy.new(function()
            return c:get()
        end)
        local d = computed(cb)
        local e = computed(function()
            if a:get() > 0 then
                b:get()
                d:get()
            else
                b:get()
            end
        end)
        e:get()
        cb:clear()
        a:set(2)
        b:set(2)
        c:set(2)
        e:get()
        assert.spy(cb).was.called(1)
        cb:clear()
        a:set(-1)
        b:set(-1)
        c:set(-1)
        e:get()
        assert.spy(cb).was_not_called()
    end)

    it("should not recompute dependencies unnecessarily", function()
        local a = signal(0)
        local b = signal(0)
        local cb = spy.new(function()
            b:get()
        end)
        local c = computed(cb)
        local d = computed(function()
            if a:get() == 0 then
                c:get()
            end
        end)
        d:get()
        assert.spy(cb).was.called(1)
        batch(function()
            b:set(1)
            a:set(1)
        end)
        d:get()
        assert.spy(cb).was.called(1)
    end)

    it("should support lazy branches", function()
        local a = signal(0)
        local b = computed(function()
            return a:get()
        end)
        local c = computed(function()
            if a:get() > 0 then
                return a:get()
            else
                return b:get()
            end
        end)
        assert.are.equal(c:get(), 0)
        a:set(1)
        assert.are.equal(c:get(), 1)
        a:set(0)
        assert.are.equal(c:get(), 0)
    end)

    it("should not update a sub if all deps unmark it", function()
        local a = signal("a")
        local b = computed(function()
            a:get()
            return "b"
        end)
        local c = computed(function()
            a:get()
            return "c"
        end)
        local cb = spy.new(function()
            return b:get() .. " " .. c:get()
        end)
        local d = computed(cb)
        assert.are.equal(d:get(), "b c")
        cb:clear()
        a:set("aa")
        assert.spy(cb).was_not_called()
    end)

    it("should detect simple dependency cycles", function()
        local a
        a = computed(function()
            a:get()
        end)
        assert.error_matches(function()
            a:get()
        end, "cycle detected")
    end)

    it("should detect deep dependency cycles", function()
        local a, b, c, d
        a = computed(function()
            return b:get()
        end)
        b = computed(function()
            return c:get()
        end)
        c = computed(function()
            return d:get()
        end)
        d = computed(function()
            return a:get()
        end)
        assert.error_matches(function()
            a:get()
        end, "cycle detected")
    end)

    it("should not allow a computed signal to become a direct dependency of itself", function()
        local a
        local cb = spy.new(function()
            pcall(function()
                a:get()
            end)
        end)
        a = computed(cb)
        a:get()
        assert.has_not.error(function()
            effect(function()
                a:get()
            end)
        end)
    end)

    it("should store thrown errors and recompute only after a dependency changes", function()
        local a = signal(0)
        local cb = spy.new(function()
            a:get()
            error("Whoops")
        end)
        local c = computed(cb)
        assert.has_error(function()
            c:get()
        end)
        assert.has_error(function()
            c:get()
        end)
        assert.spy(cb).was.called(1)
        a:set(1)
        assert.has_error(function()
            c:get()
        end)
        assert.spy(cb).was.called(2)
    end)

    it("should not leak errors raised by dependencies", function()
        local a = signal(0)
        local b = computed(function()
            a.get()
            error("Whoops")
        end)
        local c = computed(function()
            local ok, result = pcall(function()
                return b:get()
            end)
            if ok then
                return result
            else
                return "ok"
            end
        end)
        assert.are.equal(c:get(), "ok")
        a:set(1)
        assert.are.equal(c:get(), "ok")
    end)

    it("should store thrown non-errors and recompute only after a dependency changes", function()
        local a = signal(0)
        local cb = spy.new(function() end)
        local c = computed(function()
            a:get()
            cb()
            error("Whoops")
        end)
        assert.has_error(function()
            c:get()
        end)
        assert.has_error(function()
            c:get()
        end)
        assert.spy(cb).was.called(1)
        a:set(1)
        assert.has_error(function()
            c:get()
        end)
        assert.spy(cb).was.called(2)
    end)

    it("should throw when writing to computeds", function()
        local a = signal("a")
        local b = computed(function()
            return a:get()
        end)
        assert.error_matches(function()
            b:set("aa")
        end, "attempt to write to Computed<.*>%(.*%)")
    end)

    it("should keep graph consistent on errors during activation", function()
        local a = signal(0)
        local b = computed(function()
            error("Whoops")
        end)
        local c = computed(function()
            return a:get()
        end)
        assert.error_matches(function()
            b:get()
        end, "Whoops")
        a:set(1)
        assert.are.equal(c:get(), 1)
    end)

    it("should keep graph consistent on errors in computeds", function()
        local a = signal(0)
        local b = computed(function()
            if a:get() == 1 then
                error("Whoops")
            else
                return a:get()
            end
        end)
        local c = computed(function()
            return b:get()
        end)
        assert.are.equal(c:get(), 0)
        a:set(1)
        assert.error_matches(function()
            b:get()
        end, "Whoops")
        a:set(2)
        assert.are.equal(c:get(), 2)
    end)

    describe(":peek()", function()
        it("should get value", function()
            local s = signal(1)
            local c = computed(function()
                return s:get()
            end)
            assert.are.equal(c:peek(), 1)
        end)

        it("should throw when evaluation throws", function()
            local c = computed(function()
                error("Whoops")
            end)
            assert.error_matches(function()
                c:peek()
            end, "Whoops")
        end)

        it("should throw when previous evaluation threw and dependencies haven't changed", function()
            local c = computed(function()
                error("Whoops")
            end)
            assert.error_matches(function()
                c:get()
            end, "Whoops")
            assert.error_matches(function()
                c:peek()
            end, "Whoops")
        end)

        it("should refresh value if stale", function()
            local a = signal(1)
            local b = computed(function()
                return a:get()
            end)
            assert.are.equal(b:peek(), 1)
            a:set(2)
            assert.are.equal(b:peek(), 2)
        end)

        it("should not make surrounding effect depend on the computed", function()
            local s = signal(1)
            local c = computed(function()
                return s:get()
            end)
            local cb = spy.new(function()
                c:peek()
            end)
            effect(cb)
            assert.spy(cb).was.called(1)
            s:set(2)
            assert.spy(cb).was.called(1)
        end)

        it("should not make surrounding computed depend on the computed", function()
            local s = signal(1)
            local c = computed(function()
                return s:get()
            end)
            local cb = spy.new(function()
                c:peek()
            end)
            local d = computed(cb)
            d:get()
            assert.spy(cb).was.called(1)
            s:set(2)
            d:get()
            assert.spy(cb).was.called(1)
        end)

        it("should not make surrounding effect depend on the peeked computed's dependencies", function()
            local a = signal(1)
            local b = computed(function()
                return a:get()
            end)
            local cb = spy.new(function()
                b:peek()
            end)
            effect(cb)
            assert.spy(cb).was.called(1)
            cb:clear()
            a:set(1)
            assert.spy(cb).was_not_called()
        end)

        it("should not make surrounding computed depend on peeked computed's dependencies", function()
            local a = signal(1)
            local b = computed(function()
                return a:get()
            end)
            local cb = spy.new(function()
                b:peek()
            end)
            local d = computed(cb)
            d:get()
            assert.spy(cb).was.called(1)
            cb:clear()
            a:set(1)
            d:get()
            assert.spy(cb).was_not_called()
        end)

        it("should detect simple dependency cycles", function()
            local a
            a = computed(function()
                a:peek()
            end)
            assert.error_matches(function()
                a:peek()
            end, "cycle detected")
        end)

        it("should detect deep dependency cycles", function()
            local a, b, c, d
            a = computed(function()
                return b:get()
            end)
            b = computed(function()
                return c:get()
            end)
            c = computed(function()
                return d:get()
            end)
            d = computed(function()
                return a:peek()
            end)
            assert.error_matches(function()
                a:peek()
            end, "cycle detected")
        end)
    end)
end)