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

--[[ Behaviours: what a gesture does, in game or on a bar, with nothing of
     what made it. A gesture names one of three:

       <name>                      one of the shipped behaviours below
       <component>.<name>          one a component declares, handed both edges
       an entry of its own:
         { key = "<setkey name>" } a key sent to the game, down while held
                                   and up when let go
         { type = , action = ... } an action, the record a slot would hold,
                                   run on the press as that slot would run it

     Holders are counted: a behaviour two gestures hold is let go when the
     last of them lets go, and as it went down - the key it pressed, whatever
     the entry says by then. A gesture's own entry is held by itself alone.
     A let-go is `cancelled` when it ends a hold without being a release
     (focus lost, the pad gone), which a component is told so it can undo
     the hold without acting on it.

     Pure: the key sender, the action service's validate and runner, the
     components' behaviours and their delivery arrive as deps. ]]

-- A word `setkey` could take and nothing more: the name is spliced into a
-- console command, where a `;` would start another.
local KEY = "^[%w%+%-%*/%.]+$"

local SHIPPED = {
  accept = { key = "enter" },
  cancel = { key = "escape" },
  cycle_window = { key = "numpad+" },
  main_menu = { key = "numpad-" },
  lockon = { key = "numpad*" },
  autorun = { key = "r" },
  open_map = { type = "open", action = "map" },
}

local SHIPPED_NAMES = {}
for name in pairs(SHIPPED) do
  SHIPPED_NAMES[#SHIPPED_NAMES + 1] = name
end
table.sort(SHIPPED_NAMES)

local function new(deps)
  local self = {}
  local validate = type(deps.validate) == "function" and deps.validate or nil
  -- Behaviour -> `{ count = , effect = }`: how many hold it and what it went
  -- down as. A behaviour is in here exactly while something holds it.
  local held = {}
  -- Key name -> how many held behaviours have it down, so two that share one
  -- let it up only when both have.
  local keys_down = {}

  local function press_key(key)
    keys_down[key] = (keys_down[key] or 0) + 1
    if keys_down[key] == 1 then
      deps.send_key(key, true)
    end
  end

  local function lift_key(key)
    local count = (keys_down[key] or 0) - 1
    keys_down[key] = count > 0 and count or nil
    if count == 0 then
      deps.send_key(key, false)
    end
  end

  local function declared(name)
    for _, entry in ipairs(deps.components and deps.components() or {}) do
      if entry == name then
        return true
      end
    end
    return false
  end

  -- What an entry does, or nil and why it does nothing.
  local function definition(entry)
    if type(entry) ~= "table" then
      return nil, "neither a key nor an action"
    end
    local key = type(entry.key) == "string" and entry.key or nil
    if key ~= nil and entry.type ~= nil then
      return nil, "a key or an action, not both"
    end
    if key ~= nil then
      if not key:match(KEY) then
        return nil, key .. " is not a key name"
      end
      return { kind = "key", key = key }
    end
    if entry.type == nil then
      return nil, "neither a key nor an action"
    end
    if validate == nil then
      return nil, "actions need the action service, which did not load"
    end
    local ok, why = validate(entry)
    if not ok then
      return nil, why
    end
    return { kind = "action", record = entry }
  end

  local function resolve(value)
    if type(value) ~= "string" then
      return definition(value)
    end
    if value:find(".", 1, true) then
      if declared(value) then
        return { kind = "component" }
      end
      return nil, "no behavior " .. value
    end
    if SHIPPED[value] == nil then
      return nil, "no behavior " .. value
    end
    return definition(SHIPPED[value])
  end

  --- One edge of a behaviour - a name, or a gesture's own entry - from
  --- whatever holds it. One that cannot work does nothing; `check` says why.
  function self.edge(value, down, cancelled)
    local holding = held[value]
    if down then
      if holding ~= nil then
        holding.count = holding.count + 1
        return
      end
      local effect = resolve(value)
      if effect == nil then
        return
      end
      -- Counted before it goes out, so a throw downstream leaves the hold
      -- standing for its let-go to end.
      held[value] = { count = 1, effect = effect }
      if effect.kind == "key" then
        press_key(effect.key)
      elseif effect.kind == "action" then
        deps.fire_action(effect.record)
      else
        deps.deliver(value, true, false)
      end
      return
    end
    if holding == nil then
      return
    end
    if holding.count > 1 then
      holding.count = holding.count - 1
      return
    end
    held[value] = nil
    if holding.effect.kind == "key" then
      lift_key(holding.effect.key)
    elseif holding.effect.kind == "component" then
      deps.deliver(value, false, cancelled == true)
    end
  end

  --- Whether a behaviour can work: true, or nil and why not.
  function self.check(value)
    local effect, why = resolve(value)
    if effect == nil then
      return nil, why
    end
    return true
  end

  --- Whether a name is a behaviour's, sound or not.
  function self.known(name)
    if type(name) ~= "string" then
      return false
    end
    if name:find(".", 1, true) then
      return declared(name)
    end
    return SHIPPED[name] ~= nil
  end

  --- Every behaviour's name: the shipped ones, then the components'.
  function self.names()
    local names = {}
    for _, name in ipairs(SHIPPED_NAMES) do
      names[#names + 1] = name
    end
    for _, name in ipairs(deps.components and deps.components() or {}) do
      names[#names + 1] = name
    end
    return names
  end

  return self
end

return new
