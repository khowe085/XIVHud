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

--[[ Pure `enchanteditem` resolution: the one item a binding names, searched
     for in the bags and turned into the same plan shapes warp.lua produces,
     so the widget's equip -> wait -> use scheduler serves both without
     knowing which asked.

       { type = "use",   command, name, notes }
       { type = "equip", command, name, id, equip_slot, bag, bag_slot,
                         warmup = true, notes }
       { type = "none",  notes }

     This is warp's ladder with the ladder taken out: one named item instead
     of the ladder's ranked rungs, and the same rules about disabled bags, spent
     charges and a recast still running - including its `<me>` default,
     where a plain `item` binding with no target word sends none at all.
     Gear is worn by the person wearing it, so the default is right here and
     the divergence is deliberate. A NON-enchanted item resolves to a
     plain `/item` use rather than an error - binding a Prism Powder as an
     enchanteditem is a mistake that should still fire the powder.

     No I/O and no clock of its own: the widget injects both. ]]

local enchanted = require("components/crossbar/enchanted")

local EQUIPPED = enchanted.EQUIPPED

local function none(notes)
  return { type = "none", notes = notes or {} }
end

local function new(deps)
  local self = {}

  --- The plan for `enchanteditem <name> [<target>]`. `name` is whatever the
  --- binding was written with; the resource's own spelling is what reaches
  --- the game and the chat notes.
  function self.plan(name, target)
    local player = deps.get_player()
    -- get_player() can return nil (not logged in, zoning) - nothing to do.
    if player == nil then
      return none()
    end
    -- Guarded as warp.lua guards its own: the two siblings agree.
    local resource = deps.find_item ~= nil and deps.find_item(name) or nil
    if resource == nil or type(resource.id) ~= "number" then
      return none({ "No item called " .. tostring(name) .. "." })
    end
    local label = resource.en or name
    -- warp's gate, for warp's reason: a status the client has not filled in
    -- yet is not a blocked status, but anything past engaged is.
    if (player.status or 0) > 1 then
      return none({ "You cannot use items at this time." })
    end

    --[[ EVERY copy, best-ranked first - the one on your hand before a
         spare, a reachable one before a locked bag. The first that yields a
         usable plan is the one the press takes: with a single copy this is
         the copy, and with two Warp Rings it is the charged one rather than
         the spent ring you happen to be wearing. Only when NO copy can be
         used does an explanation come back, and it is the best-ranked
         copy's, since that is the one the player means. ]]
    local list = enchanted.candidates(deps.bags, deps.get_items)[resource.id]
    if list == nil then
      return none({ "You don't have " .. label .. "." })
    end

    local command = 'input /item "' .. label .. '"' .. " <" .. (target or "me") .. ">"

    --- What ONE copy of the item answers: a plan to fire, or the reason it
    --- cannot. The caller walks the copies until one of these is not a
    --- refusal.
    local function plan_for(entry)
      if not entry.enabled then
        local bag = deps.bags[entry.bag]
        local bag_name = bag ~= nil and bag.name or tostring(entry.bag)
        return none({ "You cannot access " .. label .. " from " .. bag_name .. " at this time." })
      end
      local ext = deps.extdata_decode(entry.item)
      if type(ext) ~= "table" then
        -- A decode we cannot read at all. Firing the plain `/item` anyway
        -- would be a no-op the player never sees a reason for, so this says
        -- what happened instead - and it must not arithmetic-throw, since a
        -- keypress runs under the shared handler guard.
        return none({ "Cannot read " .. label .. "." })
      end
      if ext.type ~= "Enchanted Equipment" then
        -- Readable, and simply not enchanted. A CONSUMABLE bound here is a
        -- mistake that should still fire the powder. A piece of ordinary
        -- ARMOUR is not: `/item` at a Rope Belt can only be refused, and the
        -- game's refusal explains nothing, so this does.
        --[[ Wearable is the test, and `slots` PRESENT is what says so - not
             whether this build could read the shape it came in. Reading it
             as "no slots, so a consumable" would fire `/item` at a Rope
             Belt, which is the thing this branch exists to refuse. ]]
        if type(resource.slots) ~= "nil" then
          return none({ label .. " is not enchanted equipment." })
        end
        return { type = "use", name = label, command = command, notes = {} }
      end

      local recast = enchanted.recast_remaining(ext, deps.now())
      if recast == nil then
        --[[ Out of charges. NOT MyHome's bare "<name>.", which the ladder
             keeps: there it is one line among a rung list, beside "Warp
             Cudgel: 30 sec recast.", and reads as an entry. Standalone it
             is the entire answer to a press, and a chat line saying only
             "crossbar: Vocation Ring." is indistinguishable from a stray
             echo. ]]
        return none({ label .. ": no charges left." })
      end
      if recast > 0 then
        return none({ label .. ": " .. recast .. " sec recast." })
      end
      local slots = enchanted.equip_slots(resource)
      local equip_slot = slots[1]

      --[[ Already worn - but an enchantment warms up whether or not the equip
           was ours, so "worn" is not "ready". Firing here sends an `/item`
           the game refuses seconds early and tells the player nothing, and
           equipping the ring by hand and then pressing the slot is the
           ordinary flow rather than an exotic one.

           The readiness test is deliberately not `ext.usable` alone: a
           warmup already long past is proof enough, and leaning on the flag
           by itself would turn a working press into a wait if it ever means
           something narrower than we assume. ]]
      if entry.item.status == EQUIPPED then
        -- Asked of `step`, never re-decided here: it is the same question the
        -- scheduler will go on asking every second, and two readings of it
        -- would arm waits that never fire. `true` is the worn flag - the
        -- branch is reached only on an item the client says is equipped, so
        -- its activation_time is this equip's rather than some old one's.
        local give_up = enchanted.give_up_for(label)
        local step = enchanted.step(ext, deps.now(), true, give_up)
        if step == "use" then
          return { type = "use", name = label, command = command, notes = {} }
        end
        if step == "abandon" then
          -- Arming a wait here would send `gs disable` and abandon on the very
          -- next poll, re-enabling again: the same answer, with the player's
          -- gear swapping stopped for a frame on the way to it.
          return none({ label .. " needs more than " .. give_up .. " sec." })
        end
        if step == nil then
          --[[ An activation_time we cannot read, on a piece already worn.
               FIRE it, exactly as the ladder does: nothing is armed here,
               so there is no wait to flicker, and refusing would lose a use
               that works today over a reading we do not have. The worst
               case is one command the game refuses.

               The not-worn path below refuses the same shape, and that is
               not a contradiction: arming there really does hold a GearSwap
               slot for a wait the first poll would abandon. ]]
          return { type = "use", name = label, command = command, notes = {} }
        end
        if equip_slot == nil then
          return none({ "Cannot tell which slot " .. label .. " is worn in." })
        end
        --[[ The scheduler's wait, without the equip: re-equipping what is
             already on risks restarting the very warmup we are waiting out.
             The GearSwap hold still goes on, because a running GearSwap can
             take the ring off mid-wait whoever put it there - and it covers
             EVERY slot the piece could be in, because which one it is
             actually on is not knowable from here. A ring is a coin flip,
             and the losing side is a wait that dies at the deadline. ]]
        return {
          type = "equip",
          equipped = true,
          id = resource.id,
          name = label,
          equip_slot = equip_slot,
          hold_slots = slots,
          give_up = give_up,
          -- The token the press aimed at, for the widget to pin: this
          -- command is sent when the enchantment goes live, which can be
          -- most of a minute later.
          target = target,
          bag = entry.bag,
          bag_slot = entry.item.slot,
          command = command,
          warmup = true,
          notes = {},
        }
      end

      if equip_slot == nil then
        -- Nothing to hand set_equip. An equip that silently no-ops would
        -- leave the scheduler waiting out a warmup that never starts, so
        -- this refuses rather than guesses a slot. "goes in" rather than "is
        -- worn in": this branch is reached for a piece that is NOT worn.
        return none({ "Cannot tell which slot " .. label .. " goes in." })
      end
      if type(ext.activation_time) ~= "number" then
        --[[ A warmup the poll cannot read is one it abandons immediately,
             so arming would `gs disable`, equip, and re-enable a frame
             later for nothing.

             NOT the worn branch's whole guard: that one also refuses a
             warmup past the give-up bound, which this branch does not test
             because the equip is about to rewrite `activation_time`
             anyway - a stale one from some previous equip says nothing
             about the wait we are arming. ]]
        return none({ "Cannot read " .. label .. "." })
      end
      return {
        type = "equip",
        id = resource.id,
        name = label,
        equip_slot = equip_slot,
        -- We put it there, so the hold needs one slot and no guessing.
        hold_slots = { equip_slot },
        give_up = enchanted.give_up_for(label),
        target = target,
        bag = entry.bag,
        bag_slot = entry.item.slot,
        command = command,
        -- "Using this entails a wait", which is what the travel delay reads.
        warmup = true,
        notes = {},
      }
    end

    local first_refusal = nil
    for _, entry in ipairs(list) do
      local plan = plan_for(entry)
      if plan.type ~= "none" then
        return plan
      end
      -- No copy worked: the FIRST one's reason is the one to give, since
      -- the ranking put the copy the player means at the head. Kept from
      -- that pass rather than recomputed, so the common single-copy case
      -- decodes its extdata once.
      first_refusal = first_refusal or plan
    end
    -- `candidates` never yields an empty list, but the invariant lives in
    -- another module and this runs on the keypress path under the shared
    -- guard, where a nil plan would be indexed by run_item_plan.
    return first_refusal or none()
  end

  return self
end

return new
