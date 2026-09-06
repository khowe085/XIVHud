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

--[[ The hotbar's geometry over the shared slot render (lib/actionbar/render):
     ten slots in one of four shapes - 10x1, 5x2, 2x5 or 1x10 (Kevin,
     2026-09-06), the statusbar's rows-by-columns scheme - with the set
     number before slot 1. Slots run ROW-MAJOR in every shape: 5x2 is 1-5
     across the top and 6-10 across the bottom, 1x10 has slot 1 at the top,
     which is XIV's own numbering of a reshaped hotbar and keeps `3:7` naming
     the same binding whatever shape bar 3 is drawn in.

     Frames of reference: every position is unscaled and relative to the
     row's anchor origin - its top-left, which is also what bounds()
     describes, so core's clamp holds by construction. The widget applies
     origin + uniform scale. Everything a slot draws regardless of where it
     sits is the shared module's, re-exported here so hotbar.lua reads one
     instance. ]]

local new_shared = require("lib/actionbar/render")

-- The four shapes, keyed by row count (the statusbar's own scheme).
local COLUMNS_BY_ROWS = { [1] = 10, [2] = 5, [5] = 2, [10] = 1 }
local SLOT_COUNT = 10
-- The set number: parambar's size and the crossbar's set label's, one digit
-- wide with a gap before the grid. On the wide shapes it stands left of
-- slot 1, on the tall ones above it - where XIV puts a hotbar's number in
-- each orientation.
local LABEL_SIZE = 14
local LABEL_WIDTH = 12
local LABEL_GAP = 4
--[[ The band under a row of slots that the action names draw in: the shared
     render puts a slot's name at y + 40 in the bar's font (7pt, about ten
     pixels tall), and the crossbar's panel art reserves 49px under its grid
     for the same reason. Every row pitch and every footprint here includes
     it, or row N's names would draw over row N+1's slots and a row dragged
     to the screen foot would have them clipped. ]]
local NAME_BAND = 10
-- The gap between two stacked rows at the shipped 10x1, so eight rows sit
-- in a column without touching.
local STACK_GAP = 8

local function new(deps)
  local config = deps.config
  local shared = new_shared({ config = config, icon_for = deps.icon_for })
  local SLOT = shared.slot_size()
  local self = {}

  -- The shared slot render's surface, one instance per bar: the sweep
  -- maxima and the chain animation are state, so the widget must read them
  -- off the same object its slots draw with.
  self.slot_size = shared.slot_size
  self.slot_label = shared.slot_label
  self.clear_sweep = shared.clear_sweep
  self.sweep = shared.sweep
  self.chain_tick = shared.chain_tick
  self.text_offsets = shared.text_offsets
  self.cost = shared.cost
  self.slot_alpha = shared.slot_alpha
  self.feedback_fade = shared.feedback_fade
  self.icon_candidates = shared.icon_candidates
  self.remaining_for = shared.remaining_for
  self.recast_label = shared.recast_label

  function self.columns_for(rows)
    return COLUMNS_BY_ROWS[rows]
  end

  function self.slot_count()
    return SLOT_COUNT
  end

  function self.label_size()
    return LABEL_SIZE
  end

  local function wide(rows)
    return rows == 1 or rows == 2
  end

  --- One shape's numbers: where the grid starts inside the row's origin,
  --- and the pitch its slots sit on. nil for a row count that is not a shape.
  function self.metrics(rows)
    local columns = COLUMNS_BY_ROWS[rows]
    if columns == nil then
      return nil
    end
    local pitch = SLOT + config.slot_spacing
    return {
      slot = SLOT,
      -- Columns sit on the slot pitch; rows leave the name band between them.
      pitch = pitch,
      row_pitch = pitch + NAME_BAND,
      name_band = NAME_BAND,
      rows = rows,
      columns = columns,
      grid_x = wide(rows) and (LABEL_WIDTH + LABEL_GAP) or 0,
      grid_y = wide(rows) and 0 or (LABEL_SIZE + LABEL_GAP),
    }
  end

  -- Top-left of a slot, unscaled, relative to the row's origin; nil for a
  -- slot or a shape that does not exist.
  function self.slot_pos(rows, slot, metrics)
    metrics = metrics or self.metrics(rows)
    if metrics == nil or type(slot) ~= "number" or slot < 1 or slot > SLOT_COUNT then
      return nil
    end
    local index = slot - 1
    local column = index % metrics.columns
    local row = math.floor(index / metrics.columns)
    return metrics.grid_x + column * metrics.pitch, metrics.grid_y + row * metrics.row_pitch
  end

  --- The set number's top-left: left of slot 1 on a wide shape, centred on
  --- the slot's height; above it on a tall one.
  function self.label_pos(rows)
    if COLUMNS_BY_ROWS[rows] == nil then
      return nil
    end
    if wide(rows) then
      return 0, math.floor((SLOT - LABEL_SIZE) / 2)
    end
    return 0, 0
  end

  --- The row's footprint at the given scale: label, every slot and the name
  --- band under the last row, from the origin.
  function self.bounds(rows, scale)
    local metrics = self.metrics(rows)
    if metrics == nil then
      return nil
    end
    scale = scale or 1
    local width = metrics.grid_x + (metrics.columns - 1) * metrics.pitch + SLOT
    local height = metrics.grid_y + (rows - 1) * metrics.row_pitch + SLOT + NAME_BAND
    return width * scale, height * scale
  end

  --- The distance between two stacked rows at the shipped shape, for the
  --- defaults' column of eight.
  function self.row_pitch()
    local _, height = self.bounds(1)
    return height + STACK_GAP
  end

  --[[ Where every slot currently on screen is, in SCREEN coordinates. The
       caller passes the rows it is actually drawing - each with the anchor
       placement it is drawn at and the set it addresses - and gets one rect
       per slot back, in the order the rows were given. `side` is always
       `row`: the hotbar's grammar has one side. ]]
  function self.slot_rects(groups)
    local rects = {}
    for _, group in ipairs(groups or {}) do
      local metrics = self.metrics(group.rows)
      if metrics ~= nil then
        for slot = 1, SLOT_COUNT do
          local x, y = self.slot_pos(group.rows, slot, metrics)
          rects[#rects + 1] = {
            x = group.x + x * group.scale,
            y = group.y + y * group.scale,
            width = SLOT * group.scale,
            height = SLOT * group.scale,
            key = group.key,
            set = group.set,
            side = "row",
            slot = slot,
          }
        end
      end
    end
    return rects
  end

  -- The slot under a point, over this bar's own rects: the shared render's
  -- one hit-test, fed the geometry it cannot know.
  function self.slot_at(groups, x, y, accept)
    if type(x) ~= "number" or type(y) ~= "number" then
      return nil
    end
    return shared.slot_at(self.slot_rects(groups), x, y, accept)
  end

  return self
end

return new
