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

--[[ Edit mode: the mouse-driven binder. Two surfaces - the bar's own
     slots and ONE window - and nothing but `(type, x, y, delta)` tuples
     driving them.

     It was three surfaces until 2026-08-22 (a stack panel beside the
     clicked slot and a catalog above the bar), which failed in a live
     client: the panel drew under the NEIGHBOURING slots' labels, and
     Windower renders every `texts` object above every `images` one, so no
     creation order could lift a backdrop clear of them. Centring is the
     only fix, and once everything is centred there is no reason for it to
     be three.

     The window is the fix for the overlay system the reference fork made
     "cumbersome and hard to wrap my head around": there the edit target was
     sticky global state, set elsewhere and invisible at bind time. Here it
     is chosen at the slot, at bind time, on screen, and nothing is sticky -
     closing the window or clicking another slot clears it.

     Two rules that look like details and are not:

       * Each step is EXPLICIT: slot -> layer -> action -> target, nothing
         inferred, and the step you are on is the only thing the window
         shows. Drag-to-bind was removed with the wizard - a drag that
         half-bound something, with no target step and no confirmation,
         would be a second and quieter path that could disagree with the
         three steps.
       * A press becomes a DRAG only after the cursor leaves the thing it
         started on; below that it is a click. The reference has no such
         threshold, which makes a plain click a zero-distance drag whose
         fate depends on its two disagreeing hit-tests. Ours hit-tests once,
         through the same render.lua geometry the bar is drawn with. The
         title strip is the one exception and says so where it is read.

     Prims exist only while edit mode is open: they are built by open() and
     destroyed by close(), so nothing here is on the per-frame path when the
     binder is shut. ]]

local contexts = require("components/crossbar/contexts")

-- Windower's mouse types, as layout_mode names them.
local MOVE, LEFT_DOWN, LEFT_UP, WHEEL = 0, 1, 2, 10

local SLOT_COUNT = 8

