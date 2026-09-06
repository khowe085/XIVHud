local new_input = require("components/hotbar/input")

local LCTRL, RCTRL, LSHIFT, RSHIFT, LALT, RALT = 29, 157, 42, 54, 56, 184
local ONE, TWO, ZERO = 2, 3, 11
local UP, DOWN = 200, 208

local function world(overrides)
  local env = { chat_open = false, suppressed = false, layout = false, edit = false, disabled = false }
  for key, value in pairs(overrides or {}) do
    env[key] = value
  end
  local machine = new_input({
    chat_open = function()
      return env.chat_open
    end,
    suppressed = function()
      return env.suppressed
    end,
    layout_mode = function()
      return env.layout
    end,
    edit_mode = function()
      return env.edit
    end,
    disabled = function()
      return env.disabled
    end,
  })
  return machine, env
end

local function press(machine, dik, blocked)
  return machine.on_key(dik, true, 0, blocked == true)
end

local function release(machine, dik, blocked)
  return machine.on_key(dik, false, 0, blocked == true)
end

describe("the hotbar's keys", function()
  it("fires bar 1 off the bare number row, 0 being slot 10, and swallows both edges", function()
    local machine = world()
    local intent, block = press(machine, ONE)
    assert.are.same({ bar = "bar1", slot = 1 }, intent)
    assert.is_true(block)
    intent, block = release(machine, ONE)
    assert.is_nil(intent)
    assert.is_true(block, "the release of a key we took is ours too")
    intent = press(machine, ZERO)
    assert.are.equal(10, intent.slot)
  end)

  it("picks the row off the modifiers, matching exactly", function()
    local machine = world()
    local cases = {
      { held = { LCTRL }, bar = "bar2" },
      { held = { RALT }, bar = "bar3" },
      { held = { LSHIFT }, bar = "bar4" },
      { held = { RCTRL, RSHIFT }, bar = "bar5" },
      { held = { LALT, LSHIFT }, bar = "bar6" },
      { held = { LCTRL, LALT, LSHIFT }, bar = "bar7" },
    }
    for _, case in ipairs(cases) do
      for _, dik in ipairs(case.held) do
        local intent, block = press(machine, dik)
        assert.is_nil(intent)
        assert.is_false(block, "a modifier is never ours")
      end
      local intent = press(machine, TWO)
      assert.are.equal(case.bar, intent.bar, table.concat(case.held, "+"))
      assert.are.equal(2, intent.slot)
      release(machine, TWO)
      for _, dik in ipairs(case.held) do
        release(machine, dik)
      end
    end
  end)

  it("blocks a CTRL or ALT chord it fires, knowing the game acts on it too", function()
    local machine = world()
    press(machine, LCTRL)
    local intent, block = press(machine, ONE)
    assert.are.equal("bar2", intent.bar)
    assert.is_true(block)
  end)

  it("leaves CTRL+ALT alone: nothing fires and nothing is blocked", function()
    local machine = world()
    press(machine, LCTRL)
    press(machine, LALT)
    local intent, block = press(machine, ONE)
    assert.is_nil(intent)
    assert.is_false(block)
    intent, block = release(machine, ONE)
    assert.is_nil(intent)
    assert.is_false(block)
  end)

  it("ignores every other key", function()
    local machine = world()
    local intent, block = press(machine, 39)
    assert.is_nil(intent)
    assert.is_false(block)
  end)

  it("fires nothing and blocks nothing under any guard, and on a key a prior addon took", function()
    for _, guard in ipairs({ "chat_open", "suppressed", "layout", "edit", "disabled" }) do
      local machine, env = world()
      env[guard] = true
      local intent, block = press(machine, ONE)
      assert.is_nil(intent, guard)
      assert.is_false(block, guard)
      intent, block = release(machine, ONE)
      assert.is_nil(intent, guard)
      assert.is_false(block, guard .. ": a release of a key we never took")
    end
    local machine = world()
    local intent, block = press(machine, ONE, true)
    assert.is_nil(intent)
    assert.is_false(block)
  end)

  it("keeps tracking modifiers through a guard, so the row is right when it lifts", function()
    local machine, env = world()
    env.chat_open = true
    press(machine, LSHIFT)
    env.chat_open = false
    assert.are.equal("bar4", press(machine, ONE).bar)
  end)

  it("drops every held modifier and every latched key on focus loss", function()
    local machine = world()
    press(machine, LSHIFT)
    press(machine, ONE)
    machine.focus_lost()
    local intent, block = release(machine, ONE)
    assert.is_nil(intent)
    assert.is_false(block, "the latch went with the focus")
    assert.are.equal("bar1", press(machine, TWO).bar, "SHIFT is no longer held")
  end)

  it("cycles the active set on CTRL+Up and CTRL+Down, exactly, and claims neither edge", function()
    local machine = world()
    press(machine, LCTRL)
    local intent, block = press(machine, UP)
    assert.are.same({ cycle = 1 }, intent)
    assert.is_false(block, "a chord cannot be kept from the game, so the down is not claimed")
    assert.is_nil((press(machine, UP)), "its auto-repeat does not cycle again")
    intent, block = release(machine, UP)
    assert.is_nil(intent)
    assert.is_false(block, "nor the up: the game saw the down, and CTRL may have lifted first")
    assert.are.same({ cycle = -1 }, (press(machine, DOWN)))
    release(machine, DOWN)
    press(machine, LSHIFT)
    intent, block = press(machine, UP)
    assert.is_nil(intent, "CTRL+SHIFT+Up is nobody's")
    assert.is_false(block)
    release(machine, UP)
    release(machine, LSHIFT)
    release(machine, LCTRL)
    intent, block = press(machine, UP)
    assert.is_nil(intent, "a bare arrow is the game's camera")
    assert.is_false(block)
  end)

  it("leaves the cycle keys alone under a guard", function()
    local machine, env = world()
    env.chat_open = true
    press(machine, LCTRL)
    local intent, block = press(machine, UP)
    assert.is_nil(intent)
    assert.is_false(block)
  end)

  it("leaves an arrow that went down as the game's to the game when CTRL arrives under it", function()
    local machine = world()
    assert.are.same({ nil, false }, { machine.on_key(UP, true, nil, false) }, "bare Up: the camera's")
    machine.on_key(LCTRL, true, nil, false)
    assert.are.same({ nil, false }, { machine.on_key(UP, true, nil, false) }, "its auto-repeat stays the game's")
    assert.are.same({ nil, false }, { machine.on_key(UP, false, nil, false) }, "and so does its release")
    local intent, block = machine.on_key(UP, true, nil, false)
    assert.are.same({ cycle = 1 }, intent, "a fresh press under CTRL is ours")
    assert.is_false(block)
  end)

  it("leaves a number that went down under a guard to the game when the guard lifts", function()
    local machine, env = world({ chat_open = true })
    assert.are.same({ nil, false }, { machine.on_key(ONE, true, nil, false) })
    env.chat_open = false
    assert.are.same({ nil, false }, { machine.on_key(ONE, true, nil, false) }, "its auto-repeat stays the game's")
    assert.are.same({ nil, false }, { machine.on_key(ONE, false, nil, false) })
    assert.is_not_nil(press(machine, ONE), "a fresh press is ours")
  end)

  it("does not fire on auto-repeat of a key already down", function()
    local machine = world()
    assert.is_not_nil(press(machine, ONE))
    local intent, block = press(machine, ONE)
    assert.is_nil(intent)
    assert.is_true(block, "still ours while it is down")
  end)
end)
