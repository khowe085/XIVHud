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

--[[ Party list configuration defaults, one variant per registered component.

     Keys are snake_case; the XIVParty setting each replaces is named in the
     comments. Position, scale and visibility are framework-owned and live in
     layout slots, so XIVParty's party.pos / party.scale are gone -- the default
     slot just reproduces its first-run anchor.

     XIVParty's hideAlliance has no equivalent here either: the alliance lists
     are separate components, so `//hud hide alliancelist1` already says it. ]]

-- XIVParty's relative first-run anchors, resolution independent.
local ANCHORS = {
  main = { 0.015625, 0.4791666 },
  alliance1 = { 0.8671875, 0.5277777 },
  alliance2 = { 0.8671875, 0.5972222 },
}

-- The art is drawn for a 1440p screen, so a 1080p user starts at 0.75 rather
-- than with a list two thirds of their screen wide. XIVParty's autoscale, but
-- applied once as the default slot scale instead of every frame.
local BASE_RESOLUTION_Y = 1440

local function round(value, places)
  local factor = 10 ^ places
  return math.floor(value * factor + 0.5) / factor
end

return function(screen_width, screen_height, variant)
  local anchor = ANCHORS[variant] or ANCHORS.main
  local defaults = {
    -- get_party() roster/distance poll. Target and subtarget are read every
    -- frame instead: they drive the row cursor, and 200ms of lag between a
    -- target keypress and the cursor moving is visible.
    poll_interval_ms = 200,
    item_spacing = 0, -- party.itemSpacing
    align_bottom = false, -- party.alignBottom
    show_empty_rows = false, -- party.showEmptyRows
    range = {
      numeric = false, -- rangeNumeric
      near = 0, -- rangeIndicator, 0 = off
      far = 0, -- rangeIndicatorFar, 0 = off
    },
    slots = {
      default = {
        pos = {
          x = math.floor((screen_width or 0) * anchor[1] + 0.5),
          y = math.floor((screen_height or 0) * anchor[2] + 0.5),
        },
        scale = math.max(0.25, round((screen_height or BASE_RESOLUTION_Y) / BASE_RESOLUTION_Y, 2)),
        -- The alliance lists start switched off: most play is a single party,
        -- and two empty boxes on screen would read as a bug.
        visible = variant == "main",
      },
    },
  }

  if variant == "main" then
    defaults.hide_solo = false -- hideSolo
    -- 0x076 carries the main party only, and the alliance row has no buff
    -- icons, so there is nothing for the alliance variants to configure.
    defaults.buffs = {
      -- The tweak: XIVParty's 19+13 icons run 263px past the end of a 410px
      -- row and never clear the bars. Sixteen 20px icons in two rows of eight
      -- clear the bar frame below them; they still run past the row's own
      -- edge, but the frame is stretched to cover it rather than the icons
      -- being shrunk to fit inside 410 -- see layout.lua.
      max_icons = 16,
      filter_mode = "blacklist", -- buffs.filterMode
      filters = {}, -- buffs.filters, as ids rather than a semicolon string
      -- Sparse `id -> rank` overrides on top of buff_order.lua, so a later
      -- change to the shipped order does not stomp the user's edits.
      priority = {},
    }
  end

  return defaults
end
