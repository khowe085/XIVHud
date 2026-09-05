local new_logic = require("components/invtracker/logic")

describe("invtracker logic", function()
  local logic

  before_each(function()
    logic = new_logic({})
  end)

  describe("the bag catalogue", function()
    -- Read through the layout, which is what actually consumes the catalogue;
    -- the order, the grouping and which bags exist are all visible there.
    local function drawn_keys(overrides)
      local bags = {}
      for _, group in ipairs({
        "equipment",
        "inventory",
        "safe",
        "storage",
        "locker",
        "satchel",
        "sack",
        "case",
        "wardrobe",
        "temporary",
        "treasure",
      }) do
        bags[group] = { enabled = true, columns = 5 }
      end
      for group, value in pairs(overrides or {}) do
        bags[group] = value
      end

      local sizes = {}
      for _, key in ipairs({
        "equipment",
        "inventory",
        "safe",
        "safe2",
        "storage",
        "locker",
        "satchel",
        "sack",
        "case",
        "wardrobe",
        "wardrobe2",
        "wardrobe3",
        "wardrobe4",
        "wardrobe5",
        "wardrobe6",
        "wardrobe7",
        "wardrobe8",
        "temporary",
        "treasure",
        "recycle",
      }) do
        sizes[key] = 10
      end

      local keys = {}
      for _, block in ipairs(new_logic({ spacing = 4, slot_size = 3, bags = bags }).layout(sizes, 0, 0, 1)) do
        keys[#keys + 1] = block.key
      end
      return keys
    end

    it("draws the bags in the reference addon's order", function()
      assert.are.same({
        "equipment",
        "inventory",
        "safe",
        "safe2",
        "storage",
        "locker",
        "satchel",
        "sack",
        "case",
        "wardrobe",
        "wardrobe2",
        "wardrobe3",
        "wardrobe4",
        "wardrobe5",
        "wardrobe6",
        "wardrobe7",
        "wardrobe8",
        "temporary",
        "treasure",
      }, drawn_keys())
    end)

    it("switches both safes and all eight wardrobes with one word each", function()
      local keys = drawn_keys({ safe = { enabled = false, columns = 5 }, wardrobe = { enabled = false, columns = 5 } })

      for _, key in ipairs(keys) do
        assert.is_nil(key:find("safe"), key .. " should have gone with the safe switch")
        assert.is_nil(key:find("wardrobe"), key .. " should have gone with the wardrobe switch")
      end
      assert.is_true(#keys > 0)
    end)

    it("never draws the recycle bin, which nobody tracks the fill of", function()
      for _, key in ipairs(drawn_keys()) do
        assert.are_not.equal("recycle", key)
      end
    end)
  end)

  describe("classifying a slot", function()
    local stacks = { [100] = 12, [200] = 1 }
    local function stack_of(id)
      return stacks[id]
    end

    it("calls an absent or empty slot empty", function()
      assert.are.equal("empty", logic.classify(nil, stack_of))
      assert.are.equal("empty", logic.classify({ id = 100, count = 0 }, stack_of))
    end)

    it("colours a part stack and a full stack apart", function()
      assert.are.equal("default", logic.classify({ id = 100, count = 11, status = 0 }, stack_of))
      assert.are.equal("full_stack", logic.classify({ id = 100, count = 12, status = 0 }, stack_of))
    end)

    it("colours the three flagged statuses", function()
      assert.are.equal("equipped", logic.classify({ id = 100, count = 1, status = 5 }, stack_of))
      assert.are.equal("linkshell_equipped", logic.classify({ id = 100, count = 1, status = 19 }, stack_of))
      assert.are.equal("bazaar", logic.classify({ id = 100, count = 1, status = 25 }, stack_of))
    end)

    it("falls back to the plain colour for a status it does not know", function()
      -- The reference drew an unknown status as an EMPTY slot, so an occupied
      -- slot vanished; a full slot must never read as free space.
      assert.are.equal("default", logic.classify({ id = 100, count = 1, status = 42 }, stack_of))
    end)

    it("treats an unresolvable stack size as a part stack", function()
      -- Without the resources library there is no stack size to compare, and
      -- claiming a full stack on a guess is the worse error.
      assert.are.equal("default", logic.classify({ id = 999, count = 4, status = 0 }, nil))
      assert.are.equal("default", logic.classify({ id = 999, count = 4, status = 0 }, stack_of))
    end)
  end)
  describe("sorting a bag", function()
    local stacks = { [100] = 12, [200] = 99, [300] = 1 }
    local function stack_of(id)
      return stacks[id]
    end

    local function keys(list)
      local out = {}
      for index, slot in ipairs(list) do
        out[index] = slot.tag
      end
      return out
    end

    it("floats the flagged statuses above the plain ones", function()
      local bag = {
        { tag = "plain", id = 100, count = 1, status = 0 },
        { tag = "bazaar", id = 100, count = 1, status = 25 },
        { tag = "equipped", id = 100, count = 1, status = 5 },
      }

      assert.are.same({ "bazaar", "equipped", "plain" }, keys(logic.sort(bag, stack_of)))
    end)

    it("puts the stack nearest full first", function()
      local bag = {
        { tag = "half", id = 200, count = 50, status = 0 },
        { tag = "nearly", id = 200, count = 98, status = 0 },
        { tag = "lonely", id = 200, count = 1, status = 0 },
      }

      assert.are.same({ "nearly", "half", "lonely" }, keys(logic.sort(bag, stack_of)))
    end)

    it("falls back to the larger count when the gap to full ties", function()
      -- Two singletons of unstackable items tie at a gap of zero, so the count
      -- is all that is left to order them by.
      local bag = {
        { tag = "small", id = 300, count = 1, status = 0 },
        { tag = "big", id = 100, count = 12, status = 0 },
      }

      assert.are.same({ "big", "small" }, keys(logic.sort(bag, stack_of)))
    end)

    it("sinks the empty slots below everything held", function()
      local bag = {
        { tag = "empty", id = 0, count = 0, status = 0 },
        { tag = "held", id = 100, count = 3, status = 0 },
      }

      assert.are.same({ "held", "empty" }, keys(logic.sort(bag, stack_of)))
    end)

    it("orders on the count alone when no stack size can be resolved", function()
      local bag = {
        { tag = "one", id = 999, count = 1, status = 0 },
        { tag = "five", id = 999, count = 5, status = 0 },
      }

      assert.are.same({ "five", "one" }, keys(logic.sort(bag, nil)))
    end)

    it("orders a bag holding both known and unknown items consistently", function()
      -- A comparator that skips the gap key for an unresolvable item is not a
      -- strict weak ordering: known-A beats known-C on the gap, C beats the
      -- unknown on the count, and the unknown beats A on the count. Lua's
      -- table.sort can raise on a cycle like that, and it would raise inside
      -- prerender, where guard disables the shared handler after five throws.
      local bag = {
        { tag = "near_full", id = 100, count = 11, status = 0 },
        { tag = "big_stack", id = 200, count = 90, status = 0 },
        { tag = "unknown", id = 777, count = 50, status = 0 },
      }

      local ordered
      assert.has_no.errors(function()
        ordered = logic.sort(bag, stack_of)
      end)
      assert.are.equal(3, #ordered)
    end)

    it("leaves the client's own table untouched", function()
      -- get_items hands back the client's inventory; sorting it in place is
      -- reordering something another addon may be holding.
      local bag = {
        { tag = "plain", id = 100, count = 1, status = 0 },
        { tag = "equipped", id = 100, count = 1, status = 5 },
      }

      logic.sort(bag, stack_of)

      assert.are.same({ "plain", "equipped" }, keys(bag))
    end)

    it("holds equal slots in the order the client listed them", function()
      -- table.sort is not stable, so slots that tie on every field could swap
      -- between two reads and make the grid twitch with nothing changed.
      local bag = {}
      for index = 1, 8 do
        bag[index] = { tag = "slot" .. index, id = 100, count = 4, status = 0 }
      end

      assert.are.same(keys(bag), keys(logic.sort(bag, stack_of)))
    end)

    it("keeps a bag in slot order when sorting is switched off", function()
      logic.set_config({ sort = false })
      local bag = {
        { tag = "plain", id = 100, count = 1, status = 0 },
        { tag = "equipped", id = 100, count = 1, status = 5 },
      }

      assert.are.same({ "plain", "equipped" }, keys(logic.sort(bag, stack_of)))
    end)
  end)
  describe("laying the blocks out", function()
    -- A 4px pitch carrying a 3px square, the reference addon's own geometry.
    local function grid_config(overrides)
      local config = {
        spacing = 4,
        block_spacing = 4,
        slot_size = 3,
        box_size = 2,
        align = "top",
        labels = { enabled = true, font_size = 6, gap = 1 },
        bags = {
          equipment = { enabled = false, columns = 4 },
          inventory = { enabled = true, columns = 5 },
          satchel = { enabled = true, columns = 5 },
          treasure = { enabled = true, columns = 1 },
        },
      }
      for key, value in pairs(overrides or {}) do
        config[key] = value
      end
      return config
    end

    local function keys(blocks)
      local out = {}
      for index, block in ipairs(blocks) do
        out[index] = block.key
      end
      return out
    end

    before_each(function()
      logic = new_logic(grid_config())
    end)

    it("draws only the bags switched on that hold slots", function()
      local blocks = logic.layout({ inventory = 80, satchel = 30, equipment = 16 }, 0, 0, 1)

      assert.are.same({ "inventory", "satchel" }, keys(blocks))
    end)

    it("skips a bag the client reports no slots for", function()
      -- A satchel the player has never bought answers a size of zero, and an
      -- empty treasure pool draws nothing rather than an empty column.
      local blocks = logic.layout({ inventory = 80, satchel = 0, treasure = 0 }, 0, 0, 1)

      assert.are.same({ "inventory" }, keys(blocks))
    end)

    it("wraps a bag into rows across its own column count", function()
      local blocks = logic.layout({ inventory = 80 }, 0, 0, 1)

      assert.are.equal(5, blocks[1].columns)
      assert.are.equal(80, blocks[1].slots)
      assert.are.equal(16, blocks[1].rows)
    end)

    it("gives a part-filled last row its own row", function()
      local blocks = logic.layout({ inventory = 12 }, 0, 0, 1)

      assert.are.equal(3, blocks[1].rows)
    end)

    it("puts one block's columns plus the block gap before the next", function()
      local blocks = logic.layout({ inventory = 80, satchel = 30 }, 100, 50, 1)

      assert.are.equal(100, blocks[1].x)
      -- 5 columns at a 4px pitch, then the 4px gap between blocks.
      assert.are.equal(124, blocks[2].x)
    end)

    it("runs slots left to right and then downward from the origin", function()
      local blocks = logic.layout({ inventory = 80 }, 100, 50, 1)
      local block = blocks[1]

      assert.are.same({ x = 100, y = 50 }, logic.slot_position(block, 1, 1))
      assert.are.same({ x = 116, y = 50 }, logic.slot_position(block, 5, 1))
      assert.are.same({ x = 100, y = 54 }, logic.slot_position(block, 6, 1))
    end)

    it("stands the blocks on a common foot by default", function()
      logic = new_logic(grid_config({ align = "bottom" }))
      local blocks = logic.layout({ inventory = 80, satchel = 10 }, 0, 0, 1)

      -- The satchel is 2 rows against the inventory's 16, so it starts 14
      -- rows down and the two blocks end level.
      assert.are.equal(0, blocks[1].y)
      assert.are.equal(56, blocks[2].y)
    end)

    it("hangs the blocks from a common top when told to", function()
      local blocks = logic.layout({ inventory = 80, satchel = 10 }, 0, 20, 1)

      assert.are.equal(20, blocks[1].y)
      assert.are.equal(20, blocks[2].y)
    end)

    it("scales the pitch, the gaps and the squares together", function()
      local blocks = logic.layout({ inventory = 80, satchel = 30 }, 100, 50, 2)

      assert.are.equal(148, blocks[2].x)
      assert.are.same({ x = 108, y = 58 }, logic.slot_position(blocks[1], 7, 2))
      assert.are.equal(6, logic.slot_size(2))
      assert.are.equal(4, logic.box_size(2))
    end)

    it("clamps a stored column count that could never be drawn", function()
      -- The command refuses one, but a hand-edited file, a //hud copy import
      -- or an older config can still carry it, and a block 500 columns wide is
      -- wider than any screen.
      logic = new_logic(grid_config({ bags = { inventory = { enabled = true, columns = 500 } } }))

      local blocks = logic.layout({ inventory = 80 }, 0, 0, 1)

      assert.is_true(blocks[1].columns <= 20)
    end)

    it("clamps a stored pitch narrower than the square it carries", function()
      logic = new_logic(grid_config({ spacing = 1 }))

      local blocks = logic.layout({ inventory = 80, satchel = 30 }, 0, 0, 1)

      -- A pitch under the slot size would stack every square on the last.
      assert.is_true(blocks[2].x >= blocks[1].columns * 3)
    end)

    it("clamps a stored block gap that would run the grid off screen", function()
      logic = new_logic(grid_config({ block_spacing = 5000 }))

      local blocks = logic.layout({ inventory = 80, satchel = 30 }, 0, 0, 1)

      assert.is_true(blocks[2].x <= blocks[1].columns * 4 + 64)
    end)

    it("names each block in a word short enough to fit under it", function()
      -- A 5-column block is 19px wide; at 6pt "inventory" is about 40.
      local blocks = logic.layout({ inventory = 80, satchel = 30, treasure = 2 }, 0, 0, 1)

      assert.are.equal("Inv", blocks[1].label)
      assert.are.equal("Sat", blocks[2].label)
      assert.are.equal("Pool", blocks[3].label)
    end)

    it("tells the eight wardrobes and the two safes apart by number", function()
      logic = new_logic(grid_config({
        bags = { safe = { enabled = true, columns = 5 }, wardrobe = { enabled = true, columns = 5 } },
      }))
      local names = {}
      for _, block in ipairs(logic.layout({ safe = 1, safe2 = 1, wardrobe = 1, wardrobe8 = 1 }, 0, 0, 1)) do
        names[block.key] = block.label
      end

      assert.are.equal("Safe", names.safe)
      assert.are.equal("Safe2", names.safe2)
      assert.are.equal("W1", names.wardrobe)
      assert.are.equal("W8", names.wardrobe8)
    end)

    it("puts the label just under the block's last row, at its left edge", function()
      logic = new_logic(grid_config({ align = "bottom" }))
      local blocks = logic.layout({ inventory = 80, satchel = 10 }, 100, 50, 1)

      -- 16 rows: the last square's foot is at 50 + 15*4 + 3 = 113, then the gap.
      assert.are.same({ x = 100, y = 114, size = 6 }, logic.label_position(blocks[1], 1))
      -- Bottom-aligned blocks share a foot, so their labels sit on one line.
      assert.are.equal(114, logic.label_position(blocks[2], 1).y)
    end)

    it("scales the label with the grid, in whole pixels", function()
      local blocks = logic.layout({ inventory = 80 }, 100, 50, 2)

      local at = logic.label_position(blocks[1], 2)
      assert.are.equal(12, at.size)
      assert.are.equal(50 + 15 * 8 + 6 + 2, at.y)
    end)

    it("holds the next block clear of a label wider than its own block", function()
      -- The temporary bag and the pool ship at ONE column, 4px wide, with
      -- "Temp" and "Pool" under them on the same line; nothing about the
      -- squares keeps the two names off each other.
      logic = new_logic(grid_config({
        bags = { temporary = { enabled = true, columns = 1 }, treasure = { enabled = true, columns = 1 } },
      }))
      local blocks = logic.layout({ temporary = 3, treasure = 2 }, 100, 50, 1)

      assert.is_true(blocks[2].x >= 100 + logic.label_width(blocks[1], 1) + 4, ("pool at %d"):format(blocks[2].x))
    end)

    it("leaves the block spacing alone where the label already fits", function()
      local blocks = logic.layout({ inventory = 80, satchel = 30 }, 100, 50, 1)

      assert.are.equal(124, blocks[2].x)
    end)

    it("bounds the last block's label as well as its squares", function()
      logic = new_logic(grid_config({ bags = { treasure = { enabled = true, columns = 1 } } }))

      local x, _, width = logic.bounds({ treasure = 2 }, 100, 50, 1)

      assert.is_true(x + width >= 100 + logic.label_width({ label = "Pool" }, 1))
    end)

    it("estimates a label's width from the font, like the sibling widgets", function()
      -- 4 characters at 6pt, at the 0.75 per-character ratio speedcheck
      -- settled on in a live client, doubled by the scale.
      assert.are.equal(4 * 6 * 0.75 * 2, logic.label_width({ label = "Pool" }, 2))
    end)

    it("grows the bounds to take the labels in", function()
      local _, _, _, bare = new_logic(grid_config({ labels = { enabled = false, font_size = 6, gap = 1 } })).bounds(
        { inventory = 80 },
        100,
        50,
        1
      )
      local _, _, _, labelled = logic.bounds({ inventory = 80 }, 100, 50, 1)

      assert.are.equal(63, bare)
      -- The 1px gap and a 6pt line box, ascender to descender.
      assert.are.equal(63 + 1 + 6 * 1.5, labelled)
    end)

    it("draws no label when they are switched off", function()
      logic = new_logic(grid_config({ labels = { enabled = false, font_size = 6, gap = 1 } }))

      assert.is_false(logic.labels_enabled())
    end)

    it("bounds the whole grid from the origin it was given", function()
      -- The squares alone; what the labels add is pinned separately above.
      logic = new_logic(grid_config({ labels = { enabled = false } }))
      local x, y, width, height = logic.bounds({ inventory = 80, satchel = 10 }, 100, 50, 1)

      assert.are.equal(100, x)
      assert.are.equal(50, y)
      -- Two blocks: 5 columns, the 4px block gap, 5 more columns, and the last
      -- square is 3 wide rather than a full 4px pitch.
      assert.are.equal(43, width)
      -- 16 rows: fifteen pitches and one square.
      assert.are.equal(63, height)
    end)

    it("bounds a grid with nothing in it at its origin, one square wide", function()
      -- Not zero: a widget with no bounds cannot be dragged or right-clicked
      -- in layout mode, and core has nothing to clamp it by.
      local x, y, width, height = logic.bounds({}, 100, 50, 1)

      assert.are.equal(100, x)
      assert.are.equal(50, y)
      assert.are.equal(logic.slot_size(1), width)
      assert.are.equal(logic.slot_size(1), height)
    end)
    it("keeps hold of a box to drag when every bag is switched off", function()
      -- A widget with no bounds cannot be dragged or right-clicked back on in
      -- layout mode, and core has nothing to clamp it by.
      logic = new_logic(grid_config({ bags = {} }))

      local x, y, width, height = logic.bounds({}, 100, 50, 1)

      assert.are.equal(100, x)
      assert.are.equal(50, y)
      assert.is_true(width > 0)
      assert.is_true(height > 0)
    end)
  end)
  describe("deciding when to read the client", function()
    -- 0x01D's Flag sits at the first byte of the packet body, which is byte 5
    -- of the chunk once the header is counted.
    local function finish(flag)
      return string.char(0x1D, 0, 0, 0, flag)
    end

    local function settle()
      logic.on_chunk(0x01D, finish(1))
    end

    before_each(function()
      logic = new_logic({})
      settle()
      logic.should_read()
    end)

    it("wants the packets that can move an item and no others", function()
      for _, id in ipairs({ 0x00A, 0x01C, 0x01D, 0x01E, 0x01F, 0x020, 0x050, 0x0D2, 0x0D3 }) do
        assert.is_true(logic.wants_chunk(id), ("expected to want %#05x"):format(id))
      end

      for _, id in ipairs({ 0x028, 0x063, 0x076, 0x0DD }) do
        assert.is_false(logic.wants_chunk(id), ("expected to ignore %#05x"):format(id))
      end
    end)

    it("reads once for a change and not again until the next one", function()
      logic.on_chunk(0x020, "raw")

      assert.is_true(logic.should_read())
      assert.is_false(logic.should_read())
    end)

    it("collapses a burst of changes into one read", function()
      logic.on_chunk(0x01F, "raw")
      logic.on_chunk(0x020, "raw")
      logic.on_item(4096)

      assert.is_true(logic.should_read())
      assert.is_false(logic.should_read())
    end)

    it("reads for an item entering or leaving a bag, but never for gil", function()
      logic.on_item(65535)
      assert.is_false(logic.should_read())

      logic.on_item(0)
      assert.is_false(logic.should_read())

      logic.on_item(4096)
      assert.is_true(logic.should_read())
    end)

    it("reads for a bag resize, an equip and a treasure drop", function()
      for _, id in ipairs({ 0x01C, 0x050, 0x0D2, 0x0D3 }) do
        logic.on_chunk(id, "raw")
        assert.is_true(logic.should_read(), ("expected a read after %#05x"):format(id))
      end
    end)

    it("reads when the job changes, which reshuffles what is worn", function()
      logic.on_job_change()

      assert.is_true(logic.should_read())
    end)

    it("holds every read while a zone's bags are still arriving", function()
      logic.on_chunk(0x00A, "raw")
      logic.on_chunk(0x01F, "raw")
      logic.on_chunk(0x020, "raw")

      assert.is_false(logic.should_read())
    end)

    it("reads once the last bag of the zone has finished", function()
      logic.on_chunk(0x00A, "raw")
      logic.on_chunk(0x01F, "raw")
      settle()

      assert.is_true(logic.should_read())
      assert.is_false(logic.should_read())
    end)

    it("keeps holding while single bags finish mid-load", function()
      -- Flag 0 is one bag done, not the lot; the reference read on every one
      -- of them, which is a full inventory push per bag on every zone.
      logic.on_chunk(0x00A, "raw")
      logic.on_chunk(0x01D, finish(0))

      assert.is_false(logic.should_read())
    end)

    it("does not re-read for a bag finishing once the load is done", function()
      logic.on_chunk(0x01D, finish(0))

      assert.is_false(logic.should_read())
    end)

    it("reads at every full settle, even one it was not waiting for", function()
      -- The component can be attached before the client has filled the bags
      -- in, and that first read comes back empty. The settle is what says
      -- there is something to see now.
      settle()

      assert.is_true(logic.should_read())
    end)

    it("gives up holding rather than freezing if the settle never comes", function()
      logic.on_chunk(0x00A, "raw")
      logic.on_chunk(0x020, "raw")

      for _ = 1, logic.hold_limit() - 1 do
        assert.is_false(logic.should_read())
      end

      assert.is_true(logic.should_read())
    end)

    it("stops holding for good once it has given up on the settle", function()
      -- The hold exists for a settle that never comes. Re-arming it would
      -- make every later change wait the full count again, which is not "one
      -- frame late" but ten seconds late for the rest of the session.
      logic.on_chunk(0x00A, "raw")
      logic.on_chunk(0x020, "raw")
      for _ = 1, logic.hold_limit() do
        logic.should_read()
      end

      logic.on_chunk(0x020, "raw")

      assert.is_true(logic.should_read())
    end)

    it("does not count out the hold with nothing waiting to be read", function()
      logic.on_chunk(0x00A, "raw")

      for _ = 1, logic.hold_limit() * 2 do
        assert.is_false(logic.should_read())
      end
    end)

    it("reads on the first tick after attaching", function()
      logic = new_logic({})
      logic.on_attach()

      assert.is_true(logic.should_read())
    end)

    it("forgets the character's inventory when they log out", function()
      logic.on_logout()
      logic.on_chunk(0x020, "raw")

      assert.is_false(logic.should_read())
    end)
  end)
  describe("the command parser", function()
    local function fresh()
      return new_logic({
        sort = true,
        spacing = 4,
        block_spacing = 4,
        slot_size = 3,
        box_size = 2,
        align = "bottom",
        labels = { enabled = true, font_size = 6, gap = 1 },
        bags = {
          equipment = { enabled = false, columns = 4 },
          inventory = { enabled = true, columns = 5 },
          safe = { enabled = false, columns = 5 },
          storage = { enabled = false, columns = 4 },
          locker = { enabled = false, columns = 5 },
          satchel = { enabled = true, columns = 5 },
          sack = { enabled = true, columns = 5 },
          case = { enabled = true, columns = 5 },
          wardrobe = { enabled = false, columns = 5 },
          temporary = { enabled = true, columns = 1 },
          treasure = { enabled = true, columns = 1 },
        },
      })
    end

    local function joined(message)
      if type(message) == "table" then
        return table.concat(message, "\n")
      end
      return message
    end

    before_each(function()
      logic = fresh()
    end)

    it("reports every bag and every setting when asked nothing", function()
      local message, changed = logic.command({})

      assert.is_false(changed)
      local text = joined(message)
      assert.is_truthy(text:find("sort on", 1, true))
      assert.is_truthy(text:find("align bottom", 1, true))
      assert.is_truthy(text:find("inventory", 1, true))
      assert.is_truthy(text:find("wardrobe", 1, true))
      assert.is_truthy(text:find("5 columns", 1, true))
    end)

    it("reports one bag's own state when it is named alone", function()
      local message, changed = logic.command({ "inventory" })

      assert.is_false(changed)
      local text = joined(message)
      assert.is_truthy(text:find("inventory", 1, true))
      assert.is_truthy(text:find("5 columns", 1, true))
    end)

    it("reports the pitch actually drawn, not a stored value it refused", function()
      -- The one place a player could see the clamp at work must not say the
      -- number the clamp threw away.
      logic = new_logic({ spacing = 1, slot_size = 3, block_spacing = 4, align = "bottom", bags = {} })

      local text = joined(logic.command({}))

      assert.is_truthy(text:find("spacing 3", 1, true))
      assert.is_nil(text:find("spacing 1", 1, true))
    end)

    it("switches one bag on and off", function()
      local message, changed = logic.command({ "wardrobe", "on" })

      assert.is_true(changed)
      assert.is_truthy(joined(message):find("wardrobe", 1, true))
      assert.is_true(logic.bag_setting("wardrobe").enabled)

      logic.command({ "wardrobe", "off" })
      assert.is_false(logic.bag_setting("wardrobe").enabled)
    end)

    it("takes a bag word in any case", function()
      logic.command({ "Wardrobe", "ON" })

      assert.is_true(logic.bag_setting("wardrobe").enabled)
    end)

    it("sets a bag's column count", function()
      local _, changed = logic.command({ "inventory", "columns", "8" })

      assert.is_true(changed)
      assert.are.equal(8, logic.bag_setting("inventory").columns)
    end)

    it("refuses a column count outside what can be drawn", function()
      local message, changed = logic.command({ "inventory", "columns", "0" })

      assert.is_false(changed)
      assert.is_truthy(joined(message):find("1", 1, true))
      assert.are.equal(5, logic.bag_setting("inventory").columns)

      logic.command({ "inventory", "columns", "far too many" })
      assert.are.equal(5, logic.bag_setting("inventory").columns)
    end)

    it("switches the sort", function()
      local _, changed = logic.command({ "sort", "off" })

      assert.is_true(changed)
      assert.is_false(logic.settings().sort)
    end)

    it("switches the labels", function()
      local _, changed = logic.command({ "labels", "off" })

      assert.is_true(changed)
      assert.is_false(logic.labels_enabled())
      assert.is_truthy(joined(logic.command({})):find("labels off", 1, true))
    end)

    it("sets the pitch and the gap between blocks", function()
      logic.command({ "spacing", "6" })
      logic.command({ "blockspacing", "10" })

      assert.are.equal(6, logic.settings().spacing)
      assert.are.equal(10, logic.settings().block_spacing)
    end)

    it("refuses a pitch smaller than the square it carries", function()
      -- A pitch under the slot size would draw the squares on top of one
      -- another, which reads as one solid block rather than a grid.
      local message, changed = logic.command({ "spacing", "1" })

      assert.is_false(changed)
      assert.is_truthy(joined(message):find("spacing", 1, true))
      assert.are.equal(4, logic.settings().spacing)
    end)

    it("aligns the blocks top or bottom", function()
      local _, changed = logic.command({ "align", "top" })

      assert.is_true(changed)
      assert.are.equal("top", logic.settings().align)
    end)

    it("refuses an alignment it cannot draw", function()
      local message, changed = logic.command({ "align", "middle" })

      assert.is_false(changed)
      assert.is_truthy(joined(message):find("top", 1, true))
      assert.are.equal("bottom", logic.settings().align)
    end)

    it("names the bags when the word is not one of them", function()
      local message, changed = logic.command({ "backpack", "on" })

      assert.is_false(changed)
      local text = joined(message)
      assert.is_truthy(text:find("backpack", 1, true))
      assert.is_truthy(text:find("satchel", 1, true))
    end)

    it("says what a bag takes when the rest of the line makes no sense", function()
      local message, changed = logic.command({ "inventory", "sideways" })

      assert.is_false(changed)
      assert.is_truthy(joined(message):find("columns", 1, true))
    end)

    it("says what it understands when the verb is unknown", function()
      local message, changed = logic.command({ "colour", "red" })

      assert.is_false(changed)
      assert.is_truthy(joined(message):find("sort", 1, true))
    end)
  end)
  describe("previewing in layout mode", function()
    before_each(function()
      logic = new_logic({
        spacing = 4,
        block_spacing = 4,
        slot_size = 3,
        box_size = 2,
        align = "bottom",
        bags = {
          inventory = { enabled = true, columns = 5 },
          satchel = { enabled = false, columns = 5 },
          treasure = { enabled = true, columns = 1 },
        },
      })
    end)

    it("fills every bag switched on to its usual capacity", function()
      logic.set_preview(true)
      local sizes = logic.preview_sizes()

      assert.are.equal(80, sizes.inventory)
      assert.are.equal(10, sizes.treasure)
    end)

    it("leaves a bag switched off out of the preview", function()
      -- Layout mode has to show the footprint the widget will really take,
      -- not one the player has not asked for.
      logic.set_preview(true)

      assert.is_nil(logic.preview_sizes().satchel)
    end)

    it("previews the real grid once the client has been read", function()
      -- Nominal capacities are a stand-in for a character that is not loaded.
      -- Preferring them to a real read would build prims for eight wardrobes
      -- nobody owns, and show a footprint the widget will never take.
      logic.set_preview(true)

      local sizes = logic.preview_sizes({ inventory = 30 })

      assert.are.equal(30, sizes.inventory)
      assert.is_nil(sizes.treasure)
    end)

    it("shows a mix of held and empty slots rather than one flat colour", function()
      local seen = {}
      for index = 1, 12 do
        seen[logic.preview_colour(index)] = true
      end

      assert.is_true(seen.default)
      assert.is_true(seen.empty)
    end)
  end)
  describe("reading the client's item table", function()
    local stacks = { [100] = 12 }
    local function stack_of(id)
      return stacks[id]
    end

    local function bag_of(...)
      local slots = {}
      for index, count in ipairs({ ... }) do
        slots[index] = { id = count > 0 and 100 or 0, count = count, status = 0 }
      end
      return slots
    end

    before_each(function()
      logic = new_logic({
        sort = false,
        bags = {
          equipment = { enabled = true, columns = 4 },
          inventory = { enabled = true, columns = 5 },
          satchel = { enabled = true, columns = 5 },
          temporary = { enabled = true, columns = 1 },
          treasure = { enabled = true, columns = 1 },
        },
      })
    end)

    it("takes a bag's capacity and enabled flag from the same read as its items", function()
      local read = logic.read({
        max_inventory = 30,
        enabled_inventory = true,
        inventory = bag_of(1, 0, 0),
        max_satchel = 80,
        enabled_satchel = false,
        satchel = {},
      }, stack_of)

      assert.are.equal(30, read.sizes.inventory)
      -- A satchel the character has not unlocked is not empty space to draw.
      assert.is_nil(read.sizes.satchel)
    end)

    it("colours every slot of a bag up to its capacity", function()
      local read = logic.read({
        max_inventory = 4,
        enabled_inventory = true,
        inventory = bag_of(12, 3),
      }, stack_of)

      assert.are.same({ "full_stack", "default", "empty", "empty" }, read.colours.inventory)
    end)

    it("draws the sixteen equipment slots in the equip viewer's arrangement", function()
      local read = logic.read({
        equipment = {
          main = 1,
          sub = 0,
          range = 0,
          ammo = 5,
          head = 0,
          neck = 0,
          left_ear = 0,
          right_ear = 0,
          body = 0,
          hands = 0,
          left_ring = 0,
          right_ring = 0,
          back = 0,
          waist = 0,
          legs = 0,
          feet = 3,
        },
      }, stack_of)

      assert.are.equal(16, read.sizes.equipment)
      assert.are.equal("equipment", read.colours.equipment[1])
      assert.are.equal("empty", read.colours.equipment[2])
      assert.are.equal("equipment", read.colours.equipment[4])
      assert.are.equal("equipment", read.colours.equipment[16])
    end)

    it("draws only what the temporary bag and the pool are holding", function()
      -- Neither has a capacity worth showing as free space: the pool is gone
      -- in five minutes and the temporary bag is a zone's worth of items.
      local read = logic.read({
        max_temporary = 10,
        enabled_temporary = true,
        temporary = bag_of(1, 1, 0, 0),
        treasure = { { id = 100, count = 1, status = 0 }, { id = 100, count = 1, status = 0 } },
      }, stack_of)

      assert.are.equal(2, read.sizes.temporary)
      assert.are.same({ "temp_item", "temp_item" }, read.colours.temporary)
      assert.are.equal(2, read.sizes.treasure)
      assert.are.same({ "temp_item", "temp_item" }, read.colours.treasure)
    end)

    it("leaves an empty pool out entirely", function()
      local read = logic.read({ treasure = {} }, stack_of)

      assert.is_nil(read.sizes.treasure)
    end)

    it("orders a bag before colouring it when sorting is on", function()
      logic.set_config({
        sort = true,
        bags = { inventory = { enabled = true, columns = 5 } },
      })

      local read = logic.read({
        max_inventory = 3,
        enabled_inventory = true,
        inventory = {
          { id = 100, count = 3, status = 0 },
          { id = 0, count = 0, status = 0 },
          { id = 100, count = 12, status = 0 },
        },
      }, stack_of)

      assert.are.same({ "full_stack", "default", "empty" }, read.colours.inventory)
    end)

    it("takes a bag's capacity and flag from the per-bag fields as well", function()
      -- The reference reads items.storage.max and items.safe.enabled for some
      -- bags and the top-level pair for others, so the client answers both
      -- shapes and neither alone can be relied on.
      local read = logic.read({
        inventory = { max = 4, enabled = true, bag_of(1, 1) },
      }, stack_of)

      assert.are.equal(4, read.sizes.inventory)
    end)

    it("draws a bag the client did not flag either way", function()
      -- A missing flag is not a refusal. Answering "no" to a question the
      -- client never answered is how a grid ends up blank with nothing to say
      -- why, and a bag that truly is not there answers a capacity of zero.
      local read = logic.read({
        max_inventory = 3,
        inventory = bag_of(1, 0, 0),
      }, stack_of)

      assert.are.equal(3, read.sizes.inventory)
    end)

    it("still refuses a bag the client flagged as switched off", function()
      local read = logic.read({
        max_satchel = 80,
        enabled_satchel = false,
        satchel = bag_of(1),
      }, stack_of)

      assert.is_nil(read.sizes.satchel)
    end)

    it("counts a pool entry the client sent without a count", function()
      local read = logic.read({ treasure = { { id = 100, status = 0 } } }, stack_of)

      assert.are.equal(1, read.sizes.treasure)
    end)

    it("survives a client read that came back with nothing in it", function()
      local read = logic.read(nil, stack_of)

      assert.are.same({}, read.sizes)
      assert.are.same({}, read.colours)
    end)

    it("draws a bag no longer than the slots the client actually sent", function()
      -- get_items can answer a capacity with the slots still arriving; a
      -- capacity is not a promise that the array behind it is filled in.
      local read = logic.read({
        max_inventory = 5,
        enabled_inventory = true,
        inventory = bag_of(1, 1),
      }, stack_of)

      assert.are.same({ "default", "default", "empty", "empty", "empty" }, read.colours.inventory)
    end)
  end)
end)
