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

--[[ The buff order and filter engine, shared by every component that draws a
     set of buff icons: the shipped priority with a user's overrides merged in,
     a filter list in either mode, the sort and the cap - and the `buff`
     command verbs that edit all of that, so two components' `//hud <x> buff`
     grammars cannot drift.

     Promoted out of partylist's logic (2026-09-04) when the status bar needed
     the same machinery; a component may require lib/, never a sibling.

     Factory style: `new(deps)` with
       deps.name        how a message names the caller ("partylist"), which is
                        also how the user addresses it
       deps.resources   the resources table, for res.buffs names
       deps.shipped     the ranked id list; lib/buff_order unless given
       deps.extra_verbs verbs the caller answers itself, named in the hint
       deps.hint_verbs  the whole list the hint names instead, for a caller
                        that refuses some of the verbs
       deps.filter_path where the caller puts the filter verbs, for the
                        messages ("partylist buff filter" unless given)
       deps.buff_path   where the caller puts the buff verbs, for the advice
                        in a refusal ("partylist buff" unless given)

     The `settings` every call takes is the caller's own table - `priority`
     (sparse `id -> wanted rank` overrides on the shipped order, so a later
     change to that order carries through instead of being stomped by a copy
     the user made months ago), `filters` (a list of ids) and `filter_mode`
     (`blacklist` or `whitelist`). The verbs write into it in place - the
     lists included, which are emptied rather than replaced, so a caller may
     hand in a view composed of another table's fields - and the caller saves
     it. `normalize` repairs a hand-edited one first. ]]

local shipped_order = require("lib/buff_order")

local EMPTY_SLOT = 255
local PAGE_SIZE = 20
local MAX_SEARCH_HITS = 20

-- In place, so a table the caller composed from another's fields stays theirs.
local function empty(t)
  for key in pairs(t) do
    t[key] = nil
  end
end

-- Deliberately stricter than tonumber, which also accepts "0x84" and "1e2".
local function whole_number(word)
  if type(word) ~= "string" or not word:match("^%-?%d+$") then
    return nil
  end
  return tonumber(word)
end

