local new_enchanteditem = require("components/crossbar/enchanteditem")

-- extdata's times are offset 18000 from os.time.
local NOW = 100000

local ITEMS = {
  ["vocation ring"] = { id = 27546, en = "Vocation Ring", slots = { [13] = true, [14] = true } },
  ["warp cudgel"] = { id = 17040, en = "Warp Cudgel", slots = { [0] = true } },
  ["prism powder"] = { id = 4165, en = "Prism Powder" },
  -- Wearable and entirely ordinary: /item at it can only be refused.
  ["rope belt"] = { id = 11111, en = "Rope Belt", slots = { [10] = true } },
}

local function world(overrides)
  local env = {
    player = { status = 0 },
    -- extdata per bag slot, so two copies of one ring can differ - the
    -- single shared decode made them indistinguishable to every test.
    ext_by_slot = {},
    bags = {
      [0] = { id = 0, name = "Inventory", equippable = true },
      [8] = { id = 8, name = "Wardrobe 2", equippable = true },
    },
    items = { [0] = { enabled = true, { id = 27546, slot = 3, status = 0, count = 1 } } },
    ext = {
      type = "Enchanted Equipment",
      charges_remaining = 1,
      next_use_time = NOW - 18000,
      activation_time = NOW - 18000,
    },
  }
  for key, value in pairs(overrides or {}) do
    env[key] = value
  end
  local module = new_enchanteditem({
    get_player = function()
      return env.player
    end,
    get_items = function(bag)
      return env.items[bag]
    end,
    bags = env.bags,
    extdata_decode = function(item)
      local per_slot = type(item) == "table" and env.ext_by_slot[item.slot] or nil
      return per_slot ~= nil and per_slot or env.ext
    end,
    now = function()
      return NOW
    end,
    -- Overridable, so a test needing a resource of its own does not have to
    -- reach into the shared ITEMS table and put it back afterwards.
    find_item = env.find_item or function(name)
      return ITEMS[name:lower()]
    end,
  })
  return module, env
end

