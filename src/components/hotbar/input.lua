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

--[[ The hotbar's key machine: the DIK stream in, one intent out. The bare
     number row `1234567890` fires slots 1-10 of `bar1`; the modifiers pick
     the row - CTRL bar2, ALT bar3, SHIFT bar4, CTRL+SHIFT bar5, ALT+SHIFT
     bar6, CTRL+ALT+SHIFT bar7 - matched EXACTLY, so CTRL+ALT alone is
     nothing and reaches the game whole. bar8 has no keys (Kevin,
     2026-09-06). The table is fixed rather than config: the hotbar's keys
     ARE the game's row by design, so there is nothing to choose.

     Modifiers are tracked from their own down/up edges, the crossbar's and
     layout mode's technique, with the same caveat: one released while the
     client has no focus is stuck until `focus_lost` resets it.

     The block verdict: a number key the machine fires is swallowed on the
     down AND the matching up, so the game never sees half a key; that
     swallows the CTRL and ALT chords too, knowing it does nothing to the
     game's macro palette - `return true` swallows a bare key and does not
     stop FFXI acting on a CTRL/ALT chord, so a user of rows 2, 3 and 5-7
     keeps the matching in-game macros inert (Kevin's call, 2026-09-06).
     Under any guard - chat open, suppressed, layout mode, edit mode,
     disabled - or on a key a prior addon took, nothing fires and nothing is
     blocked: no key of the hotbar's is worth protecting through a cutscene
     the way the crossbar's `;` is. The cycle keys - CTRL+Up the next set,
     CTRL+Down the previous - are the one pair that claims NEITHER edge: a
     block cannot keep a CTRL chord from the game, and a swallowed up after
     CTRL lifted is a camera that keeps turning. The arrows' scan codes
     (200/208) are unverified in a client. No Windower globals. ]]

-- DirectInput scan codes: the number row, the arrows that cycle the active
-- set under CTRL (Kevin, 2026-09-06: the game cycles its macro sets on the
-- same chord, the caveat the rows already carry), and the three modifiers,
-- each side.
local CYCLE_OF = { [200] = 1, [208] = -1 }
local SLOT_OF = { [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6, [8] = 7, [9] = 8, [10] = 9, [11] = 10 }
local MODIFIER_OF = {
  [29] = "ctrl",
  [157] = "ctrl",
  [42] = "shift",
  [54] = "shift",
  [56] = "alt",
  [184] = "alt",
}
-- Which row each exact modifier set fires, keyed c/a/s in that order.
local BAR_OF = {
  [""] = "bar1",
  c = "bar2",
  a = "bar3",
  s = "bar4",
  cs = "bar5",
  as = "bar6",
  cas = "bar7",
}

-- Injected guard accessors default to false so a missing one reads as "off".
local function flag(accessor)
  return accessor ~= nil and accessor() and true or false
end

local function new(deps)
  local self = {}

  -- Which modifier DIKs are down; a modifier is held while any of its keys is.
  local held = {}
  -- The number keys whose down this machine took, so the up is taken too.
  local latched = {}
  -- Every slot or arrow key currently down, ours or not.
  local down = {}

  local function modifier_held(which)
    for dik, name in pairs(MODIFIER_OF) do
      if name == which and held[dik] then
        return true
      end
    end
    return false
  end

  local function combo()
    return (modifier_held("ctrl") and "c" or "")
      .. (modifier_held("alt") and "a" or "")
      .. (modifier_held("shift") and "s" or "")
  end

  local function guarded()
    return flag(deps.chat_open)
      or flag(deps.suppressed)
      or flag(deps.layout_mode)
      or flag(deps.edit_mode)
      or flag(deps.disabled)
  end

  --- One keyboard event in; the intent (`{ bar, slot }`) or nil out, plus the
  --- block verdict Windower needs.
  function self.on_key(dik, pressed, _flags, blocked)
    local modifier = MODIFIER_OF[dik]
    if modifier ~= nil then
      -- Tracked through every guard, so the row is right when it lifts.
      held[dik] = pressed or nil
      return nil, false
    end
    local cycle = CYCLE_OF[dik]
    local slot = SLOT_OF[dik]
    if slot == nil and cycle == nil then
      return nil, false
    end
    if not pressed then
      local ours = latched[dik] == true
      latched[dik] = nil
      down[dik] = nil
      return nil, ours
    end
    if latched[dik] then
      -- Auto-repeat of a key already down: still ours, and fires nothing.
      return nil, true
    end
    --[[ A key that went down as the game's stays the game's until it lifts:
         its OS auto-repeats must not become ours when CTRL arrives under a
         held arrow (the camera key would then never be released to the
         game) or when a guard lifts under a held number - the crossbar's
         press-edge rule. ]]
    local repeated = down[dik] == true
    down[dik] = true
    if repeated or blocked or guarded() then
      return nil, false
    end
    local held_set = combo()
    if cycle ~= nil then
      --[[ CTRL alone: CTRL+Up is the next set, CTRL+Down the previous. A
           bare arrow is the game's camera and any other chord is nobody's.
           Neither edge is claimed: a block cannot keep a CTRL chord from
           the game, so the game sees this down whatever we answer, and a
           latched up would be swallowed even after CTRL lifted - an arrow
           the game saw go down and never come up is a camera that keeps
           turning. `down` still keeps the repeats from firing again. ]]
      if held_set ~= "c" then
        return nil, false
      end
      return { cycle = cycle }, false
    end
    local bar = BAR_OF[held_set]
    if bar == nil then
      return nil, false
    end
    latched[dik] = true
    return { bar = bar, slot = slot }, true
  end

  --- Alt-tab mid-press: the releases will never arrive.
  function self.focus_lost()
    held = {}
    latched = {}
    down = {}
  end

  return self
end

return new
