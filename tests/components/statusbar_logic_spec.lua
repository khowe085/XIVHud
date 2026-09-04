local new_logic = require("components/statusbar/logic")
local build_defaults = require("components/statusbar/defaults")

local KO, WEAKNESS, DOOM, SLEEP = 0, 1, 15, 2
local HASTE, PROTECT = 33, 40
local FOOD, SIGNET = 251, 253

local RESOURCES = {
  buffs = {
    [0] = { en = "KO" },
    [1] = { en = "weakness" },
    [15] = { en = "doom" },
    [2] = { en = "sleep" },
    [33] = { en = "haste" },
    [40] = { en = "protect" },
    [251] = { en = "Food" },
    [253] = { en = "Signet" },
  },
}

describe("statusbar logic", function()
  local config, logic

  local function build()
    local defaults = build_defaults(1920, 1080)
    config = { bars = defaults.bars, priority = defaults.priority, timers = defaults.timers }
    logic = new_logic({ config = config, resources = RESOURCES })
    logic.set_time(1000)
    return logic
  end

  local function ids_of(plan)
    local ids = {}
    for index, cell in ipairs(plan.cells) do
      ids[index] = cell.id
    end
    return ids
  end

  local function many(count)
    local list = {}
    for index = 1, count do
      list[index] = index
    end
    return list
  end

  before_each(build)

  describe("the shapes", function()
    local function shape(rows)
      config.bars.bar1.rows = rows
      local plan = logic.plan("bar1")
      return plan.cols, plan.rows, plan.capacity
    end

    it("lays one row twenty wide", function()
      assert.are.same({ 20, 1, 20 }, { shape(1) })
    end)

    it("lays two rows ten wide", function()
      assert.are.same({ 10, 2, 20 }, { shape(2) })
    end)

    it("lays three rows seven wide", function()
      assert.are.same({ 7, 3, 21 }, { shape(3) })
    end)

    it("lays four rows five wide", function()
      assert.are.same({ 5, 4, 20 }, { shape(4) })
    end)

    it("falls back to one row for a rows value that is nonsense", function()
      config.bars.bar1.rows = "many"
      assert.are.equal(20, logic.plan("bar1").cols)
      config.bars.bar1.rows = 9
      assert.are.equal(20, logic.plan("bar1").cols)
    end)
  end)

  describe("the plan", function()
    it("shows nothing before the player is read", function()
      assert.are.same({}, logic.plan("bar1").cells)
    end)

    it("fills left to right, top row first", function()
      config.bars.bar1.rows = 2
      logic.set_buffs(many(11))
      local cells = logic.plan("bar1").cells
      assert.are.same({ 0, 0 }, { cells[1].col, cells[1].row })
      assert.are.same({ 9, 0 }, { cells[10].col, cells[10].row })
      assert.are.same({ 0, 1 }, { cells[11].col, cells[11].row })
    end)

    it("orders by the shipped priority and drops the empty-slot marker", function()
      logic.set_buffs({ 255, DOOM, 255, KO, WEAKNESS })
      assert.are.same({ KO, WEAKNESS, DOOM }, ids_of(logic.plan("bar1")))
    end)

    it("shows the debuffs alone on a debuff bar", function()
      logic.set_buffs({ HASTE, SLEEP, FOOD, KO })
      assert.are.same({ KO, SLEEP }, ids_of(logic.plan("bar2")))
    end)

    it("shows food and system buffs alone on an other bar", function()
      logic.set_buffs({ HASTE, SLEEP, FOOD, SIGNET })
      assert.are.same({ FOOD, SIGNET }, ids_of(logic.plan("bar3")))
    end)

    it("shows the enhancements alone when a bar is set to them", function()
      config.bars.bar1.filter = "enhancements"
      logic.set_buffs({ HASTE, SLEEP, FOOD, PROTECT })
      assert.are.same({ HASTE, PROTECT }, ids_of(logic.plan("bar1")))
    end)

    it("shows everything on an all bar", function()
      logic.set_buffs({ HASTE, SLEEP, FOOD })
      assert.are.equal(3, #logic.plan("bar1").cells)
    end)

    it("trims a bar's own blacklist off its category", function()
      config.bars.bar2.filters = { SLEEP }
      logic.set_buffs({ HASTE, SLEEP, KO })
      assert.are.same({ KO }, ids_of(logic.plan("bar2")))
    end)

    it("keeps a bar's own whitelist inside its category", function()
      config.bars.bar2.filter_mode = "whitelist"
      config.bars.bar2.filters = { SLEEP, HASTE }
      logic.set_buffs({ HASTE, SLEEP, KO })
      assert.are.same({ SLEEP }, ids_of(logic.plan("bar2")))
    end)

    it("applies the shared priority overrides", function()
      config.priority = { [DOOM] = 1 }
      logic.set_buffs({ KO, DOOM })
      assert.are.same({ DOOM, KO }, ids_of(logic.plan("bar1")))
    end)

    it("cuts at capacity and says how many there were", function()
      logic.set_buffs(many(25))
      local plan = logic.plan("bar1")
      assert.are.equal(20, #plan.cells)
      assert.are.equal(25, plan.total)
    end)

    -- The repair lands in the config, so it is saved and not redone per frame.
    it("repairs a bar's broken lists into the config on the first plan", function()
      config.bars.bar2.filters = "nonsense"
      config.bars.bar2.filter_mode = nil
      logic.set_buffs({ KO })
      assert.are.same({ KO }, ids_of(logic.plan("bar2")))
      assert.are.same({}, config.bars.bar2.filters)
      assert.are.equal("blacklist", config.bars.bar2.filter_mode)
    end)

    it("treats an unknown bar as empty", function()
      logic.set_buffs({ KO })
      assert.are.same({}, logic.plan("bar9").cells)
    end)

    it("copes with a bar entry that is not a table", function()
      config.bars.bar2 = "nonsense"
      logic.set_buffs({ KO })
      assert.are.same({}, logic.plan("bar2").cells)
    end)
  end)

  describe("timers", function()
    before_each(function()
      logic.set_buffs({ HASTE, SLEEP })
    end)

    it("draws nothing under a buff whose expiry is unknown", function()
      assert.is_nil(logic.plan("bar1").cells[1].timer)
    end)

    it("counts seconds under a minute", function()
      logic.apply_durations({ { id = HASTE, expires = 1059 } })
      assert.are.equal("59", logic.plan("bar1").cells[2].timer)
    end)

    it("counts minutes under an hour, then hours", function()
      logic.apply_durations({ { id = HASTE, expires = 1000 + 120 }, { id = SLEEP, expires = 1000 + 7200 } })
      local cells = logic.plan("bar1").cells
      assert.are.equal("2h", cells[1].timer)
      assert.are.equal("2m", cells[2].timer)
    end)

    it("counts down as time passes", function()
      logic.apply_durations({ { id = HASTE, expires = 1100 } })
      logic.set_time(1050)
      assert.are.equal("50", logic.plan("bar1").cells[2].timer)
    end)

    it("draws nothing once the expiry has passed", function()
      logic.apply_durations({ { id = HASTE, expires = 1010 } })
      logic.set_time(1010)
      assert.is_nil(logic.plan("bar1").cells[2].timer)
    end)

    it("draws nothing when timers are switched off", function()
      config.timers = false
      logic.apply_durations({ { id = HASTE, expires = 1059 } })
      assert.is_nil(logic.plan("bar1").cells[2].timer)
    end)

    it("assigns duplicate ids their expiries in slot order", function()
      logic.set_buffs({ HASTE, HASTE })
      logic.apply_durations({ { id = HASTE, expires = 1010 }, { id = HASTE, expires = 1020 } })
      local cells = logic.plan("bar1").cells
      assert.are.same({ "10", "20" }, { cells[1].timer, cells[2].timer })
    end)

    it("replaces the last packet's expiries wholesale", function()
      logic.apply_durations({ { id = HASTE, expires = 1059 } })
      logic.apply_durations({ { id = SLEEP, expires = 1030 } })
      local cells = logic.plan("bar1").cells
      assert.are.equal("30", cells[1].timer)
      assert.is_nil(cells[2].timer)
    end)

    it("formats a remaining time", function()
      assert.is_nil(logic.timer_text(0))
      assert.is_nil(logic.timer_text(-5))
      assert.are.equal("1", logic.timer_text(0.4))
      assert.are.equal("59", logic.timer_text(59.9))
      assert.are.equal("1m", logic.timer_text(60))
      assert.are.equal("59m", logic.timer_text(3599))
      assert.are.equal("1h", logic.timer_text(3600))
      assert.are.equal("99h", logic.timer_text(99 * 3600 + 30))
    end)

    -- A sentinel timestamp for a buff that never expires decodes to some
    -- point within a wrap of now; nothing real runs for days on end.
    it("draws nothing for an expiry implausibly far off", function()
      assert.is_nil(logic.timer_text(101 * 3600))
    end)
  end)

  describe("geometry", function()
    it("places icons in a row with a timer band under each", function()
      logic.set_buffs({ KO, WEAKNESS })
      local geometry = logic.geometry("bar1", 100, 50, 1)
      local first, second = geometry.cells[1], geometry.cells[2]
      assert.are.same({ 100, 50, 32 }, { first.x, first.y, first.size })
      assert.are.equal(100, first.text_x)
      assert.is_true(first.text_y >= 82)
      assert.is_true(second.x > first.x + 32)
      assert.are.equal(first.y, second.y)
    end)

    it("scales every measurement", function()
      logic.set_buffs({ KO, WEAKNESS })
      local one = logic.geometry("bar1", 0, 0, 1)
      local two = logic.geometry("bar1", 0, 0, 2)
      assert.are.equal(one.cells[2].x * 2, two.cells[2].x)
      assert.are.equal(64, two.cells[1].size)
      assert.are.equal(one.cells[1].text_size * 2, two.cells[1].text_size)
    end)

    -- A fractional font size is not something a prim can draw; layout mode
    -- scales down to 0.25.
    it("rounds the timer font to whole pixels, never below one", function()
      logic.set_buffs({ KO })
      assert.are.equal(3, logic.geometry("bar1", 0, 0, 0.25).cells[1].text_size)
      assert.are.equal(1, logic.geometry("bar1", 0, 0, 0.01).cells[1].text_size)
    end)

    it("starts a new row beneath the last", function()
      config.bars.bar1.rows = 4
      logic.set_buffs(many(6))
      local cells = logic.geometry("bar1", 0, 0, 1).cells
      assert.are.equal(cells[1].x, cells[6].x)
      assert.is_true(cells[6].y > cells[1].y + 32)
    end)

    -- The bounds cover the whole shape, full or empty, so the origin never
    -- moves as buffs come and go.
    it("reports bounds for the whole shape from the origin it was given", function()
      local x, y, w, h = logic.bounds("bar1", 100, 50, 1)
      assert.are.same({ 100, 50 }, { x, y })
      logic.set_buffs(many(3))
      local _, _, w2, h2 = logic.bounds("bar1", 100, 50, 1)
      assert.are.same({ w, h }, { w2, h2 })
      assert.is_true(w > 20 * 32)
      assert.is_true(h >= 32 + 10)
    end)

    it("grows the bounds with the rows and the scale", function()
      local _, _, w1, h1 = logic.bounds("bar1", 0, 0, 1)
      config.bars.bar1.rows = 4
      local _, _, w4, h4 = logic.bounds("bar1", 0, 0, 1)
      assert.is_true(w4 < w1)
      assert.is_true(h4 > h1)
      local _, _, w8, h8 = logic.bounds("bar1", 0, 0, 2)
      assert.are.same({ w4 * 2, h4 * 2 }, { w8, h8 })
    end)
  end)

  describe("preview", function()
    it("shows sample buffs with timers where there are none", function()
      logic.set_preview(true)
      local plan = logic.plan("bar1")
      assert.is_true(#plan.cells >= 4)
      assert.is_not_nil(plan.cells[1].timer)
      logic.set_preview(false)
      assert.are.same({}, logic.plan("bar1").cells)
    end)

    it("shows samples on every bar, whatever its filter", function()
      logic.set_preview(true)
      assert.is_true(#logic.plan("bar2").cells >= 1)
      assert.is_true(#logic.plan("bar3").cells >= 1)
    end)
  end)

  describe("commands", function()
    local function say(...)
      local lines, changed = logic.command({ ... })
      return table.concat(lines, "\n"), changed
    end

    it("reports every bar and the timer switch when given nothing", function()
      local said = say()
      assert.is_not_nil(said:find("bar1", 1, true))
      assert.is_not_nil(said:find("bar3", 1, true))
      assert.is_not_nil(said:find("debuffs", 1, true))
      assert.is_not_nil(said:find("20x1", 1, true))
      assert.is_not_nil(said:find("timers on", 1, true))
    end)

    -- A hand-edited typo restricts nothing, which the report has to say
    -- rather than print a filter name that looks like it works.
    it("says an unknown filter name is showing everything", function()
      config.bars.bar1.filter = "debufs"
      local said = say("bar1")
      assert.is_not_nil(said:find("debufs", 1, true))
      assert.is_not_nil(said:find("unknown", 1, true))
    end)

    it("reports one bar when named", function()
      local said = say("bar2")
      assert.is_not_nil(said:find("bar2", 1, true))
      assert.is_nil(said:find("bar3", 1, true))
    end)

    it("assigns a predefined filter to the first bar by default", function()
      local _, changed = say("filter", "debuffs")
      assert.is_true(changed)
      assert.are.equal("debuffs", config.bars.bar1.filter)
    end)

    it("assigns a predefined filter to a named bar", function()
      say("bar3", "filter", "all")
      assert.are.equal("all", config.bars.bar3.filter)
    end)

    it("matches bars, verbs and filters case-insensitively", function()
      assert.is_true(select(2, say("BAR2", "FILTER", "Other")))
      assert.are.equal("other", config.bars.bar2.filter)
    end)

    it("reads the filter hint as one sentence", function()
      local said = say("filter", "wobble")
      assert.is_nil(said:find("other, or add", 1, true))
      assert.is_not_nil(said:find("add", 1, true))
    end)

    it("names the four filters when given one it does not know", function()
      local said, changed = say("filter", "wobble")
      assert.is_false(changed)
      assert.is_not_nil(said:find("enhancements", 1, true))
      assert.is_not_nil(said:find("other", 1, true))
    end)

    it("edits a bar's own filter list", function()
      local _, changed = say("bar2", "filter", "add", "doom")
      assert.is_true(changed)
      assert.are.same({ DOOM }, config.bars.bar2.filters)
      say("bar2", "filter", "mode", "whitelist")
      assert.are.equal("whitelist", config.bars.bar2.filter_mode)
      assert.is_not_nil(say("bar2", "filter", "list"):find("doom", 1, true))
      say("bar2", "filter", "clear")
      assert.are.same({}, config.bars.bar2.filters)
    end)

    it("lists a bar's filters when filter is given nothing", function()
      assert.is_not_nil(say("filter"):find("nothing", 1, true))
    end)

    it("names the bar in a filter message", function()
      assert.is_not_nil(say("bar2", "filter", "mode", "greylist"):find("statusbar bar2 filter", 1, true))
    end)

    it("sets the rows of a bar", function()
      local _, changed = say("rows", "3")
      assert.is_true(changed)
      assert.are.equal(3, config.bars.bar1.rows)
      say("bar3", "rows", "4")
      assert.are.equal(4, config.bars.bar3.rows)
    end)

    it("refuses rows outside one to four", function()
      assert.is_false(select(2, say("rows", "5")))
      assert.is_false(select(2, say("rows", "0")))
      assert.is_false(select(2, say("rows", "two")))
      assert.is_false(select(2, say("rows")))
      assert.are.equal(1, config.bars.bar1.rows)
    end)

    it("switches the timers", function()
      local _, changed = say("timers", "off")
      assert.is_true(changed)
      assert.is_false(config.timers)
      say("timers", "on")
      assert.is_true(config.timers)
      assert.is_false(select(2, say("timers", "maybe")))
    end)

    it("refuses a bar word in front of timers, which is one switch for all", function()
      local said, changed = say("bar2", "timers", "off")
      assert.is_false(changed)
      assert.is_not_nil(said:find("bar", 1, true))
      assert.is_true(config.timers)
    end)

    it("edits the shared priority through buff", function()
      local _, changed = say("buff", "top", "doom")
      assert.is_true(changed)
      assert.are.equal(1, config.priority[DOOM])
      assert.is_not_nil(say("buff", "list"):find("page 1/", 1, true))
      assert.is_not_nil(say("buff", "find", "weak"):find("weakness", 1, true))
    end)

    -- The order is one table under three engines, each memoizing it, so an
    -- edit through the buff verbs has to reach every bar's plan at once.
    it("applies a buff edit to every bar's plan", function()
      config.bars.bar2.filter = "all"
      config.bars.bar3.filter = "all"
      logic.set_buffs({ KO, DOOM })
      assert.are.same({ KO, DOOM }, ids_of(logic.plan("bar2")))
      say("buff", "top", "doom")
      assert.are.same({ DOOM, KO }, ids_of(logic.plan("bar2")))
      assert.are.same({ DOOM, KO }, ids_of(logic.plan("bar3")))
      say("buff", "reset")
      assert.are.same({ KO, DOOM }, ids_of(logic.plan("bar2")))
    end)

    it("refuses a bar word in front of buff, which is one order for all", function()
      local said, changed = say("bar2", "buff", "top", "doom")
      assert.is_false(changed)
      assert.is_not_nil(said:find("bar", 1, true))
      assert.is_nil(config.priority[DOOM])
    end)

    it("points buff filter at the per-bar verb rather than editing the first bar", function()
      local said, changed = say("buff", "filter", "add", "doom")
      assert.is_false(changed)
      assert.is_not_nil(said:find("bar", 1, true))
      assert.are.same({}, config.bars.bar1.filters)
    end)

    it("names what each bar draws right now, past the capacity", function()
      config.bars.bar1.rows = 4
      logic.set_buffs({ HASTE, SLEEP, FOOD })
      local said = say("buff")
      assert.is_not_nil(said:find("bar1", 1, true))
      assert.is_not_nil(said:find("haste", 1, true))
      assert.is_not_nil(said:find("bar2", 1, true))
      local bar2 = said:match("bar2[^\n]*\n([^\n]*)")
      assert.is_not_nil(bar2 and bar2:find("sleep", 1, true))
    end)

    it("says so when a bar has nothing to draw", function()
      logic.set_buffs({})
      assert.is_not_nil(say("buff"):find("nothing", 1, true))
    end)

    it("answers an unknown verb with a hint naming the verbs", function()
      local said, changed = say("wobble")
      assert.is_false(changed)
      assert.is_not_nil(said:find("wobble", 1, true))
      assert.is_not_nil(said:find("rows", 1, true))
      assert.is_not_nil(said:find("filter", 1, true))
    end)

    it("does not mistake a bar it does not have for a bar", function()
      local said, changed = say("bar9", "rows", "2")
      assert.is_false(changed)
      assert.is_not_nil(said:find("bar9", 1, true))
    end)

    it("copes with a bar entry that is not a table", function()
      config.bars.bar2 = "nonsense"
      local said, changed = say("bar2", "rows", "2")
      assert.is_false(changed)
      assert.is_not_nil(said:find("reset", 1, true))
    end)

    it("picks up a config handed in later", function()
      local fresh = build_defaults(1920, 1080)
      fresh.bars.bar1.rows = 4
      logic.set_config({ bars = fresh.bars, priority = fresh.priority, timers = false })
      assert.are.equal(5, logic.plan("bar1").cols)
    end)
  end)
end)
