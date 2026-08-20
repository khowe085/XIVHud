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

--[[ Pure slot counters: SCH stratagem charges and NIN/COR tool counts, both
     drawn in a slot's cost position (never both at once - a ninjutsu is not
     a stratagem ability). The tool lookup tables and the stratagem list are
     transcribed from xivcrossbar's consumables.lua (MIT (c) 2020
     AliekberFFXI - full notice text in this component's assets/LICENSE.txt);
     the stratagem mechanics come from a fork of the same repository
     (its own addition, under that repository's notices), with its display
     bug fixed: the fork left the JP gift out of the minuend and could print
     -1 with all six charges spent.

     Everything keyed to a job resolves main AND sub (the /SCH lesson: the
     fork read the SCH level from the main job only, so RDM/SCH never drew);
     everything keyed to job points or master tools resolves main ONLY. ]]

local counters = {}

-- The sixteen abilities that consume a stratagem charge. Light Arts and Dark
-- Arts are deliberately absent - they cost nothing.
local STRATAGEM_ABILITIES = {
  ["addendum: white"] = true,
  ["addendum: black"] = true,
  ["penury"] = true,
  ["celerity"] = true,
  ["accession"] = true,
  ["rapture"] = true,
  ["altruism"] = true,
  ["tranquility"] = true,
  ["perpetuance"] = true,
  ["parsimony"] = true,
  ["alacrity"] = true,
  ["manifestation"] = true,
  ["ebullience"] = true,
  ["focalization"] = true,
  ["equanimity"] = true,
  ["immanence"] = true,
}

-- Seconds for the shared pool (ability recast id 231) to return one charge,
-- by total charge count.
local CHARGE_TIME = { [1] = 240, [2] = 120, [3] = 80, [4] = 60, [5] = 48, [6] = 33 }

-- Ninjutsu spell id -> the tool it consumes.
local NINJA_TOOL_LOOKUP = {
  [318] = 2553, -- Monomi: Ichi -> Sanjaku-Tenugui
  [319] = 2555, -- Aisha: Ichi -> Soshi
  [320] = 1161, -- Katon: Ichi -> Uchitake
  [321] = 1161, -- Katon: Ni -> Uchitake
  [322] = 1161, -- Katon: San -> Uchitake
  [323] = 1164, -- Hyoton: Ichi -> Tsurara
  [324] = 1164, -- Hyoton: Ni -> Tsurara
  [325] = 1164, -- Hyoton: San -> Tsurara
  [326] = 1167, -- Huton: Ichi -> Kawahori-Ogi
  [327] = 1167, -- Huton: Ni -> Kawahori-Ogi
  [328] = 1167, -- Huton: San -> Kawahori-Ogi
  [329] = 1170, -- Doton: Ichi -> Makibishi
  [330] = 1170, -- Doton: Ni -> Makibishi
  [331] = 1170, -- Doton: San -> Makibishi
  [332] = 1173, -- Raiton: Ichi -> Hiraishin
  [333] = 1173, -- Raiton: Ni -> Hiraishin
  [334] = 1173, -- Raiton: San -> Hiraishin
  [335] = 1176, -- Suiton: Ichi -> Mizu-Deppo
  [336] = 1176, -- Suiton: Ni -> Mizu-Deppo
  [337] = 1176, -- Suiton: San -> Mizu-Deppo
  [338] = 1179, -- Utsusemi: Ichi -> Shihei
  [339] = 1179, -- Utsusemi: Ni -> Shihei
  [340] = 1179, -- Utsusemi: San -> Shihei
  [341] = 1182, -- Jubaku: Ichi -> Jusatsu
  [342] = 1182, -- Jubaku: Ni -> Jusatsu
  [343] = 1182, -- Jubaku: San -> Jusatsu
  [344] = 1185, -- Hojo: Ichi -> Kaginawa
  [345] = 1185, -- Hojo: Ni -> Kaginawa
  [346] = 1185, -- Hojo: San -> Kaginawa
  [347] = 1188, -- Kurayami: Ichi -> Sairui-Ran
  [348] = 1188, -- Kurayami: Ni -> Sairui-Ran
  [349] = 1188, -- Kurayami: San -> Sairui-Ran
  [350] = 1191, -- Dokumori: Ichi -> Kodoku
  [351] = 1191, -- Dokumori: Ni -> Kodoku
  [352] = 1191, -- Dokumori: San -> Kodoku
  [353] = 1194, -- Tonko: Ichi -> Shinobi-Tabi
  [354] = 1194, -- Tonko: Ni -> Shinobi-Tabi
  [505] = 8803, -- Gekka: Ichi -> Ranka
  [506] = 8804, -- Yain: Ichi -> Furusumi
  [507] = 2642, -- Myoshu: Ichi -> Kabenro
  [508] = 2643, -- Yurin: Ichi -> Jinko
  [509] = 2644, -- Kakka: Ichi -> Ryuno
  [510] = 2970, -- Migawari: Ichi -> Mokujin
}

-- Corsair Quick Draw shot (lowercased ability name) -> its card.
local ABILITY_TOOL_LOOKUP = {
  ["fire shot"] = 2176,
  ["ice shot"] = 2177,
  ["wind shot"] = 2178,
  ["earth shot"] = 2179,
  ["thunder shot"] = 2180,
  ["water shot"] = 2181,
  ["light shot"] = 2182,
  ["dark shot"] = 2183,
}

