local new_logic = require("components/giltracker/logic")
local build_defaults = require("components/giltracker/defaults")

local GIL_ITEM_ID = 65535
local OTHER_ITEM_ID = 4096

local ZONE_IN = 0x00A
local FINISH_INVENTORY = 0x01D
local ITEM_ASSIGN = 0x01F
local ITEM_UPDATES = 0x020
local FOUND_ITEM = 0x0D2

describe("giltracker logic", function()
  local logic, config

  -- The inventory finishing loading is what promotes a pending change into an
  -- actual read, so most of the state machine is expressed through it. Flag 0
  -- is one bag finishing, which is what arrives during play; Flag 1 is every
  -- bag, which the server only sends on a zone in.
  local function finish_inventory()
    return logic.on_chunk(FINISH_INVENTORY, { Flag = 0 })
  end

  local function load_inventory()
    assert.is_true(finish_inventory())
  end

  before_each(function()
    config = build_defaults(1920, 1080)
    logic = new_logic(config)
  end)

  describe("refresh state machine", function()
    it("reads gil the first time the inventory finishes loading", function()
      assert.is_true(finish_inventory())
    end)

    it("does not read twice when an immediate read already covered the change", function()
      -- get_items returns everything, so a read triggered by the gil packet
      -- also answers the add item the same transaction produces.
      load_inventory()
      logic.on_item(GIL_ITEM_ID)
      assert.is_true(logic.on_chunk(ITEM_UPDATES, { Item = GIL_ITEM_ID, Count = 5 }))
      assert.is_false(finish_inventory())
    end)

    it("does not read twice when gil moved before the first load", function()
      logic.on_item(GIL_ITEM_ID)
      assert.is_true(finish_inventory())
      assert.is_false(finish_inventory())
    end)

    it("does not read again while nothing has changed", function()
      load_inventory()
      assert.is_false(finish_inventory())
    end)

    it("reads once gil has moved and a bag settles", function()
      load_inventory()
      logic.on_item(GIL_ITEM_ID)
      assert.is_true(finish_inventory())
    end)

    it("ignores items that are not gil", function()
      load_inventory()
      logic.on_item(OTHER_ITEM_ID)
      assert.is_false(finish_inventory())
    end)

    it("clears the pending change once it has been read", function()
      load_inventory()
      logic.on_item(GIL_ITEM_ID)
      assert.is_true(finish_inventory())
      assert.is_false(finish_inventory())
    end)

    it("reads immediately when a packet assigns gil", function()
      load_inventory()
      assert.is_true(logic.on_chunk(ITEM_ASSIGN, { Item = GIL_ITEM_ID, Count = 500 }))
    end)

    it("reads immediately when a packet updates gil", function()
      load_inventory()
      assert.is_true(logic.on_chunk(ITEM_UPDATES, { Item = GIL_ITEM_ID, Count = 500 }))
    end)

    it("ignores item packets for anything else", function()
      load_inventory()
      assert.is_false(logic.on_chunk(ITEM_ASSIGN, { Item = OTHER_ITEM_ID, Count = 1 }))
      assert.is_false(logic.on_chunk(ITEM_UPDATES, { Item = OTHER_ITEM_ID, Count = 1 }))
    end)

    it("treats gil in the treasure pool as a reason to check", function()
      load_inventory()
      logic.on_chunk(FOUND_ITEM, { Item = GIL_ITEM_ID, Count = 3 })
      assert.is_true(finish_inventory())
    end)

    it("ignores treasure that is not gil, so a party's drops cost nothing", function()
      load_inventory()
      logic.on_chunk(FOUND_ITEM, { Item = OTHER_ITEM_ID, Count = 3 })
      assert.is_false(finish_inventory())
    end)

    it("ignores an empty treasure pool packet", function()
      load_inventory()
      logic.on_chunk(FOUND_ITEM, { Item = GIL_ITEM_ID, Count = 0 })
      assert.is_false(finish_inventory())
    end)

    it("forgets the inventory on a zone in, so the next load reads again", function()
      load_inventory()
      assert.is_false(logic.on_chunk(ZONE_IN, {}))
      assert.is_true(finish_inventory())
    end)

    it("forgets the inventory on logout", function()
      load_inventory()
      logic.on_logout()
      assert.is_true(finish_inventory())
    end)

    it("forgets a pending change on a zone in, which the fresh load covers anyway", function()
      load_inventory()
      logic.on_item(GIL_ITEM_ID)
      logic.on_chunk(ZONE_IN, {})
      assert.is_true(finish_inventory())
      assert.is_false(finish_inventory())
    end)

    it("wants only the packets it handles", function()
      for _, id in ipairs({ ZONE_IN, FINISH_INVENTORY, ITEM_ASSIGN, ITEM_UPDATES, FOUND_ITEM }) do
        assert.is_true(logic.wants_chunk(id), ("packet 0x%03X"):format(id))
      end
      assert.is_false(logic.wants_chunk(0x00E))
    end)

    it("does not need the zone in packet parsed, only that it arrived", function()
      -- 0x00A is one of the largest packets in the game, and every parse is a
      -- chance to throw inside the handler every other component shares.
      assert.is_false(logic.needs_packet(ZONE_IN))
      assert.is_false(logic.needs_packet(FINISH_INVENTORY))
      for _, id in ipairs({ ITEM_ASSIGN, ITEM_UPDATES, FOUND_ITEM }) do
        assert.is_true(logic.needs_packet(id), ("packet 0x%03X"):format(id))
      end
    end)

    it("survives a packet it could not parse", function()
      -- packets.parse can hand back nil; indexing that is the kind of silent
      -- failure Windower is full of.
      assert.is_false(logic.on_chunk(ITEM_ASSIGN, nil))
      assert.is_false(logic.on_chunk(FOUND_ITEM, nil))
    end)

    it("still refreshes when the finish packet could not be parsed", function()
      -- Nothing is read out of this packet, so refusing to act on it without
      -- one would make a parse failure stop every later refresh: it gates the
      -- only path a pending change has.
      assert.is_true(logic.on_chunk(FINISH_INVENTORY, nil))
    end)
  end)

  describe("formatting", function()
    local function shows(amount)
      logic.set_gil(amount)
      return logic.text()
    end

    it("groups thousands with commas", function()
      assert.are.equal("0", shows(0))
      assert.are.equal("999", shows(999))
      assert.are.equal("1,000", shows(1000))
      assert.are.equal("999,999", shows(999999))
      assert.are.equal("1,234,567", shows(1234567))
    end)

    it("handles the gil cap", function()
      assert.are.equal("999,999,999", shows(999999999))
    end)

    it("says so before the first read, rather than showing a wrong number", function()
      assert.are.equal("Loading...", logic.text())
    end)

    it("keeps the last good value when a read comes back empty", function()
      shows(1000)
      assert.are.equal("1,000", shows(nil))
    end)

    it("keeps the last good value when a read comes back as nonsense", function()
      shows(1000)
      assert.are.equal("1,000", shows("plenty"))
    end)

    it("drops the value on logout, so it cannot be shown to the next character", function()
      shows(1000)
      logic.on_logout()
      assert.are.equal("Loading...", logic.text())
    end)
  end)

  describe("preview", function()
    it("shows a sample wide enough to fill the reserved width", function()
      logic.set_gil(500)
      logic.set_preview(true)
      assert.are.equal("123,456,789", logic.text())
    end)

    it("restores the live value on exit", function()
      logic.set_gil(500)
      logic.set_preview(true)
      logic.set_preview(false)
      assert.are.equal("500", logic.text())
    end)
  end)

  describe("geometry", function()
    it("puts the number at the origin, nudged down to centre on the icon", function()
      local geometry = logic.geometry(100, 200, 1)
      assert.are.equal(100, geometry.text.x)
      assert.are.equal(204, geometry.text.y)
      assert.are.equal(9, geometry.text.size)
    end)

    it("parks the icon past the reserved width, so digits never move it", function()
      local geometry = logic.geometry(100, 200, 1)
      assert.are.equal(161, geometry.icon.x)
      assert.are.equal(200, geometry.icon.y)
      assert.are.equal(23, geometry.icon.size)
    end)

    it("multiplies every offset by the scale", function()
      local geometry = logic.geometry(100, 200, 2)
      assert.are.equal(100, geometry.text.x)
      assert.are.equal(208, geometry.text.y)
      assert.are.equal(18, geometry.text.size)
      assert.are.equal(221, geometry.icon.x)
      assert.are.equal(46, geometry.icon.size)
    end)

    it("rounds the font size to whole pixels", function()
      config.font_size = 9
      assert.are.equal(14, logic.geometry(0, 0, 1.5).text.size)
    end)
  end)

  describe("bounds", function()
    it("returns the origin it was given, which the framework clamps against", function()
      local x, y = logic.bounds(100, 200, 1)
      assert.are.equal(100, x)
      assert.are.equal(200, y)
    end)

    it("covers the number, the gap and the icon", function()
      local _, _, width, height = logic.bounds(100, 200, 1)
      assert.are.equal(84, width)
      assert.are.equal(23, height)
    end)

    it("scales with the widget", function()
      local _, _, width, height = logic.bounds(100, 200, 2)
      assert.are.equal(167, width)
      assert.are.equal(46, height)
    end)

    it("keeps the default position in step with the reserved width", function()
      -- defaults.lua restates the reserved-width formula to place the widget on
      -- the reference addon's footprint (its number ended 285px in from the
      -- right). Drift in either file moves the widget silently.
      config.icon.visible = false
      local _, _, reserved = logic.bounds(0, 0, 1)
      assert.are.equal(1920 - 285 - reserved, config.layout.pos.x)
    end)

    it("drops the icon from the box when it is turned off", function()
      config.icon.visible = false
      local _, _, width = logic.bounds(100, 200, 1)
      assert.are.equal(60, width)
    end)

    it("grows with a font too tall for the icon", function()
      config.font_size = 40
      local _, _, _, height = logic.bounds(100, 200, 1)
      assert.is_true(height > 23)
    end)
  end)
end)
