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

--[[ The crossbar's geometry over the shared slot render
     (lib/actionbar/render): the two crosses, the hold-state plan, the set
     label and the sword, and the six anchors' footprints. Everything a slot
     draws regardless of where it sits - its label, cost, sweep, chain
     border, flash and icon - is the shared module's, re-exported here so
     crossbar.lua reads one instance. Nothing here touches a prim or a
     Windower global; crossbar.lua turns what this module answers into prim
     calls. The drawing constants are xivcrossbar's compact metrics taken
     verbatim (decided: port its drawing, don't re-derive) - what is ours is
     the slot map (face cluster right, dpad left, both clockwise from the
     top), the framework anchors in place of upstream's screen-bottom anchor,
     and the radial sweep in place of upstream's rectangular wipe.

     Frames of reference: every position this module answers is unscaled and
     relative to the owning anchor's origin - the top-left of the anchor's
     panel footprint, which is also what bounds() describes, so core's clamp
     (get_bounds must return the origin set_pos was given) holds by
     construction. The widget applies origin + uniform scale. ]]

local new_shared = require("lib/actionbar/render")

-- Upstream's bar background art: 330x220 full size, 330x180 compact, drawn
-- 30 left of and 35 above a side's first slot (ui.lua: pos = get_slot_x(h,1)
-- - 30, get_slot_y(h,4) - 35). The panel rect IS the anchor footprint here,
-- so those overhangs become the grid's padding inside it. The 40px slot
-- itself is the shared render's.
local PAD_X, PAD_Y = 30, 35
-- The band of panel art under the slot grid: at the art's native 330x180
-- and the default pitches, 180 - 35 pad - two 28px rows - a 40px slot.
local PANEL_BOTTOM = 49
-- The set label's own line height, for centring it in that bottom band.
-- parambar's size, which is what the indicator was asked to match.
local SET_LABEL_HEIGHT = 14
-- The sword that marks the drawn weapon state. It used to stack directly
-- above the label - 24 and a 2px gap fitting the pair inside the bottom
-- slot row's own 40px band - but the two are separate anchors now, so it
-- is placed on its own: its foot 8px clear of the MIDDLE row's top edge,
-- the row slots 2 and 8 occupy (Kevin, 2026-08-29). Flush against that
-- edge read as touching, so the clearance is its own constant and is
-- measured from the row rather than from the screen - the defaults are
-- computed per resolution, and a fixed pixel would only be right at one.
-- That lifts the sword clear of the label entirely, and the centre column
-- it sits in has no slot in it - which is what leaves room for it to be
-- half again the 24 it was drawn at while it shared the label's band.
local SET_ICON = 36
local SET_ICON_CLEARANCE = 8
-- Upstream h2's base sits 300 right of h1's, and its Expanded bars at +150 -
-- reproduced exactly by centring one side panel across the main footprint.
-- The centring offset is SIDE_GAP / 2 whatever the side width, because the
-- main footprint is exactly one side wider than the gap.
local SIDE_GAP = 300
local EXPANDED_OFFSET = SIDE_GAP / 2

--[[ Our slot map to upstream's grid: side-local columns 1..6 on the 40+spacing
     pitch, rows counted down from the panel top on the halved (compact) bar
     spacing. The dpad cluster (slots 5-8) is the left cross around column 2,
     the face cluster (1-4) the right cross around column 5; both clockwise
     from the top. ]]
local SLOT_GRID = {
  [1] = { column = 5, row = 1 }, -- Y: face top
  [2] = { column = 6, row = 2 }, -- B: face right
  [3] = { column = 5, row = 3 }, -- A: face bottom
  [4] = { column = 4, row = 2 }, -- X: face left
  [5] = { column = 2, row = 1 }, -- Up: dpad top
  [6] = { column = 3, row = 2 }, -- R: dpad right
  [7] = { column = 2, row = 3 }, -- Dn: dpad bottom
  [8] = { column = 1, row = 2 }, -- L: dpad left
}

