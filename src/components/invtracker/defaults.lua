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

--[[ Inventory Tracker configuration defaults.

     Keys are snake_case; the invtracker setting each one replaces is named in
     the comments. Position, scale and visibility are framework-owned and live
     in layout slots, so the reference addon's slotImage.pos is gone - the
     default placement below just reproduces its footprint for the first run.

     Which bags start switched on differs from the reference on one point:
     equipment is OFF here. The equip viewer already draws what is worn, in
     item icons rather than blank squares, and every slot drawn costs two
     resident prims. ]]

-- The reference's own geometry: a 3px square carrying a 2px one, on a 4px
-- pitch. The difference between the two squares is the 1px shadow down the
-- right and bottom of every slot.
local SPACING = 4
local BLOCK_SPACING = 4
local SLOT_SIZE = 3
local BOX_SIZE = 2

--[[ The reference anchored the BOTTOM left of its grid 365px in from the right
     of the screen and 50px up from the bottom. Our origin is the top left, so
     the default y comes off the bottom anchor by the height of the tallest
     block a fresh character draws: the inventory, 80 slots in 5 columns, which
     is 16 rows of pitch less the pitch's own trailing gap. ]]
local ANCHOR_FROM_RIGHT = 365
local ANCHOR_FROM_BOTTOM = 50
local DEFAULT_ROWS = 16
local DEFAULT_HEIGHT = (DEFAULT_ROWS - 1) * SPACING + SLOT_SIZE

-- A bag's settings: whether it is drawn, and how wide its block is. Keyed by
-- the catalogue's GROUP, so `safe` covers both safes and `wardrobe` all eight.
local function bag(enabled, columns)
  return { enabled = enabled, columns = columns }
end

-- Builds a fresh defaults table for a screen of the given size.
return function(screen_width, screen_height)
  return {
    sort = true, -- slotImage.sort
    spacing = SPACING, -- slotImage.spacing
    block_spacing = BLOCK_SPACING, -- slotImage.blockSpacing
    slot_size = SLOT_SIZE, -- slotImage.background.size.*
    box_size = BOX_SIZE, -- slotImage.box.size.*
    -- Blocks of different heights stand on a common foot, which is how the
    -- reference drew them: it grew every block upward from one baseline.
    align = "bottom",
    -- The bag's short name under each block, in a font small enough to sit
    -- under a five-column block. Not in the reference; Kevin's, 2026-09-05.
    labels = {
      enabled = true,
      font = "sans-serif",
      font_size = 6,
      bold = false,
      italic = false,
      gap = 1,
      color = { a = 255, r = 200, g = 200, b = 200 },
      stroke = { width = 1, a = 200, r = 0, g = 0, b = 0 },
    },
    bags = {
      equipment = bag(false, 4), -- slotImage.equipment.*
      inventory = bag(true, 5), -- slotImage.inventory.*
      safe = bag(false, 5), -- slotImage.mogSafe.*, covering both safes
      storage = bag(false, 4), -- slotImage.mogStorage.*
      locker = bag(false, 5), -- slotImage.mogLocker.*
      satchel = bag(true, 5), -- slotImage.mogSatchel.*
      sack = bag(true, 5), -- slotImage.mogSack.*
      case = bag(true, 5), -- slotImage.mogCase.*
      wardrobe = bag(false, 5), -- slotImage.mogWardrobe.*, covering all eight
      temporary = bag(true, 1), -- slotImage.tempInventory.*
      treasure = bag(true, 1), -- slotImage.treasury.*
    },
    --[[ Two colours per status: the square itself, and the darker one behind
         it that shows as a 1px shadow. Straight from slotImage.status.*, with
         one addition - the reference drew a status it did not recognise as an
         empty slot, so ours falls back to `default` and there is no colour to
         add for it. ]]
    colours = {
      default = { box = { a = 255, r = 0, g = 170, b = 170 }, shadow = { a = 200, r = 0, g = 60, b = 60 } },
      full_stack = { box = { a = 255, r = 245, g = 40, b = 40 }, shadow = { a = 200, r = 100, g = 0, b = 0 } },
      equipment = { box = { a = 255, r = 253, g = 252, b = 250 }, shadow = { a = 200, r = 50, g = 50, b = 50 } },
      equipped = { box = { a = 255, r = 150, g = 255, b = 150 }, shadow = { a = 200, r = 0, g = 100, b = 0 } },
      linkshell_equipped = {
        box = { a = 255, r = 150, g = 255, b = 150 },
        shadow = { a = 200, r = 0, g = 100, b = 0 },
      },
      bazaar = { box = { a = 255, r = 225, g = 160, b = 30 }, shadow = { a = 200, r = 100, g = 100, b = 0 } },
      temp_item = { box = { a = 255, r = 255, g = 130, b = 255 }, shadow = { a = 200, r = 100, g = 0, b = 100 } },
      empty = { box = { a = 150, r = 0, g = 0, b = 0 }, shadow = { a = 150, r = 0, g = 0, b = 0 } },
    },
    layout = {
      pos = {
        x = math.max(0, (screen_width or 0) - ANCHOR_FROM_RIGHT),
        y = math.max(0, (screen_height or 0) - ANCHOR_FROM_BOTTOM - DEFAULT_HEIGHT),
      },
      scale = 1,
      visible = true,
    },
  }
end
