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

The radial recast sweep in this file (the observed-maximum denominator and
the frame formula) is transcribed from XIVhotbar2 Petit Trois Edition's
lib/ui.lua, whose notice BSD clause 1 requires retained in derived source:

BSD 3-Clause License

Copyright (c) 2026, WG Incorporated

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ The per-slot draw state every bar shares: what a slot draws for its
     name, its cost corner, the recast sweep and the chain border animation,
     the press flash, the icon it resolves to, and the hit-test over the
     rects a bar has laid its slots out at. Nothing here knows where a slot
     IS - that is each bar's own geometry (components/crossbar/render.lua's
     two crosses, the hotbar's row), which composes this and adds the
     positions. Nothing here touches a prim or a Windower global.

     Split out of the crossbar's render on 2026-09-06 for the hotbar, so the
     two bars draw a slot the same way from one file. The upstream notice
     above travels with the sweep. ]]

local kebab = require("lib/actionbar/kebab")

-- Upstream's fixed 40px slot, every bar's.
local SLOT = 40
-- The shipped cost colours: the fallback when the config's are hand-broken
-- (merge_defaults lets a user scalar beat a table default, and cost() feeds
-- the per-frame path).
local MP_COST_COLOR = { r = 230, g = 91, b = 151 }
local TP_COST_COLOR = { r = 254, g = 222, b = 0 }
-- How many characters of an action's name a slot draws before it is cut.
local SLOT_LABEL_CHARS = 7

