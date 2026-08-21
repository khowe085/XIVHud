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

--[[ Pure enchanted-item maths: charges, warmup and recast read from a decoded
     extdata table, with the clock injected as an argument. The equip -> wait
     -> use scheduling itself lives with the widget; this module only
     answers what the numbers mean.

     extdata's timestamps sit 18000 seconds off os.time -- the `+ 18000 - now`
     shape is MyHome's and the extdata library's own usage, kept as a named
     constant here.

     Two callers: the warp ladder, and the `enchanteditem` bind type over
     it. `step` is the one reading of "is this enchantment live" shared by
     the plans and the scheduler: where a plan has to decide between firing
     now and arming a wait, it asks here rather than deciding for itself,
     because a plan and a scheduler that disagreed would arm waits that
     never fire.

     That is the WORN case in both callers. Neither asks on the not-worn
     path, and neither should: the equip is about to rewrite
     `activation_time`, so the value sitting there says nothing about the
     wait being armed - which is the whole of the `worn` argument below.

     The ladder asks it too, as of CB12 (2026-08-20) - it used to treat a
     worn, off-recast ring as ready with no warmup test at all, so a Warp
     Ring pressed straight after equipping it by hand fired an `/item` the
     game refuses. Both callers now put the same question here, which is the
     point of the function. ]]

local enchanted = {}

-- extdata timestamps are offset this far from os.time.
local EXTDATA_OFFSET = 18000

-- An item needing more than this many seconds of warmup is abandoned at once
-- rather than waited out (MyHome's give-up rule -- a bound on the remaining
-- delay, not a timer).
local GIVE_UP_SECONDS = 30

--- item.status for a piece of equipment currently worn. Exported because
--- warp.lua, enchanteditem.lua and the widget all test it, and four copies
--- of a magic number is four chances to drift.
enchanted.EQUIPPED = 5
local EQUIPPED = enchanted.EQUIPPED

--[[ Every equip slot an item can be worn in, lowest first - ring1 (13)
     before ring2 (14), ear1 before ear2.

     THREE shapes are read, because nothing in this repo had ever touched
     `res.items[].slots` before this and the failure is silent and total: an
     unread shape answers "cannot tell which slot" on every press and leaves
     the binder's Enchanted group permanently empty. A set (slot id -> true)
     is what Windower's resources are believed to carry; a plain list of ids
     costs nothing to accept; and the raw DAT form is a BITFIELD, which is
     what the resources are generated from, so it is the likeliest surprise
     of the three. ]]
