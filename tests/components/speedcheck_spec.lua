local new_speedcheck = require("components/speedcheck/speedcheck")
local fakes = require("tests/support/fakes")

describe("speedcheck widget", function()
  local prims, assets, widget
  local mob, targets, saves, generation

  local function number()
    return prims.texts[1]
  end

  local function icon()
    return prims.images[1]
  end

  local function attach()
    widget.attach(widget.defaults, function()
      saves = saves + 1
    end)
  end

  before_each(function()
    prims = fakes.prims()
    assets = {}
    targets = {}
    saves = 0
    generation = 1
    mob = { movement_speed = 5 }
    widget = new_speedcheck({
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      get_mob_by_target = function(target)
        targets[#targets + 1] = target
        return mob
      end,
      generation = function()
        return generation
      end,
      asset = function(file)
        assets[#assets + 1] = file
        return "addons/XIVHud/" .. file
      end,
    })
  end)

  describe("construction", function()
    it("is named for its config namespace and command word", function()
      assert.are.equal("speedcheck", widget.name)
    end)

    it("answers to a short alias of its own", function()
      assert.are.equal("sc", widget.alias)
    end)

    it("defaults its slot position to the bottom right, a row above the gil tracker", function()
      local slot = widget.defaults.layout
      assert.are.equal(1575, slot.pos.x)
      assert.are.equal(990, slot.pos.y)
    end)

    it("builds one number and one icon", function()
      assert.are.equal(1, #prims.texts)
      assert.are.equal(1, #prims.images)
    end)

    it("makes both prims non-draggable, because the framework owns dragging", function()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(false, prim.last.draggable, prim.kind .. " must not drag itself")
      end
    end)

    it("stops the icon sizing itself to its texture, which would defeat scale", function()
      assert.are.equal(false, icon().last.fit)
    end)

    it("points the icon at Bolter's Roll, the packaged status icon", function()
      assert.are.equal("addons/XIVHud/assets/xiv/buffIcons/330.png", icon().last.path)
    end)

    it("starts hidden, because the framework decides what is on screen", function()
      assert.is_false(number().visible)
      assert.is_false(icon().visible)
    end)

    it("reads nothing while it is being built, before any character is scoped", function()
      assert.are.equal(0, #targets)
    end)
  end)

  describe("attach", function()
    it("reads the player's own speed, not a target's", function()
      attach()
      assert.are.same({ "me" }, targets)
      assert.are.equal("+0%", number().last.text)
    end)

    it("shows the value the client reports", function()
      mob = { movement_speed = 5.6 }
      attach()
      assert.are.equal("+12%", number().last.text)
    end)

    it("says it knows nothing when the client has no mob for us yet", function()
      mob = nil
      attach()
      assert.are.equal("--%", number().last.text)
    end)

    it("persists nothing of its own, having no settings to write", function()
      attach()
      assert.are.equal(0, saves)
    end)
  end)

  describe("layout", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
    end)

    --[[ Exact, not "somewhere inside the box": the number is drawn UNDER the
         art, so a placement that is merely in bounds can still overlap it or
         drift off its centre. The values are logic's, at the default 10pt font
         under the 32px icon. ]]
    it("places both prims where logic puts them", function()
      assert.are.equal(102.75, icon().x)
      assert.are.equal(200, icon().y)
      assert.are.equal(32, icon().width)
      assert.are.equal(32, icon().height)
      assert.are.equal(107.5, number().x)
      assert.are.equal(234, number().y)
      assert.are.equal(10, number().font_size)
    end)

    it("hands the framework back the origin it was given, which is what it clamps", function()
      local x, y, width, height = widget.get_bounds()
      assert.are.equal(100, x)
      assert.are.equal(200, y)
      assert.is_true(width > 0)
      assert.is_true(height > 0)
    end)

    it("has no bounds before it has been placed", function()
      local fresh = new_speedcheck({
        new_text = prims.new_text,
        new_image = prims.new_image,
        screen = function()
          return 1920, 1080
        end,
        get_mob_by_target = function()
          return mob
        end,
        asset = function(file)
          return file
        end,
      })
      assert.is_nil(fresh.get_bounds())
    end)

    it("scales the art, the font and the box together", function()
      local _, _, width = widget.get_bounds()
      widget.set_scale(2)
      local _, _, wide = widget.get_bounds()
      assert.are.equal(width * 2, wide)
      assert.are.equal(widget.defaults.icon.size * 2, icon().width)
      -- The font is the half of it nothing else would notice: the box and the
      -- art would still scale around a number frozen at 10pt.
      assert.are.equal(widget.defaults.font_size * 2, number().font_size)
      assert.are.equal(105.5, icon().x)
      assert.are.equal(115, number().x)
      -- The gap under the icon scales with everything else, or the number
      -- would climb back onto the art as the widget grew.
      assert.are.equal(268, number().y)
    end)
  end)

  describe("the tick", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
      widget.show()
    end)

    --[[ The mob memo in lib/player is cleared every frame, so a read on every
         tick would be a real client call sixty times a second - and movement
         speed moves when a buff, a mount or a piece of gear does, never within
         a frame. The counter is the cadence every other component gates on. ]]
    it("reads the client only when the shared read counter has moved", function()
      local before = #targets
      widget.update()
      widget.update()
      assert.are.equal(before, #targets)
    end)

    it("reads again once the counter moves", function()
      local before = #targets
      generation = generation + 1
      widget.update()
      assert.are.equal(before + 1, #targets)
    end)

    it("shows a speed that has changed", function()
      mob = { movement_speed = 5.6 }
      generation = generation + 1
      widget.update()
      assert.are.equal("+12%", number().last.text)
    end)

    --[[ The number is centred on the width of the string it draws, so a value
         of a different length has to be re-placed as well as re-written: core
         pushes set_pos on an attach and a drag, never on a value change. ]]
    it("re-centres the number when the value changes width", function()
      assert.are.equal(107.5, number().x, "the 3-character +0% starts here")
      mob = { movement_speed = 3.75 }
      generation = generation + 1
      widget.update()
      assert.are.equal("-25%", number().last.text)
      assert.are.equal(103.75, number().x)
    end)

    it("leaves the icon where it is while the number moves", function()
      local before = icon().x
      mob = { movement_speed = 3.75 }
      generation = generation + 1
      widget.update()
      assert.are.equal(before, icon().x)
    end)

    it("never draws the number past the box it reports", function()
      local x, _, width = widget.get_bounds()
      for _, speed in ipairs({ 0, 5, 5.6, 10 }) do
        mob = { movement_speed = speed }
        generation = generation + 1
        widget.update()
        assert.is_true(number().x >= x, "drew left of the origin at " .. speed)
        local drawn = #number().last.text * widget.defaults.font_size * 0.75
        assert.is_true(number().x + drawn <= x + width + 0.001, "drew past the box at " .. speed)
      end
    end)

    --[[ Lua's nil-tolerance would otherwise turn a wiring slip into a widget
         frozen on its first reading, which is the failure that says nothing at
         all. Reading every frame is the wrong cost, not the wrong number. ]]
    it("reads every frame when the ctx carries no counter at all", function()
      local counted = 0
      local countless = new_speedcheck({
        new_text = prims.new_text,
        new_image = prims.new_image,
        screen = function()
          return 1920, 1080
        end,
        get_mob_by_target = function()
          counted = counted + 1
          return mob
        end,
        asset = function(file)
          return file
        end,
      })
      countless.attach(countless.defaults, function() end)
      countless.set_pos(100, 200)
      countless.show()
      countless.update()
      countless.update()
      assert.are.equal(3, counted)
    end)

    it("keeps the last value when the client hands back no mob", function()
      mob = { movement_speed = 5.6 }
      generation = generation + 1
      widget.update()
      mob = nil
      generation = generation + 1
      widget.update()
      assert.are.equal("+12%", number().last.text)
    end)

    --[[ A prim write per frame is what the framework asks components to avoid;
         the value only moves when a buff lands or drops. ]]
    it("writes the number only when it has actually changed", function()
      local writes = #number().calls
      generation = generation + 1
      widget.update()
      generation = generation + 1
      widget.update()
      assert.are.equal(writes, #number().calls)
    end)

    -- Nothing is on screen, so a read would buy nothing at all.
    it("reads nothing while it is hidden", function()
      widget.hide()
      local before = #targets
      generation = generation + 1
      widget.update()
      assert.are.equal(before, #targets)
    end)

    -- ... and the value it comes back with must not be the one from before the
    -- cutscene, however long that was.
    it("reads on the first tick after it is shown again", function()
      widget.hide()
      widget.show()
      local before = #targets
      widget.update()
      assert.are.equal(before + 1, #targets)
    end)

    it("reads nothing at all while it is detached", function()
      widget.detach()
      local before = #targets
      generation = generation + 1
      widget.update()
      assert.are.equal(before, #targets)
    end)

    it("ignores the events forwarded for other components", function()
      -- dispatch broadcasts to everything registered, so the packets and vitals
      -- other components asked for arrive here too.
      local before = #targets
      generation = generation + 1
      for _, event in ipairs({ "chunk", "status", "hp", "add item", "job change" }) do
        widget.update(event, 1)
      end
      assert.are.equal(before, #targets)
    end)
  end)

  --[[ The number is drawn ON the art, so the stroke is what keeps it readable.
       CLAUDE.md's own trap: stroke_transparency takes 0..1 and would turn a 255
       into a wildly negative alpha, and nothing on screen would say so. ]]
  describe("style", function()
    before_each(function()
      attach()
    end)

    it("applies the configured font", function()
      assert.are.equal("sans-serif", number().last.font)
      assert.is_true(number().last.bold)
      assert.is_false(number().last.italic)
    end)

    it("colours the number and its stroke from config, in 0-255 alpha", function()
      assert.are.same({ 255, 255, 255 }, number().last.color)
      assert.are.equal(255, number().last.alpha)
      assert.are.equal(2, number().last.stroke_width)
      assert.are.same({ 0, 0, 0 }, number().last.stroke_color)
      assert.are.equal(255, number().last.stroke_alpha)
      -- Never stroke_transparency/transparency, which take 0..1.
      assert.is_nil(number().last.stroke_transparency)
      assert.is_nil(number().last.transparency)
    end)

    it("leaves the number's own background off, the icon being its backdrop", function()
      assert.is_false(number().last.bg_visible)
    end)

    it("colours the icon from config", function()
      assert.are.same({ 255, 255, 255 }, icon().last.color)
      assert.are.equal(255, icon().last.alpha)
      assert.is_nil(icon().last.transparency)
    end)

    it("re-applies the style of the config it is attached with", function()
      local config = widget.defaults
      config.font = "Consolas"
      config.text_stroke.width = 4
      widget.attach(config, function() end)
      assert.are.equal("Consolas", number().last.font)
      assert.are.equal(4, number().last.stroke_width)
    end)
  end)

  describe("visibility", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
    end)

    it("shows both prims when the framework says so", function()
      widget.show()
      assert.is_true(number().visible)
      assert.is_true(icon().visible)
    end)

    it("hides both", function()
      widget.show()
      widget.hide()
      assert.is_false(number().visible)
      assert.is_false(icon().visible)
    end)

    it("leaves the icon off when it has been switched off in config", function()
      local config = widget.defaults
      config.icon.visible = false
      widget.attach(config, function() end)
      widget.show()
      assert.is_true(number().visible)
      assert.is_false(icon().visible)
    end)
  end)

  describe("preview", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
    end)

    it("shows the widest number the widget will ever draw", function()
      widget.set_preview(true)
      assert.are.equal("+100%", number().last.text)
      -- And places it: the preview is what layout mode's box is judged against,
      -- so a number drawn past the edge of it is the one thing preview is for.
      assert.are.equal(100, number().x)
    end)

    it("restores the live value on exit", function()
      -- Layout mode force-shows every component, which is the only way preview
      -- is ever reached.
      widget.show()
      mob = { movement_speed = 5.6 }
      generation = generation + 1
      widget.update()
      widget.set_preview(true)
      widget.set_preview(false)
      assert.are.equal("+12%", number().last.text)
    end)
  end)

  describe("teardown", function()
    it("hides both prims when the character goes away", function()
      attach()
      widget.show()
      widget.detach()
      assert.is_false(number().visible)
      assert.is_false(icon().visible)
    end)

    it("forgets the value, rather than showing one character's speed to the next", function()
      mob = { movement_speed = 5.6 }
      attach()
      widget.detach()
      -- The client has no mob for the incoming character this early into a
      -- login, and a preserved value would be the outgoing one's.
      mob = nil
      attach()
      assert.are.equal("--%", number().last.text)
    end)

    it("disposes every prim", function()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed, prim.kind .. " was not disposed")
      end
    end)
  end)
end)
