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

     The verbs the live widget answers itself -- `set`, `cycle` and `cycle
     back`, bare `open`, `edit` and the built-in actions -- are not here:
     they execute rather than author, and the widget owns execution. ]]

local roster = require("lib/actionbar/contexts")
local grammars = require("lib/actionbar/grammar")
local jobchange = require("lib/actionbar/jobchange")
local kebab = require("lib/actionbar/kebab")

-- The component's own asset root, for the shipped half of an icon name.
-- The asset ROOT, not one folder in it: what hangs off this is `own/` for
-- XIVHud's own chrome, `icons/` for the imported pack and `cooldown/` for
-- the sweep frames, each with its own licence beside it.
local ASSETS = "assets/"

-- Slots 1-4 are the face cross, 5-8 the D-pad, both clockwise from the top
-- (the component's own slot map). Nobody should have to memorise the indices.
--[[ An address is ONE word: `<set><L|R><slot>` - `1L1`, `2R8` - and
     carries no layer. It took a prefix until 2026-10-13 (`sub:1L1`,
     `wpn:great-katana:1L1`, `ctx:light-arts:1L1`); the layer is the
     `context=` marker now, beside alias= and icon= (see layer_of).

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
-- The form itself is the grammar's (lib/actionbar/grammar): the hotbar
-- addresses a slot as `3:7`, and both bars' hints must name their own.

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

--[[ One command per line throughout (Kevin, 2026-08-29). A spaced ` | `
     crammed several unrelated commands onto a shared line, which reads as
     one command with alternatives; an argument's own alternatives keep
     their unspaced pipe, `on|off`, because that is what they are. Built per
     bar: the name is the bar's, the address form its grammar's, and the two
     view verbs are the crossbar's alone. ]]
local function help_lines(name, grammar, with_views, extra)
  local hud = "  //hud " .. name
  local lines = {
    name .. " commands:",
    hud .. " - the job, the active set" .. (with_views and ", and where each view points" or ""),
    hud .. " set <1-8>",
    hud .. " cycle - advance the rotation",
    hud .. " cycle back - the other way",
    hud .. " list [<set>]",
  }
  if with_views then
    lines[#lines + 1] = hud .. " wxhb [on|off]"
  end
  -- A bar's own verbs, answered by its widget before the CLI sees them:
  -- listed here or a player could never discover them in game.
  for _, line in ipairs(extra or {}) do
    lines[#lines + 1] = hud .. " " .. line
  end
  lines[#lines + 1] = hud
    .. " bind <address> <type> [<action>] [<target>] [alias=<name>] [icon=<name>] [context=<layer>]"
  lines[#lines + 1] = hud .. " unbind <address> [context=<layer>]"
  lines[#lines + 1] = hud .. " alias <address> [<name>] [context=<layer>] - omit the name to clear"
  lines[#lines + 1] = hud .. " icon <address> [<name>] [context=<layer>] - omit the name to clear"
  lines[#lines + 1] = hud .. " swap <address> <address>"
  if with_views then
    lines[#lines + 1] = hud .. " view <wxhb-L|wxhb-R|exp-LR|exp-RL> <set><L|R>"
  end
  lines[#lines + 1] = hud .. " share <set> on|off"
  -- `cycle <set> <mode>` edits which rotations a set belongs to, which has
  -- nothing to do with sharing (Kevin, 2026-08-24). The bare `cycle` that
  -- advances the rotation is a different command again, listed above.
  lines[#lines + 1] = hud .. " cycle <set> drawn|sheathed|both|none"
  lines[#lines + 1] = hud .. " copy <JOB>"
  lines[#lines + 1] = hud .. " context list"
  lines[#lines + 1] = hud .. " open [<name>]"
  lines[#lines + 1] = hud .. " edit"
  lines[#lines + 1] = "  an address is " .. grammar.form
  -- The marker is the grammar, not decoration: an action name may be
  -- several words, and Windower strips the quotes that used to delimit one.
  lines[#lines + 1] =
    "  a bind's alias and icon are marked - alias=Cure 4 icon=cure - and the mark ends the action name"
  -- The layer, which was a prefix on the address until 2026-10-13 (Kevin).
  lines[#lines + 1] = "  a layer is context=sub:<job>, context=wpn:<weapon type> or context=buf:<buff context>"
    .. " - none is the job base, and a weaponskill goes to its own weapon type"
  return lines
end

-- Types that carry no action name. `ra` still takes a target (`/ra <t>`);
-- the rest take nothing at all.
local NO_ACTION_TYPES =
  { ra = true, draw = true, mr = true, warp = true, sneak = true, invisible = true, reraise = true }
-- Types whose action IS the rest of the line: a chat line or a console
-- command may end in anything, so no target word is split off it.
local WHOLE_LINE_TYPES = { ct = true, ex = true }

--[[ FFXI's target tokens. The grammar is `<type> [<action>] [<target>]` over
     words Windower already split on spaces, and an action name may be
     several words ("Ascetic's Fury"), so the last word is a target only when
     it is one of these -- or is bracketed, which says so outright. Quoting
     the WHOLE name settles it without the list (it arrives as one word);
     quoting part of one settles nothing, the quotes being gone by then. ]]
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

--[[ The reading that actually works, named the same way everywhere a
     trailing word is refused. Deliberately terminal: it does NOT teach
     `<Name>` for a player (a bracketed player name is UNVERIFIED in client
     and awaits the in-client check), and it never sends anyone to a form the
     parser also refuses. A user who types `<Name>` anyway is still obeyed;
     we simply do not recommend it. Quoting is not offered beside it: quoting
     part of a line changes nothing (the words arrive as they already were),
     and quoting the whole of one binds a name each of these refusals has
     just established is not an action.

     The token list is the parser's own: a16-a19 are not alliance targets,
     so a hint promising a10-a25 would promise more than bind accepts. ]]
local TARGET_TOKENS_ADVICE = "a target token (t, me, bt, ft, pet, p0-p5, a10-a15, a20-a25, st, stpc, stnpc)"

local function is_target_token(word)
  if TARGET_TOKENS[word] then
    return true
  end
  return word:match("^p[0-5]$") ~= nil or word:match("^a[12][0-5]$") ~= nil
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--[[ A name the client handed over with its quotes still ON, stripped of
     them, and whether it was. Windower groups a quoted run into one argument
     and strips the quotes before an addon is asked (settled in a live client
     2026-08-30), so nothing in the parser may depend on reading one: this is
     the belt to that brace, and the only place a quote is read at all. An
     unbalanced quote is simply a character in the name, which is what a chat
     line carrying one needs.

     Trimmed when it strips: the quotes are the user saying where the name
     ends, and an action carrying the whitespace inside them can never
     fire. ]]
local function undelimit(text)
  --[[ A MATCHED pair, which is why the inside is checked for a quote of its
       own: `"/p a" "b"` opens and closes with one without those two being a
       pair, and stripping them would delete characters out of the middle of
       what the user typed. A delimited line that really does carry interior
       quotes is left wrapped instead - storing what was typed beats
       silently editing it, and no client this addon has met can produce
       either shape. ]]
  local inside = #text > 1 and text:sub(1, 1) == '"' and text:sub(-1) == '"' and text:sub(2, -2)
  if inside and inside:find('"', 1, true) == nil then
    return trim(inside), true
  end
  return text, false
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
  local bare = undelimit(word)
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

--[[ The words as one phrase. An EMPTY word contributes nothing, not even
     its separator: the old grammar spelled "an icon with no alias" as an
     empty span, so `ja "Berserk" "" "attack"` is what an existing user
     retypes, and joining it plainly names an action with a double space in
     it that no listing or file could be read back from. ]]
local function join(words, from, to)
  local kept = {}
  for _, word in ipairs(slice(words, from or 1, to)) do
    if word ~= "" then
      kept[#kept + 1] = word
    end
  end
  return table.concat(kept, " ")
end

--[[ The label markers, `alias=`, `icon=` and `context=`. The value one
     opens runs to the next marker or the end of the line, which makes
     `alias="My Alias"` read the same however the client hands it over: as
     one argument with the quotes stripped (what a live client does, settled
     2026-08-30), as two with the quotes still on, or as two bare words. The
     addon has no say in which of those it gets, and quotes alone -- the
     grammar this replaced -- survive none of them. ]]
local LABEL_MARKERS = { alias = true, icon = true, context = true }

--- The field a word opens a label for and the first of its value, or nil.
--- Matched case-insensitively, exactly as every verb and component name is.
local function label_marker(word)
  local field, value = word:match("^(%a+)=(.*)$")
  if field == nil or not LABEL_MARKERS[field:lower()] then
    return nil
  end
  return field:lower(), value
end

--- Where the labels begin -- the first word opening one, or past the end.
--- That word also ends the ACTION NAME, which is the whole reason the
--- markers exist: nothing else can say where a several-word name stops.
local function labels_begin(words)
  for index = 1, #words do
    if label_marker(words[index]) ~= nil then
      return index
    end
  end
  return #words + 1
end

--[[ The alias form to advise for words the user must otherwise drop, or ""
     where the line ALREADY carries an alias - a second one is refused, so
     advising it would be advising a second refusal.

     QUOTED, because that is the spelling that works in ONE hop: the words
     may end in a target token, which a bare `alias=junk me` would be
     refused for, and a value handed over whole is never read that way. Both
     the grouping client and a splitting one read it back the same. ]]
local function label_hint(words, labelled)
  if labelled then
    return ""
  end
  return ', or mark it as alias="' .. words .. '"'
end

--- Whether an `alias=` carrying a VALUE is already among the words from
--- `from` on. An empty one stores no label, so a hint to write one is still
--- the way out rather than a second refusal.
local function has_alias(words, from)
  for index = from, #words do
    local field, first = label_marker(words[index])
    if field == "alias" then
      local stop = index
      while stop < #words and label_marker(words[stop + 1]) == nil do
        stop = stop + 1
      end
      if trim(first .. " " .. join(words, index + 1, stop)) ~= "" then
        return true
      end
    end
  end
  return false
end

--[[ The labels, read from the first marker on: an alias and an icon, in
     either order and neither required. Answers a table plus a complaint,
     and an empty value is no label at all -- `alias=` says nothing.

     `targetable` says whether the type could have taken a target, which is
     the only case where a target word inside a value is worth refusing over
     (see below). On a type that takes none, `Follow me` and `Warp me` are
     ordinary aliases and there would be nowhere else to put the word.
     `targeted` says one was already given, which changes the ADVICE and
     nothing else: a second target cannot be moved in front of the first. ]]
local function take_labels(words, from, targetable, targeted)
  local found, seen, index = {}, {}, from
  -- The FIRST marker is where a late target has to go in front of: in front
  -- of a later one is still behind this one, which is this same refusal.
  local opener = label_marker(words[from])
  while index <= #words do
    local field, first = label_marker(words[index])
    if field == nil then
      -- Unreachable from `bind`, which starts at a marker and lets every
      -- value run to the next one. Answering rather than assuming keeps a
      -- later caller from dropping words in silence.
      return nil, "a label starts at alias= or icon= - drop " .. join(words, index)
    end
    local stop = index
    while stop < #words and label_marker(words[stop + 1]) == nil do
      stop = stop + 1
    end
    if seen[field] then
      -- The repeat alone: naming the rest of the line would tell the user
      -- to drop a marker that is doing its job.
      return nil, "one " .. field .. "= only - drop " .. join(words, index, stop)
    end
    --[[ A target as a word of its OWN at the end of a value is a target that
         arrived late, not part of an alias: the value would swallow it and
         bind an action aimed at nothing, reported as a success. A value the
         client handed over whole is one the user delimited, so `alias=Cure
         p1` in one piece is left alone - that is an alias someone wrote,
         and quoting it is the way out the refusal below spells. ]]
    local value = undelimit(trim(first .. " " .. join(words, index + 1, stop)))
    -- `stop > index` is the value having words of its OWN: the marker word
    -- itself carries the `alias=` prefix, so it can never read as a target.
    if targetable and stop > index and target_of(words[stop]) ~= nil then
      --[[ Two refusals, neither naming a form that binds something worse.
           Told to move a SECOND target in front of the first, the words
           between them join the action name: `ma Cure IV p1 alias=Heal me`
           would become `ma Cure IV p1 <me>`, a spell that does not exist,
           reported as a success. Keeping it in the label is the way out of
           both, so both spell it. ]]
      --[[ Only an ALIAS can keep it: an icon is a file name, so
           `icon="cure p1"` names no art and the advice would land on the
           icon refusal instead - the one thing neither message may do. ]]
      local keep = field == "alias" and (', or keep it in the label as alias="' .. value .. '"') or ""
      if targeted then
        return nil, "one target only - drop " .. words[stop] .. keep
      end
      return nil, "a target goes before the labels - move " .. words[stop] .. " in front of " .. opener .. "=" .. keep
    end
    seen[field] = true
    found[field] = value ~= "" and value or nil
    index = stop + 1
  end
  return found
end

--[[ The LAYER a verb writes, given as a third marker beside alias= and icon=
     (Kevin, 2026-10-13): it was a prefix on the address until then, which
     let a bare `wpn:` land a gun's weaponskill on the sword's layer. Every
     form names what it means - a bare `wpn` or `sub` would read whatever is
     worn or held right now, which is how that happened - and none is the
     job base. The answer is the model's own prefix, `wpn:great-katana`.

     A buff context is typed `buf:` (Kevin, 2026-10-13) and stored as the
     model's `ctx:` - the CLI's word, not the model's, so nothing written
     to a file changes. `layer_word` turns one back into the other. ]]
local LAYER_FORMS = "context=sub:<job>, context=wpn:<weapon type> or context=buf:<buff context>"

local MISSING_NAME = {
  wpn = "name the weapon type - context=wpn:sword, context=wpn:marksmanship",
  sub = "name the subjob - context=sub:whm",
  buf = "name the buff context - context=buf:light-arts",
}

local function layer_of(value)
  local text = tostring(value or "")
  local kind, name = text:match("^(%a+):(.*)$")
  if kind == nil then
    kind, name = text:match("^(%a+)$"), ""
  end
  if kind == nil then
    return nil, "a layer is " .. LAYER_FORMS
  end
  kind, name = kind:lower(), trim(name):lower()
  if name == "" then
    return nil, MISSING_NAME[kind] or ("a layer is " .. LAYER_FORMS)
  end
  --[[ A name is one word, checked here rather than left to the model: past
       this point a stray word or colon comes back as the model's own
       `unknown layer: ctx:light arts:1`, which names neither what was typed
       nor the form that works. ]]
  if kind == "wpn" then
    return "wpn:" .. kebab(name)
  elseif kind == "sub" then
    if not name:match("^%a+$") then
      return nil, "no such subjob: " .. name .. " - context=sub:<job>, like context=sub:whm"
    end
    return "sub:" .. name
  elseif kind == "buf" then
    if not name:match("^[%w%-]+$") then
      return nil, "no such buff context: " .. name .. " - one word, like context=buf:light-arts"
    end
    return "ctx:" .. name
  end
  return nil, "a layer is " .. LAYER_FORMS
end

--- A model layer as the CLI says it: a buff context is `buf:`.
local function layer_word(layer)
  return (tostring(layer):gsub("^ctx:", "buf:"))
end

--- The layer a verb's context= names: nil where it carries none, false and
--- the refusal where it names nothing.
local function resolve_layer(has_context, value)
  if not has_context then
    return nil
  end
  local layer, complaint_text = layer_of(value)
  if layer == nil then
    return false, complaint_text
  end
  return layer
end

--- Whether a bind's labels carry `context=`, and its value (which may be
--- empty), read the way take_labels reads every label.
local function context_marker(words, from)
  for index = from, #words do
    local field, first = label_marker(words[index])
    if field == "context" then
      local stop = index
      while stop < #words and label_marker(words[stop + 1]) == nil do
        stop = stop + 1
      end
      return true, undelimit(trim(first .. " " .. join(words, index + 1, stop)))
    end
  end
  return false, nil
end

--[[ The `context=` word out of a line that takes no other marker - unbind,
     alias, icon - wherever it stands, and the words left without it. One
     word: a layer has no spaces, and one the client handed over quoted
     arrives as a single word. A second marker is the fourth answer, so it
     is refused as bind refuses it rather than kept as a word of an alias. ]]
local function extract_context(words, from)
  local kept, found, value, repeated = {}, false, nil, nil
  for index = from, #words do
    local word = words[index]
    local field, rest = word:match("^(%a+)=(.*)$")
    if field ~= nil and field:lower() == "context" then
      if found then
        repeated = word
      else
        found, value = true, undelimit(trim(rest))
      end
    else
      kept[#kept + 1] = word
    end
  end
  return kept, found, value, repeated
end

--[[ The action name and its target, over the words in FRONT of the labels.
     The last word is the target only when it reads as one -- an
     unrecognised word stays part of the name, which is what makes a player
     name usable as a target only when bracketed. The fourth answer is the
     word the name swallowed, for `bind` to second-guess the reading with. ]]
local function split_action_target(rest)
  if #rest == 0 then
    return nil, nil, nil, nil
  end
  local last = rest[#rest]
  local name_words = #rest
  local target = nil
  if #rest >= 2 and target_of(last) ~= nil then
    target, name_words = target_of(last), #rest - 1
  end
  --[[ A name that arrived with its quotes on is one the user DELIMITED, so
       the swallowed-word check below has nothing to second-guess: they said
       where the name ends. Every other name is taken exactly as typed. ]]
  local name, delimited = undelimit(join(rest, 1, name_words))
  -- A grouping client strips the quotes and keeps what was inside them, so
  -- ` Cure IV ` arrives with the user's own spaces on it; an action name
  -- carrying those can never fire.
  name = trim(name)
  if name == "" then
    return nil, nil, "an empty action name"
  end
  --[[ A quote still in the name is HALF a pair: the client strips a whole
       one before we are asked, and nothing in the game is called `"Cure IV`.
       Storing it would bind an action that can never fire and report a
       success. A ct or ex line is the opposite case and does not come
       through here - a quote is part of what gets said. ]]
  if name:find('"', 1, true) ~= nil then
    return nil, nil, "a quote left in the name: " .. name .. " - no action is called that"
  end
  if target ~= nil then
    return name, target
  end
  --[[ No target: the name took every word, the last of which might have
       been meant as one. The fourth answer is that word, for bind to check
       - TRIMMED, because the name it will be measured against is, and a
       word arriving with the user's own spaces on it (`ws Savage "Blade "`)
       would otherwise cut the shorter reading mid-word. ]]
  -- An empty last word swallowed nothing, and second-guessing the name
  -- against it would cut the shorter reading mid-word.
  last = trim(last)
  return name, nil, nil, (not delimited and #rest >= 2 and last ~= "") and last or nil
end

local function new(deps)
  local self = {}

  --[[ Whose CLI this is: the bar's name prefixes every reply and its help,
       its grammar spells an address, and only the crossbar has views to
       point. Defaults are the crossbar's, so a caller that predates the
       hotbar reads exactly as it did. ]]
  local bar_name = deps.name or "crossbar"
  local grammar = deps.grammar or grammars.crossbar()
  local with_views = deps.views ~= false
  local SLOT_COUNT = grammar.slot_count
  local SET_COUNT = grammar.set_count
  local ADDRESS_FORM = grammar.form
  local HELP = help_lines(bar_name, grammar, with_views, deps.help_extra)

  local function hint(message)
    return bar_name .. ": " .. message
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
      return nil, hint("a layer is context= on bind, unbind, alias and icon - " .. tail)
    end
    return nil, complaint
  end

  -- The model is rebuilt on every attach and detach, so the dep is a getter:
  -- a captured instance would be the one from a previous login.
  local function bindings()
    return deps.bindings()
  end

  --[[ One address word -> the set (canonical digits, so `007L1` echoes back
       as the 7 it addressed), the side folded to `left`/`right`, and the
       slot number. An address carries no layer since 2026-10-13: that is
       `context=`, and a prefix in front is refused pointing there - except
       for a verb that moves every layer at once (`whole_stack`), which
       takes no context= to point at. ]]
  local function parse_address(word, whole_stack)
    if type(word) ~= "string" then
      return nil, hint("an address is " .. ADDRESS_FORM)
    end
    local prefix, digits, side, slot_word = grammar.split(word)
    if digits == nil then
      return nil, hint("no such address: " .. word .. " - an address is " .. ADDRESS_FORM)
    end
    if prefix ~= "" and whole_stack then
      return nil,
        hint("a swap moves every layer at once - drop the " .. prefix .. ": (an address is " .. ADDRESS_FORM .. ")")
    end
    if prefix ~= "" then
      return nil,
        hint(
          "an address takes no layer in front - name the layer as "
            .. LAYER_FORMS
            .. " (an address is "
            .. ADDRESS_FORM
            .. ")"
        )
    end
    local slot = whole_number(slot_word)
    if type(slot) ~= "number" or slot < 1 or slot > SLOT_COUNT then
      return nil, hint("no such slot: " .. slot_word .. " - a slot is 1-" .. SLOT_COUNT)
    end
    local set = whole_number(digits)
    if type(set) ~= "number" or set < 1 or set > SET_COUNT then
      return nil, hint("no such set: " .. digits .. " - a set is 1-" .. SET_COUNT)
    end
    return tostring(set), side, slot
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
        return nil, hint("a layer is context= on bind, unbind, alias and icon - a view points at <set><L|R>, e.g. 2L")
      end
      return nil, hint("no such view target: " .. word .. " - a view points at <set><L|R>, e.g. 2L")
    end
    local set = whole_number(digits)
    if type(set) ~= "number" or set < 1 or set > SET_COUNT then
      return nil, hint("no such set: " .. digits .. " - a set is 1-" .. SET_COUNT)
    end
    return set, side_word:lower() == "l" and "left" or "right"
  end

  -- "1L3", and the layer it reached as the context= that names it.
  local function address_label(set, side, slot, layer)
    return grammar.label(set, side, slot) .. (layer ~= nil and (" context=" .. layer_word(layer)) or "")
  end

  -- The model's set argument: the layer's prefix in front of the set.
  local function set_arg(set, layer)
    return layer ~= nil and (layer .. ":" .. set) or set
  end

  --[[ The bound action as one readable phrase: type, name, target, and the
       alias when the slot draws one -- without it a listing cannot be
       matched to what is on screen.

       Every field goes through tostring: the model guarantees only that an
       entry IS a table, and a hand-edited file whose `type` is a table
       would otherwise throw inside a command handler (paint_slot takes the
       same precaution with the same fields). ]]
  --[[ A listing prints the RECORD, not the thing's name: type, action,
       target, alias, icon - the same words `bind` takes and the same words the
       hand-editable `<JOB>.lua` in the component's own directory holds, in that
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
    --[[ Marked and quoted, which is what a retyped row needs: the marker
         says these are labels, and the quotes hold a multi-word value
         together for a client that splits the row on spaces. A client that
         groups a quoted run instead strips the quotes, and the marker reads
         back the same value either way. ]]
    if record.alias ~= nil then
      parts[#parts + 1] = 'alias="' .. tostring(record.alias) .. '"'
    end
    if record.icon ~= nil then
      parts[#parts + 1] = 'icon="' .. tostring(record.icon) .. '"'
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

  --[[ The complaint an icon name earns, or nil. Resolved exactly the way
       render.icon_candidates resolves the stored override -- the player's
       own art at icons/custom/<basename>.png first, then the shipped pack
       at assets/icons/<name>.png with the name taken VERBATIM (no kebab
       pass: the stored override is a path, not an action name). Rejected
       at entry rather than drawing nothing later. ]]
  local function icon_complaint(name)
    -- The nil dep is defensive only: the widget always wires file_exists in
    -- production (it is built from ctx.file_exists + ctx.asset, the same
    -- pair pick_icon draws with). Should a degraded ctx ever leave it out,
    -- nothing can be verified, and refusing every name would be worse than
    -- accepting one the bar may not find art for.
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
      -- The custom probe flattens to the basename, so that is the file to
      -- name: telling them to create icons/custom/items/warp-ring.png would
      -- name a path nothing ever looks at.
      return hint("no icon named '" .. name .. "' - put art in icons/custom/" .. basename .. ".png")
    end
    return nil
  end

  --[[ The trailing word the action name swallowed, second-guessed against
       the client: `ws Savage Blade Zeid` reads as a three-word weaponskill
       or as a two-word one aimed at Zeid. Only where the shorter reading
       is a real action and the longer one is NOT do we know the user meant
       a target -- and storing the longer one would report success on a
       command that can never fire. Where either answer is unknown, the
       user's reading stands and the reply says so. ]]
  local function second_guess(kind, name, absorbed, labelled)
    if absorbed == nil then
      return nil, nil
    end
    local shorter = name:sub(1, #name - #absorbed - 1)
    local whole_known, shorter_known = known_action(kind, name), known_action(kind, shorter)
    -- The third reading, which every other refusal in the parser names and
    -- this one did not: the word may have been meant as a LABEL, which is
    -- the likeliest of the three now that the old grammar spelled it that
    -- way (`ma Cure IV Healer`).
    local label = label_hint(absorbed, labelled)
    if whole_known == nil or shorter_known == nil then
      return nil, "read '" .. shorter .. "' + target '" .. absorbed .. "'? quote the name to keep it whole" .. label
    end
    if whole_known == false and shorter_known == true then
      --[[ '<shorter>' is real and '<name>' is not, so the user meant a
           target or a label. Saying "quote <shorter> and aim it at
           <absorbed>" would name a command this parser refuses, and
           "quote the whole name" - the advice this shared with the other
           refusal - would bind the name just established NOT to be an
           action. What is left is the two readings that work. ]]
      return "'"
        .. name
        .. "' is not an action - a player name as a target is not supported yet; use "
        .. TARGET_TOKENS_ADVICE
        .. label,
        nil
    end
    return nil, nil
  end

  --[[ A layer as a listing names it: the context= that reaches it, in the
       form bind takes; the job base and the shared store, which no
       context= names, as themselves. ]]
  local function layer_tag(source)
    local kind, name = tostring(source):match("^(%a+):(.+)$")
    if kind == "sub" then
      return "context=sub:" .. name:lower()
    elseif kind == "wpn" then
      return "context=wpn:" .. kebab(name)
    elseif kind == "ctx" then
      return "context=buf:" .. name
    end
    return "[" .. tostring(source) .. "]"
  end

  --[[ The way to the layers an address DOES hold, for an edit that found its
       own empty: only bind infers a weaponskill's layer, so `alias 1R1 SB`
       over one reads the job base, and "nothing bound" alone would deny
       what the bar is drawing. ]]
  local function held_hint(address, side, slot)
    local ways = {}
    for _, layer in ipairs(bindings().layers_at(tonumber(address), side, slot) or {}) do
      local tag = layer_tag(layer.source)
      ways[#ways + 1] = tag:match("^context=") and ("with " .. tag) or "without context="
    end
    if #ways == 0 then
      return ""
    end
    return " - try it " .. table.concat(ways, " or ")
  end

  --- `bind <address> <type> [<action>] [<target>] [alias=<name>] [icon=<name>] [context=<layer>]`.
  local function bind(args)
    if #args < 3 then
      return hint(
        "bind <address> <type> [<action>] [<target>] [alias=<name>] [icon=<name>] [context=<layer>] - an address is "
          .. ADDRESS_FORM
      )
    end
    local address, side, slot = parse_address(args[2])
    if address == nil then
      return side
    end
    local kind = args[3]:lower()
    local rest = slice(args, 4)
    local record = { type = kind }
    local absorbed = nil
    --[[ The labels are found FIRST: the marker that opens one is also what
         ends the action name -- the one job the quotes used to do, before a
         live client showed they never reach us. Each type then reads its own
         words out of the head, and none of them has to tell a label from a
         name. ]]
    local labels_at = labels_begin(rest)
    local head = slice(rest, 1, labels_at - 1)
    -- Whether a target could have been given at all, which decides how a
    -- target word inside a label reads: a late aim on the types that take
    -- one, an ordinary word of the alias on the types that do not.
    local targetable = kind == "ra"
      or not (NO_ACTION_TYPES[kind] or WHOLE_LINE_TYPES[kind] or kind == "open" or kind == "jc")
    local labelled = has_alias(rest, labels_at)
    if NO_ACTION_TYPES[kind] then
      if kind == "ra" and #head > 0 then
        record.target = target_of(head[1])
        if record.target == nil then
          --[[ Its own refusal rather than the shared target advice, which
               would tell a type that takes NO action name to quote the
               name. `ra Shoot` is what the old positional grammar's muscle
               memory types for a label, so both readings are named. ]]
          return hint(
            "ra takes a target or a label - "
              .. head[1]
              .. " is neither; use "
              .. TARGET_TOKENS_ADVICE
              .. label_hint(join(head), labelled)
          )
        end
        if #head > 1 then
          local extra = join(head, 2)
          return hint("ra takes a target, then alias= and icon= - drop " .. extra .. label_hint(extra, labelled))
        end
      elseif kind ~= "ra" and #head > 0 then
        local extra = join(head)
        return hint(kind .. " takes no action name or target - drop " .. extra .. label_hint(extra, labelled))
      end
    elseif WHOLE_LINE_TYPES[kind] then
      --[[ Every word up to the marker, with the user's own quoting put
           BACK. An argument can only carry whitespace where they quoted it
           - the client groups a quoted run and strips the quotes - so a
           word with a space in it is one they delimited, and a chat line
           has to reach the game with those quotes or it will not cast
           (`ct ma "Cure IV" <t>`). A word already carrying a quote is left
           alone, deliberately: those quotes are the user's own, and a
           second pair around them would say something they did not type. A
           quoted run with no space in it is indistinguishable from
           a bare word by the time we are asked and keeps no quotes -
           harmless, the game needing none around a single word. ]]
      local said = {}
      for index, word in ipairs(head) do
        local delimit = word:find("%s") ~= nil and word:find('"', 1, true) == nil
        said[index] = delimit and ('"' .. word .. '"') or word
      end
      -- Trimmed like every other name: `undelimit` only trims what it
      -- strips, and a line stored with the user's trailing space says it.
      local line = trim(undelimit(trim(join(said))))
      record.action = line ~= "" and line or nil
    elseif kind == "open" then
      if #head < 1 then
        return hint("open takes one screen name - try //hud " .. bar_name .. " open for the list")
      end
      if #head > 1 then
        -- The pointer, not just the arity: an extra word here usually means
        -- the screen names are what the user is missing.
        local extra = join(head, 2)
        return hint(
          "open takes one screen name, then alias= and icon= - "
            .. extra
            .. " is neither; drop it"
            .. label_hint(extra, labelled)
            .. ", or try //hud "
            .. bar_name
            .. " open for the list"
        )
      end
      record.action = undelimit(head[1]):lower()
    elseif kind == "jc" then
      if #head ~= 1 then
        return hint("jc takes one main/sub pair, like WAR/BLM, then alias= and icon=")
      end
      local main, sub = jobchange.parse(undelimit(head[1]))
      if main == nil then
        return hint(sub)
      end
      -- The binder's label: the icon already says the main job.
      record.action, record.alias = main .. "/" .. sub, sub
    else
      local complaint_text
      record.action, record.target, complaint_text, absorbed = split_action_target(head)
      if complaint_text ~= nil then
        return hint(complaint_text)
      end
    end
    if labels_at <= #rest then
      local labels, labels_complaint = take_labels(rest, labels_at, targetable, record.target ~= nil)
      if labels == nil then
        return hint(labels_complaint)
      end
      record.alias, record.icon = labels.alias or record.alias, labels.icon
    end
    --[[ A weaponskill belongs to ONE weapon type, the resources' own, and
         is filed there (Kevin, 2026-10-13) - never the one in hand, since a
         gun's weaponskill on the sword's layer is a slot that empties the
         moment the sword does. A context= naming any other layer is refused
         here, BEFORE the swallowed-word check, which would otherwise advise
         a retry only to have it refused for the layer - and after the
         labels, whose refusal of a target typed behind context= is the one
         every marker gives. A name that swallowed a word has no type to
         name, so that refusal names the form. ]]
    local layer, layer_complaint = resolve_layer(context_marker(rest, labels_at))
    if layer == false then
      return hint(layer_complaint)
    end
    local weapon_class = kind == "ws" and deps.weapon_class_of ~= nil and deps.weapon_class_of(record.action) or nil
    local own_layer = weapon_class ~= nil and ("wpn:" .. kebab(weapon_class)) or nil
    if kind == "ws" and layer ~= nil and layer ~= own_layer then
      if own_layer ~= nil then
        return hint(
          record.action
            .. (weapon_class:match("^[AEIOUaeiou]") and " is an " or " is a ")
            .. weapon_class
            .. " weaponskill - context="
            .. own_layer
            .. ", or leave context= off"
        )
      elseif not layer:match("^wpn:") then
        return hint(
          "a weaponskill binds on a weapon layer - context=wpn:<weapon type>, or leave context= off for its own"
        )
      end
    end
    local ok, complaint_text = deps.validate(record)
    if ok == nil then
      return hint(complaint_text)
    end
    -- A bind is one command: an icon nothing can draw refuses the whole of
    -- it rather than binding the action and dropping the art silently.
    local icon_refusal = icon_complaint(record.icon)
    if icon_refusal ~= nil then
      return icon_refusal
    end
    local refusal, caution = second_guess(kind, record.action, absorbed, labelled)
    if refusal ~= nil then
      return hint(refusal)
    end
    -- With no context=, its own type's layer - inferred only now, past the
    -- swallowed-word check, which has the better answer for a name that
    -- took in a target.
    if kind == "ws" and layer == nil then
      if own_layer == nil then
        if known_action("ws", record.action) == false then
          return hint("no weaponskill named " .. record.action)
        end
        return hint(
          "cannot tell which weapon type " .. record.action .. " belongs to - give it as context=wpn:<weapon type>"
        )
      end
      layer = own_layer
    end
    local wrote, err = bindings().bind(set_arg(address, layer), side, slot, record)
    if wrote == nil then
      return hint(err)
    end
    local told = hint("bound " .. address_label(address, side, slot, layer) .. " to " .. record_label(record))
    if caution ~= nil then
      return { told, "  " .. caution }, false, true
    end
    return told, false, true
  end

  --- `unbind <address> [context=<layer>]` -- the addressed layer only.
  local function unbind(args)
    local extra, has_context, context_value, repeated = extract_context(args, 3)
    if repeated ~= nil then
      return hint("one context= only - drop " .. repeated)
    end
    if #args < 2 or #extra > 0 then
      return hint("unbind <address> [context=<layer>] - an address is " .. ADDRESS_FORM)
    end
    local address, side, slot = parse_address(args[2])
    if address == nil then
      return side
    end
    local layer, layer_complaint = resolve_layer(has_context, context_value)
    if layer == false then
      return hint(layer_complaint)
    end
    local entry, err = bindings().entry_at(set_arg(address, layer), side, slot)
    if entry == nil then
      if err ~= nil then
        return hint(err)
      end
      -- An unbind of an empty address is a no-op in the model; saying so
      -- beats a "done" that changed nothing (a mistyped layer looks
      -- exactly like this).
      return hint("nothing bound at " .. address_label(address, side, slot, layer) .. held_hint(address, side, slot))
    end
    local wrote, write_err = bindings().unbind(set_arg(address, layer), side, slot)
    if wrote == nil then
      return hint(write_err)
    end
    return hint("unbound " .. address_label(address, side, slot, layer)), false, true
  end

  --[[ `alias` and `icon`: per-entry overrides, not separate state. Both read
       the addressed layer's own entry, write one field of it and put it
       back through bind, so a context= means the same thing it does
       everywhere else. Omitting the final argument clears the override. ]]
  local function override(args, field, value, check, context)
    local address, side, slot = parse_address(args[2])
    if address == nil then
      return side
    end
    if context.repeated ~= nil then
      return hint("one context= only - drop " .. context.repeated)
    end
    local layer, layer_complaint = resolve_layer(context.found, context.value)
    if layer == false then
      return hint(layer_complaint)
    end
    local entry, err = bindings().entry_at(set_arg(address, layer), side, slot)
    if entry == nil then
      if err ~= nil then
        return hint(err)
      end
      return hint(
        "nothing bound at "
          .. address_label(address, side, slot, layer)
          .. " to give "
          .. field
          .. " to"
          .. held_hint(address, side, slot)
      )
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
    local wrote, write_err = bindings().bind(set_arg(address, layer), side, slot, entry)
    if wrote == nil then
      return hint(write_err)
    end
    local phrase = value == nil and (field .. " cleared on ") or (field .. " '" .. value .. "' on ")
    return hint(phrase .. address_label(address, side, slot, layer)), false, true
  end

  local function alias(args)
    if #args < 2 then
      return hint("alias <address> [<name>] [context=<layer>] - omit the name to clear")
    end
    local words, has_context, context_value, repeated = extract_context(args, 3)
    local name = trim(undelimit(join(words)))
    return override(
      args,
      "alias",
      name ~= "" and name or nil,
      nil,
      { found = has_context, value = context_value, repeated = repeated }
    )
  end

  --- `icon <address> [<icon>]` -- the same name a bind takes, checked the
  --- same way.
  local function icon(args)
    if #args < 2 then
      return hint("icon <address> [<icon>] [context=<layer>] - omit the icon to clear")
    end
    local words, has_context, context_value, repeated = extract_context(args, 3)
    -- One name, but a quoted one may carry spaces: the folder is the
    -- player's own and the wiki tells them to name files whatever they want
    -- to type. An unquoted phrase simply resolves to no art and is refused
    -- by the check below.
    local name = trim(undelimit(join(words)))
    name = name ~= "" and name or nil
    return override(args, "icon", name, function()
      return icon_complaint(name)
    end, { found = has_context, value = context_value, repeated = repeated })
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
      local set, side, slot = parse_address(args[at], true)
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
      local set, complaint = plain_set(args[2], "list already shows every layer")
      if set == nil then
        return complaint
      end
      first, last = set, set
    end
    local lines = { hint(main .. (sub and ("/" .. sub) or "") .. " bindings") }
    local found = false
    for set = first, last do
      local rows = {}
      for _, side in ipairs(grammar.side_order) do
        for slot = 1, SLOT_COUNT do
          --[[ What is STORED, not what resolves: an inactive context layer
               and another subjob's overrides are bindings the user made and
               must be able to see. Only where an address carries more than
               one is the winner worth marking - on a single layer the mark
               would be on every row and mean nothing. ]]
          local layers = bindings().layers_at(set, side, slot)
          for _, layer in ipairs(layers) do
            rows[#rows + 1] = ("  %-4s %s %s%s"):format(
              grammar.label(set, side, slot),
              record_label(layer.entry),
              layer_tag(layer.source),
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
       job: the config is per character and layout slot, not per job, and a
       set's shared-ness cannot vary by job or two jobs would disagree about
       where set n lives. ]]
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
      for _, side in ipairs(grammar.side_order) do
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
  ---
  --- Job-gated (Kevin, 2026-09-04): only the contexts the scoped job can
  --- reach are listed, since a context follows the job whose buff it
  --- watches and offering the rest invites a bind into a layer that could
  --- never fire.
  local function context(args)
    if #args > 2 then
      return hint("context list - the roster is code-defined")
    end
    local sub = args[2] and args[2]:lower() or "list"
    if sub ~= "list" then
      return hint("context list - the roster is code-defined")
    end
    local available = {}
    for _, name in ipairs(bindings().available_contexts()) do
      available[name] = true
    end
    local job, sub_job = bindings().job()
    if next(available) == nil then
      local scope = job == nil and "no job loaded yet" or ("none on " .. job .. (sub_job and "/" .. sub_job or ""))
      return hint("contexts: " .. scope .. " - a context follows the job whose buff it watches")
    end
    local active = {}
    for _, name in ipairs(bindings().active_contexts()) do
      active[name] = true
    end
    local lines = { hint("contexts (stack order, last wins):") }
    for _, entry in ipairs(roster) do
      if available[entry.name] then
        lines[#lines + 1] = ("  %-15s %s%s"):format(entry.name, entry.label, active[entry.name] and " [active]" or "")
      end
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
    view = with_views and view or nil,
    share = share,
    -- The membership edit only: the widget answers bare `cycle` and `cycle
    -- back` itself, and routes anything else here.
    cycle = cycle_flags,
    wxhb = with_views and wxhb or nil,
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
      return hint("unknown command '" .. tostring(args[1]) .. "' - try //hud " .. bar_name .. " help")
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
