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

--[[ The CB5 crossbar: the persistent cross hotbar, live. Slot presses
     execute their bound actions (bindings from the directory store through
     actions.resolve into ctx.send_command), all three bars own prims - the
     XHB, the WXHB's two separately-anchored halves, and Expanded Hold
     centred on main - and the per-frame tick drives the recast sweep,
     MP/TP costs, unusable dimming, the stratagem, ninja-tool and item
     counters, the press flash, the item-icon extraction queue and the
     pending equip -> wait -> use machine that the warp ladder and an
     enchanteditem binding share.

     The ctx's prim constructors are optional on purpose: without new_image
     the widget runs headless - input machine, bindings, execution, anchors,
     real bounds - which is what the CB2/CB3-era specs exercise and what safe
     degradation looks like if the entry point ever hands out less than it
     should. Every other ctx member is likewise guarded: a missing accessor
     reads as "the client has nothing to say", never a crash.

     The guards wire to what already exists: chat/suppression/layout-mode
     come from ctx, `disabled` is the widget's own visibility (core owns
     whether it is on screen), and edit mode does not exist until CB8. ]]

local new_input = require("components/crossbar/input")
local new_render = require("components/crossbar/render")
local new_actions = require("components/crossbar/actions")
local new_bindings = require("components/crossbar/bindings")
local new_commands = require("components/crossbar/commands")
local new_roulette = require("components/crossbar/roulette")
local new_warp = require("components/crossbar/warp")
local new_enchanteditem = require("components/crossbar/enchanteditem")
local new_stealth = require("components/crossbar/stealth")
local enchanted = require("components/crossbar/enchanted")
local counters = require("components/crossbar/counters")
local openers = require("components/crossbar/openers")
local new_skillchain = require("components/crossbar/skillchain")
local new_retry = require("components/crossbar/retry")
local new_travel = require("components/crossbar/travel")
local new_catalog = require("components/crossbar/catalog")
local new_binder = require("components/crossbar/binder")
local new_weapon = require("components/crossbar/weapon")
local new_icon_cache = require("lib/icon_cache")
local build_defaults = require("components/crossbar/defaults")

--[[ `set` is the active-set label and `weapon` the sword above it. Both
     rode the main anchor at a fixed offset until 2026-08-29, so the only
     way to move either was to move the whole bar (Kevin). ]]
local ANCHORS = { "main", "wxhb_left", "wxhb_right", "set", "weapon", "skillchain_indicator" }

--[[ The five slot groups, in prim-construction order (a spec contract): the
     XHB's two sides on the main anchor, the WXHB's halves on their own
     anchors, and Expanded Hold's single side centred on main. `flag` names
     the render.visible plan key that shows the group; the expanded row has
     none - its plan entry carries the active hold state, not a boolean, and
     refresh keys it on group.key instead. ]]
local GROUPS = {
  { key = "xhb_left", bar = "xhb", side = "left", anchor = "main", flag = "xhb" },
  { key = "xhb_right", bar = "xhb", side = "right", anchor = "main", flag = "xhb" },
  { key = "wxhb_left", bar = "wxhb", side = "left", anchor = "wxhb_left", flag = "wxhb_left" },
  { key = "wxhb_right", bar = "wxhb", side = "right", anchor = "wxhb_right", flag = "wxhb_right" },
  { key = "expanded", bar = "expanded", side = "left", anchor = "main" },
}

-- The asset ROOT, not one folder in it: what hangs off this is `own/` for
-- XIVHud's own chrome, `icons/` for the imported pack and `cooldown/` for
-- the sweep frames, each with its own licence beside it.
local ASSETS = "assets/"
local SLOT_COUNT = 8
local MOUNTED_BUFF = 252
-- Namespaced so a real MyHome on another character neither triggers nor is
-- triggered by us; the receiver matches it exactly.
local IPC_WARP_MESSAGE = "xivhud crossbar warp"
--[[ Windower equipment slot id -> the name GearSwap knows it by, for the
     `gs disable` held over a slot while an enchanted item warms up. The
     warp ladder only ever needed main and ring1; an enchanteditem binding
     can name any worn piece, so the whole map is here.

     The IDS are attested in this repo - equipviewer/logic.lua carries all
     sixteen as the client's own equipment-table keys. The NAMES are not:
     the client calls id 13 `left_ring` where GearSwap wants `ring1`, and
     the same for the other ear and ring slots. Question J. ]]
local GS_SLOT_NAMES = {
  [0] = "main",
  [1] = "sub",
  [2] = "range",
  [3] = "ammo",
  [4] = "head",
  [5] = "body",
  [6] = "hands",
  [7] = "legs",
  [8] = "feet",
  [9] = "neck",
  [10] = "waist",
  [11] = "ear1",
  [12] = "ear2",
  [13] = "ring1",
  [14] = "ring2",
  [15] = "back",
}
local EQUIPPED = enchanted.EQUIPPED
--[[ How far past its own give-up bound a pending wait may run before the
     wall clock ends it. enchanted.step abandons any wait whose REMAINING
     delay exceeds that bound, so a wait it accepts must finish inside it;
     the margin covers equip latency and a set_equip that silently no-opped
     (Windower drops mismatched args), which would otherwise freeze
     activation_time and answer "wait" forever.

     Added to the PLAN's bound rather than a fixed 45: a rung that waits
     longer needs a ceiling that waits longer too, or the deadline ends the
     very wait the longer bound was granted for. ]]
local PENDING_DEADLINE_MARGIN = 15
-- enchanted.step's own default, for a plan that names no bound of its
-- own. Read from the module rather than copied, so the deadline and the
-- abandon message cannot drift from the bound `step` actually applies.
local DEFAULT_GIVE_UP_SECONDS = enchanted.give_up_default()
-- Upstream's fixed overlay alpha for the recast sweep and the red X.
local OVERLAY_ALPHA = 150
-- The tool-count colour bands, upstream's own RGB (ui.lua:963-967).
local TOOL_COLORS = {
  green = { 0, 255, 0 },
  yellow = { 255, 255, 0 },
  red = { 255, 0, 0 },
}
--[[ The set indicator's gold (Kevin, 2026-08-21). FFXIV writes the active
     set along the bottom of the cross hotbar, between the two halves, and
     without it an empty bar gives no sign that a switch did anything - which
     is how it was found. ]]
