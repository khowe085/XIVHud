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

--[[ Inventory Tracker logic - which bags are drawn, what colour each slot
     takes, and where every square goes.

     It reads nothing and draws nothing itself: the widget performs the reads
     this module asks for and owns the prims. ]]

--[[ The bags, in the order they are drawn left to right. `key` is the field
     windower.ffxi.get_items() answers under and `id` the client's bag id;
     `group` is the setting the player switches it with, so one word covers
     both safes and all eight wardrobes exactly as the reference addon grouped
     them. `label` is what is written under the block: a 5-column block is
     19px wide and at 6pt "inventory" is about 40, so the names are short, and
     the safes and wardrobes carry their number since nothing else tells them
     apart on screen.

     Two entries are not bags at all: `equipment` is what is worn, which the
     client reports as a slot-keyed table rather than a bag, and `treasure` is
     the pool. Both are read by key like the rest. No bag ID is carried,
     because nothing needs one - every read goes through get_items(), which is
     keyed by name.

     The recycle bin is deliberately absent: it holds what was thrown
     away, and nobody tracks how full that is. ]]
local BAGS = {
  { key = "equipment", group = "equipment", label = "Equip" },
  { key = "inventory", group = "inventory", label = "Inv" },
  { key = "safe", group = "safe", label = "Safe" },
  { key = "safe2", group = "safe", label = "Safe2" },
  { key = "storage", group = "storage", label = "Stor" },
  { key = "locker", group = "locker", label = "Lock" },
  { key = "satchel", group = "satchel", label = "Sat" },
  { key = "sack", group = "sack", label = "Sack" },
  { key = "case", group = "case", label = "Case" },
  { key = "wardrobe", group = "wardrobe", label = "W1" },
  { key = "wardrobe2", group = "wardrobe", label = "W2" },
  { key = "wardrobe3", group = "wardrobe", label = "W3" },
  { key = "wardrobe4", group = "wardrobe", label = "W4" },
  { key = "wardrobe5", group = "wardrobe", label = "W5" },
  { key = "wardrobe6", group = "wardrobe", label = "W6" },
  { key = "wardrobe7", group = "wardrobe", label = "W7" },
  { key = "wardrobe8", group = "wardrobe", label = "W8" },
  { key = "temporary", group = "temporary", label = "Temp" },
  { key = "treasure", group = "treasure", label = "Pool" },
}

local ZONE_IN = 0x00A -- the bags are dropped and refilled from here
local INVENTORY_SIZE = 0x01C -- a bag grew, shrank, or was switched on
local FINISH_INVENTORY = 0x01D -- a bag, or with Flag 1 every bag, finished loading
local ITEM_COUNT = 0x01E -- a stack was recounted, and carries no item id
local ITEM_ASSIGN = 0x01F -- an item appeared in a slot
local ITEM_UPDATES = 0x020 -- an item's count or status changed
local EQUIP = 0x050 -- an item was equipped or unequipped
local FOUND_ITEM = 0x0D2 -- something landed in the treasure pool
local LOT_ITEM = 0x0D3 -- someone lotted or passed on the pool

local HANDLED_CHUNKS = {
  [ZONE_IN] = true,
  [INVENTORY_SIZE] = true,
  [FINISH_INVENTORY] = true,
  [ITEM_COUNT] = true,
  [ITEM_ASSIGN] = true,
  [ITEM_UPDATES] = true,
  [EQUIP] = true,
  [FOUND_ITEM] = true,
  [LOT_ITEM] = true,
}

-- Where 0x01D's Flag byte sits in the raw chunk. Field offsets are quoted
-- from the start of the packet, header included, and string.byte is 1-based,
-- so the field at offset 0x04 is index 5 - the rule as partylist/packets.lua
-- states it.
local FINISH_FLAG_BYTE = 5
-- Flag 1 is every bag finished, which is what a zone in ends with; 0 is one
-- bag of the burst.
local ALL_BAGS_FINISHED = 1

--[[ How many ticks a pending read may be held waiting for the settle that
     releases it. About ten seconds at sixty frames a second - far longer than
     a zone takes, so it never fires in ordinary play.

     It exists because the alternative to a bounded hold is an unbounded one:
     if the settle a zone normally ends with never arrives, the grid would sit
     frozen on the previous zone's inventory for the rest of the session with
     nothing to say why. Windower fails silently, so the fallback is to read
     one frame late rather than never. ]]
