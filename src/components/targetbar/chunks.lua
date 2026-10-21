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

--[[ The two packets that say a mob is gone for good, decoded from the raw
     bytes - each has too few readers to be worth a pre-parse in the entry
     point. Shared by the treasure hunter tracker and the focus bar, which
     both forget a mob on its despawn and on a zone - each on more besides,
     which stays its own. ]]

local ZONE_IN = 0x00A
local ANIMATION = 0x038

-- The despawn animation 0x038 names.
local DESPAWN = "kesu"

-- 1-based offsets into the raw chunk, header included: fields.lua's 0x04 for
-- the id and 0x0C for the animation name.
local ID_OFFSET = 5
local ANIMATION_OFFSET = 13

local chunks = {}

function chunks.u32(raw, offset)
  local b1, b2, b3, b4 = raw:byte(offset, offset + 3)
  if not b4 then
    return nil
  end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

function chunks.zoned(id)
  return id == ZONE_IN
end

-- The id of the mob a chunk despawns, or nil when it despawns none.
function chunks.despawned(id, raw)
  if id ~= ANIMATION or type(raw) ~= "string" then
    return nil
  end
  local mob = chunks.u32(raw, ID_OFFSET)
  if mob and raw:sub(ANIMATION_OFFSET, ANIMATION_OFFSET + 3) == DESPAWN then
    return mob
  end
  return nil
end

return chunks
