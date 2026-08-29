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

--[[ Pure binding model: sets and views, the layer stack, and the cycle
     rotation. Bindings live in sets; per slot the topmost active layer with
     an entry wins:

       context layers   buff-conditioned, roster order -- later wins  (sparse)
       subjob layer     overrides for the current MAIN/SUB pair       (sparse)
       job base         the MAIN job's sets, shared by every subjob
                        -- OR the shared store, per the set's flag
                        (whole-set granularity; flipping the flag swaps
                        stores, the dormant contents stay on disk)

     Storage is injected: deps.load/deps.save move whole tables named by the
     main job ("SCH", ...) or "SHARED"; the file I/O lives outside. The
     component config (views, set_flags) arrives live through
     deps.get_config, so a flag flip shows on the next resolve. ]]

local roster = require("components/crossbar/contexts")

local SIDES = { l = "left", r = "right", left = "left", right = "right" }
local SET_COUNT = 8
local SLOT_COUNT = 8

local CONTEXT_NAMES = {}
for _, context in ipairs(roster) do
  CONTEXT_NAMES[context.name] = true
end

--[[ How deep a copy will go before it gives up on a branch. A `.lua`
     config file is code and a hand-written one can name itself, which makes
     an unbounded recursion here a stack overflow at login - taking every
     component after this one with it. The cap is far past anything the real
     shape reaches: the deepest legitimate path is
     contexts -> <name> -> <set> -> <side> -> <slot> -> the record, six
     levels, so sixteen leaves room for a shape nobody has thought of and
     still stops a cycle dead. ]]
local MAX_COPY_DEPTH = 16

--[[ A cycle is caught by IDENTITY, and the depth cap is only the belt. A
     table that names an ancestor of itself is refused outright, however
     wide it is: depth alone would let a root named by three of its own keys
     branch 3^16 ways before the cap bit, which is a hang at login rather
     than the overflow it was meant to prevent.

     `open` marks the path DOWN and unmarks on the way back up, so only a
     true ancestor counts: the same table reached twice by different routes
     is a shared branch, not a loop, and is copied both times.

     Either way the branch is dropped and its siblings survive, which is
     lib/settings' posture for a broken config throughout: degrade what is
     unreadable, keep what is not, and never throw where a handler cannot
     catch it. ]]
local function deep_copy(value, depth, open)
  if type(value) ~= "table" then
    return value
  end
  depth = (depth or 0) + 1
  if depth > MAX_COPY_DEPTH then
    return nil
  end
  open = open or {}
  if open[value] then
    return nil
  end
  open[value] = true
  local copy = {}
  for key, entry in pairs(value) do
    copy[key] = deep_copy(entry, depth, open)
  end
  open[value] = nil
  return copy
end

