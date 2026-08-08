local new_logic = require("components/equipviewer/logic")
local build_defaults = require("components/equipviewer/defaults")

local MAIN, SUB, RANGE, AMMO = 0, 1, 2, 3
local HEAD, BODY, HANDS, LEGS, FEET = 4, 5, 6, 7, 8
local NECK, WAIST, LEFT_EAR, RIGHT_EAR = 9, 10, 11, 12
local LEFT_RING, RIGHT_RING, BACK = 13, 14, 15

describe("equipviewer logic", function()
  local logic, config

  before_each(function()
    config = build_defaults(1920, 1080)
    logic = new_logic(config)
  end)

  describe("the grid", function()
    it("has one cell per equipment slot", function()
      local slots = logic.slots()
      assert.equal(16, #slots)
      assert.equal(MAIN, slots[1])
      assert.equal(BACK, slots[16])
    end)

    --[[ The reference does not lay the slots out in slot-id order: it gives
         each one a display position and reads the grid left to right. Weapons
         on the top row, then head and the neck/ear group, then the body group
         with the rings, then back/waist/legs/feet. ]]
    it("places every slot where the reference put it", function()
      local cells = {
        [MAIN] = { 0, 0 },
        [SUB] = { 1, 0 },
        [RANGE] = { 2, 0 },
        [AMMO] = { 3, 0 },
        [HEAD] = { 0, 1 },
        [NECK] = { 1, 1 },
        [LEFT_EAR] = { 2, 1 },
        [RIGHT_EAR] = { 3, 1 },
        [BODY] = { 0, 2 },
        [HANDS] = { 1, 2 },
        [LEFT_RING] = { 2, 2 },
        [RIGHT_RING] = { 3, 2 },
        [BACK] = { 0, 3 },
        [WAIST] = { 1, 3 },
        [LEGS] = { 2, 3 },
        [FEET] = { 3, 3 },
      }
      for slot, cell in pairs(cells) do
        local column, row = cell[1], cell[2]
        local placed = logic.cell(slot, 100, 200, 1)
        assert.equal(100 + column * 32, placed.x, "slot " .. slot .. " column")
        assert.equal(200 + row * 32, placed.y, "slot " .. slot .. " row")
        assert.equal(32, placed.size)
      end
    end)

    it("scales the cells and their spacing together", function()
      -- The right ring is the fourth cell of the third row.
      local placed = logic.cell(RIGHT_RING, 100, 200, 2)
      assert.equal(100 + 3 * 64, placed.x)
      assert.equal(200 + 2 * 64, placed.y)
      assert.equal(64, placed.size)
    end)

    it("follows the configured icon size", function()
      config.icon_size = 40
      local placed = logic.cell(FEET, 0, 0, 1)
      assert.equal(120, placed.x)
      assert.equal(120, placed.y)
      assert.equal(40, placed.size)
    end)
  end)

  --[[ The framework clamps a widget on screen by comparing get_bounds against
       the origin it handed set_pos, and layout mode's drag offsets assume the
       same. Every cell sits at a non-negative offset from the origin, so the
       grid is its own bounding box. ]]
  describe("bounds", function()
    it("is the four-by-four grid, anchored at the origin it was given", function()
      local x, y, width, height = logic.bounds(100, 200, 1)
      assert.equal(100, x)
      assert.equal(200, y)
      assert.equal(128, width)
      assert.equal(128, height)
    end)

    it("scales with the widget", function()
      local _, _, width, height = logic.bounds(0, 0, 1.5)
      assert.equal(192, width)
      assert.equal(192, height)
    end)

    it("covers the last cell exactly", function()
      local last = logic.cell(FEET, 100, 200, 1)
      local x, y, width, height = logic.bounds(100, 200, 1)
      assert.equal(x + width, last.x + last.size)
      assert.equal(y + height, last.y + last.size)
    end)
  end)

  describe("the ammo count", function()
    --[[ Left-justified over the ammo cell, never right-justified: texts.pos
         adds the screen width to x when the right flag is set, which would put
         the number off screen. The reference's own justify toggle goes with
         it. ]]
    it("sits over the ammo cell", function()
      local ammo = logic.cell(AMMO, 100, 200, 1)
      local placed = logic.ammo_position(100, 200, 1)
      assert.equal(ammo.x, placed.x)
      assert.equal(200 + 32 * 0.58, placed.y)
      -- A font size is whole pixels, unlike a position.
      assert.equal(math.floor(32 * 0.27 + 0.5), placed.size)
    end)

    it("scales with the widget", function()
      local placed = logic.ammo_position(0, 0, 2)
      assert.equal(64 * 3, placed.x)
      assert.equal(64 * 0.58, placed.y)
      assert.equal(math.floor(64 * 0.27 + 0.5), placed.size)
    end)
  end)

  describe("reading the equipment table", function()
    -- What the client hands back: an index per slot and a bag beside it. An
    -- index of 0 is an empty slot; the item itself takes a second read.
    local function equipment(overrides)
      local table_ = {}
      for _, name in ipairs({
        "main",
        "sub",
        "range",
        "ammo",
        "head",
        "body",
        "hands",
        "legs",
        "feet",
        "neck",
        "waist",
        "left_ear",
        "right_ear",
        "left_ring",
        "right_ring",
        "back",
      }) do
        table_[name] = 0
        table_[name .. "_bag"] = 0
      end
      for name, value in pairs(overrides or {}) do
        table_[name] = value
      end
      return table_
    end

    it("asks for the item in every occupied slot", function()
      local reads = logic.set_equipment(equipment({ main = 5, main_bag = 0, head = 12, head_bag = 8 }))
      assert.equal(2, #reads)
      table.sort(reads, function(left, right)
        return left.slot < right.slot
      end)
      assert.same({ slot = MAIN, bag = 0, index = 5 }, reads[1])
      assert.same({ slot = HEAD, bag = 8, index = 12 }, reads[2])
    end)

    it("empties a slot the client reports as unoccupied without reading it", function()
      logic.set_equipment(equipment({ main = 5 }))
      logic.set_item(MAIN, 4096, 1)
      assert.equal(4096, logic.item(MAIN))

      assert.equal(0, #logic.set_equipment(equipment()))
      assert.equal(0, logic.item(MAIN))
    end)

    -- get_items comes back empty this early into a login. Leaving the grid
    -- alone beats blanking it and reading nothing back.
    -- Half an answer is not an answer: an index with no bag beside it cannot
    -- be read, and Lua would carry the nil into the call without complaint.
    it("empties a slot the client named without a bag", function()
      logic.set_equipment(equipment({ main = 5 }))
      logic.set_item(MAIN, 4096, 1)

      local table_ = equipment()
      table_.main = 5
      table_.main_bag = nil
      assert.equal(0, #logic.set_equipment(table_))
      assert.equal(0, logic.item(MAIN))
    end)

    it("changes nothing when the client has no equipment table yet", function()
      logic.set_equipment(equipment({ main = 5 }))
      logic.set_item(MAIN, 4096, 1)

      assert.equal(0, #logic.set_equipment(nil))
      assert.equal(4096, logic.item(MAIN))
    end)
  end)

  describe("the slot state machine", function()
    local EQUIP = 0x050
    local ITEM_COUNT = 0x01E
    local ITEM_ASSIGN = 0x01F
    local ITEM_UPDATES = 0x020
    local JOB_INFO = 0x01B
    local FINISH_INVENTORY = 0x01D

    local EQUIPPED = 5 -- the item status the client reports for worn gear

    it("wants only the packets that can move gear", function()
      for _, id in ipairs({ EQUIP, ITEM_COUNT, ITEM_ASSIGN, ITEM_UPDATES, JOB_INFO, FINISH_INVENTORY }) do
        assert.is_true(logic.wants_chunk(id), ("0x%03X should be handled"):format(id))
      end
      for _, id in ipairs({ 0x00A, 0x028, 0x076, 0x0D2 }) do
        assert.is_false(logic.wants_chunk(id), ("0x%03X should be ignored"):format(id))
      end
    end)

    --[[ The equipment table is all zeros until the client has finished pushing
         the inventory, and reading it that early does not merely come back
         empty - it blanks the grid, because a zero index is how the client
         says a slot is empty. The item packets in that same burst cannot fill
         it back in: they are matched on a bag and index no slot knows yet. So
         the read that matters is the one after the bags have settled. ]]
    it("re-reads everything once the inventory has finished loading", function()
      assert.is_true(logic.on_chunk(FINISH_INVENTORY, { Flag = 0 }).refresh)
      assert.is_true(logic.on_chunk(FINISH_INVENTORY, { Flag = 1 }).refresh)
    end)

    -- Nothing is read out of it, so a parse failure must not be what stops the
    -- grid ever being filled in.
    it("re-reads everything even if that packet could not be parsed", function()
      assert.is_true(logic.on_chunk(FINISH_INVENTORY, nil).refresh)
    end)

    it("reads the item behind a newly equipped slot", function()
      local result = logic.on_chunk(EQUIP, {
        ["Equipment Slot"] = BODY,
        ["Inventory Bag"] = 8,
        ["Inventory Index"] = 30,
      })
      assert.same({ { slot = BODY, bag = 8, index = 30 } }, result.reads)
      assert.is_false(result.refresh)
    end)

    it("empties a slot the player unequipped", function()
      logic.set_item(BODY, 4096, 1)
      local result = logic.on_chunk(EQUIP, {
        ["Equipment Slot"] = BODY,
        ["Inventory Bag"] = 0,
        ["Inventory Index"] = 0,
      })
      assert.equal(0, #result.reads)
      assert.equal(0, logic.item(BODY))
    end)

    it("takes the item straight off an update, without a second read", function()
      logic.on_chunk(EQUIP, { ["Equipment Slot"] = HEAD, ["Inventory Bag"] = 0, ["Inventory Index"] = 7 })
      local result = logic.on_chunk(ITEM_UPDATES, {
        Bag = 0,
        Index = 7,
        Item = 12345,
        Count = 1,
        Status = EQUIPPED,
      })
      assert.equal(0, #result.reads)
      assert.equal(12345, logic.item(HEAD))
    end)

    it("ignores an update for something that is not equipped", function()
      logic.on_chunk(EQUIP, { ["Equipment Slot"] = HEAD, ["Inventory Bag"] = 0, ["Inventory Index"] = 7 })
      logic.set_item(HEAD, 12345, 1)
      logic.on_chunk(ITEM_ASSIGN, { Bag = 0, Index = 40, Item = 999, Count = 1, Status = EQUIPPED })
      assert.equal(12345, logic.item(HEAD))
    end)

    -- Bag and index are only unique together: index 7 of the satchel is not
    -- index 7 of the inventory.
    it("matches an update on bag as well as index", function()
      logic.on_chunk(EQUIP, { ["Equipment Slot"] = HEAD, ["Inventory Bag"] = 0, ["Inventory Index"] = 7 })
      logic.set_item(HEAD, 12345, 1)
      logic.on_chunk(ITEM_UPDATES, { Bag = 8, Index = 7, Item = 999, Count = 1, Status = EQUIPPED })
      assert.equal(12345, logic.item(HEAD))
    end)

    it("empties a slot whose stack ran out and is no longer worn", function()
      logic.on_chunk(EQUIP, { ["Equipment Slot"] = AMMO, ["Inventory Bag"] = 0, ["Inventory Index"] = 3 })
      logic.set_item(AMMO, 18000, 5)
      logic.on_chunk(ITEM_UPDATES, { Bag = 0, Index = 3, Item = 18000, Count = 0, Status = 0 })
      assert.equal(0, logic.item(AMMO))
    end)

    it("keeps a slot the client still reports as worn", function()
      logic.on_chunk(EQUIP, { ["Equipment Slot"] = AMMO, ["Inventory Bag"] = 0, ["Inventory Index"] = 3 })
      logic.set_item(AMMO, 18000, 5)
      logic.on_chunk(ITEM_UPDATES, { Bag = 0, Index = 3, Item = 18000, Count = 0, Status = EQUIPPED })
      assert.equal(18000, logic.item(AMMO))
    end)

    --[[ 0x01E carries no Item field at all, only a new count - it is what
         arrives as ammunition is spent. There is nothing to read: the slot
         already knows what is in it. ]]
    it("recounts a slot without asking what is in it", function()
      logic.on_chunk(EQUIP, { ["Equipment Slot"] = AMMO, ["Inventory Bag"] = 0, ["Inventory Index"] = 3 })
      logic.set_item(AMMO, 18000, 99)
      local result = logic.on_chunk(ITEM_COUNT, { Bag = 0, Index = 3, Count = 98, Status = EQUIPPED })
      assert.equal(0, #result.reads)
      assert.equal(18000, logic.item(AMMO))
      assert.equal("98", logic.ammo_text())
    end)

    it("re-reads everything when the job changes", function()
      local result = logic.on_chunk(JOB_INFO, { ["Encumbrance Flags"] = 0 })
      assert.is_true(result.refresh)
    end)

    it("does nothing with a packet that could not be parsed", function()
      logic.set_item(BODY, 4096, 1)
      for _, id in ipairs({ EQUIP, ITEM_COUNT, ITEM_ASSIGN, ITEM_UPDATES, JOB_INFO }) do
        local result = logic.on_chunk(id, nil)
        assert.is_false(result.refresh)
        assert.equal(0, #result.reads)
      end
      assert.equal(4096, logic.item(BODY))
    end)

    it("treats the empty-item markers as an empty slot", function()
      for _, empty in ipairs({ 0, 65535 }) do
        logic.set_item(BODY, 4096, 1)
        logic.set_item(BODY, empty, 1)
        assert.equal(0, logic.item(BODY))
      end
    end)

    --[[ The chunk handler runs for every packet the client receives, and the
         zone-in burst is hundreds of item packets for bags nothing here wears.
         Saying so lets the widget leave its thirty-four prims alone. ]]
    it("says when a packet changed nothing, so nothing need be redrawn", function()
      logic.on_chunk(EQUIP, { ["Equipment Slot"] = HEAD, ["Inventory Bag"] = 0, ["Inventory Index"] = 7 })
      local unmatched = logic.on_chunk(ITEM_UPDATES, { Bag = 0, Index = 40, Item = 999, Count = 1, Status = EQUIPPED })
      assert.is_false(unmatched.changed)
      assert.is_false(logic.on_chunk(ITEM_UPDATES, nil).changed)
    end)

    it("says when a packet changed something", function()
      logic.on_chunk(EQUIP, { ["Equipment Slot"] = HEAD, ["Inventory Bag"] = 0, ["Inventory Index"] = 7 })
      local matched = logic.on_chunk(ITEM_UPDATES, { Bag = 0, Index = 7, Item = 999, Count = 1, Status = EQUIPPED })
      assert.is_true(matched.changed)
      assert.is_true(logic.on_chunk(JOB_INFO, { ["Encumbrance Flags"] = 4 }).changed)
      local unequipped =
        logic.on_chunk(EQUIP, { ["Equipment Slot"] = HEAD, ["Inventory Bag"] = 0, ["Inventory Index"] = 0 })
      assert.is_true(unequipped.changed)
    end)

    -- get_items(bag, index) can come back nil, and an unknown item is not the
    -- same fact as an empty slot.
    it("leaves a slot alone when the read came back with nothing", function()
      logic.set_item(BODY, 4096, 1)
      logic.set_item(BODY, nil, nil)
      assert.equal(4096, logic.item(BODY))
    end)
  end)

  describe("encumbrance", function()
    local JOB_INFO = 0x01B

    local function encumber(flags)
      logic.on_chunk(JOB_INFO, { ["Encumbrance Flags"] = flags })
    end

    --[[ The low sixteen bits of the flags are the equipment slots, bit n being
         slot n. Decoded with arithmetic rather than the bit library, which is
         not part of Lua 5.1 and so cannot be tested here. ]]
    it("locks the slot each bit stands for", function()
      encumber(1)
      assert.is_true(logic.encumbered(MAIN))
      assert.is_false(logic.encumbered(SUB))

      encumber(2 ^ LEGS)
      assert.is_false(logic.encumbered(MAIN))
      assert.is_true(logic.encumbered(LEGS))

      encumber(2 ^ FEET)
      assert.is_true(logic.encumbered(FEET))

      encumber(2 ^ BACK)
      assert.is_true(logic.encumbered(BACK))
    end)

    it("locks every slot when everything is encumbered", function()
      encumber(0xFFFF)
      for _, slot in ipairs(logic.slots()) do
        assert.is_true(logic.encumbered(slot), "slot " .. slot)
      end
    end)

    it("locks nothing when nothing is encumbered", function()
      encumber(0xFFFF)
      encumber(0)
      for _, slot in ipairs(logic.slots()) do
        assert.is_false(logic.encumbered(slot), "slot " .. slot)
      end
    end)

    -- The stat bits live above the slot bits and must not reach the grid.
    it("ignores the flags above the sixteen slots", function()
      encumber(0xFFFF0000)
      for _, slot in ipairs(logic.slots()) do
        assert.is_false(logic.encumbered(slot), "slot " .. slot)
      end
    end)

    it("shows nothing while the setting is off", function()
      encumber(0xFFFF)
      config.show_encumbrance = false
      assert.is_false(logic.encumbered(MAIN))
    end)
  end)

  describe("the ammo count", function()
    it("says nothing about a slot holding a single item", function()
      logic.set_item(AMMO, 18000, 1)
      assert.is_nil(logic.ammo_text())
    end)

    it("says nothing about an empty slot", function()
      assert.is_nil(logic.ammo_text())
    end)

    it("counts a stack", function()
      logic.set_item(AMMO, 18000, 99)
      assert.equal("99", logic.ammo_text())
    end)

    it("says nothing while the setting is off", function()
      logic.set_item(AMMO, 18000, 99)
      config.show_ammo_count = false
      assert.is_nil(logic.ammo_text())
    end)

    it("forgets the count when the slot empties", function()
      logic.set_item(AMMO, 18000, 99)
      logic.set_item(AMMO, 0, nil)
      assert.is_nil(logic.ammo_text())
    end)
  end)

  -- The character is gone, so what it was wearing must not be shown to whoever
  -- logs in next.
  describe("logging out", function()
    it("empties every slot and forgets the encumbrance", function()
      logic.set_equipment({ main = 1, main_bag = 0 })
      logic.set_item(MAIN, 4096, 1)
      logic.set_item(AMMO, 18000, 99)
      logic.on_chunk(0x01B, { ["Encumbrance Flags"] = 0xFFFF })

      logic.on_logout()

      for _, slot in ipairs(logic.slots()) do
        assert.equal(0, logic.item(slot))
        assert.is_false(logic.encumbered(slot))
      end
      assert.is_nil(logic.ammo_text())
    end)

    it("forgets where the slots were, so a stale update cannot match", function()
      logic.on_chunk(0x050, { ["Equipment Slot"] = HEAD, ["Inventory Bag"] = 0, ["Inventory Index"] = 7 })
      logic.on_logout()
      logic.on_chunk(0x020, { Bag = 0, Index = 7, Item = 999, Count = 1, Status = 5 })
      assert.equal(0, logic.item(HEAD))
    end)
  end)

  describe("the background panel", function()
    it("follows the setting", function()
      config.bg.visible = false
      assert.is_false(logic.background_visible())
      config.bg.visible = true
      assert.is_true(logic.background_visible())
    end)

    -- An unequipped grid with the panel turned off draws nothing at all, and
    -- there would be nothing to see while arranging it.
    it("is forced on while the layout is being arranged", function()
      config.bg.visible = false
      logic.set_preview(true)
      assert.is_true(logic.background_visible())

      logic.set_preview(false)
      assert.is_false(logic.background_visible())
    end)
  end)

  describe("commands", function()
    it("reports both settings when asked for nothing", function()
      local message, changed = logic.command({})
      assert.equal("equipviewer: encumbrance on, ammo count on", message)
      assert.is_false(changed)
    end)

    it("reports the settings as they stand", function()
      config.show_encumbrance = false
      config.show_ammo_count = false
      assert.equal("equipviewer: encumbrance off, ammo count off", (logic.command(nil)))
    end)

    it("turns the encumbrance markers off and on", function()
      local message, changed = logic.command({ "encumbrance", "off" })
      assert.equal("equipviewer encumbrance off", message)
      assert.is_true(changed)
      assert.is_false(config.show_encumbrance)

      assert.is_true(select(2, logic.command({ "encumbrance", "on" })))
      assert.is_true(config.show_encumbrance)
    end)

    it("turns the ammo count off and on", function()
      local message, changed = logic.command({ "ammocount", "off" })
      assert.equal("equipviewer ammo count off", message)
      assert.is_true(changed)
      assert.is_false(config.show_ammo_count)

      assert.is_true(select(2, logic.command({ "ammocount", "on" })))
      assert.is_true(config.show_ammo_count)
    end)

    it("matches the verb and its argument whatever the case", function()
      assert.is_true(select(2, logic.command({ "EncUmbrance", "OFF" })))
      assert.is_false(config.show_encumbrance)
    end)

    it("asks for on or off rather than guessing", function()
      local message, changed = logic.command({ "encumbrance" })
      assert.equal("//hud equipviewer encumbrance needs on or off", message)
      assert.is_false(changed)
      assert.is_true(config.show_encumbrance)

      assert.is_false(select(2, logic.command({ "ammocount", "yes" })))
      assert.is_true(config.show_ammo_count)
    end)

    -- Unknown input always answers with a hint, never silence.
    it("names what it does understand when the verb is not one of them", function()
      local message, changed = logic.command({ "size", "64" })
      assert.equal("equipviewer has no 'size' setting (encumbrance, ammocount)", message)
      assert.is_false(changed)
    end)
  end)
end)
