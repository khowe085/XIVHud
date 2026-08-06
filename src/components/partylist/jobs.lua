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

--[[ Job roles and the trust job table, ported from XIVParty (BSD 3-clause
     (c) 2024 Tylas -- see assets/LICENSE.txt).

     The role decides the job icon's background colour. A trust reports no job
     of its own in any packet, so its job is looked up by name, and by model id
     where a name covers two variants (Iroha / Iroha II). Order matters: the
     entry carrying a model id is listed first, so a model this table has never
     seen still falls through to the entry that names no model. ]]

local ROLES = {
  WAR = "dd",
  MNK = "dd",
  WHM = "healer",
  BLM = "dd",
  RDM = "healer",
  THF = "dd",
  PLD = "tank",
  DRK = "dd",
  BST = "dd",
  BRD = "support",
  RNG = "dd",
  SAM = "dd",
  NIN = "dd",
  DRG = "dd",
  SMN = "dd",
  BLU = "dd",
  COR = "support",
  PUP = "tank",
  DNC = "dd",
  SCH = "healer",
  GEO = "support",
  RUN = "tank",
  -- Trust-only, from the table below: Darrcuiln, Monberaux, Selh'teus and
  -- Excenmille (S). The layout has its own colour for it.
  SPC = "special",
  MON = "dd",
}

