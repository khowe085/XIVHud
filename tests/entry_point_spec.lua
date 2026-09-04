--[[ The entry point's own wiring, booted under a fake Windower (see
     tests/support/entry_point.lua for what is faked and where it diverges).

     Two things are under test. The `incoming chunk` dispatch: which packet ids
     are pre-parsed, with which parser, how many times, and what reaches the
     components. And the player service: which reads each ctx is handed, which
     are deliberately left raw, and which events drop the read interval. Three
     reads stay raw; the two reachable from a ctx are pinned below, and core's
     own `logged_in` is not.

     Neither is visible from a component spec -- a component is handed whatever
     the entry point decided, and cannot tell what is behind it. ]]

local harness = require("tests/support/entry_point")

local ACTION = 0x028
local ALLIANCE, PARTY_MEMBER, CHAR = 0x0C8, 0x0DD, 0x0DF
-- Read raw by the party list; no field definition to parse it with.
local PARTY_BUFFS = 0x076
local CHAR_UPDATE = 0x063

describe("entry point", function()
  local boot

  before_each(function()
    boot = harness.boot()
  end)

  describe("load", function()
    it("registers the packet dispatch and builds every component", function()
      assert.is_not_nil(boot.handlers["incoming chunk"])
      assert.is_not_nil(boot.ctxs.targetbar)
      assert.is_not_nil(boot.ctxs.crossbar)
      assert.is_not_nil(boot.ctxs.speedcheck)
    end)

    --[[ The party list is ONE registration over three anchors. It was three
         registrations off one factory until 2026-08-30, which is why it could
         carry no alias: all three would have claimed `pl` and the second would
         have aborted the load. Only the entry point can say how many times the
         factory is called, or that nothing picks a variant for it any more. ]]
    -- The status bar reads the player through the service like everyone
    -- else, and decodes its own packet against the wall clock the timestamps
    -- count in - the monotonic `now` the other ctxs carry could not answer.
    it("builds the status bar over the player service and the wall clock", function()
      local built = 0
      for _, name in ipairs(boot.built) do
        if name == "statusbar" then
          built = built + 1
        end
      end
      assert.are.equal(1, built)
      assert.are.equal(boot.ctxs.partylist.get_player, boot.ctxs.statusbar.get_player)
      assert.are.equal(os.time, boot.ctxs.statusbar.time)
      assert.is_not_nil(boot.ctxs.statusbar.resources)
    end)

    it("builds the party list once, with no variant to pick", function()
      local built = 0
      for _, name in ipairs(boot.built) do
        if name == "partylist" then
          built = built + 1
        end
      end
      assert.are.equal(1, built)
      assert.is_nil(boot.ctxs.partylist.variant)
      for _, name in ipairs(boot.registered) do
        assert.are_not.equal("alliancelist1", name)
        assert.are_not.equal("alliancelist2", name)
      end
    end)
  end)

  --[[ The exp bar reads packets nothing else does, and asks the client for the
       last of two of them at attach. Neither the dep nor its pcall is visible
       from the component's own spec. ]]
  describe("the exp bar", function()
    it("reads the player through the service, like every other component", function()
      assert.are.equal(boot.ctxs.parambar.get_player, boot.ctxs.expbar.get_player)
    end)

    it("shares the one packet parser", function()
      assert.are.equal(boot.ctxs.giltracker.parse_packet, boot.ctxs.expbar.parse_packet)
    end)

    it("hands over the last packet the client sent, without its timestamp", function()
      boot.last_incoming[0x061] = "the char stats bytes"
      assert.are.same({ "the char stats bytes" }, { boot.ctxs.expbar.last_incoming(0x061) })
      assert.are.same({ 0x061 }, boot.last_incoming_asked)
    end)

    it("answers nil rather than throwing where windower.packets is not there", function()
      boot.last_incoming_raises = true
      assert.is_nil(boot.ctxs.expbar.last_incoming(0x061))
    end)

    it("sits out when the packets library did not load", function()
      local without = harness.boot({ require_fails = { packets = "no packets library" } })
      assert.is_nil(without.ctxs.expbar)
      -- The bar that needs no library is still there.
      assert.is_not_nil(without.ctxs.targetbar)
    end)
  end)

  --[[ The player service. Which client reads reach the client, and how the
       vitals events reconcile against them, is a decision made here and nowhere
       else -- a component is handed a getter and cannot tell what is behind it. ]]
  describe("the player service", function()
    local function tick()
      boot.handlers["prerender"]()
    end

    it("hands every component one shared set of reads", function()
      assert.are.equal(boot.ctxs.parambar.get_player, boot.ctxs.targetbar.get_player)
      assert.are.equal(boot.ctxs.partylist.get_party, boot.ctxs.targetbar.get_party)
      assert.are.equal(boot.ctxs.partylist.get_mob_by_target, boot.ctxs.crossbar.get_mob_by_target)
      --[[ speedcheck reads the mob table on the TICK, which is only affordable
           because this is the service's memoized lookup rather than a client
           read of its own. ]]
      assert.are.equal(boot.ctxs.targetbar.get_mob_by_target, boot.ctxs.speedcheck.get_mob_by_target)
    end)

    --[[ The two widgets that gate a rebuild on the counter go quiet without it -
         partylist would throw away its packet pushes every frame, targetbar
         would walk eighteen member tables sixty times a second - and no
         component spec can see whether the ctx carried it. ]]
    it("hands the counter to the components that gate on it", function()
      assert.is_function(boot.ctxs.partylist.generation)
      assert.is_function(boot.ctxs.targetbar.generation)
      assert.is_function(boot.ctxs.crossbar.generation)
      -- speedcheck polls the mob table on its tick and has nothing else to
      -- pace it: without the counter it would read the client every frame.
      assert.is_function(boot.ctxs.speedcheck.generation)
      assert.are.equal(boot.ctxs.partylist.generation, boot.ctxs.targetbar.generation)
      assert.are.equal(boot.ctxs.partylist.generation, boot.ctxs.crossbar.generation)
      assert.is_number(boot.ctxs.targetbar.generation())
    end)

    --[[ Core scopes a character from its own prerender search, not from the
         `login` event - the event can fire before the client can name anybody.
         So the event's invalidation is not enough on its own: between the two,
         the components of the character being LEFT are still attached and still
         ticking, and their per-frame reads refill the cache. The next
         character's first tick would then read the previous one - and the
         crossbar's job scoping is one-shot, so it would load the wrong job's
         bindings and stay there. Core drops the cache as it scopes. ]]
    it("drops the cache when core scopes a character", function()
      boot.ctxs.parambar.get_player()
      local before = boot.client_calls.player
      boot.core_deps.on_scope_change()
      boot.ctxs.parambar.get_player()
      assert.are.equal(before + 1, boot.client_calls.player, "the next character read the previous one")
    end)

    --[[ Core is deliberately NOT behind the cache. It re-reads the player every
         0.05s while a login is under way - LOADING_RETRY_SECONDS, whose comment
         calls that the visible delay before the HUD comes up - and a 200ms TTL
         would answer three of every four of those from the same stale nil. ]]
    it("leaves core reading the client directly", function()
      assert.are_not.equal(boot.core_deps.get_player, boot.ctxs.parambar.get_player)

      local before = boot.client_calls.player
      boot.core_deps.get_player()
      boot.core_deps.get_player()
      assert.are.equal(before + 2, boot.client_calls.player, "core's login retry is behind the cache")
    end)

    it("reads the client once however many components ask inside one interval", function()
      boot.ctxs.parambar.get_player()
      boot.ctxs.targetbar.get_player()
      boot.ctxs.partylist.get_player()
      assert.are.equal(1, boot.client_calls.player)
    end)

    -- The harness keys a ctx by its factory, so the three party lists collapse
    -- to one here; they share the getter either way, which is the point.
    it("reads the party once for the party lists and the target bar", function()
      for _ = 1, 3 do
        boot.ctxs.partylist.get_party()
      end
      boot.ctxs.targetbar.get_party()
      assert.are.equal(1, boot.client_calls.party)
    end)

    it("memoizes a mob lookup for the frame and drops it on the next one", function()
      boot.ctxs.partylist.get_mob_by_target("t")
      boot.ctxs.targetbar.get_mob_by_target("t")
      assert.are.equal(1, boot.client_calls.mob)

      tick()
      boot.ctxs.targetbar.get_mob_by_target("t")
      assert.are.equal(2, boot.client_calls.mob, "the memo outlived its frame")
    end)

    --[[ Ordering, not just clearing. A key press arrives outside prerender and
         fills the memo for that frame; if begin_frame ran AFTER core, every
         component in the next frame would resolve its target out of the press
         before it. Both orderings clear the memo once a frame, so only a read
         made outside prerender can tell them apart. ]]
    it("clears the mob memo before the components run, not after", function()
      boot.ctxs.crossbar.get_mob_by_target("t")
      local before = boot.client_calls.mob
      tick()
      assert.are.equal(before + 1, boot.client_calls.mob, "a component saw the previous frame's target")
      assert.are.equal(1, #boot.prerender_targets)
    end)

    it("answers a mob lookup with what the client gave", function()
      assert.are.equal(7, boot.ctxs.targetbar.get_mob_by_target("t").id)
    end)

    -- The events still dispatch to the components; they now also reconcile
    -- against the cached player, so every consumer sees one answer.
    it("applies a vitals change event to the player it hands out", function()
      boot.ctxs.parambar.get_player()
      boot.handlers["hp change"](640, 1000)
      assert.are.equal(640, boot.ctxs.targetbar.get_player().vitals.hp)
    end)

    it("still dispatches a vitals change event to the components", function()
      boot.handlers["hp change"](640, 1000)
      local dispatch = boot.last_dispatch("hp")
      assert.is_not_nil(dispatch, "the components stopped hearing the vitals events")
      assert.are.equal(640, dispatch[1])
      assert.are.equal(1000, dispatch[2])
    end)

    it("re-reads the client at once on a status change", function()
      boot.ctxs.parambar.get_player()
      boot.handlers["status change"](0, 4)
      boot.ctxs.parambar.get_player()
      assert.are.equal(2, boot.client_calls.player)
    end)

    --[[ The crossbar holds a job change until get_player() agrees with the id
         the event announced, retrying per frame. Answering it out of a cache
         read before the change would make that wait an interval longer for no
         reason. ]]
    it("re-reads the client at once on a job change", function()
      boot.ctxs.parambar.get_player()
      boot.handlers["job change"](5, 99)
      boot.ctxs.parambar.get_player()
      assert.are.equal(2, boot.client_calls.player)
    end)

    --[[ The crossbar flips its context layers straight off the event, from a
         pure diff of get_player().buffs: a list read before the buff landed
         does not contain it, the diff sees no change, and nothing re-syncs per
         frame - so the layer would stay wrong until the NEXT buff event, which
         can be minutes. Light Arts is the everyday case. ]]
    it("re-reads the client at once on a buff gain or loss", function()
      for _, event in ipairs({ "gain buff", "lose buff" }) do
        boot.ctxs.parambar.get_player()
        local before = boot.client_calls.player
        boot.handlers[event](43)
        boot.ctxs.parambar.get_player()
        assert.are.equal(before + 1, boot.client_calls.player, event .. " was answered from the cache")
      end
    end)

    --[[ Buff events are much the most frequent invalidation, and a buff makes
         only the player stale. Dropping the whole interval for one would re-read
         the party and the zone too, and move the counter - putting the party
         list through a full roster rebuild and the target bar through an
         eighteen-member walk for a fact neither of them holds. ]]
    it("keeps the party and the zone for a buff gain", function()
      boot.ctxs.targetbar.get_party()
      boot.ctxs.crossbar.zone()
      local party, info = boot.client_calls.party, boot.client_calls.info

      boot.handlers["gain buff"](43)
      boot.ctxs.targetbar.get_party()
      boot.ctxs.crossbar.zone()
      assert.are.equal(party, boot.client_calls.party, "a buff dropped the party read")
      assert.are.equal(info, boot.client_calls.info, "a buff dropped the zone read")
    end)

    it("keeps the counter still for a buff gain, so no roster is rebuilt", function()
      local before = boot.ctxs.partylist.generation()
      boot.handlers["gain buff"](43)
      assert.are.equal(before, boot.ctxs.partylist.generation())
    end)

    it("reads the zone once per interval, however often the crossbar draws", function()
      local before = boot.client_calls.info
      boot.ctxs.crossbar.zone()
      boot.ctxs.crossbar.zone()
      boot.ctxs.partylist.get_info()
      assert.are.equal(before + 1, boot.client_calls.info)
    end)

    --[[ The one read that must NOT be cached: it is asked on every key event to
         decide whether a key belongs to the game's chat box or to the bar, and
         a verdict an interval old would swallow the first keystrokes after a
         chat line opens or closes. ]]
    it("leaves the chat-open check reading the client directly", function()
      local before = boot.client_calls.info
      boot.ctxs.crossbar.chat_open()
      boot.ctxs.crossbar.chat_open()
      assert.are.equal(before + 2, boot.client_calls.info, "chat_open went behind the cache")
    end)

    it("re-reads the client at once on a login", function()
      boot.ctxs.parambar.get_player()
      boot.handlers["login"]()
      boot.ctxs.parambar.get_player()
      assert.are.equal(2, boot.client_calls.player)
    end)

    -- Nothing draws once core detaches, so this is tidiness - but it is the
    -- last hole in the invalidation set, and an untested one would close again.
    --[[ A status change - engaging, resting, a death, a cutscene - moves the
         player and nothing else. Dropping the whole interval for one would
         re-read the party and the zone as well, and move the counter, putting
         the party list through a full roster rebuild for a fact it does not
         hold. Infrequent enough that it hardly matters, and inconsistent enough
         with the buff handler two blocks down that it would read as an
         oversight. ]]
    it("keeps the party and the counter on a status change", function()
      boot.ctxs.parambar.get_player()
      boot.ctxs.targetbar.get_party()
      local player, party = boot.client_calls.player, boot.client_calls.party
      local generation = boot.ctxs.partylist.generation()

      boot.handlers["status change"](0, 4)
      boot.ctxs.parambar.get_player()
      boot.ctxs.targetbar.get_party()
      assert.are.equal(player + 1, boot.client_calls.player, "the player was not re-read")
      assert.are.equal(party, boot.client_calls.party, "a status change dropped the party read")
      assert.are.equal(generation, boot.ctxs.partylist.generation())
    end)

    it("re-reads the client at once on a logout", function()
      boot.ctxs.parambar.get_player()
      boot.handlers["logout"]()
      boot.ctxs.parambar.get_player()
      assert.are.equal(2, boot.client_calls.player)
    end)

    it("re-reads the client at once on a zone change", function()
      boot.ctxs.parambar.get_player()
      boot.handlers["zone change"]()
      boot.ctxs.parambar.get_player()
      assert.are.equal(2, boot.client_calls.player)
    end)
  end)

  describe("the incoming chunk dispatch", function()
    it("pre-parses the action packet and dispatches it as `parsed`", function()
      boot.action = { category = 8, param = 144, targets = { { id = 1, actions = {} } } }
      boot.chunk(ACTION, "raw action bytes")

      local dispatch = boot.last_dispatch("chunk")
      assert.are.equal(ACTION, dispatch[1])
      assert.are.equal("raw action bytes", dispatch[2])
      assert.are.same(boot.action, dispatch[3])
    end)

    -- The whole point of the hoist: targetbar's cast bar and the crossbar's
    -- skillchain engine both want this packet, and it is decoded once for
    -- the pair of them rather than once each.
    it("parses the action packet exactly once, however many components want it", function()
      boot.chunk(ACTION, "raw action bytes")

      assert.are.equal(1, #boot.action_parses)
      assert.are.equal("raw action bytes", boot.action_parses[1])
    end)

    it("uses windower.packets.parse_action for the action packet, not packets.parse", function()
      boot.chunk(ACTION, "raw action bytes")

      assert.are.equal(0, #boot.parsed_packets)
    end)

    -- parse_action is pcall'd, so a packet it cannot read costs the frame
    -- nothing: the raw bytes still go out, `parsed` is nil, and a component
    -- treating that as "nothing happened" is the contract it already has.
    it("dispatches a parse failure as a nil `parsed`, without throwing", function()
      boot.action_raises = true

      assert.has_no.errors(function()
        boot.chunk(ACTION, "unreadable")
      end)

      local dispatch = boot.last_dispatch("chunk")
      assert.are.equal(3, dispatch.n)
      assert.is_nil(dispatch[3])
      assert.are.equal("", boot.said():match("error in the incoming chunk handler") or "")
    end)

    it("still pre-parses the three party-list ids through packets.parse", function()
      for _, id in ipairs({ ALLIANCE, PARTY_MEMBER, CHAR }) do
        boot.chunk(id, "party bytes " .. id)

        local dispatch = boot.last_dispatch("chunk")
        assert.are.same({ packet = "party bytes " .. id }, dispatch[3])
      end

      assert.are.equal(3, #boot.parsed_packets)
      assert.are.equal(0, #boot.action_parses)
    end)

    -- Three readers - the crossbar's skillchain engine, expbar and the status
    -- bar - so it is decoded once here rather than once each, through the
    -- same packets.parse the party ids use (its field definition switches on
    -- the order byte, so every order comes through it).
    it("pre-parses the 0x063 character update once, for its three readers", function()
      boot.chunk(CHAR_UPDATE, "char update bytes")

      local dispatch = boot.last_dispatch("chunk")
      assert.are.equal("char update bytes", dispatch[2])
      assert.are.same({ packet = "char update bytes" }, dispatch[3])
      assert.are.equal(1, #boot.parsed_packets)
      assert.are.equal(0, #boot.action_parses)
    end)

    -- Both pre-parses are pcall'd: a packet the library cannot read costs
    -- the frame nothing, the raw bytes still go out, and `parsed` is nil -
    -- the contract every reader is written to. Unprotected, five bad packets
    -- would have guard disable the whole chunk handler for the session.
    it("dispatches a packets.parse failure as a nil `parsed`, without throwing", function()
      boot.parse_raises = true

      assert.has_no.errors(function()
        boot.chunk(CHAR_UPDATE, "unreadable")
        boot.chunk(ALLIANCE, "unreadable")
      end)

      local dispatch = boot.last_dispatch("chunk")
      assert.are.equal(3, dispatch.n)
      assert.are.equal("unreadable", dispatch[2])
      assert.is_nil(dispatch[3])
      assert.are.equal("", boot.said():match("error in the incoming chunk handler") or "")
    end)

    it("parses nothing for an id no component has a definition for", function()
      boot.chunk(PARTY_BUFFS, "buff bytes")

      local dispatch = boot.last_dispatch("chunk")
      assert.are.equal(3, dispatch.n)
      assert.are.equal("buff bytes", dispatch[2])
      assert.is_nil(dispatch[3])
      assert.are.equal(0, #boot.parsed_packets)
      assert.are.equal(0, #boot.action_parses)
    end)

    -- The mutation this kills: a component going back to parsing the packet
    -- itself. Neither can, because neither is handed a parser.
    it("hands no component its own action parser", function()
      assert.is_nil(boot.ctxs.targetbar.parse_action)
      assert.is_nil(boot.ctxs.crossbar.parse_action)
    end)
  end)

  --[[ The load check tells the player their install is incomplete, so a
       path it gets WRONG is worse than no check at all: it condemns a
       correct install and sends them re-copying files that are already
       there. It has been wrong twice - both times because a folder was
       moved and the manifest's prefix was rewritten by hand - and neither
       spelling could fail any test, because nothing had ever asserted the
       manifest describes the files that actually ship. ]]
  describe("the asset manifest", function()
    it("names only textures that ship in src/", function()
      boot.handlers["load"]()

      local checked, seen = {}, {}
      for _, open in ipairs(boot.opens) do
        local relative = open.path:match("(assets/.+)$")
        if relative and not seen[relative] then
          seen[relative] = true
          checked[#checked + 1] = relative
        end
      end

      -- Without this the whole test passes on an empty list, which is
      -- exactly what a renamed manifest or a load that died early leaves.
      assert.is_true(#checked > 40, "the manifest went quiet: " .. #checked .. " textures checked")

      local absent = {}
      for _, relative in ipairs(checked) do
        local file = io.open("src/" .. relative, "r")
        if file then
          file:close()
        else
          absent[#absent + 1] = relative
        end
      end
      assert.are.same({}, absent)
    end)
  end)
end)
