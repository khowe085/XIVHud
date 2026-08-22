local new_input = require("components/crossbar/input")

-- The default v4 map, in the shape of the settings `input` table.
local function keymap()
  return {
    xhb_left = { 39 }, -- ;
    xhb_right = { 40 }, -- '
    w_layer = { 43 }, -- backslash
    set_switch = { 41 }, -- backtick
    slot_keys = { 2, 3, 4, 5, 6, 7, 8, 9 }, -- slots 1-8
    shortcuts = {
      [13] = { tap = "open map", chorded = "edit" }, -- '=' ; pad Select
    },
  }
end

-- Builds an input machine over the default map with controllable guards.
local function build(state, keys)
  state = state or {}
  local input = new_input({
    keys = keys or keymap(),
    chat_open = function()
      return state.chat_open or false
    end,
    suppressed = function()
      return state.suppressed or false
    end,
    disabled = function()
      return state.disabled or false
    end,
    edit_mode = function()
      return state.edit_mode or false
    end,
    layout_mode = function()
      return state.layout_mode or false
    end,
  })
  return input, state
end

local function press(input, dik, blocked)
  return input.on_key(dik, true, 0, blocked or false)
end

local function release(input, dik, blocked)
  return input.on_key(dik, false, 0, blocked or false)
end

local function intent_of(intents, wanted)
  local found = nil
  for _, intent in ipairs(intents) do
    if intent.type == wanted then
      assert.is_nil(found, "more than one '" .. wanted .. "' intent")
      found = intent
    end
  end
  return found
end

