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

     The order is FIXED and the same on every job - the white magic spell,
     then Spectral Jig, then the ninjutsu (its Ni ahead of its Ichi), then
     the item - rather than preferring whatever the main job happens to
     offer. The same press then does the same thing whoever presses it, and
     the item is only ever reached when nothing else is.

     It is ordered by WHAT A RUNG SPENDS (Kevin, 2026-09-06, replacing the
     2026-08-29 order that put the ninjutsu at the front and the spell
     last): the spell and the jig consume nothing, and both ninjutsu spend
     a tool, which is why the jig sits above them and the two consumables
     are last of all.

     Every rung is gated on what the CLIENT says, never on hardcoded job
     levels: `get_spells`/`get_abilities` answer what this character knows,
     and the resource's own `levels` table answers whether the current
     main/sub pair may use it - the same two questions catalog.lua asks of
     every other action, which is why a subjob change needs no notification
     here. A ninjutsu rung also wants its tool in the bag, since the press
     would otherwise be spent on a message from the game - and every spell
     rung, ninjutsu included, is passed by under silence or mute
     (2026-10-09), so the press reaches the jig or the item the game would
     accept instead. MP is deliberately NOT checked (Kevin): Penury and
     Light Arts cut the cost, and a gate on the base cost would spend an
     item where the spell would have gone.

     `reraise` is a third ladder on the same machinery (Kevin, 2026-10-09):
     the highest tier of the spell, then the four consumables, then the
     enchanted gear. It is refused outright while Reraise is already on -
     the buff is one id for every tier, so nothing can tell a weaker one
     from a stronger one, and the items and gear charges are not worth
     spending on a guess.

     Nothing here executes: plan() answers a command string for the widget
     to send, or - for a gear rung - the enchanteditem plan for the widget's
     equip -> wait -> use scheduler, so the ladder stays testable without a
     client. ]]

local counters = require("lib/actionbar/counters")

-- Resource ids, verified against Windower's own resource data rather than
-- remembered: Sneak/Invisible are White Magic, the two ninjutsu are spells
-- as well (the client lists them in get_spells), and the jig is an ability.
local SNEAK, INVISIBLE = 137, 136
local MONOMI_ICHI, TONKO_ICHI, TONKO_NI = 318, 353, 354
local SPECTRAL_JIG = 196
local RERAISE, RERAISE_II, RERAISE_III, RERAISE_IV = 135, 141, 142, 848
-- Buff ids, off lib/buff_order: Reraise is one buff whatever the tier.
local RERAISE_BUFF, ADDENDUM_WHITE, ENLIGHTENMENT = 113, 401, 416
-- What stops every spell, ninjutsu included.
local SILENCE, MUTE = 6, 29

--[[ Spell, jig, ninjutsu, item - and for reraise, gear, which
     enchanteditem resolves by name. `spell` and `ability` are resource
     lookups; `item` is a name, because `/item` takes the name and the id
     only ever matters for the bag count - which is resolved by name too,
     the way the temporary bag and the resting status already are. Monomi
     has no Ni in the game (id 319 is Aisha: Ichi), which is why only the
     invisible ladder carries two ninjutsu rungs. ]]
local LADDERS = {
  sneak = {
    { kind = "spell", id = SNEAK },
    { kind = "ability", id = SPECTRAL_JIG },
    { kind = "spell", id = MONOMI_ICHI },
    { kind = "item", name = "Silent Oil" },
  },
  invisible = {
    { kind = "spell", id = INVISIBLE },
    { kind = "ability", id = SPECTRAL_JIG },
    { kind = "spell", id = TONKO_NI },
    { kind = "spell", id = TONKO_ICHI },
    { kind = "item", name = "Prism Powder" },
  },
  --[[ `Instant Reraise` is the consumable scroll (4182); the item called
       `Reraise` (4743) is the scroll that TEACHES the spell. The ring heads
       the gear because it recharges, where the others spend one of ten
       charges (Kevin, 2026-10-09). ]]
  reraise = {
    { kind = "spell", id = RERAISE_IV },
    { kind = "spell", id = RERAISE_III },
    { kind = "spell", id = RERAISE_II },
    { kind = "spell", id = RERAISE },
    { kind = "item", name = "Super Reraiser" },
    { kind = "item", name = "Hi-Reraiser" },
    { kind = "item", name = "Reraiser" },
    { kind = "item", name = "Instant Reraise" },
    { kind = "gear", name = "Reraise Ring" },
    { kind = "gear", name = "Reraise Earring" },
    { kind = "gear", name = "Reraise Hairpin" },
    { kind = "gear", name = "Reraise Gorget" },
  },
}

-- What a ladder refuses outright, before any rung is walked.
local REFUSED_UNDER = {
  reraise = { buff = RERAISE_BUFF, hint = "Reraise is already active" },
}

-- FFXI's own cap, the same constant catalog.lua gates the merit exception
-- on: a requirement above it is a merit or job point, which only a main job
-- can have spent.
local LEVEL_CAP = 99

-- The `targets` bitfield's Party bit. A rung without it is self-only -
-- both ninjutsu and the jig are - and can never carry <t>.
local PARTY_BIT = 4

