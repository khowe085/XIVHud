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

--[[ The weaponskill gate: a `ws` press the game could never honour is
     refused HERE, and nothing is sent at all.

     Moved in from a GearSwap file, where the same guard ran a round trip
     too late - the crossbar sent `/ws "Savage Blade" <t>`, the chat queue
     carried it, and GearSwap's precast filter cancelled it. A spammed macro
     still filled Windower's chat queue on the way to being dropped, and a
     character whose gear file did not carry the guard had none at all.

     It began as the rule this component already follows - the mount slot's
     dim and its dead press are one, and a weaponskill slot was ALREADY
     drawn dimmed below its 1000 TP while still firing - but the two are NOT
     one here, and that is a deliberate exception (Kevin, 2026-09-05):
     render.cost dims on TP and nothing else, so the reach refusal turns
     down a slot drawn bright. See the note at the call site.

     THREE RULES, down from six, cut against a live client (Kevin,
     2026-09-05). What went, and why:

     - "nothing targeted" and "the target is not an enemy". ENGAGING LOCKS
       YOUR TARGET to an attackable mob, so neither state is one the game
       will give you: both rules were untestable in a client, and a rule
       nobody can reach is a rule nobody can trust. The distance is all
       this module wants of a mob now, which is why it never sees one.
     - the in-flight lock, which held the next press for a second after one
       went out. TP RECOVERY OUTLASTS IT many times over, so a second press
       could never happen inside the window in the first place. It cost an
       unverified packet match (our own 0x028 category 3 by actor id, which
       nobody has read in a client) for a case that cannot arise. The one
       thing it did do was swallow a mashed burst inside the second a
       weaponskill takes to resolve, before TP has fallen; without it such
       a press goes out with the TP already spent, and the game refuses it
       harmlessly. A redundant command, not a wasted 3000 TP.

     PURE - the client tables arrive in `facts`, gathered by the widget from
     the player service. Weaponskills alone: an unaffordable spell still
     sends and the game refuses it, because the MP read can be an interval
     stale and a cast refused locally that you could just afford would read
     as a dead button.

     EVERY refusal is a fact the caller was CONFIDENT of. A fact that could
     not be read allows the press - the cost corner's rule, and the one that
     keeps a login's first frames from reading as a dead bar. A missing
     guard is a better failure than a button that does nothing. ]]

-- Every weaponskill costs the same, which is why crossbar.lua writes it as a
-- literal into a `ws` slot's meta rather than reading one.
local WEAPONSKILL_TP = 1000

--[[ Engaged, and it is a FALLBACK rather than a fact - travel.lua's idiom
     for the resting status. The english name out of `res.statuses` is what
     survives a client update; this stands in when the resources library did
     not load, so the gate degrades rather than disappearing. ]]
local ENGAGED_STATUS = 1

--[[ Skills whose weaponskills are fired from across the field. Their reach
     is DistancePlus' bands rather than one melee number, and that port
     lives in the targetbar, which cannot be required from here - so a
     ranged weaponskill is gated on everything EXCEPT the distance.

     THREE, not two: render.lua's icon branch classifies the same three
     (`archery`, `marksmanship`, `throwing`), and a boomerang or a deck of
     cards is thrown from well past melee reach - measuring one as melee
     would silently refuse a press that fires.

     A skill the resources could not name is measured as melee, the
     conservative reading of the two: an unnamed skill is far more likely a
     melee one the client had not answered for yet than a bow. ]]
local RANGED_SKILLS = { archery = true, marksmanship = true, throwing = true }

--[[ A positive, finite number, or the shipped one. NaN is caught by
     identity: it fails every comparison, so `<= 0` would wave a hand-edited
     `0/0` straight through and measure every reach against it. Zero is
     broken rather than an off switch - the switch is `enabled`, and a reach
     of zero would refuse everything past a yalm. ]]
local function positive(value, fallback)
  local number = tonumber(value)
  if number == nil or number ~= number or number <= 0 or number == math.huge then
    return fallback
  end
  return number
