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

--[[ Crossbar configuration defaults. Keys are snake_case; bindings are NOT
     here -- they live in the per-job files under data/<Character>/crossbar/.
     Geometry and alpha values are upstream xivcrossbar's verbatim (decided:
     port its drawing, don't re-derive); compact halves bar_spacing at render
     time exactly as upstream does. ]]

local new_render = require("components/crossbar/render")
local new_retry = require("components/crossbar/retry")
local new_travel = require("components/crossbar/travel")

local SLOT_SPACING = 6
-- First-run placements, tuned in-client: the anchor footprints come from
-- render.lua itself (bounds/metrics over this very config), so a geometry
-- change there cannot leave these placements behind. The remaining local
-- numbers are placement policy, not geometry: the skillchain indicator
-- floats 40px above the WXHB pair, and upstream anchors its bottom slot
-- row at ui_y_res - 120, which our panel-top origin translates to
-- 120 + pad + two rows up - clear of the footprint with room below.
local BOTTOM_ROW_FROM_BOTTOM = 120
local INDICATOR_LIFT = 40

-- Builds a fresh defaults table for a screen of the given size.
return function(screen_width, screen_height)
  screen_width = screen_width or 0
  screen_height = screen_height or 0

  local set_flags = {}
  for set = 1, 8 do
    -- An untouched FFXIV install: unshared, cycled in both weapon states.
    set_flags[set] = { shared = false, cycle = { drawn = true, sheathed = true } }
  end

  local config = {
    input = {
      -- DIK codes per role; the pad bridge emits these. Every role is a list
      -- so one role can carry several physical keys. To REMOVE an entry set
      -- it to `false`, not nil: the defaults merge refills nil keys, never
      -- false ones, and input.lua skips false elements.
      xhb_left = { 39 }, -- ;
      xhb_right = { 40 }, -- '
      w_layer = { 43 }, -- backslash; + a side = the WXHB views
      set_switch = { 41 }, -- backtick; tap cycle, chord jump, ours always
      slot_keys = { 2, 3, 4, 5, 6, 7, 8, 9 }, -- positional: index = slot number
      --[[ Dedicated keys -> //hud crossbar verbs. A `tap` verb fires on a
           bare press, a `chorded` one while a side is held; an entry may
           carry either, both, or - as Select does - only the chord.

           Select is deliberately INERT bare (Kevin, 2026-08-21): it used to
           open the map, and a key that is ours outright should not act on
           its own. It is still ours, still blocked from the game, and still
           opens the binder when chorded - the block keys off the entry
           existing, not off it having a verb. ]]
      shortcuts = {
        [13] = { chorded = "edit" }, -- '='; pad Select
      },
    },
    always_show_wxhb = false, -- WXHB at rest, or only while its gesture holds
    views = { -- what WXHB / Expanded Hold display: set + side
      -- One set per bar, so nothing duplicates what is already on screen:
      -- the XHB starts on set 1, so the WXHB takes set 2 and Expanded set 3.
      wxhb_left = { set = 2, side = "left" },
      wxhb_right = { set = 2, side = "right" },
      expanded_lr = { set = 3, side = "left" },
      expanded_rl = { set = 3, side = "right" },
    },
    -- Per-set flags; character-wide by definition (a set's shared-ness cannot
    -- vary by job, or two jobs would disagree about where set n lives).
    set_flags = set_flags,
    slot_spacing = SLOT_SPACING,
    bar_spacing = 56, -- upstream's HotbarSpacing verbatim; compact halves it at render time
    slot_alpha = 100,
    button_bg_alpha = 150,
    disabled_alpha = 100, -- unusable action
    hide = {
      empty_slots = false,
      action_name = false,
      cost = false,
      element = true,
      recast_animation = false,
      recast_text = false,
      skillchain_icon = false,
    },
    feedback = { alpha = 150, speed = 30 }, -- press flash
    font = "sans-serif",
    font_size = 7,
    text_offset = { x = 0, y = 0 },
    text_color = { a = 255, r = 255, g = 255, b = 255 },
    text_stroke = { width = 2, a = 200, r = 20, g = 20, b = 20 },
    mp_cost_color = { r = 230, g = 91, b = 151 },
    tp_cost_color = { r = 254, g = 222, b = 0 },
    -- Where the game is installed, for item-icon extraction. Empty means
    -- "use the client's own answer" (equipviewer's idiom); set it only when
    -- the registry answer is wrong.
    game_path = "",
    -- The cast retry's switch and tuning, from the state machine that reads
    -- them: it ships off, and its numbers are first guesses to be tuned in
    -- a live client. See retry.lua.
    retry = new_retry({}).defaults(),
    -- Seconds between pressing mount, mount roulette or warp and actually
    -- going, counted out in chat and cancelled by resting. Zero is the off
    -- switch, so there is no toggle verb. See travel.lua.
    delay = new_travel({}).defaults().delay,
    skillchain = {
      indicator = true,
      opacity = 220,
      waiting_color = { r = 237, g = 28, b = 36 },
      open_color = { r = 15, g = 205, b = 5 },
    },
  }

  -- The footprints, from the geometry's owner over this very config.
  local render = new_render({ config = config })
  local metrics = render.metrics()
  local main_width, main_height = render.bounds("main")
  local indicator_width = render.bounds("indicator")
  local main_x = math.max(0, math.floor((screen_width - main_width) / 2))
  local main_y = math.max(0, screen_height - (BOTTOM_ROW_FROM_BOTTOM + metrics.pad_y + 2 * metrics.row_pitch))
  -- The WXHB halves mirror the XHB's side columns, one bar height above.
  local wxhb_y = math.max(0, main_y - main_height)

  -- Framework-owned; per-anchor under the multi-anchor contract. `visible`
  -- is per component, not per anchor.
  config.slots = {
    default = {
      anchors = {
        main = { pos = { x = main_x, y = main_y }, scale = 1 },
        wxhb_left = { pos = { x = main_x, y = wxhb_y }, scale = 1 },
        wxhb_right = { pos = { x = main_x + metrics.side_gap, y = wxhb_y }, scale = 1 },
        indicator = {
          pos = {
            x = math.max(0, math.floor((screen_width - indicator_width) / 2)),
            y = math.max(0, wxhb_y - INDICATOR_LIFT),
          },
          scale = 1,
        },
      },
      visible = true,
    },
  }
  return config
end
