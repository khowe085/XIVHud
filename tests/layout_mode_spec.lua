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
      state = function(component)
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

    it("does not toggle mid-drag, and keeps the input to itself", function()
      mode.mouse(LEFT_DOWN, 150, 250)
      assert.is_true(mode.mouse(RIGHT_DOWN, 150, 250))
      assert.is_true(bar.state.visible)
      assert.is_nil(persisted.bar)
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