local HOLD_LIMIT = 600

-- Both mean "nothing moved that this cares about": the marker an item event
-- carries for an empty slot, and gil, which has no slot of its own.
local IGNORED_ITEM_IDS = { [0] = true, [65535] = true }

-- The item statuses the client reports, and the colour each one takes.
-- Anything else falls through to the plain colour below.
local STATUS_COLOURS = {
  [5] = "equipped",
  [19] = "linkshell_equipped",
  [25] = "bazaar",
}

-- The words that switch a bag, in the order they are reported. One word per
-- GROUP, so `safe` covers both safes and `wardrobe` all eight wardrobes.
local BAG_WORDS = {
  "equipment",
  "inventory",
  "safe",
  "storage",
  "locker",
  "satchel",
  "sack",
  "case",
  "wardrobe",
  "temporary",
  "treasure",
}

local ALIGNMENTS = { top = true, bottom = true }

-- Ascender to descender, as a multiple of the font size - the label's line
-- box, which is what the bounds have to cover.
local TEXT_HEIGHT_RATIO = 1.5
-- Fraction of the font size one character occupies. speedcheck's figure, the
-- LARGER of the repo's two estimates, because this one is used to keep two
-- labels off each other and an under-estimate would let them touch. Hardcoded
-- as speedcheck's is; a live client that sees labels touch is the reason to
-- make it a setting.
local CHARACTER_WIDTH_RATIO = 0.75

-- A grid wider than this is not a grid any more, and a pitch wider than this
-- is further apart than any screen makes sense of.
local MAX_COLUMNS = 20
local MAX_SPACING = 32
local MAX_BLOCK_SPACING = 64

--[[ What layout mode draws with nothing loaded: each bag at the capacity it
     usually has, so the box on screen is the footprint the widget will really
     take once a character is in it. A bag switched off is left out - the
     preview must not promise space the player has not asked for. ]]
local PREVIEW_SIZES = {
  equipment = 16,
  inventory = 80,
  safe = 80,
  safe2 = 80,
  storage = 80,
  locker = 80,
  satchel = 80,
  sack = 80,
  case = 80,
  wardrobe = 80,
  wardrobe2 = 80,
  wardrobe3 = 80,
  wardrobe4 = 80,
  wardrobe5 = 80,
  wardrobe6 = 80,
  wardrobe7 = 80,
  wardrobe8 = 80,
  temporary = 10,
  treasure = 10,
}

-- Every third slot of the preview is drawn empty, so a dragged grid reads as
-- a grid rather than one solid rectangle of colour.
local PREVIEW_EMPTY_EVERY = 3

--[[ The sixteen equipment slots in the order they are drawn, which is the
     equip viewer's own 4x4 arrangement rather than the reference addon's:

       main   sub    range  ammo
       head   neck   l.ear  r.ear
       body   hands  l.ring r.ring
       back   waist  legs   feet

     The reference listed them bottom-up, because its grid grew upward from a
     bottom anchor. Ours grows downward, and matching the sibling component is
     worth more than matching an inverted list.

     The client reports each slot as the bag index it is wearing, so zero
     means nothing is worn there. ]]
local EQUIPMENT_SLOTS = {
  "main",
  "sub",
  "range",
  "ammo",
  "head",
  "neck",
  "left_ear",
  "right_ear",
  "body",
  "hands",
  "left_ring",
  "right_ring",
  "back",
  "waist",
  "legs",
  "feet",
}

-- The two bags with no capacity worth drawing as free space: the pool is gone
-- within minutes and the temporary bag holds one zone's worth of items. Both
-- draw what is in them and nothing more, as the reference did.
local OCCUPIED_ONLY = { temporary = true, treasure = true }

