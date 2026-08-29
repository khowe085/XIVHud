local new_equipviewer = require("components/equipviewer/equipviewer")
local fakes = require("tests/support/fakes")

local MAIN, HEAD, BODY, BACK = 0, 4, 5, 15

local EQUIP = 0x050
local ITEM_UPDATES = 0x020
local JOB_INFO = 0x01B
local FINISH_INVENTORY = 0x01D
local UNHANDLED = 0x00E

local SLOT_COUNT = 16
-- An icon block of the right length; the bytes themselves do not matter here,
-- only that the decoder accepts it. icons_spec owns what it decodes to.
local RECORD = string.rep("\0", 0x800)

describe("equipviewer widget", function()
  local prims, widget, config
  local equipment, items, dats, files, writes, saves, packet, parsed, game
  local equipment_reads, lookups

  -- Prims are built in one order and never rebuilt: the panel, then an icon
  -- per slot, then an encumbrance marker per slot, then the ammo count.
  local function panel()
    return prims.images[1]
  end

  local function icon(slot)
    return prims.images[2 + slot]
  end

  local function marker(slot)
    return prims.images[2 + SLOT_COUNT + slot]
  end

  local function ammo()
    return prims.texts[1]
  end

  local function attach()
    config = widget.defaults
    widget.attach(config, function()
      saves = saves + 1
    end)
  end

  -- One occupied slot per name, as the client's equipment table reports it.
  local function equip(slot_name, index, bag)
    equipment[slot_name] = index
    equipment[slot_name .. "_bag"] = bag or 0
  end

  local function put_item(bag, index, id, count)
    items[bag .. ":" .. index] = { id = id, count = count }
  end

  local function chunk(id, fields)
    packet = fields
    widget.update("chunk", id, "raw bytes")
  end

  local function tick()
    widget.update()
  end

  before_each(function()
    prims = fakes.prims()
    equipment = {}
    items = {}
    dats = {}
    files = {}
    writes = {}
    saves = 0
    packet = nil
    parsed = {}
    game = "C:/FFXI"
    equipment_reads = 0
    lookups = 0

    widget = new_equipviewer({
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      asset = function(path)
        return "addons/XIVHud/" .. path
      end,
      get_equipment = function()
        equipment_reads = equipment_reads + 1
        return equipment
      end,
      get_item = function(bag, index)
        return items[bag .. ":" .. index]
      end,
      parse_packet = function(data)
        parsed[#parsed + 1] = data
        return packet
      end,
      file_exists = function(path)
        lookups = lookups + 1
        return files[path] == true
      end,
      read_dat = function(path, offset, length)
        local dat = dats[path]
        return dat and dat(offset, length) or nil
      end,
      write_binary = function(path, contents)
        writes[#writes + 1] = { path = path, contents = contents }
        files["addons/XIVHud/" .. path] = true
        return true
      end,
      game_path = function()
        return game
      end,
    })
  end)

  describe("construction", function()
    it("is named for its config namespace and command word", function()
      assert.equal("equipviewer", widget.name)
    end)

    it("builds a panel, a grid of icons, a marker per slot and the ammo count", function()
      assert.equal(1 + SLOT_COUNT * 2, #prims.images)
      assert.equal(1, #prims.texts)
    end)

    it("makes every prim non-draggable, because the framework owns dragging", function()
      for _, prim in ipairs(prims.all) do
        assert.equal(false, prim.last.draggable, prim.kind .. " must not drag itself")
      end
    end)

    -- An image sized to its texture ignores size(), which would leave the
    -- framework's scale doing nothing.
    it("stops every image sizing itself to its texture", function()
      for _, image in ipairs(prims.images) do
        assert.equal(false, image.last.fit)
      end
    end)

    -- A prim without a texture is not something this repo relies on drawing:
    -- the framework's own highlight box is a white square tinted to colour,
    -- and the panel is the same trick.
    it("draws the panel from art rather than trusting a bare colour", function()
      assert.equal("addons/XIVHud/assets/own/panel.png", panel().last.path)
    end)

    it("draws nothing before it is attached", function()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)
  end)

  describe("reading what is equipped", function()
    before_each(function()
      equip("main", 5)
      equip("head", 2, 8)
      put_item(0, 5, 4096, 1)
      put_item(8, 2, 12345, 1)
      files["addons/XIVHud/icons/4096.bmp"] = true
      files["addons/XIVHud/icons/12345.bmp"] = true
    end)

    it("shows the icon of every occupied slot", function()
      attach()
      widget.set_pos(100, 200)
      widget.show()

      assert.equal("addons/XIVHud/icons/4096.bmp", icon(MAIN).last.path)
      assert.is_true(icon(MAIN).visible)
      assert.equal("addons/XIVHud/icons/12345.bmp", icon(HEAD).last.path)
      assert.is_true(icon(HEAD).visible)
    end)

    it("leaves an empty slot empty", function()
      attach()
      widget.show()
      assert.is_false(icon(BODY).visible)
    end)

    it("reads the item behind a slot the player just equipped", function()
      attach()
      widget.show()
      put_item(0, 9, 777, 1)
      files["addons/XIVHud/icons/777.bmp"] = true

      chunk(EQUIP, { ["Equipment Slot"] = BODY, ["Inventory Bag"] = 0, ["Inventory Index"] = 9 })
      assert.equal("addons/XIVHud/icons/777.bmp", icon(BODY).last.path)
      assert.is_true(icon(BODY).visible)
    end)

    it("hides a slot the player emptied", function()
      attach()
      widget.show()
      chunk(EQUIP, { ["Equipment Slot"] = MAIN, ["Inventory Bag"] = 0, ["Inventory Index"] = 0 })
      assert.is_false(icon(MAIN).visible)
    end)

    --[[ Reading the whole table means a full item push plus a read per
         occupied slot, and the packets that ask for one arrive in bursts - one
         per bag as the inventory settles. Holding it to the next frame
         collapses the burst into a single read. ]]
    it("re-reads everything on the frame after the job changed", function()
      attach()
      widget.show()
      equipment = {}
      equip("back", 4)
      put_item(0, 4, 555, 1)
      files["addons/XIVHud/icons/555.bmp"] = true

      chunk(JOB_INFO, { ["Encumbrance Flags"] = 0 })
      assert.is_true(icon(MAIN).visible)

      tick()
      assert.is_false(icon(MAIN).visible)
      assert.equal("addons/XIVHud/icons/555.bmp", icon(BACK).last.path)
    end)

    --[[ The equipment table is all zeros until the bags have settled, and
         reading it that early blanks the grid rather than leaving it alone.
         Nothing else fills it in at a login. ]]
    it("re-reads everything once the inventory has finished loading", function()
      attach()
      widget.show()
      equipment = {}
      equip("back", 4)
      put_item(0, 4, 555, 1)
      files["addons/XIVHud/icons/555.bmp"] = true

      chunk(FINISH_INVENTORY, { Flag = 0 })
      tick()
      assert.equal("addons/XIVHud/icons/555.bmp", icon(BACK).last.path)
    end)

    -- One arrives per bag, and there are a dozen of them.
    it("collapses a burst of them into a single read", function()
      attach()
      equipment_reads = 0
      chunk(FINISH_INVENTORY, { Flag = 0 })
      chunk(FINISH_INVENTORY, { Flag = 0 })
      chunk(FINISH_INVENTORY, { Flag = 1 })
      assert.equal(0, equipment_reads)

      tick()
      assert.equal(1, equipment_reads)
      tick()
      assert.equal(1, equipment_reads)
    end)

    --[[ Every packet the client receives reaches this handler, and a zone-in
         is hundreds of item packets for bags nothing here wears. ]]
    it("leaves its prims alone for a packet that changed nothing", function()
      attach()
      widget.show()
      local before = #icon(MAIN).calls + #panel().calls + #ammo().calls
      chunk(ITEM_UPDATES, { Bag = 3, Index = 44, Item = 999, Count = 1, Status = 5 })
      assert.equal(before, #icon(MAIN).calls + #panel().calls + #ammo().calls)
    end)

    -- Setting a texture is a call into the prim layer; the path a slot already
    -- holds is not worth making it again.
    it("does not set a texture it has already set", function()
      attach()
      widget.show()
      local before = #icon(MAIN).calls
      widget.hide()
      widget.show()
      local paths = 0
      for index = before + 1, #icon(MAIN).calls do
        if icon(MAIN).calls[index].name == "path" then
          paths = paths + 1
        end
      end
      assert.equal(0, paths)
    end)

    -- The chunk handler runs for every packet the client receives, so an id
    -- this component does not care about must not reach the packet parser.
    it("does not parse a packet it has no use for", function()
      attach()
      widget.update("chunk", UNHANDLED, "raw bytes")
      assert.equal(0, #parsed)
    end)

    it("survives a packet that could not be parsed", function()
      attach()
      widget.show()
      chunk(ITEM_UPDATES, nil)
      assert.is_true(icon(MAIN).visible)
    end)
  end)

  describe("extracting an icon the cache does not have", function()
    before_each(function()
      equip("main", 5)
      put_item(0, 5, 4096, 1)
      dats["C:/FFXI/ROM/118/107.DAT"] = function()
        return RECORD
      end
    end)

    it("does not read a DAT for an icon already on disk", function()
      files["addons/XIVHud/icons/4096.bmp"] = true
      dats["C:/FFXI/ROM/118/107.DAT"] = function()
        error("should not have been read")
      end
      attach()
      tick()
      assert.equal(0, #writes)
    end)

    -- Sixteen misses at once would be sixteen DAT reads, decodes and file
    -- writes inside one frame, so the work is queued and drained a frame at a
    -- time instead.
    it("waits for a frame rather than extracting inside the packet handler", function()
      attach()
      assert.equal(0, #writes)

      tick()
      assert.equal(1, #writes)
      assert.equal("icons/4096.bmp", writes[1].path)
      assert.equal("BM", writes[1].contents:sub(1, 2))
    end)

    it("shows the icon once it has been written", function()
      attach()
      widget.show()
      assert.is_false(icon(MAIN).visible)

      tick()
      assert.equal("addons/XIVHud/icons/4096.bmp", icon(MAIN).last.path)
      assert.is_true(icon(MAIN).visible)
    end)

    it("extracts one icon per frame, not the whole queue at once", function()
      equip("head", 6)
      put_item(0, 6, 12345, 1)
      dats["C:/FFXI/ROM/118/109.DAT"] = function()
        return RECORD
      end

      attach()
      tick()
      assert.equal(1, #writes)
      tick()
      assert.equal(2, #writes)
      tick()
      assert.equal(2, #writes)
    end)

    it("reads the icon out of the DAT the item belongs to", function()
      local asked
      dats["C:/FFXI/ROM/118/107.DAT"] = function(offset, length)
        asked = { offset = offset, length = length }
        return RECORD
      end
      attach()
      tick()
      -- Item 4096 is the first record of the usable-items DAT.
      assert.same({ offset = 0x2BD, length = 0x800 }, asked)
    end)

    it("prefers the game path the player configured", function()
      attach()
      config.game_path = "D:/Games/FFXI"
      dats["D:/Games/FFXI/ROM/118/107.DAT"] = function()
        return RECORD
      end
      dats["C:/FFXI/ROM/118/107.DAT"] = nil

      tick()
      assert.equal(1, #writes)
    end)

    it("gives up on an icon it could not read, rather than retrying every frame", function()
      local attempts = 0
      dats["C:/FFXI/ROM/118/107.DAT"] = function()
        attempts = attempts + 1
        return nil
      end

      attach()
      widget.show()
      for _ = 1, 5 do
        tick()
      end
      assert.equal(1, attempts)
      assert.equal(0, #writes)
      assert.is_false(icon(MAIN).visible)
    end)

    -- Every redraw would otherwise probe the disk for a file that is never
    -- going to be there, and a redraw happens on the packet path.
    it("stops looking on disk for an icon it has given up on", function()
      dats["C:/FFXI/ROM/118/107.DAT"] = nil
      attach()
      widget.show()
      tick()

      lookups = 0
      chunk(EQUIP, { ["Equipment Slot"] = MAIN, ["Inventory Bag"] = 0, ["Inventory Index"] = 5 })
      assert.equal(0, lookups)
    end)

    it("gives up on an item no DAT covers", function()
      put_item(0, 5, 0x8000, 1)
      attach()
      tick()
      assert.equal(0, #writes)
    end)

    it("asks for nothing while the game path is unknown", function()
      game = nil
      attach()
      tick()
      assert.equal(0, #writes)
    end)
  end)

  describe("encumbrance", function()
    it("marks the slots the flags name", function()
      attach()
      widget.show()
      chunk(JOB_INFO, { ["Encumbrance Flags"] = 2 ^ HEAD })
      assert.is_true(marker(HEAD).visible)
      assert.is_false(marker(BODY).visible)
    end)

    it("dims the marker against the icon under it", function()
      attach()
      chunk(JOB_INFO, { ["Encumbrance Flags"] = 2 ^ HEAD })
      assert.equal(math.floor(230 * 0.8), marker(HEAD).last.alpha)
    end)

    it("clears every marker when the encumbrance lifts", function()
      attach()
      widget.show()
      chunk(JOB_INFO, { ["Encumbrance Flags"] = 0xFFFF })
      chunk(JOB_INFO, { ["Encumbrance Flags"] = 0 })
      for slot = 0, SLOT_COUNT - 1 do
        assert.is_false(marker(slot).visible)
      end
    end)
  end)

  describe("the ammo count", function()
    before_each(function()
      equip("ammo", 3)
      put_item(0, 3, 18000, 90)
      files["addons/XIVHud/icons/18000.bmp"] = true
    end)

    it("counts the stack over the ammo icon", function()
      attach()
      widget.show()
      assert.equal("90", ammo().last.text)
      assert.is_true(ammo().visible)
    end)

    it("follows the stack down as it is spent", function()
      attach()
      widget.show()
      chunk(0x01E, { Bag = 0, Index = 3, Count = 89, Status = 5 })
      assert.equal("89", ammo().last.text)
    end)

    it("says nothing about a single item", function()
      put_item(0, 3, 18000, 1)
      attach()
      widget.show()
      assert.is_false(ammo().visible)
    end)
  end)

  describe("styling", function()
    -- A texts setter called with no value is a getter, and nil is no value:
    -- every one of these has to be handed something.
    it("gives the ammo count a font, a colour and a stroke", function()
      attach()
      assert.equal("sans-serif", ammo().last.font)
      assert.same({ 255, 255, 255 }, ammo().last.color)
      assert.equal(230, ammo().last.alpha)
      assert.equal(1, ammo().last.stroke_width)
      assert.equal(127, ammo().last.stroke_alpha)
    end)

    it("tints the panel to the configured background", function()
      attach()
      assert.same({ 0, 0, 0 }, panel().last.color)
      assert.equal(72, panel().last.alpha)
    end)
  end)

  describe("layout", function()
    it("returns the origin it was given, which the framework clamps against", function()
      attach()
      widget.set_pos(100, 200)
      local x, y, width, height = widget.get_bounds()
      assert.equal(100, x)
      assert.equal(200, y)
      assert.equal(128, width)
      assert.equal(128, height)
    end)

    it("has no bounds before it has been placed", function()
      attach()
      assert.is_nil(widget.get_bounds())
    end)

    it("places the panel over the whole grid", function()
      attach()
      widget.set_pos(100, 200)
      assert.equal(100, panel().x)
      assert.equal(200, panel().y)
      assert.same({ 128, 128 }, { panel().width, panel().height })
    end)

    it("lays the icons out from the origin", function()
      attach()
      widget.set_pos(100, 200)
      assert.same({ 100, 200 }, { icon(MAIN).x, icon(MAIN).y })
      assert.same({ 100, 200 + 96 }, { icon(BACK).x, icon(BACK).y })
      assert.same({ 32, 32 }, { icon(MAIN).width, icon(MAIN).height })
    end)

    it("keeps a marker over the icon it belongs to", function()
      attach()
      widget.set_pos(100, 200)
      assert.same({ icon(HEAD).x, icon(HEAD).y }, { marker(HEAD).x, marker(HEAD).y })
    end)

    it("scales the whole grid", function()
      attach()
      widget.set_pos(100, 200)
      widget.set_scale(2)
      local _, _, width, height = widget.get_bounds()
      assert.same({ 256, 256 }, { width, height })
      assert.same({ 100, 200 + 192 }, { icon(BACK).x, icon(BACK).y })
      assert.same({ 64, 64 }, { icon(BACK).width, icon(BACK).height })
    end)
  end)

  describe("visibility", function()
    before_each(function()
      equip("main", 5)
      put_item(0, 5, 4096, 1)
      files["addons/XIVHud/icons/4096.bmp"] = true
    end)

    it("hides everything when the framework says to", function()
      attach()
      widget.show()
      chunk(JOB_INFO, { ["Encumbrance Flags"] = 0xFFFF })
      widget.hide()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible, prim.kind .. " should be hidden")
      end
    end)

    it("brings back only what should be on screen", function()
      attach()
      widget.hide()
      widget.show()
      assert.is_true(panel().visible)
      assert.is_true(icon(MAIN).visible)
      assert.is_false(icon(BODY).visible)
      assert.is_false(marker(MAIN).visible)
    end)

    -- With the panel off and nothing equipped there would be nothing to grab
    -- while arranging the layout.
    it("shows the panel while the layout is being arranged", function()
      attach()
      config.bg.visible = false
      widget.show()
      assert.is_false(panel().visible)

      widget.set_preview(true)
      assert.is_true(panel().visible)
      widget.set_preview(false)
      assert.is_false(panel().visible)
    end)
  end)

  describe("logging out", function()
    --[[ The likeliest reason an icon cannot be read is a game path pointing at
         the wrong install, and the only way to correct that is to edit the
         setting and log back in. An id abandoned for the last character must
         not still be abandoned for this one. ]]
    it("tries again for an icon the last character could not read", function()
      equip("main", 5)
      put_item(0, 5, 4096, 1)
      attach()
      tick()
      assert.equal(2, #widget.handle_command({}))

      widget.detach()
      dats["C:/FFXI/ROM/118/107.DAT"] = function()
        return RECORD
      end
      attach()
      tick()
      assert.equal(1, #writes)
      assert.equal("equipviewer: encumbrance on, ammo count on", widget.handle_command({}))
    end)

    it("empties the grid, so the next character sees none of it", function()
      equip("main", 5)
      put_item(0, 5, 4096, 1)
      files["addons/XIVHud/icons/4096.bmp"] = true
      attach()
      widget.show()

      widget.detach()
      widget.show()
      assert.is_false(icon(MAIN).visible)
    end)
  end)

  describe("commands", function()
    it("answers with what it understands", function()
      attach()
      assert.equal("equipviewer: encumbrance on, ammo count on", widget.handle_command({}))
    end)

    it("saves a setting it changed", function()
      attach()
      widget.show()
      chunk(JOB_INFO, { ["Encumbrance Flags"] = 0xFFFF })
      assert.is_true(marker(0).visible)

      widget.handle_command({ "encumbrance", "off" })
      assert.equal(1, saves)
      assert.is_false(marker(0).visible)
    end)

    it("saves nothing it did not change", function()
      attach()
      widget.handle_command({ "encumbrance" })
      assert.equal(0, saves)
    end)

    --[[ An icon that cannot be extracted leaves an empty cell and says
         nothing, and the likeliest cause - a game path Windower guessed wrong -
         empties the whole grid. There is no chat channel from a component, so
         the one place it can be asked about is the command. ]]
    it("owns up to the icons it could not extract", function()
      dats["C:/FFXI/ROM/118/107.DAT"] = nil
      equip("main", 5)
      put_item(0, 5, 4096, 1)
      attach()
      tick()

      local message = widget.handle_command({})
      assert.same({
        "equipviewer: encumbrance on, ammo count on",
        "  1 icon could not be read from the game's DAT files - check the game_path setting",
      }, message)
    end)

    it("says nothing about icons while every one of them was read", function()
      attach()
      assert.equal("equipviewer: encumbrance on, ammo count on", widget.handle_command({}))
    end)
  end)

  describe("teardown", function()
    it("disposes every prim it built", function()
      attach()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.equal(1, prim.destroyed, prim.kind .. " was not disposed exactly once")
      end
    end)
  end)
end)