-- Side x offset within the owning anchor, per bar. The WXHB's halves own
-- their anchors outright, so both sides sit at the origin; Expanded draws
-- centred on main ((630 - 330) / 2 = 150, upstream's own +150).
local BAR_OFFSETS = {
  xhb = { left = 0, right = SIDE_GAP },
  wxhb = { left = 0, right = 0 },
  expanded = { left = EXPANDED_OFFSET, right = EXPANDED_OFFSET },
}

local function new(deps)
  local config = deps.config
  local shared = new_shared({ config = config, icon_for = deps.icon_for })
  local SLOT = shared.slot_size()
  local self = {}

  -- The shared slot render's surface, one instance per bar: the sweep
  -- maxima and the chain animation are state, so the crossbar must read
  -- them off the same object its widget resolves icons and hit-tests with.
  self.slot_size = shared.slot_size
  self.slot_label = shared.slot_label
  self.clear_sweep = shared.clear_sweep
  self.sweep = shared.sweep
  self.chain_tick = shared.chain_tick
  self.text_offsets = shared.text_offsets
  self.cost = shared.cost
  self.slot_alpha = shared.slot_alpha
  self.feedback_fade = shared.feedback_fade
  self.icon_candidates = shared.icon_candidates
  self.remaining_for = shared.remaining_for
  self.recast_label = shared.recast_label

  -- Reads the config fresh on every call rather than caching at construction,
  -- and never writes it - upstream's setup_metrics mutated its settings table
  -- (defect 2), which this shape makes impossible.
  --[[ The set indicator: FFXIV's "Set N", centred across the bar along the
       bottom, in the band of panel art under the slot grid where nothing
       else draws.

       Centred by RESERVING a width rather than by measuring one: a prim
       cannot report its rendered width, and `right_justified` is the only
       alignment the texts library has. The reservation is honest because
       the string never changes length - there are eight sets, so it is
       always "Set " and one digit - which also means the label cannot
       twitch sideways as the set changes. ]]
  local SET_LABEL_GLYPH = 7
  local SET_LABEL_CHARS = 5

  --- The label for a set number, FFXIV's own wording.
  function self.set_label(set)
    return "Set " .. tostring(set)
  end

  --- The width reserved for it, at the drawing scale of 1.
  function self.set_label_width()
    return SET_LABEL_GLYPH * SET_LABEL_CHARS
  end

  --- The sword's edge length, square, at the drawing scale of 1.
  function self.set_icon_size()
    return SET_ICON
  end

  --[[ Where the sword and the label sit, unscaled and relative to the main
       anchor's origin. Each is centred across the bar on its own, one above
       the other, so the sword coming and going never moves the label.

       These are the DEFAULT placements only. Both became anchors of their
       own on 2026-08-29 (Kevin), so once a config exists the player's own
       positions decide - defaults.lua is the one caller left, seeding those
       positions from this geometry so a fresh install draws where it always
       did.

       The vertical placement is the constraint that matters. The two
       clusters flank the bar's centre, and in the MIDDLE row they occupy it
       (a slot ends at the centre-left, another starts at the centre-right),
       so anything drawn there lands on top of the art. The top and bottom
       rows leave that column clear. So the label's foot is aligned with the
       BOTTOM ROW's foot, which puts the pair in that row's own band and
       clear of every slot. ]]
  local function set_row_bottom(metrics)
    return metrics.pad_y + 2 * metrics.row_pitch + metrics.slot
  end

  local function set_centre(metrics)
    return (metrics.side_gap + metrics.panel_width) / 2
  end

  --- The label's top-left; its foot lines up with the bottom slot row's.
  function self.set_label_pos()
    local metrics = self.metrics()
    return set_centre(metrics) - self.set_label_width() / 2, set_row_bottom(metrics) - SET_LABEL_HEIGHT
  end

  --- The sword's top-left: centred across the bar, its bottom edge 8px
  --- clear of the middle slot row's top edge (the row slots 2 and 8 sit in).
  function self.set_icon_pos()
    local metrics = self.metrics()
    local foot = metrics.pad_y + metrics.row_pitch - SET_ICON_CLEARANCE
    return set_centre(metrics) - SET_ICON / 2, foot - SET_ICON
  end

  function self.metrics()
    local column_pitch = SLOT + config.slot_spacing
    -- Compact halves the bar spacing at render time, exactly as upstream.
    local row_pitch = config.bar_spacing / 2
    return {
      slot = SLOT,
      column_pitch = column_pitch,
      row_pitch = row_pitch,
      pad_x = PAD_X,
      pad_y = PAD_Y,
      -- The panel and footprint derive from the pitches (the spacing keys
      -- are not clamped, like partylist's): at the defaults this is the
      -- art's native 330x180, and a hand-edited grid keeps its slots
      -- inside get_bounds so core's clamp keeps holding.
      panel_width = PAD_X * 2 + 5 * column_pitch + SLOT,
      panel_height = PAD_Y + 2 * row_pitch + SLOT + PANEL_BOTTOM,
      side_gap = SIDE_GAP,
    }
  end

  -- Top-left of a slot, unscaled, relative to the owning anchor's origin.
  -- `metrics` is optional: a caller placing all forty slots at once passes
  -- the one table in rather than have this build forty identical ones.
  function self.slot_pos(bar, side, slot, metrics)
    local offsets = BAR_OFFSETS[bar]
    local grid = SLOT_GRID[slot]
    if offsets == nil or offsets[side] == nil or grid == nil then
      return nil
    end
    metrics = metrics or self.metrics()
    local x = PAD_X + offsets[side] + (grid.column - 1) * metrics.column_pitch
    local y = PAD_Y + (grid.row - 1) * metrics.row_pitch
    return x, y
  end

  -- The active-side panel rect (upstream's bar_bg_compact.png, repositioned
  -- onto whichever bar is active), relative to the owning anchor's origin.
  function self.panel_pos(bar, side)
    local offsets = BAR_OFFSETS[bar]
    if offsets == nil or offsets[side] == nil then
      return nil
    end
    local metrics = self.metrics()
    return { x = offsets[side], y = 0, width = metrics.panel_width, height = metrics.panel_height }
  end

  local function footprint_of(anchor)
    local metrics = self.metrics()
    if anchor == "main" then
      return { width = SIDE_GAP + metrics.panel_width, height = metrics.panel_height }
    elseif anchor == "wxhb_left" or anchor == "wxhb_right" then
      return { width = metrics.panel_width, height = metrics.panel_height }
    elseif anchor == "set" then
      -- The reserved width, not the current text's: the box must not
      -- breathe as the set number changes under the player's cursor.
      return { width = self.set_label_width(), height = SET_LABEL_HEIGHT }
    elseif anchor == "weapon" then
      return { width = SET_ICON, height = SET_ICON }
    end
    return nil
  end

  --[[ Where every slot currently on screen is, in SCREEN coordinates. The
       caller passes the groups it is actually drawing - each with the
       anchor placement it is drawn at - and gets one rect per slot back,
       in the order the groups were given.

       `bar` and `render_side` say where the slot is DRAWN; `set` and `side`
       say what it addresses, which for a WXHB or Expanded view is its
       config's half and not the group's. Both ride along on the rect, so a
       caller never has to re-derive either.

       This is the ONE slot hit-test: the mouse binder resolves its drops
       and drags with it and the widget answers live clicks with it. The
       reference addon had two, which is how they came to disagree. ]]
  function self.slot_rects(groups)
    local rects = {}
    local size = self.metrics().slot
    for _, group in ipairs(groups or {}) do
      for slot = 1, #SLOT_GRID do
        local x, y = self.slot_pos(group.bar, group.render_side or group.side, slot)
        if x ~= nil then
          rects[#rects + 1] = {
            x = group.x + x * group.scale,
            y = group.y + y * group.scale,
            width = size * group.scale,
            height = size * group.scale,
            key = group.key,
            set = group.set,
            side = group.side,
            slot = slot,
          }
        end
      end
    end
    return rects
  end

  -- The slot under a point, over this bar's own rects: the shared render's
  -- one hit-test, fed the geometry it cannot know.
  function self.slot_at(groups, x, y, accept)
    if type(x) ~= "number" or type(y) ~= "number" then
      return nil
    end
    return shared.slot_at(self.slot_rects(groups), x, y, accept)
  end

  --[[ The persistent-bar state table (the component is never hold-to-show:
       the held keys choose which part is ACTIVE, not whether anything is
       drawn). `state` is the input machine's activate state; `opts.hidden`
       covers both framework hide() and suppression - no side is active while
       the component is suppressed or hidden. ]]
  function self.visible(state, opts)
    opts = opts or {}
    local plan = { xhb = false, wxhb_left = false, wxhb_right = false }
    if opts.hidden then
      return plan
    end
    if state == "expanded_lr" or state == "expanded_rl" then
      -- Expanded Hold is the one bar that replaces rather than coexists,
      -- drawn centred on the main anchor where the XHB it replaced was.
      plan.expanded = state
      plan.panel = { bar = "expanded", side = state == "expanded_rl" and "right" or "left" }
      return plan
    end
    plan.xhb = true
    -- Booleans only, and only `true` counts: a hand-edited truthy
    -- (always_show_wxhb = 1) degrades to the shipped default (off), the
    -- component's posture for config garbage - leaking the raw value would
    -- hide the bar downstream while its panel still drew.
    local always = config.always_show_wxhb == true
    plan.wxhb_left = always or state == "wxhb_left"
    plan.wxhb_right = always or state == "wxhb_right"
    if state == "xhb_left" or state == "xhb_right" then
      plan.panel = { bar = "xhb", side = state:sub(5) }
    elseif state == "wxhb_left" or state == "wxhb_right" then
      plan.panel = { bar = "wxhb", side = state:sub(6) }
    end
    return plan
  end

  -- The anchor's unscaled-times-scale footprint. main answers the whole XHB
  -- whatever is currently drawn in it - Expanded replaces the XHB centred on
  -- this same box, and narrowing to the eight-slot box would let an
  -- apply_all() during a hold clamp against the transient and shift the
  -- anchor.
  function self.bounds(anchor, scale)
    local footprint = footprint_of(anchor)
    if footprint == nil then
      return nil
    end
    scale = scale or 1
    return footprint.width * scale, footprint.height * scale
  end

  return self
end

return new
