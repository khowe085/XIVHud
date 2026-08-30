local new_settings = require("lib/settings")
local fakes = require("tests/support/fakes")

describe("settings", function()
  local fs, notices, service

  -- Scoping a component handle takes both halves: the character, then the slot
  -- read out of that character's core file. Every spec below that touches a
  -- component config goes through this.
  local function scope(name, slot)
    service.set_character(name)
    service.set_slot(slot or "default")
  end

  before_each(function()
    fs = fakes.file_system()
    notices = {}
    service = new_settings({
      read_file = fs.read_file,
      write_file = fs.write_file,
      notify = function(msg)
        notices[#notices + 1] = msg
      end,
    })
  end)

  describe("namespaces", function()
    it("gives a component its own directory inside the active slot", function()
      local handle = service.register("parambar", {})
      scope("Azureblood")
      assert.are.equal("data/Azureblood/default/parambar", handle.dir())
      assert.are.equal("data/Azureblood/default/parambar/config.lua", handle.config_path())
      assert.are.equal("data/Azureblood/default/parambar/layout.lua", handle.layout_path())
    end)

    it("moves that directory with the slot", function()
      local handle = service.register("parambar", {})
      scope("Azureblood", "raid")
      assert.are.equal("data/Azureblood/raid/parambar", handle.dir())
      assert.are.equal("data/Azureblood/raid/parambar/config.lua", handle.config_path())
    end)

    -- Core owns the active-slot pointer, so its own file cannot live inside a
    -- slot; it is character-wide, alongside the slot directories.
    it("keeps a character-scoped namespace out of the slots", function()
      local handle = service.register_character("core", {})
      service.set_character("Azureblood")
      assert.are.equal("data/Azureblood/core.lua", handle.path())
    end)

    it("has no paths before a character is known", function()
      local handle = service.register("parambar", {})
      assert.is_nil(handle.dir())
      assert.is_nil(handle.config_path())
      assert.is_nil(handle.layout_path())
      assert.is_nil(handle.get())
      assert.is_nil(handle.layout())
      assert.is_false(handle.loaded())
    end)

    -- The character is known before the slot is: the slot is read out of the
    -- character's core file, which cannot be opened until the character is.
    it("has no paths after a character but before a slot", function()
      local handle = service.register("parambar", {})
      service.set_character("Azureblood")
      assert.is_nil(handle.config_path())
      assert.is_nil(handle.get())
      assert.is_false(handle.loaded())
    end)

    it("refuses to register the same name twice, whatever the scope", function()
      service.register("parambar", {})
      assert.has_error(function()
        service.register("parambar", {})
      end)
      assert.has_error(function()
        service.register_character("parambar", {})
      end)
    end)
  end)

  describe("defaults", function()
    it("gives a fresh component its defaults when no file exists", function()
      local handle = service.register("parambar", { compact = false })
      scope("Azureblood")
      assert.are.same({ compact = false }, handle.get())
    end)

    -- The layout half of a component's defaults seeds layout.lua and is kept
    -- out of the config entirely, so a component never sees its own placement
    -- in the table it was handed and merge_defaults cannot put it back.
    it("splits the layout defaults out of the config defaults", function()
      local handle = service.register("parambar", {
        compact = false,
        layout = { pos = { x = 10, y = 20 }, scale = 1, visible = true },
      })
      scope("Azureblood")
      assert.are.same({ compact = false }, handle.get())
      assert.are.same({ pos = { x = 10, y = 20 }, scale = 1, visible = true }, handle.layout())
    end)

    it("gives a component with no layout defaults an empty layout table", function()
      local handle = service.register("parambar", { compact = false })
      scope("Azureblood")
      assert.are.same({}, handle.layout())
    end)

    it("does not share the defaults table between handles or reloads", function()
      local defaults = { bar = { width = 132 }, layout = { scale = 1 } }
      local one = service.register("one", defaults)
      local two = service.register("two", defaults)
      scope("Azureblood")
      one.get().bar.width = 999
      one.layout().scale = 4
      assert.are.equal(132, two.get().bar.width)
      assert.are.equal(1, two.layout().scale)
      assert.are.equal(132, defaults.bar.width)
      assert.are.equal(1, defaults.layout.scale)
    end)

    it("keeps user values and adds newly introduced default keys", function()
      fs.put("data/Azureblood/default/parambar/config.lua", "return { compact = true, bar = { width = 100 } }")
      local defaults = { compact = false, dim_tp_bar = true, bar = { width = 132, spacing = 18 } }
      local handle = service.register("parambar", defaults)
      scope("Azureblood")
      assert.are.same({ compact = true, dim_tp_bar = true, bar = { width = 100, spacing = 18 } }, handle.get())
    end)

    it("merges a stored layout over the layout defaults", function()
      fs.put("data/Azureblood/default/parambar/layout.lua", "return { pos = { x = 5 } }")
      local handle = service.register("parambar", { layout = { pos = { x = 1, y = 2 }, scale = 1 } })
      scope("Azureblood")
      assert.are.same({ pos = { x = 5, y = 2 }, scale = 1 }, handle.layout())
    end)

    it("preserves user keys the defaults never mention", function()
      fs.put("data/Azureblood/default/parambar/config.lua", "return { mine = { scale = 2 } }")
      local handle = service.register("parambar", { compact = false })
      scope("Azureblood")
      assert.are.same({ compact = false, mine = { scale = 2 } }, handle.get())
    end)

    it("lets a user scalar win over a default table", function()
      fs.put("data/Azureblood/default/parambar/config.lua", "return { bar = 5 }")
      local handle = service.register("parambar", { bar = { width = 132 } })
      scope("Azureblood")
      assert.are.equal(5, handle.get().bar)
    end)

    it("gives a character-scoped namespace its defaults from its own file", function()
      fs.put("data/Azureblood/core.lua", "return { snap = 20 }")
      local handle = service.register_character("core", { snap = 10, slot = "default" })
      service.set_character("Azureblood")
      assert.are.same({ snap = 20, slot = "default" }, handle.get())
    end)
  end)

  describe("persistence", function()
    it("writes the config table to config.lua and nothing else", function()
      local handle = service.register("parambar", { compact = false, layout = { scale = 1 } })
      scope("Azureblood")
      handle.get().compact = true
      assert.is_true(handle.save_config())
      assert.are.equal("return {\n  compact = true,\n}\n", fs.files["data/Azureblood/default/parambar/config.lua"])
      assert.is_nil(fs.files["data/Azureblood/default/parambar/layout.lua"])
    end)

    it("writes the layout table to layout.lua and nothing else", function()
      local handle = service.register("parambar", { compact = false, layout = { scale = 1 } })
      scope("Azureblood")
      handle.layout().scale = 2
      assert.is_true(handle.save_layout())
      assert.are.equal("return {\n  scale = 2,\n}\n", fs.files["data/Azureblood/default/parambar/layout.lua"])
      assert.is_nil(fs.files["data/Azureblood/default/parambar/config.lua"])
    end)

    it("writes both files on a plain save", function()
      local handle = service.register("parambar", { compact = false, layout = { scale = 1 } })
      scope("Azureblood")
      assert.is_true(handle.save())
      assert.is_not_nil(fs.files["data/Azureblood/default/parambar/config.lua"])
      assert.is_not_nil(fs.files["data/Azureblood/default/parambar/layout.lua"])
    end)

    it("reports a save as failed when either half could not be written", function()
      local handle = service.register("parambar", { compact = false, layout = { scale = 1 } })
      scope("Azureblood")
      fs.fail_write_paths["data/Azureblood/default/parambar/layout.lua"] = true
      assert.is_false(handle.save())
      assert.is_not_nil(fs.files["data/Azureblood/default/parambar/config.lua"], "the other half is still written")
    end)

    it("round-trips a saved config and layout on the next load", function()
      local handle = service.register("parambar", { bar = { width = 132 }, layout = { scale = 1 } })
      scope("Azureblood")
      handle.get().bar.width = 200
      handle.layout().scale = 3
      handle.save()

      local reloaded = new_settings({ read_file = fs.read_file, write_file = fs.write_file, notify = print })
      local other = reloaded.register("parambar", { bar = { width = 132 }, layout = { scale = 1 } })
      reloaded.set_character("Azureblood")
      reloaded.set_slot("default")
      assert.are.equal(200, other.get().bar.width)
      assert.are.equal(3, other.layout().scale)
    end)

    it("does not write anything while unscoped", function()
      local handle = service.register("parambar", { compact = false })
      assert.is_false(handle.save())
      assert.is_false(handle.save_config())
      assert.is_false(handle.save_layout())
      service.set_character("Azureblood")
      assert.is_false(handle.save(), "a character without a slot is still unscoped")
      assert.are.same({}, fs.files)
    end)

    it("restores defaults and persists them on reset", function()
      local handle = service.register("parambar", { compact = false, layout = { scale = 1 } })
      scope("Azureblood")
      handle.get().compact = true
      handle.layout().scale = 5
      handle.save()
      handle.reset()
      assert.is_false(handle.get().compact)
      assert.are.equal(1, handle.layout().scale)
      assert.are.equal("return {\n  compact = false,\n}\n", fs.files["data/Azureblood/default/parambar/config.lua"])
      assert.are.equal("return {\n  scale = 1,\n}\n", fs.files["data/Azureblood/default/parambar/layout.lua"])
    end)

    it("resets a character-scoped namespace to its own file", function()
      local handle = service.register_character("core", { snap = 10 })
      service.set_character("Azureblood")
      handle.get().snap = 40
      handle.save()
      handle.reset()
      assert.are.equal(10, handle.get().snap)
      assert.are.equal("return {\n  snap = 10,\n}\n", fs.files["data/Azureblood/core.lua"])
    end)

    it("reports a write failure instead of raising", function()
      fs.fail_writes = true
      local handle = service.register("parambar", { compact = false })
      scope("Azureblood")
      assert.is_false(handle.save_config())
      assert.are.equal(1, #notices)
    end)
  end)

  describe("character and slot switching", function()
    it("leaves component handles unloaded until a slot is announced", function()
      fs.put("data/Alpha/default/parambar/config.lua", "return { compact = true }")
      local handle = service.register("parambar", { compact = false })

      service.set_character("Alpha")
      assert.is_nil(handle.get(), "the slot is not known yet")
      service.set_slot("default")
      assert.is_true(handle.get().compact)
    end)

    it("reloads every component handle from the new slot's dir", function()
      fs.put("data/Alpha/default/parambar/config.lua", "return { compact = true }")
      fs.put("data/Alpha/raid/parambar/config.lua", "return { compact = false }")
      local handle = service.register("parambar", { compact = false })

      scope("Alpha")
      assert.is_true(handle.get().compact)
      service.set_slot("raid")
      assert.is_false(handle.get().compact)
      assert.are.equal("data/Alpha/raid/parambar/config.lua", handle.config_path())
      assert.are.equal("raid", service.slot())
    end)

    it("reloads every handle from the new character's dir", function()
      fs.put("data/Alpha/default/parambar/config.lua", "return { compact = true }")
      fs.put("data/Bravo/default/parambar/config.lua", "return { compact = false }")
      local handle = service.register("parambar", { compact = false })

      scope("Alpha")
      assert.is_true(handle.get().compact)
      scope("Bravo")
      assert.is_false(handle.get().compact)
    end)

    -- The slot name can be the same across a character switch, and the files
    -- underneath it are still a different character's - so announcing a slot
    -- always reads, rather than short-circuiting on an unchanged name.
    it("re-reads on an unchanged slot name after a character switch", function()
      fs.put("data/Alpha/default/parambar/config.lua", "return { compact = true }")
      fs.put("data/Bravo/default/parambar/config.lua", "return { compact = false }")
      local handle = service.register("parambar", { compact = false })

      scope("Alpha")
      service.set_character("Bravo")
      service.set_slot("default")
      assert.is_false(handle.get().compact)
    end)

    it("drops loaded config on logout", function()
      local component = service.register("parambar", { compact = false })
      local core = service.register_character("core", { snap = 10 })
      scope("Alpha")
      service.set_character(nil)
      assert.is_nil(component.get())
      assert.is_nil(core.get())
      assert.is_nil(service.character())
      assert.is_nil(service.slot())
    end)

    it("loads immediately for components registered after login", function()
      fs.put("data/Alpha/default/late/config.lua", "return { n = 7 }")
      scope("Alpha")
      local handle = service.register("late", { n = 1 })
      assert.are.equal(7, handle.get().n)
    end)

    it("re-reads every handle from disk on demand", function()
      local handle = service.register("parambar", { compact = false })
      scope("Alpha")
      handle.get().compact = true

      fs.put("data/Alpha/default/parambar/config.lua", "return { compact = false, bar = { width = 200 } }")
      service.reload()
      assert.is_false(handle.get().compact, "the in-memory edit is discarded")
      assert.are.equal(200, handle.get().bar.width)
    end)

    it("reloads to defaults while logged out", function()
      local handle = service.register("parambar", { compact = false })
      service.reload()
      assert.is_nil(handle.get())
    end)

    it("keeps unsaved edits when the same character is re-announced", function()
      local handle = service.register("parambar", { compact = false })
      scope("Alpha")
      handle.get().compact = true
      assert.is_false(service.set_character("Alpha"))
      assert.is_true(handle.get().compact)
    end)
  end)

  -- Every component owns its directory now, so the store is simply the files a
  -- component adds beside the config.lua and layout.lua core writes for it.
  describe("directory store", function()
    it("round-trips a named file under the component's own directory", function()
      local handle = service.register("crossbar", {})
      scope("Azureblood")
      assert.is_true(handle.store_save("WAR", { active_set = 3 }))
      assert.are.equal("return {\n  active_set = 3,\n}\n", fs.files["data/Azureblood/default/crossbar/WAR.lua"])
      assert.are.same({ active_set = 3 }, handle.store_load("WAR"))
    end)

    it("reads a file already on disk", function()
      fs.put("data/Azureblood/default/crossbar/SHARED.lua", "return { sets = { [6] = { left = {} } } }")
      local handle = service.register("crossbar", {})
      scope("Azureblood")
      assert.are.same({ sets = { [6] = { left = {} } } }, handle.store_load("SHARED"))
    end)

    it("answers nil for a file that does not exist", function()
      local handle = service.register("crossbar", {})
      scope("Azureblood")
      assert.is_nil(handle.store_load("WAR"))
    end)

    it("neither reads nor writes while unscoped", function()
      local handle = service.register("crossbar", {})
      assert.is_nil(handle.store_load("WAR"))
      assert.is_false(handle.store_save("WAR", { active_set = 1 }))
      assert.are.same({}, fs.files)
    end)

    it("degrades a broken file to nil plus a warning, like the config file", function()
      fs.put("data/Azureblood/default/crossbar/WAR.lua", "return { this is not lua")
      local handle = service.register("crossbar", {})
      scope("Azureblood")
      assert.is_nil(handle.store_load("WAR"))
      assert.are.equal(1, #notices)
    end)

    -- The refusal is quiet on purpose: a non-table value is the calling
    -- component's bug, and serialize would otherwise turn it into a chat
    -- notice on every attempt.
    it("refuses a non-table value without writing or complaining", function()
      local handle = service.register("crossbar", {})
      scope("Azureblood")
      assert.is_false(handle.store_save("WAR", "return {}"))
      assert.is_false(handle.store_save("WAR", nil))
      assert.are.same({}, fs.files)
      assert.are.equal(0, #notices)
    end)

    it("refuses a name that is not a plain word, rather than composing a path from it", function()
      local handle = service.register("crossbar", {})
      scope("Azureblood")
      assert.is_false(handle.store_save("../core", { snap = 1 }))
      assert.is_nil(handle.store_load("../core"))
      assert.is_nil(fs.files["data/Azureblood/default/core.lua"])
    end)

    -- config.lua and layout.lua are core's, and they sit in the very directory
    -- the store writes into: a component naming either would overwrite its own
    -- settings or its own placement.
    it("refuses the two names core owns", function()
      local handle = service.register("crossbar", { compact = false, layout = { scale = 1 } })
      scope("Azureblood")
      handle.save()
      assert.is_false(handle.store_save("config", { wiped = true }))
      assert.is_false(handle.store_save("layout", { wiped = true }))
      assert.is_nil(handle.store_load("config"))
      assert.is_nil(handle.store_load("layout"))
      assert.are.equal("return {\n  compact = false,\n}\n", fs.files["data/Azureblood/default/crossbar/config.lua"])
      assert.are.equal("return {\n  scale = 1,\n}\n", fs.files["data/Azureblood/default/crossbar/layout.lua"])
    end)

    it("re-reads from disk after reload, so a copied file is not shadowed by a stale cache", function()
      local handle = service.register("crossbar", {})
      scope("Azureblood")
      handle.store_save("WAR", { active_set = 1 })
      fs.put("data/Azureblood/default/crossbar/WAR.lua", "return { active_set = 7 }")
      service.reload()
      assert.are.equal(7, handle.store_load("WAR").active_set)
    end)

    it("switches directories with the character and the slot", function()
      fs.put("data/Alpha/default/crossbar/WAR.lua", "return { active_set = 1 }")
      fs.put("data/Bravo/default/crossbar/WAR.lua", "return { active_set = 2 }")
      fs.put("data/Bravo/raid/crossbar/WAR.lua", "return { active_set = 3 }")
      local handle = service.register("crossbar", {})
      scope("Alpha")
      assert.are.equal(1, handle.store_load("WAR").active_set)
      scope("Bravo")
      assert.are.equal(2, handle.store_load("WAR").active_set)
      service.set_slot("raid")
      assert.are.equal(3, handle.store_load("WAR").active_set)
    end)

    it("keeps one component out of another's directory", function()
      local crossbar = service.register("crossbar", {})
      local other = service.register("other", {})
      scope("Azureblood")
      crossbar.store_save("WAR", { active_set = 1 })
      assert.is_nil(other.store_load("WAR"))
      assert.is_not_nil(fs.files["data/Azureblood/default/crossbar/WAR.lua"])
    end)

    -- A reset empties the component's directory in the active slot: the extra
    -- files would silently survive a rewrite of config.lua and layout.lua.
    it("clears the whole directory on reset when it can delete files", function()
      local cleaner = new_settings({
        read_file = fs.read_file,
        write_file = fs.write_file,
        list_dir = fs.list_dir,
        delete_file = fs.delete_file,
        notify = function(msg)
          notices[#notices + 1] = msg
        end,
      })
      local handle = cleaner.register("crossbar", { snap = 1 })
      cleaner.set_character("Azureblood")
      cleaner.set_slot("default")
      handle.store_save("WAR", { active_set = 5 })
      handle.reset()
      assert.is_nil(fs.files["data/Azureblood/default/crossbar/WAR.lua"])
      assert.is_nil(handle.store_load("WAR"), "the cache must go with the files")
      assert.are.equal("return {\n  snap = 1,\n}\n", fs.files["data/Azureblood/default/crossbar/config.lua"])
    end)

    it("leaves another slot's copy of the component alone on reset", function()
      local cleaner = new_settings({
        read_file = fs.read_file,
        write_file = fs.write_file,
        list_dir = fs.list_dir,
        delete_file = fs.delete_file,
        notify = print,
      })
      fs.put("data/Azureblood/raid/crossbar/WAR.lua", "return { active_set = 9 }")
      local handle = cleaner.register("crossbar", { snap = 1 })
      cleaner.set_character("Azureblood")
      cleaner.set_slot("default")
      handle.store_save("WAR", { active_set = 5 })
      handle.reset()
      assert.is_nil(fs.files["data/Azureblood/default/crossbar/WAR.lua"])
      assert.is_not_nil(fs.files["data/Azureblood/raid/crossbar/WAR.lua"])
    end)

    it("never asks the file system to delete a dot entry", function()
      -- `windower.get_dir` returns `.` and `..` among the real entries, and
      -- deleting `data/<Character>/<slot>/crossbar/..` would aim the delete at
      -- the whole slot. core.delete_tree is pinned the same way; this is the
      -- store's own copy of that guard.
      local cleaner = new_settings({
        read_file = fs.read_file,
        write_file = fs.write_file,
        list_dir = function()
          return { ".", "..", "WAR.lua" }
        end,
        delete_file = fs.delete_file,
        notify = function(msg)
          notices[#notices + 1] = msg
        end,
      })
      local handle = cleaner.register("crossbar", { snap = 1 })
      cleaner.set_character("Azureblood")
      cleaner.set_slot("default")
      handle.store_save("WAR", { active_set = 5 })
      handle.reset()
      for _, path in ipairs(fs.deletes) do
        assert.is_nil(path:find(".", #path, true) and path:match("%.%.?$"), "aimed at a dot entry: " .. path)
      end
      assert.is_true(#fs.deletes > 0, "the real entry is still deleted")
      assert.is_nil(fs.files["data/Azureblood/default/crossbar/WAR.lua"])
    end)

    it("still resets the two core files when it cannot list directories", function()
      local handle = service.register("crossbar", { snap = 1, layout = { scale = 1 } })
      scope("Azureblood")
      handle.store_save("WAR", { active_set = 5 })
      assert.has_no.errors(function()
        handle.reset()
      end)
      assert.is_not_nil(fs.files["data/Azureblood/default/crossbar/config.lua"])
      assert.is_not_nil(fs.files["data/Azureblood/default/crossbar/layout.lua"])
    end)
  end)

  describe("sandboxed loading", function()
    it("falls back to defaults and warns on a malformed file", function()
      fs.put("data/Alpha/default/parambar/config.lua", "return { this is not lua")
      local handle = service.register("parambar", { compact = false })
      scope("Alpha")
      assert.are.same({ compact = false }, handle.get())
      assert.are.equal(1, #notices)
    end)

    it("falls back to defaults when the chunk returns a non-table", function()
      fs.put("data/Alpha/default/parambar/config.lua", "return 42")
      local handle = service.register("parambar", { compact = false })
      scope("Alpha")
      assert.are.same({ compact = false }, handle.get())
      assert.are.equal(1, #notices)
    end)

    it("falls back to the layout defaults on a malformed layout file", function()
      fs.put("data/Alpha/default/parambar/layout.lua", "return { this is not lua")
      local handle = service.register("parambar", { layout = { scale = 1 } })
      scope("Alpha")
      assert.are.same({ scale = 1 }, handle.layout())
      assert.are.equal(1, #notices)
    end)

    it("denies config files access to globals", function()
      fs.put("data/Alpha/default/parambar/config.lua", "return { leaked = tostring ~= nil, addon = _G ~= nil }")
      local handle = service.register("parambar", { compact = false })
      scope("Alpha")
      assert.is_false(handle.get().leaked)
      assert.is_false(handle.get().addon)
    end)

    it("survives a config file containing a cycle", function()
      fs.put("data/Alpha/default/parambar/config.lua", "local t = {} t.self = t return { x = t }")
      local handle = service.register("parambar", { compact = false })
      scope("Alpha")
      assert.are.same({ compact = false }, handle.get())
      assert.are.equal(1, #notices)
    end)

    it("survives a config file that raises", function()
      fs.put("data/Alpha/default/parambar/config.lua", "error('boom')")
      local handle = service.register("parambar", { compact = false })
      scope("Alpha")
      assert.are.same({ compact = false }, handle.get())
      assert.are.equal(1, #notices)
    end)
  end)
end)
