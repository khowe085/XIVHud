local new_stealth = require("components/crossbar/stealth")

local SNEAK, INVISIBLE = 137, 136
local MONOMI, TONKO = 318, 353
local JIG = 196
local SANJAKU, SHINOBI, SHIKANOFUDA = 2553, 1194, 2972

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
    resources = overrides.resources == nil and resources() or overrides.resources,
  })
  return stealth, world
end

-- A NIN with tools: the top rung of both ladders.
local function ninja(overrides)
  overrides = overrides or {}
  overrides.spells = { [MONOMI] = true, [TONKO] = true }
  overrides.tools = { [SANJAKU] = 99, [SHINOBI] = 99 }
  return build(overrides)
end

describe("crossbar stealth", function()
  describe("the ladder", function()
    it("takes the ninjutsu first when the tools are there", function()
      local stealth = ninja()
      assert.equal('input /ninjutsu "Monomi: Ichi" <me>', stealth.plan("sneak"))
      assert.equal('input /ninjutsu "Tonko: Ichi" <me>', stealth.plan("invisible"))
    end)

    it("prefers the ninjutsu over a spell the same character knows", function()
      --[[ The order is fixed and the same on every job (Kevin, 2026-08-29):
           a WHM main subbing NIN still throws the ninjutsu, because it is
           free and instant. What the MAIN job offers does not win. ]]
      local stealth = build({
        player = { main_job = "WHM", main_job_id = 3, main_job_level = 99, sub_job_id = 13, sub_job_level = 49 },
        spells = { [MONOMI] = true, [SNEAK] = true },
        tools = { [SANJAKU] = 5 },
        abilities = { job_abilities = { JIG } },
      })
      -- Every rung of the sneak ladder is open to this character at once,
      -- which is what makes the answer an ORDERING and not a fallback.
      assert.equal('input /ninjutsu "Monomi: Ichi" <me>', stealth.plan("sneak"))
    end)

    it("falls to the jig when no ninjutsu is available", function()
      local stealth = build({
        player = { main_job = "DNC", main_job_id = 19, main_job_level = 99 },
        abilities = { job_abilities = { JIG } },
      })
      assert.equal('input /jobability "Spectral Jig" <me>', stealth.plan("sneak"))
      assert.equal('input /jobability "Spectral Jig" <me>', stealth.plan("invisible"), "the jig grants both")
    end)

    it("falls to the spell when there is no ninjutsu and no jig", function()
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
