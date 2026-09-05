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
     render.cost dims on TP and nothing else, so the other five refusals
     turn down a slot drawn bright. See the note at the call site.

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

-- The 0x028 category that means a weaponskill landed (skillchain.lua's own
-- CATEGORY_RESOURCES documents the numbering). Ours releases the lock.
local WEAPONSKILL_FINISH = 3

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

local function new(deps)
  local self = {}

  --[[ When the weaponskill in flight stops being one. nil is "nothing in
       flight"; the value is the BACKSTOP's deadline, not an expectation -
       the real release is our own finish packet arriving. ]]
  local locked_until = nil

  local function now()
    return deps.now ~= nil and deps.now() or 0
  end

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
      --[[ Unlike the cast retry, this ships ON - which is Kevin's call
           (2026-09-05) and NOT a claim that every rule below is safe. Five
           of the six are now settled: four are facts the client hands over
           (TP, what is selected, what it is, whether one is already in
           flight), and the fifth - that the game refuses a weaponskill
           while not engaged - Kevin confirmed the same day, closing
           in-client question P. The REACH is the one that is still a
           number nobody has measured, and it ships loose for that reason.
           Row O10 is how it gets settled. ]]
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
      --[[ Seconds the in-flight lock survives with nothing reported. The
           ORDINARY release is our own finish packet; this is only for the
           one that never comes - and it is deliberately SHORT (Kevin,
           2026-09-05), because it is the one rule here that can kill a
           button that would have worked: the finish match rests on an
           actor id nobody has read in a live client, and a wrong match
           costs the player their weaponskill for this whole span after
           every press. A second covers the 200ms the cached TP read is
           stale several times over, which is the window nothing else here
           can see.

           What it deliberately does NOT cover: a gear file that cancels a
           press, queues an ability and re-fires the weaponskill a second
           later. Spam inside that window reaches GearSwap again, where its
           own lock still catches it. Covering it would mean three seconds,
           and three seconds is too long to be wrong for.

           Zero is NOT an off switch here, unlike travel.lua's `delay`: the
           switch is `enabled`, and a hand-edited zero falls back to this
           span rather than disarming the lock on its own. ]]
      in_flight = 1,
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

  -- In flight: a weaponskill has gone out and neither landed nor timed out.
  local function locked()
    return locked_until ~= nil and now() < locked_until
  end

  --[[ Something the game would refuse anyway? A weaponskill in reach of a
       claimable mob, at TP, while engaged, with nothing already in flight.

       `facts` that is not a table at all is a wiring slip rather than an
       answer, and reads as knowing nothing - so it allows, lock included.
       A `target` of nil INSIDE a table is the opposite: the widget looked
       and there was nothing selected. ]]
  function self.allow(record, facts)
    if type(record) ~= "table" or record.type ~= "ws" or type(facts) ~= "table" or not self.enabled() then
      return true
    end
    if locked() then
      return false
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

    local target = facts.target
    if type(target) ~= "table" then
      --[[ Nothing selected refuses only where the widget actually LOOKED,
           which it says with `target_read`. A weaponskill bound to a token
           this repo has not read `get_mob_by_target` for - <st>, <p3>, a
           scan - is never looked up at all, and an empty <t> is not a fact
           about <bt>: refusing there would kill a press that fires. Nor is
           a ctx that cannot be asked, which would otherwise refuse every
           weaponskill for the session off one wiring slip. Without the mob
           there is no reach to measure either, so this is the end of it. ]]
      return facts.target_read ~= true
    end
    --[[ Not an enemy, on the three fields this repo already reads in anger
         (partylist and the stealth ladder read the first two). `valid_target`
         is deliberately absent: nobody here has confirmed the field exists,
         and a guess would refuse presses on the strength of a nil. ]]
    if target.is_npc == false or target.in_party == true or tonumber(target.hpp) == 0 then
      return false
    end

    if not RANGED_SKILLS[type(facts.skill) == "string" and facts.skill:lower() or ""] then
      -- The mob table reports the SQUARE of the distance; targetbar/logic.lua
      -- takes the same root off the same field, and prints what comes out -
      -- which is the number `melee_range` is expressed in.
      local squared = tonumber(target.distance)
      -- Strictly greater: AT the reach still fires. See melee_range above.
      if squared ~= nil and math.sqrt(math.max(squared, 0)) > self.melee_range() then
        return false
      end
    end

    return true
  end

  --- A weaponskill went out: hold the next press until it resolves. Called
  --- AFTER the send, and for a weaponskill alone - the lock exists so a
  --- spammed button cannot stack presses the client has not answered for
  --- yet, which is the window the TP read cannot cover (it is an interval
  --- old, and TP does not fall until the weaponskill lands).
  function self.sent(record)
    if type(record) ~= "table" or record.type ~= "ws" or not self.enabled() then
      return
    end
    --[[ No clock, no lock. Both fallbacks answer 0 for a missing one, so an
         armed lock would sit its whole span in a future that never arrives
         and the session's first weaponskill would be its last. ]]
    if deps.now == nil then
      return
    end
    locked_until = now() + positive(settings().in_flight, self.defaults().in_flight)
  end

  --[[ A decoded 0x028. OUR OWN weaponskill landing is what releases the
       lock; anything else - somebody else's, or one of our own spells -
       leaves it alone. A refusal the game sends instead is not read here:
       the cast retry's own refusal message ids have never been observed
       firing, so nothing is keyed to them and the backstop covers it. ]]
  function self.on_action(action, self_id)
    if type(action) ~= "table" or action.category ~= WEAPONSKILL_FINISH then
      return
    end
    if self_id == nil or action.actor_id ~= self_id then
      return
    end
    locked_until = nil
  end

  --- Forget the lock: a zone, a death, a logout or a re-attach. Whatever was
  --- in flight is not landing now.
  function self.clear()
    locked_until = nil
  end

  return self
end

return new
