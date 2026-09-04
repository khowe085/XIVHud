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

--[[ The status bar's predefined filters: which of XIV's three groups a buff
     belongs to. res.buffs carries no such field, so the two curated sets are
     transcribed from lib/buff_order.lua (XIVParty's ordering, BSD 3-clause
     (c) 2024 Tylas, derived from Windower's generated resources): DEBUFFS is
     its "debuffs / negative effects" section in full, and OTHER is the run of
     sections at its tail that are neither a spell nor an ability on you -
     restrictions and costumes, crafting imagery, EXP/CP bonuses, food and
     the mount, the signets, battlefield and instance markers, Ballista, zone
     buffs, the 72-hour boosts and the unused ids. Everything else is an
     enhancement, an unranked id included: a buff nobody has categorised is
     still something on you, and the all-bar shows it either way.

     Two calls made while curating: movement speed (Flee, quickening) stays an
     enhancement, being something you did rather than something the system
     did to you; and the stances, avatar favours and REMA aftermaths stay
     enhancements too, since each is the effect of an action. ]]

local M = {}

M.NAMES = { "all", "enhancements", "debuffs", "other" }

local function set(list)
  local out = {}
  for _, id in ipairs(list) do
    out[id] = true
  end
  return out
end

M.DEBUFFS = set({
  -- common debuffs
  0,
  1,
  15,
  632,
  633,
  14,
  17,
  2,
  19,
  10,
  28,
  11,
  12,
  567,
  177,
  13,
  565,
  3,
  540,
  630,
  4,
  566,
  5,
  156,
  6,
  29,
  7,
  18,
  8,
  31,
  9,
  20,
  631,
  16,
  21,
  22,
  30,
  299,
  473,
  575,
  576,
  -- dots
  128,
  129,
  130,
  131,
  132,
  133,
  134,
  135,
  186,
  23,
  -- song debuffs
  192,
  193,
  194,
  217,
  -- downs
  146,
  561,
  147,
  557,
  148,
  562,
  149,
  558,
  174,
  563,
  175,
  559,
  404,
  564,
  167,
  560,
  298,
  572,
  144,
  145,
  189,
  168,
  -- attribute downs
  136,
  137,
  138,
  139,
  140,
  141,
  142,
  -- pathos
  258,
  259,
  260,
  261,
  262,
  263,
  264,
})

M.OTHER = set({
  -- restrictions / costumes
  284,
  127,
  585,
  155,
  143,
  157,
  269,
  -- crafting / HELM
  235,
  236,
  237,
  238,
  239,
  240,
  241,
  242,
  243,
  578,
  -- exp/cp
  249,
  579,
  -- food / mount
  250,
  251,
  252,
  -- signets
  253,
  256,
  268,
  512,
  -- battlefields / instances
  254,
  257,
  267,
  510,
  511,
  475,
  276,
  285,
  292,
  627,
  -- ballista
  160,
  158,
  159,
  161,
  162,
  -- zone buffs
  287,
  602,
  603,
  506,
  -- 72hr buffs
  481,
  629,
  618,
  -- unused
  24,
  25,
  26,
  27,
  224,
  225,
  226,
  232,
})

function M.category_of(id)
  if M.DEBUFFS[id] then
    return "debuffs"
  end
  if M.OTHER[id] then
    return "other"
  end
  return "enhancements"
end

-- One predicate per category, built once: `keep` is asked on every plan.
local KEEP = {}
for _, name in ipairs({ "enhancements", "debuffs", "other" }) do
  KEEP[name] = function(id)
    return M.category_of(id) == name
  end
end

-- The predicate lib/buffs applies before a bar's own list; nil for `all`,
-- which restricts nothing, and for a name that is not a filter at all.
function M.keep(name)
  return KEEP[name]
end

return M
