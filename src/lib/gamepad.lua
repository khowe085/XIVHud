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

--[[ One XInput pad as a stream of key edges.

     The bars read keys, so a controller reaches them as keys: each poll turns
     the pad's state into the (DIK, down) edges a keyboard would have
     delivered, and core hands those to the same dispatch a real key takes.
     The crossbar's input machine and the hotbar's arbitration see nothing
     new. Nothing here can keep a button from the game - the game's own
     controller bindings have to be blanked for that.

     A press is CHORDED while one of the `activators` keys is held - the
     bars' sides and set switch, held by this pad or by the keyboard, so a
     back button Steam Input maps to `;` counts. Chorded, a button sends its
     bar key. Bare, a button with a game key sends the game that instead,
     through `inject`, and the bars hear nothing: what a Steam Input chord
     did. Which of the two a press is, is settled when it goes down.

     Pure: the read, the clock, the config, the injection and the keyboard's
     state arrive as deps. ]]

-- XInput's own XINPUT_GAMEPAD_TRIGGER_THRESHOLD.
local DEFAULT_THRESHOLD = 30
-- How far under the threshold a held trigger must fall to let go, so one
-- resting on it cannot raise and drop a cross every frame.
local RELEASE_BAND = 10
-- XInputGetState on a slot with nothing in it is slow enough to stall a
-- frame, so a search that found nothing waits this long before the next.
local PROBE_SECONDS = 1
local SLOTS = 4

-- The order edges are reported in. Triggers first, so both sides pressed on
-- one frame reach the crossbar left first.
local BUTTONS = {
  { name = "lt", trigger = "left_trigger" },
  { name = "rt", trigger = "right_trigger" },
  { name = "lb", bit = 0x0100 },
  { name = "rb", bit = 0x0200 },
  { name = "back", bit = 0x0020 },
  { name = "start", bit = 0x0010 },
  { name = "l3", bit = 0x0040 },
  { name = "r3", bit = 0x0080 },
  { name = "y", bit = 0x8000 },
  { name = "b", bit = 0x2000 },
  { name = "a", bit = 0x1000 },
  { name = "x", bit = 0x4000 },
  { name = "up", bit = 0x0001 },
  { name = "right", bit = 0x0008 },
  { name = "down", bit = 0x0002 },
  { name = "left", bit = 0x0004 },
}

