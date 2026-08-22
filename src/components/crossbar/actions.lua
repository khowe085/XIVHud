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

--[[ Pure action resolution: a bound action record (or a built-in's command
     form) in, an executable plan out. Plans:

       { kind = "command", command }            -- one line for send_command
       { kind = "keys", sequence }              -- setkey down/up edges, in order
       { kind = "message", message }            -- a chat hint, nothing fired
       { kind = "warp", plan }                  -- the warp ladder's own plan
       { kind = "enchanted", plan }             -- one named enchanted item's,
                                                -- the same three plan shapes
       { kind = "none" }                        -- a legitimate no-op
       nil, hint                                -- rejected input

     For the game types the type word IS the FFXI command word. The quote
     around the action name always closes -- upstream leaves it open when
     there is no target (its defect 9) -- and the target suffix appears only
     when a target exists.

     Built-in actions are dual-frontend: a slot of that type and the
     `//hud crossbar <name>` command both land in resolve(), so behaviour and
     appearance cannot diverge; resolve_builtin() is the command frontend's
     name -> record step. Adding a built-in is one BUILTINS entry both pick
     up. Openers fire immediately and unconditionally: the v4 activators are
     punctuation, so no held modifier can contaminate an injected chord. ]]

local openers = require("components/crossbar/openers")

-- Types whose word is the FFXI command word, fired as /<type> "<name>".
local GAME_TYPES = { ma = true, ja = true, ws = true, item = true, pet = true, mount = true }

--[[ Built-in actions: the execution lives in resolve(); an entry carries the
     command frontend's name(s) and the icon a bound slot shows. draw's icon
     follows its state; open's comes from the opener entry.

     ADDING AN ENTRY IS TWO EDITS, not one. The two FRONTENDS stay in step
     by construction - this one table feeds the slot form and the
     `//hud crossbar <name>` form together - but the spec keeps its own
     literal roster, deliberately: a spec that reads its expectation out of
     the code under test cannot catch an entry added by accident, which is
     why the export that let it do so was removed. `crossbar_actions_spec`
     asserts the two rosters are EQUAL, reading this table out of the
     source the way sources_spec.lua reads every file in src/, so an entry
     added here and nowhere else fails the build. Extend the spec's list
     too - that is the second edit.

     The BINDER's picker is a third place, and deliberately not automatic:
     `catalog.lua` keeps its own `BUILTIN_ENTRIES`, a curated ordering with
     its own labels ("Attack" for `draw`) and its own membership - it
     carries `ra`, which is not a built-in at all, and leaves out `open`,
     whose entries come from the opener table one by one. A new built-in
     therefore reaches the slot and command frontends for free, and the
     picker only if someone decides it belongs there. ]]
