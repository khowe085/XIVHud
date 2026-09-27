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
          empty while the number still reads full -- and an absolute value the
          client never corrects sticks for the rest of the session. Here 0%
          forces the number to 0, and the vitals arrive already reconciled from
          `lib/player`, which owns that policy for every component.

     Beyond XIVBar: HP and MP numbers are banded by percent (XIVParty's
     thresholds and colours). TP is never banded — its only colouring is the
     full-TP highlight. ]]

local new_accuracy = require("components/parambar/accuracy")

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
local SAMPLE_ACCURACY = { hits = 7, swings = 9, percent = 78 }

--[[ The accuracy row is TEXT AND NOTHING ELSE (Kevin, 2026-09-27): it
     carried an `[R]` reset button for a few hours and does not any more, so
     the widget owns no mouse handler at all and `//hud parambar accuracy
     reset` is the only way to empty the window.

     The row is still measured against the WIDEST line it can ever draw
     rather than the one on screen, which is what keeps the box `bounds`
     reports still while the digits move. FOUR digits, since the window runs
     to ten minutes and that is well past a thousand swings on a
     dual-wielding multi-attack job. ]]
local WIDEST_ACCURACY = "Acc: 0000 / 0000 (000%)"
local EMPTY_ACCURACY = "Acc: 0 / 0 (--%)"

