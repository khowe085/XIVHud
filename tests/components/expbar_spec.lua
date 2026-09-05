local new_expbar = require("components/expbar/expbar")
local fakes = require("tests/support/fakes")

local CHAR_STATS = 0x061
local CHAR_UPDATE = 0x063
local ACTION_MESSAGE = 0x02D
local UNHANDLED = 0x00A

describe("expbar widget", function()
  local prims, widget
  local clock, player, saves, parsed, last, parses

  local function header()
    return prims.texts[1]
  end

  local function icon_glyph()
    return prims.images[1]
  end

  local function background()
    return prims.images[2]
  end

  local function fill()
    return prims.images[3]
  end

  --[[ A distinct table, the way core hands one over: lib/settings deep-copies
       the merged config, so the widget never sees its own defaults object back.
       Attaching the defaults table itself would alias what the logic already
       holds and let a broken `config = loaded_config` pass unseen. ]]
  local function copy(value)
    if type(value) ~= "table" then
      return value
    end
    local result = {}
    for key, entry in pairs(value) do
      result[key] = copy(entry)
    end
    return result
  end

  local function attach(config)
    config = config or copy(widget.defaults)
    widget.attach(config, function()
      saves = saves + 1
    end)
    return config
  end

  -- One frame, as core drives it: no arguments is the tick.
  local function tick(times)
    for _ = 1, times or 1 do
      widget.update()
    end
  end

  -- 0x063 reaches the widget already parsed by the entry point (three
  -- components read it); the other two ids it parses itself.
  local function chunk(id, packet)
    if id == CHAR_UPDATE then
      widget.update("chunk", id, "raw bytes for " .. id, packet)
      return
    end
    parsed[id] = packet
    widget.update("chunk", id, "raw bytes for " .. id)
  end

  local function char_stats(current, required)
    return {
      ["Current EXP"] = current,
      ["Required EXP"] = required,
      ["Master Level"] = 0,
      ["Master Breaker"] = false,
      ["Current Exemplar Points"] = 0,
      ["Required Exemplar Points"] = 2500,
    }
  end

  before_each(function()
    prims = fakes.prims()
    clock = 0
    saves = 0
    parsed = {}
    parses = {}
    last = {}
    player = {
      name = "Tester",
      main_job = "WAR",
      main_job_full = "Warrior",
      main_job_level = 75,
      sub_job = "SAM",
      sub_job_level = 37,
      job_points = { war = { jp = 342 } },
    }
    widget = new_expbar({
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      asset = function(file)
        return "addons/XIVHud/" .. file
      end,
      now = function()
        return clock
      end,
      get_player = function()
        return player
      end,
      parse_packet = function(data)
        parses[#parses + 1] = data
        for id, packet in pairs(parsed) do
          if data == "raw bytes for " .. id or data == "last " .. id then
            return packet
          end
        end
        return nil
      end,
      last_incoming = function(id)
        return last[id]
      end,
    })
  end)

  describe("construction", function()
    it("is named for its config namespace and command word", function()
      assert.are.equal("expbar", widget.name)
    end)

    it("answers to a short alias of its own", function()
      assert.are.equal("eb", widget.alias)
    end)

    it("centres its default slot under the parameter bar", function()
      local slot = widget.defaults.layout
      assert.are.equal(843, slot.pos.x)
      assert.are.equal(1048, slot.pos.y)
    end)

    it("builds one header, one job glyph and two bar images", function()
      assert.are.equal(1, #prims.texts)
      assert.are.equal(3, #prims.images)
    end)

    it("makes every prim non-draggable, because the framework owns dragging", function()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(false, prim.last.draggable, prim.kind .. " must not drag itself")
      end
    end)

    it("stops both images sizing themselves to their texture, which would defeat scale", function()
      assert.are.equal(false, background().last.fit)
      assert.are.equal(false, fill().last.fit)
    end)

    it("points both images at the packaged art", function()
      assert.are.equal("addons/XIVHud/assets/barfiller/bar_bg.png", background().last.path)
      assert.are.equal("addons/XIVHud/assets/barfiller/bar_fg.png", fill().last.path)
    end)

    it("draws the glyph on nothing, the gold reading on its own", function()
      -- No backing, no frame: three images in total, and the glyph is one.
      assert.is_nil(icon_glyph().last.path)
    end)

    it("does not right-justify the header, which would push it off screen", function()
      assert.is_nil(header().last.right_justified)
    end)

    it("starts hidden, because the framework decides what is on screen", function()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
        local hidden = false
        for _, call in ipairs(prim.calls) do
          hidden = hidden or call.name == "hide"
        end
        assert.is_true(hidden, prim.kind .. " must hide itself, not merely start that way")
      end
    end)

    it("draws the header on nothing and both images once over", function()
      assert.are.equal(false, header().last.bg_visible)
      assert.are.equal(0, header().last.bg_alpha)
      assert.are.same({ 1, 1 }, background().last.repeat_xy)
      assert.are.same({ 1, 1 }, fill().last.repeat_xy)
    end)
  end)

  describe("attach", function()
    it("seeds itself from the packets that arrived before it was attached", function()
      last[CHAR_STATS] = "last " .. CHAR_STATS
      last[CHAR_UPDATE] = "last " .. CHAR_UPDATE
      parsed[CHAR_STATS] = char_stats(2500, 5000)
      parsed[CHAR_UPDATE] = { Order = 2, ["Limit Points"] = 0, ["Merit Points"] = 9, ["Max Merit Points"] = 30 }
      attach()
      widget.set_pos(100, 200)
      tick()
      assert.are.equal("WAR75/SAM37 JP: 342 MP: 9 EXP/hr: 0.0k", header().last.text)
    end)

    it("carries on when no such packet has arrived", function()
      attach()
      widget.set_pos(100, 200)
      tick()
      assert.are.equal("WAR75/SAM37 JP: 342 MP: 0 EXP/hr: 0.0k", header().last.text)
    end)

    it("pushes the configured text style", function()
      attach()
      assert.are.equal("sans-serif", header().last.font)
      -- Gold, matching the job glyph beside it and the bar's fill below.
      assert.are.same({ 255, 215, 0 }, header().last.color)
      assert.are.equal(255, header().last.alpha)
      assert.are.equal(2, header().last.stroke_width)
      assert.are.equal(150, header().last.stroke_alpha)
    end)

    it("lays the bar out under the header", function()
      attach()
      widget.set_pos(100, 200)
      assert.are.same({ 117, 200 }, { header().x, header().y })
      -- The bar is flush with the header; the icon stands left of both rows.
      assert.are.same({ 117, 211 }, { background().x, background().y })
      assert.are.same({ 119, 211 }, { fill().x, fill().y })
      assert.are.same({ 217, 5 }, { background().width, background().height })
    end)
  end)

  describe("the job icon", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
      widget.show()
    end)

    it("draws the main job's glyph left of the header", function()
      tick()
      assert.are.equal("addons/XIVHud/assets/xiv/jobIcons/war.png", icon_glyph().last.path)
      assert.are.same({ 100, 200 }, { icon_glyph().x, icon_glyph().y })
      -- Square, spanning the header row, the gap and the bar.
      assert.are.same({ 16, 16 }, { icon_glyph().width, icon_glyph().height })
      assert.are.equal(117, header().x)
    end)

    it("re-points the glyph on a job change", function()
      tick()
      player.main_job = "BLM"
      tick()
      assert.are.equal("addons/XIVHud/assets/xiv/jobIcons/blm.png", icon_glyph().last.path)
    end)

    it("writes the glyph's path once while the job holds", function()
      tick()
      local before = #icon_glyph().calls
      tick(10)
      assert.are.equal(before, #icon_glyph().calls)
    end)

    it("draws no glyph until the client names a job", function()
      player.main_job = nil
      tick()
      assert.is_false(icon_glyph().visible)
      assert.is_true(header().visible)
    end)

    it("takes the glyph away again if the client stops naming a job", function()
      tick()
      assert.is_true(icon_glyph().visible)
      player.main_job = nil
      tick()
      assert.is_false(icon_glyph().visible)
    end)

    it("hides the glyph with the widget", function()
      tick()
      assert.is_true(icon_glyph().visible)
      widget.hide()
      assert.is_false(icon_glyph().visible)
    end)
  end)

  describe("drawing", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
      widget.show()
    end)

    it("fills the bar toward the packet's percentage", function()
      chunk(CHAR_STATS, char_stats(2500, 5000))
      tick(200)
      assert.are.equal(106, fill().width)
      assert.are.equal(5, fill().height)
    end)

    it("hides the fill alone while there is nothing to draw", function()
      chunk(CHAR_STATS, char_stats(0, 5000))
      tick(200)
      assert.is_false(fill().visible)
      assert.is_true(background().visible)
      assert.is_true(header().visible)
    end)

    it("tints the fill from the config, one colour for every mode", function()
      local tinted = copy(widget.defaults)
      tinted.fill_color = { r = 10, g = 20, b = 30 }
      widget.attach(tinted, function() end)
      widget.set_pos(100, 200)
      chunk(CHAR_STATS, char_stats(2500, 5000))
      tick()
      assert.are.same({ 10, 20, 30 }, fill().last.color)
    end)

    it("leaves a hidden widget hidden, whatever the bar does", function()
      -- core ticks every component whether or not it is on screen, so a bar
      -- that moves while the HUD is suppressed must not put the fill back.
      chunk(CHAR_STATS, char_stats(2500, 5000))
      tick(200)
      widget.hide()
      chunk(CHAR_STATS, char_stats(4000, 5000))
      tick(200)
      assert.is_false(fill().visible)
      assert.is_false(background().visible)
      assert.is_false(header().visible)
    end)

    it("keeps an empty fill hidden when the widget is shown again", function()
      -- show() runs on its own, outside the render path, so it has to know the
      -- fill is empty rather than assume the next frame will hide it.
      chunk(CHAR_STATS, char_stats(0, 5000))
      tick(200)
      widget.hide()
      widget.show()
      assert.is_false(fill().visible)
      assert.is_true(background().visible)
    end)

    it("writes the header only when the line has changed", function()
      chunk(CHAR_STATS, char_stats(2500, 5000))
      tick(200)
      local before = #header().calls
      tick(10)
      assert.are.equal(before, #header().calls)
    end)

    it("stops writing to the prims once the bar has settled", function()
      chunk(CHAR_STATS, char_stats(2500, 5000))
      tick(200)
      local before = #fill().calls
      tick(10)
      assert.are.equal(before, #fill().calls)
    end)

    it("scales the fill with the widget", function()
      chunk(CHAR_STATS, char_stats(5000, 5000))
      tick(200)
      widget.set_scale(2)
      tick()
      assert.are.equal(426, fill().width)
      assert.are.equal(10, fill().height)
    end)

    it("advances the bar on a gain between packets", function()
      chunk(CHAR_STATS, char_stats(0, 5000))
      tick(200)
      chunk(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 2500, ["Param 2"] = 0 })
      tick(200)
      assert.are.equal(106, fill().width)
    end)
  end)

  describe("packets", function()
    before_each(function()
      attach()
      widget.set_pos(100, 200)
    end)

    -- A pre-parse that failed is a nil `third`; the bytes are not parsed a
    -- second time here, the same library having just failed on them.
    it("does not re-parse a 0x063 the entry point could not", function()
      chunk(CHAR_UPDATE, nil)
      assert.are.equal(0, #parses)
    end)

    it("parses only the two ids it alone reads; 0x063 arrives parsed", function()
      chunk(UNHANDLED, { Order = 2 })
      assert.are.equal(0, #parses)
      chunk(CHAR_STATS, char_stats(1, 2))
      chunk(CHAR_UPDATE, { Order = 2 })
      chunk(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 1, ["Param 2"] = 0 })
      assert.are.equal(2, #parses)
    end)

    it("survives a packet it could not parse", function()
      widget.update("chunk", CHAR_STATS, "unparseable")
      tick()
      assert.are.equal("WAR75/SAM37 JP: 342 MP: 0 EXP/hr: 0.0k", header().last.text)
    end)

    it("times a gain on the addon clock, not the packet", function()
      chunk(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 540, ["Param 2"] = 0 })
      clock = 60
      tick()
      assert.are.equal("WAR75/SAM37 JP: 342 MP: 0 EXP/hr: 32.4k", header().last.text)
    end)
  end)

  describe("the character's own configuration", function()
    it("draws from the config it is handed, not from its defaults", function()
      local config = copy(widget.defaults)
      config.bar = { width = 200, height = 9, inset = 4 }
      config.gap = 6
      config.font_size = 20
      config.text_color = { a = 128, r = 1, g = 2, b = 3 }
      config.text_stroke = { width = 5, a = 64, r = 4, g = 5, b = 6 }
      config.fill_color = { r = 7, g = 8, b = 9 }

      attach(config)
      widget.set_pos(100, 200)
      widget.show()
      chunk(CHAR_STATS, char_stats(5000, 5000))
      tick(200)

      assert.are.equal(20, header().font_size)
      assert.are.same({ 1, 2, 3 }, header().last.color)
      assert.are.equal(128, header().last.alpha)
      assert.are.equal(5, header().last.stroke_width)
      assert.are.equal(64, header().last.stroke_alpha)
      -- font 20 draws a 26px line, so the bar sits 32 below the origin, and
      -- both clear the icon the defaults derived at the shipped font.
      assert.are.same({ 117, 232 }, { background().x, background().y })
      assert.are.same({ 200, 9 }, { background().width, background().height })
      assert.are.equal(121, fill().x)
      assert.are.equal(192, fill().width)
      assert.are.same({ 7, 8, 9 }, fill().last.color)
      local _, _, width, height = widget.get_bounds()
      assert.are.same({ 217, 41 }, { width, height })
    end)
  end)

  describe("a second character", function()
    it("starts from the client rather than from the last one's numbers", function()
      attach()
      widget.set_pos(100, 200)
      widget.show()
      chunk(CHAR_STATS, char_stats(2500, 5000))
      chunk(CHAR_UPDATE, { Order = 2, ["Limit Points"] = 0, ["Merit Points"] = 12, ["Max Merit Points"] = 30 })
      chunk(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 540, ["Param 2"] = 0 })
      clock = 60
      tick(200)

      widget.detach()
      -- Nobody has sent the new character a state packet yet, so there is
      -- nothing to seed from and the widget must not fall back on what it held.
      player.name = "Someone Else"
      player.main_job = "BLM"
      player.job_points = nil
      attach()
      widget.set_pos(100, 200)
      widget.show()
      clock = 120
      tick()

      assert.are.equal("BLM75/SAM37 JP: 0 MP: 0 EXP/hr: 0.0k", header().last.text)
      assert.are.equal(0, fill().width)
      assert.is_false(fill().visible)
    end)

    --[[ A slot switch and `//hud reset expbar` both re-attach the SAME
         character, and neither is a reason to forget what they have earned.
         Nothing can be re-read to make up for it either: `last_incoming` is
         keyed by packet id, and 0x063 is multiplexed over five orders, so the
         merit seed only lands if order 2 happened to be the last one sent. ]]
    it("keeps everything through a re-attach of the same character", function()
      -- The login packet is still what `last_incoming` answers with: 0x061 is
      -- not resent per kill, which is the whole reason the 0x02D deltas exist.
      -- Re-applying it on a re-attach would rewind the bar to login.
      last[CHAR_STATS] = "last " .. CHAR_STATS
      parsed[CHAR_STATS] = char_stats(2500, 5000)
      attach()
      widget.set_pos(100, 200)
      widget.show()
      chunk(CHAR_STATS, char_stats(2500, 5000))
      chunk(CHAR_UPDATE, { Order = 2, ["Limit Points"] = 0, ["Merit Points"] = 12, ["Max Merit Points"] = 30 })
      chunk(ACTION_MESSAGE, { Message = 8, ["Param 1"] = 540, ["Param 2"] = 0 })
      clock = 60
      tick(200)

      widget.detach()
      attach()
      widget.set_pos(100, 200)
      widget.show()
      tick()

      assert.are.equal("WAR75/SAM37 JP: 342 MP: 12 EXP/hr: 32.4k", header().last.text)
      assert.are.equal(129, fill().width)
    end)
  end)

  describe("the framework contract", function()
    it("returns the origin it was given", function()
      attach()
      widget.set_pos(100, 200)
      local x, y, width, height = widget.get_bounds()
      assert.are.same({ 100, 200, 234, 16 }, { x, y, width, height })
    end)

    it("has no bounds before it is placed", function()
      assert.is_nil(widget.get_bounds())
    end)

    it("hides everything on hide", function()
      attach()
      widget.set_pos(100, 200)
      widget.show()
      widget.hide()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    it("hides everything when it is detached", function()
      attach()
      widget.set_pos(100, 200)
      widget.show()
      widget.detach()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    it("draws nothing while it is detached", function()
      attach()
      widget.set_pos(100, 200)
      widget.detach()
      local before = #header().calls
      tick(5)
      assert.are.equal(before, #header().calls)
    end)

    it("shows a sample in layout mode, before anything has been earned", function()
      attach()
      widget.set_pos(100, 200)
      widget.show()
      widget.set_preview(true)
      tick(200)
      assert.are.equal("WAR99/SAM49 (ML23) JP: 342 MP: 12 EP/hr: 12.6k", header().last.text)
      assert.is_true(fill().width > 0)
    end)

    it("answers its own command, and asks for no save doing it", function()
      attach()
      assert.are.equal("expbar rate history cleared", widget.handle_command({ "clear" }))
      -- Nothing here writes config, so nothing may ask core to persist one.
      assert.are.equal(0, saves)
    end)

    it("shows the sample job's icon in layout mode", function()
      attach()
      widget.set_pos(100, 200)
      widget.show()
      widget.set_preview(true)
      tick()
      assert.are.equal("addons/XIVHud/assets/xiv/jobIcons/war.png", icon_glyph().last.path)
      assert.is_true(icon_glyph().visible)
    end)

    it("disposes every prim it built", function()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed)
      end
    end)
  end)
end)
