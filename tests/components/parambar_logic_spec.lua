local new_logic = require("components/parambar/logic")
local parambar_defaults = require("components/parambar/defaults")

describe("parambar logic", function()
  local config, logic, vitals

  -- Runs frames until every bar has stopped animating, so assertions can talk
  -- about the settled picture. Guards against the runaway-easing bug.
  local function settle(limit)
    local plan
    for _ = 1, limit or 200 do
      plan = logic.tick()
      if not (plan.hp.dirty or plan.mp.dirty or plan.tp.dirty) then
        return plan
      end
    end
    error("bars never converged")
  end

  --[[ The widget hands the whole vitals table over every frame - lib/player owns
       the read interval and the event reconciliation now - so these track it
       here and push all of it on every change, which keeps a spec about one
       vital readable. ]]
  local function set_all(table)
    vitals = table or {}
    logic.set_vitals(table)
  end

  local function set(key, value)
    vitals[key] = value
    logic.set_vitals(vitals)
  end

  -- One 0x028 of the player's own swings, as the entry point decodes it.
  -- One call is one round, whatever it carries.
  local function swings(messages, at)
    local actions = {}
    for index, message in ipairs(messages) do
      actions[index] = { message = message }
    end
    logic.on_action({ actor_id = 7, targets = { { id = 99, actions = actions } } }, 7, at or 0)
  end

  before_each(function()
    config = parambar_defaults(1920, 1080)
    logic = new_logic(config)
    vitals = {}
  end)

  describe("vitals", function()
    it("starts empty", function()
      local plan = settle()
      assert.are.equal(0, plan.hp.width)
      assert.is_true(plan.hp.hidden)
      assert.are.equal("0", plan.hp.text)
    end)

    -- The client fills its vitals table in field by field, so a bar can read 0
    -- for a frame or two after login while its neighbours are already current.
    it("picks up a vital the client filled in later", function()
      logic.set_vitals({ hp = 1200, hpp = 100, mp = 0, mpp = 0, tp = 0 })
      assert.are.equal("0", settle().mp.text)

      logic.set_vitals({ hp = 1200, hpp = 100, mp = 300, mpp = 60, tp = 0 })
      assert.are.equal("300", settle().mp.text)
    end)

    --[[ The widget is told the vitals every frame - lib/player owns the read
         interval and the reconciliation now - so a set that changed nothing
         must not cost a redraw sixty times a second. ]]
    it("does not redraw a bar whose numbers did not move", function()
      logic.set_vitals({ hp = 1200, hpp = 100, mp = 300, mpp = 60, tp = 0 })
      settle()
      logic.set_vitals({ hp = 1200, hpp = 100, mp = 300, mpp = 60, tp = 0 })
      local plan = logic.tick()
      assert.is_false(plan.hp.dirty)
      assert.is_false(plan.mp.dirty)
      assert.is_false(plan.tp.dirty)
    end)

    it("zeroes a vital the table no longer mentions, being a replacement", function()
      set_all({ hp = 1200, hpp = 100, mp = 300, mpp = 60, tp = 250 })
      settle()
      set_all({ hp = 1200, hpp = 100 })
      assert.are.equal("0", settle().mp.text)
    end)

    it("takes the whole vitals table from the player", function()
      set_all({ hp = 1200, hpp = 100, mp = 300, mpp = 60, tp = 250 })
      local plan = settle()
      assert.are.equal("1200", plan.hp.text)
      assert.are.equal("300", plan.mp.text)
      assert.are.equal("250", plan.tp.text)
    end)

    it("ignores a key the vitals table should not carry", function()
      logic.set_vitals({ hp = 600, hpp = 50, wisdom = 5 })
      local plan = settle()
      assert.are.equal("600", plan.hp.text)
      assert.are.equal(66, plan.hp.width)
    end)

    it("survives a nil vitals table", function()
      assert.has_no.errors(function()
        logic.set_vitals(nil)
      end)
    end)
  end)

  describe("bar widths", function()
    it("fills proportionally to the percent, floored", function()
      set_all({ hp = 100, hpp = 100, mp = 100, mpp = 50, tp = 0 })
      local plan = settle()
      assert.are.equal(132, plan.hp.width)
      assert.are.equal(66, plan.mp.width)
    end)

    it("derives the TP bar from tenths of TP, capped at a full bar", function()
      set("tp", 500)
      assert.are.equal(50, logic.tpp())
      set("tp", 3000)
      assert.are.equal(100, logic.tpp())
      local plan = settle()
      assert.are.equal(132, plan.tp.width)
    end)

    it("hides a bar that has emptied and shows it again when it refills", function()
      set_all({ hp = 100, hpp = 100 })
      assert.is_false(settle().hp.hidden)
      set("hpp", 0)
      assert.is_true(settle().hp.hidden)
      set("hpp", 100)
      assert.is_false(settle().hp.hidden)
    end)
  end)

  describe("easing", function()
    it("grows a tenth of the remaining distance per frame, rounded up", function()
      set_all({ hp = 1000, hpp = 100 })
      assert.are.equal(14, logic.tick().hp.width)
      assert.are.equal(26, logic.tick().hp.width)
    end)

    it("shrinks the same way", function()
      set_all({ hp = 1000, hpp = 100 })
      settle()
      set("hpp", 0)
      assert.are.equal(118, logic.tick().hp.width)
      assert.are.equal(106, logic.tick().hp.width)
    end)

    it("converges exactly on the target rather than overshooting", function()
      set_all({ hp = 1000, hpp = 100 })
      assert.are.equal(132, settle().hp.width)
      set("hpp", 0)
      assert.are.equal(0, settle().hp.width)
    end)

    it("stops being dirty once it converges", function()
      set_all({ hp = 1000, hpp = 100 })
      settle()
      assert.is_false(logic.tick().hp.dirty, "a converged bar must not re-ease every frame")
      assert.is_false(logic.tick().mp.dirty)
      assert.is_false(logic.tick().tp.dirty)
    end)

    it("becomes dirty again when a value changes", function()
      set_all({ hp = 1000, hpp = 100 })
      settle()
      set("hpp", 50)
      assert.is_true(logic.tick().hp.dirty)
      assert.is_false(logic.tick().mp.dirty, "only the bar that changed")
    end)

    it("re-eases towards a new width when the metrics change mid-animation", function()
      set_all({ hp = 1000, hpp = 100 })
      settle()
      logic.command({ "width", "40" })
      assert.are.equal(40, settle().hp.width)
    end)
  end)

  describe("text colouring", function()
    local function hp_state(hpp)
      set("hpp", hpp)
      return settle().hp.color_state
    end

    it("bands HP on strictly-less-than thresholds", function()
      assert.are.equal("normal", hp_state(75))
      assert.are.equal("yellow", hp_state(74))
      assert.are.equal("yellow", hp_state(50))
      assert.are.equal("orange", hp_state(49))
      assert.are.equal("orange", hp_state(25))
      assert.are.equal("red", hp_state(24))
      assert.are.equal("red", hp_state(0))
    end)

    it("bands MP the same way", function()
      set("mpp", 24)
      assert.are.equal("red", settle().mp.color_state)
      set("mpp", 80)
      assert.are.equal("normal", settle().mp.color_state)
    end)

    it("resolves the band to the colour configured for it", function()
      set("hpp", 10)
      assert.are.same(config.low_hp_colors.red, settle().hp.color)
      set("hpp", 100)
      local normal = settle().hp.color
      assert.are.same({ r = config.text_color.r, g = config.text_color.g, b = config.text_color.b }, normal)
    end)

    it("never bands TP, however low it is", function()
      set("tp", 0)
      assert.are.equal("normal", settle().tp.color_state)
    end)

    it("highlights TP from exactly 1000", function()
      set("tp", 999)
      assert.are.equal("normal", settle().tp.color_state)
      set("tp", 1000)
      assert.are.equal("full_tp", settle().tp.color_state)
      assert.are.same(config.full_tp_color, settle().tp.color)
      set("tp", 1001)
      assert.are.equal("full_tp", settle().tp.color_state)
    end)
  end)

  describe("bar dimming", function()
    it("dims only the TP bar below full TP", function()
      set_all({ hp = 1, hpp = 100, mp = 1, mpp = 100, tp = 999 })
      local plan = settle()
      assert.are.equal(180, plan.tp.alpha)
      assert.are.equal(255, plan.hp.alpha, "HP must not be dimmed as a side effect")
      assert.are.equal(255, plan.mp.alpha)
    end)

    it("brightens the TP bar at full TP", function()
      set("tp", 1000)
      assert.are.equal(255, settle().tp.alpha)
    end)

    it("leaves the TP bar bright when dimming is turned off", function()
      config.dim_tp_bar = false
      set("tp", 500)
      assert.are.equal(255, settle().tp.alpha)
    end)
  end)

  describe("death reconciliation", function()
    it("shows zero HP when the percent says dead, whatever the absolute stream said", function()
      set_all({ hp = 1200, hpp = 100 })
      settle()
      set("hpp", 0)
      local plan = settle()
      assert.are.equal("0", plan.hp.text)
      assert.are.equal("red", plan.hp.color_state)
    end)

    it("does the same for MP", function()
      set_all({ mp = 900, mpp = 100 })
      settle()
      set("mpp", 0)
      assert.are.equal("0", settle().mp.text)
    end)

    it("takes both streams together", function()
      logic.set_vitals({ hp = 1200, hpp = 0, mp = 0, mpp = 0, tp = 0 })
      logic.set_vitals({ hp = 500, hpp = 100, mp = 0, mpp = 0, tp = 0 })
      assert.are.equal("500", settle().hp.text)
    end)
  end)

  describe("metrics", function()
    it("uses the full-size set by default", function()
      local metrics = logic.metrics()
      assert.are.equal(132, metrics.bar_width)
      assert.are.equal(18, metrics.spacing)
      assert.are.equal(472, metrics.total_width)
      assert.are.equal("bar_bg.png", metrics.background)
    end)

    it("survives a hand-edited config that put a scalar where a metric set goes", function()
      config.bar = 5
      assert.has_no.errors(function()
        logic.tick()
      end)
      assert.are.equal(0, logic.metrics().bar_width)
    end)

    it("switches to the compact set and its own image width", function()
      config.compact = true
      local metrics = logic.metrics()
      assert.are.equal(116, metrics.bar_width)
      assert.are.equal(16, metrics.spacing)
      assert.are.equal(421, metrics.total_width, "the compact image is 421px wide")
      assert.are.equal("bar_compact.png", metrics.background)
    end)
  end)

  describe("geometry", function()
    it("lays the bars and numbers out against the background frame", function()
      local geometry = logic.geometry(100, 200, 1)
      assert.are.same({ x = 100, y = 217, width = 472, height = 24 }, geometry.background)
      assert.are.equal(115, geometry.bars[1].x)
      assert.are.equal(219, geometry.bars[1].y)
      assert.are.equal(8, geometry.bars[1].height)
      assert.are.equal(275, geometry.bars[2].x)
      assert.are.equal(435, geometry.bars[3].x)
      assert.are.equal(165, geometry.texts[1].x)
      assert.are.equal(219, geometry.texts[1].y)
      assert.are.equal(330, geometry.texts[2].x)
      assert.are.equal(490, geometry.texts[3].x)
      assert.are.equal(14, geometry.font_size)
    end)

    it("moves the fills with the bar offset and the numbers with the text offset", function()
      config.bar.offset = 5
      config.text_offset = 7
      local geometry = logic.geometry(100, 200, 1)
      assert.are.equal(120, geometry.bars[1].x)
      assert.are.equal(172, geometry.texts[1].x)
    end)

    it("multiplies every offset, size and font by the scale", function()
      local geometry = logic.geometry(100, 200, 2)
      assert.are.same({ x = 100, y = 235, width = 944, height = 48 }, geometry.background)
      assert.are.equal(130, geometry.bars[1].x)
      assert.are.equal(239, geometry.bars[1].y)
      assert.are.equal(16, geometry.bars[1].height)
      assert.are.equal(230, geometry.texts[1].x)
      assert.are.equal(28, geometry.font_size)
    end)

    it("rounds the font size to a whole number", function()
      assert.are.equal(18, logic.geometry(0, 0, 1.25).font_size)
    end)

    -- With the accuracy row on, the box covers the row as well as the frame;
    -- the plain frame bounds are pinned under "accuracy geometry" below.
    it("reports bounds covering the frame and the row above it", function()
      assert.are.same({ 100, 200, 510, 41 }, { logic.bounds(100, 200, 1) })
      assert.are.same({ 100, 200, 764.5, 62 }, { logic.bounds(100, 200, 1.5) })
    end)

    it("scales the eased fill width too", function()
      set_all({ hp = 100, hpp = 100 })
      assert.are.equal(264, logic.geometry(0, 0, 2).fill_width(settle().hp.width))
    end)
  end)

  describe("preview", function()
    it("shows sample vitals so an empty HUD can still be positioned", function()
      logic.set_preview(true)
      local plan = settle()
      assert.are.equal(99, plan.hp.width)
      assert.are.equal(66, plan.mp.width)
      assert.are.equal("full_tp", plan.tp.color_state)
    end)

    it("restores the live values on the way out", function()
      set_all({ hp = 42, hpp = 10, mp = 0, mpp = 0, tp = 0 })
      settle()
      logic.set_preview(true)
      settle()
      logic.set_preview(false)
      local plan = settle()
      assert.are.equal("42", plan.hp.text)
      assert.are.equal(13, plan.hp.width)
    end)

    it("keeps recording live changes while previewing", function()
      logic.set_preview(true)
      set("hp", 77)
      set("hpp", 100)
      logic.set_preview(false)
      assert.are.equal("77", settle().hp.text)
    end)
  end)

  describe("accuracy", function()
    it("reads the window as a line above the bars", function()
      swings({ 1, 1, 15 })
      assert.are.equal("Acc: 2 / 3 (67%) / --s", logic.tick(0).accuracy.text)
    end)

    it("says so plainly when nothing has swung yet", function()
      assert.are.equal("Acc: 0 / 0 (--%) / --s", logic.tick(0).accuracy.text)
    end)

    --[[ The measured interval between rounds, not a computed one: nothing
         in the client reports haste, so the arithmetic would be guessing at
         its largest term. One decimal - the tenth is the resolution anyone
         reads a delay at. ]]
    it("draws the measured delay at the end of the line", function()
      swings({ 1 }, 0)
      swings({ 15 }, 2.4)
      assert.are.equal("Acc: 1 / 2 (50%) / 2.4s", logic.tick(2.4).accuracy.text)
    end)

    it("rounds the delay to a tenth of a second", function()
      swings({ 1 }, 0)
      swings({ 1 }, 2.46)
      assert.are.equal("Acc: 2 / 2 (100%) / 2.5s", logic.tick(2.46).accuracy.text)
    end)

    it("says nothing for a delay until two rounds have landed", function()
      swings({ 1, 1 }, 0)
      assert.are.equal("Acc: 2 / 2 (100%) / --s", logic.tick(0).accuracy.text)
    end)

    it("drops swings that have aged out of the window", function()
      swings({ 1 }, 0)
      assert.are.equal("Acc: 0 / 0 (--%) / --s", logic.tick(20).accuracy.text)
    end)

    it("takes its window length from the config", function()
      config.accuracy.window_seconds = 30
      swings({ 1 }, 0)
      assert.are.equal("Acc: 1 / 1 (100%) / --s", logic.tick(20).accuracy.text)
    end)

    it("pushes the line only on the frames its text changes", function()
      swings({ 1 })
      assert.is_true(logic.tick(0).accuracy.dirty)
      assert.is_false(logic.tick(0).accuracy.dirty)
      swings({ 15 })
      assert.is_true(logic.tick(0).accuracy.dirty)
    end)

    it("keeps recording while switched off, so a re-enable is not blank", function()
      config.accuracy.enabled = false
      logic.set_config(config)
      swings({ 1, 15 })
      config.accuracy.enabled = true
      logic.set_config(config)
      assert.are.equal("Acc: 1 / 2 (50%) / --s", logic.tick(0).accuracy.text)
    end)

    it("answers whether the row is drawn at all, for the prims", function()
      assert.is_true(logic.accuracy_enabled())
      config.accuracy.enabled = false
      logic.set_config(config)
      assert.is_false(logic.accuracy_enabled())
    end)

    it("empties the window on demand, for the reset verb", function()
      swings({ 1, 15 })
      logic.reset_accuracy()
      assert.are.equal("Acc: 0 / 0 (--%) / --s", logic.tick(0).accuracy.text)
    end)

    it("shows a sample while previewing, so the row can be positioned", function()
      logic.set_preview(true)
      assert.are.equal("Acc: 7 / 9 (78%) / 2.4s", logic.tick(0).accuracy.text)
    end)

    it("ignores an accuracy block a hand edit left as something else", function()
      config.accuracy = "on"
      logic.set_config(config)
      assert.is_false(logic.accuracy_enabled())
    end)
  end)

  describe("accuracy geometry", function()
    it("stands the row above the bars and pushes the frame down by it", function()
      local geometry = logic.geometry(100, 200, 1)
      assert.are.equal(200, geometry.accuracy.y)
      assert.are.equal(8, geometry.accuracy.font_size)
      -- The frame, the fills and the numbers all sit below the row.
      assert.are.equal(217, geometry.background.y)
      assert.are.equal(219, geometry.bars[1].y)
      assert.are.equal(219, geometry.texts[1].y)
    end)

    -- The row starts where the TP bar starts, since that is the bar it is
    -- about.
    it("lines the row up with the TP bar it reports on", function()
      local geometry = logic.geometry(100, 200, 1)
      assert.are.equal(geometry.bars[3].x, geometry.accuracy.x)
    end)

    it("moves the row with its own offset, leaving the numbers alone", function()
      config.accuracy.offset = 20
      local geometry = logic.geometry(100, 200, 1)
      assert.are.equal(455, geometry.accuracy.x)
      assert.are.equal(490, geometry.texts[3].x)
    end)

    --[[ The row is text and nothing else (Kevin, 2026-09-27): no button, so
         no rect and nothing for the mouse to find. ]]
    it("draws no button beside the line", function()
      assert.is_nil(logic.geometry(100, 200, 1).reset_button)
    end)

    --[[ The row is kept inside the box `get_bounds` reports, horizontally as
         well as vertically: a negative offset pulls it back to the origin
         rather than outside core's clamp. ]]
    it("never draws the row left of the origin", function()
      config.accuracy.offset = -1000
      assert.are.equal(100, logic.geometry(100, 200, 1).accuracy.x)
    end)

    --[[ FOUR digits: the window goes to 600 seconds, and ten minutes of a
         dual-wielding multi-attack job is well past a thousand swings. The
         reservation and the format string are two constants that have to
         agree, so this drives the REAL formatter to its longest line and
         measures what comes out against the box that has to cover it. ]]
    it("reserves room for the longest line the formatter can produce", function()
      local many = {}
      for index = 1, 4000 do
        -- All hits: four digits both sides and a three-digit percentage.
        many[index] = 1
      end
      swings(many, 0)
      -- A second round, as far from the first as the window allows, so the
      -- delay reads at its widest too.
      swings({ 1 }, 600)
      config.accuracy.window_seconds = 600
      local line = logic.tick(600).accuracy.text
      assert.are.equal("Acc: 4001 / 4001 (100%) / 600.0s", line)
      config.accuracy.offset = 200
      local geometry = logic.geometry(100, 200, 1)
      local drawn = #line * config.accuracy.font_size * config.accuracy.text_width_ratio
      local right = select(3, logic.bounds(100, 200, 1)) + 100
      assert.is_true(geometry.accuracy.x + drawn <= right, "the line reaches past the bounds: " .. line)
    end)

    it("keeps the row's footprint still as the numbers in the line change", function()
      config.accuracy.offset = 200
      local before = select(3, logic.bounds(100, 200, 1))
      swings({ 1, 1, 1, 15, 15 })
      assert.are.equal(before, select(3, logic.bounds(100, 200, 1)))
    end)

    --[[ The clearance itself, rather than the pixel the frame happens to
         land on: `bar_gap` exists because a live client showed the line
         drawing ON the bar art, so the invariant is that the frame starts
         below where the line is estimated to END. A literal alone would
         just get updated if someone retuned the row back into overlap. ]]
    it("keeps the whole line clear of the bar art", function()
      local geometry = logic.geometry(100, 200, 1)
      local line_height = config.accuracy.font_size * config.accuracy.text_height_ratio
      assert.is_true(geometry.background.y >= geometry.accuracy.y + line_height)
    end)

    --[[ `bar_gap` is the clearance between the row and the bar art - the
         knob for a line sitting on it - and it is the only thing that moves
         the frame down. ]]
    it("lifts the row off the bar art without moving the line", function()
      local before = logic.geometry(100, 200, 1)
      config.accuracy.bar_gap = 12
      local after = logic.geometry(100, 200, 1)
      assert.are.equal(before.background.y + 5, after.background.y)
      assert.are.equal(before.accuracy.x, after.accuracy.x)
    end)

    it("scales the row with everything else", function()
      local geometry = logic.geometry(100, 200, 2)
      assert.are.equal(16, geometry.accuracy.font_size)
      assert.are.equal(235, geometry.background.y)
    end)

    it("takes the row out of the geometry entirely when it is off", function()
      config.accuracy.enabled = false
      local geometry = logic.geometry(100, 200, 1)
      assert.is_nil(geometry.accuracy)
      assert.is_nil(geometry.reset_button)
      assert.are.equal(200, geometry.background.y)
      assert.are.equal(202, geometry.bars[1].y)
    end)

    it("reports bounds that cover the row as well as the frame", function()
      local x, y, width, height = logic.bounds(100, 200, 1)
      assert.are.same({ 100, 200 }, { x, y })
      assert.are.equal(41, height)
      -- The line outreaches the bar art once the delay is on the end of it.
      assert.are.equal(510, width)
    end)

    --[[ At the shipped font the row fits inside the bar art, so the frame
         decides the width. A bigger font or a pushed-out offset is what the
         widening is FOR, and without a case off the defaults nothing here
         would notice if it stopped happening. ]]
    it("widens the bounds for a row that outreaches the bar art", function()
      config.accuracy.font_size = 14
      local width = select(3, logic.bounds(100, 200, 1))
      assert.is_true(width > 472)
      local geometry = logic.geometry(100, 200, 1)
      local reserved = 23 * config.accuracy.font_size * config.accuracy.text_width_ratio
      assert.is_true(width >= geometry.accuracy.x + reserved - 100)
    end)

    it("widens the bounds for a row pushed out by its own offset", function()
      config.accuracy.offset = 120
      local width = select(3, logic.bounds(100, 200, 1))
      assert.is_true(width > 472)
    end)

    it("reports the plain frame bounds when the row is off", function()
      config.accuracy.enabled = false
      assert.are.same({ 100, 200, 472, 24 }, { logic.bounds(100, 200, 1) })
    end)
  end)

  describe("commands", function()
    it("reports the current metrics when asked for nothing", function()
      local message = logic.command({})
      assert.is_not_nil(message:find("132", 1, true))
      assert.is_not_nil(message:lower():find("compact"))
    end)

    it("sets width, spacing and offset on the active metric set", function()
      assert.is_true(select(2, logic.command({ "width", "200" })))
      assert.are.equal(200, config.bar.width)
      logic.command({ "spacing", "24" })
      assert.are.equal(24, config.bar.spacing)
      logic.command({ "offset", "3" })
      assert.are.equal(3, config.bar.offset)
      assert.are.equal(132, parambar_defaults(1920, 1080).bar.width, "defaults are untouched")
    end)

    it("writes to the compact set while compact mode is on", function()
      config.compact = true
      logic.command({ "width", "200" })
      assert.are.equal(200, config.compact_bar.width)
      assert.are.equal(132, config.bar.width)
    end)

    it("routes a metric write by the same rule metrics() reads by", function()
      config.compact = "yes"
      logic.command({ "width", "200" })
      assert.are.equal(200, config.bar.width, "only a real boolean means compact")
      assert.are.equal(116, config.compact_bar.width)
    end)

    it("toggles compact mode", function()
      assert.is_true(select(2, logic.command({ "compact", "on" })))
      assert.is_true(config.compact)
      logic.command({ "compact", "OFF" })
      assert.is_false(config.compact)
    end)

    it("refuses a width below the minimum", function()
      local message, changed = logic.command({ "width", "7" })
      assert.is_false(changed)
      assert.is_not_nil(message:find("8", 1, true))
      assert.are.equal(132, config.bar.width)
    end)

    it("accepts the minimum width", function()
      assert.is_true(select(2, logic.command({ "width", "8" })))
    end)

    it("refuses negative spacing and offset", function()
      assert.is_false(select(2, logic.command({ "spacing", "-1" })))
      assert.is_false(select(2, logic.command({ "offset", "-1" })))
      assert.is_true(select(2, logic.command({ "offset", "0" })))
    end)

    it("refuses values that are not whole numbers", function()
      assert.is_false(select(2, logic.command({ "width", "abc" })))
      assert.is_false(select(2, logic.command({ "width", "12.5" })))
      assert.is_false(select(2, logic.command({ "width" })))
    end)

    it("refuses numbers that are not plain decimal integers", function()
      assert.is_false(select(2, logic.command({ "width", "0x84" })))
      assert.is_false(select(2, logic.command({ "width", "1e2" })))
      assert.are.equal(132, config.bar.width)
    end)

    it("refuses anything but on or off for compact", function()
      local message, changed = logic.command({ "compact", "maybe" })
      assert.is_false(changed)
      assert.is_not_nil(message:lower():find("on"))
    end)

    it("reports the accuracy row in the status line", function()
      local message = logic.command({})
      assert.is_not_nil(message:lower():find("accuracy"))
      assert.is_not_nil(message:find("15", 1, true))
    end)

    it("switches the accuracy row on and off", function()
      local message, changed = logic.command({ "accuracy", "off" })
      assert.is_true(changed)
      assert.is_false(config.accuracy.enabled)
      assert.is_not_nil(message:lower():find("off"))
      assert.is_true(select(2, logic.command({ "accuracy", "on" })))
      assert.is_true(config.accuracy.enabled)
    end)

    it("reports the row on its own when given no argument", function()
      local message, changed = logic.command({ "accuracy" })
      assert.is_false(changed)
      assert.is_nil(message:find("has no", 1, true))
      assert.is_not_nil(message:find("15", 1, true))
      assert.is_not_nil(message:find("Acc: 0 / 0 (--%) / --s", 1, true))
    end)

    it("sets the window in seconds", function()
      local message, changed = logic.command({ "accuracy", "window", "30" })
      assert.is_true(changed)
      assert.are.equal(30, config.accuracy.window_seconds)
      assert.is_not_nil(message:find("30", 1, true))
    end)

    it("refuses a window longer than the module will hold", function()
      local message, changed = logic.command({ "accuracy", "window", "9999" })
      assert.is_false(changed)
      assert.is_not_nil(message:find("600", 1, true))
      assert.are.equal(15, config.accuracy.window_seconds)
      assert.is_true(select(2, logic.command({ "accuracy", "window", "600" })))
    end)

    it("refuses a window the module would fall back over", function()
      assert.is_false(select(2, logic.command({ "accuracy", "window", "0" })))
      assert.is_false(select(2, logic.command({ "accuracy", "window", "soon" })))
      assert.is_false(select(2, logic.command({ "accuracy", "window", "-5" })))
      assert.are.equal(15, config.accuracy.window_seconds)
    end)

    it("hints on an accuracy word it does not know", function()
      local message, changed = logic.command({ "accuracy", "wobble" })
      assert.is_false(changed)
      assert.is_not_nil(message:find("wobble", 1, true))
    end)

    it("empties the window on the reset verb", function()
      swings({ 1, 1, 15 })
      assert.are.equal("Acc: 2 / 3 (67%) / --s", logic.tick(0).accuracy.text)
      local message, changed = logic.command({ "accuracy", "reset" })
      -- Nothing is stored, so nothing needs saving.
      assert.is_false(changed)
      assert.is_not_nil(message:lower():find("reset"))
      assert.are.equal("Acc: 0 / 0 (--%) / --s", logic.tick(0).accuracy.text)
    end)

    it("resets without repairing a hand-broken accuracy block", function()
      config.accuracy = "on"
      logic.set_config(config)
      logic.command({ "accuracy", "reset" })
      assert.are.equal("on", config.accuracy)
    end)

    it("names the word it did not understand, not the one after it", function()
      local message, changed = logic.command({ "accuracy", "wobble", "bobble" })
      assert.is_false(changed)
      assert.is_not_nil(message:find("wobble", 1, true))
      assert.is_nil(message:find("bobble", 1, true))
      assert.is_not_nil(message:find("reset", 1, true))
    end)

    --[[ A refused command must not write: the widget only saves on a change,
         so a repair made on the way to a refusal would leave memory and disk
         disagreeing until some unrelated write. ]]
    it("leaves a broken accuracy block alone while only reporting", function()
      config.accuracy = "on"
      logic.set_config(config)
      logic.command({ "accuracy" })
      assert.are.equal("on", config.accuracy)
      logic.command({ "accuracy", "window", "0" })
      assert.are.equal("on", config.accuracy)
      logic.command({ "accuracy", "wobble" })
      assert.are.equal("on", config.accuracy)
    end)

    it("repairs an accuracy block a hand edit left as something else", function()
      config.accuracy = "on"
      logic.set_config(config)
      assert.is_true(select(2, logic.command({ "accuracy", "on" })))
      assert.are.equal("table", type(config.accuracy))
      assert.is_true(logic.accuracy_enabled())
    end)

    it("names accuracy among the settings it does know", function()
      assert.is_not_nil(logic.command({ "wobble" }):find("accuracy", 1, true))
    end)

    it("hints instead of staying silent on an unknown verb", function()
      local message, changed = logic.command({ "wobble" })
      assert.is_false(changed)
      assert.is_not_nil(message:find("wobble", 1, true))
    end)

    it("matches verbs case-insensitively", function()
      assert.is_true(select(2, logic.command({ "WIDTH", "50" })))
    end)
  end)
end)
