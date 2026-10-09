local jobchange = require("lib/actionbar/jobchange")

describe("job change", function()
  it("lists the 22 jobs in the game's own order", function()
    assert.equal(22, #jobchange.JOBS)
    assert.equal("WAR", jobchange.JOBS[1])
    assert.equal("RUN", jobchange.JOBS[22])
  end)

  it("ships a job icon for every job it lists", function()
    for _, job in ipairs(jobchange.JOBS) do
      local file = io.open("src/assets/icons/" .. jobchange.icon(job) .. ".png", "rb")
      assert.is_not_nil(file, job .. "'s icon must ship")
      file:close()
    end
  end)

  describe("parse", function()
    it("reads a main/sub pair in any case, answering upper case", function()
      local main, sub = jobchange.parse("war/blm")
      assert.equal("WAR", main)
      assert.equal("BLM", sub)
    end)

    it("refuses a job that is not one", function()
      local main, complaint = jobchange.parse("WAR/XYZ")
      assert.is_nil(main)
      assert.matches("XYZ", complaint)
    end)

    it("refuses anything that is not a main/sub pair", function()
      for _, value in ipairs({ "WAR", "WAR/", "/BLM", "WAR/BLM/RDM", "", 7 }) do
        assert.is_nil((jobchange.parse(value)), tostring(value))
      end
    end)

    it("refuses the same job on both sides", function()
      local main, complaint = jobchange.parse("WAR/WAR")
      assert.is_nil(main)
      assert.is_string(complaint)
    end)
  end)
end)
