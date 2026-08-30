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

  --[[ The layout table lives in its own file, `layout.lua`, and reaches here
       already merged over the component's layout defaults by lib/settings - so
       repair's job is the shapes a merge cannot fix: a value of the wrong type,
       and the pos/scale residue of a hand edit. It repairs in place, because
       the table it is handed is the one the handle will write back. ]]
  describe("repair", function()
    it("leaves a well-formed state alone", function()
      local state = { pos = { x = 1, y = 2 }, scale = 3, visible = false }
      assert.are.same({ pos = { x = 1, y = 2 }, scale = 3, visible = false }, layout.repair(state, {}))
    end)

    it("repairs in place and hands back the same table", function()
      local state = { scale = 2 }
      local repaired = layout.repair(state, { pos = { x = 7, y = 8 }, scale = 1, visible = true })
      assert.are.equal(state, repaired)
      assert.are.same({ pos = { x = 7, y = 8 }, scale = 2, visible = true }, state)
    end)

    it("seeds a repaired pos with a copy, not a reference to the defaults", function()
      local defaults = { pos = { x = 7, y = 8 }, scale = 1, visible = true }
      local state = layout.repair({}, defaults)
      defaults.pos.x = 999
      assert.are.equal(7, state.pos.x, "the seed must be a copy")
    end)

    it("coerces a pos or scale of the wrong type", function()
      local defaults = { pos = { x = 7, y = 8 }, scale = 1, visible = true }

      assert.are.same({ x = 7, y = 8 }, layout.repair({ pos = 5 }, defaults).pos)
      assert.are.same({ x = 0, y = 0 }, layout.repair({ pos = { x = "abc", y = {} } }, defaults).pos)
      assert.are.equal(1, layout.repair({ scale = "big" }, defaults).scale)
    end)

    it("falls back to an origin and full size when the defaults say nothing", function()
      local state = layout.repair({}, {})
      assert.are.same({ pos = { x = 0, y = 0 }, scale = 1, visible = true }, state)
    end)

    -- Anything that is not `true` reads as hidden everywhere, so a stored
    -- `false` is left as it is rather than quietly turned back on.
    it("seeds visible from the defaults only when it is missing", function()
      assert.is_true(layout.repair({}, { visible = true }).visible)
      assert.is_false(layout.repair({}, { visible = false }).visible)
      assert.is_false(layout.repair({ visible = false }, { visible = true }).visible)
      assert.is_true(layout.repair({}, {}).visible)
    end)
  end)

  -- Touchpoint 2: a component whose layout defaults carry `anchors` stores
  -- pos/scale per anchor; `visible` stays at the top level.
  describe("multi-anchor repair", function()
    local function anchored_defaults()
      return {
        anchors = {
          main = { pos = { x = 100, y = 900 }, scale = 1 },
          indicator = { pos = { x = 600, y = 700 }, scale = 1 },
        },
        visible = true,
      }
    end

    it("fills an empty state in from the per-anchor defaults", function()
      assert.are.same(anchored_defaults(), layout.repair({}, anchored_defaults()))
    end)

    it("does not fabricate top-level pos or scale on an anchored entry", function()
      local state = layout.repair({}, anchored_defaults())
      assert.is_nil(state.pos)
      assert.is_nil(state.scale)
    end)

    -- A hand-edited file can carry the pair, and so could a component that
    -- gained anchors after its layout was first written. Shed it in place, so
    -- the next save no longer has it.
    it("drops a stray top-level pos and scale", function()
      local state = layout.repair({
        pos = { x = 0, y = 0 },
        scale = 1,
        visible = true,
        anchors = { main = { pos = { x = 5, y = 6 }, scale = 2 } },
      }, anchored_defaults())
      assert.is_nil(state.pos)
      assert.is_nil(state.scale)
      assert.are.same({ pos = { x = 5, y = 6 }, scale = 2 }, state.anchors.main)
    end)

    it("repairs a missing anchor from its default without touching the others", function()
      local state = layout.repair(
        { anchors = { main = { pos = { x = 1, y = 2 }, scale = 3 } }, visible = true },
        anchored_defaults()
      )
      assert.are.same({ pos = { x = 600, y = 700 }, scale = 1 }, state.anchors.indicator)
      assert.are.same({ pos = { x = 1, y = 2 }, scale = 3 }, state.anchors.main)
    end)

    it("fills in a missing anchors table", function()
      local state = layout.repair({ visible = true }, anchored_defaults())
      assert.are.same(anchored_defaults().anchors, state.anchors)
    end)

    it("repairs an anchor entry that is the wrong shape throughout", function()
      local state = layout.repair({
        anchors = { main = "nonsense", indicator = { pos = { x = "abc", y = {} }, scale = "big" } },
      }, anchored_defaults())
      assert.are.same({ pos = { x = 100, y = 900 }, scale = 1 }, state.anchors.main)
      assert.are.same({ x = 0, y = 0 }, state.anchors.indicator.pos)
      assert.are.equal(1, state.anchors.indicator.scale)
    end)

    it("seeds a repaired anchor with a copy, not a reference to the defaults", function()
      local defaults = anchored_defaults()
      local state = layout.repair({}, defaults)
      defaults.anchors.main.pos.x = 999
      assert.are.equal(100, state.anchors.main.pos.x, "the seed must be a copy")
    end)

    -- A default that is not a table is a component authoring bug. It cannot
    -- seed anything, and what the merge left behind is not usable as a
    -- placement either, so it goes rather than reaching core.
    it("drops an anchor whose default is not a table", function()
      local state
      assert.has_no.errors(function()
        state = layout.repair({ anchors = { main = 5, indicator = { pos = { x = 9, y = 9 }, scale = 2 } } }, {
          anchors = { main = 5, indicator = { pos = { x = 600, y = 700 }, scale = 1 } },
          visible = true,
        })
      end)
      assert.is_nil(state.anchors.main)
      assert.are.same({ pos = { x = 9, y = 9 }, scale = 2 }, state.anchors.indicator)
    end)

    it("preserves an anchor the defaults do not mention, repairing it like any other", function()
      local state = layout.repair({ anchors = { extra = { pos = { x = 7, y = 8 }, scale = 2 } } }, anchored_defaults())
      assert.are.same({ pos = { x = 7, y = 8 }, scale = 2 }, state.anchors.extra)

      local broken = layout.repair({ anchors = { extra = { scale = "big" } } }, anchored_defaults())
      assert.are.same({ pos = { x = 0, y = 0 }, scale = 1 }, broken.anchors.extra)
    end)

    it("keeps visible at the top level and repairs it there", function()
      assert.is_true(layout.repair({}, anchored_defaults()).visible)
      assert.is_false(layout.repair({}, { anchors = {}, visible = false }).visible)
    end)
  end)
end)
