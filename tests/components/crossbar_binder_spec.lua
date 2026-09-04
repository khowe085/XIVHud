local new_binder = require("components/crossbar/binder")
local new_render = require("components/crossbar/render")
local new_bindings = require("components/crossbar/bindings")
local new_actions = require("components/crossbar/actions")
local build_defaults = require("components/crossbar/defaults")
local fakes = require("tests/support/fakes")

--[[ The binder: edit mode's own surfaces (the bar's slots, the stack panel,
     the catalog) driven by nothing but mouse tuples. Every drop resolves
     through the same render.lua slot geometry the bar draws with, which is
     why the real render module is used here rather than a stand-in. ]]

-- Windower's mouse types, as layout_mode names them.
local MOVE, LEFT_DOWN, LEFT_UP = 0, 1, 2
local RIGHT_DOWN, WHEEL = 4, 10

local ANCHOR_X, ANCHOR_Y = 100, 900

local function catalog_stub(groups)
  return {
    build = function()
      return groups
    end,
  }
end

local function build(opts)
  opts = opts or {}
  local config = build_defaults(1920, 1080)
  for _, set in ipairs(opts.shared_sets or {}) do
    config.set_flags[set].shared = true
  end
  local prims = fakes.prims()
  local render = new_render({
    config = config,
    icon_for = new_actions({}).icon_for,
  })
  local files = opts.files or { WAR = { sets = { [1] = { left = { [3] = { type = "ja", action = "Provoke" } } } } } }
  local bindings = new_bindings({
    load = function(name)
      return files[name]
    end,
    save = function(name, value)
      files[name] = value
    end,
    get_config = function()
      return config
    end,
  })
  bindings.set_job("WAR", "NIN")

  local env = {
    said = {},
    previews = {},
    files = files,
    bindings = bindings,
    render = render,
    prims = prims,
    config = config,
    describe = opts.describe,
  }

  local binder = new_binder({
    new_image = prims.new_image,
    new_text = prims.new_text,
    asset = function(path)
      return "addon/" .. path
    end,
    screen = function()
      return 1920, 1080
    end,
    text_style = function()
      return { font = "sans-serif", size = 10 }
    end,
    render = function()
      return render
    end,
    groups = function()
      if opts.groups then
        return opts.groups(env)
      end
      return {
        { key = "xhb_left", bar = "xhb", side = "left", x = ANCHOR_X, y = ANCHOR_Y, scale = 1, set = 1 },
        { key = "xhb_right", bar = "xhb", side = "right", x = ANCHOR_X, y = ANCHOR_Y, scale = 1, set = 1 },
      }
    end,
    bindings = function()
      return bindings
    end,
    catalog = opts.catalog_factory and opts.catalog_factory() or catalog_stub(opts.catalog or {
      {
        name = "Job Abilities",
        entries = {
          { label = "Berserk", record = { type = "ja", action = "Berserk" } },
          { label = "Warcry", record = { type = "ja", action = "Warcry" } },
        },
      },
      {
        name = "General",
        entries = { { label = "Attack", record = { type = "draw" } } },
      },
    }),
    validate = new_actions({}).validate,
    describe = function(record)
      env.describe_calls = (env.describe_calls or 0) + 1
      if env.describe then
        return env.describe(record)
      end
      return { name = record.action or record.type, type = record.type }
    end,
    icon = function(record)
      env.icon_calls = (env.icon_calls or 0) + 1
      if opts.icon == nil then
        return nil
      end
      return opts.icon(record)
    end,
    say = function(lines)
      if type(lines) == "table" then
        for _, line in ipairs(lines) do
          env.said[#env.said + 1] = line
        end
      else
        env.said[#env.said + 1] = lines
      end
    end,
    changed = function()
      env.repaints = (env.repaints or 0) + 1
    end,
    preview = function(buffs)
      -- Wrapped: a preview of nil (the live buff list) is a call, not an
      -- absence, and the specs below tell the two apart.
      env.previews[#env.previews + 1] = { buffs = buffs }
    end,
    window_pos = function()
      return env.window_pos
    end,
    save_window_pos = function(x, y)
      env.window_pos = { x = x, y = y }
      env.window_saves = (env.window_saves or 0) + 1
    end,
  })
  env.binder = binder
  return binder, env
end

-- The centre of a slot on the drawn bar, through the very geometry the bar
-- is drawn with.
local function slot_point(env, side, slot)
  local x, y = env.render.slot_pos("xhb", side, slot)
  local size = env.render.metrics().slot
  return ANCHOR_X + x + size / 2, ANCHOR_Y + y + size / 2
end

local function centre(rect)
  return rect.x + rect.width / 2, rect.y + rect.height / 2
end

local function last_preview(env)
  local call = env.previews[#env.previews]
  return call and call.buffs or nil
end

local function click(binder, x, y)
  binder.mouse(LEFT_DOWN, x, y, 0)
  return binder.mouse(LEFT_UP, x, y, 0)
end

local function drag(binder, from_x, from_y, to_x, to_y)
  binder.mouse(LEFT_DOWN, from_x, from_y, 0)
  binder.mouse(MOVE, to_x, to_y, 0)
  return binder.mouse(LEFT_UP, to_x, to_y, 0)
end

local function row_named(env, source)
  for _, row in ipairs(env.binder.layer_view().rows) do
    if row.source == source then
      return row
    end
  end
  return nil
end

local function entry_named(env, label)
  local view = env.binder.catalog_view()
  for _, entry in ipairs(view and view.entries or {}) do
    if entry.label == label then
      return entry
    end
  end
  return nil
end

local function target_named(env, label)
  local view = env.binder.target_view()
  for _, row in ipairs(view and view.targets or {}) do
    if row.label == label then
      return row
    end
  end
  return nil
end

--[[ Click a catalog entry and, when its type asks for a target, take the
     default `(no target)` - which is exactly what a mouse bind produced
     before the third step existed. Tests that are not about targeting stay
     about their own subject. ]]
local function pick(binder, env, label)
  click(binder, centre(entry_named(env, label)))
  if env.binder.target_view() ~= nil then
    click(binder, centre(target_named(env, "(no target)")))
  end
end

--- The back button walks a step in reverse; the first step does not draw it.
local function back(binder, env)
  click(binder, centre(env.binder.window().back))
end

--- The close button, in the top right, closes outright from any step.
local function close_button(binder, env)
  click(binder, centre(env.binder.window().close))
end

--- The one visible text prim carrying `label`, or nil where none is drawn.
--- Destroyed prims are skipped: the fake keeps them in the list with their
--- last state, so a binder that has been closed and reopened would otherwise
--- answer with a prim that is no longer on screen.
local function shown_text(env, label)
  for _, prim in ipairs(env.prims.texts) do
    if prim.visible and prim.destroyed == 0 and prim.last.text == label then
      return prim
    end
  end
  return nil
end

local function open_stack(binder, env, side, slot)
  binder.open()
  local x, y = slot_point(env, side, slot)
  click(binder, x, y)
end

describe("crossbar binder", function()
  describe("edit mode itself", function()
    it("starts closed and answers nothing", function()
      local binder, env = build()
      assert.is_false(binder.active())
      assert.is_false(binder.mouse(LEFT_DOWN, 314, 991, 0), "a click before edit mode is the game's")
      assert.are.equal(0, #env.prims.all, "no prims until edit mode opens")
    end)

    it("builds its prims on open and destroys every one on close", function()
      local binder, env = build()
      binder.open()
      assert.is_true(binder.active())
      assert.is_true(#env.prims.all > 0, "the binder draws")
      local built = #env.prims.all
      binder.close()
      assert.is_false(binder.active())
      for _, prim in ipairs(env.prims.all) do
        assert.are.equal(1, prim.destroyed)
      end
      binder.open()
      assert.are.equal(built * 2, #env.prims.all, "a fresh set, never the destroyed ones")
    end)

    it("turns the text background off, as every other widget here does", function()
      -- parambar, partylist, targetbar, equipviewer and lib/overlay all do
      -- this: without it the texts library draws its own opaque box behind
      -- every line.
      local binder, env = build()
      binder.open()
      assert.is_true(#env.prims.texts > 0)
      for _, prim in ipairs(env.prims.texts) do
        assert.is_false(prim.last.bg_visible, "a text prim with its background still on")
      end
    end)

    it("clears the preview when it closes", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "ctx:light-arts")))
      env.previews = {}
      binder.close()
      assert.are.equal(1, #env.previews, "the preview is handed back")
      assert.is_nil(last_preview(env), "to the live buff list")
    end)

    it("is inert without a prim surface", function()
      -- The headless ctx (no new_image/new_text) is legal everywhere else in
      -- this component; edit mode must degrade, not throw.
      local binder = new_binder({
        render = function()
          return new_render({ config = build_defaults(1920, 1080), icon_for = new_actions({}).icon_for })
        end,
        groups = function()
          return {}
        end,
        bindings = function()
          return nil
        end,
        catalog = catalog_stub({}),
        say = function() end,
      })
      assert.has_no.errors(function()
        binder.open()
        binder.mouse(LEFT_DOWN, 10, 10, 0)
        binder.mouse(LEFT_UP, 10, 10, 0)
        binder.close()
      end)
    end)
  end)

  describe("the stack panel", function()
    it("opens on a slot click, listing the whole stack", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      local panel = binder.layer_view()
      assert.is_not_nil(panel, "the clicked slot opened its stack")
      local sources = {}
      for _, row in ipairs(panel.rows) do
        sources[#sources + 1] = row.source
      end
      assert.are.same({
        "base",
        "sub",
        "ctx:light-arts",
        "ctx:dark-arts",
        "ctx:addendum-white",
        "ctx:addendum-black",
      }, sources, "shared/base, the worn subjob, then every roster context")
    end)

    it("shows each row's own entry, or a dash", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      assert.are.equal("ja Provoke", row_named(env, "base").entry)
      assert.are.equal("-", row_named(env, "sub").entry, "ASCII only - the chat and prims are not UTF-8")
    end)

    it("marks the winning row and nothing else", function()
      local files = {
        WAR = {
          sets = { [1] = { left = { [3] = { type = "ja", action = "Provoke" } } } },
          contexts = { ["light-arts"] = { [1] = { left = { [3] = { type = "ja", action = "Penury" } } } } },
        },
      }
      local binder, env = build({ files = files })
      env.bindings.update_buffs({ 358 })
      open_stack(binder, env, "left", 3)
      assert.is_false(row_named(env, "base").winner)
      assert.is_true(row_named(env, "ctx:light-arts").winner, "the live context outranks the base")
      env.bindings.update_buffs({})
      binder.refresh()
      assert.is_true(row_named(env, "base").winner, "and the base wins again when the buff drops")
    end)

    it("reports the address it is editing", function()
      local binder, env = build()
      open_stack(binder, env, "right", 1)
      assert.are.same({ set = 1, side = "right", slot = 1 }, binder.window().address)
    end)

    it("closes and clears the cursor when a click lands on nothing", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      assert.is_not_nil(binder.layer())
      click(binder, 5, 5)
      assert.is_nil(binder.window(), "the panel is gone")
      assert.is_nil(binder.layer(), "nothing is sticky")
    end)

    it("clears the cursor when another slot is clicked", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "ctx:light-arts")))
      assert.are.equal("ctx:light-arts", binder.layer())
      local x, y = slot_point(env, "left", 4)
      click(binder, x, y)
      assert.is_nil(binder.layer(), "a new slot is a new decision")
      assert.are.same({ set = 1, side = "left", slot = 4 }, binder.window().address)
    end)
  end)

  describe("the layer cursor and the catalog", function()
    it("keeps the catalog locked until a layer row is clicked", function()
      local binder, env = build()
      binder.open()
      assert.is_nil(binder.catalog_view(), "locked with no slot")
      local x, y = slot_point(env, "left", 3)
      click(binder, x, y)
      assert.is_nil(binder.catalog_view(), "still locked: no layer chosen")
      click(binder, centre(row_named(env, "base")))
      assert.is_not_nil(binder.catalog_view(), "the two-step is complete")
    end)

    it("previews a context row as a simulated buff list", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "ctx:dark-arts")))
      assert.are.same({ 359 }, last_preview(env), "dark arts alone - light arts drops out")
      -- Picking a layer moves the window on to the catalog, so choosing a
      -- different one means stepping back to the layer list first.
      back(binder, env)
      click(binder, centre(row_named(env, "ctx:addendum-white")))
      assert.are.same({ 401 }, last_preview(env), "which lights light-arts too, through any_of")
    end)

    it("views LIVE for a layer that is not a context", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      assert.is_nil(last_preview(env), "the live buff list")
      assert.are.equal("LIVE", binder.window().viewing)
      back(binder, env)
      click(binder, centre(row_named(env, "ctx:light-arts")))
      assert.are.equal("LIGHT ARTS", binder.window().viewing, "the simulated state is unmissable")
    end)

    it("binds a clicked catalog entry into the cursor's layer, and says so", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "ctx:light-arts")))
      pick(binder, env, "Berserk")
      assert.are.same(
        { type = "ja", action = "Berserk" },
        env.bindings.entry_at("ctx:light-arts:1", "left", 3),
        "into the layer under the cursor, not the base"
      )
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3), "the base survives")
      assert.is_not_nil(env.said[1]:find("light-arts", 1, true), env.said[1])
      assert.is_not_nil(env.said[1]:find("slot 3", 1, true), env.said[1])
    end)

    it("closes the catalog on a bind and leaves the stack panel refreshed in place", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      pick(binder, env, "Berserk")
      assert.is_nil(binder.catalog_view(), "the catalog closes behind the bind")
      assert.is_not_nil(binder.window(), "the stack panel stays for the next edit")
      assert.are.equal("ja Berserk", row_named(env, "base").entry, "refreshed in place")
    end)

    it("pages a catalog longer than one page and switches category", function()
      local long = {}
      for index = 1, 40 do
        long[index] = { label = ("Spell %02d"):format(index), record = { type = "ma", action = "Spell" } }
      end
      local binder, env = build({
        catalog = {
          { name = "White Magic", entries = long },
          { name = "General", entries = { { label = "Attack", record = { type = "draw" } } } },
        },
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local view = binder.catalog_view()
      assert.is_true(view.pages > 1, "40 entries do not fit one page")
      assert.are.equal(1, view.page)
      binder.mouse(WHEEL, centre(view.entries[1]))
      assert.is_not_nil(entry_named(env, "Spell 01"), "the wheel needs a direction to move")
      local first = view.entries[1]
      binder.mouse(WHEEL, first.x + 1, first.y + 1, -1)
      assert.are.equal(2, binder.catalog_view().page)
      assert.is_nil(entry_named(env, "Spell 01"), "page two starts past it")
      local categories = binder.catalog_view().categories
      click(binder, centre(categories[2]))
      assert.are.equal("General", binder.catalog_view().category)
      assert.are.equal(1, binder.catalog_view().page, "a new category starts at the top")
    end)

    it("tells the widget to repaint after every write, and only then", function()
      -- The binder owns its own panels and never the bar's slots, so a
      -- write that did not say so would leave the old action on screen.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      assert.is_nil(env.repaints, "opening and picking a layer writes nothing")
      pick(binder, env, "Berserk")
      assert.are.equal(1, env.repaints, "the bind")
      local x, y = slot_point(env, "left", 3)
      drag(binder, x, y, 4, 4)
      assert.are.equal(2, env.repaints, "the unbind")
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(LEFT_UP, x, y, 0)
      assert.are.equal(2, env.repaints, "a plain click changes nothing to repaint")
    end)

    it("draws each catalog entry's own icon, and nothing where there is none", function()
      local binder, env = build({
        catalog = {
          {
            name = "Job Abilities",
            entries = {
              { label = "Berserk", record = { type = "ja", action = "Berserk" } },
              { label = "Warcry", record = { type = "ja", action = "Warcry" } },
            },
          },
        },
        icon = function(record)
          return record.action == "Berserk" and "addon/icons/berserk.png" or nil
        end,
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local drawn = {}
      for _, prim in ipairs(env.prims.images) do
        if prim.visible and prim.last.path == "addon/icons/berserk.png" then
          drawn[#drawn + 1] = prim
        end
      end
      assert.are.equal(1, #drawn, "one icon for the one entry that resolved")
      local entry = entry_named(env, "Berserk")
      assert.are.same({ entry.x, entry.y }, { drawn[1].x, drawn[1].y }, "beside its own row")
      -- Resolving an icon walks a candidate list against the disk, and the
      -- panel redraws on every hover change: asking twice for the same
      -- record would stat the disk as fast as the mouse moves.
      local asked = env.icon_calls
      for _ = 1, 5 do
        binder.mouse(MOVE, entry.x + 1, entry.y + 1, 0)
        binder.mouse(MOVE, 4, 4, 0)
      end
      assert.are.equal(asked, env.icon_calls, "asked once per record, not once per redraw")
    end)

    --[[ The drag threshold is per ORIGIN, not per slot: a hand moves a pixel
         or two between press and release on every real click, and a panel
         row that armed a drag on that drift would lose the click entirely -
         no drop gesture starts on a row. ]]
    it("keeps a layer-row click through a pixel of drift", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      local x, y = centre(row_named(env, "ctx:light-arts"))
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(MOVE, x + 1, y + 1, 0)
      binder.mouse(LEFT_UP, x + 1, y + 1, 0)
      assert.are.equal("ctx:light-arts", binder.layer(), "the row was still clicked")
      assert.is_not_nil(binder.catalog_view(), "and the catalog unlocked behind it")
    end)

    it("keeps a category and a pager click through the same drift", function()
      local long = {}
      for index = 1, 40 do
        long[index] = { label = ("Spell %02d"):format(index), record = { type = "ma", action = "Spell" } }
      end
      local binder, env = build({
        catalog = {
          { name = "White Magic", entries = long },
          { name = "General", entries = { { label = "Attack", record = { type = "draw" } } } },
        },
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local pager = binder.catalog_view().pager
      binder.mouse(LEFT_DOWN, pager.x + 1, pager.y + 1, 0)
      binder.mouse(MOVE, pager.x + 2, pager.y + 2, 0)
      binder.mouse(LEFT_UP, pager.x + 2, pager.y + 2, 0)
      assert.are.equal(2, binder.catalog_view().page, "the pager still paged")
      local category = binder.catalog_view().categories[2]
      binder.mouse(LEFT_DOWN, category.x + 1, category.y + 1, 0)
      binder.mouse(MOVE, category.x + 2, category.y + 2, 0)
      binder.mouse(LEFT_UP, category.x + 2, category.y + 2, 0)
      assert.are.equal("General", binder.catalog_view().category, "and the category still switched")
    end)

    it("wraps the pager round the end rather than sticking on the last page", function()
      local long = {}
      for index = 1, 20 do
        long[index] = { label = ("Spell %02d"):format(index), record = { type = "ma", action = "Spell" } }
      end
      local binder, env = build({ catalog = { { name = "White Magic", entries = long } } })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      assert.are.equal(2, binder.catalog_view().pages)
      click(binder, centre(binder.catalog_view().pager))
      assert.are.equal(2, binder.catalog_view().page)
      click(binder, centre(binder.catalog_view().pager))
      assert.are.equal(1, binder.catalog_view().page, "the label says scroll, so it has to keep moving")
    end)

    it("says so when there are more categories than rows for them", function()
      -- Enough to overflow the taller window's column, whatever it holds:
      -- the count is derived from the window height now, so a fixture with
      -- a fixed number would stop testing anything the day it grew.
      local groups = {}
      for index = 1, 60 do
        groups[index] = {
          name = ("Category %02d"):format(index),
          entries = { { label = "Thing", record = { type = "draw" } } },
        }
      end
      local binder, env = build({ catalog = groups })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local view = binder.catalog_view()
      assert.is_true(#view.categories < 60, "the column is bounded")
      assert.are.equal(60 - #view.categories, view.categories_hidden, "and it counts what it cannot show")
      local header = nil
      for _, prim in ipairs(env.prims.texts) do
        if prim.visible and type(prim.last.text) == "string" and prim.last.text:find("more", 1, true) then
          header = prim.last.text
        end
      end
      assert.is_not_nil(header, "the header says how many are missing")
    end)

    it("rebuilds the catalog when the job changes under it", function()
      local built = 0
      local jobs = { "WAR" }
      local binder, env = build({
        catalog_factory = function()
          return {
            build = function()
              built = built + 1
              return {
                {
                  name = "Job Abilities",
                  entries = { { label = jobs[1] .. " thing", record = { type = "ja", action = jobs[1] } } },
                },
              }
            end,
          }
        end,
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      assert.are.equal(1, built)
      assert.is_not_nil(entry_named(env, "WAR thing"))
      jobs[1] = "MNK"
      env.bindings.set_job("MNK", "WAR")
      binder.refresh()
      assert.are.equal(2, built, "the listing is the old job's until it is rebuilt")
      assert.is_not_nil(entry_named(env, "MNK thing"))
      binder.refresh()
      assert.are.equal(2, built, "and only when the job really moved")
    end)

    it("clamps the wheel at both ends of the catalog rather than wrapping", function()
      --[[ It used to wrap, so scrolling off the end of a long list threw
           you silently back to the top and read as the list resetting
           (Kevin, 2026-08-22). ]]
      local long = {}
      for index = 1, 60 do
        long[index] = { label = ("Spell %02d"):format(index), record = { type = "ma", action = "Spell" } }
      end
      local binder, env = build({ catalog = { { name = "White Magic", entries = long } } })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local window = binder.window()
      local pages = binder.catalog_view().pages
      assert.is_true(pages > 1, "a list worth scrolling")
      binder.mouse(WHEEL, window.x + 10, window.y + 10, 1)
      assert.are.equal(1, binder.catalog_view().page, "up from the first page stays on it")
      for _ = 1, pages + 3 do
        binder.mouse(WHEEL, window.x + 10, window.y + 10, -1)
      end
      assert.are.equal(pages, binder.catalog_view().page, "and down stops on the last, never round to the top")
      binder.mouse(WHEEL, window.x + 10, window.y + 10, 1)
      assert.are.equal(pages - 1, binder.catalog_view().page, "up still steps back")
    end)

    it("echoes the bind in the plan's own shape, with no type token", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "ctx:light-arts")))
      pick(binder, env, "Berserk")
      assert.is_not_nil(
        env.said[1]:find("bound Berserk -> light-arts / set 1 / left / slot 3", 1, true),
        "said: " .. env.said[1]
      )
    end)

    it("echoes a mount by the game's own casing, not the command form", function()
      -- The one surface that produces `display` records: the catalog builds
      -- a mount as the lower-case name `/mount` takes plus the game's
      -- casing beside it, so the announcement has to read the second or it
      -- says "bound chocobo".
      local binder, env = build({
        catalog = {
          {
            name = "Mounts",
            entries = { { label = "Chocobo", record = { type = "mount", action = "chocobo", display = "Chocobo" } } },
          },
        },
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      pick(binder, env, "Chocobo")
      assert.is_not_nil(env.said[1]:find("bound Chocobo ->", 1, true), "said: " .. env.said[1])
    end)

    it("echoes an aliased record by the player's own name for it", function()
      -- And the alias outranks it: the player's label is the top of the
      -- chain everywhere else, and the echo must not be the exception.
      local binder, env = build({
        catalog = {
          {
            name = "Mounts",
            entries = {
              {
                label = "Chocobo",
                record = { type = "mount", action = "chocobo", display = "Chocobo", alias = "Pull mount" },
              },
            },
          },
        },
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      pick(binder, env, "Chocobo")
      assert.is_not_nil(env.said[1]:find("bound Pull mount ->", 1, true), "said: " .. env.said[1])
    end)

    it("binds a copy of the catalog entry, not the entry itself", function()
      -- Stored by reference, one catalog record would back every slot bound
      -- from it: a later `alias` on one slot would rename them all, and the
      -- catalog's own listing with them.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local entry = entry_named(env, "Berserk")
      click(binder, centre(entry))
      click(binder, slot_point(env, "left", 4))
      click(binder, centre(row_named(env, "base")))
      pick(binder, env, "Berserk")
      local first = env.bindings.entry_at("1", "left", 3)
      first.alias = "Rage"
      assert.is_nil(env.bindings.entry_at("1", "left", 4).alias, "the other slot kept its own record")
      assert.is_nil(entry.record.alias, "and so did the catalog")
    end)

    it("labels and writes an empty shared set's base row as shared", function()
      -- The set's own flag is the truth, not whether a layer happens to
      -- hold an entry: an empty shared set would otherwise say `base` while
      -- the write landed in SHARED.
      local binder, env = build({ shared_sets = { 1 } })
      open_stack(binder, env, "left", 3)
      assert.are.equal("shared", row_named(env, "base").label)
      click(binder, centre(row_named(env, "base")))
      pick(binder, env, "Berserk")
      assert.is_not_nil(env.said[1]:find("-> shared /", 1, true), "said: " .. env.said[1])
      assert.are.same(
        { type = "ja", action = "Berserk" },
        env.files.SHARED.sets[1].left[3],
        "and the write really landed in SHARED"
      )
    end)

    it("binds through the WORN subjob's row, leaving another subjob's layer alone", function()
      local files = {
        WAR = {
          sets = { [1] = { left = { [3] = { type = "ja", action = "Provoke" } } } },
          -- One stale subjob layer either side of the worn one in sort
          -- order: a row that took whichever it saw last would show the
          -- wrong entry under the worn subjob's own label.
          sub = {
            NIN = { [1] = { left = { [3] = { type = "ma", action = "Utsusemi: Ichi" } } } },
            DRK = { [1] = { left = { [3] = { type = "ja", action = "Last Resort" } } } },
            WHM = { [1] = { left = { [3] = { type = "ma", action = "Cure" } } } },
          },
        },
      }
      local binder, env = build({ files = files })
      open_stack(binder, env, "left", 3)
      local row = row_named(env, "sub")
      assert.are.equal("sub:NIN", row.label, "the worn subjob names the row")
      assert.are.equal("ma Utsusemi: Ichi", row.entry, "and a stale subjob's entry is not shown under it")
      click(binder, centre(row))
      pick(binder, env, "Berserk")
      assert.are.same({ type = "ja", action = "Berserk" }, env.files.WAR.sub.NIN[1].left[3])
      assert.are.same(
        { type = "ja", action = "Last Resort" },
        env.files.WAR.sub.DRK[1].left[3],
        "the layer of a subjob nobody is wearing is untouched"
      )
      assert.are.same({ type = "ma", action = "Cure" }, env.files.WAR.sub.WHM[1].left[3], "either side of it")
    end)

    it("replaces an occupied slot in one write, never clearing first", function()
      local writes = {}
      local binder, env = build()
      local saved = env.bindings.bind
      env.bindings.bind = function(...)
        writes[#writes + 1] = select(4, ...)
        return saved(...)
      end
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      pick(binder, env, "Berserk")
      assert.are.equal(1, #writes, "one write, not a clear and an insert")
      assert.are.same({ type = "ja", action = "Berserk" }, writes[1])
    end)
  end)

  describe("drag and drop", function()
    it("no longer binds a catalog entry dragged onto a slot", function()
      --[[ Drag-to-bind is gone with the wizard (Kevin, 2026-08-22): the
           three steps are the way in, and a drag that half-bound something
           (no target step, no confirmation) would be a second, quieter path
           that could disagree with them. Swap and clear survive, because
           the wizard has no equivalent for either. ]]
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "ctx:light-arts")))
      local from_x, from_y = centre(entry_named(env, "Berserk"))
      local to_x, to_y = slot_point(env, "right", 2)
      drag(binder, from_x, from_y, to_x, to_y)
      assert.is_nil(env.bindings.entry_at("ctx:light-arts:1", "right", 2), "nothing was bound")
      assert.are.equal("ctx:light-arts", binder.layer(), "and the cursor is where it was")
    end)

    it("abandons a catalog drag dropped on nothing", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local from_x, from_y = centre(entry_named(env, "Berserk"))
      drag(binder, from_x, from_y, 4, 4)
      assert.are.equal(0, #env.said, "silently abandoned")
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3), "nothing moved")
    end)

    it("swaps whole stacks when a slot is dropped on another slot", function()
      local files = {
        WAR = {
          sets = {
            [1] = {
              left = { [3] = { type = "ja", action = "Provoke" } },
              right = { [2] = { type = "ws", action = "Savage Blade" } },
            },
          },
          contexts = { ["light-arts"] = { [1] = { left = { [3] = { type = "ja", action = "Penury" } } } } },
        },
      }
      local binder, env = build({ files = files })
      binder.open()
      local from_x, from_y = slot_point(env, "left", 3)
      local to_x, to_y = slot_point(env, "right", 2)
      drag(binder, from_x, from_y, to_x, to_y)
      assert.are.same({ type = "ws", action = "Savage Blade" }, env.bindings.entry_at("1", "left", 3))
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "right", 2))
      assert.are.same(
        { type = "ja", action = "Penury" },
        env.bindings.entry_at("ctx:light-arts:1", "right", 2),
        "the whole stack travels, not just the winner"
      )
    end)

    it("clears only the cursor's layer when a slot is dropped on nothing", function()
      local files = {
        WAR = {
          sets = { [1] = { left = { [3] = { type = "ja", action = "Provoke" } } } },
          contexts = { ["light-arts"] = { [1] = { left = { [3] = { type = "ja", action = "Penury" } } } } },
        },
      }
      local binder, env = build({ files = files })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "ctx:light-arts")))
      local from_x, from_y = slot_point(env, "left", 3)
      drag(binder, from_x, from_y, 4, 4)
      assert.is_nil(env.bindings.entry_at("ctx:light-arts:1", "left", 3), "the cursor's layer is cleared")
      assert.are.same(
        { type = "ja", action = "Provoke" },
        env.bindings.entry_at("1", "left", 3),
        "and every other layer survives - a drag can never wipe a stack"
      )
    end)

    it("cancels a slot drag dropped onto the binder's own window", function()
      -- Only genuinely empty space clears; the window fills the middle of
      -- the screen, so a drop landing on it is the commonest miss there is.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local x, y = slot_point(env, "left", 3)
      local window = binder.window()
      env.said = {}
      drag(binder, x, y, centre(window))
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3), "over the list")
      assert.are.same({}, env.said, "and quietly - a cancel says nothing")
      -- The details column too: it is part of the window now rather than a
      -- panel of its own, but a drop there must still not delete.
      drag(binder, x, y, window.details.x + 10, window.details.y + 10)
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3), "over the details")
      assert.are.same({}, env.said)
      drag(binder, x, y, 4, 4)
      assert.is_nil(env.bindings.entry_at("1", "left", 3), "and empty space still clears the cursor's layer")
    end)

    it("clears nothing at all with no layer selected", function()
      local binder, env = build()
      binder.open()
      local from_x, from_y = slot_point(env, "left", 3)
      drag(binder, from_x, from_y, 4, 4)
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3))
    end)

    it("reads a press that never leaves its slot as a click", function()
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 3)
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(MOVE, x + 2, y + 2, 0)
      binder.mouse(LEFT_UP, x + 2, y + 2, 0)
      assert.is_not_nil(binder.window(), "a zero-distance drag is a click, and opens the panel")
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3), "and moves nothing")
    end)

    it("leaves a drop back on the origin slot alone", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local x, y = slot_point(env, "left", 3)
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(MOVE, 4, 4, 0)
      binder.mouse(MOVE, x, y, 0)
      binder.mouse(LEFT_UP, x, y, 0)
      assert.are.same(
        { type = "ja", action = "Provoke" },
        env.bindings.entry_at("1", "left", 3),
        "dragged out and back is not a delete"
      )
      assert.are.same({}, env.said, "and says nothing either")
    end)
  end)

  describe("tooltips", function()
    it("describes a hovered slot from known data, with its layer", function()
      local binder, env = build()
      env.describe = function(record)
        return {
          name = record.action,
          type = record.type,
          target = "me",
          mp_cost = 8,
          recast = 30,
          property = "Fusion",
        }
      end
      binder.open()
      local x, y = slot_point(env, "left", 3)
      binder.mouse(MOVE, x, y, 0)
      local tooltip = binder.details()
      assert.is_not_nil(tooltip, "hovering a slot opens one")
      local text = table.concat(tooltip.lines, "\n")
      for _, wanted in ipairs({ "Provoke", "ja", "me", "8", "30", "Fusion", "base" }) do
        assert.is_not_nil(text:find(wanted, 1, true), wanted .. " missing from: " .. text)
      end
    end)

    it("names the layers a slot's winner covers", function()
      local files = {
        WAR = {
          sets = { [1] = { left = { [3] = { type = "ja", action = "Provoke" } } } },
          contexts = { ["light-arts"] = { [1] = { left = { [3] = { type = "ja", action = "Penury" } } } } },
        },
      }
      local binder, env = build({ files = files })
      env.bindings.update_buffs({ 358 })
      binder.open()
      local x, y = slot_point(env, "left", 3)
      binder.mouse(MOVE, x, y, 0)
      local text = table.concat(binder.details().lines, "\n")
      assert.is_not_nil(text:find("covers", 1, true), text)
      assert.is_not_nil(text:find("base", 1, true), text)
    end)

    it("follows the cursor between targets and clears when it leaves", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local x, y = slot_point(env, "left", 3)
      binder.mouse(MOVE, x, y, 0)
      assert.is_not_nil(binder.details(), "a slot tooltip")
      local entry = entry_named(env, "Berserk")
      binder.mouse(MOVE, centre(entry))
      assert.is_not_nil(table.concat(binder.details().lines, "\n"):find("Berserk", 1, true))
      binder.mouse(MOVE, 4, 4, 0)
      assert.is_nil(binder.details(), "off every target, the tooltip goes")
    end)

    it("re-reads between two slots holding the same action", function()
      --[[ Edit mode draws every side, so the same action on two slots is
           ordinary. The details column does not move any more - it is a
           fixed part of the window - so what has to change is the KEY it
           was built from: a gate on the text alone would leave the column
           describing the slot the cursor has left, and with two identical
           actions nothing on screen would give it away. ]]
      local files = {
        WAR = {
          sets = {
            [1] = { left = { [3] = { type = "ja", action = "Provoke" }, [4] = { type = "ja", action = "Provoke" } } },
          },
        },
      }
      local binder, env = build({ files = files })
      -- The details column lives IN the window, so there has to be one: edit
      -- mode alone draws nothing until a slot is clicked.
      open_stack(binder, env, "left", 3)
      binder.mouse(MOVE, slot_point(env, "left", 3))
      local first = binder.details()
      binder.mouse(MOVE, slot_point(env, "left", 4))
      local second = binder.details()
      assert.is_not_nil(second)
      assert.are_not.equal(first.key, second.key, "a different slot, even reading the same")
      local drawn = nil
      for _, prim in ipairs(env.prims.texts) do
        if prim.visible and prim.last.text == "Provoke" then
          drawn = prim
        end
      end
      assert.is_not_nil(drawn, "and it is really drawn there")
      assert.are.equal(binder.window().details.y, drawn.y, "at the top of the details column")
    end)

    it("reads a recast as time left, and zero as ready", function()
      local binder, env = build()
      env.describe = function(record)
        return { name = record.action, type = record.type, recast = 12 }
      end
      binder.open()
      binder.mouse(MOVE, slot_point(env, "left", 3))
      assert.is_not_nil(table.concat(binder.details().lines, "\n"):find("12s left", 1, true))
      env.describe = function(record)
        return { name = record.action, type = record.type, recast = 0 }
      end
      binder.mouse(MOVE, 4, 4, 0)
      binder.mouse(MOVE, slot_point(env, "left", 3))
      local text = table.concat(binder.details().lines, "\n")
      assert.is_not_nil(text:find("ready", 1, true), text)
      assert.is_nil(text:find("0s", 1, true), "zero is not 'no cooldown': " .. text)
    end)

    it("re-reads between two catalog entries carrying the same label", function()
      -- The same gate as the slots, on the other surface: a text comparison
      -- would leave the column describing the row already left.
      local binder, env = build({
        catalog = {
          {
            name = "Job Abilities",
            entries = {
              { label = "Berserk", record = { type = "ja", action = "Berserk" } },
              { label = "Berserk", record = { type = "ja", action = "Berserk" } },
            },
          },
        },
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local entries = binder.catalog_view().entries
      binder.mouse(MOVE, centre(entries[1]))
      local first = binder.details()
      binder.mouse(MOVE, centre(entries[2]))
      local second = binder.details()
      assert.is_not_nil(second)
      assert.are_not.equal(first.key, second.key, "a different row, even reading the same")
    end)

    it("resolves a hovered target once, not once per mouse move", function()
      -- Every rebuild walks layers_at and describe; a cursor resting on a
      -- slot moves dozens of times a second.
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 3)
      binder.mouse(MOVE, x, y, 0)
      local asked = env.describe_calls
      assert.is_true(asked > 0, "the first move resolved it")
      for offset = 1, 6 do
        binder.mouse(MOVE, x + offset, y + offset, 0)
      end
      assert.are.equal(asked, env.describe_calls, "still the same slot")
      binder.mouse(MOVE, slot_point(env, "left", 4))
      binder.mouse(MOVE, x, y, 0)
      assert.is_true(env.describe_calls > asked, "and a real change resolves again")
    end)

    it("rebuilds a resting tooltip on demand, so a countdown does not freeze", function()
      local binder, env = build()
      local remaining = 30
      env.describe = function(record)
        return { name = record.action, type = record.type, recast = remaining }
      end
      binder.open()
      binder.mouse(MOVE, slot_point(env, "left", 3))
      assert.is_not_nil(table.concat(binder.details().lines, "\n"):find("30s left", 1, true))
      remaining = 12
      binder.refresh_details()
      assert.is_not_nil(table.concat(binder.details().lines, "\n"):find("12s left", 1, true), "the cursor never moved")
      assert.has_no.errors(function()
        binder.mouse(MOVE, 4, 4, 0)
        binder.refresh_details()
      end, "and with nothing hovered it is a no-op")
      assert.is_nil(binder.details())
    end)

    it("keeps a tooltip down while a drag is live, cadence or no cadence", function()
      -- The cadence rebuild must not resurrect what the drag stood down:
      -- a tooltip under the cursor at release time is a surface the drop
      -- has to reason about, and the whole point of standing it down is
      -- that it does not have to.
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 3)
      binder.mouse(MOVE, x, y, 0)
      assert.is_not_nil(binder.details())
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(MOVE, 500, 500, 0)
      assert.is_nil(binder.details(), "the drag stood it down")
      binder.refresh_details()
      assert.is_nil(binder.details(), "and the cadence leaves it down")
    end)

    it("does not float the tooltip of a catalog row the bind closed", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local entry = entry_named(env, "Berserk")
      binder.mouse(MOVE, centre(entry))
      assert.is_not_nil(binder.details())
      click(binder, centre(entry))
      assert.is_nil(binder.catalog_view(), "the bind closed the catalog")
      assert.is_nil(binder.details(), "so the row it described is gone too")
      binder.refresh_details()
      assert.is_nil(binder.details(), "and the cadence does not bring it back")
    end)

    it("treats its own details column as a surface, never as empty space", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      binder.mouse(MOVE, slot_point(env, "left", 3))
      assert.is_not_nil(binder.details())
      local window = binder.window()
      local x, y = window.details.x + 10, window.details.y + 10
      assert.is_false(binder.mouse(MOVE, x, y, 0), "moving onto it is not a hover of something else")
      assert.is_true(binder.mouse(LEFT_DOWN, x, y, 0), "the column is one of ours")
      assert.is_true(binder.mouse(LEFT_UP, x, y, 0))
      assert.is_not_nil(binder.window(), "so a press on it never reads as a dismissing click")
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3))
      assert.are.same({}, env.said)
    end)

    it("says nothing about an empty slot", function()
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 8)
      binder.mouse(MOVE, x, y, 0)
      assert.is_nil(binder.details(), "there is nothing known about an unbound slot")
    end)
  end)

  describe("source tags", function()
    it("marks the subjob and context layers, and leaves the base bare", function()
      local binder = build()
      assert.are.equal("", binder.mark("base"))
      assert.are.equal("", binder.mark("shared"))
      assert.are.equal("+", binder.mark("sub"))
      assert.are.equal("*", binder.mark("ctx:light-arts"))
      assert.are.equal("", binder.mark(nil))
    end)
  end)

  describe("the mouse, defensively", function()
    it("ignores a click outside every surface", function()
      local binder = build()
      binder.open()
      assert.is_false(binder.mouse(LEFT_DOWN, 1900, 20, 0), "the game keeps its own clicks")
      assert.is_false(binder.mouse(LEFT_DOWN, -50, -50, 0), "negative coordinates are nobody's slot")
      assert.is_false(binder.mouse(LEFT_DOWN, 100000, 100000, 0))
    end)

    it("stays centred when the anchor moves under it", function()
      --[[ The panel used to open beside its slot and be re-read every
           refresh, so `//hud slot <name>` could not strand it at the old
           coordinates. It is dead-centre now (Kevin, 2026-08-22), so the
           anchor moving is not its business at all - and the neighbouring
           slots' labels, which draw over any backdrop because Windower
           puts every text above every image, are nowhere near it. ]]
      local origin = { x = ANCHOR_X, y = ANCHOR_Y }
      local binder, env = build({
        groups = function()
          return {
            {
              key = "xhb_left",
              bar = "xhb",
              side = "left",
              render_side = "left",
              x = origin.x,
              y = origin.y,
              scale = 1,
              set = 1,
            },
          }
        end,
      })
      binder.open()
      click(binder, slot_point(env, "left", 3))
      local before = binder.window().x
      assert.are.equal(math.floor(1920 / 2 - binder.window().width / 2), before, "centred to begin with")
      origin.x = origin.x + 300
      binder.refresh()
      assert.are.equal(before, binder.window().x, "and it does not chase the anchor")
    end)

    it("claims the wheel over its own panels", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      local x, y = centre(binder.window())
      assert.is_true(binder.mouse(WHEEL, x, y, -1), "the game must not zoom under an open panel")
      assert.is_false(binder.mouse(WHEEL, 4, 4, -1), "elsewhere the wheel is the client's")
    end)

    it("holds a slot's edges half-open in both axes", function()
      -- Abutting rects must not both claim a pixel, and neither axis may be
      -- the only one checked.
      local binder, env = build()
      binder.open()
      local x, y = env.render.slot_pos("xhb", "left", 3)
      local size = env.render.metrics().slot
      local left, top = ANCHOR_X + x, ANCHOR_Y + y
      assert.is_true(binder.mouse(LEFT_DOWN, left, top, 0), "the top-left corner is inside")
      binder.mouse(LEFT_UP, left, top, 0)
      assert.is_false(binder.mouse(LEFT_DOWN, left + size, top, 0), "one past the right edge is not")
      assert.is_false(binder.mouse(LEFT_DOWN, left, top + size, 0), "nor one past the bottom")
      assert.is_false(binder.mouse(LEFT_DOWN, left - 1, top, 0), "nor one short of the left")
      assert.is_false(binder.mouse(LEFT_DOWN, left, top - 1, 0), "nor one above the top")
    end)

    it("ignores the right button and unknown event types", function()
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 3)
      assert.is_false(binder.mouse(RIGHT_DOWN, x, y, 0), "right-click is not the binder's gesture")
      assert.is_false(binder.mouse(99, x, y, 0))
      assert.is_nil(binder.window())
    end)

    it("ignores every event once closed, mid-gesture included", function()
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 3)
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.close()
      assert.is_false(binder.mouse(MOVE, x + 400, y, 0))
      assert.is_false(binder.mouse(LEFT_UP, x + 400, y, 0))
      binder.open()
      assert.is_nil(binder.window(), "the interrupted press did not survive the close")
    end)

    --[[ Motion is the client's unless a real drag is live - layout_mode's
         own convention (it blocks a MOVE only while a grab is armed). A
         binder that swallowed motion for a press it declined would freeze
         the camera until a LEFT_UP that may never arrive. ]]
    it("declines a press on nothing without swallowing the motion after it", function()
      local binder = build()
      binder.open()
      assert.is_false(binder.mouse(LEFT_DOWN, 4, 4, 0), "not ours")
      assert.is_false(binder.mouse(MOVE, 500, 500, 0), "and neither is the motion that follows")
      assert.is_false(binder.mouse(LEFT_UP, 500, 500, 0))
    end)

    it("leaves motion alone until a press really becomes a drag", function()
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 3)
      binder.mouse(LEFT_DOWN, x, y, 0)
      assert.is_false(binder.mouse(MOVE, x + 1, y + 1, 0), "still a click, not a drag")
      assert.is_true(binder.mouse(MOVE, 500, 500, 0), "off the slot: now it is a drag")
    end)

    it("recovers when a release never arrives", function()
      -- Released off-window, or consumed by an addon ahead of us: the next
      -- press supersedes the stranded one rather than inheriting it.
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 3)
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(MOVE, 500, 500, 0)
      binder.mouse(LEFT_DOWN, 4, 4, 0)
      assert.is_false(binder.mouse(MOVE, 520, 520, 0), "the stranded drag is gone with it")
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3), "and cleared nothing")
    end)

    it("survives a release with no press and a press with no release", function()
      local binder, env = build()
      binder.open()
      local x, y = slot_point(env, "left", 3)
      assert.is_false(binder.mouse(LEFT_UP, x, y, 0), "a release we never armed is the game's")
      assert.is_nil(binder.window())
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(LEFT_DOWN, x, y, 0)
      assert.is_true(binder.mouse(LEFT_UP, x, y, 0), "the second press replaces the first")
      assert.is_not_nil(binder.window())
    end)

    it("resolves a drag that leaves the window", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local x, y = slot_point(env, "left", 3)
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(MOVE, -400, -400, 0)
      binder.mouse(LEFT_UP, -400, -400, 0)
      assert.is_nil(env.bindings.entry_at("1", "left", 3), "off-window is 'anywhere else': the layer is cleared")
    end)

    it("centres the catalog wherever the bar happens to be", function()
      --[[ The catalog used to dodge the bar, because hit() checks it before
           the slots and so a catalog covering one makes it undroppable.
           Dead-centre unconditionally is the call (Kevin, 2026-08-22):
           predictable placement is worth more than drag-to-slot surviving a
           centred bar, which is not where a bar is put. The bar here is at
           the very top, exactly where the old rule would have pushed the
           catalog down. ]]
      local binder, env = build({
        groups = function()
          return {
            { key = "xhb_left", bar = "xhb", side = "left", render_side = "left", x = 100, y = 10, scale = 1, set = 1 },
          }
        end,
      })
      binder.open()
      local x, y = env.render.slot_pos("xhb", "left", 3)
      click(binder, 100 + x + 20, 10 + y + 20)
      click(binder, centre(row_named(env, "base")))
      assert.are.equal(
        math.floor(1080 / 2 - binder.window().height / 2),
        binder.window().y,
        "vertically centred, bar or no bar"
      )
    end)

    it("opens one window dead-centre and never moves it between steps", function()
      --[[ Beside-the-slot put it under the neighbouring slots' labels, and
           Windower draws every text above every image, so no ordering trick
           could lift a backdrop clear of them. Centring is the fix; the
           window staying PUT across the steps is the other half, or every
           choice would shift the thing under the cursor. ]]
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      local window = binder.window()
      assert.are.equal(math.floor(1920 / 2 - window.width / 2), window.x, "dead-centre")
      assert.are.equal(math.floor(1080 / 2 - window.height / 2), window.y)
      assert.is_not_nil(binder.layer_view(), "step one")
      assert.is_nil(binder.catalog_view())

      click(binder, centre(row_named(env, "base")))
      assert.is_not_nil(binder.catalog_view(), "step two")
      assert.is_nil(binder.layer_view(), "one step at a time")
      assert.are.same({ window.x, window.y }, { binder.window().x, binder.window().y }, "same window, same place")

      click(binder, centre(entry_named(env, "Berserk")))
      assert.is_not_nil(binder.target_view(), "step three, for a type that takes a target")
      assert.is_nil(binder.catalog_view())
      assert.are.same({ window.x, window.y }, { binder.window().x, binder.window().y })
    end)

    it("walks back a step at a time, and closes from the X", function()
      --[[ Every step needs a way out that is not "click empty space and
           hope" - which on a screen this full is also the gesture that
           clears a slot (Kevin, 2026-08-22). Back retreats one step; the X
           in the top right closes outright (Kevin, 2026-08-31). ]]
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      click(binder, centre(entry_named(env, "Berserk")))
      assert.is_not_nil(binder.target_view(), "three steps in")

      back(binder, env)
      assert.is_not_nil(binder.catalog_view(), "back to the actions")
      assert.is_nil(binder.target_view())
      back(binder, env)
      assert.is_not_nil(binder.layer_view(), "back to the layers")
      assert.is_nil(binder.layer(), "and the layer choice is released with it")
      close_button(binder, env)
      assert.is_nil(binder.window(), "and the X closes the window")
      assert.are.same({}, env.said, "walking back binds nothing and says nothing")
    end)

    it("closes from the X on a later step too, without binding anything", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      assert.is_not_nil(binder.catalog_view(), "two steps in")
      close_button(binder, env)
      assert.is_nil(binder.window(), "the X does not retreat, it closes")
      assert.are.same({}, env.said)
    end)

    it("draws no back button on the first step, and nothing hit-testable where it was", function()
      --[[ The first step has nothing to retreat to, so back is not drawn
           there rather than sitting dead (Kevin, 2026-08-31). The space it
           leaves is inert panel, NOT empty space - a click there must not
           read as the gesture that clears a slot. ]]
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      assert.is_nil(binder.window().back, "no back rect on the first step")
      local window = binder.window()
      click(binder, window.x + 20, window.y + 20)
      assert.is_not_nil(binder.window(), "a click where back used to be leaves the window open")

      click(binder, centre(row_named(env, "base")))
      assert.is_not_nil(binder.window().back, "and it returns once there is a step to retreat to")
    end)

    it("takes the back button down again when it retreats to the first step", function()
      -- Hidden, not merely left unaddressed: a stale `[ < back ]` painted
      -- over the first step is the dead-looking button this change removed.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      assert.is_not_nil(shown_text(env, "[ < back ]"), "drawn on the second step")
      back(binder, env)
      assert.is_nil(binder.window().back, "the first step has no rect for it")
      assert.is_nil(shown_text(env, "[ < back ]"), "nor a prim left painted where it was")
    end)

    it("takes both controls off screen with the window, edit mode still up", function()
      -- The X closes the WINDOW; edit mode and its prims outlive it, so
      -- every one of them has to be hidden or it floats over the bar.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      assert.is_not_nil(shown_text(env, "[ X ]"), "up while the window is")
      close_button(binder, env)
      assert.is_true(binder.active(), "edit mode outlives the window")
      assert.is_nil(binder.window())
      assert.is_nil(shown_text(env, "[ X ]"), "no orphan control left over the bar")
      assert.is_nil(shown_text(env, "[ < back ]"))
    end)

    it("drops the hovered details and the layer preview when the X closes the window", function()
      -- Back cleared both on its way out and the X replaces it on the first
      -- step, so what a closed window was describing - and the buff list it
      -- had the bar previewing - go with it.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "ctx:light-arts")))
      binder.mouse(MOVE, centre(entry_named(env, "Berserk")))
      assert.is_not_nil(binder.details(), "the column is describing a row")
      assert.is_not_nil(last_preview(env), "and the bar is previewing the layer")

      env.previews = {}
      close_button(binder, env)
      assert.is_nil(binder.details(), "the details go with the window")
      assert.are.equal(1, #env.previews, "the preview is handed back")
      assert.is_nil(last_preview(env), "to the live buff list")
    end)

    it("closes from the target step, the one with a bind half-made", function()
      -- The only step holding a `pending` record: closing must drop it
      -- rather than commit it.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      click(binder, centre(entry_named(env, "Berserk")))
      assert.is_not_nil(binder.target_view(), "three steps in")
      close_button(binder, env)
      assert.is_nil(binder.window())
      assert.are.same({}, env.said, "nothing was bound on the way out")
      assert.are.same({ type = "ja", action = "Provoke" }, env.files.WAR.sets[1].left[3], "and the slot is untouched")
    end)

    it("puts the X in the top right, level with back, and labels both", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      assert.is_not_nil(shown_text(env, "[ X ]"), "the X is up from the first step")
      assert.is_nil(shown_text(env, "[ close ]"), "which replaced the old top-left label")
      assert.is_nil(shown_text(env, "[ < back ]"), "and back is not drawn there")

      click(binder, centre(row_named(env, "base")))
      local window = binder.window()
      assert.is_not_nil(shown_text(env, "[ < back ]"), "back is up on the second step")
      assert.is_not_nil(shown_text(env, "[ X ]"), "and the X stays on every step")
      assert.are.equal(window.back.y, window.close.y, "both sit on the header row")
      assert.are.equal(
        window.back.x - window.x,
        window.x + window.width - (window.close.x + window.close.width),
        "the X is inset from the right edge exactly as back is from the left"
      )
    end)

    it("binds the target picked on the third step", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      click(binder, centre(entry_named(env, "Berserk")))
      click(binder, centre(target_named(env, "<me>")))
      assert.are.same({ type = "ja", action = "Berserk", target = "me" }, env.bindings.entry_at("1", "left", 3))
      -- And it lands back on the layer list, ready for the next edit on the
      -- same slot rather than closing out from under you.
      assert.is_not_nil(binder.layer_view(), "back to step one")
    end)

    it("offers every target token, not just the common few", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      click(binder, centre(entry_named(env, "Berserk")))
      local seen = {}
      local view = binder.target_view()
      for page = 1, view.pages do
        for _, row in ipairs(binder.target_view().targets) do
          seen[row.label] = true
        end
        if page < view.pages then
          local window = binder.window()
          binder.mouse(WHEEL, window.x + 10, window.y + 10, -1)
        end
      end
      for _, label in ipairs({ "(no target)", "<t>", "<me>", "<bt>", "<st>", "<pet>", "<p5>", "<a15>", "<a25>" }) do
        assert.is_true(seen[label] == true, "missing " .. label)
      end
    end)

    it("skips the target step for a type that cannot take one", function()
      -- Asking which mob to aim a menu at would be nonsense, so `draw`,
      -- `open` and the rest bind where they stand.
      local binder, env = build({
        catalog = { { name = "General", entries = { { label = "Draw", record = { type = "draw" } } } } },
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      click(binder, centre(entry_named(env, "Draw")))
      assert.is_nil(binder.target_view(), "no third step")
      assert.are.same({ type = "draw" }, env.bindings.entry_at("1", "left", 3), "bound straight away")
      assert.is_not_nil(binder.layer_view(), "and back to step one")
    end)

    it("draws at its own point size, not the bar's", function()
      -- The window is deliberately much larger than the bar, whose 10pt is
      -- unreadable at this scale - so the FAMILY comes from the widget's
      -- style and the size does not.
      local binder, env = build()
      binder.open()
      assert.is_true(#env.prims.texts > 0, "there are texts to check")
      for _, prim in ipairs(env.prims.texts) do
        assert.are.equal(18, prim.font_size)
      end
    end)

    it("wraps a details line too long for its column", function()
      --[[ The SC row found this in a live client: an action with two chain
           properties ran straight off the backdrop (Kevin, 2026-08-22).
           Windower's text objects do not measure and our prim wrapper
           exposes no extents, so the budget is an estimate from the point
           size - deliberately conservative, because a line that stops short
           looks tidy and one that overruns does not. ]]
      local binder, env = build({
        describe = function(record)
          return {
            name = record.action,
            type = record.type,
            property = { "Fusion", "Impaction", "Liquefaction", "Detonation" },
          }
        end,
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      binder.mouse(MOVE, centre(entry_named(env, "Berserk")))
      local lines = binder.details().lines
      local joined = table.concat(lines, " ")
      assert.is_not_nil(joined:find("Fusion", 1, true), "all four properties survive the wrap")
      assert.is_not_nil(joined:find("Detonation", 1, true))
      for _, line in ipairs(lines) do
        assert.is_true(#line <= binder.detail_columns(), "over the column: '" .. line .. "'")
      end
    end)

    it("does not cut a single long word mid-name", function()
      -- A name broken in half reads as a different item; better to overrun
      -- one line than to invent one.
      local binder, env = build({
        describe = function(record)
          return { name = ("W"):rep(80), type = record.type }
        end,
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      binder.mouse(MOVE, centre(entry_named(env, "Berserk")))
      assert.are.equal(("W"):rep(80), binder.details().lines[1])
    end)

    it("leaves a line whole when the only break in it is too early to help", function()
      --[[ Breaking at column 2 would leave the continuation as long as the
           line it came from, so the wrap would eat its row budget without
           shortening anything and emit a column of fragments. Such a line
           is emitted whole instead, overrun and all. ]]
      local awkward = "A " .. ("W"):rep(60)
      local binder, env = build({
        describe = function(record)
          return { name = awkward, type = record.type }
        end,
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      binder.mouse(MOVE, centre(entry_named(env, "Berserk")))
      assert.are.equal(awkward, binder.details().lines[1])
    end)

    it("drags by its title strip and remembers where it was left", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      local before = binder.window()
      -- Grab the strip to the right of the back button and pull it up-left.
      local grab_x, grab_y = before.header.x + 20, before.header.y + 5
      binder.mouse(LEFT_DOWN, grab_x, grab_y, 0)
      binder.mouse(MOVE, grab_x - 200, grab_y - 150, 0)
      assert.are.same(
        { before.x - 200, before.y - 150 },
        { binder.window().x, binder.window().y },
        "it follows the cursor, keeping the grab point under it"
      )
      binder.mouse(LEFT_UP, grab_x - 200, grab_y - 150, 0)
      assert.are.same({ x = before.x - 200, y = before.y - 150 }, env.window_pos, "and the drop saved it")

      -- A fresh binder over the same config opens where it was left, not
      -- back in the middle.
      local again, env2 = build()
      env2.window_pos = env.window_pos
      open_stack(again, env2, "left", 3)
      assert.are.same({ before.x - 200, before.y - 150 }, { again.window().x, again.window().y })
    end)

    it("does not drag from the back button", function()
      -- Back is checked first, so a slip on it must still be back rather
      -- than a grab of the window behind it. Read on the second step: the
      -- first does not draw back at all.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      local before = binder.window()
      local x, y = centre(before.back)
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(MOVE, x - 200, y - 150, 0)
      assert.is_not_nil(binder.window(), "still open")
      assert.are.same({ before.x, before.y }, { binder.window().x, binder.window().y }, "and it did not move")
      assert.is_nil(env.window_pos, "nothing was saved")
    end)

    it("does not drag from the close button", function()
      -- The X sits INSIDE the header strip, so it has to be checked before
      -- it: a slip on the one control that always gets you out must not
      -- become a grab of the window behind it.
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      local before = binder.window()
      local x, y = centre(before.close)
      binder.mouse(LEFT_DOWN, x, y, 0)
      binder.mouse(MOVE, x - 200, y - 150, 0)
      assert.is_not_nil(binder.window(), "still open")
      assert.are.same({ before.x, before.y }, { binder.window().x, binder.window().y }, "and it did not move")
      assert.is_nil(env.window_pos, "nothing was saved")
    end)

    it("keeps a dragged window on screen, and clamps a stored one that is not", function()
      local binder, env = build()
      open_stack(binder, env, "left", 3)
      local before = binder.window()
      local grab_x, grab_y = before.header.x + 20, before.header.y + 5
      binder.mouse(LEFT_DOWN, grab_x, grab_y, 0)
      binder.mouse(MOVE, grab_x - 5000, grab_y - 5000, 0)
      assert.are.same({ 0, 0 }, { binder.window().x, binder.window().y }, "off the top left is pinned to it")
      binder.mouse(MOVE, grab_x + 5000, grab_y + 5000, 0)
      assert.are.same(
        { 1920 - before.width, 1080 - before.height },
        { binder.window().x, binder.window().y },
        "and off the bottom right to that corner"
      )
      binder.mouse(LEFT_UP, grab_x + 5000, grab_y + 5000, 0)

      --[[ A position saved at one resolution and opened at another would
           otherwise leave the window unreachable, with no way back to it -
           there is no keyboard in edit mode to recentre with. ]]
      local again, env2 = build()
      env2.window_pos = { x = 9000, y = 9000 }
      open_stack(again, env2, "left", 3)
      assert.are.same({ 1920 - before.width, 1080 - before.height }, { again.window().x, again.window().y })
    end)

    it("hit-tests through the drawn geometry, so an unplaced bar catches nothing", function()
      local binder, env = build({
        groups = function()
          return {}
        end,
      })
      binder.open()
      local x, y = slot_point(env, "left", 3)
      assert.is_false(binder.mouse(LEFT_DOWN, x, y, 0), "nothing is drawn there")
      assert.is_nil(binder.window())
    end)

    it("follows a scaled anchor's slots", function()
      local binder, env = build({
        groups = function()
          return {
            { key = "xhb_left", bar = "xhb", side = "left", x = ANCHOR_X, y = ANCHOR_Y, scale = 2, set = 1 },
          }
        end,
      })
      binder.open()
      local x, y = env.render.slot_pos("xhb", "left", 3)
      local size = env.render.metrics().slot
      click(binder, ANCHOR_X + x * 2 + size, ANCHOR_Y + y * 2 + size)
      assert.are.same({ set = 1, side = "left", slot = 3 }, binder.window().address)
    end)

    it("refuses to bind what actions.validate rejects", function()
      local binder, env = build({
        catalog = { { name = "General", entries = { { label = "Broken", record = { type = "nonsense" } } } } },
      })
      open_stack(binder, env, "left", 3)
      click(binder, centre(row_named(env, "base")))
      pick(binder, env, "Broken")
      assert.are.same({ type = "ja", action = "Provoke" }, env.bindings.entry_at("1", "left", 3), "nothing written")
      assert.is_not_nil(env.said[1], "and the refusal is said")
    end)
  end)
end)
