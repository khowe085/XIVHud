local icons = require("lib/icons")

-- Byte offset of the icon inside an item record, and its length, from the
-- reference addon's extractor.
local ICON_OFFSET = 0x2BD
local RECORD_STRIDE = 0xC00

local HEADER_LENGTH = 122
local PIXEL_COUNT = 32 * 32
local FILE_LENGTH = HEADER_LENGTH + PIXEL_COUNT * 4

--[[ Every byte in the icon block is bit-rotated: the game stores `i` where the
     value meant is `(i % 32) * 8 + floor(i / 32)`. Writing a record for a test
     means inverting that. With i = 32a + b (a < 8, b < 32) the decode is
     8b + a, so for a wanted value n the stored byte is 32 * (n % 8) +
     floor(n / 8). Derived here rather than shared with the module, so a
     transcription slip in either one shows up as a failure. ]]
local function stored(value)
  return string.char(32 * (value % 8) + math.floor(value / 8))
end

--[[ A 0x800 icon block: 256 palette entries of four stored bytes, then one
     stored index byte per pixel.

     `entries` maps a palette position to the colour it should decode to,
     as { b, g, r, a } - `a` being the value *in the DAT*, which the decoder
     doubles. `pixels` maps a zero-based pixel to the palette position it
     should select. Everything unnamed is palette position 0. ]]
local function icon_block(entries, pixels)
  local palette = {}
  for position = 0, 255 do
    local entry = (entries or {})[position] or { 0, 0, 0, 0 }
    palette[position + 1] = stored(entry[1]) .. stored(entry[2]) .. stored(entry[3]) .. stored(entry[4])
  end

  local indices = {}
  for pixel = 0, PIXEL_COUNT - 1 do
    -- The index byte is itself rotated, so pointing a pixel at a palette
    -- position means storing the rotation of that position.
    indices[pixel + 1] = stored((pixels or {})[pixel] or 0)
  end

  return table.concat(palette) .. table.concat(indices)
end

-- The little-endian unsigned integer of `count` bytes at `offset` (1-based).
local function number_at(bytes, offset, count)
  local value = 0
  for step = count - 1, 0, -1 do
    value = value * 256 + bytes:byte(offset + step)
  end
  return value
end

-- The four bytes a pixel occupies in the output, as { b, g, r, a }.
local function pixel_at(bmp, pixel)
  local offset = HEADER_LENGTH + pixel * 4 + 1
  return { bmp:byte(offset), bmp:byte(offset + 1), bmp:byte(offset + 2), bmp:byte(offset + 3) }
end

--[[ The whole byte-level surface of lib/icons. Written against the equipviewer,
     whose component file this module was promoted out of; it moved here with
     the code, since tests/components mirrors src/components. ]]
