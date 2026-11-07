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

--[[ One XInput pad as a stream of behaviour edges.

     Each poll turns the pad's state into GESTURES - a button, or a chord of
     buttons ending in one - and each gesture into the behaviour the map
     holds for it (`map`, in data/gamepad.lua: a behaviour's name, or an
     entry of the gesture's own): `{ behavior, down }` edges for
     lib/behaviors, which alone knows what a behaviour does. Nothing here
     knows a key or a bar.

     A gesture is `lt+y`: the last button is the trigger, the rest held
     before it. It is resolved as the trigger goes down, against what is held
     then - the gesture naming the most held buttons wins, a tie going to the
     one whose newest button went down last - and it lasts while every button
     it names is held: the first of them up lets its behaviour go (Kevin,
     2026-11-06), so letting go of LT lowers WXHB left with LB still down.
     The trigger of a broken chord holds nothing until it is pressed again.

     The buttons XInput has no name for (the back buttons) reach the game as
     keys Steam Input types, named in `extra`. Core offers every key to
     `on_key`, which takes a named one while the bridge is on; the next poll
     answers it as a button.

     The map and the named keys are edited here too (`bind`, `unbind`,
     `set_key`), in the config table itself, for `//hud gamepad` to save.

     Pure: the read, the clock and the config arrive as deps, and so does
     `check(behavior)`, asked only to say which of the map's behaviours
     cannot work. ]]

-- XInput's own XINPUT_GAMEPAD_TRIGGER_THRESHOLD.
local DEFAULT_THRESHOLD = 30
-- How far under the threshold a held trigger must fall to let go, so one
-- resting on it cannot raise and drop a cross every frame.
local RELEASE_BAND = 10
-- XInputGetState on a slot with nothing in it is slow enough to stall a
-- frame, so a search that found nothing waits this long before the next.
local PROBE_SECONDS = 1
-- A named key is taken only while polls are running, or what it took would
-- wait for one that never comes - the pump's guard switched it off.
local STALL_SECONDS = 1
local SLOTS = 4
local NAME = "^[%l%d_]+$"

-- The order presses are answered in: the triggers first, so both pressed on
-- one frame reach the crossbar left first, the `extra` keys next, in the
-- order they came, and then these.
local TRIGGERS = {
  { name = "lt", trigger = "left_trigger" },
  { name = "rt", trigger = "right_trigger" },
}
local BUTTONS = {
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
local PAD_LISTS = { TRIGGERS, BUTTONS }
local PAD = {}
for _, list in ipairs(PAD_LISTS) do
  for _, button in ipairs(list) do
    PAD[button.name] = true
  end
end

-- The crossbar's slots in its own order: the face buttons clockwise from the
-- top, then the D-pad the same way.
local SLOT_BUTTONS = { "y", "b", "a", "x", "up", "right", "down", "left" }

local function defaults()
  local map = {
    a = "accept",
    b = "cancel",
    x = "cycle_window",
    y = "main_menu",
    lb = "autorun",
    rb = "crossbar.switch",
    lt = "crossbar.left",
    rt = "crossbar.right",
    ["lt+lb"] = "crossbar.wxhb_left",
    ["rt+rb"] = "crossbar.wxhb_right",
    ["lt+start"] = "crossbar.binder",
    ["rt+start"] = "crossbar.binder",
    back = "open_map",
    l3 = "lockon",
  }
  -- A slot under either side, and under the set switch, where it is a jump.
  for _, modifier in ipairs({ "lt", "rt", "rb" }) do
    for slot, button in ipairs(SLOT_BUTTONS) do
      map[modifier .. "+" .. button] = "crossbar.slot" .. slot
    end
  end
  return {
    -- Off until switched on (Kevin): a player whose game still binds the pad
    -- would otherwise get a second Enter from every A.
    enabled = false,
    trigger_threshold = DEFAULT_THRESHOLD,
    -- The key Steam Input types for each button XInput cannot see; false is
    -- none.
    extra = { l4 = false, l5 = false, r4 = false, r5 = false },
    map = map,
  }
end
local DEFAULTS = defaults()
-- What every poll of a bridge switched off and holding nothing answers, never
-- written to here - and kept apart from the empty list `resolve` walks, so a
-- caller that wrote to it could not reach that.
local NO_EDGES = {}
local NO_GESTURES = {}
local NO_MODIFIERS = {}

local function is_dik(value)
  return type(value) == "number" and value >= 1 and value <= 255 and value == math.floor(value)
end

local function number_or_zero(value)
  return type(value) == "number" and value or 0
end

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

-- How a gesture is kept in the map, and spelled in the shipped one:
-- lowercase, unspaced.
local function spelling_of(text)
  return (text:lower():gsub("%s", ""))
end

local function shipped_spelling(text)
  return type(text) == "string" and text == spelling_of(text)
end

-- The map's gestures, every other spelling ahead of the shipped kind, so the
-- one a user wrote comes before the one the settings merge put back.
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

-- The named keys: `{ names = { <name> = true }, by_dik = { <dik> = <name> } }`,
-- and why each entry left out was. A key two names claim is the first's.
local function read_extra(extra)
  local reading, problems = { names = {}, by_dik = {} }, {}
  for _, name in ipairs(sorted_keys(extra)) do
    local dik = extra[name]
    local label = "extra." .. tostring(name)
    if dik ~= false then
      if type(name) ~= "string" or not name:match(NAME) then
        problems[#problems + 1] = label .. " - a name is a plain lowercase word"
      elseif PAD[name] then
        problems[#problems + 1] = label .. " - an XInput button's name"
      elseif not is_dik(dik) then
        problems[#problems + 1] = label .. " - not a key number"
      elseif reading.by_dik[dik] ~= nil then
        problems[#problems + 1] = "extra." .. reading.by_dik[dik] .. " and " .. label .. " - both key " .. dik
      else
        reading.names[name] = true
        reading.by_dik[dik] = name
      end
    end
  end
  return reading, problems
end

-- A gesture's buttons, trigger last, or nil, why and the button it does not
-- know, where that is why.
local function read_gesture(text, extra_names)
  if type(text) ~= "string" then
    return nil, "not a gesture"
  end
  local buttons, seen = {}, {}
  for part in (spelling_of(text) .. "+"):gmatch("([^+]*)%+") do
    if part == "" then
      return nil, "an empty button"
    end
    if not PAD[part] and not extra_names[part] then
      return nil, "no button " .. part, part
    end
    if seen[part] then
      return nil, "names " .. part .. " twice"
    end
    seen[part] = true
    buttons[#buttons + 1] = part
  end
  return buttons
end

-- One gesture however it is spelled: its modifiers in order, then its trigger.
local function gesture_key(buttons)
  local modifiers = { unpack(buttons, 1, #buttons - 1) }
  table.sort(modifiers)
  modifiers[#modifiers + 1] = buttons[#buttons]
  return table.concat(modifiers, "+")
end

--[[ The map as trigger -> its gestures, `{ modifiers, behavior }`, and why
     each entry left out was. Two spellings of one gesture - a removal among
     them - are reported and the first in `map_order` kept, which is the one
     a user wrote. `check`, when given, is asked of each behaviour; one that
     cannot work stays in the map, inert, and is reported. ]]
local function read_map(map, extra_names, check)
  local by_trigger, problems, seen = {}, {}, {}
  for _, text in ipairs(map_order(map)) do
    local behavior = map[text]
    local label = tostring(text)
    local buttons, why = read_gesture(text, extra_names)
    if buttons == nil then
      if behavior ~= false then
        problems[#problems + 1] = label .. " - " .. why
      end
    else
      local key = gesture_key(buttons)
      if seen[key] ~= nil then
        problems[#problems + 1] = seen[key] .. " and " .. label .. " - the same gesture"
      else
        seen[key] = label
        if behavior ~= false and type(behavior) ~= "string" and type(behavior) ~= "table" then
          problems[#problems + 1] = label .. " - not a behavior"
        elseif behavior ~= false then
          local works, broken = true, nil
          if check ~= nil then
            works, broken = check(behavior)
          end
          if not works then
            problems[#problems + 1] = label .. " - " .. tostring(broken)
          end
          local trigger = table.remove(buttons)
          by_trigger[trigger] = by_trigger[trigger] or {}
          table.insert(by_trigger[trigger], { modifiers = buttons, behavior = behavior })
        end
      end
    end
  end
  return by_trigger, problems
end

local function map_of(settings)
  return type(settings.map) == "table" and settings.map or DEFAULTS.map
end

local function extra_of(settings)
  return type(settings.extra) == "table" and settings.extra or DEFAULTS.extra
end

-- The config's own map or extra, to be written to: a broken one becomes the
-- shipped one it was being read as, never the shared default itself.
local function writable(settings, field)
  if type(settings[field]) ~= "table" then
    settings[field] = defaults()[field]
  end
  return settings[field]
end

-- Every spelling in `map` of the gesture whose key is `key`.
local function spellings_of(map, key, extra_names)
  local found = {}
  for _, text in ipairs(sorted_keys(map)) do
    local buttons = read_gesture(text, extra_names)
    if buttons ~= nil and gesture_key(buttons) == key then
      found[#found + 1] = text
    end
  end
  return found
end

-- A name losing its key: a shipped one stays as the defaults spell it,
-- holding none, and one of the user's own goes.
local function forget_key(extra, name)
  if DEFAULTS.extra[name] ~= nil then
    extra[name] = false
  else
    extra[name] = nil
  end
end

local function new(deps)
  local self = {}
  local read = type(deps.read) == "function" and deps.read or nil

  -- The slot being read, or nil while searching; the slot a search reads next;
  -- how many slots in a row the search has found empty.
  local slot = nil
  local probe = 0
  local next_probe = nil
  local empty_probes = 0
  -- Button name -> `{ behavior = <name>|false, modifiers = { ... }, order =
  -- n, poll = n }`: what its press resolved to and the buttons that gesture
  -- leans on, and when it went down - in presses and in polls. In here
  -- exactly while it is held; `behavior` goes false once its chord breaks.
  local held = {}
  local presses = 0
  local polls = 0
  local last_poll = nil
  -- The named keys' edges since the last poll, `{ name, down }`, in order;
  -- and dik -> name for each key whose down was taken, so its up is too.
  local key_edges = {}
  local latched = {}
  -- The map and the named keys as last read, and the tables they came from.
  local gestures, named = {}, { names = {}, by_dik = {} }
  local map_source, extra_source = nil, nil

  local function config()
    local value = deps.config and deps.config() or nil
    return type(value) == "table" and value or {}
  end

  -- Only an explicit true: a hand-broken file must not switch on a bridge
  -- nobody asked for.
  local function is_enabled(settings)
    return settings.enabled == true
  end

  local function refresh(settings)
    local map, extra = map_of(settings), extra_of(settings)
    if map ~= map_source or extra ~= extra_source then
      map_source, extra_source = map, extra
      named = read_extra(extra)
      gestures = read_map(map, named.names)
    end
  end

  local function threshold(settings)
    local value = settings.trigger_threshold
    if type(value) == "number" and value >= 0 and value <= 255 then
      return value
    end
    return DEFAULT_THRESHOLD
  end

  local function pressed_in(state, settings)
    local down = {}
    local floor = threshold(settings)
    for _, button in ipairs(TRIGGERS) do
      local bar = held[button.name] ~= nil and math.max(floor - RELEASE_BAND, 0) or floor
      down[button.name] = number_or_zero(state[button.trigger]) > bar
    end
    local buttons = number_or_zero(state.buttons)
    for _, button in ipairs(BUTTONS) do
      down[button.name] = math.floor(buttons / button.bit) % 2 == 1
    end
    return down
  end

  local function resolve(button)
    local best, best_count, best_newest = nil, -1, -1
    for _, gesture in ipairs(gestures[button] or NO_GESTURES) do
      local newest, all_held = 0, true
      for _, modifier in ipairs(gesture.modifiers) do
        local holding = held[modifier]
        if holding == nil then
          all_held = false
          break
        end
        newest = math.max(newest, holding.order)
      end
      local count = #gesture.modifiers
      if all_held and (count > best_count or (count == best_count and newest > best_newest)) then
        best, best_count, best_newest = gesture, count, newest
      end
    end
    return best
  end

  local function press(button, out)
    presses = presses + 1
    local gesture = resolve(button)
    held[button] = {
      behavior = gesture and gesture.behavior or false,
      modifiers = gesture and gesture.modifiers or NO_MODIFIERS,
      order = presses,
      poll = polls,
    }
    if gesture then
      out[#out + 1] = { behavior = gesture.behavior, down = true }
    end
  end

  local function let_go(holding, out, cancelled)
    if holding.behavior then
      out[#out + 1] = { behavior = holding.behavior, down = false, cancelled = cancelled or nil }
      holding.behavior = false
    end
  end

  local function leans_on(holding, button)
    for _, modifier in ipairs(holding.modifiers) do
      if modifier == button then
        return true
      end
    end
    return false
  end

  -- A button up lets go of its own behaviour and of every chord it was a
  -- modifier of, those in the order they went down.
  local function lift(button, out, cancelled)
    local holding = held[button]
    held[button] = nil
    let_go(holding, out, cancelled)
    local broken = {}
    for _, other in pairs(held) do
      if other.behavior and leans_on(other, button) then
        broken[#broken + 1] = other
      end
    end
    table.sort(broken, function(a, b)
      return a.order < b.order
    end)
    for _, other in ipairs(broken) do
      let_go(other, out, cancelled)
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

  --- The ups, cancelled, for everything held. Afterwards nothing is held and
  --- no key is owed: a button still down is pressed again by the next poll
  --- that reads it, and a named key's up goes to the game.
  function self.release()
    local out = {}
    for _, button in ipairs(TRIGGERS) do
      if held[button.name] ~= nil then
        lift(button.name, out, true)
      end
    end
    for _, name in ipairs(sorted_keys(held)) do
      if not PAD[name] then
        lift(name, out, true)
      end
    end
    for _, button in ipairs(BUTTONS) do
      if held[button.name] ~= nil then
        lift(button.name, out, true)
      end
    end
    key_edges, latched = {}, {}
    return out
  end

  --- Whether there is anything to read a pad with at all.
  function self.available()
    return read ~= nil
  end

  function self.enabled()
    return is_enabled(config())
  end

  --- Whether the bridge takes this key: a named one's down while it is on,
  --- and the up of every down it took. Its edge is answered at the next poll.
  function self.on_key(dik, down)
    if not down then
      local name = latched[dik]
      if name == nil then
        return false
      end
      latched[dik] = nil
      key_edges[#key_edges + 1] = { name = name, down = false }
      return true
    end
    local settings = config()
    if read == nil or not is_enabled(settings) then
      return false
    end
    if last_poll == nil or deps.now() - last_poll > STALL_SECONDS then
      return false
    end
    refresh(settings)
    local name = named.by_dik[dik]
    if name == nil then
      return false
    end
    -- A held key's repeats are the bridge's too, and change nothing.
    if latched[dik] == nil then
      latched[dik] = name
      key_edges[#key_edges + 1] = { name = name, down = true }
    end
    return true
  end

  --- This frame's behaviour edges, `{ behavior, down, cancelled }` in order:
  --- the pad's releases, its triggers' presses, the named keys' edges as they
  --- came, then its other presses. A pad that stops answering, or a bridge
  --- switched off, lets go of everything it held, cancelled.
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
      if next(held) == nil and next(latched) == nil and #key_edges == 0 then
        return NO_EDGES
      end
      return self.release()
    end
    if read == nil then
      return {}
    end
    refresh(settings)
    polls = polls + 1
    last_poll = deps.now()
    local state = current_state()
    local down = state ~= nil and pressed_in(state, settings) or {}
    local out = {}
    for _, list in ipairs(PAD_LISTS) do
      for _, button in ipairs(list) do
        if held[button.name] ~= nil and not down[button.name] then
          lift(button.name, out, state == nil)
        end
      end
    end
    for _, button in ipairs(TRIGGERS) do
      if down[button.name] and held[button.name] == nil then
        press(button.name, out)
      end
    end
    if #key_edges > 0 then
      local edges = key_edges
      key_edges = {}
      for index, edge in ipairs(edges) do
        local holding = held[edge.name]
        if not edge.down and holding ~= nil and holding.poll == polls then
          -- A tap between two polls is held for this one and let go at the
          -- next, or a game key's down and up would leave in one frame, which
          -- the client never samples.
          for rest = index, #edges do
            key_edges[#key_edges + 1] = edges[rest]
          end
          break
        end
        if edge.down and holding == nil then
          press(edge.name, out)
        elseif not edge.down and holding ~= nil then
          lift(edge.name, out, false)
        end
      end
    end
    for _, button in ipairs(BUTTONS) do
      if down[button.name] and held[button.name] == nil then
        press(button.name, out)
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

  --- Why each gesture and named key left out of the map was, in order.
  function self.problems()
    local settings = config()
    local extra, extra_problems = read_extra(extra_of(settings))
    local check = type(deps.check) == "function" and deps.check or nil
    local _, map_problems = read_map(map_of(settings), extra.names, check)
    local out = {}
    for _, list in ipairs({ map_problems, extra_problems }) do
      for _, problem in ipairs(list) do
        out[#out + 1] = "gamepad: " .. problem
      end
    end
    return out
  end

  -- The map and the named keys are read afresh at the next look.
  local function changed()
    map_source, extra_source = nil, nil
  end

  --- Binds a gesture to a behaviour in place of whatever it held, under any
  --- spelling. Answers the spelling it is kept under, or nil, why and the
  --- button it does not know where that is why.
  function self.bind(text, behavior)
    local settings = config()
    local names = read_extra(extra_of(settings)).names
    local buttons, why, missing = read_gesture(text, names)
    if buttons == nil then
      return nil, why, missing
    end
    local map = writable(settings, "map")
    for _, spelling in ipairs(spellings_of(map, gesture_key(buttons), names)) do
      map[spelling] = nil
    end
    local spelling = spelling_of(text)
    map[spelling] = behavior
    changed()
    return spelling
  end

  --- Unbinds a gesture under every spelling; a shipped one is kept as
  --- false, which the settings merge would otherwise put back. One naming a
  --- button that has lost its key is found by its spelling alone. Answers
  --- the spelling, or nil, why and the button it does not know.
  function self.unbind(text)
    local settings = config()
    local map = writable(settings, "map")
    local names = read_extra(extra_of(settings)).names
    local buttons, why, missing = read_gesture(text, names)
    local spelling = type(text) == "string" and spelling_of(text) or nil
    local found
    local shipped = {}
    if buttons ~= nil then
      found = spellings_of(map, gesture_key(buttons), names)
      shipped = spellings_of(DEFAULTS.map, gesture_key(buttons), names)
    elseif spelling ~= nil and map[spelling] ~= nil then
      found = { spelling }
    else
      return nil, why, missing
    end
    local bound = false
    for _, other in ipairs(found) do
      bound = bound or map[other] ~= false
    end
    if not bound then
      return nil, "not bound"
    end
    for _, other in ipairs(found) do
      map[other] = nil
    end
    for _, other in ipairs(shipped) do
      map[other] = false
    end
    changed()
    return spelling
  end

  function self.set_enabled(on)
    config().enabled = on == true
  end

  --- The pad's own buttons, in the order a poll answers them.
  function self.buttons()
    local names = {}
    for _, list in ipairs(PAD_LISTS) do
      for _, button in ipairs(list) do
        names[#names + 1] = button.name
      end
    end
    return names
  end

  --- Every gesture the map holds, `{ gesture, behavior }`, in spelling
  --- order, its removals left out.
  function self.bindings()
    local map = map_of(config())
    local out = {}
    for _, text in ipairs(sorted_keys(map)) do
      if map[text] ~= false then
        out[#out + 1] = { gesture = text, behavior = map[text] }
      end
    end
    return out
  end

  --- Whether a name can be given a key: true, or nil and why not.
  function self.learnable(name)
    if type(name) ~= "string" or not name:match(NAME) then
      return nil, "a name is a plain lowercase word"
    end
    if PAD[name] then
      return nil, name .. " is a pad button"
    end
    return true
  end

  --- Every name with a key, `{ name, key }`, in name order.
  function self.named_keys()
    local extra = extra_of(config())
    local out = {}
    for _, name in ipairs(sorted_keys(read_extra(extra).names)) do
      out[#out + 1] = { name = name, key = extra[name] }
    end
    return out
  end

  --- The key a name has, or nil.
  function self.key_of(name)
    local dik = extra_of(config())[name]
    return is_dik(dik) and dik or nil
  end

  --- Gives a name a key, or takes its key away with false. A key another
  --- name had moves to this one; answers the name that lost it.
  function self.set_key(name, dik)
    local extra = writable(config(), "extra")
    local lost = nil
    if dik ~= false then
      for _, other in ipairs(sorted_keys(extra)) do
        if other ~= name and extra[other] == dik then
          lost = lost or other
          forget_key(extra, other)
        end
      end
      extra[name] = dik
    else
      forget_key(extra, name)
    end
    changed()
    return lost
  end

  --- What data/gamepad.lua starts from.
  function self.config_defaults()
    return defaults()
  end

  return self
end

return new
