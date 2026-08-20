--[[
Copyright © 2026, Azureblood2
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of XIVHud nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Azureblood2 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ Edit mode: the mouse-driven binder. Three surfaces - the bar's own
     slots, the stack panel beside the clicked slot, and the catalog above
     the bar - and nothing but `(type, x, y, delta)` tuples driving them.

     The stack panel is the fix for the overlay system the reference fork made
     "cumbersome and hard to wrap my head around": there the edit target was
     sticky global state, set elsewhere and invisible at bind time. Here it
     is chosen at the slot, at bind time, on screen, and nothing is sticky -
     closing the panel or clicking another slot clears it.

     Two rules that look like details and are not:

       * The catalog stays LOCKED until a layer row is clicked. Every bind
         is an explicit two-step (slot -> layer -> action); nothing is ever
         inferred. A drag out of the catalog therefore always has a layer
         already, so drag-to-bind cannot bypass the safeguard either.
       * A press becomes a DRAG only after the cursor leaves the thing it
         started on; below that it is a click. The reference has no such
         threshold, which makes a plain click a zero-distance drag whose
         fate depends on its two disagreeing hit-tests. Ours hit-tests once,
         through the same render.lua geometry the bar is drawn with.

     Prims exist only while edit mode is open: they are built by open() and
     destroyed by close(), so nothing here is on the per-frame path when the
     binder is shut. ]]

local contexts = require("components/crossbar/contexts")

-- Windower's mouse types, as layout_mode names them.
local MOVE, LEFT_DOWN, LEFT_UP, WHEEL = 0, 1, 2, 10

local SLOT_COUNT = 8
local ROW_HEIGHT = 16
local PAD = 6
local GAP = 8
local PANEL_WIDTH = 260
local CATALOG_WIDTH = 460
local CATEGORY_WIDTH = 150
local ENTRY_ROWS = 16
--[[ The category column is a fixed height: the shipped catalog produces
     fourteen (eight magic schools, trusts, abilities, weaponskills, items,
     mounts, open, general), so sixteen rows carries it with headroom. What
     will not fit is COUNTED and said in the header rather than dropped
     silently - the CLI can still reach it. ]]
local CATEGORY_ROWS = 16
local TOOLTIP_WIDTH = 240
local TOOLTIP_ROWS = 8
-- base/shared + the worn subjob + every roster context, with headroom so a
-- roster addition needs no prim-count edit here.
local STACK_ROWS = #contexts + 4
-- Panel chrome: the component's own white square, tinted and dimmed.
local PANEL_TEXTURE = "components/crossbar/assets/black-square.png"
local PANEL_ALPHA = 220
local ICON_SIZE = 12

-- The marks a slot wears on the bar in edit mode, so "where is this coming
-- from" is answered before any click: nothing for the job base (the common
-- case), one mark for a subjob layer, another for a context.
local MARKS = { sub = "+", ctx = "*" }

local function inside(x, y, rect)
  return rect ~= nil
    and type(x) == "number"
    and type(y) == "number"
    and x >= rect.x
    and x < rect.x + rect.width
    and y >= rect.y
    and y < rect.y + rect.height
end

