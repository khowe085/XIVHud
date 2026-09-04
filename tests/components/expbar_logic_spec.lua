local new_logic = require("components/expbar/logic")
local build_defaults = require("components/expbar/defaults")

local CHAR_STATS = 0x061
local CHAR_UPDATE = 0x063
local ACTION_MESSAGE = 0x02D

describe("expbar logic", function()
  local logic, config

  local function player(main_level, sub_level)
    return {
      main_job = "WAR",
      main_job_full = "Warrior",
      main_job_level = main_level,
      sub_job = sub_level and "SAM" or nil,
      sub_job_level = sub_level,
      job_points = { war = { jp = 342, cp = 12000 } },
    }
  end

  -- The one packet that carries experience, exemplar points and the key item
  -- that unlocks master levels.
  local function char_stats(overrides)
    local packet = {
      ["Current EXP"] = 1000,
      ["Required EXP"] = 5000,
      ["Master Level"] = 0,
      ["Master Breaker"] = false,
      ["Current Exemplar Points"] = 0,
      ["Required Exemplar Points"] = 2500,
    }
    for key, value in pairs(overrides or {}) do
      packet[key] = value
    end
    return packet
  end

  before_each(function()
    config = build_defaults(1920, 1080)
    logic = new_logic(config)
  end)

  describe("bar mode", function()
    it("fills with experience below the level cap", function()
      logic.set_player(player(75, 37))
      assert.are.equal("exp", logic.mode())
    end)

    it("fills with limit points at the cap without master breaker", function()
      logic.set_player(player(99, 49))
      assert.are.equal("limit", logic.mode())
    end)

    it("fills with exemplar points at the cap once master breaker is held", function()
      logic.set_player(player(99, 49))
      logic.on_packet(CHAR_STATS, char_stats({ ["Master Breaker"] = true }))
      assert.are.equal("ep", logic.mode())
    end)

    it("stays on experience below the cap even with master breaker", function()
      logic.set_player(player(75, 37))
      logic.on_packet(CHAR_STATS, char_stats({ ["Master Breaker"] = true }))
      assert.are.equal("exp", logic.mode())
    end)

    it("reads the master breaker bit as a number too", function()
      logic.set_player(player(99, 49))
      logic.on_packet(CHAR_STATS, char_stats({ ["Master Breaker"] = 1 }))
      assert.are.equal("ep", logic.mode())
    end)

    it("follows a job change without waiting for a packet", function()
      logic.set_player(player(99, 49))
      logic.on_packet(CHAR_STATS, char_stats({ ["Master Breaker"] = true }))
      logic.set_player(player(50, 25))
      assert.are.equal("exp", logic.mode())
    end)

    it("falls back to experience with no player at all", function()
      assert.are.equal("exp", logic.mode())
    end)
  end)

  describe("char stats", function()
    it("fills the experience bar from the packet", function()
      logic.set_player(player(75, 37))
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 2500, ["Required EXP"] = 5000 }))
      local current, required = logic.progress()
      assert.are.equal(2500, current)
      assert.are.equal(5000, required)
    end)

    it("fills the exemplar bar from the packet", function()
      logic.set_player(player(99, 49))
      logic.on_packet(
        CHAR_STATS,
        char_stats({
          ["Master Breaker"] = true,
          ["Current Exemplar Points"] = 1250,
          ["Required Exemplar Points"] = 5550,
        })
      )
      local current, required = logic.progress()
      assert.are.equal(1250, current)
      assert.are.equal(5550, required)
    end)

    it("keeps the master level for the header", function()
      logic.on_packet(CHAR_STATS, char_stats({ ["Master Level"] = 23 }))
      assert.are.equal(23, logic.master_level())
    end)

    it("reports the packet as a change", function()
      assert.is_true(logic.on_packet(CHAR_STATS, char_stats()))
    end)

    it("ignores a packet it could not parse", function()
      assert.is_false(logic.on_packet(CHAR_STATS, nil))
    end)

    it("ignores an unrelated packet id", function()
      assert.is_false(logic.on_packet(0x00A, char_stats()))
    end)

    it("wants only the three ids it reads", function()
      assert.is_true(logic.wants_chunk(CHAR_STATS))
      assert.is_true(logic.wants_chunk(CHAR_UPDATE))
      assert.is_true(logic.wants_chunk(ACTION_MESSAGE))
      assert.is_false(logic.wants_chunk(0x00A))
    end)
  end)

  describe("limit points and merits", function()
    local function char_update(overrides)
      local packet = {
        Order = 2,
        ["Limit Points"] = 4000,
        ["Merit Points"] = 12,
        ["Max Merit Points"] = 30,
      }
      for key, value in pairs(overrides or {}) do
        packet[key] = value
      end
      return packet
    end

    it("fills the limit bar toward the next merit at the cap", function()
      logic.set_player(player(99, 49))
      assert.is_true(logic.on_packet(CHAR_UPDATE, char_update()))
      local current, required = logic.progress()
      assert.are.equal(4000, current)
      assert.are.equal(10000, required)
    end)

    it("keeps the merit count for the header", function()
      logic.on_packet(CHAR_UPDATE, char_update({ ["Merit Points"] = 7 }))
      assert.are.equal(7, logic.merits())
    end)

    it("ignores the other orders of the same packet", function()
      -- Order 5 is the job point push, which get_player() already answers.
      assert.is_false(logic.on_packet(CHAR_UPDATE, { Order = 5, ["Limit Points"] = 1 }))
      assert.are.equal(0, logic.merits())
    end)
  end)

  describe("point gains between packets", function()
    local function gained(message, param1, param2)
      return logic.on_packet(ACTION_MESSAGE, { Message = message, ["Param 1"] = param1, ["Param 2"] = param2 }, 0)
    end

    before_each(function()
      logic.set_player(player(75, 37))
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 1000, ["Required EXP"] = 5000 }), 0)
    end)

    it("adds an experience gain to the bar", function()
      assert.is_true(gained(8, 250, 0))
      assert.are.equal(1250, (logic.progress()))
    end)

    it("takes the amount from the second parameter where the message does", function()
      -- Message 105 renders as "${actor} gains ${number2} experience points",
      -- so the points are Param 2 - both reference addons read Param 1 here.
      assert.is_true(gained(105, 3, 250))
      assert.are.equal(1250, (logic.progress()))
    end)

    it("counts an experience chain, which pointwatch never did", function()
      assert.is_true(gained(253, 250, 4))
      assert.are.equal(1250, (logic.progress()))
    end)

    it("wraps at the level up and waits for the packet to correct it", function()
      assert.is_true(gained(8, 4500, 0))
      assert.are.equal(500, (logic.progress()))
    end)

    it("adds limit points to the limit bar", function()
      logic.set_player(player(99, 49))
      logic.on_packet(
        CHAR_UPDATE,
        { Order = 2, ["Limit Points"] = 9500, ["Merit Points"] = 12, ["Max Merit Points"] = 30 }
      )
      assert.is_true(gained(371, 200, 0))
      assert.are.equal(9700, (logic.progress()))
    end)

    it("turns a full limit bar into a merit point", function()
      logic.set_player(player(99, 49))
      logic.on_packet(
        CHAR_UPDATE,
        { Order = 2, ["Limit Points"] = 9500, ["Merit Points"] = 12, ["Max Merit Points"] = 30 }
      )
      assert.is_true(gained(372, 700, 3))
      assert.are.equal(200, (logic.progress()))
      assert.are.equal(13, logic.merits())
    end)

    it("still wraps before the client has said how many merits are allowed", function()
      --[[ 0x063 is multiplexed over five orders and `last_incoming` is keyed by
           id alone, so the merit seed usually misses and `max_merits` stays
           unknown. Treating unknown as a cap of zero would park the bar at
           9999/10000 for the whole session. ]]
      logic.set_player(player(99, 49))
      assert.is_true(gained(371, 10500, 0))
      assert.are.equal(500, (logic.progress()))
      assert.are.equal(1, logic.merits())
    end)

    it("holds a capped merit character just short of the next merit", function()
      logic.set_player(player(99, 49))
      logic.on_packet(
        CHAR_UPDATE,
        { Order = 2, ["Limit Points"] = 9500, ["Merit Points"] = 30, ["Max Merit Points"] = 30 }
      )
      assert.is_true(gained(371, 700, 0))
      assert.are.equal(9999, (logic.progress()))
      assert.are.equal(30, logic.merits())
    end)

    it("adds exemplar points to the exemplar bar", function()
      logic.set_player(player(99, 49))
      logic.on_packet(
        CHAR_STATS,
        char_stats({
          ["Master Breaker"] = true,
          ["Current Exemplar Points"] = 1000,
          ["Required Exemplar Points"] = 5550,
        })
      )
      assert.is_true(gained(809, 250, 0))
      assert.are.equal(1250, (logic.progress()))
    end)

    it("wraps the exemplar bar at the master level", function()
      logic.set_player(player(99, 49))
      logic.on_packet(
        CHAR_STATS,
        char_stats({
          ["Master Breaker"] = true,
          ["Current Exemplar Points"] = 5500,
          ["Required Exemplar Points"] = 5550,
        })
      )
      assert.is_true(gained(810, 4, 100))
      assert.are.equal(50, (logic.progress()))
    end)

    it("ignores a message it does not track", function()
      assert.is_false(gained(1, 250, 0))
      assert.are.equal(1000, (logic.progress()))
    end)
  end)

  describe("rates", function()
    local function gain(message, amount, now)
      logic.on_packet(ACTION_MESSAGE, { Message = message, ["Param 1"] = amount, ["Param 2"] = 0 }, now)
    end

    -- The rate is only recomputed on a tick, at most once a second.
    local function rate_at(now)
      logic.tick(now)
      return logic.rate()
    end

    before_each(function()
      logic.set_player(player(75, 37))
    end)

    it("reports nothing until a sample is old enough to divide by", function()
      gain(8, 1000, 0)
      assert.are.equal(0, rate_at(20))
    end)

    it("extrapolates the window to an hour", function()
      gain(8, 1000, 0)
      assert.are.equal(60000, rate_at(60))
    end)

    it("sums samples inside the window", function()
      gain(8, 500, 0)
      gain(8, 500, 0)
      gain(8, 1000, 30)
      assert.are.equal(120000, rate_at(60))
    end)

    it("decays while nothing is earned", function()
      gain(8, 1000, 0)
      assert.are.equal(60000, rate_at(60))
      assert.is_true(rate_at(300) < 60000)
    end)

    it("forgets samples older than the window", function()
      gain(8, 1000, 0)
      assert.is_true(rate_at(60) > 0)
      assert.are.equal(0, rate_at(700))
    end)

    it("recomputes at most once a second", function()
      gain(8, 1000, 0)
      assert.are.equal(60000, rate_at(60))
      gain(8, 6000, 60)
      -- Same second: the new sample is registered but not yet divided out.
      assert.are.equal(60000, rate_at(60.5))
      assert.are.equal(413114, rate_at(61))
    end)

    it("follows the bar: capacity points at the cap", function()
      logic.set_player(player(99, 49))
      gain(718, 1000, 0)
      assert.are.equal(60000, rate_at(60))
    end)

    it("takes a capacity chain's points from the second parameter", function()
      -- 735 renders as "Capacity chain #${number}! ... gains ${number2}
      -- capacity points", so Param 1 is the chain number - which is what
      -- pointwatch's rate counts.
      logic.set_player(player(99, 49))
      logic.on_packet(ACTION_MESSAGE, { Message = 735, ["Param 1"] = 3, ["Param 2"] = 540 }, 0)
      assert.are.equal(32400, rate_at(60))
    end)

    it("survives a gain with no clock behind it", function()
      -- A nil timestamp would be a nil table key, which throws - inside the
      -- shared incoming chunk handler, where guard disables the whole dispatch
      -- after five failures.
      assert.has_no.errors(function()
        logic.on_packet(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 100, ["Param 2"] = 0 })
      end)
      assert.are.equal(0, rate_at(60))
    end)

    it("registers nothing for a gain of nothing, or of less", function()
      gain(8, 0, 0)
      gain(8, -5000, 0)
      assert.are.equal(0, rate_at(60))
    end)

    it("follows the bar: exemplar points under master levels", function()
      logic.set_player(player(99, 49))
      logic.on_packet(CHAR_STATS, char_stats({ ["Master Breaker"] = true }), 0)
      gain(809, 1000, 0)
      assert.are.equal(60000, rate_at(60))
    end)

    it("keeps the three streams apart", function()
      logic.set_player(player(99, 49))
      gain(8, 1000, 0)
      gain(809, 5000, 0)
      -- At the cap without master breaker the bar is limit points, so the
      -- header reads capacity - and nothing has been earned.
      assert.are.equal(0, rate_at(60))
    end)

    it("drops every sample on demand", function()
      gain(8, 1000, 0)
      assert.are.equal(60000, rate_at(60))
      logic.clear_rates()
      assert.are.equal(0, rate_at(61))
    end)
  end)
  describe("header", function()
    local function with_rate(message, amount)
      logic.on_packet(ACTION_MESSAGE, { Message = message, ["Param 1"] = amount, ["Param 2"] = 0 }, 0)
      logic.tick(60)
    end

    it("names the job pair, the job points, the merits and the experience rate", function()
      logic.set_player(player(75, 37))
      logic.on_packet(CHAR_UPDATE, { Order = 2, ["Limit Points"] = 0, ["Merit Points"] = 0, ["Max Merit Points"] = 30 })
      with_rate(8, 540)
      assert.are.equal("WAR75/SAM37 JP: 342 MP: 0 EXP/hr: 32.4k", logic.header())
    end)

    it("quotes capacity points at the cap without master levels", function()
      logic.set_player(player(99, 49))
      logic.on_packet(
        CHAR_UPDATE,
        { Order = 2, ["Limit Points"] = 0, ["Merit Points"] = 30, ["Max Merit Points"] = 30 }
      )
      with_rate(718, 135)
      assert.are.equal("WAR99/SAM49 JP: 342 MP: 30 CP/hr: 8.1k", logic.header())
    end)

    it("adds the master level and the exemplar rate under master levels", function()
      logic.set_player(player(99, 49))
      logic.on_packet(CHAR_STATS, char_stats({ ["Master Breaker"] = true, ["Master Level"] = 23 }))
      logic.on_packet(
        CHAR_UPDATE,
        { Order = 2, ["Limit Points"] = 0, ["Merit Points"] = 12, ["Max Merit Points"] = 30 }
      )
      with_rate(809, 210)
      assert.are.equal("WAR99/SAM49 (ML23) JP: 342 MP: 12 EP/hr: 12.6k", logic.header())
    end)

    it("shows dashes where there is no subjob", function()
      logic.set_player(player(75))
      assert.are.equal("WAR75/--- JP: 342 MP: 0 EXP/hr: 0.0k", logic.header())
    end)

    it("shows dashes where the client names the empty job instead", function()
      -- Job id 0 is `NON` in the resources, and get_player() is understood to
      -- report that rather than leaving the field out.
      local current = player(75)
      current.sub_job = "NON"
      current.sub_job_level = 0
      logic.set_player(current)
      assert.are.equal("WAR75/--- JP: 342 MP: 0 EXP/hr: 0.0k", logic.header())
    end)

    it("says nothing at all until the client names the player", function()
      assert.are.equal("", logic.header())
    end)

    it("finds the job points under the full job name too", function()
      local current = player(75, 37)
      current.job_points = { warrior = { jp = 500 } }
      logic.set_player(current)
      assert.is_true(logic.header():find("JP: 500", 1, true) ~= nil)
    end)

    it("reads no job points as none", function()
      local current = player(75, 37)
      current.job_points = nil
      logic.set_player(current)
      assert.is_true(logic.header():find("JP: 0", 1, true) ~= nil)
    end)

    it("rounds the rate down to a tenth of a thousand", function()
      logic.set_player(player(75, 37))
      with_rate(8, 16)
      assert.is_true(logic.header():find("EXP/hr: 0.9k", 1, true) ~= nil)
    end)
  end)

  --[[ measure.lua sizes the bar off a sample of the longest line the header can
       print. Nothing stops the format growing past that sample by itself, so
       the real header is driven to its widest here and measured against it. ]]
  describe("the widest line", function()
    local measure = require("components/expbar/measure")

    it("is no wider than what the bar is sized for", function()
      local current = player(99, 99)
      current.main_job = "WAR"
      current.sub_job = "SAM"
      current.job_points = { war = { jp = 9999 } }
      logic.set_player(current)
      logic.on_packet(CHAR_STATS, char_stats({ ["Master Breaker"] = true, ["Master Level"] = 50 }), 0)
      logic.on_packet(CHAR_UPDATE, { Order = 2, ["Merit Points"] = 999, ["Max Merit Points"] = 999 })
      -- A rate that has run into four digits of thousands.
      logic.on_packet(ACTION_MESSAGE, { Message = 809, ["Param 1"] = 166666, ["Param 2"] = 0 }, 0)
      logic.tick(60)

      local header = logic.header()
      assert.is_true(
        #header <= #measure.WIDEST,
        ("the header outgrew what the bar is sized for: %d characters, %q"):format(#header, header)
      )
    end)

    it("covers the sample layout mode draws too", function()
      logic.set_preview(true)
      assert.is_true(#logic.header() <= #measure.WIDEST)
    end)
  end)

  describe("the job icon", function()
    it("names the main job's glyph, lower case as the files are", function()
      logic.set_player(player(75, 37))
      assert.are.equal("war", logic.job_icon().name)
    end)

    it("follows a job change", function()
      logic.set_player(player(75, 37))
      local current = player(75, 37)
      current.main_job = "WHM"
      logic.set_player(current)
      assert.are.equal("whm", logic.job_icon().name)
    end)

    it("has nothing to draw before the client names a job", function()
      assert.is_nil(logic.job_icon())
    end)

    it("shows one in layout mode, matching the sample header", function()
      logic.set_preview(true)
      assert.are.equal("war", logic.job_icon().name)
    end)
  end)

  describe("geometry", function()
    it("stands the icon left of a flush header and bar", function()
      local geometry = logic.geometry(100, 200, 1)
      assert.are.same({ x = 100, y = 200 }, { x = geometry.icon.x, y = geometry.icon.y })
      -- The header clears the icon and its gap; the bar starts at the same x.
      assert.are.equal(117, geometry.header.x)
      assert.are.equal(200, geometry.header.y)
      assert.are.equal(117, geometry.background.x)
      assert.are.equal(211, geometry.background.y)
      assert.are.equal(217, geometry.background.width)
      assert.are.equal(5, geometry.background.height)
    end)

    it("spans both rows with the icon", function()
      -- Square, and as tall as the header, the gap and the bar together, so it
      -- ends on the bar's own foot rather than inside the header's row.
      local geometry = logic.geometry(100, 200, 1)
      assert.are.equal(16, geometry.icon.size)
      assert.are.equal(216, geometry.icon.y + geometry.icon.size)
      assert.are.equal(216, geometry.background.y + geometry.background.height)
    end)

    it("spans them at scale too", function()
      local geometry = logic.geometry(100, 200, 2)
      assert.are.equal(32, geometry.icon.size)
      assert.are.equal(232, geometry.icon.y + geometry.icon.size)
      assert.are.equal(232, geometry.background.y + geometry.background.height)
    end)

    it("grows the box for an icon taller than the rows it spans", function()
      -- A hand-edited size past the rows leaves them where they are and
      -- reserves the icon's own height, rather than letting a box that stops
      -- above it crop the glyph.
      config.job_icon.size = 30
      assert.are.equal(211, logic.geometry(100, 200, 1).background.y)
      local _, _, _, height = logic.bounds(100, 200, 1)
      assert.are.equal(30, height)
    end)

    it("insets the fill inside the frame", function()
      local geometry = logic.geometry(100, 200, 1)
      assert.are.equal(119, geometry.fill.x)
      assert.are.equal(211, geometry.fill.y)
    end)

    it("keeps the header still when there is no icon to draw", function()
      -- Before the client names a job the gap stays, rather than sliding the
      -- line and the bar left and back again as the player is filled in.
      assert.is_nil(logic.job_icon())
      assert.are.equal(117, logic.geometry(100, 200, 1).header.x)
      assert.are.equal(117, logic.geometry(100, 200, 1).background.x)
    end)

    it("multiplies every measure by the scale", function()
      local geometry = logic.geometry(100, 200, 2)
      assert.are.equal(134, geometry.header.x)
      assert.are.equal(222, geometry.background.y)
      assert.are.equal(434, geometry.background.width)
      assert.are.equal(10, geometry.background.height)
      assert.are.equal(138, geometry.fill.x)
      assert.are.equal(12, geometry.font_size)
    end)

    it("rounds the font size to a whole pixel, which is all a prim can draw", function()
      assert.are.equal(9, logic.geometry(100, 200, 1.5).font_size)
    end)

    it("reserves the whole box, from the origin it was given", function()
      local x, y, width, height = logic.bounds(100, 200, 1)
      assert.are.same({ 100, 200, 234, 16 }, { x, y, width, height })
      local _, _, wide, tall = logic.bounds(100, 200, 2)
      assert.are.same({ 468, 32 }, { wide, tall })
    end)
  end)

  describe("the bar", function()
    local function settle()
      local plan
      for _ = 1, 200 do
        plan = logic.tick(0)
      end
      return plan
    end

    before_each(function()
      logic.set_player(player(75, 37))
    end)

    it("eases toward the target rather than jumping to it", function()
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 5000, ["Required EXP"] = 5000 }))
      local plan = logic.tick(0)
      assert.is_true(plan.width > 0)
      assert.is_true(plan.width < 213)
    end)

    it("eases down as well as up, which a level up and a preview exit both do", function()
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 5000, ["Required EXP"] = 5000 }))
      settle()
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 0, ["Required EXP"] = 5000 }))
      local plan = logic.tick(0)
      assert.is_true(plan.width < 213, "the bar must come down")
      assert.is_true(plan.width > 0, "and come down one eased step, not jump")
      assert.are.equal(0, settle().width)
    end)

    it("never draws past the end of the frame", function()
      -- add_points wraps once, so two levels' worth in one message leaves more
      -- experience than the level takes.
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 0, ["Required EXP"] = 5000 }))
      logic.on_packet(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 12000, ["Param 2"] = 0 }, 0)
      assert.are.equal(213, settle().width)
    end)

    it("converges and then stops redrawing", function()
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 2500, ["Required EXP"] = 5000 }))
      local plan = settle()
      assert.are.equal(106, plan.width)
      assert.is_false(plan.dirty)
    end)

    it("hides the fill when there is nothing to draw", function()
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 0, ["Required EXP"] = 5000 }))
      assert.is_true(settle().hidden)
    end)

    it("draws nothing rather than dividing by a required of zero", function()
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 1000, ["Required EXP"] = 0 }))
      assert.is_true(settle().hidden)
    end)

    it("never draws a negative width", function()
      -- Unreachable from the gain messages, all of which are unsigned; the
      -- floor is here because a prim sized negatively is a silent failure.
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = -2500, ["Required EXP"] = 5000 }))
      assert.are.equal(0, settle().width)
    end)

    it("redraws when the mode changes under it", function()
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 2500, ["Required EXP"] = 5000 }))
      settle()
      logic.set_player(player(99, 49))
      assert.is_true(logic.tick(0).dirty)
    end)

    it("redraws everything after a layout change", function()
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 2500, ["Required EXP"] = 5000 }))
      settle()
      logic.invalidate()
      assert.is_true(logic.tick(0).dirty)
    end)

    it("redraws on a mode change that leaves the bar the same length", function()
      -- Half an experience level and half a merit fill the bar identically, so
      -- only the mode says the tint has to be repainted.
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 2500, ["Required EXP"] = 5000 }))
      settle()
      logic.on_packet(
        CHAR_UPDATE,
        { Order = 2, ["Limit Points"] = 5000, ["Merit Points"] = 0, ["Max Merit Points"] = 30 }
      )
      logic.set_player(player(99, 49))
      local plan = logic.tick(0)
      assert.are.equal(106, plan.width)
      assert.is_true(plan.dirty)
    end)

    it("carries the mode and its colour", function()
      local plan = logic.tick(0)
      assert.are.equal("exp", plan.mode)
      assert.are.same(config.fill_color, plan.color)
    end)

    it("carries the header for the frame", function()
      assert.are.equal(logic.header(), logic.tick(0).header)
    end)
  end)

  describe("a new character", function()
    it("keeps nothing of the last one", function()
      logic.set_player(player(75, 37))
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 2500, ["Required EXP"] = 5000 }), 0)
      logic.on_packet(
        CHAR_UPDATE,
        { Order = 2, ["Limit Points"] = 0, ["Merit Points"] = 12, ["Max Merit Points"] = 30 }
      )
      logic.on_packet(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 540, ["Param 2"] = 0 }, 0)
      logic.tick(60)

      logic.reset()

      assert.are.equal(0, logic.rate())
      assert.are.equal(0, logic.merits())
      assert.are.equal(0, (logic.progress()))
      assert.are.equal(0, logic.master_level())
      -- And the bar starts empty rather than easing down from their level.
      local plan = logic.tick(61)
      assert.are.equal(0, plan.width)
      assert.is_true(plan.dirty)
    end)
  end)

  describe("preview", function()
    it("fills the bar and the header with a sample", function()
      logic.set_preview(true)
      assert.is_true(logic.tick(0).width > 0)
      assert.is_true(logic.header():find("ML", 1, true) ~= nil)
    end)

    it("gives the live values back on the way out", function()
      logic.set_preview(true)
      logic.set_preview(false)
      assert.are.equal("", logic.header())
      assert.is_true(logic.tick(0).hidden)
    end)
  end)

  describe("commands", function()
    it("reports the bar, its numbers and the three rates", function()
      logic.set_player(player(75, 37))
      logic.on_packet(CHAR_STATS, char_stats({ ["Current EXP"] = 1000, ["Required EXP"] = 5000 }))
      local message, changed = logic.command({})
      assert.are.equal("expbar: experience 1000/5000 (20%) - EXP/hr 0.0k, CP/hr 0.0k, EP/hr 0.0k", message[1])
      assert.is_false(changed)
    end)

    --[[ The three master-level fields are the unverified half of this
         component: nothing outside a live client says `Master Breaker` and
         `Master Level` are the spellings Windower uses, and a wrong one reads
         as 0/false rather than as an error - a bar pinned in limit mode with
         nothing anywhere to say why. The status line is where that gets
         looked at. ]]
    it("reports what it read for the master levels, which nothing else can show", function()
      logic.set_player(player(99, 49))
      logic.on_packet(
        CHAR_STATS,
        char_stats({
          ["Master Breaker"] = true,
          ["Master Level"] = 23,
          ["Current Exemplar Points"] = 1250,
          ["Required Exemplar Points"] = 5550,
        })
      )
      assert.are.same({
        "expbar: exemplar points 1250/5550 (22%) - EXP/hr 0.0k, CP/hr 0.0k, EP/hr 0.0k",
        "expbar: master breaker yes, master level 23, merits 0/0",
      }, logic.command({}))
    end)

    it("says so when the client has claimed no master breaker", function()
      local message = logic.command({})
      assert.are.equal("expbar: master breaker no, master level 0, merits 0/0", message[2])
    end)

    it("drops the rate history on clear", function()
      logic.set_player(player(75, 37))
      logic.on_packet(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 540, ["Param 2"] = 0 }, 0)
      logic.tick(60)
      assert.is_true(logic.rate() > 0)
      local message, changed = logic.command({ "clear" })
      assert.are.equal("expbar rate history cleared", message)
      assert.is_false(changed)
      logic.tick(61)
      assert.are.equal(0, logic.rate())
    end)

    it("names what it does understand", function()
      local message = logic.command({ "wat" })
      assert.are.equal("expbar has no 'wat' command (clear)", message)
    end)
  end)
end)
