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

--[[ Equip Viewer - the equipped gear grid: sixteen item icons, an X over any
     slot the player is encumbered out of, and the ammo count over the ammo
     icon.

     This file owns prims and the two things logic cannot do - reading the
     client, and moving bytes between the game's DAT files and the icon cache.
     What is in each slot, and where it draws, comes from logic.lua.

     Every prim is created once at construction and only ever re-styled, so
     `destroy` can always dispose them and a setting change costs no rebuild -
     the reference addon tore down and recreated all thirty-four to change an
     alpha.

     Icons are not shipped. The first time an item is seen its icon is pulled
     out of the client's own DAT files and cached under icons/ beside the
     addon; from then on the file is simply there. That pipeline - the
     one-icon-per-frame queue, the give-up rule, the shared cache directory -
     lives in lib/icon_cache, promoted from this file so the crossbar can use
     it too. ]]

local new_logic = require("components/equipviewer/logic")
local build_defaults = require("components/equipviewer/defaults")
local new_icon_cache = require("lib/icon_cache")

local ASSET_DIR = "components/equipviewer/assets/"
local ENCUMBRANCE_TEXTURE = "encumbrance.png"
-- A white square, tinted to the configured colour: a prim with no texture is
-- not something this repo draws with, and the framework's highlight box is the
-- same trick.
local PANEL_TEXTURE = "panel.png"

