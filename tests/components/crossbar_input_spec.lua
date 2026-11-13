local new_input = require("components/crossbar/input")

-- Builds an input machine with controllable guards.
local function build(state)
  state = state or {}
  local input = new_input({
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

--[[ Behaviours reach the machine the keys do - the hold state, the set switch
     and the slots. A press also answers whether the key it came from, where
     the keyboard map sent it, is the bar's to keep from the game. ]]
describe("crossbar input behaviours", function()
  local function hold(input, name)
    return (input.on_behavior(name, true))
  end

  local function let_go(input, name, cancelled)
    return (input.on_behavior(name, false, cancelled))
  end

  local function state_of(intents)
    local intent = intent_of(intents, "activate")
    return intent and intent.state
  end

  it("has no key path: keys reach it as behaviours", function()
    assert.is_nil(build().on_key)
  end)

  it("raises a side while its behaviour is held", function()
    local input = build()
    assert.equal("xhb_left", state_of(hold(input, "left")))
    assert.equal("none", state_of(let_go(input, "left")))
  end)

  it("raises Expanded with both sides held, in the order they went down", function()
    local input = build()
    hold(input, "left")
    assert.equal("expanded_lr", state_of(hold(input, "right")))
    let_go(input, "left")
    let_go(input, "right")
    hold(input, "right")
    hold(input, "left")
    assert.equal("expanded_rl", input.hold_state())
  end)

  it("raises a WXHB half over a side, and lowers it back to the side", function()
    local input = build()
    hold(input, "left")
    assert.equal("wxhb_left", state_of(hold(input, "wxhb_left")))
    assert.equal("xhb_left", state_of(let_go(input, "wxhb_left")))
  end)

  it("raises a WXHB half with no side held", function()
    local input = build()
    hold(input, "wxhb_right")
    assert.equal("wxhb_right", input.hold_state())
  end)

  it("puts the newer WXHB half up with both held", function()
    local input = build()
    hold(input, "wxhb_left")
    hold(input, "wxhb_right")
    assert.equal("wxhb_right", input.hold_state())
    let_go(input, "wxhb_right")
    assert.equal("wxhb_left", input.hold_state())
  end)

  it("puts a WXHB half up over Expanded", function()
    local input = build()
    hold(input, "left")
    hold(input, "right")
    hold(input, "wxhb_left")
    assert.equal("wxhb_left", input.hold_state())
  end)

  it("fires slot N of the raised bar, on the press alone", function()
    local input = build()
    hold(input, "left")
    assert.same({ type = "fire", slot = 3 }, intent_of(hold(input, "slot3"), "fire"))
    assert.is_nil(intent_of(let_go(input, "slot3"), "fire"))
  end)

  it("fires nothing with no bar raised", function()
    local input = build()
    assert.same({}, hold(input, "slot1"))
  end)

  it("jumps to a set with the switch held, and does not cycle after", function()
    local input = build()
    hold(input, "switch")
    assert.same({ type = "jump", set = 5 }, intent_of(hold(input, "slot5"), "jump"))
    let_go(input, "slot5")
    assert.is_nil(intent_of(let_go(input, "switch"), "cycle"))
  end)

  it("cycles on a tap of the switch", function()
    local input = build()
    hold(input, "switch")
    assert.same({ type = "cycle" }, intent_of(let_go(input, "switch"), "cycle"))
  end)

  it("does not cycle on a cancelled let-go of the switch, and does on the next tap", function()
    local input = build()
    hold(input, "switch")
    assert.is_nil(intent_of(let_go(input, "switch", true), "cycle"))
    hold(input, "switch")
    assert.same({ type = "cycle" }, intent_of(let_go(input, "switch"), "cycle"))
  end)

  it("keeps the switch from cycling with a WXHB half raised under it", function()
    local input = build()
    hold(input, "switch")
    hold(input, "wxhb_left")
    assert.is_nil(intent_of(let_go(input, "switch"), "cycle"))
  end)

  it("lowers the bar on a cancelled let-go", function()
    local input = build()
    hold(input, "left")
    assert.equal("none", state_of(let_go(input, "left", true)))
  end)

  it("toggles the binder with or without a side held", function()
    local input = build()
    assert.same({ type = "shortcut", verb = "edit" }, intent_of(hold(input, "binder"), "shortcut"))
    let_go(input, "binder")
    hold(input, "left")
    assert.same({ type = "shortcut", verb = "edit" }, intent_of(hold(input, "binder"), "shortcut"))
  end)

  it("draws on the press alone, with no bar raised", function()
    local input = build()
    assert.same({ { type = "draw" } }, hold(input, "draw"))
    assert.same({}, let_go(input, "draw"))
  end)

  it("draws nothing under a raised side or WXHB half", function()
    for _, raised in ipairs({ "left", "right", "wxhb_left", "wxhb_right" }) do
      local input = build()
      hold(input, raised)
      assert.same({}, hold(input, "draw"), raised)
    end
  end)

  it("keeps the switch it draws over from cycling, and cycles on the next tap", function()
    local input = build()
    hold(input, "switch")
    assert.same({ { type = "draw" } }, hold(input, "draw"))
    let_go(input, "draw")
    assert.is_nil(intent_of(let_go(input, "switch"), "cycle"))
    hold(input, "switch")
    assert.same({ type = "cycle" }, intent_of(let_go(input, "switch"), "cycle"))
  end)

  it("draws nothing in edit mode or under a guard", function()
    for _, guard in ipairs({ "edit_mode", "chat_open", "suppressed", "layout_mode", "disabled" }) do
      local input = build({ [guard] = true })
      assert.same({}, hold(input, "draw"), guard)
    end
  end)

  it("keeps the chat guard: the bar rises and nothing fires", function()
    local input = build({ chat_open = true })
    assert.equal("xhb_left", state_of(hold(input, "left")))
    assert.is_nil(intent_of(hold(input, "slot1"), "fire"))
  end)

  it("does nothing at all while disabled", function()
    local input = build({ disabled = true })
    assert.same({}, hold(input, "left"))
    assert.same({}, hold(input, "slot1"))
  end)

  it("fires nothing while suppressed or in layout mode", function()
    for _, guard in ipairs({ "suppressed", "layout_mode" }) do
      local input = build({ [guard] = true })
      hold(input, "left")
      assert.is_nil(intent_of(hold(input, "slot1"), "fire"), guard)
    end
  end)

  it("keeps edit mode's two live inputs, the binder and the switch", function()
    local input = build({ edit_mode = true })
    assert.same({ type = "shortcut", verb = "edit" }, intent_of(hold(input, "binder"), "shortcut"))
    hold(input, "switch")
    assert.same({ type = "jump", set = 2 }, intent_of(hold(input, "slot2"), "jump"))
    let_go(input, "slot2")
    let_go(input, "switch")
    hold(input, "left")
    assert.is_nil(intent_of(hold(input, "slot1"), "fire"))
  end)

  it("ignores a behaviour it does not have", function()
    local input = build()
    assert.same({}, hold(input, "nope"))
  end)

  it("ignores a repeat of a held behaviour", function()
    local input = build()
    hold(input, "left")
    assert.same({}, hold(input, "left"))
  end)

  it("forgets every behaviour as focus goes", function()
    local input = build()
    hold(input, "left")
    input.focus_lost()
    assert.same({}, let_go(input, "left"))
  end)

  it("raises a side's WXHB half with the layer held over it, as backslash does", function()
    local input = build()
    hold(input, "left")
    assert.equal("wxhb_left", state_of(hold(input, "layer")))
    assert.equal("xhb_left", state_of(let_go(input, "layer")))
  end)

  it("draws on a tap of the switch over the held layer", function()
    local input = build()
    hold(input, "layer")
    hold(input, "switch")
    assert.same({ type = "draw" }, intent_of(let_go(input, "switch"), "draw"))
  end)

  it("opens the binder on select under a raised bar, and does nothing on select alone", function()
    local input = build()
    assert.same({}, hold(input, "select"))
    let_go(input, "select")
    hold(input, "left")
    assert.same({ type = "shortcut", verb = "edit" }, intent_of(hold(input, "select"), "shortcut"))
  end)

  it("leaves edit mode on select alone, as the Select key does", function()
    local input = build({ edit_mode = true })
    assert.same({ type = "shortcut", verb = "edit" }, intent_of(hold(input, "select"), "shortcut"))
  end)

  it("starts with no hold state", function()
    local input = build()
    assert.equal("none", input.hold_state())
  end)

  it("raises the right side while its behaviour is held", function()
    local input = build()
    assert.equal("xhb_right", state_of(hold(input, "right")))
    assert.equal("xhb_right", input.hold_state())
  end)

  it("raises a WXHB half whichever of the side and the layer went down first", function()
    local input = build()
    hold(input, "layer")
    assert.equal("wxhb_left", state_of(hold(input, "left")))
  end)

  it("raises nothing for the layer alone", function()
    local input = build()
    assert.is_nil(state_of(hold(input, "layer")))
    assert.equal("none", input.hold_state())
  end)

  describe("expanded pair", function()
    it("falls back to the survivor's side on a let-go, and re-ranks on a re-press", function()
      local input = build()
      hold(input, "left")
      hold(input, "right")
      assert.equal("xhb_right", state_of(let_go(input, "left")))
      assert.equal("expanded_rl", state_of(hold(input, "left")))
      assert.equal("xhb_left", state_of(let_go(input, "right")))
    end)

    it("ignores the layer over an expanded pair", function()
      local input = build()
      hold(input, "left")
      hold(input, "right")
      assert.is_nil(state_of(hold(input, "layer")))
      assert.equal("expanded_lr", input.hold_state())
      assert.is_nil(state_of(let_go(input, "layer")))
    end)

    it("falls back to the WXHB half when the layer is held under Expanded", function()
      local input = build()
      hold(input, "left")
      hold(input, "right")
      hold(input, "layer")
      assert.equal("wxhb_left", state_of(let_go(input, "right")))
    end)
  end)

  describe("held-set resolution", function()
    local names = { [39] = "left", [40] = "right", [43] = "layer", [41] = "switch" }
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
      local held_names = {}
      for _, dik in ipairs(case.held) do
        held_names[#held_names + 1] = names[dik]
      end
      it("resolves holding {" .. table.concat(held_names, ",") .. "} to " .. case.state, function()
        local input = build()
        for _, name in ipairs(held_names) do
          hold(input, name)
        end
        assert.equal(case.state, input.hold_state())
      end)
    end
  end)

  describe("slot behaviours", function()
    it("fires under every raised bar", function()
      local raised = {
        { "left" },
        { "right" },
        { "left", "layer" },
        { "right", "layer" },
        { "left", "right" },
        { "right", "left" },
      }
      for _, names in ipairs(raised) do
        local input = build()
        for _, name in ipairs(names) do
          hold(input, name)
        end
        assert.same({ type = "fire", slot = 1 }, intent_of(hold(input, "slot1"), "fire"), table.concat(names, ","))
      end
    end)

    it("fires nothing for the layer alone", function()
      local input = build()
      hold(input, "layer")
      assert.is_nil(intent_of(hold(input, "slot3"), "fire"))
    end)

    it("fires again on a fresh press of the slot", function()
      local input = build()
      hold(input, "left")
      hold(input, "slot3")
      let_go(input, "slot3")
      assert.same({ type = "fire", slot = 3 }, intent_of(hold(input, "slot3"), "fire"))
    end)
  end)

  describe("chat guard", function()
    it("fires no actions while chat is open", function()
      local input, state = build()
      hold(input, "left")
      state.chat_open = true
      assert.is_nil(intent_of(hold(input, "slot3"), "fire"))
      let_go(input, "slot3")
      hold(input, "switch")
      assert.is_nil(intent_of(let_go(input, "switch"), "cycle"))
      assert.is_nil(intent_of(hold(input, "select"), "shortcut"))
      assert.is_nil(intent_of(hold(input, "binder"), "shortcut"))
    end)

    it("passes the lowering so a let-go mid-chat cannot strand the bar", function()
      local input, state = build()
      hold(input, "left")
      state.chat_open = true
      assert.same({ type = "activate", state = "none" }, intent_of(let_go(input, "left"), "activate"))
      assert.equal("none", input.hold_state())
    end)

    it("keeps tracking a side held through chat", function()
      local input, state = build()
      state.chat_open = true
      hold(input, "left")
      state.chat_open = false
      assert.same({ type = "fire", slot = 3 }, intent_of(hold(input, "slot3"), "fire"))
    end)

    it("clears a slot's down-state on a let-go during chat", function()
      local input, state = build()
      hold(input, "left")
      hold(input, "slot3")
      state.chat_open = true
      let_go(input, "slot3")
      state.chat_open = false
      assert.same({ type = "fire", slot = 3 }, intent_of(hold(input, "slot3"), "fire"))
    end)

    it("tracks a slot pressed during chat so it cannot fire as a repeat after", function()
      local input, state = build()
      hold(input, "left")
      state.chat_open = true
      hold(input, "slot3")
      state.chat_open = false
      assert.is_nil(intent_of(hold(input, "slot3"), "fire"))
    end)

    it("suppresses jump and draw too", function()
      local input, state = build()
      state.chat_open = true
      hold(input, "switch")
      assert.is_nil(intent_of(hold(input, "slot3"), "jump"))
      let_go(input, "slot3")
      let_go(input, "switch")
      hold(input, "layer")
      hold(input, "switch")
      assert.is_nil(intent_of(let_go(input, "switch"), "draw"))
    end)
  end)

  describe("focus guard", function()
    it("lowers the bar and reports the drop", function()
      local input = build()
      hold(input, "left")
      hold(input, "layer")
      assert.same({ type = "activate", state = "none" }, intent_of(input.focus_lost(), "activate"))
      assert.equal("none", input.hold_state())
    end)

    it("reports nothing when nothing was raised", function()
      local input = build()
      assert.same({}, input.focus_lost())
    end)

    it("reads the next press of a formerly held behaviour as fresh", function()
      local input = build()
      hold(input, "left")
      hold(input, "slot3")
      input.focus_lost()
      hold(input, "left")
      assert.same({ type = "fire", slot = 3 }, intent_of(hold(input, "slot3"), "fire"))
    end)

    it("forgets a switch hold, so its later let-go does not cycle", function()
      local input = build()
      hold(input, "switch")
      input.focus_lost()
      assert.is_nil(intent_of(let_go(input, "switch"), "cycle"))
    end)
  end)

  describe("suppression guard", function()
    it("fires nothing while suppressed", function()
      local input, state = build()
      state.suppressed = true
      hold(input, "left")
      assert.is_nil(intent_of(hold(input, "slot3"), "fire"))
      let_go(input, "slot3")
      let_go(input, "left")
      hold(input, "switch")
      assert.is_nil(intent_of(let_go(input, "switch"), "cycle"))
      assert.is_nil(intent_of(hold(input, "binder"), "shortcut"))
    end)

    it("tracks the bar across suppression without stranding a side", function()
      local input, state = build()
      hold(input, "left")
      state.suppressed = true
      assert.same({ type = "activate", state = "none" }, intent_of(let_go(input, "left"), "activate"))
      state.suppressed = false
      assert.equal("none", input.hold_state())
    end)

    it("keeps a side raised during suppression usable once it lifts", function()
      local input, state = build()
      state.suppressed = true
      hold(input, "left")
      state.suppressed = false
      assert.same({ type = "fire", slot = 3 }, intent_of(hold(input, "slot3"), "fire"))
    end)
  end)

  describe("disabled", function()
    it("keeps tracking the bar for re-enabling mid-hold", function()
      local input, state = build()
      state.disabled = true
      hold(input, "left")
      state.disabled = false
      assert.same({ type = "fire", slot = 3 }, intent_of(hold(input, "slot3"), "fire"))
    end)
  end)

  describe("edit mode guard", function()
    it("gives the layer over the switch neither a draw nor a cycle", function()
      local input = build({ edit_mode = true })
      hold(input, "layer")
      hold(input, "switch")
      local intents = let_go(input, "switch")
      assert.is_nil(intent_of(intents, "draw"))
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("still cycles on a tap of the switch", function()
      local input = build({ edit_mode = true })
      hold(input, "switch")
      assert.same({ type = "cycle" }, intent_of(let_go(input, "switch"), "cycle"))
    end)

    it("still jumps with a side held, edit mode's own entry state", function()
      local input = build({ edit_mode = true })
      hold(input, "left")
      hold(input, "switch")
      assert.same({ type = "jump", set = 3 }, intent_of(hold(input, "slot3"), "jump"))
    end)

    it("fires nothing from a side or a bare slot", function()
      local input = build({ edit_mode = true })
      assert.is_nil(intent_of(hold(input, "slot3"), "fire"))
      assert.is_nil(intent_of(hold(input, "slot3"), "jump"))
      let_go(input, "slot3")
      hold(input, "left")
      assert.is_nil(intent_of(hold(input, "slot3"), "fire"))
    end)

    it("still tracks the bar, activate included", function()
      local input, state = build({ edit_mode = true })
      assert.equal("xhb_left", state_of(hold(input, "left")))
      state.edit_mode = false
      assert.same({ type = "fire", slot = 3 }, intent_of(hold(input, "slot3"), "fire"))
    end)

    it("keeps select live under a raised side", function()
      local input = build({ edit_mode = true })
      hold(input, "left")
      assert.same({ type = "shortcut", verb = "edit" }, intent_of(hold(input, "select"), "shortcut"))
    end)
  end)

  describe("layout mode", function()
    it("fires nothing, cycles nothing and opens no binder shortcut from select", function()
      local input = build({ layout_mode = true })
      hold(input, "left")
      assert.is_nil(intent_of(hold(input, "slot3"), "fire"))
      let_go(input, "slot3")
      let_go(input, "left")
      hold(input, "switch")
      assert.is_nil(intent_of(let_go(input, "switch"), "cycle"))
      hold(input, "left")
      assert.is_nil(intent_of(hold(input, "select"), "shortcut"))
    end)

    it("still raises and lowers the bar, as suppression does", function()
      local input = build({ layout_mode = true })
      assert.equal("xhb_left", state_of(hold(input, "left")))
      assert.equal("none", state_of(let_go(input, "left")))
    end)

    it("tracks the bar across the transition", function()
      local input, state = build()
      hold(input, "left")
      state.layout_mode = true
      assert.same({ type = "activate", state = "none" }, intent_of(let_go(input, "left"), "activate"))
    end)
  end)

  describe("shortcut behaviours", function()
    it("fires the chorded verb under an expanded pair too", function()
      local input = build()
      hold(input, "right")
      hold(input, "left")
      assert.same({ type = "shortcut", verb = "edit" }, intent_of(hold(input, "select"), "shortcut"))
    end)

    it("counts neither the layer nor the switch as a chord", function()
      local input = build()
      hold(input, "layer")
      assert.is_nil(intent_of(hold(input, "select"), "shortcut"))
      let_go(input, "select")
      let_go(input, "layer")
      hold(input, "switch")
      assert.is_nil(intent_of(hold(input, "select"), "shortcut"))
    end)

    it("fires nothing on a let-go of the binder", function()
      local input = build()
      hold(input, "binder")
      assert.is_nil(intent_of(let_go(input, "binder"), "shortcut"))
    end)
  end)

  describe("the switch", function()
    it("emits nothing on its own press", function()
      local input = build()
      assert.same({}, hold(input, "switch"))
    end)

    it("jumps even while the layer is held", function()
      local input = build()
      hold(input, "layer")
      hold(input, "switch")
      assert.same({ type = "jump", set = 1 }, intent_of(hold(input, "slot1"), "jump"))
    end)

    it("draws when tapped with the layer held, and does not cycle", function()
      local input = build()
      hold(input, "layer")
      hold(input, "switch")
      local intents = let_go(input, "switch")
      assert.same({ type = "draw" }, intent_of(intents, "draw"))
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("draws when the layer comes down after the switch", function()
      local input = build()
      hold(input, "switch")
      hold(input, "layer")
      local intents = let_go(input, "switch")
      assert.same({ type = "draw" }, intent_of(intents, "draw"))
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("cycles, not draws, once the layer is let go before the tap ends", function()
      local input = build()
      hold(input, "layer")
      hold(input, "switch")
      let_go(input, "layer")
      local intents = let_go(input, "switch")
      assert.same({ type = "cycle" }, intent_of(intents, "cycle"))
      assert.is_nil(intent_of(intents, "draw"))
    end)

    it("neither draws nor cycles when a slot was chorded during the hold", function()
      local input = build()
      hold(input, "layer")
      hold(input, "switch")
      hold(input, "slot1")
      let_go(input, "slot1")
      local intents = let_go(input, "switch")
      assert.is_nil(intent_of(intents, "draw"))
      assert.is_nil(intent_of(intents, "cycle"))
    end)

    it("is inert while a side is held", function()
      local input = build()
      hold(input, "left")
      hold(input, "switch")
      assert.same({}, let_go(input, "switch"))
    end)

    it("stays inert when the side is let go before the switch", function()
      local input = build()
      hold(input, "left")
      hold(input, "switch")
      let_go(input, "left")
      local intents = let_go(input, "switch")
      assert.is_nil(intent_of(intents, "cycle"))
      assert.is_nil(intent_of(intents, "draw"))
    end)

    it("goes inert when a side comes down mid-hold", function()
      local input = build()
      hold(input, "switch")
      hold(input, "left")
      let_go(input, "left")
      assert.is_nil(intent_of(let_go(input, "switch"), "cycle"))
    end)

    it("still jumps after a side overlap once the side is back up, but neither cycles nor draws", function()
      local input = build()
      hold(input, "switch")
      hold(input, "left")
      let_go(input, "left")
      assert.same({ type = "jump", set = 3 }, intent_of(hold(input, "slot3"), "jump"))
      let_go(input, "slot3")
      local intents = let_go(input, "switch")
      assert.is_nil(intent_of(intents, "cycle"))
      assert.is_nil(intent_of(intents, "draw"))
    end)

    it("lets a slot fire rather than jump while a side is held", function()
      local input = build()
      hold(input, "left")
      hold(input, "switch")
      local intents = hold(input, "slot6")
      assert.same({ type = "fire", slot = 6 }, intent_of(intents, "fire"))
      assert.is_nil(intent_of(intents, "jump"))
    end)

    it("still cycles over a slot held from before the switch", function()
      local input = build()
      hold(input, "slot1")
      hold(input, "switch")
      assert.same({ type = "cycle" }, intent_of(let_go(input, "switch"), "cycle"))
    end)

    it("cycles again on a fresh tap after a chorded hold", function()
      local input = build()
      hold(input, "switch")
      hold(input, "slot1")
      let_go(input, "slot1")
      let_go(input, "switch")
      hold(input, "switch")
      assert.same({ type = "cycle" }, intent_of(let_go(input, "switch"), "cycle"))
    end)
  end)

  --[[ The keyboard map's question: whether the key a press came from is the
       bar's to keep from the game, by the rules the bar's own keys keep. ]]
  describe("the key a press came from", function()
    local function kept(input, name)
      local _, block = input.on_behavior(name, true)
      return block
    end

    it("is the bar's for a side, the layer, the switch and select, whatever is raised", function()
      for _, name in ipairs({ "left", "right", "layer", "switch", "select" }) do
        assert.is_true(kept(build(), name), name)
      end
    end)

    it("is the bar's for select chorded with a side", function()
      local input = build()
      hold(input, "left")
      assert.is_true(kept(input, "select"))
    end)

    it("is the bar's for a slot only while a bar is raised or the switch held", function()
      local input = build()
      assert.is_false(kept(input, "slot1"))
      let_go(input, "slot1")
      hold(input, "left")
      assert.is_true(kept(input, "slot1"))
      input = build()
      hold(input, "switch")
      assert.is_true(kept(input, "slot2"))
    end)

    it("is the game's while disabled or with the chat line open", function()
      for _, guard in ipairs({ "disabled", "chat_open" }) do
        assert.is_false(kept(build({ [guard] = true }), "left"), guard)
      end
    end)

    it("is the bar's for its dedicated keys but never a slot while suppressed or laying out", function()
      for _, guard in ipairs({ "suppressed", "layout_mode" }) do
        local input = build({ [guard] = true })
        assert.is_true(kept(input, "left"), guard)
        assert.is_false(kept(input, "slot1"), guard)
      end
    end)

    it("is the bar's for a slot in edit mode only over the held switch", function()
      local input = build({ edit_mode = true })
      hold(input, "left")
      assert.is_false(kept(input, "slot1"))
      let_go(input, "slot1")
      hold(input, "switch")
      assert.is_true(kept(input, "slot2"))
    end)

    it("is nothing on a let-go", function()
      local input = build()
      hold(input, "left")
      local _, block = input.on_behavior("left", false)
      assert.is_false(block)
    end)
  end)
end)
