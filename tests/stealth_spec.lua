local new_stealth = require("lib/stealth")

local SNEAK, INVISIBLE = 137, 136
local MONOMI, TONKO, TONKO_NI = 318, 353, 354
local JIG = 196
local SANJAKU, SHINOBI, SHIKANOFUDA = 2553, 1194, 2972
local RERAISE, RERAISE_II, RERAISE_III, RERAISE_IV = 135, 141, 142, 848
local RERAISE_BUFF, ADDENDUM_WHITE, ENLIGHTENMENT = 113, 401, 416
local SILENCE, MUTE = 6, 29
local WHM, SCH = 3, 20

-- The resource fields the ladder actually reads, verbatim from Windower's
-- own data: the prefix it fires with, the levels it gates on, and the
-- targets bitfield that decides <t> vs <me>.
local function resources()
  return {
    spells = {
      [SNEAK] = {
        id = SNEAK,
        en = "Sneak",
        prefix = "/magic",
        levels = { [3] = 20, [5] = 20, [20] = 20 },
        targets = 5,
      },
      [INVISIBLE] = {
        id = INVISIBLE,
        en = "Invisible",
        prefix = "/magic",
        levels = { [3] = 25, [5] = 25, [20] = 25 },
        targets = 5,
      },
      [MONOMI] = { id = MONOMI, en = "Monomi: Ichi", prefix = "/ninjutsu", levels = { [13] = 25 }, targets = 1 },
      [TONKO] = { id = TONKO, en = "Tonko: Ichi", prefix = "/ninjutsu", levels = { [13] = 9 }, targets = 1 },
      [TONKO_NI] = { id = TONKO_NI, en = "Tonko: Ni", prefix = "/ninjutsu", levels = { [13] = 34 }, targets = 1 },
      -- `requirements = 4` is the bit SCH opens with an Addendum.
      [RERAISE] = {
        id = RERAISE,
        en = "Reraise",
        prefix = "/magic",
        levels = { [3] = 25, [20] = 35 },
        requirements = 4,
        targets = 1,
        type = "WhiteMagic",
      },
      [RERAISE_II] = {
        id = RERAISE_II,
        en = "Reraise II",
        prefix = "/magic",
        levels = { [3] = 56, [20] = 70 },
        requirements = 4,
        targets = 1,
        type = "WhiteMagic",
      },
      [RERAISE_III] = {
        id = RERAISE_III,
        en = "Reraise III",
        prefix = "/magic",
        levels = { [3] = 70, [20] = 91 },
        requirements = 4,
        targets = 1,
        type = "WhiteMagic",
      },
      [RERAISE_IV] = {
        id = RERAISE_IV,
        en = "Reraise IV",
        prefix = "/magic",
        levels = { [3] = 100 },
        requirements = 0,
        targets = 1,
        type = "WhiteMagic",
      },
    },
    job_abilities = {
      [JIG] = { id = JIG, en = "Spectral Jig", prefix = "/jobability", targets = 1 },
    },
  }
end

