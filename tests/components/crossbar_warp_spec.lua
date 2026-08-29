local new_warp = require("components/crossbar/warp")

local NOW = 100000
local READY = NOW - 18000 -- extdata timestamp for "ready now"

local BLM = 4
local WHM = 3
local RDM = 5

-- Bag 0 (inventory) and bag 8 (a second equippable bag); bag 5 is not
-- equippable and must never be walked.
local BAGS = {
  [0] = { name = "Inventory", equippable = true },
  [5] = { name = "Mog Safe", equippable = false },
  [8] = { name = "Wardrobe", equippable = true },
}

local RING = 28540
-- The Tavnazian Ring has no id here on purpose: nobody in this repo knows
-- it, and the ladder resolves the rung by NAME rather than writing one
-- down from memory. This is simply the id the fake resources answer with.
local TAVNAZIAN = 26123
local TAVNAZIAN_RESOURCES = {
  ["tavnazian ring"] = { id = TAVNAZIAN, en = "Tavnazian Ring", slots = { [13] = true, [14] = true } },
}
local CUDGEL = 17040
local SCROLL = 4181

-- Builds a warp planner over a controllable world. `state.items[bag_id]` is
-- the get_items answer; `state.ext[item_id]` the decoded extdata.
local function build(state)
  state.player = state.player or { main_job_id = WHM, sub_job_id = RDM, vitals = { mp = 0 }, status = 0 }
  state.spells = state.spells or {}
  state.items = state.items or {}
  state.ext = state.ext or {}
  local warp = new_warp({
    get_player = function()
      return state.player
    end,
    get_spells = function()
      return state.spells
    end,
    get_items = function(bag_id)
      return state.items[bag_id] or { enabled = true }
    end,
    bags = state.bags or BAGS,
    -- A rung named rather than numbered resolves its id through here; the
    -- three original rungs carry their ids and never ask.
    find_item = function(name)
      return state.resources and state.resources[name:lower()] or nil
    end,
    extdata_decode = function(item)
      return state.ext[item.id]
    end,
    now = function()
      return NOW
    end,
  })
  return warp
end

local function ready_ring(overrides)
  local state = {
    items = { [0] = { enabled = true, { id = RING, status = 0, slot = 3 } } },
    ext = {
      [RING] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY, usable = false },
    },
  }
  for key, value in pairs(overrides or {}) do
    state[key] = value
  end
  return state
end

