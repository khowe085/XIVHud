local new_bindings = require("components/crossbar/bindings")

local function record(name)
  return { type = "ws", action = name, target = "t" }
end

local function ja(name)
  return { type = "ja", action = name, target = "me" }
end

-- Default flags: unshared, cycled in both states -- an untouched install.
local function default_flags()
  local flags = {}
  for set = 1, 8 do
    flags[set] = { shared = false, cycle = { drawn = true, sheathed = true } }
  end
  return flags
end

-- A bindings model over an in-memory file store and a live config table.
local function build(opts)
  opts = opts or {}
  local world = {
    files = opts.files or {},
    saved = {},
    config = {
      views = opts.views or {
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
      return world.files[name]
    end,
    save = function(name, data)
      world.files[name] = data
      world.saved[name] = (world.saved[name] or 0) + 1
    end,
    get_config = function()
      return world.config
    end,
  })
  return bindings, world
end

describe("crossbar bindings", function()
  describe("per-job load", function()
    it("starts a never-bound job empty, with set 1 active", function()
      local bindings = build()
      bindings.set_job("WAR", "NIN")
      assert.equal(1, bindings.active_set())
      assert.is_nil(bindings.resolve(1, "left", 1))
    end)

    it("resolves a job base binding", function()
      local bindings = build({
        files = {
          WAR = { sets = { [1] = { left = { [3] = record("Savage Blade") } } } },
        },
      })
      bindings.set_job("WAR", "NIN")
      local entry, source = bindings.resolve(1, "left", 3)
      assert.equal("Savage Blade", entry.action)
      assert.equal("base", source)
    end)

    it("accepts l and r as side spellings", function()
      local bindings = build({
        files = { WAR = { sets = { [1] = { right = { [2] = record("Raging Rush") } } } } },
      })
      bindings.set_job("WAR")
      assert.equal("Raging Rush", bindings.resolve(1, "r", 2).action)
    end)

    it("merges defaults over a sparse file", function()
      local bindings = build({ files = { WAR = { sets = {} } } })
      bindings.set_job("WAR")
      assert.equal(1, bindings.active_set())
      assert.is_nil(bindings.resolve(2, "left", 1))
    end)

    it("remembers the active set per job", function()
      local bindings, world = build({ files = { WAR = { active_set = 4, sets = {} } } })
      bindings.set_job("WAR")
      assert.equal(4, bindings.active_set())
      bindings.jump(6)
      assert.equal(6, world.files.WAR.active_set)
      bindings.set_job("WHM")
      assert.equal(1, bindings.active_set())
      bindings.set_job("WAR")
      assert.equal(6, bindings.active_set())
    end)

    it("jump reaches any set, empty or not, and rejects out-of-range", function()
      local bindings = build()
      bindings.set_job("WAR")
      assert.equal(8, bindings.jump(8))
      assert.equal(8, bindings.active_set())
      local ok, err = bindings.jump(9)
      assert.is_nil(ok)
      assert.is_string(err)
      assert.equal(8, bindings.active_set())
    end)
  end)

  describe("broken data files", function()
    -- Hand-editing the per-job files is the documented CB4-CB6 verification
    -- procedure, and resolve runs per frame: a bad node degrades to defaults
    -- while its siblings survive, mirroring lib/settings on a broken config.
    it("drops a non-table set and keeps its siblings", function()
      local bindings = build({
        files = {
          WAR = { sets = { [1] = 5, [2] = { left = { [1] = record("Good") } } } },
        },
      })
      bindings.set_job("WAR")
      assert.is_nil(bindings.resolve(1, "left", 1))
      assert.equal("Good", bindings.resolve(2, "left", 1).action)
    end)

    it("drops a non-table side and a non-table slot entry", function()
      local bindings = build({
        files = {
          WAR = { sets = { [1] = { left = 5, right = { [1] = 7, [2] = record("Good") } } } },
        },
      })
      bindings.set_job("WAR")
      assert.is_nil(bindings.resolve(1, "left", 1))
      assert.is_nil(bindings.resolve(1, "right", 1))
      assert.equal("Good", bindings.resolve(1, "right", 2).action)
    end)

    it("drops a non-table context tree", function()
      local bindings = build({
        files = { SCH = { contexts = { ["light-arts"] = 7 } } },
      })
      bindings.set_job("SCH")
      bindings.update_buffs({ 358 })
      assert.is_nil(bindings.resolve(1, "left", 1))
    end)

    it("drops a non-table subjob tree", function()
      local bindings = build({
        files = { WAR = { sub = { NIN = 3 } } },
      })
      bindings.set_job("WAR", "NIN")
      assert.is_nil(bindings.resolve(1, "left", 1))
    end)

    it("resets a garbage active_set and coerces a numeric string", function()
      for _, garbage in ipairs({ "two", 99, 0, 2.5 }) do
        local bindings = build({ files = { WAR = { active_set = garbage, sets = {} } } })
        bindings.set_job("WAR")
        assert.equal(1, bindings.active_set(), tostring(garbage))
      end

      local coerced = build({ files = { WAR = { active_set = "3", sets = {} } } })
      coerced.set_job("WAR")
      assert.equal(3, coerced.active_set())
    end)

    it("copies from a garbage-mixed source without importing the garbage", function()
      local bindings = build({
        files = {
          WAR = {
            sets = { [1] = 5, [2] = { left = { [1] = record("Good") } } },
            sub = { NIN = 3 },
            contexts = { ["light-arts"] = 7 },
          },
        },
      })
      bindings.set_job("DRK")
      assert.is_true(bindings.copy_from("WAR"))
      assert.is_nil(bindings.resolve(1, "left", 1))
      assert.equal("Good", bindings.resolve(2, "left", 1).action)
    end)

    it("refuses to copy from a source that is not a table", function()
      local bindings = build({ files = { WAR = 5 } })
      bindings.set_job("DRK")
      local ok, err = bindings.copy_from("WAR")
      assert.is_nil(ok)
      assert.is_string(err)
    end)

    it("degrades garbage set_flags and views containers to defaults", function()
      -- merge_defaults lets a user scalar win over a table default, so a
      -- whole container can arrive as a number or boolean.
      for _, garbage in ipairs({ 5, true }) do
        local bindings = build({
          files = { WAR = { sets = { [1] = { left = { [1] = record("One") } } } } },
          set_flags = garbage,
          views = 7,
        })
        bindings.set_job("WAR")
        local entry, source = bindings.resolve(1, "left", 1)
        assert.equal("One", entry.action, tostring(garbage))
        assert.equal("base", source)
        assert.equal(1, bindings.cycle())
        assert.is_nil(bindings.view_target("wxhb_left"))
      end
    end)

    it("treats a truthy non-table set_flags entry as the default flags", function()
      local flags = default_flags()
      flags[1] = true
      local bindings = build({
        files = { WAR = { sets = { [1] = { left = { [1] = record("One") } } } } },
        set_flags = flags,
      })
      bindings.set_job("WAR")
      local entry, source = bindings.resolve(1, "left", 1)
      assert.equal("One", entry.action)
      assert.equal("base", source)
      assert.equal(1, bindings.cycle())
    end)

    it("treats a truthy non-table cycle field as cycled in both states", function()
      -- Only truthy non-tables are garbage: false must keep meaning
      -- "in no rotation" per the repo's sentinel convention.
      local flags = default_flags()
      flags[2] = { shared = false, cycle = true }
      local bindings = build({
        files = { WAR = { sets = { [2] = { left = { [1] = record("Two") } } } } },
        set_flags = flags,
      })
      bindings.set_job("WAR")
      assert.equal(2, bindings.cycle())
      bindings.set_weapon_state("drawn")
      assert.equal(2, bindings.cycle())
    end)

    it("is immune to later mutation of the loaded file table", function()
      local file = { sets = { [1] = { left = { [1] = record("Original") } } } }
      local bindings = build({ files = { WAR = file } })
      bindings.set_job("WAR")
      file.sets[1].left[1].action = "Corrupted"
      assert.equal("Original", bindings.resolve(1, "left", 1).action)
    end)

    it("cycles safely over a file whose active_set was a table", function()
      local bindings = build({
        files = {
          WAR = { active_set = {}, sets = { [2] = { left = { [1] = record("Two") } } } },
        },
      })
      bindings.set_job("WAR")
      assert.equal(2, bindings.cycle())
    end)
  end)

  describe("shared store", function()
    local function shared_six()
      local flags = default_flags()
      flags[6].shared = true
      return build({
        files = {
          SHARED = { sets = { [6] = { left = { [1] = record("Shared WS") } } } },
          WAR = { sets = { [6] = { left = { [1] = record("Dormant WS") } } } },
        },
        set_flags = flags,
      })
    end

    it("answers which sets are shared, entry or no entry", function()
      -- The binder labels and addresses its base row from this: an empty
      -- shared set holds no layer to infer the answer from.
      local bindings = shared_six()
      bindings.set_job("WAR")
      assert.is_true(bindings.shared(6))
      assert.is_false(bindings.shared(1), "an unshared set")
      assert.is_false(bindings.shared(nil), "and garbage is not shared")
    end)

    it("reads a shared set's base from SHARED, from any job", function()
      local bindings = shared_six()
      bindings.set_job("WAR")
      local entry, source = bindings.resolve(6, "left", 1)
      assert.equal("Shared WS", entry.action)
      assert.equal("shared", source)
      bindings.set_job("WHM")
      assert.equal("Shared WS", bindings.resolve(6, "left", 1).action)
    end)

    it("applies a context override on top of a shared set", function()
      -- Layers above the base apply uniformly regardless of the base's
      -- store; the override itself still lives in the job file.
      local flags = default_flags()
      flags[6].shared = true
      local bindings = build({
        files = {
          SHARED = { sets = { [6] = { left = { [1] = record("Shared WS") } } } },
          SCH = { contexts = { ["light-arts"] = { [6] = { left = { [1] = ja("Accession") } } } } },
        },
        set_flags = flags,
      })
      bindings.set_job("SCH")
      assert.equal("Shared WS", bindings.resolve(6, "left", 1).action)
      bindings.update_buffs({ 358 })
      local entry, source = bindings.resolve(6, "left", 1)
      assert.equal("Accession", entry.action)
      assert.equal("ctx:light-arts", source)
    end)

    it("keeps the dormant job-store contents when the flag flips", function()
      local bindings, world = shared_six()
      bindings.set_job("WAR")
      world.config.set_flags[6].shared = false
      local entry, source = bindings.resolve(6, "left", 1)
      assert.equal("Dormant WS", entry.action)
      assert.equal("base", source)
      world.config.set_flags[6].shared = true
      assert.equal("Shared WS", bindings.resolve(6, "left", 1).action)
    end)
  end)

  describe("views", function()
    it("answers the configured set and side for a view", function()
      local bindings = build()
      bindings.set_job("WAR")
      assert.same({ set = 2, side = "left" }, bindings.view_target("wxhb_left"))
    end)

    it("resolves both Expanded views identically when pointed at one place", function()
      local bindings = build({
        files = { WAR = { sets = { [3] = { left = { [5] = record("Expanded WS") } } } } },
        views = {
          wxhb_left = { set = 2, side = "left" },
          wxhb_right = { set = 2, side = "right" },
          expanded_lr = { set = 3, side = "left" },
          expanded_rl = { set = 3, side = "left" },
        },
      })
      bindings.set_job("WAR")
      local lr = bindings.view_target("expanded_lr")
      local rl = bindings.view_target("expanded_rl")
      assert.same(bindings.resolve(lr.set, lr.side, 5), bindings.resolve(rl.set, rl.side, 5))
      assert.equal("Expanded WS", bindings.resolve(rl.set, rl.side, 5).action)
    end)
  end)

  describe("the subjob layer", function()
    it("overrides only where the current subjob says so", function()
      local bindings = build({
        files = {
          WAR = {
            sets = { [1] = { left = { [1] = record("Base WS"), [2] = record("Other WS") } } },
            sub = { NIN = { [1] = { left = { [1] = ja("Provoke") } } } },
          },
        },
      })
      bindings.set_job("WAR", "NIN")
      local entry, source = bindings.resolve(1, "left", 1)
      assert.equal("Provoke", entry.action)
      assert.equal("sub", source)
      assert.equal("Other WS", bindings.resolve(1, "left", 2).action)
    end)

    it("ignores another subjob's overrides", function()
      local bindings = build({
        files = {
          WAR = {
            sets = { [1] = { left = { [1] = record("Base WS") } } },
            sub = { NIN = { [1] = { left = { [1] = ja("Provoke") } } } },
          },
        },
      })
      bindings.set_job("WAR", "WHM")
      assert.equal("Base WS", bindings.resolve(1, "left", 1).action)
    end)
  end)

  describe("context layers", function()
    -- Kevin's SCH file: a WS in the base; Light Arts swaps it for the
    -- Addendum; the arts fight over a stratagem slot; Addendum: White fills
    -- a WXHB-side slot with an unlocked spell.
    local function sch_files()
      return {
        SCH = {
          sets = { [1] = { left = { [1] = record("Myrkr"), [3] = record("Base Slot 3") } } },
          contexts = {
            ["light-arts"] = {
              [1] = { left = { [1] = ja("Addendum: White"), [3] = ja("Penury") } },
            },
            ["dark-arts"] = {
              [1] = { left = { [3] = ja("Parsimony") } },
            },
            ["addendum-white"] = {
              [2] = { left = { [2] = { type = "ma", action = "Cure IV", target = "t" } } },
            },
          },
        },
      }
    end

    it("keeps a context inactive until its buff arrives", function()
      local bindings = build({ files = sch_files() })
      bindings.set_job("SCH")
      assert.same({}, bindings.active_contexts())
      assert.equal("Myrkr", bindings.resolve(1, "left", 1).action)
    end)

    it("activates from the full buff list and overrides the base", function()
      local bindings = build({ files = sch_files() })
      bindings.set_job("SCH")
      assert.is_true(bindings.update_buffs({ 358 }))
      assert.same({ "light-arts" }, bindings.active_contexts())
      local entry, source = bindings.resolve(1, "left", 1)
      assert.equal("Addendum: White", entry.action)
      assert.equal("ctx:light-arts", source)
      assert.equal("Penury", bindings.resolve(1, "left", 3).action)
    end)

    it("short-circuits when nothing changed", function()
      local bindings = build({ files = sch_files() })
      bindings.set_job("SCH")
      assert.is_true(bindings.update_buffs({ 358 }))
      assert.is_false(bindings.update_buffs({ 358, 40 }))
    end)

    it("keeps the arts layer through the spurious lose-buff during an Addendum", function()
      -- FFXI drops the arts buff from the list while an Addendum is up; 401
      -- alone must keep light-arts active because the sync reads the full
      -- list against any_of, never the deltas.
      local bindings = build({ files = sch_files() })
      bindings.set_job("SCH")
      bindings.update_buffs({ 358 })
      assert.is_true(bindings.update_buffs({ 401 }))
      assert.same({ "light-arts", "addendum-white" }, bindings.active_contexts())
      assert.equal("Addendum: White", bindings.resolve(1, "left", 1).action)
      assert.equal("Penury", bindings.resolve(1, "left", 3).action)
    end)

    it("lets the addendum layer beat the arts layer on the same slot", function()
      local files = sch_files()
      files.SCH.contexts["light-arts"][1].left[5] = ja("Arts Entry")
      files.SCH.contexts["addendum-white"][1] = { left = { [5] = ja("Addendum Entry") } }
      local bindings = build({ files = files })
      bindings.set_job("SCH")
      bindings.update_buffs({ 401 })
      local entry, source = bindings.resolve(1, "left", 5)
      assert.equal("Addendum Entry", entry.action)
      assert.equal("ctx:addendum-white", source)
    end)

    it("swaps the stratagem slot between the arts", function()
      local bindings = build({ files = sch_files() })
      bindings.set_job("SCH")
      bindings.update_buffs({ 359 })
      assert.equal("Parsimony", bindings.resolve(1, "left", 3).action)
      -- Dark Arts has no entry for slot 1, so the base shows again.
      assert.equal("Myrkr", bindings.resolve(1, "left", 1).action)
    end)

    it("resolves the Addendum WXHB view end-to-end", function()
      local bindings = build({ files = sch_files() })
      bindings.set_job("SCH")
      bindings.update_buffs({ 401 })
      local view = bindings.view_target("wxhb_left")
      assert.equal("Cure IV", bindings.resolve(view.set, view.side, 2).action)
      bindings.update_buffs({})
      assert.is_nil(bindings.resolve(view.set, view.side, 2))
    end)

    it("clears active contexts on a job change until the next buff sync", function()
      -- A job change strips buffs in game; until the next full-list re-sync
      -- arrives, the old job's contexts must not colour the new job's slots.
      local files = sch_files()
      files.RDM = {
        contexts = { ["light-arts"] = { [1] = { left = { [3] = ja("Accession") } } } },
      }
      local bindings = build({ files = files })
      bindings.set_job("SCH")
      bindings.update_buffs({ 358 })
      assert.same({ "light-arts" }, bindings.active_contexts())
      bindings.set_job("RDM")
      assert.same({}, bindings.active_contexts())
      assert.is_nil(bindings.resolve(1, "left", 3))
      bindings.update_buffs({ 358 })
      assert.equal("Accession", bindings.resolve(1, "left", 3).action)
    end)

    it("keeps context overrides in the main job's file only", function()
      local bindings = build({ files = sch_files() })
      bindings.set_job("RDM", "SCH")
      bindings.update_buffs({ 358 })
      assert.is_nil(bindings.resolve(1, "left", 3))
    end)
  end)

  describe("resolution seam with actions", function()
    -- CB1's acceptance line is the composed resolution: an address through
    -- the full layer stack to the exact command.
    local new_actions = require("components/crossbar/actions")

    it("turns a resolved binding into its exact command, layers included", function()
      local bindings = build({
        files = {
          SCH = {
            sets = { [1] = { left = { [1] = { type = "ma", action = "Cure IV", target = "t" } } } },
            contexts = { ["light-arts"] = { [1] = { left = { [1] = { type = "mr" } } } } },
          },
        },
      })
      local actions = new_actions({
        roulette = {
          ride = function()
            return 'input /mount "crab"'
          end,
        },
        warp = {},
      })
      bindings.set_job("SCH")
      local plan = actions.resolve(bindings.resolve(1, "left", 1))
      assert.equal('input /ma "Cure IV" <t>', plan.command)
      -- The context layer now supplies a built-in record for the same slot.
      bindings.update_buffs({ 358 })
      plan = actions.resolve(bindings.resolve(1, "left", 1))
      assert.equal('input /mount "crab"', plan.command)
    end)
  end)

  describe("weapon state", function()
    it("starts sheathed and resets on a job change", function()
      local bindings = build()
      bindings.set_job("WAR")
      assert.equal("sheathed", bindings.weapon_state())
      bindings.set_weapon_state("drawn")
      bindings.set_job("WHM")
      assert.equal("sheathed", bindings.weapon_state())
    end)

    it("enters drawn on in-game engagement", function()
      local bindings = build()
      bindings.set_job("WAR")
      bindings.on_status(1)
      assert.equal("drawn", bindings.weapon_state())
    end)

    it("ignores in-game disengagement", function()
      local bindings = build()
      bindings.set_job("WAR")
      bindings.on_status(1)
      bindings.on_status(0)
      assert.equal("drawn", bindings.weapon_state())
    end)

    it("returns to sheathed only through an explicit flip", function()
      local bindings = build()
      bindings.set_job("WAR")
      bindings.on_status(3)
      bindings.set_weapon_state("sheathed")
      assert.equal("sheathed", bindings.weapon_state())
    end)
  end)

  describe("cycle", function()
    -- Kevin's layout: 1-2 drawn-only, 3-4 out of both rotations (views and
    -- jump only), 6-8 shared and sheathed-only. 5 is bound nowhere.
    local function kevins()
      local flags = default_flags()
      flags[1].cycle = { drawn = true, sheathed = false }
      flags[2].cycle = { drawn = true, sheathed = false }
      flags[3].cycle = { drawn = false, sheathed = false }
      flags[4].cycle = { drawn = false, sheathed = false }
      flags[5].cycle = { drawn = false, sheathed = false }
      for set = 6, 8 do
        flags[set] = { shared = true, cycle = { drawn = false, sheathed = true } }
      end
      local sets = {}
      for set = 1, 4 do
        sets[set] = { left = { [1] = record("Job WS " .. set) } }
      end
      local shared_sets = {}
      for set = 6, 8 do
        shared_sets[set] = { left = { [1] = record("Shared WS " .. set) } }
      end
      return build({
        files = { WAR = { sets = sets }, SHARED = { sets = shared_sets } },
        set_flags = flags,
      })
    end

    it("walks the sheathed rotation across the shared sets", function()
      local bindings = kevins()
      bindings.set_job("WAR")
      assert.equal(6, bindings.cycle())
      assert.equal(7, bindings.cycle())
      assert.equal(8, bindings.cycle())
      assert.equal(6, bindings.cycle())
    end)

    it("walks the drawn rotation across the combat sets", function()
      local bindings = kevins()
      bindings.set_job("WAR")
      bindings.set_weapon_state("drawn")
      assert.equal(2, bindings.cycle())
      assert.equal(1, bindings.cycle())
    end)

    it("skips an empty set even when its flags include it", function()
      local flags = default_flags()
      flags[2].cycle = { drawn = true, sheathed = true }
      local bindings = build({
        files = {
          WAR = {
            sets = {
              [1] = { left = { [1] = record("One") } },
              [3] = { left = { [1] = record("Three") } },
            },
          },
        },
        set_flags = flags,
      })
      bindings.set_job("WAR")
      assert.equal(3, bindings.cycle())
    end)

    it("counts a set with only an active context entry as non-empty", function()
      local bindings = build({
        files = {
          SCH = {
            sets = { [1] = { left = { [1] = record("One") } } },
            contexts = { ["light-arts"] = { [4] = { left = { [2] = ja("Accession") } } } },
          },
        },
      })
      bindings.set_job("SCH")
      assert.equal(1, bindings.cycle())
      bindings.update_buffs({ 358 })
      assert.equal(4, bindings.cycle())
    end)

    it("stays put when every set is excluded", function()
      local flags = default_flags()
      for set = 1, 8 do
        flags[set].cycle = { drawn = false, sheathed = false }
      end
      local bindings = build({
        files = { WAR = { sets = { [2] = { left = { [1] = record("Two") } } } } },
        set_flags = flags,
      })
      bindings.set_job("WAR")
      assert.equal(1, bindings.cycle())
      assert.equal(1, bindings.active_set())
    end)

    it("persists the set the cycle lands on", function()
      local bindings, world = kevins()
      bindings.set_job("WAR")
      bindings.cycle()
      assert.equal(6, world.files.WAR.active_set)
    end)

    it("treats cycle = false as excluded from both rotations", function()
      -- The repo convention: false disables an entry (merge_defaults refills
      -- nil, never false), so a whole cycle table may legitimately be false.
      local flags = default_flags()
      flags[3] = { shared = true, cycle = false }
      local bindings = build({
        files = {
          WAR = {
            sets = {
              [2] = { left = { [1] = record("Two") } },
              [4] = { left = { [1] = record("Four") } },
            },
          },
          SHARED = { sets = { [3] = { left = { [1] = record("Shared Three") } } } },
        },
        set_flags = flags,
      })
      bindings.set_job("WAR")
      assert.equal(2, bindings.cycle())
      assert.equal(4, bindings.cycle())
      bindings.set_weapon_state("drawn")
      assert.equal(2, bindings.cycle())
      assert.equal(4, bindings.cycle())
    end)
  end)

  describe("bind and unbind", function()
    it("writes the job base and persists only the job file", function()
      local bindings, world = build()
      bindings.set_job("WAR", "NIN")
      assert.is_true(bindings.bind(2, "l", 4, record("Upheaval")))
      assert.equal("Upheaval", world.files.WAR.sets[2].left[4].action)
      assert.equal("Upheaval", bindings.resolve(2, "left", 4).action)
      assert.is_nil(world.saved.SHARED)
    end)

    it("writes a shared set's base into SHARED, not the job file", function()
      local flags = default_flags()
      flags[6].shared = true
      local bindings, world = build({ set_flags = flags })
      bindings.set_job("WAR")
      assert.is_true(bindings.bind(6, "r", 1, record("Shared WS")))
      assert.equal("Shared WS", world.files.SHARED.sets[6].right[1].action)
      assert.is_nil(world.saved.WAR)
    end)

    it("targets the current subjob's layer through the sub: prefix", function()
      local bindings, world = build()
      bindings.set_job("WAR", "NIN")
      assert.is_true(bindings.bind("sub:1", "l", 2, ja("Provoke")))
      assert.equal("Provoke", world.files.WAR.sub.NIN[1].left[2].action)
      assert.is_nil(world.files.WAR.sets[1])
      bindings.set_job("WAR", "WHM")
      assert.is_nil(bindings.resolve(1, "left", 2))
    end)

    it("refuses the sub: prefix with no subjob to target", function()
      local bindings = build()
      bindings.set_job("WAR")
      local ok, err = bindings.bind("sub:1", "l", 2, ja("Provoke"))
      assert.is_nil(ok)
      assert.is_string(err)
    end)

    it("targets a context's overrides through the ctx: prefix", function()
      local bindings, world = build()
      bindings.set_job("SCH")
      assert.is_true(bindings.bind("ctx:light-arts:1", "l", 3, ja("Addendum: White")))
      assert.equal("Addendum: White", world.files.SCH.contexts["light-arts"][1].left[3].action)
      assert.is_nil(world.files.SCH.sets[1])
      bindings.update_buffs({ 358 })
      assert.equal("Addendum: White", bindings.resolve(1, "left", 3).action)
    end)

    it("accepts a numeric string set the way the CLI sends it", function()
      local bindings = build()
      bindings.set_job("WAR")
      assert.is_true(bindings.bind("3", "r", 8, record("Full Break")))
      assert.equal("Full Break", bindings.resolve(3, "right", 8).action)
    end)

    it("rejects unknown layers, contexts, sides and out-of-range addresses", function()
      local bindings = build()
      bindings.set_job("WAR", "NIN")
      for _, case in ipairs({
        { "job:1", "l", 1 }, -- unknown layer prefix
        { "ctx:bogus:1", "l", 1 }, -- unknown context
        { "ctx:light-arts:9", "l", 1 }, -- set out of range
        { 0, "l", 1 },
        { 9, "l", 1 },
        { 1.5, "l", 1 }, -- fractional set would serialize invisibly forever
        { 1, "x", 1 }, -- bad side
        { 1, "l", 0 },
        { 1, "l", 9 }, -- slot out of range
        { 1, "l", 2.5 }, -- fractional slot likewise
      }) do
        local ok, err = bindings.bind(case[1], case[2], case[3], record("Nope"))
        assert.is_nil(ok, tostring(case[1]) .. "/" .. case[2] .. "/" .. case[3])
        assert.is_string(err)
      end
    end)

    it("creates nothing when unbinding an already-empty address", function()
      local bindings, world = build()
      bindings.set_job("WAR")
      assert.is_true(bindings.unbind(2, "l", 4))
      assert.is_nil(world.files.WAR.sets[2])
    end)

    it("carries unknown top-level keys through a load-bind-save round trip", function()
      local bindings, world = build({
        files = { WAR = { active_set = 2, sets = {}, custom_note = "keep me" } },
      })
      bindings.set_job("WAR")
      bindings.bind(1, "l", 1, record("Upheaval"))
      assert.equal("keep me", world.files.WAR.custom_note)
    end)

    it("carries unknown SHARED keys through a shared-set bind", function()
      local flags = default_flags()
      flags[6].shared = true
      local bindings, world = build({
        files = { SHARED = { sets = {}, custom_note = "keep me" } },
        set_flags = flags,
      })
      bindings.set_job("WAR")
      bindings.bind(6, "l", 1, record("Shared WS"))
      assert.equal("keep me", world.files.SHARED.custom_note)
    end)

    it("leaves no empty layer root behind after a bind-then-unbind", function()
      local bindings, world = build()
      bindings.set_job("SCH", "NIN")
      bindings.bind("sub:1", "l", 2, ja("Provoke"))
      bindings.unbind("sub:1", "l", 2)
      assert.is_nil(world.files.SCH.sub.NIN)
      bindings.bind("ctx:light-arts:1", "l", 3, ja("Penury"))
      bindings.unbind("ctx:light-arts:1", "l", 3)
      assert.is_nil(world.files.SCH.contexts["light-arts"])
    end)

    it("unbinds through the same prefixes without touching other layers", function()
      local bindings = build({
        files = {
          SCH = {
            sets = { [1] = { left = { [3] = record("Base") } } },
            contexts = { ["light-arts"] = { [1] = { left = { [3] = ja("Penury") } } } },
          },
        },
      })
      bindings.set_job("SCH")
      bindings.update_buffs({ 358 })
      assert.is_true(bindings.unbind("ctx:light-arts:1", "l", 3))
      assert.equal("Base", bindings.resolve(1, "left", 3).action)
      assert.is_true(bindings.unbind(1, "l", 3))
      assert.is_nil(bindings.resolve(1, "left", 3))
    end)
  end)

  describe("job()", function()
    -- The CLI's read-side job check: `list` needs the scope's name for its
    -- header, and every verb needs to tell "not scoped yet" from "scoped".
    it("answers nothing before a job is scoped", function()
      local bindings = build()
      assert.is_nil(bindings.job())
    end)

    it("answers the scoped main and subjob", function()
      local bindings = build()
      bindings.set_job("SCH", "RDM")
      local main, sub = bindings.job()
      assert.equal("SCH", main)
      assert.equal("RDM", sub)
      bindings.set_job("WAR")
      main, sub = bindings.job()
      assert.equal("WAR", main)
      assert.is_nil(sub)
    end)
  end)

  describe("layers_at", function()
    -- The CLI's inspection read: what is STORED at an address, whether or
    -- not it is live. resolve() answers only the winner through the ACTIVE
    -- stack, so a listing built on it reports an inactive context layer as
    -- nothing at all.
    it("reports every stored layer in stack order, base first", function()
      local bindings = build()
      bindings.set_job("SCH", "NIN")
      bindings.bind(1, "l", 3, record("Savage Blade"))
      bindings.bind("sub:1", "l", 3, ja("Provoke"))
      bindings.bind("ctx:light-arts:1", "l", 3, ja("Penury"))
      bindings.bind("ctx:addendum-white:1", "l", 3, ja("Addendum: White"))
      local layers = bindings.layers_at(1, "left", 3)
      assert.equal(4, #layers)
      assert.same({ "base", "sub:NIN", "ctx:light-arts", "ctx:addendum-white" }, {
        layers[1].source,
        layers[2].source,
        layers[3].source,
        layers[4].source,
      })
      assert.equal("Savage Blade", layers[1].entry.action)
      assert.equal("Addendum: White", layers[4].entry.action)
    end)

    it("marks the layer that is currently winning, and none when none is", function()
      local bindings = build()
      bindings.set_job("SCH", "NIN")
      bindings.bind(1, "l", 3, record("Savage Blade"))
      bindings.bind("ctx:light-arts:1", "l", 3, ja("Penury"))
      local layers = bindings.layers_at(1, "left", 3)
      assert.is_true(layers[1].active, "with no buffs up the base wins")
      assert.is_falsy(layers[2].active)
      bindings.update_buffs({ 358 })
      layers = bindings.layers_at(1, "left", 3)
      assert.is_falsy(layers[1].active)
      assert.is_true(layers[2].active, "Light Arts up: the context wins")
    end)

    it("orders several subjob layers by name, not by table order", function()
      -- pairs over the subjob map answers WHM before NIN for this very
      -- table; a listing that shuffled between calls would be unreadable.
      local bindings = build({
        files = {
          SCH = {
            sets = {},
            sub = {
              WHM = { [1] = { left = { [2] = ja("Divine Seal") } } },
              NIN = { [1] = { left = { [2] = ja("Utsusemi") } } },
            },
          },
        },
      })
      bindings.set_job("SCH", "NIN")
      local layers = bindings.layers_at(1, "left", 2)
      assert.equal(2, #layers)
      assert.equal("sub:NIN", layers[1].source)
      assert.equal("sub:WHM", layers[2].source)
      assert.is_true(layers[1].active, "the worn one is the live one")
    end)

    it("shows a subjob layer belonging to a subjob that is not worn", function()
      local bindings = build({
        files = { SCH = { sets = {}, sub = { NIN = { [1] = { left = { [2] = ja("Utsusemi") } } } } } },
      })
      bindings.set_job("SCH", "WHM")
      local layers = bindings.layers_at(1, "left", 2)
      assert.equal(1, #layers)
      assert.equal("sub:NIN", layers[1].source)
      assert.is_falsy(layers[1].active, "another subjob's layer is stored, not live")
      assert.is_nil(bindings.resolve(1, "left", 2), "and resolve still ignores it")
    end)

    it("names a shared set's base by its store", function()
      local flags = default_flags()
      flags[6].shared = true
      local bindings = build({ set_flags = flags })
      bindings.set_job("SCH")
      bindings.bind(6, "r", 1, record("Shared WS"))
      local layers = bindings.layers_at(6, "right", 1)
      assert.equal("shared", layers[1].source)
      assert.is_true(layers[1].active)
    end)

    it("answers an empty list for an empty address, a bad side and no job", function()
      local bindings = build()
      assert.same({}, bindings.layers_at(1, "left", 1), "no job scoped")
      bindings.set_job("SCH")
      assert.same({}, bindings.layers_at(1, "left", 1))
      assert.same({}, bindings.layers_at(1, "middle", 1))
    end)
  end)

  describe("entry_at", function()
    -- The CLI's read half: alias/icon edit the entry the ADDRESSED layer
    -- holds, not whatever the stack currently resolves to.
    it("reads the addressed layer, ignoring the layers above it", function()
      local bindings = build()
      bindings.set_job("WAR", "NIN")
      bindings.bind(1, "l", 2, record("Base WS"))
      bindings.bind("sub:1", "l", 2, ja("Provoke"))
      assert.equal("Base WS", bindings.entry_at(1, "l", 2).action)
      assert.equal("Provoke", bindings.entry_at("sub:1", "l", 2).action)
      assert.equal("Provoke", bindings.resolve(1, "left", 2).action, "the stack still answers the subjob layer")
    end)

    it("reads a context layer and a shared set's own store", function()
      local flags = default_flags()
      flags[6].shared = true
      local bindings = build({ set_flags = flags })
      bindings.set_job("SCH")
      bindings.bind("ctx:light-arts:1", "r", 3, ja("Addendum: White"))
      bindings.bind(6, "r", 1, record("Shared WS"))
      assert.equal("Addendum: White", bindings.entry_at("ctx:light-arts:1", "r", 3).action)
      assert.equal("Shared WS", bindings.entry_at(6, "r", 1).action)
    end)

    it("answers nil for an empty address and never materializes it", function()
      local bindings, world = build()
      bindings.set_job("WAR")
      assert.is_nil(bindings.entry_at(1, "l", 1))
      assert.is_nil(bindings.entry_at("sub:1", "l", 1))
      assert.same({}, world.saved, "a read writes nothing")
      bindings.bind(2, "l", 1, record("Upheaval"))
      assert.is_nil(world.files.WAR.sets[1], "no husk set was built by the read")
    end)

    it("hints on a bad address like the write verbs do", function()
      local bindings = build()
      bindings.set_job("WAR")
      for _, address in ipairs({ { 9, "l", 1 }, { 1, "x", 1 }, { 1, "l", 9 }, { "ctx:bogus:1", "l", 1 } }) do
        local entry, err = bindings.entry_at(address[1], address[2], address[3])
        assert.is_nil(entry)
        assert.is_string(err)
      end
    end)

    it("refuses before a job is scoped", function()
      local bindings = build()
      local entry, err = bindings.entry_at(1, "l", 1)
      assert.is_nil(entry)
      assert.is_string(err)
    end)
  end)

  describe("swap", function()
    it("exchanges the whole stack between two addresses", function()
      local bindings, world = build({
        files = {
          SCH = {
            sets = { [1] = { left = { [1] = record("A Base") }, right = { [2] = record("B Base") } } },
            sub = { RDM = { [1] = { left = { [1] = ja("A Sub") } } } },
            contexts = { ["light-arts"] = { [1] = { right = { [2] = ja("B Ctx") } } } },
          },
        },
      })
      bindings.set_job("SCH", "RDM")
      assert.is_true(bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 1, side = "r", slot = 2 }))
      -- Every layer's entry moved: the bases exchanged...
      assert.equal("B Base", bindings.resolve(1, "left", 1).action)
      assert.equal("A Base", world.files.SCH.sets[1].right[2].action)
      -- ...the subjob override followed its slot (and still outranks the base)...
      local entry, source = bindings.resolve(1, "right", 2)
      assert.equal("A Sub", entry.action)
      assert.equal("sub", source)
      -- ...and so did the context override.
      bindings.update_buffs({ 358 })
      assert.equal("B Ctx", bindings.resolve(1, "left", 1).action)
    end)

    it("swaps across the shared/job store boundary and saves both files", function()
      local flags = default_flags()
      flags[6].shared = true
      local bindings, world = build({
        files = {
          WAR = { sets = { [1] = { left = { [1] = record("Job WS") } } } },
          SHARED = { sets = { [6] = { right = { [2] = record("Shared WS") } } } },
        },
        set_flags = flags,
      })
      bindings.set_job("WAR")
      assert.is_true(bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 6, side = "r", slot = 2 }))
      assert.equal("Shared WS", world.files.WAR.sets[1].left[1].action)
      assert.equal("Job WS", world.files.SHARED.sets[6].right[2].action)
      assert.is_number(world.saved.WAR)
      assert.is_number(world.saved.SHARED)
    end)

    it("moves into an empty stack", function()
      local bindings = build({
        files = { WAR = { sets = { [1] = { left = { [1] = record("Only") } } } } },
      })
      bindings.set_job("WAR")
      assert.is_true(bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 2, side = "l", slot = 5 }))
      assert.is_nil(bindings.resolve(1, "left", 1))
      assert.equal("Only", bindings.resolve(2, "left", 5).action)
    end)

    it("treats the same address as a content no-op", function()
      local bindings = build({
        files = { WAR = { sets = { [1] = { left = { [1] = record("Only") } } } } },
      })
      bindings.set_job("WAR")
      assert.is_true(bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 1, side = "left", slot = 1 }))
      assert.equal("Only", bindings.resolve(1, "left", 1).action)
    end)

    it("rejects an out-of-range address", function()
      local bindings = build()
      bindings.set_job("WAR")
      local ok, err = bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 9, side = "l", slot = 1 })
      assert.is_nil(ok)
      assert.is_string(err)
    end)

    it("writes no empty scaffolding into layers with nothing at either address", function()
      local bindings, world = build({
        files = {
          SCH = {
            sets = { [1] = { left = { [1] = record("A") } } },
            sub = { RDM = { [2] = { left = { [1] = ja("Elsewhere") } } } },
            contexts = { ["light-arts"] = { [2] = { left = { [1] = ja("Elsewhere") } } } },
          },
        },
      })
      bindings.set_job("SCH", "RDM")
      assert.is_true(bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 3, side = "l", slot = 1 }))
      -- The base entry moved; every untouched layer stays exactly as it was.
      assert.equal("A", world.files.SCH.sets[3].left[1].action)
      assert.is_nil(world.files.SCH.sets[1])
      assert.is_nil(world.files.SCH.sub.RDM[1])
      assert.is_nil(world.files.SCH.sub.RDM[3])
      assert.is_nil(world.files.SCH.contexts["light-arts"][1])
      assert.is_nil(world.files.SCH.contexts["light-arts"][3])
    end)

    it("never writes SHARED for a swap between two job sets", function()
      local bindings, world = build({
        files = { WAR = { sets = { [1] = { left = { [1] = record("One") } } } } },
      })
      bindings.set_job("WAR")
      assert.is_true(bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 2, side = "l", slot = 1 }))
      assert.is_nil(world.saved.SHARED)
      assert.is_number(world.saved.WAR)
    end)

    it("swaps two slots within the same set and side", function()
      local bindings = build({
        files = {
          WAR = { sets = { [1] = { left = { [1] = record("One"), [2] = record("Two") } } } },
        },
      })
      bindings.set_job("WAR")
      assert.is_true(bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 1, side = "l", slot = 2 }))
      assert.equal("Two", bindings.resolve(1, "left", 1).action)
      assert.equal("One", bindings.resolve(1, "left", 2).action)
    end)
  end)

  describe("copy", function()
    it("seeds this job's bindings from another job's file", function()
      local bindings, world = build({
        files = {
          WAR = {
            active_set = 5,
            sets = { [1] = { left = { [1] = record("War WS") } } },
            sub = { NIN = { [1] = { left = { [2] = ja("Provoke") } } } },
            contexts = { ["light-arts"] = { [1] = { left = { [3] = ja("Penury") } } } },
          },
        },
      })
      bindings.set_job("DRK", "NIN")
      assert.is_true(bindings.copy_from("WAR"))
      assert.equal("War WS", bindings.resolve(1, "left", 1).action)
      assert.equal("Provoke", bindings.resolve(1, "left", 2).action)
      -- Bindings copy; UI state does not -- the source sits on set 5.
      assert.equal(1, bindings.active_set())
      assert.equal("War WS", world.files.DRK.sets[1].left[1].action)
      -- The copy is by value: editing DRK afterwards must not touch WAR.
      bindings.bind(1, "l", 1, record("Torcleaver"))
      assert.equal("War WS", world.files.WAR.sets[1].left[1].action)
    end)

    it("refuses a job with no bindings file", function()
      local bindings = build()
      bindings.set_job("DRK")
      local ok, err = bindings.copy_from("PUP")
      assert.is_nil(ok)
      assert.is_string(err)
    end)

    it("never writes another job's file", function()
      local bindings, world = build({
        files = { WAR = { sets = { [1] = { left = { [1] = record("War WS") } } } } },
      })
      bindings.set_job("DRK")
      bindings.copy_from("WAR")
      bindings.bind(2, "l", 1, record("Torcleaver"))
      bindings.jump(3)
      assert.is_nil(world.saved.WAR)
      assert.is_number(world.saved.DRK)
    end)
  end)

  describe("before any job is scoped", function()
    -- CB5: the store-writing verbs must never run before set_job - the widget
    -- attaches before the client can name the job, and a save then would land
    -- in a file named nil.
    it("refuses every store-writing verb with a hint, and never saves", function()
      local bindings, world = build()
      local verbs = {
        function()
          return bindings.bind(1, "l", 1, record("Savage Blade"))
        end,
        function()
          return bindings.unbind(1, "l", 1)
        end,
        function()
          return bindings.swap({ set = 1, side = "l", slot = 1 }, { set = 1, side = "l", slot = 2 })
        end,
        function()
          return bindings.jump(2)
        end,
        function()
          return bindings.cycle()
        end,
        function()
          return bindings.copy_from("WAR")
        end,
      }
      for index, verb in ipairs(verbs) do
        local ok, hint = verb()
        assert.is_nil(ok, "verb " .. index .. " must refuse")
        assert.is_string(hint, "verb " .. index .. " must hint")
      end
      assert.same({}, world.saved, "nothing may be written before a job is scoped")
    end)

    it("resolves nothing rather than crashing", function()
      local bindings = build()
      assert.is_nil(bindings.resolve(1, "left", 1))
    end)
  end)
  describe("swapping a slot with itself", function()
    it("writes nothing to disk", function()
      -- Behaviourally a no-op either way, and that is exactly why the
      -- short-circuit keeps being deleted as redundant: what it saves is
      -- the DISK WRITE, so the counter is what pins it, not the bindings.
      local bindings, world = build({ files = { WAR = { sets = { [1] = { left = { [3] = ja("Provoke") } } } } } })
      bindings.set_job("WAR")
      world.saved.WAR = 0
      local here = { set = 1, side = "l", slot = 3 }
      assert.is_true(bindings.swap(here, { set = 1, side = "left", slot = 3 }))
      assert.are.equal(0, world.saved.WAR, "a slot swapped with itself is not a change")
      assert.are.same(ja("Provoke"), bindings.resolve(1, "l", 3), "and it is still there")
    end)

    it("still writes when either end differs", function()
      local bindings, world = build({ files = { WAR = { sets = { [1] = { left = { [3] = ja("Provoke") } } } } } })
      bindings.set_job("WAR")
      world.saved.WAR = 0
      assert.is_true(bindings.swap({ set = 1, side = "l", slot = 3 }, { set = 1, side = "l", slot = 4 }))
      assert.are.equal(1, world.saved.WAR)
    end)
  end)

  describe("a store that is not what it should be", function()
    it("survives a cyclic hand-written config instead of blowing the stack", function()
      -- A `.lua` config file is code, and a hand-written one can name
      -- itself. lib/settings' posture is to drop the broken branch and keep
      -- the rest; a stack overflow inside set_job would take the whole
      -- login with it.
      local cyclic = { active_set = 2, sets = { [1] = { left = {} } } }
      cyclic.sets[1].left.loop = cyclic
      local bindings = build({ files = { WAR = cyclic } })
      assert.has_no.errors(function()
        bindings.set_job("WAR")
      end)
      assert.equal(2, bindings.active_set(), "the readable part survived")
    end)

    it("catches a WIDE cycle by identity, not by counting depth to it", function()
      -- The depth cap alone is not enough. A root named by three of its own
      -- keys branches three ways at every level, so sixteen levels is
      -- ~43 million nodes copied before the cap bites - a hang at login,
      -- which is worse than the overflow it replaced. Identity stops it at
      -- the first repeat.
      local wide = { active_set = 3, sets = { [1] = { left = {} } } }
      wide.a, wide.b, wide.c = wide, wide, wide
      local bindings = build({ files = { WAR = wide } })
      local started = os.clock()
      assert.has_no.errors(function()
        bindings.set_job("WAR")
      end)
      assert.is_true(os.clock() - started < 1, "a cycle must not be walked, however wide it is")
      assert.equal(3, bindings.active_set(), "and the readable part still survives")
    end)

    it("copies a table reached twice by different routes, both times", function()
      -- The cycle guard marks the path DOWN and unmarks coming back up, so
      -- only a true ancestor counts. A permanent `seen` would read the
      -- second appearance of a shared branch as a loop and drop a binding
      -- that was never cyclic at all.
      local shared = { type = "ja", action = "Provoke", target = "me" }
      local bindings = build({
        files = { WAR = { sets = { [1] = { left = { [3] = shared, [4] = shared } } } } },
      })
      bindings.set_job("WAR")
      assert.are.same(shared, bindings.resolve(1, "l", 3))
      assert.are.same(shared, bindings.resolve(1, "l", 4), "the second route is not a cycle")
    end)

    it("takes a job file that is not a table as no file at all", function()
      -- copy_from already type-checks what it loaded; set_job did not, and
      -- a hand-broken store handed it straight to deep_copy and then to an
      -- index.
      -- No message argument on has_no.errors: luassert reads a second
      -- argument as the error it is looking for, so passing context there
      -- turns "must not throw" into "must not throw THIS", which anything
      -- else then satisfies. The junk value goes in a pcall message below.
      for _, junk in ipairs({ "sets = {}", 42, true }) do
        local bindings = build({ files = { WAR = junk } })
        local ok, err = pcall(bindings.set_job, "WAR")
        assert.is_true(ok, tostring(junk) .. " threw: " .. tostring(err))
        assert.equal(1, bindings.active_set(), tostring(junk))
        assert.is_nil(bindings.resolve(1, "l", 3), tostring(junk))
      end
    end)

    it("takes a shared store that is not a table as no shared sets", function()
      local bindings = build({ files = { WAR = { sets = {} }, SHARED = "nope" } })
      assert.has_no.errors(function()
        bindings.set_job("WAR")
      end)
      assert.is_nil(bindings.resolve(1, "l", 3))
    end)
  end)
end)