local function build(overrides)
  overrides = overrides or {}
  local world = {
    player = overrides.player or { main_job = "NIN", main_job_id = 13, main_job_level = 99 },
    spells = overrides.spells or {},
    abilities = overrides.abilities or { job_abilities = {} },
    tools = overrides.tools or {},
    items = overrides.items or {},
    target = overrides.target,
    gear = overrides.gear or {},
    gear_items = overrides.gear_items or {},
    gear_asked = {},
  }
  local stealth = new_stealth({
    get_player = function()
      return world.player
    end,
    get_spells = function()
      return world.spells
    end,
    get_abilities = function()
      return world.abilities
    end,
    tool_counts = function()
      return world.tools
    end,
    item_count = function(name)
      return world.items[name]
    end,
    get_target = function()
      return world.target
    end,
    find_item = function(name)
      return world.gear_items[name]
    end,
    gear_plan = function(name)
      world.gear_asked[#world.gear_asked + 1] = name
      return world.gear[name] or { type = "none", notes = { "You don't have " .. name .. "." } }
    end,
    resources = overrides.resources == nil and resources() or overrides.resources,
  })
  return stealth, world
end

-- A NIN with tools and no white magic: the ninjutsu rung of both ladders.
local function ninja(overrides)
  overrides = overrides or {}
  overrides.spells = overrides.spells or { [MONOMI] = true, [TONKO] = true }
  overrides.tools = overrides.tools or { [SANJAKU] = 99, [SHINOBI] = 99 }
  return build(overrides)
end

describe("crossbar stealth", function()
  describe("the ladder", function()
    it("takes the ninjutsu with the tools there and no spell or jig known", function()
      local stealth = ninja()
      assert.equal('input /ninjutsu "Monomi: Ichi" <me>', stealth.plan("sneak"))
      assert.equal('input /ninjutsu "Tonko: Ichi" <me>', stealth.plan("invisible"))
    end)

    it("prefers the white magic over a ninjutsu the same character knows", function()
      --[[ The order is fixed and the same on every job: the SPELL first,
           then the jig, then the ninjutsu, then the item (Kevin,
           2026-09-06, reversing the 2026-08-29 order that had the ninjutsu
           at the front and the spell last). A WHM main subbing NIN casts
           Sneak rather than throwing Monomi. ]]
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99, sub_job_id = 13, sub_job_level = 49 },
        spells = { [MONOMI] = true, [SNEAK] = true, [TONKO] = true, [INVISIBLE] = true },
        tools = { [SANJAKU] = 5, [SHINOBI] = 5 },
        abilities = { job_abilities = { JIG } },
      })
      -- Every rung of both ladders is open to this character at once,
      -- which is what makes the answer an ORDERING and not a fallback.
      assert.equal('input /magic "Sneak" <me>', stealth.plan("sneak"))
      assert.equal('input /magic "Invisible" <me>', stealth.plan("invisible"))
    end)

    it("prefers the jig over a ninjutsu the same character could throw", function()
      --[[ A DNC subbing NIN with tools: the jig CONSUMES NOTHING and the
           ninjutsu spends a tool, so the jig goes first (Kevin,
           2026-09-06). ]]
      local stealth = build({
        player = { main_job = "DNC", main_job_id = 19, main_job_level = 99, sub_job_id = 13, sub_job_level = 49 },
        spells = { [MONOMI] = true, [TONKO] = true },
        tools = { [SANJAKU] = 5, [SHINOBI] = 5 },
        abilities = { job_abilities = { JIG } },
      })
      assert.equal('input /jobability "Spectral Jig" <me>', stealth.plan("sneak"))
      assert.equal('input /jobability "Spectral Jig" <me>', stealth.plan("invisible"))
    end)

    it("prefers Tonko: Ni over Tonko: Ichi when both are known", function()
      -- Kevin, 2026-09-06. Monomi has no Ni in the game (id 319 is Aisha:
      -- Ichi), so the sneak ladder has nothing to prefer there.
      local stealth = ninja({ spells = { [MONOMI] = true, [TONKO] = true, [TONKO_NI] = true } })
      assert.equal('input /ninjutsu "Tonko: Ni" <me>', stealth.plan("invisible"))
    end)

    it("gates Monomi: Ichi on Sanjaku-Tenugui", function()
      --[[ Every ninjutsu rung wants its own tool in the bag - the press
           would otherwise be spent on the game's refusal. Monomi's is
           Sanjaku-Tenugui, Tonko's is Shinobi-Tabi, and neither stands in
           for the other. ]]
      local stealth = ninja({ tools = { [SHINOBI] = 99 } })
      assert.equal('input /item "Silent Oil" <me>', stealth.plan("sneak"), "no Sanjaku-Tenugui, no Monomi")
      assert.equal('input /ninjutsu "Tonko: Ichi" <me>', stealth.plan("invisible"), "Tonko has its own")
    end)

    it("gates both Tonko rungs on Shinobi-Tabi, Ni included", function()
      -- The two share a tool, so an empty bag drops the pair of them and
      -- the ladder carries on past both rather than stopping at Ni.
      local stealth = ninja({
        spells = { [TONKO] = true, [TONKO_NI] = true },
        tools = { [SANJAKU] = 99 },
      })
      assert.equal('input /item "Prism Powder" <me>', stealth.plan("invisible"))
    end)

    it("falls to Tonko: Ichi when the character has not learned Ni", function()
      local stealth = ninja()
      assert.equal('input /ninjutsu "Tonko: Ichi" <me>', stealth.plan("invisible"))
    end)

    it("takes the jig on a character with no white magic", function()
      local stealth = build({
        player = { main_job = "DNC", main_job_id = 19, main_job_level = 99 },
        abilities = { job_abilities = { JIG } },
      })
      assert.equal('input /jobability "Spectral Jig" <me>', stealth.plan("sneak"))
      assert.equal('input /jobability "Spectral Jig" <me>', stealth.plan("invisible"), "the jig grants both")
    end)

    it("takes the spell over both, on a character with nothing else", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99 },
        spells = { [SNEAK] = true, [INVISIBLE] = true },
      })
      assert.equal('input /magic "Sneak" <me>', stealth.plan("sneak"))
      assert.equal('input /magic "Invisible" <me>', stealth.plan("invisible"))
    end)

    it("falls to the item when the character has nothing at all", function()
      local stealth = build({ player = { main_job = "WAR", main_job_id = 1, main_job_level = 99 } })
      assert.equal('input /item "Silent Oil" <me>', stealth.plan("sneak"))
      assert.equal('input /item "Prism Powder" <me>', stealth.plan("invisible"))
    end)
  end)

  describe("what the client actually allows", function()
    it("skips a ninjutsu whose tool the bag does not hold", function()
      -- The press would be spent on the game's refusal, so the rung is not
      -- offered at all and the ladder carries on past it.
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99, sub_job_id = 13, sub_job_level = 49 },
        spells = { [MONOMI] = true, [SNEAK] = true },
        tools = {},
      })
      assert.equal('input /magic "Sneak" <me>', stealth.plan("sneak"))
    end)

    it("counts a master tool for a NIN main, as a bound slot does", function()
      local stealth = build({
        player = { main_job = "NIN", main_job_id = 13, main_job_level = 99 },
        spells = { [MONOMI] = true },
        tools = { [SHIKANOFUDA] = 1 },
      })
      assert.equal('input /ninjutsu "Monomi: Ichi" <me>', stealth.plan("sneak"))
    end)

    it("does not count a master tool for a NIN sub", function()
      -- Shikanofuda substitutes on the owning main job only - counters.lua
      -- already draws the corner that way, and the ladder must agree.
      local stealth = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 99, sub_job_id = 13, sub_job_level = 49 },
        spells = { [MONOMI] = true },
        tools = { [SHIKANOFUDA] = 99 },
      })
      assert.equal('input /item "Silent Oil" <me>', stealth.plan("sneak"))
    end)

    it("skips a spell the character has not learned", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99 },
        spells = {},
      })
      assert.equal('input /item "Silent Oil" <me>', stealth.plan("sneak"))
    end)

    it("skips a spell the current job pair is too low for", function()
      --[[ Sneak is level 20 and a subjob is half the main's, so WAR99/WHM49
           casts it while WAR30/WHM15 does not - the level gate is the
           resource's own, never a number written down here. ]]
      local low = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 30, sub_job_id = 3, sub_job_level = 15 },
        spells = { [SNEAK] = true },
      })
      assert.equal('input /item "Silent Oil" <me>', low.plan("sneak"))

      local high = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 99, sub_job_id = 3, sub_job_level = 49 },
        spells = { [SNEAK] = true },
      })
      assert.equal('input /magic "Sneak" <me>', high.plan("sneak"))
    end)

    it("skips the jig for a character who does not have it", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99 },
        spells = { [SNEAK] = true },
        abilities = { job_abilities = { 43 } },
      })
      assert.equal('input /magic "Sneak" <me>', stealth.plan("sneak"))
    end)

    it("skips the item rung when the bag is known to be empty", function()
      local stealth = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 99 },
        items = { ["Silent Oil"] = 0 },
      })
      local command, hint = stealth.plan("sneak")
      assert.is_nil(command)
      assert.is_string(hint)
    end)

    it("still sends the item when the bag cannot be read at all", function()
      -- An unreadable bag answers nil, not zero. Refusing a press that might
      -- have worked is worse than letting the game answer for itself.
      local stealth = build({ player = { main_job = "WAR", main_job_id = 1, main_job_level = 99 } })
      assert.equal('input /item "Silent Oil" <me>', stealth.plan("sneak"))
    end)
  end)

  describe("where it lands", function()
    it("sends a party member's sneak at them", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99 },
        spells = { [SNEAK] = true },
        target = { in_party = true, is_npc = false },
      })
      assert.equal('input /magic "Sneak" <t>', stealth.plan("sneak"))
    end)

    it("keeps a self-only rung on you whatever is targeted", function()
      -- Both ninjutsu and the jig are self-only in the resources, so a
      -- targeted party member cannot drag them off you.
      local stealth = ninja({ target = { in_party = true, is_npc = false } })
      assert.equal('input /ninjutsu "Monomi: Ichi" <me>', stealth.plan("sneak"))
    end)

    it("ignores a target outside the party", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99 },
        spells = { [SNEAK] = true },
        target = { in_party = false, is_npc = false },
      })
      assert.equal('input /magic "Sneak" <me>', stealth.plan("sneak"))
    end)

    it("ignores an NPC that somehow reports itself in party", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99 },
        spells = { [SNEAK] = true },
        target = { in_party = true, is_npc = true },
      })
      assert.equal('input /magic "Sneak" <me>', stealth.plan("sneak"))
    end)
  end)

  describe("what a picked rung amounts to", function()
    it("names a spell as the action a slot would bind", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99 },
        spells = { [SNEAK] = true },
      })
      local _, _, action = stealth.plan("sneak")
      assert.are.same({ type = "ma", action = "Sneak", target = "me" }, action)
    end)

    it("names the target the rung aims at", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99 },
        spells = { [SNEAK] = true },
        target = { in_party = true, is_npc = false },
      })
      local _, _, action = stealth.plan("sneak")
      assert.are.equal("t", action.target)
    end)

    it("names the jig as an ability", function()
      local stealth = build({
        player = { main_job = "DNC", main_job_id = 19, main_job_level = 99 },
        abilities = { job_abilities = { JIG } },
      })
      local _, _, action = stealth.plan("invisible")
      assert.are.same({ type = "ja", action = "Spectral Jig", target = "me" }, action)
    end)

    it("names the consumable as an item", function()
      local stealth = build()
      local _, _, action = stealth.plan("invisible")
      assert.are.same({ type = "item", action = "Prism Powder", target = "me" }, action)
    end)

    it("names nothing for a gear rung, which is a plan of its own", function()
      local stealth = build({
        items = { ["Super Reraiser"] = 0, ["Hi-Reraiser"] = 0, ["Reraiser"] = 0, ["Instant Reraise"] = 0 },
        gear = { ["Reraise Ring"] = { type = "equip" } },
        gear_items = { ["Reraise Ring"] = {} },
      })
      local plan, _, action = stealth.plan("reraise")
      assert.are.equal("table", type(plan))
      assert.is_nil(action)
    end)
  end)

  describe("degraded input", function()
    it("hints on an unknown stealth name", function()
      local stealth = build()
      local command, hint = stealth.plan("stealthy")
      assert.is_nil(command)
      assert.is_string(hint)
    end)

    it("folds case, as every verb in the framework does", function()
      local stealth = ninja()
      assert.equal('input /ninjutsu "Monomi: Ichi" <me>', stealth.plan("SNEAK"))
    end)

    it("falls through to the item with no resources library at all", function()
      -- Without resources nothing can be named or level-gated, but `/item`
      -- takes a name this module already knows.
      local stealth = build({
        resources = {},
        player = { main_job = "NIN", main_job_id = 13, main_job_level = 99 },
        spells = { [MONOMI] = true },
        tools = { [SANJAKU] = 99 },
      })
      assert.equal('input /item "Silent Oil" <me>', stealth.plan("sneak"))
    end)

    it("survives a client that answers nothing", function()
      local stealth = new_stealth({})
      local command
      assert.has_no.errors(function()
        command = stealth.plan("sneak")
      end)
      assert.equal('input /item "Silent Oil" <me>', command)
    end)
  end)
