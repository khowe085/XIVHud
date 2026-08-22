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

The radial recast sweep in this file (the observed-maximum denominator and
the frame formula) is transcribed from XIVhotbar2 Petit Trois Edition's
lib/ui.lua, whose notice BSD clause 1 requires retained in derived source:

BSD 3-Clause License

Copyright (c) 2026, WG Incorporated

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ Pure geometry and per-frame draw state: nothing here touches a prim or a
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

local kebab = require("components/crossbar/kebab")

-- Upstream's fixed 40px slot and its bar background art: 330x220 full size,
-- 330x180 compact, drawn 30 left of and 35 above a side's first slot
-- (ui.lua: pos = get_slot_x(h,1) - 30, get_slot_y(h,4) - 35). The panel
-- rect IS the anchor footprint here, so those overhangs become the grid's
-- padding inside it.
local SLOT = 40
local PAD_X, PAD_Y = 30, 35
-- The shipped cost colours: the fallback when the config's are hand-broken
-- (merge_defaults lets a user scalar beat a table default, and cost() feeds
-- the per-frame path).
local MP_COST_COLOR = { r = 230, g = 91, b = 151 }
local TP_COST_COLOR = { r = 254, g = 222, b = 0 }
-- The band of panel art under the slot grid: at the art's native 330x180
-- and the default pitches, 180 - 35 pad - two 28px rows - a 40px slot.
local PANEL_BOTTOM = 49
-- The set label's own line height, for centring it in that bottom band.
-- parambar's size, which is what the indicator was asked to match.
local SET_LABEL_HEIGHT = 14
-- The sword that marks the drawn weapon state, stacked ABOVE the label.
-- 24 and a 2px gap put the pair exactly inside the bottom slot row's own
-- band (24 + 2 + 14 = the 40px slot), which is what keeps it clear of the
-- art it sits between.
local SET_ICON = 24
local SET_ICON_GAP = 2
-- Upstream h2's base sits 300 right of h1's, and its Expanded bars at +150 -
-- reproduced exactly by centring one side panel across the main footprint.
-- The centring offset is SIDE_GAP / 2 whatever the side width, because the
-- main footprint is exactly one side wider than the gap.
local SIDE_GAP = 300
local EXPANDED_OFFSET = SIDE_GAP / 2
-- The skillchain bg at its widest displayed state (open: base_width+4 x 14).
-- The indicator itself lands at CB6; layout mode needs its box now.
local INDICATOR_WIDTH, INDICATOR_HEIGHT = 604, 14

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
  local self = {}

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

  --- The sword's top-left, stacked directly above the label.
  function self.set_icon_pos()
    local metrics = self.metrics()
    local _, label_y = self.set_label_pos()
    return set_centre(metrics) - SET_ICON / 2, label_y - SET_ICON_GAP - SET_ICON
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
    elseif anchor == "indicator" then
      return { width = INDICATOR_WIDTH, height = INDICATOR_HEIGHT }
    end
    return nil
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

  --[[ The radial recast sweep (Petit Trois' algorithm - see the header
       notice): 32 pre-rendered frames of an arc, indexed by the remaining
       fraction of the LARGEST recast value yet seen for the slot. The
       denominator is observed, not looked up, so the fraction cannot exceed
       1 by construction (upstream defect 7 cannot recur) and a bar that
       loads mid-cooldown starts full rather than dividing by a guess. ]]
  local cooldown_maxima = {}

  -- Forgets a slot's observed maximum. The maxima key by prim slot, so
  -- they would otherwise outlive the slot's ACTION - a set switch, job
  -- change or context flip putting a fresh 30s recast where a 300s one sat
  -- would draw it nearly done under the stale denominator. The caller says
  -- when content changed; the sweep cannot know.
  function self.clear_sweep(key)
    cooldown_maxima[key] = nil
  end

  -- Answers the frame to draw (1..32), or nil when the overlay hides; a
  -- remaining of zero (or none) ends the sweep and forgets the maximum.
  function self.sweep(key, remaining)
    if remaining == nil or remaining <= 0 then
      cooldown_maxima[key] = nil
      return nil
    end
    local maximum = cooldown_maxima[key]
    if maximum == nil or remaining > maximum then
      maximum = remaining
      cooldown_maxima[key] = maximum
    end
    local fraction = remaining / maximum
    return math.max(1, math.floor(fraction * 32 + 0.5))
  end

  --[[ The chain-result border animation (the fork's frame counter,
       ui.lua:1017/1368-1383): one advance per CALL, wrapping at 40, five
       calls per frame_step - so steps 1..8 over 40 calls. Deviation from
       the fork, which advances its counter every render pass unconditionally:
       the widget calls this only while a chain window is actually open and
       hide.skillchain_icon is off, so the cycle runs during the seconds the
       border is on screen and is simply paused the rest of the time - the
       only stretch where its phase can be seen. Module-instance state like
       the sweep maxima; a rebuild at attach restarts the cycle, which is
       invisible. ]]
  local animation_count = 0

  function self.chain_tick()
    animation_count = animation_count + 1
    if animation_count > 40 then
      animation_count = 1
    end
    return math.floor((animation_count - 1) / 5) + 1
  end

  -- Text positions for a slot at (x, y), upstream's offsets verbatim,
  -- slot-relative. Cost and recast are right-justified, so the WIDGET
  -- subtracts the screen width from their x - after scaling, which is why
  -- the subtraction cannot live here - the same texts-library gotcha
  -- giltracker documents.
  function self.text_offsets(x, y)
    local right = x + 16
    return {
      name = { x = x - 2, y = y + 40 },
      cost = { x = right + 30, y = y + 28 },
      recast = { x = right + 20, y = y + 14 },
    }
  end

  -- The cost corner: MP wins over TP as upstream orders it, nothing is
  -- priced at zero, and `affordable` is the unusable-dimming input. A vital
  -- the client has not filled in yet counts as affordable - vitals arrive
  -- piecemeal (parambar's lesson), and dimming on ignorance would read as
  -- unusable at every login.
  function self.cost(meta, vitals)
    if meta == nil then
      return nil
    end
    vitals = vitals or {}
    if meta.mp_cost ~= nil and meta.mp_cost ~= 0 then
      return {
        text = tostring(meta.mp_cost),
        color = type(config.mp_cost_color) == "table" and config.mp_cost_color or MP_COST_COLOR,
        affordable = vitals.mp == nil or vitals.mp >= meta.mp_cost,
      }
    end
    if meta.tp_cost ~= nil and meta.tp_cost ~= 0 then
      return {
        text = tostring(meta.tp_cost),
        color = type(config.tp_cost_color) == "table" and config.tp_cost_color or TP_COST_COLOR,
        affordable = vitals.tp == nil or vitals.tp >= meta.tp_cost,
      }
    end
    return nil
  end

  function self.slot_alpha(usable)
    if usable then
      return 255
    end
    return config.disabled_alpha
  end

  -- One step of the press flash: the alpha walks down by the configured
  -- speed each frame and answers nil when the flash is spent. The config is
  -- hand-editable, so a garbage feedback block falls back to the shipped
  -- speed rather than doing arithmetic on it.
  function self.feedback_fade(alpha)
    if alpha == nil then
      return nil
    end
    local feedback = type(config.feedback) == "table" and config.feedback or {}
    alpha = alpha - (feedback.speed or 30)
    if alpha <= 0 then
      return nil
    end
    return alpha
  end

  --[[ Icon resolution: an ordered list of addon-relative candidate paths for
       a bound slot; the widget draws the first one whose file exists. The
       order is the contract:

         1. the record-level `icon` override (a pack-relative name the
            authoring surface writes), custom copy first - resolved as
            icons/custom/<icon>.png then the shipped pack, per the icon
            verb's contract; deliberately resolved here and not in
            actions.icon_for, which only knows the type defaults;
         2. icons/custom/<name>.png - the player's own art for the action's
            own name, beside the addon at runtime;
         3. the pack's name-resolved art (ninjutsu/utsusemi-ichi.png ...);
         4. the type default: the id-indexed spell/ability sheets, the weapon
            type, the extracted item cache, or the built-in table via
            deps.icon_for.

       Each candidate carries the offset it draws at: the id sheets and
       extracted bitmaps are 32x32 and centre at +4/+4 in the 40px slot
       (upstream's own fix); pack art draws at the origin. ]]
  local ASSETS = "components/crossbar/assets/"

  --[[ The ability recast ids whose icons are job-suffixed on the shipped
       sheet: the lv1 SP pool (0), the lv96 SP pool (254), and the GEO/RUN
       lv96 SP2s - Widened Compass and Odyllic Subterfuge - which carry
       their own recast ids (130, 131) instead of sharing 254. Every lv1 SP
       rides recast 0.

       Four lv1 SP icons are missing from the sheet - 00000.01 (Mighty
       Strikes), 00000.16 (Azure Lore), 00000.21 (Bolster) and 00000.22
       (Elemental Sforzo); upstream's sheet has the same holes. For those
       the candidates fall through to icons/custom/ alone: no art is
       invented, custom art is the user's route, exactly as upstream draws
       blank. ]]
  local SP_RECAST_IDS = { [0] = true, [130] = true, [131] = true, [254] = true }
  local SP_SHEET_HOLES = {
    ["00000.01"] = true,
    ["00000.16"] = true,
    ["00000.21"] = true,
    ["00000.22"] = true,
  }

  local RANGED_WEAPONS = { archery = "bow", marksmanship = "gun" }

  function self.icon_candidates(record, meta, state)
    local candidates = {}
    if record == nil then
      return candidates
    end
    meta = meta or {}

    local function add(path, centred)
      local offset = centred and { x = 4, y = 4 } or { x = 0, y = 0 }
      candidates[#candidates + 1] = { path = path, offset = offset }
    end

    -- The explicit override first, custom art before the shipped copy (the
    -- icon-verb contract: <addon>/icons/custom/<name>.png, then the pack) -
    -- then the action's own name under icons/custom/. Note the shipped id
    -- sheets are not complete: ~87 spells (mostly trusts) and ~28 job
    -- abilities have no id art upstream either, so a slot bound to one
    -- draws no icon; icons/custom/ is the route there too.
    if type(record.icon) == "string" then
      -- The custom side flattens a pack-relative override to its basename:
      -- the plan promises users a FLAT icons/custom/ folder, so an override
      -- like items/warp-ring looks for icons/custom/warp-ring.png. The
      -- shipped side keeps the full relative path. A string with no
      -- basename ("", "items/") is no override at all - the pair is
      -- skipped, never a concat throw in the per-frame path.
      local basename = record.icon:match("([^/]+)$")
      if basename ~= nil then
        add("icons/custom/" .. basename .. ".png")
        add(ASSETS .. "icons/" .. record.icon .. ".png")
      end
    end
    local name = record.action or record.type
    if type(name) == "string" then
      -- Flattened the same way: kebab round-trips '/' for real action
      -- names, so a pathological one must not smuggle slashes (or an empty
      -- name) into icons/custom/.
      local flat = kebab(name):match("([^/]+)$")
      if flat ~= nil then
        add("icons/custom/" .. flat .. ".png")
      end
    end

    -- Field guards throughout: hand-edited binding files reach this path,
    -- and a wrong-typed field skips its own candidate rather than throwing
    -- in the draw path.
    if record.type == "ma" or record.type == "ja" or record.type == "pet" then
      -- meta.category is the DISPLAY form ("Blue Magic", "White Magic"):
      -- kebab maps it onto the pack directory (blue-magic). CB5's ctx must
      -- hand these display forms, never raw resource types - "BlueMagic"
      -- would kebab to "bluemagic" and silently miss the whole directory.
      if type(record.action) == "string" and type(meta.category) == "string" then
        add(ASSETS .. "icons/" .. kebab(meta.category) .. "/" .. kebab(record.action) .. ".png")
      end
      if type(meta.recast_id) == "number" then
        -- Only a `ja` record can be an SP: pet records (the blood pacts,
        -- which share recast 0 with the lv1 SPs) take the plain-sheet
        -- branch below, so the recast-0 collision is excluded by record
        -- type - no category value is consulted. Note the suffix wants
        -- the ability's OWNING job: the main job coincides for your own SP,
        -- but a shared set viewed cross-job diverges - CB5's ctx supplies
        -- the id that matches the record, not blindly the player.
        if record.type == "ja" and SP_RECAST_IDS[meta.recast_id] then
          -- The SP abilities are stored job-suffixed on the shipped sheet
          -- (00000.02.png ... - no plain 00000.png exists; upstream's
          -- resource_generator builds the same suffix from the owning job).
          -- Without a job id no suffixed file can be named correctly, so
          -- the sheet is skipped rather than guessed at.
          if type(meta.job_id) == "number" then
            local sheet_name = ("%05d.%02d"):format(meta.recast_id, meta.job_id)
            if not SP_SHEET_HOLES[sheet_name] then
              add(ASSETS .. "icons/abilities/" .. sheet_name .. ".png", true)
            end
          end
        else
          local sheet = record.type == "ma" and "spells" or "abilities"
          add(ASSETS .. ("icons/%s/%05d.png"):format(sheet, meta.recast_id), true)
        end
      end
    elseif record.type == "ws" then
      if type(record.action) == "string" and type(meta.weapon) == "string" then
        add(ASSETS .. "icons/weaponskills/" .. kebab(meta.weapon) .. "/" .. kebab(record.action) .. ".png")
      end
      if type(meta.weapon) == "string" then
        -- The weapon-type sheet keeps its spaces ("great axe.png"), so only
        -- the case folds - kebab would miss the file. The sheet has no
        -- archery/marksmanship/throwing art (upstream shares the hole, not
        -- inherited): the first two map to their weapon, throwing to the
        -- generic ranged single.
        local weapon = meta.weapon:lower()
        if weapon == "throwing" then
          add(ASSETS .. "icons/ranged.png")
        else
          add(ASSETS .. "icons/weapons/" .. (RANGED_WEAPONS[weapon] or weapon) .. ".png", true)
        end
      end
    elseif record.type == "item" or record.type == "enchanteditem" then
      -- Both draw the item's own art. Leaving enchanteditem out did not
      -- fall back to something plainer: it fell all the way through to the
      -- built-in defaults, which have nothing for it, so the slot drew
      -- NOTHING while still paying for the DAT extraction.
      if type(record.action) == "string" then
        add(ASSETS .. "icons/items/" .. kebab(record.action) .. ".png")
      end
      if type(meta.item_id) == "number" then
        -- The shared extracted-icon cache beside the addon (lib/icons), NOT
        -- under data/ - see equipviewer for why.
        add(("icons/%d.bmp"):format(meta.item_id), true)
      end
      --[[ An enchanteditem with no target word still aims at <me> (that is
           enchanteditem.lua's default, since gear is worn by the person
           wearing it), so it draws the self-use art rather than the
           generic - the two files agreeing on what "no target" means. ]]
      local on_self = record.target == "me" or (record.type == "enchanteditem" and record.target == nil)
      add(ASSETS .. (on_self and "icons/usable-item.png" or "icons/item.png"))
    elseif record.type == "ra" then
      add(ASSETS .. "icons/ranged.png")
    elseif record.type == "mount" then
      if type(record.action) == "string" then
        add(ASSETS .. "icons/mounts/" .. kebab(record.action) .. ".png")
      end
      add(ASSETS .. "icons/mount.png")
    else
      -- The built-ins resolve through actions.icon_for's type defaults.
      -- ct/ex land here too and icon_for answers nil for them - nothing
      -- shipped depicts an arbitrary chat line or console command, so
      -- those types deliberately resolve only through icons/custom/ and
      -- the record-level override above.
      local builtin = deps.icon_for ~= nil and deps.icon_for(record, state) or nil
      if builtin ~= nil then
        add(ASSETS .. "icons/" .. builtin .. ".png")
      elseif record.type == "open" then
        -- The plan's fallback for opener entries with no single of their
        -- own (equipment, quests, linkshell): a generic opener glyph. The
        -- shipped magnifier is the closest thing the pack has to one. Keyed
        -- on the record and the nil answer, never on whether the dep was
        -- wired.
        add(ASSETS .. "icons/check.png")
      end
    end

    return candidates
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
