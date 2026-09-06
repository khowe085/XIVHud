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

--[[ The crossbar widget: the persistent cross hotbar, live. What is its own
     is the two crosses' geometry (render.lua), the hold-state key machine
     (input.lua), the prims, the sword and the framework contract; a press
     resolves through lib/actionbar/bar into lib/actionbar/service, and each
     slot draws itself through lib/actionbar/slot - all shared with the
     hotbar since 2026-09-06, so the two bars cannot drift. All three bars
     own prims - the XHB, the WXHB's two separately-anchored halves, and
     Expanded Hold centred on main - and the per-frame tick feeds each slot
     the facts it draws from: recasts, costs, counters, the chain result.

     The ctx's prim constructors are optional on purpose: without new_image
     the widget runs headless - input machine, bindings, execution, anchors,
     real bounds - which is what the CB2/CB3-era specs exercise and what safe
     degradation looks like if the entry point ever hands out less than it
     should. Every other ctx member is likewise guarded: a missing accessor
     reads as "the client has nothing to say", never a crash.

     The guards wire to what already exists: chat/suppression/layout-mode
     come from ctx, `disabled` is the widget's own visibility (core owns
     whether it is on screen), and edit mode does not exist until CB8. ]]

local new_input = require("components/crossbar/input")
local new_render = require("components/crossbar/render")
local new_slot = require("lib/actionbar/slot")
local new_bar = require("lib/actionbar/bar")
local grammars = require("lib/actionbar/grammar")
local new_actions = require("lib/actionbar/actions")
local build_defaults = require("components/crossbar/defaults")

--[[ `set` is the active-set label and `weapon` the sword above it. Both
     rode the main anchor at a fixed offset until 2026-08-29, so the only
     way to move either was to move the whole bar (Kevin). ]]
--[[ The set indicator's gold (Kevin, 2026-08-21). FFXIV writes the active
     set along the bottom of the cross hotbar, between the two halves, and
     without it an empty bar gives no sign that a switch did anything - which
     is how it was found. ]]
local SET_LABEL_COLOR = { 255, 215, 0 }
-- parambar's size, which is what the indicator was asked to match; its font
-- is the component's own `font`, already sans-serif as parambar's is.
local SET_LABEL_SIZE = 14

local ANCHORS = { "main", "wxhb_left", "wxhb_right", "set", "weapon" }

--[[ The five slot groups, in prim-construction order (a spec contract): the
     XHB's two sides on the main anchor, the WXHB's halves on their own
     anchors, and Expanded Hold's single side centred on main. `flag` names
     the render.visible plan key that shows the group; the expanded row has
     none - its plan entry carries the active hold state, not a boolean, and
     refresh keys it on group.key instead. ]]
local GROUPS = {
  { key = "xhb_left", bar = "xhb", side = "left", anchor = "main", flag = "xhb" },
  { key = "xhb_right", bar = "xhb", side = "right", anchor = "main", flag = "xhb" },
  { key = "wxhb_left", bar = "wxhb", side = "left", anchor = "wxhb_left", flag = "wxhb_left" },
  { key = "wxhb_right", bar = "wxhb", side = "right", anchor = "wxhb_right", flag = "wxhb_right" },
  { key = "expanded", bar = "expanded", side = "left", anchor = "main" },
}

-- The asset ROOT, not one folder in it: what hangs off this is `own/` for
-- XIVHud's own chrome, `icons/` for the imported pack and `cooldown/` for
-- the sweep frames, each with its own licence beside it.
local ASSETS = "assets/"
local SLOT_COUNT = 8
local MOUNTED_BUFF = 252
-- Windower's own mouse-event numbers, and only the two edges the sword's
-- click reads: a move over it is the game's, so it is never named here.
local MOUSE_LEFT_DOWN, MOUSE_LEFT_UP = 1, 2

-- Half-open, as the binder's own is: the pixel at x + width belongs to
-- whatever is drawn next, not to this. A coordinate that is not a number is
-- answered rather than compared - Windower fails silently, and a handler
-- that throws is one guard.lua disables after five goes.
local function inside(x, y, left, top, width, height)
  if type(x) ~= "number" or type(y) ~= "number" then
    return false
  end
  return x >= left and y >= top and x < left + width and y < top + height
