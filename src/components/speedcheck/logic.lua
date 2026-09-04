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

--[[ Speed Check logic - the movement speed percentage and where the two prims
     go.

     It reads nothing and draws nothing itself: the widget reads the mob table
     and owns the prims.

     The percentage is the reference addon's, verbatim: the client reports a
     mob's movement speed as a number whose walking value is 5, so a speed of
     5.6 is +12%. Everything else here is layout. ]]

-- The client's walking speed with no modifiers of any kind.
local BASE_SPEED = 5

-- Nothing has been read yet. Deliberately not "+0%", which would claim the
-- player is at base speed on the strength of never having looked.
local UNKNOWN_TEXT = "--%"

-- The widest string the number ever takes ("-100%"), reserved so the icon
-- under it cannot shift as digits come and go.
local RESERVED_CHARACTERS = 5
-- Fraction of the font size one character occupies, measured for giltracker's
-- number in `//hud layout`. Used here to CENTRE rather than to reserve, so the
-- nearer estimate is the right one - config.text_offset corrects what it
-- misses in a live client.
local CHARACTER_WIDTH_RATIO = 0.75
-- Ascender to descender, as a multiple of the font size.
local TEXT_HEIGHT_RATIO = 1.5

-- What layout mode draws: the widest the number ever is, so the box on screen
-- is the footprint the widget will really take.
local PREVIEW_PERCENT = 100

local function new(initial_config)
  local self = {}
  local config = initial_config or {}

  local speed = nil
  local preview = false

  local function scaled_font_size(scale)
    -- Whole pixels: a fractional font size is not something a prim can draw.
    return math.floor((config.font_size or 0) * scale + 0.5)
  end

  local function text_width_of(characters, scale)
    return characters * scaled_font_size(scale) * CHARACTER_WIDTH_RATIO
  end

  -- The box the number is centred inside, which is fixed at a given scale: the
  -- widest string the number ever takes, so the icon under it and the origin
  -- the framework clamps stay put while the value moves.
  local function reserved_width(scale)
    return text_width_of(RESERVED_CHARACTERS, scale)
  end

  local function icon_size(scale)
    local icon = config.icon or {}
    if not icon.visible then
      return 0
    end
    return (icon.size or 0) * scale
  end

  --[[ The correction the number is drawn with, in pixels, at this scale. It
       moves the NUMBER against the icon, so the box has to grow to cover
       wherever that puts it: a positive one widens the box on the right, and a
       negative one pads it on the LEFT and shifts both prims across, which is
       what keeps everything at or right of the origin the framework clamps
       against. Only one of the two can be non-zero on an axis. ]]
  local function correction(scale)
    local offset = config.text_offset or {}
    local x = (offset.x or 0) * scale
    local y = (offset.y or 0) * scale
    return x, y, math.max(0, -x), math.max(0, -y)
  end

  -- What the number is held clear of the icon's foot by. Nothing to clear when
  -- the icon is switched off, so the number takes the whole box.
  local function gap(scale)
    if icon_size(scale) <= 0 then
      return 0
    end
    return (config.text_gap or 0) * scale
  end

  --[[ The two are STACKED, icon over number, so the box is as tall as both of
       them and as wide as the wider. The number used to be drawn on the art;
       it moved below it 2026-09-04 (Kevin, from a live client). ]]
  local function box(scale)
    local text_width = reserved_width(scale)
    local text_height = scaled_font_size(scale) * TEXT_HEIGHT_RATIO
    local art = icon_size(scale)
    local nudge_x, nudge_y = correction(scale)
    local width = math.max(art, text_width) + math.abs(nudge_x)
    local height = art + gap(scale) + text_height + math.abs(nudge_y)
    return width, height, text_width, text_height, art
  end

  function self.set_config(new_config)
    config = new_config
  end

  -- `movement_speed` off the mob table. A nil arrives every time the client has
  -- no mob for us - a zone load is a frame or two of it - and that is not a
  -- change of speed, so the last good value stays on screen.
  function self.set_speed(value)
    local reading = tonumber(value)
    if reading then
      speed = reading
    end
  end

  -- The character is gone; the next one must be read before anything is shown.
  function self.clear()
    speed = nil
  end

  function self.set_preview(on)
    preview = on and true or false
  end

  -- Whole percent, rounded half up on both signs: a -12.5% reading down to
  -- -13% would be a penalty the player does not have.
  function self.percent()
    if preview then
      return PREVIEW_PERCENT
    end
    if not speed then
      return nil
    end
    return math.floor(100 * (speed / BASE_SPEED - 1) + 0.5)
  end

  function self.text()
    local percent = self.percent()
    if not percent then
      return UNKNOWN_TEXT
    end
    return ("%+d%%"):format(percent)
  end

  --[[ Where the two prims go for a widget anchored at (x, y) and drawn at
       `scale`. The origin is the top left of the BOX, never either prim's own
       anchor, because get_bounds has to hand the framework back the same origin
       set_pos was given - and both prims are centred inside it, so whichever of
       the two is narrower is the one that moves. ]]
  function self.geometry(x, y, scale)
    local nudge_x, nudge_y, pad_x, pad_y = correction(scale)
    local width, _, _, text_height, art = box(scale)
    --[[ The GLYPHS are what has to line up with the art, so the number is centred
         on the width of the string actually drawn - a prim is left-justified
         (right_justified offsets by the screen width, see giltracker), so
         nothing else would put it there. The BOX stays measured against the
         reserved width, which is what keeps the icon still while the value
         moves. ]]
    local text_width = text_width_of(#self.text(), scale)
    -- The box the two prims are placed inside is the one the correction has
    -- not been added to yet; `pad` is its left and top edge inside the bounds.
    local inner_width = width - math.abs(nudge_x)
    return {
      icon = {
        x = x + pad_x + (inner_width - art) / 2,
        y = y + pad_y,
        size = art,
      },
      text = {
        x = x + pad_x + (inner_width - text_width) / 2 + nudge_x,
        y = y + pad_y + art + gap(scale) + nudge_y,
        size = scaled_font_size(scale),
        width = text_width,
        height = text_height,
      },
    }
  end

  function self.bounds(x, y, scale)
    local width, height = box(scale)
    return x, y, width, height
  end

  return self
end

return new
