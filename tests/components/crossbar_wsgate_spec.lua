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
    config = { enabled = true, melee_range = 3 },
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
    it("ships on, with the melee reach beside it", function()
      local wsgate = world()
      assert.same({ enabled = true, melee_range = 4 }, wsgate.defaults())
    end)

    it("is on unless the config says false outright", function()
      -- The opposite reading to the cast retry's, and deliberately: that
      -- feature ships off, so only `true` turns it on. This one ships ON,
      -- so a hand-broken config must read as on rather than silently
      -- disabling a guard the player never switched off.
      local wsgate, state = world()
      assert.is_true(wsgate.enabled())
      state.config = nil
      assert.is_true(wsgate.enabled())
      state.config = 42
      assert.is_true(wsgate.enabled())
      state.config = {}
      assert.is_true(wsgate.enabled())
      state.config = { enabled = false }
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
      local hostile = facts({ tp = 0, status = 0, distance_squared = 400 })
      for _, record_type in ipairs({ "ma", "ja", "item", "pet", "mount", "ct", "ex", "warp" }) do
        assert.is_true(wsgate.allow({ type = record_type, action = "x" }, hostile))
      end
    end)

    it("passes a weaponskill outright once switched off", function()
      local wsgate, state = world()
      state.config.enabled = false
      assert.is_true(wsgate.allow(WS, facts({ tp = 0, status = 0, distance_squared = 400 })))
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
      --[[ The setting IS that distance (Kevin, 2026-09-05, off two live
           readings): no model sizes are added to it, so a number settled by
           watching the target bar is the number to type. The fixture's reach
           is 3, so the squared distance turns at 9. ]]
      local wsgate = world()
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 8.9 })))
      assert.is_false(wsgate.allow(WS, facts({ distance_squared = 9.1 })))
      --[[ AT the setting still fires: Kevin's own readings are the ones a
           player types in, and a weaponskill landed at a target bar 4, so a
           reach of 4 must not refuse 4. The setting is the furthest
           distance that still goes out, not the first one refused. ]]
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 9 })))
    end)

    it("does not reach further at a bigger mob", function()
      -- The model sizes were consulted until the units were settled; a mob
      -- the size of a house is measured exactly like a rabbit now, which is
      -- why the mob does not reach this module at all - only its distance.
      local wsgate = world()
      assert.is_false(wsgate.allow(WS, facts({ distance_squared = 9.1 })))
    end)

    it("takes the reach from the live config", function()
      local wsgate, state = world()
      assert.is_false(wsgate.allow(WS, facts({ distance_squared = 9.1 })))
      state.config.melee_range = 4
      assert.is_true(wsgate.allow(WS, facts({ distance_squared = 9.1 })))
    end)

    it("falls back to the shipped reach for a hand-broken one", function()
      -- The shipped 4, so the squared distance turns at 16 rather than the
      -- fixture's 9.
      local wsgate, state = world()
      for _, broken in ipairs({ "close", -1, 0 / 0 }) do
        state.config.melee_range = broken
        assert.is_false(wsgate.allow(WS, facts({ distance_squared = 16.1 })))
        assert.is_true(wsgate.allow(WS, facts({ distance_squared = 15.9 })))
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
      local far = facts({ distance_squared = 400, skill = "Archery" })
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
      assert.is_false(wsgate.allow(WS, facts({ skill = NONE, distance_squared = 400 })))
    end)
  end)
end)
