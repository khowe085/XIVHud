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

--[[ Pure crossbar input state machine: the DIK stream in, intents out.

     Fed every keyboard event as `on_key(dik, pressed, flags, blocked)`; returns
     the intent list for that event plus the block verdict Windower needs. No
     Windower globals - chat, suppression, visibility and edit mode arrive as
     injected accessors, which is the only reason any of this is testable. ]]

-- Each role is a list of DIKs in the config (`false` disables an entry), so a
-- role can carry more than one physical key.
local function each_dik(list, visit)
  if type(list) ~= "table" then
    return
  end
  -- Visited in index order, not pairs order: which entry claims a DIK first
  -- decides who keeps it, and that must not depend on the hash walk. Built by
  -- hand because `false` disables an entry and would cut ipairs short.
  local indexes = {}
  for index in pairs(list) do
    if type(index) == "number" then
      indexes[#indexes + 1] = index
    end
  end
  table.sort(indexes)
  for _, index in ipairs(indexes) do
    local dik = list[index]
    if dik then
      visit(dik, index)
    end
  end
end

-- Injected guard accessors default to false so a missing one reads as "off".
local function flag(accessor)
  return accessor ~= nil and accessor() and true or false
end

local function new(deps)
  local self = {}

  --[[ One DIK, one job. A hand-edited map can list the same key twice - the
       shipped one is disjoint - and every way of doing so used to fail
       quietly or worse: two roles were settled by which assignment ran last
       (the map's own order, read backwards), a slot key beat a shortcut by
       branch order in on_key and emitted nothing at all in its place, and a
       side key sharing a shortcut fired BOTH on one press. So claims are
       taken in the order the map reads - the two sides, the layer, the
       switch, the slot keys, then the shortcuts - and the FIRST claim keeps
       the key. Everything dropped is reported, once per config read; the
       widget says it. ]]
  local claimed = {}
  local conflicts = {}
  local conflict_of = {}
  local function claim(dik, what)
    if claimed[dik] == nil then
      claimed[dik] = what
      return true
    end
    local entry = conflict_of[dik]
    if entry == nil then
      entry = { dik = dik, kept = claimed[dik], dropped = {} }
      conflict_of[dik] = entry
      conflicts[#conflicts + 1] = entry
    end
    entry.dropped[#entry.dropped + 1] = what
    return false
  end

  local role_of = {}
  local function claim_role(list, role, label)
    each_dik(list, function(dik)
      if claim(dik, label) then
        role_of[dik] = role
      end
    end)
  end
  claim_role(deps.keys.xhb_left, "left", "the left side")
  claim_role(deps.keys.xhb_right, "right", "the right side")
  claim_role(deps.keys.w_layer, "layer", "the WXHB layer")
  claim_role(deps.keys.set_switch, "switch", "the set switch")
  local slot_of = {}
  each_dik(deps.keys.slot_keys, function(dik, slot)
    if claim(dik, "slot " .. slot) then
      slot_of[dik] = slot
    end
  end)
  -- Shortcuts claim last: theirs is the only role a key can lose without the
  -- bar itself changing shape.
  local shortcut_of = {}
  for dik, verbs in pairs(deps.keys.shortcuts or {}) do
    if claim(dik, "a shortcut") then
      shortcut_of[dik] = verbs
    end
  end
  -- Sorted: pairs() over the shortcuts would report them in a different
  -- order every login.
  table.sort(conflicts, function(a, b)
    return a.dik < b.dik
  end)

  --- Every DIK a later claim had to be dropped for, as
  --- `{ dik, kept, dropped = {...} }` - what the key does, and what it was
  --- also asked to do and will not.
  function self.conflicts()
    return conflicts
  end

  -- Held DIKs per role: a role is held while any of its keys is down.
  local held = { left = {}, right = {}, layer = {}, switch = {} }
  local first_side = nil

  -- Every mapped DIK currently down. Windows auto-repeat re-delivers
  -- pressed=true for held keys, so everything fires on a state CHANGE only.
  local down = {}

  -- One switch hold: tap = cycle, chorded with a slot key = jump, tapped over
  -- the held layer = draw. "Inert while any side is held" cuts two ways: jump
  -- is instantaneous and asks only that no side is held at the slot key's
  -- press edge, while cycle/draw die if a side overlapped the hold at ANY
  -- point - that is what `switch_poisoned` records.
  local switch_chorded = false
  local switch_poisoned = false

  -- Keys whose press we swallowed. The latch alone decides a release (and the
  -- auto-repeats in between): whatever the game saw go down, it must see come
  -- up, and never the other way around.
  local latched = {}

  local function role_held(role)
    return next(held[role]) ~= nil
  end

  -- The active hold state is a pure function of what is held. `\` is a layer,
  -- not a side: it turns a held side into its WXHB state and alone does nothing.
  function self.hold_state()
    if role_held("left") and role_held("right") then
      return first_side == "left" and "expanded_lr" or "expanded_rl"
    end
    if role_held("left") then
      return role_held("layer") and "wxhb_left" or "xhb_left"
    end
    if role_held("right") then
      return role_held("layer") and "wxhb_right" or "xhb_right"
    end
    return "none"
  end

  -- Alt-tab mid-hold must not strand anything "down". Latches go too: the
  -- game gets no events while unfocused either, and a stray key-up after
  -- refocus is harmless where a swallowed one is not.
  function self.focus_lost()
    local before = self.hold_state()
    held = { left = {}, right = {}, layer = {}, switch = {} }
    first_side = nil
    down = {}
    latched = {}
    switch_chorded = false
    switch_poisoned = false
    if before ~= "none" then
      return { { type = "activate", state = "none" } }
    end
    return {}
  end

  -- The full keyboard-event signature; `flags` (a modifier bitmask) is
  -- accepted but unused - v4 holds no modifiers.
  function self.on_key(dik, pressed, _flags, blocked)
    local role = role_of[dik]
    local slot = slot_of[dik]
    local shortcut = shortcut_of[dik]
    if not role and not slot and not shortcut then
      return {}, false
    end

    pressed = not not pressed
    local was_down = down[dik] and true or false
    local press_edge = pressed and not was_down
    down[dik] = pressed and true or nil

    local before = self.hold_state()

    if role == "left" or role == "right" then
      -- "First" means first of the currently-held pair: pressing a side while
      -- the other is already held makes the HELD one first, whatever order an
      -- earlier, partly-released pair was pressed in.
      local other = role == "left" and "right" or "left"
      if pressed and not role_held(role) then
        first_side = role_held(other) and other or role
      end
      held[role][dik] = pressed and true or nil
      if not role_held("left") and not role_held("right") then
        first_side = nil
      end
      if pressed and role_held("switch") then
        switch_poisoned = true
      end
    elseif role == "layer" then
      held[role][dik] = pressed and true or nil
    elseif role == "switch" then
      if pressed and not role_held("switch") then
        switch_chorded = false
        switch_poisoned = role_held("left") or role_held("right")
      end
      held[role][dik] = pressed and true or nil
    end

    local switch_released = role == "switch" and not pressed and was_down and not role_held("switch")
    -- Edge, not level: a slot key already down before the switch went down was
    -- not chorded during this hold, and its OS auto-repeats must not say it was.
    if slot and press_edge and role_held("switch") then
      switch_chorded = true
    end

    local chat_open = flag(deps.chat_open)
    local suppressed = flag(deps.suppressed)
    local disabled = flag(deps.disabled)
    local edit_mode = flag(deps.edit_mode)
    local layout_mode = flag(deps.layout_mode)
    local blocked_in = blocked and true or false

    local after = self.hold_state()
    local intents = {}
    -- `activate` mirrors state rather than acting, so the guards let it
    -- through: suppressing it strands an active side on the screen when an
    -- activator is released mid-chat. Disabled alone silences it - full
    -- inertness - though state keeps tracking for a re-enable mid-hold.
    if after ~= before and not disabled then
      intents[#intents + 1] = { type = "activate", state = after }
    end

    local actions_live = not (chat_open or blocked_in or suppressed or disabled or layout_mode)

    if actions_live and edit_mode then
      --[[ The binder owns the keyboard, with two exceptions.

           A press of a shortcut key that toggles edit - bare or chorded -
           exits, as it always did.

           And the SET SWITCH still works (Kevin, live client, 2026-08-22):
           which set is on screen is the thing edit mode is FOR, and leaving
           the mode to change it and coming back was the whole friction.
           Slot keys stay dead on their own - `jump` is a chord over the
           held switch, which no bare press can be mistaken for - and `draw`
           is not offered, because it is an action and edit mode fires
           none. ]]
      if shortcut and press_edge and (shortcut.tap == "edit" or shortcut.chorded == "edit") then
        intents[#intents + 1] = { type = "shortcut", verb = "edit" }
      elseif slot and press_edge and role_held("switch") then
        intents[#intents + 1] = { type = "jump", set = slot }
      elseif
        switch_released
        and not switch_chorded
        and not switch_poisoned
        and after == "none"
        and not role_held("layer")
      then
        intents[#intents + 1] = { type = "cycle" }
      end
    elseif actions_live then
      if slot and press_edge then
        -- Sides and the switch are never live together, so fire-vs-jump needs
        -- no precedence: a hold state means fire, the switch chord means jump.
        if after ~= "none" then
          intents[#intents + 1] = { type = "fire", slot = slot }
        elseif role_held("switch") then
          intents[#intents + 1] = { type = "jump", set = slot }
        end
      elseif switch_released and not switch_chorded and not switch_poisoned and after == "none" then
        if role_held("layer") then
          intents[#intents + 1] = { type = "draw" }
        else
          intents[#intents + 1] = { type = "cycle" }
        end
      elseif shortcut and press_edge then
        -- "Chorded" means a SIDE is held - the pad chord is trigger+Select;
        -- the layer and switch deliberately do not count.
        local side_held = role_held("left") or role_held("right")
        local verb = side_held and shortcut.chorded or shortcut.tap
        if verb then
          intents[#intents + 1] = { type = "shortcut", verb = verb }
        end
      end
    end

    local block
    if not pressed then
      block = latched[dik] or false
      latched[dik] = nil
    elseif not press_edge then
      block = latched[dik] or false
    else
      if disabled then
        -- Off means off: every key goes back to the game.
        block = false
      elseif blocked_in then
        -- Another addon already consumed the key; not ours to also swallow.
        block = false
      elseif chat_open then
        -- The chat box has the keyboard: our keys must stay typeable.
        block = false
      elseif role or shortcut then
        -- The five dedicated keys are ours outright; slot keys only while we
        -- are using them (the set-jump chord must not leak bare numbers).
        block = true
      else
        --[[ Slot keys are the game's the moment we are not using them, and
             what counts as "using" differs by mode.

             Edit mode fires nothing FROM a hold state - no slot acts - so
             a side being down leaves the numbers to the game. But the
             set-jump chord IS live there (Kevin, 2026-08-22), so a slot key
             over the held switch is one we are using, and letting it
             through as well fires FFXI's macro palette underneath the jump.

             The switch alone, therefore - never the hold state. Gating this
             on the hold state instead was wrong in the commonest case
             there is: edit mode is ENTERED by holding a side and pressing
             Select, and the machine goes on tracking that side, so the
             mode's own entry state was the one that leaked. ]]
        --[[ An if, not `a and b or c`: with the switch up that idiom's
             first half is false and it falls straight through to the
             other mode's expression, which is how the side-held case kept
             the OLD answer. ]]
        local using
        if edit_mode then
          using = role_held("switch")
        else
          using = after ~= "none" or role_held("switch")
        end
        block = not (suppressed or layout_mode) and using
      end
      latched[dik] = block or nil
    end

    return intents, block
  end

  return self
end

return new