describe("crossbar input", function()
  it("starts with no hold state", function()
    local input = build()
    assert.equal("none", input.hold_state())
  end)

  describe("hold state", function()
    it("activates xhb_left while ; is held", function()
      local input = build()
      local intents = press(input, 39)
      assert.same({ type = "activate", state = "xhb_left" }, intent_of(intents, "activate"))
      assert.equal("xhb_left", input.hold_state())
    end)

    it("activates xhb_right while ' is held", function()
      local input = build()
      local intents = press(input, 40)
      assert.same({ type = "activate", state = "xhb_right" }, intent_of(intents, "activate"))
      assert.equal("xhb_right", input.hold_state())
    end)

    it("emits activate none when the last side is released", function()
      local input = build()
      press(input, 39)
      local intents = release(input, 39)
      assert.same({ type = "activate", state = "none" }, intent_of(intents, "activate"))
      assert.equal("none", input.hold_state())
    end)

    it("reaches wxhb_left from ; then backslash", function()
      local input = build()
      press(input, 39)
      local intents = press(input, 43)
      assert.same({ type = "activate", state = "wxhb_left" }, intent_of(intents, "activate"))
    end)

    it("reaches wxhb_left from backslash then ;", function()
      local input = build()
      press(input, 43)
      local intents = press(input, 39)
      assert.same({ type = "activate", state = "wxhb_left" }, intent_of(intents, "activate"))
    end)

    it("reaches wxhb_right from ' plus backslash", function()
      local input = build()
      press(input, 40)
      press(input, 43)
      assert.equal("wxhb_right", input.hold_state())
    end)

    it("drops back to the xhb side when the layer is released", function()
      local input = build()
      press(input, 39)
      press(input, 43)
      local intents = release(input, 43)
      assert.same({ type = "activate", state = "xhb_left" }, intent_of(intents, "activate"))
    end)

    it("activates nothing for the layer alone", function()
      local input = build()
      local intents = press(input, 43)
      assert.is_nil(intent_of(intents, "activate"))
      assert.equal("none", input.hold_state())
    end)
  end)

  describe("expanded pair", function()
    it("resolves ; then ' to expanded_lr", function()
      local input = build()
      press(input, 39)
      local intents = press(input, 40)
      assert.same({ type = "activate", state = "expanded_lr" }, intent_of(intents, "activate"))
    end)

    it("resolves ' then ; to expanded_rl", function()
      local input = build()
      press(input, 40)
      local intents = press(input, 39)
      assert.same({ type = "activate", state = "expanded_rl" }, intent_of(intents, "activate"))
    end)

    it("falls back to the survivor's xhb side on release", function()
      local input = build()
      press(input, 39)
      press(input, 40)
      local intents = release(input, 39)
      assert.same({ type = "activate", state = "xhb_right" }, intent_of(intents, "activate"))
      intents = press(input, 39)
      assert.equal("expanded_rl", intent_of(intents, "activate").state)
      intents = release(input, 40)
      assert.same({ type = "activate", state = "xhb_left" }, intent_of(intents, "activate"))
    end)

    it("makes the held side first when a released side is re-pressed", function()
      -- ;v 'v ;^ ;v must read expanded_rl: "first" means first of the
      -- currently-held pair, not whoever was first last time.
      local input = build()
      press(input, 39)
      press(input, 40)
      release(input, 39)
      local intents = press(input, 39)
      assert.same({ type = "activate", state = "expanded_rl" }, intent_of(intents, "activate"))
    end)

    it("ignores the layer over an expanded pair", function()
      local input = build()
      press(input, 39)
      press(input, 40)
      local intents = press(input, 43)
      assert.is_nil(intent_of(intents, "activate"))
      assert.equal("expanded_lr", input.hold_state())
      intents = release(input, 43)
      assert.is_nil(intent_of(intents, "activate"))
    end)

    it("falls back to the wxhb side when the layer is held under expanded", function()
      local input = build()
      press(input, 39)
      press(input, 40)
      press(input, 43)
      local intents = release(input, 40)
      assert.same({ type = "activate", state = "wxhb_left" }, intent_of(intents, "activate"))
    end)
  end)

  describe("held-set resolution", function()
    -- Every enumerable held-set state: sides x layer x switch, both side
    -- orders. The layer only matters with exactly one side; the switch never
    -- affects the state.
    local cases = {
      { held = {}, state = "none" },
      { held = { 43 }, state = "none" },
      { held = { 41 }, state = "none" },
      { held = { 43, 41 }, state = "none" },
      { held = { 39 }, state = "xhb_left" },
      { held = { 39, 41 }, state = "xhb_left" },
      { held = { 40 }, state = "xhb_right" },
      { held = { 40, 41 }, state = "xhb_right" },
      { held = { 39, 43 }, state = "wxhb_left" },
      { held = { 43, 39 }, state = "wxhb_left" },
      { held = { 40, 43 }, state = "wxhb_right" },
      { held = { 43, 40 }, state = "wxhb_right" },
      { held = { 39, 40 }, state = "expanded_lr" },
      { held = { 39, 40, 43 }, state = "expanded_lr" },
      { held = { 43, 39, 40 }, state = "expanded_lr" },
      { held = { 39, 40, 41 }, state = "expanded_lr" },
      { held = { 40, 39 }, state = "expanded_rl" },
      { held = { 40, 39, 43 }, state = "expanded_rl" },
      { held = { 40, 43, 39 }, state = "expanded_rl" },
      { held = { 40, 39, 41 }, state = "expanded_rl" },
    }
    for _, case in ipairs(cases) do
      it("resolves holding {" .. table.concat(case.held, ",") .. "} to " .. case.state, function()
        local input = build()
        for _, dik in ipairs(case.held) do
          press(input, dik)
        end
        assert.equal(case.state, input.hold_state())
      end)
    end
  end)

  describe("slot keys", function()
    it("fires the slot once per press while a hold state is active", function()
      local input = build()
      press(input, 39)
      local intents = press(input, 4) -- DIK 4 = slot 3
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)

    it("fires under every hold state", function()
      local states = {
        { keys = { 39 } },
        { keys = { 40 } },
        { keys = { 39, 43 } },
        { keys = { 40, 43 } },
        { keys = { 39, 40 } },
        { keys = { 40, 39 } },
      }
      for _, case in ipairs(states) do
        local input = build()
        for _, dik in ipairs(case.keys) do
          press(input, dik)
        end
        local intents = press(input, 2)
        assert.same({ type = "fire", slot = 1 }, intent_of(intents, "fire"))
      end
    end)

    it("does nothing with no hold state active and the switch up", function()
      local input = build()
      local intents, blocked = press(input, 4)
      assert.same({}, intents)
      assert.is_false(blocked)
      intents, blocked = release(input, 4)
      assert.same({}, intents)
      assert.is_false(blocked)
    end)

    it("fires exactly once across an auto-repeat stream", function()
      local input = build()
      press(input, 39)
      local fires = 0
      for _ = 1, 5 do
        local intents = press(input, 4)
        if intent_of(intents, "fire") then
          fires = fires + 1
        end
      end
      assert.equal(1, fires)
      release(input, 4)
      local intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)

    it("does not fire the layer-only state", function()
      local input = build()
      press(input, 43)
      local intents = press(input, 4)
      assert.is_nil(intent_of(intents, "fire"))
    end)
  end)

  describe("blocking", function()
    it("blocks all five dedicated keys at press and at release", function()
      local input = build()
      for _, dik in ipairs({ 39, 40, 43, 41, 13 }) do
        local _, blocked = press(input, dik)
        assert.is_true(blocked, "press of " .. dik)
        _, blocked = release(input, dik)
        assert.is_true(blocked, "release of " .. dik)
      end
    end)

    it("blocks the switch across a held auto-repeat stream", function()
      local input = build()
      press(input, 41)
      for _ = 1, 3 do
        local _, blocked = press(input, 41)
        assert.is_true(blocked)
      end
      local _, blocked = release(input, 41)
      assert.is_true(blocked)
    end)

    it("blocks the switch while a hold state is active", function()
      local input = build()
      press(input, 39)
      local _, blocked = press(input, 41)
      assert.is_true(blocked)
      _, blocked = release(input, 41)
      assert.is_true(blocked)
    end)

    it("blocks a slot key only while a hold state is active or the switch is held", function()
      local input = build()
      local _, blocked = press(input, 4)
      assert.is_false(blocked)
      _, blocked = release(input, 4)
      assert.is_false(blocked)

      press(input, 39)
      _, blocked = press(input, 4)
      assert.is_true(blocked)
      _, blocked = release(input, 4)
      assert.is_true(blocked)
      release(input, 39)

      press(input, 41)
      _, blocked = press(input, 5)
      assert.is_true(blocked)
      _, blocked = release(input, 5)
      assert.is_true(blocked)
      release(input, 41)
    end)

    it("lets a slot release through when its press went to the game", function()
      -- A `3` pressed unblocked whose release arrives after a side went down
      -- must still reach the game, or FFXI sees a key held forever.
      local input = build()
      press(input, 3)
      press(input, 39)
      local _, blocked = release(input, 3)
      assert.is_false(blocked)
    end)

    it("keeps a blocked slot key's repeats and release blocked after the side lifts", function()
      -- The latch is decided at the press edge: repeats follow it, in both
      -- directions, or the game sees downs with no up (or an up with no down).
      local input = build()
      press(input, 39)
      press(input, 4)
      release(input, 39)
      local _, blocked = press(input, 4)
      assert.is_true(blocked)
      _, blocked = release(input, 4)
      assert.is_true(blocked)
    end)

    it("keeps an unblocked slot key's repeats unblocked after a side goes down", function()
      local input = build()
      press(input, 3)
      press(input, 39)
      local _, blocked = press(input, 3)
      assert.is_false(blocked)
    end)

    it("never blocks an unmapped key", function()
      local input = build()
      press(input, 39)
      local intents, blocked = press(input, 30) -- 'a'
      assert.same({}, intents)
      assert.is_false(blocked)
    end)

    it("blocks a shortcut key when chorded with a side", function()
      local input = build()
      press(input, 39)
      local _, blocked = press(input, 13)
      assert.is_true(blocked)
      _, blocked = release(input, 13)
      assert.is_true(blocked)
    end)
  end)

  describe("configured key lists", function()
    it("treats every DIK in a role's list as that role", function()
      local keys = keymap()
      keys.w_layer = { 43, 53 } -- a second key folded into the layer
      local input = build(nil, keys)
      press(input, 39)
      local intents = press(input, 53)
      assert.same({ type = "activate", state = "wxhb_left" }, intent_of(intents, "activate"))
      -- Both layer keys down: releasing one keeps the layer held.
      press(input, 43)
      intents = release(input, 53)
      assert.is_nil(intent_of(intents, "activate"))
      assert.equal("wxhb_left", input.hold_state())
      intents = release(input, 43)
      assert.same({ type = "activate", state = "xhb_left" }, intent_of(intents, "activate"))
    end)

    it("gives a slot with a false entry no key at all", function()
      local keys = keymap()
      keys.slot_keys[3] = false -- slot 3 has no key; DIK 4 is the game's
      local input = build(nil, keys)
      press(input, 39)
      local intents, blocked = press(input, 4)
      assert.is_nil(intent_of(intents, "fire"))
      assert.is_false(blocked)
    end)

    it("treats a role disabled with false as having no keys", function()
      local keys = keymap()
      keys.xhb_left = false
      local input = build(nil, keys)
      local intents, blocked = press(input, 39)
      assert.same({}, intents)
      assert.is_false(blocked)
      assert.equal("none", input.hold_state())
    end)

    it("treats a shortcut disabled with false as the game's key", function()
      local keys = keymap()
      keys.shortcuts[13] = false
      local input = build(nil, keys)
      local intents, blocked = press(input, 13)
      assert.same({}, intents)
      assert.is_false(blocked)
    end)

    it("keeps a shortcut with no tap verb blocked but silent on a bare press", function()
      local keys = keymap()
      keys.shortcuts[13] = { chorded = "edit" }
      local input = build(nil, keys)
      local intents, blocked = press(input, 13)
      assert.is_nil(intent_of(intents, "shortcut"))
      assert.is_true(blocked)
    end)

    it("resolves press order across a two-key side", function()
      local keys = keymap()
      keys.xhb_left = { 39, 30 }
      local input = build(nil, keys)
      press(input, 39)
      press(input, 30) -- second left key: side already held, no change
      local intents = press(input, 40)
      assert.equal("expanded_lr", intent_of(intents, "activate").state)
      -- One left key up: the side is still held, nothing changes.
      intents = release(input, 39)
      assert.is_nil(intent_of(intents, "activate"))
      assert.equal("expanded_lr", input.hold_state())
      -- Side fully released, then re-pressed into the held right: the held
      -- side is now first, whichever left key comes back down.
      release(input, 30)
      intents = press(input, 39)
      assert.equal("expanded_rl", intent_of(intents, "activate").state)
    end)
  end)

  describe("chat guard", function()
    it("fires no actions and blocks nothing while chat is open", function()
      local input, state = build()
      press(input, 39)
      state.chat_open = true

      local intents, blocked = press(input, 4)
      assert.is_nil(intent_of(intents, "fire"))
      assert.is_false(blocked)
      release(input, 4)

      local _, switch_blocked = press(input, 41)
      assert.is_false(switch_blocked)
      intents, blocked = release(input, 41)
      assert.is_nil(intent_of(intents, "cycle"))
      assert.is_false(blocked)

      intents, blocked = press(input, 13)
      assert.is_nil(intent_of(intents, "shortcut"))
      assert.is_false(blocked)
    end)

    it("passes activate so a release mid-chat cannot strand the hold state", function()
      local input, state = build()
      press(input, 39)
      state.chat_open = true
      local intents, blocked = release(input, 39)
      assert.same({ type = "activate", state = "none" }, intent_of(intents, "activate"))
      assert.is_true(blocked) -- the latch outranks the guard
      assert.equal("none", input.hold_state())
    end)

    it("passes activate for a press during chat too", function()
      local input, state = build()
      state.chat_open = true
      local intents, blocked = press(input, 39)
      assert.same({ type = "activate", state = "xhb_left" }, intent_of(intents, "activate"))
      assert.is_false(blocked)
    end)

    it("keeps tracking activator state through chat", function()
      local input, state = build()
      state.chat_open = true
      press(input, 39)
      state.chat_open = false
      local intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)

    it("clears a slot key's down-state on a release during chat", function()
      -- Round 11: otherwise the next press reads as an auto-repeat and never
      -- fires.
      local input, state = build()
      press(input, 39)
      press(input, 4)
      state.chat_open = true
      release(input, 4)
      state.chat_open = false
      local intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)

    it("tracks a slot press during chat so it cannot fire on repeat after", function()
      local input, state = build()
      press(input, 39)
      state.chat_open = true
      press(input, 4)
      state.chat_open = false
      local intents = press(input, 4) -- auto-repeat of the chat-time press
      assert.is_nil(intent_of(intents, "fire"))
    end)

    it("keeps a latched key's auto-repeats blocked after chat opens", function()
      -- Auto-repeats follow the latch too, in both directions: a held ; must
      -- not start spamming the chat line the moment the box opens.
      local input, state = build()
      press(input, 39)
      state.chat_open = true
      for _ = 1, 3 do
        local _, blocked = press(input, 39)
        assert.is_true(blocked)
      end
      local _, blocked = release(input, 39)
      assert.is_true(blocked)
    end)

    it("suppresses jump and draw too", function()
      local input, state = build()
      state.chat_open = true
      press(input, 41)
      local intents = press(input, 4)
      assert.is_nil(intent_of(intents, "jump"))
      release(input, 4)
      release(input, 41)

      press(input, 43)
      press(input, 41)
      intents = release(input, 41)
      assert.is_nil(intent_of(intents, "draw"))
    end)
  end)

  describe("inbound blocked guard", function()
    it("fires nothing and blocks nothing when another addon ate the key", function()
      local input = build()
      press(input, 39)
      local intents, blocked = press(input, 4, true)
      assert.is_nil(intent_of(intents, "fire"))
      assert.is_false(blocked)
      -- No latch was set, so the release passes too.
      local _, release_blocked = release(input, 4)
      assert.is_false(release_blocked)
    end)

    it("still tracks activator state and passes activate", function()
      -- A blocked side-key down must not leave the model reading none while
      -- the key is physically held, or every later key routes wrong.
      local input = build()
      local intents, blocked = press(input, 39, true)
      assert.same({ type = "activate", state = "xhb_left" }, intent_of(intents, "activate"))
      assert.is_false(blocked)
      assert.equal("xhb_left", input.hold_state())
      local fire_intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(fire_intents, "fire"))
    end)

    it("still swallows a latched release that arrives inbound-blocked", function()
      local input = build()
      press(input, 39)
      local intents, blocked = release(input, 39, true)
      assert.is_true(blocked)
      assert.same({ type = "activate", state = "none" }, intent_of(intents, "activate"))
    end)

    it("tracks slot down-state so an inbound-blocked press cannot fire on repeat", function()
      local input = build()
      press(input, 39)
      press(input, 4, true)
      local intents = press(input, 4)
      assert.is_nil(intent_of(intents, "fire"))
      release(input, 4)
      intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)

    it("suppresses cycle on an inbound-blocked switch release", function()
      local input = build()
      press(input, 41)
      local intents, blocked = release(input, 41, true)
      assert.is_nil(intent_of(intents, "cycle"))
      assert.is_true(blocked) -- the press was ours, the latch stands
    end)
  end)

  describe("focus guard", function()
    it("clears all held state and reports the drop", function()
      local input = build()
      press(input, 39)
      press(input, 43)
      local intents = input.focus_lost()
      assert.same({ type = "activate", state = "none" }, intent_of(intents, "activate"))
      assert.equal("none", input.hold_state())
    end)

    it("returns no intent when nothing was active", function()
      local input = build()
      assert.same({}, input.focus_lost())
    end)

    it("reads the next press of a formerly-held key as fresh", function()
      local input = build()
      press(input, 39)
      press(input, 4)
      input.focus_lost()
      press(input, 39)
      local intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)

    it("drops latches - a stray release after refocus passes through", function()
      local input = build()
      press(input, 39)
      input.focus_lost()
      local intents, blocked = release(input, 39)
      assert.is_false(blocked)
      assert.same({}, intents)
    end)

    it("forgets a switch hold, so its later release does not cycle", function()
      local input = build()
      press(input, 41)
      input.focus_lost()
      local intents = release(input, 41)
      assert.is_nil(intent_of(intents, "cycle"))
    end)
  end)

  describe("suppression guard", function()
    it("fires nothing while suppressed", function()
      local input, state = build()
      state.suppressed = true
      press(input, 39)
      local intents = press(input, 4)
      assert.is_nil(intent_of(intents, "fire"))
      release(input, 4)
      release(input, 39)
      press(input, 41)
      intents = release(input, 41)
      assert.is_nil(intent_of(intents, "cycle"))
      intents = press(input, 13)
      assert.is_nil(intent_of(intents, "shortcut"))
    end)

    it("keeps the five dedicated keys blocked", function()
      -- An unblocked side key would open the chat log mid-cutscene and leave
      -- the component inert once suppression lifted.
      local input, state = build()
      state.suppressed = true
      for _, dik in ipairs({ 39, 40, 43, 41, 13 }) do
        local _, blocked = press(input, dik)
        assert.is_true(blocked, "press of " .. dik)
        _, blocked = release(input, dik)
        assert.is_true(blocked, "release of " .. dik)
      end
    end)

    it("lets slot keys fall through even with a side held", function()
      local input, state = build()
      state.suppressed = true
      press(input, 39)
      local _, blocked = press(input, 4)
      assert.is_false(blocked)
      _, blocked = release(input, 4)
      assert.is_false(blocked)
    end)

    it("tracks state across suppression without stranding an activator", function()
      local input, state = build()
      press(input, 39)
      state.suppressed = true
      local intents = release(input, 39)
      assert.same({ type = "activate", state = "none" }, intent_of(intents, "activate"))
      state.suppressed = false
      assert.equal("none", input.hold_state())
    end)

    it("keeps a hold made during suppression usable once it lifts", function()
      local input, state = build()
      state.suppressed = true
      press(input, 39)
      state.suppressed = false
      local intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)

    it("still swallows a latched release across the transition", function()
      local input, state = build()
      press(input, 39)
      press(input, 4)
      state.suppressed = true
      local _, blocked = release(input, 4)
      assert.is_true(blocked)
    end)
  end)

  describe("disabled", function()
    it("is fully inert: no intents, nothing blocked, ours included", function()
      local input, state = build()
      state.disabled = true
      for _, dik in ipairs({ 39, 40, 43, 41, 13, 4 }) do
        local intents, blocked = press(input, dik)
        assert.same({}, intents, "press of " .. dik)
        assert.is_false(blocked, "press of " .. dik)
      end
      local intents, blocked = release(input, 41)
      assert.same({}, intents)
      assert.is_false(blocked)
    end)

    it("still swallows a release latched before it was disabled", function()
      -- The one case where a key we no longer want is swallowed once, on its
      -- way up: the game never saw the press.
      local input, state = build()
      press(input, 39)
      press(input, 4)
      state.disabled = true
      local _, blocked = release(input, 4)
      assert.is_true(blocked)
      _, blocked = release(input, 39)
      assert.is_true(blocked)
    end)

    it("keeps tracking key state for re-enabling mid-hold", function()
      local input, state = build()
      state.disabled = true
      press(input, 39)
      state.disabled = false
      local intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)
  end)

  describe("edit mode guard", function()
    it("fires nothing from sides, the layer key or a bare slot press", function()
      --[[ The switch is the exception, and gets its own tests below: which
           set is on screen is what edit mode is FOR (Kevin, live client,
           2026-08-22). Everything else stays dead. ]]
      local input, state = build()
      state.edit_mode = true
      press(input, 39)
      local intents = press(input, 4)
      assert.is_nil(intent_of(intents, "fire"))
      release(input, 4)
      release(input, 39)
      -- A bare slot press, with no switch under it, is nothing at all.
      intents = press(input, 4)
      assert.is_nil(intent_of(intents, "fire"))
      assert.is_nil(intent_of(intents, "jump"))
      release(input, 4)
      -- And the layer key over the switch is `draw`, which is an action.
      press(input, 43)
      press(input, 41)
      intents = release(input, 41)
      assert.is_nil(intent_of(intents, "draw"))
      assert.is_nil(intent_of(intents, "cycle"), "not a cycle either - the layer was down")
      release(input, 43)
    end)

    it("still cycles and jumps from the switch", function()
      local input, state = build()
      state.edit_mode = true
      press(input, 41)
      local intents = release(input, 41)
      assert.is_not_nil(intent_of(intents, "cycle"), "a clean tap still cycles")
      press(input, 41)
      intents = press(input, 4)
      local jump = intent_of(intents, "jump")
      assert.is_not_nil(jump, "and the chord still jumps")
      assert.are.equal(3, jump.set)
      release(input, 4)
      release(input, 41)
    end)

    it("keeps our five keys blocked while slot keys fall through", function()
      local input, state = build()
      state.edit_mode = true
      for _, dik in ipairs({ 39, 40, 43, 41, 13 }) do
        local _, blocked = press(input, dik)
        assert.is_true(blocked, "press of " .. dik)
        release(input, dik)
      end
      press(input, 39)
      local _, blocked = press(input, 4)
      assert.is_false(blocked)
    end)

    it("still tracks state, activate included", function()
      local input, state = build()
      state.edit_mode = true
      local intents = press(input, 39)
      assert.same({ type = "activate", state = "xhb_left" }, intent_of(intents, "activate"))
      state.edit_mode = false
      intents = press(input, 4)
      assert.same({ type = "fire", slot = 3 }, intent_of(intents, "fire"))
    end)

    it("keeps the edit-toggling shortcut key live, bare or chorded", function()
      local input, state = build()
      state.edit_mode = true
      local intents = press(input, 13)
      assert.same({ type = "shortcut", verb = "edit" }, intent_of(intents, "shortcut"))
      release(input, 13)
      press(input, 39)
      intents = press(input, 13)
      assert.same({ type = "shortcut", verb = "edit" }, intent_of(intents, "shortcut"))
    end)

    it("keeps a shortcut key without an edit verb inert but blocked", function()
      local keys = keymap()
      keys.shortcuts[14] = { tap = "open inventory" }
      local input, state = build(nil, keys)
      state.edit_mode = true
      local intents, blocked = press(input, 14)
      assert.is_nil(intent_of(intents, "shortcut"))
      assert.is_true(blocked)
    end)

    it("exits through a shortcut whose chorded verb is the edit one", function()
      -- Any press of an edit-toggling key exits, so even a bare press of a key
      -- that only carries edit on its CHORDED arm must leave edit mode.
      local keys = keymap()
      keys.shortcuts[14] = { tap = "open inventory", chorded = "edit" }
      local input, state = build(nil, keys)
      state.edit_mode = true
      local intents = press(input, 14)
      assert.same({ type = "shortcut", verb = "edit" }, intent_of(intents, "shortcut"))
    end)

    it("still swallows a latched release across entering edit mode", function()
      local input, state = build()
      press(input, 39)
      press(input, 4)
      state.edit_mode = true
      local _, blocked = release(input, 4)
      assert.is_true(blocked)
    end)
  end)

  describe("layout mode", function()
    it("fires nothing while our five keys stay blocked", function()
      -- Placing the anchors must not open the chat log with every ;.
      local input, state = build()
      state.layout_mode = true
      for _, dik in ipairs({ 40, 43, 41, 13 }) do
        local _, blocked = press(input, dik)
        assert.is_true(blocked, "press of " .. dik)
        release(input, dik)
      end
      local _, side_blocked = press(input, 39)
      assert.is_true(side_blocked)
      local intents = press(input, 4)
      assert.is_nil(intent_of(intents, "fire"))
      release(input, 4)
      release(input, 39)
      press(input, 41)
      intents = release(input, 41)
      assert.is_nil(intent_of(intents, "cycle"))
      intents = press(input, 13)
      assert.is_nil(intent_of(intents, "shortcut"))
    end)

    it("lets slot keys fall through", function()
      local input, state = build()
      state.layout_mode = true
      press(input, 39)
      local _, blocked = press(input, 4)
      assert.is_false(blocked)
    end)

    it("still emits activate, like suppression - only actions are silenced", function()
      local input, state = build()
      state.layout_mode = true
      local intents = press(input, 39)
      assert.same({ type = "activate", state = "xhb_left" }, intent_of(intents, "activate"))
      intents = release(input, 39)
      assert.same({ type = "activate", state = "none" }, intent_of(intents, "activate"))
    end)

    it("tracks state and swallows a latched release across the transition", function()
      local input, state = build()
      press(input, 39)
      press(input, 4)
      state.layout_mode = true
      local _, blocked = release(input, 4)
      assert.is_true(blocked)
      local intents = release(input, 39)
      assert.same({ type = "activate", state = "none" }, intent_of(intents, "activate"))
    end)
  end)

  describe("shortcut keys", function()
    it("fires its tap verb on a bare press", function()
      local input = build()
      local intents = press(input, 13)
      assert.same({ type = "shortcut", verb = "open map" }, intent_of(intents, "shortcut"))
    end)

    it("fires its chorded verb while a side is held", function()
      local input = build()
      press(input, 39)
      local intents = press(input, 13)
      assert.same({ type = "shortcut", verb = "edit" }, intent_of(intents, "shortcut"))
    end)

    it("fires the chorded verb under an expanded pair too", function()
      local input = build()
      press(input, 40)
      press(input, 39)
      local intents = press(input, 13)
      assert.same({ type = "shortcut", verb = "edit" }, intent_of(intents, "shortcut"))
    end)

    it("counts neither the layer nor the switch as a chord", function()
      local input = build()
      press(input, 43)
      local intents = press(input, 13)
      assert.equal("open map", intent_of(intents, "shortcut").verb)
      release(input, 13)
      release(input, 43)

      press(input, 41)
      intents = press(input, 13)
      assert.equal("open map", intent_of(intents, "shortcut").verb)
    end)

    it("fires once per press, not per auto-repeat, and nothing on release", function()
      local input = build()
      press(input, 13)
      local intents = press(input, 13)
      assert.is_nil(intent_of(intents, "shortcut"))
      intents = release(input, 13)
      assert.is_nil(intent_of(intents, "shortcut"))
    end)
  end)

  describe("the switch", function()
    it("cycles on a bare tap", function()
      local input = build()
      local intents = press(input, 41)
      assert.same({}, intents)
      intents = release(input, 41)
      assert.same({ type = "cycle" }, intent_of(intents, "cycle"))
    end)

    it("jumps to the slot key's set while held, and does not also cycle", function()
      local input = build()
      press(input, 41)
      local intents = press(input, 7) -- DIK 7 = slot 6
      assert.same({ type = "jump", set = 6 }, intent_of(intents, "jump"))
      assert.is_nil(intent_of(intents, "fire"))
      intents = release(input, 41)
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("jumps even while the layer is held", function()
      local input = build()
      press(input, 43)
      press(input, 41)
      local intents = press(input, 2)
      assert.same({ type = "jump", set = 1 }, intent_of(intents, "jump"))
    end)

    it("fires the draw toggle when tapped with the layer held", function()
      local input = build()
      press(input, 43)
      press(input, 41)
      local intents = release(input, 41)
      assert.same({ type = "draw" }, intent_of(intents, "draw"))
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("fires draw when the layer comes down after the switch", function()
      -- The layer is checked at the release edge, so the gesture works in
      -- either press order.
      local input = build()
      press(input, 41)
      press(input, 43)
      local intents = release(input, 41)
      assert.same({ type = "draw" }, intent_of(intents, "draw"))
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("cycles, not draws, once the layer is released before the tap ends", function()
      local input = build()
      press(input, 43)
      press(input, 41)
      release(input, 43)
      local intents = release(input, 41)
      assert.same({ type = "cycle" }, intent_of(intents, "cycle"))
      assert.is_nil(intent_of(intents, "draw"))
    end)

    it("does not fire draw when a slot key was chorded during the hold", function()
      local input = build()
      press(input, 43)
      press(input, 41)
      press(input, 2)
      release(input, 2)
      local intents = release(input, 41)
      assert.is_nil(intent_of(intents, "draw"))
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("is inert while a side is held", function()
      local input = build()
      press(input, 39)
      press(input, 41)
      local intents = release(input, 41)
      assert.same({}, intents)
    end)

    it("stays inert when the side is released before the switch", function()
      -- Pressing the switch while using the bar must not turn into a cycle
      -- just because the side came up first.
      local input = build()
      press(input, 39)
      press(input, 41)
      release(input, 39)
      local intents = release(input, 41)
      assert.is_nil(intent_of(intents, "cycle"))
      assert.is_nil(intent_of(intents, "draw"))
    end)

    it("goes inert when a side comes down mid-hold", function()
      local input = build()
      press(input, 41)
      press(input, 39)
      release(input, 39)
      local intents = release(input, 41)
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("still jumps after a side overlap, once the side is back up", function()
      -- Jump is instantaneous - it needs only "no side held" at the slot's
      -- press edge - while cycle/draw are poisoned for the whole gesture.
      local input = build()
      press(input, 41)
      press(input, 39)
      release(input, 39)
      local intents = press(input, 4)
      assert.same({ type = "jump", set = 3 }, intent_of(intents, "jump"))
      release(input, 4)
      intents = release(input, 41)
      assert.is_nil(intent_of(intents, "cycle"))
      assert.is_nil(intent_of(intents, "draw"))
    end)

    it("lets slot keys fire rather than jump while a side is held", function()
      local input = build()
      press(input, 39)
      press(input, 41)
      local intents = press(input, 7)
      assert.same({ type = "fire", slot = 6 }, intent_of(intents, "fire"))
      assert.is_nil(intent_of(intents, "jump"))
    end)

    it("emits no shortcut intent itself", function()
      local input = build()
      local intents = press(input, 41)
      assert.is_nil(intent_of(intents, "shortcut"))
    end)

    it("still cycles when a slot key held from before the hold auto-repeats", function()
      -- A slot key already down BEFORE the switch went down was not chorded
      -- during the hold; its OS auto-repeats must not turn the tap into a
      -- dead chord.
      local input = build()
      press(input, 2)
      press(input, 41)
      press(input, 2) -- auto-repeat of the earlier press
      local intents = release(input, 41)
      assert.same({ type = "cycle" }, intent_of(intents, "cycle"))
    end)

    it("still cycles over a slot key held from before with no repeat at all", function()
      local input = build()
      press(input, 2)
      press(input, 41)
      local intents = release(input, 41)
      assert.same({ type = "cycle" }, intent_of(intents, "cycle"))
    end)

    it("cycles again on a fresh tap after a chorded hold", function()
      local input = build()
      press(input, 41)
      press(input, 2)
      release(input, 2)
      release(input, 41)
      press(input, 41)
      local intents = release(input, 41)
      assert.same({ type = "cycle" }, intent_of(intents, "cycle"))
    end)
  end)

  describe("a DIK bound to two roles", function()
    -- Only a hand-edited config can do this; the shipped map is disjoint.
    local function doubled()
      local keys = keymap()
      keys.shortcuts[5] = { tap = "open map", chorded = "edit" }
      return keys
    end

    it("reports the slot key it collides with, once, by DIK", function()
      local input = build(nil, doubled())
      assert.are.same({ { dik = 5, kept = "slot 4", dropped = { "a shortcut" } } }, input.conflicts())
    end)

    it("keeps the slot key and drops the shortcut, rather than losing it silently", function()
      local input = build(nil, doubled())
      -- Bare: the slot branch used to win and emit nothing at all, so the
      -- shortcut simply never fired. The resolution is the same key, said
      -- out loud - and never a shortcut intent.
      assert.is_nil(intent_of(press(input, 5), "shortcut"))
      release(input, 5)
      -- And with a side held it is still the slot it always was.
      press(input, 39)
      assert.are.equal(4, intent_of(press(input, 5), "fire").slot)
    end)

    it("keeps the side key and drops a shortcut sharing its DIK", function()
      -- Worse than the slot case: this one fired BOTH on a single press - the
      -- side went up and the shortcut's verb ran with it.
      local keys = keymap()
      keys.shortcuts[39] = { tap = "open map", chorded = "edit" }
      local input = build(nil, keys)
      assert.are.same({ { dik = 39, kept = "the left side", dropped = { "a shortcut" } } }, input.conflicts())
      local intents = press(input, 39)
      assert.is_not_nil(intent_of(intents, "activate"), "still a side key")
      assert.is_nil(intent_of(intents, "shortcut"), "and only a side key")
    end)

    it("keeps the first role a DIK is listed under and drops the second", function()
      -- Two roles used to be settled by which assignment ran last, which is
      -- the map's declaration order read backwards. The first claim wins.
      local keys = keymap()
      keys.w_layer = { 39 }
      local input = build(nil, keys)
      assert.are.same({ { dik = 39, kept = "the left side", dropped = { "the WXHB layer" } } }, input.conflicts())
      press(input, 39)
      assert.are.equal("xhb_left", input.hold_state(), "the side it was listed as first")
    end)

    it("leaves a disjoint map with nothing to report", function()
      local input = build()
      assert.are.same({}, input.conflicts())
    end)
  end)
end)
