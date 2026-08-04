local new_visibility = require("lib.visibility")

describe("visibility", function()
  local clock, vis

  before_each(function()
    clock = 0
    vis = new_visibility({
      now = function()
        return clock
      end,
      zone_delay = 3,
    })
    vis.set_logged_in(true)
  end)

  describe("suppression reasons", function()
    it("starts logged out, so nothing renders", function()
      local fresh = new_visibility({
        now = function()
          return 0
        end,
      })
      assert.is_true(fresh.suppressed())
      assert.is_true(fresh.reasons().logged_out)
    end)

    it("clears once a character is known", function()
      assert.is_false(vis.suppressed())
      assert.are.same({}, vis.reasons())
    end)

    it("suppresses on player status 4 and releases on any other status", function()
      vis.set_status(4)
      assert.is_true(vis.reasons().event)
      vis.set_status(0)
      assert.is_false(vis.suppressed())
    end)

    it("holds every active reason at once", function()
      vis.set_status(4)
      vis.zone_changed()
      vis.set_logged_in(false)
      assert.are.same({ event = true, zoning = true, logged_out = true }, vis.reasons())
    end)

    it("stays suppressed until the last reason clears", function()
      vis.set_status(4)
      vis.zone_changed()
      clock = 10
      vis.tick()
      assert.is_true(vis.suppressed(), "the event reason is still active")
      vis.set_status(0)
      assert.is_false(vis.suppressed())
    end)

    it("hands out a copy of the reason set", function()
      vis.set_status(4)
      local reasons = vis.reasons()
      reasons.event = nil
      assert.is_true(vis.reasons().event)
    end)
  end)

  describe("zone change", function()
    it("suppresses immediately and re-shows only after the delay", function()
      vis.zone_changed()
      assert.is_true(vis.reasons().zoning)

      clock = 2.9
      vis.tick()
      assert.is_true(vis.reasons().zoning, "still inside the settle window")

      clock = 3
      vis.tick()
      assert.is_false(vis.suppressed())
    end)

    it("restarts the delay when a second zone change lands mid-window", function()
      vis.zone_changed()
      clock = 2
      vis.zone_changed()
      clock = 4
      vis.tick()
      assert.is_true(vis.reasons().zoning)
      clock = 5
      vis.tick()
      assert.is_false(vis.suppressed())
    end)

    it("reports the tick that actually changed the outcome", function()
      vis.zone_changed()
      clock = 1
      assert.is_false(vis.tick())
      clock = 3
      assert.is_true(vis.tick())
      assert.is_false(vis.tick())
    end)

    it("uses a three second default delay", function()
      local defaulted = new_visibility({
        now = function()
          return clock
        end,
      })
      defaulted.set_logged_in(true)
      defaulted.zone_changed()
      clock = 2.99
      defaulted.tick()
      assert.is_true(defaulted.suppressed())
      clock = 3
      defaulted.tick()
      assert.is_false(defaulted.suppressed())
    end)
  end)

  describe("the hide-during-events toggle", function()
    it("stops status 4 from suppressing when turned off", function()
      vis.set_hide_event(false)
      vis.set_status(4)
      assert.is_false(vis.suppressed())
    end)

    it("drops an active event suppression the moment it is turned off", function()
      vis.set_status(4)
      assert.is_true(vis.suppressed())
      vis.set_hide_event(false)
      assert.is_false(vis.suppressed())
    end)

    it("re-applies the current status when turned back on", function()
      vis.set_hide_event(false)
      vis.set_status(4)
      vis.set_hide_event(true)
      assert.is_true(vis.reasons().event)
    end)
  end)

  describe("change reporting", function()
    it("reports only transitions of the overall state", function()
      assert.is_true(vis.set_status(4))
      assert.is_false(vis.set_status(4))
      assert.is_false(vis.zone_changed(), "already suppressed by the event, so the outcome is unchanged")
      assert.is_false(vis.set_status(0), "still suppressed by zoning")
      clock = 3
      assert.is_true(vis.tick())
    end)
  end)
end)
