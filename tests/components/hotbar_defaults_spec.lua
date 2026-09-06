local build_defaults = require("components/hotbar/defaults")
local new_render = require("components/hotbar/render")

local ANCHORS = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" }

describe("hotbar defaults", function()
  local defaults

  before_each(function()
    defaults = build_defaults(1920, 1080)
  end)

  it("ships every row 10x1", function()
    for _, anchor in ipairs(ANCHORS) do
      assert.are.equal(1, defaults.bars[anchor].rows, anchor)
    end
  end)

  it("carries the shared cosmetics and eight set flags", function()
    assert.are.equal(6, defaults.slot_spacing)
    assert.are.equal(7, defaults.font_size)
    assert.is_false(defaults.hide.skillchain_icon)
    assert.are.equal(8, #defaults.set_flags)
    assert.is_false(defaults.set_flags[3].shared)
    assert.are.equal("", defaults.game_path)
  end)

  it("has no crossbar furniture: no input keys, no views, no indicator block", function()
    assert.is_nil(defaults.input)
    assert.is_nil(defaults.views)
    assert.is_nil(defaults.always_show_wxhb)
    assert.is_nil(defaults.skillchain)
    assert.is_nil(defaults.retry)
    assert.is_nil(defaults.delay)
  end)

  it("stacks the eight rows down from one origin, on the 10x1 pitch, all on screen", function()
    local render = new_render({ config = defaults })
    local width, height = render.bounds(1)
    local anchors = defaults.layout.anchors
    for index, anchor in ipairs(ANCHORS) do
      local entry = anchors[anchor]
      assert.is_not_nil(entry, anchor)
      assert.are.equal(1, entry.scale)
      assert.are.equal(anchors.bar1.pos.x, entry.pos.x, "one column")
      assert.are.equal(anchors.bar1.pos.y + (index - 1) * render.row_pitch(), entry.pos.y)
      assert.is_true(entry.pos.x >= 0 and entry.pos.x + width <= 1920, anchor .. " off screen")
      assert.is_true(entry.pos.y >= 0 and entry.pos.y + height <= 1080, anchor .. " off screen")
    end
    assert.is_nil(defaults.layout.pos, "anchored: no top-level placement")
  end)

  it("ships row 1 on and rows 2-8 off, the widget itself on", function()
    local anchors = defaults.layout.anchors
    assert.is_nil(anchors.bar1.visible)
    for index = 2, 8 do
      assert.is_false(anchors["bar" .. index].visible)
    end
    assert.is_true(defaults.layout.visible)
  end)

  it("survives a zero screen", function()
    local zero = build_defaults(0, 0)
    for _, anchor in ipairs(ANCHORS) do
      assert.is_true(zero.layout.anchors[anchor].pos.x >= 0)
      assert.is_true(zero.layout.anchors[anchor].pos.y >= 0)
    end
  end)
end)
