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

--[[ XIVHud entry point. See CLAUDE.md > Modular design & testing.

     This is the ONLY file allowed to touch Windower globals. It builds a plain
     `deps` table from the live API, hands it to lib/core (the framework), wires
     the components, and registers the Windower events. Everything worth testing
     lives in lib/ and components/, which is why this file holds no logic of its
     own beyond adapting one API shape to another.

     Prims are the main adapter: Windower's texts/images objects use method
     syntax (`t:pos(x, y)`), while components are handed plain tables of
     functions so specs can pass recorders instead. ]]

_addon.name = "XIVHud"
_addon.author = "Azureblood2"
_addon.version = "0.1.0"
-- Redundant, and knowingly so. Both were set while chasing an addon that
-- answered no commands; the cause proved to be elsewhere, so which field
-- Windower honours here was never established. The convention is
-- `_addon.commands` alone (all but one addon in the repository picks one field
-- or the other), and dropping `_addon.command` needs a live client to confirm
-- `//hud` still routes -- which is the only reason it is still here.
_addon.command = "hud"
_addon.commands = { "hud", "xivhud" }

local CHAT_COLOR = 207
-- Plain white square, tinted and stretched for the layout-mode highlight.
local OVERLAY_TEXTURE = "assets/own/overlay.png"

local core

local function chat(message)
  windower.add_to_chat(CHAT_COLOR, "[XIVHud] " .. message)
end

-- Component-initiated chat, one line or a list, with the standard prefix.
-- Command replies already ride core's reply path; this is for the messages no
-- command is in flight for - a keypress hint, a binder echo.
local function say(lines)
  if type(lines) == "table" then
    for _, line in ipairs(lines) do
      chat(line)
    end
  else
    chat(lines)
  end
end

--[[ Load trace, written straight to <addon>/load.log with raw io.

     Chat is not a reliable diagnostic channel here: if the main chunk dies
     before its handlers register, the addon is silent no matter what it wanted
     to say, and a client that then crashes takes the console with it. This uses
     nothing but `io`, so it works before any library has loaded and survives
     the process going down. The last line in the file is the last thing that
     ran. ]]
local function trace(message, mode)
  pcall(function()
    local file = io.open(windower.addon_path .. "load.log", mode or "a")
    if not file then
      return
    end
    file:write(os.date("%Y-%m-%d %H:%M:%S ") .. message .. "\n")
    file:close()
  end)
end

trace("---- chunk started, version " .. _addon.version, "w")
-- Where the addon thinks it lives decides where data/ is written.
trace("addon_path    = " .. tostring(windower.addon_path))
trace("windower_path = " .. tostring(windower.windower_path))

-- Safe mode: drop an empty file named `safe_mode` beside this one and the addon
-- loads the framework and its commands but registers no component and no render
-- loop. It is the one bisect available without working commands — if the client
-- still dies in safe mode the fault is not in the drawing code.
local safe_mode = false
pcall(function()
  local file = io.open(windower.addon_path .. "safe_mode", "r")
  if file then
    file:close()
    safe_mode = true
  end
end)

if safe_mode then
  trace("SAFE MODE: no component, no render loop")
end

-- Loading is done in isolated steps. An addon whose main chunk dies part way
-- registers none of its events, so it answers no commands and cannot be
-- diagnosed from inside the game -- the worst possible failure. Instead each
-- step records why it failed, and the command handler below reports it.
local load_error = nil

local function step(description, fn)
  if load_error then
    trace("skipped " .. description .. " (already failed)")
    return nil
  end

  trace("begin " .. description)
  local ok, result = pcall(fn)
  if ok then
    trace("  ok   " .. description)
    return result
  end

  load_error = description .. ": " .. tostring(result)
  trace("  FAIL " .. load_error)
  return nil
end

-- Windower's own libraries, stored in the globals they are conventionally
-- assigned to.
-- `files` is deliberately absent: config I/O uses raw io (see below).
step("loading the Windower libraries", function()
  texts = require("texts")
  images = require("images")
end)

--[[ The resource and packet libraries are the party list's alone, and this is
     deliberately not a `step`: a step failure sets load_error, which skips the
     framework, parambar and every handler after it. A broken resources install
     should cost the user the party list, not the whole addon -- so this records
     its own failure and the party list is simply not registered. ]]
local libraries_error = nil
do
  local ok, err = pcall(function()
    res = require("resources")
    packets = require("packets")
  end)
  if not ok then
    libraries_error = tostring(err)
    trace("resources/packets unavailable: " .. libraries_error)
  end
end

-- The enchanted-item decoder, for the crossbar's auto-warp (CB5). Optional for
-- the same reason as above: without it the warp ladder loses its item rungs,
-- not the addon. Kept local - nothing else reads it, so no global convention.
local extdata = nil
do
  local ok, lib = pcall(require, "extdata")
  if ok then
    extdata = lib
  else
    trace("extdata unavailable: " .. tostring(lib))
  end
end

local new_guard = step("loading lib/guard", function()
  return require("lib/guard")
end)
local new_core = step("loading lib/core", function()
  return require("lib/core")
end)
local new_player_service = step("loading lib/player", function()
  return require("lib/player")
end)
local new_parambar = step("loading the parambar component", function()
  return require("components/parambar/parambar")
end)
local new_partylist = step("loading the partylist component", function()
  return require("components/partylist/partylist")
end)
-- The ids `incoming chunk` below pre-parses once for the party list. Loaded as
-- its own step because a missing file here would otherwise take the whole
-- chunk down.
local partylist_packets = step("loading the partylist packet parsers", function()
  return require("components/partylist/packets")
end)

