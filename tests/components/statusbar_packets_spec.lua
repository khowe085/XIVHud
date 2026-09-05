local packets = require("components/statusbar/packets")

-- Windower's decode: unix = 1009810800 + raw / 60 + k * 2^32 / 60, where the
-- raw value is 60ths of a second since the epoch, wrapped at 32 bits.
local EPOCH = 1009810800
local PERIOD = 2 ^ 32 / 60

local NOW = 1788000000 -- 2026-08-30

local function raw_for(expires)
  return math.floor(((expires - EPOCH) * 60) % 2 ^ 32)
end

-- 0x063 as the entry point's packets.parse hands it over: the order word,
-- then for order 9 the 32 ids and 32 raw timestamps under Windower's array
-- labels. An absent entry is the empty slot marker with a zero timestamp.
local function packet(kind, entries)
  local parsed = { Order = kind }
  for slot = 1, 32 do
    local entry = entries[slot]
    parsed["Buffs " .. slot] = entry and entry.id or 255
    parsed["Time " .. slot] = entry and raw_for(entry.expires) or 0
  end
  return parsed
end

describe("statusbar packets", function()
  it("names the packet the durations ride", function()
    assert.are.equal(0x063, packets.BUFF_DURATIONS)
  end)

  it("ignores the other orders of 0x063", function()
    assert.is_nil(packets.buff_durations(packet(0x02, {}), NOW))
    assert.is_nil(packets.buff_durations(packet(0x05, {}), NOW))
  end)

  it("ignores a parse that failed, or one without the arrays", function()
    assert.is_nil(packets.buff_durations(nil, NOW))
    assert.is_nil(packets.buff_durations("raw bytes", NOW))
    assert.is_nil(packets.buff_durations({ Order = 9 }, NOW))
  end)

  it("decodes each slot's id and expiry, skipping the empty ones", function()
    local parsed =
      packets.buff_durations(packet(0x09, { { id = 33, expires = NOW + 300 }, { id = 2, expires = NOW + 5 } }), NOW)
    assert.are.equal(2, #parsed)
    assert.are.equal(33, parsed[1].id)
    assert.is_true(math.abs(parsed[1].expires - (NOW + 300)) < 1)
    assert.are.equal(2, parsed[2].id)
    assert.is_true(math.abs(parsed[2].expires - (NOW + 5)) < 1)
  end)

  it("treats 0xFFFF as an empty slot too", function()
    local parsed = packet(0x09, {})
    parsed["Buffs 1"] = 0xFFFF
    assert.are.same({}, packets.buff_durations(parsed, NOW))
  end)

  it("keeps duplicate ids in slot order", function()
    local parsed =
      packets.buff_durations(packet(0x09, { { id = 33, expires = NOW + 10 }, { id = 33, expires = NOW + 20 } }), NOW)
    assert.are.equal(2, #parsed)
    assert.is_true(parsed[1].expires < parsed[2].expires)
  end)

  -- The raw value wraps every 2.27 years; Windower hardcodes the wrap count and
  -- bumps it by hand. Picking the wrap nearest to now needs no bump.
  it("resolves the 32-bit wrap to the expiry nearest now", function()
    local far_future = NOW + 3 * PERIOD + 300
    local parsed = packets.buff_durations(packet(0x09, { { id = 33, expires = far_future } }), far_future - 300)
    assert.is_true(math.abs(parsed[1].expires - far_future) < 1)
    local recent = packets.buff_durations(packet(0x09, { { id = 33, expires = NOW - 100 } }), NOW)
    assert.is_true(math.abs(recent[1].expires - (NOW - 100)) < 1)
  end)

  -- A zero timestamp is the natural sentinel for a buff with no expiry; on
  -- the nearest wrap it decodes to some fixed date, which for a few days
  -- every 2.27 years would sit inside the plausible band and count down.
  it("reads a zero timestamp as no expiry at all", function()
    local parsed = packet(0x09, { { id = 33, expires = NOW + 60 } })
    parsed["Time 1"] = 0
    local decoded = packets.buff_durations(parsed, NOW)
    assert.are.equal(33, decoded[1].id)
    assert.is_false(decoded[1].expires)
    parsed["Time 1"] = 0xFFFFFFFF
    assert.is_false(packets.buff_durations(parsed, NOW)[1].expires)
  end)

  it("keeps a real KO (id 0) rather than mistaking it for empty", function()
    local parsed = packets.buff_durations(packet(0x09, { { id = 0, expires = NOW + 60 } }), NOW)
    assert.are.equal(0, parsed[1].id)
  end)

  it("stops at a slot the parse did not fill rather than erroring", function()
    local parsed = { Order = 9, ["Buffs 1"] = 33, ["Time 1"] = raw_for(NOW + 60) }
    assert.are.equal(1, #packets.buff_durations(parsed, NOW))
  end)
end)