describe("crossbar warp", function()
  describe("the spell rungs", function()
    it("casts Warp on BLM main with the spell known and 100 MP", function()
      local warp = build({
        player = { main_job_id = BLM, sub_job_id = WHM, vitals = { mp = 100 }, status = 0 },
        spells = { [261] = true },
      })
      local plan = warp.plan()
      assert.equal("spell", plan.type)
      assert.equal('input /ma "Warp" <me>', plan.command)
    end)

    it("casts Warp on BLM sub too", function()
      local warp = build({
        player = { main_job_id = WHM, sub_job_id = BLM, vitals = { mp = 100 }, status = 0 },
        spells = { [261] = true },
      })
      assert.equal("spell", warp.plan().type)
    end)

    it("prefers Warp over Warp II when both are castable", function()
      local warp = build({
        player = { main_job_id = BLM, sub_job_id = WHM, vitals = { mp = 200 }, status = 0 },
        spells = { [261] = true, [262] = true },
      })
      assert.equal('input /ma "Warp" <me>', warp.plan().command)
    end)

    it("falls back to Warp II at 150 MP when Warp is unknown", function()
      local warp = build({
        player = { main_job_id = BLM, sub_job_id = WHM, vitals = { mp = 150 }, status = 0 },
        spells = { [262] = true },
      })
      assert.equal('input /ma "Warp II" <me>', warp.plan().command)
    end)

    it("holds Warp under 100 MP and Warp II under 150", function()
      local warp = build({
        player = { main_job_id = BLM, sub_job_id = WHM, vitals = { mp = 99 }, status = 0 },
        spells = { [261] = true, [262] = true },
      })
      assert.not_equal("spell", warp.plan().type)
      local warp2 = build({
        player = { main_job_id = BLM, sub_job_id = WHM, vitals = { mp = 149 }, status = 0 },
        spells = { [262] = true },
      })
      assert.not_equal("spell", warp2.plan().type)
    end)

    it("never casts without BLM main or sub", function()
      local warp = build({
        player = { main_job_id = WHM, sub_job_id = RDM, vitals = { mp = 999 }, status = 0 },
        spells = { [261] = true, [262] = true },
      })
      assert.not_equal("spell", warp.plan().type)
    end)

    it("still casts while the status blocks items", function()
      local warp = build({
        player = { main_job_id = BLM, sub_job_id = WHM, vitals = { mp = 100 }, status = 2 },
        spells = { [261] = true },
      })
      assert.equal("spell", warp.plan().type)
    end)
  end)

  describe("the item rungs", function()
    it("blocks all items while player status > 1", function()
      local state = ready_ring()
      state.player = { main_job_id = WHM, sub_job_id = RDM, vitals = { mp = 0 }, status = 2 }
      local plan = build(state).plan()
      assert.equal("none", plan.type)
      assert.same({ "You cannot use items at this time." }, plan.notes)
    end)

    it("equips an unequipped ready ring before using it", function()
      local plan = build(ready_ring()).plan()
      assert.equal("equip", plan.type)
      assert.equal("Warp Ring", plan.name)
      assert.equal(28540, plan.id, "the poll re-finds the item by id, not by slot alone")
      assert.equal(13, plan.equip_slot)
      assert.equal(0, plan.bag)
      assert.equal(3, plan.bag_slot)
      assert.equal('input /item "Warp Ring" <me>', plan.command)
    end)

    it("uses an already-equipped ring without re-equipping", function()
      local state = ready_ring()
      state.items[0][1].status = 5
      local plan = build(state).plan()
      assert.equal("use", plan.type)
      assert.equal('input /item "Warp Ring" <me>', plan.command)
    end)

    it("waits out a worn ring's warmup rather than giving up on it", function()
      --[[ Equipping a Warp Ring by hand and pressing warp a moment later is
           the ordinary flow, and the ring becomes usable in seconds. The
           ladder used to fire it early (CB12's defect); walking past it
           instead traded one wrong answer for another, since with no rung
           below it the press did nothing at all and had to be repeated.

           So the same wait an `enchanteditem` binding on that ring would
           arm - no re-equip, the GearSwap hold on, the scheduler polling -
           which is what makes "both callers put the same question to step"
           true of the ANSWER as well as the question. ]]
      local state = ready_ring()
      state.items[0][1].status = 5
      state.ext[RING].activation_time = READY + 10
      local plan = build(state).plan()
      assert.equal("equip", plan.type)
      assert.is_true(plan.equipped, "already on: the scheduler waits without re-equipping")
      assert.equal(13, plan.equip_slot)
      assert.equal('input /item "Warp Ring" <me>', plan.command)
    end)

    it("holds every ring slot a worn ring could be on, not the one it would equip into", function()
      --[[ A NUMBERED rung's `equip_slot` says where the ladder would PUT
           the ring; it says nothing about which finger the ring is already
           on. Holding ring1 while the ring sits on ring2 leaves GearSwap
           free to swap it off mid-wait, and the wait then dies at its
           deadline having disabled the wrong slot the whole time.

           So a numbered rung asks the resources for its slots too - which
           is the only reason it consults them at all. ]]
      local state = ready_ring()
      state.resources = {
        ["warp ring"] = { id = RING, en = "Warp Ring", slots = { [13] = true, [14] = true } },
      }
      state.items[0][1].status = 5
      state.ext[RING].activation_time = READY + 10
      local plan = build(state).plan()
      assert.are.same({ 13, 14 }, plan.hold_slots)
    end)

    it("falls back to the rung's own slot when the resources name none", function()
      -- Without a resource there is nothing better to hold than the slot
      -- the rung would have equipped into.
      local state = ready_ring()
      state.items[0][1].status = 5
      state.ext[RING].activation_time = READY + 10
      assert.are.same({ 13 }, build(state).plan().hold_slots)
    end)

    it("walks past a worn ring it would have to wait too long for", function()
      --[[ CB12. "Worn" was taken for "ready" on the recast alone, so a ring
           you had just put on by hand fired an `/item` the game refuses
           seconds early - the same defect enchanteditem fixes on its own
           side, and the same question asked of the same `step`. A rung that
           is not ready is a rung to walk past: the cudgel below it may well
           be ready now. ]]
      --[[ Past the give-up bound, so there is nothing worth waiting for and
           the rungs below it get their turn. Only THIS case walks past - a
           warmup inside the bound is waited out by the test above. ]]
      local state = ready_ring()
      state.items[0][1].status = 5
      state.ext[RING].activation_time = READY + 45
      local plan = build(state).plan()
      assert.equal("none", plan.type, "no cudgel and no scroll here, so the ladder runs out")
      assert.are.same({
        -- In its own words: MyHome's bare "Warp Ring." means out of
        -- charges, which is a different thing to do something about.
        "Warp Ring: warm-up too long.",
        "You don't have Instant Warp.",
        "You don't have Warp Cudgel.",
      }, plan.notes, "one note for the ring, then the rungs below it")
    end)

    it("still fires a worn ring whose warmup it cannot read", function()
      -- No activation_time at all is a decode we cannot judge, and refusing
      -- there would lose a warp that works today over a reading we do not
      -- have. It degrades to the behaviour that shipped.
      local state = ready_ring()
      state.items[0][1].status = 5
      local plan = build(state).plan()
      assert.equal("use", plan.type)
    end)

    it("puts Instant Warp above the Warp Cudgel", function()
      --[[ Kevin's order (2026-08-23): a scroll is consumable but INSTANT,
           while the cudgel wants a weapon slot and a warm-up - so reaching
           for the cudgel first costs a swap the scroll does not. The
           by-name rungs below add no note here, having no id to look for
           without the resources. ]]
      local plan = build({ items = {} }).plan()
      assert.are.same({
        "You don't have Warp Ring.",
        "You don't have Instant Warp.",
        "You don't have Warp Cudgel.",
      }, plan.notes, "the ladder in order, top to bottom")
    end)

    it("reaches Treat Staff II below the cudgel, into the main-hand slot", function()
      --[[ A main weapon with a thirty-second warm-up, so the cudgel's
           shape exactly - and it sits under it (Kevin, 2026-08-23). The
           rung names its own slot rather than trusting the resource's
           `slots`, which is still an open in-client question. ]]
      local staff = 12345
      local plan = build({
        resources = { ["treat staff ii"] = { id = staff, en = "Treat Staff II" } },
        items = { [0] = { enabled = true, { id = staff, status = 0, slot = 3 } } },
        ext = { [staff] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY } },
      }).plan()
      assert.equal("equip", plan.type)
      assert.equal("Treat Staff II", plan.name)
      assert.equal(0, plan.equip_slot, "the main hand")
    end)

    it("never reaches Treat Staff II while the cudgel can go", function()
      -- Below it, so a cudgel that can fire is the one that does.
      local plan = build({
        resources = { ["treat staff ii"] = { id = 12345, en = "Treat Staff II" } },
        items = {
          [0] = {
            enabled = true,
            { id = CUDGEL, status = 0, slot = 1 },
            { id = 12345, status = 0, slot = 3 },
          },
        },
        ext = {
          [CUDGEL] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY },
          [12345] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY },
        },
      }).plan()
      assert.equal("Warp Cudgel", plan.name)
    end)

    it("gives Treat Staff II the headroom its warm-up needs", function()
      -- The test is `warm > bound`, so the default would refuse it on any
      -- slop at all - equip latency, a poll landing late, a rounded
      -- timestamp - which is why the Tavnazian Ring carries forty too.
      local enchanted = require("components/crossbar/enchanted")
      assert.are.equal(40, enchanted.give_up_for("Treat Staff II"))
      assert.are.equal(40, enchanted.give_up_for("treat staff ii"), "folded, like every other name here")
    end)

    it("falls to the Tavnazian Ring when every rung above it is unavailable", function()
      -- The item of last resort: below the Warp Ring, the Warp Cudgel and
      -- Instant Warp, and reached only when none of them can go.
      local plan = build({
        resources = TAVNAZIAN_RESOURCES,
        items = { [0] = { enabled = true, { id = TAVNAZIAN, status = 0, slot = 2 } } },
        ext = { [TAVNAZIAN] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY } },
      }).plan()
      assert.equal("equip", plan.type)
      assert.equal("Tavnazian Ring", plan.name)
      assert.equal(TAVNAZIAN, plan.id, "the id came from the resources, not from a constant")
      assert.equal(13, plan.equip_slot, "ring1, read off the resource's own slots")
    end)

    it("never reaches the Tavnazian Ring while a rung above it can go", function()
      local state = ready_ring()
      state.resources = TAVNAZIAN_RESOURCES
      state.items[0][2] = { id = TAVNAZIAN, status = 0, slot = 2 }
      state.ext[TAVNAZIAN] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY }
      assert.equal("Warp Ring", build(state).plan().name)
    end)

    it("gives the Tavnazian Ring a wait long enough for its own warmup", function()
      --[[ Its enchantment takes about thirty seconds to come up, which is
           exactly the module's default give-up bound - so on the default it
           would abandon on any slop at all. The rung carries its own. ]]
      local plan = build({
        resources = TAVNAZIAN_RESOURCES,
        items = { [0] = { enabled = true, { id = TAVNAZIAN, status = 0, slot = 2 } } },
        ext = { [TAVNAZIAN] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY } },
      }).plan()
      assert.is_true(plan.give_up > 30, "longer than the thirty seconds it needs")
    end)

    it("walks past a rung whose equip slot the resources will not give up", function()
      --[[ `slots` in a shape this build cannot read. The rung cannot be
           equipped, so it cannot be used either: the ring is in the bag,
           not on a finger, and `/item` at it is refused. Firing anyway
           would also make `warp all` send the alts home on a warp that
           never happened. ]]
      local plan = build({
        resources = { ["tavnazian ring"] = { id = TAVNAZIAN, en = "Tavnazian Ring", slots = "unreadable" } },
        items = { [0] = { enabled = true, { id = TAVNAZIAN, status = 0, slot = 2 } } },
        ext = { [TAVNAZIAN] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY } },
      }).plan()
      assert.equal("none", plan.type, "no command at all, least of all a doomed one")
      assert.are.same({
        "You don't have Warp Ring.",
        "You don't have Instant Warp.",
        "You don't have Warp Cudgel.",
        "Cannot tell which slot Tavnazian Ring goes in.",
      }, plan.notes)
    end)

    it("does not offer the Tavnazian Ring when the resources cannot name it", function()
      -- No resources library, or a name the table does not carry: the rung
      -- has no id to search for, so it simply is not a rung today.
      local plan = build({
        items = { [0] = { enabled = true, { id = TAVNAZIAN, status = 0, slot = 2 } } },
        ext = { [TAVNAZIAN] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY } },
      }).plan()
      assert.equal("none", plan.type)
      assert.are.same({
        "You don't have Warp Ring.",
        "You don't have Instant Warp.",
        "You don't have Warp Cudgel.",
      }, plan.notes, "silently: an item we cannot even name is not one to report missing")
    end)

    it("skips a ring in a disabled bag, with a notice", function()
      local state = ready_ring()
      state.items[0].enabled = false
      local plan = build(state).plan()
      assert.equal("none", plan.type)
      assert.equal("You cannot access Warp Ring from Inventory at this time.", plan.notes[1])
    end)

    it("skips a ring with no charges left", function()
      local state = ready_ring()
      state.ext[RING].charges_remaining = 0
      assert.equal("none", build(state).plan().type)
    end)

    it("keeps MyHome's bare-name note for a ring out of charges", function()
      -- The bare item name is MyHome's own log line for this case, kept
      -- deliberately rather than inventing wording.
      local state = ready_ring()
      state.ext[RING].charges_remaining = 0
      assert.equal("Warp Ring.", build(state).plan().notes[1])
    end)

    it("answers a none plan when the player is not available", function()
      -- get_player() can return nil (not logged in, zoning).
      local state = ready_ring()
      local warp = build(state)
      state.player = nil
      assert.equal("none", warp.plan().type)
    end)

    it("survives a player the client is still filling in field by field", function()
      -- The documented gotcha: vitals and status land one at a time.
      local bare = build({ player = {} })
      assert.equal("none", bare.plan().type)
      local no_mp = build({
        player = { main_job_id = BLM, sub_job_id = WHM, vitals = {} },
        spells = { [261] = true },
      })
      assert.equal("none", no_mp.plan().type)
    end)

    it("treats a missing status as not blocked for items", function()
      local state = ready_ring()
      state.player = { main_job_id = WHM, sub_job_id = RDM, vitals = { mp = 0 } }
      assert.equal("equip", build(state).plan().type)
    end)

    it("skips a ring on recast and says for how long", function()
      local state = ready_ring()
      state.ext[RING].next_use_time = READY + 42
      local plan = build(state).plan()
      assert.equal("none", plan.type)
      assert.equal("Warp Ring: 42 sec recast.", plan.notes[1])
    end)

    it("falls back to the cudgel when the ring is on recast", function()
      local state = ready_ring()
      state.ext[RING].next_use_time = READY + 42
      state.items[8] = { enabled = true, { id = CUDGEL, status = 0, slot = 1 } }
      state.ext[CUDGEL] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY, usable = false }
      local plan = build(state).plan()
      assert.equal("equip", plan.type)
      assert.equal("Warp Cudgel", plan.name)
      assert.equal(0, plan.equip_slot)
      assert.equal(8, plan.bag)
    end)

    it("prefers the ring when ring and cudgel are both ready", function()
      -- MyHome walks its ladder with pairs, so its documented order is not
      -- actually guaranteed; ours is ipairs and must be.
      local state = ready_ring()
      state.items[8] = { enabled = true, { id = CUDGEL, status = 0, slot = 1 } }
      state.ext[CUDGEL] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY, usable = false }
      assert.equal("Warp Ring", build(state).plan().name)
    end)

    it("marks only the rung whose use entails a wait, not every enchanted one", function()
      -- The travel delay skips a countdown for a rung that must be equipped
      -- and warmed up, because that wait is already the window it would
      -- have given. An equipped, charged ring has no wait to skip, so the
      -- ladder must not claim it does.
      local plan = build(ready_ring()).plan()
      assert.equal("equip", plan.type)
      assert.is_true(plan.warmup)
      local state = ready_ring()
      state.items[0][1].status = 5
      local equipped = build(state).plan()
      assert.equal("use", equipped.type)
      assert.is_nil(equipped.warmup, "equipped and charged: it fires the moment it is asked")
    end)

    it("uses Instant Warp as a plain consumable, no equip step", function()
      local state = {
        items = { [0] = { enabled = true, { id = SCROLL, status = 0, slot = 7 } } },
        ext = { [SCROLL] = { type = "General" } },
      }
      local plan = build(state).plan()
      assert.equal("use", plan.type)
      assert.equal('input /item "Instant Warp" <me>', plan.command)
      assert.is_nil(plan.warmup, "a consumable has no warmup of its own to wait out")
    end)

    it("prefers a ring in an enabled bag over the same ring in a disabled one", function()
      -- Keying by item id alone let a later disabled bag shadow the usable
      -- copy; an enabled entry must win whatever the walk order.
      local state = ready_ring()
      state.items[8] = { enabled = false, { id = RING, status = 0, slot = 4 } }
      local plan = build(state).plan()
      assert.equal("equip", plan.type)
      assert.equal(0, plan.bag)
    end)

    it("prefers the enabled copy even when the disabled one walks first", function()
      -- The mirror direction: first-found must not beat enabled.
      local state = ready_ring()
      state.items[0].enabled = false
      state.items[8] = { enabled = true, { id = RING, status = 0, slot = 4 } }
      local plan = build(state).plan()
      assert.equal("equip", plan.type)
      assert.equal(8, plan.bag)
    end)

    it("picks the lowest bag id when two enabled copies exist", function()
      -- The sorted walk is what makes the pick deterministic: this VM's
      -- pairs order for the key set {0, 5, 8} visits 8 before 5, so only
      -- the sort puts the ring in bag 5. (Correct code passes on any VM;
      -- the fixture is chosen so dropping the sort shows here.)
      local state = {
        bags = {
          [0] = { name = "Inventory", equippable = true },
          [5] = { name = "Satchel", equippable = true },
          [8] = { name = "Wardrobe", equippable = true },
        },
        items = {
          [5] = { enabled = true, { id = RING, status = 0, slot = 3 } },
          [8] = { enabled = true, { id = RING, status = 0, slot = 4 } },
        },
        ext = {
          [RING] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY, usable = false },
        },
      }
      local plan = build(state).plan()
      assert.equal("equip", plan.type)
      assert.equal(5, plan.bag)
    end)

    it("never walks a non-equippable bag", function()
      local state = {
        items = { [5] = { enabled = true, { id = RING, status = 0, slot = 1 } } },
        ext = {
          [RING] = { type = "Enchanted Equipment", charges_remaining = 1, next_use_time = READY, usable = false },
        },
      }
      assert.equal("none", build(state).plan().type)
    end)

    it("answers a hint, not a crash, when nothing is available", function()
      local plan = build({}).plan()
      assert.equal("none", plan.type)
      assert.same({
        "You don't have Warp Ring.",
        "You don't have Instant Warp.",
        "You don't have Warp Cudgel.",
      }, plan.notes)
    end)
  end)
end)
