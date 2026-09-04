--[[ Boots src/XIVHud.lua itself, under a fake Windower.

     The entry point is the one file that reads Windower globals, so until now
     nothing here ran it -- tests/sources_spec.lua only proves it compiles. But
     its `incoming chunk` handler now carries a decision (which ids are
     pre-parsed, and with which parser) that no component spec can see, so the
     wiring needs coverage of its own.

     The trick is Lua 5.1's setfenv: the chunk is loaded, given an environment
     whose `windower`, `io` and `require` are ours, and run. Assignments the
     addon makes to globals (texts, images, res, packets) land in that
     environment rather than in _G, so nothing leaks between specs.

     WHAT IS FAKED, AND WHERE IT DIVERGES FROM THE CLIENT -- this is the entry
     point's first behavioural coverage, and a fake that quietly asserts a
     fiction is worse than no coverage at all:

       - `windower.register_event` only records the handler and hands back an
         id. The real one also decides the ORDER handlers run in and can be
         unregistered mid-event; nothing about ordering is testable from here.
       - `windower.packets.parse_action` returns whatever the spec sets. The
         real one decodes 0x028 into a category/param/targets tree, and what
         it does with a packet it cannot read is not something this container
         can establish -- so `action_raises` covers the throw the entry point
         already pcalls against.
       - `packets.parse` likewise returns a marker table, not a decoded
         packet: what the pre-parse is asserted on is WHICH ids reach WHICH
         parser, never the decode itself (partylist_packets_spec owns that).
       - `io` is in memory. The addon traces every load step to load.log, and
         a spec must not put that on disk.
       - lib/core and every component factory are stubs, so this exercises the
         wiring alone: what the entry point registers, what it builds each ctx
         out of, and what it dispatches. Component behaviour belongs in the
         component's own spec.
       - lib/guard and components/partylist/packets are the REAL modules: both
         are pure, and the guard's wrapping is part of what a handler does.

     The addon is booted as a fully working install: no safe_mode file, every
     library present. A spec wanting a degraded one passes `options`. ]]

local M = {}

local ENTRY_POINT = "src/XIVHud.lua"

