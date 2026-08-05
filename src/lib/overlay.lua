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

--[[ Layout-mode overlays: the highlight box and name label drawn over each
     widget while `//xh layout` is on.

     Adopted from XIVParty's setup mode, which puts an image over each widget as
     both the drag hit-surface and the visible highlight. Here the hit-testing
     is done against the widgets' own bounds (see lib/layout_mode), so these
     prims are purely feedback — without them the right-click enable toggle
     would have no visible effect at all, since layout mode force-shows every
     widget regardless.

     One box and one label per component, created on first use and reused
     afterwards; core hides them when the mode ends and disposes them on
     unload. ]]

local ENABLED = {
  box = { r = 80, g = 180, b = 250, alpha = 70 },
  label = { r = 255, g = 255, b = 255 },
  suffix = "",
}

local DISABLED = {
  box = { r = 30, g = 30, b = 30, alpha = 150 },
  label = { r = 170, g = 170, b = 170 },
  suffix = " (hidden)",
}

local LABEL_FONT = "sans-serif"
local LABEL_SIZE = 11
local LABEL_INSET = 4

local function new(deps)
  local self = {}
  local overlays = {}

  local function build()
    local box = deps.new_image()
    box.draggable(false)
    -- The texture is a plain white square, stretched to the widget's bounds and
    -- tinted per state, so it must not size itself to the 8x8 source.
    box.fit(false)
    box.repeat_xy(1, 1)
    box.path(deps.texture())
    box.hide()

    local label = deps.new_text()
    label.draggable(false)
    label.bg_visible(false)
    label.bg_alpha(0)
    label.font(LABEL_FONT)
    label.size(LABEL_SIZE)
    label.stroke_width(2)
    label.stroke_color(0, 0, 0)
    label.stroke_alpha(200)
    label.hide()

    return { box = box, label = label }
  end

  local function ensure(name)
    if not overlays[name] then
      overlays[name] = build()
    end
    return overlays[name]
  end

  -- Draws the overlay for `name` over the given bounds. `enabled` is the
  -- component's state in the active layout slot, not whether it is on screen.
  function self.show(name, x, y, width, height, enabled)
    local overlay = ensure(name)
    local style = enabled and ENABLED or DISABLED

    overlay.box.pos(x, y)
    overlay.box.size(width, height)
    overlay.box.color(style.box.r, style.box.g, style.box.b)
    overlay.box.alpha(style.box.alpha)
    overlay.box.show()

    overlay.label.pos(x + LABEL_INSET, y + LABEL_INSET / 2)
    overlay.label.text(name .. style.suffix)
    overlay.label.color(style.label.r, style.label.g, style.label.b)
    overlay.label.show()
  end

  function self.hide(name)
    local overlay = overlays[name]
    if not overlay then
      return
    end
    overlay.box.hide()
    overlay.label.hide()
  end

  function self.destroy_all()
    for _, overlay in pairs(overlays) do
      overlay.box.destroy()
      overlay.label.destroy()
    end
    overlays = {}
  end

  return self
end

return new
