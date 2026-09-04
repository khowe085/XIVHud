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

--[[ Exp Bar state machine: packets and the player in, a render plan out.

     No prims and no Windower here - expbar.lua turns the plan into prim calls.
     The point tracking is re-implemented from the `pointwatch` addon
     (Copyright (c) 2014, Byrthnoth, BSD 3-clause) with the bar drawn the way
     `barfiller` draws it (Copyright (c) 2015, Morath86, BSD 3-clause); both
     notices are reproduced in full in this directory's LICENSE.txt.

     The client answers almost none of this: `get_player()` carries no
     experience and no master level, so everything but the job pair and the job
     points arrives as packets - 0x061 for experience and exemplar points,
     0x063 order 2 for limit points and merits, and 0x02D for every gain in
     between. ]]

local CHAR_STATS = 0x061
local CHAR_UPDATE = 0x063
local ACTION_MESSAGE = 0x02D

local HANDLED_CHUNKS = {
  [CHAR_STATS] = true,
  [CHAR_UPDATE] = true,
  [ACTION_MESSAGE] = true,
}

local LEVEL_CAP = 99
local SECONDS_PER_HOUR = 3600

--[[ pointwatch's rate: a {timestamp = points} registry pruned at ten minutes,
     extrapolated from the age of its oldest surviving sample. It counts idle
     time inside the window, so the figure decays while nothing is earned -
     that is the behaviour these addons are read for, and it is kept. A window
     younger than the minimum answers 0 rather than a wild extrapolation off a
     couple of seconds. ]]
local RATE_WINDOW = 600
local RATE_MINIMUM = 30
-- Walking the registry sixty times a second is pointless: nothing here moves
-- fast enough to read differently between one frame and the next.
local RATE_INTERVAL = 1

--[[ Which stream the header quotes, per mode: the rate names what the player
     is EARNING, which is what makes a sub-99 character read EXP/hr instead of
     a capacity rate stuck at zero (Kevin, 2026-09-04).

     It is the same quantity the bar draws in two modes of three. At the cap
     without master levels they part company on purpose: the bar fills with
     limit points, as the game's own does, while the header quotes capacity -
     which is Kevin's non-ML template, and the reason there is no LP registry
     to quote instead. ]]
local RATE_FOR_MODE = { exp = "exp", limit = "cp", ep = "ep" }
local RATE_LABEL = { exp = "EXP", limit = "CP", ep = "EP" }
-- pointwatch's own rounding: hundreds, shown as tenths of a thousand.
local RATE_UNIT = 100
local NO_SUBJOB = "---"
-- Job id 0. The client is understood to answer this rather than leave the field
-- out, so both spellings of "no subjob" are read.
local EMPTY_JOB = "non"

-- barfiller's animation: one exponential step per frame toward the target,
-- with the ceiling guaranteeing it converges instead of creeping.
local EASE = 0.1

-- What layout mode draws before a character has earned anything: the header at
-- its widest and a bar with something in it, so the widget can be placed.
local SAMPLE = {
  header = "WAR99/SAM49 (ML23) JP: 342 MP: 12 EP/hr: 12.6k",
  mode = "ep",
  percent = 0.6,
}

local MODE_NAMES = { exp = "experience", limit = "limit points", ep = "exemplar points" }

-- The job the sample header names, so layout mode draws an icon too.
local SAMPLE_JOB = "WAR"
-- Limit points per merit point, and the order of 0x063 that carries them.
local LIMIT_PER_MERIT = 10000
local LIMIT_POINT_ORDER = 2

--[[ Every point gain arrives as a 0x02D action message, and WHICH parameter
     carries the amount is not uniform: the `action_messages` resource renders
     105 and 735 with `${number2}`, so their points are in Param 2. Both
     reference addons read Param 1 for all of them, which makes pointwatch's
     capacity rate count chain numbers instead of points. 253 (the experience
     chain) is barfiller's - pointwatch has no entry for it at all, so it misses
     most of the experience earned in a party. ]]
