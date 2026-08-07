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

--[[ Pure parsers for the four incoming packets the party list listens to.

     Bytes and already-parsed field tables in, plain Lua tables out; nothing
     here touches Windower. The entry point runs `packets.parse('incoming', …)`
     for 0x0C8 / 0x0DD / 0x0DF and hands the result on. 0x076 is decoded from
     the raw string here instead -- Windower does define it
     (`fields.incoming[0x076]`, verified against `Windower/Lua@dev` on
     2026-08-06), but as an opaque `data[8]` bit mask beside a `data[32]` blob,
     so the bit arithmetic below is ours either way.

     Offsets are 1-based, matching string.byte, so the packet body that starts
     at byte offset 4 starts at index 5. ]]

local MAX_BUFFS = 32
local BUFF_BLOCKS = 5
local BUFF_BLOCK_SIZE = 48
local BUFF_BODY_START = 5
local EMPTY_BUFF = 255
local ALLIANCE_MEMBERS = 18

local M = {}

M.ALLIANCE = 0x0C8
M.PARTY_MEMBER = 0x0DD
M.CHAR = 0x0DF
M.PARTY_BUFFS = 0x076

local function uint32_le(raw, offset)
  local b1, b2, b3, b4 = raw:byte(offset, offset + 3)
  if not b4 then
    return nil
  end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

--[[ 0x076: five 48-byte blocks of `player id` + 32 buff ids, each id split
     into a low byte at +16+i-1 and a 2-bit high part packed four to a byte
     from +8. Credit for the bit layout: Kenshi (PartyBuffs) and Byrth
     (GearSwap), via XIVParty.

     The main player is never in this packet, and neither is anyone outside the
     main party -- which is why the alliance rows have no buff icons. ]]
function M.party_buffs(raw)
  local by_id = {}
  if type(raw) ~= "string" or #raw < BUFF_BODY_START + BUFF_BLOCKS * BUFF_BLOCK_SIZE - 1 then
    return by_id
  end

  for block = 0, BUFF_BLOCKS - 1 do
    local base = block * BUFF_BLOCK_SIZE + BUFF_BODY_START
    local id = uint32_le(raw, base)
    -- Slot 0 is an unoccupied block, not a player.
    if id and id ~= 0 then
      local buffs = {}
      for index = 1, MAX_BUFFS do
        local high = math.floor(raw:byte(base + 8 + math.floor((index - 1) / 4)) / 4 ^ ((index - 1) % 4)) % 4
        local buff = raw:byte(base + 16 + index - 1) + 256 * high
        if buff ~= EMPTY_BUFF then
          buffs[#buffs + 1] = buff
        end
      end
      by_id[id] = buffs
    end
  end

  return by_id
end

--[[ 0x0C8: eighteen alliance slots of id + flags. Bit 4 is the party leader,
     8 the alliance leader, 16 the quartermaster; the rest are not ours. ]]
function M.alliance_flags(parsed)
  local roles = {}
  if type(parsed) ~= "table" then
    return roles
  end

  for slot = 1, ALLIANCE_MEMBERS do
    local id = parsed["ID " .. slot]
    local flags = parsed["Flags " .. slot]
    if type(id) == "number" and id > 0 and type(flags) == "number" then
      roles[id] = {
        leader = flags % 8 >= 4,
        alliance_leader = flags % 16 >= 8,
        quartermaster = flags % 32 >= 16,
      }
    end
  end

  return roles
end

--[[ The job fields hold non-zero garbage while the member is out of zone, and
     are non-zero for a character with no subjob as well. A zero main level is
     the one reliable tell, so the whole block is dropped rather than half of
     it -- XIVParty's rule, and for the same reason. ]]
local function job_block(parsed)
  local main, main_level = parsed["Main job"], parsed["Main job level"]
  local sub, sub_level = parsed["Sub job"], parsed["Sub job level"]
  if not (main and main_level and sub and sub_level) or main_level <= 0 then
    return nil
  end
  return { main = main, main_level = main_level, sub = sub, sub_level = sub_level }
end

--[[ TP is deliberately absent from `vitals`. Windower's field definition tags
     0x0DD/0x0DF TP with its `percent` formatter, while get_party() reports TP
     on a 0..3000 scale, and nothing available here settles which scale the
     packet actually carries. Pushing it on the wrong scale would fight the
     200ms poll five times a second, so TP comes from the poll alone until a
     live client says otherwise. HP and MP are unambiguous and are pushed. ]]
local function vitals_of(parsed, percent_hp, percent_mp)
  return {
    hp = parsed.HP,
    mp = parsed.MP,
    hpp = parsed[percent_hp],
    mpp = parsed[percent_mp],
  }
end

-- 0x0DD: a party member's identity, vitals and jobs.
function M.member_update(parsed)
  if type(parsed) ~= "table" or type(parsed.ID) ~= "number" or parsed.ID <= 0 then
    return nil
  end
  return {
    id = parsed.ID,
    index = parsed.Index,
    name = parsed.Name,
    zone = parsed.Zone,
    vitals = vitals_of(parsed, "HP%", "MP%"),
    job = job_block(parsed),
  }
end

-- 0x0DF: the same, without a name or a zone, and spelling the percents HPP/MPP.
function M.char_update(parsed)
  if type(parsed) ~= "table" or type(parsed.ID) ~= "number" or parsed.ID <= 0 then
    return nil
  end
  return {
    id = parsed.ID,
    index = parsed.Index,
    vitals = vitals_of(parsed, "HPP", "MPP"),
    job = job_block(parsed),
  }
end

return M
