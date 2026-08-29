local enchanted = require("components/crossbar/enchanted")

-- extdata's times are offset 18000 from os.time; a NOW well past zero keeps
-- the arithmetic honest.
local NOW = 100000

local function ext(overrides)
  local decoded = {
    type = "Enchanted Equipment",
    charges_remaining = 1,
    next_use_time = NOW - 18000, -- ready exactly now
    activation_time = NOW - 18000,
    usable = false,
  }
  for key, value in pairs(overrides or {}) do
    decoded[key] = value
  end
  return decoded
end

describe("crossbar enchanted", function()
  describe("recast_remaining", function()
    it("is zero for a ready item", function()
      assert.equal(0, enchanted.recast_remaining(ext(), NOW))
    end)

    it("counts down the seconds until next use", function()
      assert.equal(42, enchanted.recast_remaining(ext({ next_use_time = NOW - 18000 + 42 }), NOW))
    end)

    it("never goes negative", function()
      assert.equal(0, enchanted.recast_remaining(ext({ next_use_time = NOW - 18000 - 5 }), NOW))
    end)

    it("is nil with no charges left", function()
      assert.is_nil(enchanted.recast_remaining(ext({ charges_remaining = 0 }), NOW))
    end)

    it("is nil for a non-enchanted item", function()
      assert.is_nil(enchanted.recast_remaining(ext({ type = "General" }), NOW))
    end)

    it("answers nil for an ext that is not enchanted-shaped, never throws", function()
      -- The same posture step() has: this feeds warp's ladder walk, where a
      -- foreign decode must degrade, not arithmetic-throw.
      assert.is_nil(enchanted.recast_remaining(nil, NOW))
      assert.is_nil(enchanted.recast_remaining("garbage", NOW))
      assert.is_nil(enchanted.recast_remaining({ type = "Enchanted Equipment" }, NOW))
      assert.is_nil(enchanted.recast_remaining({ type = "Enchanted Equipment", charges_remaining = "x" }, NOW))
      assert.is_nil(enchanted.recast_remaining({ type = "Enchanted Equipment", charges_remaining = 1 }, NOW))
    end)
  end)

  describe("warmup_remaining", function()
    it("counts down the enchant delay after an equip", function()
      assert.equal(12, enchanted.warmup_remaining(ext({ activation_time = NOW - 18000 + 12 }), NOW))
    end)

    it("clamps at zero once the delay has passed", function()
      assert.equal(0, enchanted.warmup_remaining(ext({ activation_time = NOW - 18000 - 3 }), NOW))
    end)
  end)

  describe("step", function()
    it("uses the item the moment extdata says usable", function()
      assert.equal("use", enchanted.step(ext({ usable = true }), NOW))
    end)

    it("reads an elapsed warmup as ready only on a piece already worn", function()
      --[[ activation_time is written at the equip, so on an item that is
           NOT worn it is a leftover from some previous one. Reading it as
           ready there fires the /item one frame after set_equip - before
           the equip has reached the server - which is why the caller has to
           say which case it is in. On a piece already on, an elapsed warmup
           IS ready, and waiting on the flag alone risks the 45s deadline. ]]
      local elapsed = ext({ activation_time = NOW - 18000, usable = false })
      assert.equal("wait", enchanted.step(elapsed, NOW), "not worn: the timestamp is stale")
      assert.equal("use", enchanted.step(elapsed, NOW, true), "worn: the warmup really has passed")
      assert.equal(
        "use",
        enchanted.step(ext({ activation_time = NOW - 18000 - 60, usable = false }), NOW, true),
        "long past, and worn"
      )
      assert.equal(
        "wait",
        enchanted.step(ext({ activation_time = NOW - 18000 + 5, usable = false }), NOW, true),
        "worn but still warming is still a wait"
      )
    end)

    it("waits out a delay inside the give-up bound", function()
      assert.equal("wait", enchanted.step(ext({ activation_time = NOW - 18000 + 29 }), NOW))
    end)

    it("still waits exactly at the bound", function()
      assert.equal("wait", enchanted.step(ext({ activation_time = NOW - 18000 + 30 }), NOW))
    end)

    it("takes a longer give-up bound from the caller", function()
      --[[ 30s is MyHome's rule for MyHome's rungs. A ring whose warmup IS
           thirty seconds sits exactly on that cliff, and any slop - poll
           timing, equip latency, a rounded timestamp - tips it into
           "abandon", so the ring would look like it randomly refuses to
           work. The bound therefore belongs to the rung, not the module. ]]
      local warming = ext({ activation_time = NOW - 18000 + 35 })
      assert.equal("abandon", enchanted.step(warming, NOW), "the default bound still bites at 35")
      assert.equal("wait", enchanted.step(warming, NOW, false, 40), "a rung that expects 30s waits it out")
      assert.equal("abandon", enchanted.step(warming, NOW, false, 20), "and a shorter bound gives up sooner")
    end)

    it("abandons at once when the remaining delay exceeds 30s", function()
      -- The give-up is not a timer: an item needing more than 30s more is
      -- abandoned immediately, not polled for 30s.
      assert.equal("abandon", enchanted.step(ext({ activation_time = NOW - 18000 + 31 }), NOW))
    end)

    it("answers nil for an ext that is not enchanted-shaped, never throws", function()
      -- The widget polls this under the shared prerender guard: an
      -- arithmetic throw here would repeat until guard disables every
      -- component's update.
      assert.is_nil(enchanted.step({ type = "General" }, NOW))
      assert.is_nil(enchanted.step("garbage", NOW))
      assert.is_nil(enchanted.step(nil, NOW))
      assert.equal("use", enchanted.step({ usable = true }, NOW), "usable short-circuits before any arithmetic")
    end)
  end)

  describe("equip_slots", function()
    it("reads a set, a list and a bitfield alike, lowest first", function()
      assert.are.same({ 13, 14 }, enchanted.equip_slots({ slots = { [14] = true, [13] = true } }))
      assert.are.same({ 13, 14 }, enchanted.equip_slots({ slots = { 14, 13 } }))
      assert.are.same({ 13, 14 }, enchanted.equip_slots({ slots = 2 ^ 13 + 2 ^ 14 }))
      assert.are.same({ 0 }, enchanted.equip_slots({ slots = { [0] = true } }), "main hand is slot zero")
    end)

    it("answers nothing rather than guessing at a shape it cannot read", function()
      --[[ The contract the callers depend on: an empty answer means "cannot
           tell which slot", which the ladder walks past and enchanteditem
           refuses. A confident wrong answer would hand set_equip a slot the
           piece does not go in. ]]
      assert.are.same({}, enchanted.equip_slots({ slots = "ring1" }))
      assert.are.same({}, enchanted.equip_slots({ slots = { "ring1", "ring2" } }), "names, not ids")
      assert.are.same({}, enchanted.equip_slots({}))
      assert.are.same({}, enchanted.equip_slots(nil))
      assert.are.same({}, enchanted.equip_slots("garbage"))
    end)

    it("drops an id outside the sixteen real equip slots", function()
      --[[ Whichever shape produced it. Out of range it is not a slot at
           all: set_equip would be handed a slot that does not exist and
           GS_SLOT_NAMES would answer nothing, so the piece is equipped
           nowhere, held nowhere, and the wait dies at its deadline. ]]
      assert.are.same({ 13 }, enchanted.equip_slots({ slots = { [13] = true, [20] = true } }))
      assert.are.same({ 13 }, enchanted.equip_slots({ slots = { 20, 13, -1 } }))
      assert.are.same({}, enchanted.equip_slots({ slots = { [20] = true } }), "nothing left is cannot-tell")
    end)

    it("refuses a number small enough to be a bare slot id", function()
      --[[ 0..15 is both a legal slot id and a legal bitfield naming nothing
           above ammo, so nothing here can tell them apart. Reading `13` as a
           bitfield would answer slots 0, 2 and 3 - and the caller would
           equip a ring into the MAIN HAND. Refusing costs a dead feature
           until question I is answered; guessing costs a weapon. ]]
      assert.are.same({}, enchanted.equip_slots({ slots = 13 }), "a ring's slot id, not a bitfield")
      assert.are.same({}, enchanted.equip_slots({ slots = 1 }))
      assert.are.same({}, enchanted.equip_slots({ slots = 15 }))
      -- Above 15 a bare id is impossible, so a bitfield is the only reading.
      assert.are.same({ 4 }, enchanted.equip_slots({ slots = 16 }), "head alone")
      assert.are.same({ 13, 14 }, enchanted.equip_slots({ slots = 2 ^ 13 + 2 ^ 14 }))
    end)
  end)

  describe("collect", function()
    local BAGS = {
      [0] = { id = 0, name = "Inventory", equippable = true },
      [8] = { id = 8, name = "Wardrobe", equippable = true },
      [3] = { id = 3, name = "Satchel", equippable = false },
    }

    local function reader(contents)
      return function(bag_id)
        return contents[bag_id]
      end
    end

    it("gathers every item in every equippable bag, by id", function()
      local found = enchanted.collect(
        BAGS,
        reader({
          [0] = { enabled = true, { id = 28540, slot = 3, count = 1 } },
          [8] = { enabled = true, { id = 17040, slot = 1, count = 1 } },
        })
      )
      assert.equal(0, found[28540].bag)
      assert.equal(3, found[28540].item.slot)
      assert.equal(8, found[17040].bag)
      assert.is_true(found[28540].enabled)
    end)

    it("ignores bags that cannot hold equipment", function()
      local found = enchanted.collect(BAGS, reader({ [3] = { enabled = true, { id = 4181, slot = 1, count = 1 } } }))
      assert.is_nil(found[4181])
    end)

    it("lets an enabled bag's copy beat a disabled bag's, whatever the walk order", function()
      -- A duplicate sitting in a disabled wardrobe must not shadow the
      -- usable copy: the enabled flag outranks arrival order.
      local found = enchanted.collect(
        BAGS,
        reader({
          [0] = { enabled = false, { id = 28540, slot = 1, count = 1 } },
          [8] = { enabled = true, { id = 28540, slot = 9, count = 1 } },
        })
      )
      assert.equal(8, found[28540].bag)
      assert.is_true(found[28540].enabled)
    end)

    it("keeps the lowest bag id when both copies are enabled", function()
      local found = enchanted.collect(
        BAGS,
        reader({
          [0] = { enabled = true, { id = 28540, slot = 1, count = 1 } },
          [8] = { enabled = true, { id = 28540, slot = 9, count = 1 } },
        })
      )
      assert.equal(0, found[28540].bag, "sorted bag ids, so a duplicate resolves the same way every call")
    end)

    it("leaves the worn copy no special standing", function()
      --[[ The ladder reads charges off the ONE copy collect returns and
           then walks to the next RUNG, so preferring the worn one here
           turns a spent ring on your finger into "no charges" while a
           charged spare sits in the bag. The worn preference belongs to
           the ranking `candidates` exposes, where the caller can walk past
           a copy it cannot use. ]]
      local bags_read = reader({
        [0] = { enabled = true, { id = 28540, slot = 1, status = 0, count = 1 } },
        [8] = { enabled = true, { id = 28540, slot = 9, status = 5, count = 1 } },
      })
      assert.equal(0, enchanted.collect(BAGS, bags_read)[28540].bag, "bag order, worn or not")

      --[[ And the case bag order cannot decide: BOTH copies in inventory,
           which is how a player actually carries two rings. A tie-break
           that only compared bags let the worn-first ranking through here,
           which is the whole hazard this test names. ]]
      local one_bag = reader({
        [0] = {
          enabled = true,
          { id = 28540, slot = 1, status = 0, count = 1 },
          { id = 28540, slot = 4, status = 5, count = 1 },
        },
      })
      assert.equal(1, enchanted.collect(BAGS, one_bag)[28540].item.slot, "the first copy found, not the worn one")
    end)

    it("ranks every copy for a caller that can walk past one", function()
      local found = enchanted.candidates(
        BAGS,
        reader({
          [0] = { enabled = true, { id = 28540, slot = 1, status = 0, count = 1 } },
          [8] = { enabled = true, { id = 28540, slot = 9, status = 5, count = 1 } },
        })
      )
      assert.equal(2, #found[28540], "both copies survive")
      assert.equal(8, found[28540][1].bag, "the one on your hand leads")
      assert.equal(0, found[28540][2].bag)
    end)

    it("ranks a reachable copy above a worn one locked in a disabled bag", function()
      -- Reachability outranks everything: a ring you cannot get at is no
      -- use however conveniently it is already on.
      local found = enchanted.candidates(
        BAGS,
        reader({
          [0] = { enabled = true, { id = 28540, slot = 1, status = 0, count = 1 } },
          [8] = { enabled = false, { id = 28540, slot = 9, status = 5, count = 1 } },
        })
      )
      assert.equal(0, found[28540][1].bag)
      assert.is_true(found[28540][1].enabled)
    end)

    it("skips empty slots and survives a bag the client did not answer", function()
      local found = enchanted.collect(BAGS, reader({ [0] = { enabled = true, { id = 0, slot = 1 } } }))
      assert.is_nil(found[0])
      assert.are.same({}, enchanted.collect(BAGS, reader({})))
    end)
  end)
end)
