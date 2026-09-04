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

     Decoded from the raw bytes here. The packet id has other readers - the
     crossbar's skillchain engine, a transcription of the SkillChains addon,
     reads this order's id array alone off the same raw bytes to know which
     of your buffs affect a chain, and expbar reads order 2 (limit points
     and merits) - so by the entry point's rule (one decode for an id with
     more than one reader) this SHOULD be pre-parsed there. It is
     not, yet: the crossbar's decode is inside the transcribed module and
     takes raw data, so sharing one parse means rewiring it, which is
     deferred as an open item rather than done in the status bar's own
     change. Layout verified against Windower/Lua@dev packets/fields.lua on
     2026-09-04:

       fields.incoming[0x063] switches on data:byte(5)      -- offset 0x04
       [0x09] = { _unknown1 const 0x00C4                     -- 0x06
                  Buffs  unsigned short[32]  fn=buff         -- 0x08
                  Time   unsigned int[32]    fn=bufftime }   -- 0x48

     and the timestamp decode, verbatim:

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
     in this packet's id array (0xFF and 0xFFFF are both taken as empty; KO is
     the real id 0 and is kept), and what Time holds for a buff with no
     expiry. A raw 0 or 0xFFFFFFFF is answered as `expires = false` - no
     expiry - rather than decoded: on the nearest wrap either lands on a
     fixed date, which for a few days every 2.27 years would sit inside the
     plausible band and count down under a timerless buff. Whatever else the
     client may send there, logic.lua draws no timer for an expiry that has
     passed or that sits implausibly far off. ]]

local M = {}

M.BUFF_DURATIONS = 0x063

local DURATIONS_ORDER = 0x09
local EPOCH = 1009810800
local PERIOD = 2 ^ 32 / 60
local SLOTS = 32
-- 1-based string offsets of the two arrays, and the length that holds both.
local IDS_AT = 0x08 + 1
local TIMES_AT = 0x48 + 1
local LENGTH = 0x48 + SLOTS * 4

local EMPTY = { [0xFF] = true, [0xFFFF] = true }
local NO_EXPIRY = { [0] = true, [0xFFFFFFFF] = true }

local function u16(data, at)
  local low, high = data:byte(at, at + 1)
  return low + high * 256
end

local function u32(data, at)
  local a, b, c, d = data:byte(at, at + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- The unix expiry a raw timestamp means, on the wrap nearest to `now`.
function M.expiry(raw, now)
  local base = EPOCH + raw / 60
  local wraps = math.floor((now - base) / PERIOD + 0.5)
  return base + wraps * PERIOD
end

-- The occupied slots in order, each `{ id = , expires = }` with `expires`
-- false where the slot carries no timestamp; nil for another order of 0x063
-- or a packet too short to hold the arrays.
function M.parse_buff_durations(data, now)
  if type(data) ~= "string" or #data < LENGTH then
    return nil
  end
  if data:byte(5) ~= DURATIONS_ORDER then
    return nil
  end

  local list = {}
  for slot = 0, SLOTS - 1 do
    local id = u16(data, IDS_AT + slot * 2)
    if not EMPTY[id] then
      local raw = u32(data, TIMES_AT + slot * 4)
      list[#list + 1] = { id = id, expires = not NO_EXPIRY[raw] and M.expiry(raw, now) }
    end
  end
  return list
end

return M
