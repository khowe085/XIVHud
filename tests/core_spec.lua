local new_core = require("lib/core")
local fakes = require("tests/support/fakes")

local MOVE, LEFT_DOWN, LEFT_UP, RIGHT_DOWN, WHEEL = 0, 1, 2, 4, 10
local DIK_SHIFT = 42
local EVENT_STATUS = 4

describe("core", function()
  local deps, env, core

  local function placed(x, y)
    return { layout = { pos = { x = x, y = y }, scale = 1, visible = true } }
  end

  local function bar(name, x, y)
    return fakes.widget(name or "bar", placed(x or 100, y or 200))
  end

  local function login(name)
    env.login(name or "Azureblood")
    core.on_login()
  end

  before_each(function()
    deps, env = fakes.core_deps()
    core = new_core(deps)
  end)

  describe("registration", function()
    it("returns the component and lists it", function()
      local widget = bar()
      assert.are.equal(widget, core.register(widget))
      assert.are.same({ "bar" }, core.names())
    end)

    it("refuses a component named after a reserved command", function()
      assert.has_error(function()
        core.register(fakes.widget("layout"))
      end)
    end)

    it("leaves a component detached while logged out", function()
      local widget = core.register(bar())
      assert.is_nil(widget.config)
      assert.is_false(widget.shown)
    end)
  end)

  describe("aliases", function()
    local function aliased(name, alias)
      local widget = bar(name)
      widget.alias = alias
      return widget
    end

    it("routes a command sent through the alias to the component", function()
      local widget = aliased("crossbar", "cb")
      local commanded
      widget.handle_command = function(args)
        commanded = args
        return "done"
      end
      core.register(widget)
      login()
      core.on_command({ "cb", "set", "3" })
      assert.are.same({ "set", "3" }, commanded)
    end)

    it("names the alias in the listing", function()
      core.register(aliased("crossbar", "cb"))
      login()
      core.on_command({ "list" })
      assert.is_not_nil(env.said():find("crossbar (cb)", 1, true), "said: " .. env.said())
    end)
  end)

  describe("login and logout", function()
    it("attaches every component to its own config once a character is known", function()
      local widget = core.register(bar())
      login()
      assert.is_not_nil(widget.config)
      assert.are.same({ 100, 200 }, widget.pos)
    end)

    it("gives each component a config of its own", function()
      local one = core.register(fakes.widget("one", { size = 1 }))
      local two = core.register(fakes.widget("two", { size = 2 }))
      login()
      one.config.size = 99
      assert.are.equal(2, two.config.size)
    end)

    it("reads back what a character saved before", function()
      env.fs.put("data/Azureblood/default/bar/layout.lua", "return { pos = { x = 40, y = 50 } }")
      local widget = core.register(bar())
      login()
      assert.are.same({ 40, 50 }, widget.pos)
    end)

    it("writes the framework's own config out, so its options are discoverable", function()
      core.register(bar())
      login()
      local written = env.fs.files["data/Azureblood/core.lua"]
      assert.is_not_nil(written, "core.lua was never created")
      assert.is_not_nil(written:find("hideCutscene", 1, true))
      assert.is_not_nil(written:find("snap", 1, true))
    end)

    it("does not overwrite a core config the user has edited", function()
      env.fs.put("data/Azureblood/core.lua", "return { snap = 25 }")
      core.register(bar())
      login()
      assert.are.equal("return { snap = 25 }", env.fs.files["data/Azureblood/core.lua"])
    end)

    --[[ The player service caches the client for an interval, and core is the
         only thing that knows a different character is now being played - the
         `login` event fires before the client can name anybody, and CLAUDE.md
         records that a switch can resolve without one at all. So core announces
         the scope, and it announces it BEFORE attaching: the incoming
         character's first tick must not be able to read the outgoing one. ]]
    it("announces a scope change before it attaches anything", function()
      local widget = core.register(bar())
      local seen_at_attach = nil
      local attach = widget.attach
      widget.attach = function(...)
        seen_at_attach = #env.scope_changes
        return attach(...)
      end
      env.login("Azureblood")
      core.on_login()
      assert.are.same({ "Azureblood" }, env.scope_changes)
      assert.are.equal(1, seen_at_attach, "attached before the scope change was announced")
    end)

    it("announces the un-scoping on a logout too", function()
      core.register(bar())
      env.login("Azureblood")
      core.on_login()
      env.player = nil
      core.on_logout()
      assert.are.same({ "Azureblood", false }, env.scope_changes)
    end)

    it("ignores a blank character name until the real one arrives", function()
      local widget = core.register(bar())
      env.player = { name = "", vitals = {} }
      core.on_login()
      assert.is_nil(widget.config)
      env.login("Azureblood")
      core.on_prerender()
      assert.is_not_nil(widget.config)
    end)

    -- A login event is a one-shot, and the client may not be able to name the
    -- player yet when it fires. What a component needs beyond the name - the
    -- vitals, the inventory - it waits for itself: the client fills those in
    -- field by field, and there is no one signal that says they are all there.
    it("attaches a character the client has named but not filled in yet", function()
      local widget = core.register(bar())
      env.player = { name = "Azureblood", status = 0 }
      core.on_login()
      assert.is_not_nil(widget.config, "held the whole HUD back for data core does not own")
    end)

    -- A frame spent at character select books the slow slot; a login landing
    -- inside it must not be made to serve out someone else's second.
    it("looks for the character at login speed, not character-select speed", function()
      core.register(bar())
      core.on_prerender()

      env.clock = 0.1
      env.player = { name = "", status = 0 }
      core.on_login()
      core.on_prerender()
      assert.is_nil(core.character())

      env.clock = 0.2
      env.login("Azureblood")
      core.on_prerender()
      assert.are.equal("Azureblood", core.character(), "still serving out the character-select interval")
    end)

    it("stops watching for a character once the login resolves", function()
      local polls = 0
      local counted_deps, counted_env = fakes.core_deps({
        logged_in = function()
          polls = polls + 1
          return true
        end,
      })
      local counted_core = new_core(counted_deps)
      counted_core.register(bar())
      counted_env.login("Azureblood")
      counted_core.on_login()

      polls = 0
      for frame = 1, 100 do
        counted_env.clock = frame
        counted_core.on_prerender()
      end
      assert.are.equal(0, polls, "still asking the client for a character it already has")
    end)

    -- on_prerender only watches for a character when there is none, so a login
    -- arriving over the top of one already scoped has to keep it looking.
    it("switches to a character whose login it could not resolve at the time", function()
      core.register(bar())
      login("Alpha")

      env.player = { name = "", status = 0 }
      core.on_login()
      assert.are.equal("Alpha", core.character(), "dropped the scoped character on an unresolvable login")

      env.login("Bravo")
      core.on_prerender()
      assert.are.equal("Bravo", core.character(), "never picked Bravo up")
    end)

    it("swaps configs when a different character logs in", function()
      env.fs.put("data/Alpha/default/bar/layout.lua", "return { pos = { x = 10, y = 10 } }")
      env.fs.put("data/Bravo/default/bar/layout.lua", "return { pos = { x = 20, y = 20 } }")
      local widget = core.register(bar())
      login("Alpha")
      assert.are.same({ 10, 10 }, widget.pos)
      core.on_logout()
      login("Bravo")
      assert.are.same({ 20, 20 }, widget.pos)
    end)

    it("detaches and hides on logout", function()
      local widget = core.register(bar())
      login()
      core.on_logout()
      assert.is_nil(widget.config)
      assert.is_false(widget.shown)
    end)

    it("initialises on load when the client is already logged in", function()
      local widget = core.register(bar())
      env.login("Azureblood")
      core.on_load()
      assert.is_not_nil(widget.config)
      assert.is_true(widget.shown)
    end)

    it("does nothing on load while logged out", function()
      local widget = core.register(bar())
      core.on_load()
      assert.is_nil(widget.config)
    end)

    it("picks the character up on a later frame when it was not readable at login", function()
      local logged_in = true
      local late_deps, late_env = fakes.core_deps({
        logged_in = function()
          return logged_in
        end,
      })
      local late_core = new_core(late_deps)
      local widget = late_core.register(bar())

      late_core.on_login()
      assert.is_nil(widget.config, "get_player() has not caught up yet")

      late_env.login("Azureblood")
      late_core.on_prerender()
      assert.is_not_nil(widget.config)
    end)

    it("reports the character its configuration is scoped to", function()
      core.register(bar())
      assert.is_nil(core.character())
      login()
      assert.are.equal("Azureblood", core.character())
      core.on_logout()
      assert.is_nil(core.character())
    end)

    it("does not ask the client for a character on every single frame", function()
      local polls = 0
      local polled_deps, polled_env = fakes.core_deps({
        logged_in = function()
          polls = polls + 1
          return true
        end,
      })
      local polled_core = new_core(polled_deps)
      local widget = polled_core.register(bar())

      for _ = 1, 200 do
        polled_core.on_prerender()
      end
      assert.is_true(polls <= 2, "polled " .. polls .. " times across 200 frames")

      -- but it must still notice when the character finally appears
      polled_env.login("Azureblood")
      polled_env.clock = 5
      polled_core.on_prerender()
      assert.is_not_nil(widget.config)
    end)

    it("does not go looking for a character while logged out", function()
      local widget = core.register(bar())
      core.on_prerender()
      assert.is_nil(widget.config)
    end)

    it("hands a component a way to save its own config", function()
      local widget = core.register(bar())
      login()
      widget.config.compact = true
      widget.save()
      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/config.lua"]:find("compact = true", 1, true))
      -- config.lua alone: layout.lua is core's file, and a component saving for
      -- itself must not be what writes a placement it was never handed.
      assert.is_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"])
    end)

    it("takes the save callback away on logout", function()
      local widget = core.register(bar())
      login()
      core.on_logout()
      assert.is_nil(widget.save)
    end)

    it("attaches a component registered after login", function()
      login()
      local widget = core.register(bar())
      assert.is_not_nil(widget.config)
      assert.is_true(widget.shown)
    end)
  end)

  describe("applying layout state", function()
    it("pushes position, scale and visibility from the active slot", function()
      local widget = core.register(bar("bar", 300, 400))
      login()
      assert.are.same({ 300, 400 }, widget.pos)
      assert.are.equal(1, widget.scale)
      assert.is_true(widget.shown)
      assert.is_false(widget.preview)
    end)

    it("hides a component switched off in its slot", function()
      env.fs.put("data/Azureblood/default/bar/layout.lua", "return { visible = false }")
      local widget = core.register(bar())
      login()
      assert.is_false(widget.shown)
    end)

    it("pulls a stored position that is off screen back into reach", function()
      env.fs.put("data/Azureblood/default/bar/layout.lua", "return { pos = { x = 5000, y = 4000 } }")
      local widget = core.register(bar())
      login()
      assert.are.same({ 1720, 980 }, widget.pos, "otherwise layout mode can never grab it")

      core.on_command({ "list" })
      assert.is_not_nil(env.said():find("1720", 1, true), "said: " .. env.said())
    end)

    it("repairs a scale below the floor, in the stored state as well as on screen", function()
      env.fs.put("data/Azureblood/default/bar/layout.lua", "return { scale = 0.05 }")
      local widget = core.register(bar())
      login()
      assert.are.equal(0.25, widget.scale)

      core.on_command({ "list" })
      assert.is_not_nil(env.said():find("0.25", 1, true), "said: " .. env.said())

      core.on_command({ "layout" })
      core.on_mouse(WHEEL, 150, 250, 100)
      assert.are.equal(1.25, widget.scale, "the next wheel step must start from the repaired value")
    end)
  end)

  describe("auto-hide", function()
    it("hides everything during a cutscene and restores afterwards", function()
      local widget = core.register(bar())
      login()
      core.on_status_change(EVENT_STATUS)
      assert.is_false(widget.shown)
      core.on_status_change(0)
      assert.is_true(widget.shown)
    end)

    it("takes the current status into account at login, not just on the next change", function()
      local widget = core.register(bar())
      env.login("Azureblood")
      env.player.status = 4
      core.on_login()
      assert.is_false(widget.shown, "reloading mid-cutscene must not flash the HUD back on")
      core.on_status_change(0)
      assert.is_true(widget.shown)
    end)

    it("passes the status change on to components so they can re-seed", function()
      local widget = core.register(bar())
      login()
      core.on_status_change(EVENT_STATUS, 0)
      assert.are.same({ "status", EVENT_STATUS, 0 }, widget.updates[#widget.updates])
    end)

    it("hides on zone change and re-shows only after the settle window", function()
      local widget = core.register(bar())
      login()
      core.on_zone_change()
      assert.is_false(widget.shown)

      env.clock = 2
      core.on_prerender()
      assert.is_false(widget.shown)

      env.clock = 3
      core.on_prerender()
      assert.is_true(widget.shown)
    end)

    it("obeys the hideCutscene core option", function()
      env.fs.put("data/Azureblood/core.lua", "return { hideCutscene = false }")
      local widget = core.register(bar())
      login()
      core.on_status_change(EVENT_STATUS)
      assert.is_true(widget.shown)
    end)

    it("outranks layout mode", function()
      local widget = core.register(bar())
      login()
      core.on_command({ "layout" })
      assert.is_true(widget.shown)
      core.on_status_change(EVENT_STATUS)
      assert.is_false(widget.shown)
      assert.is_true(core.layout_active(), "the mode itself stays on")
    end)
  end)

  describe("the render loop", function()
    it("ticks every attached component once per frame", function()
      local widget = core.register(bar())
      login()
      core.on_prerender()
      core.on_prerender()
      assert.are.equal(2, #widget.updates)
      assert.are.same({}, widget.updates[1])
    end)

    it("does not tick while logged out", function()
      local widget = core.register(bar())
      core.on_prerender()
      assert.are.equal(0, #widget.updates)
    end)

    it("keeps feeding a suppressed component so its data is current when it returns", function()
      local widget = core.register(bar())
      login()
      core.on_status_change(EVENT_STATUS)
      core.on_prerender()
      assert.is_true(#widget.updates > 0)
    end)

    it("forwards game events to every component", function()
      local widget = core.register(bar())
      login()
      core.dispatch("hp", 500, 600)
      assert.are.same({ "hp", 500, 600 }, widget.updates[#widget.updates])
    end)
  end)

  describe("layout mode", function()
    it("captures input while on and releases it when off", function()
      core.register(bar())
      login()
      core.on_command({ "layout" })
      assert.is_true(env.capture)
      assert.is_true(core.layout_active())
      core.on_command({ "setup" })
      assert.is_false(env.capture)
      assert.is_false(core.layout_active())
    end)

    it("previews and force-shows even a component switched off", function()
      env.fs.put("data/Azureblood/default/bar/layout.lua", "return { visible = false }")
      local widget = core.register(bar())
      login()
      core.on_command({ "layout" })
      assert.is_true(widget.shown)
      assert.is_true(widget.preview)

      core.on_command({ "layout" })
      assert.is_false(widget.shown)
      assert.is_false(widget.preview)
    end)

    it("draws a highlight over each widget, and clears it on the way out", function()
      core.register(bar("bar", 100, 200))
      login()
      assert.are.equal(0, #env.prims.images, "no overlay prims until the mode is used")

      core.on_command({ "layout" })
      local highlight = env.prims.images[1]
      assert.is_true(highlight.visible)
      assert.are.same({ 100, 200 }, { highlight.x, highlight.y })
      assert.are.same({ 200, 100 }, { highlight.width, highlight.height })
      assert.are.equal("bar", env.prims.texts[1].last.text)

      core.on_command({ "layout" })
      assert.is_false(highlight.visible)
      assert.is_false(env.prims.texts[1].visible)
    end)

    it("follows the widget as it is dragged", function()
      core.register(bar("bar", 100, 200))
      login()
      core.on_command({ "layout" })
      core.on_mouse(LEFT_DOWN, 150, 250)
      core.on_mouse(MOVE, 400, 500)
      assert.are.same({ 350, 450 }, { env.prims.images[1].x, env.prims.images[1].y })
    end)

    it("marks a widget the right-click toggle has switched off", function()
      core.register(bar())
      login()
      core.on_command({ "layout" })
      core.on_mouse(RIGHT_DOWN, 150, 250)
      assert.is_not_nil(env.prims.texts[1].last.text:lower():find("hidden"))
    end)

    it("clears the highlight while something is suppressing", function()
      core.register(bar())
      login()
      core.on_command({ "layout" })
      core.on_status_change(EVENT_STATUS)
      assert.is_false(env.prims.images[1].visible)
    end)

    it("needs a character before it will start", function()
      core.register(bar())
      core.on_command({ "layout" })
      assert.is_false(core.layout_active())
      assert.is_not_nil(env.said():lower():find("log in"))
    end)

    it("drags a widget and writes the new position to its own config file", function()
      local widget = core.register(bar("bar", 100, 200))
      login()
      core.on_command({ "layout" })

      assert.is_true(core.on_mouse(LEFT_DOWN, 150, 250))
      assert.is_true(core.on_mouse(MOVE, 400, 500))
      assert.is_true(core.on_mouse(LEFT_UP, 400, 500))

      assert.are.same({ 350, 450 }, widget.pos)
      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"]:find("x = 350", 1, true))
    end)

    -- The other half of the split: core owns layout.lua, so a drag writes that
    -- and nothing else. Flushing the component's table here would persist edits
    -- it has not asked to keep.
    it("writes only the layout file when a drag moves a widget", function()
      local widget = core.register(bar("bar", 100, 200))
      login()
      widget.config.compact = "unsaved"

      core.on_command({ "layout" })
      core.on_mouse(LEFT_DOWN, 150, 250)
      core.on_mouse(LEFT_UP, 400, 400)
      core.on_command({ "layout" })

      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"])
      assert.is_nil(env.fs.files["data/Azureblood/default/bar/config.lua"], "a drag is not the component's save")
    end)

    it("scales with the wheel and saves", function()
      local widget = core.register(bar())
      login()
      core.on_command({ "layout" })
      assert.is_true(core.on_mouse(WHEEL, 150, 250, 120))
      assert.are.equal(2.2, widget.scale)
      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"]:find("scale = 2.2", 1, true))
    end)

    it("toggles a widget off with a right click and saves", function()
      local widget = core.register(bar())
      login()
      core.on_command({ "layout" })
      assert.is_true(core.on_mouse(RIGHT_DOWN, 150, 250))
      assert.is_true(widget.shown, "still force-shown while positioning")
      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"]:find("visible = false", 1, true))

      core.on_command({ "layout" })
      assert.is_false(widget.shown)
    end)

    it("ignores input the game has already blocked", function()
      core.register(bar())
      login()
      core.on_command({ "layout" })
      assert.is_false(core.on_mouse(LEFT_DOWN, 150, 250, 0, true))
      assert.is_false(core.on_mouse(MOVE, 400, 500))
    end)

    it("ignores mouse input while something is suppressing, so hidden widgets cannot be dragged", function()
      local widget = core.register(bar("bar", 100, 200))
      login()
      core.on_command({ "layout" })
      core.on_status_change(EVENT_STATUS)
      assert.is_false(core.on_mouse(LEFT_DOWN, 150, 250))
      core.on_mouse(MOVE, 400, 500)
      assert.are.same({ 100, 200 }, widget.pos)
    end)

    it("ignores mouse input entirely when the mode is off", function()
      core.register(bar())
      login()
      assert.is_false(core.on_mouse(LEFT_DOWN, 150, 250))
    end)

    it("frees the grid while CTRL is held", function()
      local widget = core.register(bar("bar", 100, 200))
      login()
      core.on_command({ "layout" })
      core.on_keyboard(29, true)
      core.on_mouse(LEFT_DOWN, 150, 250)
      core.on_mouse(MOVE, 404, 456)
      assert.are.same({ 354, 406 }, widget.pos)
    end)

    it("leaves the mode on logout so a re-login is not stuck in it", function()
      core.register(bar())
      login()
      core.on_command({ "layout" })
      core.on_logout()
      assert.is_false(core.layout_active())
      assert.is_false(env.capture)
    end)
  end)

  describe("commands", function()
    it("answers a bare command with help", function()
      core.on_command({})
      assert.is_not_nil(env.said():find("//hud layout", 1, true))
    end)

    it("reports every component with its state", function()
      core.register(bar("bar", 100, 200))
      login()
      core.on_command({ "list" })
      local said = env.said()
      assert.is_not_nil(said:find("bar", 1, true))
      assert.is_not_nil(said:find("100", 1, true))
    end)

    it("reports a hand-edited non-boolean visible the way the screen reads it", function()
      env.fs.put("data/Azureblood/default/bar/layout.lua", "return { visible = 1 }")
      local widget = core.register(bar())
      login()
      assert.is_false(widget.shown)
      core.on_command({ "list" })
      assert.is_not_nil(env.said():find("hidden", 1, true), "said: " .. env.said())
    end)

    it("says so when there are no components", function()
      core.on_command({ "list" })
      assert.is_not_nil(env.said():lower():find("no components"))
    end)

    it("shows and hides a component, saving each time", function()
      local widget = core.register(bar())
      login()
      core.on_command({ "hide", "bar" })
      assert.is_false(widget.shown)
      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"]:find("visible = false", 1, true))

      core.on_command({ "show", "BAR" })
      assert.is_true(widget.shown)
      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"]:find("visible = true", 1, true))
    end)

    it("resets one component back to its defaults", function()
      local widget = core.register(bar("bar", 100, 200))
      login()
      core.on_command({ "layout" })
      core.on_mouse(LEFT_DOWN, 150, 250)
      core.on_mouse(LEFT_UP, 800, 800)
      core.on_command({ "layout" })

      core.on_command({ "reset", "bar" })
      assert.are.same({ 100, 200 }, widget.pos)
      assert.is_not_nil(widget.config, "the component is re-attached to the fresh config")
    end)

    -- Reset is scoped to the slot the player is in: another slot's copy of the
    -- same component is a separate configuration and is left alone.
    it("resets one component in the active slot only", function()
      local widget = core.register(bar("bar", 100, 200))
      login()
      core.on_command({ "slot", "create", "raid" })
      env.fs.put("data/Azureblood/raid/bar/layout.lua", "return { pos = { x = 700, y = 700 } }")

      core.on_command({ "reset", "bar" })
      assert.is_not_nil(env.fs.files["data/Azureblood/raid/bar/layout.lua"], "another slot must survive")
      core.on_command({ "slot", "raid" })
      assert.are.same({ 700, 700 }, widget.pos)
    end)

    it("resets everything at once", function()
      local one = core.register(fakes.widget("one", placed(10, 10)))
      local two = core.register(fakes.widget("two", placed(20, 20)))
      login()
      core.on_command({ "hide", "one" })
      core.on_command({ "hide", "two" })
      core.on_command({ "reset", "all" })
      assert.is_true(one.shown)
      assert.is_true(two.shown)
    end)

    it("needs a character before it will change anything", function()
      core.register(bar())
      core.on_command({ "hide", "bar" })
      assert.is_not_nil(env.said():lower():find("log in"))
    end)

    it("passes unrecognised arguments to the component that owns them", function()
      local widget = core.register(bar())
      widget.handle_command = function(args)
        return "got " .. table.concat(args, " ")
      end
      login()
      core.on_command({ "bar", "width", "150" })
      assert.is_not_nil(env.said():find("got width 150", 1, true))
    end)

    -- A component whose answer is a list -- an ordering, a search result -- has
    -- nowhere to put it in one chat line, and FFXI's chat does not wrap on \n.
    it("says every line of a component's answer when it replies with a list", function()
      local widget = core.register(bar())
      widget.handle_command = function()
        return { "first line", "second line" }
      end
      login()
      core.on_command({ "bar", "list" })
      assert.is_not_nil(env.said():find("first line", 1, true))
      assert.is_not_nil(env.said():find("second line", 1, true))
    end)

    it("says nothing for a component that answers with an empty list", function()
      local widget = core.register(bar())
      widget.handle_command = function()
        return {}
      end
      login()
      local before = #env.chat
      core.on_command({ "bar", "quiet" })
      assert.are.equal(before, #env.chat)
    end)

    it("refuses a component command while logged out, rather than losing the change", function()
      local widget = core.register(bar())
      widget.handle_command = function()
        return "changed"
      end
      core.on_command({ "bar", "width", "200" })
      assert.is_not_nil(env.said():lower():find("log in"))
      assert.is_nil(env.said():find("changed", 1, true))
    end)

    it("says a component takes no commands rather than swallowing them", function()
      core.register(bar())
      login()
      core.on_command({ "bar", "width" })
      assert.is_not_nil(env.said():lower():find("no commands"))
    end)

    it("reports unknown input", function()
      core.on_command({ "bogus" })
      assert.is_not_nil(env.said():find("bogus", 1, true))
      assert.is_not_nil(env.said():find("//hud help", 1, true))
    end)
  end)

  describe("layout slots", function()
    local widget

    before_each(function()
      widget = core.register(bar("bar", 100, 200))
      login()
    end)

    -- Grabs the widget wherever it currently is, so this still works after a
    -- slot switch has moved it.
    local function move_to(x, y)
      core.on_command({ "layout" })
      core.on_mouse(LEFT_DOWN, widget.pos[1] + 50, widget.pos[2] + 50)
      core.on_mouse(LEFT_UP, x + 50, y + 50)
      core.on_command({ "layout" })
    end

    it("starts on the default slot and lists it as active", function()
      core.on_command({ "slot", "list" })
      local said = env.said()
      assert.is_not_nil(said:find("default", 1, true))
      assert.is_not_nil(said:lower():find("active"))
    end)

    it("creates a slot from the active one without switching to it", function()
      move_to(300, 400)
      core.on_command({ "slot", "create", "raid" })

      assert.is_not_nil(env.fs.files["data/Azureblood/raid/bar/layout.lua"])
      core.on_command({ "slot", "list" })
      assert.is_not_nil(env.said():find("raid", 1, true))
      assert.are.same({ 300, 400 }, widget.pos, "creating must not move anything")
    end)

    it("switches between slots, restoring each one's layout", function()
      move_to(300, 400)
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "raid" })
      move_to(600, 700)
      assert.are.same({ 600, 700 }, widget.pos)

      core.on_command({ "slot", "default" })
      assert.are.same({ 300, 400 }, widget.pos)
      core.on_command({ "slot", "raid" })
      assert.are.same({ 600, 700 }, widget.pos)
    end)

    it("remembers the active slot across a re-login", function()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "raid" })
      core.on_logout()
      login()
      core.on_command({ "slot", "list" })
      assert.is_not_nil(env.said():find("raid  (active)", 1, true), "said: " .. env.said())
    end)

    it("gives a component with no entry for the slot its default layout", function()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "raid" })
      local late = core.register(fakes.widget("late", placed(11, 22)))
      assert.are.same({ 11, 22 }, late.pos)
    end)

    it("falls back to the default slot when the stored active slot is nonsense", function()
      env.fs.put("data/Azureblood/core.lua", "return { slot = 7 }")
      core.on_logout()
      login()
      assert.has_no.errors(function()
        core.on_command({ "slot", "list" })
      end)
      assert.is_not_nil(env.said():find("default  (active)", 1, true), "said: " .. env.said())
    end)

    it("keeps every component's slots in step", function()
      local clock = core.register(fakes.widget("clock", placed(10, 20)))
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "raid" })

      for _, name in ipairs({ "bar", "clock" }) do
        assert.is_not_nil(env.fs.files["data/Azureblood/raid/" .. name .. "/layout.lua"], name)
      end

      move_to(500, 500)
      assert.are.same({ 10, 20 }, clock.pos, "the other component keeps its own layout")

      core.on_command({ "slot", "default" })
      assert.are.same({ 100, 200 }, widget.pos)
      assert.are.same({ 10, 20 }, clock.pos)

      core.on_command({ "slot", "delete", "raid" })
      for _, name in ipairs({ "bar", "clock" }) do
        assert.is_nil(env.fs.files["data/Azureblood/raid/" .. name .. "/layout.lua"], name)
      end
    end)

    -- A slot is a directory now, and one made by hand can be capitalised
    -- however the player likes.
    it("matches a hand-made slot directory whatever its case", function()
      env.fs.put("data/Azureblood/default/bar/layout.lua", "return { pos = { x = 1, y = 2 } }")
      env.fs.put("data/Azureblood/Raid/bar/layout.lua", "return { pos = { x = 300, y = 400 } }")
      core.on_logout()
      login()

      core.on_command({ "slot", "raid" })
      assert.are.same({ 300, 400 }, widget.pos)
      assert.is_nil(env.said():lower():find("no layout slot"))

      core.on_command({ "slot", "default" })
      core.on_command({ "slot", "delete", "RAID" })
      assert.is_nil(env.fs.files["data/Azureblood/Raid/bar/layout.lua"])
    end)

    -- The decision behind the whole directory layout: a slot scopes the
    -- component's own configuration too, not just where it is drawn.
    it("gives each slot its own component config", function()
      widget.config.compact = "from-default"
      widget.save()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "raid" })
      assert.are.equal("from-default", widget.config.compact, "a new slot is a copy of the active one")

      widget.config.compact = "from-raid"
      widget.save()
      core.on_command({ "slot", "default" })
      assert.are.equal("from-default", widget.config.compact)
      core.on_command({ "slot", "raid" })
      assert.are.equal("from-raid", widget.config.compact)
    end)

    -- core.lua and the directory listing are two different sources, and a hand
    -- edit can disagree with the disk about case. Reading as two slots would
    -- list the same slot twice and let the active one be deleted.
    it("treats a stored slot name and its directory as one slot whatever the case", function()
      env.fs.put("data/Azureblood/Raid/bar/layout.lua", "return { pos = { x = 300, y = 400 } }")
      env.fs.put("data/Azureblood/core.lua", "return { slot = 'raid' }")
      core.on_logout()
      login()

      env.forget()
      core.on_command({ "slot", "list" })
      local _, listed = env.said():lower():gsub("raid", "")
      assert.are.equal(1, listed, "listed twice: " .. env.said())
      assert.is_not_nil(env.said():lower():find("active"), "and marked active: " .. env.said())

      core.on_command({ "slot", "delete", "RAID" })
      assert.is_not_nil(env.said():lower():find("active"), "the active slot must not be deletable")
      assert.is_not_nil(env.fs.files["data/Azureblood/Raid/bar/layout.lua"])
    end)

    it("refuses to create a slot whose name differs only by case", function()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "create", "RAID" })
      assert.is_not_nil(env.said():lower():find("already"))
    end)

    it("refuses to switch to a slot that does not exist, and lists the ones that do", function()
      core.on_command({ "slot", "nope" })
      local said = env.said()
      assert.is_not_nil(said:find("nope", 1, true))
      assert.is_not_nil(said:find("default", 1, true))
    end)

    it("refuses to create a slot twice", function()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "create", "raid" })
      assert.is_not_nil(env.said():lower():find("already"))
    end)

    it("deletes a slot", function()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "delete", "raid" })
      assert.is_nil(env.fs.files["data/Azureblood/raid/bar/layout.lua"])
    end)

    -- `os.remove` refuses a directory outright on Windows, so deleting a slot
    -- empties its tree and leaves the directories standing. A slot that is
    -- only empty directories is not a slot.
    it("stops listing a deleted slot, though its directories survive the delete", function()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "delete", "raid" })
      assert.is_true(env.fs.is_dir("data/Azureblood/raid"), "the directory itself cannot be removed")

      env.forget()
      core.on_command({ "slot", "list" })
      assert.is_nil(env.said():find("raid", 1, true), "said: " .. env.said())

      env.forget()
      core.on_command({ "slot", "create", "raid" })
      assert.is_nil(env.said():lower():find("already"), "and the name is free again: " .. env.said())
    end)

    -- What a pre-slot install left beside core.lua: `data/<Char>/crossbar/`
    -- full of per-job binding files. A slot holds component directories; a
    -- directory of loose files is something else.
    it("does not offer a directory of loose files as a slot", function()
      env.fs.put("data/Azureblood/crossbar/WAR.lua", "return {}")
      core.on_command({ "slot", "list" })
      assert.is_nil(env.said():find("crossbar", 1, true), "said: " .. env.said())
    end)

    -- core.lua is hand-editable and `//hud copy` imports another character's,
    -- and the name becomes a path segment that `//hud reset` deletes inside.
    it("refuses a stored slot name that is not a plain word", function()
      env.fs.put("data/Azureblood/core.lua", "return { slot = '../Bravo' }")
      core.on_logout()
      login()

      core.on_command({ "hide", "bar" })
      assert.is_nil(env.fs.files["data/Azureblood/../Bravo/bar/layout.lua"], "must not escape the character's dir")
      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"])
    end)

    it("says so when the new slot could not be written, instead of claiming success", function()
      env.fs.fail_write_paths["data/Azureblood/raid/bar/layout.lua"] = true
      core.on_command({ "slot", "create", "raid" })
      assert.is_not_nil(env.said():lower():find("could not"), "said: " .. env.said())
    end)

    it("says so when the active slot could not be written down to be copied", function()
      env.fs.fail_writes = true
      core.on_command({ "slot", "create", "raid" })
      -- The wording matters: lib/settings warns about each failed write through
      -- the same chat, so "could not" alone would pass without this guard.
      assert.is_not_nil(env.said():find("nothing to copy", 1, true), "said: " .. env.said())
      assert.is_nil(env.said():find("created from", 1, true), "and it must not claim success")
      env.fs.fail_writes = false
      env.forget()
      core.on_command({ "slot", "list" })
      assert.is_nil(env.said():find("raid", 1, true), "an unwritten slot must not be listed")
    end)

    -- A re-issued switch used to re-attach every component, which on the
    -- crossbar rebuilds its state and drops a countdown in flight.
    it("changes nothing when the active slot is switched to again", function()
      widget.config.compact = "unsaved"
      core.on_command({ "slot", "default" })
      assert.are.equal("unsaved", widget.config.compact, "no re-attach, so an unsaved edit survives")
      assert.is_not_nil(env.said():lower():find("already"), "said: " .. env.said())
    end)

    it("lists a differently-cased default directory first all the same", function()
      -- `Battle` sorts before `Default`, so only the hoist can put default first.
      env.fs.put("data/Azureblood/Default/bar/layout.lua", "return { pos = { x = 1, y = 2 } }")
      env.fs.put("data/Azureblood/Battle/bar/layout.lua", "return { pos = { x = 3, y = 4 } }")
      core.on_logout()
      login()

      env.forget()
      core.on_command({ "slot", "list" })
      local said = env.said()
      assert.is_true(said:lower():find("default", 1, true) < said:find("Battle", 1, true), "said: " .. said)
    end)

    -- active_slot() answers `default` for a stored value it rejects, so without
    -- this the bad value sits in core.lua with nothing able to overwrite it.
    it("repairs an invalid stored slot name when its fallback is switched to", function()
      env.fs.put("data/Azureblood/core.lua", "return { slot = '../Bravo' }")
      core.on_logout()
      login()

      core.on_command({ "slot", "default" })
      local written = env.fs.files["data/Azureblood/core.lua"]
      assert.is_nil(written:find("Bravo", 1, true), "wrote: " .. written)
      assert.is_not_nil(env.said():lower():find("already"), "and it is still a no-op switch")
    end)

    it("says so when the copy found nothing to write, instead of claiming success", function()
      local listing = deps.list_dir
      deps.list_dir = function(path)
        return path ~= "data/Azureblood/default" and listing(path) or nil
      end

      core.on_command({ "slot", "create", "raid" })
      assert.is_nil(env.said():find("created from", 1, true), "said: " .. env.said())
      assert.is_not_nil(env.said():lower():find("nothing"), "said: " .. env.said())
    end)

    it("refuses to delete the default slot", function()
      core.on_command({ "slot", "delete", "default" })
      assert.is_not_nil(env.said():lower():find("cannot be deleted"))
    end)

    it("refuses to delete the active slot", function()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "raid" })
      core.on_command({ "slot", "delete", "raid" })
      assert.is_not_nil(env.said():lower():find("active"))
      core.on_command({ "slot", "list" })
      assert.is_not_nil(env.said():find("raid", 1, true))
    end)

    it("refuses to delete a slot that never existed", function()
      core.on_command({ "slot", "delete", "nope" })
      assert.is_not_nil(env.said():find("nope", 1, true))
    end)

    it("needs a character before it will touch slots", function()
      core.on_logout()
      core.on_command({ "slot", "create", "raid" })
      assert.is_not_nil(env.said():lower():find("log in"))
    end)
  end)

  describe("copying one character's configuration onto another", function()
    local widget

    before_each(function()
      env.fs.put("data/Alpha/default/bar/layout.lua", "return { pos = { x = 40, y = 50 } }")
      env.fs.put("data/Alpha/core.lua", "return { snap = 25 }")
      env.fs.put("data/Alpha/default/bar/extra.lua", "return { deep = true }")
      widget = core.register(bar("bar", 100, 200))
      login("Azureblood")
    end)

    it("copies every file, including a component's own directory", function()
      core.on_command({ "copy", "Alpha", "Bravo" })
      assert.is_not_nil(env.fs.files["data/Bravo/default/bar/layout.lua"]:find("x = 40", 1, true))
      assert.are.equal("return { snap = 25 }", env.fs.files["data/Bravo/core.lua"])
      assert.are.equal("return { deep = true }", env.fs.files["data/Bravo/default/bar/extra.lua"])
    end)

    it("needs no confirmation", function()
      core.on_command({ "copy", "Alpha", "Bravo" })
      assert.is_not_nil(env.fs.files["data/Bravo/default/bar/layout.lua"])
    end)

    it("wipes the destination first, so nothing of its own survives", function()
      env.fs.put("data/Bravo/default/clock/config.lua", "return { stale = true }")
      env.fs.put("data/Bravo/raid/clock/config.lua", "return { alsostale = true }")

      core.on_command({ "copy", "Alpha", "Bravo" })
      assert.is_nil(env.fs.files["data/Bravo/default/clock/config.lua"], "a file the source lacks must not survive")
      assert.is_nil(env.fs.files["data/Bravo/raid/clock/config.lua"], "nor a slot the source lacks")
      assert.is_not_nil(env.fs.files["data/Bravo/default/bar/layout.lua"])
    end)

    it("leaves other characters alone", function()
      env.fs.put("data/Charlie/default/bar/config.lua", "return { mine = true }")
      core.on_command({ "copy", "Alpha", "Bravo" })
      assert.are.equal("return { mine = true }", env.fs.files["data/Charlie/default/bar/config.lua"])
    end)

    it("reloads and re-applies when the destination is the character being played", function()
      core.on_command({ "copy", "Alpha", "Azureblood" })
      assert.are.same({ 40, 50 }, widget.pos)
      assert.is_not_nil(widget.config)
    end)

    -- settings.reload() re-reads every component under the slot that was active
    -- a moment ago; the copied core.lua can name another one.
    it("follows the copied core.lua onto its own active slot", function()
      env.fs.put("data/Alpha/core.lua", "return { slot = 'raid' }")
      env.fs.put("data/Alpha/raid/bar/layout.lua", "return { pos = { x = 600, y = 700 } }")

      core.on_command({ "copy", "Alpha", "Azureblood" })
      assert.are.same({ 600, 700 }, widget.pos)
      core.on_command({ "slot", "list" })
      assert.is_not_nil(env.said():find("raid  (active)", 1, true), "said: " .. env.said())
    end)

    it("does not disturb the running HUD when copying to someone else", function()
      core.on_command({ "copy", "Alpha", "Bravo" })
      assert.are.same({ 100, 200 }, widget.pos)
    end)

    it("copies from the character being played too", function()
      core.on_command({ "hide", "bar" })
      core.on_command({ "copy", "Azureblood", "Bravo" })
      assert.is_not_nil(env.fs.files["data/Bravo/default/bar/layout.lua"]:find("visible = false", 1, true))
    end)

    it("matches both character names case-insensitively", function()
      core.on_command({ "copy", "alpha", "AZUREBLOOD" })
      assert.are.same({ 40, 50 }, widget.pos)
    end)

    it("lists the characters it knows when the source is unknown", function()
      core.on_command({ "copy", "Nobody", "Bravo" })
      local said = env.said()
      assert.is_not_nil(said:find("Nobody", 1, true))
      assert.is_not_nil(said:find("Alpha", 1, true))
      assert.is_nil(env.fs.files["data/Bravo/default/bar/layout.lua"])
    end)

    it("refuses a destination that is not a plain character name", function()
      -- Defence in depth: the parser rejects these, but the destination is
      -- deleted before it is written, so core does not take it on trust.
      for _, bad in ipairs({ "..", ".", "../..", "bar/baz" }) do
        core.on_command({ "copy", "Alpha", bad })
      end
      assert.is_not_nil(env.fs.files["data/Alpha/default/bar/layout.lua"], "the source must be untouched")
      assert.is_not_nil(env.said():lower():find("character name"))
    end)

    it("refuses to copy a character onto itself", function()
      core.on_command({ "copy", "Alpha", "alpha" })
      assert.is_not_nil(env.said():lower():find("same character"))
    end)

    it("says so when a file could not be copied, instead of claiming success", function()
      env.fs.fail_write_paths["data/Bravo/default/bar/layout.lua"] = true
      core.on_command({ "copy", "Alpha", "Bravo" })
      assert.is_not_nil(env.said():lower():find("could not"))
    end)

    it("does not walk the . and .. entries a directory listing may include", function()
      env.fs.dot_entries = true
      assert.has_no.errors(function()
        core.on_command({ "copy", "Alpha", "Bravo" })
      end)
      assert.is_not_nil(env.fs.files["data/Bravo/default/bar/layout.lua"])
    end)
  end)
  describe("unload", function()
    it("destroys every component and drops the registry", function()
      local widget = core.register(bar())
      login()
      core.on_unload()
      assert.are.equal(1, widget.destroyed)
      assert.are.same({}, core.names())
    end)

    it("disposes the layout-mode overlays too", function()
      core.register(bar())
      login()
      core.on_command({ "layout" })
      core.on_unload()
      assert.are.equal(1, env.prims.images[1].destroyed)
      assert.are.equal(1, env.prims.texts[1].destroyed)
    end)

    it("releases input capture", function()
      core.register(bar())
      login()
      core.on_command({ "layout" })
      core.on_unload()
      assert.is_false(env.capture)
    end)
  end)

  -- Touchpoint 1: a component may consume the keyboard by declaring an
  -- optional `on_keyboard(key, down, flags, blocked) -> block` member. Core
  -- delivers every event and propagates a `true` out to Windower.
  describe("component keyboard dispatch", function()
    local function keyboard_widget(name)
      local widget = bar(name)
      widget.keys = {}
      widget.block = false
      widget.on_keyboard = function(key, down, flags, blocked)
        widget.keys[#widget.keys + 1] = { key, down, flags, blocked }
        return widget.block
      end
      return widget
    end

    it("forwards the full event signature, not just key and down", function()
      local widget = core.register(keyboard_widget())
      login()
      core.on_keyboard(39, true, 4, false)
      assert.are.same({ 39, true, 4, false }, widget.keys[1])
    end)

    it("propagates a component's true return out to Windower", function()
      local widget = core.register(keyboard_widget())
      login()
      widget.block = true
      assert.is_true(core.on_keyboard(39, true, 0, false))
      widget.block = false
      assert.is_false(core.on_keyboard(39, false, 0, false))
    end)

    it("answers false when no component wants the keyboard", function()
      core.register(bar())
      login()
      assert.is_false(core.on_keyboard(39, true, 0, false))
    end)

    it("blocks when any one of several components does", function()
      local quiet = core.register(keyboard_widget("quiet"))
      local hungry = core.register(keyboard_widget("hungry"))
      login()
      hungry.block = true
      assert.is_true(core.on_keyboard(39, true, 0, false))
      assert.are.equal(1, #quiet.keys, "every keyboard component still sees the event")
    end)

    -- The mirror ordering: a block from an EARLIER component must survive the
    -- later ones answering false - the fold is an OR, not last-answer-wins.
    it("keeps an early component's block when a later one answers false", function()
      local hungry = core.register(keyboard_widget("hungry"))
      local quiet = core.register(keyboard_widget("quiet"))
      login()
      hungry.block = true
      assert.is_true(core.on_keyboard(39, true, 0, false))
      assert.are.equal(1, #quiet.keys, "the later component still sees the event")
    end)

    -- Pinned 2026-08-16: the inertness during layout mode lives inside the
    -- component's input module, NOT in dispatch going quiet - otherwise its
    -- dedicated keys could not stay blocked while anchors are placed.
    it("keeps delivering, and honouring blocks, while layout mode is on", function()
      local widget = core.register(keyboard_widget())
      login()
      core.on_command({ "layout" })
      widget.block = true
      assert.is_true(core.on_keyboard(39, true, 0, false))
      assert.are.equal(1, #widget.keys)
    end)

    it("still tracks CTRL for the layout-mode grid while a component listens", function()
      local widget = core.register(keyboard_widget("grabby"))
      local mover = core.register(bar("mover"))
      login()
      core.on_command({ "layout" })
      core.on_keyboard(29, true, 0, false)
      core.on_mouse(LEFT_DOWN, mover.pos[1] + 50, mover.pos[2] + 50)
      core.on_mouse(MOVE, mover.pos[1] + 54, mover.pos[2] + 56)
      assert.are.same({ 104, 206 }, mover.pos, "CTRL must free the grid exactly as before")
      assert.is_true(#widget.keys > 0)
    end)

    -- Suppression hides the HUD; it must not hide the keyboard from the
    -- component, whose own guards decide what stays blocked (a latched
    -- release, the dedicated keys) while nothing fires.
    it("keeps delivering while suppressed", function()
      local widget = core.register(keyboard_widget())
      login()
      core.on_status_change(EVENT_STATUS)
      core.on_keyboard(39, true, 0, false)
      assert.are.equal(1, #widget.keys)
    end)

    it("keeps delivering while logged out, so a latched release is still swallowed", function()
      local widget = core.register(keyboard_widget())
      login()
      widget.block = true
      core.on_keyboard(39, true, 0, false)
      core.on_logout()
      core.on_keyboard(39, false, 0, false)
      assert.are.equal(2, #widget.keys)
    end)

    it("answers false and calls nobody after unload", function()
      local widget = core.register(keyboard_widget())
      login()
      core.on_unload()
      assert.is_false(core.on_keyboard(39, true, 0, false))
      assert.are.equal(0, #widget.keys)
    end)

    -- A keyboard consumer's input guards need to know what core knows: its
    -- suppression guard keys off the same resolver that hides the HUD.
    it("exposes the suppression the components are subject to", function()
      login()
      assert.is_false(core.suppressed())
      core.on_status_change(EVENT_STATUS)
      assert.is_true(core.suppressed())
      core.on_logout()
      assert.is_true(core.suppressed(), "logged out counts as suppressed")
    end)

    -- The other half of core.suppressed() for the same guards: suppression
    -- and a user hide both reach a widget as hide(), and only core can say
    -- which is which - disabled must outrank suppressed.
    it("exposes a component's user visibility, unmoved by suppression", function()
      core.register(bar())
      login()
      assert.is_true(core.component_visible("bar"))
      core.on_status_change(EVENT_STATUS)
      assert.is_true(core.component_visible("bar"), "suppression is not the user's hide")
      core.on_command({ "hide", "bar" })
      assert.is_false(core.component_visible("bar"), "the user's hide is, even mid-suppression")
      core.on_command({ "show", "bar" })
      assert.is_true(core.component_visible("bar"))
      assert.is_false(core.component_visible("nobody"))
    end)

    it("reports whether any registered component wants the keyboard", function()
      assert.is_false(core.wants_keyboard())
      core.register(keyboard_widget())
      assert.is_true(core.wants_keyboard())
      core.on_unload()
      assert.is_false(core.wants_keyboard())
    end)
  end)

  -- Touchpoint 3: same shape for the mouse, for edit-mode UI. Unlike the
  -- keyboard, layout mode owns the mouse outright while it is on - entering
  -- layout mode exits edit mode, so the two never contend.
  describe("component mouse dispatch", function()
    local function mouse_widget(name)
      local widget = bar(name)
      widget.mice = {}
      widget.block = false
      widget.on_mouse = function(mouse_type, x, y, delta, extra)
        -- `extra` catches a fifth argument the contract does not promise:
        -- core answers a blocked event itself, so a component only ever sees
        -- events nobody has taken - there is no `blocked` to forward.
        widget.mice[#widget.mice + 1] = { mouse_type, x, y, delta, extra }
        return widget.block
      end
      return widget
    end

    it("forwards mouse events to a component that asks, and propagates its block", function()
      local widget = core.register(mouse_widget())
      login()
      widget.block = true
      assert.is_true(core.on_mouse(LEFT_DOWN, 10, 20, 0, false))
      assert.are.same({ LEFT_DOWN, 10, 20, 0 }, widget.mice[1])
      widget.block = false
      assert.is_false(core.on_mouse(MOVE, 11, 21, 0, false))
    end)

    -- Blocker first: the fold across components is an OR, so a later false
    -- must not overwrite an earlier block.
    it("keeps an early component's block when a later one answers false", function()
      local hungry = core.register(mouse_widget("hungry"))
      local quiet = core.register(mouse_widget("quiet"))
      login()
      hungry.block = true
      assert.is_true(core.on_mouse(LEFT_DOWN, 10, 20, 0, false))
      assert.are.equal(1, #quiet.mice, "the later component still sees the event")
    end)

    it("gives layout mode the mouse while it is on, not the component", function()
      local widget = core.register(mouse_widget())
      login()
      core.on_command({ "layout" })
      core.on_mouse(LEFT_DOWN, widget.pos[1] + 50, widget.pos[2] + 50)
      assert.are.equal(0, #widget.mice)
    end)

    it("passes nothing a prior addon already blocked", function()
      local widget = core.register(mouse_widget())
      login()
      assert.is_false(core.on_mouse(LEFT_DOWN, 10, 20, 0, true))
      assert.are.equal(0, #widget.mice)
    end)

    it("passes nothing while something is suppressing", function()
      local widget = core.register(mouse_widget())
      login()
      core.on_status_change(EVENT_STATUS)
      assert.is_false(core.on_mouse(LEFT_DOWN, 10, 20, 0, false))
      assert.are.equal(0, #widget.mice)
    end)

    it("answers false and calls nobody after unload", function()
      local widget = core.register(mouse_widget())
      login()
      core.on_unload()
      assert.is_false(core.on_mouse(LEFT_DOWN, 10, 20, 0, false))
      assert.are.equal(0, #widget.mice)
    end)

    it("reports whether any registered component wants the mouse", function()
      assert.is_false(core.wants_mouse())
      core.register(mouse_widget())
      assert.is_true(core.wants_mouse())
    end)
  end)

  -- Touchpoint 2: a component exposing `anchors() -> {names}` keeps pos and
  -- scale per anchor inside its layout file; core applies, clamps, describes
  -- and overlays each anchor on its own. `visible` stays per component.
  -- Widgets without `anchors()` take the paths above unchanged.
  describe("multi-anchor components", function()
    local ANCHORS = { "top", "bottom" }

    local function anchored_defaults()
      return {
        layout = {
          anchors = {
            top = { pos = { x = 100, y = 100 }, scale = 1 },
            bottom = { pos = { x = 400, y = 600 }, scale = 1 },
          },
          visible = true,
        },
      }
    end

    local function cross(names)
      return fakes.widget("cross", anchored_defaults(), names or ANCHORS)
    end

    it("applies each anchor's own position and scale from the defaults", function()
      local widget = core.register(cross())
      login()
      assert.are.same({ 100, 100 }, widget.anchor.top.pos)
      assert.are.same({ 400, 600 }, widget.anchor.bottom.pos)
      assert.are.equal(1, widget.anchor.top.scale)
      assert.is_true(widget.shown)
    end)

    it("pulls a stored anchor that is off screen back into reach, alone", function()
      env.fs.put(
        "data/Azureblood/default/cross/layout.lua",
        "return { anchors = { bottom = { pos = { x = 5000, y = 4000 } } } }"
      )
      local widget = core.register(cross())
      login()
      assert.are.same({ 1720, 980 }, widget.anchor.bottom.pos)
      assert.are.same({ 100, 100 }, widget.anchor.top.pos, "the on-screen anchor must not move")
    end)

    it("repairs an anchor scale below the floor in the stored state", function()
      env.fs.put("data/Azureblood/default/cross/layout.lua", "return { anchors = { top = { scale = 0.05 } } }")
      local widget = core.register(cross())
      login()
      assert.are.equal(0.25, widget.anchor.top.scale)
      assert.are.equal(1, widget.anchor.bottom.scale)
    end)

    it("lists every anchor's position and scale", function()
      core.register(cross())
      login()
      core.on_command({ "list" })
      local said = env.said()
      assert.is_not_nil(said:find("cross", 1, true), "said: " .. said)
      assert.is_not_nil(said:find("top", 1, true))
      assert.is_not_nil(said:find("bottom", 1, true))
      assert.is_not_nil(said:find("400,600", 1, true), "said: " .. said)
    end)

    it("drags one anchor in layout mode and persists it without moving the other", function()
      local widget = core.register(cross())
      login()
      core.on_command({ "layout" })
      assert.is_true(core.on_mouse(LEFT_DOWN, 450, 650))
      assert.is_true(core.on_mouse(MOVE, 750, 850))
      assert.is_true(core.on_mouse(LEFT_UP, 750, 850))

      assert.are.same({ 700, 800 }, widget.anchor.bottom.pos)
      assert.are.same({ 100, 100 }, widget.anchor.top.pos)
      local written = env.fs.files["data/Azureblood/default/cross/layout.lua"]
      assert.is_not_nil(written:find("x = 700", 1, true), "wrote: " .. written)
      assert.is_not_nil(written:find("x = 100", 1, true), "the other anchor keeps its place on disk")
    end)

    it("scales one anchor with the wheel and saves", function()
      local widget = core.register(cross())
      login()
      core.on_command({ "layout" })
      assert.is_true(core.on_mouse(WHEEL, 150, 150, 120))
      assert.are.equal(2.2, widget.anchor.top.scale)
      assert.are.equal(1, widget.anchor.bottom.scale)
      assert.is_not_nil(env.fs.files["data/Azureblood/default/cross/layout.lua"]:find("scale = 2.2", 1, true))
    end)

    it("right-click on any anchor toggles the whole component off", function()
      local widget = core.register(cross())
      login()
      core.on_command({ "layout" })
      assert.is_true(core.on_mouse(RIGHT_DOWN, 450, 650))
      assert.is_true(widget.shown, "still force-shown while positioning")
      assert.is_not_nil(env.fs.files["data/Azureblood/default/cross/layout.lua"]:find("visible = false", 1, true))
      core.on_command({ "layout" })
      assert.is_false(widget.shown)
    end)

    --[[ Per-anchor visibility. The widget's own `visible` still governs the
         whole of it; an anchor's is a second, narrower switch stored beside
         its pos and scale, and ABSENT there means shown. ]]
    it("takes one hidden anchor down and leaves the rest on screen", function()
      env.fs.put(
        "data/Azureblood/default/cross/layout.lua",
        "return { anchors = { bottom = { pos = { x = 400, y = 600 }, scale = 1, visible = false } } }"
      )
      local widget = core.register(cross())
      login()
      assert.is_false(widget.anchor.bottom.shown)
      assert.is_true(widget.anchor.top.shown)
      assert.is_true(widget.shown, "the widget itself is still on screen")
    end)

    --[[ The mirror of "anchored defaults, no anchors() member" below: the
         member is there and the defaults are not anchored, so there is no
         anchor state to address. Core falls back to the whole-widget show
         rather than leaving a registered component silently off screen. ]]
    it("shows a widget that declares anchors its defaults never seeded", function()
      local widget = core.register(fakes.widget("odd", { layout = { pos = { x = 10, y = 20 }, scale = 1 } }, ANCHORS))
      login()
      assert.is_true(widget.shown)
    end)

    it("takes every anchor down through the widget's own switch", function()
      local widget = core.register(cross())
      login()
      core.on_command({ "hide", "cross" })
      assert.is_false(widget.shown)
    end)

    it("force-shows a hidden anchor in layout mode", function()
      env.fs.put(
        "data/Azureblood/default/cross/layout.lua",
        "return { anchors = { bottom = { pos = { x = 400, y = 600 }, scale = 1, visible = false } } }"
      )
      local widget = core.register(cross())
      login()
      core.on_command({ "layout" })
      assert.is_true(widget.shown)
      core.on_command({ "layout" })
      assert.is_false(widget.anchor.bottom.shown, "and back down when the mode ends")
    end)

    it("hides and shows one anchor by name from //hud, persisting each", function()
      local widget = core.register(cross())
      login()
      core.on_command({ "hide", "cross", "bottom" })
      assert.is_false(widget.anchor.bottom.shown)
      assert.is_true(widget.anchor.top.shown)
      assert.is_true(widget.shown)
      local written = env.fs.files["data/Azureblood/default/cross/layout.lua"]
      assert.is_not_nil(written:find("visible = false", 1, true), "wrote: " .. written)

      core.on_command({ "show", "cross", "bottom" })
      assert.is_true(widget.anchor.bottom.shown)
    end)

    -- The two switches are independent, so this is not an error - but a
    -- command that draws nothing and says nothing is indistinguishable from
    -- one that failed.
    it("says the widget itself is off when an anchor is shown under it", function()
      local widget = core.register(cross())
      login()
      core.on_command({ "hide", "cross" })
      core.on_command({ "show", "cross", "bottom" })
      local said = env.said()
      assert.is_not_nil(said:find("//hud show cross", 1, true), "said: " .. said)
      assert.is_false(widget.shown, "and the widget stays off")
    end)

    it("says nothing of the sort when the widget is on", function()
      core.register(cross())
      login()
      core.on_command({ "hide", "cross", "bottom" })
      assert.is_nil(env.said():find("//hud show cross", 1, true), "said: " .. env.said())
    end)

    it("refuses an anchor name the component does not have", function()
      core.register(cross())
      login()
      core.on_command({ "hide", "cross", "middle" })
      local said = env.said()
      assert.is_not_nil(said:find("middle", 1, true), "said: " .. said)
      assert.is_not_nil(said:find("top", 1, true), "the names it does have are worth saying")
    end)

    it("refuses an anchor name on a component that has none", function()
      core.register(fakes.widget("bar"))
      login()
      core.on_command({ "hide", "bar", "top" })
      assert.is_not_nil(env.said():find("no anchors", 1, true), "said: " .. env.said())
    end)

    it("lists each anchor's own state beside its placement", function()
      env.fs.put(
        "data/Azureblood/default/cross/layout.lua",
        "return { anchors = { bottom = { pos = { x = 400, y = 600 }, scale = 1, visible = false } } }"
      )
      core.register(cross())
      login()
      core.on_command({ "list" })
      local said = env.said()
      assert.is_not_nil(said:find("bottom - hidden", 1, true), "said: " .. said)
      assert.is_not_nil(said:find("top - shown", 1, true), "said: " .. said)
    end)

    it("hides one anchor with SHIFT + right-click in layout mode", function()
      local widget = core.register(cross())
      login()
      core.on_command({ "layout" })
      core.on_keyboard(DIK_SHIFT, true)
      assert.is_true(core.on_mouse(RIGHT_DOWN, 450, 650))
      assert.is_true(widget.shown, "still force-shown while positioning")
      local written = env.fs.files["data/Azureblood/default/cross/layout.lua"]
      assert.is_not_nil(written:find("visible = false", 1, true), "wrote: " .. written)

      core.on_command({ "layout" })
      assert.is_false(widget.anchor.bottom.shown)
      assert.is_true(widget.anchor.top.shown)
      assert.is_true(widget.shown)
    end)

    it("greys a hidden anchor's highlight and leaves its siblings lit", function()
      env.fs.put(
        "data/Azureblood/default/cross/layout.lua",
        "return { anchors = { bottom = { pos = { x = 400, y = 600 }, scale = 1, visible = false } } }"
      )
      core.register(cross())
      login()
      core.on_command({ "layout" })
      assert.are.equal("cross:top", env.prims.texts[1].last.text)
      assert.are.equal("cross:bottom (hidden)", env.prims.texts[2].last.text)
    end)

    it("draws one highlight per anchor, named for it, and clears them on exit", function()
      core.register(cross())
      login()
      core.on_command({ "layout" })
      assert.are.equal(2, #env.prims.images)
      assert.are.same({ 100, 100 }, { env.prims.images[1].x, env.prims.images[1].y })
      assert.are.same({ 400, 600 }, { env.prims.images[2].x, env.prims.images[2].y })
      assert.are.equal("cross:top", env.prims.texts[1].last.text)
      assert.are.equal("cross:bottom", env.prims.texts[2].last.text)

      core.on_command({ "layout" })
      assert.is_false(env.prims.images[1].visible)
      assert.is_false(env.prims.images[2].visible)
    end)

    it("clears every anchor's highlight while something is suppressing", function()
      core.register(cross())
      login()
      core.on_command({ "layout" })
      core.on_status_change(EVENT_STATUS)
      assert.is_false(env.prims.images[1].visible)
      assert.is_false(env.prims.images[2].visible)
    end)

    -- The CB2 stand-in registered the anchored slot schema before the
    -- framework understood it, so layout repair fabricated and persisted a
    -- spurious top-level pos/scale. CB3 tolerates the residue and sheds it on
    -- the first write.
    it("drops a stray top-level pos and scale on the first write", function()
      env.fs.put(
        "data/Azureblood/default/cross/layout.lua",
        "return { pos = { x = 0, y = 0 }, scale = 1, visible = true, "
          .. "anchors = { top = { pos = { x = 100, y = 100 }, scale = 1 }, "
          .. "bottom = { pos = { x = 400, y = 600 }, scale = 1 } } }"
      )
      core.register(cross())
      login()

      core.on_command({ "hide", "cross" })
      local written = env.fs.files["data/Azureblood/default/cross/layout.lua"]
      assert.is_nil(written:find("x = 0", 1, true), "wrote: " .. written)
    end)

    it("skips an anchor the component lists but its defaults do not", function()
      local widget = core.register(cross({ "top", "bottom", "ghost" }))
      assert.has_no.errors(function()
        login()
        core.on_command({ "list" })
      end)
      assert.is_nil(widget.anchor.ghost, "nothing must be applied to an anchor with no state")
      assert.are.same({ 100, 100 }, widget.anchor.top.pos)
    end)

    it("skips a widget whose defaults are anchored but which exposes no anchors()", function()
      -- Anchored defaults with no anchors() member. layout.repair strips the
      -- top-level pos, so the single-anchor apply must skip the mismatch
      -- rather than crash on it.
      local widget = core.register(fakes.widget("odd", anchored_defaults()))
      assert.has_no.errors(function()
        login()
      end)
      assert.is_nil(widget.pos, "nothing must be applied through the mismatch")
      assert.is_true(widget.shown)
    end)

    it("lists the mismatched widget without its unplaceable position", function()
      core.register(fakes.widget("odd", anchored_defaults()))
      login()
      assert.has_no.errors(function()
        core.on_command({ "list" })
      end)
      assert.is_not_nil(env.said():find("odd - shown", 1, true), "said: " .. env.said())
    end)

    it("treats a non-table anchors() answer as a single-anchor component", function()
      local widget = fakes.widget("odd", placed(100, 200))
      widget.anchors = function()
        return 5
      end
      core.register(widget)
      assert.has_no.errors(function()
        login()
      end)
      assert.are.same({ 100, 200 }, widget.pos)
    end)

    it("keeps a named slot's anchors apart from the default slot's", function()
      local widget = core.register(cross())
      login()
      core.on_command({ "slot", "create", "raid" })
      core.on_command({ "slot", "raid" })
      core.on_command({ "layout" })
      core.on_mouse(LEFT_DOWN, 450, 650)
      core.on_mouse(LEFT_UP, 750, 850)
      core.on_command({ "layout" })
      assert.are.same({ 700, 800 }, widget.anchor.bottom.pos)

      core.on_command({ "slot", "default" })
      assert.are.same({ 400, 600 }, widget.anchor.bottom.pos)
    end)
  end)

  -- Touchpoint 5: a component declaring `wants_store = true` is attached with
  -- a third argument, a store accessor over its own config directory. The
  -- others see exactly what they always did.
  describe("directory config store", function()
    local function store_widget(name)
      local widget = bar(name)
      widget.wants_store = true
      return widget
    end

    it("hands a store accessor to a component that claims the directory form", function()
      local widget = core.register(store_widget())
      login()
      assert.is_not_nil(widget.store)
      assert.is_true(widget.store.save("WAR", { active_set = 2 }))
      -- Beside the two files core owns, never into them: nothing has persisted
      -- either at this point, and a store save must not be what creates one.
      assert.is_nil(env.fs.files["data/Azureblood/default/bar/config.lua"])
      assert.is_nil(env.fs.files["data/Azureblood/default/bar/layout.lua"])
      assert.is_not_nil(env.fs.files["data/Azureblood/default/bar/WAR.lua"])
      assert.are.same({ active_set = 2 }, widget.store.load("WAR"))
    end)

    it("passes no store to a component that does not claim it", function()
      local widget = core.register(bar())
      login()
      assert.is_not_nil(widget.config)
      assert.is_nil(widget.store)
    end)

    it("attaches with the store on a login after registration too", function()
      local widget = core.register(store_widget())
      assert.is_nil(widget.store)
      login()
      assert.is_not_nil(widget.store)
    end)

    it("clears the directory on reset and re-attaches with a working store", function()
      local widget = core.register(store_widget())
      login()
      widget.store.save("WAR", { active_set = 5 })
      core.on_command({ "reset", "bar" })
      assert.is_nil(env.fs.files["data/Azureblood/default/bar/WAR.lua"], "reset must not leave per-job files behind")
      assert.is_nil(widget.store.load("WAR"))
      assert.is_true(widget.store.save("WAR", { active_set = 1 }))
    end)

    it("gives each slot its own store, copied when the slot is created", function()
      local widget = core.register(store_widget())
      login()
      widget.store.save("WAR", { active_set = 5 })

      core.on_command({ "slot", "create", "raid" })
      assert.is_not_nil(env.fs.files["data/Azureblood/raid/bar/WAR.lua"], "the store copies with the slot")

      core.on_command({ "slot", "raid" })
      assert.are.same({ active_set = 5 }, widget.store.load("WAR"))
      widget.store.save("WAR", { active_set = 8 })

      core.on_command({ "slot", "default" })
      assert.are.same({ active_set = 5 }, widget.store.load("WAR"), "the other slot's bindings are untouched")
    end)

    it("rebuilds the store after //hud copy, so copied files are not shadowed by a stale cache", function()
      env.fs.put("data/Alpha/default/bar/config.lua", "return {}")
      env.fs.put("data/Alpha/default/bar/WAR.lua", "return { active_set = 7 }")
      local widget = core.register(store_widget())
      login()
      widget.store.save("WAR", { active_set = 1 })
      core.on_command({ "copy", "Alpha", "Azureblood" })
      assert.are.equal(7, widget.store.load("WAR").active_set)
    end)
  end)
end)
