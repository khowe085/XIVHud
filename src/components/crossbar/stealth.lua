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

--[[ The one-button stealth ladders: `sneak` and `invisible` each walk a
     fixed list of ways to get the effect and fire the first one this
     character can actually use right now.

     The order is CHEAPEST FIRST and the same on every job (Kevin,
     2026-08-29) - ninjutsu, then the jig, then the spell, then the item -
     rather than preferring whatever the main job happens to offer. The same
     press then does the same thing whoever presses it, and the item is only
     ever reached when nothing else is.

     Every rung is gated on what the CLIENT says, never on hardcoded job
     levels: `get_spells`/`get_abilities` answer what this character knows,
     and the resource's own `levels` table answers whether the current
     main/sub pair may use it - the same two questions catalog.lua asks of
     every other action, which is why a subjob change needs no notification
     here. A ninjutsu rung also wants its tool in the bag, since the press
     would otherwise be spent on a message from the game.

     Nothing here executes: plan() answers a command string for the widget
     to send, so the ladder stays testable without a client. ]]

local counters = require("components/crossbar/counters")

-- Resource ids, verified against Windower's own resource data rather than
-- remembered: Sneak/Invisible are White Magic, the two ninjutsu are spells
-- as well (the client lists them in get_spells), and the jig is an ability.
local SNEAK, INVISIBLE = 137, 136
local MONOMI_ICHI, TONKO_ICHI = 318, 353
local SPECTRAL_JIG = 196

--[[ Cheapest first. `spell` and `ability` are resource lookups; `item` is a
     name, because `/item` takes the name and the id only ever matters for
     the bag count - which is resolved by name too, the way the temporary
     bag and the resting status already are. ]]
local LADDERS = {
  sneak = {
    { kind = "spell", id = MONOMI_ICHI },
    { kind = "ability", id = SPECTRAL_JIG },
    { kind = "spell", id = SNEAK },
    { kind = "item", name = "Silent Oil" },
  },
  invisible = {
    { kind = "spell", id = TONKO_ICHI },
    { kind = "ability", id = SPECTRAL_JIG },
    { kind = "spell", id = INVISIBLE },
    { kind = "item", name = "Prism Powder" },
  },
}

-- FFXI's own cap, the same constant catalog.lua gates the merit exception
-- on: a requirement above it is a merit or job point, which only a main job
-- can have spent.
local LEVEL_CAP = 99

-- The `targets` bitfield's Party bit. A rung without it is self-only -
-- both ninjutsu and the jig are - and can never carry <t>.
local PARTY_BIT = 4

local function call(accessor, ...)
  if type(accessor) ~= "function" then
    return nil
  end
  return accessor(...)
end

local function table_or_empty(value)
  return type(value) == "table" and value or {}
end

--- The main/sub pair, exactly as catalog.lua reads it: the sub only when the
--- client has named one, and `main` carried through for the merit exception.
local function job_pair(player)
  if type(player) ~= "table" then
    return {}
  end
  local jobs = {}
  if type(player.main_job_id) == "number" then
    jobs[#jobs + 1] = { id = player.main_job_id, level = player.main_job_level or 0, main = true }
  end
  if type(player.sub_job_id) == "number" then
    jobs[#jobs + 1] = { id = player.sub_job_id, level = player.sub_job_level or 0, main = false }
  end
  return jobs
end

--- Can one of these jobs supply this action? A resource with no `levels`
--- table is included - the client already vouched for it by listing it as
--- known, and the job abilities carry no levels at all.
local function available(record, jobs)
  local levels = type(record) == "table" and record.levels or nil
  if type(levels) ~= "table" then
    return true
  end
  for _, job in ipairs(jobs) do
    local required = levels[job.id]
    if type(required) == "number" then
      if required <= (type(job.level) == "number" and job.level or 0) then
        return true
      end
      if required > LEVEL_CAP and job.main then
        return true
      end
    end
  end
  return false
end

local function new(deps)
  deps = deps or {}
  local self = {}

  local function resources()
    return table_or_empty(deps.resources)
  end

  --[[ Where the effect lands. A rung whose resource cannot reach a party
       member is self-only and always says <me>; only the spell and the item
       can ever differ. Kevin chose the current target where it is valid
       (2026-08-29), so a press can sneak someone else - and falls back to
       <me> rather than firing at a mob. ]]
  local function suffix(entry)
    local targets = type(entry) == "table" and tonumber(entry.targets) or nil
    if targets == nil or math.floor(targets / PARTY_BIT) % 2 ~= 1 then
      return " <me>"
    end
    local target = call(deps.get_target)
    if type(target) == "table" and target.in_party == true and target.is_npc ~= true then
      return " <t>"
    end
    return " <me>"
  end

  local function line(prefix, name, entry)
    return "input " .. prefix .. ' "' .. name .. '"' .. suffix(entry)
  end

  --[[ A ninjutsu is only worth firing with its tool in the bag: without one
       the press is spent on the game's refusal. tool_display answers the
       question the slot corners already ask, master tools included on a NIN
       main - so a Shikanofuda alone is enough, exactly as it is for a bound
       ninjutsu slot. ]]
  local function has_tool(spell_id, player)
    local tool = counters.tool_for_spell(spell_id)
    if tool == nil then
      return true
    end
    local main_job = type(player) == "table" and player.main_job or nil
    local display = counters.tool_display(tool, table_or_empty(call(deps.tool_counts)), main_job)
    return display ~= nil and not display.zero
  end

  local function spell_rung(rung, jobs, player)
    local known = table_or_empty(call(deps.get_spells))
    if known[rung.id] ~= true then
      return nil
    end
    local entry = table_or_empty(resources().spells)[rung.id]
    if type(entry) ~= "table" or type(entry.en) ~= "string" then
      return nil
    end
    if not available(entry, jobs) or not has_tool(rung.id, player) then
      return nil
    end
    return line(entry.prefix or "/magic", entry.en, entry)
  end

  local function ability_rung(rung, jobs)
    local listed = table_or_empty(call(deps.get_abilities))
    local found = false
    for _, id in ipairs(table_or_empty(listed.job_abilities)) do
      if id == rung.id then
        found = true
        break
      end
    end
    if not found then
      return nil
    end
    local entry = table_or_empty(resources().job_abilities)[rung.id]
    if type(entry) ~= "table" or type(entry.en) ~= "string" then
      return nil
    end
    if not available(entry, jobs) then
      return nil
    end
    return line(entry.prefix or "/jobability", entry.en, entry)
  end

  --[[ The last rung, and the only one that works on every job. The count is
       a courtesy: where the bag cannot be read at all the press still goes,
       because the game's own "you do not have that item" beats refusing a
       press that might have worked. ]]
  local function item_rung(rung)
    local count = call(deps.item_count, rung.name)
    if type(count) == "number" and count <= 0 then
      return nil
    end
    return line("/item", rung.name, nil)
  end

  --- The command for the first rung this character can use, or nil plus a
  --- hint naming what was asked for.
  function self.plan(which)
    local name = type(which) == "string" and which:lower() or which
    local ladder = LADDERS[name]
    if ladder == nil then
      return nil, "unknown stealth action: " .. tostring(which)
    end
    local player = call(deps.get_player)
    local jobs = job_pair(player)
    for _, rung in ipairs(ladder) do
      local command
      if rung.kind == "spell" then
        command = spell_rung(rung, jobs, player)
      elseif rung.kind == "ability" then
        command = ability_rung(rung, jobs)
      else
        command = item_rung(rung)
      end
      if command ~= nil then
        return command
      end
    end
    return nil, "no way to " .. name .. " right now"
  end

  return self
end

return new
