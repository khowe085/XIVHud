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

--[[ Target Bar state machine: the current target in, a render plan out.

     No prims and no Windower here - targetbar.lua turns the plan into prim
     calls. What it owns:

       - the target's identity, vitals and claim state, fed once per frame;
       - the fill's eased width, parambar's algorithm, but reset whenever the
         target changes: a bar that slid from the last mob's hp to the new
         one's would read as a stuck bar rather than an animation;
       - the row's layout arithmetic, which is where the widget's whole
         bounding box comes from.

     Every drawn element has to sit inside the box `bounds` reports, because
     core clamps the widget on screen by comparing that box to the origin it
     handed `set_pos`. The art makes that harder than it sounds: the bar
     texture carries 25px of transparent padding above its visible band, so
     placing the frame naively would draw above the origin. See `geometry`. ]]

local EASE = 0.1

--[[ The bar art, in drawn pixels (the files are 2x this and drawn at half).

     The frame began as XIVParty's 128-wide bar (via partylist's layout.lua,
     where the same art backs the hp, mp and tp bars) and was regenerated to
     four times that width for this component: both bevelled caps are
     preserved byte for byte and the middle - which in the source art is a run
     of identical columns - is extended by replication, so no pixel was
     interpolated. See assets/LICENSE.txt for the transform. The insets and
     the vertical band survive unchanged; only the middle grew. ]]
local FRAME_WIDTH = 512
local FRAME_HEIGHT = 64
local FILL_INSET_X = 13
local FILL_WIDTH = FRAME_WIDTH - 2 * FILL_INSET_X
-- The cast bar's own art (CastBG/CastBar/CastFG), regenerated at half the
-- health bar's width by the same cap-preserving transform. Its own constants
-- because drawing the wide art narrower would squash the bevelled caps.
local CAST_FRAME_WIDTH = 256
local CAST_FILL_WIDTH = CAST_FRAME_WIDTH - 2 * FILL_INSET_X
-- The visible band inside that 64px footprint; everything outside it is
-- transparent. Vertical placement is measured from the band so the bar lands
-- where the eye expects rather than where the texture does - but the *box*
-- still covers the whole footprint, padding included.
local BAND_TOP = 25
local BAND_BOTTOM = 39

--[[ Glyph estimates. Windower prims cannot report their rendered width, so a
     row of independently coloured segments needs a reserve per segment.

     0.75 is giltracker's *measured* Arial width in pixels per point of font
     size (its own reserve constant is a deliberately low 0.6, which works
     there only because its overflow lands inside its own box; here the name is
     the last segment, so an undersized reserve walks off the box's edge).

     It bounds nothing absolutely - a wide capital is nearer 1.26x the font
     size - but mob names average well under it. The worst case is an
     in-client check, not something this module can settle. ]]
local RATIO = 0.75
-- Ascender to descender as a multiple of the font size, giltracker's measured
-- value. Not 4/3: that is the point-to-pixel conversion, which gives the em
-- size and would leave descenders below any box derived from it.
local TEXT_HEIGHT_RATIO = 1.5

-- "100%" is four characters, but the % glyph is nearly twice a digit's width,
-- so four characters of reserve overruns deterministically. The fifth absorbs
-- it.
local HP_CHARACTERS = 5
-- The row starts this many characters in from the bar's left edge, clear of
-- the frame art's own bevel.
local ROW_INSET_CHARACTERS = 1
-- "99.99", the widest the clamp below allows.
local DISTANCE_CHARACTERS = 5
local MAX_DISTANCE = 99.99

-- partylist's bands, strictly less than, on the percent value.
local BANDS = { { 25, "red" }, { 50, "orange" }, { 75, "yellow" } }

--[[ The 0x028 action packet, as windower.packets.parse_action shapes it.
     Category sets from enemybar2's actionTracking.lua (the working example of
     this exact feature), cross-checked against the Action Event wiki: a
     *start* carries the acting id in targets[1].actions[1].param, a *finish*
     in the root param. Category 8 is a spell cast beginning, 7 a weapon
     skill or TP move readying; 4, 11 and 3 are their completions. ]]
