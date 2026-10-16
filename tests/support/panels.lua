--[[ What every `config_panel()` has to be for the settings window to draw it
     and run it, checked the same way for every component.

     `problems` reads a panel's shape against the window's own capacity.
     `exercise` goes further: it stands the REAL window over the widget and
     clicks every control once, so a row whose command its component's
     parser refuses - or accepts and then ignores - is caught where a shape
     check would wave it through. ]]

local new_config_window = require("lib/config_window")

local M = {}

local LEFT_DOWN, LEFT_UP = 1, 2
local KINDS = { toggle = true, choice = true, stepper = true }

local function is_word_list(value, allow_empty)
  if type(value) ~= "table" or (#value == 0 and not allow_empty) then
    return false
  end
  for _, word in ipairs(value) do
    if type(word) ~= "string" or word == "" then
      return false
    end
  end
  return true
end

local function row_problems(row, where, found)
  local function problem(text)
    found[#found + 1] = where .. ": " .. text
  end
  if type(row.label) ~= "string" or row.label == "" then
    problem("no label")
  end
  if not KINDS[row.kind] then
    problem("unknown kind " .. tostring(row.kind))
  end
  if not is_word_list(row.command) then
    problem("command is not a list of words")
  end
  if row.suffix ~= nil and not is_word_list(row.suffix, true) then
    problem("suffix is not a list of words")
  end
  if row.route ~= nil and row.route ~= "buffs" then
    problem("unknown route " .. tostring(row.route))
  end
  if row.kind == "toggle" then
    if type(row.value) ~= "boolean" then
      problem("a toggle's value must be true or false, not " .. tostring(row.value))
    end
  elseif row.kind == "choice" then
    if type(row.options) ~= "table" or #row.options == 0 then
      problem("a choice needs options")
      return
    end
    local listed = false
    for _, option in ipairs(row.options) do
      listed = listed or option == row.value
    end
    if not listed then
      problem("value " .. tostring(row.value) .. " is not one of its options")
    end
    if row.labels ~= nil and (type(row.labels) ~= "table" or #row.labels ~= #row.options) then
      problem("labels do not match options one for one")
    end
  elseif row.kind == "stepper" then
    if type(row.value) ~= "number" then
      problem("a stepper's value must be a number, not " .. tostring(row.value))
      return
    end
    if row.step ~= nil and (type(row.step) ~= "number" or row.step <= 0) then
      problem("step must be a number above zero")
    end
    if row.min ~= nil and row.value < row.min then
      problem("value " .. row.value .. " is under its min " .. row.min)
    end
    if row.max ~= nil and row.value > row.max then
      problem("value " .. row.value .. " is over its max " .. row.max)
    end
  end
end

local function page_problems(rows, where, limit, found)
  if type(rows) ~= "table" then
    found[#found + 1] = where .. ": rows is not a list"
    return
  end
  if #rows > limit then
    found[#found + 1] = where .. ": " .. #rows .. " rows, and the window draws " .. limit
  end
  local seen = {}
  for index, row in ipairs(rows) do
    local name = where .. " row " .. index .. " (" .. tostring(type(row) == "table" and row.label or row) .. ")"
    if type(row) ~= "table" then
      found[#found + 1] = name .. ": not a table"
    else
      row_problems(row, name, found)
      if seen[row.label] then
        found[#found + 1] = name .. ": the label is used twice on one page"
      end
      seen[row.label] = true
    end
  end
end

--- Every way `panel` is not one the settings window can draw and run, as a
--- list of lines; empty for a sound panel.
function M.problems(panel)
  local found = {}
  local capacity = new_config_window({}).capacity()
  if type(panel) ~= "table" then
    return { "the panel is not a table" }
  end
  if panel.tabs ~= nil then
    if panel.rows ~= nil then
      found[#found + 1] = "a panel has tabs or rows, not both"
    end
    if type(panel.tabs) ~= "table" or #panel.tabs == 0 then
      return { "tabs is not a list of tabs" }
    end
    if #panel.tabs > capacity.tabs then
      found[#found + 1] = #panel.tabs .. " tabs, and the window draws " .. capacity.tabs
    end
    local seen = {}
    for index, tab in ipairs(panel.tabs) do
      local name = type(tab) == "table" and tab.name or nil
      if type(name) ~= "string" or name == "" then
        found[#found + 1] = "tab " .. index .. " has no name"
      elseif seen[name] then
        found[#found + 1] = "tab name " .. name .. " is used twice"
      else
        seen[name] = true
      end
      page_problems(type(tab) == "table" and tab.rows or nil, "tab " .. tostring(name), capacity.tabbed_rows, found)
    end
  else
    page_problems(panel.rows, "panel", capacity.rows, found)
  end
  return found
end

local function centre(rect)
  return rect.x + rect.width / 2, rect.y + rect.height / 2
end

local function click(window, rect)
  local x, y = centre(rect)
  window.mouse(LEFT_DOWN, x, y, 0)
  window.mouse(LEFT_UP, x, y, 0)
end

--[[ Stand the real window over `widget` - which must be attached, as it is
     when a player opens the window - and click every control once: each row
     is moved (stepped up, or down where it is already at its top; a toggle
     flipped), read back, then put back the way it was.

     Answers one record per row: `tab`, `label`, `before`, `after`,
     `restored` (the three as the window shows them), and `words` and
     `reply` for the command that made the change. ]]
function M.exercise(widget)
  local sent = {}
  local window = new_config_window({
    screen = function()
      return 1920, 1080
    end,
    entries = function()
      return { widget.name }
    end,
    panel = function()
      return widget.config_panel()
    end,
    apply = function(_, words, route)
      -- Kept apart, as core keeps them: a row routed to buff verbs its
      -- widget does not have must fail here, not pass by the other door.
      local handler = widget.handle_command
      if route == "buffs" then
        handler = widget.handle_buffs
      end
      local reply = handler ~= nil and handler(words) or nil
      sent[#sent + 1] = { words = words, reply = reply }
      return reply
    end,
  })
  window.open(widget.name)

  local records = {}
  local tabs = window.view().tabs
  for tab_index = 1, math.max(1, #tabs) do
    local tab = window.view().tabs[tab_index]
    if tab ~= nil then
      click(window, tab)
    end
    for row_index = 1, #window.view().rows do
      local function cell()
        return window.view().rows[row_index]
      end
      local before = cell().text
      local record = { tab = tab and tab.name or nil, label = cell().label, before = before }
      local forward, backward = cell().toggle or cell().inc, cell().toggle or cell().dec
      local first = #sent + 1
      click(window, forward)
      if cell().text == before then
        -- Already at its top: the way to move it is down, and back is up.
        forward, backward = backward, forward
        click(window, forward)
      end
      record.after = cell().text
      record.words = sent[first] and sent[first].words or nil
      record.reply = sent[first] and sent[first].reply or nil
      click(window, backward)
      record.restored = cell().text
      records[#records + 1] = record
    end
  end
  window.close()
  return records
end

--- The rows an exercise could not move, or could not put back, as a list of
--- lines; empty where every control works.
function M.failures(records)
  local found = {}
  for _, record in ipairs(records) do
    local where = (record.tab and (record.tab .. " / ") or "") .. tostring(record.label)
    local reply = type(record.reply) == "table" and record.reply[1] or record.reply
    if record.after == record.before then
      found[#found + 1] = ("%s: the control changed nothing (sent '%s', answered '%s')"):format(
        where,
        table.concat(record.words or {}, " "),
        tostring(reply)
      )
    elseif record.restored ~= record.before then
      found[#found + 1] = ("%s: was %s, and stepping back left %s"):format(where, record.before, record.restored)
    end
  end
  return found
end

return M
