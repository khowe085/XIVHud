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

--[[ Travel delay: the countdown that stands between pressing mount, mount
     roulette or warp and actually going. It arms, speaks once a second, and
     answers the caller when the span has run out - so a mis-press costs five
     seconds of reading rather than a trip back from your Mog House. The
     delay is the point of the feature, not a side effect.

     Pure: nothing here sends a command or writes to chat. arm() and step()
     answer the lines to say and the entry to fire, and the widget does both.

     `draw` is deliberately not on the list, and neither is mount roulette's
     DISMOUNT: getting off a mount is how you get OUT of something, and that
     stays instant. Only summoning waits. ]]

-- Config: seconds. Zero is the off switch, so there is no toggle verb.
local DEFAULT_DELAY = 5

--[[ The three the delay governs: a specific mount, mount roulette, and the
     warp ladder. `draw` is deliberately absent - it dismounts, and getting
     out of something stays instant. ]]
local TRAVEL_TYPES = { mount = true, mr = true, warp = true }

--[[ The player status that means resting, and it is a FALLBACK, not a fact.
     The number is resolved from res.statuses by english name wherever the
     resources library loaded; this is what stands in when it did not, so
     the cancel degrades rather than disappearing. Unconfirmed in a live
     client - see the in-client list. ]]
local RESTING_STATUS = 33

-- How many seconds of a countdown are spoken out loud, counting back from
-- the end. The opening line carries the total, whatever the span.
local COUNT_FROM = 5

