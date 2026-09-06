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

--[[ The hotbar's shipped configuration and placement. The slot cosmetics
     and the per-set flags are every bar's (lib/actionbar/defaults); what is
     the hotbar's own is one shape per row (`bars.<anchor>.rows`, 10x1 out of
     the box) and eight anchors stacked down a column near the bottom of
     the screen, row 1 on and rows 2-8 off (Kevin, 2026-09-05). No keys here:
     the hotbar's are the game's own number row and fixed. ]]

local shared = require("lib/actionbar/defaults")
local new_render = require("components/hotbar/render")

local ANCHORS = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" }
-- The stack's foot, up from the bottom of the screen: clear of the crossbar's
-- own bottom row (120 there) and the chat log.
local BOTTOM_MARGIN = 100

return function(screen_width, screen_height)
  screen_width = screen_width or 0
  screen_height = screen_height or 0

  local config = shared.cosmetics()
  config.set_flags = shared.set_flags()
  config.bars = {}
  for _, anchor in ipairs(ANCHORS) do
    config.bars[anchor] = { rows = 1 }
  end

  local render = new_render({ config = config })
  local width = render.bounds(1)
  local pitch = render.row_pitch()
  local x = math.max(0, math.floor((screen_width - width) / 2))
  local top = math.max(0, screen_height - BOTTOM_MARGIN - #ANCHORS * pitch)

  local anchors = {}
  for index, anchor in ipairs(ANCHORS) do
    anchors[anchor] = { pos = { x = x, y = top + (index - 1) * pitch }, scale = 1 }
    -- Rows 2-8 ship off: the statusbar's pattern, an explicit `false` on
    -- the anchor and nothing on the one that is on.
    if index > 1 then
      anchors[anchor].visible = false
    end
  end
  config.layout = { anchors = anchors, visible = true }
  return config
end