local function new(ctx)
  local self = { name = "equipviewer" }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults
  local attached = false
  local logic = new_logic(config)

  local pos = nil
  local scale = 1
  local visible = false

  local save = nil

  -- Where the client is installed. The setting wins when the player has one,
  -- because Windower's own answer is a registry lookup that can be wrong for a
  -- second install.
  local function game_path()
    local configured = config.game_path
    if type(configured) == "string" and configured ~= "" then
      return configured
    end
    return ctx.game_path()
  end

  -- The extraction pipeline: request on the packet path, one DAT read per
  -- frame off it, results cached at <addon>/icons/ for every component.
  local cache = new_icon_cache({
    asset = ctx.asset,
    file_exists = ctx.file_exists,
    read_dat = ctx.read_dat,
    write_binary = ctx.write_binary,
    game_path = game_path,
  })

  -- The whole equipment table is worth re-reading, on the next frame rather
  -- than here: the packets that ask for it arrive one per bag.
  local refresh_pending = false

  -- What each slot's icon prim was last pointed at, so a redraw does not set a
  -- texture the prim already holds.
  local drawn = {}

  local panel = ctx.new_image()
  local slot_icons = {}
  local markers = {}
  local ammo = ctx.new_text()

  local function prepare(image)
    image.draggable(false)
    image.repeat_xy(1, 1)
    -- An image sized to its texture ignores size(), which would leave the
    -- framework's scale doing nothing.
    image.fit(false)
    image.hide()
    return image
  end

  prepare(panel)
  panel.path(ctx.asset(ASSET_DIR .. PANEL_TEXTURE))
  for _, slot in ipairs(logic.slots()) do
    slot_icons[slot] = prepare(ctx.new_image())
  end
  for _, slot in ipairs(logic.slots()) do
    markers[slot] = prepare(ctx.new_image())
    markers[slot].path(ctx.asset(ASSET_DIR .. ENCUMBRANCE_TEXTURE))
  end

  ammo.draggable(false)
  -- Deliberately not right-justified: texts.pos adds the screen width to x
  -- when the right flag is set, which would draw the count off screen.
  ammo.hide()

  local function apply_visibility()
    if not visible then
      panel.hide()
      ammo.hide()
      for _, slot in ipairs(logic.slots()) do
        slot_icons[slot].hide()
        markers[slot].hide()
      end
      return
    end

    if logic.background_visible() then
      panel.show()
    else
      panel.hide()
    end

    for _, slot in ipairs(logic.slots()) do
      local item_id = logic.item(slot)
      local path = item_id ~= 0 and cache.cached_icon(item_id) or nil
      if path then
        if drawn[slot] ~= path then
          slot_icons[slot].path(path)
          drawn[slot] = path
        end
        slot_icons[slot].show()
      else
        slot_icons[slot].hide()
      end

      if logic.encumbered(slot) then
        markers[slot].show()
      else
        markers[slot].hide()
      end
    end

    local count = logic.ammo_text()
    if count then
      ammo.text(count)
      ammo.show()
    else
      ammo.hide()
    end
  end

  --[[ Every event ends here; there is no per-frame redraw. Icons are asked
       for on the way through rather than while drawing, so the cache fills as
       gear is worn whether or not the grid happens to be on screen. ]]
  local function render()
    for _, slot in ipairs(logic.slots()) do
      local item_id = logic.item(slot)
      if item_id ~= 0 and not cache.cached_icon(item_id) then
        cache.request_icon(item_id)
      end
    end
    apply_visibility()
  end

  local function apply_style()
    local icon_color = config.icon or {}
    local background = config.bg or {}
    local text = config.ammo_text or {}
    local stroke = text.stroke or {}
    local alpha = icon_color.a or 255

    panel.color(background.r, background.g, background.b)
    panel.alpha(background.a or 0)

    for _, slot in ipairs(logic.slots()) do
      slot_icons[slot].color(icon_color.r, icon_color.g, icon_color.b)
      slot_icons[slot].alpha(alpha)
      markers[slot].color(icon_color.r, icon_color.g, icon_color.b)
      -- The X is dimmed against the icon it covers.
      markers[slot].alpha(math.floor(alpha * (config.encumbrance_alpha_factor or 1)))
    end

    ammo.font(text.font)
    ammo.bold(text.bold and true or false)
    ammo.italic(text.italic and true or false)
    ammo.color(text.r, text.g, text.b)
    ammo.alpha(text.a or 255)
    ammo.stroke_width(stroke.width)
    ammo.stroke_color(stroke.r, stroke.g, stroke.b)
    ammo.stroke_alpha(stroke.a)
    ammo.bg_visible(false)
  end

  local function apply_layout()
    if not pos then
      return
    end

    local _, _, width, height = logic.bounds(pos.x, pos.y, scale)
    panel.pos(pos.x, pos.y)
    panel.size(width, height)

    for _, slot in ipairs(logic.slots()) do
      local cell = logic.cell(slot, pos.x, pos.y, scale)
      slot_icons[slot].pos(cell.x, cell.y)
      slot_icons[slot].size(cell.size, cell.size)
      markers[slot].pos(cell.x, cell.y)
      markers[slot].size(cell.size, cell.size)
    end

    local count = logic.ammo_position(pos.x, pos.y, scale)
    ammo.pos(count.x, count.y)
    ammo.size(count.size)
  end

  -- The client hands back a bag and an index per slot, never the item, so each
  -- occupied slot costs a second read. The table itself is read once, not once
  -- per slot as the reference addon did.
  local function apply_reads(reads)
    for _, read in ipairs(reads) do
      local item = ctx.get_item(read.bag, read.index)
      logic.set_item(read.slot, item and item.id, item and item.count)
    end
  end

  local function refresh()
    apply_reads(logic.set_equipment(ctx.get_equipment()))
    render()
  end

  function self.attach(loaded_config, persist)
    config = loaded_config
    attached = true
    logic.set_config(config)
    save = persist
    apply_style()
    apply_layout()
    refresh()
  end

  -- The character is gone, and so is the gear it was wearing: nothing here may
  -- be shown to whoever logs in next.
  function self.detach()
    attached = false
    logic.on_logout()
    -- The queue and the give-ups go with the character (see icon_cache.reset);
    -- what is already on disk stays for whoever logs in next.
    cache.reset()
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
    apply_visibility()
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

  --[[ No arguments is the per-frame tick, which does nothing but move the
       icon queue along. Otherwise a game event the entry point forwarded:
       `chunk` carries a raw packet and fires for every packet the client
       receives, so the id is checked before anything is parsed. ]]
  function self.update(event, first, second)
    if not attached then
      return
    end

    if event == nil then
      if refresh_pending then
        refresh_pending = false
        refresh()
        return
      end
      if cache.drain_queue() then
        render()
      end
      return
    end

    if event ~= "chunk" or not logic.wants_chunk(first) then
      return
    end

    local result = logic.on_chunk(first, ctx.parse_packet(second))
    refresh_pending = refresh_pending or result.refresh

    -- Most of what reaches here is the zone-in inventory burst, for bags
    -- nothing is wearing: thirty-four prims are left alone unless something
    -- they draw actually moved.
    if result.changed or #result.reads > 0 then
      apply_reads(result.reads)
      render()
    end
  end

  --[[ An icon that could not be extracted leaves a cell empty and says nothing
       about it, and the likeliest cause - Windower pointing at the wrong
       install - empties the whole grid. A component has no channel of its own
       to complain on, so the command answers for it. ]]
  function self.handle_command(args)
    local message, changed = logic.command(args)
    if changed then
      apply_style()
      render()
      if save then
        save()
      end
    end

    local abandoned = cache.abandoned_count()
    if abandoned == 0 then
      return message
    end

    return {
      message,
      ("  %d icon%s could not be read from the game's DAT files - check the game_path setting"):format(
        abandoned,
        abandoned == 1 and "" or "s"
      ),
    }
  end

  function self.destroy()
    panel.destroy()
    ammo.destroy()
    for _, slot in ipairs(logic.slots()) do
      slot_icons[slot].destroy()
      markers[slot].destroy()
    end
  end

  return self
end

return new
