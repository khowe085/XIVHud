local new_config_window = require("lib/config_window")
local fakes = require("tests/support/fakes")

local MOVE, LEFT_DOWN, LEFT_UP, RIGHT_DOWN, WHEEL = 0, 1, 2, 4, 10

--[[ The settings window, driven by nothing but mouse tuples over a fake
     pair of panels: `global`, a flat page, and `hotbar`, a tabbed one. The
     fake `apply` answers the way a component's command handler does - it
     changes the value the next panel read reports and says a line. ]]

local function centre(rect)
  return rect.x + rect.width / 2, rect.y + rect.height / 2
end

local function build(opts)
  opts = opts or {}
  local prims = fakes.prims()
  local env = {
    prims = prims,
    entries = opts.entries or { "global", "hotbar" },
    values = { retry = false, range = 4, delay = 5, shared = false, columns = 3 },
    applied = {},
    panel_reads = 0,
    closed = 0,
    window_pos = opts.window_pos,
  }

  local function panel(name)
    env.panel_reads = env.panel_reads + 1
    local values = env.values
    if name == "global" then
      return {
        rows = {
          { label = "Cast retry", kind = "toggle", value = values.retry, command = { "retry" } },
          {
            label = "Gate reach",
            kind = "stepper",
            value = values.range,
            min = 0.5,
            step = 0.5,
            command = { "wsgate", "range" },
          },
          {
            label = "Travel delay",
            kind = "stepper",
            value = values.delay,
            min = 0,
            max = 6,
            step = 1,
            command = { "delay" },
          },
        },
      }
    elseif name == "hotbar" then
      return {
        tabs = {
          {
            name = "sets",
            rows = { { label = "Set 1 shared", kind = "toggle", value = values.shared, command = { "share", "1" } } },
          },
          {
            name = "rows",
            rows = {
              {
                label = "Columns",
                kind = "stepper",
                value = values.columns,
                min = 1,
                max = 20,
                step = 1,
                command = { "bar2", "columns" },
                suffix = { "now" },
              },
            },
          },
        },
      }
    end
    return nil
  end

  local function apply(name, words, route)
    env.applied[#env.applied + 1] = { name = name, words = words, route = route }
    if opts.on_apply ~= nil then
      return opts.on_apply(words)
    end
    local values = env.values
    if words[1] == "retry" then
      values.retry = words[2] == "on"
      return "cast retry: " .. words[2]
    elseif words[1] == "wsgate" then
      values.range = tonumber(words[3])
      return "weaponskill gate melee reach: " .. words[3] .. " yalms"
    elseif words[1] == "delay" then
      values.delay = tonumber(words[2])
      return { "travel delay: " .. words[2] .. " seconds", "a second line" }
    elseif words[1] == "share" then
      values.shared = words[3] == "on"
      return "set 1 shared: " .. words[3]
    elseif words[1] == "bar2" then
      values.columns = tonumber(words[3])
      return nil
    end
    return "unknown"
  end

  local deps = {
    new_image = prims.new_image,
    new_text = prims.new_text,
    asset = function(path)
      return "addon/" .. path
    end,
    screen = function()
      return 1920, 1080
    end,
    entries = function()
      return env.entries
    end,
    panel = opts.panel or panel,
    apply = apply,
    window_pos = function()
      return env.window_pos
    end,
    save_window_pos = function(x, y)
      env.window_pos = { x = x, y = y }
      env.saves = (env.saves or 0) + 1
    end,
    on_close = function()
      env.closed = env.closed + 1
    end,
  }
  if opts.headless then
    deps.new_image, deps.new_text = nil, nil
  end
  local window = new_config_window(deps)
  env.window = window
  return window, env
end

local function click(window, x, y)
  window.mouse(LEFT_DOWN, x, y, 0)
  return window.mouse(LEFT_UP, x, y, 0)
end

--- The one visible, live text prim carrying `label`, or nil.
local function shown_text(env, label)
  for _, prim in ipairs(env.prims.texts) do
    if prim.visible and prim.destroyed == 0 and prim.last.text == label then
      return prim
    end
  end
  return nil
end

local function menu_entry(window, name)
  for _, entry in ipairs(window.view().menu) do
    if entry.name == name then
      return entry
    end
  end
  return nil
end

local function row_labelled(window, label)
  for _, row in ipairs(window.view().rows) do
    if row.label == label then
      return row
    end
  end
  return nil
end

describe("config window", function()
  describe("opening and closing", function()
    it("starts closed, draws nothing and answers no mouse", function()
      local window, env = build()
      assert.is_false(window.active())
      assert.is_nil(window.view())
      assert.are.equal(0, #env.prims.all)
      assert.is_false(window.mouse(LEFT_DOWN, 960, 540, 0))
    end)

    it("builds its prims on open and destroys every one on close", function()
      local window, env = build()
      window.open()
      assert.is_true(window.active())
      local built = #env.prims.all
      assert.is_true(built > 0)
      window.close()
      assert.is_false(window.active())
      assert.is_nil(window.view())
      for _, prim in ipairs(env.prims.all) do
        assert.are.equal(1, prim.destroyed)
      end
      window.open()
      assert.are.equal(built * 2, #env.prims.all, "a fresh set, never the destroyed ones")
    end)

    it("tells its owner once for every close, however it was closed", function()
      local window, env = build()
      window.open()
      window.close()
      assert.are.equal(1, env.closed)
      window.close()
      assert.are.equal(1, env.closed, "closing a closed window is nothing")
      window.open()
      click(window, centre(window.view().frame.close))
      assert.is_false(window.active(), "the X closes it")
      assert.are.equal(2, env.closed)
    end)

    it("opening an open window changes nothing", function()
      local window, env = build()
      window.open()
      local built = #env.prims.all
      window.open()
      assert.are.equal(built, #env.prims.all)
    end)

    it("lays out and answers the mouse with nothing to draw on", function()
      local window, env = build({ headless = true })
      window.open()
      assert.are.equal(0, #env.prims.all)
      click(window, centre(row_labelled(window, "Cast retry").toggle))
      assert.is_true(env.values.retry)
    end)
  end)

  describe("the frame and the menu", function()
    it("is the binder's window without a back control, titled and centred", function()
      local window, env = build()
      window.open()
      local frame = window.view().frame
      assert.are.same({ 500, 240, 920, 600 }, { frame.x, frame.y, frame.width, frame.height })
      assert.is_nil(frame.back)
      assert.is_not_nil(shown_text(env, "XIVHud settings"))
      assert.is_not_nil(shown_text(env, "[ X ]"))
      assert.is_nil(shown_text(env, "[ < back ]"))
    end)

    it("lists every entry down the left, the first one selected", function()
      local window, env = build()
      window.open()
      local menu = window.view().menu
      assert.are.equal(2, #menu)
      assert.are.same({ "global", true }, { menu[1].name, menu[1].selected })
      assert.are.same({ "hotbar", false }, { menu[2].name, menu[2].selected })
      local frame = window.view().frame
      assert.are.same({ frame.body.x, frame.body.y }, { menu[1].x, menu[1].y })
      assert.are.equal(menu[1].y + 26, menu[2].y, "a row apart")
      local drawn = shown_text(env, "> global")
      assert.is_not_nil(drawn)
      assert.are.same({ menu[1].x, menu[1].y }, { drawn.x, drawn.y })
      assert.is_not_nil(shown_text(env, "  hotbar"))
    end)

    it("switches panel on a menu click", function()
      local window = build()
      window.open()
      assert.is_not_nil(row_labelled(window, "Cast retry"))
      click(window, centre(menu_entry(window, "hotbar")))
      assert.is_true(menu_entry(window, "hotbar").selected)
      assert.is_false(menu_entry(window, "global").selected)
      assert.is_nil(row_labelled(window, "Cast retry"))
      assert.is_not_nil(row_labelled(window, "Set 1 shared"))
    end)

    it("opens on the entry it is given, and remembers the last one otherwise", function()
      local window = build()
      window.open("hotbar")
      assert.is_true(menu_entry(window, "hotbar").selected)
      window.close()
      window.open()
      assert.is_true(menu_entry(window, "hotbar").selected, "where it was left")
      window.close()
      window.open("global")
      assert.is_true(menu_entry(window, "global").selected)
    end)

    it("falls back to the first entry for one that is not in the menu", function()
      local window = build()
      window.open("parambar")
      assert.is_true(menu_entry(window, "global").selected)
    end)

    it("selects an entry while open", function()
      local window = build()
      window.open()
      window.select("hotbar")
      assert.is_true(menu_entry(window, "hotbar").selected)
      window.select("nonsense")
      assert.is_true(menu_entry(window, "hotbar").selected, "an unknown entry changes nothing")
    end)

    it("says so where an entry has nothing to show", function()
      local window = build({ entries = { "global", "ghost" } })
      window.open("ghost")
      assert.are.same({}, window.view().rows)
      assert.are.equal("ghost has no settings here", window.view().status)
    end)
  end)

  describe("a row", function()
    it("is a label with its control beside it, to the right of the menu", function()
      local window, env = build()
      window.open()
      local frame = window.view().frame
      local row = row_labelled(window, "Cast retry")
      assert.are.same({ frame.body.x + 222, frame.body.y }, { row.x, row.y })
      local label = shown_text(env, "Cast retry")
      assert.are.same({ row.x, row.y }, { label.x, label.y })
      assert.are.equal(row.y + 26, row_labelled(window, "Gate reach").y)
    end)

    it("hides the prims of rows the panel no longer has", function()
      local window, env = build()
      window.open()
      assert.is_not_nil(shown_text(env, "Travel delay"))
      click(window, centre(menu_entry(window, "hotbar")))
      assert.is_nil(shown_text(env, "Travel delay"))
      assert.is_nil(shown_text(env, "Gate reach"))
    end)
  end)

  describe("a toggle", function()
    it("shows the value and takes a click on it", function()
      local window, env = build()
      window.open()
      local row = row_labelled(window, "Cast retry")
      assert.are.equal("[ off ]", row.text)
      local drawn = shown_text(env, "[ off ]")
      assert.are.same({ row.toggle.x, row.toggle.y }, { drawn.x, drawn.y })
      assert.is_true(click(window, centre(row.toggle)), "the click is the window's")
    end)

    it("sends the row's command with the other value on the end", function()
      local window, env = build()
      window.open()
      click(window, centre(row_labelled(window, "Cast retry").toggle))
      assert.are.same({ { name = "global", words = { "retry", "on" } } }, env.applied)
      click(window, centre(row_labelled(window, "Cast retry").toggle))
      assert.are.same({ "retry", "off" }, env.applied[2].words)
    end)

    it("re-reads the panel, so it shows what the command left behind", function()
      local window, env = build()
      window.open()
      local reads = env.panel_reads
      click(window, centre(row_labelled(window, "Cast retry").toggle))
      assert.are.equal(reads + 1, env.panel_reads)
      assert.are.equal("[ on ]", row_labelled(window, "Cast retry").text)
      assert.is_not_nil(shown_text(env, "[ on ]"))
    end)

    it("writes the command's answer on the status line", function()
      local window, env = build()
      window.open()
      assert.are.equal("", window.view().status)
      click(window, centre(row_labelled(window, "Cast retry").toggle))
      assert.are.equal("cast retry: on", window.view().status)
      local frame = window.view().frame
      local drawn = shown_text(env, "cast retry: on")
      assert.are.same({ frame.subhead.x, frame.subhead.y }, { drawn.x, drawn.y })
    end)

    it("does nothing for a press that slid off it before the release", function()
      local window, env = build()
      window.open()
      local x, y = centre(row_labelled(window, "Cast retry").toggle)
      window.mouse(LEFT_DOWN, x, y, 0)
      assert.is_true(window.mouse(MOVE, x, y + 60, 0), "a drag in the window is the window's")
      assert.is_true(window.mouse(LEFT_UP, x, y + 60, 0))
      assert.are.same({}, env.applied)
    end)
  end)

  describe("a stepper", function()
    it("shows the value between a step down and a step up", function()
      local window, env = build()
      window.open()
      local row = row_labelled(window, "Travel delay")
      assert.are.equal("5", row.text)
      assert.is_nil(row.toggle)
      assert.is_true(row.dec.x < row.inc.x)
      assert.are.same({ row.dec.y, row.inc.y }, { row.y, row.y })
      local value = shown_text(env, "5")
      assert.is_true(value.x > row.dec.x and value.x < row.inc.x)
      local shown_dec, shown_inc = 0, 0
      for _, prim in ipairs(env.prims.texts) do
        if prim.visible and prim.last.text == "[-]" then
          shown_dec = shown_dec + 1
        elseif prim.visible and prim.last.text == "[+]" then
          shown_inc = shown_inc + 1
        end
      end
      assert.are.same({ 2, 2 }, { shown_dec, shown_inc }, "one pair per stepper, none for the toggle")
    end)

    it("steps the value by the row's step and sends it", function()
      local window, env = build()
      window.open()
      click(window, centre(row_labelled(window, "Travel delay").inc))
      assert.are.same({ "delay", "6" }, env.applied[1].words)
      assert.are.equal("6", row_labelled(window, "Travel delay").text)
      click(window, centre(row_labelled(window, "Travel delay").dec))
      assert.are.same({ "delay", "5" }, env.applied[2].words)
    end)

    it("stops at its bounds, sending nothing for a step past one", function()
      local window, env = build()
      env.values.delay = 6
      window.open()
      click(window, centre(row_labelled(window, "Travel delay").inc))
      assert.are.same({}, env.applied)
      env.values.delay = 0
      window.refresh()
      click(window, centre(row_labelled(window, "Travel delay").dec))
      assert.are.same({}, env.applied)
    end)

    it("lands on a bound a whole step would overshoot", function()
      local window, env = build()
      env.values.range = 0.75
      window.open()
      click(window, centre(row_labelled(window, "Gate reach").dec))
      assert.are.same({ "wsgate", "range", "0.5" }, env.applied[1].words)
    end)

    it("never moves a value the wrong way to bring it inside a bound", function()
      -- The CLI can store what the row's bounds exclude: a step down from
      -- under the minimum must not RAISE it, nor a step up from over the
      -- maximum lower it.
      local window, env = build()
      env.values.range = 0.3
      window.open()
      click(window, centre(row_labelled(window, "Gate reach").dec))
      assert.are.same({}, env.applied)
      click(window, centre(row_labelled(window, "Gate reach").inc))
      assert.are.same({ "wsgate", "range", "0.8" }, env.applied[1].words, "the way it was asked to go still works")
      env.values.delay = 9
      window.refresh()
      click(window, centre(row_labelled(window, "Travel delay").inc))
      assert.are.equal(1, #env.applied)
      click(window, centre(row_labelled(window, "Travel delay").dec))
      assert.are.same({ "delay", "6" }, env.applied[2].words, "down from over the top lands on the top")
    end)

    it("lands a whole step on a whole number from a value that is not one", function()
      -- A command that takes whole numbers refuses 5.5, so a fraction stored
      -- by hand would leave the stepper dead: every click refused.
      local window, env = build()
      env.values.delay = 4.5
      window.open()
      click(window, centre(row_labelled(window, "Travel delay").inc))
      assert.are.same({ "delay", "5" }, env.applied[1].words)
      env.values.delay = 4.5
      window.refresh()
      click(window, centre(row_labelled(window, "Travel delay").dec))
      assert.are.same({ "delay", "4" }, env.applied[2].words)
    end)

    it("has no upper bound where the row names none", function()
      local window, env = build()
      env.values.range = 400
      window.open()
      click(window, centre(row_labelled(window, "Gate reach").inc))
      assert.are.same({ "wsgate", "range", "400.5" }, env.applied[1].words)
    end)

    it("sends a fractional step as the number a player would type", function()
      local window, env = build({
        panel = function()
          return {
            rows = { { label = "Pivot", kind = "stepper", value = 1.3, min = 0, step = 0.1, command = { "pivot" } } },
          }
        end,
      })
      window.open()
      click(window, centre(row_labelled(window, "Pivot").inc))
      assert.are.same({ "pivot", "1.4" }, env.applied[1].words)
      click(window, centre(row_labelled(window, "Pivot").dec))
      assert.are.same({ "pivot", "1.2" }, env.applied[2].words)
    end)
  end)

  describe("a choice", function()
    -- One row over a fixed list, its value held here the way a component's
    -- config holds it.
    local function chooser(row)
      local state = { value = row.value }
      local window, env = build({
        panel = function()
          local copy = {}
          for key, value in pairs(row) do
            copy[key] = value
          end
          copy.value = state.value
          return { rows = { copy } }
        end,
        on_apply = function(words)
          state.value = words[#words]
          return "mode: " .. words[#words]
        end,
      })
      window.open()
      return window, env, state
    end

    local MODES = { label = "Mode", kind = "choice", options = { "auto", "magic", "gun" }, command = { "mode" } }

    local function modes(value)
      local row = {}
      for key, field in pairs(MODES) do
        row[key] = field
      end
      row.value = value
      return row
    end

    it("shows the value between a step back and a step on", function()
      local window, env = chooser(modes("magic"))
      local row = row_labelled(window, "Mode")
      assert.are.equal("magic", row.text)
      assert.is_nil(row.toggle)
      local back, on = shown_text(env, "[<]"), shown_text(env, "[>]")
      assert.are.same({ row.dec.x, row.dec.y }, { back.x, back.y })
      assert.are.same({ row.inc.x, row.inc.y }, { on.x, on.y })
      assert.is_nil(shown_text(env, "[-]"), "the stepper's signs are a number's")
    end)

    it("steps through its options in order, sending the one it lands on", function()
      local window, env = chooser(modes("auto"))
      click(window, centre(row_labelled(window, "Mode").inc))
      assert.are.same({ "mode", "magic" }, env.applied[1].words)
      assert.are.equal("magic", row_labelled(window, "Mode").text)
      click(window, centre(row_labelled(window, "Mode").dec))
      assert.are.same({ "mode", "auto" }, env.applied[2].words)
    end)

    it("wraps at both ends", function()
      local window, env = chooser(modes("gun"))
      click(window, centre(row_labelled(window, "Mode").inc))
      assert.are.same({ "mode", "auto" }, env.applied[1].words)
      click(window, centre(row_labelled(window, "Mode").dec))
      assert.are.same({ "mode", "gun" }, env.applied[2].words)
    end)

    it("shows a value its options do not list, and steps off it onto the list", function()
      -- A config file is hand-editable, so the stored value can be anything.
      local window, env, state = chooser(modes("bow"))
      assert.are.equal("bow", row_labelled(window, "Mode").text)
      click(window, centre(row_labelled(window, "Mode").inc))
      assert.are.same({ "mode", "auto" }, env.applied[1].words)
      state.value = "bow"
      window.refresh()
      click(window, centre(row_labelled(window, "Mode").dec))
      assert.are.same({ "mode", "gun" }, env.applied[2].words)
    end)

    it("shows a label where the row names one, and still sends the option", function()
      local row = modes(2)
      row.options, row.labels = { 1, 2, 5 }, { "10x1", "5x2", "2x5" }
      local window, env = chooser(row)
      assert.are.equal("5x2", row_labelled(window, "Mode").text)
      click(window, centre(row_labelled(window, "Mode").inc))
      assert.are.same({ "mode", "5" }, env.applied[1].words)
    end)

    it("sends nothing where there is nowhere else to go", function()
      local row = modes("auto")
      row.options = { "auto" }
      local window, env = chooser(row)
      click(window, centre(row_labelled(window, "Mode").inc))
      click(window, centre(row_labelled(window, "Mode").dec))
      assert.are.same({}, env.applied)
    end)
  end)

  describe("what a command answers", function()
    it("shows the first line of a list", function()
      local window = build()
      window.open()
      click(window, centre(row_labelled(window, "Travel delay").inc))
      assert.are.equal("travel delay: 6 seconds", window.view().status)
    end)

    it("clears the status line when a command answers nothing", function()
      local window = build()
      window.open("hotbar")
      click(window, centre(row_labelled(window, "Set 1 shared").toggle))
      assert.are.equal("set 1 shared: on", window.view().status)
      click(window, centre(menu_entry(window, "global")))
      assert.are.equal("", window.view().status, "a line about another panel is stale")
    end)

    it("hands the row's route through, for a command that is not handle_command's", function()
      local window, env = build({
        panel = function()
          return {
            rows = {
              {
                label = "Filter",
                kind = "toggle",
                value = false,
                command = { "bar1", "filter" },
                route = "buffs",
              },
            },
          }
        end,
      })
      window.open()
      click(window, centre(row_labelled(window, "Filter").toggle))
      assert.are.equal("buffs", env.applied[1].route)
    end)
  end)

  --[[ The window runs inside the mouse handler, where five errors make the
       guard switch the handler off for every component. So what it calls -
       a component's panel, a component's command - is never allowed to throw
       through it. ]]
  describe("a panel or a command that throws", function()
    it("opens on a panel that cannot be built, saying so instead of throwing", function()
      local window = build({
        panel = function()
          error("the panel broke")
        end,
      })
      assert.has_no.errors(function()
        window.open()
      end)
      assert.is_true(window.active())
      assert.are.same({}, window.view().rows)
      assert.is_not_nil(window.view().status:find("global: its settings could not be read", 1, true))
      assert.is_not_nil(window.view().status:find("the panel broke", 1, true), "with the reason")
      assert.is_true(window.mouse(WHEEL, 960, 540, -1), "and the mouse still answers")
      click(window, centre(window.view().frame.close))
      assert.is_false(window.active())
    end)

    it("keeps working when a panel breaks on a later read", function()
      local broken = false
      local window = build({
        panel = function()
          if broken then
            error("the panel broke")
          end
          return { rows = { { label = "Loud", kind = "toggle", value = false, command = { "loud" } } } }
        end,
        on_apply = function()
          broken = true
          return "loud: on"
        end,
      })
      window.open()
      assert.has_no.errors(function()
        click(window, centre(row_labelled(window, "Loud").toggle))
      end)
      assert.are.same({}, window.view().rows)
      assert.is_not_nil(window.view().status:find("could not be read", 1, true))
    end)

    it("draws a stepper whose value is not a number as it stands, and sends nothing for it", function()
      -- A hand-edited `width = "wide"` reaches the panel as the component
      -- read it; formatting or stepping it would throw.
      local window, env = build({
        panel = function()
          return {
            rows = { { label = "Width", kind = "stepper", value = "wide", min = 0, step = 1, command = { "width" } } },
          }
        end,
      })
      assert.has_no.errors(function()
        window.open()
      end)
      assert.are.equal("wide", row_labelled(window, "Width").text)
      assert.has_no.errors(function()
        click(window, centre(row_labelled(window, "Width").inc))
        click(window, centre(row_labelled(window, "Width").dec))
      end)
      assert.are.same({}, env.applied)
    end)

    it("writes a command's error on the status line, and stays as it was", function()
      local window, env = build({
        on_apply = function()
          error("the handler broke")
        end,
      })
      window.open()
      assert.has_no.errors(function()
        click(window, centre(row_labelled(window, "Cast retry").toggle))
      end)
      assert.is_not_nil(window.view().status:find("the handler broke", 1, true))
      assert.are.equal("[ off ]", row_labelled(window, "Cast retry").text)
      assert.are.equal(1, #env.applied)
    end)
  end)

  describe("how much a panel may hold", function()
    local function rows(count)
      local list = {}
      for index = 1, count do
        list[index] = { label = "Row " .. index, kind = "toggle", value = false, command = { "row" } }
      end
      return list
    end

    it("is said by the window, so a panel can be checked against the same numbers", function()
      assert.are.same({ rows = 20, tabbed_rows = 19, tabs = 4 }, build().capacity())
    end)

    it("is every row of the body for a flat panel, and nothing past it is drawn", function()
      local window = build({
        panel = function()
          return { rows = rows(21) }
        end,
      })
      window.open()
      assert.are.equal(20, #window.view().rows)
      assert.is_nil(row_labelled(window, "Row 21"))
    end)

    it("is a row fewer under tabs, and no more tabs than fit across", function()
      local window = build({
        panel = function()
          local tabs = {}
          for index = 1, 5 do
            tabs[index] = { name = "tab" .. index, rows = rows(20) }
          end
          return { tabs = tabs }
        end,
      })
      window.open()
      assert.are.equal(19, #window.view().rows)
      assert.are.equal(4, #window.view().tabs)
    end)
  end)

  describe("the mouse, elsewhere", function()
    it("leaves a click outside the window to the game, and stays open", function()
      local window = build()
      window.open()
      assert.is_false(window.mouse(LEFT_DOWN, 100, 100, 0))
      assert.is_false(window.mouse(LEFT_UP, 100, 100, 0))
      assert.is_true(window.active())
    end)

    it("swallows a click on the window that lands on no control", function()
      local window, env = build()
      window.open()
      local frame = window.view().frame
      assert.is_true(click(window, frame.x + frame.width - 30, frame.y + frame.height - 30))
      assert.are.same({}, env.applied)
      assert.is_true(window.active())
    end)

    it("swallows the wheel over the window and nowhere else", function()
      local window = build()
      window.open()
      assert.is_true(window.mouse(WHEEL, 960, 540, -1))
      assert.is_false(window.mouse(WHEEL, 100, 100, -1))
    end)

    it("leaves the other buttons and idle motion to the game", function()
      local window = build()
      window.open()
      assert.is_false(window.mouse(RIGHT_DOWN, 960, 540, 0))
      assert.is_false(window.mouse(MOVE, 960, 540, 0))
    end)

    it("drops a press when the window closes under it", function()
      local window = build()
      window.open()
      local x, y = centre(row_labelled(window, "Cast retry").toggle)
      window.mouse(LEFT_DOWN, x, y, 0)
      window.close()
      window.open()
      assert.is_false(window.mouse(LEFT_UP, x, y, 0), "the release belongs to no press")
    end)
  end)

  describe("tabs", function()
    local function tab_named(window, name)
      for _, tab in ipairs(window.view().tabs) do
        if tab.name == name then
          return tab
        end
      end
      return nil
    end

    it("run across the top of a tabbed panel, the first selected, the rows below", function()
      local window, env = build()
      window.open("hotbar")
      local tabs = window.view().tabs
      assert.are.equal(2, #tabs)
      assert.are.same({ "sets", true }, { tabs[1].name, tabs[1].selected })
      assert.are.same({ "rows", false }, { tabs[2].name, tabs[2].selected })
      local frame = window.view().frame
      assert.are.same({ frame.body.x + 222, frame.body.y }, { tabs[1].x, tabs[1].y })
      assert.is_true(tabs[2].x >= tabs[1].x + tabs[1].width, "side by side")
      assert.are.equal(tabs[1].y, tabs[2].y)
      assert.are.equal(frame.body.y + 26, row_labelled(window, "Set 1 shared").y)
      local drawn = shown_text(env, "[ sets ]")
      assert.are.same({ tabs[1].x, tabs[1].y }, { drawn.x, drawn.y })
      assert.is_not_nil(shown_text(env, "  rows"))
    end)

    it("are absent from a flat panel, whose rows start at the top", function()
      local window, env = build()
      window.open("hotbar")
      click(window, centre(menu_entry(window, "global")))
      assert.are.same({}, window.view().tabs)
      assert.are.equal(window.view().frame.body.y, row_labelled(window, "Cast retry").y)
      assert.is_nil(shown_text(env, "[ sets ]"))
      assert.is_nil(shown_text(env, "  rows"))
    end)

    it("show a tab's rows on a click", function()
      local window = build()
      window.open("hotbar")
      click(window, centre(tab_named(window, "rows")))
      assert.is_true(tab_named(window, "rows").selected)
      assert.is_false(tab_named(window, "sets").selected)
      assert.is_nil(row_labelled(window, "Set 1 shared"))
      assert.is_not_nil(row_labelled(window, "Columns"))
    end)

    it("stay where they are through a change, which sends the row's trailing words too", function()
      local window, env = build()
      window.open("hotbar")
      click(window, centre(tab_named(window, "rows")))
      click(window, centre(row_labelled(window, "Columns").inc))
      assert.are.same({ "bar2", "columns", "4", "now" }, env.applied[1].words)
      assert.is_true(tab_named(window, "rows").selected)
      assert.are.equal("4", row_labelled(window, "Columns").text)
      assert.are.equal("", window.view().status, "a command that answers nothing leaves no line")
    end)

    it("go back to the first when another entry is chosen", function()
      local window = build()
      window.open("hotbar")
      click(window, centre(tab_named(window, "rows")))
      click(window, centre(menu_entry(window, "global")))
      click(window, centre(menu_entry(window, "hotbar")))
      assert.is_true(tab_named(window, "sets").selected)
    end)
  end)

  describe("dragging", function()
    it("moves by its title strip and remembers where it was left", function()
      local window, env = build()
      window.open()
      local before = window.view().frame
      local row_before = row_labelled(window, "Cast retry")
      local grab_x, grab_y = before.header.x + 20, before.header.y + 5
      window.mouse(LEFT_DOWN, grab_x, grab_y, 0)
      assert.is_true(window.mouse(MOVE, grab_x - 200, grab_y - 150, 0))
      local frame = window.view().frame
      assert.are.same({ before.x - 200, before.y - 150 }, { frame.x, frame.y })
      assert.are.same(
        { row_before.x - 200, row_before.y - 150 },
        { row_labelled(window, "Cast retry").x, row_labelled(window, "Cast retry").y },
        "everything in it moves with it"
      )
      assert.is_nil(env.saves, "nothing is written per pixel")
      assert.is_true(window.mouse(LEFT_UP, grab_x - 200, grab_y - 150, 0))
      assert.are.same({ x = before.x - 200, y = before.y - 150 }, env.window_pos)
      assert.are.equal(1, env.saves)
    end)

    it("reads a slip inside the title strip as a click and writes nothing", function()
      local window, env = build()
      window.open()
      local before = window.view().frame
      window.mouse(LEFT_DOWN, before.header.x + 20, before.header.y + 5, 0)
      assert.is_false(window.mouse(MOVE, before.header.x + 22, before.header.y + 6, 0))
      window.mouse(LEFT_UP, before.header.x + 22, before.header.y + 6, 0)
      assert.are.same({ before.x, before.y }, { window.view().frame.x, window.view().frame.y })
      assert.is_nil(env.saves)
    end)

    it("does not re-read the panel for a move", function()
      local window, env = build()
      window.open()
      local header = window.view().frame.header
      window.mouse(LEFT_DOWN, header.x + 20, header.y + 5, 0)
      local reads = env.panel_reads
      window.mouse(MOVE, header.x - 100, header.y - 100, 0)
      window.mouse(MOVE, header.x - 120, header.y - 100, 0)
      assert.are.equal(reads, env.panel_reads)
    end)

    it("opens where it was left, pulled back on screen if need be", function()
      local window = build({ window_pos = { x = 40, y = 60 } })
      window.open()
      assert.are.same({ 40, 60 }, { window.view().frame.x, window.view().frame.y })
      local far = build({ window_pos = { x = 9000, y = 9000 } })
      far.open()
      assert.are.same({ 1000, 480 }, { far.view().frame.x, far.view().frame.y })
      local broken = build({ window_pos = { x = "left" } })
      broken.open()
      assert.are.same({ 500, 240 }, { broken.view().frame.x, broken.view().frame.y })
    end)
  end)

  describe("hidden", function()
    local function visible_prims(env)
      local count = 0
      for _, prim in ipairs(env.prims.all) do
        if prim.visible and prim.destroyed == 0 then
          count = count + 1
        end
      end
      return count
    end

    it("takes every prim off screen and gives the mouse back, staying open", function()
      local window, env = build()
      window.open()
      assert.is_true(visible_prims(env) > 0)
      window.set_hidden(true)
      assert.are.equal(0, visible_prims(env))
      assert.is_true(window.active())
      local x, y = centre(row_labelled(window, "Cast retry").toggle)
      assert.is_false(click(window, x, y))
      assert.is_false(window.mouse(WHEEL, x, y, -1))
      assert.are.same({}, env.applied)
    end)

    it("comes back as it was", function()
      local window, env = build()
      window.open("hotbar")
      local shown = visible_prims(env)
      window.set_hidden(true)
      window.set_hidden(false)
      assert.are.equal(shown, visible_prims(env))
      assert.is_true(menu_entry(window, "hotbar").selected)
    end)

    it("keeps a change made behind it off screen", function()
      local window, env = build()
      window.open()
      window.set_hidden(true)
      env.values.retry = true
      window.refresh()
      assert.are.equal(0, visible_prims(env))
      window.set_hidden(false)
      assert.is_not_nil(shown_text(env, "[ on ]"))
    end)

    it("drops a press it was hidden under", function()
      local window = build()
      window.open()
      local x, y = centre(row_labelled(window, "Cast retry").toggle)
      window.mouse(LEFT_DOWN, x, y, 0)
      window.set_hidden(true)
      window.set_hidden(false)
      assert.is_false(window.mouse(LEFT_UP, x, y, 0))
    end)

    it("leaves a press alone when it is told what it already is", function()
      local window, env = build()
      window.open()
      local x, y = centre(row_labelled(window, "Cast retry").toggle)
      window.mouse(LEFT_DOWN, x, y, 0)
      window.set_hidden(false)
      assert.is_true(window.mouse(LEFT_UP, x, y, 0))
      assert.is_true(env.values.retry)
    end)

    it("is forgotten by a close", function()
      local window, env = build()
      window.open()
      window.set_hidden(true)
      window.close()
      window.open()
      assert.is_true(visible_prims(env) > 0)
    end)
  end)
end)
