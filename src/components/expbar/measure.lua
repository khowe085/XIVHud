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

--[[ How wide the widget has to be.

     The bar is no longer barfiller's fixed 472: it starts at the header's own
     left edge and runs to slightly past the longest line that header can ever
     print, so the width is derived rather than chosen. The job icon stands to
     the left of both rows and spans them (Kevin, 2026-09-04, in a live client),
     so it is derived too - from the rows it has to cover. This lives apart
     from both defaults.lua and logic.lua because both need the same answer -
     the defaults to size and centre the widget, the specs to prove the header
     fits inside it.

     `WIDEST` mirrors logic.lua's format string with every field at its longest:
     three-letter jobs at two-digit levels, the master level, a four-digit job
     point count, three merit digits and a rate that has run into four. The two
     cannot drift silently - expbar_logic_spec drives the real header with
     maximal values and measures it against this.

     Windower cannot be asked how wide a string will draw from here, so the
     width comes from a per-character fraction of the font size. 0.68 is an
     estimate for this mixed run of capitals, digits and punctuation, and errs
     generous on purpose: too wide leaves slack past the text, too narrow puts
     the text over the end of the bar. It is `text_width_ratio` in the config
     precisely because only a live client can settle it. ]]

local WIDEST = "WAR99/SAM49 (ML50) JP: 9999 MP: 999 EXP/hr: 9999.9k"

local M = { WIDEST = WIDEST }

-- The header's own width, at a font size and a per-character ratio.
function M.header_width(font_size, ratio)
  return math.ceil(#WIDEST * (font_size or 0) * (ratio or 0))
end

-- The bar: the widest header, flush with it, plus the overhang that carries
-- the bar past the end of the text.
function M.bar_width(config)
  config = config or {}
  local bar = type(config.bar) == "table" and config.bar or {}
  return M.header_width(config.font_size, config.text_width_ratio) + (bar.overhang or 0)
end

-- The whole widget, which the icon standing left of the two rows makes wider
-- than the bar. This is what the default slot centres, and what `bounds`
-- reserves.
function M.widget_width(config)
  config = config or {}
  local icon = type(config.job_icon) == "table" and config.job_icon or {}
  return (icon.size or 0) + (icon.gap or 0) + M.bar_width(config)
end

--[[ How tall the header draws, which is what the icon's bottom is aligned
     against. Windower cannot be asked that any more than it can be asked a
     width, so it is the same shape of estimate: a multiple of the font size,
     config for a live client to settle. ]]
function M.text_height(config)
  config = config or {}
  return math.ceil((config.font_size or 0) * (config.text_height_ratio or 0))
end

--[[ How tall the widget's two rows are together: the header, the gap under it
     and the bar. The icon spans exactly that, and being square it is that wide
     too - so the icon grows with the font rather than being written down beside
     it and drifting out of step. ]]
function M.rows_height(config)
  config = config or {}
  local bar = type(config.bar) == "table" and config.bar or {}
  return M.text_height(config) + (config.gap or 0) + (bar.height or 0)
end

--[[ How tall the widget's two rows are together: the header, the gap under it
     and the bar. The icon spans exactly that, and being square it is that wide
     too - so the icon grows with the font rather than being written down beside
     it and drifting out of step. ]]
function M.rows_height(config)
  config = config or {}
  local bar = type(config.bar) == "table" and config.bar or {}
  return M.text_height(config) + (config.gap or 0) + (bar.height or 0)
end

return M
