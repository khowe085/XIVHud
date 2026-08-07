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

--[[ Per-component configuration service.

     Every component owns its own config and can never reach another's: a
     component receives only its own handle, bound to
     `data/<Character>/<component>.lua`. Files are Lua chunks — they are code,
     so they are loaded in an empty environment and behind a pcall; a broken or
     hostile file degrades to defaults plus a warning instead of taking the
     addon down.

     Windower's config lib is not used: it can only serialize XML, and the
     character name is unknown until login, which this service models directly
     (no character -> no config -> components stay hidden). ]]

local serialize = require("lib/serialize")

local load_chunk = loadstring or load

local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, item in pairs(value) do
    copy[key] = deep_copy(item)
  end
  return copy
end

-- User values win; default keys the user has never seen are filled in. Keys the
-- defaults do not mention (user-created layout slots, say) are preserved.
local function merge_defaults(user, defaults)
  local merged = deep_copy(user)
  for key, default_value in pairs(defaults) do
    if merged[key] == nil then
      merged[key] = deep_copy(default_value)
    elseif type(merged[key]) == "table" and type(default_value) == "table" then
      merged[key] = merge_defaults(merged[key], default_value)
    end
  end
  return merged
end

local function new(deps)
  local self = {}
  local character = nil
  local handles = {}
  local order = {}

  local function notify(message)
    if deps.notify then
      deps.notify(message)
    end
  end

  -- Reads one component file. Returns nil (and warns) for anything that is not
  -- a table produced by a chunk that ran cleanly in the sandbox.
  local function load_file(path)
    local contents = deps.read_file(path)
    if not contents or contents == "" then
      return nil
    end

    local chunk, syntax_error = load_chunk(contents, "@" .. path)
    if not chunk then
      notify("could not parse " .. path .. ": " .. tostring(syntax_error) .. " (using defaults)")
      return nil
    end

    setfenv(chunk, {})
    local ok, value = pcall(chunk)
    if not ok then
      notify("could not read " .. path .. ": " .. tostring(value) .. " (using defaults)")
      return nil
    end
    if type(value) ~= "table" then
      notify("ignoring " .. path .. ": expected a table, got " .. type(value) .. " (using defaults)")
      return nil
    end

    return value
  end

  local function load_handle(handle)
    if not character then
      handle._config = nil
      return
    end

    -- The merge walks the loaded table, so a hand-written cycle would recurse
    -- until the stack gives out. Defaults are the fallback here too.
    local stored = load_file(handle.path()) or {}
    local ok, merged = pcall(merge_defaults, stored, handle.defaults)
    if not ok then
      notify("could not merge " .. handle.path() .. ": " .. tostring(merged) .. " (using defaults)")
      merged = deep_copy(handle.defaults)
    end
    handle._config = merged
  end

  -- Registers a component's config namespace and returns its private handle.
  -- Loads straight away when a character is already logged in.
  function self.register(name, defaults)
    if handles[name] then
      error("settings namespace already registered: " .. tostring(name), 0)
    end

    local handle = { name = name, defaults = deep_copy(defaults or {}) }

    -- The component's own file. nil while logged out — there is nowhere to read
    -- or write yet.
    function handle.path()
      if not character then
        return nil
      end
      return "data/" .. character .. "/" .. name .. ".lua"
    end

    -- A component needing more than one file owns this directory outright.
    function handle.dir()
      if not character then
        return nil
      end
      return "data/" .. character .. "/" .. name
    end

    function handle.loaded()
      return handle._config ~= nil
    end

    function handle.get()
      return handle._config
    end

    function handle.save()
      local path = handle.path()
      if not path or not handle._config then
        return false
      end

      local ok, text = pcall(serialize, handle._config)
      if not ok then
        notify("could not serialize " .. name .. " config: " .. tostring(text))
        return false
      end

      local written, write_error = deps.write_file(path, text)
      if written == false then
        notify("could not write " .. path .. ": " .. tostring(write_error))
        return false
      end
      return true
    end

    function handle.reset()
      if not character then
        return false
      end
      handle._config = deep_copy(handle.defaults)
      return handle.save()
    end

    handles[name] = handle
    order[#order + 1] = name
    load_handle(handle)
    return handle
  end

  function self.get(name)
    return handles[name]
  end

  -- Re-reads every handle from disk, discarding whatever was held in memory.
  -- Used after the config files are replaced underneath us (`//hud copy`).
  function self.reload()
    for _, key in ipairs(order) do
      load_handle(handles[key])
    end
  end

  function self.character()
    return character
  end

  -- Login / logout / character switch. Re-announcing the same character is a
  -- no-op so that unsaved in-memory edits are not silently discarded.
  function self.set_character(name)
    if name == character then
      return false
    end
    character = name
    for _, key in ipairs(order) do
      load_handle(handles[key])
    end
    return true
  end

  return self
end

return new
