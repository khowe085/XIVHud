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

--[[ Parameter Bar state machine: vitals in, a per-frame render plan out.

     No prims and no Windower here — parambar.lua turns the plan into prim
     calls. Behaviour follows XIVBar (fill widths, exponential ease-out, the
     full-TP highlight) with its known bugs fixed:

       1. XIVBar clears the wrong dirty flag for HP, so its HP bar re-eases
          every frame forever. Flags here are keyed by bar.
       2. XIVBar's DimTpBar else-branch runs for all three bars, dimming HP and
          MP as a side effect. Dimming is TP-only here.
       3. XIVBar's compact width is 422 against a 421px image.
       4. XIVBar renders the bar from the percent stream and the number from the
          absolute stream and never reconciles them, so on death the bar can
          empty while the number still reads full. Here 0% forces the number to
          0, and a status change re-seeds both streams from the player.

     Beyond XIVBar: HP and MP numbers are banded by percent (XIVParty's
     thresholds and colours). TP is never banded — its only colouring is the
     full-TP highlight. ]]

local EASE = 0.1
local FULL_TP = 1000
local TP_PER_PERCENT = 10
local FULL_WIDTH = 472
local COMPACT_WIDTH = 421 -- the compact image really is 421px wide
local BACKGROUND_HEIGHT = 24
local FILL_HEIGHT = 8
local DIM_ALPHA = 180
local FULL_ALPHA = 255
local MIN_BAR_WIDTH = 8

-- Frame padding baked into the background images, from XIVBar's ui:position.
local BAR_X = { 15, 25, 35 }
local TEXT_X = { 65, 80, 90 }
local INSET_Y = 2

local BARS = { "hp", "mp", "tp" }
local VITALS = { hp = "hp", hpp = "hp", mp = "mp", mpp = "mp", tp = "tp" }

-- XIVParty's bands, strictly less than, on the percent value.
local BANDS = { { 25, "red" }, { 50, "orange" }, { 75, "yellow" } }

local SAMPLE_VITALS = { hp = 1500, hpp = 75, mp = 800, mpp = 50, tp = 1500 }

local function zeroed()
  return { hp = 0, hpp = 0, mp = 0, mpp = 0, tp = 0 }
end

local function all_unknown()
  return { hp = true, hpp = true, mp = true, mpp = true, tp = true }
end

local function band_for(percent)
  for _, band in ipairs(BANDS) do
    if percent < band[1] then
      return band[2]
    end
  end
  return "normal"
end

local function rgb(color)
  color = color or {}
  return { r = color.r or 0, g = color.g or 0, b = color.b or 0 }
end

-- Deliberately stricter than tonumber, which also accepts "0x84" and "1e2".
local function whole_number(word)
  if type(word) ~= "string" or not word:match("^%-?%d+$") then
    return nil
  end
  return tonumber(word)
end

