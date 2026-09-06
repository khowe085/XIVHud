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

--[[ The config every action bar ships with: the slot cosmetics a shared
     slot (lib/actionbar/slot) draws from, and the per-set flags the binding
     model reads. Each bar's own defaults.lua takes these and adds what is
     its own - the crossbar its keys, views and bar spacing, the hotbar its
     rows - so the two bars cannot ship a slot that looks different. The
     values are xivcrossbar's verbatim (decided: port its drawing, don't
     re-derive). Fresh tables every call: a defaults table is merged into and
     written through, and two bars must not share one. ]]

local M = {}

function M.cosmetics()
  return {
    slot_spacing = 6,
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
  }
end

--- Per-set flags, in a bar's config rather than a per-job file: a set's
--- shared-ness cannot vary by job, or two jobs would disagree about where
--- set n lives. An untouched FFXIV install: unshared, cycled in both weapon
--- states.
function M.set_flags()
  local flags = {}
  for set = 1, 8 do
    flags[set] = { shared = false, cycle = { drawn = true, sheathed = true } }
  end
  return flags
end

return M
