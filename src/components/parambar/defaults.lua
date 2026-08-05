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

--[[ Parameter Bar configuration defaults.

     Keys are snake_case; the XIVBar setting each one replaces is named in the
     comments. Position, scale and visibility are framework-owned and live in
     layout slots, so XIVBar's OffsetX/OffsetY are gone — the default slot just
     reproduces its bottom-centre anchor for the first run. ]]

local FULL_WIDTH = 472
local ANCHOR_FROM_BOTTOM = 60

local function low_vitals_colors()
  -- XIVParty's bands. Thresholds are hardcoded in logic.lua; only the colours
  -- are user-facing.
  return {
    yellow = { r = 243, g = 243, b = 124 },
    orange = { r = 248, g = 186, b = 128 },
    red = { r = 252, g = 129, b = 130 },
  }
end

-- Builds a fresh defaults table for a screen of the given size.
return function(screen_width, screen_height)
  return {
    compact = false, -- Theme.Compact
    bar = { width = 132, spacing = 18, offset = 0 }, -- Theme.Bar.*
    compact_bar = { width = 116, spacing = 16, offset = 0 }, -- Theme.Bar.Compact.*
    dim_tp_bar = true, -- Theme.DimTpBar
    font = "sans-serif", -- Texts.Font
    font_size = 14, -- Texts.Size
    text_offset = 0, -- Texts.Offset
    text_color = { a = 255, r = 253, g = 252, b = 250 }, -- Texts.Color
    -- XIVBar hardcoded these stroke values for its ffxiv theme; here they are
    -- plain defaults the user can change.
    text_stroke = { width = 2, a = 150, r = 80, g = 70, b = 30 },
    full_tp_color = { r = 80, g = 180, b = 250 }, -- Texts.FullTpColor
    low_hp_colors = low_vitals_colors(),
    low_mp_colors = low_vitals_colors(),
    slots = {
      default = {
        pos = {
          x = math.max(0, math.floor((screen_width or 0) / 2 - FULL_WIDTH / 2)),
          y = math.max(0, (screen_height or 0) - ANCHOR_FROM_BOTTOM),
        },
        scale = 1,
        visible = true,
      },
    },
  }
end
