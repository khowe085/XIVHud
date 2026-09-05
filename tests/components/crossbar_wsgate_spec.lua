local new_wsgate = require("components/crossbar/wsgate")

--[[ A press the game would refuse, and the facts the widget hands over to
     find that out. The defaults describe a legal weaponskill: 1000 TP,
     engaged, an unclaimed mob two yalms away, and a sword in hand. Every
     test below spoils exactly ONE of them, so a refusal can only be the
     rule under test. ]]
--[[ Overriding a fact to nil is INVISIBLE to pairs, so a spoiled fact has
     to be said out loud. Every `nil` written as an override below silently
     kept the default and made its test pass for the wrong reason. ]]
local NONE = {}

local function facts(overrides)
  local built = {
    tp = 1000,
    status = 1,
    skill = "Sword",
    -- The mob table reports the SQUARE of the distance (targetbar/logic.lua
    -- takes the same sqrt), which is why the name says so. 4 is two yalms,
    -- well inside the fixture's reach of 3.
    distance_squared = 4,
    model_size = 1,
  }
  for key, value in pairs(overrides or {}) do
    if value == NONE then
      built[key] = nil
    else
      built[key] = value
    end
  end
  return built
end

local function world(overrides)
  local state = {
    now = 100,
    config = { enabled = true, melee_range = 3, size_pivot = 1.3 },
  }
  for key, value in pairs(overrides or {}) do
    state[key] = value
  end
  local wsgate = new_wsgate({
    now = function()
      return state.now
    end,
    config = function()
      return state.config
    end,
    statuses = state.statuses,
  })
  return wsgate, state
end

local WS = { type = "ws", action = "Savage Blade", target = "t" }

