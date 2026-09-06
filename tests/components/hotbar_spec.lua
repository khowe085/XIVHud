local new_hotbar = require("components/hotbar/hotbar")
local new_render = require("components/hotbar/render")
local fakes = require("tests/support/fakes")

local ANCHORS = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" }
local LCTRL = 29
local DIK_SLOT = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local LEFT_DOWN, LEFT_UP = 1, 2

local function resources()
  return {
    spells = {
      [1] = { id = 1, en = "Cure", type = "WhiteMagic", recast_id = 1, mp_cost = 8 },
      [4] = { id = 4, en = "Cure IV", type = "WhiteMagic", recast_id = 4, mp_cost = 88 },
      [261] = { id = 261, en = "Warp", type = "BlackMagic", recast_id = 261, mp_cost = 100 },
    },
    job_abilities = { [605] = { id = 605, en = "Provoke", recast_id = 5, tp_cost = 0 } },
    weapon_skills = {},
    skills = {},
    items = {},
    mounts = {},
    key_items = {},
    zones = {},
    statuses = { [0] = { en = "Idle" }, [1] = { en = "Engaged" } },
    bags = { [0] = { id = 0, en = "Inventory", equippable = true } },
  }
end

local function war_bindings()
  return {
    WAR = {
      sets = {
        [1] = { row = { [3] = { type = "ma", action = "Cure", target = "t" } } },
        [2] = {
          row = {
            [3] = { type = "ja", action = "Provoke", target = "me" },
            [10] = { type = "ma", action = "Cure IV", target = "t" },
          },
        },
        [3] = { row = { [1] = { type = "ma", action = "Cure", target = "t" } } },
      },
    },
  }
end

