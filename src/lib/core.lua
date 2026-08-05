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
  "  //xh help                 this list",
  "  //xh layout               toggle layout mode: drag to move, wheel to scale,",
  "                            right-click to toggle, CTRL to ignore the grid",
  "  //xh list                 components with their state",
  "  //xh show|hide <name>     turn a component on or off",
  "  //xh reset <name|all>     restore configuration defaults",
  "  //xh slot <name>          switch layout slot",
  "  //xh slot list            layout slots, active one marked",
  "  //xh slot create <name>   new slot, copied from the active one",
  "  //xh slot delete <name>   remove a slot",
  "  //xh copy <char> confirm  overwrite this character's config with another's",
  "  //xh <name> ...           pass a command to a component",
}

local function new(deps)
  local self = {}
  local registry
  local core_handle

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
    return type(slot) == "string" and slot or CORE_DEFAULTS.slot
  end

  -- The layout a component falls back to when a slot has no entry for it.
  local function default_state_of(component)
    local defaults = component.defaults or {}
    return defaults.slots and defaults.slots.default
  end

  -- The component's layout state in the active slot, or nil while logged out.
  local function state_of(component)
    local handle = handles[component.name]
    local config = handle and handle.get()
    if not config then
      return nil
    end
    local state = layout.slot(config, active_slot(), default_state_of(component))
    -- Repair in place rather than only on the way to the prims, so `//xh list`
    -- and the next wheel step work from the same number that is on screen.
    state.scale = layout.clamp_scale(state.scale)
    return state
  end

  local function persist(component)
    local handle = handles[component.name]
    if handle then
      handle.save()
    end
  end

  -- Handed to a component on attach so it can write its *own* config after a
  -- change of its own (a `//xh <name> ...` command). Layout state is still
  -- saved by core; a component never reaches another component's handle.
  local function saver_for(component)
    return function()
      persist(component)
    end
  end

  -- Bounds are read after the position and scale have been pushed, so the
  -- highlight tracks the widget through a drag or a wheel-scale.
  local function apply_overlay(component, state)
    if not self.layout_active() or visibility.suppressed() then
      overlay.hide(component.name)
      return
    end

    local x, y, width, height = component.get_bounds()
    if not x then
      overlay.hide(component.name)
      return
    end
    overlay.show(component.name, x, y, width, height, state.visible == true)
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

    component.set_scale(state.scale)
    component.set_pos(state.pos.x, state.pos.y)

    -- A position can arrive off screen from a hand-edited file, a resolution
    -- change or `//xh copy`. Left alone, layout mode's hit test could never
    -- reach the widget again. Bounds are only known once the position and
    -- scale are on the component, hence the second set_pos.
    local bounds_x, bounds_y, width, height = component.get_bounds()
    if bounds_x then
      local x, y = layout.clamp(bounds_x, bounds_y, width, height)
      if x ~= state.pos.x or y ~= state.pos.y then
        state.pos.x, state.pos.y = x, y
        component.set_pos(x, y)
      end
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
    state = state_of,
    apply = apply,
    persist = persist,
  })

  function self.layout_active()
    return layout_mode.active()
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
      component.attach(handles[component.name].get(), saver_for(component))
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
  -- Shared by login and by `//xh copy`, which replaces the files underneath us.
  local function apply_settings(name)
    local config = core_config()
    visibility.set_logged_in(name ~= nil)
    visibility.set_hide_event(not config or config.hideCutscene ~= false)
    -- Reloading mid-cutscene must not flash the HUD back on: take the status
    -- the player is already in, rather than waiting for the next transition.
    local player = name and deps.get_player() or nil
    visibility.set_status(player and player.status or nil)

    for _, component in ipairs(registry.all()) do
      local handle = handles[component.name]
      if name then
        component.attach(handle.get(), saver_for(component))
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
      core_handle = settings.register(CORE_NAMESPACE, CORE_DEFAULTS)
    end

    -- Nothing else ever writes core's file, so create it on the first login for
    -- a character: an option the user cannot see is an option they do not have.
    if name and not deps.read_file(core_handle.path()) then
      core_handle.save()
    end

    apply_settings(name)
    return true
  end

  local function character_name()
    if deps.logged_in and not deps.logged_in() then
      return nil
    end
    local player = deps.get_player()
    local name = player and player.name
    -- The name is briefly an empty string around zone-in; scoping configs to
    -- `data//<component>.lua` on the strength of that would be worse than
    -- waiting a frame.
    if type(name) ~= "string" or name == "" then
      return nil
    end
    return name
  end

  function self.on_load()
    set_character(character_name())
  end

  function self.on_login()
    set_character(character_name())
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
    -- The `login` event can fire before get_player() has a name, so keep
    -- looking until it does. Only ever runs in the window where the client says
    -- we are logged in but no config has been loaded yet.
    if not settings.character() and deps.logged_in and deps.logged_in() then
      set_character(character_name())
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

  function self.on_mouse(mouse_type, x, y, delta, blocked)
    -- Suppression outranks layout mode, so nothing is on screen to grab.
    if blocked or visibility.suppressed() then
      return false
    end
    return layout_mode.mouse(mouse_type, x, y, delta)
  end

  function self.on_keyboard(key, down)
    layout_mode.key(key, down)
    return false
  end

  local function require_character()
    if settings.character() then
      return true
    end
    say("log in first — XIVHud configuration is per character")
    return false
  end

  local function describe(component)
    local state = state_of(component)
    if not state then
      return "  " .. component.name .. " — not loaded"
    end
    return string.format(
      "  %s — %s, pos %d,%d, scale %.2f",
      component.name,
      state.visible == true and "shown" or "hidden",
      state.pos.x,
      state.pos.y,
      state.scale
    )
  end

  local function set_visible(component, visible)
    local state = state_of(component)
    state.visible = visible
    persist(component)
    apply(component)
  end

  local function reset(component)
    local handle = handles[component.name]
    handle.reset()
    component.attach(handle.get(), saver_for(component))
    apply(component)
  end

  --[[ Layout slots ------------------------------------------------------- ]]

  -- Slots live in each component's own config, so the set of slots is their
  -- union. `default` and the active slot always count, even before any
  -- component has written an entry for them.
  local function slot_names()
    local seen, names = {}, {}
    local function add(name)
      if not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end

    for _, component in ipairs(registry.all()) do
      local handle = handles[component.name]
      local config = handle and handle.get()
      if config then
        for _, name in ipairs(layout.slot_names(config)) do
          add(name)
        end
      end
    end
    add("default")
    add(active_slot())

    table.sort(names)
    for index, name in ipairs(names) do
      if name == "default" and index > 1 then
        table.remove(names, index)
        table.insert(names, 1, "default")
        break
      end
    end
    return names
  end

  -- Config files are hand-editable, so a stored key may not be lowercase even
  -- though the parser lowercases what the user types. Returns the stored key.
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
      say("  " .. name .. (name == active_slot() and "  (active)" or ""))
    end
  end

  local function slot_switch(name)
    local slot = resolve_slot(name)
    if not slot then
      say("no layout slot named '" .. name .. "'")
      say_slots()
      return
    end

    core_config().slot = slot
    core_handle.save()
    for _, component in ipairs(registry.all()) do
      -- Reading the state creates this slot's entry if the component has none,
      -- seeded from its default slot; persist it so the fallback sticks.
      state_of(component)
      persist(component)
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
    for _, component in ipairs(registry.all()) do
      layout.create_slot(handles[component.name].get(), name, source, default_state_of(component))
      persist(component)
    end
    say(("layout slot '%s' created from '%s' — '//xh slot %s' to switch to it"):format(name, source, name))
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
    if slot == active_slot() then
      say("'" .. slot .. "' is the active layout slot — switch to another one first")
      return
    end

    for _, component in ipairs(registry.all()) do
      layout.delete_slot(handles[component.name].get(), slot)
      persist(component)
    end
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

  -- Characters with saved configuration, excluding the one being played:
  -- copying onto yourself is refused, so offering it would be noise.
  local function character_dirs(except)
    local names = {}
    for _, entry in ipairs((deps.list_dir and deps.list_dir("data")) or {}) do
      if entry ~= "." and entry ~= ".." and deps.is_dir("data/" .. entry) then
        if not except or entry:lower() ~= except:lower() then
          names[#names + 1] = entry
        end
      end
    end
    table.sort(names)
    return names
  end

  -- Copies a config tree file by file, recursing into the directories a
  -- component may claim for itself. Returns how many files were written.
  --
  -- This overlays rather than replaces: a file the target has and the source
  -- lacks is left alone. Deleting config the user did not ask us to delete is
  -- the worse failure, so the wording everywhere says "overwrites", not
  -- "replaces".
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

  local function run_copy(action)
    local character = settings.character()

    -- Checked before the source lookup, because character_dirs deliberately
    -- leaves the current character out of the list it offers.
    if action.character:lower() == character:lower() then
      say("'" .. action.character .. "' is already the character you are playing")
      return
    end

    local known = character_dirs(character)
    local source = nil
    for _, name in ipairs(known) do
      if name:lower() == action.character:lower() then
        source = name
      end
    end

    if not source then
      say("no saved configuration for '" .. action.character .. "'")
      say(
        #known == 0 and "  no other character has saved configuration yet" or ("  known: " .. table.concat(known, ", "))
      )
      return
    end
    if not action.confirmed then
      say(("'//xh copy %s confirm' overwrites %s's settings with %s's"):format(source, character, source))
      return
    end

    local copied, failed = copy_tree("data/" .. source, "data/" .. character)
    settings.reload()
    apply_settings(character)

    if failed > 0 then
      -- Half a copy is a config that is half each character's, so say so rather
      -- than reporting a number that looks like success.
      say(("%d file(s) could not be copied from %s; %d were"):format(failed, source, copied))
      say(("  %s's configuration is now a mix of both — '//xh reset all' starts over"):format(character))
      return
    end

    say(("copied %d file(s) from %s — configuration reloaded"):format(copied, source))
    say(("  anything %s has that %s does not was left as it was"):format(character, source))
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
        say(layout_mode.active() and "layout mode on — //xh layout again when you are done" or "layout mode off")
      end
    elseif action.action == "list" then
      local components = registry.all()
      if #components == 0 then
        say("no components registered")
        return
      end
      say("XIVHud components:")
      for _, component in ipairs(components) do
        say(describe(component))
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
      if require_character() then
        run_copy(action)
      end
    elseif action.action == "component" then
      if not require_character() then
        return
      end
      local component = registry.get(action.component)
      if not component.handle_command then
        say(component.name .. " takes no commands")
        return
      end
      local reply = component.handle_command(action.args)
      if reply then
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
