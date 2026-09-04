local fakes = require("tests/support/fakes")
local new_statusbar = require("components/statusbar/statusbar")
local build_defaults = require("components/statusbar/defaults")

local KO, SLEEP, HASTE, FOOD = 0, 2, 33, 251

local RESOURCES = {
  buffs = { [0] = { en = "KO" }, [2] = { en = "sleep" }, [33] = { en = "haste" }, [251] = { en = "Food" } },
}

local EPOCH = 1009810800

local function u16(value)
  return string.char(value % 256, math.floor(value / 256) % 256)
end

local function u32(value)
  local bytes = {}
  for index = 1, 4 do
    bytes[index] = string.char(value % 256)
    value = math.floor(value / 256)
  end
  return table.concat(bytes)
end

-- A 0x063 order 9 packet carrying the given `{ id = , expires = }` entries.
local function durations_packet(entries, kind)
  local ids, times = {}, {}
  for slot = 1, 32 do
    local entry = entries[slot]
    ids[slot] = u16(entry and entry.id or 255)
    times[slot] = u32(entry and math.floor(((entry.expires - EPOCH) * 60) % 2 ^ 32) or 0)
  end
  return string.char(0x63, 0, 0, 0) .. u16(kind or 0x09) .. u16(0xC4) .. table.concat(ids) .. table.concat(times)
end

