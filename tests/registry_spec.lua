local new_registry = require("lib.registry")

describe("registry", function()
  local warnings, registry

  local function component(name)
    local c = { name = name, destroyed = 0 }
    function c.destroy()
      c.destroyed = c.destroyed + 1
    end
    return c
  end

  before_each(function()
    warnings = {}
    registry = new_registry({
      reserved = { help = true, layout = true, list = true },
      notify = function(msg)
        warnings[#warnings + 1] = msg
      end,
    })
  end)

  describe("registration", function()
    it("returns the registered component and finds it by name", function()
      local bar = component("parambar")
      assert.are.equal(bar, registry.register(bar))
      assert.are.equal(bar, registry.get("parambar"))
    end)

    it("looks components up case-insensitively", function()
      registry.register(component("parambar"))
      assert.is_not_nil(registry.get("ParamBar"))
    end)

    it("returns nil for an unknown component", function()
      assert.is_nil(registry.get("nope"))
      assert.is_nil(registry.get(nil))
    end)

    it("refuses a duplicate name", function()
      registry.register(component("parambar"))
      assert.has_error(function()
        registry.register(component("parambar"))
      end)
    end)

    it("refuses a name that collides with a reserved verb", function()
      assert.has_error(function()
        registry.register(component("layout"))
      end)
      assert.has_error(function()
        registry.register(component("LIST"))
      end)
    end)

    it("refuses 'all', which //xh reset already means", function()
      assert.has_error(function()
        registry.register(component("all"))
      end)
    end)

    it("refuses names that cannot be typed as a single command word", function()
      for _, bad in ipairs({ "", "two words", "9lives", "has-dash" }) do
        assert.has_error(function()
          registry.register(component(bad))
        end, nil, "expected '" .. bad .. "' to be rejected")
      end
      assert.has_error(function()
        registry.register({})
      end)
    end)
  end)

  describe("enumeration", function()
    it("preserves registration order", function()
      registry.register(component("alpha"))
      registry.register(component("bravo"))
      registry.register(component("charlie"))
      assert.are.same({ "alpha", "bravo", "charlie" }, registry.names())
      assert.are.equal("bravo", registry.all()[2].name)
    end)

    it("hands out a copy, so callers cannot reorder the registry", function()
      registry.register(component("alpha"))
      local names = registry.names()
      names[1] = "hacked"
      assert.are.same({ "alpha" }, registry.names())
    end)
  end)

  describe("teardown", function()
    it("destroys components in reverse registration order", function()
      local order = {}
      for _, name in ipairs({ "alpha", "bravo", "charlie" }) do
        local c = component(name)
        c.destroy = function()
          order[#order + 1] = name
        end
        registry.register(c)
      end
      registry.destroy_all()
      assert.are.same({ "charlie", "bravo", "alpha" }, order)
    end)

    it("empties the registry so a reload can re-register", function()
      registry.register(component("alpha"))
      registry.destroy_all()
      assert.are.same({}, registry.names())
      assert.is_nil(registry.get("alpha"))
      assert.has_no.errors(function()
        registry.register(component("alpha"))
      end)
    end)

    it("keeps destroying after one component blows up, and warns", function()
      local survivor = component("alpha")
      registry.register(survivor)
      local bomb = component("bravo")
      bomb.destroy = function()
        error("prim already gone")
      end
      registry.register(bomb)

      registry.destroy_all()
      assert.are.equal(1, survivor.destroyed)
      assert.are.equal(1, #warnings)
    end)

    it("tolerates a component without a destroy method", function()
      registry.register({ name = "alpha" })
      assert.has_no.errors(function()
        registry.destroy_all()
      end)
    end)
  end)
end)