-- Every field through tostring: the binding files are hand-editable, and a
-- record whose `type` is a table must not throw inside a mouse handler.
-- Like the CLI's listing (and unlike name_of below), this shows the STORED
-- record rather than what the player calls it, so `display` is deliberately
-- not read here: a layer row's job is to say what is in the file.
local function label_of(record)
  if type(record) ~= "table" then
    return "-"
  end
  local parts = { tostring(record.type) }
  if record.alias ~= nil then
    parts[#parts + 1] = '"' .. tostring(record.alias) .. '"'
  elseif record.action ~= nil then
    parts[#parts + 1] = tostring(record.action)
  end
  return table.concat(parts, " ")
end

-- What the player calls the thing: its own alias, else its action name,
-- else the built-in's type word (`draw`, `mr`, `warp` carry no name).
local function name_of(record)
  if type(record) ~= "table" then
    return "-"
  end
  return tostring(record.alias or record.display or record.action or record.type)
end

--[[ A binding is stored, and later edited in place by `alias` and `icon`.
     Binding the catalog's own record table would hand every slot bound from
     one entry the SAME table, so a rename on one would rename them all -
     and the catalog's listing with them. The CLI builds a fresh record per
     invocation; this is that, for the mouse. ]]
local function copy_record(record)
  if type(record) ~= "table" then
    return record
  end
  local copy = {}
  for key, value in pairs(record) do
    copy[key] = type(value) == "table" and copy_record(value) or value
  end
  return copy
end

local function context_named(name)
  for _, context in ipairs(contexts) do
    if context.name == name then
      return context
    end
  end
  return nil
end

local function new(deps)
  deps = deps or {}
  local self = {}

  local active = false
  local prims = nil
  -- The clicked slot (with the screen rect it was clicked in), the layer
  -- cursor, and whether the catalog is unlocked. The cursor deliberately
  -- outlives a bind: filling one context across several slots is the case
  -- the drag gestures exist for.
  local slot = nil
  local cursor = nil
  local catalog_open = false
  local catalog_groups = nil
  local category_index, page = 1, 1
  local press = nil
  local tooltip = nil
  -- The target the tooltip was built from, kept so a cadence rebuild can
  -- redo it without the cursor moving.
  local hovered = nil
  -- The drawn descriptors, rebuilt by redraw() and read by the hit-test, so
  -- what is clickable is exactly what is on screen.
  local panel = nil
  local view = nil

  local function say(lines)
    if deps.say ~= nil then
      deps.say(lines)
    end
  end

  -- The bar itself has to be repainted after a write: the binder owns its
  -- own panels, never the widget's slots.
  local function changed()
    if deps.changed ~= nil then
      deps.changed()
    end
  end

  local function model()
    return deps.bindings ~= nil and deps.bindings() or nil
  end

  --[[ Icon paths are memoized by record identity, and the memo is dropped
       when edit mode closes: resolving one walks a candidate list against
       the disk, and redraw() runs on every hover change, so an unmemoized
       lookup would stat the disk hundreds of times a second while the
       cursor moved. `false` records "asked, and there is none". ]]
  local icon_memo = {}
  local function icon_for(record)
    if record == nil or deps.icon == nil then
      return nil
    end
    local remembered = icon_memo[record]
    if remembered == nil then
      remembered = deps.icon(record) or false
      icon_memo[record] = remembered
    end
    return remembered or nil
  end

  -- A getter, like the model: the widget rebuilds its render instance over
  -- the user's own config on every attach.
  local function renderer()
    return deps.render ~= nil and deps.render() or nil
  end

  local function screen()
    if deps.screen == nil then
      return 1920, 1080
    end
    local width, height = deps.screen()
    return width or 1920, height or 1080
  end

  --[[ Prims ---------------------------------------------------------------- ]]

  -- The job the catalog listing was built for: a job change under an open
  -- binder leaves the old job's spells in the picker otherwise.
  local catalog_job = nil

  local function rebuild_catalog()
    local bindings = model()
    catalog_job = bindings ~= nil and bindings.job() or nil
    catalog_groups = deps.catalog ~= nil and deps.catalog.build() or {}
    category_index, page = 1, 1
    -- The memo is keyed by record identity, and those records are new.
    icon_memo = {}
  end

  local function build_prims()
    if deps.new_image == nil or deps.new_text == nil or deps.asset == nil then
      return
    end
    local style = deps.text_style ~= nil and deps.text_style() or {}
    local function image(texture)
      local prim = deps.new_image()
      prim.draggable(false)
      prim.repeat_xy(1, 1)
      prim.fit(false)
      if texture ~= nil then
        prim.path(deps.asset(texture))
      end
      prim.color(255, 255, 255)
      prim.hide()
      return prim
    end
    local function text()
      local prim = deps.new_text()
      prim.font(style.font or "sans-serif")
      prim.size(style.size or 10)
      prim.color(255, 255, 255)
      prim.stroke_width(1)
      prim.stroke_color(0, 0, 0)
      -- stroke_alpha, not stroke_transparency: the library reads a 0..1
      -- transparency and would turn a 0-255 alpha wildly negative.
      prim.stroke_alpha(255)
      -- The texts library draws its own opaque box behind a line unless
      -- told not to; every other widget here turns it off (parambar,
      -- partylist, targetbar, equipviewer, lib/overlay).
      prim.bg_visible(false)
      prim.right_justified(false)
      prim.text("")
      prim.hide()
      return prim
    end
    local function texts(count)
      local list = {}
      for index = 1, count do
        list[index] = text()
      end
      return list
    end
    local function images(count)
      local list = {}
      for index = 1, count do
        list[index] = image()
      end
      return list
    end
    prims = {
      panel_bg = image(PANEL_TEXTURE),
      panel_rows = texts(STACK_ROWS + 2),
      catalog_bg = image(PANEL_TEXTURE),
      catalog_header = text(),
      categories = texts(CATEGORY_ROWS),
      entries = texts(ENTRY_ROWS),
      entry_icons = images(ENTRY_ROWS),
      pager = text(),
      tip_bg = image(PANEL_TEXTURE),
      tip_rows = texts(TOOLTIP_ROWS),
    }
  end

  local function destroy_prims()
    if prims == nil then
      return
    end
    local function kill(prim)
      prim.destroy()
    end
    kill(prims.panel_bg)
    kill(prims.catalog_bg)
    kill(prims.catalog_header)
    kill(prims.pager)
    kill(prims.tip_bg)
    for _, list in ipairs({ prims.panel_rows, prims.categories, prims.entries, prims.entry_icons, prims.tip_rows }) do
      for _, prim in ipairs(list) do
        kill(prim)
      end
    end
    prims = nil
  end

  local function draw_backdrop(prim, rect)
    prim.color(0, 0, 0)
    prim.alpha(PANEL_ALPHA)
    prim.pos(rect.x, rect.y)
    prim.size(rect.width, rect.height)
    prim.show()
  end

  local function draw_rows(list, lines)
    for index, prim in ipairs(list) do
      local line = lines[index]
      if line == nil then
        prim.hide()
      else
        prim.text(line.text)
        prim.pos(line.x, line.y)
        prim.show()
      end
    end
  end

  --[[ Geometry -------------------------------------------------------------- ]]

  -- The slot rects currently on screen, through the one geometry function
  -- render.lua draws them with: the reference resolves picker drops and slot
  -- drags with two different hit-tests, which can disagree.
  local function slot_rects()
    local rects = {}
    local render = renderer()
    if render == nil or deps.groups == nil then
      return rects
    end
    local size = render.metrics().slot
    for _, group in ipairs(deps.groups() or {}) do
      for index = 1, SLOT_COUNT do
        -- The render side is the GROUP's own half of the bar; the binding
        -- side is whichever half the group is displaying, which for a WXHB
        -- or Expanded view is its config's and not the group's.
        local x, y = render.slot_pos(group.bar, group.render_side or group.side, index)
        if x ~= nil then
          rects[#rects + 1] = {
            x = group.x + x * group.scale,
            y = group.y + y * group.scale,
            width = size * group.scale,
            height = size * group.scale,
            set = group.set,
            side = group.side,
            slot = index,
          }
        end
      end
    end
    return rects
  end

  local function bars_top()
    local top = nil
    for _, group in ipairs((deps.groups ~= nil and deps.groups()) or {}) do
      if top == nil or group.y < top then
        top = group.y
      end
    end
    return top
  end

  -- The lowest edge any drawn bar reaches, for the catalog that must not
  -- cover one: hit() checks the catalog first, so a slot underneath it
  -- would be neither clickable nor droppable.
  local function bars_bottom()
    local render = renderer()
    local bottom = nil
    if render == nil then
      return nil
    end
    local height = render.metrics().panel_height
    for _, group in ipairs((deps.groups ~= nil and deps.groups()) or {}) do
      local edge = group.y + height * group.scale
      if bottom == nil or edge > bottom then
        bottom = edge
      end
    end
    return bottom
  end

  --[[ The stack ------------------------------------------------------------- ]]

  local function address_for(source, set)
    if source == "sub" then
      return "sub:" .. set
    end
    local name = source:match("^ctx:(.+)$")
    if name ~= nil then
      return "ctx:" .. name .. ":" .. set
    end
    -- The base row addresses the set plainly: the model itself picks the
    -- shared store or the job file from the set's own flag.
    return tostring(set)
  end

  local function stack_rows()
    local rows = {}
    local bindings = model()
    if slot == nil or bindings == nil then
      return rows
    end
    local layers = bindings.layers_at(slot.set, slot.side, slot.slot) or {}
    local found = {}
    for _, layer in ipairs(layers) do
      -- The shared store and the job base are one row: which of the two a
      -- set uses is the set's flag, not a choice at the slot.
      local key = layer.source
      if key == "shared" then
        key = "base"
      elseif key:match("^sub:") then
        key = layer.worn and "sub" or nil
      end
      if key ~= nil then
        found[key] = layer
      end
    end
    local function row(source, label)
      local layer = found[source]
      rows[#rows + 1] = {
        source = source,
        label = label,
        entry = layer ~= nil and label_of(layer.entry) or "-",
        record = layer ~= nil and layer.entry or nil,
        winner = layer ~= nil and layer.active == true,
      }
    end
    -- The SET's own flag, never whether a layer happens to hold an entry:
    -- an empty shared set would otherwise be labelled (and echoed) `base`
    -- while the write landed in SHARED.
    row("base", bindings.shared(slot.set) and "shared" or "base")
    local _, sub = bindings.job()
    if sub ~= nil then
      row("sub", "sub:" .. tostring(sub))
    end
    for _, context in ipairs(contexts) do
      row("ctx:" .. context.name, context.name)
    end
    return rows
  end

  -- The slot's rect as it is drawn NOW, not as it was when clicked: the
  -- layout slot can move under an open panel (`//hud slot <name>`).
  local function current_slot_rect()
    for _, rect in ipairs(slot_rects()) do
      if rect.set == slot.set and rect.side == slot.side and rect.slot == slot.slot then
        return rect
      end
    end
    return slot.rect
  end

  local function build_panel()
    if slot == nil then
      return nil
    end
    local rows = stack_rows()
    local width, height = PANEL_WIDTH, PAD * 2 + (#rows + 2) * ROW_HEIGHT
    local screen_width, screen_height = screen()
    local rect = current_slot_rect()
    local x = rect.x + rect.width + GAP
    if x + width > screen_width then
      x = rect.x - width - GAP
    end
    local y = rect.y
    if y + height > screen_height then
      y = screen_height - height
    end
    local built = {
      x = math.max(0, x),
      y = math.max(0, y),
      width = width,
      height = height,
      address = { set = slot.set, side = slot.side, slot = slot.slot },
      rows = rows,
    }
    local context = cursor ~= nil and context_named((cursor.source:match("^ctx:(.+)$")) or "") or nil
    built.viewing = context ~= nil and context.label:upper() or "LIVE"
    built.cursor = cursor ~= nil and cursor.label or nil
    local row_y = built.y + PAD + ROW_HEIGHT * 2
    for index, row in ipairs(rows) do
      row.x, row.width = built.x, width
      row.y, row.height = row_y + (index - 1) * ROW_HEIGHT, ROW_HEIGHT
      row.selected = cursor ~= nil and cursor.source == row.source
    end
    return built
  end

  --[[ The catalog ----------------------------------------------------------- ]]

  local function build_view()
    if not catalog_open or catalog_groups == nil or #catalog_groups == 0 then
      return nil
    end
    if category_index > #catalog_groups then
      category_index = 1
    end
    local group = catalog_groups[category_index]
    local entries = group.entries or {}
    local pages = math.max(1, math.ceil(#entries / ENTRY_ROWS))
    if page > pages then
      page = pages
    end
    local width = CATALOG_WIDTH
    local height = PAD * 2 + (ENTRY_ROWS + 2) * ROW_HEIGHT
    local screen_width = screen()
    local top = bars_top()
    local y = top ~= nil and (top - height - GAP) or 0
    if y < 0 then
      -- No room above: go below the bar rather than over it.
      local bottom = bars_bottom()
      y = bottom ~= nil and (bottom + GAP) or 0
    end
    local built = {
      x = math.max(0, math.floor(screen_width / 2 - width / 2)),
      y = math.max(0, y),
      width = width,
      height = height,
      category = group.name,
      page = page,
      pages = pages,
      categories = {},
      categories_hidden = math.max(0, #catalog_groups - CATEGORY_ROWS),
      entries = {},
    }
    local first_row = built.y + PAD + ROW_HEIGHT
    for index = 1, math.min(#catalog_groups, CATEGORY_ROWS) do
      built.categories[index] = {
        name = catalog_groups[index].name,
        index = index,
        x = built.x + PAD,
        y = first_row + (index - 1) * ROW_HEIGHT,
        width = CATEGORY_WIDTH,
        height = ROW_HEIGHT,
        selected = index == category_index,
      }
    end
    local entry_x = built.x + PAD * 2 + CATEGORY_WIDTH
    local entry_width = width - CATEGORY_WIDTH - PAD * 3
    for index = 1, ENTRY_ROWS do
      local entry = entries[(page - 1) * ENTRY_ROWS + index]
      if entry ~= nil then
        built.entries[#built.entries + 1] = {
          label = entry.label,
          record = entry.record,
          x = entry_x,
          y = first_row + (index - 1) * ROW_HEIGHT,
          width = entry_width,
          height = ROW_HEIGHT,
        }
      end
    end
    built.pager = {
      x = entry_x,
      y = built.y + height - PAD - ROW_HEIGHT,
      width = entry_width,
      height = ROW_HEIGHT,
    }
    return built
  end

  --[[ Tooltips -------------------------------------------------------------- ]]

  -- Only what the component already knows: no game description text, which
  -- is data we do not hold and would have to vendor to invent.
  local function tooltip_lines(record, address)
    if type(record) ~= "table" then
      return nil
    end
    local facts = (deps.describe ~= nil and deps.describe(record)) or {}
    -- The tail of this chain is redundancy, not a live branch: `describe`
    -- resolves the same alias -> display -> action -> type order itself, so
    -- `facts.name` answers whenever the dep is wired at all, and the rest
    -- only stands in for a ctx that handed the binder no describe.
    local lines = { tostring(facts.name or record.alias or record.display or record.action or record.type) }
    local second = "type: " .. tostring(record.type)
    if record.target ~= nil then
      second = second .. "  target: <" .. tostring(record.target) .. ">"
    elseif facts.target ~= nil then
      second = second .. "  target: <" .. tostring(facts.target) .. ">"
    end
    lines[#lines + 1] = second
    if facts.mp_cost ~= nil and facts.mp_cost ~= 0 then
      lines[#lines + 1] = "MP " .. tostring(facts.mp_cost)
    end
    if facts.tp_cost ~= nil and facts.tp_cost ~= 0 then
      lines[#lines + 1] = "TP " .. tostring(facts.tp_cost)
    end
    if facts.recast ~= nil then
      -- What is LEFT, not what the action costs: a bare "0s" would read as
      -- "no cooldown" on an ability that has a long one and is simply up.
      local recast = tonumber(facts.recast)
      if recast ~= nil and recast <= 0 then
        lines[#lines + 1] = "recast: ready"
      else
        lines[#lines + 1] = "recast: " .. tostring(facts.recast) .. "s left"
      end
    end
    if facts.property ~= nil then
      local property = facts.property
      if type(property) == "table" then
        property = table.concat(property, ", ")
      end
      lines[#lines + 1] = "SC: " .. tostring(property)
    end
    if address ~= nil then
      local bindings = model()
      local layers = bindings ~= nil and bindings.layers_at(address.set, address.side, address.slot) or {}
      local winner, covered = nil, {}
      for _, layer in ipairs(layers) do
        if layer.active then
          winner = layer.source
        elseif winner == nil then
          covered[#covered + 1] = layer.source
        end
      end
      if winner ~= nil then
        lines[#lines + 1] = "layer: " .. winner
      end
      if #covered > 0 then
        lines[#lines + 1] = "covers: " .. table.concat(covered, ", ")
      end
    end
    return lines
  end

  -- What a hovered target IS, cheaply: the gate below rebuilds only when
  -- this changes, so a resting cursor costs one comparison per move rather
  -- than a layers_at walk and a describe.
  local function target_key(target)
    if target == nil then
      return nil
    end
    if target.kind == "slot" then
      -- The address, not the action: two slots may hold the same one.
      return "slot:" .. target.set .. ":" .. target.side .. ":" .. target.slot
    end
    if target.kind == "entry" then
      return "entry:" .. tostring(target.entry.label) .. ":" .. target.entry.y
    end
    return nil
  end

  local function build_tooltip(target)
    if target == nil then
      return nil
    end
    local lines, rect, key
    if target.kind == "slot" then
      local bindings = model()
      local record = bindings ~= nil and bindings.resolve(target.set, target.side, target.slot) or nil
      lines = tooltip_lines(record, target)
      rect = target.rect
      key = target_key(target)
    elseif target.kind == "entry" then
      lines = tooltip_lines(target.entry.record, nil)
      rect = target.entry
      key = target_key(target)
    end
    if lines == nil or #lines == 0 then
      return nil
    end
    local screen_width, screen_height = screen()
    local width = TOOLTIP_WIDTH
    local height = PAD * 2 + #lines * ROW_HEIGHT
    local x = rect.x + rect.width + GAP
    if x + width > screen_width then
      x = rect.x - width - GAP
    end
    local y = rect.y
    if y + height > screen_height then
      y = screen_height - height
    end
    return { x = math.max(0, x), y = math.max(0, y), width = width, height = height, lines = lines, key = key }
  end

  --[[ Drawing --------------------------------------------------------------- ]]

  local function redraw()
    panel = build_panel()
    view = build_view()
    if prims == nil then
      return
    end
    if panel == nil then
      prims.panel_bg.hide()
      draw_rows(prims.panel_rows, {})
    else
      draw_backdrop(prims.panel_bg, panel)
      local lines = {
        {
          text = "slot: set " .. panel.address.set .. " " .. panel.address.side:sub(1, 1) .. " " .. panel.address.slot,
          x = panel.x + PAD,
          y = panel.y + PAD,
        },
        {
          text = "EDITING -> " .. (panel.cursor or "(pick a layer)") .. "   viewing: " .. panel.viewing,
          x = panel.x + PAD,
          y = panel.y + PAD + ROW_HEIGHT,
        },
      }
      for _, row in ipairs(panel.rows) do
        lines[#lines + 1] = {
          text = (row.winner and "* " or "  ") .. (row.selected and "> " or "") .. row.label .. ": " .. row.entry,
          x = row.x + PAD,
          y = row.y,
        }
      end
      draw_rows(prims.panel_rows, lines)
    end
    if view == nil then
      prims.catalog_bg.hide()
      prims.catalog_header.hide()
      prims.pager.hide()
      draw_rows(prims.categories, {})
      draw_rows(prims.entries, {})
      for _, prim in ipairs(prims.entry_icons) do
        prim.hide()
      end
    else
      draw_backdrop(prims.catalog_bg, view)
      local header = "catalog: " .. view.category
      if view.categories_hidden > 0 then
        header = header .. "  (+" .. view.categories_hidden .. " more, use //hud crossbar bind)"
      end
      prims.catalog_header.text(header)
      prims.catalog_header.pos(view.x + PAD, view.y + PAD)
      prims.catalog_header.show()
      local categories = {}
      for index, category in ipairs(view.categories) do
        categories[index] = {
          text = (category.selected and "> " or "  ") .. category.name,
          x = category.x,
          y = category.y,
        }
      end
      draw_rows(prims.categories, categories)
      local entries = {}
      for index, entry in ipairs(view.entries) do
        entries[index] = { text = entry.label, x = entry.x + ICON_SIZE + 4, y = entry.y }
      end
      draw_rows(prims.entries, entries)
      for index, prim in ipairs(prims.entry_icons) do
        local entry = view.entries[index]
        local path = entry ~= nil and icon_for(entry.record) or nil
        if path == nil then
          prim.hide()
        else
          prim.path(path)
          prim.pos(entry.x, entry.y)
          prim.size(ICON_SIZE, ICON_SIZE)
          prim.show()
        end
      end
      prims.pager.text("page " .. view.page .. "/" .. view.pages .. " - wheel to scroll")
      prims.pager.pos(view.pager.x, view.pager.y)
      prims.pager.show()
    end
    if tooltip == nil then
      prims.tip_bg.hide()
      draw_rows(prims.tip_rows, {})
    else
      draw_backdrop(prims.tip_bg, tooltip)
      local lines = {}
      for index, line in ipairs(tooltip.lines) do
        if index <= TOOLTIP_ROWS then
          lines[index] = { text = line, x = tooltip.x + PAD, y = tooltip.y + PAD + (index - 1) * ROW_HEIGHT }
        end
      end
      draw_rows(prims.tip_rows, lines)
    end
  end

  --[[ Hit-testing ----------------------------------------------------------- ]]

  --[[ Panels first: they draw over the bar, so a slot beneath one is not
       clickable while it is open.

       EVERY target carries the rect it was found in, and the drag threshold
       measures against that rect - never against the slot grid alone. A row
       whose rect went missing would arm a drag on the pixel of drift every
       real click has, and since no drop gesture starts on a row, the click
       would simply vanish. ]]
  local function hit(x, y)
    --[[ The tooltip first: it draws over everything, and a release inside
         it must never read as the empty space that unbinds a slot. It is
         inert - no click does anything through it - which is exactly why
         it has to be named rather than fallen through. ]]
    if tooltip ~= nil and inside(x, y, tooltip) then
      return { kind = "tooltip", rect = tooltip }
    end
    if view ~= nil and inside(x, y, view) then
      for _, entry in ipairs(view.entries) do
        if inside(x, y, entry) then
          return { kind = "entry", entry = entry, rect = entry }
        end
      end
      for _, category in ipairs(view.categories) do
        if inside(x, y, category) then
          return { kind = "category", index = category.index, rect = category }
        end
      end
      if inside(x, y, view.pager) then
        return { kind = "pager", rect = view.pager }
      end
      return { kind = "panel", rect = view }
    end
    if panel ~= nil and inside(x, y, panel) then
      for index, row in ipairs(panel.rows) do
        if inside(x, y, row) then
          return { kind = "row", index = index, row = row, rect = row }
        end
      end
      return { kind = "panel", rect = panel }
    end
    local rects = slot_rects()
    for index = #rects, 1, -1 do
      local rect = rects[index]
      if inside(x, y, rect) then
        return { kind = "slot", set = rect.set, side = rect.side, slot = rect.slot, rect = rect }
      end
    end
    return nil
  end

  --[[ Actions --------------------------------------------------------------- ]]

  local function preview_for(source)
    local name = source ~= nil and source:match("^ctx:(.+)$") or nil
    local context = name ~= nil and context_named(name) or nil
    if context == nil then
      return nil
    end
    -- One simulated buff, run through the LIVE resolver: picking dark-arts
    -- drops light-arts even if it is actually up (the arts are mutually
    -- exclusive), and picking an addendum lights its arts too through the
    -- context's own `any_of`. The preview is therefore always the true
    -- stacked result, never a hand-toggled layer.
    return { context.any_of[1] }
  end

  local function apply_preview()
    if deps.preview ~= nil then
      deps.preview(preview_for(cursor ~= nil and cursor.source or nil))
    end
  end

  local function address_text(address, layer)
    return layer .. " / set " .. address.set .. " / " .. address.side .. " / slot " .. address.slot
  end

  local function write_bind(record, address)
    local bindings = model()
    if bindings == nil or cursor == nil then
      return
    end
    local ok, complaint = true, nil
    if deps.validate ~= nil then
      ok, complaint = deps.validate(record)
    end
    if ok == nil then
      say("crossbar: " .. tostring(complaint))
      return
    end
    -- One write over the old entry, never a clear and an insert: the
    -- reference's non-atomic remove-then-insert can lose the original.
    local wrote, err =
      bindings.bind(address_for(cursor.source, address.set), address.side, address.slot, copy_record(record))
    if wrote == nil then
      say("crossbar: " .. tostring(err))
      return
    end
    -- The plan's own shape: the action's NAME, not its type token -
    -- "bound Addendum: White -> light-arts / set 1 / left / slot 3".
    say("crossbar: bound " .. name_of(record) .. " -> " .. address_text(address, cursor.label))
    changed()
  end

  local function clear_layer(address)
    local bindings = model()
    -- With no layer selected there is nothing to clear, so the gesture is a
    -- no-op: an unbind can never wipe a whole stack.
    if bindings == nil or cursor == nil then
      return
    end
    local wrote, err = bindings.unbind(address_for(cursor.source, address.set), address.side, address.slot)
    if wrote == nil then
      say("crossbar: " .. tostring(err))
      return
    end
    say("crossbar: cleared " .. address_text(address, cursor.label))
    changed()
  end

  local function swap_slots(from, to)
    local bindings = model()
    if bindings == nil then
      return
    end
    local wrote, err = bindings.swap(
      { set = from.set, side = from.side, slot = from.slot },
      { set = to.set, side = to.side, slot = to.slot }
    )
    if wrote == nil then
      say("crossbar: " .. tostring(err))
      return
    end
    say(
      "crossbar: swapped set "
        .. from.set
        .. " "
        .. from.side
        .. " slot "
        .. from.slot
        .. " with set "
        .. to.set
        .. " "
        .. to.side
        .. " slot "
        .. to.slot
    )
    changed()
  end

  local function select_slot(target)
    -- Nothing is sticky: a new slot is a new decision, so the layer cursor
    -- (and its preview) goes with the old one.
    if slot == nil or slot.set ~= target.set or slot.side ~= target.side or slot.slot ~= target.slot then
      cursor = nil
      catalog_open = false
      apply_preview()
    end
    slot = { set = target.set, side = target.side, slot = target.slot, rect = target.rect }
  end

  local function close_panel()
    slot, cursor, catalog_open = nil, nil, false
    apply_preview()
  end

  local function on_click(target)
    if target == nil then
      close_panel()
    elseif target.kind == "slot" then
      select_slot(target)
    elseif target.kind == "row" then
      local row = target.row
      if row ~= nil then
        cursor = { source = row.source, label = row.label }
        catalog_open = true
        -- The category the user last picked survives; the page does not,
        -- since the listing itself may have changed under it.
        page = 1
        apply_preview()
      end
    elseif target.kind == "entry" then
      write_bind(target.entry.record, panel ~= nil and panel.address or slot)
      -- The catalog closes behind a click-bind and the stack panel refreshes
      -- in place: unbind, relayer or the next slot all carry on from there.
      -- The row the cursor is on goes with it, tooltip and all - there is
      -- nothing left for the cadence to describe.
      catalog_open = false
      tooltip, hovered = nil, nil
    elseif target.kind == "category" then
      category_index, page = target.index, 1
    elseif target.kind == "pager" then
      page = view ~= nil and (page % view.pages + 1) or 1
    end
    redraw()
  end

  local function on_drop(origin, target)
    if origin.kind == "entry" then
      -- A catalog drag always has an explicit layer already (the catalog
      -- does not unlock without one), so the drop inherits it; dropped on
      -- anything but a slot it is abandoned silently.
      if target ~= nil and target.kind == "slot" then
        write_bind(origin.entry.record, target)
      end
    elseif origin.kind == "slot" then
      if target == nil then
        --[[ GENUINELY empty space only - the wiki's own words. The stack
             panel opens eight pixels from the slot, so a drop onto one of
             the binder's own surfaces is the commonest miss there is, and
             it cancels quietly rather than deleting. Deliberately
             asymmetric with the slot-to-slot swap: moving a button takes
             everything about it, deleting only ever touches the one plane
             being edited. ]]
        clear_layer(origin)
      elseif target.kind == "slot" then
        if target.set ~= origin.set or target.side ~= origin.side or target.slot ~= origin.slot then
          swap_slots(origin, target)
        end
      end
    end
    redraw()
  end

  --[[ The public surface ---------------------------------------------------- ]]

  function self.active()
    return active
  end

  function self.open()
    if active then
      return
    end
    active = true
    slot, cursor, catalog_open, press, tooltip, hovered = nil, nil, false, nil, nil, nil
    -- Rebuilt every time edit mode opens: the inventory, the known spells
    -- and the job pair all move in play.
    rebuild_catalog()
    build_prims()
    redraw()
  end

  function self.close()
    if not active then
      return
    end
    active = false
    slot, cursor, catalog_open, press, tooltip, hovered = nil, nil, false, nil, nil, nil
    panel, view, catalog_groups = nil, nil, nil
    icon_memo = {}
    apply_preview()
    destroy_prims()
  end

  --- Re-read the model and redraw: a job change, a buff change or the bar's
  --- own repaint can all move what the panel is showing.
  function self.refresh()
    if not active then
      return
    end
    local bindings = model()
    if bindings ~= nil and bindings.job() ~= catalog_job then
      rebuild_catalog()
    end
    redraw()
  end

  --- The layer under the `EDITING ->` cursor, or nil.
  function self.layer()
    return cursor ~= nil and cursor.source or nil
  end

  function self.panel()
    return panel
  end

  function self.catalog_view()
    return view
  end

  function self.tooltip()
    return tooltip
  end

  --- Rebuild the resting tooltip from the target it was already on: a
  --- recast counts down whether or not the cursor moves. Called on the
  --- widget's own read cadence, never per frame.
  function self.refresh_tooltip()
    -- Never mid-gesture: a drag owns the cursor, and the tooltip it stood
    -- down stays down until the drop resolves.
    if not active or hovered == nil or (press ~= nil and press.drag) then
      return
    end
    local rebuilt = build_tooltip(hovered)
    local before = tooltip ~= nil and table.concat(tooltip.lines, "\n") or nil
    local after = rebuilt ~= nil and table.concat(rebuilt.lines, "\n") or nil
    tooltip = rebuilt
    if before ~= after then
      redraw()
    end
  end

  --- The mark a slot wears on the bar for the layer its winner came from.
  function self.mark(source)
    if type(source) ~= "string" then
      return ""
    end
    if source:match("^ctx:") then
      return MARKS.ctx
    end
    if source == "sub" or source:match("^sub:") then
      return MARKS.sub
    end
    return ""
  end

  function self.mouse(kind, x, y, delta)
    if not active then
      return false
    end
    if kind == MOVE then
      if press ~= nil then
        if not press.drag and not inside(x, y, press.rect) then
          press.drag = true
          -- The cursor left what it started on: this is a drag, so the
          -- tooltip that was following it stands down - and the target it
          -- was built from goes with it, or the cadence rebuild would put
          -- it back under a cursor that is mid-gesture.
          tooltip, hovered = nil, nil
          redraw()
        end
        -- Motion is the client's until a real drag is live - layout_mode's
        -- own convention. Blocking it for a press that is still a click
        -- would freeze the camera on every button-down.
        return press.drag
      end
      local target = hit(x, y)
      if target ~= nil and target.kind == "tooltip" then
        -- Hovering our own tooltip changes nothing: it describes whatever
        -- it was opened for until the cursor reaches something else.
        return false
      end
      -- Keyed on the TARGET, not on the text: edit mode draws every side,
      -- so two slots holding the same action are ordinary, and a text-only
      -- gate would leave the panel beside the slot the cursor has left.
      if target_key(target) == (tooltip and tooltip.key) then
        return false
      end
      hovered = target
      tooltip = build_tooltip(target)
      redraw()
      return false
    end
    if kind == LEFT_DOWN then
      --[[ A fresh press supersedes whatever the last one left behind: a
           release consumed by an addon ahead of us, or delivered off-window,
           would otherwise strand a drag that swallows motion for good. ]]
      press = nil
      local target = hit(x, y)
      if target == nil then
        -- Nothing of ours under the cursor: the click is the client's, and
        -- it dismisses the panel (rule 5 - nothing is sticky). Resolved on
        -- the press so no gesture is armed for a click we declined.
        on_click(nil)
        return false
      end
      press = { target = target, rect = target.rect, drag = false }
      return true
    end
    if kind == LEFT_UP then
      local armed = press
      press = nil
      if armed == nil then
        return false
      end
      if armed.drag then
        on_drop(armed.target, hit(x, y))
      else
        on_click(armed.target)
      end
      return true
    end
    if kind == WHEEL then
      if view == nil or not inside(x, y, view) then
        -- Still ours over the stack panel and the tooltip: the game zooming
        -- its camera under a panel the player is reading is not wanted.
        -- There is simply nothing to scroll there.
        return (panel ~= nil and inside(x, y, panel)) or (tooltip ~= nil and inside(x, y, tooltip))
      end
      if type(delta) == "number" and delta ~= 0 then
        -- Wheel down is forward, and both ends wrap: the pager says scroll,
        -- so it has to keep moving rather than stick at an end.
        local step = delta < 0 and 1 or -1
        page = (page - 1 + step) % view.pages + 1
        redraw()
      end
      return true
    end
    return false
  end

  --- Terminal teardown. Deliberately routed through close(), so a destroy
  --- with a preview up hands the live buff list back exactly as an ordinary
  --- exit would - there is no second, quieter shutdown path to keep in step.
  function self.destroy()
    self.close()
    press, tooltip, hovered, panel, view = nil, nil, nil, nil, nil
  end

  return self
end

return new
