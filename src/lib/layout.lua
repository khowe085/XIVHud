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

--[[ Layout maths and the per-slot state stored in each component's own config.

     A component's layout state lives under a named slot:

       slots = { default = { pos = { x = , y = }, scale = , visible = } }

     `default` always exists and is the seed for any slot the user creates
     later. Positions are snapped to a grid (CTRL frees them) and clamped so a
     widget can never be dragged off screen. ]]

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

  -- The state table for `slot_name`, created on first use: seeded from the
  -- `default` slot when there is one, otherwise from the component's defaults.
  -- Individual missing keys are repaired the same way.
  function self.slot(config, slot_name, defaults)
    if type(config.slots) ~= "table" then
      config.slots = {}
    end

    local state = config.slots[slot_name]
    if type(state) ~= "table" then
      state = copy(config.slots.default)
      if type(state) ~= "table" then
        state = {}
      end
      config.slots[slot_name] = state
    end

    defaults = defaults or {}
    if type(state.pos) ~= "table" then
      state.pos = copy(defaults.pos) or { x = 0, y = 0 }
    end
    state.pos.x = tonumber(state.pos.x) or 0
    state.pos.y = tonumber(state.pos.y) or 0
    if type(state.scale) ~= "number" then
      state.scale = tonumber(defaults.scale) or 1
    end
    -- `visible` is deliberately left as stored: anything that is not `true`
    -- reads as hidden everywhere, rather than being quietly turned back on.
    if state.visible == nil then
      state.visible = defaults.visible ~= false
    end
    return state
  end

  -- Creates `name` as a copy of the `source` slot's state. Falls back to the
  -- default slot, then to the component's own defaults, so a component that has
  -- never seen the source slot still gets something sensible. nil when `name`
  -- is already taken — the caller decides what to say about that.
  function self.create_slot(config, name, source, defaults)
    config.slots = config.slots or {}
    if config.slots[name] then
      return nil
    end

    local seed = config.slots[source]
    if seed then
      config.slots[name] = copy(seed)
    end
    return self.slot(config, name, defaults)
  end

  -- Reports whether there was anything to delete. Refusing to delete `default`
  -- or the active slot is a command-level decision, not this function's.
  function self.delete_slot(config, name)
    if not config.slots or not config.slots[name] then
      return false
    end
    config.slots[name] = nil
    return true
  end

  -- `default` first (it is the one slot that always exists), then the rest
  -- alphabetically, so `//xh slot list` reads the same way every time.
  function self.slot_names(config)
    local slots = type(config.slots) == "table" and config.slots or {}
    local names = {}
    for name in pairs(slots) do
      -- A slot name has to be typeable as a command word; a hand-edited config
      -- can hold anything, and a mixed-type list is not even sortable.
      if type(name) == "string" and name ~= "default" then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    if slots.default ~= nil then
      table.insert(names, 1, "default")
    end
    return names
  end

  return self
end

return new
