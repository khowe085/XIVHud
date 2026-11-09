local new_gamepad = require("lib/gamepad")

-- XInput's wButtons bits.
local UP, DOWN, LEFT, RIGHT = 0x0001, 0x0002, 0x0004, 0x0008
local START, BACK, L3, R3 = 0x0010, 0x0020, 0x0040, 0x0080
local LB, RB = 0x0100, 0x0200
local A, B, X, Y = 0x1000, 0x2000, 0x4000, 0x8000

describe("gamepad", function()
  local pads, reads, clock, config, pad

  local function state(buttons, left_trigger, right_trigger)
    return { buttons = buttons or 0, left_trigger = left_trigger or 0, right_trigger = right_trigger or 0 }
  end

  -- A switched-on config carrying `overrides`.
  local function on(overrides)
    local settings = { enabled = true }
    for key, value in pairs(overrides or {}) do
      settings[key] = value
    end
    return settings
  end

  local function build(overrides)
    overrides = overrides or {}
    local deps = {
      read = function(index)
        reads[#reads + 1] = index
        return pads[index]
      end,
      now = function()
        return clock
      end,
      config = function()
        return config
      end,
    }
    for key, value in pairs(overrides) do
      deps[key] = value
    end
    return new_gamepad(deps)
  end

  before_each(function()
    pads, reads, clock, config = {}, {}, 0, on()
    pad = build()
  end)

  local function edges(list)
    local out = {}
    for _, edge in ipairs(list) do
      out[#out + 1] = { edge.behavior, edge.down }
    end
    return out
  end

  -- lib/behaviors' answer: a component's own behaviour is `<component>.<name>`.
  local function component_named(value)
    return type(value) == "string" and value:find(".", 1, true) ~= nil
  end

  -- Polls, a second apart, until the probe reaches the pad in `index`.
  local function connect(index, s)
    pads[index] = s or state()
    for _ = 1, 4 do
      clock = clock + 1
      reads = {}
      pad.poll()
      if reads[#reads] == index then
        break
      end
    end
    reads = {}
  end

  describe("finding a pad", function()
    it("probes one slot at a time, from the first, and answers no edges", function()
      assert.are.same({}, pad.poll())
      assert.are.same({ 0 }, reads)
    end)

    it("probes the next slot at most once a second while nothing answers, round and round", function()
      pad.poll()
      clock = 0.5
      pad.poll()
      assert.are.same({ 0 }, reads, "not again inside the second")
      for second = 1, 4 do
        clock = second
        pad.poll()
      end
      assert.are.same({ 0, 1, 2, 3, 0 }, reads)
    end)

    it("reads only the slot that answered, every frame", function()
      connect(2)
      pad.poll()
      pad.poll()
      assert.are.same({ 2, 2 }, reads)
    end)

    it("takes the first slot its probe reaches", function()
      pads[1], pads[3] = state(), state()
      pad.poll()
      clock = 1
      pad.poll()
      reads = {}
      pad.poll()
      assert.are.same({ 1 }, reads)
    end)

    it("does nothing at all without a reader", function()
      pad = build({ read = false })
      assert.are.same({}, pad.poll())
      assert.is_false(pad.available())
    end)

    it("is available with a reader, pad or no pad", function()
      assert.is_true(pad.available())
    end)
  end)

  describe("the shipped map", function()
    before_each(function()
      pad = build({ is_component = component_named })
      connect(0)
    end)

    -- Presses `buttons` alone and answers what came of it, letting go after.
    local function press(buttons, left_trigger, right_trigger)
      pads[0] = state(buttons, left_trigger, right_trigger)
      local got = edges(pad.poll())
      pads[0] = state()
      pad.poll()
      return got
    end

    it("answers a button's behaviour on its edges, once each", function()
      pads[0] = state(A)
      assert.are.same({ { "accept", true } }, edges(pad.poll()))
      assert.are.same({}, edges(pad.poll()))
      pads[0] = state()
      assert.are.same({ { "accept", false } }, edges(pad.poll()))
    end)

    it("gives the face buttons, the bumpers, Back, Start and the sticks their behaviours", function()
      assert.are.same({ { "accept", true } }, press(A))
      assert.are.same({ { "cancel", true } }, press(B))
      assert.are.same({ { "cycle_window", true } }, press(X))
      assert.are.same({ { "lockon", true } }, press(Y))
      assert.are.same({ { "crossbar.switch", true } }, press(RB))
      assert.are.same({ { "open_map", true } }, press(BACK))
      assert.are.same({ { "main_menu", true } }, press(START))
      assert.are.same({ { "target_self", true } }, press(L3))
      assert.are.same({ { "target_npc", true } }, press(R3))
    end)

    it("holds the crossbar's sides on the triggers", function()
      assert.are.same({ { "crossbar.left", true } }, press(0, 255, 0))
      assert.are.same({ { "crossbar.right", true } }, press(0, 0, 255))
    end)

    it("leaves the D-pad alone unmapped", function()
      assert.are.same({}, press(UP + RIGHT + DOWN + LEFT))
    end)

    it("fires slots 1-8 with a face or D-pad button under LT", function()
      local slots = { Y, B, A, X, UP, RIGHT, DOWN, LEFT }
      for slot, button in ipairs(slots) do
        assert.are.same(
          { { "crossbar.left", true }, { "crossbar.slot" .. slot, true } },
          press(button, 255, 0),
          "slot " .. slot
        )
      end
    end)

    it("fires them under RT and RB as well", function()
      assert.are.same({ { "crossbar.right", true }, { "crossbar.slot3", true } }, press(A, 0, 255))
      assert.are.same({ { "crossbar.switch", true }, { "crossbar.slot8", true } }, press(RB + LEFT))
    end)

    it("raises WXHB with a trigger and its own bumper", function()
      assert.are.same({ { "crossbar.left", true }, { "crossbar.wxhb_left", true } }, press(LB, 255, 0))
      assert.are.same({ { "crossbar.right", true }, { "crossbar.wxhb_right", true } }, press(RB, 0, 255))
    end)

    it("keeps WXHB right up when LB, held over from WXHB left, lets go", function()
      pads[0] = state(LB, 255, 0)
      pad.poll()
      pads[0] = state(LB)
      pad.poll()
      pads[0] = state(LB, 0, 255)
      pad.poll()
      pads[0] = state(LB + RB, 0, 255)
      assert.are.same({ { "crossbar.wxhb_right", true } }, edges(pad.poll()))
      pads[0] = state(RB, 0, 255)
      assert.are.same({}, edges(pad.poll()))
    end)

    it("reads LB+RB as the draw chord once the trigger that raised WXHB has let go", function()
      pads[0] = state(LB, 255, 0)
      pad.poll()
      pads[0] = state(LB)
      pad.poll()
      pads[0] = state(LB + RB)
      assert.are.same({ { "crossbar.draw", true } }, edges(pad.poll()))
    end)

    it("reads RB under both triggers as the draw chord, LB having gone down after RT", function()
      pads[0] = state(LB, 255, 255)
      pad.poll()
      pads[0] = state(LB + RB, 255, 255)
      assert.are.same({ { "crossbar.draw", true } }, edges(pad.poll()))
    end)

    it("reads the other bumper under a raised WXHB half as the draw chord", function()
      pads[0] = state(LB, 255, 0)
      pad.poll()
      pads[0] = state(LB + RB, 255, 0)
      assert.are.same({ { "crossbar.draw", true } }, edges(pad.poll()))
    end)

    it("lowers WXHB with its trigger, the bumper still held", function()
      pads[0] = state(LB, 255, 0)
      pad.poll()
      pads[0] = state(LB)
      assert.are.same({ { "crossbar.left", false }, { "crossbar.wxhb_left", false } }, edges(pad.poll()))
    end)

    it("opens the binder with Start under either trigger", function()
      assert.are.same({ { "crossbar.left", true }, { "crossbar.binder", true } }, press(START, 255, 0))
      assert.are.same({ { "crossbar.right", true }, { "crossbar.binder", true } }, press(START, 0, 255))
    end)

    it("draws with LB pressed over the held set switch", function()
      pads[0] = state(RB)
      assert.are.same({ { "crossbar.switch", true } }, edges(pad.poll()))
      pads[0] = state(RB + LB)
      assert.are.same({ { "crossbar.draw", true } }, edges(pad.poll()))
    end)

    it("draws with RB pressed over a held LB, which then autoruns at no release", function()
      pads[0] = state(LB)
      assert.are.same({}, edges(pad.poll()))
      pads[0] = state(LB + RB)
      assert.are.same({ { "crossbar.draw", true } }, edges(pad.poll()))
      clock = clock + 0.05
      pads[0] = state()
      assert.are.same({ { "crossbar.draw", false } }, edges(pad.poll()))
      assert.are.same({}, edges(pad.poll()))
    end)

    it("reads both bumpers pressed in one frame as LB first, and so as the draw alone", function()
      assert.are.same({ { "crossbar.draw", true } }, press(LB + RB))
      assert.are.same({}, edges(pad.poll()))
    end)

    it("autoruns on a tap of LB, at its release, and lets R go at the next poll", function()
      pads[0] = state(LB)
      assert.are.same({}, edges(pad.poll()), "nothing at the press")
      clock = clock + 0.1
      pads[0] = state()
      assert.are.same({ { "autorun", true } }, edges(pad.poll()))
      assert.are.same({ { "autorun", false } }, edges(pad.poll()))
      assert.are.same({}, edges(pad.poll()))
    end)

    it("autoruns on nothing for LB held a quarter of a second", function()
      pads[0] = state(LB)
      pad.poll()
      clock = clock + 0.25
      pads[0] = state()
      assert.are.same({}, edges(pad.poll()))
      assert.are.same({}, edges(pad.poll()))
    end)

    it("autoruns on a tap across a press that built no chord on LB", function()
      pads[0] = state(LB)
      pad.poll()
      pads[0] = state(LB + A)
      assert.are.same({ { "accept", true } }, edges(pad.poll()))
      clock = clock + 0.1
      pads[0] = state(A)
      assert.are.same({ { "autorun", true } }, edges(pad.poll()))
    end)

    it("reads the tap window from the config", function()
      config = on({ tap_seconds = 0.5 })
      pads[0] = state(LB)
      pad.poll()
      clock = clock + 0.4
      pads[0] = state()
      assert.are.same({ { "autorun", true } }, edges(pad.poll()))
    end)

    it("takes a quarter of a second for a tap window that is no positive number", function()
      for _, broken in ipairs({ 0, -1 }) do
        config = on({ tap_seconds = broken })
        pads[0] = state(LB)
        pad.poll()
        clock = clock + 0.2
        pads[0] = state()
        assert.are.same({ { "autorun", true } }, edges(pad.poll()), tostring(broken))
        pad.poll()
      end
      config = on({ tap_seconds = "0.5" })
      pads[0] = state(LB)
      pad.poll()
      clock = clock + 0.3
      pads[0] = state()
      assert.are.same({}, edges(pad.poll()), "a string is not read as a number")
    end)

    it("presses both triggers in one frame left first", function()
      assert.are.same({ { "crossbar.left", true }, { "crossbar.right", true } }, press(0, 255, 255))
    end)

    it("releases before it presses inside one frame", function()
      pads[0] = state(A)
      pad.poll()
      pads[0] = state(B)
      assert.are.same({ { "accept", false }, { "cancel", true } }, edges(pad.poll()))
    end)

    it("presses a trigger only past the threshold", function()
      pads[0] = state(0, 30, 0)
      assert.are.same({}, pad.poll())
      pads[0] = state(0, 31, 0)
      assert.are.same({ { "crossbar.left", true } }, edges(pad.poll()))
    end)

    it("lets a trigger go only well under the threshold, so one resting there cannot flicker", function()
      pads[0] = state(0, 31, 0)
      pad.poll()
      pads[0] = state(0, 21, 0)
      assert.are.same({}, pad.poll())
      pads[0] = state(0, 20, 0)
      assert.are.same({ { "crossbar.left", false } }, edges(pad.poll()))
      pads[0] = state(0, 30, 0)
      assert.are.same({}, pad.poll(), "and takes the full threshold to press again")
    end)
  end)

  describe("resolving a press", function()
    local function map(entries)
      config = on({ map = entries })
      connect(0)
    end

    it("takes the gesture naming the most held buttons", function()
      map({ y = "one", ["lt+y"] = "two", ["lt+lb+y"] = "three" })
      pads[0] = state(Y)
      assert.are.same({ { "one", true } }, edges(pad.poll()))
      pads[0] = state(0, 255, 0)
      assert.are.same({ { "one", false } }, edges(pad.poll()), "LT has no behaviour of its own here")
      pads[0] = state(Y, 255, 0)
      assert.are.same({ { "two", true } }, edges(pad.poll()))
      pads[0] = state(LB, 255, 0)
      assert.are.same({ { "two", false } }, edges(pad.poll()))
      pads[0] = state(LB + Y, 255, 0)
      assert.are.same({ { "three", true } }, edges(pad.poll()))
    end)

    it("lets a chord go as soon as any of its buttons does", function()
      map({ lt = "side", ["lt+y"] = "slot", y = "bare" })
      pads[0] = state(Y, 255, 0)
      assert.are.same({ { "side", true }, { "slot", true } }, edges(pad.poll()))
      pads[0] = state(Y)
      assert.are.same({ { "side", false }, { "slot", false } }, edges(pad.poll()))
    end)

    it("leaves the trigger of a broken chord holding nothing until it is pressed again", function()
      map({ lt = "side", ["lt+y"] = "slot", y = "bare" })
      pads[0] = state(Y, 255, 0)
      pad.poll()
      pads[0] = state(Y)
      pad.poll()
      pads[0] = state()
      assert.are.same({}, pad.poll(), "its own release lets go of nothing")
      pads[0] = state(Y)
      assert.are.same({ { "bare", true } }, edges(pad.poll()))
    end)

    it("lets a broken chord go cancelled when the pad is lost", function()
      map({ lt = "side", ["lt+y"] = "slot" })
      pads[0] = state(Y, 255, 0)
      pad.poll()
      pads[0] = nil
      local got = pad.poll()
      assert.are.same({ { "side", false }, { "slot", false } }, edges(got))
      assert.is_true(got[2].cancelled)
    end)

    it("lets a chord a named key holds go with the key", function()
      config = on({ extra = { l4 = 100 }, map = { ["l4+y"] = "named" } })
      connect(0)
      pad.on_key(100, true)
      pad.poll()
      pads[0] = state(Y)
      assert.are.same({ { "named", true } }, edges(pad.poll()))
      pad.on_key(100, false)
      assert.are.same({ { "named", false } }, edges(pad.poll()))
    end)

    it("keeps a press bare that went down before its modifier", function()
      map({ lt = "side", ["lt+y"] = "slot", y = "bare" })
      pads[0] = state(Y)
      pad.poll()
      pads[0] = state(Y, 255, 0)
      assert.are.same({ { "side", true } }, edges(pad.poll()))
      pads[0] = state(0, 255, 0)
      assert.are.same({ { "bare", false } }, edges(pad.poll()))
    end)

    it("breaks a tie for the gesture whose newest button went down last", function()
      map({ ["lt+y"] = "left_y", ["rt+y"] = "right_y" })
      pads[0] = state(0, 255, 0)
      pad.poll()
      pads[0] = state(0, 255, 255)
      pad.poll()
      pads[0] = state(Y, 255, 255)
      assert.are.same({ { "right_y", true } }, edges(pad.poll()))
      pads[0] = state()
      pad.poll()
      pads[0] = state(0, 0, 255)
      pad.poll()
      pads[0] = state(0, 255, 255)
      pad.poll()
      pads[0] = state(Y, 255, 255)
      assert.are.same({ { "left_y", true } }, edges(pad.poll()))
    end)

    it("counts a held button with no behaviour of its own as a modifier", function()
      map({ ["start+y"] = "start_y" })
      pads[0] = state(START)
      assert.are.same({}, pad.poll())
      pads[0] = state(START + Y)
      assert.are.same({ { "start_y", true } }, edges(pad.poll()))
    end)

    it("reads a gesture in any case and spacing", function()
      map({ ["LT + Y"] = "slot" })
      pads[0] = state(0, 255, 0)
      pad.poll()
      pads[0] = state(Y, 255, 0)
      assert.are.same({ { "slot", true } }, edges(pad.poll()))
    end)

    it("skips a gesture set to false, or one naming no button, and keeps the rest", function()
      map({ a = false, ["lt+q"] = "bad", b = "cancel" })
      pads[0] = state(A + B)
      assert.are.same({ { "cancel", true } }, edges(pad.poll()))
    end)

    it("keeps the spelling of a gesture that comes first, a removal included", function()
      map({ ["LT+Y"] = false, ["lt+y"] = "slot", ["rb+lt+a"] = "kept", ["lt+rb+a"] = "first" })
      pads[0] = state(0, 255, 0)
      pad.poll()
      pads[0] = state(Y, 255, 0)
      assert.are.same({}, pad.poll(), "the removal comes first, its capitals sorting ahead")
      pads[0] = state(RB, 255, 0)
      pad.poll()
      pads[0] = state(RB + A, 255, 0)
      assert.are.same({ { "first", true } }, edges(pad.poll()))
    end)

    it("keeps the user's spelling over the shipped one, a trailing space included", function()
      map({ ["lt+y "] = "mine", ["lt+y"] = "shipped" })
      pads[0] = state(0, 255, 0)
      pad.poll()
      pads[0] = state(Y, 255, 0)
      assert.are.same({ { "mine", true } }, edges(pad.poll()))
    end)

    it("ignores a behaviour that is not a name", function()
      map({ a = 5 })
      pads[0] = state(A)
      assert.are.same({}, pad.poll())
    end)
  end)

  --[[ A button a chord holds as a modifier keeps its own game key or action
       for its release, as a tap, so the chord never sends that too. ]]
  describe("a chord's modifier", function()
    before_each(function()
      pad = build({ is_component = component_named })
      connect(0)
    end)

    local function tap(buttons)
      pads[0] = state(buttons)
      local pressed = edges(pad.poll())
      clock = clock + 0.1
      pads[0] = state()
      return pressed, edges(pad.poll())
    end

    it("keeps a game key or an action for its release on any button a chord leans on", function()
      local own = { type = "open", action = "map" }
      config = on({ map = { b = "cancel", ["b+a"] = "both", x = own, ["x+y"] = "xy" } })
      assert.are.same({ {}, { { "cancel", true } } }, { tap(B) })
      pad.poll()
      pads[0] = state(X)
      assert.are.same({}, pad.poll())
      clock = clock + 0.1
      pads[0] = state()
      assert.are.equal(own, pad.poll()[1].behavior)
    end)

    it("sends a chord's own key or action at the press, though a chord leans on its last button", function()
      config = on({ map = { lb = "autorun", ["lb+rb"] = "c.draw", ["rt+lb"] = "accept" } })
      pads[0] = state(0, 0, 255)
      pad.poll()
      pads[0] = state(LB, 0, 255)
      assert.are.same({ { "accept", true } }, edges(pad.poll()))
    end)

    it("sends a component's behaviour at the press, its component hearing the hold", function()
      config = on({ map = { lb = "c.hold", ["lb+a"] = "c.chord" } })
      pads[0] = state(LB)
      assert.are.same({ { "c.hold", true } }, edges(pad.poll()))
    end)

    it("sends at the press a button no chord holds as a modifier, its trigger or not", function()
      config = on({ map = { b = "cancel", ["a+b"] = "chord" } })
      pads[0] = state(B)
      assert.are.same({ { "cancel", true } }, edges(pad.poll()))
    end)

    it("keeps nothing back without a way to tell a component's behaviour", function()
      pad = build()
      connect(0)
      pads[0] = state(LB)
      assert.are.same({ { "autorun", true } }, edges(pad.poll()))
    end)

    it("drops a tap a release cancels, and one the lost pad ends", function()
      pads[0] = state(LB)
      pad.poll()
      assert.are.same({}, pad.release())
      pads[0] = state()
      assert.are.same({}, pad.poll())
      pads[0] = state(LB)
      pad.poll()
      pads[0] = nil
      assert.are.same({}, pad.poll())
    end)

    it("lets a tap's game key go, cancelled, when released before the next poll", function()
      tap(LB)
      local got = pad.release()
      assert.are.same({ { "autorun", false } }, edges(got))
      assert.is_true(got[1].cancelled)
      assert.are.same({}, pad.poll())
    end)

    it("lets a tap's game key go when switched off before the next poll", function()
      tap(LB)
      config = { enabled = false }
      assert.are.same({ { "autorun", false } }, edges(pad.poll()))
      assert.are.same({}, pad.poll())
    end)

    it("taps a named key a chord leans on, held for a poll when it came between two", function()
      config = on({ extra = { l4 = 100 }, map = { l4 = "accept", ["l4+y"] = "named" } })
      pad.poll()
      pad.on_key(100, true)
      pad.on_key(100, false)
      assert.are.same({}, edges(pad.poll()))
      assert.are.same({ { "accept", true } }, edges(pad.poll()))
      assert.are.same({ { "accept", false } }, edges(pad.poll()))
    end)
  end)

  --[[ The back buttons have no XInput name, so Steam types a key for each and
       `extra` names them. ]]
  describe("buttons XInput cannot see", function()
    before_each(function()
      config = on({
        extra = { l4 = 100 },
        map = {
          lt = "side",
          l4 = "wxhb",
          ["lt+l4"] = "side_wxhb",
          ["l4+y"] = "wxhb_y",
          y = "bare",
        },
      })
      connect(0)
    end)

    it("takes a named key's edges while on, and answers them at the next poll", function()
      assert.is_true(pad.on_key(100, true))
      assert.are.same({ { "wxhb", true } }, edges(pad.poll()))
      assert.is_true(pad.on_key(100, false))
      assert.are.same({ { "wxhb", false } }, edges(pad.poll()))
    end)

    it("leaves every other key alone", function()
      assert.is_false(pad.on_key(101, true))
      assert.are.same({}, pad.poll())
    end)

    it("leaves a named key alone while off", function()
      config.enabled = false
      assert.is_false(pad.on_key(100, true))
    end)

    it("takes the up of a down it took, switched off in between", function()
      pad.on_key(100, true)
      config.enabled = false
      assert.is_true(pad.on_key(100, false))
    end)

    it("leaves the up of a down it did not take", function()
      config.enabled = false
      pad.on_key(100, true)
      config.enabled = true
      assert.is_false(pad.on_key(100, false))
    end)

    it("leaves a named key alone without a reader", function()
      pad = build({ read = false })
      assert.is_false(pad.on_key(100, true))
    end)

    it("chords a named key like any button", function()
      pads[0] = state(0, 255, 0)
      pad.poll()
      pad.on_key(100, true)
      assert.are.same({ { "side_wxhb", true } }, edges(pad.poll()))
      pads[0] = state()
      pad.on_key(100, false)
      pad.poll()
      pad.on_key(100, true)
      pad.poll()
      pads[0] = state(Y)
      assert.are.same({ { "wxhb_y", true } }, edges(pad.poll()))
    end)

    it("reads LT and a named key pressed in one frame as LT first", function()
      pads[0] = state(0, 255, 0)
      pad.on_key(100, true)
      assert.are.same({ { "side", true }, { "side_wxhb", true } }, edges(pad.poll()))
    end)

    it("presses a named key before the face buttons in one frame", function()
      pads[0] = state(Y)
      pad.on_key(100, true)
      assert.are.same({ { "wxhb", true }, { "wxhb_y", true } }, edges(pad.poll()))
    end)

    it("does not miss a tap between two polls, and holds it for one", function()
      pad.on_key(100, true)
      pad.on_key(100, false)
      assert.are.same({ { "wxhb", true } }, edges(pad.poll()))
      assert.are.same({ { "wxhb", false } }, edges(pad.poll()))
    end)

    it("leaves a named key alone once polls have stopped", function()
      clock = clock + 2
      assert.is_false(pad.on_key(100, true))
    end)

    it("takes a held key's repeats and answers them once", function()
      pad.on_key(100, true)
      assert.is_true(pad.on_key(100, true))
      assert.are.same({ { "wxhb", true } }, edges(pad.poll()))
    end)

    it("lets go of a named key on release, and leaves the up that follows to the game", function()
      pad.on_key(100, true)
      pad.poll()
      assert.are.same({ { "wxhb", false } }, edges(pad.release()))
      assert.is_false(pad.on_key(100, false))
      assert.are.same({}, pad.poll())
    end)

    it("ignores a name that is an XInput button's, or a value that is no key", function()
      config = on({ extra = { lb = 100, l4 = "100", r4 = 0 }, map = { lb = "bumper", l4 = "x", r4 = "y" } })
      for _, dik in ipairs({ 100, 0 }) do
        assert.is_false(pad.on_key(dik, true), tostring(dik))
      end
    end)

    it("gives a key two names to the first in order", function()
      config = on({ extra = { r4 = 100, l4 = 100 }, map = { l4 = "first", r4 = "second" } })
      pad.on_key(100, true)
      assert.are.same({ { "first", true } }, edges(pad.poll()))
    end)
  end)

  describe("losing the pad", function()
    it("lets go of everything held, cancelled, and goes back to probing from the slot it lost", function()
      connect(1, state(A, 255, 0))
      pads[1] = nil
      local got = pad.poll()
      assert.are.same({ { "crossbar.left", false }, { "crossbar.slot3", false } }, edges(got))
      assert.is_true(got[1].cancelled)
      assert.is_true(got[2].cancelled)
      assert.are.same({ 1 }, reads, "nothing else is probed that frame")
      reads = {}
      pad.poll()
      assert.are.same({}, reads, "nor inside the next second")
      clock = clock + 1
      pad.poll()
      assert.are.same({ 1 }, reads)
    end)

    it("does not cancel a real release", function()
      connect(0, state(A))
      pads[0] = state()
      assert.is_nil(pad.poll()[1].cancelled)
    end)
  end)

  describe("release", function()
    it("answers the ups for everything held, cancelled, and nothing after", function()
      connect(0, state(A + LB))
      local got = pad.release()
      assert.are.same({ { "autorun", false }, { "accept", false } }, edges(got))
      assert.is_true(got[1].cancelled)
      assert.are.same({}, pad.release())
    end)

    it("presses again, on the next poll, what is still held", function()
      connect(0, state(A))
      pad.release()
      assert.are.same({ { "accept", true } }, edges(pad.poll()))
    end)
  end)

  describe("configuration", function()
    it("uses the shipped map where the config has none", function()
      connect(0)
      pads[0] = state(A)
      assert.are.same({ { "accept", true } }, edges(pad.poll()))
    end)

    it("uses the config's map as it stands, nothing filled in", function()
      config = on({ map = { a = "cancel" } })
      connect(0)
      pads[0] = state(A + B)
      assert.are.same({ { "cancel", true } }, edges(pad.poll()))
    end)

    it("reads the trigger threshold from the config", function()
      config = on({ trigger_threshold = 100 })
      connect(0)
      pads[0] = state(0, 100, 0)
      assert.are.same({}, pad.poll())
      pads[0] = state(0, 101, 0)
      assert.are.same({ { "crossbar.left", true } }, edges(pad.poll()))
    end)

    it("falls back to the default threshold for one out of range", function()
      config = on({ trigger_threshold = -1 })
      connect(0)
      pads[0] = state(0, 10, 0)
      assert.are.same({}, pad.poll())
    end)

    it("answers fresh defaults every time, switched off, with no named keys", function()
      local first = pad.config_defaults()
      first.map.a = "changed"
      local defaults = pad.config_defaults()
      assert.are.equal("accept", defaults.map.a)
      assert.is_false(defaults.enabled)
      assert.are.same({ l4 = false, l5 = false, r4 = false, r5 = false }, defaults.extra)
    end)

    it("ships a quarter-second tap window", function()
      assert.are.equal(0.25, pad.config_defaults().tap_seconds)
    end)

    it("ships a gesture for every slot under LT, RT and RB", function()
      local map = pad.config_defaults().map
      local count = 0
      for _ in pairs(map) do
        count = count + 1
      end
      assert.are.equal(42, count)
      assert.are.equal("crossbar.slot1", map["lt+y"])
      assert.are.equal("crossbar.slot7", map["rt+down"])
      assert.are.equal("crossbar.slot8", map["rb+left"])
    end)
  end)

  describe("switched off", function()
    it("neither reads nor answers", function()
      config = { enabled = false }
      pads[0] = state(A)
      assert.are.same({}, pad.poll())
      assert.are.same({}, reads)
    end)

    it("is off with no config at all", function()
      config = nil
      pads[0] = state(A)
      assert.are.same({}, pad.poll())
      assert.are.same({}, reads)
    end)

    it("lets go of what was held, cancelled, the frame it goes off", function()
      connect(0, state(A))
      config = { enabled = false }
      local got = pad.poll()
      assert.are.same({ { "accept", false } }, edges(got))
      assert.is_true(got[1].cancelled)
      assert.are.same({}, pad.poll())
    end)

    it("is off for anything but an explicit true", function()
      config = { enabled = "yes" }
      pads[0] = state(A)
      assert.are.same({}, pad.poll())
    end)

    it("says whether it is on the way poll reads it", function()
      assert.is_true(pad.enabled())
      config = { enabled = false }
      assert.is_false(pad.enabled())
      config = { enabled = "yes" }
      assert.is_false(pad.enabled())
    end)

    it("presses again, once back on, what is still held", function()
      connect(0, state(A + LB))
      config = { enabled = false }
      pad.poll()
      config = on()
      assert.are.same({ { "autorun", true }, { "accept", true } }, edges(pad.poll()))
    end)
  end)

  describe("status", function()
    it("names the pad it reads, counted from one", function()
      connect(2)
      assert.are.equal("gamepad: on - pad 3 connected", pad.status())
    end)

    it("says it is looking until every slot has been probed", function()
      pad.poll()
      assert.are.equal("gamepad: on - looking for a pad", pad.status())
      for second = 1, 3 do
        clock = second
        pad.poll()
      end
      assert.are.equal("gamepad: on - no pad connected", pad.status())
    end)

    it("says it is looking, not that there is no pad, when switched on and not yet polled", function()
      config = { enabled = false }
      pads[0] = state()
      pad.poll()
      config = on()
      assert.are.equal("gamepad: on - looking for a pad", pad.status())
      pad.poll()
      assert.are.equal("gamepad: on - pad 1 connected", pad.status())
    end)

    it("forgets the pad it was reading while switched off", function()
      connect(0)
      config = { enabled = false }
      pad.poll()
      pads[0] = nil
      config = on()
      assert.are.equal("gamepad: on - looking for a pad", pad.status())
    end)

    it("says when it is off", function()
      config = { enabled = false }
      assert.are.equal("gamepad: off", pad.status())
    end)

    it("says why there is no reader", function()
      pad = build({ read = false, unavailable = "_LuaXInput not loaded" })
      assert.are.equal("gamepad: unavailable - _LuaXInput not loaded", pad.status())
    end)
  end)

  describe("problems", function()
    local function check(value)
      if value == "nope" then
        return nil, "no behavior nope"
      end
      if type(value) == "table" and value.key == "enter;quit" then
        return nil, "enter;quit is not a key name"
      end
      return true
    end

    it("has none for the shipped map", function()
      pad = build({ check = check })
      assert.are.same({}, pad.problems())
    end)

    it("names each broken gesture once, in order", function()
      pad = build({ check = check })
      config = on({
        map = {
          ["lt+q"] = "slot",
          ["lt+lt"] = "slot",
          a = "nope",
          b = 5,
          x = false,
          y = { key = "enter;quit" },
        },
      })
      assert.are.same({
        "gamepad: a - no behavior nope",
        "gamepad: b - not a behavior",
        "gamepad: lt+lt - names lt twice",
        "gamepad: lt+q - no button q",
        "gamepad: y - enter;quit is not a key name",
      }, pad.problems())
    end)

    it("names two gestures that read the same", function()
      config = on({ map = { ["LT+Y"] = "one", ["lt+y"] = "two" } })
      assert.are.same({ "gamepad: LT+Y and lt+y - the same gesture" }, pad.problems())
    end)

    it("reads a gesture's modifiers in any order as one gesture", function()
      config = on({ map = { ["lt+rb+y"] = "one", ["rb+lt+y"] = "two" } })
      assert.are.same({ "gamepad: lt+rb+y and rb+lt+y - the same gesture" }, pad.problems())
    end)

    it("names a spelling that collides with one the map removes", function()
      config = on({ map = { ["LT+Y"] = false, ["lt+y"] = "slot" } })
      assert.are.same({ "gamepad: LT+Y and lt+y - the same gesture" }, pad.problems())
    end)

    it("names each broken extra key", function()
      config = on({ extra = { lb = 100, l4 = "100", r4 = 101, r5 = 101, L5 = 102 }, map = {} })
      assert.are.same({
        "gamepad: extra.L5 - a name is a plain lowercase word",
        "gamepad: extra.l4 - not a key number",
        "gamepad: extra.lb - an XInput button's name",
        "gamepad: extra.r4 and extra.r5 - both key 101",
      }, pad.problems())
    end)

    it("does not ask after behaviours it has no way to ask about", function()
      config = on({ map = { a = "nope" } })
      assert.are.same({}, pad.problems())
    end)
  end)

  describe("a gesture's own behaviour", function()
    it("goes out as the entry the map holds", function()
      local own = { key = "f" }
      config = on({ map = { a = own } })
      connect(0)
      pads[0] = state(A)
      local got = pad.poll()
      assert.are.equal(own, got[1].behavior)
      pads[0] = state()
      assert.are.equal(own, pad.poll()[1].behavior)
    end)
  end)

  describe("editing the map", function()
    local function map_copy()
      local copy = {}
      for gesture, value in pairs(config.map) do
        copy[gesture] = value
      end
      return copy
    end

    before_each(function()
      config = on({ map = pad.config_defaults().map, extra = { l4 = 100, l5 = false, r4 = false, r5 = false } })
    end)

    describe("bind", function()
      it("binds a gesture under its spelling, lowercased, and answers it", function()
        assert.are.equal("lt+l4", pad.bind("LT+L4", "accept"))
        assert.are.equal("accept", config.map["lt+l4"])
      end)

      it("replaces what the gesture held", function()
        pad.bind("a", { key = "f" })
        assert.are.same({ key = "f" }, config.map.a)
      end)

      it("keeps one gesture under one spelling", function()
        config.map["RB+LT+Y"] = "one"
        assert.are.equal("lt+rb+y", pad.bind("lt+rb+y", "two"))
        assert.are.equal("two", config.map["lt+rb+y"])
        assert.is_nil(config.map["RB+LT+Y"])
      end)

      it("takes effect at the next press", function()
        connect(0)
        pad.bind("a", "cancel")
        pads[0] = state(A)
        assert.are.same({ { "cancel", true } }, edges(pad.poll()))
      end)

      it("refuses a gesture it cannot read, and changes nothing", function()
        local before = map_copy()
        for _, case in ipairs({
          { "lt+lt", "names lt twice" },
          { "lt+", "an empty button" },
          { "", "an empty button" },
        }) do
          local spelling, why = pad.bind(case[1], "accept")
          assert.is_nil(spelling, case[1])
          assert.are.equal(case[2], why, case[1])
        end
        assert.are.same(before, config.map)
      end)

      it("names the button it does not know", function()
        local spelling, why, missing = pad.bind("lt+l5", "accept")
        assert.is_nil(spelling)
        assert.are.equal("no button l5", why)
        assert.are.equal("l5", missing)
        assert.is_nil(config.map["lt+l5"])
      end)

      it("gives a broken map a table of its own, the shipped one under the binding", function()
        config.map = "broken"
        pad.bind("a", "cancel")
        assert.are.equal("cancel", config.map.a)
        assert.are.equal("cancel", config.map.b)
        config = on()
        connect(0, state(A))
        assert.are.same({}, pad.poll())
        pads[0] = state()
        pad.poll()
        pads[0] = state(A)
        assert.are.same({ { "accept", true } }, edges(pad.poll()))
      end)
    end)

    describe("unbind", function()
      it("removes a gesture of the user's own", function()
        pad.bind("lt+l4", "accept")
        assert.are.equal("lt+l4", pad.unbind("lt+l4"))
        assert.is_nil(config.map["lt+l4"])
      end)

      it("writes false over a shipped gesture, which the merge would put back", function()
        assert.are.equal("a", pad.unbind("A"))
        assert.is_false(config.map.a)
      end)

      it("removes the gesture under every spelling", function()
        config.map["LT+Y"] = "one"
        pad.unbind("lt+y")
        assert.is_nil(config.map["LT+Y"])
        assert.is_false(config.map["lt+y"])
      end)

      it("says when the gesture is not bound", function()
        pad.unbind("a")
        for _, gesture in ipairs({ "a", "lt+rb+y" }) do
          local spelling, why = pad.unbind(gesture)
          assert.is_nil(spelling)
          assert.are.equal("not bound", why)
        end
      end)

      it("removes a gesture whose button has lost its key", function()
        config.map["lt+l5"] = "accept"
        assert.are.equal("lt+l5", pad.unbind("lt+l5"))
        assert.is_nil(config.map["lt+l5"])
      end)

      it("names a button it does not know in a gesture the map does not hold", function()
        local spelling, why, missing = pad.unbind("lt+q")
        assert.is_nil(spelling)
        assert.are.equal("no button q", why)
        assert.are.equal("q", missing)
      end)

      it("takes effect at the next press", function()
        connect(0)
        pad.unbind("a")
        pads[0] = state(A)
        assert.are.same({}, pad.poll())
      end)
    end)

    it("switches the bridge on and off", function()
      pad.set_enabled(false)
      assert.is_false(config.enabled)
      assert.is_false(pad.enabled())
      pad.set_enabled(true)
      assert.is_true(config.enabled)
    end)

    it("names the pad's buttons in the order it answers them", function()
      assert.are.same(
        { "lt", "rt", "lb", "rb", "back", "start", "l3", "r3", "y", "b", "a", "x", "up", "right", "down", "left" },
        pad.buttons()
      )
    end)

    it("lists every gesture and what it does, in order, removals left out", function()
      config.map = { b = "cancel", a = false, ["lt+y"] = { key = "f" }, back = "open_map" }
      assert.are.same({
        { gesture = "b", behavior = "cancel" },
        { gesture = "back", behavior = "open_map" },
        { gesture = "lt+y", behavior = { key = "f" } },
      }, pad.bindings())
    end)
  end)

  describe("naming keys", function()
    before_each(function()
      config =
        on({ map = { l4 = "accept", r4 = "cancel" }, extra = { l4 = false, l5 = false, r4 = false, r5 = false } })
    end)

    it("takes any plain name that is no pad button", function()
      assert.is_true(pad.learnable("l4"))
      assert.is_true(pad.learnable("lpad"))
    end)

    it("refuses a pad button and a name that is not a plain word", function()
      for _, case in ipairs({
        { "a", "a is a pad button" },
        { "lt", "lt is a pad button" },
        { "L4", "a name is a plain lowercase word" },
        { "l4+y", "a name is a plain lowercase word" },
      }) do
        local ok, why = pad.learnable(case[1])
        assert.is_nil(ok, case[1])
        assert.are.equal(case[2], why, case[1])
      end
    end)

    it("gives a name its key, which then reads as a button", function()
      connect(0)
      assert.is_nil(pad.set_key("l4", 100))
      assert.are.equal(100, config.extra.l4)
      assert.are.equal(100, pad.key_of("l4"))
      assert.is_true(pad.on_key(100, true))
      assert.are.same({ { "accept", true } }, edges(pad.poll()))
    end)

    it("moves a key another name has, and says which name lost it", function()
      config.extra.l4 = 100
      assert.are.equal("l4", pad.set_key("r4", 100))
      assert.is_false(config.extra.l4)
      assert.are.equal(100, config.extra.r4)
    end)

    it("drops a name of the user's own that loses its key", function()
      config.extra.lpad = 100
      assert.are.equal("lpad", pad.set_key("l4", 100))
      assert.is_nil(config.extra.lpad)
    end)

    it("clears a key with false", function()
      config.extra.l4, config.extra.lpad = 100, 101
      pad.set_key("l4", false)
      pad.set_key("lpad", false)
      assert.is_false(config.extra.l4)
      assert.is_nil(config.extra.lpad)
      assert.is_nil(pad.key_of("l4"))
    end)

    it("gives a broken extra a table of its own", function()
      config.extra = "broken"
      pad.set_key("l4", 100)
      assert.are.same({ l4 = 100, l5 = false, r4 = false, r5 = false }, config.extra)
    end)

    it("names the names with a key, in order, leaving out any that holds no key", function()
      config.extra = { r4 = 101, l4 = 100, l5 = false, lpad = "x", rpad = 101 }
      assert.are.same({ { name = "l4", key = 100 }, { name = "r4", key = 101 } }, pad.named_keys())
    end)

    it("knows no key for a name holding something else", function()
      config.extra.l4 = "100"
      assert.is_nil(pad.key_of("l4"))
      assert.is_nil(pad.key_of("nothing"))
    end)
  end)
end)
