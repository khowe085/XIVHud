local new_spell_tier = require("lib/actionbar/spell_tier")

local BLM, NIN, BRD, SCH = 4, 13, 10, 20
local ADDENDUM_BLACK = 402

local function spells()
  local list = {
    { id = 144, en = "Fire", type = "BlackMagic", levels = { [BLM] = 13, [SCH] = 16 } },
    { id = 145, en = "Fire II", type = "BlackMagic", levels = { [BLM] = 38, [SCH] = 42 } },
    { id = 146, en = "Fire III", type = "BlackMagic", levels = { [BLM] = 62, [SCH] = 63 } },
    { id = 147, en = "Fire IV", type = "BlackMagic", levels = { [BLM] = 73, [SCH] = 73 }, requirements = 4 },
    { id = 148, en = "Fire V", type = "BlackMagic", levels = { [BLM] = 86, [SCH] = 87 }, requirements = 4 },
    { id = 253, en = "Sleep", type = "BlackMagic", levels = { [BLM] = 20 } },
    { id = 259, en = "Sleep II", type = "BlackMagic", levels = { [BLM] = 41 } },
    { id = 338, en = "Utsusemi: Ichi", type = "Ninjutsu", levels = { [NIN] = 12 } },
    { id = 339, en = "Utsusemi: Ni", type = "Ninjutsu", levels = { [NIN] = 37 } },
    { id = 340, en = "Utsusemi: San", type = "Ninjutsu", levels = { [NIN] = 100 } },
    { id = 373, en = "Foe Requiem VI", type = "BardSong", levels = { [BRD] = 67 } },
    { id = 374, en = "Foe Requiem VII", type = "BardSong", levels = { [BRD] = 76 } },
    { id = 896, en = "Shantotto", type = "Trust" },
    { id = 1019, en = "Shantotto II", type = "Trust" },
    -- Whom each can be aimed at, as the resources library names it: a set.
    { id = 261, en = "Warp", type = "BlackMagic", levels = { [BLM] = 17 }, targets = { Self = true } },
    { id = 262, en = "Warp II", type = "BlackMagic", levels = { [BLM] = 40 }, targets = { Party = true } },
    -- And as the raw data numbers it: Self is 1, Party 4.
    { id = 106, en = "Phalanx", type = "WhiteMagic", levels = { [BLM] = 1 }, targets = 1 },
    { id = 107, en = "Phalanx II", type = "WhiteMagic", levels = { [BLM] = 1 }, targets = 5 },
    -- A family with a tier missing from the table.
    { id = 9001, en = "Gap", type = "BlackMagic", levels = { [BLM] = 1 } },
    { id = 9003, en = "Gap III", type = "BlackMagic", levels = { [BLM] = 1 } },
  }
  local by_name = {}
  for _, spell in ipairs(list) do
    by_name[spell.en:lower()] = spell
  end
  return list, by_name
end