describe("crossbar enchanteditem", function()
  it("equips an enchanted item that is not worn, into its own slot", function()
    local module = world()
    local plan = module.plan("Vocation Ring")
    assert.equal("equip", plan.type)
    assert.equal("Vocation Ring", plan.name)
    assert.equal(27546, plan.id)
    assert.equal(13, plan.equip_slot, "the lowest slot the item fits - ring1 over ring2")
    assert.equal(0, plan.bag)
    assert.equal(3, plan.bag_slot)
    assert.equal('input /item "Vocation Ring" <me>', plan.command)
    assert.is_true(plan.warmup, "using it entails a wait, which is what the travel delay reads")
  end)

  it("finds the ring in a wardrobe, not the inventory alone", function()
    -- The whole point of searching every equippable bag: gear lives in
    -- wardrobes, and the plan has to carry that bag through to the equip.
    local module, env = world()
    env.items[0] = { enabled = true }
    env.items[8] = { enabled = true, { id = 27546, slot = 7, status = 0, count = 1 } }
    local plan = module.plan("Vocation Ring")
    assert.equal("equip", plan.type)
    assert.equal(8, plan.bag)
    assert.equal(7, plan.bag_slot)
  end)

  it("uses an enchanted item already worn and charged, with no equip step", function()
    local module, env = world()
    env.items[0] = { enabled = true, { id = 27546, slot = 3, status = 5, count = 1 } }
    local plan = module.plan("Vocation Ring")
    assert.equal("use", plan.type)
    assert.equal('input /item "Vocation Ring" <me>', plan.command)
    assert.is_nil(plan.warmup, "nothing to wait out - it fires the moment it is asked")
  end)

  it("waits out the warmup on a ring already worn but not yet live", function()
    -- The state the two halves disagreed on: recast says ready, the
    -- enchantment is still warming. Firing here sends an /item the game
    -- refuses about ten seconds early and says nothing about why. Equipping
    -- it by hand and then pressing the slot is the ordinary flow.
    local module, env = world()
    env.items[0] = { enabled = true, { id = 27546, slot = 3, status = 5, count = 1 } }
    env.ext.activation_time = NOW - 18000 + 10
    local plan = module.plan("Vocation Ring")
    assert.equal("equip", plan.type, "arms the scheduler rather than firing")
    assert.is_true(plan.equipped, "and tells it not to re-equip what is already on")
    -- Which of the two rings it is actually on is not knowable from here,
    -- so the GearSwap hold covers both: holding one is a coin flip, and
    -- losing it means GearSwap swaps the warming ring off and the wait dies
    -- at the deadline.
    assert.are.same({ 13, 14 }, plan.hold_slots)
  end)

  it("gives a long-warmup item the same wait the ladder gives it", function()
    --[[ The bound is a fact about the ITEM, so a slot bound to the ring and
         the warp rung reaching it must wait the same length of time.
         Otherwise the ring works from one and "randomly refuses" from the
         other - the very flakiness the ladder's bound was added to fix. ]]
    local module, env = world({
      find_item = function(name)
        if name:lower() == "tavnazian ring" then
          return { id = 26123, en = "Tavnazian Ring", slots = { [13] = true, [14] = true } }
        end
        return nil
      end,
    })
    env.items[0] = { enabled = true, { id = 26123, slot = 3, status = 0, count = 1 } }
    env.ext.activation_time = NOW - 18000 + 35
    local plan = module.plan("Tavnazian Ring")
    assert.equal("equip", plan.type)
    assert.is_true(plan.give_up > 30, "longer than the thirty seconds its warmup takes")
  end)

  it("holds an ordinary item to the default bound", function()
    local enchanted = require("components/crossbar/enchanted")
    local module = world()
    assert.equal(enchanted.give_up_default(), module.plan("Vocation Ring").give_up)
  end)

  it("refuses a worn piece needing more warmup than the wait allows, without touching GearSwap", function()
    -- Arming it would send `gs disable` and then abandon on the very next
    -- poll, re-enabling again: the same answer, with the player's gear
    -- swapping stopped for a frame on the way.
    local module, env = world()
    env.items[0] = { enabled = true, { id = 27546, slot = 3, status = 5, count = 1 } }
    env.ext.activation_time = NOW - 18000 + 31
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    assert.are.same({ "Vocation Ring needs more than 30 sec." }, plan.notes)
  end)

  it("fires a worn piece whose warmup it cannot read, as the ladder does", function()
    --[[ Nothing is armed on this path, so there is no GearSwap hold to
         flicker and no wait to abandon - and the warp ladder fires the same
         shape. Refusing would lose a use that works over a reading we do
         not have. The not-worn path still refuses it, because arming THERE
         holds a slot for a wait the first poll would abandon. ]]
    local module, env = world()
    env.items[0] = { enabled = true, { id = 27546, slot = 3, status = 5, count = 1 } }
    env.ext.activation_time = "not a number"
    local plan = module.plan("Vocation Ring")
    assert.equal("use", plan.type)
    assert.equal('input /item "Vocation Ring" <me>', plan.command)
  end)

  it("still refuses an unreadable warmup on a piece it would have to equip", function()
    local module, env = world()
    env.items[0] = { enabled = true, { id = 27546, slot = 3, status = 0, count = 1 } }
    env.ext.activation_time = "not a number"
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    assert.are.same({ "Cannot read Vocation Ring." }, plan.notes)
  end)

  it("falls back to a charged spare when the worn copy is spent", function()
    --[[ Two Warp Rings is an ordinary thing to carry: one charge each and a
         recast measured in hours. Preferring the worn copy and stopping
         there reports "no charges" for the rest of the day while the
         charged one sits in the bag - and the built-in `warp` ladder, which
         has no such preference, would have found it. ]]
    local module, env = world()
    env.items[0] = {
      enabled = true,
      { id = 27546, slot = 1, status = 0, count = 1 }, -- the spare, charged
      { id = 27546, slot = 4, status = 5, count = 1 }, -- worn, spent
    }
    env.ext_by_slot[4] = { type = "Enchanted Equipment", charges_remaining = 0 }
    local plan = module.plan("Vocation Ring")
    assert.equal("equip", plan.type, "the spare is usable, so it is what the press reaches for")
    assert.equal(1, plan.bag_slot)
  end)

  it("still says what the worn copy is waiting on when no copy is usable", function()
    --[[ The two copies refuse for DIFFERENT reasons, so which reason comes
         back says which copy was asked first. The worn one leads the
         ranking, and its answer is the one the player means - reporting the
         spare's would describe a ring they are not thinking about. ]]
    local module, env = world()
    env.items[0] = {
      enabled = true,
      { id = 27546, slot = 1, status = 0, count = 1 },
      { id = 27546, slot = 4, status = 5, count = 1 },
    }
    env.ext_by_slot[4] = {
      type = "Enchanted Equipment",
      charges_remaining = 1,
      next_use_time = NOW - 18000 + 42,
      activation_time = NOW - 18000,
    }
    env.ext_by_slot[1] = { type = "Enchanted Equipment", charges_remaining = 0 }
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    assert.are.same({ "Vocation Ring: 42 sec recast." }, plan.notes, "the worn copy's reason, not the spare's")
  end)

  it("prefers the copy already worn over a spare in a lower bag", function()
    -- Otherwise the spare wins on bag order and the plan equips a cold ring
    -- over the warm one already on your finger.
    local module, env = world()
    env.items[0] = { enabled = true, { id = 27546, slot = 1, status = 0, count = 1 } }
    env.items[8] = { enabled = true, { id = 27546, slot = 4, status = 5, count = 1 } }
    local plan = module.plan("Vocation Ring")
    assert.equal("use", plan.type, "the worn one is ready; the spare would have needed equipping")
  end)

  it("holds only the slot it chose when it does the equipping itself", function()
    local module = world()
    assert.are.same({ 13 }, module.plan("Vocation Ring").hold_slots, "we put it there, so we know where it is")
  end)

  it("uses a worn ring whose warmup has already passed", function()
    local module, env = world()
    env.items[0] = { enabled = true, { id = 27546, slot = 3, status = 5, count = 1 } }
    env.ext.activation_time = NOW - 18000 - 60
    env.ext.usable = false
    assert.equal("use", module.plan("Vocation Ring").type, "a warmup long past is not a reason to wait")
  end)

  it("reads the equip slots whichever shape the resources carry them in", function()
    --[[ Nothing in this repo had read `res.items[].slots` before, and the
         failure of an unread shape is silent and total. The bitfield is the
         raw DAT form the resources are generated from, so it is the
         likeliest surprise: bits 13 and 14 are the two ring slots. ]]
    --[[ An ipairs list, not pairs over a keyed table: the shape in flight
         has to be knowable from the failure message, and pairs order is
         unspecified. The resource is a LOCAL copy rather than the shared
         fixture, so a failure mid-loop cannot leave a stray shape behind
         for every later test in this file to trip over. ]]
    for _, case in ipairs({
      { shape = "set", slots = { [13] = true, [14] = true } },
      { shape = "list", slots = { 13, 14 } },
      { shape = "bitfield", slots = 2 ^ 13 + 2 ^ 14 },
    }) do
      local shape = case.shape
      local module, env = world({
        find_item = function(name)
          if name:lower() == "vocation ring" then
            return { id = 27546, en = "Vocation Ring", slots = case.slots }
          end
          return ITEMS[name:lower()]
        end,
      })
      assert.equal(13, module.plan("Vocation Ring").equip_slot, shape .. ": lowest slot wins")
      -- The whole set matters too, but only on the worn path, where the
      -- hold has to cover every slot the piece could be on.
      env.items[0] = { enabled = true, { id = 27546, slot = 3, status = 5, count = 1 } }
      env.ext.activation_time = NOW - 18000 + 10
      assert.are.same({ 13, 14 }, module.plan("Vocation Ring").hold_slots, shape .. ": both ring slots")
      env.items[0] = { enabled = true, { id = 27546, slot = 3, status = 0, count = 1 } }
      env.ext.activation_time = NOW - 18000
    end
  end)

  it("refuses ordinary armour rather than sending /item at it", function()
    -- A consumable bound here should still fire; a Rope Belt should not,
    -- and the game's refusal explains nothing.
    local module, env = world()
    env.items[0] = { enabled = true, { id = 11111, slot = 3, status = 0, count = 1 } }
    env.ext = { type = "General" }
    local plan = module.plan("Rope Belt")
    assert.equal("none", plan.type)
    assert.are.same({ "Rope Belt is not enchanted equipment." }, plan.notes)
  end)

  it("sends the target the binding names instead of <me>", function()
    local module = world()
    assert.equal('input /item "Vocation Ring" <t>', module.plan("Vocation Ring", "t").command)
  end)

  -- Casing itself is the widget's `resource_by_name` doing the folding, not
  -- this module's - a test for it here would only assert the fake's own
  -- `name:lower()`. What IS this module's is the line below: whichever
  -- casing came in, the resource's spelling is what goes out.

  it("names the item the way the game does, not the way the binding does", function()
    local module = world()
    assert.equal("Vocation Ring", module.plan("vocation RING").name)
  end)

  it("holds off while the enchantment is on recast", function()
    local module, env = world()
    env.ext.next_use_time = NOW - 18000 + 42
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    assert.are.same({ "Vocation Ring: 42 sec recast." }, plan.notes)
  end)

  it("holds off when the charges are spent", function()
    local module, env = world()
    env.ext.charges_remaining = 0
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    --[[ NOT MyHome's bare "<name>.", which the warp ladder keeps: there it
         is one line among a rung list and reads as an entry. Standalone it
         is the whole answer to a press, and a chat line saying only
         "crossbar: Vocation Ring." says nothing at all. ]]
    assert.are.same({ "Vocation Ring: no charges left." }, plan.notes)
  end)

  it("uses a plain item outright rather than trying to equip it", function()
    local module, env = world()
    env.items[0] = { enabled = true, { id = 4165, slot = 2, status = 0, count = 5 } }
    env.ext = { type = "General" }
    local plan = module.plan("Prism Powder")
    assert.equal("use", plan.type)
    assert.equal('input /item "Prism Powder" <me>', plan.command)
  end)

  it("says so when the item is not carried", function()
    local module, env = world()
    env.items[0] = { enabled = true }
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    assert.are.same({ "You don't have Vocation Ring." }, plan.notes)
  end)

  it("says which bag is out of reach when the copy sits in a disabled one", function()
    local module, env = world()
    env.items[0] = { enabled = false, { id = 27546, slot = 3, status = 0, count = 1 } }
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    assert.are.same({ "You cannot access Vocation Ring from Inventory at this time." }, plan.notes)
  end)

  it("refuses a name no item resource answers to", function()
    local module = world()
    local plan = module.plan("Ring of Nothing")
    assert.equal("none", plan.type)
    assert.are.same({ "No item called Ring of Nothing." }, plan.notes)
  end)

  it("refuses an item it cannot tell the equip slot of", function()
    -- Without a slot there is nothing to hand set_equip, and an equip that
    -- silently no-ops would leave the widget waiting out a warmup that never
    -- starts.
    local module, env = world()
    env.items[0] = { enabled = true, { id = 4165, slot = 2, status = 0, count = 1 } }
    local plan = module.plan("Prism Powder")
    assert.equal("none", plan.type)
    -- "goes in", not "is worn in": this one is not worn.
    assert.are.same({ "Cannot tell which slot Prism Powder goes in." }, plan.notes)
  end)

  it("does not act at all while the player cannot use items", function()
    local module, env = world()
    env.player.status = 33
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    assert.are.same({ "You cannot use items at this time." }, plan.notes)
  end)

  it("answers a bare none when there is no player to read", function()
    local module, env = world()
    env.player = nil
    local plan = module.plan("Vocation Ring")
    assert.equal("none", plan.type)
    assert.are.same({}, plan.notes)
  end)

  it("degrades rather than throwing on an extdata it cannot read", function()
    -- This runs off a keypress under the shared guard; a foreign decode must
    -- not arithmetic-throw.
    local module, env = world()
    env.ext = nil
    assert.are.same({ "Cannot read Vocation Ring." }, module.plan("Vocation Ring").notes)
    env.ext = "garbage"
    assert.equal("none", module.plan("Vocation Ring").type)
  end)
end)
