local new_skillchain = require("components/crossbar/skillchain")

describe("crossbar skillchain", function()
  local env, sc

  before_each(function()
    env = { now = 100, target = { id = 500, hpp = 75 }, player = { id = 42 } }
    sc = new_skillchain({
      now = function()
        return env.now
      end,
      get_mob_by_target = function()
        return env.target
      end,
      get_player = function()
        return env.player
      end,
    })
  end)

  -- A raw windower.packets.parse_action shape: one target, one action - the
  -- only parts the engine reads. Category 3 is weaponskill_finish; the
  -- top-level param carries the action id, the per-action param the payload
  -- ids (chainbound level, gained buff).
  local function act(opts)
    return {
      category = opts.category or 3,
      param = opts.id,
      actor_id = opts.actor or 42,
      targets = {
        {
          id = opts.target or 500,
          actions = {
            {
              message = opts.message or 185,
              param = opts.action_param,
              has_add_effect = opts.chain ~= nil,
              add_effect_animation = opts.chain,
              add_effect_message = opts.chain ~= nil and 288 or nil,
            },
          },
        },
      },
    }
  end

  describe("properties", function()
    it("answers single-, double- and triple-property weapon skills", function()
      assert.same({ "Impaction" }, sc.properties(1, "weapon_skills"))
      assert.same({ "Transfixion", "Impaction" }, sc.properties(7, "weapon_skills"))
      assert.same({ "Induration", "Detonation", "Impaction" }, sc.properties(13, "weapon_skills"))
    end)

    it("answers the plain list for an aeonic weapon skill - aeonic is dead upstream", function()
      -- Shijin Spiral carries aeonic data in the table; the property list it
      -- answers is the ordinary one.
      assert.same({ "Fusion", "Reverberation" }, sc.properties(15, "weapon_skills"))
    end)

    it("reaches the spell, job-ability and monster-ability tables", function()
      assert.same({ "Liquefaction" }, sc.properties(144, "spells"))
      assert.same({ "Transfixion" }, sc.properties(513, "job_abilities"))
    end)

    it("answers nil for an unknown id or resource, never a crash", function()
      assert.is_nil(sc.properties(999999, "weapon_skills"))
      assert.is_nil(sc.properties(1, "no_such_table"))
      assert.is_nil(sc.properties(nil, "weapon_skills"))
    end)
  end)

  describe("the window machine", function()
    it("opens a resonation from a weapon-skill finish: waiting, then open, then gone", function()
      -- Dragon Kick (Fragmentation), damage message 185, no add effect.
      sc.on_action(act({ id = 8 }))
      -- Waiting: the full 3s delay, window = delay + 8 - step.
      local delay, window = sc.window()
      assert.are.equal(3, delay)
      assert.are.equal(10, window)
      -- Open.
      env.now = 104
      delay, window = sc.window()
      assert.are.equal(0, delay)
      assert.are.equal(6, window)
      -- Expired.
      env.now = 110
      delay, window = sc.window()
      assert.are.same({ 0, 0 }, { delay, window })
    end)

    it("answers 0,0 with no target, a dead target, or a target with no chain", function()
      sc.on_action(act({ id = 8 }))
      env.now = 104
      env.target = nil
      assert.are.same({ 0, 0 }, { sc.window() })
      env.target = { id = 500, hpp = 0 }
      assert.are.same({ 0, 0 }, { sc.window() })
      env.target = { id = 777, hpp = 50 }
      assert.are.same({ 0, 0 }, { sc.window() })
    end)

    it("tracks resonations per target id", function()
      sc.on_action(act({ id = 8, target = 500 })) -- Fragmentation on 500
      sc.on_action(act({ id = 1, target = 600 })) -- Impaction on 600
      env.now = 104
      -- Against 500's Fragmentation, Pyrrhic Kleos forms Distortion.
      assert.are.equal("Distortion", sc.result(29, "weapon_skills"))
      -- Against 600's Impaction it forms nothing; Cyclone (Detonation,
      -- Impaction) continues to Detonation.
      env.target = { id = 600, hpp = 50 }
      assert.is_nil(sc.result(29, "weapon_skills"))
      assert.are.equal("Detonation", sc.result(20, "weapon_skills"))
    end)
  end)

  describe("chain results", function()
    before_each(function()
      -- Dragon Kick opens Fragmentation on the default target.
      sc.on_action(act({ id = 8 }))
    end)

    it("answers nothing while the resonation is still waiting", function()
      assert.is_nil(sc.result(29, "weapon_skills"))
    end)

    it("answers the property a weapon skill would form once the window opens", function()
      env.now = 104
      -- Pyrrhic Kleos (Distortion, Scission): Fragmentation x Distortion -> Distortion.
      assert.are.equal("Distortion", sc.result(29, "weapon_skills"))
      -- Combo (Impaction) forms nothing out of Fragmentation.
      assert.is_nil(sc.result(1, "weapon_skills"))
    end)

    it("answers job abilities out of the job_abilities table", function()
      env.now = 104
      -- Neither Chaotic Strike (Fragmentation, Transfixion) nor Eclipse Bite
      -- (Gravitation, Scission) continues Fragmentation.
      assert.is_nil(sc.result(630, "job_abilities"))
      assert.is_nil(sc.result(534, "job_abilities"))
      -- Tornado Kick opens Induration/Detonation/Impaction on a fresh target;
      -- Head Butt (Detonation) continues the Impaction leg to Detonation.
      env.target = { id = 800, hpp = 50 }
      sc.on_action(act({ id = 13, target = 800 }))
      env.now = 108
      assert.are.equal("Detonation", sc.result(675, "job_abilities"))
    end)

    it("keeps the dead aeonic dead: Light after Light answers Light, not Radiance", function()
      env.now = 104
      env.target = { id = 700, hpp = 50 }
      -- Final Heaven (Light, Fusion) opens on a fresh target...
      sc.on_action(act({ id = 10, target = 700 }))
      env.now = 108
      -- ...then Victory Smite (Light, Fragmentation): Light x Light -> Light
      -- (the {4,'Light','Radiance'} combo's aeonic third is never chosen).
      assert.are.equal("Light", sc.result(14, "weapon_skills"))
    end)

    it("answers nothing on no target, a dead target, an unknown action, or after expiry", function()
      env.now = 104
      assert.is_nil(sc.result(999999, "weapon_skills"))
      assert.is_nil(sc.result(29, "nonsense"))
      env.target = nil
      assert.is_nil(sc.result(29, "weapon_skills"))
      env.target = { id = 500, hpp = 0 }
      assert.is_nil(sc.result(29, "weapon_skills"))
      env.target = { id = 500, hpp = 75 }
      env.now = 111
      assert.is_nil(sc.result(29, "weapon_skills"))
    end)
  end)

  describe("chain continuation (the add effect)", function()
    before_each(function()
      -- Dragon Kick opens Fragmentation.
      sc.on_action(act({ id = 8 }))
      env.now = 104
    end)

    it("moves the resonation onto the formed property and steps the window", function()
      -- Pyrrhic Kleos lands carrying the Distortion add effect (animation 5).
      sc.on_action(act({ id = 29, chain = 5 }))
      local delay, window = sc.window()
      assert.are.equal(3, delay)
      assert.are.equal(9, window, "step 2: delay + 8 - 2")
      env.now = 108
      -- Against Distortion, Mandalic Stab (Fusion, Compression) forms Fusion.
      assert.are.equal("Fusion", sc.result(27, "weapon_skills"))
    end)

    it("steps even when the chain's own opener was never seen", function()
      env.target = { id = 900, hpp = 50 }
      sc.on_action(act({ id = 29, chain = 5, target = 900 }))
      local delay, window = sc.window()
      assert.are.same({ 3, 9 }, { delay, window })
    end)

    it("closes the resonation after the fifth chain", function()
      -- Chains 1-4 (steps 2-5) stay open; the fifth (step 6) closes.
      for _ = 1, 4 do
        sc.on_action(act({ id = 29, chain = 5 }))
      end
      assert.is_true(select(2, sc.window()) > 0, "step 5 is still open")
      sc.on_action(act({ id = 29, chain = 5 }))
      assert.are.same({ 0, 0 }, { sc.window() })
      assert.is_nil(sc.result(29, "weapon_skills"))
    end)

    it("answers no result from a closed resonation even inside its window", function()
      env.target = { id = 900, hpp = 50 }
      -- Final Heaven, then the Light add effect off Victory Smite: level 4,
      -- closed at step 2 with times = 108 + 3 + 8 - 2 = 117.
      sc.on_action(act({ id = 10, target = 900 }))
      env.now = 108
      sc.on_action(act({ id = 14, chain = 1, target = 900 }))
      -- Past the delay (111), inside what would be the window: the closed
      -- gate alone stands between this and a phantom Light result.
      env.now = 113
      assert.is_nil(sc.result(14, "weapon_skills"))
    end)

    it("closes a chain that reaches level 4", function()
      env.target = { id = 900, hpp = 50 }
      -- Final Heaven opens Light/Fusion; Victory Smite lands the Light add
      -- effect: Light x Light re-checks to level 4 and closes at step 2.
      sc.on_action(act({ id = 10, target = 900 }))
      env.now = 108
      sc.on_action(act({ id = 14, chain = 1, target = 900 }))
      assert.are.same({ 0, 0 }, { sc.window() })
      assert.is_nil(sc.result(14, "weapon_skills"))
    end)
  end)

  describe("the long-list threshold", function()
    it("does not break off a three-property opener at the same level", function()
      -- Spinning Axe opens {Liquefaction, Scission, Impaction} - three
      -- properties, one short of the chainbound lists the break rule is
      -- for. Spinning Attack is {Liquefaction, Impaction}: Liquefaction's
      -- Impaction combo answers Fusion. Were the threshold `> 2`, the
      -- same-level miss on Liquefaction would break that walk off and
      -- Scission's Liquefaction combo would answer Liquefaction instead.
      sc.on_action(act({ id = 68 }))
      env.now = 104
      assert.are.equal("Fusion", sc.result(6, "weapon_skills"))
    end)
  end)

  describe("the purge", function()
    it("drops a lapsed resonation so the next chain starts over", function()
      -- Chain the mob to step 3, then let it lapse past times + grace. A
      -- fresh chain on the SAME mob id must start a new resonation at
      -- step 2 (window 9), not resume the dead one at step 4 (window 7).
      sc.on_action(act({ id = 8 })) -- opener, step 1
      env.now = 104
      sc.on_action(act({ id = 29, chain = 5 })) -- step 2
      env.now = 108
      sc.on_action(act({ id = 29, chain = 5 })) -- step 3, times = 116
      assert.are.equal(8, select(2, sc.window()), "step 3 while it lives")
      -- Past times + the 10s grace; the tick's own window() call is what
      -- runs the purge.
      env.now = 127
      assert.are.same({ 0, 0 }, { sc.window() })
      sc.on_action(act({ id = 29, chain = 5 }))
      local delay, window = sc.window()
      assert.are.equal(3, delay)
      assert.are.equal(9, window, "a purged mob chains from step 2, not step 4")
    end)
  end)

  describe("chainbound (message 529)", function()
    it("opens the bound level's property list on a 2s delay", function()
      sc.on_action(act({ id = 33, message = 529, action_param = 1 }))
      local delay, window = sc.window()
      assert.are.equal(2, delay)
      assert.are.equal(9, window)
      env.now = 103
      -- Backhand Blow (Detonation) continues Compression, the list's first.
      assert.are.equal("Detonation", sc.result(4, "weapon_skills"))
      -- Combo (Impaction): Compression and its level peers break off (the
      -- long-list rule), Liquefaction's Impaction combo answers Fusion.
      assert.are.equal("Fusion", sc.result(1, "weapon_skills"))
    end)

    it("ignores a chainbound level it does not know", function()
      sc.on_action(act({ id = 33, message = 529, action_param = 9 }))
      assert.are.same({ 0, 0 }, { sc.window() })
    end)

    it("walks the long list with the level-break rule", function()
      sc.on_action(act({ id = 33, message = 529, action_param = 1 }))
      env.now = 103
      -- Aeolian Edge (Scission, Detonation, Impaction): Compression DOES
      -- offer Detonation, but on a long list a same-level miss on Scission
      -- ends Compression's walk first, so Liquefaction's Scission combo
      -- answers. Without the break rule this reads Detonation.
      assert.are.equal("Scission", sc.result(30, "weapon_skills"))
    end)
  end)

  describe("the finish categories", function()
    it("opens from every ability-flavoured category out of job_abilities", function()
      -- job_ability (6), avatar_tp_finish (13, the blood pacts) and
      -- job_ability_unblinkable (14) all index the job_abilities table:
      -- Eclipse Bite (534) opens Gravitation/Scission from each.
      for i, category in ipairs({ 6, 13, 14 }) do
        env.now = 100
        env.target = { id = 1000 + i, hpp = 50 }
        sc.on_action(act({ category = category, id = 534, message = 317, target = 1000 + i }))
        assert.are.same({ 3, 10 }, { sc.window() }, "category " .. category)
        env.now = 104
        -- Gravitation x Pyrrhic Kleos (Distortion, Scission) -> Darkness.
        assert.are.equal("Darkness", sc.result(29, "weapon_skills"), "category " .. category)
      end
    end)

    it("opens a mob TP move out of monster_abilities", function()
      sc.on_action(act({ category = 11, id = 940, message = 185 }))
      assert.are.same({ 3, 10 }, { sc.window() })
      env.now = 104
      -- Rampage's Scission x Gust Slash (Detonation) -> Detonation.
      assert.are.equal("Detonation", sc.result(19, "weapon_skills"))
    end)
  end)

  describe("the chain-opening buffs", function()
    local function gain(buff_id)
      -- A job-ability finish (category 6) whose message 100 grants the buff.
      sc.on_action(act({ category = 6, id = 317, message = 100, action_param = buff_id }))
    end

    local function cast(spell_id)
      -- A plain spell finish: message 2, no add effect.
      sc.on_action(act({ category = 4, id = spell_id or 144, message = 2 }))
    end

    it("opens a chain from a plain spell finish under Immanence, consumed by it", function()
      gain(470)
      cast()
      local delay, window = sc.window()
      assert.are.same({ 3, 10 }, { delay, window })
      env.now = 104
      cast(149)
      -- Consumed: the second cast must NOT have reopened the delay.
      delay = sc.window()
      assert.are.equal(0, delay)
    end)

    it("keeps Azure Lore across casts until it expires", function()
      gain(163)
      cast()
      env.now = 108
      cast(149)
      local delay = sc.window()
      assert.are.equal(3, delay, "the second cast reopened: 163 is not consumed")
      env.now = 141
      cast()
      assert.are.same({ 0, 0 }, { sc.window() }, "the 40s buff expired")
    end)

    it("consumes Chain Affinity like Immanence", function()
      gain(164)
      cast()
      env.now = 104
      cast(149)
      assert.are.equal(0, sc.window())
    end)

    it("pins Immanence at 60 seconds", function()
      gain(470)
      env.now = 159
      cast()
      assert.are.equal(3, (sc.window()), "alive at 59s")
      gain(470)
      env.now = 220
      cast()
      assert.are.same({ 0, 0 }, { sc.window() }, "dead at 61s")
    end)

    it("pins Chain Affinity at 30 seconds", function()
      gain(164)
      env.now = 129
      cast()
      assert.are.equal(3, (sc.window()), "alive at 29s")
      gain(164)
      env.now = 160
      cast()
      assert.are.same({ 0, 0 }, { sc.window() }, "dead at 31s")
    end)

    it("prunes a dead Chain Affinity so Immanence can be found", function()
      gain(164)
      env.now = 131
      gain(470)
      cast()
      -- The dead 164 still shadows this one cast - but checking it pruned
      -- it (transcribed behaviour: check_buff drops what it finds spent).
      assert.are.same({ 0, 0 }, { sc.window() })
      cast()
      assert.are.equal(3, (sc.window()), "the prune let Immanence through")
    end)

    it("opens nothing from a plain cast with no chain buff up", function()
      cast()
      assert.are.same({ 0, 0 }, { sc.window() })
    end)
  end)

  describe("buff maintenance chunks", function()
    local function u16le(v)
      return string.char(v % 256, math.floor(v / 256) % 256)
    end

    local function u32le(v)
      return u16le(v % 65536) .. u16le(math.floor(v / 65536))
    end

    -- 0x29 action message: actor at 5, target id at 9, param at 13,
    -- message id at 25. 206 is "wears off".
    local function wear_off(target_id, buff_id, message)
      return "HDRX" .. u32le(1) .. u32le(target_id) .. u32le(buff_id) .. string.rep("\0", 8) .. u16le(message or 206)
    end

    -- 0x63 subtype 9: the full buff list, 32 u16 ids from offset 9.
    local function buff_refresh(subtype, buff_ids)
      local body = "HDRX" .. string.char(subtype) .. "\0\0\0"
      for n = 1, 32 do
        body = body .. u16le(buff_ids[n] or 0)
      end
      return body
    end

    local function gain(buff_id)
      sc.on_action(act({ category = 6, id = 317, message = 100, action_param = buff_id }))
    end

    local function cast()
      sc.on_action(act({ category = 4, id = 144, message = 2 }))
    end

    it("drops a chain buff the client says wore off", function()
      gain(470)
      sc.on_chunk(0x29, wear_off(42, 470))
      cast()
      assert.are.same({ 0, 0 }, { sc.window() })
    end)

    it("ignores wear-offs aimed at someone else or saying something else", function()
      gain(470)
      sc.on_chunk(0x29, wear_off(77, 470))
      sc.on_chunk(0x29, wear_off(42, 470, 205))
      cast()
      assert.are.equal(3, (sc.window()))
    end)

    it("rebuilds the buff set from a subtype-9 refresh", function()
      sc.on_chunk(0x63, buff_refresh(9, { 470 }))
      cast()
      assert.are.equal(3, (sc.window()))
    end)

    it("a refresh without the buff clears it; other subtypes change nothing", function()
      gain(470)
      sc.on_chunk(0x63, buff_refresh(9, {}))
      cast()
      assert.are.same({ 0, 0 }, { sc.window() })
      sc.on_chunk(0x63, buff_refresh(5, { 470 }))
      cast()
      assert.are.same({ 0, 0 }, { sc.window() })
    end)

    it("ignores a short subtype-9 refresh outright", function()
      gain(470)
      -- 40 bytes: the subtype says buff list, the length can't hold one.
      sc.on_chunk(0x63, "HDRX" .. string.char(9) .. string.rep("\0", 35))
      cast()
      -- Ignored means the buff survived - and nothing threw on the way.
      assert.are.equal(3, (sc.window()))
    end)

    it("clears every resonation on the zone-out chunk", function()
      sc.on_action(act({ id = 8 }))
      env.now = 104
      sc.on_chunk(0x0B, "HDRX")
      assert.are.same({ 0, 0 }, { sc.window() })
    end)

    it("survives short data, wrong types and a missing player", function()
      sc.on_chunk(0x29, "x")
      sc.on_chunk(0x63, "ab")
      sc.on_chunk(0x29, nil)
      env.player = nil
      sc.on_chunk(0x29, wear_off(42, 470))
      sc.on_chunk(0x63, buff_refresh(9, { 470 }))
      assert.are.same({ 0, 0 }, { sc.window() })
    end)
  end)

  describe("the indicator plan", function()
    -- The drawn geometry, anchor-relative (origin = the open-state bg's
    -- top-left, the 604x14 footprint the render module reports): waiting is
    -- the thin bar growing OUT of the centre as the delay burns down, open
    -- the thick bar shrinking back INTO it, both centre-anchored.
    it("answers nothing while nothing is open", function()
      assert.is_nil(sc.indicator_plan(0, 0))
      assert.is_nil(sc.indicator_plan(nil, nil))
    end)

    it("plans the waiting bar: thin, growing from the centre", function()
      local plan = sc.indicator_plan(1.5, 9)
      assert.are.equal("waiting", plan.state)
      assert.are.same({ x = 152, y = 5, width = 300, height = 4 }, plan.fill)
      assert.are.same({ x = 150, y = 3, width = 304, height = 8 }, plan.bg)
    end)

    it("starts the waiting bar at nothing, ends it full", function()
      local plan = sc.indicator_plan(3, 9)
      assert.are.same({ x = 302, y = 5, width = 0, height = 4 }, plan.fill)
      plan = sc.indicator_plan(0.0001, 9)
      assert.are.equal(600, plan.fill.width)
      assert.are.equal(2, plan.fill.x)
    end)

    it("never draws a negative width on a delay past 3s (the helix spells)", function()
      local plan = sc.indicator_plan(5, 12)
      assert.are.same({ x = 302, y = 5, width = 0, height = 4 }, plan.fill)
      assert.are.same({ x = 300, y = 3, width = 4, height = 8 }, plan.bg)
    end)

    it("plans the open bar: thick, shrinking into the centre", function()
      local plan = sc.indicator_plan(0, 3.5)
      assert.are.equal("open", plan.state)
      assert.are.same({ x = 152, y = 2, width = 300, height = 10 }, plan.fill)
      assert.are.same({ x = 150, y = 0, width = 304, height = 14 }, plan.bg)
      plan = sc.indicator_plan(0, 7)
      assert.are.same({ x = 2, y = 2, width = 600, height = 10 }, plan.fill)
      assert.are.same({ x = 0, y = 0, width = 604, height = 14 }, plan.bg)
    end)
  end)

  describe("reset", function()
    it("drops resonations and buffs together", function()
      sc.on_action(act({ category = 6, id = 317, message = 100, action_param = 163 }))
      sc.on_action(act({ id = 8 }))
      sc.reset()
      assert.are.same({ 0, 0 }, { sc.window() })
      sc.on_action(act({ category = 4, id = 144, message = 2 }))
      assert.are.same({ 0, 0 }, { sc.window() }, "the chain buff went with the reset")
    end)
  end)

  describe("guards", function()
    it("ignores garbage and non-chain packets without crashing", function()
      sc.on_action(nil)
      sc.on_action({})
      sc.on_action(act({ id = 0 }))
      sc.on_action(act({ id = 8, category = 1 }))
      sc.on_action({ category = 3, param = 8, targets = {} })
      sc.on_action({ category = 3, param = 8, targets = { { id = 500 } } })
      assert.are.same({ 0, 0 }, { sc.window() })
    end)

    it("runs without any deps at all", function()
      local bare = new_skillchain({})
      bare.on_action(act({ id = 8 }))
      assert.are.same({ 0, 0 }, { bare.window() })
      assert.is_nil(bare.result(8, "weapon_skills"))
      assert.same({ "Fragmentation" }, bare.properties(8, "weapon_skills"))
    end)
  end)
end)
