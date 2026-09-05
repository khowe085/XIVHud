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

--[[ The one packet the status bar reads: 0x063, order 0x09, the client's
     list of your buffs WITH their expiry times - the only place a duration
     is ever reported (get_player().buffs and 0x076 carry ids alone).

     It arrives here already decoded: the packet id has three readers (the
     crossbar's skillchain engine for this order's ids, expbar for order 2,
     and this), so the entry point parses it ONCE through Windower's
     packets.parse and dispatches the table, the rule every multi-reader id
     follows. That parser's field definition for 0x063 switches on the order
     byte and, for order 9 (verified against Windower/Lua@dev
     packets/fields.lua on 2026-09-04), reads

       Buffs  unsigned short[32]  fn=buff       -- 0x08
       Time   unsigned int[32]    fn=bufftime   -- 0x48

     which packets.parse stores raw under the labels `Buffs 1`..`Buffs 32`
     and `Time 1`..`Time 32` (its `fn` formatters run only when a packet is
     printed - verified in packets.lua the same day). This module turns those
     into `{ id = , expires = }` pairs; the timestamp decode is Windower's,
     verbatim:

       bufftime = function(ts)
         return fn(1009810800 + (ts / 60) + 0x100000000 / 60 * 10)
           -- increment last number every 2.27 years
       end

     so the raw value is 60ths of a second since 2002-01-01 JST, wrapped at
     32 bits. Windower hardcodes the wrap count and bumps it by hand; here the
     wrap is resolved against the clock instead - the multiple that lands the
     expiry nearest to now - which needs no bump, since nothing on you lasts
     a fraction of the 2.27-year period.

     UNVERIFIED in a live client, and read defensively: the empty-slot marker
     in the id array (0xFF and 0xFFFF are both taken as empty; KO is the real
     id 0 and is kept), and what Time holds for a buff with no expiry. A raw
     0 or 0xFFFFFFFF is answered as `expires = false` - no expiry - rather
     than decoded: on the nearest wrap either lands on a fixed date, which
     for a few days every 2.27 years would sit inside the plausible band and
     count down under a timerless buff. Whatever else the client may send
     there, logic.lua draws no timer for an expiry that has passed or that
     sits implausibly far off. ]]

local M = {}

M.BUFF_DURATIONS = 0x063

local DURATIONS_ORDER = 0x09
local EPOCH = 1009810800
local PERIOD = 2 ^ 32 / 60
local SLOTS = 32

local EMPTY = { [0xFF] = true, [0xFFFF] = true }
local NO_EXPIRY = { [0] = true, [0xFFFFFFFF] = true }

-- The unix expiry a raw timestamp means, on the wrap nearest to `now`.
function M.expiry(raw, now)
  local base = EPOCH + raw / 60
  local wraps = math.floor((now - base) / PERIOD + 0.5)
  return base + wraps * PERIOD
end

-- The occupied slots in order, each `{ id = , expires = }` with `expires`
-- false where the slot carries no timestamp; nil for another order of 0x063,
-- a parse that failed, or a table without the arrays. A slot the parse did
-- not fill ends the walk rather than erroring.
function M.buff_durations(parsed, now)
  if type(parsed) ~= "table" or parsed.Order ~= DURATIONS_ORDER then
    return nil
  end
  if type(parsed["Buffs 1"]) ~= "number" then
    return nil
  end

  local list = {}
  for slot = 1, SLOTS do
    local id = parsed["Buffs " .. slot]
    local raw = parsed["Time " .. slot]
    if type(id) ~= "number" or type(raw) ~= "number" then
      break
    end
    if not EMPTY[id] then
      list[#list + 1] = { id = id, expires = not NO_EXPIRY[raw] and M.expiry(raw, now) }
    end
  end
  return list
end

return M
