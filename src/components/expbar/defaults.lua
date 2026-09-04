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

     Two things are DERIVED rather than chosen (see measure.lua): the bar's
     width, which is flush with the header and runs a little past the longest
     line it can print, and the job icon's size, which is the height of the two
     rows it stands beside and spans. The widget is wider than its bar by that
     icon, and that total is what the default slot centres. ]]

local measure = require("components/expbar/measure")

-- The widget is 23px tall at scale 1 (header, gap, bar), so this leaves it
-- clear of the screen edge without pushing it up into the play area.
local ANCHOR_FROM_BOTTOM = 32

return function(screen_width, screen_height)
  local config = {
    font = "sans-serif",
    -- 8pt: 11 drew far too large in a live client (Kevin, 2026-09-04).
    font_size = 8,
    -- The crossbar's gold, so the line matches the job glyph beside it and the
    -- gold of the bar's own fill below.
    text_color = { a = 255, r = 255, g = 215, b = 0 },
    -- XIVBar's stroke values.
    text_stroke = { width = 2, a = 150, r = 80, g = 70, b = 30 },
    --[[ The gap between the bottom of the header band and the top of the bar.
         The band itself is not configured: it is the taller of the header and
         the icon, both derived, so nothing here can disagree with the font
         size the way a written-down band height would. ]]
    gap = 2,
    --[[ The main job's icon: left of both rows, and as tall as the two of them
         together - `size` is derived below. XivParty's glyphs are gold with a
         dark outline, so they are drawn on their own.

         `gap` is 1 because the ART already carries a gap of its own, and a
         different one per job: of its 64px square WHM's glyph starts 18px in
         and WAR's 4px, which at this size is ~5px against ~1px of apparent
         space before the text. Nothing here can even that out - it would take
         cropping the art per job - so the configured gap is kept to almost
         nothing and the drawn one varies with the job. ]]
    job_icon = { gap = 1 },
    --[[ barfiller's own 5px bar with its fill inset 2px, but NOT its fixed 472
         width: the bar starts where the header does and runs `overhang` past
         the longest line it can print, and `width` is derived from exactly that
         below. The art is 472 wide and is squeezed to whatever comes out,
         which costs a fraction of a pixel off each of its 2px caps.

         `width` is derived ONCE, here. A config that changes `font_size`
         afterwards wants its `width` changed with it, or a
         `//hud reset expbar` to derive both again. ]]
    bar = { height = 5, inset = 2, overhang = 8 },
    -- How wide and how tall a character draws, as fractions of the font size.
    -- See measure.lua: the two numbers in here only a live client can settle.
    -- The height is what the icon's bottom is aligned against.
    text_width_ratio = 0.68,
    text_height_ratio = 1.3,
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
  -- Square, and exactly as tall as the rows beside it.
  config.job_icon.size = measure.rows_height(config)
  config.layout.pos.x = math.max(0, math.floor((screen_width or 0) / 2 - measure.widget_width(config) / 2))
  return config
end
