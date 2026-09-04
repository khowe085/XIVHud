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

--[[ Status bar - the FFXIV status display for FFXI's own buffs and debuffs:
     the player's active effects as icon grids with the remaining time under
     each, on three independently placed bars.

     This file owns the prims and every ctx read; logic.lua decides what each
     bar draws and where. One component over three anchors (`bar1`, `bar2`,
     `bar3`), each a pool of icon and timer prims grown on demand up to the
     bar's capacity and merely hidden after that. Whether a bar is on screen
     is the framework's per-anchor `visible` - core pushes each bar's switch
     through show/hide and force-shows every one in layout mode, so a bar
     switched off is still draggable without this knowing why.

     Presence is read off ctx.get_player() every tick (the service caches the
     client read and refreshes it on every buff event); the expiries arrive
     on the 0x063 chunk, decoded here from the raw bytes since nothing else
     reads it. A tick that changes nothing pushes nothing: each cell remembers
     what it last drew, so a settled bar costs a plan and a comparison. ]]

local new_logic = require("components/statusbar/logic")
local build_defaults = require("components/statusbar/defaults")
local packets = require("components/statusbar/packets")

local ANCHORS = { "bar1", "bar2", "bar3" }

-- The party list's buff art, 32px, by buff id.
local ICON_DIR = "assets/xiv/buffIcons/"

local TIMER_FONT = "Arial"
local TIMER_COLOR = { r = 255, g = 255, b = 255, a = 255 }
local TIMER_STROKE = { r = 0, g = 0, b = 0, a = 255, width = 2 }

