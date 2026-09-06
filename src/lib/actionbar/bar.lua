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

--[[ The widget-independent state of ONE action bar, shared by the crossbar
     and the hotbar so the two cannot drift: its bindings over its own store
     and geometry, its job scoping, its buff-context sync, the weapon layer,
     the item counts a slot's corner draws, the resource facts a record
     resolves to, the press path into the action service, the binder
     session and the authoring CLI. A widget keeps what is its own - prims,
     geometry, input and the framework contract - and reaches everything
     else through here.

     Deps: `name`, `grammar` (lib/actionbar/grammar), `views` (the
     crossbar's view verbs, false for a bar without them), `ctx` (the
     widget's, `ctx.actions` included), `config()` (the live config table),
     `save()` (the live saver, a no-op while detached), `render()` (the
     widget's live geometry render, which the binder hit-tests through),
     `groups()` (the drawn groups the binder resolves a click over),
     `cells(visit)` (walks every slot object, for the ids they are bound
     to), `repaint()`, `visible()` (the widget's own switch, for edit mode's
     refusal), `on_edit(open)` (the widget's own edit-mode housekeeping) and
     an optional `status()` (the bare command's lines, when the widget has
     more to say than the head line here). ]]

local new_bindings = require("lib/actionbar/bindings")
local new_commands = require("lib/actionbar/commands")
local new_catalog = require("lib/actionbar/catalog")
local new_binder = require("lib/actionbar/binder")
local new_weapon = require("lib/actionbar/weapon")
local counters = require("lib/actionbar/counters")
local openers = require("lib/actionbar/openers")
local grammars = require("lib/actionbar/grammar")
local new_icon_cache = require("lib/icon_cache")

-- The tool-count colour bands, upstream's own RGB (ui.lua:963-967).
local TOOL_COLORS = {
  green = { 0, 255, 0 },
  yellow = { 255, 255, 0 },
  red = { 255, 0, 0 },
}
-- Item counts and stratagem charges draw in plain white: no bands, since
-- neither is a ninja-tool fact.
local PLAIN_COUNT_COLOR = { 255, 255, 255 }

-- How long a job-change gate keeps the per-frame get_player retry alive
-- before standing down (parambar's login-retry precedent): a stale or
-- dying announcement must not poll forever. The next job change event
-- re-arms it.
local RESCOPE_DEADLINE_SECONDS = 10

--[[ The two target tokens the weaponskill gate may look up a mob for - the
     pair this repo has read `get_mob_by_target` for, exactly as the service's
     retry pin is scoped. ]]
local PINNED_TARGETS = { t = true, bt = true }

local RESOURCE_TABLES = {
  ma = "spells",
  ja = "job_abilities",
  pet = "job_abilities",
  ws = "weapon_skills",
  item = "items",
  enchanteditem = "items",
  mount = "mounts",
}

local function new(deps)
  local self = {}

  local name = deps.name or "crossbar"
  local grammar = deps.grammar or grammars.crossbar()
  local ctx = deps.ctx
  local service = assert(ctx.actions, name .. " needs ctx.actions, the action service")
  local resources = ctx.resources
  local roulette = service.roulette
  local skillchain = service.skillchain
  local actions = service.actions
  local icon_for = actions.icon_for

  local function config()
    return deps.config()
  end

  local function say(lines)
    if ctx.say ~= nil and lines ~= nil then
      ctx.say(lines)
    end
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

  local function read_bag(bag)
    if ctx.get_items ~= nil then
      return ctx.get_items(bag)
    end
    return nil
  end

  local function draw_state()
    return service.draw_state()
  end
  self.draw_state = draw_state
  self.icon_for = icon_for

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
       the bar carries on. ]]
  local weapon_layer = nil
  if resources ~= nil then
    weapon_layer = new_weapon({
      get_equipment = ctx.get_equipment,
      get_items = ctx.get_items,
      resources = resources,
    })
  end

  --[[ The item-icon extraction pipeline (lib/icon_cache): built only when
       the ctx carries the file surface; a config-level game_path override
       wins over the client's own answer, equipviewer's convention. A
       SEPARATE instance per bar: the on-disk cache under <addon>/icons/ is
       shared, the queues are not. ]]
  local icon_cache = nil
  if ctx.file_exists ~= nil and ctx.read_dat ~= nil and ctx.write_binary ~= nil and ctx.asset ~= nil then
    icon_cache = new_icon_cache({
      asset = ctx.asset,
      file_exists = ctx.file_exists,
      read_dat = ctx.read_dat,
      write_binary = ctx.write_binary,
      game_path = function()
        local live = config()
        if type(live.game_path) == "string" and live.game_path ~= "" then
          return live.game_path
        end
        return ctx.game_path ~= nil and ctx.game_path() or nil
      end,
    })
  end

  --[[ Resource name lookups, indexed lazily by lowercased English name; the
       items table alone is tens of thousands of entries, so nothing walks it
       until something actually needs it. ]]
  local name_indexes = {}
  local function resource_by_name(table_name, key)
    if resources == nil or type(key) ~= "string" then
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
    return index[key:lower()]
  end

  local function display_category(resource_type)
    if type(resource_type) ~= "string" then
      return nil
    end
    return (resource_type:gsub("(%l)(%u)", "%1 %2"))
  end

  --[[ What a record resolves to in the resources: the facts a slot draws
       and a press is gated on - recast id, costs, the display category the
       icon pack is keyed by, the weapon class of a weaponskill, an item's
       id. The SP job suffix takes the player's main job id - the owning job
       coincides for your own SP; a shared set viewed cross-job may draw the
       viewing job's art (accepted, same as binding it fresh). ]]
  function self.meta_for(record)
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
      local item = resource_by_name("items", record.action)
      if item ~= nil then
        return { kind = "item", item_id = item.id }
      end
    end
    return nil
  end
  local meta_for = self.meta_for

  --[[ The binding model, over the bar's own store and geometry. Rebuilt on
       every attach and detach: a detach hands it a store that answers
       nothing, so nothing of the character who left survives. ]]
  local function build_bindings(store)
    local function nothing() end
    return new_bindings({
      geometry = grammar,
      load = store ~= nil and store.load or nothing,
      save = store ~= nil and store.save or nothing,
      get_config = config,
    })
  end
  local bindings = build_bindings(nil)

  function self.bindings()
    return bindings
  end

  --[[ The authoring CLI. Reads the model through a getter, since attach and
       detach rebuild it, and validates an icon name against the same two
       candidates render.icon_candidates draws from - the player's own art
       first, then the shipped pack. ]]
  local authoring = new_commands({
    name = name,
    grammar = grammar,
    views = deps.views,
    help_extra = deps.help_extra,
    bindings = function()
      return bindings
    end,
    get_config = config,
    file_exists = file_exists,
    validate = actions.validate,
    action_exists = function(kind, action)
      local table_name = RESOURCE_TABLES[kind]
      if resources == nil or table_name == nil then
        -- Nothing to check against: the CLI keeps the user's reading and
        -- says so, rather than guessing.
        return nil
      end
      return resource_by_name(table_name, action) ~= nil
    end,
  })
  self.authoring = authoring
  --[[ A built-in that shares a word with an authoring verb would be
       unreachable from the console. It could only ever fire on a code
       change, so it is said to chat rather than thrown - an error here
       would take the whole bar down over a naming slip, and the addon's
       posture is that a load failure must stay diagnosable. ]]
  local collisions = actions.check_collisions(authoring.verbs())
  if #collisions > 0 then
    say(name .. ": built-in action name(s) shadow an authoring verb: " .. table.concat(collisions, ", "))
  end

  --[[ Job scoping ---------------------------------------------------------
       nil until the client can name a main job; a `job change` notes the
       ids it announced so a stale get_player() is not rescoped. ]]
  local scoped_main = nil
  local scoped_sub = nil
  local rescope_want = nil

  function self.scoped()
    return scoped_main, scoped_sub
  end

  --[[ Buffs ---------------------------------------------------------------
       The ONE writer of the model's buff state. While the binder previews a
       context, the simulated list owns it outright and live buff events are
       dropped rather than queued - the alternative, letting both write,
       reverts the previewed bar under a header still claiming the simulated
       view. The handover (preview(nil)) re-reads the client here, so nothing
       stale can survive the preview coming down. ]]
  local previewing = nil

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
  self.apply_buffs = apply_buffs

  function self.sync_buffs()
    if apply_buffs() then
      deps.repaint()
    end
  end

  --[[ Item counts ---------------------------------------------------------
       What every consumable a slot is bound to counts from the inventory,
       plus enchanted gear from the other equippable bags. Re-read when an
       item event names an id something is bound to (giltracker's pattern),
       and when a repaint changes WHICH ids those are. ]]
  local item_counts = {}
  local gear_counts = {}
  local temporary_seen = false
  local counts_dirty = true
  local counted_signature = nil
  --[[ The class in the main hand is a whole-inventory call, so it is asked
       only when a packet or a rescope says the gear may have moved - never
       per frame. It starts DOWN, unlike `counts_dirty`: every attach clears
       the scope, so the first tick of any attach goes through try_scope,
       which arms it there. ]]
  local weapon_dirty = false

  local binder = nil
  local function editing()
    return binder ~= nil and binder.active()
  end
  self.editing = editing

  --[[ The item ids some painted slot is bound to, so a consumable's count
       is read for the same reason a ninja tool's is. Three sets, not two:
       `plain` and `gear` are tracked separately rather than "gear, and
       everything else", because ONE id can be bound both ways on the same
       bar. Walked on demand rather than cached: it is a few dozen lookups,
       only an item event and a recount ask for it, and a cache would be
       one more thing to invalidate on every bind, set switch, context flip
       and job change. ]]
  local function bound_item_ids()
    local wanted, gear, plain = {}, {}, {}
    deps.cells(function(cell)
      local meta, record = cell.meta(), cell.record()
      if meta ~= nil and meta.item_id ~= nil then
        wanted[meta.item_id] = true
        if record ~= nil and record.type == "enchanteditem" then
          gear[meta.item_id] = true
        else
          plain[meta.item_id] = true
        end
      end
    end)
    return wanted, gear, plain
  end

  --[[ Those same ids as one comparable string, for the repaint check. Each
       id carries the KINDS bound to it, so unbinding one half of an id
       bound both ways still changes the signature. ]]
  local function bound_item_signature()
    local _, gear, plain = bound_item_ids()
    local parts = {}
    for id in pairs(gear) do
      parts[#parts + 1] = id .. "g"
    end
    for id in pairs(plain) do
      parts[#parts + 1] = id .. "i"
    end
    table.sort(parts)
    return table.concat(parts, ",")
  end

  --[[ A repaint is the only thing that can change WHICH ids need counting,
       but most repaints do not change them at all, and marking the counts
       dirty on every one would re-read the inventory (and, with gear bound,
       every wardrobe) on each hold state and set switch. So the set is
       recomputed and compared. ]]
  function self.check_bound_items()
    local signature = bound_item_signature()
    if signature ~= counted_signature then
      counted_signature = signature
      counts_dirty = true
    end
  end

  function self.mark_counts_dirty()
    counts_dirty = true
  end

  -- An item entering or leaving a bag: worth a recount only when something
  -- painted is bound to it, or a tool count could read it.
  function self.on_item_event(id)
    if counters.tracked_item(id) or bound_item_ids()[id] then
      counts_dirty = true
    end
  end

  --[[ Whether any painted slot draws a number the bag feeds - a bound item
       or piece of gear, or a spell/ability whose school spends a tool. The
       inventory packet names no id, so this is the only gate available to
       it, and it is deliberately coarser than the events'. ]]
  function self.counts_from_inventory()
    local found = false
    deps.cells(function(cell)
      if found then
        return
      end
      local meta, record = cell.meta(), cell.record()
      if meta ~= nil and meta.item_id ~= nil then
        found = true
      elseif meta ~= nil and meta.spell_id ~= nil and counters.tool_for_spell(meta.spell_id) ~= nil then
        found = true
      elseif record ~= nil and record.type == "ja" and counters.tool_for_ability(record.action) ~= nil then
        found = true
      end
    end)
    return found
  end

  function self.mark_weapon_dirty()
    weapon_dirty = true
  end

  --[[ The class in the main hand, into the binding model. Only when
       something said it may have moved, and an unreadable client leaves the
       flag up rather than clearing the layer: an empty bag is the ordinary
       state for the first seconds of a login. The class arriving can move
       the active set - the landing set_job made could not see this layer -
       so an open binder is deselected exactly as try_scope does it. ]]
  local function refresh_weapon()
    if not weapon_dirty or weapon_layer == nil then
      return
    end
    local class, known = weapon_layer.resolve()
    if not known then
      return
    end
    weapon_dirty = false
    if class == bindings.weapon_type() then
      return
    end
    local set_before = bindings.active_set()
    bindings.set_weapon_type(class)
    if editing() and set_before ~= bindings.active_set() then
      binder.deselect()
    end
    deps.repaint()
  end

  local function recount_items()
    counts_dirty = false
    --[[ TWO tallies, because the two bindings do not count the same thing:
         `item_counts` is what the inventory holds (tools and consumables -
         the only bag `/item` can reach) and `gear_counts` what every
         reachable equippable bag holds. ]]
    item_counts = {}
    gear_counts = {}
    --[[ Whether a temporary bag was actually found and read this pass. When
         it was not, a plain item's zero might simply be a copy we could not
         see - the bag is matched on a resource name nothing here has read -
         so the corner shows the number and withholds the red X. ]]
    temporary_seen = false
    local wanted, gear, plain = bound_item_ids()

    local function tally(into, bag, matches)
      for _, item in ipairs(bag or {}) do
        if type(item) == "table" and item.id ~= nil and item.id ~= 0 and matches(item.id) then
          into[item.id] = (into[item.id] or 0) + (item.count or 0)
        end
      end
    end

    local function usable_from_here(id)
      return counters.tracked_item(id) or wanted[id] == true
    end
    -- An ABSENT enabled flag reads as reachable, and only an explicit
    -- `false` excludes: "I did not say" is not the same answer as "no".
    local inventory = read_bag(0)
    local inventory_reachable = type(inventory) == "table" and inventory.enabled ~= false
    if inventory_reachable then
      tally(item_counts, inventory, usable_from_here)
    end
    local wants_temporary = next(plain) ~= nil
    if next(gear) ~= nil and inventory_reachable then
      tally(gear_counts, inventory, function(id)
        return gear[id] == true
      end)
    end
    for bag_id, bag in pairs(equip_bags) do
      -- A CONTAINS match, not equality: "Temporary Items" is as plausible a
      -- spelling as "Temporary", and a miss would cross out a press that
      -- works.
      local bag_name = type(bag.name) == "string" and bag.name:lower() or ""
      if bag_id ~= 0 and bag_name:find("temporary", 1, true) ~= nil then
        temporary_seen = true
      end
      if wants_temporary and bag_id ~= 0 and bag_name:find("temporary", 1, true) ~= nil then
        local temporary = read_bag(bag_id)
        if type(temporary) == "table" and temporary.enabled ~= false then
          -- Bound items only, and never a ninja tool: `item_counts` is the
          -- same table the tool counter reads, so folding a temporary-bag
          -- copy in would clear a red X that is telling the truth.
          tally(item_counts, temporary, function(id)
            return plain[id] == true and not counters.tracked_item(id)
          end)
        end
      end
    end
    -- Gear is different: enchanteditem searches every equippable bag, so a
    -- count that stopped at the inventory would cross out a slot whose
    -- press works perfectly. Bag 0 was tallied above.
    if next(gear) ~= nil then
      for bag_id, bag in pairs(equip_bags) do
        if bag_id ~= 0 and bag.equippable then
          local held = read_bag(bag_id)
          if type(held) == "table" and held.enabled ~= false then
            tally(gear_counts, held, function(id)
              return gear[id] == true
            end)
          end
        end
      end
    end
  end

  function self.recount_if_dirty()
    if counts_dirty then
      recount_items()
    end
  end

  local function has_job(player, job)
    return player ~= nil and (player.main_job == job or player.sub_job == job)
  end

  --[[ The count drawn in a slot's cost corner, when the action carries
       one: SCH stratagem charges, NIN/COR tool counts, or how many of an
       item the slot names are carried. At most one of the three can apply. ]]
  function self.counter_for(record, meta, player, ability_recasts)
    if record.type == "ja" and counters.stratagem_ability(record.action) then
      local charges = counters.stratagems(player, ability_recasts[231] or 0)
      if charges ~= nil then
        return { text = tostring(charges.available), color = PLAIN_COUNT_COLOR }
      end
      return nil
    end
    --[[ A plain item binding counts what it names: no master substitutes
         and no job gate, both of which are tool facts rather than item
         ones. Enchanted gear counts the same way - COPIES, not charges, so
         a spent ring still reads "1". ]]
    if (record.type == "item" or record.type == "enchanteditem") and meta ~= nil and meta.item_id ~= nil then
      local counts = record.type == "enchanteditem" and gear_counts or item_counts
      local display = counters.item_display(meta.item_id, counts)
      -- The zero flag raises the red X, so it is only set where the zero is
      -- TRUSTWORTHY: gear is never temporary, so its zero always stands.
      local trustworthy = record.type == "enchanteditem" or temporary_seen
      return {
        text = display.text,
        color = PLAIN_COUNT_COLOR,
        zero = display.zero and trustworthy,
      }
    end
    -- The fork's own gates: tool counts draw only while the owning school's
    -- job is somewhere on the pair.
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

  --[[ Client reads ride lib/player's read counter, not a clock of our own:
       a second throttle would sit out of phase and leave these answers up
       to two intervals stale. The recasts have no service behind them, but
       want the same cadence, so they ride the counter too. An absent
       counter reads every frame - costly, unreachable in a client, but a
       wiring slip must degrade rather than freeze. ]]
  local reads = nil
  local last_read_generation = nil

  function self.reads()
    return reads
  end

  function self.refresh_reads(generation)
    if reads ~= nil and generation ~= nil and generation == last_read_generation then
      return
    end
    last_read_generation = generation
    refresh_weapon()
    reads = {
      player = get_player(),
      spell_recasts = ctx.get_spell_recasts ~= nil and ctx.get_spell_recasts() or {},
      ability_recasts = ctx.get_ability_recasts ~= nil and ctx.get_ability_recasts() or {},
    }
    -- The binder's details column reads its recast from these, so it is
    -- rebuilt on the same cadence rather than per frame - and only in edit
    -- mode, the only place anything describes an action.
    if editing() then
      binder.refresh_details()
    end
  end

  -- An icon landing on disk: only unresolved item slots can care, and the
  -- widget repaints those.
  function self.drain_icons()
    return icon_cache ~= nil and icon_cache.drain_queue()
  end

  --[[ Whether the shared cache has the item's art, asking it to extract
       what it has not: queued, never extracted here - one icon per frame,
       off the hot path. The slot draws its fallback meanwhile and is
       repainted when the extraction lands - unless the cache has given up
       on the item, which only a detach (reset) forgives. ]]
  function self.item_icon(item_id)
    if icon_cache == nil or icon_cache.cached_icon(item_id) ~= nil or icon_cache.is_abandoned(item_id) then
      return nil
    end
    icon_cache.request_icon(item_id)
    return "awaiting"
  end

  -- The first existing candidate wins; without a file surface nothing can
  -- be verified, so nothing draws.
  function self.pick_icon(record, meta, state)
    for _, candidate in ipairs(deps.render().icon_candidates(record, meta, state)) do
      if file_exists(candidate.path) then
        return candidate
      end
    end
    return nil
  end

  --[[ The press -----------------------------------------------------------
       Which mob the gate may look up for a press, or nil for "do not look":
       the PINNED PAIR and nothing else. A weaponskill bound to <st>, <p3>
       or a scan cannot be resolved here, and reading <t> in its place would
       refuse a press on a mob it never aimed at. A record with no token at
       all aims at the current target, which IS <t>. ]]
  local function gate_token(record)
    local token = record.target
    if token == nil then
      return "t"
    end
    token = type(token) == "string" and token:lower() or nil
    return token ~= nil and PINNED_TARGETS[token] and token or nil
  end

  --[[ What the weaponskill gate needs, for a weaponskill alone: every other
       type would pay a resource lookup and up to two mob reads for facts
       nothing downstream consults. The mob read is memoized for the frame
       by the player service. ]]
  local function gate_facts(record)
    if record.type ~= "ws" then
      return nil
    end
    local player = get_player()
    local vitals = player ~= nil and player.vitals or nil
    local meta = meta_for(record)
    local token = ctx.get_mob_by_target ~= nil and gate_token(record) or nil
    local target = token ~= nil and ctx.get_mob_by_target(token) or nil
    return {
      tp = vitals ~= nil and vitals.tp or nil,
      status = player ~= nil and player.status or nil,
      buffs = player ~= nil and player.buffs or nil,
      skill = meta ~= nil and meta.weapon or nil,
      distance_squared = target ~= nil and target.distance or nil,
      model_size = target ~= nil and target.model_size or nil,
    }
  end

  --[[ The cast retry's guards, answered for the record it is about to
       re-send: whether this very slot still holds it (identity, not
       contents), its recast, its affordability and the player's buffs. Read
       live rather than off the tick's snapshot: the service steps the
       retry BEFORE this bar's tick refreshes that snapshot, and the probe
       runs only when a re-send is otherwise due. ]]
  local function retry_facts_at(entry, set, side, slot)
    if bindings.resolve(set, side, slot) ~= entry.record then
      return { bound = false }
    end
    local meta = meta_for(entry.record)
    local player = get_player()
    local render = deps.render()
    local cost = render.cost(meta, player ~= nil and player.vitals or {})
    local spell_recasts = ctx.get_spell_recasts ~= nil and ctx.get_spell_recasts() or {}
    local ability_recasts = ctx.get_ability_recasts ~= nil and ctx.get_ability_recasts() or {}
    return {
      bound = true,
      recast = render.remaining_for(meta, spell_recasts, ability_recasts),
      affordable = cost == nil or cost.affordable ~= false,
      buffs = player ~= nil and player.buffs or nil,
    }
  end

  --[[ The weapon state is the service's; the rotation follows it from
       here. Read on every path that can move it - a press, a status, the
       tick - and a change lands the set exactly as the old in-widget flip
       did (bindings.set_weapon_state is the same landing). ]]
  function self.sync_weapon()
    local state = service.weapon_state()
    if bindings.weapon_state() ~= state then
      bindings.set_weapon_state(state)
      deps.repaint()
    end
  end

  --[[ Fire one slot of one (set, side), whatever pointed at it. Everything
       after the resolve - the gate, the flash, the travel countdown, the
       cast retry - is the service's, so two ways in cannot become two
       behaviours. ]]
  function self.fire(set, side, slot, flash)
    local record = bindings.resolve(set, side, slot)
    service.fire(record, {
      gate_facts = record ~= nil and gate_facts(record) or nil,
      flash = flash,
      retry_facts = function(entry)
        return retry_facts_at(entry, set, side, slot)
      end,
      owner = name,
    })
    self.sync_weapon()
  end

  --[[ Job scoping, continued ---------------------------------------------- ]]

  function self.try_scope(force)
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
    -- `set_job` reloads `active_set` from the incoming job's own file, so a
    -- job change usually lands somewhere else entirely; an open binder
    -- window would keep the address it was opened on.
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
    -- job change landing mid-preview must re-assert the simulated list.
    apply_buffs()
    deps.repaint()
  end

  -- The tick's half of scoping: the deadline on an announced job change,
  -- and the retry while nothing is scoped yet.
  function self.tick_scope(clock)
    if rescope_want ~= nil and rescope_want.deadline ~= nil and clock >= rescope_want.deadline then
      -- The client never confirmed the announced ids: stop gating and
      -- scope whatever it answers now.
      rescope_want = nil
      self.try_scope(true)
    elseif scoped_main == nil or rescope_want ~= nil then
      self.try_scope(rescope_want ~= nil)
    end
  end

  -- The event carries (main_id, main_lv, sub_id, sub_lv); both ids gate the
  -- reload - get_player() can still answer the OLD job here.
  function self.on_job_change(main_id, _, sub_id)
    rescope_want = nil
    if type(main_id) == "number" then
      rescope_want = {
        main = main_id,
        sub = type(sub_id) == "number" and sub_id or nil,
        deadline = (ctx.now ~= nil and ctx.now() or 0) + RESCOPE_DEADLINE_SECONDS,
      }
    end
    self.try_scope(true)
  end

  --[[ The binder ----------------------------------------------------------
       The catalog instance is built with it; the binder rebuilds its listing
       on each open, so a level-up or a fresh spell is picked up without a
       reload. ]]
  local catalog = new_catalog({
    get_player = get_player,
    get_spells = ctx.get_spells,
    get_abilities = ctx.get_abilities,
    -- What the weapon in hand can perform: the client's weaponskill list is
    -- the JOB's. Read through the model rather than resolved again here,
    -- so the picker and the `wpn:` layer can never name different classes.
    weapon_class = function()
      return bindings ~= nil and bindings.weapon_type() or nil
    end,
    get_items = ctx.get_items,
    owned_mounts = roulette ~= nil and roulette.owned or nil,
    mount_display = roulette ~= nil and roulette.display or nil,
    resources = resources,
    bags = equip_bags,
    extdata_decode = ctx.decode_extdata,
  })

  binder = new_binder({
    name = name,
    grammar = grammar,
    new_image = ctx.new_image,
    new_text = ctx.new_text,
    asset = ctx.asset,
    screen = ctx.screen,
    text_style = function()
      local live = config()
      return { font = live.font or "sans-serif", size = live.font_size or 7 }
    end,
    render = deps.render,
    groups = deps.groups,
    bindings = function()
      return bindings
    end,
    catalog = catalog,
    validate = actions.validate,
    icon = function(record)
      local candidate = record ~= nil and self.pick_icon(record, meta_for(record), draw_state()) or nil
      return candidate ~= nil and ctx.asset(candidate.path) or nil
    end,
    --[[ Tooltips carry only what the bar already knows - no game
         description text. The recast reads ride the tick's cache when it
         has one, falling back to a live read rather than an empty table. ]]
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
        local spell_recasts = reads ~= nil and reads.spell_recasts
          or (ctx.get_spell_recasts ~= nil and ctx.get_spell_recasts())
          or {}
        local ability_recasts = reads ~= nil and reads.ability_recasts
          or (ctx.get_ability_recasts ~= nil and ctx.get_ability_recasts())
          or {}
        local remaining = deps.render().remaining_for(meta, spell_recasts, ability_recasts)
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
    changed = deps.repaint,
    -- Where the player dragged the binder window to: edit-mode furniture,
    -- so it lives in the bar's own config beside the other preferences.
    window_pos = function()
      return config().binder_pos
    end,
    save_window_pos = function(x, y)
      config().binder_pos = { x = x, y = y }
      deps.save()
    end,
    --[[ Preview = a SIMULATED buff list through the live resolver, never a
         hand-toggled layer, so the bar always shows the true stacked
         result. nil hands the live buff list back. ]]
    preview = function(buffs)
      previewing = buffs
      apply_buffs()
      deps.repaint()
    end,
  })

  function self.binder()
    return binder
  end

  --[[ The set moved under the bar. Edit mode lets the switch through, and
       the binder's window remembers the address it was opened on - so the
       window is put away rather than left pointing at a set that is no
       longer on screen. Only a set that actually MOVED puts it away. ]]
  function self.set_changed(before)
    if editing() and before ~= bindings.active_set() then
      binder.deselect()
    end
    deps.repaint()
  end

  function self.close_edit()
    if editing() then
      binder.close()
      service.set_edit_mode(name, false)
      deps.on_edit(false)
      deps.repaint()
    end
  end

  function self.toggle_edit()
    if editing() then
      self.close_edit()
      return name .. ": edit mode off"
    end
    if ctx.layout_active ~= nil and ctx.layout_active() then
      return name .. ": //hud layout owns the mouse - leave layout mode first"
    end
    if not deps.visible() then
      return name .. ": the " .. name .. " is hidden - //hud show " .. name .. " first"
    end
    -- Two binders would each answer one click: core ORs every bar's mouse
    -- handler, and each routes to its own window unconditionally.
    local other = service.edit_owner()
    if other ~= nil and other ~= name then
      return name .. ": the " .. other .. "'s binder is open - close it first"
    end
    if scoped_main == nil then
      -- Nothing is bindable before a job is named: the binder would open on
      -- a bar with no set behind it, which is worse than a refusal.
      return name .. ": no job scoped yet - log in first"
    end
    binder.open()
    -- The service refuses a trip while any bar's binder is up, and calls
    -- off one already counting down.
    service.set_edit_mode(name, true)
    deps.on_edit(true)
    -- The bar repaints into its edit-mode dress: each slot wearing the tag
    -- of the layer its winner came from.
    deps.repaint()
    return name .. ": edit mode on - click a slot, then a layer, an action, and a target"
  end

  --[[ Commands ------------------------------------------------------------ ]]

  function self.status_lines()
    if scoped_main == nil then
      return name .. ": no job loaded yet"
    end
    local head = name .. ": " .. scoped_main
    if scoped_sub ~= nil then
      head = head .. "/" .. scoped_sub
    end
    local lines = { head .. " - set " .. bindings.active_set() .. " (" .. bindings.weapon_state() .. ")" }
    -- The class the weapon layer is keyed to, which nothing else reports.
    local class = bindings.weapon_type()
    if class ~= nil then
      lines[1] = lines[1] .. " - " .. class
    end
    if deps.views ~= false then
      -- The CLI owns the view map: it is the spelling the user types.
      for _, view in ipairs(authoring.views) do
        local target = bindings.view_target(view.key)
        if type(target) == "table" then
          lines[#lines + 1] = "  "
            .. view.cli
            .. " -> "
            .. tostring(target.set)
            .. (target.side == "left" and "L" or "R")
        end
      end
    end
    return lines
  end

  local function opener_lines()
    local names = {}
    for opener in pairs(openers) do
      names[#names + 1] = opener
    end
    table.sort(names)
    return { name .. " open targets:", "  " .. table.concat(names, ", ") }
  end

  --[[ The one dispatcher behind `//hud <name> ...` and a shortcut key's
       verb. Answers a string or a list of lines, or nil when execution
       already happened. `set`, bare `cycle`, bare `open`, `edit` and `open
       <name>` are answered here; the authoring verbs by the CLI; anything
       else - the framework's own verbs included, `warp` and `draw` among
       them - by the hint, with no pointer. ]]
  function self.command(args)
    args = args or {}
    local verb = type(args[1]) == "string" and args[1]:lower() or nil
    if verb == nil or verb == "" then
      if deps.status ~= nil then
        return deps.status()
      end
      return self.status_lines()
    end
    if verb == "set" then
      -- The CLI absorbs the model's asymmetry: `jump` takes numbers only,
      -- while `bind` also takes numeric strings because its set argument
      -- carries the layer prefixes.
      local set = tonumber(args[2])
      if set == nil then
        return name .. ": set takes a number - //hud " .. name .. " set <1-8>"
      end
      local before = bindings.active_set()
      local landed, err = bindings.jump(set)
      if landed == nil then
        return name .. ": " .. err
      end
      self.set_changed(before)
      return name .. ": set " .. landed
    end
    if verb == "cycle" and args[2] == nil then
      -- The bare/args overload: bare advances the rotation, with args it
      -- edits rotation membership (the authoring half, below).
      local before = bindings.active_set()
      local landed, err = bindings.cycle()
      if landed == nil then
        return name .. ": " .. err
      end
      self.set_changed(before)
      return name .. ": set " .. landed
    end
    if verb == "open" and args[2] == nil then
      return opener_lines()
    end
    if verb == "edit" then
      return self.toggle_edit()
    end
    if authoring.handles(verb) then
      local reply, save_config, needs_repaint = authoring.command(args)
      -- Every accepted change persists immediately: a binding write went
      -- through the store on its way here, and a config write needs core's
      -- own save. Both then re-render.
      if save_config then
        deps.save()
      end
      if needs_repaint then
        deps.repaint()
      end
      return reply
    end
    if verb == "open" then
      -- Arguments fold case like verbs do: `open EQUIPMENT` is the same
      -- opener. The one built-in still answered by a bar: it opens a game
      -- window, a bar's convenience rather than a press.
      local argument = args[2]
      if type(argument) == "string" then
        argument = argument:lower()
      end
      local hint = service.builtin(verb, argument)
      if hint ~= nil then
        return name .. ": " .. hint
      end
      return nil
    end
    -- `help` first: the CLI's own unknown-verb reply is unreachable (the
    -- routing above asks handles() first), so this is the only hint an
    -- unknown verb ever sees, and the full list is one word away.
    return name .. ": unknown command '" .. verb .. "' - try help, set, cycle, open or edit"
  end

  --[[ The bar's attach and detach halves of the widget contract. ]]

  function self.attach(store)
    bindings = build_bindings(store)
    -- A trip belongs to the configuration that armed it, and core
    -- re-attaches WITHOUT detaching (`//hud reset`, `//hud slot`, the
    -- reload `//hud copy` does), so one armed beforehand would otherwise
    -- fire afterwards. The service drops the countdown silently and names
    -- a warm-up it lets go.
    service.drop_trip()
    scoped_main, scoped_sub, rescope_want = nil, nil, nil
    counts_dirty = true
    reads, last_read_generation = nil, nil
  end

  function self.detach()
    -- The binder describes a character's bindings; a logout invalidates
    -- every one of them, so it goes down with the scope.
    self.close_edit()
    -- A logout mid-warp must not leave a GearSwap slot disabled, and the
    -- cast THIS bar pressed is invalidated with everything else - the other
    -- bar's is its own to drop, the rule bar_hidden keeps.
    service.drop_trip()
    local held = service.retry.held()
    if held ~= nil and held.owner == name then
      service.retry.clear()
    end
    scoped_main, scoped_sub, rescope_want = nil, nil, nil
    reads, last_read_generation = nil, nil
    bindings = build_bindings(nil)
    if icon_cache ~= nil then
      icon_cache.reset()
    end
  end

  function self.destroy()
    if binder ~= nil then
      binder.destroy()
    end
  end

  return self
end

return new
