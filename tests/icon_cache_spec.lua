local new_icon_cache = require("lib/icon_cache")

-- An icon block of the right length; what it decodes to is icons_spec's
-- business, this spec only cares that the pipeline moves it.
local RECORD = string.rep("\0", 0x800)

-- Item 4096 (0x1000) sits first in the usable-items DAT 118/107.
local USABLE = 4096

describe("icon cache", function()
  local deps, cache, files, dat_reads, writes, exist_checks

  before_each(function()
    files = {}
    dat_reads = {}
    writes = {}
    exist_checks = 0
    deps = {
      asset = function(relative)
        return "addons/XIVHud/" .. relative
      end,
      file_exists = function(path)
        exist_checks = exist_checks + 1
        return files[path] == true
      end,
      read_dat = function(path, offset, length)
        dat_reads[#dat_reads + 1] = { path = path, offset = offset, length = length }
        return RECORD
      end,
      write_binary = function(path, contents)
        writes[#writes + 1] = { path = path, contents = contents }
        files["addons/XIVHud/" .. path] = true
        return true
      end,
      game_path = function()
        return "C:/FFXI"
      end,
    }
    cache = new_icon_cache(deps)
  end)

  --[[ The folder moved on 2026-09-27 because everything left at the old path
       was extracted at the old record size and is garbage. A fallback to it
       would put those icons straight back on screen. ]]
  it("never reads an icon from the folder it used before", function()
    files["addons/XIVHud/icons/" .. USABLE .. ".bmp"] = true
    assert.is_nil(cache.cached_icon(USABLE))

    cache.request_icon(USABLE)
    cache.drain_queue()
    assert.are.equal("icons/items/" .. USABLE .. ".bmp", writes[1].path)
  end)

  it("extracts a requested icon into icons/items/<item_id>.bmp and reports it done", function()
    cache.request_icon(USABLE)
    assert.is_true(cache.drain_queue())
    assert.are.equal("icons/items/" .. USABLE .. ".bmp", writes[1].path)
    assert.are.equal("addons/XIVHud/icons/items/" .. USABLE .. ".bmp", cache.cached_icon(USABLE))
  end)

  it("reads the DAT the game path names, at the item's own record", function()
    cache.request_icon(USABLE)
    cache.drain_queue()
    assert.are.equal("C:/FFXI/ROM/118/107.DAT", dat_reads[1].path)
    assert.are.equal(0x2BD, dat_reads[1].offset)
    assert.are.equal(0x800, dat_reads[1].length)
  end)

  it("extracts one icon per frame, not the whole queue at once", function()
    cache.request_icon(USABLE)
    cache.request_icon(USABLE + 1)
    assert.is_true(cache.drain_queue())
    assert.are.equal(1, #writes)
    assert.is_true(cache.drain_queue())
    assert.are.equal(2, #writes)
    assert.is_false(cache.drain_queue(), "an empty queue does no work")
  end)

  it("queues an item once however often it is requested", function()
    cache.request_icon(USABLE)
    cache.request_icon(USABLE)
    cache.drain_queue()
    assert.is_false(cache.drain_queue())
    assert.are.equal(1, #writes)
  end)

  it("finds an icon already on disk and remembers the answer", function()
    files["addons/XIVHud/icons/items/777.bmp"] = true
    assert.are.equal("addons/XIVHud/icons/items/777.bmp", cache.cached_icon(777))
    cache.cached_icon(777)
    assert.are.equal(1, exist_checks, "the second answer must come from memory")
  end)

  it("answers nil for an icon not on disk", function()
    assert.is_nil(cache.cached_icon(777))
  end)

  it("gives up on an icon it could not read, and stops looking on disk for it", function()
    deps.read_dat = function()
      return nil
    end
    cache.request_icon(USABLE)
    assert.is_false(cache.drain_queue())
    assert.are.equal(1, cache.abandoned_count())

    local checks = exist_checks
    assert.is_nil(cache.cached_icon(USABLE))
    assert.are.equal(checks, exist_checks, "an abandoned item must not be looked for on disk")

    cache.request_icon(USABLE)
    assert.is_false(cache.drain_queue(), "an abandoned item is not re-queued")
  end)

  it("names the items it has given up on", function()
    deps.read_dat = function()
      return nil
    end
    cache.request_icon(USABLE)
    assert.is_false(cache.is_abandoned(USABLE), "not before the attempt")
    cache.drain_queue()
    assert.is_true(cache.is_abandoned(USABLE))
    assert.is_false(cache.is_abandoned(12345))
    cache.reset()
    assert.is_false(cache.is_abandoned(USABLE), "a reset forgives - a relog is a retry")
  end)

  it("gives up once per item on a write failure too", function()
    deps.write_binary = function()
      return false
    end
    cache.request_icon(USABLE)
    assert.is_false(cache.drain_queue())
    assert.are.equal(1, cache.abandoned_count())
  end)

  it("abandons an item no DAT covers", function()
    cache.request_icon(0)
    assert.is_false(cache.drain_queue())
    assert.are.equal(1, cache.abandoned_count())
  end)

  -- A relog is a retry: the client may not have named its folder the first
  -- time, and nothing else would ever ask again.
  it("forgets the queue and the failures on reset, but keeps what is on disk", function()
    cache.request_icon(USABLE)
    cache.drain_queue()
    deps.read_dat = function()
      return nil
    end
    cache.request_icon(USABLE + 1)
    cache.request_icon(USABLE + 2)
    cache.drain_queue()
    assert.are.equal(1, cache.abandoned_count())

    cache.reset()
    assert.are.equal(0, cache.abandoned_count())
    assert.is_false(cache.drain_queue(), "the pending queue is dropped")

    local checks = exist_checks
    assert.are.equal("addons/XIVHud/icons/items/" .. USABLE .. ".bmp", cache.cached_icon(USABLE))
    assert.are.equal(checks, exist_checks, "resolved icons survive the reset")

    cache.request_icon(USABLE + 1)
    assert.is_false(cache.drain_queue(), "the failure is retryable again, and fails again")
    assert.are.equal(1, cache.abandoned_count())
  end)

  it("asks the game path per attempt, so one the client names late is used", function()
    local path = "C:/FFXI"
    deps.game_path = function()
      return path
    end
    cache.request_icon(USABLE)
    cache.drain_queue()
    path = "D:/Games/FFXI"
    cache.request_icon(USABLE + 1)
    cache.drain_queue()
    assert.are.equal("D:/Games/FFXI/ROM/118/107.DAT", dat_reads[2].path)
  end)

  --[[ A cached icon was permanent: `cached_icon` hands back whatever .bmp is on
       disk and never looks at it again, and a failed extraction is abandoned
       for the session. So a wrong icon - Almace drawn as a scythe (Kevin,
       2026-09-18) - survived every login with no way to clear it from in game.
       Forgetting one removes the file and lets the next request extract it
       afresh. ]]
  --[[ There is no way to re-extract an icon already on disk, deliberately.
       `refresh` did that and was withdrawn the day it shipped: it left the
       file in place and made `cached_icon` answer nil until the icon had been
       read again, so the grid blanked - and the re-extraction could not put it
       back, because `write_binary` opens the .bmp "wb" while the renderer
       still holds that exact file open (Kevin, 2026-09-27). Deleting instead
       is no better: three cache instances share one `icons/` directory and
       each remembers separately what it resolved, so two would be left on a
       texture that is gone, which Windower draws as silently nothing. Until
       something safer is worked out, nothing writes over a texture in use. ]]
  --[[ The diagnostic. An icon that comes out wrong was read at the wrong
       record, and none of the numbers that decide the record - the DAT, the
       index, the byte offset, how much came back - is visible from in game. ]]
  describe("probing an item", function()
    it("reports the numbers the read would use", function()
      local report = cache.probe(USABLE)
      assert.are.equal(USABLE, report.id)
      assert.are.equal("118/107", report.dat)
      assert.are.equal(0, report.record)
      assert.are.equal(0x2BD, report.offset)
      assert.are.equal("C:/FFXI/ROM/118/107.DAT", report.path)
      assert.are.equal(0x800, report.read)
      assert.is_false(report.cached)
    end)

    it("says when the icon is already on disk", function()
      cache.request_icon(USABLE)
      cache.drain_queue()
      assert.is_true(cache.probe(USABLE).cached)
    end)

    -- What the record's own first bytes hold is the whole point: it is the
    -- only evidence of WHICH item the offset actually landed on.
    it("samples the head of the record itself, not the icon", function()
      deps.read_dat = function(_, offset, length)
        return ("o%d:%d"):format(offset, length)
      end
      local report = cache.probe(USABLE)
      assert.are.equal("o0:32", report.sample_raw, "the sample starts at the record, not the icon")
    end)

    it("reports a read that came back short", function()
      deps.read_dat = function()
        return "tiny"
      end
      local report = cache.probe(USABLE)
      assert.are.equal(4, report.read)
    end)

    it("reports a read that answered nothing", function()
      deps.read_dat = function()
        return nil
      end
      local report = cache.probe(USABLE)
      assert.are.equal(0, report.read)
    end)

    it("survives an id no DAT covers", function()
      local report = cache.probe(0x8000)
      assert.are.equal(0x8000, report.id)
      assert.is_nil(report.dat)
      assert.are.equal(0, report.read)
    end)
  end)
end)
