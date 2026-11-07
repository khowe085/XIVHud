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

    it("gives the face buttons, the bumpers, Back and L3 their behaviours", function()
      assert.are.same({ { "accept", true } }, press(A))
      assert.are.same({ { "cancel", true } }, press(B))
      assert.are.same({ { "cycle_window", true } }, press(X))
      assert.are.same({ { "main_menu", true } }, press(Y))
      assert.are.same({ { "autorun", true } }, press(LB))
      assert.are.same({ { "crossbar.switch", true } }, press(RB))
      assert.are.same({ { "open_map", true } }, press(BACK))
      assert.are.same({ { "lockon", true } }, press(L3))
    end)

    it("holds the crossbar's sides on the triggers", function()
      assert.are.same({ { "crossbar.left", true } }, press(0, 255, 0))
      assert.are.same({ { "crossbar.right", true } }, press(0, 0, 255))
    end)

    it("leaves Start, R3 and the D-pad alone unmapped", function()
      assert.are.same({}, press(START + R3 + UP + RIGHT + DOWN + LEFT))
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

    it("ships a gesture for every slot under LT, RT and RB", function()
      local map = pad.config_defaults().map
      local count = 0
      for _ in pairs(map) do
        count = count + 1
      end
      assert.are.equal(38, count)
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
    local function known(name)
      return name ~= "nope"
    end

    it("has none for the shipped map", function()
      pad = build({ known = known })
      assert.are.same({}, pad.problems())
    end)

    it("names each broken gesture once, in order", function()
      pad = build({ known = known })
      config = on({ map = { ["lt+q"] = "slot", ["lt+lt"] = "slot", a = "nope", b = 5, x = false } })
      assert.are.same({
        "gamepad: a - no behavior nope",
        "gamepad: b - not a behavior name",
        "gamepad: lt+lt - names lt twice",
        "gamepad: lt+q - no button q",
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
end)
