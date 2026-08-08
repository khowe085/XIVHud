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

--[[ Equip Viewer configuration defaults.

     Keys are snake_case; the equipviewer setting each one replaces is named in
     the comments. Position, scale and visibility are framework-owned and live
     in layout slots, so the reference addon's `pos` is gone and its `size` is
     no longer the scale control - the framework's uniform scale multiplies the
     icon size below. Its hide_on_zone and hide_on_cutscene are gone too: the
     framework already suppresses the whole HUD in both cases.

     The reference's default position, which the default slot reproduces. ]]
local ANCHOR_X = 500
local ANCHOR_Y = 500

-- Builds a fresh defaults table for a screen of the given size.
return function(screen_width, screen_height)
  return {
    -- One cell of the grid, and the native size of an extracted icon. (size)
    icon_size = 32,
    icon = { a = 230, r = 255, g = 255, b = 255 }, -- icon.*
    bg = { visible = true, a = 72, r = 0, g = 0, b = 0 }, -- bg.*
    show_encumbrance = true, -- show_encumbrance
    -- The reference dimmed the X against the icon beneath it by multiplying
    -- the icon alpha inline; named here so it can be turned off.
    encumbrance_alpha_factor = 0.8,
    show_ammo_count = true, -- show_ammo_count
    ammo_text = {
      font = "sans-serif",
      -- Both fractions of a cell, from the reference. The count is drawn over
      -- the lower half of the ammo icon.
      size_factor = 0.27, -- ammo_count_text_settings.text.size
      y_factor = 0.58, -- ammo_count_text_settings.pos.y
      bold = true, -- ammo_text.flags.bold
      italic = true, -- ammo_text.flags.italic
      a = 230, -- ammo_text.alpha
      r = 255,
      g = 255,
      b = 255,
      stroke = { width = 1, a = 127, r = 0, g = 0, b = 0 }, -- ammo_text.stroke.*
    },
    -- Where the client is installed, when the addon cannot work it out itself.
    -- Left unset, the entry point asks Windower. (game_path)
    game_path = "",
    slots = {
      default = {
        pos = {
          x = math.min(ANCHOR_X, math.max(0, (screen_width or 0) - 128)),
          y = math.min(ANCHOR_Y, math.max(0, (screen_height or 0) - 128)),
        },
        scale = 1,
        visible = true,
      },
    },
  }
end
