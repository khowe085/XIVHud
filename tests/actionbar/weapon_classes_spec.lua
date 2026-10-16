local classes = require("lib/actionbar/weapon_classes")

describe("weapon classes", function()
  --[[ Skills 1-12 of Windower's skills resource, read 2026-10-12: the only
       classes a MAIN hand can hold, and so every name the weapon layer can
       ever be keyed by. Archery, Marksmanship and Throwing are ranged-slot
       skills and never reach it. ]]
  it("lists the twelve main-hand classes in the resource's own order", function()
    assert.same({
      "Hand-to-Hand",
      "Dagger",
      "Sword",
      "Great Sword",
      "Axe",
      "Great Axe",
      "Scythe",
      "Polearm",
      "Katana",
      "Great Katana",
      "Club",
      "Staff",
    }, classes.main)
  end)

  --[[ Skills 25-27: the classes of the RANGED slot, each a weapon layer of
       its own beside the main hand's (Kevin, 2026-10-12), so a ranged
       weaponskill has somewhere to be bound. ]]
  it("lists the three ranged classes in the resource's own order", function()
    assert.same({ "Archery", "Marksmanship", "Throwing" }, classes.ranged)
  end)
end)
