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

--[[ Status bar configuration defaults - one file for all three bars.

     The bars are one component with three anchors, so each bar's own settings
     sit under `bars.<anchor>`: the anchor name is the single key across the
     config, the code, the command word and the layout-mode label. What is
     shared sits beside them: `priority`, one order for all three (a buff is
     as important on one bar as on another), and two switches: `timers` and
     `tooltips` (the buff's name and id under the cursor).

     Position, scale and visibility are framework-owned and live in layout
     slots. Bars 2 and 3 start switched off - the single all-bar is XIV's own
     default, and two empty strips on screen would read as a bug - and say so
     with `visible = false` on their anchors; absent means shown, so bar1 says
     nothing. ]]

local BARS = { "bar1", "bar2", "bar3" }
local FILTERS = { bar1 = "all", bar2 = "debuffs", bar3 = "other" }

-- Bar 1 sits in the top-left corner, where XI's own display is not; the
-- other two stack beneath it one bar-height apart - a one-row bar is 46px
-- (logic.lua's icon plus timer band), so 56 leaves a gap between them.
local ORIGIN = { 0.015625, 0.0208333 }
local ROW_PITCH = 56

return function(screen_width, screen_height)
  local bars, anchors = {}, {}
  local x = math.floor((screen_width or 0) * ORIGIN[1] + 0.5)
  local y = math.floor((screen_height or 0) * ORIGIN[2] + 0.5)

  for index, name in ipairs(BARS) do
    bars[name] = {
      filter = FILTERS[name],
      rows = 1,
      filters = {},
      filter_mode = "blacklist",
    }
    anchors[name] = {
      pos = { x = x, y = y + (index - 1) * ROW_PITCH },
      scale = 1,
    }
    -- Written as a statement because `cond and false or nil` yields nil for
    -- both answers.
    if name ~= "bar1" then
      anchors[name].visible = false
    end
  end

  -- No top-level pos or scale: layout.repair keys the anchored branch off the
  -- defaults, and would shed a stray pair from every file it repaired anyway.
  return {
    bars = bars,
    priority = {},
    timers = true,
    tooltips = true,
    layout = {
      anchors = anchors,
      visible = true,
    },
  }
end
