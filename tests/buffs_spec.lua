local new_buffs = require("lib/buffs")

-- Ranks 1, 2 and 3 of the shipped order are KO, weakness and doom.
local KO, WEAKNESS, DOOM = 0, 1, 15
local UNRANKED, ALSO_UNRANKED = 9998, 9999

local RESOURCES = {
  buffs = {
    [0] = { en = "KO" },
    [1] = { en = "weakness" },
    [15] = { en = "doom" },
    [2] = { en = "sleep" },
    [33] = { en = "haste" },
    [40] = { en = "protect" },
    [253] = { en = "max hp boost" },
  },
}

describe("lib/buffs", function()
  local engine, settings

  before_each(function()
    engine = new_buffs({ name = "partylist", resources = RESOURCES })
    settings = { priority = {}, filters = {}, filter_mode = "blacklist" }
  end)

  local function say(cap, ...)
    local lines, changed = engine.command(settings, { ... }, cap)
    return table.concat(lines, "\n"), changed
  end

  describe("the order", function()
    it("ranks the shipped list from one", function()
      local ranks, ordered = engine.order({})
      assert.are.equal(1, ranks[KO])
      assert.are.equal(2, ranks[WEAKNESS])
      assert.are.equal(3, ranks[DOOM])
      assert.are.equal(621, #ordered)
    end)

    it("leaves a buff the shipped list never heard of unranked", function()
      local ranks = engine.order({})
      assert.is_nil(ranks[UNRANKED])
    end)

    it("moves an overridden buff to the rank it was given", function()
      local ranks = engine.order({ [DOOM] = 1 })
      assert.are.equal(1, ranks[DOOM])
      assert.are.equal(2, ranks[KO])
    end)

    it("promotes a buff the shipped order does not rank at all", function()
      local ranks = engine.order({ [UNRANKED] = 1 })
      assert.are.equal(1, ranks[UNRANKED])
      assert.are.equal(2, ranks[KO])
    end)

    it("gives a contested rank to the lower id", function()
      local ranks = engine.order({ [DOOM] = 1, [WEAKNESS] = 1 })
      assert.are.equal(1, ranks[WEAKNESS])
      assert.are.equal(2, ranks[DOOM])
      assert.are.equal(3, ranks[KO])
    end)

    it("clamps a rank past the end of the order", function()
      local ranks, ordered = engine.order({ [KO] = 9999 })
      assert.are.equal(#ordered, ranks[KO])
    end)

    it("ignores an override that is not a number pair", function()
      local ranks = engine.order({ [DOOM] = "first", doom = 1 })
      assert.are.equal(3, ranks[DOOM])
    end)

    -- A config re-read hands the logic a fresh table; nothing should have to
    -- remember to invalidate for that.
    it("recomputes for a different overrides table", function()
      assert.are.equal(3, engine.order({})[DOOM])
      assert.are.equal(1, engine.order({ [DOOM] = 1 })[DOOM])
    end)

    it("recomputes the same table after invalidate", function()
      local overrides = {}
      assert.are.equal(3, engine.order(overrides)[DOOM])
      overrides[DOOM] = 1
      assert.are.equal(3, engine.order(overrides)[DOOM], "memoized until told otherwise")
      engine.invalidate()
      assert.are.equal(1, engine.order(overrides)[DOOM])
    end)

    -- A broken config is normalized to a throwaway every call; the order must
    -- not be rebuilt (621 entries) per member per frame because of it.
    it("keeps one order for a settings value that is not a table", function()
      local _, first = engine.order(engine.normalize("nonsense").priority)
      local _, again = engine.order(engine.normalize(42).priority)
      assert.are.equal(first, again)
    end)

    it("uses a shipped list of the caller's choosing", function()
      local custom = new_buffs({ name = "x", resources = RESOURCES, shipped = { DOOM, KO } })
      local ranks, ordered = custom.order({})
      assert.are.same({ DOOM, KO }, ordered)
      assert.are.equal(1, ranks[DOOM])
    end)
  end)

  describe("the plan", function()
    local function shown(ids, opts)
      return engine.plan(ids, settings, opts)
    end

    it("orders buffs by the shipped priority", function()
      assert.are.same({ KO, WEAKNESS, DOOM }, shown({ DOOM, KO, WEAKNESS }))
    end)

    it("sorts a buff the priority list has never heard of last", function()
      assert.are.same({ KO, UNRANKED }, shown({ UNRANKED, KO }))
    end)

    it("breaks a tie between two unranked buffs by id, so the order never flickers", function()
      assert.are.same({ UNRANKED, ALSO_UNRANKED }, shown({ ALSO_UNRANKED, UNRANKED }))
    end)

    it("drops the empty-slot marker", function()
      assert.are.same({ KO }, shown({ 255, KO, 255 }))
    end)

    it("keeps the highest priority buffs when the cap bites", function()
      assert.are.same({ KO, WEAKNESS }, shown({ DOOM, WEAKNESS, KO }, { cap = 2 }))
    end)

    it("cuts nothing without a cap", function()
      local many = {}
      for index = 1, 32 do
        many[index] = index
      end
      assert.are.equal(32, #shown(many))
    end)

    it("removes a blacklisted buff", function()
      settings.filters = { WEAKNESS }
      assert.are.same({ KO, DOOM }, shown({ KO, WEAKNESS, DOOM }))
    end)

    it("keeps only the whitelisted buffs", function()
      settings.filter_mode = "whitelist"
      settings.filters = { WEAKNESS, DOOM }
      assert.are.same({ WEAKNESS, DOOM }, shown({ KO, WEAKNESS, DOOM }))
    end)

    it("shows nothing when the whitelist is empty", function()
      settings.filter_mode = "whitelist"
      assert.are.same({}, shown({ KO, WEAKNESS }))
    end)

    it("applies the user's overrides", function()
      settings.priority = { [DOOM] = 1 }
      assert.are.same({ DOOM, KO, WEAKNESS }, shown({ KO, WEAKNESS, DOOM }))
    end)

    -- A caller's own category restriction (the status bar's debuff bar) is
    -- applied before the user's list, so a blacklist can still trim it.
    it("keeps only what the caller's predicate accepts, before the list", function()
      settings.filters = { DOOM }
      local plan = shown({ KO, WEAKNESS, DOOM, UNRANKED }, {
        keep = function(id)
          return id ~= KO
        end,
      })
      assert.are.same({ WEAKNESS, UNRANKED }, plan)
    end)

    it("handles a nil source", function()
      assert.are.same({}, shown(nil))
    end)
  end)

  describe("normalize", function()
    it("fills in the keys a hand-edited file lost", function()
      local fixed = engine.normalize({ priority = "nonsense" })
      assert.are.same({}, fixed.priority)
      assert.are.same({}, fixed.filters)
      assert.are.equal("blacklist", fixed.filter_mode)
    end)

    it("keeps a whitelist", function()
      assert.are.equal("whitelist", engine.normalize({ filter_mode = "whitelist" }).filter_mode)
    end)

    it("repairs in place, so the fix is what gets saved", function()
      local broken = {}
      assert.are.equal(broken, engine.normalize(broken))
    end)

    it("hands back a throwaway for something that is not a table", function()
      local fixed = engine.normalize("nonsense")
      assert.are.same({ priority = {}, filters = {}, filter_mode = "blacklist" }, fixed)
    end)
  end)

  describe("names and lookups", function()
    it("names a buff from the resources", function()
      assert.are.equal("doom", engine.name(DOOM))
    end)

    it("falls back to the id for a buff the resources lack", function()
      assert.are.equal("buff 9998", engine.name(UNRANKED))
    end)

    it("resolves an id", function()
      assert.are.equal(15, engine.resolve("15"))
    end)

    it("resolves a name, whatever its case", function()
      assert.are.equal(DOOM, engine.resolve("DOOM"))
    end)

    it("refuses nothing at all", function()
      local id, lines = engine.resolve("")
      assert.is_nil(id)
      assert.is_not_nil(table.concat(lines, "\n"):find("//hud partylist buff", 1, true))
    end)

    it("refuses a name it cannot resolve", function()
      local id, lines = engine.resolve("nonsense")
      assert.is_nil(id)
      assert.is_not_nil(table.concat(lines, "\n"):find("no buff", 1, true))
    end)

    -- Several buffs share a name -- sleep is both 2 and 19 -- so the id is
    -- the only way to say which one, and guessing would be worse than asking.
    it("refuses an ambiguous name and lists the candidates", function()
      RESOURCES.buffs[19] = { en = "sleep" }
      local id, lines = engine.resolve("sleep")
      RESOURCES.buffs[19] = nil
      assert.is_nil(id)
      local said = table.concat(lines, "\n")
      assert.is_not_nil(said:find("2", 1, true))
      assert.is_not_nil(said:find("19", 1, true))
    end)

    it("sorts a list of ids by rank, then id", function()
      local ids = { UNRANKED, DOOM, KO, ALSO_UNRANKED }
      engine.sort(ids, engine.order({}))
      assert.are.same({ KO, DOOM, UNRANKED, ALSO_UNRANKED }, ids)
    end)
  end)

  describe("the commands", function()
    it("lists the icon slots that actually get drawn", function()
      local said = say(16)
      assert.is_not_nil(said:find("first 16", 1, true))
      assert.is_not_nil(said:find("KO", 1, true))
      -- Sixteen slots plus a heading, not the whole 621-entry order.
      assert.is_true(select(2, said:gsub("\n", "")) < 20)
    end)

    it("pages the whole order rather than only the visible slots", function()
      assert.is_not_nil(say(16, "list"):find("page 1/", 1, true))
    end)

    it("jumps to a page", function()
      local first = say(16, "list", "1")
      local third = say(16, "list", "3")
      assert.are_not.equal(first, third)
      assert.is_not_nil(third:find("page 3/", 1, true))
    end)

    it("clamps a page number that is off either end", function()
      local pages = say(16, "list"):match("page %d+/(%d+)")
      assert.is_not_nil(pages)
      assert.is_not_nil(say(16, "list", "9999"):find("page " .. pages .. "/" .. pages, 1, true))
      assert.is_not_nil(say(16, "list", "0"):find("page 1/" .. pages, 1, true))
    end)

    it("marks where the icon cap cuts the order", function()
      assert.is_not_nil(say(16, "list", "1"):find("cut", 1, true))
    end)

    it("lists the buffs the resources know that nothing ranks, after the ranked ones", function()
      RESOURCES.buffs[UNRANKED] = { en = "mystery" }
      local last = say(16, "list", "9999")
      RESOURCES.buffs[UNRANKED] = nil
      assert.is_not_nil(last:find("unranked", 1, true))
      assert.is_not_nil(last:find("mystery", 1, true))
    end)

    it("finds a buff by part of its name", function()
      local said = say(16, "find", "weak")
      assert.is_not_nil(said:find("weakness", 1, true))
      assert.is_not_nil(said:find("(drawn)", 1, true))
    end)

    it("finds a buff whose name has spaces", function()
      assert.is_not_nil(say(16, "find", "max", "hp"):find("max hp boost", 1, true))
    end)

    it("says so when a search matches nothing", function()
      local said, changed = say(16, "find", "zzzz")
      assert.is_false(changed)
      assert.is_not_nil(said:find("no buff", 1, true))
    end)

    it("wants something to search for", function()
      assert.is_false(select(2, say(16, "find")))
    end)

    it("moves a buff to the top by name", function()
      local _, changed = say(16, "top", "doom")
      assert.is_true(changed)
      assert.are.equal(1, settings.priority[DOOM])
    end)

    it("moves a buff to the top by id", function()
      say(16, "top", "15")
      assert.are.equal(1, settings.priority[DOOM])
    end)

    it("moves a buff one place up", function()
      say(16, "up", "doom")
      assert.are.equal(2, settings.priority[DOOM])
    end)

    it("moves a buff one place down", function()
      say(16, "down", "0")
      assert.are.equal(2, settings.priority[KO])
    end)

    it("will not move the top buff any higher", function()
      local said, changed = say(16, "up", "0")
      assert.is_false(changed)
      assert.is_not_nil(said:find("already", 1, true))
    end)

    it("will not move the bottom buff any lower", function()
      local _, ordered = engine.order(settings.priority)
      local said, changed = say(16, "down", tostring(ordered[#ordered]))
      assert.is_false(changed)
      assert.is_not_nil(said:find("already", 1, true))
    end)

    it("pulls an unranked buff in with up", function()
      local _, changed = say(16, "up", tostring(UNRANKED))
      assert.is_true(changed)
      assert.is_not_nil(settings.priority[UNRANKED])
    end)

    -- `order` tolerates a non-number override (a hand-edited file); an edit
    -- has to tolerate it too rather than error comparing it.
    it("moves a buff past an override that is not a number", function()
      settings.priority = { [WEAKNESS] = "first" }
      local _, changed = say(16, "top", "doom")
      assert.is_true(changed)
      assert.are.equal(1, settings.priority[DOOM])
    end)

    it("moves a buff to a given rank", function()
      say(16, "rank", "doom", "1")
      assert.are.equal(1, settings.priority[DOOM])
    end)

    it("reports the rank a buff actually landed on, not the one asked for", function()
      assert.is_nil(say(16, "rank", "doom", "9999"):find("9999", 1, true))
    end)

    it("rejects a rank that is not a positive whole number", function()
      assert.is_false(select(2, say(16, "rank", "doom", "0")))
      assert.is_false(select(2, say(16, "rank", "doom", "half")))
      assert.is_false(select(2, say(16, "rank", "doom")))
    end)

    -- The change has to show on the next plan without anyone invalidating.
    it("re-sorts as soon as a rank changes", function()
      assert.are.same({ KO, DOOM }, engine.plan({ KO, DOOM }, settings))
      say(16, "top", "doom")
      assert.are.same({ DOOM, KO }, engine.plan({ KO, DOOM }, settings))
    end)

    it("lets a later promotion take the rank from an earlier one", function()
      say(16, "top", "0")
      say(16, "top", "doom")
      assert.are.same({ DOOM, KO, WEAKNESS }, engine.plan({ KO, WEAKNESS, DOOM }, settings))
    end)

    it("pushes the buff that held a rank down rather than dropping it", function()
      say(16, "rank", "doom", "2")
      say(16, "rank", "1", "2")
      assert.are.same({ KO, WEAKNESS, DOOM }, engine.plan({ KO, WEAKNESS, DOOM }, settings))
    end)

    -- A caller may hand in a view whose `priority` is another table's field
    -- (the status bar's shared order under a per-bar filter list), so the
    -- clear has to happen inside the table rather than by replacing it.
    it("empties the overrides table it was handed on reset", function()
      local priority = settings.priority
      say(16, "top", "doom")
      say(16, "reset")
      assert.are.equal(priority, settings.priority)
      assert.are.same({}, priority)
    end)

    it("drops every override on reset", function()
      say(16, "top", "doom")
      local _, changed = say(16, "reset")
      assert.is_true(changed)
      assert.are.same({}, settings.priority)
      assert.are.same({ KO, DOOM }, engine.plan({ DOOM, KO }, settings))
    end)

    it("refuses a name it cannot resolve, and changes nothing", function()
      local said, changed = say(16, "top", "nonsense")
      assert.is_false(changed)
      assert.is_not_nil(said:find("no buff", 1, true))
    end)

    -- A caller with no icon cap still gets the listings, without cut marks.
    it("answers the listing verbs without a cap", function()
      assert.is_not_nil(say(nil):find("KO", 1, true))
      local listed = say(nil, "list")
      assert.is_not_nil(listed:find("page 1/", 1, true))
      assert.is_nil(listed:find("cut", 1, true))
      assert.is_nil(say(nil, "find", "weak"):find("(drawn)", 1, true))
    end)

    it("matches verbs case-insensitively", function()
      assert.is_true(select(2, say(16, "TOP", "doom")))
    end)

    it("answers an unknown verb with a hint naming the verbs", function()
      local said, changed = say(16, "wobble")
      assert.is_false(changed)
      assert.is_not_nil(said:find("rank", 1, true))
      assert.is_nil(said:find("active", 1, true))
    end)

    -- The status bar refuses `buff filter`, so its hint must not offer it.
    it("names only the verbs the caller lists, when it gives a list", function()
      local narrow = new_buffs({ name = "statusbar", resources = RESOURCES, hint_verbs = { "list", "top", "reset" } })
      local said = table.concat(narrow.command(settings, { "wobble" }, 16), "\n")
      assert.is_not_nil(said:find("list, top or reset", 1, true))
      assert.is_nil(said:find("filter", 1, true))
    end)

    it("names a single verb without an 'or'", function()
      local one = new_buffs({ name = "x", resources = RESOURCES, hint_verbs = { "list" } })
      local said = table.concat(one.command(settings, { "wobble" }, 16), "\n")
      assert.is_not_nil(said:find("takes list", 1, true))
      assert.is_nil(said:find(" or ", 1, true))
    end)

    it("falls back to its own verbs when the caller's list is empty", function()
      local none = new_buffs({ name = "x", resources = RESOURCES, hint_verbs = {} })
      local said = table.concat(none.command(settings, { "wobble" }, 16), "\n")
      assert.is_not_nil(said:find("rank", 1, true))
    end)

    -- Partylist answers `active` itself, from its roster; the hint should
    -- still name it.
    it("names the caller's own verbs in the hint", function()
      local extra = new_buffs({ name = "partylist", resources = RESOURCES, extra_verbs = { "active" } })
      assert.is_not_nil(table.concat(extra.command(settings, { "wobble" }, 16), "\n"):find("active", 1, true))
    end)

    describe("filters", function()
      it("adds a buff to the filter list", function()
        local _, changed = say(16, "filter", "add", "doom")
        assert.is_true(changed)
        assert.are.same({ DOOM }, settings.filters)
      end)

      it("does not add the same buff twice", function()
        say(16, "filter", "add", "doom")
        local _, changed = say(16, "filter", "add", "doom")
        assert.is_false(changed)
        assert.are.equal(1, #settings.filters)
      end)

      it("removes a buff from the filter list", function()
        say(16, "filter", "add", "doom")
        say(16, "filter", "remove", "15")
        assert.are.same({}, settings.filters)
      end)

      it("says so when removing a buff that was never filtered", function()
        local said, changed = say(16, "filter", "remove", "doom")
        assert.is_false(changed)
        assert.is_not_nil(said:find("not filtered", 1, true))
      end)

      it("empties the filter list", function()
        say(16, "filter", "add", "doom")
        say(16, "filter", "clear")
        assert.are.same({}, settings.filters)
      end)

      it("empties the filter list it was handed on clear", function()
        local filters = settings.filters
        say(16, "filter", "add", "doom")
        say(16, "filter", "clear")
        assert.are.equal(filters, settings.filters)
        assert.are.same({}, filters)
      end)

      -- The status bar's filters sit at `//hud statusbar <bar> filter`, with
      -- no `buff` word in the path, so the messages take the path from the
      -- caller.
      it("names the filter path the caller gave in its messages", function()
        local bar = new_buffs({ name = "statusbar bar2", resources = RESOURCES, filter_path = "statusbar bar2 filter" })
        local said = table.concat(bar.command(settings, { "filter", "mode", "greylist" }, 16), "\n")
        assert.is_not_nil(said:find("//hud statusbar bar2 filter mode", 1, true))
        assert.is_nil(said:find("buff filter", 1, true))
        said = table.concat(bar.command(settings, { "filter", "wobble" }, 16), "\n")
        assert.is_not_nil(said:find("//hud statusbar bar2 filter takes", 1, true))
      end)

      it("names the filter path in every filter message", function()
        local bar = new_buffs({ name = "statusbar bar2", resources = RESOURCES, filter_path = "statusbar bar2 filter" })
        local function said(...)
          return table.concat((bar.command(settings, { ... }, 16)), "\n")
        end
        assert.is_not_nil(said("filter", "mode", "whitelist"):find("statusbar bar2 filter is now", 1, true))
        assert.is_not_nil(said("filter", "clear"):find("statusbar bar2 filters cleared", 1, true))
        assert.is_not_nil(said("filter", "add"):find("//hud statusbar bar2 filter add", 1, true))
        assert.is_nil(said("filter", "add"):find("bar2 buff", 1, true))
      end)

      -- The advice in a refusal has to name a command the caller answers:
      -- the status bar's buff verbs take no bar word.
      it("points a failed lookup at the buff path the caller gave", function()
        local bar = new_buffs({
          name = "statusbar bar2",
          resources = RESOURCES,
          filter_path = "statusbar bar2 filter",
          buff_path = "statusbar buff",
        })
        local said = table.concat((bar.command(settings, { "filter", "add", "xyzzy" }, 16)), "\n")
        assert.is_not_nil(said:find("//hud statusbar buff find xyzzy", 1, true))
        assert.is_nil(said:find("bar2 buff", 1, true))
      end)

      it("lists a hand-edited entry that is not a number rather than erroring", function()
        settings.filters = { "wobble" }
        assert.is_not_nil(say(16, "filter", "list"):find("wobble", 1, true))
      end)

      it("lists the filtered buffs", function()
        say(16, "filter", "add", "doom")
        assert.is_not_nil(say(16, "filter", "list"):find("doom", 1, true))
      end)

      it("lists by default", function()
        assert.is_not_nil(say(16, "filter"):find("nothing", 1, true))
      end)

      it("switches the list between a blacklist and a whitelist", function()
        say(16, "filter", "mode", "whitelist")
        assert.are.equal("whitelist", settings.filter_mode)
        say(16, "filter", "mode", "blacklist")
        assert.are.equal("blacklist", settings.filter_mode)
      end)

      it("rejects a mode that is neither", function()
        assert.is_false(select(2, say(16, "filter", "mode", "greylist")))
      end)

      it("answers an unknown filter verb with a hint", function()
        local said, changed = say(16, "filter", "wobble")
        assert.is_false(changed)
        assert.is_not_nil(said:find("add", 1, true))
      end)
    end)
  end)
end)
