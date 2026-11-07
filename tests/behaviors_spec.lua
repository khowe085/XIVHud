local new_behaviors = require("lib/behaviors")

describe("behaviors", function()
  local file, sent, fired, delivered, parsed, components, behaviors

  local function build(overrides)
    local deps = {
      config = function()
        return file
      end,
      send_key = function(key, down)
        sent[#sent + 1] = { key, down }
      end,
      parse_action = function(text)
        parsed[#parsed + 1] = text
        if text == "open map" then
          return { type = "open", action = "map" }
        end
        return nil, "unknown open target: " .. text
      end,
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
    file = { accept = { key = "enter" }, open_map = { action = "open map" } }
    sent, fired, delivered, parsed = {}, {}, {}, {}
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

    it("lets go of the key it pressed, whatever the file says by then", function()
      behaviors.edge("accept", true)
      file.accept = { key = "escape" }
      behaviors.edge("accept", false)
      assert.are.same({ { "enter", true }, { "enter", false } }, sent)
    end)

    it("goes up on a cancelled let-go too", function()
      behaviors.edge("accept", true)
      behaviors.edge("accept", false, true)
      assert.are.same({ { "enter", true }, { "enter", false } }, sent)
    end)

    it("holds a key two behaviours share until both let go", function()
      file = { accept = { key = "enter" }, confirm = { key = "enter" } }
      behaviors.edge("accept", true)
      behaviors.edge("confirm", true)
      behaviors.edge("accept", false)
      assert.are.same({ { "enter", true } }, sent)
      behaviors.edge("confirm", false)
      assert.are.same({ { "enter", true }, { "enter", false } }, sent)
    end)

    it("refuses a key name that could start a second command", function()
      file.bad = { key = "enter;quit" }
      behaviors.edge("bad", true)
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

    it("is read once, however often it runs", function()
      for _ = 1, 3 do
        behaviors.edge("open_map", true)
        behaviors.edge("open_map", false)
      end
      assert.are.same({ "open map" }, parsed)
    end)

    it("does nothing when it does not parse", function()
      file.open_map = { action = "open mapp" }
      behaviors.edge("open_map", true)
      assert.are.same({}, fired)
    end)

    it("does nothing without the action service", function()
      behaviors = build({ parse_action = false })
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

    it("cannot be shadowed by an entry in the file", function()
      file["crossbar.left"] = { key = "a" }
      behaviors.edge("crossbar.left", true)
      assert.are.same({}, sent)
      assert.are.same({ { "crossbar.left", true, false } }, delivered)
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

  it("does nothing for a behaviour the file removes", function()
    file.accept = false
    behaviors.edge("accept", true)
    assert.are.same({}, sent)
  end)

  it("reads a file that is not a table as one naming nothing, so the shipped behaviours stand", function()
    file = nil
    behaviors.edge("cancel", true)
    assert.are.same({ { "escape", true } }, sent)
  end)

  --[[ The file is never merged with them: an entry merged field by field
       would carry a shipped key into a behaviour the file makes an action. ]]
  describe("the shipped behaviours", function()
    it("stand for every name the file leaves out", function()
      file = {}
      behaviors.edge("cancel", true)
      behaviors.edge("open_map", true)
      assert.are.same({ { "escape", true } }, sent)
      assert.are.same({ { type = "open", action = "map" } }, fired)
      assert.is_true(behaviors.known("lockon"))
    end)

    it("give way whole to the file's entry, whatever its kind", function()
      file = { open_map = { key = "m" }, accept = { action = "open map" } }
      behaviors.edge("open_map", true)
      behaviors.edge("accept", true)
      assert.are.same({ { "m", true } }, sent)
      assert.are.same({ { type = "open", action = "map" } }, fired)
      assert.are.same({}, behaviors.problems())
    end)

    it("are named in problems when one cannot work", function()
      file = {}
      behaviors = build({ parse_action = false })
      assert.are.same(
        { "behaviors: open_map - actions need the action service, which did not load" },
        behaviors.problems()
      )
    end)
  end)

  describe("known", function()
    it("knows the file's behaviours and the components'", function()
      assert.is_true(behaviors.known("accept"))
      assert.is_true(behaviors.known("open_map"))
      assert.is_true(behaviors.known("crossbar.left"))
      assert.is_false(behaviors.known("nope"))
      assert.is_false(behaviors.known("crossbar.nope"))
    end)

    it("knows one whose definition is broken, which problems() reports", function()
      file.bad = { key = "enter;quit" }
      assert.is_true(behaviors.known("bad"))
    end)

    it("does not know one the file removes", function()
      file.accept = false
      assert.is_false(behaviors.known("accept"))
    end)
  end)

  describe("problems", function()
    it("has none for a sound file", function()
      assert.are.same({}, behaviors.problems())
    end)

    it("names each broken entry once, in name order", function()
      file = {
        ["Bad Name"] = { key = "enter" },
        both = { key = "enter", action = "open map" },
        neither = {},
        keyless = { key = "enter;quit" },
        broken = { action = "open mapp" },
        number = 5,
        removed = false,
      }
      assert.are.same({
        "behaviors: Bad Name - a name is a plain lowercase word",
        "behaviors: both - a key or an action, not both",
        "behaviors: broken - unknown open target: open mapp",
        "behaviors: keyless - enter;quit is not a key name",
        "behaviors: neither - neither a key nor an action",
        "behaviors: number - neither a key nor an action",
      }, behaviors.problems())
    end)

    it("says an action has nothing to run it without the action service", function()
      behaviors = build({ parse_action = false })
      assert.are.same(
        { "behaviors: open_map - actions need the action service, which did not load" },
        behaviors.problems()
      )
    end)
  end)

  it("ships the game keys and the map", function()
    file = {}
    for name, key in pairs({
      accept = "enter",
      cancel = "escape",
      cycle_window = "numpad+",
      main_menu = "numpad-",
      lockon = "numpad*",
      autorun = "r",
    }) do
      behaviors.edge(name, true)
      assert.are.same({ key, true }, sent[#sent], name)
    end
    behaviors.edge("open_map", true)
    assert.are.same({ type = "open", action = "map" }, fired[1])
  end)
end)
