local buff_order = require("lib/buff_order")

describe("shipped buff order", function()
  it("carries every entry XIVParty ranks", function()
    assert.are.equal(621, #buff_order)
  end)

  -- The whole file is one ranking, so a duplicate id would make the rank of
  -- that buff depend on which copy the lookup reached first.
  it("ranks each buff id exactly once", function()
    local seen = {}
    for rank, id in ipairs(buff_order) do
      assert.is_nil(seen[id], ("buff id %d is ranked twice, at %d and %d"):format(id, seen[id] or 0, rank))
      seen[id] = rank
    end
  end)

  it("holds nothing but whole non-negative ids", function()
    for rank, id in ipairs(buff_order) do
      assert.are.equal("number", type(id), "rank " .. rank .. " is not a number")
      assert.are.equal(id, math.floor(id), "rank " .. rank .. " is not a whole number")
      assert.is_true(id >= 0, "rank " .. rank .. " is negative")
    end
  end)

  -- The point of the order is that the things that get you killed sort above
  -- the things that do not, so the head of the list is worth pinning.
  it("opens with the debuffs that matter most", function()
    assert.are.same({ 0, 1, 15 }, { buff_order[1], buff_order[2], buff_order[3] })
  end)
end)