local BUILTINS = {
  draw = {},
  mr = { icon = "mount" },
  warp = { icon = "items/warp-ring" },
  open = {},
}
-- Derived, sorted: the name walk can never drift from the table, so the two
-- frontends need no edit of their own (the spec's roster still does).
local BUILTIN_NAMES = {}
for name in pairs(BUILTINS) do
  BUILTIN_NAMES[#BUILTIN_NAMES + 1] = name
end
table.sort(BUILTIN_NAMES)

-- Built-in names allowed to shadow an authoring verb: `open` is both the
-- action prefix (`open <name>`) and, bare, the list verb. (The plan's other
-- dual-use verb, `cycle`, is an authoring verb only -- it never appears in
-- BUILTINS, so it needs no exception here; its bare-vs-args overload is the
-- command parser's concern.)
local COLLISION_EXCEPTIONS = { open = true }

local function target_suffix(target)
  if target == nil then
    return ""
  end
  return " <" .. target .. ">"
end

-- The action name (or ct line / ex command) a record must carry to fire.
local function valid_name(value)
  return type(value) == "string" and value ~= ""
end

local function command_plan(command)
  return { kind = "command", command = command }
end

local function open_plan(name)
  local entry = openers[name]
  if entry == nil then
    return nil, "unknown open target: " .. tostring(name)
  end
  if entry.command then
    return command_plan("input " .. entry.command)
  end
  local sequence = {}
  for index = 1, #entry.chord do
    sequence[#sequence + 1] = { key = entry.chord[index], state = "down" }
  end
  for index = #entry.chord, 1, -1 do
    sequence[#sequence + 1] = { key = entry.chord[index], state = "up" }
  end
  return { kind = "keys", sequence = sequence }
end

-- Mounted outranks everything: you cannot engage while mounted, and the same
-- gesture should dismount, which is the one draw press that does NOT touch
-- the weapon state.
local function draw_plan(state)
  state = state or {}
  if state.mounted then
    return command_plan("input /dismount")
  end
  if state.weapon_drawn then
    local plan = command_plan("input /attack off")
    plan.weapon_state = "sheathed"
    return plan
  end
  --[[ Entering drawn sends NOTHING (Kevin, 2026-08-22). The component's
       weapon state is its own: it picks which set rotation is live and
       lights the bar's sword. Wanting the combat rotation is not wanting to
       swing at something, and the player engages and picks targets himself.

       It used to `/attack <t>` with a target and refuse outright without
       one. Both are gone, which is why this branch no longer asks whether
       anything is targeted at all.

       Leaving drawn still sends `/attack off`, and deliberately: an
       explicit `draw` while drawn means "I am done fighting", which is the
       rule the whole one-way state machine is built on. ]]
  return { kind = "none", weapon_state = "drawn" }
end

local function new(deps)
  local self = {}

  function self.resolve(record, state)
    -- An unbound slot is the commonest input: bindings.resolve answers nil
    -- for empty, which is normal -- plain nil back, no hint.
    if record == nil then
      return nil
    end
    local kind = record.type
    -- The data files are hand-editable and bindings stores what it is given,
    -- so a malformed record answers nil + hint, never a crash or a nil command.
    if record.target ~= nil and type(record.target) ~= "string" then
      return nil, "target must be a string when present"
    end
    if GAME_TYPES[kind] then
      if not valid_name(record.action) then
        return nil, "missing action name for /" .. kind
      end
      return command_plan("input /" .. kind .. ' "' .. record.action .. '"' .. target_suffix(record.target))
    end
    if kind == "ra" then
      return command_plan("input /ra" .. target_suffix(record.target))
    end
    if kind == "ct" then
      if not valid_name(record.action) then
        return nil, "missing chat line for ct"
      end
      return command_plan("input /" .. record.action .. target_suffix(record.target))
    end
    if kind == "ex" then
      if not valid_name(record.action) then
        return nil, "missing console command for ex"
      end
      return command_plan(record.action)
    end
    if kind == "open" then
      return open_plan(record.action)
    end
    if kind == "draw" then
      return draw_plan(state)
    end
    if kind == "mr" then
      local command = deps.roulette.ride()
      if command == nil then
        return { kind = "none" }
      end
      local plan = command_plan(command)
      -- Which of the two rides this is, from the roulette's own buff read.
      -- The travel delay holds a summon and lets a dismount go at once, and
      -- a flag is how it knows without reading the command string back.
      if deps.roulette.mounted ~= nil and deps.roulette.mounted() then
        plan.dismount = true
      end
      return plan
    end
    if kind == "warp" then
      return { kind = "warp", plan = deps.warp.plan() }
    end
    -- The named-item sibling of warp: the same plan shapes, so the widget's
    -- equip -> wait -> use scheduler runs either without knowing which asked.
    if kind == "enchanteditem" then
      if not valid_name(record.action) then
        return nil, "missing item name for enchanteditem"
      end
      return { kind = "enchanted", plan = deps.enchanteditem.plan(record.action, record.target) }
    end
    return nil, "unknown action type: " .. tostring(kind)
  end

  -- The command frontend: `//hud crossbar <name> [<arg>]` -> the same record
  -- shape a slot binds, resolved through the same path.
  function self.resolve_builtin(name, arg, state)
    -- Verbs match case-insensitively everywhere in the framework.
    name = type(name) == "string" and name:lower() or name
    if BUILTINS[name] then
      return self.resolve({ type = name, action = arg }, state)
    end
    return nil, "unknown built-in action: " .. tostring(name)
  end

  -- The icon a slot shows for a built-in; nil where the render fallback (or,
  -- later, the catalog) chooses instead.
  function self.icon_for(record, state)
    if record == nil then
      return nil
    end
    if record.type == "draw" then
      state = state or {}
      if state.mounted then
        return "dismount"
      end
      if state.weapon_drawn then
        return "disengage"
      end
      return "attack"
    end
    if record.type == "open" then
      local entry = openers[record.action]
      return entry and entry.icon
    end
    local entry = BUILTINS[record.type]
    return entry and entry.icon
  end

  --- Bind-time validation: is this record something resolve() could fire?
  --- Answers true, or nil + a hint naming what is wrong. Nothing is executed
  --- -- `mr` and `warp` resolve through their collaborators, and validating
  --- a binding must not ride a mount or equip a ring.
  function self.validate(record)
    if type(record) ~= "table" then
      return nil, "a binding needs a type"
    end
    local kind = record.type
    if record.target ~= nil and type(record.target) ~= "string" then
      return nil, "target must be a string when present"
    end
    if GAME_TYPES[kind] then
      if not valid_name(record.action) then
        return nil, "/" .. kind .. " needs an action name"
      end
      return true
    end
    if kind == "ct" or kind == "ex" then
      if not valid_name(record.action) then
        return nil, kind == "ct" and "ct needs a chat line" or "ex needs a console command"
      end
      return true
    end
    if kind == "enchanteditem" then
      -- Name only. Whether the item exists, is carried, is enchanted or is
      -- charged is a question about right now, and binding is not now.
      if not valid_name(record.action) then
        return nil, "enchanteditem needs an item name"
      end
      return true
    end
    if kind == "open" then
      if openers[record.action] == nil then
        return nil, "unknown open target: " .. tostring(record.action)
      end
      return true
    end
    if kind == "ra" or BUILTINS[kind] then
      -- `open` was answered above; the rest carry no action name at all, so
      -- one silently ignored would be a binding that does not do what it says.
      if record.action ~= nil then
        return nil, kind .. " takes no action name"
      end
      return true
    end
    return nil, "unknown action type: " .. tostring(kind)
  end

  -- Built-in names must not shadow the authoring verbs (validated at load,
  -- like registry names against reserved command words), bar the documented
  -- exceptions. Answers the colliding names, in table order.
  function self.check_collisions(reserved_verbs)
    local reserved = {}
    for _, verb in ipairs(reserved_verbs) do
      reserved[verb] = true
    end
    local collisions = {}
    for _, name in ipairs(BUILTIN_NAMES) do
      if reserved[name] and not COLLISION_EXCEPTIONS[name] then
        collisions[#collisions + 1] = name
      end
    end
    return collisions
  end

  return self
end

return new
