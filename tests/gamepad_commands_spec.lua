local new_commands = require("lib/gamepad_commands")
local new_gamepad = require("lib/gamepad")
local new_behaviors = require("lib/behaviors")
local new_bar_commands = require("lib/actionbar/commands")

local ESCAPE, ENTER, NUMPAD_ENTER = 1, 28, 156

local READ_FAILED = "gamepad: data/gamepad.lua could not be read - fix it first"
local SPACED = "gamepad: a gesture is one word with no spaces, like lt+y"
local BIND_FORM = "gamepad bind <gesture> <type> [<action>] [<target>] - or a behavior, or key <key name>;"
  .. " a gesture is buttons joined by +, the trigger last, like lt+y"
local LEARN_FORM = "gamepad learn <name> [off] - the next key pressed is <name>'s"

describe("gamepad commands", function()
  -- `on_disk`, when set, is what the next re-read of the file finds.
  local config, on_disk, readable, reloads, saved, said, focused, behaviors, commands

  -- The action service's own answers, narrowed to what these specs bind.
  local function validate(record)
    if record.type == "open" then
      if record.action == "map" then
        return true
      end
      return nil, "unknown open target: " .. tostring(record.action)
    end
    if record.type == "ma" then
      if type(record.action) == "string" then
        return true
      end
      return nil, "/ma needs an action name"
    end
    return nil, "unknown action type: " .. tostring(record.type)
  end

  local ACTION_TYPES = { ma = true, open = true }

  -- Every behaviour the shipped map names a component for.
  local CROSSBAR = {}
  for _, name in ipairs({ "left", "right", "wxhb_left", "wxhb_right", "switch", "binder", "draw" }) do
    CROSSBAR[#CROSSBAR + 1] = "crossbar." .. name
  end
  for slot = 1, 8 do
    CROSSBAR[#CROSSBAR + 1] = "crossbar.slot" .. slot
  end

  local function build(overrides)
    local pad = new_gamepad({
      read = function()
        return nil
      end,
      now = function()
        return 0
      end,
      config = function()
        return config
      end,
      check = function(value)
        return behaviors.check(value)
      end,
    })
    behaviors = new_behaviors({
      send_key = function() end,
      validate = validate,
      fire_action = function() end,
      components = function()
        return CROSSBAR
      end,
      deliver = function() end,
    })
    local parser = new_bar_commands({ validate = validate })
    local deps = {
      gamepad = pad,
      behaviors = behaviors,
      parse_action = parser.parse_action,
      is_action_type = function(kind)
        return ACTION_TYPES[kind] == true
      end,
      describe_action = parser.describe_action,
      reload = function()
        reloads = reloads + 1
        if on_disk ~= nil then
          config, on_disk = on_disk, nil
        end
        return readable
      end,
      save = function()
        saved = saved + 1
      end,
      say = function(line)
        said[#said + 1] = line
      end,
      focused = function()
        return focused
      end,
    }
    for key, value in pairs(overrides or {}) do
      deps[key] = value
    end
    commands = new_commands(deps)
  end

  before_each(function()
    config, on_disk = new_gamepad({}).config_defaults(), nil
    readable, reloads, saved, said, focused = true, 0, 0, {}, true
    build()
  end)

  describe("the bare verb and the switch", function()
    it("answers the status, then what is wrong with the map", function()
      config.map["lt+q"] = "accept"
      assert.are.same({ "gamepad: off", "gamepad: lt+q - no button q" }, commands.handle({}))
    end)

    it("re-reads the file first", function()
      commands.handle({})
      assert.are.equal(1, reloads)
    end)

    it("says the bridge is paused while the game is out of focus", function()
      config.enabled = true
      focused = false
      assert.are.same({ "gamepad: on - looking for a pad - paused - the game is not in focus" }, commands.handle({}))
    end)

    it("switches the bridge on and off, saving each", function()
      assert.are.same({ "gamepad: on - looking for a pad" }, commands.handle({ "on" }))
      assert.is_true(config.enabled)
      commands.handle({ "OFF" })
      assert.is_false(config.enabled)
      assert.are.equal(2, saved)
    end)

    it("refuses to switch over a file it could not read", function()
      readable = false
      assert.are.same({ READ_FAILED }, commands.handle({ "on" }))
      assert.is_false(config.enabled)
      assert.are.equal(0, saved)
    end)

    it("still answers the status over a file it could not read", function()
      readable = false
      assert.are.same({ "gamepad: off" }, commands.handle({}))
    end)

    it("answers the form for words it does not know, and nothing after it", function()
      config.map["lt+q"] = "accept"
      assert.are.same({
        "gamepad [on|off] - the bridge's state, or switch it",
        "gamepad list - every gesture and what it does",
        BIND_FORM,
        "gamepad unbind <gesture>",
        LEARN_FORM,
      }, commands.handle({ "bogus" }))
    end)
  end)

  describe("bind", function()
    it("binds a gesture to a shipped behaviour, saving", function()
      assert.are.same({ "gamepad: bound b+a to accept" }, commands.handle({ "bind", "b+a", "accept" }))
      assert.are.equal("accept", config.map["b+a"])
      assert.are.equal(1, saved)
    end)

    it("binds one to a component's behaviour", function()
      assert.are.same(
        { "gamepad: bound rt+lb to crossbar.left" },
        commands.handle({ "bind", "RT+LB", "crossbar.left" })
      )
      assert.are.equal("crossbar.left", config.map["rt+lb"])
    end)

    it("takes a behaviour's name in any case", function()
      commands.handle({ "bind", "b+a", "Accept" })
      assert.are.equal("accept", config.map["b+a"])
    end)

    it("binds one to a game key", function()
      assert.are.same({ "gamepad: bound l3 to key numpad*" }, commands.handle({ "bind", "l3", "key", "NumPad*" }))
      assert.are.same({ key = "numpad*" }, config.map.l3)
    end)

    it("refuses a key name a console command could not take", function()
      assert.are.same(
        { "gamepad: enter;quit is not a key name" },
        commands.handle({ "bind", "l3", "key", "enter;quit" })
      )
      assert.are.equal("target_self", config.map.l3)
      assert.are.equal(0, saved)
    end)

    it("wants exactly one key name", function()
      for _, words in ipairs({ { "bind", "l3", "key" }, { "bind", "l3", "key", "a", "b" } }) do
        assert.are.same({ "gamepad: key takes one key name, like numpad*" }, commands.handle(words))
      end
    end)

    it("binds one to anything a slot can hold, read as bind reads it", function()
      assert.are.same(
        { "gamepad: bound lt+r3 to ma Cure IV <t>" },
        commands.handle({ "bind", "lt+r3", "ma", "Cure IV", "<t>" })
      )
      assert.are.same({ type = "ma", action = "Cure IV", target = "t" }, config.map["lt+r3"])
      assert.are.same({ "gamepad: bound back to open map" }, commands.handle({ "bind", "back", "open", "map" }))
      assert.are.same({ type = "open", action = "map" }, config.map.back)
    end)

    it("says what bind's parser refuses", function()
      assert.are.same({ "gamepad: /ma needs an action name" }, commands.handle({ "bind", "a", "ma" }))
      assert.are.same(
        { "gamepad: alias=, icon= and context= need a slot - drop them" },
        commands.handle({ "bind", "a", "ma", "Cure", "alias=C" })
      )
      assert.are.equal(0, saved)
    end)

    it("refuses a word that is neither a bind type nor a behaviour, naming the behaviours", function()
      assert.are.same({
        "gamepad: acept is neither a bind type nor a behavior - behaviors are "
          .. table.concat(behaviors.names(), ", "),
      }, commands.handle({ "bind", "a", "acept" }))
      assert.are.equal("accept", behaviors.names()[1])
    end)

    it("refuses words after a behaviour's name", function()
      assert.are.same(
        { "gamepad: accept takes nothing after it - drop now please" },
        commands.handle({ "bind", "a", "accept", "now", "please" })
      )
    end)

    it("refuses a gesture with spaces in it", function()
      for _, words in ipairs({
        { "bind", "lt", "+", "y", "accept" },
        { "bind", "lt+", "y", "accept" },
        { "bind", "lt", "+y", "accept" },
      }) do
        assert.are.same({ SPACED }, commands.handle(words), table.concat(words, " "))
      end
      assert.are.equal(0, saved)
    end)

    it("names the buttons when it does not know one", function()
      assert.are.same({
        "gamepad: lt+q - no button q; buttons are lt rt lb rb back start l3 r3 y b a x up right down left,"
          .. " or a name given a key with //hud gamepad learn <name>",
      }, commands.handle({ "bind", "lt+q", "accept" }))
    end)

    it("names the learned buttons among them", function()
      config.extra.l4 = 100
      assert.are.same({
        "gamepad: lt+q - no button q; buttons are lt rt lb rb back start l3 r3 y b a x up right down left l4,"
          .. " or a name given a key with //hud gamepad learn <name>",
      }, commands.handle({ "bind", "lt+q", "accept" }))
    end)

    it("says what else is wrong with a gesture", function()
      assert.are.same({ "gamepad: lt+lt - names lt twice" }, commands.handle({ "bind", "lt+lt", "accept" }))
    end)

    it("binds behaviours and keys without the action service, and says actions need it", function()
      build({ parse_action = false, is_action_type = false })
      assert.are.same({ "gamepad: bound a to cancel" }, commands.handle({ "bind", "a", "cancel" }))
      assert.are.same(
        { "gamepad: actions need the action service, which did not load" },
        commands.handle({ "bind", "a", "ma", "Cure" })
      )
    end)

    it("refuses to bind over a file it could not read", function()
      readable = false
      assert.are.same({ READ_FAILED }, commands.handle({ "bind", "a", "cancel" }))
      assert.are.equal("accept", config.map.a)
      assert.are.equal(0, saved)
    end)

    it("answers its form when the words run short", function()
      for _, words in ipairs({ { "bind" }, { "bind", "a" } }) do
        assert.are.same({ BIND_FORM }, commands.handle(words))
      end
    end)
  end)

  describe("unbind", function()
    it("unbinds a gesture, saving", function()
      assert.are.same({ "gamepad: unbound a" }, commands.handle({ "unbind", "A" }))
      assert.is_false(config.map.a)
      assert.are.equal(1, saved)
    end)

    it("says when the gesture is not bound", function()
      assert.are.same({ "gamepad: lt+rb+y - not bound" }, commands.handle({ "unbind", "lt+rb+y" }))
      assert.are.equal(0, saved)
    end)

    it("refuses a gesture with spaces in it", function()
      assert.are.same({ SPACED }, commands.handle({ "unbind", "lt", "+", "y" }))
    end)

    it("names the buttons when it does not know one", function()
      assert.are.same({
        "gamepad: lt+q - no button q; buttons are lt rt lb rb back start l3 r3 y b a x up right down left,"
          .. " or a name given a key with //hud gamepad learn <name>",
      }, commands.handle({ "unbind", "lt+q" }))
    end)

    it("refuses over a file it could not read", function()
      readable = false
      assert.are.same({ READ_FAILED }, commands.handle({ "unbind", "a" }))
      assert.are.equal("accept", config.map.a)
    end)

    it("answers its form for anything else", function()
      for _, words in ipairs({ { "unbind" }, { "unbind", "a", "b" } }) do
        assert.are.same({ "gamepad unbind <gesture>" }, commands.handle(words))
      end
    end)
  end)

  describe("list", function()
    it("lists every gesture and what it does, in bind's words", function()
      config.map = {
        b = "cancel",
        a = false,
        l3 = { key = "numpad*" },
        ["lt+r3"] = { type = "ma", action = "Cure IV", target = "t" },
      }
      assert.are.same({
        "gamepad: 3 gestures",
        "  b cancel",
        "  l3 key numpad*",
        "  lt+r3 ma Cure IV <t>",
      }, commands.handle({ "list" }))
    end)

    it("names an action by its type where nothing can label it", function()
      build({ describe_action = false })
      config.map = { ["lt+r3"] = { type = "ma", action = "Cure IV", target = "t" } }
      assert.are.same({ "gamepad: 1 gesture", "  lt+r3 ma" }, commands.handle({ "list" }))
    end)

    it("counts one gesture as one", function()
      config.map = { b = "cancel" }
      assert.are.same({ "gamepad: 1 gesture", "  b cancel" }, commands.handle({ "list" }))
    end)

    it("says when nothing is bound", function()
      config.map = { a = false }
      assert.are.same({ "gamepad: no gestures" }, commands.handle({ "list" }))
    end)

    it("names the buttons given keys after the gestures", function()
      config.map = { b = "cancel" }
      config.extra = { l4 = 100, l5 = false, lpad = 101 }
      assert.are.same(
        { "gamepad: 1 gesture", "  b cancel", "gamepad: learned l4 (key 100), lpad (key 101)" },
        commands.handle({ "list" })
      )
    end)
  end)

  describe("learn", function()
    it("arms a capture, then gives the name the next key pressed, saving", function()
      assert.are.same({ "gamepad: press the key for l4 - Escape cancels" }, commands.handle({ "learn", "L4" }))
      assert.is_true(commands.on_key(100, true))
      assert.are.same({ "gamepad: l4 is key 100" }, said)
      assert.are.equal(100, config.extra.l4)
      assert.are.equal(1, saved)
    end)

    it("swallows the key it took until it comes up, repeats included", function()
      commands.handle({ "learn", "l4" })
      commands.on_key(100, true)
      assert.is_true(commands.on_key(100, true))
      assert.is_true(commands.on_key(100, false))
      assert.is_false(commands.on_key(100, true))
    end)

    it("leaves keys alone with nothing armed", function()
      assert.is_false(commands.on_key(100, true))
      assert.is_false(commands.on_key(100, false))
    end)

    it("moves a key another name has, and says which lost it", function()
      config.extra.r4 = 100
      commands.handle({ "learn", "l4" })
      commands.on_key(100, true)
      assert.are.same({ "gamepad: l4 is key 100 - r4 has no key now" }, said)
      assert.is_false(config.extra.r4)
    end)

    it("cancels on Escape, swallowing it", function()
      commands.handle({ "learn", "l4" })
      assert.is_true(commands.on_key(ESCAPE, true))
      assert.is_true(commands.on_key(ESCAPE, false))
      assert.are.same({ "gamepad: learn cancelled - l4 is unchanged" }, said)
      assert.is_false(config.extra.l4)
      assert.are.equal(0, saved)
      assert.is_false(commands.on_key(100, true))
    end)

    it("lets Enter and the modifiers through to the game, and goes on waiting", function()
      commands.handle({ "learn", "l4" })
      for _, dik in ipairs({ ENTER, NUMPAD_ENTER, 29, 157, 42, 54, 56, 184, 219, 220 }) do
        assert.is_false(commands.on_key(dik, true), tostring(dik))
        assert.is_false(commands.on_key(dik, false), tostring(dik))
      end
      assert.is_true(commands.on_key(100, true))
      assert.are.equal(100, config.extra.l4)
    end)

    it("re-reads the file before it saves the key, keeping what was edited meanwhile", function()
      commands.handle({ "learn", "l4" })
      on_disk = new_gamepad({}).config_defaults()
      on_disk.map["lt+y"] = "cancel"
      commands.on_key(100, true)
      assert.are.equal(2, reloads)
      assert.are.equal(100, config.extra.l4)
      assert.are.equal("cancel", config.map["lt+y"])
    end)

    it("saves nothing over a file it cannot read by then, still taking the key", function()
      commands.handle({ "learn", "l4" })
      readable = false
      assert.is_true(commands.on_key(100, true))
      assert.are.same({ READ_FAILED }, said)
      assert.is_false(config.extra.l4)
      assert.are.equal(0, saved)
      assert.is_true(commands.on_key(100, false))
      assert.is_false(commands.on_key(100, true), "and waits no more")
    end)

    it("forgets the keys it took once told everything is let go", function()
      commands.handle({ "learn", "l4" })
      commands.on_key(100, true)
      commands.release()
      assert.is_false(commands.on_key(100, true))
    end)

    it("takes no notice of an up that arrives first", function()
      commands.handle({ "learn", "l4" })
      assert.is_false(commands.on_key(100, false))
      assert.is_true(commands.on_key(101, true))
      assert.are.equal(101, config.extra.l4)
    end)

    it("arms for the name asked last", function()
      commands.handle({ "learn", "l4" })
      commands.handle({ "learn", "r4" })
      commands.on_key(100, true)
      assert.are.equal(100, config.extra.r4)
      assert.is_false(config.extra.l4)
    end)

    it("takes any plain name that is no pad button", function()
      commands.handle({ "learn", "lpad" })
      commands.on_key(100, true)
      assert.are.equal(100, config.extra.lpad)
    end)

    it("refuses a pad button, or a name that is not a plain word", function()
      assert.are.same({ "gamepad: a is a pad button" }, commands.handle({ "learn", "a" }))
      assert.are.same({ "gamepad: a name is a plain lowercase word" }, commands.handle({ "learn", "l4+y" }))
      assert.is_false(commands.on_key(100, true))
    end)

    it("takes a name's key away with off, saving", function()
      config.extra.l4 = 100
      assert.are.same({ "gamepad: l4 has no key now" }, commands.handle({ "learn", "l4", "OFF" }))
      assert.is_false(config.extra.l4)
      assert.are.equal(1, saved)
      assert.are.same({ "gamepad: l4 had no key" }, commands.handle({ "learn", "l4", "off" }))
      assert.are.equal(1, saved)
    end)

    it("disarms the name it takes the key from", function()
      commands.handle({ "learn", "l4" })
      commands.handle({ "learn", "l4", "off" })
      assert.is_false(commands.on_key(100, true))
    end)

    it("refuses to arm over a file it could not read", function()
      readable = false
      assert.are.same({ READ_FAILED }, commands.handle({ "learn", "l4" }))
      assert.is_false(commands.on_key(100, true))
    end)

    it("answers its form for anything else", function()
      for _, words in ipairs({ { "learn" }, { "learn", "l4", "on" }, { "learn", "l4", "off", "now" } }) do
        assert.are.same({ LEARN_FORM }, commands.handle(words))
      end
    end)
  end)

  describe("the map's problems", function()
    it("are answered once, for the first poll to say", function()
      config.map["lt+q"] = "accept"
      assert.are.same({ "gamepad: lt+q - no button q" }, commands.unsaid_problems())
      assert.are.same({}, commands.unsaid_problems())
    end)

    it("count as said once the bare verb has said them", function()
      config.map["lt+q"] = "accept"
      commands.handle({})
      assert.are.same({}, commands.unsaid_problems())
    end)
  end)
end)
