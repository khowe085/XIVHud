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
    zones = {},
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
    groups = function()
      return {}
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
end)