end

--[[ The same, but zero is legitimate: a size pivot of zero means every mob
     adds the whole of its bulk to the reach, which is a real setting rather
     than a broken one. Split from `positive` above rather than
     parameterised, because which side zero falls on is the entire
     difference. ]]
local function nonnegative(value, fallback)
  local number = tonumber(value)
  if number == nil or number ~= number or number < 0 or number == math.huge then
    return fallback
  end
  return number
end

local function new(deps)
  local self = {}

  -- The live config block. A hand-broken one (a non-table, a missing key)
  -- must read as the SHIPPED posture rather than throw in a key handler.
  local function settings()
    local live = deps.config ~= nil and deps.config() or nil
    return type(live) == "table" and live or {}
  end

  --[[ The shipped config block - defaults.lua seeds `config.wsgate` from
       here, so there is one place to tune and nothing to keep in step. ]]
  function self.defaults()
    return {
      --[[ Unlike the cast retry, this ships ON, and all three rules that
           survive are now settled in a live client (Kevin, 2026-09-05): TP
           is a fact the client hands over, the game refuses a weaponskill
           while not engaged (in-client question P), and the reach was
           measured by walking in on a mob (row O10). ]]
      enabled = true,
      --[[ Yalms of reach: THE DISTANCE THE TARGET BAR PRINTS, and nothing
           added to it (Kevin, 2026-09-05).

           It was `reach + both model sizes` at first, copying
           targetbar/logic.lua's casting_state - which made the number
           unsettable from a live client, since the number a player reads
           off the target bar was not the number the setting meant. A reach
           of 6 let a weaponskill go at a target bar 6, which is how that
           was found. The model sizes are gone: a mob the size of a house
           is measured exactly like a rabbit, which is wrong in principle
           and tunable in practice, and tunable won.

           WHICH DIRECTION IS SAFE also changed once a client answered. It
           shipped loose on the reasoning that a press let through reaches
           a game that refuses it harmlessly - and the game does NOT refuse
           it. Kevin's weaponskill fired at a target bar 6 and spent the
           whole 3000 TP for nothing. So too loose is the EXPENSIVE
           failure and too tight is merely a dead button, the reverse of
           what was written here first, and this rule is the most valuable
           of the six rather than the most expendable.

           FOUR, from a live client (Kevin, 2026-09-05): a weaponskill
           landed at a target bar 3 and at 4, and was thrown away at 6. It
           is the furthest distance that still FIRES rather than the first
           one refused, which is why the comparison below is strictly
           greater - a player types the number they watched work.
           `//hud crossbar wsgate range <yalms>` moves it live. ]]
      melee_range = 4,
      --[[ The mob bulk the reach already covers. Past it, every yalm of
           model size is another yalm of reach; at or under it, `melee_range`
           is the whole answer.

           FITTED to five live readings (Kevin, 2026-09-05), model size
           against the furthest distance a weaponskill still landed from:
           1.0 -> 4, 1.2 -> 4, 1.5 -> 4, 2.5 -> 5, 6.3 -> 9. The first three
           are what put a FLOOR under it - three different sizes all capping
           at the same 4, so the reach does not shrink with a small mob - and
           they are why this is a pivot rather than the plain `base + size`
           that a two-point fit suggested: that fit refused the 1.0 mob at a
           distance it had just been struck from.

           The readings are LOWER BOUNDS - the furthest distance that still
           landed, not the first that failed - so every cutoff must REACH
           its reading, and that is what fixes 1.3 rather than a rounder
           number: the 6.3 mob allows no more than 1.3 and the 2.5 mob no
           more than 1.5, so 1.3 is the tightest value honouring both. A
           pivot of 1.5 was tried first and fell 0.2 short of the 6.3
           reading, which is a press that landed in a client being refused.

           It also keeps `melee_range` meaning what it already meant, the
           reach against an ORDINARY mob, so the number settled by walking in
           on one carries over untouched and the size term is purely an
           addition for the big.

           This is why the mob's size arrives here at all, and why the reach
           SITS OUT when it cannot be read: without it there is no telling a
           rabbit from a monster, and measuring the monster on the bare reach
           would refuse a press that lands. ]]
      size_pivot = 1.3,
    }
  end

  --- On unless the config says `false` outright - the OPPOSITE reading to
  --- the cast retry's, and deliberately: that feature ships off, so only
  --- `true` may turn it on. A hand-broken config must not silently disable
  --- a guard the player never switched off.
  function self.enabled()
    return settings().enabled ~= false
  end

  --[[ The reach in force, shipped value and all. Public because the CLI
       reports and sets it: a second reading of the fallback over there
       could report a number that is not the one being measured against. ]]
  function self.melee_range()
    return positive(settings().melee_range, self.defaults().melee_range)
  end

  --- The reach against a mob of this bulk: the setting, plus every yalm of
  --- model size past the pivot. Public for the same reason melee_range is -
  --- the CLI prints it for the current target, and a second reading of the
  --- sum over there could name a number that is not the one being measured.
  --- The bulk the reach already covers, live. Public beside melee_range so
  --- the CLI can report and set it without a second reading of the fallback.
  function self.size_pivot()
    return nonnegative(settings().size_pivot, self.defaults().size_pivot)
  end

  function self.reach_for(model_size)
    -- NaN and infinity answer "no size" rather than an infinite reach: the
    -- module is scrupulous about both everywhere else, and an inf here
    -- would switch the rule off while printing `inf` in the CLI's readout.
    local size = tonumber(model_size)
    if size == nil or size ~= size or size == math.huge then
      return nil
    end
    local pivot = self.size_pivot()
    return self.melee_range() + math.max(0, size - pivot)
  end

  --[[ Engaged, resolved from the resource table rather than trusted from
       memory - the same walk travel.lua makes for resting. ]]
  local engaged = ENGAGED_STATUS
  if type(deps.statuses) == "table" then
    for id, entry in pairs(deps.statuses) do
      if
        type(id) == "number"
        and type(entry) == "table"
        and type(entry.en) == "string"
        and entry.en:lower() == "engaged"
      then
        engaged = id
        break
      end
    end
  end

  --[[ Something the game would refuse anyway? A weaponskill at TP, while
       engaged, within reach of whatever the bind aims at.

       The mob never reaches here - only `distance_squared`, the mob table's
       own squared field, and only when the widget looked one up. `facts`
       that is not a table at all is a wiring slip rather than an answer and
       reads as knowing nothing, so it allows. ]]
  function self.allow(record, facts)
    if type(record) ~= "table" or record.type ~= "ws" or type(facts) ~= "table" or not self.enabled() then
      return true
    end
    local tp = tonumber(facts.tp)
    if tp ~= nil and tp < WEAPONSKILL_TP then
      return false
    end

    --[[ CONFIRMED (Kevin, 2026-09-05): the game does not allow a
         weaponskill while not engaged, so refusing one here costs nothing.
         It was an assumption when it was written - and the wrong one would
         have made every out-of-combat press a dead button with no message,
         which is why it was tracked as in-client question P rather than
         left as a plain rule. ]]
    local status = tonumber(facts.status)
    if status ~= nil and status ~= engaged then
      return false
    end

    if not RANGED_SKILLS[type(facts.skill) == "string" and facts.skill:lower() or ""] then
      -- The SQUARE of the distance, as the mob table reports it and as the
      -- name says; targetbar/logic.lua takes the same root off the same
      -- field and prints what comes out, which is the number melee_range
      -- is expressed in.
      local squared = tonumber(facts.distance_squared)
      local reach = self.reach_for(facts.model_size)
      -- Strictly greater: AT the reach still fires. See melee_range above.
      if squared ~= nil and reach ~= nil and math.sqrt(math.max(squared, 0)) > reach then
        return false
      end
    end

    return true
  end

  return self
end

return new
