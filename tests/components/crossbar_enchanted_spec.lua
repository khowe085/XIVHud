local enchanted = require("components/crossbar/enchanted")

-- extdata's times are offset 18000 from os.time; a NOW well past zero keeps
-- the arithmetic honest.
local NOW = 100000

local function ext(overrides)
  local decoded = {
    type = "Enchanted Equipment",
    charges_remaining = 1,
    next_use_time = NOW - 18000, -- ready exactly now
    activation_time = NOW - 18000,
    usable = false,
  }
  for key, value in pairs(overrides or {}) do
    decoded[key] = value
  end
  return decoded
end

describe("crossbar enchanted", function()
  describe("recast_remaining", function()
    it("is zero for a ready item", function()
      assert.equal(0, enchanted.recast_remaining(ext(), NOW))
    end)

    it("counts down the seconds until next use", function()
      assert.equal(42, enchanted.recast_remaining(ext({ next_use_time = NOW - 18000 + 42 }), NOW))
    end)

    it("never goes negative", function()
      assert.equal(0, enchanted.recast_remaining(ext({ next_use_time = NOW - 18000 - 5 }), NOW))
    end)

    it("is nil with no charges left", function()
      assert.is_nil(enchanted.recast_remaining(ext({ charges_remaining = 0 }), NOW))
    end)

    it("is nil for a non-enchanted item", function()
      assert.is_nil(enchanted.recast_remaining(ext({ type = "General" }), NOW))
    end)

    it("answers nil for an ext that is not enchanted-shaped, never throws", function()
      -- The same posture step() has: this feeds warp's ladder walk, where a
      -- foreign decode must degrade, not arithmetic-throw.
      assert.is_nil(enchanted.recast_remaining(nil, NOW))
      assert.is_nil(enchanted.recast_remaining("garbage", NOW))
      assert.is_nil(enchanted.recast_remaining({ type = "Enchanted Equipment" }, NOW))
      assert.is_nil(enchanted.recast_remaining({ type = "Enchanted Equipment", charges_remaining = "x" }, NOW))
      assert.is_nil(enchanted.recast_remaining({ type = "Enchanted Equipment", charges_remaining = 1 }, NOW))
    end)
  end)

  describe("warmup_remaining", function()
    it("counts down the enchant delay after an equip", function()
      assert.equal(12, enchanted.warmup_remaining(ext({ activation_time = NOW - 18000 + 12 }), NOW))
    end)

    it("clamps at zero once the delay has passed", function()
      assert.equal(0, enchanted.warmup_remaining(ext({ activation_time = NOW - 18000 - 3 }), NOW))
    end)
  end)

  describe("step", function()
    it("uses the item the moment extdata says usable", function()
      assert.equal("use", enchanted.step(ext({ usable = true }), NOW))
    end)

    it("waits out a delay inside the give-up bound", function()
      assert.equal("wait", enchanted.step(ext({ activation_time = NOW - 18000 + 29 }), NOW))
    end)

    it("still waits exactly at the bound", function()
      assert.equal("wait", enchanted.step(ext({ activation_time = NOW - 18000 + 30 }), NOW))
    end)

    it("abandons at once when the remaining delay exceeds 30s", function()
      -- The give-up is not a timer: an item needing more than 30s more is
      -- abandoned immediately, not polled for 30s.
      assert.equal("abandon", enchanted.step(ext({ activation_time = NOW - 18000 + 31 }), NOW))
    end)

    it("answers nil for an ext that is not enchanted-shaped, never throws", function()
      -- The widget polls this under the shared prerender guard: an
      -- arithmetic throw here would repeat until guard disables every
      -- component's update.
      assert.is_nil(enchanted.step({ type = "General" }, NOW))
      assert.is_nil(enchanted.step("garbage", NOW))
      assert.is_nil(enchanted.step(nil, NOW))
      assert.equal("use", enchanted.step({ usable = true }, NOW), "usable short-circuits before any arithmetic")
    end)
  end)
end)
