local categories = require("components/statusbar/categories")
local buff_order = require("lib/buff_order")

describe("statusbar categories", function()
  it("offers the four predefined filters, all first", function()
    assert.are.same({ "all", "buffs", "debuffs", "other" }, categories.NAMES)
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

  it("calls everything else a buff, ranked or not", function()
    -- haste, protect, and an id nothing ranks
    for _, id in ipairs({ 33, 40, 9998 }) do
      assert.are.equal("buffs", categories.category_of(id), "buff " .. id)
    end
  end)

  it("keeps no id in both curated sets", function()
    for id in pairs(categories.DEBUFFS) do
      assert.is_nil(categories.OTHER[id], "buff " .. id .. " is a debuff and other")
    end
  end)

  -- The debuff set is a hand copy of the shipped order's opening section;
  -- pinning where that section ends is what catches a debuff added to the
  -- order later and landing on the buffs bar.
  it("holds exactly the debuff section that opens the shipped order", function()
    local section_end = 91
    for rank = 1, section_end do
      assert.is_true(categories.DEBUFFS[buff_order[rank]] == true, "rank " .. rank .. " is not a debuff")
    end
    assert.is_nil(categories.DEBUFFS[buff_order[section_end + 1]], "the section ends at rank " .. section_end)
    local count = 0
    for _ in pairs(categories.DEBUFFS) do
      count = count + 1
    end
    assert.are.equal(section_end, count)
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
      assert.is_true(categories.keep("buffs")(33))
      assert.is_false(categories.keep("buffs")(251))
      assert.is_false(categories.keep("buffs")(2))
      assert.is_true(categories.keep("other")(251))
      assert.is_false(categories.keep("other")(33))
    end)

    it("answers nothing for a name it does not know", function()
      assert.is_nil(categories.keep("wobble"))
      assert.is_nil(categories.keep(nil))
    end)
  end)
end)
