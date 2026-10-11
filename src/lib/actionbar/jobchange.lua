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

--[[ The `jc` bind type: a main/sub pair, stored as one word (`WAR/BLM`) and
     fired as the Windower JobChange addon's own command (`jc war/blm`).
     The change itself - finding a Moogle in range, poking the nomad ones,
     stepping through a temporary job when the pair conflicts with the one
     worn - is that addon's, so a slot does nothing but say "unknown command"
     in the console unless it is loaded. That is the status bar's `cancel`
     posture: no outgoing packet is injected from here. ]]

local M = {}

-- The game's own menu order.
M.JOBS = {
  "WAR",
  "MNK",
  "WHM",
  "BLM",
  "RDM",
  "THF",
  "PLD",
  "DRK",
  "BST",
  "BRD",
  "RNG",
  "SAM",
  "NIN",
  "DRG",
  "SMN",
  "BLU",
  "COR",
  "PUP",
  "DNC",
  "SCH",
  "GEO",
  "RUN",
}

local KNOWN = {}
for _, job in ipairs(M.JOBS) do
  KNOWN[job] = true
end

--- `WAR/BLM` (any case) -> "WAR", "BLM"; nil + a hint for anything else.
function M.parse(value)
  if type(value) ~= "string" then
    return nil, "jc needs a main/sub pair, like WAR/BLM"
  end
  local main, sub = value:upper():match("^(%a+)/(%a+)$")
  if main == nil then
    return nil, "jc needs a main/sub pair, like WAR/BLM - " .. value .. " is not one"
  end
  for _, job in ipairs({ main, sub }) do
    if not KNOWN[job] then
      return nil, job .. " is not a job"
    end
  end
  if main == sub then
    return nil, "a job cannot be its own sub job"
  end
  return main, sub
end

-- Pack-relative, the form an `icon=` override and a menu row both take.
function M.icon(job)
  return "jobs/" .. job:lower()
end

return M
