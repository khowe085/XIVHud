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

    -- Deliberately NOT the module's own default, or the test would pass
    -- just as well if the config were ignored.
    it("takes its length from the config", function()
      config.window_seconds = 45
      observe({ 1 }, 0)
      assert.are.equal(1, accuracy.sample(40).swings)
      assert.are.equal(45, accuracy.window())
    end)

    --[[ The config is a file the user can hand-edit, so a value the module
         would fall back over is refused here rather than believed: the
         report and the fallback come from one place. ]]
    it("falls back to its own length when the config value is unusable", function()
      config.window_seconds = 0
      assert.are.equal(30, accuracy.window())
      config.window_seconds = "soon"
      assert.are.equal(30, accuracy.window())
    end)
  end)

  describe("the percentage", function()
    it("rounds to the nearest whole percent", function()
      observe({ 1, 1, 15 })
      assert.are.equal(67, accuracy.sample(0).percent)
    end)
  end)

  --[[ The delay is MEASURED, never computed: nothing in the client reports
       your haste, and a march's potency depends on the singer's gear and
       skill, so the only honest number is the interval the rounds actually
       arrive at. One packet is one round, however many swings are in it. ]]
  describe("the measured delay", function()
    it("has nothing to report before two rounds have landed", function()
      assert.is_nil(accuracy.sample(0).delay)
      observe({ 1, 1 }, 0)
      assert.is_nil(accuracy.sample(0).delay)
    end)

    it("is the interval between two rounds", function()
      observe({ 1 }, 0)
      observe({ 1 }, 3)
      assert.are.equal(3, accuracy.sample(3).delay)
    end)

    it("counts a round once however many swings it carried", function()
      observe({ 1, 1, 15, 67 }, 0)
      observe({ 1, 15 }, 2.5)
      assert.are.equal(2.5, accuracy.sample(2.5).delay)
    end)

    --[[ The median, not the mean: a weaponskill, a cast or a step out of
         range inserts a long gap that would drag an average a long way. ]]
    it("takes the median gap, so one interruption cannot drag it", function()
      -- Wide enough to hold the interruption as well as the rounds either
      -- side of it; the point is the statistic, not the pruning.
      config.window_seconds = 60
      for index = 0, 4 do
        observe({ 1 }, index * 3)
      end
      observe({ 1 }, 42)
      -- Gaps 3, 3, 3, 3 and 30: the mean would read 8.4.
      assert.are.equal(3, accuracy.sample(42).delay)
    end)

    --[[ What the median is worth over a SHORT window - fifteen seconds, the
         row's own default until 2026-09-28 and still a value anyone can set.
         A four-second delay gives two or three gaps there, and the median of
         an even pair IS their mean, so one interruption still moves the
         number. Pinned so the honest limit cannot be quietly lost. ]]
    it("is still dragged by one interruption while the window is short", function()
      observe({ 1 }, 8)
      observe({ 1 }, 12)
      observe({ 1 }, 20)
      -- Gaps 4 and 8 inside this spec's fifteen-second window: 6, not 4.
      assert.are.equal(6, accuracy.sample(20).delay)
    end)

    it("averages the middle pair when the gaps are even in number", function()
      observe({ 1 }, 0)
      observe({ 1 }, 2)
      observe({ 1 }, 6)
      assert.are.equal(3, accuracy.sample(6).delay)
    end)

    it("ages rounds out of the window like the swings", function()
      observe({ 1 }, 0)
      observe({ 1 }, 3)
      assert.are.equal(3, accuracy.sample(3).delay)
      -- Both are past the window now, so there is no pair left to measure.
      assert.is_nil(accuracy.sample(30).delay)
    end)

    it("ignores a packet that carried no countable swing", function()
      observe({ 1 }, 0)
      -- All parried: neither a hit nor a miss, so not a round we can see.
      observe({ 70, 32 }, 2)
      observe({ 1 }, 4)
      assert.are.equal(4, accuracy.sample(4).delay)
    end)

    it("follows a round landing after it was last read", function()
      observe({ 1 }, 0)
      observe({ 1 }, 2)
      assert.are.equal(2, accuracy.sample(2).delay)
      observe({ 1 }, 8)
      -- Three rounds, gaps 2 and 6: the median is their mean.
      assert.are.equal(4, accuracy.sample(8).delay)
    end)

    --[[ Two packets stamped at the same instant are not a round apart, and
         `0.0s` would be a claim where `--s` is an admission. ]]
    it("ignores a gap of no time at all", function()
      observe({ 1 }, 0)
      observe({ 1 }, 0)
      assert.is_nil(accuracy.sample(0).delay)
      observe({ 1 }, 3)
      assert.are.equal(3, accuracy.sample(3).delay)
    end)

    it("is emptied with the window", function()
      observe({ 1 }, 0)
      observe({ 1 }, 3)
      accuracy.reset()
      assert.is_nil(accuracy.sample(3).delay)
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

  --[[ The share of rounds that carried more attacks than the weapons alone
       swing: more than one single-wield, more than two dual-wield. Whether a
       round was dual-wield is read off the packet itself - an off-hand swing
       (`animation` 1) in it - so nothing reads the equipment. ]]
  describe("multi-attack rounds", function()
    -- One round of { message, animation } pairs.
    local function swung(pairs_, at, category)
      local actions = {}
      for index, entry in ipairs(pairs_) do
        actions[index] = { message = entry[1], animation = entry[2] }
      end
      accuracy.on_action(
        { actor_id = 1, category = category, targets = { { id = 99, actions = actions } } },
        1,
        at or 0
      )
    end

    local MELEE = 1

    local MAIN, OFF = 0, 1

    it("has no percentage before a round has landed", function()
      local sample = accuracy.sample(0)
      assert.are.equal(0, sample.rounds)
      assert.is_nil(sample.multi_percent)
    end)

    it("counts a single-wield round of two attacks as a multi-attack", function()
      swung({ { 1, MAIN }, { 1, MAIN } })
      local sample = accuracy.sample(0)
      assert.are.equal(1, sample.rounds)
      assert.are.equal(1, sample.multi_rounds)
      assert.are.equal(100, sample.multi_percent)
    end)

    it("does not count a single-wield round of one attack", function()
      swung({ { 1, MAIN } })
      assert.are.equal(0, accuracy.sample(0).multi_percent)
    end)

    it("does not count a dual-wield round of its two ordinary attacks", function()
      swung({ { 1, MAIN }, { 15, OFF } })
      assert.are.equal(0, accuracy.sample(0).multi_rounds)
    end)

    it("counts a dual-wield round of three attacks", function()
      swung({ { 1, MAIN }, { 1, MAIN }, { 1, OFF } })
      assert.are.equal(1, accuracy.sample(0).multi_rounds)
    end)

    -- Every swing is an attack, whatever became of it: a parried extra
    -- attack was still an extra attack.
    it("counts a swing that was neither a hit nor a miss as an attack", function()
      swung({ { 1, MAIN }, { 70, MAIN } })
      assert.are.equal(1, accuracy.sample(0).multi_rounds)
    end)

    -- Outside a melee packet, a hit or a miss is the only proof the packet
    -- was a round at all: a spell's messages and animations are not swings.
    it("ignores a packet with no hit or miss in it that is not a melee round", function()
      swung({ { 70, MAIN }, { 32, MAIN } })
      swung({ { 230, 12 } }, 0, 4)
      assert.are.equal(0, accuracy.sample(0).rounds)
    end)

    -- A single swing is parried or absorbed more often than every swing of
    -- a multi-attack is, so leaving such rounds out would inflate the share.
    it("judges a melee round whose every swing was parried", function()
      swung({ { 70, MAIN } }, 0, MELEE)
      swung({ { 70, MAIN }, { 31, MAIN } }, 3, MELEE)
      local sample = accuracy.sample(3)
      assert.are.equal(2, sample.rounds)
      assert.are.equal(1, sample.multi_rounds)
      assert.are.equal(50, sample.multi_percent)
    end)

    it("leaves a parried melee round out of the accuracy and the delay", function()
      swung({ { 1, MAIN } }, 0, MELEE)
      swung({ { 70, MAIN } }, 1, MELEE)
      swung({ { 1, MAIN } }, 3, MELEE)
      local sample = accuracy.sample(3)
      assert.are.equal(2, sample.swings)
      assert.are.equal(3, sample.delay)
    end)

    it("ages a parried melee round out of the window", function()
      swung({ { 70, MAIN } }, 0, MELEE)
      swung({ { 1, MAIN } }, 20, MELEE)
      assert.are.equal(1, accuracy.sample(31).rounds)
      assert.are.equal(0, accuracy.sample(51).rounds)
    end)

    it("takes the share of rounds, rounded to a whole percent", function()
      swung({ { 1, MAIN }, { 1, MAIN } }, 0)
      swung({ { 1, MAIN } }, 3)
      swung({ { 1, MAIN } }, 6)
      assert.are.equal(33, accuracy.sample(6).multi_percent)
    end)

    it("rounds the share half up", function()
      swung({ { 1, MAIN }, { 1, MAIN } }, 0)
      swung({ { 1, MAIN }, { 1, MAIN } }, 3)
      swung({ { 1, MAIN } }, 6)
      assert.are.equal(67, accuracy.sample(6).multi_percent)
    end)

    it("ages rounds out with the window", function()
      swung({ { 1, MAIN }, { 1, MAIN } }, 0)
      swung({ { 1, MAIN } }, 10)
      local sample = accuracy.sample(16)
      assert.are.equal(1, sample.rounds)
      assert.are.equal(0, sample.multi_rounds)
    end)

    --[[ Out by decision (Kevin, 2026-11-08): a Kick Attack and a Daken are
         extra swings in the round but not multi-attacks, so only the hand
         swings are counted. ]]
    it("does not count a kick or a Daken as an extra attack", function()
      local RIGHT_KICK, LEFT_KICK, DAKEN = 2, 3, 4
      swung({ { 1, MAIN }, { 1, OFF }, { 1, RIGHT_KICK } }, 0)
      swung({ { 1, MAIN }, { 1, LEFT_KICK } }, 3)
      swung({ { 1, MAIN }, { 1, OFF }, { 1, DAKEN } }, 6)
      local sample = accuracy.sample(6)
      assert.are.equal(3, sample.rounds)
      assert.are.equal(0, sample.multi_rounds)
    end)

    -- Footwork turns the hand swings into kicks: such a round says nothing
    -- about multi-attack either way, so it is left out of the share.
    it("leaves a round of kicks alone out of the share", function()
      swung({ { 1, 2 }, { 1, 3 } }, 0)
      swung({ { 1, MAIN }, { 1, MAIN } }, 3)
      local sample = accuracy.sample(3)
      assert.are.equal(1, sample.rounds)
      assert.are.equal(100, sample.multi_percent)
    end)

    -- A swing the packet gives no animation for is a hand swing: an absent
    -- field must not silently empty the row.
    it("counts a swing with no animation as a hand swing", function()
      swung({ { 1 }, { 1 } })
      assert.are.equal(1, accuracy.sample(0).multi_rounds)
    end)

    it("ages a single-attack round out of the share", function()
      swung({ { 1, MAIN } }, 0)
      swung({ { 1, MAIN }, { 1, MAIN } }, 10)
      local sample = accuracy.sample(16)
      assert.are.equal(1, sample.rounds)
      assert.are.equal(100, sample.multi_percent)
    end)

    it("ages a round of kicks out without taking a counted round with it", function()
      swung({ { 1, 2 }, { 1, 3 } }, 0)
      swung({ { 1, MAIN } }, 10)
      local sample = accuracy.sample(16)
      assert.are.equal(1, sample.rounds)
      assert.are.equal(0, sample.multi_percent)
    end)

    -- Zanshin repeats a swing in the same round on the main hand, so it
    -- reads as an extra attack - the repo's own definition counts it as one
    -- (docs/ffxi-mechanics.md).
    it("counts a Zanshin repeat as an extra attack", function()
      swung({ { 15, MAIN }, { 1, MAIN } })
      assert.are.equal(1, accuracy.sample(0).multi_rounds)
    end)

    it("is emptied with the window", function()
      swung({ { 1, MAIN }, { 1, MAIN } })
      accuracy.reset()
      local sample = accuracy.sample(0)
      assert.are.equal(0, sample.rounds)
      assert.is_nil(sample.multi_percent)
    end)
  end)
end)
