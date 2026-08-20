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
        "You don't have Warp Cudgel.",
        "You don't have Instant Warp.",
      }, plan.notes)
    end)
  end)
end)
