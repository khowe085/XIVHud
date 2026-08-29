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

--[[ `//hud layout` — the FFXIV HUD-Layout equivalent, as a pure state machine.

     A widget is a *group* of prims, so the texts library's own per-object drag
     is useless here: it would move one prim and leave the rest behind. Instead
     every prim is created non-draggable and layout mode registers a single
     global mouse handler, hit-testing widget bounding boxes itself. That keeps
     all of the drag logic in this module, fed nothing but (type, x, y, delta)
     tuples — which is exactly what the specs push through it.

     Interactions, all of which persist immediately (a crash must not lose the
     user's layout):

       left-drag    move the whole widget; snapped to the grid unless CTRL is
                    held (XIVParty snaps *while* CTRL is held; we invert that,
                    so the useful behaviour is the default)
       wheel        scale the widget under the cursor, floored at 0.25
       right-click  toggle the widget on or off; disabled widgets stay visible
                    and draggable in layout mode so they can be re-enabled

     A widget exposing `anchors() -> {names}` (touchpoint 2) is hit-tested per
     anchor: dragging and wheel-scaling address the one anchor under the
     cursor, whose state is fetched as deps.state(component, anchor). Only the
     right-click toggle stays whole-widget - `visible` is per component.

     A drag captures the mouse: once a grab is live every mouse event belongs to
     the mode, so a stray right-click or wheel cannot reach the game mid-drag. ]]

local MOVE, LEFT_DOWN, LEFT_UP = 0, 1, 2
local RIGHT_DOWN, RIGHT_UP, WHEEL = 4, 5, 10
local CONTROL_KEYS = { [29] = true, [157] = true }
local WHEEL_SCALE_STEP = 100

local function new(deps)
  local self = {}
  local layout = deps.layout
  local active = false
  local drag = nil
  local control_held = false
  local swallow_right_up = false

  local function apply_all()
    for _, component in ipairs(deps.components()) do
      deps.apply(component)
    end
  end

  local function inside(x, y, bx, by, width, height)
    return bx ~= nil and x >= bx and x < bx + width and y >= by and y < by + height
  end

  -- Topmost wins: later registrations draw over earlier ones, so search back to
  -- front - and within a multi-anchor widget, later anchors over earlier ones.
  -- Bounds are half-open, so abutting widgets cannot both claim a pixel.
  local function hit_test(x, y)
    local components = deps.components()
    for index = #components, 1, -1 do
      local component = components[index]
      -- A non-table anchors() answer reads as no anchors, matching core.
      local names = component.anchors and component.anchors()
      if type(names) == "table" then
        for position = #names, 1, -1 do
          local anchor = names[position]
          if inside(x, y, component.get_bounds(anchor)) then
            return component, anchor
          end
        end
      elseif inside(x, y, component.get_bounds()) then
        return component
      end
    end
    return nil
  end

  local function move_to(x, y)
    local state = deps.state(drag.component, drag.anchor)
    -- The grab was live when it started; a state that has since gone (the
    -- policy everywhere here: nil kills the interaction) ends the move, not
    -- the mouse capture.
    if not state then
      return
    end
    local _, _, width, height = drag.component.get_bounds(drag.anchor)
    state.pos.x, state.pos.y = layout.resolve(x - drag.offset_x, y - drag.offset_y, width, height, control_held)
    deps.apply(drag.component)
  end

  local function end_drag()
    if not drag then
      return
    end
    local component = drag.component
    drag = nil
    deps.persist(component)
  end

  function self.active()
    return active
  end

  function self.dragging()
    return drag and drag.component or nil
  end

  function self.enter()
    if active then
      return true
    end
    active = true
    drag = nil
    swallow_right_up = false
    -- CTRL tracking only runs while the keyboard handler is registered, and
    -- that is guaranteed only while some component consumes keys; with none,
    -- the handler comes and goes with the mode and a release outside it is
    -- never seen. Entering from a known-released state is the safe reading
    -- either way: a CTRL still physically down re-asserts itself on its next
    -- auto-repeat.
    control_held = false
    apply_all()
    return true
  end

  function self.exit()
    if not active then
      return false
    end
    -- Releasing the mouse outside the mode is not something we can observe, so
    -- an in-flight drag is committed rather than rolled back.
    end_drag()
    active = false
    swallow_right_up = false
    apply_all()
    return false
  end

  function self.toggle()
    if active then
      return self.exit()
    end
    return self.enter()
  end

  -- Returns true when the event was consumed; the entry point turns that into
  -- the `return true` that stops Windower passing the input to the game.
  function self.mouse(mouse_type, x, y, delta)
    if not active then
      return false
    end

    if drag then
      if mouse_type == MOVE then
        move_to(x, y)
      elseif mouse_type == LEFT_UP then
        move_to(x, y)
        end_drag()
      end
      return true
    end

    -- deps.state(component, anchor) is the pos/scale-bearing state the hit
    -- addresses: one anchor's entry, or the whole slot state when anchor is
    -- nil. Its nil kills the interaction - an anchor with bounds but no state
    -- entry is a component authoring bug, not worth crashing the mouse over.
    if mouse_type == LEFT_DOWN then
      local component, anchor = hit_test(x, y)
      local state = component and deps.state(component, anchor)
      if not state then
        return false
      end
      drag = { component = component, anchor = anchor, offset_x = x - state.pos.x, offset_y = y - state.pos.y }
      return true
    elseif mouse_type == WHEEL then
      local component, anchor = hit_test(x, y)
      local state = component and deps.state(component, anchor)
      if not state then
        return false
      end
      state.scale = layout.clamp_scale(state.scale + (delta or 0) / WHEEL_SCALE_STEP)
      deps.apply(component)
      deps.persist(component)
      return true
    elseif mouse_type == RIGHT_DOWN then
      local component = hit_test(x, y)
      local state = component and deps.state(component)
      if not state then
        return false
      end
      state.visible = not state.visible
      swallow_right_up = true
      deps.apply(component)
      deps.persist(component)
      return true
    elseif mouse_type == RIGHT_UP then
      if not swallow_right_up then
        return false
      end
      swallow_right_up = false
      return true
    end

    return false
  end

  -- CTRL frees a drag from the grid. Read live on every move, so pressing or
  -- releasing it part way through a drag takes effect immediately.
  function self.key(dik, down)
    if CONTROL_KEYS[dik] then
      control_held = down and true or false
    end
  end

  function self.free()
    return control_held
  end

  return self
end

return new
