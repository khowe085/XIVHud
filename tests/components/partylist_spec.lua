local fakes = require("tests/support/fakes")
local new_partylist = require("components/partylist/partylist")
local layouts = require("components/partylist/layout")

local RESOURCES = {
  jobs = { [4] = { ens = "WHM" }, [5] = { ens = "BLM" } },
  zones = {
    [230] = { name = "Southern San d'Oria", search = "San d'Oria" },
    [50] = { name = "Port Bastok", search = "Bastok" },
  },
  buffs = { [0] = { en = "KO" }, [15] = { en = "doom" } },
}

-- `elsewhere` drops the mob table, which is how get_party() reports a member
-- who is not in the zone.
local function member(name, id, fields)
  local entry = {
    name = name,
    hp = 1000,
    hpp = 100,
    mp = 500,
    mpp = 100,
    tp = 0,
    zone = 230,
    mob = { id = id, distance = 25, is_npc = false, models = { 0 } },
  }
  for key, value in pairs(fields or {}) do
    entry[key] = value
  end
  if (fields or {}).elsewhere then
    entry.mob, entry.elsewhere = nil, nil
  end
  return entry
end

-- A real 0x076 body: the widget decodes the bytes itself, because Windower's
-- packet library has no field definition for this one.
local function party_buff_packet(id, buffs)
  local bytes = {}
  for index = 1, 5 * 48 + 4 do
    bytes[index] = 0
  end
  for byte = 0, 3 do
    bytes[5 + byte] = math.floor(id / 256 ^ byte) % 256
  end
  for index = 1, 32 do
    local buff = buffs[index] or 255
    bytes[5 + 16 + index - 1] = buff % 256
    local packed = 5 + 8 + math.floor((index - 1) / 4)
    bytes[packed] = bytes[packed] + math.floor(buff / 256) % 4 * 4 ^ ((index - 1) % 4)
  end
  local out = {}
  for index, byte in ipairs(bytes) do
    out[index] = string.char(byte)
  end
  return table.concat(out)
end

