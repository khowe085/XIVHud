local new_logic = require("components/targetbar/logic")
local build_defaults = require("components/targetbar/defaults")

-- What res.spells / res.monster_abilities / res.weapon_skills look like to the
-- cast tracker: entries keyed by id, with an English name, and cast_time in
-- seconds on spells.
local FAKE_RESOURCES = {
  spells = {
    [144] = { en = "Fire IV", cast_time = 8 },
    [1] = { en = "Cure", cast_time = 2 },
  },
  monster_abilities = {
    [672] = { en = "Blood Drain" },
  },
  weapon_skills = {
    [32] = { en = "Fast Blade" },
  },
}

-- A parsed 0x028 the way windower.packets.parse_action shapes it: category
-- and param at the root, the per-target ids one level down.
local function action(fields)
  local act = {
    actor_id = 100,
    category = 8,
    param = 0,
    targets = { { id = 1, actions = { { param = 144, message = 327 } } } },
  }
  for key, value in pairs(fields or {}) do
    act[key] = value
  end
  return act
end

-- A plain monster: not a PC, not in the party, nobody's claim.
local function mob(fields)
  local target = {
    id = 100,
    name = "Greater Colibri",
    hpp = 100,
    claim_id = 0,
    in_party = false,
    is_npc = true,
    distance = 144,
    model_size = 1.0,
  }
  for key, value in pairs(fields or {}) do
    target[key] = value
  end
  return target
end