--[[ A spell's `requirements` bit that SCH must open with an Addendum. It
     sits on exactly the Addendum spells - the -na family, Erase, Raise II
     and III, Reraise I to III, and the tier IV/V nukes, Sleep, Break and
     Dispel on the black side - and binds SCH alone: a WHM casts Reraise
     without one. Enlightenment opens both addenda at once. Only the white
     side is mapped, no ladder casting black magic. ]]
local SCH = 20
local ADDENDUM_BIT = 4
local ADDENDUM_FOR = { WhiteMagic = ADDENDUM_WHITE }

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

local function has_buff(player, id)
  local buffs = type(player) == "table" and player.buffs or nil
  if type(buffs) ~= "table" then
    return false
  end
  for _, buff in ipairs(buffs) do
    if buff == id then
      return true
    end
  end
  return false
end

--- The Addendum buff a SCH must have up to cast this spell, or nil.
local function addendum_for(record)
  local requirements = tonumber(record.requirements)
  if requirements == nil or math.floor(requirements / ADDENDUM_BIT) % 2 ~= 1 then
    return nil
  end
  return ADDENDUM_FOR[record.type]
end

--[[ Can the main job wear this piece? Gear is the main job's alone, and
     enchanteditem asks no such question - a gorget a THF cannot put on
     would otherwise hold the neck slot through a warm-up that never
     starts. `jobs` is read as a bitfield (the raw data) or a set (what the
     resources library may hand over) - a table is a set only when it holds
     a `true`, since a list `{ 1, 5 }` read as one would refuse the WAR it
     names. Any other shape, or no level, is a fact that cannot be read and
     allows the piece. ]]
local function is_set(value)
  for _, member in pairs(value) do
    if member == true then
      return true
    end
  end
  return false
end

local function wearable(item, player)
  if type(item) ~= "table" or type(player) ~= "table" then
    return true
  end
  local job = player.main_job_id
  if type(job) == "number" then
    if type(item.jobs) == "number" and math.floor(item.jobs / 2 ^ job) % 2 ~= 1 then
      return false
    end
    if type(item.jobs) == "table" and is_set(item.jobs) and item.jobs[job] ~= true then
      return false
    end
  end
  local level = player.main_job_level
  if type(item.level) == "number" and type(level) == "number" and item.level > level then
    return false
  end
  return true
end

--- Can one of these jobs supply this action? A resource with no `levels`
--- table is included - the client already vouched for it by listing it as
--- known, and the job abilities carry no levels at all.
local function available(record, jobs, player)
  local levels = type(record) == "table" and record.levels or nil
  if type(levels) ~= "table" then
    return true
  end
  local addendum = addendum_for(record)
  for _, job in ipairs(jobs) do
    local required = levels[job.id]
    local opened = job.id ~= SCH or addendum == nil or has_buff(player, addendum) or has_buff(player, ENLIGHTENMENT)
    local level = type(job.level) == "number" and job.level or 0
    if type(required) == "number" and opened then
      if required <= level then
        return true
      end
      --[[ A merit or job-point gift, which a main job spends - and only at
           the cap: a gift is off while synced below it. catalog.lua offers
           it regardless, a binding being for later; this ladder fires now. ]]
      if required > LEVEL_CAP and job.main and level >= LEVEL_CAP then
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
    if not available(entry, jobs, player) or not has_tool(rung.id, player) then
      return nil
    end
    if has_buff(player, SILENCE) or has_buff(player, MUTE) then
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

  --[[ The consumable, which works on every job. The count is a courtesy:
       where the bag cannot be read at all the press still goes, because the
       game's own "you do not have that item" beats refusing a press that
       might have worked. ]]
  local function item_rung(rung)
    local count = call(deps.item_count, rung.name)
    if type(count) == "number" and count <= 0 then
      return nil
    end
    return line("/item", rung.name, nil)
  end

  --[[ Enchanted gear is enchanteditem's to judge - which bag, which copy,
       the charges, the recast, the warm-up - so a gear rung is that plan
       verbatim, and passed over when it answers "none". ]]
  local function gear_rung(rung, player)
    if not wearable(call(deps.find_item, rung.name), player) then
      return nil
    end
    local plan = call(deps.gear_plan, rung.name)
    if type(plan) ~= "table" or plan.type == "none" then
      return nil
    end
    return plan
  end

  --- The command (or, for a gear rung, the enchanteditem plan) for the
  --- first rung this character can use, or nil plus a hint naming what was
  --- asked for.
  function self.plan(which)
    local name = type(which) == "string" and which:lower() or which
    local ladder = LADDERS[name]
    if ladder == nil then
      return nil, "unknown stealth action: " .. tostring(which)
    end
    local player = call(deps.get_player)
    local refused = REFUSED_UNDER[name]
    if refused ~= nil and has_buff(player, refused.buff) then
      return nil, refused.hint
    end
    local jobs = job_pair(player)
    for _, rung in ipairs(ladder) do
      local command
      if rung.kind == "spell" then
        command = spell_rung(rung, jobs, player)
      elseif rung.kind == "ability" then
        command = ability_rung(rung, jobs)
      elseif rung.kind == "gear" then
        command = gear_rung(rung, player)
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
