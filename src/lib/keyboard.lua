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
     key already down delivers nothing more until it comes up, whether or not
     its press was delivered, so a modifier arriving under a held key cannot
     turn its repeats into a chord. A press another addon took is not
     delivered at all, nor, with the chat line open, one whose behaviour is no
     component's: that key types.

     An entry is one key, or a CHORD of Ctrl, Alt and Shift over one key
     (`ctrl+shift+1`) - the hotbar's rows. The modifiers are tracked from
     their own edges, either side, and matched exactly; a key pressed under
     modifiers no chord of it names falls back to its bare entry, the crossbar
     having always ignored them. Any other chord is reported and left out.

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

-- The modifiers a chord names, each side by scan code, and the one order a
-- chord is spelled in.
local MODIFIER_OF = {
  [0x1D] = "ctrl",
  [0x9D] = "ctrl",
  [0x38] = "alt",
  [0xB8] = "alt",
  [0x2A] = "shift",
  [0x36] = "shift",
}
local MODIFIERS = { "ctrl", "alt", "shift" }
local IS_MODIFIER = { ctrl = true, alt = true, shift = true }

-- The hotbar's rows as its own key machine had them: Ctrl, Alt, Shift,
-- Ctrl+Shift, Alt+Shift and all three over the number row, `0` being
-- slot 10.
local HOTBAR_ROWS = {
  { "ctrl+", "bar1" },
  { "alt+", "bar2" },
  { "shift+", "bar3" },
  { "ctrl+shift+", "bar4" },
  { "alt+shift+", "bar5" },
  { "ctrl+alt+shift+", "bar6" },
}

-- The crossbar's own keys, as its `config.input` shipped them, and the
-- hotbar's rows and set cycle.
local function defaults()
  local map = {
    semicolon = "crossbar.left",
    apostrophe = "crossbar.right",
    backslash = "crossbar.layer",
    grave = "crossbar.switch",
    equals = "crossbar.select",
    ["ctrl+up"] = "hotbar.cycle",
    ["ctrl+down"] = "hotbar.cycle_back",
  }
  for slot = 1, 8 do
    map[tostring(slot)] = "crossbar.slot" .. slot
  end
  for _, row in ipairs(HOTBAR_ROWS) do
    for slot = 1, 10 do
      map[row[1] .. tostring(slot % 10)] = "hotbar." .. row[2] .. "_slot" .. slot
    end
  end
  return { enabled = true, map = map }
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

-- The map's keys, the user's own spellings ahead of the shipped map's, so the
-- one a user wrote comes before the one the settings merge put back.
local function map_order(map)
  local keys = sorted_keys(map)
  table.sort(keys, function(a, b)
    local shipped_a, shipped_b = DEFAULTS.map[a] ~= nil, DEFAULTS.map[b] ~= nil
    if shipped_a ~= shipped_b then
      return shipped_b
    end
    return tostring(a) < tostring(b)
  end)
  return keys
end

-- A chord's modifiers as they are spelled, in the one order.
local function prefix_of(named)
  local prefix = ""
  for _, modifier in ipairs(MODIFIERS) do
    if named[modifier] then
      prefix = prefix .. modifier .. "+"
    end
  end
  return prefix
end

-- An entry's key and its modifiers' prefix, or nil, nil and why. What is left
-- is looked up whole before a `+` in it reads as a chord, so `numpad+` is one
-- key.
local function read_key(text)
  if type(text) ~= "string" then
    return nil, nil, "not a key"
  end
  local rest, named = spelling_of(text), {}
  while DIK_OF[rest] == nil do
    local word, after = rest:match("^([^+]+)%+(.+)$")
    if word == nil then
      break
    end
    if not IS_MODIFIER[word] then
      return nil, nil, word .. " is no modifier: a chord is ctrl, alt or shift over one key"
    end
    if named[word] then
      return nil, nil, "names " .. word .. " twice"
    end
    named[word] = true
    rest = after
  end
  local dik = DIK_OF[rest]
  if dik == nil then
    return nil, nil, "no key " .. rest
  end
  return dik, prefix_of(named)
end

