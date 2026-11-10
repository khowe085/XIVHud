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

--[[ `//hud gamepad`: the bridge's state and its switch, and its map changed
     without a hand edit (Kevin, 2026-11-06) - a slot's `bind` with a gesture
     where the address goes, `unbind` and `list`.

     Every verb re-reads data/gamepad.lua first, and one that writes refuses a
     file that could not be read rather than write the defaults over it.

     Pure: the bridge, the behaviours, bind's action parser and labeller, the
     file's reload and save and the focus arrive as deps. ]]

local READ_FAILED = "gamepad: data/gamepad.lua could not be read - fix it first"
local SPACED = "gamepad: a gesture is one word with no spaces, like lt+y"
local BIND_FORM = "gamepad bind <gesture> <type> [<action>] [<target>] - or a behavior, or key <key name>;"
  .. " a gesture is buttons joined by +, the trigger last, like lt+y"
local UNBIND_FORM = "gamepad unbind <gesture>"
-- Asked every frame the bridge is on, so nothing is built to say nothing.
local NO_LINES = {}
local FORM = {
  "gamepad [on|off] - the bridge's state, or switch it",
  "gamepad list - every gesture and what it does",
  BIND_FORM,
  UNBIND_FORM,
}

-- A gesture typed with spaces in it arrives as several words, one of them
-- ending or beginning in `+`.
local function spaced(words)
  local gesture, after = words[2], words[3]
  return (gesture ~= nil and gesture:sub(-1) == "+") or (after ~= nil and after:sub(1, 1) == "+")
end

local function new(deps)
  local self = {}
  local pad = deps.gamepad
  local parse_action = type(deps.parse_action) == "function" and deps.parse_action or nil
  local is_action_type = type(deps.is_action_type) == "function" and deps.is_action_type or nil
  local describe_action = type(deps.describe_action) == "function" and deps.describe_action or nil
  local problems_said = false

  local function problems()
    problems_said = true
    return pad.problems()
  end

  local function status()
    local line = pad.status()
    if pad.enabled() and not deps.focused() then
      line = line .. " - paused - the game is not in focus"
    end
    local lines = { line }
    for _, problem in ipairs(problems()) do
      lines[#lines + 1] = problem
    end
    return lines
  end

  local function switch(on)
    if not deps.reload() then
      return { READ_FAILED }
    end
    pad.set_enabled(on)
    deps.save()
    return status()
  end

  local function refusal(gesture, why, missing)
    local line = "gamepad: " .. gesture .. " - " .. why
    if missing ~= nil then
      line = line .. "; buttons are " .. table.concat(pad.buttons(), " ")
    end
    return { line }
  end

  -- What a gesture does, in the words `bind` takes after the gesture.
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

  -- The behaviour a bind's words name after the gesture, or nil and why.
  local function behavior_of(words)
    local kind = words[3]:lower()
    if deps.behaviors.known(kind) then
      if #words > 3 then
        return nil, kind .. " takes nothing after it - drop " .. table.concat(words, " ", 4)
      end
      return kind
    end
    if kind == "key" then
      if #words ~= 4 then
        return nil, "key takes one key name, like numpad*"
      end
      local entry = { key = words[4]:lower() }
      local ok, why = deps.behaviors.check(entry)
      if not ok then
        return nil, why
      end
      return entry
    end
    if parse_action == nil or is_action_type == nil then
      return nil, "actions need the action service, which did not load"
    end
    if not is_action_type(kind) then
      return nil,
        kind .. " is neither a bind type nor a behavior - behaviors are " .. table.concat(deps.behaviors.names(), ", ")
    end
    return parse_action({ unpack(words, 3) })
  end

  local function bind(words)
    if #words < 3 then
      return { BIND_FORM }
    end
    if spaced(words) then
      return { SPACED }
    end
    if not deps.reload() then
      return { READ_FAILED }
    end
    local behavior, why = behavior_of(words)
    if behavior == nil then
      return { "gamepad: " .. why }
    end
    local spelling, refused, missing = pad.bind(words[2], behavior)
    if spelling == nil then
      return refusal(words[2], refused, missing)
    end
    deps.save()
    return { "gamepad: bound " .. spelling .. " to " .. describe(behavior) }
  end

  local function unbind(words)
    if #words > 2 and spaced(words) then
      return { SPACED }
    end
    if #words ~= 2 then
      return { UNBIND_FORM }
    end
    if not deps.reload() then
      return { READ_FAILED }
    end
    local spelling, why, missing = pad.unbind(words[2])
    if spelling == nil then
      return refusal(words[2], why, missing)
    end
    deps.save()
    return { "gamepad: unbound " .. spelling }
  end

  local function list()
    deps.reload()
    local bindings = pad.bindings()
    local lines = { "gamepad: no gestures" }
    if #bindings > 0 then
      lines[1] = "gamepad: " .. #bindings .. (#bindings == 1 and " gesture" or " gestures")
    end
    for _, binding in ipairs(bindings) do
      lines[#lines + 1] = "  " .. binding.gesture .. " " .. describe(binding.behavior)
    end
    return lines
  end

  --- A `//hud gamepad` line's words after the verb: the lines to say.
  function self.handle(words)
    local verb = words[1] ~= nil and words[1]:lower() or nil
    if verb == nil then
      deps.reload()
      return status()
    elseif verb == "on" or verb == "off" then
      return #words == 1 and switch(verb == "on") or FORM
    elseif verb == "bind" then
      return bind(words)
    elseif verb == "unbind" then
      return unbind(words)
    elseif verb == "list" then
      return #words == 1 and list() or FORM
    end
    return FORM
  end

  --- What is wrong with the map, the first time it is asked and not since
  --- the bare verb said it.
  function self.unsaid_problems()
    if problems_said then
      return NO_LINES
    end
    return problems()
  end

  return self
end

return new
