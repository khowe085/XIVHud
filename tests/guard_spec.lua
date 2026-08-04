local new_guard = require("lib.guard")

describe("guard", function()
  local said, guard

  before_each(function()
    said = {}
    guard = new_guard({
      limit = 3,
      notify = function(message)
        said[#said + 1] = message
      end,
    })
  end)

  local function joined()
    return table.concat(said, "\n")
  end

  describe("when nothing goes wrong", function()
    it("passes arguments through and returns the result", function()
      local wrapped = guard.wrap("mouse", function(a, b)
        return a + b
      end)
      assert.are.equal(7, wrapped(3, 4))
      assert.are.same({}, said)
    end)

    it("passes a false return through, rather than losing it", function()
      local wrapped = guard.wrap("mouse", function()
        return false
      end)
      assert.is_false(wrapped())
    end)
  end)

  describe("when a handler raises", function()
    it("reports the handler and the error instead of letting it escape", function()
      local wrapped = guard.wrap("prerender", function()
        error("something broke")
      end)
      assert.has_no.errors(wrapped)
      assert.is_not_nil(joined():find("prerender", 1, true))
      assert.is_not_nil(joined():find("something broke", 1, true))
    end)

    it("returns the fallback the caller asked for", function()
      local wrapped = guard.wrap("mouse", function()
        error("nope")
      end, false)
      assert.is_false(wrapped(), "a mouse handler must never block input by erroring")
    end)

    it("says the same thing only once, however often it recurs", function()
      local wrapped = guard.wrap("prerender", function()
        error("same every frame")
      end)
      wrapped()
      wrapped()
      wrapped()
      assert.are.equal(2, #said, "one report, then the disable notice")
    end)

    it("reports a different error from the same handler", function()
      local calls = 0
      local wrapped = guard.wrap("prerender", function()
        calls = calls + 1
        error("failure " .. calls)
      end)
      wrapped()
      wrapped()
      assert.is_not_nil(joined():find("failure 1", 1, true))
      assert.is_not_nil(joined():find("failure 2", 1, true))
    end)
  end)

  describe("giving up", function()
    it("stops calling a handler that keeps failing, and says so", function()
      local calls = 0
      local wrapped = guard.wrap("prerender", function()
        calls = calls + 1
        error("broken " .. calls)
      end)

      for _ = 1, 10 do
        wrapped()
      end
      assert.are.equal(3, calls, "a handler that fails every frame must not run every frame")
      assert.is_not_nil(joined():lower():find("disabled"))
      assert.is_not_nil(joined():find("//lua reload", 1, true))
    end)

    it("keeps returning the fallback once disabled", function()
      local wrapped = guard.wrap("mouse", function()
        error("broken")
      end, false)
      for _ = 1, 10 do
        assert.is_false(wrapped())
      end
    end)

    it("gives up on each handler separately", function()
      local healthy = 0
      local ok = guard.wrap("command", function()
        healthy = healthy + 1
      end)
      local bad = guard.wrap("prerender", function()
        error("broken")
      end)

      for _ = 1, 10 do
        bad()
        ok()
      end
      assert.are.equal(10, healthy, "one bad handler must not silence the others")
    end)

    it("reports whether anything has been disabled", function()
      assert.is_false(guard.failed())
      local wrapped = guard.wrap("prerender", function()
        error("broken")
      end)
      for _ = 1, 5 do
        wrapped()
      end
      assert.is_true(guard.failed())
    end)
  end)
end)
