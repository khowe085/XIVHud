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
local OVERLAY_TEXTURE = "assets/overlay.png"

local core

local function chat(message)
  windower.add_to_chat(CHAT_COLOR, "[XIVHud] " .. message)
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

local new_guard = step("loading lib/guard", function()
  return require("lib/guard")
end)
local new_core = step("loading lib/core", function()
  return require("lib/core")
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
local new_giltracker = step("loading the giltracker component", function()
  return require("components/giltracker/giltracker")
end)

-- Every Windower handler goes through this, so a bug degrades to a message and
-- a dead handler rather than an unexplained freeze.
local guard = new_guard and new_guard({ notify = chat }) or nil

-- Registered only while layout mode is on, so normal play carries no
-- input-handling cost at all.
local mouse_event_id, keyboard_event_id

local function set_input_capture(on)
  if on and not mouse_event_id then
    -- These fall back to false: a handler that dies must never keep swallowing
    -- the player's mouse and keyboard, which is indistinguishable from a hang.
    mouse_event_id = windower.register_event(
      "mouse",
      guard.wrap("mouse", function(mouse_type, x, y, delta, blocked)
        return core.on_mouse(mouse_type, x, y, delta, blocked)
      end, false)
    )
    keyboard_event_id = windower.register_event(
      "keyboard",
      guard.wrap("keyboard", function(key, down)
        return core.on_keyboard(key, down)
      end, false)
    )
  elseif not on and mouse_event_id then
    windower.unregister_event(mouse_event_id)
    windower.unregister_event(keyboard_event_id)
    mouse_event_id, keyboard_event_id = nil, nil
  end
end

--[[ Config I/O deliberately does not use the `files` library.

     `files.write` on a missing file calls `create()`, which calls
     `create_path()` and then **ignores its error**, so a directory that could
     not be created is reported as "New file: ..." and then dies indexing a nil
     handle. That is exactly what happened here: load.log, which sits directly
     in the addon folder and is written with raw io, appeared every time, while
     data/<Character>/<component>.lua -- two directories deep -- never did.

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

-- Behind a pcall because this runs on inbound packets: a throw here would
-- propagate into the shared `incoming chunk` handler, and guard disables that
-- after five failures for the rest of the session -- after which gil would
-- silently stop updating. A component already has to treat a nil packet as a
-- real case, so failing to nil costs nothing.
local function parse_packet(data)
  local ok, packet = pcall(packets.parse, "incoming", data)
  return ok and packet or nil
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
    get_player = get_player,
    now = os.clock,
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

-- One factory, three components: the main party and the two alliance parties
-- each get their own config file, layout slot and drag box.
step("building the party list components", function()
  if safe_mode or libraries_error then
    return
  end
  for _, list in ipairs({
    { name = "partylist", variant = "main" },
    { name = "alliancelist1", variant = "alliance1" },
    { name = "alliancelist2", variant = "alliance2" },
  }) do
    core.register(new_partylist({
      name = list.name,
      variant = list.variant,
      new_text = wrap_text,
      new_image = wrap_image,
      screen = screen,
      asset = asset,
      resources = res,
      now = os.clock,
      get_player = get_player,
      get_party = function()
        return windower.ffxi.get_party()
      end,
      get_mob_by_target = function(kind)
        return windower.ffxi.get_mob_by_target(kind)
      end,
      get_info = function()
        return windower.ffxi.get_info()
      end,
    }))
  end
end)

-- Textures fail silently: a prim with a bad path simply draws nothing, so an
-- incomplete install looks like a broken addon. Say so at load instead.
local function check_assets()
  local missing = {}
  local expected = { OVERLAY_TEXTURE }
  for _, texture in ipairs({ "bar_bg.png", "bar_compact.png", "hp_fg.png", "mp_fg.png", "tp_fg.png" }) do
    expected[#expected + 1] = "components/parambar/assets/" .. texture
  end
  -- The party list ships some 680 textures; checking every one at load would
  -- cost 680 file opens to learn what a handful already tells us.
  for _, texture in ipairs({
    "assets/xiv/BgTopWide.png",
    "assets/xiv/BarBG.png",
    "assets/xiv/Cursor.png",
    "assets/xiv/AllyBarBG.png",
    "assets/jobIcons/frame.png",
    "assets/jobIcons/whm.png",
    "assets/buffIcons/33.png",
  }) do
    expected[#expected + 1] = "components/partylist/" .. texture
  end
  expected[#expected + 1] = "components/giltracker/assets/gil.png"

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
  end)
)

windower.register_event(
  "login",
  guard.wrap("login", function()
    core.on_login()
  end)
)

windower.register_event(
  "logout",
  guard.wrap("logout", function()
    core.on_logout()
  end)
)

if not safe_mode then
  windower.register_event(
    "prerender",
    guard.wrap("prerender", function()
      core.on_prerender()
    end)
  )
end

windower.register_event(
  "status change",
  guard.wrap("status change", function(new_status, old_status)
    core.on_status_change(new_status, old_status)
  end)
)

windower.register_event(
  "zone change",
  guard.wrap("zone change", function()
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

     The three party-list ids Windower has a field definition for are the one
     exception: they are parsed once here rather than once per sibling --
     three party lists (`partylist`, `alliancelist1`, `alliancelist2`) would
     otherwise each redo the same `packets.parse` call on every packet.
     `PARTY_BUFFS` has no such definition (see packets.lua) and is decoded by
     the component itself from the raw bytes.

     Guarded on `libraries_error`, not just `safe_mode`: both the pre-parse
     below and giltracker's `parse_packet` call into the `packets` library,
     which failed to load in that case. Components receive the event as
     `update('chunk', id, original, parsed)` and are free to ignore it --
     parambar does. ]]
if not safe_mode and not libraries_error then
  local structured = partylist_packets
      and {
        [partylist_packets.ALLIANCE] = true,
        [partylist_packets.PARTY_MEMBER] = true,
        [partylist_packets.CHAR] = true,
      }
    or {}
  windower.register_event(
    "incoming chunk",
    guard.wrap("incoming chunk", function(id, original)
      core.dispatch("chunk", id, original, structured[id] and packets.parse("incoming", original) or nil)
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

-- FFXI reports vitals as two independent streams, absolute and percent; both
-- are forwarded, and the component reconciles them.
for _, vital in ipairs({ "hp", "hpp", "mp", "mpp", "tp" }) do
  windower.register_event(
    vital .. " change",
    guard.wrap(vital .. " change", function(new_value, old_value)
      core.dispatch(vital, new_value, old_value)
    end)
  )
end

trace("---- chunk finished, every handler registered")
chat("loaded - type //hud for commands")
