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

--[[ The player service: one read of the client per interval, shared by every
     component, and the single place the two vitals streams are reconciled.

     It exists because the components were each answering "what is the player's
     HP right now" for themselves, and answering it differently. parambar took
     the absolute stream from the `hp change` events alone and never re-read the
     client, so an HP number stuck at max HP after a Max HP Down wore off had no
     path back for the rest of the session; partylist polled and overlaid the
     events on top, dropping them each poll, which is correct; targetbar polled
     and ignored the events, so the player's own row lagged what parambar drew.
     One of the three was wrong for months. Now there is one policy:

       the client is the authority, and a change event carries the bars until
       the next read of the client overrules it.

     The second job is deduplication. Five callers wanted the player and four
     wanted the party inside every 200ms; six distinct `get_mob_by_target`
     signatures were asked about thirteen times a frame, because the three party
     lists each ask for the same four. Consumers now call every frame and let
     this own the cadence -- their own throttles come out -- and read
     `generation()` when they need to tell a fresh read from a cached one.

     Nothing here touches a Windower global: `deps` carries the four client
     reads and a clock. ]]

-- The cadence the target bar and the party list already ran at.
local READ_INTERVAL_MS = 200

--[[ How long a mob memo may live if `begin_frame` never comes. It normally
     clears every frame; this is only reached when prerender has stopped -- guard
     disables a handler after five failures, and a minimised client renders
     nothing -- while key presses and packets keep arriving. A press resolved
     against a frozen target sends an action at the wrong mob, so the memo lets
     go on its own: far longer than a frame, far shorter than a person. ]]
local MEMO_MAX_SECONDS = 0.1

local VITALS = { hp = true, hpp = true, mp = true, mpp = true, tp = true }