describe("partylist widget", function()
  local prims, env, widget

  local function build(variant)
    prims = fakes.prims()
    env = { party = {}, targets = {}, clock = 0, polls = 0, target_reads = 0 }

    local ctx = {
      name = variant == "main" and "partylist" or "alliancelist1",
      variant = variant or "main",
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      asset = function(path)
        return "addons/XIVHud/" .. path
      end,
      resources = RESOURCES,
      now = function()
        return env.clock
      end,
      get_player = function()
        return {
          name = "Ayame",
          buffs = {},
          main_job_id = 4,
          main_job_level = 99,
          sub_job_id = 5,
          sub_job_level = 49,
        }
      end,
      get_party = function()
        env.polls = env.polls + 1
        return env.party
      end,
      get_mob_by_target = function(kind)
        if kind == "t" then
          env.target_reads = env.target_reads + 1
        end
        return env.targets[kind]
      end,
      get_info = function()
        return { zone = 230 }
      end,
    }

    widget = new_partylist(ctx)
    widget.attach(widget.defaults, function() end)
    widget.set_pos(100, 200)
    widget.set_scale(1)
    widget.show()
    return widget
  end

  -- Runs frames until the bars have stopped easing, advancing the clock past
  -- the poll gate each time so the roster is actually re-read.
  local function settle(count)
    for _ = 1, count or 200 do
      env.clock = env.clock + 1
      widget.update()
    end
  end

  -- Frames without advancing the clock, so the poll gate stays shut. A push
  -- only lives until the next poll overrules it, which is the point of it.
  local function frames(count)
    for _ = 1, count or 5 do
      widget.update()
    end
  end

  before_each(function()
    build("main")
  end)

  describe("prims", function()
    local FRAME_PRIMS = 3

    it("draws only the background until somebody is in the party", function()
      widget.update()
      assert.are.equal(FRAME_PRIMS, #prims.all)
    end)

    it("builds a row's prims when a member appears", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      assert.is_true(#prims.all > 3)
    end)

    it("builds no prims for the empty slots", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local one_row = #prims.all
      env.party = { p0 = member("Ayame", 1), p1 = member("Volker", 2) }
      settle(2)
      assert.are.equal(2 * (one_row - FRAME_PRIMS) + FRAME_PRIMS, #prims.all)
    end)

    -- The list is the component's whole prim budget; a party that churns all
    -- session would otherwise only ever grow it. Nothing is drawn for an empty
    -- row, so there is nothing to wait for.
    it("disposes a row's prims as soon as its member has gone", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local row_prims = {}
      for _, prim in ipairs(prims.all) do
        row_prims[#row_prims + 1] = prim
      end
      env.party = {}
      settle()
      local destroyed = 0
      for _, prim in ipairs(row_prims) do
        destroyed = destroyed + (prim.destroyed > 0 and 1 or 0)
      end
      assert.is_true(destroyed > 0)
    end)

    it("disposes every prim it ever made on destroy", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.is_true(prim.destroyed > 0, "a " .. prim.kind .. " prim outlived the widget")
      end
    end)

    it("never draws more buff icons than the cap", function()
      local many = {}
      for index = 1, 32 do
        many[index] = index
      end
      env.party = { p0 = member("Volker", 2) }
      settle(2)
      widget.update("chunk", 0x076, party_buff_packet(2, many))
      settle(2)
      local shown = 0
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("buffIcons", 1, true) and prim.visible then
          shown = shown + 1
        end
      end
      assert.are.equal(16, shown)
    end)
  end)

  describe("placement", function()
    -- 470-odd prims at sixty frames a second: a settled list that keeps
    -- rewriting the same values is the one thing that could make this
    -- component cost something.
    it("touches no prim at all once nothing is moving", function()
      env.party = { p0 = member("Ayame", 1) }
      settle()
      local before = 0
      for _, prim in ipairs(prims.all) do
        before = before + #prim.calls
      end
      widget.update()
      local after = 0
      for _, prim in ipairs(prims.all) do
        after = after + #prim.calls
      end
      assert.are.equal(before, after)
    end)

    -- With align_bottom the rows sit at the bottom of the box, so every
    -- existing row moves when the party grows.
    it("re-places the rows already on screen when the list grows upward", function()
      widget.defaults.align_bottom = true
      widget.attach(widget.defaults, function() end)
      env.party = { p0 = member("Ayame", 1) }
      settle(3)
      local first_row_y = nil
      for _, prim in ipairs(prims.texts) do
        if prim.last.text == "Ayame" then
          first_row_y = prim.y
        end
      end
      assert.is_not_nil(first_row_y)
      env.party = { p0 = member("Ayame", 1), p1 = member("Volker", 2) }
      settle(3)
      for _, prim in ipairs(prims.texts) do
        if prim.last.text == "Ayame" then
          assert.are_not.equal(first_row_y, prim.y)
        end
      end
    end)

    it("reports the origin it was given, so the framework can clamp it", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local x, y = widget.get_bounds()
      assert.are.equal(100, x)
      assert.are.equal(200, y)
    end)

    --[[ The leader marker sits 24px left of the row and the frame's top cap
         21px above it. If the reported box were the row rectangle alone, core
         would clamp against a box the art overhangs -- so at the screen edge
         the marker and the cap would be drawn at negative coordinates and
         silently vanish -- and layout mode's hit test would not reach them. ]]
    it("reports a box that contains everything it draws", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local x, y, width, height = widget.get_bounds()

      for _, prim in ipairs(prims.all) do
        if prim.visible and prim.x then
          assert.is_true(prim.x >= x, "a prim is drawn left of the reported box")
          assert.is_true(prim.y >= y, "a prim is drawn above the reported box")
          assert.is_true(prim.x <= x + width, "a prim is drawn right of the reported box")
          assert.is_true(prim.y <= y + height, "a prim is drawn below the reported box")
        end
      end
    end)

    it("scales the box it reports", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local _, _, full_width, full_height = widget.get_bounds()
      widget.set_scale(0.5)
      local _, _, width, height = widget.get_bounds()
      assert.are.equal(full_width / 2, width)
      assert.are.equal(full_height / 2, height)
    end)

    -- The fill is the one prim whose size render() writes rather than
    -- place_row, so a scale change has to reach it through the render path or
    -- it stays at the old scale until the member's HP happens to move.
    it("re-sizes the bar fills when the scale changes", function()
      env.party = { p0 = member("Ayame", 1) }
      settle()
      local fill = nil
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("xiv/Bar.png", 1, true) then
          fill = fill or prim
        end
      end
      assert.is_not_nil(fill)
      local width = fill.width
      assert.is_true(width > 0)
      widget.set_scale(2)
      widget.update()
      assert.are.equal(width * 2, fill.width)
    end)

    it("shows a full sample party while previewing, so there is something to drag", function()
      env.party = {}
      widget.set_preview(true)
      settle(2)
      local names = 0
      for _, prim in ipairs(prims.texts) do
        if type(prim.last.text) == "string" and prim.last.text ~= "" and prim.visible then
          names = names + 1
        end
      end
      assert.is_true(names > 0)
    end)

    it("reports nothing before it has a position", function()
      local fresh = new_partylist({
        name = "partylist",
        variant = "main",
        new_text = prims.new_text,
        new_image = prims.new_image,
        screen = function()
          return 1920, 1080
        end,
        asset = tostring,
        resources = RESOURCES,
        now = function()
          return 0
        end,
      })
      assert.is_nil(fresh.get_bounds())
    end)

    -- Moving the group moves every row with it; nothing is positioned against
    -- the screen, only against the list's own origin.
    -- The frame has to contain the rows. align_bottom moves the rows to the
    -- foot of the box, and the background has to follow them there.
    it("keeps the background around the rows when the list is aligned to the bottom", function()
      widget.defaults.align_bottom = true
      widget.attach(widget.defaults, function() end)
      env.party = { p0 = member("Ayame", 1) }
      settle(3)

      local name_y = nil
      for _, prim in ipairs(prims.texts) do
        if prim.last.text == "Ayame" then
          name_y = prim.y
        end
      end
      assert.is_not_nil(name_y)

      local top, bottom = nil, nil
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" then
          if prim.last.path:find("BgTop", 1, true) then
            top = prim.y
          elseif prim.last.path:find("BgBottom", 1, true) then
            bottom = prim.y + prim.height
          end
        end
      end
      assert.is_not_nil(top)
      assert.is_not_nil(bottom)
      assert.is_true(top < name_y, "the frame starts below the row it contains")
      assert.is_true(bottom > name_y, "the frame ends above the row it contains")
    end)

    --[[ Core's apply() reads get_bounds twice -- once to clamp, once for the
         layout-mode highlight -- and both reads happen straight after
         set_preview, before any frame has been rendered with the preview on.
         A stale box means the highlight is drawn around one row while six are
         on screen, which is the one case the preview exists for. ]]
    it("reports the preview's box as soon as previewing starts", function()
      env.party = {}
      settle(2)
      local _, _, _, one_row = widget.get_bounds()
      widget.set_preview(true)
      local _, _, _, previewing = widget.get_bounds()
      assert.is_true(previewing > one_row)
    end)

    --[[ The frame has to reach across the buff icon grid -- which now runs
         past the row's own edge, all the way to x=460, so the bars can be
         covered along with it -- without trailing unboundedly far past that. ]]
    it("draws the frame across the icon grid without overshooting it", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)

      local x = select(1, widget.get_bounds())
      local strip = nil
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("BgMid", 1, true) then
          strip = prim
        end
      end
      assert.is_not_nil(strip)

      -- 24 is the left margin; the icon grid's own right edge is 24 + 460.
      local right = strip.x - x + strip.width
      assert.is_true(right >= 24 + 460, ("frame ends at %.0f, the icon grid ends at 484"):format(right))
      assert.is_true(right <= 24 + 460 + 60, ("frame runs %.0f past the icon grid"):format(right - 484))
    end)

    -- The name and the job labels are one block and have to share a bottom
    -- edge, rather than each sitting wherever its own size happens to put it.
    it("sits the name and the job labels on the same bottom edge", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(3)

      local bottoms = {}
      for _, prim in ipairs(prims.texts) do
        local said = prim.last.text
        if said == "Ayame" or said == "WHM 99" or said == "BLM 49" then
          -- `size` is in points and draws at 96dpi, so the box is 4/3 of it.
          bottoms[said] = prim.y + prim.font_size * layouts.points_to_pixels
        end
      end
      assert.is_not_nil(bottoms["Ayame"], "no name was drawn")
      assert.is_not_nil(bottoms["BLM 49"], "no subjob was drawn")
      -- The job line sits above the subjob, so the subjob is the block's foot.
      -- Within half a pixel: 8pt draws 10 and two thirds tall, and a prim
      -- lands on whole pixels anyway, so exact equality would only be testing
      -- how the layout's decimals were written down.
      assert.is_true(
        math.abs(bottoms["Ayame"] - bottoms["BLM 49"]) < 0.5,
        ("name bottom %.2f, subjob bottom %.2f"):format(bottoms["Ayame"], bottoms["BLM 49"])
      )
      assert.is_true(bottoms["WHM 99"] < bottoms["BLM 49"])
    end)

    -- The zone name stands in for the buff icons on a member who is elsewhere,
    -- so it belongs on the same line as the rest of the row's text.
    it("sits the zone name on that bottom edge too", function()
      env.party = { p0 = member("Ayame", 1), p1 = member("Volker", 2, { zone = 50, elsewhere = true }) }
      settle(3)

      local name_bottom, zone_bottom = nil, nil
      for _, prim in ipairs(prims.texts) do
        local said = prim.last.text
        if said == "Volker" then
          name_bottom = prim.y + prim.font_size * layouts.points_to_pixels
        elseif type(said) == "string" and said:find("Bastok", 1, true) then
          zone_bottom = prim.y + prim.font_size * layouts.points_to_pixels
        end
      end
      assert.is_not_nil(name_bottom, "no name was drawn")
      assert.is_not_nil(zone_bottom, "no zone name was drawn")
      assert.is_true(
        math.abs(name_bottom - zone_bottom) < 0.5,
        ("name bottom %.2f, zone bottom %.2f"):format(name_bottom, zone_bottom)
      )
    end)

    --[[ The icon grid is anchored to its bottom row, which is the one nearest
         the bars. A short buff list otherwise sat at the top of the block with
         a row of empty space between it and the bar. ]]
    it("fills the bottom icon row first and only spills upward on the ninth", function()
      env.party = { p0 = member("Volker", 2) }
      settle(3)

      local function icon_rows(count)
        local ids = {}
        for index = 1, count do
          ids[index] = index
        end
        widget.update("chunk", 0x076, party_buff_packet(2, ids))
        frames()
        local ys = {}
        for _, prim in ipairs(prims.images) do
          if type(prim.last.path) == "string" and prim.last.path:find("buffIcons", 1, true) and prim.visible then
            ys[prim.y] = (ys[prim.y] or 0) + 1
          end
        end
        local sorted = {}
        for y, n in pairs(ys) do
          sorted[#sorted + 1] = { y = y, n = n }
        end
        table.sort(sorted, function(a, b)
          return a.y < b.y
        end)
        return sorted
      end

      local eight = icon_rows(8)
      assert.are.equal(1, #eight, "eight buffs should occupy one row")
      local bottom_y = eight[1].y

      local nine = icon_rows(9)
      assert.are.equal(2, #nine, "nine buffs should occupy two rows")
      assert.are.equal(bottom_y, nine[2].y, "the lower geometric row must not move when the block grows")
      assert.is_true(nine[1].y < bottom_y, "the ninth buff opens a row above, not below")
      -- The first eight buffs are placed by index, not recency, so crossing
      -- the row boundary relocates them from the bottom position to the newly
      -- opened top one; only the ninth (newest) buff lands in the bottom slot.
      assert.are.equal(8, nine[1].n)
      assert.are.equal(1, nine[2].n)
    end)

    it("moves every prim when the group moves", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local before = {}
      for index, prim in ipairs(prims.all) do
        before[index] = prim.x
      end
      widget.set_pos(150, 200)
      widget.update()
      for index, prim in ipairs(prims.all) do
        if before[index] then
          assert.are.equal(before[index] + 50, prim.x)
        end
      end
    end)
  end)

  --[[ The drag path -------------------------------------------------------

       Layout mode calls move_to on every raw mouse-move event, and each one
       runs core.apply, which pushes set_scale, set_pos and set_preview before
       reading get_bounds. Two of those three carry a value the widget already
       holds, so the cost that matters is what an unchanged setter does -- and
       what a move does that a rescale has to but a move does not. ]]
  describe("the drag path", function()
    local function prim_calls()
      local total = 0
      for _, prim in ipairs(prims.all) do
        total = total + #prim.calls
      end
      return total
    end

    local function measure(act)
      local before = prim_calls()
      act()
      return prim_calls() - before
    end

    local function full_party()
      env.party = { party1_count = 6 }
      for slot = 1, 6 do
        env.party["p" .. (slot - 1)] = member("Mem" .. slot, 100 + slot)
      end
      settle()
    end

    it("writes nothing when the scale it is given is the one it holds", function()
      full_party()
      assert.are.equal(
        0,
        measure(function()
          widget.set_scale(1)
        end)
      )
    end)

    it("writes nothing when the position it is given is the one it holds", function()
      full_party()
      widget.set_pos(300, 400)
      assert.are.equal(
        0,
        measure(function()
          widget.set_pos(300, 400)
        end)
      )
    end)

    it("writes nothing when the preview flag it is given is the one it holds", function()
      full_party()
      widget.set_preview(true)
      assert.are.equal(
        0,
        measure(function()
          widget.set_preview(true)
        end)
      )
    end)

    -- A move changes no drawn value -- not a text, colour, alpha, path,
    -- visibility or fill width -- so it re-places without redrawing. A scale
    -- change has to do both, because the fill widths are written by render().
    it("costs less to move than to rescale", function()
      full_party()
      local move = measure(function()
        widget.set_pos(301, 401)
      end)
      local rescale = measure(function()
        widget.set_scale(1.25)
      end)
      assert.is_true(move > 0)
      assert.is_true(move < rescale)
    end)

    -- The whole point of the gate: one core.apply per mouse move used to cost
    -- three full rebuilds, two of them for values that had not moved.
    it("costs one placement pass for a whole core.apply, not three rebuilds", function()
      full_party()
      widget.set_preview(true)
      local placement = measure(function()
        widget.set_pos(310, 410)
      end)
      local apply = measure(function()
        widget.set_scale(1)
        widget.set_pos(311, 411)
        widget.get_bounds()
        widget.set_preview(true)
      end)
      assert.are.equal(placement, apply)
    end)

    local function first_fill()
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("xiv/Bar.png", 1, true) then
          return prim
        end
      end
    end

    --[[ logic.tick() is not a query. It advances the ease and clears the
         forced flag, and draw_row writes a fill's width only on the tick that
         moved it -- so a move that ticks without drawing can swallow the tick
         that lands on the target, and the fill stays part-drawn for good.

         Dragging the list in layout mode is exactly that sequence. ]]
    it("does not swallow the bar ease while it is being moved", function()
      local function settled_width(drag)
        build("main")
        env.party = { p0 = member("Ayame", 1) }
        settle()
        env.party = { p0 = member("Ayame", 1, { hp = 400, hpp = 40 }) }
        env.clock = env.clock + 1
        widget.update()
        if drag then
          for step = 1, 30 do
            widget.set_pos(100 + step, 200)
          end
        end
        settle()
        return first_fill().width
      end
      assert.are.equal(settled_width(false), settled_width(true))
    end)

    -- layout.clamp hands back a fractional x at a non-integral scale, and the
    -- background's placement signature is the only thing a move invalidates.
    -- Truncate the position into that signature and the frame stays behind
    -- while the rows it wraps move out from under it.
    it("moves the background too when only the fraction of the position changes", function()
      full_party()
      widget.set_pos(100.1, 200)
      local before = {}
      for index, prim in ipairs(prims.all) do
        before[index] = prim.x
      end
      widget.set_pos(100.9, 200)
      for index, prim in ipairs(prims.all) do
        if before[index] then
          assert.is_true(math.abs(prim.x - (before[index] + 0.8)) < 1e-9)
        end
      end
    end)

    -- Core reads get_bounds and clamps straight after set_pos, and layout mode
    -- draws its highlight from the same read -- all before the next render.
    -- So a move has to land on the prims now, not on the following frame.
    it("moves every prim without waiting for a render", function()
      full_party()
      local before = {}
      for index, prim in ipairs(prims.all) do
        before[index] = prim.x
      end
      widget.set_pos(140, 200)
      for index, prim in ipairs(prims.all) do
        if before[index] then
          assert.are.equal(before[index] + 40, prim.x)
        end
      end
    end)
  end)

  describe("visibility", function()
    it("hides every prim when the framework hides it", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      widget.hide()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    it("shows the list again without needing another party update", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      widget.hide()
      widget.show()
      local visible = 0
      for _, prim in ipairs(prims.all) do
        visible = visible + (prim.visible and 1 or 0)
      end
      assert.is_true(visible > 0)
    end)

    it("draws nothing at all while detached", function()
      widget.detach()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)
  end)

  describe("hiding while solo", function()
    -- XIVParty's hideSolo. The framework has no equivalent -- it knows about
    -- cutscenes and zoning, not party size -- so the component draws nothing
    -- rather than deciding it is off screen.
    it("draws nothing when the only member is the player", function()
      widget.defaults.hide_solo = true
      widget.attach(widget.defaults, function() end)
      env.party = { p0 = member("Ayame", 1) }
      settle(3)
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    it("draws the list again as soon as somebody joins", function()
      widget.defaults.hide_solo = true
      widget.attach(widget.defaults, function() end)
      env.party = { p0 = member("Ayame", 1) }
      settle(3)
      env.party = { p0 = member("Ayame", 1), p1 = member("Volker", 2) }
      settle(3)
      local shown = 0
      for _, prim in ipairs(prims.all) do
        shown = shown + (prim.visible and 1 or 0)
      end
      assert.is_true(shown > 0)
    end)

    it("draws a solo party when hide_solo is off", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(3)
      local shown = 0
      for _, prim in ipairs(prims.all) do
        shown = shown + (prim.visible and 1 or 0)
      end
      assert.is_true(shown > 0)
    end)
  end)

  describe("an empty list", function()
    -- Turning a list on with nobody in its slots must not leave an empty
    -- frame on screen -- an alliance list you have enabled but are not
    -- currently in is exactly this case, and hide_solo is not involved.
    it("draws nothing at all, frame included", function()
      env.party = {}
      settle(3)
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    it("draws the frame again as soon as somebody occupies it", function()
      build("alliance1")
      env.party = {}
      settle(3)
      env.party = { a10 = member("Zeid", 1) }
      settle(3)
      local shown = 0
      for _, prim in ipairs(prims.all) do
        shown = shown + (prim.visible and 1 or 0)
      end
      assert.is_true(shown > 0)
    end)
  end)

  describe("the poll", function()
    it("reads the party once per interval rather than once per frame", function()
      env.party = { p0 = member("Ayame", 1) }
      widget.update()
      env.polls = 0
      -- Ten frames inside one 200ms window.
      for _ = 1, 10 do
        env.clock = env.clock + 0.01
        widget.update()
      end
      assert.are.equal(0, env.polls)
      env.clock = env.clock + 0.2
      widget.update()
      assert.are.equal(1, env.polls)
    end)

    -- The cursor follows the target key, so it cannot wait up to 200ms for the
    -- next poll; one cheap lookup a frame is the price of that.
    it("reads the target every frame", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      env.target_reads = 0
      for _ = 1, 5 do
        widget.update()
      end
      assert.are.equal(5, env.target_reads)
    end)
  end)

  describe("commands", function()
    it("answers with the lines the parser produced", function()
      local reply = widget.handle_command({ "spacing", "4" })
      assert.are.equal("table", type(reply))
      assert.is_not_nil(table.concat(reply, "\n"):find("spacing", 1, true))
    end)

    it("saves and re-lays out when a command changed something", function()
      local saves = 0
      widget.attach(widget.defaults, function()
        saves = saves + 1
      end)
      widget.handle_command({ "spacing", "4" })
      assert.are.equal(1, saves)
    end)

    it("does not save when a command changed nothing", function()
      local saves = 0
      widget.attach(widget.defaults, function()
        saves = saves + 1
      end)
      widget.handle_command({ "wobble" })
      assert.are.equal(0, saves)
    end)
  end)

  describe("the target cursor", function()
    -- The buff icon grid runs past the row's own edge; the highlight has to
    -- reach it, or a targeted member's buffs sit outside their own cursor.
    it("extends the target cursor across the buff icon grid", function()
      env.targets.t = { id = 1 }
      env.party = { p0 = member("Ayame", 1) }
      settle(3)
      local cursor = nil
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("Cursor.png", 1, true) then
          cursor = prim
        end
      end
      assert.is_not_nil(cursor)
      local x = select(1, widget.get_bounds())
      local right = cursor.x - x + cursor.width
      -- 24 is the left margin; the icon grid's own right edge is 24 + 460.
      assert.is_true(right >= 24 + 460, ("cursor ends at %.0f, the icon grid ends at 484"):format(right))
    end)

    it("marks the targeted row", function()
      env.targets.t = { id = 2 }
      env.party = { p0 = member("Ayame", 1), p1 = member("Volker", 2) }
      settle(3)
      local marked = 0
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("Cursor.png", 1, true) and prim.visible then
          marked = marked + 1
        end
      end
      assert.are.equal(1, marked)
    end)

    -- st, stpt and stal are three names for the subtarget depending on which
    -- menu opened it; any of them has to reach the cursor.
    it("half-marks a row subtargeted through any of the subtarget slots", function()
      for _, kind in ipairs({ "st", "stpt", "stal" }) do
        build("main")
        env.targets[kind] = { id = 2 }
        env.party = { p0 = member("Ayame", 1), p1 = member("Volker", 2) }
        settle(3)
        local half = false
        for _, prim in ipairs(prims.images) do
          if type(prim.last.path) == "string" and prim.last.path:find("Cursor.png", 1, true) then
            half = half or (prim.visible and prim.last.alpha == 127)
          end
        end
        assert.is_true(half, kind .. " does not reach the cursor")
      end
    end)
  end)

  describe("packets", function()
    it("takes leader flags from an alliance packet", function()
      env.party = { p0 = member("Volker", 2) }
      settle(2)
      widget.update("chunk", 0x0C8, "raw", { ["ID 1"] = 2, ["Flags 1"] = 4 })
      settle(2)
      local leader = 0
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("Leader.png", 1, true) and prim.visible then
          leader = leader + 1
        end
      end
      assert.are.equal(1, leader)
    end)

    -- 0x0DD is the only packet carrying a name next to an id, and the id is
    -- what an out-of-zone member loses along with their mob table.
    it("remembers the name and id a party member packet pairs up", function()
      env.party = { p0 = member("Volker", 2, { zone = 50, elsewhere = true }) }
      settle(3)
      widget.update("chunk", 0x0DD, "raw", {
        ID = 2,
        Index = 1,
        Name = "Volker",
        Zone = 50,
        HP = 1,
        MP = 1,
        ["HP%"] = 1,
        ["MP%"] = 1,
      })
      widget.update("chunk", 0x0C8, "raw", { ["ID 1"] = 2, ["Flags 1"] = 4 })
      settle(3)
      local leader = 0
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("xiv/Leader.png", 1, true) and prim.visible then
          leader = leader + 1
        end
      end
      assert.are.equal(1, leader)
    end)

    it("takes vitals and jobs from a char update", function()
      env.party = { p0 = member("Volker", 2) }
      settle(3)
      widget.update("chunk", 0x0DF, "raw", {
        ID = 2,
        Index = 1,
        HP = 400,
        MP = 50,
        HPP = 40,
        MPP = 10,
        ["Main job"] = 4,
        ["Main job level"] = 99,
        ["Sub job"] = 4,
        ["Sub job level"] = 49,
      })
      frames()
      local said = {}
      for _, prim in ipairs(prims.texts) do
        said[#said + 1] = tostring(prim.last.text)
      end
      assert.is_not_nil(table.concat(said, "|"):find("400", 1, true))
      assert.is_not_nil(table.concat(said, "|"):find("WHM 99", 1, true))
    end)

    -- The player's own vitals never arrive in a party packet; they come as the
    -- same change events parambar reads.
    it("takes the player's own vitals from the change events", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(3)
      widget.update("hp", 123)
      widget.update("hpp", 12)
      frames()
      local said = {}
      for _, prim in ipairs(prims.texts) do
        said[#said + 1] = tostring(prim.last.text)
      end
      assert.is_not_nil(table.concat(said, "|"):find("123", 1, true))
    end)

    it("ignores a packet id it does not listen for", function()
      assert.has_no.errors(function()
        widget.update("chunk", 0x001, "whatever", nil)
      end)
    end)
  end)

  describe("construction", function()
    it("answers to a short alias, the main list alone", function()
      build("main")
      assert.are.equal("pl", widget.alias)
      build("alliance1")
      assert.is_nil(widget.alias, "an alliance list is reached by its own name")
      build("alliance2")
      assert.is_nil(widget.alias)
    end)
  end)

  describe("the alliance variant", function()
    it("reads its own party keys and draws the smaller row", function()
      build("alliance1")
      env.party = { p0 = member("Ayame", 1), a10 = member("Zeid", 3) }
      settle(2)
      local named = false
      for _, prim in ipairs(prims.texts) do
        named = named or prim.last.text == "Zeid"
      end
      assert.is_true(named)
    end)

    -- The alliance layout asks for hideOutsideZone; the main list leaves an
    -- empty bar reading '?' instead.
    it("takes an out-of-zone member's bars away entirely", function()
      build("alliance1")
      env.party = { a10 = member("Zeid", 3, { zone = 50, elsewhere = true }) }
      settle(3)
      for _, prim in ipairs(prims.images) do
        if type(prim.last.path) == "string" and prim.last.path:find("AllyBar", 1, true) then
          assert.is_false(prim.visible)
        end
      end
    end)

    it("draws fewer prims per row than the main list", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local main_row = #prims.all
      build("alliance1")
      env.party = { a10 = member("Zeid", 3) }
      settle(2)
      assert.is_true(#prims.all < main_row)
    end)
  end)
end)
