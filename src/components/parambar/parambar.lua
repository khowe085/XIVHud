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

--[[ Parameter Bar — the FFXIV parameter bar for FFXI: HP / MP / TP fills with
     their numbers, on the XIVBar art.

     This file owns prims and nothing else; every decision about what to draw
     comes from logic.lua, and every decision about *whether* to draw comes from
     the framework. It creates its prims once at construction so `destroy` can
     always dispose them — XIVBar had no unload path and left its bars on screen.

     All seven prims are created non-draggable: a widget is a group, and the
     framework drags the group from `//hud layout`. ]]

local new_logic = require("components/parambar/logic")
local build_defaults = require("components/parambar/defaults")

local ASSET_DIR = "assets/ffxiv/"
local BARS = { "hp", "mp", "tp" }
local FILL_TEXTURES = { "hp_fg.png", "mp_fg.png", "tp_fg.png" }

-- How long after attaching the player may be re-read, if any vital is still
-- missing by then. The client fills vitals in field by field - in a live client
-- HP landed with MP still zero - and MP does not tick on its own outside
-- resting, so a single seed can leave a bar reading 0 until the player happens
-- to cast. The reading stops early once every vital has a number, but a vital
-- that is legitimately zero - no TP, a dead character, a job with no MP - never
-- reports one, so in practice this ceiling is what usually ends it.
local SEED_SETTLE_SECONDS = 10

local function new(ctx)
  local self = { name = "parambar", alias = "pb" }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults
  local attached = false
  local save = nil
  local logic = new_logic(config)

  local pos = nil
  local scale = 1
  local visible = false
  -- Set while the vitals are still arriving; nil once they have settled.
  local settling_until = nil
  -- Which fills are currently empty; they stay hidden even when the widget as a
  -- whole is shown.
  local empty = { hp = false, mp = false, tp = false }

  local background = ctx.new_image()
  local fills = {}
  local numbers = {}

  local function setup_image(image, texture)
    image.draggable(false)
    image.repeat_xy(1, 1)
    -- The prim must not size itself to its texture: fills are stretched to the
    -- eased width and everything is multiplied by the widget scale.
    image.fit(false)
    image.path(ctx.asset(ASSET_DIR .. texture))
    image.hide()
  end

  -- Tracked so a compact-mode switch is the only thing that re-points the
  -- background texture.
  local background_texture = logic.metrics().background
  setup_image(background, background_texture)
  for index, texture in ipairs(FILL_TEXTURES) do
    fills[index] = ctx.new_image()
    setup_image(fills[index], texture)
  end
  for index = 1, #BARS do
    local number = ctx.new_text()
    number.draggable(false)
    number.bg_visible(false)
    number.bg_alpha(0)
    -- Deliberately NOT right-justified. texts.pos adds ui_x_res to x when the
    -- right flag is set, because a right-justified text is positioned from the
    -- screen's right edge -- so these numbers would be drawn off screen. The
    -- offsets below come from XIVBar, whose own right_justified() call passes
    -- no argument and is therefore a getter, so it renders left-justified and
    -- its offsets are tuned for that.
    number.hide()
    numbers[index] = number
  end

  local function apply_visibility()
    if not visible then
      background.hide()
      for index = 1, #BARS do
        fills[index].hide()
        numbers[index].hide()
      end
      return
    end

    background.show()
    for index, bar in ipairs(BARS) do
      numbers[index].show()
      if empty[bar] then
        fills[index].hide()
      else
        fills[index].show()
      end
    end
  end

  local function apply_text_style()
    local color = config.text_color or {}
    local stroke = config.text_stroke or {}
    for index = 1, #BARS do
      local number = numbers[index]
      number.font(config.font)
      number.color(color.r, color.g, color.b)
      number.alpha(color.a or 255)
      number.stroke_width(stroke.width)
      number.stroke_color(stroke.r, stroke.g, stroke.b)
      number.stroke_alpha(stroke.a)
    end
  end

  -- Pushes the frame geometry to every prim. Called whenever the position, the
  -- scale or a metric changes; render() recomputes it only for a frame in which
  -- a bar is actually being redrawn.
  local function apply_layout()
    logic.invalidate()
    if not pos then
      return
    end

    local metrics = logic.metrics()
    if metrics.background ~= background_texture then
      background_texture = metrics.background
      background.path(ctx.asset(ASSET_DIR .. metrics.background))
    end

    local geometry = logic.geometry(pos.x, pos.y, scale)
    background.pos(geometry.background.x, geometry.background.y)
    background.size(geometry.background.width, geometry.background.height)

    for index = 1, #BARS do
      fills[index].pos(geometry.bars[index].x, geometry.bars[index].y)
      numbers[index].pos(geometry.texts[index].x, geometry.texts[index].y)
      numbers[index].size(geometry.font_size)
    end
  end

  -- One frame of the render plan. Only bars the plan marks dirty are touched,
  -- so a settled HUD costs nothing.
  local function render()
    if not attached or not pos then
      return
    end

    local plan = logic.tick()
    local geometry

    for index, bar in ipairs(BARS) do
      local entry = plan[bar]
      if entry.dirty then
        geometry = geometry or logic.geometry(pos.x, pos.y, scale)
        empty[bar] = entry.hidden
        fills[index].size(geometry.fill_width(entry.width), geometry.fill_height)
        fills[index].alpha(entry.alpha)
        numbers[index].text(entry.text)
        numbers[index].color(entry.color.r, entry.color.g, entry.color.b)
        if visible then
          if entry.hidden then
            fills[index].hide()
          else
            fills[index].show()
          end
        end
      end
    end
  end

  -- get_player() can return nil around zone-in. Re-seeding from nothing would
  -- zero every vital, and the change events only fire on an actual change — so
  -- a character standing at full HP would read 0 until something moved.
  local function seed_from_player()
    local player = ctx.get_player()
    if player and player.vitals then
      logic.seed(player.vitals)
    end
  end

  -- Re-read the player each frame until the vitals have had time to arrive in
  -- full, then leave it to the change events. Only the gaps are filled, so a
  -- value an event delivered mid-window is never walked over.
  local function fill_while_settling()
    if not settling_until then
      return
    end
    if not logic.awaiting_vitals() or ctx.now() >= settling_until then
      settling_until = nil
      return
    end
    local player = ctx.get_player()
    if player and player.vitals then
      logic.fill_missing(player.vitals)
    end
  end

  -- The character's config has been loaded; `persist` writes it back.
  function self.attach(loaded_config, persist)
    config = loaded_config
    save = persist
    attached = true
    logic.set_config(config)
    apply_text_style()
    apply_layout()
    settling_until = ctx.now() + SEED_SETTLE_SECONDS
    seed_from_player()
  end

  function self.detach()
    attached = false
    save = nil
    settling_until = nil
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

  -- No arguments is the per-frame tick; otherwise a game event the entry point
  -- forwarded. Vitals arrive as two independent streams, so a status change
  -- re-seeds both from the player at once (XIVBar let them drift apart).
  function self.update(event, value)
    if event == nil then
      fill_while_settling()
      render()
      return
    end
    if event == "status" then
      seed_from_player()
    else
      logic.set_vital(event, value)
    end
  end

  function self.handle_command(args)
    local message, changed = logic.command(args)
    if changed then
      apply_text_style()
      apply_layout()
      if save then
        save()
      end
    end
    return message
  end

  function self.destroy()
    background.destroy()
    for index = 1, #BARS do
      fills[index].destroy()
      numbers[index].destroy()
    end
  end

  return self
end

return new
