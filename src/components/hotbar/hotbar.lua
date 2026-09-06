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

--[[ The hotbar: FFXIV's hotbar, ten slots in a row, one row per set - eight
     anchors (`bar1`..`bar8`). Row 1 follows the ACTIVE set; rows 2-8 are
     locked to sets 2-8, so row 1 duplicates one of them whenever the active
     set is not 1 - deliberately: row 1 is the one placed where it is
     easiest to reach (Kevin, 2026-09-05). Each row takes one of four shapes
     (10x1, 5x2, 2x5, 1x10; `//hud hotbar [<bar>] rows <n>`, the statusbar's
     grammar).

     It is the crossbar with a different face, and shares its engine so the
     two cannot drift: lib/actionbar/bar holds the bindings (this bar's own
     per-job files, keyed one side, `row`), the job scoping, the counts, the
     binder and the authoring CLI; lib/actionbar/slot draws each cell;
     lib/actionbar/service executes every press. What is this file's own is
     the geometry (render.lua), the keys (input.lua - the bare number row
     and CTRL/ALT/SHIFT rows, nothing of the crossbar's), the prims, and the
     framework contract routed by anchor the way partylist routes it.

     A row's prims are built the first time it is shown, not all 720 in the
     factory the way the crossbar builds its 365: seven of the eight rows
     ship off. ]]

local new_render = require("components/hotbar/render")
local new_input = require("components/hotbar/input")
local build_defaults = require("components/hotbar/defaults")
local new_slot = require("lib/actionbar/slot")
local new_bar = require("lib/actionbar/bar")
local grammars = require("lib/actionbar/grammar")
local new_actions = require("lib/actionbar/actions")

local ANCHORS = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" }
local ROW_INDEX = {}
for index, anchor in ipairs(ANCHORS) do
  ROW_INDEX[anchor] = index
end
-- The set number's gold: the crossbar's set label's.
local LABEL_COLOR = { 255, 215, 0 }
local MOUSE_LEFT_DOWN, MOUSE_LEFT_UP = 1, 2
-- The packets the bar reads for its slot counters and its weapon layer: the
-- same three the crossbar reads, for the same reasons (see its header).
local INVENTORY_CHUNK = 0x01E
local EQUIP_CHUNK = 0x050
local INVENTORY_READY_CHUNK = 0x01D
local MAIN_HAND_SLOT = 0
-- Riding a mount: the draw built-in's icon follows it.
local MOUNTED_BUFF = 252

local function new(ctx)
  local self = { name = "hotbar", alias = "hb", wants_store = true }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)
  local config = self.defaults
  local save = nil

  local service = assert(ctx.actions, "hotbar needs ctx.actions, the action service")
  local skillchain = service.skillchain
  local roulette = service.roulette
  local icon_for = new_actions({}).icon_for
  local render = new_render({ config = config, icon_for = icon_for })

  local function config_hide(key)
    local hide = config.hide
    return type(hide) == "table" and hide[key] == true
  end

  -- Per-anchor placement pushed by core, and the anchors core has switched
  -- off one at a time - kept apart because a hidden anchor is still PLACED.
  local placed = {}
  local hidden_anchors = {}
  local visible = false
  local preview = false
  local swallow_left_up = false
  -- The key machine, rebuilt on attach and dropped on detach: its absence is
  -- what says the widget is detached, and a detached bar draws nothing.
  local machine = nil
  local bar
  local function editing()
    return bar ~= nil and bar.editing()
  end

  -- One entry per anchor: its slots and label once built, and whether the
  -- last refresh left it on screen.
  local rows = {}
  for _, anchor in ipairs(ANCHORS) do
    rows[anchor] = { slots = nil, label = nil, shown = false }
  end

  local function anchor_at(anchor)
    if hidden_anchors[anchor] then
      return nil
    end
    return placed[anchor]
  end

  --- The shape a row is drawn in, off its config; a hand-broken value draws
  --- the shipped 10x1 rather than nothing.
  local function rows_of(anchor)
    local bars = type(config.bars) == "table" and config.bars or {}
    local entry = type(bars[anchor]) == "table" and bars[anchor] or {}
    if render.columns_for(entry.rows) ~= nil then
      return entry.rows
    end
    return 1
  end

  --- The set a row shows: the active set on row 1, its own number on the
  --- rest. nil while no job is scoped.
  local function set_of(anchor)
    if bar.scoped() == nil then
      return nil
    end
    if anchor == "bar1" then
      return bar.bindings().active_set()
    end
    return ROW_INDEX[anchor]
  end

  function self.anchors()
    return ANCHORS
  end

  local function dress_label(label)
    local stroke = type(config.text_stroke) == "table" and config.text_stroke or {}
    label.font(config.font or "sans-serif")
    label.size(render.label_size())
    label.color(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3])
    label.alpha(255)
    label.stroke_width(stroke.width or 0)
    label.stroke_color(stroke.r or 0, stroke.g or 0, stroke.b or 0)
    label.stroke_alpha(stroke.a or 255)
    label.bg_visible(false)
    label.right_justified(false)
  end

  --[[ Prims for one row, on demand: ten shared slots and the set number.
       Nothing without the ctx's constructors (the headless shape the
       contract specs run). ]]
  local function build_row(anchor)
    local row = rows[anchor]
    if row.slots ~= nil or ctx.new_image == nil or ctx.new_text == nil or ctx.asset == nil then
      return
    end
    row.slots = {}
    for slot = 1, render.slot_count() do
      row.slots[slot] = new_slot({
        new_image = ctx.new_image,
        new_text = ctx.new_text,
        asset = ctx.asset,
        config = function()
          return config
        end,
        render = function()
          return render
        end,
        screen_width = function()
          return screen_width
        end,
        hide = config_hide,
        key = anchor .. ":" .. slot,
      })
      row.slots[slot].dress()
    end
    local label = ctx.new_text()
    label.text("")
    label.hide()
    dress_label(label)
    row.label = label
  end

  local function each_cell(visit)
    for _, anchor in ipairs(ANCHORS) do
      local row = rows[anchor]
      if row.slots ~= nil then
        for slot = 1, render.slot_count() do
          visit(row.slots[slot], anchor, slot)
        end
      end
    end
  end

  -- Repositions one row's prims from its anchor's origin and scale.
  local function layout(only)
    for _, anchor in ipairs(ANCHORS) do
      local row = rows[anchor]
      local entry = placed[anchor]
      if (only == nil or only == anchor) and row.slots ~= nil and entry ~= nil and entry.pos ~= nil then
        local shape = rows_of(anchor)
        local metrics = render.metrics(shape)
        for slot = 1, render.slot_count() do
          local x, y = render.slot_pos(shape, slot, metrics)
          row.slots[slot].place(entry.pos.x, entry.pos.y, x, y, entry.scale)
        end
        local lx, ly = render.label_pos(shape)
        row.label.pos(entry.pos.x + lx * entry.scale, entry.pos.y + ly * entry.scale)
        row.label.size(math.floor(render.label_size() * entry.scale + 0.5))
      end
    end
  end

  local function dress_all()
    each_cell(function(cell)
      cell.dress()
    end)
    for _, anchor in ipairs(ANCHORS) do
      if rows[anchor].label ~= nil then
        dress_label(rows[anchor].label)
      end
    end
  end

  --[[ Whether a slot of a SHOWN row is actually drawn: `hide.empty_slots`
       is the one thing that can hide one, and the binder gets empty slots
       back regardless - an invisible slot is still a drop target. ONE
       predicate for drawing and for the click hit-test. ]]
  local function slot_drawn(anchor, slot)
    local row = rows[anchor]
    local cell = row.slots ~= nil and row.slots[slot] or nil
    if cell == nil then
      return false
    end
    return cell.record() ~= nil or editing() or not config_hide("empty_slots")
  end

  --[[ Only the rows on screen, with the placement they are drawn at and the
       set they address, so nothing here can claim a row that is not there.
       The binder hit-tests its drops with this and the live click answers
       with it, over ONE set of rects. ]]
  local function painted_groups()
    local list = {}
    for _, anchor in ipairs(ANCHORS) do
      local row = rows[anchor]
      local entry = placed[anchor]
      local set = set_of(anchor)
      if row.shown and entry ~= nil and entry.pos ~= nil and set ~= nil then
        list[#list + 1] = {
          key = anchor,
          x = entry.pos.x,
          y = entry.pos.y,
          scale = entry.scale,
          set = set,
          side = "row",
          rows = rows_of(anchor),
        }
      end
    end
    return list
  end

  -- Forward-declared: refresh() below builds a row on first show and
  -- paints it, and paint needs the state below refresh.
  local paint_row

  --[[ Applies which rows are on screen. Core owns whether the widget is
       visible at all; this owns what "visible" shows. A row shown for the
       first time is NOT built here: core's apply sends the bare show()
       first and restates each anchor after it, so every row is shown and
       hidden again inside one apply, and building here would build all
       eight at every login. The tick builds what is still shown then. ]]
  local function refresh()
    for _, anchor in ipairs(ANCHORS) do
      local row = rows[anchor]
      local entry = anchor_at(anchor)
      local shown = visible and machine ~= nil and entry ~= nil and entry.pos ~= nil
      row.shown = shown
      if row.slots ~= nil then
        local set = set_of(anchor)
        -- Gated like the slots' own writes: core runs a refresh per mouse
        -- move of a layout-mode drag.
        local label = (shown and set ~= nil) and tostring(set) or nil
        if label ~= row.label_text then
          row.label_text = label
          if label ~= nil then
            row.label.text(label)
            row.label.show()
          else
            row.label.hide()
          end
        end
        for slot = 1, render.slot_count() do
          row.slots[slot].show(shown, slot_drawn(anchor, slot))
        end
      end
    end
  end

  -- Re-resolves one slot's content: the record through the bar's live
  -- layer stack, its meta, then the slot draws it.
  local function paint_slot(anchor, slot, state)
    local row = rows[anchor]
    local cell = row.slots ~= nil and row.slots[slot] or nil
    if cell == nil then
      return
    end
    local record, source = nil, nil
    local set = set_of(anchor)
    if set ~= nil then
      record, source = bar.bindings().resolve(set, "row", slot)
    end
    if record ~= nil then
      state = state or bar.draw_state()
    end
    cell.paint(record, bar.meta_for(record), {
      state = state,
      builtin = record ~= nil and icon_for(record, state) or nil,
      mark = (record ~= nil and editing()) and bar.binder().mark(source) or "",
      resolve_icon = bar.pick_icon,
      item_icon = bar.item_icon,
    })
    local entry = placed[anchor]
    if entry ~= nil and entry.pos ~= nil then
      local shape = rows_of(anchor)
      local x, y = render.slot_pos(shape, slot)
      cell.place(entry.pos.x, entry.pos.y, x, y, entry.scale)
    end
  end

  function paint_row(anchor, state)
    for slot = 1, render.slot_count() do
      paint_slot(anchor, slot, state)
    end
  end

  local function repaint()
    local state = nil
    for _, anchor in ipairs(ANCHORS) do
      if rows[anchor].slots ~= nil then
        -- One draw-state read per repaint, not one per slot.
        state = state or bar.draw_state()
        paint_row(anchor, state)
      end
    end
    -- Which ids need counting can only change here, and rarely does.
    bar.check_bound_items()
    refresh()
    bar.binder().refresh()
  end

  -- An icon landing on disk can only change slots still waiting for item art.
  local function repaint_unresolved_items()
    local state = nil
    each_cell(function(cell, anchor, slot)
      if cell.awaiting_item_icon() then
        state = state or bar.draw_state()
        paint_slot(anchor, slot, state)
      end
    end)
    refresh()
  end

  local function flash(anchor, slot)
    local row = rows[anchor]
    local cell = row.slots ~= nil and row.slots[slot] or nil
    if cell ~= nil then
      cell.flash()
    end
  end

  --[[ Fire one slot of one row, whatever pointed at it - a key or a click.
       Everything after the resolve is the bar's and then the service's. A
       row need not be on screen to be fired: XIV's own rule, a hidden
       hotbar's binds still work. ]]
  local function fire_at(anchor, slot)
    local set = set_of(anchor)
    if set == nil then
      return
    end
    bar.fire(set, "row", slot, function()
      flash(anchor, slot)
    end)
  end

  local function chain_result(record, meta)
    if record.type == "ws" and meta.ws_id ~= nil then
      return skillchain.result(meta.ws_id, "weapon_skills")
    elseif (record.type == "ja" or record.type == "pet") and meta.ability_id ~= nil then
      return skillchain.result(meta.ability_id, "job_abilities")
    end
    return nil
  end

  local function mount_facts()
    if roulette == nil then
      return nil
    end
    return { blocked = not roulette.mounted() and roulette.blocked(), cooldown = roulette.cooldown() }
  end

  --[[ A row built for layout mode's force-show and switched back off is
       torn down once the preview is over and core's per-anchor hides have
       landed - which is only knowable from the tick, since core sends the
       preview flag BEFORE it restates each anchor. Otherwise one `//hud
       layout` visit would leave seven rows of prims resident for the
       session, the very cost the lazy build exists to avoid. Only a row
       hidden by its own anchor: a whole-widget hide (suppression) keeps its
       prims, as the crossbar does, rather than rebuilding on every
       cutscene. ]]
  local function prune_hidden_rows()
    for _, anchor in ipairs(ANCHORS) do
      local row = rows[anchor]
      if row.slots ~= nil and hidden_anchors[anchor] then
        for _, cell in ipairs(row.slots) do
          cell.destroy()
        end
        row.label.destroy()
        row.slots, row.label, row.label_text = nil, nil, nil
      end
    end
  end

  -- A row still shown once core's apply has settled is built now, once,
  -- and painted; a repaint afterwards keeps it current.
  local function build_shown_rows()
    local built = false
    for _, anchor in ipairs(ANCHORS) do
      local row = rows[anchor]
      if row.shown and row.slots == nil then
        build_row(anchor)
        built = built or row.slots ~= nil
      end
    end
    if built then
      layout()
      repaint()
    end
  end

  local function tick()
    bar.tick_scope(ctx.now ~= nil and ctx.now() or 0)
    bar.sync_weapon()
    if bar.drain_icons() then
      repaint_unresolved_items()
    end
    if bar.scoped() == nil or not visible then
      return
    end
    build_shown_rows()
    if not preview then
      prune_hidden_rows()
    end
    -- The per-slot chain results only while the window is actually open;
    -- the border animation's clock advances once per tick.
    local sc_delay, sc_window = skillchain.window()
    local chain_step = nil
    if sc_window > 0 and sc_delay <= 0 and not config_hide("skillchain_icon") then
      chain_step = render.chain_tick()
    end
    bar.recount_if_dirty()
    bar.refresh_reads(ctx.generation and ctx.generation() or nil)
    local reads = bar.reads()
    local player = reads.player
    local ability_recasts = reads.ability_recasts
    local facts = {
      player = player,
      vitals = player and player.vitals or {},
      spell_recasts = reads.spell_recasts,
      ability_recasts = ability_recasts,
      chain_step = chain_step,
      counter = function(record, meta)
        return bar.counter_for(record, meta, player, ability_recasts)
      end,
      chain_result = chain_result,
      mount = mount_facts,
    }
    for _, anchor in ipairs(ANCHORS) do
      local row = rows[anchor]
      if row.shown and row.slots ~= nil then
        for slot = 1, render.slot_count() do
          row.slots[slot].tick(facts)
        end
      end
    end
  end

  --[[ Commands ------------------------------------------------------------
       `//hud hotbar [<bar>] rows <1|2|5|10>` is the widget's; the bare form
       lists every row; a bar word alone lists that row. The common roster
       (bind, set, cycle, list, edit ...) is the bar's and takes NO bar word:
       a set is a set whatever row draws it, so one in front is refused
       rather than dropped. ]]
  local COLUMNS_FORM = "rows <1|2|5|10> - 10x1, 5x2, 2x5 or 1x10"

  local function row_line(anchor)
    local entry = placed[anchor]
    local on = visible and entry ~= nil and not hidden_anchors[anchor]
    local shape = rows_of(anchor)
    local set = set_of(anchor)
    local line = ("  %s: %s, %dx%d"):format(anchor, on and "on" or "off", render.columns_for(shape), shape)
    if set ~= nil then
      line = line .. ", set " .. set .. (anchor == "bar1" and " (active)" or "")
    end
    return line
  end

  local function status_lines(only)
    local lines = bar.status_lines()
    if type(lines) == "string" then
      lines = { lines }
    end
    for _, anchor in ipairs(ANCHORS) do
      if only == nil or only == anchor then
        lines[#lines + 1] = row_line(anchor)
      end
    end
    return lines
  end

  local function set_rows(anchor, word)
    local shape = tonumber(word)
    if shape == nil or render.columns_for(shape) == nil then
      return "hotbar: " .. COLUMNS_FORM
    end
    config.bars = type(config.bars) == "table" and config.bars or {}
    config.bars[anchor] = type(config.bars[anchor]) == "table" and config.bars[anchor] or {}
    config.bars[anchor].rows = shape
    if save ~= nil then
      save()
    end
    -- A reshape re-lays the same prims from the same origin; nothing is
    -- rebuilt, and core reads the new footprint the next time it asks.
    layout(anchor)
    repaint()
    return ("hotbar: %s now draws %d rows (%dx%d)"):format(anchor, shape, render.columns_for(shape), shape)
  end

  local function dispatch_command(args)
    args = args or {}
    local first = type(args[1]) == "string" and args[1]:lower() or nil
    local row_word = nil
    local words = args
    if first ~= nil and ROW_INDEX[first] ~= nil then
      row_word = first
      words = {}
      for index = 2, #args do
        words[index - 1] = args[index]
      end
    end
    local verb = type(words[1]) == "string" and words[1]:lower() or nil
    if verb == nil or verb == "" then
      return status_lines(row_word)
    end
    if verb == "rows" then
      if #words > 2 then
        return "hotbar: " .. COLUMNS_FORM
      end
      return set_rows(row_word or "bar1", words[2])
    end
    if row_word ~= nil then
      return "hotbar: " .. verb .. " takes no row word - a set is a set whatever row draws it"
    end
    return bar.command(words)
  end

  --[[ The bar's state, built at the foot: every dep above is a local. ]]
  bar = new_bar({
    name = "hotbar",
    grammar = grammars.hotbar(),
    views = false,
    help_extra = { "[<bar>] rows <1|2|5|10> - 10x1, 5x2, 2x5 or 1x10 (bar1 when no row is named)" },
    ctx = ctx,
    config = function()
      return config
    end,
    save = function()
      if save ~= nil then
        save()
      end
    end,
    render = function()
      return render
    end,
    groups = painted_groups,
    cells = each_cell,
    repaint = repaint,
    visible = function()
      return visible
    end,
    on_edit = function()
      -- From here the binder answers the mouse, so a debt the bar took is
      -- owed to nothing.
      swallow_left_up = false
    end,
  })

  --[[ The widget contract ------------------------------------------------- ]]

  function self.attach(new_config, persist, store)
    screen_width = ctx.screen()
    config = type(new_config) == "table" and new_config or self.defaults
    save = persist
    render = new_render({ config = config, icon_for = icon_for })
    bar.attach(store)
    each_cell(function(cell)
      cell.reset()
    end)
    machine = new_input({
      chat_open = ctx.chat_open,
      suppressed = ctx.suppressed,
      layout_mode = ctx.layout_active,
      -- ANY bar's binder, not just this one's: the pair goes inert together.
      edit_mode = function()
        return service.edit_owner() ~= nil
      end,
      --[[ Disabled means the USER-hidden case: a hotbar the player turned
           off keeps its keys with the game. Core's user flag is the one
           truthful source - suppression and a user hide both reach this
           widget as hide(). Suppression is plain inertness here too: no key
           of the hotbar's is worth protecting through a cutscene. ]]
      disabled = function()
        -- And a bar with no job scoped has nothing to fire: the row is
        -- the game's until the client names one.
        if bar.scoped() == nil then
          return true
        end
        if ctx.component_visible ~= nil then
          return ctx.component_visible() ~= true
        end
        return not visible
      end,
    })
    dress_all()
    layout()
    bar.try_scope()
    repaint()
  end

  function self.detach()
    swallow_left_up = false
    bar.detach()
    machine = nil
    each_cell(function(cell)
      cell.reset()
    end)
    refresh()
  end

  function self.on_keyboard(key, down, flags, blocked)
    if machine == nil then
      return false
    end
    local intent, block = machine.on_key(key, down, flags, blocked)
    if intent ~= nil and intent.cycle ~= nil then
      -- The active set moves row 1, through the same path the CLI's cycle
      -- takes (the machine's edit_mode guard keeps a key out while a
      -- binder is open, so the put-away in set_changed never fires here).
      local before = bar.bindings().active_set()
      if bar.bindings().cycle(intent.cycle) ~= nil then
        bar.set_changed(before)
      end
    elseif intent ~= nil then
      fire_at(intent.bar, intent.slot)
    end
    return block
  end

  function self.update(event, a, ...)
    if event == nil then
      tick()
      return
    end
    if event == "lose focus" then
      if machine ~= nil then
        machine.focus_lost()
      end
    elseif event == "job change" then
      bar.on_job_change(a, ...)
    elseif event == "gain buff" or event == "lose buff" then
      bar.sync_buffs()
      if a == MOUNTED_BUFF then
        repaint()
      end
    elseif event == "status" then
      bar.sync_weapon()
    elseif event == "add item" or event == "remove item" then
      bar.on_item_event(a)
    elseif event == "chunk" then
      if a == INVENTORY_CHUNK and bar.counts_from_inventory() then
        bar.mark_counts_dirty()
      end
      if a == INVENTORY_READY_CHUNK then
        bar.mark_weapon_dirty()
      elseif a == EQUIP_CHUNK then
        local raw = ...
        local equip = ctx.parse_packet ~= nil and ctx.parse_packet(raw) or nil
        local moved = type(equip) == "table" and equip["Equipment Slot"] or nil
        if moved == nil or moved == MAIN_HAND_SLOT then
          bar.mark_weapon_dirty()
        end
      end
    end
  end

  function self.set_pos(x, y, anchor)
    local entry = placed[anchor]
    if entry ~= nil and entry.pos ~= nil and entry.pos.x == x and entry.pos.y == y then
      return
    end
    if entry == nil then
      entry = { scale = 1 }
      placed[anchor] = entry
    end
    entry.pos = { x = x, y = y }
    layout(anchor)
  end

  function self.set_scale(scale, anchor)
    local entry = placed[anchor]
    if entry ~= nil and entry.scale == scale then
      return
    end
    if entry == nil then
      entry = {}
      placed[anchor] = entry
    end
    entry.scale = scale
    layout(anchor)
  end

  function self.set_preview(on)
    local wanted = on == true
    if wanted == preview then
      return
    end
    preview = wanted
    swallow_left_up = false
    if preview then
      -- Layout mode owns the mouse from here; the binder cannot share it.
      bar.close_edit()
    end
    refresh()
  end

  function self.show(anchor)
    if anchor == nil then
      -- Core calls this on every apply, so a layout-mode drag calls it on
      -- every mouse move; a widget already on screen with nothing to
      -- restore must not repaint eighty slots for it.
      local restored = next(hidden_anchors) ~= nil
      hidden_anchors = {}
      if visible and not restored then
        return
      end
      visible = true
      repaint()
      return
    end
    if hidden_anchors[anchor] then
      hidden_anchors[anchor] = nil
      if visible then
        repaint()
      end
    end
  end

  function self.hide(anchor)
    if anchor ~= nil then
      if not hidden_anchors[anchor] then
        hidden_anchors[anchor] = true
        refresh()
      end
      return
    end
    visible = false
    swallow_left_up = false
    -- Suppression and a user hide both arrive here: the cast this bar
    -- pressed does not outlive it; a countdown goes only under suppression.
    service.bar_hidden("hotbar")
    bar.close_edit()
    refresh()
  end

  -- The same origin set_pos was given, with the row's real footprint.
  function self.get_bounds(anchor)
    local entry = placed[anchor]
    if entry == nil or entry.pos == nil then
      return nil
    end
    local width, height = render.bounds(rows_of(anchor), entry.scale)
    return entry.pos.x, entry.pos.y, width, height
  end

  function self.handle_command(args)
    return dispatch_command(args)
  end

  function self.on_mouse(mouse_type, x, y, delta)
    if editing() then
      return bar.binder().mouse(mouse_type, x, y, delta) == true
    end
    --[[ Another bar's binder is open: the click is that binder's, whatever
         it lands on - core does not short-circuit the mouse, so this bar
         would otherwise fire a slot under the other's picker (the shipped
         hotbar row sits inside the crossbar's binder window). ]]
    if service.edit_owner() ~= nil then
      return false
    end
    if mouse_type == MOUSE_LEFT_UP then
      local owed = swallow_left_up
      swallow_left_up = false
      return owed
    end
    if mouse_type ~= MOUSE_LEFT_DOWN then
      return false
    end
    swallow_left_up = false
    if preview or (ctx.layout_active ~= nil and ctx.layout_active()) then
      return false
    end
    -- A left-click on a slot fires it; the row under the cursor supplies
    -- the set. An empty slot is silent but still ours.
    local rect = render.slot_at(painted_groups(), x, y, function(candidate)
      return slot_drawn(candidate.key, candidate.slot)
    end)
    if rect == nil then
      return false
    end
    fire_at(rect.key, rect.slot)
    swallow_left_up = true
    return true
  end

  function self.destroy()
    bar.destroy()
    for _, anchor in ipairs(ANCHORS) do
      local row = rows[anchor]
      if row.slots ~= nil then
        for _, cell in ipairs(row.slots) do
          cell.destroy()
        end
        row.label.destroy()
        row.slots, row.label = nil, nil
      end
    end
  end

  return self
end

return new
