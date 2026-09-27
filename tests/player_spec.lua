local new_player = require("lib/player")

describe("player service", function()
  local clock, calls, client, mob_args, service

  before_each(function()
    clock = 0
    calls = { player = 0, party = 0, info = 0, mob = 0 }
    mob_args = {}
    client = {
      player = {
        name = "Kevin",
        main_job = "WHM",
        vitals = { hp = 1000, hpp = 100, mp = 500, mpp = 100, tp = 0 },
      },
      party = { p0 = { name = "Kevin" } },
      info = { zone = 230 },
      mobs = { t = { id = 7 }, me = { id = 1 } },
    }
    service = new_player({
      now = function()
        return clock
      end,
      get_player = function()
        calls.player = calls.player + 1
        return client.player
      end,
      get_party = function()
        calls.party = calls.party + 1
        return client.party
      end,
      get_info = function()
        calls.info = calls.info + 1
        return client.info
      end,
      get_mob_by_target = function(...)
        calls.mob = calls.mob + 1
        mob_args[#mob_args + 1] = { ... }
        return client.mobs[(...)]
      end,
    })
  end)

  describe("the read interval", function()
    it("reads the client once however many callers ask inside one interval", function()
      for _ = 1, 20 do
        service.get_player()
        service.get_party()
        service.get_info()
      end
      assert.are.equal(1, calls.player)
      assert.are.equal(1, calls.party)
      assert.are.equal(1, calls.info)
    end)

    it("reads again once the interval has passed", function()
      service.get_player()
      clock = 0.19
      service.get_player()
      assert.are.equal(1, calls.player)

      clock = 0.2
      service.get_player()
      assert.are.equal(2, calls.player)
    end)

    -- Each source re-arms for itself, so each is pinned for itself: a staleness
    -- flag that stopped being set would otherwise show up in one spec only.
    it("re-arms the party and the zone too", function()
      service.get_party()
      service.get_info()
      clock = 0.19
      service.get_party()
      service.get_info()
      assert.are.equal(1, calls.party)
      assert.are.equal(1, calls.info)

      clock = 0.2
      service.get_party()
      service.get_info()
      assert.are.equal(2, calls.party)
      assert.are.equal(2, calls.info)
    end)

    -- Each read is lazy: a caller that never asks for the party never costs one.
    it("does not read something nobody asked for", function()
      service.get_player()
      clock = 1
      service.get_player()
      assert.are.equal(0, calls.party)
    end)

    it("hands back what the client gave", function()
      assert.are.equal("Kevin", service.get_player().name)
      assert.are.equal(client.party, service.get_party())
      assert.are.equal(230, service.get_info().zone)
    end)

    --[[ The crossbar's zone read is `pcall(read_info)` and swallows the error.
         Clearing the flag before the call would have that throw count as the
         interval's read, and every later call in it would hand back the
         pre-throw value with nothing to say anything had failed. ]]
    it("retries inside the interval when the client read threw", function()
      local raising = true
      service = new_player({
        now = function()
          return clock
        end,
        get_info = function()
          calls.info = calls.info + 1
          if raising then
            error("the client is not ready")
          end
          return client.info
        end,
        get_player = function()
          return client.player
        end,
        get_party = function()
          return client.party
        end,
        get_mob_by_target = function() end,
      })

      assert.has.errors(function()
        service.get_info()
      end)
      raising = false
      assert.are.equal(230, service.get_info().zone, "served the interval from a read that threw")
      assert.are.equal(2, calls.info)
    end)

    it("survives a client that answers nothing", function()
      client.player, client.party, client.info = nil, nil, nil
      assert.is_nil(service.get_player())
      assert.is_nil(service.get_party())
      assert.is_nil(service.get_info())
    end)

    -- A zone or a login: everything the client could say has moved under us,
    -- and the rest of the interval is not worth waiting out.
    it("re-reads at once when invalidated", function()
      service.get_player()
      service.get_party()
      service.invalidate()
      service.get_player()
      service.get_party()
      assert.are.equal(2, calls.player)
      assert.are.equal(2, calls.party)
    end)

    --[[ Buff gains and losses are much the most frequent trigger, and only the
         player is stale for one. Dropping the whole interval would re-read the
         party and the zone as well, and push the party list through a full
         roster rebuild and the target bar through an eighteen-member walk, for
         a fact neither of them holds. ]]
    it("re-reads only the named source when the invalidation is keyed", function()
      service.get_player()
      service.get_party()
      service.get_info()

      service.invalidate("player")
      service.get_player()
      service.get_party()
      service.get_info()

      assert.are.equal(2, calls.player)
      assert.are.equal(1, calls.party, "the party was re-read for a player-only invalidation")
      assert.are.equal(1, calls.info, "the zone was re-read for a player-only invalidation")
    end)

    --[[ A keyed invalidation must NOT move the counter: consumers gate a roster
         rebuild on it, so bumping it would put them through the very work the
         keyed form exists to avoid. ]]
    it("leaves the counter alone on a keyed invalidation", function()
      service.get_player()
      local before = service.generation()
      service.invalidate("player")
      service.get_player()
      assert.are.equal(before, service.generation())
    end)

    --[[ A zone is the case: the mobs the memo remembers are gone, and a key
         press arriving before the next prerender would resolve a target out of
         the previous zone. A keyed invalidation leaves the memo alone - a buff
         does not move anybody. ]]
    it("drops the mob memo too when everything is invalidated", function()
      service.get_mob_by_target("t")
      service.invalidate()
      client.mobs.t = { id = 9 }
      assert.are.equal(9, service.get_mob_by_target("t").id, "kept a target from before the zone")
    end)

    it("keeps the mob memo on a keyed invalidation", function()
      service.get_mob_by_target("t")
      service.invalidate("player")
      client.mobs.t = { id = 9 }
      assert.are.equal(7, service.get_mob_by_target("t").id, "a buff moved nobody, but the memo went")
    end)

    it("refuses a key it does not know rather than silently doing nothing", function()
      service.get_player()
      service.get_party()
      service.invalidate("wisdom")
      service.get_player()
      service.get_party()
      assert.are.equal(2, calls.player, "an unknown key must fall back to invalidating everything")
      assert.are.equal(2, calls.party)
    end)
  end)

  describe("the generation counter", function()
    -- How a consumer tells a fresh read from a cached one, so work it only wants
    -- to do per interval - the party list resetting its packet overlay - can key
    -- off it while still calling every frame.
    it("stands still inside an interval", function()
      local first = service.generation()
      service.get_player()
      service.get_party()
      assert.are.equal(first, service.generation())
    end)

    it("moves once per interval, not once per read", function()
      local before = service.generation()
      clock = 0.2
      service.get_player()
      service.get_party()
      service.get_info()
      assert.are.equal(before + 1, service.generation())
    end)

    it("moves when invalidated", function()
      local before = service.generation()
      service.invalidate()
      service.get_player()
      assert.are.equal(before + 1, service.generation())
    end)

    --[[ Reading the counter opens the interval itself. A consumer may gate ALL
         of its reads behind the counter - targetbar does - and if only a read
         could advance it, that consumer would never read again after its first
         frame. It worked at first only because parambar happened to read the
         player unconditionally earlier in the same frame, which is a cross-
         component ordering dependency and not something to rely on. ]]
    it("moves for a caller that reads nothing else", function()
      local seen = { service.generation() }
      for tick = 1, 120 do
        clock = tick / 60
        local now = service.generation()
        if now ~= seen[#seen] then
          seen[#seen + 1] = now
        end
      end
      -- A floor rather than an exact count: each interval is anchored to the
      -- call that opened it, so a frame that lands a hair short pushes the next
      -- one a frame later. Ten in two seconds is the point; two would be the bug.
      assert.is_true(#seen >= 10, "the counter stalled for a caller that only gates on it, saw " .. #seen)
    end)

    it("does not read the client merely because the counter was read", function()
      service.generation()
      service.generation()
      assert.are.equal(0, calls.player, "reading the counter must not cost a client read")
    end)
  end)

  describe("mob lookups", function()
    it("reads the client once per distinct target inside a frame", function()
      for _ = 1, 10 do
        service.get_mob_by_target("t")
      end
      assert.are.equal(1, calls.mob)
      assert.are.equal(7, service.get_mob_by_target("t").id)
    end)

    it("keys the memo by the target, not by the call", function()
      service.get_mob_by_target("t")
      service.get_mob_by_target("me")
      assert.are.equal(2, calls.mob)
      assert.are.equal(1, service.get_mob_by_target("me").id)
    end)

    it("reads again in the next frame, because the target moves", function()
      service.get_mob_by_target("t")
      service.begin_frame()
      service.get_mob_by_target("t")
      assert.are.equal(2, calls.mob)
    end)

    -- Narrowing the arity would break the skillchain engine's ('t', 'bt')
    -- fallback pair, and a pair must not share a memo slot with a single.
    it("passes every argument through and keys on all of them", function()
      service.get_mob_by_target("t", "bt")
      service.get_mob_by_target("t")
      assert.are.same({ "t", "bt" }, mob_args[1])
      assert.are.same({ "t" }, mob_args[2])
      assert.are.equal(2, calls.mob)
    end)

    --[[ Only fixed tokens are ever passed, so this cannot fire in the addon -
         but the separation above is stated as an invariant, and joining the
         arguments alone would not give it: one argument of "a\0b" and the pair
         ("a", "b") join to the same string. The count leads the key. ]]
    it("does not let one argument collide with a pair", function()
      service.get_mob_by_target("a\0b")
      service.get_mob_by_target("a", "b")
      assert.are.equal(2, calls.mob, "a single argument shared a memo slot with a pair")
    end)

    it("remembers a target the client had nothing for", function()
      service.get_mob_by_target("st")
      service.get_mob_by_target("st")
      assert.are.equal(1, calls.mob, "an absent target is an answer, and must not be re-asked")
      assert.is_nil(service.get_mob_by_target("st"))
    end)

    --[[ begin_frame is called from prerender, and prerender can stop: guard
         disables a handler after five failures, and a minimised client renders
         nothing. Key presses and packets keep arriving either way, and a press
         resolved against a frozen target is an action sent at the wrong mob -
         so the memo expires on its own as a backstop, far longer than a frame
         and far shorter than a person can react. ]]
    it("expires on its own if the frame never ends", function()
      service.get_mob_by_target("t")
      clock = 0.05
      service.get_mob_by_target("t")
      assert.are.equal(1, calls.mob, "expired inside a single frame")

      clock = 0.2
      client.mobs.t = { id = 9 }
      assert.are.equal(9, service.get_mob_by_target("t").id, "a frozen prerender froze the target")
    end)

    --[[ Each frame re-anchors the backstop. Without that the 0.1s is measured
         from the first insert since the last expiry, so a memo filled early in
         a long-running client would let go part way through a later frame. ]]
    it("re-anchors the expiry on every frame", function()
      service.get_mob_by_target("t")
      clock = 0.05
      service.begin_frame()
      service.get_mob_by_target("t")

      clock = 0.14
      client.mobs.t = { id = 9 }
      assert.are.equal(7, service.get_mob_by_target("t").id, "the expiry was still anchored to an older frame")
    end)

    --[[ The backstop is measured from the FIRST insert since the last clear,
         not the latest. With prerender dead - the case it exists for - lookups
         on different targets trickle in, and anchoring to the latest would keep
         pushing the deadline out and hold a frozen target past its budget. ]]
    it("anchors the expiry to the first lookup, not the most recent", function()
      service.get_mob_by_target("t")
      clock = 0.05
      service.get_mob_by_target("me")

      clock = 0.11
      client.mobs.t = { id = 9 }
      assert.are.equal(9, service.get_mob_by_target("t").id, "a later lookup pushed the deadline out")
    end)

    -- The mob memo has nothing to do with the read interval: the target can
    -- change between any two frames.
    it("is not held for the interval", function()
      service.get_mob_by_target("t")
      service.begin_frame()
      client.mobs.t = { id = 9 }
      assert.are.equal(9, service.get_mob_by_target("t").id)
    end)
  end)

  --[[ ONE source for a vital, and it is the client.

       An event used to carry its VALUE: it was laid over the cached player and
       held until the next read of the client dropped it. That reconciled the
       two streams the wrong way round. The absolute stream can report a value
       nothing corrects -- an HP number stuck at max HP after a Max HP Down wore
       off is the defect this service was built for -- and laying it on top
       meant the bogus value and the true one took turns: the event put it up,
       the read 200ms later took it down, the next event put it back. Kevin saw
       that as an HP bar jumping high and falling back, over and over, after
       dying and being raised (2026-09-18).

       So an event now says only THAT a vital moved, never what to. It marks the
       player stale and the next read answers with the client's own numbers.
       Nothing is merged, so nothing can disagree. ]]
  describe("the vitals stream", function()
    --[[ The defect itself. A remembered value would take turns with the
         client's: the event putting it up, the next read taking it down. So the
         answer is checked on both sides of an interval boundary. ]]
    it("answers out of the client on both sides of an interval boundary", function()
      service.get_player()
      client.player.vitals.hp = 640
      service.vital_changed("hp")

      assert.are.equal(640, service.get_player().vitals.hp, "the event held a value back")
      clock = 0.2
      assert.are.equal(640, service.get_player().vitals.hp)
    end)

    -- The responsiveness the overlay was there for, kept: the event does not
    -- wait out the interval, it re-opens it.
    it("re-reads the client at once rather than waiting out the interval", function()
      service.get_player()
      assert.are.equal(1, calls.player)

      client.player.vitals.hp = 640
      client.player.vitals.hpp = 64
      service.vital_changed("hp")

      assert.are.equal(640, service.get_player().vitals.hp)
      assert.are.equal(64, service.get_player().vitals.hpp, "the whole table, not one key")
      assert.are.equal(2, calls.player)
    end)

    --[[ Keyed, like a buff gain and for the same reason: a vital moves neither
         the party nor the zone, and TP alone moves several times a second. The
         counter is what puts the party list through a roster rebuild and the
         target bar through an eighteen-member walk. ]]
    it("does not move the read counter", function()
      local before = service.generation()
      service.vital_changed("hp")
      assert.are.equal(before, service.generation())
      assert.are.equal(before, service.generation(), "and the interval is not re-opened")
    end)

    it("leaves the party and the zone alone", function()
      service.get_party()
      service.get_info()
      service.vital_changed("hp")
      service.get_party()
      service.get_info()
      assert.are.equal(1, calls.party)
      assert.are.equal(1, calls.info)
    end)

    -- The mob memo is the frame's, and a vital moves nobody.
    it("leaves the mob memo alone", function()
      service.get_mob_by_target("t")
      service.vital_changed("hp")
      client.mobs.t = { id = 9 }
      assert.are.equal(7, service.get_mob_by_target("t").id)
    end)

    it("ignores a key that is not a vital", function()
      service.get_player()
      assert.has_no.errors(function()
        service.vital_changed("wisdom")
      end)
      service.get_player()
      assert.are.equal(1, calls.player, "and does not buy a read for one")
    end)

    it("survives an event while the client answers nothing", function()
      client.player = nil
      assert.has_no.errors(function()
        service.vital_changed("hp")
      end)
      assert.is_nil(service.get_player())
    end)
  end)

  describe("the table it hands back", function()
    -- Five consumers share one player table now, so a writer would corrupt the
    -- others rather than only itself. Nothing writes to it today; this keeps the
    -- client's own table out of reach if something ever does.
    it("is the service's own, not the client's", function()
      local handed = service.get_player()
      assert.are_not.equal(client.player, handed)
      assert.are_not.equal(client.player.vitals, handed.vitals)

      handed.vitals.hp = 1
      handed.name = "Someone else"
      assert.are.equal(1000, client.player.vitals.hp)
      assert.are.equal("Kevin", client.player.name)
    end)

    it("is the same table for every caller inside one interval", function()
      assert.are.equal(service.get_player(), service.get_player())
    end)

    it("carries every field the client reported", function()
      assert.are.equal("WHM", service.get_player().main_job)
    end)

    -- The client fills the player in field by field, and a caller guards on
    -- `player and player.vitals`. Inventing an empty table would defeat that.
    it("leaves a missing vitals table missing", function()
      client.player = { name = "Kevin" }
      assert.is_nil(service.get_player().vitals)
    end)

    --[[ A change event must NOT conjure a vitals table the client has not sent.
         parambar treats what it is handed as a replacement, so a table carrying
         nothing but `hp` would drive hpp, mp, mpp and tp to zero - blanking the
         numbers and hiding the fills. The event is not lost: it re-opens the
         read, and the client brings the whole table whenever it has one. ]]
    it("does not conjure a vitals table the client has not sent", function()
      client.player = { name = "Kevin" }
      service.get_player()
      service.vital_changed("hp")
      assert.is_nil(service.get_player().vitals)
    end)

    --[[ The party is handed over as the client gave it: eighteen member tables
         copied five times a second would cost more than the reads this saves,
         and only the player is merged with anything. ]]
    it("does not copy the party", function()
      assert.are.equal(client.party, service.get_party())
    end)
  end)
end)
