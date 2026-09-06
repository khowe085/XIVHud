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

--[[ A bar's geometry as the binding store and the CLI see it: how many
     slots a set has, which sides it has, and how one slot is ADDRESSED in
     a command. The crossbar is two sides of eight (`1L1`), the hotbar one
     row of ten (`3:7`); both are eight sets. Everything geometry-shaped in
     lib/actionbar reads one of these rather than a literal of its own, so
     the two bars cannot drift, and a third shape would be one more entry
     here.

     `split(word)` takes an address as typed and answers its four parts -
     the layer prefix (lower-cased, "" for the job base, "ctx:<name>" for a
     context), the set's digits as typed, the side's canonical name and the
     slot's digits - or nil for anything that is not an address in this
     grammar. Bounds are the caller's to check: this only knows the shape.
     `label` is the other direction, for listings and replies. ]]

local M = {}

local SET_COUNT = 8

--- `<set><L|R><slot>` - `1L1`, `2R8`. A lower-case `l` beside digits is
--- indistinguishable from a `1` in the game's font, so the side is shown
--- upper case; either case parses.
function M.crossbar()
  local sides = { l = "left", r = "right", L = "left", R = "right", left = "left", right = "right" }
  return {
    set_count = SET_COUNT,
    slot_count = 8,
    sides = sides,
    side_order = { "left", "right" },
    form = "<set><L|R><slot> - 1L1, 2R8, sub:1L6, wpn:1L6, ctx:<name>:1L3",
    split = function(word)
      if type(word) ~= "string" then
        return nil
      end
      -- The prefix ends at the LAST colon: a context address carries two
      -- (`ctx:<name>:1L3`) and a context name may contain none.
      local prefix, tail = word:match("^(.*):([^:]*)$")
      if prefix == nil then
        prefix, tail = "", word
      end
      local digits, side_word, slot = tail:match("^(%d+)([lLrR])(%d+)$")
      if digits == nil then
        return nil
      end
      return prefix:lower(), digits, sides[side_word], slot
    end,
    label = function(set_arg, side, slot)
      return tostring(set_arg) .. (side == "left" and "L" or "R") .. tostring(slot)
    end,
  }
end

--- `<set>:<slot>` - `3:7`, `3:10`. Digits with a colon cannot be misread the
--- way `1l1` could, and `3-7` reads as a range. The layer prefixes go in
--- front exactly as on the crossbar, so the prefix is whatever precedes the
--- last two colon-separated numbers.
function M.hotbar()
  return {
    set_count = SET_COUNT,
    slot_count = 10,
    sides = { row = "row" },
    side_order = { "row" },
    form = "<set>:<slot> - 3:7, 3:10, sub:3:7, wpn:3:7, ctx:<name>:3:7",
    split = function(word)
      if type(word) ~= "string" then
        return nil
      end
      -- Bare, or a prefix that ends in its own colon: `wpn3:7` is not an
      -- address, however tempting the digits look.
      local digits, slot = word:match("^(%d+):(%d+)$")
      if digits ~= nil then
        return "", digits, "row", slot
      end
      local prefix
      prefix, digits, slot = word:match("^(.-):(%d+):(%d+)$")
      if digits == nil or prefix == "" then
        return nil
      end
      return prefix:lower(), digits, "row", slot
    end,
    label = function(set_arg, _, slot)
      return tostring(set_arg) .. ":" .. tostring(slot)
    end,
  }
end

return M
