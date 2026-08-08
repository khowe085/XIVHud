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
     addon; from then on the file is simply there. That work is queued rather
     than done where the packet arrives - see drain_queue. ]]

local new_logic = require("components/equipviewer/logic")
local build_defaults = require("components/equipviewer/defaults")
local icons = require("components/equipviewer/icons")

local ASSET_DIR = "components/equipviewer/assets/"
local ENCUMBRANCE_TEXTURE = "encumbrance.png"
-- A white square, tinted to the configured colour: a prim with no texture is
-- not something this repo draws with, and the framework's highlight box is the
-- same trick.
local PANEL_TEXTURE = "panel.png"
--[[ Deliberately not under data/: `//hud copy` enumerates every directory
     there as a character, so an icon cache alongside them would be offered as
     one - and `//hud copy icons <character>` would then wipe that character's
     configuration and fill it with bitmaps. The cache is not per-character
     anyway; item art is the same for everyone. ]]
local ICON_CACHE_DIR = "icons/"

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

  --[[ Item ids waiting to be pulled out of a DAT, and the ones already spoken
       for: `queued` stops an item being asked for twice, `abandoned` stops a
       failure being retried every frame for the rest of the session, and
       `resolved` remembers the icons already on disk so a redraw costs no
       file lookups. ]]
  local pending = {}
  local queued = {}
  local abandoned = {}
  local abandoned_count = 0
  local resolved = {}

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

  local function icon_file(item_id)
    return ICON_CACHE_DIR .. item_id .. ".bmp"
  end

  -- The icon on disk for an item, or nil if it has not been extracted yet.
  -- An item already given up on is not looked for again: a redraw runs on the
  -- packet path, and the file is not going to appear.
  local function cached_icon(item_id)
    if resolved[item_id] then
      return resolved[item_id]
    end
    if abandoned[item_id] then
      return nil
    end
    local path = ctx.asset(icon_file(item_id))
    if not ctx.file_exists(path) then
      return nil
    end
    resolved[item_id] = path
    return path
  end

  -- An icon the cache does not have is asked for once. Nothing is read here:
  -- this runs on the packet path.
  local function request_icon(item_id)
    if queued[item_id] or abandoned[item_id] then
      return
    end
    queued[item_id] = true
    pending[#pending + 1] = item_id
  end

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
      local path = item_id ~= 0 and cached_icon(item_id) or nil
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
      if item_id ~= 0 and not cached_icon(item_id) then
        request_icon(item_id)
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

  --[[ One icon per frame, and only while something is waiting.

       The reference extracted inside the packet handler, so a first login with
       nothing cached meant sixteen DAT opens, decodes and file writes in a
       single frame. Spreading them costs a few frames before the grid is full
       and keeps the disk off the packet path entirely. ]]
  local function drain_queue()
    local item_id = table.remove(pending, 1)
    if not item_id then
      return false
    end
    queued[item_id] = nil

    -- Whatever the reason, it will be the same reason next frame: an item is
    -- given exactly one attempt.
    abandoned[item_id] = true
    abandoned_count = abandoned_count + 1

    local located = icons.locate(item_id)
    local path = located and icons.dat_path(game_path(), located.dat)
    if not path then
      return false
    end

    local bmp = icons.to_bmp(ctx.read_dat(path, located.offset, located.length))
    if not bmp or not ctx.write_binary(icon_file(item_id), bmp) then
      return false
    end

    abandoned[item_id] = nil
    abandoned_count = abandoned_count - 1
    resolved[item_id] = ctx.asset(icon_file(item_id))
    return true
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
    --[[ The queue goes with the character, and so does everything abandoned:
         the likeliest reason an icon could not be read is a game path pointing
         at the wrong install, and correcting that setting has to be worth
         something. `resolved` stays - a file already on disk is still there
         whoever logs in next. ]]
    pending = {}
    queued = {}
    abandoned = {}
    abandoned_count = 0
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
      if drain_queue() then
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

    if abandoned_count == 0 then
      return message
    end

    return {
      message,
      ("  %d icon%s could not be read from the game's DAT files - check the game_path setting"):format(
        abandoned_count,
        abandoned_count == 1 and "" or "s"
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
