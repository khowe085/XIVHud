local new_render = require("components/hotbar/render")
local defaults = require("lib/actionbar/defaults")

local PITCH = 46 -- 40 + slot_spacing
local ROW_PITCH = 56 -- the slot pitch plus the 10px name band under a row
local NAME_BAND = 10

local function make(overrides)
  local config = defaults.cosmetics()
  for key, value in pairs(overrides or {}) do
    config[key] = value
  end
  return new_render({ config = config }), config
end

describe("hotbar render", function()
  describe("the four shapes", function()
    it("knows exactly four row counts", function()
      local render = make()
      assert.are.equal(10, render.columns_for(1))
      assert.are.equal(5, render.columns_for(2))
      assert.are.equal(2, render.columns_for(5))
      assert.are.equal(1, render.columns_for(10))
      assert.is_nil(render.columns_for(3))
      assert.is_nil(render.columns_for(nil))
    end)

    it("lays the ten slots out row-major on the slot pitch", function()
      local render = make()
      local metrics = render.metrics(1)
      local gx, gy = metrics.grid_x, metrics.grid_y
      assert.are.same({ gx, gy }, { render.slot_pos(1, 1) })
      assert.are.same({ gx + 9 * PITCH, gy }, { render.slot_pos(1, 10) })
      metrics = render.metrics(2)
      gx, gy = metrics.grid_x, metrics.grid_y
      assert.are.same({ gx + 4 * PITCH, gy }, { render.slot_pos(2, 5) }, "5x2: slot 5 ends the top row")
      assert.are.same({ gx, gy + ROW_PITCH }, { render.slot_pos(2, 6) }, "and slot 6 starts the bottom one")
      metrics = render.metrics(5)
      gx, gy = metrics.grid_x, metrics.grid_y
      assert.are.same({ gx + PITCH, gy + ROW_PITCH }, { render.slot_pos(5, 4) }, "2x5: 1-2, 3-4 down")
      metrics = render.metrics(10)
      gx, gy = metrics.grid_x, metrics.grid_y
      assert.are.same({ gx, gy + 9 * ROW_PITCH }, { render.slot_pos(10, 10) }, "1x10: slot 1 at the top")
      assert.is_nil(render.slot_pos(1, 11))
      assert.is_nil(render.slot_pos(3, 1))
    end)

    it("puts the set number before slot 1: left of it on the wide shapes, above on the tall", function()
      local render = make()
      for _, rows in ipairs({ 1, 2 }) do
        local metrics = render.metrics(rows)
        local x, y = render.label_pos(rows)
        assert.are.equal(0, x, "wide: the label starts the row")
        assert.is_true(metrics.grid_x > 0, "and the grid sits to its right")
        assert.are.equal(0, metrics.grid_y)
        assert.are.equal(10, y, "centred on the slot at the digit's drawn height")
      end
      for _, rows in ipairs({ 5, 10 }) do
        local metrics = render.metrics(rows)
        local x, y = render.label_pos(rows)
        assert.are.same({ 0, 0 }, { x, y }, "tall: the label tops the column")
        assert.are.equal(0, metrics.grid_x)
        assert.is_true(metrics.grid_y >= 20 + 4, "and the grid sits under the digit's drawn height, not its point size")
      end
    end)

    it("bounds label, every slot and the name band under the last row, in every shape", function()
      local render = make()
      local metrics = render.metrics(1)
      local width, height = render.bounds(1)
      assert.are.equal(metrics.grid_x + 9 * PITCH + 40, width)
      assert.are.equal(40 + NAME_BAND, height, "the names draw under the slots")
      width, height = render.bounds(10)
      assert.are.equal(40, width)
      assert.are.equal(render.metrics(10).grid_y + 9 * ROW_PITCH + 40 + NAME_BAND, height)
      width, height = render.bounds(2, 2)
      assert.are.equal(2 * (metrics.grid_x + 4 * PITCH + 40), width, "scaled")
      assert.are.equal(2 * (ROW_PITCH + 40 + NAME_BAND), height)
      assert.is_nil(render.bounds(3))
    end)

    it("leaves the name band between two rows of one shape, and between stacked rows", function()
      local render = make()
      local _, y1 = render.slot_pos(2, 1)
      local _, y6 = render.slot_pos(2, 6)
      assert.is_true(y6 - y1 >= 40 + NAME_BAND, "row 2 of a 5x2 clears row 1's names")
      assert.are.equal(select(2, render.bounds(1)) + 8, render.row_pitch())
      assert.is_true(render.row_pitch() >= 40 + NAME_BAND + 8)
    end)
  end)

  describe("the hit-test", function()
    local function group(overrides)
      local entry = { key = "bar2", x = 100, y = 500, scale = 1, set = 2, side = "row", rows = 2 }
      for key, value in pairs(overrides or {}) do
        entry[key] = value
      end
      return entry
    end

    it("answers one rect per slot of every group, addressed by its set and the row side", function()
      local render = make()
      local rects = render.slot_rects({ group(), group({ key = "bar1", y = 400, set = 4, rows = 1 }) })
      assert.are.equal(20, #rects)
      assert.are.same({ "bar2", 2, "row", 7 }, { rects[7].key, rects[7].set, rects[7].side, rects[7].slot })
      local x, y = render.slot_pos(2, 7)
      assert.are.same({ 100 + x, 500 + y, 40, 40 }, { rects[7].x, rects[7].y, rects[7].width, rects[7].height })
      assert.are.equal(4, rects[11].set)
      assert.are.same({}, render.slot_rects(nil))
    end)

    it("resolves a point to the slot under it, scaled", function()
      local render = make()
      local groups = { group({ scale = 2 }) }
      local x, y = render.slot_pos(2, 8)
      local hit = render.slot_at(groups, 100 + x * 2 + 5, 500 + y * 2 + 5)
      assert.are.equal(8, hit.slot)
      assert.is_nil(render.slot_at(groups, 0, 0))
      assert.is_nil(render.slot_at(groups, 100 + x * 2 + 5, 500 + y * 2 + 5, function()
        return false
      end))
    end)
  end)

  it("re-exports the shared slot render, one instance", function()
    local render = make()
    assert.are.equal(40, render.slot_size())
    assert.are.equal("Cure", render.slot_label("Cure"))
    assert.are.equal(32, render.sweep("k", 10))
    assert.is_function(render.icon_candidates)
    assert.is_function(render.remaining_for)
    assert.is_function(render.cost)
  end)
end)
