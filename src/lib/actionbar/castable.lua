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

--[[ Whether the jobs a character is on can supply an action right now, by the
     resource's own `levels` and nothing hardcoded. One test for everything
     that picks an action at the press - the stealth and reraise ladders and
     the spell tier walk - so they cannot disagree about what can be cast.
     The binder's catalog asks a looser question of its own: a binding is for
     later, where these fire now. ]]

local M = {}

-- FFXI's own cap. A requirement above it is a merit or job point gift, which
-- only a main job can have spent.
local LEVEL_CAP = 99

--[[ A spell's `requirements` bit that SCH must open with an Addendum. It sits
     on exactly the Addendum spells - the -na family, Erase, Raise II and III
     and Reraise I to III on the white side, the tier IV and V nukes, Sleep,
     Break and Dispel on the black - and binds SCH alone: a WHM casts Reraise
     without one. Enlightenment opens both addenda at once. ]]
local SCH = 20
local ADDENDUM_BIT = 4
local ENLIGHTENMENT = 416
local ADDENDUM_FOR = { WhiteMagic = 401, BlackMagic = 402 }
local ADDENDUM_NAMES = { [401] = "Addendum: White", [402] = "Addendum: Black" }

--- The main/sub pair, as catalog.lua reads it: the sub only when the client
--- has named one, and `main` carried through for the gift exception. `name`
--- is the client's own word for the job, which only `why_not` reads.
function M.job_pair(player)
  if type(player) ~= "table" then
    return {}
  end
  local jobs = {}
  if type(player.main_job_id) == "number" then
    jobs[#jobs + 1] =
      { id = player.main_job_id, name = player.main_job, level = player.main_job_level or 0, main = true }
  end
  if type(player.sub_job_id) == "number" then
    jobs[#jobs + 1] = { id = player.sub_job_id, name = player.sub_job, level = player.sub_job_level or 0, main = false }
  end
  return jobs
end

function M.has_buff(player, id)
  local buffs = type(player) == "table" and player.buffs or nil
  if type(buffs) ~= "table" then
    return false
  end
  for _, buff in ipairs(buffs) do
    if buff == id then
      return true
    end
  end
  return false
end

-- The Addendum buff a SCH must have up to cast this spell, or nil.
local function addendum_for(record)
  local requirements = tonumber(record.requirements)
  if requirements == nil or math.floor(requirements / ADDENDUM_BIT) % 2 ~= 1 then
    return nil
  end
  return ADDENDUM_FOR[record.type]
end

-- Whether a SCH has the Addendum this spell wants up; any other job needs none.
local function opened(job, addendum, player)
  return job.id ~= SCH or addendum == nil or M.has_buff(player, addendum) or M.has_buff(player, ENLIGHTENMENT)
end

local function level_of(job)
  return type(job.level) == "number" and job.level or 0
end

--- Can one of these jobs supply this action? A resource with no `levels`
--- table is included - the client already vouched for it by listing it as
--- known, and the job abilities carry no levels at all.
function M.available(record, jobs, player)
  local levels = type(record) == "table" and record.levels or nil
  if type(levels) ~= "table" then
    return true
  end
  local addendum = addendum_for(record)
  for _, job in ipairs(jobs) do
    local required = levels[job.id]
    local level = level_of(job)
    if type(required) == "number" and opened(job, addendum, player) then
      if required <= level then
        return true
      end
      -- A gift, which a main job spends - and only at the cap: it is off
      -- while synced below it.
      if required > LEVEL_CAP and job.main and level >= LEVEL_CAP then
        return true
      end
    end
  end
  return false
end

local function job_name(job)
  return type(job.name) == "string" and job.name or ("job" .. tostring(job.id))
end

-- The level a job is short of for this requirement, in words, or nil where it
-- is not short: a gift wants the job as the main one, at the cap.
local function short_of(job, required)
  local level = level_of(job)
  if required > LEVEL_CAP then
    if job.main and level >= LEVEL_CAP then
      return nil
    end
    return ("%s %d as the main job"):format(job_name(job), LEVEL_CAP)
  end
  return required > level and (job_name(job) .. " " .. required) or nil
end

--[[ Why none of these jobs can supply this action, in words for a debug
     line, or nil for one `available` takes: everything each job of the pair
     that has the action still needs - its Addendum, its level, or to be the
     main job at the cap for a gift - and the jobs and levels that were
     asked. ]]
function M.why_not(record, jobs, player)
  if M.available(record, jobs, player) then
    return nil
  end
  if #jobs == 0 then
    return "no job to cast it"
  end
  local addendum = addendum_for(record)
  local needs, on = {}, {}
  for _, job in ipairs(jobs) do
    on[#on + 1] = job_name(job) .. " " .. level_of(job)
    local required = record.levels[job.id]
    if type(required) == "number" then
      local wants = {}
      if not opened(job, addendum, player) then
        wants[#wants + 1] = ADDENDUM_NAMES[addendum]
      end
      wants[#wants + 1] = short_of(job, required)
      needs[#needs + 1] = table.concat(wants, " and ")
    end
  end
  if #needs == 0 then
    return "no spell of " .. table.concat(on, "/")
  end
  return ("needs %s (on %s)"):format(table.concat(needs, " or "), table.concat(on, "/"))
end

return M
