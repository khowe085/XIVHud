local new_roulette = require("components/crossbar/roulette")

local NOTE = "\226\153\170" -- the music-note prefix on mount key item names

-- A small world: two mount KIs, the quest whistle, and a non-mount KI.
local function world(overrides)
  local state = {
    key_items = { 3000, 3001, 3002, 3010 },
    buffs = {},
    rolls = { 0 },
  }
  for key, value in pairs(overrides or {}) do
    state[key] = value
  end

  local resources = {
    key_items = {
      [3000] = { category = "Mounts", name = NOTE .. "Raptor Companion" },
      [3001] = { category = "Mounts", name = NOTE .. "Crab Companion" },
      [3002] = { category = "Mounts", name = "trainer's whistle" },
      [3003] = { category = "Mounts", name = NOTE .. "Raptor Companion II" },
      [3005] = { category = "Mounts", name = NOTE .. "Dragon Companion" },
      [3010] = { category = "Magic Maps", name = "map of the northlands" },
      -- Note-prefixed and a perfect mount-name match, but the WRONG
      -- category: only the category check can reject this one, so it is
      -- what makes that check testable.
      [3011] = { category = "Instance Entry", name = NOTE .. "Tiger" },
    },
    mounts = {
      -- Deliberately hash-part keys in scrambled declaration order: the
      -- sorted id walk, not table iteration order, must decide a tie.
      [14] = { name = "Raptor Companion" },
      [11] = { name = "Raptor" },
      [13] = { name = "Tiger" },
      [12] = { name = "Crab" },
    },
  }

  local roll_index = 0
  local roulette = new_roulette({
    get_key_items = function()
      return state.key_items
    end,
    get_buffs = function()
      return state.buffs
    end,
    key_items = resources.key_items,
    mounts = resources.mounts,
    random = function()
      roll_index = roll_index + 1
      return state.rolls[roll_index] or 0
    end,
  })
  return roulette, state
end

describe("mount availability", function()
  --[[ A mount slot is unusable in a zone that forbids mounting, and for the
       60 seconds after a summon (Kevin, 2026-08-29). The zone answer comes
       from the resources' own `can_mount`, which is present-or-absent
       rather than true/false; the cooldown is tracked here because nothing
       in get_ability_recasts() carries it - there is no mount ability at
       all in the job_abilities resource. ]]
  local function build(overrides)
    overrides = overrides or {}
    local state = {
      zone = overrides.zone,
      buffs = overrides.buffs or {},
    }
    local roulette = new_roulette({
      mounts = { [1] = { name = "Chocobo" } },
      key_items = {},
      get_key_items = function()
        return {}
      end,
      get_buffs = function()
        return state.buffs
      end,
      zones = overrides.zones == nil and {
        [100] = { id = 100, en = "Carpenters' Landing", can_mount = true },
        [200] = { id = 200, en = "Port Bastok" },
      } or overrides.zones,
      get_zone = function()
        return state.zone
      end,
      random = function()
        return 0.5
      end,
    })
    return roulette, state
  end

  describe("where you are", function()
    it("allows mounting in a zone whose resource says can_mount", function()
      local roulette = build({ zone = 100 })
      assert.is_false(roulette.blocked())
    end)

    it("blocks it in a zone that does not", function()
      -- `can_mount` is absent rather than false on a city or dungeon, so
      -- the test is presence, never a comparison against false.
      local roulette = build({ zone = 200 })
      assert.is_true(roulette.blocked())
    end)

    it("does not block on a zone it cannot resolve", function()
      --[[ The repo's rule for the cost corner, applied here: dimming on
           ignorance reads as unusable at every login. An unknown zone, a
           missing zones table and no zone at all all answer "not blocked". ]]
      assert.is_false(build({ zone = 999 }).blocked(), "a zone not in the table")
      assert.is_false(build({ zone = nil }).blocked(), "no zone yet")
      assert.is_false(build({ zone = 200, zones = {} }).blocked(), "no zones resource")
    end)
  end)

  describe("the cooldown", function()
    it("reports nothing outstanding before any summon", function()
      local roulette = build({ zone = 100 })
      assert.are.equal(0, roulette.cooldown(500))
    end)

    it("counts sixty seconds down from the summon", function()
      local roulette = build({ zone = 100 })
      roulette.summoned(1000)
      assert.are.equal(60, roulette.cooldown(1000))
      assert.are.equal(38, roulette.cooldown(1022))
      assert.are.equal(0, roulette.cooldown(1060), "expired exactly on the minute")
      assert.are.equal(0, roulette.cooldown(9999), "and stays expired")
    end)

    it("restarts from the latest summon", function()
      local roulette = build({ zone = 100 })
      roulette.summoned(1000)
      roulette.summoned(1030)
      assert.are.equal(60, roulette.cooldown(1030))
    end)

    it("never answers a negative, whatever the clock does", function()
      -- A clock that goes backwards (a reload re-basing os.clock) must not
      -- produce a remaining longer than the cooldown, nor a negative one.
      local roulette = build({ zone = 100 })
      roulette.summoned(1000)
      assert.are.equal(60, roulette.cooldown(900))
    end)
  end)
end)

