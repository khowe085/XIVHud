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
       { type = "equip", command, name, id, equip_slot, hold_slots, bag,
                         bag_slot, warmup, give_up, equipped, notes }
                                                -- gear to equip and wait for,
                                                -- or (equipped) already on and
                                                -- only waiting
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
local EQUIPPED = enchanted.EQUIPPED

--[[ The priority ladder, in the order it must be walked.

     A rung carries EITHER an `id` (MyHome's three, whose ids came across
     with the port and are attested by it) or nothing, in which case its id
     is resolved from the resources by name at plan time. Naming rather than
     numbering is how a rung gets added without writing down an id from
     memory - the class of unverified constant this repo keeps being bitten
     by - at the cost of the rung simply not existing when the resources are
     absent.

     A rung carries no wait bound of its own: how long an enchantment takes
     to come up is a fact about the ITEM, so `enchanted.give_up_for` answers
     it and a slot bound `enchanteditem "<the same ring>"` waits exactly as
     long as the rung does. ]]
local LADDER = {
  { id = 28540, name = "Warp Ring", equip_slot = 13 },
  { id = 17040, name = "Warp Cudgel", equip_slot = 0 },
  { id = 4181, name = "Instant Warp" },
  --[[ The item of last resort (Kevin, 2026-08-20). Its id is not written
       here on purpose, and neither is its warmup bound - that lives with
       the item in enchanted.lua, so a slot bound `enchanteditem "Tavnazian
       Ring"` waits exactly as long as this rung does. ]]
  { name = "Tavnazian Ring" },
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
    local found = enchanted.collect(deps.bags, deps.get_items)
    local notes = {}
    for _, rung in ipairs(LADDER) do
      --[[ Every rung asks the resources, not only the named ones. A named
           rung NEEDS the answer - it has no id otherwise, and is passed
           over in silence when the resources cannot name it, since the
           player has no way to act on "an item I cannot name is absent".

           A numbered rung wants it for the slots: a ring already on your
           hand could be on either ring slot, and the rung's own
           `equip_slot` names where it would PUT the piece, not where the
           piece already is. Holding the wrong one leaves GearSwap free to
           swap the ring off mid-wait. ]]
      local resource = deps.find_item ~= nil and deps.find_item(rung.name) or nil
      local rung_id = rung.id or (type(resource) == "table" and resource.id or nil)
      local entry = rung_id ~= nil and found[rung_id] or nil
      --[[ The resource's own spelling where the resources answered, the
           ladder's otherwise: `find_item` folds case, so a name matching
           loosely would otherwise ship the ladder's spelling to `/item`.
           enchanteditem states the same rule. Declared out here so every
           note below reads the same way, whichever branch writes it. ]]
      local label = type(resource) == "table" and resource.en or rung.name
      if entry and entry.enabled then
        local ext = deps.extdata_decode(entry.item)
        local recast = enchanted.recast_remaining(ext, now)
        local command = 'input /item "' .. label .. '" <me>'
        if recast == 0 or ext.type == "General" then
          -- A rung that must be equipped first makes the widget wait out the
          -- enchantment with the GearSwap slot held disabled. The travel
          -- delay reads `warmup` to decide whether a countdown would only be
          -- adding a second wait to that one, which is why the flag says
          -- "using this entails a wait" rather than "this is enchanted
          -- equipment": an already-equipped, charged ring is enchanted and
          -- yet fires the moment it is asked.
          local worn = ext.type ~= "Enchanted Equipment" or entry.item.status == EQUIPPED
          if not worn then
            --[[ NOT worn, so this rung can only go by being equipped
                 first. A numbered rung names its slot; a resolved one
                 reads it off the resource, lowest first, exactly as
                 enchanteditem does.

                 Where the resource will not answer - a `slots` shape this
                 build cannot read, still an open in-client question - the
                 rung is walked past. Arming it would send no `gs disable`
                 at all and drop a `set_equip` with a nil slot; and falling
                 through to the use branch below would fire `/item` at a
                 ring that is in the bag rather than on a finger, which the
                 game refuses and which `warp all` would broadcast on. ]]
            local equip_slot = rung.equip_slot or enchanted.equip_slots(resource)[1]
            if equip_slot ~= nil then
              return {
                type = "equip",
                id = rung_id,
                name = label,
                equip_slot = equip_slot,
                bag = entry.bag,
                bag_slot = entry.item.slot,
                command = command,
                warmup = true,
                give_up = enchanted.give_up_for(rung.name),
                notes = notes,
              }
            end
            notes[#notes + 1] = "Cannot tell which slot " .. rung.name .. " goes in."
          else
            --[[ CB12. Worn is not ready: an enchantment warms up whether
                 or not the equip was ours, so a ring just put on by hand
                 fires an `/item` the game refuses seconds early. `step` is
                 the one reading of that question, asked here exactly as
                 enchanteditem asks it, with `worn` true because this
                 branch is reached only on a piece the client says is
                 equipped - or on a plain consumable, which has no warmup
                 to read and answers nil below.

                 What happens when it is NOT ready depends on why. A rung
                 on RECAST is walked past - the cudgel below it may be
                 ready right now. A rung merely still WARMING UP is waited
                 out just below, because walking past that one left the
                 press doing nothing at all when no rung sat beneath it.
                 Only a warmup longer than the item's own bound is walked
                 past, there being nothing worth waiting for.

                 A decode with no activation_time at all cannot be judged,
                 and refusing there would lose a warp that works today over
                 a reading we do not have, so that case degrades to the
                 behaviour that shipped. ]]
            local step = ext.type == "Enchanted Equipment"
                and enchanted.step(ext, now, true, enchanted.give_up_for(rung.name))
              or nil
            if step == nil or step == "use" then
              return { type = "use", name = label, command = command, notes = notes }
            end
            --[[ Still warming, and inside the bound: wait it out exactly as an
                 `enchanteditem` binding on this ring would - no re-equip
                 (it is already on), the GearSwap hold over its slot, the
                 scheduler polling. Walking past instead would leave the
                 press doing nothing at all when nothing sits below it,
                 which is what equipping a ring by hand and pressing warp a
                 moment later would meet. ]]
            local worn_slots = enchanted.equip_slots(resource)
            local equip_slot = rung.equip_slot or worn_slots[1]
            if step == "wait" and equip_slot ~= nil then
              return {
                type = "equip",
                equipped = true,
                id = rung_id,
                name = label,
                equip_slot = equip_slot,
                --[[ EVERY slot the piece fits, not the one the rung would
                     have equipped into: the piece is already on, and which
                     slot it is on is not knowable from here. A ring is a
                     coin flip, and the losing side is GearSwap swapping it
                     off mid-wait and the wait dying at its deadline.
                     `{ equip_slot }` is the fallback for a resource that
                     named no slots at all. ]]
                hold_slots = #worn_slots > 0 and worn_slots or { equip_slot },
                bag = entry.bag,
                bag_slot = entry.item.slot,
                command = command,
                warmup = true,
                give_up = enchanted.give_up_for(rung.name),
                notes = notes,
              }
            end
            --[[ Warming for longer than the wait allows, or with no slot to
                 hold. Said in its own words rather than reusing MyHome's
                 bare "<name>." below, which means OUT OF CHARGES: a player
                 who cannot tell those two apart cannot act on either. ]]
            notes[#notes + 1] = label .. (step == "abandon" and ": warm-up too long." or ": still warming up.")
          end
        else
          -- On recast, or out of charges (recast nil): note it and walk on.
          -- The bare "<name>." for the no-charges case is MyHome's own log
          -- wording, kept deliberately rather than inventing new text.
          notes[#notes + 1] = recast and (rung.name .. ": " .. recast .. " sec recast.") or (rung.name .. ".")
        end
      elseif entry then
        local bag_name = deps.bags[entry.bag].name
        notes[#notes + 1] = "You cannot access " .. label .. " from " .. bag_name .. " at this time."
      elseif rung_id ~= nil then
        notes[#notes + 1] = "You don't have " .. label .. "."
      end
    end
    return { type = "none", notes = notes }
  end

  return self
end

return new
