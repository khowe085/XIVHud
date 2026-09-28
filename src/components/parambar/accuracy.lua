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

--[[ Melee accuracy over a rolling window: the scoreboard addon's parse, one
     player, no history past the window.

     The swings come off the `0x028` action packet the entry point already
     decodes for the cast bar and the skillchain engine, so nothing new is
     registered and nothing is parsed twice; the widget hands each one over
     with the player's own id and the frame clock.

     WHAT COUNTS is scoreboard's classification, message id for message id
     (addons/scoreboard/scoreboard.lua): 1 and 67 are a hit and a critical
     hit, 15 and 63 are a miss. Everything else the round can produce - a
     parry, a block, a counter, a guard, a Third Eye evasion - is NEITHER,
     and never reaches the denominator (Kevin, 2026-09-27). None of those is
     your accuracy failing, so the figure is "of the swings that resolved to
     a hit or a miss", not "of the swings taken".

     Ranged attacks are deliberately absent. They are a different stat with
     its own message ids (352 / 353 / 354), and pooling the two would answer
     a question nobody asked.

     THE PACKET'S CATEGORY IS DELIBERATELY NOT READ, which is a deviation
     from this repo's other two `0x028` readers (`lib/skillchain` and the
     target bar's cast tracker both switch on it). The four ids above are
     melee-specific on their own, so the category could only ever narrow a
     set that is already narrow - and it would do so against a constant
     nobody here has verified in a client, where being wrong means the row
     silently never moves. An unread fact must not disable a feature; the
     worst a missing gate can do is count a swing that was already a swing.

     THE SAMPLE IS SMALL and that is inherent: the shipped thirty seconds is
     eight or ten swings single-wield, and fifteen was four or five. The hit
     and swing counts ride alongside the percentage for exactly that reason -
     a reader can see how much the number is worth - and the window is
     config.

     THE DELAY IS MEASURED BESIDE IT, never computed. Nothing in the client
     reports your haste: gear haste is only in item description text, and a
     march's potency depends on the singer's skill, instrument and gear,
     which your client cannot see at all - so an effective delay worked out
     from the pieces would have its largest term guessed. The interval the
     rounds actually arrive at needs none of that. ONE PACKET IS ONE ROUND,
     however many swings it carries, and the MEDIAN gap is what is reported,
     since a weaponskill, a cast or a step out of range inserts a long gap.
     HOW MUCH THAT BUYS DEPENDS ON THE WINDOW, which is half of why the
     shipped one is thirty seconds: at a four-second delay that is six or
     seven gaps, enough for the median to shrug off an interruption. At the
     fifteen it shipped at there were two or three, and the median of an
     even pair is their mean, so one weaponskill still moved it. A round in
     which every swing was parried is invisible here (no countable swing, so
     no round), which lengthens one gap - the median absorbs it.

     No Windower here: `now` is passed in, so the whole thing is a pure
     function of what it has been told. ]]

-- scoreboard's melee message ids. A hit and a crit; both misses.
local HIT = { [1] = true, [67] = true }
local MISS = { [15] = true, [63] = true }

local DEFAULT_WINDOW = 30
-- Every swing inside the window is held, so the window is bounded: ten
-- minutes of a multi-attack job is already far past what a reading is for,
-- and a window nothing prunes is a list that grows for the session.
local MAX_WINDOW = 600

