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

--[[ The binder's catalog: everything the player can bind right now, grouped
     for the picker. Pure - the client tables and resources arrive injected,
     so the level rules below are testable without a client.

     The level filter is upstream's SHAPE with its defect fixed (plan defect
     10). Upstream gates a spell on `levels[job] <= job_level`, but a merit
     spell encodes its requirement as a sentinel far above the level cap
     (Refresh III at 1200), so `1200 <= 99` is false and the spell can never
     be bound - the defect that this component exists in part to avoid. Ours:
     include it when the client says it is KNOWN, the job COULD know it, and
     either the level is met or the requirement is above the cap AND the job
     in question is the MAIN one (merits and job points apply to the main job
     alone - the same main-only rule the stratagem gift follows). ]]

local openers = require("components/crossbar/openers")

local LEVEL_CAP = 99
local INVENTORY_BAG = 0

-- Category ranks: the magic schools first (alphabetically among themselves),
-- then the client's own lists, then what needs no client at all.
local RANK = {
  Trusts = 2,
  ["Job Abilities"] = 3,
  ["Weapon Skills"] = 4,
  Items = 5,
  Mounts = 6,
  Open = 7,
  General = 8,
}
local SCHOOL_RANK = 1

--[[ The built-ins, in the order a picker reads best: the state-aware toggle
     first (the catalog's "Attack" IS `draw`, not a bare /attack line), then
     the two one-button conveniences, then the bare ranged attack.

     A CURATED LIST, not a mirror of actions.lua's BUILTINS: it carries
     `ra`, which is a game type rather than a built-in, and leaves out
     `open`, whose entries are listed one per opener below. A new built-in
     does NOT appear here on its own - putting it in the picker is a
     decision, and this is where it gets made. ]]
local BUILTIN_ENTRIES = {
  { label = "Attack", type = "draw" },
  { label = "Mount Roulette", type = "mr" },
  { label = "Warp", type = "warp" },
  { label = "Ranged Attack", type = "ra" },
}

local function call(accessor, ...)
  if type(accessor) ~= "function" then
    return nil
  end
  return accessor(...)
end

local function table_or_empty(value)
  return type(value) == "table" and value or {}
end

-- "WhiteMagic" -> "White Magic": the display form, never the raw resource
-- type (which the icon pack's directory would miss too).
local function display_category(resource_type)
  if type(resource_type) ~= "string" or resource_type == "" then
    return nil
  end
  if resource_type == "Trust" then
    return "Trusts"
  end
  return (resource_type:gsub("(%l)(%u)", "%1 %2"))
end

local function new(deps)
  deps = deps or {}
  local self = {}

  -- The jobs a merged listing draws from: the main job, and the sub only
  -- when the client has named one. `main` decides the merit exception.
  local function job_pair()
    local player = call(deps.get_player)
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

  --[[ Can one of these jobs supply this action? A resource with no `levels`
       table at all is included: the client already vouched for it by
       listing it as known, and degraded resource data must not empty the
       catalog. ]]
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
        -- Above the cap means merits or job points, which only the main job
        -- can have spent; the strict test stands on the sub half.
        if required > LEVEL_CAP and job.main then
          return true
        end
      end
    end
    return false
  end

  local function add(groups, category, entry)
    local group = groups[category]
    if group == nil then
      group = { name = category, entries = {} }
      groups[category] = group
    end
    group.entries[#group.entries + 1] = entry
  end

  local function spells(groups, jobs)
    local known = call(deps.get_spells)
    if type(known) ~= "table" then
      return
    end
    local resource = table_or_empty(table_or_empty(deps.resources).spells)
    for id, is_known in pairs(known) do
      local spell = is_known and resource[id] or nil
      if type(spell) == "table" and type(spell.en) == "string" and available(spell, jobs) then
        -- Trusts included: `/trust` is not a command word, so upstream maps
        -- the category to `ma` and so do we - only the grouping differs.
        add(groups, display_category(spell.type) or "Magic", {
          label = spell.en,
          record = { type = "ma", action = spell.en },
        })
      end
    end
  end

  local function abilities(groups, jobs)
    local listed = table_or_empty(call(deps.get_abilities))
    local resources = table_or_empty(deps.resources)
    local job_abilities = table_or_empty(resources.job_abilities)
    for _, id in ipairs(table_or_empty(listed.job_abilities)) do
      local ability = job_abilities[id]
      if type(ability) == "table" and type(ability.en) == "string" and available(ability, jobs) then
        add(groups, "Job Abilities", { label = ability.en, record = { type = "ja", action = ability.en } })
      end
    end
    -- Weaponskills carry no per-job levels at all, so the client's own list
    -- is the whole answer and there is nothing left to filter on.
    local weapon_skills = table_or_empty(resources.weapon_skills)
    for _, id in ipairs(table_or_empty(listed.weapon_skills)) do
      local ws = weapon_skills[id]
      if type(ws) == "table" and type(ws.en) == "string" then
        add(groups, "Weapon Skills", { label = ws.en, record = { type = "ws", action = ws.en } })
      end
    end
  end

  local function items(groups)
    local bag = call(deps.get_items, INVENTORY_BAG)
    if type(bag) ~= "table" then
      return
    end
    local resource = table_or_empty(table_or_empty(deps.resources).items)
    local seen = {}
    for _, held in ipairs(bag) do
      local item = type(held) == "table" and resource[held.id] or nil
      -- Usable only: a bag holds equipment and crafting materials too, and
      -- `/item` on either is a binding that can never fire.
      if type(item) == "table" and item.category == "Usable" and type(item.en) == "string" and not seen[item.en] then
        seen[item.en] = true
        add(groups, "Items", { label = item.en, record = { type = "item", action = item.en } })
      end
    end
  end

  --[[ The owned list is the COMMAND form - lower case, because that is
       what `/mount` takes - so a label built off it reads "chocobo". The
       display casing rides along in the record's own `display` field, which
       every label path prefers after the alias.

       DELIBERATELY NOT `alias`: that field is the player's, written by
       `//hud crossbar alias` and cleared by the same verb with the name
       omitted. Putting the game's casing there would mean the binder and
       the CLI produced differently-labelled bindings for the same mount,
       and clearing an alias would lose the casing for good. Two owners, two
       fields, alias first. ]]
  local function mounts(groups)
    for _, name in ipairs(table_or_empty(call(deps.owned_mounts))) do
      if type(name) == "string" then
        local shown = type(deps.mount_display) == "function" and deps.mount_display(name) or nil
        local record = { type = "mount", action = name }
        if type(shown) == "string" and shown ~= name then
          record.display = shown
        end
        add(groups, "Mounts", { label = record.display or name, record = record })
      end
    end
  end

  -- The built-ins need no client at all, which is what keeps the catalog
  -- useful before the resources library has answered anything.
  local function builtins(groups)
    for _, entry in ipairs(BUILTIN_ENTRIES) do
      add(groups, "General", { label = entry.label, record = { type = entry.type } })
    end
    for name in pairs(openers) do
      add(groups, "Open", { label = name, record = { type = "open", action = name } })
    end
  end

  --- Every bindable action right now, grouped and ordered for the picker.
  --- Rebuilt on demand (the binder does it when edit mode opens): the
  --- inventory, the known spells and the job pair all move in play.
  --- `ct` and `ex` are deliberately absent - they need text entry, which
  --- the mouse binder has no way to take.
  function self.build()
    local jobs = job_pair()
    local groups = {}
    spells(groups, jobs)
    abilities(groups, jobs)
    items(groups)
    mounts(groups)
    builtins(groups)

    local ordered = {}
    for _, group in pairs(groups) do
      -- Stable inside a category: pairs() over the client's tables would
      -- reshuffle the picker between openings for no reason.
      table.sort(group.entries, function(a, b)
        return a.label < b.label
      end)
      ordered[#ordered + 1] = group
    end
    table.sort(ordered, function(a, b)
      local rank_a, rank_b = RANK[a.name] or SCHOOL_RANK, RANK[b.name] or SCHOOL_RANK
      if rank_a ~= rank_b then
        return rank_a < rank_b
      end
      return a.name < b.name
    end)
    return ordered
  end

  return self
end

return new
