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

--[[ Speed Check - the player's movement speed as a percentage, drawn over
     Bolter's Roll's own status icon.

     Re-implemented from the Windower `SpeedChecker` addon (BSD (c) 2013-2014
     Windower), which is one prerender handler and one text: the percentage
     maths below is its, and everything else here is the framework contract it
     had none of - position, scale, visibility and teardown are all core's.

     This file owns prims and nothing else; the number comes from logic.lua and
     whether to draw comes from the framework. Both prims are created once at
     construction so `destroy` can always dispose them.

     The reading is `movement_speed` off the player's own mob table -- the
     player table does not carry it -- and no packet carries it either, so it
     has to be polled. It is polled on `lib/player`'s read counter rather than
     on the frame: the mob memo is cleared every frame, so a read per frame is
     a real client call sixty times a second, and a speed moves when a buff, a
     mount or a piece of gear does. The prim is written only when the number it
     would draw has actually changed. ]]

local new_logic = require("components/speedcheck/logic")
local build_defaults = require("components/speedcheck/defaults")

-- Bolter's Roll (status 330) - the roll that grants movement speed, so the one
-- icon in the game that says what this widget is. XivParty's art, under its
-- notice in assets/xiv/LICENSE.txt.
local ICON_TEXTURE = "assets/xiv/buffIcons/330.png"

local function new(ctx)
  local self = { name = "speedcheck", alias = "sc" }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults
  local attached = false
  local logic = new_logic(config)

  local pos = nil
  local scale = 1
  local visible = false
  -- What the number prim currently holds, so an unchanged value costs no write.
  local drawn = nil
  -- The value of ctx.generation() the speed on screen was read at.
  local last_generation = nil

  local number = ctx.new_text()
  local icon = ctx.new_image()

  number.draggable(false)
  number.hide()

  icon.draggable(false)
  icon.repeat_xy(1, 1)
  -- The prim must not size itself to its texture, or the widget scale would
  -- silently do nothing.
  icon.fit(false)
  icon.path(ctx.asset(ICON_TEXTURE))
  icon.hide()

  local function apply_visibility()
    if not visible then
      number.hide()
      icon.hide()
      return
    end

    number.show()
    if (config.icon or {}).visible then
      icon.show()
    else
      icon.hide()
    end
  end

  local function apply_style()
    local color = config.text_color or {}
    local stroke = config.text_stroke or {}
    local background = config.bg or {}
    local icon_color = (config.icon or {}).color or {}

    number.font(config.font)
    number.italic(config.italic and true or false)
    number.bold(config.bold and true or false)
    number.color(color.r, color.g, color.b)
    number.alpha(color.a or 255)
    number.stroke_width(stroke.width)
    number.stroke_color(stroke.r, stroke.g, stroke.b)
    number.stroke_alpha(stroke.a)
    number.bg_visible(background.visible and true or false)
    number.bg_color(background.r, background.g, background.b)
    number.bg_alpha(background.a or 0)

    icon.color(icon_color.r, icon_color.g, icon_color.b)
    icon.alpha(icon_color.a or 255)
  end

  local function apply_layout()
    if not pos then
      return
    end

    local geometry = logic.geometry(pos.x, pos.y, scale)
    number.pos(geometry.text.x, geometry.text.y)
    number.size(geometry.text.size)
    icon.pos(geometry.icon.x, geometry.icon.y)
    icon.size(geometry.icon.size, geometry.icon.size)
  end

  local function apply_text()
    local text = logic.text()
    if text == drawn then
      return
    end
    drawn = text
    number.text(text)
    --[[ The number is centred on the width of the string it draws, so a value
         of another length has to be re-placed as well as re-written. Core
         pushes set_pos on an attach, a drag and a slot switch - never on a
         value change - so this is the only thing that would. Behind the
         unchanged-value guard above, so a settled speed still costs nothing. ]]
    apply_layout()
  end

  -- get_mob_by_target('me') comes back nil while a zone loads; logic keeps the
  -- last good value rather than blanking the number.
  local function read_speed()
    -- Nil without a counter in the ctx, which is what makes the tick below read
    -- every frame rather than never: a wiring slip must not freeze the widget
    -- on its first reading, where nothing on screen would say so.
    last_generation = ctx.generation and ctx.generation()
    local me = ctx.get_mob_by_target("me")
    logic.set_speed(me and me.movement_speed)
    apply_text()
  end

  function self.attach(loaded_config, _persist)
    config = loaded_config
    attached = true
    logic.set_config(config)
    apply_style()
    -- Read first: the placement is measured against the string, so laying out
    -- before the value is known would place the one it is replacing.
    read_speed()
    apply_layout()
    apply_visibility()
  end

  -- The character is gone, so the speed that was read for them is too.
  function self.detach()
    attached = false
    logic.clear()
    apply_text()
    self.hide()
  end

  function self.set_pos(x, y)
    pos = { x = x, y = y }
    apply_layout()
  end

  function self.set_scale(new_scale)
    scale = new_scale
    apply_layout()
  end

  function self.set_preview(on)
    logic.set_preview(on)
    apply_text()
  end

  function self.show()
    visible = true
    apply_visibility()
  end

  function self.hide()
    visible = false
    -- So the first tick after it comes back reads, however long it was off:
    -- the value it holds is as old as the cutscene it sat out.
    last_generation = nil
    apply_visibility()
  end

  function self.get_bounds()
    if not pos then
      return nil
    end
    return logic.bounds(pos.x, pos.y, scale)
  end

  --[[ No arguments is the per-frame tick. Every other event belongs to another
       component: core dispatches to everything registered.

       Nothing is read while the widget is off screen, and nothing is read
       twice inside one of the player service's read intervals. Asking for the
       counter is what opens the next interval, so this keeps its own cadence
       even when no other component reads the client. ]]
  function self.update(event)
    if event ~= nil or not attached or not visible then
      return
    end
    local generation = ctx.generation and ctx.generation()
    if generation ~= nil and generation == last_generation then
      return
    end
    read_speed()
  end

  function self.destroy()
    number.destroy()
    icon.destroy()
  end

  return self
end

return new
