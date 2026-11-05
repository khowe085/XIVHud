--[[ The binding, over the scripted XInput in fake_loader.c. Run by
     `make -C native/xinput test`, which builds both into one test library
     first; the real DLL's loader is covered by smoke.lua on Windows. ]]

local BUILD = "build/test/_LuaXInput.so"

package.cpath = "build/test/?.so;" .. package.cpath
local fake = assert(package.loadlib(BUILD, "luaopen__LuaXInputFake"))()

local NOT_CONNECTED, EMPTY = 1167, 4306

-- The module as the fake now stands: lx_load runs at every open.
local function open()
  package.loaded._LuaXInput = nil
  return require("_LuaXInput")
end

describe("_LuaXInput", function()
  local xinput

  before_each(function()
    fake.reset()
    xinput = open()
  end)

  describe("the module", function()
    it("is a table, and sets no global", function()
      assert.are.equal("table", type(xinput))
      assert.is_nil(rawget(_G, "_LuaXInput"))
    end)

    it("carries its version and XInput's constants", function()
      assert.is_truthy(xinput.VERSION:match("^%d+%.%d+%.%d+$"))
      assert.are.equal(4, xinput.MAX_PADS)
      assert.are.equal(255, xinput.ANY)
      assert.are.equal(30, xinput.TRIGGER_THRESHOLD)
      assert.are.equal(7849, xinput.LEFT_THUMB_DEADZONE)
      assert.are.equal(8689, xinput.RIGHT_THUMB_DEADZONE)
      assert.are.same({
        dpad_up = 0x0001,
        dpad_down = 0x0002,
        dpad_left = 0x0004,
        dpad_right = 0x0008,
        start = 0x0010,
        back = 0x0020,
        left_thumb = 0x0040,
        right_thumb = 0x0080,
        left_shoulder = 0x0100,
        right_shoulder = 0x0200,
        a = 0x1000,
        b = 0x2000,
        x = 0x4000,
        y = 0x8000,
      }, xinput.buttons)
    end)

    it("names the XInput library it found, or nil for none", function()
      assert.are.equal("fake_xinput.dll", xinput.library())
      fake.unload()
      assert.is_nil(open().library())
    end)
  end)

  describe("get_state", function()
    local pad = {
      packet = 77,
      buttons = 0x1001,
      left_trigger = 12,
      right_trigger = 255,
      thumb_lx = -32768,
      thumb_ly = 32767,
      thumb_rx = -1,
      thumb_ry = 0,
    }

    it("answers a connected pad's state, sticks signed", function()
      fake.connect(2, pad)
      assert.are.same(pad, xinput.get_state(2))
    end)

    it("fills and hands back the table it is given", function()
      fake.connect(0, pad)
      local out = { mine = true }
      assert.are.equal(out, xinput.get_state(0, out))
      assert.are.equal(77, out.packet)
      assert.are.equal(-32768, out.thumb_lx)
      assert.is_true(out.mine)
    end)

    it("answers nil, not_connected and the code for an empty slot", function()
      local state, reason, code = xinput.get_state(1)
      assert.is_nil(state)
      assert.are.equal("not_connected", reason)
      assert.are.equal(NOT_CONNECTED, code)
    end)

    it("answers nil, error and the code for any other failure", function()
      fake.force("get_state", 5)
      assert.are.same({ nil, "error", 5 }, { xinput.get_state(0) })
    end)

    it("answers nil and no_xinput without an XInput library", function()
      fake.unload()
      assert.are.same({ nil, "no_xinput" }, { open().get_state(0) })
    end)

    it("raises on an index outside 0 to 3", function()
      assert.has_error(function()
        xinput.get_state(-1)
      end)
      assert.has_error(function()
        xinput.get_state(4)
      end)
      assert.has_error(function()
        xinput.get_state("first")
      end)
    end)

    it("raises on an out that is not a table, pad or no pad", function()
      assert.has_error(function()
        xinput.get_state(0, 5)
      end)
    end)
  end)

  describe("set_vibration", function()
    it("sets both motors of a connected pad", function()
      fake.connect(1)
      assert.is_true(xinput.set_vibration(1, 100, 65535))
      assert.are.same({ 100, 65535, 1 }, { fake.vibration(1) })
    end)

    it("raises on a speed outside 0 to 65535", function()
      fake.connect(0)
      assert.has_error(function()
        xinput.set_vibration(0, -1, 0)
      end)
      assert.has_error(function()
        xinput.set_vibration(0, 0, 65536)
      end)
      assert.are.same({ 0, 0, 0 }, { fake.vibration(0) })
    end)

    it("answers not_connected for an empty slot", function()
      assert.are.same({ nil, "not_connected", NOT_CONNECTED }, { xinput.set_vibration(3, 1, 1) })
    end)

    it("answers not_supported where the library lacks the call", function()
      fake.drop("set_state")
      fake.connect(0)
      assert.are.same({ nil, "not_supported" }, { open().set_vibration(0, 1, 1) })
    end)
  end)

  describe("get_capabilities", function()
    local caps = {
      type = 1,
      subtype = 1,
      flags = 0x0004,
      buttons = 0xF3FF,
      left_trigger = 255,
      right_trigger = 255,
      thumb_lx = -64,
      thumb_ly = -64,
      thumb_rx = -64,
      thumb_ry = -64,
      left_motor = 255,
      right_motor = 255,
    }

    it("answers the pad's type, subtype, flags, reach and motors, for any device type", function()
      fake.connect(0)
      fake.capabilities(0, caps)
      assert.are.same(caps, xinput.get_capabilities(0))
      assert.are.equal(0, fake.last_flags())
    end)

    it("fills and hands back the table it is given", function()
      fake.connect(0)
      fake.capabilities(0, caps)
      local out = {}
      assert.are.equal(out, xinput.get_capabilities(0, out))
      assert.are.equal(0x0004, out.flags)
    end)

    it("answers not_connected for an empty slot", function()
      assert.are.same({ nil, "not_connected", NOT_CONNECTED }, { xinput.get_capabilities(0) })
    end)
  end)

  describe("get_battery", function()
    before_each(function()
      fake.connect(0)
    end)

    it("answers the gamepad's battery by name", function()
      fake.battery(0, 0, 2, 3)
      assert.are.same({ type = "alkaline", level = "full" }, xinput.get_battery(0))
      assert.are.equal(0, fake.last_device())
    end)

    it("asks for the headset's when told", function()
      fake.battery(0, 1, 1, 1)
      assert.are.same({ type = "wired", level = "low" }, xinput.get_battery(0, "headset"))
      assert.are.equal(1, fake.last_device())
    end)

    it("names every type and level XInput defines", function()
      local types = { [0] = "disconnected", "wired", "alkaline", "nimh", [255] = "unknown" }
      for value, name in pairs(types) do
        fake.battery(0, 0, value, 2)
        assert.are.equal(name, xinput.get_battery(0).type)
      end
      local levels = { [0] = "empty", "low", "medium", "full" }
      for value, name in pairs(levels) do
        fake.battery(0, 0, 1, value)
        assert.are.equal(name, xinput.get_battery(0).level)
      end
    end)

    it("names a type or level it does not know unknown", function()
      fake.battery(0, 0, 0x80, 9)
      assert.are.same({ type = "unknown", level = "unknown" }, xinput.get_battery(0))
    end)

    it("raises on a device it does not know", function()
      assert.has_error(function()
        xinput.get_battery(0, "keyboard")
      end)
    end)

    it("answers not_supported where the library lacks the call", function()
      fake.drop("get_battery")
      assert.are.same({ nil, "not_supported" }, { open().get_battery(0) })
    end)
  end)

  describe("get_keystroke", function()
    it("answers a waiting keystroke, once", function()
      fake.connect(0)
      fake.keystroke({ key = 0x5800, unicode = 0, flags = 0x0001, user_index = 0, hid_code = 0 })
      assert.are.same({
        key = 0x5800,
        unicode = 0,
        user_index = 0,
        hid_code = 0,
        down = true,
        up = false,
        repeating = false,
      }, xinput.get_keystroke(0))
      assert.are.same({ nil, "empty", EMPTY }, { xinput.get_keystroke(0) })
    end)

    it("reads a release and a repeat off the flags", function()
      fake.connect(0)
      fake.keystroke({ key = 0x5801, flags = 0x0006, user_index = 0 })
      local keystroke = xinput.get_keystroke(0)
      assert.is_false(keystroke.down)
      assert.is_true(keystroke.up)
      assert.is_true(keystroke.repeating)
    end)

    it("takes ANY for the pad, and says which pad the keystroke came from", function()
      fake.keystroke({ key = 0x5802, flags = 0x0001, user_index = 3 })
      assert.are.equal(3, xinput.get_keystroke(xinput.ANY).user_index)
      assert.are.equal(255, fake.last_index("get_keystroke"))
    end)

    it("raises on any other index", function()
      for _, index in ipairs({ -1, 4, 254 }) do
        assert.has_error(function()
          xinput.get_keystroke(index)
        end)
      end
    end)

    it("answers not_connected for an empty slot", function()
      assert.are.same({ nil, "not_connected", NOT_CONNECTED }, { xinput.get_keystroke(2) })
    end)

    it("answers not_supported where the library lacks the call", function()
      fake.drop("get_keystroke")
      assert.are.same({ nil, "not_supported" }, { open().get_keystroke(0) })
    end)
  end)
end)
