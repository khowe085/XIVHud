local openers = require("components/crossbar/openers")

describe("crossbar openers", function()
  it("opens the equipment screen with a Ctrl+E key chord", function()
    assert.same({ "ctrl", "e" }, openers.equipment.chord)
    assert.is_nil(openers.equipment.command)
  end)

  it("opens the inventory with a Ctrl+I key chord", function()
    assert.same({ "ctrl", "i" }, openers.inventory.chord)
  end)

  it("opens every wardrobe by slash command", function()
    assert.equal("/wardrobe", openers.wardrobe.command)
    for n = 2, 8 do
      assert.equal("/wardrobe" .. n, openers["wardrobe" .. n].command)
    end
  end)

  it("opens the other bags by slash command", function()
    assert.equal("/case", openers.case.command)
    assert.equal("/sack", openers.sack.command)
    assert.equal("/satchel", openers.satchel.command)
  end)

  it("opens quests, linkshell search and the map by slash command", function()
    assert.equal("/quest", openers.quests.command)
    assert.equal("/sea all linkshell", openers.linkshell.command)
    assert.equal("/map", openers.map.command)
  end)

  it("carries per-entry icons where the default pack has a match", function()
    assert.equal("map", openers.map.icon)
    assert.equal("item", openers.inventory.icon)
    assert.equal("item", openers.wardrobe.icon)
    assert.equal("item", openers.satchel.icon)
    -- No match in the pack: these take the render-time fallback.
    assert.is_nil(openers.equipment.icon)
    assert.is_nil(openers.quests.icon)
    assert.is_nil(openers.linkshell.icon)
  end)

  it("gives every entry exactly one opener", function()
    for name, entry in pairs(openers) do
      local has_command = entry.command ~= nil
      local has_chord = entry.chord ~= nil
      assert.is_true(has_command ~= has_chord, name .. " must have a command or a chord, never both")
    end
  end)
end)
