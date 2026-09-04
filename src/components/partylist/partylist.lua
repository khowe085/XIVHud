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

--[[ Party List -- the FFXIV party list for FFXI, on XIVParty's xiv art.

     ONE registered component over three lists: the main party and the two
     alliance parties, each placed independently through an anchor of the same
     name. `new_list` below is the whole of one list -- its own logic instance,
     its own prims, its own box -- and `new` builds three of them and routes
     the contract by anchor. A list still knows only its own variant, which
     picks which party keys it reads and which of the two row layouts it draws.

     Per-list visibility is the framework's: core sends `show(<list>)` and
     `hide(<list>)` for one anchor's own switch, and the bare pair for the
     widget as a whole. A right-click in layout mode still toggles all three
     together; SHIFT + right-click, and `//hud show|hide partylist <list>`,
     address one. The component holds no on/off of its own beside it.

     This file owns prims and nothing else. What to draw comes from logic.lua,
     whether to draw comes from the framework. A row's prims are built when a
     member arrives and disposed the moment the row empties -- a full alliance
     is around 470 prims, so a solo player should not be paying for six rows
     of them.

     Every prim is created non-draggable: a widget is a group, and the
     framework drags the group from `//hud layout`. ]]

local new_logic = require("components/partylist/logic")
local build_defaults = require("components/partylist/defaults")
local layouts = require("components/partylist/layout")
local packet_parsers = require("components/partylist/packets")

-- Art lives at the addon root now (`assets/`), shared rather than owned,
-- so layout's own `assets/...` paths need nothing in front of them.

local PARSED_PACKETS = {
  [packet_parsers.ALLIANCE] = true,
  [packet_parsers.PARTY_MEMBER] = true,
  [packet_parsers.CHAR] = true,
}

--[[ One list: the prims, the logic instance and the placement for a single
     anchor. It implements the widget contract in the singular -- no anchor
     argument reaches it -- and `new` below is what turns three of these into
     one component. ]]
