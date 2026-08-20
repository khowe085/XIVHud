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

Ported from the MyHome addon (Icydeath/ffxi-addons), whose notice BSD
clause 1 requires retained in derived source:

Copyright © 2018, from20020516
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
    * Neither the name of MyHome nor the
    names of its contributors may be used to endorse or promote products
    derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL from20020516 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ Pure auto-warp: MyHome's priority ladder resolved into a plan, no I/O.
     plan() answers one of:

       { type = "spell", command }              -- cast Warp / Warp II
       { type = "use",   command, name, notes } -- /item something already usable
       { type = "equip", command, name, equip_slot, bag, bag_slot, notes }
                                                -- enchanted gear to equip first
       { type = "none",  notes }                -- nothing available; notes are
                                                -- the chat hints, never a crash

     The equip -> wait -> use scheduling (GearSwap-safe: gs disable, equip,
     use, gs enable on every exit) belongs to the widget; this module only
     decides which rung fires. Deviations from MyHome, all deliberate: the
     ladder walks with ipairs (upstream's `pairs` does not actually guarantee
     its documented Ring -> Cudgel -> Instant order), English names only (JP
     literals are non-ASCII, forbidden in src/), and no polling -- the wait
     maths live in enchanted.lua for the widget's scheduler. ]]

local enchanted = require("components/crossbar/enchanted")

local BLM = 4
local WARP_SPELL = 261
local WARP2_SPELL = 262
-- item.status for a piece of equipment currently equipped.
local EQUIPPED = 5

-- The priority ladder, in the order it must be walked.
local LADDER = {
  { id = 28540, name = "Warp Ring", equip_slot = 13 },
  { id = 17040, name = "Warp Cudgel", equip_slot = 0 },
  { id = 4181, name = "Instant Warp" },
}

local function new(deps)
  local self = {}

  local function spell_plan(player)
    if player.main_job_id ~= BLM and player.sub_job_id ~= BLM then
      return nil
    end
    -- The client fills the player in field by field: no vitals yet means no
    -- MP to spend, so the spell rungs simply do not apply.
    local mp = player.vitals and player.vitals.mp
    if mp == nil then
      return nil
    end
    local spells = deps.get_spells() or {}
    if spells[WARP_SPELL] and mp >= 100 then
      return { type = "spell", command = 'input /ma "Warp" <me>' }
    end
    if spells[WARP2_SPELL] and mp >= 150 then
      return { type = "spell", command = 'input /ma "Warp II" <me>' }
    end
  end

  -- Every item in every equippable bag, by item id. Bags walk in id order so
  -- a duplicate resolves the same way every call (upstream's pairs walk left
  -- that to chance too).
  local function collect_items()
    local bag_ids = {}
    for id, bag in pairs(deps.bags) do
      if bag.equippable then
        bag_ids[#bag_ids + 1] = id
      end
    end
    table.sort(bag_ids)

    local found = {}
    for _, bag_id in ipairs(bag_ids) do
      local bag = deps.get_items(bag_id) or {}
      for _, item in ipairs(bag) do
        if item.id and item.id > 0 then
          -- An entry from an enabled bag always beats one from a disabled
          -- bag, whatever the walk order -- a duplicate in a disabled
          -- wardrobe must not shadow the usable copy.
          local existing = found[item.id]
          if existing == nil or (not existing.enabled and bag.enabled) then
            found[item.id] = { item = item, bag = bag_id, enabled = bag.enabled and true or false }
          end
        end
      end
    end
    return found
  end

  function self.plan()
    local player = deps.get_player()
    -- get_player() can return nil (not logged in, zoning) -- nothing to do.
    if player == nil then
      return { type = "none", notes = {} }
    end
    local cast = spell_plan(player)
    if cast then
      return cast
    end

    -- Items only from here; the spell rungs are not status-gated (MyHome's
    -- own shape -- only search_item checks). A status the client has not
    -- filled in yet is not a blocked status.
    if (player.status or 0) > 1 then
      return { type = "none", notes = { "You cannot use items at this time." } }
    end

    local now = deps.now()
    local found = collect_items()
    local notes = {}
    for _, rung in ipairs(LADDER) do
      local entry = found[rung.id]
      if entry and entry.enabled then
        local ext = deps.extdata_decode(entry.item)
        local recast = enchanted.recast_remaining(ext, now)
        local command = 'input /item "' .. rung.name .. '" <me>'
        if recast == 0 or ext.type == "General" then
          -- A rung that must be equipped first makes the widget wait out the
          -- enchantment with the GearSwap slot held disabled. The travel
          -- delay reads `warmup` to decide whether a countdown would only be
          -- adding a second wait to that one, which is why the flag says
          -- "using this entails a wait" rather than "this is enchanted
          -- equipment": an already-equipped, charged ring is enchanted and
          -- yet fires the moment it is asked.
          if ext.type == "Enchanted Equipment" and entry.item.status ~= EQUIPPED then
            return {
              type = "equip",
              id = rung.id,
              name = rung.name,
              equip_slot = rung.equip_slot,
              bag = entry.bag,
              bag_slot = entry.item.slot,
              command = command,
              warmup = true,
              notes = notes,
            }
          end
          return { type = "use", name = rung.name, command = command, notes = notes }
        end
        -- On recast, or out of charges (recast nil): note it and walk on.
        -- The bare "<name>." for the no-charges case is MyHome's own log
        -- wording, kept deliberately rather than inventing new text.
        notes[#notes + 1] = recast and (rung.name .. ": " .. recast .. " sec recast.") or (rung.name .. ".")
      elseif entry then
        local bag_name = deps.bags[entry.bag].name
        notes[#notes + 1] = "You cannot access " .. rung.name .. " from " .. bag_name .. " at this time."
      else
        notes[#notes + 1] = "You don't have " .. rung.name .. "."
      end
    end
    return { type = "none", notes = notes }
  end

  return self
end

return new
