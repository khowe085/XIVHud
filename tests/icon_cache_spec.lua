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

  it("extracts a requested icon into icons/<item_id>.bmp and reports it done", function()
    cache.request_icon(USABLE)
    assert.is_true(cache.drain_queue())
    assert.are.equal("icons/" .. USABLE .. ".bmp", writes[1].path)
    assert.are.equal("addons/XIVHud/icons/" .. USABLE .. ".bmp", cache.cached_icon(USABLE))
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
    files["addons/XIVHud/icons/777.bmp"] = true
    assert.are.equal("addons/XIVHud/icons/777.bmp", cache.cached_icon(777))
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
    assert.is_false(cache.is_abandoned(USABLE), "a reset forgives - the game path may have been fixed")
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

  -- The likeliest reason an icon could not be read is a wrong game path;
  -- correcting the setting has to be worth something on the next login.
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
    assert.are.equal("addons/XIVHud/icons/" .. USABLE .. ".bmp", cache.cached_icon(USABLE))
    assert.are.equal(checks, exist_checks, "resolved icons survive the reset")

    cache.request_icon(USABLE + 1)
    assert.is_false(cache.drain_queue(), "the failure is retryable again, and fails again")
    assert.are.equal(1, cache.abandoned_count())
  end)

  it("asks the game path per attempt, so a corrected setting takes effect", function()
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
end)
