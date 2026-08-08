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

--[[ Equip Viewer logic - what is in each equipment slot, and where the grid
     draws it.

     Nothing here reads the client or touches disk: the widget performs the
     reads this module asks for and owns the prims. ]]

local COLUMNS = 4
local ROWS = 4

--[[ The sixteen equipment slots, in slot-id order, each with the grid cell the
     reference addon draws it in. Cells are numbered left to right, top to
     bottom, so the order down this list is not the order across the grid:

       main   sub    range  ammo
       head   neck   l.ear  r.ear
       body   hands  l.ring r.ring
       back   waist  legs   feet

     `name` is the key the client's equipment table uses; its bag is the same
     key with `_bag` appended. ]]
local SLOTS = {
  { id = 0, name = "main", cell = 0 },
  { id = 1, name = "sub", cell = 1 },
  { id = 2, name = "range", cell = 2 },
  { id = 3, name = "ammo", cell = 3 },
  { id = 4, name = "head", cell = 4 },
  { id = 5, name = "body", cell = 8 },
  { id = 6, name = "hands", cell = 9 },
  { id = 7, name = "legs", cell = 14 },
  { id = 8, name = "feet", cell = 15 },
  { id = 9, name = "neck", cell = 5 },
  { id = 10, name = "waist", cell = 13 },
  { id = 11, name = "left_ear", cell = 6 },
  { id = 12, name = "right_ear", cell = 7 },
  { id = 13, name = "left_ring", cell = 10 },
  { id = 14, name = "right_ring", cell = 11 },
  { id = 15, name = "back", cell = 12 },
}

local SLOT_IDS = {}
local BY_ID = {}
for index, slot in ipairs(SLOTS) do
  SLOT_IDS[index] = slot.id
  BY_ID[slot.id] = slot
end

local AMMO_SLOT = 3

-- Both mean "nothing here": a slot the client reports as empty, and the
-- marker an item packet carries for one.
local EMPTY_ITEM_IDS = { [0] = true, [65535] = true }

-- The item status the client reports for gear that is being worn. Anything
-- else, with a count of zero, means the stack is gone.
local EQUIPPED_STATUS = 5

local EQUIP = 0x050 -- an item was equipped or unequipped
local ITEM_COUNT = 0x01E -- a stack was recounted, with no item id
local ITEM_ASSIGN = 0x01F -- an item appeared in a slot
local ITEM_UPDATES = 0x020 -- an item's count or status changed
local JOB_INFO = 0x01B -- job, stats, and the encumbrance flags
local FINISH_INVENTORY = 0x01D -- a bag, or with Flag 1 every bag, finished loading

local HANDLED_CHUNKS = {
  [EQUIP] = true,
  [ITEM_COUNT] = true,
  [ITEM_ASSIGN] = true,
  [ITEM_UPDATES] = true,
  [JOB_INFO] = true,
  [FINISH_INVENTORY] = true,
}

-- The two features that are worth a command; `label` is how each reads back
-- in a sentence.
local TOGGLES = {
  encumbrance = { word = "encumbrance", key = "show_encumbrance", label = "encumbrance" },
  ammocount = { word = "ammocount", key = "show_ammo_count", label = "ammo count" },
}

