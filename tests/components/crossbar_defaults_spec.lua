local build_defaults = require("components/crossbar/defaults")

local WIDTH, HEIGHT = 1920, 1080

describe("crossbar defaults", function()
  local defaults

  before_each(function()
    defaults = build_defaults(WIDTH, HEIGHT)
  end)

  it("ships the v4 input map", function()
    assert.same({ 39 }, defaults.input.xhb_left)
    assert.same({ 40 }, defaults.input.xhb_right)
    assert.same({ 43 }, defaults.input.w_layer)
    assert.same({ 41 }, defaults.input.set_switch)
    assert.same({ 2, 3, 4, 5, 6, 7, 8, 9 }, defaults.input.slot_keys)
    -- Chord only: bare Select does nothing, though the key stays ours.
    assert.same({ chorded = "edit" }, defaults.input.shortcuts[13])
  end)

  it("points each view at a set nothing else is showing", function()
    -- The XHB starts on set 1, so the WXHB takes set 2 and Expanded set 3.
    assert.same({ set = 2, side = "left" }, defaults.views.wxhb_left)
    assert.same({ set = 2, side = "right" }, defaults.views.wxhb_right)
    assert.same({ set = 3, side = "left" }, defaults.views.expanded_lr)
    assert.same({ set = 3, side = "right" }, defaults.views.expanded_rl)
  end)

  it("keeps the WXHB off screen at rest", function()
    assert.is_false(defaults.always_show_wxhb)
  end)

  it("flags all eight sets unshared and cycled in both weapon states", function()
    for set = 1, 8 do
      assert.same({ shared = false, cycle = { drawn = true, sheathed = true } }, defaults.set_flags[set])
    end
    assert.is_nil(defaults.set_flags[9])
  end)

  it("keeps upstream's geometry and alpha values", function()
    assert.equal(6, defaults.slot_spacing)
    assert.equal(56, defaults.bar_spacing)
    assert.equal(100, defaults.slot_alpha)
    assert.equal(150, defaults.button_bg_alpha)
    assert.equal(100, defaults.disabled_alpha)
  end)

  it("hides only the element by default", function()
    assert.same({
      empty_slots = false,
      action_name = false,
      cost = false,
      element = true,
      recast_animation = false,
      recast_text = false,
      skillchain_icon = false,
    }, defaults.hide)
  end)

  it("ships an empty game_path override, equipviewer's idiom", function()
    -- Discoverable in the file players read; the widget's guard treats
    -- empty as "use the client's own answer".
    assert.equal("", defaults.game_path)
  end)

  it("carries the press-flash, text and cost colour settings", function()
    assert.same({ alpha = 150, speed = 30 }, defaults.feedback)
    assert.equal("sans-serif", defaults.font)
    assert.equal(7, defaults.font_size)
    assert.same({ x = 0, y = 0 }, defaults.text_offset)
    assert.same({ a = 255, r = 255, g = 255, b = 255 }, defaults.text_color)
    assert.same({ width = 2, a = 200, r = 20, g = 20, b = 20 }, defaults.text_stroke)
    assert.same({ r = 230, g = 91, b = 151 }, defaults.mp_cost_color)
    assert.same({ r = 254, g = 222, b = 0 }, defaults.tp_cost_color)
  end)

  it("carries no skillchain indicator block - the indicator is its own component", function()
    assert.is_nil(defaults.skillchain)
  end)

  it("carries none of the action service's tuning - that is core.lua's", function()
    assert.is_nil(defaults.retry)
    assert.is_nil(defaults.wsgate)
    assert.is_nil(defaults.delay)
  end)

  it("places all four anchors on screen", function()
    local anchors = defaults.layout.anchors
    for _, name in ipairs({ "main", "wxhb_left", "wxhb_right", "set", "weapon" }) do
      local anchor = anchors[name]
      assert.is_table(anchor, name)
      assert.equal(1, anchor.scale, name)
      assert.is_true(anchor.pos.x >= 0 and anchor.pos.x < WIDTH, name .. " x on screen")
      assert.is_true(anchor.pos.y >= 0 and anchor.pos.y < HEIGHT, name .. " y on screen")
    end
    -- Visibility is per component, never per anchor.
    assert.is_true(defaults.layout.visible)
    assert.is_nil(anchors.main.visible)
  end)

  it("centres the XHB on the real footprint above the screen bottom", function()
    -- render.lua's main footprint is 630x180; upstream anchors its bottom
    -- slot row at ui_y_res - 120, which puts our panel-top origin 211 up
    -- (120 + the 35px pad + two 28px rows) - clear of the 180-tall box.
    local anchors = defaults.layout.anchors
    assert.equal((WIDTH - 630) / 2, anchors.main.pos.x)
    assert.equal(HEIGHT - 211, anchors.main.pos.y)
    -- The WXHB halves mirror the XHB's side columns, one bar height up.
    assert.equal(anchors.main.pos.x, anchors.wxhb_left.pos.x)
    assert.equal(anchors.main.pos.x + 300, anchors.wxhb_right.pos.x)
    assert.equal(anchors.main.pos.y - 180, anchors.wxhb_left.pos.y)
    assert.equal(anchors.wxhb_left.pos.y, anchors.wxhb_right.pos.y)
    assert.is_nil(anchors.skillchain_indicator, "the indicator is its own component now")
  end)

  it("survives a zero screen (size not yet known)", function()
    local zero = build_defaults(0, 0)
    for name, anchor in pairs(zero.layout.anchors) do
      assert.is_true(anchor.pos.x >= 0, name)
      assert.is_true(anchor.pos.y >= 0, name)
    end
  end)

  it("builds a fresh table on every call", function()
    local first = build_defaults(WIDTH, HEIGHT)
    local second = build_defaults(WIDTH, HEIGHT)
    first.input.slot_keys[1] = 999
    first.set_flags[1].cycle.drawn = false
    assert.equal(2, second.input.slot_keys[1])
    assert.is_true(second.set_flags[1].cycle.drawn)
  end)
end)
