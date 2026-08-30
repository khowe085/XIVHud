local new_targetbar = require("components/targetbar/targetbar")
local fakes = require("tests/support/fakes")

describe("targetbar widget", function()
  local prims, assets, widget
  local target, party, player, me, clock, saves, target_reads
  local generation_count, generation_deadline

  -- The prims are built in draw order: the hp layers, then the cast's.
  local function background()
    return prims.images[1]
  end

  local function fill()
    return prims.images[2]
  end

  local function frame()
    return prims.images[3]
  end

  local function cast_fill()
    return prims.images[5]
  end

  local function cast_frame()
    return prims.images[6]
  end

  local function cast_name()
    return prims.texts[4]
  end

  local function hp()
    return prims.texts[1]
  end

  local function distance()
    return prims.texts[2]
  end

  local function name()
    return prims.texts[3]
  end

  --[[ A distinct table, the way core hands one over: settings deep-copies the
       merged config, so the widget never sees its own defaults object back.
       Attaching the defaults table itself would alias the widget's initial
       config and let a broken `config = loaded_config` pass unseen. ]]
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

  local function mob(fields)
    local result = {
      id = 100,
      name = "Greater Colibri",
      hpp = 100,
      claim_id = 0,
      in_party = false,
      is_npc = true,
      distance = 144,
      model_size = 1.0,
    }
    for key, value in pairs(fields or {}) do
      result[key] = value
    end
    return result
  end

  before_each(function()
    prims = fakes.prims()
    assets = {}
    target = nil
    party = {}
    player = { main_job = "WAR" }
    me = { id = 1, model_size = 1.0 }
    clock = 0
    saves = 0
    target_reads = 0
    generation_count, generation_deadline = 0, nil
    widget = new_targetbar({
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return 1920, 1080
      end,
      get_mob_by_target = function(kind)
        if kind == "t" then
          target_reads = target_reads + 1
          return target
        end
        if kind == "me" then
          return me
        end
        return nil
      end,
      get_party = function()
        return party
      end,
      get_player = function()
        return player
      end,
      --[[ lib/player's read counter, faked to its real contract: reading it opens
           the interval, so it advances for a caller - this one - that gates all
           of its reads behind it. ]]
      generation = function()
        if generation_deadline == nil or clock >= generation_deadline then
          generation_deadline = clock + 0.2
          generation_count = generation_count + 1
        end
        return generation_count
      end,
      now = function()
        return clock
      end,
      asset = function(file)
        assets[#assets + 1] = file
        return "addons/XIVHud/" .. file
      end,
      resources = {
        spells = { [144] = { en = "Fire IV", cast_time = 8 } },
        monster_abilities = { [672] = { en = "Blood Drain" } },
      },
    })
  end)

  -- The target winds up Fire IV: the raw chunk arrives with the action the
  -- entry point's dispatch already parsed out of it, and the widget forwards
  -- that to the tracker.
  local function begin_cast()
    widget.update("chunk", 0x028, "raw action bytes", {
      actor_id = 100,
      category = 8,
      param = 0,
      targets = { { id = 1, actions = { { param = 144, message = 327 } } } },
    })
  end

  describe("construction", function()
    it("is named for its config namespace and command word", function()
      assert.are.equal("targetbar", widget.name)
      assert.are.equal("tb", widget.alias)
    end)

    it("centres its default slot on the row it draws", function()
      local slot = widget.defaults.layout
      assert.are.equal(704, slot.pos.x)
      assert.are.equal(50, slot.pos.y)
    end)

    it("builds four texts and six bar layers", function()
      assert.are.equal(4, #prims.texts)
      assert.are.equal(6, #prims.images)
    end)

    it("points every layer at its own copy of the art", function()
      assert.are.same({
        "assets/xiv/wide/BarBG.png",
        "assets/xiv/wide/Bar.png",
        "assets/xiv/wide/BarFG.png",
        "assets/xiv/wide/CastBG.png",
        "assets/xiv/wide/CastBar.png",
        "assets/xiv/wide/CastFG.png",
      }, assets)
    end)

    -- The one right-justified text in the addon: the cast name grows leftward
    -- from the box's right edge, and its position pre-subtracts the screen
    -- width the library will add back.
    it("right-justifies only the cast name", function()
      assert.is_true(cast_name().last.right_justified)
      assert.is_nil(hp().last.right_justified)
    end)

    -- fit(true) sizes a prim to its texture, which would defeat both the
    -- halving the art needs and the widget's own scale.
    it("never lets a layer size itself to its texture", function()
      for _, image in ipairs(prims.images) do
        assert.is_false(image.last.fit)
      end
    end)

    it("leaves every prim non-draggable, since the framework drags the group", function()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.last.draggable)
      end
    end)

    -- A text background is a drawn element with its own footprint, and the
    -- widget's bounds make no room for one.
    it("turns off the text backgrounds", function()
      for _, text in ipairs(prims.texts) do
        assert.is_false(text.last.bg_visible)
      end
    end)

    -- Explicit rather than trusting the library's defaults, which CLAUDE.md
    -- classes as unverified until read in the sources.
    it("paints the plate and frame opaque white at construction", function()
      assert.are.same({ 255, 255, 255 }, background().last.color)
      assert.are.equal(255, background().last.alpha)
      assert.are.same({ 255, 255, 255 }, frame().last.color)
      assert.are.equal(255, frame().last.alpha)
    end)

    it("draws one copy of each texture rather than a tiled grid", function()
      for _, image in ipairs(prims.images) do
        assert.are.same({ 1, 1 }, image.last.repeat_xy)
      end
    end)

    it("draws nothing before it is attached", function()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)
  end)

  describe("styling", function()
    before_each(function()
      attach()
    end)

    it("gives every segment the configured font", function()
      for _, text in ipairs(prims.texts) do
        assert.are.equal("Arial", text.last.font)
      end
    end)

    it("strokes every segment so it reads over the game world", function()
      for _, text in ipairs(prims.texts) do
        assert.are.equal(2, text.last.stroke_width)
        assert.are.same({ 6, 45, 84 }, text.last.stroke_color)
      end
    end)

    --[[ stroke_alpha, not stroke_transparency: the library reads transparency
         as 0..1 and computes 255 * (1 - value), so handing it an alpha of 200
         produces a wildly negative one. CLAUDE.md records this costing real
         debugging time. ]]
    it("sets the stroke's opacity as an alpha, not as a transparency", function()
      for _, text in ipairs(prims.texts) do
        assert.are.equal(200, text.last.stroke_alpha)
        assert.is_nil(text.last.stroke_transparency)
      end
    end)

    it("clears the text background's alpha as well as its flag", function()
      for _, text in ipairs(prims.texts) do
        assert.are.equal(0, text.last.bg_alpha)
      end
    end)

    it("honours a translucent text colour", function()
      local restyled = copy(widget.defaults)
      restyled.text_color = { a = 120, r = 1, g = 2, b = 3 }
      attach(restyled)
      widget.set_pos(100, 100)
      widget.show()
      target = mob({ hpp = 90 })
      widget.update()
      assert.are.equal(120, name().last.alpha)
    end)

    it("honours a translucent fill colour", function()
      local restyled = copy(widget.defaults)
      restyled.fill_colors.unclaimed = { a = 90, r = 230, g = 230, b = 138 }
      attach(restyled)
      widget.set_pos(100, 100)
      widget.show()
      target = mob({ claim_id = 0 })
      widget.update()
      assert.are.equal(90, fill().last.alpha)
    end)

    it("adopts the config it is handed, not the one it was built with", function()
      local loaded = copy(widget.defaults)
      loaded.font = "Consolas"
      loaded.text_stroke = { width = 4, a = 100, r = 1, g = 2, b = 3 }
      loaded.name_max_chars = 3
      attach(loaded)
      widget.set_pos(100, 100)
      widget.show()
      target = mob({ name = "Bugbear" })
      widget.update()
      assert.are.equal("Consolas", hp().last.font)
      assert.are.equal(4, hp().last.stroke_width)
      assert.are.equal(100, hp().last.stroke_alpha)
      -- Through to logic as well, not just the prim styling.
      assert.are.equal("Bug", name().last.text)
    end)

    --[[ The defaults merge preserves a user's scalar where the defaults have a
         table, so a hand-edited config can put a number where the style
         sections belong - on the attach path, which runs at every login. ]]
    it("survives style sections that are not tables", function()
      local mangled = copy(widget.defaults)
      mangled.text_color = "red"
      mangled.text_stroke = 3
      assert.has_no.errors(function()
        attach(mangled)
      end)
      -- Degraded to defined values, not left as getters holding whatever the
      -- previous character's config put on the prim.
      assert.are.equal(0, hp().last.stroke_width)
      assert.are.equal("Arial", hp().last.font)
    end)

    -- Windower setters given only nils turn into getters, so a colour with
    -- missing channels must be filled in rather than passed through.
    it("never hands the colour setter a channel of nothing", function()
      local bare = copy(widget.defaults)
      bare.text_color = {}
      attach(bare)
      assert.are.same({ 255, 255, 255 }, hp().last.color)
    end)

    it("fills missing channels on the per-frame colour path too", function()
      local bare = copy(widget.defaults)
      bare.fill_colors.unclaimed = { a = 90 }
      attach(bare)
      widget.set_pos(100, 100)
      widget.show()
      target = mob({ claim_id = 0 })
      widget.update()
      assert.are.same({ 255, 255, 255 }, fill().last.color)
      assert.are.equal(90, fill().last.alpha)
    end)
  end)

  describe("visibility", function()
    before_each(function()
      attach()
      widget.set_pos(100, 100)
      target = mob()
    end)

    it("stays hidden until the framework shows it", function()
      widget.update()
      assert.is_false(frame().visible)
    end)

    it("draws the row once shown with a target", function()
      widget.show()
      widget.update()
      assert.is_true(frame().visible)
      assert.is_true(fill().visible)
      assert.is_true(hp().visible)
      assert.is_true(distance().visible)
      assert.is_true(name().visible)
    end)

    it("hides every prim when the framework hides it", function()
      widget.show()
      widget.update()
      widget.hide()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    -- Nothing targeted is not the same as the widget being switched off, but
    -- it draws the same: no bar, and no leftover row of text.
    it("draws nothing at all with no target", function()
      widget.show()
      target = nil
      widget.update()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)

    --[[ Releasing the target is the commonest thing this widget sees, and the
         one failure that would be obvious in play: a bar left frozen on a mob
         the player is no longer looking at. ]]
    it("clears the row when the target is released", function()
      widget.show()
      widget.update()
      assert.is_true(frame().visible)
      assert.is_true(name().visible)

      target = nil
      widget.update()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible, "something was left on screen after the target was released")
      end
    end)

    it("comes back when a target returns", function()
      widget.show()
      target = nil
      widget.update()
      target = mob()
      widget.update()
      assert.is_true(frame().visible)
    end)

    it("shows the sample target in preview with nothing targeted", function()
      widget.show()
      widget.set_preview(true)
      target = nil
      widget.update()
      assert.is_true(frame().visible)
      assert.is_true(#name().last.text > 0)
    end)

    it("hides everything again once detached", function()
      widget.show()
      widget.update()
      widget.detach()
      for _, prim in ipairs(prims.all) do
        assert.is_false(prim.visible)
      end
    end)
  end)

  describe("drawing", function()
    before_each(function()
      attach()
      widget.set_pos(100, 100)
      widget.show()
      target = mob()
    end)

    it("writes the row's three segments", function()
      target = mob({ hpp = 63, name = "Colibri", distance = 144 })
      widget.update()
      assert.are.equal("63%", hp().last.text)
      assert.are.equal("12.00", distance().last.text)
      assert.are.equal("Colibri", name().last.text)
    end)

    it("tints the fill by the claim state", function()
      target = mob({ claim_id = 0 })
      widget.update()
      assert.are.same({ 230, 230, 138 }, fill().last.color)
    end)

    it("sizes the fill from the health, inside the frame's fill region", function()
      target = mob({ hpp = 50 })
      widget.update()
      assert.are.equal(243, fill().width)
      -- Full height: the fill art carries the band's vertical placement.
      assert.are.equal(64, fill().height)
    end)

    it("draws the plate and frame at the art's drawn size", function()
      widget.update()
      assert.are.equal(512, background().width)
      assert.are.equal(64, background().height)
      assert.are.equal(512, frame().width)
      assert.are.equal(64, frame().height)
    end)

    --[[ Only the fill tracks the health. The reference addon reset its
         background's width every single frame with a comment saying it had no
         idea why that was needed; here the plate is sized once with the rest
         of the layout and left alone. ]]
    it("keeps the background at the frame's full width whatever the health", function()
      target = mob({ hpp = 10 })
      widget.update()
      assert.is_true(background().visible)
      assert.are.equal(512, background().width)
    end)

    it("hides the fill at once when the target is dead on arrival", function()
      target = mob({ hpp = 0 })
      widget.update()
      assert.is_false(fill().visible)
      -- The plate and frame stay: a dead target is still a target.
      assert.is_true(background().visible)
      assert.is_true(frame().visible)
    end)

    it("hides just the fill on a dead target, keeping the frame", function()
      target = mob({ hpp = 100 })
      widget.update()
      target = mob({ hpp = 0 })
      for _ = 1, 200 do
        widget.update()
      end
      assert.is_false(fill().visible)
      assert.is_true(frame().visible)
    end)

    --[[ This is the one component with a per-frame prim write, so it keeps
         partylist's discipline: a value that has not moved is not pushed. ]]
    it("does not rewrite a value that has not changed", function()
      widget.update()
      local before = #hp().calls
      widget.update()
      widget.update()
      assert.are.equal(before, #hp().calls)
    end)

    it("does rewrite once the value moves", function()
      widget.update()
      local before = #hp().calls
      target = mob({ hpp = 42 })
      widget.update()
      assert.is_true(#hp().calls > before)
    end)
  end)

  describe("layout", function()
    before_each(function()
      attach()
      widget.show()
    end)

    -- Core clamps the widget by comparing this to what it passed set_pos.
    it("hands back exactly the origin it was given", function()
      widget.set_pos(300, 400)
      local x, y = widget.get_bounds()
      assert.are.equal(300, x)
      assert.are.equal(400, y)
    end)

    it("has no bounds before it has been positioned", function()
      assert.is_nil(widget.get_bounds())
    end)

    it("reports the row's full width", function()
      widget.set_pos(300, 400)
      local _, _, width = widget.get_bounds()
      assert.are.equal(512, width)
    end)

    it("shrinks with the scale", function()
      widget.set_pos(300, 400)
      local _, _, full = widget.get_bounds()
      widget.set_scale(0.5)
      local _, _, half = widget.get_bounds()
      assert.is_true(half < full)
    end)

    it("places the three segments across the row at the drawn font size", function()
      widget.set_pos(300, 400)
      assert.are.equal(310.5, hp().x)
      assert.are.equal(400, hp().y)
      assert.are.equal(363.5, distance().x)
      assert.are.equal(416.5, name().x)
      -- The three row segments share the row font; the cast name below has
      -- its own smaller one.
      for index = 1, 3 do
        assert.are.equal(14, prims.texts[index].font_size)
      end
      assert.are.equal(12, cast_name().font_size)
    end)

    -- A prim cannot draw a fractional font, so the size it is handed has to be
    -- the whole-pixel one the reserves were measured against.
    it("rounds the drawn font when scaled", function()
      widget.set_pos(300, 400)
      widget.set_scale(0.25)
      assert.are.equal(4, hp().font_size)
    end)

    it("insets the fill inside the frame rather than leaving it at the origin", function()
      widget.set_pos(300, 400)
      assert.are.equal(frame().x + 13, fill().x)
      assert.are.equal(frame().y, fill().y)
    end)

    it("drops the bar below the text rather than over it", function()
      widget.set_pos(300, 400)
      assert.is_true(frame().y > hp().y)
    end)

    it("moves the whole group when repositioned", function()
      widget.set_pos(100, 100)
      target = mob()
      widget.update()
      local first = frame().x
      widget.set_pos(200, 100)
      assert.are.equal(first + 100, frame().x)
    end)

    -- Fill widths are only written when the health moves, so a scale change
    -- has to push them itself or the bar keeps the old scale's size.
    it("resizes the fill when the scale changes, not just on the next hit", function()
      widget.set_pos(100, 100)
      target = mob({ hpp = 100 })
      widget.update()
      local before = fill().width
      widget.set_scale(0.5)
      widget.update()
      assert.is_true(fill().width < before)
    end)
  end)

  describe("polling", function()
    before_each(function()
      attach()
      widget.set_pos(100, 100)
      widget.show()
      target = mob()
    end)

    it("reads the party and the player on the first frame", function()
      local reads = 0
      widget = new_targetbar({
        new_text = prims.new_text,
        new_image = prims.new_image,
        screen = function()
          return 1920, 1080
        end,
        get_mob_by_target = function()
          return nil
        end,
        get_party = function()
          reads = reads + 1
          return {}
        end,
        get_player = function()
          return player
        end,
        generation = function()
          if generation_deadline == nil or clock >= generation_deadline then
            generation_deadline = clock + 0.2
            generation_count = generation_count + 1
          end
          return generation_count
        end,
        now = function()
          return clock
        end,
        asset = function(file)
          return file
        end,
      })
      widget.attach(widget.defaults, function() end)
      widget.set_pos(100, 100)
      widget.update()
      assert.are.equal(1, reads)
    end)

    it("does not read the party again inside the interval", function()
      local reads = 0
      party = setmetatable({}, {
        __index = function()
          reads = reads + 1
          return nil
        end,
      })
      widget.update()
      widget.update()
      widget.update()
      -- Eighteen keys per poll; three frames inside one window is still one.
      assert.are.equal(18, reads)
    end)

    it("colours the fill from the party roster it polled", function()
      party = { p0 = { name = "Ally", mob = { id = 77 } } }
      target = mob({ claim_id = 77 })
      widget.update()
      assert.are.same({ 255, 20, 20 }, fill().last.color)
    end)
  end)

  describe("the cast bar", function()
    before_each(function()
      attach()
      widget.set_pos(100, 100)
      widget.show()
      target = mob()
      widget.update()
    end)

    it("draws nothing while nobody casts", function()
      assert.is_false(cast_frame().visible)
      assert.is_false(cast_fill().visible)
      assert.is_false(cast_name().visible)
    end)

    it("raises the bar when the target starts casting", function()
      begin_cast()
      widget.update()
      assert.is_true(cast_frame().visible)
      assert.are.equal("Fire IV", cast_name().last.text)
      -- The fill itself waits for the first sliver of progress: a zero-width
      -- prim is hidden, exactly like the hp fill at zero health.
      assert.is_false(cast_fill().visible)
      clock = 1
      widget.update()
      assert.is_true(cast_fill().visible)
    end)

    --[[ The action packet is decoded once, in the entry point's chunk
         dispatch, and handed down as the fourth argument -- targetbar's cast
         bar and the crossbar's skillchain engine used to parse it one apiece.
         So the widget is given an action, never a parser: this drives it with
         a ctx that has no way to decode anything. ]]
    it("raises the bar from the action the dispatch already parsed", function()
      widget.update("chunk", 0x028, "raw action bytes", {
        actor_id = 100,
        category = 8,
        param = 0,
        targets = { { id = 1, actions = { { param = 144, message = 327 } } } },
      })
      widget.update()
      assert.is_true(cast_frame().visible)
      assert.are.equal("Fire IV", cast_name().last.text)
    end)

    it("fills with the cast's progress, not the target's health", function()
      begin_cast()
      widget.update()
      local at_start = cast_fill().width
      clock = 4
      widget.update()
      -- Half of Fire IV's 8s: half the cast art's 230px region at 0.67.
      assert.are.equal(115 * 0.67, cast_fill().width)
      assert.is_true(cast_fill().width > at_start)
    end)

    --[[ This counted the widget's own parse calls until CB6, when the entry
         point took the decode over (see tests/entry_point_spec.lua). What is
         left to prove here is the filter it was really about: an action
         handed to this widget under any other id is not its business. ]]
    it("reads the action chunk, nothing else", function()
      local elsewhere = {
        actor_id = 100,
        category = 8,
        param = 0,
        targets = { { id = 1, actions = { { param = 144, message = 327 } } } },
      }
      widget.update("chunk", 0x00A, "zone bytes", elsewhere)
      widget.update("chunk", 0x0D2, "treasure bytes", elsewhere)
      widget.update()
      assert.is_false(cast_frame().visible)
      begin_cast()
      widget.update()
      assert.is_true(cast_frame().visible)
    end)

    it("shrugs off a chunk the parser cannot read", function()
      assert.has_no.errors(function()
        -- A packet parse_action could not decode: the raw bytes still come
        -- through, with nothing parsed beside them.
        widget.update("chunk", 0x028, "garbage", nil)
      end)
      widget.update()
      assert.is_false(cast_frame().visible)
    end)

    it("lowers the bar when the cast completes", function()
      begin_cast()
      widget.update()
      widget.update("chunk", 0x028, "finish bytes", { actor_id = 100, category = 4, param = 144, targets = {} })
      widget.update()
      assert.is_false(cast_frame().visible)
      assert.is_false(cast_name().visible)
    end)

    it("expires a cast nothing closed", function()
      begin_cast()
      widget.update()
      clock = 30
      widget.update()
      assert.is_false(cast_frame().visible)
    end)

    it("hides with the rest of the widget, and stays hidden through a tick", function()
      begin_cast()
      clock = 1
      widget.update()
      widget.hide()
      for _, prim in ipairs({ cast_frame(), cast_fill(), cast_name(), prims.images[4] }) do
        assert.is_false(prim.visible)
      end
      -- The next frame must not raise it again over a hidden HUD - this is
      -- the cutscene/zoning auto-hide path.
      widget.update()
      for _, prim in ipairs({ cast_frame(), cast_fill(), cast_name(), prims.images[4] }) do
        assert.is_false(prim.visible)
      end
    end)

    it("shows the sample cast in preview", function()
      target = nil
      widget.set_preview(true)
      widget.update()
      assert.is_true(cast_frame().visible)
      assert.are.equal("Fire IV", cast_name().last.text)
    end)

    it("sits right-aligned under the bar", function()
      begin_cast()
      widget.update()
      -- Box right edge at 100 + 512; the 0.67-scale half-width art hangs
      -- from it.
      assert.are.equal(100 + 512 - 256 * 0.67, cast_frame().x)
      assert.is_true(cast_frame().y > frame().y)
      assert.are.equal(256 * 0.67, cast_frame().width)
      assert.are.equal(64 * 0.67, cast_frame().height)
    end)

    --[[ The riskiest mechanism in the widget: a right-justified prim's x has
         the screen width pre-subtracted, because the texts library adds it
         back. Forgetting to forward the screen width - or to place the prim
         at all - fails silently in a client, drawing the name off-screen. ]]
    it("places the cast name pre-compensated for the right-justify offset", function()
      begin_cast()
      widget.update()
      assert.are.equal(100 + 512 - 1920, cast_name().x)
      assert.is_true(cast_name().y > cast_frame().y)
    end)

    it("places the cast fill inside its own frame, not the hp bar's", function()
      begin_cast()
      widget.update()
      assert.are.equal(cast_frame().x + 13 * 0.67, cast_fill().x)
      assert.are.equal(cast_frame().y, cast_fill().y)
    end)

    it("truncates the cast name at the configured cap", function()
      local trimmed = copy(widget.defaults)
      trimmed.cast.name_max_chars = 3
      attach(trimmed)
      widget.set_pos(100, 100)
      widget.show()
      target = mob()
      widget.update()
      begin_cast()
      widget.update()
      assert.are.equal("Fir", cast_name().last.text)
    end)

    it("wears the fixed pale yellow, never the claim tint", function()
      target = mob({ claim_id = 77 })
      party = { p0 = { name = "Ally", mob = { id = 77 } } }
      -- Past the poll window, so the roster above is actually read.
      clock = 1
      begin_cast()
      widget.update()
      assert.are.same({ 255, 20, 20 }, fill().last.color)
      assert.are.same({ 230, 230, 138 }, cast_fill().last.color)
    end)
  end)

  describe("events it is handed but does not want", function()
    before_each(function()
      attach()
      widget.set_pos(100, 100)
      widget.show()
      target = mob()
    end)

    --[[ core.dispatch feeds every component every forwarded event, and guard
         disables a handler that throws after five failures - so ignoring them
         quietly is load-bearing, not politeness. ]]
    it("ignores every event the framework forwards", function()
      assert.has_no.errors(function()
        widget.update("chunk", 0x00A, "raw bytes")
        widget.update("add item", 65535)
        widget.update("remove item", 65535)
        widget.update("status", 4, 0)
        widget.update("hp", 100, 90)
        widget.update("tp", 1000, 0)
        widget.update("action", {})
      end)
    end)

    it("draws nothing new for them either", function()
      widget.update()
      local before = #fill().calls
      widget.update("chunk", 0x00A, "raw bytes")
      widget.update("status", 4, 0)
      assert.are.equal(before, #fill().calls)
    end)

    --[[ Not merely "draws nothing": it must not *look*. An incoming chunk
         fires for every packet the client receives, so rendering on one would
         put a client read - and, on a poll boundary, a whole get_party - on
         every packet rather than every frame. ]]
    it("does not read the client for an event it did not ask for", function()
      widget.update()
      local before = target_reads
      widget.update("chunk", 0x00A, "raw bytes")
      widget.update("add item", 65535)
      widget.update("status", 4, 0)
      widget.update("hp", 100, 90)
      -- The action chunk is wanted, but even it must not trigger a render.
      begin_cast()
      assert.are.equal(before, target_reads)
    end)
  end)

  describe("commands", function()
    before_each(function()
      attach()
      widget.set_pos(100, 100)
      widget.show()
    end)

    it("reports its range mode", function()
      assert.is_truthy(widget.handle_command({}):find("auto"))
    end)

    it("saves the config when a command changes it", function()
      widget.handle_command({ "mode", "bow" })
      assert.are.equal(1, saves)
    end)

    it("does not save when nothing changed", function()
      widget.handle_command({ "mode", "trebuchet" })
      assert.are.equal(0, saves)
    end)
  end)

  --[[ Everything below the target itself comes from the player: the job that
       picks the range scheme, the model size every range band is measured
       from, and the id that decides whose claim is whose. Each is a separate
       wire from the client into logic, and each is invisible in-game when it
       breaks - the widget still draws, just in the wrong colours. ]]
  describe("reading the player", function()
    before_each(function()
      attach()
      widget.set_pos(100, 100)
      widget.show()
    end)

    it("picks the range scheme from the player's main job", function()
      player = { main_job = "WHM" }
      -- 10 yalms, inside a white mage's 20 plus both model sizes.
      target = mob({ distance = 100 })
      widget.update()
      assert.are.same({ 0, 255, 0 }, distance().last.color)
    end)

    it("measures the range bands from the player's own model size", function()
      player = { main_job = "WHM" }
      target = mob({ distance = 100 })
      me = { id = 1 }
      widget.update()
      -- With no model size for the player there is no threshold to compute,
      -- so the segment stays plain rather than guessing one.
      assert.are.same({ 255, 255, 255 }, distance().last.color)
    end)

    it("recognises the player's own claim without a roster", function()
      party = {}
      me = { id = 4242, model_size = 1.0 }
      target = mob({ claim_id = 4242 })
      widget.update()
      assert.are.same({ 255, 20, 20 }, fill().last.color)
    end)

    it("tells the player apart from the party members around them", function()
      me = { id = 4242, model_size = 1.0 }
      party = { p0 = { name = "Me", mob = { id = 4242 } } }
      target = mob({ id = 4242, in_party = true, is_npc = false, claim_id = 0 })
      widget.update()
      -- Targeting yourself is not targeting a party member.
      assert.are.same({ 255, 255, 255 }, fill().last.color)
    end)

    it("copes with the client not naming the player yet", function()
      player = nil
      assert.has_no.errors(function()
        target = mob()
        widget.update()
      end)
    end)
  end)

  describe("changing character", function()
    --[[ Config is per character and so is the party. A roster kept across a
         logout would let the previous character's alliance decide whether this
         one's target is claimed by a friend. ]]
    it("forgets the old character's party when it detaches", function()
      attach()
      widget.set_pos(100, 100)
      widget.show()
      party = { p0 = { name = "Ally", mob = { id = 77 } } }
      target = mob({ claim_id = 77 })
      widget.update()
      assert.are.same({ 255, 20, 20 }, fill().last.color)

      widget.detach()
      party = {}
      clock = 10
      attach()
      widget.show()
      widget.update()
      -- The same claim, now nobody we know: someone else's mob.
      assert.are.same({ 153, 102, 255 }, fill().last.color)
    end)

    --[[ Mob ids are per-zone indices and do repeat, so the next character's
         first target can carry the last one's id. Without dropping the target
         on the way out, the bar would read that as the same mob and ease from
         the old health to the new instead of simply showing it. ]]
    it("does not ease from the last character's target onto a reused id", function()
      attach()
      widget.set_pos(100, 100)
      widget.show()
      target = mob({ id = 42, hpp = 100 })
      widget.update()

      widget.detach()
      clock = 10
      attach()
      widget.show()
      target = mob({ id = 42, hpp = 10 })
      widget.update()
      -- Snapped straight to 10% of the 486px fill, no eased slide.
      assert.are.equal(48, fill().width)
    end)

    it("polls again on the first frame after a fresh attach", function()
      local reads = 0
      party = setmetatable({}, {
        __index = function()
          reads = reads + 1
          return nil
        end,
      })
      attach()
      widget.set_pos(100, 100)
      widget.update()
      local first = reads
      widget.detach()
      attach()
      widget.update()
      assert.is_true(reads > first, "a relog waited out the poll interval before reading the party")
    end)
  end)

  describe("teardown", function()
    it("disposes every prim exactly once", function()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed)
      end
    end)
  end)
end)