local function new(initial_config)
  local self = {}
  local config = initial_config or {}
  local preview = false

  -- One entry per equipment slot: what is in it, and where that came from.
  -- `bag` and `index` are how an item packet is matched back to a slot.
  local slots = {}
  local encumbrance = 0

  local function reset_slots()
    for _, slot in ipairs(SLOT_IDS) do
      slots[slot] = { item_id = 0, count = nil, bag = nil, index = nil }
    end
  end

  reset_slots()

  local function cell_size(scale)
    return (config.icon_size or 0) * scale
  end

  -- Whether the last packet moved anything the grid draws. The widget leaves
  -- its prims alone when it did not.
  local changed = false

  local function empty_slot(slot)
    local state = slots[slot]
    changed = changed or state.item_id ~= 0 or state.count ~= nil
    state.item_id = 0
    state.count = nil
    state.bag = nil
    state.index = nil
  end

  local function slot_at(bag, index)
    if bag == nil or index == nil then
      return nil
    end
    for _, slot in ipairs(SLOT_IDS) do
      local state = slots[slot]
      if state.bag == bag and state.index == index then
        return slot
      end
    end
    return nil
  end

  function self.set_config(new_config)
    config = new_config
  end

  -- Every equipment slot, in slot-id order. The widget builds one icon per
  -- entry and asks where it goes.
  function self.slots()
    return SLOT_IDS
  end

  -- Where a slot's icon draws for a grid anchored at (x, y).
  function self.cell(slot, x, y, scale)
    local size = cell_size(scale)
    local placement = BY_ID[slot]
    if not placement then
      return { x = x, y = y, size = size }
    end
    return {
      x = x + (placement.cell % COLUMNS) * size,
      y = y + math.floor(placement.cell / COLUMNS) * size,
      size = size,
    }
  end

  -- The whole grid. Nothing draws outside it, and its top left is the origin
  -- the framework handed set_pos, which is what get_bounds has to return.
  function self.bounds(x, y, scale)
    local size = cell_size(scale)
    return x, y, COLUMNS * size, ROWS * size
  end

  --[[ The client's equipment table, which gives a bag and an index per slot but
       not the item itself. Returns the reads the widget must perform to find
       out; an unoccupied slot is emptied here and costs no read.

       A nil table is the client not being ready - early in a login get_items
       comes back with nothing - and leaves the grid as it was. ]]
  function self.set_equipment(equipment)
    local reads = {}
    if not equipment then
      return reads
    end

    for _, slot in ipairs(SLOT_IDS) do
      local name = BY_ID[slot].name
      local index = equipment[name]
      local bag = equipment[name .. "_bag"]
      -- Both or neither: an index with no bag beside it cannot be read, and
      -- the nil would be carried into the call without complaint.
      if not index or index == 0 or not bag then
        empty_slot(slot)
      else
        slots[slot].bag = bag
        slots[slot].index = index
        reads[#reads + 1] = { slot = slot, bag = bag, index = index }
      end
    end

    return reads
  end

  --[[ The result of a read, or an item id straight off a packet. A nil id is a
       read that came back with nothing, which is not the same fact as an empty
       slot and leaves the icon alone. ]]
  function self.set_item(slot, item_id, count)
    local state = slots[slot]
    if not state or item_id == nil then
      return
    end

    if EMPTY_ITEM_IDS[item_id] then
      empty_slot(slot)
      return
    end

    changed = changed or state.item_id ~= item_id or state.count ~= count
    state.item_id = item_id
    state.count = count
  end

  function self.item(slot)
    local state = slots[slot]
    return state and state.item_id or 0
  end

  function self.wants_chunk(id)
    return HANDLED_CHUNKS[id] == true
  end

  --[[ A packet the entry point forwarded, already parsed - nil when parsing
       failed. Everything this module can settle on its own it settles here;
       what comes back is only the reads it cannot perform itself: `refresh`
       for the whole equipment table, `reads` for individual slots. ]]
  function self.on_chunk(id, packet)
    changed = false
    local result = { refresh = false, reads = {}, changed = false }

    --[[ The whole equipment table, once the client has finished pushing the
         bags. Nothing else fills the grid at a login or a zone: read any
         earlier and every slot reports index 0, which is indistinguishable
         from an empty one, and the item packets in the same burst are matched
         on a bag and index no slot knows yet. The widget coalesces the refresh
         onto its next frame, so the one per bag this fires costs one read.

         Ahead of the parsed-packet guard deliberately, as giltracker does with
         the same packet: nothing is read out of it, and this is the only path
         that fills the grid at a login - a parse failure here would leave it
         blank until the player next changed job. ]]
    if id == FINISH_INVENTORY then
      result.refresh = true
      return result
    end

    if not packet then
      return result
    end

    if id == JOB_INFO then
      local flags = tonumber(packet["Encumbrance Flags"]) or 0
      changed = changed or flags ~= encumbrance
      encumbrance = flags
      -- A job change lands here, and the gear it swapped in arrives with no
      -- packet of its own. Cheaper than an outgoing chunk handler, which would
      -- have to see every packet the client sends to catch the one request.
      result.refresh = true
      result.changed = changed
      return result
    end

    if id == EQUIP then
      local slot = packet["Equipment Slot"]
      if not slots[slot] then
        return result
      end
      local index = packet["Inventory Index"]
      if not index or index == 0 then
        empty_slot(slot)
        result.changed = changed
        return result
      end
      local bag = packet["Inventory Bag"]
      slots[slot].bag = bag
      slots[slot].index = index
      result.reads[1] = { slot = slot, bag = bag, index = index }
      return result
    end

    local slot = slot_at(packet.Bag, packet.Index)
    if not slot then
      return result
    end

    local count = tonumber(packet.Count)
    if packet.Status ~= EQUIPPED_STATUS and count == 0 then
      empty_slot(slot)
      result.changed = changed
      return result
    end

    -- 0x01E carries no item at all, only a new count, so there is nothing to
    -- set beyond it - the slot already knows what it is holding.
    if packet.Item ~= nil then
      self.set_item(slot, packet.Item, count)
    elseif count then
      changed = changed or slots[slot].count ~= count
      slots[slot].count = count
    end

    result.changed = changed
    return result
  end

  -- Whether the grid should draw an X over a slot. Bit n of the flags is slot
  -- n, so only the low sixteen bits are ever read here - the rest are the stat
  -- encumbrances. Arithmetic rather than the bit library, which is LuaJIT's
  -- and not Lua 5.1's, so nothing here could test it.
  function self.encumbered(slot)
    if not config.show_encumbrance or not BY_ID[slot] then
      return false
    end
    return math.floor(encumbrance / 2 ^ slot) % 2 == 1
  end

  -- The number over the ammo icon, or nil when there is nothing worth saying.
  -- A single item is not a stack, which is the reference's rule.
  function self.ammo_text()
    if not config.show_ammo_count then
      return nil
    end
    local count = slots[AMMO_SLOT].count
    if not count or count <= 1 then
      return nil
    end
    return tostring(count)
  end

  -- The character is gone. What it was wearing must not reach the next one,
  -- and neither must the bag and index a stale packet could still match.
  function self.on_logout()
    reset_slots()
    encumbrance = 0
  end

  function self.set_preview(on)
    preview = on and true or false
  end

  -- The panel behind the grid. Forced on while the layout is being arranged:
  -- with it off and nothing equipped there would be nothing on screen to
  -- arrange.
  function self.background_visible()
    return preview or (config.bg or {}).visible == true
  end

  local function set_toggle(verb, word)
    local wanted = word and word:lower()
    if wanted ~= "on" and wanted ~= "off" then
      return "//hud equipviewer " .. verb.word .. " needs on or off", false
    end
    config[verb.key] = wanted == "on"
    return "equipviewer " .. verb.label .. " " .. wanted, true
  end

  local function status()
    return string.format(
      "equipviewer: encumbrance %s, ammo count %s",
      config.show_encumbrance and "on" or "off",
      config.show_ammo_count and "on" or "off"
    )
  end

  -- `//hud equipviewer ...`. Returns the line to print and whether anything
  -- changed, so the widget knows when to redraw and save. The reference's
  -- position, size, scale, alpha, background and justify verbs are gone: the
  -- framework owns the first three and the rest are configuration keys.
  function self.command(args)
    local word = (args or {})[1]
    if not word then
      return status(), false
    end

    local verb = TOGGLES[word:lower()]
    if verb then
      return set_toggle(verb, args[2])
    end

    return string.format("equipviewer has no '%s' setting (encumbrance, ammocount)", word), false
  end

  -- The ammo count, drawn over the lower half of the ammo icon.
  function self.ammo_position(x, y, scale)
    local size = cell_size(scale)
    local text = config.ammo_text or {}
    return {
      x = self.cell(AMMO_SLOT, x, y, scale).x,
      y = y + size * (text.y_factor or 0),
      -- Whole pixels: a fractional font size is not something a prim can draw.
      size = math.floor(size * (text.size_factor or 0) + 0.5),
    }
  end

  return self
end

return new
