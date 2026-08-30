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

--[[ The framework itself: everything XIVHud.lua would otherwise have to do.

     Core owns the registry, the per-component config service, the auto-hide
     resolver and layout mode, and it is the single place that decides whether a
     component is on screen. It touches no Windower globals — the entry point
     hands it a plain deps table — so the whole framework is exercised by specs
     with fake file I/O and a scripted mouse.

     Responsibilities that deliberately live here rather than in a component:

     - Visibility. Components expose show/hide; only core calls them, folding
       together the suppression set, the active layout slot and layout mode.
     - Persistence. A component never writes its own file; core saves through
       the handle it owns on its behalf.
     - Character scoping. Configs do not exist until login, so components are
       attached on login and detached on logout. ]]

local new_commands = require("lib/commands")
local new_layout = require("lib/layout")
local new_layout_mode = require("lib/layout_mode")
local new_overlay = require("lib/overlay")
local new_registry = require("lib/registry")
local new_settings = require("lib/settings")
local new_visibility = require("lib/visibility")

-- How often on_prerender may ask the client for a character before one is
-- known. Only relevant in the gap between the login event and get_player().
local CHARACTER_RETRY_SECONDS = 1
-- Once the client says we are logged in, the only thing still missing is the
-- player data, which arrives within a moment: this is the visible delay before
-- the HUD comes up, so it is checked far more often than character select is.
local LOADING_RETRY_SECONDS = 0.05

local CORE_NAMESPACE = "core"
local CORE_DEFAULTS = {
  -- Grid the drag in layout mode snaps to; CTRL frees it.
  snap = 10,
  -- Active layout slot. Named slots are already in the schema; the commands
  -- that manage them are still to come.
  slot = "default",
  -- Named after XIVParty's hideCutscene: hide the HUD during the NPC
  -- conversations and cutscenes that put the player in status 4.
  hideCutscene = true,
}

local HELP = {
  "XIVHud commands:",
  "  //hud help                 this list",
  "  //hud layout               toggle layout mode: drag to move, wheel to scale,",
  "                            right-click to toggle, CTRL to ignore the grid",
  "  //hud list                 components with their state",
  "  //hud show|hide <name>     turn a component on or off",
  "  //hud reset <name|all>     restore configuration defaults",
  "  //hud slot <name>          switch layout slot",
  "  //hud slot list            layout slots, active one marked",
  "  //hud slot create <name>   new slot, copied from the active one",
  "  //hud slot delete <name>   remove a slot",
  "  //hud copy <from> <to>     replace one character's config with another's",
  "  //hud <name> ...           pass a command to a component",
}

