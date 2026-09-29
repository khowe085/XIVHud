local new_crossbar = require("components/crossbar/crossbar")
local new_hotbar = require("components/hotbar/hotbar")
local crossbar_render = require("components/crossbar/render")
local hotbar_render = require("components/hotbar/render")
local fakes = require("tests/support/fakes")

--[[ The two action bars TOGETHER: both real widgets over one action service,
     registered and dispatched to in the entry point's order - the crossbar
     first. Each has a spec of its own for what it does alone; this is for
     what neither can show by itself, a slot leaving one bar and landing on
     the other. ]]

local MOVE, LEFT_DOWN, LEFT_UP = 0, 1, 2

local HOTBAR_ANCHORS = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" }
local CROSS_X, CROSS_Y = 100, 900
local HOT_X, HOT_Y = 100, 100

local PROVOKE = { type = "ja", action = "Provoke", target = "me" }
local CURE = { type = "ma", action = "Cure", target = "t" }

local function resources()
  return {
    spells = { [1] = { id = 1, en = "Cure", type = "WhiteMagic", recast_id = 1, mp_cost = 8 } },
    job_abilities = { [605] = { id = 605, en = "Provoke", recast_id = 5, tp_cost = 0 } },
    weapon_skills = {},
    skills = {},
    items = {},
    mounts = {},
    key_items = {},
    statuses = { [0] = { en = "Idle" }, [1] = { en = "Engaged" } },
    bags = { [0] = { id = 0, en = "Inventory", equippable = true } },
  }
end

