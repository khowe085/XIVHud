local job_abilities = require("lib/actionbar/job_abilities")
local jobchange = require("lib/actionbar/jobchange")

--[[ What a subjob layer offers for job abilities (Kevin, 2026-10-12): the
     client lists only the worn pair's, and `res.job_abilities` carries no job
     or level, so this table is the only place either is written down. It is
     hand-ported from BG Wiki, so its shape is checked here rather than trusted. ]]
describe("job abilities by subjob", function()
  it("names every one of the 22 jobs", function()
    for _, job in ipairs(jobchange.JOBS) do
      assert.is_table(job_abilities[job], job)
    end
    local count = 0
    for _ in pairs(job_abilities) do
      count = count + 1
    end
    assert.equal(#jobchange.JOBS, count, "and nothing else")
  end)

  it("carries an id, the resource's name and a support-job level on every entry", function()
    for job, entries in pairs(job_abilities) do
      for i, entry in ipairs(entries) do
        local where = job .. " #" .. i
        assert.is_number(entry.id, where)
        assert.is_string(entry.name, where)
        assert.is_number(entry.level, where)
        assert.equal(math.floor(entry.level), entry.level, where .. " is a whole level")
        -- 59 is the highest a support job reaches, at master level 50.
        assert.is_true(entry.level >= 1 and entry.level <= 59, where .. " at " .. entry.level)
      end
    end
  end)

  it("lists an ability once per job, in level order", function()
    for job, entries in pairs(job_abilities) do
      local seen = {}
      for i, entry in ipairs(entries) do
        assert.is_nil(seen[entry.id], job .. " repeats " .. entry.name)
        seen[entry.id] = true
        if i > 1 then
          assert.is_true(entries[i - 1].level <= entry.level, job .. ": " .. entry.name .. " is out of order")
        end
      end
    end
  end)

  local function find(job, name)
    for _, entry in ipairs(job_abilities[job]) do
      if entry.name == name then
        return entry
      end
    end
    return nil
  end

  it("holds the levels the wiki gives", function()
    assert.same({ id = 35, name = "Provoke", level = 5 }, find("WAR", "Provoke"))
    assert.same({ id = 211, name = "Light Arts", level = 10 }, find("SCH", "Light Arts"))
    assert.same({ id = 125, name = "Fire Shot", level = 40 }, find("COR", "Fire Shot"))
    assert.same({ id = 358, name = "Ignis", level = 5 }, find("RUN", "Ignis"))
  end)

  it("leaves out what a subjob can never use", function()
    -- Composure is main-job only in the wiki's own words; the SP abilities
    -- need the main job.
    assert.is_nil(find("RDM", "Composure"))
    for job in pairs(job_abilities) do
      assert.is_nil(find(job, "Mighty Strikes"), job)
      assert.is_nil(find(job, "Benediction"), job)
    end
  end)
end)
