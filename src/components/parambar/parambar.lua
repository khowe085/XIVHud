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
-- The action packet, as the entry point dispatches it already parsed.
local ACTION_CHUNK = 0x028
local BARS = { "hp", "mp", "tp" }
local FILL_TEXTURES = { "hp_fg.png", "mp_fg.png", "tp_fg.png" }

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
  -- Which fills are currently empty; they stay hidden even when the widget as a
  -- whole is shown.
  local empty = { hp = false, mp = false, tp = false }

  local background = ctx.new_image()
  local fills = {}
  local numbers = {}
  -- The accuracy row: one text, built after the numbers below so it sits at
  -- the end of the prim list rather than in front of the bars it reports on.
  -- It is text and nothing else - no button, and so no mouse handler.
  local readout

  -- The frame clock. Absent only in a harness; a window that cannot age is
  -- better than a widget that throws sixty times a second.
  local function now()
    return ctx.now ~= nil and ctx.now() or 0
  end

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
  readout = ctx.new_text()
  readout.draggable(false)
  readout.bg_visible(false)
  readout.bg_alpha(0)
  readout.hide()

  local function apply_visibility()
    if not visible then
      background.hide()
      for index = 1, #BARS do
        fills[index].hide()
        numbers[index].hide()
      end
      readout.hide()
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
    -- The row is a setting of its own on top of the widget's visibility.
    if logic.accuracy_enabled() then
      readout.show()
    else
      readout.hide()
    end
  end

  local function apply_text_style()
    local color = config.text_color or {}
    local stroke = config.text_stroke or {}
    -- The row takes the numbers' colour and stroke; only its size differs,
    -- and that comes from the geometry with everything else scaled.
    local texts = { numbers[1], numbers[2], numbers[3], readout }
    for _, text in ipairs(texts) do
      text.font(config.font)
      text.color(color.r, color.g, color.b)
      text.alpha(color.a or 255)
      text.stroke_width(stroke.width)
      text.stroke_color(stroke.r, stroke.g, stroke.b)
      text.stroke_alpha(stroke.a)
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

    if geometry.accuracy then
      readout.pos(geometry.accuracy.x, geometry.accuracy.y)
      readout.size(geometry.accuracy.font_size)
    end
  end

  -- One frame of the render plan. Only bars the plan marks dirty are touched,
  -- so a settled HUD costs nothing.
  local function render()
    if not attached or not pos then
      return
    end

    local plan = logic.tick(now())
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

    -- The line moves only when a swing lands or ages out of the window.
    if plan.accuracy.dirty then
      readout.text(plan.accuracy.text)
    end
  end

  --[[ Read every frame. `ctx.get_player` is lib/player's, so this costs a real
       client read only once per interval - and the change events re-open that
       read rather than carrying a value of their own, so what comes back is
       the client's own numbers and the widget hears no event itself.

       get_player() can return nil around zone-in, and the client fills the
       player in field by field, so a missing vitals table leaves the bars where
       they are: pushing nothing would zero every one of them. ]]
  local function read_player()
    local player = ctx.get_player()
    if player and player.vitals then
      logic.set_vitals(player.vitals)
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
    -- No read here: the next tick takes one, as every tick does.
  end

  function self.detach()
    attached = false
    save = nil
    -- The window is this character's. speedcheck's rule: a detach forgets,
    -- so a logout cannot carry one character's numbers into the next.
    logic.reset_accuracy()
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

  --[[ Only the per-frame tick does anything. The vitals events reach
       `lib/player`, which reconciles them against the client and hands the
       result back through `ctx.get_player` - so a forwarded event needs no
       handling here, and a status change needs no special case: the service
       drops its interval on one, and the next tick sees the fresh numbers. ]]
  function self.update(event, first, _second, parsed)
    --[[ The action packet, already decoded by the entry point for the cast
         bar and the skillchain engine - there is no second parse here, and
         `parsed` is nil where that one failed. Only the player's own swings
         count, so the packet is worth nothing without a player to compare
         against; `ctx.get_player` is the service's, so asking on a packet
         costs no client read of its own. ]]
    if event == "chunk" then
      if first == ACTION_CHUNK and parsed ~= nil then
        local player = ctx.get_player()
        logic.on_action(parsed, player and player.id or nil, now())
      end
      return
    end
    if event ~= nil then
      return
    end
    if attached then
      read_player()
    end
    render()
  end

  function self.handle_command(args)
    local message, changed = logic.command(args)
    if changed then
      apply_text_style()
      apply_layout()
      -- The accuracy verbs can raise or drop the row, which is a visibility
      -- change as well as a layout one.
      apply_visibility()
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
    readout.destroy()
  end

  return self
end

return new
