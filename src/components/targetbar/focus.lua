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

--[[ The focus target: the one mob `//hud targetbar focus` names, held by id
     for the session and never saved. Pure, as th.lua is: the widget hands it
     the mobs the client answers and the chunks the dispatch carries.

     Death ends a focus for good, a player's KO included (Kevin, 2026-10-20),
     and so does the client no longer having the mob, a zone or its despawn.
     A mob the client merely will not let be targeted - out of draw range -
     draws nothing and keeps the focus. ]]

local chunks = require("components/targetbar/chunks")

-- The tokens `focus` takes in place of a name, as the client's own target
-- lookup spells them, in the order a reply lists them.
local TOKEN_WORDS = { "t", "st", "bt" }
local TOKENS = {}
for _, word in ipairs(TOKEN_WORDS) do
  TOKENS["<" .. word .. ">"] = word
end

-- The mob table's status values for a mob lying dead.
local DEAD_STATUS = { [2] = true, [3] = true }

local function alive(mob)
  return tonumber(mob.hpp) ~= 0 and not DEAD_STATUS[mob.status]
end

local function focusable(mob)
  return type(mob) == "table" and mob.id ~= nil and mob.valid_target ~= false and alive(mob)
end

-- An unknown distance ranks behind every one the client measured.
local function distance_of(mob)
  return tonumber(mob.distance) or math.huge
end

local function new()
  local self = {}
  local id = nil
  local name = nil

  function self.id()
    return id
  end

  function self.name()
    return name
  end

  function self.clear()
    id, name = nil, nil
  end

  -- The client's word for a token typed in place of a name, or nil for a name.
  function self.token(word)
    return TOKENS[word:lower()]
  end

  -- A word in angle brackets that is not one of the tokens. No mob's name is
  -- wrapped in them, so searching for one by name could only ever miss.
  function self.unknown_token(word)
    return word:match("^<.*>$") ~= nil and TOKENS[word:lower()] == nil
  end

  function self.tokens()
    local listed = {}
    for index, word in ipairs(TOKEN_WORDS) do
      listed[index] = "<" .. word .. ">"
    end
    return listed
  end

  --[[ Holds `mob` when it can be focused, named `typed` if it carries no name
       of its own. Answers whether it did; a refusal keeps what was held. ]]
  function self.take(mob, typed)
    if not focusable(mob) then
      return false
    end
    id = mob.id
    name = type(mob.name) == "string" and mob.name or typed
    return true
  end

  --[[ The mob whose whole name is `wanted`, in any case: `target` when it is
       one (Kevin, 2026-10-20 - the mob you are looking at is the one you
       mean, and it holds if the client ever hands `<t>` over as a name),
       otherwise the nearest such mob in `array`, since several routinely
       share one name. Never a part of a name: a short word must not grab
       the wrong mob. ]]
  function self.find(wanted, target, array)
    wanted = wanted:lower()
    local function named(mob)
      return focusable(mob) and type(mob.name) == "string" and mob.name:lower() == wanted
    end
    if named(target) then
      return target
    end
    local best = nil
    for _, mob in pairs(array or {}) do
      if named(mob) and (best == nil or distance_of(mob) < distance_of(best)) then
        best = mob
      end
    end
    return best
  end

  --[[ What to draw this frame, given what the client answers for the held id:
       the mob, or nil. A mob that is gone or dead lets the focus go; one that
       cannot be targeted only draws nothing. ]]
  function self.resolve(mob)
    if id == nil then
      return nil
    end
    if type(mob) ~= "table" or not alive(mob) then
      self.clear()
      return nil
    end
    if mob.valid_target == false then
      return nil
    end
    return mob
  end

  function self.on_chunk(chunk_id, raw)
    if chunks.zoned(chunk_id) or (id ~= nil and chunks.despawned(chunk_id, raw) == id) then
      self.clear()
    end
  end

  return self
end

return new
