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

--[[ Gil Tracker configuration defaults.

     Keys are snake_case; the giltracker setting each one replaces is named in
     the comments. Position, scale and visibility are framework-owned and live
     in layout slots, so the reference addon's gilText.pos is gone - the default
     slot just reproduces its bottom-right anchor for the first run. ]]

-- The reference anchored the right edge of its number 285px in from the right
-- of the screen and put the icon past it. Our origin is the left edge of the
-- box instead, so the reserved number width (60px at the default font) comes
-- off the anchor and the widget lands on the same footprint.
local FONT_SIZE = 9
-- Mirrors the reserved width logic.lua computes (11 characters of the gil cap,
-- each about 0.6 of the font size). Derived rather than hardcoded so changing
-- the font size below moves the default anchor with it.
local RESERVED_WIDTH = math.ceil(11 * FONT_SIZE * 0.6)
local ANCHOR_FROM_RIGHT = 285 + RESERVED_WIDTH
local ANCHOR_FROM_BOTTOM = 35

-- Builds a fresh defaults table for a screen of the given size.
return function(screen_width, screen_height)
  return {
    font = "sans-serif", -- gilText.text.font
    font_size = FONT_SIZE, -- gilText.text.size
    italic = true, -- gilText.flags.italic
    bold = false, -- gilText.flags.bold
    text_color = { a = 255, r = 253, g = 252, b = 250 }, -- gilText.text.*
    text_stroke = { width = 2, a = 200, r = 50, g = 50, b = 50 }, -- gilText.text.stroke.*
    -- The reference lifted its icon by size/6 to centre it against the smaller
    -- number. Inverted here into a nudge downwards for the text, so nothing is
    -- ever drawn above the origin the framework clamps against.
    text_y_offset = 4,
    bg = { visible = false, a = 100, r = 0, g = 0, b = 0 }, -- gilText.bg.*
    icon = {
      visible = true, -- gilImage.visible
      size = 23, -- gilImage.size.*, square
      gap = 1, -- was a bare "+ 1" against the text position
      color = { a = 255, r = 255, g = 255, b = 255 }, -- gilImage.color.*
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