-- The Windower libraries the addon require()s, and the internal modules it is
-- not this harness's job to exercise. Anything not named here falls through to
-- the real require.
local function build_stubs(boot, options)
  local function component(name)
    return function(ctx)
      boot.ctxs[name] = ctx
      boot.built[#boot.built + 1] = name
      return { name = ctx.name or name }
    end
  end

  local stubs = {
    texts = {
      new = function()
        return {}
      end,
    },
    images = {
      new = function()
        return {}
      end,
    },
    resources = { spells = {}, monster_abilities = {} },
    packets = {
      parse = function(direction, data)
        boot.parsed_packets[#boot.parsed_packets + 1] = { direction = direction, data = data }
        return { packet = data }
      end,
    },
    extdata = {
      decode = function()
        return nil
      end,
    },
    ["lib/core"] = function(deps)
      boot.core_deps = deps
      return boot.core
    end,
    ["components/parambar/parambar"] = component("parambar"),
    ["components/partylist/partylist"] = component("partylist"),
    ["components/statusbar/statusbar"] = component("statusbar"),
    ["components/giltracker/giltracker"] = component("giltracker"),
    ["components/equipviewer/equipviewer"] = component("equipviewer"),
    ["components/targetbar/targetbar"] = component("targetbar"),
    ["components/crossbar/crossbar"] = component("crossbar"),
    ["components/speedcheck/speedcheck"] = component("speedcheck"),
    ["components/expbar/expbar"] = component("expbar"),
  }

  for name, failure in pairs(options.require_fails or {}) do
    stubs[name] = nil
    boot.require_fails[name] = failure
  end

  return stubs
end

-- In-memory io. Only the calls the load path makes are supported: the trace
-- writes, the safe_mode probe and read_file.
local function build_io(boot)
  local function handle(path, mode)
    local buffer = {}
    return {
      write = function(_, text)
        buffer[#buffer + 1] = text
      end,
      read = function()
        return boot.files[path]
      end,
      seek = function() end,
      close = function()
        if mode:find("w") or mode:find("a") then
          local existing = (mode:find("a") and boot.files[path]) or ""
          boot.files[path] = existing .. table.concat(buffer)
        end
      end,
    }
  end

  return {
    open = function(path, mode)
      mode = mode or "r"
      boot.opens[#boot.opens + 1] = { path = path, mode = mode }
      if mode:find("r") and boot.files[path] == nil then
        return nil, path .. ": No such file or directory"
      end
      return handle(path, mode)
    end,
  }
end

local function build_windower(boot)
  return {
    addon_path = "addons/XIVHud/",
    windower_path = "Windower4/",
    ffxi_path = "FFXI/",
    pol_path = "POL/",
    register_event = function(name, handler)
      boot.handlers[name] = handler
      boot.registrations[#boot.registrations + 1] = name
      return #boot.registrations
    end,
    unregister_event = function(id)
      boot.unregistered[#boot.unregistered + 1] = id
    end,
    add_to_chat = function(_, message)
      boot.chat[#boot.chat + 1] = message
    end,
    dir_exists = function()
      return true
    end,
    create_dir = function()
      return true
    end,
    get_dir = function()
      return {}
    end,
    get_windower_settings = function()
      return { ui_x_res = 1920, ui_y_res = 1080 }
    end,
    send_command = function() end,
    send_ipc_message = function() end,
    -- Core API, not a library: available even when resources/packets did not
    -- load, which is why the action packet can be parsed at all in that case.
    packets = {
      parse_action = function(data)
        boot.action_parses[#boot.action_parses + 1] = data
        if boot.action_raises then
          error("cannot read that packet")
        end
        return boot.action
      end,
      --[[ The client answers (data, timestamp); the addon passes on the data
           alone. `boot.last_incoming_raises` stands in for a client where
           windower.packets is not there at all, which is the case the pcall
           around it exists for. ]]
      last_incoming = function(id)
        boot.last_incoming_asked[#boot.last_incoming_asked + 1] = id
        if boot.last_incoming_raises then
          error("no such packet table")
        end
        return boot.last_incoming[id], 12345
      end,
    },
    --[[ The four reads the player service caches are counted, because how many
         of them reach the client is exactly what that service is for and is
         invisible from any component spec. ]]
    ffxi = {
      get_player = function()
        boot.client_calls.player = boot.client_calls.player + 1
        return boot.player
      end,
      get_mob_by_target = function(...)
        boot.client_calls.mob = boot.client_calls.mob + 1
        return boot.mobs[(...)]
      end,
      get_party = function()
        boot.client_calls.party = boot.client_calls.party + 1
        return boot.party
      end,
      get_info = function()
        boot.client_calls.info = boot.client_calls.info + 1
        return { logged_in = true, chat_open = false }
      end,
      get_items = function()
        return {}
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
        return {}
      end,
      get_abilities = function()
        return {}
      end,
      set_equip = function() end,
    },
  }
end

local function build_core(boot)
  local core = {}

  function core.register(widget)
    boot.registered[#boot.registered + 1] = widget.name
  end

  -- Every argument is kept, `n` included: whether the fourth one is nil or
  -- absent is exactly what the pre-parse specs turn on.
  function core.dispatch(event, ...)
    boot.dispatches[#boot.dispatches + 1] = { event = event, n = select("#", ...), ... }
  end

  --[[ Stands in for a component reading the target during its per-frame update.
       What that buys a spec is the ordering of `begin_frame` against
       `core.on_prerender`: a component must never see the memo a key press
       filled during the previous frame. ]]
  function core.on_prerender()
    local component = boot.ctxs.targetbar
    if component ~= nil and component.get_mob_by_target ~= nil then
      boot.prerender_targets[#boot.prerender_targets + 1] = component.get_mob_by_target("t")
    end
  end

  function core.wants_keyboard()
    return false
  end

  function core.wants_mouse()
    return false
  end

  for _, name in ipairs({
    "suppressed",
    "component_visible",
    "layout_active",
    "on_command",
    "on_load",
    "on_unload",
    "on_login",
    "on_logout",
    -- on_prerender is NOT here: it has a real stub above, which reads a target
    -- the way a component would so a spec can pin the frame memo's clearing
    -- against it. A no-op here would silently overwrite it.
    "on_status_change",
    "on_zone_change",
    "character",
  }) do
    core[name] = function()
      return nil
    end
  end

  return core
end

--[[ Runs the entry point and returns the recorder. `options`:
       files         - seeded in-memory files (an entry named
                       "addons/XIVHud/safe_mode" boots the addon in safe mode)
       require_fails - module name -> message, for a library that will not load ]]
function M.boot(options)
  options = options or {}

  local boot = {
    files = options.files or {},
    opens = {},
    handlers = {},
    registrations = {},
    unregistered = {},
    chat = {},
    ctxs = {},
    built = {},
    registered = {},
    dispatches = {},
    parsed_packets = {},
    action_parses = {},
    require_fails = {},
    -- What the fake windower.packets.parse_action answers with.
    action = { category = 8, param = 0, targets = {} },
    action_raises = false,
    -- What the fake windower.packets.last_incoming answers with, per id.
    last_incoming = {},
    last_incoming_asked = {},
    last_incoming_raises = false,
    player = { name = "Tester", vitals = { hp = 1000, hpp = 100, mp = 500, mpp = 100, tp = 0 } },
    party = {},
    mobs = { t = { id = 7 } },
    client_calls = { player = 0, party = 0, info = 0, mob = 0 },
    prerender_targets = {},
  }

  boot.core = build_core(boot)

  local stubs = build_stubs(boot, options)
  local real_require = require

  local env = {
    _addon = {},
    io = build_io(boot),
    windower = build_windower(boot),
    require = function(name)
      local failure = boot.require_fails[name]
      if failure then
        error(failure, 0)
      end
      local stub = stubs[name]
      if stub ~= nil then
        return stub
      end
      -- lib/guard and components/partylist/packets: real, and pure.
      return real_require(name)
    end,
  }
  setmetatable(env, { __index = _G })

  local chunk = assert(loadfile(ENTRY_POINT))
  setfenv(chunk, env)
  chunk()

  boot.env = env

  -- The registered handler for an event. Handlers are guard-wrapped, so
  -- calling one can never throw -- an error becomes a chat line instead.
  function boot.fire(event, ...)
    local handler = boot.handlers[event]
    assert(handler, "no handler is registered for " .. event)
    return handler(...)
  end

  function boot.chunk(id, data)
    return boot.fire("incoming chunk", id, data)
  end

  -- The last dispatch of an event: {event, [1], [2], ..., n = argument count}.
  function boot.last_dispatch(event)
    for index = #boot.dispatches, 1, -1 do
      if boot.dispatches[index].event == event then
        return boot.dispatches[index]
      end
    end
    return nil
  end

  function boot.said()
    return table.concat(boot.chat, "\n")
  end

  return boot
end

return M