local TRUSTS = {
  { name = "Amchuchu", job = "RUN", sub_job = "WAR" },
  { name = "ArkEV", job = "PLD", sub_job = "WHM" },
  { name = "ArkHM", job = "WAR", sub_job = "NIN" },
  { name = "August", job = "PLD", sub_job = "WAR" },
  { name = "Curilla", job = "PLD" },
  { name = "Gessho", job = "NIN", sub_job = "WAR" },
  { name = "Mnejing", job = "PLD", sub_job = "WAR" },
  { name = "Rahal", job = "PLD", sub_job = "WAR" },
  { name = "Rughadjeen", job = "PLD" },
  { name = "Trion", job = "PLD", sub_job = "WAR" },
  { name = "Valaineral", job = "PLD", sub_job = "WAR" },
  { name = "Abenzio", job = "THF", sub_job = "WAR" },
  { name = "Abquhbah", job = "WAR" },
  { name = "Aldo", job = "THF", model = 3034 },
  { name = "Areuhat", job = "WAR" },
  { name = "ArkGK", job = "SAM", sub_job = "DRG" },
  { name = "ArkMR", job = "BST", sub_job = "THF" },
  { name = "Ayame", job = "SAM", model = 3004 },
  { name = "BabbanMheillea", job = "MNK" },
  { name = "Balamor", job = "DRK" },
  { name = "Chacharoon", job = "THF" },
  { name = "Cid", job = "WAR" },
  { name = "Darrcuiln", job = "SPC" },
  { name = "Excenmille", job = "PLD", model = 3003 },
  { name = "Excenmille", job = "SPC" },
  { name = "Fablinix", job = "RDM", sub_job = "BLM" },
  { name = "Gilgamesh", job = "SAM" },
  { name = "Halver", job = "PLD", sub_job = "WAR" },
  { name = "Ingrid", job = "WAR", sub_job = "WHM", model = 3102 },
  { name = "Iroha", job = "SAM", model = 3111 },
  { name = "Iroha", job = "SAM", sub_job = "WHM", model = 3112 },
  { name = "IronEater", job = "WAR" },
  { name = "Klara", job = "WAR" },
  { name = "LehkoHabhoka", job = "THF", sub_job = "BLM" },
  { name = "LheLhangavo", job = "MNK" },
  { name = "LhuMhakaracca", job = "BST", sub_job = "WAR" },
  { name = "Lilisette", job = "DNC", model = 3049 },
  { name = "Lilisette", job = "DNC", model = 3084 },
  { name = "Lion", job = "THF", model = 3011 },
  { name = "Lion", job = "THF", sub_job = "NIN", model = 3081 },
  { name = "Luzaf", job = "COR", sub_job = "NIN" },
  { name = "Maat", job = "MNK", model = 3037 },
  { name = "Maximilian", job = "WAR", sub_job = "THF" },
  { name = "Mayakov", job = "DNC" },
  { name = "Mildaurion", job = "PLD", sub_job = "WAR" },
  { name = "Morimar", job = "BST" },
  { name = "Mumor", job = "DNC", sub_job = "WAR", model = 3050 },
  { name = "NajaSalaheem", job = "MNK", sub_job = "WAR", model = 3016 },
  { name = "Naji", job = "WAR" },
  { name = "NanaaMihgo", job = "THF" },
  { name = "Nashmeira", job = "PUP", sub_job = "WHM", model = 3027 },
  { name = "Noillurie", job = "SAM", sub_job = "PLD" },
  { name = "Prishe", job = "MNK", sub_job = "WHM", model = 3017 },
  { name = "Prishe", job = "MNK", sub_job = "WHM", model = 3082 },
  { name = "Rainemard", job = "RDM" },
  { name = "RomaaMihgo", job = "THF" },
  { name = "Rongelouts", job = "WAR" },
  { name = "Selh'teus", job = "SPC" },
  { name = "ShikareeZ", job = "DRG", sub_job = "WHM" },
  { name = "Tenzen", job = "SAM", model = 3012 },
  { name = "Teodor", job = "SAM", sub_job = "BLM" },
  { name = "UkaTotlihn", job = "DNC", sub_job = "WAR" },
  { name = "Volker", job = "WAR" },
  { name = "Zazarg", job = "MNK" },
  { name = "Zeid", job = "DRK", model = 3010 },
  { name = "Zeid", job = "DRK", model = 3086 },
  { name = "Matsui-P", job = "NIN", sub_job = "BLM" },
  { name = "Elivira", job = "RNG", sub_job = "WAR" },
  { name = "Makki-Chebukki", job = "RNG" },
  { name = "Margret", job = "RNG" },
  { name = "Najelith", job = "RNG" },
  { name = "SemihLafihna", job = "RNG" },
  { name = "Tenzen", job = "RNG", model = 3097 },
  { name = "Adelheid", job = "SCH" },
  { name = "Ajido-Marujido", job = "BLM", sub_job = "RDM" },
  { name = "ArkTT", job = "BLM", sub_job = "DRK" },
  { name = "D.Shantotto", job = "BLM" },
  { name = "Gadalar", job = "BLM" },
  { name = "Ingrid", job = "WHM", model = 3025 },
  { name = "Kayeel-Payeel", job = "BLM" },
  { name = "Kukki-Chebukki", job = "BLM" },
  { name = "Leonoyne", job = "BLM" },
  { name = "Mumor", job = "BLM", model = 3104 },
  { name = "Ovjang", job = "RDM", sub_job = "WHM" },
  { name = "Robel-Akbel", job = "BLM" },
  { name = "Rosulatia", job = "BLM" },
  { name = "Shantotto", job = "BLM", model = 3000 },
  { name = "Shantotto", job = "BLM", model = 3110 },
  { name = "Ullegore", job = "BLM" },
  { name = "Cherukiki", job = "WHM" },
  { name = "FerreousCoffin", job = "WHM", sub_job = "WAR" },
  { name = "Karaha-Baruha", job = "WHM", sub_job = "SMN" },
  { name = "Kupipi", job = "WHM" },
  { name = "MihliAliapoh", job = "WHM" },
  { name = "Monberaux", job = "SPC" },
  { name = "Nashmeira", job = "WHM", model = 3083 },
  { name = "Ygnas", job = "WHM" },
  { name = "Arciela", job = "RDM", model = 3074 },
  { name = "Arciela", job = "RDM", model = 3085 },
  { name = "Joachim", job = "BRD", sub_job = "WHM" },
  { name = "KingOfHearts", job = "RDM", sub_job = "WHM" },
  { name = "Koru-Moru", job = "RDM" },
  { name = "Qultada", job = "COR" },
  { name = "Ulmia", job = "BRD" },
  { name = "Brygid", job = "GEO" },
  { name = "Cornelia", job = "GEO" },
  { name = "Kupofried", job = "GEO" },
  { name = "KuyinHathdenna", job = "GEO" },
  { name = "Moogle", job = "GEO" },
  { name = "Sakura", job = "GEO" },
  { name = "StarSibyl", job = "GEO" },
  { name = "Aldo", job = "THF" },
  { name = "Apururu", job = "WHM", sub_job = "RDM", model = 3061 },
  { name = "Ayame", job = "SAM" },
  { name = "Flaviria", job = "DRG", sub_job = "WAR" },
  { name = "InvincibleShield", job = "WAR", sub_job = "MNK" },
  { name = "JakohWahcondalo", job = "THF", sub_job = "WAR" },
  { name = "Maat", job = "MNK", sub_job = "WAR" },
  { name = "NajaSalaheem", job = "THF", sub_job = "WAR" },
  { name = "Pieuje", job = "WHM" },
  { name = "Sylvie", job = "GEO", sub_job = "WHM" },
  { name = "Yoran-Oran", job = "WHM" },
}

local M = { ROLES = ROLES, trusts = TRUSTS }

-- The icon background colour is keyed by role, and an unrecognised job is
-- still a damage dealer as far as the colour is concerned.
function M.role_of(job)
  if type(job) ~= "string" then
    return "dd"
  end
  return ROLES[job:upper()] or "dd"
end

-- `{ job, sub_job }` for a trust, or nil for a real player.
function M.trust_info(name, model)
  if type(name) ~= "string" then
    return nil
  end
  for _, trust in ipairs(TRUSTS) do
    if trust.name == name and (trust.model == nil or trust.model == model) then
      return { job = trust.job, sub_job = trust.sub_job }
    end
  end
  return nil
end

return M
