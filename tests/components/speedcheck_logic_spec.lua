local new_logic = require("components/speedcheck/logic")
local build_defaults = require("components/speedcheck/defaults")

describe("speedcheck logic", function()
  local logic, config

  before_each(function()
    config = build_defaults(1920, 1080)
    logic = new_logic(config)
  end)

  describe("the percentage", function()
    it("knows nothing before the first read, and says so rather than claiming base speed", function()
      assert.are.equal("--%", logic.text())
    end)

    it("reads the walking speed as no bonus at all", function()
      logic.set_speed(5)
      assert.are.equal("+0%", logic.text())
    end)

    it("signs a bonus, because the sign is the whole point of the number", function()
      logic.set_speed(5.6)
      assert.are.equal("+12%", logic.text())
    end)

    it("signs a penalty", function()
      logic.set_speed(3.75)
      assert.are.equal("-25%", logic.text())
    end)

    it("reports a bound player as standing still", function()
      logic.set_speed(0)
      assert.are.equal("-100%", logic.text())
    end)

    it("rounds to the nearest whole percent", function()
      -- 5.019 is +0.38%, which is a rounding error in the client's own float
      -- rather than a movement bonus anyone has.
      logic.set_speed(5.019)
      assert.are.equal("+0%", logic.text())
      logic.set_speed(5.3251)
      assert.are.equal("+7%", logic.text())
    end)

    it("rounds a penalty to the nearest whole percent as well", function()
      -- Halfway cases go up on both signs: math.floor(x + 0.5) is not
      -- symmetric, and -12.5% reading as -13% would be a percent the player
      -- does not have.
      logic.set_speed(4.375)
      assert.are.equal("-12%", logic.text())
    end)
  end)

  describe("a reading the client cannot answer", function()
    --[[ get_mob_by_target('me') comes back nil while the zone loads. That is a
         frame or two, not a change of speed, so the last good value stays on
         screen rather than blinking out - the same rule giltracker applies to
         a gil read that lands empty. ]]
    it("keeps the last value when the mob is not there", function()
      logic.set_speed(5.6)
      logic.set_speed(nil)
      assert.are.equal("+12%", logic.text())
    end)

    it("keeps the last value when the field is not a number", function()
      logic.set_speed(5.6)
      logic.set_speed("fast")
      assert.are.equal("+12%", logic.text())
    end)

    -- The value belongs to the character. Keeping it across a detach would show
    -- one character's speed to the next.
    it("forgets the value when the character goes", function()
      logic.set_speed(5.6)
      logic.clear()
      assert.are.equal("--%", logic.text())
    end)
  end)

  describe("preview", function()
    it("shows the widest number the widget draws, so layout mode shows its real footprint", function()
      logic.set_preview(true)
      assert.are.equal("+100%", logic.text())
    end)

    it("goes back to the live value when preview ends", function()
      logic.set_speed(5.6)
      logic.set_preview(true)
      logic.set_preview(false)
      assert.are.equal("+12%", logic.text())
    end)
  end)

  describe("geometry", function()
    it("centres the icon inside the box, so the origin is the box and not the art", function()
      local geometry = logic.geometry(100, 200, 1)
      local width = select(3, logic.bounds(100, 200, 1))
      assert.are.equal(100 + (width - config.icon.size) / 2, geometry.icon.x)
      assert.are.equal(200, geometry.icon.y)
      assert.are.equal(config.icon.size, geometry.icon.size)
    end)

    --[[ The number is drawn ON the icon, so it is the GLYPHS that have to land
         over the art. A prim is left-justified (right_justified would offset it
         by the screen width - see giltracker), so this is the only thing that
         puts it there. ]]
    it("centres the number over the icon rather than beside it", function()
      logic.set_speed(5)
      local geometry = logic.geometry(100, 200, 1)
      local _, _, _, height = logic.bounds(100, 200, 1)
      assert.are.equal(
        geometry.icon.x + geometry.icon.size / 2,
        geometry.text.x + geometry.text.width / 2,
        "the number's own centre must land on the icon's"
      )
      assert.is_true(geometry.text.y > 200, "the number must sit inside the icon, not above the origin")
      assert.is_true(geometry.text.y + geometry.text.height <= 200 + height + 0.001)
    end)

    it("re-centres the number as the value changes width", function()
      logic.set_speed(3.75)
      local wide = logic.geometry(100, 200, 1)
      logic.set_speed(5)
      local narrow = logic.geometry(100, 200, 1)
      -- "-25%" is a character shorter than "-100%" would be, so it starts
      -- further right; both still centre on the same point.
      assert.is_true(narrow.text.x > wide.text.x)
      assert.are.equal(wide.text.x + wide.text.width / 2, narrow.text.x + narrow.text.width / 2)
    end)

    --[[ What the reserved width is FOR: the box is measured against the widest
         string the number ever takes, so the icon under it and the origin the
         framework clamps stay where they are while the value moves. ]]
    it("keeps the icon and the box still while the value changes width", function()
      logic.set_speed(5)
      local narrow = logic.geometry(100, 200, 1)
      local _, _, narrow_width = logic.bounds(100, 200, 1)
      logic.set_speed(3.75)
      local wide = logic.geometry(100, 200, 1)
      local _, _, wide_width = logic.bounds(100, 200, 1)
      assert.are.equal(narrow.icon.x, wide.icon.x)
      assert.are.equal(narrow_width, wide_width)
    end)

    it("never lets the number reach past the box, whatever it holds", function()
      local _, _, width = logic.bounds(100, 200, 1)
      for _, speed in ipairs({ 0, 5, 5.6, 10 }) do
        logic.set_speed(speed)
        local geometry = logic.geometry(100, 200, 1)
        assert.is_true(geometry.text.x >= 100)
        assert.is_true(geometry.text.x + geometry.text.width <= 100 + width + 0.001)
      end
    end)

    it("scales both prims and their placement", function()
      local geometry = logic.geometry(100, 200, 2)
      assert.are.equal(config.icon.size * 2, geometry.icon.size)
      assert.are.equal(math.floor(config.font_size * 2 + 0.5), geometry.text.size)
    end)

    it("draws nothing above or left of the origin the framework clamps against", function()
      local geometry = logic.geometry(0, 0, 1)
      assert.is_true(geometry.icon.x >= 0)
      assert.is_true(geometry.icon.y >= 0)
      assert.is_true(geometry.text.x >= 0)
      assert.is_true(geometry.text.y >= 0)
    end)
  end)

  --[[ No prim can be measured, so the centring is estimated from the font size
       and this is the knob for correcting it against a live client. The
       correction moves the NUMBER against the icon - moving both would just be
       a drag - and the box grows to cover wherever it lands, so nothing is ever
       drawn outside what the framework clamps and layout mode highlights. ]]
  describe("the centring correction", function()
    local function with_offset(x, y)
      config.text_offset = { x = x, y = y }
      logic.set_config(config)
      return logic.geometry(100, 200, 1)
    end

    it("moves the number against the icon", function()
      local centred = with_offset(0, 0)
      local nudged = with_offset(4, 3)
      assert.are.equal(centred.text.x - centred.icon.x + 4, nudged.text.x - nudged.icon.x)
      assert.are.equal(centred.text.y - centred.icon.y + 3, nudged.text.y - nudged.icon.y)
    end)

    it("widens the box rather than letting the number hang out of it", function()
      local _, _, width, height = logic.bounds(100, 200, 1)
      config.text_offset = { x = 4, y = 3 }
      logic.set_config(config)
      local geometry = logic.geometry(100, 200, 1)
      local _, _, wide, tall = logic.bounds(100, 200, 1)
      assert.are.equal(width + 4, wide)
      assert.are.equal(height + 3, tall)
      assert.is_true(geometry.text.x + geometry.text.width <= 100 + wide + 0.001)
      assert.is_true(geometry.text.y + geometry.text.height <= 200 + tall + 0.001)
    end)

    it("shifts the whole box right rather than drawing left of the origin", function()
      local geometry = with_offset(-4, -3)
      assert.is_true(geometry.text.x >= 100)
      assert.is_true(geometry.text.y >= 200)
      assert.is_true(geometry.icon.x >= 100)
      assert.is_true(geometry.icon.y >= 200)
    end)

    it("scales the correction with everything else", function()
      config.text_offset = { x = 4, y = 0 }
      logic.set_config(config)
      local geometry = logic.geometry(100, 200, 2)
      config.text_offset = { x = 0, y = 0 }
      logic.set_config(config)
      local centred = logic.geometry(100, 200, 2)
      assert.are.equal(centred.text.x + 8, geometry.text.x)
    end)
  end)

  describe("bounds", function()
    it("hands back the origin it was given, which is what the framework clamps", function()
      local x, y = logic.bounds(100, 200, 1)
      assert.are.equal(100, x)
      assert.are.equal(200, y)
    end)

    it("covers the icon and the number both", function()
      local _, _, width, height = logic.bounds(100, 200, 1)
      assert.is_true(width >= config.icon.size)
      assert.is_true(height >= config.icon.size)
    end)

    it("grows with the scale", function()
      local _, _, width, height = logic.bounds(100, 200, 1)
      local _, _, wide, tall = logic.bounds(100, 200, 2)
      assert.are.equal(width * 2, wide)
      assert.are.equal(height * 2, tall)
    end)

    it("still covers the number when the icon is switched off", function()
      config.icon.visible = false
      logic.set_config(config)
      local _, _, width, height = logic.bounds(100, 200, 1)
      assert.is_true(width > 0)
      assert.is_true(height > 0)
    end)
  end)
end)
