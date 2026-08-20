--[[
Copyright © 2026, Azureblood2
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of XIVHud nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Azureblood2 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ Item icons, read out of the client's own DAT files.

     No icons ship with the addon - there are tens of thousands of items and
     the art is the game's. The client already has it: each item's record in a
     ROM DAT carries a 32x32 icon as a 256-colour palette plus one index byte
     per pixel, and this module turns that into a Windows bitmap the prim layer
     can load from disk.

     Everything here is pure. The DAT read and the file write live in
     lib/icon_cache behind injected deps - which is what makes the byte-level
     work below testable at all, since this container has neither a client nor
     a DAT.

     Promoted out of `components/equipviewer/` so more than one
     component can draw item art without one requiring the other (CLAUDE.md
     forbids that outright); the equipviewer and the crossbar both require it
     straight from lib/.

     Ported from the `icon_extractor` library of the Windower `equipviewer`
     addon (base extraction code credited to Trv):

       Copyright (c) 2021, Rubenator. All rights reserved. Redistribution and
       use in source and binary forms, with or without modification, are
       permitted provided that the conditions of the BSD 3-clause licence
       reproduced in components/equipviewer/assets/LICENSE.txt are met.

     The notice above is the in-file copy that BSD clause 1 asks derived
     source to retain; nothing in lib/ depends on the component's LICENSE.txt
     being present. ]]

local icons = {}

-- Every item record is 0xC00 bytes; the icon sits 0x2BD in and runs 0x800.
local RECORD_STRIDE = 0xC00
local ICON_OFFSET = 0x2BD
local ICON_LENGTH = 0x800

-- Half the icon block is the palette (256 entries, four bytes each), the rest
-- one index byte per pixel of a 32x32 image.
local PALETTE_LENGTH = 0x400
local PALETTE_ENTRIES = 256
local BYTES_PER_PIXEL = 4

--[[ Item id ranges to the DAT that holds them. `first` is the id the DAT's
     first record belongs to: it is the range's own minimum everywhere except
     the general-items DAT, whose records start one in - id 1 is record 1, not
     record 0. (The reference expressed that as a separate `offset = -1` on the
     range; folding it into `first` says the same thing once.) ]]
local DATS = {
  { min = 0x0001, max = 0x0FFF, dat = "118/106", first = 0x0000 }, -- general items
  { min = 0x1000, max = 0x1FFF, dat = "118/107", first = 0x1000 }, -- usable items
  { min = 0x2000, max = 0x21FF, dat = "118/110", first = 0x2000 }, -- automaton items
  { min = 0x2200, max = 0x27FF, dat = "301/115", first = 0x2200 }, -- general items 2
  { min = 0x2800, max = 0x3FFF, dat = "118/109", first = 0x2800 }, -- armor
  { min = 0x4000, max = 0x59FF, dat = "118/108", first = 0x4000 }, -- weapons
  { min = 0x5A00, max = 0x6FFF, dat = "286/73", first = 0x5A00 }, -- armor 2
  { min = 0x7000, max = 0x73FF, dat = "217/21", first = 0x7000 }, -- maze and basic items
  { min = 0x7400, max = 0x77FF, dat = "288/80", first = 0x7400 }, -- instincts
  { min = 0xF000, max = 0xF1FF, dat = "288/67", first = 0xF000 }, -- monipulator items
  { min = 0xFFFF, max = 0xFFFF, dat = "174/48", first = 0xFFFF }, -- gil
}

local BITMAP_SIDE = 32
local PIXEL_DATA_LENGTH = BITMAP_SIDE * BITMAP_SIDE * BYTES_PER_PIXEL
local DIB_HEADER_LENGTH = 108 -- BITMAPV4HEADER, the smallest one carrying masks
local HEADER_LENGTH = 14 + DIB_HEADER_LENGTH

local function little_endian(value, width)
  local bytes = {}
  for index = 1, width do
    bytes[index] = value % 0x100
    value = math.floor(value / 0x100)
  end
  return string.char(unpack(bytes))
end

local function u16(value)
  return little_endian(value, 2)
end

local function u32(value)
  return little_endian(value, 4)
end

--[[ The icons carry an alpha channel, so the file has to be a bitfield DIB
     rather than a plain 24-bit one - the header is fixed, and every icon
     shares it.

     Two oddities are the reference's and are kept deliberately. The colour
     space is written as the literal "sRGB", which is the LCS_sRGB constant
     byte-reversed; and the height is positive, so the rows are read bottom-up,
     which is the order the DAT already stores them in. Both are how the
     reference addon has been drawing these icons for years - "correcting"
     either one is a change no test here could check and a live client might
     not survive. ]]
