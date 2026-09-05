local build_defaults = require("components/statusbar/defaults")

describe("statusbar defaults", function()
  local defaults

  before_each(function()
    defaults = build_defaults(1920, 1080)
  end)

  it("seeds three bars: everything on the first, debuffs and other on the rest", function()
    assert.are.equal("all", defaults.bars.bar1.filter)
    assert.are.equal("debuffs", defaults.bars.bar2.filter)
    assert.are.equal("other", defaults.bars.bar3.filter)
  end)

  it("gives every bar one row and an empty blacklist", function()
    for _, name in ipairs({ "bar1", "bar2", "bar3" }) do
      local bar = defaults.bars[name]
      assert.are.equal(1, bar.rows, name)
      assert.are.same({}, bar.filters, name)
      assert.are.equal("blacklist", bar.filter_mode, name)
    end
  end)

  it("shares one priority order and shows timers and tooltips", function()
    assert.are.same({}, defaults.priority)
    assert.is_true(defaults.timers)
    assert.is_true(defaults.tooltips)
  end)

  it("places one anchor per bar, at scale 1, with no top-level pos", function()
    assert.is_nil(defaults.layout.pos)
    assert.is_nil(defaults.layout.scale)
    for _, name in ipairs({ "bar1", "bar2", "bar3" }) do
      local anchor = defaults.layout.anchors[name]
      assert.is_number(anchor.pos.x, name)
      assert.is_number(anchor.pos.y, name)
      assert.are.equal(1, anchor.scale, name)
    end
    assert.is_true(defaults.layout.visible)
  end)

  -- Absent means shown, so the first bar says nothing about it.
  it("switches the second and third bars off out of the box", function()
    assert.is_nil(defaults.layout.anchors.bar1.visible)
    assert.is_false(defaults.layout.anchors.bar2.visible)
    assert.is_false(defaults.layout.anchors.bar3.visible)
  end)

  it("stacks the bars down the screen", function()
    local anchors = defaults.layout.anchors
    assert.is_true(anchors.bar1.pos.y < anchors.bar2.pos.y)
    assert.is_true(anchors.bar2.pos.y < anchors.bar3.pos.y)
    assert.are.equal(anchors.bar1.pos.x, anchors.bar2.pos.x)
  end)

  it("scales the placement with the screen", function()
    local large = build_defaults(3840, 2160)
    assert.is_true(large.layout.anchors.bar1.pos.y > defaults.layout.anchors.bar1.pos.y)
  end)

  it("builds a fresh table every time", function()
    assert.are_not.equal(defaults, build_defaults(1920, 1080))
    assert.are_not.equal(defaults.bars.bar1.filters, build_defaults(1920, 1080).bars.bar1.filters)
  end)

  it("copes with an unknown screen", function()
    local blind = build_defaults(nil, nil)
    assert.is_number(blind.layout.anchors.bar1.pos.x)
  end)
end)