describe("targetbar logic", function()
  local logic, config

  before_each(function()
    config = build_defaults(1920, 1080)
    logic = new_logic(config)
  end)

  describe("occupancy", function()
    it("is unoccupied before a target arrives", function()
      assert.is_false(logic.occupied())
    end)

    it("is occupied once a target is set", function()
      logic.set_target(mob())
      assert.is_true(logic.occupied())
    end)

    it("is unoccupied again once the target is cleared", function()
      logic.set_target(mob())
      logic.clear_target()
      assert.is_false(logic.occupied())
    end)

    it("treats a nil mob as no target", function()
      logic.set_target(nil)
      assert.is_false(logic.occupied())
    end)

    it("treats a mob with a non-numeric hpp as no target", function()
      logic.set_target(mob({ hpp = "unknown" }))
      assert.is_false(logic.occupied())
    end)

    it("is occupied in preview even with nothing targeted", function()
      logic.set_preview(true)
      assert.is_true(logic.occupied())
    end)
  end)

  describe("hp banding", function()
    -- partylist's thresholds, strictly less than.
    local cases = {
      { 0, "red" },
      { 24, "red" },
      { 25, "orange" },
      { 49, "orange" },
      { 50, "yellow" },
      { 74, "yellow" },
      { 75, "normal" },
      { 100, "normal" },
    }

    for _, case in ipairs(cases) do
      local hpp, band = case[1], case[2]
      it(("bands %d%% as %s"):format(hpp, band), function()
        assert.are.equal(band, logic.band_for(hpp))
      end)
    end
  end)

  describe("text segments", function()
    it("reports the hp percent, the distance and the name", function()
      logic.set_target(mob({ hpp = 63, distance = 144, name = "Colibri" }))
      local texts = logic.texts()
      assert.are.equal("63%", texts.hp.text)
      -- distance is squared in the mob table.
      assert.are.equal("12.00", texts.distance.text)
      assert.are.equal("Colibri", texts.name.text)
    end)

    it("keeps names with spaces intact", function()
      logic.set_target(mob({ name = "Ruby Quadav" }))
      assert.are.equal("Ruby Quadav", logic.texts().name.text)
    end)

    it("truncates a name past the configured cap", function()
      config.name_max_chars = 8
      logic.set_config(config)
      logic.set_target(mob({ name = "Bugbear Strongman" }))
      assert.are.equal("Bugbear ", logic.texts().name.text)
    end)

    -- A mob the client has not named yet: the name read must not throw on
    -- the per-frame path.
    it("tolerates a mob with no name at all", function()
      local target = mob({ hpp = 50 })
      target.name = nil
      logic.set_target(target)
      assert.are.equal("", logic.texts().name.text)
    end)

    it("tolerates an empty name", function()
      logic.set_target(mob({ name = "" }))
      assert.are.equal("", logic.texts().name.text)
    end)

    it("formats the extremes of the hp range", function()
      logic.set_target(mob({ hpp = 0 }))
      assert.are.equal("0%", logic.texts().hp.text)
      logic.set_target(mob({ hpp = 100 }))
      assert.are.equal("100%", logic.texts().hp.text)
    end)

    it("clamps the distance to the width its reserve was sized for", function()
      -- 400^2 away: past two digits, and long out of range in every mode.
      logic.set_target(mob({ distance = 160000 }))
      assert.are.equal("99.99", logic.texts().distance.text)
    end)

    it("reads no distance as zero rather than crashing", function()
      local target = mob()
      target.distance = nil
      logic.set_target(target)
      assert.are.equal("0.00", logic.texts().distance.text)
    end)

    -- Literal values, not config round-trips: comparing against config.bands
    -- would stay green however wrongly the defaults were transcribed.
    it("colors the hp number by its band and leaves the name alone", function()
      logic.set_target(mob({ hpp = 20 }))
      local texts = logic.texts()
      assert.are.same({ a = 255, r = 252, g = 129, b = 130 }, texts.hp.color)
      assert.are.same({ a = 255, r = 240, g = 255, b = 255 }, texts.name.color)
    end)

    it("carries partylist's exact band palette", function()
      logic.set_target(mob({ hpp = 30 }))
      assert.are.same({ a = 255, r = 248, g = 186, b = 128 }, logic.texts().hp.color)
      logic.set_target(mob({ hpp = 60 }))
      assert.are.same({ a = 255, r = 243, g = 243, b = 124 }, logic.texts().hp.color)
    end)

    it("falls back to the text colour above the top band", function()
      logic.set_target(mob({ hpp = 90 }))
      assert.are.same(config.text_color, logic.texts().hp.color)
    end)

    it("blanks every segment with nothing targeted", function()
      local texts = logic.texts()
      assert.are.equal("", texts.hp.text)
      assert.are.equal("", texts.distance.text)
      assert.are.equal("", texts.name.text)
    end)
  end)

  describe("the eased fill", function()
    -- The fill region is 486px wide inside the 512px frame, so a percentage
    -- lands on 486, never 512.
    local FULL = 486

    local function settle()
      local plan
      for _ = 1, 200 do
        plan = logic.tick()
      end
      return plan
    end

    it("has nothing to draw with no target", function()
      local plan = logic.tick()
      assert.is_false(plan.occupied)
      assert.are.equal(0, plan.fill.width)
    end)

    it("draws a freshly acquired target at its real width at once", function()
      logic.set_target(mob({ hpp = 50 }))
      assert.are.equal(243, logic.tick().fill.width)
    end)

    it("eases rather than jumping as the same target takes damage", function()
      logic.set_target(mob({ hpp = 100 }))
      logic.tick()
      logic.set_target(mob({ hpp = 0 }))
      -- A tenth of the distance, rounded away from zero so it converges:
      -- 486 - ceil(486 * 0.1) = 437.
      assert.are.equal(437, logic.tick().fill.width)
    end)

    it("converges on empty rather than approaching it forever", function()
      logic.set_target(mob({ hpp = 100 }))
      logic.tick()
      logic.set_target(mob({ hpp = 0 }))
      assert.are.equal(0, settle().fill.width)
    end)

    it("converges on full rather than approaching it forever", function()
      logic.set_target(mob({ hpp = 1 }))
      logic.tick()
      logic.set_target(mob({ hpp = 100 }))
      assert.are.equal(FULL, settle().fill.width)
    end)

    it("snaps to the new width when the target changes", function()
      logic.set_target(mob({ id = 1, hpp = 12 }))
      logic.tick()
      logic.set_target(mob({ id = 2, hpp = 100 }))
      assert.are.equal(FULL, logic.tick().fill.width)
    end)

    -- A deselect and retarget must not resume a slide nobody could see.
    it("snaps when the same target is dropped and reacquired", function()
      logic.set_target(mob({ id = 1, hpp = 100 }))
      logic.tick()
      logic.set_target(mob({ id = 1, hpp = 10 }))
      logic.tick()
      logic.clear_target()
      logic.tick()
      logic.set_target(mob({ id = 1, hpp = 10 }))
      assert.are.equal(48, logic.tick().fill.width)
    end)

    it("snaps when preview opens, so layout mode shows the real footprint", function()
      logic.set_target(mob({ hpp = 100 }))
      logic.tick()
      logic.set_preview(true)
      assert.are.equal(194, logic.tick().fill.width)
    end)

    it("keeps the fill drawn while it still has width", function()
      logic.set_target(mob({ hpp = 100 }))
      local plan = logic.tick()
      assert.are.equal(FULL, plan.fill.width)
      assert.is_false(plan.fill.hidden)
    end)

    it("hides the fill once it has emptied", function()
      logic.set_target(mob({ hpp = 100 }))
      logic.tick()
      logic.set_target(mob({ hpp = 0 }))
      assert.is_true(settle().fill.hidden)
    end)

    it("tints the fill by the claim state", function()
      logic.set_target(mob({ claim_id = 0 }))
      assert.are.same(config.fill_colors.unclaimed, logic.tick().fill.color)
    end)

    it("carries the row's text segments so a frame is one call", function()
      logic.set_target(mob({ hpp = 63, name = "Colibri" }))
      assert.are.equal("63%", logic.tick().texts.hp.text)
    end)
  end)

  describe("claim state", function()
    local SELF_ID, MEMBER_ID, ALLY_ID, STRANGER_ID = 10, 20, 30, 40

    -- What get_party() hands back: member tables under the eighteen party
    -- keys, and scalars (counts, leader ids) alongside them.
    local function party(ids)
      local roster = { party1_count = 3, p0_leader_id = SELF_ID }
      for key, id in pairs(ids) do
        roster[key] = { name = "Member", mob = { id = id } }
      end
      return roster
    end

    before_each(function()
      logic.set_self(SELF_ID, 1.0, "WAR")
      logic.set_party(party({ p0 = SELF_ID, p1 = MEMBER_ID, a10 = ALLY_ID }))
    end)

    it("reports a dead target ahead of every other state", function()
      logic.set_target(mob({ hpp = 0, claim_id = SELF_ID }))
      assert.are.equal("dead", logic.claim_state())
    end)

    it("reports our own claim as mine", function()
      logic.set_target(mob({ claim_id = SELF_ID }))
      assert.are.equal("mine", logic.claim_state())
    end)

    it("reports a party member's claim as mine", function()
      logic.set_target(mob({ claim_id = MEMBER_ID }))
      assert.are.equal("mine", logic.claim_state())
    end)

    -- The upgrade over the reference, which only scanned p1-p5.
    it("reports an alliance member's claim as mine", function()
      logic.set_target(mob({ claim_id = ALLY_ID }))
      assert.are.equal("mine", logic.claim_state())
    end)

    it("reports somebody else's claim as claimed", function()
      logic.set_target(mob({ claim_id = STRANGER_ID }))
      assert.are.equal("claimed", logic.claim_state())
    end)

    it("reports an unclaimed mob as unclaimed", function()
      logic.set_target(mob({ claim_id = 0 }))
      assert.are.equal("unclaimed", logic.claim_state())
    end)

    it("reports a mob with no claim field at all as unclaimed", function()
      local target = mob()
      target.claim_id = nil
      logic.set_target(target)
      assert.are.equal("unclaimed", logic.claim_state())
    end)

    it("reports a targeted party member as member", function()
      logic.set_target(mob({ id = MEMBER_ID, in_party = true, is_npc = false, claim_id = 0 }))
      assert.are.equal("member", logic.claim_state())
    end)

    -- Branch order: member is tested before unclaimed, and party members carry
    -- claim_id 0, so testing unclaimed any earlier would eat this state.
    it("still reports a party member with no claim as member", function()
      logic.set_target(mob({ id = MEMBER_ID, in_party = true, is_npc = false, claim_id = 0 }))
      assert.are.not_equal("unclaimed", logic.claim_state())
    end)

    it("reports yourself as a pc rather than a party member", function()
      logic.set_target(mob({ id = SELF_ID, in_party = true, is_npc = false, claim_id = 0 }))
      assert.are.equal("pc", logic.claim_state())
    end)

    -- Faithful to the reference: only an explicit `is_npc == false` is a
    -- player. A mob table missing the field entirely falls through to the
    -- claim branches, exactly as enemybar's chain does.
    it("does not treat a mob with no is_npc field as a player", function()
      local target = mob({ claim_id = STRANGER_ID })
      target.is_npc = nil
      logic.set_target(target)
      assert.are.equal("claimed", logic.claim_state())
    end)

    it("reports an unpartied player as a pc", function()
      logic.set_target(mob({ id = STRANGER_ID, in_party = false, is_npc = false, claim_id = 0 }))
      assert.are.equal("pc", logic.claim_state())
    end)

    it("has no claim state with nothing targeted", function()
      logic.clear_target()
      assert.is_nil(logic.claim_state())
    end)

    it("deepens the mine tint to FF1414 rather than the reference's pink", function()
      logic.set_self(SELF_ID, 1.0, "WAR")
      logic.set_target(mob({ claim_id = SELF_ID }))
      assert.are.same({ a = 255, r = 255, g = 20, b = 20 }, config.fill_colors[logic.claim_state()])
    end)

    it("carries enemybar's exact colours for the dead and member states", function()
      logic.set_target(mob({ hpp = 0 }))
      assert.are.same({ a = 255, r = 155, g = 155, b = 155 }, config.fill_colors[logic.claim_state()])
      logic.set_target(mob({ id = MEMBER_ID, in_party = true, is_npc = false, claim_id = 0 }))
      assert.are.same({ a = 255, r = 102, g = 255, b = 255 }, config.fill_colors[logic.claim_state()])
    end)

    it("shows the mine tint in preview so layout mode has a colour", function()
      logic.set_preview(true)
      assert.are.equal("mine", logic.claim_state())
    end)

    describe("without the player resolved yet", function()
      before_each(function()
        logic = new_logic(config)
      end)

      --[[ The reference initialises player_id to 0 and matches
           `player_id == claim_id`, so until its load handler resolves the
           player every unclaimed mob reads as claimed by us. ]]
      it("never calls an unclaimed mob mine, with no self id", function()
        logic.set_target(mob({ claim_id = 0 }))
        assert.are.equal("unclaimed", logic.claim_state())
      end)

      it("never calls an unclaimed mob mine, with a zero self id", function()
        logic.set_self(0, 1.0, "WAR")
        logic.set_target(mob({ claim_id = 0 }))
        assert.are.equal("unclaimed", logic.claim_state())
      end)

      -- `in_party and id ~= player_id` with a nil player id is true for
      -- yourself, so the member branch needs the same guard as mine.
      it("degrades a party target to pc rather than miscolouring it", function()
        logic.set_target(mob({ id = SELF_ID, in_party = true, is_npc = false, claim_id = 0 }))
        assert.are.equal("pc", logic.claim_state())
      end)

      it("still resolves our own claim from the self id with no roster", function()
        logic.set_self(SELF_ID, 1.0, "WAR")
        logic.set_target(mob({ claim_id = SELF_ID }))
        assert.are.equal("mine", logic.claim_state())
      end)
    end)

    describe("reading the roster", function()
      it("skips a member the client has not loaded a mob for", function()
        logic.set_party({ p0 = { name = "Elsewhere" }, p1 = { name = "Here", mob = { id = MEMBER_ID } } })
        logic.set_target(mob({ claim_id = MEMBER_ID }))
        assert.are.equal("mine", logic.claim_state())
      end)

      -- get_party() mixes scalars in with the member tables; a bare pairs()
      -- walk would index a number inside the guarded prerender path.
      it("ignores the scalar keys get_party mixes in", function()
        assert.has_no.errors(function()
          logic.set_party({ party1_count = 3, p0_leader_id = SELF_ID, p0 = { name = "Me", mob = { id = SELF_ID } } })
        end)
      end)

      it("survives no roster at all", function()
        assert.has_no.errors(function()
          logic.set_party(nil)
        end)
      end)

      it("forgets members who have left", function()
        logic.set_party(party({ p0 = SELF_ID }))
        logic.set_target(mob({ claim_id = MEMBER_ID }))
        assert.are.equal("claimed", logic.claim_state())
      end)
    end)
  end)

  describe("the poll gate", function()
    it("is open on its first call, so the first frame has a roster", function()
      assert.is_true(logic.due_for_poll(0))
    end)

    it("stays shut inside the interval", function()
      logic.due_for_poll(0)
      assert.is_false(logic.due_for_poll(0.1))
    end)

    it("opens again once the interval has passed", function()
      logic.due_for_poll(0)
      assert.is_true(logic.due_for_poll(0.2))
    end)

    --[[ Logic is built once per widget but attached on every login, so
         without this only the session's first attach would poll immediately
         and a relog would spend a window with no roster. ]]
    it("reopens when a fresh config arrives on attach", function()
      logic.due_for_poll(0)
      assert.is_false(logic.due_for_poll(0.1))
      logic.set_config(config)
      assert.is_true(logic.due_for_poll(0.1))
    end)
  end)

  --[[ DistancePlus's range coding, ported whole. The expected values are
       derived by walking that addon's own branch order at the given model
       sizes, never from a description of it: its bands add both model sizes,
       so which branch a distance lands in is not something prose can
       summarise. ]]
  describe("range colouring", function()
    -- Neither party is large enough for the ranged +0.1 adjustment.
    local SELF, TARGET = 1.0, 1.0

    local function state(mode, distance, target_size)
      return logic.range_state(mode, distance, SELF, target_size or TARGET)
    end

    it("colours nothing without a mode", function()
      assert.are.equal("out", state("default", 10))
    end)

    it("colours a target you are standing on as out of range", function()
      -- The source checks a zero distance before it looks at the mode at all.
      assert.are.equal("out", state("magic", 0))
    end)

    it("falls back to plain white when the player is unresolved", function()
      assert.are.equal("out", logic.range_state("magic", 10, nil, TARGET))
    end)

    -- Every band is measured from both parties' sizes, so a mob the client has
    -- not sized yet gets no band rather than one measured from zero.
    it("falls back to plain white when the target has no model size", function()
      assert.are.equal("out", logic.range_state("magic", 10, SELF, nil))
    end)

    it("leaves a target with no model size uncoloured", function()
      config.distance.mode = "magic"
      logic.set_config(config)
      logic.set_self(1, 1.0, "WHM")
      local target = mob({ distance = 100 })
      target.model_size = nil
      logic.set_target(target)
      assert.are.same(config.distance.colors.out, logic.texts().distance.color)
    end)

    describe("magic", function()
      it("is in range inside 20 plus both model sizes", function()
        assert.are.equal("good", state("magic", 21))
      end)

      it("is out of range beyond it", function()
        assert.are.equal("out", state("magic", 23))
      end)

      it("is out of range exactly at the boundary", function()
        assert.are.equal("out", state("magic", 22))
      end)

      it("adds a tenth for a large target", function()
        -- 20.1 + 3 + 1: without the adjustment 24 would be out of range.
        assert.are.equal("good", state("magic", 24, 3.0))
      end)

      --[[ The source's model_size == 4.4 special case is unreachable: the
           `> 2` branch above it always fires first. Ported in branch order, so
           the cap is 20.1 rather than the 20.0666 the dead branch names. ]]
      it("takes the large-target branch ahead of the dead special case", function()
        assert.are.equal("good", state("magic", 25.47, 4.4))
      end)
    end)

    describe("ninjutsu", function()
      it("is in range inside 16.1 plus both model sizes", function()
        assert.are.equal("good", state("ninjutsu", 18))
      end)

      it("is out of range beyond it", function()
        assert.are.equal("out", state("ninjutsu", 19))
      end)

      -- A twentieth either side of 16.1 + 1 + 1, so the base cannot drift in
      -- its first decimal without a flip.
      it("pins the base to its decimal from below", function()
        assert.are.equal("good", state("ninjutsu", 18.05))
      end)

      it("pins the base to its decimal from above", function()
        assert.are.equal("out", state("ninjutsu", 18.15))
      end)
    end)

    describe("bow", function()
      it("is out of range past 25", function()
        assert.are.equal("out", state("bow", 30))
      end)

      it("is out of range exactly at 25", function()
        assert.are.equal("out", state("bow", 25))
      end)

      it("shoots without a bonus when too far for the square band", function()
        assert.are.equal("capable", state("bow", 20))
      end)

      it("shoots without a bonus when too close for the square band", function()
        assert.are.equal("capable", state("bow", 5))
      end)

      it("shoots squarely in the far band", function()
        assert.are.equal("good", state("bow", 14))
      end)

      it("shoots squarely in the near band", function()
        assert.are.equal("good", state("bow", 7))
      end)

      it("strikes true between them", function()
        assert.are.equal("best", state("bow", 10))
      end)

      --[[ The source adds both model sizes to the band constant and only then
           adds the large-target tenth. Folding that tenth in earlier is the
           same sum in algebra but not in floating point, and it moves this
           boundary by one unit in the last place: at exactly the square band's
           near edge the two orders disagree. ]]
      it("adds the large-target tenth in the source's order, not earlier", function()
        assert.are.equal("good", logic.range_state("bow", 7.22, 0.5, 2.0))
      end)

      it("agrees with the source at the other end of the same band", function()
        assert.are.equal("capable", logic.range_state("bow", 13.02, 3.0, 5.3))
      end)

      -- Keyed on the target's model size alone, exactly as the source has it.
      it("adds a tenth to every band for a large target", function()
        -- At 12.6 the unadjusted bands say square shot; the adjusted ones,
        -- true shot.
        assert.are.equal("best", state("bow", 12.6, 2.0))
      end)
    end)

    --[[ Boundaries the port could get wrong without any constant changing.
         Each is a strict comparison in the source that an idle `>=` would
         silently widen. ]]
    describe("at the exact boundaries", function()
      it("treats a target of exactly 1.6 as small for the ranged bands", function()
        -- The bonus is `> 1.6`, so 1.6 itself gets none. 12.15 sits just past
        -- the unadjusted true-shot ceiling of 12.1199 and just inside the
        -- adjusted one, so it reads square shot here and would read true shot
        -- if that comparison ever widened to `>=`.
        assert.are.equal("good", state("bow", 12.15, 1.6))
      end)

      it("treats a target of exactly 2 as small for the casting range", function()
        -- `> 2`, so no tenth here: 23 sits outside 20 + 2 + 1 either way, but
        -- 23.05 only stays out without the bonus.
        assert.are.equal("out", state("magic", 23.05, 2.0))
      end)

      --[[ Edges chosen so a slip in a transcribed constant's last digit flips
           the answer: 11.52 reads square shot only while bow's true-shot
           ceiling is exactly 9.5199 (2 + 9.52 would claim it); 7.0 reads
           square shot only while xbow's floor keeps its .0007; 6.32 likewise
           for gun's 4.3189; and 24.15 stays out of a large target's casting
           range only while the bonus is a tenth. ]]
      it("pins bow's true-shot ceiling to its fourth decimal", function()
        assert.are.equal("good", state("bow", 11.52))
      end)

      it("pins xbow's true-shot floor to its fourth decimal", function()
        assert.are.equal("good", state("xbow", 7.0))
      end)

      it("pins gun's true-shot ceiling to its fourth decimal", function()
        assert.are.equal("good", state("gun", 6.32))
      end)

      it("pins the casting bonus at a tenth, not more", function()
        assert.are.equal("out", state("magic", 24.15, 3.0))
      end)

      -- The same treatment for every remaining transcribed constant: one
      -- distance just past each edge, chosen so any drift flips the colour.
      it("pins bow's square-shot ceiling", function()
        assert.are.equal("capable", state("bow", 16.52))
      end)

      it("pins xbow's true-shot ceiling", function()
        assert.are.equal("good", state("xbow", 10.4))
      end)

      it("pins xbow's square-shot ceiling", function()
        assert.are.equal("capable", state("xbow", 13.72))
      end)

      it("pins xbow's square-shot floor", function()
        assert.are.equal("capable", state("xbow", 5.61))
      end)

      it("pins gun's true-shot floor", function()
        assert.are.equal("good", state("gun", 5.02))
      end)

      it("pins gun's square-shot ceiling", function()
        assert.are.equal("capable", state("gun", 8.82))
      end)

      it("pins gun's square-shot floor", function()
        assert.are.equal("capable", state("gun", 4.22))
      end)

      -- Both directions this time: 8.01 sits a hundredth under bow's
      -- true-shot floor of 2 + 6.02 and 8.02 exactly on it, so the constant
      -- cannot drift either way without one of these flipping.
      it("pins bow's true-shot floor from below", function()
        assert.are.equal("good", state("bow", 8.01))
      end)

      it("pins bow's true-shot floor from above", function()
        assert.are.equal("best", state("bow", 8.02))
      end)

      -- The large-target tenth is added to all four thresholds, and each
      -- addition is separately observable. These two pin the ones the
      -- order-of-summation tests do not reach.
      it("adds the large-target tenth to the true-shot floor", function()
        -- 9.05 is below the adjusted floor of 3 + 6.02 + 0.1, so square shot;
        -- without that tenth it would clear the floor and strike true.
        assert.are.equal("good", state("bow", 9.05, 2.0))
      end)

      it("adds the large-target tenth to the square-shot ceiling", function()
        -- 17.57 is inside the adjusted ceiling of 3 + 14.5199 + 0.1; without
        -- the tenth it would fall past the band into plain capable.
        assert.are.equal("good", state("bow", 17.57, 2.0))
      end)

      -- A target of 1.7 is large: if the threshold crept up from 1.6, the
      -- tenth would vanish and 12.28 would fall past the true-shot ceiling.
      it("treats a target just over 1.6 as large", function()
        assert.are.equal("best", state("bow", 12.28, 1.7))
      end)

      it("puts a distance exactly at the true-shot edge in the true-shot band", function()
        -- The square-shot branch is `> true_max`, so the edge itself falls
        -- through to true shot rather than being claimed by square shot.
        assert.are.equal("best", state("bow", 11.5199))
      end)
    end)

    describe("crossbow", function()
      it("strikes true in its own tighter band", function()
        assert.are.equal("best", state("xbow", 8))
      end)

      it("is out of range past 25", function()
        assert.are.equal("out", state("xbow", 30))
      end)
    end)

    describe("gun", function()
      it("strikes true in its own tightest band", function()
        assert.are.equal("best", state("gun", 5.5))
      end)

      it("is out of range past 25", function()
        assert.are.equal("out", state("gun", 30))
      end)
    end)

    describe("choosing the mode from the job", function()
      it("casts for every job that casts", function()
        for _, job in ipairs({ "RDM", "BLM", "GEO", "SCH", "WHM", "BRD" }) do
          assert.are.equal("magic", logic.resolve_mode("auto", job), job .. " should use the casting range")
        end
      end)

      it("uses ninjutsu range on a ninja", function()
        assert.are.equal("ninjutsu", logic.resolve_mode("auto", "NIN"))
      end)

      it("uses gun range on a corsair", function()
        assert.are.equal("gun", logic.resolve_mode("auto", "COR"))
      end)

      -- The source hands RNG the default and tells the player to pick a
      -- weapon mode themselves; there is no way to know which they are using.
      it("leaves a ranger on the default until they choose a weapon", function()
        assert.are.equal("default", logic.resolve_mode("auto", "RNG"))
      end)

      it("leaves every other job on the default", function()
        assert.are.equal("default", logic.resolve_mode("auto", "WAR"))
      end)

      it("copes with no job at all", function()
        assert.are.equal("default", logic.resolve_mode("auto", nil))
      end)

      it("honours an explicit choice over the job", function()
        assert.are.equal("bow", logic.resolve_mode("bow", "WHM"))
      end)

      it("ignores a mode nobody defines", function()
        assert.are.equal("default", logic.resolve_mode("trebuchet", "WHM"))
      end)
    end)

    -- DistancePlus's yellow and blue, by literal: nothing else reaches them.
    it("carries the reference's exact colours for the ranged states", function()
      config.distance.mode = "bow"
      logic.set_config(config)
      logic.set_self(1, 1.0, "WAR")
      logic.set_target(mob({ distance = 400 }))
      assert.are.same({ a = 255, r = 255, g = 255, b = 0 }, logic.texts().distance.color)
      logic.set_target(mob({ distance = 100 }))
      assert.are.same({ a = 255, r = 0, g = 0, b = 255 }, logic.texts().distance.color)
    end)

    describe("colouring the distance segment", function()
      it("uses the out-of-range colour by default", function()
        logic.set_target(mob({ distance = 400 }))
        assert.are.same(config.distance.colors.out, logic.texts().distance.color)
      end)

      it("uses the in-range colour once the job and mode agree", function()
        config.distance.mode = "magic"
        logic.set_config(config)
        logic.set_self(1, 1.0, "WHM")
        -- 10 away, well inside 20 plus both model sizes.
        logic.set_target(mob({ distance = 100 }))
        assert.are.same(config.distance.colors.good, logic.texts().distance.color)
      end)

      it("follows the job when the mode is left on auto", function()
        logic.set_self(1, 1.0, "WHM")
        logic.set_target(mob({ distance = 100 }))
        assert.are.same(config.distance.colors.good, logic.texts().distance.color)
      end)
    end)
  end)

  describe("the mode command", function()
    it("reports the mode it is on when asked nothing", function()
      local reply, changed = logic.command({})
      assert.is_false(changed)
      assert.is_truthy(reply:find("auto"))
    end)

    it("nudges a ranger to pick a weapon, as the reference does", function()
      logic.set_self(1, 1.0, "RNG")
      local reply = logic.command({})
      assert.is_truthy(reply:find("bow"))
    end)

    it("switches mode and asks to be saved", function()
      local reply, changed = logic.command({ "mode", "bow" })
      assert.is_true(changed)
      assert.are.equal("bow", config.distance.mode)
      assert.is_truthy(reply:find("bow"))
    end)

    it("matches the mode case-insensitively", function()
      logic.command({ "mode", "XBOW" })
      assert.are.equal("xbow", config.distance.mode)
    end)

    -- Core hands a component's arguments through exactly as the player typed
    -- them, and CLAUDE.md promises verbs match case-insensitively.
    it("matches the verb case-insensitively too", function()
      local _, changed = logic.command({ "MODE", "bow" })
      assert.is_true(changed)
      assert.are.equal("bow", config.distance.mode)
    end)

    it("refuses a mode nobody defines", function()
      local reply, changed = logic.command({ "mode", "trebuchet" })
      assert.is_false(changed)
      assert.are.equal("auto", config.distance.mode)
      assert.is_truthy(reply:find("magic"))
    end)

    it("asks for a mode when given none", function()
      local reply, changed = logic.command({ "mode" })
      assert.is_false(changed)
      assert.is_truthy(reply:find("magic"))
    end)

    --[[ Config files are hand-editable Lua, so the mode can be anything. What
         it must not do is report one mode while colouring by another. ]]
    it("reports the mode it will actually colour by, not what the file says", function()
      config.distance.mode = 42
      logic.set_config(config)
      logic.set_self(1, 1.0, "WHM")
      -- resolve_mode reads a non-string as `default`, so the status line must
      -- not claim the casting range a WHM would otherwise get.
      local reply = logic.command({})
      assert.is_truthy(reply:find("default"))
      assert.is_nil(reply:find("magic"))
    end)

    it("hints rather than falling silent on a verb it does not know", function()
      local reply, changed = logic.command({ "colour", "red" })
      assert.is_false(changed)
      assert.is_truthy(reply:find("mode"))
    end)
  end)

  -- defaults.lua re-derives the row width locally (it runs before logic has a
  -- config), so this is the one place the two computations are held together:
  -- if either side's arithmetic drifts, the default slot stops centring the
  -- box the widget actually draws.
  it("caps the name identically with and without the config key", function()
    local unconfigured = new_logic({})
    local target = mob({ name = "Absolutely Enormous Name" })
    logic.set_target(target)
    unconfigured.set_target(target)
    -- logic's fallback cap and the shipped default are the same 17.
    assert.are.equal(logic.texts().name.text, unconfigured.texts().name.text)
    assert.are.equal(17, #logic.texts().name.text)
  end)

  it("centres the default slot on the row logic actually computes", function()
    local screen_width = 1920
    local defaults = build_defaults(screen_width, 1080)
    local _, _, row_width = new_logic(defaults).bounds(0, 0, 1)
    assert.are.equal(math.floor((screen_width - row_width) / 2), defaults.slots.default.pos.x)
  end)

  describe("layout", function()
    local ORIGIN_X, ORIGIN_Y = 400, 200
    local SCREEN_WIDTH = 1920

    -- Every rectangle the widget will actually draw, art footprints and all.
    -- The fills are measured at their widest, since the eased width only ever
    -- shrinks them.
    local function drawn_boxes(geometry)
      local boxes = {}
      local function add(label, box)
        boxes[#boxes + 1] = { label = label, x = box.x, y = box.y, width = box.width, height = box.height }
      end

      for key, segment in pairs(geometry.texts) do
        add("text " .. key, segment)
      end
      add("frame", geometry.frame)
      add("fill", {
        x = geometry.fill.x,
        y = geometry.fill.y,
        width = geometry.fill.full_width,
        height = geometry.fill.height,
      })
      add("cast frame", geometry.cast.frame)
      add("cast fill", {
        x = geometry.cast.fill.x,
        y = geometry.cast.fill.y,
        width = geometry.cast.fill.full_width,
        height = geometry.cast.fill.height,
      })
      -- Right-justified, so it grows leftwards from its right edge; the box
      -- it can occupy is its capped width back from there.
      add("cast name", {
        x = geometry.cast.name.right_edge - geometry.cast.name.max_width,
        y = geometry.cast.name.y,
        width = geometry.cast.name.max_width,
        height = geometry.cast.name.height,
      })
      return boxes
    end

    local function assert_contained(scale)
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, scale, SCREEN_WIDTH)
      local bx, by, width, height = logic.bounds(ORIGIN_X, ORIGIN_Y, scale)

      assert.are.equal(ORIGIN_X, bx)
      assert.are.equal(ORIGIN_Y, by)

      for _, box in ipairs(drawn_boxes(geometry)) do
        assert.is_true(box.x >= bx, box.label .. " starts left of the origin")
        assert.is_true(box.y >= by, box.label .. " starts above the origin")
        assert.is_true(box.x + box.width <= bx + width, box.label .. " runs past the right edge")
        assert.is_true(box.y + box.height <= by + height, box.label .. " runs past the bottom edge")
      end
    end

    it("hands back exactly the origin it was given", function()
      local bx, by = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(ORIGIN_X, bx)
      assert.are.equal(ORIGIN_Y, by)
    end)

    it("sizes the row from the frame, which outgrows the default text", function()
      -- The reserves come to 285 at 14pt; the 512px frame wins.
      local _, _, width = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(512, width)
    end)

    it("sizes the row from the reserves once the text outgrows the frame", function()
      config.font_size = 28
      logic.set_config(config)
      -- 21 of leading inset, then 105 + 105 + 357 at 28pt: past the frame's
      -- 512, so the inset counts toward the box too.
      local _, _, width = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(588, width)
    end)

    it("lays the row out left to right: hp, distance, then name", function()
      -- The row starts one character in from the bar's left edge (10.5px at
      -- the 14pt font), clear of the frame art's own bevel.
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(ORIGIN_X + 10.5, geometry.texts.hp.x)
      assert.are.equal(ORIGIN_X + 63.5, geometry.texts.distance.x)
      assert.are.equal(ORIGIN_X + 116.5, geometry.texts.name.x)
    end)

    it("scales the row's leading inset with the font", function()
      -- At half scale the drawn font is 7, so the inset is one 7px character.
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 0.5)
      assert.are.equal(ORIGIN_X + 5.25, geometry.texts.hp.x)
    end)

    it("drops the bar's visible band below the text, not its texture", function()
      -- 21px of text, an 8px gap, less the 25px of transparent art above the
      -- band: the texture starts at +4 so the band itself lands at +29.
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(ORIGIN_Y + 4, geometry.frame.y)
    end)

    it("insets the fill inside the frame", function()
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(ORIGIN_X + 13, geometry.fill.x)
      assert.are.equal(486, geometry.fill.full_width)
    end)

    --[[ Absolute positions at half scale. The containment assertions derive
         the drawn boxes and the bounds from the same arithmetic, so they are
         blind to an error both sides share - only fixed numbers pin whether
         each piece of the layout actually scales. At 0.5 the drawn font
         rounds to 7, the text row is 10.5 tall, and the effective gap is 4,
         so the band lands at 14.5 - which, less the scaled 12.5 of padding
         above it, puts the frame's texture 2 below the origin. An unscaled
         gap would push it to 6; unscaled padding would lift it above the
         origin entirely. ]]
    it("scales every part of the vertical stack, not just the art", function()
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 0.5)
      assert.are.equal(ORIGIN_Y + 2, geometry.frame.y)
      assert.are.equal(256, geometry.frame.width)
      assert.are.equal(32, geometry.frame.height)
    end)

    it("scales the fill's inset and height with the frame", function()
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 0.5)
      assert.are.equal(ORIGIN_X + 6.5, geometry.fill.x)
      assert.are.equal(geometry.frame.y, geometry.fill.y)
      assert.are.equal(243, geometry.fill.full_width)
      assert.are.equal(32, geometry.fill.height)
    end)

    it("draws the frame at the art's full height at scale 1", function()
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(64, geometry.frame.height)
      assert.are.equal(64, geometry.fill.height)
    end)

    it("reports the box's absolute height, not just its origin", function()
      -- Text row 21, gap 8, band offset 25: the hp frame starts at +4 and
      -- runs 64 deep to +68. The cast rows reach past it: the cast band
      -- lands at +47, its frame runs 64 * 0.67 deep from the band offset
      -- above it, and the name row (10pt, 15px tall) hangs 2 below the
      -- band's bottom.
      -- The name row is 12pt now, 18px tall.
      local _, _, _, height = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(47 - 25 * 0.67 + 39 * 0.67 + 2 + 18, height)
    end)

    --[[ The cast rows are in the box whether or not anything is casting: a
         drag target that grew the moment a mob started casting would move
         out from under the cursor mid-drag. ]]
    it("reserves the cast rows in the box permanently", function()
      local _, _, _, idle_height = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
      logic = new_logic(config, FAKE_RESOURCES)
      logic.set_target(mob())
      logic.on_action({
        actor_id = 100,
        category = 8,
        param = 0,
        targets = { { id = 1, actions = { { param = 144, message = 327 } } } },
      }, 10)
      local _, _, _, casting_height = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(idle_height, casting_height)
    end)

    it("right-aligns the cast bar against the box's edge, on its own art", function()
      -- The cast bar draws half-width art (256 drawn), not a squashed copy
      -- of the wide frame - non-uniform scaling would warp the caps.
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1, SCREEN_WIDTH)
      assert.are.equal(256 * 0.67, geometry.cast.frame.width)
      assert.are.equal(64 * 0.67, geometry.cast.frame.height)
      assert.are.equal(ORIGIN_X + 512, geometry.cast.frame.x + geometry.cast.frame.width)
      -- Its band lands cast.gap below the hp band's bottom: hp band ends at
      -- +43, plus 4, less the cast-scale band offset.
      assert.are.equal(ORIGIN_Y + 47 - 25 * 0.67, geometry.cast.frame.y)
    end)

    it("insets the cast fill like the main fill, at the cast's scale", function()
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1, SCREEN_WIDTH)
      assert.are.equal(geometry.cast.frame.x + 13 * 0.67, geometry.cast.fill.x)
      assert.are.equal(230 * 0.67, geometry.cast.fill.full_width)
      assert.are.equal(64 * 0.67, geometry.cast.fill.height)
    end)

    --[[ The one right-justified text in the addon. texts.pos adds the screen
         width to x when the right flag is set, so the position handed to the
         prim pre-subtracts it; the right edge is the box's own. ]]
    it("offsets the right-justified cast name by the screen width", function()
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1, SCREEN_WIDTH)
      assert.are.equal(ORIGIN_X + 512, geometry.cast.name.right_edge)
      assert.are.equal(ORIGIN_X + 512 - SCREEN_WIDTH, geometry.cast.name.x)
      assert.are.equal(12, geometry.cast.name.size)
      assert.are.equal(20, geometry.cast.name.max_chars)
    end)

    it("scales the fill's eased width with the widget", function()
      local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 0.5)
      assert.are.equal(243, geometry.fill.width_at(486))
    end)

    --[[ Core reads the box to clamp the widget on screen and layout mode reads
         it to hit-test a drag, both while the target is changing underneath.
         A box that moved with the target would drag out from under the
         cursor. ]]
    it("reports the same box whatever is targeted", function()
      local _, _, empty_width, empty_height = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
      logic.set_target(mob({ name = "A", hpp = 3 }))
      local _, _, width, height = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
      assert.are.equal(empty_width, width)
      assert.are.equal(empty_height, height)
    end)

    it("keeps every drawn element inside the box", function()
      assert_contained(1)
    end)

    it("keeps every drawn element inside the box when scaled down", function()
      assert_contained(0.25)
    end)

    it("keeps every drawn element inside the box at a fractional scale", function()
      assert_contained(0.75)
    end)

    it("keeps every drawn element inside the box when scaled up", function()
      assert_contained(2)
    end)

    describe("with the font rounded to whole pixels", function()
      -- A prim cannot draw a fractional font, so the reserves have to be
      -- computed from the size the prim will actually round to.
      it("rounds the drawn font rather than scaling the reserve", function()
        local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 0.25)
        assert.are.equal(4, geometry.texts.hp.size)
      end)

      it("keeps a tiny font drawable", function()
        config.font_size = 1
        logic.set_config(config)
        local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 0.25)
        assert.is_true(geometry.texts.hp.size >= 1)
      end)

      it("measures the row from the rounded font, not the scaled box", function()
        -- Reserves reach 81 at the 4px font a quarter scale rounds 14 to;
        -- the frame's 128 drawn pixels win.
        local _, _, width = logic.bounds(ORIGIN_X, ORIGIN_Y, 0.25)
        assert.are.equal(128, width)
      end)
    end)

    describe("with hostile configuration", function()
      local function reconfigure(changes)
        for key, value in pairs(changes) do
          config[key] = value
        end
        logic.set_config(config)
      end

      it("floors the row at the bar's own drawn width", function()
        reconfigure({ font_size = 6 })
        -- The reserves only reach 123, but the frame still draws 512 wide.
        local _, _, width = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
        assert.are.equal(512, width)
        assert_contained(1)
      end)

      it("keeps the bar below the origin when the gap is closed", function()
        reconfigure({ font_size = 12, gap = 0 })
        local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1)
        assert.are.equal(ORIGIN_Y, geometry.frame.y)
        assert_contained(1)
      end)

      it("keeps the bar below the origin when the gap goes negative", function()
        reconfigure({ gap = -1000 })
        assert_contained(1)
      end)

      -- A font tall enough to outrun the bar, with a gap pulling the bar back
      -- up under it: the text row, not the art, is then the lowest thing drawn.
      it("keeps a text row taller than the bar inside the box", function()
        reconfigure({ font_size = 60, gap = -50 })
        assert_contained(1)
      end)

      it("survives a cast bar scaled past the widget", function()
        config.cast.scale = 8
        logic.set_config(config)
        assert_contained(1)
      end)

      it("survives a cast font of zero or worse", function()
        config.cast.font_size = 0
        logic.set_config(config)
        assert_contained(1)
        config.cast.font_size = -10
        logic.set_config(config)
        assert_contained(1)
      end)

      it("survives negative cast spacing, which would hoist the rows", function()
        config.cast.gap = -1000
        config.cast.name_gap = -1000
        logic.set_config(config)
        assert_contained(1)
      end)

      it("keeps the cast name's derived cap in charge of a huge config cap", function()
        config.cast.name_max_chars = 1000000000
        logic.set_config(config)
        assert_contained(1)
        local geometry = logic.geometry(ORIGIN_X, ORIGIN_Y, 1, SCREEN_WIDTH)
        -- The room the row actually has, not the config's ambition.
        assert.is_true(geometry.cast.name.max_chars <= 61)
      end)

      it("survives a cast section that is not a table", function()
        config.cast = 42
        logic.set_config(config)
        assert.has_no.errors(function()
          logic.geometry(ORIGIN_X, ORIGIN_Y, 1, SCREEN_WIDTH)
        end)
        assert_contained(1)
      end)

      it("survives a tiny name cap", function()
        reconfigure({ name_max_chars = 3 })
        assert_contained(1)
      end)

      -- The cap needs a ceiling as well as a floor: a hand-edited huge value
      -- would otherwise hand a megapixel-wide box to the screen clamp.
      it("caps a huge name reserve rather than sizing the box to it", function()
        reconfigure({ name_max_chars = 100000 })
        local _, _, huge_width = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
        reconfigure({ name_max_chars = 64 })
        local _, _, ceiling_width = logic.bounds(ORIGIN_X, ORIGIN_Y, 1)
        assert.are.equal(ceiling_width, huge_width)
        assert_contained(1)
      end)

      it("clamps a negative name cap rather than passing it to a substring", function()
        reconfigure({ name_max_chars = -5 })
        logic.set_target(mob({ name = "Bugbear" }))
        assert.are.equal("B", logic.texts().name.text)
        assert_contained(1)
      end)
    end)
  end)

  --[[ Config files are Lua a user can hand-edit, and the defaults merge
       deliberately preserves a user's scalar where the defaults have a table.
       Every read below runs on the per-frame path, and prerender is one
       guarded handler shared by every component - five throws and the whole
       HUD stops rendering for the session. Nonsense must degrade, never
       throw. ]]
  describe("with a hand-mangled config", function()
    local function mangled(key, value)
      config[key] = value
      logic.set_config(config)
      logic.set_target(mob({ hpp = 20, distance = 100 }))
    end

    it("survives bands that are not a table", function()
      mangled("bands", 7)
      assert.has_no.errors(function()
        logic.tick()
      end)
      -- The number degrades to the plain text colour.
      assert.are.same(config.text_color, logic.texts().hp.color)
    end)

    it("survives a distance section that is not a table", function()
      mangled("distance", 42)
      assert.has_no.errors(function()
        logic.tick()
      end)
      assert.are.same(config.text_color, logic.texts().distance.color)
    end)

    it("survives a fill palette that is not a table", function()
      mangled("fill_colors", 7)
      assert.has_no.errors(function()
        logic.tick()
      end)
    end)

    it("survives text colours that are not tables", function()
      mangled("text_color", "red")
      mangled("text_stroke", 3)
      assert.has_no.errors(function()
        logic.tick()
      end)
    end)

    it("still changes mode over a mangled distance section", function()
      mangled("distance", "magic")
      local reply, changed
      assert.has_no.errors(function()
        reply, changed = logic.command({ "mode", "bow" })
      end)
      assert.is_true(changed)
      assert.are.equal("bow", config.distance.mode)
      assert.is_truthy(reply:find("bow"))
    end)
  end)

  describe("the cast bar", function()
    local function acquire(fields)
      logic.set_target(mob(fields))
    end

    before_each(function()
      logic = new_logic(config, FAKE_RESOURCES)
      acquire()
    end)

    local function cast_of(now)
      return logic.tick(now).cast
    end

    it("shows nothing before anyone casts", function()
      assert.is_false(cast_of(0).active)
    end)

    it("starts a bar when the target begins a spell", function()
      logic.on_action(action(), 10)
      local cast = cast_of(10)
      assert.is_true(cast.active)
      assert.are.equal("Fire IV", cast.name)
    end)

    it("measures spell progress against the spell's cast time", function()
      logic.on_action(action(), 10)
      -- Fire IV casts in 8 seconds; 4 in is half way.
      assert.are.equal(0.5, cast_of(14).progress)
      -- And half way is half the cast art's own 230px fill region.
      assert.are.equal(115, cast_of(14).width)
    end)

    it("starts at zero and clamps at full until something closes it", function()
      logic.on_action(action(), 10)
      assert.are.equal(0, cast_of(10).progress)
      assert.are.equal(1, cast_of(18.5).progress)
    end)

    it("runs a TP move on the fixed sweep, since no real duration exists", function()
      logic.on_action(
        action({ category = 7, targets = { { id = 1, actions = { { param = 672, message = 43 } } } } }),
        10
      )
      local cast = cast_of(11)
      assert.is_true(cast.active)
      assert.are.equal("Blood Drain", cast.name)
      -- cast.tp_move_sweep is 2 seconds; 1 in is half way.
      assert.are.equal(0.5, cast.progress)
    end)

    it("reads a readying player as a weapon skill, not a monster ability", function()
      acquire({ is_npc = false, id = 100 })
      logic.on_action(
        action({ category = 7, targets = { { id = 1, actions = { { param = 32, message = 43 } } } } }),
        10
      )
      assert.are.equal("Fast Blade", cast_of(10).name)
    end)

    it("ignores an action by anything that is not the target", function()
      logic.on_action(action({ actor_id = 999 }), 10)
      assert.is_false(cast_of(10).active)
    end)

    it("ignores actions with nothing targeted", function()
      logic.clear_target()
      assert.has_no.errors(function()
        logic.on_action(action(), 10)
      end)
      assert.is_false(cast_of(10).active)
    end)

    --[[ The reference guards `action_id == 0` explicitly: start packets can
         carry a zero (or missing) id, and a bar named "Unknown (id:0)" for
         five seconds is worse than none. ]]
    it("ignores a start with a zero id", function()
      logic.on_action(action({ targets = { { id = 1, actions = { { param = 0, message = 327 } } } } }), 10)
      assert.is_false(cast_of(10).active)
    end)

    it("ignores a start with no id at all", function()
      logic.on_action(action({ targets = { { id = 1, actions = { { message = 327 } } } } }), 10)
      assert.is_false(cast_of(10).active)
    end)

    -- Some spells legitimately cast in zero seconds; a bar with nothing to
    -- fill and nothing to wait for is noise, not information.
    it("raises no bar for an instant cast", function()
      logic = new_logic(config, { spells = { [7] = { en = "Instacast", cast_time = 0 } } })
      acquire()
      logic.on_action(action({ targets = { { id = 1, actions = { { param = 7, message = 327 } } } } }), 10)
      assert.is_false(cast_of(10).active)
    end)

    it("names an id the resources do not know without crashing", function()
      logic.on_action(action({ targets = { { id = 1, actions = { { param = 9999, message = 327 } } } } }), 10)
      local cast = cast_of(10)
      assert.is_true(cast.active)
      assert.is_truthy(cast.name:find("9999"))
    end)

    it("clears when the spell completes", function()
      logic.on_action(action(), 10)
      -- Category 4 is the finish; on a finish the id is the root param.
      logic.on_action(action({ category = 4, param = 144 }), 12)
      assert.is_false(cast_of(12).active)
    end)

    it("clears when a TP move fires", function()
      logic.on_action(
        action({ category = 7, targets = { { id = 1, actions = { { param = 672, message = 43 } } } } }),
        10
      )
      logic.on_action(action({ category = 11, param = 672 }), 12)
      assert.is_false(cast_of(12).active)
    end)

    --[[ An interrupt arrives as a start-shaped packet whose one action has
         message 0 and targets the caster itself - the structural signature
         enemybar2 keys on, needing no magic parameter. ]]
    it("clears when the cast is interrupted", function()
      logic.on_action(action(), 10)
      logic.on_action(action({ targets = { { id = 100, actions = { { param = 0, message = 0 } } } } }), 12)
      assert.is_false(cast_of(12).active)
    end)

    -- The other half of the structural test: message 0 aimed at anything
    -- *other* than the caster is not an interrupt, just a start.
    it("does not read a message-0 start at another target as an interrupt", function()
      logic.on_action(action({ targets = { { id = 55, actions = { { param = 144, message = 0 } } } } }), 10)
      assert.is_true(cast_of(10).active)
      assert.are.equal("Fire IV", cast_of(10).name)
    end)

    it("clears on the other finish categories the reference closes on", function()
      -- 6 is a job ability resolving, 5 an item finishing: either from the
      -- caster means whatever was winding up has resolved or been replaced.
      logic.on_action(action(), 10)
      logic.on_action(action({ category = 6, param = 99, targets = {} }), 11)
      assert.is_false(cast_of(11).active)
      logic.on_action(action(), 12)
      logic.on_action(action({ category = 5, param = 4096, targets = {} }), 13)
      assert.is_false(cast_of(13).active)
    end)

    it("honours a configured sweep other than the default", function()
      config.cast.tp_move_sweep = 4
      logic.set_config(config)
      logic.on_action(
        action({ category = 7, targets = { { id = 1, actions = { { param = 672, message = 43 } } } } }),
        10
      )
      assert.are.equal(0.5, cast_of(12).progress)
    end)

    it("clamps a hostile sweep instead of dividing by it", function()
      config.cast.tp_move_sweep = -5
      logic.set_config(config)
      assert.has_no.errors(function()
        logic.on_action(
          action({ category = 7, targets = { { id = 1, actions = { { param = 672, message = 43 } } } } }),
          10
        )
        cast_of(10)
      end)
    end)

    -- Belt as well as braces: a finish the packet stream never delivers must
    -- not leave a bar on screen forever.
    it("expires a bar nothing ever closed", function()
      logic.on_action(action(), 10)
      -- 8s cast + grace: gone well after, still there just past full.
      assert.is_true(cast_of(18.5).active)
      assert.is_false(cast_of(25).active)
    end)

    it("replaces a running cast when the target starts another", function()
      logic.on_action(action(), 10)
      logic.on_action(action({ targets = { { id = 1, actions = { { param = 1, message = 327 } } } } }), 14)
      local cast = cast_of(14)
      assert.are.equal("Cure", cast.name)
      assert.are.equal(0, cast.progress)
    end)

    it("drops the bar when the target changes", function()
      logic.on_action(action(), 10)
      acquire({ id = 555 })
      assert.is_false(cast_of(11).active)
    end)

    it("drops the bar when the target is lost", function()
      logic.on_action(action(), 10)
      logic.clear_target()
      assert.is_false(cast_of(11).active)
    end)

    it("drops the bar when the target dies", function()
      logic.on_action(action(), 10)
      acquire({ hpp = 0 })
      assert.is_false(cast_of(11).active)
    end)

    it("survives a malformed action table", function()
      assert.has_no.errors(function()
        logic.on_action({ category = 8 }, 10)
        logic.on_action({ actor_id = 100, category = 8, targets = {} }, 10)
        logic.on_action(nil, 10)
      end)
    end)

    it("shows a sample cast in preview so layout mode has the full stack", function()
      logic.set_preview(true)
      local cast = cast_of(0)
      assert.is_true(cast.active)
      assert.is_true(#cast.name > 0)
      assert.is_true(cast.progress > 0 and cast.progress < 1)
    end)

    describe("without the resources library", function()
      before_each(function()
        logic = new_logic(config, nil)
        acquire()
      end)

      it("never starts a bar", function()
        logic.on_action(action(), 10)
        assert.is_false(cast_of(10).active)
      end)
    end)
  end)

  describe("preview", function()
    it("shows a sample target while nothing is targeted", function()
      logic.set_preview(true)
      local texts = logic.texts()
      assert.are.equal("40%", texts.hp.text)
      assert.is_true(#texts.name.text > 0)
    end)

    it("restores the live target when preview ends", function()
      logic.set_target(mob({ hpp = 63, name = "Colibri" }))
      logic.set_preview(true)
      assert.are.equal("40%", logic.texts().hp.text)
      logic.set_preview(false)
      assert.are.equal("63%", logic.texts().hp.text)
      assert.are.equal("Colibri", logic.texts().name.text)
    end)
  end)
end)
