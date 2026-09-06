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

--[[ What class of weapon is in the main hand, as the name the binding model
     keys its weapon layer by. Pure: the two client reads and the resource
     tables all arrive as deps.

     The answer is a SKILL name ("Sword", "Great Katana"), never an item -
     one layer per class of weapon, the way the subjob layer is one per job.

     Two nils, told apart by the second return, because they are different
     facts to the caller: `nil, false` is "the client could not be read",
     which is the ordinary state for the first frames of a login and must
     leave the layer as it was; `nil, true` is an answer - there is no
     weapon layer - and clears it. A wrong layer is worse than none, and a
     layer that churns every login is worse than either. ]]

-- An equipment table carrying OTHER slots but no `main` reads as an empty
-- hand; one carrying nothing at all reads as a client that has not filled it
-- in yet. The read is whole-inventory and the client answers it whole, so a
-- table with no slot in it is not a character wearing nothing everywhere -
-- and taking it for one would latch Hand-to-Hand at login, clear the dirty
-- flag with it, and leave nothing to ask again until the player next changed
-- a piece of gear.
--
-- Unarmed is Hand-to-Hand in game terms (Kevin, 2026-09-04), so it resolves
-- through the same naming path an equipped H2H weapon does rather than
-- carrying a literal of its own: whatever the resources call skill 1, both
-- answer, and the two can never key different layers.
local UNARMED_SKILL = 1

local function skill_of(resources, item)
  local items = type(resources.items) == "table" and resources.items or nil
  local entry = items ~= nil and items[tonumber(item.id)] or nil
  if type(entry) ~= "table" then
    return nil
  end
  local skill = tonumber(entry.skill)
  -- Skill 0 is every item that is not a weapon; nothing names it.
  if skill == nil or skill == 0 then
    return nil
  end
  return skill
end

local function name_of(resources, skill)
  local skills = type(resources.skills) == "table" and resources.skills or nil
  local entry = skills ~= nil and skills[skill] or nil
  if type(entry) ~= "table" or type(entry.en) ~= "string" then
    return nil
  end
  return entry.en
end

local function new(deps)
  deps = deps or {}
  local self = {}

  --- The equipped weapon class, and whether that is an answer at all.
  function self.resolve()
    local resources = deps.resources
    if type(resources) ~= "table" or type(deps.get_equipment) ~= "function" or type(deps.get_items) ~= "function" then
      return nil, false
    end
    local equipment = deps.get_equipment()
    if type(equipment) ~= "table" or next(equipment) == nil then
      return nil, false
    end
    local index = tonumber(equipment.main)
    if index == nil or index == 0 then
      return name_of(resources, UNARMED_SKILL), true
    end
    --[[ An index with no bag beside it cannot be read, and the nil would
         ride into the client call without complaint. equipviewer reads the
         same half-answer as an EMPTY slot; here it clears the layer
         instead, which is deliberately not the same thing - an empty main
         hand is Hand-to-Hand, and "I could not read what you are holding"
         must not key a layer. ]]
    local bag = tonumber(equipment.main_bag)
    if bag == nil then
      return nil, true
    end
    local item = deps.get_items(bag, index)
    if type(item) ~= "table" then
      return nil, true
    end
    local skill = skill_of(resources, item)
    if skill == nil then
      return nil, true
    end
    return name_of(resources, skill), true
  end

  return self
end

return new