local new_statusbar = step("loading the statusbar component", function()
  return require("components/statusbar/statusbar")
end)
local new_giltracker = step("loading the giltracker component", function()
  return require("components/giltracker/giltracker")
end)
local new_equipviewer = step("loading the equipviewer component", function()
  return require("components/equipviewer/equipviewer")
end)
local new_targetbar = step("loading the targetbar component", function()
  return require("components/targetbar/targetbar")
end)
local new_crossbar = step("loading the crossbar component", function()
  return require("components/crossbar/crossbar")
end)
local new_speedcheck = step("loading the speedcheck component", function()
  return require("components/speedcheck/speedcheck")
end)
local new_expbar = step("loading the expbar component", function()
  return require("components/expbar/expbar")
end)

-- Every Windower handler goes through this, so a bug degrades to a message and
-- a dead handler rather than an unexplained freeze.
local guard = new_guard and new_guard({ notify = chat }) or nil

--[[ Mouse and keyboard handlers. Historically these existed only while layout
     mode was on; a component that consumes input (the crossbar) needs its
     handler for as long as the addon runs, so each is registered on demand
     and marked permanent when a component asked for it - layout mode then
     registers whatever is not already there and releases only that. Both fall
     back to false: a handler that dies must never keep swallowing the
     player's mouse and keyboard, which is indistinguishable from a hang. ]]
local mouse_event_id, keyboard_event_id
local mouse_permanent, keyboard_permanent = false, false

local function register_mouse()
  if not mouse_event_id then
    mouse_event_id = windower.register_event(
      "mouse",
      guard.wrap("mouse", function(mouse_type, x, y, delta, blocked)
        return core.on_mouse(mouse_type, x, y, delta, blocked)
      end, false)
    )
  end
end

local function register_keyboard()
  if not keyboard_event_id then
    -- The full signature. `flags` and the inbound `blocked` used to be
    -- dropped here, and a component's inbound-blocked guard needs them.
    keyboard_event_id = windower.register_event(
      "keyboard",
      guard.wrap("keyboard", function(key, down, flags, blocked)
        return core.on_keyboard(key, down, flags, blocked)
      end, false)
    )
  end
end

local function release_input(everything)
  if mouse_event_id and (everything or not mouse_permanent) then
    windower.unregister_event(mouse_event_id)
    mouse_event_id = nil
  end
  if keyboard_event_id and (everything or not keyboard_permanent) then
    windower.unregister_event(keyboard_event_id)
    keyboard_event_id = nil
  end
end

local function set_input_capture(on)
  if on then
    register_mouse()
    register_keyboard()
  else
    release_input(false)
  end
end

--[[ Config I/O deliberately does not use the `files` library.

     `files.write` on a missing file calls `create()`, which calls
     `create_path()` and then **ignores its error**, so a directory that could
     not be created is reported as "New file: ..." and then dies indexing a nil
     handle. That is exactly what happened here: load.log, which sits directly
     in the addon folder and is written with raw io, appeared every time, while
     a component's config -- directories deep under data/ -- never did.

     So the directories are built explicitly, the result of every step is
     checked, and the file is written with plain io. ]]

local function read_file(path)
  local file = io.open(windower.addon_path .. path, "r")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  return contents
end

-- Builds `data`, then `data/Character`, ... reporting the first one that fails
-- rather than pressing on to a write that cannot succeed.
local function ensure_dir(relative_dir)
  local built = windower.addon_path
  for segment in relative_dir:gmatch("[^/\\]+") do
    built = built .. segment .. "/"
    if not windower.dir_exists(built) then
      local created, err = windower.create_dir(built)
      trace(("create_dir %s -> %s%s"):format(built, tostring(created), err and (" (" .. tostring(err) .. ")") or ""))
      if not created then
        return false, "could not create " .. built .. (err and (": " .. err) or "")
      end
      -- create_dir can report success without the directory being usable.
      if not windower.dir_exists(built) then
        trace("create_dir claimed success but " .. built .. " still does not exist")
        return false, built .. " could not be created (reported success, but is not there)"
      end
    end
  end
  return true
end

local function write_file(path, contents)
  local directory = path:match("^(.*)[/\\][^/\\]*$")
  if directory then
    local ok, err = ensure_dir(directory)
    if not ok then
      trace("write failed: " .. tostring(err))
      return false, err
    end
  end

  local file, err = io.open(windower.addon_path .. path, "w")
  if not file then
    trace("write failed: could not open " .. path .. ": " .. tostring(err))
    return false, err
  end

  file:write(contents)
  file:close()
  return true
end

--[[ The same write for a file that is not text. The mode matters: "w" is a
     text stream, and on Windows every 0x0A byte in it becomes 0x0D 0x0A - which
     would corrupt roughly one byte in sixty of an extracted icon and leave the
     prim layer with a bitmap it cannot parse. Nothing else differs, so the
     directory handling above is reused. ]]
local function write_binary(path, contents)
  local directory = path:match("^(.*)[/\\][^/\\]*$")
  if directory then
    local ok, err = ensure_dir(directory)
    if not ok then
      trace("binary write failed: " .. tostring(err))
      return false, err
    end
  end

  local file, err = io.open(windower.addon_path .. path, "wb")
  if not file then
    trace("binary write failed: could not open " .. path .. ": " .. tostring(err))
    return false, err
  end

  file:write(contents)
  file:close()
  return true
end

--[[ Whether a path is a readable file. Unlike the helpers above, the path is
     absolute rather than addon-relative: the icon cache is composed by the
     component through `asset`, and the DAT reads below are outside the addon
     directory entirely.

     `windower.file_exists` would say the
     same, but nothing in this addon has ever called it, and CLAUDE.md's rule
     is that raw io against a path is the one file operation proven to work
     here. The cost of being wrong is not small: this is called from the
     component's attach, and core attaches every component in one unprotected
     loop, so a throw would leave the party lists and the target bar
     unattached too. ]]
local function file_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

--[[ A slice of a file outside the addon directory: the client's own item DATs,
     which equipviewer reads icons out of.

     Behind a pcall because the path comes from a setting or from Windower's
     idea of where the game is installed, and neither is something this addon
     controls. A read that throws here would reach the per-frame handler that
     drives the extraction queue. ]]
local function read_dat(path, offset, length)
  local ok, contents = pcall(function()
    local file = assert(io.open(path, "rb"))
    file:seek("set", offset)
    local slice = file:read(length)
    file:close()
    return slice
  end)
  return ok and contents or nil
end

-- Directory enumeration for `//hud copy`, which walks another character's
-- data/ tree. get_dir returns files and directories alike, so entries are
-- classified with dir_exists. lib/core expects bare entry names; the trailing
-- match strips a leading path in case get_dir hands back full ones.
local function list_dir(path)
  local entries = windower.get_dir(windower.addon_path .. path)
  if not entries then
    return nil
  end

  local names = {}
  for index, entry in ipairs(entries) do
    names[index] = entry:match("([^/\\]+)[/\\]?$") or entry
  end
  return names
end

local function is_dir(path)
  return windower.dir_exists(windower.addon_path .. path)
end

-- Used by `//hud copy` to empty the destination first. os.remove deletes files;
-- on a directory it simply fails, which is fine -- an empty directory left
-- behind changes nothing.
local function delete_file(path)
  return os.remove(windower.addon_path .. path) and true or false
end

local function wrap_image()
  local image = images.new({ draggable = false })
  return {
    pos = function(x, y)
      image:pos(x, y)
    end,
    size = function(width, height)
      image:size(width, height)
    end,
    path = function(texture)
      image:path(texture)
    end,
    fit = function(on)
      image:fit(on)
    end,
    repeat_xy = function(x, y)
      image:repeat_xy(x, y)
    end,
    draggable = function(on)
      image:draggable(on)
    end,
    color = function(red, green, blue)
      image:color(red, green, blue)
    end,
    alpha = function(alpha)
      image:alpha(alpha)
    end,
    show = function()
      image:show()
    end,
    hide = function()
      image:hide()
    end,
    destroy = function()
      image:destroy()
    end,
  }
end

local function wrap_text()
  local text = texts.new({ flags = { draggable = false } })
  return {
    pos = function(x, y)
      text:pos(x, y)
    end,
    size = function(font_size)
      text:size(font_size)
    end,
    text = function(value)
      text:text(value)
    end,
    font = function(name)
      text:font(name)
    end,
    color = function(red, green, blue)
      text:color(red, green, blue)
    end,
    alpha = function(alpha)
      text:alpha(alpha)
    end,
    stroke_width = function(width)
      text:stroke_width(width)
    end,
    stroke_color = function(red, green, blue)
      text:stroke_color(red, green, blue)
    end,
    -- stroke_alpha, not stroke_transparency: the library reads transparency as
    -- 0..1 and would turn an alpha of 150 into a wildly negative value.
    stroke_alpha = function(alpha)
      text:stroke_alpha(alpha)
    end,
    bg_visible = function(on)
      text:bg_visible(on)
    end,
    bg_color = function(red, green, blue)
      text:bg_color(red, green, blue)
    end,
    bg_alpha = function(alpha)
      text:bg_alpha(alpha)
    end,
    -- The argument is required: texts.right_justified() with none is a getter.
    right_justified = function(on)
      text:right_justified(on)
    end,
    italic = function(on)
      text:italic(on)
    end,
    bold = function(on)
      text:bold(on)
    end,
    draggable = function(on)
      text:draggable(on)
    end,
    show = function()
      text:show()
    end,
    hide = function()
      text:hide()
    end,
    destroy = function()
      text:destroy()
    end,
  }
end

local function screen()
  local settings = windower.get_windower_settings()
  return settings.ui_x_res, settings.ui_y_res
end

local function get_player()
  return windower.ffxi.get_player()
end

-- A dep of the player service below, which is what every component gets handed
-- instead: nothing here reaches a component directly any more.
-- Argument-agnostic: the skillchain engine reads the fallback pair
-- ('t', 'bt'), the other consumers a single kind - a wrapper must not
-- narrow the API's arity.
local function get_mob_by_target(...)
  return windower.ffxi.get_mob_by_target(...)
end

local function get_party()
  return windower.ffxi.get_party()
end

local function get_info()
  return windower.ffxi.get_info()
end

--[[ One read of the client per interval, shared by every component, and the one
     place the two vitals streams are reconciled -- see lib/player. The four
     accessors above are its deps, and no COMPONENT gets them: what each ctx
     below gets is the service's getters, so a component cannot reach past it.
     Core is the exception, and takes the raw `get_player` for the reason given
     where its deps are built.

     `player_service` is nil only when its own load step failed, in which case
     `load_error` is set and nothing below this point builds a ctx, registers a
     handler or draws. ]]
local player_service = step("building the player service", function()
  -- No nil check on new_player_service: if its own load step failed, load_error
  -- is set and step() never calls this at all. Were it somehow nil, the call
  -- below would throw inside the step and become a reported load failure, which
  -- is the outcome a check would have to produce anyway.
  return new_player_service({
    now = os.clock,
    get_player = get_player,
    get_party = get_party,
    get_info = get_info,
    get_mob_by_target = get_mob_by_target,
  })
end)

-- All nil together, and only when the service's own load step failed - which
-- sets `load_error`, and nothing past that point builds a ctx or registers a
-- handler. A raw fallback here would read as safety it does not provide.
local read_player = player_service and player_service.get_player
local read_party = player_service and player_service.get_party
local read_info = player_service and player_service.get_info
local read_mob_by_target = player_service and player_service.get_mob_by_target
local read_generation = player_service and player_service.generation

local function asset(relative_path)
  return windower.addon_path .. relative_path
end

-- get_items() pushes every item the character owns, so this is called only when
-- a packet says gil may have moved -- never on a timer. It comes back empty
-- before the inventory has loaded.
--
-- The documented signature takes an integer bag id; the reference addon passes
-- the string 'gil' instead, which evidently works but is undocumented, and
-- whether it skips materialising the whole table is not something this
-- container can answer. The documented form is used until a live client says
-- the other is worth it.
local function get_gil()
  local items = windower.ffxi.get_items()
  return items and items.gil
end

-- Which bag and index each equipment slot is wearing - not the items
-- themselves, which take a read apiece. Read once per refresh; the reference
-- addon called this once per slot.
local function get_equipment()
  local items = windower.ffxi.get_items()
  return items and items.equipment
end

local function get_item(bag, index)
  return windower.ffxi.get_items(bag, index)
end

--[[ Where the client is installed, for the DAT reads above. Undocumented, and
     the reason the setting exists to override it: the wiki documents
     `pol_path` ("path to playonline and ffxi install directory") but not
     `ffxi_path`, which is what the reference addon uses and what its DAT
     offsets were derived against. Prefer it, fall back to the documented one,
     and let the player name a third. ]]
local function game_path()
  return windower.ffxi_path or windower.pol_path
end

-- Behind a pcall because this runs on inbound packets: a throw here would
-- propagate into the shared `incoming chunk` handler, and guard disables that
-- after five failures for the rest of the session -- after which gil would
-- silently stop updating. A component already has to treat a nil packet as a
-- real case, so failing to nil costs nothing.
local function parse_packet(data)
  local ok, packet = pcall(packets.parse, "incoming", data)
  return ok and packet or nil
end

-- Windower's own parser for the 0x028 action packet - core API, not a
-- library, so it is available even when resources/packets failed to load.
-- Same pcall reasoning as parse_packet: this too runs on inbound packets.
-- The index happens INSIDE the closure: pcall(windower.packets.parse_action,
-- data) evaluates the index before the protected call, so a missing
-- windower.packets would throw straight into the shared chunk handler.
local function parse_action(data)
  local ok, act = pcall(function()
    return windower.packets.parse_action(data)
  end)
  return ok and act or nil
end

--[[ The last packet the client sent with this id, for the exp bar: it is
     attached on login and on every slot switch, and neither 0x061 nor 0x063 is
     re-sent on request. Core API, like parse_action, and indexed INSIDE the
     closure for the same reason - `pcall(windower.packets.last_incoming, id)`
     would evaluate the index before the protected call. Only the data is
     passed on; the timestamp beside it is the client's, not the addon's. ]]
local function last_incoming(id)
  local ok, data = pcall(function()
    return windower.packets.last_incoming(id)
  end)
  return ok and data or nil
end

-- Whether the chat box has focus, for the crossbar's chat guard. Runs on
-- every key event inside a guarded handler, so it must be nil-tolerant by
-- construction - an input spike once died on exactly this call unguarded.
--[[ Deliberately NOT through the player service: this is asked on every key
     event to decide whether a key belongs to the game's chat box or to the
     crossbar, and a verdict up to an interval old would swallow the first
     keystrokes after a chat line opens or closes.

     Not the only raw get_info caller: core's `logged_in` below is another, and
     for its own reason - core's login scoping polls it while nothing is scoped
     yet, which is the visible delay before the HUD comes up. ]]
local function chat_open()
  local ok, info = pcall(function()
    return windower.ffxi.get_info()
  end)
  return ok and info ~= nil and info.chat_open == true
end

-- Everything from here on can fail on a broken install, so each part is a step
-- and the command handler is registered regardless of how they go.
local command_handler = nil

step("building the framework", function()
  core = new_core({
    read_file = read_file,
    write_file = write_file,
    list_dir = list_dir,
    is_dir = is_dir,
    delete_file = delete_file,
    --[[ Core scopes a character from its own prerender search, not from the
         `login` event, so the event's invalidation is not enough on its own:
         between the two, the outgoing character's components are still attached
         and still reading, and they refill the cache. This drops it at the
         moment the scope actually moves. ]]
    on_scope_change = function()
      player_service.invalidate()
    end,
    --[[ The raw read, deliberately not the service's. Core re-reads the player
         every 0.05s while a login is under way, and that retry is the visible
         delay before the HUD comes up; a 200ms cache in front of it would
         answer three of every four attempts from the same stale nil. Once a
         character is scoped it makes no calls at all, so there is nothing to
         save here either. ]]
    get_player = get_player,
    logged_in = function()
      return windower.ffxi.get_info().logged_in
    end,
    screen = screen,
    now = os.clock,
    chat = chat,
    set_input_capture = set_input_capture,
    new_image = wrap_image,
    new_text = wrap_text,
    overlay_texture = function()
      return windower.addon_path .. OVERLAY_TEXTURE
    end,
  })
end)

-- Components are wired explicitly — no directory scanning — so the set of
-- registered components is always readable from here.
step("building the parambar component", function()
  if safe_mode then
    return
  end
  core.register(new_parambar({
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    get_player = read_player,
    asset = asset,
  }))
end)

step("building the giltracker component", function()
  -- parse_packet calls packets.parse; without the library loaded there is
  -- nothing useful this component could do with a chunk anyway.
  if safe_mode or libraries_error then
    return
  end
  core.register(new_giltracker({
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    get_gil = get_gil,
    parse_packet = parse_packet,
    asset = asset,
  }))
end)

--[[ Gated on safe_mode alone, like parambar: the movement speed is one field
     of the mob table, so nothing here needs the resource or packet
     libraries. ]]
step("building the speedcheck component", function()
  if safe_mode then
    return
  end
  core.register(new_speedcheck({
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    get_mob_by_target = read_mob_by_target,
    generation = read_generation,
    asset = asset,
  }))
end)

step("building the equipviewer component", function()
  -- Same gate as giltracker: everything this component learns arrives through
  -- parse_packet, and without the packets library there is nothing it could
  -- find out about what is equipped.
  if safe_mode or libraries_error then
    return
  end
  core.register(new_equipviewer({
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    asset = asset,
    get_equipment = get_equipment,
    get_item = get_item,
    parse_packet = parse_packet,
    file_exists = file_exists,
    read_dat = read_dat,
    write_binary = write_binary,
    game_path = game_path,
  }))
end)

--[[ Gated on safe_mode alone, like parambar and unlike the two components
     that also take libraries_error.

     The party list and the gil tracker are useless without the resource and
     packet libraries, so a failure there skips them wholesale. The target bar
     is not: its health bar, name and distance read the mob table directly and
     need no library at all. ]]
step("building the targetbar component", function()
  if safe_mode then
    return
  end
  core.register(new_targetbar({
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    asset = asset,
    now = os.clock,
    get_player = read_player,
    get_mob_by_target = read_mob_by_target,
    get_party = read_party,
    generation = read_generation,
    -- nil when the resource library failed to load: the cast bar then never
    -- shows, and the health bar, name and distance carry on without it.
    resources = libraries_error == nil and res or nil,
  }))
end)

-- One component over three lists: the main party and the two alliance parties,
-- each placed independently through an anchor of its own (`main`, `alliance1`,
-- `alliance2`), sharing one config file and one `visible` flag.
step("building the party list component", function()
  if safe_mode or libraries_error then
    return
  end
  core.register(new_partylist({
    name = "partylist",
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    asset = asset,
    resources = res,
    get_player = read_player,
    get_party = read_party,
    generation = read_generation,
    get_mob_by_target = read_mob_by_target,
    get_info = read_info,
  }))
end)

--[[ The status bar: the player's own buffs and debuffs on three anchored bars
     (`bar1`, `bar2`, `bar3`). Presence comes off the player service; the
     expiries ride the 0x063 chunk, which the chunk handler below pre-parses
     once for its three readers. The wall clock is what the packet's
     timestamps count in.

     Gated on safe_mode alone, targetbar's rule: the icons draw by id and the
     packet arrives parsed, so the resources only ever name a buff in a
     command's answer - without them it says `buff 33` instead. What a
     libraries failure DOES cost it is the timers: the `incoming chunk`
     handler below is registered only with the libraries up - and this one
     is not too wide a gate for it, the pre-parse being packets.parse - so
     the bar then draws icons with no time under them. ]]
step("building the statusbar component", function()
  if safe_mode then
    return
  end
  core.register(new_statusbar({
    name = "statusbar",
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    asset = asset,
    resources = libraries_error == nil and res or nil,
    get_player = read_player,
    time = os.time,
    -- The seed at attach: the last 0x063 the client sent, parsed the same
    -- way the chunk handler parses it - timers after a reload.
    last_incoming = last_incoming,
    parse_packet = parse_packet,
    -- A right-click on an icon asks the cancel addon to drop the buff.
    send_command = function(command)
      windower.send_command(command)
    end,
  }))
end)

--[[ The crossbar, live since CB5: all three bars drawn, slot presses
     executing their bound actions through the ctx below (recasts, key
     items, extdata, IPC...). Every windower call here is wrapped in a
     closure, so an API this container cannot verify is not touched until
     the component actually asks. ]]
step("building the crossbar component", function()
  if safe_mode then
    return
  end
  -- The ctx's `random` feeds mount roulette; unseeded, Lua's generator would
  -- deal the same mount sequence every client start.
  math.randomseed(os.time())
  core.register(new_crossbar({
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    asset = asset,
    now = os.clock,
    -- Wall clock for the warp machine: extdata timestamps are os.time
    -- offsets, which the monotonic os.clock cannot answer.
    time = os.time,
    say = say,
    chat_open = chat_open,
    --[[ The zone id, for the crossbar's mount rule (res.zones carries
         `can_mount`). Read while drawing, so it goes through the service: this
         was the heaviest get_info caller in the addon, once a frame. A zone id
         is safe to hold for an interval, and `zone change` invalidates anyway.
         Nil-tolerant like chat_open. ]]
    zone = function()
      local ok, info = pcall(read_info)
      return ok and info ~= nil and info.zone or nil
    end,
    suppressed = function()
      return core.suppressed()
    end,
    -- The user's own show/hide flag, which suppression never touches: the
    -- input guards rank disabled (user-hidden) above suppressed.
    component_visible = function()
      return core.component_visible("crossbar")
    end,
    layout_active = function()
      return core.layout_active()
    end,
    -- Action execution (CB5).
    send_command = function(command)
      windower.send_command(command)
    end,
    send_ipc = function(message)
      windower.send_ipc_message(message)
    end,
    -- Client state (CB5); each returns nil-tolerantly like the rest of the
    -- entry point's accessors.
    get_player = read_player,
    get_mob_by_target = read_mob_by_target,
    generation = read_generation,
    get_spell_recasts = function()
      return windower.ffxi.get_spell_recasts()
    end,
    get_ability_recasts = function()
      return windower.ffxi.get_ability_recasts()
    end,
    get_key_items = function()
      return windower.ffxi.get_key_items()
    end,
    get_spells = function()
      return windower.ffxi.get_spells()
    end,
    -- The binder's catalog (CB8): the client's own lists of job abilities
    -- and weaponskills, which is what "known" means for those.
    get_abilities = function()
      return windower.ffxi.get_abilities()
    end,
    -- Argument-agnostic: the widget reads whole bags and, through the warp
    -- machine, could grow an index argument - a wrapper must not narrow the
    -- API's arity.
    get_items = function(...)
      return windower.ffxi.get_items(...)
    end,
    -- What is in the main hand, for the weapon binding layer. The SAME
    -- accessor equipviewer takes, so the addon has one reading of the
    -- equipment table rather than two that could disagree about what an
    -- empty slot looks like.
    get_equipment = get_equipment,
    --[[ And the same decode equipviewer reads that packet with, so the
         crossbar can ask WHICH slot an Equip packet moved by field name
         rather than by an offset of its own. Not among the ids the dispatch
         pre-parses: only this component wants it, so parsing it once here
         would be a decode every other component pays for. ]]
    parse_packet = parse_packet,
    -- Argument-agnostic on purpose: set_equip's exact arity is a CB5,
    -- in-client question, and a wrapper must not encode a guess.
    set_equip = function(...)
      return windower.ffxi.set_equip(...)
    end,
    -- Behind a pcall because this runs on the prerender warp poll and the
    -- keyboard press path: extdata.decode raises (a nil item, an unknown
    -- id, a non-24-byte extdata field), and a throw there would hand guard
    -- a repeating failure until it disables the shared handler - the same
    -- posture as parse_packet and parse_action above.
    decode_extdata = function(item)
      if extdata == nil then
        return nil
      end
      local ok, ext = pcall(extdata.decode, item)
      return ok and ext or nil
    end,
    random = math.random,
    file_exists = file_exists,
    read_dat = read_dat,
    write_binary = write_binary,
    game_path = game_path,
    -- nil when the resource library failed to load: mount roulette and the
    -- catalog then sit out, the bar itself carries on.
    resources = libraries_error == nil and res or nil,
  }))
end)

--[[ Gated on libraries_error as well as safe_mode, like giltracker and the
     equip viewer: `get_player()` carries no experience and no master level, so
     everything this component draws arrives through parse_packet and there is
     nothing useful it could do without the packets library. ]]
step("building the expbar component", function()
  if safe_mode or libraries_error then
    return
  end
  core.register(new_expbar({
    new_text = wrap_text,
    new_image = wrap_image,
    screen = screen,
    asset = asset,
    now = os.clock,
    get_player = read_player,
    parse_packet = parse_packet,
    last_incoming = last_incoming,
  }))
end)

-- A component that consumes input needs its handler for as long as it is
-- registered, not just during layout mode. Decided from the registry rather
-- than hardcoded, so a component dropping out (safe mode, a failed step)
-- releases the keyboard with it.
step("registering component input handlers", function()
  keyboard_permanent = core.wants_keyboard()
  mouse_permanent = core.wants_mouse()
  if keyboard_permanent then
    register_keyboard()
  end
  if mouse_permanent then
    register_mouse()
  end
end)

-- Textures fail silently: a prim with a bad path simply draws nothing, so an
-- incomplete install looks like a broken addon. Say so at load instead.
local function check_assets()
  local missing = {}
  local expected = { OVERLAY_TEXTURE }
  for _, texture in ipairs({ "bar_bg.png", "bar_compact.png", "hp_fg.png", "mp_fg.png", "tp_fg.png" }) do
    expected[#expected + 1] = "assets/ffxiv/" .. texture
  end
  -- The party list ships some 680 textures; checking every one at load would
  -- cost 680 file opens to learn what a handful already tells us.
  for _, texture in ipairs({
    "assets/xiv/BgTopWide.png",
    "assets/xiv/BarBG.png",
    "assets/xiv/Cursor.png",
    "assets/xiv/AllyBarBG.png",
    "assets/xiv/jobIcons/frame.png",
    "assets/xiv/jobIcons/whm.png",
    "assets/xiv/buffIcons/33.png",
  }) do
    expected[#expected + 1] = texture
  end
  expected[#expected + 1] = "assets/gil/gil.png"
  -- speedcheck names one buff icon outright, so the directory sample above
  -- does not speak for it.
  expected[#expected + 1] = "assets/xiv/buffIcons/330.png"
  expected[#expected + 1] = "assets/barfiller/bar_bg.png"
  expected[#expected + 1] = "assets/barfiller/bar_fg.png"
  expected[#expected + 1] = "assets/encumbrance/encumbrance.png"
  expected[#expected + 1] = "assets/own/panel.png"
  for _, texture in ipairs({ "BarBG.png", "Bar.png", "BarFG.png", "CastBG.png", "CastBar.png", "CastFG.png" }) do
    expected[#expected + 1] = "assets/xiv/wide/" .. texture
  end
  -- The crossbar ships ~1,300 icons; same sampling rule as the party list -
  -- a few from each imported category, plus every icon a CB1 table
  -- (openers.lua, contexts.lua, actions.lua's built-ins) names outright.
  for _, texture in ipairs({
    -- Every entry here is root-relative, chrome and icons alike, because
    -- the two live under different folders and a shared prefix can only
    -- be right for one of them.
    "own/slot.png",
    "own/frame.png",
    "own/bar_bg_compact.png",
    "own/feedback.png",
    "own/red-x.png",
    "own/black-square.png",
    "own/frame_step1.png",
    "own/frame_step8.png",
    "own/indicator.png",
    "cooldown/frame_01.png",
    "cooldown/frame_16.png",
    "cooldown/frame_32.png",
    "icons/spells/00001.png",
    "icons/abilities/00005.png",
    "icons/weaponskills/sword/expiacion.png",
    "icons/weapons/sword.png",
    "icons/skillchain/light.png",
    -- elements/ is the one capitalised directory in the import.
    "icons/elements/Fire.png",
    "icons/mounts/crab.png",
    "icons/trust/kupipi.png",
    "icons/ninjutsu/utsusemi-ichi.png",
    "icons/blue-magic/cocoon.png",
    "icons/usable-item.png",
    -- The generic opener glyph and ra's art, both resolved by render.lua.
    "icons/check.png",
    "icons/ranged.png",
    -- openers.lua: every icon its entries carry.
    "icons/item.png",
    "icons/map.png",
    -- contexts.lua: the icons the roster entries name - the arts/addendum
    -- books, and BLU's job icon for unbridled (the shipped ability sheet is
    -- keyed by recast id, which nothing here can look up). Load-checked with
    -- the rest though no surface draws a roster icon yet: the field is what
    -- the roster carries, and art that is missing should say so at load
    -- rather than the day something starts drawing it.
    "icons/abilities/book_white.png",
    "icons/abilities/book_black.png",
    "icons/jobs/blu.png",
    -- actions.lua built-ins: mr, warp, and draw's three states.
    "icons/mounts/mount-roulette.png",
    "icons/spells/00261.png",
    "icons/spells/00137.png",
    "icons/spells/00136.png",
    "icons/attack.png",
    "icons/disengage.png",
    "icons/dismount.png",
    -- The sword beside the set label, which drew a bare square when its
    -- path went wrong and said nothing about it.
    "icons/weapons/sword.png",
    -- The pre-rendered job icons, XivParty art rather than the pack -
    -- their own generation step, so their own sample.
    "icons/jobs/whm.png",
  }) do
    -- The asset ROOT: these are icons, and `own/` is the chrome beside
    -- them. Prefixing the folder here sent every one of them to
    -- `assets/own/icons/...`, which exists nowhere, so the load check
    -- reported the addon folder incomplete (Kevin, live client).
    expected[#expected + 1] = "assets/" .. texture
  end

  for _, relative_path in ipairs(expected) do
    if not read_file(relative_path) then
      missing[#missing + 1] = relative_path
    end
  end

  if #missing > 0 then
    chat(("%d texture(s) are missing from this install:"):format(#missing))
    for _, relative_path in ipairs(missing) do
      chat("  " .. relative_path)
    end
    chat("  the addon folder is incomplete - re-copy every file and folder from src/")
  end

  if libraries_error then
    chat("the party list is off: Windower's resource or packet library did not load")
    chat("  " .. libraries_error)
  end
end

-- Registered before anything else could have gone wrong. An addon that answers
-- no commands cannot be diagnosed from inside the game, so //hud always replies:
-- with the failure if there was one, and normally otherwise.
windower.register_event("addon command", function(...)
  if load_error then
    chat("did not load - " .. load_error)
    return
  end
  return command_handler(...)
end)
trace("command handler registered")

if load_error then
  windower.register_event("load", function()
    trace("load event: reporting the failure")
    chat("did not load - " .. load_error)
    chat("  nothing will be drawn. Type //hud to see this again.")
  end)
  trace("---- stopped: " .. load_error)
  return
end

command_handler = guard.wrap("command", function(...)
  core.on_command({ ... })
end)

windower.register_event(
  "load",
  guard.wrap("load", function()
    trace("load event")
    check_assets()
    core.on_load()
    trace("load event done, character = " .. tostring(core.character()))
  end)
)

windower.register_event(
  "unload",
  guard.wrap("unload", function()
    core.on_unload()
    -- The permanent handlers too: nothing may stay hooked on the way out.
    release_input(true)
  end)
)

windower.register_event(
  "login",
  guard.wrap("login", function()
    -- Whoever was cached is not who is logging in.
    player_service.invalidate()
    core.on_login()
  end)
)

windower.register_event(
  "logout",
  guard.wrap("logout", function()
    -- Nothing draws once core detaches, so this is tidiness rather than a
    -- visible fix: it keeps the invalidation set complete, so the service can
    -- never hand the next reader the character who just left.
    player_service.invalidate()
    core.on_logout()
  end)
)

if not safe_mode then
  windower.register_event(
    "prerender",
    guard.wrap("prerender", function()
      -- Before core touches a component: the mob memo is good for one frame,
      -- and a component reading a target must not see the previous frame's.
      player_service.begin_frame()
      core.on_prerender()
    end)
  )
end

windower.register_event(
  "status change",
  guard.wrap("status change", function(new_status, old_status)
    --[[ Keyed, like the buff events and for the same reason: a death, a
         cutscene or resting moves the PLAYER and neither the party nor the zone
         nor any mob, so dropping the whole interval would re-read those too and
         move the counter, putting the party list through a full roster rebuild
         for a fact it does not hold.

         Ordering against core does not matter here: on_status_change reads no
         player of its own, and the one read on a re-attach takes the raw
         accessor. ]]
    player_service.invalidate("player")
    core.on_status_change(new_status, old_status)
  end)
)

windower.register_event(
  "zone change",
  guard.wrap("zone change", function()
    player_service.invalidate()
    core.on_zone_change()
  end)
)

--[[ Packets. Every chunk the client receives passes through here, so this
     handler must stay cheap: it forwards the raw bytes and each component
     decides, from the id alone, whether it is worth reading -- giltracker's
     own `logic.wants_chunk` does exactly that for item packets. It must also
     return nothing -- a returned value would be read as a modified or
     blocked packet. guard.wrap falls back to nil with no fallback argument,
     so the error path is safe too.

     The ids with a shared decode are the exception: they are parsed once
     here rather than once per consumer, and the result rides the fourth
     argument.

       - the three party-list ids Windower has a field definition for. The
         party list is one component now, but it is still three lists behind
         one name, each with its own state machine reading the same packet,
         so the decode would otherwise be redone three times over. Doing it
         here also keeps that private to the component. `PARTY_BUFFS` has no
         such definition (see packets.lua) and is decoded by the component
         itself from the raw bytes.
       - the action packet 0x028, wanted by targetbar's cast bar and by the
         crossbar's skillchain engine, which parsed it independently until
         CB6 -- two decodes of the same packet on every action in a fight.
         `windower.packets.parse_action` decodes it, not `packets.parse`:
         it is core API rather than a library, and the only thing that reads
         0x028's shape.

     A component still decides from the id alone whether the packet is worth
     reading; `parsed` is nil for every other id, and nil for these too when
     the parse failed (parse_action is pcall'd above, and a component already
     has to treat a nil packet as a real case).

     Guarded on `libraries_error`, not just `safe_mode`: the party-list
     pre-parse and giltracker's `parse_packet` both call into the `packets`
     library, which failed to load in that case. Components receive the event
     as `update('chunk', id, original, parsed)` and are free to ignore it --
     parambar does.

     That gate is too wide, and knowingly so (issue #14): the cast bar and the
     skillchain engine need no library -- parse_action is core API -- yet a
     missing `packets` takes the whole handler down and leaves both silent.
     Pre-existing, and not this change's to fix. ]]
if not safe_mode and not libraries_error then
  local ACTION_CHUNK = 0x028
  --[[ 0x063, the character update: one id over several orders, and three
       readers - the crossbar's skillchain engine (order 9's buff ids), expbar
       (order 2's limit points and merits) and the status bar (order 9's ids
       with their expiries). Windower's field definition for it switches on
       the order byte, so one packets.parse serves every order and every
       reader; until 2026-09-04 each of the three decoded it again. ]]
  local CHAR_UPDATE_CHUNK = 0x063
  local structured = partylist_packets
      and {
        [partylist_packets.ALLIANCE] = true,
        [partylist_packets.PARTY_MEMBER] = true,
        [partylist_packets.CHAR] = true,
        [CHAR_UPDATE_CHUNK] = true,
      }
    or { [CHAR_UPDATE_CHUNK] = true }
  windower.register_event(
    "incoming chunk",
    guard.wrap("incoming chunk", function(id, original)
      local parsed = nil
      if id == ACTION_CHUNK then
        parsed = parse_action(original)
      elseif structured[id] then
        -- pcall'd, like parse_action: a packet the library cannot read is a
        -- nil `parsed` with the bytes still dispatched, never a handler
        -- failure that guard would count towards disabling the whole thing.
        parsed = parse_packet(original)
      end
      core.dispatch("chunk", id, original, parsed)
    end)
  )

  -- Gil entering or leaving a bag is the cheap signal that something moved; the
  -- expensive read waits for the inventory to settle.
  for _, movement in ipairs({ "add item", "remove item" }) do
    windower.register_event(
      movement,
      guard.wrap(movement, function(_bag, _index, id)
        core.dispatch(movement, id)
      end)
    )
  end
end

--[[ FFXI reports vitals as two independent streams, absolute and percent. Each
     value goes to the player service first, which lays it over the cached
     player until the next read of the client overrules it -- so every component
     asking `get_player()` sees one answer rather than three reconciliations.
     They are still dispatched as well: a component that wants the event itself,
     rather than the reconciled value, is not cut off from it. ]]
for _, vital in ipairs({ "hp", "hpp", "mp", "mpp", "tp" }) do
  windower.register_event(
    vital .. " change",
    guard.wrap(vital .. " change", function(new_value, old_value)
      player_service.set_vital(vital, new_value)
      core.dispatch(vital, new_value, old_value)
    end)
  )
end

--[[ Forwarded whole, under the event's own name: focus for the input reset
     (alt-tab mid-hold must not strand an activator), buffs for the context
     layers, `job change` for the per-job binding reload, `ipc message` for
     `warp all`. The crossbar consumes them from CB5; dispatch to components
     that ignore them costs a table walk. ]]
for _, event in ipairs({ "gain focus", "lose focus", "gain buff", "lose buff", "job change", "ipc message" }) do
  windower.register_event(
    event,
    guard.wrap(event, function(...)
      --[[ Three of these are answered out of get_player() the moment they
           arrive, so a cached read taken BEFORE the event would be read as
           "nothing changed". They are all rare, so dropping the interval costs
           nothing:

             job change - the crossbar holds it until get_player() agrees with
             the ids the event announced, retrying per frame, so a stale read
             only makes that wait an interval longer.

             gain buff / lose buff - the crossbar's context layers are a pure
             diff of get_player().buffs done once, from here. A list that does
             not yet contain the buff diffs to no change, and nothing re-syncs
             per frame, so the layer would stay wrong until the next buff
             event - minutes, on a Light Arts flip. ]]
      if event == "job change" or event == "gain buff" or event == "lose buff" then
        --[[ Keyed: none of the three changes the party or the zone, and buff
             events are frequent enough that dropping the whole interval for one
             would undo the deduplication this service exists for.

             Accepted for the job change: the crossbar's rescope retries every
             frame until get_player() agrees with the ids the event announced,
             and it now sees a fresh answer once per interval rather than once
             per frame. Its deadline is ten wall-clock seconds, so it still gets
             about fifty attempts, and the binding reload lands up to ~200ms
             later than it used to on a change that takes a menu to make. ]]
        player_service.invalidate("player")
      end
      core.dispatch(event, ...)
    end)
  )
end

trace("---- chunk finished, every handler registered")
chat("loaded - type //hud for commands")
