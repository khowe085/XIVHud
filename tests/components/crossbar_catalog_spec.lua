local new_catalog = require("components/crossbar/catalog")

--[[ The binder's catalog: what the player can actually bind, grouped for the
     picker. Everything here is pure - injected client tables in, category
     lists out - so the defect-10 level rule (merit spells) is testable
     without a client. ]]

-- SCH main / BLM sub, the roster's own job pair.
local function player()
  return {
    main_job = "SCH",
    main_job_id = 20,
    main_job_level = 99,
    sub_job = "BLM",
    sub_job_id = 4,
    sub_job_level = 49,
  }
end

local function resources()
  return {
    spells = {
      -- Known to both jobs, inside both levels.
      [1] = { id = 1, en = "Cure", type = "WhiteMagic", levels = { [20] = 5, [4] = 1 } },
      -- Sub-only: the main job cannot know it at all.
      [144] = { id = 144, en = "Stone", type = "BlackMagic", levels = { [4] = 1 } },
      -- Above the sub's level, inside the main's.
      [149] = { id = 149, en = "Stone III", type = "BlackMagic", levels = { [20] = 55, [4] = 55 } },
      -- The defect-10 fixture: a merit spell's sentinel requirement.
      [98] = { id = 98, en = "Refresh III", type = "WhiteMagic", levels = { [20] = 1200 } },
      -- A merit spell only the SUB could know: the strict test stands there.
      [204] = { id = 204, en = "Death", type = "BlackMagic", levels = { [4] = 1200 } },
      [896] = { id = 896, en = "Shantotto II", type = "Trust", levels = { [20] = 1, [4] = 1 } },
    },
    job_abilities = {
      [696] = { id = 696, en = "Penury", levels = { [20] = 5 } },
      -- Known, but this job pair cannot have it.
      [605] = { id = 605, en = "Provoke", levels = { [1] = 5 } },
      -- A merit ability on the main job.
      [720] = { id = 720, en = "Enlightenment", levels = { [20] = 1200 } },
    },
    weapon_skills = {
      [42] = { id = 42, en = "Savage Blade", skill = 4 },
    },
    items = {
      [4165] = { id = 4165, en = "Prism Powder", category = "Usable" },
      [17040] = { id = 17040, en = "Warp Cudgel", category = "Weapon" },
    },
    mounts = {},
  }
end

local function build(overrides)
  overrides = overrides or {}
  local world = {
    player = overrides.player == nil and player() or overrides.player,
    spells = overrides.spells or { [1] = true, [144] = true, [149] = true, [98] = true, [204] = true, [896] = true },
    abilities = overrides.abilities or { job_abilities = { 696, 605, 720 }, weapon_skills = { 42 } },
    items = overrides.items or { [0] = { { id = 4165, count = 2 }, { id = 17040, count = 1 } } },
    mounts = overrides.mounts or { "chocobo" },
  }
  local catalog = new_catalog({
    get_player = function()
      return world.player
    end,
    get_spells = function()
      return world.spells
    end,
    get_abilities = function()
      return world.abilities
    end,
    get_items = function(bag)
      return world.items[bag]
    end,
    owned_mounts = function()
      return world.mounts
    end,
    mount_display = overrides.mount_display,
    resources = overrides.resources == nil and resources() or overrides.resources,
    bags = overrides.bags,
    extdata_decode = overrides.extdata_decode,
  })
  return catalog, world
end

local function category(list, name)
  for _, entry in ipairs(list) do
    if entry.name == name then
      return entry
    end
  end
  return nil
end

