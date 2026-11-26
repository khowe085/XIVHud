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

     Which spells step down is each BINDING's to say (Kevin, 2026-11-25):
     `tier = "auto"` in its record, which the tier that stands in carries on.
     A binding without it goes as it is, and so does a ladder's pick, which
     is no binding of a spell.

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
     what the walk passes by: a tier whose recast runs past what a lock will
     wait out, or runs at all with nothing busy, where a tier ready now is
     the better one. MP is not asked: Penury, Light Arts and gear cut the cost below
     what the resource says.

     Pure: the spell lookup, the client reads and the queue's
     two answers arrive as deps, with `note` for the queue's debug log and
     what a line there quotes: a recast's seconds (`recast_left`) and what
     the queue is busy with (`doing`). ]]

local castable = require("lib/actionbar/castable")

-- What a binding's `tier` holds where it steps down. Anything else is off:
-- it changes which spell a press casts.
local AUTO = "auto"

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

  --[[ Whether a binding's spell has a tier under it that could stand in for
       it, which is what makes the flag worth offering. Asked of the
       resources alone, so it says nothing of now. False for anything but a
       spell, and nil for a name the resources do not know, which is not for
       this to refuse. ]]
  function self.has_lower(record)
    if type(record) ~= "table" or record.type ~= "ma" or type(record.action) ~= "string" then
      return false
    end
    local spell = deps.find_spell(record.action)
    if type(spell) ~= "table" or type(spell.en) ~= "string" then
      return nil
    end
    if spell.type == "Trust" then
      return false
    end
    for _, name in ipairs(tiers_under(spell.en)) do
      local entry = deps.find_spell(name)
      if type(entry) == "table" and type(entry.en) == "string" and aims_as(entry, spell) then
        return true
      end
    end
    return false
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

  -- What a spell's recast has left, where something answers for it. The debug
  -- line's alone: far_off and refused are what decide.
  local function recast_left(record)
    local left = deps.recast_left ~= nil and deps.recast_left(record) or nil
    return type(left) == "number" and left or nil
  end

  local function on_recast(record)
    local left = recast_left(record)
    return left ~= nil and ("on recast %.2fs"):format(left) or "on recast"
  end

  -- With what the queue was busy with, in its own words: a recast is far
  -- off against a lock's end, and against now under anything else.
  local function with_doing(words)
    local doing = deps.doing ~= nil and deps.doing() or nil
    return type(doing) == "string" and (words .. ", " .. doing) or words
  end

  --[[ The record to press in this one's place: a lower tier's where this spell
       cannot go and one under it can, and otherwise the record itself.

       `where` is the moment it is asked - at the press, at OK, at the
       release - for the one debug line a walk writes: the spell and why it
       could not go, each tier passed by and why, and what was settled on. A
       spell kept though its recast runs says so too, so a log shows the walk
       was asked. ]]
  function self.lower(record, where)
    if type(record) ~= "table" or record.tier ~= AUTO or record.type ~= "ma" or type(record.action) ~= "string" then
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

    -- Why the character cannot cast it at all, or nil for one it can.
    local function uncastable(entry)
      if known[entry.id] ~= true then
        return "not learned"
      end
      return castable.why_not(entry, jobs, player)
    end

    local said = {}
    local function settle(outcome)
      said[#said + 1] = outcome
      note((where ~= nil and (where .. ": ") or "") .. table.concat(said, "; "))
    end

    local why = uncastable(spell)
    if why == nil then
      if not far_off(record) then
        if (recast_left(record) or 0) > 0 then
          said[1] = spell.en .. " " .. with_doing(on_recast(record))
          settle("near enough ready, kept")
        end
        return record
      end
      why = with_doing(on_recast(record))
    end
    said[1] = spell.en .. " " .. why
    for _, name in ipairs(under) do
      local entry = deps.find_spell(name)
      if type(entry) ~= "table" or type(entry.en) ~= "string" then
        -- Not in the resources, or in them and no spell a player can cast,
        -- which the name lookup leaves out.
        said[#said + 1] = name .. " no such spell"
      else
        local lowered = { type = "ma", action = entry.en, target = record.target, tier = record.tier }
        local passed = uncastable(entry)
        if passed == nil and not aims_as(entry, spell) then
          passed = "cannot be aimed as " .. spell.en
        end
        if passed == nil and refused(lowered) then
          passed = on_recast(lowered)
        end
        if passed == nil then
          settle("down to " .. entry.en)
          return lowered
        end
        said[#said + 1] = entry.en .. " " .. passed
      end
    end
    settle("no tier under it can go")
    return record
  end

  return self
end

return new
