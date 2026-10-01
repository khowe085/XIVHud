--[[ Every shipped component's panel in the `//hud config` window, together.
     A component's own spec proves its rows against its own command parser;
     this is what only the whole set can say: which components the window's
     menu lists, and that not one of their panels asks the window for more
     than it draws - there is no paging, so a row past the last is a setting
     nobody can reach. ]]

local fakes = require("tests/support/fakes")
local panels = require("tests/support/panels")

local FACTORIES = {
  "components/parambar/parambar",
  "components/giltracker/giltracker",
  "components/equipviewer/equipviewer",
  "components/targetbar/targetbar",
  "components/crossbar/crossbar",
  "components/hotbar/hotbar",
  "components/skillchain/skillchain",
  "components/partylist/partylist",
  "components/statusbar/statusbar",
  "components/speedcheck/speedcheck",
  "components/expbar/expbar",
  "components/invtracker/invtracker",
}

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, field in pairs(value) do
    out[key] = copy(field)
  end
  return out
end

describe("config panels", function()
  local widgets

  -- Built, and - where it declares a panel - attached the way core attaches
  -- it at login: the component's own defaults, its placement split off, a
  -- saver and a store. One with no panel is only ever asked whether it has
  -- one, so it is left unattached.
  local function build(module)
    local prims = fakes.prims()
    local ctx = {
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      asset = function(path)
        return "addons/XIVHud/" .. path
      end,
      resources = { spells = {}, job_abilities = {}, items = {}, zones = {}, statuses = {}, buffs = {} },
      now = function()
        return 0
      end,
      time = function()
        return 0
      end,
      say = function() end,
      -- The client reads an attach makes: a logged-in WAR/NIN with nothing
      -- equipped, nobody in the party and nothing targeted.
      get_player = function()
        return {
          id = 1,
          name = "Azureblood",
          main_job = "WAR",
          main_job_id = 1,
          main_job_level = 99,
          sub_job = "NIN",
          sub_job_id = 13,
          status = 0,
          buffs = {},
          vitals = { hp = 1000, max_hp = 1000, hpp = 100, mp = 500, max_mp = 500, mpp = 100, tp = 0 },
        }
      end,
      get_party = function()
        return {}
      end,
      get_info = function()
        return {}
      end,
      get_mob_by_target = function()
        return nil
      end,
      get_items = function()
        return {}
      end,
      get_equipment = function()
        return {}
      end,
      get_item = function()
        return nil
      end,
      get_spells = function()
        return {}
      end,
      get_abilities = function()
        return { job_abilities = {}, weapon_skills = {} }
      end,
      get_spell_recasts = function()
        return {}
      end,
      get_ability_recasts = function()
        return {}
      end,
      get_key_items = function()
        return {}
      end,
      generation = function()
        return 1
      end,
      parse_packet = function()
        return nil
      end,
      file_exists = function()
        return false
      end,
      game_path = function()
        return "C:/FFXI"
      end,
    }
    ctx.actions = fakes.action_service(ctx)
    local widget = require(module)(ctx)
    if widget.config_panel == nil then
      return widget
    end
    local config = copy(widget.defaults)
    config.layout = nil
    local files = {}
    widget.attach(config, function() end, widget.wants_store and {
      load = function(name)
        return files[name]
      end,
      save = function(name, value)
        files[name] = value
      end,
    } or nil)
    return widget
  end

  before_each(function()
    widgets = {}
    for index, module in ipairs(FACTORIES) do
      widgets[index] = build(module)
    end
  end)

  it("are declared by exactly the components that have settings a command sets", function()
    local with, without = {}, {}
    for _, widget in ipairs(widgets) do
      local list = widget.config_panel ~= nil and with or without
      list[#list + 1] = widget.name
    end
    table.sort(with)
    table.sort(without)
    assert.are.same({
      "crossbar",
      "equipviewer",
      "hotbar",
      "invtracker",
      "parambar",
      "partylist",
      "statusbar",
      "targetbar",
    }, with)
    -- No settings verb of their own: an action (`expbar clear`) is not one.
    assert.are.same({ "expbar", "giltracker", "skillchain", "speedcheck" }, without)
  end)

  it("are each one the window can draw, every row inside what it holds", function()
    for _, widget in ipairs(widgets) do
      if widget.config_panel ~= nil then
        assert.are.same({}, panels.problems(widget.config_panel()), widget.name)
      end
    end
  end)

  it("name a handler for every row they route", function()
    for _, widget in ipairs(widgets) do
      if widget.config_panel ~= nil then
        local panel = widget.config_panel()
        local pages = panel.tabs or { panel }
        for _, page in ipairs(pages) do
          for _, row in ipairs(page.rows) do
            local handler = row.route == "buffs" and "handle_buffs" or "handle_command"
            assert.is_function(widget[handler], widget.name .. " / " .. row.label .. " needs " .. handler)
          end
        end
      end
    end
  end)
end)