local CAST_START = { [7] = true, [8] = true }
-- 4 spell finish, 11 TP move landing, 3 a weapon skill landing, 6 a job
-- ability resolving, 5 an item finishing - any of them from the caster means
-- whatever was winding up has resolved. Item *starts* (category 9) are
-- deliberately not tracked: monsters do not use items.
local CAST_FINISH = { [3] = true, [4] = true, [5] = true, [6] = true, [11] = true }
local SPELL_START = 8
-- A finish the packet stream never delivers - a despawn mid-cast, a packet
-- lost - must not leave a bar on screen forever.
local CAST_EXPIRY_GRACE = 3
local DEFAULT_TP_SWEEP = 2
-- How much of the row the cast name's derived cap may claim; the last tenth
-- stays as margin, because a cap sized to the whole row would spend the glyph
-- estimate's entire error budget on the contract edge.
local CAST_NAME_MARGIN = 0.9

local PREVIEW_CAST = { active = true, name = "Fire IV", progress = 0.4, width = 92 }
local IDLE_CAST = { active = false, name = "", progress = 0, width = 0 }

--[[ DistancePlus's range coding, ported whole (BSD 3-clause (c) 2017 Sammeh
     of Quetzalcoatl).

     Every constant below is copied digit for digit, and - more importantly -
     so is the *branch order*. The bands add both parties' model sizes, so
     which one a distance falls into is not something that can be restated as
     "green under X": at a large enough target the square-shot band reaches
     past the 25 yalm cutoff and a distance that would otherwise be out of
     range comes back green. Rewriting these as tidier comparisons would
     quietly change the answer. ]]
local RANGED_BANDS = {
  bow = { true_max = 9.5199, true_min = 6.02, square_max = 14.5199, square_min = 4.62 },
  xbow = { true_max = 8.3999, true_min = 5.0007, square_max = 11.7199, square_min = 3.6199 },
  gun = { true_max = 4.3189, true_min = 3.0209, square_max = 6.8199, square_min = 2.2219 },
}
local RANGED_MAX_DISTANCE = 25
-- The ranged rule keys on the *target's* model size alone, even though both
-- sizes feed the band bounds.
local RANGED_LARGE_TARGET = 1.6
local RANGED_LARGE_BONUS = 0.1

local CASTING_MAX_DISTANCE = { magic = 20, ninjutsu = 16.1 }
local CASTING_LARGE_TARGET = 2
local CASTING_LARGE_BONUS = 0.1

-- Which range scheme a job gets when the mode is left on auto. RNG is absent
-- deliberately: the source hands it the default and asks the player to name
-- the weapon themselves, because nothing in the client says which is equipped.
local MODE_FOR_JOB = {
  RDM = "magic",
  BLM = "magic",
  GEO = "magic",
  SCH = "magic",
  WHM = "magic",
  BRD = "magic",
  NIN = "ninjutsu",
  COR = "gun",
}

local MODES = { "auto", "default", "magic", "ninjutsu", "gun", "bow", "xbow" }
local IS_MODE = {}
for _, mode in ipairs(MODES) do
  IS_MODE[mode] = true
end

--[[ In casting range, or not. The dead branches in the source
     (`floor(model_size * 10) == 44` and `== 53`) are not reproduced: they sit
     behind the `> 2` test in an elseif chain, and every model size that could
     satisfy them is already larger than 2, so the first branch always wins.
     Porting them as live code would answer 20.0666 where the source answers
     20.1. ]]
local function casting_state(base, distance, self_size, target_size)
  local max_distance = base
  if target_size > CASTING_LARGE_TARGET then
    max_distance = max_distance + CASTING_LARGE_BONUS
  end
  return distance < max_distance + target_size + self_size and "good" or "out"
end

