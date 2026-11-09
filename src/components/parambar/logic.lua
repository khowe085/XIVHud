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
-- The player status for engaged, which starts the multi-attack share over.
local ENGAGED = 1
local FULL_TP = 1000
local TP_PER_PERCENT = 10
local FULL_WIDTH = 472
local COMPACT_WIDTH = 421 -- the compact image really is 421px wide
local BACKGROUND_HEIGHT = 24
local FILL_HEIGHT = 8
local DIM_ALPHA = 180
local FULL_ALPHA = 255
-- Where the troughs sit in each background image, from XIVBar's ffxiv theme.
-- They are baked into the art, so they are not settings: a fill moved off
-- them draws beside an empty trough.
local FULL_BARS = { width = 132, spacing = 18 }
local COMPACT_BARS = { width = 116, spacing = 16 }

-- Frame padding baked into the background images, from XIVBar's ui:position.
local BAR_X = { 15, 25, 35 }
local TEXT_X = { 65, 80, 90 }
local INSET_Y = 2

local BARS = { "hp", "mp", "tp" }
local VITALS = { hp = "hp", hpp = "hp", mp = "mp", mpp = "mp", tp = "tp" }

-- XIVParty's bands, strictly less than, on the percent value.
local BANDS = { { 25, "red" }, { 50, "orange" }, { 75, "yellow" } }

local SAMPLE_VITALS = { hp = 1500, hpp = 75, mp = 800, mpp = 50, tp = 1500 }
local SAMPLE_ACCURACY =
  { hits = 7, swings = 9, percent = 78, delay = 2.4, multi_percent = 30, multi_rounds = 3, rounds = 10 }

--[[ The accuracy row is TEXT AND NOTHING ELSE (Kevin, 2026-09-27): it
     carried an `[R]` reset button for a few hours and does not any more, so
     the widget owns no mouse handler at all and `//hud parambar accuracy
     reset` is the only way to empty the window.

     The row is still measured against the WIDEST line it can ever draw
     rather than the one on screen, which is what keeps the box `bounds`
     reports still while the digits move. FOUR digits, since the window runs
     to ten minutes and that is well past a thousand swings on a
     dual-wielding multi-attack job - and a delay as wide as the window
     itself, since the gap between two rounds can be the whole of it. ]]
