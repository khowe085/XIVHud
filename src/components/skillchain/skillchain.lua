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

--[[ The skillchain window indicator: one bar that shows the resonation on
     your target - red and thin while the next step is not yet allowed,
     green and thick while the window is open, shrinking as it closes. It
     was one of the crossbar's anchors until 2026-09-06 (Kevin): with a
     second bar drawing per-slot chain results off the same engine, the
     window bar became a component of its own so the two bars do not each
     carry one. Both bars keep their per-slot chain borders.

     It receives no packets and reads no client: the engine is the action
     service's (lib/skillchain, fed by the entry point), and this asks it
     once a frame for the window and draws the plan. The colours and
     opacity are its config; on/off is the framework's `//hud show|hide
     skillchain`. Without the service it draws nothing. ]]

local INDICATOR_WIDTH, INDICATOR_HEIGHT = 604, 14
-- The shipped colours: the fallback when the config's are hand-broken.
local WAITING_COLOR = { r = 237, g = 28, b = 36 }
local OPEN_COLOR = { r = 15, g = 205, b = 5 }
local OPACITY = 220
local BG_ALPHA = 150
--[[ Where the crossbar seeded it: 40px above its WXHB pair at the shipped
     geometry, whose bars are 180 tall with the main bar's origin 211 up
     from the screen bottom - so the indicator sits 431 up. A placement
     policy, written down here rather than read off the crossbar, which no
     component may reach. ]]
local BOTTOM_LIFT = 431

local function new(ctx)
  local self = { name = "skillchain", alias = "sc" }

  local screen_width, screen_height = ctx.screen()
  screen_width = screen_width or 0
  screen_height = screen_height or 0
  self.defaults = {
    opacity = OPACITY,
    waiting_color = { r = WAITING_COLOR.r, g = WAITING_COLOR.g, b = WAITING_COLOR.b },
    open_color = { r = OPEN_COLOR.r, g = OPEN_COLOR.g, b = OPEN_COLOR.b },
    layout = {
      pos = {
        x = math.max(0, math.floor((screen_width - INDICATOR_WIDTH) / 2)),
        y = math.max(0, screen_height - BOTTOM_LIFT),
      },
      scale = 1,
      visible = true,
    },
  }
  local config = self.defaults

  local engine = ctx.actions ~= nil and ctx.actions.skillchain or nil

  local pos = nil
  local scale = 1
  local visible = false
  local preview = false

  -- A black backdrop and a centre-anchored fill, both the addon's own white
  -- square tinted at draw time (fill after bg, so it draws on top).
  local prims = nil
  if ctx.new_image ~= nil and ctx.asset ~= nil then
    local function image()
      local prim = ctx.new_image()
      prim.draggable(false)
      prim.repeat_xy(1, 1)
      prim.fit(false)
      prim.path(ctx.asset("assets/own/indicator.png"))
      prim.color(255, 255, 255)
      prim.hide()
      return prim
    end
    prims = { bg = image(), fill = image() }
    prims.bg.color(0, 0, 0)
    prims.bg.alpha(BG_ALPHA)
  end

  --[[ The change-gate: the fill and bg geometry last pushed, the colour
       state, and visibility. Wiped when the anchor moves or scales, so the
       next tick reapplies everything against the new origin; NOT wiped by
       a hide, since hiding a prim does not make it forget where it is. ]]
  local written = { fill = {}, bg = {} }

  local function reset_written()
    written = { fill = {}, bg = {} }
  end

  local function push_rect(prim, cache, x, y, width, height)
    if cache.x ~= x or cache.y ~= y then
      cache.x, cache.y = x, y
      prim.pos(x, y)
    end
    if cache.w ~= width or cache.h ~= height then
      cache.w, cache.h = width, height
      prim.size(width, height)
    end
  end

  local function take_down()
    if prims == nil or written.visible == false then
      return
    end
    written.visible = false
    written.state = nil
    prims.bg.hide()
    prims.fill.hide()
  end

  --[[ Draws (or hides) the bar for this tick. Colour and opacity land only
       on a state flip (upstream's own gate); geometry lands whenever it
       moves, which while a window runs is every frame - that IS the
       animation. In preview the full open-state bar stands in, so layout
       mode has the real footprint to drag whatever the live chain state. ]]
  local function draw()
    if prims == nil then
      return
    end
    local plan = nil
    if visible and pos ~= nil and engine ~= nil then
      if preview then
        plan = engine.indicator_plan(0, 7)
      else
        plan = engine.indicator_plan(engine.window())
      end
    end
    if plan == nil then
      take_down()
      return
    end
    if written.state ~= plan.state then
      written.state = plan.state
      local color = plan.state == "waiting" and WAITING_COLOR or OPEN_COLOR
      local tuned = plan.state == "waiting" and config.waiting_color or config.open_color
      if type(tuned) ~= "table" then
        tuned = color
      end
      prims.fill.color(tuned.r or color.r, tuned.g or color.g, tuned.b or color.b)
      prims.fill.alpha(type(config.opacity) == "number" and config.opacity or OPACITY)
    end
    local fill, bg = plan.fill, plan.bg
    push_rect(
      prims.fill,
      written.fill,
      pos.x + fill.x * scale,
      pos.y + fill.y * scale,
      fill.width * scale,
      fill.height * scale
    )
    push_rect(prims.bg, written.bg, pos.x + bg.x * scale, pos.y + bg.y * scale, bg.width * scale, bg.height * scale)
    if written.visible ~= true then
      written.visible = true
      prims.bg.show()
      prims.fill.show()
    end
  end

  function self.attach(new_config)
    config = type(new_config) == "table" and new_config or self.defaults
    written.state = nil
  end

  function self.detach()
    take_down()
  end

  function self.set_pos(x, y)
    if pos ~= nil and pos.x == x and pos.y == y then
      return
    end
    pos = { x = x, y = y }
    reset_written()
  end

  function self.set_scale(value)
    if scale == value then
      return
    end
    scale = value
    reset_written()
  end

  function self.set_preview(on)
    local wanted = on == true
    if wanted == preview then
      return
    end
    preview = wanted
    draw()
  end

  function self.show()
    visible = true
  end

  function self.hide()
    visible = false
    take_down()
  end

  -- The open bar's box at the origin set_pos was given, whatever is drawn.
  function self.get_bounds()
    if pos == nil then
      return nil
    end
    return pos.x, pos.y, INDICATOR_WIDTH * scale, INDICATOR_HEIGHT * scale
  end

  function self.update(event)
    if event == nil then
      draw()
    end
  end

  function self.destroy()
    if prims ~= nil then
      prims.bg.destroy()
      prims.fill.destroy()
      prims = nil
    end
  end

  return self
end

return new