local function new_list(ctx, variant, defaults)
  local self = {}

  local layout = layouts[variant == "main" and "main" or "alliance"]
  local config = defaults
  local logic = new_logic({ variant = variant, config = config, resources = ctx.resources or {} })

  local attached = false
  -- The service's read counter as of the last roster rebuild; nil until the
  -- first frame, which is why the first one always rebuilds.
  local last_generation = nil
  local pos = nil
  local scale = 1
  local preview = false
  local visible = false
  -- hide_solo: the framework says the widget is on screen, the widget draws
  -- nothing anyway. Kept apart from `visible` so neither has to know about the
  -- other's reasons.
  local suppressed = false
  local margin = layout.margin
  local box = {
    width = margin.left + layout.column_width * layout.columns + margin.right,
    height = margin.top + layout.row_height + margin.bottom,
  }

  --[[ Whether this list puts anything on screen at all. `visible` is what the
       framework last said about THIS list - core pushes the anchor's own
       switch through show/hide, and force-shows every one of them in layout
       mode, so a list switched off is still draggable without this knowing
       why. hide_solo silences it independently. An unplaced list is silenced
       too: nothing has told it where it is, so its background would go up at
       whatever position its prims were created with. Core places every anchor
       before it shows one, so that last term is a defence rather than a live
       path. ]]
  local function drawing()
    return visible and pos ~= nil and not suppressed
  end

  -- The art overhangs its column rectangle, so the widget's own origin is the
  -- top-left of everything it draws, and the row grid starts inside it.
  local function content_origin()
    return pos.x + margin.left * scale, pos.y + margin.top * scale
  end
  local rows = {}

  --[[ Prim helpers ------------------------------------------------------- ]]

  local function image(texture, color)
    local prim = ctx.new_image()
    prim.draggable(false)
    prim.repeat_xy(1, 1)
    -- The prim must not size itself to its texture: fills are stretched to the
    -- eased width and everything is multiplied by the widget scale.
    prim.fit(false)
    if texture then
      prim.path(ctx.asset(texture))
    end
    color = color or { r = 255, g = 255, b = 255, a = 255 }
    prim.color(color.r, color.g, color.b)
    prim.alpha(color.a or 255)
    prim.hide()
    return prim
  end

  local function text(spec)
    local prim = ctx.new_text()
    prim.draggable(false)
    prim.bg_visible(false)
    prim.bg_alpha(0)
    prim.font(spec.font)
    prim.color(spec.color.r, spec.color.g, spec.color.b)
    prim.alpha(spec.color.a or 255)
    prim.stroke_width(spec.stroke_width)
    prim.stroke_color(spec.stroke.r, spec.stroke.g, spec.stroke.b)
    prim.stroke_alpha(spec.stroke.a)
    -- Deliberately NOT right-justified: texts.pos adds the screen width to x
    -- when the right flag is set, which would put these off screen. XIVParty's
    -- own alignRight offsets are tuned against the same behaviour.
    prim.hide()
    return prim
  end

  --[[ A row's prims. Built on demand, disposed when the row empties, and
       always laid out relative to the list origin so a group move is one
       recompute rather than a stored screen position per prim. ]]
  local function new_row()
    local row = { prims = {}, bars = {}, buffs = {}, showing = {}, written = {}, placed = {}, by_key = {} }

    local function track(prim)
      row.prims[#row.prims + 1] = prim
      return prim
    end

    --[[ Built in the layout's z-order, lowest first. Windower's own libraries
         expose no depth control, so creation order is all there is: the cursor
         has to exist before the bars or it paints over them.

         Which way round the client actually draws them is not something this
         devcontainer can settle -- if the cursor turns out to be *under* the
         row art in a live client, reverse this list, not the layout. ]]
    local builders = {
      [1] = function()
        row.cursor = track(image(layout.row.cursor.texture, layout.row.cursor.color))
      end,
      [5] = function()
        local icon = layout.row.job_icon
        row.job_icon = {
          highlight = track(image(icon.highlight.texture, icon.highlight.color)),
          bg = track(image(icon.bg.texture, icon.bg.color)),
          gradient = track(image(icon.gradient.texture, icon.gradient.color)),
          icon = track(image(nil)),
          frame = track(image(icon.frame.texture, icon.frame.color)),
        }
      end,
      [6] = function()
        row.name = track(text(layout.row.name))
      end,
      [7] = function()
        row.zone = track(text(layout.row.zone))
      end,
      [8] = function()
        if layout.row.job then
          row.job = track(text(layout.row.job))
          row.sub_job = track(text(layout.row.sub_job))
        end
      end,
      [10] = function()
        row.leader = {
          party = track(image(layout.row.leader.party.texture)),
          alliance = track(image(layout.row.leader.alliance.texture)),
          quartermaster = track(image(layout.row.leader.quartermaster.texture)),
        }
      end,
      [11] = function()
        if layout.row.range then
          row.range = {
            near = track(image(layout.row.range.near.texture)),
            far = track(image(layout.row.range.far.texture)),
            distance = track(text(layout.row.range.distance)),
          }
        end
      end,
      [12] = function()
        if layout.row.buff_icons then
          local cap = 0
          for _, count in ipairs(layout.row.buff_icons.icons_by_row) do
            cap = cap + count
          end
          for index = 1, cap do
            row.buffs[index] = track(image(nil))
          end
        end
      end,
    }

    for _, spec in ipairs(layout.row.bars) do
      builders[spec.z_order] = function()
        local bar = {
          spec = spec,
          bg = track(image(spec.bg.texture, spec.bg.color)),
          fill = track(image(spec.fill.texture, spec.fill.color)),
          fg = track(image(spec.fg.texture, spec.fg.color)),
        }
        if spec.value then
          bar.value = track(text(spec.value))
        end
        row.bars[spec.key] = bar
      end
    end

    for z = 0, 12 do
      if builders[z] then
        builders[z]()
      end
    end

    return row
  end

  local function dispose_row(slot)
    local row = rows[slot]
    if not row then
      return
    end
    for _, prim in ipairs(row.prims) do
      prim.destroy()
    end
    rows[slot] = nil
  end

  --[[ Placement ---------------------------------------------------------- ]]

  -- Every prim is placed against the list origin, so `set_pos` is the only
  -- thing that ever needs to know where on screen the list is.
  local function place(prim, origin_x, origin_y, spec_pos, spec_size)
    prim.pos(origin_x + spec_pos[1] * scale, origin_y + spec_pos[2] * scale)
    if spec_size then
      prim.size(spec_size[1] * scale, spec_size[2] * scale)
    end
  end

  local function place_text(prim, origin_x, origin_y, spec)
    prim.pos(origin_x + spec.pos[1] * scale, origin_y + spec.pos[2] * scale)
    -- Whole pixels: a fractional font size is not something a prim can draw.
    prim.size(math.max(1, math.floor(spec.size * scale + 0.5)))
  end

  local function place_row(row, plan)
    local origin_x, origin_y = content_origin()
    local x = origin_x + plan.offset_x * scale
    local y = origin_y + plan.offset_y * scale
    row.placed.x, row.placed.y, row.placed.buff_rows = x, y, plan.buff_rows

    for _, spec in ipairs(layout.row.bars) do
      local bar = row.bars[spec.key]
      local bar_x = x + spec.pos[1] * scale
      local bar_y = y + spec.pos[2] * scale
      place(bar.bg, bar_x, bar_y, spec.bg.pos, spec.bg.size)
      place(bar.fg, bar_x, bar_y, spec.fg.pos, spec.fg.size)
      -- The fill's width is written by render(); only its origin is fixed.
      bar.fill.pos(bar_x + spec.fill.pos[1] * scale, bar_y + spec.fill.pos[2] * scale)
      if bar.value then
        place_text(bar.value, bar_x, bar_y, spec.value)
      end
    end

    local icon = layout.row.job_icon
    local icon_x = x + icon.pos[1] * scale
    local icon_y = y + icon.pos[2] * scale
    local icon_scale = icon.scale[1]
    for key, part in pairs({
      highlight = icon.highlight,
      bg = icon.bg,
      gradient = icon.gradient,
      icon = icon.icon,
      frame = icon.frame,
    }) do
      row.job_icon[key].pos(icon_x + part.pos[1] * icon_scale * scale, icon_y + part.pos[2] * icon_scale * scale)
      row.job_icon[key].size(part.size[1] * icon_scale * scale, part.size[2] * icon_scale * scale)
    end

    local leader = layout.row.leader
    local leader_x = x + leader.pos[1] * scale
    local leader_y = y + leader.pos[2] * scale
    local leader_parts = { party = leader.party, alliance = leader.alliance, quartermaster = leader.quartermaster }
    for key, part in pairs(leader_parts) do
      row.leader[key].pos(
        leader_x + part.pos[1] * leader.scale[1] * scale,
        leader_y + part.pos[2] * leader.scale[2] * scale
      )
      row.leader[key].size(part.size[1] * leader.scale[1] * scale, part.size[2] * leader.scale[2] * scale)
    end

    place(row.cursor, x, y, layout.row.cursor.pos, layout.row.cursor.size)
    place_text(row.name, x, y, layout.row.name)
    place_text(row.zone, x, y, layout.row.zone)
    if row.job then
      place_text(row.job, x, y, layout.row.job)
      place_text(row.sub_job, x, y, layout.row.sub_job)
    end

    if row.range then
      local range = layout.row.range
      local range_x = x + range.pos[1] * scale
      local range_y = y + range.pos[2] * scale
      place(row.range.near, range_x, range_y, range.near.pos, range.near.size)
      place(row.range.far, range_x, range_y, range.far.pos, range.far.size)
      place_text(row.range.distance, range_x, range_y, range.distance)
    end

    local buffs = layout.row.buff_icons
    if buffs then
      -- The grid hangs from its bottom row, the one nearest the bars, so a
      -- short buff list sits against the bar instead of leaving a row of gap.
      local hang = #buffs.icons_by_row - (plan.buff_rows or #buffs.icons_by_row)
      local slot = 0
      for line, count in ipairs(buffs.icons_by_row) do
        for column = 1, count do
          slot = slot + 1
          local prim = row.buffs[slot]
          if prim then
            local offset = (buffs.offset_by_row[line] or 0) * (buffs.size[1] + buffs.spacing[1])
            local icon_left = offset + (column - 1) * (buffs.size[1] + buffs.spacing[1])
            local icon_top = (line - 1 + hang) * (buffs.size[2] + buffs.spacing[2])
            prim.pos(x + (buffs.pos[1] + icon_left) * scale, y + (buffs.pos[2] + icon_top) * scale)
            prim.size(buffs.size[1] * scale, buffs.size[2] * scale)
          end
        end
      end
    end
  end

  -- The background is three tiles: a fixed cap top and bottom with the middle
  -- stretched over the rows, so the frame keeps its caps at any height. Its
  -- width comes from the layout, which draws the main list's wider than the
  -- source art -- see the note there.
  local background = {
    top = image(layout.background.top.texture, layout.background.color),
    mid = image(layout.background.mid.texture, layout.background.color),
    bottom = image(layout.background.bottom.texture, layout.background.color),
  }

  -- Guarded because it runs every frame and the height only changes when the
  -- party does; six prim writes a frame for a list that has not moved is
  -- exactly the cost this component cannot afford.
  local placed_background = nil
  -- The last plan render() or apply_layout() computed. A move re-places from
  -- this rather than ticking for a fresh one: logic.tick() advances the bar
  -- ease and clears the forced flag, and draw_row writes a fill's width only
  -- on the tick that moved it -- so a move that ticked without drawing would
  -- swallow the tick that lands on the target and freeze the fill part-drawn.
  -- Everything a move needs from the plan is geometry, which only a new
  -- roster or a config change moves, and both of those go through a redraw.
  local last_plan = nil

  local function place_background(content_height, content_offset_y)
    if not pos then
      return
    end
    -- %f on the position, not %d: layout.clamp returns a fractional x at a
    -- non-integral scale, and a move is invalidated by this signature alone.
    local signature = ("%f:%f:%f:%d:%d"):format(pos.x, pos.y, scale, content_height, content_offset_y)
    local origin_x, origin_y = content_origin()
    if placed_background == signature then
      return
    end
    placed_background = signature
    local spec = layout.background
    local x = origin_x + spec.pos[1] * scale
    -- The frame wraps the rows, so it starts wherever they do.
    local y = origin_y + (spec.pos[2] + content_offset_y) * scale
    place(background.top, x, y, spec.top.pos, spec.top.size)
    background.mid.pos(x + spec.mid.pos[1] * scale, y + spec.mid.pos[2] * scale)
    background.mid.size(spec.mid.size[1] * scale, content_height * scale)
    -- size stretches, repeat_xy tiles. Windower's Lua side just forwards both
    -- to the closed core, so this pairing is copied from XIVParty's
    -- uiBackground rather than read from a source that explains it -- and it
    -- is what the art was drawn for.
    background.mid.repeat_xy(1, math.max(1, math.floor(content_height / spec.mid.size[2])))
    background.bottom.pos(x + spec.bottom.pos[1] * scale, y + (spec.mid.pos[2] + content_height) * scale)
    background.bottom.size(spec.bottom.size[1] * scale, spec.bottom.size[2] * scale)
  end

  --[[ Drawing ------------------------------------------------------------ ]]

  --[[ Nothing is written to a prim that already holds it. A full alliance is
       around 470 prims; a settled list that rewrote every value sixty times a
       second would be the one thing about this component that costs anything.
       `written` is the last value pushed, per prim, per property. ]]
  local function push(row, key, value, apply)
    if row.written[key] == value then
      return
    end
    row.written[key] = value
    apply(value)
  end

  local function push_text(row, prim, key, value)
    push(row, key .. ".text", value, prim.text)
  end

  local function push_color(row, prim, key, color)
    push(row, key .. ".color", color.r * 65536 + color.g * 256 + color.b, function()
      prim.color(color.r, color.g, color.b)
    end)
  end

  local function push_alpha(row, prim, key, alpha)
    push(row, key .. ".alpha", alpha, prim.alpha)
  end

  local function push_path(row, prim, key, path)
    push(row, key .. ".path", path, prim.path)
  end

  -- Shown only when the framework says the widget is visible *and* the element
  -- itself has something to say; `showing` remembers the latter across a
  -- hide/show so the list comes back the way it went away.
  local function want(row, prim, key, on)
    row.showing[key] = on
    row.by_key[key] = prim
    push(row, key .. ".visible", drawing() and on, function(wanted)
      if wanted then
        prim.show()
      else
        prim.hide()
      end
    end)
  end

  local function band_color(band)
    return layouts.bands[band] or layouts.bands.normal
  end

  local function draw_row(row, plan)
    for key, bar in pairs(row.bars) do
      local entry = plan.bars[key]
      -- The alliance layout takes its bars away for a member who is not in the
      -- zone; the main layout leaves an empty bar reading '?'.
      local drawn = plan.occupied and not (bar.spec.hide_outside_zone and plan.outside_zone)
      want(row, bar.bg, "bar_bg_" .. key, drawn)
      want(row, bar.fg, "bar_fg_" .. key, drawn)
      want(row, bar.fill, "bar_fill_" .. key, drawn and not entry.hidden)
      if entry.dirty then
        bar.fill.size(entry.width * scale, bar.spec.fill.size[2] * scale)
      end
      push_alpha(row, bar.fill, "bar_fill_" .. key, entry.alpha)
      if bar.value then
        push_text(row, bar.value, "bar_value_" .. key, entry.text)
        push_color(row, bar.value, "bar_value_" .. key, band_color(entry.band))
        want(row, bar.value, "bar_value_" .. key, drawn)
      end
    end

    local has_icon = plan.occupied and plan.job_icon ~= nil
    if has_icon then
      -- The icon files are lowercase; res.jobs reports the job uppercase.
      local path = ctx.asset(layout.row.job_icon.path .. plan.job_icon:lower() .. ".png")
      push_path(row, row.job_icon.icon, "job_icon", path)
      push_color(row, row.job_icon.bg, "job_bg", layout.row.job_icon.colors[plan.role] or layout.row.job_icon.colors.dd)
    end
    want(row, row.job_icon.bg, "job_bg", has_icon)
    want(row, row.job_icon.gradient, "job_gradient", has_icon)
    want(row, row.job_icon.icon, "job_icon", has_icon)
    want(row, row.job_icon.frame, "job_frame", has_icon)
    want(row, row.job_icon.highlight, "job_highlight", has_icon and plan.cursor == 1)

    want(row, row.leader.party, "leader_party", plan.occupied and plan.leader.party)
    want(row, row.leader.alliance, "leader_alliance", plan.occupied and plan.leader.alliance)
    want(row, row.leader.quartermaster, "leader_qm", plan.occupied and plan.leader.quartermaster)

    -- XIVParty fades the cursor to half for a subtarget rather than swapping
    -- the texture, so the same prim covers both.
    push_alpha(row, row.cursor, "cursor", math.floor(255 * (plan.cursor or 0)))
    want(row, row.cursor, "cursor", plan.occupied and (plan.cursor or 0) > 0)

    push_text(row, row.name, "name", plan.occupied and plan.name or "")
    want(row, row.name, "name", plan.occupied)
    push_text(row, row.zone, "zone", plan.zone_text or "")
    want(row, row.zone, "zone", plan.occupied and plan.zone_text ~= "")

    if row.job then
      push_text(row, row.job, "job", plan.job_text or "")
      want(row, row.job, "job", plan.occupied and (plan.job_text or "") ~= "")
      push_text(row, row.sub_job, "sub_job", plan.sub_job_text or "")
      want(row, row.sub_job, "sub_job", plan.occupied and (plan.sub_job_text or "") ~= "")
    end

    if row.range then
      local range = plan.range or {}
      want(row, row.range.near, "range_near", plan.occupied and range.near == true)
      want(row, row.range.far, "range_far", plan.occupied and range.far == true)
      push_text(row, row.range.distance, "range_text", range.text or "")
      want(row, row.range.distance, "range_text", plan.occupied and (range.text or "") ~= "")
    end

    for index, prim in ipairs(row.buffs) do
      local id = plan.occupied and (plan.buffs or {})[index] or nil
      if id then
        push_path(row, prim, "buff_" .. index, ctx.asset(layout.row.buff_icons.path .. id .. ".png"))
      end
      want(row, prim, "buff_" .. index, id ~= nil)
    end
  end

  -- Re-evaluates every element's visibility against the new widget state.
  -- `want` already folds the two together, so this is one pass over what each
  -- row last asked for -- and the cache means an unchanged prim is not touched.
  local background_shown = nil

  local function apply_visibility()
    for _, row in pairs(rows) do
      for key, prim in pairs(row.by_key) do
        want(row, prim, key, row.showing[key])
      end
    end

    local wanted = drawing()
    if background_shown == wanted then
      return
    end
    background_shown = wanted
    for _, prim in pairs(background) do
      if wanted then
        prim.show()
      else
        prim.hide()
      end
    end
  end

  local function apply_box(plan)
    box.width = plan.margin.left + plan.width + plan.margin.right
    box.height = plan.margin.top + plan.box_height + plan.margin.bottom
  end

  local function render()
    if not attached or not pos then
      return
    end

    --[[ Read every frame; lib/player owns the interval, so this costs a real
         client read only once per interval however many lists ask.

         NOT for the row's vitals: those come from get_party() with the change
         events laid over them by `set_own_vital`, and between reads this hands
         back the identical cached table. What per-frame buys is the KEYED
         invalidation - a `gain buff` refreshes the player without moving the
         counter, so the player's own buff icons land on the next frame rather
         than at the next rebuild. ]]
    logic.set_main_player(ctx.get_player and ctx.get_player() or nil)

    --[[ The roster is only rebuilt when the service actually read, because
         set_roster drops the 0x0DD / 0x0DF pushes this list is holding -- doing
         that sixty times a second would throw away the very packets the pushes
         exist to deliver. The service's own counter is the gate rather than a
         clock here: a second throttle would sit out of phase with it and put
         this list up to two intervals behind.

         An absent counter falls back to rebuilding every frame. That is a
         DEGRADED list, not merely a costly one: rebuilding drops the packet
         pushes, so the 0x0DD / 0x0DF overlay never survives to be drawn and the
         rows fall back to what the poll alone says. It is still the better of
         the two failures - a wiring slip must not leave the list frozen on a
         dead roster, which is what Lua's nil-tolerance would otherwise buy -
         and it is unreachable in a client, where the entry point always wires
         the counter. ]]
    local generation = ctx.generation and ctx.generation() or nil
    if generation == nil or generation ~= last_generation then
      last_generation = generation
      local info = ctx.get_info and ctx.get_info() or nil
      logic.set_zone(info and info.zone or nil)
      logic.set_roster(ctx.get_party and ctx.get_party() or nil)
    end

    -- Read every frame: the cursor follows the target key, so it cannot wait
    -- for the next read. Up to four client lookups a frame across ALL THREE
    -- lists, not four per list - lib/player memoizes them for the frame, and
    -- the three ask for the same four.
    local target = ctx.get_mob_by_target and ctx.get_mob_by_target("t") or nil
    local subtarget = ctx.get_mob_by_target
        and (ctx.get_mob_by_target("st") or ctx.get_mob_by_target("stpt") or ctx.get_mob_by_target("stal"))
      or nil
    logic.set_target(target and target.id or nil, subtarget and subtarget.id or nil)

    local plan = logic.tick()
    last_plan = plan
    apply_box(plan)

    if plan.hidden ~= suppressed then
      suppressed = plan.hidden
      apply_visibility()
    end

    for slot, row_plan in ipairs(plan.rows) do
      if row_plan.occupied and not rows[slot] then
        rows[slot] = new_row()
      end

      local row = rows[slot]
      if row then
        if not row_plan.occupied then
          -- Nothing is drawn for an empty row, so there is nothing to wait
          -- for; keeping the prims would mean a party that churns only grows.
          dispose_row(slot)
        else
          -- align_bottom moves every row when the party grows, so a row's
          -- offsets are not fixed for the life of the row.
          local origin_x, origin_y = content_origin()
          local x = origin_x + row_plan.offset_x * scale
          local y = origin_y + row_plan.offset_y * scale
          -- The icon grid hangs from its bottom row, so its offsets move when
          -- the buff count crosses a row boundary.
          if row.placed.x ~= x or row.placed.y ~= y or row.placed.buff_rows ~= row_plan.buff_rows then
            place_row(row, row_plan)
          end
          draw_row(row, row_plan)
        end
      end
    end

    place_background(plan.content_height, plan.content_offset_y)
  end

  --[[ A move changes only where the rows sit: every value draw_row writes --
       text, colour, alpha, path, visibility, fill width -- is independent of
       the widget's origin. So the rows are re-placed from the last plan,
       without being redrawn and without the write cache being cleared.

       This is the drag path: layout mode runs core.apply on every raw
       mouse-move event, and a full rebuild there costs three figures of prim
       calls per event. Callers must have a plan already -- see set_pos. ]]
  local function reposition()
    apply_box(last_plan)
    for slot, row in pairs(rows) do
      place_row(row, last_plan.rows[slot])
    end
    place_background(last_plan.content_height, last_plan.content_offset_y)
  end

  --[[ Pushes the frame geometry to every prim, and redraws them. Called when
       the scale or a metric changes -- a move goes through reposition above,
       which is the cheaper half of this.

       It has to draw as well as place. The bar fill's *width* is the one thing
       place_row does not write -- render() owns it, because it is the eased
       value -- so a scale change that only re-placed would leave every fill at
       the old scale until that member's HP happened to move. Clearing the
       write cache first is what makes the redraw actually reach the prims. ]]
  local function apply_layout()
    logic.invalidate()
    placed_background = nil
    if not pos then
      return
    end
    local plan = logic.tick()
    last_plan = plan
    apply_box(plan)
    for slot, row in pairs(rows) do
      row.written = {}
      place_row(row, plan.rows[slot])
      draw_row(row, plan.rows[slot])
    end
    place_background(plan.content_height, plan.content_offset_y)
  end

  --[[ Packets ------------------------------------------------------------ ]]

  --[[ `parsed` is the entry point's `packets.parse` result, handed in rather
       than fetched: all three lists see every chunk, and parsing the same
       packet three times to reach the same table is work done to be thrown
       away twice. One component now, but still three state machines reading
       it. 0x076 is decoded from the raw bytes instead: Windower does
       define it, but as an opaque data[8] bit mask plus a data[32] blob, so
       the bit arithmetic is ours either way. ]]
  local function handle_chunk(id, original, parsed)
    if id == packet_parsers.PARTY_BUFFS then
      -- Skipped outright on the alliance lists: their layout has no buff icons
      -- to draw, so decoding 48 bytes five times would be for nothing.
      if layout.row.buff_icons then
        for player_id, buffs in pairs(packet_parsers.party_buffs(original)) do
          logic.apply_buffs(player_id, buffs)
        end
      end
      return
    end

    if not PARSED_PACKETS[id] or not parsed then
      return
    end

    if id == packet_parsers.ALLIANCE then
      logic.apply_alliance_flags(packet_parsers.alliance_flags(parsed))
      return
    end

    local update
    if id == packet_parsers.PARTY_MEMBER then
      update = packet_parsers.member_update(parsed)
    else
      update = packet_parsers.char_update(parsed)
    end
    if not update then
      return
    end
    logic.apply_vitals(update.id, update.vitals)
    if update.name then
      logic.apply_member_identity(update.id, update.name)
    end
    if update.job then
      logic.apply_job(update.id, update.job)
    end
  end

  --[[ The contract, in the singular ------------------------------------- ]]

  function self.attach(loaded_config)
    config = loaded_config
    attached = true
    -- Forget the last read: a relog inside one interval would otherwise keep
    -- the previous character's roster until the service next reads.
    last_generation = nil
    logic.set_config(config)
    apply_layout()
  end

  function self.detach()
    attached = false
    self.hide()
  end

  --[[ Core pushes all three of these on every core.apply, and layout mode runs
       one per raw mouse-move event -- so two of the three carry a value the
       widget already holds. An unchanged setter must cost nothing. ]]
  function self.set_pos(x, y)
    if pos and pos.x == x and pos.y == y then
      return
    end
    -- The first placement is a full layout: reposition assumes the rows
    -- already hold every value but their origin, and before this they hold
    -- nothing at all.
    local placed = pos ~= nil and last_plan ~= nil
    pos = { x = x, y = y }
    if placed then
      reposition()
    else
      apply_layout()
      -- Being placed is one of the reasons drawing() weighs, so the first
      -- placement has to re-ask it. Core happens to follow every placement
      -- with show(), but a widget that draws only because its caller calls
      -- the right thing next is exactly the silent failure to avoid.
      apply_visibility()
    end
  end

  function self.set_scale(new_scale)
    if scale == new_scale then
      return
    end
    scale = new_scale
    apply_layout()
  end

  -- Core reads get_bounds straight after this, to clamp and to size the
  -- layout-mode highlight, and both reads land before the next render. So the
  -- box has to be right now, not a frame later.
  function self.set_preview(on)
    on = on == true
    if preview == on then
      return
    end
    preview = on
    logic.set_preview(on)
    apply_box(logic.tick())
    apply_visibility()
    if pos then
      apply_layout()
    end
  end

  function self.show()
    visible = true
    apply_visibility()
  end

  function self.hide()
    visible = false
    apply_visibility()
  end

  -- The origin set_pos was given, exactly: core clamps the widget on screen by
  -- comparing the two, and layout mode's drag offsets assume it.
  function self.get_bounds()
    if not pos then
      return nil
    end
    return pos.x, pos.y, box.width * scale, box.height * scale
  end

  -- No arguments is the per-frame tick; `chunk` is a packet the entry point
  -- forwarded; anything else is a game event, of which only the vital changes
  -- mean something here.
  function self.update(event, ...)
    if event == nil then
      render()
    elseif event == "chunk" then
      handle_chunk(...)
    else
      -- The vital change events. Yours is the one row no party packet covers.
      logic.set_own_vital(event, ...)
    end
  end

  -- The verbs logic.lua parses, for this list alone. The outer widget picks
  -- which list a `//hud partylist ...` line addresses.
  function self.command(args)
    local lines, changed = logic.command(args)
    if changed then
      apply_layout()
    end
    return lines, changed
  end

  function self.destroy()
    background.top.destroy()
    background.mid.destroy()
    background.bottom.destroy()
    for slot in pairs(rows) do
      dispose_row(slot)
    end
  end

  return self
end

--[[ The component: three lists under one name, one config file and one
     `visible` flag, addressed through the anchor names below. ]]

-- Main first. This is the order `//hud list` prints and, reversed, layout
-- mode's hit-test priority, so a later anchor wins where two overlap.
local ANCHORS = { "main", "alliance1", "alliance2" }

--[[ Verbs the main party alone can answer, refused out loud at an alliance
     list rather than quietly applied to main or quietly stored where nothing
     will read them. Two reasons, both structural: 0x076 carries the main party
     alone and an alliance row draws no buff icons, and the alliance row layout
     has no range block at all - `range` was accepted and inert there before
     this, back to when the lists were three components. ]]
local MAIN_ONLY = { hidesolo = true, buff = true, range = true }

local function new(ctx)
  local self = { name = ctx.name or "partylist", alias = "pl" }

  local screen_width, screen_height = (ctx.screen or function() end)()
  self.defaults = build_defaults(screen_width, screen_height)

  local save = nil
  local lists = {}
  for _, anchor in ipairs(ANCHORS) do
    lists[anchor] = new_list(ctx, anchor, self.defaults.lists[anchor])
  end

  local function each(method, ...)
    for _, anchor in ipairs(ANCHORS) do
      lists[anchor][method](...)
    end
  end

  function self.anchors()
    return ANCHORS
  end

  --[[ Core fans a placement out over every anchor on every apply, and layout
       mode drags one of them -- so a name that is not ours has to cost
       nothing rather than crash the apply. Crossbar's guard, for the same
       reason. ]]
  local function list_at(anchor)
    return anchor ~= nil and lists[anchor] or nil
  end

  --[[ A config file is code and is hand-editable, and `//hud copy` imports
       another character's, so a list entry can be any shape at all by the time
       it reaches here - and lib/settings' merge leaves a non-table where it
       found one, since it only recurses where both sides are tables. This
       attach runs inside core's login path under the guard-wrapped prerender,
       where five errors disable the render loop, so anything unusable is
       replaced with a FRESH copy of the defaults rather than indexed.

       Fresh, and written back into the config, deliberately: handing a list
       `self.defaults` would have every later command write into the defaults
       table, which `save()` does not serialise - a change the user was told
       had been made and that no file ever carried. ]]
  function self.attach(loaded_config, persist)
    save = persist
    local config = type(loaded_config) == "table" and loaded_config or {}
    if type(config.lists) ~= "table" then
      config.lists = {}
    end
    local seed = nil
    for _, anchor in ipairs(ANCHORS) do
      if type(config.lists[anchor]) ~= "table" then
        -- Built at most once per attach, however many entries are unusable.
        seed = seed or build_defaults(screen_width, screen_height)
        config.lists[anchor] = seed.lists[anchor]
      end
      lists[anchor].attach(config.lists[anchor])
    end
  end

  -- The config tables and the saver belong to the character being detached;
  -- core does not route a command to a detached component, but holding its
  -- writer afterwards is a defence worth keeping.
  function self.detach()
    save = nil
    each("detach")
  end

  function self.set_pos(x, y, anchor)
    local list = list_at(anchor)
    if list then
      list.set_pos(x, y)
    end
  end

  function self.set_scale(scale, anchor)
    local list = list_at(anchor)
    if list then
      list.set_scale(scale)
    end
  end

  function self.set_preview(on)
    each("set_preview", on)
  end

  --[[ Core sends the widget's own switch with no anchor and one list's with
       its name; a whole-widget show is also what layout mode force-shows with,
       so it has to bring back every list a per-anchor hide took down. An
       anchor that is not ours costs nothing, as everywhere else here. ]]
  function self.show(anchor)
    if anchor ~= nil then
      local list = list_at(anchor)
      if list then
        list.show()
      end
      return
    end
    each("show")
  end

  function self.hide(anchor)
    if anchor ~= nil then
      local list = list_at(anchor)
      if list then
        list.hide()
      end
      return
    end
    each("hide")
  end

  function self.get_bounds(anchor)
    local list = list_at(anchor)
    if not list then
      return nil
    end
    return list.get_bounds()
  end

  function self.update(event, ...)
    each("update", event, ...)
  end

  function self.destroy()
    each("destroy")
  end

  --[[ `//hud partylist [<list>] <verb> ...`, the list word leading so the verb
       grammar behind it is untouched. Absent, the main party is addressed -
       which is what every line that worked before this component was merged
       still means. ]]
  -- What `//hud partylist <list>` reports: the list's own settings. Whether it
  -- is on screen at all is the framework's answer now, and `//hud list` prints
  -- it per anchor.
  local function status_of(anchor)
    -- Parenthesised: `command` answers (lines, changed), and a report has no
    -- second value to hand its caller.
    return (lists[anchor].command({}))
  end

  local function status_all()
    local lines = {}
    for _, anchor in ipairs(ANCHORS) do
      for _, line in ipairs(status_of(anchor)) do
        lines[#lines + 1] = line
      end
    end
    return lines
  end

  function self.handle_command(args)
    args = args or {}
    local first = args[1] and args[1]:lower() or nil
    if not first then
      return status_all()
    end

    -- The list word, if the first one is a list at all.
    local anchor = lists[first] and first or nil
    local rest = args
    if anchor then
      rest = {}
      for index = 2, #args do
        rest[index - 1] = args[index]
      end
    end

    local verb = rest[1] and rest[1]:lower() or nil
    if verb == nil then
      return status_of(anchor or "main")
    end
    --[[ The per-list switch moved to the framework on 2026-08-31, and it
         answered here the day before - so it is pointed at its replacement by
         name rather than left to the generic verb hint, which cannot mention
         a `//hud` verb this component knows nothing about. ]]
    if verb == "on" or verb == "off" then
      return {
        ("//hud partylist %s is the framework's now:"):format(verb),
        ("  //hud %s partylist %s"):format(verb == "on" and "show" or "hide", anchor or "main"),
      }
    end

    -- Kept loud rather than silently applied to main: the asymmetry is real,
    -- and a command that appears to work on the wrong list is worse than one
    -- that refuses.
    if anchor and anchor ~= "main" and MAIN_ONLY[verb] then
      return { ("%s is the main party only, so //hud partylist %s takes it, not %s"):format(verb, verb, anchor) }
    end

    local lines, changed = lists[anchor or "main"].command(rest)
    if changed and save then
      save()
    end
    return lines
  end

  return self
end

return new
