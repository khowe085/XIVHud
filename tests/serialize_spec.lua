local serialize = require("lib.serialize")

describe("serialize", function()
  -- Reads the emitted chunk back the way lib/settings does: sandboxed, no globals.
  local function roundtrip(value)
    local chunk = assert(loadstring(serialize(value)))
    setfenv(chunk, {})
    return chunk()
  end

  it("emits an empty table", function()
    assert.are.equal("return {}\n", serialize({}))
  end)

  it("emits string keys in sorted order regardless of insertion order", function()
    local t = {}
    t.zulu = 1
    t.alpha = 2
    t.mike = 3
    assert.are.equal("return {\n  alpha = 2,\n  mike = 3,\n  zulu = 1,\n}\n", serialize(t))
  end)

  it("emits the array part positionally, before keyed entries", function()
    assert.are.equal('return {\n  "a",\n  "b",\n  name = "list",\n}\n', serialize({ "a", "b", name = "list" }))
  end)

  it("indents nested tables", function()
    local expected = "return {\n  pos = {\n    x = 10,\n    y = 20,\n  },\n}\n"
    assert.are.equal(expected, serialize({ pos = { x = 10, y = 20 } }))
  end)

  it("brackets keys that are not Lua identifiers", function()
    assert.are.equal('return {\n  ["two words"] = 1,\n}\n', serialize({ ["two words"] = 1 }))
    assert.are.equal("return {\n  [7] = 1,\n}\n", serialize({ [7] = 1 }))
  end)

  it("escapes characters that would break the emitted chunk", function()
    local restored = roundtrip({ s = 'quote " backslash \\ newline \n tab \t' })
    assert.are.equal('quote " backslash \\ newline \n tab \t', restored.s)
    assert.are.equal('return {\n  s = "a\\nb",\n}\n', serialize({ s = "a\nb" }))
  end)

  it("round-trips booleans, negative and fractional numbers", function()
    local restored = roundtrip({ on = true, off = false, neg = -3, frac = 0.5 })
    assert.is_true(restored.on)
    assert.is_false(restored.off)
    assert.are.equal(-3, restored.neg)
    assert.are.equal(0.5, restored.frac)
  end)

  it("writes whole numbers without a decimal point", function()
    assert.are.equal("return {\n  n = 1,\n}\n", serialize({ n = 1 }))
  end)

  it("round-trips a realistic component config", function()
    local cfg = {
      compact = false,
      bar = { width = 132, spacing = 18 },
      slots = { default = { pos = { x = 100, y = 200 }, scale = 1, visible = true } },
    }
    assert.are.same(cfg, roundtrip(cfg))
  end)

  it("rejects values it cannot represent", function()
    assert.has_error(function()
      serialize({ fn = print })
    end)
    assert.has_error(function()
      serialize({ [true] = 1 })
    end)
  end)

  it("rejects cyclic tables instead of recursing forever", function()
    local t = {}
    t.self = t
    assert.has_error(function()
      serialize(t)
    end)
  end)
end)
