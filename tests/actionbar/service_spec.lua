local new_service = require("lib/actionbar/service")
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
      -- Spells and abilities number their recasts apart: this is not a stratagem.
      [231] = { id = 231, en = "Bio II", type = "BlackMagic", recast_id = 231, mp_cost = 36 },
      [136] = { id = 136, en = "Invisible", prefix = "/magic", targets = 5, levels = { [4] = 25 }, recast_id = 136 },
      [137] = { id = 137, en = "Sneak", prefix = "/magic", targets = 5, levels = { [4] = 20 }, recast_id = 137 },
    },
    job_abilities = {
      [605] = { id = 605, en = "Provoke", recast_id = 5, tp_cost = 0 },
      [700] = { id = 700, en = "Fight", recast_id = 100 },
      -- One from each family that shares a charged recast.
      [215] = { id = 215, en = "Penury", recast_id = 231 },
      [131] = { id = 131, en = "Fire Shot", recast_id = 195 },
      [688] = { id = 688, en = "Foot Kick", recast_id = 102 },
      [251] = { id = 251, en = "Ready", recast_id = 255 },
    },
    weapon_skills = { [42] = { id = 42, en = "Savage Blade", skill = 4 } },
    skills = { [4] = { id = 4, en = "Sword" } },
    items = {
      [4181] = { id = 4181, en = "Instant Warp" },
      [26123] = { id = 26123, en = "Tavnazian Ring", slots = { [13] = true, [14] = true } },
      -- The reraise ladder's consumables and one piece of its gear.
      [5770] = { id = 5770, en = "Super Reraiser" },
      [4173] = { id = 4173, en = "Hi-Reraiser" },
      [4172] = { id = 4172, en = "Reraiser" },
      [4182] = { id = 4182, en = "Instant Reraise" },
      [14790] = { id = 14790, en = "Reraise Earring", slots = { [11] = true, [12] = true } },
    },
    mounts = { [1] = { name = "Chocobo" } },
    key_items = { [3000] = { category = "Mounts", name = "\226\153\170Chocobo" } },
    statuses = { [0] = { en = "Idle" }, [1] = { en = "Engaged" }, [2] = { en = "Dead" }, [7] = { en = "Resting" } },
    bags = {
      [0] = { id = 0, en = "Inventory", equippable = true },
      [3] = { id = 3, en = "Temporary", equippable = false },
    },
  }
end

