local new_retry = require("components/crossbar/retry")

local ME = 777
local SOMEONE_ELSE = 42
-- The unconfirmed trigger: 0x029 carrying action message 17 or 18.
local ACTION_MESSAGE_CHUNK = 0x029
local REFUSED = 17

local RECORD = { type = "ma", action = "Cure", target = "t" }
local COMMAND = 'input /ma "Cure" <t>'

-- Little-endian, the client's own byte order.
local function le(value, bytes)
  local out = {}
  for _ = 1, bytes do
    out[#out + 1] = string.char(value % 256)
    value = math.floor(value / 256)
  end
  return table.concat(out)
end

--[[ A 0x029 body in Windower's field order: the 4-byte chunk header, Actor,
     Target, Param 1, Param 2, Actor Index, Target Index, Message - the same
     layout skillchain.lua reads the wear-off message out of. ]]
local function packet(actor, message)
  return le(0, 4) .. le(actor, 4) .. le(0, 4) .. le(0, 4) .. le(0, 4) .. le(0, 2) .. le(0, 2) .. le(message, 2)
end

local function world(overrides)
  local state = {
    now = 100,
    player = { id = ME },
    config = { enabled = true, window = 2, backoff = 1, deadline = 5, attempts = 3 },
    player_reads = 0,
  }
  for key, value in pairs(overrides or {}) do
    state[key] = value
  end
  local retry = new_retry({
    now = function()
      return state.now
    end,
    config = function()
      return state.config
    end,
    get_player = function()
      state.player_reads = state.player_reads + 1
      return state.player
    end,
  })
  return retry, state
end

local function press(command)
  return { record = RECORD, command = command or COMMAND, kind = "spell", set = 1, side = "left", slot = 3 }
end

-- The same press for an ability or a weaponskill: a different refusal
-- message answers it, and a different buff makes it impossible.
local function press_kind(kind)
  local entry = press('input /ja "Provoke" <t>')
  entry.kind = kind
  return entry
end

describe("crossbar cast retry", function()
  describe("what went out", function()
    it("remembers the spell a slot press sent, with nothing pending", function()
      local retry = world()
      retry.sent(press())
      local held = retry.held()
      assert.is_table(held)
      assert.equal(COMMAND, held.command)
      assert.equal(RECORD, held.record)
      assert.equal(0, held.attempts)
      assert.is_nil(retry.pending())
    end)

    it("carries the whole press through, whatever the widget put on it", function()
      -- The press is the widget's shape, not this module's: the address it
      -- came from and the target it was pinned to are read back by the
      -- guards, and a field this module does not name must still arrive.
      local retry = world()
      retry.sent({
        record = RECORD,
        command = COMMAND,
        kind = "spell",
        set = 2,
        side = "right",
        slot = 7,
        follows_target = true,
        target = 99,
      })
      local held = retry.held()
      assert.equal(2, held.set)
      assert.equal("right", held.side)
      assert.equal(7, held.slot)
      assert.is_true(held.follows_target)
      assert.equal(99, held.target)
    end)

    it("cannot be rewritten through the table it was handed", function()
      -- The copy is defensive: the widget builds a fresh table per press
      -- today, so nothing reaches back into it - but what is being watched
      -- decides what gets sent, and it is not the caller's to edit after
      -- the fact.
      local retry = world()
      local entry = press()
      retry.sent(entry)
      entry.command = 'input /ma "Death" <t>'
      entry.slot = 8
      assert.equal(COMMAND, retry.held().command)
      assert.equal(3, retry.held().slot)
    end)

    it("keeps its own bookkeeping to itself", function()
      -- A press cannot smuggle in an attempt count or a deadline.
      local retry = world()
      retry.sent({ record = RECORD, command = COMMAND, kind = "spell", attempts = 99, first_at = 0, due_at = 0 })
      assert.equal(0, retry.held().attempts)
      assert.equal(100, retry.held().first_at)
      assert.is_nil(retry.held().due_at)
    end)

    it("remembers nothing while the feature is off", function()
      local retry, state = world()
      state.config.enabled = false
      retry.sent(press())
      assert.is_nil(retry.held())
    end)
  end)

  describe("the refusal", function()
    it("makes the record pending when it names us, soon after our send", function()
      local retry, state = world()
      retry.sent(press())
      state.now = state.now + 0.3
      assert.is_true(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)))
      local owed = retry.pending()
      assert.is_table(owed)
      assert.equal(COMMAND, owed.command)
    end)

    it("takes the second refusal message too", function()
      local retry = world()
      retry.sent(press())
      assert.is_true(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, 18)))
      assert.is_not_nil(retry.pending())
    end)

    it("ignores a refusal aimed at someone else", function()
      local retry = world()
      retry.sent(press())
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(SOMEONE_ELSE, REFUSED)))
      assert.is_nil(retry.pending())
      assert.is_not_nil(retry.held(), "someone else's refusal does not forget our send")
    end)

    it("ignores a refusal that arrives long after our send, and keeps watching", function()
      local retry, state = world()
      retry.sent(press())
      state.now = state.now + 2.01
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)))
      assert.is_nil(retry.pending())
      assert.is_not_nil(retry.held())
    end)

    it("ignores a refusal with nothing sent", function()
      local retry = world()
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)))
      assert.is_nil(retry.pending())
      assert.is_nil(retry.held())
    end)

    it("ignores any other action message on the same packet", function()
      local retry = world()
      retry.sent(press())
      -- 206 is the wear-off skillchain.lua reads off this very chunk.
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, 206)))
      assert.is_nil(retry.pending())
    end)

    it("ignores every other chunk, and anything that is not a chunk body", function()
      local retry = world()
      retry.sent(press())
      assert.is_false(retry.on_chunk(0x028, packet(ME, REFUSED)))
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, nil))
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, 42))
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED):sub(1, 25)))
      assert.is_nil(retry.pending())
    end)

    it("reads the player only once the cheap checks have passed", function()
      local retry, state = world()
      retry.sent(press())
      retry.on_chunk(0x028, packet(ME, REFUSED))
      retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, 206))
      assert.equal(0, state.player_reads, "other people's traffic must cost no client call")
      retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED))
      assert.equal(1, state.player_reads)
    end)

    it("ignores a refusal it cannot match, with no player to match against", function()
      local retry, state = world()
      retry.sent(press())
      state.player = nil
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)))
      assert.is_nil(retry.pending())
    end)

    it("does not push the backoff out when a second refusal arrives for the same send", function()
      -- Both message ids are believed to mean the same thing, and nobody
      -- has seen which the client sends; two for one press must not put the
      -- re-send off by another whole backoff.
      local retry, state = world()
      retry.sent(press())
      assert.is_true(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, 17)))
      state.now = state.now + 0.5
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, 18)), "already owed a re-send")
      state.now = state.now + 0.5
      assert.is_not_nil(
        retry.step(function()
          return { bound = true, recast = 0, affordable = true, buffs = {} }
        end),
        "still due one second after the FIRST refusal"
      )
    end)

    it("ignores a refusal while the feature is off", function()
      local retry, state = world()
      retry.sent(press())
      state.config.enabled = false
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)))
      assert.is_nil(retry.pending())
    end)
  end)

  describe("what the refusal has to say", function()
    -- Each kind of action is refused in its own words, so the message that
    -- answers a spell must not answer an ability, and the reverse.
    local MESSAGES = { spell = { 17, 18 }, ability = { 71 }, weaponskill = { 72 } }

    it("takes only the refusal messages its own kind is refused with", function()
      for kind, mine in pairs(MESSAGES) do
        for _, message in ipairs(mine) do
          local retry = world()
          retry.sent(press_kind(kind))
          assert.is_true(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, message)), kind .. " / " .. message)
        end
        for other, theirs in pairs(MESSAGES) do
          if other ~= kind then
            for _, message in ipairs(theirs) do
              local retry = world()
              retry.sent(press_kind(kind))
              assert.is_false(
                retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, message)),
                kind .. " must not answer to " .. other .. "'s message " .. message
              )
            end
          end
        end
      end
    end)

    it("watches nothing for a kind it has no refusal message for", function()
      local retry = world()
      retry.sent(press_kind("item"))
      assert.is_nil(retry.held(), "not watched at all, not merely unable to go pending")
      assert.is_false(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, 17)))
      assert.is_nil(retry.pending())
    end)
  end)

  describe("the re-send", function()
    -- Every guard passing, which is what the refusal path assumes.
    local function clear_facts()
      return { bound = true, recast = 0, affordable = true, buffs = {} }
    end

    local function probe(facts)
      local calls = { count = 0 }
      return function(entry)
        calls.count = calls.count + 1
        calls.entry = entry
        return facts or clear_facts()
      end,
        calls
    end

    -- A press, refused, sitting on its backoff.
    local function refused(overrides)
      local retry, state = world(overrides)
      retry.sent(press())
      retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED))
      return retry, state
    end

    it("holds still until the backoff has run", function()
      local retry, state = refused()
      local ask, calls = probe()
      assert.is_nil(retry.step(ask))
      assert.equal(0, calls.count, "the guards are not worth asking before the re-send is due")
      state.now = state.now + 0.99
      assert.is_nil(retry.step(ask))
    end)

    it("re-sends once, then goes back to watching", function()
      local retry, state = refused()
      local ask, calls = probe()
      state.now = state.now + 1
      local resend = retry.step(ask)
      assert.is_table(resend)
      assert.equal(COMMAND, resend.command)
      assert.equal(1, calls.count)
      assert.equal(retry.held(), calls.entry, "the guards are asked about the record we are about to send")
      assert.equal(1, retry.held().attempts)
      assert.is_nil(retry.pending(), "a re-send is watched, not owed again - nothing fires twice")
      state.now = state.now + 1
      assert.is_nil(retry.step(ask), "and no second send without a second refusal")
    end)

    it("does nothing at all with nothing pending", function()
      local retry = world()
      local ask, calls = probe()
      assert.is_nil(retry.step(ask))
      retry.sent(press())
      assert.is_nil(retry.step(ask))
      assert.equal(0, calls.count)
    end)

    it("takes a fresh refusal after a re-send and sends again", function()
      local retry, state = refused()
      local ask = probe()
      state.now = state.now + 1
      assert.is_not_nil(retry.step(ask))
      assert.is_true(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)))
      state.now = state.now + 1
      assert.is_not_nil(retry.step(ask))
      assert.equal(2, retry.held().attempts)
    end)

    it("measures the refusal window from the LAST send, not the first", function()
      -- The re-send re-arms the clock. A refusal 2.3s after the original
      -- press is far outside the 2s window, but a tenth of a second after
      -- the re-send it answers - and rejecting it would silently cost the
      -- attempt that was the whole point of having a cap above one.
      local retry, state = refused()
      local ask = probe()
      state.now = state.now + 1
      assert.is_not_nil(retry.step(ask), "re-send")
      state.now = state.now + 1.3
      assert.is_true(
        retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)),
        "2.3s after the press, 0.3s after the re-send"
      )
      state.now = state.now + 1
      assert.is_not_nil(retry.step(ask), "and the next attempt goes")
      assert.equal(2, retry.held().attempts)
    end)

    it("gives up at the attempt cap", function()
      local retry, state =
        refused({ config = { enabled = true, window = 2, backoff = 1, deadline = 60, attempts = 2 } })
      local ask = probe()
      for _ = 1, 2 do
        state.now = state.now + 1
        assert.is_not_nil(retry.step(ask))
        retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED))
      end
      state.now = state.now + 1
      assert.is_nil(retry.step(ask), "the third re-send is over the cap")
      assert.is_nil(retry.held(), "and the record is dropped, not left to try again")
    end)

    it("gives up at the deadline, measured from the original press", function()
      local retry, state = refused()
      local ask, calls = probe()
      state.now = state.now + 5
      assert.is_nil(retry.step(ask))
      assert.is_nil(retry.held())
      assert.equal(0, calls.count, "an expired record is dropped without asking the guards")
    end)

    it("drops a pending cast the moment the feature is switched off", function()
      local retry, state = refused()
      local ask, calls = probe()
      state.config.enabled = false
      state.now = state.now + 1
      assert.is_nil(retry.step(ask), "switching off drops the cast, it does not let a last one through")
      assert.is_nil(retry.held())
      assert.equal(0, calls.count)
    end)
  end)

  describe("the guards", function()
    local function facts(overrides)
      local table_ = { bound = true, recast = 0, affordable = true, buffs = {} }
      for key, value in pairs(overrides or {}) do
        table_[key] = value
      end
      return table_
    end

    -- A refused press with its backoff run out, ready to re-send.
    local function due(overrides)
      local retry, state = world()
      retry.sent(press())
      retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED))
      state.now = state.now + 1
      return retry, function()
        return facts(overrides)
      end
    end

    -- A failed guard DROPS the record rather than spending an attempt:
    -- "unable to cast" has non-timing causes, and a blind retry would
    -- hammer a doomed spell until its deadline.
    local function assert_dropped(overrides, why)
      local retry, ask = due(overrides)
      assert.is_nil(retry.step(ask), why)
      assert.is_nil(retry.held(), why .. " - and it is dropped, not held for another attempt")
    end

    it("sends when every guard passes", function()
      local retry, ask = due()
      assert.is_not_nil(retry.step(ask))
    end)

    it("drops a slot that no longer holds the record it sent", function()
      assert_dropped({ bound = false }, "rebound, re-set or context-swapped")
    end)

    it("drops an action that has gone onto a recast", function()
      -- The whole reason the reference addon's queue was abandoned: it held
      -- actions blocked by a cooldown and fired them long after the moment.
      assert_dropped({ recast = 0.5 }, "on cooldown")
    end)

    it("drops an action there is no longer MP or TP for", function()
      assert_dropped({ affordable = false }, "unaffordable")
    end)

    it("drops a spell while silenced or muted", function()
      assert_dropped({ buffs = { 33, 6 } }, "silenced")
      assert_dropped({ buffs = { 29 } }, "muted")
    end)

    it("blocks each kind with the buffs that actually stop it", function()
      -- Silence and mute stop spells; amnesia stops abilities and
      -- weaponskills. Neither set blocks the other, and assuming otherwise
      -- would throw away retries that would have worked.
      local blocked = { spell = { 6, 29 }, ability = { 16 }, weaponskill = { 16 } }
      local kinds = { "spell", "ability", "weaponskill" }
      for _, kind in ipairs(kinds) do
        for _, buff in ipairs({ 6, 29, 16 }) do
          local stops = false
          for _, id in ipairs(blocked[kind]) do
            stops = stops or id == buff
          end
          local retry, state = world()
          retry.sent(kind == "spell" and press() or press_kind(kind))
          retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, kind == "spell" and 17 or (kind == "ability" and 71 or 72)))
          state.now = state.now + 1
          local sent = retry.step(function()
            return facts({ buffs = { buff } })
          end)
          if stops then
            assert.is_nil(sent, ("buff %d must stop a %s"):format(buff, kind))
          else
            assert.is_not_nil(sent, ("buff %d must not stop a %s"):format(buff, kind))
          end
        end
      end
    end)

    it("sends on an unknown that is not a no", function()
      -- Only `bound` is mandatory. A cost the resource tables do not carry
      -- and a recast that could not be looked up are unknowns, not
      -- evidence against a press that already went out.
      local retry, ask = due({ affordable = nil, recast = nil })
      assert.is_not_nil(retry.step(ask))
    end)

    it("sends through a buff that blocks nothing", function()
      local retry, ask = due({ buffs = { 33, 43, 252 } })
      assert.is_not_nil(retry.step(ask))
    end)

    it("drops when the guards cannot be answered at all", function()
      -- Nothing short of a clear yes sends: an empty answer, no answer, and
      -- no probe to ask are all "we do not know", which is not permission.
      local answers = {
        function()
          return {}
        end,
        function()
          return nil
        end,
        nil,
      }
      for index = 1, 3 do
        local retry, state = world()
        retry.sent(press())
        retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED))
        state.now = state.now + 1
        assert.is_nil(retry.step(answers[index]), "answer " .. index)
        assert.is_nil(retry.held(), "answer " .. index)
      end
    end)
  end)

  describe("letting go", function()
    it("forgets everything on clear", function()
      local retry = world()
      retry.sent(press())
      retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED))
      retry.clear()
      assert.is_nil(retry.held())
      assert.is_nil(retry.pending())
    end)

    it("is replaced outright by a newer press", function()
      local retry = world()
      retry.sent(press())
      retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED))
      retry.sent(press('input /ma "Dia" <t>'))
      assert.equal('input /ma "Dia" <t>', retry.held().command)
      assert.is_nil(retry.pending(), "the newer press has not been refused")
      assert.equal(0, retry.held().attempts)
    end)

    it("is dropped by a press worth no retry at all", function()
      local retry = world()
      retry.sent(press())
      retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED))
      retry.sent(nil)
      assert.is_nil(retry.held())
    end)

    it("drops what it is watching when sync finds the feature off", function()
      local retry, state = world()
      retry.sent(press())
      retry.sync()
      assert.is_not_nil(retry.held(), "sync leaves a live feature alone")
      state.config.enabled = false
      retry.sync()
      assert.is_nil(retry.held())
    end)
  end)

  describe("the shipped config", function()
    it("ships off, with a tuning block", function()
      local defaults = world().defaults()
      assert.is_false(defaults.enabled)
      for _, key in ipairs({ "window", "backoff", "deadline", "attempts" }) do
        assert.is_true(type(defaults[key]) == "number" and defaults[key] > 0, key)
      end
    end)

    it("falls back to the shipped number for a hand-broken tuning value", function()
      local retry, state = world()
      state.config = { enabled = true, window = "soon", backoff = {}, deadline = false, attempts = nil }
      retry.sent(press())
      assert.is_true(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)), "window fell back")
      state.now = state.now + retry.defaults().backoff
      assert.is_not_nil(
        retry.step(function()
          return { bound = true, recast = 0, affordable = true, buffs = {} }
        end),
        "backoff, deadline and attempts fell back"
      )
    end)

    it("takes nothing but a literal true for the switch", function()
      -- A hand-edited `retry = { enabled = 1 }` is not consent to run a
      -- feature whose trigger nobody has seen fire.
      for _, truthy in ipairs({ 1, "on", "true", {} }) do
        local retry, state = world()
        state.config.enabled = truthy
        assert.is_false(retry.enabled(), tostring(truthy))
        retry.sent(press())
        assert.is_nil(retry.held(), tostring(truthy))
      end
    end)

    it("will not let a hand-edited backoff spend every attempt at once", function()
      -- The other three tunings fail safe on a bad sign: a zero or negative
      -- window, deadline or attempt cap simply stops the retry. A backoff
      -- of zero does the opposite - every attempt fires on consecutive
      -- frames, which is the hammering the whole design avoids.
      for _, bad in ipairs({ 0, -5 }) do
        local retry, state = world()
        state.config.backoff = bad
        retry.sent(press())
        assert.is_true(retry.on_chunk(ACTION_MESSAGE_CHUNK, packet(ME, REFUSED)), tostring(bad))
        assert.is_nil(
          retry.step(function()
            return { bound = true, recast = 0, affordable = true, buffs = {} }
          end),
          "backoff " .. bad .. " must still make the tick wait"
        )
      end
    end)

    it("stays off for a config block that is not a table", function()
      local retry, state = world()
      state.config = "yes please"
      assert.is_false(retry.enabled())
      retry.sent(press())
      assert.is_nil(retry.held())
    end)
  end)
end)
