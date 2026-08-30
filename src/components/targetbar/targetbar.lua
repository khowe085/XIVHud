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

--[[ Target Bar - the current target's health, name and distance, on the same
     xiv bar art the party list uses.

     This file owns prims and nothing else: what to draw comes from logic.lua,
     whether to draw comes from the framework. The prims are built once at
     construction rather than on demand - there are only six of them, and a
     widget that builds them lazily has to dispose them somewhere too.

     It runs every frame, which is what shapes the rest of it:

       - the target is read each tick, because the cursor can move between any
         two frames and nothing announces it;
       - the party roster and the player are read on a 200ms gate instead,
         since neither changes at frame rate and get_party() allocates
         eighteen member tables per call;
       - nothing is written to a prim that already holds it. partylist's
         discipline, for the same reason: a settled bar that rewrote every
         value sixty times a second is the only thing here that would cost
         anything. ]]

local new_logic = require("components/targetbar/logic")
local build_defaults = require("components/targetbar/defaults")

local ASSET_DIR = "assets/xiv/wide/"
-- The one chunk this widget reads: the action packet, which reaches it
-- already decoded - the entry point's dispatch runs
-- windower.packets.parse_action once for every component that wants it.
local ACTION_CHUNK = 0x028

local function new(ctx)
  local self = { name = "targetbar", alias = "tb" }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults
  -- Without the resources library there is no spell name or cast time to
  -- show, so logic quietly runs with the cast feature off.
  local logic = new_logic(config, ctx.resources)

  local attached = false
  local save = nil
  local pos = nil
  local scale = 1
  local visible = false
  local geometry = nil
  -- The last value pushed to each prim, per property. An unchanged value is
  -- never written again.
  local written = {}

  --[[ Prims --------------------------------------------------------------- ]]

  local function image(texture)
    local prim = ctx.new_image()
    prim.draggable(false)
    prim.repeat_xy(1, 1)
    -- Never fit: the art is twice its drawn size, and fitting would pin the
    -- prim to the texture and ignore both that and the widget's scale.
    prim.fit(false)
    prim.path(ctx.asset(ASSET_DIR .. texture))
    -- Explicit, not left to the library's defaults: the plate and frame draw
    -- their art untinted, and the fill's tint is written over this per frame.
    prim.color(255, 255, 255)
    prim.alpha(255)
    prim.hide()
    return prim
  end

  local function text()
    local prim = ctx.new_text()
    prim.draggable(false)
    -- No background: the bounds this widget reports make no room for one.
    prim.bg_visible(false)
    prim.bg_alpha(0)
    prim.hide()
    return prim
  end

  -- Creation order is draw order - the Windower libraries expose no depth
  -- control - so each frame has to be built after the fill it sits over.
  local background = image("BarBG.png")
  local fill = image("Bar.png")
  local frame = image("BarFG.png")
  local cast_background = image("CastBG.png")
  local cast_fill = image("CastBar.png")
  local cast_frame = image("CastFG.png")

  local hp_text = text()
  local distance_text = text()
  local name_text = text()
  local cast_name = text()
  -- The one right-justified text here: it grows leftward from the box's right
  -- edge, and its position pre-subtracts the screen width the library adds
  -- back for right-flagged texts.
  cast_name.right_justified(true)

  local texts = { hp = hp_text, distance = distance_text, name = name_text }

  --[[ Writing --------------------------------------------------------------- ]]

  local function push(key, value, apply)
    if written[key] == value then
      return
    end
    written[key] = value
    apply(value)
  end

  local function push_text(prim, key, value)
    push(key .. ".text", value, prim.text)
  end

  local function push_color(prim, key, color)
    color = color or {}
    local red, green, blue = color.r or 255, color.g or 255, color.b or 255
    push(key .. ".color", red * 65536 + green * 256 + blue, function()
      prim.color(red, green, blue)
    end)
    push(key .. ".alpha", color.a or 255, prim.alpha)
  end

  local function want(prim, key, on)
    push(key .. ".visible", on and true or false, function(shown)
      if shown then
        prim.show()
      else
        prim.hide()
      end
    end)
  end

  local function styled(value)
    if type(value) == "table" then
      return value
    end
    return {}
  end

  local function apply_style()
    local color = styled(config.text_color)
    local stroke = styled(config.text_stroke)
    -- Every argument filled in: a Windower setter handed nothing is a getter,
    -- so a mangled config would otherwise leave the prim wearing whatever the
    -- previous character's style put on it.
    for _, prim in pairs(texts) do
      prim.font(config.font or "Arial")
      prim.stroke_width(stroke.width or 0)
      prim.stroke_color(stroke.r or 0, stroke.g or 0, stroke.b or 0)
      -- stroke_alpha, not stroke_transparency: the library reads transparency
      -- as 0..1 and would turn an alpha of 200 into a wildly negative value.
      prim.stroke_alpha(stroke.a or 255)
      -- With a fallback: three nils would turn the setter into a getter.
      prim.color(color.r or 255, color.g or 255, color.b or 255)
      prim.alpha(color.a or 255)
    end

    local stroke_width = stroke.width or 0
    cast_name.font(config.font or "Arial")
    cast_name.stroke_width(stroke_width)
    cast_name.stroke_color(stroke.r or 0, stroke.g or 0, stroke.b or 0)
    cast_name.stroke_alpha(stroke.a or 255)
    cast_name.color(color.r or 255, color.g or 255, color.b or 255)
    cast_name.alpha(color.a or 255)

    -- The cast fill's tint is fixed configuration, never claim state.
    local cast_color = styled(styled(config.cast).fill_color)
    cast_fill.color(cast_color.r or 255, cast_color.g or 255, cast_color.b or 255)
    cast_fill.alpha(cast_color.a or 255)
  end

  --[[ Layout ---------------------------------------------------------------- ]]

  local function apply_layout()
    if not pos then
      geometry = nil
      return
    end

    -- Re-read, not the construction-time value: the cast name's x
    -- pre-subtracts the screen width, so a mid-session resolution change
    -- would otherwise park it off screen by the delta.
    screen_width = ctx.screen()
    geometry = logic.geometry(pos.x, pos.y, scale, screen_width)

    for key, prim in pairs(texts) do
      local segment = geometry.texts[key]
      prim.pos(segment.x, segment.y)
      prim.size(segment.size)
    end

    for _, layer in ipairs({ { background, geometry.frame }, { frame, geometry.frame } }) do
      layer[1].pos(layer[2].x, layer[2].y)
      layer[1].size(layer[2].width, layer[2].height)
    end
    -- The fills' widths belong to the render: only their origins are fixed.
    fill.pos(geometry.fill.x, geometry.fill.y)

    local cast = geometry.cast
    for _, layer in ipairs({ { cast_background, cast.frame }, { cast_frame, cast.frame } }) do
      layer[1].pos(layer[2].x, layer[2].y)
      layer[1].size(layer[2].width, layer[2].height)
    end
    cast_fill.pos(cast.fill.x, cast.fill.y)
    cast_name.pos(cast.name.x, cast.name.y)
    cast_name.size(cast.name.size)

    --[[ Sizes are only written when the value behind them moves, so a layout
         change has to clear that memory or the bar keeps the previous scale's
         fill until the target next takes damage. ]]
    written = {}
  end

  --[[ Drawing --------------------------------------------------------------- ]]

  local function hide_all()
    want(background, "background", false)
    want(fill, "fill", false)
    want(frame, "frame", false)
    want(cast_background, "cast_background", false)
    want(cast_fill, "cast_fill", false)
    want(cast_frame, "cast_frame", false)
    want(cast_name, "cast_name", false)
    for key, prim in pairs(texts) do
      want(prim, key, false)
    end
  end

  local function render()
    if not attached or not pos or not geometry then
      return
    end

    -- The target can change between any two frames, so it is read every one.
    -- Everything else rides the poll below.
    if logic.due_for_poll(ctx.now()) then
      local me = ctx.get_mob_by_target("me")
      local player = ctx.get_player()
      logic.set_self(me and me.id, me and me.model_size, player and player.main_job)
      logic.set_party(ctx.get_party())
    end

    local mob = ctx.get_mob_by_target("t")
    if mob then
      logic.set_target(mob)
    else
      logic.clear_target()
    end

    local plan = logic.tick(ctx.now())
    local drawn = visible and plan.occupied

    want(background, "background", drawn)
    want(frame, "frame", drawn)
    want(fill, "fill", drawn and not plan.fill.hidden)
    if drawn then
      push("fill.width", plan.fill.width, function(width)
        fill.size(geometry.fill.width_at(width), geometry.fill.height)
      end)
      push_color(fill, "fill", plan.fill.color)
    end

    for key, prim in pairs(texts) do
      local segment = plan.texts[key]
      want(prim, key, drawn)
      if drawn then
        push_text(prim, key, segment.text)
        push_color(prim, key, segment.color)
      end
    end

    local casting = visible and plan.cast.active
    want(cast_background, "cast_background", casting)
    want(cast_frame, "cast_frame", casting)
    want(cast_fill, "cast_fill", casting and plan.cast.width > 0)
    want(cast_name, "cast_name", casting)
    if casting then
      push("cast_fill.width", plan.cast.width, function(width)
        cast_fill.size(geometry.cast.fill.width_at(width), geometry.cast.fill.height)
      end)
      push_text(cast_name, "cast_name", plan.cast.name:sub(1, geometry.cast.name.max_chars))
    end
  end

  --[[ The widget contract ---------------------------------------------------- ]]

  function self.attach(loaded_config, persist)
    config = loaded_config
    save = persist
    attached = true
    logic.set_config(config)
    apply_style()
    apply_layout()
  end

  function self.detach()
    attached = false
    save = nil
    --[[ Only the target is dropped. The roster and the player need no clearing
         because attach reopens the poll gate and render polls before it reads
         anything, so the next character's first frame already has its own.

         The target is different: the same mob keeps the same id across a
         logout, and a mule in the same zone can pick it straight back up -
         which the bar would read as a continuously held target and ease from
         health nobody has watched in minutes rather than snapping to what is
         actually there. ]]
    logic.clear_target()
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
  end

  function self.hide()
    visible = false
    hide_all()
  end

  -- The origin set_pos was given, exactly: core clamps the widget on screen by
  -- comparing the two, and layout mode's drag offsets assume it.
  function self.get_bounds()
    if not pos then
      return nil
    end
    return logic.bounds(pos.x, pos.y, scale)
  end

  --[[ No arguments is the per-frame tick. Of the events the entry point
       forwards to every component, exactly one is wanted: the action chunk,
       which feeds the cast tracker and nothing else - no render, no client
       read. Everything else is ignored quietly, which is the contract:
       core.dispatch has no idea who wants what, and a handler that threw
       would be disabled for the rest of the session. ]]
  function self.update(event, id, _original, parsed)
    if event == nil then
      render()
      return
    end
    if event ~= "chunk" or id ~= ACTION_CHUNK or not attached then
      return
    end
    -- Already decoded, by the one dispatch that sees the packet: nil when the
    -- parse failed, which reads the same as nothing having happened.
    if parsed then
      logic.on_action(parsed, ctx.now())
    end
  end

  function self.handle_command(args)
    local reply, changed = logic.command(args)
    -- No re-layout: the only setting here picks a colour scheme, and the next
    -- tick pushes the colour that follows from it. Add one back alongside the
    -- first command that actually moves something.
    if changed and save then
      save()
    end
    return reply
  end

  function self.destroy()
    background.destroy()
    fill.destroy()
    frame.destroy()
    cast_background.destroy()
    cast_fill.destroy()
    cast_frame.destroy()
    cast_name.destroy()
    for _, prim in pairs(texts) do
      prim.destroy()
    end
  end

  return self
end

return new
