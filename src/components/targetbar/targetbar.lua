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

--[[ Target Bar - the current target's health, name and distance, on the same
     xiv bar art the party list uses, and the same again for the `<st>`
     selection cursor on a second bar of its own.

     This file owns prims and nothing else: what to draw comes from logic.lua,
     whether to draw comes from the framework. The prims are built once at
     construction rather than on demand - there are only six of them a bar, and
     a widget that builds them lazily has to dispose them somewhere too.

     It runs every frame, which is what shapes the rest of it:

       - the target is read each tick, because the cursor can move between any
         two frames and nothing announces it;
       - the party roster and the player are read on a 200ms gate instead,
         since neither changes at frame rate and get_party() allocates
         eighteen member tables per call;
       - nothing is written to a prim that already holds it. partylist's
         discipline, for the same reason: a settled bar that rewrote every
         value sixty times a second is the only thing here that would cost
         anything. ]]

local new_logic = require("components/targetbar/logic")
local build_defaults = require("components/targetbar/defaults")

local ASSET_DIR = "assets/xiv/wide/"
-- The one chunk this widget reads: the action packet, which reaches it
-- already decoded - the entry point's dispatch runs
-- windower.packets.parse_action once for every component that wants it.
local ACTION_CHUNK = 0x028

--[[ The two bars. `main` follows the target, `subtarget` the `<st>` selection
     cursor - the only difference between the two instances is the token each
     one reads. Main leads: the order `//hud list` prints, and the order layout
     mode hit-tests REVERSED, so the subtarget wins where the two overlap. ]]
local ANCHORS = { "main", "subtarget" }
local TOKEN = { main = "t", subtarget = "st" }

--[[ One bar: its own prims, its own logic, its own placement. The token is
     the only thing that tells the two apart - everything below draws whatever
     mob it is handed. ]]
