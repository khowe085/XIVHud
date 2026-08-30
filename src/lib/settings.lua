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

     Every component owns its own directory and can never reach another's: a
     component receives only its own handle, bound to
     `data/<Character>/<slot>/<component>/`, holding `config.lua` (the
     component's settings), `layout.lua` (the placement core owns) and whatever
     else the component writes beside them. Files are Lua chunks - they are
     code, so they are loaded in an empty environment and behind a pcall; a
     broken or hostile file degrades to defaults plus a warning instead of
     taking the addon down.

     Scoping takes two steps, and in this order: the character, then the slot.
     The active slot is read out of `data/<Character>/core.lua`, which cannot be
     opened until the character is known - so `set_character` loads the
     character-scoped namespaces and leaves every component unloaded, and
     `set_slot` loads the components. `set_slot` always reads, rather than
     short-circuiting on an unchanged name: the slot can be called `default` for
     both characters and still be a different directory.

     Windower's config lib is not used: it can only serialize XML, and the
     character name is unknown until login, which this service models directly
     (no character -> no config -> components stay hidden). ]]

local serialize = require("lib/serialize")

local load_chunk = loadstring or load

-- Core writes these two into every component's directory, so a store file
-- naming either would overwrite the component's own settings or its placement.
-- Matched case-insensitively: the addon runs on Windows, where `Config.lua`
-- and `config.lua` are the same file.
local RESERVED_STORE_NAMES = { config = true, layout = true }

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
-- defaults do not mention are preserved.
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
  local slot = nil
  local handles = {}
  local order = {}

  local function notify(message)
    if deps.notify then
      deps.notify(message)
    end
  end

  -- Reads one file. Returns nil (and warns) for anything that is not a table
  -- produced by a chunk that ran cleanly in the sandbox.
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

  -- The merge walks the loaded table, so a hand-written cycle would recurse
  -- until the stack gives out. Defaults are the fallback there too.
  local function merged_from(path, defaults)
    local stored = load_file(path) or {}
    local ok, merged = pcall(merge_defaults, stored, defaults)
    if not ok then
      notify("could not merge " .. path .. ": " .. tostring(merged) .. " (using defaults)")
      return deep_copy(defaults)
    end
    return merged
  end

  local function write(path, value, label)
    local ok, text = pcall(serialize, value)
    if not ok then
      notify("could not serialize " .. label .. ": " .. tostring(text))
      return false
    end

    local written, write_error = deps.write_file(path, text)
    if written == false then
      notify("could not write " .. path .. ": " .. tostring(write_error))
      return false
    end
    return true
  end

  local function claim(name, handle)
    if handles[name] then
      error("settings namespace already registered: " .. tostring(name), 0)
    end
    handles[name] = handle
    order[#order + 1] = name
    handle.load()
    return handle
  end

  --[[ The character-scoped namespace: one file, `data/<Character>/<name>.lua`,
       outside every slot. Core alone uses it - it holds the active slot, which
       by definition cannot live inside one. ]]
  function self.register_character(name, defaults)
    local handle = { name = name, defaults = deep_copy(defaults or {}), character_scoped = true }

    function handle.path()
      if not character then
        return nil
      end
      return "data/" .. character .. "/" .. name .. ".lua"
    end

    function handle.load()
      handle._config = character and merged_from(handle.path(), handle.defaults) or nil
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
      return write(path, handle._config, name .. " config")
    end

    function handle.reset()
      if not character then
        return false
      end
      handle._config = deep_copy(handle.defaults)
      return handle.save()
    end

    return claim(name, handle)
  end

  --[[ A component's namespace: the directory
       `data/<Character>/<slot>/<name>/`. `defaults.layout` seeds layout.lua and
       is taken out of what seeds config.lua, so a component never sees its own
       placement in the table it is handed and merge_defaults cannot put it
       back. ]]
  function self.register(name, defaults)
    local config_defaults = deep_copy(defaults or {})
    local layout_defaults = config_defaults.layout
    config_defaults.layout = nil
    if type(layout_defaults) ~= "table" then
      layout_defaults = {}
    end

    local handle = {
      name = name,
      defaults = config_defaults,
      layout_defaults = layout_defaults,
      character_scoped = false,
      _store = {},
    }

    -- nil until both halves of the scope are known - there is nowhere to read
    -- or write before that.
    function handle.dir()
      if not character or not slot then
        return nil
      end
      return "data/" .. character .. "/" .. slot .. "/" .. name
    end

    function handle.config_path()
      local dir = handle.dir()
      return dir and (dir .. "/config.lua") or nil
    end

    function handle.layout_path()
      local dir = handle.dir()
      return dir and (dir .. "/layout.lua") or nil
    end

    function handle.load()
      -- The store cache goes whenever the config is re-read: a login, logout,
      -- character switch, slot switch or `//hud copy` reload must all reach the
      -- disk again.
      handle._store = {}
      if not handle.dir() then
        handle._config, handle._layout = nil, nil
        return
      end
      handle._config = merged_from(handle.config_path(), handle.defaults)
      handle._layout = merged_from(handle.layout_path(), handle.layout_defaults)
    end

    function handle.loaded()
      return handle._config ~= nil
    end

    function handle.get()
      return handle._config
    end

    function handle.layout()
      return handle._layout
    end

    function handle.save_config()
      local path = handle.config_path()
      if not path or not handle._config then
        return false
      end
      return write(path, handle._config, name .. " config")
    end

    function handle.save_layout()
      local path = handle.layout_path()
      if not path or not handle._layout then
        return false
      end
      return write(path, handle._layout, name .. " layout")
    end

    -- Both halves are attempted even when the first fails: a component whose
    -- settings could not be written must not also lose its placement.
    function handle.save()
      local config_written = handle.save_config()
      local layout_written = handle.save_layout()
      return config_written and layout_written
    end

    --[[ The store: the files a component adds beside config.lua and layout.lua
         (per-job bindings). Same trust model as those two - sandboxed load,
         serialized write - plus a cache dropped whenever the config is re-read.
         The name becomes a path segment, so anything but a plain word is
         refused outright rather than composed. ]]

    local function store_path(file)
      local dir = handle.dir()
      if not dir or type(file) ~= "string" or not file:match("^[%w_]+$") then
        return nil
      end
      if RESERVED_STORE_NAMES[file:lower()] then
        return nil
      end
      return dir .. "/" .. file .. ".lua"
    end

    -- Only found files are cached: a MISSING file is re-read from disk on
    -- every call (nil is uncacheable in a table). That is the contract -
    -- callers cache what they load and read on their own events (a job
    -- change, an attach); calling this per frame is forbidden.
    function handle.store_load(file)
      local path = store_path(file)
      if not path then
        return nil
      end
      if handle._store[file] == nil then
        handle._store[file] = load_file(path)
      end
      return handle._store[file]
    end

    function handle.store_save(file, value)
      local path = store_path(file)
      if not path or type(value) ~= "table" then
        return false
      end
      if not write(path, value, file) then
        return false
      end
      handle._store[file] = value
      return true
    end

    function handle.reset()
      local dir = handle.dir()
      if not dir then
        return false
      end
      -- The files a component writes beside config.lua and layout.lua would
      -- silently survive a reset otherwise - `//hud reset crossbar` must not
      -- leave last week's bindings behind. Only possible when the deps can
      -- enumerate and delete; the store cache is dropped either way.
      -- Deliberately NON-recursive: the directory is flat by construction
      -- (`store_path` admits no separators), so a nested directory here is not
      -- ours and is left alone. Only the active slot's copy is touched - a
      -- reset is scoped to the slot the player is in.
      if deps.list_dir and deps.delete_file then
        for _, entry in ipairs(deps.list_dir(dir) or {}) do
          if entry ~= "." and entry ~= ".." then
            deps.delete_file(dir .. "/" .. entry)
          end
        end
      end
      handle._store = {}
      handle._config = deep_copy(handle.defaults)
      handle._layout = deep_copy(handle.layout_defaults)
      return handle.save()
    end

    return claim(name, handle)
  end

  function self.get(name)
    return handles[name]
  end

  -- `nil` reloads every namespace; true or false narrows it to one kind.
  local function load_all(character_scoped)
    for _, key in ipairs(order) do
      local handle = handles[key]
      if character_scoped == nil or handle.character_scoped == character_scoped then
        handle.load()
      end
    end
  end

  -- Re-reads every handle from disk, discarding whatever was held in memory.
  -- Used after the config files are replaced underneath us (`//hud copy`).
  function self.reload()
    load_all(nil)
  end

  function self.character()
    return character
  end

  function self.slot()
    return slot
  end

  -- Login / logout / character switch. Re-announcing the same character is a
  -- no-op so that unsaved in-memory edits are not silently discarded.
  function self.set_character(name)
    if name == character then
      return false
    end
    character = name
    -- The new character's active slot lives in a file that has not been read
    -- yet, so every component goes unloaded until set_slot announces one.
    slot = nil
    load_all(nil)
    return true
  end

  -- Announced by core once it has read the character's core file, and again on
  -- every `//hud slot` switch. Always reads: set_character has just unloaded
  -- the components, and the same slot name under another character is another
  -- directory entirely.
  function self.set_slot(name)
    slot = name
    load_all(false)
  end

  return self
end

return new
