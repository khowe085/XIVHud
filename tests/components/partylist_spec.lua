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
  -- The list a plain `widget.set_pos(...)` in this file addresses. The three
  -- are one component now, so every placement names an anchor; `build` picks
  -- which one the block that follows is about.
  local anchor
  local generation_count, generation_deadline

  local function build(variant)
    prims = fakes.prims()
    env = { party = {}, targets = {}, clock = 0, polls = 0, target_reads = 0, saves = 0 }
    env.player = {
      name = "Ayame",
      buffs = {},
      main_job_id = 4,
      main_job_level = 99,
      sub_job_id = 5,
      sub_job_level = 49,
    }
    generation_count, generation_deadline = 0, nil

    anchor = variant or "main"

    local ctx = {
      name = "partylist",
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      asset = function(path)
        return "addons/XIVHud/" .. path
      end,
      resources = RESOURCES,
      -- One table, so a spec can move a field on it between reads: lib/player
      -- hands the same object back for the whole interval, and the point of
      -- reading per frame is that a keyed invalidation lands inside one.
      get_player = function()
        return env.player
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
      --[[ lib/player's read counter, faked to its real contract: reading it opens
           the interval, so it advances for a caller that gates every one of its
           reads behind it. A fake driven by the clock alone would pass over a
           service that had stopped advancing. ]]
      generation = function()
        if generation_deadline == nil or env.clock >= generation_deadline then
          generation_deadline = env.clock + 0.2
          generation_count = generation_count + 1
        end
        return generation_count
      end,
    }

    widget = new_partylist(ctx)
    widget.attach(widget.defaults, function()
      env.saves = env.saves + 1
    end)
    -- Only the anchor under test is placed: an unplaced list draws nothing,
    -- which keeps a block about one list counting only that list's prims.
    widget.set_scale(1, anchor)
    widget.set_pos(100, 200, anchor)
    -- A bare show is the widget's own switch, and puts every list up: the
    -- alliance lists ship hidden through the framework's per-anchor `visible`,
    -- which is core's to push and not this widget's to hold.
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

  -- One anchor placed the way core does it: scale first, then position.
  local function place(name, x, y)
    widget.set_scale(1, name)
    widget.set_pos(x, y, name)
  end

  before_each(function()
    build("main")
  end)

  describe("prims", function()
    -- Three background prims apiece, and all three lists build theirs in the
    -- factory whether or not they are ever placed.
    local FRAME_PRIMS = 3 * 3

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
      widget.defaults.lists[anchor].align_bottom = true
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
      local x, y = widget.get_bounds(anchor)
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
      local x, y, width, height = widget.get_bounds(anchor)

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
      local _, _, full_width, full_height = widget.get_bounds(anchor)
      widget.set_scale(0.5, anchor)
      local _, _, width, height = widget.get_bounds(anchor)
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
      widget.set_scale(2, anchor)
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
      })
      assert.is_nil(fresh.get_bounds())
    end)

    -- Moving the group moves every row with it; nothing is positioned against
    -- the screen, only against the list's own origin.
    -- The frame has to contain the rows. align_bottom moves the rows to the
    -- foot of the box, and the background has to follow them there.
    it("keeps the background around the rows when the list is aligned to the bottom", function()
      widget.defaults.lists[anchor].align_bottom = true
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
        -- Every list builds a background, and the two alliance lists ship
        -- switched off, so only this one's is ever shown.
        if prim.visible and type(prim.last.path) == "string" then
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
      local _, _, _, one_row = widget.get_bounds(anchor)
      widget.set_preview(true)
      local _, _, _, previewing = widget.get_bounds(anchor)
      assert.is_true(previewing > one_row)
    end)

    --[[ The frame has to reach across the buff icon grid -- which now runs
         past the row's own edge, all the way to x=460, so the bars can be
         covered along with it -- without trailing unboundedly far past that. ]]
    it("draws the frame across the icon grid without overshooting it", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)

      local x = select(1, widget.get_bounds(anchor))
      local strip = nil
      for _, prim in ipairs(prims.images) do
        if prim.visible and type(prim.last.path) == "string" and prim.last.path:find("BgMid", 1, true) then
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
      widget.set_pos(150, 200, anchor)
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
          widget.set_scale(1, anchor)
        end)
      )
    end)

    it("writes nothing when the position it is given is the one it holds", function()
      full_party()
      widget.set_pos(300, 400, anchor)
      assert.are.equal(
        0,
        measure(function()
          widget.set_pos(300, 400, anchor)
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
        widget.set_pos(301, 401, anchor)
      end)
      local rescale = measure(function()
        widget.set_scale(1.25, anchor)
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
        widget.set_pos(310, 410, anchor)
      end)
      local apply = measure(function()
        widget.set_scale(1, anchor)
        widget.set_pos(311, 411, anchor)
        widget.get_bounds(anchor)
        widget.set_preview(true)
      end)
      assert.are.equal(placement, apply)
    end)

    --[[ The reason PA0 was a prerequisite: core.apply pushes a placement for
         EVERY anchor on every mouse-move event, and now all three are inside
         one component. Dragging one list must not lay out the other two -
         untouched, this shape was measured at roughly 5000 prim calls per
         event against the old 2882. ]]
    it("lays out only the anchor that moved, over a whole three-anchor apply", function()
      full_party()
      widget.handle_command({ "alliance1", "on" })
      widget.handle_command({ "alliance2", "on" })
      for _, name in ipairs({ "alliance1", "alliance2" }) do
        widget.set_scale(1, name)
        widget.set_pos(700, 300, name)
      end
      env.party.a10 = member("Ally1", 200)
      env.party.a20 = member("Ally2", 201)
      settle()

      local moved = measure(function()
        widget.set_pos(320, 420, anchor)
      end)
      -- Exactly what core does per mouse move: scale then position for every
      -- anchor, the preview flag, then show().
      local apply = measure(function()
        widget.set_scale(1, "main")
        widget.set_pos(321, 421, "main")
        widget.set_scale(1, "alliance1")
        widget.set_pos(700, 300, "alliance1")
        widget.set_scale(1, "alliance2")
        widget.set_pos(700, 300, "alliance2")
        widget.set_preview(false)
        widget.show()
      end)
      assert.is_true(moved > 0)
      assert.are.equal(moved, apply, "an apply must cost the moved anchor's placement and nothing else")
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
            widget.set_pos(100 + step, 200, anchor)
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
      widget.set_pos(100.1, 200, anchor)
      local before = {}
      for index, prim in ipairs(prims.all) do
        before[index] = prim.x
      end
      widget.set_pos(100.9, 200, anchor)
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
      widget.set_pos(140, 200, anchor)
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
      widget.defaults.lists.main.hide_solo = true
      widget.attach(widget.defaults, function() end)
      env.party = { p0 = member("Ayame", 1) }
      settle(3)
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    it("draws the list again as soon as somebody joins", function()
      widget.defaults.lists.main.hide_solo = true
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

    --[[ The player is read every FRAME while the roster rides the counter, and
         this is what that buys. Your own buff icons come off get_player().buffs
         - no packet carries them for you - and a `gain buff` sends the entry
         point's keyed invalidate("player"), which refreshes the player without
         moving the counter. Read on the counter instead and your own buffs
         would wait for the next roster rebuild.

         The counter is held still here deliberately: that is the whole case. ]]
    it("shows the player's own new buff without waiting for a roster rebuild", function()
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local function own_icons()
        local shown = 0
        for _, prim in ipairs(prims.images) do
          if type(prim.last.path) == "string" and prim.last.path:find("buffIcons", 1, true) and prim.visible then
            shown = shown + 1
          end
        end
        return shown
      end
      assert.are.equal(0, own_icons())

      -- REPLACED, not mutated: set_main_player stores the table by reference,
      -- so moving a field on it would be visible whether or not the setter ran
      -- again - and the test would pass against the gated placement too.
      env.player = {
        name = "Ayame",
        buffs = { 33 },
        main_job_id = 4,
        main_job_level = 99,
        sub_job_id = 5,
        sub_job_level = 49,
      }
      widget.update()
      assert.is_true(own_icons() > 0, "the player's own buff waited for the next roster rebuild")
    end)

    --[[ The read counter survives a detach, so without the reset on attach a
         relog inside one interval would leave the previous character's roster
         on screen until the service next read. targetbar has the same guard. ]]
    it("reads the party again on the first frame after a fresh attach", function()
      env.party = { p0 = member("Ayame", 1) }
      widget.update()
      local before = env.polls
      widget.detach()
      widget.attach(widget.defaults, function() end)
      widget.update()
      assert.is_true(env.polls > before, "a relog waited out the interval before reading the party")
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
      local x = select(1, widget.get_bounds(anchor))
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
    -- One registration backs all three lists, so there is one name to claim a
    -- short word for. Three registrations off one factory could not: each
    -- would claim `pl` and the second would abort the load.
    it("registers under one name and claims the short alias", function()
      build()
      assert.are.equal("partylist", widget.name)
      assert.are.equal("pl", widget.alias)
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
  --[[ The three lists are ONE registered component with three anchors, so the
       framework places each of them independently, and switches each of them
       on and off independently too. Everything here is the anchor half of the
       widget contract. ]]
  --[[ The alliance lists ship switched off - most play is a single party, and
       two empty boxes read as a bug. That is a per-anchor `visible` in the
       LAYOUT defaults now, which core reads and pushes, rather than a config
       flag the component enforced itself. ]]
  describe("the shipped per-anchor visibility", function()
    it("ships both alliance lists hidden and the main party shown", function()
      build()
      local anchors = widget.defaults.layout.anchors
      assert.is_false(anchors.alliance1.visible)
      assert.is_false(anchors.alliance2.visible)
      assert.is_nil(anchors.main.visible, "absent means shown")
    end)

    it("keeps no on/off flag of its own in the config defaults", function()
      build()
      for _, name in ipairs({ "main", "alliance1", "alliance2" }) do
        assert.is_nil(widget.defaults.lists[name].enabled, name .. " must not carry a second switch")
      end
    end)
  end)

  describe("multi-anchor contract", function()
    it("declares its three anchors, main first", function()
      build()
      assert.are.same({ "main", "alliance1", "alliance2" }, widget.anchors())
    end)

    --[[ layout.repair keys the anchored branch off the DEFAULTS, so a stray
         top-level pos would be shed from every stored file it repaired.

         Iterated from anchors() rather than a hardcoded list, and counted in
         both directions: the ordered names live in partylist.lua and the
         seeding copy in defaults.lua, so an anchor added to one alone would
         otherwise reach a list with no defaults at all - at factory time,
         before login, which is the failure this repo cannot diagnose. ]]
    it("seeds a placement and a settings block for every anchor it declares", function()
      build()
      local layout = widget.defaults.layout
      assert.is_nil(layout.pos)
      assert.is_nil(layout.scale)
      assert.is_true(layout.visible)

      local seeded = 0
      for _ in pairs(widget.defaults.lists) do
        seeded = seeded + 1
      end
      assert.are.equal(#widget.anchors(), seeded, "defaults and anchors() must name the same lists")

      for _, name in ipairs(widget.anchors()) do
        assert.is_table(layout.anchors[name].pos, name .. " must ship a position")
        assert.is_number(layout.anchors[name].scale, name .. " must ship a scale")
        assert.is_table(widget.defaults.lists[name], name .. " must ship its own settings")
      end

      -- Seeded only where it can be drawn: the alliance row layout has no range
      -- block, and the verb is refused there.
      assert.is_table(widget.defaults.lists.main.range)
      assert.is_nil(widget.defaults.lists.alliance1.range)
      assert.is_nil(widget.defaults.lists.alliance2.range)
    end)

    it("gives each anchor back the origin it was given", function()
      build()
      place("main", 100, 200)
      place("alliance1", 300, 400)
      place("alliance2", 500, 600)
      env.party = { p0 = member("Ayame", 1), a10 = member("Zeid", 3), a20 = member("Curilla", 5) }
      settle(2)
      local function origin(name)
        local x, y = widget.get_bounds(name)
        return { x, y }
      end
      assert.are.same({ 100, 200 }, origin("main"))
      assert.are.same({ 300, 400 }, origin("alliance1"))
      assert.are.same({ 500, 600 }, origin("alliance2"))
    end)

    -- get_bounds and set_pos route through the same lookup, so bounds alone
    -- cannot tell a correct fan-out from one that moves the wrong list.
    it("draws each list at its own anchor's origin", function()
      build()
      place("main", 100, 200)
      place("alliance1", 900, 200)
      widget.handle_command({ "alliance1", "on" })
      env.party = { p0 = member("Ayame", 1), a10 = member("Zeid", 3) }
      settle(2)

      local main_x, ally_x = nil, nil
      for _, prim in ipairs(prims.texts) do
        if prim.visible then
          main_x = main_x or (prim.last.text == "Ayame" and prim.x or nil)
          ally_x = ally_x or (prim.last.text == "Zeid" and prim.x or nil)
        end
      end
      assert.is_not_nil(main_x)
      assert.is_not_nil(ally_x)
      assert.is_true(main_x >= 100 and main_x < 500, ("main drew at %.0f"):format(main_x))
      assert.is_true(ally_x >= 900, ("alliance1 drew at %.0f"):format(ally_x))
    end)

    it("scales one anchor without touching another", function()
      build()
      place("main", 100, 200)
      place("alliance1", 300, 400)
      env.party = { p0 = member("Ayame", 1), a10 = member("Zeid", 3) }
      settle(2)
      local _, _, main_width = widget.get_bounds("main")
      local _, _, ally_width = widget.get_bounds("alliance1")
      widget.set_scale(0.5, "alliance1")
      assert.are.equal(main_width, select(3, widget.get_bounds("main")))
      assert.are.equal(ally_width / 2, select(3, widget.get_bounds("alliance1")))
    end)

    -- Crossbar's guard: core fans every placement out over every anchor, and a
    -- name that is not ours must cost nothing rather than crash the apply.
    it("ignores a placement for an anchor it does not have", function()
      build()
      place("main", 100, 200)
      assert.has_no.errors(function()
        widget.set_pos(10, 20, "wxhb_left")
        widget.set_scale(3, nil)
        widget.set_pos(10, 20)
      end)
      assert.is_nil(widget.get_bounds("wxhb_left"))
      local x, y = widget.get_bounds("main")
      assert.are.same({ 100, 200 }, { x, y })
    end)

    it("reports no bounds for an anchor it has never been given a position for", function()
      build()
      place("main", 100, 200)
      assert.is_nil(widget.get_bounds("alliance1"))
    end)
  end)
  --[[ show/hide/detach are the framework's, and reach the widget as a whole -
       auto-hide during a cutscene or a zone, and the logout that detaches. A
       fan-out that quietly served the main list alone would leave the alliance
       lists on screen through a cutscene, which no spec placing one anchor can
       see. ]]
  describe("the framework's whole-widget calls", function()
    local function all_three_drawing()
      build()
      for _, name in ipairs({ "alliance1", "alliance2" }) do
        widget.set_scale(1, name)
        widget.set_pos(700, 200, name)
      end
      env.party = { p0 = member("Ayame", 1), a10 = member("Zeid", 3), a20 = member("Curilla", 5) }
      settle(2)
      local drawn = {}
      for _, prim in ipairs(prims.texts) do
        if prim.visible then
          drawn[tostring(prim.last.text)] = true
        end
      end
      for _, name in ipairs({ "Ayame", "Zeid", "Curilla" }) do
        assert.is_true(drawn[name] == true, name .. " has to be on screen before it can be taken off it")
      end
    end

    local function nothing_visible()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible, "a prim was left on screen")
      end
    end

    it("takes every list off screen on hide", function()
      all_three_drawing()
      widget.hide()
      nothing_visible()
    end)

    --[[ Per-anchor visibility is the framework's now: core sends hide(<list>)
         for a list switched off in the layout file and show(<list>) for one
         that is on, and the component's own `enabled` flag is gone with the
         commands that wrote it. ]]
    it("takes one list off screen on hide(<list>) and leaves the others", function()
      all_three_drawing()
      widget.hide("alliance1")
      settle(2)
      local drawn = {}
      for _, prim in ipairs(prims.texts) do
        if prim.visible then
          drawn[tostring(prim.last.text)] = true
        end
      end
      assert.is_nil(drawn.Zeid, "alliance1 was hidden")
      assert.is_true(drawn.Ayame)
      assert.is_true(drawn.Curilla)
    end)

    it("brings one list back on show(<list>)", function()
      all_three_drawing()
      widget.hide("alliance1")
      settle(2)
      widget.show("alliance1")
      settle(2)
      local drawn = false
      for _, prim in ipairs(prims.texts) do
        drawn = drawn or (prim.visible and prim.last.text == "Zeid")
      end
      assert.is_true(drawn)
    end)

    -- Core walks the anchors in declared order, so a show for one arrives
    -- among hides for the others: restoring the lot on a NAMED show would put
    -- a list back on screen with the file still saying it is off.
    it("leaves the other hidden lists alone on a named show", function()
      all_three_drawing()
      widget.hide("alliance1")
      widget.hide("alliance2")
      widget.show("alliance2")
      settle(2)
      local drawn = {}
      for _, prim in ipairs(prims.texts) do
        if prim.visible then
          drawn[tostring(prim.last.text)] = true
        end
      end
      assert.is_true(drawn.Curilla, "alliance2 was the one asked for")
      assert.is_nil(drawn.Zeid, "alliance1 must stay down")
    end)

    -- A whole-widget show is what core sends in layout mode, and it has to
    -- undo a per-anchor hide or a hidden list could never be dragged back.
    it("brings every list back on a whole-widget show", function()
      all_three_drawing()
      widget.hide("alliance1")
      widget.hide("alliance2")
      widget.show()
      settle(2)
      local drawn = {}
      for _, prim in ipairs(prims.texts) do
        if prim.visible then
          drawn[tostring(prim.last.text)] = true
        end
      end
      assert.is_true(drawn.Zeid)
      assert.is_true(drawn.Curilla)
    end)

    -- An anchor name that is not ours has to cost nothing, the way every other
    -- anchor-addressed call on this widget treats one.
    it("ignores a show or hide for an anchor it does not have", function()
      all_three_drawing()
      assert.has_no.errors(function()
        widget.hide("wobble")
        widget.show("wobble")
      end)
      settle(2)
      local drawn = false
      for _, prim in ipairs(prims.texts) do
        drawn = drawn or (prim.visible and prim.last.text == "Zeid")
      end
      assert.is_true(drawn, "no list may go down for a name that addresses none of them")
    end)

    it("takes every list off screen on detach", function()
      all_three_drawing()
      widget.detach()
      nothing_visible()
    end)

    -- The config the outgoing character was attached to, and the closure that
    -- writes it, must not outlive the detach. Core does not route a command to
    -- a detached component, so this is a defence rather than a live path.
    it("stops writing config once it has been detached", function()
      build()
      widget.detach()
      local before = env.saves
      widget.handle_command({ "spacing", "4" })
      assert.are.equal(before, env.saves)
    end)

    -- The other half of the rule below: placing a list is what makes it
    -- drawable, so the placement has to re-ask the question. Core always
    -- follows a placement with show(), which is why nothing noticed - but a
    -- widget that only draws if its caller happens to call the right thing
    -- next is the silent failure this repo keeps being bitten by.
    it("draws a list the moment it is placed, without waiting to be shown again", function()
      build()
      widget.show()
      env.party = { a10 = member("Zeid", 3) }
      settle(2)
      widget.set_scale(1, "alliance1")
      widget.set_pos(700, 200, "alliance1")
      settle(2)

      local drawn, framed = false, false
      for _, prim in ipairs(prims.texts) do
        drawn = drawn or (prim.visible and prim.last.text == "Zeid")
      end
      -- The row's own prims come back through the draw path, which asks
      -- drawing() per element. The background does not: it is behind a cache
      -- only apply_visibility writes, so it is the half that stays dark.
      for _, prim in ipairs(prims.images) do
        if prim.visible and type(prim.last.path) == "string" and prim.last.path:find("BgTop", 1, true) then
          framed = framed or (prim.x ~= nil and prim.x >= 700)
        end
      end
      assert.is_true(drawn, "the row has to draw")
      assert.is_true(framed, "and so does the frame behind it")
    end)

    --[[ A list core has shown but never placed has no origin to draw at, and
         its background would otherwise be pushed onto the screen at whatever
         position the prims were created with. Unreachable through core, which
         places every anchor before it shows anything - but `drawing()` is what
         the rest of this file relies on to mean "on screen". ]]
    it("draws nothing for a list that has been shown but never placed", function()
      build()
      widget.show()
      for _, prim in ipairs(prims.all) do
        if prim.visible then
          assert.is_not_nil(prim.x, "a prim was shown before it was ever placed")
        end
      end
    end)
  end)

  --[[ `//hud partylist [<list>] <verb> ...`. The list word leads, and its
       absence means the main party - so every line that worked while the three
       were separate components still means what it did. Switching one list on
       and off is NOT here: `//hud show|hide partylist <list>` is the
       framework's, addressing the anchor. ]]
  describe("the command router", function()
    local function said(args)
      return table.concat(widget.handle_command(args), "\n")
    end

    it("addresses the main party when no list is named", function()
      build()
      said({ "spacing", "4" })
      assert.are.equal(4, widget.defaults.lists.main.item_spacing)
      assert.are.equal(0, widget.defaults.lists.alliance1.item_spacing)
    end)

    it("addresses the list it is given", function()
      build()
      said({ "alliance1", "spacing", "6" })
      assert.are.equal(6, widget.defaults.lists.alliance1.item_spacing)
      assert.are.equal(0, widget.defaults.lists.main.item_spacing)
    end)

    -- The per-list on/off is the framework's now (`//hud show|hide partylist
    -- <list>`, and SHIFT + right-click in layout mode), so the verb that used
    -- to write it is gone rather than kept as a second switch beside it.
    --[[ It worked yesterday, so it is worth naming where it went rather than
         answering with the generic hint - which cannot name it either, since
         `//hud show|hide` is the framework's and this module knows nothing
         about it. ]]
    it("points its removed on|off verb at the framework's switch", function()
      build()
      local reply = said({ "alliance1", "off" })
      assert.is_not_nil(reply:find("//hud hide partylist alliance1", 1, true), "said: " .. reply)
      assert.is_not_nil(said({ "on" }):find("//hud show partylist main", 1, true))
      assert.is_nil(said({ "alliance1" }):find("enabled", 1, true))
    end)

    -- A hint that offers a verb the next line refuses is worse than no hint.
    it("stops offering on and off in the verb hint", function()
      build()
      local hint = said({ "alliance1", "wobble" })
      assert.is_nil(hint:find("on,", 1, true), "hint: " .. hint)
      assert.is_nil(hint:find("off,", 1, true), "hint: " .. hint)
      assert.is_not_nil(hint:find("spacing", 1, true))
    end)

    -- The asymmetry is real - 0x076 carries the main party alone and the
    -- alliance row draws no buff icons - so it is refused out loud rather than
    -- quietly applied to a list the user did not name.
    it("refuses the main-only verbs at an alliance list", function()
      build()
      local reply = said({ "alliance1", "hidesolo", "on" })
      assert.is_not_nil(reply:find("main party only", 1, true))
      assert.is_false(widget.defaults.lists.main.hide_solo == true)
      assert.is_not_nil(said({ "alliance2", "buff", "reset" }):find("main party only", 1, true))
    end)

    -- The alliance row layout has no range block at all, so the setting could
    -- only ever be stored and never drawn.
    it("refuses range at an alliance list too", function()
      build()
      assert.is_not_nil(said({ "alliance1", "range", "5", "10" }):find("main party only", 1, true))
      said({ "range", "5", "10" })
      assert.are.equal(5, widget.defaults.lists.main.range.near)
    end)

    -- A report that advertises a setting the next command refuses is worse than
    -- either one alone.
    it("leaves range out of an alliance list's own report", function()
      build()
      assert.is_nil(said({ "alliance1" }):find("range", 1, true))
      assert.is_not_nil(said({ "main" }):find("range", 1, true))
    end)

    it("leaves range out of an alliance list's own verb hint", function()
      build()
      local hint = said({ "alliance1", "wobble" })
      assert.is_nil(hint:find("range", 1, true))
      assert.is_not_nil(said({ "wobble" }):find("range", 1, true))
    end)

    it("still takes the main-only verbs at the main party", function()
      build()
      said({ "hidesolo", "on" })
      assert.is_true(widget.defaults.lists.main.hide_solo)
      said({ "main", "hidesolo", "off" })
      assert.is_false(widget.defaults.lists.main.hide_solo)
    end)

    it("reports every list when nothing is named, and one when it is", function()
      build()
      local all = said({})
      assert.is_not_nil(all:find("partylist alliance1", 1, true))
      assert.is_not_nil(all:find("partylist alliance2", 1, true))
      local one = said({ "alliance2" })
      assert.is_not_nil(one:find("partylist alliance2", 1, true))
      assert.is_nil(one:find("alliance1", 1, true))
    end)

    it("answers an unknown verb with the hint it always did", function()
      build()
      assert.is_not_nil(said({ "wobble" }):find("wobble", 1, true))
    end)
  end)

  --[[ PA4: a list switched off must still be draggable, or it can never be
       positioned again. In layout mode core sends the WIDGET's show - never a
       per-anchor one - so a hidden list comes back up with the rest, and its
       bounds have to be right whether or not it is drawing. ]]
  describe("layout mode against a switched-off list", function()
    it("draws a list that is off once the widget is force-shown, and stops after", function()
      build("alliance1")
      widget.hide("alliance1")
      env.party = { a10 = member("Zeid", 3) }
      settle(2)

      widget.show()
      widget.set_preview(true)
      settle(2)
      local drawn = false
      for _, prim in ipairs(prims.texts) do
        drawn = drawn or (prim.visible and type(prim.last.text) == "string" and prim.last.text ~= "")
      end
      assert.is_true(drawn, "a switched-off list must draw in layout mode")

      widget.set_preview(false)
      widget.hide("alliance1")
      for _, prim in ipairs(prims.texts) do
        assert.is_false(prim.visible)
      end
    end)

    it("reports bounds for a switched-off list, so it can still be dragged", function()
      build("alliance1")
      widget.hide("alliance1")
      local x, y, width = widget.get_bounds("alliance1")
      assert.are.same({ 100, 200 }, { x, y })
      assert.is_true(width > 0)
    end)
  end)
  --[[ config.lua is code and is hand-editable, and `//hud copy` imports another
       character's - so a list entry can be any shape at all by the time it
       arrives. It has to degrade to defaults: this attach runs inside core's
       login path, under the guard-wrapped prerender, where five errors disable
       the render loop outright. ]]
  describe("a config that is not the shape it should be", function()
    local function attach(config)
      build()
      widget.attach(config, function()
        env.saves = env.saves + 1
      end)
      widget.set_scale(1, "main")
      widget.set_pos(100, 200, "main")
      widget.show()
    end

    it("falls back to defaults for a list entry that is not a table", function()
      assert.has_no.errors(function()
        attach({ lists = { main = 1, alliance1 = "on", alliance2 = false } })
      end)
      env.party = { p0 = member("Ayame", 1) }
      settle(2)
      local drawn = false
      for _, prim in ipairs(prims.texts) do
        drawn = drawn or (prim.visible and prim.last.text == "Ayame")
      end
      assert.is_true(drawn, "the main list must still draw on defaults")
    end)

    it("falls back to defaults when there are no list entries at all", function()
      for _, broken in ipairs({ { lists = "nonsense" }, {} }) do
        assert.has_no.errors(function()
          attach(broken)
        end)
        -- Not just "it did not throw": a config swallowed whole would leave
        -- every list unattached, which draws nothing and says nothing.
        assert.is_table(broken.lists.main, "the config must be seeded in place")
        assert.are.equal(0, broken.lists.main.item_spacing)
        widget.handle_command({ "spacing", "7" })
        assert.are.equal(7, broken.lists.main.item_spacing)
      end
    end)

    -- Writing into the defaults instead would make every command a silent
    -- no-op: save() serialises the config it was attached to, which would never
    -- have seen the change.
    it("writes a command into the config it was attached to", function()
      local config = { lists = {} }
      attach(config)
      widget.handle_command({ "spacing", "4" })
      assert.are.equal(4, config.lists.main.item_spacing)
      assert.are.equal(0, widget.defaults.lists.main.item_spacing)
      widget.handle_command({ "alliance1", "spacing", "9" })
      assert.are.equal(9, config.lists.alliance1.item_spacing)
      assert.are.equal(0, widget.defaults.lists.alliance1.item_spacing)
    end)
  end)
end)
