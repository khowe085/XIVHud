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

--[[ Target Bar configuration defaults.

     Colours come from three separate sources and are deliberately kept apart:
     the text colour and stroke are partylist's (this widget is styled to match
     it), the hp bands are partylist's too, and the fill palette is enemybar's
     claim colours - moved from its text, where the reference put them, onto
     the bar fill. ]]

-- Mirrors logic.lua's row arithmetic so the first-run slot can centre the
-- widget before any config exists to derive it from. giltracker does the same
-- with its reserved width; the duplication is the price of defaults being
-- built before logic sees a config.
local FONT_SIZE = 14
local RATIO = 0.75
local FRAME_WIDTH = 512
local ROW_WIDTH = math.max(
  math.ceil(5 * FONT_SIZE * RATIO) + math.ceil(5 * FONT_SIZE * RATIO) + math.ceil(17 * FONT_SIZE * RATIO),
  FRAME_WIDTH
)

-- Builds a fresh defaults table for a screen of the given size.
return function(screen_width, _screen_height)
  return {
    font = "Arial",
    font_size = FONT_SIZE,
    -- partylist's own text colour and stroke: this widget is meant to read as
    -- part of the same HUD.
    text_color = { a = 255, r = 240, g = 255, b = 255 },
    text_stroke = { width = 2, a = 200, r = 6, g = 45, b = 84 },
    -- The hp number's bands. "normal" (>= 75%) is deliberately absent - it
    -- falls back to text_color, exactly as partylist's palette does.
    bands = {
      red = { a = 255, r = 252, g = 129, b = 130 },
      orange = { a = 255, r = 248, g = 186, b = 128 },
      yellow = { a = 255, r = 243, g = 243, b = 124 },
    },
    -- enemybar's claim palette, in its own priority order.
    fill_colors = {
      dead = { a = 255, r = 155, g = 155, b = 155 },
      -- Deepened from the reference's 255,204,204: its pale pink was drawn
      -- as a text colour, and spread across a wide fill it read as washed
      -- out rather than "this one is ours".
      mine = { a = 255, r = 255, g = 20, b = 20 },
      member = { a = 255, r = 102, g = 255, b = 255 },
      pc = { a = 255, r = 255, g = 255, b = 255 },
      unclaimed = { a = 255, r = 230, g = 230, b = 138 },
      claimed = { a = 255, r = 153, g = 102, b = 255 },
    },
    name_max_chars = 17,
    -- Text bottom to the bar's *visible* band, not to the texture's top: the
    -- art carries 25px of transparent padding above the band.
    gap = 8,
    distance = {
      mode = "auto",
      -- DistancePlus's four states.
      colors = {
        out = { a = 255, r = 255, g = 255, b = 255 },
        capable = { a = 255, r = 255, g = 255, b = 0 },
        good = { a = 255, r = 0, g = 255, b = 0 },
        best = { a = 255, r = 0, g = 0, b = 255 },
      },
    },
    cast = {
      -- The claim palette's unclaimed yellow, but its own key: the cast fill
      -- is fixed and never follows the claim state.
      fill_color = { a = 255, r = 230, g = 230, b = 138 },
      -- One factor for both axes, so the key cannot leave the height
      -- undetermined.
      scale = 0.5,
      font_size = 10,
      -- HP band bottom to the cast band's top, and cast band bottom to the
      -- name row.
      gap = 4,
      name_gap = 2,
      name_max_chars = 20,
      -- A TP move's ready time is in no packet and no resource, so its bar is
      -- an animation of this length rather than a measurement.
      tp_move_sweep = 2,
    },
    slots = {
      default = {
        pos = {
          x = math.max(0, math.floor(((screen_width or 0) - ROW_WIDTH) / 2)),
          y = 50,
        },
        scale = 1,
        visible = true,
      },
    },
  }
end