local function new_bar(ctx, variant, config)
  local bar = {}
  local token = TOKEN[variant]

  local screen_width = ctx.screen()

  -- Without the resources library there is no spell name or cast time to
  -- show, so logic quietly runs with the cast feature off.
  local logic = new_logic(config, ctx.resources, variant)

  local attached = false
  local pos = nil
  local scale = 1
  local visible = false
  local geometry = nil
  -- The last value pushed to each prim, per property. An unchanged value is
  -- never written again.
  local written = {}

  --[[ Prims --------------------------------------------------------------- ]]

  local function image(texture)
    local prim = ctx.new_image()
    prim.draggable(false)
    prim.repeat_xy(1, 1)
    -- Never fit: the art is twice its drawn size, and fitting would pin the
    -- prim to the texture and ignore both that and the widget's scale.
    prim.fit(false)
    prim.path(ctx.asset(ASSET_DIR .. texture))
    -- Explicit, not left to the library's defaults: the plate and frame draw
    -- their art untinted, and the fill's tint is written over this per frame.
    prim.color(255, 255, 255)
    prim.alpha(255)
    prim.hide()
    return prim
  end

  local function text()
    local prim = ctx.new_text()
    prim.draggable(false)
    -- No background: the bounds this widget reports make no room for one.
    prim.bg_visible(false)
    prim.bg_alpha(0)
    prim.hide()
    return prim
  end

  -- Creation order is draw order - the Windower libraries expose no depth
  -- control - so each frame has to be built after the fill it sits over.
  local background = image("BarBG.png")
  local fill = image("Bar.png")
  local frame = image("BarFG.png")
  local cast_background = image("CastBG.png")
  local cast_fill = image("CastBar.png")
  local cast_frame = image("CastFG.png")

  local hp_text = text()
  local distance_text = text()
  local name_text = text()
  local cast_name = text()
  -- The one right-justified text here: it grows leftward from the box's right
  -- edge, and its position pre-subtracts the screen width the library adds
  -- back for right-flagged texts.
  cast_name.right_justified(true)

  local texts = { hp = hp_text, distance = distance_text, name = name_text }

  --[[ Writing --------------------------------------------------------------- ]]

  local function push(key, value, apply)
    if written[key] == value then
      return
    end
    written[key] = value
    apply(value)
  end

  local function push_text(prim, key, value)
    push(key .. ".text", value, prim.text)
  end

  local function push_color(prim, key, color)
    color = color or {}
    local red, green, blue = color.r or 255, color.g or 255, color.b or 255
    push(key .. ".color", red * 65536 + green * 256 + blue, function()
      prim.color(red, green, blue)
    end)
    push(key .. ".alpha", color.a or 255, prim.alpha)
  end

  local function want(prim, key, on)
    push(key .. ".visible", on and true or false, function(shown)
      if shown then
        prim.show()
      else
        prim.hide()
      end
    end)
  end

  local function styled(value)
    if type(value) == "table" then
      return value
    end
    return {}
  end

  local function apply_style()
    local color = styled(config.text_color)
    local stroke = styled(config.text_stroke)
    -- Every argument filled in: a Windower setter handed nothing is a getter,
    -- so a mangled config would otherwise leave the prim wearing whatever the
    -- previous character's style put on it.
    for _, prim in pairs(texts) do
      prim.font(config.font or "Arial")
      prim.stroke_width(stroke.width or 0)
      prim.stroke_color(stroke.r or 0, stroke.g or 0, stroke.b or 0)
      -- stroke_alpha, not stroke_transparency: the library reads transparency
      -- as 0..1 and would turn an alpha of 200 into a wildly negative value.
      prim.stroke_alpha(stroke.a or 255)
      -- With a fallback: three nils would turn the setter into a getter.
      prim.color(color.r or 255, color.g or 255, color.b or 255)
      prim.alpha(color.a or 255)
    end

    local stroke_width = stroke.width or 0
    cast_name.font(config.font or "Arial")
    cast_name.stroke_width(stroke_width)
    cast_name.stroke_color(stroke.r or 0, stroke.g or 0, stroke.b or 0)
    cast_name.stroke_alpha(stroke.a or 255)
    cast_name.color(color.r or 255, color.g or 255, color.b or 255)
    cast_name.alpha(color.a or 255)

    -- The cast fill's tint is fixed configuration, never claim state.
    local cast_color = styled(styled(config.cast).fill_color)
    cast_fill.color(cast_color.r or 255, cast_color.g or 255, cast_color.b or 255)
    cast_fill.alpha(cast_color.a or 255)
  end

  --[[ Layout ---------------------------------------------------------------- ]]

  local function apply_layout()
    if not pos then
      geometry = nil
      return
    end

    -- Re-read, not the construction-time value: the cast name's x
    -- pre-subtracts the screen width, so a mid-session resolution change
    -- would otherwise park it off screen by the delta.
    screen_width = ctx.screen()
    geometry = logic.geometry(pos.x, pos.y, scale, screen_width)

    for key, prim in pairs(texts) do
      local segment = geometry.texts[key]
      prim.pos(segment.x, segment.y)
      prim.size(segment.size)
    end

    for _, layer in ipairs({ { background, geometry.frame }, { frame, geometry.frame } }) do
      layer[1].pos(layer[2].x, layer[2].y)
      layer[1].size(layer[2].width, layer[2].height)
    end
    -- The fills' widths belong to the render: only their origins are fixed.
    fill.pos(geometry.fill.x, geometry.fill.y)

    local cast = geometry.cast
    for _, layer in ipairs({ { cast_background, cast.frame }, { cast_frame, cast.frame } }) do
      layer[1].pos(layer[2].x, layer[2].y)
      layer[1].size(layer[2].width, layer[2].height)
    end
    cast_fill.pos(cast.fill.x, cast.fill.y)
    cast_name.pos(cast.name.x, cast.name.y)
    cast_name.size(cast.name.size)

    --[[ Sizes are only written when the value behind them moves, so a layout
         change has to clear that memory or the bar keeps the previous scale's
         fill until the target next takes damage. ]]
    written = {}
  end

  --[[ Drawing --------------------------------------------------------------- ]]

  local function hide_all()
    want(background, "background", false)
    want(fill, "fill", false)
    want(frame, "frame", false)
    want(cast_background, "cast_background", false)
    want(cast_fill, "cast_fill", false)
    want(cast_frame, "cast_frame", false)
    want(cast_name, "cast_name", false)
    for key, prim in pairs(texts) do
      want(prim, key, false)
    end
  end

  local function render()
    if not attached or not pos or not geometry then
      return
    end

    --[[ The bar's own mob is read every frame, because the cursor can move
         between any two of them and nothing announces it - and lib/player
         memoizes the read for the frame, so the sibling bar and the party list
         asking for the same one cost nothing extra. The player's own facts
         come from the outer widget instead: both bars want the same answer,
         and it is worth reading once. ]]
    local mob = ctx.get_mob_by_target(token)
    if mob then
      logic.set_target(mob)
    else
      logic.clear_target()
    end

    local plan = logic.tick(ctx.now())
    local drawn = visible and plan.occupied

    want(background, "background", drawn)
    want(frame, "frame", drawn)
    want(fill, "fill", drawn and not plan.fill.hidden)
    if drawn then
      push("fill.width", plan.fill.width, function(width)
        fill.size(geometry.fill.width_at(width), geometry.fill.height)
      end)
      push_color(fill, "fill", plan.fill.color)
    end

    for key, prim in pairs(texts) do
      local segment = plan.texts[key]
      want(prim, key, drawn)
      if drawn then
        push_text(prim, key, segment.text)
        push_color(prim, key, segment.color)
      end
    end

    local casting = visible and plan.cast.active
    want(cast_background, "cast_background", casting)
    want(cast_frame, "cast_frame", casting)
    want(cast_fill, "cast_fill", casting and plan.cast.width > 0)
    want(cast_name, "cast_name", casting)
    if casting then
      push("cast_fill.width", plan.cast.width, function(width)
        cast_fill.size(geometry.cast.fill.width_at(width), geometry.cast.fill.height)
      end)
      push_text(cast_name, "cast_name", plan.cast.name:sub(1, geometry.cast.name.max_chars))
    end
  end

  --[[ What the outer widget drives ------------------------------------------ ]]

  function bar.attach(loaded_config)
    config = loaded_config
    attached = true
    logic.set_config(config)
    apply_style()
    apply_layout()
  end

  --[[ Whether this bar is in a state to draw, which is what decides whether
       the outer widget reads the client at all: an unplaced or detached bar
       renders nothing, and a poll for it would be a get_party nobody uses. ]]
  function bar.ready()
    return attached and pos ~= nil and geometry ~= nil
  end

  -- The player's own facts, read once by the outer widget and pushed into
  -- both bars.
  function bar.set_client(me, player, party)
    logic.set_self(me and me.id, me and me.model_size, player and player.main_job)
    logic.set_party(party)
  end

  bar.render = render

  function bar.on_action(parsed, now)
    logic.on_action(parsed, now)
  end

  function bar.command(args)
    return logic.command(args)
  end

  function bar.detach()
    attached = false
    --[[ Only the target is dropped. The roster and the player need no clearing
         because attach reopens the poll gate and render polls before it reads
         anything, so the next character's first frame already has its own.

         The target is different: the same mob keeps the same id across a
         logout, and a mule in the same zone can pick it straight back up -
         which the bar would read as a continuously held target and ease from
         health nobody has watched in minutes rather than snapping to what is
         actually there. ]]
    logic.clear_target()
    bar.hide()
  end

  --[[ Both setters are change-gated. Core fans a placement over every anchor
       on every apply and layout mode applies per raw mouse-move event, so a
       drag of one bar re-states the other's position and scale dozens of times
       a second - and `apply_layout` clears the write cache, which would put a
       full set of prim writes behind each of those. ]]
  function bar.set_pos(x, y)
    --[[ The screen is part of what a placement means here, not just the
         origin: apply_layout re-reads it because the cast name is right
         justified and its x pre-subtracts the width the library adds back, so
         a resolution change moves that text without moving the origin. Core
         re-pushes the same origin afterwards, and a gate on the origin alone
         would swallow it. ]]
    if pos and pos.x == x and pos.y == y and ctx.screen() == screen_width then
      return
    end
    pos = { x = x, y = y }
    apply_layout()
  end

  function bar.set_scale(new_scale)
    if scale == new_scale then
      return
    end
    scale = new_scale
    apply_layout()
  end

  function bar.set_preview(on)
    logic.set_preview(on)
  end

  function bar.show()
    visible = true
  end

  function bar.hide()
    visible = false
    hide_all()
  end

  -- The origin set_pos was given, exactly: core clamps the widget on screen by
  -- comparing the two, and layout mode's drag offsets assume it.
  function bar.get_bounds()
    if not pos then
      return nil
    end
    return logic.bounds(pos.x, pos.y, scale)
  end

  function bar.destroy()
    background.destroy()
    fill.destroy()
    frame.destroy()
    cast_background.destroy()
    cast_fill.destroy()
    cast_frame.destroy()
    cast_name.destroy()
    for _, prim in pairs(texts) do
      prim.destroy()
    end
  end

  return bar
