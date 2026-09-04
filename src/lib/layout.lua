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

--[[ Layout maths, and the repair of the layout table a component's `layout.lua`
     holds:

       { pos = { x = , y = }, scale = , visible = }

     A multi-anchor component (touchpoint 2) declares `anchors` in its layout
     defaults instead, and pos/scale move under the anchor names. `visible`
     stays at the top level for the widget as a whole, and an anchor may carry
     one of its own beside its placement - a second, narrower switch:

       { anchors = { main = { pos = , scale = , visible = } }, visible = }

     The two are read in OPPOSITE directions, and nothing here writes either.
     The widget's must be `true` exactly (a broken file must not switch a whole
     widget on); an anchor's is absent-means-shown, and only an explicit `false`
     hides one - so repair fabricates no per-anchor key, and a component that
     wants an anchor off out of the box says so in its own defaults, which the
     seeding copy carries through.

     The slot itself is a directory, not a key in here - lib/settings resolves
     `data/<Character>/<slot>/<component>/layout.lua` and merges the file over
     the component's layout defaults, so what reaches `repair` is already
     complete except for the shapes a merge cannot fix. Positions are snapped to
     a grid (CTRL frees them) and clamped so a widget can never be dragged off
     screen. ]]

local MIN_SCALE = 0.25

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, item in pairs(value) do
    out[key] = copy(item)
  end
  return out
end

local function new(deps)
  local self = {}

  local function grid()
    local size = deps.snap_size and deps.snap_size() or 0
    return type(size) == "number" and size > 0 and size or nil
  end

  function self.snap(value)
    local size = grid()
    if not size then
      return value
    end
    -- Round half away from zero, so -5 and 5 land on their own grid lines.
    local magnitude = math.floor(math.abs(value) / size + 0.5) * size
    if magnitude == 0 then
      return 0
    end
    return value < 0 and -magnitude or magnitude
  end

  -- Keeps the whole widget on screen. A widget larger than the screen is pinned
  -- to the origin rather than pushed off the top-left.
  function self.clamp(x, y, width, height)
    local screen_width, screen_height = deps.screen()
    local max_x = math.max(0, screen_width - width)
    local max_y = math.max(0, screen_height - height)
    return math.max(0, math.min(x, max_x)), math.max(0, math.min(y, max_y))
  end

  -- Snap first, then clamp: a snap that would push the widget past the screen
  -- edge must not win over the clamp.
  function self.resolve(x, y, width, height, free)
    if not free then
      x, y = self.snap(x), self.snap(y)
    end
    return self.clamp(x, y, width, height)
  end

  function self.clamp_scale(scale)
    if type(scale) ~= "number" then
      return 1
    end
    return math.max(MIN_SCALE, scale)
  end

  -- Repairs one pos/scale-bearing entry in place: `entry` is the layout state
  -- itself for a single-anchor component, or one anchor's table otherwise.
  local function repair_placement(entry, defaults)
    if type(entry.pos) ~= "table" then
      entry.pos = copy(defaults.pos) or { x = 0, y = 0 }
    end
    entry.pos.x = tonumber(entry.pos.x) or 0
    entry.pos.y = tonumber(entry.pos.y) or 0
    if type(entry.scale) ~= "number" then
      entry.scale = tonumber(defaults.scale) or 1
    end
  end

  --[[ Makes `state` - the table lib/settings loaded, merged over `defaults`
       already - usable as a placement, in place: the caller writes this very
       table back. Fixes what a merge cannot, which is a stored value of the
       wrong type, plus the two structural repairs below. ]]
  function self.repair(state, defaults)
    defaults = defaults or {}
    if type(defaults.anchors) == "table" then
      -- A top-level pos/scale on an anchored entry is residue - a hand edit, or
      -- a component that gained anchors after its layout was first written.
      -- Shedding it here means the next save no longer carries it.
      state.pos, state.scale = nil, nil
      if type(state.anchors) ~= "table" then
        state.anchors = {}
      end
      for name, anchor_defaults in pairs(defaults.anchors) do
        -- A default that is not a table is a component authoring bug; it seeds
        -- nothing, and the entry it left behind is dropped below.
        if type(anchor_defaults) == "table" and type(state.anchors[name]) ~= "table" then
          state.anchors[name] = copy(anchor_defaults)
        end
      end
      -- Anchors the defaults do not mention are repaired like any other, so
      -- every entry that survives is a usable placement.
      for name, anchor in pairs(state.anchors) do
        if type(anchor) ~= "table" then
          state.anchors[name] = nil
        else
          local anchor_defaults = defaults.anchors[name]
          repair_placement(anchor, type(anchor_defaults) == "table" and anchor_defaults or {})
        end
      end
    else
      repair_placement(state, defaults)
    end
    -- `visible` is deliberately left as stored: anything that is not `true`
    -- reads as hidden everywhere, rather than being quietly turned back on.
    if state.visible == nil then
      state.visible = defaults.visible ~= false
    end
    return state
  end

  return self
end

return new
