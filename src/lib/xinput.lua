--[[
Copyright © 2026, Azureblood2
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of XIVHud nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Azureblood2 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ XInputGetState through LuaJIT's ffi: the one call the gamepad bridge
     makes into Windows. `ffi` is injected, so a spec can stand in for it.

     __stdcall matters: FFXI is a 32-bit process, where XInput's functions
     are WINAPI and a cdecl call would leave the stack unbalanced. ]]

local DECLARATIONS = [[
typedef struct {
  uint16_t wButtons;
  uint8_t bLeftTrigger;
  uint8_t bRightTrigger;
  int16_t sThumbLX;
  int16_t sThumbLY;
  int16_t sThumbRX;
  int16_t sThumbRY;
} XINPUT_GAMEPAD;
typedef struct {
  uint32_t dwPacketNumber;
  XINPUT_GAMEPAD Gamepad;
} XINPUT_STATE;
uint32_t __stdcall XInputGetState(uint32_t dwUserIndex, XINPUT_STATE *pState);
]]

-- Newest first: 1_4 ships with Windows 8 and later, 1_3 with the DirectX
-- runtime, and 9_1_0 with every Windows since Vista.
local LIBRARIES = { "xinput1_4", "xinput1_3", "xinput9_1_0" }
local ERROR_SUCCESS = 0

--- A reader, `{ library, read(index) }`, or nil and why there is none.
local function new(ffi)
  if type(ffi) ~= "table" then
    return nil, "ffi not available"
  end
  local declared, failure = pcall(ffi.cdef, DECLARATIONS)
  if not declared then
    return nil, "could not declare XInputGetState: " .. tostring(failure)
  end
  -- The call is looked up here first: a symbol a library lacks raises on
  -- lookup, which belongs at load rather than in every frame's read.
  local library, name
  for _, candidate in ipairs(LIBRARIES) do
    local loaded, namespace = pcall(ffi.load, candidate)
    if loaded then
      local found, call = pcall(function()
        return namespace.XInputGetState
      end)
      if found and call ~= nil then
        library, name = namespace, candidate
        break
      end
    end
  end
  if library == nil then
    return nil, "no XInput library with XInputGetState loaded (tried " .. table.concat(LIBRARIES, ", ") .. ")"
  end

  local state = ffi.new("XINPUT_STATE")
  -- Handed out every frame and read before the next, so one table serves.
  local answer = {}
  local reader = { library = name }

  --- The pad in slot `index` (0-3), or nil when nothing answers there.
  function reader.read(index)
    -- Through the namespace on every call, LuaJIT's own idiom, and what keeps
    -- it referenced: a namespace that is collected unloads its DLL, and a
    -- function taken from it would then jump into freed memory.
    local called, code = pcall(library.XInputGetState, index, state)
    if not called or code ~= ERROR_SUCCESS then
      return nil
    end
    local pad = state.Gamepad
    answer.buttons = tonumber(pad.wButtons)
    answer.left_trigger = tonumber(pad.bLeftTrigger)
    answer.right_trigger = tonumber(pad.bRightTrigger)
    return answer
  end

  return reader
end

return new
