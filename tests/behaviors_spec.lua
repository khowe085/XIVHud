local new_behaviors = require("lib/behaviors")

describe("behaviors", function()
  local sent, fired, delivered, components, behaviors

  -- The action service's own answer, narrowed to the two types used here.
  local function validate(record)
    if record.type == "open" and record.action == "map" then
      return true
    end
    if record.type == "ma" and type(record.action) == "string" then
      return true
    end
    return nil, "unknown action type: " .. tostring(record.type)
  end

  local function build(overrides)
    local deps = {
      send_key = function(key, down)
        sent[#sent + 1] = { key, down }
      end,
      validate = validate,
      fire_action = function(record)
        fired[#fired + 1] = record
      end,
      components = function()
        return components
      end,
      deliver = function(name, down, cancelled)
        delivered[#delivered + 1] = { name, down, cancelled }
      end,
    }
    for key, value in pairs(overrides or {}) do
      deps[key] = value
    end
    return new_behaviors(deps)
  end

  before_each(function()
    sent, fired, delivered = {}, {}, {}
    components = { "crossbar.left", "crossbar.slot1" }
    behaviors = build()
  end)

  describe("a game key", function()
    it("goes down with the behaviour and up when it is let go", function()
      behaviors.edge("accept", true)
      assert.are.same({ { "enter", true } }, sent)
      behaviors.edge("accept", false)
      assert.are.same({ { "enter", true }, { "enter", false } }, sent)
    end)

    it("stays down until everything holding it has let go", function()
      behaviors.edge("accept", true)
      behaviors.edge("accept", true)
      behaviors.edge("accept", false)
      assert.are.same({ { "enter", true } }, sent)
      behaviors.edge("accept", false)
      assert.are.same({ { "enter", true }, { "enter", false } }, sent)
    end)

    it("ignores a let-go with nothing held", function()
      behaviors.edge("accept", false)
      assert.are.same({}, sent)
    end)

    it("goes up on a cancelled let-go too", function()
      behaviors.edge("accept", true)
      behaviors.edge("accept", false, true)
      assert.are.same({ { "enter", true }, { "enter", false } }, sent)
    end)

    it("can be a gesture's own", function()
      local own = { key = "numpad*" }
      behaviors.edge(own, true)
      behaviors.edge(own, false)
      assert.are.same({ { "numpad*", true }, { "numpad*", false } }, sent)
    end)

    it("holds a key two behaviours share until both let go", function()
      local own = { key = "enter" }
      behaviors.edge("accept", true)
      behaviors.edge(own, true)
      behaviors.edge("accept", false)
      assert.are.same({ { "enter", true } }, sent)
      behaviors.edge(own, false)
      assert.are.same({ { "enter", true }, { "enter", false } }, sent)
    end)

    it("lets go of the key it pressed, whatever the entry says by then", function()
      local own = { key = "f" }
      behaviors.edge(own, true)
      own.key = "g"
      behaviors.edge(own, false)
      assert.are.same({ { "f", true }, { "f", false } }, sent)
    end)

    it("refuses a key name that could start a second command", function()
      behaviors.edge({ key = "enter;quit" }, true)
      assert.are.same({}, sent)
    end)
  end)

  describe("an action", function()
    it("runs on the press alone", function()
      behaviors.edge("open_map", true)
      behaviors.edge("open_map", false)
      assert.are.same({ { type = "open", action = "map" } }, fired)
    end)

    it("runs again on the next press", function()
      behaviors.edge("open_map", true)
      behaviors.edge("open_map", false)
      behaviors.edge("open_map", true)
      assert.are.equal(2, #fired)
    end)

    it("can be a gesture's own, the record a slot would hold", function()
      local record = { type = "ma", action = "Cure IV", target = "t" }
      behaviors.edge(record, true)
      behaviors.edge(record, false)
      assert.are.same({ record }, fired)
    end)

    it("does nothing when the action service refuses it", function()
      behaviors.edge({ type = "nope" }, true)
      assert.are.same({}, fired)
    end)

    it("does nothing without the action service", function()
      behaviors = build({ validate = false })
      behaviors.edge("open_map", true)
      assert.are.same({}, fired)
    end)
  end)

  describe("a component's behaviour", function()
    it("reaches the component on both edges", function()
      behaviors.edge("crossbar.left", true)
      behaviors.edge("crossbar.left", false)
      assert.are.same({ { "crossbar.left", true, false }, { "crossbar.left", false, false } }, delivered)
    end)

    it("says a let-go was cancelled rather than released", function()
      behaviors.edge("crossbar.left", true)
      behaviors.edge("crossbar.left", false, true)
      assert.are.same({ "crossbar.left", false, true }, delivered[2])
    end)

    it("stays held until everything holding it has let go", function()
      behaviors.edge("crossbar.left", true)
      behaviors.edge("crossbar.left", true)
      behaviors.edge("crossbar.left", false)
      assert.are.equal(1, #delivered)
      behaviors.edge("crossbar.left", false)
      assert.are.same({ "crossbar.left", false, false }, delivered[2])
    end)

    it("goes nowhere when no component declares it", function()
      behaviors.edge("crossbar.wxhb_left", true)
      assert.are.same({}, delivered)
    end)

    it("keeps its count when the component throws", function()
      local calls = 0
      behaviors = build({
        deliver = function(_, down)
          calls = calls + 1
          if down then
            error("broken", 0)
          end
        end,
      })
      assert.has_error(function()
        behaviors.edge("crossbar.left", true)
      end, "broken")
      behaviors.edge("crossbar.left", false)
      assert.are.equal(2, calls)
    end)
  end)

  it("does nothing for a name it does not know", function()
    behaviors.edge("nope", true)
    behaviors.edge("nope", false)
    assert.are.same({}, sent)
    assert.are.same({}, fired)
    assert.are.same({}, delivered)
  end)

  describe("check", function()
    it("passes the shipped behaviours, the components' and a gesture's own sound ones", function()
      for _, value in ipairs({
        "accept",
        "open_map",
        "crossbar.left",
        { key = "numpad*" },
        { type = "ma", action = "Cure IV", target = "t" },
      }) do
        assert.is_true(behaviors.check(value))
      end
    end)

    it("says what is wrong with the rest", function()
      for _, case in ipairs({
        { "nope", "no behavior nope" },
        { "crossbar.nope", "no behavior crossbar.nope" },
        { { key = "enter;quit" }, "enter;quit is not a key name" },
        { { key = "enter", type = "ma", action = "Cure" }, "a key or an action, not both" },
        { {}, "neither a key nor an action" },
        { { type = "nope" }, "unknown action type: nope" },
        { 5, "neither a key nor an action" },
      }) do
        local ok, why = behaviors.check(case[1])
        assert.is_nil(ok)
        assert.are.equal(case[2], why)
      end
    end)

    it("says an action has nothing to run it without the action service", function()
      behaviors = build({ validate = false })
      local ok, why = behaviors.check("open_map")
      assert.is_nil(ok)
      assert.are.equal("actions need the action service, which did not load", why)
    end)
  end)

  --[[ What a press answers is whether the key it came from is taken from the
       game: the keyboard map's question, which the pad never asks. ]]
  describe("what a press takes", function()
    local answer

    before_each(function()
      answer = true
      behaviors = build({
        deliver = function(name, down, cancelled)
          delivered[#delivered + 1] = { name, down, cancelled }
          return answer
        end,
      })
    end)

    it("answers a component's own answer to the press", function()
      assert.is_true(behaviors.edge("crossbar.left", true))
      answer = nil
      assert.is_false(behaviors.edge("crossbar.slot1", true))
    end)

    it("takes the press of a game key or an action", function()
      assert.is_true(behaviors.edge("accept", true))
      assert.is_true(behaviors.edge({ type = "open", action = "map" }, true))
    end)

    it("takes nothing for a behaviour that cannot work", function()
      assert.is_false(behaviors.edge("nope", true))
      assert.is_false(behaviors.edge("crossbar.right", true), "declared by no component")
    end)

    it("answers a second holder what the first press answered", function()
      behaviors.edge("crossbar.left", true)
      answer = false
      assert.is_true(behaviors.edge("crossbar.left", true))
      assert.are.equal(1, #delivered)
    end)

    it("answers a let-go nothing", function()
      behaviors.edge("crossbar.left", true)
      assert.is_false(behaviors.edge("crossbar.left", false))
    end)
  end)

  describe("is_component", function()
    it("says a component's own behaviour is one by its name, declared or not", function()
      assert.is_true(behaviors.is_component("crossbar.left"))
      assert.is_true(behaviors.is_component("nobody.left"))
    end)

    it("says a shipped behaviour and a gesture's own entry are not", function()
      assert.is_false(behaviors.is_component("autorun"))
      assert.is_false(behaviors.is_component({ key = "f1" }))
      assert.is_false(behaviors.is_component({ type = "open", action = "map" }))
      assert.is_false(behaviors.is_component(nil))
    end)
  end)

  describe("known", function()
    it("knows the shipped behaviours and the components'", function()
      assert.is_true(behaviors.known("accept"))
      assert.is_true(behaviors.known("open_map"))
      assert.is_true(behaviors.known("crossbar.left"))
      assert.is_false(behaviors.known("nope"))
      assert.is_false(behaviors.known("crossbar.nope"))
    end)

    it("knows names alone", function()
      assert.is_false(behaviors.known({ key = "enter" }))
    end)
  end)

  it("names the shipped behaviours, then the components'", function()
    assert.are.same({
      "accept",
      "autorun",
      "cancel",
      "cycle_window",
      "lockon",
      "main_menu",
      "open_map",
      "target_npc",
      "target_self",
      "crossbar.left",
      "crossbar.slot1",
    }, behaviors.names())
  end)

  -- A gesture's bind reads a behaviour's name before a bind type.
  it("names no behaviour after a bind type", function()
    local actions = require("lib/actionbar/actions")({})
    for _, name in ipairs(behaviors.names()) do
      assert.is_false(actions.is_type(name), name)
    end
    assert.is_false(actions.is_type("key"))
  end)

  it("ships the game keys and the map", function()
    for name, key in pairs({
      accept = "enter",
      cancel = "escape",
      cycle_window = "numpad+",
      main_menu = "numpad-",
      lockon = "numpad*",
      autorun = "r",
      target_self = "f1",
      target_npc = "f8",
    }) do
      behaviors.edge(name, true)
      assert.are.same({ key, true }, sent[#sent], name)
    end
    behaviors.edge("open_map", true)
    assert.are.same({ type = "open", action = "map" }, fired[1])
  end)
end)