-- Plain tool -> the master tool that substitutes for its whole family.
local MASTER_TOOL_LOOKUP = {
  [1179] = 2972, -- Shihei -> Shikanofuda
  [1194] = 2972, -- Shinobi-Tabi -> Shikanofuda
  [2553] = 2972, -- Sanjaku-Tenugui -> Shikanofuda
  [2642] = 2972, -- Kabenro -> Shikanofuda
  [8804] = 2972, -- Furusumi -> Shikanofuda
  [2970] = 2972, -- Mokujin -> Shikanofuda
  [8803] = 2972, -- Ranka -> Shikanofuda
  [2644] = 2972, -- Ryuno -> Shikanofuda
  [1182] = 2973, -- Jusatsu -> Chonofuda
  [1185] = 2973, -- Kaginawa -> Chonofuda
  [1191] = 2973, -- Kodoku -> Chonofuda
  [1188] = 2973, -- Sairui-Ran -> Chonofuda
  [2555] = 2973, -- Soshi -> Chonofuda
  [1173] = 2971, -- Hiraishin -> Inoshishinofuda
  [1167] = 2971, -- Kawahori-Ogi -> Inoshishinofuda
  [1170] = 2971, -- Makibishi -> Inoshishinofuda
  [1176] = 2971, -- Mizu-Deppo -> Inoshishinofuda
  [1164] = 2971, -- Tsurara -> Inoshishinofuda
  [1161] = 2971, -- Uchitake -> Inoshishinofuda
  [2176] = 2974, -- Fire Card -> Trump Card
  [2177] = 2974, -- Ice Card -> Trump Card
  [2178] = 2974, -- Wind Card -> Trump Card
  [2179] = 2974, -- Earth Card -> Trump Card
  [2180] = 2974, -- Thunder Card -> Trump Card
  [2181] = 2974, -- Water Card -> Trump Card
  [2182] = 2974, -- Light Card -> Trump Card
  [2183] = 2974, -- Dark Card -> Trump Card
}

-- Trump Card substitutes on main COR, every other master on main NIN.
-- Open in-client question: whether /COR actually burns master cards - the
-- fork's COR branch predates its master-tool gate, so the unified main-only
-- rule stands here unless the live check says otherwise.
local TRUMP_CARD = 2974

--- Whether a job ability consumes a stratagem charge (the count draws only
--- on these sixteen).
function counters.stratagem_ability(name)
  if type(name) ~= "string" then
    return false
  end
  return STRATAGEM_ABILITIES[name:lower()] == true
end

local function sch_level(player)
  -- Main and sub both resolve (the /SCH lesson); main wins when both carry
  -- SCH, which the game cannot produce anyway.
  if player.main_job == "SCH" then
    return player.main_job_level
  end
  if player.sub_job == "SCH" then
    return player.sub_job_level
  end
  return nil
end

--- Available and maximum stratagem charges, or nil when the counter draws
--- nothing at all (no SCH, or SCH below 10 - the formula's zero is not a
--- charge count, and CHARGE_TIME[0] does not exist).
function counters.stratagems(player, recast_231)
  if type(player) ~= "table" then
    return nil
  end
  local level = sch_level(player)
  if type(level) ~= "number" or level < 10 then
    return nil
  end
  local max = math.floor((level - 10) / 20) + 1
  -- The sixth charge is a job point gift: main SCH only - gifts require the
  -- main job.
  local points = player.main_job == "SCH" and player.job_points and player.job_points.sch
  if points and (points.jp_spent or 0) >= 550 then
    max = max + 1
  end
  local used = math.ceil((recast_231 or 0) / CHARGE_TIME[max])
  return { available = math.max(0, max - used), max = max }
end

--- The tool a ninjutsu consumes, by spell id.
function counters.tool_for_spell(spell_id)
  return NINJA_TOOL_LOOKUP[spell_id]
end

--- The card a Corsair Quick Draw shot consumes, by ability name.
function counters.tool_for_ability(name)
  if type(name) ~= "string" then
    return nil
  end
  return ABILITY_TOOL_LOOKUP[name:lower()]
end

--- What the slot's count corner shows for a tool: total (master tools
--- included on the owning main job only), the 99+ capped text, the colour
--- band, and the zero flag that raises the red X. `counts` maps item id ->
--- how many are carried.
function counters.tool_display(tool_id, counts, main_job)
  if tool_id == nil then
    return nil
  end
  counts = counts or {}
  local plain = counts[tool_id] or 0
  local master = MASTER_TOOL_LOOKUP[tool_id]
  local total = plain
  if master ~= nil then
    local owning_job = master == TRUMP_CARD and "COR" or "NIN"
    if main_job == owning_job then
      total = total + (counts[master] or 0)
    end
  end
  local color = "red"
  if plain > 50 then
    color = "green"
  elseif total > 50 then
    color = "yellow"
  end
  return {
    total = total,
    text = total > 99 and "99+" or tostring(total),
    color = color,
    zero = total == 0,
  }
end

-- Every item id whose count matters: the tools themselves (Jinko included,
-- which has no master) and the four masters.
local TRACKED = {}
for _, tool in pairs(NINJA_TOOL_LOOKUP) do
  TRACKED[tool] = true
end
for _, tool in pairs(ABILITY_TOOL_LOOKUP) do
  TRACKED[tool] = true
end
for tool, master in pairs(MASTER_TOOL_LOOKUP) do
  TRACKED[tool] = true
  TRACKED[master] = true
end

--- Whether an item id's count matters to some tool count - the add item /
--- remove item events carry only an id, so this is the "is a re-read worth
--- it" test.
function counters.tracked_item(item_id)
  return TRACKED[item_id] == true
end

return counters