end)

describe("the reraise ladder", function()
  -- Every reraise item known to be absent, so a test reaches the gear.
  local NO_ITEMS = { ["Super Reraiser"] = 0, ["Hi-Reraiser"] = 0, ["Reraiser"] = 0, ["Instant Reraise"] = 0 }
  local ALL_RERAISE = { [RERAISE] = true, [RERAISE_II] = true, [RERAISE_III] = true, [RERAISE_IV] = true }

  local function equip_plan(name)
    return { type = "equip", name = name, command = 'input /item "' .. name .. '" <me>', warmup = true, notes = {} }
  end

  describe("the spells", function()
    it("casts the highest tier the character can use", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = WHM, main_job_level = 99, buffs = {} },
        spells = ALL_RERAISE,
      })
      assert.equal('input /magic "Reraise IV" <me>', stealth.plan("reraise"))
    end)

    it("walks down the tiers the character has learned", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = WHM, main_job_level = 99, buffs = {} },
        spells = { [RERAISE] = true, [RERAISE_II] = true },
      })
      assert.equal('input /magic "Reraise II" <me>', stealth.plan("reraise"))
    end)

    it("leaves Reraise IV to a WHM main and a subjob to the tiers its level reaches", function()
      --[[ Reraise IV's requirement sits above the cap, so it is a main-job
           gift; a WHM49 sub reaches Reraise (25) but not Reraise II (56). ]]
      local stealth = build({
        player = {
          main_job = "WAR",
          main_job_id = 1,
          main_job_level = 99,
          sub_job_id = WHM,
          sub_job_level = 49,
          buffs = {},
        },
        spells = ALL_RERAISE,
      })
      assert.equal('input /magic "Reraise" <me>', stealth.plan("reraise"))
    end)

    it("passes a job-point gift by while the main job is synced below the cap", function()
      --[[ Reraise IV is a WHM job-point gift, and gifts are off below 99:
           a WHM synced to 60 casts Reraise II rather than a Reraise IV the
           game would refuse. ]]
      local stealth = build({
        player = { main_job = "WHM", main_job_id = WHM, main_job_level = 60, buffs = {} },
        spells = ALL_RERAISE,
      })
      assert.equal('input /magic "Reraise II" <me>', stealth.plan("reraise"))
    end)

    it("keeps a reraise on you whatever is targeted", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = WHM, main_job_level = 99, buffs = {} },
        spells = { [RERAISE] = true },
        target = { in_party = true, is_npc = false },
      })
      assert.equal('input /magic "Reraise" <me>', stealth.plan("reraise"))
    end)
  end)

  describe("a scholar's Addendum: White", function()
    it("passes a SCH-only spell by while Addendum: White is down", function()
      -- SCH knows the spell and meets its level, but the game refuses the
      -- cast without the Addendum, so the ladder carries on past it.
      local stealth = build({
        player = { main_job = "SCH", main_job_id = SCH, main_job_level = 99, buffs = {} },
        spells = ALL_RERAISE,
      })
      assert.equal('input /item "Super Reraiser" <me>', stealth.plan("reraise"))
    end)

    it("casts it under Enlightenment, which opens both addenda", function()
      local stealth = build({
        player = { main_job = "SCH", main_job_id = SCH, main_job_level = 99, buffs = { ENLIGHTENMENT } },
        spells = ALL_RERAISE,
      })
      assert.equal('input /magic "Reraise III" <me>', stealth.plan("reraise"))
    end)

    it("casts it once Addendum: White is up", function()
      local stealth = build({
        player = { main_job = "SCH", main_job_id = SCH, main_job_level = 99, buffs = { ADDENDUM_WHITE } },
        spells = ALL_RERAISE,
      })
      assert.equal('input /magic "Reraise III" <me>', stealth.plan("reraise"))
    end)

    it("asks nothing of a WHM, main or sub, who carries the same spell", function()
      local whm_main = build({
        player = {
          main_job = "WHM",
          main_job_id = WHM,
          main_job_level = 99,
          sub_job_id = SCH,
          sub_job_level = 49,
          buffs = {},
        },
        spells = { [RERAISE_III] = true },
      })
      assert.equal('input /magic "Reraise III" <me>', whm_main.plan("reraise"))

      --[[ A SCH/WHM without the Addendum: Reraise III and II are SCH's
           alone at this sub level and are passed by, while Reraise comes
           through the WHM sub, which needs none. ]]
      local whm_sub = build({
        player = {
          main_job = "SCH",
          main_job_id = SCH,
          main_job_level = 99,
          sub_job_id = WHM,
          sub_job_level = 49,
          buffs = {},
        },
        spells = ALL_RERAISE,
      })
      assert.equal('input /magic "Reraise" <me>', whm_sub.plan("reraise"))
    end)

    it("leaves a spell without the Addendum bit alone", function()
      -- Sneak carries `requirements = 1`, not the Addendum bit.
      local stealth = build({
        player = { main_job = "SCH", main_job_id = SCH, main_job_level = 99, buffs = {} },
        spells = { [SNEAK] = true },
        resources = (function()
          local res = resources()
          res.spells[SNEAK].levels[SCH] = 20
          res.spells[SNEAK].requirements = 1
          return res
        end)(),
      })
      assert.equal('input /magic "Sneak" <me>', stealth.plan("sneak"))
    end)
  end)

  describe("the items", function()
    it("reaches for the items in order once no spell can go", function()
      local cases = {
        { items = {}, expect = "Super Reraiser" },
        { items = { ["Super Reraiser"] = 0 }, expect = "Hi-Reraiser" },
        { items = { ["Super Reraiser"] = 0, ["Hi-Reraiser"] = 0 }, expect = "Reraiser" },
        {
          items = { ["Super Reraiser"] = 0, ["Hi-Reraiser"] = 0, ["Reraiser"] = 0 },
          expect = "Instant Reraise",
        },
      }
      for _, case in ipairs(cases) do
        local stealth = build({
          player = { main_job = "WAR", main_job_id = 1, main_job_level = 99, buffs = {} },
          items = case.items,
        })
        assert.equal('input /item "' .. case.expect .. '" <me>', stealth.plan("reraise"))
      end
    end)

    it("prefers any spell over an item", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = WHM, main_job_level = 99, buffs = {} },
        spells = { [RERAISE] = true },
        items = { ["Super Reraiser"] = 12 },
      })
      assert.equal('input /magic "Reraise" <me>', stealth.plan("reraise"))
    end)

    it("asks nothing of the gear while an item can go", function()
      local stealth, world = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 99, buffs = {} },
        items = { ["Instant Reraise"] = 1 },
        gear = { ["Reraise Ring"] = equip_plan("Reraise Ring") },
      })
      stealth.plan("reraise")
      assert.are.same({}, world.gear_asked)
    end)
  end)

  describe("the gear", function()
    it("walks the gear ring, earring, hairpin, gorget once the items are gone", function()
      local order = { "Reraise Ring", "Reraise Earring", "Reraise Hairpin", "Reraise Gorget" }
      for index, name in ipairs(order) do
        local gear = {}
        gear[name] = equip_plan(name)
        local stealth, world = build({
          player = { main_job = "WAR", main_job_id = 1, main_job_level = 99, buffs = {} },
          items = NO_ITEMS,
          gear = gear,
        })
        local plan = stealth.plan("reraise")
        assert.equal(gear[name], plan, name .. " is the plan handed back, untouched")
        assert.are.same({ unpack(order, 1, index) }, world.gear_asked, "asked in order, stopping at " .. name)
      end
    end)

    it("passes over a piece that cannot go and takes the next", function()
      local stealth = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 99, buffs = {} },
        items = NO_ITEMS,
        gear = {
          ["Reraise Ring"] = { type = "none", notes = { "Reraise Ring: 70000 sec recast." } },
          ["Reraise Earring"] = equip_plan("Reraise Earring"),
        },
      })
      assert.equal("Reraise Earring", stealth.plan("reraise").name)
    end)

    it("passes by a piece the main job cannot wear", function()
      -- The gorget's own job mask (Windower's data): WAR RDM PLD DRK BST
      -- RNG SAM DRG BLU RUN - no THF. The set shape is read as well.
      for _, jobs in ipairs({ 4283298, { [1] = true, [5] = true } }) do
        local stealth, world = build({
          player = { main_job = "THF", main_job_id = 6, main_job_level = 99, buffs = {} },
          items = NO_ITEMS,
          gear = { ["Reraise Gorget"] = equip_plan("Reraise Gorget") },
          gear_items = { ["Reraise Gorget"] = { en = "Reraise Gorget", jobs = jobs, level = 56 } },
        })
        local plan, hint = stealth.plan("reraise")
        assert.is_nil(plan)
        assert.equal("no way to reraise right now", hint)
        assert.are.same({ "Reraise Ring", "Reraise Earring", "Reraise Hairpin" }, world.gear_asked)
      end
    end)

    it("passes by a piece above the main job's level", function()
      local stealth = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 50, buffs = {} },
        items = NO_ITEMS,
        gear = {
          ["Reraise Hairpin"] = equip_plan("Reraise Hairpin"),
          ["Reraise Gorget"] = equip_plan("Reraise Gorget"),
        },
        gear_items = {
          ["Reraise Hairpin"] = { en = "Reraise Hairpin", jobs = 8388606, level = 60 },
          ["Reraise Gorget"] = { en = "Reraise Gorget", jobs = 4283298, level = 50 },
        },
      })
      assert.equal("Reraise Gorget", stealth.plan("reraise").name)
    end)

    it("reads a job list as no answer rather than as a set", function()
      -- `{ 1, 5 }` read as a set would refuse the WAR it names.
      local stealth = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 99, buffs = {} },
        items = NO_ITEMS,
        gear = { ["Reraise Ring"] = equip_plan("Reraise Ring") },
        gear_items = { ["Reraise Ring"] = { en = "Reraise Ring", jobs = { 1, 5 } } },
      })
      assert.equal("Reraise Ring", stealth.plan("reraise").name)
    end)

    it("takes a piece whose jobs and level the resources do not give", function()
      -- A fact that cannot be read allows the press.
      local stealth = build({
        player = { main_job = "THF", main_job_id = 6, main_job_level = 1, buffs = {} },
        items = NO_ITEMS,
        gear = { ["Reraise Earring"] = equip_plan("Reraise Earring") },
        gear_items = { ["Reraise Earring"] = { en = "Reraise Earring" } },
      })
      assert.equal("Reraise Earring", stealth.plan("reraise").name)
    end)

    it("answers the bare hint when nothing at all can go", function()
      local stealth = build({
        player = { main_job = "WAR", main_job_id = 1, main_job_level = 99, buffs = {} },
        items = NO_ITEMS,
      })
      local plan, hint = stealth.plan("reraise")
      assert.is_nil(plan)
      assert.equal("no way to reraise right now", hint)
    end)

    it("skips the gear rungs where no gear planner was given", function()
      local stealth = new_stealth({
        item_count = function()
          return 0
        end,
      })
      local plan, hint = stealth.plan("reraise")
      assert.is_nil(plan)
      assert.equal("no way to reraise right now", hint)
    end)
  end)

  describe("a spell the game would refuse right now", function()
    local function whm(buffs)
      return { main_job = "WHM", main_job_id = WHM, main_job_level = 99, buffs = buffs }
    end

    it("reaches for an item while silenced or muted", function()
      for _, buff in ipairs({ SILENCE, MUTE }) do
        local stealth = build({
          player = whm({ buff }),
          spells = ALL_RERAISE,
          items = { ["Super Reraiser"] = 0, ["Hi-Reraiser"] = 3 },
        })
        assert.equal('input /item "Hi-Reraiser" <me>', stealth.plan("reraise"), "buff " .. buff)
      end
    end)

    it("leaves MP to the game", function()
      -- Penury and Light Arts cut the cost, so a gate on the base cost would
      -- spend an item where the spell would have gone (Kevin, 2026-10-09).
      local player = whm({})
      player.vitals = { mp = 10 }
      local stealth = build({ player = player, spells = { [RERAISE] = true } })
      assert.equal('input /magic "Reraise" <me>', stealth.plan("reraise"))
    end)

    it("passes the stealth spells and ninjutsu by while silenced, but not the jig", function()
      local silenced = {
        main_job = "WHM",
        main_job_id = WHM,
        main_job_level = 99,
        sub_job_id = 13,
        sub_job_level = 49,
        buffs = { SILENCE },
      }
      local stealth = build({
        player = silenced,
        spells = { [SNEAK] = true, [MONOMI] = true },
        tools = { [SANJAKU] = 5 },
      })
      assert.equal('input /item "Silent Oil" <me>', stealth.plan("sneak"))

      local dancer = build({
        player = { main_job = "DNC", main_job_id = 19, main_job_level = 99, buffs = { SILENCE } },
        abilities = { job_abilities = { JIG } },
      })
      assert.equal('input /jobability "Spectral Jig" <me>', dancer.plan("sneak"), "a jig is no spell")
    end)
  end)

  describe("a reraise already on", function()
    it("refuses the press with a hint and walks no rung", function()
      local stealth, world = build({
        player = { main_job = "WHM", main_job_id = WHM, main_job_level = 99, buffs = { RERAISE_BUFF } },
        spells = ALL_RERAISE,
        items = NO_ITEMS,
      })
      local plan, hint = stealth.plan("reraise")
      assert.is_nil(plan)
      assert.equal("Reraise is already active", hint)
      assert.are.same({}, world.gear_asked)
    end)

    it("leaves sneak and invisible alone under it", function()
      local stealth = build({
        player = { main_job = "WHM", main_job_id = WHM, main_job_level = 99, buffs = { RERAISE_BUFF } },
        spells = { [SNEAK] = true },
      })
      assert.equal('input /magic "Sneak" <me>', stealth.plan("sneak"))
    end)
  end)

  it("folds case", function()
    local stealth = build({
      player = { main_job = "WHM", main_job_id = WHM, main_job_level = 99, buffs = {} },
      spells = { [RERAISE] = true },
    })
    assert.equal('input /magic "Reraise" <me>', stealth.plan("RERAISE"))
  end)

  it("survives a client that answers nothing", function()
    local stealth = new_stealth({})
    local command
    assert.has_no.errors(function()
      command = stealth.plan("reraise")
    end)
    assert.equal('input /item "Super Reraiser" <me>', command)
  end)
end)