describe("crossbar roulette", function()
  describe("display names", function()
    it("answers the resource's own casing for an owned mount", function()
      -- `/mount` takes the lower-case name, so that is what `owned` carries
      -- and what a binding stores; a label wants the name as the game
      -- writes it.
      local roulette = world()
      roulette.refresh()
      assert.equal("Raptor", roulette.display("raptor"))
      assert.equal("Crab", roulette.display("crab"))
    end)

    it("hands back anything it does not know, unchanged", function()
      local roulette = world()
      roulette.refresh()
      assert.equal("nonesuch", roulette.display("nonesuch"))
      assert.is_nil(roulette.display(nil))
    end)
  end)

  describe("the mounted state", function()
    it("answers whether the mounted buff is up", function()
      -- The travel delay holds a summon and lets a dismount go at once, so
      -- something has to say which of the two a press is - and it is this,
      -- the same buff read ride() already turns on, rather than a second
      -- look at the client that could disagree with it.
      local roulette = world({ buffs = { 252 } })
      assert.is_true(roulette.mounted())
      assert.equal("input /dismount", roulette.ride())
    end)

    it("answers false with no mount up", function()
      local roulette = world()
      assert.is_false(roulette.mounted())
      assert.is_false(world({ buffs = false }).mounted(), "and does not throw without a buff list")
    end)
  end)

  describe("owned mounts", function()
    it("matches mount key items to mounts by the note-prefixed name", function()
      local roulette = world()
      assert.same({ "raptor", "crab" }, roulette.owned())
    end)

    it("ignores key items outside the Mounts category", function()
      local roulette = world({ key_items = { 3010 } })
      assert.same({}, roulette.owned())
      -- And the case that actually needs the category check: a key item
      -- whose name WOULD prefix-match a mount. Without it, the name alone
      -- would make this a rideable mount.
      assert.same({}, world({ key_items = { 3011 } }).owned(), "note-prefixed, wrong category")
    end)

    it("ignores the trainer's whistle", function()
      local roulette = world({ key_items = { 3002 } })
      assert.same({}, roulette.owned())
    end)

    it("ignores a key item id absent from the resources", function()
      local roulette = world({ key_items = { 3006 } })
      assert.same({}, roulette.owned())
    end)

    it("owns a mount once however many key items match it", function()
      -- 3000 and 3003 both prefix-match Raptor; the pick pool must not
      -- double-weight it.
      local roulette = world({ key_items = { 3000, 3003 } })
      assert.same({ "raptor" }, roulette.owned())
    end)

    it("breaks a multi-mount match by the lowest resource id", function()
      -- "Raptor" (11) and "Raptor Companion" (14) both prefix-match the
      -- 3000 key item; the sorted id walk decides, not iteration order.
      local roulette = world({ key_items = { 3000 } })
      assert.same({ "raptor" }, roulette.owned())
    end)

    it("ignores a mount key item whose name matches no mount", function()
      -- 3005 IS in the key-item resources with category Mounts, so this
      -- reaches the name match and pins the nil-mount guard.
      local roulette = world({ key_items = { 3005 } })
      assert.same({}, roulette.owned())
    end)

    it("refreshes on key item chunk 0x055 and only that chunk", function()
      local roulette, state = world({ key_items = {} })
      assert.same({}, roulette.owned())
      state.key_items = { 3000 }
      roulette.on_chunk(0x054)
      assert.same({}, roulette.owned())
      roulette.on_chunk(0x055)
      assert.same({ "raptor" }, roulette.owned())
    end)
  end)

  describe("ride", function()
    it("dismounts when the mounted buff is up", function()
      local roulette = world({ buffs = { 40, 252 } })
      assert.equal("input /dismount", roulette.ride())
    end)

    it("does nothing when no mounts are owned", function()
      local roulette = world({ key_items = {} })
      assert.is_nil(roulette.ride())
    end)

    it("mounts a random pick from the owned list", function()
      local roulette = world({ rolls = { 0.9 } })
      assert.equal('input /mount "crab"', roulette.ride())
    end)

    it("stays in range when the roll is zero", function()
      local roulette = world({ rolls = { 0 } })
      assert.equal('input /mount "raptor"', roulette.ride())
    end)

    it("survives a nil buff list", function()
      local roulette, state = world({ rolls = { 0 } })
      state.buffs = nil
      assert.equal('input /mount "raptor"', roulette.ride())
    end)
  end)
end)
