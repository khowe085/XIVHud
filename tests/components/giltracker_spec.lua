local new_giltracker = require("components/giltracker/giltracker")
local fakes = require("tests/support/fakes")

local GIL_ITEM_ID = 65535
local OTHER_ITEM_ID = 4096

local ZONE_IN = 0x00A
local FINISH_INVENTORY = 0x01D
local ITEM_UPDATES = 0x020
local UNHANDLED = 0x00E

describe("giltracker widget", function()
  local prims, assets, widget
  local gil, reads, saves, parsed, packet

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

  -- The inventory settling is what turns a pending change into a read.
  local function finish_inventory()
    packet = { Flag = 0 }
    widget.update("chunk", FINISH_INVENTORY, "raw bytes")
  end

  before_each(function()
    prims = fakes.prims()
    assets = {}
    gil = 1234567
    reads = 0
    saves = 0
    parsed = {}
    packet = nil
    widget = new_giltracker({
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      get_gil = function()
        reads = reads + 1
        return gil
      end,
      parse_packet = function(data)
        parsed[#parsed + 1] = data
        return packet
      end,
      asset = function(file)
        assets[#assets + 1] = file
        return "addons/XIVHud/" .. file
      end,
    })
  end)

  describe("construction", function()
    it("is named for its config namespace and command word", function()
      assert.are.equal("giltracker", widget.name)
    end)

    it("defaults its slot position to the bottom right of the screen", function()
      local slot = widget.defaults.slots.default
      assert.are.equal(1575, slot.pos.x)
      assert.are.equal(1045, slot.pos.y)
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

    it("does not right-justify the number, which would push it off screen", function()
      -- texts.pos offsets x by the screen width when the right flag is set, so
      -- the number is left-justified inside a reserved width instead.
      assert.is_nil(number().last.right_justified)
    end)

    it("stops the icon sizing itself to its texture, which would defeat scale", function()
      assert.are.equal(false, icon().last.fit)
    end)

    it("points the icon at the packaged asset", function()
      assert.are.equal("addons/XIVHud/assets/gil/gil.png", icon().last.path)
    end)

    it("starts hidden, because the framework decides what is on screen", function()
      assert.is_false(number().visible)
      assert.is_false(icon().visible)
    end)
  end)

  describe("attach", function()
    it("reads gil once and shows it", function()
      attach()
      assert.are.equal(1, reads)
      assert.are.equal("1,234,567", number().last.text)
    end)

    it("says it is loading when the read comes back empty", function()
      gil = nil
      attach()
      assert.are.equal("Loading...", number().last.text)
    end)

    it("pushes the configured text style", function()
      attach()
      assert.are.equal("sans-serif", number().last.font)
      assert.are.same({ 253, 252, 250 }, number().last.color)
      assert.are.equal(255, number().last.alpha)
      assert.are.equal(2, number().last.stroke_width)
      assert.are.same({ 50, 50, 50 }, number().last.stroke_color)
      assert.are.equal(200, number().last.stroke_alpha)
      assert.are.equal(true, number().last.italic)
      assert.are.equal(false, number().last.bold)
    end)

    it("pushes the configured background style", function()
      attach()
      assert.are.equal(false, number().last.bg_visible)
      assert.are.same({ 0, 0, 0 }, number().last.bg_color)
      assert.are.equal(100, number().last.bg_alpha)
    end)

    it("pushes the configured icon colour", function()
      attach()
      assert.are.same({ 255, 255, 255 }, icon().last.color)
      assert.are.equal(255, icon().last.alpha)
    end)

    it("does not read gil before it is attached to a character", function()
      widget.update("chunk", ITEM_UPDATES, "raw bytes")
      assert.are.equal(0, reads)
    end)
  end)

  describe("layout", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
    end)

    it("puts the number at the origin and the icon past the reserved width", function()
      assert.are.equal(100, number().x)
      assert.are.equal(204, number().y)
      assert.are.equal(161, icon().x)
      assert.are.equal(200, icon().y)
    end)

    it("sizes the icon square", function()
      assert.are.equal(23, icon().width)
      assert.are.equal(23, icon().height)
    end)

    it("multiplies everything by the scale", function()
      widget.set_scale(2)
      assert.are.equal(208, number().y)
      assert.are.equal(18, number().font_size)
      assert.are.equal(221, icon().x)
      assert.are.equal(46, icon().width)
    end)

    it("hands the framework back the origin it was given", function()
      local x, y, width, height = widget.get_bounds()
      assert.are.equal(100, x)
      assert.are.equal(200, y)
      assert.are.equal(84, width)
      assert.are.equal(23, height)
    end)

    it("has no bounds before it has been positioned", function()
      local unpositioned = new_giltracker({
        new_text = prims.new_text,
        new_image = prims.new_image,
        screen = function()
          return 1920, 1080
        end,
        get_gil = function()
          return 0
        end,
        parse_packet = function() end,
        asset = function(file)
          return file
        end,
      })
      assert.is_nil(unpositioned.get_bounds())
    end)
  end)

  describe("visibility", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
    end)

    it("shows and hides both prims together", function()
      widget.show()
      assert.is_true(number().visible)
      assert.is_true(icon().visible)

      widget.hide()
      assert.is_false(number().visible)
      assert.is_false(icon().visible)
    end)

    it("keeps the icon hidden while it is turned off in config", function()
      widget.defaults.icon.visible = false
      widget.attach(widget.defaults, function() end)
      widget.show()
      assert.is_true(number().visible)
      assert.is_false(icon().visible)
    end)

    it("does not put a prim back on screen when a later read arrives", function()
      widget.show()
      widget.hide()
      gil = 42
      finish_inventory()
      assert.is_false(number().visible)
      assert.is_false(icon().visible)
    end)
  end)

  describe("game events", function()
    before_each(function()
      attach()
      reads = 0
    end)

    it("reads gil when a packet updates it", function()
      packet = { Item = GIL_ITEM_ID, Count = 90 }
      gil = 90
      widget.update("chunk", ITEM_UPDATES, "raw bytes")
      assert.are.equal(1, reads)
      assert.are.equal("90", number().last.text)
    end)

    it("never parses a packet it does not handle", function()
      widget.update("chunk", UNHANDLED, "raw bytes")
      assert.are.equal(0, #parsed)
      assert.are.equal(0, reads)
    end)

    it("never parses the finish packet, needing only the fact that it arrived", function()
      finish_inventory()
      assert.are.equal(0, #parsed)
      assert.are.equal(1, reads)
    end)

    it("reads a gil packet that arrives before the inventory has settled", function()
      packet = { Item = GIL_ITEM_ID, Count = 90 }
      widget.update("chunk", ITEM_UPDATES, "raw bytes")
      assert.are.equal(1, reads)
    end)

    it("never parses the zone in packet, needing only the fact that it arrived", function()
      widget.update("chunk", ZONE_IN, "raw bytes")
      assert.are.equal(0, #parsed)
      -- Still acted on: the next bag to settle has to read again.
      finish_inventory()
      assert.are.equal(1, reads)
    end)

    it("parses a packet it does handle exactly once", function()
      packet = { Item = OTHER_ITEM_ID, Count = 1 }
      widget.update("chunk", ITEM_UPDATES, "raw bytes")
      assert.are.same({ "raw bytes" }, parsed)
      assert.are.equal(0, reads)
    end)

    it("reads after gil enters a bag and the inventory settles", function()
      finish_inventory()
      reads = 0
      widget.update("add item", GIL_ITEM_ID)
      finish_inventory()
      assert.are.equal(1, reads)
    end)

    it("reads after gil leaves a bag and the inventory settles", function()
      finish_inventory()
      reads = 0
      widget.update("remove item", GIL_ITEM_ID)
      finish_inventory()
      assert.are.equal(1, reads)
    end)

    it("ignores items that are not gil", function()
      finish_inventory()
      reads = 0
      widget.update("add item", OTHER_ITEM_ID)
      finish_inventory()
      assert.are.equal(0, reads)
    end)

    it("does nothing on the per-frame tick, having nothing to animate", function()
      widget.update()
      assert.are.equal(0, reads)
      assert.are.equal(0, #parsed)
    end)

    it("ignores the events forwarded for other components", function()
      -- dispatch broadcasts to everything registered, so the vitals parambar
      -- asked for arrive here too.
      for _, event in ipairs({ "status", "hp", "hpp", "mp", "mpp", "tp" }) do
        widget.update(event, 1)
      end
      assert.are.equal(0, reads)
      assert.are.equal(0, #parsed)
    end)
  end)

  describe("preview", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
    end)

    it("shows the widest value the widget will ever hold", function()
      widget.set_preview(true)
      assert.are.equal("123,456,789", number().last.text)
    end)

    it("restores the live value on exit", function()
      widget.set_preview(true)
      widget.set_preview(false)
      assert.are.equal("1,234,567", number().last.text)
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

    it("forgets the inventory, so the next character reads its own gil", function()
      attach()
      finish_inventory()
      widget.detach()
      attach()
      reads = 0
      finish_inventory()
      assert.are.equal(1, reads)
    end)

    it("forgets the value too, rather than showing one character's gil to the next", function()
      attach()
      finish_inventory()
      widget.detach()
      -- get_items comes back empty this early into a login, and a preserved
      -- value would be the previous character's.
      gil = nil
      attach()
      assert.are.equal("Loading...", number().last.text)
    end)

    it("disposes every prim, which the reference addon never did", function()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed, prim.kind .. " was not disposed")
      end
    end)
  end)
end)
