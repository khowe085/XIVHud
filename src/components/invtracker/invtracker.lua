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
     path worth keeping.

     Every square and label remembers what it last drew, and a repaint pushes
     only what changed (2026-09-06). It used to hide every prim and show each
     again as it was placed, on every read - and every packet that says an
     item moved buys a read, so a GearSwap burst (one 0x050 per slot swapped)
     repainted the grid frame after frame and it flickered in a live client
     (Kevin). A square that stays where it is now hears nothing at all. ]]

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
       bottom that gives the grid its relief. `drawn` is what the pair last
       drew, nil while it is hidden. ]]
  local squares = {}
  -- One text per block key, the bag's short name under it. Built and kept
  -- exactly as the squares are, with the same `drawn` memory beside it.
  local labels = {}

  --[[ Which config the colours and the label style on screen came from.
       Bumped on attach, so every prim is re-pushed its palette and style by
       the next render - WITHOUT forgetting whether it is up: a re-attach
       arrives with no detach before it (`//hud slot`, `//hud reset`, `//hud
       copy`), and a memory wiped there stranded the squares of a bag the
       new config drops on screen for the session (caught in review).

       The contract is that an attach is the ONLY thing that moves the
       palette or the label style: no `//hud invtracker` verb touches
       either today, and one that did would have to bump this as well or
       its change would never reach a square already on screen. ]]
  local dressing = 0

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
      square = { shadow = new_square(), box = new_square(), drawn = nil, memo = {} }
      bag[index] = square
    end
    return square
  end

  local function label_for(key)
    local label = labels[key]
    if not label then
      local prim = ctx.new_text()
      -- Deliberately not right-justified, like every text this addon draws:
      -- a right-justified prim is positioned from the screen's right edge.
      prim.draggable(false)
      prim.hide()
      label = { prim = prim, drawn = nil, memo = {}, dressing = nil }
      labels[key] = label
    end
    return label
  end

  local function style_label(label)
    local style = config.labels or {}
    local color = style.color or {}
    local stroke = style.stroke or {}
    label.font(style.font)
    label.bold(style.bold and true or false)
    label.italic(style.italic and true or false)
    label.color(color.r, color.g, color.b)
    label.alpha(color.a or 255)
    label.stroke_width(stroke.width or 0)
    label.stroke_color(stroke.r, stroke.g, stroke.b)
    label.stroke_alpha(stroke.a or 0)
    label.bg_visible(false)
  end

  -- Takes down whatever was drawn last time and is not in `kept` - a slot
  -- that has gone (a shrunken bag, a bag switched off), or everything.
  local function hide_unkept(kept)
    for key, bag in pairs(squares) do
      for index, square in pairs(bag) do
        if square.drawn ~= nil and not (kept.squares[key] and kept.squares[key][index]) then
          square.shadow.hide()
          square.box.hide()
          square.drawn = nil
        end
      end
    end
    for key, label in pairs(labels) do
      if label.drawn ~= nil and not kept.labels[key] then
        label.prim.hide()
        label.drawn = nil
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

  -- A square is pushed what differs from its last draw and nothing else.
  -- The memory is one table per prim for its life, written in place: a
  -- fresh one per render would be over a thousand allocations a repaint.
  local function place_square(square, x, y, slot_size, box_size, colour)
    local last = square.drawn
    if last == nil or last.colour ~= colour or last.dressing ~= dressing then
      paint(square, colour)
    end
    if last == nil or last.x ~= x or last.y ~= y or last.slot ~= slot_size or last.box ~= box_size then
      square.shadow.pos(x, y)
      square.shadow.size(slot_size, slot_size)
      square.box.pos(x, y)
      square.box.size(box_size, box_size)
    end
    if last == nil then
      square.shadow.show()
      square.box.show()
      last = square.memo
      square.drawn = last
    end
    last.x, last.y, last.slot, last.box, last.colour, last.dressing = x, y, slot_size, box_size, colour, dressing
  end

  local function place_label(label, value, x, y, size)
    if label.dressing ~= dressing then
      style_label(label.prim)
      label.dressing = dressing
    end
    local last = label.drawn
    if last == nil or last.text ~= value then
      label.prim.text(value)
    end
    if last == nil or last.x ~= x or last.y ~= y then
      label.prim.pos(x, y)
    end
    if last == nil or last.size ~= size then
      label.prim.size(size)
    end
    if last == nil then
      label.prim.show()
      last = label.memo
      label.drawn = last
    end
    last.text, last.x, last.y, last.size = value, x, y, size
  end

  --[[ Lay the blocks out and push every square at them. Called on a read and
       on any change that moves things - never per frame, since nothing here
       animates and a settled grid costs nothing to leave alone. ]]
  local function render()
    -- What this pass placed; whatever was up and is not in it comes down
    -- afterwards, so a slot that has gone cannot be left on screen and a
    -- slot that stays is never blinked.
    local kept = { squares = {}, labels = {} }

    if visible and pos then
      local preview = logic.preview()
      local sizes = preview and logic.preview_sizes(drawing.sizes) or drawing.sizes
      local box_size = logic.box_size(scale)
      local slot_size = logic.slot_size(scale)

      for _, block in ipairs(logic.layout(sizes, pos.x, pos.y, scale)) do
        local colours = drawing.colours[block.key] or {}
        local kept_bag = {}
        kept.squares[block.key] = kept_bag
        for index = 1, block.slots do
          local at = logic.slot_position(block, index, scale)
          local colour = preview and logic.preview_colour(index) or colours[index] or "empty"
          place_square(square_for(block.key, index), at.x, at.y, slot_size, box_size, colour)
          kept_bag[index] = true
        end

        if logic.labels_enabled() then
          local at = logic.label_position(block, scale)
          place_label(label_for(block.key), block.label or block.key, at.x, at.y, at.size)
          kept.labels[block.key] = true
        end
      end
    end

    hide_unkept(kept)
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
    -- The palette and the label style are the new config's.
    dressing = dressing + 1
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
    local message, changed, reread = logic.command(args)
    if changed then
      --[[ Which bags are drawn and how each is ordered are decided at the
           READ, not at the repaint, so a bag just switched on has no colours
           to draw until the client is read again; logic says which changes
           are that kind. The read is taken on the next tick like every other,
           so a burst of commands still costs one. ]]
      if reread then
        logic.mark_dirty()
      end
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
    for _, label in pairs(labels) do
      label.prim.destroy()
    end
    labels = {}
  end

  return self
end

return new