local SET_LABEL_COLOR = { 255, 215, 0 }
-- parambar's size, which is what the indicator was asked to match; its font
-- is the component's own `font`, already sans-serif as parambar's is.
local SET_LABEL_SIZE = 14
-- Counts with no colour meaning of their own - stratagem charges and item
-- counts - are drawn in explicit white, never left inheriting whatever the
-- cost prim last showed (the fork sets no colour there at all).
local PLAIN_COUNT_COLOR = { 255, 255, 255 }
-- The skillchain indicator's shipped colours and opacity - the fallbacks
-- when the config's skillchain block is hand-broken - and its constant
-- black backdrop (upstream's own 150-alpha black).
local SC_WAITING_COLOR = { r = 237, g = 28, b = 36 }
local SC_OPEN_COLOR = { r = 15, g = 205, b = 5 }
local SC_OPACITY = 220
local SC_BG_ALPHA = 150
-- The chain-result overlay's dim state, upstream's numbers: a WS slot short
-- of its 1000 TP draws the result at 75 over a 150 frame.
local SC_DIM_ICON_ALPHA = 75
local SC_DIM_FRAME_ALPHA = 150
-- The chunks the skillchain engine feeds on beyond the action packet: the
-- action message (buff wear-off), the buff-list refresh, and zone-out.
local ACTION_CHUNK = 0x028
--[[ `0x01E` Modify Inventory (Count, Bag, Index, Status - read from
     Windower's own packets/fields.lua): the packet a stack DECREMENT rides.
     `add item`/`remove item` fire when a record enters or leaves a bag, so
     using one of five never reached the count and only the last one did
     (Kevin, live client, 2026-08-22). It carries no item id, so unlike the
     events it cannot be gated on which id moved - only on whether the bar
     draws a count at all. ]]
local INVENTORY_CHUNK = 0x01E
--[[ The two packets the weapon layer follows: `0x050` Equip, which says a
     slot changed, and `0x01D` Finish Inventory, the login and zone-in bag
     dump without which the first read of a session finds nothing to name.
     Both are the ids equipviewer keys its own grid off.

     The Equip packet is READ rather than merely counted, and by its field
     name rather than by an offset, the way equipviewer reads the same one.
     Answering it costs a whole-inventory `get_equipment`, and GearSwap
     fires one of these per slot it swaps on every cast - sixteen of them a
     spell, none of which can move a layer keyed to the MAIN hand. A packet
     that will not decode arms the read anyway: a decode that fails must not
     freeze the layer for the session. ]]
local EQUIP_CHUNK = 0x050
local INVENTORY_READY_CHUNK = 0x01D
-- Equipment slot 0 is the main hand (equipviewer's own slot table).
local MAIN_HAND_SLOT = 0
-- Zoning out: every mob id on this side of the line is stale, and so is any
-- cast the retry is still holding.
local ZONE_OUT_CHUNK = 0x0B
local SC_CHUNKS = { [0x29] = true, [0x63] = true, [ZONE_OUT_CHUNK] = true }
-- The player statuses that mean dead ("Dead" and "Engaged dead"): whatever
-- was in flight when you fell is not worth sending afterwards.
local DEAD_STATUSES = { [2] = true, [3] = true }

--[[ How the cast retry treats a bound record's target word, in three
     groups. A command's target is resolved by the GAME when the command is
     sent, so a re-send would otherwise land wherever the token points THEN
     - "at whatever you are now pointed at", the reference queue's own
     defect. The answer is to PIN: resolve the token to a mob id at the
     press and send the id in place of the token when re-sending, so the
     cast lands on what was aimed at however far the cursor has wandered.

     PINNED: `<t>` and `<bt>`. Deliberately only these two: they are the
     tokens this repo already asks `get_mob_by_target` for (skillchain.lua
     passes exactly `"t", "bt"`), and CLAUDE.md's rule is that Windower
     behaviour is unverified until it has been read for - a user-authored
     word is never handed to the client's lookup on a guess.

     FIXED: yourself and your pet. Nothing a cursor or a roster can move,
     so the re-send is the press verbatim and no pin is needed.

     EVERYTHING ELSE IS NOT WATCHED AT ALL - the rule is the two lists
     above, not the cases below, so a token nobody thought of falls out
     unwatched rather than guessed at. The cases worth naming:

     - the subtarget family (`<stpc>` and friends), which would re-open a
       selection cursor the player has already answered;
     - a record with no target word, whose command has nothing to
       substitute;
     - **party and alliance slots** (decided 2026-08-19). `<p3>` is whoever
       is standing third, not a person: a member leaving or zoning inside
       the deadline shifts everyone below them, and a re-send would land on
       someone the press never meant. Pinning them by id would need
       `get_mob_by_target("p3")` to work, which nobody here has read for,
       so the honest answer is not to hold them at all;
     - and the rest of what the bind parser accepts - `<ft>`, `<r>`,
       `<scan>`, `<lastst>`, `<stal>` - which are simply on neither list.
       Adding one means deciding whether it can be pinned, and that is a
       question about the client nobody here has answered. ]]
local FIXED_TARGETS = { me = true, pet = true }
local PINNED_TARGETS = { t = true, bt = true }

--[[ Bind types the cast retry watches, mapped to the kind whose refusal
     message and blocking buffs answer them (retry.lua owns both tables).
     Everything absent is never watched: an item, a `ct` line, a console
     command and the built-ins are all refused - where they are refused at
     all - in words nothing here reads.

     `pet` is deliberately out. A blood pact is an ability by every other
     measure in this component, but it goes out as its own command word and
     nobody has seen which message refuses it; guessing it is `ja`'s would
     be the one thing this feature must not do. ]]
local RETRY_KINDS = { ma = "spell", ja = "ability", ws = "weaponskill" }

-- The resource table each bindable type's action name lives in -- the same
-- mapping meta_for reads, exposed for the CLI's "is that really an action?"
-- question.
local RESOURCE_TABLES = {
  ma = "spells",
  ja = "job_abilities",
  pet = "job_abilities",
  ws = "weapon_skills",
  item = "items",
  enchanteditem = "items",
  mount = "mounts",
}

local function new(ctx)
  local self = { name = "crossbar", alias = "cb", wants_store = true }

  -- Per-anchor placement pushed by core.
  local placed = {}
  --[[ The anchors core has switched off, one at a time. Kept apart from
       `placed` because a hidden anchor is still PLACED: core clamps it on
       screen from get_bounds and layout mode drags it, so only the drawing
       reads below go through anchor_at. ]]
  local hidden_anchors = {}

  local function anchor_at(anchor)
    if hidden_anchors[anchor] then
      return nil
    end
    return placed[anchor]
  end

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults

  local function say(lines)
    if ctx.say ~= nil and lines ~= nil then
      ctx.say(lines)
    end
  end

  --[[ A travel countdown's NAMED lines - the one that arms it and the one
       that calls it off - carry the component's prefix like every other
       line it says. The bare counts ("4...") deliberately do not: they read
       as a continuation of the line that named them, and five prefixed
       lines per mount is the chat spam this repo treats as a defect. ]]
  local function say_travel(line)
    if line ~= nil then
      say("crossbar: " .. line)
    end
  end

  local function send_command(command)
    if ctx.send_command ~= nil then
      ctx.send_command(command)
    end
  end

  -- Wall clock for the extdata maths (their timestamps are os.time-based);
  -- ctx.now is the monotonic frame clock and would misread every enchant.
  local function time_now()
    if ctx.time ~= nil then
      return ctx.time()
    end
    return 0
  end

  -- The monotonic frame clock, for durations measured in play (the mount
  -- recast). Distinct from time_now() above, which is wall clock and would
  -- not move at all between two frames.
  local function frame_now()
    if ctx.now ~= nil then
      return ctx.now()
    end
    return 0
  end

  local function get_player()
    if ctx.get_player ~= nil then
      return ctx.get_player()
    end
    return nil
  end

  local function file_exists(relative)
    return ctx.file_exists ~= nil and ctx.asset ~= nil and ctx.file_exists(ctx.asset(relative)) == true
  end

  -- icon_for reads only the module-level built-in table, so an actions
  -- instance with no execution deps is enough for icon resolution.
  local icon_for = new_actions({}).icon_for

  -- Rebuilt at attach over the live config; the defaults-backed one answers
  -- bounds for layout mode before any login has attached a config.
  local render = new_render({ config = self.defaults, icon_for = icon_for })

  --[[ Execution collaborators. Mount roulette needs the resource tables, so
       without them it degrades to a no-op ride; warp degrades rung by rung
       (an empty bag table walks to "you don't have it"). ]]
  local resources = ctx.resources

  local roulette = nil
  if resources ~= nil then
    roulette = new_roulette({
      mounts = resources.mounts or {},
      key_items = resources.key_items or {},
      get_key_items = function()
        if ctx.get_key_items ~= nil then
          return ctx.get_key_items()
        end
        return {}
      end,
      get_buffs = function()
        local player = get_player()
        return player and player.buffs or {}
      end,
      -- Whether this zone allows mounting at all, and which zone that is.
      zones = resources.zones,
      -- The recast's clock, read by the module itself: both the drawing and
      -- the press refusal must agree about how far along it is.
      now = frame_now,
      get_zone = function()
        local info = ctx.zone ~= nil and ctx.zone() or nil
        return info
      end,
      random = ctx.random or math.random,
    })
  end

  local equip_bags = {}
  if resources ~= nil then
    for id, bag in pairs(resources.bags or {}) do
      if type(bag) == "table" then
        equip_bags[id] = { name = bag.name or bag.en or tostring(id), equippable = bag.equippable and true or false }
      end
    end
  end

  --[[ The weapon layer's resolver. Built only WITH the resources - the
       class is a skill name off `res.items`/`res.skills`, so without them
       there is no answer to be had and the refresh below must not go on
       asking the client for one every interval for the rest of the
       session. Without it the layer simply never comes up, and the rest of
       the bar carries on (the cast bar's posture in targetbar). ]]
  local weapon_layer = nil
  if resources ~= nil then
    weapon_layer = new_weapon({
      get_equipment = ctx.get_equipment,
      get_items = ctx.get_items,
      resources = resources,
    })
  end

  -- Shared by the warp ladder and by a named enchanteditem binding: both
  -- search the same bags and read the same extdata.
  local function read_bag(bag)
    if ctx.get_items ~= nil then
      return ctx.get_items(bag)
    end
    return nil
  end

  local function read_ext(item)
    return ctx.decode_extdata ~= nil and ctx.decode_extdata(item) or nil
  end

  --[[ The warp ladder's own reading of a decode it did not get: "not
       usable, not enchanted", so the rung is noted and the walk carries on
       to the next one rather than crashing.

       enchanteditem deliberately does NOT get this substitute. It has one
       item and no next rung, so "I could not read it" is a different answer
       from "it is a plain item" - the latter sends a /item the game will
       refuse, and tells the player nothing about why. ]]
  local function decode_ext(item)
    return read_ext(item) or { type = "unavailable" }
  end

  --[[ Forward declaration: an enchanteditem binding names its item, so the
       module needs the resource index - which is built further down, after
       the actions table it has to be handed to. ]]
  local resource_by_name

  local warp = new_warp({
    bags = equip_bags,
    get_player = get_player,
    get_spells = function()
      if ctx.get_spells ~= nil then
        return ctx.get_spells()
      end
      return {}
    end,
    get_items = read_bag,
    extdata_decode = decode_ext,
    now = time_now,
    -- A ladder rung carrying a name rather than an id resolves it here.
    find_item = function(name)
      return resource_by_name("items", name)
    end,
  })

  local enchanteditem = new_enchanteditem({
    bags = equip_bags,
    get_player = get_player,
    get_items = read_bag,
    extdata_decode = read_ext,
    now = time_now,
    find_item = function(name)
      return resource_by_name("items", name)
    end,
  })

  --[[ A PRESS-TIME bag read, deliberately not the per-frame `item_counts`
       tally: that one is maintained only for ids some painted slot is
       bound to, and the stealth ladder asks about ids nothing need be
       bound to at all. A press happens seconds apart, so reading the bag
       then is both cheap and always current.

       Bag 0 alone. A ninja tool or a Silent Oil in a wardrobe is not one
       the game will let you use, which is the same rule the slot counters
       apply to a consumable. ]]
  local function tally_inventory(matches)
    local counts = {}
    local bag = read_bag(0)
    if type(bag) ~= "table" or bag.enabled == false then
      return nil
    end
    for _, item in ipairs(bag) do
      if type(item) == "table" and type(item.id) == "number" and item.id ~= 0 and matches(item.id) then
        counts[item.id] = (counts[item.id] or 0) + (item.count or 0)
      end
    end
    return counts
  end

  local stealth = new_stealth({
    get_player = get_player,
    get_spells = function()
      if ctx.get_spells ~= nil then
        return ctx.get_spells()
      end
      return {}
    end,
    get_abilities = ctx.get_abilities,
    resources = resources,
    tool_counts = function()
      return tally_inventory(counters.tracked_item) or {}
    end,
    --[[ nil, never 0, when the item cannot be resolved or the bag cannot be
         read: the ladder reads a real 0 as "you have none" and skips the
         rung, and refusing a press that might have worked is worse than
         letting the game answer for itself. ]]
    item_count = function(name)
      local entry = resource_by_name("items", name)
      local id = type(entry) == "table" and entry.id or nil
      if type(id) ~= "number" then
        return nil
      end
      local counts = tally_inventory(function(candidate)
        return candidate == id
      end)
      return counts ~= nil and (counts[id] or 0) or nil
    end,
    get_target = function()
      return ctx.get_mob_by_target ~= nil and ctx.get_mob_by_target("t") or nil
    end,
  })

  local actions = new_actions({
    roulette = roulette or {
      ride = function()
        return nil
      end,
    },
    warp = warp,
    enchanteditem = enchanteditem,
    stealth = stealth,
  })

  --[[ The chain-state engine (CB6): pure, always built - it needs no
       resources, only the clock and the target, and degrades to "no chain"
       without either. 't' falling back to 'bt' is the reference's own read:
       the chain you are fighting is the one that matters mid-cast.

       The target dep is memoized PER TICK: the engine asks for the target
       from window() and again from every bound slot's result(), which
       during an open window would be a client read per slot per frame.
       One read per tick is the contract (targetbar's "the target itself is
       read per frame" precedent - deliberately fresher than the 200ms
       cache, so a target switch drops the indicator the same frame); the
       memo lives in the dep, keeping the engine's API untouched. ]]
  local sc_target = nil
  local sc_target_read = false

  local skillchain = new_skillchain({
    now = function()
      if ctx.now ~= nil then
        return ctx.now()
      end
      return 0
    end,
    get_mob_by_target = function()
      if not sc_target_read then
        sc_target_read = true
        sc_target = nil
        if ctx.get_mob_by_target ~= nil then
          sc_target = ctx.get_mob_by_target("t", "bt")
        end
      end
      return sc_target
    end,
    get_player = get_player,
  })

  --[[ The cast retry (CB9): one refused spell, re-sent. It reads the config
       through a closure rather than a copy, so `//hud crossbar retry off`
       reaches it the moment the write lands - including with a cast already
       pending, which it drops rather than firing. ]]
  local retry = new_retry({
    now = function()
      if ctx.now ~= nil then
        return ctx.now()
      end
      return 0
    end,
    config = function()
      return config.retry
    end,
    get_player = get_player,
  })

  --[[ The travel countdown (CB10): mount, mount roulette and warp wait five
       seconds, saying so once a second, before they go. The config is read
       through a closure for the same reason the retry's is - a write to
       `delay` reaches it at once, including the zero that switches it off.

       The resource table goes in whole: the module resolves the resting
       status out of it by english name rather than trusting a number from
       memory, and degrades to its own constant when resources did not
       load. ]]
  local travel = new_travel({
    now = function()
      if ctx.now ~= nil then
        return ctx.now()
      end
      return 0
    end,
    config = function()
      return config
    end,
    statuses = resources ~= nil and resources.statuses or nil,
  })

  --[[ The item-icon extraction pipeline (lib/icon_cache): built only when
       the ctx carries the file surface; a config-level game_path override
       wins over the client's own answer, equipviewer's convention.

       Deliberately a SEPARATE instance per component: the on-disk cache
       under <addon>/icons/ is shared (an icon either component extracts is
       found by the other through cached_icon), but the queues and
       abandoned-lists are not, so one session can in the worst case
       extract an icon twice - once per component - before the disk copy
       wins. Accepted as the cost of no cross-component coupling; a shared
       lib-level instance is the fallback if a third consumer appears. ]]
  local icon_cache = nil
  if ctx.file_exists ~= nil and ctx.read_dat ~= nil and ctx.write_binary ~= nil and ctx.asset ~= nil then
    icon_cache = new_icon_cache({
      asset = ctx.asset,
      file_exists = ctx.file_exists,
      read_dat = ctx.read_dat,
      write_binary = ctx.write_binary,
      game_path = function()
        -- Empty is "no override" (equipviewer's own guard shape): the
        -- shipped default is "" so the key is discoverable, and a copied
        -- equipviewer idiom must not silently abandon every item icon.
        if type(config.game_path) == "string" and config.game_path ~= "" then
          return config.game_path
        end
        return ctx.game_path ~= nil and ctx.game_path() or nil
      end,
    })
  end

  local machine = nil
  --[[ The binder (CB8), declared here and built far below: everything it
       needs - the render instance, the model, the drawn groups, the icon
       and tooltip lookups - is a local defined later in this constructor,
       while refresh() and paint_slot() above it must already be able to ask
       whether edit mode is on. Its prims exist only while edit mode is
       open, so a closed binder costs nothing on the tick path. ]]
  local binder = nil
  -- The simulated buff list while the binder previews a context, or nil for
  -- "the client's own". Declared with the binder because apply_buffs()
  -- below is the only reader and the preview callback the only writer.
  local previewing = nil
  local function editing()
    return binder ~= nil and binder.active()
  end

  local visible = false
  local preview = false
  local active_state = "none"

  -- The job scope: nil until the client can name a main job; a `job change`
  -- notes the id it announced so a stale get_player() is not rescoped.
  local scoped_main = nil
  local scoped_sub = nil
  local rescope_want = nil

  --[[ Item counts for the slot corners: ninja/Corsair tools and every
       consumable a slot is bound to, from the inventory, plus enchanted
       gear from the other equippable bags. Re-read when an item event
       names an id something is bound to (giltracker's pattern), and when a
       repaint changes WHICH ids those are. ]]
  local item_counts = {}
  local gear_counts = {}
  local temporary_seen = false
  local counts_dirty = true
  --[[ Whether the class in the main hand needs re-reading. `get_equipment`
       is a whole-inventory call, so it is asked only when a packet or a
       rescope says the gear may have moved - never per frame - and the
       answer is then taken at most once per client interval, off the same
       generation counter the recast reads are gated on.

       It starts DOWN, unlike `counts_dirty`: every attach clears the scope,
       so the first tick of any attach goes through try_scope, which arms it
       there. An attach that armed it as well would be a second path to the
       same state that no test could tell from the first. ]]
  local weapon_dirty = false
  --[[ The bound-id set as it stood at the last repaint, so a repaint that
       changed nothing worth counting costs no client read. Forward-declared
       because repaint sits well above the counting code that builds it. ]]
  local counted_signature = nil
  local bound_item_signature
  -- Forward-declared: the tick's config-mode gate calls it well above the
  -- status handlers it sits with.
  local end_trip

  -- The pending equip -> wait -> use machine, shared by the warp ladder and
  -- an enchanteditem binding: gs disable, equip, wait, use, with `gs enable`
  -- on every exit path (success, give-up, suppression, detach) for every
  -- slot it held. One at a time, whichever armed it.
  local pending_item = nil
  -- Seconds of a warm-up spoken one at a time, counting back from the end.
  -- travel.lua counts its own the same way and for the same reason.
  local PENDING_COUNT_FROM = 5

  local function build_bindings(store)
    local function nothing() end
    return new_bindings({
      -- Store reads land only in set_job - once per file per scope (attach,
      -- job change), never per frame - so lib/settings' "missing file is
      -- re-read per call" contract costs one stat per absent job file per
      -- scope and needs no negative-cache sentinel.
      load = store ~= nil and store.load or nothing,
      save = store ~= nil and store.save or nothing,
      get_config = function()
        return config
      end,
    })
  end

  local bindings = build_bindings(nil)

  -- Core's config save, handed in at attach: the authoring verbs that write
  -- the component's own config need it, and nothing else here does.
  local save = nil

  --[[ Resource name lookups, indexed lazily by lowercased English name; the
       items table alone is tens of thousands of entries, so nothing walks it
       until something actually needs it - an item record being painted, or
       a warp press reaching a rung that names its item rather than
       numbering it. ]]
  local name_indexes = {}
  function resource_by_name(table_name, name)
    if resources == nil or type(name) ~= "string" then
      return nil
    end
    local index = name_indexes[table_name]
    if index == nil then
      index = {}
      for _, entry in pairs(resources[table_name] or {}) do
        if type(entry) == "table" and type(entry.en) == "string" then
          index[entry.en:lower()] = entry
        end
      end
      name_indexes[table_name] = index
    end
    return index[name:lower()]
  end

  -- Built here rather than beside the model: its action_exists dep closes
  -- over resource_by_name, whose forward declaration sits with the other
  -- state at the top of new() and which is only ASSIGNED just above.
  --[[ The authoring CLI (CB7). Reads the model through a getter, since
       attach and detach rebuild it, and validates an icon name against the
       same two candidates render.icon_candidates draws from - the player's
       own art first, then the shipped pack. ]]
  local authoring = new_commands({
    bindings = function()
      return bindings
    end,
    get_config = function()
      return config
    end,
    file_exists = file_exists,
    validate = actions.validate,
    action_exists = function(kind, name)
      local table_name = RESOURCE_TABLES[kind]
      if resources == nil or table_name == nil then
        -- Nothing to check against: the CLI keeps the user's reading and
        -- says so, rather than guessing.
        return nil
      end
      return resource_by_name(table_name, name) ~= nil
    end,
  })

  --[[ The load-time check actions.lua documents: a built-in action name
       must not shadow an authoring verb, the way the registry validates a
       component name against the reserved command words. It could only ever
       fire on a code change, so it is said to chat rather than thrown -- an
       error here would take the whole component down over a naming slip,
       and the addon's own posture is that a load failure must stay
       diagnosable. ]]
  local collisions = actions.check_collisions(authoring.verbs())
  if #collisions > 0 then
    say("crossbar: built-in action name(s) shadow an authoring verb: " .. table.concat(collisions, ", "))
  end

  -- "WhiteMagic" -> "White Magic": meta.category is the DISPLAY form (the
  -- icon-candidate contract) - kebab maps it to the pack directory, and the
  -- raw resource type would silently miss the whole directory.
  local function display_category(resource_type)
    if type(resource_type) ~= "string" then
      return nil
    end
    return (resource_type:gsub("(%l)(%u)", "%1 %2"))
  end

  --[[ What the resources know about a bound record: recast id, costs, the
       icon-resolution fields. The SP job suffix takes the player's main job
       id - the owning job coincides for your own SP; a shared set viewed
       cross-job may draw the viewing job's art (accepted, same as binding
       it fresh). ]]
  local function meta_for(record)
    if record == nil then
      return nil
    end
    if record.type == "ma" then
      local spell = resource_by_name("spells", record.action)
      if spell ~= nil then
        return {
          kind = "spell",
          spell_id = spell.id,
          recast_id = spell.recast_id,
          mp_cost = spell.mp_cost,
          category = display_category(spell.type),
        }
      end
    elseif record.type == "ja" or record.type == "pet" then
      local ability = resource_by_name("job_abilities", record.action)
      if ability ~= nil then
        local player = get_player()
        return {
          kind = "ability",
          -- The ability's own id, for the chain-result lookup: recast ids
          -- are shared pool timers (every blood pact rides 173, every
          -- Ready move 102) and can never address the chain table.
          ability_id = ability.id,
          recast_id = ability.recast_id,
          mp_cost = ability.mp_cost,
          tp_cost = ability.tp_cost,
          job_id = player and player.main_job_id or nil,
        }
      end
    elseif record.type == "ws" then
      local ws = resource_by_name("weapon_skills", record.action)
      if ws ~= nil then
        local skill = resources ~= nil and resources.skills and resources.skills[ws.skill] or nil
        return { kind = "ws", ws_id = ws.id, weapon = skill and skill.en or nil, tp_cost = 1000 }
      end
    elseif record.type == "item" or record.type == "enchanteditem" then
      -- Both draw the item's own icon and count its copies; the difference
      -- between them is how the press fires, not what the slot shows.
      local item = resource_by_name("items", record.action)
      if item ~= nil then
        return { kind = "item", item_id = item.id }
      end
    end
    return nil
  end

  -- The two framework states that make the crossbar inert without hiding
  -- it, read the way input.lua reads them (a missing dep is "no").
  local function chat_open()
    return ctx.chat_open ~= nil and ctx.chat_open() == true
  end

  local function layout_active()
    return ctx.layout_active ~= nil and ctx.layout_active() == true
  end

  --[[ The id the given target token points at right now, for the cast
       retry's pin alone. The RECORD's own token, not always `t`: `<bt>` and
       `<t>` are different selections. Read once on a press of a
       token-targeted spell - never per frame, and not at all while the
       feature is off. ]]
  local function selected_id(token)
    local mob = ctx.get_mob_by_target ~= nil and ctx.get_mob_by_target(token) or nil
    return mob ~= nil and mob.id or nil
  end

  --[[ The command the cast retry would RE-SEND for a press, or nil for a
       press it must not watch at all. The first send is never touched: it
       goes out with the token exactly as it always did, and only this
       later copy names a concrete mob.

       A pinned token becomes the id it stood for at the press - the shape
       the reference addon sends, `/ma "Fire IV" 16941234`. The suffix is
       matched and replaced literally rather than by pattern, and a command
       that does not end in the expected `<token>` is not watched: a
       substitution this cannot prove correct is worse than no retry. ]]
  local function resend_command(command, target)
    if type(command) ~= "string" then
      return nil
    end
    -- Folded, because the config files are hand-editable: the CLI writes
    -- lower case, but `target = "T"` fires in game exactly as `t` does and
    -- must not go unwatched for the capital.
    target = type(target) == "string" and target:lower() or target
    if FIXED_TARGETS[target] then
      return command
    end
    if not PINNED_TARGETS[target] then
      -- Not watched: a subtarget prompt, a bracketed name, or no target
      -- word at all. A nil target lands here too, and deliberately - the
      -- command has nothing to substitute, and appending a target would
      -- send a shape the press itself never used.
      return nil
    end
    local id = selected_id(target)
    if id == nil then
      -- Pressed with nothing selected there is no id to carry, and
      -- re-resolving the token later is the behaviour the pin exists to
      -- prevent.
      return nil
    end
    -- The suffix is matched case-insensitively for the same reason, over a
    -- tail of the command's own length rather than a pattern.
    local suffix = " <" .. target .. ">"
    if command:sub(-#suffix):lower() ~= suffix then
      -- Unreachable as things stand: actions.resolve appends the target
      -- suffix last for every `ma` record, so a watched command always ends
      -- in it. Kept as the one thing that makes the substitution provable
      -- rather than assumed, not as a branch anything can cover.
      return nil
    end
    return command:sub(1, #command - #suffix) .. " " .. tostring(id)
  end

  local function draw_state()
    local player = get_player()
    local mounted = false
    for _, buff in ipairs(player and player.buffs or {}) do
      if buff == MOUNTED_BUFF then
        mounted = true
        break
      end
    end
    --[[ No `has_target` any more: `draw` stopped sending `/attack <t>`
         (2026-08-22), and that check was its only reader - so this is one
         fewer client read on every path that asks for the draw state,
         including the per-repaint icon walk. ]]
    return {
      mounted = mounted,
      weapon_drawn = bindings.weapon_state() == "drawn",
    }
  end

  --[[ Prims. Or nil when the ctx has no constructors (the headless shape the
       CB2/CB3 specs run). Construction order is a spec contract AND the
       z-order: the panel, then per group and slot six images in upstream's
       own layering - background, chain overlay, icon, sweep, frame,
       feedback - and three texts (name, cost, recast), then the skillchain
       indicator's bg and fill. The sweep overlay doubles as the red X over
       an empty-tool slot - upstream's own prim reuse; the chain overlay
       gets its own prim because, unlike the X, it must draw WITH the
       sweep, not instead of it. ]]
  local prims = nil
  if ctx.new_image ~= nil and ctx.new_text ~= nil and ctx.asset ~= nil then
    --[[ Sibling-component construction hygiene: draggable off, one tile,
         never fit-to-texture (fit(true) silently defeats size()), an
         explicit untinted color, and hidden from the first frame. `texture`
         is optional - the icon and sweep prims have no art until content
         picks one. Alphas are config-owned and land at attach. ]]
    --[[ `texture` is relative to the ASSET ROOT, not to any one folder in
         it. It used to have `own/` put in front, which was right for the
         chrome and silently wrong for the sword - `assets/own/icons/...`
         does not exist, and a missing texture draws a bare square rather
         than complaining. Each caller names its own folder now. ]]
    local function image(texture)
      local prim = ctx.new_image()
      prim.draggable(false)
      prim.repeat_xy(1, 1)
      prim.fit(false)
      if texture ~= nil then
        prim.path(ctx.asset(ASSETS .. texture))
      end
      prim.color(255, 255, 255)
      prim.hide()
      return prim
    end

    local function text()
      local prim = ctx.new_text()
      prim.text("")
      prim.hide()
      return prim
    end

    prims = { panel = image("own/bar_bg_compact.png"), groups = {} }
    for _, group in ipairs(GROUPS) do
      local slots = {}
      for slot = 1, SLOT_COUNT do
        -- Field order IS z-order (creation order draws bottom to top),
        -- mirroring upstream's ui.lua:407-412: background, then the chain
        -- overlay (CB6's per-slot chain result, upstream's slot_warmup),
        -- icon, the sweep/red-X overlay, the frame - so the frame-step
        -- border animation draws OVER the chain icon and the sweep, as
        -- shipped - and the press flash above everything, which is where
        -- the reference loads its feedback icon ("last so it stays above
        -- everything else").
        slots[slot] = {
          background = image("own/slot.png"),
          chain = image(),
          icon = image(),
          sweep = image(),
          frame = image("own/frame.png"),
          feedback = image("own/feedback.png"),
          name = text(),
          cost = text(),
          recast = text(),
        }
      end
      prims.groups[group.key] = slots
    end
    -- The skillchain indicator, on its own anchor: a black backdrop and a
    -- centre-anchored fill, both the component's own white square tinted at
    -- draw time (fill after bg, so it draws on top).
    --[[ Created BEFORE the indicator on purpose: the skillchain pair has to
         stay last in the image list, which is how the specs address it. ]]
    prims.set_icon = image("icons/weapons/sword.png")
    -- The skillchain indicator, last.
    prims.indicator = { bg = image("own/indicator.png"), fill = image("own/indicator.png") }
    -- The active set, written between the two crosses, with the sword that
    -- marks the drawn weapon state to its left.
    prims.set_label = text()
  end

  -- Per-slot content resolved at repaint time: the record, its meta, the
  -- icon candidate that won, and the press-flash alpha in flight.
  local contents = {}
  local function reset_contents()
    contents = {}
    for _, group in ipairs(GROUPS) do
      contents[group.key] = {}
      for slot = 1, SLOT_COUNT do
        -- The sweep key is per prim slot and built once - never per frame.
        local sweep_key = group.key .. ":" .. slot
        contents[group.key][slot] = { written = {}, sweep_key = sweep_key }
        render.clear_sweep(sweep_key)
      end
    end
  end
  reset_contents()

  -- Which groups the last refresh left on screen, so the tick skips the rest.
  local shown_groups = {}

  --[[ The indicator's own change-gate cache (it is not a slot): the fill and
       bg geometry last pushed, the colour state, and visibility. Wiped by
       layout() - anchor moves and scales land there - so the next tick
       reapplies everything against the new origin. ]]
  local indicator_written = { fill = {}, bg = {} }

  local function reset_indicator_written()
    indicator_written = { fill = {}, bg = {} }
  end

  --[[ The indicator down with the widget - draw_indicator's own no-plan
       branch, reached from refresh() instead of the tick. The cache is NOT
       wiped: hiding a prim does not make it forget where it is, so what the
       gate holds stays true across the hide, and layout() is what invalidates
       it when the anchor actually moves. Only the two keys that changed are
       written, so a widget that is already hidden costs nothing to keep
       hidden - core calls refresh once per mouse move of a drag. ]]
  local function hide_indicator()
    if prims == nil then
      return
    end
    if indicator_written.visible ~= false then
      indicator_written.visible = false
      indicator_written.state = nil
      prims.indicator.bg.hide()
      prims.indicator.fill.hide()
    end
  end

  -- One prim's gated pos/size push against its cache slot.
  local function push_rect(prim, cache, x, y, width, height)
    if cache.x ~= x or cache.y ~= y then
      cache.x, cache.y = x, y
      prim.pos(x, y)
    end
    if cache.w ~= width or cache.h ~= height then
      cache.w, cache.h = width, height
      prim.size(width, height)
    end
  end

  local function placement(anchor)
    if render.bounds(anchor) == nil then
      return nil
    end
    local entry = placed[anchor]
    if not entry then
      entry = { scale = 1 }
      placed[anchor] = entry
    end
    return entry
  end

  function self.anchors()
    return ANCHORS
  end

  local function config_hide(key)
    local hide = config.hide
    return type(hide) == "table" and hide[key] == true
  end

  -- The (set, side) a group displays; nil while no job is scoped or the
  -- view config is broken. Expanded shows whichever view its press order
  -- selected, and nothing while it is not held.
  local function group_target(group)
    if scoped_main == nil then
      return nil
    end
    if group.bar == "xhb" then
      return bindings.active_set(), group.side
    end
    local view_name = group.key
    if group.key == "expanded" then
      if active_state ~= "expanded_lr" and active_state ~= "expanded_rl" then
        return nil
      end
      view_name = active_state
    end
    local view = bindings.view_target(view_name)
    if type(view) ~= "table" then
      return nil
    end
    return view.set, view.side
  end

  -- Applies values that live in config; construction only knows paths.
  local function dress()
    if prims == nil then
      return
    end
    local text_color = type(config.text_color) == "table" and config.text_color or {}
    local stroke = type(config.text_stroke) == "table" and config.text_stroke or {}
    local function dress_text(prim, right_justified)
      prim.font(config.font or "sans-serif")
      prim.size(config.font_size or 7)
      prim.color(text_color.r or 255, text_color.g or 255, text_color.b or 255)
      prim.alpha(text_color.a or 255)
      prim.stroke_width(stroke.width or 0)
      prim.stroke_color(stroke.r or 0, stroke.g or 0, stroke.b or 0)
      -- stroke_alpha, not stroke_transparency: the library reads a 0..1
      -- transparency and would turn a 0-255 alpha wildly negative.
      prim.stroke_alpha(stroke.a or 255)
      -- The texts library draws its own opaque box behind a line unless
      -- told not to, and every sibling widget turns it off (parambar,
      -- partylist, targetbar, equipviewer, lib/overlay). Missing here since
      -- CB4 - a slot label would have carried a black box over the art.
      prim.bg_visible(false)
      prim.right_justified(right_justified == true)
    end
    prims.panel.alpha(config.button_bg_alpha)
    --[[ The set label takes the same dressing every other text gets - the
         stroke, and above all `bg_visible(false)`, without which the texts
         library draws an opaque box behind it - then overrides the two
         things that make it the set label: parambar's size, and gold. ]]
    dress_text(prims.set_label, false)
    prims.set_label.size(SET_LABEL_SIZE)
    prims.set_label.color(SET_LABEL_COLOR[1], SET_LABEL_COLOR[2], SET_LABEL_COLOR[3])
    prims.set_label.alpha(255)
    -- The indicator's backdrop is constant; the fill's colour is state
    -- (waiting/open) and lands from the tick.
    prims.indicator.bg.color(0, 0, 0)
    prims.indicator.bg.alpha(SC_BG_ALPHA)
    for _, group in ipairs(GROUPS) do
      for slot = 1, SLOT_COUNT do
        local pair = prims.groups[group.key][slot]
        pair.background.alpha(config.slot_alpha)
        pair.frame.alpha(255)
        dress_text(pair.name, false)
        dress_text(pair.cost, true)
        dress_text(pair.recast, true)
      end
    end
  end

  -- Repositions one slot's prims from its anchor's origin and scale. The
  -- icon carries its candidate's offset (the 32x32 sheets centre at +4/+4).
  -- `metrics` is optional and exists for layout(), which places up to forty
  -- slots in one pass: without it every slot builds the same table twice
  -- (once here, once inside slot_pos).
  local function place_slot(group, slot, metrics)
    if prims == nil then
      return
    end
    local entry = placed[group.anchor]
    if entry == nil or entry.pos == nil then
      return
    end
    local scale = entry.scale
    metrics = metrics or render.metrics()
    local x, y = render.slot_pos(group.bar, group.side, slot, metrics)
    local ax, ay = entry.pos.x, entry.pos.y
    local pair = prims.groups[group.key][slot]
    local size = metrics.slot * scale
    pair.background.pos(ax + x * scale, ay + y * scale)
    pair.background.size(size, size)
    pair.frame.pos(ax + x * scale, ay + y * scale)
    pair.frame.size(size, size)
    pair.sweep.pos(ax + x * scale, ay + y * scale)
    pair.sweep.size(size, size)
    pair.feedback.pos(ax + x * scale, ay + y * scale)
    pair.feedback.size(size, size)
    pair.chain.pos(ax + x * scale, ay + y * scale)
    pair.chain.size(size, size)
    local offset = contents[group.key][slot].offset or { x = 0, y = 0 }
    pair.icon.pos(ax + (x + offset.x) * scale, ay + (y + offset.y) * scale)
    pair.icon.size((metrics.slot - 2 * offset.x) * scale, (metrics.slot - 2 * offset.y) * scale)
    -- Slot-relative text offsets (no screen width here); the cost and
    -- recast texts are right-justified, so their drawn x hangs off the
    -- screen's right edge - subtracted AFTER scaling, or the screen term
    -- would scale with the anchor (the texts-library gotcha giltracker
    -- documents).
    local offsets = render.text_offsets(x, y)
    local font_size = (config.font_size or 7) * scale
    pair.name.pos(ax + offsets.name.x * scale, ay + offsets.name.y * scale)
    pair.name.size(font_size)
    pair.cost.pos(ax + offsets.cost.x * scale - screen_width, ay + offsets.cost.y * scale)
    pair.cost.size(font_size)
    pair.recast.pos(ax + offsets.recast.x * scale - screen_width, ay + offsets.recast.y * scale)
    pair.recast.size(font_size)
  end

  --[[ Lays out the slots on one anchor, or every group when `anchor` is nil.
       Scoped deliberately, and it is only one of three things that keep a
       layout-mode drag cheap: core's per-move apply() pushes a placement for
       EVERY anchor, then the preview flag, then show(), so scoping this alone
       still left the untouched anchors being re-shown and repainted. The
       other two are the no-op guards on set_pos/set_scale/set_preview/show
       and refresh()'s change-gate, which writes only where the answer
       changed. Measured on the full core sequence, one mouse move costs 433
       prim calls where it once cost 8530, and what remains is this: the
       moved anchor's own slots. ]]
  local function layout(anchor)
    if prims == nil then
      return
    end
    local metrics = render.metrics()
    for _, group in ipairs(GROUPS) do
      if anchor == nil or group.anchor == anchor then
        for slot = 1, SLOT_COUNT do
          place_slot(group, slot, metrics)
        end
      end
    end
    -- The indicator has no resting geometry - the tick draws it from the
    -- live plan - but whatever was pushed is now against the wrong origin.
    if anchor == nil or anchor == "skillchain_indicator" then
      reset_indicator_written()
    end
  end

  --[[ Applies the visibility plan for the current hold state: which bars
       are on screen, which slots inside them, and where the active-side
       panel sits. Core owns whether the component is visible at all; this
       owns what "visible" shows. Dynamic prims (cost, recast, sweep,
       feedback) are hidden here when their group leaves the screen and
       re-shown by the tick when it next has something to draw. ]]
  --[[ The change-gate: nothing is written to a prim that already holds it
       (partylist's written/push pattern - 363 prims at sixty frames a
       second would otherwise rewrite every value each tick). `written` is
       the last value pushed, per prim property, per slot; paint_slot and
       the refresh blanking wipe it so event-driven writes stay authoritative. ]]
  local function push(written, key, value, apply)
    if written[key] == value then
      return
    end
    written[key] = value
    apply(value)
  end

  local function want(written, prim, key, on)
    on = on and true or false
    if written[key] == on then
      return
    end
    written[key] = on
    if on then
      prim.show()
    else
      prim.hide()
    end
  end

  local function push_color(written, prim, key, r, g, b)
    local encoded = r * 65536 + g * 256 + b
    if written[key] == encoded then
      return
    end
    written[key] = encoded
    prim.color(r, g, b)
  end

  -- The sweep overlay's one gated write: `mode` is false (hidden), "x" (the
  -- red X) or a frame number - compared BEFORE any path string is built, so
  -- a slot whose frame index has not moved costs no allocation at all.
  local function set_sweep(written, prim, mode)
    if written["sweep.mode"] == mode then
      return
    end
    written["sweep.mode"] = mode
    if mode == false then
      prim.hide()
      return
    end
    if mode == "x" then
      prim.path(ctx.asset(ASSETS .. "own/red-x.png"))
    else
      prim.path(ctx.asset(ASSETS .. ("cooldown/frame_%02d.png"):format(mode)))
    end
    prim.alpha(OVERLAY_ALPHA)
    prim.show()
  end

  -- The chain overlay's gated write: `prop` is false (hidden) or the
  -- property whose icon to draw - compared before any path string is built.
  local function set_chain(written, prim, prop)
    if written["chain.prop"] == prop then
      return
    end
    written["chain.prop"] = prop
    if prop == false then
      prim.hide()
      return
    end
    prim.path(ctx.asset(ASSETS .. "icons/skillchain/" .. prop:lower() .. ".png"))
    prim.show()
  end

  -- The slot frame doubles as the chain border animation: `step` is false
  -- (the plain frame) or a frame_step index.
  local function set_frame(written, prim, step)
    if written["frame.step"] == step then
      return
    end
    written["frame.step"] = step
    if step == false then
      prim.path(ctx.asset(ASSETS .. "own/frame.png"))
      return
    end
    prim.path(ctx.asset(ASSETS .. ("own/frame_step%d.png"):format(step)))
  end

  local function refresh()
    if prims == nil then
      return
    end
    local hidden = not visible or machine == nil
    local plan = render.visible(active_state, { hidden = hidden })
    if (preview or editing()) and not hidden then
      -- Layout placement: with always_show_wxhb off the WXHB is invisible
      -- in play, so preview forces its halves up to give the anchors a
      -- visible footprint. Edit mode wants them for the same reason from
      -- the other end - every side must be reachable by mouse.
      plan.wxhb_left = true
      plan.wxhb_right = true
    end
    shown_groups = {}
    for _, group in ipairs(GROUPS) do
      local entry = anchor_at(group.anchor)
      local shown
      if group.key == "expanded" then
        shown = plan.expanded ~= nil
      else
        shown = plan[group.flag] == true
      end
      shown = shown and entry ~= nil and entry.pos ~= nil
      shown_groups[group.key] = shown
      for slot = 1, SLOT_COUNT do
        local content = contents[group.key][slot]
        local pair = prims.groups[group.key][slot]
        if not shown then
          content.flash = nil
          -- The chain state goes down with its prim: left standing, the
          -- icon predicate below would read it on the re-show repaint and
          -- leave the slot with neither icon nor chain for a frame.
          content.chain_prop = nil
        end
        --[[ The tick's own cache, deliberately shared rather than wiped:
             every write below goes through the gate, so what it holds after
             this pass is the truth about these prims, and a group that has
             not moved costs nothing on the next refresh - which matters
             because core runs one per mouse move of a layout-mode drag.
             Sharing is safe in the other direction too: flash() and
             paint_slot's chain hide write a prim without the gate but sync
             the key they wrote, and paint_slot's raw icon/name writes are
             preceded by a wipe of the whole cache. The non-visibility values
             (text, colour, alpha, path) stay true while a prim is hidden -
             hiding a prim does not make it forget them - so the tick has
             nothing to re-push when the group comes back either. ]]
        local written = content.written
        -- Empty slots come back for the binder whatever the config says:
        -- an invisible slot is still a drop target, which is the one thing
        -- edit mode cannot have.
        local slot_shown = shown and (content.record ~= nil or editing() or not config_hide("empty_slots"))
        want(written, pair.background, "background.visible", slot_shown)
        want(written, pair.frame, "frame.visible", slot_shown)
        -- Chain-aware on purpose: while a chain result covers the slot the
        -- tick keeps the action icon down, and refresh must agree with it
        -- or the two would fight over the prim between frames. Both write
        -- the same gate key for the same reason.
        want(
          written,
          pair.icon,
          "icon.visible",
          shown and content.record ~= nil and content.icon_found and content.chain_prop == nil
        )
        local label = content.label
        want(
          written,
          pair.name,
          "name.visible",
          shown and content.record ~= nil and label ~= nil and label ~= "" and not config_hide("action_name")
        )
        if not shown then
          want(written, pair.cost, "cost.visible", false)
          want(written, pair.recast, "recast.visible", false)
          set_sweep(written, pair.sweep, false)
          want(written, pair.feedback, "feedback.visible", false)
          set_chain(written, pair.chain, false)
        end
      end
    end
    local panel_shown = false
    if plan.panel ~= nil then
      local anchor = plan.panel.bar == "wxhb" and ("wxhb_" .. plan.panel.side) or "main"
      local entry = anchor_at(anchor)
      if entry ~= nil and entry.pos ~= nil then
        local rect = render.panel_pos(plan.panel.bar, plan.panel.side)
        prims.panel.pos(entry.pos.x + rect.x * entry.scale, entry.pos.y + rect.y * entry.scale)
        prims.panel.size(rect.width * entry.scale, rect.height * entry.scale)
        prims.panel.show()
        panel_shown = true
      end
    end
    if not panel_shown then
      prims.panel.hide()
    end
    --[[ The set label, on its own anchor: it says which set the XHB is on,
         which is true whether or not a side is held, so it is shown
         whenever the widget is - and it is not a panel, so nothing about
         the hold state moves it. ]]
    local set_at = anchor_at("set")
    if not hidden and set_at ~= nil and set_at.pos ~= nil then
      prims.set_label.pos(set_at.pos.x, set_at.pos.y)
      prims.set_label.size(math.floor(SET_LABEL_SIZE * set_at.scale + 0.5))
      prims.set_label.text(render.set_label(bindings.active_set()))
      prims.set_label.show()
    else
      prims.set_label.hide()
    end
    --[[ The sword, likewise its own: shown while the weapon is drawn,
         hidden while it is sheathed. Nothing reserves its space any more
         and nothing needs to - the label cannot move when the sword goes,
         because the two no longer share an origin.

         This is the component's OWN weapon state, not the client's status
         - the same state that picks which set rotation is live - so it
         lights on `draw` even with nothing targeted, which is what makes
         that press visible at all. ]]
    local weapon_at = anchor_at("weapon")
    if not hidden and weapon_at ~= nil and weapon_at.pos ~= nil and bindings.weapon_state() == "drawn" then
      local icon_size = render.set_icon_size() * weapon_at.scale
      prims.set_icon.pos(weapon_at.pos.x, weapon_at.pos.y)
      prims.set_icon.size(icon_size, icon_size)
      prims.set_icon.show()
    else
      prims.set_icon.hide()
    end
    if hidden then
      -- The indicator follows the widget down; while shown, the tick owns it.
      hide_indicator()
    end
  end

  -- The first existing candidate wins; without a file surface nothing can
  -- be verified, so nothing draws.
  local function pick_icon(record, meta, state)
    for _, candidate in ipairs(render.icon_candidates(record, meta, state)) do
      if file_exists(candidate.path) then
        return candidate
      end
    end
    return nil
  end

  -- Re-resolves one slot's content: the record through the live layer
  -- stack, its meta, its icon, its label.
  local function paint_slot(group, slot, state)
    local content = contents[group.key][slot]
    content.written = {}
    local record = nil
    local source = nil
    local set, side = group_target(group)
    if set ~= nil then
      record, source = bindings.resolve(set, side, slot)
    end
    if record ~= content.record then
      -- The slot's action changed: its recast denominator is the OLD
      -- action's and must be re-learned, or a fresh 30s recast draws
      -- nearly done under a stale 300s maximum. The icon memo goes the
      -- same way, and so does the chain result - the new action's is the
      -- next tick's to compute, and until it does the OLD action's
      -- property must not be left on screen. The prim comes down with the
      -- state, exactly as the not-shown branch of refresh() takes it down:
      -- state and prim are cleared together or one frame draws the dead
      -- one.
      render.clear_sweep(content.sweep_key)
      content.icon_memo = nil
      content.chain_prop = nil
      if prims ~= nil then
        prims.groups[group.key][slot].chain.hide()
        content.written["chain.prop"] = false
      end
    end
    local meta = meta_for(record)
    content.record = record
    content.meta = meta
    content.label = nil
    if prims == nil then
      return
    end
    local pair = prims.groups[group.key][slot]
    if record ~= nil then
      state = state or draw_state()
      --[[ The icon memo: the candidate walk stats the disk, so it re-runs
           only when its answer could change - a different record (the same
           identity rule the sweep uses), a state-swapped builtin icon
           (draw's attack/disengage/dismount), or an extraction still
           pending. A settled repaint stats nothing.

           The override is compared BESIDE the identity, not folded into
           it: `//hud crossbar icon` writes the field on the live entry
           table, so the record is the same table before and after and the
           identity alone left the old art on screen. Giving the verb a
           fresh table instead would clear the sweep and the chain result
           too, which an icon change has no business resetting. ]]
      local builtin = icon_for(record, state)
      local memo = content.icon_memo
      if
        memo == nil
        or memo.record ~= record
        or memo.icon ~= record.icon
        or memo.builtin ~= builtin
        or memo.awaiting
      then
        content.icon_found = false
        content.offset = nil
        content.awaiting_item_icon = false
        if
          icon_cache ~= nil
          and meta ~= nil
          and meta.item_id ~= nil
          and icon_cache.cached_icon(meta.item_id) == nil
        then
          -- Queued, never extracted here: one icon per frame, off the hot
          -- path. The slot draws its fallback meanwhile and is repainted
          -- when the extraction lands - unless the cache has given up on
          -- the item, which only a detach (reset) forgives.
          if not icon_cache.is_abandoned(meta.item_id) then
            icon_cache.request_icon(meta.item_id)
            content.awaiting_item_icon = true
          end
        end
        local candidate = pick_icon(record, meta, state)
        if candidate ~= nil then
          content.icon_found = true
          content.offset = candidate.offset
          pair.icon.path(ctx.asset(candidate.path))
        end
        content.icon_memo = {
          record = record,
          icon = record.icon,
          builtin = builtin,
          awaiting = content.awaiting_item_icon,
        }
      end
      --[[ The player's own label, then the game's own casing for what the
           record names, then the raw command form - cut to what a slot can
           draw. The record keeps its whole name; only this is shortened. ]]
      local label = render.slot_label(record.alias or record.display or record.action or record.type)
      --[[ The source tag, edit mode only: nothing for the job base (the
           common case), one mark for a subjob layer and another for a
           context, so "where is this coming from" is answered before any
           click - and the tags leave with edit mode, since the played bar
           has no room for them.

           Added AFTER the cut, so a name loses the same characters whether
           or not edit mode is open and the two readings of a slot agree. ]]
      local mark = editing() and binder.mark(source) or ""
      content.label = mark ~= "" and (mark .. " " .. label) or label
      pair.name.text(content.label)
    else
      content.icon_found = false
      content.offset = nil
      content.awaiting_item_icon = false
      content.icon_memo = nil
      pair.name.text("")
    end
    place_slot(group, slot)
  end

  local function repaint()
    if prims ~= nil then
      -- One draw-state read per repaint, not one per slot.
      local state = draw_state()
      for _, group in ipairs(GROUPS) do
        for slot = 1, SLOT_COUNT do
          paint_slot(group, slot, state)
        end
      end
    end
    --[[ A repaint is the only thing that can change WHICH ids need
         counting - a bind, a set switch, a context flip, a view change -
         but most repaints do not change them at all, and marking the counts
         dirty on every one would re-read the inventory (and, with gear
         bound, every wardrobe) on each hold state and set switch. So the
         set is recomputed here and compared: it is forty table lookups
         against up to ten client reads. Not a cache - it is rebuilt from
         the contents each time, so there is nothing to invalidate. ]]
    local signature = bound_item_signature()
    if signature ~= counted_signature then
      counted_signature = signature
      counts_dirty = true
    end
    refresh()
    -- Whatever moved the bar - a bind, a buff, a job change - moved what
    -- the binder's panels are describing too. Closed, this costs a nil
    -- check; nothing here reaches the tick path.
    if binder ~= nil then
      binder.refresh()
    end
  end

  -- An icon landing on disk can only change slots still waiting for item
  -- art, so only those repaint - a full repaint would re-stat every settled
  -- slot's candidates each time the queue lands one. (Chosen over teaching
  -- lib/icon_cache to report which id landed: no lib API change, and
  -- equipviewer stays untouched.)
  local function repaint_unresolved_items()
    if prims ~= nil then
      local state = draw_state()
      for _, group in ipairs(GROUPS) do
        for slot = 1, SLOT_COUNT do
          local content = contents[group.key][slot]
          if content.awaiting_item_icon then
            paint_slot(group, slot, state)
          end
        end
      end
    end
    refresh()
  end

  --[[ Execution ----------------------------------------------------------- ]]

  --[[ The line for a wait dropped by a re-attach or a detach. Those two
       used to go in silence, on the reasoning that a reset is not a
       cancellation worth reporting - but a warp evaporating is: the ring is
       on your finger, the GearSwap hold has just been let go, and nothing
       will ever happen. Every OTHER way a wait can end says something, so
       silence here read as "still waiting" for as long as the player cared
       to look, which is what hid an intermittent drop from view (Kevin,
       live client, 2026-08-22). ]]
  local function dropped_line()
    if pending_item == nil then
      return nil
    end
    return "crossbar: " .. pending_item.noun .. " dropped - " .. tostring(pending_item.name)
  end

  local function abort_pending(message)
    if pending_item == nil then
      return
    end
    if message ~= nil then
      say(message)
    end
    -- Every exit path re-enables every slot it held; harmless without
    -- GearSwap, and leaving one disabled would quietly break the player's
    -- gear swapping until they reloaded.
    for _, name in ipairs(pending_item.gs_slots or {}) do
      send_command("gs enable " .. name)
    end
    pending_item = nil
  end

  --[[ Giving up on whatever is in flight, naming it and (bar the bare
       suppression case) why. One builder for all five exits so the wording
       cannot drift apart, and so the noun stays the one that armed it. ]]
  local function abandon(reason)
    -- Guarded like abort_pending itself: this runs from the prerender
    -- poll, where a nil dereference would repeat sixty times a second
    -- until guard disabled the shared handler.
    if pending_item == nil then
      return
    end
    local message = "crossbar: " .. pending_item.noun .. " abandoned"
    if reason ~= nil then
      message = message .. " - " .. tostring(pending_item.name) .. " " .. reason
    end
    abort_pending(message)
  end

  --[[ Runs one of warp.lua's or enchanteditem.lua's plans - the same three
       shapes, so the scheduler below serves both and cannot drift between
       them. `noun` is what the chat calls the thing in progress ("warp",
       "enchanted item"); `broadcast`, when given, is `warp all`'s IPC send,
       and it fires where the LOCAL warp commits and nowhere else: with the
       command for a spell, a consumable or a ring already charged; with the
       deferred use for a ring being warmed up; at once when the ladder found
       nothing at all, the alts' own ladders being independent of ours. A
       warm-up that is later abandoned therefore sends nobody - the press
       alone was never a warp. ]]
  local function run_item_plan(plan, broadcast, noun)
    noun = noun or "warp"
    if pending_item ~= nil then
      -- One wait at a time, whatever armed it: a second gs disable or a
      -- crossed pair of equips mid-wait helps nobody. A pending warp
      -- therefore blocks an enchanted item and the reverse, which is the
      -- honest reading - there is one pair of hands.
      say("crossbar: " .. pending_item.noun .. " already in progress - " .. tostring(pending_item.name))
      return
    end
    for _, note in ipairs(plan.notes or {}) do
      say("crossbar: " .. note)
    end
    if plan.type == "spell" or plan.type == "use" then
      send_command(plan.command)
    elseif plan.type == "equip" then
      --[[ The target is resolved HERE, at the press, or the press does not
           happen. This command is not sent now - it goes when the
           enchantment comes up, as much as a minute later - so a token
           carried that far resolves THEN: `<t>` would land on whatever has
           been tabbed to since, and `<st>` would open a selection cursor
           long after the button was let go. Neither is the target the
           press meant.

           Refused before anything is held, so a press that will not happen
           leaves no GearSwap slot disabled behind it. A fixed target
           (`<me>` and friends) needs no pin and passes straight through,
           and a binding with no target word has nothing to resolve. ]]
      local deferred = plan.command
      if plan.target ~= nil then
        deferred = resend_command(plan.command, plan.target)
        if deferred == nil then
          local token = type(plan.target) == "string" and plan.target:lower() or plan.target
          if PINNED_TARGETS[token] then
            say("crossbar: " .. noun .. " pressed with nothing targeted - " .. tostring(plan.name))
          else
            say("crossbar: cannot pin <" .. tostring(token) .. "> at the press - bind <me> or <t>")
          end
          return
        end
      end
      -- Deferred: the broadcast travels with the pending machine and goes
      -- when the item does.
      --[[ xivcrossbar's enchanted-item pattern: a running GearSwap would
           otherwise swap the ring straight back off before it fires. The
           plan names which slots to hold - one when it chose the slot
           itself, every slot the piece fits when it found the piece
           already worn and cannot tell which one it is on. ]]
      local gs_slots = {}
      for _, slot_id in ipairs(plan.hold_slots or { plan.equip_slot }) do
        local name = GS_SLOT_NAMES[slot_id]
        if name ~= nil then
          gs_slots[#gs_slots + 1] = name
          send_command("gs disable " .. name)
        end
      end
      -- `equipped` says the piece is already on and only the enchantment is
      -- still warming: re-equipping it would risk restarting that warmup.
      -- The GearSwap hold above still applies - it can be swapped off
      -- mid-wait whoever put it on.
      if ctx.set_equip ~= nil and not plan.equipped then
        ctx.set_equip(plan.bag_slot, plan.equip_slot, plan.bag)
      end
      --[[ Said at the press, because the wait that follows can be half a
           minute and an unannounced one reads as nothing having happened
           (Kevin, live client, 2026-08-22). How LONG it will be is not
           knowable yet - the piece may only now be going on, and its
           warmup is read off the extdata the first poll fetches - so the
           length is spoken by tick_pending once it has a number.

           `noun` is used AS a noun, the way every other reader does
           (" already in progress", " abandoned", " dropped"): inflecting
           it produced "enchanted iteming with Vocation Ring", that path's
           own noun being two words.

           And the piece is only being equipped on the branch that equips
           it. `equipped` means it is already on with the enchantment still
           warming - `set_equip` is skipped just above - so promising to
           put it on would describe the one case that does not. ]]
      local doing = plan.equipped and " - waiting for it to charge." or " - equipping it first."
      say("crossbar: " .. noun .. " with " .. tostring(plan.name) .. doing)
      pending_item = {
        broadcast = broadcast,
        noun = noun,
        -- Whether the piece was already on when the wait was armed, which
        -- is what makes its activation_time trustworthy in the poll.
        equipped = plan.equipped == true,
        name = plan.name,
        -- Already resolved at the press, above.
        command = deferred,
        item_id = plan.id,
        bag = plan.bag,
        bag_slot = plan.bag_slot,
        -- Kept so the poll can re-issue the equip: `gs disable` does not
        -- cancel a GearSwap swap already in flight, and ours can lose.
        equip_slot = plan.equip_slot,
        gs_slots = gs_slots,
        give_up = plan.give_up,
        deadline = time_now() + (plan.give_up or DEFAULT_GIVE_UP_SECONDS) + PENDING_DEADLINE_MARGIN,
      }
      return
    end
    -- Nothing deferred: it either just went, or there was nothing here to
    -- send and the alts are asked anyway.
    if broadcast ~= nil then
      broadcast()
    end
  end

  -- One poll of the equip -> wait -> use machine, from the prerender tick:
  -- no coroutine sleeps, and every exit re-enables GearSwap. The poll runs
  -- once a second (MyHome's own cadence), never a whole-bag read per frame;
  -- the suppression and deadline aborts check every frame, ahead of the
  -- poll gate.
  local function tick_pending()
    if pending_item == nil then
      return
    end
    if ctx.suppressed ~= nil and ctx.suppressed() then
      abandon()
      return
    end
    if time_now() >= pending_item.deadline then
      abandon("took too long")
      return
    end
    local now = ctx.now ~= nil and ctx.now() or 0
    if pending_item.next_poll ~= nil and now < pending_item.next_poll then
      return
    end
    pending_item.next_poll = now + 1
    local bag = ctx.get_items ~= nil and ctx.get_items(pending_item.bag) or nil
    -- Matched by id AND slot: the remembered slot is not trusted to still
    -- hold the ring (a sort, a trade, GearSwap itself can move it).
    local item = nil
    for _, entry in ipairs(bag or {}) do
      if type(entry) == "table" and entry.slot == pending_item.bag_slot and entry.id == pending_item.item_id then
        item = entry
        break
      end
    end
    if item == nil then
      abandon("went missing")
      return
    end
    --[[ Is it actually ON? `gs disable` stops FUTURE GearSwap swaps and
         does not cancel one already in flight, so a set equipped in the
         same breath as the press lands on top of ours and the ring never
         reaches a finger - `gs equip sets.engaged; hud crossbar warp`
         reproduces it every time (Kevin, live client, 2026-08-22).

         Put it back, once a second until the deadline gives up on the
         press - long enough to outlast a GearSwap burst, and the honest
         answer for a slot that is being fought over.

         And read NOTHING off it until it is on. The extdata of a ring in
         the bag belongs to some earlier equip, so the use branch below
         would fire `/item` at a ring that is not worn - which the game
         refuses, and which `warp all` would broadcast on regardless.

         Only on the equip path: a piece that was already worn at the press
         is left alone, since re-equipping it would restart the warmup this
         is waiting out. ]]
    if not pending_item.equipped and item.status ~= EQUIPPED then
      if ctx.set_equip ~= nil and pending_item.equip_slot ~= nil then
        ctx.set_equip(pending_item.bag_slot, pending_item.equip_slot, pending_item.bag)
      end
      return
    end
    local ext = ctx.decode_extdata ~= nil and ctx.decode_extdata(item) or nil
    --[[ BOTH conditions, and neither alone is enough.

         The press-time flag, because only a wait armed over a piece that
         was ALREADY on may trust activation_time at all: on the equip path
         the timestamp belongs to some earlier equip, and `status` flips to
         worn the moment the CLIENT applies ours - which can be a poll ahead
         of the server's extdata refresh. Inferring worn-ness from the live
         item alone would start trusting that stale timestamp right there,
         moving the fired-too-early bug one poll later instead of killing
         it.

         And the live status, because the piece can come OFF mid-wait: a
         manual equip out of the game's own menu takes the ring off whatever
         GearSwap was told, and every other check here - bag, slot, id,
         extdata - is re-read for exactly that reason. ]]
    local worn = pending_item.equipped and item.status == EQUIPPED
    local step = ext ~= nil and enchanted.step(ext, time_now(), worn, pending_item.give_up) or nil
    if step == nil then
      -- A decode that is not enchanted-shaped: degrade, never arithmetic -
      -- this runs under the shared prerender guard.
      abandon("cannot be read")
      return
    end
    --[[ The countdown over the warm-up, spoken from the poll's own clock
         rather than a second one armed beside it: this is where the
         remaining time is actually known, and two clocks over one wait
         would disagree the moment the server's extdata lagged a poll.

         AFTER `step`, which is what vouches for the extdata being
         enchanted-shaped at all: reading a warmup off a decode that is not
         would throw, in a handler whose whole contract is to degrade.

         The whole number once, when it is first readable, then silence,
         then the last few seconds one at a time - travel.lua's shape, for
         travel.lua's reason. ]]
    if step == "wait" then
      local remaining = math.ceil(enchanted.warmup_remaining(ext, time_now()))
      --[[ A POSITIVE reading only. On the equip path the extdata's
           activation_time still belongs to some earlier equip until the
           server refreshes it - the same staleness `worn` exists to guard
           against above - so the first polls read zero remaining while the
           ring is genuinely warming. Announcing that said "ready in 0
           seconds" and then latched the counter at 1, so every later real
           reading was smaller-than-nothing and never spoke (Kevin, live
           client, 2026-08-22).

           A warm-up whose length the client never admits to therefore gets
           no countdown at all - the press-time line is what the player
           gets, and saying nothing beats promising a zero. ]]
      if remaining > 0 then
        --[[ A warm-up that RESTARTED, which the re-equip loop above causes
             every time it wins a slot back: the fresh activation_time
             pushes `remaining` up, and a counter left at the old low value
             would never see a smaller number again and go silent for the
             rest of the wait. Re-seed and let it count the new one down. ]]
        if pending_item.said ~= nil and remaining > pending_item.said then
          pending_item.said = remaining
        end
        if pending_item.said == nil then
          -- The opening line has already spoken this second, so the count
          -- starts below it - travel.arm seeds its own the same way, and
          -- `remaining + 1` made a short warm-up say the number twice.
          pending_item.said = remaining
          say(
            "crossbar: "
              .. tostring(pending_item.name)
              .. " ready in "
              .. remaining
              .. (remaining == 1 and " second" or " seconds")
              .. ". /heal to cancel."
          )
        end
        if remaining < pending_item.said then
          pending_item.said = remaining
          if remaining <= PENDING_COUNT_FROM then
            -- BARE, like the travel countdown's own counts: they read as a
            -- continuation of the line that named them, and five prefixed
            -- lines per wait is the chat spam this repo treats as a defect
            -- (say_travel's rule, a few hundred lines up).
            say(remaining .. "...")
          end
        end
      end
    end
    if step == "use" then
      local broadcast = pending_item.broadcast
      send_command(pending_item.command)
      abort_pending(nil)
      if broadcast ~= nil then
        broadcast()
      end
    elseif step == "abandon" then
      -- Not a timer: the REMAINING delay exceeds the bound, so waiting is
      -- pointless and the item is abandoned at once (MyHome's rule).
      abandon("needs more than " .. (pending_item.give_up or DEFAULT_GIVE_UP_SECONDS) .. " sec")
    end
  end

  local function flash(group_key, slot)
    if prims == nil then
      return
    end
    -- A hand-edited config can name a ninth slot key: the binding still
    -- fires, but there is no ninth prim to flash.
    local content = contents[group_key] ~= nil and contents[group_key][slot] or nil
    local slots = prims.groups[group_key]
    if content == nil or slots == nil or slots[slot] == nil then
      return
    end
    local feedback = type(config.feedback) == "table" and config.feedback or {}
    content.flash = feedback.alpha or 150
    local pair = slots[slot]
    pair.feedback.alpha(content.flash)
    pair.feedback.show()
    content.written["feedback.alpha"] = content.flash
    content.written["feedback.visible"] = true
  end

  -- Runs a resolved plan. Console strings - the `input` line for a slash
  -- command, the chained setkey chord for an opener - are composed in
  -- actions.lua, where they are pure; the ctx stays a plain send_command.
  local function execute(plan, hint)
    if plan == nil then
      if hint ~= nil then
        say("crossbar: " .. hint)
      end
      return
    end
    if plan.weapon_state ~= nil then
      -- Firing draw flips the component's weapon state, which flips the
      -- cycle rotation AND the draw slot's own icon - same as FFXIV.
      bindings.set_weapon_state(plan.weapon_state)
      repaint()
    end
    if plan.kind == "command" then
      --[[ The mount recast is ours to track: nothing in the client's recast
           tables names it (see roulette.lua), so the clock starts here,
           where the summon actually goes out - after the travel wait, not
           at the press that armed it.

           A blocked press never arrives: actions.lua refuses it at
           resolve, so there is no plan, no travel countdown and no command
           (Kevin, 2026-08-29). Nothing here needs to re-check the zone. ]]
      if plan.mount_summon and roulette ~= nil then
        roulette.summoned()
      end
      send_command(plan.command)
    elseif plan.kind == "message" then
      say("crossbar: " .. plan.message)
    elseif plan.kind == "warp" then
      run_item_plan(plan.plan)
    elseif plan.kind == "enchanted" then
      -- Deliberately outside the travel gate below: the warmup already is
      -- the wait, and an enchanted item is not a trip you press by mistake
      -- and want back (decided 2026-08-20).
      run_item_plan(plan.plan, nil, "enchanted item")
    end
  end

  --[[ The travel gate (CB10): mount, mount roulette and warp arm a
       countdown instead of firing, and the widget fires them when it runs
       out. Answers whether the press was held - false means fire it now,
       which is every other press, a dismount, an enchanted warp rung and a
       `delay` of zero.

       `fire` is how the press goes when the countdown ends, and the default
       closes over the plan computed AT THE PRESS. It used to re-resolve,
       on the reasoning that five seconds is long enough for the ladder's
       rung or the mounted state to have moved on and the later one should
       win - but the opening line NAMES the rung now, and a line promising
       one item while another goes is the worse trade (Kevin, 2026-08-22).
       The warp verb passes its own `fire` closing over the same walk, so
       every frontend obeys one rule. ]]
  --[[ The config modes: `//hud layout` and the binder are for arranging
       the HUD, not for playing in. Answers the open one by the name the
       player types, or nil. Layout mode is asked first because entering it
       closes the binder, so it is the one that is open when both look it. ]]
  local function config_mode()
    if layout_active() then
      return "//hud layout"
    end
    if editing() then
      return "edit mode"
    end
    return nil
  end

  local function delay_travel(record, plan, fire)
    local label = travel.label(record, plan)
    if label == nil then
      -- A trip that goes at once - a dismount, a warp on an enchanted rung,
      -- a `delay` of zero - is still a newer trip, so it ends whatever was
      -- counting down rather than firing alongside it. An ordinary press is
      -- not a trip at all and leaves the countdown alone: curing something
      -- while you wait to warp is not a change of mind.
      if travel.travels(record) then
        say_travel(travel.cancel())
      end
      return false
    end
    --[[ Refused where the press is made, rather than armed and called off
         a frame later by the gate on the tick: the outcome is the same and
         this is one line to read instead of two that contradict each other.
         The gate still has the other direction to catch - a mode opened
         while a trip is already counting down. ]]
    local mode = config_mode()
    if mode ~= nil then
      say("crossbar: " .. label .. " - not while " .. mode .. " is open")
      return true
    end
    local message = travel.arm({
      label = label,
      --[[ The PLAN, not the record: the countdown's opening line names the
           rung, so re-resolving when it ends could fire something the
           player was never told about. The warp verb closed over its
           ladder walk already; this is the same rule for every other
           frontend, the slot included, which used to re-pick and could
           therefore name one item and spend another. ]]
      fire = fire or function()
        execute(plan)
      end,
    })
    if message == nil then
      return false
    end
    say_travel(message)
    return true
  end

  -- The (set, side) a hold state fires from, plus the group that flashes.
  local function state_target(state)
    if state == "xhb_left" or state == "xhb_right" then
      return bindings.active_set(), state:sub(5), state
    end
    if state == "wxhb_left" or state == "wxhb_right" then
      local view = bindings.view_target(state)
      if type(view) == "table" then
        return view.set, view.side, state
      end
    elseif state == "expanded_lr" or state == "expanded_rl" then
      local view = bindings.view_target(state)
      if type(view) == "table" then
        return view.set, view.side, "expanded"
      end
    end
    return nil
  end

  local function fire_slot(slot)
    if scoped_main == nil or machine == nil then
      return
    end
    local set, side, group_key = state_target(machine.hold_state())
    if set == nil then
      return
    end
    local record = bindings.resolve(set, side, slot)
    if record == nil then
      -- An empty slot is silent: no command, no hint, no flash. It is still
      -- a newer slot press, though, so it drops whatever the cast retry was
      -- watching - nothing may outlive the moment it belonged to.
      retry.sent(nil)
      return
    end
    flash(group_key, slot)
    local plan, hint = actions.resolve(record, draw_state())
    -- A travel press counts down instead of going; everything else fires
    -- the moment it is pressed, exactly as it always did.
    if not delay_travel(record, plan) then
      execute(plan, hint)
    end
    --[[ Hand the press to the cast retry - after the send, never before it:
         this feature reacts, and a press the game accepts is never delayed
         by it. What is stored is the RE-SEND form, target already pinned;
         the send above went out with the token, untouched. The KIND goes
         with it, because a spell, an ability and a weaponskill are each
         refused in their own words and stopped by their own buffs; the
         address rides along so the retry can ask whether the slot still
         holds this very record. Any other press hands over nil, which
         drops whatever was being watched - a newer press means the player
         has moved on. ]]
    local sent = nil
    local kind = RETRY_KINDS[record.type]
    if kind ~= nil and plan ~= nil and plan.kind == "command" and retry.enabled() then
      local resend = resend_command(plan.command, record.target)
      if resend ~= nil then
        sent = { record = record, command = resend, kind = kind, set = set, side = side, slot = slot }
      end
    end
    retry.sent(sent)
  end

  --[[ Job scoping and events ---------------------------------------------- ]]

  --[[ The ONE writer of the model's buff state. While the binder previews a
       context, the simulated list owns it outright and live buff events are
       dropped rather than queued - the alternative, letting both write,
       reverts the previewed bar under a header still claiming the simulated
       view. The handover (preview(nil)) re-reads the client here, so
       nothing stale can survive the preview coming down. ]]
  local function apply_buffs()
    if previewing ~= nil then
      return bindings.update_buffs(previewing)
    end
    local player = get_player()
    if player == nil then
      return false
    end
    return bindings.update_buffs(player.buffs or {})
  end

  local function sync_buffs()
    if apply_buffs() then
      repaint()
    end
  end

  local function try_scope(force)
    local player = get_player()
    if player == nil or player.main_job == nil then
      return
    end
    if rescope_want ~= nil then
      -- The job change event outran get_player(): the client still reports
      -- the old job - or, on a sub-only change, the old SUB under the same
      -- main - and scoping it would stick. The want stays armed until both
      -- announced ids agree with what the client answers.
      if rescope_want.main ~= nil and player.main_job_id ~= nil and player.main_job_id ~= rescope_want.main then
        return
      end
      if rescope_want.sub ~= nil and player.sub_job_id ~= nil and player.sub_job_id ~= rescope_want.sub then
        return
      end
    end
    local wanted = rescope_want ~= nil
    rescope_want = nil
    if not force and not wanted and player.main_job == scoped_main and player.sub_job == scoped_sub then
      return
    end
    --[[ The FOURTH producer of an active-set change, after the two key
         intents and the two CLI verbs: `set_job` reloads `active_set` from
         the incoming job's own file, so a job change usually lands
         somewhere else entirely. An open binder window kept the address it
         was opened on, and the next bind would have written into that set
         of the NEW job's file. ]]
    local set_before = bindings.active_set()
    bindings.set_job(player.main_job, player.sub_job)
    scoped_main, scoped_sub = player.main_job, player.sub_job
    if editing() and set_before ~= bindings.active_set() then
      binder.deselect()
    end
    counts_dirty = true
    -- A job change auto-equips, and set_job has just dropped the class the
    -- outgoing job was holding.
    weapon_dirty = true
    -- Through the one writer: set_job clears the active contexts, and a
    -- job change landing mid-preview must re-assert the simulated list
    -- rather than the client's.
    apply_buffs()
    repaint()
  end

  --[[ The per-frame tick -------------------------------------------------- ]]

  --[[ The item ids some painted slot is bound to, so a consumable's count
       is read for the same reason a ninja tool's is. Two sets, because the
       two types are not carried in the same places: `wanted` is everything,
       `gear` the enchanteditem half, which resolves out of every equippable
       bag rather than the inventory alone.

       Walked on demand rather than cached: it is forty lookups, only an item
       event and a recount ask for it, and a cache would be one more thing
       to invalidate on every bind, set switch, context flip and job
       change. ]]
  local function bound_item_ids()
    --[[ Three sets, not two: `plain` and `gear` are tracked separately
         rather than "gear, and everything else", because ONE id can be
         bound both ways on the same bar. Deriving plain as "wanted minus
         gear" made such an id invisible to the temporary-bag read, so the
         plain slot showed a red X over a copy it could use. ]]
    local wanted, gear, plain = {}, {}, {}
    for _, group in ipairs(GROUPS) do
      for slot = 1, SLOT_COUNT do
        local content = contents[group.key][slot]
        local meta = content.meta
        if meta ~= nil and meta.item_id ~= nil then
          wanted[meta.item_id] = true
          if content.record ~= nil and content.record.type == "enchanteditem" then
            gear[meta.item_id] = true
          else
            plain[meta.item_id] = true
          end
        end
      end
    end
    return wanted, gear, plain
  end

  --[[ Those same ids as one comparable string, for the repaint check. The
       gear half is marked, because moving a slot from `item` to
       `enchanteditem` changes which bags get read even though the id has
       not moved. ]]
  function bound_item_signature()
    local _, gear, plain = bound_item_ids()
    local parts = {}
    --[[ Each id carries the KINDS bound to it, so unbinding one half of an
         id bound both ways still changes the signature. A single marker
         could not tell "gear only" from "gear and plain". ]]
    for id in pairs(gear) do
      parts[#parts + 1] = id .. "g"
    end
    for id in pairs(plain) do
      parts[#parts + 1] = id .. "i"
    end
    table.sort(parts)
    return table.concat(parts, ",")
  end

  --[[ Whether any painted slot draws a number the bag feeds - a bound
       item or piece of gear, or a spell/ability whose school spends a tool.
       The inventory packet names no id, so this is the only gate available
       to it, and it is deliberately coarser than the events': the JOB check
       the tool count itself applies is left out, because marking a recount
       on the wrong job costs one bag read and skipping one on the right job
       costs a wrong number on screen. ]]
  local function counts_from_inventory()
    for _, group in ipairs(GROUPS) do
      for slot = 1, SLOT_COUNT do
        local content = contents[group.key][slot]
        local meta, record = content.meta, content.record
        if meta ~= nil and meta.item_id ~= nil then
          return true
        end
        if meta ~= nil and meta.spell_id ~= nil and counters.tool_for_spell(meta.spell_id) ~= nil then
          return true
        end
        if record ~= nil and record.type == "ja" and counters.tool_for_ability(record.action) ~= nil then
          return true
        end
      end
    end
    return false
  end

  --[[ The class in the main hand, into the binding model. Only when
       something said it may have moved, and an unreadable client leaves the
       flag up rather than clearing the layer: an empty bag is the ordinary
       state for the first seconds of a login, and answering it would key
       the layer off a hand the client has not described yet. ]]
  local function refresh_weapon()
    if not weapon_dirty or weapon_layer == nil then
      return
    end
    local name, known = weapon_layer.resolve()
    if not known then
      return
    end
    weapon_dirty = false
    if name == bindings.weapon_type() then
      return
    end
    --[[ The class arriving can move the active set - the landing set_job
         made could not see this layer - which makes this the fifth producer
         of a set change, after the two key intents, the two CLI verbs and a
         job change. An open binder keeps the address it was opened on, so
         it is deselected exactly as try_scope does it. ]]
    local set_before = bindings.active_set()
    bindings.set_weapon_type(name)
    if editing() and set_before ~= bindings.active_set() then
      binder.deselect()
    end
    repaint()
  end

  local function recount_items()
    counts_dirty = false
    --[[ TWO tallies, because the two bindings do not count the same thing:
         `item_counts` is what the inventory holds (tools and consumables -
         the only bag `/item` can reach) and `gear_counts` what every
         reachable equippable bag holds. One shared number would have to be
         wrong for one of the slots whenever an id is bound both ways. ]]
    item_counts = {}
    gear_counts = {}
    --[[ Whether a temporary bag was actually found and read this pass. When
         it was not, a plain item's zero might simply be a copy we could not
         see - the bag is matched on a resource name nothing here has read
         (question M) - so the corner shows the number and withholds the red
         X. A missing warning beats a false one over a press that works. ]]
    temporary_seen = false
    local wanted, gear, plain = bound_item_ids()

    local function tally(into, bag, matches)
      for _, item in ipairs(bag or {}) do
        if type(item) == "table" and item.id ~= nil and item.id ~= 0 and matches(item.id) then
          into[item.id] = (into[item.id] or 0) + (item.count or 0)
        end
      end
    end

    --[[ The inventory answers tools and consumables: a potion in a
         wardrobe is not one the game will let you drink, so counting it
         would promise a press that cannot fire.

         The TEMPORARY bag answers alongside it, because an item held
         there is one `/item` can use and the inventory alone would draw a
         red X over a press that works. Resolved by NAME out of the
         resources, the way travel.lua resolves the resting status, so no
         bag id is being remembered here; without the resources it simply
         does not apply.

         NOT a claim about which items live there, and in particular NOT
         about Instant Warp - which is an ordinary inventory item (Kevin,
         2026-08-21), so the warp ladder's equippable-bags-only search
         reaches it and always has. This tally is for whatever the client
         does put in that bag. ]]
    local function usable_from_here(id)
      return counters.tracked_item(id) or wanted[id] == true
    end
    --[[ Reachability applies to bag 0 exactly as it does to every other
         bag - the press refuses an entry from a bag the client has
         disabled, whichever bag that is - so both tallies below share one
         gate rather than the gear half having its own.

         An ABSENT flag reads as reachable, and only an explicit `false`
         excludes. The client always sends one; a fixture that has never
         thought about the field should not have its counts silently
         emptied, and "I did not say" is not the same answer as "no". ]]
    local inventory = read_bag(0)
    local inventory_reachable = type(inventory) == "table" and inventory.enabled ~= false
    if inventory_reachable then
      tally(item_counts, inventory, usable_from_here)
    end
    -- Only a plain `item` binding can want the temporary bag: gear is never
    -- a temporary item, and tools are inventory-only by the rule below.
    local wants_temporary = next(plain) ~= nil
    -- Gear in the inventory counts too, off the same read - and under the
    -- same reachability rule the other bags get, which the press path
    -- applies to bag 0 as well.
    if next(gear) ~= nil and inventory_reachable then
      tally(gear_counts, inventory, function(id)
        return gear[id] == true
      end)
    end
    for bag_id, bag in pairs(equip_bags) do
      --[[ A CONTAINS match, not equality: the resource string is one this
           repo has never read, and "Temporary Items" is as plausible a
           spelling as "Temporary". A miss is NOT harmless - the slot reads
           0, crosses itself out and dims over a press that works, which is
           worse than the blank corner these slots had before counts existed
           at all. Question M is the read that settles the spelling. ]]
      local name = type(bag.name) == "string" and bag.name:lower() or ""
      if bag_id ~= 0 and name:find("temporary", 1, true) ~= nil then
        --[[ The NAME matched, which is the thing question M is about. Set
             here rather than after the read: an empty temporary bag is
             ordinary and its zero is trustworthy, while no bag of that name
             at ALL means the match itself failed and a plain item's zero
             cannot be trusted. ]]
        temporary_seen = true
      end
      if wants_temporary and bag_id ~= 0 and name:find("temporary", 1, true) ~= nil then
        --[[ Read only once the NAME has matched: hoisting this above the
             test would cost a client read for every bag on the character,
             on every recount. ]]
        local temporary = read_bag(bag_id)
        -- Reachability, the rule every other bag here gets: presumably
        -- always true for this one, but a presumption is not a reason to
        -- differ.
        if type(temporary) == "table" and temporary.enabled ~= false then
          --[[ Bound items only, and never a ninja tool: `item_counts` is the
             same table the tool counter reads, so folding a temporary-bag
             copy in would clear a red X that is telling the truth about
             what a ninjutsu can draw from. ]]
          tally(item_counts, temporary, function(id)
            return plain[id] == true and not counters.tracked_item(id)
          end)
        end
      end
    end

    --[[ Gear is different: enchanteditem searches every equippable bag, so
         a count that stopped at the inventory would cross out a slot whose
         press works perfectly. Bag 0 is not walked in this loop - it was
         tallied into `gear_counts` above, off the read the consumables
         already paid for, so nothing is counted twice. ]]
    if next(gear) ~= nil then
      for bag_id, bag in pairs(equip_bags) do
        -- Bag 0 was walked above; re-reading it here would cost a second
        -- client read for nothing.
        if bag_id ~= 0 and bag.equippable then
          local held = read_bag(bag_id)
          --[[ The runtime `enabled` flag, not the resource's `equippable`:
               enchanteditem refuses a copy it cannot reach, so counting one
               would promise the very press that cannot fire. ]]
          -- Same rule as bag 0 above: an explicit false excludes, an absent
          -- flag does not.
          if type(held) == "table" and held.enabled ~= false then
            tally(gear_counts, held, function(id)
              return gear[id] == true
            end)
          end
        end
      end
    end
  end

  local function recast_label(seconds)
    if seconds >= 3600 then
      return ("%dh"):format(math.floor(seconds / 3600))
    end
    if seconds >= 60 then
      return ("%dm"):format(math.floor(seconds / 60))
    end
    return ("%ds"):format(math.ceil(seconds))
  end

  -- Seconds remaining on a slot's recast. Spell recasts arrive in 60ths of
  -- a second, ability recasts in seconds - the client's own units.
  local function remaining_for(meta, spell_recasts, ability_recasts)
    if meta == nil or meta.recast_id == nil then
      return 0
    end
    if meta.kind == "spell" then
      return (spell_recasts[meta.recast_id] or 0) / 60
    end
    return ability_recasts[meta.recast_id] or 0
  end

  -- `mr` and a named mount share the recast and the zone rule: both are
  -- the same one command to the game.
  local function is_mount_record(record)
    return record ~= nil and (record.type == "mount" or record.type == "mr")
  end

  local function has_job(player, job)
    return player ~= nil and (player.main_job == job or player.sub_job == job)
  end

  --[[ The count drawn in a slot's cost corner, when the action carries
       one: SCH stratagem charges, NIN/COR tool counts, or how many of an
       item the slot names are carried. At most one of the three can apply -
       a ninjutsu is not a stratagem ability, and neither is an item. ]]
  local function counter_for(content, player, ability_recasts)
    local record = content.record
    local meta = content.meta
    if record.type == "ja" and counters.stratagem_ability(record.action) then
      local charges = counters.stratagems(player, ability_recasts[231] or 0)
      if charges ~= nil then
        return { text = tostring(charges.available), color = PLAIN_COUNT_COLOR }
      end
      return nil
    end
    --[[ A plain item binding counts what it names: no master substitutes
         and no job gate, both of which are tool facts rather than item
         ones. Enchanted gear counts the same way, and note what that means
         - these are COPIES, not charges, so a spent ring still reads "1".
         Its charges are the press's business, and the press says so. ]]
    if (record.type == "item" or record.type == "enchanteditem") and meta ~= nil and meta.item_id ~= nil then
      local counts = record.type == "enchanteditem" and gear_counts or item_counts
      local display = counters.item_display(meta.item_id, counts)
      --[[ The zero flag raises the red X and dims the slot, so it is only
           set where the zero is TRUSTWORTHY. A plain item counted without a
           temporary bag having been found might have a copy we never read;
           gear is never temporary, so its zero always stands. ]]
      local trustworthy = record.type == "enchanteditem" or temporary_seen
      return {
        text = display.text,
        color = PLAIN_COUNT_COLOR,
        zero = display.zero and trustworthy,
      }
    end
    -- The fork's own gates (its ui.lua:1057/1102): tool counts draw only
    -- while the owning school's job is somewhere on the pair - a shared
    -- Utsusemi slot viewed on WHM shows no count and no red X.
    local tool = nil
    if meta ~= nil and meta.spell_id ~= nil and has_job(player, "NIN") then
      tool = counters.tool_for_spell(meta.spell_id)
    end
    if tool == nil and record.type == "ja" and has_job(player, "COR") then
      tool = counters.tool_for_ability(record.action)
    end
    if tool ~= nil then
      local display = counters.tool_display(tool, item_counts, player and player.main_job or nil)
      return { text = display.text, color = TOOL_COLORS[display.color], zero = display.zero }
    end
    return nil
  end

  local function tick_slot(group, slot, player, vitals, spell_recasts, ability_recasts, chain_step)
    local content = contents[group.key][slot]
    local pair = prims.groups[group.key][slot]
    local written = content.written

    if content.flash ~= nil then
      content.flash = render.feedback_fade(content.flash)
      if content.flash == nil then
        want(written, pair.feedback, "feedback.visible", false)
      else
        push(written, "feedback.alpha", content.flash, pair.feedback.alpha)
      end
    end

    local record = content.record
    if record == nil then
      want(written, pair.cost, "cost.visible", false)
      want(written, pair.recast, "recast.visible", false)
      set_sweep(written, pair.sweep, false)
      content.chain_prop = nil
      set_chain(written, pair.chain, false)
      set_frame(written, pair.frame, false)
      push(written, "frame.alpha", 255, pair.frame.alpha)
      return
    end

    --[[ The chain result (CB6): while the window is open, a WS or JA slot
         whose action would continue the resonation swaps to the property's
         icon under the animated frame - WS and JA/pet each by the action's
         own id. Deviation from the reference fork, its own bug fixed: the
         fork queries JA slots by recast_id, but the chain table is keyed by
         ability id and the two are disjoint across all 75 entries (blood
         pacts share recast 173, Ready moves 102), so its JA slots can never
         light. A WS short of its 1000 TP draws the pair dimmed with the
         cost still up; a JA is never TP-dimmed (a knowingly dropped
         upstream quirk). ]]
    local meta = content.meta
    local chain_prop = nil
    if chain_step ~= nil and meta ~= nil then
      if record.type == "ws" and meta.ws_id ~= nil then
        chain_prop = skillchain.result(meta.ws_id, "weapon_skills")
      elseif (record.type == "ja" or record.type == "pet") and meta.ability_id ~= nil then
        chain_prop = skillchain.result(meta.ability_id, "job_abilities")
      end
    end
    content.chain_prop = chain_prop
    local chain_dim = chain_prop ~= nil and record.type == "ws" and vitals.tp ~= nil and vitals.tp < 1000

    local usable = true
    local crossed_out = false

    if chain_prop ~= nil and not chain_dim then
      -- The undimmed result owns the slot; counters and costs sit out for
      -- the window's few seconds, exactly as the reference blanks them.
      want(written, pair.cost, "cost.visible", false)
    else
      local counter = counter_for(content, player, ability_recasts)
      if counter ~= nil then
        -- Deliberately NOT gated on hide.cost: a count is not a cost. The
        -- option hides prices; how many tools you carry stays visible.
        push(written, "cost.text", counter.text, pair.cost.text)
        local color = counter.color or PLAIN_COUNT_COLOR
        push_color(written, pair.cost, "cost.color", color[1], color[2], color[3])
        want(written, pair.cost, "cost.visible", true)
        if counter.zero then
          crossed_out = true
          usable = false
        end
      else
        local cost = render.cost(content.meta, vitals)
        if cost ~= nil and not config_hide("cost") then
          push(written, "cost.text", cost.text, pair.cost.text)
          push_color(written, pair.cost, "cost.color", cost.color.r, cost.color.g, cost.color.b)
          want(written, pair.cost, "cost.visible", true)
        else
          want(written, pair.cost, "cost.visible", false)
        end
        if cost ~= nil and not cost.affordable then
          usable = false
        end
      end
    end

    local remaining = remaining_for(content.meta, spell_recasts, ability_recasts)
    --[[ A mount slot answers to neither a spell nor an ability recast, so
         its own two conditions land here - and they part company the moment
         you are actually mounted.

         The ZONE stops applying: you can be riding somewhere you could not
         have mounted, and the press is a dismount, which is never held up.

         The RECAST does not. It is the one thing still true while you ride
         - it says when you could mount again - so it keeps counting and
         keeps the slot dim (Kevin's call, 2026-08-29), even though the
         press would dismount you. Skipping it along with the zone made the
         sweep vanish the instant the mount landed. ]]
    if is_mount_record(content.record) and roulette ~= nil then
      if not roulette.mounted() and roulette.blocked() then
        usable = false
      end
      local cooling = roulette.cooldown()
      if cooling > remaining then
        remaining = cooling
      end
    end
    if remaining > 0 then
      usable = false
    end
    -- No sweep work at all while the animation is configured away - the
    -- maxima simply re-learn (starting full, the algorithm's own posture)
    -- if it is ever turned back on.
    local frame = nil
    if not config_hide("recast_animation") then
      frame = render.sweep(content.sweep_key, remaining)
    end

    if crossed_out then
      -- The sweep overlay doubles as the red X (upstream's prim reuse), and
      -- the recast text hides under it.
      set_sweep(written, pair.sweep, "x")
      want(written, pair.recast, "recast.visible", false)
    else
      if frame ~= nil then
        set_sweep(written, pair.sweep, frame)
      else
        set_sweep(written, pair.sweep, false)
      end
      if remaining > 0 and not config_hide("recast_text") then
        push(written, "recast.text", recast_label(remaining), pair.recast.text)
        want(written, pair.recast, "recast.visible", true)
      else
        want(written, pair.recast, "recast.visible", false)
      end
    end

    if chain_prop ~= nil then
      set_chain(written, pair.chain, chain_prop)
      push(written, "chain.alpha", chain_dim and SC_DIM_ICON_ALPHA or 255, pair.chain.alpha)
      set_frame(written, pair.frame, chain_step)
      push(written, "frame.alpha", chain_dim and SC_DIM_FRAME_ALPHA or 255, pair.frame.alpha)
    else
      set_chain(written, pair.chain, false)
      set_frame(written, pair.frame, false)
      push(written, "frame.alpha", 255, pair.frame.alpha)
    end
    -- The action icon hides under a chain result and comes back with it;
    -- refresh() applies the same predicate, so the two never fight.
    want(written, pair.icon, "icon.visible", chain_prop == nil and content.icon_found)

    -- Deviation from upstream, deliberate: dimming covers the ICON only.
    -- Upstream dims icon + cost + element together (toggle_slot); the
    -- element prim does not exist at CB5 (hide.element defaults on, no
    -- milestone home), and the cost text keeps its own semantic colours -
    -- the mp/tp/tool bands ARE its signal, and greying them would fight it.
    push(written, "icon.alpha", render.slot_alpha(usable), pair.icon.alpha)
  end

  --[[ Draws (or hides) the window indicator for this tick. Colour and
       opacity land only on a state flip (upstream's own gate); geometry
       lands whenever it moves, which while a window runs is every frame -
       that IS the animation, upstream's too. In preview the full open-state
       bar stands in, so layout mode has the anchor's real footprint to
       drag whatever the live chain state. ]]
  local function draw_indicator(delay, window)
    if prims == nil then
      return
    end
    local pair = prims.indicator
    local entry = anchor_at("skillchain_indicator")
    local cfg = type(config.skillchain) == "table" and config.skillchain or {}
    local plan = nil
    if entry ~= nil and entry.pos ~= nil and cfg.indicator ~= false then
      if preview then
        plan = skillchain.indicator_plan(0, 7)
      else
        plan = skillchain.indicator_plan(delay, window)
      end
    end
    local w = indicator_written
    if plan == nil then
      if w.visible ~= false then
        w.visible = false
        w.state = nil
        pair.bg.hide()
        pair.fill.hide()
      end
      return
    end
    if w.state ~= plan.state then
      w.state = plan.state
      local color = plan.state == "waiting" and SC_WAITING_COLOR or SC_OPEN_COLOR
      local tuned = plan.state == "waiting" and cfg.waiting_color or cfg.open_color
      if type(tuned) ~= "table" then
        tuned = color
      end
      pair.fill.color(tuned.r or color.r, tuned.g or color.g, tuned.b or color.b)
      pair.fill.alpha(type(cfg.opacity) == "number" and cfg.opacity or SC_OPACITY)
    end
    local scale = entry.scale
    local ax, ay = entry.pos.x, entry.pos.y
    local fill, bg = plan.fill, plan.bg
    push_rect(pair.fill, w.fill, ax + fill.x * scale, ay + fill.y * scale, fill.width * scale, fill.height * scale)
    push_rect(pair.bg, w.bg, ax + bg.x * scale, ay + bg.y * scale, bg.width * scale, bg.height * scale)
    if w.visible ~= true then
      w.visible = true
      pair.bg.show()
      pair.fill.show()
    end
  end

  -- How long a job-change gate keeps the per-frame get_player retry alive
  -- before standing down (parambar's login-retry precedent): a stale or
  -- dying announcement must not poll forever. The next job change event
  -- re-arms it.
  local RESCOPE_DEADLINE_SECONDS = 10

  --[[ Client reads ride the roster cadence. The sweep has 32 frames of
       granularity, so nothing visible is lost; the per-frame work between reads
       runs against the cached answers, and a bar with nothing on screen reads
       nothing at all.

       The cadence is **lib/player's read counter**, not a clock of our own. A
       second 200ms throttle in front of the service's would sit out of phase
       with it and leave these answers up to two intervals stale - the pattern
       the sibling components had removed. The recasts have no service behind
       them, but they want the same cadence, so they ride the counter too.

       An absent counter reads every frame, the same fallback the party list and
       the target bar take: costly, and unreachable in a client, but a wiring
       slip must degrade rather than freeze. ]]
  local reads = nil
  local last_read_generation = nil

  --[[ The binder (CB8) ----------------------------------------------------
       Built here, at the foot of the constructor, because every dep below
       closes over a local defined above it. The catalog instance is built
       with it; the binder rebuilds its listing on each open, so a level-up
       or a fresh spell is picked up without a reload. ]]

  local catalog = new_catalog({
    get_player = get_player,
    get_spells = ctx.get_spells,
    get_abilities = ctx.get_abilities,
    --[[ What the weapon in hand can perform: the client's weaponskill list
         is the JOB's, so without this the picker offers weaponskills for a
         weapon you are not holding (Kevin, live client, 2026-09-05). Read
         through the model rather than resolved again here, so the picker
         and the `wpn:` layer can never name different classes. ]]
    weapon_class = function()
      return bindings ~= nil and bindings.weapon_type() or nil
    end,
    get_items = ctx.get_items,
    owned_mounts = roulette ~= nil and roulette.owned or nil,
    -- The owned list is what /mount takes; this is how it is written.
    mount_display = roulette ~= nil and roulette.display or nil,
    resources = resources,
    -- The enchanted group walks the equippable bags, not inventory alone -
    -- the same table and the same decode the warp ladder searches with.
    bags = equip_bags,
    extdata_decode = ctx.decode_extdata,
  })

  binder = new_binder({
    new_image = ctx.new_image,
    new_text = ctx.new_text,
    asset = ctx.asset,
    screen = ctx.screen,
    text_style = function()
      return { font = config.font or "sans-serif", size = config.font_size or 7 }
    end,
    -- The live render instance, not the construction-time one: attach
    -- rebuilds it over the user's own config.
    render = function()
      return render
    end,
    -- Only the groups actually on screen, with the anchor placement they
    -- are drawn at, so the hit-test can never claim a bar that is not
    -- there. Expanded Hold cannot appear here: the widget ignores every
    -- activate intent while the binder is up - and the displayed state is
    -- `none`, which toggle_edit forces on the way in, so no side is drawn
    -- as active either.
    groups = function()
      local list = {}
      for _, group in ipairs(GROUPS) do
        local entry = placed[group.anchor]
        local set, side = group_target(group)
        if shown_groups[group.key] and entry ~= nil and entry.pos ~= nil and set ~= nil then
          list[#list + 1] = {
            key = group.key,
            bar = group.bar,
            -- Two sides, deliberately: the group's own half decides where
            -- the slots are drawn, the view's decides what they address.
            render_side = group.side,
            side = side,
            x = entry.pos.x,
            y = entry.pos.y,
            scale = entry.scale,
            set = set,
          }
        end
      end
      return list
    end,
    bindings = function()
      return bindings
    end,
    catalog = catalog,
    validate = actions.validate,
    icon = function(record)
      local candidate = record ~= nil and pick_icon(record, meta_for(record), draw_state()) or nil
      return candidate ~= nil and ctx.asset(candidate.path) or nil
    end,
    --[[ Tooltips carry only what the component already knows - no game
         description text, which we do not hold and would have to vendor.
         The recast reads ride the tick's 200ms cache when it has one: a
         hover is a mouse-move stream, and a client read per move would be
         hundreds a second. ]]
    describe = function(record)
      local meta = meta_for(record)
      local facts = {
        name = record.alias or record.display or record.action or record.type,
        type = record.type,
        target = record.target,
      }
      if meta ~= nil then
        facts.mp_cost = meta.mp_cost
        facts.tp_cost = meta.tp_cost
        -- The tick's 200ms cache when there is one - a hover is a mouse
        -- move stream - falling back to a live read rather than to an empty
        -- table, which would report every recast as ready until the first
        -- tick after attach landed.
        local spell_recasts = reads ~= nil and reads.spell_recasts
          or (ctx.get_spell_recasts ~= nil and ctx.get_spell_recasts())
          or {}
        local ability_recasts = reads ~= nil and reads.ability_recasts
          or (ctx.get_ability_recasts ~= nil and ctx.get_ability_recasts())
          or {}
        local remaining = remaining_for(meta, spell_recasts, ability_recasts)
        facts.recast = math.floor(remaining + 0.5)
        if meta.ws_id ~= nil then
          facts.property = skillchain.properties(meta.ws_id, "weapon_skills")
        elseif meta.ability_id ~= nil then
          facts.property = skillchain.properties(meta.ability_id, "job_abilities")
        end
      end
      return facts
    end,
    say = say,
    -- A binder write lands in the same store the CLI writes through, so the
    -- bar has to be repainted from it exactly as an authoring verb would.
    changed = repaint,
    --[[ Where the player dragged the binder window to. It is edit-mode
         furniture rather than anything the bar draws, so it lives in the
         component's own config beside the other preferences - not in a
         framework layout slot, which is for placed widget anchors. ]]
    window_pos = function()
      return config ~= nil and config.binder_pos or nil
    end,
    save_window_pos = function(x, y)
      if config == nil then
        return
      end
      config.binder_pos = { x = x, y = y }
      if save ~= nil then
        save()
      end
    end,
    --[[ Preview = a SIMULATED buff list through the live resolver, never a
         hand-toggled layer: picking dark-arts drops light-arts even if it
         is actually up, and picking an addendum lights its arts too, so the
         bar always shows the true stacked result. nil hands the live buff
         list back. ]]
    preview = function(buffs)
      previewing = buffs
      apply_buffs()
      repaint()
    end,
  })

  --[[ The cast retry's guards, answered for the record it is about to
       re-send. Every fact comes from state the widget already holds - the
       binding store, the memoised resource tables and the recast cache - plus
       the player, which is lib/player's cached read and so costs no client
       call either. The probe is only ever called when a re-send is otherwise
       due. The target is not among them: it was pinned at the press (see
       FIXED_TARGETS above), so there is nothing to re-check and no second
       lookup to pay for.

       The player is read HERE rather than taken off the recast snapshot: the
       whole point of a guard is that it sees the state as it is at the re-send,
       and MP spent or a silence landed since the snapshot is exactly what it
       is looking for. ]]
  local function retry_facts(entry)
    if bindings.resolve(entry.set, entry.side, entry.slot) ~= entry.record then
      -- Rebound, re-set, or a context has swapped the slot out from under
      -- the press. Identity, not contents: a different table at that
      -- address is a different binding, whatever it says.
      return { bound = false }
    end
    local meta = meta_for(entry.record)
    local snapshot = reads or {}
    local player = get_player()
    local cost = render.cost(meta, player ~= nil and player.vitals or {})
    return {
      bound = true,
      recast = remaining_for(meta, snapshot.spell_recasts or {}, snapshot.ability_recasts or {}),
      affordable = cost == nil or cost.affordable ~= false,
      buffs = player ~= nil and player.buffs or nil,
    }
  end

  local function tick()
    -- A fresh tick re-arms the one-per-tick target memo (see the engine's
    -- construction above).
    sc_target_read = false
    local clock = ctx.now ~= nil and ctx.now() or 0
    if rescope_want ~= nil and rescope_want.deadline ~= nil and clock >= rescope_want.deadline then
      -- The client never confirmed the announced ids: stop gating and
      -- scope whatever it answers now; the retry stands down with the want.
      rescope_want = nil
      try_scope(true)
    elseif scoped_main == nil or rescope_want ~= nil then
      try_scope(rescope_want ~= nil)
    end
    --[[ The config-mode gate runs BEFORE the poll, or the poll fires the
         very trip the gate is there to call off: `tick_pending` has no
         mode check of its own, so a ring whose enchantment came up while
         `//hud layout` was open used to warp anyway. ]]
    if (travel.armed() or pending_item ~= nil) and config_mode() ~= nil then
      end_trip("cancelled")
    end
    -- The warp poll keeps its own 1s cadence and must run even while the
    -- bar is hidden - a warp mid-wait does not stop for a cutscene's hide.
    tick_pending()
    --[[ The travel countdown, ahead of the visibility gates for the same
         reason: it is a press already made, and it is answered whether or
         not the bar is on screen. With nothing counting down this is one
         nil test and no client read at all.

         A late trip goes only where a fresh press would, the cast retry's
         own rule: `//hud layout` and the binder are configuration, not
         play, so either of them calls a countdown off. The armed test comes
         FIRST because the two questions behind it are ctx calls, and a
         player with nothing counting down must not pay for them sixty
         times a second. One gate covers both directions - a mode opened
         mid-count, and a press made while one was already open - so
         neither entry point needs a cancel of its own. Chat is deliberately
         NOT here, unlike the retry: typing a line is not a config mode, and
         answering a tell while you wait to warp should not strand you. ]]
    local travelling, count = travel.step()
    if count ~= nil then
      say(count)
    end
    if travelling ~= nil then
      travelling.fire()
    end
    if icon_cache ~= nil and icon_cache.drain_queue() then
      -- An icon landed on disk; only unresolved item slots can care.
      repaint_unresolved_items()
    end
    if prims == nil or scoped_main == nil then
      return
    end
    --[[ Hidden or suppressed: zero client reads. The test is the WIDGET's own
         switch, deliberately - it was "is any group on screen" until
         2026-08-31, which a per-anchor hide of `main` also satisfies, and
         everything below here stopped dead on `//hud hide crossbar main`:
         the skillchain indicator froze on its own anchor (this tick is the
         only thing that draws it) and a pending re-send was neither stepped
         nor dropped. Hiding one anchor is not hiding the bar. A whole-widget
         hide still clears both - hide() drops the retry, refresh() takes the
         indicator down - which is what this gate was written for. ]]
    if not visible then
      return
    end
    -- The skillchain surface: the indicator from the window state, and the
    -- per-slot results only while the window is actually open. The border
    -- animation's clock advances once per tick, shared by every slot.
    -- Decision: the indicator rides the bar's own tick and gates rather
    -- than a path of its own - a hidden or suppressed bar is a hidden
    -- indicator, which is the visibility contract, at the cost of the
    -- indicator sitting out until a job is scoped.
    local sc_delay, sc_window = skillchain.window()
    draw_indicator(sc_delay, sc_window)
    local chain_step = nil
    if sc_window > 0 and sc_delay <= 0 and not config_hide("skillchain_icon") then
      chain_step = render.chain_tick()
    end
    if counts_dirty then
      recount_items()
    end
    local generation = ctx.generation and ctx.generation() or nil
    if reads == nil or generation == nil or generation ~= last_read_generation then
      last_read_generation = generation
      refresh_weapon()
      reads = {
        player = get_player(),
        spell_recasts = ctx.get_spell_recasts ~= nil and ctx.get_spell_recasts() or {},
        ability_recasts = ctx.get_ability_recasts ~= nil and ctx.get_ability_recasts() or {},
      }
      -- The binder's details column reads its recast from these, so it is
      -- rebuilt on the same cadence rather than per frame - and only in
      -- edit mode, the only place anything describes an action.
      if editing() then
        binder.refresh_details()
      end
    end
    --[[ The cast retry, over the reads above. The pending test comes FIRST
         and is a plain nil check on state this component already holds: the
         guards below are client calls (chat_open() is get_info() behind a
         wrapper), and a player who never turns the feature on must not pay
         for one of those sixty times a second.

         A re-send is the same slot press arriving late, so it fires only
         where a slot press would - never into an open chat line, never
         under the binder, never while layout mode owns the screen. (The
         input machine's other two, suppressed and disabled, arrive here as
         hide(), which clears outright.) A cast held when one of the three
         opens is dropped, not queued behind it. ]]
    if retry.pending() ~= nil then
      if chat_open() or editing() or layout_active() then
        retry.clear()
      else
        local resend = retry.step(retry_facts)
        if resend ~= nil then
          send_command(resend.command)
        end
      end
    end
    local player = reads.player
    local vitals = player and player.vitals or {}
    for _, group in ipairs(GROUPS) do
      if shown_groups[group.key] then
        for slot = 1, SLOT_COUNT do
          tick_slot(group, slot, player, vitals, reads.spell_recasts, reads.ability_recasts, chain_step)
        end
      end
    end
  end

  --[[ Edit mode ------------------------------------------------------------

       One entry point for all three frontends: the `edit` verb, the Select
       chord, and any press of that shortcut key while the binder is up.
       Layout mode owns the mouse outright while it is on, so the two can
       never contend - core refuses nothing here, the component does. ]]

  --[[ A transition that ends whatever trip was in flight - a countdown
       AND a warm-up. Resting learned the second half first and the others
       were left behind, so dying or zoning mid-warm-up kept a GearSwap
       slot disabled for the best part of a minute and then had `/item`
       fired on the far side, with `warp all` broadcasting on it. One
       helper, so the endings cannot drift apart again. ]]
  function end_trip(reason)
    say_travel(travel.cancel())
    if pending_item ~= nil then
      abort_pending("crossbar: " .. pending_item.noun .. " " .. reason .. " - " .. tostring(pending_item.name))
    end
  end

  --[[ The set moved under the bar. Edit mode lets the switch through, and
       the binder's window remembers the address it was opened on - so the
       window is put away rather than left pointing at a set that is no
       longer on screen. Edit mode itself stays on: changing set is how you
       bind across several of them without leaving. ]]
  local function set_changed(before)
    -- Only a set that actually MOVED puts the window away: `jump` answers
    -- the set it was given whether or not that was already the one on
    -- screen, and `cycle` answers where it started when nothing else
    -- qualifies, so both can report a change that did not happen.
    if editing() and before ~= bindings.active_set() then
      binder.deselect()
    end
    repaint()
  end

  local function close_edit()
    if editing() then
      binder.close()
      -- The activate intents that arrived while the binder was up went
      -- unheard, so the side memory is stale: read the machine, exactly as
      -- show() does when the component comes back from hidden.
      active_state = machine and machine.hold_state() or "none"
      repaint()
    end
  end

  local function toggle_edit()
    if editing() then
      close_edit()
      return "crossbar: edit mode off"
    end
    if ctx.layout_active ~= nil and ctx.layout_active() then
      return "crossbar: //hud layout owns the mouse - leave layout mode first"
    end
    if not visible then
      return "crossbar: the crossbar is hidden - //hud show crossbar first"
    end
    if scoped_main == nil then
      -- Nothing is bindable before a job is named: the binder would open on
      -- a bar with no set behind it, which is worse than a refusal.
      return "crossbar: no job scoped yet - log in first"
    end
    binder.open()
    --[[ No side is active in edit mode. The mode is entered by HOLDING a
         side and pressing Select, so without this the side that opened it
         stayed lit for as long as the mode was on - long after the key was
         released, since activate intents go unheard from here (Kevin, live
         client, 2026-08-22). Sides are inert in edit mode, so a lit one
         says something untrue. close_edit() reads the machine on the way
         out, which is what puts the display back in step with the keys
         really held. ]]
    active_state = "none"
    -- The bar repaints into its edit-mode dress: every side drawn, and each
    -- slot wearing the tag of the layer its winner came from.
    repaint()
    return "crossbar: edit mode on - click a slot, then a layer, an action, and a target"
  end

  --[[ Commands ------------------------------------------------------------ ]]

  local function status_lines()
    if scoped_main == nil then
      return "crossbar: no job loaded yet"
    end
    local head = "crossbar: " .. scoped_main
    if scoped_sub ~= nil then
      head = head .. "/" .. scoped_sub
    end
    local lines = { head .. " - set " .. bindings.active_set() .. " (" .. bindings.weapon_state() .. ")" }
    -- The class the weapon layer is keyed to, which nothing else reports:
    -- `list` prints a wpn row only where one is already bound.
    local class = bindings.weapon_type()
    if class ~= nil then
      lines[1] = lines[1] .. " - " .. class
    end
    -- The CLI owns the view map: it is the spelling the user types, and a
    -- second copy here could disagree with the verb that sets them.
    for _, view in ipairs(authoring.views) do
      local target = bindings.view_target(view.key)
      if type(target) == "table" then
        lines[#lines + 1] = "  " .. view.cli .. " -> " .. tostring(target.set) .. (target.side == "left" and "L" or "R")
      end
    end
    return lines
  end

  local function opener_lines()
    local names = {}
    for name in pairs(openers) do
      names[#names + 1] = name
    end
    table.sort(names)
    return { "crossbar open targets:", "  " .. table.concat(names, ", ") }
  end

  -- The one dispatcher behind both frontends: `//hud crossbar ...` through
  -- core's passthrough, and the shortcut keys' verbs. Answers a string or a
  -- list of lines (or nil when execution already happened).
  local function dispatch_command(args)
    args = args or {}
    local verb = type(args[1]) == "string" and args[1]:lower() or nil
    if verb == nil or verb == "" then
      return status_lines()
    end
    if verb == "set" then
      -- The CLI absorbs the model's asymmetry: `jump` takes numbers only
      -- (the input machine hands it one), while `bind` also takes numeric
      -- strings because its set argument carries the layer prefixes. A
      -- command line is all strings, so the conversion belongs here.
      local set = tonumber(args[2])
      if set == nil then
        return "crossbar: set takes a number - //hud crossbar set <1-8>"
      end
      local before = bindings.active_set()
      local landed, err = bindings.jump(set)
      if landed == nil then
        return "crossbar: " .. err
      end
      -- Through set_changed, not a bare repaint: the CLI is live in edit
      -- mode, so a set moved from here has to put an open binder window
      -- away exactly as the switch key does. It did not, and the window
      -- went on naming the address it was opened on.
      set_changed(before)
      return "crossbar: set " .. landed
    end
    if verb == "cycle" and args[2] == nil then
      -- The bare/args overload: bare advances the rotation, with args it
      -- edits rotation membership (the authoring half, below) - never a
      -- silent advance either way.
      local before = bindings.active_set()
      local landed, err = bindings.cycle()
      if landed == nil then
        return "crossbar: " .. err
      end
      set_changed(before)
      return "crossbar: set " .. landed
    end
    if verb == "open" and args[2] == nil then
      return opener_lines()
    end
    if verb == "edit" then
      return toggle_edit()
    end
    if verb == "warp" then
      --[[ The broadcast rides the local warp rather than the press: a
           countdown the player calls off, or a ring warm-up that is later
           abandoned, must not leave the alts already sent home. It is
           handed to run_item_plan, which knows where the warp commits. ]]
      local broadcast = nil
      if type(args[2]) == "string" and args[2]:lower() == "all" and ctx.send_ipc ~= nil then
        broadcast = function()
          ctx.send_ipc(IPC_WARP_MESSAGE)
        end
      end
      local record = { type = "warp" }
      --[[ Walked ONCE, and the rung it picks is the rung that fires (Kevin,
           2026-08-22). It used to be walked again when the countdown ended,
           on the reasoning that the best rung five seconds ago may not be
           the best one now - but the opening line names the rung, and a
           line that named one item while another went is worse than a
           slightly stale choice. The stale case is also narrow: it takes
           the named item leaving your bags during the countdown, and the
           press then fails where it would have succeeded, which is at
           least the outcome you were told about. ]]
      local ladder = warp.plan()
      if
        not delay_travel(record, { kind = "warp", plan = ladder }, function()
          run_item_plan(ladder, broadcast)
        end)
      then
        run_item_plan(ladder, broadcast)
      end
      return nil
    end
    if authoring.handles(verb) then
      local reply, save_config, needs_repaint = authoring.command(args)
      -- Every accepted change persists immediately: a binding write went
      -- through the store on its way here, and a config write needs core's
      -- own save. Both then re-render, since a repointed view or a flipped
      -- shared flag changes what the bar is showing.
      if save_config and save ~= nil then
        save()
      end
      -- A config write can have been `retry off`, and switching the feature
      -- off must drop a cast pending at that moment rather than let a last
      -- one through. Generic on purpose: no verb is named here.
      retry.sync()
      if needs_repaint then
        repaint()
      end
      return reply
    end
    -- Arguments fold case like verbs do (the framework convention):
    -- `open EQUIPMENT` is the same opener.
    local argument = args[2]
    if type(argument) == "string" then
      argument = argument:lower()
    end
    local plan, hint = actions.resolve_builtin(verb, argument, draw_state())
    if plan == nil then
      if hint ~= nil and not hint:find("unknown built%-in") then
        return "crossbar: " .. hint
      end
      -- `help` first: the CLI's own unknown-verb reply is unreachable (the
      -- widget routes on handles() before it), so this is the only hint an
      -- unknown verb ever sees, and the full list is one word away.
      return "crossbar: unknown command '" .. verb .. "' - try help, set, cycle, open, draw, mr or warp"
    end
    -- The same record resolve_builtin just built, so the typed command and
    -- a bound slot reach the travel gate identically - one path by design.
    if not delay_travel({ type = verb, action = argument }, plan) then
      execute(plan)
    end
    return nil
  end

  -- A shortcut key's verb is a `//hud crossbar` line without the prefix.
  local function run_shortcut(verb)
    if type(verb) ~= "string" then
      return
    end
    local words = {}
    for word in verb:gmatch("%S+") do
      words[#words + 1] = word
    end
    local reply = dispatch_command(words)
    if reply ~= nil then
      say(reply)
    end
  end

  --[[ The widget contract ------------------------------------------------- ]]

  function self.attach(new_config, persist, store)
    -- Re-read on every attach (targetbar's precedent): the right-justified
    -- text x subtracts the width, and a resolution change must correct
    -- here. The height's only consumer is the construction-time defaults.
    screen_width = ctx.screen()
    config = type(new_config) == "table" and new_config or self.defaults
    save = persist
    render = new_render({ config = config, icon_for = icon_for })
    bindings = build_bindings(store)
    --[[ A countdown belongs to the configuration that armed it. NOT the
         detach clear by another name: core re-attaches WITHOUT detaching
         (`//hud reset crossbar`, and the reload `//hud copy` does when it
         writes the character being played), so a trip armed beforehand
         would otherwise fire afterwards carrying a record from the
         configuration just thrown away - and unlike the cast retry there is
         no `bound` guard here to notice that it had. Silent: a reset is not
         a cancellation the player needs told about. ]]
    travel.clear()
    --[[ And the same argument for a wait already in flight, which the
         countdown's own reasoning always covered and this did not do: its
         command comes from the configuration being replaced, and it is
         holding a GearSwap slot disabled meanwhile. abort_pending releases
         every slot it held - and unlike the countdown above it SAYS so,
         because a warp that evaporates in silence is indistinguishable
         from one still counting down. ]]
    abort_pending(dropped_line())
    scoped_main, scoped_sub, rescope_want = nil, nil, nil
    counts_dirty = true
    reset_contents()
    -- A hand-broken input block degrades to the shipped defaults rather
    -- than crashing attach: one bad config file at login would otherwise
    -- leave every component after this one unattached.
    machine = new_input({
      keys = type(config.input) == "table" and config.input or self.defaults.input,
      chat_open = ctx.chat_open,
      suppressed = ctx.suppressed,
      layout_mode = ctx.layout_active,
      --[[ The sixth guard, live from CB8: while the binder is up the
           crossbar's own keys fire nothing and keep tracking. TWO live
           inputs now, not one - the shortcut key that exits, and the set
           SWITCH, because which set is on screen is what edit mode is for
           (2026-08-22). Slot keys stay the game's there unless the switch
           is held, which is the jump chord and is blocked. ]]
      edit_mode = editing,
      disabled = function()
        --[[ Disabled means the USER-hidden case only, and it outranks
             suppression: a crossbar the player turned off keeps its keys
             with the game through cutscenes and zoning. Core's user flag
             is the one truthful source - suppression and a user hide both
             reach this widget as hide() (and a hide arriving DURING a
             cutscene is never signalled at all, the widget already being
             hidden), so show()/hide() cannot rank the two. ]]
        if ctx.component_visible ~= nil then
          return ctx.component_visible() ~= true
        end
        -- Degraded ctx (the wire missing): infer from show()/hide() and
        -- rank suppression above the ambiguous hidden state.
        return not visible and not (ctx.suppressed ~= nil and ctx.suppressed() == true)
      end,
    })
    --[[ A hand-edited key map can give one DIK two jobs; input.lua keeps the
         first claim and drops the rest, and this is the only place the player
         would ever hear about it - said once per config read, not once per
         press, and one line per key so a map broken twice reads as two
         problems. ]]
    if ctx.say ~= nil then
      for _, clash in ipairs(machine.conflicts()) do
        ctx.say(
          ("crossbar: DIK %d is bound to more than one thing - %s wins, and %s is ignored"):format(
            clash.dik,
            clash.kept,
            table.concat(clash.dropped, " and ")
          )
        )
      end
    end
    active_state = "none"
    reads, last_read_generation = nil, nil
    dress()
    layout()
    -- The login may already be far enough along to name the job; otherwise
    -- the tick keeps looking (core scopes on the character name alone -
    -- anything else a component needs it waits for itself).
    try_scope()
    repaint()
  end

  function self.detach()
    -- The binder describes a character's bindings; a logout invalidates
    -- every one of them, so it goes down with the scope.
    close_edit()
    -- gs enable on every exit path: a logout mid-warp must not leave the
    -- slot disabled. Named, for the reason above - a logout is a place a
    -- warp really can evaporate from.
    abort_pending(dropped_line())
    -- A logout (or a reload) invalidates a held cast with everything else.
    -- Belt and braces: the binding store deep-copies on load, so the record
    -- a re-attach resolves can never be the table the press pinned, and the
    -- `bound` guard would drop it anyway. Kept because this is where the
    -- rest of the per-character state is let go, not because it is the only
    -- thing standing there.
    retry.clear()
    -- And a countdown, dropped without a word: a logout leaves nobody
    -- reading the chat it would have been cancelled in.
    travel.clear()
    -- Core's save belongs to the attached config; holding it past a detach
    -- would write a config this widget no longer has.
    save = nil
    -- The machine is rebuilt on attach (the plan's detach handshake): a key
    -- released while detached would otherwise strand held/down/latch state
    -- and make the next press read as an auto-repeat.
    machine = nil
    active_state = "none"
    scoped_main, scoped_sub, rescope_want = nil, nil, nil
    reads, last_read_generation = nil, nil
    bindings = build_bindings(nil)
    reset_contents()
    -- Chain state is per character and per zone at best; a detach (logout,
    -- reload) invalidates all of it, exactly like the reference's logout.
    skillchain.reset()
    if icon_cache ~= nil then
      icon_cache.reset()
    end
    refresh()
  end

  function self.on_keyboard(key, down, flags, blocked)
    if not machine then
      return false
    end
    local intents, block = machine.on_key(key, down, flags, blocked)
    for _, intent in ipairs(intents) do
      if intent.type == "activate" then
        --[[ Activations are silent: the panel shows which side is active.
             OPEN QUESTION (chat-focus display): `activate` passes
             the chat guard by design, so the display follows the physical
             keys even while the chat box has focus. A "freeze the display
             while chat has focus" option would gate THIS branch on
             ctx.chat_open() - nothing else - and is deliberately not
             decided here.

             Edit mode is the one state that ignores them outright: the
             machine keeps tracking every key (CB0's contract is untouched),
             but the widget stops reacting, so no side lights and Expanded
             never replaces the XHB. The slots CAN move under an open binder
             window, though - the set switch is live in edit mode - which is
             why a set change puts that window away (see set_changed).
             close_edit() reads hold_state() on the way out, the same
             handshake show() uses. ]]
        if not editing() then
          local was_expanded = active_state == "expanded_lr" or active_state == "expanded_rl"
          active_state = intent.state
          local is_expanded = active_state == "expanded_lr" or active_state == "expanded_rl"
          if was_expanded ~= is_expanded or is_expanded then
            -- Entering Expanded (or crossing between its two views) is the
            -- one activation that changes CONTENT, not just visibility.
            repaint()
          else
            refresh()
          end
        end
      elseif intent.type == "fire" then
        fire_slot(intent.slot)
      elseif intent.type == "jump" then
        local before = bindings.active_set()
        if bindings.jump(intent.set) ~= nil then
          set_changed(before)
        end
      elseif intent.type == "cycle" then
        local before = bindings.active_set()
        if bindings.cycle() ~= nil then
          set_changed(before)
        end
      elseif intent.type == "draw" then
        execute(actions.resolve({ type = "draw" }, draw_state()))
      elseif intent.type == "shortcut" then
        run_shortcut(intent.verb)
      end
    end
    return block
  end

  function self.update(event, a, ...)
    if event == nil then
      tick()
      return
    end
    if event == "lose focus" then
      if machine ~= nil then
        machine.focus_lost()
        active_state = "none"
        refresh()
      end
    elseif event == "job change" then
      -- The event carries (main_id, main_lv, sub_id, sub_lv); both ids gate
      -- the reload - get_player() can still answer the OLD job (or the old
      -- sub) here, and scoping it would stick.
      local sub_id = select(2, ...)
      -- A cast held across a job change belongs to the job that pressed it,
      -- and so does a trip counting down.
      retry.clear()
      -- The whole trip, not just its countdown: CLAUDE.md lists a job
      -- change among the transitions that end one, and a ring warming for
      -- the job you just left is not a warp you still want.
      end_trip("cancelled")
      rescope_want = nil
      if type(a) == "number" then
        rescope_want = {
          main = a,
          sub = type(sub_id) == "number" and sub_id or nil,
          deadline = (ctx.now ~= nil and ctx.now() or 0) + RESCOPE_DEADLINE_SECONDS,
        }
      end
      try_scope(true)
    elseif event == "gain buff" or event == "lose buff" then
      sync_buffs()
      if a == MOUNTED_BUFF then
        -- Not a context, but the draw slot's icon follows it.
        repaint()
      end
    elseif event == "status" then
      if DEAD_STATUSES[a] then
        retry.clear()
        -- Whatever you were travelling towards, you are not going now.
        end_trip("cancelled")
      end
      -- Resting calls a countdown off, which is the way out the opening
      -- line names. The status is the trigger, never the command text.
      say_travel(travel.on_status(a))
      --[[ And it calls off a WARM-UP, which the same opening line offers
           the same way out of (Kevin, live client, 2026-08-22). Only the
           countdown answered `/heal` before, so a ring being warmed sat
           there with a GearSwap slot held until it fired - the one part of
           a trip the player could not call off. `travel.resting` is the
           same resolver the countdown's own cancel uses, rather than a
           second reading of the status that could hold a different
           opinion - and unlike `on_status` it answers whether or not
           anything happened to be armed. ]]
      if travel.resting(a) and pending_item ~= nil then
        abort_pending("crossbar: " .. pending_item.noun .. " cancelled - " .. tostring(pending_item.name))
      end
      -- (Resting keeps its own line above rather than end_trip's, because
      -- travel.on_status has already spoken the countdown's half of it.)
      local before = bindings.weapon_state()
      bindings.on_status(a)
      if bindings.weapon_state() ~= before then
        repaint()
      end
    elseif event == "ipc message" then
      if a == IPC_WARP_MESSAGE then
        -- The receiving half of `warp all`: warp locally, never re-broadcast.
        run_item_plan(warp.plan())
      end
    elseif event == "add item" or event == "remove item" then
      if counters.tracked_item(a) or bound_item_ids()[a] then
        counts_dirty = true
      end
    elseif event == "chunk" then
      if roulette ~= nil then
        roulette.on_chunk(a)
      end
      -- Coalesced by the flag, so an equip burst or a zone-in's inventory
      -- dump costs one re-read on the next tick rather than one per packet.
      if a == INVENTORY_CHUNK and counts_from_inventory() then
        counts_dirty = true
      end
      -- Coalesced the same way: an equip burst, or a zone-in's whole bag
      -- dump, costs one re-read on the next interval rather than one each.
      if a == INVENTORY_READY_CHUNK then
        weapon_dirty = true
      elseif a == EQUIP_CHUNK then
        local raw = ...
        local equip = ctx.parse_packet ~= nil and ctx.parse_packet(raw) or nil
        local moved = type(equip) == "table" and equip["Equipment Slot"] or nil
        if moved == nil or moved == MAIN_HAND_SLOT then
          weapon_dirty = true
        end
      end
      -- The skillchain feed, attached only: the action packet, decoded once
      -- by the entry point's dispatch and handed down beside the raw bytes,
      -- plus the buff and zone chunks the engine reads raw. Chain state
      -- changes draw from the tick - no repaint here, packets are not a
      -- place to touch prims.
      if machine ~= nil then
        local original, parsed = ...
        -- The cast retry's refusal branch, reading the same action-message
        -- packet the skillchain engine takes its wear-off from - and the
        -- zone-out, which invalidates a held cast exactly as it does the
        -- chain state.
        retry.on_chunk(a, original)
        if a == ZONE_OUT_CHUNK then
          retry.clear()
          -- A zone ends the moment a trip belonged to as surely as it ends
          -- a held cast - the warm-up included, since the ring is coming
          -- with you and the enchantment is not.
          end_trip("cancelled")
        end
        if a == ACTION_CHUNK then
          -- nil when the parse failed, which reads as nothing having landed.
          if parsed ~= nil then
            skillchain.on_action(parsed)
          end
        elseif SC_CHUNKS[a] then
          skillchain.on_chunk(a, original)
        end
      end
    end
  end

  --[[ Core pushes scale AND position for every anchor on every mouse move,
       though a drag moves one anchor and changes only one of the two; the
       push that changes nothing is dropped before it can lay anything out. ]]
  function self.set_pos(x, y, anchor)
    local entry = placement(anchor)
    if entry == nil or (entry.pos ~= nil and entry.pos.x == x and entry.pos.y == y) then
      return
    end
    entry.pos = { x = x, y = y }
    layout(anchor)
    refresh()
  end

  function self.set_scale(scale, anchor)
    local entry = placement(anchor)
    if entry == nil or entry.scale == scale then
      return
    end
    entry.scale = scale
    layout(anchor)
    refresh()
  end

  function self.set_preview(on)
    local wanted = on == true
    -- Core pushes the flag on every apply, which during a layout-mode drag
    -- is every mouse move; only a change is worth a pass.
    if wanted == preview then
      return
    end
    preview = wanted
    if preview then
      -- Core sets preview as layout mode opens, which is the one signal a
      -- component gets for it: entering layout mode exits edit mode, so the
      -- two never contend for the mouse. close_edit repaints on its own;
      -- preview itself only changes which groups the plan raises.
      close_edit()
    end
    refresh()
  end

  --[[ Core calls show() on every apply, so a layout-mode drag calls it on
       every mouse move; a widget already on screen has nothing to re-sync
       and must not repaint forty slots (or re-read the player) for it. The
       work below is the way back from hidden - a user hide, or core's
       suppression - and `visible` is the one thing that says which this is.
       Preview and edit-mode toggles do their own repainting, so nothing
       else rides on this call.

       An anchor name narrows the call to that anchor. The BARE form is the
       widget's own switch and puts every anchor back up: it is what layout
       mode force-shows with, and a hidden anchor that stayed hidden there
       could never be dragged or switched back on. ]]
  function self.show(anchor)
    local restored = false
    if anchor == nil then
      restored = next(hidden_anchors) ~= nil
      hidden_anchors = {}
    elseif hidden_anchors[anchor] then
      hidden_anchors[anchor] = nil
      restored = true
    end
    if visible then
      if restored then
        -- Repaint rather than refresh, for the reason below: the anchor's
        -- groups painted nothing while they were down.
        repaint()
      end
      return
    end
    visible = true
    -- Resync the side memory: while hidden the widget is disabled, so the
    -- machine swallowed releases (and ignored presses) without emitting
    -- activate intents, and the memory here went stale. This is the plan's
    -- suppression re-enable handshake: read hold_state() on the way back.
    active_state = machine and machine.hold_state() or "none"
    -- And repaint, not just refresh: an Expanded hold entered while hidden
    -- never painted its view's contents (group_target answered nil), so a
    -- bare refresh would show an empty bar. The change-gate and icon memo
    -- keep this cheap when nothing actually changed.
    repaint()
  end

  function self.hide(anchor)
    --[[ One anchor going down takes nothing else with it: the widget is still
         on screen and still the owner of its keys, so none of the teardown
         below applies - a retry or a trip is not a property of the anchor the
         user just switched off. ]]
    if anchor ~= nil then
      if hidden_anchors[anchor] then
        return
      end
      hidden_anchors[anchor] = true
      refresh()
      return
    end
    visible = false
    -- Suppression (a cutscene, zoning) and a user hide both arrive here,
    -- and a cast held through either would fire into a moment that has
    -- gone. Nothing the retry holds outlives the bar being on screen, and
    -- neither does a trip counting down.
    retry.clear()
    say_travel(travel.cancel())
    -- A hidden crossbar has no bar to bind against, and its panels would be
    -- left floating over a screen with nothing under them. Suppression
    -- (cutscene, zoning) arrives here as a hide too, and takes the binder
    -- with it for the same reason.
    close_edit()
    refresh()
  end

  -- The same origin set_pos was given, with render.lua's real footprint:
  -- main answers the whole XHB whatever is currently drawn in it.
  function self.get_bounds(anchor)
    local entry = placed[anchor]
    if not entry or not entry.pos then
      return nil
    end
    local width, height = render.bounds(anchor, entry.scale)
    return entry.pos.x, entry.pos.y, width, height
  end

  function self.handle_command(args)
    return dispatch_command(args)
  end

  --[[ The mouse, dispatched by core while any component declares
       `on_mouse` (touchpoint 3). Core has already answered an event layout
       mode owns or another addon took, so everything arriving here is
       genuinely free. Closed, this is one call and one comparison per
       event. ]]
  function self.on_mouse(mouse_type, x, y, delta)
    if not editing() then
      return false
    end
    return binder.mouse(mouse_type, x, y, delta) == true
  end

  function self.destroy()
    if binder ~= nil then
      binder.destroy()
    end
    abort_pending(nil)
    if prims == nil then
      return
    end
    prims.panel.destroy()
    prims.set_label.destroy()
    prims.set_icon.destroy()
    prims.indicator.bg.destroy()
    prims.indicator.fill.destroy()
    for _, group in ipairs(GROUPS) do
      for slot = 1, SLOT_COUNT do
        for _, prim in pairs(prims.groups[group.key][slot]) do
          prim.destroy()
        end
      end
    end
    prims = nil
  end

  return self
end

return new