local function new(deps)
  local config = deps.config
  local self = {}

  function self.slot_size()
    return SLOT
  end

  --[[ What a slot DRAWS for its name. The stored record keeps the whole
       thing - that is what `list` prints, what the binder describes and
       what the game is sent - and only the drawn label is cut (Kevin,
       2026-08-24): a long spell name otherwise runs off its slot and into
       the neighbour's. Seven characters, then a dot to say there is more.

       The cut backs off any UTF-8 continuation byte it lands on. Lua 5.1
       has no utf8 library and `sub` counts bytes, so a mount's music note
       taken mid-sequence would draw a broken glyph; the note is kept whole
       or dropped whole. Everything else here is ASCII and unaffected. ]]
  function self.slot_label(name)
    local text = name ~= nil and tostring(name) or ""
    if #text <= SLOT_LABEL_CHARS then
      return text
    end
    local cut = SLOT_LABEL_CHARS
    while cut > 0 do
      local byte = text:byte(cut + 1)
      -- 0x80..0xBF is a continuation byte: the cut is inside a character.
      if byte == nil or byte < 128 or byte > 191 then
        break
      end
      cut = cut - 1
    end
    return text:sub(1, cut) .. "."
  end

  --[[ The slot under a point, over the rects a bar laid its slots out at -
       screen coordinates, one per drawn slot, in drawing order. Walked
       backwards so a slot drawn over another wins, which is core's own rule
       for overlapping anchors.

       `accept` is optional and is asked INSIDE the walk, so a rect it turns
       down is looked past rather than ending the search: a slot the caller
       does not draw must not take a click off a drawn one beneath it. The
       binder passes none - an invisible slot is still a drop target there,
       the one thing edit mode cannot do without.

       This is the ONE slot hit-test: the mouse binder resolves its drops
       and drags with it and a bar answers live clicks with it. The
       reference addon had two, which is how they came to disagree. ]]
  function self.slot_at(rects, x, y, accept)
    if type(x) ~= "number" or type(y) ~= "number" or type(rects) ~= "table" then
      return nil
    end
    for index = #rects, 1, -1 do
      local rect = rects[index]
      if x >= rect.x and y >= rect.y and x < rect.x + rect.width and y < rect.y + rect.height then
        if accept == nil or accept(rect) then
          return rect
        end
      end
    end
    return nil
  end

  --[[ The radial recast sweep (Petit Trois' algorithm - see the header
       notice): 32 pre-rendered frames of an arc, indexed by the remaining
       fraction of the LARGEST recast value yet seen for the slot. The
       denominator is observed, not looked up, so the fraction cannot exceed
       1 by construction (upstream defect 7 cannot recur) and a bar that
       loads mid-cooldown starts full rather than dividing by a guess. ]]
  local cooldown_maxima = {}

  -- Forgets a slot's observed maximum. The maxima key by prim slot, so
  -- they would otherwise outlive the slot's ACTION - a set switch, job
  -- change or context flip putting a fresh 30s recast where a 300s one sat
  -- would draw it nearly done under the stale denominator. The caller says
  -- when content changed; the sweep cannot know.
  function self.clear_sweep(key)
    cooldown_maxima[key] = nil
  end

  -- Answers the frame to draw (1..32), or nil when the overlay hides; a
  -- remaining of zero (or none) ends the sweep and forgets the maximum.
  function self.sweep(key, remaining)
    if remaining == nil or remaining <= 0 then
      cooldown_maxima[key] = nil
      return nil
    end
    local maximum = cooldown_maxima[key]
    if maximum == nil or remaining > maximum then
      maximum = remaining
      cooldown_maxima[key] = maximum
    end
    local fraction = remaining / maximum
    return math.max(1, math.floor(fraction * 32 + 0.5))
  end

  --[[ The chain-result border animation (the fork's frame counter,
       ui.lua:1017/1368-1383): one advance per CALL, wrapping at 40, five
       calls per frame_step - so steps 1..8 over 40 calls. A bar calls this
       only while a chain window is actually open and hide.skillchain_icon
       is off, so the cycle runs during the seconds the border is on screen
       and is simply paused the rest of the time. Instance state like the
       sweep maxima; a rebuild at attach restarts the cycle, invisibly. ]]
  local animation_count = 0

  function self.chain_tick()
    animation_count = animation_count + 1
    if animation_count > 40 then
      animation_count = 1
    end
    return math.floor((animation_count - 1) / 5) + 1
  end

  -- Text positions for a slot at (x, y), upstream's offsets verbatim,
  -- slot-relative. Cost and recast are right-justified, so the BAR
  -- subtracts the screen width from their x - after scaling, which is why
  -- the subtraction cannot live here - the same texts-library gotcha
  -- giltracker documents.
  function self.text_offsets(x, y)
    local right = x + 16
    return {
      name = { x = x - 2, y = y + 40 },
      cost = { x = right + 30, y = y + 28 },
      recast = { x = right + 20, y = y + 14 },
    }
  end

  -- The cost corner: MP wins over TP as upstream orders it, nothing is
  -- priced at zero, and `affordable` is the unusable-dimming input. A vital
  -- the client has not filled in yet counts as affordable - vitals arrive
  -- piecemeal (parambar's lesson), and dimming on ignorance would read as
  -- unusable at every login.
  function self.cost(meta, vitals)
    if meta == nil then
      return nil
    end
    vitals = vitals or {}
    if meta.mp_cost ~= nil and meta.mp_cost ~= 0 then
      return {
        text = tostring(meta.mp_cost),
        color = type(config.mp_cost_color) == "table" and config.mp_cost_color or MP_COST_COLOR,
        affordable = vitals.mp == nil or vitals.mp >= meta.mp_cost,
      }
    end
    if meta.tp_cost ~= nil and meta.tp_cost ~= 0 then
      return {
        text = tostring(meta.tp_cost),
        color = type(config.tp_cost_color) == "table" and config.tp_cost_color or TP_COST_COLOR,
        affordable = vitals.tp == nil or vitals.tp >= meta.tp_cost,
      }
    end
    return nil
  end

  -- Seconds remaining on a slot's recast. Spell recasts arrive in 60ths of
  -- a second, ability recasts in seconds - the client's own units.
  function self.remaining_for(meta, spell_recasts, ability_recasts)
    if meta == nil or meta.recast_id == nil then
      return 0
    end
    if meta.kind == "spell" then
      return ((spell_recasts or {})[meta.recast_id] or 0) / 60
    end
    return (ability_recasts or {})[meta.recast_id] or 0
  end

  -- The recast corner's text: hours, then minutes, then whole seconds up.
  function self.recast_label(seconds)
    if seconds >= 3600 then
      return ("%dh"):format(math.floor(seconds / 3600))
    end
    if seconds >= 60 then
      return ("%dm"):format(math.floor(seconds / 60))
    end
    return ("%ds"):format(math.ceil(seconds))
  end

  function self.slot_alpha(usable)
    if usable then
      return 255
    end
    return config.disabled_alpha
  end

  -- One step of the press flash: the alpha walks down by the configured
  -- speed each frame and answers nil when the flash is spent. The config is
  -- hand-editable, so a garbage feedback block falls back to the shipped
  -- speed rather than doing arithmetic on it.
  function self.feedback_fade(alpha)
    if alpha == nil then
      return nil
    end
    local feedback = type(config.feedback) == "table" and config.feedback or {}
    alpha = alpha - (feedback.speed or 30)
    if alpha <= 0 then
      return nil
    end
    return alpha
  end

  --[[ Icon resolution: an ordered list of addon-relative candidate paths for
       a bound slot; the bar draws the first one whose file exists. The
       order is the contract:

         1. the record-level `icon` override (a pack-relative name the
            authoring surface writes), custom copy first - resolved as
            icons/custom/<icon>.png then the shipped pack, per the icon
            verb's contract; deliberately resolved here and not in
            actions.icon_for, which only knows the type defaults;
         2. icons/custom/<name>.png - the player's own art for the action's
            own name, beside the addon at runtime;
         3. the pack's name-resolved art (ninjutsu/utsusemi-ichi.png ...);
         4. the type default: the id-indexed spell/ability sheets, the weapon
            type, the extracted item cache, or the built-in table via
            deps.icon_for.

       Each candidate carries the offset it draws at: the id sheets and
       extracted bitmaps are 32x32 and centre at +4/+4 in the 40px slot
       (upstream's own fix); pack art draws at the origin. ]]
  -- The asset ROOT, not one folder in it: what hangs off this is `own/` for
  -- XIVHud's own chrome, `icons/` for the imported pack and `cooldown/` for
  -- the sweep frames, each with its own licence beside it.
  local ASSETS = "assets/"

  --[[ The ability recast ids whose icons are job-suffixed on the shipped
       sheet: the lv1 SP pool (0), the lv96 SP pool (254), and the GEO/RUN
       lv96 SP2s - Widened Compass and Odyllic Subterfuge - which carry
       their own recast ids (130, 131) instead of sharing 254. Every lv1 SP
       rides recast 0.

       Four lv1 SP icons are missing from the sheet - 00000.01 (Mighty
       Strikes), 00000.16 (Azure Lore), 00000.21 (Bolster) and 00000.22
       (Elemental Sforzo); upstream's sheet has the same holes. For those
       the candidates fall through to icons/custom/ alone: no art is
       invented, custom art is the user's route, exactly as upstream draws
       blank. ]]
  local SP_RECAST_IDS = { [0] = true, [130] = true, [131] = true, [254] = true }
  local SP_SHEET_HOLES = {
    ["00000.01"] = true,
    ["00000.16"] = true,
    ["00000.21"] = true,
    ["00000.22"] = true,
  }

  local RANGED_WEAPONS = { archery = "bow", marksmanship = "gun" }

  function self.icon_candidates(record, meta, state)
    local candidates = {}
    if record == nil then
      return candidates
    end
    meta = meta or {}

    local function add(path, centred)
      local offset = centred and { x = 4, y = 4 } or { x = 0, y = 0 }
      candidates[#candidates + 1] = { path = path, offset = offset }
    end

    -- The explicit override first, custom art before the shipped copy (the
    -- icon-verb contract: <addon>/icons/custom/<name>.png, then the pack) -
    -- then the action's own name under icons/custom/. Note the shipped id
    -- sheets are not complete: ~87 spells (mostly trusts) and ~28 job
    -- abilities have no id art upstream either, so a slot bound to one
    -- draws no icon; icons/custom/ is the route there too.
    if type(record.icon) == "string" then
      -- The custom side flattens a pack-relative override to its basename:
      -- the plan promises users a FLAT icons/custom/ folder, so an override
      -- like items/warp-ring looks for icons/custom/warp-ring.png. The
      -- shipped side keeps the full relative path. A string with no
      -- basename ("", "items/") is no override at all - the pair is
      -- skipped, never a concat throw in the per-frame path.
      local basename = record.icon:match("([^/]+)$")
      if basename ~= nil then
        add("icons/custom/" .. basename .. ".png")
        add(ASSETS .. "icons/" .. record.icon .. ".png")
      end
    end
    local name = record.action or record.type
    if type(name) == "string" then
      -- Flattened the same way: kebab round-trips '/' for real action
      -- names, so a pathological one must not smuggle slashes (or an empty
      -- name) into icons/custom/.
      local flat = kebab(name):match("([^/]+)$")
      if flat ~= nil then
        add("icons/custom/" .. flat .. ".png")
      end
    end

    -- Field guards throughout: hand-edited binding files reach this path,
    -- and a wrong-typed field skips its own candidate rather than throwing
    -- in the draw path.
    if record.type == "ma" or record.type == "ja" or record.type == "pet" then
      -- meta.category is the DISPLAY form ("Blue Magic", "White Magic"):
      -- kebab maps it onto the pack directory (blue-magic). The bar's meta
      -- must hand these display forms, never raw resource types -
      -- "BlueMagic" would kebab to "bluemagic" and silently miss the whole
      -- directory.
      if type(record.action) == "string" and type(meta.category) == "string" then
        add(ASSETS .. "icons/" .. kebab(meta.category) .. "/" .. kebab(record.action) .. ".png")
      end
      if type(meta.recast_id) == "number" then
        -- Only a `ja` record can be an SP: pet records (the blood pacts,
        -- which share recast 0 with the lv1 SPs) take the plain-sheet
        -- branch below, so the recast-0 collision is excluded by record
        -- type - no category value is consulted. Note the suffix wants
        -- the ability's OWNING job: the main job coincides for your own SP,
        -- but a shared set viewed cross-job diverges - the bar's meta
        -- supplies the id that matches the record, not blindly the player.
        if record.type == "ja" and SP_RECAST_IDS[meta.recast_id] then
          -- The SP abilities are stored job-suffixed on the shipped sheet
          -- (00000.02.png ... - no plain 00000.png exists; upstream's
          -- resource_generator builds the same suffix from the owning job).
          -- Without a job id no suffixed file can be named correctly, so
          -- the sheet is skipped rather than guessed at.
          if type(meta.job_id) == "number" then
            local sheet_name = ("%05d.%02d"):format(meta.recast_id, meta.job_id)
            if not SP_SHEET_HOLES[sheet_name] then
              add(ASSETS .. "icons/abilities/" .. sheet_name .. ".png", true)
            end
          end
        else
          local sheet = record.type == "ma" and "spells" or "abilities"
          add(ASSETS .. ("icons/%s/%05d.png"):format(sheet, meta.recast_id), true)
        end
      end
    elseif record.type == "ws" then
      if type(record.action) == "string" and type(meta.weapon) == "string" then
        add(ASSETS .. "icons/weaponskills/" .. kebab(meta.weapon) .. "/" .. kebab(record.action) .. ".png")
      end
      if type(meta.weapon) == "string" then
        -- The weapon-type sheet keeps its spaces ("great axe.png"), so only
        -- the case folds - kebab would miss the file. The sheet has no
        -- archery/marksmanship/throwing art (upstream shares the hole, not
        -- inherited): the first two map to their weapon, throwing to the
        -- generic ranged single.
        local weapon = meta.weapon:lower()
        if weapon == "throwing" then
          add(ASSETS .. "icons/ranged.png")
        else
          add(ASSETS .. "icons/weapons/" .. (RANGED_WEAPONS[weapon] or weapon) .. ".png", true)
        end
      end
    elseif record.type == "item" or record.type == "enchanteditem" then
      -- Both draw the item's own art. Leaving enchanteditem out did not
      -- fall back to something plainer: it fell all the way through to the
      -- built-in defaults, which have nothing for it, so the slot drew
      -- NOTHING while still paying for the DAT extraction.
      if type(record.action) == "string" then
        add(ASSETS .. "icons/items/" .. kebab(record.action) .. ".png")
      end
      if type(meta.item_id) == "number" then
        -- The shared extracted-icon cache beside the addon (lib/icons), NOT
        -- under data/ - see equipviewer for why.
        add(("icons/%d.bmp"):format(meta.item_id), true)
      end
      --[[ An enchanteditem with no target word still aims at <me> (that is
           enchanteditem.lua's default, since gear is worn by the person
           wearing it), so it draws the self-use art rather than the
           generic - the two files agreeing on what "no target" means. ]]
      local on_self = record.target == "me" or (record.type == "enchanteditem" and record.target == nil)
      add(ASSETS .. (on_self and "icons/usable-item.png" or "icons/item.png"))
    elseif record.type == "ra" then
      add(ASSETS .. "icons/ranged.png")
    elseif record.type == "mount" then
      if type(record.action) == "string" then
        add(ASSETS .. "icons/mounts/" .. kebab(record.action) .. ".png")
      end
      add(ASSETS .. "icons/mount.png")
    else
      -- The built-ins resolve through actions.icon_for's type defaults.
      -- ct/ex land here too and icon_for answers nil for them - nothing
      -- shipped depicts an arbitrary chat line or console command, so
      -- those types deliberately resolve only through icons/custom/ and
      -- the record-level override above.
      local builtin = deps.icon_for ~= nil and deps.icon_for(record, state) or nil
      if builtin ~= nil then
        add(ASSETS .. "icons/" .. builtin .. ".png")
      elseif record.type == "open" then
        -- The plan's fallback for opener entries with no single of their
        -- own (equipment, quests, linkshell): a generic opener glyph. The
        -- shipped magnifier is the closest thing the pack has to one. Keyed
        -- on the record and the nil answer, never on whether the dep was
        -- wired.
        add(ASSETS .. "icons/check.png")
      end
    end

    return candidates
  end

  return self
end

return new