local function new(config)
  local self = {}

  -- The window, oldest first, plus the running tallies over it. The tallies
  -- are maintained on the way in and out rather than summed per frame: this
  -- is read every frame and pushed to only when the numbers move.
  local swings = {}
  local head = 1
  local tail = 0
  local hits = 0
  local total = 0
  -- When each ROUND landed, oldest first: one entry per packet that carried
  -- a countable swing, pruned against the same window.
  local rounds = {}
  local rounds_head = 1
  local rounds_tail = 0
  -- The last median, and the state it was computed from. `sample` is called
  -- every frame and a 600-second window on a dual-wielding job holds a few
  -- hundred gaps: sorting those sixty times a second for a number that
  -- moves when a round lands is exactly what the tallies above avoid.
  local delay_cached = nil
  local delay_state = nil

  function self.set_config(new_config)
    config = new_config
  end

  --[[ The window in seconds. A hand-edited config is a file like any other,
       so a value this could not use is refused here rather than believed -
       and the fallback lives with the reader, so nothing can report a length
       that is not the one in force. ]]
  function self.window()
    local settings = type(config) == "table" and config or {}
    local seconds = tonumber(settings.window_seconds)
    if not seconds or seconds <= 0 or seconds > MAX_WINDOW then
      return DEFAULT_WINDOW
    end
    return seconds
  end

  -- The longest window it will hold, so the CLI can refuse exactly what this
  -- would otherwise fall back over rather than naming a bound of its own.
  function self.max_window()
    return MAX_WINDOW
  end

  function self.reset()
    swings = {}
    head, tail = 1, 0
    hits, total = 0, 0
    rounds = {}
    rounds_head, rounds_tail = 1, 0
    delay_cached, delay_state = nil, nil
  end

  local function record(hit, at)
    tail = tail + 1
    swings[tail] = { at = at, hit = hit }
    total = total + 1
    if hit then
      hits = hits + 1
    end
  end

  --[[ One parsed `0x028`. Only the player's own swings count - a pet has its
       own actor id, so it is excluded by the same test - and only the
       action's own `message`: an added effect rides a different field, which
       is why scoreboard reads the main one alone.

       Every guard here is against the client rather than against a caller:
       `parse_action` is pcall'd in the entry point, so a packet it could not
       read arrives as nil, and Lua's nil-tolerance would otherwise turn a
       half-decoded one into a silent error sixty times a second. ]]
  function self.on_action(action, player_id, now)
    if type(action) ~= "table" or player_id == nil or action.actor_id ~= player_id then
      return
    end
    if type(action.targets) ~= "table" then
      return
    end
    local counted = 0
    for _, target in ipairs(action.targets) do
      if type(target) == "table" and type(target.actions) == "table" then
        for _, swing in ipairs(target.actions) do
          local message = type(swing) == "table" and swing.message or nil
          if HIT[message] then
            record(true, now)
            counted = counted + 1
          elseif MISS[message] then
            record(false, now)
            counted = counted + 1
          end
        end
      end
    end
    if counted > 0 then
      rounds_tail = rounds_tail + 1
      rounds[rounds_tail] = now
    end
  end

  -- Drops everything strictly older than the window. A swing sitting exactly
  -- on the edge is inside it.
  local function prune(now)
    local window = self.window()
    while head <= tail and now - swings[head].at > window do
      if swings[head].hit then
        hits = hits - 1
      end
      total = total - 1
      swings[head] = nil
      head = head + 1
    end
    while rounds_head <= rounds_tail and now - rounds[rounds_head] > window do
      rounds[rounds_head] = nil
      rounds_head = rounds_head + 1
    end
    if head > tail and rounds_head > rounds_tail then
      -- Emptied: start the arithmetic over rather than let the indices climb
      -- for the length of a session.
      self.reset()
    end
  end

  --[[ The median interval between the rounds still in the window. Two rounds
       are the minimum - one gap - and there is deliberately no smoothing
       beyond the median: a number that lags the fight it is measuring would
       be worse than one that moves. ]]
  local function measured_delay()
    if rounds_tail - rounds_head < 1 then
      return nil
    end
    -- Which rounds are in the window is the whole of the input, so the two
    -- ends of the deque say whether the answer can have changed.
    local state = rounds_head .. ":" .. rounds_tail
    if state == delay_state then
      return delay_cached
    end
    local gaps = {}
    for index = rounds_head + 1, rounds_tail do
      local gap = rounds[index] - rounds[index - 1]
      -- Two packets at the same instant are not a round apart, and a zero
      -- in the median would be a claim rather than an admission.
      if gap > 0 then
        gaps[#gaps + 1] = gap
      end
    end
    delay_state = state
    if #gaps == 0 then
      delay_cached = nil
      return nil
    end
    table.sort(gaps)
    local middle = #gaps / 2
    if #gaps % 2 == 1 then
      delay_cached = gaps[math.ceil(middle)]
    else
      delay_cached = (gaps[middle] + gaps[middle + 1]) / 2
    end
    return delay_cached
  end

  --[[ What the window holds right now. `percent` is nil rather than zero
       when nothing is in it: no swings is not 0% accuracy, and the widget
       draws the difference. ]]
  function self.sample(now)
    prune(now)
    local percent = nil
    if total > 0 then
      percent = math.floor((hits / total) * 100 + 0.5)
    end
    return { hits = hits, swings = total, percent = percent, delay = measured_delay() }
  end

  return self
end

return new