describe("the crossbar and the hotbar together", function()
  local env, crossbar, hotbar, service

  local function store_over(files)
    return {
      load = function(name)
        return files[name]
      end,
      save = function(name, value)
        files[name] = value
      end,
    }
  end

  local function tick()
    service.tick()
    crossbar.update()
    hotbar.update()
  end

  -- Core's own dispatch: every component hears every event, in
  -- registration order, and the answers are ORed.
  local function mouse(kind, x, y)
    local first = crossbar.on_mouse(kind, x, y, 0)
    local second = hotbar.on_mouse(kind, x, y, 0)
    return first or second
  end

  local function drag(from_x, from_y, to_x, to_y)
    mouse(LEFT_DOWN, from_x, from_y)
    mouse(MOVE, to_x, to_y)
    return mouse(LEFT_UP, to_x, to_y)
  end

  local function crossbar_slot(side, slot)
    local render = crossbar_render({ config = crossbar.defaults })
    local x, y = render.slot_pos("xhb", side, slot)
    local size = render.metrics().slot
    return CROSS_X + x + size / 2, CROSS_Y + y + size / 2
  end

  local function hotbar_slot(slot)
    local render = hotbar_render({ config = hotbar.defaults })
    local x, y = render.slot_pos(1, slot)
    return HOT_X + x + render.slot_size() / 2, HOT_Y + y + render.slot_size() / 2
  end

  before_each(function()
    env = {
      chat = {},
      commands = {},
      now = 0,
      player = {
        id = 777,
        main_job = "WAR",
        main_job_id = 1,
        main_job_level = 99,
        sub_job = "NIN",
        sub_job_id = 13,
        vitals = { mp = 100, tp = 1000 },
        buffs = {},
        status = 0,
      },
      crossbar_files = { WAR = { sets = { [1] = { left = { [3] = PROVOKE } } } } },
      hotbar_files = { WAR = { sets = { [1] = { row = { [7] = CURE } } } } },
    }
    local prims = fakes.prims()
    env.prims = prims
    local ctx = {
      screen = function()
        return 1920, 1080
      end,
      say = function(lines)
        for _, line in ipairs(type(lines) == "table" and lines or { lines }) do
          env.chat[#env.chat + 1] = line
        end
      end,
      chat_open = function()
        return false
      end,
      suppressed = function()
        return false
      end,
      layout_active = function()
        return false
      end,
      component_visible = function()
        return true
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
        return nil
      end,
      get_spell_recasts = function()
        return {}
      end,
      get_ability_recasts = function()
        return {}
      end,
      get_key_items = function()
        return {}
      end,
      get_spells = function()
        return { [1] = true }
      end,
      get_abilities = function()
        return { job_abilities = { 605 }, weapon_skills = {} }
      end,
      get_items = function()
        return { enabled = true }
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
    crossbar = new_crossbar(ctx)
    hotbar = new_hotbar(ctx)

    crossbar.attach(crossbar.defaults, function() end, store_over(env.crossbar_files))
    local render = crossbar_render({ config = crossbar.defaults })
    local label_x, label_y = render.set_label_pos()
    local sword_x, sword_y = render.set_icon_pos()
    for anchor, at in pairs({
      main = { CROSS_X, CROSS_Y },
      set = { CROSS_X + label_x, CROSS_Y + label_y },
      weapon = { CROSS_X + sword_x, CROSS_Y + sword_y },
    }) do
      crossbar.set_pos(at[1], at[2], anchor)
      crossbar.set_scale(1, anchor)
    end
    crossbar.show()

    hotbar.attach(hotbar.defaults, function() end, store_over(env.hotbar_files))
    local pitch = hotbar_render({ config = hotbar.defaults }).row_pitch()
    for index, anchor in ipairs(HOTBAR_ANCHORS) do
      hotbar.set_pos(HOT_X, HOT_Y + (index - 1) * pitch, anchor)
      hotbar.set_scale(1, anchor)
    end
    hotbar.show()
    for index = 2, 8 do
      hotbar.hide("bar" .. index)
    end
    tick()
  end)

  it("opens both binders from either bar's command and closes both from the other's", function()
    local reply = crossbar.handle_command({ "edit" })
    assert.is_not_nil(reply:find("^crossbar: edit mode on, hotbar too"), reply)
    local x, y = hotbar_slot(7)
    assert.is_true(mouse(LEFT_DOWN, x, y), "a press on the hotbar is its binder's now")
    assert.are.same({}, env.commands, "and fires nothing")
    mouse(LEFT_UP, x, y)
    assert.are.equal("hotbar: edit mode off", hotbar.handle_command({ "edit" }))
    assert.is_nil(service.edit_owner())
    mouse(LEFT_DOWN, crossbar_slot("left", 3))
    assert.are.equal(1, #env.commands, "the crossbar is live again: its binder closed with the hotbar's")
  end)

  it("drags a slot off the crossbar onto the hotbar", function()
    crossbar.handle_command({ "edit" })
    local from_x, from_y = crossbar_slot("left", 3)
    assert.is_true(drag(from_x, from_y, hotbar_slot(7)))
    assert.are.same(CURE, env.crossbar_files.WAR.sets[1].left[3])
    assert.are.same(PROVOKE, env.hotbar_files.WAR.sets[1].row[7])
    assert.are.equal("crossbar: swapped set 1 left slot 3 with hotbar set 1 row slot 7", env.chat[#env.chat])
  end)

  it("drags a slot off the hotbar onto the crossbar, under the same edit mode", function()
    crossbar.handle_command({ "edit" })
    local from_x, from_y = hotbar_slot(7)
    -- An empty crossbar slot: a swap with nothing is a move.
    assert.is_true(drag(from_x, from_y, crossbar_slot("right", 2)))
    assert.are.same(CURE, env.crossbar_files.WAR.sets[1].right[2])
    assert.is_nil(env.hotbar_files.WAR.sets[1], "and the hotbar's slot is left empty")
    assert.are.equal("hotbar: swapped set 1 row slot 7 with crossbar set 1 right slot 2", env.chat[#env.chat])
  end)

  it("cancels a drop between two slots of the other bar", function()
    crossbar.handle_command({ "edit" })
    local from_x, from_y = crossbar_slot("left", 3)
    -- Pick the slot and then its base layer, which is what a drop on empty
    -- space would clear.
    mouse(LEFT_DOWN, from_x, from_y)
    mouse(LEFT_UP, from_x, from_y)
    local row = nil
    for _, prim in ipairs(env.prims.texts) do
      if prim.visible and prim.destroyed == 0 and tostring(prim.last.text):find("base: ", 1, true) then
        row = prim
      end
    end
    mouse(LEFT_DOWN, row.x + 5, row.y + 5)
    mouse(LEFT_UP, row.x + 5, row.y + 5)
    local x, y = hotbar_slot(7)
    local said = #env.chat
    drag(from_x, from_y, x + hotbar_render({ config = hotbar.defaults }).slot_size() / 2 + 2, y)
    assert.are.same(PROVOKE, env.crossbar_files.WAR.sets[1].left[3], "a near miss is not a delete")
    assert.are.equal(said, #env.chat)
    drag(from_x, from_y, 4, 4)
    assert.is_nil(env.crossbar_files.WAR.sets[1], "clear of both bars still clears the layer")
  end)
end)
