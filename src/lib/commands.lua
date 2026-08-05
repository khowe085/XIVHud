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

--[[ Pure `//xh` parser: argument list in, action table out.

     Nothing here executes anything — the entry point maps actions onto the
     framework. Verbs and component names match case-insensitively; everything
     after a component name is passed through untouched, and character names
     keep their case. Unknown input always produces an `error` action with a
     one-line hint: Windower fails silently often enough on its own. ]]

local HELP_HINT = "see //xh help"

local RESERVED = {
  help = true,
  layout = true,
  setup = true,
  list = true,
  show = true,
  hide = true,
  reset = true,
  slot = true,
  copy = true,
}

local SLOT_OPS = { list = true, create = true, delete = true }

local function fail(message)
  return { action = "error", message = message .. " (" .. HELP_HINT .. ")" }
end

-- Windower hands over whatever the user typed; drop the empty strings a stray
-- double space produces so `//xh  ` still reads as a bare command.
local function clean(args)
  local words = {}
  for _, word in ipairs(args or {}) do
    if type(word) == "string" and word ~= "" then
      words[#words + 1] = word
    end
  end
  return words
end

local function new(deps)
  local self = { reserved = RESERVED }

  local function resolve_component(name)
    local wanted = name:lower()
    for _, registered in ipairs(deps.components() or {}) do
      if registered:lower() == wanted then
        return registered:lower()
      end
    end
    return nil
  end

  -- `verb` may be more than one word ("slot list"); anything past it is an error.
  local function no_extra(words, verb)
    local verb_words = 0
    for _ in verb:gmatch("%S+") do
      verb_words = verb_words + 1
    end
    if #words > verb_words then
      return fail("'//xh " .. verb .. "' takes no arguments")
    end
    return nil
  end

  local function parse_target(words, verb, allow_all)
    local target = words[2]
    if not target then
      return fail("'//xh " .. verb .. "' needs a component name")
    end
    if #words > 2 then
      return fail("'//xh " .. verb .. "' takes a single component name")
    end
    if allow_all and target:lower() == "all" then
      return { action = verb, component = "all" }
    end
    local component = resolve_component(target)
    if not component then
      return fail("no component named '" .. target .. "'")
    end
    return { action = verb, component = component }
  end

  local function parse_slot(words)
    local first = words[2]
    if not first then
      return fail("'//xh slot' needs a slot name, or list/create/delete")
    end

    local op = first:lower()
    if op == "list" then
      return no_extra(words, "slot list") or { action = "slot", op = "list" }
    end
    if SLOT_OPS[op] then
      local name = words[3]
      if not name or #words > 3 or not name:match("^[%w_]+$") then
        return fail("'//xh slot " .. op .. "' needs a one-word slot name")
      end
      -- Otherwise `//xh slot create list` makes a slot no command can reach.
      if SLOT_OPS[name:lower()] then
        return fail("'" .. name .. "' cannot be used as a slot name")
      end
      return { action = "slot", op = op, name = name:lower() }
    end

    if #words > 2 or not first:match("^[%w_]+$") then
      return fail("'//xh slot' needs a one-word slot name, or list/create/delete")
    end
    return { action = "slot", op = "switch", name = op }
  end

  -- `//xh copy <source> <destination>`. Both ends are named explicitly, so the
  -- command reads the same whichever character is logged in, and neither end is
  -- implied. Character names keep the case they were typed with.
  local function parse_copy(words)
    local source = words[2]
    if not source then
      return fail("'//xh copy' needs a source character")
    end

    local destination = words[3]
    if not destination then
      return fail("'//xh copy " .. source .. " <destination>' needs a destination character")
    end
    if #words > 3 then
      return fail("'//xh copy' takes a source and a destination character, nothing more")
    end

    return { action = "copy", source = source, destination = destination }
  end

  -- Parses one `//xh ...` invocation into an action table. Never returns nil.
  function self.parse(args)
    local words = clean(args)
    local verb = words[1] and words[1]:lower() or "help"

    if verb == "help" then
      return no_extra(words, "help") or { action = "help" }
    elseif verb == "layout" or verb == "setup" then
      return no_extra(words, verb) or { action = "layout" }
    elseif verb == "list" then
      return no_extra(words, "list") or { action = "list" }
    elseif verb == "show" or verb == "hide" then
      return parse_target(words, verb, false)
    elseif verb == "reset" then
      return parse_target(words, "reset", true)
    elseif verb == "slot" then
      return parse_slot(words)
    elseif verb == "copy" then
      return parse_copy(words)
    end

    local component = resolve_component(verb)
    if component then
      local passthrough = {}
      for index = 2, #words do
        passthrough[index - 1] = words[index]
      end
      return { action = "component", component = component, args = passthrough }
    end

    return fail("unknown command '" .. words[1] .. "'")
  end

  return self
end

return new
