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

--[[ The hotbar's behaviours: a row's slot, `bar<row>_slot<n>`, and the set
     cycle, `cycle` and `cycle_back` - in; one intent out, and for a press
     whether the key behind it is the hotbar's. Which key or chord that was
     - the shipped keyboard map has Ctrl, Alt and Shift over the number row
     (2026-11-09) - its repeats and its release are the keyboard map's.

     A slot fires and keeps its key: that swallows a Ctrl or Alt chord too,
     knowing it does nothing to the game's macro palette - `return true`
     swallows a bare key and does not stop FFXI acting on a CTRL/ALT chord,
     so a user of rows 1, 2 and 4-6 keeps the matching in-game macros inert
     (Kevin's call, 2026-09-06). Under any guard - chat open, suppressed,
     layout mode, edit mode, disabled - nothing fires and nothing is kept: no
     key of the hotbar's is worth protecting through a cutscene the way the
     crossbar's `;` is. A row the user HID (`deps.row_hidden`, the per-anchor
     switch) is the same: its chord goes back to the game rather than firing
     a bar nobody can see (Kevin, 2026-10-09). The cycle pair fire and keep
     NEITHER edge: a block cannot keep a CTRL chord from the game, and a
     swallowed up after CTRL lifted is a camera that keeps turning. No
     Windower globals. ]]

local ROWS, SLOTS = 8, 10
local SLOT_OF = {}
for row = 1, ROWS do
  for slot = 1, SLOTS do
    SLOT_OF["bar" .. row .. "_slot" .. slot] = { bar = "bar" .. row, slot = slot }
  end
end
local CYCLE_OF = { cycle = 1, cycle_back = -1 }

-- Injected guard accessors default to false so a missing one reads as "off".
local function flag(accessor)
  return accessor ~= nil and accessor() and true or false
end

local function new(deps)
  local self = {}

  local function guarded()
    return flag(deps.chat_open)
      or flag(deps.suppressed)
      or flag(deps.layout_mode)
      or flag(deps.edit_mode)
      or flag(deps.disabled)
  end

  --- One edge of a behaviour in; the intent (`{ bar, slot }` or `{ cycle }`)
  --- or nil out, and for a press whether the key behind it is the hotbar's.
  function self.on_behavior(name, pressed)
    local target, cycle = SLOT_OF[name], CYCLE_OF[name]
    if not pressed or (target == nil and cycle == nil) or guarded() then
      return nil, false
    end
    if cycle ~= nil then
      return { cycle = cycle }, false
    end
    if deps.row_hidden ~= nil and deps.row_hidden(target.bar) == true then
      return nil, false
    end
    return { bar = target.bar, slot = target.slot }, true
  end

  return self
end

return new
