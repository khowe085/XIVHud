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

--[[ The authoring CLI: the `//hud crossbar` verbs that write bindings and
     per-set config. Pure -- the binding model, the live config table and a
     file-existence probe arrive as deps, and nothing here draws or saves a
     file itself.

       command(args) -> reply, save_config, repaint

     `reply` is a string or a list of strings (core says each line); the two
     flags tell the widget to persist the component config and to re-render.
     A binding write persists itself through the model's own store, so it
     asks only for the repaint.

     The verbs the live widget answers itself -- `set`, bare `cycle`, bare
     `open`, `edit` and the built-in actions -- are not here: they execute
     rather than author, and the widget owns execution. ]]

local roster = require("components/crossbar/contexts")

-- The component's own asset root, for the shipped half of an icon name.
local ASSETS = "components/crossbar/assets/"
local SET_COUNT = 8
local SLOT_COUNT = 8

-- Slots 1-4 are the face cross, 5-8 the D-pad, both clockwise from the top
-- (the component's own slot map). Nobody should have to memorise the indices.
--[[ An address is ONE word: `<set><L|R><slot>` - `1L1`, `2R8` - and may
     carry a layer prefix, `sub:1L1` or `ctx:light-arts:1L1`.

     It was three words (`1 l 1`) until 2026-08-22. The side was the
     problem: a lower-case `l` beside digits is indistinguishable from a
     `1` in the game's font, so the side is written upper case and the
     three words are one, which cannot be miscounted either. Both cases
     parse - it is a hint about how to READ an address, not a demand about
     how to type one.

     The slots' controller names went at the same time (`y b a x up right
     down left`). There is no controller - Windower cannot see one - so
     naming its buttons in a hint only invited the question of which pad
     was meant. Slots are 1-8. ]]
local ADDRESS_FORM = "<set><L|R><slot> - 1L1, 2R8, sub:1L6, ctx:<name>:1L3"

-- The four configurable views, CLI spelling -> config key. Matched
-- case-insensitively; the upper-case spelling is the one shown, for the
-- same reason the address carries one.
local VIEW_KEYS = {
  ["wxhb-l"] = "wxhb_left",
  ["wxhb-r"] = "wxhb_right",
  ["exp-lr"] = "expanded_lr",
  ["exp-rl"] = "expanded_rl",
}
local VIEW_ORDER = { "wxhb-L", "wxhb-R", "exp-LR", "exp-RL" }
-- The same four in the shape the widget's status line wants, derived so the
-- two can never drift. The keys are lower case and the spellings upper, so
-- the lookup folds exactly as the verb's own does.
local VIEW_LIST = {}
for _, cli in ipairs(VIEW_ORDER) do
  VIEW_LIST[#VIEW_LIST + 1] = { cli = cli, key = VIEW_KEYS[cli:lower()] }
end

local HELP = {
  "crossbar commands:",
  "  //hud crossbar [set <1-8> | cycle | list [<set>] | wxhb [on|off]]",
  "  //hud crossbar bind <address> <type> [<action>] [<target>]",
  "  //hud crossbar unbind <address>",
  "  //hud crossbar alias|icon <address> [<name>] - omit to clear",
  "  //hud crossbar swap <address> <address>",
  "  //hud crossbar view <wxhb-L|wxhb-R|exp-LR|exp-RL> <set><L|R>",
  "  //hud crossbar share <set> on|off",
  -- Its own line: `cycle <set> <mode>` edits which rotations a set belongs
  -- to, which has nothing to do with sharing. Sharing a line read as one
  -- command with an `|` in the middle (Kevin, 2026-08-24). The bare `cycle`
  -- that advances the rotation is the one on the first line.
  "  //hud crossbar cycle <set> drawn|sheathed|both|none",
  "  //hud crossbar retry [on|off] - re-send an action the game refused as too soon",
  "  //hud crossbar copy <JOB> | context list | open [<name>]",
  "  //hud crossbar draw | mr | warp [all] | edit",
  "  an address is <set><L|R><slot> - 1L1, 2R8 - and takes sub: or ctx:<name>: in front",
}

-- Types that carry no action name. `ra` still takes a target (`/ra <t>`);
-- the other three take nothing at all.
local NO_ACTION_TYPES = { ra = true, draw = true, mr = true, warp = true }
-- Types whose action IS the rest of the line: a chat line or a console
-- command may end in anything, so no target word is split off it.
local WHOLE_LINE_TYPES = { ct = true, ex = true }

--[[ FFXI's target tokens. The grammar is `<type> [<action>] [<target>]` over
     words Windower already split on spaces, and an action name may be
     several words ("Ascetic's Fury"), so the last word is a target only when
     it is one of these -- or is bracketed, which says so outright. A name
     may also be double-quoted, which settles it without the list. ]]
local TARGET_TOKENS = {
  t = true,
  me = true,
  bt = true,
  ft = true,
  st = true,
  stpc = true,
  stnpc = true,
  stal = true,
  lastst = true,
  scan = true,
  r = true,
  pet = true,
}

--[[ The two readings that actually work, named the same way everywhere a
     trailing word is refused. Deliberately terminal: it does NOT teach
     `<Name>` for a player (a bracketed player name is UNVERIFIED in client
     and awaits the in-client check), and it never sends anyone to a form the parser
     also refuses - quoting only the shorter name leaves the trailing word
     bare, which lands right back here. A user who types `<Name>` anyway is
     still obeyed; we simply do not recommend it.

     The token list is the parser's own: a16-a19 are not alliance targets,
     so a hint promising a10-a25 would promise more than bind accepts. ]]
local TARGET_ADVICE = "a player name as a target is not supported yet - quote the whole name to keep it, "
  .. "or use a target token (t, me, bt, ft, pet, p0-p5, a10-a15, a20-a25, st, stpc, stnpc)"

local function not_a_target(word)
  return "not a target: " .. word .. " - " .. TARGET_ADVICE
end

local function is_target_token(word)
  if TARGET_TOKENS[word] then
    return true
  end
  return word:match("^p[0-5]$") ~= nil or word:match("^a[12][0-5]$") ~= nil
end

-- A name the user wrapped in quotes: the wiki teaches quoting for names with
-- spaces, and a user who quotes one without them must not get the quotes
-- stored as the label.
local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function unquote(text)
  return text:match('^"(.*)"$') or text
end

--- A quoted name, or nil + a complaint when the quote never closes: a
--- dropped closing quote stores the quote as part of the name and binds
--- something that can never fire.
local function unquote_checked(text)
  if text:sub(1, 1) == '"' and (#text < 2 or text:sub(-1) ~= '"') then
    return nil, "unterminated quote in " .. text
  end
  -- Trimmed: the quotes are the user's way of saying where the name ends,
  -- and an action whose name carries the whitespace they typed inside them
  -- can never fire.
  return trim(unquote(text))
end

--- A decimal integer, or nil. tonumber takes "0x3", "3.0" and "1e0" as
--- numbers; a set or slot typed that way is a typo, and one silently
--- rounded into a neighbouring set is a binding the user cannot find again.
local function whole_number(word)
  if type(word) ~= "string" or word:match("^%d+$") == nil then
    return nil
  end
  return tonumber(word)
end

--- A target argument -- nil when the word is not one. Brackets are the user
--- saying "this word is the target", so a bracketed word is taken as typed
--- (its case with it, since only the game's own tokens are case-insensitive
--- spellings of one thing). A bare word must BE one of those tokens: where
--- it cannot be part of the action name, an unrecognised one is a typo, and
--- binding it would build a command that silently never fires.
local function target_of(word)
  local bracketed = word:match("^<(.+)>$")
  if bracketed ~= nil then
    return is_target_token(bracketed:lower()) and bracketed:lower() or bracketed
  end
  local bare = unquote(word)
  if is_target_token(bare:lower()) then
    return bare:lower()
  end
  return nil
end

local function slice(words, from, to)
  local out = {}
  for index = from, to or #words do
    out[#out + 1] = words[index]
  end
  return out
end

local function join(words, from, to)
  return table.concat(slice(words, from or 1, to), " ")
end

--- The optional trailing target: answers the action name and the target, or
--- nil + a complaint. A double-quoted name wins outright; otherwise the last
--- of two or more words is the target only when it reads as one -- an
--- unrecognised word stays part of the name, which is what makes a player
--- name usable as a target only when bracketed or quoted past.
local function split_action_target(rest)
  if #rest == 0 then
    return nil, nil
  end
  if rest[1]:sub(1, 1) == '"' then
    for index = 1, #rest do
      local word = rest[index]
      -- The opening quote cannot double as the closing one, so a one-word
      -- span needs two characters before it can close.
      if word:sub(-1) == '"' and (index > 1 or #word > 1) then
        if #rest > index + 1 then
          return nil, nil, "one action name and at most one target - drop what follows " .. rest[index + 1]
        end
        local name = trim(join(rest, 1, index):sub(2, -2))
        if name == "" then
          return nil, nil, "an empty action name"
        end
        local target = rest[index + 1]
        if target == nil then
          return name, nil
        end
        -- The quote closed, so this word cannot belong to the name.
        local resolved = target_of(target)
        if resolved == nil then
          return nil, nil, not_a_target(target)
        end
        return name, resolved
      end
    end
    -- Unterminated. Storing it would keep the quote in the action name and
    -- bind something that can never fire, reported as a success.
    return nil, nil, "unterminated quote in " .. join(rest)
  end
  local last = rest[#rest]
  if #rest >= 2 and target_of(last) ~= nil then
    return join(rest, 1, #rest - 1), target_of(last)
  end
  -- No target: the name took every word, the last of which might have been
  -- meant as one. The fourth answer is that word, for bind to check.
  return join(rest), nil, nil, #rest >= 2 and last or nil
end

local function new(deps)
  local self = {}

  local function hint(message)
    return "crossbar: " .. message
  end

  -- A plain set number, no layer prefix: the config verbs address sets as a
  -- whole, where a layer means nothing.
  local function parse_set_only(word)
    local set = whole_number(word)
    if set == nil or set < 1 or set > SET_COUNT then
      return nil, hint("no such set: " .. tostring(word) .. " (1-" .. SET_COUNT .. ")")
    end
    return set
  end

  --- A set for a verb that addresses it as a WHOLE, where a layer prefix
  --- means nothing. `tail` says why, in that verb's own terms.
  local function plain_set(word, tail)
    local set, complaint = parse_set_only(word)
    if set ~= nil then
      return set
    end
    if type(word) == "string" and word:find(":", 1, true) then
      return nil, hint("a layer prefix belongs on bind, unbind, alias and icon - " .. tail)
    end
    return nil, complaint
  end

  -- The model is rebuilt on every attach and detach, so the dep is a getter:
  -- a captured instance would be the one from a previous login.
  local function bindings()
    return deps.bindings()
  end

  --[[ One address word -> the three things the model wants: the set
       argument (prefix and all, as the model spells it), the side folded to
       `left`/`right`, and the slot number.

       The prefix ends at the LAST colon, because a context address carries
       two (`ctx:<name>:1L3`) and a context name may contain none. The set
       is canonicalised to its own digits only when it stands alone, so
       `007L1` echoes back as the 7 it addressed while a prefixed set keeps
       the text the model's own patterns expect. ]]
  local function parse_address(word, allow_prefix)
    if type(word) ~= "string" then
      return nil, hint("an address is " .. ADDRESS_FORM)
    end
    local prefix, tail = word:match("^(.*):([^:]*)$")
    if prefix == nil then
      prefix, tail = "", word
    else
      prefix = prefix:lower() .. ":"
    end
    if prefix ~= "" and not allow_prefix then
      return nil, hint("a layer prefix belongs on bind, unbind, alias and icon - address this one as " .. ADDRESS_FORM)
    end
    local digits, side_word, slot_word = tail:match("^(%d+)([lLrR])(%d+)$")
    if digits == nil then
      return nil, hint("no such address: " .. word .. " - an address is " .. ADDRESS_FORM)
    end
    local slot = whole_number(slot_word)
    if type(slot) ~= "number" or slot < 1 or slot > SLOT_COUNT then
      return nil, hint("no such slot: " .. slot_word .. " - a slot is 1-" .. SLOT_COUNT)
    end
    local set = whole_number(digits)
    if type(set) ~= "number" or set < 1 or set > SET_COUNT then
      return nil, hint("no such set: " .. digits .. " - a set is 1-" .. SET_COUNT)
    end
    local side = side_word:lower() == "l" and "left" or "right"
    -- Prefixed, the model parses the whole string itself and wants the
    -- text; plain, the canonical digits.
    return (prefix ~= "" and (prefix .. digits) or tostring(set)), side, slot
  end

  --- `<set><L|R>`, for the views, which address a whole side and no slot.
  local function parse_view_address(word)
    if type(word) ~= "string" then
      return nil, hint("a view points at <set><L|R> - 2L, 3R")
    end
    local digits, side_word = word:match("^(%d+)([lLrR])$")
    if digits == nil then
      -- A layer prefix is the likelier mistake than a typo, and deserves
      -- its own answer: a view shows a whole side, every layer stacked.
      if word:find(":", 1, true) then
        return nil,
          hint("a layer prefix belongs on bind, unbind, alias and icon - a view points at <set><L|R>, e.g. 2L")
      end
      return nil, hint("no such view target: " .. word .. " - a view points at <set><L|R>, e.g. 2L")
    end
    local set = whole_number(digits)
    if type(set) ~= "number" or set < 1 or set > SET_COUNT then
      return nil, hint("no such set: " .. digits .. " - a set is 1-" .. SET_COUNT)
    end
    return set, side_word:lower() == "l" and "left" or "right"
  end

  -- "1L3", or "sub:1L3": the layer prefix is kept as the user addressed it,
  -- and the side arrives already folded to "left"/"right".
  local function address_label(set_arg, side, slot)
    return tostring(set_arg) .. (side == "left" and "L" or "R") .. slot
  end

  --[[ The bound action as one readable phrase: type, name, target, and the
       alias when the slot draws one -- without it a listing cannot be
       matched to what is on screen.

       Every field goes through tostring: the model guarantees only that an
       entry IS a table, and a hand-edited file whose `type` is a table
       would otherwise throw inside a command handler (paint_slot takes the
       same precaution with the same fields). ]]
  --[[ A listing prints the RECORD, not the thing's name: type, action,
       target, alias - the same words `bind` takes and the same words the
       hand-editable `data/<Character>/crossbar/<JOB>.lua` holds, in that
       order, so what you read here is what is stored and what you would
       type to reproduce it.

       That is why `display` is deliberately absent. It is the game's own
       casing for an action whose stored form must stay as it is (a mount's
       lower-case command name), so it belongs to the label paths - the slot
       name, the tooltip, the bind echo, the travel countdown - and not to a
       surface whose job is to show the file. A binder-bound Chocobo
       therefore DRAWS as "Chocobo" and LISTS as `mount chocobo`, and both
       are correct for what they are. ]]
  local function record_label(record)
    local parts = { tostring(record.type) }
    if record.action ~= nil then
      parts[#parts + 1] = tostring(record.action)
    end
    if record.target ~= nil then
      parts[#parts + 1] = "<" .. tostring(record.target) .. ">"
    end
    if record.alias ~= nil then
      parts[#parts + 1] = '"' .. tostring(record.alias) .. '"'
    end
    return table.concat(parts, " ")
  end

  --[[ Three answers, not two: the dep says true (a real action), false
       (definitely not one), or NIL -- it has nothing to check against,
       because the type has no resource table or the client handed us no
       resources library at all. Nil is the degraded case the widget really
       produces (its closure is always wired), and reading it as "not an
       action" is what would make the caution below unreachable. ]]
  local function known_action(kind, name)
    if deps.action_exists == nil then
      return nil
    end
    local answer = deps.action_exists(kind, name)
    if answer == nil then
      return nil
    end
    return answer == true
  end

  --[[ The trailing word the action name swallowed, second-guessed against
       the client: `ws Savage Blade Zeid` reads as a three-word weaponskill
       or as a two-word one aimed at Zeid. Only where the shorter reading
       is a real action and the longer one is NOT do we know the user meant
       a target -- and storing the longer one would report success on a
       command that can never fire. Where either answer is unknown, the
       user's reading stands and the reply says so. ]]
  local function second_guess(kind, name, absorbed)
    if absorbed == nil then
      return nil, nil
    end
    local shorter = name:sub(1, #name - #absorbed - 1)
    local whole_known, shorter_known = known_action(kind, name), known_action(kind, shorter)
    if whole_known == nil or shorter_known == nil then
      return nil, "read '" .. shorter .. "' + target '" .. absorbed .. "'? quote the name to keep it whole"
    end
    if whole_known == false and shorter_known == true then
      -- '<shorter>' is real and '<name>' is not, so the user meant a
      -- target. Saying "quote <shorter> and aim it at <absorbed>" would
      -- name a command this parser refuses, so the advice is the terminal
      -- one both refusals share.
      return "'" .. name .. "' is not an action, and " .. TARGET_ADVICE, nil
    end
    return nil, nil
  end

  --- `bind <address> <type> [<action>] [<target>]`.
  local function bind(args)
    if #args < 3 then
      return hint("bind <address> <type> [<action>] [<target>] - an address is " .. ADDRESS_FORM)
    end
    local address, side, slot = parse_address(args[2], true)
    if address == nil then
      return side
    end
    local kind = args[3]:lower()
    local rest = slice(args, 4)
    local record = { type = kind }
    local absorbed = nil
    if NO_ACTION_TYPES[kind] then
      if kind == "ra" and #rest <= 1 then
        if rest[1] ~= nil then
          record.target = target_of(rest[1])
          if record.target == nil then
            return hint(not_a_target(rest[1]))
          end
        end
      elseif #rest > 0 then
        return hint(
          kind == "ra" and "ra takes a target and nothing else" or (kind .. " takes no action name or target")
        )
      end
    elseif WHOLE_LINE_TYPES[kind] then
      -- The whole line, interior quotes included -- but a leading quote that
      -- never closes is the same dropped-quote typo the other path refuses,
      -- and the wiki teaches quoting for exactly this type.
      local line, quote_complaint = unquote_checked(join(rest))
      if line == nil then
        return hint(quote_complaint)
      end
      record.action = line ~= "" and line or nil
    elseif kind == "open" then
      if #rest ~= 1 then
        return hint("open takes one screen name - try //hud crossbar open for the list")
      end
      record.action = unquote(rest[1]):lower()
    else
      local complaint_text
      record.action, record.target, complaint_text, absorbed = split_action_target(rest)
      if complaint_text ~= nil then
        return hint(complaint_text)
      end
    end
    local ok, complaint_text = deps.validate(record)
    if ok == nil then
      return hint(complaint_text)
    end
    local refusal, caution = second_guess(kind, record.action, absorbed)
    if refusal ~= nil then
      return hint(refusal)
    end
    local wrote, err = bindings().bind(address, side, slot, record)
    if wrote == nil then
      return hint(err)
    end
    local told = hint("bound " .. address_label(address, side, slot) .. " to " .. record_label(record))
    if caution ~= nil then
      return { told, "  " .. caution }, false, true
    end
    return told, false, true
  end

  --- `unbind <address>` -- the addressed layer only.
  local function unbind(args)
    if #args ~= 2 then
      return hint("unbind <address> - an address is " .. ADDRESS_FORM)
    end
    local address, side, slot = parse_address(args[2], true)
    if address == nil then
      return side
    end
    local entry, err = bindings().entry_at(address, side, slot)
    if entry == nil then
      if err ~= nil then
        return hint(err)
      end
      -- An unbind of an empty address is a no-op in the model; saying so
      -- beats a "done" that changed nothing (a mistyped layer prefix looks
      -- exactly like this).
      return hint("nothing bound at " .. address_label(address, side, slot))
    end
    local wrote, write_err = bindings().unbind(address, side, slot)
    if wrote == nil then
      return hint(write_err)
    end
    return hint("unbound " .. address_label(address, side, slot)), false, true
  end

  --[[ `alias` and `icon`: per-entry overrides, not separate state. Both read
       the addressed layer's own entry, write one field of it and put it
       back through bind, so a layer prefix means the same thing it does
       everywhere else. Omitting the final argument clears the override. ]]
  local function override(args, field, value, check)
    local address, side, slot = parse_address(args[2], true)
    if address == nil then
      return side
    end
    local entry, err = bindings().entry_at(address, side, slot)
    if entry == nil then
      if err ~= nil then
        return hint(err)
      end
      return hint("nothing bound at " .. address_label(address, side, slot) .. " to give " .. field .. " to")
    end
    -- Value checks run AFTER the address does: "no job loaded yet" and
    -- "nothing bound there" are the more fundamental refusals, and a user
    -- who sees the icon complaint first would go hunting for the wrong bug.
    if check ~= nil then
      local complaint_text = check()
      if complaint_text ~= nil then
        return complaint_text
      end
    end
    entry[field] = value
    local wrote, write_err = bindings().bind(address, side, slot, entry)
    if wrote == nil then
      return hint(write_err)
    end
    local phrase = value == nil and (field .. " cleared on ") or (field .. " '" .. value .. "' on ")
    return hint(phrase .. address_label(address, side, slot)), false, true
  end

  local function alias(args)
    if #args < 2 then
      return hint("alias <address> [<name>] - omit the name to clear")
    end
    local joined = join(args, 3)
    local name, complaint = unquote_checked(joined)
    if name == nil then
      return hint(complaint)
    end
    return override(args, "alias", name ~= "" and name or nil)
  end

  --[[ `icon <address> [<icon>]`: resolved exactly the way
       render.icon_candidates resolves the stored override -- the player's
       own art at icons/custom/<basename>.png first, then the shipped pack
       at assets/icons/<name>.png with the name taken VERBATIM (no kebab
       pass: the stored override is a path, not an action name). Rejected
       at entry rather than drawing nothing later. ]]
  local function icon(args)
    if #args < 2 then
      return hint("icon <address> [<icon>] - omit the icon to clear")
    end
    -- One name, but a quoted one may carry spaces: the folder is the
    -- player's own and the wiki tells them to name files whatever they want
    -- to type. An unquoted phrase simply resolves to no art and is refused
    -- by the check below.
    local joined = join(args, 3)
    local name, quote_complaint = unquote_checked(joined)
    if name == nil then
      return hint(quote_complaint)
    end
    name = name ~= "" and name or nil
    return override(args, "icon", name, function()
      -- Defensive only: the widget always wires file_exists in production
      -- (it is built from ctx.file_exists + ctx.asset, the same pair
      -- pick_icon draws with). Should a degraded ctx ever leave it out,
      -- nothing can be verified, and refusing every name would be worse
      -- than accepting one the bar may not find art for.
      if name == nil or deps.file_exists == nil then
        return nil
      end
      local basename = name:match("([^/]+)$")
      if basename == nil then
        -- "items/" and friends: there is no file name to look for, and a
        -- refusal naming icons/custom//.png would be nonsense.
        return hint("no icon named '" .. name .. "' - an icon name needs a file name, not just a folder")
      end
      local found = deps.file_exists("icons/custom/" .. basename .. ".png")
      found = found or deps.file_exists(ASSETS .. "icons/" .. name .. ".png")
      if not found then
        -- The custom probe flattens to the basename, so that is the file
        -- to name: telling them to create icons/custom/items/warp-ring.png
        -- would name a path nothing ever looks at.
        return hint("no icon named '" .. name .. "' - put art in icons/custom/" .. basename .. ".png")
      end
      return nil
    end)
  end

  --[[ `swap <address> <address>` -- both addresses' ENTIRE
       stacks change places, so no layer prefix applies. A move is a swap
       with an empty stack. ]]
  local function swap(args)
    if #args ~= 3 then
      return hint("swap <address> <address> - an address is " .. ADDRESS_FORM)
    end
    local addresses = {}
    for index, at in ipairs({ 2, 3 }) do
      -- No prefix: a swap moves every layer at once, so addressing one
      -- would promise something it does not do.
      local set, side, slot = parse_address(args[at], false)
      if set == nil then
        return side
      end
      addresses[index] = { set = tonumber(set), side = side, slot = slot }
    end
    local wrote, err = bindings().swap(addresses[1], addresses[2])
    if wrote == nil then
      return hint(err)
    end
    return hint(
      "swapped "
        .. address_label(addresses[1].set, addresses[1].side, addresses[1].slot)
        .. " with "
        .. address_label(addresses[2].set, addresses[2].side, addresses[2].slot)
    ),
      false,
      true
  end

  --- `list [<set>]` -- what this job's sets hold, through the live stack.
  local function list(args)
    if #args > 2 then
      return hint("list [<set>]")
    end
    local main, sub = bindings().job()
    if main == nil then
      return hint("no job loaded yet")
    end
    local first, last = 1, SET_COUNT
    if args[2] ~= nil then
      local set, complaint = plain_set(args[2], "list already shows every layer, prefixes and all")
      if set == nil then
        return complaint
      end
      first, last = set, set
    end
    local lines = { "crossbar: " .. main .. (sub and ("/" .. sub) or "") .. " bindings" }
    local found = false
    for set = first, last do
      local rows = {}
      for _, side in ipairs({ "left", "right" }) do
        for slot = 1, SLOT_COUNT do
          --[[ What is STORED, not what resolves: an inactive context layer
               and another subjob's overrides are bindings the user made and
               must be able to see. Only where an address carries more than
               one is the winner worth marking - on a single layer the mark
               would be on every row and mean nothing. ]]
          local layers = bindings().layers_at(set, side, slot)
          for _, layer in ipairs(layers) do
            rows[#rows + 1] = ("  %-4s %s [%s]%s"):format(
              tostring(set) .. (side == "left" and "L" or "R") .. slot,
              record_label(layer.entry),
              layer.source,
              (#layers > 1 and layer.active) and " live" or ""
            )
          end
        end
      end
      if #rows > 0 then
        found = true
        lines[#lines + 1] = " set " .. set .. (set == bindings().active_set() and " (active)" or "")
        for _, row in ipairs(rows) do
          lines[#lines + 1] = row
        end
      end
    end
    if not found then
      lines[#lines + 1] = "  nothing bound"
    end
    return lines
  end

  -- on|off, the framework's own switch spelling. Answers nil for anything
  -- else so the caller can hint with its own grammar.
  local function parse_switch(word)
    if word == nil then
      return nil
    end
    local value = word:lower()
    if value == "on" then
      return true
    end
    if value == "off" then
      return false
    end
    return nil
  end

  --[[ The config-owning half of the CLI. These write the component's own
       config table (views, set_flags, always_show_wxhb) rather than the
       binding store, so they ask the widget to save it -- and they need no
       job: the config is character-wide, and a set's shared-ness cannot vary
       by job or two jobs would disagree about where set n lives. ]]
  local function config()
    local live = deps.get_config()
    return type(live) == "table" and live or {}
  end

  -- The container may be missing or hand-broken; a write rebuilds it rather
  -- than throwing in a command handler.
  local function config_table(key)
    local live = config()
    if type(live[key]) ~= "table" then
      live[key] = {}
    end
    return live[key]
  end

  local function flags_for(set)
    local flags = config_table("set_flags")
    if type(flags[set]) ~= "table" then
      flags[set] = {}
    end
    return flags[set]
  end

  --- `view <wxhb-L|wxhb-R|exp-LR|exp-RL> <set><L|R>`.
  local function view(args)
    if #args ~= 3 then
      return hint("view <" .. table.concat(VIEW_ORDER, "|") .. "> <set><L|R> - e.g. view wxhb-L 2L")
    end
    local key = VIEW_KEYS[args[2]:lower()]
    if key == nil then
      return hint("no such view: " .. args[2] .. " - try " .. table.concat(VIEW_ORDER, ", "))
    end
    local set, side = parse_view_address(args[3])
    if set == nil then
      return side
    end
    config_table("views")[key] = { set = set, side = side }
    -- The canonical spelling, not the whole token upper-cased: the help,
    -- the hints and the status line all say `wxhb-L`.
    local shown = VIEW_ORDER[1]
    for _, name in ipairs(VIEW_ORDER) do
      if name:lower() == args[2]:lower() then
        shown = name
      end
    end
    return hint(shown .. " shows " .. set .. (side == "left" and "L" or "R")), true, true
  end

  --- `share <set> on|off` -- shared (every job) vs job-specific.
  local function share(args)
    if #args ~= 3 then
      return hint("share <set> on|off")
    end
    local set, complaint = plain_set(args[2], "a set is shared as a whole")
    if set == nil then
      return complaint
    end
    local shared = parse_switch(args[3])
    if shared == nil then
      return hint("share <set> on|off")
    end
    -- Read BEFORE the flag flips: afterwards the base reads the shared
    -- store and the job's own contents are invisible from here.
    local dormant = false
    if shared then
      for _, side in ipairs({ "left", "right" }) do
        for slot = 1, SLOT_COUNT do
          for _, layer in ipairs(bindings().layers_at(set, side, slot)) do
            dormant = dormant or layer.source == "base"
          end
        end
      end
    end
    flags_for(set).shared = shared
    local told = hint("set " .. set .. " is " .. (shared and "shared (every job)" or "job-specific"))
    if dormant then
      return {
        told,
        "  this job's own bindings for set "
          .. set
          .. " are dormant while it is shared - "
          .. "they stay in the file and come back if you share it off",
      },
        true,
        true
    end
    return told, true, true
  end

  --- `cycle <set> drawn|sheathed|both|none` -- rotation membership per
  --- weapon state. Both keys are always written, so the answer cannot depend
  --- on what a defaults merge would refill.
  local function cycle_flags(args)
    if #args ~= 3 then
      return hint("cycle <set> drawn|sheathed|both|none")
    end
    local set, complaint = plain_set(args[2], "a set is cycled as a whole")
    if set == nil then
      return complaint
    end
    local mode = args[3] and args[3]:lower() or nil
    local states = {
      drawn = { drawn = true, sheathed = false },
      sheathed = { drawn = false, sheathed = true },
      both = { drawn = true, sheathed = true },
      none = { drawn = false, sheathed = false },
    }
    local cycle = mode and states[mode] or nil
    if cycle == nil then
      return hint("cycle <set> drawn|sheathed|both|none")
    end
    flags_for(set).cycle = cycle
    return hint("set " .. set .. " cycles when " .. mode), true, true
  end

  --- `wxhb [on|off]` -- the WXHB resting on screen. No argument reports.
  local function wxhb(args)
    if #args > 2 then
      return hint("wxhb [on|off]")
    end
    local live = config()
    if args[2] == nil then
      return hint("wxhb rests on screen: " .. (live.always_show_wxhb and "on" or "off"))
    end
    local on = parse_switch(args[2])
    if on == nil then
      return hint("wxhb [on|off]")
    end
    live.always_show_wxhb = on
    return hint("wxhb rests on screen: " .. (on and "on" or "off")), true, true
  end

  --- `retry [on|off]` -- the cast retry. No argument reports.
  local function retry(args)
    if #args > 2 then
      return hint("retry [on|off]")
    end
    local live = config()
    if args[2] == nil then
      -- A config written before the feature existed has no block at all,
      -- and reads as off - the shipped posture - rather than being written
      -- into existence by a question.
      local block = type(live.retry) == "table" and live.retry or {}
      return hint("cast retry: " .. (block.enabled == true and "on" or "off"))
    end
    local on = parse_switch(args[2])
    if on == nil then
      return hint("retry [on|off]")
    end
    -- Through config_table, so only the switch is touched: the backoff and
    -- deadline are tuned in a live client, and flipping the feature off and
    -- on again must not throw that tuning away.
    config_table("retry").enabled = on
    return hint("cast retry: " .. (on and "on" or "off")), true, false
  end

  --- `copy <JOB>` -- seed this job's bindings from another job's file.
  local function copy(args)
    if #args ~= 2 then
      return hint("copy <JOB> - the job to seed this one's bindings from")
    end
    -- Job files are named by the job's own three letters; the framework
    -- folds argument case everywhere else too.
    local from = args[2]:upper()
    -- SHARED.lua type-checks as a job file but carries only `sets`, so
    -- copying it in would wipe this job's base, subjob and context layers
    -- and put nothing back. A shared set is already on every job anyway --
    -- that is what the flag means.
    if from == "SHARED" then
      return hint("copy takes a job, not the shared store - a shared set is already on every job")
    end
    local main = bindings().job()
    if main ~= nil and from == main:upper() then
      return hint(from .. " is already this job - copy takes the job to seed these bindings FROM")
    end
    local wrote, err = bindings().copy_from(from)
    if wrote == nil then
      return hint(err)
    end
    return hint("bindings copied from " .. args[2]:upper() .. " - this job's previous bindings were replaced"),
      false,
      true
  end

  --- `context list` -- the code-defined roster in stack order, active
  --- entries marked. There is nothing to author here: users bind INTO a
  --- context, they do not define one.
  local function context(args)
    if #args > 2 then
      return hint("context list - the roster is code-defined")
    end
    local sub = args[2] and args[2]:lower() or "list"
    if sub ~= "list" then
      return hint("context list - the roster is code-defined")
    end
    local active = {}
    for _, name in ipairs(bindings().active_contexts()) do
      active[name] = true
    end
    local lines = { "crossbar contexts (stack order, last wins):" }
    for _, entry in ipairs(roster) do
      lines[#lines + 1] = ("  %-15s %s%s"):format(entry.name, entry.label, active[entry.name] and " [active]" or "")
    end
    return lines
  end

  -- The verb table IS the surface: one entry per verb, so the router can
  -- never disagree with what is implemented.
  local VERBS = {
    help = function(args)
      if #args > 1 then
        return hint("help takes no arguments")
      end
      return HELP
    end,
    bind = bind,
    unbind = unbind,
    alias = alias,
    icon = icon,
    swap = swap,
    list = list,
    view = view,
    share = share,
    -- With arguments only: the widget answers bare `cycle` itself, and
    -- routes here when it sees any.
    cycle = cycle_flags,
    wxhb = wxhb,
    retry = retry,
    copy = copy,
    context = context,
  }

  local function command(raw)
    -- Words only: the verbs downstream index positionally. Empties need no
    -- filter -- lib/commands.clean drops them before core builds the
    -- passthrough, and a shortcut verb is split on %S+.
    local args = {}
    for _, word in ipairs(raw or {}) do
      if type(word) == "string" then
        args[#args + 1] = word
      end
    end
    local verb = args[1] and args[1]:lower() or ""
    local handler = VERBS[verb]
    if handler == nil then
      return "crossbar: unknown command '" .. tostring(args[1]) .. "' - try //hud crossbar help"
    end
    return handler(args)
  end

  --- Every verb this module answers, sorted -- the load-time collision
  --- check reads it, and a report built from it reads the same twice.
  function self.verbs()
    local names = {}
    for verb in pairs(VERBS) do
      names[#names + 1] = verb
    end
    table.sort(names)
    return names
  end

  --- Whether this module answers a verb -- the widget's routing test, so
  --- the verb surface lives in exactly one place. `set`, bare `cycle`, bare
  --- `open`, `edit` and the built-ins are the widget's own and are checked
  --- before this.
  function self.handles(verb)
    return type(verb) == "string" and VERBS[verb:lower()] ~= nil
  end

  -- The one view map: the widget's status line reads these rather than
  -- keeping a second copy that could disagree about a spelling.
  self.views = VIEW_LIST

  self.command = command

  return self
end

return new
