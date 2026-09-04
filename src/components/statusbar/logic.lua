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

--[[ Status bar logic: the pure state machine behind the three bars. Given
     the player's buff list, the last duration packet and the clock, it
     answers what each bar draws (which ids, in which cell, with what timer
     text), where each cell sits, and every `//hud statusbar` command.

     It holds no prims and reads no client - statusbar.lua feeds it and draws
     what it says. The order and the filters are lib/buffs', one engine per
     bar so a message names the bar it is about; the priority table is the
     component's single shared one, handed to all three under each bar's own
     filter list (a view, which the lib edits in place for that reason).

     Two sources, matched by id rather than by slot: presence is the player's
     list (live the moment the client fills it in, and refreshed on every buff
     event by the service), and the expiries are the last 0x063 seen, which
     nothing re-sends after a reload until a buff changes. So icons can be up
     without timers, which is the honest state; the reverse never happens. ]]

local new_buffs = require("lib/buffs")
local categories = require("components/statusbar/categories")

local BARS = { "bar1", "bar2", "bar3" }
-- How a message names a bar, which is also how the user addresses it: the
-- first is the default and goes unnamed, partylist's `main` rule.
local NAMES = { bar1 = "statusbar", bar2 = "statusbar bar2", bar3 = "statusbar bar3" }
local LABELS = { bar1 = "statusbar bar1", bar2 = "statusbar bar2", bar3 = "statusbar bar3" }

-- XIV's four arrangements, by rows: 20x1, 10x2, 7x3, 5x4.
local COLUMNS_BY_ROWS = { [1] = 20, [2] = 10, [3] = 7, [4] = 5 }

-- The icon art is 32px; the timer sits in a band beneath it.
local ICON_SIZE = 32
local COLUMN_GAP = 2
local ROW_GAP = 2
local TIMER_BAND = 14
local TIMER_FONT = 10

-- Nothing on you runs for days; an expiry further off than this is a
-- sentinel for "no expiry", whatever wrap it decoded onto.
local MAX_TIMER = 100 * 3600

-- Layout mode force-shows every bar; with nothing on you there would be
-- nothing to grab. One of each category, with a spread of timers.
local PREVIEW = {
  { id = 33, left = 1500 }, -- haste
  { id = 40, left = 900 }, -- protect
  { id = 2, left = 45 }, -- sleep
  { id = 3, left = 20 }, -- poison
  { id = 251, left = 1700 }, -- Food
  { id = 253, left = 7000 }, -- Signet
}

-- Deliberately stricter than tonumber, which also accepts "0x84" and "1e2".
local function whole_number(word)
  if type(word) ~= "string" or not word:match("^%-?%d+$") then
    return nil
  end
  return tonumber(word)
end

