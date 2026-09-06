local defaults = require("lib/actionbar/defaults")

describe("the shared bar defaults", function()
  it("ships the slot cosmetics every bar draws with", function()
    local cosmetics = defaults.cosmetics()
    assert.are.equal(6, cosmetics.slot_spacing)
    assert.are.equal(100, cosmetics.slot_alpha)
    assert.are.equal(100, cosmetics.disabled_alpha)
    assert.are.equal(7, cosmetics.font_size)
    assert.are.same({ alpha = 150, speed = 30 }, cosmetics.feedback)
    assert.is_false(cosmetics.hide.empty_slots)
    assert.is_true(cosmetics.hide.element)
    assert.are.same({ r = 230, g = 91, b = 151 }, cosmetics.mp_cost_color)
    assert.are.equal("", cosmetics.game_path)
  end)

  it("hands out a fresh table each time", function()
    local a, b = defaults.cosmetics(), defaults.cosmetics()
    a.hide.cost = true
    assert.is_false(b.hide.cost)
  end)

  it("ships eight sets unshared and cycled in both weapon states", function()
    local flags = defaults.set_flags()
    assert.are.equal(8, #flags)
    for set = 1, 8 do
      assert.are.same({ shared = false, cycle = { drawn = true, sheathed = true } }, flags[set])
    end
  end)
end)
