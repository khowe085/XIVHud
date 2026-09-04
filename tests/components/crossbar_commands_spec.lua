local new_commands = require("components/crossbar/commands")
local new_bindings = require("components/crossbar/bindings")
local new_actions = require("components/crossbar/actions")

--[[ The store is a FILE, not a shared table: lib/settings serializes on
     save and loadstring's a fresh table on load, so neither side can reach
     the other's memory. A fake that handed out live references would let a
     verb that mutates a record in place look persisted when nothing was
     ever written. ]]
local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for key, entry in pairs(value) do
    copy[key] = deep_copy(entry)
  end
  return copy
end

local function default_flags()
  local flags = {}
  for set = 1, 8 do
    flags[set] = { shared = false, cycle = { drawn = true, sheathed = true } }
  end
  return flags
end

-- A CLI over a real binding model, an in-memory file store and a live config
-- table -- the same shapes the widget hands it.
local function build(opts)
  opts = opts or {}
  local world = {
    files = opts.files or {},
    saved = {},
    stats = {},
    asked = {},
    icons = opts.icons or {},
    config = {
      always_show_wxhb = false,
      views = {
        wxhb_left = { set = 2, side = "left" },
        wxhb_right = { set = 2, side = "right" },
        expanded_lr = { set = 3, side = "left" },
        expanded_rl = { set = 3, side = "right" },
      },
      set_flags = opts.set_flags or default_flags(),
    },
  }
  local bindings = new_bindings({
    load = function(name)
      return deep_copy(world.files[name])
    end,
    save = function(name, data)
      world.files[name] = deep_copy(data)
      world.saved[name] = (world.saved[name] or 0) + 1
    end,
    get_config = function()
      return world.config
    end,
  })
  if opts.job ~= false then
    bindings.set_job(opts.job or "SCH", opts.sub)
  end
  if opts.weapon then
    bindings.set_weapon_type(opts.weapon)
  end
  local commands = new_commands({
    bindings = function()
      return bindings
    end,
    --[[ The widget's own shape: the dep is ALWAYS wired, and answers nil
         when it has nothing to check against (no resources library). A
         fixture that omitted the closure instead would exercise a branch
         production never takes. ]]
    action_exists = function(kind, name)
      world.asked[#world.asked + 1] = kind .. ":" .. name
      if opts.known == nil then
        return nil
      end
      return opts.known[name] == true
    end,
    get_config = function()
      return world.config
    end,
    file_exists = function(path)
      world.stats[#world.stats + 1] = path
      return world.icons[path] == true
    end,
    validate = new_actions({}).validate,
  })
  world.bindings = bindings
  return commands, world
end

-- Reads a stored slot without assuming any of the path exists -- a rejected
-- verb must leave the whole tree untouched, file included.
local function stored(world, file, set, side, slot)
  local data = world.files[file]
  local sets = data and data.sets
  local entries = sets and sets[set]
  local side_entries = entries and entries[side]
  return side_entries and side_entries[slot]
end

-- The reply is a string or a list of strings; both fold to one blob for the
-- content assertions.
local function text_of(reply)
  if type(reply) == "table" then
    return table.concat(reply, "\n")
  end
  return tostring(reply)
end

describe("crossbar commands", function()
  describe("bind", function()
    it("writes a game action into the job base", function()
      local commands, world = build()
      local reply, save_config, repaint = commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "t" })
      assert.are.same(
        { type = "ws", action = "Savage Blade", target = "t" },
        world.files.SCH.sets[1].left[3],
        text_of(reply)
      )
      assert.is_falsy(save_config, "a binding write saves through the model, not the config")
      assert.is_true(repaint)
      assert.is_string(reply)
    end)

    it("takes the button names as slots", function()
      local commands, world = build()
      commands.command({ "bind", "1R1", "ja", "Provoke" })
      commands.command({ "bind", "1R8", "ja", "Berserk" })
      assert.equal("Provoke", world.files.SCH.sets[1].right[1].action)
      assert.equal("Berserk", world.files.SCH.sets[1].right[8].action)
    end)

    it("targets the subjob layer with sub:", function()
      local commands, world = build({ sub = "NIN" })
      commands.command({ "bind", "sub:2L4", "ja", "Utsusemi" })
      assert.equal("Utsusemi", world.files.SCH.sub.NIN[2].left[4].action)
      assert.is_nil(stored(world, "SCH", 2, "left", 4))
    end)

    it("targets a context layer with ctx:", function()
      local commands, world = build()
      commands.command({ "bind", "ctx:light-arts:1L3", "ja", "Addendum:", "White" })
      assert.equal("Addendum: White", world.files.SCH.contexts["light-arts"][1].left[3].action)
    end)

    it("targets the equipped weapon class with wpn:", function()
      local commands, world = build({ weapon = "Great Katana" })
      commands.command({ "bind", "wpn:1L3", "ws", "Tachi:", "Fudo" })
      assert.equal("Tachi: Fudo", world.files.SCH.weapons["Great Katana"][1].left[3].action)
    end)

    it("refuses a wpn: address with nothing in hand, and says why", function()
      local commands, world = build()
      local reply = commands.command({ "bind", "wpn:1L3", "ws", "Savage", "Blade" })
      assert.is_not_nil(text_of(reply):find("weapon", 1, true), text_of(reply))
      assert.is_nil(world.files.SCH)
    end)

    -- The other side of the same rule: an entry the player can SEE in
    -- `list` and can delete must not be one they cannot rename.
    it("still relabels an entry an out-of-reach context already holds", function()
      local commands, world = build({
        job = "WAR",
        sub = "NIN",
        files = {
          WAR = { contexts = { ["light-arts"] = { [1] = { left = { [3] = { type = "ja", action = "Penury" } } } } } },
        },
      })
      commands.command({ "alias", "ctx:light-arts:1L3", "Pen" })
      assert.equal("Pen", world.files.WAR.contexts["light-arts"][1].left[3].alias)
    end)

    it("refuses a context this job cannot reach, naming the job that can", function()
      local commands = build({ job = "WAR", sub = "NIN" })
      local reply = commands.command({ "bind", "ctx:light-arts:1L3", "ja", "Penury" })
      assert.is_not_nil(text_of(reply):find("SCH", 1, true), text_of(reply))
    end)

    it("rejects an unknown context and an unparseable set", function()
      local commands, world = build()
      for _, address in ipairs({ "ctx:bogus:1", "sub", "9", "0" }) do
        local reply, _, repaint = commands.command({ "bind", address, "l", "3", "ja", "Provoke" })
        assert.is_string(reply, address)
        assert.is_falsy(repaint, address)
      end
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("keeps a quoted action name whole and strips the quotes", function()
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", '"Addendum:', 'White"', "me" })
      assert.are.same({ type = "ma", action = "Addendum: White", target = "me" }, world.files.SCH.sets[1].left[1])
    end)

    it("reads a trailing target token and keeps everything else in the name", function()
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", "Cure", "IV", "p1" })
      assert.are.same({ type = "ma", action = "Cure IV", target = "p1" }, world.files.SCH.sets[1].left[1])
      commands.command({ "bind", "1L2", "ws", "Ascetic's", "Fury" })
      assert.are.same({ type = "ws", action = "Ascetic's Fury" }, world.files.SCH.sets[1].left[2])
    end)

    it("accepts the alliance target tokens", function()
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", "Cure", "a15" })
      commands.command({ "bind", "1L2", "ma", "Cure", "a21" })
      commands.command({ "bind", "1L3", "ma", "Cure", "p5" })
      assert.equal("a15", stored(world, "SCH", 1, "left", 1).target)
      assert.equal("a21", stored(world, "SCH", 1, "left", 2).target)
      assert.equal("p5", stored(world, "SCH", 1, "left", 3).target)
    end)

    it("refuses the alliance numbers the game does not use", function()
      -- a16-a19 are not targets: the parties are a10-a15 and a20-a25, so
      -- a17 stays part of the action name rather than becoming a target.
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", "Cure", "a17" })
      assert.are.same({ type = "ma", action = "Cure a17" }, stored(world, "SCH", 1, "left", 1))
      local reply, _, repaint = commands.command({ "bind", "1L2", "ra", "a17" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 2))
    end)

    it("reads a lone word as the action name, never as a bare target", function()
      -- A one-word rest is the action: `ma t` binds a spell called t (odd,
      -- but the user's), never a targetless spell aimed at t.
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", "t" })
      assert.are.same({ type = "ma", action = "t" }, stored(world, "SCH", 1, "left", 1))
    end)

    it("accepts an angle-bracketed target", function()
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", "Cure", "<stpc>" })
      assert.are.same({ type = "ma", action = "Cure", target = "stpc" }, world.files.SCH.sets[1].left[1])
    end)

    it("keeps a bracketed target's case while folding the game's own tokens", function()
      -- The brackets are the user saying "this word is the target", so it
      -- is stored as typed; the game's own tokens are case-insensitive
      -- spellings of one thing and fold.
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", '"Cure IV"', "<Kevin>" })
      assert.equal("Kevin", stored(world, "SCH", 1, "left", 1).target)
      commands.command({ "bind", "1L2", "ma", "Cure", "<T>" })
      assert.equal("t", stored(world, "SCH", 1, "left", 2).target)
      commands.command({ "bind", "1L3", "ra", "<Kevin>" })
      assert.equal("Kevin", stored(world, "SCH", 1, "left", 3).target)
    end)

    it("refuses a bare word that is not one of the game's targets", function()
      -- Where the word cannot be part of the name - as ra's only argument,
      -- ra taking none - an unrecognised one is a typo, not a target:
      -- binding it would build a command that silently never fires.
      local commands, world = build()
      for _, words in ipairs({
        { "bind", "1L3", "ra", "Kevin" },
      }) do
        local reply, _, repaint = commands.command(words)
        assert.is_string(reply, words[5])
        assert.is_falsy(repaint, words[5])
        -- The bracket form for a player NAME is unverified in client, so
        -- the hint must not teach it; it names the game's own tokens.
        assert.is_nil(reply:find("<Kevin>", 1, true), reply)
        assert.is_not_nil(reply:find("me", 1, true), reply)
        -- The parser takes a10-a15 and a20-a25, not a16-a19: a hint that
        -- promises more than the parser accepts is a hint that lies.
        assert.is_nil(reply:find("a10-a25", 1, true), reply)
        assert.is_not_nil(reply:find("a10-a15", 1, true), reply)
        assert.is_not_nil(reply:find("a20-a25", 1, true), reply)
      end
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("binds the no-action types bare, ra with a target", function()
      local commands, world = build()
      commands.command({ "bind", "1L5", "ra", "t" })
      commands.command({ "bind", "1L6", "draw" })
      commands.command({ "bind", "1L7", "mr" })
      commands.command({ "bind", "1L8", "warp" })
      assert.are.same({ type = "ra", target = "t" }, world.files.SCH.sets[1].left[5])
      assert.are.same({ type = "draw" }, world.files.SCH.sets[1].left[6])
      assert.are.same({ type = "mr" }, world.files.SCH.sets[1].left[7])
      assert.are.same({ type = "warp" }, world.files.SCH.sets[1].left[8])
    end)

    it("unwraps only a matched pair, never two quotes that are not one", function()
      --[[ `"/p a" "b"` opens and closes with a quote without those two
           being a pair, and stripping them deletes characters out of the
           middle of a line the user typed. Only the client that hands
           quotes through can produce this shape at all, which is the one
           this unwrapping exists for - corrupting it there would be worse
           than never unwrapping. ]]
      local commands, world = build()
      commands.command({ "bind", "1R1", "ct", '"/p a"', '"b"' })
      commands.command({ "bind", "1R2", "ct", '"/p a"', '"b"', "alias=X" })
      commands.command({ "alias", "1R1", '"Big"', "and", '"Small"' })
      assert.equal('"/p a" "b"', stored(world, "SCH", 1, "right", 2).action)
      assert.equal('"Big" and "Small"', stored(world, "SCH", 1, "right", 1).alias)
    end)

    it("keeps an unbalanced quote in a ct or ex line", function()
      -- A quote is a character now, not grammar: the client strips the pair
      -- that used to delimit a line, and `alias=` is what ends one. A chat
      -- line refused for carrying a quote would be a line nobody can say.
      local commands, world = build()
      for slot, kind in ipairs({ "ct", "ex" }) do
        commands.command({ "bind", "1R" .. slot, kind, '"sea', "all" })
        assert.equal('"sea all', stored(world, "SCH", 1, "right", slot).action, kind)
      end
      commands.command({ "bind", "1R3", "ct", '"' })
      assert.equal('"', stored(world, "SCH", 1, "right", 3).action)
    end)

    it("trims a quoted ct or ex line the way it trims a name", function()
      local commands, world = build()
      commands.command({ "bind", "1R3", "ct", '" sea all linkshell "' })
      assert.equal("sea all linkshell", stored(world, "SCH", 1, "right", 3).action)
    end)

    it("keeps interior quotes on a ct or ex line", function()
      local commands, world = build()
      commands.command({ "bind", "1R2", "ex", "exec", 'say "hi"' })
      assert.equal('exec say "hi"', stored(world, "SCH", 1, "right", 2).action)
    end)

    it("takes the whole rest of the line for ct and ex", function()
      local commands, world = build()
      commands.command({ "bind", "1R1", "ct", "party", "I", "am", "here" })
      commands.command({ "bind", "1R2", "ex", "exec", "pull.txt" })
      assert.are.same({ type = "ct", action = "party I am here" }, world.files.SCH.sets[1].right[1])
      assert.are.same({ type = "ex", action = "exec pull.txt" }, world.files.SCH.sets[1].right[2])
    end)

    it("points at the opener list when open has no name, and unquotes one", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1R3", "open" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("//hud crossbar open", 1, true), reply)
      assert.is_falsy(repaint)
      commands.command({ "bind", "1R3", "open", '"map"' })
      assert.are.same({ type = "open", action = "map" }, stored(world, "SCH", 1, "right", 3))
    end)

    it("validates open targets at bind time", function()
      local commands, world = build()
      commands.command({ "bind", "1R3", "open", "map" })
      assert.are.same({ type = "open", action = "map" }, world.files.SCH.sets[1].right[3])
      local reply, _, repaint = commands.command({ "bind", "1R4", "open", "bogus" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "right", 4))
    end)

    it("rejects an unknown type, a bad side and a bad slot", function()
      local commands, world = build()
      local cases = {
        { "bind", "1L3", "spell", "Cure" },
        { "bind", "1", "x", "3", "ja", "Provoke" },
        { "bind", "1L9", "ja", "Provoke" },
        { "bind", "1", "l", "middle", "ja", "Provoke" },
      }
      for _, words in ipairs(cases) do
        local reply, _, repaint = commands.command(words)
        assert.is_string(reply, words[5])
        assert.is_falsy(repaint, words[5])
      end
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("trims a quoted name and refuses one that is all whitespace", function()
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", '" Cure IV"' })
      assert.equal("Cure IV", stored(world, "SCH", 1, "left", 1).action)
      commands.command({ "bind", "1L2", "ma", '"Cure IV "' })
      assert.equal("Cure IV", stored(world, "SCH", 1, "left", 2).action)
      local reply, _, repaint = commands.command({ "bind", "1L3", "ma", '"  "' })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("does not let a lone opening quote close itself", function()
      -- The wrapper is read over the whole name, so the opening quote is
      -- not asked to close on itself: `" Cure IV"` is one delimited name,
      -- not an empty one plus a target called Cure.
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", '"', "Cure", 'IV"' })
      assert.are.same({ type = "ma", action = "Cure IV" }, stored(world, "SCH", 1, "left", 1))
    end)

    it("refuses a quote left in a game action's name", function()
      -- The pair is read only where it wraps the WHOLE name. Half of one is
      -- no name at all - nothing in the game is called `"Cure IV` - so it is
      -- refused rather than bound as something that can never fire. A ct or
      -- ex line is the opposite case and keeps every quote it was given.
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1L3", "ma", '"Cure', "IV" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("quote", 1, true), reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("refuses extra words on the types that take none", function()
      local commands, world = build()
      for _, kind in ipairs({ "draw", "mr", "warp" }) do
        local reply, _, repaint = commands.command({ "bind", "1L3", kind, "Provoke" })
        assert.is_string(reply, kind)
        assert.is_falsy(repaint, kind)
      end
      local reply, _, repaint = commands.command({ "bind", "1L3", "ra", "t", "please" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("unquotes a quoted ra target", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ra", '"t"' })
      assert.are.same({ type = "ra", target = "t" }, stored(world, "SCH", 1, "left", 3))
    end)

    it("hints on wrong arity rather than binding half an address", function()
      local commands, world = build()
      for _, words in ipairs({ { "bind" }, { "bind", "1" }, { "bind", "1", "l" }, { "bind", "1L3" } }) do
        local reply, _, repaint = commands.command(words)
        assert.is_string(reply, #words .. " words")
        assert.is_falsy(repaint, #words .. " words")
      end
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("refuses before a job is scoped", function()
      local commands, world = build({ job = false })
      local reply, _, repaint = commands.command({ "bind", "1L3", "ja", "Provoke" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("job"), reply)
      assert.is_falsy(repaint)
      assert.are.same({}, world.saved)
    end)
  end)

  --[[ The optional trailing labels: an alias and an icon, each opened by its
       own MARKER, `alias=` and `icon=`. Windower groups a quoted run into one
       argument and strips the quote characters before an addon sees a word
       (settled in a live client 2026-08-30, testplan row C26), so a quote can
       never say which word is a label - it is gone by the time we are asked.
       The marker is what survives the trip, and it ends the action name,
       which is the one thing the quotes used to do.

       A value runs to the next marker or the end of the line, so all three
       shapes `alias="My Alias"` could arrive in read as the same alias. ]]
  describe("bind with an alias and an icon", function()
    it("reads a marked alias after a name and its target", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1L1", "ma", "Cure IV", "p1", "alias=Cure 4" })
      assert.are.same(
        { type = "ma", action = "Cure IV", target = "p1", alias = "Cure 4" },
        world.files.SCH.sets[1].left[1],
        text_of(reply)
      )
      assert.is_true(repaint)
    end)

    it("reads one alias however the client split the words", function()
      -- The three shapes `alias="My Alias"` can arrive in. Only the first is
      -- what a live client hands over today; reading the other two costs
      -- nothing and means the grammar does not rest on that staying true.
      local commands, world = build()
      commands.command({ "bind", "1L1", "ra", "t", "alias=My Alias" })
      commands.command({ "bind", "1L2", "ra", "t", 'alias="My', 'Alias"' })
      commands.command({ "bind", "1L3", "ra", "t", "alias=My", "Alias" })
      for slot = 1, 3 do
        assert.are.same({ type = "ra", target = "t", alias = "My Alias" }, stored(world, "SCH", 1, "left", slot), slot)
      end
    end)

    it("matches a marker case-insensitively, as it matches every verb", function()
      local commands, world = build({ icons = { ["icons/custom/cure.png"] = true } })
      commands.command({ "bind", "1L1", "ma", "Cure IV", "Alias=Cure 4", "ICON=cure" })
      assert.are.same(
        { type = "ma", action = "Cure IV", alias = "Cure 4", icon = "cure" },
        stored(world, "SCH", 1, "left", 1)
      )
    end)

    it("ends the action name at the first marker", function()
      -- What the quotes used to do, and the reason a ONE-WORD name can carry
      -- a label now: `ma Cure "C"` and `ma Cure C` arrive identically, so
      -- nothing but the marker could have told them apart.
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", "Cure", "IV", "alias=Big Cure" })
      commands.command({ "bind", "1L2", "ma", "Cure", "alias=C" })
      assert.are.same({ type = "ma", action = "Cure IV", alias = "Big Cure" }, stored(world, "SCH", 1, "left", 1))
      assert.are.same({ type = "ma", action = "Cure", alias = "C" }, stored(world, "SCH", 1, "left", 2))
    end)

    it("puts the user's own quoting back into a ct or ex line", function()
      --[[ An argument can only CARRY whitespace where the user quoted it -
           the client groups a quoted run and strips the quotes - so a word
           with a space in it is one they delimited, and the line has to
           reach the game with those quotes or it will not cast. Without
           this, `ct ma "Cure IV" <t>` says `/ma Cure IV <t>`. ]]
      local commands, world = build()
      commands.command({ "bind", "1R1", "ct", "ma", "Cure IV", "<t>" })
      commands.command({ "bind", "1R2", "ex", "gs", "c", "set TP", "alias=TP set" })
      assert.equal('ma "Cure IV" <t>', stored(world, "SCH", 1, "right", 1).action)
      assert.are.same({ type = "ex", action = 'gs c "set TP"', alias = "TP set" }, stored(world, "SCH", 1, "right", 2))
      -- A word with no space in it was never distinguishable from a bare
      -- one by the time we are asked, so it keeps none: harmless, the game
      -- needing no quotes around a single word.
      commands.command({ "bind", "1R3", "ct", "ma", "Cure", "<t>" })
      assert.equal("ma Cure <t>", stored(world, "SCH", 1, "right", 3).action)
      -- A whole line quoted as ONE run is re-quoted and then unwrapped
      -- again: the pair it gets back is its own, so it keeps neither.
      commands.command({ "bind", "1R4", "ct", "sea all linkshell" })
      assert.equal("sea all linkshell", stored(world, "SCH", 1, "right", 4).action)
    end)

    it("labels a ct or ex line, and leaves an unmarked one whole", function()
      -- The marker is also what delimits a whole-line type, which nothing
      -- else could: a chat line may end in anything, quotes included.
      local commands, world = build({ icons = { ["assets/icons/jobs/rdm.png"] = true } })
      commands.command({ "bind", "1R1", "ex", "jc RDM/DRK", "alias=RDM/DRK", "icon=jobs/rdm" })
      commands.command({ "bind", "1R2", "ct", "p", "say", '"hi"', "there" })
      assert.are.same(
        { type = "ex", action = "jc RDM/DRK", alias = "RDM/DRK", icon = "jobs/rdm" },
        stored(world, "SCH", 1, "right", 1)
      )
      assert.are.same({ type = "ct", action = 'p say "hi" there' }, stored(world, "SCH", 1, "right", 2))
    end)

    it("labels the types that take no action name", function()
      local commands, world = build({ icons = { ["assets/icons/items/warp-ring.png"] = true } })
      commands.command({ "bind", "1L8", "warp", "alias=Warp", "icon=items/warp-ring" })
      commands.command({ "bind", "1L5", "ra", "alias=Shoot" })
      assert.are.same({ type = "warp", alias = "Warp", icon = "items/warp-ring" }, stored(world, "SCH", 1, "left", 8))
      assert.are.same({ type = "ra", alias = "Shoot" }, stored(world, "SCH", 1, "left", 5))
    end)

    it("labels an open screen", function()
      local commands, world = build({ icons = { ["icons/custom/chart.png"] = true } })
      commands.command({ "bind", "1R3", "open", "map", "alias=Map", "icon=chart" })
      assert.are.same(
        { type = "open", action = "map", alias = "Map", icon = "chart" },
        stored(world, "SCH", 1, "right", 3)
      )
    end)

    it("points at the opener list when open is given more than a name", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1R3", "open", "map", "extra" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("//hud crossbar open", 1, true), reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "right", 3))
    end)

    it("takes an icon without an alias, and an empty marker as neither", function()
      -- No positional slot to hold open any more, so `icon=` alone is the
      -- whole of it - and a marker with nothing after it says nothing.
      local commands, world = build({ icons = { ["icons/custom/rage.png"] = true } })
      commands.command({ "bind", "1L2", "ja", "Berserk", "icon=rage" })
      commands.command({ "bind", "1L3", "ja", "Berserk", "alias=", "icon=rage" })
      assert.are.same({ type = "ja", action = "Berserk", icon = "rage" }, stored(world, "SCH", 1, "left", 2))
      assert.are.same({ type = "ja", action = "Berserk", icon = "rage" }, stored(world, "SCH", 1, "left", 3))
    end)

    it("refuses the whole bind when the icon names no art", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1L1", "ja", "Berserk", "icon=nosuchart" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("icons/custom/nosuchart.png", 1, true), reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 1))
      assert.are.same({}, world.saved, "a refused bind writes nothing at all")
    end)

    it("refuses a target that arrived after the labels, where one was possible", function()
      --[[ The value runs to the next marker, so a late target would vanish
           into the alias and bind an action aimed at nothing - reported as a
           success, which is the outcome worth refusing over. It is refused
           only where the target is a WORD OF ITS OWN: a value the client
           handed over whole is one the user delimited, and `alias=Cure p1`
           in one piece is an alias someone meant to write. ]]
      local commands, world = build()
      local late = text_of(commands.command({ "bind", "1L3", "ma", "Cure IV", "alias=Heal", "p1" }))
      assert.is_not_nil(late:find("p1", 1, true), late)
      assert.is_not_nil(late:find("in front", 1, true), late)
      -- Never advice that lands on another refusal: quoting the label is the
      -- way to keep it, so the refusal spells the quoted form out.
      assert.is_not_nil(late:find('alias="Heal p1"', 1, true), late)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
      commands.command({ "bind", "1L4", "ra", "t", "alias=Cure p1" })
      assert.are.same({ type = "ra", target = "t", alias = "Cure p1" }, stored(world, "SCH", 1, "left", 4))
    end)

    it("leaves a target word alone in a label on a type that takes no target", function()
      --[[ `Follow me` and `Heal me` are ordinary aliases. Refusing them
           where a target is IMPOSSIBLE would close a loop: the type refuses
           a bare `me` in front of the labels too, so there would be nowhere
           left to put it - and on a ct line, moving it in front is a
           silently DIFFERENT bind, the word being part of what gets said. ]]
      local commands, world = build()
      -- Split the way a client splits an UNQUOTED value, which is the shape
      -- the user types and the only one the guard could ever fire on.
      commands.command({ "bind", "1L1", "warp", "alias=Warp", "me" })
      commands.command({ "bind", "1R1", "ct", "follow", "alias=Follow", "me" })
      commands.command({ "bind", "1R2", "open", "map", "alias=Show", "me" })
      assert.are.same({ type = "warp", alias = "Warp me" }, stored(world, "SCH", 1, "left", 1))
      assert.are.same({ type = "ct", action = "follow", alias = "Follow me" }, stored(world, "SCH", 1, "right", 1))
      assert.are.same({ type = "open", action = "map", alias = "Show me" }, stored(world, "SCH", 1, "right", 2))
    end)

    it("says one target only when one is already in front", function()
      --[[ Never advice that lands on a WORSE bind: told to move `me` in
           front of a target that is already there, the words in between
           become part of the name and `ma Cure IV p1 <me>` binds a spell
           that does not exist, reported as a success. So the second target
           is one to drop, or to keep in the label deliberately. ]]
      local commands, world = build()
      local twice = text_of(commands.command({ "bind", "1L3", "ma", "Cure IV", "p1", "alias=Heal", "me" }))
      local ra = text_of(commands.command({ "bind", "1L5", "ra", "t", "alias=Shoot", "me" }))
      -- An ICON has no such way out: `icon="cure p1"` names no art, so the
      -- refusal that offered it would send the user to another refusal.
      local art = text_of(commands.command({ "bind", "1L6", "ma", "Cure IV", "icon=cure", "p1" }))
      assert.is_not_nil(art:find("in front of icon=", 1, true), art)
      assert.is_nil(art:find('icon="cure p1"', 1, true), art)
      -- In front of the FIRST marker, not the one the target landed in:
      -- moving it in front of the second lands on this refusal again.
      local second = text_of(commands.command({ "bind", "1L7", "ma", "Cure IV", "alias=Heal", "icon=cure", "p1" }))
      assert.is_not_nil(second:find("in front of alias=", 1, true), second)
      for _, reply in ipairs({ twice, ra }) do
        assert.is_not_nil(reply:find("one target", 1, true), reply)
        assert.is_nil(reply:find("in front", 1, true), "it must not send them back to a worse bind: " .. reply)
      end
      assert.is_not_nil(twice:find('alias="Heal me"', 1, true), twice)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
      assert.is_nil(stored(world, "SCH", 1, "left", 5))
    end)

    it("refuses a bind whose action name is only a marker", function()
      -- The marker ends the name, so a line starting with one leaves no
      -- name at all. The type's own validation says so.
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1L3", "ma", "alias=X" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("reads only alias= and icon= as markers", function()
      --[[ The one predicate that tells a marker from an ordinary word
           carrying an `=`. Without it a chat line saying `HP=50` loses
           everything after `HP` to a bogus label, reported as a success -
           and every type would gain labels nobody asked for. ]]
      local commands, world = build()
      commands.command({ "bind", "1R1", "ct", "p", "HP=50", "now" })
      commands.command({ "bind", "1L1", "ma", "Cure", "IV", "hp=50" })
      assert.are.same({ type = "ct", action = "p HP=50 now" }, stored(world, "SCH", 1, "right", 1))
      assert.equal("Cure IV hp=50", stored(world, "SCH", 1, "left", 1).action)
    end)

    it("refuses either marker twice", function()
      local commands, world = build({ icons = { ["icons/custom/a.png"] = true, ["icons/custom/b.png"] = true } })
      for _, words in ipairs({
        { "bind", "1L3", "ma", "Cure IV", "alias=A", "alias=B" },
        { "bind", "1L3", "ma", "Cure IV", "icon=a", "icon=b" },
      }) do
        local reply, _, repaint = commands.command(words)
        assert.is_not_nil(text_of(reply):find("only", 1, true), text_of(reply))
        assert.is_falsy(repaint, words[5])
      end
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
      -- The repeat alone is what to drop: naming the rest of the line would
      -- tell the user to throw away a marker that is doing its job.
      local trailing = text_of(commands.command({ "bind", "1L3", "ma", "Cure IV", "alias=A", "alias=B", "icon=a" }))
      assert.is_not_nil(trailing:find("drop alias=B", 1, true), trailing)
      assert.is_nil(trailing:find("icon=a", 1, true), trailing)
    end)

    it("trims a value the client handed over with the spaces still in it", function()
      -- A grouping client strips the quotes and keeps what was inside them,
      -- so ` cure ` arrives as one argument. Stored untrimmed it names no
      -- art, and an action name carrying the whitespace can never fire.
      local commands, world = build({ icons = { ["icons/custom/cure.png"] = true } })
      commands.command({ "bind", "1L1", "ma", " Cure IV ", "icon= cure " })
      commands.command({ "bind", "1L2", "ws", "Savage Blade" })
      commands.command({ "alias", "1L2", " Big Hit " })
      commands.command({ "icon", "1L2", " cure " })
      assert.are.same({ type = "ma", action = "Cure IV", icon = "cure" }, stored(world, "SCH", 1, "left", 1))
      assert.are.same(
        { type = "ws", action = "Savage Blade", alias = "Big Hit", icon = "cure" },
        stored(world, "SCH", 1, "left", 2)
      )
    end)

    it("takes the markers in either order", function()
      local commands, world = build({ icons = { ["icons/custom/cure.png"] = true } })
      commands.command({ "bind", "1L1", "ma", "Cure IV", "icon=cure", "alias=Cure 4" })
      assert.are.same(
        { type = "ma", action = "Cure IV", alias = "Cure 4", icon = "cure" },
        stored(world, "SCH", 1, "left", 1)
      )
    end)

    it("says what a bare trailing word needed", function()
      local commands, world = build()
      local bare = text_of(commands.command({ "bind", "1L4", "warp", "Home" }))
      local shot = text_of(commands.command({ "bind", "1L5", "ra", "t", "junk" }))
      -- The actionable form, not the grammar in the abstract: a message
      -- naming `alias=` alone is satisfied by any prose that mentions it.
      assert.is_not_nil(bare:find('alias="Home"', 1, true), bare)
      assert.is_not_nil(shot:find('alias="junk"', 1, true), shot)
      local screen = text_of(commands.command({ "bind", "1R1", "open", "map", "extra" }))
      assert.is_not_nil(screen:find('alias="extra"', 1, true), screen)
      --[[ Quoted, because that is the form that works in ONE hop: the words
           it names may end in a target token, and a bare `alias=junk me`
           lands on the late-target refusal. A client that groups the quoted
           run and one that splits it both read the label the same. ]]
      -- ...and not offered at all where an alias is already on the line:
      -- a second one is refused, so the advice would be a second refusal.
      local taken = text_of(commands.command({ "bind", "1L4", "warp", "Home", "alias=Warp" }))
      assert.is_not_nil(taken:find("drop Home", 1, true), taken)
      assert.is_nil(taken:find('alias="Home"', 1, true), taken)
      -- An EMPTY alias stores no label, so writing one is still the way out.
      local empty = text_of(commands.command({ "bind", "1L4", "warp", "Home", "alias=" }))
      assert.is_not_nil(empty:find('alias="Home"', 1, true), empty)
      local pair = text_of(commands.command({ "bind", "1L6", "ra", "t", "junk", "me" }))
      assert.is_not_nil(pair:find('alias="junk me"', 1, true), pair)
      -- ra's ONE-word case went to the target advice alone, which tells a
      -- type that takes no name to quote the name: `ra Shoot` is what the
      -- old positional grammar's muscle memory types for a label.
      local named = text_of(commands.command({ "bind", "1L7", "ra", "Shoot" }))
      assert.is_not_nil(named:find('alias="Shoot"', 1, true), named)
      assert.is_nil(stored(world, "SCH", 1, "left", 4))
      assert.is_nil(stored(world, "SCH", 1, "left", 5))
    end)

    it("points at the label grammar when it cannot tell a name from a target", function()
      -- The likeliest "I meant that as a label" mistake, and the one the old
      -- positional grammar refused outright. Every other refusal in the
      -- parser names the marker; this one said only "quote the name".
      local commands = build()
      local caution = text_of(commands.command({ "bind", "1L3", "ma", "Cure", "IV", "Healer" }))
      assert.is_not_nil(caution:find('alias="Healer"', 1, true), caution)
    end)

    it("trims a whole-line type the way every other name is trimmed", function()
      local commands, world = build()
      commands.command({ "bind", "1R1", "ct", "p", "" })
      assert.equal("p", stored(world, "SCH", 1, "right", 1).action)
    end)

    it("takes an empty argument as no word at all", function()
      --[[ The old grammar's spelling for "an icon with no alias" was an
           empty span, so `ja "Berserk" "" "attack"` is what an existing user
           retypes. The bind it makes is junk either way - that is the cost
           of replacing a grammar - but it must not be junk with a DOUBLE
           space in it, nor second-guessed against an empty word, which cut
           the shorter reading mid-name (`Savag`). ]]
      local commands, world = build()
      local legacy = text_of(commands.command({ "bind", "1L2", "ja", "Berserk", "", "attack" }))
      assert.equal("Berserk attack", stored(world, "SCH", 1, "left", 2).action)
      assert.is_not_nil(legacy:find("read 'Berserk'", 1, true), legacy)
      local empty = text_of(commands.command({ "bind", "1L3", "ws", "Savage", "" }))
      assert.equal("Savage", stored(world, "SCH", 1, "left", 3).action)
      assert.is_nil(empty:find("read ", 1, true), "nothing was swallowed, so nothing to second-guess: " .. empty)
    end)

    it("second-guesses the name the client's own spaces were trimmed from", function()
      --[[ The name is trimmed and the swallowed word is measured against
           it, so a word arriving with the user's spaces still on it (a
           grouped quoted run, `ws Savage "Blade "`) used to cut the shorter
           reading mid-word and offer `Savag`. ]]
      local commands = build()
      local reply = text_of(commands.command({ "bind", "1L3", "ws", "Savage", "Blade " }))
      assert.is_not_nil(reply:find("read 'Savage'", 1, true), reply)
    end)

    it("leaves the swallowed-word check reading the name alone", function()
      -- A label must not change which words the name is second-guessed over.
      local commands, world = build({ known = { ["Savage Blade"] = true } })
      local reply, _, repaint = commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "Zeid", "alias=SB" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("is not an action", 1, true), reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
      commands.command({ "bind", "1L4", "ws", "Savage", "Blade", "t", "alias=SB" })
      assert.are.same(
        { type = "ws", action = "Savage Blade", target = "t", alias = "SB" },
        stored(world, "SCH", 1, "left", 4)
      )
    end)

    it("leaves a bind's icon in place when the alias verb edits the entry", function()
      local commands, world = build({ icons = { ["icons/custom/cure.png"] = true } })
      commands.command({ "bind", "1L1", "ma", "Cure IV", "alias=Cure 4", "icon=cure" })
      commands.command({ "alias", "1L1", "Cure V" })
      assert.are.same(
        { type = "ma", action = "Cure IV", alias = "Cure V", icon = "cure" },
        stored(world, "SCH", 1, "left", 1)
      )
    end)

    it("lists what would reproduce the bind, icon and all", function()
      --[[ The listing prints the record in the words `bind` takes, so a row
           retyped BINDS THE SAME THING. The row is split on whitespace here,
           which is the WORST the client could do to it: the quotes a value
           is printed with survive that split, and the marker reassembles
           what they hold either way. ]]
      local commands, world = build({ icons = { ["icons/custom/cure.png"] = true } })
      commands.command({ "bind", "1L1", "ma", "Cure", "IV", "<p1>", "alias=Cure 4", "icon=cure" })
      local listed = text_of(commands.command({ "list", "1" }))
      assert.is_not_nil(listed:find('alias="Cure 4" icon="cure"', 1, true), listed)
      local words = { "bind", "1L2" }
      for word in listed:match("1L1%s+(.-)%s+%["):gmatch("%S+") do
        words[#words + 1] = word
      end
      commands.command(words)
      assert.are.same(stored(world, "SCH", 1, "left", 1), stored(world, "SCH", 1, "left", 2), table.concat(words, " "))
      assert.equal("cure", stored(world, "SCH", 1, "left", 2).icon)
    end)

    it("lists an icon with no alias so that retyping the row binds the same thing", function()
      -- The one shape the round trip above does not reach: `record_label`
      -- skips the alias branch entirely, and the icon has to stand alone.
      local commands, world = build({ icons = { ["icons/custom/rage.png"] = true } })
      commands.command({ "bind", "1L2", "ja", "Berserk", "icon=rage" })
      local listed = text_of(commands.command({ "list", "1" }))
      assert.is_not_nil(listed:find('icon="rage"', 1, true), listed)
      local words = { "bind", "1L3" }
      for word in listed:match("1L2%s+(.-)%s+%["):gmatch("%S+") do
        words[#words + 1] = word
      end
      commands.command(words)
      assert.are.same({ type = "ja", action = "Berserk", icon = "rage" }, stored(world, "SCH", 1, "left", 3))
    end)

    it("lists a chat line carrying quotes so that retyping the row says the same line", function()
      -- The headline of the re-quoting: `record_label` prints the action
      -- unquoted, and re-entry has to put the same quotes back.
      local commands, world = build()
      commands.command({ "bind", "1R1", "ct", "ma", "Cure IV", "<t>", "alias=Cure" })
      local listed = text_of(commands.command({ "list", "1" }))
      local words = { "bind", "1R2" }
      for word in listed:match("1R1%s+(.-)%s+%["):gmatch("%S+") do
        words[#words + 1] = word
      end
      commands.command(words)
      assert.are.same(
        { type = "ct", action = 'ma "Cure IV" <t>', alias = "Cure" },
        stored(world, "SCH", 1, "right", 2),
        table.concat(words, " ")
      )
    end)

    it("lists a labelled chat line so that retyping the row binds the same line", function()
      -- A chat line ends at the marker, so the row needs no quoting of its
      -- own for its labels to read as labels.
      local commands, world = build({ icons = { ["icons/custom/attack.png"] = true } })
      commands.command({ "bind", "1R1", "ct", "p", "pulling", "alias=Pull", "icon=attack" })
      local listed = text_of(commands.command({ "list", "1" }))
      local words = { "bind", "1R2" }
      for word in listed:match("1R1%s+(.-)%s+%["):gmatch("%S+") do
        words[#words + 1] = word
      end
      commands.command(words)
      assert.are.same(
        { type = "ct", action = "p pulling", alias = "Pull", icon = "attack" },
        stored(world, "SCH", 1, "right", 2)
      )
    end)

    it("echoes the alias and the icon it stored", function()
      local commands, world = build({ icons = { ["icons/custom/cure.png"] = true } })
      local reply = commands.command({ "bind", "1L1", "ma", "Cure IV", "p1", "alias=Cure 4", "icon=cure" })
      local told = text_of(reply)
      assert.is_not_nil(told:find('alias="Cure 4"', 1, true), told)
      assert.is_not_nil(told:find('icon="cure"', 1, true), told)
      assert.equal("Cure 4", stored(world, "SCH", 1, "left", 1).alias)
    end)

    it("teaches the form in the help", function()
      local commands = build()
      local told = text_of(commands.command({ "help" }))
      local line = told:match("[^\n]*crossbar bind[^\n]*")
      assert.is_not_nil(line, told)
      assert.is_not_nil(line:find("alias=<name>", 1, true), line)
      assert.is_not_nil(line:find("icon=<name>", 1, true), line)
    end)
  end)

  describe("a trailing word that could be a target", function()
    -- `ws Savage Blade Kevin` reads two ways. Storing the longer one and
    -- reporting success binds a command that can never fire, which is the
    -- one outcome worth refusing over.
    it("refuses when the shorter reading is a real action and the longer is not", function()
      local commands, world = build({ known = { ["Savage Blade"] = true } })
      local reply, _, repaint = commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "Kevin" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("Savage Blade", 1, true), reply)
      assert.is_not_nil(reply:find("Kevin", 1, true), reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("never advises a form the parser also refuses", function()
      -- The refusal used to say "for 'Savage Blade' aimed at Kevin, quote
      -- the name" - and doing exactly that is refused too, leaving no route
      -- at all. Both messages must be terminal: they say what is not
      -- supported and name only readings that work.
      local commands = build({ known = { ["Savage Blade"] = true } })
      local refusal = commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "Kevin" })
      assert.is_string(refusal)
      assert.is_not_nil(refusal:find("not supported yet", 1, true), refusal)
      assert.is_nil(refusal:find("aimed at", 1, true), "it must not send them back to the refused form: " .. refusal)
      --[[ And no longer "quote the whole name": the addon has just
           established that the whole name is NOT an action, and quoting it
           now reaches the parser as one word that binds - a command that can
           never fire. What is left are the two readings that work. ]]
      assert.is_nil(refusal:find("quote the whole name", 1, true), refusal)
      assert.is_not_nil(refusal:find("a10-a15", 1, true), refusal)
      assert.is_not_nil(refusal:find('alias="Kevin"', 1, true), refusal)
    end)

    it("takes the whole phrase when that is what the client knows", function()
      local commands, world = build({ known = { ["Ascetic's Fury"] = true } })
      local reply = commands.command({ "bind", "1L3", "ws", "Ascetic's", "Fury" })
      assert.is_string(reply, "a name the client knows needs no caution")
      assert.equal("Ascetic's Fury", stored(world, "SCH", 1, "left", 3).action)
    end)

    it("takes a quoted name whole without asking the client anything", function()
      local commands, world = build({ known = { ["Savage Blade"] = true } })
      local reply = commands.command({ "bind", "1L3", "ws", '"Savage', "Blade", 'Kevin"' })
      assert.is_string(reply)
      assert.equal("Savage Blade Kevin", stored(world, "SCH", 1, "left", 3).action)
      assert.are.same({}, world.asked, "the quotes settled it")
    end)

    it("keeps both readings out of it when neither resolves", function()
      local commands, world = build({ known = {} })
      commands.command({ "bind", "1L3", "ws", "Made", "Up" })
      assert.equal("Made Up", stored(world, "SCH", 1, "left", 3).action)
    end)

    it("binds but says so when it cannot tell", function()
      -- The degraded client as the widget really presents it: the dep is
      -- wired and answers nil, because there is no resources library to
      -- ask. A nil is "cannot verify", NOT "not an action" - reading it as
      -- the latter is what made this caution unreachable in production.
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "Kevin" })
      assert.is_table(reply, "the caution needs its own line")
      assert.is_true(repaint)
      assert.equal("Savage Blade Kevin", stored(world, "SCH", 1, "left", 3).action)
      local text = text_of(reply)
      assert.is_not_nil(text:find("Kevin", 1, true), text)
      assert.is_not_nil(text:lower():find("quote"), text)
    end)

    it("says nothing extra when the trailing word is a target token", function()
      local commands = build()
      local reply = commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "t" })
      assert.is_string(reply)
    end)
  end)

  describe("unbind", function()
    it("clears the addressed layer only", function()
      local commands, world = build({ sub = "NIN" })
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "bind", "sub:1L3", "ja", "Provoke" })
      local reply, save_config, repaint = commands.command({ "unbind", "sub:1L3" })
      assert.is_string(reply)
      assert.is_falsy(save_config)
      assert.is_true(repaint)
      assert.equal("Savage Blade", world.bindings.resolve(1, "left", 3).action)
      assert.is_nil(world.bindings.entry_at("sub:1", "l", 3))
    end)

    it("says so when the address was already empty, and writes nothing", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "unbind", "1L3" })
      assert.is_string(reply)
      assert.is_not_nil(reply:lower():find("nothing"), reply)
      assert.is_falsy(repaint)
      assert.are.same({}, world.saved)
    end)

    it("hints on wrong arity and a bad address", function()
      local commands = build()
      local cases = { { "unbind" }, { "unbind", "1" }, { "unbind", "1", "l" }, { "unbind", "9L1" } }
      for _, words in ipairs(cases) do
        local reply, _, repaint = commands.command(words)
        assert.is_string(reply, #words .. " words")
        assert.is_falsy(repaint, #words .. " words")
      end
    end)

    it("refuses before a job is scoped", function()
      local commands, world = build({ job = false })
      local reply, _, repaint = commands.command({ "unbind", "1L3" })
      assert.is_not_nil(reply:find("job"), reply)
      assert.is_falsy(repaint)
      assert.are.same({}, world.saved)
    end)
  end)

  describe("alias", function()
    it("relabels the addressed entry and nothing else about it", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "t" })
      local reply, save_config, repaint = commands.command({ "alias", "1L3", "Big", "Hit" })
      assert.is_string(reply)
      assert.is_falsy(save_config)
      assert.is_true(repaint)
      assert.are.same(
        { type = "ws", action = "Savage Blade", target = "t", alias = "Big Hit" },
        stored(world, "SCH", 1, "left", 3)
      )
      assert.are.equal(2, world.saved.SCH, "the bind, then the alias - both written")
    end)

    it("keeps an unbalanced quote in the name, as bind does", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "alias", "1L3", '"Big', "Hit" })
      assert.equal('"Big Hit', stored(world, "SCH", 1, "left", 3).alias)
    end)

    it("clears the override when the name is omitted", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "alias", "1L3", "Big", "Hit" })
      commands.command({ "alias", "1L3" })
      assert.are.same({ type = "ws", action = "Savage Blade" }, stored(world, "SCH", 1, "left", 3))
    end)

    it("follows the layer prefixes", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "bind", "ctx:light-arts:1L3", "ja", "Addendum:", "White" })
      commands.command({ "alias", "ctx:light-arts:1L3", "AW" })
      assert.equal("AW", world.files.SCH.contexts["light-arts"][1].left[3].alias)
      assert.is_nil(stored(world, "SCH", 1, "left", 3).alias, "the base entry is untouched")
    end)

    it("refuses an empty slot rather than carrying the label nowhere", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "alias", "1L3", "Big", "Hit" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.are.same({}, world.saved)
    end)

    it("hints on wrong arity, a bad address and no job", function()
      local commands = build()
      for _, words in ipairs({ { "alias" }, { "alias", "1" }, { "alias", "1", "l" }, { "alias", "1L9" } }) do
        assert.is_string(commands.command(words), #words .. " words")
      end
      local unscoped = build({ job = false })
      local reply = unscoped.command({ "alias", "1L3", "Name" })
      assert.is_not_nil(reply:find("job"), reply)
    end)
  end)

  describe("icon", function()
    it("resolves the player's own art ahead of the shipped pack", function()
      local commands, world = build({ icons = { ["icons/custom/attack.png"] = true } })
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      local reply, save_config, repaint = commands.command({ "icon", "1L3", "attack" })
      assert.is_string(reply)
      assert.is_falsy(save_config)
      assert.is_true(repaint)
      assert.equal("attack", stored(world, "SCH", 1, "left", 3).icon)
      assert.are.equal(2, world.saved.SCH, "the bind, then the icon - both written")
      assert.equal("icons/custom/attack.png", world.stats[1], "custom art is stat'd first")
    end)

    it("accepts a pack-relative name from the shipped pack", function()
      local commands, world = build({ icons = { ["assets/icons/items/warp-ring.png"] = true } })
      commands.command({ "bind", "1L3", "warp" })
      commands.command({ "icon", "1L3", "items/warp-ring" })
      assert.equal("items/warp-ring", stored(world, "SCH", 1, "left", 3).icon)
    end)

    it("takes a quoted name with a space in it", function()
      local commands, world = build({ icons = { ["icons/custom/my pull.png"] = true } })
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "icon", "1L3", '"my', 'pull"' })
      assert.equal("my pull", stored(world, "SCH", 1, "left", 3).icon)
    end)

    it("finds custom art for a pack-relative name by its basename", function()
      -- render.icon_candidates looks for icons/custom/<basename>.png, so
      -- accepting the name here has to use the same flattening or the
      -- verb refuses art the bar would happily draw.
      local commands, world = build({ icons = { ["icons/custom/warp-ring.png"] = true } })
      commands.command({ "bind", "1L3", "warp" })
      local reply, _, repaint = commands.command({ "icon", "1L3", "items/warp-ring" })
      assert.is_string(reply)
      assert.is_true(repaint)
      assert.equal("items/warp-ring", stored(world, "SCH", 1, "left", 3).icon)
    end)

    it("names the path it actually probed when it refuses", function()
      local commands = build()
      commands.command({ "bind", "1L3", "warp" })
      local reply = commands.command({ "icon", "1L3", "items/warp-ring" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("icons/custom/warp-ring.png", 1, true), reply)
      assert.is_nil(reply:find("icons/custom/items/", 1, true), "that path is never looked at: " .. reply)
    end)

    it("refuses an icon name with no file name in it", function()
      local commands = build()
      commands.command({ "bind", "1L3", "warp" })
      local reply, _, repaint = commands.command({ "icon", "1L3", "items/" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(reply:find("//.png", 1, true), "never name a path with an empty file name: " .. reply)
      assert.is_nil(reply:find("items/.png", 1, true), reply)
    end)

    it("rejects a name no art answers to", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      local reply, _, repaint = commands.command({ "icon", "1L3", "nosuchart" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3).icon)
    end)

    it("clears the override when the name is omitted", function()
      local commands, world = build({ icons = { ["icons/custom/attack.png"] = true } })
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "icon", "1L3", "attack" })
      commands.command({ "icon", "1L3" })
      assert.are.same({ type = "ws", action = "Savage Blade" }, stored(world, "SCH", 1, "left", 3))
    end)

    it("refuses an empty slot, a bad address, wrong arity and no job", function()
      local commands, world = build({ icons = { ["icons/custom/attack.png"] = true } })
      local reply = commands.command({ "icon", "1L3", "attack" })
      assert.is_string(reply)
      assert.are.same({}, world.saved)
      for _, words in ipairs({ { "icon" }, { "icon", "1" }, { "icon", "1", "l" }, { "icon", "9L1" } }) do
        assert.is_string(commands.command(words), #words .. " words")
      end
      local unscoped = build({ job = false })
      assert.is_not_nil(unscoped.command({ "icon", "1L3", "attack" }):find("job"))
    end)

    it("takes one name, not a phrase", function()
      local commands, world = build({ icons = { ["icons/custom/attack.png"] = true } })
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      local reply, _, repaint = commands.command({ "icon", "1L3", "attack", "please" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3).icon)
    end)
  end)

  describe("swap", function()
    it("exchanges two addresses' entire stacks", function()
      local commands, world = build({ sub = "NIN" })
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "bind", "sub:1L3", "ja", "Provoke" })
      commands.command({ "bind", "2R5", "ma", "Cure" })
      local reply, save_config, repaint = commands.command({ "swap", "1L3", "2R5" })
      assert.is_string(reply)
      assert.is_falsy(save_config)
      assert.is_true(repaint)
      assert.equal("Cure", world.bindings.entry_at(1, "l", 3).action)
      assert.equal("Savage Blade", world.bindings.entry_at(2, "r", 5).action)
      assert.equal("Provoke", world.bindings.entry_at("sub:2", "r", 5).action, "the subjob layer moved too")
      assert.is_nil(world.bindings.entry_at("sub:1", "l", 3))
    end)

    it("takes the button names on both addresses", function()
      local commands, world = build()
      commands.command({ "bind", "1L1", "ja", "Provoke" })
      commands.command({ "swap", "1L1", "1R7" })
      assert.equal("Provoke", world.bindings.entry_at(1, "r", 7).action)
      assert.is_nil(world.bindings.entry_at(1, "l", 1))
    end)

    it("moves a stack onto an empty address", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "swap", "1L3", "4R2" })
      assert.equal("Savage Blade", world.bindings.entry_at(4, "r", 2).action)
      assert.is_nil(world.bindings.entry_at(1, "l", 3))
    end)

    it("refuses a layer prefix - a swap moves every layer at once", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      local reply, _, repaint = commands.command({ "swap", "sub:1L3", "2R5" })
      assert.is_string(reply)
      assert.is_not_nil(reply:lower():find("layer"), reply)
      assert.is_falsy(repaint)
      assert.equal("Savage Blade", world.bindings.entry_at(1, "l", 3).action)
    end)

    it("hints on wrong arity, a bad address and no job", function()
      local commands = build()
      local cases = {
        { "swap" },
        { "swap", "1L3" },
        { "swap", "1L3", "2", "r" },
        { "swap", "1L3", "9R5" },
        { "swap", "1L3", "2", "x", "5" },
        { "swap", "1", "l", "middle", "2R5" },
      }
      for index, words in ipairs(cases) do
        local reply, _, repaint = commands.command(words)
        assert.is_string(reply, "case " .. index)
        assert.is_falsy(repaint, "case " .. index)
      end
      local unscoped, world = build({ job = false })
      local reply = unscoped.command({ "swap", "1L3", "2R5" })
      assert.is_not_nil(reply:find("job"), reply)
      assert.are.same({}, world.saved)
    end)
  end)

  describe("list", function()
    it("lists what each set holds, with its layer and the active marker", function()
      local commands, world = build({ sub = "NIN" })
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "t" })
      commands.command({ "bind", "sub:1R1", "ja", "Provoke" })
      commands.command({ "bind", "5L8", "ma", "Cure", "IV", "p1" })
      local reply, save_config, repaint = commands.command({ "list" })
      assert.is_table(reply)
      assert.is_falsy(save_config)
      assert.is_falsy(repaint)
      local text = text_of(reply)
      assert.is_not_nil(text:find("SCH/NIN", 1, true), text)
      assert.is_not_nil(text:find("Savage Blade", 1, true), text)
      assert.is_not_nil(text:find("Cure IV", 1, true), text)
      assert.is_not_nil(text:find("sub", 1, true), "the subjob layer is tagged: " .. text)
      assert.is_not_nil(text:find("set 1", 1, true), text)
      assert.is_not_nil(text:find("set 5", 1, true), text)
      assert.is_not_nil(text:find("active", 1, true), "the active set is marked: " .. text)
      assert.equal(world.bindings.active_set(), 1)
    end)

    it("shows a context layer that no buff is holding up", function()
      -- The only inspection verb must not report a successful write as a
      -- no-op: an unbuffed context layer is stored, tagged, and simply not
      -- winning.
      local commands = build()
      commands.command({ "bind", "ctx:light-arts:1L3", "ja", "Penury" })
      local text = text_of(commands.command({ "list" }))
      assert.is_not_nil(text:find("Penury", 1, true), text)
      assert.is_not_nil(text:find("[ctx:light-arts]", 1, true), text)
    end)

    it("shows a subjob layer belonging to a subjob that is not worn", function()
      local commands, world = build({ sub = "NIN" })
      commands.command({ "bind", "sub:1L4", "ja", "Utsusemi" })
      world.bindings.set_job("SCH", "WHM")
      local text = text_of(commands.command({ "list" }))
      assert.is_not_nil(text:find("Utsusemi", 1, true), text)
      assert.is_not_nil(text:find("[sub:NIN]", 1, true), text)
    end)

    it("marks which layer is live when an address has more than one", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "bind", "ctx:light-arts:1L3", "ja", "Penury" })
      local lines = commands.command({ "list", "1" })
      local base_row, ctx_row
      for _, line in ipairs(lines) do
        if line:find("Savage Blade", 1, true) then
          base_row = line
        elseif line:find("Penury", 1, true) then
          ctx_row = line
        end
      end
      assert.is_not_nil(base_row)
      assert.is_not_nil(ctx_row)
      assert.is_not_nil(base_row:find("live", 1, true), "the base wins with no buff up: " .. base_row)
      assert.is_nil(ctx_row:find("live", 1, true), ctx_row)
      world.bindings.update_buffs({ 358 })
      local text = text_of(commands.command({ "list", "1" }))
      for _, line in ipairs(commands.command({ "list", "1" })) do
        if line:find("Penury", 1, true) then
          assert.is_not_nil(line:find("live", 1, true), "Light Arts up: " .. text)
        end
      end
    end)

    it("leaves a single-layer address unmarked", function()
      local commands = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      local text = text_of(commands.command({ "list", "1" }))
      assert.is_nil(text:find("live", 1, true), text)
    end)

    it("restricts to one set and says when it is empty", function()
      local commands = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      local text = text_of(commands.command({ "list", "2" }))
      assert.is_nil(text:find("Savage Blade", 1, true), text)
      assert.is_not_nil(text:lower():find("nothing"), text)
    end)

    it("shows a slot's alias beside its action", function()
      local commands = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "alias", "1L3", "Big Hit" })
      local text = text_of(commands.command({ "list", "1" }))
      assert.is_not_nil(text:find("Big Hit", 1, true), text)
      assert.is_not_nil(text:find("Savage Blade", 1, true), text)
    end)

    it("names each row by its address, and by nothing else", function()
      --[[ The rows used to read `l 5 up   ja Provoke`, naming the D-pad
           button the slot would be on a controller. There is no controller
           - Windower cannot see one - so the name only invited the question
           of which pad was meant (Kevin, 2026-08-22). One address word now,
           the same one you would type back. ]]
      local commands = build()
      commands.command({ "bind", "1L5", "ja", "Provoke" })
      local text = text_of(commands.command({ "list", "1" }))
      assert.is_not_nil(text:find("1L5", 1, true), text)
      assert.is_nil(text:find("up", 1, true), "no button names: " .. text)
    end)

    it("survives a hand-broken entry rather than crashing the handler", function()
      -- The binding files are hand-editable and the model only guarantees
      -- that an entry is a table; a wrong-typed field must not throw in a
      -- command handler.
      local commands = build({
        files = { SCH = { sets = { [1] = { left = { [2] = { type = {}, action = 42, alias = true } } } } } },
      })
      local reply
      assert.has_no.errors(function()
        reply = commands.command({ "list" })
      end)
      assert.is_table(reply)
    end)

    it("reports an empty job rather than an empty reply", function()
      local commands = build()
      local text = text_of(commands.command({ "list" }))
      assert.is_not_nil(text:lower():find("nothing"), text)
    end)

    it("hints on a bad set and before a job is scoped", function()
      local commands = build()
      assert.is_string(commands.command({ "list", "9" }))
      local prefixed = commands.command({ "list", "sub:1" })
      assert.is_string(prefixed)
      assert.is_not_nil(prefixed:lower():find("layer"), prefixed)
      local unscoped = build({ job = false })
      local reply = unscoped.command({ "list" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("job"), reply)
    end)
  end)

  describe("view", function()
    it("repoints a view and asks for a config save", function()
      local commands, world = build()
      local reply, save_config, repaint = commands.command({ "view", "wxhb-L", "5R" })
      assert.is_string(reply)
      assert.is_true(save_config)
      assert.is_true(repaint)
      assert.are.same({ set = 5, side = "right" }, world.config.views.wxhb_left)
    end)

    it("knows all four views, case-insensitively", function()
      local commands, world = build()
      -- The view name and the side both fold: upper case is what the help
      -- and the echo show, not what the parser demands.
      commands.command({ "view", "WXHB-R", "4l" })
      commands.command({ "view", "exp-lr", "6R" })
      commands.command({ "view", "EXP-RL", "7L" })
      assert.are.same({ set = 4, side = "left" }, world.config.views.wxhb_right)
      assert.are.same({ set = 6, side = "right" }, world.config.views.expanded_lr)
      assert.are.same({ set = 7, side = "left" }, world.config.views.expanded_rl)
    end)

    it("rebuilds a views table the config lost", function()
      local commands, world = build()
      world.config.views = nil
      commands.command({ "view", "wxhb-L", "2L" })
      assert.are.same({ set = 2, side = "left" }, world.config.views.wxhb_left)
    end)

    it("hints on an unknown view, a bad set, a bad side and wrong arity", function()
      local commands, world = build()
      local cases = {
        { "view" },
        { "view", "wxhb-L" },
        -- The side is not optional: a bare set is not an address.
        { "view", "wxhb-L", "2" },
        { "view", "bogus", "2L" },
        { "view", "wxhb-L", "9L" },
        { "view", "wxhb-L", "2X" },
        -- And the slot belongs to a bind, not to a view.
        { "view", "wxhb-L", "2L3" },
        { "view", "wxhb-L", "2L", "3" },
      }
      for index, words in ipairs(cases) do
        local reply, save_config = commands.command(words)
        assert.is_string(reply, "case " .. index)
        assert.is_falsy(save_config, "case " .. index)
      end
      assert.are.same({ set = 2, side = "left" }, world.config.views.wxhb_left, "nothing moved")
    end)
  end)

  describe("share", function()
    it("flips a set between shared and job-specific", function()
      local commands, world = build()
      local reply, save_config, repaint = commands.command({ "share", "6", "on" })
      assert.is_string(reply)
      assert.is_true(save_config)
      assert.is_true(repaint)
      assert.is_true(world.config.set_flags[6].shared)
      commands.command({ "share", "6", "OFF" })
      assert.is_false(world.config.set_flags[6].shared)
    end)

    it("gives its grammar when the switch is missing entirely", function()
      local commands = build()
      local reply = commands.command({ "share" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("on|off", 1, true), reply)
    end)

    it("says the job's own bindings go dormant when a populated set is shared", function()
      local commands, world = build()
      commands.command({ "bind", "4L1", "ja", "Provoke" })
      local reply = commands.command({ "share", "4", "on" })
      assert.is_table(reply, "the warning needs its own line")
      local text = text_of(reply)
      assert.is_not_nil(text:lower():find("dormant"), text)
      assert.equal("Provoke", world.files.SCH.sets[4].left[1].action, "and they really do stay in the file")
      -- An empty set has nothing to lose, so it says nothing extra.
      assert.is_string(commands.command({ "share", "5", "on" }))
    end)

    it("builds the flags entry the config never had", function()
      local commands, world = build({ set_flags = {} })
      commands.command({ "share", "3", "on" })
      assert.is_true(world.config.set_flags[3].shared)
    end)

    it("says why a layer prefix does not belong on a set-wide verb", function()
      local commands = build()
      for _, words in ipairs({ { "share", "sub:1", "on" }, { "cycle", "ctx:light-arts:1", "drawn" } }) do
        local reply, save_config = commands.command(words)
        assert.is_string(reply, words[1])
        assert.is_not_nil(reply:lower():find("layer"), words[1] .. ": " .. reply)
        assert.is_falsy(save_config, words[1])
      end
      local reply = commands.command({ "view", "wxhb-L", "sub:1L" })
      assert.is_not_nil(reply:lower():find("layer"), reply)
    end)

    it("hints on a bad set, a missing switch and garbage", function()
      local commands, world = build()
      for _, words in ipairs({ { "share" }, { "share", "6" }, { "share", "9", "on" }, { "share", "6", "maybe" } }) do
        local reply, save_config = commands.command(words)
        assert.is_string(reply, #words .. " words")
        assert.is_falsy(save_config, #words .. " words")
      end
      assert.is_false(world.config.set_flags[6].shared)
    end)
  end)

  describe("cycle with arguments", function()
    it("sets rotation membership per weapon state", function()
      local commands, world = build()
      local reply, save_config, repaint = commands.command({ "cycle", "2", "drawn" })
      assert.is_string(reply)
      assert.is_true(save_config)
      assert.is_true(repaint)
      assert.are.same({ drawn = true, sheathed = false }, world.config.set_flags[2].cycle)
      commands.command({ "cycle", "2", "sheathed" })
      assert.are.same({ drawn = false, sheathed = true }, world.config.set_flags[2].cycle)
      commands.command({ "cycle", "2", "BOTH" })
      assert.are.same({ drawn = true, sheathed = true }, world.config.set_flags[2].cycle)
      commands.command({ "cycle", "2", "none" })
      assert.are.same({ drawn = false, sheathed = false }, world.config.set_flags[2].cycle)
    end)

    it("takes the set out of the live rotation at once", function()
      local commands, world = build()
      world.bindings.bind(2, "l", 1, { type = "ja", action = "Provoke" })
      world.bindings.bind(3, "l", 1, { type = "ja", action = "Berserk" })
      commands.command({ "cycle", "2", "none" })
      assert.equal(3, world.bindings.cycle(), "set 2 is out of the rotation")
    end)

    it("hints on a bad set and an unknown mode, without advancing anything", function()
      local commands, world = build()
      for _, words in ipairs({ { "cycle", "9", "drawn" }, { "cycle", "2", "sometimes" }, { "cycle", "2" } }) do
        local reply, save_config = commands.command(words)
        assert.is_string(reply, words[3] or "bare set")
        assert.is_falsy(save_config, words[3] or "bare set")
      end
      assert.equal(1, world.bindings.active_set())
      assert.are.same({ drawn = true, sheathed = true }, world.config.set_flags[2].cycle)
    end)
  end)

  describe("wxhb", function()
    it("reports the current setting with no argument", function()
      local commands, world = build()
      local reply, save_config = commands.command({ "wxhb" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("off"), reply)
      assert.is_falsy(save_config)
      assert.is_false(world.config.always_show_wxhb)
    end)

    it("turns the resting WXHB on and off", function()
      local commands, world = build()
      local reply, save_config, repaint = commands.command({ "wxhb", "on" })
      assert.is_string(reply)
      assert.is_true(save_config)
      assert.is_true(repaint)
      assert.is_true(world.config.always_show_wxhb)
      local reported = commands.command({ "wxhb" })
      assert.is_not_nil(reported:find("on", 1, true), "bare wxhb reports what is set: " .. reported)
      commands.command({ "wxhb", "OFF" })
      assert.is_false(world.config.always_show_wxhb)
      reported = commands.command({ "wxhb" })
      assert.is_not_nil(reported:find("off", 1, true), reported)
    end)

    it("hints on anything else", function()
      local commands, world = build()
      local reply, save_config = commands.command({ "wxhb", "maybe" })
      assert.is_string(reply)
      assert.is_falsy(save_config)
      assert.is_false(world.config.always_show_wxhb)
    end)
  end)

  describe("retry", function()
    it("reports the current setting with no argument", function()
      local commands, world = build()
      -- The fixture config carries no retry block at all, which is the
      -- shape a config written before the feature existed has: it reports
      -- off rather than throwing, and writes nothing to say so.
      local reply, save_config = commands.command({ "retry" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("off", 1, true), reply)
      assert.is_falsy(save_config)
      assert.is_nil(world.config.retry)
    end)

    it("turns the cast retry on and off", function()
      local commands, world = build()
      local reply, save_config = commands.command({ "retry", "on" })
      assert.is_string(reply)
      assert.is_true(save_config)
      assert.is_true(world.config.retry.enabled)
      local reported = commands.command({ "retry" })
      assert.is_not_nil(reported:find("on", 1, true), reported)
      commands.command({ "retry", "OFF" })
      assert.is_false(world.config.retry.enabled)
      reported = commands.command({ "retry" })
      assert.is_not_nil(reported:find("off", 1, true), reported)
    end)

    it("leaves the tuning alone when it flips the switch", function()
      local commands, world = build()
      world.config.retry = { enabled = false, window = 2, backoff = 1.5, deadline = 5, attempts = 3 }
      commands.command({ "retry", "on" })
      assert.is_true(world.config.retry.enabled)
      assert.equal(1.5, world.config.retry.backoff, "the in-client tuning is not reset by the switch")
      assert.equal(3, world.config.retry.attempts)
    end)

    it("rebuilds a retry block the config lost", function()
      local commands, world = build()
      world.config.retry = "yes"
      commands.command({ "retry", "on" })
      assert.is_true(world.config.retry.enabled)
    end)

    it("hints on anything else", function()
      local commands, world = build()
      local reply, save_config = commands.command({ "retry", "sometimes" })
      assert.is_string(reply)
      assert.is_falsy(save_config)
      assert.is_nil(world.config.retry)
      local over, over_save = commands.command({ "retry", "on", "please" })
      assert.is_string(over)
      assert.is_falsy(over_save)
      assert.is_nil(world.config.retry)
    end)
  end)

  describe("copy", function()
    it("seeds this job's bindings from another job's file", function()
      local commands, world = build({
        files = { WAR = { sets = { [1] = { left = { [2] = { type = "ws", action = "Upheaval" } } } } } },
      })
      local reply, save_config, repaint = commands.command({ "copy", "war" })
      assert.is_string(reply)
      assert.is_falsy(save_config)
      assert.is_true(repaint)
      assert.equal("Upheaval", world.bindings.resolve(1, "left", 2).action)
      assert.equal("Upheaval", stored(world, "SCH", 1, "left", 2).action)
      assert.is_nil(stored(world, "WAR", 1, "left", 2).alias, "the source file is untouched")
    end)

    it("says the previous bindings were replaced", function()
      local commands = build({
        files = { WAR = { sets = { [1] = { left = { [2] = { type = "ws", action = "Upheaval" } } } } } },
      })
      local reply = commands.command({ "copy", "war" })
      assert.is_string(reply)
      assert.is_not_nil(reply:lower():find("replaced"), reply)
    end)

    it("refuses to copy from the shared store, whatever the case", function()
      -- SHARED.lua type-checks as a job file, so copying from it would
      -- overwrite this job's base, subjob and context layers with a table
      -- that only ever holds `sets` - the job's bindings, destroyed.
      local commands, world = build({
        files = {
          SCH = { sets = { [1] = { left = { [1] = { type = "ja", action = "Penury" } } } } },
          SHARED = { sets = { [6] = { left = { [1] = { type = "ja", action = "Provoke" } } } } },
        },
      })
      for _, name in ipairs({ "SHARED", "shared", "Shared" }) do
        local reply, _, repaint = commands.command({ "copy", name })
        assert.is_string(reply, name)
        assert.is_falsy(repaint, name)
      end
      assert.equal("Penury", stored(world, "SCH", 1, "left", 1).action, "the job kept its own bindings")
      assert.is_nil(world.saved.SCH)
    end)

    it("refuses to copy a job onto itself", function()
      local commands, world = build({
        files = { SCH = { sets = { [1] = { left = { [1] = { type = "ja", action = "Penury" } } } } } },
      })
      local reply, _, repaint = commands.command({ "copy", "sch" })
      assert.is_string(reply)
      assert.is_not_nil(reply:lower():find("already"), reply)
      assert.is_falsy(repaint)
      assert.is_nil(world.saved.SCH)
    end)

    it("hints on a job with no file, wrong arity and no job scoped", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "copy", "BLM" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_string(commands.command({ "copy" }))
      assert.are.same({}, world.saved)
      local unscoped = build({ files = { WAR = { sets = {} } }, job = false })
      assert.is_not_nil(unscoped.command({ "copy", "WAR" }):find("job"))
    end)
  end)

  describe("context", function()
    it("lists the roster in stack order with the active ones marked", function()
      local commands, world = build()
      world.bindings.update_buffs({ 401 })
      local reply, save_config, repaint = commands.command({ "context", "list" })
      assert.is_table(reply)
      assert.is_falsy(save_config)
      assert.is_falsy(repaint)
      local text = text_of(reply)
      for _, name in ipairs({ "light-arts", "dark-arts", "addendum-white", "addendum-black" }) do
        assert.is_not_nil(text:find(name, 1, true), name .. " missing: " .. text)
      end
      assert.is_true(text:find("light%-arts") < text:find("addendum%-white"), "roster order: " .. text)
      local lines = reply
      local marked = {}
      for _, line in ipairs(lines) do
        if line:find("active", 1, true) then
          marked[#marked + 1] = line
        end
      end
      assert.equal(2, #marked, "Addendum: White implies Light Arts: " .. text)
    end)

    --[[ The gate (Kevin, 2026-09-04): a context follows the job whose buff
         it watches, and listing one the player cannot raise is an invitation
         to bind into a layer that can never fire. ]]
    it("lists only the contexts the scoped job can reach", function()
      local commands = build()
      local text = text_of(commands.command({ "context", "list" }))
      assert.is_nil(text:find("unbridled", 1, true), "a BLU context on SCH: " .. text)
    end)

    it("lists a BLU main job's own context and none of the arts", function()
      local commands = build({ job = "BLU", sub = "WAR" })
      local text = text_of(commands.command({ "context", "list" }))
      assert.is_not_nil(text:find("unbridled", 1, true), text)
      assert.is_nil(text:find("light-arts", 1, true), text)
    end)

    it("says so plainly on a job with no context at all", function()
      local commands = build({ job = "WAR", sub = "NIN" })
      local reply = commands.command({ "context", "list" })
      local text = text_of(reply)
      assert.is_not_nil(text:find("WAR", 1, true), text)
      assert.is_nil(text:find("light-arts", 1, true), text)
    end)

    -- Character select: `handle_command` routes whether or not a job is
    -- scoped, and every other unscoped path has a case of its own.
    it("says there is no job yet rather than naming one", function()
      local commands = build({ job = false })
      local text = text_of(commands.command({ "context", "list" }))
      assert.is_not_nil(text:find("no job", 1, true), text)
      assert.is_nil(text:find("light-arts", 1, true), text)
    end)

    it("lists bare and hints on an unknown subverb", function()
      local commands = build()
      assert.is_table(commands.command({ "context" }))
      assert.is_string(commands.command({ "context", "bogus" }))
    end)
  end)

  describe("without a job scoped", function()
    -- Only the store writers need a job: the component config is
    -- character-wide, and the context roster is code.
    it("answers the config and inspection verbs anyway", function()
      local commands, world = build({ job = false })
      local cases = {
        { { "wxhb", "on" }, true },
        { { "view", "wxhb-L", "4R" }, true },
        { { "share", "2", "on" }, true },
        { { "cycle", "2", "drawn" }, true },
        { { "context", "list" }, false },
        { { "help" }, false },
      }
      for _, case in ipairs(cases) do
        local reply, save_config = commands.command(case[1])
        assert.is_truthy(reply, case[1][1])
        assert.are.equal(case[2], save_config == true, case[1][1])
      end
      assert.is_true(world.config.always_show_wxhb)
      assert.are.same({}, world.saved, "no binding file was written")
    end)
  end)

  describe("quoting", function()
    -- The wiki teaches quotes for a name with a space, and a user who
    -- quotes one that has none must not get the quotes stored as the label.
    it("strips the quotes off an alias and an icon name", function()
      local commands, world = build({ icons = { ["icons/custom/pull.png"] = true } })
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      commands.command({ "alias", "1L3", '"AW"' })
      assert.equal("AW", stored(world, "SCH", 1, "left", 3).alias)
      commands.command({ "alias", "1L3", '"Big', 'Hit"' })
      assert.equal("Big Hit", stored(world, "SCH", 1, "left", 3).alias)
      commands.command({ "icon", "1L3", '"pull"' })
      assert.equal("pull", stored(world, "SCH", 1, "left", 3).icon)
    end)
  end)

  describe("the subjob layer with no subjob", function()
    it("hints rather than writing a nil-named layer", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "sub:1L3", "ja", "Provoke" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.are.same({}, world.saved)
    end)
  end)

  describe("built-in name collisions", function()
    it("names its verbs for the load-time collision check", function()
      local commands = build()
      local verbs = commands.verbs()
      assert.is_table(verbs)
      local seen = {}
      for _, verb in ipairs(verbs) do
        seen[verb] = true
      end
      for _, verb in ipairs({ "bind", "unbind", "alias", "icon", "swap", "list", "view", "share" }) do
        assert.is_true(seen[verb], verb)
      end
      assert.is_true(#verbs >= 13, "every verb, not a sample")
      local sorted = true
      for index = 2, #verbs do
        sorted = sorted and verbs[index - 1] < verbs[index]
      end
      assert.is_true(sorted, "sorted, so a report reads the same twice")
    end)
  end)

  describe("the verb surface", function()
    -- The widget routes on this rather than keeping a second list of the
    -- verbs; a verb added here must never need adding there too.
    it("names exactly the verbs it answers", function()
      local commands = build()
      for _, verb in ipairs({
        "bind",
        "unbind",
        "alias",
        "icon",
        "swap",
        "list",
        "view",
        "share",
        "cycle",
        "wxhb",
        "retry",
        "copy",
        "context",
        "help",
      }) do
        assert.is_true(commands.handles(verb), verb)
        assert.is_true(commands.handles(verb:upper()), verb .. " folded")
      end
      for _, verb in ipairs({ "set", "open", "edit", "draw", "mr", "warp", "bogus", "" }) do
        assert.is_false(commands.handles(verb), verb)
      end
      assert.is_false(commands.handles(nil))
    end)
  end)

  describe("case folding", function()
    it("takes an upper-case layer prefix", function()
      local commands, world = build({ sub = "NIN" })
      assert.is_true(select(3, commands.command({ "bind", "SUB:1L3", "ja", "Utsusemi" })), "sub:")
      assert.equal("Utsusemi", world.files.SCH.sub.NIN[1].left[3].action)
      assert.is_true(select(3, commands.command({ "bind", "CTX:Light-Arts:1L3", "ja", "Addendum:", "White" })), "ctx:")
      assert.equal("Addendum: White", world.files.SCH.contexts["light-arts"][1].left[3].action)
      commands.command({ "bind", "SUB:1L3", "ja", "Utsusemi" })
      assert.is_true(select(3, commands.command({ "alias", "SUB:1L3", "Shadows" })), "alias")
      assert.equal("Shadows", world.files.SCH.sub.NIN[1].left[3].alias)
      assert.is_true(select(3, commands.command({ "unbind", "SUB:1L3" })), "unbind")
    end)

    -- The framework folds verbs and names everywhere; the side argument is
    -- a name like any other, and an error saying "side must be l or r" to
    -- someone who typed L is worse than useless.
    it("takes either case of side on every address", function()
      local commands, world = build()
      assert.is_true(select(3, commands.command({ "bind", "1L3", "ja", "Provoke" })), "bind")
      -- Upper case is what the help shows, not what the parser demands.
      assert.is_true(select(3, commands.command({ "alias", "1l3", "Poke" })), "alias")
      assert.equal("Poke", stored(world, "SCH", 1, "left", 3).alias)
      assert.is_true(select(3, commands.command({ "swap", "1L3", "2R5" })), "swap")
      assert.equal("Provoke", world.bindings.entry_at(2, "r", 5).action)
      assert.is_true(select(3, commands.command({ "unbind", "2R5" })), "unbind")
      assert.is_nil(world.bindings.entry_at(2, "r", 5))
    end)
  end)

  describe("what the replies say", function()
    --[[ The confirmation is the only thing the user sees, so it is pinned.
         It used to name the controller button the slot would be - `set 1 l
         3 (a)` - which named a pad the addon cannot see, and spelt the side
         in the lower case that is the whole reason the address changed
         (Kevin, 2026-08-22). It echoes the address instead: the same word
         you would type back. ]]
    it("echoes the address itself, in the form you would type it", function()
      local commands = build()
      local reply = commands.command({ "bind", "1L3", "ja", "Provoke" })
      assert.is_not_nil(reply:find("1L3", 1, true), reply)
      assert.is_nil(reply:find("(a)", 1, true), "no button name: " .. reply)
      reply = commands.command({ "bind", "1R5", "ja", "Berserk" })
      assert.is_not_nil(reply:find("1R5", 1, true), reply)
      -- Either case in, upper case out.
      reply = commands.command({ "bind", "1r6", "ja", "Berserk" })
      assert.is_not_nil(reply:find("1R6", 1, true), reply)
    end)

    it("shows the target it bound, in the confirmation and in the listing", function()
      local commands = build()
      local reply = commands.command({ "bind", "1L3", "ws", "Savage", "Blade", "t" })
      assert.is_not_nil(reply:find("ws Savage Blade <t>", 1, true), reply)
      local text = text_of(commands.command({ "list", "1" }))
      assert.is_not_nil(text:find("ws Savage Blade <t>", 1, true), text)
    end)
  end)

  describe("trailing junk", function()
    -- The framework hints on anything it does not understand rather than
    -- ignoring it: a word the parser drops is a word the user believed in.
    it("refuses extra words on every fixed-arity verb", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage Blade" })
      local cases = {
        { "unbind", "1L3", "please" },
        { "swap", "1L3", "2R5", "please" },
        { "list", "1", "please" },
        { "view", "wxhb-l", "2", "l", "please" },
        { "share", "2", "on", "please" },
        { "cycle", "2", "drawn", "please" },
        { "copy", "WAR", "please" },
        { "context", "list", "please" },
        { "wxhb", "on", "please" },
        { "help", "please" },
      }
      for _, words in ipairs(cases) do
        local reply, save_config, repaint = commands.command(words)
        assert.is_string(reply, words[1])
        assert.is_falsy(save_config, words[1])
        assert.is_falsy(repaint, words[1])
      end
      assert.equal("Savage Blade", world.bindings.entry_at(1, "l", 3).action, "nothing was unbound")
      assert.is_false(world.config.always_show_wxhb)
      assert.is_false(world.config.set_flags[2].shared)
    end)
  end)

  describe("number formats", function()
    -- tonumber takes "0x3", "3.0" and "1e0"; a set is a decimal integer or
    -- it is a typo, and one silently rounded into a neighbouring set is a
    -- binding the user cannot find again.
    it("refuses hex, exponent and fractional sets and slots", function()
      local commands, world = build()
      --[[ Through the ONE-WORD grammar, or these prove nothing: a
           three-word address now fails on its shape and a four-word `view`
           on its arity, both long before any number is read. The block
           went vacuous when the grammar changed and still carried the
           comment above, which described a check it had stopped
           making. ]]
      local cases = {
        { "bind", "0x3L1", "ja", "Provoke" },
        { "bind", "3.0L1", "ja", "Provoke" },
        { "bind", "1e0L1", "ja", "Provoke" },
        { "bind", "1L0x3", "ja", "Provoke" },
        { "bind", "1L3.0", "ja", "Provoke" },
        { "share", "0x3", "on" },
        { "cycle", "3.0", "drawn" },
        { "view", "wxhb-L", "1e0L" },
        { "list", "0x3" },
        { "swap", "0x3L1", "2R1" },
        -- And the set half of an address, which has its own range check.
        { "bind", "9L1", "ja", "Provoke" },
        { "bind", "1L9", "ja", "Provoke" },
      }
      for _, words in ipairs(cases) do
        local reply, save_config, repaint = commands.command(words)
        assert.is_string(reply, table.concat(words, " "))
        assert.is_falsy(save_config, table.concat(words, " "))
        assert.is_falsy(repaint, table.concat(words, " "))
      end
      assert.same({}, world.saved)
    end)

    it("echoes a padded set canonically", function()
      local commands, world = build()
      local reply = commands.command({ "bind", "007L3", "ja", "Provoke" })
      assert.is_not_nil(reply:find("7L3", 1, true), reply)
      assert.equal("Provoke", world.bindings.entry_at(7, "l", 3).action)
    end)
  end)

  describe("help", function()
    it("lists the authoring verbs", function()
      local commands = build()
      local reply = commands.command({ "help" })
      local text = text_of(reply)
      for _, verb in ipairs({ "bind", "unbind", "alias", "icon", "swap", "view", "share", "copy", "list", "retry" }) do
        assert.is_not_nil(text:find(verb, 1, true), verb .. " missing from help: " .. text)
      end
    end)

    it("names every layer prefix an address can carry", function()
      local commands = build()
      local text = text_of(commands.command({ "help" }))
      for _, prefix in ipairs({ "sub:", "wpn:", "ctx:" }) do
        assert.is_not_nil(text:find(prefix, 1, true), prefix .. " missing from help: " .. text)
      end
    end)

    it("gives cycle's two meanings a line each", function()
      --[[ `cycle` is two commands sharing a word: bare it advances the
           rotation, with arguments it edits which rotations a set belongs
           to. Sharing a line with `share` read as though they were one
           command with an `|` in it (Kevin, 2026-08-24). ]]
      local commands = build()
      local lines = commands.command({ "help" })
      local share, cycle = nil, nil
      for _, line in ipairs(lines) do
        if line:find("share", 1, true) then
          share = line
        end
        if line:find("cycle <set>", 1, true) then
          cycle = line
        end
      end
      assert.is_not_nil(share, "a line for share")
      assert.is_not_nil(cycle, "and its own for cycle")
      assert.are_not.equal(share, cycle, "not the same line")
      assert.is_nil(share:find("cycle", 1, true), "share's line is only share's: " .. share)
    end)

    it("gives every command its own line", function()
      --[[ Two ways a line crammed several commands together, both found by
           a player reading the help (Kevin, 2026-08-29): a spaced ` | `
           between whole commands (`draw | mr | warp [all] | edit`), and a
           pipe inside the VERB itself (`alias|icon <address>`). An
           argument's own alternatives keep their unspaced pipe - `on|off`,
           `drawn|sheathed` - so the test judges the verb, not the line. ]]
      local commands = build()
      local crammed = {}
      for _, line in ipairs(commands.command({ "help" })) do
        local verb = line:match("^%s*//hud crossbar (%S+)")
        if line:find(" | ", 1, true) or (verb ~= nil and verb:find("|", 1, true)) then
          crammed[#crammed + 1] = line
        end
      end
      assert.are.same({}, crammed)
    end)

    it("changes nothing", function()
      local commands, world = build()
      local _, save_config, repaint = commands.command({ "help" })
      assert.is_falsy(save_config)
      assert.is_falsy(repaint)
      assert.are.same({}, world.saved)
    end)
  end)
end)
