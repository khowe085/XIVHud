local categories = require("components/statusbar/categories")
local buff_order = require("lib/buff_order")

describe("statusbar categories", function()
  it("offers the four predefined filters, all first", function()
    assert.are.same({ "all", "enhancements", "debuffs", "other" }, categories.NAMES)
  end)

  it("knows the debuffs that open the shipped order", function()
    for _, id in ipairs({ 0, 1, 15, 2, 3, 6, 144 }) do
      assert.are.equal("debuffs", categories.category_of(id), "buff " .. id)
    end
  end)

  it("puts food and the system buffs under other", function()
    -- Food, Signet, Sanction, Sigil, Ionis, Dedication, Level Restriction.
    for _, id in ipairs({ 251, 253, 256, 268, 512, 249, 143 }) do
      assert.are.equal("other", categories.category_of(id), "buff " .. id)
    end
  end)

  it("calls everything else an enhancement, ranked or not", function()
    -- haste, protect, and an id nothing ranks
    for _, id in ipairs({ 33, 40, 9998 }) do
      assert.are.equal("enhancements", categories.category_of(id), "buff " .. id)
    end
  end)

  it("keeps no id in both curated sets", function()
    for id in pairs(categories.DEBUFFS) do
      assert.is_nil(categories.OTHER[id], "buff " .. id .. " is a debuff and other")
    end
  end)

  it("curates only ids the shipped order ranks", function()
    local ranked = {}
    for _, id in ipairs(buff_order) do
      ranked[id] = true
    end
    for _, set in ipairs({ categories.DEBUFFS, categories.OTHER }) do
      for id in pairs(set) do
        assert.is_true(ranked[id] == true, "buff " .. id .. " is curated but unranked")
      end
    end
  end)

  describe("keep", function()
    it("restricts nothing for all", function()
      assert.is_nil(categories.keep("all"))
    end)

    it("admits only the category named", function()
      assert.is_true(categories.keep("debuffs")(2))
      assert.is_false(categories.keep("debuffs")(33))
      assert.is_true(categories.keep("enhancements")(33))
      assert.is_false(categories.keep("enhancements")(251))
      assert.is_false(categories.keep("enhancements")(2))
      assert.is_true(categories.keep("other")(251))
      assert.is_false(categories.keep("other")(33))
    end)

    it("answers nothing for a name it does not know", function()
      assert.is_nil(categories.keep("wobble"))
      assert.is_nil(categories.keep(nil))
    end)
  end)
end)
