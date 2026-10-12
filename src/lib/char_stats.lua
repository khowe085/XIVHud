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

--[[ The last 0x061 (character stats) per character and MAIN job, in memory
     and on disk (Kevin, 2026-10-12). The client sends it on a zone, a level
     change and a job change - never on request - so after a login or a
     `//lua reload` everything that reads it (the exp bar's numbers, the
     binder's master level) had nothing until the player zoned. It also comes
     far more often than that, carrying gear-driven stats too (see
     `significant`). A cached copy
     stands in for a live one until the next real packet replaces it, stale
     experience and all: that was the call.

     Keyed by the job the packet itself names - its Main Job byte at offset
     0x0C, numbered as `res.jobs` numbers them, which is jobchange.JOBS's
     order - since the packet describes that job's levels and experience.
     Stored as HEX text under cache/packets/<Character>/, beside the item
     icon cache and for the same reason it is not under data/ (`//hud copy`
     and `//hud reset` must never touch it): hex because a text-mode read on
     Windows turns 0x0D 0x0A into one byte and stops at 0x1A. ]]

local JOBS = require("lib/actionbar/jobchange").JOBS

local ROOT = "cache/packets/"
local MAIN_JOB_BYTE = 0x0C + 1

--[[ What anything reads off the packet, by offset: the job pair and levels
     and the EXP (0x0C-0x13), the master level (0x65), Master Breaker (bit 0 of
     0x66 - the other 15 bits are junk) and the exemplar points (0x68-0x6F).
     The rest - max HP and MP, the added stats, attack, defence - moves with
     gear and buffs, and likely makes the packet frequent (GearSwap reads max
     HP off it, which suggests one per gear change - unverified), so only a
     change here earns a disk write. ]]
local function significant(bytes)
  local breaker = bytes:byte(0x66 + 1)
  return bytes:sub(0x0C + 1, 0x13 + 1)
    .. bytes:sub(0x65 + 1, 0x65 + 1)
    .. (breaker ~= nil and tostring(breaker % 2) or "")
    .. bytes:sub(0x68 + 1, 0x6F + 1)
end

local function job_of(bytes)
  if type(bytes) ~= "string" or #bytes < MAIN_JOB_BYTE then
    return nil
  end
  return JOBS[bytes:byte(MAIN_JOB_BYTE)]
end

local function encode(bytes)
  return (bytes:gsub(".", function(char)
    return ("%02X"):format(char:byte())
  end))
end

local function decode(text)
  if type(text) ~= "string" or #text == 0 or #text % 2 ~= 0 or text:find("[^%x]") then
    return nil
  end
  return (text:gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

local function new(deps)
  deps = deps or {}
  local self = {}
  -- character -> job -> bytes, or false where the disk was asked and had none.
  local known = {}
  -- character -> job -> the significant fields last put on disk.
  local written = {}
  --[[ A packet names no character, so whose it is comes from WHEN it arrived
       (Kevin, 2026-10-12): `scoped` is who core has scoped, `pending` a packet
       that arrived with nobody to name, for the next character scoped. The
       client's own leftover packet is trusted only for the character logged
       in when the addon loaded (`trust_leftover`), and only until the first
       change of character after that - by then it may be the outgoing one's. ]]
  local scoped, pending, scopes, first_scoped = nil, nil, 0, nil
  local trust_leftover = deps.trust_leftover ~= false

  -- Before core has scoped anyone there is no name to hold it to; after,
  -- only the first character scoped, and only until the next change.
  local function trusted(character)
    if not trust_leftover then
      return false
    end
    return scopes == 0 or (scopes == 1 and character == first_scoped)
  end

  local function path(character, job)
    return ROOT .. character .. "/0x061_" .. job .. ".txt"
  end

  -- The name becomes a path segment, so anything but a plain word is refused.
  local function plain(character)
    return type(character) == "string" and character:find("^%w+$") ~= nil
  end

  local function remember(character, job, bytes)
    known[character] = known[character] or {}
    known[character][job] = bytes
    written[character] = written[character] or {}
    local key = significant(bytes)
    if written[character][job] ~= key and deps.write ~= nil then
      -- pcall'd here rather than at each caller: the exp bar's attach and the
      -- binder's catalog reach this through `current`. Marked written only
      -- once it landed, so a failed write is tried again on the next packet.
      local ok, wrote = pcall(deps.write, path(character, job), encode(bytes))
      if ok and wrote ~= false then
        written[character][job] = key
      end
    end
  end

  --- A live 0x061, filed under the job it names.
  function self.store(character, bytes)
    local job = job_of(bytes)
    if not plain(character) or job == nil then
      return
    end
    remember(character, job, bytes)
  end

  --- A live 0x061, as it arrives: filed under `observed` (the name the
  --- client reports right now) or the scoped character, else held.
  function self.arrived(bytes, observed)
    local owner = plain(observed) and observed or scoped
    if owner ~= nil then
      self.store(owner, bytes)
    elseif job_of(bytes) ~= nil then
      pending = bytes
    end
  end

  --- Who core has scoped, nil at a logout: a held packet is the incoming
  --- character's, and a logout drops it.
  function self.scope(name)
    scopes = scopes + 1
    scoped = plain(name) and name or nil
    if scopes == 1 then
      first_scoped = scoped
    end
    if scoped ~= nil and pending ~= nil then
      self.store(scoped, pending)
    end
    pending = nil
  end

  --- The packet for a character's job: `live` (the client's own last one)
  --- where it is for that job and can still be trusted, else what was
  --- stored, else nil.
  function self.current(character, job, live)
    -- No key to file it under: the live packet is still the best answer,
    -- where it can be trusted at all.
    if not plain(character) or type(job) ~= "string" then
      return trusted(character) and live or nil
    end
    if live ~= nil and trusted(character) and job_of(live) == job then
      remember(character, job, live)
      return live
    end
    known[character] = known[character] or {}
    local held = known[character][job]
    if held == nil then
      held = deps.read ~= nil and decode(deps.read(path(character, job))) or nil
      known[character][job] = held or false
      if held then
        written[character] = written[character] or {}
        written[character][job] = significant(held)
      end
    end
    return held or nil
  end

  return self
end

return new
