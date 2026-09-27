local new_parambar = require("components/parambar/parambar")
local fakes = require("tests/support/fakes")

describe("parambar widget", function()
  local prims, player, saves, assets, widget, reads, clock

  local function attach()
    widget.attach(widget.defaults, function()
      saves = saves + 1
    end)
  end

  -- Background, then the HP/MP/TP fills, in creation order.
  local function background()
    return prims.images[1]
  end

  local function fill(index)
    return prims.images[index + 1]
  end

  local function number(index)
    return prims.texts[index]
  end

  -- The accuracy row: the readout, then the reset button beside it.
  local function readout()
    return prims.texts[4]
  end

  local function reset_button()
    return prims.texts[5]
  end

  local MOUSE_LEFT_DOWN, MOUSE_LEFT_UP, MOUSE_RIGHT_DOWN = 1, 2, 4

  -- Attached, placed and shown: the state every accuracy assertion needs.
  local function place()
    attach()
    widget.set_pos(100, 200)
    widget.show()
    widget.update()
  end

  -- A point inside the reset button, taken from the geometry the row was laid
  -- out at rather than from numbers written down here.
  local function on_button()
    return reset_button().x + 2, reset_button().y + 2
  end

  -- One 0x028 of the player's own swings, dispatched as core dispatches it.
  local function swing(messages)
    local actions = {}
    for index, message in ipairs(messages) do
      actions[index] = { message = message }
    end
    widget.update("chunk", 0x028, "raw bytes", {
      actor_id = player.id,
      targets = { { id = 99, actions = actions } },
    })
  end

  local function settle()
    for _ = 1, 200 do
      widget.update()
    end
  end

  --[[ The widget hears no vitals event of its own any more: `ctx.get_player` is
       lib/player's, and hands back the client's numbers with the change events
       already reconciled into them. So a spec moves a vital by moving what the
       client reports. ]]
  local function vital(key, value)
    player.vitals[key] = value
  end

  before_each(function()
    prims = fakes.prims()
    saves = 0
    assets = {}
    player = { id = 7, vitals = { hp = 1000, hpp = 100, mp = 500, mpp = 100, tp = 500 } }
    reads = 0
    clock = 0
    widget = new_parambar({
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      get_player = function()
        reads = reads + 1
        return player
      end,
      asset = function(file)
        assets[#assets + 1] = file
        return "addons/XIVHud/" .. file
      end,
      now = function()
        return clock
      end,
    })
  end)

  describe("construction", function()
    it("is named for its config namespace and command word", function()
      assert.are.equal("parambar", widget.name)
    end)

    it("answers to a short alias of its own", function()
      assert.are.equal("pb", widget.alias)
    end)

    it("defaults its position to the bottom centre of the screen", function()
      local slot = widget.defaults.layout
      assert.are.equal(724, slot.pos.x)
      assert.are.equal(1020, slot.pos.y)
    end)

    it("builds one background, three fills, three numbers and the accuracy row", function()
      assert.are.equal(4, #prims.images)
      assert.are.equal(5, #prims.texts)
    end)

    it("makes every prim non-draggable, because the framework owns dragging", function()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(false, prim.last.draggable, prim.kind .. " must not drag itself")
      end
    end)

    it("does not right-justify the numbers, which would push them off screen", function()
      -- texts.pos offsets x by the screen width when the right flag is set.
      for index = 1, 3 do
        assert.is_nil(number(index).last.right_justified, "number " .. index)
      end
    end)

    it("stays hidden until it is attached", function()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    it("loads its textures from its own asset folder", function()
      assert.are.equal("assets/ffxiv/bar_bg.png", assets[1])
      assert.are.equal("addons/XIVHud/assets/ffxiv/hp_fg.png", fill(1).last.path)
    end)
  end)

  describe("attaching", function()
    it("reads the vitals off the player on its first frame", function()
      attach()
      widget.set_pos(0, 0)
      settle()
      assert.are.equal("1000", number(1).last.text)
      assert.are.equal("500", number(2).last.text)
    end)

    -- The client fills vitals in field by field: HP was seen landing in a live
    -- client while MP was still zero, and MP does not tick on its own outside
    -- resting, so one read leaves the MP bar empty until the player casts.
    it("picks up a vital that lands after the first read", function()
      player = { vitals = { hp = 1000, hpp = 100, mp = 0, mpp = 0, tp = 0, max_hp = 1000 } }
      attach()
      widget.set_pos(0, 0)
      settle()
      assert.are.equal("0", number(2).last.text)

      player.vitals.mp = 500
      player.vitals.mpp = 100
      settle()
      assert.are.equal("500", number(2).last.text)
    end)

    -- get_player() is unreadable around zone-in, and the framework attaches the
    -- widget whether or not it answered: the first read finds nothing, so a
    -- later one is all that will ever put a number on the bars.
    it("fills the bars in when the player was unreadable at attach", function()
      player = nil
      attach()
      widget.set_pos(0, 0)
      settle()
      assert.are.equal("0", number(1).last.text)

      player = { vitals = { hp = 1000, hpp = 100, mp = 500, mpp = 100, tp = 250 } }
      settle()
      assert.are.equal("1000", number(1).last.text)
      assert.are.equal("500", number(2).last.text)
    end)

    -- The widget reads every frame and lets lib/player throttle; a throttle
    -- here as well would put the two out of phase and double the worst-case lag.
    it("reads the player every frame", function()
      attach()
      widget.set_pos(0, 0)
      widget.update()
      widget.update()
      assert.are.equal(2, reads)
    end)

    it("stops re-reading the player when it is detached", function()
      player = { vitals = { hp = 1000, hpp = 100, mp = 0, mpp = 0, tp = 0 } }
      attach()
      widget.set_pos(0, 0)
      settle()
      widget.detach()

      local before = reads
      settle()
      assert.are.equal(before, reads, "still polling the client for a character it is no longer showing")
    end)

    it("keeps reading the player long after login", function()
      player = { vitals = { hp = 1000, hpp = 100, mp = 0, mpp = 0, tp = 0, max_hp = 1000 } }
      attach()
      widget.set_pos(0, 0)
      settle()

      player.vitals.mp = 500
      player.vitals.mpp = 100
      settle()
      assert.are.equal("500", number(2).last.text, "stopped reading the client after login")
    end)

    it("survives being attached while the player is unreadable", function()
      player = nil
      assert.has_no.errors(attach)
      widget.set_pos(0, 0)
      settle()
      assert.are.equal("0", number(1).last.text)
    end)

    it("applies the configured font and stroke to every number", function()
      attach()
      for index = 1, 3 do
        assert.are.equal("sans-serif", number(index).last.font)
        assert.are.same({ 253, 252, 250 }, number(index).last.color)
        assert.are.equal(2, number(index).last.stroke_width)
        assert.are.same({ 80, 70, 30 }, number(index).last.stroke_color)
        assert.are.equal(150, number(index).last.stroke_alpha)
      end
    end)

    it("does nothing on a frame tick before it is attached", function()
      assert.has_no.errors(function()
        widget.update()
      end)
      assert.is_nil(number(1).last.text)
    end)
  end)

  --[[ The melee accuracy row. The swings come off the 0x028 the entry point
       already decodes, so nothing new is registered; the widget supplies the
       player id and the clock, and everything else is logic's. ]]
  describe("the accuracy row", function()
    it("draws the row above the bars, at the origin set_pos was given", function()
      place()
      assert.are.equal(200, readout().y)
      assert.are.equal(200, reset_button().y)
      assert.is_true(number(3).y > readout().y)
    end)

    it("draws it small, at its own font size rather than the numbers'", function()
      place()
      assert.are.equal(12, readout().font_size)
      assert.are.equal(14, number(1).font_size)
    end)

    it("says so plainly before anything has swung", function()
      place()
      assert.are.equal("Accuracy: 0 / 0 (--%)", readout().last.text)
      assert.are.equal("[R]", reset_button().last.text)
    end)

    it("counts the player's own melee swings off the action packet", function()
      place()
      swing({ 1, 1, 15 })
      widget.update()
      assert.are.equal("Accuracy: 2 / 3 (67%)", readout().last.text)
    end)

    it("ages swings out of the window as the clock moves", function()
      place()
      swing({ 1 })
      widget.update()
      clock = 20
      widget.update()
      assert.are.equal("Accuracy: 0 / 0 (--%)", readout().last.text)
    end)

    it("ignores a chunk that is not the action packet", function()
      place()
      widget.update("chunk", 0x029, "raw bytes", {
        actor_id = player.id,
        targets = { { id = 99, actions = { { message = 1 } } } },
      })
      widget.update()
      assert.are.equal("Accuracy: 0 / 0 (--%)", readout().last.text)
    end)

    it("ignores an action packet the entry point could not parse", function()
      place()
      widget.update("chunk", 0x028, "raw bytes", nil)
      widget.update()
      assert.are.equal("Accuracy: 0 / 0 (--%)", readout().last.text)
    end)

    it("pushes the line only when it changes", function()
      place()
      swing({ 1 })
      widget.update()
      local pushes = #readout().calls
      widget.update()
      widget.update()
      assert.are.equal(pushes, #readout().calls)
    end)

    it("hides the row with the rest of the widget", function()
      place()
      widget.hide()
      assert.is_false(readout().visible)
      assert.is_false(reset_button().visible)
      widget.show()
      assert.is_true(readout().visible)
      assert.is_true(reset_button().visible)
    end)

    it("keeps the row down while the setting is off", function()
      widget.defaults.accuracy.enabled = false
      place()
      assert.is_false(readout().visible)
      assert.is_false(reset_button().visible)
      assert.is_true(background().visible)
    end)

    --[[ speedcheck's rule: a detach forgets, so a logout cannot carry one
         character's numbers into the next. ]]
    it("forgets the window when it is detached", function()
      place()
      swing({ 1, 1, 15 })
      widget.update()
      widget.detach()
      place()
      assert.are.equal("Accuracy: 0 / 0 (--%)", readout().last.text)
    end)

    it("raises the row when the command switches it on", function()
      widget.defaults.accuracy.enabled = false
      place()
      widget.handle_command({ "accuracy", "on" })
      assert.is_true(readout().visible)
      assert.are.equal(200, readout().y)
    end)
  end)

  describe("the reset button", function()
    before_each(function()
      place()
      swing({ 1, 1, 15 })
      widget.update()
    end)

    it("empties the window when it is clicked", function()
      local x, y = on_button()
      assert.is_true(widget.on_mouse(MOUSE_LEFT_DOWN, x, y))
      widget.update()
      assert.are.equal("Accuracy: 0 / 0 (--%)", readout().last.text)
    end)

    it("swallows the release of a click it took", function()
      local x, y = on_button()
      widget.on_mouse(MOUSE_LEFT_DOWN, x, y)
      assert.is_true(widget.on_mouse(MOUSE_LEFT_UP, x, y))
      assert.is_false(widget.on_mouse(MOUSE_LEFT_UP, x, y))
    end)

    it("leaves a click anywhere else to the game", function()
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, 1000, 1000))
      widget.update()
      assert.are.equal("Accuracy: 2 / 3 (67%)", readout().last.text)
    end)

    it("leaves every other button to the game", function()
      local x, y = on_button()
      assert.is_false(widget.on_mouse(MOUSE_RIGHT_DOWN, x, y))
      widget.update()
      assert.are.equal("Accuracy: 2 / 3 (67%)", readout().last.text)
    end)

    it("is inert while the widget is hidden", function()
      widget.hide()
      local x, y = reset_button().x + 2, reset_button().y + 2
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, x, y))
    end)

    it("is inert while the row is switched off", function()
      widget.handle_command({ "accuracy", "off" })
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, 100, 200))
    end)

    --[[ Layout mode owns the mouse outright, so nothing should arrive here
         then; the widget refuses on its own preview flag rather than trusting
         core to have stopped dispatching, exactly as the crossbar's sword
         does. ]]
    it("is inert while layout mode is previewing", function()
      widget.set_preview(true)
      local x, y = on_button()
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, x, y))
    end)
  end)

  describe("layout", function()
    before_each(attach)

    it("moves every prim as a group", function()
      widget.set_pos(100, 200)
      assert.are.same({ 100, 218 }, { background().x, background().y })
      assert.are.same({ 115, 220 }, { fill(1).x, fill(1).y })
      assert.are.same({ 275, 220 }, { fill(2).x, fill(2).y })
      assert.are.same({ 165, 220 }, { number(1).x, number(1).y })
      assert.are.same({ 435, 200 }, { reset_button().x, reset_button().y })
    end)

    it("scales positions, sizes and the font together", function()
      widget.set_pos(100, 200)
      widget.set_scale(2)
      assert.are.same({ 944, 48 }, { background().width, background().height })
      assert.are.same({ 130, 239 }, { fill(1).x, fill(1).y })
      assert.are.equal(28, number(1).font_size)
    end)

    it("reports bounds covering the frame and the accuracy row above it", function()
      widget.set_pos(100, 200)
      assert.are.same({ 100, 200, 575, 42 }, { widget.get_bounds() })
      widget.set_scale(0.5)
      assert.are.same({ 100, 200, 288.5, 21 }, { widget.get_bounds() })
    end)

    it("reports no bounds before it has a position", function()
      assert.is_nil(widget.get_bounds())
    end)

    it("stretches the fills to the eased width at the current scale", function()
      widget.set_pos(0, 0)
      widget.set_scale(2)
      settle()
      assert.are.same({ 264, 16 }, { fill(1).width, fill(1).height })
    end)
  end)

  describe("rendering", function()
    before_each(function()
      attach()
      widget.set_pos(0, 0)
      widget.show()
      settle()
    end)

    it("eases the fill towards its target instead of jumping", function()
      vital("hpp", 50)
      widget.update()
      assert.is_true(fill(1).width > 66 and fill(1).width < 132, "mid-animation, got " .. tostring(fill(1).width))
      settle()
      assert.are.equal(66, fill(1).width)
    end)

    it("re-sizes the fills when the scale changes, not just the background", function()
      assert.are.same({ 132, 8 }, { fill(1).width, fill(1).height })
      widget.set_scale(2)
      settle()
      assert.are.same({ 264, 16 }, { fill(1).width, fill(1).height })
    end)

    it("stops touching the prims once a bar has settled", function()
      settle()
      local before = #fill(1).calls
      widget.update()
      widget.update()
      assert.are.equal(before, #fill(1).calls, "a settled bar must not be rewritten every frame")
    end)

    it("hides an emptied fill and brings it back on a refill", function()
      vital("hpp", 0)
      settle()
      assert.is_false(fill(1).visible)
      vital("hpp", 100)
      settle()
      assert.is_true(fill(1).visible)
    end)

    it("colours the number for the low-HP band it is in", function()
      vital("hpp", 20)
      settle()
      assert.are.same({ 252, 129, 130 }, number(1).last.color)
    end)

    it("highlights the TP number and undims the TP fill at full TP", function()
      vital("tp", 1000)
      settle()
      assert.are.same({ 80, 180, 250 }, number(3).last.color)
      assert.are.equal(255, fill(3).last.alpha)
    end)

    it("dims only the TP fill below full TP", function()
      vital("tp", 500)
      settle()
      assert.are.equal(180, fill(3).last.alpha)
      assert.are.equal(255, fill(1).last.alpha)
      assert.are.equal(255, fill(2).last.alpha)
    end)

    it("keeps the last known vitals when the player is briefly unreadable", function()
      settle()
      assert.are.equal("1000", number(1).last.text)
      player = nil
      settle()
      assert.are.equal("1000", number(1).last.text, "a nil player must not blank the bars")
    end)

    -- The client fills the player in field by field, so a vitals table can be
    -- absent on a player that is otherwise readable.
    it("keeps the last known vitals when the player has no vitals table", function()
      settle()
      player = { name = "Kevin" }
      settle()
      assert.are.equal("1000", number(1).last.text)
    end)

    --[[ Whatever the player service hands over is what gets drawn, on the very
         next frame. Reconciling the absolute and percent streams - the defect
         that had an HP number stuck at max HP for a whole session - is that
         service's job and is pinned in tests/player_spec.lua; all that is left
         here is that the widget does not hold a value of its own. ]]
    it("follows the player it is handed, every frame", function()
      settle()
      player.vitals = { hp = 700, hpp = 70, mp = 100, mpp = 20, tp = 0 }
      settle()
      assert.are.equal("700", number(1).last.text)
      assert.are.equal("100", number(2).last.text)
    end)

    it("ignores a forwarded event, having no vitals of its own to update", function()
      settle()
      assert.has_no.errors(function()
        widget.update("hp", 9999)
        widget.update("status", 0, 4)
      end)
      assert.are.equal("1000", number(1).last.text)
    end)
  end)

  describe("visibility", function()
    before_each(function()
      attach()
      widget.set_pos(0, 0)
    end)

    it("shows and hides every prim", function()
      widget.show()
      settle()
      for _, prim in ipairs(prims.all) do
        assert.is_true(prim.visible, prim.kind .. " should be visible")
      end

      widget.hide()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    it("leaves an empty fill hidden even when the widget is shown", function()
      player.vitals.hpp = 0
      settle()
      widget.show()
      assert.is_true(background().visible)
      assert.is_false(fill(1).visible)
    end)

    it("keeps everything hidden while hidden, whatever the bars do", function()
      widget.hide()
      vital("hpp", 100)
      settle()
      assert.is_false(fill(1).visible)
    end)
  end)

  describe("preview", function()
    before_each(function()
      attach()
      widget.set_pos(0, 0)
      widget.show()
    end)

    it("renders sample vitals so an empty HUD can be positioned", function()
      widget.set_preview(true)
      settle()
      assert.are.equal(99, fill(1).width)
      assert.are.same({ 80, 180, 250 }, number(3).last.color)
    end)

    it("goes back to live vitals on the way out", function()
      settle()
      widget.set_preview(true)
      settle()
      widget.set_preview(false)
      settle()
      assert.are.equal("1000", number(1).last.text)
    end)
  end)

  describe("commands", function()
    before_each(function()
      attach()
      widget.set_pos(0, 0)
    end)

    it("reports its metrics without saving", function()
      local reply = widget.handle_command({})
      assert.is_not_nil(reply:find("132", 1, true))
      assert.are.equal(0, saves)
    end)

    it("applies a new width, re-lays out and saves once", function()
      widget.handle_command({ "width", "100" })
      assert.are.equal(1, saves)
      assert.are.equal(100 + 18, fill(2).x - fill(1).x - 10, "the second fill follows the new width")
      settle()
      assert.are.equal(100, fill(1).width)
    end)

    it("switches the background image with compact mode", function()
      widget.handle_command({ "compact", "on" })
      assert.are.equal("addons/XIVHud/assets/ffxiv/bar_compact.png", background().last.path)
      assert.are.equal(421, background().width)
    end)

    it("does not save a rejected command", function()
      local reply = widget.handle_command({ "width", "2" })
      assert.are.equal(0, saves)
      assert.is_not_nil(reply:find("8", 1, true))
    end)
  end)

  describe("teardown", function()
    it("disposes every prim so a reload leaves nothing on screen", function()
      attach()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed, prim.kind .. " was not disposed")
      end
    end)

    it("hides on detach and stops rendering", function()
      attach()
      widget.set_pos(0, 0)
      widget.show()
      settle()
      widget.detach()
      assert.is_false(background().visible)
      assert.has_no.errors(function()
        widget.update()
      end)
    end)
  end)
end)
