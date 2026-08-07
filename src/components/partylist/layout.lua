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

--[[ The `xiv` theme geometry, transcribed from XIVParty's layouts/xiv.xml and
     layouts/xiv_alliance.xml (BSD 3-clause (c) 2024 Tylas).

     Data only -- no behaviour, no Windower, no prims. Every position and size
     is in unscaled layout pixels relative to its parent, exactly as the XML
     nests them, so a loader that reads these numbers from a file can replace
     this table without touching anything else. That loader is a backlog item;
     hardcoding the one theme is what unblocks the rest.

     Two deliberate departures from the XML:

       - No glow. XIVParty snaps the bar to its target and animates a glow
         across the gap, which costs three prims per bar. The bar itself eases
         here, so imgGlow and imgGlowSides are gone.
       - Arial everywhere. The XML asks for Grammara on the numbers, an FFXI
         font that may not resolve; the FFXIV-ish numerals are not worth a
         silently blank value.

     The alliance row is a genuinely smaller row rather than a scaled copy: no
     TP bar, no range, no buff icons, no job text, and a 3x2 grid instead of a
     single column. Its HP and MP bar groups really do share one position --
     the AllyBarHP and AllyBarMP textures carry the vertical offset themselves. ]]

local FONT = "Arial"
local STROKE = { r = 6, g = 45, b = 84, a = 200 }
local TEXT_COLOR = { r = 240, g = 255, b = 255, a = 255 }

local function text(pos, size, stroke_width, extra)
  local spec = {
    pos = pos,
    size = size,
    font = FONT,
    color = TEXT_COLOR,
    stroke = STROKE,
    stroke_width = stroke_width,
  }
  for key, value in pairs(extra or {}) do
    spec[key] = value
  end
  return spec
end

local function image(texture, pos, size, color)
  return { texture = texture, pos = pos, size = size, color = color or { r = 255, g = 255, b = 255, a = 255 } }
end

-- The job icon stack is identical in both layouts apart from its scale.
local function job_icon(pos, scale)
  return {
    pos = pos,
    scale = scale,
    path = "assets/jobIcons/",
    highlight = image("assets/jobIcons/highlight.png", { -13, -13 }, { 62, 62 }),
    bg = image("assets/jobIcons/bg.png", { 0, 0 }, { 36, 36 }),
    gradient = image("assets/jobIcons/gradient.png", { 0, 0 }, { 36, 36 }),
    icon = { pos = { 0, 0 }, size = { 36, 36 } },
    frame = image("assets/jobIcons/frame.png", { 0, 0 }, { 36, 36 }),
    colors = {
      dd = { r = 102, g = 53, b = 53, a = 255 },
      healer = { r = 59, g = 101, b = 41, a = 255 },
      special = { r = 255, g = 151, b = 0, a = 255 },
      support = { r = 218, g = 178, b = 0, a = 255 },
      tank = { r = 54, g = 69, b = 151, a = 255 },
    },
  }
end

local function leader(pos, scale)
  return {
    pos = pos,
    scale = scale,
    party = image("assets/xiv/Leader.png", { 0, 0 }, { 24, 24 }),
    alliance = image("assets/xiv/AllianceLeader.png", { 0, 12 }, { 24, 24 }),
    quartermaster = image("assets/xiv/QuarterMaster.png", { 0, 24 }, { 24, 24 }),
  }
end

-- Text and bar tint share one palette; the xiv theme tints the number only,
-- which is why the bar images have no band colour of their own.
local BANDS = {
  red = { r = 252, g = 129, b = 130, a = 255 },
  orange = { r = 248, g = 186, b = 128, a = 255 },
  yellow = { r = 243, g = 243, b = 124, a = 255 },
  full_tp = { r = 80, g = 180, b = 250, a = 255 },
  normal = TEXT_COLOR,
}

