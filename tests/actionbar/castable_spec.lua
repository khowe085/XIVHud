local castable = require("lib/actionbar/castable")

local WHM, BLM, SCH = 3, 4, 20
local ADDENDUM_WHITE, ADDENDUM_BLACK, ENLIGHTENMENT = 401, 402, 416

describe("castable", function()
  local function someone(overrides)
    local player = {
      main_job_id = BLM,
      main_job_level = 99,
      sub_job_id = WHM,
      sub_job_level = 49,
      buffs = {},
    }
    for key, value in pairs(overrides or {}) do
      player[key] = value
    end
    return player
  end

  local function available(spell, player)
    return castable.available(spell, castable.job_pair(player), player)
  end

  describe("the job pair", function()
    it("is the main job, marked as the main, then the sub the client names", function()
      assert.are.same({
        { id = BLM, level = 99, main = true },
        { id = WHM, level = 49, main = false },
      }, castable.job_pair(someone()))
    end)

    it("carries no sub the client has not named", function()
      assert.are.same({ { id = BLM, level = 99, main = true } }, castable.job_pair(someone({ sub_job_id = false })))
    end)

    it("is empty with no player to read", function()
      assert.are.same({}, castable.job_pair(nil))
    end)

    it("carries the names the client gives its jobs", function()
      assert.are.same({
        { id = BLM, name = "BLM", level = 99, main = true },
        { id = WHM, name = "WHM", level = 49, main = false },
      }, castable.job_pair(someone({ main_job = "BLM", sub_job = "WHM" })))
    end)
  end)

  describe("a buff", function()
    it("is found in the player's list, and nowhere else", function()
      assert.is_true(castable.has_buff(someone({ buffs = { 33, ADDENDUM_BLACK } }), ADDENDUM_BLACK))
      assert.is_false(castable.has_buff(someone(), ADDENDUM_BLACK))
      assert.is_false(castable.has_buff(nil, ADDENDUM_BLACK))
      assert.is_false(castable.has_buff({ buffs = "none" }, ADDENDUM_BLACK))
    end)
  end)

  describe("whether a job can supply a spell", function()
    local FIRE_V = { en = "Fire V", type = "BlackMagic", levels = { [BLM] = 86 } }

    it("takes one a job of the pair has reached", function()
      assert.is_true(available(FIRE_V, someone()))
      assert.is_true(available({ levels = { [WHM] = 49 } }, someone()))
    end)

    it("refuses one above both jobs, as under a level sync", function()
      assert.is_false(available(FIRE_V, someone({ main_job_level = 70 })))
      assert.is_false(available({ levels = { [WHM] = 50 } }, someone()))
      assert.is_false(available({ levels = { [SCH] = 10 } }, someone()))
    end)

    it("takes one with no levels at all, the client having listed it", function()
      assert.is_true(available({ en = "Fire V" }, someone()))
      assert.is_true(available(nil, someone()))
    end)

    it("takes a gift above the cap for a main job at the cap alone", function()
      local gift = { levels = { [BLM] = 100, [WHM] = 100 } }
      assert.is_true(available(gift, someone()))
      assert.is_false(available(gift, someone({ main_job_level = 98 })), "a gift is off while synced")
      assert.is_false(available(gift, someone({ main_job_id = SCH })), "and never the sub's")
    end)

    describe("for a scholar", function()
      local FIRE_IV = { en = "Fire IV", type = "BlackMagic", levels = { [SCH] = 73 }, requirements = 4 }
      local RAISE_II = { en = "Raise II", type = "WhiteMagic", levels = { [SCH] = 70, [WHM] = 56 }, requirements = 4 }

      local function scholar(buffs, sub)
        return someone({ main_job_id = SCH, sub_job_id = sub or false, buffs = buffs or {} })
      end

      it("wants Addendum: Black up for black magic that carries the bit", function()
        assert.is_false(available(FIRE_IV, scholar()))
        assert.is_false(available(FIRE_IV, scholar({ ADDENDUM_WHITE })))
        assert.is_true(available(FIRE_IV, scholar({ ADDENDUM_BLACK })))
      end)

      it("wants Addendum: White up for white magic that carries it", function()
        assert.is_false(available(RAISE_II, scholar()))
        assert.is_false(available(RAISE_II, scholar({ ADDENDUM_BLACK })))
        assert.is_true(available(RAISE_II, scholar({ ADDENDUM_WHITE })))
      end)

      it("has both opened by Enlightenment", function()
        assert.is_true(available(FIRE_IV, scholar({ ENLIGHTENMENT })))
        assert.is_true(available(RAISE_II, scholar({ ENLIGHTENMENT })))
      end)

      it("asks no Addendum for a spell without the bit", function()
        assert.is_true(available({ type = "BlackMagic", levels = { [SCH] = 62 }, requirements = 1 }, scholar()))
        assert.is_true(available({ type = "BlackMagic", levels = { [SCH] = 62 } }, scholar()))
      end)

      it("leaves the other job of the pair to cast it without one", function()
        local player = someone({ main_job_id = WHM, sub_job_id = SCH, sub_job_level = 49 })
        assert.is_true(available(RAISE_II, player), "a white mage needs no Addendum")
      end)
    end)
  end)

  describe("why no job can supply a spell", function()
    local FIRE_V = { en = "Fire V", type = "BlackMagic", levels = { [BLM] = 86 } }
    local FIRE_IV = { en = "Fire IV", type = "BlackMagic", levels = { [SCH] = 73 }, requirements = 4 }
    local RAISE_II = { en = "Raise II", type = "WhiteMagic", levels = { [SCH] = 70 }, requirements = 4 }

    -- A black mage with a white mage under it, as the client names them.
    local function named(overrides)
      local player = someone({ main_job = "BLM", sub_job = "WHM" })
      for key, value in pairs(overrides or {}) do
        player[key] = value
      end
      return player
    end

    local function scholar(buffs)
      return named({ main_job_id = SCH, main_job = "SCH", sub_job_id = false, buffs = buffs or {} })
    end

    local function scholar_at(level, buffs)
      local player = scholar(buffs)
      player.main_job_level = level
      return player
    end

    local function why_not(spell, player)
      return castable.why_not(spell, castable.job_pair(player), player)
    end

    it("has nothing to say of one that can be cast", function()
      assert.is_nil(why_not(FIRE_V, named()))
      assert.is_nil(why_not({ en = "Fire V" }, named()))
      assert.is_nil(why_not(nil, named()))
    end)

    it("names the level a job still needs, and the jobs it was asked of", function()
      assert.are.equal("needs BLM 86 (on BLM 70/WHM 49)", why_not(FIRE_V, named({ main_job_level = 70 })))
    end)

    it("names each job of the pair that could reach it", function()
      local both = { levels = { [BLM] = 86, [WHM] = 60 } }
      assert.are.equal("needs BLM 86 or WHM 60 (on BLM 70/WHM 49)", why_not(both, named({ main_job_level = 70 })))
    end)

    it("says when it is a spell of neither job", function()
      assert.are.equal("no spell of BLM 99/WHM 49", why_not({ levels = { [SCH] = 10 } }, named()))
      assert.are.equal("no spell of BLM 99", why_not({ levels = { [SCH] = 10 } }, named({ sub_job_id = false })))
    end)

    it("names the Addendum a scholar has not got up", function()
      assert.are.equal("needs Addendum: Black (on SCH 99)", why_not(FIRE_IV, scholar()))
      assert.are.equal("needs Addendum: White (on SCH 99)", why_not(RAISE_II, scholar({ ADDENDUM_BLACK })))
      assert.is_nil(why_not(FIRE_IV, scholar({ ENLIGHTENMENT })))
    end)

    it("names the level too where the Addendum alone would not be enough", function()
      local synced = scholar()
      synced.main_job_level = 60
      assert.are.equal("needs Addendum: Black and SCH 73 (on SCH 60)", why_not(FIRE_IV, synced))
      assert.are.equal("needs SCH 73 (on SCH 60)", why_not(FIRE_IV, scholar_at(60, { ADDENDUM_BLACK })))
      local gift = { type = "BlackMagic", levels = { [SCH] = 100 }, requirements = 4 }
      assert.are.equal("needs Addendum: Black and SCH 99 as the main job (on SCH 60)", why_not(gift, synced))
    end)

    it("says a gift wants its job as the main one, at the cap", function()
      assert.are.equal(
        "needs BLM 99 as the main job (on BLM 98/WHM 49)",
        why_not({ levels = { [BLM] = 100 } }, named({ main_job_level = 98 }))
      )
      assert.are.equal(
        "needs WHM 99 as the main job (on BLM 99/WHM 49)",
        why_not({ levels = { [WHM] = 100 } }, named())
      )
    end)

    it("falls back on a job's number where the client gave it no name", function()
      assert.are.equal("needs job4 86 (on job4 70/job3 49)", why_not(FIRE_V, someone({ main_job_level = 70 })))
    end)

    it("says there is no job where the client named none", function()
      assert.are.equal("no job to cast it", castable.why_not(FIRE_V, {}, nil))
    end)

    it("never disagrees with whether one can", function()
      local spells =
        { FIRE_V, FIRE_IV, RAISE_II, { levels = { [BLM] = 100, [WHM] = 100 } }, { levels = { [WHM] = 50 } } }
      local players = {
        named(),
        named({ main_job_level = 70 }),
        scholar(),
        scholar({ ADDENDUM_BLACK }),
        named({ main_job_id = SCH }),
      }
      for _, spell in ipairs(spells) do
        for _, player in ipairs(players) do
          assert.are.equal(available(spell, player), why_not(spell, player) == nil)
        end
      end
    end)
  end)
end)
