local new_actions = require("components/crossbar/actions")

-- Actions with controllable roulette/warp stand-ins.
local function build(state)
  state = state or {}
  local actions = new_actions({
    roulette = {
      ride = function()
        return state.ride
      end,
      mounted = function()
        return state.mounted == true
      end,
    },
    warp = {
      plan = function()
        return state.warp_plan
      end,
    },
    enchanteditem = {
      plan = function(name, target)
        state.asked = { name = name, target = target }
        return state.item_plan
      end,
    },
  })
  return actions, state
end

local function command_of(actions, record)
  local plan = actions.resolve(record)
  assert.equal("command", plan.kind)
  return plan.command
end

-- The shipped built-ins, spelled out. Two specs read it: one proves each
-- name resolves, the other proves the table holds these and nothing else.
local SHIPPED_BUILTINS = { "draw", "mr", "warp", "open" }

describe("crossbar actions", function()
  describe("game action commands", function()
    it("builds the command from the type word, quoted name and target", function()
      local actions = build()
      assert.equal('input /ma "Cure" <t>', command_of(actions, { type = "ma", action = "Cure", target = "t" }))
      assert.equal('input /ja "Provoke" <t>', command_of(actions, { type = "ja", action = "Provoke", target = "t" }))
      assert.equal(
        'input /ws "Savage Blade" <t>',
        command_of(actions, { type = "ws", action = "Savage Blade", target = "t" })
      )
      assert.equal(
        'input /item "Echo Drops" <me>',
        command_of(actions, { type = "item", action = "Echo Drops", target = "me" })
      )
      assert.equal('input /pet "Sic" <t>', command_of(actions, { type = "pet", action = "Sic", target = "t" }))
      assert.equal('input /mount "raptor"', command_of(actions, { type = "mount", action = "raptor" }))
    end)

    it("casts a trust as plain magic", function()
      local actions = build()
      assert.equal(
        'input /ma "Valaineral" <me>',
        command_of(actions, { type = "ma", action = "Valaineral", target = "me" })
      )
    end)

    it("always closes the quote when there is no target", function()
      -- Upstream leaves the quote open without a target (defect 9).
      local actions = build()
      assert.equal('input /ma "Cure"', command_of(actions, { type = "ma", action = "Cure" }))
    end)

    it("keeps apostrophes in action names intact", function()
      local actions = build()
      assert.equal(
        [[input /ws "Ascetic's Fury" <t>]],
        command_of(actions, { type = "ws", action = "Ascetic's Fury", target = "t" })
      )
    end)

    it("sends ranged attack with no action name", function()
      local actions = build()
      assert.equal("input /ra <t>", command_of(actions, { type = "ra", target = "t" }))
      assert.equal("input /ra", command_of(actions, { type = "ra" }))
    end)

    it("sends a ct line under input with its own slash", function()
      local actions = build()
      assert.equal("input /wave <t>", command_of(actions, { type = "ct", action = "wave", target = "t" }))
      assert.equal("input /heal", command_of(actions, { type = "ct", action = "heal" }))
    end)

    it("sends an ex console command as-is, no input prefix", function()
      local actions = build()
      assert.equal("lua reload xivhud", command_of(actions, { type = "ex", action = "lua reload xivhud" }))
    end)

    it("rejects an unknown type with a hint", function()
      local actions = build()
      local plan, err = actions.resolve({ type = "dance", action = "Jig" })
      assert.is_nil(plan)
      assert.is_string(err)
    end)
  end)

  describe("malformed records", function()
    -- The data files are hand-edited during milestone verification and
    -- bindings stores what it is given, so a broken record must answer
    -- nil + hint, never crash or emit a nil command.
    local cases = {
      ["game action with no name"] = { type = "ma", target = "t" },
      ["game action with an empty name"] = { type = "ws", action = "" },
      ["game action with a non-string name"] = { type = "ja", action = {} },
      ["ct with no line"] = { type = "ct" },
      ["ex with no command"] = { type = "ex" },
      ["ex with a non-string command"] = { type = "ex", action = 42 },
      ["game action with a non-string target"] = { type = "ja", action = "Provoke", target = {} },
      ["ra with a non-string target"] = { type = "ra", target = 5 },
      ["ct with a non-string target"] = { type = "ct", action = "wave", target = {} },
    }
    for label, record in pairs(cases) do
      it("rejects a " .. label .. " with a hint", function()
        local actions = build()
        local plan, err = actions.resolve(record)
        assert.is_nil(plan)
        assert.is_string(err)
      end)
    end

    it("answers plain nil, no hint, for an unbound slot", function()
      -- Empty is normal, not rejected: bindings.resolve answers nil for an
      -- unbound slot and the caller just skips it.
      local actions = build()
      local plan, hint = actions.resolve(nil)
      assert.is_nil(plan)
      assert.is_nil(hint)
    end)

    it("rejects a record with no type", function()
      local actions = build()
      local plan, err = actions.resolve({})
      assert.is_nil(plan)
      assert.is_string(err)
    end)

    it("answers nil icon for an unbound slot", function()
      local actions = build()
      assert.is_nil(actions.icon_for(nil))
    end)
  end)

  describe("open actions", function()
    it("resolves a command entry to its input line", function()
      local actions = build()
      assert.equal("input /map", command_of(actions, { type = "open", action = "map" }))
    end)

    it("holds a chord down long enough for the client to see it", function()
      --[[ The four edges went out as four separate console commands inside
           one frame. FFXI samples the keyboard once a frame, so a key
           pressed and released within a frame is never observed down: the
           menu never opened, and nothing said so. The same chord with a
           `wait` between the edges DOES open it, verified in the client
           (Kevin, 2026-08-29) - so the hold is the fix, not the key names.

           It is one chained console command rather than a scheduled
           release because that is the form that was verified working, and
           because a release owed on a later frame is a release a zone, a
           logout or a detach can swallow - leaving ctrl stuck down. ]]
      local actions = build()
      local plan = actions.resolve({ type = "open", action = "equipment" })
      assert.equal("command", plan.kind)
      assert.equal(
        "setkey ctrl down;setkey e down;wait 0.25;setkey e up;setkey ctrl up",
        plan.command
      )
    end)

    it("rejects an unknown opener with a hint", function()
      local actions = build()
      local plan, err = actions.resolve({ type = "open", action = "bank" })
      assert.is_nil(plan)
      assert.is_string(err)
    end)
  end)

  describe("the draw toggle", function()
    it("dismounts first, even somehow engaged, without flipping the weapon state", function()
      local actions = build()
      local plan = actions.resolve({ type = "draw" }, { mounted = true, weapon_drawn = true })
      assert.equal("input /dismount", plan.command)
      assert.is_nil(plan.weapon_state)
    end)

    it("disengages while drawn and flips to sheathed", function()
      local actions = build()
      local plan = actions.resolve({ type = "draw" }, { weapon_drawn = true })
      assert.equal("input /attack off", plan.command)
      assert.equal("sheathed", plan.weapon_state)
    end)

    it("flips to drawn without attacking, target or no target", function()
      --[[ The state is the component's own - which rotation is live, and
           the sword on the bar - not a combat order. It used to send
           `/attack <t>` here (Kevin, 2026-08-22). `has_target` is a dead
           field now, deliberately still passed: the widget stopped
           supplying it, and this pins that nothing reads it if it comes
           back. ]]
      local actions = build()
      for _, targeted in ipairs({ true, false }) do
        local plan = actions.resolve({ type = "draw" }, { weapon_drawn = false, has_target = targeted })
        assert.equal("none", plan.kind)
        assert.equal("drawn", plan.weapon_state)
        assert.is_nil(plan.command)
      end
    end)

    it("still disengages on the way out", function()
      -- Asymmetric on purpose: an explicit `draw` while drawn means "I am
      -- done fighting", which is the rule the state machine is built on.
      local actions = build()
      local plan = actions.resolve({ type = "draw" }, { weapon_drawn = true })
      assert.equal("input /attack off", plan.command)
      assert.equal("sheathed", plan.weapon_state)
    end)
  end)

  describe("a named mount", function()
    it("dismounts instead of summoning while mounted, and instantly", function()
      --[[ `mr` dismounts when pressed mounted; a slot bound to a NAMED
           mount counted down five seconds and then sent a summon (Kevin,
           live client, 2026-08-22). The same press was instant on one slot
           and a countdown on the next, for no reason the player could see.

           Getting OUT of something is never held - the rule mount roulette
           and `draw` already follow - and the `dismount` flag is what says
           so, rather than anything downstream reading the command back. ]]
      local actions, state = build()
      state.mounted = true
      local plan = actions.resolve({ type = "mount", action = "raptor" }, { mounted = true })
      assert.equal("input /dismount", plan.command)
      assert.is_true(plan.dismount)
    end)

    it("summons when not mounted, and is held for the countdown", function()
      local actions = build()
      local plan = actions.resolve({ type = "mount", action = "raptor" }, { mounted = false })
      assert.equal('input /mount "raptor"', plan.command)
      assert.is_nil(plan.dismount)
    end)

    it("summons when the caller passes no state at all", function()
      -- Nothing known about the player reads as "not mounted": a slot that
      -- refused to summon without a state would be worse than one that
      -- sends a summon the game ignores.
      local actions = build()
      assert.equal('input /mount "raptor"', command_of(actions, { type = "mount", action = "raptor" }))
    end)
  end)

  describe("mount roulette", function()
    it("relays the roulette's command", function()
      local actions, state = build()
      state.ride = "input /dismount"
      assert.equal("input /dismount", command_of(actions, { type = "mr" }))
    end)

    it("is a no-op with no mounts", function()
      local actions, state = build()
      state.ride = nil
      assert.equal("none", actions.resolve({ type = "mr" }).kind)
    end)

    it("marks the plan when the ride is a dismount", function()
      -- The travel delay holds a summon and lets a dismount go at once. The
      -- flag is what tells them apart, so nothing downstream has to read
      -- the command string to find out which it got.
      local actions, state = build()
      state.ride, state.mounted = "input /dismount", true
      assert.is_true(actions.resolve({ type = "mr" }).dismount)
      state.ride, state.mounted = 'input /mount "crab"', false
      assert.is_nil(actions.resolve({ type = "mr" }).dismount)
    end)

    it("leaves the plan unmarked when the roulette cannot say", function()
      -- A resources-less client gets the no-op stand-in, which answers no
      -- ride and knows nothing about mounts.
      local actions = new_actions({
        roulette = {
          ride = function()
            return "input /dismount"
          end,
        },
      })
      assert.is_nil(actions.resolve({ type = "mr" }).dismount)
    end)
  end)

  describe("auto-warp", function()
    it("relays the warp plan", function()
      local actions, state = build()
      state.warp_plan = { type = "spell", command = 'input /ma "Warp" <me>' }
      local plan = actions.resolve({ type = "warp" })
      assert.equal("warp", plan.kind)
      assert.same(state.warp_plan, plan.plan)
    end)
  end)

  describe("enchanted items", function()
    it("relays the plan for the item the slot names", function()
      local actions, state = build()
      state.item_plan = { type = "use", name = "Vocation Ring", command = 'input /item "Vocation Ring" <me>' }
      local plan = actions.resolve({ type = "enchanteditem", action = "Vocation Ring" })
      assert.equal("enchanted", plan.kind)
      assert.same(state.item_plan, plan.plan)
      assert.equal("Vocation Ring", state.asked.name)
    end)

    it("passes the bound target through", function()
      local actions, state = build()
      state.item_plan = { type = "none", notes = {} }
      actions.resolve({ type = "enchanteditem", action = "Vocation Ring", target = "t" })
      assert.equal("t", state.asked.target)
    end)

    it("refuses a slot with no item named, the way every game type does", function()
      local actions = build()
      local plan, hint = actions.resolve({ type = "enchanteditem" })
      assert.is_nil(plan)
      assert.equal("missing item name for enchanteditem", hint)
    end)

    it("validates without searching a single bag", function()
      -- Binding is authoring, not firing: validate must not run the plan,
      -- which reads the client's bags and its clock.
      local actions, state = build()
      assert.is_true(actions.validate({ type = "enchanteditem", action = "Vocation Ring" }))
      assert.is_nil(state.asked, "the plan was never asked for")
      local ok, complaint = actions.validate({ type = "enchanteditem" })
      assert.is_nil(ok)
      assert.equal("enchanteditem needs an item name", complaint)
    end)
  end)

  describe("built-in dual frontend", function()
    it("resolves the command form and the slot form identically", function()
      local actions, state = build()
      state.ride = 'input /mount "crab"'
      local slot_state = { weapon_drawn = true }
      assert.same(actions.resolve({ type = "draw" }, slot_state), actions.resolve_builtin("draw", nil, slot_state))
      assert.same(actions.resolve({ type = "mr" }), actions.resolve_builtin("mr"))
      assert.same(actions.resolve({ type = "warp" }), actions.resolve_builtin("warp"))
      assert.same(actions.resolve({ type = "open", action = "map" }), actions.resolve_builtin("open", "map"))
    end)

    it("matches built-in names case-insensitively, like every verb", function()
      local actions, state = build()
      state.ride = "input /dismount"
      state.warp_plan = { type = "none", notes = {} }
      assert.same(actions.resolve_builtin("mr"), actions.resolve_builtin("MR"))
      assert.same(actions.resolve_builtin("warp"), actions.resolve_builtin("Warp"))
    end)

    it("can resolve every built-in name", function()
      -- The shipped names, spelled out: a built-in the command frontend
      -- cannot find would be one no command reaches. Adding a built-in adds
      -- its name here.
      local actions = build()
      for _, name in ipairs(SHIPPED_BUILTINS) do
        local _, err = actions.resolve_builtin(name, name == "open" and "map" or nil, {})
        assert.is_not_equal("unknown built-in action: " .. name, err, name)
      end
    end)

    it("has exactly these built-ins and no others", function()
      --[[ The other half, and the half that catches an entry added by
           accident: the list above only proves every name IT knows
           resolves, so an unlisted built-in was invisible to it. Nothing at
           runtime enumerates the table - the export that did was removed
           deliberately, because a spec that reads its expectation out of
           the code under test cannot catch drift at all - so the roster is
           read from the SOURCE, the same kind of static check
           sources_spec.lua makes over every file in src/.

           IT LEANS ON THE FORMATTER for one thing: the pattern wants each
           entry to start a line, so `draw = {}, fly = {},` written on one
           line would hide `fly` from it. What closes that is stylua -
           `stylua --check .` gates the build and splits the table back out
           - so the escape only exists in a file nobody has formatted. ]]
      local file = assert(io.open("src/components/crossbar/actions.lua", "r"))
      local source = file:read("*a")
      file:close()
      local body = source:match("\nlocal BUILTINS = {(.-)\n}")
      assert.is_string(body, "BUILTINS moved or changed shape - this check has to move with it")
      local found = {}
      for name in body:gmatch("[\r\n]%s*([%w_]+)%s*=") do
        found[#found + 1] = name
      end
      table.sort(found)
      local expected = {}
      for _, name in ipairs(SHIPPED_BUILTINS) do
        expected[#expected + 1] = name
      end
      table.sort(expected)
      assert.same(
        expected,
        found,
        "a built-in was added or removed without updating SHIPPED_BUILTINS "
          .. "(or an entry grew onto several lines, and an inner key like `icon` is being read as a name)"
      )
    end)

    it("rejects an unknown built-in with a hint", function()
      local actions = build()
      local plan, err = actions.resolve_builtin("fly")
      assert.is_nil(plan)
      assert.is_string(err)
    end)
  end)

  describe("icons", function()
    it("swaps draw's icon with its state", function()
      local actions = build()
      assert.equal("dismount", actions.icon_for({ type = "draw" }, { mounted = true, weapon_drawn = true }))
      assert.equal("disengage", actions.icon_for({ type = "draw" }, { weapon_drawn = true }))
      assert.equal("attack", actions.icon_for({ type = "draw" }, { weapon_drawn = false }))
    end)

    it("gives every built-in its fixed icon, and each one ships", function()
      --[[ `mr` wore the generic mount glyph and `warp` a Warp Ring, which
           named one rung of a ladder with several (Kevin, 2026-08-24). The
           roulette has its own art, and the trip is the Warp SPELL's icon -
           by recast id, the way every spell icon resolves.

           Each is checked to exist: an icon naming art that does not ship
           draws a bare square and says nothing. ]]
      local actions = build()
      local expected = {
        ["mr"] = "mounts/mount-roulette",
        ["warp"] = "spells/00261",
      }
      for kind, icon in pairs(expected) do
        assert.equal(icon, actions.icon_for({ type = kind }))
        local file = io.open("src/assets/icons/" .. icon .. ".png", "rb")
        assert.is_not_nil(file, icon .. " must ship")
        file:close()
      end
      assert.equal("map", actions.icon_for({ type = "open", action = "map" }))
    end)

    it("leaves an opener with no pack match to the render fallback", function()
      local actions = build()
      assert.is_nil(actions.icon_for({ type = "open", action = "equipment" }))
    end)
  end)

  describe("bind-time validation", function()
    -- The CLI's gate: a record is checked WITHOUT firing it, so the type
    -- list can never drift from the one resolve() executes.
    it("accepts every game type with an action name", function()
      local actions = build()
      for _, kind in ipairs({ "ma", "ja", "ws", "item", "pet", "mount" }) do
        assert.is_true(actions.validate({ type = kind, action = "Provoke", target = "t" }), kind)
      end
    end)

    it("accepts the no-action built-ins bare", function()
      local actions = build()
      for _, kind in ipairs({ "ra", "draw", "mr", "warp" }) do
        assert.is_true(actions.validate({ type = kind }), kind)
      end
    end)

    it("rejects a game type with no action name", function()
      local actions = build()
      local ok, hint = actions.validate({ type = "ws" })
      assert.is_nil(ok)
      assert.is_string(hint)
    end)

    it("rejects an action name on a type that takes none", function()
      local actions = build()
      for _, kind in ipairs({ "draw", "mr", "warp" }) do
        local ok, hint = actions.validate({ type = kind, action = "Provoke" })
        assert.is_nil(ok, kind)
        assert.is_string(hint, kind)
      end
    end)

    it("rejects an unknown type", function()
      local actions = build()
      local ok, hint = actions.validate({ type = "spell", action = "Cure" })
      assert.is_nil(ok)
      assert.is_string(hint)
    end)

    it("rejects an unknown open target and accepts a known one", function()
      local actions = build()
      assert.is_true(actions.validate({ type = "open", action = "map" }))
      local ok, hint = actions.validate({ type = "open", action = "bogus" })
      assert.is_nil(ok)
      assert.is_string(hint)
    end)

    it("rejects a non-string target and a missing record", function()
      local actions = build()
      local ok = actions.validate({ type = "ws", action = "Savage Blade", target = 5 })
      assert.is_nil(ok)
      assert.is_nil(actions.validate(nil))
    end)

    it("never fires anything it validates", function()
      local actions, state = build({ ride = 'input /mount "Raptor"' })
      assert.is_true(actions.validate({ type = "mr" }))
      assert.is_nil(state.fired)
    end)
  end)

  describe("verb collisions", function()
    it("rejects a built-in name that shadows an authoring verb at load", function()
      local actions = build()
      assert.same({ "draw" }, actions.check_collisions({ "bind", "unbind", "draw", "list" }))
    end)

    it("reports several collisions in sorted-name order, not input order", function()
      local actions = build()
      assert.same({ "draw", "mr" }, actions.check_collisions({ "mr", "draw" }))
    end)

    it("documents open as the deliberate exception", function()
      -- `open` really is a built-in name AND an authoring verb, so this
      -- exercises the exception; `cycle` is an authoring verb only and needs
      -- no exception (its bare-vs-args overload is the command parser's).
      local actions = build()
      assert.same({}, actions.check_collisions({ "open", "bind" }))
    end)
  end)
end)
