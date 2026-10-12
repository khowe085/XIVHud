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
    }, classes)
  end)
end)