describe("crossbar weaponskill gate", function()
  describe("the shipped config", function()
    it("ships off, with the melee reach beside it", function()
      local wsgate = world()
      assert.same({ enabled = false, melee_range = 4, size_pivot = 1.3 }, wsgate.defaults())
    end)

    it("is off unless the config says true outright", function()
      --[[ The cast retry's reading exactly, and for the same reason: a
           feature that ships off must not be switched on by a hand-broken
           config, so a truthy value is not enough. It read the opposite way
           for a day, while the gate shipped on. ]]
      local wsgate, state = world()
      assert.is_true(wsgate.enabled())
      state.config = nil
      assert.is_false(wsgate.enabled())
      state.config = 42
      assert.is_false(wsgate.enabled())
      state.config = {}
      assert.is_false(wsgate.enabled())
      state.config = { enabled = false }
      assert.is_false(wsgate.enabled())
      state.config = { enabled = "yes" }
      assert.is_false(wsgate.enabled())
    end)

    it("reads the live config, so a write takes effect at once", function()
      local wsgate, state = world()
      assert.is_false(wsgate.allow(WS, facts({ tp = 0 })))
      state.config.enabled = false
      assert.is_true(wsgate.allow(WS, facts({ tp = 0 })))
    end)
  end)

  describe("what it is not the business of", function()
    it("passes every type but ws, however hostile the facts", function()
      local wsgate = world()
      local hostile = facts({ tp = 0, status = 0, distance_squared = 400, model_size = 1 })
      for _, record_type in ipairs({ "ma", "ja", "item", "pet", "mount", "ct", "ex", "warp" }) do
        assert.is_true(wsgate.allow({ type = record_type, action = "x" }, hostile))
      end
    end)

    it("passes a weaponskill outright once switched off", function()
      local wsgate, state = world()
      state.config.enabled = false
      assert.is_true(wsgate.allow(WS, facts({ tp = 0, status = 0, distance_squared = 400, model_size = 1 })))
    end)

    it("passes a record that is not a table at all rather than throwing", function()
      -- allow() is called from the key handler; an error there is swallowed
      -- by lib/guard and takes the whole press with it.
      local wsgate = world()
      assert.is_true(wsgate.allow(nil, facts()))
      assert.is_true(wsgate.allow(WS, nil))
    end)
  end)

  describe("TP", function()
    it("refuses under a thousand and allows at it", function()
      local wsgate = world()
      assert.is_false(wsgate.allow(WS, facts({ tp = 999 })))
      assert.is_true(wsgate.allow(WS, facts({ tp = 1000 })))
      assert.is_true(wsgate.allow(WS, facts({ tp = 3000 })))
    end)

    it("allows a TP it could not read", function()
      -- The first frames of a login, where the client has not filled the
      -- vitals in yet. Ignorance is not a refusal.
      local wsgate = world()
      assert.is_true(wsgate.allow(WS, facts({ tp = NONE })))
      assert.is_true(wsgate.allow(WS, facts({ tp = "lots" })))
    end)
  end)

  describe("engagement", function()
    it("refuses while not engaged", function()
      local wsgate = world()
      assert.is_false(wsgate.allow(WS, facts({ status = 0 })))
      assert.is_false(wsgate.allow(WS, facts({ status = 33 })))
      assert.is_true(wsgate.allow(WS, facts({ status = 1 })))
    end)

    it("resolves engaged from the resource table rather than the constant", function()
      -- travel.lua's idiom: the english name is what survives a client
      -- update, and the constant is only what stands in when the resources
      -- library did not load.
      local wsgate = world({ statuses = { [44] = { en = "Engaged" }, [0] = { en = "Idle" } } })
      assert.is_true(wsgate.allow(WS, facts({ status = 44 })))
      assert.is_false(wsgate.allow(WS, facts({ status = 1 })))
    end)

    it("allows a status it could not read", function()
      local wsgate = world()
      assert.is_true(wsgate.allow(WS, facts({ status = NONE })))
    end)
  end)

  describe("melee reach", function()
    it("measures the reach against the distance the target bar prints", function()
      --[[ The setting IS that distance (Kevin, 2026-09-05): it is what a
           player reads off the target bar, so a number settled by watching
           one is the number to type. A mob's bulk is added to it past the
           pivot; the fixture's mob is under the pivot, so its reach is the
           bare 3 and the squared distance turns at 9. ]]
      local wsgate = world()
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 8.9, model_size = 1 })))
      assert.is_false(wsgate.allow(WS, facts({ distance_squared = 9.1, model_size = 1 })))
      --[[ AT the setting still fires: Kevin's own readings are the ones a
           player types in, and a weaponskill landed at a target bar 4, so a
           reach of 4 must not refuse 4. The setting is the furthest
           distance that still goes out, not the first one refused. ]]
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 9, model_size = 1 })))
    end)

    --[[ THE FIVE READINGS the size correction was fitted to (Kevin, live
         client, 2026-09-05), model size against the furthest distance a
         weaponskill still landed from. The first three are what prove there
         is a FLOOR: three different sizes all cap at the same 4, so the
         reach does not shrink with a small mob, and a plain `base + size`
         fit would have refused the 1.0 mob at a distance that worked.

         They are LOWER BOUNDS - the furthest distance that still landed,
         not the first that failed - so the rule is that every cutoff must
         REACH its reading. That is what fixes the pivot: the 6.3 mob puts
         it at 1.3 or under, the 2.5 mob at 1.5 or under, and the tightest
         value honouring both is 1.3. ]]
    local READINGS = {
      { size = 1.0, worked_at = 4 },
      { size = 1.2, worked_at = 4 },
      { size = 1.5, worked_at = 4 },
      { size = 2.5, worked_at = 5 },
      { size = 6.3, worked_at = 9 },
    }

    it("reaches every distance those five readings say it should", function()
      local wsgate, state = world()
      state.config.melee_range = 4
      for _, reading in ipairs(READINGS) do
        local label = "model size " .. reading.size
        assert.is_true(
          wsgate.allow(WS, facts({ distance_squared = reading.worked_at ^ 2, model_size = reading.size })),
          label .. " at " .. reading.worked_at .. " worked in a client"
        )
        assert.is_false(
          wsgate.allow(WS, facts({ distance_squared = (reading.worked_at + 1) ^ 2, model_size = reading.size })),
          label .. " a yalm further out"
        )
      end
    end)

    it("holds the floor for every mob at or under the pivot", function()
      -- The reach never SHRINKS with a small mob: below the pivot the
      -- setting is the whole of it, which is what the first three readings
      -- say and what keeps melee_range meaning what it already meant.
      local wsgate = world()
      for _, size in ipairs({ 0.1, 1, 1.3 }) do
        assert.is_true(wsgate.allow(WS, facts({ distance_squared = 8.9, model_size = size })), size)
        assert.is_false(wsgate.allow(WS, facts({ distance_squared = 9.1, model_size = size })), size)
      end
    end)

    it("grows one for one with the bulk past the pivot", function()
      local wsgate = world()
      -- Pivot 1.3, reach 3: a mob of 4.5 adds 3.2, so the cutoff is 6.2.
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 38.3, model_size = 4.5 })))
      assert.is_false(wsgate.allow(WS, facts({ distance_squared = 38.6, model_size = 4.5 })))
    end)

    it("takes the pivot from the live config, and falls back over a broken one", function()
      local wsgate, state = world()
      state.config.size_pivot = 4.5
      -- Nothing is added below the pivot, so the 4.5 mob is back on the
      -- bare reach of 3.
      assert.is_false(wsgate.allow(WS, facts({ distance_squared = 9.1, model_size = 4.5 })))
      for _, broken in ipairs({ "big", -1, 0 / 0 }) do
        state.config.size_pivot = broken
        assert.is_true(wsgate.allow(WS, facts({ distance_squared = 35.9, model_size = 4.5 })), tostring(broken))
      end
      -- Zero is a legitimate pivot, not a broken one: it means every mob
      -- adds the whole of its bulk. Reach 3 plus 4.5 is 7.5.
      state.config.size_pivot = 0
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 56, model_size = 4.5 })))
    end)

    it("sits the reach out for a mob whose size it could not read", function()
      --[[ Ignorance allows, and here that matters both ways: without the
           size there is no telling a rabbit from a monster, and measuring
           the monster on the bare reach would refuse a press that lands. ]]
      local wsgate = world()
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 9999, model_size = NONE })))
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 9999, model_size = "huge" })))
    end)

    it("reaches further at a bigger mob, and not at a small one", function()
      --[[ The inverse of what this test said for one day. The model sizes
           were dropped when the units were settled, which made a large
           monster unreachable - its own bulk keeping you outside the reach
           you had measured on a rabbit - and they came back as a pivot. ]]
      local wsgate = world()
      assert.is_false(wsgate.allow(WS, facts({ distance_squared = 25, model_size = 1 })))
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 25, model_size = 3.3 })))
    end)

    it("takes the reach from the live config", function()
      local wsgate, state = world()
      assert.is_false(wsgate.allow(WS, facts({ distance_squared = 9.1, model_size = 1 })))
      state.config.melee_range = 4
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 9.1, model_size = 1 })))
    end)

    it("falls back to the shipped reach for a hand-broken one", function()
      -- The shipped 4, so the squared distance turns at 16 rather than the
      -- fixture's 9.
      local wsgate, state = world()
      for _, broken in ipairs({ "close", -1, 0 / 0 }) do
        state.config.melee_range = broken
        assert.is_false(wsgate.allow(WS, facts({ distance_squared = 16.1, model_size = 1 })))
        assert.is_true(wsgate.allow(WS, facts({ distance_squared = 15.9, model_size = 1 })))
      end
    end)

    it("allows a distance it could not read", function()
      -- Nothing selected reaches here as no distance at all, and allows:
      -- engaging locks your target to an attackable mob, so a weaponskill
      -- press with nothing to measure against is the game's to refuse.
      local wsgate = world()
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = NONE })))
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = "far" })))
    end)

    it("never measures a ranged weaponskill", function()
      --[[ Archery and Marksmanship reach far past any melee number, and
           their band is DistancePlus' rather than this one - a port that
           lives in the targetbar and cannot be required from here. So a
           ranged weaponskill is gated on everything except the distance. ]]
      local wsgate = world()
      local far = facts({ distance_squared = 400, model_size = 1, skill = "Archery" })
      assert.is_true(wsgate.allow(WS, far))
      far.skill = "Marksmanship"
      assert.is_true(wsgate.allow(WS, far))
      far.skill = "marksmanship"
      assert.is_true(wsgate.allow(WS, far))
      -- Throwing is the third of them: render.lua's own art branch knows
      -- all three, and a boomerang weaponskill is thrown from range.
      far.skill = "Throwing"
      assert.is_true(wsgate.allow(WS, far))
      -- Everything else still applies to it.
      far.tp = 0
      assert.is_false(wsgate.allow(WS, far))
    end)

    it("measures a weaponskill whose skill it could not name", function()
      -- The reverse of the rule above, and deliberately: an unnamed skill
      -- is far more likely a melee one the resources did not answer for
      -- than a bow, and the melee test is the conservative reading.
      local wsgate = world()
      assert.is_false(wsgate.allow(WS, facts({ skill = NONE, distance_squared = 400, model_size = 1 })))
    end)
  end)
end)