describe("hotbar", function()
  local env, ctx, prims, widget, store, config, service

  local function said()
    return table.concat(env.chat, "\n")
  end

  local function push(event, ...)
    if event == nil then
      service.tick()
    elseif event == "status" then
      service.on_status(...)
    elseif event == "job change" then
      service.on_job_change()
    end
    return widget.update(event, ...)
  end

  local function build_world(opts)
    opts = opts or {}
    env = {
      chat = {},
      commands = {},
      chat_open = false,
      suppressed = false,
      layout = false,
      user_visible = true,
      player = {
        id = 777,
        main_job = "WAR",
        main_job_id = 1,
        main_job_level = 99,
        sub_job = "NIN",
        sub_job_id = 13,
        vitals = { mp = 100, tp = 1000 },
        buffs = {},
        status = 1,
      },
      store_files = opts.store_files or war_bindings(),
      items = { [0] = { enabled = true } },
      now = 0,
      config_saves = 0,
    }
    prims = fakes.prims()
    ctx = {
      screen = function()
        return 1920, 1080
      end,
      say = function(lines)
        if type(lines) == "table" then
          for _, line in ipairs(lines) do
            env.chat[#env.chat + 1] = line
          end
        else
          env.chat[#env.chat + 1] = lines
        end
      end,
      chat_open = function()
        return env.chat_open
      end,
      suppressed = function()
        return env.suppressed
      end,
      layout_active = function()
        return env.layout
      end,
      component_visible = function()
        return env.user_visible
      end,
      new_image = prims.new_image,
      new_text = prims.new_text,
      asset = function(path)
        return "addon/" .. path
      end,
      send_command = function(command)
        env.commands[#env.commands + 1] = command
      end,
      get_player = function()
        return env.player
      end,
      get_mob_by_target = function()
        return { id = 99, distance = 4, model_size = 1 }
      end,
      get_spell_recasts = function()
        return {}
      end,
      get_ability_recasts = function()
        return {}
      end,
      get_spells = function()
        return { [1] = true, [4] = true }
      end,
      get_abilities = function()
        return { job_abilities = { 605 }, weapon_skills = {} }
      end,
      get_items = function(bag)
        return env.items[bag]
      end,
      get_equipment = function()
        return {}
      end,
      parse_packet = function(data)
        return type(data) == "table" and data or nil
      end,
      generation = function()
        return 1
      end,
      now = function()
        return env.now
      end,
      time = function()
        return 1000000
      end,
      file_exists = function()
        return false
      end,
      resources = resources(),
    }
    ctx.actions = fakes.action_service(ctx)
    service = ctx.actions
    store = {
      load = function(name)
        return env.store_files[name]
      end,
      save = function(name, value)
        env.store_files[name] = value
      end,
    }
    widget = new_hotbar(ctx)
    config = widget.defaults
    if opts.tune then
      opts.tune(config)
    end
    widget.attach(config, function()
      env.config_saves = env.config_saves + 1
    end, store)
    local render = new_render({ config = config })
    local pitch = render.row_pitch()
    for index, anchor in ipairs(ANCHORS) do
      widget.set_pos(100, 100 + (index - 1) * pitch, anchor)
      widget.set_scale(1, anchor)
    end
    widget.show()
    for index = 2, 8 do
      widget.hide("bar" .. index)
    end
  end

  -- The name text of a row's slot: each row's ten slots are ten texts of
  -- three, name first, built in row order the first time the row shows.
  local function texts_of_row(anchor)
    local index = 0
    for _, candidate in ipairs(ANCHORS) do
      if candidate == anchor then
        break
      end
      index = index + 1
    end
    return index
  end

  local function row_names(anchor)
    local names = {}
    local base = texts_of_row(anchor) * 31
    for slot = 1, 10 do
      local text = prims.texts[base + (slot - 1) * 3 + 1]
      names[slot] = text ~= nil and text.last.text or nil
    end
    return names
  end

  it("implements the contract as an eight-anchor widget with a store", function()
    build_world()
    assert.are.equal("hotbar", widget.name)
    assert.are.equal("hb", widget.alias)
    assert.is_true(widget.wants_store)
    assert.are.same(ANCHORS, widget.anchors())
    assert.is_function(widget.on_keyboard)
    assert.is_function(widget.on_mouse)
  end)

  it("answers bounds at the origin it was given, in the row's shape", function()
    build_world()
    local render = new_render({ config = config })
    local x, y, w, h = widget.get_bounds("bar2")
    local width, height = render.bounds(1)
    assert.are.same({ 100, 100 + render.row_pitch(), width, height }, { x, y, w, h })
    widget.set_scale(2, "bar2")
    local _, _, scaled_w, scaled_h = widget.get_bounds("bar2")
    assert.are.same({ width * 2, height * 2 }, { scaled_w, scaled_h })
    assert.is_nil(widget.get_bounds("bar9"))
  end)

  it("builds only the rows that are shown, and paints row 1 with the active set", function()
    build_world()
    push()
    assert.are.equal(31, #prims.texts, "one row: ten slots of three texts, and the set number")
    assert.are.equal(60, #prims.images)
    local names = row_names("bar1")
    assert.are.equal("Cure", names[3])
    assert.are.equal("", names[1])
    assert.are.equal("1", prims.texts[31].last.text, "the set number")
    assert.is_true(prims.texts[31].visible)
  end)

  it("locks rows 2-8 to their own sets and shows them on demand", function()
    build_world()
    push()
    widget.show("bar2")
    push()
    assert.are.equal(62, #prims.texts, "the second row was built on first show")
    local names = row_names("bar2")
    assert.are.equal("Provoke", names[3])
    assert.are.equal("Cure IV", names[10])
    assert.are.equal("2", prims.texts[62].last.text)
  end)

  it("moves row 1 with the active set", function()
    build_world()
    push()
    local reply = widget.handle_command({ "set", "2" })
    assert.are.equal("hotbar: set 2", reply)
    local names = row_names("bar1")
    assert.are.equal("Provoke", names[3])
    assert.are.equal("Cure IV", names[10])
    assert.are.equal("2", prims.texts[31].last.text)
  end)

  describe("keys", function()
    it("fires row 1's slot off the bare number row, and row 2's under CTRL", function()
      build_world()
      push()
      assert.is_true(widget.on_keyboard(DIK_SLOT[3], true, 0, false))
      assert.are.same({ 'input /ma "Cure" <t>' }, env.commands)
      assert.is_true(widget.on_keyboard(DIK_SLOT[3], false, 0, false))
      widget.on_keyboard(LCTRL, true, 0, false)
      widget.on_keyboard(DIK_SLOT[3], true, 0, false)
      assert.are.equal('input /ja "Provoke" <me>', env.commands[2], "row 2 need not be on screen")
    end)

    it("fires nothing before a job is scoped, and blocks nothing", function()
      build_world({ store_files = {} })
      env.player = nil
      widget.detach()
      widget.attach(config, function() end, store)
      widget.show()
      assert.is_false(widget.on_keyboard(DIK_SLOT[3], true, 0, false))
      assert.are.same({}, env.commands)
    end)

    it("hands the row back to the game while the chat box has focus, and when the user hid it", function()
      build_world()
      push()
      env.chat_open = true
      assert.is_false(widget.on_keyboard(DIK_SLOT[3], true, 0, false))
      env.chat_open = false
      env.user_visible = false
      widget.hide()
      assert.is_false(widget.on_keyboard(DIK_SLOT[3], true, 0, false))
      assert.are.same({}, env.commands)
    end)

    it("forgets a held modifier on focus loss", function()
      build_world()
      push()
      widget.on_keyboard(LCTRL, true, 0, false)
      push("lose focus")
      widget.on_keyboard(DIK_SLOT[3], true, 0, false)
      assert.are.same({ 'input /ma "Cure" <t>' }, env.commands, "row 1, not row 2")
    end)
  end)

  describe("the mouse", function()
    it("fires the slot under a left-click and swallows both edges", function()
      build_world()
      push()
      local render = new_render({ config = config })
      local x, y = render.slot_pos(1, 3)
      assert.is_true(widget.on_mouse(LEFT_DOWN, 100 + x + 5, 100 + y + 5, 0))
      assert.are.same({ 'input /ma "Cure" <t>' }, env.commands)
      assert.is_true(widget.on_mouse(LEFT_UP, 100 + x + 5, 100 + y + 5, 0))
      assert.is_false(widget.on_mouse(LEFT_DOWN, 5, 5, 0), "the gaps stay the game's")
    end)

    it("leaves the mouse to layout mode", function()
      build_world()
      push()
      widget.set_preview(true)
      local render = new_render({ config = config })
      local x, y = render.slot_pos(1, 3)
      assert.is_false(widget.on_mouse(LEFT_DOWN, 100 + x + 5, 100 + y + 5, 0))
    end)
  end)

  describe("commands", function()
    it("lists every row bare, and one row by name", function()
      build_world()
      push()
      local lines = widget.handle_command({})
      assert.are.equal("hotbar: WAR/NIN - set 1 (sheathed)", lines[1])
      assert.are.equal("  bar1: on, 10x1, set 1 (active)", lines[2])
      assert.are.equal("  bar2: off, 10x1, set 2", lines[3])
      assert.are.equal(9, #lines)
      lines = widget.handle_command({ "bar3" })
      assert.are.equal(2, #lines)
      assert.are.equal("  bar3: off, 10x1, set 3", lines[2])
      widget.hide()
      lines = widget.handle_command({ "bar1" })
      assert.are.equal("  bar1: off, 10x1, set 1 (active)", lines[2], "the widget's own switch counts")
    end)

    it("reshapes a row with rows <n>, saving and re-laying the same prims", function()
      build_world()
      push()
      local before = #prims.images
      local reply = widget.handle_command({ "bar1", "rows", "2" })
      assert.are.equal("hotbar: bar1 now draws 2 rows (5x2)", reply)
      assert.are.equal(2, config.bars.bar1.rows)
      assert.are.equal(1, env.config_saves)
      assert.are.equal(before, #prims.images, "no prim was rebuilt")
      local render = new_render({ config = config })
      local _, _, w, h = widget.get_bounds("bar1")
      assert.are.same({ render.bounds(2) }, { w, h })
      local x, y = render.slot_pos(2, 6)
      assert.are.same({ 100 + x, 100 + y }, { prims.images[(6 - 1) * 6 + 1].x, prims.images[(6 - 1) * 6 + 1].y })
      reply = widget.handle_command({ "rows", "3" })
      assert.is_not_nil(reply:find("rows <1|2|5|10>", 1, true), reply)
      assert.are.equal(
        "hotbar: bar1 now draws 10 rows (1x10)",
        widget.handle_command({ "rows", "10" }),
        "bar1 when no row is named"
      )
    end)

    it("passes the common roster to the bar, and refuses a row word in front of it", function()
      build_world()
      push()
      local reply = widget.handle_command({ "bind", "2:5", "ma", "Cure", "t" })
      assert.is_not_nil(reply:find("^hotbar: bound 2:5"), reply)
      assert.are.same({ type = "ma", action = "Cure", target = "t" }, env.store_files.WAR.sets[2].row[5])
      reply = widget.handle_command({ "bar2", "bind", "2:6", "ma", "Cure", "t" })
      assert.is_not_nil(reply:find("takes no row word", 1, true), reply)
      assert.is_nil(env.store_files.WAR.sets[2].row[6])
      reply = widget.handle_command({ "warp" })
      assert.is_not_nil(reply:find("unknown command 'warp'", 1, true), reply)
    end)

    it("fires nothing by click or key while the OTHER bar's binder is open", function()
      build_world()
      push()
      service.set_edit_mode("crossbar", true)
      local render = new_render({ config = config })
      local x, y = render.slot_pos(1, 3)
      assert.is_false(widget.on_mouse(LEFT_DOWN, 100 + x + 5, 100 + y + 5, 0), "the click is the binder's")
      assert.is_false(widget.on_keyboard(DIK_SLOT[3], true, 0, false))
      assert.are.same({}, env.commands)
      service.set_edit_mode("crossbar", false)
      assert.is_true(widget.on_mouse(LEFT_DOWN, 100 + x + 5, 100 + y + 5, 0))
      assert.are.equal(1, #env.commands)
    end)

    it("opens edit mode and routes the mouse to the binder", function()
      build_world()
      push()
      local reply = widget.handle_command({ "edit" })
      assert.is_not_nil(reply:find("edit mode on", 1, true), reply)
      local render = new_render({ config = config })
      local x, y = render.slot_pos(1, 3)
      widget.on_mouse(LEFT_DOWN, 100 + x + 5, 100 + y + 5, 0)
      assert.are.same({}, env.commands, "a click in edit mode selects, never fires")
      widget.handle_command({ "edit" })
      widget.on_mouse(LEFT_DOWN, 100 + x + 5, 100 + y + 5, 0)
      assert.are.equal(1, #env.commands)
    end)
  end)

  describe("visibility", function()
    it("takes a row down and brings it back without rebuilding it", function()
      build_world()
      push()
      widget.hide("bar1")
      assert.is_false(prims.texts[31].visible)
      assert.is_false(prims.images[1].visible)
      widget.show("bar1")
      assert.is_true(prims.texts[31].visible)
      assert.are.equal(31, #prims.texts)
    end)

    it("drops a countdown when suppression hides the whole widget", function()
      build_world()
      push()
      env.suppressed = true
      -- A BLM who knows Warp: the spell rung, which counts down.
      env.player.main_job_id = 4
      env.player.vitals.mp = 200
      ctx.get_spells = function()
        return { [261] = true }
      end
      service.warp(false)
      assert.is_true(service.travel.armed())
      widget.hide()
      assert.is_false(service.travel.armed())
      assert.is_not_nil(said():find("cancelled", 1, true), said())
    end)

    it("draws nothing after a detach, and everything again after a re-attach", function()
      build_world()
      push()
      widget.detach()
      assert.is_false(prims.images[1].visible)
      widget.attach(config, function() end, store)
      widget.show()
      push()
      assert.is_true(prims.images[(3 - 1) * 6 + 1].visible, "slot 3's background is back")
      assert.is_true(prims.texts[(3 - 1) * 3 + 1].visible, "and its name")
    end)
  end)

  it("lists its own rows verb in help", function()
    build_world()
    push()
    local help = widget.handle_command({ "help" })
    local found = false
    for _, line in ipairs(help) do
      if line:find("//hud hotbar [<bar>] rows <1|2|5|10>", 1, true) then
        found = true
      end
    end
    assert.is_true(found, table.concat(help, "\n"))
  end)

  it("tears down the rows layout mode built once the preview ends, in core's order", function()
    build_world()
    push()
    -- Core's apply: the preview flag, the bare show, then each anchor.
    widget.set_preview(true)
    widget.show()
    push()
    assert.are.equal(8 * 31, #prims.texts, "every row was built for the drag")
    widget.set_preview(false)
    widget.show()
    for index = 2, 8 do
      widget.hide("bar" .. index)
    end
    push()
    local alive = 0
    for _, prim in ipairs(prims.texts) do
      if prim.destroyed == 0 then
        alive = alive + 1
      end
    end
    assert.are.equal(31, alive, "only row 1 stays resident")
    push()
    assert.is_true(prims.texts[31].visible, "and it still draws")
  end)

  it("destroys every prim it built", function()
    build_world()
    push()
    widget.show("bar2")
    push()
    widget.destroy()
    for _, prim in ipairs(prims.all) do
      assert.are.equal(1, prim.destroyed)
    end
  end)
end)