local function new(deps)
  local self = {}

  --[[ What is counting down, and how far it has got:

         { entry,    -- the widget's payload, verbatim: the label and how
                     -- to fire it when the span runs out
           label,    -- what the lines call it
           fire_at,  -- when it goes
           said }    -- the lowest second already spoken, so a per-frame
                     -- tick says each of them exactly once ]]
  local pending = nil

  local function now()
    return deps.now ~= nil and deps.now() or 0
  end

  -- The live config block. A hand-broken one (a non-table, a missing key)
  -- reads as the shipped span rather than throwing on a keypress.
  local function settings()
    local live = deps.config ~= nil and deps.config() or nil
    return type(live) == "table" and live or {}
  end

  --- The shipped config block - defaults.lua seeds `config.delay` from
  --- here, so the span and its fallback cannot drift apart.
  function self.defaults()
    return { delay = DEFAULT_DELAY }
  end

  --- The configured span in seconds, never negative: a countdown that could
  --- never end is not a thing to arm. A number the arithmetic cannot use
  --- (a hand-edited `0/0` or an infinity) is not a span either - both would
  --- arm a countdown that never fires and speaks every frame - so they read
  --- as the shipped value rather than as zero, which would fire at once.
  function self.delay()
    local span = settings().delay
    if type(span) ~= "number" or span ~= span or span == math.huge or span == -math.huge then
      return DEFAULT_DELAY
    end
    if span < 0 then
      return 0
    end
    return span
  end

  --[[ Is this press a trip at all? The TYPE alone, unlike label(), which
       also weighs the plan: a trip that fires the moment it is pressed -
       a dismount, a warp whose rung is already a wait, a `delay` of zero - is
       still a trip, and still supersedes a countdown already running. An
       ordinary press does not, and must leave one alone. ]]
  function self.travels(record)
    if type(record) ~= "table" then
      return false
    end
    return TRAVEL_TYPES[record.type] == true
  end

  --[[ Does this press wait, and what is the countdown called? Answers the
       label to speak, or nil for a press that fires the moment it is made -
       which is everything the feature does not name, plus three deliberate
       exclusions:

         * mount roulette's DISMOUNT (see the header),
         * a warp whose rung must be equipped and warmed up before it can
           fire - that wait, held with the GearSwap slot disabled, IS the
           window this feature exists to give you. The condition is the
           WAIT, not the item: an already-equipped, charged ring entails no
           wait at all, so it counts down like a spell rather than warping
           the instant it is pressed,
         * a press with nothing to fire: a rejected record (no plan), a
           roulette no-op, a warp ladder that found nothing.

       Called with the plan computed AT THE PRESS. The widget re-computes
       when the countdown ends, so a ladder that has moved on in the
       meantime fires whatever it says then - the later one wins. ]]
  -- A label a record actually carries: a non-empty string, or nothing.
  local function named(value)
    if type(value) ~= "string" or value == "" then
      return nil
    end
    return value
  end

  function self.label(record, plan)
    if type(record) ~= "table" or type(plan) ~= "table" then
      return nil
    end
    local kind = record.type
    if kind == "warp" then
      local rung = plan.plan
      if plan.kind ~= "warp" or type(rung) ~= "table" or rung.type == "none" or rung.warmup then
        return nil
      end
      --[[ The RUNG's own name, so the opening line says which way you are
           going home (Kevin, live client, 2026-08-22): the ladder has
           several, and "Warp" alone left the player watching a countdown
           without knowing whether it was about to burn a scroll or cast a
           spell. The bare word is the fallback for a rung that carries no
           name - a spell rung built before the resources loaded. ]]
      local name = named(rung.name)
      return name or "Warp"
    end
    -- Everything below fires one command, and a plan of any other shape
    -- (a hint, a no-op, an injected chord) is not a trip worth delaying.
    if plan.kind ~= "command" then
      return nil
    end
    if kind == "mount" then
      -- A mount slot pressed while mounted is a DISMOUNT, and getting out
      -- is never held - the same exclusion mount roulette gets below, on
      -- the same flag, so the two cannot drift.
      if plan.dismount then
        return nil
      end
      -- Named, or nothing: resolve() rejects a nameless mount record
      -- outright, and a countdown that cannot say what it is summoning
      -- would be a worse answer than the rejection.
      if type(record.action) ~= "string" or record.action == "" then
        return nil
      end
      -- The player's own label first, then the game's own casing, exactly
      -- as every other label path in the component reads them: a mount's
      -- stored action is the lower-case command form, and announcing
      -- "Mount chocobo" reads as a typo.
      local shown = named(record.alias) or named(record.display)
      return "Mount " .. (shown or record.action)
    end
    if kind == "mr" and not plan.dismount then
      return "Mount roulette"
    end
    return nil
  end

  --[[ Arms a countdown for `entry` - the widget's own payload, carried
       untouched and handed straight back when the span runs out. Answers
       the opening line to say, or nil for a press that must fire NOW: the
       delay is off (zero), or the payload has no name to speak.

       nil is therefore always "the caller fires it", and an armed countdown
       always leaves a line to say - there is no silent third case.

       A newer press REPLACES whatever was counting down, the cast retry's
       own discipline: nothing outlives the moment it belonged to, and the
       press the player just made is the one they meant. ]]
  function self.arm(entry)
    --[[ Cleared before anything is decided, so every answer this can give
         leaves the older countdown gone. DEFENCE, not a live path: it takes
         `delay` dropping to zero between two presses, and nothing can write
         it mid-session today - there is no verb for it, and a config reload
         detaches the widget, which drops the countdown anyway. Kept so that
         a `delay` made writable later cannot leave a countdown running
         behind a press that fired at once. ]]
    pending = nil
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
      return nil
    end
    local span = self.delay()
    if span <= 0 then
      return nil
    end
    pending = {
      entry = entry,
      label = entry.label,
      fire_at = now() + span,
      -- The opening line has already spoken this second, so the count
      -- starts at the one below it.
      said = math.ceil(span),
    }
    return entry.label .. " in " .. span .. (span == 1 and " second" or " seconds") .. ". /heal to cancel."
  end

  --[[ One step of the tick. Answers the entry to fire (and nothing else) on
       the step the span runs out, or the line for a second that has just
       ticked over, or neither. With nothing armed it is one comparison,
       which is what the per-frame budget allows.

       A frame that swallowed several seconds says the one it landed on and
       not the ones it missed: the countdown is a clock, not a queue. ]]
  function self.step()
    if pending == nil then
      return nil
    end
    local clock = now()
    if clock >= pending.fire_at then
      local entry = pending.entry
      pending = nil
      return entry
    end
    local remaining = math.ceil(pending.fire_at - clock)
    if remaining >= pending.said then
      return nil
    end
    pending.said = remaining
    --[[ Only the last few seconds are spoken (Kevin, live client,
         2026-08-22). Every second of the span was fine at the shipped five
         and a wall of text at thirty, which is what a ring rung's warm-up
         takes - the opening line already gave the whole number, so the
         middle of a long wait has nothing to add. ]]
    if remaining > COUNT_FROM then
      return nil
    end
    return nil, remaining .. "..."
  end

  --[[ Is a countdown running? One comparison, and no clock read. The
       widget's tick asks this BEFORE it asks whether a config mode is
       open: those two are not client calls (the binder's own state and the
       framework's layout flag), but they are calls across the ctx boundary
       on every frame, and the settled-tick budget the specs pin counts
       them. A player with nothing counting down should pay for the cheapest
       question only. (The cast retry's `pending()` gates its tick the same
       way, where the question behind it really is a client read.) ]]
  function self.armed()
    return pending ~= nil
  end

  --- Calls off whatever is counting down and answers the line saying so, or
  --- nil when there was nothing to call off. A cancel is never silent -
  --- a countdown that simply stopped would look exactly like one that fired.
  function self.cancel()
    if pending == nil then
      return nil
    end
    local label = pending.label
    pending = nil
    return label .. " cancelled."
  end

  --- Forget the countdown without a word, for the exits where telling the
  --- player would be noise: a logout or reload (the widget's detach), and a
  --- re-attach, where the configuration that armed it has just been
  --- replaced. Nothing else calls this - a cancel the player caused says so.
  function self.clear()
    pending = nil
  end

  --[[ The resting cancel, resolved from the resource table rather than
       hardcoded: this repo does not take a Windower number on trust. The
       english name is the key that survives a client update; the constant
       above is what stands in when the resources library did not load, so
       the cancel degrades rather than disappearing. ]]
  local resting = RESTING_STATUS
  if type(deps.statuses) == "table" then
    for id, entry in pairs(deps.statuses) do
      if
        type(id) == "number"
        and type(entry) == "table"
        and type(entry.en) == "string"
        and entry.en:lower() == "resting"
      then
        resting = id
        break
      end
    end
  end

  --[[ A status change: resting calls the countdown off. The trigger is the
       STATUS and not the `/heal` text (Sel-Include.lua:2313 does exactly
       this), so it catches resting however the player entered it - the
       command, a macro, or a pad button nobody here can see. Answers the
       cancel line, or nil for a status that means nothing to us. ]]
  --[[ Is this status the one that means resting? The countdown answers
       `/heal` by cancelling, and so does a warm-up over in the widget - but
       a warm-up arms no countdown, so `on_status` has nothing to report and
       cannot be what the widget keys off. One resolver, two readers. ]]
  function self.resting(status)
    return resting ~= nil and status == resting
  end

  function self.on_status(status)
    if status ~= resting then
      return nil
    end
    return self.cancel()
  end

  return self
end

return new
