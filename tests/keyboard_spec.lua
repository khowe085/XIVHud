local new_keyboard = require("lib/keyboard")

-- DirectInput scan codes.
local ONE, EIGHT, NINE, ZERO, EQUALS = 2, 9, 10, 11, 13
local SEMICOLON, APOSTROPHE, GRAVE, BACKSLASH = 39, 40, 41, 43
local F9, UP = 67, 200
local LCTRL, RCTRL, LALT, LSHIFT = 29, 157, 56, 42

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
    it("carries the crossbar's own keys", function()
      local map = keyboard.config_defaults().map
      for key, behavior in pairs({
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
      }) do
        assert.are.equal(behavior, map[key], key)
      end
    end)

    it("carries the hotbar's six rows on Ctrl, Alt and Shift over the number row, and its set cycle", function()
      local map = keyboard.config_defaults().map
      for key, behavior in pairs({
        ["ctrl+1"] = "hotbar.bar1_slot1",
        ["ctrl+0"] = "hotbar.bar1_slot10",
        ["alt+5"] = "hotbar.bar2_slot5",
        ["shift+1"] = "hotbar.bar3_slot1",
        ["ctrl+shift+1"] = "hotbar.bar4_slot1",
        ["alt+shift+1"] = "hotbar.bar5_slot1",
        ["ctrl+alt+shift+0"] = "hotbar.bar6_slot10",
        ["ctrl+up"] = "hotbar.cycle",
        ["ctrl+down"] = "hotbar.cycle_back",
      }) do
        assert.are.equal(behavior, map[key], key)
      end
      local count = 0
      for _ in pairs(map) do
        count = count + 1
      end
      assert.are.equal(13 + 60 + 2, count)
    end)

    it("ships switched on, and answers fresh defaults every time", function()
      local first = keyboard.config_defaults()
      first.map.semicolon = "changed"
      local defaults = keyboard.config_defaults()
      assert.is_true(defaults.enabled)
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

    it("lets go of a press it delivered when another addon took the release, cancelled", function()
      answers["crossbar.left"] = true
      keyboard.on_key(SEMICOLON, true, false)
      assert.is_true(keyboard.on_key(SEMICOLON, false, true))
      assert.are.same({ { "crossbar.left", true, false }, { "crossbar.left", false, true } }, delivered)
    end)

    it("delivers nothing for the repeats of a press another addon took", function()
      keyboard.on_key(SEMICOLON, true, true)
      assert.is_false(keyboard.on_key(SEMICOLON, true, false))
      assert.are.same({}, delivered)
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
      config = on({
        map = {
          semicolon = "crossbar.left",
          ["1"] = "crossbar.slot1",
          ["Shift+Ctrl+1"] = "hotbar.bar4_slot1",
          ["ctrl+1"] = "hotbar.bar1_slot1",
          f9 = false,
          nope = "x",
        },
      })
      assert.are.same({
        { key = "1", behavior = "crossbar.slot1" },
        { key = "ctrl+1", behavior = "hotbar.bar1_slot1" },
        { key = "ctrl+shift+1", behavior = "hotbar.bar4_slot1" },
        { key = "semicolon", behavior = "crossbar.left" },
      }, keyboard.bindings())
    end)
  end)

  --[[ Ctrl, Alt and Shift, either side, held under a key make a chord: the
       hotbar's rows. They are matched exactly, and a key with no chord of
       its own falls back to its bare entry, as the crossbar ignored them. ]]
  describe("modifiers", function()
    local function chord(modifiers, dik)
      for _, modifier in ipairs(modifiers) do
        keyboard.on_key(modifier, true, false)
      end
      local taken = keyboard.on_key(dik, true, false)
      keyboard.on_key(dik, false, false)
      for _, modifier in ipairs(modifiers) do
        keyboard.on_key(modifier, false, false)
      end
      return taken
    end

    it("delivers a key's Ctrl chord while either Ctrl is held", function()
      chord({ LCTRL }, ONE)
      chord({ RCTRL }, ZERO)
      assert.are.same({
        { "hotbar.bar1_slot1", true, false },
        { "hotbar.bar1_slot1", false, false },
        { "hotbar.bar1_slot10", true, false },
        { "hotbar.bar1_slot10", false, false },
      }, delivered)
    end)

    it("matches the modifiers exactly, a key with no chord for them falling back to its bare entry", function()
      chord({ LCTRL, LALT }, ONE)
      chord({ LSHIFT }, SEMICOLON)
      assert.are.same({
        { "crossbar.slot1", true, false },
        { "crossbar.slot1", false, false },
        { "crossbar.left", true, false },
        { "crossbar.left", false, false },
      }, delivered)
    end)

    it("hands a chord the map names to that entry alone, though its behaviour leaves the press", function()
      assert.is_false(chord({ LALT }, ONE))
      assert.are.same({ { "hotbar.bar2_slot1", true, false }, { "hotbar.bar2_slot1", false, false } }, delivered)
    end)

    it("lets a chord go with its key, though its modifier came up first", function()
      answers["hotbar.bar1_slot1"] = true
      keyboard.on_key(LCTRL, true, false)
      assert.is_true(keyboard.on_key(ONE, true, false))
      keyboard.on_key(LCTRL, false, false)
      assert.is_true(keyboard.on_key(ONE, false, false))
      assert.are.same({ { "hotbar.bar1_slot1", true, false }, { "hotbar.bar1_slot1", false, false } }, delivered)
    end)

    it("hands a chord set to false to its key alone", function()
      config = on({ map = { ["1"] = "crossbar.slot1", ["ctrl+1"] = false } })
      chord({ LCTRL }, ONE)
      assert.are.same({ { "crossbar.slot1", true, false }, { "crossbar.slot1", false, false } }, delivered)
    end)

    it("leaves a modifier's own edges to the game", function()
      assert.is_false(keyboard.on_key(LCTRL, true, false))
      assert.is_false(keyboard.on_key(LCTRL, false, false))
      assert.are.same({}, delivered)
    end)

    it("reads the modifiers in any order and case, and a key whose name has a plus in it", function()
      config = on({ map = { ["Shift+CTRL+f9"] = "x", ["ctrl+numpad+"] = "y" } })
      chord({ LCTRL, LSHIFT }, F9)
      chord({ RCTRL }, 0x4E)
      assert.are.same(
        { { "x", true, false }, { "x", false, false }, { "y", true, false }, { "y", false, false } },
        delivered
      )
      assert.are.same({}, keyboard.problems())
    end)

    it("delivers nothing for a key's repeats, though a modifier arrives under it", function()
      keyboard.on_key(UP, true, false)
      keyboard.on_key(LCTRL, true, false)
      assert.is_false(keyboard.on_key(UP, true, false))
      assert.are.same({}, delivered)
    end)

    it("forgets every held modifier on a release", function()
      keyboard.on_key(LCTRL, true, false)
      keyboard.release()
      keyboard.on_key(ONE, true, false)
      assert.are.same({ { "crossbar.slot1", true, false } }, delivered)
    end)

    it("tracks the modifiers while switched off", function()
      config = { enabled = false }
      keyboard.on_key(LCTRL, true, false)
      config = on()
      keyboard.on_key(ONE, true, false)
      assert.are.same({ { "hotbar.bar1_slot1", true, false } }, delivered)
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
        "keyboard: semicolon+1 - semicolon is no modifier: a chord is ctrl, alt or shift over one key",
        "keyboard: wat - no key wat",
      }, keyboard.problems())
    end)

    it("names a modifier written twice", function()
      config = on({ map = { ["ctrl+ctrl+1"] = "x" } })
      assert.are.same({ "keyboard: ctrl+ctrl+1 - names ctrl twice" }, keyboard.problems())
    end)

    it("names one key written twice, keeping the first in order", function()
      config = on({ map = { F9 = "accept", f9 = "cancel" } })
      assert.are.same({ "keyboard: F9 and f9 - the same key" }, keyboard.problems())
      keyboard.on_key(F9, true, false)
      assert.are.same({ { "accept", true, false } }, delivered)
    end)

    it("keeps a spelling of the user's own over the shipped one for the same chord", function()
      config = on({ map = { ["shift+ctrl+1"] = "mine", ["ctrl+shift+1"] = "hotbar.bar4_slot1" } })
      assert.are.same({ "keyboard: shift+ctrl+1 and ctrl+shift+1 - the same key" }, keyboard.problems())
      keyboard.on_key(LCTRL, true, false)
      keyboard.on_key(LSHIFT, true, false)
      keyboard.on_key(ONE, true, false)
      assert.are.same({ { "mine", true, false } }, delivered)
    end)

    it("does not ask after behaviours it has no way to ask about", function()
      config = on({ map = { f9 = "nope" } })
      assert.are.same({}, keyboard.problems())
    end)
  end)
end)
