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

--[[ One slot of an action bar: its nine prims and everything drawn into
     them, shared by every bar so a crossbar slot and a hotbar slot cannot
     drift. The bar owns WHERE the slot is (it calls `place` with the origin
     its geometry answers) and WHAT it holds (it resolves the record through
     its own bindings and hands it to `paint`); this owns how that record is
     drawn, from the label cut to the recast sweep, and the change-gate that
     keeps a settled slot from writing a prim sixty times a second.

     Prim creation order IS z-order (creation order draws bottom to top),
     mirroring upstream's ui.lua:407-412: background, then the chain overlay
     (the per-slot chain result, upstream's slot_warmup), icon, the
     sweep/red-X overlay, the frame - so the frame-step border animation
     draws OVER the chain icon and the sweep, as shipped - and the press
     flash above everything, which is where the reference loads its feedback
     icon ("last so it stays above everything else"). Then the three texts:
     name, cost, recast. The crossbar's spec addresses prims by that order.

     Deps: `new_image`, `new_text`, `asset` (an addon-relative path to a
     full one), `config()` (the bar's live config), `render()` (the bar's
     live lib/actionbar/render), `screen_width()`, `hide(key)` (the bar's
     `hide.<key>` switch) and `key`, this slot's own sweep key. ]]

-- The asset ROOT, not one folder in it: what hangs off this is `own/` for
-- XIVHud's own chrome, `icons/` for the imported pack and `cooldown/` for
-- the sweep frames, each with its own licence beside it.
local ASSETS = "assets/"
-- Upstream's fixed overlay alpha for the recast sweep and the red X.
local OVERLAY_ALPHA = 150
-- A chain result over a weaponskill short of its TP: the pair draws dimmed.
local SC_DIM_ICON_ALPHA = 75
local SC_DIM_FRAME_ALPHA = 150
-- The counter's colour when the counter names none of its own.
local PLAIN_COUNT_COLOR = { 255, 255, 255 }

-- `mr` and a named mount share the recast and the zone rule: both are
-- the same one command to the game.
local function is_mount_record(record)
  return record ~= nil and (record.type == "mount" or record.type == "mr")
end

local function new(deps)
  local self = {}

  local function config()
    return deps.config()
  end

  local function render()
    return deps.render()
  end

  local function asset(path)
    return deps.asset(ASSETS .. path)
  end

  --[[ Sibling-component construction hygiene: draggable off, one tile,
       never fit-to-texture (fit(true) silently defeats size()), an explicit
       untinted color, and hidden from the first frame. `texture` is
       optional - the icon and sweep prims have no art until content picks
       one. Alphas are config-owned and land at dress(). ]]
  local function image(texture)
    local prim = deps.new_image()
    prim.draggable(false)
    prim.repeat_xy(1, 1)
    prim.fit(false)
    if texture ~= nil then
      prim.path(asset(texture))
    end
    prim.color(255, 255, 255)
    prim.hide()
    return prim
  end

  local function text()
    local prim = deps.new_text()
    prim.text("")
    prim.hide()
    return prim
  end

  local pair = {
    background = image("own/slot.png"),
    chain = image(),
    icon = image(),
    sweep = image(),
    frame = image("own/frame.png"),
    feedback = image("own/feedback.png"),
    name = text(),
    cost = text(),
    recast = text(),
  }
  self.prims = pair

  -- Per-slot content resolved at paint time: the record, its meta, the
  -- icon candidate that won, and the press-flash alpha in flight.
  local content = { written = {} }

  --[[ The change-gate: nothing is written to a prim that already holds it
       (partylist's written/push pattern - 363 prims at sixty frames a
       second would otherwise rewrite every value each tick). `written` is
       the last value pushed, per prim property; paint and the not-shown
       blanking keep it truthful so event-driven writes stay authoritative. ]]
  local function push(key, value, apply)
    if content.written[key] == value then
      return
    end
    content.written[key] = value
    apply(value)
  end

  local function want(prim, key, on)
    on = on and true or false
    if content.written[key] == on then
      return
    end
    content.written[key] = on
    if on then
      prim.show()
    else
      prim.hide()
    end
  end

  local function push_color(prim, key, r, g, b)
    local encoded = r * 65536 + g * 256 + b
    if content.written[key] == encoded then
      return
    end
    content.written[key] = encoded
    prim.color(r, g, b)
  end

  -- The sweep overlay's one gated write: `mode` is false (hidden), "x" (the
  -- red X) or a frame number - compared BEFORE any path string is built, so
  -- a slot whose frame index has not moved costs no allocation at all.
  local function set_sweep(mode)
    if content.written["sweep.mode"] == mode then
      return
    end
    content.written["sweep.mode"] = mode
    if mode == false then
      pair.sweep.hide()
      return
    end
    if mode == "x" then
      pair.sweep.path(asset("own/red-x.png"))
    else
      pair.sweep.path(asset(("cooldown/frame_%02d.png"):format(mode)))
    end
    pair.sweep.alpha(OVERLAY_ALPHA)
    pair.sweep.show()
  end

  -- The chain overlay's gated write: `prop` is false (hidden) or the
  -- property whose icon to draw - compared before any path string is built.
  local function set_chain(prop)
    if content.written["chain.prop"] == prop then
      return
    end
    content.written["chain.prop"] = prop
    if prop == false then
      pair.chain.hide()
      return
    end
    pair.chain.path(asset("icons/skillchain/" .. prop:lower() .. ".png"))
    pair.chain.show()
  end

  -- The slot frame doubles as the chain border animation: `step` is false
  -- (the plain frame) or a frame_step index.
  local function set_frame(step)
    if content.written["frame.step"] == step then
      return
    end
    content.written["frame.step"] = step
    if step == false then
      pair.frame.path(asset("own/frame.png"))
      return
    end
    pair.frame.path(asset(("own/frame_step%d.png"):format(step)))
  end

  -- Applies values that live in config; construction only knows paths.
  function self.dress()
    local live = config()
    local text_color = type(live.text_color) == "table" and live.text_color or {}
    local stroke = type(live.text_stroke) == "table" and live.text_stroke or {}
    local function dress_text(prim, right_justified)
      prim.font(live.font or "sans-serif")
      prim.size(live.font_size or 7)
      prim.color(text_color.r or 255, text_color.g or 255, text_color.b or 255)
      prim.alpha(text_color.a or 255)
      prim.stroke_width(stroke.width or 0)
      prim.stroke_color(stroke.r or 0, stroke.g or 0, stroke.b or 0)
      -- stroke_alpha, not stroke_transparency: the library reads a 0..1
      -- transparency and would turn a 0-255 alpha wildly negative.
      prim.stroke_alpha(stroke.a or 255)
      -- The texts library draws its own opaque box behind a line unless
      -- told not to, and every sibling widget turns it off.
      prim.bg_visible(false)
      prim.right_justified(right_justified == true)
    end
    pair.background.alpha(live.slot_alpha)
    pair.frame.alpha(255)
    dress_text(pair.name, false)
    dress_text(pair.cost, true)
    dress_text(pair.recast, true)
  end

  --[[ Repositions the prims from the anchor origin (ax, ay), the slot's
       unscaled origin (x, y) inside it, and the anchor's scale. The icon
       carries its candidate's offset (the 32x32 sheets centre at +4/+4).
       The cost and recast texts are right-justified, so their drawn x
       hangs off the screen's right edge - subtracted AFTER scaling, or the
       screen term would scale with the anchor (the texts-library gotcha
       giltracker documents). ]]
  function self.place(ax, ay, x, y, scale)
    local size = render().slot_size() * scale
    local px, py = ax + x * scale, ay + y * scale
    pair.background.pos(px, py)
    pair.background.size(size, size)
    pair.frame.pos(px, py)
    pair.frame.size(size, size)
    pair.sweep.pos(px, py)
    pair.sweep.size(size, size)
    pair.feedback.pos(px, py)
    pair.feedback.size(size, size)
    pair.chain.pos(px, py)
    pair.chain.size(size, size)
    local offset = content.offset or { x = 0, y = 0 }
    local slot_size = render().slot_size()
    pair.icon.pos(ax + (x + offset.x) * scale, ay + (y + offset.y) * scale)
    pair.icon.size((slot_size - 2 * offset.x) * scale, (slot_size - 2 * offset.y) * scale)
    local offsets = render().text_offsets(x, y)
    local font_size = (config().font_size or 7) * scale
    local screen_width = deps.screen_width()
    pair.name.pos(ax + offsets.name.x * scale, ay + offsets.name.y * scale)
    pair.name.size(font_size)
    pair.cost.pos(ax + offsets.cost.x * scale - screen_width, ay + offsets.cost.y * scale)
    pair.cost.size(font_size)
    pair.recast.pos(ax + offsets.recast.x * scale - screen_width, ay + offsets.recast.y * scale)
    pair.recast.size(font_size)
  end

  --[[ Re-resolves the slot's content from the record the bar resolved for
       it: its meta, its icon, its label. `opts`:

         state         the service's draw state, for a built-in's icon
         builtin       actions.icon_for's answer for the record and state
         mark          the edit-mode source tag, or "" (added AFTER the cut,
                       so a name loses the same characters either way)
         resolve_icon  fn(record, meta, state) -> the first existing
                       candidate, or nil
         item_icon     fn(item_id) -> "awaiting" when the shared cache has
                       been asked to extract the item's art and this slot
                       should repaint when it lands; anything else otherwise

       The bar calls `place` afterwards: a fresh icon carries a fresh offset. ]]
  function self.paint(record, meta, opts)
    opts = opts or {}
    content.written = {}
    if record ~= content.record then
      -- The slot's action changed: its recast denominator is the OLD
      -- action's and must be re-learned, or a fresh 30s recast draws
      -- nearly done under a stale 300s maximum. The icon memo goes the
      -- same way, and so does the chain result - the new action's is the
      -- next tick's to compute, and until it does the OLD action's
      -- property must not be left on screen. The prim comes down with the
      -- state, or one frame draws the dead one.
      render().clear_sweep(deps.key)
      content.icon_memo = nil
      content.chain_prop = nil
      pair.chain.hide()
      content.written["chain.prop"] = false
    end
    content.record = record
    content.meta = meta
    content.label = nil
    if record == nil then
      content.icon_found = false
      content.offset = nil
      content.awaiting_item_icon = false
      content.icon_memo = nil
      pair.name.text("")
      return
    end
    --[[ The icon memo: the candidate walk stats the disk, so it re-runs
         only when its answer could change - a different record (the same
         identity rule the sweep uses), a state-swapped builtin icon
         (draw's attack/disengage/dismount), or an extraction still
         pending. A settled repaint stats nothing.

         The override is compared BESIDE the identity, not folded into
         it: the `icon` verb writes the field on the live entry table, so
         the record is the same table before and after and the identity
         alone left the old art on screen. Giving the verb a fresh table
         instead would clear the sweep and the chain result too, which an
         icon change has no business resetting. ]]
    local memo = content.icon_memo
    if
      memo == nil
      or memo.record ~= record
      or memo.icon ~= record.icon
      or memo.builtin ~= opts.builtin
      or memo.awaiting
    then
      content.icon_found = false
      content.offset = nil
      content.awaiting_item_icon = false
      if opts.item_icon ~= nil and meta ~= nil and meta.item_id ~= nil then
        -- Queued by the bar's cache, never extracted here: one icon per
        -- frame, off the hot path. The slot draws its fallback meanwhile.
        content.awaiting_item_icon = opts.item_icon(meta.item_id) == "awaiting"
      end
      local candidate = opts.resolve_icon ~= nil and opts.resolve_icon(record, meta, opts.state) or nil
      if candidate ~= nil then
        content.icon_found = true
        content.offset = candidate.offset
        pair.icon.path(deps.asset(candidate.path))
      end
      content.icon_memo = {
        record = record,
        icon = record.icon,
        builtin = opts.builtin,
        awaiting = content.awaiting_item_icon,
      }
    end
    -- The player's own label, then the game's own casing for what the
    -- record names, then the raw command form - cut to what a slot can
    -- draw. The record keeps its whole name; only this is shortened.
    local label = render().slot_label(record.alias or record.display or record.action or record.type)
    local mark = opts.mark or ""
    content.label = mark ~= "" and (mark .. " " .. label) or label
    pair.name.text(content.label)
  end

  --[[ The bar's refresh step for this slot: whether its group is on screen
       at all, and whether the slot itself is drawn there (an empty slot may
       be hidden by config, and comes back for the binder). Every write goes
       through the gate, so a slot that has not moved costs nothing here -
       which matters because core runs one refresh per mouse move of a
       layout-mode drag. The non-visibility values stay true while a prim
       is hidden, so the tick has nothing to re-push when the group comes
       back either. ]]
  function self.show(shown, slot_shown)
    if not shown then
      content.flash = nil
      -- The chain state goes down with its prim: left standing, the icon
      -- predicate below would read it on the re-show repaint and leave
      -- the slot with neither icon nor chain for a frame.
      content.chain_prop = nil
    end
    slot_shown = shown and slot_shown
    want(pair.background, "background.visible", slot_shown)
    want(pair.frame, "frame.visible", slot_shown)
    -- Chain-aware on purpose: while a chain result covers the slot the
    -- tick keeps the action icon down, and this must agree with it or the
    -- two would fight over the prim between frames.
    want(
      pair.icon,
      "icon.visible",
      shown and content.record ~= nil and content.icon_found and content.chain_prop == nil
    )
    local label = content.label
    want(
      pair.name,
      "name.visible",
      shown and content.record ~= nil and label ~= nil and label ~= "" and not deps.hide("action_name")
    )
    if not shown then
      want(pair.cost, "cost.visible", false)
      want(pair.recast, "recast.visible", false)
      set_sweep(false)
      want(pair.feedback, "feedback.visible", false)
      set_chain(false)
    end
  end

  -- The press flash, at the configured alpha; the tick walks it down.
  function self.flash()
    local feedback = type(config().feedback) == "table" and config().feedback or {}
    content.flash = feedback.alpha or 150
    pair.feedback.alpha(content.flash)
    pair.feedback.show()
    content.written["feedback.alpha"] = content.flash
    content.written["feedback.visible"] = true
  end

  --[[ The per-frame draw. `facts` is what only the bar (or the service it
       reads) can answer:

         player, vitals               the player service's read
         spell_recasts, ability_recasts
         chain_step                   the border animation's step while a
                                      chain window is open, or nil
         counter(record, meta)        the cost-corner count, or nil
         chain_result(record, meta)   the property the action would
                                      continue, or nil
         mount(record)                { blocked, cooldown } for a mount
                                      record, or nil ]]
  function self.tick(facts)
    if content.flash ~= nil then
      content.flash = render().feedback_fade(content.flash)
      if content.flash == nil then
        want(pair.feedback, "feedback.visible", false)
      else
        push("feedback.alpha", content.flash, pair.feedback.alpha)
      end
    end

    local record = content.record
    if record == nil then
      want(pair.cost, "cost.visible", false)
      want(pair.recast, "recast.visible", false)
      set_sweep(false)
      content.chain_prop = nil
      set_chain(false)
      set_frame(false)
      push("frame.alpha", 255, pair.frame.alpha)
      return
    end

    --[[ The chain result: while the window is open, a WS or JA slot whose
         action would continue the resonation swaps to the property's icon
         under the animated frame. A WS short of its 1000 TP draws the pair
         dimmed with the cost still up; a JA is never TP-dimmed (a
         knowingly dropped upstream quirk). ]]
    local meta = content.meta
    local vitals = facts.vitals or {}
    local chain_prop = nil
    if facts.chain_step ~= nil and meta ~= nil then
      chain_prop = facts.chain_result(record, meta)
    end
    content.chain_prop = chain_prop
    local chain_dim = chain_prop ~= nil and record.type == "ws" and vitals.tp ~= nil and vitals.tp < 1000

    local usable = true
    local crossed_out = false

    if chain_prop ~= nil and not chain_dim then
      -- The undimmed result owns the slot; counters and costs sit out for
      -- the window's few seconds, exactly as the reference blanks them.
      want(pair.cost, "cost.visible", false)
    else
      local counter = facts.counter ~= nil and facts.counter(record, meta) or nil
      if counter ~= nil then
        -- Deliberately NOT gated on hide.cost: a count is not a cost. The
        -- option hides prices; how many tools you carry stays visible.
        push("cost.text", counter.text, pair.cost.text)
        local color = counter.color or PLAIN_COUNT_COLOR
        push_color(pair.cost, "cost.color", color[1], color[2], color[3])
        want(pair.cost, "cost.visible", true)
        if counter.zero then
          crossed_out = true
          usable = false
        end
      else
        local cost = render().cost(meta, vitals)
        if cost ~= nil and not deps.hide("cost") then
          push("cost.text", cost.text, pair.cost.text)
          push_color(pair.cost, "cost.color", cost.color.r, cost.color.g, cost.color.b)
          want(pair.cost, "cost.visible", true)
        else
          want(pair.cost, "cost.visible", false)
        end
        if cost ~= nil and not cost.affordable then
          usable = false
        end
      end
    end

    local remaining = render().remaining_for(meta, facts.spell_recasts, facts.ability_recasts)
    --[[ A mount slot answers to neither a spell nor an ability recast, so
         its own two conditions land here - and they part company the moment
         you are actually mounted: the zone stops applying (the press is a
         dismount) while the recast keeps counting and keeps the slot dim.
         The bar's `mount` fact has already folded that in. ]]
    if is_mount_record(record) and facts.mount ~= nil then
      local mount = facts.mount(record)
      if mount ~= nil then
        if mount.blocked then
          usable = false
        end
        if mount.cooldown ~= nil and mount.cooldown > remaining then
          remaining = mount.cooldown
        end
      end
    end
    if remaining > 0 then
      usable = false
    end
    -- No sweep work at all while the animation is configured away - the
    -- maxima simply re-learn (starting full, the algorithm's own posture)
    -- if it is ever turned back on.
    local frame = nil
    if not deps.hide("recast_animation") then
      frame = render().sweep(deps.key, remaining)
    end

    if crossed_out then
      -- The sweep overlay doubles as the red X (upstream's prim reuse), and
      -- the recast text hides under it.
      set_sweep("x")
      want(pair.recast, "recast.visible", false)
    else
      if frame ~= nil then
        set_sweep(frame)
      else
        set_sweep(false)
      end
      if remaining > 0 and not deps.hide("recast_text") then
        push("recast.text", render().recast_label(remaining), pair.recast.text)
        want(pair.recast, "recast.visible", true)
      else
        want(pair.recast, "recast.visible", false)
      end
    end

    if chain_prop ~= nil then
      set_chain(chain_prop)
      push("chain.alpha", chain_dim and SC_DIM_ICON_ALPHA or 255, pair.chain.alpha)
      set_frame(facts.chain_step)
      push("frame.alpha", chain_dim and SC_DIM_FRAME_ALPHA or 255, pair.frame.alpha)
    else
      set_chain(false)
      set_frame(false)
      push("frame.alpha", 255, pair.frame.alpha)
    end
    -- The action icon hides under a chain result and comes back with it;
    -- show() applies the same predicate, so the two never fight.
    want(pair.icon, "icon.visible", chain_prop == nil and content.icon_found)

    -- Dimming covers the ICON only: the cost text keeps its own semantic
    -- colours - the mp/tp/tool bands ARE its signal, and greying them
    -- would fight it.
    push("icon.alpha", render().slot_alpha(usable), pair.icon.alpha)
  end

  -- Forgets everything but the prims: a re-attach or a detach, where the
  -- sweep's observed maximum and the icon memo belong to a bar that is gone.
  function self.reset()
    content = { written = {} }
    render().clear_sweep(deps.key)
  end

  -- What the slot holds, for the bar's own walks (bound ids, drawn-ness,
  -- the binder's marks).
  function self.record()
    return content.record
  end

  function self.meta()
    return content.meta
  end

  function self.label()
    return content.label
  end

  function self.icon_found()
    return content.icon_found == true
  end

  function self.awaiting_item_icon()
    return content.awaiting_item_icon == true
  end

  function self.destroy()
    for _, prim in pairs(pair) do
      prim.destroy()
    end
  end

  return self
end

return new