local function main_bar(key, pos, z_order)
  return {
    key = key,
    pos = pos,
    z_order = z_order,
    bg = image("assets/xiv/BarBG.png", { 0, 0 }, { 128, 64 }),
    fill = image("assets/xiv/Bar.png", { 13, 0 }, { 102, 64 }),
    fg = image("assets/xiv/BarFG.png", { 0, 0 }, { 128, 64 }),
    -- Not right-justified: texts.pos adds the screen width to x when the
    -- right flag is set. XIVParty asks for alignRight here and does not get it
    -- either -- its own right_justified() call passes no argument, so it reads
    -- the flag rather than setting it, and this offset is tuned for that.
    value = text({ 120, 35 }, 11, 2),
  }
end

local function alliance_bar(key, fill_texture, z_order)
  return {
    key = key,
    pos = { 37, -12 },
    z_order = z_order,
    bg = image("assets/xiv/AllyBarBG.png", { 0, 0 }, { 64, 64 }),
    fill = image(fill_texture, { 4, 0 }, { 56, 64 }),
    fg = image("assets/xiv/AllyBarFG.png", { 0, 0 }, { 64, 64 }),
    -- The alliance row shows bars without numbers.
    value = nil,
    hide_outside_zone = true,
  }
end

return {
  bands = BANDS,

  --[[ Text sizes are in points and render at 96dpi, so a prim's drawn height
       is 4/3 of the number in `size` -- a 15pt name occupies 20 pixels, not
       15. Anything lining text up against art has to go through this. ]]
  points_to_pixels = 4 / 3,

  main = {
    column_width = 410,
    columns = 1,
    --[[ 74, not XIVParty's 46. Measured against the art rather than the XML:
         the bar frame's opaque band is box y 25..39, so it needs a clear band
         at least 14 tall above it, plus room for the buff icon grid.

         The row grew twice. First to 66, moving the bars down 20 to make room
         for two rows of small icons above them (XIVParty avoids this by
         parking its second row at x=413, off the row body -- the overflow
         this component exists to avoid). Then to 74, when the icons grew to
         20px: two rows of 20 plus a 1px gap is 41 tall, and 66 only had 38
         clear above the bar frame at that point. Bars move down another 8, to
         y=21, landing the frame at row y=46 -- 5px below the icon block,
         matching the clearance the smaller grids left. ]]
    row_height = 74,
    rows = 6,
    --[[ How far the row art reaches outside its column rectangle: the leader
         stack sits 24px to its left, the background's top and bottom caps 21px
         above and below, and the frame (now carrying the buff icon grid with
         it) extends well past the row's own right edge. The widget adds this
         to every position so that the origin it is given is the true top-left
         corner -- otherwise the framework clamps the list against a box the
         art overhangs, and at the screen edge the overhanging piece vanishes. ]]
    -- `right` covers the icon block (ends x=502) and the frame's fade past it
    -- (ends x=542), both measured from the row's own left edge.
    margin = { left = 24, top = 21, right = 132, bottom = 21 },
    background = {
      pos = { 0, -21 },
      color = { r = 255, g = 255, b = 255, a = 221 },
      --[[ The `Wide` art, drawn 1:1 at 542.

           The frame is a horizontal gradient rather than a panel. XIVParty's
           own strips fade in over their first 14 pixels, hold solid to x=240
           of 377 -- 64% of the way -- and then take 137 to fade away.
           Stretching cannot fix that: it scales the falloff too, so the solid
           band always ends at 64% of the drawn width. The art is remapped
           instead -- fade-in kept, the flat solid section stretched, the tail
           compressed -- so it holds solid out to wherever the row's content
           actually ends and only then fades, over a fixed ~40px tail. See
           assets/LICENSE.txt for the transform.

           Solid-to was x=410 (the row's own right edge) until the buff icon
           grid grew past it: XIVParty pins its buffs to the row body and lives
           with the overflow, and once the frame could be stretched to cover
           whatever was drawn on it, matching that overflow was the simpler
           choice than re-shrinking the icons to fit inside 410 again. Solid-to
           is now x=502, the icon grid's own right edge -- see buff_icons. ]]
      top = image("assets/xiv/BgTopWide.png", { 0, 0 }, { 542, 21 }),
      mid = image("assets/xiv/BgMidWide.png", { 0, 21 }, { 542, 12 }),
      bottom = image("assets/xiv/BgBottomWide.png", { 0, 0 }, { 542, 21 }),
    },
    row = {
      bars = {
        main_bar("hp", { 19, 21 }, 2),
        main_bar("mp", { 150, 21 }, 3),
        main_bar("tp", { 281, 21 }, 4),
      },
      job_icon = job_icon({ -11, -2 }, { 1, 1 }),
      leader = leader({ -24, -8 }, { 1, 1 }),
      range = {
        pos = { 30, 56.5 },
        near = image("assets/xiv/Range.png", { 0, 0 }, { 14, 12 }),
        far = image("assets/xiv/RangeFar.png", { 0, 0 }, { 14, 12 }),
        distance = text({ 0, 1.5 }, 6, 1),
      },
      --[[ Two rows of ten 20px icons from x=293, 1px apart both ways: 209px
           wide, ending at x=502 -- past the row's own 410 and the TP bar's
           400, onto the frame's extended solid band above. 41px tall, with
           5px of clearance above the bar frame at row y=46.

           This overflows the row body the same way XIVParty's does, and is
           deliberately allowed to now that the frame is stretched to cover it
           rather than being fixed at 410: a grid this size never fit inside
           the row on its own, at any icon size worth drawing. ]]
      buff_icons = {
        pos = { 293, 0 },
        size = { 20, 20 },
        spacing = { 1, 1 },
        icons_by_row = { 10, 10 },
        -- Both rows left-aligned, unlike XIVParty's indented second row.
        offset_by_row = { 0, 0 },
        path = "assets/buffIcons/",
      },
      cursor = image("assets/xiv/Cursor.png", { 20, -8 }, { 390, 80 }),
      --[[ The name and the job labels share a bottom edge at row y 29.

           Sizes are points and draw 4/3 as tall (see points_to_pixels), so the
           15pt name occupies 20 pixels from y=9 and the 8pt subjob occupies
           10.7 from y=18.33. The job line keeps XIVParty's 9px stack above the
           subjob, which is slightly tighter than the text is tall -- its
           leading, not a mistake. ]]
      name = text({ 95, 9 }, 15, 2, { max_chars = 17 }),
      -- Same bottom edge as the name: 13pt draws 17.33 tall, so y=11.67 lands
      -- it on 29. It takes the buff icons' place, never sharing a row with
      -- them -- a member outside the zone has no buffs to show.
      zone = text({ 292, 11.67 }, 13, 2, { short = false }),
      job = text({ 30, 9.33 }, 8, 1),
      sub_job = text({ 39, 18.33 }, 8, 1),
    },
  },

  alliance = {
    column_width = 105,
    columns = 3,
    row_height = 42,
    rows = 2,
    -- The alliance frame and cursor sit 6px outside the grid on every side.
    margin = { left = 6, top = 6, right = 6, bottom = 6 },
    background = {
      pos = { -6, -6 },
      -- Flat, not a gradient: AllyBgMid holds a uniform alpha across its whole
      -- width, so it needs none of the main frame's stretching.
      color = { r = 255, g = 255, b = 255, a = 221 },
      top = image("assets/xiv/AllyBgTop.png", { 0, 0 }, { 327, 5 }),
      mid = image("assets/xiv/AllyBgMid.png", { 0, 5 }, { 327, 42 }),
      bottom = image("assets/xiv/AllyBgBottom.png", { 0, 0 }, { 327, 5 }),
    },
    row = {
      bars = {
        alliance_bar("hp", "assets/xiv/AllyBarHP.png", 2),
        alliance_bar("mp", "assets/xiv/AllyBarMP.png", 3),
      },
      job_icon = job_icon({ 4, 4 }, { 0.9, 0.9 }),
      leader = leader({ -6, 0 }, { 0.8, 0.8 }),
      cursor = image("assets/xiv/AllyCursor.png", { -6, -6 }, { 116, 53 }),
      name = text({ 41, 1 }, 8, 2, { max_chars = 9 }),
      zone = text({ 8, 18 }, 9, 2, { short = true }),
    },
  },
}
