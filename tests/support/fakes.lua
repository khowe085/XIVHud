--[[ Reusable fakes for the injected Windower surface.

     With dependency injection a "mock" is just a plain table of functions, so
     tests stay framework-light. Build a deps table here and pass it to a lib
     module's constructor. Override only the fields a given test cares about. ]]

local M = {}

-- In-memory stand-in for the addon-relative file I/O injected into lib/settings.
-- `files` is the backing store, so specs can seed it (`put`) and assert on it.
function M.file_system(seed)
  local fs = {
    files = seed or {},
    fail_writes = false,
    fail_write_paths = {},
    dot_entries = false,
    writes = 0,
    deletes = {},
  }

  function fs.put(path, contents)
    fs.files[path] = contents
  end

  function fs.read_file(path)
    return fs.files[path]
  end

  -- Mirrors windower.get_dir: the names directly inside `path`, files and
  -- directories alike. nil when there is no such directory.
  function fs.list_dir(path)
    local prefix = path .. "/"
    local seen, entries = {}, {}
    for name in pairs(fs.files) do
      if name:sub(1, #prefix) == prefix then
        local head = name:sub(#prefix + 1):match("^([^/]+)")
        if head and not seen[head] then
          seen[head] = true
          entries[#entries + 1] = head
        end
      end
    end
    table.sort(entries)
    if #entries == 0 then
      return nil
    end
    -- Some directory APIs include the . and .. links; make sure callers cope.
    if fs.dot_entries then
      table.insert(entries, 1, "..")
      table.insert(entries, 1, ".")
    end
    return entries
  end

  -- Every attempted path is recorded, hit or miss: deleting a *directory*
  -- goes through the same dep (os.remove at runtime, a no-op on Windows for
  -- non-empty dirs), and the attempt is the only thing a spec can pin.
  function fs.delete_file(path)
    fs.deletes[#fs.deletes + 1] = path
    if fs.files[path] == nil then
      return false
    end
    fs.files[path] = nil
    return true
  end

  function fs.is_dir(path)
    local prefix = path .. "/"
    for name in pairs(fs.files) do
      if name:sub(1, #prefix) == prefix then
        return true
      end
    end
    return false
  end

  function fs.write_file(path, contents)
    if fs.fail_writes or fs.fail_write_paths[path] then
      return false, "disk full"
    end
    fs.files[path] = contents
    fs.writes = fs.writes + 1
    return true
  end

  return fs
end

-- A stand-in for a Windower texts/images prim. Every setter records its
-- argument so a spec can assert on what a widget pushed, without a client.
local PRIM_SETTERS = {
  "path",
  "fit",
  "repeat_xy",
  "draggable",
  "color",
  "alpha",
  "text",
  "font",
  "italic",
  "bold",
  "stroke_width",
  "stroke_color",
  "stroke_alpha",
  "bg_alpha",
  "bg_color",
  "bg_visible",
  "right_justified",
}

function M.prim(kind)
  local p = { kind = kind, visible = false, destroyed = 0, calls = {}, last = {}, x = nil, y = nil }

  local function log(name, ...)
    p.calls[#p.calls + 1] = { name = name, args = { ... } }
  end

  -- Setter values go in `last` rather than onto the prim, so they cannot
  -- shadow the same-named method: `p.last.color` is the value, `p.color` the
  -- method. One argument is stored as itself, several as a list.
  local function record(name, ...)
    local args = { ... }
    log(name, ...)
    p.last[name] = #args > 1 and args or args[1]
  end

  function p.pos(x, y)
    p.x, p.y = x, y
    log("pos", x, y)
  end

  -- Images take (width, height); a text's size is its font size.
  function p.size(width, height)
    p.width, p.height, p.font_size = width, height, width
    log("size", width, height)
  end

  function p.show()
    p.visible = true
    log("show")
  end

  function p.hide()
    p.visible = false
    log("hide")
  end

  function p.destroy()
    p.destroyed = p.destroyed + 1
    log("destroy")
  end

  for _, name in ipairs(PRIM_SETTERS) do
    p[name] = function(...)
      record(name, ...)
    end
  end

  return p
end

-- Prim constructors plus the list of everything they have handed out.
function M.prims()
  local factory = { all = {}, texts = {}, images = {} }

  local function make(kind, bucket)
    local prim = M.prim(kind)
    factory.all[#factory.all + 1] = prim
    bucket[#bucket + 1] = prim
    return prim
  end

  function factory.new_text()
    return make("text", factory.texts)
  end

  function factory.new_image()
    return make("image", factory.images)
  end

  return factory
end

-- A component implementing the widget contract, recording everything the
-- framework does to it. `defaults` is the component's own config defaults.
-- `anchor_names` makes it a multi-anchor widget (touchpoint 2): it grows the
-- optional `anchors()` member, and set_pos/set_scale/get_bounds address one
-- anchor each, recorded under `w.anchor[name]`.
function M.widget(name, defaults, anchor_names)
  local w = {
    name = name,
    defaults = defaults or {},
    config = nil,
    pos = nil,
    scale = nil,
    preview = false,
    shown = nil,
    destroyed = 0,
    updates = {},
    width = 200,
    height = 100,
  }

  -- `store` arrives only for widgets declaring `wants_store = true` (the
  -- directory config form); it is recorded either way so specs can assert on
  -- both sides of that contract.
  function w.attach(config, save, store)
    w.config = config
    w.save = save
    w.store = store
  end

  function w.detach()
    w.config = nil
    w.save = nil
    w.store = nil
  end

  function w.set_pos(x, y)
    w.pos = { x, y }
  end

  function w.set_scale(scale)
    w.scale = scale
  end

  function w.set_preview(on)
    w.preview = on
  end

  function w.show()
    w.shown = true
  end

  function w.hide()
    w.shown = false
  end

  function w.get_bounds()
    if not w.pos then
      return nil
    end
    return w.pos[1], w.pos[2], w.width, w.height
  end

  function w.update(...)
    w.updates[#w.updates + 1] = { ... }
  end

  function w.destroy()
    w.destroyed = w.destroyed + 1
  end

  if anchor_names then
    w.anchor = {}

    -- An anchor-addressed call without an anchor is a framework bug; indexing
    -- with the nil key makes the test error loudly rather than pass quietly.
    local function entry(anchor)
      w.anchor[anchor] = w.anchor[anchor] or {}
      return w.anchor[anchor]
    end

    function w.anchors()
      return anchor_names
    end

    function w.set_pos(x, y, anchor)
      entry(anchor).pos = { x, y }
    end

    function w.set_scale(scale, anchor)
      entry(anchor).scale = scale
    end

    function w.get_bounds(anchor)
      local placed = w.anchor[anchor]
      if not placed or not placed.pos then
        return nil
      end
      return placed.pos[1], placed.pos[2], w.width, w.height
    end
  end

  return w
end

-- The Windower surface lib/core is injected with, backed by M.file_system.
-- Returns the deps table plus the recorders the specs assert against.
function M.core_deps(overrides)
  local fs = M.file_system()
  local prims = M.prims()
  local recorder = {
    fs = fs,
    prims = prims,
    chat = {},
    capture = false,
    player = nil,
    clock = 0,
    screen_width = 1920,
    screen_height = 1080,
  }

  local deps = {
    read_file = fs.read_file,
    write_file = fs.write_file,
    get_player = function()
      return recorder.player
    end,
    logged_in = function()
      return recorder.player ~= nil
    end,
    screen = function()
      return recorder.screen_width, recorder.screen_height
    end,
    now = function()
      return recorder.clock
    end,
    chat = function(message)
      recorder.chat[#recorder.chat + 1] = message
    end,
    set_input_capture = function(on)
      recorder.capture = on
    end,
    list_dir = fs.list_dir,
    is_dir = fs.is_dir,
    delete_file = fs.delete_file,
    new_image = prims.new_image,
    new_text = prims.new_text,
    overlay_texture = function()
      return "addons/XIVHud/assets/overlay.png"
    end,
  }

  for key, value in pairs(overrides or {}) do
    deps[key] = value
  end

  -- Every line the addon has said, joined, for substring assertions.
  function recorder.said()
    return table.concat(recorder.chat, "\n")
  end

  -- A character the client has finished loading. Core scopes on the name alone,
  -- so the vitals here are for the components reading them.
  function recorder.login(name)
    recorder.player = {
      name = name,
      status = 0,
      vitals = { hp = 1000, max_hp = 1000, hpp = 100, mp = 500, max_mp = 500, mpp = 100, tp = 0 },
    }
  end

  return deps, recorder
end

return M
