local new_service = require("lib/actionbar/service")
local new_retry = require("lib/actionbar/retry")
local new_wsgate = require("lib/actionbar/wsgate")
local enchanted = require("lib/actionbar/enchanted")

local RING_EXT_WARMING = {
  type = "Enchanted Equipment",
  charges_remaining = 1,
  next_use_time = 1000000 - 18000,
  activation_time = 1000000 - 18000 + 31,
  usable = false,
}

local function resources()
  return {
    spells = {
      [1] = { id = 1, en = "Cure", type = "WhiteMagic", recast_id = 1, mp_cost = 8 },
      [261] = { id = 261, en = "Warp", type = "BlackMagic", recast_id = 261, mp_cost = 100 },
    },
    job_abilities = { [605] = { id = 605, en = "Provoke", recast_id = 5, tp_cost = 0 } },
    weapon_skills = { [42] = { id = 42, en = "Savage Blade", skill = 4 } },
    skills = { [4] = { id = 4, en = "Sword" } },
    items = {
      [4181] = { id = 4181, en = "Instant Warp" },
      [26123] = { id = 26123, en = "Tavnazian Ring", slots = { [13] = true, [14] = true } },
    },
    mounts = { [1] = { name = "Chocobo" } },
    key_items = { [3000] = { category = "Mounts", name = "\226\153\170Chocobo" } },
    zones = { [100] = { id = 100, en = "Outdoors", can_mount = true } },
    statuses = { [0] = { en = "Idle" }, [1] = { en = "Engaged" }, [2] = { en = "Dead" }, [7] = { en = "Resting" } },
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
    ipc = {},
    equips = {},
    now = 0,
    time = 1000000,
    chat_open = false,
    suppressed = false,
    layout = false,
    player = {
      id = 777,
      main_job = "BLM",
      main_job_id = 4,
      main_job_level = 99,
      sub_job_id = 20,
      vitals = { mp = 200, tp = 1000 },
      buffs = {},
      status = 1,
    },
    known_spells = { [261] = true, [1] = true },
    items = { [0] = {} },
    ext = nil,
    target = { id = 99, distance = 4, model_size = 1 },
    config = {
      retry = new_retry({}).defaults(),
      wsgate = new_wsgate({}).defaults(),
      delay = 5,
    },
  }
  env.config.retry.enabled = true
  env.config.wsgate.enabled = true
  local service = new_service({
    say = function(line)
      env.chat[#env.chat + 1] = line
    end,
    send_command = function(command)
      env.commands[#env.commands + 1] = command
    end,
    send_ipc = function(message)
      env.ipc[#env.ipc + 1] = message
    end,
    now = function()
      return env.now
    end,
    time = function()
      return env.time
    end,
    get_player = function()
      return env.player
    end,
    get_mob_by_target = function()
      return env.target
    end,
    get_items = function(bag)
      return env.items[bag]
    end,
    get_spells = function()
      return env.known_spells
    end,
    get_abilities = function()
      return { job_abilities = {}, weapon_skills = { 42 } }
    end,
    get_key_items = function()
      return {}
    end,
    -- The client puts the piece on: the poll reads that status back.
    set_equip = function(bag_slot, equip_slot, bag)
      env.equips[#env.equips + 1] = { bag_slot, equip_slot, bag }
      for _, item in ipairs(env.items[bag] or {}) do
        if item.slot == bag_slot then
          item.status = enchanted.EQUIPPED
        end
      end
    end,
    decode_extdata = function()
      return env.ext
    end,
    random = function()
      return 1
    end,
    resources = (not opts.no_resources) and resources() or nil,
    zone = function()
      return 100
    end,
    suppressed = function()
      return env.suppressed
    end,
    chat_open = function()
      return env.chat_open
    end,
    layout_active = function()
      return env.layout
    end,
    config = function()
      return env.config
    end,
  })
  return service, env
end

local function said(env)
  return table.concat(env.chat, "\n")
end

-- A ring in the bag whose enchantment is still warming: the equip -> wait ->
-- use path, exactly as the widget spec drives it.
local function ring_in_bag(env)
  env.items[0] = { enabled = true, { id = 26123, slot = 4, status = 0, count = 1 } }
  env.ext = {}
  for key, value in pairs(RING_EXT_WARMING) do
    env.ext[key] = value
  end
  -- Warp the spell is the top rung; take it away so the ladder reaches the ring.
  env.known_spells = {}
  env.player.vitals.mp = 0
end

describe("the action service", function()
  describe("weapon state", function()
    it("starts sheathed and flips on the draw built-in", function()
      local service, env = world()
      assert.are.equal("sheathed", service.weapon_state())
      service.builtin("draw")
      assert.are.equal("drawn", service.weapon_state())
      assert.is_true(service.draw_state().weapon_drawn)
      assert.are.same({}, env.commands, "entering drawn sends nothing")
      service.builtin("draw")
      assert.are.equal("sheathed", service.weapon_state())
      assert.are.same({ "input /attack off" }, env.commands, "leaving drawn sheathes in game")
    end)

    it("enters drawn on an engage and stays there when the game disengages", function()
      local service = world()
      service.on_status(1)
      assert.are.equal("drawn", service.weapon_state())
      service.on_status(0)
      assert.are.equal("drawn", service.weapon_state())
    end)
  end)

  describe("a slot press", function()
    it("sends the record's command and hands the retry a re-send pinned to the target", function()
      local service, env = world()
      local flashed = 0
      local probe = function()
        return { bound = true }
      end
      service.fire({ type = "ma", action = "Cure", target = "t" }, {
        flash = function()
          flashed = flashed + 1
        end,
        retry_facts = probe,
      })
      assert.are.same({ 'input /ma "Cure" <t>' }, env.commands)
      assert.are.equal(1, flashed)
      assert.are.equal('input /ma "Cure" 99', service.retry.held().command)
      assert.are.equal(probe, service.retry.held().probe, "the bar's probe rides with the press")
    end)

    it("refuses a weaponskill the gate turns down, with no flash and no command", function()
      local service, env = world()
      local flashed = 0
      service.fire({ type = "ws", action = "Savage Blade", target = "t" }, {
        gate_facts = { tp = 500, status = 1, buffs = {}, skill = "Sword", distance_squared = 4, model_size = 1 },
        flash = function()
          flashed = flashed + 1
        end,
      })
      assert.are.same({}, env.commands)
      assert.are.equal(0, flashed)
    end)

    it("is silent for an empty slot and drops whatever the retry was watching", function()
      local service, env = world()
      service.fire({ type = "ma", action = "Cure", target = "t" }, {
        retry_facts = function()
          return { bound = true }
        end,
      })
      assert.is_not_nil(service.retry.held())
      service.fire(nil, {})
      assert.is_nil(service.retry.held())
      assert.are.equal(1, #env.commands)
      assert.are.equal("", said(env))
    end)
  end)

  describe("a warp", function()
    it("counts the spell rung down and fires it when the delay runs out", function()
      local service, env = world()
      service.warp(false)
      assert.is_not_nil(said(env):find("Warp in 5 seconds"), "said: " .. said(env))
      assert.are.same({}, env.commands, "held for the countdown")
      env.now = 5
      service.tick()
      assert.are.same({ 'input /ma "Warp" <me>' }, env.commands)
    end)

    it("broadcasts `warp all` only where the local warp commits", function()
      local service, env = world()
      service.warp(true)
      assert.are.same({}, env.ipc, "not at the press")
      env.now = 5
      service.tick()
      assert.are.same({ service.ipc_warp_message }, env.ipc)
    end)

    it("warps locally on the broadcast and never re-broadcasts", function()
      local service, env = world()
      env.config.delay = 0
      service.on_ipc(service.ipc_warp_message)
      assert.are.same({ 'input /ma "Warp" <me>' }, env.commands)
      assert.are.same({}, env.ipc)
    end)

    it("holds GearSwap, equips the ring, waits out the warmup, uses it and releases", function()
      local service, env = world()
      ring_in_bag(env)
      service.warp(false)
      assert.are.same({ "gs disable ring1" }, env.commands)
      assert.are.same({ { 4, 13, 0 } }, env.equips)
      env.now = 1
      service.tick()
      assert.are.equal(1, #env.commands, "still warming")
      env.ext.usable = true
      env.now = 2
      service.tick()
      assert.are.equal('input /item "Tavnazian Ring" <me>', env.commands[2])
      assert.are.equal("gs enable ring1", env.commands[3])
    end)

    it("abandons a wait under suppression and releases the hold", function()
      local service, env = world()
      ring_in_bag(env)
      service.warp(false)
      env.suppressed = true
      env.now = 1
      service.tick()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said(env):find("warp abandoned"), "said: " .. said(env))
    end)

    it("refuses to arm while a config mode is open", function()
      local service, env = world()
      service.set_edit_mode("crossbar", true)
      service.warp(false)
      assert.is_not_nil(said(env):find("not while edit mode is open"), "said: " .. said(env))
      assert.is_false(service.travel.armed())
      service.set_edit_mode("crossbar", false)
      env.layout = true
      service.warp(false)
      assert.is_not_nil(said(env):find("not while //hud layout is open"), "said: " .. said(env))
    end)

    it("calls a countdown off when a config mode opens under it", function()
      local service, env = world()
      service.warp(false)
      service.set_edit_mode("hotbar", true)
      service.tick()
      assert.is_false(service.travel.armed())
      env.now = 6
      service.tick()
      assert.are.same({}, env.commands)
    end)
  end)

  describe("the transitions that end a trip", function()
    it("drops a countdown and a warm-up on a job change, saying so", function()
      local service, env = world()
      ring_in_bag(env)
      service.warp(false)
      service.on_job_change()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said(env):find("warp cancelled"), "said: " .. said(env))
    end)

    it("lets resting call a warm-up off", function()
      local service, env = world()
      ring_in_bag(env)
      service.warp(false)
      service.on_status(7)
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
    end)

    it("sheathes on a job change, the way a bar's own bindings do", function()
      local service = world()
      service.builtin("draw")
      assert.are.equal("drawn", service.weapon_state())
      service.on_job_change()
      assert.are.equal("sheathed", service.weapon_state())
    end)

    it("drops a held cast only for the bar that pressed it, and a countdown only under suppression", function()
      local service, env = world()
      service.fire({ type = "ma", action = "Cure", target = "t" }, {
        owner = "crossbar",
        retry_facts = function()
          return { bound = true }
        end,
      })
      assert.is_not_nil(service.retry.held())
      service.bar_hidden("hotbar")
      assert.is_not_nil(service.retry.held(), "the other bar's cast stands")
      service.bar_hidden("crossbar")
      assert.is_nil(service.retry.held())
      service.warp(false)
      assert.is_true(service.travel.armed())
      service.bar_hidden("crossbar")
      assert.is_true(service.travel.armed(), "a user hide is not a change of mind about a warp")
      env.suppressed = true
      service.bar_hidden("hotbar")
      assert.is_false(service.travel.armed(), "a cutscene is the moment gone")
      assert.is_not_nil(said(env):find("cancelled", 1, true))
    end)

    it("names the bar whose binder is open", function()
      local service = world()
      assert.is_nil(service.edit_owner())
      service.set_edit_mode("hotbar", true)
      assert.are.equal("hotbar", service.edit_owner())
      service.set_edit_mode("hotbar", false)
      assert.is_nil(service.edit_owner())
    end)

    it("drops everything on logout and names the warp it let go", function()
      local service, env = world()
      ring_in_bag(env)
      service.warp(false)
      service.on_logout()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said(env):find("warp dropped"), "said: " .. said(env))
      assert.are.equal("sheathed", service.weapon_state())
    end)

    it("ends a trip on the zone-out chunk and on a death", function()
      local service = world()
      service.warp(false)
      service.on_chunk(0x0B, "")
      assert.is_false(service.travel.armed())
      service.warp(false)
      service.on_status(2)
      assert.is_false(service.travel.armed())
    end)
  end)

  describe("the rest of its surface", function()
    it("sheathes in game on the sword's click, one way", function()
      local service, env = world()
      service.sheathe()
      assert.are.same({ "input /attack off" }, env.commands)
      assert.are.equal("sheathed", service.weapon_state())
    end)

    it("releases a held slot silently on unload", function()
      local service, env = world()
      ring_in_bag(env)
      service.warp(false)
      local lines = #env.chat
      service.on_unload()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.are.equal(lines, #env.chat)
    end)

    it("names the tuning core seeds from the modules that own it", function()
      local service = world()
      local defaults = service.config_defaults()
      assert.is_false(defaults.retry.enabled)
      assert.is_false(defaults.wsgate.enabled)
      assert.are.equal(5, defaults.delay)
    end)
  end)

  describe("degraded", function()
    it("builds without the resources library and still answers a press", function()
      local service, env = world({ no_resources = true })
      service.fire({ type = "ma", action = "Cure", target = "t" }, {})
      assert.are.same({ 'input /ma "Cure" <t>' }, env.commands)
      assert.is_nil(service.roulette, "no mounts without the resource tables")
    end)
  end)
end)