end
--[[ `0x01E` Modify Inventory (Count, Bag, Index, Status - read from
     Windower's own packets/fields.lua): the packet a stack DECREMENT rides.
     `add item`/`remove item` fire when a record enters or leaves a bag, so
     using one of five never reached the count and only the last one did
     (Kevin, live client, 2026-08-22). It carries no item id, so unlike the
     events it cannot be gated on which id moved - only on whether the bar
     draws a count at all. ]]
local INVENTORY_CHUNK = 0x01E
--[[ The two packets the weapon layer follows: `0x050` Equip, which says a
     slot changed, and `0x01D` Finish Inventory, the login and zone-in bag
     dump without which the first read of a session finds nothing to name.
     Both are the ids equipviewer keys its own grid off.

     The Equip packet is READ rather than merely counted, and by its field
     name rather than by an offset, the way equipviewer reads the same one.
     Answering it costs a whole-inventory `get_equipment`, and GearSwap
     fires one of these per slot it swaps on every cast - sixteen of them a
     spell, none of which can move a layer keyed to the MAIN hand. A packet
     that will not decode arms the read anyway: a decode that fails must not
     freeze the layer for the session. ]]
local EQUIP_CHUNK = 0x050
local INVENTORY_READY_CHUNK = 0x01D
-- Equipment slot 0 is the main hand (equipviewer's own slot table).
local MAIN_HAND_SLOT = 0

local function new(ctx)
  local self = { name = "crossbar", alias = "cb", wants_store = true }

  -- Per-anchor placement pushed by core.
  local placed = {}
  --[[ The anchors core has switched off, one at a time. Kept apart from
       `placed` because a hidden anchor is still PLACED: core clamps it on
       screen from get_bounds and layout mode drags it, so only the drawing
       reads below go through anchor_at. ]]
  local hidden_anchors = {}

  local function anchor_at(anchor)
    if hidden_anchors[anchor] then
      return nil
    end
    return placed[anchor]
  end

  local screen_width, screen_height = ctx.screen()
  self.defaults = build_defaults(screen_width, screen_height)

  local config = self.defaults

  local function say(lines)
    if ctx.say ~= nil and lines ~= nil then
      ctx.say(lines)
    end
  end

  -- icon_for reads only the module-level built-in table, so an actions
  -- instance with no execution deps is enough for icon resolution.
  local icon_for = new_actions({}).icon_for

  -- Rebuilt at attach over the live config; the defaults-backed one answers
  -- bounds for layout mode before any login has attached a config.
  local render = new_render({ config = self.defaults, icon_for = icon_for })

  --[[ Execution is the action service's (lib/actionbar/service), built once
       in the entry point and shared with every bar: the scheduler, the
       travel countdown, the cast retry, the weaponskill gate, the skillchain
       engine, mount roulette and the warp and stealth ladders all live
       there, and so does the player's weapon state. This bar hands it a
       resolved record and the facts only the bar knows, and mirrors its
       weapon state into the rotation below. ]]
  local service = assert(ctx.actions, "crossbar needs ctx.actions, the action service")
  local roulette = service.roulette
  local skillchain = service.skillchain

  local machine = nil
  --[[ The bar's state (lib/actionbar/bar): bindings, job scoping, buffs,
       the weapon layer, the counts, the binder and the CLI. Declared here
       and built at the foot of the constructor: everything it needs - the
       render instance, the drawn groups, repaint - is a local defined
       below, while refresh() and paint_slot() above must already be able
       to ask whether edit mode is on. ]]
  local bar
  local function editing()
    return bar ~= nil and bar.editing()
  end

  local visible = false
  local preview = false
  -- The release of a press the sword took, owed back to nothing: see on_mouse.
  local swallow_left_up = false
  local active_state = "none"

  -- Core's config save, handed in at attach: the authoring verbs that write
  -- the component's own config need it, and nothing else here does.
  local save = nil

  -- Layout mode, read the way input.lua reads it (a missing dep is "no").
  local function layout_active()
    return ctx.layout_active ~= nil and ctx.layout_active() == true
  end

  local function draw_state()
    return service.draw_state()
  end

  local function config_hide(key)
    local hide = config.hide
    return type(hide) == "table" and hide[key] == true
  end

  --[[ Prims. Or nil when the ctx has no constructors (the headless shape the
       CB2/CB3 specs run). Construction order is a spec contract AND the
       z-order: the panel, then per group and slot six images in upstream's
       own layering - background, chain overlay, icon, sweep, frame,
       feedback - and three texts (name, cost, recast), then the sword. The
       sweep overlay doubles as the red X over an empty-tool slot -
       upstream's own prim reuse; the chain overlay gets its own prim
       because, unlike the X, it must draw WITH the sweep, not instead of
       it. ]]
  local prims = nil
  if ctx.new_image ~= nil and ctx.new_text ~= nil and ctx.asset ~= nil then
    --[[ Sibling-component construction hygiene: draggable off, one tile,
         never fit-to-texture (fit(true) silently defeats size()), an
         explicit untinted color, and hidden from the first frame. `texture`
         is optional - the icon and sweep prims have no art until content
         picks one. Alphas are config-owned and land at attach. ]]
    --[[ `texture` is relative to the ASSET ROOT, not to any one folder in
         it. It used to have `own/` put in front, which was right for the
         chrome and silently wrong for the sword - `assets/own/icons/...`
         does not exist, and a missing texture draws a bare square rather
         than complaining. Each caller names its own folder now. ]]
    local function image(texture)
      local prim = ctx.new_image()
      prim.draggable(false)
      prim.repeat_xy(1, 1)
      prim.fit(false)
      if texture ~= nil then
        prim.path(ctx.asset(ASSETS .. texture))
      end
      prim.color(255, 255, 255)
      prim.hide()
      return prim
    end

    local function text()
      local prim = ctx.new_text()
      prim.text("")
      prim.hide()
      return prim
    end

    prims = { panel = image("own/bar_bg_compact.png"), groups = {} }
    for _, group in ipairs(GROUPS) do
      local slots = {}
      for slot = 1, SLOT_COUNT do
        -- One shared slot (lib/actionbar/slot) per cell: its nine prims in
        -- upstream's z-order, its paint and its tick. The sweep key is per
        -- prim slot and built once - never per frame.
        slots[slot] = new_slot({
          new_image = ctx.new_image,
          new_text = ctx.new_text,
          asset = ctx.asset,
          config = function()
            return config
          end,
          render = function()
            return render
          end,
          screen_width = function()
            return screen_width
          end,
          hide = config_hide,
          key = group.key .. ":" .. slot,
        })
      end
      prims.groups[group.key] = slots
    end
    prims.set_icon = image("icons/weapons/sword.png")
    -- The active set, written between the two crosses, with the sword that
    -- marks the drawn weapon state to its left.
    prims.set_label = text()
  end

  -- Every slot forgets what it held: a re-attach and a detach both belong
  -- to a bar that is gone.
  local function reset_contents()
    if prims == nil then
      return
    end
    for _, group in ipairs(GROUPS) do
      for slot = 1, SLOT_COUNT do
        prims.groups[group.key][slot].reset()
      end
    end
  end

  -- Which groups the last refresh left on screen, so the tick skips the rest.
  local shown_groups = {}

  local function placement(anchor)
    if render.bounds(anchor) == nil then
      return nil
    end
    local entry = placed[anchor]
    if not entry then
      entry = { scale = 1 }
      placed[anchor] = entry
    end
    return entry
  end

  function self.anchors()
    return ANCHORS
  end

  -- The (set, side) a group displays; nil while no job is scoped or the
  -- view config is broken. Expanded shows whichever view its press order
  -- selected, and nothing while it is not held.
  local function group_target(group)
    if bar.scoped() == nil then
      return nil
    end
    if group.bar == "xhb" then
      return bar.bindings().active_set(), group.side
    end
    local view_name = group.key
    if group.key == "expanded" then
      if active_state ~= "expanded_lr" and active_state ~= "expanded_rl" then
        return nil
      end
      view_name = active_state
    end
    local view = bar.bindings().view_target(view_name)
    if type(view) ~= "table" then
      return nil
    end
    return view.set, view.side
  end

  --[[ Whether a slot of a SHOWN group is actually drawn - the group's own
       visibility is `painted_groups`' half of the question, and this is the
       rest of it. ONE predicate, exactly as `sword_at` is for the sword:
       refresh draws by it and the click hit-tests by it, so a slot nobody
       can see can never swallow the game's click. `hide.empty_slots` is
       what makes the two disagree if they are written twice.

       Empty slots come back for the binder whatever that config says - an
       invisible slot is still a drop target, which is the one thing edit
       mode cannot have - which is why `editing()` is in here. ]]
  local function slot_drawn(group_key, slot)
    local slots = prims ~= nil and prims.groups[group_key] or nil
    local cell = slots ~= nil and slots[slot] or nil
    if cell == nil then
      return false
    end
    return cell.record() ~= nil or editing() or not config_hide("empty_slots")
  end

  --[[ Only the groups actually on screen, with the anchor placement they
       are drawn at, so nothing here can claim a bar that is not there. The
       binder hit-tests its drops and drags with this and the live click
       answers with it, over ONE set of rects (render.slot_rects): the
       reference had two and they disagreed.

       Two sides, deliberately: the group's own half decides where the slots
       are DRAWN, the view's decides what they ADDRESS, which for a WXHB or
       Expanded view is its config's and not the group's. ]]
  local function painted_groups()
    local list = {}
    for _, group in ipairs(GROUPS) do
      local entry = placed[group.anchor]
      local set, side = group_target(group)
      if shown_groups[group.key] and entry ~= nil and entry.pos ~= nil and set ~= nil then
        list[#list + 1] = {
          key = group.key,
          bar = group.bar,
          render_side = group.side,
          side = side,
          x = entry.pos.x,
          y = entry.pos.y,
          scale = entry.scale,
          set = set,
        }
      end
    end
    return list
  end

  --[[ The sword, placed, or nil when there is none on screen. ONE predicate
       for drawing it and for hit-testing it (a click on it sheathes): a
       sword nobody can see must not answer a click, and one on screen must.
       `visible` and `machine` are the widget's own ways of being off - a
       user hide, suppression, or nothing scoped yet. ]]
  local function sword_at()
    if not visible or machine == nil or bar.bindings().weapon_state() ~= "drawn" then
      return nil
    end
    local entry = anchor_at("weapon")
    if entry == nil or entry.pos == nil then
      return nil
    end
    return entry
  end

  -- Applies values that live in config; construction only knows paths.
  local function dress()
    if prims == nil then
      return
    end
    local text_color = type(config.text_color) == "table" and config.text_color or {}
    local stroke = type(config.text_stroke) == "table" and config.text_stroke or {}
    local function dress_text(prim, right_justified)
      prim.font(config.font or "sans-serif")
      prim.size(config.font_size or 7)
      prim.color(text_color.r or 255, text_color.g or 255, text_color.b or 255)
      prim.alpha(text_color.a or 255)
      prim.stroke_width(stroke.width or 0)
      prim.stroke_color(stroke.r or 0, stroke.g or 0, stroke.b or 0)
      -- stroke_alpha, not stroke_transparency: the library reads a 0..1
      -- transparency and would turn a 0-255 alpha wildly negative.
      prim.stroke_alpha(stroke.a or 255)
      -- The texts library draws its own opaque box behind a line unless
      -- told not to, and every sibling widget turns it off (parambar,
      -- partylist, targetbar, equipviewer, lib/overlay). Missing here since
      -- CB4 - a slot label would have carried a black box over the art.
      prim.bg_visible(false)
      prim.right_justified(right_justified == true)
    end
    prims.panel.alpha(config.button_bg_alpha)
    --[[ The set label takes the same dressing every other text gets - the
         stroke, and above all `bg_visible(false)`, without which the texts
         library draws an opaque box behind it - then overrides the two
         things that make it the set label: parambar's size, and gold. ]]
    dress_text(prims.set_label, false)
    prims.set_label.size(SET_LABEL_SIZE)
    prims.set_label.color(SET_LABEL_COLOR[1], SET_LABEL_COLOR[2], SET_LABEL_COLOR[3])
    prims.set_label.alpha(255)
    for _, group in ipairs(GROUPS) do
      for slot = 1, SLOT_COUNT do
        prims.groups[group.key][slot].dress()
      end
    end
  end

  -- Repositions one slot's prims from its anchor's origin and scale. The
  -- icon carries its candidate's offset (the 32x32 sheets centre at +4/+4).
  -- `metrics` is optional and exists for layout(), which places up to forty
  -- slots in one pass: without it every slot builds the same table twice
  -- (once here, once inside slot_pos).
  local function place_slot(group, slot, metrics)
    if prims == nil then
      return
    end
    local entry = placed[group.anchor]
    if entry == nil or entry.pos == nil then
      return
    end
    metrics = metrics or render.metrics()
    local x, y = render.slot_pos(group.bar, group.side, slot, metrics)
    prims.groups[group.key][slot].place(entry.pos.x, entry.pos.y, x, y, entry.scale)
  end

  --[[ Lays out the slots on one anchor, or every group when `anchor` is nil.
       Scoped deliberately, and it is only one of three things that keep a
       layout-mode drag cheap: core's per-move apply() pushes a placement for
       EVERY anchor, then the preview flag, then show(), so scoping this alone
       still left the untouched anchors being re-shown and repainted. The
       other two are the no-op guards on set_pos/set_scale/set_preview/show
       and refresh()'s change-gate, which writes only where the answer
       changed. Measured on the full core sequence, one mouse move costs 433
       prim calls where it once cost 8530, and what remains is this: the
       moved anchor's own slots. ]]
  local function layout(anchor)
    if prims == nil then
      return
    end
    local metrics = render.metrics()
    for _, group in ipairs(GROUPS) do
      if anchor == nil or group.anchor == anchor then
        for slot = 1, SLOT_COUNT do
          place_slot(group, slot, metrics)
        end
      end
    end
  end

  --[[ Applies the visibility plan for the current hold state: which bars
       are on screen, which slots inside them, and where the active-side
       panel sits. Core owns whether the component is visible at all; this
       owns what "visible" shows. Dynamic prims (cost, recast, sweep,
       feedback) are hidden here when their group leaves the screen and
       re-shown by the tick when it next has something to draw. ]]
  local function refresh()
    if prims == nil then
      return
    end
    local hidden = not visible or machine == nil
    local plan = render.visible(active_state, { hidden = hidden })
    if (preview or editing()) and not hidden then
      -- Layout placement: with always_show_wxhb off the WXHB is invisible
      -- in play, so preview forces its halves up to give the anchors a
      -- visible footprint. Edit mode wants them for the same reason from
      -- the other end - every side must be reachable by mouse.
      plan.wxhb_left = true
      plan.wxhb_right = true
    end
    shown_groups = {}
    for _, group in ipairs(GROUPS) do
      local entry = anchor_at(group.anchor)
      local shown
      if group.key == "expanded" then
        shown = plan.expanded ~= nil
      else
        shown = plan[group.flag] == true
      end
      shown = shown and entry ~= nil and entry.pos ~= nil
      shown_groups[group.key] = shown
      for slot = 1, SLOT_COUNT do
        -- Empty slots come back for the binder whatever the config says:
        -- an invisible slot is still a drop target, which is the one thing
        -- edit mode cannot have (slot_drawn's own rule).
        prims.groups[group.key][slot].show(shown, slot_drawn(group.key, slot))
      end
    end
    local panel_shown = false
    if plan.panel ~= nil then
      local anchor = plan.panel.bar == "wxhb" and ("wxhb_" .. plan.panel.side) or "main"
      local entry = anchor_at(anchor)
      if entry ~= nil and entry.pos ~= nil then
        local rect = render.panel_pos(plan.panel.bar, plan.panel.side)
        prims.panel.pos(entry.pos.x + rect.x * entry.scale, entry.pos.y + rect.y * entry.scale)
        prims.panel.size(rect.width * entry.scale, rect.height * entry.scale)
        prims.panel.show()
        panel_shown = true
      end
    end
    if not panel_shown then
      prims.panel.hide()
    end
    --[[ The set label, on its own anchor: it says which set the XHB is on,
         which is true whether or not a side is held, so it is shown
         whenever the widget is - and it is not a panel, so nothing about
         the hold state moves it. ]]
    local set_at = anchor_at("set")
    if not hidden and set_at ~= nil and set_at.pos ~= nil then
      prims.set_label.pos(set_at.pos.x, set_at.pos.y)
      prims.set_label.size(math.floor(SET_LABEL_SIZE * set_at.scale + 0.5))
      prims.set_label.text(render.set_label(bar.bindings().active_set()))
      prims.set_label.show()
    else
      prims.set_label.hide()
    end
    --[[ The sword, likewise its own: shown while the weapon is drawn,
         hidden while it is sheathed. Nothing reserves its space any more
         and nothing needs to - the label cannot move when the sword goes,
         because the two no longer share an origin.

         This is the component's OWN weapon state, not the client's status
         - the same state that picks which set rotation is live - so it
         lights on `draw` even with nothing targeted, which is what makes
         that press visible at all. ]]
    local weapon_at = sword_at()
    if weapon_at ~= nil then
      local icon_size = render.set_icon_size() * weapon_at.scale
      prims.set_icon.pos(weapon_at.pos.x, weapon_at.pos.y)
      prims.set_icon.size(icon_size, icon_size)
      prims.set_icon.show()
    else
      prims.set_icon.hide()
    end
  end

  -- Re-resolves one slot's content: the record through the live layer
  -- stack, its meta, then the slot draws it.
  local function paint_slot(group, slot, state)
    local cell = prims ~= nil and prims.groups[group.key][slot] or nil
    if cell == nil then
      return
    end
    local record, source = nil, nil
    local set, side = group_target(group)
    if set ~= nil then
      record, source = bar.bindings().resolve(set, side, slot)
    end
    if record ~= nil then
      state = state or draw_state()
    end
    cell.paint(record, bar.meta_for(record), {
      state = state,
      builtin = record ~= nil and icon_for(record, state) or nil,
      --[[ The source tag, edit mode only: nothing for the job base (the
           common case), one mark for a subjob layer and another for a
           context, so "where is this coming from" is answered before any
           click - and the tags leave with edit mode, since the played bar
           has no room for them. ]]
      mark = (record ~= nil and editing()) and bar.binder().mark(source) or "",
      resolve_icon = bar.pick_icon,
      item_icon = bar.item_icon,
    })
    place_slot(group, slot)
  end

  local function repaint()
    if prims ~= nil then
      -- One draw-state read per repaint, not one per slot.
      local state = draw_state()
      for _, group in ipairs(GROUPS) do
        for slot = 1, SLOT_COUNT do
          paint_slot(group, slot, state)
        end
      end
    end
    -- Which ids need counting can only change here, and rarely does.
    bar.check_bound_items()
    refresh()
    -- Whatever moved the bar moved what the binder's panels are describing
    -- too. Closed, this costs a nil check.
    bar.binder().refresh()
  end

  -- An icon landing on disk can only change slots still waiting for item
  -- art, so only those repaint - a full repaint would re-stat every settled
  -- slot's candidates each time the queue lands one. (Chosen over teaching
  -- lib/icon_cache to report which id landed: no lib API change, and
  -- equipviewer stays untouched.)
  local function repaint_unresolved_items()
    if prims ~= nil then
      local state = draw_state()
      for _, group in ipairs(GROUPS) do
        for slot = 1, SLOT_COUNT do
          if prims.groups[group.key][slot].awaiting_item_icon() then
            paint_slot(group, slot, state)
          end
        end
      end
    end
    refresh()
  end

  local function flash(group_key, slot)
    -- A hand-edited config can name a ninth slot key: the binding still
    -- fires, but there is no ninth prim to flash.
    local slots = prims ~= nil and prims.groups[group_key] or nil
    local cell = slots ~= nil and slots[slot] or nil
    if cell ~= nil then
      cell.flash()
    end
  end

  -- The (set, side) a hold state fires from, plus the group that flashes.
  local function state_target(state)
    if state == "xhb_left" or state == "xhb_right" then
      return bar.bindings().active_set(), state:sub(5), state
    end
    if state == "wxhb_left" or state == "wxhb_right" then
      local view = bar.bindings().view_target(state)
      if type(view) == "table" then
        return view.set, view.side, state
      end
    elseif state == "expanded_lr" or state == "expanded_rl" then
      local view = bar.bindings().view_target(state)
      if type(view) == "table" then
        return view.set, view.side, "expanded"
      end
    end
    return nil
  end

  --[[ Fire one slot of one (set, side), whatever pointed at it. A KEY press
       reads the hold state for that pair; a CLICK has no hold state to read
       and takes the pair off the group it landed on. Everything after the
       resolve is the bar's and then the service's, so two ways in cannot
       become two behaviours. ]]
  local function fire_at(set, side, slot, group_key)
    bar.fire(set, side, slot, function()
      flash(group_key, slot)
    end)
  end

  -- The keyboard's way in: the pair comes from whichever side is held.
  local function fire_slot(slot)
    if bar.scoped() == nil or machine == nil then
      return
    end
    local set, side, group_key = state_target(machine.hold_state())
    if set == nil then
      return
    end
    fire_at(set, side, slot, group_key)
  end

  --[[ The chain result: while the window is open, a WS or JA slot whose
       action would continue the resonation swaps to the property's icon -
       WS and JA/pet each by the action's own id. Deviation from the
       reference fork, its own bug fixed: the fork queries JA slots by
       recast_id, but the chain table is keyed by ability id and the two
       are disjoint across all 75 entries (blood pacts share recast 173,
       Ready moves 102), so its JA slots can never light. ]]
  local function chain_result(record, meta)
    if record.type == "ws" and meta.ws_id ~= nil then
      return skillchain.result(meta.ws_id, "weapon_skills")
    elseif (record.type == "ja" or record.type == "pet") and meta.ability_id ~= nil then
      return skillchain.result(meta.ability_id, "job_abilities")
    end
    return nil
  end

  --[[ A mount slot's two conditions, which part company the moment you are
       actually mounted: the ZONE stops applying (you can be riding
       somewhere you could not have mounted, and the press is a dismount,
       never held up) while the RECAST does not - it is the one thing still
       true while you ride, so it keeps counting and keeps the slot dim
       (Kevin's call, 2026-08-29), even though the press would dismount.
       Skipping it along with the zone made the sweep vanish the instant
       the mount landed. ]]
  local function mount_facts()
    if roulette == nil then
      return nil
    end
    return { blocked = not roulette.mounted() and roulette.blocked(), cooldown = roulette.cooldown() }
  end

  local function tick()
    bar.tick_scope(ctx.now ~= nil and ctx.now() or 0)
    bar.sync_weapon()
    if bar.drain_icons() then
      -- An icon landed on disk; only unresolved item slots can care.
      repaint_unresolved_items()
    end
    if prims == nil or bar.scoped() == nil then
      return
    end
    --[[ Hidden or suppressed: zero client reads. The test is the WIDGET's own
         switch, deliberately - it was "is any group on screen" until
         2026-08-31, which a per-anchor hide of `main` also satisfies, and
         everything below here stopped dead on `//hud hide crossbar main`.
         Hiding one anchor is not hiding the bar. ]]
    if not visible then
      return
    end
    -- The per-slot chain results, only while the window is actually open;
    -- the border animation's clock advances once per tick, shared by every
    -- slot. The window bar itself is the skillchain component's.
    local sc_delay, sc_window = skillchain.window()
    local chain_step = nil
    if sc_window > 0 and sc_delay <= 0 and not config_hide("skillchain_icon") then
      chain_step = render.chain_tick()
    end
    bar.recount_if_dirty()
    -- Client reads ride lib/player's read counter; the bar keeps them.
    bar.refresh_reads(ctx.generation and ctx.generation() or nil)
    local reads = bar.reads()
    local player = reads.player
    local ability_recasts = reads.ability_recasts
    -- One facts table per tick, shared by every slot: what only this bar
    -- (or the service it reads) can answer for the slot's draw.
    local facts = {
      player = player,
      vitals = player and player.vitals or {},
      spell_recasts = reads.spell_recasts,
      ability_recasts = ability_recasts,
      chain_step = chain_step,
      counter = function(record, meta)
        return bar.counter_for(record, meta, player, ability_recasts)
      end,
      chain_result = chain_result,
      mount = mount_facts,
    }
    for _, group in ipairs(GROUPS) do
      if shown_groups[group.key] then
        for slot = 1, SLOT_COUNT do
          prims.groups[group.key][slot].tick(facts)
        end
      end
    end
  end

  --[[ A shortcut key's verb: a `//hud crossbar` line without the prefix, OR
       one of the framework's own verbs - `draw`, `mr`, `sneak`, `invisible`
       and `warp [all]` left the bar's dispatcher on 2026-09-06 and a pad
       button bound to one must still fire it. ]]
  local FRAMEWORK_VERBS = { draw = true, mr = true, sneak = true, invisible = true }
  local function run_shortcut(verb)
    if type(verb) ~= "string" then
      return
    end
    local words = {}
    for word in verb:gmatch("%S+") do
      words[#words + 1] = word
    end
    local first = type(words[1]) == "string" and words[1]:lower() or nil
    if first == "warp" then
      service.warp(type(words[2]) == "string" and words[2]:lower() == "all")
      return
    end
    if FRAMEWORK_VERBS[first] then
      local hint = service.builtin(first)
      bar.sync_weapon()
      if hint ~= nil then
        say(hint)
      end
      return
    end
    local reply = bar.command(words)
    if reply ~= nil then
      say(reply)
    end
  end

  --[[ The bar's state, built here at the foot: every dep below closes over
       a local defined above it. The widget's own edit-mode housekeeping
       rides `on_edit`: no side is active in edit mode - the mode is entered
       by HOLDING a side and pressing Select, so the side that opened it
       would otherwise stay lit for as long as the mode was on (Kevin, live
       client, 2026-08-22) - and on the way out the machine is re-read,
       since the activate intents that arrived meanwhile went unheard. ]]
  bar = new_bar({
    name = "crossbar",
    grammar = grammars.crossbar(),
    views = true,
    ctx = ctx,
    config = function()
      return config
    end,
    save = function()
      if save ~= nil then
        save()
      end
    end,
    -- The live render instance, not the construction-time one: attach
    -- rebuilds it over the user's own config.
    render = function()
      return render
    end,
    -- Expanded Hold cannot appear in this one: the widget ignores every
    -- activate intent while the binder is up, and the displayed state is
    -- `none`, which on_edit forces on the way in.
    groups = painted_groups,
    cells = function(visit)
      if prims == nil then
        return
      end
      for _, group in ipairs(GROUPS) do
        for slot = 1, SLOT_COUNT do
          visit(prims.groups[group.key][slot])
        end
      end
    end,
    repaint = repaint,
    visible = function()
      return visible
    end,
    on_edit = function(open)
      -- The owed release is settled here too, beside hide, detach and
      -- set_preview: from here the binder answers the mouse, so a debt the
      -- bar took is owed to nothing.
      swallow_left_up = false
      if open then
        active_state = "none"
      else
        active_state = machine and machine.hold_state() or "none"
      end
    end,
  })

  --[[ The widget contract ------------------------------------------------- ]]

  function self.attach(new_config, persist, store)
    -- Re-read on every attach (targetbar's precedent): the right-justified
    -- text x subtracts the width, and a resolution change must correct
    -- here. The height's only consumer is the construction-time defaults.
    screen_width = ctx.screen()
    config = type(new_config) == "table" and new_config or self.defaults
    save = persist
    render = new_render({ config = config, icon_for = icon_for })
    bar.attach(store)
    reset_contents()
    -- A hand-broken input block degrades to the shipped defaults rather
    -- than crashing attach: one bad config file at login would otherwise
    -- leave every component after this one unattached.
    machine = new_input({
      keys = type(config.input) == "table" and config.input or self.defaults.input,
      chat_open = ctx.chat_open,
      suppressed = ctx.suppressed,
      layout_mode = ctx.layout_active,
      --[[ The sixth guard, live from CB8: while the binder is up the
           crossbar's own keys fire nothing and keep tracking. TWO live
           inputs now, not one - the shortcut key that exits, and the set
           SWITCH, because which set is on screen is what edit mode is for
           (2026-08-22). Slot keys stay the game's there unless the switch
           is held, which is the jump chord and is blocked. ]]
      -- ANY bar's binder, not just this one's: the pair goes inert together.
      edit_mode = function()
        return service.edit_owner() ~= nil
      end,
      disabled = function()
        --[[ Disabled means the USER-hidden case only, and it outranks
             suppression: a crossbar the player turned off keeps its keys
             with the game through cutscenes and zoning. Core's user flag
             is the one truthful source - suppression and a user hide both
             reach this widget as hide() (and a hide arriving DURING a
             cutscene is never signalled at all, the widget already being
             hidden), so show()/hide() cannot rank the two. ]]
        if ctx.component_visible ~= nil then
          return ctx.component_visible() ~= true
        end
        -- Degraded ctx (the wire missing): infer from show()/hide() and
        -- rank suppression above the ambiguous hidden state.
        return not visible and not (ctx.suppressed ~= nil and ctx.suppressed() == true)
      end,
    })
    --[[ A hand-edited key map can give one DIK two jobs; input.lua keeps the
         first claim and drops the rest, and this is the only place the player
         would ever hear about it - said once per config read, not once per
         press, and one line per key so a map broken twice reads as two
         problems. ]]
    if ctx.say ~= nil then
      for _, clash in ipairs(machine.conflicts()) do
        ctx.say(
          ("crossbar: DIK %d is bound to more than one thing - %s wins, and %s is ignored"):format(
            clash.dik,
            clash.kept,
            table.concat(clash.dropped, " and ")
          )
        )
      end
    end
    active_state = "none"
    dress()
    layout()
    -- The login may already be far enough along to name the job; otherwise
    -- the tick keeps looking (core scopes on the character name alone -
    -- anything else a component needs it waits for itself).
    bar.try_scope()
    repaint()
  end

  function self.detach()
    -- Nothing owed to a click on a bar that is going away.
    swallow_left_up = false
    -- The bar's half: the binder goes down with the scope, the service
    -- drops the trip and the held cast, the bindings are rebuilt empty.
    bar.detach()
    -- Core's save belongs to the attached config; holding it past a detach
    -- would write a config this widget no longer has.
    save = nil
    -- The machine is rebuilt on attach (the plan's detach handshake): a key
    -- released while detached would otherwise strand held/down/latch state
    -- and make the next press read as an auto-repeat.
    machine = nil
    active_state = "none"
    reset_contents()
    refresh()
  end

  function self.on_keyboard(key, down, flags, blocked)
    if not machine then
      return false
    end
    local intents, block = machine.on_key(key, down, flags, blocked)
    for _, intent in ipairs(intents) do
      if intent.type == "activate" then
        --[[ Activations are silent: the panel shows which side is active.
             OPEN QUESTION (chat-focus display): `activate` passes
             the chat guard by design, so the display follows the physical
             keys even while the chat box has focus. A "freeze the display
             while chat has focus" option would gate THIS branch on
             ctx.chat_open() - nothing else - and is deliberately not
             decided here.

             Edit mode is the one state that ignores them outright: the
             machine keeps tracking every key (CB0's contract is untouched),
             but the widget stops reacting, so no side lights and Expanded
             never replaces the XHB. The slots CAN move under an open binder
             window, though - the set switch is live in edit mode - which is
             why a set change puts that window away (see set_changed).
             close_edit() reads hold_state() on the way out, the same
             handshake show() uses. ]]
        if not editing() then
          local was_expanded = active_state == "expanded_lr" or active_state == "expanded_rl"
          active_state = intent.state
          local is_expanded = active_state == "expanded_lr" or active_state == "expanded_rl"
          if was_expanded ~= is_expanded or is_expanded then
            -- Entering Expanded (or crossing between its two views) is the
            -- one activation that changes CONTENT, not just visibility.
            repaint()
          else
            refresh()
          end
        end
      elseif intent.type == "fire" then
        fire_slot(intent.slot)
      elseif intent.type == "jump" then
        local before = bar.bindings().active_set()
        if bar.bindings().jump(intent.set) ~= nil then
          bar.set_changed(before)
        end
      elseif intent.type == "cycle" then
        local before = bar.bindings().active_set()
        if bar.bindings().cycle() ~= nil then
          bar.set_changed(before)
        end
      elseif intent.type == "draw" then
        service.builtin("draw")
        bar.sync_weapon()
      elseif intent.type == "shortcut" then
        run_shortcut(intent.verb)
      end
    end
    return block
  end

  function self.update(event, a, ...)
    if event == nil then
      tick()
      return
    end
    if event == "lose focus" then
      if machine ~= nil then
        machine.focus_lost()
        active_state = "none"
        refresh()
      end
    elseif event == "job change" then
      -- The event carries (main_id, main_lv, sub_id, sub_lv); the bar holds
      -- the reload until the client agrees with both ids.
      bar.on_job_change(a, ...)
    elseif event == "gain buff" or event == "lose buff" then
      bar.sync_buffs()
      if a == MOUNTED_BUFF then
        -- Not a context, but the draw slot's icon follows it.
        repaint()
      end
    elseif event == "status" then
      -- The service has already heard the status from the entry point; the
      -- rotation follows whatever it made of it.
      bar.sync_weapon()
    elseif event == "add item" or event == "remove item" then
      bar.on_item_event(a)
    elseif event == "chunk" then
      -- Coalesced by the flag, so an equip burst or a zone-in's inventory
      -- dump costs one re-read on the next tick rather than one per packet.
      if a == INVENTORY_CHUNK and bar.counts_from_inventory() then
        bar.mark_counts_dirty()
      end
      -- Coalesced the same way: an equip burst, or a zone-in's whole bag
      -- dump, costs one re-read on the next interval rather than one each.
      if a == INVENTORY_READY_CHUNK then
        bar.mark_weapon_dirty()
      elseif a == EQUIP_CHUNK then
        local raw = ...
        local equip = ctx.parse_packet ~= nil and ctx.parse_packet(raw) or nil
        local moved = type(equip) == "table" and equip["Equipment Slot"] or nil
        if moved == nil or moved == MAIN_HAND_SLOT then
          bar.mark_weapon_dirty()
        end
      end
    end
  end

  --[[ Core pushes scale AND position for every anchor on every mouse move,
       though a drag moves one anchor and changes only one of the two; the
       push that changes nothing is dropped before it can lay anything out. ]]
  function self.set_pos(x, y, anchor)
    local entry = placement(anchor)
    if entry == nil or (entry.pos ~= nil and entry.pos.x == x and entry.pos.y == y) then
      return
    end
    entry.pos = { x = x, y = y }
    layout(anchor)
    refresh()
  end

  function self.set_scale(scale, anchor)
    local entry = placement(anchor)
    if entry == nil or entry.scale == scale then
      return
    end
    entry.scale = scale
    layout(anchor)
    refresh()
  end

  function self.set_preview(on)
    local wanted = on == true
    -- Core pushes the flag on every apply, which during a layout-mode drag
    -- is every mouse move; only a change is worth a pass.
    if wanted == preview then
      return
    end
    preview = wanted
    -- The third place the sword's owed release is settled, beside hide and
    -- detach: layout mode opening between the two edges of a click owes it
    -- to nothing.
    swallow_left_up = false
    if preview then
      -- Core sets preview as layout mode opens, which is the one signal a
      -- component gets for it: entering layout mode exits edit mode, so the
      -- two never contend for the mouse. close_edit repaints on its own;
      -- preview itself only changes which groups the plan raises.
      bar.close_edit()
    end
    refresh()
  end

  --[[ Core calls show() on every apply, so a layout-mode drag calls it on
       every mouse move; a widget already on screen has nothing to re-sync
       and must not repaint forty slots (or re-read the player) for it. The
       work below is the way back from hidden - a user hide, or core's
       suppression - and `visible` is the one thing that says which this is.
       Preview and edit-mode toggles do their own repainting, so nothing
       else rides on this call.

       An anchor name narrows the call to that anchor. The BARE form is the
       widget's own switch and puts every anchor back up: it is what layout
       mode force-shows with, and a hidden anchor that stayed hidden there
       could never be dragged or switched back on. ]]
  function self.show(anchor)
    local restored = false
    if anchor == nil then
      restored = next(hidden_anchors) ~= nil
      hidden_anchors = {}
    elseif hidden_anchors[anchor] then
      hidden_anchors[anchor] = nil
      restored = true
    end
    if visible then
      if restored then
        -- Repaint rather than refresh, for the reason below: the anchor's
        -- groups painted nothing while they were down.
        repaint()
      end
      return
    end
    visible = true
    -- Resync the side memory: while hidden the widget is disabled, so the
    -- machine swallowed releases (and ignored presses) without emitting
    -- activate intents, and the memory here went stale. This is the plan's
    -- suppression re-enable handshake: read hold_state() on the way back.
    active_state = machine and machine.hold_state() or "none"
    -- And repaint, not just refresh: an Expanded hold entered while hidden
    -- never painted its view's contents (group_target answered nil), so a
    -- bare refresh would show an empty bar. The change-gate and icon memo
    -- keep this cheap when nothing actually changed.
    repaint()
  end

  function self.hide(anchor)
    --[[ One anchor going down takes nothing else with it: the widget is still
         on screen and still the owner of its keys, so none of the teardown
         below applies - a retry or a trip is not a property of the anchor the
         user just switched off. ]]
    if anchor ~= nil then
      if hidden_anchors[anchor] then
        return
      end
      hidden_anchors[anchor] = true
      refresh()
      return
    end
    visible = false
    -- Suppression (a cutscene, zoning) and a user hide both arrive here,
    -- and a cast held through either would fire into a moment that has
    -- gone. Nothing the retry holds outlives the bar being on screen, and
    -- neither does a trip counting down - nor the sword's owed release,
    -- which core would go on dispatching to a hidden component and which
    -- would then be paid out of the game's next click.
    swallow_left_up = false
    service.bar_hidden("crossbar")
    -- A hidden crossbar has no bar to bind against, and its panels would be
    -- left floating over a screen with nothing under them. Suppression
    -- (cutscene, zoning) arrives here as a hide too, and takes the binder
    -- with it for the same reason.
    bar.close_edit()
    refresh()
  end

  -- The same origin set_pos was given, with render.lua's real footprint:
  -- main answers the whole XHB whatever is currently drawn in it.
  function self.get_bounds(anchor)
    local entry = placed[anchor]
    if not entry or not entry.pos then
      return nil
    end
    local width, height = render.bounds(anchor, entry.scale)
    return entry.pos.x, entry.pos.y, width, height
  end

  function self.handle_command(args)
    return bar.command(args)
  end

  --[[ The mouse, dispatched by core while any component declares
       `on_mouse` (touchpoint 3). Core has already answered an event layout
       mode owns or another addon took, so everything arriving here is
       genuinely free. Closed, a move costs two comparisons and nothing
       else: only a left-down reaches the sword's placement, and only a
       left-up reads the debt below. ]]
  function self.on_mouse(mouse_type, x, y, delta)
    if editing() then
      return bar.binder().mouse(mouse_type, x, y, delta) == true
    end
    --[[ Another bar's binder is open: the click is that binder's, whatever
         it lands on - core does not short-circuit the mouse, so this bar
         would otherwise fire a slot under the other's picker (the shipped
         hotbar row sits inside the crossbar's binder window). ]]
    if service.edit_owner() ~= nil then
      return false
    end
    --[[ A left-click on the sword sheathes. The sword is drawn only while
         the weapon state is DRAWN, so the click is one way and resolves
         straight to `sheathe` rather than through the `draw` verb, which
         answers the state it is given and mounted would dismount instead
         (Kevin, 2026-09-05). Preview is layout mode opening: core stops
         dispatching then, and this refuses in the same breath rather than
         relying on it. Edit mode above is a no-op for the sword by the same
         decision - the binder is for authoring the bar, not firing it, and
         it answers the click itself, whatever it makes of it.
         Both edges are swallowed, so the game does not act on a click that
         was ours; the release is answered on the flag alone, since a press
         that started on the sword is ours wherever the button comes up. A
         fresh press clears that debt first (the binder's rule for the same
         hazard): a release taken by an addon ahead of us, or arriving while
         suppression has dispatch off, would otherwise leave it owed to a
         click that never comes and swallow the game's next one. ]]
    if mouse_type == MOUSE_LEFT_UP then
      local owed = swallow_left_up
      swallow_left_up = false
      return owed
    end
    if mouse_type ~= MOUSE_LEFT_DOWN then
      return false
    end
    swallow_left_up = false
    --[[ Layout mode owns the mouse outright, and is refused on BOTH the
         signals that say so: core sets `preview` as it opens, and
         `layout_active` is the client-side reader every other refusal in
         this file uses. In production they agree - core stops dispatching
         before either could matter - so this is belt and braces over a
         gesture that would otherwise fire while the player is dragging the
         bar around. ]]
    if preview or layout_active() then
      return false
    end
    --[[ The sword is asked FIRST, so it wins where it has been dragged over
         a slot: ANCHORS orders `weapon` after `main`, and layout mode
         hit-tests later anchors over earlier ones. One precedence, not two.
         The slot under it is reached by moving the sword off it. ]]
    local entry = sword_at()
    if entry ~= nil then
      -- Two returns, so no `and`/`or`: that idiom keeps only the first, and
      -- a nil height would compare against nothing.
      local width, height = render.bounds("weapon", entry.scale)
      if width ~= nil and inside(x, y, entry.pos.x, entry.pos.y, width, height) then
        service.sheathe()
        bar.sync_weapon()
        swallow_left_up = true
        return true
      end
    end
    --[[ Otherwise a slot, which fires what it holds. The GROUP under the
         cursor gives the (set, side), since a click has no hold state to
         read - so a WXHB half fires what that half displays. A slot the
         player can see is the bar's pixel whether or not anything is bound
         to it: an empty one is silent, exactly as its key press is, but the
         click is still ours rather than handed on to the game. ]]
    local rect = render.slot_at(painted_groups(), x, y, function(candidate)
      return slot_drawn(candidate.key, candidate.slot)
    end)
    if rect == nil then
      return false
    end
    fire_at(rect.set, rect.side, rect.slot, rect.key)
    swallow_left_up = true
    return true
  end

  function self.destroy()
    bar.destroy()
    if prims == nil then
      return
    end
    prims.panel.destroy()
    prims.set_label.destroy()
    prims.set_icon.destroy()
    for _, group in ipairs(GROUPS) do
      for slot = 1, SLOT_COUNT do
        prims.groups[group.key][slot].destroy()
      end
    end
    prims = nil
  end

  return self
end

return new
