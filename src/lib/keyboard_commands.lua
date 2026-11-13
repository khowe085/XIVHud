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

--[[ `//hud keyboard`: the keyboard map's state and its switch, and the map.

     Every verb re-reads data/keyboard.lua first, and the switch refuses a
     file that could not be read rather than write the defaults over it.
     Switching off lets go of every key the map holds.

     Pure: the map, the file's reload and save, the release and bind's
     labeller arrive as deps. ]]

local READ_FAILED = "keyboard: data/keyboard.lua could not be read - fix it first"
local FORM = {
  "keyboard [on|off] - the keyboard map's state, or switch it",
  "keyboard list - every key and what it does",
}

local function new(deps)
  local self = {}
  local keyboard = deps.keyboard
  local describe_action = type(deps.describe_action) == "function" and deps.describe_action or nil

  local function status()
    local lines = { "keyboard: " .. (keyboard.enabled() and "on" or "off") }
    for _, problem in ipairs(keyboard.problems()) do
      lines[#lines + 1] = problem
    end
    return lines
  end

  local function switch(on)
    if not deps.reload() then
      return { READ_FAILED }
    end
    keyboard.set_enabled(on)
    deps.save()
    if not on then
      deps.release()
    end
    return status()
  end

  -- What a key does, in the words the map holds.
  local function describe(behavior)
    if type(behavior) ~= "table" then
      return tostring(behavior)
    end
    if behavior.key ~= nil then
      return "key " .. tostring(behavior.key)
    end
    if describe_action == nil then
      return tostring(behavior.type)
    end
    return describe_action(behavior)
  end

  local function list()
    deps.reload()
    local bindings = keyboard.bindings()
    local lines = { "keyboard: no keys" }
    if #bindings > 0 then
      lines[1] = "keyboard: " .. #bindings .. (#bindings == 1 and " key" or " keys")
    end
    for _, binding in ipairs(bindings) do
      lines[#lines + 1] = "  " .. binding.key .. " " .. describe(binding.behavior)
    end
    return lines
  end

  --- A `//hud keyboard` line's words after the verb: the lines to say.
  function self.handle(words)
    local verb = words[1] ~= nil and words[1]:lower() or nil
    if verb == nil then
      deps.reload()
      return status()
    elseif verb == "on" or verb == "off" then
      return #words == 1 and switch(verb == "on") or FORM
    elseif verb == "list" then
      return #words == 1 and list() or FORM
    end
    return FORM
  end

  return self
end

return new
