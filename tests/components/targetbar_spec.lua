local new_targetbar = require("components/targetbar/targetbar")
local fakes = require("tests/support/fakes")

describe("targetbar widget", function()
  local prims, assets, widget
  local target, subtarget, party, player, me, clock, saves
  local target_reads, subtarget_reads, party_reads
  local screen_w, screen_h
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

  -- The subtarget bar is built after the main one, so its prims follow the
  -- first bar's six images and four texts.
  local function sub_fill()
    return prims.images[8]
  end

  local function sub_name()
    return prims.texts[7]
  end

  local function sub_cast_frame()
    return prims.images[12]
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
    subtarget = nil
    party = {}
    player = { main_job = "WAR" }
    me = { id = 1, model_size = 1.0 }
    clock = 0
    saves = 0
    target_reads = 0
    subtarget_reads = 0
    party_reads = 0
    screen_w, screen_h = 1920, 1080
    generation_count, generation_deadline = 0, nil
    widget = new_targetbar({
      new_text = prims.new_text,
      new_image = prims.new_image,
      screen = function()
        return screen_w, screen_h
      end,
      get_mob_by_target = function(kind)
        if kind == "t" then
          target_reads = target_reads + 1
          return target
        end
        if kind == "st" then
          subtarget_reads = subtarget_reads + 1
          return subtarget
        end
        if kind == "me" then
          return me
        end
        return nil
      end,
      get_party = function()
        party_reads = party_reads + 1
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

    it("centres the target bar's default slot on the row it draws", function()
      local slot = widget.defaults.layout.anchors.main
      assert.are.equal(704, slot.pos.x)
      assert.are.equal(50, slot.pos.y)
    end)

    --[[ layout.repair keys the anchored branch off the defaults, and sheds a
         stray top-level pair from every anchored entry it repairs anyway. ]]
    it("seeds a placement per anchor and none above them", function()
      local layout = widget.defaults.layout
      assert.is_table(layout.anchors.main.pos)
      assert.is_table(layout.anchors.subtarget.pos)
      assert.is_nil(layout.pos)
      assert.is_nil(layout.scale)
    end)

    -- Roughly the reference's 300-against-600: the subtarget bar is the same
    -- art at a smaller scale, never a second geometry.
    it("ships the subtarget bar smaller than the target bar", function()
      assert.are.equal(0.6, widget.defaults.layout.anchors.subtarget.scale)
    end)

    --[[ Both anchors ship shown, so neither carries the key: absent means
         shown, and only an explicit false hides one. ]]
    it("ships both bars on", function()
      local layout = widget.defaults.layout
      assert.is_true(layout.visible)
      assert.is_nil(layout.anchors.main.visible)
      assert.is_nil(layout.anchors.subtarget.visible)
    end)

    it("seeds the subtarget bar clear of the target bar", function()
      local anchors = widget.defaults.layout.anchors
      attach()
      for anchor, slot in pairs(anchors) do
        widget.set_pos(slot.pos.x, slot.pos.y, anchor)
        widget.set_scale(slot.scale, anchor)
      end
      local _, main_y, _, main_height = widget.get_bounds("main")
      local _, sub_y = widget.get_bounds("subtarget")
      assert.is_true(sub_y >= main_y + main_height)
    end)

    --[[ Distinct tables, not one shared: a command edits the bar it names,
         and a shared table would have it edit both. ]]
    it("gives each bar its own settings", function()
      local bars = widget.defaults.bars
      assert.are.same(bars.main, bars.subtarget)
      assert.is_false(rawequal(bars.main, bars.subtarget))
    end)

    it("builds four texts and six bar layers for each of the two bars", function()
      assert.are.equal(8, #prims.texts)
      assert.are.equal(12, #prims.images)
    end)

    -- The same six textures twice: each bar owns its own layers, and the
    -- library gives no way to share one prim between two placements.
    it("points every layer at its own copy of the art", function()
      local wanted = {}
      for _ = 1, 2 do
        for _, file in ipairs({ "BarBG", "Bar", "BarFG", "CastBG", "CastBar", "CastFG" }) do
          wanted[#wanted + 1] = "assets/xiv/wide/" .. file .. ".png"
        end
      end
      assert.are.same(wanted, assets)
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

  --[[ Two bars, one component: the target and the `<st>` selection cursor,
       each placed and scaled on its own. Everything routes by anchor name,
       and main leads - the order `//hud list` prints, and the order layout
       mode hit-tests reversed, so the subtarget wins an overlap. ]]
  describe("anchors", function()
    it("declares the target and the subtarget", function()
      assert.are.same({ "main", "subtarget" }, widget.anchors())
    end)

    it("draws the selection cursor on the second bar", function()
      attach()
      subtarget = mob({ id = 200, name = "Chocobo", hpp = 50 })
      widget.set_pos(100, 100, "subtarget")
      widget.show()
      widget.update()
      assert.are.equal("Chocobo", sub_name().last.text)
    end)

    -- Two mobs, two bars: neither instance may read the other's token.
    it("keeps the two bars on their own targets", function()
      attach()
      target = mob({ name = "Greater Colibri" })
      subtarget = mob({ id = 200, name = "Chocobo" })
      widget.set_pos(100, 100, "main")
      widget.set_pos(100, 300, "subtarget")
      widget.show()
      widget.update()
      assert.are.equal("Greater Colibri", name().last.text)
      assert.are.equal("Chocobo", sub_name().last.text)
    end)

    it("places each bar where its own anchor was put", function()
      attach()
      widget.set_pos(100, 100, "main")
      widget.set_pos(700, 300, "subtarget")
      local x = widget.get_bounds("main")
      local sub_x = widget.get_bounds("subtarget")
      assert.are.equal(100, x)
      assert.are.equal(700, sub_x)
    end)

    it("scales each bar on its own anchor", function()
      attach()
      widget.set_pos(0, 0, "main")
      widget.set_pos(0, 0, "subtarget")
      widget.set_scale(0.5, "subtarget")
      local _, _, full = widget.get_bounds("main")
      local _, _, half = widget.get_bounds("subtarget")
      assert.is_true(half < full)
    end)

    --[[ Core names an anchor for every placement it makes on an anchored
         widget, so a nil is a wiring slip - and one that silently moved the
         main bar would leave the framework looking as though it worked. ]]
    it("ignores a placement that names no anchor", function()
      attach()
      widget.set_pos(100, 100)
      widget.set_scale(0.5)
      assert.is_nil(widget.get_bounds("main"))
      assert.is_nil(widget.get_bounds("subtarget"))
    end)

    it("ignores a placement naming an anchor that is not its own", function()
      attach()
      widget.set_pos(100, 100, "alliance1")
      assert.is_nil(widget.get_bounds("main"))
      assert.is_nil(widget.get_bounds("alliance1"))
    end)

    describe("switching one bar", function()
      before_each(function()
        attach()
        widget.set_pos(100, 100, "main")
        widget.set_pos(100, 300, "subtarget")
        target = mob()
        subtarget = mob({ id = 200, name = "Chocobo" })
        widget.show()
        widget.update()
      end)

      it("takes down the anchor named and leaves the other drawing", function()
        widget.hide("subtarget")
        widget.update()
        assert.is_true(fill().visible)
        assert.is_false(sub_fill().visible)
      end)

      --[[ The bare show is the whole of what layout mode force-shows with, so
           a bar a per-anchor hide took down has to come back on it - hidden, it
           could never be dragged or switched back on. ]]
      it("brings a hidden anchor back on the bare show", function()
        widget.hide("subtarget")
        widget.update()
        widget.show()
        widget.update()
        assert.is_true(sub_fill().visible)
      end)

      it("takes both bars down on the bare hide", function()
        widget.hide()
        widget.update()
        assert.is_false(fill().visible)
        assert.is_false(sub_fill().visible)
      end)

      -- An anchor that is not ours must not be read as the bare call.
      it("switches nothing for an anchor it does not have", function()
        widget.hide("alliance1")
        widget.update()
        assert.is_true(fill().visible)
        assert.is_true(sub_fill().visible)
      end)
    end)

    --[[ Both cast trackers hear every action packet and each keeps the one
         aimed at the mob it is drawing: the entry point decodes 0x028 once for
         every component that wants it, and neither bar can be told apart from
         the other at that point. ]]
    it("raises the cast bar of whichever bar the caster is on", function()
      attach()
      widget.set_pos(100, 100, "main")
      widget.set_pos(100, 300, "subtarget")
      subtarget = mob({ id = 200, name = "Chocobo" })
      widget.show()
      widget.update()
      widget.update("chunk", 0x028, "raw action bytes", {
        actor_id = 200,
        category = 8,
        param = 0,
        targets = { { id = 1, actions = { { param = 144, message = 327 } } } },
      })
      widget.update()
      assert.is_true(sub_cast_frame().visible)
      assert.is_false(cast_frame().visible)
    end)

    --[[ core.apply fans set_scale, set_pos and set_preview out over EVERY
         anchor on every call, and layout mode calls it per raw mouse-move
         event - so a drag of one bar re-applies the other's placement dozens
         of times a second. Only a value that actually moved may reach a prim:
         partylist measured two thirds of its drag cost in exactly these
         no-op re-applies. ]]
    describe("re-applying a placement that has not moved", function()
      before_each(function()
        attach()
        widget.set_pos(100, 100, "main")
        widget.set_pos(100, 300, "subtarget")
        widget.set_scale(0.5, "main")
        widget.show()
        target = mob()
        subtarget = mob({ id = 200, name = "Chocobo" })
        widget.update()
      end)

      it("writes nothing to the bar it names", function()
        local before = #fill().calls
        widget.set_pos(100, 100, "main")
        widget.set_scale(0.5, "main")
        assert.are.equal(before, #fill().calls)
      end)

      it("writes nothing to the bar it does not name", function()
        local before = #sub_fill().calls
        widget.set_pos(200, 200, "main")
        widget.set_scale(0.75, "main")
        assert.are.equal(before, #sub_fill().calls)
      end)

      -- Still moves when the value really changes, which is the whole point.
      it("still lays the bar out when the placement does move", function()
        local before = #fill().calls
        widget.set_pos(101, 100, "main")
        assert.is_true(#fill().calls > before)
      end)

      --[[ apply_layout re-reads the screen, because the cast name is right
           justified and its x pre-subtracts the width the library adds back.
           A resolution change moves that text without moving the origin, and
           core re-pushes the same origin afterwards - so the gate has to let
           that through or the name sits off screen by the delta until
           something else moves the bar. ]]
      it("lays the bar out again when the screen changed under it", function()
        local before = #cast_name().calls
        screen_w, screen_h = 2560, 1440
        widget.set_pos(100, 100, "main")
        assert.is_true(#cast_name().calls > before)
      end)
    end)

    --[[ Nothing is read while no bar could draw with the answer: an unplaced
         or detached bar renders nothing, and a poll for it would be a whole
         get_party nobody uses. ]]
    describe("reading the client for two bars", function()
      it("reads nothing at all while neither bar has been placed", function()
        attach()
        widget.show()
        widget.update()
        assert.are.equal(0, party_reads)
        assert.are.equal(0, target_reads)
        assert.are.equal(0, subtarget_reads)
      end)

      it("reads nothing once both bars are detached", function()
        attach()
        widget.set_pos(100, 100, "main")
        widget.update()
        widget.detach()
        local before = party_reads
        clock = clock + 1
        widget.update()
        assert.are.equal(before, party_reads)
      end)

      -- Each bar reads its own token, and only where it could draw with it.
      it("reads only the token of a bar that has been placed", function()
        attach()
        widget.set_pos(100, 100, "main")
        widget.show()
        widget.update()
        assert.is_true(target_reads > 0)
        assert.are.equal(0, subtarget_reads)
      end)

      it("reads the second token once its bar is placed too", function()
        attach()
        widget.set_pos(100, 100, "main")
        widget.set_pos(100, 300, "subtarget")
        widget.show()
        widget.update()
        assert.is_true(subtarget_reads > 0)
      end)

      -- The action chunk feeds both cast trackers and reads no client at all.
      it("reads neither token for an event it did not ask for", function()
        attach()
        widget.set_pos(100, 100, "main")
        widget.set_pos(100, 300, "subtarget")
        widget.show()
        widget.update()
        local seen, sub_seen = target_reads, subtarget_reads
        begin_cast()
        widget.update("chunk", 0x00A, "raw bytes")
        assert.are.equal(seen, target_reads)
        assert.are.equal(sub_seen, subtarget_reads)
      end)
    end)

    --[[ Layout mode opens with set_preview plus the bare show, so a bar that
         drew no sample could not be seen or dragged - and with nothing
         targeted, the sample is the only thing either bar has to draw. ]]
    it("previews both bars", function()
      attach()
      widget.set_pos(100, 100, "main")
      widget.set_pos(100, 300, "subtarget")
      widget.set_preview(true)
      widget.show()
      widget.update()
      assert.are.equal("Greater Colibri", name().last.text)
      assert.are.equal("Greater Colibri", sub_name().last.text)
      assert.is_true(sub_fill().visible)
    end)

    it("destroys both bars' prims", function()
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed)
      end
    end)

    --[[ A config file is code and `//hud copy` imports another character's, so
         a bar's entry can be any shape by the time it reaches attach. ]]
    describe("a config it cannot use", function()
      it("replaces an unusable bar entry with a fresh copy of the defaults", function()
        local config = copy(widget.defaults)
        config.bars.subtarget = "broken"
        attach(config)
        assert.are.equal(14, config.bars.subtarget.font_size)
      end)

      -- Fresh, and written back: handing a bar the widget's own defaults table
      -- would have every later command write where save() never looks.
      it("seeds from a copy rather than from its own defaults table", function()
        local config = copy(widget.defaults)
        config.bars.main = nil
        attach(config)
        assert.is_false(rawequal(config.bars.main, widget.defaults.bars.main))
      end)

      it("survives a config carrying no bars at all", function()
        assert.has_no.errors(function()
          attach({})
        end)
      end)

      it("survives a config that is not a table", function()
        assert.has_no.errors(function()
          widget.attach("broken", function() end)
        end)
      end)
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
      restyled.bars.main.text_color = { a = 120, r = 1, g = 2, b = 3 }
      attach(restyled)
      widget.set_pos(100, 100, "main")
      widget.show()
      target = mob({ hpp = 90 })
      widget.update()
      assert.are.equal(120, name().last.alpha)
    end)

    it("honours a translucent fill colour", function()
      local restyled = copy(widget.defaults)
      restyled.bars.main.fill_colors.unclaimed = { a = 90, r = 230, g = 230, b = 138 }
      attach(restyled)
      widget.set_pos(100, 100, "main")
      widget.show()
      target = mob({ claim_id = 0 })
      widget.update()
      assert.are.equal(90, fill().last.alpha)
    end)

    it("adopts the config it is handed, not the one it was built with", function()
      local loaded = copy(widget.defaults)
      loaded.bars.main.font = "Consolas"
      loaded.bars.main.text_stroke = { width = 4, a = 100, r = 1, g = 2, b = 3 }
      loaded.bars.main.name_max_chars = 3
      attach(loaded)
      widget.set_pos(100, 100, "main")
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
      mangled.bars.main.text_color = "red"
      mangled.bars.main.text_stroke = 3
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
      bare.bars.main.text_color = {}
      attach(bare)
      assert.are.same({ 255, 255, 255 }, hp().last.color)
    end)

    it("fills missing channels on the per-frame colour path too", function()
      local bare = copy(widget.defaults)
      bare.bars.main.fill_colors.unclaimed = { a = 90 }
      attach(bare)
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(300, 400, "main")
      local x, y = widget.get_bounds("main")
      assert.are.equal(300, x)
      assert.are.equal(400, y)
    end)

    it("has no bounds before it has been positioned", function()
      assert.is_nil(widget.get_bounds("main"))
    end)

    it("reports the row's full width", function()
      widget.set_pos(300, 400, "main")
      local _, _, width = widget.get_bounds("main")
      assert.are.equal(512, width)
    end)

    it("shrinks with the scale", function()
      widget.set_pos(300, 400, "main")
      local _, _, full = widget.get_bounds("main")
      widget.set_scale(0.5, "main")
      local _, _, half = widget.get_bounds("main")
      assert.is_true(half < full)
    end)

    it("places the three segments across the row at the drawn font size", function()
      widget.set_pos(300, 400, "main")
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
      widget.set_pos(300, 400, "main")
      widget.set_scale(0.25, "main")
      assert.are.equal(4, hp().font_size)
    end)

    it("insets the fill inside the frame rather than leaving it at the origin", function()
      widget.set_pos(300, 400, "main")
      assert.are.equal(frame().x + 13, fill().x)
      assert.are.equal(frame().y, fill().y)
    end)

    it("drops the bar below the text rather than over it", function()
      widget.set_pos(300, 400, "main")
      assert.is_true(frame().y > hp().y)
    end)

    it("moves the whole group when repositioned", function()
      widget.set_pos(100, 100, "main")
      target = mob()
      widget.update()
      local first = frame().x
      widget.set_pos(200, 100, "main")
      assert.are.equal(first + 100, frame().x)
    end)

    -- Fill widths are only written when the health moves, so a scale change
    -- has to push them itself or the bar keeps the old scale's size.
    it("resizes the fill when the scale changes, not just on the next hit", function()
      widget.set_pos(100, 100, "main")
      target = mob({ hpp = 100 })
      widget.update()
      local before = fill().width
      widget.set_scale(0.5, "main")
      widget.update()
      assert.is_true(fill().width < before)
    end)
  end)

  describe("polling", function()
    before_each(function()
      attach()
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(100, 100, "main")
      widget.update()
      assert.are.equal(1, reads)
    end)

    --[[ One client read per interval, and one roster per bar off the table it
         returned: get_party allocates eighteen member tables and is called
         once, while each bar walks those eighteen keys for its own claim set -
         lookups, not allocations, and the price of the two keeping separate
         logic. ]]
    it("does not read the party again inside the interval", function()
      local reads = 0
      party = setmetatable({}, {
        __index = function()
          reads = reads + 1
          return nil
        end,
      })
      widget.set_pos(100, 300, "subtarget")
      widget.update()
      widget.update()
      widget.update()
      -- Eighteen keys per bar per poll; three frames inside one window is
      -- still one poll.
      assert.are.equal(36, reads)
    end)

    -- And no roster at all for a bar that could not draw with one.
    it("builds no roster for a bar that has not been placed", function()
      local reads = 0
      party = setmetatable({}, {
        __index = function()
          reads = reads + 1
          return nil
        end,
      })
      widget.update()
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
      widget.set_pos(100, 100, "main")
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
      trimmed.bars.main.cast.name_max_chars = 3
      attach(trimmed)
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(100, 100, "main")
      widget.show()
    end)

    -- One line per bar, each naming its own: partylist's shape, and core says
    -- each line of a list.
    it("reports both bars' range modes", function()
      local reply = widget.handle_command({})
      assert.are.equal(2, #reply)
      assert.is_truthy(reply[1]:find("main"))
      assert.is_truthy(reply[2]:find("subtarget"))
      assert.is_truthy(reply[1]:find("auto"))
    end)

    it("reports one bar when it is named", function()
      local reply = widget.handle_command({ "subtarget" })
      assert.are.equal("string", type(reply))
      assert.is_truthy(reply:find("subtarget"))
    end)

    -- The bar word matches the way every other word in `//hud` does.
    it("takes the bar word in any case", function()
      local reply = widget.handle_command({ "SubTarget" })
      assert.is_truthy(reply:find("subtarget"))
    end)

    it("sets the mode of the bar named and leaves the other alone", function()
      local config = attach()
      widget.handle_command({ "subtarget", "mode", "bow" })
      assert.are.equal("bow", config.bars.subtarget.distance.mode)
      assert.are.equal("auto", config.bars.main.distance.mode)
    end)

    --[[ Absent, the bar word means the target bar - so every line that worked
         before the subtarget existed still means what it meant. ]]
    it("addresses the target bar when no bar is named", function()
      local config = attach()
      widget.handle_command({ "mode", "bow" })
      assert.are.equal("bow", config.bars.main.distance.mode)
      assert.are.equal("auto", config.bars.subtarget.distance.mode)
    end)

    it("saves the config when a command changes it", function()
      widget.handle_command({ "mode", "bow" })
      assert.are.equal(1, saves)
    end)

    it("saves a change made to the other bar too", function()
      widget.handle_command({ "subtarget", "mode", "bow" })
      assert.are.equal(1, saves)
    end)

    it("does not save when nothing changed", function()
      widget.handle_command({ "mode", "trebuchet" })
      assert.are.equal(0, saves)
    end)

    -- A first word that is not a bar is a verb, which is what keeps the verb
    -- grammar behind the bar word untouched.
    it("reads an unknown first word as a verb rather than a bar", function()
      local reply = widget.handle_command({ "trebuchet" })
      assert.is_truthy(reply:find("trebuchet"))
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
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(100, 100, "main")
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
      widget.set_pos(100, 100, "main")
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
