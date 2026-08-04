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

--[[ Framework-owned auto-hide: a set of suppression reasons, resolved to one
     answer for every component.

     Components never implement their own hide logic. A component renders when
     it is enabled in the active layout slot AND no reason is suppressing:

       event      -- player status 4, the status FFXI sets for the NPC
                     conversations and cutscenes that lock the player. Plain
                     dialog boxes do not set it, which is why only "certain
                     NPCs" hide the HUD.
       zoning     -- hidden on zone change and for a settle window afterwards,
                     so components do not flash stale data on zone-in.
       logged_out -- no character, so no config either; nothing can render.

     Suppression outranks layout mode: a cutscene hides the HUD even while the
     user is dragging widgets around. ]]

local EVENT_STATUS = 4
local DEFAULT_ZONE_DELAY = 3

local function new(deps)
  local self = {}
  local zone_delay = deps.zone_delay or DEFAULT_ZONE_DELAY
  local reasons = { logged_out = true }
  local hide_event = true
  local status = nil
  local zone_until = nil

  local function count()
    local n = 0
    for _ in pairs(reasons) do
      n = n + 1
    end
    return n
  end

  -- Runs a mutation and reports whether the answer components care about --
  -- "is anything suppressing?" -- actually flipped.
  local function transition(mutate)
    local before = count() > 0
    mutate()
    return before ~= (count() > 0)
  end

  local function apply_event()
    reasons.event = (hide_event and status == EVENT_STATUS) or nil
  end

  function self.set_logged_in(logged_in)
    return transition(function()
      reasons.logged_out = (not logged_in) or nil
    end)
  end

  function self.set_status(status_id)
    return transition(function()
      status = status_id
      apply_event()
    end)
  end

  -- The `hideCutscene` core option, for users who want the HUD during dialogue.
  function self.set_hide_event(enabled)
    return transition(function()
      hide_event = enabled and true or false
      apply_event()
    end)
  end

  function self.zone_changed()
    return transition(function()
      reasons.zoning = true
      zone_until = deps.now() + zone_delay
    end)
  end

  -- Drives the timed reasons; call once per frame.
  function self.tick()
    if not zone_until then
      return false
    end
    if deps.now() < zone_until then
      return false
    end
    return transition(function()
      zone_until = nil
      reasons.zoning = nil
    end)
  end

  function self.suppressed()
    return count() > 0
  end

  function self.reasons()
    local copy = {}
    for reason in pairs(reasons) do
      copy[reason] = true
    end
    return copy
  end

  return self
end

return new