local function world(opts)
  opts = opts or {}
  local res = (not opts.no_resources) and resources() or nil
  -- The equip delay the items resource names (`cast_delay`), when a test
  -- gives the ring one.
  if res ~= nil and opts.cast_delay ~= nil then
    res.items[26123].cast_delay = opts.cast_delay
  end
  local env = {
    chat = {},
    debug_log = {},
    commands = {},
    ipc = {},
    equips = {},
    now = 0,
    time = 1000000,
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
    spell_recasts = {},
    ability_recasts = {},
    items = { [0] = {} },
    ext = nil,
    target = { id = 99 },
    config = {
      delay = 5,
    },
  }
  local service = new_service({
    say = function(line)
      env.chat[#env.chat + 1] = line
    end,
    debug_log = not opts.no_debug_log and function(line)
      env.debug_log[#env.debug_log + 1] = line
    end or nil,
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
    get_mob_by_target = function(token)
      if token == "st" then
        return env.subtarget
      end
      env.asked_token = token
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
    get_spell_recasts = function()
      return env.spell_recasts
    end,
    get_ability_recasts = function()
      return env.ability_recasts
    end,
    -- The client puts the piece on: the poll reads that status back. A test
    -- holds it off (a GearSwap swap in flight) with `equip_lands = false`.
    set_equip = function(bag_slot, equip_slot, bag)
      env.equips[#env.equips + 1] = { bag_slot, equip_slot, bag }
      if env.equip_lands == false then
        return
      end
      for _, item in ipairs(env.items[bag] or {}) do
        if item.slot == bag_slot then
          item.status = enchanted.EQUIPPED
        end
      end
    end,
    -- One ext for every item unless a test gives an item its own.
    decode_extdata = function(item)
      return env.ext_by_id ~= nil and env.ext_by_id[item.id] or env.ext
    end,
    random = function()
      return 1
    end,
    resources = res,
    suppressed = function()
      return env.suppressed
    end,
    layout_active = function()
      return env.layout
    end,
    settings_open = function()
      return env.settings_open
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

local function logged(env)
  return table.concat(env.debug_log, "\n")
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
  describe("the reraise ladder", function()
    it("equips the earring once no spell or item can go, and waits out its warm-up", function()
      --[[ None of the four consumables is in the bag, so the ladder reaches
           the gear. The earring warms for thirty seconds and the scheduler
           must not give up on it at the first poll. ]]
      local service, env = world()
      env.items[0] = { enabled = true, { id = 14790, slot = 4, status = 0, count = 1 } }
      env.ext = {}
      for key, value in pairs(RING_EXT_WARMING) do
        env.ext[key] = value
      end
      service.builtin("reraise")
      assert.are.same({ "gs disable ear1" }, env.commands)
      assert.are.same({ { 4, 11, 0 } }, env.equips)
      env.now = 1
      service.tick()
      assert.are.same({ "gs disable ear1" }, env.commands, "still warming, still held")
      env.ext.usable = true
      env.now = 2
      service.tick()
      assert.are.same({ "gs disable ear1", 'input /item "Reraise Earring" <me>', "gs enable ear1" }, env.commands)
    end)

    it("refuses while Reraise is already on and touches nothing", function()
      local service, env = world()
      env.items[0] = { enabled = true, { id = 14790, slot = 4, status = 0, count = 1 } }
      env.player.buffs = { 113 }
      assert.are.equal("Reraise is already active", service.builtin("reraise"))
      assert.are.same({}, env.commands)
      assert.are.same({}, env.equips)
    end)
  end)

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

  --[[ What a command sent late is sent as: a pinned token becomes the id it
       stood for at the press, a fixed one goes as written, and anything
       else cannot be pinned. ]]
  describe("the target pin", function()
    it("pins the battle target to its id", function()
      local service, env = world()
      assert.are.equal('input /item "Ring" 99', service.pinned_command('input /item "Ring" <bt>', "bt"))
      assert.are.equal("bt", env.asked_token)
    end)

    it("folds a hand-edited upper-case token before pinning it", function()
      local service = world()
      assert.are.equal('input /item "Ring" 99', service.pinned_command('input /item "Ring" <T>', "T"))
    end)

    it("sends a fixed token as written", function()
      local service = world()
      assert.are.equal('input /item "Ring" <pet>', service.pinned_command('input /item "Ring" <pet>', "pet"))
      assert.are.equal('input /item "Ring" <me>', service.pinned_command('input /item "Ring" <me>', "me"))
    end)

    it("refuses a token it cannot pin", function()
      local service = world()
      assert.is_nil(service.pinned_command('input /item "Ring" <st>', "st"))
    end)

    it("refuses a command that does not end in the token it names", function()
      local service = world()
      assert.is_nil(service.pinned_command('input /item "Ring" <me>', "t"))
    end)
  end)

  describe("a slot press", function()
    it("sends the record's command and flashes", function()
      local service, env = world()
      local flashed = 0
      service.fire({ type = "ma", action = "Cure", target = "t" }, {
        flash = function()
          flashed = flashed + 1
        end,
      })
      assert.are.same({ 'input /ma "Cure" <t>' }, env.commands)
      assert.are.equal(1, flashed)
    end)

    it("is silent for an empty slot", function()
      local service, env = world()
      service.fire(nil, {})
      assert.are.same({}, env.commands)
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
      -- Warm, and held to the five-second travel delay from the press.
      env.now = 5
      service.tick()
      assert.are.equal('input /item "Tavnazian Ring" <me>', env.commands[2])
      assert.are.equal("gs enable ring1", env.commands[3])
    end)

    --[[ The ladder notes every rung it walks past, and those notes are the
         whole answer when nothing fires. When a lower rung DOES go they are
         noise - a Warp Ring's recast read out while the Tavnazian Ring
         warms up (Kevin, live client, 2026-09-13). ]]
    it("says nothing about the rungs it walked past when a lower one goes", function()
      local service, env = world()
      ring_in_bag(env)
      table.insert(env.items[0], 1, { id = 28540, slot = 2, status = 0, count = 1 })
      env.ext_by_id = {
        [28540] = {
          type = "Enchanted Equipment",
          charges_remaining = 1,
          next_use_time = env.time - 18000 + 42,
          activation_time = env.time - 18000,
          usable = false,
        },
      }
      service.warp(false)
      assert.are.same({ { 4, 13, 0 } }, env.equips, "the Tavnazian Ring goes")
      assert.is_nil(said(env):find("recast", 1, true), "said: " .. said(env))
      assert.is_nil(said(env):find("You don't have", 1, true), "said: " .. said(env))
    end)

    it("still says why when no rung goes", function()
      local service, env = world()
      env.known_spells = {}
      env.player.vitals.mp = 0
      env.items[0] = { enabled = true, { id = 28540, slot = 2, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000 + 42,
        activation_time = env.time - 18000,
        usable = false,
      }
      service.warp(false)
      assert.is_not_nil(said(env):find("Warp Ring: 42 sec recast.", 1, true), "said: " .. said(env))
    end)

    --[[ A rung that must be equipped skips the travel countdown, its own
         warm-up being the window - but a short warm-up made that window
         three seconds (Kevin, live client, 2026-09-13). The warm-up still
         sets the pace, and the travel delay is its floor. ]]
    describe("a warm-up rung's window", function()
      local function quick_ring(env)
        ring_in_bag(env)
        env.ext.activation_time = env.time - 18000 + 2
      end

      it("never fires sooner than the travel delay after the press", function()
        local service, env = world()
        quick_ring(env)
        service.warp(false)
        env.now = 1
        service.tick()
        env.time = env.time + 2
        env.ext.usable = true
        env.now = 2
        service.tick()
        env.now = 4
        service.tick()
        assert.are.same({ "gs disable ring1" }, env.commands, "warmed, and still held")
        env.now = 5
        service.tick()
        assert.are.same({ "gs disable ring1", 'input /item "Tavnazian Ring" <me>', "gs enable ring1" }, env.commands)
      end)

      it("counts the longer of the two down", function()
        local service, env = world()
        quick_ring(env)
        service.warp(false)
        env.now = 1
        service.tick()
        assert.is_not_nil(
          said(env):find("Tavnazian Ring ready in 4 seconds. /heal to cancel.", 1, true),
          "the hold outlasts a two-second warm-up: " .. said(env)
        )
      end)

      it("leaves a warm-up longer than the delay to set the pace", function()
        local service, env = world()
        ring_in_bag(env)
        service.warp(false)
        env.now = 1
        service.tick()
        assert.is_not_nil(said(env):find("Tavnazian Ring ready in 31 seconds", 1, true), said(env))
      end)

      it("fires the moment it is warm when the delay is off", function()
        local service, env = world()
        env.config.delay = 0
        quick_ring(env)
        service.warp(false)
        env.ext.usable = true
        env.now = 1
        service.tick()
        assert.are.equal('input /item "Tavnazian Ring" <me>', env.commands[2])
      end)

      it("does not give up on a delay longer than the item's own bound", function()
        local service, env = world()
        env.config.delay = 60
        quick_ring(env)
        service.warp(false)
        env.ext.usable = true
        for second = 1, 59 do
          env.time = env.time + 1
          env.now = second
          service.tick()
        end
        assert.is_nil(said(env):find("abandoned", 1, true), "said: " .. said(env))
        assert.are.same({ "gs disable ring1" }, env.commands, "held for the whole minute")
        env.now = 60
        service.tick()
        assert.are.equal('input /item "Tavnazian Ring" <me>', env.commands[2])
      end)

      --[[ The count started a second late - "ready in 4 seconds" for a
           five-second window - because nothing could be said until the
           ring was on and its extdata read (Kevin, live client,
           2026-09-13). The items resource names the equip delay itself,
           so the wait is known the moment the item is picked. ]]
      it("announces the wait at the press when the item names its equip delay", function()
        local service, env = world({ cast_delay = 3 })
        quick_ring(env)
        service.warp(false)
        assert.are.equal("Tavnazian Ring ready in 5 seconds. /heal to cancel.", env.chat[#env.chat])
        env.now = 1
        service.tick()
        env.now = 2
        service.tick()
        local _, announced = said(env):gsub("ready in", "")
        assert.are.equal(1, announced, "announced once, at the press")
        assert.are.equal("3...", env.chat[#env.chat])
      end)

      it("announces the item's own delay at the press when it outlasts the floor", function()
        local service, env = world({ cast_delay = 30 })
        ring_in_bag(env)
        service.warp(false)
        assert.are.equal("Tavnazian Ring ready in 30 seconds. /heal to cancel.", env.chat[#env.chat])
      end)

      it("says the wait again when the ring goes on late", function()
        local service, env = world({ cast_delay = 30 })
        ring_in_bag(env)
        env.equip_lands = false
        service.warp(false)
        local pressed = env.time
        for second = 1, 3 do
          env.time = pressed + second
          env.now = second
          service.tick()
        end
        -- It lands on the fourth second's re-equip, and warms from there.
        env.equip_lands = true
        env.time = pressed + 4
        env.now = 4
        service.tick()
        env.ext.activation_time = pressed + 4 + 30 - 18000
        env.time = pressed + 5
        env.now = 5
        service.tick()
        local _, announced = said(env):gsub("ready in", "")
        assert.are.equal(2, announced, "the press, then the correction: " .. said(env))
        assert.are.equal("Tavnazian Ring ready in 29 seconds. /heal to cancel.", env.chat[#env.chat])
      end)

      it("lets the wall clock lag a poll behind without saying the wait twice", function()
        -- The warm-up is read off the game's whole-second clock and the
        -- polls off the frame clock, so one poll can land before the wall
        -- second ticks over and read a second high.
        local service, env = world()
        ring_in_bag(env)
        service.warp(false)
        env.now = 0
        service.tick()
        env.now = 1
        service.tick()
        env.time = env.time + 2
        env.now = 2
        service.tick()
        local _, announced = said(env):gsub("ready in", "")
        assert.are.equal(1, announced, said(env))
      end)

      it("lets the first reading after the press run a second over in silence", function()
        local service, env = world({ cast_delay = 30 })
        ring_in_bag(env)
        env.ext.activation_time = env.time - 18000 + 30
        service.warp(false)
        env.now = 1
        service.tick()
        local _, announced = said(env):gsub("ready in", "")
        assert.are.equal(1, announced, said(env))
      end)

      it("does not repeat the wait for a ring that goes on in the ordinary time", function()
        --[[ The press-time figure starts counting before the ring is on,
             and the game stamps its warm-up in whole seconds: pressed late
             in one wall-clock second, landed early in the next, and read
             off a clock that has not ticked over, an ordinary equip reads
             a second over the promise before any rounding. ]]
        local service, env = world({ cast_delay = 30 })
        ring_in_bag(env)
        env.equip_lands = false
        local pressed = env.time
        service.warp(false)
        env.equip_lands = true
        env.now = 0.05
        service.tick()
        env.ext.activation_time = pressed + 1 + 30 - 18000
        env.time = pressed + 1
        env.now = 1.05
        service.tick()
        local _, announced = said(env):gsub("ready in", "")
        assert.are.equal(1, announced, said(env))
      end)

      it("leaves a ring already on to its own clock, whatever the resource says", function()
        -- Worn, the warm-up is already under way: the equip delay is the
        -- whole of it, not what is left of it.
        local service, env = world({ cast_delay = 30 })
        quick_ring(env)
        env.items[0][1].status = enchanted.EQUIPPED
        env.ext.activation_time = env.time - 18000 + 3
        service.warp(false)
        assert.is_nil(said(env):find("ready in", 1, true), "nothing promised at the press: " .. said(env))
        service.tick()
        assert.are.equal("Tavnazian Ring ready in 5 seconds. /heal to cancel.", env.chat[#env.chat])
      end)

      it("holds nothing on an alt sent home by `warp all`", function()
        -- The floor is the presser's window to call a trip off, and nobody
        -- pressed anything here - exactly why the alt's spell rung fires
        -- with no countdown either.
        local service, env = world()
        quick_ring(env)
        service.on_ipc(service.ipc_warp_message)
        env.ext.usable = true
        env.now = 1
        service.tick()
        assert.are.equal('input /item "Tavnazian Ring" <me>', env.commands[2])
      end)

      it("holds only a warp - an enchanted item is not a trip", function()
        local service, env = world()
        quick_ring(env)
        service.fire({ type = "enchanteditem", action = "Tavnazian Ring", target = "me" })
        env.ext.usable = true
        env.now = 1
        service.tick()
        assert.are.equal('input /item "Tavnazian Ring" <me>', env.commands[2])
      end)
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

    it("counts the settings window as a config mode, by its own name", function()
      local service, env = world()
      assert.is_nil(service.mode())
      env.settings_open = true
      assert.are.equal("//hud config", service.mode())
      service.warp(false)
      assert.is_not_nil(said(env):find("not while //hud config is open"), "said: " .. said(env))
      assert.is_false(service.travel.armed())
      env.layout = true
      assert.are.equal("//hud layout", service.mode(), "layout mode is asked first: entering it closes the window")
    end)

    it("calls a countdown off when the settings window opens under it", function()
      local service, env = world()
      service.warp(false)
      assert.is_true(service.travel.armed())
      env.settings_open = true
      service.tick()
      assert.is_false(service.travel.armed())
    end)

    it("says whether the settings window is open, for a bar deciding whether its binder may be", function()
      local service, env = world()
      assert.is_false(service.settings_open())
      env.settings_open = true
      assert.is_true(service.settings_open())
      local unwired = require("lib/actionbar/service")({})
      assert.is_false(unwired.settings_open(), "a service nobody told about the window has none open")
    end)

    it("does not dress the bars for the settings window", function()
      local service, env = world()
      env.settings_open = true
      assert.is_nil(service.edit_owner(), "a bar asks this to know whether a binder is up")
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

    it("drops a countdown only under suppression", function()
      local service, env = world()
      service.warp(false)
      assert.is_true(service.travel.armed())
      service.bar_hidden()
      assert.is_true(service.travel.armed(), "a user hide is not a change of mind about a warp")
      env.suppressed = true
      service.bar_hidden()
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

  describe("the bars as each other's drop targets", function()
    local function bar_hooks(log, name, rect)
      return {
        slot_at = function(x, y)
          log[#log + 1] = name .. " asked"
          return x == 10 and y == 20 and rect or nil
        end,
        bindings = function()
          return name .. " model"
        end,
        repaint = function()
          log[#log + 1] = name .. " repainted"
        end,
      }
    end

    it("answers the OTHER bar's slot under a point, never the asker's own", function()
      local service = world()
      local log = {}
      local rect = { set = 3, side = "row", slot = 7, x = 0, y = 0, width = 40, height = 40 }
      service.register_bar("crossbar", bar_hooks(log, "crossbar", { set = 1, side = "left", slot = 1 }))
      service.register_bar("hotbar", bar_hooks(log, "hotbar", rect))
      local target = service.drop_target_at("crossbar", 10, 20)
      assert.are.equal("hotbar", target.bar)
      assert.are.equal(3, target.set)
      assert.are.equal("row", target.side)
      assert.are.equal(7, target.slot)
      assert.are.equal(rect, target.rect)
      assert.are.equal("hotbar model", target.bindings)
      assert.are.same({ "hotbar asked" }, log, "the asker's own slots are its binder's to hit-test")
      target.repaint()
      assert.are.equal("hotbar repainted", log[#log])
    end)

    it("answers nothing where no other bar has a slot", function()
      local service = world()
      local log = {}
      assert.is_nil(service.drop_target_at("crossbar", 10, 20), "with no bar registered at all")
      service.register_bar("crossbar", bar_hooks(log, "crossbar", { set = 1, side = "left", slot = 1 }))
      service.register_bar("hotbar", bar_hooks(log, "hotbar", { set = 3, side = "row", slot = 7 }))
      assert.is_nil(service.drop_target_at("crossbar", 11, 20))
    end)

    it("replaces a bar registered twice rather than asking it twice", function()
      local service = world()
      local log = {}
      service.register_bar("hotbar", bar_hooks(log, "hotbar", nil))
      service.register_bar("hotbar", bar_hooks(log, "hotbar", { set = 3, side = "row", slot = 7 }))
      assert.is_not_nil(service.drop_target_at("crossbar", 10, 20))
      assert.are.same({ "hotbar asked" }, log)
    end)

    it("names the bar a point falls on, the asker's own as much as another", function()
      -- A drop that lands on a bar but on no slot of it is a miss, and
      -- whose bar it was makes no difference to that.
      local service = world()
      assert.is_nil(service.bar_at(10, 20), "with no bar registered at all")
      for _, name in ipairs({ "crossbar", "hotbar" }) do
        local hooks = bar_hooks({}, name)
        hooks.covers = function(x)
          return name == "hotbar" and x == 10
        end
        service.register_bar(name, hooks)
      end
      assert.are.equal("hotbar", service.bar_at(10, 20))
      assert.is_nil(service.bar_at(11, 20))
    end)

    it("repaints every other bar when a binder opens or closes", function()
      -- The others dress as drop targets for as long as it is open, and
      -- nothing else tells them it has.
      local service = world()
      local log = {}
      service.register_bar("crossbar", bar_hooks(log, "crossbar"))
      service.register_bar("hotbar", bar_hooks(log, "hotbar"))
      service.set_edit_mode("crossbar", true)
      assert.are.same({ "hotbar repainted" }, log, "the owner repaints itself")
      service.set_edit_mode("crossbar", false)
      assert.are.same({ "hotbar repainted", "hotbar repainted" }, log)
    end)
  end)

  describe("one edit mode over every bar", function()
    -- A bar as the service sees it for this: a binder it can open or close,
    -- and the window that binder has on screen.
    local function editable(log, name, opts)
      opts = opts or {}
      return {
        slot_at = function() end,
        bindings = function() end,
        repaint = function() end,
        open_edit = function()
          log[#log + 1] = name .. " asked to open"
          return opts.opens ~= false
        end,
        close_edit = function()
          log[#log + 1] = name .. " closed"
        end,
        window = function()
          return opts.window
        end,
      }
    end

    it("opens every OTHER bar's binder beside the asker's and names the ones that came up", function()
      local service = world()
      local log = {}
      service.register_bar("crossbar", editable(log, "crossbar"))
      service.register_bar("hotbar", editable(log, "hotbar"))
      service.register_bar("third", editable(log, "third", { opens = false }))
      assert.are.same({ "hotbar" }, service.open_edit_with("crossbar"))
      assert.are.same({ "hotbar asked to open", "third asked to open" }, log, "the asker opens its own")
    end)

    it("closes every bar's binder, the asker's included", function()
      local service = world()
      local log = {}
      service.register_bar("crossbar", editable(log, "crossbar"))
      service.register_bar("hotbar", editable(log, "hotbar"))
      service.close_edit_all()
      assert.are.same({ "crossbar closed", "hotbar closed" }, log)
    end)

    it("names the OTHER bar whose window is over a point", function()
      -- Two binders each hit-test their own window and nobody else's, so a
      -- click on one bar's window would be the other's click on the slot
      -- beneath it.
      local service = world()
      local window = { x = 500, y = 240, width = 920, height = 600 }
      service.register_bar("crossbar", editable({}, "crossbar", { window = window }))
      service.register_bar("hotbar", editable({}, "hotbar"))
      assert.are.equal("crossbar", service.window_at("hotbar", 900, 516))
      assert.is_nil(service.window_at("hotbar", 499, 516), "clear of it")
      assert.is_nil(service.window_at("hotbar", 1420, 516), "the far edge is outside")
      assert.is_nil(service.window_at("crossbar", 900, 516), "its own window is its binder's to hit-test")
    end)

    describe("where two bars' slots overlap", function()
      -- One point, a slot of each bar on it. The bar registered LATER is
      -- the one built later and so drawn on top, and what is on top is
      -- what the player is pointing at - core's own rule for anchors.
      local function overlapping(names)
        local service = world()
        local asked = {}
        for _, name in ipairs(names) do
          local hooks = editable({}, name)
          hooks.slot_at = function(x, y)
            asked[#asked + 1] = name
            return x == 10 and y == 20 and { set = 1, side = name, slot = 1 } or nil
          end
          service.register_bar(name, hooks)
        end
        return service, asked
      end

      it("names the bar drawn over the asker's slot, and none for the bar on top", function()
        local service = overlapping({ "crossbar", "hotbar" })
        assert.are.equal("hotbar", service.slot_above("crossbar", 10, 20))
        assert.is_nil(service.slot_above("hotbar", 10, 20), "nothing is drawn over the last bar")
        assert.is_nil(service.slot_above("crossbar", 11, 20), "nor over a point the other has no slot on")
      end)

      it("counts only bars in edit mode when asked to", function()
        -- A press is only worth yielding to a binder that can take it.
        local service = overlapping({ "crossbar", "hotbar" })
        assert.is_nil(service.slot_above("crossbar", 10, 20, true))
        service.set_edit_mode("hotbar", true)
        assert.are.equal("hotbar", service.slot_above("crossbar", 10, 20, true))
      end)

      it("answers a drop with the topmost of the other bars", function()
        local service, asked = overlapping({ "crossbar", "hotbar", "third" })
        assert.are.equal("third", service.drop_target_at("crossbar", 10, 20).bar)
        assert.are.same({ "third" }, asked)
        assert.are.equal("hotbar", service.drop_target_at("third", 10, 20).bar)
      end)
    end)

    it("stands every OTHER bar's binder down when one opens its window", function()
      -- One window, by construction rather than by every path to a second
      -- one happening to be closed.
      local service = world()
      local log = {}
      for _, name in ipairs({ "crossbar", "hotbar", "third" }) do
        local hooks = editable(log, name)
        hooks.stand_down = function()
          log[#log + 1] = name .. " stood down"
        end
        service.register_bar(name, hooks)
      end
      service.window_opened("hotbar")
      assert.are.same({ "crossbar stood down", "third stood down" }, log)
    end)

    it("takes a bar that registered none of this as a bar with nothing to open", function()
      local service = world()
      service.register_bar("crossbar", { slot_at = function() end, repaint = function() end })
      assert.are.same({}, service.open_edit_with("hotbar"))
      assert.has_no.errors(service.close_edit_all)
      assert.is_nil(service.window_at("hotbar", 900, 516))
      assert.has_no.errors(function()
        service.window_opened("hotbar")
      end)
    end)
  end)

  describe("the rest of its surface", function()
    it("sheathes in game on the sword's click, one way", function()
      local service, env = world()
      service.sheathe()
      assert.are.same({ "input /attack off" }, env.commands)
      assert.are.equal("sheathed", service.weapon_state())
    end)

    it("draws on the sword's click, one way and sending nothing", function()
      -- Mounted would make the draw toggle dismount; this reads no state.
      local service, env = world()
      env.player.buffs = { 252 }
      service.draw()
      assert.are.same({}, env.commands)
      assert.are.equal("drawn", service.weapon_state())
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
      assert.are.equal(5, defaults.delay)
      assert.is_nil(defaults.retry, "the cast retry is gone")
      assert.is_nil(defaults.wsgate, "the weaponskill gate is gone")
    end)
  end)

  describe("the action queue", function()
    local ACTION, ZONE_OUT, MESSAGE = 0x028, 0x0B, 0x029
    local CURE = { type = "ma", action = "Cure", target = "me" }
    local CURE_COMMAND = 'input /ma "Cure" <me>'

    local function queued(mode)
      local service, env = world()
      env.config.queue = mode or "on"
      return service, env
    end

    local function act(category, param)
      return { actor_id = 777, category = category, param = param or 0, targets = {} }
    end

    local function start_cast(service)
      service.on_chunk(ACTION, "raw", act(8, 24931))
    end

    -- A cast's finish, with the start the game always sends ahead of one.
    local function finish_cast(service)
      start_cast(service)
      service.on_chunk(ACTION, "raw", act(4, 1))
    end

    -- Past what a spell locks for.
    local function past_the_lock(service, env)
      env.now = env.now + 3.01
      service.tick()
    end

    it("names its mode among the tuning core seeds, shipping off", function()
      local service = world()
      assert.are.equal("off", service.config_defaults().queue)
    end)

    it("reads its mode off the config core keeps", function()
      local service, env = world()
      assert.are.equal("off", service.queue.mode())
      env.config.queue = "debug"
      assert.are.equal("debug", service.queue.mode())
    end)

    for _, named in ipairs({
      { category = 3, id = 1, name = "Cure", kind = "spell" },
      { category = 7, id = 42, name = "Savage Blade", kind = "weaponskill" },
      { category = 9, id = 605, name = "Provoke", kind = "ability" },
    }) do
      it("names a " .. named.kind .. " going out in its debug line", function()
        local service, env = queued("debug")
        local param = string.char(named.id % 256, math.floor(named.id / 256))
        service.on_outgoing(
          0x01A,
          string.rep("\0", 10) .. string.char(named.category, 0) .. param .. string.rep("\0", 14)
        )
        assert.is_not_nil(logged(env):find("out " .. named.kind .. " " .. named.name, 1, true))
      end)
    end

    it("hands its debug lines to the log and never to chat", function()
      local service, env = queued("debug")
      start_cast(service)
      assert.is_not_nil(logged(env):find("start spell", 1, true))
      assert.are.equal("", said(env))
    end)

    it("copes with no log, as a spec's ctx has none", function()
      local service, env = world({ no_debug_log = true })
      env.config.queue = "debug"
      assert.has_no.errors(function()
        start_cast(service)
      end)
    end)

    it("sends a press at once while off, whatever is casting", function()
      local service, env = world()
      start_cast(service)
      service.fire(CURE, {})
      assert.are.same({ CURE_COMMAND }, env.commands)
    end)

    it("sends a press at once while nothing is busy", function()
      local service, env = queued()
      service.fire(CURE, {})
      assert.are.same({ CURE_COMMAND }, env.commands)
    end)

    it("holds a press through the cast and sends it the tick the lock clears", function()
      local service, env = queued()
      start_cast(service)
      service.fire(CURE, {})
      assert.are.same({}, env.commands)
      finish_cast(service)
      service.tick()
      assert.are.same({}, env.commands, "the lock is still running")
      past_the_lock(service, env)
      assert.are.same({ CURE_COMMAND }, env.commands)
    end)

    it("flashes a held press, which is the only sign it was taken", function()
      local service = queued()
      start_cast(service)
      local flashed = false
      service.fire(CURE, {
        flash = function()
          flashed = true
        end,
      })
      assert.is_true(flashed)
    end)

    it("pins a target at the press", function()
      local service, env = queued()
      env.target = { id = 99 }
      start_cast(service)
      service.fire({ type = "ma", action = "Cure", target = "t" }, {})
      env.target = { id = 5 }
      finish_cast(service)
      past_the_lock(service, env)
      assert.are.same({ 'input /ma "Cure" 99' }, env.commands)
    end)

    it("holds a slot with no target and sends it verbatim", function()
      local service, env = queued()
      start_cast(service)
      service.fire({ type = "ma", action = "Cure" }, {})
      finish_cast(service)
      past_the_lock(service, env)
      assert.are.same({ 'input /ma "Cure"' }, env.commands)
    end)

    it("sends a target it cannot pin as it always did", function()
      local service, env = queued()
      start_cast(service)
      service.fire({ type = "ma", action = "Cure", target = "ft" }, {})
      assert.are.same({ 'input /ma "Cure" <ft>' }, env.commands)
    end)

    describe("a cursor slot", function()
      local SHELL = { type = "ma", action = "Cure", target = "stpc" }

      it("opens over /ta while nothing is busy too", function()
        local service, env = queued()
        service.fire(SHELL, {})
        assert.are.same({ "input /ta <stpc>" }, env.commands)
      end)

      it("sends nothing for a press with the arrow up, reading it off <st>", function()
        local service, env = queued()
        service.fire(SHELL, {})
        env.subtarget = { id = 5 }
        service.fire(SHELL, {})
        assert.are.same({ "input /ta <stpc>" }, env.commands)
      end)

      it("goes as it always did with the queue off", function()
        local service, env = world()
        service.fire(SHELL, {})
        assert.are.same({ 'input /ma "Cure" <stpc>' }, env.commands)
      end)

      it("opens over /ta while busy, holds at OK and casts when the lock clears", function()
        local service, env = queued()
        finish_cast(service)
        service.fire(SHELL, {})
        assert.are.same({ "input /ta <stpc>" }, env.commands)
        assert.is_falsy(service.on_text("/ta <stpc>"))
        assert.is_falsy(service.on_text("/ta 777"))
        assert.is_true(service.on_text("/ta 12345"), "OK never reaches the game")
        assert.are.same({ "input /ta <stpc>" }, env.commands, "held")
        past_the_lock(service, env)
        assert.are.same({ "input /ta <stpc>", 'input /ma "Cure" 12345' }, env.commands)
      end)

      it("sends at OK when the lock cleared first", function()
        local service, env = queued()
        finish_cast(service)
        service.fire(SHELL, {})
        service.on_text("/ta 777")
        past_the_lock(service, env)
        assert.is_true(service.on_text("/ta 12345"))
        assert.are.same({ "input /ta <stpc>", 'input /ma "Cure" 12345' }, env.commands)
      end)

      it("still flashes, the only sign the press was taken", function()
        local service = queued()
        finish_cast(service)
        local flashed = false
        service.fire(SHELL, {
          flash = function()
            flashed = true
          end,
        })
        assert.is_true(flashed)
      end)
    end)

    it("leaves a spell on its own recast to the game", function()
      local service, env = queued()
      env.spell_recasts[1] = 120
      start_cast(service)
      service.fire(CURE, {})
      assert.are.same({ CURE_COMMAND }, env.commands)
    end)

    it("reads a spell's recast in seconds, from the frames the client reports", function()
      local service, env = queued()
      finish_cast(service)
      env.spell_recasts[1] = 120
      service.fire(CURE, {})
      assert.are.same({}, env.commands, "two seconds ends inside the lock")
      assert.are.equal(CURE_COMMAND, service.queue.held().command)
    end)

    it("leaves a spell whose recast outlasts the lock to the game", function()
      local service, env = queued()
      finish_cast(service)
      env.spell_recasts[1] = 180
      service.fire(CURE, {})
      assert.are.same({ CURE_COMMAND }, env.commands)
    end)

    it("reads an ability's recast in seconds as it comes", function()
      local service, env = queued()
      finish_cast(service)
      env.ability_recasts[5] = 2
      service.fire({ type = "ja", action = "Provoke", target = "t" }, {})
      assert.are.same({}, env.commands, "held")
      assert.is_not_nil(service.queue.held())
    end)

    it("leaves an ability whose recast outlasts the lock to the game", function()
      local service, env = queued()
      finish_cast(service)
      env.ability_recasts[5] = 3
      service.fire({ type = "ja", action = "Provoke", target = "t" }, {})
      assert.are.same({ 'input /ja "Provoke" <t>' }, env.commands)
    end)

    it("sends the next press at once after one on its own recast, which GearSwap may have cancelled", function()
      local service, env = queued()
      env.spell_recasts[1] = 120
      service.fire(CURE, {})
      env.commands = {}
      service.fire({ type = "ja", action = "Provoke", target = "t" }, {})
      assert.are.same({ 'input /ja "Provoke" <t>' }, env.commands)
    end)

    it("reads a recast table the client did not answer as no recast", function()
      local service, env = queued()
      env.spell_recasts = nil
      start_cast(service)
      service.fire(CURE, {})
      assert.are.same({}, env.commands)
      assert.are.equal(CURE_COMMAND, service.queue.held().command)
    end)

    it("reads an ability's recast from the ability table", function()
      local service, env = queued()
      env.ability_recasts[5] = 30
      start_cast(service)
      service.fire({ type = "ja", action = "Provoke", target = "t" }, {})
      assert.are.same({ 'input /ja "Provoke" <t>' }, env.commands)
    end)

    --[[ These share one recast across a family with charges, so the timer
         running says a charge was spent, not that none is left: the slot stays
         bright under it, and a chain of them is what the queue is for. ]]
    for _, charged in ipairs({
      { type = "ja", name = "Penury", recast_id = 231 },
      { type = "ja", name = "Fire Shot", recast_id = 195 },
      { type = "pet", name = "Foot Kick", recast_id = 102 },
      { type = "pet", name = "Ready", recast_id = 255 },
    }) do
      it("holds " .. charged.name .. " under its shared recast, and sends it", function()
        local service, env = queued()
        env.ability_recasts[charged.recast_id] = 48
        start_cast(service)
        service.fire({ type = charged.type, action = charged.name, target = "me" }, {})
        assert.are.same({}, env.commands)
        finish_cast(service)
        past_the_lock(service, env)
        assert.are.same({ "input /" .. charged.type .. ' "' .. charged.name .. '" <me>' }, env.commands)
      end)
    end

    it("keeps that to abilities: a spell on the same number is on its own recast", function()
      local service, env = queued()
      env.spell_recasts[231] = 120
      start_cast(service)
      service.fire(CURE, {})
      service.fire({ type = "ma", action = "Bio II", target = "me" }, {})
      assert.are.same({ 'input /ma "Bio II" <me>' }, env.commands)
      assert.are.equal(CURE_COMMAND, service.queue.held().command, "and what was held survives it")
    end)

    it("reads a pet command's recast from the ability table", function()
      local service, env = queued()
      env.ability_recasts[100] = 10
      start_cast(service)
      service.fire({ type = "pet", action = "Fight", target = "t" }, {})
      assert.are.same({ 'input /pet "Fight" <t>' }, env.commands)
    end)

    it("drops a held press whose recast is running when the lock clears", function()
      local service, env = queued()
      start_cast(service)
      service.fire(CURE, {})
      finish_cast(service)
      env.spell_recasts[1] = 120
      past_the_lock(service, env)
      env.spell_recasts[1] = 0
      env.now = env.now + 5
      service.tick()
      assert.are.same({}, env.commands)
    end)

    it("reads no recast for a weaponskill, which has none", function()
      local service, env = queued()
      start_cast(service)
      service.fire({ type = "ws", action = "Savage Blade", target = "t" }, {})
      assert.are.same({}, env.commands)
    end)

    it("holds a spell the resources do not know, having no recast to read", function()
      local service, env = queued()
      start_cast(service)
      service.fire({ type = "ma", action = "Nonesuch", target = "me" }, {})
      assert.are.same({}, env.commands)
    end)

    it("leaves a travel press to the countdown", function()
      local service, env = queued()
      start_cast(service)
      service.fire({ type = "mount", action = "Chocobo" }, {})
      assert.is_true(service.travel.armed())
      assert.is_nil(service.queue.held())
      assert.are.same({}, env.commands)
    end)

    it("hears what goes out, whoever sent it", function()
      local service, env = queued()
      service.on_outgoing(0x01A, string.rep("\0", 10) .. string.char(3, 0) .. string.rep("\0", 16))
      service.fire(CURE, {})
      assert.are.same({}, env.commands)
    end)

    it("hears a refusal off the action message", function()
      local service, env = queued()
      service.on_outgoing(0x037, "item use")
      local actor = string.char(777 % 256, math.floor(777 / 256), 0, 0)
      service.on_chunk(MESSAGE, string.rep("\0", 4) .. actor .. string.rep("\0", 16) .. string.char(17, 0, 0, 0), nil)
      service.fire(CURE, {})
      assert.are.same({ CURE_COMMAND }, env.commands)
    end)

    it("still feeds the skillchain engine the action message", function()
      local service, env = queued()
      local fed = {}
      service.skillchain.on_chunk = function(id)
        fed[#fed + 1] = id
      end
      service.on_chunk(MESSAGE, "short", nil)
      assert.are.same({ MESSAGE }, fed)
      assert.are.same({}, env.commands)
    end)

    describe("a ladder slot", function()
      local INVISIBLE = { type = "invisible" }
      local INVISIBLE_LINE = 'input /magic "Invisible" <me>'

      local function knows_invisible(env)
        env.known_spells[136] = true
      end

      it("holds the rung it picked through a lock, and sends it when the lock clears", function()
        local service, env = queued()
        knows_invisible(env)
        finish_cast(service)
        service.fire(INVISIBLE)
        assert.are.same({}, env.commands)
        past_the_lock(service, env)
        assert.are.same({ INVISIBLE_LINE }, env.commands)
      end)

      it("goes at once with nothing busy", function()
        local service, env = queued()
        knows_invisible(env)
        service.fire(INVISIBLE)
        assert.are.same({ INVISIBLE_LINE }, env.commands)
      end)

      it("names the rung, not the slot", function()
        local service, env = queued("debug")
        knows_invisible(env)
        finish_cast(service)
        service.fire(INVISIBLE)
        assert.is_not_nil(logged(env):find("hold Invisible", 1, true))
      end)

      it("leaves a rung on its recast to the game, as any slot of it", function()
        local service, env = queued()
        knows_invisible(env)
        env.spell_recasts[136] = 300
        finish_cast(service)
        service.fire(INVISIBLE)
        assert.are.same({ INVISIBLE_LINE }, env.commands)
      end)

      it("pins a party member it aims at, as any held press", function()
        local service, env = queued()
        knows_invisible(env)
        env.target = { id = 99, in_party = true }
        finish_cast(service)
        service.fire(INVISIBLE)
        past_the_lock(service, env)
        assert.are.same({ 'input /magic "Invisible" 99' }, env.commands)
      end)

      it("holds a consumable the ladder fell through to", function()
        local service, env = queued()
        finish_cast(service)
        service.fire(INVISIBLE)
        assert.are.same({}, env.commands)
        past_the_lock(service, env)
        assert.are.same({ 'input /item "Prism Powder" <me>' }, env.commands)
      end)

      it("says the ladder's hint at once when it finds nothing", function()
        local service, env = queued()
        env.player.buffs = { 113 }
        finish_cast(service)
        service.fire({ type = "reraise" })
        assert.is_not_nil(said(env):find("Reraise is already active", 1, true))
      end)

      it("goes as it always did with the queue off", function()
        local service, env = queued("off")
        knows_invisible(env)
        finish_cast(service)
        service.fire(INVISIBLE)
        assert.are.same({ INVISIBLE_LINE }, env.commands)
      end)

      it("leaves the typed verb alone, as every typed command is", function()
        local service, env = queued()
        knows_invisible(env)
        finish_cast(service)
        service.builtin("invisible")
        assert.are.same({ INVISIBLE_LINE }, env.commands)
      end)
    end)

    describe("what ends a held press", function()
      local function holding()
        local service, env = queued()
        finish_cast(service)
        service.fire(CURE, {})
        return service, env
      end

      local function nothing_goes(service, env)
        past_the_lock(service, env)
        assert.are.same({}, env.commands)
      end

      it("a zone", function()
        local service, env = holding()
        service.on_chunk(ZONE_OUT, "raw", nil)
        assert.is_false(service.queue.busy(), "the lock goes with it")
        nothing_goes(service, env)
      end)

      it("a death", function()
        local service, env = holding()
        service.on_status(2)
        assert.is_false(service.queue.busy(), "the lock goes with it")
        nothing_goes(service, env)
      end)

      it("a job change", function()
        local service, env = holding()
        service.on_job_change()
        assert.is_false(service.queue.busy(), "the lock goes with it")
        nothing_goes(service, env)
      end)

      it("a logout", function()
        local service, env = holding()
        service.on_logout()
        assert.is_false(service.queue.busy(), "the lock goes with it")
        nothing_goes(service, env)
      end)

      it("an unload", function()
        local service, env = holding()
        service.on_unload()
        assert.is_false(service.queue.busy(), "the lock goes with it")
        nothing_goes(service, env)
      end)

      it("a bar's re-attach, which replaced what it was bound to", function()
        local service, env = holding()
        service.drop_trip()
        assert.is_true(service.queue.busy(), "the lock is the player's")
        nothing_goes(service, env)
      end)

      it("layout mode", function()
        local service, env = holding()
        env.layout = true
        service.tick()
        env.layout = false
        nothing_goes(service, env)
      end)

      it("the settings window", function()
        local service, env = holding()
        env.settings_open = true
        service.tick()
        env.settings_open = false
        nothing_goes(service, env)
      end)

      it("suppression", function()
        local service, env = holding()
        env.suppressed = true
        service.tick()
        env.suppressed = false
        nothing_goes(service, env)
      end)

      it("the queue being switched off", function()
        local service, env = holding()
        env.config.queue = "off"
        nothing_goes(service, env)
      end)
    end)

    it("does not hold a press under a config mode, which goes out as it always did", function()
      local service, env = queued()
      env.layout = true
      start_cast(service)
      service.fire(CURE, {})
      assert.are.same({ CURE_COMMAND }, env.commands)
    end)

    it("does not end a trip for a held press, or the reverse", function()
      local service, env = queued()
      start_cast(service)
      service.fire(CURE, {})
      service.warp(false)
      assert.is_true(service.travel.armed())
      service.on_chunk(ACTION, "raw", act(4, 1))
      assert.is_true(service.travel.armed())
      assert.are.equal(CURE_COMMAND, service.queue.held().command)
      assert.are.same({}, env.commands)
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
