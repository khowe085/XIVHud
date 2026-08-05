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

--[[ Gil Tracker logic - when to re-read gil, and what the widget draws.

     Reading gil is expensive: windower.ffxi.get_items() pushes every item the
     character owns, and there is no cheaper call that carries gil (get_bag_info
     returns counts only). So gil is never polled. The packets below say when it
     may have changed, and this module turns that stream into "read it now"
     answers - the same design the reference addon used, which is the one thing
     about it worth keeping verbatim.

     It reads nothing and draws nothing itself: the widget performs the read and
     owns the prims. ]]

local GIL_ITEM_ID = 65535

local ZONE_IN = 0x00A -- clears the inventory as the zone changes
local FINISH_INVENTORY = 0x01D -- a bag, or with Flag 1 every bag, finished loading
local ITEM_ASSIGN = 0x01F -- an item appeared in a slot
local ITEM_UPDATES = 0x020 -- an item's count changed
local FOUND_ITEM = 0x0D2 -- something landed in the treasure pool

local HANDLED_CHUNKS = {
  [ZONE_IN] = true,
  [FINISH_INVENTORY] = true,
  [ITEM_ASSIGN] = true,
  [ITEM_UPDATES] = true,
  [FOUND_ITEM] = true,
}

-- The widest gil the game allows, 999,999,999, is 11 characters once it is
-- grouped. The number is left-justified inside that reserved width so the icon
-- beside it never moves as digits come and go.
local RESERVED_CHARACTERS = 11
-- Fraction of the font size one character occupies. The real width is nearer
-- 0.75 -- verified in `//xh layout`, where a capped value runs about two
-- characters under the icon -- but 0.6 is deliberate: reserving the true width
-- parks the icon 75px from a single-digit value, and a gap that wide at every
-- ordinary balance is worse than an overlap nobody will see below 100,000,000
-- gil. Widen it if that day comes.
local CHARACTER_WIDTH_RATIO = 0.6
-- Ascender to descender, as a multiple of the font size. Only decides the box
-- height for a font too tall for the icon.
local TEXT_HEIGHT_RATIO = 1.5

local UNKNOWN_TEXT = "Loading..."
-- Fills the reserved width exactly, so layout mode shows the widest the widget
-- will ever be rather than whatever the character happens to be carrying.
local PREVIEW_GIL = 123456789

local function comma_value(amount)
  local formatted = tostring(amount)
  while true do
    local replacements
    formatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if replacements == 0 then
      return formatted
    end
  end
end

local function new(initial_config)
  local self = {}
  local config = initial_config or {}

  -- Whether this character's bags have finished loading since the last zone.
  local inventory_loaded = false
  -- Whether something has happened that could have moved gil, still waiting on
  -- the inventory to settle before it is worth a read.
  local pending = false
  local gil = nil
  local preview = false

  local function scaled_font_size(scale)
    -- Whole pixels: a fractional font size is not something a prim can draw.
    return math.floor((config.font_size or 0) * scale + 0.5)
  end

  local function reserved_width(scale)
    return math.ceil(RESERVED_CHARACTERS * scaled_font_size(scale) * CHARACTER_WIDTH_RATIO)
  end

  function self.set_config(new_config)
    config = new_config
  end

  function self.wants_chunk(id)
    return HANDLED_CHUNKS[id] == true
  end

  -- Whether the fields are needed, or only the fact that the packet arrived.
  -- Parsing is not free, and every parse is a chance to throw inside the
  -- incoming chunk handler that every component shares.
  function self.needs_packet(id)
    return id == ITEM_ASSIGN or id == ITEM_UPDATES or id == FOUND_ITEM
  end

  -- A packet the entry point forwarded, already parsed. Returns true when gil
  -- should be read now. `packet` is nil if parsing failed.
  function self.on_chunk(id, packet)
    if id == ZONE_IN then
      inventory_loaded = false
      -- The fresh load reads unconditionally, so anything pending from the old
      -- zone is already covered and would otherwise buy one wasted read later.
      pending = false
      return false
    end

    -- Before the parsed-packet guard: nothing is read out of this one, and
    -- refusing to act without it would let a single parse failure stop every
    -- later refresh, since this is the only path a pending change has.
    if id == FINISH_INVENTORY then
      -- What stops a multi-bag load from reading once per bag is these two
      -- flags. Not the packet's Flag field, which distinguishes one bag
      -- finishing from all of them: the "all" value only arrives on a zone in,
      -- so gating on it would leave a pending change unread until the player
      -- next zoned.
      if not inventory_loaded then
        inventory_loaded = true
        -- The read this returns is the whole inventory, so anything pending is
        -- covered by it.
        pending = false
        return true
      end
      if pending then
        pending = false
        return true
      end
      return false
    end

    if not packet then
      return false
    end

    if id == FOUND_ITEM then
      -- Narrower than the reference addon, which armed a read for any drop.
      -- Gil does reach the pool (Windower's own field notes call out counts
      -- above 1 "in the case of gil"), but a party's item drops must not each
      -- buy a full get_items.
      pending = pending or (packet.Item == GIL_ITEM_ID and (tonumber(packet.Count) or 0) > 0)
      return false
    end

    if id == ITEM_ASSIGN or id == ITEM_UPDATES then
      if packet.Item ~= GIL_ITEM_ID then
        return false
      end
      -- Same reasoning as the finish branch: the read this returns is the whole
      -- inventory, so the add item the transaction also produces is covered.
      pending = false
      return true
    end

    return false
  end

  -- An item entered or left a bag. Gil moving is worth a read, but only once
  -- the inventory has settled, so it is recorded rather than acted on.
  function self.on_item(item_id)
    if item_id == GIL_ITEM_ID then
      pending = true
    end
  end

  -- The value goes with the character. Keeping it would show one character's
  -- gil to the next: get_items is empty that early into a login, and set_gil
  -- preserves the last good value rather than blanking the widget.
  function self.on_logout()
    inventory_loaded = false
    pending = false
    gil = nil
  end

  -- The result of a read. A nil or non-numeric value keeps whatever was on
  -- screen: get_items can come back empty around a zone, and a blank widget is
  -- worse than a slightly stale one.
  function self.set_gil(value)
    local amount = tonumber(value)
    if amount then
      gil = math.floor(amount)
    end
  end

  function self.set_preview(on)
    preview = on and true or false
  end

  function self.text()
    if preview then
      return comma_value(PREVIEW_GIL)
    end
    if not gil then
      return UNKNOWN_TEXT
    end
    return comma_value(gil)
  end

  -- Where the two prims go for a widget anchored at (x, y) and drawn at `scale`.
  -- The origin is the top left of the box, never the text's own anchor, because
  -- get_bounds has to hand the framework back the same origin set_pos was given.
  function self.geometry(x, y, scale)
    local font_size = scaled_font_size(scale)
    local icon = config.icon or {}
    return {
      text = {
        x = x,
        y = y + (config.text_y_offset or 0) * scale,
        size = font_size,
      },
      icon = {
        x = x + reserved_width(scale) + (icon.gap or 0) * scale,
        y = y,
        size = (icon.size or 0) * scale,
      },
    }
  end

  function self.bounds(x, y, scale)
    local icon = config.icon or {}
    local width = reserved_width(scale)
    local height = (config.text_y_offset or 0) * scale + scaled_font_size(scale) * TEXT_HEIGHT_RATIO

    if icon.visible then
      width = width + (icon.gap or 0) * scale + (icon.size or 0) * scale
      height = math.max(height, (icon.size or 0) * scale)
    end

    return x, y, width, height
  end

  return self
end

return new
