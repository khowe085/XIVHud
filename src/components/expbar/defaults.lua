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

--[[ Exp Bar configuration defaults.

     Keys are snake_case. Position, scale and visibility are framework-owned and
     live in layout slots, so barfiller's own Pos/AllowDecenter settings are gone
     - the default slot just puts the widget along the bottom of the screen,
     where FFXIV draws this bar and where barfiller centres its own.

     The bar's WIDTH is derived rather than chosen (see measure.lua): it is
     flush with the header's left edge and runs a little past the longest line
     that header can print. The widget is wider than its bar by the job icon,
     which hangs off to the left of both, and that total is what the default
     slot centres. ]]

local measure = require("components/expbar/measure")

-- The widget is 23px tall at scale 1 (header, gap, bar), so this leaves it
-- clear of the screen edge without pushing it up into the play area.
local ANCHOR_FROM_BOTTOM = 32

return function(screen_width, screen_height)
  local config = {
    font = "sans-serif",
    font_size = 11,
    -- The crossbar's gold, so the line matches the job glyph beside it and the
    -- gold of the bar's own fill below.
    text_color = { a = 255, r = 255, g = 215, b = 0 },
    -- XIVBar's stroke values.
    text_stroke = { width = 2, a = 150, r = 80, g = 70, b = 30 },
    -- The band the header is drawn in; the bar sits under it, or under the job
    -- icon where that is the taller of the two.
    header_height = 16,
    gap = 2,
    -- The main job's icon, drawn left of the header. XivParty's glyphs are
    -- gold with a dark outline, so they are drawn on their own.
    job_icon = { size = 16, gap = 4 },
    --[[ barfiller's own 5px bar with its fill inset 2px, but NOT its fixed 472
         width: the bar starts where the header does and runs `overhang` past
         the longest line it can print, and `width` is derived from exactly that
         below. The art is 472 wide and is squeezed to whatever comes out,
         which costs a fraction of a pixel off each of its 2px caps.

         `width` is derived ONCE, here. A config that changes `font_size`
         afterwards wants its `width` changed with it, or a
         `//hud reset expbar` to derive both again. ]]
    bar = { height = 5, inset = 2, overhang = 8 },
    -- How wide a character draws, as a fraction of the font size. See
    -- measure.lua: the one number in here only a live client can settle.
    text_width_ratio = 0.68,
    --[[ White, which MODULATES barfiller's fill to itself: the art is already
         a gold gradient (255,245,191 down to 214,111,0), the same gold as the
         job glyph and the header text. One colour rather than one per mode -
         the modes are told apart by the line above the bar, not by a tint the
         gold art could not carry anyway. ]]
    fill_color = { r = 255, g = 255, b = 255 },
    layout = {
      pos = { x = 0, y = math.max(0, (screen_height or 0) - ANCHOR_FROM_BOTTOM) },
      scale = 1,
      visible = true,
    },
  }

  config.bar.width = measure.bar_width(config)
  -- Centred on the WIDGET, which the icon makes wider than the bar.
  config.layout.pos.x = math.max(0, math.floor((screen_width or 0) / 2 - measure.widget_width(config) / 2))
  return config
end
