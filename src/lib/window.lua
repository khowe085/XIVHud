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

--[[ The chrome of a centred, draggable window: the frame and its controls,
     the prims they are drawn with, paging, and the press that becomes a
     click or a drag.

     Extracted from the action bars' binder (2026-10-01) so that the
     settings window (lib/config_window) is drawn with the same chrome and
     the two cannot drift. It holds nothing that is either one's alone: what
     a window shows, where it is and whether it is open are its client's. ]]

-- Windower's mouse types, as layout_mode names them.
local MOVE, LEFT_DOWN, LEFT_UP, WHEEL = 0, 1, 2, 10

local FONT_SIZE = 18
local ROW_HEIGHT = 26
local PAD = 10
local GAP = 12
local WIDTH = 920
local HEIGHT = 600
local BACK_WIDTH = 90
local CLOSE_WIDTH = 50
-- The title line and the line under it.
local HEADER_ROWS = 2
-- Derived from the window rather than fixed, so changing its height moves
-- every client's lists with it instead of leaving them short or overflowing.
local BODY_ROWS = math.floor((HEIGHT - PAD * 2 - HEADER_ROWS * ROW_HEIGHT) / ROW_HEIGHT)
-- xivcrossbar's black square (imported; notice in assets/own/LICENSE.txt),
-- tinted and dimmed behind the window.
local PANEL_TEXTURE = "assets/own/black-square.png"
local PANEL_ALPHA = 220

local function inside(x, y, rect)
  return rect ~= nil
    and type(x) == "number"
    and type(y) == "number"
    and x >= rect.x
    and x < rect.x + rect.width
    and y >= rect.y
    and y < rect.y + rect.height
end

local function draw_rows(list, lines)
  for index, prim in ipairs(list) do
    local line = lines[index]
    if line == nil then
      prim.hide()
    else
      prim.text(line.text)
      prim.pos(line.x, line.y)
      prim.show()
    end
  end
end

local function new(deps)
  deps = deps or {}
  local self = {}

  self.MOVE, self.LEFT_DOWN, self.LEFT_UP, self.WHEEL = MOVE, LEFT_DOWN, LEFT_UP, WHEEL
  self.inside = inside
  self.draw_rows = draw_rows

  local function screen()
    if deps.screen == nil then
      return 1920, 1080
    end
    local width, height = deps.screen()
    return width or 1920, height or 1080
  end

  --[[ Fully on screen, always. A position saved at one resolution and
       opened at another would otherwise leave the window unreachable, and
       there is no keyboard to recentre it with. A window larger than the
       screen pins to the top left rather than inverting the range. ]]
  local function clamp(x, y)
    local screen_width, screen_height = screen()
    return math.max(0, math.min(x, screen_width - WIDTH)), math.max(0, math.min(y, screen_height - HEIGHT))
  end

  --- A stored or dragged position made safe to open at: nil unless it is a
  --- pair of numbers - these come out of hand-editable files - and clamped.
  function self.position(candidate)
    if type(candidate) ~= "table" or type(candidate.x) ~= "number" or type(candidate.y) ~= "number" then
      return nil
    end
    local x, y = clamp(candidate.x, candidate.y)
    return { x = x, y = y }
  end

  function self.metrics()
    return { font_size = FONT_SIZE, row_height = ROW_HEIGHT, gap = GAP, body_rows = BODY_ROWS }
  end

  --[[ The window and its regions, dead centre unless it is told where.
       `position` is clamped where it is SET - on a drag and on the read at
       open - so there is one clamp per way in rather than a second one here
       that would make both untestable. ]]
  function self.frame(position)
    local screen_width, screen_height = screen()
    local x = position ~= nil and position.x or math.max(0, math.floor(screen_width / 2 - WIDTH / 2))
    local y = position ~= nil and position.y or math.max(0, math.floor(screen_height / 2 - HEIGHT / 2))
    local frame = { x = x, y = y, width = WIDTH, height = HEIGHT }
    --[[ The drag handle is the whole top strip, because a handle you have
         to aim at is worse than no handle. Close sits INSIDE it and back
         beside it, and `control_at` asks for both first, so a slip onto
         either is still that control. ]]
    local header_x, title_x = x, x + PAD
    if deps.back then
      frame.back = { x = x + PAD, y = y + PAD, width = BACK_WIDTH, height = ROW_HEIGHT }
      header_x = frame.back.x + BACK_WIDTH
      title_x = header_x + GAP
    end
    -- Inset from the right edge exactly as back is from the left, so the two
    -- controls read as a pair however wide the window is.
    frame.close = { x = x + WIDTH - PAD - CLOSE_WIDTH, y = y + PAD, width = CLOSE_WIDTH, height = ROW_HEIGHT }
    frame.title = { x = title_x, y = y + PAD }
    frame.header = { x = header_x, y = y, width = x + WIDTH - header_x, height = PAD + ROW_HEIGHT }
    frame.subhead = { x = x + PAD, y = y + PAD + ROW_HEIGHT }
    frame.body = {
      x = x + PAD,
      y = y + PAD + HEADER_ROWS * ROW_HEIGHT,
      width = WIDTH - PAD * 2,
      height = BODY_ROWS * ROW_HEIGHT,
    }
    return frame
  end

  --[[ One page of a list, laid into a column. Shared by every list a window
       pages, so the clamp and the row rects cannot drift apart between two
       that look the same. Answers the page it actually built: one past the
       end comes back as the last. ]]
  function self.paged(items, column, rows_per_page, page)
    local pages = math.max(1, math.ceil(#items / rows_per_page))
    if page > pages then
      page = pages
    end
    local first = (page - 1) * rows_per_page
    local built = {}
    for index = 1, rows_per_page do
      local item = items[first + index]
      if item == nil then
        break
      end
      built[index] = {
        item = item,
        index = first + index,
        x = column.x,
        y = column.y + (index - 1) * ROW_HEIGHT,
        width = column.width,
        height = ROW_HEIGHT,
      }
    end
    return built, pages, page
  end

  --[[ The two ways out, then the drag handle: checked before anything a
       client lays into the window, so no row can ever be put over them. A
       frame whose `back` the client has taken off answers nothing in that
       corner - an undrawn control that still answered would swallow clicks
       for good. ]]
  function self.control_at(frame, x, y)
    if frame == nil then
      return nil
    end
    if inside(x, y, frame.close) then
      return { kind = "close", rect = frame.close }
    end
    if frame.back ~= nil and inside(x, y, frame.back) then
      return { kind = "back", rect = frame.back }
    end
    if inside(x, y, frame.header) then
      return { kind = "header", rect = frame.header }
    end
    return nil
  end

  --- `prims` is the client's own table: `window_bg`, `close`, `title`,
  --- `subhead`, and `back` where the window has one.
  function self.draw_frame(prims, frame, title, subhead)
    prims.window_bg.color(0, 0, 0)
    prims.window_bg.alpha(PANEL_ALPHA)
    prims.window_bg.pos(frame.x, frame.y)
    prims.window_bg.size(frame.width, frame.height)
    prims.window_bg.show()
    if prims.back ~= nil then
      if frame.back ~= nil then
        prims.back.text("[ < back ]")
        prims.back.pos(frame.back.x, frame.back.y)
        prims.back.show()
      else
        prims.back.hide()
      end
    end
    prims.close.text("[ X ]")
    prims.close.pos(frame.close.x, frame.close.y)
    prims.close.show()
    prims.title.text(title)
    prims.title.pos(frame.title.x, frame.title.y)
    prims.title.show()
    prims.subhead.text(subhead)
    prims.subhead.pos(frame.subhead.x, frame.subhead.y)
    prims.subhead.show()
  end

  function self.hide_frame(prims)
    prims.window_bg.hide()
    if prims.back ~= nil then
      prims.back.hide()
    end
    prims.close.hide()
    prims.title.hide()
    prims.subhead.hide()
  end

  --[[ The press ------------------------------------------------------------
       A press becomes a DRAG only after the cursor leaves the thing it
       started on; below that it is a click. The title strip keeps the same
       threshold - without it a one-pixel slip while clicking the strip
       wrote the config file.

       One press at a time, and the record is the client's to hang its own
       fields on: this reads `target`, `rect`, `drag`, `offset` and
       `position` and nothing else. ]]
  local press = nil

  --- Arm a press on `target`, replacing whatever the last one left behind.
  --- `frame` is the window as it stands on screen: a press on its title
  --- strip remembers where in the window it grabbed.
  function self.press(target, x, y, frame)
    press = { target = target, rect = target.rect, drag = false }
    if target.kind == "header" and frame ~= nil then
      press.offset = { x = x - frame.x, y = y - frame.y }
    end
  end

  function self.pressed()
    return press
  end

  --[[ What a move makes of the press: nil with none armed, "click" while
       the cursor is still on what it started on, "start" on the move that
       leaves it and "drag" on every one after. A drag of the title strip
       also answers where the window now belongs - the grab point stays
       under the cursor, so the window does not jump to have its corner
       there. ]]
  function self.motion(x, y)
    if press == nil then
      return nil
    end
    local phase = "drag"
    if not press.drag then
      if inside(x, y, press.rect) then
        return "click"
      end
      press.drag = true
      phase = "start"
    end
    if press.offset ~= nil then
      local moved_x, moved_y = clamp(x - press.offset.x, y - press.offset.y)
      press.position = { x = moved_x, y = moved_y }
      return phase, moved_x, moved_y
    end
    return phase
  end

  --- The press, handed over and forgotten. `position` is on it only where
  --- the title strip was really dragged, which is what there is to save.
  function self.release()
    local armed = press
    press = nil
    return armed
  end

  function self.cancel()
    press = nil
  end

  --[[ The prims of one open window: built when it opens and destroyed when
       it closes, so a shut window costs nothing. Nil without the three deps
       a prim is made from - a client that cannot draw still lays out. ]]
  function self.pool()
    if deps.new_image == nil or deps.new_text == nil or deps.asset == nil then
      return nil
    end
    local pool, made = {}, {}
    local family = deps.font ~= nil and deps.font() or nil

    function pool.image(texture)
      local prim = deps.new_image()
      made[#made + 1] = prim
      prim.draggable(false)
      prim.repeat_xy(1, 1)
      prim.fit(false)
      if texture ~= nil then
        prim.path(deps.asset(texture))
      end
      prim.color(255, 255, 255)
      prim.hide()
      return prim
    end

    function pool.text()
      local prim = deps.new_text()
      made[#made + 1] = prim
      prim.font(family or "sans-serif")
      -- The FAMILY is the client's, the SIZE is the window's: a bar's 10pt
      -- is unreadable at this scale.
      prim.size(FONT_SIZE)
      prim.color(255, 255, 255)
      prim.stroke_width(1)
      prim.stroke_color(0, 0, 0)
      -- stroke_alpha, not stroke_transparency: the library reads a 0..1
      -- transparency and would turn a 0-255 alpha wildly negative.
      prim.stroke_alpha(255)
      -- The texts library draws its own opaque box behind a line unless
      -- told not to; every other widget here turns it off (parambar,
      -- partylist, targetbar, equipviewer, lib/overlay).
      prim.bg_visible(false)
      prim.right_justified(false)
      prim.text("")
      prim.hide()
      return prim
    end

    function pool.backdrop()
      return pool.image(PANEL_TEXTURE)
    end

    function pool.texts(count)
      local list = {}
      for index = 1, count do
        list[index] = pool.text()
      end
      return list
    end

    function pool.images(count)
      local list = {}
      for index = 1, count do
        list[index] = pool.image()
      end
      return list
    end

    function pool.destroy()
      for _, prim in ipairs(made) do
        prim.destroy()
      end
      made = {}
    end

    return pool
  end

  return self
end

return new
