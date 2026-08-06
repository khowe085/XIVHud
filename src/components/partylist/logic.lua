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

--[[ The party list state machine: a roster and a stream of packets in, a
     per-frame render plan out.

     No prims and no Windower here -- partylist.lua turns the plan into prim
     calls, and the entry point does the talking to the client. Behaviour
     follows XIVParty (bar fills, colour bands, distance dimming, buff order)
     with its rough edges left behind; see the component plan for the list.

     Two data streams meet here. The 200ms `get_party()` poll is authoritative:
     it reads the client's own state, which is downstream of the very packets
     we parse. The 0x0DD / 0x0DF pushes that land between polls are a latency
     accelerator on top, and a poll always wins the disagreement -- which is
     also what makes a dropped packet a one-tick problem rather than a bar
     frozen for the rest of the session. ]]

local layouts = require("components/partylist/layout")
local job_table = require("components/partylist/jobs")
local shipped_buff_order = require("components/partylist/buff_order")

local EASE = 0.1
local FULL_TP = 1000
local TP_PER_PERCENT = 10

-- XIVParty's ranges, in the same units as the (square-rooted) mob distance.
local CAST_RANGE = 20.79
local TARGET_RANGE = 50

-- The bar opacity XIVParty dims to outside each range.
local ALPHA_IN_CAST_RANGE = 255
local ALPHA_IN_TARGET_RANGE = 128
local ALPHA_OUT_OF_RANGE = 64

-- XIVParty's bands, strictly less than, on the percent value.
local BANDS = { { 25, "red" }, { 50, "orange" }, { 75, "yellow" } }

local PARTY_KEYS = { main = "p%d", alliance1 = "a1%d", alliance2 = "a2%d" }

local DEFAULT_POLL_INTERVAL_MS = 200

local OWN_VITALS = { hp = true, hpp = true, mp = true, mpp = true, tp = true }

--[[ The party layout mode shows when there is no party to show. Hand-written
     rather than randomised, because a preview that reshuffles under a drag is
     worse than no preview: it looks like the drag did something. One member is
     out of zone and one is the target, so both of those looks can be seen. ]]
local PREVIEW = {
  { name = "Ayame", job = "SAM", level = 99, sub_job = "WAR", sub_level = 49, hpp = 100, mpp = 100, tp = 1000 },
  { name = "Volker", job = "WAR", level = 99, sub_job = "NIN", sub_level = 49, hpp = 72, mpp = 40, tp = 300 },
  { name = "Ulmia", job = "BRD", level = 99, sub_job = "WHM", sub_level = 49, hpp = 48, mpp = 88, tp = 0 },
  { name = "Kupipi", job = "WHM", level = 99, sub_job = "BLM", sub_level = 49, hpp = 21, mpp = 65, tp = 1500 },
  { name = "Curilla", job = "PLD", level = 99, sub_job = "WAR", sub_level = 49, hpp = 90, mpp = 12, tp = 800 },
  { name = "Rughadjeen", job = "PLD", level = 99, hpp = 100, mpp = 100, tp = 0, elsewhere = true },
}
local PREVIEW_ZONE = 0
local PREVIEW_ELSEWHERE_ZONE = 1
local PREVIEW_BUFFS = { 33, 40, 43, 41, 42, 45, 44, 46, 32, 34, 36, 39 }

local function band_for(percent)
  for _, band in ipairs(BANDS) do
    if percent < band[1] then
      return band[2]
    end
  end
  return "normal"
end

