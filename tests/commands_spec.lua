local new_commands = require("lib/commands")

describe("commands", function()
  local commands

  before_each(function()
    commands = new_commands({
      components = function()
        return { "parambar", "clock" }
      end,
      aliases = function()
        return { pb = "parambar" }
      end,
    })
  end)

  local function parse(...)
    return commands.parse({ ... })
  end

  local function assert_error(action, needle)
    assert.are.equal("error", action.action)
    assert.is_not_nil(action.message:lower():find(needle, 1, true), "message was: " .. action.message)
    assert.is_not_nil(action.message:find("//hud help", 1, true), "every error points at help")
  end

  describe("help", function()
    it("treats a bare command as help", function()
      assert.are.equal("help", parse().action)
      assert.are.equal("help", commands.parse(nil).action)
    end)

    it("accepts the explicit verb in any case", function()
      assert.are.equal("help", parse("help").action)
      assert.are.equal("help", parse("HELP").action)
    end)

    it("exposes the reserved verbs so registration can refuse them", function()
      for _, verb in ipairs({ "help", "layout", "setup", "list", "show", "hide", "reset", "slot", "copy" }) do
        assert.is_true(commands.reserved[verb], verb .. " must be reserved")
      end
      assert.is_nil(commands.reserved.parambar)
    end)
  end)

  describe("layout", function()
    it("toggles layout mode under either name", function()
      assert.are.equal("layout", parse("layout").action)
      assert.are.equal("layout", parse("setup").action)
      assert.are.equal("layout", parse("Layout").action)
    end)

    it("rejects trailing arguments", function()
      assert_error(parse("layout", "now"), "layout")
    end)
  end)

  describe("list", function()
    it("parses with no arguments", function()
      assert.are.equal("list", parse("list").action)
    end)
  end)

  describe("show and hide", function()
    it("resolves the component name case-insensitively to its registered form", function()
      assert.are.same({ action = "show", component = "parambar" }, parse("show", "ParamBar"))
      assert.are.same({ action = "hide", component = "clock" }, parse("hide", "CLOCK"))
    end)

    it("requires a component", function()
      assert_error(parse("show"), "component")
      assert_error(parse("hide"), "component")
    end)

    it("rejects an unknown component", function()
      assert_error(parse("show", "nope"), "nope")
    end)

    --[[ The second word is an anchor of that component. The parser does not
         know which anchors a component has - it knows names and aliases and
         nothing else - so an unusable one is refused by core, where the widget
         is, and where the real names can be said back. ]]
    it("takes an anchor after the component, keeping the word as typed", function()
      assert.are.same(
        { action = "hide", component = "parambar", anchor = "alliance1" },
        parse("hide", "ParamBar", "alliance1")
      )
      assert.are.same({ action = "show", component = "parambar", anchor = "Main" }, parse("show", "pb", "Main"))
    end)

    it("rejects more than a component and an anchor", function()
      assert_error(parse("show", "parambar", "clock", "extra"), "anchor")
      assert_error(parse("hide", "parambar", "clock", "extra"), "anchor")
    end)
  end)

  describe("reset", function()
    it("targets one component", function()
      assert.are.same({ action = "reset", component = "parambar" }, parse("reset", "parambar"))
    end)

    it("targets everything", function()
      assert.are.same({ action = "reset", component = "all" }, parse("reset", "ALL"))
    end)

    it("requires a target", function()
      assert_error(parse("reset"), "component")
    end)

    it("rejects an unknown target", function()
      assert_error(parse("reset", "nope"), "nope")
    end)
  end)

  describe("slot", function()
    it("switches to a named slot, stored lowercase", function()
      assert.are.same({ action = "slot", op = "switch", name = "raid" }, parse("slot", "Raid"))
    end)

    it("parses the sub-verbs", function()
      assert.are.same({ action = "slot", op = "list" }, parse("slot", "list"))
      assert.are.same({ action = "slot", op = "create", name = "raid" }, parse("slot", "create", "Raid"))
      assert.are.same({ action = "slot", op = "delete", name = "raid" }, parse("slot", "delete", "Raid"))
    end)

    it("requires a name for create and delete", function()
      assert_error(parse("slot", "create"), "name")
      assert_error(parse("slot", "delete"), "name")
    end)

    it("rejects trailing words after list", function()
      assert_error(parse("slot", "list", "please"), "slot")
    end)

    it("refuses to name a slot after one of its own sub-verbs", function()
      assert_error(parse("slot", "create", "list"), "name")
      assert_error(parse("slot", "create", "DELETE"), "name")
    end)

    it("requires a sub-verb or slot name", function()
      assert_error(parse("slot"), "slot")
    end)

    it("rejects slot names that are not a single word", function()
      assert_error(parse("slot", "create", "two words"), "name")
    end)
  end)

  describe("copy", function()
    it("names a source and a destination, keeping their case", function()
      local action = parse("copy", "Azureblood", "Altcharacter")
      assert.are.same({ action = "copy", source = "Azureblood", destination = "Altcharacter" }, action)
    end)

    it("requires a source", function()
      assert_error(parse("copy"), "source")
    end)

    it("requires a destination, since it overwrites one", function()
      assert_error(parse("copy", "Azureblood"), "destination")
    end)

    it("refuses names that could climb out of the data directory", function()
      -- The destination is deleted before the copy, so a name like ".." would
      -- take the addon's own files with it.
      for _, bad in ipairs({ "..", ".", "a/b", "a\\b", "..\\..\\x" }) do
        assert_error(parse("copy", "Alpha", bad), "character")
        assert_error(parse("copy", bad, "Alpha"), "character")
      end
    end)

    it("rejects extra arguments", function()
      assert_error(parse("copy", "Azureblood", "Altcharacter", "confirm"), "copy")
    end)
  end)

  describe("aliases", function()
    it("accepts an alias wherever a component name is accepted", function()
      assert.are.same({ action = "show", component = "parambar" }, parse("show", "pb"))
      assert.are.same({ action = "hide", component = "parambar" }, parse("hide", "PB"))
      assert.are.same({ action = "reset", component = "parambar" }, parse("reset", "pb"))
    end)

    it("routes a passthrough through the alias, under the component's real name", function()
      assert.are.same(
        { action = "component", component = "parambar", args = { "width", "150" } },
        parse("pb", "width", "150")
      )
    end)

    it("gets by without an alias dep at all", function()
      local bare = new_commands({
        components = function()
          return { "parambar" }
        end,
      })
      assert.are.equal("component", bare.parse({ "parambar" }).action)
      assert_error(bare.parse({ "pb" }), "unknown command")
    end)
  end)

  describe("component passthrough", function()
    it("routes an unreserved first word that names a component", function()
      local action = parse("parambar", "width", "150")
      assert.are.same({ action = "component", component = "parambar", args = { "width", "150" } }, action)
    end)

    it("passes no arguments through for a bare component name", function()
      assert.are.same({ action = "component", component = "parambar", args = {} }, parse("ParamBar"))
    end)

    it("leaves passthrough arguments exactly as typed", function()
      assert.are.same({ "Compact", "ON" }, parse("parambar", "Compact", "ON").args)
    end)
  end)

  describe("unknown input", function()
    it("never stays silent", function()
      assert_error(parse("bogus"), "bogus")
    end)

    it("reflects components registered after construction", function()
      local names = { "parambar" }
      local late = new_commands({
        components = function()
          return names
        end,
      })
      assert.are.equal("error", late.parse({ "clock" }).action)
      names[#names + 1] = "clock"
      assert.are.equal("component", late.parse({ "clock" }).action)
    end)

    it("ignores empty arguments Windower may hand over", function()
      assert.are.equal("help", commands.parse({ "" }).action)
    end)
  end)
end)
