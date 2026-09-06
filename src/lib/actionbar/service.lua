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

--[[ The action service: the ONE place a press is executed, shared by every
     bar and by the framework's own `//hud warp|mr|sneak|invisible|draw`.

     It exists because the crossbar's execution glue held process-wide
     invariants - "only one wait of any kind is in flight", the GearSwap hold
     over a ring being warmed up, the cast retry's single held press, the
     player's weapon state - and a second bar with a scheduler of its own
     could issue a second `gs disable` over the same ring. So the scheduler,
     the travel countdown, the retry, the weaponskill gate, the skillchain
     engine, mount roulette and the warp and stealth ladders all live here,
     built once in the entry point (lib/player's shape) and handed to each bar
     as `ctx.actions`.

     A BAR keeps what is its own: its bindings, its job scoping, the facts a
     press needs from them (the weaponskill gate's facts, the retry's probe of
     whether the slot still holds the record) and its prims. It hands a
     resolved record to `fire` with those facts in `opts`, and reads
     `weapon_state()` back to mirror into its own rotation.

     Lines said here carry no bar's name: the entry point prefixes every line
     with the addon's, and a warp is nobody's bar's in particular. ]]

local new_actions = require("lib/actionbar/actions")
local new_retry = require("lib/actionbar/retry")
local new_travel = require("lib/actionbar/travel")
local new_wsgate = require("lib/actionbar/wsgate")
local new_enchanteditem = require("lib/actionbar/enchanteditem")
local enchanted = require("lib/actionbar/enchanted")
local counters = require("lib/actionbar/counters")
local new_warp = require("lib/warp")
local new_roulette = require("lib/roulette")
local new_skillchain = require("lib/skillchain")
local new_stealth = require("lib/stealth")

-- `warp all`'s broadcast. It named the crossbar until 2026-09-06; an alt on
-- the older build no longer hears this one (accepted, pre-release).
local IPC_WARP_MESSAGE = "xivhud warp"

--[[ Windower equipment slot id -> the name GearSwap knows it by, for the
     `gs disable` held over a slot while an enchanted item warms up. The
     warp ladder only ever needed main and ring1; an enchanteditem binding
     can name any worn piece, so the whole map is here.

     The IDS are attested in this repo - equipviewer/logic.lua carries all
     sixteen as the client's own equipment-table keys. The NAMES are not:
     the client calls id 13 `left_ring` where GearSwap wants `ring1`, and
     the same for the other ear and ring slots. ]]
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
     activation_time and answer "wait" forever. Added to the PLAN's bound
     rather than a fixed 45: a rung that waits longer needs a ceiling that
     waits longer too. ]]
local PENDING_DEADLINE_MARGIN = 15
-- enchanted.step's own default, read from the module so the deadline and
-- the abandon message cannot drift from the bound `step` actually applies.
local DEFAULT_GIVE_UP_SECONDS = enchanted.give_up_default()
-- The last seconds of a warm-up are counted aloud one at a time, from here.
local PENDING_COUNT_FROM = 5
-- The buff the client raises while mounted; the draw built-in dismounts on it.
local MOUNTED_BUFF = 252
local ACTION_CHUNK = 0x028
local ZONE_OUT_CHUNK = 0x0B
local SC_CHUNKS = { [0x29] = true, [0x63] = true, [ZONE_OUT_CHUNK] = true }
local DEAD_STATUSES = { [2] = true, [3] = true }

--[[ The cast retry's target pinning. A command's target is resolved by the
     GAME when the command is sent, so a re-send would otherwise land
     wherever the token points THEN. PINNED tokens are resolved to a mob id
     at the press and re-sent as the id; FIXED ones (yourself, your pet) need
     no pin; everything else is not watched at all - a token nobody thought
     of falls out unwatched rather than guessed at. See the crossbar plan's
     cast retry decision for the cases (party slots in particular). ]]
local FIXED_TARGETS = { me = true, pet = true }
local PINNED_TARGETS = { t = true, bt = true }
-- The record types the retry can watch, by the kind retry.lua refuses in.
local RETRY_KINDS = { ma = "spell", ja = "ability", ws = "weaponskill" }

local function new(deps)
  local self = { ipc_warp_message = IPC_WARP_MESSAGE }

  local function say(line)
    if deps.say ~= nil and line ~= nil then
      deps.say(line)
    end
  end

  local function send_command(command)
    if deps.send_command ~= nil then
      deps.send_command(command)
    end
  end

  -- Wall clock for the extdata maths (their timestamps are os.time-based);
  -- deps.now is the monotonic frame clock and would misread every enchant.
  local function time_now()
    if deps.time ~= nil then
      return deps.time()
    end
    return 0
  end

  local function frame_now()
    if deps.now ~= nil then
      return deps.now()
    end
    return 0
  end

  local function get_player()
    if deps.get_player ~= nil then
      return deps.get_player()
    end
    return nil
  end

  local resources = deps.resources

  --[[ Resource name lookups, indexed lazily by lowercased English name; the
       items table alone is tens of thousands of entries, so nothing walks it
       until something actually needs it. ]]
  local name_indexes = {}
  function self.find_resource(table_name, name)
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

  --[[ Execution collaborators. Mount roulette needs the resource tables, so
       without them it degrades to a no-op ride; warp degrades rung by rung
       (an empty bag table walks to "you don't have it"). ]]
  local roulette = nil
  if resources ~= nil then
    roulette = new_roulette({
      mounts = resources.mounts or {},
      key_items = resources.key_items or {},
      get_key_items = function()
        if deps.get_key_items ~= nil then
          return deps.get_key_items()
        end
        return {}
      end,
      get_buffs = function()
        local player = get_player()
        return player and player.buffs or {}
      end,
      zones = resources.zones,
      -- The recast's clock, read by the module itself: both the drawing and
      -- the press refusal must agree about how far along it is.
      now = frame_now,
      get_zone = function()
        return deps.zone ~= nil and deps.zone() or nil
      end,
      random = deps.random or math.random,
    })
  end
  self.roulette = roulette

  local equip_bags = {}
  if resources ~= nil then
    for id, bag in pairs(resources.bags or {}) do
      if type(bag) == "table" then
        equip_bags[id] = { name = bag.name or bag.en or tostring(id), equippable = bag.equippable and true or false }
      end
    end
  end

  local function read_bag(bag)
    if deps.get_items ~= nil then
      return deps.get_items(bag)
    end
    return nil
  end

  local function read_ext(item)
    return deps.decode_extdata ~= nil and deps.decode_extdata(item) or nil
  end

  --[[ The warp ladder's own reading of a decode it did not get: "not
       usable, not enchanted", so the rung is noted and the walk carries on
       to the next one rather than crashing. enchanteditem deliberately does
       NOT get this substitute: it has one item and no next rung, so "I could
       not read it" is a different answer from "it is a plain item". ]]
  local function decode_ext(item)
    return read_ext(item) or { type = "unavailable" }
  end

  local function get_spells()
    if deps.get_spells ~= nil then
      return deps.get_spells()
    end
    return {}
  end

  local function find_item(name)
    return self.find_resource("items", name)
  end

  local warp = new_warp({
    bags = equip_bags,
    get_player = get_player,
    get_spells = get_spells,
    get_items = read_bag,
    extdata_decode = decode_ext,
    now = time_now,
    find_item = find_item,
  })

  local enchanteditem = new_enchanteditem({
    bags = equip_bags,
    get_player = get_player,
    get_items = read_bag,
    extdata_decode = read_ext,
    now = time_now,
    find_item = find_item,
  })

  --[[ A PRESS-TIME bag read, bag 0 alone: a ninja tool or a Silent Oil in a
       wardrobe is not one the game will let you use. A press happens
       seconds apart, so reading the bag then is both cheap and current. ]]
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
    get_spells = get_spells,
    get_abilities = deps.get_abilities,
    resources = resources,
    tool_counts = function()
      return tally_inventory(counters.tracked_item) or {}
    end,
    --[[ nil, never 0, when the item cannot be resolved or the bag cannot be
         read: the ladder reads a real 0 as "you have none" and skips the
         rung, and refusing a press that might have worked is worse than
         letting the game answer for itself. ]]
    item_count = function(name)
      local entry = find_item(name)
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
      return deps.get_mob_by_target ~= nil and deps.get_mob_by_target("t") or nil
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
  self.actions = actions

  --[[ The chain-state engine: pure, always built - it needs no resources,
       only the clock and the target. The target dep is memoized PER TICK:
       the engine asks for it from window() and again from every bound
       slot's result(), which during an open window would be a client read
       per slot per frame. One read per tick is the contract, and the memo
       lives in the dep so the engine's API is untouched. ]]
  local sc_target = nil
  local sc_target_read = false

  local skillchain = new_skillchain({
    now = frame_now,
    get_mob_by_target = function()
      if not sc_target_read then
        sc_target_read = true
        sc_target = nil
        if deps.get_mob_by_target ~= nil then
          sc_target = deps.get_mob_by_target("t", "bt")
        end
      end
      return sc_target
    end,
    get_player = get_player,
  })
  self.skillchain = skillchain

  local function config()
    local live = deps.config ~= nil and deps.config() or nil
    return type(live) == "table" and live or {}
  end

  -- Each reads its config through a closure, so a write reaches it the
  -- moment it lands - `//hud retry off` with a cast already pending drops
  -- it rather than firing a last one.
  local retry = new_retry({
    now = frame_now,
    config = function()
      return config().retry
    end,
    get_player = get_player,
  })
  self.retry = retry

  local travel = new_travel({
    now = frame_now,
    config = config,
    statuses = resources ~= nil and resources.statuses or nil,
  })
  self.travel = travel

  local wsgate = new_wsgate({
    config = function()
      return config().wsgate
    end,
    statuses = resources ~= nil and resources.statuses or nil,
  })
  self.wsgate = wsgate

  --[[ Weapon state: the PLAYER's, never the client's status. `draw` toggles
       it, engaging in game enters drawn, and a mob dying does not leave it -
       so a bar's cycle rotation cannot lurch back mid-pull. One state for
       every bar, which is why it lives here and not in a bar's bindings. ]]
  local weapon = "sheathed"

  function self.weapon_state()
    return weapon
  end

  function self.set_weapon_state(state)
    if state == "drawn" or state == "sheathed" then
      weapon = state
    end
  end

  --[[ The config modes: `//hud layout` and a bar's binder are for arranging
       the HUD, not for playing in. A bar reports its binder here, so a trip
       refuses to arm under either and one already counting down is called
       off. Layout mode is asked first because entering it closes every
       binder, so it is the one that is open when both look it. ]]
  local editing = {}

  function self.set_edit_mode(owner, open)
    editing[owner] = open and true or nil
  end

  local function layout_active()
    return deps.layout_active ~= nil and deps.layout_active() == true
  end

  local function chat_open()
    return deps.chat_open ~= nil and deps.chat_open() == true
  end

  local function config_mode()
    if layout_active() then
      return "//hud layout"
    end
    if next(editing) ~= nil then
      return "edit mode"
    end
    return nil
  end
  self.mode = config_mode

  local function selected_id(token)
    local mob = deps.get_mob_by_target ~= nil and deps.get_mob_by_target(token) or nil
    return mob ~= nil and mob.id or nil
  end

  --[[ The command the cast retry would RE-SEND for a press, or nil for a
       press it must not watch at all. A pinned token becomes the id it
       stood for at the press; the suffix is matched literally over a tail
       of the command's own length, and a command that does not end in the
       expected `<token>` is not watched - a substitution this cannot prove
       correct is worse than no retry. ]]
  local function resend_command(command, target)
    if type(command) ~= "string" then
      return nil
    end
    target = type(target) == "string" and target:lower() or target
    if FIXED_TARGETS[target] then
      return command
    end
    if not PINNED_TARGETS[target] then
      return nil
    end
    local id = selected_id(target)
    if id == nil then
      return nil
    end
    local suffix = " <" .. target .. ">"
    if command:sub(-#suffix):lower() ~= suffix then
      return nil
    end
    return command:sub(1, #command - #suffix) .. " " .. tostring(id)
  end
  self.resend_command = resend_command

  function self.draw_state()
    local player = get_player()
    local mounted = false
    for _, buff in ipairs(player and player.buffs or {}) do
      if buff == MOUNTED_BUFF then
        mounted = true
        break
      end
    end
    return { mounted = mounted, weapon_drawn = weapon == "drawn" }
  end

  --[[ The pending machine: equip -> wait -> use, for a ring being warmed up.
       One at a time, whatever armed it - there is one pair of hands. ]]
  local pending_item = nil

  local function dropped_line()
    if pending_item == nil then
      return nil
    end
    return pending_item.noun .. " dropped - " .. tostring(pending_item.name)
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

  local function abandon(reason)
    if pending_item == nil then
      return
    end
    local message = pending_item.noun .. " abandoned"
    if reason ~= nil then
      message = message .. " - " .. tostring(pending_item.name) .. " " .. reason
    end
    abort_pending(message)
  end

  --[[ Runs one of warp.lua's or enchanteditem.lua's plans - the same three
       shapes, so one scheduler serves both. `broadcast`, when given, is
       `warp all`'s IPC send, and it fires where the LOCAL warp commits and
       nowhere else: with the command for a spell or a charged item, with
       the deferred use for a ring being warmed up, at once when the ladder
       found nothing at all. ]]
  local function run_item_plan(plan, broadcast, noun)
    noun = noun or "warp"
    if pending_item ~= nil then
      say(pending_item.noun .. " already in progress - " .. tostring(pending_item.name))
      return
    end
    for _, note in ipairs(plan.notes or {}) do
      say(note)
    end
    if plan.type == "spell" or plan.type == "use" then
      send_command(plan.command)
    elseif plan.type == "equip" then
      --[[ The target is resolved HERE, at the press, or the press does not
           happen: the command goes when the enchantment comes up, as much
           as a minute later, and a token carried that far would land on
           whatever had been tabbed to since. Refused before anything is
           held, so a press that will not happen leaves no GearSwap slot
           disabled behind it. ]]
      local deferred = plan.command
      if plan.target ~= nil then
        deferred = resend_command(plan.command, plan.target)
        if deferred == nil then
          local token = type(plan.target) == "string" and plan.target:lower() or plan.target
          if PINNED_TARGETS[token] then
            say(noun .. " pressed with nothing targeted - " .. tostring(plan.name))
          else
            say("cannot pin <" .. tostring(token) .. "> at the press - bind <me> or <t>")
          end
          return
        end
      end
      -- A running GearSwap would otherwise swap the ring straight back off
      -- before it fires. The plan names which slots to hold.
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
      if deps.set_equip ~= nil and not plan.equipped then
        deps.set_equip(plan.bag_slot, plan.equip_slot, plan.bag)
      end
      -- Said at the press: the wait that follows can be half a minute. How
      -- long is not knowable yet; tick_pending speaks it once it has a number.
      local doing = plan.equipped and " - waiting for it to charge." or " - equipping it first."
      say(noun .. " with " .. tostring(plan.name) .. doing)
      pending_item = {
        broadcast = broadcast,
        noun = noun,
        equipped = plan.equipped == true,
        name = plan.name,
        command = deferred,
        item_id = plan.id,
        bag = plan.bag,
        bag_slot = plan.bag_slot,
        equip_slot = plan.equip_slot,
        gs_slots = gs_slots,
        give_up = plan.give_up,
        deadline = time_now() + (plan.give_up or DEFAULT_GIVE_UP_SECONDS) + PENDING_DEADLINE_MARGIN,
      }
      return
    end
    if broadcast ~= nil then
      broadcast()
    end
  end

  --[[ One poll of the equip -> wait -> use machine, from the tick: no
       coroutine sleeps, and every exit re-enables GearSwap. The poll runs
       once a second, never a whole-bag read per frame; the suppression and
       deadline aborts check every frame, ahead of the poll gate. ]]
  local function tick_pending()
    if pending_item == nil then
      return
    end
    if deps.suppressed ~= nil and deps.suppressed() then
      abandon()
      return
    end
    if time_now() >= pending_item.deadline then
      abandon("took too long")
      return
    end
    local now = frame_now()
    if pending_item.next_poll ~= nil and now < pending_item.next_poll then
      return
    end
    pending_item.next_poll = now + 1
    local bag = read_bag(pending_item.bag)
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
         same breath as the press lands on top of ours. Put it back, once a
         second until the deadline gives up, and read NOTHING off it until
         it is on: the extdata of a ring in the bag belongs to some earlier
         equip. Only on the equip path - a piece already worn at the press
         is left alone, since re-equipping would restart the warmup. ]]
    if not pending_item.equipped and item.status ~= EQUIPPED then
      if deps.set_equip ~= nil and pending_item.equip_slot ~= nil then
        deps.set_equip(pending_item.bag_slot, pending_item.equip_slot, pending_item.bag)
      end
      return
    end
    local ext = read_ext(item)
    --[[ BOTH conditions: the press-time flag, because only a wait armed over
         a piece that was ALREADY on may trust activation_time at all; and
         the live status, because the piece can come OFF mid-wait. ]]
    local worn = pending_item.equipped and item.status == EQUIPPED
    local step = ext ~= nil and enchanted.step(ext, time_now(), worn, pending_item.give_up) or nil
    if step == nil then
      abandon("cannot be read")
      return
    end
    if step == "wait" then
      local remaining = math.ceil(enchanted.warmup_remaining(ext, time_now()))
      -- A POSITIVE reading only: on the equip path the first polls read zero
      -- while the ring is genuinely warming, and "ready in 0 seconds" then
      -- latched the counter so no later reading ever spoke.
      if remaining > 0 then
        -- A warm-up that RESTARTED (the re-equip loop above wins a slot
        -- back) pushes `remaining` up; re-seed and count the new one down.
        if pending_item.said ~= nil and remaining > pending_item.said then
          pending_item.said = remaining
        end
        if pending_item.said == nil then
          pending_item.said = remaining
          say(
            tostring(pending_item.name)
              .. " ready in "
              .. remaining
              .. (remaining == 1 and " second" or " seconds")
              .. ". /heal to cancel."
          )
        end
        if remaining < pending_item.said then
          pending_item.said = remaining
          if remaining <= PENDING_COUNT_FROM then
            -- Bare, like the travel countdown's own counts: they read as a
            -- continuation of the line that named them.
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
      -- The REMAINING delay exceeds the bound, so waiting is pointless.
      abandon("needs more than " .. (pending_item.give_up or DEFAULT_GIVE_UP_SECONDS) .. " sec")
    end
  end

  -- Runs a resolved plan. Console strings are composed in actions.lua,
  -- where they are pure; this stays a plain send_command.
  local function execute(plan, hint)
    if plan == nil then
      say(hint)
      return
    end
    if plan.weapon_state ~= nil then
      self.set_weapon_state(plan.weapon_state)
    end
    if plan.kind == "command" then
      -- The mount recast is ours to track: nothing in the client's recast
      -- tables names it, so the clock starts where the summon goes out -
      -- after the travel wait, not at the press that armed it.
      if plan.mount_summon and roulette ~= nil then
        roulette.summoned()
      end
      send_command(plan.command)
    elseif plan.kind == "message" then
      say(plan.message)
    elseif plan.kind == "warp" then
      run_item_plan(plan.plan)
    elseif plan.kind == "enchanted" then
      -- Outside the travel gate: the warmup already is the wait, and an
      -- enchanted item is not a trip you press by mistake and want back.
      run_item_plan(plan.plan, nil, "enchanted item")
    end
  end

  --[[ The travel gate: mount, mount roulette and warp arm a countdown
       instead of firing. Answers whether the press was held - false means
       fire it now. `fire` closes over the plan computed AT THE PRESS: the
       opening line names the rung, and a line promising one item while
       another goes is the worse trade. ]]
  local function delay_travel(record, plan, fire)
    local label = travel.label(record, plan)
    if label == nil then
      -- A trip that goes at once is still a newer trip, so it ends whatever
      -- was counting down; an ordinary press leaves the countdown alone.
      if travel.travels(record) then
        say(travel.cancel())
      end
      return false
    end
    local mode = config_mode()
    if mode ~= nil then
      say(label .. " - not while " .. mode .. " is open")
      return true
    end
    local message = travel.arm({
      label = label,
      fire = fire or function()
        execute(plan)
      end,
    })
    if message == nil then
      return false
    end
    say(message)
    return true
  end

  --[[ A bar's press, whatever pointed at it - a key or a click. `record` is
       the bar's resolved binding (nil for an empty slot); `opts` carries
       what only the bar knows:

         gate_facts   the weaponskill gate's facts (tp, status, buffs, skill,
                      distance_squared, model_size), or nil to allow
         flash        called once the gate has passed, before the send
         retry_facts  the retry's probe, answering { bound, recast,
                      affordable, buffs } for the press it is handed; a
                      press with no probe is never watched
         owner        the bar's name, so its hide drops its own held cast

       Everything after the resolve - the gate, the flash, the travel
       countdown, the retry - is the same for every way in, deliberately. ]]
  function self.fire(record, opts)
    opts = opts or {}
    if record == nil then
      -- An empty slot is silent, but it is still a newer press, so it
      -- drops whatever the retry was watching.
      retry.sent(nil)
      return
    end
    -- The gate BEFORE the flash: a press the game could never honour is a
    -- complete no-op, and the retry keeps whatever it was watching.
    if not wsgate.allow(record, opts.gate_facts) then
      return
    end
    if opts.flash ~= nil then
      opts.flash()
    end
    local plan, hint = actions.resolve(record, self.draw_state())
    if not delay_travel(record, plan) then
      execute(plan, hint)
    end
    -- After the send, never before it: this feature reacts, and a press the
    -- game accepts is never delayed by it. What is stored is the RE-SEND
    -- form, target already pinned; the bar's probe rides along.
    local sent = nil
    local kind = RETRY_KINDS[record.type]
    if kind ~= nil and plan ~= nil and plan.kind == "command" and retry.enabled() and opts.retry_facts ~= nil then
      local resend = resend_command(plan.command, record.target)
      if resend ~= nil then
        sent = { record = record, command = resend, kind = kind, probe = opts.retry_facts, owner = opts.owner }
      end
    end
    retry.sent(sent)
  end

  -- A built-in by name from the console (`draw`, `mr`, `sneak`, `invisible`,
  -- `open <name>`). Answers a hint for a name or argument it cannot run, nil
  -- when the press went - or was refused in words already said.
  function self.builtin(name, arg)
    local plan, hint = actions.resolve_builtin(name, arg, self.draw_state())
    if plan == nil then
      return hint
    end
    local record = { type = type(name) == "string" and name:lower() or name, action = arg }
    if not delay_travel(record, plan) then
      execute(plan, hint)
    end
    return nil
  end

  -- The sword's click: one way, no state read - mounted, `draw` would
  -- dismount instead, which is not what a click on a sword means.
  function self.sheathe()
    execute(actions.sheathe())
  end

  --[[ The warp verb. Walked ONCE, and the rung it picks is the rung that
       fires: the opening line names it. `all` broadcasts to the alts where
       the local warp commits - run_item_plan knows where that is. ]]
  function self.warp(all)
    local broadcast = nil
    if all and deps.send_ipc ~= nil then
      broadcast = function()
        deps.send_ipc(IPC_WARP_MESSAGE)
      end
    end
    local ladder = warp.plan()
    local function go()
      run_item_plan(ladder, broadcast)
    end
    if not delay_travel({ type = "warp" }, { kind = "warp", plan = ladder }, go) then
      go()
    end
  end

  --[[ A transition that ends whatever trip was in flight - a countdown AND
       a warm-up. One helper, so the endings cannot drift apart. ]]
  function self.end_trip(reason)
    say(travel.cancel())
    if pending_item ~= nil then
      abort_pending(pending_item.noun .. " " .. reason .. " - " .. tostring(pending_item.name))
    end
  end

  --[[ A trip dropped by a bar's re-attach or detach: the countdown goes
       silently (a reset is not a cancellation the player needs told about),
       a warm-up says so, because a ring left on your finger with nothing
       coming is not something to work out from silence. ]]
  function self.drop_trip()
    travel.clear()
    abort_pending(dropped_line())
  end

  --[[ A bar going off screen. The cast it pressed does not outlive it - the
       retry is keyed to the OWNER that pressed it, so one bar hiding drops
       its own held cast and leaves the other's alone. A trip counting down
       is the player's, not a bar's, and goes only when the moment has gone:
       suppression (a cutscene, zoning), which hides every bar at once. A
       user switching one bar off is not a change of mind about a warp. ]]
  function self.bar_hidden(owner)
    local held = retry.held()
    if held ~= nil and held.owner == owner then
      retry.clear()
    end
    if deps.suppressed ~= nil and deps.suppressed() then
      say(travel.cancel())
    end
  end

  --- Which bar's binder is open, or nil: a second bar must not open its own
  --- over it, or one click would be answered by both.
  function self.edit_owner()
    return (next(editing))
  end

  --[[ Once per frame, from core, BEFORE any bar's tick: the target memo is
       re-armed here, the config-mode gate runs ahead of the poll (or the
       poll fires the very trip the gate is there to call off), the warp
       poll keeps its own 1s cadence whether or not any bar is on screen,
       then the countdown, then the retry. ]]
  function self.tick()
    sc_target_read = false
    if (travel.armed() or pending_item ~= nil) and config_mode() ~= nil then
      self.end_trip("cancelled")
    end
    tick_pending()
    local travelling, count = travel.step()
    say(count)
    if travelling ~= nil then
      travelling.fire()
    end
    -- The pending test first, a plain nil check: the guards behind it are
    -- client calls, and a player who never turns the feature on must not
    -- pay for one sixty times a second. A re-send is the same press
    -- arriving late, so it fires only where a press would - never into an
    -- open chat line, never under a binder, never in layout mode.
    if retry.pending() ~= nil then
      if chat_open() or config_mode() ~= nil then
        retry.clear()
      else
        local resend = retry.step(function(entry)
          return entry.probe(entry)
        end)
        if resend ~= nil then
          send_command(resend.command)
        end
      end
    end
  end

  --[[ Events, forwarded by the entry point - never by a bar, or two bars
       would feed one engine twice. ]]
  function self.on_chunk(id, data, parsed)
    if roulette ~= nil then
      roulette.on_chunk(id)
    end
    retry.on_chunk(id, data)
    if id == ZONE_OUT_CHUNK then
      -- A zone ends the moment a trip belonged to as surely as it ends a
      -- held cast - the warm-up included, since the ring is coming with
      -- you and the enchantment is not.
      retry.clear()
      self.end_trip("cancelled")
    end
    if id == ACTION_CHUNK then
      if parsed ~= nil then
        skillchain.on_action(parsed)
      end
    elseif SC_CHUNKS[id] then
      skillchain.on_chunk(id, data, parsed)
    end
  end

  function self.on_status(status)
    if DEAD_STATUSES[status] then
      retry.clear()
      self.end_trip("cancelled")
    end
    -- Resting calls a countdown off, which is the way out the opening line
    -- names; and a warm-up, which offers the same way out.
    say(travel.on_status(status))
    if travel.resting(status) and pending_item ~= nil then
      abort_pending(pending_item.noun .. " cancelled - " .. tostring(pending_item.name))
    end
    -- The one-way game trigger: engaging by any means enters drawn; a
    -- disengage the game forced changes nothing.
    if status == 1 or status == 3 then
      weapon = "drawn"
    end
  end

  function self.on_job_change()
    -- A cast held across a job change belongs to the job that pressed it,
    -- and so does a trip - the warm-up included.
    retry.clear()
    self.end_trip("cancelled")
    -- Loading a job sheathes you without a transition; the bars' bindings
    -- reset the same way on set_job, and the two must agree or the mirror
    -- would put the drawn rotation straight back.
    weapon = "sheathed"
  end

  function self.on_ipc(message)
    if message == IPC_WARP_MESSAGE then
      -- The receiving half of `warp all`: warp locally, never re-broadcast.
      run_item_plan(warp.plan())
    end
  end

  function self.on_logout()
    self.drop_trip()
    retry.clear()
    skillchain.reset()
    weapon = "sheathed"
    editing = {}
  end

  -- The addon going away: every GearSwap slot it held is released, in
  -- silence - nobody is left to read a line about it.
  function self.on_unload()
    travel.clear()
    abort_pending(nil)
    retry.clear()
  end

  -- What core seeds its own config with, so the tuning has a home and a
  -- name before anyone types a verb.
  function self.config_defaults()
    return { retry = retry.defaults(), wsgate = wsgate.defaults(), delay = travel.defaults().delay }
  end

  return self
end

return new