local function labels(list, name)
  local found = category(list, name)
  local out = {}
  for _, entry in ipairs(found and found.entries or {}) do
    out[#out + 1] = entry.label
  end
  return out
end

local function entry_named(list, name, label)
  local found = category(list, name)
  for _, entry in ipairs(found and found.entries or {}) do
    if entry.label == label then
      return entry
    end
  end
  return nil
end

local function has(list, name, label)
  for _, entry in ipairs(labels(list, name)) do
    if entry == label then
      return true
    end
  end
  return false
end

describe("crossbar catalog", function()
  describe("mount casing", function()
    it("lists a mount as the game writes it and binds the name /mount takes", function()
      -- Both come off the same owned list, which is lower-cased because it
      -- IS the command form. Reading the label off it too is what made a
      -- binder-bound mount announce "Mount chocobo".
      local catalog = build({
        mounts = { "raptor companion" },
        mount_display = function(name)
          return name == "raptor companion" and "Raptor Companion" or name
        end,
      })
      local entry = entry_named(catalog.build(), "Mounts", "Raptor Companion")
      assert.is_not_nil(entry)
      assert.equal("mount", entry.record.type)
      assert.equal("raptor companion", entry.record.action, "the command form is what gets sent")
      assert.equal("Raptor Companion", entry.record.display, "and the display form rides along for the label")
      assert.is_nil(entry.record.alias, "alias belongs to the player, not to us")
    end)

    it("falls back to the owned name with no display lookup wired", function()
      local catalog = build({ mounts = { "chocobo" } })
      local entry = entry_named(catalog.build(), "Mounts", "chocobo")
      assert.is_not_nil(entry)
      assert.is_nil(entry.record.display)
      assert.is_nil(entry.record.alias)
    end)
  end)

  describe("spells", function()
    it("merges the main and sub job's known spells", function()
      local catalog = build()
      local built = catalog.build()
      assert.is_true(has(built, "White Magic", "Cure"), "main and sub both know Cure")
      assert.is_true(has(built, "Black Magic", "Stone"), "the sub's own spell")
    end)

    it("includes a spell inside the main job's level but past the sub's", function()
      local catalog = build()
      assert.is_true(has(catalog.build(), "Black Magic", "Stone III"))
    end)

    it("excludes a spell above every level it could be known at", function()
      local catalog = build({
        player = (function()
          local p = player()
          p.main_job_level = 30
          p.sub_job_level = 15
          return p
        end)(),
      })
      assert.is_false(has(catalog.build(), "Black Magic", "Stone III"), "55 is past both levels")
    end)

    it("includes a merit spell on the main job - defect 10", function()
      -- The reference gates on `levels[job] <= job_level`, and a merit
      -- spell's requirement is a sentinel far above the cap, so Refresh III
      -- could never be bound there. Having learned it is proof the gate was
      -- passed.
      local catalog = build()
      assert.is_true(has(catalog.build(), "White Magic", "Refresh III"))
    end)

    it("excludes a merit spell the SUB job would have to supply", function()
      -- Merits and job points apply to the main job only, so the strict
      -- level test stands on the sub half of the merge.
      local catalog = build()
      assert.is_false(has(catalog.build(), "Black Magic", "Death"))
    end)

    it("excludes an unknown spell whatever its level", function()
      local catalog = build({ spells = { [1] = true } })
      local built = catalog.build()
      assert.is_true(has(built, "White Magic", "Cure"))
      assert.is_false(has(built, "Black Magic", "Stone"), "not in get_spells()")
    end)

    it("reads get_spells' own false as unknown, not as merely absent", function()
      -- The client answers a map of booleans, so a spell can be present and
      -- false; treating the key's existence as knowledge would offer every
      -- spell the table mentions.
      local catalog = build({ spells = { [1] = true, [144] = false } })
      local built = catalog.build()
      assert.is_true(has(built, "White Magic", "Cure"))
      assert.is_false(has(built, "Black Magic", "Stone"), "present, and false")
    end)

    it("includes a spell learned at exactly the job's level", function()
      -- The boundary the reference gets right and we must not lose: the
      -- test is `required <= level`, not `<`.
      local catalog = build({
        player = (function()
          local p = player()
          p.main_job_level = 55
          p.sub_job_level = 1
          return p
        end)(),
      })
      assert.is_true(has(catalog.build(), "Black Magic", "Stone III"), "55 at level 55")
    end)

    it("excludes a known spell neither job can ever know", function()
      local catalog = build({
        player = (function()
          local p = player()
          p.sub_job_id = nil
          p.sub_job_level = nil
          return p
        end)(),
      })
      assert.is_false(has(catalog.build(), "Black Magic", "Stone"), "no BLM in the pair any more")
    end)

    it("groups trusts of their own, away from the magic schools", function()
      local built = build().build()
      assert.is_true(has(built, "Trusts", "Shantotto II"))
      assert.is_false(has(built, "Trust", "Shantotto II"), "the raw resource type is never a category")
    end)

    it("binds every spell, trusts included, as /ma", function()
      -- `/trust` is not a command word: upstream maps the trust category to
      -- `ma`, and so do we.
      local built = build().build()
      local trusts = category(built, "Trusts")
      assert.are.same({ type = "ma", action = "Shantotto II" }, trusts.entries[1].record)
    end)
  end)

  describe("abilities and weaponskills", function()
    it("includes an ability the job pair can know", function()
      assert.is_true(has(build().build(), "Job Abilities", "Penury"))
    end)

    it("excludes an ability neither job can know", function()
      assert.is_false(has(build().build(), "Job Abilities", "Provoke"))
    end)

    it("includes a merit ability on the main job - the same rule as spells", function()
      assert.is_true(has(build().build(), "Job Abilities", "Enlightenment"))
    end)

    it("excludes an ability the client never listed", function()
      local catalog = build({ abilities = { job_abilities = { 605 }, weapon_skills = {} } })
      assert.is_false(has(catalog.build(), "Job Abilities", "Penury"))
    end)

    it("takes the client's weaponskill list as it stands", function()
      local built = build().build()
      assert.is_true(has(built, "Weapon Skills", "Savage Blade"))
      assert.are.same(
        { type = "ws", action = "Savage Blade" },
        category(built, "Weapon Skills").entries[1].record,
        "bound as /ws"
      )
    end)
  end)

  describe("items, mounts and built-ins", function()
    it("lists usable items from the inventory only", function()
      local built = build().build()
      assert.is_true(has(built, "Items", "Prism Powder"))
      assert.is_false(has(built, "Items", "Warp Cudgel"), "a weapon is not a usable item")
    end)

    it("lists an item once however many stacks of it are carried", function()
      local catalog = build({
        items = { [0] = { { id = 4165, count = 12 }, { id = 4165, count = 3 }, { id = 4165, count = 1 } } },
      })
      assert.are.same({ "Prism Powder" }, labels(catalog.build(), "Items"), "three stacks, one entry")
    end)

    it("lists an owned mount, bound as /mount", function()
      local built = build().build()
      assert.are.same({ type = "mount", action = "chocobo" }, entry_named(built, "Mounts", "chocobo").record)
    end)

    it("files Mount Roulette with the mounts, at the head of them", function()
      --[[ It was in General beside Warp, which is where a player looking
           for it does not look (Kevin, 2026-08-29). It is pinned above the
           mounts rather than sorted among them: it is not a mount, and an
           owned mount whose name sorts before it would otherwise bury it. ]]
      local built = build({ mounts = { "adamantoise", "chocobo" } }).build()
      local mounts = category(built, "Mounts")
      assert.are.equal("Mount Roulette", mounts.entries[1].label)
      assert.are.same({ type = "mr" }, mounts.entries[1].record)
      assert.are.same({ "adamantoise", "chocobo" }, { mounts.entries[2].label, mounts.entries[3].label })
      assert.is_false(has(built, "General", "Mount Roulette"), "and no longer in General")
    end)

    it("offers no roulette to a player who owns no mounts", function()
      -- A roulette over nothing cannot fire, and the Mounts group is built
      -- from owned mounts, so both vanish together.
      local built = build({ mounts = {} }).build()
      assert.is_nil(category(built, "Mounts"))
    end)

    it("carries the built-ins, Attack among them as the draw toggle", function()
      local built = build().build()
      local general = category(built, "General")
      local seen = {}
      for _, entry in ipairs(general.entries) do
        seen[entry.label] = entry.record
      end
      assert.are.same({ type = "draw" }, seen["Attack"], "Attack is the state-aware toggle")
      assert.are.same({ type = "warp" }, seen["Warp"])
      assert.are.same({ type = "ra" }, seen["Ranged Attack"])
    end)

    it("carries every open target as its own entry", function()
      local openers = require("components/crossbar/openers")
      local built = build().build()
      local opens = {}
      for _, entry in ipairs(category(built, "Open").entries) do
        opens[entry.record.action] = entry.record.type
      end
      for name in pairs(openers) do
        assert.are.equal("open", opens[name], name)
      end
    end)

    it("keeps ct and ex out of v1", function()
      local built = build().build()
      for _, group in ipairs(built) do
        for _, entry in ipairs(group.entries) do
          assert.is_not_equal("ct", entry.record.type)
          assert.is_not_equal("ex", entry.record.type)
        end
      end
    end)
  end)

  describe("shape", function()
    it("sorts entries inside a category and drops empty ones", function()
      local catalog = build({ mounts = {} })
      local built = catalog.build()
      assert.is_nil(category(built, "Mounts"), "an empty category is not offered")
      local white = labels(built, "White Magic")
      assert.are.same({ "Cure", "Refresh III" }, white, "sorted by label")
    end)

    it("puts the schools first and the built-ins last", function()
      local built = build().build()
      assert.are.equal("General", built[#built].name)
      assert.are.equal("Black Magic", built[1].name)
    end)

    it("survives a client that answers nothing at all", function()
      local catalog = new_catalog({})
      local built
      assert.has_no.errors(function()
        built = catalog.build()
      end)
      assert.is_table(built)
      -- The built-ins need no client, so they are all that survives.
      assert.are.same({ "Open", "General" }, { built[1].name, built[2].name })
      assert.is_nil(category(built, "White Magic"))
    end)

    it("survives garbage in every injected table", function()
      local catalog = new_catalog({
        get_player = function()
          return 42
        end,
        get_spells = function()
          return "no"
        end,
        get_abilities = function()
          return { job_abilities = 7, weapon_skills = { "x" } }
        end,
        get_items = function()
          return { 5, { id = "nope" } }
        end,
        owned_mounts = function()
          return { 9 }
        end,
        resources = { spells = "broken", items = {} },
      })
      assert.has_no.errors(function()
        catalog.build()
      end)
    end)
  end)

  describe("enchanted equipment", function()
    -- Gear lives in wardrobes as well as inventory, so this group walks the
    -- equippable bags rather than bag 0 alone.
    local function enchanted_world(overrides)
      overrides = overrides or {}
      local res = resources()
      res.items[27546] = { id = 27546, en = "Vocation Ring", category = "Armor", slots = { [13] = true } }
      res.items[11111] = { id = 11111, en = "Plain Ring", category = "Armor", slots = { [13] = true } }
      local decoded = overrides.decoded
        or {
          [27546] = { type = "Enchanted Equipment", charges_remaining = 3 },
          [11111] = { type = "General" },
        }
      return build({
        resources = res,
        items = {
          [0] = { enabled = true, { id = 4165, count = 2, slot = 1 } },
          [8] = { enabled = true, { id = 27546, count = 1, slot = 2 }, { id = 11111, count = 1, slot = 3 } },
        },
        bags = {
          [0] = { id = 0, name = "Inventory", equippable = true },
          [8] = { id = 8, name = "Wardrobe", equippable = true },
        },
        extdata_decode = function(item)
          return decoded[item.id]
        end,
      })
    end

    it("lists enchanted gear from every equippable bag, bound as enchanteditem", function()
      local catalog = enchanted_world()
      local list = catalog.build()
      assert.is_true(has(list, "Enchanted", "Vocation Ring"))
      local entry = category(list, "Enchanted").entries[1]
      assert.equal("enchanteditem", entry.record.type)
      assert.equal("Vocation Ring", entry.record.action)
    end)

    it("leaves out gear in a bag that cannot be reached", function()
      -- Binding it would produce a slot reading 0 with a red X, whose press
      -- answers "you cannot access it" - the count and the press already
      -- agree on this, and the picker has to as well.
      local res = resources()
      res.items[27546] = { id = 27546, en = "Vocation Ring", category = "Armor", slots = { [13] = true } }
      local catalog = build({
        resources = res,
        items = { [8] = { enabled = false, { id = 27546, count = 1, slot = 2 } } },
        bags = { [8] = { id = 8, name = "Wardrobe", equippable = true } },
        extdata_decode = function()
          return { type = "Enchanted Equipment", charges_remaining = 3 }
        end,
      })
      assert.is_nil(category(catalog.build(), "Enchanted"))
    end)

    it("leaves out gear with no enchantment on it", function()
      local catalog = enchanted_world()
      assert.is_false(has(catalog.build(), "Enchanted", "Plain Ring"))
    end)

    it("does not move consumables out of Items", function()
      local catalog = enchanted_world()
      local list = catalog.build()
      assert.is_true(has(list, "Items", "Prism Powder"))
      assert.is_false(has(list, "Enchanted", "Prism Powder"))
    end)

    it("decodes only what could be worn, never the whole bag", function()
      -- A wardrobe pass that decoded every stack would be hundreds of
      -- extdata reads on the click that opens the binder.
      local seen = {}
      local res = resources()
      res.items[27546] = { id = 27546, en = "Vocation Ring", category = "Armor", slots = { [13] = true } }
      local catalog = build({
        resources = res,
        items = { [0] = { enabled = true, { id = 4165, count = 2, slot = 1 }, { id = 27546, count = 1, slot = 2 } } },
        bags = { [0] = { id = 0, name = "Inventory", equippable = true } },
        extdata_decode = function(item)
          seen[#seen + 1] = item.id
          return { type = "Enchanted Equipment" }
        end,
      })
      catalog.build()
      assert.are.same({ 27546 }, seen, "Prism Powder has no slots, so it was never decoded")
    end)

    it("draws no Enchanted group without an extdata decoder", function()
      -- The library is optional; the rest of the catalog carries on.
      local res = resources()
      res.items[27546] = { id = 27546, en = "Vocation Ring", category = "Armor", slots = { [13] = true } }
      local catalog = build({
        resources = res,
        items = { [0] = { enabled = true, { id = 4165, count = 2, slot = 1 }, { id = 27546, count = 1, slot = 2 } } },
        bags = { [0] = { id = 0, name = "Inventory", equippable = true } },
      })
      local list = catalog.build()
      assert.is_nil(category(list, "Enchanted"))
      assert.is_true(has(list, "Items", "Prism Powder"))
    end)

    it("draws no Enchanted group without a bag table to walk", function()
      local catalog = build({ bags = nil })
      assert.is_nil(category(catalog.build(), "Enchanted"))
    end)
  end)
end)
