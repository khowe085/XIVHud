local new_keyboard = require("lib/keyboard")

-- DirectInput scan codes.
local ONE, EIGHT, NINE, EQUALS = 2, 9, 10, 13
local SEMICOLON, APOSTROPHE, GRAVE, BACKSLASH = 39, 40, 41, 43
local F9 = 67

describe("keyboard", function()
  local config, delivered, answers, chat, keyboard

  -- A switched-on config carrying `overrides`.
  local function on(overrides)
    local settings = { enabled = true }
    for key, value in pairs(overrides or {}) do
      settings[key] = value
    end
    return settings
  end

  local function build(overrides)
    local deps = {
      config = function()
        return config
      end,
      -- Answers what `answers` holds for the behaviour, as a component would.
      deliver = function(behavior, down, cancelled)
        delivered[#delivered + 1] = { behavior, down, cancelled }
        return answers[behavior]
      end,
      is_component = function(value)
        return type(value) == "string" and value:find(".", 1, true) ~= nil
      end,
      chat_open = function()
        return chat
      end,
    }
    for key, value in pairs(overrides or {}) do
      deps[key] = value
    end
    return new_keyboard(deps)
  end

  before_each(function()
    config, delivered, answers, chat = on(), {}, {}, false
    keyboard = build()
  end)

  describe("the shipped map", function()
    it("is the crossbar's own keys", function()
      local map = keyboard.config_defaults().map
      assert.are.same({
        ["1"] = "crossbar.slot1",
        ["2"] = "crossbar.slot2",
        ["3"] = "crossbar.slot3",
        ["4"] = "crossbar.slot4",
        ["5"] = "crossbar.slot5",
        ["6"] = "crossbar.slot6",
        ["7"] = "crossbar.slot7",
        ["8"] = "crossbar.slot8",
        apostrophe = "crossbar.right",
        backslash = "crossbar.layer",
        equals = "crossbar.select",
        grave = "crossbar.switch",
        semicolon = "crossbar.left",
      }, map)
    end)

    it("ships switched off, and answers fresh defaults every time", function()
      local first = keyboard.config_defaults()
      first.map.semicolon = "changed"
      local defaults = keyboard.config_defaults()
      assert.is_false(defaults.enabled)
      assert.are.equal("crossbar.left", defaults.map.semicolon)
    end)

    it("reads the crossbar's scan codes as the keys they are", function()
      for dik, behavior in pairs({
        [SEMICOLON] = "crossbar.left",
        [APOSTROPHE] = "crossbar.right",
        [BACKSLASH] = "crossbar.layer",
        [GRAVE] = "crossbar.switch",
        [ONE] = "crossbar.slot1",
        [EIGHT] = "crossbar.slot8",
        [EQUALS] = "crossbar.select",
      }) do
        delivered = {}
        keyboard.on_key(dik, true, false)
        keyboard.on_key(dik, false, false)
        assert.are.same({ { behavior, true, false }, { behavior, false, false } }, delivered, tostring(dik))
      end
    end)

    it("leaves a key the map does not name to everyone else", function()
      assert.is_false(keyboard.on_key(NINE, true, false))
      assert.is_false(keyboard.on_key(NINE, false, false))
      assert.are.same({}, delivered)
    end)
  end)

  describe("a key's edges", function()
    it("takes a press its behaviour takes, and its release with it", function()
      answers["crossbar.left"] = true
      assert.is_true(keyboard.on_key(SEMICOLON, true, false))
      answers["crossbar.left"] = nil
      assert.is_true(keyboard.on_key(SEMICOLON, false, false), "the release goes where the press went")
    end)

    it("leaves a press its behaviour leaves, and its release with it", function()
      assert.is_false(keyboard.on_key(ONE, true, false))
      answers["crossbar.slot1"] = true
      assert.is_false(keyboard.on_key(ONE, false, false))
      assert.are.same({ { "crossbar.slot1", true, false }, { "crossbar.slot1", false, false } }, delivered)
    end)

    it("delivers a press once, answering each repeat as it answered the press", function()
      answers["crossbar.left"] = true
      keyboard.on_key(SEMICOLON, true, false)
      answers["crossbar.left"] = nil
      assert.is_true(keyboard.on_key(SEMICOLON, true, false))
      assert.are.same({ { "crossbar.left", true, false } }, delivered)
    end)

    it("ignores a press another addon took, and the release that follows it", function()
      assert.is_false(keyboard.on_key(SEMICOLON, true, true))
      assert.is_false(keyboard.on_key(SEMICOLON, false, false))
      assert.are.same({}, delivered)
    end)

    it("delivers the release of a press it delivered, though that release arrives taken", function()
      answers["crossbar.left"] = true
      keyboard.on_key(SEMICOLON, true, false)
      assert.is_true(keyboard.on_key(SEMICOLON, false, true))
      assert.are.same({ { "crossbar.left", true, false }, { "crossbar.left", false, false } }, delivered)
    end)

    it("delivers the release of a key held as it was switched off", function()
      keyboard.on_key(SEMICOLON, true, false)
      config = { enabled = false }
      keyboard.on_key(SEMICOLON, false, false)
      assert.are.same({ { "crossbar.left", true, false }, { "crossbar.left", false, false } }, delivered)
    end)
  end)

  describe("the chat line", function()
    it("still hands a component's behaviour every key, for the component to judge", function()
      chat = true
      keyboard.on_key(SEMICOLON, true, false)
      assert.are.same({ { "crossbar.left", true, false } }, delivered)
    end)

    it("leaves a key whose behaviour is a game key or an action to type", function()
      config = on({ map = { f9 = "accept", semicolon = { type = "open", action = "map" } } })
      answers.accept = true
      chat = true
      assert.is_false(keyboard.on_key(F9, true, false))
      assert.is_false(keyboard.on_key(SEMICOLON, true, false))
      assert.are.same({}, delivered)
    end)
  end)

  describe("release", function()
    it("lets go of every key it holds, cancelled, in the order they went down", function()
      keyboard.on_key(APOSTROPHE, true, false)
      keyboard.on_key(SEMICOLON, true, false)
      delivered = {}
      keyboard.release()
      assert.are.same({ { "crossbar.right", false, true }, { "crossbar.left", false, true } }, delivered)
    end)

    it("delivers nothing more for a key it let go", function()
      keyboard.on_key(SEMICOLON, true, false)
      keyboard.release()
      delivered = {}
      assert.is_false(keyboard.on_key(SEMICOLON, false, false))
      assert.are.same({}, delivered)
    end)
  end)

  describe("switched off", function()
    it("is switched in the config itself", function()
      keyboard.set_enabled(false)
      assert.is_false(config.enabled)
      assert.is_false(keyboard.enabled())
      keyboard.set_enabled(true)
      assert.is_true(config.enabled)
    end)

    it("takes and delivers nothing", function()
      config = { enabled = false }
      answers["crossbar.left"] = true
      assert.is_false(keyboard.on_key(SEMICOLON, true, false))
      assert.are.same({}, delivered)
    end)

    it("is off for anything but an explicit true, and with no config at all", function()
      for _, value in ipairs({ { enabled = "yes" }, false }) do
        config = value or nil
        assert.is_false(keyboard.enabled())
        assert.is_false(keyboard.on_key(SEMICOLON, true, false))
      end
      assert.are.same({}, delivered)
    end)
  end)

  describe("the map", function()
    it("uses the config's map as it stands, nothing filled in", function()
      config = on({ map = { f9 = "accept" } })
      answers.accept = true
      assert.is_true(keyboard.on_key(F9, true, false))
      assert.is_false(keyboard.on_key(SEMICOLON, true, false))
    end)

    it("uses the shipped map where the config has none", function()
      config = on({ map = "broken" })
      keyboard.on_key(SEMICOLON, true, false)
      assert.are.same({ { "crossbar.left", true, false } }, delivered)
    end)

    it("reads a key's name in any case and leaves a key set to false alone", function()
      config = on({ map = { F9 = "accept", semicolon = false } })
      keyboard.on_key(F9, true, false)
      keyboard.on_key(SEMICOLON, true, false)
      assert.are.same({ { "accept", true, false } }, delivered)
    end)

    it("reads a key whose own name has a plus in it", function()
      config = on({ map = { ["numpad+"] = "accept" } })
      keyboard.on_key(0x4E, true, false)
      assert.are.same({ { "accept", true, false } }, delivered)
      assert.are.same({}, keyboard.problems())
    end)

    it("hands a key's own entry over as the map holds it", function()
      local own = { key = "f10" }
      config = on({ map = { f9 = own } })
      keyboard.on_key(F9, true, false)
      assert.are.equal(own, delivered[1][1])
    end)

    it("lists each key and what it does, in keyboard order, leaving out what is unbound or broken", function()
      config = on({ map = { semicolon = "crossbar.left", ["1"] = "crossbar.slot1", f9 = false, nope = "x" } })
      assert.are.same({
        { key = "1", behavior = "crossbar.slot1" },
        { key = "semicolon", behavior = "crossbar.left" },
      }, keyboard.bindings())
    end)
  end)

  describe("problems", function()
    local function check(value)
      if value == "nope" then
        return nil, "no behavior nope"
      end
      return true
    end

    it("has none for the shipped map", function()
      keyboard = build({ check = check })
      assert.are.same({}, keyboard.problems())
    end)

    it("names each broken entry once, in order, and keeps the rest", function()
      keyboard = build({ check = check })
      config = on({
        map = {
          f9 = "nope",
          f10 = 5,
          ["semicolon+1"] = "crossbar.slot1",
          wat = "accept",
          x = false,
        },
      })
      assert.are.same({
        "keyboard: f10 - not a behavior",
        "keyboard: f9 - no behavior nope",
        "keyboard: semicolon+1 - one key per entry: the keyboard reads no chords",
        "keyboard: wat - no key wat",
      }, keyboard.problems())
    end)

    it("names one key written twice, and keeps the spelling that is not the shipped one", function()
      config = on({ map = { F9 = "accept", f9 = "cancel" } })
      assert.are.same({ "keyboard: F9 and f9 - the same key" }, keyboard.problems())
      keyboard.on_key(F9, true, false)
      assert.are.same({ { "accept", true, false } }, delivered)
    end)

    it("does not ask after behaviours it has no way to ask about", function()
      config = on({ map = { f9 = "nope" } })
      assert.are.same({}, keyboard.problems())
    end)
  end)
end)
