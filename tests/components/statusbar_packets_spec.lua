local packets = require("components/statusbar/packets")

-- Windower's decode: unix = 1009810800 + raw / 60 + k * 2^32 / 60, where the
-- raw value is 60ths of a second since the epoch, wrapped at 32 bits.
local EPOCH = 1009810800
local PERIOD = 2 ^ 32 / 60

local NOW = 1788000000 -- 2026-08-30

local function u16(value)
  return string.char(value % 256, math.floor(value / 256) % 256)
end

local function u32(value)
  local bytes = {}
  for index = 1, 4 do
    bytes[index] = string.char(value % 256)
    value = math.floor(value / 256)
  end
  return table.concat(bytes)
end

local function raw_for(expires)
  return math.floor(((expires - EPOCH) * 60) % 2 ^ 32)
end

-- A 0x063 packet of the given order: the 4-byte header, the order word (its
-- low byte at offset 0x04 is what the decode switches on), the constant word
-- at 0x06, then the type 9 body of 32 ids at 0x08 and 32 timestamps at 0x48.
local function packet(kind, entries)
  local ids, times = {}, {}
  for slot = 1, 32 do
    local entry = entries[slot]
    ids[slot] = u16(entry and entry.id or 255)
    times[slot] = u32(entry and raw_for(entry.expires) or 0)
  end
  return string.char(0x63, 0x00, 0x00, 0x00) .. u16(kind) .. u16(0x00C4) .. table.concat(ids) .. table.concat(times)
end

describe("statusbar packets", function()
  it("names the packet the durations ride", function()
    assert.are.equal(0x063, packets.BUFF_DURATIONS)
  end)

  it("ignores the other orders of 0x063", function()
    assert.is_nil(packets.parse_buff_durations(packet(0x02, {}), NOW))
    assert.is_nil(packets.parse_buff_durations(packet(0x05, {}), NOW))
  end)

  it("ignores a packet too short to hold the arrays", function()
    assert.is_nil(packets.parse_buff_durations(packet(0x09, {}):sub(1, 100), NOW))
    assert.is_nil(packets.parse_buff_durations(nil, NOW))
  end)

  it("decodes each slot's id and expiry, skipping the empty ones", function()
    local parsed = packets.parse_buff_durations(
      packet(0x09, { { id = 33, expires = NOW + 300 }, { id = 2, expires = NOW + 5 } }),
      NOW
    )
    assert.are.equal(2, #parsed)
    assert.are.equal(33, parsed[1].id)
    assert.is_true(math.abs(parsed[1].expires - (NOW + 300)) < 1)
    assert.are.equal(2, parsed[2].id)
    assert.is_true(math.abs(parsed[2].expires - (NOW + 5)) < 1)
  end)

  it("treats 0xFFFF as an empty slot too", function()
    local body = packet(0x09, {})
    local patched = body:sub(1, 8) .. u16(0xFFFF) .. body:sub(11)
    assert.are.same({}, packets.parse_buff_durations(patched, NOW))
  end)

  it("keeps duplicate ids in slot order", function()
    local parsed = packets.parse_buff_durations(
      packet(0x09, { { id = 33, expires = NOW + 10 }, { id = 33, expires = NOW + 20 } }),
      NOW
    )
    assert.are.equal(2, #parsed)
    assert.is_true(parsed[1].expires < parsed[2].expires)
  end)

  -- The raw value wraps every 2.27 years; Windower hardcodes the wrap count and
  -- bumps it by hand. Picking the wrap nearest to now needs no bump.
  it("resolves the 32-bit wrap to the expiry nearest now", function()
    local far_future = NOW + 3 * PERIOD + 300
    local parsed = packets.parse_buff_durations(packet(0x09, { { id = 33, expires = far_future } }), far_future - 300)
    assert.is_true(math.abs(parsed[1].expires - far_future) < 1)
    local recent = packets.parse_buff_durations(packet(0x09, { { id = 33, expires = NOW - 100 } }), NOW)
    assert.is_true(math.abs(recent[1].expires - (NOW - 100)) < 1)
  end)

  -- A zero timestamp is the natural sentinel for a buff with no expiry; on
  -- the nearest wrap it decodes to some fixed date, which for a few days
  -- every 2.27 years would sit inside the plausible band and count down.
  it("reads a zero timestamp as no expiry at all", function()
    local body = packet(0x09, { { id = 33, expires = NOW + 60 } })
    local zeroed = body:sub(1, 0x48) .. u32(0) .. body:sub(0x48 + 5)
    local parsed = packets.parse_buff_durations(zeroed, NOW)
    assert.are.equal(33, parsed[1].id)
    assert.is_false(parsed[1].expires)
    local maxed = body:sub(1, 0x48) .. u32(0xFFFFFFFF) .. body:sub(0x48 + 5)
    assert.is_false(packets.parse_buff_durations(maxed, NOW)[1].expires)
  end)

  it("keeps a real KO (id 0) rather than mistaking it for empty", function()
    local parsed = packets.parse_buff_durations(packet(0x09, { { id = 0, expires = NOW + 60 } }), NOW)
    assert.are.equal(0, parsed[1].id)
  end)
end)