local function zeroed()
  return { hp = 0, hpp = 0, mp = 0, mpp = 0, tp = 0 }
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
  local accuracy_shown = nil
  -- The clock the last tick sampled at, so a command answered between frames
  -- reports the window as the row currently draws it.
  local accuracy_sampled_at = 0

  local function vitals()
    return preview and SAMPLE_VITALS or live
  end

  -- The accuracy block, or an empty stand-in for a hand edit that left it as
  -- something other than a table. Nothing below may index it directly.
  local function accuracy_config()
    local set = config.accuracy
    return type(set) == "table" and set or {}
  end

  -- Strictly true, the framework's rule for a switch: a broken file must not
  -- turn something on.
  local function accuracy_enabled()
    return accuracy_config().enabled == true
  end

  local accuracy = new_accuracy(accuracy_config())

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
    -- Re-pointed rather than rebuilt: the window survives a settings change,
    -- so switching the row off and on again does not throw the swings away.
    accuracy.set_config(accuracy_config())
    mark_all_dirty()
  end

  --[[ One parsed `0x028`, straight through to the window. The widget reads
       the player and the clock; nothing about accuracy is decided here
       except when it is drawn. ]]
  function self.on_action(action, player_id, now)
    accuracy.on_action(action, player_id, now)
  end

  -- Empties the window, for the `accuracy reset` verb.
  function self.reset_accuracy()
    accuracy.reset()
  end

  -- Whether the row is drawn. The widget asks outside a tick - on an attach,
  -- a show, a hide - where there is no plan to read it off.
  function self.accuracy_enabled()
    return accuracy_enabled()
  end

  --[[ The current vitals, as `lib/player` hands them over: the client's own
       numbers with any `hp change` / `hpp change` / … event already laid on top.
       Reconciling the two streams is that service's job, and used to be done
       here - wrongly, until 2026-08-30, when the absolute stream could carry a
       value nothing corrected and an HP number stuck at max HP for the session.

       The widget calls this every frame, so it must be cheap and quiet:
       anything the table is missing goes to zero (this is a replacement, not a
       patch), and only bars whose numbers actually moved are marked dirty, so a
       settled HUD costs nothing. ]]
  function self.set_vitals(player_vitals)
    player_vitals = player_vitals or {}
    for key, bar in pairs(VITALS) do
      local value = tonumber(player_vitals[key]) or 0
      if live[key] ~= value then
        live[key] = value
        dirty[bar] = true
      end
    end
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

  --[[ The accuracy row's own measurements. Every width here is an ESTIMATE:
       Windower cannot be asked how wide a string will draw, so the two
       ratios stand in for it (expbar's approach and its config names) and
       `offset` is the knob for correcting the row in a live client.

       `row_height` is what the whole widget grows by. The row is drawn at
       the widget's origin and the bar art below it, rather than the other
       way round: anything drawn ABOVE the origin would fall outside
       `get_bounds` and defeat core's clamp. ]]
  local function accuracy_metrics(scale)
    local set = accuracy_config()
    local font = tonumber(set.font_size) or 0
    local height_ratio = tonumber(set.text_height_ratio) or 0
    local width_ratio = tonumber(set.text_width_ratio) or 0
    local bar_gap = tonumber(set.bar_gap) or 0
    local scaled_font = font * scale
    return {
      font_size = math.floor(scaled_font + 0.5),
      offset = tonumber(set.offset) or 0,
      -- The line's own band plus the clearance under it: `bar_gap` is what
      -- lifts the row off the bar art.
      row_height = math.floor((font * height_ratio + bar_gap) * scale + 0.5),
      -- Floored at nothing, so a hand-edited negative font cannot reach
      -- back past the origin, where `bounds` does not cover it.
      readout_width = math.max(0, math.ceil(#WIDEST_ACCURACY * scaled_font * width_ratio)),
    }
  end

  -- Where the row starts, measured from the widget's own x: the TP bar's
  -- left edge, since that is the bar the row is about.
  local function accuracy_row_x(metrics, row, scale)
    local step = metrics.bar_width + metrics.spacing
    -- Clamped at the origin: a negative offset pulls the row back rather
    -- than drawing it outside the box `bounds` reports and core clamps.
    return math.max(0, (BAR_X[#BARS] + metrics.offset + (#BARS - 1) * step + row.offset) * scale)
  end

  -- How far right the row reaches from the widget's own x: the widest line
  -- it can ever draw.
  local function accuracy_reach(metrics, row, scale)
    return accuracy_row_x(metrics, row, scale) + row.readout_width
  end

  -- Where every prim goes for a widget anchored at (x, y) and drawn at `scale`.
  function self.geometry(x, y, scale)
    local metrics = self.metrics()
    local step = metrics.bar_width + metrics.spacing
    local row = accuracy_enabled() and accuracy_metrics(scale) or nil
    -- The frame's top, which is the origin only while the row is off.
    local top = y + (row and row.row_height or 0)
    local geometry = {
      background = {
        x = x,
        y = top,
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
        y = top + INSET_Y * scale,
        height = FILL_HEIGHT * scale,
      }
      geometry.texts[index] = {
        x = x + (TEXT_X[index] + (config.text_offset or 0) + shift) * scale,
        y = top + INSET_Y * scale,
      }
    end

    if row then
      geometry.accuracy = { x = x + accuracy_row_x(metrics, row, scale), y = y, font_size = row.font_size }
    end

    return geometry
  end

  --[[ The origin is the row's, not the frame's, whenever the row is on - the
       contract is that `get_bounds` hands back the point `set_pos` was
       given, and core clamps against it. The width grows with the readout
       too: at the shipped font the line is wider than the bar art, and a
       box that did not cover it would let the row slide off screen. ]]
  function self.bounds(x, y, scale)
    local metrics = self.metrics()
    local width = metrics.total_width * scale
    local height = BACKGROUND_HEIGHT * scale
    if accuracy_enabled() then
      local row = accuracy_metrics(scale)
      width = math.max(width, accuracy_reach(metrics, row, scale))
      height = height + row.row_height
    end
    return x, y, width, height
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

  local function accuracy_line(sample)
    if sample.swings <= 0 or not sample.percent then
      -- Nothing swung is not nought per cent, and the row says so.
      return EMPTY_ACCURACY
    end
    return string.format("Acc: %d / %d (%d%%)", sample.hits, sample.swings, sample.percent)
  end

  --[[ The render plan for this frame. `dirty` says whether the bar needs
       pushing to its prims; it clears on the frame the animation converges.
       `now` is the frame clock, and only the accuracy row reads it: the
       window is pruned where it is sampled, so a widget that stops ticking
       stops ageing its swings rather than losing them. ]]
  function self.tick(now)
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

    --[[ The window is sampled whether or not the row is drawn, so switching
         it back on shows what has been happening rather than starting over.
         The line is diffed rather than pushed: the text only moves when a
         swing lands or ages out, which is a handful of frames a fight. ]]
    accuracy_sampled_at = now or 0
    local sample = preview and SAMPLE_ACCURACY or accuracy.sample(accuracy_sampled_at)
    local line = accuracy_line(sample)
    plan.accuracy = { text = line, dirty = line ~= accuracy_shown }
    accuracy_shown = line

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
      return string.format("//hud parambar %s needs a whole number of at least %d", verb, rule.min), false
    end

    local set = compact_mode() and config.compact_bar or config.bar
    if type(set) ~= "table" then
      return "parambar's bar metrics are not a table - try '//hud reset parambar'", false
    end
    set[rule.key] = value
    mark_all_dirty()
    local which = compact_mode() and "compact" or "normal"
    return string.format("parambar %s %s set to %d", which, verb, value), true
  end

  local function set_compact(word)
    local wanted = word and word:lower()
    if wanted ~= "on" and wanted ~= "off" then
      return "//hud parambar compact needs on or off", false
    end
    config.compact = wanted == "on"
    mark_all_dirty()
    return "parambar compact mode " .. wanted, true
  end

  local function accuracy_status()
    return string.format(
      "parambar accuracy: %s, %g second window - %s",
      accuracy_enabled() and "on" or "off",
      accuracy.window(),
      accuracy_line(preview and SAMPLE_ACCURACY or accuracy.sample(accuracy_sampled_at))
    )
  end

  --[[ The accuracy verbs. `window` is a command rather than a file-only key
       for wsgate's reason: it is settled by watching the number move in a
       fight, and alt-tabbing to a text file between readings is the wrong
       loop. The value the CLI refuses is exactly the value the module would
       fall back over, and the length it reports comes from the module, so
       neither can name a number that is not in force.

       `reset` empties the window, and is the only way to: the row carried a
       button for a few hours on 2026-09-27 and is text alone now. ]]
  --[[ A hand edit can leave something other than a table here, and the
       defaults merge cannot repair it (the key exists). A command that
       WRITES repairs it on the way; one that only reports or refuses must
       not, or a refusal would silently discard what is in the file and
       return `changed = false`, leaving memory and disk disagreeing until
       some unrelated write. ]]
  local function writable_accuracy()
    local set = config.accuracy
    if type(set) ~= "table" then
      set = {}
      config.accuracy = set
      accuracy.set_config(set)
    end
    return set
  end

  local function set_accuracy(word, value)
    if word == nil then
      return accuracy_status(), false
    end

    word = word:lower()
    if word == "on" or word == "off" then
      writable_accuracy().enabled = word == "on"
      mark_all_dirty()
      return "parambar accuracy row " .. word, true
    end

    if word == "reset" then
      -- Nothing is stored, so there is nothing to save and nothing to
      -- repair on the way - which keeps a hand-broken config block
      -- untouched where a refusal would otherwise discard it.
      self.reset_accuracy()
      return "parambar accuracy window reset", false
    end

    if word == "window" then
      local seconds = whole_number(value)
      local longest = accuracy.max_window()
      if not seconds or seconds <= 0 or seconds > longest then
        -- Bounded like the statusbar's rows and the invtracker's columns:
        -- every swing inside the window is held in memory, and a window
        -- nothing ever prunes is a session-long list.
        return string.format("//hud parambar accuracy window needs a whole number of seconds, 1 to %d", longest), false
      end
      writable_accuracy().window_seconds = seconds
      return string.format("parambar accuracy window set to %d seconds", seconds), true
    end

    -- `word` is the one that was not understood; `value` is whatever came
    -- after it, and naming that instead would point at the wrong thing.
    return string.format("//hud parambar accuracy takes on, off, reset or window <seconds>, not '%s'", word), false
  end

  local function status()
    local metrics = self.metrics()
    return string.format(
      "parambar: width %d, spacing %d, offset %d, compact %s, accuracy %s (%gs)",
      metrics.bar_width,
      metrics.spacing,
      metrics.offset,
      metrics.compact and "on" or "off",
      accuracy_enabled() and "on" or "off",
      accuracy.window()
    )
  end

  -- `//hud parambar ...`. Returns the line to print and whether anything
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
    if verb == "accuracy" then
      return set_accuracy(args[2], args[3])
    end
    return string.format("parambar has no '%s' setting (width, spacing, offset, compact, accuracy)", args[1]), false
  end

  return self
end

return new
