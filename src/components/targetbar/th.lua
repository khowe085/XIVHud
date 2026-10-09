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

--[[ Treasure Hunter levels, per mob, as the Windower `thtracker` addon reads
     them (BSD, (c) 2017 Krizz) - its detection and its forgetting, and
     nothing of its own text box. Pure: the widget hands it what the chunk
     dispatch carries and asks it for a level by mob id.

     Detection reads Target 1 Action 1 alone, as the reference does: a melee
     round's added effect with message 603, or a weaponskill's message 608, the
     level in the matching param. ]]

local MELEE = 1
local WEAPONSKILL = 3
local MELEE_MESSAGE = 603
local WEAPONSKILL_MESSAGE = 608

local ZONE_IN = 0x00A
local NPC_UPDATE = 0x00E
local ANIMATION = 0x038

-- The despawn animation 0x038 names.
local DESPAWN = "kesu"
-- 0x00E's Status for an idle mob, which with full health is a mob that reset.
local IDLE = 0

-- 1-based offsets into the raw chunk, header included: fields.lua's 0x04 for
-- both ids, 0x0C for the animation name, 0x1E and 0x1F for HP % and Status.
local ID_OFFSET = 5
local ANIMATION_OFFSET = 13
local HPP_OFFSET = 31
local STATUS_OFFSET = 32

local function u32(raw, offset)
  local b1, b2, b3, b4 = raw:byte(offset, offset + 3)
  if not b4 then
    return nil
  end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function first_action(act)
  local target = type(act.targets) == "table" and act.targets[1] or nil
  if type(target) ~= "table" or type(target.actions) ~= "table" then
    return nil, nil
  end
  local action = target.actions[1]
  if type(action) ~= "table" then
    return nil, nil
  end
  return target.id, action
end

local function new()
  local self = {}
  local levels = {}

  function self.level(mob_id)
    return levels[mob_id]
  end

  function self.clear()
    levels = {}
  end

  function self.on_action(act)
    if type(act) ~= "table" then
      return
    end
    local id, action = first_action(act)
    if id == nil then
      return
    end
    local level
    if act.category == MELEE and action.has_add_effect and action.add_effect_message == MELEE_MESSAGE then
      level = tonumber(action.add_effect_param)
    elseif act.category == WEAPONSKILL and action.message == WEAPONSKILL_MESSAGE then
      level = tonumber(action.param)
    end
    if level then
      levels[id] = level
    end
  end

  function self.on_chunk(id, raw)
    if id == ZONE_IN then
      self.clear()
      return
    end
    if type(raw) ~= "string" then
      return
    end
    if id == ANIMATION then
      local mob = u32(raw, ID_OFFSET)
      if mob and raw:sub(ANIMATION_OFFSET, ANIMATION_OFFSET + 3) == DESPAWN then
        levels[mob] = nil
      end
    elseif id == NPC_UPDATE then
      local mob = u32(raw, ID_OFFSET)
      local hpp, status = raw:byte(HPP_OFFSET, STATUS_OFFSET)
      if mob and hpp == 100 and status == IDLE then
        levels[mob] = nil
      end
    end
  end

  return self
end

return new
