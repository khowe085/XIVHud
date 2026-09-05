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

--[[ Exp Bar - the FFXIV experience bar for FFXI: one filling bar with a status
     line above it.

     This file owns prims, the ctx reads and nothing else; what to draw comes
     from logic.lua and whether to draw comes from the framework. All three
     prims are built once at construction so `destroy` can always dispose them -
     neither reference addon has an unload path, and both leave their bars on
     screen after a reload.

     The client answers none of what the bar draws, so the component seeds
     itself from the last 0x061 and 0x063 the client sent: `attach` happens on
     login and on every slot switch, and nothing re-sends either packet on
     request. ]]

local new_logic = require("components/expbar/logic")
local build_defaults = require("components/expbar/defaults")

-- barfiller's own art, with Morath86's notice beside it.
local BACKGROUND_TEXTURE = "assets/barfiller/bar_bg.png"
local FILL_TEXTURE = "assets/barfiller/bar_fg.png"

-- XivParty's job glyphs, drawn bare: they are gold with a dark outline, so
-- they need none of the backing the party list puts under its own.
local JOB_ICON_DIR = "assets/xiv/jobIcons/"

-- The two packets that carry state rather than a change, and so are worth
-- asking the client for at attach.
local CHAR_UPDATE = 0x063
local SEEDED_PACKETS = { 0x061, CHAR_UPDATE }

