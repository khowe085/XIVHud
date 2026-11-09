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

--[[ The keyboard as behaviour edges, as lib/gamepad has the pad.

     Each key names a BEHAVIOUR in the map (`map`, in data/keyboard.lua: a
     behaviour's name, or an entry of the key's own), and its edges go to
     lib/behaviors, which alone knows what a behaviour does, through
     `deliver(behavior, down, cancelled) -> taken`. Whether the key is kept
     from the game is the behaviour's answer to the press: a component's own
     says (the crossbar keeps its five dedicated keys, and the number row only
     while it uses it), and a game key or an action always keeps it.

     A press is delivered once. Its repeats change nothing and answer what it
     answered; so does its release, delivered whatever has changed since -
     whatever the game saw go down it must see come up, and nothing else. A
     press another addon took is not delivered at all, nor, with the chat line
     open, one whose behaviour is no component's: that key types.

     One key per entry: a chord is reported and left out.

     Pure: the config, the delivery, `is_component`, `chat_open` and `check`
     arrive as deps. ]]

-- DirectInput's scan codes and its names for them, lowercased; Enter,
-- Escape and the numpad's operators as `setkey` spells them.
local KEY_NAMES = {
  [0x01] = "escape",
  [0x02] = "1",
  [0x03] = "2",
  [0x04] = "3",
  [0x05] = "4",
  [0x06] = "5",
  [0x07] = "6",
  [0x08] = "7",
  [0x09] = "8",
  [0x0A] = "9",
  [0x0B] = "0",
  [0x0C] = "minus",
  [0x0D] = "equals",
  [0x0E] = "backspace",
  [0x0F] = "tab",
  [0x10] = "q",
  [0x11] = "w",
  [0x12] = "e",
  [0x13] = "r",
  [0x14] = "t",
  [0x15] = "y",
  [0x16] = "u",
  [0x17] = "i",
  [0x18] = "o",
  [0x19] = "p",
  [0x1A] = "lbracket",
  [0x1B] = "rbracket",
  [0x1C] = "enter",
  [0x1D] = "lctrl",
  [0x1E] = "a",
  [0x1F] = "s",
  [0x20] = "d",
  [0x21] = "f",
  [0x22] = "g",
  [0x23] = "h",
  [0x24] = "j",
  [0x25] = "k",
  [0x26] = "l",
  [0x27] = "semicolon",
  [0x28] = "apostrophe",
  [0x29] = "grave",
  [0x2A] = "lshift",
  [0x2B] = "backslash",
  [0x2C] = "z",
  [0x2D] = "x",
  [0x2E] = "c",
  [0x2F] = "v",
  [0x30] = "b",
  [0x31] = "n",
  [0x32] = "m",
  [0x33] = "comma",
  [0x34] = "period",
  [0x35] = "slash",
  [0x36] = "rshift",
  [0x37] = "numpad*",
  [0x38] = "lalt",
  [0x39] = "space",
  [0x3A] = "capslock",
  [0x3B] = "f1",
  [0x3C] = "f2",
  [0x3D] = "f3",
  [0x3E] = "f4",
  [0x3F] = "f5",
  [0x40] = "f6",
  [0x41] = "f7",
  [0x42] = "f8",
  [0x43] = "f9",
  [0x44] = "f10",
  [0x45] = "numlock",
  [0x46] = "scrolllock",
  [0x47] = "numpad7",
  [0x48] = "numpad8",
  [0x49] = "numpad9",
  [0x4A] = "numpad-",
  [0x4B] = "numpad4",
  [0x4C] = "numpad5",
  [0x4D] = "numpad6",
  [0x4E] = "numpad+",
  [0x4F] = "numpad1",
  [0x50] = "numpad2",
  [0x51] = "numpad3",
  [0x52] = "numpad0",
  [0x53] = "numpad.",
  [0x57] = "f11",
  [0x58] = "f12",
  [0x9C] = "numpadenter",
  [0x9D] = "rctrl",
  [0xB5] = "numpad/",
  [0xB8] = "ralt",
  [0xC5] = "pause",
  [0xC7] = "home",
  [0xC8] = "up",
  [0xC9] = "pageup",
  [0xCB] = "left",
  [0xCD] = "right",
  [0xCF] = "end",
  [0xD0] = "down",
  [0xD1] = "pagedown",
  [0xD2] = "insert",
  [0xD3] = "delete",
  [0xDB] = "lwin",
  [0xDC] = "rwin",
  [0xDD] = "apps",
}
local DIK_OF = {}
for dik, name in pairs(KEY_NAMES) do
  DIK_OF[name] = dik
end

-- The crossbar's own keys, as its `config.input` ships them.
local function defaults()
  local map = {
    semicolon = "crossbar.left",
    apostrophe = "crossbar.right",
    backslash = "crossbar.layer",
    grave = "crossbar.switch",
    equals = "crossbar.select",
  }
  for slot = 1, 8 do
    map[tostring(slot)] = "crossbar.slot" .. slot
  end
  return { enabled = false, map = map }
end
local DEFAULTS = defaults()

local function sorted_keys(entries)
  local keys = {}
  for key in pairs(entries) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

-- How a key is kept in the map, and spelled in the shipped one: lowercase,
-- unspaced.
local function spelling_of(text)
  return (text:lower():gsub("%s", ""))
end

local function shipped_spelling(text)
  return type(text) == "string" and text == spelling_of(text)
end

