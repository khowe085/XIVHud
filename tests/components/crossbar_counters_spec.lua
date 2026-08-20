local counters = require("components/crossbar/counters")

describe("crossbar counters", function()
  describe("stratagem charges", function()
    local function sch(level)
      return { main_job = "SCH", main_job_level = level, sub_job = "WAR", sub_job_level = 49 }
    end

    it("marks exactly the sixteen stratagem-consuming abilities", function()
      for _, name in ipairs({
        "Addendum: White",
        "Addendum: Black",
        "Penury",
        "Celerity",
        "Accession",
        "Rapture",
        "Altruism",
        "Tranquility",
        "Perpetuance",
        "Parsimony",
        "Alacrity",
        "Manifestation",
        "Ebullience",
        "Focalization",
        "Equanimity",
        "Immanence",
      }) do
        assert.is_true(counters.stratagem_ability(name), name)
      end
      -- Light and Dark Arts cost nothing - a count on them would be wrong.
      assert.is_false(counters.stratagem_ability("Light Arts"))
      assert.is_false(counters.stratagem_ability("Dark Arts"))
      assert.is_false(counters.stratagem_ability("Provoke"))
    end)

    it("draws nothing below SCH 10, one charge at 10", function()
      assert.is_nil(counters.stratagems(sch(9), 0))
      assert.same({ available = 1, max = 1 }, counters.stratagems(sch(10), 0))
    end)

    it("steps max charges at each level boundary", function()
      assert.equal(1, counters.stratagems(sch(29), 0).max)
      assert.equal(2, counters.stratagems(sch(30), 0).max)
      assert.equal(2, counters.stratagems(sch(49), 0).max)
      assert.equal(3, counters.stratagems(sch(50), 0).max)
      assert.equal(3, counters.stratagems(sch(69), 0).max)
      assert.equal(4, counters.stratagems(sch(70), 0).max)
      assert.equal(4, counters.stratagems(sch(89), 0).max)
      assert.equal(5, counters.stratagems(sch(90), 0).max)
    end)

    it("counts the job point gift for main SCH at 550 spent, not 549", function()
      local player = sch(99)
      player.job_points = { sch = { jp_spent = 549 } }
      assert.equal(5, counters.stratagems(player, 0).max)
      player.job_points.sch.jp_spent = 550
      assert.equal(6, counters.stratagems(player, 0).max)
    end)

    it("never grants the gift to sub-SCH", function()
      local player = {
        main_job = "RDM",
        main_job_level = 99,
        sub_job = "SCH",
        sub_job_level = 49,
        job_points = { sch = { jp_spent = 2100 } },
      }
      assert.equal(2, counters.stratagems(player, 0).max, "sub level 49 reads the sub column, no gift")
    end)

    it("draws on RDM/SCH from the sub job level", function()
      -- The named regression: the fork read the SCH level from the main job
      -- only, so on RDM/SCH the counter never drew.
      local player = { main_job = "RDM", main_job_level = 99, sub_job = "SCH", sub_job_level = 52 }
      assert.same({ available = 3, max = 3 }, counters.stratagems(player, 0))
    end)

    it("draws nothing without SCH anywhere", function()
      assert.is_nil(counters.stratagems({ main_job = "WAR", main_job_level = 99 }, 0))
    end)

    it("spends charges against the shared recast pool", function()
      -- 5 charges at L90: charge_time 48s. 100s of recast = ceil(100/48) = 3 used.
      assert.equal(2, counters.stratagems(sch(90), 100).available)
      assert.equal(4, counters.stratagems(sch(90), 1).available, "any recast at all spends one")
      assert.equal(5, counters.stratagems(sch(90), 0).available)
    end)

    it("clamps the raw negative when the gift lands mid-recast", function()
      -- Five L90 charges all spent (recast 240), then JP crosses 550: max
      -- becomes 6 and CHARGE_TIME[6] = 33, so used = ceil(240/33) = 8 and
      -- the raw 6 - 8 = -2 must display as 0, never a negative.
      local player = sch(90)
      player.job_points = { sch = { jp_spent = 550 } }
      assert.same({ available = 0, max = 6 }, counters.stratagems(player, 240))
    end)

    it("clamps at zero with the gift in both places", function()
      -- The fork's own display bug printed -1 here: six charges spent, gift
      -- left out of the minuend. 6 charges recharge at 33s each.
      local player = sch(99)
      player.job_points = { sch = { jp_spent = 550 } }
      local full = counters.stratagems(player, 6 * 33)
      assert.equal(0, full.available)
      assert.equal(6, full.max)
      assert.equal(5, counters.stratagems(player, 33).available, "gift counts in the minuend too")
    end)

    it("tolerates a player the client has not filled in", function()
      assert.is_nil(counters.stratagems(nil, 0))
      assert.is_nil(counters.stratagems({}, 0))
      assert.is_nil(counters.stratagems({ main_job = "SCH" }, 0), "no level yet")
    end)
  end)

  describe("ninja tool counts", function()
    it("maps each ninjutsu family to its tool", function()
      assert.equal(1179, counters.tool_for_spell(338), "Utsusemi: Ichi -> Shihei")
      assert.equal(1179, counters.tool_for_spell(339), "Utsusemi: Ni -> Shihei")
      assert.equal(1161, counters.tool_for_spell(320), "Katon: Ichi -> Uchitake")
      assert.equal(2970, counters.tool_for_spell(510), "Migawari: Ichi -> Mokujin")
      assert.is_nil(counters.tool_for_spell(1), "Cure is not a ninjutsu")
      assert.is_nil(counters.tool_for_spell(nil))
    end)

    it("maps the Corsair Quick Draw shots to their cards", function()
      assert.equal(2176, counters.tool_for_ability("Fire Shot"))
      assert.equal(2183, counters.tool_for_ability("Dark Shot"))
      assert.is_nil(counters.tool_for_ability("Provoke"))
      assert.is_nil(counters.tool_for_ability(nil))
    end)

    it("adds the master tool on main NIN only", function()
      local counts = { [1179] = 10, [2972] = 40 } -- Shihei + Shikanofuda
      assert.equal(50, counters.tool_display(1179, counts, "NIN").total)
      assert.equal(10, counters.tool_display(1179, counts, "RDM").total, "sub-NIN sums the plain tool alone")
    end)

    it("adds Trump Card for main COR the same way", function()
      local counts = { [2176] = 5, [2974] = 20 }
      assert.equal(25, counters.tool_display(2176, counts, "COR").total)
      assert.equal(5, counters.tool_display(2176, counts, "NIN").total)
    end)

    it("caps the display at 99+", function()
      assert.equal("99", counters.tool_display(1179, { [1179] = 99 }, "RDM").text)
      assert.equal("99+", counters.tool_display(1179, { [1179] = 100 }, "RDM").text)
    end)

    it("bands the colour on plain-alone vs total-with-masters", function()
      local plain_rich = { [1179] = 51 }
      assert.equal("green", counters.tool_display(1179, plain_rich, "NIN").color)
      local master_rich = { [1179] = 50, [2972] = 1 }
      assert.equal("yellow", counters.tool_display(1179, master_rich, "NIN").color, "only the total exceeds 50")
      assert.equal("red", counters.tool_display(1179, { [1179] = 50 }, "NIN").color)
      assert.equal(
        "red",
        counters.tool_display(1179, { [1179] = 50, [2972] = 1 }, "RDM").color,
        "master ignored off-main"
      )
    end)

    it("flags the zero state for the red X", function()
      local display = counters.tool_display(1179, {}, "NIN")
      assert.is_true(display.zero)
      assert.equal("0", display.text)
      assert.is_false(counters.tool_display(1179, { [1179] = 1 }, "NIN").zero)
    end)

    it("answers nothing for no tool", function()
      assert.is_nil(counters.tool_display(nil, {}, "NIN"))
    end)

    it("tracks exactly the tool and master item ids for re-reads", function()
      assert.is_true(counters.tracked_item(1179), "Shihei")
      assert.is_true(counters.tracked_item(2643), "Jinko, which has no master")
      assert.is_true(counters.tracked_item(2972), "Shikanofuda")
      assert.is_true(counters.tracked_item(2974), "Trump Card")
      assert.is_false(counters.tracked_item(4181), "Instant Warp is nobody's tool")
      assert.is_false(counters.tracked_item(nil))
    end)
  end)
end)