local function new(deps)
  deps = deps or {}
  local NAME = deps.name or "hud"
  local FILTER_PATH = deps.filter_path or (NAME .. " buff filter")
  local BUFF_PATH = deps.buff_path or (NAME .. " buff")
  local resources = deps.resources or {}
  local shipped = deps.shipped or shipped_order

  local self = {}

  -- One throwaway per engine rather than one per call, so a broken config
  -- still hits the order cache below instead of rebuilding it every frame.
  local throwaway = { priority = {}, filters = {}, filter_mode = "blacklist" }

  -- Memoized on the overrides table itself: a config re-read hands the caller
  -- a fresh table, which recomputes without anyone remembering to say so. An
  -- in-place edit does need `invalidate`, and the verbs below do it.
  local cached_for, cached_ranks, cached_order = nil, nil, nil

  function self.invalidate()
    cached_for, cached_ranks, cached_order = nil, nil, nil
  end

  function self.name(id)
    local entry = (resources.buffs or {})[id]
    return entry and entry.en or ("buff " .. tostring(id))
  end

  --[[ Config files are hand-editable Lua, so the settings can be any shape at
       all -- the defaults merge only fills a key that is *missing*. A broken
       table is repaired in place, so what the caller saves is the fix; one
       that is not a table at all gets a throwaway, deliberately not written
       back: whatever the user put there is theirs to fix, and `//hud reset` is
       how. ]]
  function self.normalize(settings)
    if type(settings) ~= "table" then
      return throwaway
    end
    if type(settings.priority) ~= "table" then
      settings.priority = {}
    end
    if type(settings.filters) ~= "table" then
      settings.filters = {}
    end
    if settings.filter_mode ~= "whitelist" then
      settings.filter_mode = "blacklist"
    end
    return settings
  end

  --[[ The effective order: the shipped list with the user's overrides lifted
       out and re-inserted at the rank each was given.

       Returns `id -> rank` and the ordered list; an id in neither has no rank
       and sorts last. ]]
  function self.order(overrides)
    overrides = type(overrides) == "table" and overrides or {}
    if cached_for == overrides then
      return cached_ranks, cached_order
    end

    local moved = {}
    for id, rank in pairs(overrides) do
      if type(id) == "number" and type(rank) == "number" then
        moved[#moved + 1] = { id = id, rank = rank }
      end
    end
    -- Descending on the id, because each insert at a given rank displaces the
    -- previous occupant down one: inserting the higher id first leaves the
    -- lower one holding the contested rank.
    table.sort(moved, function(a, b)
      if a.rank ~= b.rank then
        return a.rank < b.rank
      end
      return a.id > b.id
    end)

    local is_moved = {}
    for _, entry in ipairs(moved) do
      is_moved[entry.id] = true
    end

    local order = {}
    for _, id in ipairs(shipped) do
      if not is_moved[id] then
        order[#order + 1] = id
      end
    end
    for _, entry in ipairs(moved) do
      table.insert(order, math.max(1, math.min(entry.rank, #order + 1)), entry.id)
    end

    local ranks = {}
    for rank, id in ipairs(order) do
      ranks[id] = rank
    end
    cached_for, cached_ranks, cached_order = overrides, ranks, order
    return ranks, order
  end

  -- In place, by rank then id. Unranked ids tie on rank, so the id breaks the
  -- tie and the icon order stays put between frames instead of flickering.
  function self.sort(ids, ranks)
    table.sort(ids, function(a, b)
      local rank_a, rank_b = ranks[a] or math.huge, ranks[b] or math.huge
      if rank_a ~= rank_b then
        return rank_a < rank_b
      end
      return a < b
    end)
    return ids
  end

  --[[ The ids to draw: filtered, sorted by priority and cut to `opts.cap`.
       `opts.keep(id)` is the caller's own restriction (a category), applied
       before the user's list so a blacklist can still trim what it admits. ]]
  function self.plan(ids, settings, opts)
    settings = self.normalize(settings)
    opts = opts or {}
    local blocked = {}
    for _, id in ipairs(settings.filters) do
      blocked[id] = true
    end
    local whitelist = settings.filter_mode == "whitelist"

    local kept = {}
    for _, id in ipairs(ids or {}) do
      if id ~= EMPTY_SLOT and (not opts.keep or opts.keep(id)) and (blocked[id] == true) == whitelist then
        kept[#kept + 1] = id
      end
    end

    self.sort(kept, (self.order(settings.priority)))
    if opts.cap then
      while #kept > opts.cap do
        table.remove(kept)
      end
    end
    return kept
  end

  -- `<id|name>`: digits are an id, anything else is matched case-insensitively
  -- against res.buffs. Several buffs share a name -- sleep is both 2 and 19 --
  -- so an ambiguous name asks which rather than guessing.
  function self.resolve(text)
    if text == nil or text == "" then
      return nil, { ("//hud %s needs a buff id or name"):format(BUFF_PATH) }
    end

    local id = whole_number(text)
    if id and id >= 0 then
      return id
    end

    local wanted = text:lower()
    local hits = {}
    for buff_id, entry in pairs(resources.buffs or {}) do
      if type(entry) == "table" and type(entry.en) == "string" and entry.en:lower() == wanted then
        hits[#hits + 1] = buff_id
      end
    end
    if #hits == 1 then
      return hits[1]
    end
    if #hits == 0 then
      return nil, { ("no buff called '%s' - try '//hud %s find %s'"):format(text, BUFF_PATH, text) }
    end

    table.sort(hits)
    local ids = {}
    for index, buff_id in ipairs(hits) do
      ids[index] = tostring(buff_id)
    end
    return nil,
      {
        ("'%s' is the name of %d buffs - say which id:"):format(text, #hits),
        "  " .. table.concat(ids, ", "),
      }
  end

  --[[ The command verbs. Each takes the caller's settings and answers the
       lines to print plus whether anything changed, so the caller knows when
       to re-lay out and save. `cap` is how many icons the caller draws, which
       the listings mark; without one nothing is marked and the bare verb
       shows the first page of the order instead of the drawn slots. ]]

  -- Everything a listing can show: the ranked order first, then every buff the
  -- resources know that nothing has ranked. Nothing is silently left out.
  local function full_listing(settings)
    local ranks, order = self.order(settings.priority)
    local listing = {}
    for index, id in ipairs(order) do
      listing[index] = id
    end

    local unranked = {}
    for id in pairs(resources.buffs or {}) do
      if not ranks[id] then
        unranked[#unranked + 1] = id
      end
    end
    table.sort(unranked)

    local first_unranked = #listing + 1
    for _, id in ipairs(unranked) do
      listing[#listing + 1] = id
    end
    return listing, first_unranked
  end

  local function list_page(settings, word, cap)
    local listing, first_unranked = full_listing(settings)
    local pages = math.max(1, math.ceil(#listing / PAGE_SIZE))
    local page = math.max(1, math.min(whole_number(word) or 1, pages))
    local first = (page - 1) * PAGE_SIZE + 1
    local last = math.min(first + PAGE_SIZE - 1, #listing)

    local lines = { ("%s buff order - page %d/%d"):format(NAME, page, pages) }
    for rank = first, last do
      if rank == first_unranked then
        lines[#lines + 1] = "  --- unranked below; these sort after everything above ---"
      end
      lines[#lines + 1] = ("  %3d. %s (%d)"):format(rank, self.name(listing[rank]), listing[rank])
      if rank == cap then
        lines[#lines + 1] = ("  --- cut: only the %d above are ever drawn ---"):format(cap)
      end
    end
    lines[#lines + 1] = ("  '//hud %s buff list <page>' for another page"):format(NAME)
    return lines, false
  end

  local function shown_slots(settings, cap)
    if not cap then
      return list_page(settings, nil, nil)
    end
    local _, order = self.order(settings.priority)
    local lines = { ("%s draws the first %d of these:"):format(NAME, cap) }
    for rank = 1, math.min(cap, #order) do
      lines[#lines + 1] = ("  %2d. %s (%d)"):format(rank, self.name(order[rank]), order[rank])
    end
    return lines, false
  end

  local function find_buffs(settings, text, cap)
    if text == "" then
      return { ("//hud %s buff find needs something to search for"):format(NAME) }, false
    end

    local ranks = self.order(settings.priority)
    local wanted = text:lower()
    local hits = {}
    for id, entry in pairs(resources.buffs or {}) do
      if type(entry) == "table" and type(entry.en) == "string" and entry.en:lower():find(wanted, 1, true) then
        hits[#hits + 1] = { id = id, rank = ranks[id] }
      end
    end
    if #hits == 0 then
      return { ("no buff has '%s' in its name"):format(text) }, false
    end

    table.sort(hits, function(a, b)
      if (a.rank or math.huge) ~= (b.rank or math.huge) then
        return (a.rank or math.huge) < (b.rank or math.huge)
      end
      return a.id < b.id
    end)

    local lines = { ("buffs matching '%s':"):format(text) }
    for index = 1, math.min(#hits, MAX_SEARCH_HITS) do
      local hit = hits[index]
      lines[#lines + 1] = ("  rank %s  id %d  %s%s"):format(
        hit.rank and tostring(hit.rank) or "-",
        hit.id,
        self.name(hit.id),
        (cap and hit.rank and hit.rank <= cap) and "  (drawn)" or ""
      )
    end
    if #hits > MAX_SEARCH_HITS then
      lines[#lines + 1] = ("  %d more - refine the search"):format(#hits - MAX_SEARCH_HITS)
    end
    return lines, false
  end

  --[[ A rank past the end of the order is clamped, so storing and reporting
       the number the user typed would be two different lies.

       Any other override already at or below the wanted rank moves down one.
       Without that, two overrides claim the same rank and the id tie-break
       decides -- so `buff top` on one buff and then another would report a
       promotion that silently did not happen. ]]
  local function set_rank(settings, id, rank)
    local _, order = self.order(settings.priority)
    local landed = math.max(1, math.min(rank, #order))
    local overrides = settings.priority

    for other, other_rank in pairs(overrides) do
      if other ~= id and type(other_rank) == "number" and other_rank >= landed then
        overrides[other] = other_rank + 1
      end
    end
    overrides[id] = landed

    self.invalidate()
    return { ("%s moved to rank %d"):format(self.name(id), landed) }, true
  end

  local function move_buff(settings, verb, words)
    local id, complaint = self.resolve(words)
    if not id then
      return complaint, false
    end

    if verb == "top" then
      return set_rank(settings, id, 1)
    end

    local ranks, order = self.order(settings.priority)
    -- An unranked buff sits notionally past the end, so "up" pulls it in.
    local rank = ranks[id] or (#order + 1)
    if verb == "up" then
      if rank <= 1 then
        return { ("%s is already at the top"):format(self.name(id)) }, false
      end
      return set_rank(settings, id, rank - 1)
    end
    if rank >= #order then
      return { ("%s is already at the bottom"):format(self.name(id)) }, false
    end
    return set_rank(settings, id, rank + 1)
  end

  local function rank_buff(settings, words)
    local rank = whole_number(words[#words])
    if not rank or rank < 1 then
      return { ("//hud %s buff rank needs a buff and a rank of at least 1"):format(NAME) }, false
    end
    local id, complaint = self.resolve(table.concat(words, " ", 2, #words - 1))
    if not id then
      return complaint, false
    end
    return set_rank(settings, id, rank)
  end

  local function filter_command(settings, words)
    local action = words[2] and words[2]:lower() or "list"

    if action == "list" then
      if #settings.filters == 0 then
        return { ("%s filters nothing (%s mode)"):format(NAME, settings.filter_mode) }, false
      end
      local lines = { ("%s %s (%d):"):format(NAME, settings.filter_mode, #settings.filters) }
      for _, id in ipairs(settings.filters) do
        lines[#lines + 1] = ("  id %d  %s"):format(id, self.name(id))
      end
      return lines, false
    end

    if action == "clear" then
      empty(settings.filters)
      return { FILTER_PATH .. " cleared" }, true
    end

    if action == "mode" then
      local mode = words[3] and words[3]:lower()
      if mode ~= "blacklist" and mode ~= "whitelist" then
        return { ("//hud %s mode needs blacklist or whitelist"):format(FILTER_PATH) }, false
      end
      settings.filter_mode = mode
      return { ("%s is now a %s"):format(FILTER_PATH, mode) }, true
    end

    if action == "add" or action == "remove" then
      local text = table.concat(words, " ", 3)
      if text == "" then
        return { ("//hud %s %s needs a buff id or name"):format(FILTER_PATH, action) }, false
      end
      local id, complaint = self.resolve(text)
      if not id then
        return complaint, false
      end
      for index, filtered in ipairs(settings.filters) do
        if filtered == id then
          if action == "add" then
            return { ("%s is already filtered"):format(self.name(id)) }, false
          end
          table.remove(settings.filters, index)
          return { ("%s is no longer filtered"):format(self.name(id)) }, true
        end
      end
      if action == "remove" then
        return { ("%s is not filtered"):format(self.name(id)) }, false
      end
      settings.filters[#settings.filters + 1] = id
      return { ("%s is now filtered"):format(self.name(id)) }, true
    end

    return { ("//hud %s takes add, remove, clear, list or mode"):format(FILTER_PATH) }, false
  end

  local function verbs_hint()
    local list = deps.hint_verbs
    if not list or #list == 0 then
      list = { "list", "find" }
      for _, verb in ipairs(deps.extra_verbs or {}) do
        list[#list + 1] = verb
      end
      for _, verb in ipairs({ "top", "up", "down", "rank", "reset", "filter" }) do
        list[#list + 1] = verb
      end
    end
    if #list == 1 then
      return list[1]
    end
    return table.concat(list, ", ", 1, #list - 1) .. " or " .. list[#list]
  end

  -- `words` is everything after the caller's `buff` word. The caller has
  -- already checked its settings are a table (`normalize` would hand a
  -- throwaway to an edit, and the change would vanish on save).
  function self.command(settings, words, cap)
    settings = self.normalize(settings)
    words = words or {}
    local verb = words[1] and words[1]:lower() or nil
    if not verb then
      return shown_slots(settings, cap)
    end
    if verb == "list" then
      return list_page(settings, words[2], cap)
    end
    if verb == "find" then
      return find_buffs(settings, table.concat(words, " ", 2), cap)
    end
    if verb == "top" or verb == "up" or verb == "down" then
      return move_buff(settings, verb, table.concat(words, " ", 2))
    end
    if verb == "rank" then
      return rank_buff(settings, words)
    end
    if verb == "reset" then
      empty(settings.priority)
      self.invalidate()
      return { NAME .. " buff order reset to the shipped one" }, true
    end
    if verb == "filter" then
      return filter_command(settings, words)
    end
    return { ("//hud %s buff takes %s"):format(NAME, verbs_hint()) }, false
  end

  return self
end

return new
