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

--[[ Pure Lua-literal serializer for the config service (see lib/settings.lua).

     Config files are plain `return {...}` chunks. Key order is stable (array
     part first, then keys sorted) so that a rewritten config produces a clean
     diff instead of a reshuffled file. Only data is representable: anything
     else raises, so a bad write fails loudly at the caller rather than
     emitting a file that will not load back. ]]

local KEYWORDS = {
  ["and"] = true,
  ["break"] = true,
  ["do"] = true,
  ["else"] = true,
  ["elseif"] = true,
  ["end"] = true,
  ["false"] = true,
  ["for"] = true,
  ["function"] = true,
  ["if"] = true,
  ["in"] = true,
  ["local"] = true,
  ["nil"] = true,
  ["not"] = true,
  ["or"] = true,
  ["repeat"] = true,
  ["return"] = true,
  ["then"] = true,
  ["true"] = true,
  ["until"] = true,
  ["while"] = true,
}

local ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function quote(str)
  local escaped = str:gsub('[\\"\n\r\t]', ESCAPES):gsub("%c", function(c)
    return string.format("\\%03d", c:byte())
  end)
  return '"' .. escaped .. '"'
end

local function number_literal(n)
  if n ~= n or n == math.huge or n == -math.huge then
    error("cannot serialize non-finite number", 0)
  end
  -- %.14g keeps whole numbers integral ("1", not "1.0") while staying round-trippable.
  return string.format("%.14g", n)
end

local function is_identifier(str)
  return str:match("^[%a_][%w_]*$") ~= nil and not KEYWORDS[str]
end

-- Array part = the contiguous 1..n integer keys; everything else is a keyed entry.
local function split_keys(tbl)
  local count = 0
  while tbl[count + 1] ~= nil do
    count = count + 1
  end

  local keyed = {}
  for key in pairs(tbl) do
    local is_array_index = type(key) == "number" and key % 1 == 0 and key >= 1 and key <= count
    if not is_array_index then
      local kind = type(key)
      if kind ~= "string" and kind ~= "number" then
        error("cannot serialize table key of type " .. kind, 0)
      end
      keyed[#keyed + 1] = key
    end
  end

  table.sort(keyed, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) == "number"
  end)

  return count, keyed
end

local function key_literal(key)
  if type(key) == "string" and is_identifier(key) then
    return key
  elseif type(key) == "string" then
    return "[" .. quote(key) .. "]"
  end
  return "[" .. number_literal(key) .. "]"
end

local write_value

local function write_table(tbl, out, indent, seen)
  if seen[tbl] then
    error("cannot serialize cyclic table", 0)
  end
  seen[tbl] = true

  local array_count, keyed = split_keys(tbl)
  if array_count == 0 and #keyed == 0 then
    out[#out + 1] = "{}"
    seen[tbl] = nil
    return
  end

  local inner = indent .. "  "
  out[#out + 1] = "{\n"
  for i = 1, array_count do
    out[#out + 1] = inner
    write_value(tbl[i], out, inner, seen)
    out[#out + 1] = ",\n"
  end
  for _, key in ipairs(keyed) do
    out[#out + 1] = inner .. key_literal(key) .. " = "
    write_value(tbl[key], out, inner, seen)
    out[#out + 1] = ",\n"
  end
  out[#out + 1] = indent .. "}"

  seen[tbl] = nil
end

function write_value(value, out, indent, seen)
  local kind = type(value)
  if kind == "table" then
    write_table(value, out, indent, seen)
  elseif kind == "string" then
    out[#out + 1] = quote(value)
  elseif kind == "number" then
    out[#out + 1] = number_literal(value)
  elseif kind == "boolean" then
    out[#out + 1] = tostring(value)
  else
    error("cannot serialize value of type " .. kind, 0)
  end
end

-- Serializes a data table to a loadable `return {...}` chunk. Raises on
-- functions, userdata, cycles and non-finite numbers.
return function(tbl)
  if type(tbl) ~= "table" then
    error("serialize expects a table, got " .. type(tbl), 0)
  end
  local out = { "return " }
  write_value(tbl, out, "", {})
  out[#out + 1] = "\n"
  return table.concat(out)
end