local function new(deps)
  local self = {}

  -- The client's own tables, exactly as it handed them over.
  local raw = {}
  -- Which of them the next call must re-read.
  local stale = { player = true, party = true, info = true }
  local deadline = nil
  local generation = 0

  -- Change-event values since the last real read of the player, and the merged
  -- player table handed to callers. `merged` is nil when it needs rebuilding,
  -- which is on a read and on an event -- never per call, because five
  -- consumers an interval must not each pay for a copy.
  local overlay = nil
  local merged = nil

  -- Cleared every frame rather than on the interval: the target can change
  -- between any two frames, so a memo that outlived one would be wrong.
  local mobs = {}
  local mobs_stamp = nil

  local function opening_read()
    local now = deps.now()
    if deadline ~= nil and now < deadline then
      return
    end
    deadline = now + READ_INTERVAL_MS / 1000
    generation = generation + 1
    stale.player, stale.party, stale.info = true, true, true
  end

  --[[ A shallow copy, plus a copy of `vitals` with the overlay written over it.
       Only `vitals` is copied deeply, because only `vitals` is merged: the other
       nested fields (`buffs`, `job_points`) are handed on as the client's own
       tables, which is safe for as long as nothing writes to them, and nothing
       does.

       The copy is per READ, not per caller: every consumer shares one table for
       the whole interval. So a consumer that wrote to it would corrupt the
       others' view rather than only its own - a wider blast radius than before
       this service existed, and the reason nothing here hands out the client's
       own table either.

       A missing `vitals` stays missing, overlay or not. The client fills the
       player in field by field and callers guard on `player and player.vitals`;
       inventing a table would defeat that guard, and a consumer that treats
       what it is handed as a REPLACEMENT - parambar does - would drive every
       vital the overlay does not mention to zero, blanking the numbers and
       hiding the fills. The event is not lost, only deferred: the next read is
       at most an interval away and brings the whole table with it. ]]
  local function rebuild()
    local player = raw.player
    if player == nil then
      merged = nil
      return
    end

    local copy = {}
    for key, value in pairs(player) do
      copy[key] = value
    end

    if player.vitals ~= nil then
      local vitals = {}
      for key, value in pairs(player.vitals) do
        vitals[key] = value
      end
      for key, value in pairs(overlay or {}) do
        vitals[key] = value
      end
      copy.vitals = vitals
    end

    merged = copy
  end

  -- Cleared at the top of every prerender, before any component updates.
  function self.begin_frame()
    mobs = {}
    mobs_stamp = nil
  end

  --[[ Which read interval we are in. A consumer that calls every frame reads
       this to tell a fresh answer from a cached one -- the party list resets its
       packet overlay per read, and doing that per frame would throw away the
       0x0DD / 0x0DF pushes it exists to hold.

       Reading it OPENS the interval, and must: a consumer may gate every one of
       its reads behind this counter (targetbar does), and if only a read could
       advance it, that consumer would go quiet after its first frame and only
       look right for as long as some other component happened to read the
       client earlier in the same frame. It costs nothing on its own -- the
       reads stay lazy, so opening an interval nobody reads from is free. ]]
  function self.generation()
    opening_read()
    return generation
  end

  --[[ The client has moved under us and the rest of the interval is not worth
       waiting out. Bare, it drops everything: a zone or a login changes every
       answer here.

       Keyed (`invalidate("player")`), it marks one source stale and leaves the
       interval and the counter alone. That matters for the frequent triggers:
       a buff gain makes the player stale and nothing else, and dropping the
       whole interval for one would re-read the party and the zone as well - and
       move the counter, which puts the party list through a full roster rebuild
       and the target bar through an eighteen-member walk for a fact neither of
       them holds.

       An unknown key drops everything rather than nothing: a typo must not
       quietly turn an invalidation into a no-op, which is the silent-failure
       shape this codebase keeps getting bitten by.

       The bare form drops the mob memo as well, which the keyed form leaves
       alone: on a zone the mobs it remembers are gone, and a key press arriving
       before the next prerender would resolve its target out of the zone just
       left. A buff moves nobody. ]]
  function self.invalidate(source)
    if source ~= nil and stale[source] ~= nil then
      stale[source] = true
      -- No `merged = nil` here: the only thing that consumes stale.player is
      -- the read in get_player, which clears `merged` itself.
      return
    end
    deadline = nil
    mobs = {}
    mobs_stamp = nil
  end

  function self.get_player()
    opening_read()
    if stale.player then
      -- Assigned first, flag cleared after: a read that throws must not count
      -- as this interval's, or every later call in it would be served the
      -- pre-throw value with nothing to say the client had failed.
      raw.player = deps.get_player()
      stale.player = false
      -- The read is newer than any event that preceded it, by construction:
      -- the events are reported out of the state this just read.
      overlay = nil
      merged = nil
    end
    if merged == nil then
      rebuild()
    end
    return merged
  end

  --[[ Handed over as the client gave it. Eighteen member tables copied five
       times a second would cost more than the reads this saves, and nothing is
       merged into the party the way the overlay is merged into the player.

       So the three lists and the target bar now share one table where each used
       to get its own, and a consumer that wrote to a member would corrupt the
       others rather than only itself. None does - they keep what they add in
       side tables (`live.pushed`, `live.own_vitals`, `party_ids`) - and this is
       the reason to keep it that way. ]]
  function self.get_party()
    opening_read()
    if stale.party then
      raw.party = deps.get_party()
      stale.party = false
    end
    return raw.party
  end

  function self.get_info()
    opening_read()
    if stale.info then
      raw.info = deps.get_info()
      stale.info = false
    end
    return raw.info
  end

  --[[ Memoized for the frame, keyed on every argument. The ARGUMENT arity is
       not narrowed: the skillchain engine reads the fallback pair ('t', 'bt'),
       and a pair must not share a slot with the single 't' either. The RETURN
       is narrowed to one value, which the wrapper this replaced did not do -
       the API answers a single mob table and nothing reads past it. ]]
  function self.get_mob_by_target(...)
    --[[ The count leads the key. Joining the arguments alone would let one
         argument carrying the separator collide with a longer call, and the
         pair ('t', 'bt') sharing a slot with a single 't' is exactly what this
         memo must not do. Unreachable with the six fixed tokens the addon
         passes, but the separation is an invariant rather than an accident. ]]
    local count = select("#", ...)
    local parts = { tostring(count) }
    for index = 1, count do
      local value = select(index, ...)
      -- Typed, so 5 and "5" cannot share a slot either. Unreachable with the
      -- six fixed tokens the addon passes, but a separation worth stating is a
      -- separation worth holding in general.
      parts[index + 1] = type(value) .. tostring(value)
    end
    local key = table.concat(parts, "\0")

    local now = deps.now()
    if mobs_stamp ~= nil and now - mobs_stamp >= MEMO_MAX_SECONDS then
      mobs = {}
      mobs_stamp = nil
    end

    -- Boxed, because "the client had nothing for this target" is an answer
    -- worth remembering rather than asking again every call.
    local remembered = mobs[key]
    if remembered == nil then
      remembered = { deps.get_mob_by_target(...) }
      mobs[key] = remembered
      mobs_stamp = mobs_stamp or now
    end
    return remembered[1]
  end

  -- One value from an `hp change` / `hpp change` / … event. Good until the next
  -- read of the client, which drops it.
  function self.set_vital(kind, value)
    if not VITALS[kind] then
      return
    end
    value = tonumber(value)
    if value == nil then
      return
    end
    overlay = overlay or {}
    overlay[kind] = value
    merged = nil
  end

  return self
end

return new
