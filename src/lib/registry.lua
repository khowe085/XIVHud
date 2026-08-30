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

--[[ Component registration, enumeration and teardown.

     Components are wired explicitly by the entry point (no directory scanning),
     so registration is the one place that can enforce the shared-key rules: a
     component's name is its code dir, its config namespace and its command
     word, which is why a name that collides with a reserved verb or cannot be
     typed as a single command word is rejected outright. ]]

local NAME_PATTERN = "^[%a][%w_]*$"

-- An alias stands in for the component's name after `//hud`, so it is a word on
-- its own: no underscore, and bounded at both ends - one character is too easy
-- to type by accident, and past four the full name is as quick to type.
local ALIAS_PATTERN = "^[%a][%w]*$"
local ALIAS_MIN, ALIAS_MAX = 2, 4

-- Not a verb, but `//hud reset all` already means something else.
local RESERVED_TARGETS = { all = true }

local function new(deps)
  local self = {}
  local reserved = deps.reserved or {}
  local by_name = {}
  local by_alias = {}
  local order = {}

  local function notify(message)
    if deps.notify then
      deps.notify(message)
    end
  end

  -- Registers a component. Raises on programmer error (bad or clashing name) —
  -- this runs at load time, where a hard failure is the visible one.
  function self.register(component)
    local name = type(component) == "table" and component.name or nil
    if type(name) ~= "string" or not name:match(NAME_PATTERN) then
      error("component name must be a word starting with a letter, got " .. tostring(name), 0)
    end

    local key = name:lower()
    if reserved[key] or RESERVED_TARGETS[key] then
      error("component name '" .. name .. "' is a reserved XIVHud command", 0)
    end
    if by_name[key] then
      error("component already registered: " .. name, 0)
    end
    if by_alias[key] then
      error("component name '" .. name .. "' is already another component's alias", 0)
    end

    -- The alias is optional; a component without one is reached by its name
    -- alone. Nothing is claimed until both name and alias have passed, so a
    -- rejected alias cannot leave its component half registered.
    local alias_key = nil
    local alias = component.alias
    if alias ~= nil then
      if type(alias) ~= "string" or not alias:match(ALIAS_PATTERN) or #alias < ALIAS_MIN or #alias > ALIAS_MAX then
        error(
          ("component alias must be %d-%d letters or digits starting with a letter, got %s"):format(
            ALIAS_MIN,
            ALIAS_MAX,
            tostring(alias)
          ),
          0
        )
      end
      alias_key = alias:lower()
      if reserved[alias_key] or RESERVED_TARGETS[alias_key] then
        error("component alias '" .. alias .. "' is a reserved XIVHud command", 0)
      end
      -- A word already spoken for by a NAME is fatal: two different components
      -- disagreeing about one word is a programmer error, and `key` is checked
      -- alongside the table because this component's own name is not in
      -- `by_name` yet (`{ name = "cb", alias = "cb" }` would alias a word to
      -- itself). A word already held by another ALIAS is not fatal - one
      -- factory registered several times declares the same alias on each
      -- registration, which is the party list - so the first claimant keeps it
      -- and the rest register without one, said out loud rather than guessed at.
      if by_name[alias_key] or alias_key == key then
        error("component alias '" .. alias .. "' is a component name", 0)
      end
      if by_alias[alias_key] then
        notify(("alias '%s' is already %s's; %s keeps none"):format(alias_key, by_alias[alias_key], name))
        alias_key = nil
      end
    end

    by_name[key] = component
    if alias_key then
      by_alias[alias_key] = key
    end
    order[#order + 1] = component
    return component
  end

  function self.get(name)
    if type(name) ~= "string" then
      return nil
    end
    return by_name[name:lower()]
  end

  -- Alias to component name, for the parser, which takes either. Nothing else
  -- consumes it: an alias is a word inside `//hud`, never a command of its own.
  function self.alias_map()
    local copy = {}
    for alias, name in pairs(by_alias) do
      copy[alias] = name
    end
    return copy
  end

  function self.all()
    local copy = {}
    for index, component in ipairs(order) do
      copy[index] = component
    end
    return copy
  end

  function self.names()
    local names = {}
    for index, component in ipairs(order) do
      names[index] = component.name
    end
    return names
  end

  -- Reverse order so that components torn down last were built first. One
  -- component failing must not strand another's prims on screen, so each
  -- destroy is isolated.
  function self.destroy_all()
    for index = #order, 1, -1 do
      local component = order[index]
      if component.destroy then
        local ok, err = pcall(component.destroy)
        if not ok then
          notify("error destroying " .. component.name .. ": " .. tostring(err))
        end
      end
    end
    by_name = {}
    by_alias = {}
    order = {}
  end

  return self
end

return new
