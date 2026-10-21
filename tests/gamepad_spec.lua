local new_gamepad = require("lib/gamepad")

-- XInput's wButtons bits.
local UP, DOWN, LEFT, RIGHT = 0x0001, 0x0002, 0x0004, 0x0008
local START, BACK = 0x0010, 0x0020
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
      out[#out + 1] = { edge.dik, edge.down }
    end
    return out
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

  describe("buttons", function()
    before_each(function()
      connect(0)
    end)

    it("emits a press and a release once each, on the edges", function()
      pads[0] = state(A)
      assert.are.same({ { 4, true } }, edges(pad.poll()))
      assert.are.same({}, edges(pad.poll()))
      pads[0] = state()
      assert.are.same({ { 4, false } }, edges(pad.poll()))
    end)

    it("maps the face buttons to slots 1-4 and the D-pad to slots 5-8", function()
      pads[0] = state(Y + B + A + X + UP + RIGHT + DOWN + LEFT)
      local got = {}
      for _, edge in ipairs(pad.poll()) do
        got[edge.dik] = true
      end
      assert.are.same(
        { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true },
        got
      )
    end)

    it("maps LB to the WXHB layer, RB to the set switch and Back to Select", function()
      pads[0] = state(LB)
      assert.are.same({ { 43, true } }, edges(pad.poll()))
      pads[0] = state(RB)
      assert.are.same({ { 43, false }, { 41, true } }, edges(pad.poll()))
      pads[0] = state(BACK)
      assert.are.same({ { 41, false }, { 13, true } }, edges(pad.poll()))
    end)

    it("leaves Start unmapped", function()
      pads[0] = state(START)
      assert.are.same({}, pad.poll())
    end)

    it("presses a trigger only past the threshold", function()
      pads[0] = state(0, 30, 0)
      assert.are.same({}, pad.poll())
      pads[0] = state(0, 31, 0)
      assert.are.same({ { 39, true } }, edges(pad.poll()))
    end)

    it("lets a trigger go only well under the threshold, so one resting there cannot flicker", function()
      pads[0] = state(0, 31, 0)
      pad.poll()
      pads[0] = state(0, 21, 0)
      assert.are.same({}, pad.poll())
      pads[0] = state(0, 20, 0)
      assert.are.same({ { 39, false } }, edges(pad.poll()))
      pads[0] = state(0, 30, 0)
      assert.are.same({}, pad.poll(), "and takes the full threshold to press again")
    end)

    it("presses both triggers in one frame left first", function()
      pads[0] = state(0, 255, 255)
      assert.are.same({ { 39, true }, { 40, true } }, edges(pad.poll()))
    end)

    it("releases before it presses inside one frame", function()
      pads[0] = state(A)
      pad.poll()
      pads[0] = state(B)
      assert.are.same({ { 4, false }, { 3, true } }, edges(pad.poll()))
    end)
  end)

  describe("chords", function()
    before_each(function()
      connect(0)
    end)

    it("sends RB as the WXHB layer while RT is held", function()
      pads[0] = state(RB, 0, 255)
      assert.are.same({ { 40, true }, { 43, true } }, edges(pad.poll()))
    end)

    it("keeps the key a button went down with until it comes up", function()
      pads[0] = state(RB, 0, 255)
      pad.poll()
      pads[0] = state(RB)
      assert.are.same({ { 40, false } }, edges(pad.poll()))
      pads[0] = state()
      assert.are.same({ { 43, false } }, edges(pad.poll()))
    end)

    it("holds a key two buttons share until both are up", function()
      pads[0] = state(LB)
      pad.poll()
      pads[0] = state(LB + RB, 0, 255)
      assert.are.same({ { 40, true } }, edges(pad.poll()))
      pads[0] = state(RB, 0, 255)
      assert.are.same({}, edges(pad.poll()))
      pads[0] = state(0, 0, 255)
      assert.are.same({ { 43, false } }, edges(pad.poll()))
    end)
  end)

  --[[ A face button pressed with no side held is the game's: the bridge sends
       it a key of its own through `inject`, and the bars hear nothing. ]]
  describe("bare keys", function()
    local injected, keyboard

    before_each(function()
      injected, keyboard = {}, {}
      pad = build({
        inject = function(name, down)
          injected[#injected + 1] = { name, down }
        end,
        key_held = function(dik)
          return keyboard[dik] == true
        end,
      })
      connect(0)
    end)

    it("sends a bare A to the game as Enter, and nothing to the bars", function()
      pads[0] = state(A)
      assert.are.same({}, pad.poll())
      assert.are.same({ { "enter", true } }, injected)
      pads[0] = state()
      assert.are.same({}, pad.poll())
      assert.are.same({ { "enter", true }, { "enter", false } }, injected)
    end)

    it("sends B, X and Y as Escape, Numpad + and Numpad -", function()
      pads[0] = state(B + X + Y)
      pad.poll()
      assert.are.same({ { "numpad-", true }, { "escape", true }, { "numpad+", true } }, injected)
    end)

    it("sends a face button to the bars while a side is held, and nothing to the game", function()
      pads[0] = state(A, 255, 0)
      assert.are.same({ { 39, true }, { 4, true } }, edges(pad.poll()))
      assert.are.same({}, injected)
    end)

    it("counts the set switch as a side", function()
      pads[0] = state(RB + A)
      assert.are.same({ { 41, true }, { 4, true } }, edges(pad.poll()))
      assert.are.same({}, injected)
    end)

    it("counts a side held on the keyboard, as a paddle sends it", function()
      keyboard[39] = true
      pads[0] = state(A)
      assert.are.same({ { 4, true } }, edges(pad.poll()))
      assert.are.same({}, injected)
    end)

    it("presses bare a face button that comes down as the side goes up", function()
      pads[0] = state(0, 255, 0)
      pad.poll()
      pads[0] = state(A)
      assert.are.same({ { 39, false } }, edges(pad.poll()))
      assert.are.same({ { "enter", true } }, injected)
    end)

    it("keeps a press bare until it comes up, whatever is pressed after it", function()
      pads[0] = state(A)
      pad.poll()
      pads[0] = state(A, 255, 0)
      assert.are.same({ { 39, true } }, edges(pad.poll()))
      pads[0] = state(0, 255, 0)
      pad.poll()
      assert.are.same({ { "enter", true }, { "enter", false } }, injected)
    end)

    it("holds a game key two buttons share until both are up", function()
      config = on({ bare = { b = "enter" } })
      pads[0] = state(A + B)
      pad.poll()
      pads[0] = state(B)
      pad.poll()
      assert.are.same({ { "enter", true } }, injected)
      pads[0] = state()
      pad.poll()
      assert.are.same({ { "enter", true }, { "enter", false } }, injected)
    end)

    it("sends the D-pad to the bars bare, having no game key of its own", function()
      pads[0] = state(UP)
      assert.are.same({ { 6, true } }, edges(pad.poll()))
      assert.are.same({}, injected)
    end)

    it("lets the game key go when switched off", function()
      pads[0] = state(A)
      pad.poll()
      config = { enabled = false }
      pad.poll()
      assert.are.same({ { "enter", true }, { "enter", false } }, injected)
    end)

    it("lets the game key go when the pad is lost", function()
      pads[0] = state(A)
      pad.poll()
      pads[0] = nil
      pad.poll()
      assert.are.same({ { "enter", true }, { "enter", false } }, injected)
    end)

    it("reads the game keys and the sides from the config", function()
      config = on({ bare = { a = "f1" }, activators = { 43, false, false } })
      pads[0] = state(A)
      pad.poll()
      assert.are.same({ { "f1", true } }, injected)
      pads[0] = state(LB + B)
      assert.are.same({ { 43, true }, { 3, true } }, edges(pad.poll()), "LB is a side now")
      pads[0] = state(X, 255, 0)
      local got = edges(pad.poll())
      assert.are.same({ "numpad+", true }, injected[#injected], "and LT is not")
      assert.are.same({ 39, true }, got[#got])
    end)

    it("sends a button's own key bare when the config gives it no game key", function()
      config = on({ bare = { a = false } })
      pads[0] = state(A)
      assert.are.same({ { 4, true } }, edges(pad.poll()))
      assert.are.same({}, injected)
    end)

    it("refuses a game key that could carry a console command", function()
      config = on({ bare = { a = "enter;quit", b = "" } })
      pads[0] = state(A + B)
      local got = {}
      for _, edge in ipairs(pad.poll()) do
        got[edge.dik] = edge.down
      end
      assert.are.same({ [3] = true, [4] = true }, got)
      assert.are.same({}, injected)
    end)

    it("sends no game key at all where the config switches the section off", function()
      config = on({ bare = false })
      pads[0] = state(A)
      assert.are.same({ { 4, true } }, edges(pad.poll()))
      assert.are.same({}, injected)
    end)

    it("never sends bare a button that is itself a side", function()
      config = on({ buttons = { x = 39 } })
      pads[0] = state(X)
      assert.are.same({ { 39, true } }, edges(pad.poll()))
      assert.are.same({}, injected)
    end)

    it("chords nothing where the config switches the sides off", function()
      config = on({ activators = false })
      pads[0] = state(A, 255, 0)
      assert.are.same({ { 39, true } }, edges(pad.poll()))
      assert.are.same({ { "enter", true } }, injected)
    end)

    it("feeds the bars alone when it has no way to reach the game", function()
      pad = build()
      connect(0)
      pads[0] = state(A)
      assert.are.same({ { 4, true } }, edges(pad.poll()))
    end)
  end)

  describe("losing the pad", function()
    it("releases everything held and goes back to probing, from the slot it lost", function()
      connect(1, state(A, 255, 0))
      pads[1] = nil
      assert.are.same({ { 39, false }, { 4, false } }, edges(pad.poll()))
      assert.are.same({ 1 }, reads, "nothing else is probed that frame")
      reads = {}
      pad.poll()
      assert.are.same({}, reads, "nor inside the next second")
      clock = clock + 1
      pad.poll()
      assert.are.same({ 1 }, reads)
    end)
  end)

  describe("release", function()
    it("answers the bars' ups for everything held, and nothing after", function()
      connect(0, state(A + LB))
      assert.are.same({ { 43, false }, { 4, false } }, edges(pad.release()))
      assert.are.same({}, pad.release())
    end)

    it("lets a game key go too", function()
      local injected = {}
      pad = build({
        inject = function(name, down)
          injected[#injected + 1] = { name, down }
        end,
      })
      connect(0, state(A))
      pad.release()
      assert.are.same({ { "enter", true }, { "enter", false } }, injected)
    end)

    it("presses again, on the next poll, what is still held", function()
      connect(0, state(A))
      pad.release()
      assert.are.same({ { 4, true } }, edges(pad.poll()))
    end)
  end)

  describe("configuration", function()
    local function configure(overrides)
      config = on(overrides)
      connect(0)
    end

    it("uses the default map where the config names no button", function()
      configure()
      pads[0] = state(A)
      assert.are.same({ { 4, true } }, edges(pad.poll()))
    end)

    it("takes a button's key from the config", function()
      configure({ buttons = { a = 30 } })
      pads[0] = state(A)
      assert.are.same({ { 30, true } }, edges(pad.poll()))
    end)

    it("falls back to the default for a key the config does not name", function()
      configure({ buttons = { a = 30 } })
      pads[0] = state(B)
      assert.are.same({ { 3, true } }, edges(pad.poll()))
    end)

    it("sends nothing for a button set to false", function()
      configure({ buttons = { a = false } })
      pads[0] = state(A)
      assert.are.same({}, pad.poll())
    end)

    it("ignores a key that is not a DIK", function()
      configure({ buttons = { a = "x", b = 0, x = 256, y = 2.5 } })
      pads[0] = state(A + B + X + Y)
      assert.are.same({}, pad.poll())
    end)

    it("maps Start when the config gives it a key", function()
      configure({ buttons = { start = 1 } })
      pads[0] = state(START)
      assert.are.same({ { 1, true } }, edges(pad.poll()))
    end)

    it("reads the trigger threshold from the config", function()
      configure({ trigger_threshold = 100 })
      pads[0] = state(0, 100, 0)
      assert.are.same({}, pad.poll())
      pads[0] = state(0, 101, 0)
      assert.are.same({ { 39, true } }, edges(pad.poll()))
    end)

    it("falls back to the default threshold for one out of range", function()
      configure({ trigger_threshold = -1 })
      pads[0] = state(0, 10, 0)
      assert.are.same({}, pad.poll())
    end)

    it("reads a chord from the config", function()
      configure({ chords = { a = { lt = 20 } } })
      pads[0] = state(A, 255, 0)
      assert.are.same({ { 39, true }, { 20, true } }, edges(pad.poll()))
    end)

    it("drops every chord where the config switches the section off", function()
      configure({ chords = false })
      pads[0] = state(RB, 0, 255)
      assert.are.same({ { 40, true }, { 41, true } }, edges(pad.poll()))
    end)

    it("sends nothing where the config switches the buttons off", function()
      configure({ buttons = false })
      pads[0] = state(A + B, 255, 0)
      assert.are.same({}, pad.poll())
    end)

    it("drops a chord the config switches off", function()
      configure({ chords = { rb = false } })
      pads[0] = state(RB, 0, 255)
      assert.are.same({ { 40, true }, { 41, true } }, edges(pad.poll()))
    end)

    it("answers fresh defaults every time, switched off", function()
      local first = pad.config_defaults()
      first.buttons.a = 99
      assert.are.equal(4, pad.config_defaults().buttons.a)
      assert.is_false(pad.config_defaults().enabled)
      assert.are.equal("enter", pad.config_defaults().bare.a)
      assert.are.same({ 39, 40, 41 }, pad.config_defaults().activators)
    end)
  end)

  describe("switched off", function()
    it("neither reads nor sends", function()
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

    it("releases what was held the frame it goes off", function()
      connect(0, state(A))
      config = { enabled = false }
      assert.are.same({ { 4, false } }, edges(pad.poll()))
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
      assert.are.same({ { 43, false }, { 4, false } }, edges(pad.poll()))
      config = on()
      assert.are.same({ { 43, true }, { 4, true } }, edges(pad.poll()))
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
      pad = build({ read = false, unavailable = "ffi not available" })
      assert.are.equal("gamepad: unavailable - ffi not available", pad.status())
    end)
  end)
end)
