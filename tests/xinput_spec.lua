local new_xinput = require("lib/xinput")

--[[ The bridge's reader over _LuaXInput (native/xinput), which the entry
     point loads; the module itself is native/xinput's own spec's. ]]
describe("xinput", function()
  local calls, answer, library

  -- A stand-in for _LuaXInput: `answer(index, out)` is what get_state says.
  local function fake_module()
    return {
      library = function()
        return library
      end,
      get_state = function(index, out)
        calls[#calls + 1] = { index = index, out = out }
        return answer(index, out)
      end,
    }
  end

  before_each(function()
    calls, library = {}, "xinput1_4.dll"
    answer = function(_, out)
      out.buttons, out.left_trigger, out.right_trigger = 0x1000, 12, 255
      return out
    end
  end)

  describe("loading", function()
    it("needs the module", function()
      local reader, reason = new_xinput(nil)
      assert.is_nil(reader)
      assert.are.equal("_LuaXInput not loaded", reason)
    end)

    it("needs an XInput library behind it", function()
      library = nil
      local reader, reason = new_xinput(fake_module())
      assert.is_nil(reader)
      assert.are.equal("no XInput library found", reason)
    end)

    it("names the XInput library the module found", function()
      assert.are.equal("xinput1_4.dll", new_xinput(fake_module()).library)
    end)
  end)

  describe("reading", function()
    local reader

    before_each(function()
      reader = new_xinput(fake_module())
    end)

    it("answers the buttons and both triggers of a connected pad", function()
      local state = reader.read(2)
      assert.are.equal(0x1000, state.buttons)
      assert.are.equal(12, state.left_trigger)
      assert.are.equal(255, state.right_trigger)
      assert.are.equal(2, calls[1].index)
    end)

    it("reads into one table, so a frame's read allocates nothing", function()
      local first = reader.read(0)
      assert.are.equal(first, reader.read(0))
      assert.are.equal(first, calls[1].out)
    end)

    it("answers nil for a slot with nothing in it", function()
      answer = function()
        return nil, "not_connected", 1167
      end
      assert.is_nil(reader.read(0))
    end)

    it("answers nil when the module raises", function()
      answer = function()
        error("bad argument")
      end
      assert.is_nil(reader.read(0))
    end)
  end)
end)