local HEADER = table.concat({
  "BM",
  u32(HEADER_LENGTH + PIXEL_DATA_LENGTH),
  u16(0), -- reserved
  u16(0), -- reserved
  u32(HEADER_LENGTH), -- where the pixels start
  u32(DIB_HEADER_LENGTH),
  u32(BITMAP_SIDE), -- width
  u32(BITMAP_SIDE), -- height
  u16(1), -- colour planes
  u16(32), -- bits per pixel
  u32(3), -- BI_BITFIELDS
  u32(PIXEL_DATA_LENGTH),
  u32(0), -- horizontal resolution, unused
  u32(0), -- vertical resolution, unused
  u32(0), -- palette size, none for a 32-bit image
  u32(0), -- important colours
  u32(0x00FF0000), -- red mask
  u32(0x0000FF00), -- green mask
  u32(0x000000FF), -- blue mask
  u32(0xFF000000), -- alpha mask
  "sRGB",
  string.rep("\0", 36), -- CIE endpoints, meaningless for sRGB
  u32(0), -- red gamma
  u32(0), -- green gamma
  u32(0), -- blue gamma
})

--[[ Every byte in the icon block is bit-rotated - the value meant by a stored
     byte `i` is `(i % 32) * 8 + floor(i / 32)`. Alpha is stored at half scale
     besides, so it is doubled and clamped on the way out.

     Both directions are needed: the colour bytes are decoded, while a pixel's
     index byte is left as it was stored and looked up by that, so the palette
     has to be keyed by the *stored* form of each position. ]]
local DECODED = {}
local DECODED_ALPHA = {}
local STORED_FOR = {}

for stored = 0, 255 do
  local decoded = (stored % 0x20) * 8 + math.floor(stored / 0x20)
  DECODED[string.char(stored)] = string.char(decoded)
  DECODED_ALPHA[string.char(stored)] = string.char(math.min(decoded * 2, 255))
  STORED_FOR[decoded] = string.char(stored)
end

-- Where an item's icon lives: the DAT path (relative to the game's ROM dir),
-- the byte offset of the icon within it, and how much to read. nil for an id
-- no DAT covers - which includes 0, the empty equipment slot.
function icons.locate(item_id)
  local id = tonumber(item_id)
  if not id then
    return nil
  end

  for _, range in ipairs(DATS) do
    if id >= range.min and id <= range.max then
      return {
        dat = range.dat,
        offset = (id - range.first) * RECORD_STRIDE + ICON_OFFSET,
        length = ICON_LENGTH,
      }
    end
  end

  return nil
end

-- The file a DAT reference names, under the game's install directory. Windower
-- reports that path with a trailing separator; a player who typed one in may
-- have gone either way.
function icons.dat_path(game_path, dat)
  if type(game_path) ~= "string" or game_path == "" or not dat then
    return nil
  end
  return (game_path:gsub("[/\\]$", "")) .. "/ROM/" .. dat .. ".DAT"
end

--[[ An icon block read out of a DAT, as a 32x32 bitmap ready to be written to
     disk. nil for anything shorter than a whole icon: a truncated read means
     the DAT is not what was expected, and a malformed bitmap would leave the
     prim drawing nothing with no way to tell why.

     Only the palette is decoded - 256 entries rather than 1024 pixels - and
     the pixel pass is a single gsub through it. ]]
function icons.to_bmp(record)
  if type(record) ~= "string" or #record < ICON_LENGTH then
    return nil
  end

  local palette = record:sub(1, PALETTE_LENGTH):gsub("(.)(.)(.)(.)", function(blue, green, red, alpha)
    return DECODED[blue] .. DECODED[green] .. DECODED[red] .. DECODED_ALPHA[alpha]
  end)

  local colours = {}
  for position = 0, PALETTE_ENTRIES - 1 do
    local at = position * BYTES_PER_PIXEL + 1
    colours[STORED_FOR[position]] = palette:sub(at, at + BYTES_PER_PIXEL - 1)
  end

  local pixels = record:sub(PALETTE_LENGTH + 1, ICON_LENGTH):gsub(".", colours)

  return HEADER .. pixels
end

return icons
