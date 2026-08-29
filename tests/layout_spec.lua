local new_layout = require("lib/layout")

describe("layout", function()
  local snap_size, layout

  before_each(function()
    snap_size = 10
    layout = new_layout({
      screen = function()
        return 1920, 1080
      end,
      snap_size = function()
        return snap_size
      end,
    })
  end)

  describe("snapping", function()
    it("rounds to the nearest grid line", function()
      assert.are.equal(0, layout.snap(4))
      assert.are.equal(10, layout.snap(5))
      assert.are.equal(10, layout.snap(14))
      assert.are.equal(20, layout.snap(15))
    end)

    it("rounds negatives away from zero at the halfway point", function()
      assert.are.equal(-10, layout.snap(-5))
      assert.are.equal(0, layout.snap(-4))
    end)

    it("is a no-op when the grid is off", function()
      snap_size = 0
      assert.are.equal(7, layout.snap(7))
      snap_size = nil
      assert.are.equal(7, layout.snap(7))
    end)
  end)

  describe("clamping", function()
    it("keeps a widget fully on screen", function()
      local x, y = layout.clamp(-50, -50, 200, 100)
      assert.are.same({ 0, 0 }, { x, y })

      x, y = layout.clamp(1900, 1050, 200, 100)
      assert.are.same({ 1720, 980 }, { x, y })
    end)

    it("leaves an on-screen widget alone", function()
      assert.are.same({ 100, 200 }, { layout.clamp(100, 200, 200, 100) })
    end)

    it("pins a widget wider than the screen to the origin", function()
      assert.are.same({ 0, 0 }, { layout.clamp(50, 50, 4000, 4000) })
    end)
  end)

  describe("resolve", function()
    it("snaps then clamps", function()
      assert.are.same({ 100, 200 }, { layout.resolve(97, 204, 50, 50) })
    end)

    it("snaps a widget back inside the screen rather than off its edge", function()
      -- 1899 snaps to 1900, which would put the right edge past 1920.
      assert.are.same({ 1870, 0 }, { layout.resolve(1899, 0, 50, 50) })
    end)

    it("skips the grid when free movement is asked for", function()
      assert.are.same({ 97, 204 }, { layout.resolve(97, 204, 50, 50, true) })
    end)
  end)

  describe("scale", function()
    it("floors at a quarter size", function()
      assert.are.equal(0.25, layout.clamp_scale(0.1))
      assert.are.equal(0.25, layout.clamp_scale(0.25))
      assert.are.equal(1.5, layout.clamp_scale(1.5))
    end)

    it("falls back to full size for a missing or bad value", function()
      assert.are.equal(1, layout.clamp_scale(nil))
      assert.are.equal(1, layout.clamp_scale("big"))
    end)
  end)

  describe("slot state", function()
    it("fills in a missing slot from the component's default state", function()
      local config = {}
      local state = layout.slot(config, "raid", { pos = { x = 5, y = 6 }, scale = 2, visible = false })
      assert.are.same({ pos = { x = 5, y = 6 }, scale = 2, visible = false }, state)
      assert.are.same(state, config.slots.raid)
    end)

    it("seeds a new slot from the default slot when one exists", function()
      local config = { slots = { default = { pos = { x = 40, y = 50 }, scale = 1.5, visible = true } } }
      local state = layout.slot(config, "raid", { pos = { x = 0, y = 0 }, scale = 1, visible = true })
      assert.are.same({ pos = { x = 40, y = 50 }, scale = 1.5, visible = true }, state)
      config.slots.default.pos.x = 999
      assert.are.equal(40, config.slots.raid.pos.x, "the seed must be a copy")
    end)

    it("returns the stored slot untouched when it already exists", function()
      local config = { slots = { raid = { pos = { x = 1, y = 2 }, scale = 3, visible = false } } }
      assert.are.same({ pos = { x = 1, y = 2 }, scale = 3, visible = false }, layout.slot(config, "raid", {}))
    end)

    it("repairs a slot missing individual keys", function()
      local config = { slots = { raid = { scale = 2 } } }
      local state = layout.slot(config, "raid", { pos = { x = 7, y = 8 }, scale = 1, visible = true })
      assert.are.same({ pos = { x = 7, y = 8 }, scale = 2, visible = true }, state)
    end)

    it("creates a slot as a copy of the one it is seeded from", function()
      local config = { slots = { default = { pos = { x = 1, y = 2 }, scale = 1, visible = true } } }
      config.slots.raid = { pos = { x = 10, y = 20 }, scale = 2, visible = false }

      local created = layout.create_slot(config, "party", "raid", {})
      assert.are.same({ pos = { x = 10, y = 20 }, scale = 2, visible = false }, created)
      config.slots.raid.pos.x = 999
      assert.are.equal(10, config.slots.party.pos.x, "the seed must be a copy")
    end)

    it("falls back to the default slot when the source has no entry", function()
      local config = { slots = { default = { pos = { x = 1, y = 2 }, scale = 3, visible = false } } }
      local created = layout.create_slot(config, "party", "missing", {})
      assert.are.same({ pos = { x = 1, y = 2 }, scale = 3, visible = false }, created)
    end)

    it("falls back to the component's defaults when there is nothing at all", function()
      local config = {}
      local created =
        layout.create_slot(config, "party", "missing", { pos = { x = 7, y = 8 }, scale = 1, visible = true })
      assert.are.same({ pos = { x = 7, y = 8 }, scale = 1, visible = true }, created)
    end)

    it("refuses to create a slot that already exists", function()
      local config = { slots = { raid = { scale = 2 } } }
      assert.is_nil(layout.create_slot(config, "raid", "default", {}))
      assert.are.equal(2, config.slots.raid.scale)
    end)

    it("deletes a slot, reporting whether there was one", function()
      local config = { slots = { default = {}, raid = {} } }
      assert.is_true(layout.delete_slot(config, "raid"))
      assert.is_nil(config.slots.raid)
      assert.is_false(layout.delete_slot(config, "raid"))
      assert.is_false(layout.delete_slot({}, "raid"))
    end)

    it("survives a hand-edited config that is the wrong shape throughout", function()
      local defaults = { pos = { x = 7, y = 8 }, scale = 1, visible = true }

      assert.are.same(defaults, layout.slot({ slots = 5 }, "default", defaults))
      assert.are.same(defaults, layout.slot({ slots = { default = true } }, "default", defaults))

      local text_pos = layout.slot({ slots = { default = { pos = { x = "abc", y = {} } } } }, "default", defaults)
      assert.are.same({ x = 0, y = 0 }, text_pos.pos)

      local text_scale = layout.slot({ slots = { default = { scale = "big" } } }, "default", defaults)
      assert.are.equal(1, text_scale.scale)
    end)

    it("ignores slot keys that are not names", function()
      assert.are.same({ "default", "raid" }, layout.slot_names({ slots = { default = {}, raid = {}, [3] = {} } }))
      assert.are.same({}, layout.slot_names({ slots = 5 }))
    end)

    it("lists slot names with default first and the rest sorted", function()
      local config = { slots = { zulu = {}, default = {}, alpha = {} } }
      assert.are.same({ "default", "alpha", "zulu" }, layout.slot_names(config))
    end)

    it("reports no slots for a config that has none", function()
      assert.are.same({}, layout.slot_names({}))
    end)
  end)

  -- Touchpoint 2: a component whose default slot state carries `anchors`
  -- stores pos/scale per anchor; `visible` stays at the top level.
  describe("multi-anchor slot state", function()
    local function anchored_defaults()
      return {
        anchors = {
          main = { pos = { x = 100, y = 900 }, scale = 1 },
          indicator = { pos = { x = 600, y = 700 }, scale = 1 },
        },
        visible = true,
      }
    end

    it("fills a missing slot in from the per-anchor defaults", function()
      local config = {}
      local state = layout.slot(config, "default", anchored_defaults())
      assert.are.same(anchored_defaults(), state)
      assert.are.same(state, config.slots.default)
    end)

    it("does not fabricate top-level pos or scale on an anchored entry", function()
      local state = layout.slot({}, "default", anchored_defaults())
      assert.is_nil(state.pos)
      assert.is_nil(state.scale)
    end)

    -- The CB2 stand-in registered with the anchored schema before the
    -- framework understood it, so layout.slot persisted a spurious top-level
    -- pos/scale into crossbar config. Tolerate the residue and shed it, so
    -- the first write after this repair no longer carries it.
    it("drops a stray top-level pos and scale left by the CB2 stand-in", function()
      local config = {
        slots = {
          default = {
            pos = { x = 0, y = 0 },
            scale = 1,
            visible = true,
            anchors = { main = { pos = { x = 5, y = 6 }, scale = 2 } },
          },
        },
      }
      local state = layout.slot(config, "default", anchored_defaults())
      assert.is_nil(state.pos)
      assert.is_nil(state.scale)
      assert.are.same({ pos = { x = 5, y = 6 }, scale = 2 }, state.anchors.main)
    end)

    it("repairs a missing anchor from its default without touching the others", function()
      local config = {
        slots = { default = { anchors = { main = { pos = { x = 1, y = 2 }, scale = 3 } }, visible = true } },
      }
      local state = layout.slot(config, "default", anchored_defaults())
      assert.are.same({ pos = { x = 600, y = 700 }, scale = 1 }, state.anchors.indicator)
      assert.are.same({ pos = { x = 1, y = 2 }, scale = 3 }, state.anchors.main)
    end)

    it("repairs an anchor entry that is the wrong shape throughout", function()
      local config = {
        slots = {
          default = {
            anchors = { main = "nonsense", indicator = { pos = { x = "abc", y = {} }, scale = "big" } },
          },
        },
      }
      local state = layout.slot(config, "default", anchored_defaults())
      assert.are.same({ pos = { x = 100, y = 900 }, scale = 1 }, state.anchors.main)
      assert.are.same({ x = 0, y = 0 }, state.anchors.indicator.pos)
      assert.are.equal(1, state.anchors.indicator.scale)
    end)

    it("seeds a repaired anchor with a copy, not a reference to the defaults", function()
      local defaults = anchored_defaults()
      local state = layout.slot({}, "default", defaults)
      defaults.anchors.main.pos.x = 999
      assert.are.equal(100, state.anchors.main.pos.x, "the seed must be a copy")
    end)

    it("skips an anchor whose default is not a table", function()
      local config = {
        slots = { default = { anchors = { indicator = { pos = { x = 9, y = 9 }, scale = 2 } } } },
      }
      local state
      assert.has_no.errors(function()
        state = layout.slot(config, "default", {
          anchors = { main = 5, indicator = { pos = { x = 600, y = 700 }, scale = 1 } },
          visible = true,
        })
      end)
      assert.is_nil(state.anchors.main, "a malformed default must not seed an anchor")
      assert.are.same({ pos = { x = 9, y = 9 }, scale = 2 }, state.anchors.indicator)
    end)

    it("preserves an anchor the defaults do not mention", function()
      local config = {
        slots = { default = { anchors = { extra = { pos = { x = 7, y = 8 }, scale = 2 } } } },
      }
      local state = layout.slot(config, "default", anchored_defaults())
      assert.are.same({ pos = { x = 7, y = 8 }, scale = 2 }, state.anchors.extra)
    end)

    it("keeps visible at the top level and repairs it there", function()
      local state = layout.slot({}, "default", anchored_defaults())
      assert.is_true(state.visible)
      local hidden = layout.slot({}, "default", { anchors = {}, visible = false })
      assert.is_false(hidden.visible)
    end)

    it("creates a new slot as a deep copy of the anchored source", function()
      local config = {}
      layout.slot(config, "default", anchored_defaults())
      local created = layout.create_slot(config, "raid", "default", anchored_defaults())
      assert.are.same(config.slots.default, created)
      config.slots.default.anchors.main.pos.x = 999
      assert.are.equal(100, config.slots.raid.anchors.main.pos.x, "the seed must be a copy")
    end)
  end)
end)
