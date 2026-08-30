--[[ Every shipped component, registered together, exactly as the entry point
     registers them. The registry refuses a clash, so this is what says the
     shipped aliases are unique - a per-component spec can only ever speak for
     its own. ]]

local new_registry = require("lib/registry")
local new_commands = require("lib/commands")
local fakes = require("tests/support/fakes")

local FACTORIES = {
  { module = "components/parambar/parambar" },
  { module = "components/giltracker/giltracker" },
  { module = "components/equipviewer/equipviewer" },
  { module = "components/targetbar/targetbar" },
  { module = "components/crossbar/crossbar" },
  { module = "components/partylist/partylist", name = "partylist", variant = "main" },
  { module = "components/partylist/partylist", name = "alliancelist1", variant = "alliance1" },
  { module = "components/partylist/partylist", name = "alliancelist2", variant = "alliance2" },
}

describe("component aliases", function()
  local registry

  -- The widgets are built for their `alias` alone, so the ctx carries only what
  -- a factory reads while constructing: the screen its defaults are measured
  -- against, prim constructors, and the two libraries a component may look for.
  local function build(entry)
    local prims = fakes.prims()
    return require(entry.module)({
      name = entry.name,
      variant = entry.variant,
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      asset = function(path)
        return "addons/XIVHud/" .. path
      end,
      resources = { spells = {}, job_abilities = {}, items = {}, zones = {}, statuses = {} },
      now = function()
        return 0
      end,
      time = function()
        return 0
      end,
      say = function() end,
    })
  end

  before_each(function()
    registry = new_registry({ reserved = new_commands({}).reserved })
  end)

  it("registers every shipped component together, so no two claim the same word", function()
    for _, entry in ipairs(FACTORIES) do
      local widget = build(entry)
      local registered, err = pcall(registry.register, widget)
      assert.is_true(registered, widget.name .. " must register beside the others: " .. tostring(err))
    end
  end)

  it("gives each of them the alias it ships with", function()
    for _, entry in ipairs(FACTORIES) do
      registry.register(build(entry))
    end
    assert.are.same({
      pb = "parambar",
      gt = "giltracker",
      ev = "equipviewer",
      tb = "targetbar",
      cb = "crossbar",
      pl = "partylist",
    }, registry.alias_map())
  end)
end)
