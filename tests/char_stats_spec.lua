local new_char_stats = require("lib/char_stats")

--[[ The last 0x061 per character and main job (Kevin, 2026-10-12), in memory
     and on disk, because the client sends it on a zone or a level change and
     never on request - so after a login or a reload the exp bar and the
     binder's master level had nothing to read until the player zoned. ]]

-- A full-length 0x061 (0x70 bytes) whose Main Job byte (offset 0x0C) is
-- `job_id`, with every byte a text read on Windows would mangle somewhere in
-- it. `at` sets single bytes by their packet offset.
local function packet(job_id, at)
  local bytes = {}
  for offset = 0, 0x6F do
    bytes[offset + 1] = 0
  end
  for offset, value in pairs({ [0x04] = 0x0A, [0x05] = 0x0D, [0x06] = 0x1A, [0x07] = 0xFF }) do
    bytes[offset + 1] = value
  end
  bytes[0x0C + 1], bytes[0x0D + 1], bytes[0x0E + 1], bytes[0x0F + 1] = job_id, 99, 4, 49
  for offset, value in pairs(at or {}) do
    bytes[offset + 1] = value
  end
  return string.char(unpack(bytes))
end

local function disk()
  local files, writes = {}, {}
  return {
    files = files,
    writes = writes,
    read = function(path)
      return files[path]
    end,
    write = function(path, contents)
      writes[#writes + 1] = path
      files[path] = contents
      return true
    end,
  }
end

local function build(fs)
  fs = fs or disk()
  return new_char_stats({ read = fs.read, write = fs.write }), fs
end

describe("char stats cache", function()
  it("answers the packet stored for a character's main job", function()
    local cache = build()
    local war = packet(1)
    cache.store("Tester", war)
    assert.equal(war, cache.current("Tester", "WAR"))
  end)

  it("keys a packet by the main job it carries, one per job", function()
    local cache = build()
    local war, whm = packet(1, { [0x10] = 1 }), packet(3, { [0x10] = 2 })
    cache.store("Tester", war)
    cache.store("Tester", whm)
    assert.equal(war, cache.current("Tester", "WAR"))
    assert.equal(whm, cache.current("Tester", "WHM"))
    assert.is_nil(cache.current("Tester", "BLM"))
    assert.is_nil(cache.current("Other", "WAR"), "and one set per character")
  end)

  it("persists to cache/packets/<Character>/ and reads it back after a reload", function()
    local fs = disk()
    local cache = build(fs)
    local war = packet(1)
    cache.store("Tester", war)
    assert.same({ "cache/packets/Tester/0x061_WAR.txt" }, fs.writes)
    local reloaded = build(fs)
    assert.equal(war, reloaded.current("Tester", "WAR"), "every byte, the awkward ones included")
  end)

  it("stores the bytes as hex text, so no text-mode read can mangle them", function()
    local fs = disk()
    local cache = build(fs)
    cache.store("Tester", packet(1))
    assert.is_nil(fs.files["cache/packets/Tester/0x061_WAR.txt"]:find("[^%x]"))
  end)

  --[[ 0x061 also carries max HP and MP, the added stats, attack and defence,
       which move with gear and buffs - so it arrives far more often than its
       readers need it. The newest is always held, but the disk is written
       only when a field something reads moved: the job and levels, the EXP,
       the master level, Master Breaker and the exemplar points (review,
       2026-10-12). ]]
  it("writes only when a field something reads has moved", function()
    local fs = disk()
    local cache = build(fs)
    cache.store("Tester", packet(1))
    cache.store("Tester", packet(1, { [0x04] = 0x50, [0x30] = 9, [0x66] = 0x02 }))
    assert.equal(1, #fs.writes, "max HP, attack and junk bits are not worth a write")
    assert.equal(packet(1, { [0x04] = 0x50, [0x30] = 9, [0x66] = 0x02 }), cache.current("Tester", "WAR"), "though held")
    for _, at in ipairs({ { [0x10] = 7 }, { [0x0D] = 98 }, { [0x65] = 10 }, { [0x66] = 0x01 }, { [0x6C] = 3 } }) do
      local writes = #fs.writes
      cache.store("Tester", packet(1, at))
      assert.equal(writes + 1, #fs.writes)
    end
  end)

  -- The client's own last packet is fresher than anything on disk, but only
  -- for the job it describes: after a job change it is the old job's.
  it("prefers the client's live packet when it is for the job asked", function()
    local fs = disk()
    local cache = build(fs)
    local stale, live = packet(1, { [0x10] = 1 }), packet(1, { [0x10] = 2 })
    cache.store("Tester", stale)
    assert.equal(live, cache.current("Tester", "WAR", live))
    assert.equal(live, build(fs).current("Tester", "WAR"), "and keeps it")
    assert.equal(live, cache.current("Tester", "WAR", packet(3)), "another job's is not an answer")
  end)

  it("answers the live packet alone when nothing is cached for the job", function()
    local cache = build()
    assert.is_nil(cache.current("Tester", "WAR", packet(3)))
    local live = packet(1)
    assert.equal(live, cache.current("Tester", "WAR", live))
  end)

  -- The name becomes a path segment; with no key the live packet still serves.
  it("files nothing under a character name that is not a plain word", function()
    local fs = disk()
    local cache = build(fs)
    cache.store("../Tester", packet(1))
    assert.same({}, fs.writes)
    assert.is_nil(cache.current("../Tester", "WAR"))
    assert.equal(packet(1), cache.current("../Tester", "WAR", packet(1)))
    assert.same({}, fs.writes)
  end)

  -- It writes from read paths too (the exp bar's attach, the binder's
  -- catalog), so a write that throws must not reach the caller, and one that
  -- did not land is tried again on the next packet.
  it("survives a write that throws, and retries one that failed", function()
    local fs = disk()
    local attempts = 0
    local failing = true
    local cache = new_char_stats({
      read = fs.read,
      write = function(path, contents)
        attempts = attempts + 1
        if failing then
          error("disk full")
        end
        return fs.write(path, contents)
      end,
    })
    assert.has_no.errors(function()
      cache.store("Tester", packet(1))
      assert.equal(packet(1), cache.current("Tester", "WAR", packet(1)))
    end)
    failing = false
    cache.store("Tester", packet(1))
    assert.equal(3, attempts)
    assert.same({ "cache/packets/Tester/0x061_WAR.txt" }, fs.writes)
  end)

  it("retries a write that reported failure", function()
    local fs = disk()
    local answer = false
    local cache = new_char_stats({
      read = fs.read,
      write = function(path, contents)
        fs.writes[#fs.writes + 1] = path
        fs.files[path] = answer and contents or nil
        return answer
      end,
    })
    cache.store("Tester", packet(1))
    answer = true
    cache.store("Tester", packet(1))
    assert.equal(2, #fs.writes)
  end)

  it("reads nothing out of a file that is not hex", function()
    local fs = disk()
    fs.files["cache/packets/Tester/0x061_WAR.txt"] = "not a packet"
    assert.is_nil(build(fs).current("Tester", "WAR"))
  end)

  it("ignores a packet whose job byte names no job", function()
    local fs = disk()
    local cache = build(fs)
    cache.store("Tester", packet(0))
    cache.store("Tester", packet(23))
    cache.store("Tester", "short")
    assert.same({}, fs.writes)
  end)
end)
