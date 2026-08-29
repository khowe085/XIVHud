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

--[[ Cast retry: the pure state machine behind one refused action.

     REACTIVE, never predictive. A slot press sends immediately and is
     remembered here with its timestamp; only a refusal the client actually
     sends makes that record pending, and only then does the tick re-send
     it. A press the game accepted is never delayed, and nothing is ever
     held because of a RECAST - holding on cooldown is the defect that made
     the reference addon's queue (Selindrile's MiniQueue) unusable, and the
     reason this is not a port of it.

     Spells, job abilities and weaponskills, each on its OWN refusal message
     and its own blocking buffs - see the two tables below, which are where
     the per-kind scope actually lives. Anything with no entry there is
     never watched. ]]

--[[ THE TRIGGER, AND EVERY ID BELOW IS UNCONFIRMED. An action sent too soon
     is believed to be refused by the action-message packet 0x029 carrying
     one of these action messages - ids read out of a resource table, not
     observed: the reference addon's own handler for them has never once
     executed (it compares `action.message` where Windower's field label is
     `Message`), so nobody has seen any of this fire. See in-client question
     C in .claude/Planning/crossbar-in-client.md, which asks for all three
     to be collected in one sitting; whatever the client actually sends wins
     over what is written here, and changing it is an edit to this table and
     nothing else.

     Per KIND, because each is refused in its own words: answering an
     ability with a spell's message would re-send on somebody else's
     refusal. A kind absent from this table is never watched at all, which
     is what keeps items and the built-ins out. The ability and weaponskill
     ids are the weaker guess of the three - the spell pair at least has the
     reference addon's citation behind it. ]]
-- The shortest wait a re-send may be put on, whatever the config says.
local MIN_BACKOFF_SECONDS = 0.25

local ACTION_MESSAGE_CHUNK = 0x029
local REFUSAL_MESSAGES = {
  spell = { [17] = true, [18] = true },
  ability = { [71] = true },
  weaponskill = { [72] = true },
}
-- 1-based byte offsets into the raw chunk, header included - Windower's own
-- field order for 0x029: Actor (0x04), Target, Param 1, Param 2, Actor
-- Index, Target Index, Message (0x18). skillchain.lua reads the same packet
-- for the wear-off message. Question C also asks WHICH field names the
-- caster; if the refusal turns out to carry us as the Target instead, this
-- is the one offset to move (Target sits at byte 9).
local ACTOR_OFFSET = 5
local MESSAGE_OFFSET = 25

--[[ A KNOWN LIMIT of that match, and a second thing to look at while
     question C is being answered: the refusal is attributed to our last
     send on the strength of the actor and the timing alone - nothing here
     correlates it with the SPELL. A refusal produced by a game macro,
     another addon or GearSwap inside the window would therefore re-send
     ours. If the packet carries the spell id (Param 1 is the obvious
     candidate), comparing it would close the gap; nobody has seen the
     packet, so nothing is decoded here that has not been read for. ]]

--[[ Buffs that make an action impossible for a reason no amount of waiting
     fixes, by their resource ids (read off partylist's own buff order:
     silence 6, amnesia 16, mute 29). A refusal has non-timing causes, and a
     blind retry would hammer a doomed action until its deadline.

     Per kind, and NOT pooled: silence and mute stop spells, amnesia stops
     abilities and weaponskills, and neither set touches the other. Pooling
     them would throw away retries that would have worked - a silenced
     player can still use Provoke. ]]
local BLOCKING_BUFFS = {
  spell = { [6] = true, [29] = true },
  ability = { [16] = true },
  weaponskill = { [16] = true },
}

local function u16(data, offset)
  local low, high = data:byte(offset, offset + 1)
  return low + high * 256
end

local function u32(data, offset)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function new(deps)
  local self = {}

  --[[ What went out, and how far it has got:

         { record, command, set, side, slot,  -- the press, verbatim
           first_at,   -- the ORIGINAL send; the deadline measures from here
           sent_at,    -- the most recent send; the refusal window from here
           attempts,   -- re-sends spent, not counting the original press
           due_at }    -- when the pending re-send comes due

       `pending` is what separates "sent and quietly watched" from "refused
       and owed a re-send": a re-send puts the record straight back to
       watched, so a cast the game accepted the second time is never sent a
       third. ]]
  local held = nil
  local pending = false

  local function now()
    return deps.now ~= nil and deps.now() or 0
  end

  -- The live config block. A hand-broken one (a non-table, a missing key)
  -- must read as "off" rather than throw in a packet handler.
  local function settings()
    local live = deps.config ~= nil and deps.config() or nil
    return type(live) == "table" and live or {}
  end

  --[[ The shipped config block - defaults.lua seeds `config.retry` from
       here, so there is one place to tune and nothing to keep in step.

       EVERY NUMBER BELOW IS A FIRST GUESS, not a measurement. The enforced
       gap is reported as "usually 1-2 seconds, but"; how long after a
       refusal a re-send actually succeeds is in-client question D, and
       these are meant to be replaced by what a few minutes of casting says.
       A backoff shorter than the real gap just collects a second refusal
       and spends an attempt; a longer one wastes the smoothing the feature
       exists for. ]]
  function self.defaults()
    return {
      -- Off until the trigger above is confirmed in a live client.
      enabled = false,
      -- How soon after a send a refusal is still an answer to it.
      window = 2,
      -- The wait before a re-send. Flat, not escalating: with an attempt
      -- cap this small, an escalation would only be the deadline arriving
      -- sooner by another name.
      backoff = 1,
      -- Measured from the ORIGINAL press: nothing is re-sent after this,
      -- however many attempts are left.
      deadline = 5,
      -- Re-sends allowed, the original press not counted.
      attempts = 3,
    }
  end

  --- Off by default, and only `true` counts: the trigger this reacts to has
  --- never been observed firing (see the message ids above), so a truthy
  --- config value is not enough to turn it on.
  function self.enabled()
    return settings().enabled == true
  end

  --- The press the widget just sent, or nil for a press worth no retry.
  --- Either way it REPLACES whatever was held: a newer press means the
  --- player has moved on, and nothing may outlive the moment it belonged to.
  function self.sent(entry)
    held, pending = nil, false
    if entry == nil or not self.enabled() or REFUSAL_MESSAGES[entry.kind] == nil then
      -- A kind nothing here is refused in the words of can never be
      -- answered, so watching it would be pure cost.
      return
    end
    -- A copy, so nothing outside can rewrite what is being watched -- and a
    -- shallow copy of the WHOLE press rather than a named list of fields:
    -- the press is the widget's shape (the address it came from, the target
    -- it was pinned to, whatever a later guard needs), and this module has
    -- no business enumerating it. Its own bookkeeping is written last and
    -- therefore wins outright.
    local clock = now()
    held = {}
    for key, value in pairs(entry) do
      held[key] = value
    end
    held.first_at, held.sent_at, held.attempts, held.due_at = clock, clock, 0, nil
  end

  --- A number from the config, or the shipped fallback for a key a hand
  --- edit has broken. The shipped values themselves live in defaults().
  local function tuning(key)
    local value = settings()[key]
    if type(value) ~= "number" then
      return self.defaults()[key]
    end
    return value
  end

  --[[ The refusal branch on the `incoming chunk` the component already
       receives. Every cheap test comes BEFORE the player read - the id, the
       length, the message, and whether we even sent anything recently - so
       the traffic this is buried in costs no client call at all. Answers
       whether the refusal was taken, which is what the specs read. ]]
  function self.on_chunk(id, data)
    -- `pending` among the rejects: already owed a re-send, and a second
    -- refusal for the same send (both message ids are believed to mean the
    -- same thing) must not push the backoff out by another whole wait.
    if held == nil or pending or id ~= ACTION_MESSAGE_CHUNK or type(data) ~= "string" then
      return false
    end
    local refusals = REFUSAL_MESSAGES[held.kind]
    if refusals == nil or #data < MESSAGE_OFFSET + 1 or not refusals[u16(data, MESSAGE_OFFSET)] then
      return false
    end
    if not self.enabled() or now() - held.sent_at > tuning("window") then
      -- Too late to be an answer to what we sent: someone else's refusal,
      -- or our own from a press the game already dealt with. The record
      -- stays watched - a refusal for the NEXT send may still be coming.
      return false
    end
    local player = deps.get_player ~= nil and deps.get_player() or nil
    local me = player ~= nil and player.id or nil
    if me == nil or u32(data, ACTOR_OFFSET) ~= me then
      return false
    end
    pending = true
    -- Floored, because this one tuning does not fail safe on a bad sign: a
    -- zero or negative backoff from a hand-edited config would put every
    -- attempt on consecutive frames, which is the hammering the whole
    -- design exists to avoid. The other three stop the retry when they go
    -- wrong, which is the harmless direction.
    held.due_at = now() + math.max(tuning("backoff"), MIN_BACKOFF_SECONDS)
    return true
  end

  --- Forget everything. Every clear trigger goes through here: a zone, a
  --- death, a logout, a job change, the component being suppressed or
  --- hidden, and the feature being switched off.
  function self.clear()
    held, pending = nil, false
  end

  --- Reconcile with the live config after a write to it. Switching the
  --- feature off drops what is held there and then, rather than at the next
  --- tick: nothing is left for a refusal to revive.
  function self.sync()
    if not self.enabled() then
      self.clear()
    end
  end

  --[[ Are the conditions the press was made under still true? Every fact
       comes from state the widget already holds - the binding store, the
       resource tables and the 200ms client read - so a guard costs no
       client call of its own.

       `bound` is the mandatory one, and it doubles as "the probe answered
       at all": no answer, an empty answer or no probe is not permission to
       re-send. The rest block only when they positively say so - a recast
       we could not look up, or a cost the resource tables do not carry, is
       an unknown, not evidence against the press that already went out.

       A target that has CHANGED is deliberately not among these. The
       widget pins the target at the press and re-sends the id, so the cast
       lands on what was aimed at; giving up because the player looked
       elsewhere would solve that backwards. ]]
  local function guards_pass(kind, facts)
    if type(facts) ~= "table" or facts.bound ~= true then
      return false
    end
    if type(facts.recast) == "number" and facts.recast > 0 then
      return false
    end
    if facts.affordable == false then
      return false
    end
    local blocking = BLOCKING_BUFFS[kind] or {}
    for _, buff in ipairs(facts.buffs or {}) do
      if blocking[buff] then
        return false
      end
    end
    return true
  end

  --[[ One step of the tick. `probe` answers the guards for the record about
       to be re-sent, and is called ONLY when a re-send is otherwise due -
       with nothing pending this is a single comparison, which is what the
       per-frame budget allows. Answers the record to re-send, or nil.

       Two exits leave the record alone, and only two: nothing is pending,
       and the backoff has not run out. Once the record IS due, every exit
       but the send drops it outright - no guard failure is ever held back
       for a later attempt, because a guard that fails has said the press is
       not worth repeating, and the alternative is hammering a doomed spell
       until its deadline. ]]
  function self.step(probe)
    if not pending then
      return nil
    end
    if not self.enabled() then
      -- Switched off with a cast pending: it is dropped, never fired.
      self.clear()
      return nil
    end
    local clock = now()
    if clock < (held.due_at or 0) then
      return nil
    end
    if clock - held.first_at >= tuning("deadline") or held.attempts >= tuning("attempts") then
      self.clear()
      return nil
    end
    if not guards_pass(held.kind, probe ~= nil and probe(held) or nil) then
      self.clear()
      return nil
    end
    -- Straight back to watched: the re-send may well have worked, and only
    -- another refusal says otherwise.
    pending = false
    held.attempts = held.attempts + 1
    held.sent_at = clock
    held.due_at = nil
    return held
  end

  --- What is being watched, pending or not. Introspection.
  function self.held()
    return held
  end

  --- The record owed a re-send, or nil when nothing is pending.
  function self.pending()
    if not pending then
      return nil
    end
    return held
  end

  return self
end

return new
