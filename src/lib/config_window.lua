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

--[[ `//hud config`: the settings window. A menu of panels down the left -
     `global` and every component that declares one - and the selected
     panel's rows on the right, each a label and a control.

     It is a front end to the COMMANDS and nothing else: a click builds the
     words a player would have typed and hands them to `deps.apply`, which
     runs them through the handler `//hud` itself reaches. So the window
     cannot set what the CLI could not, every refusal and bound is the
     command's own, and the line the command answers is what the window
     says. It never reads or writes a config table: what it shows is the
     panel its owner builds, re-read after every change.

     Drawn with lib/window, the binder's chrome, and built the same way:
     prims exist only while it is open. ]]

local new_window = require("lib/window")

local TITLE = "XIVHud settings"
local MENU_WIDTH = 210
-- Reserved per tab rather than measured, like every width here.
local TAB_WIDTH = 160
-- Where a row's control starts, past its label.
local LABEL_WIDTH = 300
local TOGGLE_WIDTH = 80
-- A stepper: a step down, the value, a step up. The value's width is
-- RESERVED rather than measured - Windower cannot say how wide a string will
-- draw - so the step up stays put while the digits change.
local STEP_WIDTH = 40
local VALUE_WIDTH = 160
local CONTROL_GAP = 6

local function new(deps)
  deps = deps or {}
  local self = {}

  local chrome = new_window({
    new_image = deps.new_image,
    new_text = deps.new_text,
    asset = deps.asset,
    screen = deps.screen,
  })
  local MOVE, LEFT_DOWN, LEFT_UP, WHEEL = chrome.MOVE, chrome.LEFT_DOWN, chrome.LEFT_UP, chrome.WHEEL
  local inside, draw_rows = chrome.inside, chrome.draw_rows
  local metrics = chrome.metrics()
  local GAP, ROW_HEIGHT, BODY_ROWS = metrics.gap, metrics.row_height, metrics.body_rows

  local active = false
  -- Put away by its owner while the HUD is suppressed: still open, nothing
  -- on screen and nothing to click.
  local hidden = false
  local pool, prims = nil, nil
  local position = nil
  local selected = nil
  local tab = 1
  local panel = nil
  local status = ""
  -- The drawn descriptors, rebuilt by redraw() and read by the hit-test, so
  -- what is clickable is exactly what is on screen.
  local view = nil

  local function entries()
    return deps.entries ~= nil and deps.entries() or {}
  end

  local function known(name)
    for _, entry in ipairs(entries()) do
      if entry == name then
        return true
      end
    end
    return false
  end

  --[[ What the window calls is somebody else's code - a component's panel
       here, a component's command in `send` - and it runs inside the mouse
       handler, where five errors make the guard switch that handler off for
       EVERY component. So neither is allowed to throw through it: the error
       goes on the status line instead. ]]
  local function read_panel()
    panel = nil
    if selected == nil or deps.panel == nil then
      return
    end
    local read, answer = pcall(deps.panel, selected)
    if not read then
      status = selected .. ": its settings could not be read - " .. tostring(answer)
      return
    end
    panel = answer
    if panel == nil then
      status = selected .. " has no settings here"
    end
  end

  local function panel_tabs()
    return panel ~= nil and panel.tabs or {}
  end

  local function panel_rows()
    if panel == nil then
      return {}
    end
    if panel.tabs ~= nil then
      local shown = panel.tabs[tab]
      return shown ~= nil and shown.rows or {}
    end
    return panel.rows or {}
  end

  --[[ A number as a player would type it: a step of 0.1 lands on
       1.4000000000000001, and that is neither what the row should show nor
       a word to hand a command. ]]
  local function number_word(value)
    return ("%.14g"):format(value)
  end

  local function option_index(row)
    for index, option in ipairs(row.options or {}) do
      if option == row.value then
        return index
      end
    end
    return nil
  end

  local function value_text(row)
    if row.kind == "toggle" then
      return row.value and "[ on ]" or "[ off ]"
    end
    if row.kind == "choice" then
      -- A stored value the options do not list is shown as it stands: the
      -- files are hand-editable, and the row must say what is in force.
      local index = option_index(row)
      return tostring(index ~= nil and row.labels ~= nil and row.labels[index] or row.value)
    end
    -- A stepper over something that is not a number - a hand-edited file -
    -- is shown as it stands; formatting it would throw in the mouse handler.
    if type(row.value) ~= "number" then
      return tostring(row.value)
    end
    return number_word(row.value)
  end

  --- The option one place along, wrapping, as the word to send - or nil
  --- where that is the option already in force. A value off the list steps
  --- onto its nearer end.
  local function chosen(row, direction)
    local options = row.options or {}
    if #options == 0 then
      return nil
    end
    local index = option_index(row)
    local target = direction > 0 and 1 or #options
    if index ~= nil then
      target = (index - 1 + direction) % #options + 1
    end
    if options[target] == row.value then
      return nil
    end
    return tostring(options[target])
  end

  --- The value one step along, as the word to send, or nil where the row's
  --- bound leaves nowhere to go. A step that would overshoot lands on it.
  local function stepped(row, direction)
    if type(row.value) ~= "number" then
      return nil
    end
    local step, from = row.step or 1, row.value
    -- A whole step lands on a whole number. A fraction a hand-edited file
    -- stored would otherwise be stepped to another fraction, which a
    -- command taking whole numbers refuses - a stepper dead on every click.
    if step % 1 == 0 and from % 1 ~= 0 then
      from = direction > 0 and math.floor(from) or math.ceil(from)
    end
    local value = from + direction * step
    if row.min ~= nil and value < row.min then
      value = row.min
    end
    if row.max ~= nil and value > row.max then
      value = row.max
    end
    -- A value the CLI stored outside the row's bounds: the clamp must not
    -- answer a step down by raising it, or a step up by lowering it.
    if (value - row.value) * direction <= 0 then
      return nil
    end
    local word = number_word(value)
    if word == number_word(row.value) then
      return nil
    end
    return word
  end

  local function layout()
    local frame = chrome.frame(position)
    local body = frame.body
    local built = { frame = frame, status = status, menu = {}, tabs = {}, rows = {} }

    local menu = chrome.paged(entries(), { x = body.x, y = body.y, width = MENU_WIDTH }, BODY_ROWS, 1)
    for index, cell in ipairs(menu) do
      cell.name, cell.selected = cell.item, cell.item == selected
      built.menu[index] = cell
    end

    local column = { x = body.x + MENU_WIDTH + GAP, y = body.y, width = body.width - MENU_WIDTH - GAP }
    local capacity = BODY_ROWS
    for index, shown in ipairs(panel_tabs()) do
      if index * TAB_WIDTH <= column.width then
        built.tabs[index] = {
          name = shown.name,
          index = index,
          selected = index == tab,
          x = column.x + (index - 1) * TAB_WIDTH,
          y = column.y,
          width = TAB_WIDTH,
          height = ROW_HEIGHT,
        }
      end
    end
    -- The tabs take the column's first row; a flat panel starts at the top.
    if #built.tabs > 0 then
      column.y, capacity = column.y + ROW_HEIGHT, capacity - 1
    end
    local rows = chrome.paged(panel_rows(), column, capacity, 1)
    for index, cell in ipairs(rows) do
      local row = cell.item
      cell.label, cell.kind, cell.text = row.label, row.kind, value_text(row)
      local control_x = cell.x + LABEL_WIDTH
      if row.kind == "toggle" then
        cell.toggle = { x = control_x, y = cell.y, width = TOGGLE_WIDTH, height = cell.height }
        cell.value_x = control_x
      else
        -- A choice walks a list and a stepper a number, so they wear
        -- different signs over the same three rects.
        cell.signs = row.kind == "choice" and { "[<]", "[>]" } or { "[-]", "[+]" }
        cell.dec = { x = control_x, y = cell.y, width = STEP_WIDTH, height = cell.height }
        cell.value_x = control_x + STEP_WIDTH + CONTROL_GAP
        cell.inc = {
          x = cell.value_x + VALUE_WIDTH + CONTROL_GAP,
          y = cell.y,
          width = STEP_WIDTH,
          height = cell.height,
        }
      end
      built.rows[index] = cell
    end
    return built
  end

  local function redraw()
    view = layout()
    if prims == nil then
      return
    end
    if hidden then
      chrome.hide_frame(prims)
      for _, list in ipairs({ prims.menu, prims.tabs, prims.labels, prims.values, prims.decs, prims.incs }) do
        draw_rows(list, {})
      end
      return
    end
    chrome.draw_frame(prims, view.frame, TITLE, view.status)
    local menu, tabs, labels, values = {}, {}, {}, {}
    for index, cell in ipairs(view.menu) do
      menu[index] = { text = (cell.selected and "> " or "  ") .. cell.name, x = cell.x, y = cell.y }
    end
    for index, cell in ipairs(view.tabs) do
      tabs[index] = {
        text = cell.selected and ("[ " .. cell.name .. " ]") or ("  " .. cell.name),
        x = cell.x,
        y = cell.y,
      }
    end
    for index, cell in ipairs(view.rows) do
      labels[index] = { text = cell.label, x = cell.x, y = cell.y }
      values[index] = { text = cell.text, x = cell.value_x, y = cell.y }
    end
    draw_rows(prims.menu, menu)
    draw_rows(prims.tabs, tabs)
    draw_rows(prims.labels, labels)
    draw_rows(prims.values, values)
    -- Indexed by ROW, not packed: a toggle's row leaves its pair hidden.
    for index, prim in ipairs(prims.decs) do
      local cell = view.rows[index]
      local stepped_row = cell ~= nil and cell.dec ~= nil
      draw_rows({ prim }, { stepped_row and { text = cell.signs[1], x = cell.dec.x, y = cell.y } or nil })
      draw_rows({ prims.incs[index] }, { stepped_row and { text = cell.signs[2], x = cell.inc.x, y = cell.y } or nil })
    end
  end

  local function build_prims()
    pool = chrome.pool()
    if pool == nil then
      return
    end
    prims = {
      window_bg = pool.backdrop(),
      close = pool.text(),
      title = pool.text(),
      subhead = pool.text(),
      menu = pool.texts(BODY_ROWS),
      tabs = pool.texts(self.capacity().tabs),
      labels = pool.texts(BODY_ROWS),
      values = pool.texts(BODY_ROWS),
      decs = pool.texts(BODY_ROWS),
      incs = pool.texts(BODY_ROWS),
    }
  end

  local function choose(name)
    selected, tab = name, 1
    status = ""
    read_panel()
  end

  --[[ The words a player would have typed for this change: the row's own
       command, the new value, and whatever the row says follows it. ]]
  local function send(row, value_word)
    local words = {}
    for _, word in ipairs(row.command or {}) do
      words[#words + 1] = word
    end
    words[#words + 1] = value_word
    for _, word in ipairs(row.suffix or {}) do
      words[#words + 1] = word
    end
    local reply = nil
    if deps.apply ~= nil then
      local ran, answer = pcall(deps.apply, selected, words, row.route)
      reply = answer
      if not ran then
        reply = "that did not work - " .. tostring(answer)
      end
    end
    if type(reply) == "table" then
      reply = reply[1]
    end
    status = type(reply) == "string" and reply or ""
    read_panel()
  end

  local function hit(x, y)
    if view == nil or not inside(x, y, view.frame) then
      return nil
    end
    local control = chrome.control_at(view.frame, x, y)
    if control ~= nil then
      return control
    end
    for _, cell in ipairs(view.menu) do
      if inside(x, y, cell) then
        return { kind = "menu", name = cell.name, rect = cell }
      end
    end
    for _, cell in ipairs(view.tabs) do
      if inside(x, y, cell) then
        return { kind = "tab", index = cell.index, rect = cell }
      end
    end
    for _, cell in ipairs(view.rows) do
      if inside(x, y, cell.toggle) then
        return { kind = "toggle", row = cell.item, rect = cell.toggle }
      end
      if inside(x, y, cell.dec) then
        return { kind = "step", row = cell.item, direction = -1, rect = cell.dec }
      end
      if inside(x, y, cell.inc) then
        return { kind = "step", row = cell.item, direction = 1, rect = cell.inc }
      end
    end
    --[[ Anywhere else inside the window is the window itself: inert, but
         NAMED rather than fallen through, so the click is swallowed instead
         of reaching whatever the game has under it. ]]
    return { kind = "panel", rect = view.frame }
  end

  local function on_click(target)
    if target.kind == "close" then
      self.close()
      return
    elseif target.kind == "menu" then
      choose(target.name)
    elseif target.kind == "tab" then
      tab = target.index
    elseif target.kind == "toggle" then
      send(target.row, target.row.value and "off" or "on")
    elseif target.kind == "step" then
      local along = target.row.kind == "choice" and chosen or stepped
      local word = along(target.row, target.direction)
      if word == nil then
        return
      end
      send(target.row, word)
    end
    redraw()
  end

  function self.active()
    return active
  end

  --- The window as it is drawn - frame, menu, rows and status line - or nil
  --- while it is closed.
  function self.view()
    return view
  end

  --- What one page holds, so a spec can check a panel against the numbers
  --- the layout uses rather than a copy that could drift from them. Rows
  --- past these are simply not drawn: there is no paging.
  function self.capacity()
    local column_width = chrome.frame().body.width - MENU_WIDTH - GAP
    return { rows = BODY_ROWS, tabbed_rows = BODY_ROWS - 1, tabs = math.floor(column_width / TAB_WIDTH) }
  end

  --- Open on `name`, or where it was last left; an entry the menu does not
  --- carry falls back to the first.
  function self.open(name)
    if active then
      return
    end
    active = true
    chrome.cancel()
    position = chrome.position(deps.window_pos ~= nil and deps.window_pos() or nil)
    if name ~= nil and known(name) then
      selected, tab = name, 1
    elseif selected == nil or not known(selected) or name ~= nil then
      selected, tab = entries()[1], 1
    end
    status = ""
    read_panel()
    build_prims()
    redraw()
  end

  function self.close()
    if not active then
      return
    end
    active, hidden = false, false
    chrome.cancel()
    view, panel = nil, nil
    if pool ~= nil then
      pool.destroy()
    end
    pool, prims = nil, nil
    if deps.on_close ~= nil then
      deps.on_close()
    end
  end

  function self.select(name)
    if not active or not known(name) then
      return
    end
    choose(name)
    redraw()
  end

  --- Re-read the panel and redraw: a typed command, a reset or a slot
  --- switch can all move what the window is showing.
  function self.refresh()
    if not active then
      return
    end
    read_panel()
    redraw()
  end

  --- Put the window away, or bring it back, without closing it: the HUD is
  --- suppressed, and nothing of it may stay on screen or take a click.
  function self.set_hidden(on)
    on = on and true or false
    -- Its owner states this on every visibility pass, changed or not.
    if on == hidden then
      return
    end
    hidden = on
    chrome.cancel()
    if active then
      redraw()
    end
  end

  function self.mouse(kind, x, y)
    if not active or hidden then
      return false
    end
    if kind == MOVE then
      local phase, moved_x, moved_y = chrome.motion(x, y)
      if moved_x ~= nil then
        -- The title strip is being dragged. Geometry only: the panel is
        -- not re-read for a move.
        position = { x = moved_x, y = moved_y }
        redraw()
        return true
      end
      -- Motion is the game's until a real drag is live: blocking it for a
      -- press that is still a click would freeze the camera on every
      -- button-down.
      return phase ~= nil and phase ~= "click"
    end
    if kind == LEFT_DOWN then
      -- A click outside is the game's and changes nothing here: the window
      -- is the whole mode, so it does not close on a stray click.
      chrome.cancel()
      local target = hit(x, y)
      if target == nil then
        return false
      end
      chrome.press(target, x, y, view.frame)
      return true
    end
    if kind == LEFT_UP then
      local armed = chrome.release()
      if armed == nil then
        return false
      end
      if armed.position ~= nil then
        -- Saved on the drop, not on every pixel: this writes a config file.
        if deps.save_window_pos ~= nil then
          deps.save_window_pos(armed.position.x, armed.position.y)
        end
      elseif not armed.drag then
        -- A press that slid off its control is a change of mind.
        on_click(armed.target)
      end
      return true
    end
    if kind == WHEEL then
      -- The game zooming its camera under a window the player is reading
      -- is not wanted.
      return inside(x, y, view.frame)
    end
    return false
  end

  return self
end

return new
