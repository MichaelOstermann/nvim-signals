-- Ported from: https://github.com/preactjs/signals/blob/main/packages/core/test/signal.test.tsx
local signal = require("signals.signal")
local effect = require("signals.effect")
local computed = require("signals.computed")
local batch = require("signals.batch")
local spy = require("luassert.spy")

describe("graph", function()
    it("should run computeds once for multiple dep changes", function()
        local a = signal("a")
        local b = signal("b")
        local cb = spy.new(function()
            return a:get() .. b:get()
        end)
        local c = computed(cb)
        assert.are.equal(c:get(), "ab")
        assert.spy(cb).was.called(1)
        cb:clear()
        a:set("aa")
        b:set("bb")
        c:get()
        assert.spy(cb).was.called(1)
    end)

    it("should drop A->B->A updates", function()
        local a = signal(2)
        local b = computed(function()
            return a:get() - 1
        end)
        local c = computed(function()
            return a:get() + b:get()
        end)
        local cb = spy.new(function()
            return "d: " .. c:get()
        end)
        local d = computed(cb)
        assert.are.equal(d:get(), "d: 3")
        assert.spy(cb).was.called(1)
        cb:clear()
        a:set(4)
        d:get()
        assert.spy(cb).was.called(1)
    end)

    it("should only update every signal once (diamond graph)", function()
        local a = signal("a")
        local b = computed(function()
            return a:get()
        end)
        local c = computed(function()
            return a:get()
        end)
        local cb = spy.new(function()
            return b:get() .. " " .. c:get()
        end)
        local d = computed(cb)
        assert.are.equal(d:get(), "a a")
        assert.spy(cb).was.called(1)
        a:set("aa")
        assert.are.equal(d:get(), "aa aa")
        assert.spy(cb).was.called(2)
    end)

    it("should only update every signal once (diamond graph + tail)", function()
        local a = signal("a")
        local b = computed(function()
            return a:get()
        end)
        local c = computed(function()
            return a:get()
        end)
        local d = computed(function()
            return b:get() .. " " .. c:get()
        end)
        local cb = spy.new(function()
            return d:get()
        end)
        local e = computed(cb)
        assert.are.equal(e:get(), "a a")
        assert.spy(cb).was.called(1)
        a:set("aa")
        assert.are.equal(e:get(), "aa aa")
        assert.spy(cb).was.called(2)
    end)

    it("should bail out if result is the same", function()
        local a = signal("a")
        local b = computed(function()
            a:get()
            return "foo"
        end)
        local cb = spy.new(function()
            return b:get()
        end)
        local c = computed(cb)
        assert.are.equal(c:get(), "foo")
        assert.spy(cb).was.called(1)
        a:set("aa")
        assert.are.equal(c:get(), "foo")
        assert.spy(cb).was.called(1)
    end)

    it("should only update every signal once (jagged diamond graph + tails)", function()
        local stack = {}
        local a = signal("a")
        local b = computed(function()
            return a:get()
        end)
        local c = computed(function()
            return a:get()
        end)
        local d = computed(function()
            return c:get()
        end)
        local eSpy = spy.new(function()
            table.insert(stack, "eSpy")
            return b:get() .. " " .. d:get()
        end)
        local e = computed(eSpy)
        local fSpy = spy.new(function()
            table.insert(stack, "fSpy")
            return e:get()
        end)
        local f = computed(fSpy)
        local gSpy = spy.new(function()
            table.insert(stack, "gSpy")
            return e:get()
        end)
        local g = computed(gSpy)

        assert.are.equal(f:get(), "a a")
        assert.spy(fSpy).was.called(1)
        assert.are.equal(g:get(), "a a")
        assert.spy(gSpy).was.called(1)

        eSpy:clear()
        fSpy:clear()
        gSpy:clear()

        a:set("b")

        assert.are.equal(e:get(), "b b")
        assert.spy(eSpy).was.called(1)
        assert.are.equal(f:get(), "b b")
        assert.spy(fSpy).was.called(1)
        assert.are.equal(g:get(), "b b")
        assert.spy(gSpy).was.called(1)

        eSpy:clear()
        fSpy:clear()
        gSpy:clear()
        stack = {}

        a:set("c")

        assert.are.equal(e:get(), "c c")
        assert.spy(eSpy).was.called(1)
        assert.are.equal(f:get(), "c c")
        assert.spy(fSpy).was.called(1)
        assert.are.equal(g:get(), "c c")
        assert.spy(gSpy).was.called(1)

        assert.are.same(stack, { "eSpy", "fSpy", "gSpy" })
    end)

    it("should only subscribe to signals listened to", function()
        local a = signal("a")
        local b = computed(function()
            return a:get()
        end)
        local cb = spy.new(function()
            return a:get()
        end)
        computed(cb)
        assert.are.equal(b:get(), "a")
        assert.spy(cb).was_not_called()
        a:set("aa")
        assert.are.equal(b:get(), "aa")
        assert.spy(cb).was_not_called()
    end)

    it("should only subscribe to signals listened to", function()
        local a = signal("a")
        local spyB = spy.new(function()
            return a:get()
        end)
        local b = computed(spyB)
        local spyC = spy.new(function()
            return b:get()
        end)
        local c = computed(spyC)
        local d = computed(function()
            return a:get()
        end)
        local result = ""
        local e = effect(function()
            result = c:get()
        end)
        assert.are.equal(result, "a")
        assert.are.equal(d:get(), "a")
        spyB:clear()
        spyC:clear()
        e:dispose()
        a:set("aa")
        assert.spy(spyB).was_not_called()
        assert.spy(spyC).was_not_called()
        assert.are.equal(d:get(), "aa")
    end)

    it("should ensure subs update even if one dep unmarks it", function()
        local a = signal("a")
        local b = computed(function()
            return a:get()
        end)
        local c = computed(function()
            a:get()
            return "c"
        end)
        local cb = spy.new(function()
            return b:get() .. " " .. c:get()
        end)
        local d = computed(cb)
        assert.are.equal(d:get(), "a c")
        cb:clear()
        a:set("aa")
        d:get()
        assert.spy(cb).returned_with("aa c")
    end)

    it("should ensure subs update even if two deps unmark it", function()
        local a = signal("a")
        local b = computed(function()
            return a:get()
        end)
        local c = computed(function()
            a:get()
            return "c"
        end)
        local d = computed(function()
            a:get()
            return "d"
        end)
        local cb = spy.new(function()
            return b:get() .. " " .. c:get() .. " " .. d:get()
        end)
        local e = computed(cb)
        assert.are.equal(e:get(), "a c d")
        cb:clear()
        a:set("aa")
        e:get()
        assert.spy(cb).returned_with("aa c d")
    end)
end)
