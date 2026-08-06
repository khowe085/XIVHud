local packets = require("components/partylist/packets")

-- Builds a 0x076 body the way the server lays it out: five 48-byte blocks
-- starting at byte 5, each `{ id = <player id>, buffs = { <ids> } }` or nil for
-- an empty slot. Buff i occupies a low byte at +16+i-1 and a 2-bit high pair
-- packed four-to-a-byte from +8.
local function party_buff_packet(blocks)
  local bytes = { 0, 0, 0, 0 }

  local function put(offset, value)
    bytes[offset] = value
  end

  for k = 0, 4 do
    local base = k * 48 + 5
    for offset = base, base + 47 do
      put(offset, 0)
    end

    local block = blocks[k + 1]
    if block then
      local id = block.id
      for byte = 0, 3 do
        put(base + byte, math.floor(id / 256 ^ byte) % 256)
      end
      for index = 1, 32 do
        local buff = block.buffs[index] or 255
        put(base + 16 + index - 1, buff % 256)
        local high = math.floor(buff / 256) % 4
        local packed = base + 8 + math.floor((index - 1) / 4)
        bytes[packed] = bytes[packed] + high * 4 ^ ((index - 1) % 4)
      end
    end
  end

  local out = {}
  for index = 1, 5 * 48 + 4 do
    out[index] = string.char(bytes[index] or 0)
  end
  return table.concat(out)
end