local function defaults()
  return {
    -- Off until switched on (Kevin): a player whose game still binds the pad
    -- would otherwise get a second Enter from every A.
    enabled = false,
    trigger_threshold = DEFAULT_THRESHOLD,
    -- The DIK each button sends; false sends nothing.
    buttons = {
      lt = 39, -- ; the crossbar's left side
      rt = 40, -- ' its right side
      lb = 43, -- \ the WXHB layer
      rb = 41, -- ` the set switch
      back = 13, -- = Select
      start = false,
      l3 = false,
      r3 = false,
      y = 2, -- 1-4: the face cross, slots 1-4
      b = 3,
      a = 4,
      x = 5,
      up = 6, -- 5-8: the D-pad cross, slots 5-8
      right = 7,
      down = 8,
      left = 9,
    },
    -- A button's DIK while another is held, picked when it goes down: RB with
    -- RT held is the WXHB layer, so each WXHB half is a trigger and its own
    -- bumper. false drops a chord.
    chords = {
      rb = { rt = 43 },
    },
    -- What a button sends the GAME when pressed bare, by Windower `setkey`
    -- name; false sends the bars its own key instead.
    bare = {
      a = "enter",
      b = "escape",
      x = "numpad+",
      y = "numpad-",
    },
    -- The keys whose being held makes a press chorded. false removes an
    -- entry: the settings merge refills a nil one.
    activators = { 39, 40, 41 },
  }
end
local DEFAULTS = defaults()
-- One empty list, read only and never handed anything: every poll of a
-- bridge switched off and holding nothing, and a section switched off.
local EMPTY = {}

local function is_dik(value)
  return type(value) == "number" and value >= 1 and value <= 255 and value == math.floor(value)
end

-- A word `setkey` could take and nothing more: the name is spliced into a
-- console command, where a `;` would start another.
local function is_key_name(value)
  return type(value) == "string" and value:match("^[%w%+%-%*/%.]+$") ~= nil
end

local function number_or_zero(value)
  return type(value) == "number" and value or 0
end

local function new(deps)
  local self = {}
  local read = type(deps.read) == "function" and deps.read or nil
  local inject = type(deps.inject) == "function" and deps.inject or nil

  -- The slot being read, or nil while searching; the slot a search reads next;
  -- how many slots in a row the search has found empty.
  local slot = nil
  local probe = 0
  local next_probe = nil
  local empty_probes = 0
  -- Button name -> `{ dik = , bare = }`, what it went down sending: a bar
  -- key, a game key, or neither. A button is in here exactly while it is
  -- held.
  local held = {}
  -- How many held buttons are sending each bar key and each game key, so a
  -- key two buttons share comes up only when both have.
  local senders = {}
  local injected = {}

  local function config()
    local value = deps.config and deps.config() or nil
    return type(value) == "table" and value or {}
  end

  local function threshold(settings)
    local value = settings.trigger_threshold
    if type(value) == "number" and value >= 0 and value <= 255 then
      return value
    end
    return DEFAULT_THRESHOLD
  end

  -- Each key falls back to its default on its own, so a config written before
  -- a button was mapped still sends it; a whole section set to false is off.
  local function entry(settings, section, name)
    local entries = settings[section]
    if entries == false then
      return nil
    end
    if type(entries) ~= "table" then
      entries = DEFAULTS[section]
    end
    local value = entries[name]
    if value == nil then
      value = DEFAULTS[section][name]
    end
    return value
  end

  local function key_for(settings, name, down)
    local chord = entry(settings, "chords", name)
    if type(chord) == "table" then
      for _, button in ipairs(BUTTONS) do
        local dik = chord[button.name]
        if down[button.name] and is_dik(dik) then
          return dik
        end
      end
    end
    local dik = entry(settings, "buttons", name)
    return is_dik(dik) and dik or false
  end

  local function activators(settings)
    local list = settings.activators
    if list == false then
      return EMPTY
    end
    return type(list) == "table" and list or DEFAULTS.activators
  end

  local function is_activator(settings, dik)
    for _, key in pairs(activators(settings)) do
      if key == dik then
        return true
      end
    end
    return false
  end

  local function chorded(settings)
    for _, dik in pairs(activators(settings)) do
      if is_dik(dik) and (senders[dik] ~= nil or (deps.key_held ~= nil and deps.key_held(dik))) then
        return true
      end
    end
    return false
  end

  -- nil where the press goes to the bars: chorded, no game key, or no way to
  -- reach the game.
  local function game_key(settings, name)
    if inject == nil or chorded(settings) then
      return nil
    end
    local key = entry(settings, "bare", name)
    return is_key_name(key) and key or nil
  end

  local function pressed_in(state, settings)
    local down = {}
    local buttons = number_or_zero(state.buttons)
    local floor = threshold(settings)
    for _, button in ipairs(BUTTONS) do
      if button.trigger then
        local bar = held[button.name] ~= nil and math.max(floor - RELEASE_BAND, 0) or floor
        down[button.name] = number_or_zero(state[button.trigger]) > bar
      else
        down[button.name] = math.floor(buttons / button.bit) % 2 == 1
      end
    end
    return down
  end

  -- Counts one more or one fewer sender of `key`; true when that crossed
  -- zero, which is when the key itself goes down or comes up.
  local function count(counts, key, delta)
    local now = (counts[key] or 0) + delta
    counts[key] = now > 0 and now or nil
    return (delta > 0 and now == 1) or (delta < 0 and now == 0)
  end

  local function lift(name, out)
    local sent = held[name]
    held[name] = nil
    if sent.dik and count(senders, sent.dik, -1) then
      out[#out + 1] = { dik = sent.dik, down = false }
    end
    if sent.bare and count(injected, sent.bare, -1) then
      inject(sent.bare, false)
    end
  end

  local function press(name, settings, down, out)
    local dik = key_for(settings, name, down)
    -- A button that IS a side is never bare: it would hold the side for the
    -- bars and press a key in the game at once.
    local bare = not (dik and is_activator(settings, dik)) and game_key(settings, name) or nil
    if bare then
      held[name] = { bare = bare }
      if count(injected, bare, 1) then
        inject(bare, true)
      end
      return
    end
    held[name] = { dik = dik or nil }
    if dik and count(senders, dik, 1) then
      out[#out + 1] = { dik = dik, down = true }
    end
  end

  -- One slot per search, so an empty slot's stall is one slot's, never four;
  -- a lost pad is looked for first where it was.
  local function current_state()
    local now = deps.now()
    if slot ~= nil then
      local state = read(slot)
      if state ~= nil then
        return state
      end
      probe, slot = slot, nil
      next_probe = now + PROBE_SECONDS
      empty_probes = 0
      return nil
    end
    if next_probe ~= nil and now < next_probe then
      return nil
    end
    next_probe = now + PROBE_SECONDS
    local index = probe
    probe = (probe + 1) % SLOTS
    local state = read(index)
    if state ~= nil then
      slot, empty_probes = index, 0
    else
      empty_probes = empty_probes + 1
    end
    return state
  end

  --- The bars' ups for everything held, game keys let go as well. Afterwards
  --- nothing is held, so a button still down is pressed again by the next
  --- poll that reads it.
  function self.release()
    local out = {}
    for _, button in ipairs(BUTTONS) do
      if held[button.name] ~= nil then
        lift(button.name, out)
      end
    end
    return out
  end

  --- Whether there is anything to read a pad with at all.
  function self.available()
    return read ~= nil
  end

  -- Only an explicit true: a hand-broken file must not switch on a bridge
  -- nobody asked for.
  local function is_enabled(settings)
    return settings.enabled == true
  end

  function self.enabled()
    return is_enabled(config())
  end

  --- This frame's edges for the bars, as `{ dik, down }` in order: every
  --- release, then every press. Game keys go out through `inject` as they
  --- happen. A pad that stops answering, or a bridge switched off, releases
  --- everything held.
  function self.poll()
    local settings = config()
    if not is_enabled(settings) then
      -- Whatever was found before is not known to be there when it comes
      -- back on, so the search starts over - where the pad was, as a lost
      -- one's does.
      probe = slot or probe
      slot, next_probe, empty_probes = nil, nil, 0
      -- Every frame, off being the shipped state: nothing allocated for a
      -- bridge that holds nothing.
      return next(held) == nil and EMPTY or self.release()
    end
    if read == nil then
      return {}
    end
    local state = current_state()
    local down = state ~= nil and pressed_in(state, settings) or {}
    local out = {}
    for _, button in ipairs(BUTTONS) do
      if held[button.name] ~= nil and not down[button.name] then
        lift(button.name, out)
      end
    end
    for _, button in ipairs(BUTTONS) do
      if down[button.name] and held[button.name] == nil then
        press(button.name, settings, down, out)
      end
    end
    return out
  end

  function self.status()
    if read == nil then
      return "gamepad: unavailable - " .. tostring(deps.unavailable or "no reader")
    end
    if not self.enabled() then
      return "gamepad: off"
    end
    if slot ~= nil then
      return "gamepad: on - pad " .. tostring(slot + 1) .. " connected"
    end
    -- Not until every slot has been asked: a bridge just switched on, or not
    -- yet polled, has not looked.
    if empty_probes >= SLOTS then
      return "gamepad: on - no pad connected"
    end
    return "gamepad: on - looking for a pad"
  end

  --- What data/gamepad.lua starts from.
  function self.config_defaults()
    return defaults()
  end

  return self
end

return new
