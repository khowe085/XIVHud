local new_layout = require("lib/layout")
local new_layout_mode = require("lib/layout_mode")

-- Windower mouse event types (see the Events wiki).
local MOVE, LEFT_DOWN, LEFT_UP, RIGHT_DOWN, RIGHT_UP, WHEEL = 0, 1, 2, 4, 5, 10
local DIK_LCONTROL, DIK_RCONTROL, DIK_SHIFT = 29, 157, 42

describe("layout_mode", function()
  local components, applied, persisted, mode

  local function widget(name, x, y, width, height)
    local w = { name = name, state = { pos = { x = x, y = y }, scale = 1, visible = true } }
    function w.get_bounds()
      return w.state.pos.x, w.state.pos.y, width, height
    end
    components[#components + 1] = w
    return w
  end

  local function pos_of(w)
    return { w.state.pos.x, w.state.pos.y }
  end

  before_each(function()
    components, applied, persisted = {}, {}, {}
    local layout = new_layout({
      screen = function()
        return 1920, 1080
      end,
      snap_size = function()
        return 10
      end,
    })
    mode = new_layout_mode({
      layout = layout,
      components = function()
        return components
      end,
      state = function(component, anchor)
        if anchor then
          return component.state.anchors and component.state.anchors[anchor]
        end
        return component.state
      end,
      apply = function(component)
        applied[component.name] = (applied[component.name] or 0) + 1
      end,
      persist = function(component)
        persisted[component.name] = (persisted[component.name] or 0) + 1
      end,
    })
  end)

  describe("while inactive", function()
    it("ignores every mouse event", function()
      local bar = widget("bar", 100, 200, 200, 100)
      assert.is_false(mode.active())
      assert.is_false(mode.mouse(LEFT_DOWN, 150, 250))
      assert.is_false(mode.mouse(MOVE, 400, 500))
      assert.is_false(mode.mouse(WHEEL, 150, 250, 120))
      assert.is_false(mode.mouse(RIGHT_DOWN, 150, 250))
      assert.are.same({ 100, 200 }, pos_of(bar))
      assert.are.same({}, persisted)
    end)
  end)

  describe("entering and leaving", function()
    it("re-applies every component on enter and on exit", function()
      widget("bar", 0, 0, 10, 10)
      widget("clock", 0, 0, 10, 10)

      mode.enter()
      assert.is_true(mode.active())
      assert.are.same({ bar = 1, clock = 1 }, applied)

      mode.exit()
      assert.is_false(mode.active())
      assert.are.same({ bar = 2, clock = 2 }, applied)
    end)

    it("toggles", function()
      assert.is_true(mode.toggle())
      assert.is_false(mode.toggle())
    end)

    it("entering twice does not restart anything", function()
      widget("bar", 0, 0, 10, 10)
      mode.enter()
      mode.enter()
      assert.are.equal(1, applied.bar)
    end)

    it("forgets a held CTRL between sessions, since the key handler is gone in between", function()
      local bar = widget("bar", 100, 200, 200, 100)
      mode.enter()
      mode.key(DIK_LCONTROL, true)
      mode.exit()

      mode.enter()
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 404, 456)
      assert.are.same({ 350, 410 }, pos_of(bar), "the grid must be back on")
    end)

    it("saves a drag that is still in progress when the mode is left", function()
      local bar = widget("bar", 100, 200, 200, 100)
      mode.enter()
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 400, 500)
      mode.exit()

      assert.are.same({ 350, 450 }, pos_of(bar))
      assert.are.equal(1, persisted.bar)
      assert.is_false(mode.mouse(MOVE, 600, 600))
    end)
  end)

  describe("dragging", function()
    local bar

    before_each(function()
      bar = widget("bar", 100, 200, 200, 100)
      mode.enter()
    end)

    it("moves the widget by the grab offset, not to the cursor", function()
      assert.is_true(mode.mouse(LEFT_DOWN, 150, 250))
      assert.is_true(mode.mouse(MOVE, 400, 500))
      assert.are.same({ 350, 450 }, pos_of(bar))
    end)

    it("snaps to the grid by default", function()
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 404, 456)
      assert.are.same({ 350, 410 }, pos_of(bar))
    end)

    it("moves freely while CTRL is held", function()
      mode.key(DIK_LCONTROL, true)
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 404, 456)
      assert.are.same({ 354, 406 }, pos_of(bar))
    end)

    it("honours the right CTRL key too, and ignores other keys", function()
      mode.key(DIK_SHIFT, true)
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 404, 456)
      assert.are.same({ 350, 410 }, pos_of(bar))

      mode.key(DIK_RCONTROL, true)
      mode.mouse(MOVE, 404, 456)
      assert.are.same({ 354, 406 }, pos_of(bar))
    end)

    it("picks up CTRL being released part way through a drag", function()
      mode.key(DIK_LCONTROL, true)
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 404, 456)
      assert.are.same({ 354, 406 }, pos_of(bar))

      mode.key(DIK_LCONTROL, false)
      mode.mouse(MOVE, 404, 456)
      assert.are.same({ 350, 410 }, pos_of(bar))
    end)

    it("clamps a drag past the screen edge", function()
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 1900, 1050)
      assert.are.same({ 1720, 980 }, pos_of(bar))
    end)

    it("saves once, on release", function()
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 400, 500)
      mode.mouse(MOVE, 410, 510)
      assert.is_nil(persisted.bar)
      assert.is_true(mode.mouse(LEFT_UP, 410, 510))
      assert.are.equal(1, persisted.bar)
    end)

    it("stops moving after release", function()
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(LEFT_UP, 150, 250)
      assert.is_false(mode.mouse(MOVE, 900, 900))
      assert.are.same({ 100, 200 }, pos_of(bar))
    end)

    it("ignores a press that misses every widget", function()
      assert.is_false(mode.mouse(LEFT_DOWN, 900, 900))
      assert.is_false(mode.mouse(MOVE, 400, 500))
      assert.are.same({ 100, 200 }, pos_of(bar))
    end)

    it("treats the bounding box as half-open, so touching edges do not both grab", function()
      assert.is_true(mode.mouse(LEFT_DOWN, 100, 200))
      mode.mouse(LEFT_UP, 100, 200)
      assert.is_false(mode.mouse(LEFT_DOWN, 300, 300), "right/bottom edge belongs to the next widget")
    end)

    it("gives the drag to the widget registered last where they overlap", function()
      local clock = widget("clock", 150, 250, 200, 100)
      mode.mouse(LEFT_DOWN, 200, 300)
      mode.mouse(MOVE, 400, 500)
      assert.are.same({ 100, 200 }, pos_of(bar))
      assert.are.same({ 350, 450 }, pos_of(clock))
    end)

    it("skips a component that cannot report bounds yet", function()
      local pending = widget("pending", 0, 0, 0, 0)
      pending.get_bounds = function()
        return nil
      end
      assert.is_true(mode.mouse(LEFT_DOWN, 150, 250))
      assert.are.equal("bar", mode.dragging().name)
    end)
  end)

  describe("scaling with the wheel", function()
    local bar

    before_each(function()
      bar = widget("bar", 100, 200, 200, 100)
      mode.enter()
    end)

    it("scales the widget under the cursor and saves", function()
      assert.is_true(mode.mouse(WHEEL, 150, 250, 120))
      assert.are.equal(2.2, bar.state.scale)
      assert.are.equal(1, persisted.bar)
    end)

    it("floors at a quarter size", function()
      mode.mouse(WHEEL, 150, 250, -120)
      assert.are.equal(0.25, bar.state.scale)
    end)

    it("ignores a wheel that misses every widget", function()
      assert.is_false(mode.mouse(WHEEL, 900, 900, 120))
      assert.are.equal(1, bar.state.scale)
    end)
  end)

  describe("right-click enable toggle", function()
    local bar

    before_each(function()
      bar = widget("bar", 100, 200, 200, 100)
      mode.enter()
    end)

    it("flips the slot's visible flag and saves", function()
      assert.is_true(mode.mouse(RIGHT_DOWN, 150, 250))
      assert.is_false(bar.state.visible)
      assert.are.equal(1, persisted.bar)

      mode.mouse(RIGHT_UP, 150, 250)
      mode.mouse(RIGHT_DOWN, 150, 250)
      assert.is_true(bar.state.visible)
      assert.are.equal(2, persisted.bar)
    end)

    it("swallows the matching release so the game never sees the click", function()
      mode.mouse(RIGHT_DOWN, 150, 250)
      assert.is_true(mode.mouse(RIGHT_UP, 900, 900))
      assert.is_false(mode.mouse(RIGHT_UP, 150, 250), "only the release that pairs with a handled press")
    end)

    it("ignores a right-click that misses every widget", function()
      assert.is_false(mode.mouse(RIGHT_DOWN, 900, 900))
      assert.is_true(bar.state.visible)
    end)

    it("leaves a disabled widget draggable", function()
      mode.mouse(RIGHT_DOWN, 150, 250)
      mode.mouse(RIGHT_UP, 150, 250)
      mode.mouse(LEFT_DOWN, 150, 250)
      mode.mouse(MOVE, 400, 500)
      assert.are.same({ 350, 450 }, pos_of(bar))
    end)

    it("ignores a right-click on a widget that cannot report state", function()
      local ghost = { name = "ghost" }
      function ghost.get_bounds()
        return 500, 500, 50, 50
      end
      components[#components + 1] = ghost
      assert.has_no.errors(function()
        assert.is_false(mode.mouse(RIGHT_DOWN, 510, 510))
      end)
      assert.is_nil(persisted.ghost)
    end)

    it("does not toggle mid-drag, and keeps the input to itself", function()
      mode.mouse(LEFT_DOWN, 150, 250)
      assert.is_true(mode.mouse(RIGHT_DOWN, 150, 250))
      assert.is_true(bar.state.visible)
      assert.is_nil(persisted.bar)
    end)
  end)

  -- Touchpoint 2: a widget exposing `anchors()` is hit-tested, dragged and
  -- scaled per anchor; only the right-click enable toggle stays whole-widget.
  describe("multi-anchor widgets", function()
    local cross

    -- Two 100x50 anchors: `top` at (100, 100), `bottom` at (100, 400).
    local function anchored_widget(name)
      local w = {
        name = name,
        state = {
          anchors = {
            top = { pos = { x = 100, y = 100 }, scale = 1 },
            bottom = { pos = { x = 100, y = 400 }, scale = 1 },
          },
          visible = true,
        },
      }
      function w.anchors()
        return { "top", "bottom" }
      end
      function w.get_bounds(anchor)
        local entry = w.state.anchors[anchor]
        if not entry then
          return nil
        end
        return entry.pos.x, entry.pos.y, 100, 50
      end
      components[#components + 1] = w
      return w
    end

    local function anchor_pos(w, anchor)
      return { w.state.anchors[anchor].pos.x, w.state.anchors[anchor].pos.y }
    end

    before_each(function()
      cross = anchored_widget("cross")
      mode.enter()
    end)

    it("drags the anchor under the cursor and leaves the others alone", function()
      assert.is_true(mode.mouse(LEFT_DOWN, 150, 425))
      assert.is_true(mode.mouse(MOVE, 650, 725))
      assert.are.same({ 600, 700 }, anchor_pos(cross, "bottom"))
      assert.are.same({ 100, 100 }, anchor_pos(cross, "top"))
    end)

    it("saves the component once when an anchor drag ends", function()
      mode.mouse(LEFT_DOWN, 150, 425)
      mode.mouse(MOVE, 650, 725)
      assert.is_nil(persisted.cross)
      mode.mouse(LEFT_UP, 650, 725)
      assert.are.equal(1, persisted.cross)
    end)

    it("snaps and clamps an anchor drag like any other", function()
      mode.mouse(LEFT_DOWN, 150, 425)
      mode.mouse(MOVE, 154, 429)
      assert.are.same({ 100, 400 }, anchor_pos(cross, "bottom"))
      mode.mouse(MOVE, 1900, 1070)
      assert.are.same({ 1820, 1030 }, anchor_pos(cross, "bottom"))
    end)

    it("gives an overlapping pixel to the anchor later in the list", function()
      cross.state.anchors.bottom.pos = { x = 120, y = 120 }
      mode.mouse(LEFT_DOWN, 150, 140)
      mode.mouse(MOVE, 650, 640)
      assert.are.same({ 620, 620 }, anchor_pos(cross, "bottom"))
      assert.are.same({ 100, 100 }, anchor_pos(cross, "top"))
    end)

    it("scales only the anchor under the wheel", function()
      assert.is_true(mode.mouse(WHEEL, 150, 425, 120))
      assert.are.equal(2.2, cross.state.anchors.bottom.scale)
      assert.are.equal(1, cross.state.anchors.top.scale)
      assert.are.equal(1, persisted.cross)
    end)

    it("toggles the whole widget with a right-click on any anchor", function()
      assert.is_true(mode.mouse(RIGHT_DOWN, 150, 425))
      assert.is_false(cross.state.visible)
      assert.are.equal(1, persisted.cross)
      mode.mouse(RIGHT_UP, 150, 425)
      mode.mouse(RIGHT_DOWN, 150, 125)
      assert.is_true(cross.state.visible, "the top anchor toggles the same flag")
    end)

    it("still hit-tests a plain widget drawn over an anchor", function()
      local bar = widget("bar", 80, 380, 200, 100)
      mode.mouse(LEFT_DOWN, 150, 425)
      mode.mouse(MOVE, 650, 725)
      assert.are.same({ 580, 680 }, pos_of(bar), "the later registration wins the pixel")
      assert.are.same({ 100, 400 }, anchor_pos(cross, "bottom"))
    end)

    it("abandons a drag whose anchor state disappears mid-drag", function()
      mode.mouse(LEFT_DOWN, 150, 425)
      cross.state.anchors.bottom = nil
      assert.has_no.errors(function()
        assert.is_true(mode.mouse(MOVE, 650, 725), "the grab still owns the mouse")
        assert.is_true(mode.mouse(LEFT_UP, 650, 725))
      end)
      assert.are.same({ 100, 100 }, anchor_pos(cross, "top"))
    end)

    it("treats a non-table anchors() answer as a single-anchor widget", function()
      local odd = widget("odd", 100, 200, 200, 100)
      odd.anchors = function()
        return 5
      end
      assert.is_true(mode.mouse(LEFT_DOWN, 150, 250))
      mode.mouse(MOVE, 400, 500)
      assert.are.same({ 350, 450 }, pos_of(odd))
    end)

    it("ignores input on an anchor whose state entry is missing", function()
      cross.get_bounds = function()
        return 100, 400, 100, 50
      end
      cross.state.anchors = {}
      assert.is_false(mode.mouse(LEFT_DOWN, 150, 425))
      assert.is_false(mode.mouse(WHEEL, 150, 425, 120))
      assert.is_nil(persisted.cross)
    end)
  end)

  describe("unhandled input", function()
    it("passes through mouse types the mode does not use", function()
      widget("bar", 100, 200, 200, 100)
      mode.enter()
      assert.is_false(mode.mouse(99, 150, 250))
    end)

    it("passes a plain move through when nothing is being dragged", function()
      widget("bar", 100, 200, 200, 100)
      mode.enter()
      assert.is_false(mode.mouse(MOVE, 150, 250))
    end)
  end)
end)
