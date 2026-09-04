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

--[[ Speed Check configuration defaults.

     Position, scale and visibility are framework-owned and live in layout
     slots; the reference addon (SpeedChecker, BSD (c) 2013-2014 Windower) had
     no layout of its own at all - it handed Windower's config library an empty
     table and let the player edit settings.xml.

     The default anchor is measured from the same edge giltracker's is, so the
     two stack rather than overlap on a first run. ]]

local FONT_SIZE = 10
local ICON_SIZE = 32
-- Between the foot of the icon and the top of the number's LINE box, which is
-- taller than the glyphs in it (TEXT_HEIGHT_RATIO is ascender to descender), so
-- a gap of zero already reads as a gap on screen. Negative pulls the number up
-- into the icon's own transparent foot, which is where it looks right - the
-- value is Kevin's, from a live client.
local TEXT_GAP = -1

-- giltracker's own anchor, so the two widgets share a left edge; this one sits
-- a row above it.
local ANCHOR_FROM_RIGHT = 345
-- Far enough up that the whole stack - icon, gap and number - clears the gil
-- tracker's own row rather than landing on it.
local ANCHOR_FROM_BOTTOM = 90

-- Builds a fresh defaults table for a screen of the given size.
return function(screen_width, screen_height)
  return {
    font = "sans-serif",
    font_size = FONT_SIZE,
    -- Bold and stroked: the number is drawn ON the icon rather than beside it,
    -- so it has art under it rather than the screen.
    bold = true,
    italic = false,
    text_color = { a = 255, r = 255, g = 255, b = 255 },
    text_stroke = { width = 2, a = 255, r = 0, g = 0, b = 0 },
    -- Centring is estimated from the font size (no prim can be measured), so
    -- these are the knobs for correcting it against a live client.
    text_offset = { x = 0, y = 0 },
    text_gap = TEXT_GAP,
    bg = { visible = false, a = 100, r = 0, g = 0, b = 0 },
    icon = {
      visible = true,
      -- The source art's own size. Anything larger scales it up.
      size = ICON_SIZE,
      color = { a = 255, r = 255, g = 255, b = 255 },
    },
    layout = {
      pos = {
        x = math.max(0, (screen_width or 0) - ANCHOR_FROM_RIGHT),
        y = math.max(0, (screen_height or 0) - ANCHOR_FROM_BOTTOM),
      },
      scale = 1,
      visible = true,
    },
  }
end
