local new_accuracy = require("components/parambar/accuracy")

describe("parambar accuracy", function()
  local config, accuracy

  -- One 0x028 as `windower.packets.parse_action` hands it over: an actor, then
  -- a target per mob and an action per swing inside it.
  local function round(actor_id, messages, target_id)
    local actions = {}
    for index, message in ipairs(messages) do
      actions[index] = { message = message }
    end
    return { actor_id = actor_id, targets = { { id = target_id or 99, actions = actions } } }
  end

  local function observe(messages, at)
    accuracy.on_action(round(1, messages), 1, at or 0)
  end

  before_each(function()
    config = { window_seconds = 15 }
    accuracy = new_accuracy(config)
  end)

  describe("the empty window", function()
    it("has no swings and no percentage to report", function()
      local sample = accuracy.sample(0)
      assert.are.equal(0, sample.swings)
      assert.are.equal(0, sample.hits)
      assert.is_nil(sample.percent)
    end)
  end)

  describe("reading a melee round", function()
    it("counts a hit", function()
      observe({ 1 })
      local sample = accuracy.sample(0)
      assert.are.equal(1, sample.swings)
      assert.are.equal(1, sample.hits)
      assert.are.equal(100, sample.percent)
    end)

    it("counts a critical hit as a hit", function()
      observe({ 67 })
      assert.are.equal(1, accuracy.sample(0).hits)
    end)

    it("counts both miss messages as swings that missed", function()
      observe({ 15, 63 })
      local sample = accuracy.sample(0)
      assert.are.equal(2, sample.swings)
      assert.are.equal(0, sample.hits)
      assert.are.equal(0, sample.percent)
    end)

    --[[ scoreboard's rule, and Kevin's: a parry, block, counter, guard or
         Third Eye evasion is neither a hit nor a miss, so it never reaches
         the denominator. None of them is your accuracy failing. ]]
    it("ignores an outcome that is neither a hit nor a miss", function()
      observe({ 1, 70, 32, 15 })
      assert.are.equal(2, accuracy.sample(0).swings)
    end)

    --[[ Ranged attacks are their own stat with their own ids, and are out by
         decision rather than by omission - so they are pinned, or the next
         edit "fixes" the gap. ]]
    it("ignores a ranged attack entirely", function()
      observe({ 352, 353, 354 })
      assert.are.equal(0, accuracy.sample(0).swings)
    end)

    it("counts every swing in one round, not the round", function()
      observe({ 1, 1, 15 })
      local sample = accuracy.sample(0)
      assert.are.equal(3, sample.swings)
      assert.are.equal(2, sample.hits)
    end)

    it("counts swings against every target in the packet", function()
      accuracy.on_action({
        actor_id = 1,
        targets = { { id = 10, actions = { { message = 1 } } }, { id = 11, actions = { { message = 15 } } } },
      }, 1, 0)
      assert.are.equal(2, accuracy.sample(0).swings)
    end)
  end)

  describe("whose swings count", function()
    it("ignores a round somebody else swung", function()
      accuracy.on_action(round(2, { 1, 1 }), 1, 0)
      assert.are.equal(0, accuracy.sample(0).swings)
    end)

    it("ignores every round while the player is unknown", function()
      accuracy.on_action(round(1, { 1 }), nil, 0)
      assert.are.equal(0, accuracy.sample(0).swings)
    end)
  end)

  describe("the rolling window", function()
    it("drops a swing once it is older than the window", function()
      observe({ 1 }, 0)
      observe({ 15 }, 10)
      assert.are.equal(2, accuracy.sample(10).swings)

      local sample = accuracy.sample(16)
      assert.are.equal(1, sample.swings)
      assert.are.equal(0, sample.hits)
    end)

    it("keeps a swing sitting exactly on the window edge", function()
      observe({ 1 }, 0)
      assert.are.equal(1, accuracy.sample(15).swings)
    end)

    it("empties completely once every swing has aged out", function()
      observe({ 1, 15 }, 0)
      local sample = accuracy.sample(100)
      assert.are.equal(0, sample.swings)
      assert.is_nil(sample.percent)
    end)

    it("takes its length from the config", function()
      config.window_seconds = 30
      observe({ 1 }, 0)
      assert.are.equal(1, accuracy.sample(20).swings)
      assert.are.equal(30, accuracy.window())
    end)

    --[[ The config is a file the user can hand-edit, so a value the module
         would fall back over is refused here rather than believed. wsgate's
         rule: the report and the fallback come from one place. ]]
    it("falls back to its own length when the config value is unusable", function()
      config.window_seconds = 0
      assert.are.equal(15, accuracy.window())
      config.window_seconds = "soon"
      assert.are.equal(15, accuracy.window())
    end)
  end)

  describe("the percentage", function()
    it("rounds to the nearest whole percent", function()
      observe({ 1, 1, 15 })
      assert.are.equal(67, accuracy.sample(0).percent)
    end)
  end)

  describe("reset", function()
    it("empties the window", function()
      observe({ 1, 15 })
      accuracy.reset()
      local sample = accuracy.sample(0)
      assert.are.equal(0, sample.swings)
      assert.is_nil(sample.percent)
    end)

    it("leaves the tracker recording afterwards", function()
      observe({ 1 })
      accuracy.reset()
      observe({ 15 })
      assert.are.equal(1, accuracy.sample(0).swings)
    end)
  end)

  describe("a packet it cannot read", function()
    it("ignores a nil action", function()
      accuracy.on_action(nil, 1, 0)
      assert.are.equal(0, accuracy.sample(0).swings)
    end)

    it("ignores a packet with no targets", function()
      accuracy.on_action({ actor_id = 1 }, 1, 0)
      assert.are.equal(0, accuracy.sample(0).swings)
    end)

    it("ignores a target with no actions", function()
      accuracy.on_action({ actor_id = 1, targets = { { id = 10 } } }, 1, 0)
      assert.are.equal(0, accuracy.sample(0).swings)
    end)
  end)
end)