-- The data files are hand-edited during milestone verification and resolve
-- runs per frame, so a load degrades bad nodes to nothing instead of letting
-- a crash kill the handler: any node that should be a table but is not is
-- dropped; siblings survive intact (lib/settings' broken-config posture).
local function sanitize_sets(sets)
  if type(sets) ~= "table" then
    return {}
  end
  for set, sides in pairs(sets) do
    if type(sides) ~= "table" then
      sets[set] = nil
    else
      for side, slots in pairs(sides) do
        if type(slots) ~= "table" then
          sides[side] = nil
        else
          for slot, entry in pairs(slots) do
            if type(entry) ~= "table" then
              slots[slot] = nil
            end
          end
        end
      end
    end
  end
  return sets
end

-- sub and contexts: a map of name -> sets tree, each tree sanitized.
local function sanitize_tree_map(map)
  if type(map) ~= "table" then
    return {}
  end
  for key, tree in pairs(map) do
    if type(tree) ~= "table" then
      map[key] = nil
    else
      sanitize_sets(tree)
    end
  end
  return map
end

local function valid_set(set)
  return type(set) == "number" and set >= 1 and set <= SET_COUNT and set % 1 == 0
end

local function valid_slot(slot)
  return type(slot) == "number" and slot >= 1 and slot <= SLOT_COUNT and slot % 1 == 0
end

-- The set argument of bind/unbind, with its optional layer prefix: a number
-- (or numeric string) targets the base; "sub:<set>" the current subjob's
-- layer; "ctx:<name>:<set>" a context's overrides.
local function parse_address(set_arg)
  local layer, context, set = "base", nil, tonumber(set_arg)
  if set == nil and type(set_arg) == "string" then
    local sub_set = set_arg:match("^sub:(%d+)$")
    local ctx_name, ctx_set = set_arg:match("^ctx:([%w%-]+):(%d+)$")
    if sub_set then
      layer, set = "sub", tonumber(sub_set)
    elseif ctx_name then
      if not CONTEXT_NAMES[ctx_name] then
        return nil, "unknown context: " .. ctx_name
      end
      layer, context, set = "ctx", ctx_name, tonumber(ctx_set)
    else
      return nil, "unknown layer: " .. set_arg
    end
  end
  if not valid_set(set) then
    return nil, "no such set: " .. tostring(set_arg) .. " (1-" .. SET_COUNT .. ")"
  end
  return { layer = layer, context = context, set = set }
end

-- Walks (and builds) the nested set -> side tables down to the slot map.
local function slot_table(sets, set, side)
  sets[set] = sets[set] or {}
  sets[set][side] = sets[set][side] or {}
  return sets[set][side]
end

-- Reads without building -- a missing set or side answers nil.
local function slot_in(sets, set, side, slot)
  local entries = sets[set]
  local side_entries = entries and entries[side]
  return side_entries and side_entries[slot]
end

-- Writes a slot without leaving husks behind: a value materializes the
-- path, nil removes the entry and drops any side/set tables that emptied --
-- otherwise every swap and unbind would grow the file with empty
-- scaffolding that serializes forever.
local function write_slot(sets, set, side, slot, value)
  if value ~= nil then
    slot_table(sets, set, side)[slot] = value
    return
  end
  local entries = sets[set]
  local side_entries = entries and entries[side]
  if side_entries == nil then
    return
  end
  side_entries[slot] = nil
  if next(side_entries) == nil then
    entries[side] = nil
  end
  if next(entries) == nil then
    sets[set] = nil
  end
end

local function new(deps)
  local self = {}

  local job_name = nil
  local sub_name = nil
  local job_data = { active_set = 1, sets = {}, sub = {}, contexts = {} }
  local shared_data = { sets = {} }
  -- Active context names, re-synced from the full buff list only.
  local active = {}

  local function config()
    return deps.get_config()
  end

  -- The container nodes get the same treatment as their children:
  -- merge_defaults lets a user scalar win over a table default, so even
  -- `set_flags` or `views` themselves can arrive as garbage.
  local function config_table(key)
    local value = config()[key]
    if type(value) ~= "table" then
      return {}
    end
    return value
  end

  -- Config arrives live and hand-editable, so garbage degrades to defaults
  -- here per read: a truthy non-table entry is garbage (false stays a valid
  -- sentinel elsewhere; a missing entry already fell to the default).
  local function flags_for(set)
    local flags = config_table("set_flags")[set]
    if type(flags) ~= "table" then
      return { shared = false, cycle = { drawn = true, sheathed = true } }
    end
    return flags
  end

  -- The set's rotation membership: `false` keeps meaning "in no rotation"
  -- (the repo's false sentinel); nil or truthy garbage degrades to the
  -- all-weapons default, matching what merge_defaults would refill.
  local function cycle_flags(set)
    local cycle = flags_for(set).cycle
    if cycle == false then
      return {}
    end
    if type(cycle) ~= "table" then
      return { drawn = true, sheathed = true }
    end
    return cycle
  end

  local function is_shared(set)
    return flags_for(set).shared and true or false
  end

  -- The store a set's BASE reads and writes: the shared file for a shared
  -- set, the job file otherwise. A job set never touches SHARED.
  local function base_sets(set)
    if is_shared(set) then
      return shared_data.sets
    end
    return job_data.sets
  end

  local function save_job()
    deps.save(job_name, job_data)
  end

  -- Every store-writing verb refuses before set_job has named a job: the
  -- widget attaches before the client can name one, and a save then would
  -- write a file named nil.
  local function require_job()
    if job_name == nil then
      return nil, "no job loaded yet"
    end
    return true
  end

  -- Session-only, never persisted: sheathed on attach, job change and
  -- reload, self-correcting on the next engagement.
  local weapon = "sheathed"
  -- Defined below set_is_empty, declared here because set_job needs it.
  local land_on_first_set

  --- Scope to a main job (subjob may be nil): loads that job's file and the
  --- shared store. Everything job-scoped -- base, subjob overrides, context
  --- overrides, the active set -- comes from the main job's file alone.
  function self.set_job(main, sub)
    job_name = main
    sub_name = sub
    -- Copied by value, defaults filled in place: top-level keys this module
    -- does not know survive the load -> save round trip (the framework
    -- convention -- keys the defaults do not mention are preserved).
    -- Type-checked the way copy_from already checks what it loaded: a
    -- hand-broken store answering a string reached deep_copy intact and
    -- then an index, which is a crash at login rather than a bad config.
    local from_store = deps.load(main)
    local loaded = deep_copy(type(from_store) == "table" and from_store or {})
    local active_set = tonumber(loaded.active_set)
    if active_set == nil or active_set < 1 or active_set > SET_COUNT or active_set % 1 ~= 0 then
      active_set = 1
    end
    loaded.active_set = active_set
    loaded.sets = sanitize_sets(loaded.sets)
    loaded.sub = sanitize_tree_map(loaded.sub)
    loaded.contexts = sanitize_tree_map(loaded.contexts)
    job_data = loaded
    local from_shared = deps.load("SHARED")
    local shared = deep_copy(type(from_shared) == "table" and from_shared or {})
    shared.sets = sanitize_sets(shared.sets)
    shared_data = shared
    weapon = "sheathed"
    -- A job change strips buffs in game; until the next full-list re-sync
    -- arrives, the old job's contexts must not colour the new job's slots.
    active = {}
    --[[ The line above SHEATHES you without entering the state, so nothing
         reconciled the set the store just handed back: on a config whose
         low sets are drawn-only, a job change landed on a set the sheathed
         rotation does not contain (Kevin, 2026-08-29). Landing here means
         the stored active_set no longer decides where a job resumes - his
         call, made knowing that. ]]
    land_on_first_set()
  end

  --- Re-sync context activation from the AUTHORITATIVE buff list -- never
  --- from gain/lose deltas: using an Addendum fires a spurious arts
  --- `lose buff` while arts is still active, and only a full-list check
  --- against `any_of` (where the addendum ids imply their arts) survives it.
  --- Answers whether anything changed, the caller's no-rebuild short-circuit.
  function self.update_buffs(buffs)
    local up = {}
    for _, id in ipairs(buffs or {}) do
      up[id] = true
    end
    local next_active = {}
    local changed = false
    for _, context in ipairs(roster) do
      for _, id in ipairs(context.any_of) do
        if up[id] then
          next_active[context.name] = true
          break
        end
      end
      if (next_active[context.name] or false) ~= (active[context.name] or false) then
        changed = true
      end
    end
    if changed then
      active = next_active
    end
    return changed
  end

  --- The active context names, in roster (stack) order.
  function self.active_contexts()
    local names = {}
    for _, context in ipairs(roster) do
      if active[context.name] then
        names[#names + 1] = context.name
      end
    end
    return names
  end

  function self.weapon_state()
    return weapon
  end

  --[[ The set follows the weapon state (Kevin, 2026-08-24): entering a mode
       lands you on the FIRST set of it - the lowest-numbered non-empty one
       flagged for that rotation - rather than advancing from wherever you
       happened to be. The landing is then the same every time, which is
       what makes arranging a combat set worth doing.

       Only a real TRANSITION moves it. `on_status` fires on every engage,
       so re-entering a mode you are already in must leave the set alone or
       picking one by hand would be undone by the next mob. And a mode with
       no set to offer leaves it alone too: stranding the bar on nothing is
       worse than staying put. ]]
  -- Forward-declared: the landing needs `set_is_empty`, which the cycle
  -- below owns and which is defined with it.
  local enter_weapon_state

  --- The explicit flip -- the `draw` action's two-way transition.
  function self.set_weapon_state(state)
    enter_weapon_state(state)
  end

  --- The one-way game trigger: engaging by any means (status 1 or 3) enters
  --- drawn; a disengage the game forced (mob died, zoned) changes nothing --
  --- only an explicit `draw` returns to sheathed.
  function self.on_status(status)
    if status == 1 or status == 3 then
      enter_weapon_state("drawn")
    end
  end

  --- The winning entry for an address, and where it came from:
  --- "ctx:<name>", "sub", "shared" or "base". Nil for an empty stack.
  function self.resolve(set, side, slot)
    side = SIDES[side]
    if side == nil then
      return nil
    end
    for index = #roster, 1, -1 do
      local name = roster[index].name
      if active[name] then
        local entry = slot_in(job_data.contexts[name] or {}, set, side, slot)
        if entry then
          return entry, "ctx:" .. name
        end
      end
    end
    if sub_name then
      local entry = slot_in(job_data.sub[sub_name] or {}, set, side, slot)
      if entry then
        return entry, "sub"
      end
    end
    local entry = slot_in(base_sets(set), set, side, slot)
    if entry then
      return entry, is_shared(set) and "shared" or "base"
    end
    return nil
  end

  --- Every layer that HAS an entry at an address, in stack order (base
  --- first, then each subjob layer, then the contexts in roster order),
  --- tagged with its source and whether it is the one currently winning.
  --- This is the INSPECTION read: resolve() answers only the winner through
  --- the ACTIVE stack, so a listing built on it reports a stored-but-dormant
  --- layer -- an unbuffed context, another subjob's overrides -- as nothing
  --- at all. Subjob layers carry their own job name, since a file holds the
  --- layers of every subjob ever bound on it, not just the one worn.
  function self.layers_at(set, side, slot)
    local layers = {}
    if job_name == nil then
      return layers
    end
    side = SIDES[side]
    if side == nil then
      return layers
    end
    local base = slot_in(base_sets(set), set, side, slot)
    if base then
      layers[#layers + 1] = { source = is_shared(set) and "shared" or "base", entry = base }
    end
    -- Sorted: pairs order over the subjob map would shuffle the listing
    -- between calls for no reason.
    local subs = {}
    for name in pairs(job_data.sub) do
      subs[#subs + 1] = name
    end
    table.sort(subs)
    for _, name in ipairs(subs) do
      local entry = slot_in(job_data.sub[name], set, side, slot)
      if entry then
        layers[#layers + 1] = { source = "sub:" .. name, entry = entry, worn = name == sub_name }
      end
    end
    for _, context in ipairs(roster) do
      local entry = slot_in(job_data.contexts[context.name] or {}, set, side, slot)
      if entry then
        layers[#layers + 1] = { source = "ctx:" .. context.name, entry = entry, live = active[context.name] == true }
      end
    end
    -- The winner by the same rule resolve() applies: the topmost ACTIVE
    -- context, else the worn subjob's layer, else the base. Walking the
    -- list backwards finds it in one pass, since the list is already in
    -- stack order.
    for index = #layers, 1, -1 do
      local layer = layers[index]
      local eligible = layer.source == "base" or layer.source == "shared" or layer.worn == true or layer.live == true
      if eligible then
        layer.active = true
        break
      end
    end
    return layers
  end

  function self.active_set()
    return job_data.active_set
  end

  --- Jump reaches ANY set, empty and non-rotation ones included.
  function self.jump(set)
    local ok, err = require_job()
    if ok == nil then
      return nil, err
    end
    if type(set) ~= "number" or set < 1 or set > SET_COUNT or set % 1 ~= 0 then
      return nil, "no such set: " .. tostring(set) .. " (1-" .. SET_COUNT .. ")"
    end
    job_data.active_set = set
    save_job()
    return set
  end

  --- The configured (set, side) a WXHB / Expanded Hold view displays.
  function self.view_target(name)
    return config_table("views")[name]
  end

  -- "No registered actions" from the player's seat: a set is empty when no
  -- slot in it resolves through the full current stack -- so a set populated
  -- only by an active context counts, and stops counting when the buff drops.
  local function set_is_empty(set)
    for _, side in ipairs({ "left", "right" }) do
      for slot = 1, SLOT_COUNT do
        if self.resolve(set, side, slot) ~= nil then
          return false
        end
      end
    end
    return true
  end

  --- Lands the bar on the FIRST set of the weapon state now in force - the
  --- lowest-numbered non-empty one flagged for it. A set flagged for
  --- neither rotation is never landed on, and a state with nothing to
  --- offer leaves the set where it is: stranding the bar on nothing would
  --- be worse than staying.
  function land_on_first_set()
    if job_data == nil then
      return
    end
    for set = 1, SET_COUNT do
      if cycle_flags(set)[weapon] and not set_is_empty(set) then
        if set ~= job_data.active_set then
          job_data.active_set = set
          save_job()
        end
        return
      end
    end
  end

  function enter_weapon_state(state)
    if weapon == state then
      return
    end
    weapon = state
    land_on_first_set()
  end

  --- Advance to the next set that is non-empty AND flagged for the current
  --- weapon state's rotation. Wraps; when nothing qualifies it stays put and
  --- answers the unchanged active set (the no-op).
  function self.cycle()
    local ok, err = require_job()
    if ok == nil then
      return nil, err
    end
    local from = job_data.active_set
    for step = 1, SET_COUNT do
      local set = (from + step - 1) % SET_COUNT + 1
      if cycle_flags(set)[weapon] and not set_is_empty(set) then
        if set ~= from then
          job_data.active_set = set
          save_job()
        end
        return set
      end
    end
    return from
  end

  -- The one write path: resolves the addressed layer to its sets root plus
  -- the save that persists it. Nothing is materialized here -- bind builds
  -- the path only when it writes a value, and an unbind of a layer whose
  -- root does not exist finds `sets` nil and has nothing to do. Writes can
  -- only ever reach the current job's file or SHARED -- another job's file
  -- has no handle here.
  local function write_target(set_arg, side, slot)
    local address, err = parse_address(set_arg)
    if address == nil then
      return nil, err
    end
    side = SIDES[side]
    if side == nil then
      return nil, "side must be l or r"
    end
    if not valid_slot(slot) then
      return nil, "no such slot: " .. tostring(slot) .. " (1-" .. SLOT_COUNT .. ")"
    end
    local target = { set = address.set, side = side, slot = slot, save = save_job }
    if address.layer == "sub" then
      if sub_name == nil then
        return nil, "no subjob to target"
      end
      target.sets = job_data.sub[sub_name]
      target.materialize = function()
        job_data.sub[sub_name] = job_data.sub[sub_name] or {}
        return job_data.sub[sub_name]
      end
      target.prune_root = function()
        if job_data.sub[sub_name] ~= nil and next(job_data.sub[sub_name]) == nil then
          job_data.sub[sub_name] = nil
        end
      end
    elseif address.layer == "ctx" then
      target.sets = job_data.contexts[address.context]
      target.materialize = function()
        job_data.contexts[address.context] = job_data.contexts[address.context] or {}
        return job_data.contexts[address.context]
      end
      target.prune_root = function()
        if job_data.contexts[address.context] ~= nil and next(job_data.contexts[address.context]) == nil then
          job_data.contexts[address.context] = nil
        end
      end
    elseif is_shared(address.set) then
      target.sets = shared_data.sets
      target.save = function()
        deps.save("SHARED", shared_data)
      end
    else
      target.sets = job_data.sets
    end
    return target
  end

  --- Whether a set's base lives in the SHARED store rather than this job's
  --- file. The binder labels and addresses its base row from this: an empty
  --- shared set holds no layer to infer it from.
  function self.shared(set)
    return is_shared(set)
  end

  --- The scope: the main job and subjob currently loaded, or nothing at all
  --- before set_job has named one.
  function self.job()
    return job_name, sub_name
  end

  --- The entry the ADDRESSED layer holds, or nil -- the read half of
  --- bind/unbind, for the CLI's alias and icon overrides, which edit one
  --- layer's own entry rather than whatever the stack resolves to. Reads
  --- through write_target, so it materializes nothing and rejects a bad
  --- address with the same hints the writes give.
  function self.entry_at(set_arg, side, slot)
    local ok, err = require_job()
    if ok == nil then
      return nil, err
    end
    local target, target_err = write_target(set_arg, side, slot)
    if target == nil then
      return nil, target_err
    end
    if target.sets == nil then
      return nil
    end
    return slot_in(target.sets, target.set, target.side, target.slot)
  end

  --- Bind an action record at an address; persists immediately into the
  --- store the addressed layer lives in.
  function self.bind(set_arg, side, slot, entry)
    local ok, err = require_job()
    if ok == nil then
      return nil, err
    end
    local target, target_err = write_target(set_arg, side, slot)
    if target == nil then
      return nil, target_err
    end
    local sets = target.sets or target.materialize()
    write_slot(sets, target.set, target.side, target.slot, entry)
    target.save()
    return true
  end

  --- Remove an address's entry in the addressed layer only. Never creates
  --- anything: an already-empty address is a persisted no-op.
  function self.unbind(set_arg, side, slot)
    local ok, err = require_job()
    if ok == nil then
      return nil, err
    end
    local target, target_err = write_target(set_arg, side, slot)
    if target == nil then
      return nil, target_err
    end
    if target.sets ~= nil then
      write_slot(target.sets, target.set, target.side, target.slot, nil)
      if target.prune_root then
        target.prune_root()
      end
    end
    target.save()
    return true
  end

  --- Exchange two addresses' ENTIRE stacks: the bases (each in the store its
  --- set's flag selects), every subjob override and every context override.
  --- No layer prefix applies; a move is a swap with an empty stack.
  function self.swap(a, b)
    local ok, err = require_job()
    if ok == nil then
      return nil, err
    end
    local a_side, b_side = SIDES[a.side], SIDES[b.side]
    if
      not (valid_set(a.set) and valid_set(b.set) and a_side and b_side and valid_slot(a.slot) and valid_slot(b.slot))
    then
      return nil, "swap needs two addresses as <set> <l|r> <slot>"
    end
    --[[ A slot swapped with itself is not a change, and the point of
         saying so here is the DISK WRITE: without this the exchange below
         reads and re-writes the same value at every layer and then saves
         the job file for nothing. The behaviour is identical either way,
         which is exactly why this reads as redundant and has been deleted
         once already - the save counter in the spec is what pins it. ]]
    if a.set == b.set and a_side == b_side and a.slot == b.slot then
      return true
    end

    -- Reads both values first (the two addresses may share tables), touches
    -- nothing when a layer has neither, and writes through write_slot so an
    -- emptied side leaves no husk behind.
    local function exchange(a_sets, b_sets)
      local value_a = slot_in(a_sets, a.set, a_side, a.slot)
      local value_b = slot_in(b_sets, b.set, b_side, b.slot)
      if value_a == nil and value_b == nil then
        return
      end
      write_slot(a_sets, a.set, a_side, a.slot, value_b)
      write_slot(b_sets, b.set, b_side, b.slot, value_a)
    end

    exchange(base_sets(a.set), base_sets(b.set))
    for _, overrides in pairs(job_data.sub) do
      exchange(overrides, overrides)
    end
    for _, overrides in pairs(job_data.contexts) do
      exchange(overrides, overrides)
    end

    save_job()
    if is_shared(a.set) or is_shared(b.set) then
      deps.save("SHARED", shared_data)
    end
    return true
  end

  --- Seed this job's bindings from another job's file: base, subjob layers
  --- and context overrides, copied by value (shared sets are already
  --- everywhere). The active set stays this job's own.
  function self.copy_from(job)
    local ok, err = require_job()
    if ok == nil then
      return nil, err
    end
    local loaded = deps.load(job)
    if type(loaded) ~= "table" then
      return nil, "no bindings for job: " .. tostring(job)
    end
    -- Same sanitizing load path as set_job: a hand-broken source must not
    -- become a per-frame crash here. active_set is not copied, so it needs
    -- no coercion.
    job_data.sets = sanitize_sets(deep_copy(loaded.sets))
    job_data.sub = sanitize_tree_map(deep_copy(loaded.sub))
    job_data.contexts = sanitize_tree_map(deep_copy(loaded.contexts))
    save_job()
    return true
  end

  return self
end

return new