local function new(deps)
  deps = deps or {}
  local config = deps.config or {}
  local resources = deps.resources or {}

  local self = {}

  local engines = {}
  for _, bar in ipairs(BARS) do
    engines[bar] = new_buffs({
      name = NAMES[bar],
      resources = resources,
      filter_path = NAMES[bar] .. " filter",
      -- The buff verbs take no bar word, so every bar's advice names the
      -- same path; and `buff filter` is refused below, so the hint must not
      -- offer it.
      buff_path = "statusbar buff",
      hint_verbs = { "list", "find", "top", "up", "down", "rank", "reset" },
    })
  end

  local buffs = nil
  local now = 0
  -- id -> its expiries in slot order, from the last packet.
  local expiries = {}
  local preview = false

  -- One view per bar entry, kept while nothing about the entry has changed;
  -- see view_of.
  local views = {}

  function self.set_config(new_config)
    config = new_config or {}
    views = {}
    for _, engine in pairs(engines) do
      engine.invalidate()
    end
  end

  function self.set_buffs(list)
    buffs = list
  end

  function self.set_time(t)
    now = t or 0
  end

  function self.apply_durations(list)
    expiries = {}
    for _, entry in ipairs(list or {}) do
      local slots = expiries[entry.id]
      if not slots then
        slots = {}
        expiries[entry.id] = slots
      end
      slots[#slots + 1] = entry.expires
    end
  end

  function self.set_preview(on)
    preview = on and true or false
  end

  --[[ Settings ------------------------------------------------------------ ]]

  -- The bar's own table, or nil where a hand-edited file left something
  -- else: nothing here indexes it, and the commands say so.
  local function bar_settings(bar)
    local bars = type(config.bars) == "table" and config.bars or {}
    local entry = bars[bar]
    if type(entry) ~= "table" then
      return nil
    end
    return entry
  end

  local function priority()
    if type(config.priority) ~= "table" then
      config.priority = {}
    end
    return config.priority
  end

  local function store_view(entry, view)
    entry.filters = view.filters
    entry.filter_mode = view.filter_mode
  end

  -- What the lib is handed: the shared order under this bar's lists. The
  -- lists are edited in place, but a mode change lands on the view, so
  -- `store_view` copies both back after a command. One view per entry is
  -- kept while nothing about it has changed, rather than a table per paint;
  -- a repair the lib makes is written back into the entry at once, so it is
  -- not redone every frame and rides the next save.
  local function view_of(entry)
    local held = views[entry]
    if
      held
      and held.priority == config.priority
      and held.filters == entry.filters
      and held.filter_mode == entry.filter_mode
    then
      return held
    end
    local view = engines.bar1.normalize({
      priority = priority(),
      filters = entry.filters,
      filter_mode = entry.filter_mode,
    })
    store_view(entry, view)
    views[entry] = view
    return view
  end

  local function shape(entry)
    local rows = tonumber(entry and entry.rows)
    if not COLUMNS_BY_ROWS[rows] then
      rows = 1
    end
    local cols = COLUMNS_BY_ROWS[rows]
    return cols, rows, cols * rows
  end

  --[[ The plan ------------------------------------------------------------ ]]

  function self.timer_text(remaining)
    if not remaining or remaining <= 0 or remaining > MAX_TIMER then
      return nil
    end
    if remaining < 60 then
      return tostring(math.max(1, math.floor(remaining)))
    end
    if remaining < 3600 then
      return math.floor(remaining / 60) .. "m"
    end
    return math.floor(remaining / 3600) .. "h"
  end

  local function source()
    if preview then
      local ids = {}
      for index, sample in ipairs(PREVIEW) do
        ids[index] = sample.id
      end
      return ids
    end
    return buffs
  end

  -- `seen` counts occurrences so a duplicate id takes the next expiry.
  local function timer_for(id, seen)
    if config.timers == false then
      return nil
    end
    if preview then
      for _, sample in ipairs(PREVIEW) do
        if sample.id == id then
          return self.timer_text(sample.left)
        end
      end
      return nil
    end
    seen[id] = (seen[id] or 0) + 1
    local slots = expiries[id]
    local expires = slots and slots[seen[id]]
    if not expires then
      return nil
    end
    return self.timer_text(expires - now)
  end

  -- Every id a bar would draw, past its capacity: filtered and in order.
  local function ids_for(bar, entry)
    return engines[bar].plan(source(), view_of(entry), { keep = categories.keep(entry.filter) })
  end

  --[[ What a bar draws: `cells` in fill order (left to right, top row first),
       each with its id, grid position and timer text; `total` is how many
       passed the filter before the capacity cut them. ]]
  function self.plan(bar)
    local entry = bar_settings(bar)
    local cols, rows, capacity = shape(entry)
    local plan = { cols = cols, rows = rows, capacity = capacity, total = 0, cells = {} }
    if not entry or not engines[bar] then
      return plan
    end

    local ids = ids_for(bar, entry)
    plan.total = #ids
    local seen = {}
    for index = 1, math.min(#ids, capacity) do
      local id = ids[index]
      plan.cells[index] = {
        id = id,
        col = (index - 1) % cols,
        row = math.floor((index - 1) / cols),
        timer = timer_for(id, seen),
      }
    end
    return plan
  end

  --[[ Geometry ------------------------------------------------------------ ]]

  -- The whole shape, full or empty, from the origin given: the origin never
  -- moves as buffs come and go, which is what get_bounds promises core.
  function self.bounds(bar, x, y, scale)
    local cols, rows = shape(bar_settings(bar))
    local width = cols * ICON_SIZE + (cols - 1) * COLUMN_GAP
    local height = rows * (ICON_SIZE + TIMER_BAND) + (rows - 1) * ROW_GAP
    return x, y, width * scale, height * scale
  end

  function self.geometry(bar, x, y, scale)
    local plan = self.plan(bar)
    local pitch_x = (ICON_SIZE + COLUMN_GAP) * scale
    local pitch_y = (ICON_SIZE + TIMER_BAND + ROW_GAP) * scale
    local cells = {}
    for index, cell in ipairs(plan.cells) do
      local cell_x = x + cell.col * pitch_x
      local cell_y = y + cell.row * pitch_y
      cells[index] = {
        id = cell.id,
        timer = cell.timer,
        x = cell_x,
        y = cell_y,
        size = ICON_SIZE * scale,
        text_x = cell_x,
        text_y = cell_y + ICON_SIZE * scale,
        -- Whole pixels: a fractional font size is not something a prim can
        -- draw, and layout mode scales down to 0.25.
        text_size = math.max(1, math.floor(TIMER_FONT * scale + 0.5)),
      }
    end
    return { cells = cells }
  end

  --[[ Commands ------------------------------------------------------------ ]]

  local function is_filter_name(word)
    for _, name in ipairs(categories.NAMES) do
      if name == word then
        return true
      end
    end
    return false
  end

  local function bar_line(bar)
    local entry = bar_settings(bar)
    if not entry then
      return ("%s: settings are not a table - try '//hud reset statusbar'"):format(LABELS[bar])
    end
    local cols, rows = shape(entry)
    local view = view_of(entry)
    -- A name that is not a filter restricts nothing; said, rather than
    -- printed as if it worked.
    local filter = tostring(entry.filter)
    if not is_filter_name(entry.filter) then
      filter = filter .. " (unknown - showing everything)"
    end
    return ("%s: filter %s, rows %d (%dx%d), filters %d (%s)"):format(
      LABELS[bar],
      filter,
      rows,
      cols,
      rows,
      #view.filters,
      view.filter_mode
    )
  end

  local function status(bar)
    if bar then
      return { bar_line(bar) }, false
    end
    local lines = {}
    for _, name in ipairs(BARS) do
      lines[#lines + 1] = bar_line(name)
    end
    lines[#lines + 1] = "  timers " .. (config.timers == false and "off" or "on")
    return lines, false
  end

  local function unknown(word)
    return { ("statusbar has no '%s' setting (filter, rows, timers, buff)"):format(tostring(word)) }, false
  end

  local function unusable(bar)
    return { ("%s settings are not a table - try '//hud reset statusbar'"):format(LABELS[bar]) }, false
  end

  local function set_filter(bar, entry, words)
    local word = words[2] and words[2]:lower() or nil
    if word and is_filter_name(word) then
      entry.filter = word
      return { ("%s now shows %s"):format(LABELS[bar], word) }, true
    end
    -- An edit sub-verb, or nothing at all (which lists): the lib's grammar.
    if word == nil or word == "add" or word == "remove" or word == "clear" or word == "list" or word == "mode" then
      local view = view_of(entry)
      local lines, changed = engines[bar].command(view, words, select(3, shape(entry)))
      store_view(entry, view)
      return lines, changed
    end
    return {
      ("//hud %s filter takes a category (%s) or an edit (add, remove, clear, list, mode)"):format(
        NAMES[bar],
        table.concat(categories.NAMES, ", ")
      ),
    },
      false
  end

  local function set_rows(bar, entry, word)
    local rows = whole_number(word)
    if not rows or not COLUMNS_BY_ROWS[rows] then
      return { ("//hud %s rows needs a number from 1 to 4"):format(NAMES[bar]) }, false
    end
    entry.rows = rows
    return { ("%s now draws %d rows (%dx%d)"):format(LABELS[bar], rows, COLUMNS_BY_ROWS[rows], rows) }, true
  end

  local function set_timers(word)
    word = word and word:lower() or nil
    if word ~= "on" and word ~= "off" then
      return { "//hud statusbar timers needs on or off" }, false
    end
    config.timers = word == "on"
    return { "statusbar timers " .. word }, true
  end

  -- What each bar draws right now, past its capacity: how you name a buff
  -- you just saw rather than one you can already name. `only` narrows it to
  -- one bar: three bars of 32 is a wall of chat.
  local function active(only)
    local lines = {}
    for _, bar in ipairs(BARS) do
      local entry = bar_settings(bar)
      if entry and (only == nil or only == bar) then
        local capacity = select(3, shape(entry))
        local ids = ids_for(bar, entry)
        if #ids == 0 then
          lines[#lines + 1] = ("%s (%s): nothing to draw"):format(LABELS[bar], tostring(entry.filter))
        else
          lines[#lines + 1] = ("%s (%s): %d, %d drawn"):format(
            LABELS[bar],
            tostring(entry.filter),
            #ids,
            math.min(#ids, capacity)
          )
          for index, id in ipairs(ids) do
            lines[#lines + 1] = ("  %s (%d)%s"):format(
              engines[bar].name(id),
              id,
              index > capacity and "  (not drawn)" or ""
            )
          end
        end
      end
    end
    return lines, false
  end

  local function buff_command(words)
    local verb = words[1] and words[1]:lower() or nil
    if verb == nil then
      return active()
    end
    if engines[verb] then
      if words[2] then
        return { ("//hud statusbar buff %s takes nothing after the bar - '%s' is not understood"):format(verb, words[2]) },
          false
      end
      return active(verb)
    end
    if verb == "filter" then
      return { "a filter list belongs to one bar: //hud statusbar [<bar>] filter add|remove|clear|list|mode" }, false
    end
    local entry = bar_settings("bar1")
    if not entry then
      return unusable("bar1")
    end
    local view = view_of(entry)
    local lines, changed = engines.bar1.command(view, words, select(3, shape(entry)))
    store_view(entry, view)
    -- The order is one table under three engines, each memoizing it, and
    -- the lib invalidated only the one it ran through.
    if changed then
      for _, engine in pairs(engines) do
        engine.invalidate()
      end
    end
    return lines, changed
  end

  --[[ `//hud statusbar [<bar>] <verb> ...`, the bar word leading so the verb
       grammar behind it is untouched; absent, the first bar is addressed.
       Returns the lines to print and whether anything changed, so the widget
       knows when to re-lay out and save. ]]
  function self.command(args)
    args = args or {}
    local first = args[1] and args[1]:lower() or nil
    if not first then
      return status()
    end

    local bar = engines[first] and first or nil
    local words = args
    if bar then
      words = {}
      for index = 2, #args do
        words[index - 1] = args[index]
      end
    end

    local verb = words[1] and words[1]:lower() or nil
    if verb == nil then
      return status(bar or "bar1")
    end

    if verb == "timers" or verb == "buff" then
      -- One switch and one order for all three, so a bar word is refused
      -- rather than silently dropped.
      if bar then
        return { ("%s is shared by every bar, so //hud statusbar %s takes no bar word"):format(verb, verb) }, false
      end
      if verb == "timers" then
        return set_timers(words[2])
      end
      local rest = {}
      for index = 2, #words do
        rest[index - 1] = words[index]
      end
      return buff_command(rest)
    end

    if verb == "filter" or verb == "rows" then
      bar = bar or "bar1"
      local entry = bar_settings(bar)
      if not entry then
        return unusable(bar)
      end
      if verb == "rows" then
        return set_rows(bar, entry, words[2])
      end
      return set_filter(bar, entry, words)
    end

    return unknown(words[1])
  end

  return self
end

return new