--[[ ONE window, and a wizard inside it (Kevin, 2026-08-22). It replaced a
     stack panel, a catalog and a floating tooltip drawn beside one another:
     the panel opened next to its slot and drew UNDER the neighbouring
     slots' labels, and no ordering trick could have lifted it clear -
     Windower renders every `texts` object above every `images` one, so a
     text always covers a backdrop. Centring the window is what actually
     fixes that, and once everything is centred there is no reason for it to
     be three surfaces.

     Three steps, each replacing the last in the same frame:

       layer   -> which plane of the stack you are editing
       catalog -> what to put there
       target  -> what it aims at, for the types that take one

     `back` in the top left walks the steps in reverse and closes the window
     from the first, so every dead end has a way out that is not "click
     somewhere empty and hope". ]]
local STEP_LAYER, STEP_CATALOG, STEP_TARGET = "layer", "catalog", "target"

local FONT_SIZE = 18
local ROW_HEIGHT = 26
local PAD = 10
local GAP = 12
local WINDOW_WIDTH = 920
local WINDOW_HEIGHT = 600
local CATEGORY_WIDTH = 210
local DETAILS_WIDTH = 280
local BACK_WIDTH = 90
-- The title line and the line under it naming the slot and the choice so far.
local HEADER_ROWS = 2
--[[ Rows are derived from the window rather than fixed, so changing its
     height moves the lists with it instead of leaving them short or
     overflowing. The entry list gives one row back to the pager; the
     category column and the details pane use the full body. ]]
local BODY_ROWS = math.floor((WINDOW_HEIGHT - PAD * 2 - HEADER_ROWS * ROW_HEIGHT) / ROW_HEIGHT)
local ENTRY_ROWS = BODY_ROWS - 1
--[[ The shipped catalog produces fifteen categories (eight magic groups,
     Trusts among them, then abilities, weaponskills, items, enchanted,
     mounts, open, general), so the body carries them with room to spare.
     What will not fit is COUNTED and said in the header rather than dropped
     silently - the CLI can still reach it. ]]
local CATEGORY_ROWS = BODY_ROWS
local DETAIL_ROWS = BODY_ROWS
-- base/shared + the worn subjob + the weapon in hand + every roster context,
-- with headroom so a roster addition needs no prim-count edit here. Counted
-- off the WHOLE roster though the job gate hides most of it: the panel is
-- rebuilt per job and the prims are not.
local STACK_ROWS = #contexts + 5
-- Panel chrome: the component's own white square, tinted and dimmed.
local PANEL_TEXTURE = "assets/own/black-square.png"
local PANEL_ALPHA = 220
local ICON_SIZE = 16

--[[ The types whose records carry a target, and so the ones that get the
     third step. `mount` is deliberately absent though `actions.lua` would
     accept a target on it - there is nothing to aim a chocobo at - and so
     are `ct`/`ex`, whose action word is a whole command line the catalog
     does not offer. Everything else the catalog can produce is here. ]]
local TARGETED_TYPES = {
  ma = true,
  ja = true,
  ws = true,
  ra = true,
  item = true,
  enchanteditem = true,
  pet = true,
}

--[[ Every FFXI target token, because a menu that stops at the common few
     leaves the rest reachable only from the CLI (Kevin, 2026-08-22). The
     first row binds no target at all, which is what a mouse bind has always
     produced and stays the default. ]]
local TARGET_ROWS = {
  { label = "(no target)" },
  { token = "t", note = "current target" },
  { token = "me", note = "myself" },
  { token = "bt", note = "battle target" },
  { token = "ft", note = "focus target" },
  { token = "st", note = "select on use" },
  { token = "stpc", note = "select a player" },
  { token = "stnpc", note = "select an NPC" },
  { token = "pet", note = "my pet" },
}
for index = 0, 5 do
  TARGET_ROWS[#TARGET_ROWS + 1] = { token = "p" .. index, note = "party member " .. index }
end
for _, first in ipairs({ 10, 20 }) do
  for index = first, first + 5 do
    TARGET_ROWS[#TARGET_ROWS + 1] = { token = "a" .. index, note = "alliance member " .. index }
  end
end
for _, row in ipairs(TARGET_ROWS) do
  if row.token ~= nil then
    row.label = "<" .. row.token .. ">"
  end
end

-- The marks a slot wears on the bar in edit mode, so "where is this coming
-- from" is answered before any click: nothing for the job base (the common
-- case), one mark for a subjob layer, one for the weapon layer, another for
-- a context. Each is a single character none of them can start a name with.
local MARKS = { sub = "+", wpn = "^", ctx = "*" }

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
  --[[ The clicked slot (with the screen rect it was clicked in), which step
       of the wizard is on screen, the layer cursor, and the action waiting
       for a target. The cursor deliberately outlives a bind: filling one
       context across several slots is the case the layer step exists for,
       and a commit drops back to it rather than closing the window. ]]
  local slot = nil
  local step = nil
  local cursor = nil
  local pending = nil
  local catalog_groups = nil
  local category_index, page = 1, 1
  local press = nil
  --[[ Where the player dragged the window to, or nil for dead centre. Read
       from the config on open and written back on the drop, so it survives
       a reload - the window is a working surface, and having to shove it
       out of the way every session is exactly the friction the mode
       exists to remove. ]]
  local position = nil
  -- The details column, and the target it was built from - kept so a
  -- cadence rebuild can redo it without the cursor moving.
  local details = nil
  local hovered = nil
  -- The drawn descriptors, rebuilt by redraw() and read by the hit-test, so
  -- what is clickable is exactly what is on screen. Exactly one of the
  -- three views is ever non-nil.
  local window = nil
  local layer_view = nil
  local catalog_view = nil
  local target_view = nil

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
      -- The FAMILY is the widget's, the SIZE is the window's: the bar's
      -- 10pt is unreadable at this scale.
      prim.size(FONT_SIZE)
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
    --[[ One backdrop for one window. The row prims are shared across the
         steps rather than one set each: only one step is on screen at a
         time, and three sets would be three times the prims for no frame
         that could ever use them. ]]
    prims = {
      window_bg = image(PANEL_TEXTURE),
      back = text(),
      title = text(),
      subhead = text(),
      categories = texts(CATEGORY_ROWS),
      entries = texts(math.max(ENTRY_ROWS, STACK_ROWS)),
      entry_icons = images(ENTRY_ROWS),
      pager = text(),
      details = texts(DETAIL_ROWS),
    }
  end

  local function destroy_prims()
    if prims == nil then
      return
    end
    local function kill(prim)
      prim.destroy()
    end
    kill(prims.window_bg)
    kill(prims.back)
    kill(prims.title)
    kill(prims.subhead)
    kill(prims.pager)
    for _, list in ipairs({ prims.categories, prims.entries, prims.entry_icons, prims.details }) do
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

  --[[ The window and its regions. Dead centre, and nothing dodges the bar
       (Kevin, 2026-08-22): `hit()` checks the window before the slots, so a
       window over a slot makes that slot neither clickable nor droppable.
       Predictable placement won that trade - a bar in the middle of the
       screen loses drag-to-slot while the binder is open, and a bar is not
       put there. ]]
  --[[ Fully on screen, always. A position saved at one resolution and
       opened at another would otherwise leave the window unreachable, and
       there is no keyboard in edit mode to recentre it with. A window
       larger than the screen pins to the top left rather than inverting
       the range. ]]
  local function clamp_to_screen(x, y)
    local screen_width, screen_height = screen()
    return math.max(0, math.min(x, screen_width - WINDOW_WIDTH)),
      math.max(0, math.min(y, screen_height - WINDOW_HEIGHT))
  end

  local function build_frame()
    local screen_width, screen_height = screen()
    -- `position` is clamped where it is SET - on the drag and on the read at
    -- open - so there is one clamp per way in rather than a second one here
    -- that would make both untestable.
    local x = position ~= nil and position.x or math.max(0, math.floor(screen_width / 2 - WINDOW_WIDTH / 2))
    local y = position ~= nil and position.y or math.max(0, math.floor(screen_height / 2 - WINDOW_HEIGHT / 2))
    local frame = { x = x, y = y, width = WINDOW_WIDTH, height = WINDOW_HEIGHT }
    frame.back = { x = frame.x + PAD, y = frame.y + PAD, width = BACK_WIDTH, height = ROW_HEIGHT }
    frame.title = { x = frame.back.x + BACK_WIDTH + GAP, y = frame.y + PAD }
    --[[ The drag handle: the top strip, back button excluded, which is
         checked first so a slip onto it is still back. It spans the rest of
         the width rather than only the title text, because a handle you
         have to aim at is worse than no handle. ]]
    frame.header = {
      x = frame.back.x + BACK_WIDTH,
      y = frame.y,
      width = WINDOW_WIDTH - PAD - BACK_WIDTH,
      height = PAD + ROW_HEIGHT,
    }
    frame.subhead = { x = frame.x + PAD, y = frame.y + PAD + ROW_HEIGHT }
    local body_y = frame.y + PAD + HEADER_ROWS * ROW_HEIGHT
    local body_height = BODY_ROWS * ROW_HEIGHT
    frame.details = {
      x = frame.x + WINDOW_WIDTH - PAD - DETAILS_WIDTH,
      y = body_y,
      width = DETAILS_WIDTH,
      height = body_height,
    }
    -- Everything left of the details column, which every step lists into.
    frame.list = {
      x = frame.x + PAD,
      y = body_y,
      width = WINDOW_WIDTH - PAD * 2 - DETAILS_WIDTH - GAP,
      height = body_height,
    }
    return frame
  end

  --- The frame only exists while a slot is being edited: no slot, no window.
  local function build_frame_for_step()
    if slot == nil or step == nil then
      return nil
    end
    local frame = build_frame()
    frame.step = step
    frame.address = { set = slot.set, side = slot.side, slot = slot.slot }
    -- Which stacked state the bar is being shown as: a context layer
    -- previews itself, so the window has to say which one you are looking
    -- at or the bar's contents are unexplained.
    local context = cursor ~= nil and context_named((cursor.source:match("^ctx:(.+)$")) or "") or nil
    frame.viewing = context ~= nil and context.label:upper() or "LIVE"
    return frame
  end

  --[[ One page of a list, laid into a column. Shared by the catalog's
       entries and the target tokens, so the pager, the clamp and the row
       rects cannot drift apart between two steps that look the same. ]]
  local function paged(items, column, rows_per_page)
    local pages = math.max(1, math.ceil(#items / rows_per_page))
    if page > pages then
      page = pages
    end
    local first = (page - 1) * rows_per_page
    local built = {}
    for index = 1, rows_per_page do
      local item = items[first + index]
      if item == nil then
        break
      end
      built[index] = {
        item = item,
        index = first + index,
        x = column.x,
        y = column.y + (index - 1) * ROW_HEIGHT,
        width = column.width,
        height = ROW_HEIGHT,
      }
    end
    return built, pages
  end

  --[[ The stack ------------------------------------------------------------- ]]

  local function address_for(source, set)
    if source == "sub" then
      return "sub:" .. set
    end
    if source == "wpn" then
      return "wpn:" .. set
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
      elseif key:match("^sub:") or key:match("^wpn:") then
        -- Only the worn subjob and the class in hand have a row here; the
        -- others are stored layers this slot cannot be edited through.
        key = layer.worn and key:sub(1, 3) or nil
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
    -- The weapon row exists only once the client has answered with a class:
    -- it is what is in your hand, not a setting.
    local weapon = bindings.weapon_type()
    if weapon ~= nil then
      row("wpn", "wpn:" .. tostring(weapon))
    end
    -- Job-gated: a context this job cannot raise is not a layer to bind into.
    for _, name in ipairs(bindings.available_contexts()) do
      row("ctx:" .. name, name)
    end
    return rows
  end

  --[[ The three steps ------------------------------------------------------ ]]

  --- Step one: which plane of the stack the edit lands on.
  local function build_layer_view(frame)
    local rows = stack_rows()
    for index, row in ipairs(rows) do
      row.x, row.width = frame.list.x, frame.list.width
      row.y, row.height = frame.list.y + (index - 1) * ROW_HEIGHT, ROW_HEIGHT
      row.selected = cursor ~= nil and cursor.source == row.source
    end
    return { rows = rows }
  end

  --- Step two: what goes there. Categories left, one page of entries right.
  local function build_catalog_view(frame)
    if catalog_groups == nil or #catalog_groups == 0 then
      return nil
    end
    if category_index > #catalog_groups then
      category_index = 1
    end
    local group = catalog_groups[category_index]
    local column = {
      x = frame.list.x + CATEGORY_WIDTH + GAP,
      y = frame.list.y,
      width = frame.list.width - CATEGORY_WIDTH - GAP,
    }
    -- The last row of the column belongs to the pager, so the list itself
    -- stops one short of the body.
    local rows, pages = paged(group.entries or {}, column, ENTRY_ROWS)
    local built = {
      category = group.name,
      page = page,
      pages = pages,
      categories = {},
      categories_hidden = math.max(0, #catalog_groups - CATEGORY_ROWS),
      entries = {},
      pager = {
        x = column.x,
        y = frame.list.y + (BODY_ROWS - 1) * ROW_HEIGHT,
        width = column.width,
        height = ROW_HEIGHT,
      },
    }
    for index = 1, math.min(#catalog_groups, CATEGORY_ROWS) do
      built.categories[index] = {
        name = catalog_groups[index].name,
        index = index,
        x = frame.list.x,
        y = frame.list.y + (index - 1) * ROW_HEIGHT,
        width = CATEGORY_WIDTH,
        height = ROW_HEIGHT,
        selected = index == category_index,
      }
    end
    for index, row in ipairs(rows) do
      built.entries[index] = {
        label = row.item.label,
        record = row.item.record,
        x = row.x,
        y = row.y,
        width = row.width,
        height = row.height,
      }
    end
    return built
  end

  --- Step three: what it aims at, for a type that takes a target.
  local function build_target_view(frame)
    local rows, pages = paged(TARGET_ROWS, frame.list, ENTRY_ROWS)
    local built = {
      page = page,
      pages = pages,
      targets = {},
      pager = {
        x = frame.list.x,
        y = frame.list.y + (BODY_ROWS - 1) * ROW_HEIGHT,
        width = frame.list.width,
        height = ROW_HEIGHT,
      },
    }
    for index, row in ipairs(rows) do
      built.targets[index] = {
        label = row.item.label,
        note = row.item.note,
        token = row.item.token,
        x = row.x,
        y = row.y,
        width = row.width,
        height = row.height,
      }
    end
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

  --[[ The details pane. It was a floating tooltip beside the cursor and is
       now a column inside the window (Kevin, 2026-08-22), so the binder is
       genuinely one window rather than one window and a follower. It reads
       the same lines from the same describe, and is still keyed on the
       hovered target so a resting cursor rebuilds nothing. ]]
  --[[ How many characters fit a details line. Windower's text objects do not
       measure and our prim wrapper exposes no extents, so this is an
       ESTIMATE from the point size - deliberately conservative, because a
       line that stops short looks tidy and one that runs off the backdrop
       does not. Two chain properties on one SC row found it in a live
       client (Kevin, 2026-08-22). ]]
  local DETAIL_CHARS = math.max(8, math.floor(DETAILS_WIDTH / (FONT_SIZE * 0.55)))

  local function wrap_details(lines)
    local out = {}
    for _, line in ipairs(lines) do
      local text = tostring(line)
      --[[ Bounded by the rows the column HAS, so this cannot spin however
           the break rule below behaves. It is a mouse handler: a wrap that
           never finished would freeze the client, and that is not a risk
           worth carrying on the correctness of an off-by-one. ]]
      local rows = 0
      while #text > DETAIL_CHARS and rows < DETAIL_ROWS do
        rows = rows + 1
        --[[ The last space that fits, and never before the third column: a
             break at 2 would leave the continuation as long as the line it
             came from, so it would eat the budget without shortening
             anything. A single word longer than the budget has no break at
             all and is left to overrun - cutting a name in half reads as a
             different item, which is worse. ]]
        local cut = nil
        for index = DETAIL_CHARS + 1, 3, -1 do
          if text:sub(index, index) == " " then
            cut = index
            break
          end
        end
        if cut == nil then
          break
        end
        out[#out + 1] = text:sub(1, cut - 1)
        -- Indented, so a wrapped line reads as one fact and not two.
        text = "  " .. text:sub(cut + 1)
      end
      out[#out + 1] = text
    end
    return out
  end

  local function build_details(target)
    if target == nil then
      return nil
    end
    local lines, key
    if target.kind == "slot" then
      local bindings = model()
      local record = bindings ~= nil and bindings.resolve(target.set, target.side, target.slot) or nil
      lines = tooltip_lines(record, target)
      key = target_key(target)
    elseif target.kind == "entry" then
      lines = tooltip_lines(target.entry.record, nil)
      key = target_key(target)
    end
    if lines == nil or #lines == 0 then
      return nil
    end
    return { lines = wrap_details(lines), key = key }
  end

  --[[ Drawing --------------------------------------------------------------- ]]

  --[[ The title and the line under it: what is being edited, and how far
       through the wizard we are. The subhead carries the choices already
       made, so a step never leaves you guessing what it applies to. ]]
  local function header_text(frame)
    local address = frame.address
    -- The address in the form the CLI takes it, so the window and the
    -- command line name a slot the same way.
    local where = address.set .. (address.side == "left" and "L" or "R") .. address.slot
    if frame.step == STEP_LAYER then
      return "pick a layer", where
    end
    local layer = cursor ~= nil and cursor.label or "?"
    local viewing = frame.viewing ~= "LIVE" and ("   viewing: " .. frame.viewing) or ""
    if frame.step == STEP_CATALOG then
      return "pick an action", where .. "   layer: " .. layer .. viewing
    end
    local action = pending ~= nil and name_of(pending) or "?"
    return "pick a target", where .. "   layer: " .. layer .. "   action: " .. action
  end

  local function redraw()
    window = build_frame_for_step()
    layer_view, catalog_view, target_view = nil, nil, nil
    if window ~= nil then
      if window.step == STEP_LAYER then
        layer_view = build_layer_view(window)
      elseif window.step == STEP_CATALOG then
        catalog_view = build_catalog_view(window)
      else
        target_view = build_target_view(window)
      end
    end
    if prims == nil then
      return
    end
    if window == nil then
      prims.window_bg.hide()
      prims.back.hide()
      prims.title.hide()
      prims.subhead.hide()
      prims.pager.hide()
      draw_rows(prims.categories, {})
      draw_rows(prims.entries, {})
      draw_rows(prims.details, {})
      for _, prim in ipairs(prims.entry_icons) do
        prim.hide()
      end
      return
    end

    draw_backdrop(prims.window_bg, window)
    -- The first step's back closes the window, and the label says so rather
    -- than leaving a dead-looking button on the only screen it cannot
    -- retreat from.
    prims.back.text(window.step == STEP_LAYER and "[ close ]" or "[ < back ]")
    prims.back.pos(window.back.x, window.back.y)
    prims.back.show()
    local title, subhead = header_text(window)
    prims.title.text(title)
    prims.title.pos(window.title.x, window.title.y)
    prims.title.show()
    prims.subhead.text(subhead)
    prims.subhead.pos(window.subhead.x, window.subhead.y)
    prims.subhead.show()

    local categories, rows, pager = {}, {}, nil
    local icons = {}
    if layer_view ~= nil then
      for index, row in ipairs(layer_view.rows) do
        rows[index] = {
          text = (row.winner and "* " or "  ") .. (row.selected and "> " or "") .. row.label .. ": " .. row.entry,
          x = row.x,
          y = row.y,
        }
      end
    elseif catalog_view ~= nil then
      for index, category in ipairs(catalog_view.categories) do
        categories[index] = {
          text = (category.selected and "> " or "  ") .. category.name,
          x = category.x,
          y = category.y,
        }
      end
      for index, entry in ipairs(catalog_view.entries) do
        rows[index] = { text = entry.label, x = entry.x + ICON_SIZE + 4, y = entry.y }
        icons[index] = entry
      end
      local text = "page " .. catalog_view.page .. "/" .. catalog_view.pages .. " - wheel to scroll"
      if catalog_view.categories_hidden > 0 then
        text = text .. "  (+" .. catalog_view.categories_hidden .. " more categories, use //hud crossbar bind)"
      end
      pager = { text = text, rect = catalog_view.pager }
    elseif target_view ~= nil then
      for index, entry in ipairs(target_view.targets) do
        rows[index] = {
          text = entry.note ~= nil and (entry.label .. "   " .. entry.note) or entry.label,
          x = entry.x,
          y = entry.y,
        }
      end
      pager = {
        text = "page " .. target_view.page .. "/" .. target_view.pages .. " - wheel to scroll",
        rect = target_view.pager,
      }
    end
    draw_rows(prims.categories, categories)
    draw_rows(prims.entries, rows)
    for index, prim in ipairs(prims.entry_icons) do
      local entry = icons[index]
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
    if pager == nil then
      prims.pager.hide()
    else
      prims.pager.text(pager.text)
      prims.pager.pos(pager.rect.x, pager.rect.y)
      prims.pager.show()
    end

    local detail_lines = {}
    if details ~= nil then
      for index, line in ipairs(details.lines) do
        if index <= DETAIL_ROWS then
          detail_lines[index] = {
            text = line,
            x = window.details.x,
            y = window.details.y + (index - 1) * ROW_HEIGHT,
          }
        end
      end
    end
    draw_rows(prims.details, detail_lines)
  end

  --[[ Hit-testing ----------------------------------------------------------- ]]

  --[[ The window first: it draws over the bar, so a slot beneath it is not
       clickable while it is open.

       EVERY target carries the rect it was found in, and the drag threshold
       measures against that rect - never against the slot grid alone. A row
       whose rect went missing would arm a drag on the pixel of drift every
       real click has, and since no drop gesture starts on a row, the click
       would simply vanish. ]]
  local function hit(x, y)
    if window ~= nil and inside(x, y, window) then
      -- Back is checked before anything else in the window, so no row can
      -- ever be laid over the one control that gets you out.
      if inside(x, y, window.back) then
        return { kind = "back", rect = window.back }
      end
      if inside(x, y, window.header) then
        return { kind = "header", rect = window.header }
      end
      if layer_view ~= nil then
        for index, row in ipairs(layer_view.rows) do
          if inside(x, y, row) then
            return { kind = "row", index = index, row = row, rect = row }
          end
        end
      elseif catalog_view ~= nil then
        for _, entry in ipairs(catalog_view.entries) do
          if inside(x, y, entry) then
            return { kind = "entry", entry = entry, rect = entry }
          end
        end
        for _, category in ipairs(catalog_view.categories) do
          if inside(x, y, category) then
            return { kind = "category", index = category.index, rect = category }
          end
        end
        if inside(x, y, catalog_view.pager) then
          return { kind = "pager", rect = catalog_view.pager }
        end
      elseif target_view ~= nil then
        for _, entry in ipairs(target_view.targets) do
          if inside(x, y, entry) then
            return { kind = "target", token = entry.token, rect = entry }
          end
        end
        if inside(x, y, target_view.pager) then
          return { kind = "pager", rect = target_view.pager }
        end
      end
      --[[ Anywhere else inside the window is the window itself: inert, but
           NAMED rather than fallen through, so a release on the details
           column never reads as the empty space that clears a slot. ]]
      return { kind = "panel", rect = window }
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
    -- (and its preview) goes with the old one, and the wizard restarts.
    if slot == nil or slot.set ~= target.set or slot.side ~= target.side or slot.slot ~= target.slot then
      cursor, pending = nil, nil
      apply_preview()
    end
    slot = { set = target.set, side = target.side, slot = target.slot, rect = target.rect }
    step, page = STEP_LAYER, 1
  end

  local function close_panel()
    slot, cursor, pending, step = nil, nil, nil, nil
    apply_preview()
  end

  --- Commit, then fall back to the layer step so the next edit on the same
  --- slot carries on from where this one started.
  local function commit(record)
    write_bind(record, window ~= nil and window.address or slot)
    step, page, pending = STEP_LAYER, 1, nil
    details, hovered = nil, nil
  end

  --[[ Back walks the wizard in reverse, and from the first step it closes
       the window (Kevin, 2026-08-22). Every step therefore has a way out
       that is not "click empty space and hope" - which on a full screen is
       also the gesture that clears a slot. ]]
  local function go_back()
    if step == STEP_TARGET then
      step, page, pending = STEP_CATALOG, 1, nil
    elseif step == STEP_CATALOG then
      cursor, step, page = nil, STEP_LAYER, 1
      apply_preview()
    else
      close_panel()
    end
    details, hovered = nil, nil
  end

  local function on_click(target)
    if target == nil then
      close_panel()
    elseif target.kind == "back" then
      go_back()
    elseif target.kind == "slot" then
      select_slot(target)
    elseif target.kind == "row" then
      local row = target.row
      if row ~= nil then
        cursor = { source = row.source, label = row.label }
        step = STEP_CATALOG
        -- The category the user last picked survives; the page does not,
        -- since the listing itself may have changed under it.
        page = 1
        apply_preview()
      end
    elseif target.kind == "entry" then
      --[[ A type that takes a target gets the third step; the rest bind
           where they stand. Skipping the step for a `draw` or an `open`
           would otherwise ask which mob to aim a menu at. ]]
      if TARGETED_TYPES[target.entry.record.type] then
        pending = copy_record(target.entry.record)
        step, page = STEP_TARGET, 1
        details, hovered = nil, nil
      else
        commit(target.entry.record)
      end
    elseif target.kind == "target" then
      if pending ~= nil then
        local record = copy_record(pending)
        record.target = target.token
        commit(record)
      end
    elseif target.kind == "category" then
      category_index, page = target.index, 1
    elseif target.kind == "pager" then
      --[[ The pager CLICK still wraps, deliberately, where the wheel now
           clamps: its own label says "wheel to scroll", so it reads as a
           button that keeps moving rather than a position on the list. The
           spec argues the same. The two are inconsistent and a reviewer
           has said so - left alone because the wrap is what the existing
           test pins, and that is Kevin's call rather than a review's. ]]
      local pages = (catalog_view or target_view or {}).pages or 1
      page = page % pages + 1
    end
    redraw()
  end

  local function on_drop(origin, target)
    if origin.kind == "slot" then
      if target == nil then
        --[[ GENUINELY empty space only - the wiki's own words. The window
             fills the middle of the screen, so a drop landing on it is the
             commonest miss there is, and it cancels quietly rather than
             deleting. Deliberately
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
    slot, step, cursor, pending, press, details, hovered = nil, nil, nil, nil, nil, nil, nil
    -- Rebuilt every time edit mode opens: the inventory, the known spells
    -- and the job pair all move in play.
    --[[ Read once per open rather than per frame: the config is the
         player's own file and nothing else writes this key. A stored value
         that is not a pair of numbers is ignored rather than trusted -
         these files are hand-editable. ]]
    position = nil
    local stored = deps.window_pos ~= nil and deps.window_pos() or nil
    if type(stored) == "table" and type(stored.x) == "number" and type(stored.y) == "number" then
      position = { x = 0, y = 0 }
      position.x, position.y = clamp_to_screen(stored.x, stored.y)
    end
    rebuild_catalog()
    build_prims()
    redraw()
  end

  function self.close()
    if not active then
      return
    end
    active = false
    slot, step, cursor, pending, press, details, hovered = nil, nil, nil, nil, nil, nil, nil
    window, layer_view, catalog_view, target_view, catalog_groups = nil, nil, nil, nil, nil
    icon_memo = {}
    apply_preview()
    destroy_prims()
  end

  --[[ Put the window away without leaving edit mode. The set switch is
       live in edit mode, and the window's address was captured when the
       slot was clicked - so a set change under an open window would write
       the next bind into a set the player is no longer looking at. Closing
       the window is the only reading that cannot do that. ]]
  function self.deselect()
    if not active or slot == nil then
      return
    end
    close_panel()
    details, hovered = nil, nil
    redraw()
  end

  --[[ The cursor against the rows the slot offers NOW. It deliberately
       outlives a bind, so it can outlive its row - a subjob change takes a
       context out of reach and unequipping takes the weapon row away - and
       it can outlive its row's NAME: `sub:` and `wpn:` address whatever is
       worn or held, so the class under the cursor changes when the hand
       does. Both are answered from stack_rows rather than from the model,
       so the panel and the cursor can never hold different opinions of
       what a row is called. A cursor always has a slot (close_panel drops
       them together, and a new slot drops the cursor), so the rows are
       always there to compare against.

       Answers false when the row is gone; adopts the live label otherwise. ]]
  local function cursor_offered()
    if cursor == nil or slot == nil then
      return true
    end
    for _, row in ipairs(stack_rows()) do
      if row.source == cursor.source then
        cursor.label = row.label
        return true
      end
    end
    return false
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
    --[[ A stranded cursor is worse than a closed one: the bar goes on
         showing a context's world under a header naming it, the wizard
         walks to the end, and only the write says the layer is out of
         reach. Back to the layer step, with the preview taken down. ]]
    if not cursor_offered() then
      cursor, pending = nil, nil
      step, page = STEP_LAYER, 1
      details, hovered = nil, nil
      apply_preview()
    end
    redraw()
  end

  --- The layer the wizard is editing into, or nil.
  function self.layer()
    return cursor ~= nil and cursor.source or nil
  end

  --- The one window, and the step it is showing. Nil while no slot is
  --- picked - edit mode itself draws nothing until you click one.
  function self.window()
    return window
  end

  --- Exactly one of the three is non-nil, and only for the live step.
  function self.layer_view()
    return layer_view
  end

  function self.catalog_view()
    return catalog_view
  end

  function self.target_view()
    return target_view
  end

  function self.details()
    return details
  end

  --- The wrap budget, so a spec can assert against the same number the
  --- wrapping used rather than a copy that could drift from it.
  function self.detail_columns()
    return DETAIL_CHARS
  end

  --- Rebuild the resting details column from the target it was already on:
  --- a recast counts down whether or not the cursor moves. Called on the
  --- widget's own read cadence, never per frame.
  function self.refresh_details()
    -- Never mid-gesture: a drag owns the cursor, and the details it stood
    -- down stay down until the drop resolves.
    if not active or hovered == nil or (press ~= nil and press.drag) then
      return
    end
    local rebuilt = build_details(hovered)
    local before = details ~= nil and table.concat(details.lines, "\n") or nil
    local after = rebuilt ~= nil and table.concat(rebuilt.lines, "\n") or nil
    details = rebuilt
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
    if source == "wpn" or source:match("^wpn:") then
      return MARKS.wpn
    end
    return ""
  end

  function self.mouse(kind, x, y, delta)
    if not active then
      return false
    end
    if kind == MOVE then
      if press ~= nil then
        if press.target.kind == "header" and (press.drag or not inside(x, y, press.rect)) then
          --[[ The same threshold every other press here uses: a drag
               starts once the cursor LEAVES what it started on. Without it
               a one-pixel slip while clicking the strip wrote the config
               file. The grab point stays under the cursor either way, so
               the window does not jump to have its corner there. ]]
          press.drag = true
          position = { x = 0, y = 0 }
          position.x, position.y = clamp_to_screen(x - press.offset.x, y - press.offset.y)
          details, hovered = nil, nil
          redraw()
          return true
        end
        if not press.drag and not inside(x, y, press.rect) then
          press.drag = true
          -- The cursor left what it started on: this is a drag, so the
          -- details it was describing stand down - and the target they were
          -- built from goes with them, or the cadence rebuild would put
          -- them back under a cursor that is mid-gesture.
          details, hovered = nil, nil
          redraw()
        end
        -- Motion is the client's until a real drag is live - layout_mode's
        -- own convention. Blocking it for a press that is still a click
        -- would freeze the camera on every button-down.
        return press.drag
      end
      local target = hit(x, y)
      -- Keyed on the TARGET, not on the text: edit mode draws every side,
      -- so two slots holding the same action are ordinary, and a text-only
      -- gate would leave the column describing the slot the cursor has
      -- left.
      if target_key(target) == (details and details.key) then
        return false
      end
      hovered = target
      details = build_details(target)
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
      if target.kind == "header" and window ~= nil then
        press.offset = { x = x - window.x, y = y - window.y }
      end
      return true
    end
    if kind == LEFT_UP then
      local armed = press
      press = nil
      if armed == nil then
        return false
      end
      if armed.target.kind == "header" then
        -- Saved on the drop, not on every pixel: a drag is a stream of
        -- moves, and this writes a config file.
        if armed.drag and position ~= nil and deps.save_window_pos ~= nil then
          deps.save_window_pos(position.x, position.y)
        end
      elseif armed.drag then
        on_drop(armed.target, hit(x, y))
      else
        on_click(armed.target)
      end
      return true
    end
    if kind == WHEEL then
      -- Ours anywhere over the window, scrollable or not: the game zooming
      -- its camera under a window the player is reading is not wanted.
      if window == nil or not inside(x, y, window) then
        return false
      end
      local pages = (catalog_view or target_view or {}).pages
      if pages ~= nil and type(delta) == "number" and delta ~= 0 then
        --[[ Wheel down is forward, and BOTH ends clamp (Kevin,
             2026-08-22): they used to wrap, so scrolling off the end of a
             long list silently threw you back to the top and it read as the
             list having reset. ]]
        local move = delta < 0 and 1 or -1
        page = math.max(1, math.min(pages, page + move))
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
    press, details, hovered = nil, nil, nil
    window, layer_view, catalog_view, target_view = nil, nil, nil, nil
  end

  return self
end

return new
