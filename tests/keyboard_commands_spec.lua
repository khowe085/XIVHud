local new_keyboard = require("lib/keyboard")
local new_keyboard_commands = require("lib/keyboard_commands")

describe("keyboard commands", function()
  local config, readable, saves, releases, keyboard, commands

  local function build()
    keyboard = new_keyboard({
      config = function()
        return config
      end,
      deliver = function()
        return true
      end,
      check = function(value)
        if value == "nope" then
          return nil, "no behavior nope"
        end
        return true
      end,
    })
    commands = new_keyboard_commands({
      keyboard = keyboard,
      reload = function()
        return readable
      end,
      save = function()
        saves = saves + 1
      end,
      release = function()
        releases = releases + 1
      end,
      describe_action = function(record)
        return record.type .. " " .. record.action
      end,
    })
  end

  before_each(function()
    config, readable, saves, releases = { enabled = false }, true, 0, 0
    build()
  end)

  it("says whether the map is on, then what is wrong with it", function()
    assert.are.same({ "keyboard: off" }, commands.handle({}))
    config = { enabled = true, map = { f9 = "nope" } }
    assert.are.same({ "keyboard: on", "keyboard: f9 - no behavior nope" }, commands.handle({}))
  end)

  it("switches the map on and saves it", function()
    assert.are.same({ "keyboard: on" }, commands.handle({ "on" }))
    assert.is_true(config.enabled)
    assert.are.equal(1, saves)
    assert.are.equal(0, releases)
  end)

  it("switches the map off, letting go of every key it held", function()
    config.enabled = true
    assert.are.same({ "keyboard: off" }, commands.handle({ "OFF" }))
    assert.is_false(config.enabled)
    assert.are.equal(1, saves)
    assert.are.equal(1, releases)
  end)

  it("refuses to switch over a file it could not read", function()
    readable = false
    assert.are.same({ "keyboard: data/keyboard.lua could not be read - fix it first" }, commands.handle({ "on" }))
    assert.is_false(config.enabled)
    assert.are.equal(0, saves)
  end)

  it("lists every key and what it does, in the words the map holds", function()
    config.map = { semicolon = "crossbar.left", f9 = { key = "f10" }, f10 = { type = "open", action = "map" } }
    assert.are.same({
      "keyboard: 3 keys",
      "  semicolon crossbar.left",
      "  f9 key f10",
      "  f10 open map",
    }, commands.handle({ "list" }))
  end)

  it("says when the map binds no key", function()
    config.map = {}
    assert.are.same({ "keyboard: no keys" }, commands.handle({ "list" }))
  end)

  it("answers anything else with its forms", function()
    local form = {
      "keyboard [on|off] - the keyboard map's state, or switch it",
      "keyboard list - every key and what it does",
    }
    assert.are.same(form, commands.handle({ "bind", "f9", "accept" }))
    assert.are.same(form, commands.handle({ "on", "now" }))
    assert.are.same(form, commands.handle({ "list", "all" }))
  end)
end)