describe("lib icons", function()
  describe("locate", function()
    -- The reference maps an item id to a DAT by range. Only the general-items
    -- range carries an offset, so its records are indexed by the raw id.
    local function offset_of(index)
      return index * RECORD_STRIDE + ICON_OFFSET
    end

    it("puts the first general item one record in, not at the start", function()
      local found = icons.locate(0x0001)
      assert.equal("118/106", found.dat)
      assert.equal(offset_of(1), found.offset)
    end)

    it("indexes every other range from its own first id", function()
      local found = icons.locate(0x1000)
      assert.equal("118/107", found.dat)
      assert.equal(offset_of(0), found.offset)
    end)

    it("reads a fixed-length icon", function()
      assert.equal(0x800, icons.locate(0x1000).length)
    end)

    -- Both ends of every range, so a transposed bound cannot pass. `index` is
    -- the record the id lands on within its DAT.
    it("maps each range to its DAT", function()
      local cases = {
        { id = 0x0FFF, dat = "118/106", index = 0x0FFF },
        { id = 0x1000, dat = "118/107", index = 0x0000 },
        { id = 0x1FFF, dat = "118/107", index = 0x0FFF },
        { id = 0x2000, dat = "118/110", index = 0x0000 },
        { id = 0x21FF, dat = "118/110", index = 0x01FF },
        { id = 0x2200, dat = "301/115", index = 0x0000 },
        { id = 0x27FF, dat = "301/115", index = 0x05FF },
        { id = 0x2800, dat = "118/109", index = 0x0000 },
        { id = 0x3FFF, dat = "118/109", index = 0x17FF },
        { id = 0x4000, dat = "118/108", index = 0x0000 },
        { id = 0x59FF, dat = "118/108", index = 0x19FF },
        { id = 0x5A00, dat = "286/73", index = 0x0000 },
        { id = 0x6FFF, dat = "286/73", index = 0x15FF },
        { id = 0x7000, dat = "217/21", index = 0x0000 },
        { id = 0x73FF, dat = "217/21", index = 0x03FF },
        { id = 0x7400, dat = "288/80", index = 0x0000 },
        { id = 0x77FF, dat = "288/80", index = 0x03FF },
        { id = 0xF000, dat = "288/67", index = 0x0000 },
        { id = 0xF1FF, dat = "288/67", index = 0x01FF },
        { id = 0xFFFF, dat = "174/48", index = 0x0000 },
      }
      for _, case in ipairs(cases) do
        local found = icons.locate(case.id)
        assert.is_not_nil(found, ("id 0x%04X should map to a DAT"):format(case.id))
        assert.equal(case.dat, found.dat)
        assert.equal(offset_of(case.index), found.offset)
      end
    end)

    -- An empty equipment slot reports id 0, and 65535 is the game's "nothing"
    -- marker on a packet. Neither must send the extractor at a DAT.
    it("has nothing for an id outside every range", function()
      assert.is_nil(icons.locate(0x0000))
      assert.is_nil(icons.locate(0x7800))
      assert.is_nil(icons.locate(0xEFFF))
      assert.is_nil(icons.locate(0xF200))
    end)

    it("has nothing for a missing or non-numeric id", function()
      assert.is_nil(icons.locate(nil))
      assert.is_nil(icons.locate("main"))
    end)
  end)

  -- The game's install path comes from Windower, which may or may not end in a
  -- separator, and from a setting the player may have typed either way.
  describe("dat_path", function()
    it("reaches the ROM directory from the game's install path", function()
      assert.equal("C:/FFXI/ROM/118/106.DAT", icons.dat_path("C:/FFXI", "118/106"))
    end)

    it("does not double a separator the path already ends with", function()
      assert.equal("C:/FFXI/ROM/118/106.DAT", icons.dat_path("C:/FFXI/", "118/106"))
      assert.equal("C:\\FFXI/ROM/118/106.DAT", icons.dat_path("C:\\FFXI\\", "118/106"))
    end)

    it("has no path without a game to read from", function()
      assert.is_nil(icons.dat_path(nil, "118/106"))
      assert.is_nil(icons.dat_path("", "118/106"))
      assert.is_nil(icons.dat_path("C:/FFXI", nil))
    end)
  end)

  describe("to_bmp", function()
    it("writes a bitmap of the one size a 32x32 icon can be", function()
      local bmp = icons.to_bmp(icon_block())
      assert.equal(FILE_LENGTH, #bmp)
      assert.equal("BM", bmp:sub(1, 2))
      assert.equal(FILE_LENGTH, number_at(bmp, 3, 4))
      assert.equal(HEADER_LENGTH, number_at(bmp, 11, 4))
    end)

    --[[ A texture path that does not exist fails silently, and so, in effect,
         does one the prim layer cannot parse: the widget draws nothing and
         says nothing. These are the fields that decide whether it parses. ]]
    it("declares a 32-bit bitfield DIB the prim layer can read", function()
      local bmp = icons.to_bmp(icon_block())
      assert.equal(108, number_at(bmp, 15, 4)) -- BITMAPV4HEADER
      assert.equal(32, number_at(bmp, 19, 4)) -- width
      assert.equal(32, number_at(bmp, 23, 4)) -- height
      assert.equal(1, number_at(bmp, 27, 2)) -- colour planes
      assert.equal(32, number_at(bmp, 29, 2)) -- bits per pixel
      assert.equal(3, number_at(bmp, 31, 4)) -- BI_BITFIELDS
      assert.equal(PIXEL_COUNT * 4, number_at(bmp, 35, 4)) -- image size
      assert.equal(0x00FF0000, number_at(bmp, 55, 4)) -- red mask
      assert.equal(0x0000FF00, number_at(bmp, 59, 4)) -- green mask
      assert.equal(0x000000FF, number_at(bmp, 63, 4)) -- blue mask
      assert.equal(0xFF000000, number_at(bmp, 67, 4)) -- alpha mask
    end)

    it("expands each pixel into the palette entry it points at", function()
      local bmp = icons.to_bmp(icon_block({ [9] = { 0x12, 0x34, 0x56, 0x40 } }, { [0] = 9 }))
      assert.same({ 0x12, 0x34, 0x56, 0x80 }, pixel_at(bmp, 0))
    end)

    it("un-rotates every byte of the palette, not just the first", function()
      local bmp = icons.to_bmp(icon_block({ [255] = { 0x01, 0x08, 0x40, 0x02 } }, { [1023] = 255 }))
      assert.same({ 0x01, 0x08, 0x40, 0x04 }, pixel_at(bmp, 1023))
    end)

    -- The DAT stores alpha at half scale, so an opaque pixel reads 0x80.
    it("doubles alpha and clamps it at opaque", function()
      local bmp = icons.to_bmp(icon_block({
        [1] = { 0, 0, 0, 0x80 },
        [2] = { 0, 0, 0, 0xFF },
      }, { [0] = 1, [1] = 2 }))
      assert.equal(0xFF, pixel_at(bmp, 0)[4])
      assert.equal(0xFF, pixel_at(bmp, 1)[4])
    end)

    it("keeps a fully transparent pixel transparent", function()
      local bmp = icons.to_bmp(icon_block({ [3] = { 0xFF, 0xFF, 0xFF, 0x00 } }, { [0] = 3 }))
      assert.same({ 0xFF, 0xFF, 0xFF, 0x00 }, pixel_at(bmp, 0))
    end)

    -- A short read means a truncated or wrong DAT. Better no icon than a
    -- bitmap the prim layer chokes on.
    it("refuses a record that is not a whole icon", function()
      assert.is_nil(icons.to_bmp(icon_block():sub(1, 0x7FF)))
      assert.is_nil(icons.to_bmp(""))
      assert.is_nil(icons.to_bmp(nil))
    end)
  end)

  -- Carried from this spec's twelve-line stub: the smoke test that the module
  -- answers straight from lib/, with no component in the picture.
  it("locates an item's icon straight from lib/", function()
    local located = icons.locate(4096)
    assert.are.same({ dat = "118/107", offset = 0x2BD, length = 0x800 }, located)
    assert.are.equal("C:/FFXI/ROM/118/107.DAT", icons.dat_path("C:/FFXI/", located.dat))
  end)
end)