local function new(ctx)
  local self = { name = "expbar", alias = "eb" }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults
  local attached = false
  local logic = new_logic(config)

  local pos = nil
  local scale = 1
  local visible = false
  -- Whether the fill is currently empty; it stays hidden even when the widget
  -- as a whole is shown.
  local empty = false
  -- Who the numbers belong to. Everything the logic holds is one character's,
  -- and this is what says when that character has changed.
  local character = nil
  -- The last string pushed to the prim, so a settled header costs one string
  -- comparison a frame rather than a prim write.
  local drawn_header = nil
  -- Likewise for the glyph: its path only changes on a job change.
  local drawn_job = nil
  -- Whether the job has art at all; a job without it hides the whole stack.
  local job_shown = false

  local header = ctx.new_text()
  local glyph = ctx.new_image()
  local background = ctx.new_image()
  local fill = ctx.new_image()

  header.draggable(false)
  header.bg_visible(false)
  header.bg_alpha(0)
  -- Deliberately NOT right-justified: texts.pos adds ui_x_res to x when the
  -- right flag is set, so the line would be drawn off screen.
  header.hide()

  local function setup_image(image, texture)
    image.draggable(false)
    image.repeat_xy(1, 1)
    -- The prim must not size itself to its texture: the fill is stretched to
    -- the eased width, and everything is multiplied by the widget scale.
    image.fit(false)
    if texture ~= nil then
      image.path(ctx.asset(texture))
    end
    image.hide()
  end

  -- The glyph's path is pushed per job; there is none to point at yet.
  setup_image(glyph, nil)
  setup_image(background, BACKGROUND_TEXTURE)
  setup_image(fill, FILL_TEXTURE)

  local function apply_visibility()
    if not visible then
      header.hide()
      glyph.hide()
      background.hide()
      fill.hide()
      return
    end

    header.show()
    if job_shown then
      glyph.show()
    else
      glyph.hide()
    end
    background.show()
    if empty then
      fill.hide()
    else
      fill.show()
    end
  end

  local function apply_text_style()
    local color = config.text_color or {}
    local stroke = config.text_stroke or {}
    header.font(config.font)
    header.color(color.r, color.g, color.b)
    header.alpha(color.a or 255)
    header.stroke_width(stroke.width)
    header.stroke_color(stroke.r, stroke.g, stroke.b)
    header.stroke_alpha(stroke.a)
  end

  -- Pushes the frame geometry to every prim. The fill's width is not set here:
  -- only a frame that redraws it knows how much of the bar is filled, and
  -- `invalidate` is what makes the next frame one of those.
  local function apply_layout()
    logic.invalidate()
    if not pos then
      return
    end

    local geometry = logic.geometry(pos.x, pos.y, scale)
    header.pos(geometry.header.x, geometry.header.y)
    header.size(geometry.font_size)
    glyph.pos(geometry.icon.x, geometry.icon.y)
    glyph.size(geometry.icon.size, geometry.icon.size)
    background.pos(geometry.background.x, geometry.background.y)
    background.size(geometry.background.width, geometry.background.height)
    fill.pos(geometry.fill.x, geometry.fill.y)
  end

  -- One frame of the render plan. Only a bar that moved is written to.
  local function render()
    if not pos then
      return
    end

    local plan = logic.tick(ctx.now())

    if plan.header ~= drawn_header then
      drawn_header = plan.header
      header.text(plan.header)
    end

    --[[ The glyph only changes on a job change, so its path is compared before
         being pushed - a job holds for hours and this runs every frame. Nil is
         a client that has not named a job yet, and hides it. ]]
    local job = logic.job_icon()
    local name = job and job.name or nil
    if name ~= drawn_job then
      drawn_job = name
      job_shown = name ~= nil
      if name ~= nil then
        glyph.path(ctx.asset(JOB_ICON_DIR .. name .. ".png"))
      end
      if visible then
        apply_visibility()
      end
    end

    if not plan.dirty then
      return
    end

    local geometry = logic.geometry(pos.x, pos.y, scale)
    empty = plan.hidden
    fill.size(geometry.fill_width(plan.width), geometry.fill.height)
    fill.color(plan.color.r, plan.color.g, plan.color.b)
    if visible then
      if empty then
        fill.hide()
      else
        fill.show()
      end
    end
  end

  -- What the client last sent, for the two packets that describe a state
  -- rather than a change. Either may never have arrived.
  local function seed()
    for _, id in ipairs(SEEDED_PACKETS) do
      local data = ctx.last_incoming(id)
      if data then
        logic.on_packet(id, ctx.parse_packet(data), ctx.now())
      end
    end
  end

  --[[ Read every frame. `ctx.get_player` is lib/player's, so this costs a real
       client read only once per interval; the job pair, the job points and the
       name are all this widget wants from it. ]]
  local function read_player()
    logic.set_player(ctx.get_player())
  end

  --[[ Core attaches once it has scoped a character, so this is the one moment
       that happens per character rather than per frame - and the name it can
       read here is what says whether the numbers already held are still theirs.

       Only a CHANGE of character clears them. Everything the logic holds
       belongs to one player, so a second must not be drawn with the first's
       merits and rate; but `//hud slot` and `//hud reset expbar` re-attach the
       same character, and clearing there would put a zero on screen that
       nothing could fill back in - the client sends these numbers once, at
       login, and `last_incoming` cannot reliably re-read them (0x063 is
       multiplexed over five orders, so the merit seed only lands if order 2
       happened to be the last one sent).

       The seed goes with the reset, in that same branch, and must: 0x061 is
       not resent per kill - which is the whole reason the 0x02D deltas exist -
       so re-applying it on a re-attach of the same character would rewind the
       bar to whatever it read at login and throw away everything earned
       since. ]]
  function self.attach(loaded_config)
    config = loaded_config
    attached = true
    logic.set_config(config)

    local player = ctx.get_player()
    local name = player and player.name or nil
    if name ~= character then
      character = name
      logic.reset()
      seed()
    end
    apply_text_style()
    apply_layout()
  end

  function self.detach()
    attached = false
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

  --[[ The per-frame tick draws; a chunk is read only for the three ids the
       logic asks for. Packets are ignored while detached: nothing is on screen
       then, and the points they carry belong to whoever logs in next. 0x063
       arrives already parsed - three components read it, so the entry point
       decodes it once and hands the table over as `third`; the other two ids
       are this widget's alone and are parsed here. ]]
  function self.update(event, first, second, third)
    if not attached then
      return
    end

    if event == nil then
      read_player()
      render()
      return
    end

    if event == "chunk" and logic.wants_chunk(first) then
      -- Written as a branch, not `and/or`: a pre-parse that FAILED is a nil
      -- `third`, and the idiom would fall through to parsing the same bytes
      -- a second time with the library that has just failed on them.
      local packet
      if first == CHAR_UPDATE then
        packet = third
      else
        packet = ctx.parse_packet(second)
      end
      logic.on_packet(first, packet, ctx.now())
    end
  end

  --[[ `attach`'s second argument is deliberately dropped: no verb here writes
       config, so `logic.command` answers `changed = false` every time and there
       is nothing to persist. The parenthesis discards that second return rather
       than passing it on as a message. A verb that DOES write a setting has to
       keep `persist` and call it, the way parambar and the target bar do. ]]
  function self.handle_command(args)
    return (logic.command(args))
  end

  function self.destroy()
    header.destroy()
    glyph.destroy()
    background.destroy()
    fill.destroy()
  end

  return self
end

return new