describe("the spell tier walk", function()
  local env, tier

  -- A binding flagged to step down, which is the only kind the walk reads.
  local function fire(tier_name, target)
    return { type = "ma", action = tier_name, target = target or "t", tier = "auto" }
  end

  --[[ The queue's two answers about a recast, by the spell's name. One in
       `on_recast` is far from ready: further off than the queue waits out,
       and refused if sent. One in `nearly_ready` would be refused too, but
       is not far off. ]]
  local function deps_over(by_name, overrides)
    local deps = {
      find_spell = function(name)
        return by_name[name:lower()]
      end,
      get_spells = function()
        return env.known
      end,
      get_player = function()
        return env.player
      end,
      far_off = function(record)
        return env.on_recast[record.action] == true
      end,
      refused = function(record)
        return env.on_recast[record.action] == true or env.nearly_ready[record.action] == true
      end,
      -- What a debug line quotes, which decides nothing: a recast's seconds,
      -- and what the queue is busy with in its own words.
      recast_left = function(record)
        return env.recasts[record.action] or 0
      end,
      doing = function()
        return env.doing
      end,
      note = function(line)
        env.notes[#env.notes + 1] = line
      end,
    }
    for key, value in pairs(overrides or {}) do
      deps[key] = value or nil
    end
    return deps
  end

  local function build(overrides)
    local list, by_name = spells()
    for _, spell in ipairs(list) do
      env.known[spell.id] = true
    end
    env.spells = by_name
    return new_spell_tier(deps_over(by_name, overrides))
  end

  before_each(function()
    env = {
      known = {},
      on_recast = {},
      nearly_ready = {},
      recasts = {},
      doing = "free",
      notes = {},
      player = { main_job_id = BLM, main_job_level = 99, buffs = {} },
    }
    tier = build()
  end)

  describe("the binding's flag", function()
    it("walks only a binding that says tier = auto, exactly", function()
      env.on_recast["Fire V"] = true
      for _, value in ipairs({ false, true, "on", "AUTO", 1 }) do
        local pressed = { type = "ma", action = "Fire V", target = "t", tier = value }
        assert.are.equal(pressed, tier.lower(pressed), tostring(value))
      end
      local plain = { type = "ma", action = "Fire V", target = "t" }
      assert.are.equal(plain, tier.lower(plain))
      assert.are.same({}, env.notes)
    end)

    it("is carried on by the tier that stands in, which may step down again", function()
      env.on_recast["Fire V"] = true
      local lowered = tier.lower(fire("Fire V"))
      assert.are.equal("auto", lowered.tier)
      env.on_recast["Fire IV"] = true
      assert.are.same(fire("Fire III"), tier.lower(lowered))
    end)
  end)

  describe("whether a binding has a tier to step down to", function()
    it("is so for a spell with a tier under it, flagged or not", function()
      assert.is_true(tier.has_lower(fire("Fire V")))
      assert.is_true(tier.has_lower({ type = "ma", action = "fire ii" }))
      assert.is_true(tier.has_lower(fire("Utsusemi: Ni", "me")))
    end)

    it("is not for a first tier, a Trust, or anything but a spell", function()
      for _, record in ipairs({
        fire("Fire"),
        fire("Utsusemi: Ichi", "me"),
        fire("Shantotto II", "me"),
        { type = "ja", action = "Fire V" },
        { type = "ma" },
      }) do
        assert.is_false(tier.has_lower(record), tostring(record.action))
      end
      assert.is_false(tier.has_lower(nil))
    end)

    it("is not where no tier under it can be aimed as it can", function()
      assert.is_false(tier.has_lower(fire("Warp II", "p1")))
      assert.is_false(tier.has_lower(fire("Phalanx II", "p1")))
    end)

    it("counts a tier past one the resources do not carry", function()
      assert.is_true(tier.has_lower(fire("Gap III")))
    end)

    it("cannot say of a name the resources do not know", function()
      assert.is_nil(tier.has_lower(fire("Fira V")))
    end)

    it("asks nothing of the client or the queue", function()
      tier = build({ far_off = false, refused = false, get_spells = false, get_player = false })
      assert.is_true(tier.has_lower(fire("Fire V")))
    end)
  end)

  describe("a spell that can go", function()
    it("goes as pressed, the same record", function()
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed))
      assert.are.same({}, env.notes)
    end)
  end)

  describe("a spell on its recast", function()
    it("gives way to the next tier down", function()
      env.on_recast["Fire V"] = true
      assert.are.same(fire("Fire IV"), tier.lower(fire("Fire V")))
    end)

    it("walks past each tier that is on its own recast", function()
      env.on_recast["Fire V"], env.on_recast["Fire IV"], env.on_recast["Fire III"] = true, true, true
      assert.are.same(fire("Fire II"), tier.lower(fire("Fire V")))
    end)

    it("reaches the first tier, which carries no numeral", function()
      env.on_recast["Sleep II"] = true
      assert.are.same(fire("Sleep", "stnpc"), tier.lower(fire("Sleep II", "stnpc")))
    end)

    it("goes as pressed when no tier under it can go", function()
      for _, name in ipairs({ "Fire V", "Fire IV", "Fire III", "Fire II", "Fire" }) do
        env.on_recast[name] = true
      end
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed))
    end)

    it("never walks up", function()
      env.on_recast["Fire"], env.on_recast["Fire II"] = true, true
      local first = fire("Fire")
      assert.are.equal(first, tier.lower(first), "nothing is under the first tier")
      local second = fire("Fire II")
      assert.are.equal(second, tier.lower(second), "and Fire III is above the second")
    end)

    it("keeps the press's target, or its lack of one, and its flag, and nothing else of it", function()
      env.on_recast["Fire V"] = true
      local labelled = { type = "ma", action = "Fire V", target = "bt", alias = "Nuke", icon = "fire", tier = "auto" }
      assert.are.same({ type = "ma", action = "Fire IV", target = "bt", tier = "auto" }, tier.lower(labelled))
      assert.are.same(
        { type = "ma", action = "Fire IV", tier = "auto" },
        tier.lower({ type = "ma", action = "Fire V", tier = "auto" })
      )
    end)

    it("reads the name in any case and answers the resource's own spelling", function()
      env.on_recast["fire v"] = true
      assert.are.same(fire("Fire IV"), tier.lower(fire("fire v")))
    end)

    it("passes a tier the resources do not carry", function()
      env.on_recast["Gap III"] = true
      assert.are.same(fire("Gap"), tier.lower(fire("Gap III")))
    end)

    it("goes as pressed while it is nearly ready, though the game will refuse it", function()
      env.nearly_ready["Fire V"] = true
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed))
      assert.are.same({}, env.notes)
    end)

    it("walks past a tier the game would refuse, however nearly ready", function()
      env.on_recast["Fire V"] = true
      env.nearly_ready["Fire IV"] = true
      assert.are.same(fire("Fire III"), tier.lower(fire("Fire V")))
    end)

    it("is no reason to step down where nothing answers for a recast", function()
      tier = build({ far_off = false, refused = false })
      env.on_recast["Fire V"] = true
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed))
      env.known[148] = nil
      assert.are.same(fire("Fire IV"), tier.lower(fire("Fire V")), "an unavailable one still gives way")
    end)
  end)

  describe("a spell that is not available", function()
    it("gives way when neither job has reached it, as under a level sync", function()
      env.player.main_job_level = 70
      assert.are.same(fire("Fire III"), tier.lower(fire("Fire V")))
    end)

    it("gives way when it has not been learned", function()
      env.known[148] = nil
      assert.are.same(fire("Fire IV"), tier.lower(fire("Fire V")))
    end)

    it("passes a lower tier that has not been learned either", function()
      env.known[148], env.known[147] = nil, false
      assert.are.same(fire("Fire III"), tier.lower(fire("Fire V")))
    end)

    it("gives way to what a scholar can cast without Addendum: Black", function()
      env.player.main_job_id = SCH
      assert.are.same(fire("Fire III"), tier.lower(fire("Fire V")))
      env.player.buffs = { ADDENDUM_BLACK }
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed))
    end)

    it("goes as pressed when nothing under it is available either", function()
      env.player.main_job_id = NIN
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed))
    end)
  end)

  describe("ninjutsu", function()
    before_each(function()
      env.player.main_job_id = NIN
    end)

    it("steps San to Ni to Ichi", function()
      env.on_recast["Utsusemi: San"] = true
      assert.are.same(fire("Utsusemi: Ni", "me"), tier.lower(fire("Utsusemi: San", "me")))
      env.on_recast["Utsusemi: Ni"] = true
      assert.are.same(fire("Utsusemi: Ichi", "me"), tier.lower(fire("Utsusemi: San", "me")))
    end)

    it("has nothing under Ichi", function()
      env.on_recast["Utsusemi: Ichi"] = true
      local pressed = fire("Utsusemi: Ichi", "me")
      assert.are.equal(pressed, tier.lower(pressed))
    end)
  end)

  describe("what is tiered", function()
    it("takes a song's numeral as far as VII", function()
      env.player.main_job_id = BRD
      env.on_recast["Foe Requiem VII"] = true
      assert.are.same(fire("Foe Requiem VI"), tier.lower(fire("Foe Requiem VII")))
    end)

    it("never takes one Trust for a tier of another", function()
      env.on_recast["Shantotto II"] = true
      local pressed = fire("Shantotto II", "me")
      assert.are.equal(pressed, tier.lower(pressed))
    end)

    it("is a spell alone", function()
      env.on_recast["Fire V"] = true
      for _, record in ipairs({
        { type = "ja", action = "Fire V", tier = "auto" },
        { type = "ws", action = "Fire V", target = "t", tier = "auto" },
        { type = "ma", tier = "auto" },
        { type = "ma", action = 5, tier = "auto" },
      }) do
        assert.are.equal(record, tier.lower(record))
      end
    end)

    it("leaves a name the resources do not know to the game", function()
      env.on_recast["Fira V"] = true
      local pressed = fire("Fira V")
      assert.are.equal(pressed, tier.lower(pressed))
    end)
  end)

  describe("a tier that cannot be aimed where the pressed spell can", function()
    it("never stands in, by the set of names the resources library gives", function()
      env.on_recast["Warp II"] = true
      local pressed = fire("Warp II", "stpc")
      assert.are.equal(pressed, tier.lower(pressed))
    end)

    it("never stands in, by the bitfield the raw data gives", function()
      env.on_recast["Phalanx II"] = true
      local pressed = fire("Phalanx II", "stpc")
      assert.are.equal(pressed, tier.lower(pressed))
    end)

    it("is passed by for the tier under it that can", function()
      env.spells["fire v"].targets = { Enemy = true }
      env.spells["fire iv"].targets = { Self = true }
      env.spells["fire iii"].targets = { Enemy = true, NPC = true }
      env.on_recast["Fire V"] = true
      assert.are.same(fire("Fire III"), tier.lower(fire("Fire V")), "one that takes more is still one that takes it")
    end)

    it("stands in where the two cannot be compared, the game having the last word", function()
      env.spells["fire v"].targets = { Enemy = true }
      env.spells["fire iv"].targets = 32
      env.on_recast["Fire V"] = true
      assert.are.same(fire("Fire IV"), tier.lower(fire("Fire V")))
      env.spells["fire iv"].targets = nil
      assert.are.same(fire("Fire IV"), tier.lower(fire("Fire V")))
    end)
  end)

  describe("with a client that cannot be read", function()
    it("leaves the press alone when nothing says what is learned", function()
      env.on_recast["Fire V"] = true
      env.known = nil
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed))
    end)

    it("leaves the press alone with no player", function()
      env.on_recast["Fire V"] = true
      env.player = nil
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed))
    end)
  end)

  describe("what it says for the debug log", function()
    -- Fire V ten seconds from ready, with 1.2s of a lock still to run.
    local function fire_v_far_off()
      env.on_recast["Fire V"] = true
      env.recasts["Fire V"], env.doing = 10, "lock 1.20s"
    end

    it("says where it was asked, what the recast had left and the queue was busy with, and what stands in", function()
      fire_v_far_off()
      tier.lower(fire("Fire V"), "at the press")
      assert.are.same({ "at the press: Fire V on recast 10.00s, lock 1.20s; down to Fire IV" }, env.notes)
    end)

    it("says each tier it passed by, and why", function()
      fire_v_far_off()
      env.on_recast["Fire IV"], env.recasts["Fire IV"] = true, 4.5
      env.known[146] = nil
      tier.lower(fire("Fire V"), "at the release")
      assert.are.same({
        "at the release: Fire V on recast 10.00s, lock 1.20s; Fire IV on recast 4.50s; "
          .. "Fire III not learned; down to Fire II",
      }, env.notes)
    end)

    it("says a spell that has not been learned", function()
      env.known[148] = nil
      tier.lower(fire("Fire V"), "at OK")
      assert.are.same({ "at OK: Fire V not learned; down to Fire IV" }, env.notes)
    end)

    it("says the level a job still needs, as under a level sync", function()
      env.player.main_job, env.player.main_job_level = "BLM", 70
      tier.lower(fire("Fire V"), "at the press")
      assert.are.same({
        "at the press: Fire V needs BLM 86 (on BLM 70); Fire IV needs BLM 73 (on BLM 70); down to Fire III",
      }, env.notes)
    end)

    it("says the Addendum a scholar has not got up", function()
      env.player.main_job_id, env.player.main_job = SCH, "SCH"
      tier.lower(fire("Fire IV"), "at the press")
      assert.are.same({ "at the press: Fire IV needs Addendum: Black (on SCH 99); down to Fire III" }, env.notes)
    end)

    it("says a tier that cannot be aimed as the pressed spell can", function()
      env.on_recast["Warp II"], env.recasts["Warp II"] = true, 20
      tier.lower(fire("Warp II", "stpc"), "at the press")
      assert.are.same({
        "at the press: Warp II on recast 20.00s, free; Warp cannot be aimed as Warp II; no tier under it can go",
      }, env.notes)
    end)

    it("says a press made while another spell is still casting, where no lock counts yet", function()
      env.on_recast["Fire V"] = true
      env.recasts["Fire V"], env.doing = 10, "casting"
      tier.lower(fire("Fire V"), "at the press")
      assert.are.same({ "at the press: Fire V on recast 10.00s, casting; down to Fire IV" }, env.notes)
    end)

    it("says a tier the name lookup has no spell for", function()
      env.on_recast["Gap III"], env.recasts["Gap III"] = true, 6
      tier.lower(fire("Gap III"), "at the press")
      assert.are.same({
        "at the press: Gap III on recast 6.00s, free; Gap II no such spell; down to Gap",
      }, env.notes)
    end)

    it("says when no tier under it can go", function()
      for _, name in ipairs({ "Fire V", "Fire IV", "Fire III", "Fire II", "Fire" }) do
        env.on_recast[name], env.recasts[name] = true, 9
      end
      tier.lower(fire("Fire V"), "at the press")
      assert.are.same({
        "at the press: Fire V on recast 9.00s, free; Fire IV on recast 9.00s; Fire III on recast 9.00s; "
          .. "Fire II on recast 9.00s; Fire on recast 9.00s; no tier under it can go",
      }, env.notes)
    end)

    it("says a spell it kept though its recast runs, being near enough ready", function()
      env.nearly_ready["Fire V"] = true
      env.recasts["Fire V"], env.doing = 3.5, "lock 2.00s"
      local pressed = fire("Fire V")
      assert.are.equal(pressed, tier.lower(pressed, "at the press"))
      assert.are.same({ "at the press: Fire V on recast 3.50s, lock 2.00s; near enough ready, kept" }, env.notes)
    end)

    it("leaves out where it was asked when no one says", function()
      fire_v_far_off()
      tier.lower(fire("Fire V"))
      assert.are.same({ "Fire V on recast 10.00s, lock 1.20s; down to Fire IV" }, env.notes)
    end)

    it("leaves out the seconds and the queue's state where nothing answers for them", function()
      tier = build({ recast_left = false, doing = false })
      env.on_recast["Fire V"], env.on_recast["Fire IV"] = true, true
      tier.lower(fire("Fire V"), "at the press")
      assert.are.same({ "at the press: Fire V on recast; Fire IV on recast; down to Fire III" }, env.notes)
    end)

    it("says nothing of a first tier, which has no walk to make", function()
      env.on_recast["Fire"] = true
      tier.lower(fire("Fire"))
      assert.are.same({}, env.notes)
    end)

    it("needs no one listening", function()
      tier = build({ note = false })
      env.on_recast["Fire V"] = true
      assert.are.same(fire("Fire IV"), tier.lower(fire("Fire V")))
    end)
  end)
end)
