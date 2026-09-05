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

--[[ Inventory Tracker - the FFXIV inventory grid for FFXI: every slot of the
     chosen bags as a small coloured square, so how full each bag is reads at a
     glance without opening a menu.

     This file owns the prims and the one read of the client; which bags to
     draw, what colour each slot takes and when a read is worth making all come
     from logic.lua, and whether to draw at all comes from the framework.

     Prims are built the first time a slot is drawn and then kept: a bag that
     shrinks or is switched off hides its surplus rather than destroying it, so
     switching it back on costs nothing. Nothing is ever built per read - the
     reference addon cached the same way, and it is the only part of its draw
     path worth keeping. ]]

local new_logic = require("components/invtracker/logic")
local build_defaults = require("components/invtracker/defaults")

-- A flat white square, tinted per slot. XIVHud's own art, already bundled for
-- the panel behind the equip viewer's grid.
local SQUARE_TEXTURE = "assets/own/panel.png"

local function new(ctx)
  local self = { name = "invtracker", alias = "inv" }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults
  local logic = new_logic(config)

  local attached = false
  local visible = false
  local pos = nil
  local scale = 1
  local save = nil

  -- The last read turned into colours, and the blocks those colours fill.
  -- Kept so a command can repaint without buying another read of the client.
  local drawing = { sizes = {}, colours = {} }

  --[[ Two prims per slot, keyed by bag and slot index: the darker `shadow`
       square and the `box` drawn on top of it, offset by nothing - the box is
       smaller, so what shows around it is the 1px shadow down the right and
       bottom that gives the grid its relief. ]]
  local squares = {}

  -- An item id's stack size, for telling a full stack from a part one.
  -- Answers nil without the resources library, which costs only that colour.
  local function stack_of(item_id)
    local items = ctx.resources and ctx.resources.items
    local item = items and items[item_id]
    return item and item.stack
  end

  local function new_square()
    local prim = ctx.new_image()
    prim.draggable(false)
    prim.repeat_xy(1, 1)
    -- The prim must not size itself to its texture, or the widget scale would
    -- silently do nothing.
    prim.fit(false)
    prim.path(ctx.asset(SQUARE_TEXTURE))
    prim.hide()
    return prim
  end

  local function square_for(key, index)
    local bag = squares[key]
    if not bag then
      bag = {}
      squares[key] = bag
    end
    local square = bag[index]
    if not square then
      square = { shadow = new_square(), box = new_square() }
      bag[index] = square
    end
    return square
  end

  local function hide_all()
    for _, bag in pairs(squares) do
      for _, square in pairs(bag) do
        square.shadow.hide()
        square.box.hide()
      end
    end
  end

  local function paint(square, colour)
    local palette = (config.colours or {})[colour] or (config.colours or {}).default or {}
    local box = palette.box or {}
    local shadow = palette.shadow or {}

    square.shadow.color(shadow.r, shadow.g, shadow.b)
    square.shadow.alpha(shadow.a or 255)
    square.box.color(box.r, box.g, box.b)
    square.box.alpha(box.a or 255)
  end

  --[[ Lay the blocks out and push every square at them. Called on a read and
       on any change that moves things - never per frame, since nothing here
       animates and a settled grid costs nothing to leave alone. ]]
  local function render()
    -- Everything is hidden first and shown as it is placed, so a slot that has
    -- gone (a shrunken bag, a bag switched off) cannot be left on screen.
    hide_all()

    if not visible or not pos then
      return
    end

    local preview = logic.preview()
    local sizes = preview and logic.preview_sizes(drawing.sizes) or drawing.sizes
    local box_size = logic.box_size(scale)
    local slot_size = logic.slot_size(scale)

    for _, block in ipairs(logic.layout(sizes, pos.x, pos.y, scale)) do
      local colours = drawing.colours[block.key] or {}
      for index = 1, block.slots do
        local square = square_for(block.key, index)
        local at = logic.slot_position(block, index, scale)

        paint(square, preview and logic.preview_colour(index) or colours[index] or "empty")

        square.shadow.pos(at.x, at.y)
        square.shadow.size(slot_size, slot_size)
        square.shadow.show()
        square.box.pos(at.x, at.y)
        square.box.size(box_size, box_size)
        square.box.show()
      end
    end
  end

  -- One read of the client, turned straight into what to draw. Every read is a
  -- full get_items push, so logic decides when one is worth making.
  local function read_client()
    drawing = logic.read(ctx.get_items(), ctx.resources and stack_of or nil)
    render()
  end

  function self.attach(loaded_config, persist)
    config = loaded_config
    save = persist
    attached = true
    logic.set_config(config)
    logic.on_attach()
    render()
  end

  -- The character is gone, and so are the bags this was drawing. Nothing is
  -- read again until the next character's own load settles.
  function self.detach()
    attached = false
    drawing = { sizes = {}, colours = {} }
    logic.on_logout()
    self.hide()
  end

  --[[ Every one of the four below is pushed far more often than it changes:
       core's apply sends scale, position, preview and visibility together, and
       layout mode calls apply on every mouse-move event of a drag. A repaint
       rewrites every square in the grid, of which there are hundreds, so one
       that would draw exactly what is already on screen is skipped.

       Safe because render() is a pure function of these four and the last
       read, and every change to the read renders itself. ]]
  function self.set_pos(x, y)
    if pos and pos.x == x and pos.y == y then
      return
    end
    pos = { x = x, y = y }
    render()
  end

  function self.set_scale(new_scale)
    if scale == new_scale then
      return
    end
    scale = new_scale
    render()
  end

  function self.set_preview(on)
    local wanted = on and true or false
    if logic.preview() == wanted then
      return
    end
    logic.set_preview(wanted)
    render()
  end

  local function set_visible(wanted)
    if visible == wanted then
      return
    end
    visible = wanted
    render()
  end

  function self.show()
    set_visible(true)
  end

  function self.hide()
    set_visible(false)
  end

  function self.get_bounds()
    if not pos then
      return nil
    end
    local sizes = logic.preview() and logic.preview_sizes(drawing.sizes) or drawing.sizes
    return logic.bounds(sizes, pos.x, pos.y, scale)
  end

  --[[ No arguments is the per-frame tick, which is where a pending read is
       taken: the packets below only mark that something moved, so a burst of
       them costs one read rather than one apiece.

       Anything else is a game event the entry point forwarded. `chunk` fires
       for every packet the client receives, so the id is asked first and the
       raw bytes are never parsed through the packets library - the one field
       this reads, 0x01D's Flag, is a single byte of the chunk. ]]
  function self.update(event, first, second)
    if not attached then
      return
    end

    if event == nil then
      if logic.should_read() then
        read_client()
      end
      return
    end

    if event == "chunk" then
      if logic.wants_chunk(first) then
        logic.on_chunk(first, second)
      end
      return
    end

    if event == "add item" or event == "remove item" then
      logic.on_item(first)
      return
    end

    if event == "job change" then
      logic.on_job_change()
    end
  end

  function self.handle_command(args)
    local message, changed = logic.command(args)
    if changed then
      --[[ Which bags are drawn and how each is ordered are decided at the
           READ, not at the repaint, so a bag just switched on has no colours
           to draw until the client is read again. The read is taken on the
           next tick like every other, so a burst of commands still costs
           one. ]]
      logic.mark_dirty()
      render()
      if save then
        save()
      end
    end
    return message
  end

  function self.destroy()
    for _, bag in pairs(squares) do
      for _, square in pairs(bag) do
        square.shadow.destroy()
        square.box.destroy()
      end
    end
    squares = {}
  end

  return self
end

return new