local WIDEST_ACCURACY = "Acc: 000% (0000/0000) - 000.0s"
local UNKNOWN_DELAY = "--s"
-- Four digits each side: ten thousand rounds is past eight hours of one fight.
local WIDEST_MULTI_ATTACK = "Multi. Attk: 100% (9999/9999)"

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
  local multi_attack_shown = nil
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

  local function multi_attack_enabled()
    return config.multi_attack == true
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

  -- Starts the multi-attack count over, for the `multiattack reset` verb.
  function self.reset_multi_attack()
    accuracy.new_fight()
  end

  --[[ The player's status, every frame. Engaging starts the multi-attack
       share over; leaving it keeps the fight's figure on screen until the
       next one. The last status survives a re-attach, so a slot switch
       mid-fight is engaged to engaged and keeps the count; the first one
       heard after a `//lua reload` is no transition. A player the client has
       not filled a status in for yet says nothing. ]]
  local last_status = nil
  function self.set_status(status)
    if status == nil then
      return
    end
    if status == ENGAGED and last_status ~= nil and last_status ~= ENGAGED then
      accuracy.new_fight()
    end
    last_status = status
  end

  -- Whether the row is drawn. The widget asks outside a tick - on an attach,
  -- a show, a hide - where there is no plan to read it off.
  function self.accuracy_enabled()
    return accuracy_enabled()
  end

  function self.multi_attack_enabled()
    return multi_attack_enabled()
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
    local bars = compact and COMPACT_BARS or FULL_BARS
    return {
      compact = compact,
      bar_width = bars.width,
      spacing = bars.spacing,
      total_width = compact and COMPACT_WIDTH or FULL_WIDTH,
      background = compact and "bar_compact.png" or "bar_bg.png",
    }
  end

  --[[ The accuracy row's own measurements. Every width here is an ESTIMATE:
       Windower cannot be asked how wide a string will draw, so the two
       ratios stand in for it (expbar's approach and its config names) and
       `offset` is the knob for correcting the row in a live client.

       `row_height` is what the whole widget grows by: one line per row
       drawn, `line_gap` between two of them, then `bar_gap` under them.
       The rows are drawn from the widget's origin and the bar art below them, rather than the other way round:
       anything drawn ABOVE the origin would fall outside `get_bounds` and
       defeat core's clamp. The multi-attack row shares every measurement
       here, so its line is the same height and starts at the same x. ]]
  local function accuracy_metrics(scale)
    local lines = (accuracy_enabled() and 1 or 0) + (multi_attack_enabled() and 1 or 0)
    local set = accuracy_config()
    local font = tonumber(set.font_size) or 0
    local height_ratio = tonumber(set.text_height_ratio) or 0
    local width_ratio = tonumber(set.text_width_ratio) or 0
    local bar_gap = tonumber(set.bar_gap) or 0
    -- Floored, so a hand edit cannot stack the rows onto each other.
    local line_gap = math.max(0, tonumber(set.line_gap) or 0)
    local scaled_font = font * scale
    return {
      font_size = math.floor(scaled_font + 0.5),
      offset = tonumber(set.offset) or 0,
      -- The lines' own bands plus the clearances: `bar_gap` lifts the rows
      -- off the bar art and `line_gap` the two rows off each other.
      row_height = math.floor((lines * font * height_ratio + (lines - 1) * line_gap + bar_gap) * scale + 0.5),
      -- From the top of one row to the top of the next.
      line_pitch = math.floor((font * height_ratio + line_gap) * scale + 0.5),
      -- Floored at nothing, so a hand-edited negative font cannot reach
      -- back past the origin, where `bounds` does not cover it.
      readout_width = math.max(0, math.ceil(#WIDEST_ACCURACY * scaled_font * width_ratio)),
      multi_attack_width = math.max(0, math.ceil(#WIDEST_MULTI_ATTACK * scaled_font * width_ratio)),
    }
  end

  -- Where the row starts, measured from the widget's own x: the TP bar's
  -- left edge, since that is the bar the row is about.
  local function accuracy_row_x(metrics, row, scale)
    local step = metrics.bar_width + metrics.spacing
    -- Clamped at the origin: a negative offset pulls the row back rather
    -- than drawing it outside the box `bounds` reports and core clamps.
    return math.max(0, (BAR_X[#BARS] + (#BARS - 1) * step + row.offset) * scale)
  end

  -- How far right the rows reach from the widget's own x: the widest line
  -- either can ever draw.
  local function accuracy_reach(metrics, row, scale)
    local width = 0
    if accuracy_enabled() then
      width = row.readout_width
    end
    if multi_attack_enabled() then
      width = math.max(width, row.multi_attack_width)
    end
    return accuracy_row_x(metrics, row, scale) + width
  end

  local function any_row()
    return accuracy_enabled() or multi_attack_enabled()
  end

  -- Where every prim goes for a widget anchored at (x, y) and drawn at `scale`.
  function self.geometry(x, y, scale)
    local metrics = self.metrics()
    local step = metrics.bar_width + metrics.spacing
    local row = any_row() and accuracy_metrics(scale) or nil
    -- The frame's top, which is the origin only while both rows are off.
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
        x = x + (BAR_X[index] + shift) * scale,
        y = top + INSET_Y * scale,
        height = FILL_HEIGHT * scale,
      }
      geometry.texts[index] = {
        x = x + (TEXT_X[index] + (config.text_offset or 0) + shift) * scale,
        y = top + INSET_Y * scale,
      }
    end

    if row then
      local row_x = x + accuracy_row_x(metrics, row, scale)
      local line_y = y
      if multi_attack_enabled() then
        geometry.multi_attack = { x = row_x, y = line_y, font_size = row.font_size }
        line_y = line_y + row.line_pitch
      end
      if accuracy_enabled() then
        geometry.accuracy = { x = row_x, y = line_y, font_size = row.font_size }
      end
    end

    return geometry
  end

  --[[ The origin is the rows', not the frame's, whenever a row is on - the
       contract is that `get_bounds` hands back the point `set_pos` was
       given, and core clamps against it. The width grows with the readout
       too: at the shipped font the line is wider than the bar art, and a
       box that did not cover it would let the row slide off screen. ]]
  function self.bounds(x, y, scale)
    local metrics = self.metrics()
    local width = metrics.total_width * scale
    local height = BACKGROUND_HEIGHT * scale
    if any_row() then
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

  --[[ `Acc: 78% (7/9) - 2.4s` (Kevin's ordering, 2026-09-28): the figure
       first, then what it was measured over, then the delay. Both readings
       admit to knowing nothing rather than claiming a zero - `--%` until a
       swing has landed, `--s` until two rounds have. ]]
  local function accuracy_line(sample)
    local delay = UNKNOWN_DELAY
    if sample.delay then
      delay = string.format("%.1fs", sample.delay)
    end
    if sample.swings <= 0 or not sample.percent then
      -- Nothing swung is not nought per cent, and the row says so.
      return "Acc: --% (0/0) - " .. delay
    end
    return string.format("Acc: %d%% (%d/%d) - %s", sample.percent, sample.hits, sample.swings, delay)
  end

  -- `Multi. Attk: 30% (3/10)` - rounds, not swings - or `--% (0/0)` until
  -- a round has landed.
  local function multi_attack_line(sample)
    if not sample.multi_percent then
      return "Multi. Attk: --% (0/0)"
    end
    return string.format("Multi. Attk: %d%% (%d/%d)", sample.multi_percent, sample.multi_rounds, sample.rounds)
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
    local multi_line = multi_attack_line(sample)
    plan.multi_attack = { text = multi_line, dirty = multi_line ~= multi_attack_shown }
    multi_attack_shown = multi_line

    return plan
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
       because it is settled by watching the number move in a
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

  -- The row has one setting, its switch, and one action, `reset`; it counts
  -- the whole fight.
  local function set_multi_attack(word)
    if word == nil then
      return string.format(
        "parambar multiattack: %s - %s",
        multi_attack_enabled() and "on" or "off",
        multi_attack_line(preview and SAMPLE_ACCURACY or accuracy.sample(accuracy_sampled_at))
      ),
        false
    end
    local wanted = word:lower()
    if wanted == "reset" then
      -- Nothing is stored, as with the accuracy row's reset.
      self.reset_multi_attack()
      return "parambar multi-attack count reset", false
    end
    if wanted ~= "on" and wanted ~= "off" then
      return string.format("//hud parambar multiattack takes on, off or reset, not '%s'", word), false
    end
    config.multi_attack = wanted == "on"
    mark_all_dirty()
    return "parambar multi-attack row " .. wanted, true
  end

  local function status()
    return string.format(
      "parambar: compact %s, accuracy %s (%gs), multiattack %s",
      compact_mode() and "on" or "off",
      accuracy_enabled() and "on" or "off",
      accuracy.window(),
      multi_attack_enabled() and "on" or "off"
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
    if verb == "compact" then
      return set_compact(args[2])
    end
    if verb == "accuracy" then
      return set_accuracy(args[2], args[3])
    end
    if verb == "multiattack" then
      return set_multi_attack(args[2])
    end
    return string.format("parambar has no '%s' setting (compact, accuracy, multiattack)", args[1]), false
  end

  --[[ The same settings as rows of the `//hud config` window, each naming
       the command above that sets it. Every value is read the way `status`
       reads it: the window from the tracker, which falls back over a stored
       length it refuses. ]]
  function self.config_panel()
    return {
      rows = {
        { label = "Compact", kind = "toggle", value = compact_mode(), command = { "compact" } },
        { label = "Accuracy row", kind = "toggle", value = accuracy_enabled(), command = { "accuracy" } },
        {
          label = "Accuracy window (s)",
          kind = "stepper",
          value = accuracy.window(),
          -- The least whole number of seconds the `window` verb takes.
          min = 1,
          max = accuracy.max_window(),
          step = 5,
          command = { "accuracy", "window" },
        },
        { label = "Multi-attack row", kind = "toggle", value = multi_attack_enabled(), command = { "multiattack" } },
      },
    }
  end

  return self
end

return new