local function ranged_state(band, distance, self_size, target_size)
  --[[ Each threshold is summed and *then* adjusted, which is the order the
       source uses. Folding the tenth into `base` first is the same sum in
       algebra and a different one in floating point, and the difference is
       visible: it shifts each band edge by one unit in the last place, which
       at a distance sitting exactly on an edge flips the colour. ]]
  local base = self_size + target_size
  local true_max = base + band.true_max
  local true_min = base + band.true_min
  local square_max = base + band.square_max
  local square_min = base + band.square_min

  if target_size > RANGED_LARGE_TARGET then
    true_max = true_max + RANGED_LARGE_BONUS
    true_min = true_min + RANGED_LARGE_BONUS
    square_max = square_max + RANGED_LARGE_BONUS
    square_min = square_min + RANGED_LARGE_BONUS
  end

  if distance < RANGED_MAX_DISTANCE and (distance > square_max or distance < square_min) then
    return "capable"
  elseif (distance <= square_max and distance > true_max) or (distance < true_min and distance >= square_min) then
    return "good"
  elseif distance <= true_max and distance >= true_min then
    return "best"
  end
  return "out"
end

-- The eighteen keys get_party() files members under. Walked explicitly rather
-- than with pairs(), because the same table carries scalars (member counts,
-- leader ids) that would be indexed as tables by a blind walk.
local PARTY_KEYS = {}
for slot = 0, 5 do
  PARTY_KEYS[#PARTY_KEYS + 1] = ("p%d"):format(slot)
  PARTY_KEYS[#PARTY_KEYS + 1] = ("a1%d"):format(slot)
  PARTY_KEYS[#PARTY_KEYS + 1] = ("a2%d"):format(slot)
end

--[[ Layout mode has to show the widget's real footprint with nothing
     targeted. 40% lands in the orange band (the thresholds are strictly less
     than, so 63 would read yellow), and the claim state is forced to `mine` -
     the state a player looking at this widget is in most of the time. ]]
local PREVIEW_TARGET = {
  id = -1,
  name = "Greater Colibri",
  hpp = 40,
  claim_id = -1,
  in_party = false,
  is_npc = true,
  distance = 144,
  model_size = 1.0,
}
local PREVIEW_CLAIM_STATE = "mine"

local function band_for(percent)
  for _, band in ipairs(BANDS) do
    if percent < band[1] then
      return band[2]
    end
  end
  return "normal"
end

local function new(initial_config, resources)
  local self = {}
  local config = initial_config or {}

  local target = nil
  local preview = false
  local self_id = nil
  local self_model_size = nil
  local self_main_job = nil
  local party_ids = {}
  -- The fill's animated width, in authored pixels (0..FILL_WIDTH).
  local eased_width = 0
  -- The cast the target is winding up, or nil. name/started_at/duration in
  -- seconds, expires_at the moment the belt-and-braces timeout drops it.
  local cast = nil
  --[[ Set whenever the bar's subject changes rather than its hp: a new target,
       a reacquire, a preview toggle. The next step jumps straight to the
       answer, because easing between two different mobs' health animates
       something that never happened. ]]
  local snap = true
  -- Declared here because texts() below calls it while its definition sits
  -- with the rest of the range colouring, further down.
  local distance_state

  local function current()
    if preview then
      return PREVIEW_TARGET
    end
    return target
  end

  --[[ The defaults merge deliberately preserves a user's value even where the
       defaults have a table, so any section of a hand-edited config can be a
       scalar. Everything below runs on the per-frame path inside the one
       guarded prerender handler every component shares - an unguarded index
       would take the whole HUD down, not just this widget. ]]
  local function section(value)
    if type(value) == "table" then
      return value
    end
    return {}
  end

  local function whole(value, minimum, fallback)
    local number = tonumber(value)
    if not number then
      return fallback
    end
    return math.max(minimum, math.floor(number))
  end

  function self.set_config(new_config)
    config = new_config or {}
  end

  --[[ The player's own facts, fed on the poll rather than per frame: none of
       them change often, and reading the player every frame is a cost the
       sibling components deliberately bound. ]]
  function self.set_self(id, model_size, main_job)
    self_id = tonumber(id)
    self_model_size = tonumber(model_size)
    self_main_job = main_job
  end

  --[[ The claim-ownership roster, straight from get_party(). The id lives in
       the member's mob table, which the client has not loaded for a member
       outside the zone - those simply drop out of the set for this window
       (their claim reads as somebody else's until the client catches up)
       rather than being chased through the packet machinery partylist keeps
       for its own out-of-zone rows. ]]
  function self.set_party(party)
    party = party or {}
    party_ids = {}
    for _, key in ipairs(PARTY_KEYS) do
      local member = party[key]
      if type(member) == "table" and member.mob then
        local id = tonumber(member.mob.id)
        if id then
          party_ids[id] = true
        end
      end
    end
  end

  --[[ Whether a claim belongs to us or anyone fighting alongside us.

       Claim 0 means unclaimed, and returning false for it is a fix, not a
       detail: the reference initialises its player id to 0 and compares
       `player_id == claim_id`, so before the player resolves it paints every
       unclaimed mob as claimed by us. An unknown self id matches nothing. ]]
  local function claimed_by_us(claim_id)
    if claim_id == 0 then
      return false
    end
    if self_id and claim_id == self_id then
      return true
    end
    return party_ids[claim_id] == true
  end

  --[[ enemybar's six branches, in its order. The order carries meaning that
       the individual tests do not: party members and other players both carry
       claim 0, so hoisting the unclaimed test any earlier would swallow them
       both. ]]
  function self.claim_state()
    if preview then
      return PREVIEW_CLAIM_STATE
    end

    local mob = current()
    if not mob then
      return nil
    end
    if mob.hpp == 0 then
      return "dead"
    end
    if claimed_by_us(mob.claim_id) then
      return "mine"
    end
    -- The self id guard is the member branch's half of the same fix: without
    -- it, `id ~= nil` is true and you are your own party member.
    if mob.in_party and self_id and mob.id ~= self_id then
      return "member"
    end
    if mob.is_npc == false then
      return "pc"
    end
    if mob.claim_id == 0 then
      return "unclaimed"
    end
    return "claimed"
  end

  --[[ The frame's facts, as one table. `hpp` decides occupancy: a mob table
       that cannot say how hurt it is has nothing this widget can draw, and
       every read below would have to guard against it separately. ]]
  function self.set_target(mob)
    local hpp = mob and tonumber(mob.hpp)
    if not hpp then
      self.clear_target()
      return
    end

    -- A different mob is a different animation. Identity, not hp, is what
    -- decides whether the bar eases or jumps - and its cast goes with it.
    if not target or target.id ~= mob.id then
      snap = true
      cast = nil
    end
    -- The dead do not finish casting.
    if hpp == 0 then
      cast = nil
    end

    target = {
      id = mob.id,
      name = type(mob.name) == "string" and mob.name or "",
      hpp = hpp,
      -- Normalised here so a mob table without the field reads as unclaimed
      -- rather than as somebody else's claim.
      claim_id = tonumber(mob.claim_id) or 0,
      in_party = mob.in_party == true,
      is_npc = mob.is_npc,
      distance = tonumber(mob.distance) or 0,
      model_size = tonumber(mob.model_size),
    }
  end

  -- Losing the target ends the animation as well as the target: set_target
  -- treats an arrival with no incumbent as an identity change, so reacquiring
  -- the same mob starts fresh rather than resuming a slide nobody could see.
  function self.clear_target()
    target = nil
    cast = nil
  end

  function self.occupied()
    return current() ~= nil
  end

  function self.set_preview(on)
    on = on and true or false
    if on ~= preview then
      snap = true
    end
    preview = on
  end

  self.band_for = band_for

  -- Bounded both ways: the floor keeps the substring sane, and the ceiling
  -- keeps a hand-edited huge value from sizing the drag box to the reserve a
  -- hundred-thousand-character name would need.
  local function name_cap()
    return math.min(whole(config.name_max_chars, 1, 17), 64)
  end

  -- The mob table reports the *square* of the distance.
  local function real_distance(squared)
    return math.sqrt(math.max(tonumber(squared) or 0, 0))
  end

  -- Clamped only for display: the reserve is sized for five characters, and a
  -- target followed at range can pass three digits. Every range scheme reads
  -- "out" long before that, so the range test keeps the true value.
  local function distance_text(distance)
    return ("%.2f"):format(math.min(distance, MAX_DISTANCE))
  end

  --[[ The three row segments. Each carries its own colour because each is a
       separate prim: the hp number bands, the distance follows the range
       scheme, and the name is never coloured by either. ]]
  function self.texts()
    local text_color = section(config.text_color)
    local mob = current()
    if not mob then
      return {
        hp = { text = "", color = text_color },
        distance = { text = "", color = text_color },
        name = { text = "", color = text_color },
      }
    end

    local band = band_for(mob.hpp)
    local bands = section(config.bands)
    local distance = real_distance(mob.distance)
    local range_colors = section(section(config.distance).colors)

    return {
      hp = {
        text = ("%d%%"):format(mob.hpp),
        color = bands[band] or text_color,
      },
      distance = {
        text = distance_text(distance),
        color = range_colors[distance_state(distance)] or text_color,
      },
      name = {
        text = mob.name:sub(1, name_cap()),
        color = text_color,
      },
    }
  end

  --[[ Range colouring ----------------------------------------------------- ]]

  --[[ Which scheme applies. `auto` follows the main job; anything else is
       taken at its word, and anything unrecognised - a hand-edited config -
       degrades to the uncoloured default rather than erroring. ]]
  function self.resolve_mode(configured, main_job)
    if type(configured) ~= "string" or not IS_MODE[configured] then
      return "default"
    end
    if configured ~= "auto" then
      return configured
    end
    return MODE_FOR_JOB[main_job] or "default"
  end

  --[[ The colour state for a distance under a given scheme. Pure: the caller
       supplies both model sizes, so the whole table of DistancePlus's
       behaviour is exercisable without a client.

       A distance of zero is white before the mode is even consulted, which is
       the source's own first test - you are inside the target, and no band
       means anything there. ]]
  function self.range_state(mode, distance, self_size, target_size)
    self_size = tonumber(self_size)
    target_size = tonumber(target_size)
    -- Without the player's own model size no threshold can be computed, so
    -- the segment stays plain rather than guessing one.
    if not self_size or not target_size or distance == 0 then
      return "out"
    end

    local casting = CASTING_MAX_DISTANCE[mode]
    if casting then
      return casting_state(casting, distance, self_size, target_size)
    end

    local band = RANGED_BANDS[mode]
    if band then
      return ranged_state(band, distance, self_size, target_size)
    end

    return "out"
  end

  --[[ What the config asks for, as resolve_mode will read it. Normalised here
       so a hand-edited nonsense value is reported as the mode actually in
       force rather than echoed back as something the colouring never used. ]]
  local function configured_mode()
    local mode = section(config.distance).mode
    if type(mode) ~= "string" or not IS_MODE[mode] then
      return "default"
    end
    return mode
  end

  function distance_state(distance)
    local mode = self.resolve_mode(configured_mode(), self_main_job)
    return self.range_state(mode, distance, self_model_size, (current() or {}).model_size)
  end

  --[[ Commands ------------------------------------------------------------ ]]

  local function mode_list()
    return table.concat(MODES, "|")
  end

  local function status()
    local configured = configured_mode()
    local effective = self.resolve_mode(configured, self_main_job)
    local line = ("targetbar range mode: %s"):format(configured)
    if configured == "auto" then
      line = line .. (" (%s)"):format(effective)
    end
    -- Nothing in the client says which ranged weapon is equipped, so a ranger
    -- has to say so - the same nudge the reference addon prints at login.
    if effective == "default" and self_main_job == "RNG" then
      line = line .. " - pick bow, xbow or gun for range bands"
    end
    return line
  end

  -- `//hud targetbar ...`. Returns the line to say and whether anything
  -- changed, so the widget knows when to re-lay out and save.
  function self.command(args)
    args = args or {}
    local verb = args[1] and args[1]:lower() or nil
    if not verb then
      return status(), false
    end

    if verb == "mode" then
      local wanted = args[2] and args[2]:lower() or nil
      if not wanted or not IS_MODE[wanted] then
        return ("//hud targetbar mode needs one of: %s"):format(mode_list()), false
      end
      -- Replaced outright when mangled: assigning into a user's scalar would
      -- throw inside the addon command handler.
      if type(config.distance) ~= "table" then
        config.distance = {}
      end
      config.distance.mode = wanted
      return ("targetbar range mode set to %s"):format(wanted), true
    end

    return ("targetbar has no '%s' setting (mode %s)"):format(tostring(args[1]), mode_list()), false
  end

  --[[ Layout ------------------------------------------------------------- ]]

  -- Whole pixels: a prim cannot draw a fractional font, so every reserve is
  -- measured against the size it will actually round to rather than the
  -- fractional one, which under-reserves once the widget is scaled down.
  local function drawn_font(size, scale)
    return math.max(1, math.floor((tonumber(size) or 0) * scale + 0.5))
  end

  local function reserve(characters, font_size)
    return math.ceil(characters * font_size * RATIO)
  end

  --[[ Everything both `geometry` and `bounds` need, derived once. Splitting it
       would be how the two drift apart, and a box that disagrees with what is
       drawn is exactly the bug the containment spec exists to catch. ]]
  local function metrics(x, y, scale)
    local font_size = drawn_font(config.font_size, scale)
    local text_height = font_size * TEXT_HEIGHT_RATIO
    local hp_reserve = reserve(HP_CHARACTERS, font_size)
    local distance_reserve = reserve(DISTANCE_CHARACTERS, font_size)
    local name_reserve = reserve(name_cap(), font_size)
    local row_inset = ROW_INSET_CHARACTERS * font_size * RATIO

    -- Floored at the frame's own drawn width: the art is that wide whatever
    -- the reserves come to, and a box narrower than the art it contains is a
    -- drag target that misses half the widget. The inset counts toward the
    -- box: the name's reserve ends that much further right.
    local row_width = math.max(row_inset + hp_reserve + distance_reserve + name_reserve, FRAME_WIDTH * scale)

    --[[ The bar art carries BAND_TOP pixels of transparency above its visible
         band, so the gap is measured to the band and the texture is placed
         above it. The clamp is what keeps that transparent margin from
         reaching above the origin once a user edits the font or the gap:
         nothing may be drawn above the box, padding included. ]]
    local gap = math.max((tonumber(config.gap) or 0) * scale, BAND_TOP * scale - text_height)
    local frame_y = y + text_height + gap - BAND_TOP * scale
    local band_bottom = frame_y + BAND_BOTTOM * scale

    --[[ The cast rows. Every key is a user-editable config value, so every
         one is clamped: the scale to (0, 1] (a cast bar wider than the box
         would cross the origin from its right anchor), the font to a whole
         pixel, the gaps to zero and up (a negative would hoist a row above
         the origin, which no frame-position floor reaches). ]]
    local cast_config = section(config.cast)
    local cast_scale = math.min(math.max(tonumber(cast_config.scale) or 0.67, 0.01), 1) * scale
    local cast_gap = math.max(tonumber(cast_config.gap) or 0, 0) * scale
    local cast_frame_y = math.max(y, band_bottom + cast_gap - BAND_TOP * cast_scale)
    local cast_frame_x = math.max(x, x + row_width - CAST_FRAME_WIDTH * cast_scale)
    local cast_band_bottom = cast_frame_y + BAND_BOTTOM * cast_scale

    local cast_font = drawn_font(math.max(math.floor(tonumber(cast_config.font_size) or 12), 1), scale)
    local cast_name_gap = math.max(tonumber(cast_config.name_gap) or 0, 0) * scale
    local cast_name_y = cast_band_bottom + cast_name_gap
    local cast_name_height = cast_font * TEXT_HEIGHT_RATIO

    --[[ The cast name is the one right-justified text here, so it grows
         leftwards from the box edge and its cap is the only thing standing
         between it and the origin. Derived from the room actually available
         at the current font - nine tenths of the row, keeping the last tenth
         as margin for the glyph estimate - with the config cap as a further
         ceiling, never the guarantee. ]]
    local room = math.floor(row_width * CAST_NAME_MARGIN / (cast_font * RATIO))
    local cast_name_chars = math.max(math.min(room, whole(cast_config.name_max_chars, 1, 20)), 0)

    return {
      font_size = font_size,
      text_height = text_height,
      hp_reserve = hp_reserve,
      distance_reserve = distance_reserve,
      name_reserve = name_reserve,
      row_width = row_width,
      row_inset = row_inset,
      frame_y = frame_y,
      cast_scale = cast_scale,
      cast_frame_x = cast_frame_x,
      cast_frame_y = cast_frame_y,
      cast_font = cast_font,
      cast_name_y = cast_name_y,
      cast_name_height = cast_name_height,
      cast_name_chars = cast_name_chars,
      cast_name_width = cast_name_chars * cast_font * RATIO,
    }
  end

  --[[ Where every prim goes for a widget anchored at (x, y) at `scale`.

       `screen_width` serves only the right-justified cast name: the texts
       library adds the screen width to x when the right flag is set, so the
       position handed to that prim pre-subtracts it. Logic holds no ctx; the
       widget reads its screen and passes the width in. ]]
  function self.geometry(x, y, scale, screen_width)
    local m = metrics(x, y, scale)

    local function text(offset, size, width)
      return { x = x + offset, y = y, size = size, width = width, height = size * TEXT_HEIGHT_RATIO }
    end

    return {
      row_width = m.row_width,
      texts = {
        hp = text(m.row_inset, m.font_size, m.hp_reserve),
        distance = text(m.row_inset + m.hp_reserve, m.font_size, m.distance_reserve),
        name = text(m.row_inset + m.hp_reserve + m.distance_reserve, m.font_size, m.name_reserve),
      },
      frame = { x = x, y = m.frame_y, width = FRAME_WIDTH * scale, height = FRAME_HEIGHT * scale },
      fill = {
        x = x + FILL_INSET_X * scale,
        y = m.frame_y,
        height = FRAME_HEIGHT * scale,
        full_width = FILL_WIDTH * scale,
        -- The eased width arrives in authored pixels; only the widget knows
        -- when it changed, so the conversion goes with the placement.
        width_at = function(eased)
          return eased * scale
        end,
      },
      cast = {
        frame = {
          x = m.cast_frame_x,
          y = m.cast_frame_y,
          width = CAST_FRAME_WIDTH * m.cast_scale,
          height = FRAME_HEIGHT * m.cast_scale,
        },
        fill = {
          x = m.cast_frame_x + FILL_INSET_X * m.cast_scale,
          y = m.cast_frame_y,
          height = FRAME_HEIGHT * m.cast_scale,
          full_width = CAST_FILL_WIDTH * m.cast_scale,
          width_at = function(width)
            return width * m.cast_scale
          end,
        },
        name = {
          x = x + m.row_width - (tonumber(screen_width) or 0),
          y = m.cast_name_y,
          size = m.cast_font,
          height = m.cast_name_height,
          right_edge = x + m.row_width,
          max_chars = m.cast_name_chars,
          max_width = m.cast_name_width,
        },
      },
    }
  end

  --[[ The box core clamps against and layout mode drags. The origin is handed
       straight back, because core compares it to what it passed set_pos.

       It covers the frame's whole footprint, so the box runs BAND_TOP * scale
       past the last visible pixel: the art's bottom padding is inside it. That
       is the deliberate direction to err - every drawn rect stays inside the
       box, which is the invariant the containment spec pins - but it does mean
       the layout-mode highlight sits a little low and the screen clamp stops
       the widget just short of the bottom edge. Measuring to the band instead
       would tighten both at the cost of putting a prim outside its own box. ]]
  function self.bounds(x, y, scale)
    local m = metrics(x, y, scale)
    local bottom = math.max(
      y + m.text_height,
      m.frame_y + FRAME_HEIGHT * scale,
      m.cast_frame_y + FRAME_HEIGHT * m.cast_scale,
      m.cast_name_y + m.cast_name_height
    )
    return x, y, m.row_width, bottom - y
  end

  --[[ One eased step towards the target width - parambar's exponential
       ease-out, whose `math.ceil` is what makes it actually converge instead
       of creeping at the last pixel forever.

       Returns the width and whether the fill is empty. On the eased path the
       empty flag lands a frame after the width reaches zero, exactly as
       parambar's does: the branch that reports it is the one taken when there
       is nothing left to move, so a drain's final frame draws at width zero
       (which draws nothing) and hides on the next. Only the snap path reports
       empty immediately, for a target that was already dead on arrival. ]]
  local function ease(target_width)
    if snap then
      snap = false
      eased_width = math.max(0, math.min(target_width, FILL_WIDTH))
      -- Reported here too, unlike the eased path below: a target acquired
      -- already dead has nothing to animate, so there is no frame in which a
      -- zero-width fill would be the honest thing to draw.
      return eased_width, eased_width == 0
    end
    if eased_width == target_width then
      return eased_width, eased_width == 0
    end
    if eased_width < target_width then
      eased_width = math.min(eased_width + math.ceil((target_width - eased_width) * EASE), FILL_WIDTH)
    else
      eased_width = math.max(eased_width - math.ceil((eased_width - target_width) * EASE), 0)
    end
    return eased_width, false
  end

  --[[ The cast tracker ---------------------------------------------------- ]]

  --[[ A parsed 0x028 from the entry point's chunk stream. Only the current
       target's actions matter, and without the resources library there is no
       name or duration to show, so the whole feature quietly sits out. ]]
  function self.on_action(act, now)
    if not resources or type(act) ~= "table" or not target then
      return
    end
    if act.actor_id ~= target.id then
      return
    end

    if CAST_FINISH[act.category] then
      cast = nil
      return
    end
    if not CAST_START[act.category] then
      return
    end

    local first_target = type(act.targets) == "table" and act.targets[1] or nil
    local first_action = first_target and type(first_target.actions) == "table" and first_target.actions[1] or nil
    if type(first_action) ~= "table" then
      return
    end

    -- An interrupt arrives as a start-shaped packet whose one action has
    -- message 0 and is aimed back at the caster - structural, no magic
    -- parameter (enemybar2's own test).
    if first_action.message == 0 and first_target.id == act.actor_id then
      cast = nil
      return
    end

    local id = tonumber(first_action.param)
    -- The reference's own `action_id == 0` guard: start packets can carry a
    -- zero or missing id, and a bar named for nothing helps nobody.
    if not id or id == 0 then
      return
    end
    -- Clamped away from zero: the sweep divides the progress.
    local sweep = math.max(tonumber(section(config.cast).tp_move_sweep) or DEFAULT_TP_SWEEP, 0.1)
    local entry, duration
    if act.category == SPELL_START then
      entry = section(resources.spells)[id]
      -- cast_time is in seconds (verified: the 8s bard songs read 8).
      duration = entry and tonumber(entry.cast_time) or sweep
    else
      -- A readying player is winding up a weapon skill; anything else, a
      -- monster ability. Neither has a duration in any packet or resource,
      -- so the bar runs the configured sweep - an animation, honestly.
      local book = target.is_npc == false and resources.weapon_skills or resources.monster_abilities
      entry = section(book)[id]
      duration = sweep
    end

    -- A spell that casts in zero seconds is done before any bar could mean
    -- anything; its finish packet is already on the wire.
    if duration <= 0 then
      return
    end

    cast = {
      name = entry and entry.en or ("Unknown (id:" .. tostring(id) .. ")"),
      started_at = now,
      duration = duration,
      expires_at = now + duration + CAST_EXPIRY_GRACE,
    }
  end

  local function cast_plan(now)
    if preview then
      return PREVIEW_CAST
    end
    if not cast or not now then
      return IDLE_CAST
    end
    if now >= cast.expires_at then
      cast = nil
      return IDLE_CAST
    end

    local progress = 0
    if cast.duration > 0 then
      progress = math.min(math.max((now - cast.started_at) / cast.duration, 0), 1)
    end
    -- Width in the fill's authored pixels, like the hp fill's; the widget
    -- scales it into place.
    return {
      active = true,
      name = cast.name,
      progress = progress,
      width = math.floor(progress * CAST_FILL_WIDTH),
    }
  end

  -- Everything a frame draws, in one call: the widget pushes it to prims and
  -- decides nothing. `now` feeds the cast bar's clock; without it the cast
  -- simply reads idle, which is what the layout-only callers want.
  function self.tick(now)
    local mob = current()
    if not mob then
      return {
        occupied = false,
        fill = { width = 0, hidden = true, color = nil },
        texts = self.texts(),
        cast = cast_plan(now),
      }
    end

    local state = self.claim_state()
    local eased, hidden = ease(math.floor(mob.hpp / 100 * FILL_WIDTH))

    return {
      occupied = true,
      fill = {
        width = eased,
        hidden = hidden,
        color = section(config.fill_colors)[state],
      },
      texts = self.texts(),
      cast = cast_plan(now),
    }
  end

  return self
end

return new
