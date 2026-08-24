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
      -- Where the word cannot be part of the name - after a closing quote,
      -- or as ra's only argument - an unrecognised one is a typo, not a
      -- target: binding it would build a command that silently never fires.
      local commands, world = build()
      for _, words in ipairs({
        { "bind", "1L3", "ma", '"Cure IV"', "Kevin" },
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

    it("refuses an unterminated quote on a ct or ex line", function()
      local commands, world = build()
      for _, kind in ipairs({ "ct", "ex" }) do
        local reply, _, repaint = commands.command({ "bind", "1R1", kind, '"sea', "all" })
        assert.is_string(reply, kind)
        assert.is_falsy(repaint, kind)
      end
      assert.is_nil(stored(world, "SCH", 1, "right", 1))
    end)

    it("refuses a ct or ex line that is nothing but a quote", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1R1", "ct", '"' })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "right", 1))
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
      -- The span needs two characters before it can close, or `" Cure IV"`
      -- would read as an empty name plus a target called Cure.
      local commands, world = build()
      commands.command({ "bind", "1L1", "ma", '"', "Cure", 'IV"' })
      assert.are.same({ type = "ma", action = "Cure IV" }, stored(world, "SCH", 1, "left", 1))
    end)

    it("refuses an unterminated quote instead of storing it", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1L3", "ma", '"Cure', "IV" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3))
    end)

    it("refuses trailing words after a quoted name and its target", function()
      local commands, world = build()
      local reply, _, repaint = commands.command({ "bind", "1L3", "ma", '"Cure', 'IV"', "t", "please" })
      assert.is_string(reply)
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
      local quoted = commands.command({ "bind", "1L3", "ws", '"Savage', 'Blade"', "Kevin" })
      for _, reply in ipairs({ refusal, quoted }) do
        assert.is_string(reply)
        assert.is_not_nil(reply:find("not supported yet", 1, true), reply)
        assert.is_nil(reply:find("aimed at", 1, true), "it must not send them back to the refused form: " .. reply)
      end
      assert.is_not_nil(refusal:find("quote the whole name", 1, true), refusal)
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

    it("refuses an unterminated quote like bind does", function()
      local commands, world = build()
      commands.command({ "bind", "1L3", "ws", "Savage", "Blade" })
      local reply, _, repaint = commands.command({ "alias", "1L3", '"Big', "Hit" })
      assert.is_string(reply)
      assert.is_falsy(repaint)
      assert.is_nil(stored(world, "SCH", 1, "left", 3).alias)
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
      local commands, world = build({ icons = { ["components/crossbar/assets/icons/items/warp-ring.png"] = true } })
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

    it("changes nothing", function()
      local commands, world = build()
      local _, save_config, repaint = commands.command({ "help" })
      assert.is_falsy(save_config)
      assert.is_falsy(repaint)
      assert.are.same({}, world.saved)
    end)
  end)
end)
