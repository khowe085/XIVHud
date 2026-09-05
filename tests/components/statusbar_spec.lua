local fakes = require("tests/support/fakes")
local new_statusbar = require("components/statusbar/statusbar")
local build_defaults = require("components/statusbar/defaults")

local KO, SLEEP, HASTE, FOOD = 0, 2, 33, 251

local RESOURCES = {
  buffs = { [0] = { en = "KO" }, [2] = { en = "sleep" }, [33] = { en = "haste" }, [251] = { en = "Food" } },
}

local EPOCH = 1009810800

-- A 0x063 order 9 packet carrying the given `{ id = , expires = }` entries,
-- as the entry point's packets.parse hands it over.
local function durations_packet(entries, kind)
  local parsed = { Order = kind or 0x09 }
  for slot = 1, 32 do
    local entry = entries[slot]
    parsed["Buffs " .. slot] = entry and entry.id or 255
    parsed["Time " .. slot] = entry and math.floor(((entry.expires - EPOCH) * 60) % 2 ^ 32) or 0
  end
  return parsed
end

describe("statusbar widget", function()
  local prims, env, widget, config, saves

  local function build(without)
    prims = fakes.prims()
    env = { clock = 1788000000, player = { name = "Ayame", buffs = {} }, last = {}, parses = 0, commands = {} }
    saves = 0
    local ctx = {
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
      -- What the client last sent under an id, and the parse the entry
      -- point would run on it: the seed at attach.
      last_incoming = function(id)
        return env.last[id]
      end,
      parse_packet = function(data)
        env.parses = env.parses + 1
        return type(data) == "table" and data or nil
      end,
      send_command = function(command)
        env.commands[#env.commands + 1] = command
      end,
    }
    for _, key in ipairs(without or {}) do
      ctx[key] = nil
    end
    widget = new_statusbar(ctx)
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
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
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

    -- Core pushes both for every anchor on every layout-mode mouse move.
    it("costs nothing on a placement push that changes nothing", function()
      env.player.buffs = { HASTE }
      widget.update()
      local before = calls()
      widget.set_pos(100, 50, "bar1")
      widget.set_scale(1, "bar1")
      assert.are.equal(before, calls())
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
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      local shown = texts_shown()
      assert.are.equal(1, #shown)
      assert.are.equal("59", shown[1].text)
      assert.are.equal(100, shown[1].x)
      assert.is_true(shown[1].y >= 82)
    end)

    it("counts down as the clock moves", function()
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      env.clock = env.clock + 30
      widget.update()
      assert.are.equal("29", texts_shown()[1].text)
    end)

    it("clears the text when the timer runs out but the buff has not gone", function()
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 5 } }))
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
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      attach()
      widget.update()
      assert.are.equal("59", texts_shown()[1].text)
    end)

    it("ignores the other orders of the packet, other packets, and a failed parse", function()
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }, 0x05))
      widget.update("chunk", 0x076, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update("chunk", 0x063, "raw", nil)
      widget.update()
      assert.are.same({}, texts_shown())
    end)

    -- Without a wall clock the wrap would resolve against zero and a slice
    -- of raw values would count down as garbage; no clock means no timers.
    it("draws no text when the ctx has no wall clock", function()
      build({ "time" })
      attach()
      env.player.buffs = { HASTE }
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      assert.are.equal(1, #icons_shown())
      assert.are.same({}, texts_shown())
    end)

    -- Nothing re-sends the packet after a reload until a buff changes, but
    -- the client keeps the last one sent under its id, and order 9 is what
    -- usually sits there: the attach seeds from it, through the same parse
    -- the entry point would run.
    it("seeds the timers at attach from the last packet the client sent", function()
      env.last[0x063] = durations_packet({ { id = HASTE, expires = env.clock + 59 } })
      attach()
      widget.update()
      assert.are.equal("59", texts_shown()[1].text)
      assert.are.equal(1, env.parses)
    end)

    it("seeds nothing when the last packet was another order, or there was none", function()
      env.last[0x063] = durations_packet({ { id = HASTE, expires = env.clock + 59 } }, 0x02)
      attach()
      widget.update()
      assert.are.same({}, texts_shown())
      env.last[0x063] = nil
      build()
      attach()
      widget.update()
      assert.are.same({}, texts_shown())
    end)

    it("copes with a ctx that cannot answer the last packet", function()
      build({ "last_incoming", "parse_packet" })
      attach()
      widget.update()
      assert.are.same({}, texts_shown())
    end)

    it("draws no text while the timers are switched off", function()
      widget.handle_command({ "timers", "off" })
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
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
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
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

  describe("tooltips", function()
    local MOVE, RIGHT_DOWN, RIGHT_UP = 0, 4, 5

    local function tip()
      for _, prim in ipairs(prims.texts) do
        if prim.visible and type(prim.last.text) == "string" and prim.last.text:find("(", 1, true) then
          return prim
        end
      end
      return nil
    end

    before_each(function()
      attach()
      env.player.buffs = { HASTE, KO }
      widget.update()
    end)

    it("declares a mouse handler, so core forwards the mouse", function()
      assert.is_function(widget.on_mouse)
    end)

    it("names the buff under the cursor, below its cell, and never blocks", function()
      assert.is_false(widget.on_mouse(MOVE, 140, 60, 0))
      local shown = tip()
      assert.is_not_nil(shown)
      assert.are.equal("haste (33)", shown.last.text)
      assert.are.equal(134, shown.x)
      assert.is_true(shown.y >= 50 + 32 + 14)
      assert.is_true(shown.last.bg_visible)
    end)

    it("hides the tip when the cursor leaves the icons", function()
      widget.on_mouse(MOVE, 140, 60, 0)
      widget.on_mouse(MOVE, 140, 400, 0)
      assert.is_nil(tip())
    end)

    it("costs nothing while the cursor stays on one cell", function()
      widget.on_mouse(MOVE, 140, 60, 0)
      local before = calls()
      widget.on_mouse(MOVE, 141, 61, 0)
      widget.on_mouse(MOVE, 150, 70, 0)
      assert.are.equal(before, calls())
    end)

    it("ignores clicks and the wheel", function()
      assert.is_false(widget.on_mouse(1, 140, 60, 0))
      assert.is_false(widget.on_mouse(10, 140, 60, 1))
      assert.is_nil(tip())
    end)

    it("shows nothing over a hidden bar", function()
      widget.hide("bar1")
      widget.on_mouse(MOVE, 140, 60, 0)
      assert.is_nil(tip())
    end)

    it("shows nothing while tooltips are switched off, and drops one already up", function()
      widget.on_mouse(MOVE, 140, 60, 0)
      widget.handle_command({ "tooltips", "off" })
      widget.on_mouse(MOVE, 141, 60, 0)
      assert.is_nil(tip())
    end)

    it("drops the tip on a whole-widget hide and on detach", function()
      widget.on_mouse(MOVE, 140, 60, 0)
      widget.hide()
      assert.is_nil(tip())
      widget.show()
      widget.update()
      widget.on_mouse(MOVE, 140, 60, 0)
      assert.is_not_nil(tip())
      widget.detach()
      assert.is_nil(tip())
      assert.is_false(widget.on_mouse(MOVE, 140, 60, 0))
    end)

    -- A right-click over an icon asks the cancel addon to drop the buff, and
    -- the click is swallowed - both edges - so the game does not act on it.
    it("cancels the buff under a right-click, and swallows the click", function()
      assert.is_true(widget.on_mouse(RIGHT_DOWN, 140, 60, 0))
      assert.are.same({ "cancel 33" }, env.commands)
      assert.is_true(widget.on_mouse(RIGHT_UP, 140, 60, 0))
      assert.are.same({ "cancel 33" }, env.commands, "the release sends nothing")
    end)

    it("leaves a right-click off the icons to the game", function()
      assert.is_false(widget.on_mouse(RIGHT_DOWN, 140, 400, 0))
      assert.is_false(widget.on_mouse(RIGHT_UP, 140, 400, 0))
      assert.are.same({}, env.commands)
    end)

    it("leaves a right-click alone over a hidden bar, or without a console", function()
      widget.hide("bar1")
      assert.is_false(widget.on_mouse(RIGHT_DOWN, 140, 60, 0))
      assert.are.same({}, env.commands)
      build({ "send_command" })
      attach()
      env.player.buffs = { HASTE }
      widget.update()
      assert.is_false(widget.on_mouse(RIGHT_DOWN, 105, 60, 0))
    end)

    it("swallows only the release that followed a swallowed press", function()
      assert.is_true(widget.on_mouse(RIGHT_DOWN, 140, 60, 0))
      assert.is_true(widget.on_mouse(RIGHT_UP, 500, 500, 0), "released off the icon, still ours")
      assert.is_false(widget.on_mouse(RIGHT_UP, 140, 60, 0), "a release with no press of ours")
    end)

    it("follows a buff that moves cells", function()
      widget.on_mouse(MOVE, 105, 60, 0)
      assert.are.equal("KO (0)", tip().last.text)
      env.player.buffs = { HASTE }
      widget.update()
      widget.on_mouse(MOVE, 106, 60, 0)
      assert.are.equal("haste (33)", tip().last.text)
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
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
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

    -- Core attaches over a character switch without a logout event, so the
    -- expiries - keyed by buff id, the same on every character - would carry
    -- across. A re-attach for the same character (a slot switch) must keep
    -- them: nothing re-sends the packet.
    it("forgets the timers when a different character attaches", function()
      attach()
      env.player.buffs = { HASTE }
      widget.update("chunk", 0x063, "raw", durations_packet({ { id = HASTE, expires = env.clock + 59 } }))
      widget.update()
      assert.are.equal(1, #texts_shown())
      attach()
      widget.update()
      assert.are.equal(1, #texts_shown(), "a re-attach for the same character keeps them")
      env.player = { name = "Bea", buffs = { HASTE } }
      attach()
      widget.update()
      assert.are.same({}, texts_shown())
    end)

    it("draws the incoming character's buffs from the attach, not the outgoing one's", function()
      attach()
      env.player.buffs = { HASTE }
      widget.update()
      env.player = { name = "Bea", buffs = { KO } }
      attach()
      local shown = icons_shown()
      assert.are.equal(1, #shown)
      assert.are.equal(KO, shown[1].id)
    end)

    -- Core's apply sends the bare show first and restates each anchor after
    -- it, so a bar that is off is shown and hidden inside one apply; it must
    -- not grow prims for the moment in between.
    it("builds no prims for a bar shown and hidden inside one apply", function()
      env.player.buffs = { HASTE, KO }
      attach()
      widget.update()
      assert.are.equal(2, #prims.images)
      -- What core's apply sends, with the buffs already read.
      widget.show()
      widget.hide("bar2")
      widget.hide("bar3")
      widget.update()
      assert.are.equal(2, #prims.images)
      assert.are.equal(2, #icons_shown())
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