describe("statusbar widget", function()
  local prims, env, widget, config, saves

  local function build()
    prims = fakes.prims()
    env = { clock = 1788000000, player = { name = "Ayame", buffs = {} } }
    saves = 0
    widget = new_statusbar({
      name = "statusbar",
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      asset = function(path)
        return "addons/XIVHud/" .. path
      end,
      resources = RESOURCES,
      get_player = function()
        return env.player
      end,
      time = function()
        return env.clock
      end,
    })
    return widget
  end

  local function attach(loaded)
    config = loaded or build_defaults(1920, 1080)
    config.layout = nil
    widget.attach(config, function()
      saves = saves + 1
    end)
    widget.set_pos(100, 50, "bar1")
    widget.set_pos(100, 150, "bar2")
    widget.set_pos(100, 250, "bar3")
    -- What core pushes for the shipped defaults: the widget on, then the
    -- second and third bars off.
    widget.show()
    widget.hide("bar2")
    widget.hide("bar3")
  end

  -- The visible icon prims, in creation order, with the buff id each shows.
  local function icons_shown()
    local shown = {}
    for _, prim in ipairs(prims.images) do
      local path = prim.last.path
      if prim.visible and type(path) == "string" then
        local id = path:match("buffIcons/(%d+)%.png$")
        shown[#shown + 1] = { id = tonumber(id), x = prim.x, y = prim.y, width = prim.width }
      end
    end
    return shown
  end

  local function texts_shown()
    local shown = {}
    for _, prim in ipairs(prims.texts) do
      if prim.visible then
        shown[#shown + 1] = { text = prim.last.text, x = prim.x, y = prim.y }
      end
    end
    return shown
  end

  local function calls()
    local count = 0
    for _, prim in ipairs(prims.all) do
      count = count + #prim.calls
    end
    return count
  end

  before_each(build)

  describe("the contract", function()
    it("is the status bar, sb for short, on three anchors", function()
      assert.are.equal("statusbar", widget.name)
      assert.are.equal("sb", widget.alias)
      assert.are.same({ "bar1", "bar2", "bar3" }, widget.anchors())
    end)

    it("carries the component defaults, layout included", function()
      assert.are.equal("all", widget.defaults.bars.bar1.filter)
      assert.is_false(widget.defaults.layout.anchors.bar2.visible)
    end)

    it("draws nothing before it is attached", function()
      env.player.buffs = { HASTE }
      widget.set_pos(100, 50, "bar1")
      widget.show()
      widget.update()
      assert.are.same({}, icons_shown())
    end)
  end)

  describe("drawing", function()
    before_each(function()
      attach()
    end)

    it("shows the player's buffs on the first bar, in priority order", function()
      env.player.buffs = { HASTE, KO, 255, 255 }
      widget.update()
      local shown = icons_shown()
      assert.are.equal(2, #shown)
      assert.are.same({ KO, HASTE }, { shown[1].id, shown[2].id })
      assert.are.same({ 100, 50 }, { shown[1].x, shown[1].y })
      assert.is_true(shown[2].x > shown[1].x)
      assert.are.equal(32, shown[1].width)
    end)

    it("draws the icons from the party list's buff art", function()
      env.player.buffs = { HASTE }
      widget.update()
      assert.are.equal("addons/XIVHud/assets/xiv/buffIcons/33.png", prims.images[1].last.path)
    end)

    it("keeps the second and third bars dark until they are shown", function()
      widget.hide("bar2")
      widget.hide("bar3")
      env.player.buffs = { SLEEP, FOOD }
      widget.update()
      assert.are.equal(2, #icons_shown())
      widget.show("bar2")
      widget.update()
      local shown = icons_shown()
      assert.are.equal(3, #shown)
      assert.are.equal(SLEEP, shown[3].id)
      assert.are.equal(150, shown[3].y)
    end)

    it("takes every bar down on a bare hide and brings them all back on a bare show", function()
      env.player.buffs = { SLEEP, FOOD }
      widget.update()
      widget.hide()
      assert.are.same({}, icons_shown())
      widget.hide("bar3")
      widget.show()
      widget.update()
      assert.are.equal(4, #icons_shown())
    end)

    it("follows a buff that goes away", function()
      env.player.buffs = { HASTE, KO }
      widget.update()
      env.player.buffs = { HASTE }
      widget.update()
      local shown = icons_shown()
      assert.are.equal(1, #shown)
      assert.are.equal(HASTE, shown[1].id)
    end)

    it("costs nothing on a tick where nothing changed", function()
      env.player.buffs = { HASTE, KO }
      widget.update()
      local before = calls()
      widget.update()
      widget.update()
      assert.are.equal(before, calls())
    end)

    -- Suppression hides the widget once and the tick keeps running; a bar
    -- that has drawn must not re-hide its prims sixty times a second.
    it("costs nothing on a tick while hidden", function()
      env.player.buffs = { HASTE, KO }
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      widget.hide()
      local before = calls()
      widget.update()
      widget.update()
      assert.are.equal(before, calls())
      widget.show("bar1")
      widget.update()
      assert.are.equal(2, #icons_shown())
    end)

    it("scales one bar without moving the others", function()
      env.player.buffs = { HASTE, KO, SLEEP }
      widget.show("bar2")
      widget.set_scale(2, "bar1")
      widget.update()
      local shown = icons_shown()
      assert.are.equal(5, #shown)
      assert.are.equal(64, shown[1].width)
      assert.are.equal(32, shown[4].width)
    end)

    it("re-lays the icons when the bar moves", function()
      env.player.buffs = { HASTE }
      widget.update()
      widget.set_pos(300, 60, "bar1")
      assert.are.same({ 300, 60 }, { icons_shown()[1].x, icons_shown()[1].y })
    end)

    it("copes with a player the client cannot name yet", function()
      env.player = nil
      widget.update()
      assert.are.same({}, icons_shown())
    end)

    it("ignores an anchor it does not have", function()
      widget.set_pos(1, 1, "bar9")
      widget.set_scale(2, "bar9")
      widget.show("bar9")
      widget.hide("bar9")
      assert.is_nil(widget.get_bounds("bar9"))
    end)
  end)

  describe("bounds", function()
    it("answers the origin it was given, per anchor, whatever is drawn", function()
      attach()
      local x, y, w, h = widget.get_bounds("bar1")
      assert.are.same({ 100, 50 }, { x, y })
      assert.is_true(w > 600 and h > 40)
      env.player.buffs = { HASTE }
      widget.update()
      local x2, y2, w2, h2 = widget.get_bounds("bar1")
      assert.are.same({ x, y, w, h }, { x2, y2, w2, h2 })
      assert.are.equal(150, select(2, widget.get_bounds("bar2")))
    end)

    it("is nil before the bar is placed", function()
      assert.is_nil(widget.get_bounds("bar1"))
    end)
  end)

  describe("timers", function()
    before_each(function()
      attach()
      env.player.buffs = { HASTE }
    end)

    it("writes the remaining time under an icon once the client reports it", function()
      widget.update()
      assert.are.same({}, texts_shown())
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      local shown = texts_shown()
      assert.are.equal(1, #shown)
      assert.are.equal("59", shown[1].text)
      assert.are.equal(100, shown[1].x)
      assert.is_true(shown[1].y >= 82)
    end)

    it("counts down as the clock moves", function()
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      env.clock = env.clock + 30
      widget.update()
      assert.are.equal("29", texts_shown()[1].text)
    end)

    it("clears the text when the timer runs out but the buff has not gone", function()
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 5 } }))
      widget.update()
      env.clock = env.clock + 10
      widget.update()
      assert.are.same({}, texts_shown())
      assert.are.equal(1, #icons_shown())
    end)

    -- Nothing re-sends the packet until a buff changes, so one that lands
    -- between the character being scoped and the attach must be kept.
    it("keeps a packet that arrives before the attach", function()
      widget.detach()
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      attach()
      widget.update()
      assert.are.equal("59", texts_shown()[1].text)
    end)

    it("ignores the other orders of the packet, and other packets", function()
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 59 } }, 0x05))
      widget.update("chunk", 0x076, durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      assert.are.same({}, texts_shown())
    end)

    it("draws no text while the timers are switched off", function()
      widget.handle_command({ "timers", "off" })
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      assert.are.same({}, texts_shown())
    end)
  end)

  -- A timer prim exists only where a cell had a timer, so the pool is
  -- sparse whenever an untimed buff sorts ahead of a timed one - the usual
  -- case. Every hide has to reach past the gap.
  describe("a timer behind a cell without one", function()
    before_each(function()
      attach()
      env.player.buffs = { KO, HASTE }
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      assert.are.equal(1, #texts_shown())
    end)

    it("goes with a hide", function()
      widget.hide()
      assert.are.same({}, texts_shown())
    end)

    it("goes with a per-anchor hide", function()
      widget.hide("bar1")
      assert.are.same({}, texts_shown())
    end)

    it("goes on detach", function()
      widget.detach()
      assert.are.same({}, texts_shown())
    end)

    it("is destroyed with the rest", function()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed)
      end
    end)
  end)

  describe("preview", function()
    it("shows sample buffs with timers on every bar, so an empty bar can be dragged", function()
      attach()
      widget.set_preview(true)
      assert.is_true(#icons_shown() >= 6)
      assert.is_true(#texts_shown() >= 6)
      widget.set_preview(false)
      assert.are.same({}, icons_shown())
    end)
  end)

  describe("commands", function()
    before_each(function()
      attach()
    end)

    it("reports the bars", function()
      local lines = widget.handle_command({})
      assert.is_not_nil(table.concat(lines, "\n"):find("bar1", 1, true))
    end)

    it("saves and re-lays after a change", function()
      env.player.buffs = { HASTE, KO, SLEEP }
      widget.update()
      widget.handle_command({ "rows", "4" })
      assert.are.equal(1, saves)
      assert.are.equal(4, config.bars.bar1.rows)
      -- Five wide now, so the sixth icon would start a row; three fit still.
      assert.are.equal(3, #icons_shown())
      widget.handle_command({ "filter", "debuffs" })
      assert.are.equal(2, saves)
      local shown = icons_shown()
      assert.are.equal(2, #shown)
    end)

    it("does not save a refusal", function()
      widget.handle_command({ "rows", "9" })
      assert.are.equal(0, saves)
    end)
  end)

  describe("attach and detach", function()
    it("replaces a bar entry that is not a table with a fresh default", function()
      local broken = build_defaults(1920, 1080)
      broken.bars.bar1 = "nonsense"
      attach(broken)
      env.player.buffs = { HASTE }
      widget.update()
      assert.are.equal(1, #icons_shown())
      assert.are.equal("table", type(config.bars.bar1))
      assert.are_not.equal(widget.defaults.bars.bar1, config.bars.bar1)
    end)

    it("replaces a bars table that is not one", function()
      attach({ bars = 7 })
      env.player.buffs = { HASTE }
      widget.update()
      assert.are.equal(1, #icons_shown())
    end)

    it("hides everything on detach and forgets the timers", function()
      attach()
      env.player.buffs = { HASTE }
      widget.update("chunk", 0x063, durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      widget.detach()
      assert.are.same({}, icons_shown())
      widget.update()
      assert.are.same({}, icons_shown())
      attach()
      widget.update()
      assert.are.equal(1, #icons_shown())
      assert.are.same({}, texts_shown())
    end)

    it("destroys every prim it made", function()
      attach()
      env.player.buffs = { HASTE, KO }
      widget.update()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed)
      end
    end)
  end)
end)
