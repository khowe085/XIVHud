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

--[[ Named behaviours: what a gesture does, in game or on a bar, with nothing
     of what made it. Three kinds:

       { key = "<setkey name>" }  a key sent to the game, down while held and
                                  up when let go
       { action = "<words>" }     an action, written as `bind` takes it after
                                  the address, run on the press as a slot
                                  holding it would run it
       <component>.<name>         one a component declares, handed both edges

     The first two are the file's (data/behaviors.lua), over the shipped ones:
     a name the file leaves out is the shipped behaviour, and one it names is
     its own entry, WHOLE - never merged field by field, which would carry a
     shipped key into an entry the file makes an action. A component's
     carries a dot, which no name in the file may, so the file cannot shadow
     one.

     Holders are counted: a behaviour two gestures hold is let go when the
     last of them lets go, and as it went down - the key it pressed, whatever
     the file says by then. A let-go is `cancelled` when it ends a hold
     without being a release (focus lost, the pad gone), which a component is
     told so it can undo the hold without acting on it.

     Pure: the file, the key sender, the action parser and runner, the
     components' behaviours and their delivery arrive as deps. ]]

local NAME = "^[%l%d_]+$"
-- A word `setkey` could take and nothing more: the name is spliced into a
-- console command, where a `;` would start another.
local KEY = "^[%w%+%-%*/%.]+$"

local function defaults()
  return {
    accept = { key = "enter" },
    cancel = { key = "escape" },
    cycle_window = { key = "numpad+" },
    main_menu = { key = "numpad-" },
    lockon = { key = "numpad*" },
    autorun = { key = "r" },
    open_map = { action = "open map" },
  }
end
local SHIPPED = defaults()

local function new(deps)
  local self = {}
  local parse_action = type(deps.parse_action) == "function" and deps.parse_action or nil
  -- Name -> `{ count = , effect = }`: how many hold it and what it went down
  -- as. A behaviour is in here exactly while something holds it.
  local held = {}
  -- Action words -> `{ record = }` or `{ why = }`: each is read once.
  local actions = {}
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

  local function file()
    local value = deps.config and deps.config() or nil
    return type(value) == "table" and value or {}
  end

  -- The file's entry for a name, or the shipped one where it has none.
  local function entry_of(entries, name)
    local entry = entries[name]
    if entry == nil then
      return SHIPPED[name]
    end
    return entry
  end

  local function declared(name)
    for _, entry in ipairs(deps.components and deps.components() or {}) do
      if entry == name then
        return true
      end
    end
    return false
  end

  local function read_action(words)
    local known = actions[words]
    if known == nil then
      local record, why = parse_action(words)
      known = record ~= nil and { record = record } or { why = why }
      actions[words] = known
    end
    return known
  end

  -- What a file entry does, or nil and why it does nothing.
  local function definition(name, entry)
    if type(name) ~= "string" or not name:match(NAME) then
      return nil, "a name is a plain lowercase word"
    end
    if type(entry) ~= "table" then
      return nil, "neither a key nor an action"
    end
    local key = type(entry.key) == "string" and entry.key or nil
    local action = type(entry.action) == "string" and entry.action or nil
    if key ~= nil and action ~= nil then
      return nil, "a key or an action, not both"
    end
    if key ~= nil then
      if not key:match(KEY) then
        return nil, key .. " is not a key name"
      end
      return { kind = "key", key = key }
    end
    if action == nil then
      return nil, "neither a key nor an action"
    end
    if parse_action == nil then
      return nil, "actions need the action service, which did not load"
    end
    local known = read_action(action)
    if known.record == nil then
      return nil, known.why
    end
    return { kind = "action", record = known.record }
  end

  local function resolve(name)
    if type(name) ~= "string" then
      return nil
    end
    if name:find(".", 1, true) then
      return declared(name) and { kind = "component" } or nil
    end
    local entry = entry_of(file(), name)
    if entry == nil or entry == false then
      return nil
    end
    return (definition(name, entry))
  end

  --- One edge of a behaviour, from whatever holds it. Unknown and broken
  --- behaviours do nothing; `problems` says why.
  function self.edge(name, down, cancelled)
    local holding = held[name]
    if down then
      if holding ~= nil then
        holding.count = holding.count + 1
        return
      end
      local effect = resolve(name)
      if effect == nil then
        return
      end
      -- Counted before it goes out, so a throw downstream leaves the hold
      -- standing for its let-go to end.
      held[name] = { count = 1, effect = effect }
      if effect.kind == "key" then
        press_key(effect.key)
      elseif effect.kind == "action" then
        deps.fire_action(effect.record)
      else
        deps.deliver(name, true, false)
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
    held[name] = nil
    if holding.effect.kind == "key" then
      lift_key(holding.effect.key)
    elseif holding.effect.kind == "component" then
      deps.deliver(name, false, cancelled == true)
    end
  end

  --- Whether a behaviour of that name exists, sound or not.
  function self.known(name)
    if type(name) ~= "string" then
      return false
    end
    if name:find(".", 1, true) then
      return declared(name)
    end
    local entry = entry_of(file(), name)
    return entry ~= nil and entry ~= false
  end

  --- Why each broken behaviour does nothing, the file's and the shipped ones
  --- it leaves standing alike, in name order.
  function self.problems()
    local entries = file()
    local names, seen = {}, {}
    for _, source in ipairs({ entries, SHIPPED }) do
      for name in pairs(source) do
        if not seen[name] then
          seen[name] = true
          names[#names + 1] = name
        end
      end
    end
    table.sort(names, function(a, b)
      return tostring(a) < tostring(b)
    end)
    local out = {}
    for _, name in ipairs(names) do
      local entry = entry_of(entries, name)
      if entry ~= false then
        local effect, why = definition(name, entry)
        if effect == nil then
          out[#out + 1] = "behaviors: " .. tostring(name) .. " - " .. why
        end
      end
    end
    return out
  end

  return self
end

return new
