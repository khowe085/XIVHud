local jobs = require("components/partylist/jobs")

describe("partylist jobs", function()
  describe("roles", function()
    it("puts the shield jobs on tank", function()
      for _, job in ipairs({ "PLD", "PUP", "RUN" }) do
        assert.are.equal("tank", jobs.role_of(job))
      end
    end)

    it("puts the cure jobs on healer", function()
      for _, job in ipairs({ "WHM", "RDM", "SCH" }) do
        assert.are.equal("healer", jobs.role_of(job))
      end
    end)

    it("puts the buff jobs on support", function()
      for _, job in ipairs({ "BRD", "COR", "GEO" }) do
        assert.are.equal("support", jobs.role_of(job))
      end
    end)

    -- SPC is what the trust table gives Darrcuiln, Monberaux and Excenmille
    -- (S); the xiv layout has an orange for it.
    it("keeps the special role the trust table uses", function()
      assert.are.equal("special", jobs.role_of("SPC"))
    end)

    it("falls back to dd for everything else, monstrosity included", function()
      for _, job in ipairs({ "WAR", "BLM", "MON", "DNC" }) do
        assert.are.equal("dd", jobs.role_of(job))
      end
    end)

    it("matches case-insensitively", function()
      assert.are.equal("tank", jobs.role_of("pld"))
    end)

    it("answers dd for a job it has never heard of", function()
      assert.are.equal("dd", jobs.role_of("XYZ"))
      assert.are.equal("dd", jobs.role_of(nil))
    end)
  end)

  describe("trusts", function()
    it("resolves a trust with no model-id ambiguity", function()
      assert.are.same({ job = "PLD", sub_job = "WAR" }, jobs.trust_info("Mnejing"))
    end)

    it("resolves a trust that has no subjob", function()
      assert.are.same({ job = "PLD" }, jobs.trust_info("Curilla"))
    end)

    -- Iroha and Iroha II share a name and differ only by model id.
    it("separates the I and II variants by model id", function()
      assert.are.same({ job = "SAM" }, jobs.trust_info("Iroha", 3111))
      assert.are.same({ job = "SAM", sub_job = "WHM" }, jobs.trust_info("Iroha", 3112))
    end)

    -- The entry carrying a model id is listed first, so an unrecognised model
    -- falls through to the entry that names no model at all.
    it("falls through to the model-less entry for an unknown model", function()
      assert.are.same({ job = "THF", sub_job = "WAR" }, jobs.trust_info("NajaSalaheem", 9999))
    end)

    it("takes the first entry when no model id is supplied", function()
      assert.are.same({ job = "THF" }, jobs.trust_info("Aldo"))
    end)

    it("keeps the apostrophe in a trust name", function()
      assert.are.same({ job = "SPC" }, jobs.trust_info("Selh'teus"))
    end)

    it("returns nothing for a name that is not a trust", function()
      assert.is_nil(jobs.trust_info("Tarutaru", 1))
      assert.is_nil(jobs.trust_info(nil))
    end)
  end)

  describe("the trust table", function()
    it("covers every trust XIVParty knows", function()
      assert.are.equal(122, #jobs.trusts)
    end)

    it("names a job for every entry, and only jobs the role map knows", function()
      for _, trust in ipairs(jobs.trusts) do
        assert.is_string(trust.name, "a trust has no name")
        assert.is_not_nil(jobs.ROLES[trust.job], trust.name .. " has an unknown job " .. tostring(trust.job))
        if trust.sub_job then
          assert.is_not_nil(jobs.ROLES[trust.sub_job], trust.name .. " has an unknown subjob")
        end
      end
    end)
  end)
end)