-- The map's keys, every other spelling ahead of the shipped kind, so the one
-- a user wrote comes before the one the settings merge put back.
local function map_order(map)
  local keys = sorted_keys(map)
  table.sort(keys, function(a, b)
    local shipped_a, shipped_b = shipped_spelling(a), shipped_spelling(b)
    if shipped_a ~= shipped_b then
      return shipped_b
    end
    return tostring(a) < tostring(b)
  end)
  return keys
end

-- A key's scan code, or nil and why.
local function read_key(text)
  if type(text) ~= "string" then
    return nil, "not a key"
  end
  local spelling = spelling_of(text)
  local dik = DIK_OF[spelling]
  if dik ~= nil then
    return dik
  end
  -- Only once the name is no key's: `numpad+` is one key.
  if spelling:find("+", 1, true) then
    return nil, "one key per entry: the keyboard reads no chords"
  end
  return nil, "no key " .. spelling
end

--[[ The map as scan code -> behaviour, and why each entry left out was. One
     key spelled twice is reported and the first in `map_order` kept, which is
     the one a user wrote. `check`, when given, is asked of each behaviour;
     one that cannot work stays in the map, inert, and is reported. ]]
local function read_map(map, check)
  local by_dik, problems, seen = {}, {}, {}
  for _, text in ipairs(map_order(map)) do
    local behavior = map[text]
    local label = tostring(text)
    local dik, why = read_key(text)
    if dik == nil then
      if behavior ~= false then
        problems[#problems + 1] = label .. " - " .. why
      end
    elseif seen[dik] ~= nil then
      problems[#problems + 1] = seen[dik] .. " and " .. label .. " - the same key"
    else
      seen[dik] = label
      if behavior ~= false and type(behavior) ~= "string" and type(behavior) ~= "table" then
        problems[#problems + 1] = label .. " - not a behavior"
      elseif behavior ~= false then
        if check ~= nil then
          local works, broken = check(behavior)
          if not works then
            problems[#problems + 1] = label .. " - " .. tostring(broken)
          end
        end
        by_dik[dik] = behavior
      end
    end
  end
  return by_dik, problems
end

local function map_of(settings)
  return type(settings.map) == "table" and settings.map or DEFAULTS.map
end

local function new(deps)
  local self = {}
  local check = type(deps.check) == "function" and deps.check or nil
  local is_component = type(deps.is_component) == "function" and deps.is_component or nil
  local chat_open = type(deps.chat_open) == "function" and deps.chat_open or nil

  -- Scan code -> `{ behavior, taken, order }`: every key whose press was
  -- delivered, until its release is.
  local held = {}
  local presses = 0
  -- The map as last read, and the table it came from.
  local by_dik, map_source = {}, nil

  local function config()
    local value = deps.config and deps.config() or nil
    return type(value) == "table" and value or {}
  end

  -- Only an explicit true: a hand-broken file must not hand the bar's keys
  -- to a map nobody switched on.
  local function is_enabled(settings)
    return settings.enabled == true
  end

  local function refresh(settings)
    local map = map_of(settings)
    if map ~= map_source then
      map_source = map
      by_dik = read_map(map)
    end
  end

  -- With the chat line open a key types, unless its behaviour is a
  -- component's, which judges the chat line for itself.
  local function types(behavior)
    if chat_open == nil or chat_open() ~= true then
      return false
    end
    return is_component ~= nil and not is_component(behavior)
  end

  --- Whether the game is kept from this key edge.
  function self.on_key(dik, down, blocked)
    local holding = held[dik]
    if holding ~= nil then
      if not down then
        held[dik] = nil
        deps.deliver(holding.behavior, false, false)
      end
      return holding.taken
    end
    if not down or blocked then
      return false
    end
    local settings = config()
    if not is_enabled(settings) then
      return false
    end
    refresh(settings)
    local behavior = by_dik[dik]
    if behavior == nil or types(behavior) then
      return false
    end
    presses = presses + 1
    -- Held before it goes out, so a throw downstream leaves the release still
    -- to deliver.
    holding = { behavior = behavior, taken = false, order = presses }
    held[dik] = holding
    holding.taken = deps.deliver(behavior, true, false) == true
    return holding.taken
  end

  --- Lets go of every key held, cancelled, in the order they went down - a
  --- lost focus, a switch-off, an unload. The ups that follow are nobody's.
  --- Each is let go though one throws, and the first error raised after.
  function self.release()
    local holdings = {}
    for _, holding in pairs(held) do
      holdings[#holdings + 1] = holding
    end
    table.sort(holdings, function(a, b)
      return a.order < b.order
    end)
    held = {}
    local failure = nil
    for _, holding in ipairs(holdings) do
      local ok, err = pcall(deps.deliver, holding.behavior, false, true)
      if not ok and failure == nil then
        failure = err
      end
    end
    if failure ~= nil then
      error(failure, 0)
    end
  end

  function self.enabled()
    return is_enabled(config())
  end

  function self.set_enabled(on)
    config().enabled = on == true
  end

  --- Each key the map binds and what it does, in keyboard order.
  function self.bindings()
    refresh(config())
    local codes = {}
    for dik in pairs(by_dik) do
      codes[#codes + 1] = dik
    end
    table.sort(codes)
    local out = {}
    for _, dik in ipairs(codes) do
      out[#out + 1] = { key = KEY_NAMES[dik], behavior = by_dik[dik] }
    end
    return out
  end

  --- Why each entry left out of the map was, in order.
  function self.problems()
    local _, problems = read_map(map_of(config()), check)
    local out = {}
    for _, problem in ipairs(problems) do
      out[#out + 1] = "keyboard: " .. problem
    end
    return out
  end

  function self.config_defaults()
    return defaults()
  end

  return self
end

return new