local function new(deps)
  local self = {}
  local config = deps.config or {}
  local variant = deps.variant or "main"
  local resources = deps.resources or {}
  local layout = layouts[variant == "main" and "main" or "alliance"]
  -- Both layouts hold six, one as a column and one as a 3x2 grid; taking it
  -- from the layout rather than a constant is what lets a layout file change it.
  local MEMBERS_PER_PARTY = layout.rows * layout.columns

  --[[ Everything the rows are drawn from. Two bags of it: the live one, which
       the setters always write to, and the preview one that layout mode swaps
       in front. Readers go through bag(), so a preview never has to be undone
       -- and a party that changes mid-drag is still there when the drag ends.

       `pushed` is vitals from 0x0DD / 0x0DF, cleared by every poll: the poll
       is the authority and these only carry the gap between two of them. ]]
  local function empty_bag()
    return {
      roster = {},
      pushed = {},
      roles = {},
      jobs = {},
      named_jobs = {},
      buffs = {},
      ids_by_name = {},
      own_vitals = {},
      player = nil,
      zone = nil,
      target = nil,
      subtarget = nil,
    }
  end

  local live = empty_bag()
  local preview_bag = nil

  local function bag()
    return preview_bag or live
  end

  local buff_ranks = nil
  local buff_ordered = nil
  local trust_cache = {}
  local next_poll = nil

  -- Bar animation state, keyed by list position. A slot whose occupant changes
  -- restarts rather than easing the new member's bar down from the old one's.
  -- `forced` is the one flag kept: a bar at its target is not redrawn, so a
  -- scale change needs a way to say "push everything again anyway".
  local eased = {}
  for slot = 1, MEMBERS_PER_PARTY do
    eased[slot] = { occupant = nil, hp = 0, mp = 0, tp = 0, forced = { hp = true, mp = true, tp = true } }
  end

  local function bar_keys()
    local keys = {}
    for index, bar in ipairs(layout.row.bars) do
      keys[index] = bar.key
    end
    return keys
  end

  local BARS = bar_keys()

  function self.set_config(new_config)
    config = new_config or {}
    self.invalidate()
    self.invalidate_buff_order()
  end

  -- The effective buff order is derived from a 621-entry list plus the user's
  -- overrides, so it is built once and kept until something changes it.
  function self.invalidate_buff_order()
    buff_ranks, buff_ordered = nil, nil
  end

  -- Forces every bar to re-push next tick. The widget calls this after a
  -- layout change: fill sizes are only written for a dirty bar, so a scale
  -- change would otherwise leave them at the previous scale.
  function self.invalidate()
    for slot = 1, MEMBERS_PER_PARTY do
      for _, key in ipairs(BARS) do
        eased[slot].forced[key] = true
      end
    end
  end

  function self.set_zone(zone_id)
    live.zone = zone_id
  end

  --[[ Layout mode force-shows every widget so it can be dragged, and a solo
       player has nothing to drag. This puts a full party in front of the live
       one -- the live bag keeps filling underneath, so the real party is back
       the moment the drag ends. ]]
  function self.set_preview(on)
    on = on and true or false
    if on == (preview_bag ~= nil) then
      return
    end

    if not on then
      preview_bag = nil
      self.invalidate()
      return
    end

    local sample = empty_bag()
    sample.zone = PREVIEW_ZONE
    sample.player = { name = PREVIEW[1].name, buffs = PREVIEW_BUFFS }
    -- The second row is the target, so the cursor and the job highlight are
    -- both visible while the list is being placed.
    sample.target = 2

    for slot, entry in ipairs(PREVIEW) do
      sample.roster[slot] = {
        name = entry.name,
        hp = math.floor(2500 * entry.hpp / 100),
        hpp = entry.hpp,
        mp = math.floor(1200 * entry.mpp / 100),
        mpp = entry.mpp,
        tp = entry.tp,
        zone = entry.elsewhere and PREVIEW_ELSEWHERE_ZONE or PREVIEW_ZONE,
        mob = entry.elsewhere and nil or { id = slot, distance = (slot * 4) ^ 2, is_npc = false, models = { 0 } },
      }
      sample.named_jobs[slot] = {
        job = entry.job,
        level = entry.level,
        sub_job = entry.sub_job,
        sub_level = entry.sub_level,
      }
      sample.buffs[slot] = PREVIEW_BUFFS
    end
    sample.roles[1] = { leader = true, alliance_leader = true, quartermaster = false }

    preview_bag = sample
    self.invalidate()
  end

  -- Which row carries the cursor. Read every frame rather than on the poll:
  -- 200ms between a target keypress and the cursor moving is visible.
  function self.set_target(target, subtarget)
    live.target, live.subtarget = target, subtarget
  end

  -- 0x0C8 is a whole-alliance snapshot, so this replaces the previous set
  -- rather than merging into it -- otherwise a demoted leader keeps their mark.
  function self.apply_alliance_flags(new_roles)
    live.roles = new_roles or {}
  end

  -- Jobs from 0x0DD / 0x0DF. There is no poll path for these: get_party()
  -- reports no job at all, so the packets are the only source for anyone but
  -- the player themselves.
  -- The name/id pairing from 0x0DD, which is the only packet carrying both.
  function self.apply_member_identity(id, name)
    if type(id) == "number" and type(name) == "string" and name ~= "" then
      live.ids_by_name[name] = id
    end
  end

  function self.apply_job(id, job)
    if type(id) ~= "number" or type(job) ~= "table" then
      return
    end
    live.jobs[id] = job
  end

  -- windower.ffxi.get_player(). The player's own job and buffs are not in any
  -- party packet, so they come from here.
  function self.set_main_player(player)
    live.player = player
  end

  -- Buffs from 0x076, which carries the main party only -- and never the
  -- player themselves. There is no poll path at all: get_party() reports no
  -- buffs and get_player().buffs covers you alone.
  function self.apply_buffs(id, buffs)
    if type(id) ~= "number" or type(buffs) ~= "table" then
      return
    end
    live.buffs[id] = buffs
  end

  --[[ Your own vitals, from the `hp change` / `hpp change` / ... events -- the
       same stream parambar reads. Without them your row would be the only one
       in the list moving at the poll rate while the parameter bar beside it
       moved instantly. TP is taken here, unlike from a packet: the change
       event is unambiguously the 0..3000 scale. Overruled by the next poll,
       exactly as a packet push is. ]]
  function self.set_own_vital(kind, value)
    if OWN_VITALS[kind] and type(tonumber(value)) == "number" then
      live.own_vitals[kind] = tonumber(value)
    end
  end

  -- HP and MP from 0x0DD / 0x0DF, applied until the next poll overrules them.
  function self.apply_vitals(id, vitals)
    if type(id) ~= "number" or type(vitals) ~= "table" then
      return
    end
    local pushed = live.pushed[id] or {}
    for key, value in pairs(vitals) do
      if type(value) == "number" then
        pushed[key] = value
      end
    end
    live.pushed[id] = pushed
  end

  --[[ The id lives in the mob table, and get_party() has no mob for a member
       outside the zone. 0x0DD carries the name and the id together, so the
       pairing is remembered: without it an out-of-zone member can never be
       matched to their 0x0C8 leader flags, their cached job is pruned the
       moment they leave the zone, and two members occupying one slot in turn
       share an eased bar. ]]
  local function member_id_in(source, member)
    if member.mob and member.mob.id then
      return member.mob.id
    end
    return source.ids_by_name[member.name]
  end

  local function member_id(member)
    return member_id_in(bag(), member)
  end

  --[[ There is no party event of any kind, so who is in the party can only
       come from polling. The call is indivisible -- it hands back whole member
       tables -- so the vitals that arrive with the roster are used rather than
       thrown away, which is what seeds a member who joined before the addon
       loaded. ]]
  function self.set_roster(party)
    party = party or {}
    local key = PARTY_KEYS[variant] or PARTY_KEYS.main
    for slot = 1, MEMBERS_PER_PARTY do
      local member = party[key:format(slot - 1)]
      live.roster[slot] = (type(member) == "table" and member.name) and member or nil
    end
    live.pushed = {}
    live.own_vitals = {}

    -- Packets are keyed by player id and nothing ever says a member left, so
    -- without this the job and buff tables grow for the length of a session --
    -- XIVParty's allPlayers list, which is only cleared on zoning.
    local present = {}
    for slot = 1, MEMBERS_PER_PARTY do
      -- Against `live`, not bag(): the poll keeps running while layout mode
      -- previews, and the preview bag knows none of the real pairings -- so
      -- resolving through it would decide every out-of-zone member had left.
      local id = live.roster[slot] and member_id_in(live, live.roster[slot])
      if id then
        present[id] = true
      end
    end
    for _, keyed in ipairs({ live.jobs, live.buffs }) do
      for id in pairs(keyed) do
        if not present[id] then
          keyed[id] = nil
        end
      end
    end
    for name, id in pairs(live.ids_by_name) do
      if not present[id] then
        live.ids_by_name[name] = nil
      end
    end
  end

  -- True once per poll interval. Nonsense in the config means every frame,
  -- which is merely wasteful rather than a gate that never opens.
  function self.due_for_poll(now)
    local interval = tonumber(config.poll_interval_ms) or DEFAULT_POLL_INTERVAL_MS
    if interval <= 0 then
      return true
    end
    if next_poll and now < next_poll then
      return false
    end
    next_poll = now + interval / 1000
    return true
  end

  local function is_main_player(member)
    local player = bag().player
    return player ~= nil and player.name ~= nil and member.name == player.name
  end

  -- Poll values first, then whatever a packet has pushed since that poll.
  local function vitals_of(member)
    local vitals = {
      hp = member.hp or 0,
      mp = member.mp or 0,
      tp = member.tp or 0,
      hpp = member.hpp or 0,
      mpp = member.mpp or 0,
    }
    local pushed = bag().pushed[member_id(member)]
    for key, value in pairs(pushed or {}) do
      if type(value) == "number" then
        vitals[key] = value
      end
    end
    if is_main_player(member) then
      for key, value in pairs(bag().own_vitals) do
        vitals[key] = value
      end
    end
    return vitals
  end

  -- get_party() reports the square of the distance.
  local function distance_of(member)
    local squared = member.mob and member.mob.distance
    return squared and math.sqrt(squared) or nil
  end

  local function alpha_for(distance)
    if distance and distance < CAST_RANGE then
      return ALPHA_IN_CAST_RANGE
    elseif distance and distance < TARGET_RANGE then
      return ALPHA_IN_TARGET_RANGE
    end
    return ALPHA_OUT_OF_RANGE
  end

  --[[ One eased step towards the target, parambar's exponential ease-out.
       `math.ceil` guarantees it converges instead of creeping asymptotically.

       Dirtiness is *derived* from the gap rather than flagged by whoever moved
       the value. Vitals arrive from a poll, from two packet types and from a
       slot changing hands, and every one of those would otherwise have to
       remember to raise a flag; XIVBar's equivalent bug -- clearing the wrong
       flag, so its HP bar re-eased forever -- came from exactly that split. ]]
  local function ease(state, key, target, limit)
    local old = state[key]
    local forced = state.forced[key]
    state.forced[key] = false

    if old == target then
      return old, forced
    end
    if old < target then
      state[key] = math.min(old + math.ceil((target - old) * EASE), limit)
    else
      state[key] = math.max(old - math.ceil((old - target) * EASE), 0)
    end
    return state[key], true
  end

  local function percent_of(key, vitals, outside_zone)
    if outside_zone then
      return 0
    end
    if key == "hp" then
      return vitals.hpp
    elseif key == "mp" then
      return vitals.mpp
    end
    return math.min(vitals.tp / TP_PER_PERCENT, 100)
  end

  local function band_of(key, vitals, outside_zone)
    if outside_zone then
      return "normal"
    end
    if key == "hp" then
      return band_for(vitals.hpp)
    elseif key == "tp" then
      return vitals.tp >= FULL_TP and "full_tp" or "normal"
    end
    return "normal"
  end

  local function bar_plans(slot, vitals, outside_zone, distance)
    local state = eased[slot]
    local plans = {}
    local alpha = alpha_for(distance)

    for index, spec in ipairs(layout.row.bars) do
      local key = spec.key
      local limit = spec.fill.size[1]
      local target = math.floor(percent_of(key, vitals, outside_zone) / 100 * limit)
      local width, dirty = ease(state, key, target, limit)

      plans[key] = {
        index = index,
        width = width,
        hidden = width == 0,
        dirty = dirty,
        text = outside_zone and "?" or tostring(vitals[key]),
        band = band_of(key, vitals, outside_zone),
        alpha = alpha,
      }
    end

    return plans
  end

  -- Nothing is drawn for an empty row -- the widget disposes its prims -- so
  -- these are the plan's shape and nothing more. The next occupant restarts
  -- the animation from zero, which is what the occupant check in row_plan does.
  local function empty_bar_plans()
    local plans = {}
    for index, spec in ipairs(layout.row.bars) do
      plans[spec.key] = {
        index = index,
        width = 0,
        hidden = true,
        dirty = false,
        text = "",
        band = "normal",
        alpha = ALPHA_OUT_OF_RANGE,
      }
    end
    return plans
  end

  local function zone_text(member, outside_zone)
    if not outside_zone or not member.zone then
      return ""
    end
    local entry = (resources.zones or {})[member.zone]
    if not entry then
      -- res.zones is generated, so a zone id it has never heard of means a
      -- game update. XIVParty indexes it unguarded and dies in the render loop.
      return "(?)"
    end
    -- The entry can exist without the field: `search` is a generated column and
    -- `name` resolves through the resource metatable, so neither is a promise.
    return "(" .. ((layout.row.zone.short and entry.search or entry.name) or "?") .. ")"
  end

  local function truncate(name, limit)
    if type(name) ~= "string" or not limit or #name <= limit then
      return name
    end
    return name:sub(1, limit)
  end

  local function job_name(job_id)
    local entry = job_id and (resources.jobs or {})[job_id]
    return entry and entry.ens or nil
  end

  -- The level a trust inherits: XIVParty copies the party leader's, and gives
  -- the subjob half of it. Only this list's own members are searched, so an
  -- alliance party's trust follows that party's leader.
  local function level_of(member, id)
    -- Your own job never arrives in a party packet, so it has to come from
    -- get_player(); solo-with-trusts is exactly the case where you are leader.
    if is_main_player(member) then
      return bag().player.main_job_level
    end
    local named = bag().named_jobs[id]
    if named then
      return named.level
    end
    local job = bag().jobs[id]
    return job and job.main_level or nil
  end

  local function party_leader_level()
    for slot = 1, MEMBERS_PER_PARTY do
      local member = bag().roster[slot]
      local id = member and member_id(member)
      if id and bag().roles[id] and bag().roles[id].leader then
        return level_of(member, id)
      end
    end
    -- 0x0C8 has not necessarily arrived by the time the first trust is called,
    -- and you are the one who called it.
    return bag().player and bag().player.main_job_level or nil
  end

  --[[ Where a member's job comes from, in the order the sources are reliable:

       - the player themselves, from get_player(), because no party packet
         carries the player's own job;
       - a trust, from its name and model id, because a trust reports no job in
         any packet at all;
       - everyone else, from 0x0DD / 0x0DF. ]]
  local function job_of(member)
    local named = bag().named_jobs[member_id(member)]
    if named then
      return named
    end

    if is_main_player(member) then
      local player = bag().player
      return {
        job = job_name(player.main_job_id),
        level = player.main_job_level,
        sub_job = job_name(player.sub_job_id),
        sub_level = player.sub_job_level,
      }
    end

    if member.mob and member.mob.is_npc then
      -- Cached: the lookup is a linear scan of 122 entries, and this runs for
      -- every trust in the party on every frame.
      local key = tostring(member.name) .. ":" .. tostring((member.mob.models or {})[1])
      local trust = trust_cache[key]
      if trust == nil then
        trust = job_table.trust_info(member.name, (member.mob.models or {})[1]) or false
        trust_cache[key] = trust
      end
      if trust then
        local level = party_leader_level()
        return {
          job = trust.job,
          level = level,
          sub_job = trust.sub_job,
          sub_level = level and math.max(1, math.floor(level / 2)) or nil,
        }
      end
    end

    local packet = bag().jobs[member_id(member)]
    if not packet then
      return {}
    end
    return {
      job = job_name(packet.main),
      level = packet.main_level,
      sub_job = job_name(packet.sub),
      sub_level = packet.sub_level,
    }
  end

  local function job_line(name, level)
    if not name then
      return ""
    end
    return level and (name .. " " .. tostring(level)) or name
  end

  --[[ Config files are hand-editable Lua, so `buffs` can be any shape at all --
       the defaults merge only fills a key that is *missing*. Callers index
       .priority and .filters, so a broken table degrades to an empty one and
       `usable` tells the command layer to say so rather than write into it. ]]
  local function buff_settings()
    local settings = config.buffs
    if type(settings) ~= "table" then
      -- A throwaway, deliberately not written back: whatever the user put
      -- there is theirs to fix, and `//xh reset` is how.
      return { priority = {}, filters = {}, filter_mode = "blacklist" }
    end
    if type(settings.priority) ~= "table" then
      settings.priority = {}
    end
    if type(settings.filters) ~= "table" then
      settings.filters = {}
    end
    if settings.filter_mode ~= "whitelist" then
      settings.filter_mode = "blacklist"
    end
    return settings
  end

  -- Whether writing to the buff settings would actually stick.
  local function buffs_usable()
    return type(config.buffs) == "table"
  end

  --[[ The effective order: the shipped list with the user's overrides lifted
       out and re-inserted at the rank each was given. Storing overrides as
       `id -> wanted rank` rather than as a whole reordered list is what lets a
       later change to the shipped order carry through instead of being stomped
       by a copy the user made months ago.

       Returns `id -> rank`; an id in neither the list nor the overrides has no
       rank and sorts last. ]]
  local function buff_order()
    if buff_ranks then
      return buff_ranks, buff_ordered
    end

    local overrides = buff_settings().priority or {}
    local moved = {}
    for id, rank in pairs(overrides) do
      if type(id) == "number" and type(rank) == "number" then
        moved[#moved + 1] = { id = id, rank = rank }
      end
    end
    -- Descending on the id, because each insert at a given rank displaces the
    -- previous occupant down one: inserting the higher id first leaves the
    -- lower one holding the contested rank.
    table.sort(moved, function(a, b)
      if a.rank ~= b.rank then
        return a.rank < b.rank
      end
      return a.id > b.id
    end)

    local is_moved = {}
    for _, entry in ipairs(moved) do
      is_moved[entry.id] = true
    end

    local order = {}
    for _, id in ipairs(shipped_buff_order) do
      if not is_moved[id] then
        order[#order + 1] = id
      end
    end
    for _, entry in ipairs(moved) do
      table.insert(order, math.max(1, math.min(entry.rank, #order + 1)), entry.id)
    end

    buff_ranks, buff_ordered = {}, order
    for rank, id in ipairs(order) do
      buff_ranks[id] = rank
    end
    return buff_ranks, buff_ordered
  end

  -- Never more than the layout has icon prims for: a hand-edited max_icons of
  -- 25 would otherwise have the commands promise fifteen icons that no slot
  -- exists to draw.
  local function icon_slots()
    local slots = 0
    for _, count in ipairs((layout.row.buff_icons or {}).icons_by_row or {}) do
      slots = slots + count
    end
    return slots
  end

  local function cap()
    return math.min(tonumber(buff_settings().max_icons) or 0, icon_slots())
  end

  local function filter_set()
    local settings = buff_settings()
    local set = {}
    for _, id in ipairs(settings.filters or {}) do
      set[id] = true
    end
    return set, settings.filter_mode == "whitelist"
  end

  -- The member's buffs, filtered, sorted by priority and cut to the cap.
  -- Unranked ids tie on rank, so the id breaks the tie and the icon order
  -- stays put between frames instead of flickering.
  local function buff_plan(member, outside_zone)
    if not layout.row.buff_icons then
      return nil
    end
    if outside_zone then
      return {}
    end

    local source = is_main_player(member) and bag().player.buffs or bag().buffs[member_id(member)]
    local blocked, whitelist = filter_set()
    local ids = {}
    for _, id in ipairs(source or {}) do
      -- 255 is the empty-slot marker in get_player().buffs.
      if id ~= 255 and (blocked[id] == true) == whitelist then
        ids[#ids + 1] = id
      end
    end

    local ranks = buff_order()
    table.sort(ids, function(a, b)
      local rank_a, rank_b = ranks[a] or math.huge, ranks[b] or math.huge
      if rank_a ~= rank_b then
        return rank_a < rank_b
      end
      return a < b
    end)

    local limit = cap()
    while #ids > limit do
      table.remove(ids)
    end
    return ids
  end

  local function range_plan(member, outside_zone, distance)
    if not layout.row.range then
      return nil
    end

    local settings = type(config.range) == "table" and config.range or {}
    local plan = { near = false, far = false, text = "" }
    if outside_zone then
      return plan
    end

    if settings.numeric == true then
      -- The distance to yourself is always zero; printing it is only noise.
      if not is_main_player(member) then
        plan.text = distance and string.format("%.2f", distance) or "?"
      end
      return plan
    end

    local near = tonumber(settings.near) or 0
    local far = tonumber(settings.far) or 0
    if distance then
      if near > 0 and distance <= near then
        plan.near = true
      elseif far > 0 and distance <= far then
        plan.far = true
      end
    end
    return plan
  end

  -- Full for the target, half for the subtarget, nothing otherwise. A member
  -- who is not in the zone cannot be the one you are pointing at.
  local function cursor_for(id, outside_zone)
    if outside_zone or id == nil then
      return 0
    end
    if id == bag().target then
      return 1
    end
    return id == bag().subtarget and 0.5 or 0
  end

  -- A slot's whole render plan. `occupied` decides whether the widget draws
  -- anything at all beyond the bars, which drain either way.
  local function row_plan(slot)
    local member = bag().roster[slot]
    local columns = layout.columns
    local spacing = tonumber(config.item_spacing) or 0
    local column = (slot - 1) % columns
    local line = math.floor((slot - 1) / columns)
    local plan = {
      slot = slot,
      offset_x = column * (layout.column_width + spacing),
      offset_y = line * (layout.row_height + spacing),
    }

    if not member then
      eased[slot].occupant = nil
      plan.occupied = false
      plan.bars = empty_bar_plans()
      return plan
    end

    local id = member_id(member)
    if eased[slot].occupant ~= id then
      eased[slot].occupant = id
      for _, key in ipairs(BARS) do
        eased[slot][key] = 0
        eased[slot].forced[key] = true
      end
    end

    local zone = bag().zone
    local outside_zone = member.zone ~= nil and zone ~= nil and member.zone ~= zone
    local distance = distance_of(member)
    local role = bag().roles[id] or {}

    plan.occupied = true
    plan.id = id
    -- A name that overruns its column is drawn straight over the next one, and
    -- the alliance column is 105px of 8pt text.
    plan.name = truncate(member.name, layout.row.name.max_chars)
    plan.outside_zone = outside_zone
    plan.zone_text = zone_text(member, outside_zone)
    plan.distance = distance
    plan.leader = {
      party = role.leader == true,
      alliance = role.alliance_leader == true,
      quartermaster = role.quartermaster == true,
    }
    plan.cursor = cursor_for(id, outside_zone)
    plan.range = range_plan(member, outside_zone, distance)
    plan.buffs = buff_plan(member, outside_zone)
    plan.bars = bar_plans(slot, vitals_of(member), outside_zone, distance)

    local job = outside_zone and {} or job_of(member)
    plan.job_icon = job.job
    plan.role = job.job and job_table.role_of(job.job) or nil
    plan.job_text = job_line(job.job, job.level)
    -- MON is what the subjob slot reads in monstrosity; it is not a subjob.
    plan.sub_job_text = job.sub_job ~= "MON" and job_line(job.sub_job, job.sub_level) or ""
    return plan
  end

  -- The render plan for this frame: one entry per list position, plus the
  -- sizing the widget needs to place them.
  function self.tick()
    local rows = {}
    local occupied = 0
    for slot = 1, MEMBERS_PER_PARTY do
      rows[slot] = row_plan(slot)
      if rows[slot].occupied then
        occupied = slot
      end
    end

    local spacing = tonumber(config.item_spacing) or 0
    -- show_empty_rows stretches the frame and nothing else -- no row art is
    -- drawn for a slot nobody is in. That is XIVParty's behaviour too: it
    -- feeds the flag into rowCount, which reaches contentHeight and the
    -- alignBottom offset, and creates list items only for real members.
    local shown = config.show_empty_rows == true and MEMBERS_PER_PARTY or math.max(occupied, 1)
    local function height_of(row_lines)
      return row_lines * layout.row_height + (row_lines - 1) * spacing
    end

    local lines = math.floor((shown - 1) / layout.columns) + 1
    local content_height = height_of(lines)

    --[[ alignBottom grows the list upward as members join. XIVParty shifts the
         whole list's origin to do it; here the box stays full height and the
         rows pack to the bottom of it, because the widget contract has
         get_bounds report the origin set_pos was given -- a shifted origin
         would have core clamp against a box the list is not in. ]]
    local box_height = content_height
    local shift = 0
    if config.align_bottom == true then
      box_height = height_of(math.floor((MEMBERS_PER_PARTY - 1) / layout.columns) + 1)
      shift = box_height - content_height
      for _, row in ipairs(rows) do
        row.offset_y = row.offset_y + shift
      end
    end

    return {
      rows = rows,
      row_count = shown,
      row_height = layout.row_height,
      width = layout.column_width * layout.columns,
      content_height = content_height,
      box_height = box_height,
      margin = layout.margin,
      -- How far down the box the rows start. The frame has to follow them
      -- there, or an aligned-to-the-bottom list draws in two pieces.
      content_offset_y = shift,
      -- XIVParty's hideSolo. The framework decides whether a component is on
      -- screen, and it knows about cutscenes and zoning, not party size, so
      -- this asks the widget to draw nothing rather than to be hidden.
      hidden = config.hide_solo == true and occupied <= 1,
    }
  end

  --[[ Commands ------------------------------------------------------------

       `//xh <name> ...`, parsed here so the widget only has to save and
       re-lay out. Answers are a list of lines, because the buff verbs exist to
       show you an order 621 entries long and one chat line cannot.

       Every verb that shows you buffs reaches past the icon cap on purpose: a
       buff you cannot see is a buff you cannot promote, and only the first ten
       are ever drawn. ]]

  local NAMES = { main = "partylist", alliance1 = "alliancelist1", alliance2 = "alliancelist2" }
  local NAME = NAMES[variant] or NAMES.main
  local PAGE_SIZE = 20
  local MAX_SEARCH_HITS = 20

  -- Deliberately stricter than tonumber, which also accepts "0x84" and "1e2".
  local function whole_number(word)
    if type(word) ~= "string" or not word:match("^%-?%d+$") then
      return nil
    end
    return tonumber(word)
  end

  local function has_buffs()
    return layout.row.buff_icons ~= nil
  end

  local function buff_name(id)
    local entry = (resources.buffs or {})[id]
    return entry and entry.en or ("buff " .. tostring(id))
  end

  local function verbs()
    local list = { "spacing", "align", "emptyrows", "range" }
    if variant == "main" then
      list[#list + 1] = "hidesolo"
      list[#list + 1] = "buff"
    end
    return table.concat(list, ", ")
  end

  local function status()
    local settings = type(config.range) == "table" and config.range or {}
    local lines = {
      ("%s: spacing %d, align %s, empty rows %s"):format(
        NAME,
        tonumber(config.item_spacing) or 0,
        config.align_bottom == true and "bottom" or "top",
        config.show_empty_rows == true and "on" or "off"
      ),
      ("  range %s, near %s, far %s"):format(
        settings.numeric == true and "numeric" or "icons",
        tonumber(settings.near) or 0,
        tonumber(settings.far) or 0
      ),
    }
    if variant == "main" then
      lines[#lines + 1] = ("  hide solo %s, buff icons %d, filter %s (%d)"):format(
        config.hide_solo == true and "on" or "off",
        tonumber(buff_settings().max_icons) or 0,
        buff_settings().filter_mode or "blacklist",
        #(buff_settings().filters or {})
      )
    end
    return lines
  end

  local function unknown(word)
    return { ("%s has no '%s' setting (%s)"):format(NAME, tostring(word), verbs()) }, false
  end

  local function set_spacing(word)
    local value = whole_number(word)
    if not value or value < 0 then
      return { ("//xh %s spacing needs a whole number of at least 0"):format(NAME) }, false
    end
    config.item_spacing = value
    return { ("%s row spacing set to %d"):format(NAME, value) }, true
  end

  local function set_align(word)
    local wanted = word and word:lower()
    if wanted ~= "top" and wanted ~= "bottom" then
      return { ("//xh %s align needs top or bottom"):format(NAME) }, false
    end
    config.align_bottom = wanted == "bottom"
    return { ("%s grows %s"):format(NAME, wanted == "bottom" and "upward from the bottom" or "downward") }, true
  end

  local function set_toggle(key, word, label)
    local wanted = word and word:lower()
    if wanted ~= "on" and wanted ~= "off" then
      return { ("//xh %s %s needs on or off"):format(NAME, label) }, false
    end
    config[key] = wanted == "on"
    return { ("%s %s %s"):format(NAME, label, wanted) }, true
  end

  local function set_range(args)
    -- Deliberately not written back until something is accepted: a rejected
    -- command must leave the configuration exactly as it found it.
    local settings = type(config.range) == "table" and config.range or {}
    local function keep()
      config.range = settings
    end

    local first = args[2] and args[2]:lower()
    if first == "num" or first == "numeric" then
      settings.numeric = true
      keep()
      return { NAME .. " range shows the numeric distance" }, true
    end
    if first == "icons" or first == "icon" then
      settings.numeric = false
      keep()
      return { NAME .. " range shows the indicator icons" }, true
    end

    local near, far = whole_number(args[2]), whole_number(args[3])
    if not near or not far or near < 0 or far < 0 then
      return { ("//xh %s range needs num, icons, or two distances (near far)"):format(NAME) }, false
    end
    if far > 0 and near > 0 and far < near then
      -- The far icon marks the wider ring, so a far distance inside the near
      -- one could never be reached.
      return { ("//xh %s range needs the far distance to be further than the near one"):format(NAME) }, false
    end
    settings.near, settings.far = near, far
    keep()
    return { ("%s range set to near %d, far %d"):format(NAME, near, far) }, true
  end

  --[[ Buff verbs ]]

  -- `<id|name>`: digits are an id, anything else is matched case-insensitively
  -- against res.buffs. Several buffs share a name -- sleep is both 2 and 19 --
  -- so an ambiguous name asks which rather than guessing.
  local function resolve_buff(text)
    if text == nil or text == "" then
      return nil, { ("//xh %s buff needs a buff id or name"):format(NAME) }
    end

    local id = whole_number(text)
    if id and id >= 0 then
      return id
    end

    local wanted = text:lower()
    local hits = {}
    for buff_id, entry in pairs(resources.buffs or {}) do
      if type(entry) == "table" and type(entry.en) == "string" and entry.en:lower() == wanted then
        hits[#hits + 1] = buff_id
      end
    end
    if #hits == 1 then
      return hits[1]
    end
    if #hits == 0 then
      return nil, { ("no buff called '%s' - try '//xh %s buff find %s'"):format(text, NAME, text) }
    end

    table.sort(hits)
    local ids = {}
    for index, buff_id in ipairs(hits) do
      ids[index] = tostring(buff_id)
    end
    return nil,
      {
        ("'%s' is the name of %d buffs - say which id:"):format(text, #hits),
        "  " .. table.concat(ids, ", "),
      }
  end

  -- Everything a listing can show: the ranked order first, then every buff the
  -- resources know that nothing has ranked. Nothing is silently left out.
  local function full_listing()
    local ranks, order = buff_order()
    local listing = {}
    for index, id in ipairs(order) do
      listing[index] = id
    end

    local unranked = {}
    for id in pairs(resources.buffs or {}) do
      if not ranks[id] then
        unranked[#unranked + 1] = id
      end
    end
    table.sort(unranked)

    local first_unranked = #listing + 1
    for _, id in ipairs(unranked) do
      listing[#listing + 1] = id
    end
    return listing, first_unranked
  end

  local function shown_slots()
    local _, order = buff_order()
    local lines = { ("%s draws the first %d of these:"):format(NAME, cap()) }
    for rank = 1, math.min(cap(), #order) do
      lines[#lines + 1] = ("  %2d. %s (%d)"):format(rank, buff_name(order[rank]), order[rank])
    end
    return lines, false
  end

  local function list_page(word)
    local listing, first_unranked = full_listing()
    local pages = math.max(1, math.ceil(#listing / PAGE_SIZE))
    local page = math.max(1, math.min(whole_number(word) or 1, pages))
    local first = (page - 1) * PAGE_SIZE + 1
    local last = math.min(first + PAGE_SIZE - 1, #listing)

    local lines = { ("%s buff order - page %d/%d"):format(NAME, page, pages) }
    for rank = first, last do
      if rank == first_unranked then
        lines[#lines + 1] = "  --- unranked below; these sort after everything above ---"
      end
      lines[#lines + 1] = ("  %3d. %s (%d)"):format(rank, buff_name(listing[rank]), listing[rank])
      if rank == cap() then
        lines[#lines + 1] = ("  --- cut: only the %d above are ever drawn ---"):format(cap())
      end
    end
    lines[#lines + 1] = ("  '//xh %s buff list <page>' for another page"):format(NAME)
    return lines, false
  end

  local function find_buffs(text)
    if text == "" then
      return { ("//xh %s buff find needs something to search for"):format(NAME) }, false
    end

    local ranks = buff_order()
    local wanted = text:lower()
    local hits = {}
    for id, entry in pairs(resources.buffs or {}) do
      if type(entry) == "table" and type(entry.en) == "string" and entry.en:lower():find(wanted, 1, true) then
        hits[#hits + 1] = { id = id, rank = ranks[id] }
      end
    end
    if #hits == 0 then
      return { ("no buff has '%s' in its name"):format(text) }, false
    end

    table.sort(hits, function(a, b)
      if (a.rank or math.huge) ~= (b.rank or math.huge) then
        return (a.rank or math.huge) < (b.rank or math.huge)
      end
      return a.id < b.id
    end)

    local lines = { ("buffs matching '%s':"):format(text) }
    for index = 1, math.min(#hits, MAX_SEARCH_HITS) do
      local hit = hits[index]
      lines[#lines + 1] = ("  rank %s  id %d  %s%s"):format(
        hit.rank and tostring(hit.rank) or "-",
        hit.id,
        buff_name(hit.id),
        (hit.rank and hit.rank <= cap()) and "  (drawn)" or ""
      )
    end
    if #hits > MAX_SEARCH_HITS then
      lines[#lines + 1] = ("  %d more - refine the search"):format(#hits - MAX_SEARCH_HITS)
    end
    return lines, false
  end

  -- The buffs a member has right now, all of them, past the icon cap. This is
  -- how you name a buff you just saw rather than one you can already name.
  local function active_buffs(who)
    local target, label = nil, nil
    if who == nil or who == "" then
      target = bag().player and bag().player.buffs or nil
      label = bag().player and bag().player.name or "you"
    else
      for slot = 1, MEMBERS_PER_PARTY do
        local candidate = bag().roster[slot]
        if candidate and candidate.name:lower() == who:lower() then
          label = candidate.name
          target = is_main_player(candidate) and (bag().player.buffs or {}) or bag().buffs[member_id(candidate)]
          break
        end
      end
      if not label then
        return { ("'%s' is not in this party list"):format(who) }, false
      end
    end

    if not target then
      -- 0x076 covers the main party only, so an alliance member's buffs are
      -- not something the client ever tells us.
      return { ("no buff data for %s"):format(label) }, false
    end

    local ranks = buff_order()
    local ids = {}
    for _, id in ipairs(target) do
      if id ~= 255 then
        ids[#ids + 1] = id
      end
    end
    if #ids == 0 then
      return { ("%s has no buffs"):format(label) }, false
    end

    table.sort(ids, function(a, b)
      if (ranks[a] or math.huge) ~= (ranks[b] or math.huge) then
        return (ranks[a] or math.huge) < (ranks[b] or math.huge)
      end
      return a < b
    end)

    local lines = { ("%s has %d buff(s):"):format(label, #ids) }
    for _, id in ipairs(ids) do
      lines[#lines + 1] = ("  rank %s  id %d  %s"):format(ranks[id] and tostring(ranks[id]) or "-", id, buff_name(id))
    end
    return lines, false
  end

  -- A rank past the end of the order is clamped by buff_order(), so storing and
  -- reporting the number the user typed would be two different lies.
  --[[ A rank past the end of the order is clamped, so storing and reporting
       the number the user typed would be two different lies.

       Any other override already at or below the wanted rank moves down one.
       Without that, two overrides claim the same rank and the id tie-break
       decides -- so `buff top` on one buff and then another would report a
       promotion that silently did not happen. ]]
  local function set_rank(id, rank)
    local _, order = buff_order()
    local landed = math.max(1, math.min(rank, #order))
    local overrides = buff_settings().priority

    for other, other_rank in pairs(overrides) do
      if other ~= id and other_rank >= landed then
        overrides[other] = other_rank + 1
      end
    end
    overrides[id] = landed

    self.invalidate_buff_order()
    return { ("%s moved to rank %d"):format(buff_name(id), landed) }, true
  end

  local function move_buff(verb, words)
    local id, complaint = resolve_buff(words)
    if not id then
      return complaint, false
    end

    if verb == "top" then
      return set_rank(id, 1)
    end

    local ranks, order = buff_order()
    -- An unranked buff sits notionally past the end, so "up" pulls it in.
    local rank = ranks[id] or (#order + 1)
    if verb == "up" then
      if rank <= 1 then
        return { ("%s is already at the top"):format(buff_name(id)) }, false
      end
      return set_rank(id, rank - 1)
    end
    if rank >= #order then
      return { ("%s is already at the bottom"):format(buff_name(id)) }, false
    end
    return set_rank(id, rank + 1)
  end

  local function rank_buff(args)
    local rank = whole_number(args[#args])
    if not rank or rank < 1 then
      return { ("//xh %s buff rank needs a buff and a rank of at least 1"):format(NAME) }, false
    end
    local words = table.concat(args, " ", 3, #args - 1)
    local id, complaint = resolve_buff(words)
    if not id then
      return complaint, false
    end
    return set_rank(id, rank)
  end

  local function filter_command(args)
    local settings = buff_settings()
    local action = args[3] and args[3]:lower() or "list"

    if action == "list" then
      if #settings.filters == 0 then
        return { ("%s filters nothing (%s mode)"):format(NAME, settings.filter_mode) }, false
      end
      local lines = { ("%s %s (%d):"):format(NAME, settings.filter_mode, #settings.filters) }
      for _, id in ipairs(settings.filters) do
        lines[#lines + 1] = ("  id %d  %s"):format(id, buff_name(id))
      end
      return lines, false
    end

    if action == "clear" then
      settings.filters = {}
      return { NAME .. " buff filters cleared" }, true
    end

    if action == "mode" then
      local mode = args[4] and args[4]:lower()
      if mode ~= "blacklist" and mode ~= "whitelist" then
        return { ("//xh %s buff filter mode needs blacklist or whitelist"):format(NAME) }, false
      end
      settings.filter_mode = mode
      return { ("%s buff filter is now a %s"):format(NAME, mode) }, true
    end

    if action == "add" or action == "remove" then
      local id, complaint = resolve_buff(table.concat(args, " ", 4))
      if not id then
        return complaint, false
      end
      for index, filtered in ipairs(settings.filters) do
        if filtered == id then
          if action == "add" then
            return { ("%s is already filtered"):format(buff_name(id)) }, false
          end
          table.remove(settings.filters, index)
          return { ("%s is no longer filtered"):format(buff_name(id)) }, true
        end
      end
      if action == "remove" then
        return { ("%s is not filtered"):format(buff_name(id)) }, false
      end
      settings.filters[#settings.filters + 1] = id
      return { ("%s is now filtered"):format(buff_name(id)) }, true
    end

    return { ("//xh %s buff filter takes add, remove, clear, list or mode"):format(NAME) }, false
  end

  local function buff_command(args)
    if not has_buffs() then
      return { ("%s has no buff icons - buffs are a %s setting"):format(NAME, NAMES.main) }, false
    end
    if not buffs_usable() then
      return { ("%s buff settings are not a table - try '//xh reset %s'"):format(NAME, NAME) }, false
    end

    local verb = args[2] and args[2]:lower() or nil
    if not verb then
      return shown_slots()
    end
    if verb == "list" then
      return list_page(args[3])
    end
    if verb == "find" then
      return find_buffs(table.concat(args, " ", 3))
    end
    if verb == "active" then
      return active_buffs(args[3])
    end
    if verb == "top" or verb == "up" or verb == "down" then
      return move_buff(verb, table.concat(args, " ", 3))
    end
    if verb == "rank" then
      return rank_buff(args)
    end
    if verb == "reset" then
      buff_settings().priority = {}
      self.invalidate_buff_order()
      return { NAME .. " buff order reset to the shipped one" }, true
    end
    if verb == "filter" then
      return filter_command(args)
    end
    return {
      ("//xh %s buff takes list, find, active, top, up, down, rank, reset or filter"):format(NAME),
    },
      false
  end

  -- Returns the lines to print and whether anything changed, so the widget
  -- knows when to re-lay out and save.
  function self.command(args)
    args = args or {}
    local verb = args[1] and args[1]:lower() or nil
    if not verb then
      return status(), false
    end
    if verb == "spacing" then
      return set_spacing(args[2])
    end
    if verb == "align" then
      return set_align(args[2])
    end
    if verb == "emptyrows" then
      return set_toggle("show_empty_rows", args[2], "emptyrows")
    end
    if verb == "hidesolo" and variant == "main" then
      return set_toggle("hide_solo", args[2], "hidesolo")
    end
    if verb == "range" then
      return set_range(args)
    end
    if verb == "buff" then
      return buff_command(args)
    end
    return unknown(args[1])
  end

  return self
end

return new
