local new_catalog = require("lib/actionbar/catalog")

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
      [3] = { id = 3, en = "Skullbreaker", skill = 3 },
      -- A weaponskill the resources cannot name a weapon for.
      [90] = { id = 90, en = "Nameless Blow", skill = 41 },
    },
    skills = { [3] = { id = 3, en = "Club" }, [4] = { id = 4, en = "Sword" } },
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
    master_level = overrides.master_level,
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

    --[[ A weaponskill is bound on a WEAPON layer and nowhere else (Kevin,
         2026-10-12), so no other layer's listing carries the category. ]]
    it("offers no weaponskills off a weapon layer", function()
      local catalog = build({ abilities = { job_abilities = {}, weapon_skills = { 42, 3 } } })
      assert.is_nil(category(catalog.build(), "Weapon Skills"))
      assert.is_nil(category(catalog.build({ sub = "BLM" }), "Weapon Skills"))
    end)

    --[[ And on one, the listing behaves as if that weapon were in hand, with
         every weaponskill of the class the resources carry - not only what
         the client says the job knows, which need not cover a weapon you are
         not holding (Kevin, 2026-10-12). ]]
    it("offers every weaponskill of the layer's class, listed by the client or not", function()
      local catalog = build({ abilities = { job_abilities = {}, weapon_skills = {} } })
      local built = catalog.build({ weapon = "Sword" })
      assert.same({ "Savage Blade" }, labels(built, "Weapon Skills"))
      local record = category(built, "Weapon Skills").entries[1].record
      assert.are.same({ type = "ws", action = "Savage Blade" }, record, "bound as /ws")
      assert.same({ "Skullbreaker" }, labels(catalog.build({ weapon = "Club" }), "Weapon Skills"))
    end)

    -- Without the class named there is no telling whose it is.
    it("leaves out a weaponskill whose weapon the resources cannot name", function()
      local built = build().build({ weapon = "Club" })
      assert.is_false(has(built, "Weapon Skills", "Nameless Blow"))
    end)

    it("offers no category for a class nothing carries", function()
      assert.is_nil(category(build().build({ weapon = "Great Katana" }), "Weapon Skills"))
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

    it("offers Reraise among the built-ins", function()
      local general = category(build().build(), "General")
      local seen = {}
      for _, entry in ipairs(general.entries) do
        seen[entry.label] = entry.record
      end
      assert.are.same({ type = "reraise" }, seen["Reraise"])
    end)

    it("carries every open target as its own entry", function()
      local openers = require("lib/actionbar/openers")
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
      local function walk(entries)
        for _, entry in ipairs(entries) do
          if entry.record ~= nil then
            assert.is_not_equal("ct", entry.record.type)
            assert.is_not_equal("ex", entry.record.type)
          end
          walk(entry.children or {})
        end
      end
      for _, group in ipairs(built) do
        walk(group.entries)
      end
    end)

    describe("job change", function()
      local function menu()
        return entry_named(build().build(), "General", "Job Change")
      end

      it("is a menu of every main job, each wearing its icon", function()
        local entry = menu()
        assert.is_table(entry, "General carries Job Change")
        assert.is_nil(entry.record, "the menu itself is not bindable")
        assert.are.equal("targetnpc", entry.icon)
        local file = io.open("src/assets/icons/targetnpc.png", "rb")
        assert.is_not_nil(file, "the menu's icon must ship")
        file:close()
        assert.are.equal(22, #entry.children)
        assert.are.equal("WAR", entry.children[1].label)
        assert.are.equal("jobs/war", entry.children[1].icon)
      end)

      it("offers every sub job but the main, binding the pair labelled by the sub", function()
        local war = menu().children[1]
        assert.are.equal(21, #war.children)
        for _, sub in ipairs(war.children) do
          assert.is_not_equal("WAR", sub.label)
        end
        assert.are.equal("MNK", war.children[1].label)
        assert.are.same({ type = "jc", action = "WAR/MNK", alias = "MNK" }, war.children[1].record)
      end)

      it("needs no client at all", function()
        assert.is_table(entry_named(new_catalog({}).build(), "General", "Job Change"))
      end)
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

  --[[ The parent-menu families: `res.job_abilities` carries a menu entry
       (223 Stratagems, 97 Phantom Roll, 91 Blood Pact: Rage ...) whose
       children are separate records of their own type. Binding the parent
       writes a command the game refuses, and the children were unreachable
       from the picker until this. Ids and type names are the resource's
       own, read off Windower/Resources 2026-09-07. ]]
  describe("parent-menu families", function()
    local function family_resources()
      return {
        spells = {},
        job_abilities = {
          -- The Stratagems menu and two of its sixteen children.
          [223] = { id = 223, en = "Stratagems", prefix = "/jobability", type = "JobAbility" },
          [218] = { id = 218, en = "Accession", prefix = "/jobability", type = "Scholar" },
          [234] = { id = 234, en = "Addendum: White", prefix = "/jobability", type = "Scholar" },
          -- A /pet family, whose children bind as `pet` rather than `ja`.
          [91] = { id = 91, en = "Blood Pact: Rage", prefix = "/pet", type = "PetCommand" },
          [634] = { id = 634, en = "Volt Strike", prefix = "/pet", type = "BloodPactRage" },
          -- Directly usable despite its /pet prefix: not a menu.
          [72] = { id = 72, en = "Sic", prefix = "/pet", type = "PetCommand" },
          -- A menu whose children are the /pet abilities beside it, each of
          -- which the client lists and binds on its own.
          [55] = { id = 55, en = "Pet commands", prefix = "/jobability", type = "JobAbility" },
          -- The DNC menu, whose name is PLURAL in the resource, and one child.
          [183] = { id = 183, en = "Waltzes", prefix = "/jobability", type = "JobAbility" },
          [190] = { id = 190, en = "Curing Waltz", prefix = "/jobability", type = "Waltz" },
          -- An ordinary ability, to prove the flat list still fills.
          [605] = { id = 605, en = "Provoke", prefix = "/jobability", type = "JobAbility" },
        },
        weapon_skills = {},
        skills = {},
        items = {},
        mounts = {},
      }
    end

    local function family_build(listed)
      return build({
        resources = family_resources(),
        spells = {},
        items = { [0] = {} },
        mounts = {},
        abilities = { job_abilities = listed, weapon_skills = {} },
      })
    end

    local function child_labels(list, parent)
      local found = entry_named(list, "Job Abilities", parent)
      local out = {}
      for _, child in ipairs(found and found.children or {}) do
        out[#out + 1] = child.label
      end
      return out
    end

    --[[ A menu row carries no record, so nothing could resolve art for it and
         Stratagems drew a blank gutter beside sixteen icon-bearing rows. The
         field is the CONTEXT roster's own shape - a pack-relative name under
         `assets/icons/` - so `icon_candidates` resolves it through the same
         custom-override-then-pack chain a bound record's `icon=` override
         takes, and a user can override it the same way. ]]
    it("carries the grimoire art on the Stratagems menu", function()
      local catalog = family_build({ 223 })
      assert.equal("abilities/book_white", entry_named(catalog.build(), "Job Abilities", "Stratagems").icon)
    end)

    --[[ Every other family falls back to its JOB's glyph (Kevin, 2026-09-13):
         a menu row has no record for art to be resolved from, and the shipped
         ability sheet is keyed by RECAST id, which nothing here can look up -
         the same bind that makes the context roster use a job icon. Eight of
         the sixteen are COR's or DNC's and so repeat a glyph; a family with
         art of its own says so instead, as Stratagems does. ]]
    it("falls back to the job's glyph on a family with no art of its own", function()
      assert.equal("jobs/smn", entry_named(family_build({ 91 }).build(), "Job Abilities", "Blood Pact: Rage").icon)
      assert.equal("jobs/dnc", entry_named(family_build({ 183 }).build(), "Job Abilities", "Waltzes").icon)
    end)

    --[[ A typo in one of these fails SILENTLY - a missing texture just draws
         nothing (CLAUDE.md) - and the fixtures above can only pin a string
         against itself, so every name the table carries is opened on disk.
         `crossbar_render_spec`'s own move, over the source rather than the
         table, which is file-local. ]]
    it("names art that actually ships, on every family", function()
      local source = assert(io.open("src/lib/actionbar/catalog.lua", "r"))
      local body = source:read("*a")
      source:close()
      local seen = 0
      for name in body:gmatch('icon = "([^"]+)"') do
        seen = seen + 1
        local path = "src/assets/icons/" .. name .. ".png"
        local art = io.open(path, "rb")
        assert.is_not_nil(art, path .. " does not ship")
        art:close()
      end
      assert.is_true(seen >= 16, "expected an icon per family, found " .. seen)
    end)

    it("offers the parent as a submenu rather than a bindable record", function()
      local catalog = family_build({ 223 })
      local parent = entry_named(catalog.build(), "Job Abilities", "Stratagems")
      assert.is_not_nil(parent)
      assert.is_nil(parent.record, "binding the menu writes a command the game refuses")
      assert.is_table(parent.children)
    end)

    it("takes the children the client lists, when it lists any", function()
      local catalog = family_build({ 223, 218 })
      assert.same({ "Accession" }, child_labels(catalog.build(), "Stratagems"))
    end)

    it("offers the whole family when the client lists none of its children", function()
      local catalog = family_build({ 223 })
      assert.same({ "Accession", "Addendum: White" }, child_labels(catalog.build(), "Stratagems"))
    end)

    it("omits a family whose parent the client does not list", function()
      local catalog = family_build({ 605 })
      local list = catalog.build()
      assert.is_nil(entry_named(list, "Job Abilities", "Stratagems"))
      assert.is_false(has(list, "Job Abilities", "Accession"))
      assert.is_true(has(list, "Job Abilities", "Provoke"))
    end)

    it("keeps a listed child out of the flat list, so it is offered once", function()
      local list = family_build({ 223, 218 }).build()
      assert.is_false(has(list, "Job Abilities", "Accession"))
    end)

    it("binds a /pet family's children as pet, off the resource's own prefix", function()
      local list = family_build({ 91 }).build()
      local children = entry_named(list, "Job Abilities", "Blood Pact: Rage").children
      assert.same({ type = "pet", action = "Volt Strike" }, children[1].record)
    end)

    it("leaves Sic a plain bindable ability - it is usable, not a menu", function()
      local list = family_build({ 72 }).build()
      local sic = entry_named(list, "Job Abilities", "Sic")
      assert.same({ type = "pet", action = "Sic" }, sic.record)
      assert.is_nil(sic.children)
    end)

    it("leaves a child flat when the client lists it but not its parent", function()
      -- The no-regression case: nothing is spoken for by a family that is not
      -- on offer, so the child stays an ordinary bindable ability.
      local list = family_build({ 218 }).build()
      assert.is_nil(entry_named(list, "Job Abilities", "Stratagems"))
      assert.same({ type = "ja", action = "Accession" }, entry_named(list, "Job Abilities", "Accession").record)
    end)

    it("offers a family on the client's list alone, never on a level rule", function()
      -- `res.job_abilities` carries no levels, so nothing can gate a family -
      -- but a parent turned down while its children stayed spoken for would
      -- take the whole family off the picker with no submenu behind it.
      local levelled = family_resources()
      levelled.job_abilities[223].levels = { [20] = 1200 }
      local catalog = build({
        resources = levelled,
        spells = {},
        items = { [0] = {} },
        mounts = {},
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 99 },
        abilities = { job_abilities = { 223 }, weapon_skills = {} },
      })
      local list = catalog.build()
      assert.is_not_nil(entry_named(list, "Job Abilities", "Stratagems"), "the client listed it, so it is on offer")
      assert.same({ "Accession", "Addendum: White" }, child_labels(list, "Stratagems"))
    end)

    it("leaves the children flat when the resources cannot supply the parent", function()
      --[[ The mirror of the case below. A family is only spoken for once the
           PARENT RECORD is there to open it: without one no submenu can be
           built, and suppressing the children too would take them off the
           picker with no message - the silent removal this file warns about,
           and the opposite of degrading toward offering more. ]]
      local degraded = family_resources()
      degraded.job_abilities[223] = nil
      local catalog = build({
        resources = degraded,
        spells = {},
        items = { [0] = {} },
        mounts = {},
        abilities = { job_abilities = { 223, 218 }, weapon_skills = {} },
      })
      local list = catalog.build()
      assert.is_nil(entry_named(list, "Job Abilities", "Stratagems"))
      assert.same({ type = "ja", action = "Accession" }, entry_named(list, "Job Abilities", "Accession").record)
    end)

    --[[ The seventeen ids are hand-transcribed and cannot be checked here, and
         the file's own warning is that a wrong one REMOVES a usable ability
         from the picker with no message. Checking the parent's own type turns
         that into a no-op: an id naming something that is not the menu it was
         meant to be is left flat, which is the direction everything else here
         degrades in. ]]
    it("leaves an id flat when it is not the menu it was taken for", function()
      local wrong = family_resources()
      -- 223 is Stratagems, a JobAbility. Something else entirely lives here.
      wrong.job_abilities[223] = { id = 223, en = "Berserk", prefix = "/jobability", type = "Scholar" }
      local catalog = build({
        resources = wrong,
        spells = {},
        items = { [0] = {} },
        mounts = {},
        abilities = { job_abilities = { 223, 218 }, weapon_skills = {} },
      })
      local list = catalog.build()
      assert.same({ type = "ja", action = "Berserk" }, entry_named(list, "Job Abilities", "Berserk").record)
      assert.is_not_nil(entry_named(list, "Job Abilities", "Accession"), "and its family is not swallowed")
    end)

    it("drops a parent whose children the resources cannot supply", function()
      local degraded = family_resources()
      degraded.job_abilities[218] = nil
      degraded.job_abilities[234] = nil
      local catalog = build({
        resources = degraded,
        spells = {},
        items = { [0] = {} },
        mounts = {},
        abilities = { job_abilities = { 223 }, weapon_skills = {} },
      })
      -- An empty submenu is a dead end, and the parent itself cannot be bound.
      assert.is_nil(entry_named(catalog.build(), "Job Abilities", "Stratagems"))
    end)

    --[[ The DNC menus are parents too, and were missed on the first pass: the
         resource names them in the PLURAL (`Waltzes`, `Sambas`, `Jigs`,
         `Steps`, `Flourishes I..III`), so a search for `Waltz` found only the
         children and the family read as parentless. `/ja "Waltzes"` is the
         same dead bind as `/ja "Stratagems"`. ]]
    it("treats the plural DNC menus as parents like any other", function()
      local list = family_build({ 183 }).build()
      local parent = entry_named(list, "Job Abilities", "Waltzes")
      assert.is_nil(parent.record, "a mode menu is not an action")
      assert.same({ "Curing Waltz" }, child_labels(list, "Waltzes"))
    end)

    --[[ `Pet commands` (55) is a menu like the rest, but it needs no submenu:
         its children are the `PetCommand` abilities - Fight, Heel, Sic, the
         maneuvers - which the client lists and binds individually already. So
         it is dropped rather than opened, or it would be one more dead bind
         (`/ja "Pet commands"`) in the flat list. ]]
    it("drops a menu whose children are already bindable on their own", function()
      local list = family_build({ 55, 72 }).build()
      assert.is_nil(entry_named(list, "Job Abilities", "Pet commands"))
      assert.is_not_nil(entry_named(list, "Job Abilities", "Sic"), "its children are untouched")
    end)

    it("leaves a family's child flat while its own parent is unlisted", function()
      local list = family_build({ 190 }).build()
      assert.is_true(has(list, "Job Abilities", "Curing Waltz"))
    end)
  end)
  --[[ The binder edits a subjob you are not on and a class you are not
       holding (Kevin, 2026-10-12), so the listing follows the LAYER, handed
       to build: the class it names filters the weaponskills, and a subjob
       layer - the worn one included - takes the sub's place at the highest
       level a support job can reach, its spells off what the character has
       learned and its abilities off `lib/actionbar/job_abilities`. ]]
  describe("for a layer the player is not using", function()
    local function with_jobs()
      local res = resources()
      res.jobs = {
        [1] = { id = 1, ens = "WAR" },
        [3] = { id = 3, ens = "WHM" },
        [4] = { id = 4, ens = "BLM" },
        [5] = { id = 5, ens = "RDM" },
        [9] = { id = 9, ens = "BST" },
        [11] = { id = 11, ens = "RNG" },
        [13] = { id = 13, ens = "NIN" },
        [17] = { id = 17, ens = "COR" },
        [20] = { id = 20, ens = "SCH" },
      }
      res.spells[2] = { id = 2, en = "Cure II", type = "WhiteMagic", levels = { [3] = 11 } }
      res.spells[3] = { id = 3, en = "Cure III", type = "WhiteMagic", levels = { [3] = 21 } }
      res.spells[4] = { id = 4, en = "Cure IV", type = "WhiteMagic", levels = { [3] = 41 } }
      res.spells[5] = { id = 5, en = "Cure V", type = "WhiteMagic", levels = { [3] = 61 } }
      return res
    end

    local function spells_known()
      return { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [144] = true }
    end

    local function pair(main, main_id, sub, sub_id)
      return {
        main_job = main,
        main_job_id = main_id,
        main_job_level = 99,
        sub_job = sub,
        sub_job_id = sub_id,
        sub_job_level = 49,
      }
    end

    describe("spells", function()
      -- WHM-only spells either side of every cap a master level can set.
      local function capped(master_level)
        local res = with_jobs()
        local known = {}
        for _, level in ipairs({ 49, 50, 54, 55, 59, 60 }) do
          local id = 300 + level
          res.spells[id] = { id = id, en = "WHM " .. level, type = "WhiteMagic", levels = { [3] = level } }
          known[id] = true
        end
        return build({
          resources = res,
          spells = known,
          master_level = master_level,
        })
      end

      local function at(value)
        return function()
          return value
        end
      end

      --[[ BG Wiki, Master Levels: at 99 a support job's cap is 49, plus one
           level for every five master levels, to 59 at ML50. ]]
      it("caps a subjob at 49 plus a level for every five master levels", function()
        assert.same({ "WHM 49" }, labels(capped(at(0)).build({ sub = "WHM" }), "White Magic"))
        assert.same({ "WHM 49", "WHM 50", "WHM 54" }, labels(capped(at(25)).build({ sub = "WHM" }), "White Magic"))
        assert.same(
          { "WHM 49", "WHM 50", "WHM 54", "WHM 55", "WHM 59" },
          labels(capped(at(50)).build({ sub = "WHM" }), "White Magic")
        )
      end)

      -- Kevin's call, 2026-10-12: no 0x061 seen yet reads as ML50.
      it("assumes master level 50 until the client has said", function()
        local full = { "WHM 49", "WHM 50", "WHM 54", "WHM 55", "WHM 59" }
        assert.same(full, labels(capped(at(nil)).build({ sub = "WHM" }), "White Magic"))
        assert.same(full, labels(capped(nil).build({ sub = "WHM" }), "White Magic"), "and with nothing wired")
      end)

      it("caps a subjob at half the main job's level below 99", function()
        local p = player()
        p.main_job_level = 60
        local catalog = build({
          player = p,
          resources = with_jobs(),
          spells = spells_known(),
          master_level = at(50),
        })
        local white = labels(catalog.build({ sub = "WHM" }), "White Magic")
        assert.same({ "Cure", "Cure II", "Cure III" }, white, "30, whatever the master level says")
        assert.same({}, labels(catalog.build({ sub = "WHM" }), "Black Magic"), "and not the worn sub's")
      end)

      it("lists the worn subjob at the cap too, not at the level it is at", function()
        local res = with_jobs()
        res.spells[355] = { id = 355, en = "BLM 55", type = "BlackMagic", levels = { [4] = 55 } }
        local catalog = build({ resources = res, spells = { [355] = true }, master_level = at(50) })
        assert.is_false(has(catalog.build(), "Black Magic", "BLM 55"), "the live listing is the worn 49")
        assert.is_true(has(catalog.build({ sub = "BLM" }), "Black Magic", "BLM 55"))
      end)

      it("lists only the spells the character has learned", function()
        local catalog = build({
          resources = with_jobs(),
          spells = { [2] = true, [3] = false },
          master_level = at(50),
        })
        assert.same({ "Cure II" }, labels(catalog.build({ sub = "WHM" }), "White Magic"))
      end)
    end)

    describe("job abilities", function()
      -- The ids and names are the resource's, as `job_abilities.lua` holds them.
      local function with_abilities()
        local res = with_jobs()
        local function add(id, en, kind, prefix)
          res.job_abilities[id] = { id = id, en = en, type = kind or "JobAbility", prefix = prefix or "/jobability" }
        end
        add(35, "Provoke")
        add(31, "Berserk")
        add(33, "Defender")
        add(32, "Warcry")
        add(74, "Divine Seal")
        add(75, "Elemental Seal")
        add(173, "Hasso")
        add(174, "Seigan")
        add(59, "Sharpshot")
        add(86, "Unlimited Shot")
        add(97, "Phantom Roll")
        add(114, "Corsair's Roll", "CorsairRoll")
        add(110, "Ninja Roll", "CorsairRoll")
        add(101, "Wizard's Roll", "CorsairRoll")
        add(223, "Stratagems")
        add(218, "Accession", "Scholar")
        add(234, "Addendum: White", "Scholar")
        add(221, "Ebullience", "Scholar")
        add(251, "Ready", "PetCommand", "/pet")
        add(672, "Foot Kick", "Monster", "/pet")
        return res
      end

      local function abilities_build(overrides)
        return build({
          player = overrides.player,
          resources = overrides.resources or with_abilities(),
          spells = {},
          abilities = { job_abilities = overrides.listed or {}, weapon_skills = {} },
          master_level = function()
            return overrides.master_level
          end,
        })
      end

      local function child_labels(list, parent)
        local found = entry_named(list, "Job Abilities", parent)
        local out = {}
        for _, child in ipairs(found and found.children or {}) do
          out[#out + 1] = child.label
        end
        return out
      end

      it("offers a subjob's abilities off the table, up to the cap", function()
        local p = player()
        p.main_job_level = 60
        local list = abilities_build({ player = p }).build({ sub = "WAR" })
        assert.same({ "Berserk", "Defender", "Provoke" }, labels(list, "Job Abilities"), "30 is the cap")
        assert.same({ type = "ja", action = "Provoke" }, entry_named(list, "Job Abilities", "Provoke").record)
      end)

      it("offers the worn subjob's off the table too, past the level it is at", function()
        -- RNG worn at 49: Unlimited Shot is 51, and the client does not list it.
        local list = abilities_build({
          player = pair("SCH", 20, "RNG", 11),
          listed = { 59 },
          master_level = 50,
        }).build({ sub = "RNG" })
        assert.same({ "Sharpshot", "Unlimited Shot" }, labels(list, "Job Abilities"), "and Sharpshot once")
      end)

      --[[ The client lists the abilities of the pair WORN: on WAR/SAM a
           sub:WHM layer would otherwise offer Hasso. ]]
      it("drops the worn subjob's abilities from the main job's list", function()
        local catalog = abilities_build({
          player = pair("WAR", 1, "SAM", 12),
          listed = { 35, 31, 173, 174 },
        })
        assert.same({ "Berserk", "Divine Seal", "Provoke" }, labels(catalog.build({ sub = "WHM" }), "Job Abilities"))
        assert.same(
          { "Berserk", "Provoke" },
          labels(catalog.build(), "Job Abilities"),
          "and so does the base, a subjob's ability being bound through its menu"
        )
      end)

      --[[ A subjob's ability is bound through the subjob menu or under a
           buff context (Kevin, 2026-10-13), never on the base or a weapon
           layer: those drop what the worn sub's table claims. ]]
      it("keeps the worn subjob's abilities off the base and weapon layers", function()
        local catalog = abilities_build({
          player = pair("WAR", 1, "SAM", 12),
          listed = { 35, 31, 173, 174 },
        })
        assert.same({ "Berserk", "Provoke" }, labels(catalog.build(), "Job Abilities"))
        assert.same({ "Berserk", "Provoke" }, labels(catalog.build({ weapon = "Sword" }), "Job Abilities"))
      end)

      it("keeps them under a buff context", function()
        local catalog = abilities_build({
          player = pair("WAR", 1, "SAM", 12),
          listed = { 35, 31, 173, 174 },
        })
        assert.same(
          { "Berserk", "Hasso", "Provoke", "Seigan" },
          labels(catalog.build({ context = "light-arts" }), "Job Abilities")
        )
      end)

      it("lists the client's abilities as they are with no player to read", function()
        local list = abilities_build({ listed = { 35, 173 } }).build()
        assert.same({ "Hasso", "Provoke" }, labels(list, "Job Abilities"))
      end)

      it("keeps one the main job's own table lists as well", function()
        local war = require("lib/actionbar/job_abilities").WAR
        war[#war + 1] = { id = 173, name = "Hasso", level = 25 }
        finally(function()
          war[#war] = nil
        end)
        local catalog = abilities_build({
          player = pair("WAR", 1, "SAM", 12),
          listed = { 35, 173 },
        })
        assert.is_true(has(catalog.build({ sub = "WHM" }), "Job Abilities", "Hasso"))
      end)

      --[[ No shipped subjob reaches a menu whose children the table leaves out
           (BST's Ready is main-job only), so the two cases below stand one up
           for the length of the test. ]]
      local function with_ready()
        local bst = require("lib/actionbar/job_abilities").BST
        bst[#bst + 1] = { id = 251, name = "Ready", level = 25 }
        finally(function()
          bst[#bst] = nil
        end)
      end

      --[[ The table lists a family's children but not always its menu - SCH's
           Stratagems, the DNC and RUN menus - and a menu left on the list
           would offer its whole family on every other layer. ]]
      it("drops a worn subjob's menu with its children", function()
        local list = abilities_build({
          player = pair("RDM", 5, "SCH", 20),
          listed = { 223, 218 },
        }).build({ sub = "WHM" })
        assert.is_nil(entry_named(list, "Job Abilities", "Stratagems"))
        assert.is_false(has(list, "Job Abilities", "Accession"))
      end)

      it("drops what the client lists under a worn subjob's menu", function()
        -- Ready is BST's in the table; a move under it is not listed there.
        with_ready()
        local list = abilities_build({
          player = pair("WAR", 1, "BST", 9),
          listed = { 35, 251, 672 },
        }).build({ sub = "WHM" })
        assert.same({ "Divine Seal", "Provoke" }, labels(list, "Job Abilities"))
      end)

      it("skips a table entry whose id no longer names it", function()
        local res = with_abilities()
        res.job_abilities[31] = nil
        res.job_abilities[35].en = "Shield Bash"
        local list = abilities_build({ resources = res }).build({ sub = "WAR" })
        assert.is_true(has(list, "Job Abilities", "Defender"))
        assert.is_false(has(list, "Job Abilities", "Provoke"))
        assert.is_false(has(list, "Job Abilities", "Shield Bash"), "a drifted id is not offered as something else")
        assert.is_false(has(list, "Job Abilities", "Berserk"))
      end)

      it("builds the menus from the main job's list and the subjob's table together", function()
        local list = abilities_build({
          listed = { 223, 218 },
          master_level = 0,
        }).build({ sub = "COR" })
        assert.same({ "Accession" }, child_labels(list, "Stratagems"), "the main job's, as the client lists it")
        assert.same({ "Corsair's Roll", "Ninja Roll" }, child_labels(list, "Phantom Roll"), "Wizard's Roll is 58")
      end)

      it("opens a subjob's family whose menu the table leaves out", function()
        local list = abilities_build({
          player = pair("RDM", 5, "WHM", 3),
          master_level = 0,
        }).build({ sub = "SCH" })
        assert.same({ "Accession", "Addendum: White" }, child_labels(list, "Stratagems"), "Ebullience is 55")
        assert.is_false(has(list, "Job Abilities", "Accession"), "offered once, inside the menu")
      end)

      it("falls back to the whole family where the table names none of it", function()
        -- Ready's moves are the pet's, so the table would list Ready alone.
        with_ready()
        local list = abilities_build({ player = pair("WAR", 1, "NIN", 13) }).build({ sub = "BST" })
        assert.same({ "Foot Kick" }, child_labels(list, "Ready"))
        assert.same(
          { type = "pet", action = "Foot Kick" },
          entry_named(list, "Job Abilities", "Ready").children[1].record
        )
      end)
    end)
  end)
end)