local function new(initial_config)
  local self = {}
  local config = initial_config or {}

  --[[ Whether this character's bags have finished arriving since the last
       zone. Reads are held until they have: a zone in refills every bag, and
       reading on each one of the eighteen packets that announces it is a full
       inventory push apiece. ]]
  local loaded = false
  -- Something happened that the grid on screen does not reflect yet.
  local dirty = false
  -- Ticks a pending read has been held for, against HOLD_LIMIT above.
  local held = 0
  local preview = false

  function self.set_config(new_config)
    config = new_config
  end

  --[[ The colour key one slot takes. `stack_of` answers an item id's stack
       size, or nil when the resources library is absent or the item is
       unknown - in which case the slot is drawn as a part stack rather than
       guessed at, since claiming a full stack wrongly is the louder error.

       A status this does not know draws in the plain colour. The reference
       drew it as EMPTY, which made an occupied slot read as free space. ]]
  function self.classify(slot, stack_of)
    if not slot or (tonumber(slot.count) or 0) <= 0 then
      return "empty"
    end

    local colour = STATUS_COLOURS[tonumber(slot.status)]
    if colour then
      return colour
    end

    local stack = stack_of and tonumber(stack_of(slot.id))
    if stack and tonumber(slot.count) == stack then
      return "full_stack"
    end

    return "default"
  end

  --[[ A bag ordered for display, as a COPY - get_items hands back the client's
       own table, and another addon may be holding it.

       The reference addon's comparator, which its README explains: the client
       does not report the player's own sort order, so the grid imposes one.
       Flagged statuses first, then the stack nearest full, then the largest
       count - and finally the client's own slot order, which table.sort would
       otherwise scramble between two reads and make the grid twitch with
       nothing changed. ]]
  function self.sort(bag, stack_of)
    local ordered = {}
    local original = {}
    for index, slot in ipairs(bag or {}) do
      ordered[index] = slot
      original[slot] = index
    end

    if config.sort == false then
      return ordered
    end

    --[[ How many of a full stack the slot is short. An item nothing can name
         sorts as furthest from full rather than dropping the comparison: a key
         that applies to some pairs and not others is not a strict weak
         ordering, and Lua's table.sort can raise on the cycle that makes. It
         would raise inside prerender, where guard disables the shared handler
         after five throws. ]]
    local function gap_to_full(slot)
      local stack = stack_of and tonumber(stack_of(slot.id))
      if not stack then
        return math.huge
      end
      return stack - (tonumber(slot.count) or 0)
    end

    table.sort(ordered, function(a, b)
      local a_status, b_status = tonumber(a.status) or 0, tonumber(b.status) or 0
      if a_status ~= b_status then
        return a_status > b_status
      end

      local a_gap, b_gap = gap_to_full(a), gap_to_full(b)
      if a_gap ~= b_gap then
        return a_gap < b_gap
      end

      local a_count, b_count = tonumber(a.count) or 0, tonumber(b.count) or 0
      if a_count ~= b_count then
        return a_count > b_count
      end

      return original[a] < original[b]
    end)

    return ordered
  end

  --[[ Both of these are clamped on the way OUT of the config rather than only
       on the way in. The command refuses a bad value, but a hand-edited file,
       a //hud copy import or a config written by an older version can still
       carry one, and neither failure is visible as a mistake: a pitch under
       the square draws the grid as one solid block, and a 500-column bag draws
       a block wider than any screen. ]]
  local function effective_spacing()
    return math.min(MAX_SPACING, math.max(config.slot_size or 1, tonumber(config.spacing) or 0))
  end

  local function effective_block_spacing()
    return math.min(MAX_BLOCK_SPACING, math.max(0, tonumber(config.block_spacing) or 0))
  end

  local function pitch(scale)
    return effective_spacing() * scale
  end

  -- The bag's own settings, which the player switches by GROUP: one word
  -- covers both safes and all eight wardrobes.
  local function settings_for(bag)
    return (config.bags or {})[bag.group] or {}
  end

  local function columns_for(bag)
    return math.min(MAX_COLUMNS, math.max(1, math.floor(tonumber(settings_for(bag).columns) or 1)))
  end

  -- The darker square under each slot, and the brighter one drawn on it. The
  -- difference between the two is the 1px shadow down the right and bottom.
  function self.slot_size(scale)
    return (config.slot_size or 0) * scale
  end

  function self.box_size(scale)
    return (config.box_size or 0) * scale
  end

  local function labels_config()
    return config.labels or {}
  end

  function self.labels_enabled()
    return labels_config().enabled and true or false
  end

  local function label_font_size(scale)
    -- Whole pixels: a fractional font size is not something a prim can draw.
    return math.floor((tonumber(labels_config().font_size) or 0) * scale + 0.5)
  end

  -- What the labels add under the grid: the gap and the line box.
  local function labels_height(scale)
    if not self.labels_enabled() then
      return 0
    end
    return (tonumber(labels_config().gap) or 0) * scale + label_font_size(scale) * TEXT_HEIGHT_RATIO
  end

  -- How wide a block's name draws, estimated from the font: no prim can be
  -- measured. Zero when the labels are off, so nothing is reserved for them.
  function self.label_width(block, scale)
    if not self.labels_enabled() then
      return 0
    end
    -- The same fallback the widget draws with, so what is reserved is what
    -- is written.
    return #tostring(block.label or block.key or "") * label_font_size(scale) * CHARACTER_WIDTH_RATIO
  end

  -- Where a block's name goes: at its left edge, just under its last row.
  -- Bottom-aligned blocks share a foot, so their labels sit on one line.
  function self.label_position(block, scale)
    return {
      x = block.x,
      y = block.y
        + (block.rows - 1) * pitch(scale)
        + self.slot_size(scale)
        + (tonumber(labels_config().gap) or 0) * scale,
      size = label_font_size(scale),
    }
  end

  --[[ The blocks to draw, left to right, for a grid anchored at (x, y).

       `sizes` is how many squares each bag wants, keyed by the catalogue's
       `key`: a bag's capacity for the ordinary ones, and how much is IN it for
       the temporary bag and the treasure pool, which have no capacity worth
       drawing. A bag missing from it, or answering zero, draws no block at all
       - an unbought satchel and an empty pool are not empty space to show.

       The origin is the TOP left and rows run downward, which is the FFXIV
       grid's own direction and not the reference addon's: that one grew
       upward from a bottom anchor, which would draw above the origin the
       framework clamps against. ]]
  function self.layout(sizes, x, y, scale)
    local step = pitch(scale)
    local blocks = {}
    local tallest = 0

    for _, bag in ipairs(BAGS) do
      local slots = math.floor(tonumber((sizes or {})[bag.key]) or 0)
      if slots > 0 and settings_for(bag).enabled then
        local columns = columns_for(bag)
        local rows = math.ceil(slots / columns)
        tallest = math.max(tallest, rows)
        blocks[#blocks + 1] = {
          key = bag.key,
          group = bag.group,
          label = bag.label,
          columns = columns,
          slots = slots,
          rows = rows,
        }
      end
    end

    local offset = 0
    for _, block in ipairs(blocks) do
      block.x = x + offset
      -- Bottom alignment stands blocks of different heights on a common foot,
      -- which is how the reference drew them; it grew every block upward from
      -- one baseline to get there.
      block.y = y + (config.align == "top" and 0 or (tallest - block.rows) * step)
      --[[ A block is as wide as its columns OR its label, whichever is more.
           The temporary bag and the pool ship at one column - 4px - with a
           four-letter name under each on the same line, and nothing about the
           squares would keep the two names off each other. ]]
      local width = math.max(block.columns * step, self.label_width(block, scale))
      offset = offset + width + effective_block_spacing() * scale
    end

    return blocks
  end

  -- Where one slot of a block goes. Slots run left to right across the block's
  -- columns, then down to the next row.
  function self.slot_position(block, index, scale)
    local step = pitch(scale)
    local offset = index - 1
    return {
      x = block.x + (offset % block.columns) * step,
      y = block.y + math.floor(offset / block.columns) * step,
    }
  end

  --[[ The footprint the whole grid takes. The origin is handed straight back:
       core clamps the widget on screen by comparing this with what set_pos was
       given, and layout mode's drag offsets assume the two agree. ]]
  function self.bounds(sizes, x, y, scale)
    local blocks = self.layout(sizes, x, y, scale)
    if #blocks == 0 then
      -- One square rather than nothing: a widget with no bounds cannot be
      -- dragged or right-clicked back on in layout mode, and core has nothing
      -- to clamp it by.
      local square = self.slot_size(scale)
      return x, y, square, square
    end

    local step = pitch(scale)
    local square = self.slot_size(scale)
    local right, bottom = x, y

    for _, block in ipairs(blocks) do
      right = math.max(right, block.x + (block.columns - 1) * step + square, block.x + self.label_width(block, scale))
      bottom = math.max(bottom, block.y + (block.rows - 1) * step + square)
    end

    return x, y, right - x, bottom - y + labels_height(scale)
  end

  function self.wants_chunk(id)
    return HANDLED_CHUNKS[id] == true
  end

  -- The number of ticks a pending read is held for before it is taken anyway.
  function self.hold_limit()
    return HOLD_LIMIT
  end

  --[[ A packet the entry point forwarded, as raw bytes. Nothing here is
       parsed through the packets library: every id below either means "read
       everything again" on its own, or carries the one byte read straight out
       of the chunk. That keeps the component alive when the library is not. ]]
  function self.on_chunk(id, raw)
    if id == ZONE_IN then
      loaded = false
      -- The refill that follows reads the lot, so anything pending from the
      -- old zone is covered by it and would buy one wasted read otherwise.
      dirty = false
      held = 0
      return
    end

    if id == FINISH_INVENTORY then
      --[[ Flag 0 is a single bag of the burst finishing. Only the last one
           releases the hold, and once the bags are in, a bag finishing says
           nothing the packets that moved the item have not already said.

           This reads the same field in the OPPOSITE direction to
           giltracker, deliberately: that component refuses to gate on Flag 1
           because it would leave a pending change unread until the player next
           zoned. Here nothing is gated on it - a change is read on the next
           tick whatever the Flag says - and the only thing Flag 1 releases is
           the post-zone hold, which is exactly the moment giltracker says the
           value arrives. The 600-tick limit above is what covers the two
           readings turning out to disagree in a live client. ]]
      if type(raw) == "string" and raw:byte(FINISH_FLAG_BYTE) == ALL_BAGS_FINISHED then
        loaded = true
        dirty = true
      end
      return
    end

    dirty = true
  end

  -- An item entered or left a bag. Gil has no slot in the grid, and the zero
  -- marker means the slot was empty either way.
  function self.on_item(item_id)
    if not IGNORED_ITEM_IDS[item_id] then
      dirty = true
    end
  end

  -- What is worn changes with the job, and every bag reports it as a status.
  function self.on_job_change()
    dirty = true
  end

  --[[ Something other than a packet changed what would be drawn. A command is
       the only caller: which bags are drawn and how each is ordered are both
       decided at the READ, so repainting alone would leave a bag just switched
       on invisible until an unrelated packet happened to arrive. ]]
  function self.mark_dirty()
    dirty = true
  end

  -- Attaching happens on login, which may be before or after the client has
  -- filled the bags in. Either way there is nothing on screen yet, so read:
  -- an early read comes back empty and the settle that follows reads again.
  function self.on_attach()
    loaded = true
    dirty = true
    held = 0
  end

  -- The character is gone, so the bags this was drawing are too. Nothing is
  -- read again until the next character's own load settles.
  function self.on_logout()
    loaded = false
    dirty = false
    held = 0
  end

  --[[ Whether the widget should read the client on this tick. Every read is a
       full get_items push, so the answer is yes only for a change that has
       actually been announced, and at most once for however many announced
       it. ]]
  function self.should_read()
    if not dirty then
      return false
    end

    if not loaded then
      held = held + 1
      if held < HOLD_LIMIT then
        return false
      end
      --[[ Giving up on the settle is permanent until the next zone. Leaving
           the gate shut would make every later change wait the full count
           again, which is not "one frame late" but ten seconds late for the
           rest of the session - the opposite of what the limit is for. ]]
      loaded = true
    end

    dirty = false
    held = 0
    return true
  end

  -- The settings table itself, so the widget can persist what a command
  -- changed and a spec can see it.
  function self.settings()
    return config
  end

  function self.bag_setting(group)
    return (config.bags or {})[group] or {}
  end

  local function on_off(word)
    local lowered = (word or ""):lower()
    if lowered == "on" then
      return true
    end
    if lowered == "off" then
      return false
    end
    return nil
  end

  -- A whole number inside the range, or nil. tonumber alone would accept
  -- "5.5" and a fractional column count is not something a grid can draw.
  local function bounded_number(word, lowest, highest)
    local value = tonumber(word)
    if not value or value % 1 ~= 0 or value < lowest or value > highest then
      return nil
    end
    return value
  end

  local function report()
    local lines = {
      ("invtracker - sort %s, labels %s, spacing %d, block spacing %d, align %s"):format(
        config.sort == false and "off" or "on",
        self.labels_enabled() and "on" or "off",
        -- The values actually drawn, not the stored ones: a stored value the
        -- clamp threw away must not be the number the player is shown.
        effective_spacing(),
        effective_block_spacing(),
        config.align or "bottom"
      ),
    }

    for _, word in ipairs(BAG_WORDS) do
      local bag = self.bag_setting(word)
      lines[#lines + 1] = ("  %-10s %s, %d columns"):format(word, bag.enabled and "on" or "off", bag.columns or 0)
    end

    return lines
  end

  local function bag_command(group, args)
    local bag = (config.bags or {})[group]
    if not bag then
      return ("invtracker has no settings for the %s"):format(group), false
    end

    local switch = on_off(args[2])
    if switch ~= nil then
      bag.enabled = switch
      return ("invtracker %s %s"):format(group, switch and "on" or "off"), true, true
    end

    if (args[2] or ""):lower() == "columns" then
      local columns = bounded_number(args[3], 1, MAX_COLUMNS)
      if not columns then
        return ("invtracker %s columns takes a number from 1 to %d"):format(group, MAX_COLUMNS), false
      end
      bag.columns = columns
      return ("invtracker %s in %d columns"):format(group, columns), true
    end

    if args[2] == nil then
      -- Named alone, a bag reports itself - the party list's own reading of
      -- `//hud partylist <list>`.
      return ("invtracker %s %s, %d columns"):format(group, bag.enabled and "on" or "off", bag.columns or 0), false
    end

    return ("invtracker %s takes on, off, or columns <1-%d>"):format(group, MAX_COLUMNS), false
  end

  --[[ The `//hud invtracker` line, already split into words. Answers the
       message core prints, whether anything changed - the widget repaints and
       persists on a change, and never on a report - and whether the change
       needs the client READ again: which bags are coloured and how they are
       ordered are decided at the read, so a bag switched on or the sort
       flipped would otherwise draw nothing new until an unrelated packet
       arrived, while a column count or a label is pure geometry and a read is
       a full get_items push.

       Unknown input always answers with what IS understood rather than
       nothing: a silent command is indistinguishable from a broken addon. ]]
  function self.command(args)
    args = args or {}
    local word = (args[1] or ""):lower()

    if word == "" then
      return report(), false
    end

    if word == "sort" then
      local switch = on_off(args[2])
      if switch == nil then
        return "invtracker sort takes on or off", false
      end
      config.sort = switch
      return ("invtracker sort %s"):format(switch and "on" or "off"), true, true
    end

    if word == "labels" then
      local switch = on_off(args[2])
      if switch == nil then
        return "invtracker labels takes on or off", false
      end
      config.labels = config.labels or {}
      config.labels.enabled = switch
      return ("invtracker labels %s"):format(switch and "on" or "off"), true
    end

    if word == "spacing" then
      -- The pitch has to clear the square it carries, or the grid draws as one
      -- solid block with no gaps in it.
      local lowest = math.max(1, math.floor(config.slot_size or 1))
      local spacing = bounded_number(args[2], lowest, MAX_SPACING)
      if not spacing then
        return ("invtracker spacing takes a number from %d to %d"):format(lowest, MAX_SPACING), false
      end
      config.spacing = spacing
      return ("invtracker spacing %d"):format(spacing), true
    end

    if word == "blockspacing" then
      local spacing = bounded_number(args[2], 0, MAX_BLOCK_SPACING)
      if not spacing then
        return ("invtracker blockspacing takes a number from 0 to %d"):format(MAX_BLOCK_SPACING), false
      end
      config.block_spacing = spacing
      return ("invtracker block spacing %d"):format(spacing), true
    end

    if word == "align" then
      local alignment = (args[2] or ""):lower()
      if not ALIGNMENTS[alignment] then
        return "invtracker align takes top or bottom", false
      end
      config.align = alignment
      return ("invtracker align %s"):format(alignment), true
    end

    for _, bag_word in ipairs(BAG_WORDS) do
      if word == bag_word then
        return bag_command(bag_word, args)
      end
    end

    return {
      ("invtracker has no '%s' setting"):format(args[1]),
      "  bags: " .. table.concat(BAG_WORDS, " "),
      "  settings: sort on|off, labels on|off, spacing <px>, blockspacing <px>, align top|bottom",
    },
      false
  end

  function self.set_preview(on)
    preview = on and true or false
  end

  function self.preview()
    return preview
  end

  --[[ The slot counts layout mode draws. `read_sizes` is what the last read of
       the client found, and is preferred wherever it has an answer: it is the
       footprint the widget really takes, and the nominal capacities below would
       otherwise build squares for eight wardrobes nobody owns. They stand in
       only for a character that is not loaded, which is the case layout mode at
       character select actually has. ]]
  function self.preview_sizes(read_sizes)
    if read_sizes and next(read_sizes) then
      return read_sizes
    end

    local sizes = {}
    for _, bag in ipairs(BAGS) do
      if ((config.bags or {})[bag.group] or {}).enabled then
        sizes[bag.key] = PREVIEW_SIZES[bag.key]
      end
    end
    return sizes
  end

  function self.preview_colour(index)
    if index % PREVIEW_EMPTY_EVERY == 0 then
      return "empty"
    end
    return "default"
  end

  -- Everything held in a bag, however the client indexed it. The treasure
  -- pool is keyed by pool slot rather than run 1..n, so ipairs would stop at
  -- the first gap in it.
  local function occupied(bag)
    local contents = {}
    for _, slot in pairs(bag or {}) do
      -- Either field is enough to call the slot occupied. The treasure pool's
      -- entries are not the same shape as a bag's, and a pool that drew
      -- nothing because it carries no count would say nothing about why.
      if type(slot) == "table" and ((tonumber(slot.count) or 0) > 0 or (tonumber(slot.id) or 0) > 0) then
        contents[#contents + 1] = slot
      end
    end
    return contents
  end

  --[[ A bag's capacity and whether the character has it, from either shape
       the client answers in: the top-level `max_<bag>`/`enabled_<bag>` pair,
       and the `max`/`enabled` fields on the bag itself. The reference addon
       reads both - items.max_inventory beside items.storage.max - so neither
       alone can be relied on.

       An absent flag is NOT a refusal. The client not saying is not the client
       saying no, and answering no to a question it never answered is how a
       grid ends up blank with nothing to explain it; a bag the character does
       not have answers a capacity of zero anyway. ]]
  local function capacity_of(items, key)
    local bag = type(items[key]) == "table" and items[key] or {}
    local enabled = items["enabled_" .. key]
    if enabled == nil then
      enabled = bag.enabled
    end
    if enabled == false then
      return 0
    end
    return math.floor(tonumber(items["max_" .. key]) or tonumber(bag.max) or 0)
  end

  local function equipment_colours(worn)
    local colours = {}
    for index, slot in ipairs(EQUIPMENT_SLOTS) do
      colours[index] = (tonumber((worn or {})[slot]) or 0) > 0 and "equipment" or "empty"
    end
    return colours
  end

  --[[ One read of the client turned into what to draw: how many squares each
       bag wants, and the colour of every one of them.

       `items` is the whole get_items() table - the capacities and enabled
       flags come out of the same read as the items themselves, so the grid can
       never be sized from one answer and filled from another. `stack_of`
       answers an item id's stack size, and is nil without the resources
       library, which costs only the full-stack colour. ]]
  function self.read(items, stack_of)
    items = items or {}
    local sizes, colours = {}, {}

    for _, bag in ipairs(BAGS) do
      if ((config.bags or {})[bag.group] or {}).enabled then
        if bag.key == "equipment" then
          if items.equipment then
            sizes.equipment = #EQUIPMENT_SLOTS
            colours.equipment = equipment_colours(items.equipment)
          end
        elseif OCCUPIED_ONLY[bag.key] then
          local contents = occupied(items[bag.key])
          if #contents > 0 then
            sizes[bag.key] = #contents
            colours[bag.key] = {}
            for index = 1, #contents do
              colours[bag.key][index] = "temp_item"
            end
          end
        else
          local capacity = capacity_of(items, bag.key)
          if capacity > 0 then
            local ordered = self.sort(items[bag.key], stack_of)
            sizes[bag.key] = capacity
            colours[bag.key] = {}
            for index = 1, capacity do
              -- A capacity the client has answered is not a promise that the
              -- array behind it has arrived; a slot it has not sent is free
              -- space until it says otherwise.
              colours[bag.key][index] = self.classify(ordered[index], stack_of)
            end
          end
        end
      end
    end

    return { sizes = sizes, colours = colours }
  end

  return self
end

return new