function enchanted.equip_slots(item)
  local slots = type(item) == "table" and item.slots or nil
  if type(slots) == "number" then
    --[[ A bitfield - but ONLY where it cannot be anything else. A bare slot
         id would be 0..15, and so would a bitfield naming nothing above
         ammo, so the two are indistinguishable down there and the contract
         is to say "cannot tell" rather than guess. Above 15 a bare id is
         impossible, so the number can only be a bitfield.

         Guessing wrong here is not a quiet failure: reading a bare `13` as
         a bitfield answers slots 0, 2 and 3, and the caller then equips a
         RING into the main hand and holds `gs disable main`. A dead feature
         is a better wrong answer than a weapon coming off mid-fight, and
         question I settles which shape it really is. ]]
    if slots <= 15 then
      return {}
    end
    local ids = {}
    for bit = 0, 15 do
      -- Arithmetic, not LuaJIT's `bit`: Lua 5.1 has no bitwise operators
      -- and the library is not part of the standard the addon targets
      -- (equipviewer decodes encumbrance the same way).
      if math.floor(slots / 2 ^ bit) % 2 == 1 then
        ids[#ids + 1] = bit
      end
    end
    return ids
  end
  if type(slots) ~= "table" then
    return {}
  end
  local ids = {}
  --[[ The two table shapes are read SEPARATELY rather than in one pass, so
       neither can be mistaken for the other:

       - a list is the array part, so `ipairs` is the reading - it requires
         keys 1..n and simply finds nothing in a set;
       - a set is `key -> true`, and the value must be `true` rather than
         merely truthy.

       Mixing them was wrong in both directions. A list of slot NAMES would
       have resolved to its own indices (1 and 2, sub and range), and a set
       written `{[13] = 1, [14] = 1}` would have resolved to its VALUES (1,
       the off-hand) - each a confident wrong answer where the contract is
       to say "cannot tell". ]]
  local candidates = {}
  for _, value in ipairs(slots) do
    if type(value) == "number" then
      candidates[#candidates + 1] = value
    end
  end
  for key, value in pairs(slots) do
    if value == true and type(key) == "number" then
      candidates[#candidates + 1] = key
    end
  end
  for _, id in ipairs(candidates) do
    --[[ In range, whichever branch produced it. There are sixteen equip
         slots; an id outside them reaches `set_equip` as a slot that does
         not exist AND misses GS_SLOT_NAMES, so the piece is equipped
         nowhere with no GearSwap hold and the wait dies at its deadline.
         The bitfield branch refuses what it cannot read for the same
         reason - the set and list branches were the two left undefended. ]]
    if id ~= nil and id >= 0 and id <= 15 then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

--[[ EVERY copy of every item in every equippable bag, by item id: an
     ordered list per id rather than one winner, because which copy is the
     right one is a question only the caller can answer. Bags walk in sorted
     id order so the ordering is the same on every call (MyHome's `pairs`
     walk left that to chance).

     Ranked: reachable before unreachable (a spare in a disabled wardrobe
     must not shadow the copy you can actually reach), then the copy you are
     WEARING before a spare, then bag order. That ranking is a preference,
     not a verdict: an enchanteditem binding walks DOWN it until it finds a
     copy it can actually use. `collect` below does NOT take its head - it
     re-picks without the worn preference, for the reason its own comment
     gives.

     Lives here rather than in warp.lua because the ladder is not the only
     caller any more: an `enchanteditem` binding searches the same bags for
     the one item it names. ]]
function enchanted.candidates(bags, get_items)
  local bag_ids = {}
  for id, bag in pairs(bags or {}) do
    if bag.equippable then
      bag_ids[#bag_ids + 1] = id
    end
  end
  table.sort(bag_ids)

  local found = {}
  --[[ Where each entry came in the walk: bags in sorted id order, items in
       array order. It is the tie-break of last resort here AND what
       `collect` orders by, so two copies sharing ONE bag are still
       separable - comparing bags alone let the worn-first ranking decide
       them, which is the opposite of what collect promises. ]]
  local seq = 0
  for _, bag_id in ipairs(bag_ids) do
    local bag = get_items(bag_id) or {}
    --[[ An ABSENT flag reads as reachable; only an explicit `false`
         excludes. The client always sends one, so this is about what a
         partial read means - and "I did not say" is not "no". The count
         path applies the identical rule, which is what lets the corner and
         the press agree. ]]
    local enabled = bag.enabled ~= false
    for _, item in ipairs(bag) do
      if item.id and item.id > 0 then
        seq = seq + 1
        found[item.id] = found[item.id] or {}
        local list = found[item.id]
        list[#list + 1] = { item = item, bag = bag_id, enabled = enabled, seq = seq }
      end
    end
  end

  for _, list in pairs(found) do
    table.sort(list, function(a, b)
      if a.enabled ~= b.enabled then
        return a.enabled
      end
      local a_worn = a.item.status == EQUIPPED
      local b_worn = b.item.status == EQUIPPED
      if a_worn ~= b_worn then
        return a_worn
      end
      return a.seq < b.seq
    end)
  end
  return found
end

--[[ One copy per item id, for the warp ladder: it reads charges off the
     single copy it is handed and then walks to the next RUNG rather than
     the next copy.

     Reachable first, then bag order - and deliberately NOT the worn
     preference the ranking above carries. With one copy surviving,
     preferring a SPENT ring on your finger would report the rung as out of
     charges while a charged spare sat in the bag. ]]
function enchanted.collect(bags, get_items)
  local best = {}
  for id, list in pairs(enchanted.candidates(bags, get_items)) do
    local pick = nil
    for _, entry in ipairs(list) do
      -- Ordered by `seq`, not by bag: two copies sharing a bag are
      -- separated here rather than falling through to the worn-first
      -- ranking `candidates` applied.
      local better = pick == nil
        or (not pick.enabled and entry.enabled)
        or (pick.enabled == entry.enabled and entry.seq < pick.seq)
      if better then
        pick = entry
      end
    end
    best[id] = pick
  end
  return best
end

--- Seconds until the enchantment can fire again; 0 when ready. Nil for a
--- non-enchanted item, one with no charges left, or an ext that is not
--- enchanted-shaped at all - the same degrade-not-throw posture step() has,
--- because this feeds warp's ladder walk.
function enchanted.recast_remaining(ext, now)
  if type(ext) ~= "table" or ext.type ~= "Enchanted Equipment" then
    return nil
  end
  if type(ext.charges_remaining) ~= "number" or ext.charges_remaining <= 0 then
    return nil
  end
  if type(ext.next_use_time) ~= "number" then
    return nil
  end
  return math.max(ext.next_use_time + EXTDATA_OFFSET - now, 0)
end

--- Seconds of equip warmup still to pass before the enchantment activates.
function enchanted.warmup_remaining(ext, now)
  return math.max(ext.activation_time + EXTDATA_OFFSET - now, 0)
end

--- The default give-up bound, for a caller that wants to name it in a
--- message rather than hardcode the number beside it.
function enchanted.give_up_default()
  return GIVE_UP_SECONDS
end

--[[ Items whose warmup runs long enough that the default bound would give up
     on them. Keyed by lowercased english name, because this is a fact about
     the ITEM and both callers have to agree on it: the warp ladder reaching
     a rung and an `enchanteditem` binding naming the same ring must wait the
     same length of time, or the ring works from one and "randomly refuses"
     from the other.

     The Tavnazian Ring's warmup is thirty seconds (confirmed in client,
     2026-08-21), and the test is
     `warm > bound`, so thirty exactly still waits. What does not is thirty
     plus anything: equip latency, the poll landing a moment late, a
     timestamp the client rounded up. On the default bound each of those
     turns into "needs more than 30 sec" and the ring looks like it randomly
     refuses. Ten seconds of headroom covers the slop, not the warmup. ]]
local GIVE_UP_BY_NAME = {
  ["tavnazian ring"] = 40,
}

--- The give-up bound for a named item: its own where it has one, the module
--- default otherwise.
function enchanted.give_up_for(name)
  if type(name) ~= "string" then
    return GIVE_UP_SECONDS
  end
  return GIVE_UP_BY_NAME[name:lower()] or GIVE_UP_SECONDS
end

--- One poll of the equip -> wait -> use plan: "use" when the enchantment is
--- live, "abandon" when the remaining delay exceeds the give-up bound, "wait"
--- otherwise. `worn` says the caller knows the piece is already equipped,
--- which is the only case where an elapsed warmup counts as live - see below.
--- `give_up` overrides the default bound for a caller whose item is known to
--- need longer than MyHome's rungs do.
--- Nil for an ext that is not enchanted-shaped (no numeric activation_time):
--- this runs per frame under a shared handler guard, so a foreign decode must
--- degrade, never arithmetic-throw.
function enchanted.step(ext, now, worn, give_up)
  if type(ext) ~= "table" then
    return nil
  end
  if ext.usable then
    return "use"
  end
  if type(ext.activation_time) ~= "number" then
    return nil
  end
  local warm = enchanted.warmup_remaining(ext, now)
  --[[ `worn` says the caller KNOWS the piece is already on, and only then
       is an elapsed warmup evidence of anything: activation_time is written
       when a piece is equipped, so on an item that is not worn it is a
       stale timestamp from some previous equip, and reading it as "ready"
       fires the moment after set_equip - before the equip has even
       round-tripped to the server, let alone rewritten extdata.

       That distinction is the whole point of the argument (added
       2026-08-20, corrected the same day): for a piece already on, waiting
       for `usable` alone risks sitting out the whole deadline if the flag
       ever means something narrower than we assume, and firing a shade
       early costs one refused command instead. For a piece we are
       equipping, `usable` is the only signal that means anything, which is
       what the ladder has always relied on.

       Note the flag short-circuits ABOVE all of this, so `worn` cannot
       protect the equip path from a stale `usable` - the same staleness the
       argument is about. Whether it can be stale-true is open: question N
       in .claude/Planning/crossbar-in-client.md. ]]
  if worn and warm == 0 then
    return "use"
  end
  --[[ Per call, because the bound is a fact about the ITEM: a ring whose
       warmup is thirty seconds sits exactly on the module default, and any
       slop - poll timing, equip latency, a rounded timestamp - would tip it
       into "abandon" and make the ring look like it randomly refuses. ]]
  if warm > (give_up or GIVE_UP_SECONDS) then
    return "abandon"
  end
  return "wait"
end

return enchanted
