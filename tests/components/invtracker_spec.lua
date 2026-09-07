local fakes = require("tests/support/fakes")
local new_invtracker = require("components/invtracker/invtracker")

describe("invtracker widget", function()
  local widget, prims, assets, items, saves, resources

  -- 0x01D with Flag 1: every bag has finished arriving.
  local SETTLED = string.char(0x1D, 0, 0, 0, 1)

  local function bag(count, held)
    local slots = {}
    for index = 1, count do
      local amount = index <= (held or 0) and 1 or 0
      slots[index] = { id = amount > 0 and 100 or 0, count = amount, status = 0 }
    end
    return slots
  end

  local function build(overrides)
    local ctx = {
      new_image = prims.new_image,
      new_text = prims.new_text,
      screen = function()
        return 1920, 1080
      end,
      asset = function(file)
        assets[#assets + 1] = file
        return "addons/XIVHud/" .. file
      end,
      get_items = function()
        items.reads = items.reads + 1
        return items.table
      end,
      resources = resources,
    }
    for key, value in pairs(overrides or {}) do
      ctx[key] = value
    end
    return new_invtracker(ctx)
  end

  -- The framework's own sequence: attach, place, then show.
  local function attach(config)
    local merged = {}
    for key, value in pairs(widget.defaults) do
      merged[key] = value
    end
    merged.layout = nil
    for key, value in pairs(config or {}) do
      merged[key] = value
    end
    widget.attach(merged, function()
      saves = saves + 1
    end)
    widget.set_pos(100, 50)
    widget.set_scale(1)
    widget.show()
    return merged
  end

  local function tick()
    widget.update()
  end

  local function drawn()
    local count = 0
    for _, prim in ipairs(prims.images) do
      if prim.visible then
        count = count + 1
      end
    end
    return count
  end

  before_each(function()
    prims = fakes.prims()
    assets = {}
    saves = 0
    resources = { items = { [100] = { stack = 12 } } }
    items = {
      reads = 0,
      table = {
        max_inventory = 10,
        enabled_inventory = true,
        inventory = bag(10, 4),
        equipment = {
          main = 1,
          sub = 0,
          range = 0,
          ammo = 0,
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
          feet = 0,
        },
        treasure = {},
      },
    }
    widget = build()
  end)

  describe("the widget contract", function()
    it("registers under its own name and short alias", function()
      assert.are.equal("invtracker", widget.name)
      assert.are.equal("inv", widget.alias)
    end)

    it("ships a placement for the framework to seed a layout slot with", function()
      assert.is_truthy(widget.defaults.layout.pos.x)
      assert.is_truthy(widget.defaults.layout.pos.y)
      assert.are.equal(1, widget.defaults.layout.scale)
      assert.is_true(widget.defaults.layout.visible)
    end)

    it("holds the whole grid on screen at its default placement", function()
      local layout = widget.defaults.layout
      attach()
      widget.set_pos(layout.pos.x, layout.pos.y)
      tick()

      local x, y, width, height = widget.get_bounds()

      assert.is_true(x >= 0 and y >= 0)
      assert.is_true(x + width <= 1920)
      assert.is_true(y + height <= 1080)
    end)

    it("builds no prims before a character is attached", function()
      assert.are.equal(0, #prims.images)
    end)

    it("hands back the origin it was given", function()
      attach()
      tick()

      local x, y = widget.get_bounds()

      assert.are.equal(100, x)
      assert.are.equal(50, y)
    end)

    it("bounds itself before it has ever read the client", function()
      -- Layout mode has to have something to drag from the first frame.
      attach()

      local x, y, width, height = widget.get_bounds()

      assert.are.equal(100, x)
      assert.are.equal(50, y)
      assert.is_number(width)
      assert.is_number(height)
    end)
  end)

  describe("drawing the grid", function()
    it("draws a square and its shadow for every slot of an enabled bag", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      assert.are.equal(20, drawn())
    end)

    it("paints held, full and empty slots in their own colours", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      items.table.inventory[1] = { id = 100, count = 12, status = 0 }
      tick()

      local colours = {}
      for _, prim in ipairs(prims.images) do
        if prim.visible then
          colours[table.concat(prim.last.color, ",")] = true
        end
      end

      -- The full stack, the part stacks and the empty slots cannot all be
      -- the same colour, or the grid says nothing.
      local distinct = 0
      for _ in pairs(colours) do
        distinct = distinct + 1
      end
      assert.is_true(distinct >= 3)
    end)

    it("reuses the same prims on the next read rather than building more", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local built = #prims.images

      widget.update("chunk", 0x020, "raw")
      tick()

      assert.are.equal(built, #prims.images)
    end)

    it("builds nothing for a bag that is switched off", function()
      attach({ bags = { inventory = { enabled = false, columns = 5 } } })
      tick()

      assert.are.equal(0, #prims.images)
    end)

    it("hides the squares of a bag switched off after it was drawn", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      assert.are.equal(20, drawn())

      widget.handle_command({ "inventory", "off" })

      assert.are.equal(0, drawn())
    end)

    it("hides the surplus rather than destroying it when a bag shrinks", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local built = #prims.images

      items.table.max_inventory = 5
      items.table.inventory = bag(5, 2)
      widget.update("chunk", 0x020, "raw")
      tick()

      assert.are.equal(built, #prims.images)
      assert.are.equal(10, drawn())
    end)

    it("does not repaint for a placement it is already at", function()
      --[[ Layout mode calls core's apply on every mouse-move event, and apply
           pushes scale, position, preview and show together - so guarding the
           position alone still leaves two full repaints per event, against a
           widget that draws hundreds of squares. ]]
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local before = 0
      for _, prim in ipairs(prims.images) do
        before = before + #prim.calls
      end

      widget.set_scale(1)
      widget.set_pos(100, 50)
      widget.set_preview(false)
      widget.show()

      local after = 0
      for _, prim in ipairs(prims.images) do
        after = after + #prim.calls
      end
      assert.are.equal(before, after)
    end)

    it("does not repaint when it is put back where it already was", function()
      --[[ Layout mode pushes a placement on every drag event, and core pushes
           scale, then position, then position again after clamping. A full
           repaint here is every prim in the grid rewritten several times a
           mouse-move, against a widget that draws hundreds of them. ]]
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local before = 0
      for _, prim in ipairs(prims.images) do
        before = before + #prim.calls
      end

      widget.set_pos(100, 50)
      widget.set_scale(1)

      local after = 0
      for _, prim in ipairs(prims.images) do
        after = after + #prim.calls
      end
      assert.are.equal(before, after)
    end)

    --[[ The grid flickered in a live client (Kevin, 2026-09-06). Every
         repaint used to hide every square and show it again as it was
         placed, and every read repainted - so a GearSwap burst, which is
         one 0x050 per slot swapped, blinked the whole grid. A square now
         remembers what it last drew and is pushed only what changed. ]]
    local function calls_on(list)
      local count = 0
      for _, prim in ipairs(list) do
        count = count + #prim.calls
      end
      return count
    end

    local function calls_named(list, name)
      local count = 0
      for _, prim in ipairs(list) do
        for _, call in ipairs(prim.calls) do
          if call.name == name then
            count = count + 1
          end
        end
      end
      return count
    end

    it("pushes nothing for a read that changed nothing", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local before = calls_on(prims.images) + calls_on(prims.texts)

      widget.update("chunk", 0x020, "raw")
      tick()

      assert.are.equal(2, items.reads, "the client was read again")
      assert.are.equal(before, calls_on(prims.images) + calls_on(prims.texts))
    end)

    it("never hides a square that stays on screen across a repaint", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local hides = calls_named(prims.images, "hide")

      widget.set_pos(300, 200)
      widget.update("chunk", 0x020, "raw")
      tick()

      assert.are.equal(hides, calls_named(prims.images, "hide"))
      assert.are.equal(20, drawn(), "and every square is still up")
    end)

    it("repaints only the squares whose colour moved", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local colours = calls_named(prims.images, "color")

      items.table.inventory = bag(10, 5)
      widget.update("add item", 100)
      tick()

      -- One slot went from empty to held: its box and its shadow.
      assert.are.equal(colours + 2, calls_named(prims.images, "color"))
    end)

    it("takes down a bag dropped by a re-attach that had no detach before it", function()
      --[[ `//hud slot`, `//hud reset` and `//hud copy` re-attach a live,
           shown widget without detaching it first. The squares of a bag
           the new config does not draw were stranded on screen for the
           session by the first diffing render (caught in review). ]]
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      assert.are.equal(20, drawn())

      attach({ bags = { inventory = { enabled = false, columns = 5 } } })
      tick()

      assert.are.equal(0, drawn(), "the dropped bag's squares came down")
      widget.hide()
      assert.are.equal(0, drawn())
    end)

    it("re-pushes every colour and style on a re-attach, keeping what is up", function()
      -- The new config's palette may differ; the squares still on screen
      -- take it without being blinked.
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local colours = calls_named(prims.images, "color")
      local hides = calls_named(prims.images, "hide")
      local fonts = calls_named(prims.texts, "font")

      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      -- Ten slots: ten boxes and ten shadows, one colour push apiece.
      assert.are.equal(colours + 20, calls_named(prims.images, "color"), "every box and shadow repainted")
      assert.are.equal(hides, calls_named(prims.images, "hide"), "and none was hidden to do it")
      assert.are.equal(fonts + 1, calls_named(prims.texts, "font"), "the label restyled once")
      assert.are.equal(20, drawn())
    end)

    it("styles a label once rather than on every repaint", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local fonts = calls_named(prims.texts, "font")

      widget.set_pos(300, 200)
      widget.update("chunk", 0x020, "raw")
      tick()

      assert.are.equal(fonts, calls_named(prims.texts, "font"))
    end)

    it("repaints when it is actually moved", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      widget.set_pos(300, 200)

      assert.are.equal(300, prims.images[1].x)
    end)

    it("draws nothing at all while hidden", function()
      attach()
      tick()
      widget.hide()

      assert.are.equal(0, drawn())
    end)

    it("comes back at the same size after being hidden and shown", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      local before = drawn()

      widget.hide()
      widget.show()

      assert.are.equal(before, drawn())
    end)

    it("does not build prims while it is hidden", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      widget.hide()
      tick()

      assert.are.equal(0, #prims.images)
    end)
  end)

  describe("the labels", function()
    local function shown_labels()
      local out = {}
      for _, prim in ipairs(prims.texts) do
        if prim.visible then
          out[#out + 1] = prim.last.text
        end
      end
      table.sort(out)
      return out
    end

    it("names each drawn block once, in a 6pt font", function()
      attach({
        bags = {
          inventory = { enabled = true, columns = 5 },
          equipment = { enabled = true, columns = 4 },
        },
      })
      tick()

      assert.are.same({ "Equip", "Inv" }, shown_labels())
      assert.are.equal(6, prims.texts[1].font_size)
    end)

    it("sits each label under its own block", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      local label = prims.texts[1]
      assert.are.equal(100, label.x)
      -- The inventory is two rows of five: 50 + 4 + 3, then the 1px gap.
      assert.are.equal(58, label.y)
    end)

    it("hides the labels when they are switched off, and brings them back", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      assert.are.same({ "Inv" }, shown_labels())

      widget.handle_command({ "labels", "off" })
      assert.are.same({}, shown_labels())

      widget.handle_command({ "labels", "on" })
      assert.are.same({ "Inv" }, shown_labels())
    end)

    it("hides a label with the block it named", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      widget.hide()

      assert.are.same({}, shown_labels())
    end)

    it("draws no label for a bag the client says it has none of", function()
      attach({
        bags = {
          inventory = { enabled = true, columns = 5 },
          satchel = { enabled = true, columns = 5 },
        },
      })
      tick()

      assert.are.same({ "Inv" }, shown_labels())
    end)

    it("disposes the labels with the squares", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      widget.destroy()

      assert.is_true(#prims.texts > 0)
      for _, prim in ipairs(prims.texts) do
        assert.are.equal(1, prim.destroyed)
      end
    end)
  end)

  describe("reading the client", function()
    it("reads on the tick rather than the moment a packet lands", function()
      attach()
      widget.update("chunk", 0x020, "raw")

      assert.are.equal(0, items.reads)
    end)

    it("reads on the first tick after attaching", function()
      attach()
      tick()

      assert.are.equal(1, items.reads)
    end)

    it("does not read again with nothing to read for", function()
      attach()
      tick()
      tick()
      tick()

      assert.are.equal(1, items.reads)
    end)

    it("reads once for a change however many packets announced it", function()
      attach()
      tick()

      widget.update("chunk", 0x01F, "raw")
      widget.update("chunk", 0x020, "raw")
      widget.update("add item", 4096)
      tick()

      assert.are.equal(2, items.reads)
    end)

    it("holds its reads through a zone until the bags have arrived", function()
      attach()
      tick()

      widget.update("chunk", 0x00A, "raw")
      widget.update("chunk", 0x01F, "raw")
      tick()
      assert.are.equal(1, items.reads)

      widget.update("chunk", 0x01D, SETTLED)
      tick()
      assert.are.equal(2, items.reads)
    end)

    it("ignores a packet it has no use for", function()
      attach()
      tick()

      widget.update("chunk", 0x028, "raw")
      tick()

      assert.are.equal(1, items.reads)
    end)

    it("reads again when the job changes what is worn", function()
      attach()
      tick()

      widget.update("job change", 5, 99, 1, 49)
      tick()

      assert.are.equal(2, items.reads)
    end)

    it("stops reading and clears the grid when the character logs out", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      widget.detach()
      assert.are.equal(0, drawn())

      widget.update("chunk", 0x020, "raw")
      tick()
      assert.are.equal(1, items.reads)
    end)

    it("draws on without the resources library, losing only the full stack", function()
      widget = build({ resources = nil })
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      items.table.inventory[1] = { id = 100, count = 12, status = 0 }
      tick()

      assert.are.equal(20, drawn())
    end)

    it("survives a read that came back with nothing in it", function()
      attach()
      items.table = nil
      widget.update("chunk", 0x020, "raw")
      tick()

      assert.are.equal(0, drawn())
    end)
  end)

  describe("layout mode", function()
    it("draws a grid to drag with no character loaded", function()
      attach()
      widget.set_preview(true)

      assert.is_true(drawn() > 0)
      assert.are.equal(0, items.reads)
    end)

    it("goes back to the client's own bags when the preview ends", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()
      widget.set_preview(true)
      widget.set_preview(false)

      assert.are.equal(20, drawn())
    end)

    it("moves and scales with the framework", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      widget.set_pos(300, 200)
      widget.set_scale(2)

      local x, y, width, height = widget.get_bounds()
      assert.are.equal(300, x)
      assert.are.equal(200, y)

      widget.set_scale(1)
      local _, _, narrow, short = widget.get_bounds()
      assert.is_true(width > narrow and height > short)
    end)
  end)

  describe("commands", function()
    it("reports its settings without changing anything", function()
      attach()
      local message = widget.handle_command({})

      assert.is_table(message)
      assert.are.equal(0, saves)
    end)

    it("persists a change and repaints without re-reading the client", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      local message = widget.handle_command({ "inventory", "columns", "10" })

      assert.is_truthy(message)
      assert.are.equal(1, saves)
      assert.are.equal(1, items.reads)
      assert.are.equal(20, drawn())
    end)

    it("shows a bag the moment it is switched on", function()
      -- Whether a bag is drawn at all is decided at the READ, so a repaint
      -- alone leaves a bag just switched on invisible until some unrelated
      -- packet happens to arrive - minutes, in a quiet zone.
      attach({
        bags = {
          inventory = { enabled = true, columns = 5 },
          satchel = { enabled = false, columns = 5 },
        },
      })
      items.table.max_satchel = 10
      items.table.enabled_satchel = true
      items.table.satchel = bag(10, 2)
      tick()
      assert.are.equal(20, drawn())

      widget.handle_command({ "satchel", "on" })
      tick()

      assert.are.equal(40, drawn())
    end)

    it("re-orders the squares the moment the sort is switched off", function()
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      widget.handle_command({ "sort", "off" })
      tick()

      assert.are.equal(2, items.reads)
    end)

    it("does not re-read the client for a setting the read has no part in", function()
      -- Which bags are drawn and how they are ordered are decided at the read;
      -- the labels, the columns and the spacing are not, and a read is a full
      -- get_items push.
      attach({ bags = { inventory = { enabled = true, columns = 5 } } })
      tick()

      widget.handle_command({ "labels", "off" })
      widget.handle_command({ "inventory", "columns", "10" })
      widget.handle_command({ "spacing", "6" })
      tick()

      assert.are.equal(1, items.reads)
    end)

    it("does not persist a command it refused", function()
      attach()
      widget.handle_command({ "inventory", "columns", "nonsense" })

      assert.are.equal(0, saves)
    end)
  end)

  it("disposes every prim it built", function()
    attach({ bags = { inventory = { enabled = true, columns = 5 } } })
    tick()

    widget.destroy()

    for _, prim in ipairs(prims.images) do
      assert.are.equal(1, prim.destroyed)
    end
  end)
end)