end

--[[ The widget contract ---------------------------------------------------- ]]

--[[ Two bars under one registration: the outer widget owns the contract and
     routes it by anchor, and a bar knows only its own token. partylist's
     shape, and for its reason - a second component would have to require this
     one to share the logic, which the isolation rule forbids outright. ]]
local function new(ctx)
  local self = { name = "targetbar", alias = "tb" }

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local save = nil
  local attached = false
  --[[ The service's read counter as of the last rebuild of the claim roster,
       held here rather than in either bar: both want the same answer, and
       set_party walks eighteen member tables to reach it. ]]
  local last_generation = nil

  local bars = {}
  for _, anchor in ipairs(ANCHORS) do
    bars[anchor] = new_bar(ctx, anchor, self.defaults.bars[anchor])
  end

  local function each(method, ...)
    for _, anchor in ipairs(ANCHORS) do
      bars[anchor][method](...)
    end
  end

  function self.anchors()
    return ANCHORS
  end

  --[[ Core fans a placement out over every anchor on every apply, and layout
       mode drags one of them - so a name that is not ours has to cost nothing
       rather than crash the apply. An absent name is the same case and not a
       shorthand for the main bar: core names an anchor for every placement it
       makes on an anchored widget, so a nil is a wiring slip, and one that
       quietly moved the main bar would leave the slip looking like success. ]]
  local function bar_at(anchor)
    return anchor ~= nil and bars[anchor] or nil
  end

  --[[ The player's own facts, read once for both bars and pushed into each.
       Gated on the service's read counter rather than a clock of our own,
       which would sit out of phase with it and leave the bars up to two
       intervals behind; an absent counter falls back to reading every frame
       rather than never. Nothing is read while neither bar could draw. ]]
  local function refresh_client()
    local wanted = false
    for _, anchor in ipairs(ANCHORS) do
      wanted = wanted or bars[anchor].ready()
    end
    if not wanted then
      return
    end
    local generation = ctx.generation and ctx.generation() or nil
    if generation ~= nil and generation == last_generation then
      return
    end
    last_generation = generation
    local me = ctx.get_mob_by_target("me")
    local player = ctx.get_player()
    local party = ctx.get_party()
    -- Per bar, not `each`: building a claim roster walks all eighteen party
    -- keys, and a bar that could not draw with one has no use for it.
    for _, anchor in ipairs(ANCHORS) do
      if bars[anchor].ready() then
        bars[anchor].set_client(me, player, party)
      end
    end
  end

  --[[ A config file is code and is hand-editable, and `//hud copy` imports
       another character's, so a bar's entry can be any shape at all by the
       time it reaches here. Anything unusable is replaced with a FRESH copy of
       the defaults and written back into the config - fresh, because handing a
       bar `self.defaults` would have every later command write into the
       defaults table, which `save()` does not serialise. ]]
  function self.attach(loaded_config, persist)
    save = persist
    attached = true
    -- Forget the last read: a relog inside one interval would otherwise keep
    -- the previous character's roster until the service next reads.
    last_generation = nil
    local config = type(loaded_config) == "table" and loaded_config or {}
    if type(config.bars) ~= "table" then
      config.bars = {}
    end
    local seed = nil
    for _, anchor in ipairs(ANCHORS) do
      if type(config.bars[anchor]) ~= "table" then
        -- Built at most once per attach, however many entries are unusable.
        seed = seed or build_defaults(screen_width, screen_height)
        config.bars[anchor] = seed.bars[anchor]
      end
      bars[anchor].attach(config.bars[anchor])
    end
  end

  function self.detach()
    attached = false
    save = nil
    each("detach")
  end

  function self.set_pos(x, y, anchor)
    local placed = bar_at(anchor)
    if placed then
      placed.set_pos(x, y)
    end
  end

  function self.set_scale(scale, anchor)
    local placed = bar_at(anchor)
    if placed then
      placed.set_scale(scale)
    end
  end

  function self.set_preview(on)
    each("set_preview", on)
  end

  --[[ Core sends the widget's own switch with no anchor and one bar's with its
       name; a whole-widget show is also what layout mode force-shows with, so
       it has to bring back a bar a per-anchor hide took down. ]]
  function self.show(anchor)
    local shown = bar_at(anchor)
    if anchor ~= nil then
      if shown then
        shown.show()
      end
      return
    end
    each("show")
  end

  function self.hide(anchor)
    local hidden = bar_at(anchor)
    if anchor ~= nil then
      if hidden then
        hidden.hide()
      end
      return
    end
    each("hide")
  end

  function self.get_bounds(anchor)
    local placed = bar_at(anchor)
    if not placed then
      return nil
    end
    return placed.get_bounds()
  end

  --[[ No arguments is the per-frame tick. Of the events the entry point
       forwards to every component, exactly one is wanted: the action chunk,
       which feeds both cast trackers and nothing else - no render, no client
       read. Everything else is ignored quietly, which is the contract:
       core.dispatch has no idea who wants what, and a handler that threw
       would be disabled for the rest of the session. ]]
  function self.update(event, id, _original, parsed)
    if event == nil then
      refresh_client()
      each("render")
      return
    end
    if event ~= "chunk" or id ~= ACTION_CHUNK or not attached then
      return
    end
    -- Already decoded, by the one dispatch that sees the packet: nil when the
    -- parse failed, which reads the same as nothing having happened.
    if parsed then
      each("on_action", parsed, ctx.now())
    end
  end

  -- What `//hud targetbar <bar>` reports: that bar's own settings. Whether it
  -- is on screen at all is the framework's answer, and `//hud list` prints it
  -- per anchor.
  local function status_of(anchor)
    -- Parenthesised: `command` answers (line, changed), and a report has no
    -- second value to hand its caller.
    return (bars[anchor].command({}))
  end

  --[[ `//hud targetbar [<bar>] <verb> ...`, the bar word leading so the verb
       grammar behind it is untouched. Absent, the target bar is addressed -
       which is what every line that worked before the subtarget bar existed
       still means. A first word that is not a bar is a verb, so an unknown one
       still reaches the verb parser and answers with its hint. ]]
  function self.handle_command(args)
    args = args or {}
    local first = args[1] and args[1]:lower() or nil
    if not first then
      local lines = {}
      for _, anchor in ipairs(ANCHORS) do
        lines[#lines + 1] = status_of(anchor)
      end
      return lines
    end

    local anchor = bars[first] and first or nil
    local rest = args
    if anchor then
      rest = {}
      for index = 2, #args do
        rest[index - 1] = args[index]
      end
    end
    if rest[1] == nil then
      return status_of(anchor or "main")
    end

    local reply, changed = bars[anchor or "main"].command(rest)
    -- No re-layout: the only setting here picks a colour scheme, and the next
    -- tick pushes the colour that follows from it. Add one back alongside the
    -- first command that actually moves something.
    if changed and save then
      save()
    end
    return reply
  end

  function self.destroy()
    each("destroy")
  end

  return self
end

return new
