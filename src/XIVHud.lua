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
_addon.command = "xh"
_addon.commands = { "xivhud" }

texts = require("texts")
images = require("images")
files = require("files")

local new_core = require("lib.core")
local new_guard = require("lib.guard")
local new_parambar = require("components.parambar.parambar")

local CHAT_COLOR = 207
-- Plain white square, tinted and stretched for the layout-mode highlight.
local OVERLAY_TEXTURE = "assets/overlay.png"

local core

local function chat(message)
  windower.add_to_chat(CHAT_COLOR, "[XIVHud] " .. message)
end

-- Every Windower handler goes through this, so a bug here degrades to a
-- message and a dead handler rather than an unexplained freeze.
local guard = new_guard({ notify = chat })

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

local function read_file(path)
  local file = files.new(path)
  if not file:exists() then
    return nil
  end
  return file:read()
end

-- files.write() calls f:create() for a file that does not exist, which calls
-- create_path() -> windower.create_dir for each missing directory. So the
-- per-character data/ tree appears on the first save without help from here.
local function write_file(path, contents)
  local ok, err = pcall(function()
    files.new(path):write(contents)
  end)
  if not ok then
    return false, err
  end
  return true
end

-- Directory enumeration for `//xh copy`, which walks another character's
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
    bg_alpha = function(alpha)
      text:bg_alpha(alpha)
    end,
    -- The argument is required: texts.right_justified() with none is a getter.
    right_justified = function(on)
      text:right_justified(on)
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

core = new_core({
  read_file = read_file,
  write_file = write_file,
  list_dir = list_dir,
  is_dir = is_dir,
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

-- Components are wired explicitly — no directory scanning — so the set of
-- registered components is always readable from here.
core.register(new_parambar({
  new_text = wrap_text,
  new_image = wrap_image,
  screen = screen,
  get_player = get_player,
  asset = function(relative_path)
    return windower.addon_path .. relative_path
  end,
}))

-- Textures fail silently: a prim with a bad path simply draws nothing, so an
-- incomplete install looks like a broken addon. Say so at load instead.
local function check_assets()
  local missing = {}
  local expected = { OVERLAY_TEXTURE }
  for _, texture in ipairs({ "bar_bg.png", "bar_compact.png", "hp_fg.png", "mp_fg.png", "tp_fg.png" }) do
    expected[#expected + 1] = "components/parambar/assets/" .. texture
  end

  for _, relative_path in ipairs(expected) do
    if not files.exists(relative_path) then
      missing[#missing + 1] = relative_path
    end
  end

  if #missing > 0 then
    chat(("%d texture(s) are missing from this install:"):format(#missing))
    for _, relative_path in ipairs(missing) do
      chat("  " .. relative_path)
    end
    chat("  the addon folder is incomplete — re-copy every file and folder under src/")
  end
end

windower.register_event(
  "load",
  guard.wrap("load", function()
    check_assets()
    core.on_load()
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

windower.register_event(
  "addon command",
  guard.wrap("command", function(...)
    core.on_command({ ... })
  end)
)

windower.register_event(
  "prerender",
  guard.wrap("prerender", function()
    core.on_prerender()
  end)
)

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
