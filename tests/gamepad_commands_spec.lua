local new_commands = require("lib/gamepad_commands")
local new_gamepad = require("lib/gamepad")
local new_behaviors = require("lib/behaviors")
local new_bar_commands = require("lib/actionbar/commands")

local READ_FAILED = "gamepad: data/gamepad.lua could not be read - fix it first"
local SPACED = "gamepad: a gesture is one word with no spaces, like lt+y"
local BIND_FORM = "gamepad bind <gesture> <type> [<action>] [<target>] - or a behavior, or key <key name>;"
  .. " a gesture is buttons joined by +, the trigger last, like lt+y"

describe("gamepad commands", function()
  local config, readable, reloads, saved, focused, behaviors, commands

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
        return readable
      end,
      save = function()
        saved = saved + 1
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
    config = new_gamepad({}).config_defaults()
    readable, reloads, saved, focused = true, 0, 0, true
    build()
  end)

  describe("the bare verb and the switch", function()
    it("answers the status, then what is wrong with the map", function()
      config.map["lt+q"] = "accept"
      assert.are.same({ "gamepad: on - looking for a pad", "gamepad: lt+q - no button q" }, commands.handle({}))
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

    it("switches the bridge off and on, saving each", function()
      assert.are.same({ "gamepad: off" }, commands.handle({ "OFF" }))
      assert.is_false(config.enabled)
      assert.are.same({ "gamepad: on - looking for a pad" }, commands.handle({ "on" }))
      assert.is_true(config.enabled)
      assert.are.equal(2, saved)
    end)

    it("refuses to switch over a file it could not read", function()
      readable = false
      assert.are.same({ READ_FAILED }, commands.handle({ "off" }))
      assert.is_true(config.enabled)
      assert.are.equal(0, saved)
    end)

    it("still answers the status over a file it could not read", function()
      readable = false
      assert.are.same({ "gamepad: on - looking for a pad" }, commands.handle({}))
    end)

    it("answers the form for words it does not know, and nothing after it", function()
      config.map["lt+q"] = "accept"
      assert.are.same({
        "gamepad [on|off] - the bridge's state, or switch it",
        "gamepad list - every gesture and what it does",
        BIND_FORM,
        "gamepad unbind <gesture>",
      }, commands.handle({ "bogus" }))
    end)

    it("has no learn verb, and takes no key", function()
      assert.are.same(commands.handle({ "bogus" }), commands.handle({ "learn", "l4" }))
      assert.is_nil(commands.on_key)
      assert.is_nil(commands.release)
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
        "gamepad: lt+q - no button q; buttons are lt rt lb rb back start l3 r3 y b a x up right down left",
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
        "gamepad: lt+q - no button q; buttons are lt rt lb rb back start l3 r3 y b a x up right down left",
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
