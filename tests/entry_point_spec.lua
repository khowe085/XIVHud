--[[ The entry point's own wiring, booted under a fake Windower (see
     tests/support/entry_point.lua for what is faked and where it diverges).

     What is under test here is the `incoming chunk` dispatch: which packet
     ids are pre-parsed, with which parser, how many times, and what reaches
     the components. None of that is visible from a component spec -- a
     component is handed whatever the entry point decided. ]]

local harness = require("tests/support/entry_point")

local ACTION = 0x028
local ALLIANCE, PARTY_MEMBER, CHAR = 0x0C8, 0x0DD, 0x0DF
-- Read raw by the party list; no field definition to parse it with.
local PARTY_BUFFS = 0x076

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
end)