local function gesture_of(prefix, dik)
  return prefix .. "#" .. dik
end

--[[ The map as gesture -> `{ behavior, dik, prefix }`, and why each entry
     left out was. One key or chord spelled twice is reported and the first in
     `map_order` kept, which is the one a user wrote. `check`, when given, is
     asked of each behaviour; one that cannot work stays in the map, inert,
     and is reported. ]]
local function read_map(map, check)
  local by_gesture, problems, seen = {}, {}, {}
  for _, text in ipairs(map_order(map)) do
    local behavior = map[text]
    local label = tostring(text)
    local dik, prefix, why = read_key(text)
    local gesture = dik ~= nil and gesture_of(prefix, dik) or nil
    if dik == nil then
      if behavior ~= false then
        problems[#problems + 1] = label .. " - " .. why
      end
    elseif seen[gesture] ~= nil then
      problems[#problems + 1] = seen[gesture] .. " and " .. label .. " - the same key"
    else
      seen[gesture] = label
      if behavior ~= false and type(behavior) ~= "string" and type(behavior) ~= "table" then
        problems[#problems + 1] = label .. " - not a behavior"
      elseif behavior ~= false then
        if check ~= nil then
          local works, broken = check(behavior)
          if not works then
            problems[#problems + 1] = label .. " - " .. tostring(broken)
          end
        end
        by_gesture[gesture] = { behavior = behavior, dik = dik, prefix = prefix }
      end
    end
  end
  return by_gesture, problems
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
  -- Every key down, delivered or not, and the modifier keys among them.
  local down_keys, modifiers_down = {}, {}
  -- The map as last read, and the table it came from.
  local by_gesture, map_source = {}, nil

  local function config()
    local value = deps.config and deps.config() or nil
    return type(value) == "table" and value or {}
  end

  -- Only an explicit true, as every switch in the addon is read: a
  -- hand-broken value is off, though the map ships on.
  local function is_enabled(settings)
    return settings.enabled == true
  end

  local function refresh(settings)
    local map = map_of(settings)
    if map ~= map_source then
      map_source = map
      by_gesture = read_map(map)
    end
  end

  local function held_prefix()
    local named = {}
    for dik in pairs(modifiers_down) do
      named[MODIFIER_OF[dik]] = true
    end
    return prefix_of(named)
  end

  -- The chord the held modifiers make over this key, else its bare entry.
  local function resolve(dik, prefix)
    local entry = by_gesture[gesture_of(prefix, dik)]
    if entry == nil and prefix ~= "" then
      entry = by_gesture[gesture_of("", dik)]
    end
    return entry and entry.behavior or nil
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
    -- The modifiers held before this edge: a modifier is no chord of itself.
    local prefix = held_prefix()
    if MODIFIER_OF[dik] ~= nil then
      modifiers_down[dik] = down or nil
    end
    local holding = held[dik]
    if not down then
      down_keys[dik] = nil
      if holding == nil then
        return false
      end
      held[dik] = nil
      -- A release another addon took ends the hold without being one, so the
      -- set switch does not take it for a tap.
      deps.deliver(holding.behavior, false, blocked == true)
      return holding.taken
    end
    if down_keys[dik] then
      return holding ~= nil and holding.taken
    end
    down_keys[dik] = true
    if blocked then
      return false
    end
    local settings = config()
    if not is_enabled(settings) then
      return false
    end
    refresh(settings)
    local behavior = resolve(dik, prefix)
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
    held, down_keys, modifiers_down = {}, {}, {}
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
    local entries = {}
    for _, entry in pairs(by_gesture) do
      entries[#entries + 1] = entry
    end
    -- By key, a bare key ahead of its chords, the shorter chord first.
    table.sort(entries, function(a, b)
      if a.dik ~= b.dik then
        return a.dik < b.dik
      end
      if #a.prefix ~= #b.prefix then
        return #a.prefix < #b.prefix
      end
      return a.prefix < b.prefix
    end)
    local out = {}
    for _, entry in ipairs(entries) do
      out[#out + 1] = { key = entry.prefix .. KEY_NAMES[entry.dik], behavior = entry.behavior }
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
