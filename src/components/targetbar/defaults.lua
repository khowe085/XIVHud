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

     TWO bars, under `bars.main` and `bars.subtarget`: the target and the
     `<st>` selection cursor. The two ship identical - the subtarget's smaller
     size is its anchor's scale, not a smaller font - but they are separate
     tables, because a command edits the bar it names.

     Colours come from three separate sources and are deliberately kept apart:
     the text colour and stroke are partylist's (this widget is styled to match
     it), the hp bands are partylist's too, and the fill palette is enemybar's
     claim colours - moved from its text, where the reference put them, onto
     the bar fill. ]]

local new_logic = require("components/targetbar/logic")

local ANCHORS = { "main", "subtarget" }

-- Roughly the reference's 300 against the target bar's 600. The art is the
-- same at either size; only the framework's scale differs.
local SUBTARGET_SCALE = 0.6
-- Between the target bar's box and the subtarget's, at the first-run slots.
-- The boxes take in the art's bottom padding, so the drawn gap reads wider.
local BAR_GAP = 8
-- The target bar's own first-run row, unchanged.
local MAIN_Y = 50

local function bar_defaults()
  return {
    font = "Arial",
    font_size = 14,
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
      scale = 0.67,
      font_size = 12,
      -- HP band bottom to the cast band's top, and cast band bottom to the
      -- name row.
      gap = 4,
      name_gap = 2,
      name_max_chars = 20,
      -- A TP move's ready time is in no packet and no resource, so its bar is
      -- an animation of this length rather than a measurement.
      tp_move_sweep = 2,
    },
  }
end

-- Builds a fresh defaults table for a screen of the given size.
return function(screen_width, _screen_height)
  local bars = {}
  for _, name in ipairs(ANCHORS) do
    bars[name] = bar_defaults()
  end

  --[[ Measured through the very maths the widget draws by, rather than a copy
       of the row arithmetic kept in step by hand - which is what stood here,
       under a comment calling its own drift latent, and which a second bar at
       a second scale would have doubled. logic holds no ctx and reads no
       client, so building one to ask it a question costs nothing. ]]
  local function box(name, scale)
    local _, _, width, height = new_logic(bars[name]).bounds(0, 0, scale)
    return width, height
  end

  local main_width, main_height = box("main", 1)
  local sub_width = box("subtarget", SUBTARGET_SCALE)

  local function centred(width)
    return math.max(0, math.floor(((screen_width or 0) - width) / 2))
  end

  return {
    bars = bars,
    -- No top-level pos or scale: layout.repair keys the anchored branch off
    -- the defaults, and would shed a stray pair from every file it repaired
    -- anyway. Neither anchor carries `visible` - absent means shown, and both
    -- bars ship on.
    layout = {
      anchors = {
        main = { pos = { x = centred(main_width), y = MAIN_Y }, scale = 1 },
        subtarget = {
          pos = { x = centred(sub_width), y = math.floor(MAIN_Y + main_height + BAR_GAP) },
          scale = SUBTARGET_SCALE,
        },
      },
      visible = true,
    },
  }
end