local function new(deps)
  local self = {}
  local registry
  local core_handle
  local next_character_check = nil
  local awaiting_login = false

  local function say(message)
    deps.chat(message)
  end

  local commands = new_commands({
    components = function()
      return registry and registry.names() or {}
    end,
  })

  local settings = new_settings({
    read_file = deps.read_file,
    write_file = deps.write_file,
    -- So reset can clear a component's directory store, not just its file.
    list_dir = deps.list_dir,
    delete_file = deps.delete_file,
    notify = say,
  })

  registry = new_registry({ reserved = commands.reserved, notify = say })

  local function core_config()
    return core_handle and core_handle.get() or nil
  end

  local layout = new_layout({
    screen = deps.screen,
    snap_size = function()
      local config = core_config()
      return config and config.snap or CORE_DEFAULTS.snap
    end,
  })

  local visibility = new_visibility({ now = deps.now })

  -- The layout-mode highlight and name label per component. Purely feedback:
  -- layout mode force-shows every widget, so without it the right-click enable
  -- toggle would change nothing the user can see.
  local overlay = new_overlay({
    new_image = deps.new_image,
    new_text = deps.new_text,
    texture = deps.overlay_texture,
  })

  -- Config handles, keyed by component name. A component only ever reaches its
  -- own, which is what keeps the per-component isolation honest.
  local handles = {}

  local function active_slot()
    local config = core_config()
    local slot = config and config.slot
    -- The name becomes a path segment, and this one arrives from a file: core.lua
    -- is hand-editable and `//hud copy` imports another character's. Everything
    -- else that takes a slot name checks it (the parser, the directory listing,
    -- the store); this is the one that would otherwise compose `..` into a path
    -- that `//hud reset` deletes inside.
    if type(slot) == "string" and slot:match("^[%w_]+$") then
      return slot
    end
    return CORE_DEFAULTS.slot
  end

  -- The placement a component ships with, seeding its layout.lua and repairing
  -- whatever a hand edit left unusable in it.
  local function layout_defaults_of(component)
    local defaults = component.defaults or {}
    return defaults.layout
  end

  -- The anchor names of a multi-anchor component (touchpoint 2), or nil for
  -- the single-anchor majority - the pinned detection: an optional `anchors()`
  -- member, never an implicit convention.
  local function anchor_names(component)
    local names = component.anchors and component.anchors()
    -- A non-table answer reads as no anchors, matching layout_mode.
    if type(names) ~= "table" then
      return nil
    end
    return names
  end

  -- The component's layout state in the active slot, or nil while logged out.
  local function state_of(component)
    local handle = handles[component.name]
    local state = handle and handle.layout()
    if not state then
      return nil
    end
    layout.repair(state, layout_defaults_of(component))
    -- Repair in place rather than only on the way to the prims, so `//hud list`
    -- and the next wheel step work from the same number that is on screen.
    local names = anchor_names(component)
    if names then
      for _, name in ipairs(names) do
        local anchor = state.anchors and state.anchors[name]
        if anchor then
          anchor.scale = layout.clamp_scale(anchor.scale)
        end
      end
    else
      state.scale = layout.clamp_scale(state.scale)
    end
    return state
  end

  -- One anchor's pos/scale-bearing state, or the whole slot state when
  -- `anchor` is nil. nil for an anchor the component lists but its defaults
  -- never seeded - a component authoring bug the callers skip over.
  local function placement_of(component, anchor)
    local state = state_of(component)
    if state and anchor then
      return state.anchors and state.anchors[anchor] or nil
    end
    return state
  end

  -- Layout is core's file, so this is the only thing that writes it.
  local function persist(component)
    local handle = handles[component.name]
    if handle then
      handle.save_layout()
    end
  end

  -- Handed to a component on attach so it can write its *own* config after a
  -- change of its own (a `//hud <name> ...` command). It reaches config.lua
  -- alone: layout.lua is core's, and a component never reaches another
  -- component's handle at all.
  local function saver_for(component)
    return function()
      local handle = handles[component.name]
      if handle then
        handle.save_config()
      end
    end
  end

  --[[ The directory store, for a component declaring `wants_store = true`:
       the files it adds beside the config.lua and layout.lua core writes into
       `data/<Character>/<slot>/<component>/`, the shape per-job configuration
       needs. The closures re-read the handle on every call
       rather than capturing its state, so one accessor stays valid across
       re-attaches and reloads. Everyone else keeps the two-argument attach
       they always had. ]]
  local function store_for(component)
    if not component.wants_store then
      return nil
    end
    local handle = handles[component.name]
    return {
      load = function(name)
        return handle.store_load(name)
      end,
      save = function(name, value)
        return handle.store_save(name, value)
      end,
    }
  end

  local function attach(component)
    local handle = handles[component.name]
    component.attach(handle.get(), saver_for(component), store_for(component))
  end

  -- Bounds are read after the position and scale have been pushed, so the
  -- highlight tracks the widget through a drag or a wheel-scale. A
  -- multi-anchor component gets one highlight per anchor, under a per-anchor
  -- key that doubles as the label naming the anchor.
  local function overlay_key(component, anchor)
    return anchor and (component.name .. ":" .. anchor) or component.name
  end

  local function apply_anchor_overlay(component, state, anchor)
    local key = overlay_key(component, anchor)
    if not self.layout_active() or visibility.suppressed() then
      overlay.hide(key)
      return
    end

    local x, y, width, height = component.get_bounds(anchor)
    if not x then
      overlay.hide(key)
      return
    end
    overlay.show(key, x, y, width, height, state.visible == true)
  end

  local function apply_overlay(component, state)
    local names = anchor_names(component)
    if names then
      for _, name in ipairs(names) do
        apply_anchor_overlay(component, state, name)
      end
    else
      apply_anchor_overlay(component, state, nil)
    end
  end

  -- Pushes one placement - an anchor's, or the whole widget's when `anchor`
  -- is nil - and repairs it back on screen. A position can arrive off screen
  -- from a hand-edited file, a resolution change or `//hud copy`; left alone,
  -- layout mode's hit test could never reach the widget again. Bounds are
  -- only known once the position and scale are on the component, hence the
  -- second set_pos.
  local function apply_placement(component, placement, anchor)
    -- Anchored defaults on a widget with no anchors() member: layout.repair
    -- keys off the defaults and strips the top-level pos, while detection here
    -- keys off the member - skip the mismatch rather than crash the apply.
    if type(placement.pos) ~= "table" then
      return
    end
    component.set_scale(placement.scale, anchor)
    component.set_pos(placement.pos.x, placement.pos.y, anchor)

    local bounds_x, bounds_y, width, height = component.get_bounds(anchor)
    if bounds_x then
      local x, y = layout.clamp(bounds_x, bounds_y, width, height)
      if x ~= placement.pos.x or y ~= placement.pos.y then
        placement.pos.x, placement.pos.y = x, y
        component.set_pos(x, y, anchor)
      end
    end
  end

  -- The one decision about whether a component is on screen. Layout mode
  -- force-shows everything (including components the user has switched off, so
  -- they can be re-enabled), but a suppression reason still outranks it.
  local function apply(component)
    local state = state_of(component)
    if not state then
      component.hide()
      return
    end

    local names = anchor_names(component)
    if names then
      for _, name in ipairs(names) do
        local anchor = state.anchors and state.anchors[name]
        if anchor then
          apply_placement(component, anchor, name)
        end
      end
    else
      apply_placement(component, state, nil)
    end
    if component.set_preview then
      component.set_preview(self.layout_active())
    end

    if visibility.suppressed() then
      component.hide()
    elseif self.layout_active() then
      component.show()
    elseif state.visible == true then
      component.show()
    else
      component.hide()
    end

    apply_overlay(component, state)
  end

  local function apply_all()
    for _, component in ipairs(registry.all()) do
      apply(component)
    end
  end

  local layout_mode = new_layout_mode({
    layout = layout,
    components = function()
      return registry.all()
    end,
    state = placement_of,
    apply = apply,
    persist = persist,
  })

  function self.layout_active()
    return layout_mode.active()
  end

  -- For an input-consuming component's guards: whether the auto-hide resolver
  -- is currently hiding the HUD (cutscene, zoning, logged out).
  function self.suppressed()
    return visibility.suppressed()
  end

  -- The other half of suppressed() for the same guards: the USER's visible
  -- flag for one component. Suppression and a user hide both reach a widget
  -- as hide(), and only core can say which is which - the flag is what
  -- `//hud show|hide` and layout mode's right-click write, untouched by
  -- suppression, so a guard ranking disabled above suppressed reads it.
  function self.component_visible(name)
    local component = registry.get(name)
    if component == nil then
      return false
    end
    local state = state_of(component)
    return state ~= nil and state.visible == true
  end

  function self.character()
    return settings.character()
  end

  function self.names()
    return registry.names()
  end

  -- Registers a constructed component: claims its config namespace and, when a
  -- character is already logged in, attaches it straight away.
  function self.register(component)
    registry.register(component)
    handles[component.name] = settings.register(component.name, component.defaults)
    if settings.character() then
      attach(component)
    end
    apply(component)
    return component
  end

  local function set_layout_mode(on)
    if on then
      layout_mode.enter()
    else
      layout_mode.exit()
    end
    deps.set_input_capture(on)
  end

  -- Pushes freshly loaded configuration into the framework and the components.
  -- Shared by login and by `//hud copy`, which replaces the files underneath us.
  local function apply_settings(name)
    local config = core_config()
    visibility.set_logged_in(name ~= nil)
    visibility.set_hide_event(not config or config.hideCutscene ~= false)
    -- Reloading mid-cutscene must not flash the HUD back on: take the status
    -- the player is already in, rather than waiting for the next transition.
    local player = name and deps.get_player() or nil
    visibility.set_status(player and player.status or nil)

    for _, component in ipairs(registry.all()) do
      if name then
        attach(component)
      else
        component.detach()
      end
    end

    apply_all()
  end

  -- Login, logout and character switch all land here. Returns true when the
  -- character actually changed, so callers can avoid needless re-attaching.
  local function set_character(name)
    if not settings.set_character(name) then
      return false
    end

    if not core_handle then
      -- Character-scoped, not slot-scoped: core holds the active slot, so its
      -- own file cannot live inside one.
      core_handle = settings.register_character(CORE_NAMESPACE, CORE_DEFAULTS)
    end

    -- Nothing else ever writes core's file, so create it on the first login for
    -- a character: an option the user cannot see is an option they do not have.
    if name and not deps.read_file(core_handle.path()) then
      core_handle.save()
    end

    -- Every component's directory hangs off the active slot, which is core's
    -- to know, so announce it before anything reads a config. A logout needs
    -- no announcement: set_character has already un-scoped every component.
    if name then
      settings.set_slot(active_slot())
    end

    apply_settings(name)
    return true
  end

  -- The character to scope configuration to, or nil while the client cannot say
  -- yet. Deliberately asks for nothing but the name: a component that needs the
  -- player's data waits for it itself, because the client fills that in field by
  -- field and there is no one signal that says it is all there. parambar does
  -- exactly that.
  local function character_to_scope()
    if deps.logged_in and not deps.logged_in() then
      return nil
    end
    local player = deps.get_player()
    local name = player and player.name
    -- The name is briefly an empty string around zone-in; scoping configs to
    -- `data//<slot>/<component>/` on the strength of that would be worse than
    -- waiting a frame.
    if type(name) ~= "string" or name == "" then
      return nil
    end
    return name
  end

  -- A login the client cannot resolve yet leaves the character already scoped
  -- alone - dropping one is on_logout's job - and leaves `awaiting_login` set,
  -- because the login event is a one-shot and on_prerender otherwise only looks
  -- when there is no character at all.
  local function catch_up()
    local name = character_to_scope()
    if name then
      awaiting_login = false
      set_character(name)
    end
  end

  local function login_event()
    awaiting_login = true
    -- Whatever slot the retry booked while nobody was logged in is a second the
    -- player would now spend watching a blank HUD.
    next_character_check = nil
    catch_up()
  end

  function self.on_load()
    login_event()
  end

  function self.on_login()
    login_event()
  end

  function self.on_logout()
    if layout_mode.active() then
      set_layout_mode(false)
    end
    set_character(nil)
  end

  function self.on_unload()
    if layout_mode.active() then
      set_layout_mode(false)
    end
    overlay.destroy_all()
    registry.destroy_all()
    handles = {}
  end

  function self.on_status_change(new_status, old_status)
    if visibility.set_status(new_status) then
      apply_all()
    end
    self.dispatch("status", new_status, old_status)
  end

  function self.on_zone_change()
    if visibility.zone_changed() then
      apply_all()
    end
  end

  -- Components are fed every frame rather than on a core-owned throttle: the
  -- bars ease their width per frame, and a component that only polls can time
  -- its own refresh. Components keep receiving updates while suppressed so
  -- their data is current the moment they come back.
  function self.on_prerender()
    -- The `login` event can fire before get_player() has a name, so keep looking
    -- until it does. Throttled, at two speeds: a login already
    -- under way is the player watching a blank HUD, while an empty character
    -- select is worth no more than a poll a second.
    if awaiting_login or not settings.character() then
      local now = deps.now()
      if not next_character_check or now >= next_character_check then
        local live = deps.logged_in and deps.logged_in() or false
        next_character_check = now + (live and LOADING_RETRY_SECONDS or CHARACTER_RETRY_SECONDS)
        if live then
          catch_up()
        end
      end
    end

    if visibility.tick() then
      apply_all()
    end
    if not settings.character() then
      return
    end
    for _, component in ipairs(registry.all()) do
      if component.update then
        component.update()
      end
    end
  end

  -- Forwards a game event (hp change, status change, …) to every component.
  function self.dispatch(event, ...)
    if not settings.character() then
      return
    end
    for _, component in ipairs(registry.all()) do
      if component.update then
        component.update(event, ...)
      end
    end
  end

  --[[ An event a prior addon already took is answered here and never reaches
       a component, so the component signature carries no `blocked`: it would
       be false on every call the dispatch can make. ]]
  function self.on_mouse(mouse_type, x, y, delta, blocked)
    -- Suppression outranks layout mode, so nothing is on screen to grab.
    if blocked or visibility.suppressed() then
      return false
    end
    -- Layout mode owns the mouse outright while it is on; entering it exits a
    -- component's edit mode, so the two never contend (touchpoint 3).
    if layout_mode.active() then
      return layout_mode.mouse(mouse_type, x, y, delta)
    end
    local block = false
    for _, component in ipairs(registry.all()) do
      if component.on_mouse then
        block = component.on_mouse(mouse_type, x, y, delta) == true or block
      end
    end
    return block
  end

  function self.wants_mouse()
    for _, component in ipairs(registry.all()) do
      if component.on_mouse then
        return true
      end
    end
    return false
  end

  --[[ Keyboard events flow whenever the handler is registered: to layout mode
       for its CTRL tracking, and to every component that declares an
       `on_keyboard` member. A component's `true` propagates out to Windower as
       the block. Deliberately NOT gated on layout mode, suppression or login
       (pinned 2026-08-16): a consumer's dedicated keys must stay blocked and
       its key state must keep tracking through all three - the inertness lives
       in the component's own input module, not in dispatch going quiet. The
       full signature is forwarded; `blocked` in particular feeds the
       inbound-blocked guard. ]]
  function self.on_keyboard(key, down, flags, blocked)
    layout_mode.key(key, down)
    local block = false
    for _, component in ipairs(registry.all()) do
      if component.on_keyboard then
        block = component.on_keyboard(key, down, flags, blocked) == true or block
      end
    end
    return block
  end

  -- Whether the keyboard handler is worth registering at all: the entry point
  -- keeps it always-on when some component consumes keys, and layout-mode-only
  -- otherwise.
  function self.wants_keyboard()
    for _, component in ipairs(registry.all()) do
      if component.on_keyboard then
        return true
      end
    end
    return false
  end

  local function require_character()
    if settings.character() then
      return true
    end
    say("log in first - XIVHud configuration is per character")
    return false
  end

  -- One line for a single-anchor component; a headline plus one indented line
  -- per anchor otherwise, since four placements do not fit one chat line.
  local function describe(component)
    local state = state_of(component)
    if not state then
      return { "  " .. component.name .. " - not loaded" }
    end
    local shown = state.visible == true and "shown" or "hidden"
    local names = anchor_names(component)
    -- A placement apply skipped (anchored defaults, no anchors() member) has
    -- no pos to format; the headline still names the component and its state.
    if not names and type(state.pos) ~= "table" then
      return { string.format("  %s - %s", component.name, shown) }
    end
    if not names then
      return {
        string.format("  %s - %s, pos %d,%d, scale %.2f", component.name, shown, state.pos.x, state.pos.y, state.scale),
      }
    end
    local lines = { string.format("  %s - %s", component.name, shown) }
    for _, name in ipairs(names) do
      local anchor = state.anchors and state.anchors[name]
      if anchor then
        lines[#lines + 1] =
          string.format("    %s - pos %d,%d, scale %.2f", name, anchor.pos.x, anchor.pos.y, anchor.scale)
      end
    end
    return lines
  end

  local function set_visible(component, visible)
    local state = state_of(component)
    state.visible = visible
    persist(component)
    apply(component)
  end

  local function reset(component)
    handles[component.name].reset()
    attach(component)
    apply(component)
  end

  --[[ Config trees ------------------------------------------------------- ]]

  local function character_dir(name)
    return "data/" .. name
  end

  -- Empties a config tree. Deleting the files is what makes a copy a
  -- replacement; a directory left behind because it cannot be removed is
  -- harmless, so its failure is not worth reporting.
  local function delete_tree(path)
    local removed = 0
    for _, entry in ipairs(deps.list_dir(path) or {}) do
      if entry ~= "." and entry ~= ".." then
        local child = path .. "/" .. entry
        if deps.is_dir(child) then
          removed = removed + delete_tree(child)
        elseif deps.delete_file and deps.delete_file(child) then
          removed = removed + 1
        end
      end
    end
    if deps.delete_file then
      deps.delete_file(path)
    end
    return removed
  end

  -- Copies a config tree file by file, recursing into the directories under it.
  -- Returns how many files were written and how many failed. Callers empty the
  -- destination with delete_tree first, so what this leaves behind is the
  -- source and nothing else.
  local function copy_tree(from, to)
    local copied, failed = 0, 0
    for _, entry in ipairs(deps.list_dir(from) or {}) do
      -- Recursing into "." would never terminate.
      if entry ~= "." and entry ~= ".." then
        local source, target = from .. "/" .. entry, to .. "/" .. entry
        if deps.is_dir(source) then
          local ok, bad = copy_tree(source, target)
          copied, failed = copied + ok, failed + bad
        else
          local contents = deps.read_file(source)
          if type(contents) == "string" and deps.write_file(target, contents) ~= false then
            copied = copied + 1
          else
            failed = failed + 1
          end
        end
      end
    end
    return copied, failed
  end

  --[[ Layout slots ------------------------------------------------------- ]]

  --[[ Whether a directory is a slot, which is not the same question as whether
       it exists. A slot holds one directory per component, and the files are a
       level below that; both halves are load-bearing:

       - `os.remove` refuses a directory outright on Windows, so deleting a slot
         empties its tree and leaves every directory in it standing. Asking
         `dir_exists` alone would go on offering a slot the player deleted, and
         refuse to let them re-create it.
       - A directory of loose files is not an empty slot, it is something else -
         `data/<Character>/<component>/` as a pre-slot install wrote it. ]]
  local function is_slot_dir(dir)
    for _, entry in ipairs(deps.list_dir(dir) or {}) do
      local component = dir .. "/" .. entry
      if entry ~= "." and entry ~= ".." and deps.is_dir(component) then
        for _, file in ipairs(deps.list_dir(component) or {}) do
          if file ~= "." and file ~= ".." and not deps.is_dir(component .. "/" .. file) then
            return true
          end
        end
      end
    end
    return false
  end

  -- Slot names are compared case-insensitively throughout: the name in core.lua
  -- and the directory on disk are two different sources, and a hand edit can
  -- have them disagree. The path segment works either way on Windows.
  local function same_slot(one, other)
    return type(one) == "string" and type(other) == "string" and one:lower() == other:lower()
  end

  -- A slot is a directory under the character's own. `default` and the active
  -- slot always count, whether or not either has been written to disk yet - and
  -- the directory is added first, so its casing is the one that survives.
  local function slot_names()
    local seen, names = {}, {}
    local function add(name)
      if type(name) == "string" and name ~= "" and not seen[name:lower()] then
        seen[name:lower()] = true
        names[#names + 1] = name
      end
    end

    local character = settings.character()
    if character and deps.list_dir then
      local root = character_dir(character)
      for _, entry in ipairs(deps.list_dir(root) or {}) do
        -- core.lua sits beside the slots, and a slot name has to be typeable as
        -- a command word: a directory that is neither is not a slot.
        local child = root .. "/" .. entry
        if entry:match("^[%w_]+$") and deps.is_dir(child) and is_slot_dir(child) then
          add(entry)
        end
      end
    end
    add("default")
    add(active_slot())

    table.sort(names)
    for index, name in ipairs(names) do
      if name:lower() == "default" and index > 1 then
        table.remove(names, index)
        table.insert(names, 1, "default")
        break
      end
    end
    return names
  end

  -- Directory names are hand-editable, so a stored slot may not be lowercase
  -- even though the parser lowercases what the user types. Returns the stored
  -- name, which is the path segment.
  local function resolve_slot(name)
    for _, known in ipairs(slot_names()) do
      if known:lower() == name:lower() then
        return known
      end
    end
    return nil
  end

  local function say_slots()
    say("XIVHud layout slots:")
    for _, name in ipairs(slot_names()) do
      say("  " .. name .. (same_slot(name, active_slot()) and "  (active)" or ""))
    end
  end

  local function slot_switch(name)
    local slot = resolve_slot(name)
    if not slot then
      say("no layout slot named '" .. name .. "'")
      say_slots()
      return
    end

    if same_slot(slot, active_slot()) then
      -- Still written down, and only then: `active_slot` answers `default` for a
      -- stored value it rejected, so returning here without writing would leave
      -- that value in core.lua with no way to correct it from in-game.
      if core_config().slot ~= slot then
        core_config().slot = slot
        core_handle.save()
      end
      say("'" .. slot .. "' is already the active layout slot")
      return
    end

    core_config().slot = slot
    core_handle.save()
    settings.set_slot(slot)
    -- A slot holds every component's configuration, not just its placement, so
    -- the switch is a re-attach rather than a re-index: what each component was
    -- handed on login belongs to the slot being left.
    for _, component in ipairs(registry.all()) do
      attach(component)
    end
    apply_all()
    say("layout slot '" .. slot .. "' is now active")
  end

  local function slot_create(name)
    local existing = resolve_slot(name)
    if existing then
      say("layout slot '" .. existing .. "' already exists")
      return
    end
    if #registry.all() == 0 then
      say("no components are registered, so there is nothing to put in a slot")
      return
    end

    local source = active_slot()
    -- The copy is of files, so the active slot has to be on disk first: a
    -- component that has never been written would be missing from the new slot
    -- rather than copied into it, and a slot with no files in it does not
    -- survive the listing. Every component is still attempted before giving up,
    -- so one unwritable file does not decide the rest.
    local saved = true
    for _, component in ipairs(registry.all()) do
      saved = handles[component.name].save() and saved
    end
    if not saved then
      say(("could not write the '%s' slot, so there was nothing to copy"):format(source))
      return
    end

    local character = settings.character()
    local copied, failed = copy_tree(character_dir(character) .. "/" .. source, character_dir(character) .. "/" .. name)
    if failed > 0 then
      say(("%d file(s) could not be copied into '%s'; %d were"):format(failed, name, copied))
      say(("  '//hud slot delete %s' to start over"):format(name))
      return
    end
    -- The saves above succeeded, so an empty copy means the source could not be
    -- read. Claiming success would name a slot that never appears in the list.
    if copied == 0 then
      say(("nothing was copied into '%s' - the '%s' slot could not be read"):format(name, source))
      return
    end
    say(("layout slot '%s' created from '%s' - '//hud slot %s' to switch to it"):format(name, source, name))
  end

  local function slot_delete(name)
    local slot = resolve_slot(name)
    if not slot then
      say("no layout slot named '" .. name .. "'")
      return
    end
    if slot:lower() == "default" then
      say("the 'default' layout slot cannot be deleted")
      return
    end
    if same_slot(slot, active_slot()) then
      say("'" .. slot .. "' is the active layout slot - switch to another one first")
      return
    end

    delete_tree(character_dir(settings.character()) .. "/" .. slot)
    say("layout slot '" .. slot .. "' deleted")
  end

  local function run_slot(action)
    if action.op == "list" then
      say_slots()
    elseif action.op == "create" then
      slot_create(action.name)
    elseif action.op == "delete" then
      slot_delete(action.name)
    else
      slot_switch(action.name)
    end
  end

  --[[ Copying another character's configuration ---------------------------- ]]

  -- Every character with saved configuration. Both ends of a copy are named
  -- explicitly, so the character being played is no longer a special case.
  local function character_dirs()
    local names = {}
    for _, entry in ipairs((deps.list_dir and deps.list_dir("data")) or {}) do
      if entry ~= "." and entry ~= ".." and deps.is_dir(character_dir(entry)) then
        names[#names + 1] = entry
      end
    end
    table.sort(names)
    return names
  end

  local function resolve_character(name, known)
    for _, entry in ipairs(known) do
      if entry:lower() == name:lower() then
        return entry
      end
    end
    return nil
  end

  -- `//hud copy <source> <destination>` replaces the destination outright: its
  -- tree is emptied before the copy, so what remains is the source's
  -- configuration and nothing else. There is no undo.
  local function run_copy(action)
    -- Defence in depth. The parser already rejects these, but this deletes a
    -- directory tree, and "the caller validated it" is not a good enough reason
    -- to hand an unchecked string to delete_tree.
    for _, name in ipairs({ action.source, action.destination }) do
      if type(name) ~= "string" or not name:match("^[%w_]+$") then
        say("'" .. tostring(name) .. "' is not a character name")
        return
      end
    end

    local known = character_dirs()

    local source = resolve_character(action.source, known)
    if not source then
      say("no saved configuration for '" .. action.source .. "'")
      say(#known == 0 and "  no character has saved configuration yet" or ("  known: " .. table.concat(known, ", ")))
      return
    end

    -- The destination need not exist yet; that is half the point.
    local destination = resolve_character(action.destination, known) or action.destination
    if source:lower() == destination:lower() then
      say("'" .. source .. "' is the same character at both ends")
      return
    end

    local removed = delete_tree(character_dir(destination))
    local copied, failed = copy_tree(character_dir(source), character_dir(destination))

    -- Only the character being played has anything loaded to refresh.
    local character = settings.character()
    if character and destination:lower() == character:lower() then
      settings.reload()
      -- The copied core.lua can name a different slot, and the components were
      -- just re-read under the old one; announcing it puts them in the right
      -- directory.
      settings.set_slot(active_slot())
      apply_settings(character)
    end

    if failed > 0 then
      say(("%d file(s) could not be copied from %s to %s; %d were"):format(failed, source, destination, copied))
      say(("  %s's configuration is now incomplete - '//hud reset all' starts over"):format(destination))
      return
    end

    say(("copied %d file(s) from %s to %s, replacing %d"):format(copied, source, destination, removed))
  end

  local function run(action)
    if action.action == "help" then
      for _, line in ipairs(HELP) do
        say(line)
      end
    elseif action.action == "error" then
      say(action.message)
    elseif action.action == "layout" then
      if require_character() then
        set_layout_mode(not layout_mode.active())
        say(layout_mode.active() and "layout mode on - //hud layout again when you are done" or "layout mode off")
      end
    elseif action.action == "list" then
      local components = registry.all()
      if #components == 0 then
        say("no components registered")
        return
      end
      say("XIVHud components:")
      for _, component in ipairs(components) do
        for _, line in ipairs(describe(component)) do
          say(line)
        end
      end
    elseif action.action == "show" or action.action == "hide" then
      if require_character() then
        set_visible(registry.get(action.component), action.action == "show")
      end
    elseif action.action == "reset" then
      if require_character() then
        if action.component == "all" then
          for _, component in ipairs(registry.all()) do
            reset(component)
          end
          say("all components reset to defaults")
        else
          reset(registry.get(action.component))
          say(action.component .. " reset to defaults")
        end
      end
    elseif action.action == "slot" then
      if require_character() then
        run_slot(action)
      end
    elseif action.action == "copy" then
      run_copy(action)
    elseif action.action == "component" then
      if not require_character() then
        return
      end
      local component = registry.get(action.component)
      if not component.handle_command then
        say(component.name .. " takes no commands")
        return
      end
      -- A list, because a component whose answer is an ordering or a search
      -- result has nowhere to put it in one line, and FFXI's chat ignores \n.
      local reply = component.handle_command(action.args)
      if type(reply) == "table" then
        for _, line in ipairs(reply) do
          say(line)
        end
      elseif reply then
        say(reply)
      end
    end
  end

  function self.on_command(args)
    run(commands.parse(args))
  end

  return self
end

return new