local function new(ctx)
  local self = { name = ctx.name or "statusbar", alias = "sb" }

  local screen_width, screen_height = (ctx.screen or function() end)()
  self.defaults = build_defaults(screen_width, screen_height)

  -- The wall clock, which the packet's timestamps count in; without one
  -- every expiry is in the past and no timer is drawn, the crossbar's rule.
  local clock = ctx.time or function()
    return 0
  end
  local logic = new_logic({ config = self.defaults, resources = ctx.resources or {} })

  local attached = false
  local save = nil

  --[[ The plan is only rebuilt when something it reads could have changed:
       the player's buff list is a table the service hands out unchanged for
       an interval, the timer text moves at most once a second, and a packet,
       a command or a placement marks it stale. A settled bar costs one clock
       read and three comparisons a frame. ]]
  local last_buffs, last_second = nil, nil
  local stale = true
  -- Whose expiries the packet map holds: the character the client named
  -- when the packet landed. Core attaches over a character switch without a
  -- logout event, and buff ids are the same on every character, so an attach
  -- for a DIFFERENT name drops them; one for the same name (a slot switch,
  -- or the attach a packet arrived just ahead of) keeps them, since nothing
  -- re-sends the packet.
  local expiries_of = nil

  local bars = {}
  for _, anchor in ipairs(ANCHORS) do
    bars[anchor] = { pos = nil, scale = 1, visible = false, icons = {}, texts = {}, drawn = {} }
  end

  --[[ Core fans a placement out over every anchor on every apply, and layout
       mode drags one of them -- so a name that is not ours has to cost
       nothing rather than crash the apply. ]]
  local function bar_at(anchor)
    return anchor ~= nil and bars[anchor] or nil
  end

  local function drawing(bar)
    return attached and bar.visible and bar.pos ~= nil
  end

  --[[ Prims ---------------------------------------------------------------- ]]

  local function icon_prim(bar, index)
    local prim = bar.icons[index]
    if not prim then
      prim = ctx.new_image()
      prim.draggable(false)
      prim.repeat_xy(1, 1)
      -- The prim must not size itself to its texture, or the scale would
      -- silently do nothing.
      prim.fit(false)
      prim.hide()
      bar.icons[index] = prim
    end
    return prim
  end

  local function text_prim(bar, index)
    local prim = bar.texts[index]
    if not prim then
      prim = ctx.new_text()
      prim.draggable(false)
      prim.bg_visible(false)
      prim.bg_alpha(0)
      prim.font(TIMER_FONT)
      prim.color(TIMER_COLOR.r, TIMER_COLOR.g, TIMER_COLOR.b)
      prim.alpha(TIMER_COLOR.a)
      prim.stroke_width(TIMER_STROKE.width)
      prim.stroke_color(TIMER_STROKE.r, TIMER_STROKE.g, TIMER_STROKE.b)
      prim.stroke_alpha(TIMER_STROKE.a)
      -- Deliberately NOT right-justified: texts.pos adds the screen width to
      -- x when the right flag is set, which would put these off screen.
      prim.hide()
      bar.texts[index] = prim
    end
    return prim
  end

  -- Hide everything a bar drew and forget it, so the next paint pushes all.
  -- `pairs`, not `ipairs`: a timer prim exists only where a cell had a timer,
  -- so the text pool is sparse whenever an untimed buff sorts ahead of a
  -- timed one, and `ipairs` would stop at the gap with a timer still up.
  local function blank(bar)
    -- Already blank: the tick keeps running while a bar is hidden, and a
    -- re-hide per prim per frame is exactly the cost this file promises not
    -- to pay.
    if next(bar.drawn) == nil then
      return
    end
    for _, prim in pairs(bar.icons) do
      prim.hide()
    end
    for _, prim in pairs(bar.texts) do
      prim.hide()
    end
    bar.drawn = {}
  end

  -- One cell against what it last drew; only the fields that moved are pushed.
  local function draw_cell(bar, index, cell)
    local last = bar.drawn[index]
    if not last then
      last = {}
      bar.drawn[index] = last
    end

    local icon = icon_prim(bar, index)
    if last.id ~= cell.id then
      icon.path(ctx.asset(ICON_DIR .. tostring(cell.id) .. ".png"))
      last.id = cell.id
    end
    if last.x ~= cell.x or last.y ~= cell.y then
      icon.pos(cell.x, cell.y)
      last.x, last.y = cell.x, cell.y
    end
    if last.size ~= cell.size then
      icon.size(cell.size, cell.size)
      last.size = cell.size
    end
    if not last.icon_shown then
      icon.show()
      last.icon_shown = true
    end

    if cell.timer then
      local text = text_prim(bar, index)
      if last.timer ~= cell.timer then
        text.text(cell.timer)
        last.timer = cell.timer
      end
      if last.text_x ~= cell.text_x or last.text_y ~= cell.text_y then
        text.pos(cell.text_x, cell.text_y)
        last.text_x, last.text_y = cell.text_x, cell.text_y
      end
      if last.text_size ~= cell.text_size then
        text.size(cell.text_size)
        last.text_size = cell.text_size
      end
      if not last.text_shown then
        text.show()
        last.text_shown = true
      end
    elseif last.text_shown then
      bar.texts[index].hide()
      last.text_shown = false
      last.timer = nil
    end
  end

  local function paint(anchor)
    local bar = bars[anchor]
    if not drawing(bar) then
      blank(bar)
      return
    end

    local geometry = logic.geometry(anchor, bar.pos.x, bar.pos.y, bar.scale)
    for index, cell in ipairs(geometry.cells) do
      draw_cell(bar, index, cell)
    end
    -- The cells past the end: hidden, and forgotten so a return repaints.
    for index = #geometry.cells + 1, #bar.drawn do
      local last = bar.drawn[index]
      if last then
        if last.icon_shown then
          bar.icons[index].hide()
        end
        if last.text_shown then
          bar.texts[index].hide()
        end
        bar.drawn[index] = nil
      end
    end
  end

  local function paint_all()
    for _, anchor in ipairs(ANCHORS) do
      paint(anchor)
    end
  end

  --[[ The contract ------------------------------------------------------- ]]

  function self.anchors()
    return ANCHORS
  end

  --[[ A config file is code and is hand-editable, and `//hud copy` imports
       another character's, so a bar entry can be any shape at all by the time
       it reaches here. Anything unusable is replaced with a FRESH copy of the
       defaults rather than indexed - fresh, and written back into the config,
       so a later command's edit lands in a table that `save()` serialises
       rather than in the defaults. ]]
  function self.attach(loaded_config, persist)
    save = persist
    local config = type(loaded_config) == "table" and loaded_config or {}
    if type(config.bars) ~= "table" then
      config.bars = {}
    end
    local seed = nil
    for _, anchor in ipairs(ANCHORS) do
      if type(config.bars[anchor]) ~= "table" then
        seed = seed or build_defaults(screen_width, screen_height)
        config.bars[anchor] = seed.bars[anchor]
      end
    end
    local player = ctx.get_player()
    local name = player and player.name or nil
    if name ~= expiries_of then
      logic.apply_durations({})
      expiries_of = name
    end
    logic.set_config(config)
    attached = true
    stale = true
    paint_all()
  end

  -- The character is gone, and so are the expiries the client told us about
  -- them: the next character's bars start dark until their own packet lands.
  function self.detach()
    attached = false
    save = nil
    stale = true
    expiries_of = nil
    logic.apply_durations({})
    logic.set_buffs(nil)
    for _, anchor in ipairs(ANCHORS) do
      blank(bars[anchor])
    end
  end

  function self.set_pos(x, y, anchor)
    local bar = bar_at(anchor)
    if not bar then
      return
    end
    bar.pos = { x = x, y = y }
    paint(anchor)
  end

  function self.set_scale(scale, anchor)
    local bar = bar_at(anchor)
    if not bar then
      return
    end
    bar.scale = scale
    paint(anchor)
  end

  function self.set_preview(on)
    logic.set_preview(on)
    paint_all()
  end

  --[[ Core sends the widget's own switch with no anchor and one bar's with
       its name; a whole-widget show is also what layout mode force-shows with,
       so it has to bring back every bar a per-anchor hide took down. A show
       does not paint: core's apply sends the bare show first and restates
       each anchor after it, so a bar that is off is shown and hidden inside
       one apply, and painting in between would grow its prims for nothing.
       The next tick paints what is still shown; a hide is immediate. ]]
  function self.show(anchor)
    if anchor ~= nil then
      local bar = bar_at(anchor)
      if bar then
        bar.visible = true
        stale = true
      end
      return
    end
    for _, name in ipairs(ANCHORS) do
      bars[name].visible = true
    end
    stale = true
  end

  function self.hide(anchor)
    if anchor ~= nil then
      local bar = bar_at(anchor)
      if bar then
        bar.visible = false
        paint(anchor)
      end
      return
    end
    for _, name in ipairs(ANCHORS) do
      bars[name].visible = false
    end
    paint_all()
  end

  -- The whole shape from the origin set_pos gave, full or empty.
  function self.get_bounds(anchor)
    local bar = bar_at(anchor)
    if not bar or not bar.pos then
      return nil
    end
    return logic.bounds(anchor, bar.pos.x, bar.pos.y, bar.scale)
  end

  -- No arguments is the per-frame tick: read the player, move the clock,
  -- repaint what changed. Otherwise a game event the entry point forwarded;
  -- only the 0x063 chunk matters, and only its order 9. The chunk is kept
  -- whether or not this is attached yet: nothing re-sends it until a buff
  -- changes, and core dispatches it only for a character already scoped, so
  -- one landing just ahead of the attach is that character's.
  function self.update(event, first, second)
    if event == "chunk" and first == packets.BUFF_DURATIONS then
      local parsed = packets.parse_buff_durations(second, clock())
      if parsed then
        logic.apply_durations(parsed)
        local player = ctx.get_player()
        expiries_of = player and player.name or nil
        stale = true
      end
      return
    end
    if event == nil and attached then
      local player = ctx.get_player()
      local buffs = player and player.buffs or nil
      local now = clock()
      local this_second = math.floor(now)
      if not stale and buffs == last_buffs and this_second == last_second then
        return
      end
      last_buffs, last_second, stale = buffs, this_second, false
      logic.set_buffs(buffs)
      logic.set_time(now)
      paint_all()
    end
  end

  function self.handle_command(args)
    local lines, changed = logic.command(args)
    if changed then
      if save then
        save()
      end
      paint_all()
    end
    return lines
  end

  function self.destroy()
    for _, anchor in ipairs(ANCHORS) do
      local bar = bars[anchor]
      for _, prim in pairs(bar.icons) do
        prim.destroy()
      end
      for _, prim in pairs(bar.texts) do
        prim.destroy()
      end
      bar.icons, bar.texts, bar.drawn = {}, {}, {}
    end
  end

  return self
end

return new