describe("partylist packets", function()
  describe("0x076 party buffs", function()
    it("reads a member's buff ids", function()
      local raw = party_buff_packet({ { id = 1234, buffs = { 33, 40, 2 } } })
      local parsed = packets.party_buffs(raw)
      assert.are.same({ 33, 40, 2 }, parsed[1234])
    end)

    it("reconstructs ids above 255 from the packed high bits", function()
      local raw = party_buff_packet({ { id = 99, buffs = { 256, 511, 767, 1023 } } })
      assert.are.same({ 256, 511, 767, 1023 }, packets.party_buffs(raw)[99])
    end)

    it("drops the empty slots rather than leaving holes in the list", function()
      local raw = party_buff_packet({ { id = 7, buffs = { 1, 2 } } })
      assert.are.equal(2, #packets.party_buffs(raw)[7])
    end)

    it("reads every occupied block and skips the empty ones", function()
      local raw = party_buff_packet({
        { id = 10, buffs = { 1 } },
        nil,
        { id = 30, buffs = { 2 } },
      })
      local parsed = packets.party_buffs(raw)
      assert.are.same({ 1 }, parsed[10])
      assert.are.same({ 2 }, parsed[30])
      assert.is_nil(parsed[0])
    end)

    it("records an empty list for a member whose buffs all dropped", function()
      local raw = party_buff_packet({ { id = 5, buffs = {} } })
      assert.are.same({}, packets.party_buffs(raw)[5])
    end)

    it("ignores a truncated packet rather than erroring", function()
      assert.are.same({}, packets.party_buffs("short"))
      assert.are.same({}, packets.party_buffs(nil))
    end)
  end)

  describe("0x0C8 alliance flags", function()
    local function alliance(entries)
      local parsed = {}
      for slot = 1, 18 do
        local entry = entries[slot] or { id = 0, flags = 0 }
        parsed["ID " .. slot] = entry.id
        parsed["Flags " .. slot] = entry.flags
      end
      return parsed
    end

    it("decodes the three flag bits independently", function()
      local roles = packets.alliance_flags(alliance({
        { id = 11, flags = 4 },
        { id = 22, flags = 8 },
        { id = 33, flags = 16 },
      }))
      assert.are.same({ leader = true, alliance_leader = false, quartermaster = false }, roles[11])
      assert.are.same({ leader = false, alliance_leader = true, quartermaster = false }, roles[22])
      assert.are.same({ leader = false, alliance_leader = false, quartermaster = true }, roles[33])
    end)

    it("decodes a member holding every role at once", function()
      local roles = packets.alliance_flags(alliance({ { id = 44, flags = 4 + 8 + 16 } }))
      assert.are.same({ leader = true, alliance_leader = true, quartermaster = true }, roles[44])
    end)

    it("ignores bits it does not own", function()
      local roles = packets.alliance_flags(alliance({ { id = 55, flags = 1 + 2 + 32 + 64 } }))
      assert.are.same({ leader = false, alliance_leader = false, quartermaster = false }, roles[55])
    end)

    it("reports every occupied slot, and only those", function()
      local roles = packets.alliance_flags(alliance({ { id = 66, flags = 0 }, nil, { id = 77, flags = 4 } }))
      assert.is_not_nil(roles[66])
      assert.is_not_nil(roles[77])
      assert.is_nil(roles[0])
    end)

    it("ignores a packet it could not parse", function()
      assert.are.same({}, packets.alliance_flags(nil))
    end)
  end)

  -- `pairs` skips a nil, so a spec that wants a field *absent* asks for it by
  -- name instead.
  local ABSENT = {}

  local function override(parsed, fields)
    for key, value in pairs(fields or {}) do
      parsed[key] = value ~= ABSENT and value or nil
    end
    return parsed
  end

  describe("0x0DD party member update", function()
    local function member(fields)
      local parsed = {
        ID = 1001,
        Index = 5,
        Name = "Tarutaru",
        Zone = 230,
        HP = 1200,
        MP = 400,
        TP = 1500,
        ["HP%"] = 80,
        ["MP%"] = 40,
        ["Main job"] = 7,
        ["Main job level"] = 99,
        ["Sub job"] = 1,
        ["Sub job level"] = 49,
      }
      return override(parsed, fields)
    end

    it("carries the identity fields", function()
      local update = packets.member_update(member())
      assert.are.equal(1001, update.id)
      assert.are.equal(5, update.index)
      assert.are.equal("Tarutaru", update.name)
      assert.are.equal(230, update.zone)
    end)

    it("carries the vitals the packet also holds", function()
      local update = packets.member_update(member())
      assert.are.same({ hp = 1200, mp = 400, hpp = 80, mpp = 40 }, update.vitals)
    end)

    it("carries main and sub job", function()
      local update = packets.member_update(member())
      assert.are.same({ main = 7, main_level = 99, sub = 1, sub_level = 49 }, update.job)
    end)

    -- Out of zone these fields hold non-zero garbage, and they are non-zero
    -- for a character with no subjob too. A zero main level is the one
    -- reliable tell, so the whole job block goes rather than half of it.
    it("drops the job block when the main job level is zero", function()
      assert.is_nil(packets.member_update(member({ ["Main job level"] = 0 })).job)
    end)

    it("drops the job block when a job field is missing", function()
      assert.is_nil(packets.member_update(member({ ["Sub job"] = ABSENT })).job)
    end)

    it("rejects an update with no usable id", function()
      assert.is_nil(packets.member_update(member({ ID = 0 })))
      assert.is_nil(packets.member_update(nil))
    end)
  end)

  describe("0x0DF char update", function()
    local function char(fields)
      local parsed = {
        ID = 2002,
        Index = 9,
        HP = 900,
        MP = 100,
        TP = 0,
        HPP = 45,
        MPP = 10,
        ["Main job"] = 3,
        ["Main job level"] = 75,
        ["Sub job"] = 4,
        ["Sub job level"] = 37,
      }
      return override(parsed, fields)
    end

    -- 0x0DF spells the percents HPP/MPP where 0x0DD writes HP%/MP%.
    it("reads the percents from this packet's own field names", function()
      local update = packets.char_update(char())
      assert.are.same({ hp = 900, mp = 100, hpp = 45, mpp = 10 }, update.vitals)
    end)

    it("carries the id, index and job, but no name or zone", function()
      local update = packets.char_update(char())
      assert.are.equal(2002, update.id)
      assert.are.equal(9, update.index)
      assert.are.same({ main = 3, main_level = 75, sub = 4, sub_level = 37 }, update.job)
      assert.is_nil(update.name)
      assert.is_nil(update.zone)
    end)

    it("drops the job block when the main job level is zero", function()
      assert.is_nil(packets.char_update(char({ ["Main job level"] = 0 })).job)
    end)

    it("rejects an update with no usable id", function()
      assert.is_nil(packets.char_update(char({ ID = 0 })))
      assert.is_nil(packets.char_update(nil))
    end)
  end)
end)
