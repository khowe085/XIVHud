local new_settings = require("lib/settings")
local fakes = require("tests/support/fakes")

describe("settings", function()
  local fs, notices, service

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
    it("resolves a component file under the character's data dir", function()
      local handle = service.register("parambar", {})
      service.set_character("Azureblood")
      assert.are.equal("data/Azureblood/parambar.lua", handle.path())
      assert.are.equal("data/Azureblood/parambar", handle.dir())
    end)

    it("has no path before a character is known", function()
      local handle = service.register("parambar", {})
      assert.is_nil(handle.path())
      assert.is_nil(handle.get())
      assert.is_false(handle.loaded())
    end)

    it("refuses to register the same component twice", function()
      service.register("parambar", {})
      assert.has_error(function()
        service.register("parambar", {})
      end)
    end)
  end)

  describe("defaults", function()
    it("gives a fresh component its defaults when no file exists", function()
      local handle = service.register("core", { snap = 10, slot = "default" })
      service.set_character("Azureblood")
      assert.are.same({ snap = 10, slot = "default" }, handle.get())
    end)

    it("does not share the defaults table between handles or reloads", function()
      local defaults = { bar = { width = 132 } }
      local one = service.register("one", defaults)
      local two = service.register("two", defaults)
      service.set_character("Azureblood")
      one.get().bar.width = 999
      assert.are.equal(132, two.get().bar.width)
      assert.are.equal(132, defaults.bar.width)
    end)

    it("keeps user values and adds newly introduced default keys", function()
      fs.put("data/Azureblood/parambar.lua", "return { compact = true, bar = { width = 100 } }")
      local defaults = { compact = false, dim_tp_bar = true, bar = { width = 132, spacing = 18 } }
      local handle = service.register("parambar", defaults)
      service.set_character("Azureblood")
      assert.are.same({ compact = true, dim_tp_bar = true, bar = { width = 100, spacing = 18 } }, handle.get())
    end)

    it("preserves user keys the defaults never mention", function()
      fs.put("data/Azureblood/parambar.lua", "return { slots = { raid = { scale = 2 } } }")
      local handle = service.register("parambar", { slots = { default = { scale = 1 } } })
      service.set_character("Azureblood")
      assert.are.same({ slots = { default = { scale = 1 }, raid = { scale = 2 } } }, handle.get())
    end)

    it("lets a user scalar win over a default table", function()
      fs.put("data/Azureblood/parambar.lua", "return { bar = 5 }")
      local handle = service.register("parambar", { bar = { width = 132 } })
      service.set_character("Azureblood")
      assert.are.equal(5, handle.get().bar)
    end)
  end)

  describe("persistence", function()
    it("writes the current table to the component's own file", function()
      local handle = service.register("parambar", { compact = false })
      service.set_character("Azureblood")
      handle.get().compact = true
      assert.is_true(handle.save())
      assert.are.equal("return {\n  compact = true,\n}\n", fs.files["data/Azureblood/parambar.lua"])
    end)

    it("round-trips a saved config on the next load", function()
      local handle = service.register("parambar", { bar = { width = 132 } })
      service.set_character("Azureblood")
      handle.get().bar.width = 200
      handle.save()

      local reloaded = new_settings({ read_file = fs.read_file, write_file = fs.write_file, notify = print })
      local other = reloaded.register("parambar", { bar = { width = 132 } })
      reloaded.set_character("Azureblood")
      assert.are.equal(200, other.get().bar.width)
    end)

    it("does not write anything while logged out", function()
      local handle = service.register("parambar", { compact = false })
      assert.is_false(handle.save())
      assert.are.same({}, fs.files)
    end)

    it("restores defaults and persists them on reset", function()
      local handle = service.register("parambar", { compact = false })
      service.set_character("Azureblood")
      handle.get().compact = true
      handle.save()
      handle.reset()
      assert.is_false(handle.get().compact)
      assert.are.equal("return {\n  compact = false,\n}\n", fs.files["data/Azureblood/parambar.lua"])
    end)

    it("reports a write failure instead of raising", function()
      fs.fail_writes = true
      local handle = service.register("parambar", { compact = false })
      service.set_character("Azureblood")
      assert.is_false(handle.save())
      assert.are.equal(1, #notices)
    end)
  end)

  describe("character switching", function()
    it("reloads every handle from the new character's dir", function()
      fs.put("data/Alpha/parambar.lua", "return { compact = true }")
      fs.put("data/Bravo/parambar.lua", "return { compact = false }")
      local handle = service.register("parambar", { compact = false })

      service.set_character("Alpha")
      assert.is_true(handle.get().compact)
      service.set_character("Bravo")
      assert.is_false(handle.get().compact)
      assert.are.equal("data/Bravo/parambar.lua", handle.path())
    end)

    it("drops loaded config on logout", function()
      local handle = service.register("parambar", { compact = false })
      service.set_character("Alpha")
      service.set_character(nil)
      assert.is_nil(handle.get())
      assert.is_nil(service.character())
    end)

    it("loads immediately for components registered after login", function()
      fs.put("data/Alpha/late.lua", "return { n = 7 }")
      service.set_character("Alpha")
      local handle = service.register("late", { n = 1 })
      assert.are.equal(7, handle.get().n)
    end)

    it("re-reads every handle from disk on demand", function()
      local handle = service.register("parambar", { compact = false })
      service.set_character("Alpha")
      handle.get().compact = true

      fs.put("data/Alpha/parambar.lua", "return { compact = false, bar = { width = 200 } }")
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
      service.set_character("Alpha")
      handle.get().compact = true
      service.set_character("Alpha")
      assert.is_true(handle.get().compact)
    end)
  end)

  describe("sandboxed loading", function()
    it("falls back to defaults and warns on a malformed file", function()
      fs.put("data/Alpha/parambar.lua", "return { this is not lua")
      local handle = service.register("parambar", { compact = false })
      service.set_character("Alpha")
      assert.are.same({ compact = false }, handle.get())
      assert.are.equal(1, #notices)
    end)

    it("falls back to defaults when the chunk returns a non-table", function()
      fs.put("data/Alpha/parambar.lua", "return 42")
      local handle = service.register("parambar", { compact = false })
      service.set_character("Alpha")
      assert.are.same({ compact = false }, handle.get())
      assert.are.equal(1, #notices)
    end)

    it("denies config files access to globals", function()
      fs.put("data/Alpha/parambar.lua", "return { leaked = tostring ~= nil, addon = _G ~= nil }")
      local handle = service.register("parambar", { compact = false })
      service.set_character("Alpha")
      assert.is_false(handle.get().leaked)
      assert.is_false(handle.get().addon)
    end)

    it("survives a config file containing a cycle", function()
      fs.put("data/Alpha/parambar.lua", "local t = {} t.self = t return { x = t }")
      local handle = service.register("parambar", { compact = false })
      service.set_character("Alpha")
      assert.are.same({ compact = false }, handle.get())
      assert.are.equal(1, #notices)
    end)

    it("survives a config file that raises", function()
      fs.put("data/Alpha/parambar.lua", "error('boom')")
      local handle = service.register("parambar", { compact = false })
      service.set_character("Alpha")
      assert.are.same({ compact = false }, handle.get())
      assert.are.equal(1, #notices)
    end)
  end)
end)
