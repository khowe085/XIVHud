local new_bar = require("lib/actionbar/bar")
local grammars = require("lib/actionbar/grammar")
local new_render = require("lib/actionbar/render")
local fakes = require("tests/support/fakes")

local function resources()
  return {
    spells = {
      [1] = { id = 1, en = "Cure", type = "WhiteMagic", recast_id = 1, mp_cost = 8 },
    },
    job_abilities = { [605] = { id = 605, en = "Provoke", recast_id = 5, tp_cost = 0 } },
    weapon_skills = { [42] = { id = 42, en = "Savage Blade", skill = 4 } },
    skills = { [4] = { id = 4, en = "Sword" } },
    items = {
      [4112] = { id = 4112, en = "Potion" },
      [16535] = { id = 16535, en = "Ark Sword", skill = 4 },
    },
    mounts = {},
    key_items = {},
    statuses = { [0] = { en = "Idle" }, [1] = { en = "Engaged" } },
    bags = {
      [0] = { id = 0, en = "Inventory", equippable = true },
      [3] = { id = 3, en = "Temporary", equippable = false },
    },
  }
end

local function world(opts)
  opts = opts or {}
  local env = {
    chat = {},
    commands = {},
    player = {
      id = 7,
      main_job = "WAR",
      main_job_id = 1,
      main_job_level = 99,
      sub_job = "NIN",
      sub_job_id = 13,
      vitals = { mp = 100, tp = 1000 },
      buffs = {},
      status = 1,
    },
    items = { [0] = { enabled = true } },
    equipment = {},
    files = {},
    store_files = opts.store_files or {
      WAR = { sets = { [1] = { row = { [3] = { type = "ma", action = "Cure", target = "t" } } } } },
    },
    repaints = 0,
    layout = false,
    visible = true,
    edits = {},
    config = { set_flags = {}, hide = {} },
    config_saves = 0,
  }
  for set = 1, 8 do
    env.config.set_flags[set] = { shared = false, cycle = { drawn = true, sheathed = true } }
  end
  local prims = fakes.prims()
  local ctx = {
    screen = function()
      return 1920, 1080
    end,
    say = function(line)
      env.chat[#env.chat + 1] = line
    end,
    send_command = function(command)
      env.commands[#env.commands + 1] = command
    end,
    now = function()
      return env.now or 0
    end,
    get_player = function()
      return env.player
    end,
    get_mob_by_target = function()
      return { id = 99, distance = 4, model_size = 1 }
    end,
    get_spells = function()
      return { [1] = true }
    end,
    get_abilities = function()
      return { job_abilities = { 605 }, weapon_skills = { 42 } }
    end,
    get_items = function(bag, index)
      if index ~= nil then
        return (env.items[bag] or {})[index]
      end
      return env.items[bag]
    end,
    get_equipment = function()
      return env.equipment
    end,
    get_spell_recasts = function()
      return env.spell_recasts or {}
    end,
    get_ability_recasts = function()
      return env.ability_recasts or {}
    end,
    file_exists = function(path)
      return env.files[path] == true
    end,
    asset = function(path)
      return "addon/" .. path
    end,
    new_image = prims.new_image,
    new_text = prims.new_text,
    layout_active = function()
      return env.layout
    end,
    resources = resources(),
  }
  env.service_config = {
    retry = require("lib/actionbar/retry")({}).defaults(),
    wsgate = require("lib/actionbar/wsgate")({}).defaults(),
    delay = 5,
  }
  ctx.actions = fakes.action_service(ctx, env.service_config)
  local render = new_render({ config = env.config })
  local store = {
    load = function(name)
      return env.store_files[name]
    end,
    save = function(name, value)
      env.store_files[name] = value
    end,
  }
  local cells = {}
  local bar = new_bar({
    name = "hotbar",
    grammar = grammars.hotbar(),
    views = false,
    ctx = ctx,
    config = function()
      return env.config
    end,
    save = function()
      env.config_saves = env.config_saves + 1
    end,
    render = function()
      return render
    end,
    -- The shared render hit-tests rects as they are, so a spec that wants
    -- slots on screen names them outright.
    groups = function()
      return env.rects or {}
    end,
    cells = function(visit)
      for _, cell in ipairs(cells) do
        visit(cell)
      end
    end,
    repaint = function()
      env.repaints = env.repaints + 1
    end,
    visible = function()
      return env.visible
    end,
    footprint = function()
      return env.footprint or {}
    end,
    on_edit = function(open)
      env.edits[#env.edits + 1] = open
    end,
  })
  return bar, env, ctx, store, cells
end

describe("one bar's state", function()
  describe("job scoping", function()
    it("scopes the job the client names and loads its file, once", function()
      local bar, env, _, store = world()
      bar.attach(store)
      assert.is_nil(bar.scoped())
      bar.try_scope()
      assert.are.equal("WAR", bar.scoped())
      assert.are.same({ type = "ma", action = "Cure", target = "t" }, (bar.bindings().resolve(1, "row", 3)))
      local repaints = env.repaints
      bar.try_scope()
      assert.are.equal(repaints, env.repaints, "the same job is not rescoped")
    end)

    it("holds a job change until the client agrees with the announced ids", function()
      local bar, env, _, store = world()
      bar.attach(store)
      bar.try_scope()
      env.now = 1
      bar.on_job_change(3, 99, 13, 49)
      assert.are.equal("WAR", bar.scoped(), "the client still answers the old job")
      env.player.main_job, env.player.main_job_id = "MNK", 3
      bar.tick_scope(2)
      assert.are.equal("MNK", bar.scoped())
    end)

    it("gives up waiting after the deadline and scopes whatever the client says", function()
      local bar, env, _, store = world()
      bar.attach(store)
      bar.try_scope()
      env.now = 1
      bar.on_job_change(3, 99, 13, 49)
      bar.tick_scope(12)
      assert.are.equal("WAR", bar.scoped())
    end)

    it("forgets the scope on detach", function()
      local bar, _, _, store = world()
      bar.attach(store)
      bar.try_scope()
      bar.detach()
      assert.is_nil(bar.scoped())
    end)
  end)

  describe("a press", function()
    it("resolves the slot through its bindings and fires it through the service", function()
      local bar, env, _, store = world()
      bar.attach(store)
      bar.try_scope()
      local flashed = 0
      bar.fire(1, "row", 3, function()
        flashed = flashed + 1
      end)
      assert.are.same({ 'input /ma "Cure" <t>' }, env.commands)
      assert.are.equal(1, flashed)
    end)

    it("is silent for an empty slot", function()
      local bar, env, _, store = world()
      bar.attach(store)
      bar.try_scope()
      bar.fire(1, "row", 4, function() end)
      assert.are.same({}, env.commands)
    end)

    it("mirrors the service's weapon state into the rotation and repaints", function()
      local bar, env, ctx, store = world()
      bar.attach(store)
      bar.try_scope()
      local repaints = env.repaints
      ctx.actions.set_weapon_state("drawn")
      bar.sync_weapon()
      assert.are.equal("drawn", bar.bindings().weapon_state())
      assert.are.equal(repaints + 1, env.repaints)
      bar.sync_weapon()
      assert.are.equal(repaints + 1, env.repaints, "settled, nothing to repaint")
    end)
  end)

  describe("meta", function()
    it("names a record's resource facts", function()
      local bar = world()
      local meta = bar.meta_for({ type = "ma", action = "cure" })
      assert.are.equal("spell", meta.kind)
      assert.are.equal(8, meta.mp_cost)
      assert.are.equal("White Magic", meta.category)
      assert.are.equal("Sword", bar.meta_for({ type = "ws", action = "Savage Blade" }).weapon)
      assert.are.equal(4112, bar.meta_for({ type = "item", action = "Potion" }).item_id)
      assert.is_nil(bar.meta_for(nil))
    end)
  end)

  describe("the item counts", function()
    it("counts what the painted slots are bound to, from the inventory", function()
      local bar, env, _, store, cells = world()
      bar.attach(store)
      bar.try_scope()
      env.items[0] = { enabled = true, { id = 4112, slot = 1, count = 3 } }
      cells[1] = {
        record = function()
          return { type = "item", action = "Potion" }
        end,
        meta = function()
          return { kind = "item", item_id = 4112 }
        end,
      }
      bar.mark_counts_dirty()
      bar.recount_if_dirty()
      local counter = bar.counter_for(cells[1].record(), cells[1].meta(), env.player, {})
      assert.are.equal("3", counter.text)
      assert.is_false(counter.zero == true)
    end)

    it("hands a stratagem slot the next charge's recast and whether one is in hand", function()
      local bar = world()
      local player = { main_job = "SCH", main_job_level = 50, sub_job = "WHM", sub_job_level = 25 }
      local record = { type = "ja", action = "Penury" }
      local spent = bar.counter_for(record, nil, player, { [231] = 240 })
      assert.are.equal("0", spent.text)
      assert.are.equal(80, spent.recast)
      assert.is_false(spent.charged)
      local one_back = bar.counter_for(record, nil, player, { [231] = 150 })
      assert.are.equal("1", one_back.text)
      assert.are.equal(70, one_back.recast)
      assert.is_true(one_back.charged)
    end)

    it("leaves the recast alone on a counter that is not a stratagem", function()
      local bar, env, _, store = world()
      bar.attach(store)
      bar.try_scope()
      local counter = bar.counter_for(
        { type = "item", action = "Potion" },
        { kind = "item", item_id = 4112 },
        env.player,
        {}
      )
      assert.is_nil(counter.recast)
      assert.is_nil(counter.charged)
    end)
  end)

  describe("commands", function()
    it("switches sets, advances the rotation and refuses the rest with a hint", function()
      local bar, _, _, store = world({
        store_files = {
          WAR = {
            sets = {
              [1] = { row = { [1] = { type = "ma", action = "Cure" } } },
              [2] = { row = { [1] = { type = "ma", action = "Cure" } } },
              [3] = { row = { [1] = { type = "ma", action = "Cure" } } },
            },
          },
        },
      })
      bar.attach(store)
      bar.try_scope()
      assert.are.equal("hotbar: set 2", bar.command({ "set", "2" }))
      assert.are.equal("hotbar: set 3", bar.command({ "cycle" }))
      assert.are.equal("hotbar: set 2", bar.command({ "cycle", "back" }))
      assert.are.equal("hotbar: set 1", bar.command({ "cycle", "BACK" }))
      assert.is_not_nil(bar.command({ "set" }):find("set takes a number", 1, true))
      assert.is_not_nil(bar.command({ "bogus" }):find("unknown command 'bogus'", 1, true))
      assert.is_not_nil(
        bar.command({ "warp" }):find("unknown command 'warp'", 1, true),
        "the framework's verb, not the bar's"
      )
    end)

    it("authors through the CLI in its own name and saves a config write", function()
      local bar, env, _, store = world()
      bar.attach(store)
      bar.try_scope()
      local reply = bar.command({ "bind", "2:5", "ma", "Cure", "t" })
      assert.is_not_nil(reply:find("^hotbar: bound 2:5"), reply)
      assert.are.same({ type = "ma", action = "Cure", target = "t" }, env.store_files.WAR.sets[2].row[5])
      bar.command({ "share", "2", "on" })
      assert.are.equal(1, env.config_saves)
    end)

    it("refuses to open its binder over another bar's", function()
      local bar, env, ctx, store = world()
      bar.attach(store)
      bar.try_scope()
      ctx.actions.set_edit_mode("crossbar", true)
      local reply = bar.command({ "edit" })
      assert.is_not_nil(reply:find("crossbar's binder is open", 1, true), reply)
      assert.is_false(bar.editing())
      assert.are.same({}, env.edits)
      ctx.actions.set_edit_mode("crossbar", false)
      assert.is_not_nil(bar.command({ "edit" }):find("edit mode on", 1, true))
    end)

    it("drops only its own held cast on detach", function()
      local bar, env, ctx, store = world()
      env.service_config.retry.enabled = true
      bar.attach(store)
      bar.try_scope()
      ctx.actions.fire({ type = "ma", action = "Cure", target = "t" }, {
        owner = "crossbar",
        retry_facts = function()
          return { bound = true }
        end,
      })
      bar.detach()
      assert.is_not_nil(ctx.actions.retry.held(), "the crossbar's cast is the crossbar's")
    end)

    it("names itself as the owner of the press it fires", function()
      local bar, env, ctx, store = world()
      env.service_config.retry.enabled = true
      bar.attach(store)
      bar.try_scope()
      bar.fire(1, "row", 3, function() end)
      assert.are.equal("hotbar", ctx.actions.retry.held().owner)
    end)

    it("opens and closes edit mode through the widget's hook, refusing while hidden", function()
      local bar, env, _, store = world()
      bar.attach(store)
      env.visible = false
      assert.is_not_nil(bar.command({ "edit" }):find("hidden", 1, true))
      env.visible = true
      assert.is_not_nil(bar.command({ "edit" }):find("no job scoped", 1, true))
      bar.try_scope()
      assert.is_not_nil(bar.command({ "edit" }):find("edit mode on", 1, true))
      assert.is_true(bar.editing())
      assert.are.same({ true }, env.edits)
      assert.is_not_nil(bar.command({ "edit" }):find("edit mode off", 1, true))
      assert.is_false(bar.editing())
      assert.are.same({ true, false }, env.edits)
    end)
  end)

  describe("as one of two bars", function()
    local MOVE, LEFT_DOWN, LEFT_UP = 0, 1, 2

    local function on_screen(env)
      env.rects = { { x = 100, y = 100, width = 40, height = 40, key = "bar3", set = 1, side = "row", slot = 3 } }
    end

    it("answers another bar's drop with the slot it draws there and its own model", function()
      local bar, env, ctx, store = world()
      bar.attach(store)
      bar.try_scope()
      on_screen(env)
      assert.is_nil(ctx.actions.drop_target_at("hotbar", 120, 120), "never to itself")
      assert.is_nil(ctx.actions.drop_target_at("crossbar", 90, 120), "nor where it draws nothing")
      local target = ctx.actions.drop_target_at("crossbar", 120, 120)
      assert.are.equal("hotbar", target.bar)
      assert.are.same({ 1, "row", 3 }, { target.set, target.side, target.slot })
      assert.are.equal(bar.bindings(), target.bindings)
      local repaints = env.repaints
      target.repaint()
      assert.are.equal(repaints + 1, env.repaints)
    end)

    it("answers nothing while it is hidden", function()
      local bar, env, ctx, store = world()
      bar.attach(store)
      bar.try_scope()
      on_screen(env)
      env.footprint = { { x = 90, y = 90, width = 200, height = 60 } }
      env.visible = false
      assert.is_nil(ctx.actions.drop_target_at("crossbar", 120, 120))
      assert.is_nil(ctx.actions.bar_at(120, 120))
    end)

    it("covers every rect of its footprint, and nothing past them", function()
      local bar, env, ctx, store = world()
      bar.attach(store)
      bar.try_scope()
      assert.is_nil(ctx.actions.bar_at(95, 95), "a bar that names no footprint covers nothing")
      env.footprint = {
        { x = 90, y = 90, width = 200, height = 60 },
        { x = 90, y = 300, width = 200, height = 60 },
      }
      assert.are.equal("hotbar", ctx.actions.bar_at(95, 95))
      assert.are.equal("hotbar", ctx.actions.bar_at(289, 359))
      assert.is_nil(ctx.actions.bar_at(290, 95), "the far edge is outside")
      assert.is_nil(ctx.actions.bar_at(95, 200), "and so is the space between two rows")
    end)

    it("cancels a slot dropped on the bar but on no slot of it", function()
      local files = {
        WAR = {
          sets = { [1] = { row = { [3] = { type = "ma", action = "Cure", target = "t" } } } },
          sub = { NIN = { [1] = { row = { [3] = { type = "ja", action = "Provoke" } } } } },
        },
      }
      local bar, env, _, store = world({ store_files = files })
      bar.attach(store)
      bar.try_scope()
      on_screen(env)
      env.footprint = { { x = 90, y = 90, width = 200, height = 60 } }
      bar.command({ "edit" })
      local binder = bar.binder()
      -- Pick the slot, then its subjob layer: the layer a drop on empty
      -- space clears.
      binder.mouse(LEFT_DOWN, 120, 120, 0)
      binder.mouse(LEFT_UP, 120, 120, 0)
      for _, row in ipairs(binder.layer_view().rows) do
        if row.source == "sub" then
          binder.mouse(LEFT_DOWN, row.x + 5, row.y + 5, 0)
          binder.mouse(LEFT_UP, row.x + 5, row.y + 5, 0)
        end
      end
      assert.are.equal("sub", binder.layer())
      local said = #env.chat
      binder.mouse(LEFT_DOWN, 120, 120, 0)
      binder.mouse(MOVE, 200, 145, 0)
      binder.mouse(LEFT_UP, 200, 145, 0)
      assert.are.same({ type = "ja", action = "Provoke" }, env.store_files.WAR.sub.NIN[1].row[3])
      assert.are.equal(said, #env.chat, "and quietly")
      binder.mouse(LEFT_DOWN, 120, 120, 0)
      binder.mouse(MOVE, 4, 4, 0)
      binder.mouse(LEFT_UP, 4, 4, 0)
      assert.is_nil(env.store_files.WAR.sub.NIN, "clear of the bar still clears the layer")
    end)

    it("repaints when another bar's binder opens and when it closes", function()
      local bar, env, ctx, store = world()
      bar.attach(store)
      bar.try_scope()
      local repaints = env.repaints
      ctx.actions.set_edit_mode("crossbar", true)
      assert.are.equal(repaints + 1, env.repaints)
      ctx.actions.set_edit_mode("crossbar", false)
      assert.are.equal(repaints + 2, env.repaints)
    end)

    it("swaps a slot dragged off it with the other bar's slot under the drop", function()
      local bar, env, ctx, store = world()
      bar.attach(store)
      bar.try_scope()
      on_screen(env)
      local files = { WAR = { sets = { [2] = { left = { [5] = { type = "ja", action = "Provoke" } } } } } }
      local crossbar = require("lib/actionbar/bindings")({
        load = function(name)
          return files[name]
        end,
        save = function(name, value)
          files[name] = value
        end,
        get_config = function()
          return env.config
        end,
      })
      crossbar.set_job("WAR", "NIN")
      local repainted = 0
      ctx.actions.register_bar("crossbar", {
        slot_at = function(x, y)
          return x == 600 and y == 120 and { set = 2, side = "left", slot = 5 } or nil
        end,
        bindings = function()
          return crossbar
        end,
        repaint = function()
          repainted = repainted + 1
        end,
      })
      bar.command({ "edit" })
      repainted = 0
      local binder = bar.binder()
      binder.mouse(LEFT_DOWN, 120, 120, 0)
      binder.mouse(MOVE, 600, 120, 0)
      binder.mouse(LEFT_UP, 600, 120, 0)
      assert.are.same({ type = "ja", action = "Provoke" }, env.store_files.WAR.sets[1].row[3])
      assert.are.same({ type = "ma", action = "Cure", target = "t" }, files.WAR.sets[2].left[5])
      assert.are.equal("hotbar: swapped set 1 row slot 3 with crossbar set 2 left slot 5", env.chat[#env.chat])
      assert.are.equal(1, repainted)
    end)
  end)
end)