local function new(config)
  local self = {}
  local live = zeroed()
  local preview = false
  local widths = { hp = 0, mp = 0, tp = 0 }
  local dirty = { hp = true, mp = true, tp = true }
  -- Vitals the client has never given a real number for, as opposed to ones it
  -- has said are zero. Only these are open to fill_missing. Every vital starts
  -- here: the widget can be attached with get_player() unreadable, in which case
  -- the seed never runs and the fill is the only thing that will fill the bars.
  local unknown = all_unknown()

  local function vitals()
    return preview and SAMPLE_VITALS or live
  end

  local function mark_all_dirty()
    for _, key in ipairs(BARS) do
      dirty[key] = true
    end
  end

  -- Forces the next tick to re-push every bar. The widget calls this after a
  -- layout change: fill sizes are only written by render(), so a scale change
  -- would otherwise leave the fills at the previous scale until a vital moved.
  function self.invalidate()
    mark_all_dirty()
  end

  function self.set_config(new_config)
    config = new_config
    mark_all_dirty()
  end

  -- Full re-seed from windower.ffxi.get_player().vitals. Anything the table is
  -- missing goes to zero: this is a replacement, not a patch.
  function self.seed(player_vitals)
    player_vitals = player_vitals or {}
    live = zeroed()
    unknown = all_unknown()
    for key in pairs(live) do
      live[key] = tonumber(player_vitals[key]) or 0
      if live[key] ~= 0 then
        unknown[key] = nil
      end
    end
    mark_all_dirty()
  end

  -- Whether any vital is still waiting for its first real number. The widget
  -- stops re-reading the player as soon as this goes false.
  function self.awaiting_vitals()
    return next(unknown) ~= nil
  end

  -- Fills in vitals the client has never given a number for, from a fresh read
  -- of the player. It populates its vitals table field by field, so a bar can
  -- still be waiting for its first real number while its neighbours are current.
  -- Unlike seed() this cannot walk over a change event: a vital an event drove
  -- to zero is a vital the client has spoken for, and stays where it was put.
  function self.fill_missing(player_vitals)
    player_vitals = player_vitals or {}
    for key, bar in pairs(VITALS) do
      if unknown[key] then
        local value = tonumber(player_vitals[key]) or 0
        if value ~= 0 then
          live[key] = value
          unknown[key] = nil
          dirty[bar] = true
        end
      end
    end
  end

  -- One value from an `hp change` / `hpp change` / … event.
  function self.set_vital(kind, value)
    local bar = VITALS[kind]
    if not bar then
      return
    end
    live[kind] = tonumber(value) or 0
    -- The client has now spoken for this vital, zero or not.
    unknown[kind] = nil
    dirty[bar] = true
  end

  function self.set_preview(on)
    on = on and true or false
    if on == preview then
      return
    end
    preview = on
    mark_all_dirty()
  end

  function self.preview()
    return preview
  end

  -- TP runs 0..3000 but the bar is full at 1000.
  function self.tpp()
    return math.min(vitals().tp / TP_PER_PERCENT, 100)
  end

  local function compact_mode()
    return config.compact == true
  end

  function self.metrics()
    local compact = compact_mode()
    local set = compact and config.compact_bar or config.bar
    -- The defaults merge lets a hand-edited user value win, table or not.
    if type(set) ~= "table" then
      set = {}
    end
    return {
      compact = compact,
      bar_width = set.width or 0,
      spacing = set.spacing or 0,
      offset = set.offset or 0,
      total_width = compact and COMPACT_WIDTH or FULL_WIDTH,
      background = compact and "bar_compact.png" or "bar_bg.png",
    }
  end

  -- Where every prim goes for a widget anchored at (x, y) and drawn at `scale`.
  function self.geometry(x, y, scale)
    local metrics = self.metrics()
    local step = metrics.bar_width + metrics.spacing
    local geometry = {
      background = {
        x = x,
        y = y,
        width = metrics.total_width * scale,
        height = BACKGROUND_HEIGHT * scale,
      },
      bars = {},
      texts = {},
      -- Whole pixels: a fractional font size is not something a prim can draw.
      font_size = math.floor((config.font_size or 0) * scale + 0.5),
      fill_height = FILL_HEIGHT * scale,
      fill_width = function(width)
        return width * scale
      end,
    }

    for index = 1, #BARS do
      local shift = (index - 1) * step
      geometry.bars[index] = {
        x = x + (BAR_X[index] + metrics.offset + shift) * scale,
        y = y + INSET_Y * scale,
        height = FILL_HEIGHT * scale,
      }
      geometry.texts[index] = {
        x = x + (TEXT_X[index] + (config.text_offset or 0) + shift) * scale,
        y = y + INSET_Y * scale,
      }
    end

    return geometry
  end

  function self.bounds(x, y, scale)
    local metrics = self.metrics()
    return x, y, metrics.total_width * scale, BACKGROUND_HEIGHT * scale
  end

  -- One eased step towards the target width, XIVBar's exponential ease-out.
  -- `math.ceil` guarantees it converges instead of creeping asymptotically.
  local function ease(key, target, bar_width)
    local old = widths[key]
    if old == target then
      dirty[key] = false
      return old, old == 0
    end
    if old < target then
      widths[key] = math.min(old + math.ceil((target - old) * EASE), bar_width)
    else
      widths[key] = math.max(old - math.ceil((old - target) * EASE), 0)
    end
    return widths[key], false
  end

  -- 0% means dead, whatever the absolute stream last reported.
  local function displayed(bar)
    local current = vitals()
    if bar == "hp" then
      return current.hpp == 0 and 0 or current.hp
    elseif bar == "mp" then
      return current.mpp == 0 and 0 or current.mp
    end
    return current.tp
  end

  local function color_state(bar)
    local current = vitals()
    if bar == "tp" then
      return current.tp >= FULL_TP and "full_tp" or "normal"
    end
    return band_for(bar == "hp" and current.hpp or current.mpp)
  end

  local function color_for(bar, state)
    if state == "full_tp" then
      return rgb(config.full_tp_color)
    elseif state == "normal" then
      return rgb(config.text_color)
    end
    local palette = bar == "hp" and config.low_hp_colors or config.low_mp_colors
    return rgb((palette or {})[state])
  end

  local function alpha_for(bar, state)
    if bar ~= "tp" or config.dim_tp_bar ~= true then
      return FULL_ALPHA
    end
    return state == "full_tp" and FULL_ALPHA or DIM_ALPHA
  end

  local function percent(bar)
    local current = vitals()
    if bar == "hp" then
      return current.hpp
    elseif bar == "mp" then
      return current.mpp
    end
    return self.tpp()
  end

  -- The render plan for this frame. `dirty` says whether the bar needs pushing
  -- to its prims; it clears on the frame the animation converges.
  function self.tick()
    local metrics = self.metrics()
    local plan = {}

    for _, bar in ipairs(BARS) do
      local was_dirty = dirty[bar]
      local target = math.floor((percent(bar) / 100) * metrics.bar_width)
      local width, hidden

      if was_dirty then
        width, hidden = ease(bar, target, metrics.bar_width)
      else
        width, hidden = widths[bar], widths[bar] == 0
      end

      local state = color_state(bar)
      plan[bar] = {
        width = width,
        hidden = hidden,
        dirty = was_dirty,
        text = tostring(displayed(bar)),
        color_state = state,
        color = color_for(bar, state),
        alpha = alpha_for(bar, state),
      }
    end

    return plan
  end

  local METRIC_VERBS = {
    width = { key = "width", min = MIN_BAR_WIDTH },
    spacing = { key = "spacing", min = 0 },
    offset = { key = "offset", min = 0 },
  }

  local function set_metric(verb, word)
    local rule = METRIC_VERBS[verb]
    local value = whole_number(word)
    if not value or value < rule.min then
      return string.format("//xh parambar %s needs a whole number of at least %d", verb, rule.min), false
    end

    local set = compact_mode() and config.compact_bar or config.bar
    if type(set) ~= "table" then
      return "parambar's bar metrics are not a table - try '//xh reset parambar'", false
    end
    set[rule.key] = value
    mark_all_dirty()
    local which = compact_mode() and "compact" or "normal"
    return string.format("parambar %s %s set to %d", which, verb, value), true
  end

  local function set_compact(word)
    local wanted = word and word:lower()
    if wanted ~= "on" and wanted ~= "off" then
      return "//xh parambar compact needs on or off", false
    end
    config.compact = wanted == "on"
    mark_all_dirty()
    return "parambar compact mode " .. wanted, true
  end

  local function status()
    local metrics = self.metrics()
    return string.format(
      "parambar: width %d, spacing %d, offset %d, compact %s",
      metrics.bar_width,
      metrics.spacing,
      metrics.offset,
      metrics.compact and "on" or "off"
    )
  end

  -- `//xh parambar ...`. Returns the line to print and whether anything
  -- changed, so the widget knows when to re-lay out and save.
  function self.command(args)
    args = args or {}
    local verb = args[1] and args[1]:lower() or nil
    if not verb then
      return status(), false
    end
    if METRIC_VERBS[verb] then
      return set_metric(verb, args[2])
    end
    if verb == "compact" then
      return set_compact(args[2])
    end
    return string.format("parambar has no '%s' setting (width, spacing, offset, compact)", args[1]), false
  end

  return self
end

return new