local GAINS = {
  [8] = { kind = "exp", param = 1 },
  [105] = { kind = "exp", param = 2 },
  [253] = { kind = "exp", param = 1 },
  [371] = { kind = "limit", param = 1 },
  [372] = { kind = "limit", param = 1 },
  [718] = { kind = "cp", param = 1 },
  [735] = { kind = "cp", param = 2 },
  -- 809/810 are pointwatch's; they are past the end of the resource file, so
  -- nothing but that addon vouches for them (see the plan's unverified list).
  [809] = { kind = "ep", param = 1 },
  [810] = { kind = "ep", param = 2 },
}

local function new_registry()
  local samples = {}
  local registry = {}

  function registry.add(now, points)
    if now == nil or points <= 0 then
      return
    end
    samples[now] = (samples[now] or 0) + points
  end

  -- Pruning happens here rather than on a clock of its own: nothing else walks
  -- the table, so a sample that has aged out costs nothing until it is read.
  function registry.rate(now)
    local total, oldest = 0, 0
    for stamp, points in pairs(samples) do
      local age = now - stamp
      if age > RATE_WINDOW then
        samples[stamp] = nil
      else
        total = total + points
        if age > oldest then
          oldest = age
        end
      end
    end
    if oldest < RATE_MINIMUM then
      return 0
    end
    return math.floor(total / oldest * SECONDS_PER_HOUR)
  end

  function registry.clear()
    samples = {}
  end

  return registry
end

local function new(config)
  local self = {}

  local player = nil
  local exp = { current = 0, required = 0 }
  local ep = { current = 0, required = 0, master_level = 0, master_breaker = false }
  local limit = { current = 0, merits = 0, max_merits = 0 }
  local registries = { exp = new_registry(), cp = new_registry(), ep = new_registry() }
  local rates = { exp = 0, cp = 0, ep = 0 }
  local rates_at = nil
  local preview = false
  local width = 0
  local last_mode = nil
  local forced = true

  local function whole(value)
    return math.floor(tonumber(value) or 0)
  end

  --[[ `Master Breaker` is a boolbit, so the packets library answers a boolean -
       but a raw or hand-rolled decode would answer 0 or 1, and 0 is truthy in
       Lua. Both forms are read, and neither is trusted to be a boolean. ]]
  local function flag(value)
    if value == true then
      return true
    end
    return (tonumber(value) or 0) ~= 0
  end

  function self.wants_chunk(id)
    return HANDLED_CHUNKS[id] == true
  end

  -- The client's own view of the player, pushed every frame by the widget.
  function self.set_player(current)
    player = current
  end

  --[[ Which quantity the bar is filling with. The level comes from the client
       rather than from 0x061's own `Main Job Level`, so a job change moves the
       bar without waiting for a packet. ]]
  function self.mode()
    local level = player and tonumber(player.main_job_level) or 0
    if level < LEVEL_CAP then
      return "exp"
    end
    return ep.master_breaker and "ep" or "limit"
  end

  function self.master_level()
    return ep.master_level
  end

  function self.merits()
    return limit.merits
  end

  -- The rate behind the header's last line, for the mode the bar is in.
  function self.rate()
    return rates[RATE_FOR_MODE[self.mode()]] or 0
  end

  --[[ The client keys `job_points` by the short job name lowercased, which is
       what the wiki documents - but pointwatch indexes the 0x063 packet by the
       full name, so both spellings are tried. Neither found answers 0: a wrong
       guess should cost a zero, not a crash inside the render loop. ]]
  local function job_points()
    local points = player and player.job_points
    if type(points) ~= "table" then
      return 0
    end
    local entry = points[tostring(player.main_job or ""):lower()]
      or points[tostring(player.main_job_full or ""):lower()]
    if type(entry) ~= "table" then
      return 0
    end
    return whole(entry.jp)
  end

  --[[ The status line above the bar. Two shapes, differing only in the master
       level: Kevin's templates, with the job levels added (2026-09-04) because
       nothing else on the widget says what level you are, and the rate always
       naming whatever the bar underneath is filling with.

       Empty until the client names a job. Core attaches on login and the
       client fills the player in field by field, so there are a frame or two
       with nothing to say, and saying it in dashes would be worse. ]]
  function self.header()
    if preview then
      return SAMPLE.header
    end
    if not player or not player.main_job then
      return ""
    end
    local mode = self.mode()
    local sub_job = player.sub_job and tostring(player.sub_job) or nil
    if sub_job ~= nil and sub_job:lower() == EMPTY_JOB then
      sub_job = nil
    end
    local sub = sub_job and (sub_job .. tostring(whole(player.sub_job_level))) or NO_SUBJOB
    return string.format(
      "%s%d/%s%s JP: %d MP: %d %s/hr: %.1fk",
      tostring(player.main_job),
      whole(player.main_job_level),
      sub,
      mode == "ep" and string.format(" (ML%d)", ep.master_level) or "",
      job_points(),
      limit.merits,
      RATE_LABEL[mode],
      math.floor(self.rate() / RATE_UNIT) / 10
    )
  end

  --[[ Everything this module holds belongs to one character: the widget calls
       this as it attaches, before seeding from the client.

       Without it a second character inherits the first's numbers - their merit
       count and experience are drawn until a fresh 0x061 and 0x063 land, which
       is never if `windower.packets.last_incoming` has nothing to give, and
       their rate history is quoted in the new character's header for the whole
       ten-minute window. Preview is deliberately untouched: layout mode owns
       that flag, and core sets it independently of who is logged in. ]]
  function self.reset()
    player = nil
    exp = { current = 0, required = 0 }
    ep = { current = 0, required = 0, master_level = 0, master_breaker = false }
    limit = { current = 0, merits = 0, max_merits = 0 }
    width = 0
    last_mode = nil
    forced = true
    self.clear_rates()
  end

  function self.clear_rates()
    for _, registry in pairs(registries) do
      registry.clear()
    end
    for kind in pairs(rates) do
      rates[kind] = 0
    end
    rates_at = nil
  end

  -- What the bar is filling: how much of it, and how much it takes.
  function self.progress()
    local mode = self.mode()
    if mode == "ep" then
      return ep.current, ep.required
    elseif mode == "limit" then
      return limit.current, LIMIT_PER_MERIT
    end
    return exp.current, exp.required
  end

  local function on_char_stats(packet)
    exp.current = whole(packet["Current EXP"])
    exp.required = whole(packet["Required EXP"])
    ep.current = whole(packet["Current Exemplar Points"])
    ep.required = whole(packet["Required Exemplar Points"])
    ep.master_level = whole(packet["Master Level"])
    ep.master_breaker = flag(packet["Master Breaker"])
    return true
  end

  local function on_char_update(packet)
    -- One packet id over five layouts; only order 2 carries limit points.
    if whole(packet.Order) ~= LIMIT_POINT_ORDER then
      return false
    end
    limit.current = whole(packet["Limit Points"])
    limit.merits = whole(packet["Merit Points"])
    limit.max_merits = whole(packet["Max Merit Points"])
    return true
  end

  --[[ pointwatch's own wrapping rules, with its exemplar branch fixed: it
       registers an exemplar gain for the rate and then never adds it, so its EP
       figure moves only when a 0x061 arrives. Every wrap here is provisional -
       the server's own packet corrects it moments later. ]]
  local function add_points(kind, amount)
    if kind == "exp" then
      exp.current = exp.current + amount
      if exp.required > 0 and exp.current >= exp.required then
        exp.current = exp.current - exp.required
      end
    elseif kind == "ep" then
      ep.current = ep.current + amount
      if ep.required > 0 and ep.current >= ep.required then
        ep.current = ep.current - ep.required
      end
    elseif kind == "limit" then
      limit.current = limit.current + amount
      --[[ A cap of zero means the client has not said yet, not that no merit
           can be held: 0x063 is multiplexed over five orders and
           `last_incoming` is keyed by id alone, so the seed usually misses and
           the first order-2 packet may be a while coming. Reading unknown as
           capped would park the bar at 9999/10000 until then. ]]
      local known_cap = limit.max_merits > 0
      if limit.current >= LIMIT_PER_MERIT and (not known_cap or limit.merits < limit.max_merits) then
        limit.merits = limit.merits + math.floor(limit.current / LIMIT_PER_MERIT)
        if known_cap then
          limit.merits = math.min(limit.merits, limit.max_merits)
        end
        limit.current = limit.current % LIMIT_PER_MERIT
      else
        -- Merits are capped, so the points are spent on nothing and the bar
        -- sits one point short of a full one rather than wrapping.
        limit.current = math.min(limit.current, LIMIT_PER_MERIT - 1)
      end
    end
  end

  local function on_action_message(packet, now)
    local gain = GAINS[whole(packet.Message)]
    if not gain then
      return false
    end
    local amount = whole(packet["Param " .. gain.param])
    add_points(gain.kind, amount)
    -- Limit points feed the merit count and the bar, but no rate: neither
    -- header line quotes LP/hr.
    local registry = registries[gain.kind]
    if registry then
      registry.add(now, amount)
    end
    return true
  end

  -- A packet the entry point forwarded, already parsed. `packet` is nil when
  -- the parse failed, which is a real case rather than a fault.
  function self.on_packet(id, packet, now)
    if packet == nil or not HANDLED_CHUNKS[id] then
      return false
    end
    if id == CHAR_STATS then
      return on_char_stats(packet)
    elseif id == CHAR_UPDATE then
      return on_char_update(packet)
    end
    return on_action_message(packet, now)
  end

  --[[ Which of XivParty's job glyphs the header draws, or nil before the
       client has named a job. They are gold with a dark outline, so they are
       drawn on their own - the party list's tinted backing is what that
       component wants for its role colours, not something legibility needs.

       An art file XivParty does not ship draws nothing, silently. That is the
       platform's behaviour for a missing texture and is left as it is: the
       only job the client ever reports here is the one being played. ]]
  function self.job_icon()
    local job = preview and SAMPLE_JOB or (player and player.main_job)
    if job == nil then
      return nil
    end
    return { name = tostring(job):lower() }
  end

  -- The mode the bar is DRAWN in, which layout mode overrides; `self.mode()` is
  -- the client's own answer and stays untouched.
  local function display_mode()
    return preview and SAMPLE.mode or self.mode()
  end

  local function icon_metrics()
    local icon = config.job_icon
    if type(icon) ~= "table" then
      icon = {}
    end
    return { size = icon.size or 0, gap = icon.gap or 0 }
  end

  -- The header band is as tall as the taller of the text and the icon, so an
  -- icon sized past the band pushes the bar down rather than drawing over it.
  local function band_height()
    return math.max(config.header_height or 0, icon_metrics().size)
  end

  local function metrics()
    local bar = config.bar
    if type(bar) ~= "table" then
      bar = {}
    end
    local bar_width = bar.width or 0
    local inset = bar.inset or 0
    return {
      width = bar_width,
      height = bar.height or 0,
      inset = inset,
      -- The frame is inset at both ends, so the fill is narrower than the art.
      span = math.max(bar_width - inset * 2, 0),
    }
  end

  -- Where every prim goes for a widget anchored at (x, y) and drawn at `scale`.
  function self.geometry(x, y, scale)
    local bar = metrics()
    local icon = icon_metrics()
    local bar_y = y + (band_height() + (config.gap or 0)) * scale
    --[[ The header and the bar share a left edge, with the icon hanging off to
         the left of both. The indent holds whether or not a glyph is drawn: a
         job the client has not named yet must not slide the line left and back
         again, and the bar must not move under it. ]]
    local left = x + (icon.size + icon.gap) * scale
    return {
      icon = { x = x, y = y, size = icon.size * scale },
      header = { x = left, y = y },
      background = { x = left, y = bar_y, width = bar.width * scale, height = bar.height * scale },
      fill = { x = left + bar.inset * scale, y = bar_y, height = bar.height * scale },
      -- Whole pixels: a fractional font size is not something a prim can draw.
      font_size = math.floor((config.font_size or 0) * scale + 0.5),
      fill_width = function(value)
        return value * scale
      end,
    }
  end

  -- The reserved box: as wide as the bar plus the icon left of it, and as tall
  -- as the header band, the gap and the bar together.
  function self.bounds(x, y, scale)
    local bar = metrics()
    local icon = icon_metrics()
    local height = band_height() + (config.gap or 0) + bar.height
    return x, y, (icon.size + icon.gap + bar.width) * scale, height * scale
  end

  -- Forces the next tick to re-push the bar. The widget calls this after a
  -- layout change: the fill is only sized on a frame it is redrawn, so a scale
  -- change would otherwise leave it at the previous scale.
  function self.invalidate()
    forced = true
  end

  function self.set_config(new_config)
    config = new_config
    forced = true
  end

  function self.set_preview(on)
    on = on and true or false
    if on == preview then
      return
    end
    preview = on
    forced = true
  end

  function self.preview()
    return preview
  end

  local function target_width()
    local bar = metrics()
    if preview then
      return math.floor(SAMPLE.percent * bar.span)
    end
    local current, required = self.progress()
    if required <= 0 then
      return 0
    end
    return math.max(math.min(math.floor(current / required * bar.span), bar.span), 0)
  end

  --[[ One frame: the eased fill width, the header, and whether either needs
       pushing to a prim. `now` is the widget's monotonic clock and feeds the
       rates alone - the animation is per frame, as barfiller's is. ]]
  function self.tick(now)
    if now ~= nil and (rates_at == nil or now - rates_at >= RATE_INTERVAL) then
      rates_at = now
      for kind, registry in pairs(registries) do
        rates[kind] = registry.rate(now)
      end
    end

    local mode = display_mode()
    local target = target_width()
    local moved = width ~= target
    if moved then
      if width < target then
        width = math.min(width + math.ceil((target - width) * EASE), target)
      else
        width = math.max(width - math.ceil((width - target) * EASE), target)
      end
    end

    local dirty = moved or forced or mode ~= last_mode
    last_mode = mode
    forced = false

    return {
      mode = mode,
      header = self.header(),
      width = width,
      hidden = width == 0,
      dirty = dirty,
      color = config.fill_color or {},
    }
  end

  -- `//hud expbar ...`. Returns the line to print and whether anything the
  -- framework persists has changed - nothing here does, so it is always false.
  function self.command(args)
    args = args or {}
    local verb = args[1] and args[1]:lower() or nil

    if verb == "clear" then
      self.clear_rates()
      return "expbar rate history cleared", false
    end

    if verb ~= nil then
      return string.format("expbar has no '%s' command (clear)", args[1]), false
    end

    local current, required = self.progress()
    local percent = required > 0 and math.floor(current / required * 100) or 0
    --[[ Two lines, and the second earns its place: the master-level fields are
         the unverified half of this component. Nothing outside a live client
         says `Master Breaker` and `Master Level` are the spellings Windower's
         parser uses, and a wrong one reads as false and 0 rather than as an
         error - the bar simply pins itself in limit mode with nothing anywhere
         to say why. Core prints a list of strings a line each. ]]
    return {
      string.format(
        "expbar: %s %d/%d (%d%%) - EXP/hr %.1fk, CP/hr %.1fk, EP/hr %.1fk",
        MODE_NAMES[self.mode()],
        current,
        required,
        percent,
        math.floor(rates.exp / RATE_UNIT) / 10,
        math.floor(rates.cp / RATE_UNIT) / 10,
        math.floor(rates.ep / RATE_UNIT) / 10
      ),
      string.format(
        "expbar: master breaker %s, master level %d, merits %d/%d",
        ep.master_breaker and "yes" or "no",
        ep.master_level,
        limit.merits,
        limit.max_merits
      ),
    },
      false
  end

  return self
end

return new
