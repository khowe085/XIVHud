local new_travel = require("components/crossbar/travel")

local function world(overrides)
  local state = {
    now = 100,
    config = { delay = 5 },
    -- Counted: the tick calls step() every frame, so a settled one must
    -- not even ask what time it is.
    clock_reads = 0,
  }
  for key, value in pairs(overrides or {}) do
    state[key] = value
  end
  local travel = new_travel({
    now = function()
      state.clock_reads = state.clock_reads + 1
      return state.now
    end,
    config = function()
      return state.config
    end,
    statuses = state.statuses,
  })
  return travel, state
end

describe("crossbar travel delay", function()
  describe("the shipped span", function()
    it("ships five seconds, seeded from one place", function()
      local travel = world()
      assert.same({ delay = 5 }, travel.defaults())
    end)

    it("reads the live config, so a write takes effect at once", function()
      local travel, state = world()
      assert.equal(5, travel.delay())
      state.config.delay = 2
      assert.equal(2, travel.delay())
    end)

    it("falls back to the shipped span for a hand-broken config", function()
      local travel, state = world()
      state.config = nil
      assert.equal(5, travel.delay())
      state.config = 42
      assert.equal(5, travel.delay())
      state.config = { delay = "soon" }
      assert.equal(5, travel.delay())
    end)

    it("reads a negative span as no delay rather than a countdown that never ends", function()
      local travel, state = world()
      state.config.delay = -1
      assert.equal(0, travel.delay())
    end)

    it("reads a span that is not a number at all as the shipped one", function()
      -- A hand-edited `delay = 0/0` would otherwise arm a countdown that
      -- never ends and speaks "nan..." sixty times a second.
      local travel, state = world()
      state.config.delay = 0 / 0
      assert.equal(5, travel.delay())
      state.config.delay = math.huge
      assert.equal(5, travel.delay())
    end)

    it("takes zero as the off switch", function()
      local travel, state = world()
      state.config.delay = 0
      assert.equal(0, travel.delay())
    end)
  end)

  describe("which presses wait", function()
    local function command(extra)
      local plan = { kind = "command", command = "input /something" }
      for key, value in pairs(extra or {}) do
        plan[key] = value
      end
      return plan
    end

    local function warp_plan(rung)
      return { kind = "warp", plan = rung }
    end

    it("names the mount a bound mount slot is about to summon", function()
      local travel = world()
      assert.equal("Mount Chocobo", travel.label({ type = "mount", action = "Chocobo" }, command()))
    end)

    it("says a mount the way the slot says it, not the way /mount takes it", function()
      local travel = world()
      -- A binder-bound mount stores the lower-case command form, so the
      -- countdown read "Mount chocobo" until it learned to prefer the
      -- alias every other label path in the component already prefers.
      local mount = { type = "mount", action = "raptor companion", display = "Raptor Companion" }
      assert.equal("Mount Raptor Companion", travel.label(mount, command()))
      assert.equal(
        "Mount chocobo",
        travel.label({ type = "mount", action = "chocobo", display = "" }, command()),
        "an empty display name is not a name"
      )
      -- The player's own label still outranks ours, and clearing it falls
      -- back to the game's casing rather than to the command form.
      local named = { type = "mount", action = "raptor companion", display = "Raptor Companion", alias = "Pull mount" }
      assert.equal("Mount Pull mount", travel.label(named, command()))
      named.alias = nil
      assert.equal("Mount Raptor Companion", travel.label(named, command()))
    end)

    it("holds nothing for a mount slot that names no mount", function()
      -- Nothing to summon, so nothing to count down - and a countdown for
      -- "Mount nil" is not a line to put in front of a player.
      local travel = world()
      assert.is_nil(travel.label({ type = "mount" }, command()))
      assert.is_nil(travel.label({ type = "mount", action = "" }, command()))
      assert.is_nil(travel.label({ type = "mount", action = 42 }, command()))
    end)

    it("names mount roulette", function()
      local travel = world()
      assert.equal("Mount roulette", travel.label({ type = "mr" }, command()))
    end)

    it("lets mount roulette's dismount go at once", function()
      -- Dismounting is getting OUT of something; the delay is for summoning.
      local travel = world()
      assert.is_nil(travel.label({ type = "mr" }, command({ dismount = true })))
    end)

    it("names a warp on a spell rung", function()
      local travel = world()
      assert.equal("Warp", travel.label({ type = "warp" }, warp_plan({ type = "spell", command = "x" })))
    end)

    it("names the RUNG on a plain consumable, not just the trip", function()
      --[[ Instant Warp has no warmup of its own, so the countdown is the
           only window it ever gets - and the line has to say which way you
           are going home, since the ladder has several rungs and the
           player is about to spend one of them (Kevin, 2026-08-22). ]]
      local travel = world()
      assert.equal("Instant Warp", travel.label({ type = "warp" }, warp_plan({ type = "use", name = "Instant Warp" })))
    end)

    it("falls back to the bare word for a rung carrying no name", function()
      local travel = world()
      assert.equal("Warp", travel.label({ type = "warp" }, warp_plan({ type = "use" })))
    end)

    it("lets a rung whose use entails a wait go at once - that wait is the window", function()
      -- A Warp Ring that has to be equipped and warmed up already makes you
      -- wait, with the GearSwap slot held disabled; five more seconds on
      -- top buys nothing.
      local travel = world()
      assert.is_nil(travel.label({ type = "warp" }, warp_plan({ type = "equip", name = "Warp Ring", warmup = true })))
    end)

    it("counts an enchanted item down when using it entails no wait", function()
      -- The corollary, and why the condition is the WAIT and not the rung:
      -- an already-equipped, charged ring fires the instant it is asked, so
      -- skipping there would be an instant warp with no window at all - the
      -- rationale inverted.
      local travel = world()
      assert.equal("Warp Ring", travel.label({ type = "warp" }, warp_plan({ type = "use", name = "Warp Ring" })))
    end)

    it("does not hold a warp that has nothing to fire", function()
      -- A "none" plan is a chat hint about what is missing; delaying it
      -- would say nothing for five seconds and then complain.
      local travel = world()
      assert.is_nil(travel.label({ type = "warp" }, warp_plan({ type = "none", notes = {} })))
      assert.is_nil(travel.label({ type = "warp" }, nil))
      assert.is_nil(travel.label({ type = "warp" }, { kind = "warp" }))
    end)

    it("holds nothing else, whatever it is", function()
      local travel = world()
      for _, kind in ipairs({ "ma", "ja", "ws", "item", "pet", "ra", "ct", "ex", "open", "draw" }) do
        assert.is_nil(travel.label({ type = kind, action = "x" }, command()), kind)
      end
      assert.is_nil(travel.label(nil, command()))
      assert.is_nil(travel.label("mr", command()))
    end)

    it("knows a trip by its type alone, whatever its plan turns out to be", function()
      -- The press that fires AT ONCE is still a trip, and still ends
      -- whatever was counting down: a dismount or a ring warp supersedes
      -- an armed countdown exactly as a delayed one does. The plan cannot
      -- answer that - it is what said the press need not wait.
      local travel = world()
      for _, kind in ipairs({ "mount", "mr", "warp" }) do
        assert.is_true(travel.travels({ type = kind }), kind)
      end
      for _, kind in ipairs({ "ma", "ja", "ws", "item", "pet", "ra", "ct", "ex", "open", "draw" }) do
        assert.is_false(travel.travels({ type = kind }), kind)
      end
      assert.is_false(travel.travels(nil))
      assert.is_false(travel.travels("warp"))
      assert.is_false(travel.travels({}))
    end)

    it("holds nothing a press could not fire in the first place", function()
      -- resolve() answers nil + a hint for a malformed record, and a no-op
      -- for roulette with no mounts owned: neither is worth a countdown.
      local travel = world()
      assert.is_nil(travel.label({ type = "mount", action = "Chocobo" }, nil))
      assert.is_nil(travel.label({ type = "mr" }, { kind = "none" }))
      assert.is_nil(travel.label({ type = "mount", action = "Chocobo" }, { kind = "message", message = "no" }))
    end)
  end)

  describe("the countdown", function()
    local ENTRY = { label = "Mount roulette", fire = "the widget's own payload" }

    it("arms, and says what is coming, how long, and the way out", function()
      local travel, state = world()
      assert.equal("Mount roulette in 5 seconds. /heal to cancel.", travel.arm(ENTRY))
      assert.equal(100, state.now, "and the clock has not moved: nothing has fired")
      -- Armed, seen the way the widget sees it: there is now a trip to
      -- call off.
      assert.equal("Mount roulette cancelled.", travel.cancel())
    end)

    it("counts the seconds down, one line each, and fires at the end", function()
      local travel, state = world()
      travel.arm(ENTRY)
      local said = {}
      for tenth = 1, 50 do
        state.now = 100 + tenth / 10
        local fired, line = travel.step()
        if line ~= nil then
          said[#said + 1] = line
        end
        if fired ~= nil then
          assert.same(ENTRY, fired)
          assert.equal(50, tenth, "it fires when the span runs out, not before")
          assert.is_nil(line, "the last step fires rather than speaking")
        end
      end
      assert.same({ "4...", "3...", "2...", "1..." }, said)
    end)

    it("counts a fractional span from the second it opened on", function()
      -- 2.5 seconds opens on "2.5 seconds" and still owes the player both
      -- whole seconds below it: rounding the opening count DOWN instead
      -- would swallow the first line.
      local travel, state = world()
      state.config.delay = 2.5
      assert.equal("Mount roulette in 2.5 seconds. /heal to cancel.", travel.arm(ENTRY))
      local said = {}
      for tenth = 1, 25 do
        state.now = 100 + tenth / 10
        local fired, line = travel.step()
        if line ~= nil then
          said[#said + 1] = line
        end
        if fired ~= nil then
          assert.equal(25, tenth, "it fires when the span runs out, not before")
        end
      end
      assert.same({ "2...", "1..." }, said)
    end)

    it("says nothing between the seconds", function()
      local travel, state = world()
      travel.arm(ENTRY)
      state.now = 100.5
      assert.is_nil(select(2, travel.step()))
      state.now = 100.9
      assert.is_nil(select(2, travel.step()))
      state.now = 101
      assert.equal("4...", select(2, travel.step()))
      assert.is_nil(select(2, travel.step()), "and never twice for the same second")
    end)

    it("says one line for a frame that swallowed several seconds", function()
      local travel, state = world()
      travel.arm(ENTRY)
      state.now = 103
      assert.equal("2...", select(2, travel.step()))
    end)

    it("fires once and then holds nothing", function()
      local travel, state = world()
      travel.arm(ENTRY)
      state.now = 200
      assert.same(ENTRY, travel.step())
      assert.is_nil(travel.step())
      assert.is_nil(travel.cancel(), "and there is nothing left to call off")
    end)

    it("answers whether anything is counting down, for the frame that has to ask", function()
      -- The widget's tick asks this before it asks whether a config mode is
      -- open, so a player with nothing counting down never pays for those
      -- reads. One comparison, no clock read of its own.
      local travel, state = world()
      state.clock_reads = 0
      assert.is_false(travel.armed())
      travel.arm(ENTRY)
      assert.is_true(travel.armed())
      travel.cancel()
      assert.is_false(travel.armed())
      state.clock_reads = 0
      assert.is_false(travel.armed())
      assert.equal(0, state.clock_reads, "asking costs no clock read")
    end)

    it("costs one comparison with nothing armed, and not even a clock read", function()
      local travel, state = world()
      state.clock_reads = 0
      local fired, line = travel.step()
      assert.is_nil(fired)
      assert.is_nil(line)
      assert.equal(0, state.clock_reads, "a settled frame asks the client nothing at all")
    end)

    it("fires nothing itself when the delay is off - the caller does", function()
      local travel, state = world()
      state.config.delay = 0
      assert.is_nil(travel.arm(ENTRY))
      assert.is_nil(travel.cancel(), "nothing armed means nothing to call off, and nothing to tick")
      state.now = 200
      assert.is_nil(travel.step())
    end)

    it("counts a one-second span in the singular", function()
      local travel, state = world()
      state.config.delay = 1
      assert.equal("Mount roulette in 1 second. /heal to cancel.", travel.arm(ENTRY))
      state.now = 101
      assert.same(ENTRY, travel.step())
    end)

    it("arms nothing for a payload with no name to say", function()
      local travel = world()
      assert.is_nil(travel.arm(nil))
      assert.is_nil(travel.arm({}))
      assert.is_nil(travel.arm("Warp"))
      assert.is_nil(travel.cancel())
    end)

    it("replaces what is counting down, so the newer press is the one that goes", function()
      -- The same discipline as the cast retry: nothing outlives the moment
      -- it belonged to, and a newer press means the player has moved on.
      local travel, state = world()
      local warp = { label = "Warp" }
      travel.arm(ENTRY)
      state.now = 102
      assert.equal("Warp in 5 seconds. /heal to cancel.", travel.arm(warp))
      state.now = 105
      assert.is_nil(travel.step(), "the first press's own moment has gone with it")
      state.now = 107
      assert.same(warp, travel.step())
    end)
  end)

  describe("calling it off", function()
    local ENTRY = { label = "Mount roulette" }
    -- Deliberately not the fallback: a spec that agreed with the constant
    -- would pass whether or not the resource table was ever read.
    local RESTING = { [7] = { en = "Resting" }, [0] = { en = "Idle" }, [1] = { en = "Engaged" } }
    -- The fallback the module carries for a client with no resources.
    local RESTING_FALLBACK = 33

    it("says a cancel rather than going quiet", function()
      local travel, state = world()
      travel.arm(ENTRY)
      assert.equal("Mount roulette cancelled.", travel.cancel())
      state.now = 200
      assert.is_nil(travel.step())
    end)

    it("has nothing to say when nothing is counting down", function()
      local travel = world()
      assert.is_nil(travel.cancel())
    end)

    it("drops the countdown without a word when the caller wants silence", function()
      local travel, state = world()
      travel.arm(ENTRY)
      assert.is_nil(travel.clear())
      assert.is_nil(travel.cancel(), "nothing left, and nothing said about it")
      state.now = 200
      assert.is_nil(travel.step())
    end)

    it("cancels on resting, read out of the resource table by name", function()
      -- Selindrile's shape: the trigger is the STATUS, so it catches
      -- resting however the player entered it, not just the /heal text.
      local travel = world({ statuses = RESTING })
      travel.arm(ENTRY)
      assert.equal("Mount roulette cancelled.", travel.on_status(7))
      assert.is_nil(travel.cancel(), "and there is nothing left to call off")
    end)

    it("ignores every other status", function()
      local travel, state = world({ statuses = RESTING })
      travel.arm(ENTRY)
      for _, status in ipairs({ 0, 1, 2, 4, RESTING_FALLBACK }) do
        assert.is_nil(travel.on_status(status), tostring(status))
      end
      assert.is_nil(travel.on_status(nil))
      state.now = 105
      assert.same(ENTRY, travel.step(), "the countdown was still running")
    end)

    it("matches the name however the resource table cases it", function()
      local travel = world({ statuses = { [9] = { en = "resting" } } })
      travel.arm(ENTRY)
      assert.equal("Mount roulette cancelled.", travel.on_status(9))
    end)

    it("falls back to the recorded number without the resources library", function()
      -- Degrade to the constant rather than lose the cancel altogether.
      for _, statuses in ipairs({ { nil }, { 42 }, { { [0] = { en = "Idle" } } }, { { { en = 5 } } } }) do
        local travel = world({ statuses = statuses[1] })
        travel.arm(ENTRY)
        assert.equal("Mount roulette cancelled.", travel.on_status(RESTING_FALLBACK))
      end
    end)

    it("has nothing to say about a status while nothing is counting down", function()
      local travel = world({ statuses = RESTING })
      assert.is_nil(travel.on_status(7))
    end)
  end)

  describe("how much it says", function()
    --[[ One line per second for the LAST FIVE only (Kevin, live client,
         2026-08-22). The countdown used to speak every second of whatever
         span it was armed for, which is fine at the default five and a wall
         of text at thirty - and thirty-second waits are exactly what the
         warp ladder's ring rungs produce. ]]
    it("stays quiet above five seconds and counts the last five", function()
      local travel, clock = world({ config = { delay = 30 } })
      local opening = travel.arm({ label = "Warp Ring" })
      assert.is_string(opening)
      assert.is_not_nil(opening:find("30", 1, true), opening)

      local said = {}
      for elapsed = 1, 30 do
        clock.now = 100 + elapsed
        local entry, line = travel.step()
        if line ~= nil then
          said[#said + 1] = line
        end
        if entry ~= nil then
          said[#said + 1] = "FIRED"
        end
      end
      assert.are.same({ "5...", "4...", "3...", "2...", "1...", "FIRED" }, said)
    end)

    it("still counts a whole five-second wait, which is every second of it", function()
      local travel, clock = world({ config = { delay = 5 } })
      travel.arm({ label = "Warp" })
      local said = {}
      for elapsed = 1, 5 do
        clock.now = 100 + elapsed
        local entry, line = travel.step()
        if line ~= nil then
          said[#said + 1] = line
        end
        if entry ~= nil then
          said[#said + 1] = "FIRED"
        end
      end
      assert.are.same({ "4...", "3...", "2...", "1...", "FIRED" }, said)
    end)
  end)
end)
