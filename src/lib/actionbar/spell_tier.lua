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

--[[ AutoSpellTier: a tiered spell that cannot go gives way to the highest
     tier under it that can - Fire V to Fire IV, Utsusemi: San to Ni - and
     never to one above it. With no tier that can go, the spell goes as it
     was pressed and the game refuses it.

     A tier is read off the spell's own name: a Roman numeral on the end, the
     first tier carrying none, or ninjutsu's Ichi, Ni and San. A Trust is
     never tiered, Shantotto II being no tier of Shantotto, and a tier that
     cannot be aimed where the pressed spell can is never one to stand in.

     "Cannot go" is two questions. Whether the character can cast it at all -
     learned, and within reach of a job at its level now - is asked here, of
     the client. Its recast is the queue's to judge, since only the queue
     knows how long a lock has left and what it will wait out, and it is
     asked two things. `far_off` sends the walk down: a spell nearer ready
     than the queue's grace is never traded for a lower tier. `refused` is
     what the walk passes by: a tier the game would refuse if it were settled
     on now. MP is not asked: Penury, Light Arts and gear cut the cost below
     what the resource says.

     Pure: the setting, the spell lookup, the client reads and the queue's
     two answers arrive as deps, with `note` for the queue's debug log. ]]

local castable = require("lib/actionbar/castable")

-- The numeral each tier is written with. The first is written with none.
local NUMERALS = { "", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
local NUMERAL_TIERS = {}
for tier = 2, #NUMERALS do
  NUMERAL_TIERS[NUMERALS[tier]] = tier
end
local NINJUTSU = { "Ichi", "Ni", "San" }
local NINJUTSU_TIERS = { Ichi = 1, Ni = 2, San = 3 }

--- The names of the tiers under a spell, the nearest first.
local function tiers_under(name)
  local names = {}
  local base, numeral = name:match("^(.-) ([IVX]+)$")
  local tier = NUMERAL_TIERS[numeral]
  if tier ~= nil then
    for lower = tier - 1, 2, -1 do
      names[#names + 1] = base .. " " .. NUMERALS[lower]
    end
    names[#names + 1] = base
    return names
  end
  base, numeral = name:match("^(.-): (%a+)$")
  tier = NINJUTSU_TIERS[numeral]
  if tier ~= nil then
    for lower = tier - 1, 1, -1 do
      names[#names + 1] = base .. ": " .. NINJUTSU[lower]
    end
  end
  return names
end

--[[ Whether a tier can be aimed at every kind of target the pressed spell
     can, and so wherever the press was aimed: Warp is no stand-in for a Warp
     II cast at someone else. `targets` is a set of names from the resources
     library and a bitfield in the raw data. Where the two cannot be compared
     the game has the last word. ]]
local TARGET_BITS = 8

local function aims_as(lower, pressed)
  local offered, wanted = lower.targets, pressed.targets
  if type(wanted) == "table" and type(offered) == "table" then
    for kind, member in pairs(wanted) do
      if member == true and offered[kind] ~= true then
        return false
      end
    end
  elseif type(wanted) == "number" and type(offered) == "number" then
    for bit = 0, TARGET_BITS - 1 do
      local flag = 2 ^ bit
      if math.floor(wanted / flag) % 2 == 1 and math.floor(offered / flag) % 2 ~= 1 then
        return false
      end
    end
  end
  return true
end

local function new(deps)
  local self = {}

  function self.defaults()
    return { autospelltier = false }
  end

  --- Only an explicit `true` is on: it changes which spell a press casts.
  function self.enabled()
    local live = deps.config ~= nil and deps.config() or nil
    return type(live) == "table" and live.autospelltier == true
  end

  local function note(line)
    if deps.note ~= nil then
      deps.note(line)
    end
  end

  local function far_off(record)
    return deps.far_off ~= nil and deps.far_off(record) == true
  end

  local function refused(record)
    return deps.refused ~= nil and deps.refused(record) == true
  end

  --- The record to press in this one's place: a lower tier's where this spell
  --- cannot go and one under it can, and otherwise the record itself.
  function self.lower(record)
    if not self.enabled() or type(record) ~= "table" or record.type ~= "ma" or type(record.action) ~= "string" then
      return record
    end
    local spell = deps.find_spell(record.action)
    if type(spell) ~= "table" or type(spell.en) ~= "string" or spell.type == "Trust" then
      return record
    end
    local under = tiers_under(spell.en)
    if #under == 0 then
      return record
    end
    local known = deps.get_spells ~= nil and deps.get_spells() or nil
    local player = deps.get_player ~= nil and deps.get_player() or nil
    -- A client that cannot be read says nothing of what can be cast.
    if type(known) ~= "table" or type(player) ~= "table" then
      return record
    end
    local jobs = castable.job_pair(player)

    local function castable_now(entry)
      return known[entry.id] == true and castable.available(entry, jobs, player)
    end

    local why
    if not castable_now(spell) then
      why = "unavailable"
    elseif far_off(record) then
      why = "on recast"
    else
      return record
    end
    for _, name in ipairs(under) do
      local entry = deps.find_spell(name)
      if type(entry) == "table" and type(entry.en) == "string" and castable_now(entry) and aims_as(entry, spell) then
        local lowered = { type = "ma", action = entry.en, target = record.target }
        if not refused(lowered) then
          note(("%s %s, down to %s"):format(spell.en, why, entry.en))
          return lowered
        end
      end
    end
    note(("%s %s, no tier under it can go"):format(spell.en, why))
    return record
  end

  return self
end

return new
