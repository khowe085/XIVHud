local new_input = require("components/hotbar/input")

local function world(overrides)
  local env = { chat_open = false, suppressed = false, layout = false, edit = false, disabled = false, hidden = {} }
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
    row_hidden = function(bar)
      return env.hidden[bar] == true
    end,
  })
  return machine, env
end

local function press(machine, name)
  return machine.on_behavior(name, true)
end

--[[ The hotbar's behaviours - a row's slot, and the set cycle - in; one
     intent out, and whether the key behind a press is the hotbar's. Which
     key or chord that was, its repeats and its release are the keyboard
     map's. ]]
describe("the hotbar's behaviours", function()
  it("has no key path: keys reach it as behaviours", function()
    assert.is_nil(world().on_key)
  end)

  it("fires a row's slot and keeps the key behind it, slot 10 being the tenth", function()
    local machine = world()
    local intent, block = press(machine, "bar1_slot1")
    assert.are.same({ bar = "bar1", slot = 1 }, intent)
    assert.is_true(block)
    assert.are.same({ bar = "bar1", slot = 10 }, (press(machine, "bar1_slot10")))
  end)

  it("fires every row, the two no key ships on included", function()
    local machine = world()
    for row = 1, 8 do
      local bar = "bar" .. row
      assert.are.same({ bar = bar, slot = 2 }, (press(machine, bar .. "_slot2")), bar)
    end
  end)

  it("answers a let-go nothing", function()
    local machine = world()
    press(machine, "bar1_slot1")
    local intent, block = machine.on_behavior("bar1_slot1", false)
    assert.is_nil(intent)
    assert.is_false(block)
  end)

  it("ignores a behaviour it does not have", function()
    local machine = world()
    for _, name in ipairs({ "bar9_slot1", "bar1_slot11", "slot1", "nope" }) do
      local intent, block = press(machine, name)
      assert.is_nil(intent, name)
      assert.is_false(block, name)
    end
  end)

  it("fires nothing and keeps nothing under any guard", function()
    for _, guard in ipairs({ "chat_open", "suppressed", "layout", "edit", "disabled" }) do
      local machine, env = world()
      env[guard] = true
      local intent, block = press(machine, "bar1_slot1")
      assert.is_nil(intent, guard)
      assert.is_false(block, guard)
    end
  end)

  it("fires nothing and keeps nothing on a row that is hidden, and fires it again once shown", function()
    local machine, env = world()
    env.hidden.bar2 = true
    local intent, block = press(machine, "bar2_slot1")
    assert.is_nil(intent)
    assert.is_false(block)
    env.hidden.bar2 = nil
    assert.are.equal("bar2", press(machine, "bar2_slot1").bar)
  end)

  it("cycles the active set forward and back, keeping neither edge", function()
    local machine = world()
    local intent, block = press(machine, "cycle")
    assert.are.same({ cycle = 1 }, intent)
    assert.is_false(block, "a chord cannot be kept from the game, so the down is not claimed")
    assert.are.same({ cycle = -1 }, (press(machine, "cycle_back")))
  end)

  it("leaves the cycle alone under a guard", function()
    local machine = world({ chat_open = true })
    local intent, block = press(machine, "cycle")
    assert.is_nil(intent)
    assert.is_false(block)
  end)
end)
