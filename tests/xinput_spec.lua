local new_xinput = require("lib/xinput")

describe("xinput", function()
  local ffi, loaded, calls, answer

  -- A stand-in for LuaJIT's ffi: `libraries` names the DLLs that load, and
  -- XInputGetState fills the state the way the real one does.
  local function fake_ffi(libraries)
    return {
      cdef = function(source)
        ffi.declared = source
      end,
      load = function(name)
        loaded[#loaded + 1] = name
        if not libraries[name] then
          error("cannot load module '" .. name .. "'")
        end
        return {
          XInputGetState = function(index, state)
            calls[#calls + 1] = { library = name, index = index, state = state }
            if type(answer) == "function" then
              return answer(index, state)
            end
            return answer
          end,
        }
      end,
      new = function(ctype)
        ffi.allocated = ctype
        return { Gamepad = {} }
      end,
    }
  end

  before_each(function()
    loaded, calls, answer = {}, {}, 0
    ffi = fake_ffi({ xinput1_4 = true })
  end)

  describe("loading", function()
    it("needs ffi", function()
      local reader, reason = new_xinput(nil)
      assert.is_nil(reader)
      assert.are.equal("ffi not available", reason)
    end)

    it("declares XInputGetState as __stdcall over XINPUT_STATE", function()
      assert.is_not_nil(new_xinput(ffi))
      assert.is_not_nil(ffi.declared:find("__stdcall XInputGetState", 1, true))
      assert.is_not_nil(ffi.declared:find("XINPUT_STATE", 1, true))
      assert.are.equal("XINPUT_STATE", ffi.allocated)
    end)

    it("says why when the declaration is refused", function()
      ffi.cdef = function()
        error("bad declaration")
      end
      local reader, reason = new_xinput(ffi)
      assert.is_nil(reader)
      assert.is_not_nil(reason:find("bad declaration", 1, true))
    end)

    it("takes the first library that loads, newest first", function()
      ffi = fake_ffi({ xinput1_3 = true, xinput9_1_0 = true })
      local reader = new_xinput(ffi)
      assert.are.same({ "xinput1_4", "xinput1_3" }, loaded)
      assert.are.equal("xinput1_3", reader.library)
    end)

    it("passes over a library without XInputGetState, resolving the call once, at load", function()
      ffi = fake_ffi({ xinput1_4 = true, xinput1_3 = true })
      local load = ffi.load
      ffi.load = function(name)
        local library = load(name)
        if name == "xinput1_4" then
          return setmetatable({}, {
            __index = function(_, key)
              error("missing symbol " .. key)
            end,
          })
        end
        return library
      end
      local reader = new_xinput(ffi)
      assert.are.equal("xinput1_3", reader.library)
    end)

    it("keeps the library loaded for as long as the reader lives", function()
      local alive = setmetatable({}, { __mode = "v" })
      local load = ffi.load
      ffi.load = function(name)
        local library = load(name)
        alive[1] = library
        return library
      end
      local reader = new_xinput(ffi)
      collectgarbage("collect")
      assert.is_not_nil(alive[1], "a collected namespace unloads its DLL from under the reader")
      assert.is_not_nil(reader.read)
    end)

    it("says why when no library has XInputGetState", function()
      ffi.load = function()
        return {}
      end
      local reader, reason = new_xinput(ffi)
      assert.is_nil(reader)
      assert.is_not_nil(reason:find("XInputGetState", 1, true))
    end)

    it("says which libraries it tried when none loads", function()
      ffi = fake_ffi({})
      local reader, reason = new_xinput(ffi)
      assert.is_nil(reader)
      assert.are.same({ "xinput1_4", "xinput1_3", "xinput9_1_0" }, loaded)
      assert.is_not_nil(reason:find("xinput1_4, xinput1_3, xinput9_1_0", 1, true))
    end)
  end)

  describe("reading", function()
    local reader

    before_each(function()
      reader = new_xinput(ffi)
      answer = function(_, state)
        state.Gamepad.wButtons = 0x1000
        state.Gamepad.bLeftTrigger = 12
        state.Gamepad.bRightTrigger = 255
        return 0
      end
    end)

    it("answers the buttons and both triggers of a connected pad", function()
      assert.are.same({ buttons = 0x1000, left_trigger = 12, right_trigger = 255 }, reader.read(2))
      assert.are.equal(2, calls[1].index)
    end)

    it("answers nil for a slot with nothing in it", function()
      answer = 1167 -- ERROR_DEVICE_NOT_CONNECTED
      assert.is_nil(reader.read(0))
    end)

    it("answers nil when the call itself fails", function()
      answer = function()
        error("access violation")
      end
      assert.is_nil(reader.read(0))
    end)
  end)
end)
