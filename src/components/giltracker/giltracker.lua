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

--[[ Gil Tracker - the FFXIV gil widget for FFXI: the current gil total beside
     the gil icon.

     This file owns prims and nothing else; when to re-read gil comes from
     logic.lua, and whether to draw comes from the framework. Both prims are
     created once at construction so `destroy` can always dispose them - the
     reference addon had no unload path and left its number on screen.

     There is no per-frame work: the value is pushed the moment a read happens,
     so the tick does nothing. ]]

local new_logic = require("components/giltracker/logic")
local build_defaults = require("components/giltracker/defaults")

local ASSET_DIR = "components/giltracker/assets/"
local ICON_TEXTURE = "gil.png"

local function new(ctx)
  local self = { name = "giltracker" }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults
  local attached = false
  local logic = new_logic(config)

  local pos = nil
  local scale = 1
  local visible = false

  local number = ctx.new_text()
  local icon = ctx.new_image()

  number.draggable(false)
  -- Deliberately NOT right-justified. texts.pos adds ui_x_res to x when the
  -- right flag is set, because a right-justified text is positioned from the
  -- screen's right edge -- so the number would be drawn off screen. It is
  -- left-justified inside a reserved width instead, which keeps the icon still
  -- as digits come and go.
  number.hide()

  icon.draggable(false)
  icon.repeat_xy(1, 1)
  -- The prim must not size itself to its texture, or the widget scale would
  -- silently do nothing.
  icon.fit(false)
  icon.path(ctx.asset(ASSET_DIR .. ICON_TEXTURE))
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
    local icon_config = config.icon or {}
    local icon_color = icon_config.color or {}

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
    number.text(logic.text())
  end

  -- get_items() can come back without a gil field around a zone; logic keeps
  -- the last good value rather than blanking the widget.
  local function read_gil()
    logic.set_gil(ctx.get_gil())
    apply_text()
  end

  function self.attach(loaded_config, _persist)
    config = loaded_config
    attached = true
    logic.set_config(config)
    apply_style()
    apply_layout()
    read_gil()
    apply_visibility()
  end

  -- The character is gone, so the inventory this was tracking is too: the next
  -- character must load its own before anything is believed.
  function self.detach()
    attached = false
    logic.on_logout()
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
    apply_visibility()
  end

  function self.get_bounds()
    if not pos then
      return nil
    end
    return logic.bounds(pos.x, pos.y, scale)
  end

  -- No arguments is the per-frame tick, and there is nothing to animate.
  -- Otherwise a game event the entry point forwarded: `chunk` carries a raw
  -- packet, which is only parsed for the handful of ids that can move gil --
  -- this fires for every packet the client receives.
  function self.update(event, first, second)
    if event == nil or not attached then
      return
    end

    if event == "chunk" then
      if not logic.wants_chunk(first) then
        return
      end
      local packet = logic.needs_packet(first) and ctx.parse_packet(second) or nil
      if logic.on_chunk(first, packet) then
        read_gil()
      end
      return
    end

    if event == "add item" or event == "remove item" then
      logic.on_item(first)
    end
  end

  function self.destroy()
    number.destroy()
    icon.destroy()
  end

  return self
end

return new
