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
  -- `actions` shares one service between two bars, as the entry point does.
  ctx.actions = opts.actions or fakes.action_service(ctx, env.service_config)
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
    name = opts.name or "hotbar",
    grammar = opts.name == "crossbar" and grammars.crossbar() or grammars.hotbar(),
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

    it("opens its binder beside another bar's", function()
      -- It refused until 2026-09-28, one binder at a time: a slot could be
      -- dragged off the bar being edited and never off the other.
      local bar, env, ctx, store = world()
      bar.attach(store)
      bar.try_scope()
      ctx.actions.set_edit_mode("crossbar", true)
      local reply = bar.command({ "edit" })
      assert.is_not_nil(reply:find("edit mode on", 1, true), reply)
      assert.is_true(bar.editing())
      assert.are.same({ true }, env.edits)
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

  --[[ Two REAL bars over one service, as the entry point builds them: the
       crossbar first, which is the order core hands each mouse event round
       in. The hotbar draws `1:3` at (100, 100) and the crossbar `2L5` at
       (100, 900), both clear of where a binder's window opens. ]]
  describe("one edit mode over both bars", function()
    local MOVE, LEFT_DOWN, LEFT_UP = 0, 1, 2
    local PROVOKE = { type = "ja", action = "Provoke" }
    local CURE = { type = "ma", action = "Cure", target = "t" }

    local function pair()
      local cross, cross_env, ctx, cross_store = world({
        name = "crossbar",
        store_files = { WAR = { sets = { [2] = { left = { [5] = { type = "ja", action = "Provoke" } } } } } },
      })
      local hot, hot_env, _, hot_store = world({ actions = ctx.actions })
      cross.attach(cross_store)
      cross.try_scope()
      hot.attach(hot_store)
      hot.try_scope()
      cross_env.rects = { { x = 100, y = 900, width = 40, height = 40, set = 2, side = "left", slot = 5 } }
      hot_env.rects = { { x = 100, y = 100, width = 40, height = 40, set = 1, side = "row", slot = 3 } }
      local both = { cross = cross, cross_env = cross_env, hot = hot, hot_env = hot_env, service = ctx.actions }
      -- Core's own dispatch: every bar hears every event, and the answers
      -- are ORed.
      function both.mouse(kind, x, y)
        local crossbar = cross.editing() and cross.binder().mouse(kind, x, y, 0) or false
        local hotbar = hot.editing() and hot.binder().mouse(kind, x, y, 0) or false
        return crossbar or hotbar
      end
      function both.click(x, y)
        both.mouse(LEFT_DOWN, x, y)
        return both.mouse(LEFT_UP, x, y)
      end
      function both.drag(from_x, from_y, to_x, to_y)
        both.mouse(LEFT_DOWN, from_x, from_y)
        both.mouse(MOVE, to_x, to_y)
        return both.mouse(LEFT_UP, to_x, to_y)
      end
      return both
    end

    it("opens every bar's binder from either bar's command, and says so", function()
      local both = pair()
      local reply = both.hot.command({ "edit" })
      assert.is_not_nil(reply:find("^hotbar: edit mode on, crossbar too"), reply)
      assert.is_true(both.hot.editing())
      assert.is_true(both.cross.editing())
      assert.are.same({ true }, both.cross_env.edits, "through the widget's own hook")
    end)

    it("closes every bar's binder from either bar's command", function()
      local both = pair()
      both.hot.command({ "edit" })
      assert.are.equal("crossbar: edit mode off", both.cross.command({ "edit" }))
      assert.is_false(both.hot.editing())
      assert.is_false(both.cross.editing())
      assert.is_nil(both.service.edit_owner())
    end)

    it("leaves out a bar that cannot open, and says nothing of it", function()
      local both = pair()
      both.cross_env.visible = false
      local reply = both.hot.command({ "edit" })
      assert.is_not_nil(reply:find("^hotbar: edit mode on %- "), reply)
      assert.is_true(both.hot.editing())
      assert.is_false(both.cross.editing())
    end)

    it("joins an edit mode the other bar is already in", function()
      local both = pair()
      both.cross_env.visible = false
      both.hot.command({ "edit" })
      both.cross_env.visible = true
      local reply = both.cross.command({ "edit" })
      assert.is_not_nil(reply:find("^crossbar: edit mode on, hotbar too"), reply)
      assert.is_true(both.cross.editing())
      assert.is_true(both.hot.editing(), "and the one already open stays open")
    end)

    it("opens nothing when the bar that was asked cannot", function()
      local both = pair()
      both.hot_env.visible = false
      local reply = both.hot.command({ "edit" })
      assert.is_not_nil(reply:find("hidden", 1, true), reply)
      assert.is_false(both.cross.editing())
    end)

    it("drags a slot off either bar onto the other", function()
      local both = pair()
      both.hot.command({ "edit" })
      assert.is_true(both.drag(120, 120, 120, 920), "off the hotbar")
      assert.are.same(PROVOKE, both.hot_env.store_files.WAR.sets[1].row[3])
      assert.are.same(CURE, both.cross_env.store_files.WAR.sets[2].left[5])
      assert.is_true(both.drag(120, 920, 120, 120), "and off the crossbar")
      assert.are.same(CURE, both.hot_env.store_files.WAR.sets[1].row[3])
      assert.are.same(PROVOKE, both.cross_env.store_files.WAR.sets[2].left[5])
    end)

    it("puts one bar's window away when a slot on the other is clicked", function()
      local both = pair()
      both.hot.command({ "edit" })
      both.click(120, 920)
      assert.is_not_nil(both.cross.binder().window())
      both.click(120, 120)
      assert.is_nil(both.cross.binder().window(), "one window, whichever bar it is for")
      assert.is_not_nil(both.hot.binder().window())
    end)

    it("leaves a click on one bar's window to that bar, whatever slot lies beneath", function()
      -- The shipped hotbar row sits under the crossbar's centred window.
      local both = pair()
      both.hot_env.rects = { { x = 900, y = 516, width = 40, height = 40, set = 1, side = "row", slot = 3 } }
      both.hot.command({ "edit" })
      both.click(120, 920)
      local window = both.cross.binder().window()
      assert.are.equal("layer", window.step)
      assert.is_false(both.hot.binder().mouse(LEFT_DOWN, 920, 536, 0), "not the hotbar's press")
      assert.is_false(both.hot.binder().mouse(MOVE, 100, 100, 0), "so nothing is in hand")
      assert.is_false(both.hot.binder().mouse(LEFT_UP, 920, 536, 0))
      assert.is_nil(both.hot.binder().window(), "and no second window opened")
      assert.is_true(both.click(920, 536), "it is the crossbar's, on its own window")
      assert.are.equal(window.step, both.cross.binder().window().step)
    end)

    describe("with a slot of each on one point", function()
      -- The hotbar's `1:3` laid over the crossbar's `2L5`. The hotbar is
      -- registered second, so it is the one on top.
      local function overlapping()
        local both = pair()
        both.cross_env.rects = {
          { x = 100, y = 900, width = 40, height = 40, set = 2, side = "left", slot = 5 },
          { x = 200, y = 900, width = 40, height = 40, set = 2, side = "left", slot = 6 },
        }
        both.hot_env.rects = { { x = 100, y = 900, width = 40, height = 40, set = 1, side = "row", slot = 3 } }
        both.hot.command({ "edit" })
        return both
      end

      it("opens ONE window for a click, the bar's that is drawn on top", function()
        local both = overlapping()
        both.click(120, 920)
        assert.is_not_nil(both.hot.binder().window())
        assert.is_nil(both.cross.binder().window())
      end)

      it("does ONE swap for a drag, of the slot that is drawn on top", function()
        local both = overlapping()
        both.drag(120, 920, 220, 920)
        assert.are.same(PROVOKE, both.cross_env.store_files.WAR.sets[2].left[5], "the slot underneath is untouched")
        assert.are.same(CURE, both.cross_env.store_files.WAR.sets[2].left[6])
        assert.is_nil(both.hot_env.store_files.WAR.sets[1], "the hotbar's slot moved onto an empty one")
        assert.are.equal(1, #both.hot_env.chat)
        assert.are.equal(0, #both.cross_env.chat)
      end)

      it("drops onto the slot that is drawn on top", function()
        local both = overlapping()
        both.cross.bindings().bind("2", "left", 6, { type = "ja", action = "Berserk" })
        both.drag(220, 920, 120, 920)
        assert.are.same({ type = "ja", action = "Berserk" }, both.hot_env.store_files.WAR.sets[1].row[3])
        assert.are.same(CURE, both.cross_env.store_files.WAR.sets[2].left[6])
        assert.are.same(PROVOKE, both.cross_env.store_files.WAR.sets[2].left[5], "the slot underneath is untouched")
      end)
    end)

    it("keeps to one window after a drag whose release never arrived", function()
      --[[ The hotbar's drag loses its release, so its window stays put
           away; the next press lands on a crossbar slot INSIDE that window's
           rect. The crossbar hears it first and sees no window there; the
           hotbar then puts its window back and takes the same press for it.
           Both acted on the release, and from then on one click drove two
           wizards - a bind would have been written into both bars' files. ]]
      local both = pair()
      both.cross_env.rects = { { x = 900, y = 516, width = 40, height = 40, set = 2, side = "left", slot = 5 } }
      both.hot.command({ "edit" })
      both.click(120, 120)
      both.mouse(LEFT_DOWN, 120, 120)
      both.mouse(MOVE, 4, 4)
      both.click(920, 536)
      assert.is_not_nil(both.cross.binder().window(), "the slot that was pressed")
      assert.is_nil(both.hot.binder().window(), "and nothing else")
      local row = both.cross.binder().layer_view().rows[1]
      both.click(row.x + 5, row.y + 5)
      assert.are.equal("catalog", both.cross.binder().window().step)
      assert.is_nil(both.hot.binder().window())
    end)

    it("keeps a drag to one bar after a drag whose release never arrived", function()
      -- The same lost release, followed by a DRAG off the crossbar slot
      -- rather than a click on it: nothing opens a window, so nothing stood
      -- the hotbar down, and its binder acted on the release as a click on
      -- a row of the window it had put back.
      local both = pair()
      both.cross_env.rects = {
        { x = 900, y = 516, width = 40, height = 40, set = 2, side = "left", slot = 5 },
        { x = 100, y = 900, width = 40, height = 40, set = 2, side = "left", slot = 6 },
      }
      both.hot.command({ "edit" })
      both.click(120, 120)
      local row = both.hot.binder().layer_view().rows[1]
      both.click(row.x + 5, row.y + 5)
      assert.are.equal("catalog", both.hot.binder().window().step)
      both.mouse(LEFT_DOWN, 120, 120)
      both.mouse(MOVE, 4, 4)
      local said = #both.hot_env.chat
      assert.is_true(both.drag(920, 536, 120, 920))
      assert.are.equal(said, #both.hot_env.chat, "the hotbar did nothing")
      assert.are.same(CURE, both.hot_env.store_files.WAR.sets[1].row[3])
      assert.is_nil(both.hot.binder().window())
      assert.are.same(
        PROVOKE,
        both.cross_env.store_files.WAR.sets[2].left[6],
        "the crossbar's drag is the one that ran"
      )
      assert.is_nil(both.cross_env.store_files.WAR.sets[2].left[5])
    end)

    it("reaches the slot under a window that a drag has put away", function()
      local both = pair()
      both.hot_env.rects = { { x = 900, y = 516, width = 40, height = 40, set = 1, side = "row", slot = 3 } }
      both.hot.command({ "edit" })
      both.click(120, 920)
      assert.are.equal("crossbar", both.service.window_at("hotbar", 920, 536))
      both.mouse(LEFT_DOWN, 120, 920)
      both.mouse(MOVE, 920, 536)
      assert.is_nil(both.service.window_at("hotbar", 920, 536), "off screen for the length of the drag")
      both.mouse(LEFT_UP, 920, 536)
      assert.are.same(PROVOKE, both.hot_env.store_files.WAR.sets[1].row[3])
    end)
  end)
end)
