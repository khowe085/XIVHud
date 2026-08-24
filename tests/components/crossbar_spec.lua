local new_crossbar = require("components/crossbar/crossbar")
local new_render = require("components/crossbar/render")

-- Default DIKs: `;` is the left side, `1`-`8` sit on DIK 2-9.
local SIDE = 39
local SLOT_3 = 4

describe("crossbar stand-in", function()
  local ctx, env, widget

  before_each(function()
    env = { chat = {}, chat_open = false, suppressed = false, layout = false }
    ctx = {
      screen = function()
        return 1920, 1080
      end,
      say = function(lines)
        if type(lines) == "table" then
          for _, line in ipairs(lines) do
            env.chat[#env.chat + 1] = line
          end
        else
          env.chat[#env.chat + 1] = lines
        end
      end,
      chat_open = function()
        return env.chat_open
      end,
      suppressed = function()
        return env.suppressed
      end,
      layout_active = function()
        return env.layout
      end,
    }
    widget = new_crossbar(ctx)
  end)

  local function attach()
    widget.attach(widget.defaults)
    widget.show()
  end

  it("implements the contract under the component's name", function()
    assert.are.equal("crossbar", widget.name)
    assert.are.same({ 39 }, widget.defaults.input.xhb_left)
    assert.is_nil(widget.get_bounds())
  end)

  it("lets every key through before it is attached", function()
    assert.is_false(widget.on_keyboard(SIDE, true, 0, false))
    assert.are.equal(0, #env.chat)
  end)

  it("blocks its side key once attached, without chatter", function()
    -- Since CB4 the panel shows which side is active; saying every press
    -- and release to chat would be spam in play, so activations are silent.
    attach()
    assert.is_true(widget.on_keyboard(SIDE, true, 0, false))
    assert.is_true(widget.on_keyboard(SIDE, false, 0, false), "the latched release is swallowed too")
    assert.are.equal(0, #env.chat, "side activation is shown by the panel, not said")
  end)

  it("fires nothing on a slot press while no job is scoped", function()
    -- CB5 retires the CB2 stand-in's log line: execution is real now, and
    -- with no client to name a job there are no bindings to fire. The press
    -- is still ours (blocked), just empty.
    attach()
    widget.on_keyboard(SIDE, true, 0, false)
    assert.is_true(widget.on_keyboard(SLOT_3, true, 0, false))
    assert.are.equal(0, #env.chat, "nothing to say: an empty slot is silent")
  end)

  it("leaves a bare slot key to the game", function()
    attach()
    assert.is_false(widget.on_keyboard(SLOT_3, true, 0, false))
    assert.are.equal(0, #env.chat)
  end)

  it("hands its keys back while the chat box has focus", function()
    attach()
    env.chat_open = true
    assert.is_false(widget.on_keyboard(SIDE, true, 0, false))
  end)

  it("keeps its side key blocked while suppressed, which also hides it", function()
    -- The "fires nothing" half of this guard is pinned in the live block,
    -- where a ctx with send_command makes the assertion bite. Suppression
    -- HIDES the component (core's own doing), so the reachable state is
    -- both at once - suppressed-but-visible never happens in production.
    attach()
    env.suppressed = true
    widget.hide()
    assert.is_true(widget.on_keyboard(SIDE, true, 0, false))
    assert.is_false(widget.on_keyboard(SLOT_3, true, 0, false), "slot keys are the game's under suppression")
  end)

  it("keeps its side key blocked during layout mode", function()
    attach()
    env.layout = true
    assert.is_true(widget.on_keyboard(SIDE, true, 0, false))
    assert.is_false(widget.on_keyboard(SLOT_3, true, 0, false), "slot keys fall through in layout mode")
  end)

  it("goes fully inert when hidden, except for a latched release", function()
    attach()
    assert.is_true(widget.on_keyboard(SIDE, true, 0, false))
    widget.hide()
    assert.is_true(widget.on_keyboard(SIDE, false, 0, false), "the game never saw the press")
    assert.is_false(widget.on_keyboard(SIDE, true, 0, false), "a fresh press falls through while hidden")
  end)

  it("survives a config whose input block is garbage, on the default keys", function()
    -- One hand-broken config file must not leave every later component
    -- unattached at login: a non-table input block degrades to the shipped
    -- defaults instead of crashing attach.
    local config = require("components/crossbar/defaults")(1920, 1080)
    config.input = 42
    assert.has_no.errors(function()
      widget.attach(config)
    end)
    widget.show()
    assert.is_true(widget.on_keyboard(SIDE, true, 0, false), "the default side key still blocks")
  end)

  it("says once when a hand-edited key map gives a slot key a shortcut too", function()
    -- The shipped map is disjoint, so only a hand-edited file gets here. The
    -- slot key wins and the shortcut is dropped - a resolution the player has
    -- to be told about, or the key simply appears to do nothing.
    local config = require("components/crossbar/defaults")(1920, 1080)
    config.input.shortcuts[5] = { tap = "open map" }
    widget.attach(config)
    assert.are.equal(1, #env.chat, "one line, not one per key event")
    local said = env.chat[1]
    assert.is_not_nil(said:find("5", 1, true), "names the DIK: " .. said)
    assert.is_not_nil(said:lower():find("slot"), "and says which role kept it: " .. said)
    widget.show()
    widget.on_keyboard(5, true, 0, false)
    assert.are.equal(1, #env.chat, "and never repeats it as the key is used")
  end)

  it("resets its held state when focus is lost", function()
    attach()
    widget.on_keyboard(SIDE, true, 0, false)
    widget.update("lose focus")
    assert.is_false(widget.on_keyboard(SIDE, false, 0, false), "the latch went with the focus")
  end)

  it("starts from scratch after a detach", function()
    attach()
    widget.on_keyboard(SIDE, true, 0, false)
    widget.detach()
    assert.is_false(widget.on_keyboard(SIDE, true, 0, false))
    attach()
    assert.is_true(widget.on_keyboard(SIDE, true, 0, false), "not read as an auto-repeat of the stranded press")
  end)

  it("refuses an authoring verb before a job is scoped, without a store", function()
    -- Attached with no store at all (the pre-login shape): every verb that
    -- would write one must say so rather than throw inside the handler.
    attach()
    for _, words in ipairs({
      { "bind", "1L3", "ja", "Provoke" },
      { "unbind", "1L3" },
      { "alias", "1L3", "Name" },
      { "swap", "1L3", "2R1" },
      { "copy", "WAR" },
      { "list" },
    }) do
      local reply = widget.handle_command(words)
      assert.is_string(reply, words[1])
      assert.is_not_nil(reply:lower():find("job"), words[1] .. ": " .. reply)
    end
  end)

  it("reports that no job is scoped when asked bare", function()
    attach()
    local reply = widget.handle_command({})
    local text = type(reply) == "table" and table.concat(reply, "\n") or reply
    assert.is_not_nil(text:lower():find("no job"), "got: " .. text)
  end)

  -- Touchpoint 2: the stand-in carries the four anchors so the multi-anchor
  -- framework path can be exercised in-client at CB3 - layout mode's overlay
  -- boxes give them a visible, draggable footprint even though the stand-in
  -- itself draws nothing. CB4's render.lua replaces the placeholder sizes.
  describe("anchors", function()
    it("declares the four anchors, main first", function()
      assert.are.same({ "main", "wxhb_left", "wxhb_right", "indicator" }, widget.anchors())
    end)

    it("matches its defaults' anchored slot schema", function()
      local anchors = widget.defaults.slots.default.anchors
      for _, name in ipairs(widget.anchors()) do
        assert.is_not_nil(anchors[name], name .. " has no default placement")
      end
      assert.is_nil(widget.defaults.slots.default.pos, "no top-level pos on the anchored schema")
    end)

    it("reports no bounds for an anchor never positioned", function()
      assert.is_nil(widget.get_bounds("main"))
    end)

    it("returns the origin set_pos gave it, per anchor", function()
      widget.set_pos(100, 900, "main")
      widget.set_pos(600, 700, "indicator")
      local x, y = widget.get_bounds("main")
      assert.are.same({ 100, 900 }, { x, y })
      x, y = widget.get_bounds("indicator")
      assert.are.same({ 600, 700 }, { x, y })
    end)

    it("scales each anchor's footprint independently", function()
      widget.set_pos(0, 0, "main")
      widget.set_pos(0, 0, "wxhb_left")
      local _, _, base_width, base_height = widget.get_bounds("main")
      local _, _, left_width = widget.get_bounds("wxhb_left")
      widget.set_scale(2, "main")
      local _, _, width, height = widget.get_bounds("main")
      assert.are.equal(base_width * 2, width)
      assert.are.equal(base_height * 2, height)
      local _, _, left_after = widget.get_bounds("wxhb_left")
      assert.are.equal(left_width, left_after, "the other anchor must not scale")
    end)

    it("gives every anchor a positive footprint", function()
      for _, name in ipairs(widget.anchors()) do
        widget.set_pos(0, 0, name)
        local _, _, width, height = widget.get_bounds(name)
        assert.is_true(width > 0 and height > 0, name)
      end
    end)

    it("ignores a placement aimed at no anchor", function()
      assert.has_no.errors(function()
        widget.set_pos(1, 2)
        widget.set_scale(3)
      end)
      assert.is_nil(widget.get_bounds())
    end)
  end)
end)

-- CB4: the widget grows its prims - the persistent 16-slot XHB and the
-- active-side panel. The stand-in describe above still passes untouched
-- because a ctx without prim constructors stays legal: the input machine,
-- anchors and bounds all work headless (which is also what keeps the specs
-- above honest about never having drawn anything).
describe("crossbar widget", function()
  local fakes = require("tests/support/fakes")
  local RIGHT = 40 -- default DIK for the right side (')

  local env, ctx, prims, widget

  before_each(function()
    env = { chat = {}, chat_open = false, suppressed = false, layout = false }
    prims = fakes.prims()
    ctx = {
      screen = function()
        return 1920, 1080
      end,
      say = function(line)
        env.chat[#env.chat + 1] = line
      end,
      chat_open = function()
        return env.chat_open
      end,
      suppressed = function()
        return env.suppressed
      end,
      layout_active = function()
        return env.layout
      end,
      new_image = prims.new_image,
      new_text = prims.new_text,
      asset = function(path)
        return "addon/" .. path
      end,
    }
    widget = require("components/crossbar/crossbar")(ctx)
    widget.attach(widget.defaults)
    widget.set_pos(100, 900, "main")
    widget.set_scale(1, "main")
    widget.show()
  end)

  local function images_at(x, y)
    local hits = {}
    for _, prim in ipairs(prims.images) do
      if prim.x == x and prim.y == y then
        hits[#hits + 1] = prim
      end
    end
    return hits
  end

  local function visible_count()
    local count = 0
    for _, prim in ipairs(prims.all) do
      if prim.visible then
        count = count + 1
      end
    end
    return count
  end

  it("creates the panel, six images plus three texts per slot, and the indicator pair", function()
    -- 1 panel + 40 slots (XHB 16, WXHB 16, Expanded 8) x (background, chain
    -- overlay, icon, sweep-overlay, frame, feedback - upstream's layering,
    -- bottom to top); the sweep overlay doubles as the red X, upstream's own
    -- prim reuse, and the chain overlay is CB6's per-slot chain-result icon.
    -- Then the sword that marks the drawn weapon state, and the skillchain
    -- indicator's bg and fill closing the list. Texts: name, cost and
    -- recast per slot, plus the one set label between the crosses.
    assert.are.equal(1 + 40 * 6 + 1 + 2, #prims.images)
    assert.are.equal(40 * 3 + 1, #prims.texts)
  end)

  it("draws every slot from the render geometry", function()
    -- Slot 8 (dpad left) of the left side: column 1, middle row. Six
    -- images share the slot origin while nothing is bound: background,
    -- frame, icon, sweep overlay, feedback flash and chain overlay.
    local hits = images_at(100 + 30, 900 + 35 + 28)
    assert.are.equal(6, #hits, "background, chain, icon, sweep, frame, feedback")
    assert.are.equal("addon/components/crossbar/assets/slot.png", hits[1].last.path)
    assert.are.equal("addon/components/crossbar/assets/frame.png", hits[5].last.path)
    assert.are.same({ 40, 40 }, { hits[1].width, hits[1].height })
    assert.are.same({ 40, 40 }, { hits[5].width, hits[5].height }, "the frame is slot-sized too")
    assert.is_false(hits[1].last.fit, "explicitly sized art must not fit-to-texture")
    assert.is_false(hits[5].last.fit, "the frame is sized too")
    -- Slot 1 (face top) of the right side: column 5 plus the side gap.
    hits = images_at(100 + 30 + 300 + 4 * 46, 900 + 35)
    assert.are.equal(6, #hits)
  end)

  it("keeps everything hidden until show() and blanks again on hide()", function()
    -- 32 slot pieces, plus the set label, which says which set the XHB is
    -- on whether or not a side is held.
    assert.are.equal(33, visible_count(), "the panel stays down while nothing is held")
    widget.hide()
    assert.are.equal(0, visible_count())
    widget.show()
    assert.are.equal(33, visible_count())
  end)

  it("scales the grid with the main anchor", function()
    widget.set_scale(2, "main")
    local hits = images_at(100 + (30 + 300 + 4 * 46) * 2, 900 + 35 * 2)
    assert.are.equal(6, hits and #hits or 0)
    assert.are.same({ 80, 80 }, { hits[1].width, hits[1].height })
    assert.are.same({ 80, 80 }, { hits[5].width, hits[5].height }, "the frame scales with the slot")
    -- The panel scales with the grid: the right side's offset and the art's
    -- size both carry the anchor scale.
    widget.on_keyboard(RIGHT, true, 0, false)
    local panel = images_at(100 + 300 * 2, 900)[1]
    assert.is_not_nil(panel, "the scaled right panel sits one scaled side gap over")
    assert.are.same({ 330 * 2, 180 * 2 }, { panel.width, panel.height })
  end)

  it("panels the held side and clears it on release", function()
    widget.on_keyboard(39, true, 0, false)
    local panel = images_at(100, 900)[1]
    assert.is_not_nil(panel, "the left panel sits at the anchor origin")
    assert.is_true(panel.visible)
    assert.are.equal("addon/components/crossbar/assets/bar_bg_compact.png", panel.last.path)
    assert.are.same({ 330, 180 }, { panel.width, panel.height })
    assert.is_false(panel.last.fit, "the panel is sized too")
    assert.are.equal(widget.defaults.button_bg_alpha, panel.last.alpha)
    widget.on_keyboard(39, false, 0, false)
    assert.is_false(panel.visible)
    widget.on_keyboard(RIGHT, true, 0, false)
    assert.are.equal(100 + 300, panel.x, "the right side's panel sits one side gap over")
    assert.is_true(panel.visible)
  end)

  it("carries a lit panel along with a move", function()
    widget.on_keyboard(39, true, 0, false)
    widget.set_pos(500, 700, "main")
    local panel = images_at(500, 700)[1]
    assert.is_not_nil(panel, "the panel follows the anchor")
    assert.is_true(panel.visible)
  end)

  it("keeps the WXHB and its panel down while its anchor is unplaced", function()
    -- Layer + side = the WXHB view. The bar exists since CB5, but nothing
    -- may draw before its own anchor has been placed - and the panel must
    -- not be painted at the main origin for a wxhb bar either.
    widget.on_keyboard(43, true, 0, false)
    widget.on_keyboard(39, true, 0, false)
    local panel = nil
    for _, prim in ipairs(prims.images) do
      if prim.last.path == "addon/components/crossbar/assets/bar_bg_compact.png" then
        panel = prim
      end
    end
    assert.is_not_nil(panel)
    assert.is_false(panel.visible, "the wxhb anchor was never placed")
    -- 32 slot pieces plus the set label.
    assert.are.equal(33, visible_count(), "the XHB stays up, inactive")
  end)

  it("survives a scale applied before any position", function()
    -- Core applies layout in its own order; a scale landing first must not
    -- index a position that does not exist, and nothing may draw until the
    -- anchor has one.
    local fresh = fakes.prims()
    local bare_ctx = {}
    for key, value in pairs(ctx) do
      bare_ctx[key] = value
    end
    bare_ctx.new_image = fresh.new_image
    bare_ctx.new_text = fresh.new_text
    local fresh_widget = require("components/crossbar/crossbar")(bare_ctx)
    fresh_widget.attach(fresh_widget.defaults)
    fresh_widget.show()
    fresh_widget.on_keyboard(39, true, 0, false)
    assert.has_no.errors(function()
      fresh_widget.set_scale(2, "main")
    end)
    local drawn = 0
    for _, prim in ipairs(fresh.all) do
      if prim.visible then
        drawn = drawn + 1
      end
    end
    assert.are.equal(0, drawn, "nothing draws before the anchor is placed")
  end)

  it("hides the whole XHB while Expanded Hold replaces it", function()
    widget.on_keyboard(39, true, 0, false)
    widget.on_keyboard(RIGHT, true, 0, false)
    -- The XHB's 32 slot prims yield to Expanded's eight slots (16 visible
    -- prims: background+frame) plus its active panel, centred on main.
    local expanded = images_at(100 + 30 + 150 + 46, 900 + 35)
    assert.is_true(#expanded > 0, "the Expanded slots draw one half-gap over")
    assert.is_true(expanded[1].visible)
    local panel = images_at(100 + 150, 900)[1]
    assert.is_not_nil(panel, "the Expanded panel sits centred on main")
    assert.is_true(panel.visible)
    -- Eight slots of background+frame, the panel, and the set label -
    -- which names the XHB's set whether or not Expanded has replaced it.
    assert.are.equal(16 + 1 + 1, visible_count(), "eight slots, the panel, the set label")
    widget.on_keyboard(RIGHT, false, 0, false)
    assert.are.equal(32 + 1 + 1, visible_count(), "the survivor's XHB side returns, panelled, label and all")
  end)

  it("writes the active set between the two crosses, in gold", function()
    --[[ Without this an empty bar gives no sign that a set switch did
         anything, which is how its absence was found in a live client. ]]
    local label = prims.texts[#prims.texts]
    assert.are.equal("Set 1", label.last.text)
    assert.are.same({ 255, 215, 0 }, label.last.color)
    assert.is_true(label.visible, "shown whether or not a side is held")
    local render = new_render({ config = widget.defaults })
    local x, y = render.set_label_pos()
    assert.are.same({ 100 + x, 900 + y }, { label.x, label.y })
  end)

  it("keeps the sword down while the weapon is sheathed", function()
    -- Sheathed is the state a fresh attach starts in. The sword sits just
    -- before the indicator pair, which is last in the image list.
    assert.is_false(prims.images[#prims.images - 2].visible)
  end)

  it("does not strand the panel across hide and show", function()
    -- Hold a side, hide, release while hidden: the widget is disabled, so
    -- no activate intent arrives and the widget's own side memory goes
    -- stale. show() must resync from the machine rather than trust it.
    widget.on_keyboard(39, true, 0, false)
    widget.hide()
    widget.on_keyboard(39, false, 0, false)
    widget.show()
    local panel = images_at(100, 900)[1]
    assert.is_false(panel.visible, "nobody holds a side any more")
    -- The inverse: a press that lands while hidden is still a physically
    -- held key the machine tracked (its guard against stranding state), so
    -- show() lights the panel from the machine's truth even though the
    -- activate intent went by unheard.
    widget.hide()
    widget.on_keyboard(39, true, 0, false)
    widget.show()
    assert.is_true(panel.visible, "the machine knows the side is held")
    widget.on_keyboard(39, false, 0, false)
    assert.is_false(panel.visible, "and the release clears it as usual")
  end)

  it("reports the render footprint through get_bounds", function()
    local x, y, width, height = widget.get_bounds("main")
    assert.are.same({ 100, 900, 630, 180 }, { x, y, width, height })
    widget.set_pos(5, 6, "wxhb_left")
    local _, _, wxhb_width, wxhb_height = widget.get_bounds("wxhb_left")
    assert.are.same({ 330, 180 }, { wxhb_width, wxhb_height })
    widget.set_pos(7, 8, "indicator")
    local _, _, indicator_width, indicator_height = widget.get_bounds("indicator")
    assert.are.same({ 604, 14 }, { indicator_width, indicator_height })
  end)

  it("hides and normalises every prim at construction", function()
    -- The sibling components' construction hygiene: nothing flashes at
    -- (0,0) before attach, and repeat_xy is pinned to a single tile.
    local fresh = fakes.prims()
    local bare_ctx = {}
    for key, value in pairs(ctx) do
      bare_ctx[key] = value
    end
    bare_ctx.new_image = fresh.new_image
    bare_ctx.new_text = fresh.new_text
    require("components/crossbar/crossbar")(bare_ctx)
    assert.are.equal(1 + 40 * 6 + 1 + 2, #fresh.images)
    for _, prim in ipairs(fresh.images) do
      assert.is_false(prim.visible)
      assert.are.same({ 1, 1 }, prim.last.repeat_xy)
      assert.are.same({ 255, 255, 255 }, prim.last.color, "untinted must be explicit, not a library default")
      assert.are.equal(false, prim.last.draggable)
    end
    for _, prim in ipairs(fresh.all) do
      assert.is_false(prim.visible)
      local hidden = false
      for _, call in ipairs(prim.calls) do
        hidden = hidden or call.name == "hide"
      end
      assert.is_true(hidden, "hide() must be called at build, not assumed")
    end
  end)

  it("turns every text prim's own background off", function()
    -- The texts library draws an opaque box behind a line unless told not
    -- to; parambar, partylist, targetbar, equipviewer and lib/overlay all
    -- turn it off at dress time, and this widget was missing it.
    for _, prim in ipairs(prims.texts) do
      assert.is_false(prim.last.bg_visible, "a slot text still carrying its background")
    end
  end)

  it("paints the configured slot alpha onto every slot background", function()
    local fresh = fakes.prims()
    local bare_ctx = {}
    for key, value in pairs(ctx) do
      bare_ctx[key] = value
    end
    bare_ctx.new_image = fresh.new_image
    bare_ctx.new_text = fresh.new_text
    local fresh_widget = require("components/crossbar/crossbar")(bare_ctx)
    fresh_widget.defaults.slot_alpha = 123
    fresh_widget.attach(fresh_widget.defaults)
    local backgrounds, frames = 0, 0
    for _, prim in ipairs(fresh.images) do
      if prim.last.path == "addon/components/crossbar/assets/slot.png" then
        backgrounds = backgrounds + 1
        assert.are.equal(123, prim.last.alpha)
      elseif prim.last.path == "addon/components/crossbar/assets/frame.png" then
        frames = frames + 1
        assert.are.equal(255, prim.last.alpha, "the frame draws opaque")
      end
    end
    assert.are.equal(40, backgrounds, "every bar dresses, the hidden ones included")
    assert.are.equal(40, frames)
  end)

  it("follows the attached config rather than its defaults", function()
    -- The render is rebuilt over the attached config: a login's saved
    -- spacing must move the drawn grid and the reported bounds, not just
    -- the numbers inside defaults.
    local fresh = fakes.prims()
    local bare_ctx = {}
    for key, value in pairs(ctx) do
      bare_ctx[key] = value
    end
    bare_ctx.new_image = fresh.new_image
    bare_ctx.new_text = fresh.new_text
    local fresh_widget = require("components/crossbar/crossbar")(bare_ctx)
    local config = require("components/crossbar/defaults")(1920, 1080)
    config.slot_spacing = 16 -- pitch 56, not the default 46
    config.always_show_wxhb = true
    fresh_widget.attach(config)
    fresh_widget.set_pos(100, 900, "main")
    fresh_widget.set_scale(1, "main")
    fresh_widget.show()
    -- Slot 6 (dpad right, column 3, middle row) on the attached pitch.
    local hit = nil
    for _, prim in ipairs(fresh.images) do
      if prim.x == 100 + 30 + 2 * 56 and prim.y == 900 + 35 + 28 then
        hit = prim
      end
    end
    assert.is_not_nil(hit, "a slot must sit on the attached 56px pitch")
    -- And the bounds grow with it: 300 + (30 + 5 * 56 + 40 + 30).
    local _, _, width = fresh_widget.get_bounds("main")
    assert.are.equal(680, width)
  end)

  it("blanks on detach and forgets its side on re-attach", function()
    widget.on_keyboard(39, true, 0, false)
    local panel = images_at(100, 900)[1]
    assert.is_true(panel.visible)
    widget.detach()
    assert.are.equal(0, visible_count(), "detach blanks every prim")
    widget.attach(widget.defaults)
    assert.are.equal(33, visible_count(), "re-attach redraws the resting bar")
    assert.is_false(panel.visible, "the old side is forgotten")
    -- A re-attach straight over a live hold forgets it too: the fresh
    -- machine holds nothing, and the widget's memory must not outlive it.
    widget.on_keyboard(39, true, 0, false)
    assert.is_true(panel.visible)
    widget.attach(widget.defaults)
    assert.is_false(panel.visible, "a fresh machine holds nothing")
  end)

  it("destroys every prim it created", function()
    widget.destroy()
    for _, prim in ipairs(prims.all) do
      assert.are.equal(1, prim.destroyed)
    end
  end)
end)

-- CB5: the widget executes. Bindings come through the directory store,
-- intents run through actions.resolve into ctx.send_command, all three bars
-- own prims, and the per-frame tick drives recasts, costs, counters and the
-- press flash from live data.
describe("crossbar live widget", function()
  local fakes = require("tests/support/fakes")

  local LEFT, RIGHT, LAYER, SWITCH, SHORTCUT = 39, 40, 43, 41, 13
  -- Slot keys: DIK 2-9 = slots 1-8.
  local DIK_SLOT = { 2, 3, 4, 5, 6, 7, 8, 9 }

  --[[ What the resources call the temporary bag. A test can blank it to
       describe a client whose `res.bags` does not carry that word at all,
       which is the case question M is open about - and the case where a
       plain item's zero stops being trustworthy. ]]
  local temporary_bag = "Temporary"
  local function temporary_bag_name()
    return temporary_bag
  end

  -- Resource fixtures: only the fields the widget reads.
  local function resources()
    return {
      spells = {
        [1] = { id = 1, en = "Cure", type = "WhiteMagic", recast_id = 1, mp_cost = 8 },
        [261] = { id = 261, en = "Warp", type = "BlackMagic", recast_id = 261, mp_cost = 100 },
        [338] = { id = 338, en = "Utsusemi: Ichi", type = "Ninjutsu", recast_id = 338, mp_cost = 0 },
      },
      job_abilities = {
        [605] = { id = 605, en = "Provoke", recast_id = 5, tp_cost = 0 },
        [696] = { id = 696, en = "Penury", recast_id = 231 },
        [98] = { id = 98, en = "Berserk", recast_id = 1, tp_cost = 0 },
        [195] = { id = 195, en = "Fire Shot", recast_id = 195, tp_cost = 0 },
        -- Real resource rows: a blood pact and a Ready move. Their recast
        -- ids are the shared pool timers (173 Blood Pact: Rage, 102 Ready),
        -- NOT their ability ids - which is exactly why the chain lookup
        -- must key on the ability id.
        [534] = { id = 534, en = "Eclipse Bite", recast_id = 173, tp_cost = 0 },
        [736] = { id = 736, en = "Sudden Lunge", recast_id = 102, tp_cost = 0 },
      },
      weapon_skills = {
        [42] = { id = 42, en = "Savage Blade", skill = 4 },
      },
      skills = { [4] = { id = 4, en = "Sword" } },
      items = {
        [4165] = { id = 4165, en = "Prism Powder", stack = 12 },
        -- Enchanted gear, for the enchanteditem bind type. `slots` is the
        -- set shape Windower's resources use; ring1 and ring2 both fit.
        [27546] = { id = 27546, en = "Vocation Ring", slots = { [13] = true, [14] = true } },
        -- Worn somewhere that is not a ring, so the GearSwap slot map is
        -- exercised past its one long-standing entry.
        [17040] = { id = 17040, en = "Warp Cudgel", slots = { [0] = true } },
        [4181] = { id = 4181, en = "Instant Warp" },
        -- The warp ladder's last rung, resolved by name rather than by an
        -- id anyone here claims to know.
        [26123] = { id = 26123, en = "Tavnazian Ring", slots = { [13] = true, [14] = true } },
      },
      -- One owned mount, for the travel delay: nothing is owned until a
      -- test puts the key item in env.key_items and lets the KI chunk in.
      mounts = { [1] = { name = "Chocobo" } },
      key_items = { [3000] = { category = "Mounts", name = "\226\153\170Chocobo" } },
      -- Resting, and deliberately NOT the number the module falls back to:
      -- a fixture that agreed with the constant would pass whether or not
      -- the resource table was ever read.
      statuses = { [0] = { en = "Idle" }, [1] = { en = "Engaged" }, [7] = { en = "Resting" } },
      -- Two equippable bags, because gear legitimately lives in a wardrobe
      -- and a ring in one is as usable as a ring in inventory. The third is
      -- the temporary bag, which a test can rename to describe a client
      -- whose resources do not call it that.
      bags = {
        [0] = { id = 0, en = "Inventory", equippable = true },
        [8] = { id = 8, en = "Wardrobe 2", equippable = true },
        -- Not equippable, and not the inventory: the temporary bag, named
        -- as the resources name it.
        [3] = { id = 3, en = temporary_bag_name(), equippable = false },
      },
    }
  end

  local function war_player()
    return {
      id = 777,
      main_job = "WAR",
      main_job_id = 1,
      main_job_level = 99,
      sub_job = "NIN",
      sub_job_id = 13,
      sub_job_level = 49,
      vitals = { mp = 100, tp = 1000 },
      buffs = {},
      status = 0,
    }
  end

  local function war_bindings()
    return {
      WAR = {
        sets = {
          [1] = {
            left = {
              [3] = { type = "ws", action = "Savage Blade", target = "t" },
              [4] = { type = "ja", action = "Provoke", target = "me" },
              [5] = { type = "ma", action = "Cure", target = "t" },
            },
          },
          [2] = {
            left = {
              [1] = { type = "ja", action = "Provoke", target = "me" },
              [4] = { type = "ja", action = "Berserk", target = "me" },
            },
          },
          [3] = { left = { [2] = { type = "ma", action = "Cure", target = "t" } } },
          [4] = { left = { [1] = { type = "ma", action = "Cure", target = "t" } } },
        },
        contexts = {
          ["light-arts"] = { [1] = { left = { [2] = { type = "ja", action = "Penury", target = "me" } } } },
        },
      },
      SHARED = {
        sets = { [6] = { left = { [1] = { type = "ja", action = "Provoke", target = "me" } } } },
      },
    }
  end

  local env, ctx, prims, widget, store, config

  local function build_world(opts)
    opts = opts or {}
    temporary_bag = opts.no_temporary_bag and "Satchel" or "Temporary"
    env = {
      chat = {},
      chat_open = false,
      suppressed = false,
      layout = false,
      commands = {},
      ipc = {},
      files = {},
      store_files = opts.store_files or war_bindings(),
      player = opts.player or war_player(),
      spell_recasts = {},
      ability_recasts = {},
      items = { [0] = {} },
      known_spells = {},
      key_items = {},
      target = { id = 99 },
      equips = {},
      writes = {},
      stats = {},
      dat_paths = {},
      user_visible = true,
      now = 0,
      time = 1000000,
    }
    prims = fakes.prims()
    ctx = {
      screen = function()
        return 1920, 1080
      end,
      say = function(lines)
        if type(lines) == "table" then
          for _, line in ipairs(lines) do
            env.chat[#env.chat + 1] = line
          end
        else
          env.chat[#env.chat + 1] = lines
        end
      end,
      chat_open = function()
        -- Counted: this is windower.ffxi.get_info() behind a wrapper, so a
        -- per-frame call is a per-frame client read like any other.
        env.chat_reads = (env.chat_reads or 0) + 1
        return env.chat_open
      end,
      suppressed = function()
        return env.suppressed
      end,
      layout_active = function()
        env.layout_reads = (env.layout_reads or 0) + 1
        return env.layout
      end,
      new_image = prims.new_image,
      new_text = prims.new_text,
      asset = function(path)
        return "addon/" .. path
      end,
      component_visible = function()
        return env.user_visible
      end,
      send_command = function(command)
        env.commands[#env.commands + 1] = command
      end,
      send_ipc = function(message)
        env.ipc[#env.ipc + 1] = message
      end,
      get_player = function()
        env.player_reads = (env.player_reads or 0) + 1
        return env.player
      end,
      get_mob_by_target = function(...)
        env.target_reads = (env.target_reads or 0) + 1
        if env.target_tokens ~= nil then
          for _, token in ipairs({ ... }) do
            env.target_tokens[#env.target_tokens + 1] = token
          end
        end
        if env.targets == nil then
          return env.target
        end
        -- Per-token targets, for the tests that care which selection a
        -- command is aimed at; the first token with a mob wins, as the
        -- client's own multi-token lookup does.
        for _, token in ipairs({ ... }) do
          if env.targets[token] ~= nil then
            return env.targets[token]
          end
        end
        return nil
      end,
      get_spell_recasts = function()
        env.spell_reads = (env.spell_reads or 0) + 1
        return env.spell_recasts
      end,
      get_ability_recasts = function()
        env.ability_reads = (env.ability_reads or 0) + 1
        return env.ability_recasts
      end,
      get_key_items = function()
        return env.key_items
      end,
      get_spells = function()
        return env.known_spells
      end,
      get_items = function(bag)
        env.item_reads = (env.item_reads or 0) + 1
        return env.items[bag]
      end,
      --[[ The client puts the piece ON, which is what the widget's poll
           reads back: a ring that stays flagged in-the-bag is a ring
           something swapped off, and the fixtures modelled that state for
           every wait until 2026-08-22 - a thing the real client cannot do,
           and the reason an equip losing a race with GearSwap went unseen.
           A test wanting the swapped-off case puts the status back. ]]
      set_equip = function(bag_slot, equip_slot, bag)
        env.equips[#env.equips + 1] = { bag_slot, equip_slot, bag }
        for _, entry in ipairs(env.items[bag] or {}) do
          if type(entry) == "table" and entry.slot == bag_slot then
            entry.status = 5
          end
        end
      end,
      decode_extdata = function()
        return env.ext
      end,
      random = function()
        return 0.5
      end,
      now = function()
        return env.now
      end,
      time = function()
        return env.time
      end,
      file_exists = function(path)
        env.stats[#env.stats + 1] = path
        return env.files[path] == true
      end,
      read_dat = function(dat_path, _, length)
        env.dat_paths[#env.dat_paths + 1] = dat_path
        if env.dat_fails then
          return nil
        end
        return string.rep("\0", length)
      end,
      write_binary = function(path)
        env.writes[#env.writes + 1] = path
        env.files["addon/" .. path] = true
        return true
      end,
      game_path = function()
        return "C:/FFXI/"
      end,
      resources = resources(),
    }
    store = {
      load = function(name)
        return env.store_files[name]
      end,
      save = function(name, value)
        env.store_files[name] = value
      end,
    }
    widget = new_crossbar(ctx)
    config = widget.defaults
    if opts.tune_config then
      opts.tune_config(config)
    end
    widget.attach(config, function()
      env.config_saves = (env.config_saves or 0) + 1
    end, store)
    widget.set_pos(100, 900, "main")
    widget.set_scale(1, "main")
    widget.show()
  end

  -- The prim-order contract: images[1] is the panel; then, per group in
  -- (xhb_left, xhb_right, wxhb_left, wxhb_right, expanded) order and slot
  -- 1-8, six images in upstream's draw order (background, chain, icon,
  -- sweep, frame, feedback) and three texts (name, cost, recast); the
  -- skillchain indicator's bg and fill are the last two images.
  local GROUP_INDEX = { xhb_left = 0, xhb_right = 1, wxhb_left = 2, wxhb_right = 3, expanded = 4 }
  local IMAGE_KIND = { background = 1, chain = 2, icon = 3, sweep = 4, frame = 5, feedback = 6 }
  local TEXT_KIND = { name = 1, cost = 2, recast = 3 }

  local function image_of(group, slot, kind)
    return prims.images[1 + (GROUP_INDEX[group] * 8 + slot - 1) * 6 + IMAGE_KIND[kind]]
  end

  local function indicator_prims()
    return prims.images[#prims.images - 1], prims.images[#prims.images]
  end

  -- The sword sits immediately before the indicator pair, which is last.
  local function sword_icon()
    return prims.images[#prims.images - 2]
  end

  local function text_of(group, slot, kind)
    return prims.texts[(GROUP_INDEX[group] * 8 + slot - 1) * 3 + TEXT_KIND[kind]]
  end

  local function press(dik)
    return widget.on_keyboard(dik, true, 0, false)
  end

  local function release(dik)
    return widget.on_keyboard(dik, false, 0, false)
  end

  local function said()
    return table.concat(env.chat, "\n")
  end

  describe("construction", function()
    it("runs headless when the ctx lacks a text constructor", function()
      -- The header promises headless degradation for a partial prim
      -- surface; images-without-texts must not throw at construction.
      build_world()
      local bare_ctx = {}
      for key, value in pairs(ctx) do
        bare_ctx[key] = value
      end
      bare_ctx.new_text = nil
      local fresh
      assert.has_no.errors(function()
        fresh = new_crossbar(bare_ctx)
      end)
      fresh.attach(fresh.defaults, function() end, store)
      assert.is_true(fresh.on_keyboard(LEFT, true, 0, false), "the machine still runs headless")
    end)
  end)

  describe("store and job scoping", function()
    it("declares the directory store", function()
      build_world()
      assert.is_true(widget.wants_store)
    end)

    it("re-reads the screen size on attach", function()
      -- The right-justified cost x subtracts the screen width; a client
      -- resolution change must correct on the next attach (targetbar's
      -- precedent), not stay pinned to the width at construction.
      build_world()
      ctx.screen = function()
        return 1000, 800
      end
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      -- Slot 3 (face bottom, column 5): x = 30 + 4*46; cost x = x + 46.
      assert.are.equal(100 + (30 + 4 * 46 + 46) - 1000, text_of("xhb_left", 3, "cost").x)
    end)

    it("survives an attach without a store", function()
      build_world()
      assert.has_no.errors(function()
        widget.attach(config, function() end, nil)
      end)
    end)

    it("draws a bound slot's icon from the per-job file", function()
      build_world()
      env.files["addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png"] = true
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      local icon = image_of("xhb_left", 3, "icon")
      assert.are.equal("addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png", icon.last.path)
      assert.is_true(icon.visible)
      assert.are.equal("Savage Blade", text_of("xhb_left", 3, "name").last.text)
    end)

    it("redraws the icon when the icon verb overrides it", function()
      --[[ The icon memo re-runs on record IDENTITY, and the icon verb
           mutates the stored entry in place - `override` writes the field
           on the table `entry_at` handed back, which is the live one - so
           the identity never moved and the slot kept Savage Blade's art
           (Kevin, live client, test plan C19). The alias verb looked fine
           beside it only because the label is recomputed every paint. ]]
      build_world()
      env.files["addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png"] = true
      env.files["addon/components/crossbar/assets/icons/map.png"] = true
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      assert.are.equal(
        "addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png",
        image_of("xhb_left", 3, "icon").last.path
      )
      widget.handle_command({ "icon", "1L3", "map" })
      widget.update()
      assert.are.equal("addon/components/crossbar/assets/icons/map.png", image_of("xhb_left", 3, "icon").last.path)
      -- The memo must still settle on the override, or an re-iconed slot
      -- stats the disk every frame for the life of the binding.
      env.stats = {}
      widget.handle_command({ "set", "1" })
      for _, path in ipairs(env.stats) do
        assert.is_nil(path:find("map%.png"), "a settled override must not be re-stat'd: " .. path)
      end
      -- And back off again: clearing the override restores the action's own.
      widget.handle_command({ "icon", "1L3" })
      widget.update()
      assert.are.equal(
        "addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png",
        image_of("xhb_left", 3, "icon").last.path
      )
    end)

    it("labels a type-only record by its type", function()
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mr" }
      build_world({ store_files = files })
      assert.are.equal("mr", text_of("xhb_left", 2, "name").last.text)
      assert.is_true(text_of("xhb_left", 2, "name").visible)
    end)

    it("labels a mount the way the game writes it, under the player's own label", function()
      -- Two owners of a slot's name: the player's `alias` and the record's
      -- `display` (the game's casing for a command form that has to stay
      -- lower case). Alias first, display under it, the raw action last.
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mount", action = "chocobo", display = "Chocobo" }
      build_world({ store_files = files })
      assert.are.equal("Chocobo", text_of("xhb_left", 2, "name").last.text)

      files.WAR.sets[1].left[2] = { type = "mount", action = "chocobo", display = "Chocobo", alias = "Pull mount" }
      build_world({ store_files = files })
      assert.are.equal("Pull mount", text_of("xhb_left", 2, "name").last.text)
    end)

    it("labels a degenerate record with nothing, never the word nil", function()
      local files = war_bindings()
      files.WAR.sets[1].left[2] = {}
      build_world({ store_files = files })
      assert.are.equal("", text_of("xhb_left", 2, "name").last.text)
      assert.is_false(text_of("xhb_left", 2, "name").visible)
    end)

    it("draws builtin and opener icons on their bound slots", function()
      -- The builtin branch only works if the widget passed actions.icon_for
      -- into render; observed through the drawn slots, not a spec-only seam.
      local files = war_bindings()
      files.WAR.sets[1].left[1] = { type = "mr" }
      files.WAR.sets[1].left[2] = { type = "open", action = "equipment" }
      files.WAR.sets[1].left[7] = { type = "draw" }
      local player = war_player()
      player.buffs = { 252 }
      build_world({ store_files = files, player = player })
      env.files["addon/components/crossbar/assets/icons/mount.png"] = true
      env.files["addon/components/crossbar/assets/icons/check.png"] = true
      env.files["addon/components/crossbar/assets/icons/dismount.png"] = true
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      assert.are.equal("addon/components/crossbar/assets/icons/mount.png", image_of("xhb_left", 1, "icon").last.path)
      assert.are.equal("addon/components/crossbar/assets/icons/check.png", image_of("xhb_left", 2, "icon").last.path)
      assert.are.equal(
        "addon/components/crossbar/assets/icons/dismount.png",
        image_of("xhb_left", 7, "icon").last.path,
        "draw's icon follows the mounted state"
      )
    end)

    it("keeps an empty slot's icon and name down", function()
      build_world()
      assert.is_false(image_of("xhb_left", 1, "icon").visible)
      assert.is_false(text_of("xhb_left", 1, "name").visible)
    end)
  end)

  describe("execution", function()
    it("fires the bound action on its slot key", function()
      build_world()
      press(LEFT)
      press(DIK_SLOT[3])
      assert.are.same({ 'input /ws "Savage Blade" <t>' }, env.commands)
    end)

    it("stays silent on an empty slot: no command, no hint, no flash", function()
      build_world()
      press(LEFT)
      press(DIK_SLOT[1])
      assert.are.same({}, env.commands)
      assert.are.equal(0, #env.chat)
      assert.is_false(image_of("xhb_left", 1, "feedback").visible, "nothing fired, nothing flashes")
    end)

    it("ranks disabled above suppressed across the whole truth table", function()
      -- (visible, unsuppressed): normal.
      build_world()
      assert.is_true(press(LEFT))
      press(DIK_SLOT[3])
      assert.are.equal(1, #env.commands)

      -- (visible, suppressed): blocked and inert - the cutscene row.
      build_world()
      env.suppressed = true
      widget.hide()
      assert.is_true(press(LEFT), "ours through the cutscene")
      press(DIK_SLOT[3])
      assert.are.same({}, env.commands)

      -- (user-hidden, unsuppressed): everything falls through.
      build_world()
      env.user_visible = false
      widget.hide()
      assert.is_false(press(LEFT), "the player turned it off")

      -- (user-hidden, suppressed): the user's hide outranks the cutscene.
      build_world()
      env.user_visible = false
      widget.hide()
      env.suppressed = true
      assert.is_false(press(LEFT), "a crossbar the player turned off keeps its keys with the game")
      assert.are.same({}, env.commands)
    end)

    it("keeps ranking through hides and shows that arrive mid-cutscene", function()
      -- A user hide DURING suppression: core never calls hide() again (the
      -- widget is already hidden), only the flag flips - and it must count.
      build_world()
      env.suppressed = true
      widget.hide()
      assert.is_true(press(LEFT), "suppressed but the user still wants it")
      assert.is_true(release(LEFT))
      env.user_visible = false
      assert.is_false(press(LEFT), "the flag flip alone releases the keys")
      release(LEFT)
      env.suppressed = false
      assert.is_false(press(LEFT), "and they stay with the game when the cutscene ends")
      release(LEFT)
      -- A user show DURING suppression: core still keeps it hidden
      -- (suppression wins the display), but the keys are ours again.
      env.suppressed = true
      env.user_visible = true
      assert.is_true(press(LEFT), "suppressed behaviour resumes on the flag alone")
      press(DIK_SLOT[3])
      assert.are.same({}, env.commands, "still inert while suppressed")
      release(DIK_SLOT[3])
      release(LEFT)
      env.suppressed = false
      widget.show()
      press(LEFT)
      press(DIK_SLOT[3])
      assert.are.same({ 'input /ws "Savage Blade" <t>' }, env.commands)
    end)

    it("keeps every dedicated key through a cutscene, which suppresses AND hides", function()
      -- Core hides the component BECAUSE of suppression (core.apply), so
      -- `not visible` alone cannot mean disabled: collapsing the two lets
      -- the five keys fall through mid-cutscene and the first `;` opens
      -- the chat log. Suppressed = blocked and inert; disabled = the
      -- user-hidden case only.
      build_world()
      env.suppressed = true
      widget.hide()
      assert.is_true(press(LEFT), "the side key stays ours")
      assert.is_true(press(RIGHT))
      assert.is_true(press(LAYER))
      assert.is_true(press(SWITCH))
      assert.is_true(press(SHORTCUT))
      assert.is_false(press(DIK_SLOT[3]), "slot keys are the game's under suppression")
      assert.are.same({}, env.commands, "nothing fires")
      assert.are.equal(0, #env.chat)
      release(DIK_SLOT[3])
      assert.is_true(release(SHORTCUT), "latched releases stay swallowed")
      release(SWITCH)
      release(LAYER)
      release(RIGHT)
      release(LEFT)
      -- The cutscene ends: suppression lifts, core shows the widget again.
      env.suppressed = false
      widget.show()
      press(LEFT)
      press(DIK_SLOT[3])
      assert.are.same({ 'input /ws "Savage Blade" <t>' }, env.commands, "normal service resumes")
    end)

    it("executes nothing while a guard is up, with real wiring", function()
      -- The stand-in block pins the BLOCK behaviour; this pins execution,
      -- with a ctx that has send_command so the assertion bites.
      for _, guard in ipairs({ "suppressed", "layout", "chat_open" }) do
        build_world()
        env[guard] = true
        press(LEFT)
        press(DIK_SLOT[3])
        assert.are.same({}, env.commands, guard)
      end
    end)

    it("survives a hand-configured ninth slot key", function()
      -- input's slot map is positional and a hand-edited file can carry a
      -- ninth entry; the flash has nowhere to draw but the binding fires.
      local files = war_bindings()
      files.WAR.sets[1].left[9] = { type = "ja", action = "Provoke", target = "me" }
      build_world({
        store_files = files,
        tune_config = function(tuned)
          tuned.input.slot_keys = { 2, 3, 4, 5, 6, 7, 8, 9, 10 }
        end,
      })
      press(LEFT)
      assert.has_no.errors(function()
        press(10)
      end)
      assert.are.same({ 'input /ja "Provoke" <me>' }, env.commands)
    end)

    it("flashes the fired slot and fades it out", function()
      build_world()
      press(LEFT)
      press(DIK_SLOT[3])
      local flash = image_of("xhb_left", 3, "feedback")
      assert.is_true(flash.visible)
      assert.are.equal(config.feedback.alpha, flash.last.alpha)
      widget.update()
      assert.are.equal(config.feedback.alpha - config.feedback.speed, flash.last.alpha)
      for _ = 1, 10 do
        widget.update()
      end
      assert.is_false(flash.visible, "the flash is spent")
    end)

    it("jumps to a set with the switch chord and persists it", function()
      build_world()
      press(SWITCH)
      press(DIK_SLOT[2])
      release(DIK_SLOT[2])
      release(SWITCH)
      assert.are.equal(2, env.store_files.WAR.active_set)
      -- And the bar repainted onto set 2: slot 1 now carries Provoke's name.
      assert.are.equal("Provoke", text_of("xhb_left", 1, "name").last.text)
      press(LEFT)
      press(DIK_SLOT[1])
      assert.are.same({ 'input /ja "Provoke" <me>' }, env.commands)
    end)

    it("cycles the sheathed rotation, honouring flags and emptiness", function()
      build_world({
        tune_config = function(tuned)
          tuned.set_flags[2].cycle = { drawn = true, sheathed = false }
          tuned.set_flags[4].cycle = { drawn = false, sheathed = true }
        end,
      })
      -- Sheathed: set 2 is drawn-only, set 3 is empty of BASE bindings but
      -- still resolves nothing (no context up), set 4 is the next sheathed
      -- stop. From 1: 2 skipped (flag), 3 has content (set 3 left 2) - wait,
      -- set 3 has a base binding, so it qualifies.
      press(SWITCH)
      release(SWITCH)
      assert.are.equal(3, env.store_files.WAR.active_set, "set 2 is drawn-only; set 3 is the next sheathed stop")
      -- Engage: the drawn rotation now includes 2 but not 4.
      widget.update("status", 1)
      press(SWITCH)
      release(SWITCH)
      assert.are.equal(1, env.store_files.WAR.active_set, "from 3: 4 is sheathed-only, 5-8 empty, 1 qualifies")
      press(SWITCH)
      release(SWITCH)
      assert.are.equal(2, env.store_files.WAR.active_set, "drawn reaches set 2 now")
    end)

    it("keeps the drawn state when the mob dies, until an explicit draw", function()
      build_world()
      widget.update("status", 1)
      widget.update("status", 0)
      -- Still drawn: the draw toggle now disengages.
      press(LAYER)
      press(SWITCH)
      release(SWITCH)
      release(LAYER)
      assert.are.same({ "input /attack off" }, env.commands)
    end)

    it("fires the draw toggle from the gesture, flipping the weapon state", function()
      --[[ Entering drawn sends nothing at all (Kevin, 2026-08-22): the
           rotation is the point, not the attack, and the sword beside the
           set label is the feedback. Leaving it still disengages - an
           explicit `draw` while drawn means "I am done fighting". ]]
      build_world()
      press(LAYER)
      press(SWITCH)
      release(SWITCH)
      release(LAYER)
      assert.are.same({}, env.commands, "nothing sent on the way in")
      assert.is_true(sword_icon().visible, "but the sword says the state flipped")
      -- Drawn now; the same gesture disengages.
      press(LAYER)
      press(SWITCH)
      release(SWITCH)
      release(LAYER)
      assert.are.same({ "input /attack off" }, env.commands)
      assert.is_false(sword_icon().visible)
    end)

    it("sends nothing on the way in whether or not anything is targeted", function()
      -- The target used to decide between `/attack <t>` and a refusal. It
      -- decides nothing now, which is why draw_state stopped reading it.
      build_world()
      env.target = nil
      press(LAYER)
      press(SWITCH)
      release(SWITCH)
      release(LAYER)
      assert.are.same({}, env.commands)
      assert.are.same({}, env.chat, "no complaint")
      assert.is_true(sword_icon().visible)
    end)

    it("ignores a hand-edited non-string shortcut verb", function()
      build_world({
        tune_config = function(tuned)
          tuned.input.shortcuts = { [13] = { tap = 5, chorded = true } }
        end,
      })
      assert.has_no.errors(function()
        press(SHORTCUT)
        release(SHORTCUT)
        press(LEFT)
        press(SHORTCUT)
      end)
      assert.are.same({}, env.commands)
    end)

    it("repaints the draw slot's icon when the gesture flips the weapon state", function()
      local files = war_bindings()
      files.WAR.sets[1].left[7] = { type = "draw" }
      build_world({ store_files = files })
      env.files["addon/components/crossbar/assets/icons/attack.png"] = true
      env.files["addon/components/crossbar/assets/icons/disengage.png"] = true
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      local icon = image_of("xhb_left", 7, "icon")
      assert.are.equal("addon/components/crossbar/assets/icons/attack.png", icon.last.path, "sheathed shows attack")
      press(LAYER)
      press(SWITCH)
      release(SWITCH)
      release(LAYER)
      assert.are.equal(
        "addon/components/crossbar/assets/icons/disengage.png",
        icon.last.path,
        "the flip repaints the draw slot"
      )
    end)

    it("does nothing on a bare Select, and keeps the key anyway", function()
      --[[ Select used to open the map bare. A key that is ours outright
           should not act on its own (Kevin, 2026-08-21) - but it is still
           ours: the block keys off the shortcut entry existing, not off it
           carrying a verb, so the game never sees it either. ]]
      build_world()
      assert.is_true(press(SHORTCUT), "still swallowed")
      assert.is_true(release(SHORTCUT))
      assert.are.same({}, env.commands)
    end)

    it("still routes a tap verb where one is configured", function()
      -- The mechanism is intact; only the shipped default dropped its tap.
      build_world({
        tune_config = function(fresh)
          fresh.input.shortcuts[13] = { tap = "open map", chorded = "edit" }
        end,
      })
      press(SHORTCUT)
      release(SHORTCUT)
      assert.are.same({ "input /map" }, env.commands)
    end)

    it("routes the shortcut chord to the binder", function()
      -- Until CB8 this answered "binder not yet available"; the binder now
      -- exists, so the chord is the pad's way into it.
      build_world()
      press(LEFT)
      press(SHORTCUT)
      assert.is_not_nil(said():lower():find("edit mode on"), "said: " .. said())
    end)
  end)

  describe("the other bars", function()
    it("lays out only the groups on the anchor that moved", function()
      build_world()
      -- Layout mode pushes set_scale then set_pos for EVERY anchor on every
      -- mouse move; laying all forty slots out each time is thousands of prim
      -- calls a move. A placement touches its own anchor's groups and no others
      -- (the main anchor carries both XHB sides and the expanded row).
      local function pos_calls(prim)
        local count = 0
        for _, call in ipairs(prim.calls) do
          if call.name == "pos" then
            count = count + 1
          end
        end
        return count
      end
      local moved = image_of("wxhb_left", 1, "background")
      local untouched = image_of("xhb_left", 1, "background")
      local moved_before, untouched_before = pos_calls(moved), pos_calls(untouched)
      widget.set_pos(400, 100, "wxhb_left")
      assert.is_true(pos_calls(moved) > moved_before, "the anchor that moved is laid out")
      assert.are.equal(untouched_before, pos_calls(untouched), "the main anchor's slots are not")
    end)
    it("lays nothing out for a placement that changes nothing", function()
      build_world()
      -- The other half of the drag cost: core pushes scale and position
      -- together, and while dragging only the position actually moves.
      widget.set_pos(400, 100, "wxhb_left")
      widget.set_scale(1.5, "wxhb_left")
      local prim = image_of("wxhb_left", 1, "background")
      local before = #prim.calls
      widget.set_scale(1.5, "wxhb_left")
      assert.are.equal(before, #prim.calls, "an unchanged scale lays nothing out")
      widget.set_pos(400, 100, "wxhb_left")
      assert.are.equal(before, #prim.calls, "nor does an unchanged position")
    end)

    it("writes nothing to an untouched anchor once a drag is under way", function()
      -- The whole per-move cost, driven the way core drives it: apply()
      -- pushes scale and position for EVERY anchor, then set_preview, then
      -- show(). Dragging main must stop reaching the WXHB's prims entirely
      -- once the first pass has settled them.
      build_world()
      local at = {
        { "main", 100, 900 },
        { "wxhb_left", 400, 100 },
        { "wxhb_right", 800, 100 },
        { "indicator", 600, 700 },
      }
      env.layout = true
      local function core_apply(main_x, main_y)
        for _, anchor in ipairs(at) do
          local name = anchor[1]
          widget.set_scale(1, name)
          widget.set_pos(name == "main" and main_x or anchor[2], name == "main" and main_y or anchor[3], name)
        end
        widget.set_preview(true)
        widget.show()
      end
      core_apply(101, 901)
      local untouched = image_of("wxhb_left", 1, "background")
      local moved = image_of("xhb_left", 1, "background")
      local untouched_before, moved_before = #untouched.calls, #moved.calls
      core_apply(102, 902)
      core_apply(103, 903)
      assert.are.equal(untouched_before, #untouched.calls, "a settled anchor takes no write while another drags")
      assert.is_true(#moved.calls > moved_before, "the dragged anchor is still laid out every move")
    end)

    it("costs nothing when the preview flag is pushed again unchanged", function()
      -- Core pushes set_preview on every apply, so during a layout-mode drag
      -- it arrives once a mouse move with the same answer every time.
      build_world()
      widget.set_preview(true)
      local function calls()
        local total = 0
        for _, prim in ipairs(prims.all) do
          total = total + #prim.calls
        end
        return total
      end
      local settled = calls()
      widget.set_preview(true)
      widget.set_preview(true)
      assert.are.equal(settled, calls(), "an unchanged preview flag is not a refresh")
    end)

    it("leaves a group that is never on screen alone, refresh after refresh", function()
      -- Expanded Hold is hidden unless both sides are held, so on a normal
      -- drag it is 8 of the 40 slots that no refresh has anything to say
      -- about. Re-pushing "hidden" over "hidden" is exactly what the
      -- change-gate exists to stop, and core runs a refresh per mouse move.
      build_world()
      local function calls()
        local total = 0
        for _, kind in ipairs({ "background", "chain", "icon", "sweep", "frame", "feedback" }) do
          total = total + #image_of("expanded", 1, kind).calls
        end
        for _, kind in ipairs({ "name", "cost", "recast" }) do
          total = total + #text_of("expanded", 1, kind).calls
        end
        return total
      end
      -- Two refreshes that touch nothing else: the preview flag flips the
      -- WXHB's halves and leaves Expanded exactly where it was.
      widget.set_preview(true)
      local settled = calls()
      widget.set_preview(false)
      widget.set_preview(true)
      assert.are.equal(settled, calls(), "a settled hidden group must cost nothing")
    end)

    it("still repaints on the way back from hidden, preview or not", function()
      -- The re-sync paths show() exists for: a hide (a user hide, or core's
      -- suppression) leaves the machine swallowing releases, so the way back
      -- must re-read the hold state AND repaint - a bar that came back empty
      -- would be the CB5 handshake broken.
      build_world()
      widget.set_preview(true)
      widget.show()
      widget.hide()
      press(LEFT)
      widget.show()
      assert.is_true(prims.images[1].visible, "the side held while hidden lights on the way back")
      assert.is_true(image_of("xhb_left", 1, "background").visible)
      assert.are.equal("Provoke", text_of("xhb_left", 4, "name").last.text, "with its contents painted")
    end)

    it("shows the WXHB while its gesture holds, with the view's contents", function()
      build_world()
      widget.set_pos(400, 100, "wxhb_left")
      local background = image_of("wxhb_left", 1, "background")
      assert.is_false(background.visible, "hidden at rest with always_show_wxhb off")
      press(LEFT)
      press(LAYER)
      assert.is_true(background.visible)
      assert.are.same({ 400 + 30 + 4 * 46, 100 + 35 }, { background.x, background.y }, "slot 1 on the wxhb anchor")
      assert.are.equal("Provoke", text_of("wxhb_left", 1, "name").last.text, "the view points at set 2 left")
      -- The active panel sits on the wxhb anchor, not on main.
      local panel = prims.images[1]
      assert.is_true(panel.visible)
      assert.are.same({ 400, 100 }, { panel.x, panel.y })
      -- And the slot key fires the view's binding.
      press(DIK_SLOT[1])
      assert.are.same({ 'input /ja "Provoke" <me>' }, env.commands)
      release(LAYER)
      assert.is_false(background.visible, "the layer dropped; back to the XHB side")
    end)

    it("degrades a truthy-garbage always_show_wxhb to off, never a bare panel", function()
      -- merge_defaults lets `always_show_wxhb = 1` through; the widget's
      -- posture for config garbage is the shipped default (false). The
      -- plan's boolean plumbing must not leak the raw 1: refresh reads
      -- `== true`, so a leaked truthy would hide the bar while the panel
      -- still drew - a bare panel with no slots under it.
      build_world({
        tune_config = function(tuned)
          tuned.always_show_wxhb = 1
        end,
      })
      widget.set_pos(400, 100, "wxhb_left")
      local background = image_of("wxhb_left", 1, "background")
      assert.is_false(background.visible, "garbage reads as the default: off at rest")
      press(LEFT)
      press(LAYER)
      assert.is_true(background.visible, "the held bar draws")
      assert.is_true(prims.images[1].visible, "with its panel - never the panel alone")
    end)

    it("draws the WXHB at rest when always_show_wxhb is on", function()
      build_world({
        tune_config = function(tuned)
          tuned.always_show_wxhb = true
        end,
      })
      widget.set_pos(400, 100, "wxhb_left")
      widget.set_pos(800, 100, "wxhb_right")
      assert.is_true(image_of("wxhb_left", 1, "background").visible)
      assert.is_true(image_of("wxhb_right", 1, "background").visible)
    end)

    it("fires the Expanded view's binding while both sides hold", function()
      build_world()
      press(LEFT)
      press(RIGHT)
      press(DIK_SLOT[2])
      assert.are.same({ 'input /ma "Cure" <t>' }, env.commands, "expanded_lr points at set 3 left")
      assert.are.equal("Cure", text_of("expanded", 2, "name").last.text)
    end)

    it("repaints the Expanded contents when shown mid-hold", function()
      -- Hidden (user-hide: no suppression) the machine still tracks the
      -- keys; showing again must repaint, not just refresh - the Expanded
      -- group's contents were last painted when no view was active.
      build_world()
      env.user_visible = false
      widget.hide()
      press(LEFT)
      press(RIGHT)
      env.user_visible = true
      widget.show()
      local name = text_of("expanded", 2, "name")
      assert.are.equal("Cure", name.last.text, "the expanded_lr view's set 3 contents are painted")
      assert.is_true(name.visible)
      assert.is_true(image_of("expanded", 2, "background").visible)
    end)

    it("keeps the layout-mode corner honest while Expanded is held", function()
      build_world()
      widget.set_pos(400, 100, "wxhb_left")
      widget.set_pos(800, 100, "wxhb_right")
      env.layout = true
      widget.set_preview(true)
      press(LEFT)
      press(RIGHT)
      -- Expanded replaces the XHB on main...
      assert.is_true(image_of("expanded", 2, "background").visible)
      assert.is_false(image_of("xhb_left", 3, "background").visible)
      -- ...while preview keeps the WXHB halves up for placement...
      assert.is_true(image_of("wxhb_left", 1, "background").visible)
      assert.is_true(image_of("wxhb_right", 1, "background").visible)
      -- ...and main's bounds stay the full XHB footprint, so a drag mid-hold
      -- clamps against the real box, not the transient eight-slot one.
      assert.are.same({ 100, 900, 630, 180 }, { widget.get_bounds("main") })
    end)

    it("previews the WXHB bars for layout placement", function()
      build_world()
      widget.set_pos(400, 100, "wxhb_left")
      widget.set_preview(true)
      assert.is_true(image_of("wxhb_left", 1, "background").visible)
      widget.set_preview(false)
      assert.is_false(image_of("wxhb_left", 1, "background").visible)
    end)
  end)

  describe("job, buff and status events", function()
    it("reloads on a job change: shared sets follow, job sets do not", function()
      build_world({
        tune_config = function(tuned)
          tuned.set_flags[6].shared = true
        end,
      })
      widget.handle_command({ "set", "6" })
      press(LEFT)
      press(DIK_SLOT[1])
      assert.are.equal('input /ja "Provoke" <me>', env.commands[#env.commands], "the shared set on WAR")
      release(DIK_SLOT[1])
      release(LEFT)
      env.player = war_player()
      env.player.main_job = "DRK"
      env.player.main_job_id = 8
      widget.update("job change", 8, 99, 13, 49)
      widget.handle_command({ "set", "6" })
      press(LEFT)
      press(DIK_SLOT[1])
      assert.are.equal('input /ja "Provoke" <me>', env.commands[#env.commands], "the shared set followed to DRK")
      release(DIK_SLOT[1])
      widget.handle_command({ "set", "1" })
      press(DIK_SLOT[3])
      assert.are_not.equal('input /ws "Savage Blade" <t>', env.commands[#env.commands], "WAR's job set did not")
    end)

    it("waits for a fresh sub before rescoping a sub-only change", function()
      -- The event carries (main_id, main_lv, sub_id, ...); dropping the sub
      -- id would rescope the stale sub, clear the want, and never catch up.
      local files = war_bindings()
      files.WAR.sub = { DNC = { [1] = { left = { [8] = { type = "ja", action = "Provoke", target = "me" } } } } }
      build_world({ store_files = files })
      widget.update("job change", 1, 99, 19, 49)
      press(LEFT)
      press(DIK_SLOT[8])
      assert.are.same({}, env.commands, "the stale NIN sub must not be scoped as final")
      release(DIK_SLOT[8])
      env.player.sub_job = "DNC"
      env.player.sub_job_id = 19
      widget.update()
      press(DIK_SLOT[8])
      assert.are.same({ 'input /ja "Provoke" <me>' }, env.commands, "the DNC sub layer resolves once scoped")
    end)

    it("caps the rescope retry at ten seconds", function()
      -- The client never confirms the announced ids (a mid-zone job change
      -- that dies, a stale packet): the per-frame get_player retry stands
      -- down after 10s, re-armed by the next job change event.
      build_world()
      widget.hide()
      widget.update("job change", 8, 99, 13, 49)
      env.player_reads = 0
      env.now = 1
      widget.update()
      assert.is_true(env.player_reads > 0, "the retry is live inside the window")
      env.now = 11
      widget.update()
      env.player_reads = 0
      env.now = 12
      widget.update()
      widget.update()
      assert.are.equal(0, env.player_reads, "the retry has stood down")
    end)

    it("waits for a fresh player before rescoping", function()
      build_world()
      -- The job change event outruns get_player: the stale player still
      -- says WAR. Nothing rescopes until the ids agree.
      widget.update("job change", 8, 99, 13, 49)
      press(LEFT)
      press(DIK_SLOT[3])
      assert.are.same({ 'input /ws "Savage Blade" <t>' }, env.commands, "still WAR until the client catches up")
      release(DIK_SLOT[3])
      env.player.main_job = "DRK"
      env.player.main_job_id = 8
      widget.update()
      press(DIK_SLOT[3])
      assert.are.equal(1, #env.commands, "DRK has no binding in that slot")
    end)

    it("swaps a context layer in on a buff and back off", function()
      build_world()
      press(LEFT)
      press(DIK_SLOT[2])
      assert.are.same({}, env.commands, "slot 2 is empty in the base")
      release(DIK_SLOT[2])
      env.player.buffs = { 358 }
      widget.update("gain buff", 358)
      press(DIK_SLOT[2])
      assert.are.same({ 'input /ja "Penury" <me>' }, env.commands)
      release(DIK_SLOT[2])
      env.player.buffs = {}
      widget.update("lose buff", 358)
      press(DIK_SLOT[2])
      assert.are.equal(1, #env.commands, "the layer dropped with the buff")
    end)

    it("keeps the arts layer alive on the addendum buff alone", function()
      -- FFXI fires a spurious arts `lose buff` while an Addendum is used;
      -- the full-list resync plus the any_of implication must survive it.
      build_world()
      env.player.buffs = { 401 }
      widget.update("gain buff", 401)
      press(LEFT)
      press(DIK_SLOT[2])
      assert.are.same({ 'input /ja "Penury" <me>' }, env.commands)
    end)
  end)

  describe("the per-frame tick", function()
    it("reads the client on the roster cadence, not per frame", function()
      build_world()
      env.player_reads, env.spell_reads, env.ability_reads = 0, 0, 0
      for i = 1, 12 do
        env.now = i * 0.01
        widget.update()
      end
      assert.are.equal(1, env.player_reads, "12 frames inside 200ms are one read")
      assert.are.equal(1, env.spell_reads)
      assert.are.equal(1, env.ability_reads)
      env.now = 0.4
      widget.update()
      assert.are.equal(2, env.player_reads, "the next cadence window reads again")
    end)

    it("reads nothing from the client while hidden", function()
      build_world()
      widget.hide()
      env.player_reads, env.spell_reads, env.ability_reads = 0, 0, 0
      for i = 1, 3 do
        env.now = i
        widget.update()
      end
      assert.are.equal(0, env.player_reads + env.spell_reads + env.ability_reads)
    end)

    it("touches no prim at all on a settled tick", function()
      -- 365 prims at sixty frames a second: partylist's written/push gate,
      -- pinned the same way partylist_spec pins it - two identical ticks,
      -- zero recorder calls on the second.
      build_world()
      env.ability_recasts = { [5] = 30 }
      env.spell_recasts = { [1] = 600 }
      widget.update()
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

    it("honours every hide option", function()
      build_world({
        tune_config = function(tuned)
          tuned.hide.empty_slots = true
          tuned.hide.action_name = true
          tuned.hide.cost = true
          tuned.hide.recast_animation = true
          tuned.hide.recast_text = true
        end,
      })
      env.spell_recasts = { [1] = 1800 }
      widget.update()
      assert.is_false(image_of("xhb_left", 1, "background").visible, "empty_slots: an empty slot draws nothing")
      assert.is_true(image_of("xhb_left", 3, "background").visible, "a bound slot still draws")
      assert.is_false(text_of("xhb_left", 3, "name").visible, "action_name")
      assert.is_false(text_of("xhb_left", 5, "cost").visible, "cost")
      assert.is_false(image_of("xhb_left", 5, "sweep").visible, "recast_animation")
      assert.is_false(text_of("xhb_left", 5, "recast").visible, "recast_text")
    end)

    it("never tick-writes a bar that is off screen", function()
      -- The wxhb view points at set 2, whose slot 1 carries Provoke with a
      -- live recast; the bar is placed but not held, so nothing may show.
      build_world()
      widget.set_pos(400, 100, "wxhb_left")
      env.ability_recasts = { [5] = 30 }
      widget.update()
      assert.is_false(text_of("wxhb_left", 1, "cost").visible)
      assert.is_false(image_of("wxhb_left", 1, "sweep").visible)
      assert.is_false(text_of("wxhb_left", 1, "recast").visible)
    end)

    it("re-learns the sweep denominator when a set switch changes the action", function()
      build_world()
      env.ability_recasts = { [5] = 300 }
      widget.update()
      widget.handle_command({ "set", "2" })
      env.now = 0.3
      env.ability_recasts = { [1] = 25 }
      widget.update()
      local sweep = image_of("xhb_left", 4, "sweep")
      assert.are.equal(
        "addon/components/crossbar/assets/cooldown/frame_32.png",
        sweep.last.path,
        "a fresh recast must not draw nearly-done under the old action's 300s denominator"
      )
    end)

    it("re-shows the dynamic prims when a bar is re-held", function()
      -- Release and re-hold ride refresh() alone - never repaint - so the
      -- change-gate cache must be dropped with the blanking, or the second
      -- hold finds "already shown" in the cache and draws nothing.
      build_world()
      widget.set_pos(400, 100, "wxhb_left")
      env.ability_recasts = { [5] = 30 }
      press(LEFT)
      press(LAYER)
      widget.update()
      local recast = text_of("wxhb_left", 1, "recast")
      local sweep = image_of("wxhb_left", 1, "sweep")
      assert.is_true(recast.visible)
      assert.is_true(sweep.visible)
      release(LAYER)
      assert.is_false(recast.visible, "the bar dropped with the layer")
      press(LAYER)
      env.now = 0.3
      widget.update()
      assert.is_true(recast.visible, "the second hold draws the recast again")
      assert.is_true(sweep.visible)
    end)

    it("blanks the dynamic prims on hide and on detach", function()
      build_world()
      env.spell_recasts = { [1] = 1800 }
      widget.update()
      local cost = text_of("xhb_left", 5, "cost")
      local sweep = image_of("xhb_left", 5, "sweep")
      assert.is_true(cost.visible)
      assert.is_true(sweep.visible)
      widget.hide()
      assert.is_false(cost.visible)
      assert.is_false(sweep.visible)
      widget.show()
      widget.update()
      assert.is_true(sweep.visible, "the tick brings them back")
      widget.detach()
      assert.is_false(cost.visible)
      assert.is_false(sweep.visible)
    end)

    it("sweeps an ability recast and clears at zero", function()
      build_world()
      local sweep = image_of("xhb_left", 4, "sweep")
      local recast = text_of("xhb_left", 4, "recast")
      env.ability_recasts = { [5] = 30 }
      widget.update()
      assert.is_true(sweep.visible)
      assert.are.equal(150, sweep.last.alpha, "upstream's fixed overlay alpha")
      assert.are.equal("addon/components/crossbar/assets/cooldown/frame_32.png", sweep.last.path)
      assert.are.equal("30s", recast.last.text)
      assert.is_true(recast.visible)
      env.now = 0.3
      env.ability_recasts = { [5] = 15 }
      widget.update()
      assert.are.equal("addon/components/crossbar/assets/cooldown/frame_16.png", sweep.last.path)
      env.now = 0.6
      env.ability_recasts = {}
      widget.update()
      assert.is_false(sweep.visible)
      assert.is_false(recast.visible)
    end)

    it("labels the recast boundaries exactly", function()
      build_world()
      -- 3570 sixtieths = 59.5s: the seconds branch rounds UP.
      env.spell_recasts = { [1] = 3570 }
      widget.update()
      local label = text_of("xhb_left", 5, "recast")
      assert.are.equal("60s", label.last.text, "seconds ceil, not floor")
      env.now = 0.3
      env.spell_recasts = { [1] = 3600 }
      widget.update()
      assert.are.equal("1m", label.last.text, "60s exactly is a minute")
      env.now = 0.6
      env.spell_recasts = { [1] = 3660 }
      widget.update()
      assert.are.equal("1m", label.last.text)
      env.now = 0.9
      env.spell_recasts = {}
      env.ability_recasts = { [5] = 3599 }
      widget.update()
      assert.are.equal("59m", text_of("xhb_left", 4, "recast").last.text)
      env.now = 1.2
      env.ability_recasts = { [5] = 3600 }
      widget.update()
      assert.are.equal("1h", text_of("xhb_left", 4, "recast").last.text, "3600s exactly is an hour")
    end)

    it("labels minutes and hours on long recasts", function()
      build_world()
      env.ability_recasts = { [5] = 300 }
      widget.update()
      assert.are.equal("5m", text_of("xhb_left", 4, "recast").last.text)
      env.now = 0.3
      env.ability_recasts = { [5] = 7200 }
      widget.update()
      assert.are.equal("2h", text_of("xhb_left", 4, "recast").last.text)
    end)

    it("reads spell recasts in sixtieths and dims the slot while cooling", function()
      build_world()
      local icon = image_of("xhb_left", 5, "icon")
      env.spell_recasts = { [1] = 1800 }
      widget.update()
      assert.are.equal("30s", text_of("xhb_left", 5, "recast").last.text)
      assert.are.equal(config.disabled_alpha, icon.last.alpha, "a cooling slot dims")
      env.now = 0.3
      env.spell_recasts = {}
      widget.update()
      assert.are.equal(255, icon.last.alpha)
    end)

    it("prices a spell and dims it when unaffordable", function()
      build_world()
      widget.update()
      local cost = text_of("xhb_left", 5, "cost")
      assert.are.equal("8", cost.last.text)
      assert.are.same({ 230, 91, 151 }, cost.last.color)
      assert.is_true(cost.visible)
      assert.are.equal(255, image_of("xhb_left", 5, "icon").last.alpha)
      env.now = 0.3
      env.player.vitals.mp = 5
      widget.update()
      assert.are.equal(config.disabled_alpha, image_of("xhb_left", 5, "icon").last.alpha)
    end)

    it("counts stratagems in the cost corner on RDM/SCH", function()
      local files = war_bindings()
      files.RDM = { sets = { [1] = { left = { [1] = { type = "ja", action = "Penury", target = "me" } } } } }
      local player = war_player()
      player.main_job = "RDM"
      player.main_job_id = 5
      player.sub_job = "SCH"
      player.sub_job_level = 52
      build_world({
        store_files = files,
        player = player,
        tune_config = function(tuned)
          -- A non-white base text colour, so the white assertion below can
          -- only pass if the counter sets its colour explicitly.
          tuned.text_color = { a = 255, r = 10, g = 20, b = 30 }
        end,
      })
      env.ability_recasts = { [231] = 0 }
      widget.update()
      assert.are.equal("3", text_of("xhb_left", 1, "cost").last.text)
      assert.are.same({ 255, 255, 255 }, text_of("xhb_left", 1, "cost").last.color, "explicit white, never inherited")
      env.now = 0.3
      env.ability_recasts = { [231] = 100 }
      widget.update()
      assert.are.equal("1", text_of("xhb_left", 1, "cost").last.text, "ceil(100/80) = 2 of 3 spent")
    end)

    it("counts ninja tools with the master colours", function()
      local files = { NIN = { sets = { [1] = { left = { [1] = { type = "ma", action = "Utsusemi: Ichi" } } } } } }
      local player = war_player()
      player.main_job = "NIN"
      player.main_job_id = 13
      player.sub_job = "WAR"
      build_world({ store_files = files, player = player })
      env.items[0] = { { id = 1179, count = 10, slot = 1 }, { id = 2972, count = 45, slot = 2 } }
      widget.update()
      local cost = text_of("xhb_left", 1, "cost")
      assert.are.equal("55", cost.last.text, "master tools count on main NIN")
      assert.are.same({ 255, 255, 0 }, cost.last.color, "only the total clears 50")
      -- A count is not a cost: hide.cost leaves it visible.
      config.hide.cost = true
      env.now = 0.3
      widget.update()
      assert.is_true(cost.visible, "the tool count survives hide.cost")
    end)

    it("recounts tools when an item event names one", function()
      local files = { NIN = { sets = { [1] = { left = { [1] = { type = "ma", action = "Utsusemi: Ichi" } } } } } }
      local player = war_player()
      player.main_job = "NIN"
      build_world({ store_files = files, player = player })
      env.items[0] = { { id = 1179, count = 10, slot = 1 } }
      widget.update()
      assert.are.equal("10", text_of("xhb_left", 1, "cost").last.text)
      env.items[0] = {}
      widget.update()
      assert.are.equal("10", text_of("xhb_left", 1, "cost").last.text, "no event, no re-read")
      widget.update("remove item", 1179)
      widget.update()
      assert.are.equal("0", text_of("xhb_left", 1, "cost").last.text)
    end)

    it("counts Quick Draw cards on a COR main and nothing without COR", function()
      local files =
        { COR = { sets = { [1] = { left = { [1] = { type = "ja", action = "Fire Shot", target = "t" } } } } } }
      local player = war_player()
      player.main_job = "COR"
      player.main_job_id = 17
      build_world({ store_files = files, player = player })
      env.items[0] = { { id = 2176, count = 3, slot = 1 }, { id = 2974, count = 10, slot = 2 } }
      widget.update()
      assert.are.equal("13", text_of("xhb_left", 1, "cost").last.text, "Trump Card rides the same machinery")
      -- The same slot without COR anywhere on the pair: no count, no X.
      files = { WAR = { sets = { [1] = { left = { [1] = { type = "ja", action = "Fire Shot", target = "t" } } } } } }
      build_world({ store_files = files })
      env.items[0] = { { id = 2176, count = 3, slot = 1 } }
      widget.update()
      assert.is_false(text_of("xhb_left", 1, "cost").visible)
      assert.is_false(image_of("xhb_left", 1, "sweep").visible, "no red X either")
    end)

    it("draws no tool count on a job without the school", function()
      -- The fork's own gate (ui.lua:1057/1102): a shared Utsusemi slot
      -- viewed on WHM/BLM draws no count and no red X.
      local files = { WHM = { sets = { [1] = { left = { [1] = { type = "ma", action = "Utsusemi: Ichi" } } } } } }
      local player = war_player()
      player.main_job = "WHM"
      player.sub_job = "BLM"
      build_world({ store_files = files, player = player })
      widget.update()
      assert.is_false(text_of("xhb_left", 1, "cost").visible)
      assert.is_false(image_of("xhb_left", 1, "sweep").visible, "no red X either")
    end)

    it("ignores item events for items no tool cares about", function()
      local files = { NIN = { sets = { [1] = { left = { [1] = { type = "ma", action = "Utsusemi: Ichi" } } } } } }
      local player = war_player()
      player.main_job = "NIN"
      build_world({ store_files = files, player = player })
      widget.update()
      local reads = env.item_reads
      widget.update("add item", 4165)
      widget.update()
      assert.are.equal(reads, env.item_reads, "an untracked item is no reason to re-read the bag")
      widget.update("remove item", 1179)
      widget.update()
      --[[ Exact, not merely "more": the read budget is the point of the
           gate. ONE bag per recount here - nothing is bound to an item id,
           so the temporary bag has nothing it could answer for and is not
           read at all. A binding that did name one would cost a second. ]]
      assert.are.equal(reads + 1, env.item_reads, "a tracked one is")
    end)

    it("crosses out a slot whose tool count is zero", function()
      local files = { NIN = { sets = { [1] = { left = { [1] = { type = "ma", action = "Utsusemi: Ichi" } } } } } }
      local player = war_player()
      player.main_job = "NIN"
      build_world({ store_files = files, player = player })
      widget.update()
      local cost = text_of("xhb_left", 1, "cost")
      assert.are.equal("0", cost.last.text)
      assert.are.same({ 255, 0, 0 }, cost.last.color)
      local sweep = image_of("xhb_left", 1, "sweep")
      assert.is_true(sweep.visible)
      assert.are.equal("addon/components/crossbar/assets/red-x.png", sweep.last.path)
      assert.is_false(text_of("xhb_left", 1, "recast").visible, "the recast text hides under the X")
    end)

    it("counts what an item slot is bound to, in plain white", function()
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.items[0] = { { id = 4165, count = 7, slot = 1 } }
      widget.update()
      local cost = text_of("xhb_left", 6, "cost")
      assert.are.equal("7", cost.last.text)
      assert.are.same({ 255, 255, 255 }, cost.last.color, "no bands - there is no defined low for a consumable")
    end)

    it("crosses out an item slot the bag can no longer supply", function()
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.items[0] = {}
      widget.update()
      assert.are.equal("0", text_of("xhb_left", 6, "cost").last.text)
      assert.is_true(image_of("xhb_left", 6, "sweep").visible, "the red X, the same one a spent tool raises")
    end)

    it("counts an item the moment it is bound, without waiting for an inventory event", function()
      -- The count is read for the ids some painted slot holds, so binding
      -- one changes what has to be counted. Without this the new slot reads
      -- 0, crosses itself out and dims until something unrelated moves.
      build_world({ store_files = war_bindings() })
      env.items[0] = { { id = 4165, count = 7, slot = 1 } }
      widget.update()
      widget.handle_command({ "bind", "1L6", "item", "Prism Powder", "me" })
      widget.update()
      assert.are.equal("7", text_of("xhb_left", 6, "cost").last.text)
      assert.is_false(image_of("xhb_left", 6, "sweep").visible, "no red X on an item we are holding")
    end)

    it("counts enchanted gear sitting in a wardrobe, not inventory alone", function()
      -- enchanteditem resolves out of every equippable bag, so a count that
      -- read bag 0 alone would cross out a slot whose press works.
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "enchanteditem", action = "Vocation Ring" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true }
      env.items[8] = { enabled = true, { id = 27546, slot = 2, status = 0, count = 1 } }
      widget.update()
      assert.are.equal("1", text_of("xhb_left", 6, "cost").last.text)
      assert.is_false(image_of("xhb_left", 6, "sweep").visible)
    end)

    it("re-reads the bags only when a repaint changes WHICH ids are bound", function()
      -- A repaint is the event that can invalidate the counts, but most of
      -- them do not: a hold state, a set switch, a context flip. Binding a
      -- spell repaints and changes nothing worth counting; binding an item
      -- changes it.
      build_world({ store_files = war_bindings() })
      env.items[0] = { { id = 4165, count = 7, slot = 1 } }
      widget.update()
      local reads = env.item_reads
      widget.handle_command({ "bind", "1L5", "ma", "Cure", "me" })
      widget.update()
      assert.are.equal(reads, env.item_reads, "a spell is not something to count")
      widget.handle_command({ "bind", "1L6", "item", "Prism Powder", "me" })
      widget.update()
      assert.is_true(env.item_reads > reads, "an item is")
      assert.are.equal("7", text_of("xhb_left", 6, "cost").last.text)
    end)

    it("re-counts when a slot changes from item to enchanteditem on the same id", function()
      --[[ The id does not move, but where it is counted FROM does: an
           `item` counts out of the inventory alone, gear out of every
           equippable bag. Without the type in the signature the recount
           never runs, and the slot keeps the count the old type gave it -
           here a red-crossed 0 on a ring the press uses perfectly. ]]
      build_world({ store_files = war_bindings() })
      env.items[0] = { enabled = true }
      env.items[8] = { enabled = true, { id = 27546, slot = 2, status = 0, count = 1 } }
      widget.handle_command({ "bind", "1L6", "item", "Vocation Ring" })
      widget.update()
      assert.are.equal("0", text_of("xhb_left", 6, "cost").last.text, "an item is not reachable in a wardrobe")
      widget.handle_command({ "bind", "1L6", "enchanteditem", "Vocation Ring" })
      widget.update()
      assert.are.equal("1", text_of("xhb_left", 6, "cost").last.text, "gear is")
    end)

    it("follows the set it names", function()
      -- The label exists so a set switch is visible on a bar with nothing
      -- bound to it, which is the state it was found missing in.
      build_world()
      local label = prims.texts[#prims.texts]
      assert.are.equal("Set 1", label.last.text)
      widget.handle_command({ "set", "5" })
      widget.update()
      assert.are.equal("Set 5", label.last.text)
    end)

    it("counts a temporary item out of the bag it actually lives in", function()
      --[[ Whatever the client reports in that bag - the item here is one
           of the fixture's consumables, and the test asserts nothing about
           which items are really temporary (Instant Warp, the obvious
           guess, is an ordinary inventory item). Counting bag 0 alone drew
           a red X and dimmed the icon on a slot whose press works, which is
           worse than the blank corner these slots had before counts
           existed. The bag is found by NAME out of the resources, the way
           travel.lua resolves the resting status, not by a remembered
           id. ]]
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true }
      env.items[3] = { enabled = true, { id = 4165, slot = 1, count = 2 } }
      widget.update()
      assert.are.equal("2", text_of("xhb_left", 6, "cost").last.text)
      assert.is_false(image_of("xhb_left", 6, "sweep").visible, "no red X on a working binding")
    end)

    it("does not cross out an item slot when no temporary bag was found", function()
      --[[ The bag is matched on a resource name nothing in this repo has
           read. If the match fails, a plain item's zero might just be a copy
           we never looked at - so the corner shows the number and withholds
           the red X. A missing warning beats a false one over a press that
           works. ]]
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files, no_temporary_bag = true })
      env.items[0] = { enabled = true }
      widget.update()
      assert.are.equal("0", text_of("xhb_left", 6, "cost").last.text, "the count is still honest")
      assert.is_false(image_of("xhb_left", 6, "sweep").visible, "but it does not claim to know")
    end)

    it("counts one id bound both ways by each slot's own rule", function()
      -- The two types count from different places, so one shared number
      -- would have to be wrong for one of the slots. A cudgel in a wardrobe
      -- is reachable as gear and not as an item.
      local files = war_bindings()
      files.WAR.sets[1].left[5] = { type = "item", action = "Warp Cudgel" }
      files.WAR.sets[1].left[6] = { type = "enchanteditem", action = "Warp Cudgel" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true }
      env.items[8] = { enabled = true, { id = 17040, slot = 2, status = 0, count = 1 } }
      widget.update()
      assert.are.equal("0", text_of("xhb_left", 5, "cost").last.text, "not usable as an item from there")
      assert.are.equal("1", text_of("xhb_left", 6, "cost").last.text, "but usable as gear")
    end)

    it("does not count gear in a bag the client has disabled", function()
      -- The press refuses a copy it cannot reach, so counting it would
      -- promise exactly the press that cannot fire.
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "enchanteditem", action = "Vocation Ring" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true }
      env.items[8] = { enabled = false, { id = 27546, slot = 2, status = 0, count = 1 } }
      widget.update()
      assert.are.equal("0", text_of("xhb_left", 6, "cost").last.text)
    end)

    it("keeps a consumable's count to the inventory, which is the only bag it can be used from", function()
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true }
      env.items[8] = { enabled = true, { id = 4165, slot = 2, count = 12 } }
      widget.update()
      assert.are.equal("0", text_of("xhb_left", 6, "cost").last.text, "a powder in a wardrobe is not usable")
    end)

    it("re-reads the bag for an item event naming something a slot is bound to", function()
      -- The tool gate alone would ignore Prism Powder; a bound item id joins
      -- the tracked set, and an id nothing is bound to still does not.
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.items[0] = { { id = 4165, count = 7, slot = 1 } }
      widget.update()
      local reads = env.item_reads
      widget.update("add item", 999)
      widget.update()
      assert.are.equal(reads, env.item_reads, "nothing is bound to 999")
      env.items[0] = { { id = 4165, count = 2, slot = 1 } }
      widget.update("remove item", 4165)
      widget.update()
      assert.is_true(env.item_reads > reads, "the recount ran")
      assert.are.equal("2", text_of("xhb_left", 6, "cost").last.text)
    end)

    it("recounts a stack the inventory packet shrank without emptying", function()
      --[[ Using one of five fires no `remove item`: that event is the item
           leaving the bag, and four are still in it. The count only moved
           when the stack emptied (Kevin, live client, 2026-08-22). The
           decrement rides `0x01E` Modify Inventory instead, which carries
           Count/Bag/Index and NO item id - so the packet cannot be gated on
           the bound ids the way the events are. ]]
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.items[0] = { { id = 4165, count = 5, slot = 1 } }
      widget.update()
      assert.are.equal("5", text_of("xhb_left", 6, "cost").last.text)
      env.items[0] = { { id = 4165, count = 4, slot = 1 } }
      widget.update()
      assert.are.equal("5", text_of("xhb_left", 6, "cost").last.text, "no packet, no re-read")
      widget.update("chunk", 0x01E, "raw inventory bytes")
      widget.update()
      assert.are.equal("4", text_of("xhb_left", 6, "cost").last.text)
    end)

    it("recounts a tool stack off the same packet", function()
      -- Casting Utsusemi burns one tool out of a stack, which is the same
      -- shape: no event, and the count is drawn from the spell rather than
      -- from a bound item id.
      local files = { NIN = { sets = { [1] = { left = { [1] = { type = "ma", action = "Utsusemi: Ichi" } } } } } }
      local player = war_player()
      player.main_job = "NIN"
      build_world({ store_files = files, player = player })
      env.items[0] = { { id = 1179, count = 10, slot = 1 } }
      widget.update()
      assert.are.equal("10", text_of("xhb_left", 1, "cost").last.text)
      env.items[0] = { { id = 1179, count = 9, slot = 1 } }
      widget.update("chunk", 0x01E, "raw inventory bytes")
      widget.update()
      assert.are.equal("9", text_of("xhb_left", 1, "cost").last.text)
    end)

    it("does not re-read the bag for an inventory packet when nothing is counted", function()
      --[[ The read budget is the whole reason the events are gated, and the
           packet arrives far more often than they do - every equip status
           change is one. A bar drawing no count has nothing to refresh. ]]
      build_world()
      widget.update()
      local reads = env.item_reads
      widget.update("chunk", 0x01E, "raw inventory bytes")
      widget.update()
      assert.are.equal(reads, env.item_reads)
    end)

    it("extracts an item icon through the cache and repaints", function()
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.files["addon/components/crossbar/assets/icons/usable-item.png"] = true
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      local icon = image_of("xhb_left", 6, "icon")
      assert.are.equal("addon/components/crossbar/assets/icons/usable-item.png", icon.last.path, "fallback first")
      widget.update()
      assert.are.equal("icons/4165.bmp", env.writes[1], "one extraction, queued off the packet path")
      assert.are.equal("addon/icons/4165.bmp", icon.last.path, "the cache landing repaints the slot")
    end)

    it("re-stats nothing on a settled repaint", function()
      -- The icon path re-resolves only when the record changes - the same
      -- identity rule the sweep uses.
      build_world()
      env.files["addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png"] = true
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      env.stats = {}
      widget.handle_command({ "set", "1" })
      for _, path in ipairs(env.stats) do
        assert.is_nil(path:find("savage%-blade"), "a settled slot must not be re-stat'd: " .. path)
      end
    end)

    it("ignores an empty game_path override", function()
      -- equipviewer ships game_path = "" as its override idiom; copied into
      -- this component's config it must fall through to the client's
      -- answer, not silently abandon every item icon for the session.
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({
        store_files = files,
        tune_config = function(tuned)
          tuned.game_path = ""
        end,
      })
      widget.update()
      assert.are.equal(1, #env.dat_paths)
      assert.is_not_nil(env.dat_paths[1]:find("C:/FFXI/", 1, true), "read: " .. env.dat_paths[1])
    end)

    it("stops re-stat'ing an item the cache has given up on", function()
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.dat_fails = true
      env.files["addon/components/crossbar/assets/icons/usable-item.png"] = true
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      widget.update()
      widget.handle_command({ "set", "1" })
      env.stats = {}
      widget.handle_command({ "set", "1" })
      for _, path in ipairs(env.stats) do
        assert.is_nil(path:find("4165"), "an abandoned item must not be re-stat'd: " .. path)
        assert.is_nil(path:find("prism"), "nor its named candidates: " .. path)
      end
    end)

    it("repaints only the unresolved item slots when an icon lands", function()
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "item", action = "Prism Powder", target = "me" }
      build_world({ store_files = files })
      env.files["addon/components/crossbar/assets/icons/usable-item.png"] = true
      env.files["addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png"] = true
      widget.attach(config, function() end, store)
      widget.set_pos(100, 900, "main")
      widget.show()
      env.stats = {}
      widget.update()
      assert.are.equal("addon/icons/4165.bmp", image_of("xhb_left", 6, "icon").last.path)
      for _, path in ipairs(env.stats) do
        assert.is_nil(path:find("savage%-blade"), "a settled slot must not be re-stat'd: " .. path)
      end
    end)
  end)

  describe("skillchain", function()
    -- A raw parse_action-shaped weapon-skill finish: the plain damage
    -- message, no add effect. The fixture's parse_action is identity, so
    -- these ride the ordinary chunk dispatch as 0x028.
    local function ws_act(ws_id, opts)
      opts = opts or {}
      return {
        category = 3,
        param = ws_id,
        actor_id = opts.actor or 1234,
        targets = {
          {
            id = opts.target or 99,
            actions = { { message = opts.message or 185, param = opts.action_param } },
          },
        },
      }
    end

    -- The dispatch's shape: the raw bytes, and the action already parsed out
    -- of them.
    local function open_chain(ws_id)
      widget.update("chunk", 0x028, "raw action bytes", ws_act(ws_id))
    end

    before_each(function()
      build_world()
      env.target = { id = 99, hpp = 75 }
      widget.set_pos(1000, 500, "indicator")
    end)

    describe("the indicator", function()
      --[[ The action packet is decoded once, in the entry point's chunk
           dispatch, and handed down as the fourth argument -- this engine and
           targetbar's cast bar used to parse it one apiece. So the widget is
           given an action, never a parser: the raw bytes beside it are bytes,
           and nothing in this fixture could decode them. ]]
      it("opens a chain from the action the dispatch already parsed", function()
        local _, fill = indicator_prims()
        widget.update("chunk", 0x028, "raw action bytes", ws_act(8))
        env.now = 1.5
        widget.update()
        assert.is_true(fill.visible)
      end)

      it("tracks a chain: red and thin while waiting, green and thick while open, then gone", function()
        local bg, fill = indicator_prims()
        open_chain(8) -- Dragon Kick: Fragmentation, 3s delay
        env.now = 1.5
        widget.update()
        assert.is_true(fill.visible)
        assert.is_true(bg.visible)
        assert.are.same({ 237, 28, 36 }, fill.last.color, "the waiting colour")
        assert.are.equal(220, fill.last.alpha)
        -- Waiting at fraction 0.5: 300 wide, grown out of the centre.
        assert.are.same({ 1152, 505, 300, 4 }, { fill.x, fill.y, fill.width, fill.height })
        assert.are.same({ 1150, 503, 304, 8 }, { bg.x, bg.y, bg.width, bg.height })
        assert.are.same({ 0, 0, 0 }, bg.last.color)
        assert.are.equal(150, bg.last.alpha)
        -- Open at 4s: window 6 of 7 remains.
        env.now = 4
        widget.update()
        assert.are.same({ 15, 205, 5 }, fill.last.color, "the open colour")
        assert.are.same({ 1045, 502, 514, 10 }, { fill.x, fill.y, fill.width, fill.height })
        assert.are.same({ 1043, 500, 518, 14 }, { bg.x, bg.y, bg.width, bg.height })
        -- Expired.
        env.now = 12
        widget.update()
        assert.is_false(fill.visible)
        assert.is_false(bg.visible)
      end)

      it("leaves the hidden indicator alone on every refresh after the first", function()
        -- refresh() takes the indicator down with the widget, and core runs a
        -- refresh per mouse move of a layout-mode drag; the second one has
        -- nothing to say.
        local bg, fill = indicator_prims()
        open_chain(8)
        env.now = 1.5
        widget.update()
        widget.hide()
        local settled = #bg.calls + #fill.calls
        widget.set_preview(true)
        widget.set_preview(false)
        assert.are.equal(settled, #bg.calls + #fill.calls, "a hidden indicator costs nothing to keep hidden")
        assert.is_false(fill.visible)
      end)

      it("comes back against an origin that moved while it was hidden", function()
        -- The indicator has no resting geometry - the tick draws it from the
        -- live plan - so the anchor moving under a hidden indicator must not
        -- leave the change-gate cache pointing at the old origin.
        local _, fill = indicator_prims()
        open_chain(8)
        env.now = 1.5
        widget.update()
        widget.hide()
        widget.set_pos(1200, 700, "indicator")
        widget.show()
        widget.update()
        assert.is_true(fill.visible)
        assert.are.same({ 1200 + 152, 700 + 5 }, { fill.x, fill.y })
      end)

      it("scales with its own anchor", function()
        widget.set_scale(2, "indicator")
        local _, fill = indicator_prims()
        open_chain(8)
        env.now = 1.5
        widget.update()
        assert.are.same({ 1000 + 152 * 2, 500 + 5 * 2, 600, 8 }, { fill.x, fill.y, fill.width, fill.height })
      end)

      it("stays down with no target or a dead one", function()
        local bg, fill = indicator_prims()
        open_chain(8)
        env.now = 1.5
        env.target = nil
        widget.update()
        assert.is_false(fill.visible)
        env.target = { id = 99, hpp = 0 }
        widget.update()
        assert.is_false(fill.visible)
        assert.is_false(bg.visible)
      end)

      it("obeys the skillchain.indicator config switch", function()
        build_world({
          tune_config = function(tuned)
            tuned.skillchain.indicator = false
          end,
        })
        env.target = { id = 99, hpp = 75 }
        widget.set_pos(1000, 500, "indicator")
        local bg, fill = indicator_prims()
        open_chain(8)
        env.now = 1.5
        widget.update()
        assert.is_false(fill.visible)
        assert.is_false(bg.visible)
      end)

      it("survives a hand-broken skillchain block on the shipped colours", function()
        -- The duplicate constants ARE the fallback path (render.lua's own
        -- MP/TP colour pattern): a garbage config block degrades to the
        -- shipped waiting colour and opacity, never a crash or a bare bar.
        build_world({
          tune_config = function(tuned)
            tuned.skillchain = "garbage"
          end,
        })
        env.target = { id = 99, hpp = 75 }
        widget.set_pos(1000, 500, "indicator")
        local _, fill = indicator_prims()
        open_chain(8)
        env.now = 1.5
        widget.update()
        assert.is_true(fill.visible)
        assert.are.same({ 237, 28, 36 }, fill.last.color)
        assert.are.equal(220, fill.last.alpha)
      end)

      it("goes down with hide() and does not linger past detach", function()
        local bg, fill = indicator_prims()
        open_chain(8)
        env.now = 1.5
        widget.update()
        assert.is_true(fill.visible)
        widget.hide()
        assert.is_false(fill.visible)
        assert.is_false(bg.visible)
        widget.show()
        widget.update()
        assert.is_true(fill.visible, "back with the widget")
        widget.detach()
        assert.is_false(fill.visible)
        -- The chain state went with the detach: the same clock shows nothing.
        widget.attach(config, function() end, store)
        widget.show()
        widget.update()
        assert.is_false(fill.visible)
      end)

      it("previews its footprint for layout placement", function()
        local bg, fill = indicator_prims()
        widget.set_preview(true)
        widget.update()
        assert.is_true(fill.visible)
        assert.is_true(bg.visible)
        assert.are.same({ 1000, 500, 604, 14 }, { bg.x, bg.y, bg.width, bg.height })
        widget.set_preview(false)
        widget.update()
        assert.is_false(fill.visible)
      end)
    end)

    describe("the per-slot chain results", function()
      it("swaps a chaining WS slot to its result icon with the frame animation", function()
        -- Asuran Fists opens Gravitation/Liquefaction; the bound Savage
        -- Blade (Fragmentation, Scission) would continue to Fragmentation.
        open_chain(9)
        env.now = 4
        widget.update()
        local chain = image_of("xhb_left", 3, "chain")
        assert.is_true(chain.visible)
        assert.are.equal("addon/components/crossbar/assets/icons/skillchain/fragmentation.png", chain.last.path)
        assert.are.equal(255, chain.last.alpha, "full TP: undimmed")
        assert.are.equal("addon/components/crossbar/assets/frame_step1.png", image_of("xhb_left", 3, "frame").last.path)
        assert.is_false(image_of("xhb_left", 3, "icon").visible, "the action icon hides under the result")
        assert.is_false(text_of("xhb_left", 3, "cost").visible, "at full TP the cost hides too")
        -- The border animation steps every five ticks.
        for _ = 1, 5 do
          widget.update()
        end
        assert.are.equal("addon/components/crossbar/assets/frame_step2.png", image_of("xhb_left", 3, "frame").last.path)
        -- A slot whose action forms nothing stays put: Cure is a spell.
        assert.is_false(image_of("xhb_left", 5, "chain").visible)
      end)

      it("keeps the action icon down through a mid-chain refresh", function()
        -- The cache-poisoning path: refresh() shows/hides the icon directly,
        -- so if it ignored the chain state it would resurrect the icon and
        -- the tick's want() cache - which already believes it pushed hidden -
        -- would never push it back down. An activation (held side key) runs
        -- exactly such a refresh.
        env.files["addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png"] = true
        widget.attach(config, function() end, store)
        widget.show()
        open_chain(9)
        env.now = 4
        widget.update()
        local icon = image_of("xhb_left", 3, "icon")
        assert.is_true(image_of("xhb_left", 3, "chain").visible)
        assert.is_false(icon.visible)
        widget.on_keyboard(39, true, 0, false)
        -- Asserted BEFORE the next tick, which is the only frame in which
        -- the bug is visible: the tick re-pushes the right answer, so a
        -- check after it passes with or without refresh's chain term.
        assert.is_false(icon.visible, "not even for the one frame between the refresh and the tick")
        widget.update()
        assert.is_false(icon.visible, "refresh must not resurrect the icon under the chain result")
        widget.on_keyboard(39, false, 0, false)
        assert.is_false(icon.visible, "and the release runs a refresh of its own")
        -- Layout mode's per-move refreshes run the same predicate.
        widget.set_preview(true)
        assert.is_false(icon.visible, "so does the preview flip")
      end)

      it("takes the chain overlay down the moment the slot is rebound", function()
        -- A set switch mid-window repaints the slot: its record changes, so
        -- the chain result computed for the OLD action is void. Clearing
        -- only the state leaves the prim drawing the dead property until
        -- the next tick - a stale chain peeking out from under (or, on an
        -- emptied slot, over) whatever is there now.
        open_chain(9)
        env.now = 4
        widget.update()
        local chain = image_of("xhb_left", 3, "chain")
        assert.is_true(chain.visible)
        -- Set 2 has nothing in slot 3.
        widget.handle_command({ "set", "2" })
        assert.is_false(chain.visible, "the rebound slot must not keep the old chain icon")
      end)

      it("restores the slot when the window closes", function()
        -- The real icon exists on disk so the restore has something to show.
        env.files["addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png"] = true
        widget.update("job change")
        open_chain(9)
        env.now = 4
        widget.update()
        assert.is_true(image_of("xhb_left", 3, "chain").visible)
        env.now = 15
        widget.update()
        local chain = image_of("xhb_left", 3, "chain")
        assert.is_false(chain.visible)
        assert.are.equal("addon/components/crossbar/assets/frame.png", image_of("xhb_left", 3, "frame").last.path)
        assert.are.equal(255, image_of("xhb_left", 3, "frame").last.alpha)
        assert.is_true(image_of("xhb_left", 3, "icon").visible, "the action icon comes back")
      end)

      it("re-shows the action icon, never a hole, when the bar comes back mid-window", function()
        -- Hiding blanks the chain overlay and wipes the write cache, so a
        -- stale chain_prop would leave the re-shown slot with NEITHER icon
        -- nor chain until the tick catches up - a one-frame hole. The
        -- hidden branch must drop the chain state with the prims.
        env.files["addon/components/crossbar/assets/icons/weaponskills/sword/savage-blade.png"] = true
        widget.attach(config, function() end, store)
        widget.show()
        open_chain(9)
        env.now = 4
        widget.update()
        assert.is_true(image_of("xhb_left", 3, "chain").visible)
        widget.hide()
        widget.show()
        -- Before any tick: the action icon is back; the next tick may swap
        -- it out again, but the slot is never empty.
        assert.is_true(image_of("xhb_left", 3, "icon").visible)
        assert.is_false(image_of("xhb_left", 3, "chain").visible)
        widget.update()
        assert.is_false(image_of("xhb_left", 3, "icon").visible, "the tick re-swaps to the result")
        assert.is_true(image_of("xhb_left", 3, "chain").visible)
      end)

      it("dims a WS result while TP is short, and keeps the cost up", function()
        env.player.vitals.tp = 900
        open_chain(9)
        env.now = 4
        widget.update()
        assert.are.equal(75, image_of("xhb_left", 3, "chain").last.alpha)
        assert.are.equal(150, image_of("xhb_left", 3, "frame").last.alpha)
        assert.is_true(text_of("xhb_left", 3, "cost").visible, "1000 TP is still owed")
      end)

      it("lights a Ready move's JA slot by its ability id, not its recast id", function()
        -- Sudden Lunge rides the shared Ready recast (102); the chain table
        -- is keyed by its ability id (736). The recast id can never match -
        -- the reference fork's own bug, fixed here as a documented deviation.
        local with_ja = war_bindings()
        with_ja.WAR.sets[1].left[6] = { type = "ja", action = "Sudden Lunge", target = "t" }
        build_world({ store_files = with_ja })
        env.target = { id = 99, hpp = 75 }
        -- Tornado Kick opens Induration/Detonation/Impaction; Sudden Lunge
        -- (Impaction) continues the Induration leg to Impaction.
        open_chain(13)
        env.now = 4
        widget.update()
        local chain = image_of("xhb_left", 6, "chain")
        assert.is_true(chain.visible)
        assert.are.equal("addon/components/crossbar/assets/icons/skillchain/impaction.png", chain.last.path)
      end)

      it("lights a blood pact's pet slot, never TP-dimmed", function()
        local with_pet = war_bindings()
        with_pet.WAR.sets[1].left[6] = { type = "pet", action = "Eclipse Bite", target = "t" }
        build_world({ store_files = with_pet })
        env.target = { id = 99, hpp = 75 }
        env.player.vitals.tp = 0
        -- Tornado Kick opens Induration/Detonation/Impaction; Eclipse Bite
        -- (Gravitation, Scission) continues the Detonation leg to Scission.
        open_chain(13)
        env.now = 4
        widget.update()
        local chain = image_of("xhb_left", 6, "chain")
        assert.is_true(chain.visible)
        assert.are.equal("addon/components/crossbar/assets/icons/skillchain/scission.png", chain.last.path)
        assert.are.equal(255, chain.last.alpha, "no TP gate off the ws type")
      end)

      it("honours hide.skillchain_icon without touching the indicator", function()
        build_world({
          tune_config = function(tuned)
            tuned.hide.skillchain_icon = true
          end,
        })
        env.target = { id = 99, hpp = 75 }
        widget.set_pos(1000, 500, "indicator")
        open_chain(9)
        env.now = 4
        widget.update()
        assert.is_false(image_of("xhb_left", 3, "chain").visible)
        local _, fill = indicator_prims()
        assert.is_true(fill.visible)
      end)
    end)

    describe("the buff and zone chunks", function()
      local function u16le(v)
        return string.char(v % 256, math.floor(v / 256) % 256)
      end

      local function buff_refresh(buff_id)
        local body = "HDRX" .. string.char(9) .. "\0\0\0"
        for n = 1, 32 do
          body = body .. u16le(n == 1 and buff_id or 0)
        end
        return body
      end

      it("reads the target from the client once per tick, never once per slot", function()
        open_chain(9)
        env.now = 4
        widget.update()
        env.target_reads = 0
        for _ = 1, 5 do
          widget.update()
        end
        -- The contract: ONE get_mob_by_target per tick (targetbar's "the
        -- target itself is read per frame" precedent; fresher than the
        -- 200ms cache so a target switch drops the indicator the same
        -- frame) - shared by the window and every per-slot result, never
        -- one read per result-capable slot.
        assert.are.equal(5, env.target_reads)
      end)

      it("feeds 0x63 through: a spell under Immanence opens the indicator", function()
        local _, fill = indicator_prims()
        widget.update("chunk", 0x63, buff_refresh(470))
        widget.update("chunk", 0x028, "raw action bytes", {
          category = 4,
          param = 144,
          actor_id = 777,
          targets = { { id = 99, actions = { { message = 2 } } } },
        })
        env.now = 1.5
        widget.update()
        assert.is_true(fill.visible)
      end)

      it("feeds the zone-out through: 0x0B drops the chain", function()
        local _, fill = indicator_prims()
        open_chain(8)
        env.now = 1.5
        widget.update()
        assert.is_true(fill.visible)
        widget.update("chunk", 0x0B, "HDRX")
        widget.update()
        assert.is_false(fill.visible)
      end)
    end)
  end)

  describe("enchanted item slots", function()
    local function vocation_world(status)
      local files = war_bindings()
      files.WAR.sets[1].left[1] = { type = "enchanteditem", action = "Vocation Ring" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true, { id = 27546, slot = 4, status = status or 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000,
        usable = false,
      }
    end

    local function fire()
      press(LEFT)
      press(DIK_SLOT[1])
    end

    it("uses a ring already worn and charged, with no equip and no GearSwap hold", function()
      vocation_world(5)
      fire()
      assert.are.same({ 'input /item "Vocation Ring" <me>' }, env.commands)
      assert.are.same({}, env.equips)
    end)

    it("equips a ring that is not worn, waits it out, then uses and re-enables", function()
      vocation_world()
      fire()
      assert.are.same({ "gs disable ring1" }, env.commands, "ring1, the lowest slot the ring fits")
      assert.are.same({ { 4, 13, 0 } }, env.equips, "bag slot 4 into equip slot 13 from bag 0")
      env.ext.activation_time = env.time - 18000 + 10
      widget.update()
      assert.are.equal(1, #env.commands, "still warming")
      env.ext.usable = true
      env.now = 1.5
      widget.update()
      assert.are.same({ "gs disable ring1", 'input /item "Vocation Ring" <me>', "gs enable ring1" }, env.commands)
    end)

    it("does not fire on the first poll after equipping, on the extdata the client still holds", function()
      --[[ The regression guard. Every other equip-path test rewrites
           activation_time between the press and the first update, so none
           of them sees what the client actually has one frame after
           set_equip: the timestamp from a PREVIOUS equip, elapsed. Reading
           that as ready sends the /item before the ring is on. ]]
      vocation_world()
      env.ext.activation_time = env.time - 18000 - 600 -- some equip, long ago
      fire()
      widget.update()
      assert.are.same({ "gs disable ring1" }, env.commands, "the wait waits")
      env.ext.usable = true
      env.now = 1.5
      widget.update()
      assert.are.same({ "gs disable ring1", 'input /item "Vocation Ring" <me>', "gs enable ring1" }, env.commands)
    end)

    it("never trusts the warmup on a ring it equipped itself, even once the client says it is on", function()
      --[[ The other half of the regression guard. `status` flips to worn as
           soon as the client applies the equip, which can be a poll before
           the server's extdata refresh lands - so a ring worn earlier this
           session carries an ELAPSED activation_time from that older equip,
           and reading worn-ness off the live item alone would start
           trusting it the moment the equip registered. Only a wait armed
           over a piece that was ALREADY on may trust that timestamp. ]]
      vocation_world()
      env.ext.activation_time = env.time - 18000 - 600 -- an equip from earlier
      fire()
      env.items[0] = { enabled = true, { id = 27546, slot = 4, status = 5, count = 1 } }
      env.now = 1.5
      widget.update()
      assert.are.same({ "gs disable ring1" }, env.commands, "the equip landed; the enchantment has not")
      env.ext.usable = true
      env.now = 3
      widget.update()
      assert.are.equal('input /item "Vocation Ring" <me>', env.commands[2], "the flag is what ends this wait")
    end)

    it("pins a target token at the press, so a deferred use cannot wander", function()
      --[[ The command is sent when the enchantment goes live, which can be
           forty seconds after the press. Carrying `<t>` that far means
           landing on whatever has been tabbed to since - the exact wander
           the cast retry pins against, and the warp ladder never met it
           because every rung of that is hardcoded <me>. ]]
      local files = war_bindings()
      files.WAR.sets[1].left[1] = { type = "enchanteditem", action = "Vocation Ring", target = "t" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true, { id = 27546, slot = 4, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000,
        usable = false,
      }
      env.target = { id = 4242 }
      fire()
      env.target = { id = 9999 }
      env.ext.usable = true
      env.now = 1.5
      widget.update()
      assert.are.equal('input /item "Vocation Ring" 4242', env.commands[2], "the mob from the press, not the new one")
    end)

    it("refuses a deferred press whose target cannot be pinned at the press", function()
      --[[ The command is sent when the enchantment goes live, so a token
           carried that far resolves THEN. `<st>` would open a selection
           cursor most of a minute after the press; nothing about that is
           the press's target. Either the press resolves it or the press
           does not happen - and nothing is held meanwhile, so no GearSwap
           slot is left disabled over a refusal. ]]
      local files = war_bindings()
      files.WAR.sets[1].left[1] = { type = "enchanteditem", action = "Vocation Ring", target = "st" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true, { id = 27546, slot = 4, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000,
        usable = false,
      }
      fire()
      assert.are.same({}, env.commands, "no gs disable over a press that will not happen")
      assert.are.same({}, env.equips)
      assert.is_not_nil(said():find("cannot pin"), "said: " .. said())
    end)

    it("refuses a deferred press aimed at nothing", function()
      -- `<t>` with no target selected has nothing to pin either: resolving
      -- it later is the wander, and resolving it now answers nothing.
      local files = war_bindings()
      files.WAR.sets[1].left[1] = { type = "enchanteditem", action = "Vocation Ring", target = "t" }
      build_world({ store_files = files })
      env.target = nil
      env.items[0] = { enabled = true, { id = 27546, slot = 4, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000,
        usable = false,
      }
      fire()
      assert.are.same({}, env.commands)
      assert.is_not_nil(said():find("nothing targeted"), "said: " .. said())
    end)

    it("stops trusting the warmup if the ring comes off mid-wait", function()
      --[[ "Worn" is why an elapsed warmup counts for anything, so it has to
           be read at the poll rather than remembered from the press: a
           manual equip from the game's own menu takes the ring off whatever
           GearSwap was told, and the piece is still in its bag slot, so
           every other check the poll makes still passes. ]]
      vocation_world(5)
      env.ext.activation_time = env.time - 18000 + 10
      fire()
      -- The warmup elapses, which on a worn ring means ready - but the ring
      -- has been taken off in the meantime, so that timestamp is once again
      -- describing an equip that is over.
      env.ext.activation_time = env.time - 18000
      env.items[0] = { enabled = true, { id = 27546, slot = 4, status = 0, count = 1 } }
      env.now = 1.5
      widget.update()
      assert.are.same({ "gs disable ring1", "gs disable ring2" }, env.commands, "no /item on a ring not worn")
      env.ext.usable = true
      env.now = 3
      widget.update()
      assert.are.equal('input /item "Vocation Ring" <me>', env.commands[3], "the flag still speaks for itself")
    end)

    it("equips a wardrobe ring and polls the bag it actually came from", function()
      -- The wait polls by bag, so a ring found in wardrobe 8 that was
      -- polled for in bag 0 would be reported missing a second later.
      vocation_world()
      env.items[0] = { enabled = true }
      env.items[8] = { enabled = true, { id = 27546, slot = 7, status = 0, count = 1 } }
      fire()
      assert.are.same({ "gs disable ring1" }, env.commands)
      assert.are.same({ { 7, 13, 8 } }, env.equips, "bag slot 7 into equip slot 13 from bag 8")
      env.ext.usable = true
      env.now = 1.5
      widget.update()
      assert.are.same({ "gs disable ring1", 'input /item "Vocation Ring" <me>', "gs enable ring1" }, env.commands)
    end)

    it("fires at once - an enchanted item is not a trip and takes no travel delay", function()
      -- CB10 holds mount, mr and warp for five seconds. This is deliberately
      -- outside that: the warmup already is the wait, and a Vocation Ring is
      -- not something you press by mistake and want back.
      --
      -- A GUARD, not a proof: travel.lua's own type list names only warp,
      -- mount and mr, so no wiring in the widget could delay this record
      -- today. What it pins is the decision - adding enchanteditem to that
      -- list later would fail here, which is the point.
      vocation_world(5)
      config.delay = 5
      fire()
      assert.are.same({ 'input /item "Vocation Ring" <me>' }, env.commands, "no countdown between press and use")
    end)

    it("says why nothing happened when the ring is on recast", function()
      vocation_world(5)
      env.ext.next_use_time = env.time - 18000 + 42
      fire()
      assert.are.same({}, env.commands)
      assert.is_not_nil(said():find("42 sec recast"), "said: " .. said())
    end)

    it("refuses to start a second wait while one is already running", function()
      vocation_world()
      fire()
      local after_first = #env.commands
      release(DIK_SLOT[1])
      release(LEFT)
      fire()
      assert.are.equal(after_first, #env.commands, "no second gs disable, no crossed equips")
      assert.is_not_nil(said():lower():find("already in progress"), "said: " .. said())
    end)

    it("is blocked by a warp already in flight, and told so in the warp's own words", function()
      -- One pair of hands: the two share a scheduler, so whichever armed it
      -- names itself in the refusal. Pressing the same type twice would not
      -- show that, since both nouns would read the same.
      local files = war_bindings()
      files.WAR.sets[1].left[1] = { type = "enchanteditem", action = "Vocation Ring" }
      build_world({ store_files = files })
      -- Both rings present, so the enchanted press is otherwise viable and
      -- the pending guard is the only thing that can stop it.
      env.items[0] = {
        enabled = true,
        { id = 28540, slot = 5, status = 0, count = 1 },
        { id = 27546, slot = 6, status = 0, count = 1 },
      }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000 + 5,
        usable = false,
      }
      widget.handle_command({ "warp" })
      env.now = 6
      widget.update()
      assert.are.same({ "gs disable ring1" }, env.commands, "the warp holds the ring slot")
      fire()
      assert.are.same({ "gs disable ring1" }, env.commands, "the enchanted press adds nothing")
      assert.is_not_nil(said():find("warp already in progress"), "the WARP's noun, not ours: " .. said())
    end)

    it("drops a wait in flight when the component is re-attached", function()
      -- `//hud reset crossbar` and the reload after `//hud copy` replace the
      -- configuration that armed it, so a wait carrying a command from the
      -- discarded config must not fire - and the GearSwap slot it is
      -- holding must not stay held.
      vocation_world()
      fire()
      assert.are.same({ "gs disable ring1" }, env.commands)
      widget.attach(config, function() end, store)
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      env.ext.usable = true
      env.now = 2
      widget.update()
      assert.are.equal(2, #env.commands, "nothing fires from the replaced configuration")
    end)

    it("gives up the wait and re-enables the slot when the component is suppressed", function()
      vocation_world()
      fire()
      env.suppressed = true
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(
        said():find("enchanted item abandoned"),
        "says what was given up, not the warp ladder's word for it: " .. said()
      )
      env.ext.usable = true
      env.suppressed = false
      env.now = 2
      widget.update()
      assert.are.equal(2, #env.commands, "nothing fires after the abort")
    end)

    it("holds GearSwap off a worn ring that is still warming, without re-equipping it", function()
      -- Both ring slots are held: the ring is on one of them and nothing
      -- here can say which, so holding one is a coin flip whose losing side
      -- is GearSwap swapping the warming ring off and the wait dying at the
      -- deadline. Every slot held is released on the way out.
      vocation_world(5)
      env.ext.activation_time = env.time - 18000 + 10
      fire()
      assert.are.same({ "gs disable ring1", "gs disable ring2" }, env.commands)
      assert.are.same({}, env.equips, "already on - re-equipping could restart the warmup")
      env.ext.usable = true
      env.now = 1.5
      widget.update()
      assert.are.same({
        "gs disable ring1",
        "gs disable ring2",
        'input /item "Vocation Ring" <me>',
        "gs enable ring1",
        "gs enable ring2",
      }, env.commands)
    end)

    it("names the GearSwap slot the item is actually worn in, not just rings", function()
      -- GS_SLOT_NAMES carries all sixteen slots since a binding can name any
      -- worn piece; ring1 was the only one the warp ladder ever exercised.
      local files = war_bindings()
      files.WAR.sets[1].left[1] = { type = "enchanteditem", action = "Warp Cudgel" }
      build_world({ store_files = files })
      env.items[0] = { enabled = true, { id = 17040, slot = 6, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000,
        usable = false,
      }
      fire()
      assert.are.same({ "gs disable main" }, env.commands, "a cudgel is a main-hand weapon")
      assert.are.same({ { 6, 0, 0 } }, env.equips)
    end)

    it("says so rather than firing when the extdata cannot be read at all", function()
      -- Without the extdata library there is no way to know whether the
      -- ring is charged, or even enchanted. Sending the plain /item anyway
      -- is refused by the game and tells the player nothing.
      vocation_world()
      env.ext = nil
      fire()
      assert.are.same({}, env.commands)
      assert.is_not_nil(said():find("Cannot read Vocation Ring"), "said: " .. said())
    end)

    it("second-guesses a trailing word against the item resources when binding one", function()
      --[[ The CLI checks an over-long action name against the client before
           storing it, and it can only do that for a type it knows which
           resource table to ask. Without the enchanteditem entry both
           lookups answer "no idea", the junk name is bound with a mere
           caution, and the slot can never fire. ]]
      build_world({ store_files = war_bindings() })
      local told = widget.handle_command({ "bind", "1L6", "enchanteditem", "Vocation", "Ring", "Zeid" })
      assert.is_not_nil(tostring(told):find("is not an action"), "said: " .. tostring(told))
      assert.is_nil(env.store_files.WAR.sets[1].left[6], "and nothing was written")
    end)

    it("counts the ring in the slot corner like any other item", function()
      vocation_world(5)
      widget.update()
      assert.are.equal("1", text_of("xhb_left", 1, "cost").last.text)
    end)
  end)

  describe("auto-warp", function()
    --[[ A ring off recast and NOT worn: `activation_time` is whatever some
         previous equip left behind - here, elapsed - which is exactly why
         an elapsed warmup means nothing until the piece is on. The wait
         this arms ends when `usable` says so, not when this arithmetic
         does. ]]
    local RING_EXT_READY = {
      type = "Enchanted Equipment",
      charges_remaining = 1,
      next_use_time = 1000000 - 18000,
      activation_time = 1000000 - 18000,
      usable = false,
    }

    local function ring_world()
      build_world()
      -- A windower bag table: the enabled flag beside the array of items.
      env.items[0] = { enabled = true, { id = 28540, slot = 5, status = 0, count = 1 } }
      env.ext = {}
      for key, value in pairs(RING_EXT_READY) do
        env.ext[key] = value
      end
    end

    it("waits out the Tavnazian Ring's long warmup instead of abandoning it", function()
      --[[ CB13. Its enchantment takes about thirty seconds, and the test
           is `warm > bound`, so thirty exactly would wait on the default
           too - which is why this sits at THIRTY-ONE, the first value the
           default bound rejects and the per-item bound accepts. That is
           the slop the longer bound exists for: equip latency, a poll
           landing late, a rounded timestamp.

           Nothing above it is available here, so the ladder falls to it -
           which also proves the widget passes the resource lookup a named
           rung needs. ]]
      build_world()
      env.items[0] = { enabled = true, { id = 26123, slot = 4, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000 + 31,
        usable = false,
      }
      widget.handle_command({ "warp" })
      env.now = 6
      widget.update()
      assert.are.same({ "gs disable ring1" }, env.commands, "ring1, off the resource's own slots")
      assert.are.same({ { 4, 13, 0 } }, env.equips)
      env.now = 7
      widget.update()
      assert.are.equal(1, #env.commands, "past the default bound, inside this ring's own")
      env.ext.usable = true
      env.now = 8
      widget.update()
      assert.are.equal('input /item "Tavnazian Ring" <me>', env.commands[2])
    end)

    it("lets a long-bound wait outlive the deadline a default one would have had", function()
      --[[ The load-bearing half of the longer bound. The old ceiling was a
           flat 45 seconds, measured from the press; a rung granted forty
           seconds of warmup would have been killed by it at 45 with five
           seconds still to run, so the bound it was given would have bought
           nothing. The ceiling is now the PLAN's bound plus a margin. ]]
      build_world()
      env.items[0] = { enabled = true, { id = 26123, slot = 4, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000 + 30,
        usable = false,
      }
      widget.handle_command({ "warp" })
      -- Past 45s, which is where the flat ceiling used to end it.
      env.time = env.time + 50
      env.now = 51
      widget.update()
      assert.are.equal(1, #env.commands, "still waiting, not abandoned")
      env.ext.usable = true
      env.now = 52
      widget.update()
      assert.are.equal('input /item "Tavnazian Ring" <me>', env.commands[2])
    end)

    it("still ends a long-bound wait once its own ceiling passes", function()
      -- The ceiling moved; it did not go away.
      build_world()
      env.items[0] = { enabled = true, { id = 26123, slot = 4, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000 + 30,
        usable = false,
      }
      widget.handle_command({ "warp" })
      env.time = env.time + 60
      env.now = 61
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said():find("took too long"), "said: " .. said())
    end)

    it("fires the spell rung when its countdown runs out", function()
      -- Since CB10 a spell rung waits out the travel delay; the ladder's
      -- pick is what this pins, and the countdown is covered on its own.
      build_world()
      env.player.main_job_id = 4
      env.player.vitals.mp = 200
      env.known_spells = { [261] = true }
      widget.handle_command({ "warp" })
      env.now = 5
      widget.update()
      assert.are.same({ 'input /ma "Warp" <me>' }, env.commands)
    end)

    it("equips the ring GearSwap-safely, waits, uses, re-enables", function()
      ring_world()
      widget.handle_command({ "warp" })
      assert.are.same({ "gs disable ring1" }, env.commands)
      assert.are.same({ { 5, 13, 0 } }, env.equips, "bag slot 5 into equip slot 13 from bag 0")
      env.ext.activation_time = env.time - 18000 + 10
      widget.update()
      assert.are.equal(1, #env.commands, "still warming: 10s is inside the 30s bound")
      env.ext.usable = true
      env.now = 1.5
      widget.update()
      assert.are.same({ "gs disable ring1", 'input /item "Warp Ring" <me>', "gs enable ring1" }, env.commands)
      env.now = 3
      widget.update()
      assert.are.equal(3, #env.commands, "the machine is done")
    end)

    it("polls the pending warp once a second, not per frame", function()
      -- MyHome's own cadence; a per-frame poll would read the whole bag
      -- sixty times a second.
      ring_world()
      widget.handle_command({ "warp" })
      env.now = 0
      local reads = env.item_reads
      widget.update()
      local first = env.item_reads
      assert.is_true(first > reads, "the first poll runs at once")
      widget.update()
      widget.update()
      assert.are.equal(first, env.item_reads, "no further bag reads inside the second")
      env.now = 1.5
      widget.update()
      assert.is_true(env.item_reads > first, "the next second polls again")
    end)

    it("aborts when the remembered slot no longer holds the ring", function()
      ring_world()
      widget.handle_command({ "warp" })
      env.items[0] = { enabled = true, { id = 12345, slot = 5, status = 0, count = 1 } }
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said():lower():find("missing"), "said: " .. said())
      env.ext.usable = true
      env.now = 2
      widget.update()
      assert.are.equal(2, #env.commands, "nothing fires after the abort")
    end)

    it("aborts when the ring moved even though it still exists", function()
      -- A sort, a trade or GearSwap itself can move the ring; the poll
      -- matches id AND slot, and a moved ring is a warp abandoned.
      ring_world()
      widget.handle_command({ "warp" })
      env.items[0] = { enabled = true, { id = 28540, slot = 9, status = 0, count = 1 } }
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said():lower():find("missing"), "said: " .. said())
    end)

    it("aborts when the extdata decode itself would raise", function()
      -- extdata.decode raises on foreign input; the entry point's wrapper
      -- pcalls it and answers nil, which the widget treats as unreadable.
      ring_world()
      widget.handle_command({ "warp" })
      ctx.decode_extdata = function()
        local ok, ext = pcall(error, "unknown item class")
        return ok and ext or nil
      end
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said():lower():find("cannot be read"), "said: " .. said())
    end)

    it("aborts rather than throws on an ext that is not enchanted-shaped", function()
      ring_world()
      widget.handle_command({ "warp" })
      env.ext = { type = "General" }
      assert.has_no.errors(function()
        widget.update()
      end)
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
    end)

    it("refuses a second warp while one is pending", function()
      ring_world()
      widget.handle_command({ "warp" })
      -- Swapped straight back off, so the wait is still trying to get it on
      -- when the second press arrives - which is the state the guard is
      -- about, and no longer the state the first press leaves behind.
      env.items[0][1].status = 0
      local before = #env.commands
      widget.handle_command({ "warp" })
      assert.are.equal(before, #env.commands, "no second gs disable, no second equip")
      assert.are.equal(1, #env.equips)
      assert.is_not_nil(said():lower():find("in progress"), "said: " .. said())
    end)

    it("re-enables GearSwap on destroy", function()
      -- core.on_unload calls destroy, not detach: gs enable on EVERY exit.
      ring_world()
      widget.handle_command({ "warp" })
      widget.destroy()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
    end)

    it("re-equips a ring something else swapped straight back off", function()
      --[[ `gs disable` stops FUTURE GearSwap swaps; it does not cancel one
           already in flight. `gs equip sets.engaged; hud crossbar warp`
           reproduces it exactly: our equip goes out, GearSwap's set lands
           on top, and the ring never reaches a finger - so the wait sat
           there for a minute polling the extdata of a ring in the bag
           (Kevin, live client, 2026-08-22).

           The poll re-read the item every second and never asked the one
           question that mattered: is it actually ON. It asks now, and puts
           it back. ]]
      ring_world()
      widget.handle_command({ "warp" })
      local first = #env.equips
      assert.is_true(first > 0, "the press equipped it once")
      -- GearSwap takes it straight back off, which is what `gs disable`
      -- cannot stop once a swap is already in flight.
      env.items[0][1].status = 0
      env.now = 2
      widget.update()
      assert.is_true(#env.equips > first, "and the poll puts it back on")
      -- The extdata of a ring that is not worn is never acted on, whatever
      -- it says - firing /item at a ring in the bag is refused by the game
      -- and would broadcast a `warp all` on nothing.
      env.items[0][1].status = 0
      env.ext.usable = true
      env.now = 3
      widget.update()
      for _, command in ipairs(env.commands) do
        assert.is_nil(command:find("/item", 1, true), "nothing fires at a ring in the bag")
      end
    end)

    it("keeps putting a stolen ring back until the deadline gives up on it", function()
      --[[ Kevin's call (2026-08-22): retry for as long as the press has,
           rather than giving up early on a slot being fought over. A
           GearSwap burst can outlast several seconds, and the deadline is
           already the one exit that always fires. ]]
      ring_world()
      widget.handle_command({ "warp" })
      local tries = #env.equips
      env.chat = {}
      for second = 2, 12 do
        -- Stolen again every single poll.
        env.items[0][1].status = 0
        env.now = second
        widget.update()
      end
      assert.is_true(#env.equips > tries + 5, "it kept trying, once a poll")
      assert.are.same({}, env.chat, "and said nothing while it was still trying")

      -- The wall clock is what ends it, and it releases the slot.
      env.time = env.time + 46
      env.now = 13
      widget.update()
      assert.is_not_nil(said():lower():find("abandoned"), "said: " .. said())
      assert.are.equal("gs enable ring1", env.commands[#env.commands], "and lets the slot go")
    end)

    it("gives up on the wall clock when the wait never resolves", function()
      -- set_equip can silently no-op (Windower drops mismatched args),
      -- leaving activation_time stale and the step answering "wait"
      -- forever; the deadline is the one exit that still fires.
      ring_world()
      widget.handle_command({ "warp" })
      env.ext.activation_time = env.time - 18000 + 5
      widget.update()
      assert.are.equal(1, #env.commands, "still waiting inside the 30s bound")
      env.time = env.time + 46
      env.now = 2
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said():lower():find("abandoned"), "said: " .. said())
      env.ext.usable = true
      env.now = 4
      widget.update()
      assert.are.equal(2, #env.commands, "nothing fires after the deadline abort")
    end)

    it("gives up at once when the wait exceeds the bound", function()
      ring_world()
      widget.handle_command({ "warp" })
      env.ext.activation_time = env.time - 18000 + 31
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.is_not_nil(said():lower():find("warp"), "the give-up is said")
    end)

    it("aborts on suppression, re-enabling GearSwap", function()
      ring_world()
      widget.handle_command({ "warp" })
      env.suppressed = true
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      env.ext.usable = true
      widget.update()
      assert.are.equal(2, #env.commands, "nothing fires after the abort")
    end)

    it("re-enables GearSwap on detach", function()
      ring_world()
      widget.handle_command({ "warp" })
      widget.detach()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
    end)

    it("holds the warp all broadcast until the ring itself fires", function()
      -- The rung skips the countdown (its warm-up is the wait), so the
      -- press commits nothing: the alts must not be home while this
      -- character is still waiting on a ring that may yet be abandoned.
      ring_world()
      widget.handle_command({ "warp", "all" })
      assert.are.same({ "gs disable ring1" }, env.commands)
      assert.are.same({}, env.ipc, "nobody is sent while the ring is still warming")
      env.ext.usable = true
      env.now = 1.5
      widget.update()
      assert.are.same({ "gs disable ring1", 'input /item "Warp Ring" <me>', "gs enable ring1" }, env.commands)
      assert.are.same({ "xivhud crossbar warp" }, env.ipc, "and they go when it does")
    end)

    it("sends nobody when the warm-up is abandoned", function()
      ring_world()
      widget.handle_command({ "warp", "all" })
      env.items[0] = { enabled = true, { id = 12345, slot = 5, status = 0, count = 1 } }
      widget.update()
      assert.are.equal("gs enable ring1", env.commands[#env.commands])
      assert.are.same({}, env.ipc, "a warp that never happened sends nobody home")
    end)

    it("broadcasts warp all and answers only its own IPC message", function()
      build_world()
      env.player.main_job_id = 4
      env.player.vitals.mp = 200
      env.known_spells = { [261] = true }
      widget.handle_command({ "warp", "all" })
      -- Since CB10 the broadcast goes when the local warp does, not when
      -- it is pressed: a cancelled countdown must call the alts off too.
      env.now = 5
      widget.update()
      assert.are.same({ "xivhud crossbar warp" }, env.ipc)
      assert.are.same({ 'input /ma "Warp" <me>' }, env.commands, "and warps locally")
      widget.update("ipc message", "xivhud crossbar warp")
      assert.are.equal(2, #env.commands, "the receiver warps without re-broadcasting")
      assert.are.equal(1, #env.ipc)
      widget.update("ipc message", "myhome")
      assert.are.equal(2, #env.commands, "a real MyHome next door is not our message")
    end)
  end)

  --[[ CB10: mount, mount roulette and warp arm a five-second countdown,
       speak once a second, and only then go - so a mis-press costs five
       seconds of reading rather than a trip home. ]]
  describe("travel delay", function()
    local RIDE = 'input /mount "chocobo"'
    local WARP = 'input /ma "Warp" <me>'
    -- The key item chunk the roulette refreshes its owned mounts on.
    local KEY_ITEM_CHUNK = 0x055
    -- The zone-out chunk, and the resource table's own resting status.
    local ZONE_OUT_CHUNK = 0x0B
    local RESTING, DEAD = 7, 2

    -- A world with one mount owned, so `mr` has something to summon.
    local function mount_world(opts)
      build_world(opts)
      env.key_items = { 3000 }
      widget.update("chunk", KEY_ITEM_CHUNK)
    end

    -- A BLM with the MP and the spell for the ladder's first rung.
    local function warp_world(opts)
      build_world(opts)
      env.player.main_job_id = 4
      env.player.vitals.mp = 200
      env.known_spells = { [261] = true }
    end

    local function tick_to(seconds)
      env.now = seconds
      widget.update()
    end

    local function last_said()
      return env.chat[#env.chat]
    end

    it("counts a mount roulette down, one line a second, and then rides", function()
      mount_world()
      widget.handle_command({ "mr" })
      assert.are.same({}, env.commands, "the press itself fires nothing")
      assert.are.equal("crossbar: Mount roulette in 5 seconds. /heal to cancel.", last_said())
      for second = 1, 4 do
        tick_to(second)
        assert.are.equal((5 - second) .. "...", last_said(), "second " .. second)
        assert.are.same({}, env.commands)
      end
      tick_to(5)
      assert.are.same({ RIDE }, env.commands)
      assert.are.equal("1...", last_said(), "the last word is a count, not a fanfare")
      tick_to(9)
      assert.are.equal(1, #env.commands, "and nothing rides twice")
    end)

    it("says nothing on a tick with nothing counting down", function()
      mount_world()
      tick_to(1)
      tick_to(2)
      assert.are.equal(0, #env.chat)
      assert.are.same({}, env.commands)
    end)

    it("costs the settled tick nothing", function()
      -- The per-frame budget: with nothing counting down the tick must be
      -- the same frame it was before the feature existed.
      mount_world()
      widget.update()
      env.player_reads, env.spell_reads, env.ability_reads = 0, 0, 0
      env.chat_reads, env.layout_reads = 0, 0
      widget.update()
      assert.are.equal(0, env.player_reads + env.spell_reads + env.ability_reads, "no client read of its own")
      assert.are.equal(0, env.chat_reads + env.layout_reads)
    end)

    it("holds a bound slot exactly as it holds the typed command", function()
      -- Both frontends resolve through one path by design, so they cannot
      -- behave differently.
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mr" }
      mount_world({ store_files = files })
      press(LEFT)
      press(DIK_SLOT[2])
      assert.are.same({}, env.commands)
      assert.are.equal("crossbar: Mount roulette in 5 seconds. /heal to cancel.", last_said())
      tick_to(5)
      assert.are.same({ RIDE }, env.commands)
    end)

    it("holds a bound mount, and names the mount it is about to summon", function()
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mount", action = "Chocobo" }
      mount_world({ store_files = files })
      press(LEFT)
      press(DIK_SLOT[2])
      assert.are.equal("crossbar: Mount Chocobo in 5 seconds. /heal to cancel.", last_said())
      tick_to(5)
      assert.are.same({ 'input /mount "Chocobo"' }, env.commands)
    end)

    it("announces a CLI-bound and a binder-bound mount identically", function()
      --[[ The two authoring surfaces store different records for the same
           mount - the CLI keeps what the player typed, the binder keeps the
           command form plus the game's own casing in `display` - and a
           countdown reading only one of them is what made a binder-bound
           mount announce "Mount chocobo". They must arrive at one line. ]]
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mount", action = "Chocobo" }
      files.WAR.sets[1].left[3] = { type = "mount", action = "chocobo", display = "Chocobo" }
      mount_world({ store_files = files })
      press(LEFT)
      press(DIK_SLOT[2])
      local from_cli = last_said()

      -- A fresh world rather than a cancel, so neither line can be the
      -- other's leftover.
      mount_world({ store_files = files })
      press(LEFT)
      press(DIK_SLOT[3])
      assert.are.equal(from_cli, last_said())
      assert.is_not_nil(from_cli:find("Mount Chocobo", 1, true), from_cli)
      tick_to(5)
      assert.are.same({ 'input /mount "chocobo"' }, env.commands, "and the lower-case form is what is sent")
    end)

    it("keeps the player's own label above the game's casing, and survives clearing it", function()
      -- Two owners, two fields: `//hud crossbar alias ... ` with the name
      -- omitted clears the player's label, and the game's casing must still
      -- be there underneath it.
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mount", action = "chocobo", display = "Chocobo" }
      mount_world({ store_files = files })
      widget.handle_command({ "alias", "1L2", "Pull mount" })
      press(LEFT)
      press(DIK_SLOT[2])
      assert.is_not_nil(last_said():find("Mount Pull mount", 1, true), last_said())

      mount_world({ store_files = files })
      widget.handle_command({ "alias", "1L2", "Pull mount" })
      widget.handle_command({ "alias", "1L2" })
      press(LEFT)
      press(DIK_SLOT[2])
      assert.is_not_nil(last_said():find("Mount Chocobo", 1, true), last_said())
    end)

    it("dismounts at once - the delay is for summoning, not for getting off", function()
      build_world()
      env.player.buffs = { 252 }
      widget.handle_command({ "mr" })
      assert.are.same({ "input /dismount" }, env.commands)
      assert.are.equal(0, #env.chat, "nothing to count down, nothing to say")
    end)

    it("dismounts at once from a NAMED mount slot too", function()
      --[[ The countdown is for summoning. A slot bound to a specific mount
           counted one out and then sent its summon while already mounted,
           so the same press was instant on an `mr` slot and a five-second
           wait on the one beside it (Kevin, live client, 2026-08-22). ]]
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mount", action = "chocobo", display = "Chocobo" }
      build_world({ store_files = files })
      env.player.buffs = { 252 }
      press(LEFT)
      press(DIK_SLOT[2])
      assert.are.same({ "input /dismount" }, env.commands)
      assert.are.equal(0, #env.chat, "nothing to count down, nothing to say")
    end)

    it("leaves the draw toggle instant", function()
      -- Instant means no countdown. Entering drawn sends nothing at all
      -- now, so the disengage is what this can watch go straight out.
      build_world()
      widget.handle_command({ "draw" })
      widget.handle_command({ "draw" })
      assert.are.same({ "input /attack off" }, env.commands)
      assert.are.equal(0, #env.chat, "no countdown either way")
    end)

    it("counts a spell-rung warp down before casting it", function()
      warp_world()
      widget.handle_command({ "warp" })
      assert.are.same({}, env.commands)
      assert.are.equal("crossbar: Warp in 5 seconds. /heal to cancel.", last_said())
      tick_to(5)
      assert.are.same({ WARP }, env.commands)
    end)

    it("counts a bound warp slot down and walks the ladder when it ends", function()
      -- The slot frontend of the warp path: its fire re-resolves through
      -- actions, where the typed verb walks the ladder itself.
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "warp" }
      warp_world({ store_files = files })
      press(LEFT)
      press(DIK_SLOT[2])
      assert.are.same({}, env.commands)
      assert.are.equal("crossbar: Warp in 5 seconds. /heal to cancel.", last_said())
      env.player.vitals.mp = 150
      env.known_spells = { [262] = true }
      tick_to(5)
      --[[ The rung it ANNOUNCED, not the one the ladder would pick now.
           A slot bound to `warp` used to re-walk when the countdown ended,
           while the `//hud crossbar warp` verb had already stopped - so
           the same trip obeyed two different rules depending on how it was
           pressed, and only the slot could name one item and fire
           another. ]]
      assert.are.same({ 'input /ma "Warp" <me>' }, env.commands, "what the countdown named")
    end)

    it("skips the countdown for a rung it has to equip and warm up", function()
      build_world()
      env.items[0] = { enabled = true, { id = 28540, slot = 5, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000,
        usable = false,
      }
      widget.handle_command({ "warp" })
      assert.are.same({ "gs disable ring1" }, env.commands, "the ring is equipped on the press")
      assert.is_nil(said():find("5 seconds", 1, true), "said: " .. said())
    end)

    it("counts an equipped, charged ring down - it has no wait of its own to skip", function()
      -- The corollary of the rule above: the skip is for a rung whose use
      -- entails a wait, and this one fires the moment it is asked.
      build_world()
      env.items[0] = { enabled = true, { id = 28540, slot = 5, status = 5, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000,
        usable = true,
      }
      widget.handle_command({ "warp" })
      assert.are.same({}, env.commands, "no instant warp: this one waits like a spell")
      -- The RUNG's name, so the line says which way you are going home.
      assert.are.equal("crossbar: Warp Ring in 5 seconds. /heal to cancel.", last_said())
      tick_to(5)
      assert.are.same({ 'input /item "Warp Ring" <me>' }, env.commands)
    end)

    it("fires at once when the delay is configured off", function()
      -- Zero is the off switch; there is no separate toggle verb.
      mount_world({
        tune_config = function(tuned)
          tuned.delay = 0
        end,
      })
      widget.handle_command({ "mr" })
      assert.are.same({ RIDE }, env.commands)
      assert.are.equal(0, #env.chat)
    end)

    it("narrates a ring warm-up, then lets /heal call it off", function()
      --[[ A warm-up is the longest wait the component ever imposes and was
           the only one it never spoke about, so it read as nothing having
           happened - and `/heal`, the way out its siblings all name, did
           not answer here at all: the ring sat there with a GearSwap slot
           held until it fired (Kevin, live client, 2026-08-22). ]]
      build_world()
      env.items[0] = { enabled = true, { id = 28540, slot = 5, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        -- Ten seconds of warmup still to run: inside the give-up bound, so
        -- the poll waits it out rather than abandoning at once.
        activation_time = env.time - 18000 + 10,
        usable = false,
      }
      widget.handle_command({ "warp" })
      assert.are.equal("crossbar: warp with Warp Ring - equipping it first.", last_said())
      assert.are.equal("gs disable ring1", env.commands[1])

      -- The first poll can read the warmup, so the length is spoken then.
      tick_to(1)
      assert.is_not_nil(said():find("Warp Ring ready in", 1, true), said())
      assert.is_not_nil(said():find("/heal to cancel", 1, true), said())

      -- Resting calls it off, and lets go of the slot it was holding.
      widget.update("status", RESTING)
      assert.is_not_nil(said():find("warp cancelled", 1, true), said())
      local released = false
      for _, command in ipairs(env.commands) do
        released = released or command == "gs enable ring1"
      end
      assert.is_true(released, "the GearSwap hold is released with it")
      tick_to(40)
      for _, command in ipairs(env.commands) do
        assert.is_nil(command:find("/item", 1, true), "and nothing fires afterwards")
      end
    end)

    it("waits for a warmup it can believe before announcing one", function()
      --[[ On the EQUIP path the extdata's activation_time still belongs to
           some earlier equip until the server refreshes it, so the first
           poll reads zero seconds remaining. Announcing that produced
           "Warp Ring ready in 0 seconds" and then silence for the ten
           seconds it actually took (Kevin, live client, 2026-08-22): the
           zero had latched the counter at 1, so every later real reading
           was smaller-than-nothing and never spoke. ]]
      build_world()
      env.items[0] = { enabled = true, { id = 28540, slot = 5, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        -- Stale: reads as zero remaining, and means nothing.
        activation_time = env.time - 18000,
        usable = false,
      }
      widget.handle_command({ "warp" })
      tick_to(1)
      assert.is_nil(said():find("ready in 0", 1, true), "no zero-second promise: " .. said())

      -- The server refreshes it: ten seconds, and NOW there is something to say.
      env.ext.activation_time = env.time - 18000 + 10
      tick_to(2)
      assert.is_not_nil(said():find("Warp Ring ready in 10 seconds", 1, true), said())

      -- Ten seconds in hand, so the last five are counted and the first
      -- five pass in silence.
      --[[ Second by second, on BOTH clocks: `tick_to` moves the frame
           clock and polls once, while the warmup is measured against the
           game's own timestamp - so a leap on either alone either skips
           every second the countdown speaks on, or freezes the warmup. ]]
      local base = env.time
      for second = 3, 13 do
        env.time = base + (second - 2)
        tick_to(second)
      end
      local spoken = said()
      for _, line in ipairs({ "5...", "4...", "3...", "2...", "1..." }) do
        assert.is_not_nil(spoken:find(line, 1, true), line .. " missing from: " .. spoken)
      end
      assert.is_nil(spoken:find("9...", 1, true), "and the middle stays quiet: " .. spoken)
    end)

    it("says so when a re-attach drops a wait that was in flight", function()
      --[[ Attach and detach drop a pending wait deliberately - its command
           comes from a configuration being replaced - and did it in
           silence, on the reasoning that a reset is not a cancellation
           worth reporting.

           That reasoning does not survive a warp evaporating: the ring is
           on your finger, the GearSwap slot has just been let go, and
           nothing ever happens. It is also exactly what hid an
           intermittent one from view (Kevin, live client, 2026-08-22) -
           every OTHER way a wait can end says something, so silence read
           as "still waiting" for as long as the player cared to look. ]]
      build_world()
      env.items[0] = { enabled = true, { id = 28540, slot = 5, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000 + 10,
        usable = false,
      }
      widget.handle_command({ "warp" })
      env.chat = {}
      -- A re-attach: what `//hud reset crossbar` and the reload after
      -- `//hud copy` both do.
      widget.detach()
      assert.is_not_nil(said():find("Warp Ring", 1, true), "it names what it dropped: " .. said())
      local released = false
      for _, command in ipairs(env.commands) do
        released = released or command == "gs enable ring1"
      end
      assert.is_true(released, "and still lets go of the slot")
    end)

    it("reads as English on the enchanteditem path, and tells the truth about equipping", function()
      --[[ Two faults in one line. `noun` is a NOUN everywhere else it is
           used (" already in progress", " abandoned", " dropped"), and
           inflecting it here produced "enchanted iteming with Vocation
           Ring". And it promised "equipping it first" on the one plan
           where nothing is equipped - a ring already on your finger and
           still warming, which `set_equip` deliberately skips. ]]
      local files = war_bindings()
      files.WAR.sets[1].left[6] = { type = "enchanteditem", action = "Vocation Ring" }
      build_world({ store_files = files })
      -- Worn already, still warming: the equipped path, where `set_equip`
      -- is deliberately skipped.
      env.items[0] = { enabled = true, { id = 27546, slot = 5, status = 5, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000 + 10,
        usable = false,
      }
      press(LEFT)
      press(DIK_SLOT[6])
      release(DIK_SLOT[6])
      release(LEFT)
      local spoken = said()
      assert.is_nil(spoken:find("iteming", 1, true), "not inflected: " .. spoken)
      assert.is_nil(spoken:find("equipping it first", 1, true), "nothing is being equipped: " .. spoken)
      assert.is_not_nil(spoken:find("Vocation Ring", 1, true), "but it still names the piece: " .. spoken)
    end)

    it("drops a warm-up when you die or zone, not just when you rest", function()
      --[[ Resting learned to cancel a warm-up; death and zoning did not,
           though both already end a travel countdown. A player who died
           mid-warm-up kept a GearSwap slot disabled for the best part of a
           minute and then had `/item` fired for them on the other side -
           with `warp all` broadcasting on it. ]]
      for _, ending in ipairs({ "death", "zone" }) do
        build_world()
        env.items[0] = { enabled = true, { id = 28540, slot = 5, status = 0, count = 1 } }
        env.ext = {
          type = "Enchanted Equipment",
          charges_remaining = 1,
          next_use_time = env.time - 18000,
          activation_time = env.time - 18000 + 10,
          usable = false,
        }
        widget.handle_command({ "warp" })
        env.chat = {}
        if ending == "death" then
          widget.update("status", DEAD)
        else
          widget.update("chunk", 0x0B, "HDRX")
        end
        local released = false
        for _, command in ipairs(env.commands) do
          released = released or command == "gs enable ring1"
        end
        assert.is_true(released, ending .. ": the GearSwap hold is released")
        env.ext.usable = true
        tick_to(30)
        for _, command in ipairs(env.commands) do
          assert.is_nil(command:find("/item", 1, true), ending .. ": and nothing fires afterwards")
        end
      end
    end)

    it("fires the rung it announced, not a better one that appeared meanwhile", function()
      --[[ The ladder used to be walked AGAIN when the countdown ended, so
           the freshest rung won. The opening line names the rung now, and a
           line that promised one thing while another went is worse than a
           slightly stale choice (Kevin, 2026-08-22). Five seconds is long
           enough for the ladder to move under you - and it must not. ]]
      warp_world()
      widget.handle_command({ "warp" })
      local announced = last_said()
      env.known_spells = { [262] = true }
      env.player.vitals.mp = 150
      tick_to(5)
      assert.are.same({ WARP }, env.commands, "the rung that was announced")
      assert.is_not_nil(announced:find("Warp", 1, true), announced)
    end)

    it("still fires its announced rung when a better one has gone by the end", function()
      -- The other direction of the same rule, and the case that costs
      -- something: what was promised is attempted, where the re-walk would
      -- have quietly found something else to do.
      warp_world()
      widget.handle_command({ "warp" })
      env.known_spells = {}
      tick_to(5)
      assert.are.same({ WARP }, env.commands, "what it promised, whatever the ladder says now")
    end)

    it("broadcasts warp all when it goes, not when it is pressed", function()
      -- Otherwise a cancelled press still sends every other character home.
      warp_world()
      widget.handle_command({ "warp", "all" })
      assert.are.same({}, env.ipc, "the alts are not sent until this one goes")
      tick_to(5)
      assert.are.same({ "xivhud crossbar warp" }, env.ipc)
      assert.are.same({ WARP }, env.commands)
    end)

    it("warps at once for the receiving half of warp all", function()
      -- The sender's own countdown was the window; the message is the
      -- moment, and a second wait on every alt buys nothing.
      warp_world()
      widget.update("ipc message", "xivhud crossbar warp")
      assert.are.same({ WARP }, env.commands)
    end)

    it("replaces a countdown with the newer press", function()
      warp_world()
      env.key_items = { 3000 }
      widget.update("chunk", KEY_ITEM_CHUNK)
      widget.handle_command({ "mr" })
      tick_to(2)
      widget.handle_command({ "warp" })
      assert.are.equal("crossbar: Warp in 5 seconds. /heal to cancel.", last_said())
      tick_to(5)
      assert.are.same({}, env.commands, "the press that was replaced never fires")
      tick_to(7)
      assert.are.same({ WARP }, env.commands)
    end)

    it("ends a countdown with a trip that goes at once", function()
      -- A dismount is instant, but it is still a newer trip: leaving the
      -- mount counting down behind it would summon one three seconds after
      -- the player got off.
      mount_world()
      widget.handle_command({ "mr" })
      env.player.buffs = { 252 }
      tick_to(2)
      widget.handle_command({ "mr" })
      assert.are.same({ "input /dismount" }, env.commands)
      assert.are.equal("crossbar: Mount roulette cancelled.", last_said())
      tick_to(7)
      assert.are.same({ "input /dismount" }, env.commands, "and nothing is summoned afterwards")
    end)

    it("ends a countdown with a warp that skips its own", function()
      mount_world()
      widget.handle_command({ "mr" })
      env.items[0] = { enabled = true, { id = 28540, slot = 5, status = 0, count = 1 } }
      env.ext = {
        type = "Enchanted Equipment",
        charges_remaining = 1,
        next_use_time = env.time - 18000,
        activation_time = env.time - 18000,
        usable = false,
      }
      tick_to(2)
      widget.handle_command({ "warp" })
      assert.are.equal("gs disable ring1", env.commands[1])
      -- The cancel is still said; the warm-up's own opening line follows it,
      -- so the cancel is no longer the LAST thing spoken.
      assert.is_not_nil(said():find("Mount roulette cancelled.", 1, true), said())
      assert.are.equal("crossbar: warp with Warp Ring - equipping it first.", last_said())
      tick_to(6)
      for _, command in ipairs(env.commands) do
        assert.is_nil(command:find("/mount", 1, true), "no mount lands in the middle of the ring's wait")
      end
    end)

    it("keeps counting through a press that is not a trip", function()
      -- Only the listed transitions call a countdown off, and a press that
      -- goes nowhere is not one of them: curing while you wait to warp
      -- must not strand you where you were.
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mr" }
      mount_world({ store_files = files })
      press(LEFT)
      press(DIK_SLOT[2])
      release(DIK_SLOT[2])
      press(DIK_SLOT[3])
      assert.are.same({ 'input /ws "Savage Blade" <t>' }, env.commands, "the other press fires at once")
      tick_to(5)
      assert.are.same({ 'input /ws "Savage Blade" <t>', RIDE }, env.commands, "and the ride still goes")
    end)

    describe("what calls it off", function()
      local function armed()
        mount_world()
        widget.handle_command({ "mr" })
      end

      local function assert_cancelled(context)
        assert.are.equal("crossbar: Mount roulette cancelled.", last_said(), context)
        tick_to(9)
        assert.are.same({}, env.commands, context .. ": and nothing fires afterwards")
      end

      it("cancels on resting, from the status rather than the command text", function()
        -- Sel-Include.lua:2313's shape: /heal is the idiom, the status is
        -- the trigger, so it catches resting however it was entered.
        armed()
        widget.update("status", RESTING, 0)
        assert_cancelled("resting")
      end)

      it("cancels on death", function()
        armed()
        widget.update("status", DEAD, 0)
        assert_cancelled("death")
      end)

      it("cancels on a zone", function()
        armed()
        widget.update("chunk", ZONE_OUT_CHUNK, "\0\0\0\0")
        assert_cancelled("zone")
      end)

      it("cancels on a job change", function()
        armed()
        widget.update("job change", 5, 75, 13, 37)
        assert_cancelled("job change")
      end)

      it("cancels when the bar is suppressed or hidden", function()
        armed()
        env.suppressed = true
        widget.hide()
        assert_cancelled("suppression")
      end)

      it("cancels when layout mode takes the screen", function()
        -- A late action fires only where a fresh press would, the cast
        -- retry's own rule: opening a config mode means you are not
        -- playing just now.
        armed()
        env.layout = true
        widget.set_preview(true)
        tick_to(1)
        assert_cancelled("layout mode")
      end)

      it("cancels when the binder opens", function()
        armed()
        assert.is_string(widget.handle_command({ "edit" }))
        tick_to(1)
        assert_cancelled("edit mode")
      end)

      it("refuses a trip pressed while layout mode is already on, in one line", function()
        -- The other way round: the mode was open before the press. Refused
        -- where it is made rather than armed and called off a frame later -
        -- the outcome is the same and this is one line to read instead of
        -- two contradicting each other.
        mount_world()
        env.layout = true
        widget.set_preview(true)
        widget.handle_command({ "mr" })
        assert.are.equal("crossbar: Mount roulette - not while //hud layout is open", last_said())
        assert.are.equal(1, #env.chat, "one line, not an arming line and then a cancel")
        tick_to(9)
        assert.are.same({}, env.commands)
      end)

      it("refuses a trip pressed while the binder is already open", function()
        mount_world()
        assert.is_string(widget.handle_command({ "edit" }))
        widget.handle_command({ "mr" })
        assert.are.equal("crossbar: Mount roulette - not while edit mode is open", last_said())
        assert.are.equal(1, #env.chat)
        tick_to(9)
        assert.are.same({}, env.commands)
      end)

      it("still lets an instant trip through a config mode", function()
        -- The rule is about a LATE action landing where a fresh press
        -- would not; a dismount is the press itself, and getting off a
        -- mount to place the bar is not something to refuse.
        build_world()
        env.player.buffs = { 252 }
        env.layout = true
        widget.set_preview(true)
        widget.handle_command({ "mr" })
        assert.are.same({ "input /dismount" }, env.commands)
      end)

      it("keeps counting through an open chat line", function()
        -- Deliberately not a config mode: answering a tell while you wait
        -- to warp is playing, and stranding the trip for it would be a
        -- worse answer than the wait itself. (The cast retry DOES drop on
        -- this, because a re-send is a keypress and this one is not.)
        armed()
        env.chat_open = true
        tick_to(5)
        assert.are.same({ 'input /mount "chocobo"' }, env.commands)
      end)

      it("drops the countdown on a re-attach, without a word", function()
        -- `//hud reset crossbar` re-attaches WITHOUT detaching, and a trip
        -- armed beforehand belongs to the configuration just thrown away.
        armed()
        widget.attach(widget.defaults, function() end, store)
        assert.are.equal("crossbar: Mount roulette in 5 seconds. /heal to cancel.", last_said())
        tick_to(9)
        assert.are.same({}, env.commands)
      end)

      it("drops the countdown on a logout, without a word to a chat nobody is reading", function()
        armed()
        widget.detach()
        assert.are.equal("crossbar: Mount roulette in 5 seconds. /heal to cancel.", last_said())
        tick_to(9)
        assert.are.same({}, env.commands)
      end)

      it("keeps counting through the statuses that mean nothing to it", function()
        armed()
        widget.update("status", 1, 0)
        tick_to(5)
        assert.are.same({ RIDE }, env.commands)
      end)
    end)
  end)

  describe("cast retry", function()
    local CURE = 'input /ma "Cure" <t>'
    -- The same press re-sent: the token replaced by the id it stood for at
    -- the press, which is the whole point of the pin.
    local CURE_PINNED = 'input /ma "Cure" 99'
    local PROVOKE = 'input /ja "Provoke" <me>'
    -- Slot 5 of the active set's left side is Cure; slot 4 is Provoke.
    local CURE_SLOT, PROVOKE_SLOT = DIK_SLOT[5], DIK_SLOT[4]
    local SAVAGE = 'input /ws "Savage Blade" <t>'

    local function le(value, bytes)
      local out = {}
      for _ = 1, bytes do
        out[#out + 1] = string.char(value % 256)
        value = math.floor(value / 256)
      end
      return table.concat(out)
    end

    -- A 0x029 body: header, Actor, Target, Param 1, Param 2, Actor Index,
    -- Target Index, Message - the layout skillchain.lua reads too.
    local function refusal(actor, message)
      return le(0, 4)
        .. le(actor, 4)
        .. le(0, 4)
        .. le(0, 4)
        .. le(0, 4)
        .. le(0, 2)
        .. le(0, 2)
        .. le(message or 17, 2)
    end

    local function live(tune)
      build_world({
        tune_config = function(tuned)
          tuned.retry.enabled = true
          if tune ~= nil then
            tune(tuned)
          end
        end,
      })
    end

    local function cast(slot)
      press(LEFT)
      press(slot or CURE_SLOT)
      release(slot or CURE_SLOT)
      release(LEFT)
    end

    -- Cast, take the refusal, and run the clock past the backoff.
    local function refused()
      cast()
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
    end

    it("ships off: nothing is remembered and nothing is re-sent", function()
      build_world()
      assert.is_false(widget.defaults.retry.enabled, "off until the trigger is confirmed in client")
      cast()
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = 5
      widget.update()
      assert.are.same({ CURE }, env.commands, "the press went out once, and only once")
    end)

    it("sends the press immediately and re-sends it after a refusal", function()
      live()
      cast()
      assert.are.same({ CURE }, env.commands, "a press is never delayed by this feature")
      widget.update("chunk", 0x29, refusal(env.player.id))
      widget.update()
      assert.are.same({ CURE }, env.commands, "and nothing goes out before the backoff")
      env.now = 1
      widget.update()
      assert.are.same({ CURE, CURE_PINNED }, env.commands)
      env.now = 2
      widget.update()
      assert.are.same({ CURE, CURE_PINNED }, env.commands, "one refusal buys one re-send")
    end)

    it("ignores a refusal that names somebody else", function()
      live()
      cast()
      widget.update("chunk", 0x29, refusal(4242))
      env.now = 1
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    it("retries an ability, on the message an ability is refused with", function()
      live()
      cast(PROVOKE_SLOT)
      assert.are.same({ PROVOKE }, env.commands)
      -- 17 is the SPELL refusal: it is not an answer to this press.
      widget.update("chunk", 0x29, refusal(env.player.id, 17))
      env.now = 1
      widget.update()
      assert.are.same({ PROVOKE }, env.commands, "a spell's refusal does not answer an ability")
      widget.update("chunk", 0x29, refusal(env.player.id, 71))
      env.now = 2
      widget.update()
      assert.are.same({ PROVOKE, PROVOKE }, env.commands)
    end)

    it("retries a weaponskill, target pinned like any other", function()
      live()
      cast(DIK_SLOT[3])
      assert.are.same({ SAVAGE }, env.commands)
      widget.update("chunk", 0x29, refusal(env.player.id, 72))
      env.now = 1
      env.target = { id = 4242 }
      widget.update()
      assert.are.same({ SAVAGE, 'input /ws "Savage Blade" 99' }, env.commands)
    end)

    it("watches nothing it has no refusal message for", function()
      -- Items and the built-ins are refused in words nothing here reads.
      live()
      widget.handle_command({ "bind", "1L6", "item", "Prism Powder", "me" })
      cast(DIK_SLOT[6])
      for _, message in ipairs({ 17, 71, 72 }) do
        widget.update("chunk", 0x29, refusal(env.player.id, message))
      end
      env.now = 1
      widget.update()
      assert.are.same({ 'input /item "Prism Powder" <me>' }, env.commands)
    end)

    it("does not watch a pet ability, whatever it is refused with", function()
      -- Deliberate: a blood pact is an ability by every other measure in
      -- this component, but it goes out as its own command word and nobody
      -- has seen which message refuses one. Guessing it is the job
      -- ability's is the one thing this feature must not do.
      live()
      widget.handle_command({ "bind", "1L6", "pet", "Eclipse Bite", "t" })
      cast(DIK_SLOT[6])
      for _, message in ipairs({ 17, 18, 71, 72 }) do
        widget.update("chunk", 0x29, refusal(env.player.id, message))
      end
      env.now = env.now + 1
      widget.update()
      assert.are.same({ 'input /pet "Eclipse Bite" <t>' }, env.commands)
    end)

    it("re-sends a pet-targeted action as it was written", function()
      -- `<pet>` is a valid bind target and names something no cursor and no
      -- roster can move, so there is nothing to pin and the re-send is the
      -- press verbatim - the same treatment `<me>` gets.
      live()
      widget.handle_command({ "bind", "1L6", "ma", "Cure", "pet" })
      cast(DIK_SLOT[6])
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      env.target = { id = 4242 }
      widget.update()
      assert.are.same({ 'input /ma "Cure" <pet>', 'input /ma "Cure" <pet>' }, env.commands)
    end)

    it("does not watch a cast aimed at a party or alliance slot", function()
      -- A party position is whoever is standing there: a member leaving or
      -- zoning inside the deadline shifts everyone below them, so a re-send
      -- can land on a different person. We cannot pin it, so we do not hold
      -- it at all.
      live()
      for _, target in ipairs({ "p2", "a13", "a24" }) do
        widget.handle_command({ "bind", "1L6", "ma", "Cure", target })
        env.commands = {}
        cast(DIK_SLOT[6])
        widget.update("chunk", 0x29, refusal(env.player.id))
        env.now = env.now + 1
        widget.update()
        assert.are.same({ 'input /ma "Cure" <' .. target .. ">" }, env.commands, target)
      end
    end)

    it("is replaced outright by a newer press", function()
      live()
      cast()
      widget.update("chunk", 0x29, refusal(env.player.id))
      cast(PROVOKE_SLOT)
      env.now = 1
      widget.update()
      assert.are.same({ CURE, PROVOKE }, env.commands, "the moment the cast belonged to has passed")
    end)

    it("is dropped by a press of an empty slot", function()
      -- Any newer slot press replaces what is held outright, and a press
      -- that turned out to be bound to nothing is still a press.
      live()
      refused()
      press(LEFT)
      press(DIK_SLOT[1])
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    it("never holds an action blocked by a recast", function()
      -- The defect that made the reference addon's queue unusable.
      live()
      refused()
      env.spell_recasts = { [1] = 300 }
      widget.update()
      assert.are.same({ CURE }, env.commands)
      env.spell_recasts = {}
      env.now = env.now + 1
      widget.update()
      assert.are.same({ CURE }, env.commands, "and it is dropped, not waiting for the recast")
    end)

    it("drops a cast there is no longer the MP for", function()
      live()
      refused()
      env.player.vitals = { mp = 2, tp = 1000 }
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    it("drops a cast while silenced", function()
      live()
      refused()
      env.player.buffs = { 6 }
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    it("re-sends at the target it was pressed against, however far the cursor has gone", function()
      -- The point of the whole feature: fire what you meant at what you
      -- meant it for. The first send goes out with the token exactly as
      -- ever; only the re-send names the id the token stood for at the
      -- press, so tabbing away in between changes nothing.
      live()
      cast()
      assert.are.same({ CURE }, env.commands, "the first send is untouched")
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      env.target = { id = 4242 }
      widget.update()
      assert.are.same({ CURE, 'input /ma "Cure" 99' }, env.commands)
    end)

    it("pins the token the record was bound with, not always <t>", function()
      -- `<bt>` and `<t>` are different selections; a bt-aimed spell must
      -- carry the battle target's id, not the cursor's.
      live()
      env.targets = { t = { id = 7 }, bt = { id = 99 } }
      widget.handle_command({ "bind", "1L6", "ma", "Cure", "bt" })
      cast(DIK_SLOT[6])
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      widget.update()
      assert.are.same({ 'input /ma "Cure" <bt>', 'input /ma "Cure" 99' }, env.commands)
    end)

    it("re-sends a fixed-target cast as it was written", function()
      -- `<me>` names somebody the cursor cannot move, so there is nothing
      -- to pin and the re-send is the press verbatim.
      live()
      widget.handle_command({ "bind", "1L6", "ma", "Cure", "me" })
      cast(DIK_SLOT[6])
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      env.target = { id = 4242 }
      widget.update()
      assert.are.same({ 'input /ma "Cure" <me>', 'input /ma "Cure" <me>' }, env.commands)
    end)

    it("does not watch a cast it had nothing to pin", function()
      -- Pressed with nothing selected: there is no id for the re-send to
      -- carry, and re-resolving `<t>` later is the behaviour the pin exists
      -- to prevent.
      live()
      env.target = nil
      cast()
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      env.target = { id = 4242 }
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    it("does not watch a cast bound with no target word at all", function()
      -- The command carries no target to substitute, and appending one
      -- would send a shape the first press never used.
      live()
      widget.handle_command({ "bind", "1L6", "ma", "Cure" })
      cast(DIK_SLOT[6])
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      widget.update()
      assert.are.same({ 'input /ma "Cure"' }, env.commands)
    end)

    it("drops a cast whose slot no longer holds it", function()
      live()
      refused()
      -- Rebound out from under the press. The address is what the retry
      -- remembers, so what matters is the record living at it.
      widget.handle_command({ "bind", "1L5", "ma", "Dia", "t" })
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    it("drops on a job change the client has not caught up with yet", function()
      -- The window the existing loop case cannot reach: `job change`
      -- announces a job get_player() still disagrees with, so try_scope
      -- returns early and leaves the OLD job's bindings in place. `bound`
      -- therefore still answers true, and without the clear the previous
      -- job's spell re-sends under the new one.
      live()
      refused()
      widget.update("job change", 4, 99, 13, 49)
      assert.are.equal("WAR", widget.handle_command({})[1]:match("WAR") and "WAR" or "", "still scoped to the old job")
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    --[[ The detach case is here for completeness, not as a proof: the
         binding store deep-copies on load, so after a re-attach the `bound`
         guard drops the record whether or not detach cleared it. Only the
         zone, the two deaths and the hide are actually pinned by this, and
         the name says so. ]]
    it("drops on a zone, either death and a hide", function()
      local drops = {
        function()
          widget.update("chunk", 0x0B, "HDRX")
        end,
        function()
          widget.update("status", 2)
        end,
        function()
          -- Engaged dead: the common one, since you usually die fighting.
          -- Death is not a suppression trigger, so this clear is the only
          -- thing standing between a corpse and a re-sent cast.
          widget.update("status", 3)
        end,
        function()
          widget.hide()
          widget.show()
        end,
        function()
          widget.detach()
          widget.attach(config, function() end, store)
          widget.show()
        end,
      }
      for index, drop in ipairs(drops) do
        live()
        refused()
        drop()
        widget.update()
        assert.are.same({ CURE }, env.commands, "clear trigger " .. index)
      end
    end)

    it("re-sends only where a slot press would fire", function()
      -- The input machine refuses to act on a slot key while the chat box
      -- has focus, while layout mode owns the screen, or while the binder
      -- is up; a re-send is the same press arriving late and must obey the
      -- same three. Anything held when one of them opens is dropped.
      -- Each guard carries its own way back out: `edit` is a TOGGLE, so a
      -- shared undo would open edit mode for the two cases that never
      -- entered it and leave their second assertion unable to fail.
      local shut_out = {
        {
          name = "chat",
          shut = function()
            env.chat_open = true
          end,
          open = function()
            env.chat_open = false
          end,
        },
        {
          name = "layout mode",
          shut = function()
            env.layout = true
          end,
          open = function()
            env.layout = false
          end,
        },
        {
          name = "the binder",
          shut = function()
            widget.handle_command({ "edit" })
          end,
          open = function()
            widget.handle_command({ "edit" })
          end,
        },
      }
      for _, guard in ipairs(shut_out) do
        live()
        refused()
        guard.shut()
        widget.update()
        assert.are.same({ CURE }, env.commands, guard.name .. " shuts the re-send out")
        -- And it is dropped, not queued behind the guard.
        guard.open()
        env.now = env.now + 1
        widget.update()
        assert.are.same({ CURE }, env.commands, guard.name .. " dropped it rather than deferring it")
      end
    end)

    it("folds the case of a hand-edited target word", function()
      -- The CLI lowercases what it writes, but the config files are
      -- hand-editable and `target = "T"` fires in game exactly as `t`
      -- does. It must not be silently unwatched for the capital.
      live()
      store.load = function(name)
        if name ~= "WAR" then
          return env.store_files[name]
        end
        local data = env.store_files.WAR
        data.sets[1].left[5] = { type = "ma", action = "Cure", target = "T" }
        return data
      end
      widget.detach()
      widget.attach(config, function() end, store)
      widget.show()
      widget.update()
      cast()
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      widget.update()
      assert.are.same({ 'input /ma "Cure" <T>', 'input /ma "Cure" 99' }, env.commands)
    end)

    it("does not watch a cast whose target it cannot pin", function()
      -- `<stpc>` and the rest of the subtarget family are resolved by a
      -- cursor the player answers; a re-send would re-open it a second
      -- later. Nothing this widget cannot pin is retried at all.
      live()
      widget.handle_command({ "bind", "1L6", "ma", "Cure", "stpc" })
      cast(DIK_SLOT[6])
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      widget.update()
      assert.are.same({ 'input /ma "Cure" <stpc>' }, env.commands)
    end)

    it("does not read the target to pin while the feature is off", function()
      -- The pin is the one client read this feature adds, and the feature
      -- ships OFF: a player who never turns it on must not pay for it. The
      -- press itself already reads the target once (draw_state), so the
      -- measure is the difference between the two builds.
      build_world()
      assert.is_false(widget.defaults.retry.enabled, "the shipped posture")
      env.target_tokens = {}
      cast()
      local off = #env.target_tokens
      live()
      env.target_tokens = {}
      cast()
      assert.are.equal(off + 1, #env.target_tokens, "the pin is one extra read, and only when enabled")
    end)

    it("asks the client only for target tokens the repo already uses", function()
      live()
      env.target_tokens = {}
      widget.handle_command({ "bind", "1L6", "ma", "Cure", "bt" })
      cast(DIK_SLOT[6])
      cast()
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = env.now + 1
      widget.update()
      for _, token in ipairs(env.target_tokens) do
        assert.is_true(token == "t" or token == "bt", "unvetted target token asked of the client: " .. token)
      end
    end)

    it("drops a pending cast when the feature is switched off, rather than firing a last one", function()
      live()
      refused()
      local reply = widget.handle_command({ "retry", "off" })
      assert.is_not_nil(tostring(reply):find("off", 1, true), tostring(reply))
      widget.update()
      env.now = env.now + 5
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    it("forgets the cast it was watching the moment it is switched off", function()
      -- Not just the pending case: switching off drops what is merely being
      -- WATCHED too, so switching back on cannot resurrect a press made
      -- before the feature was live.
      live()
      cast()
      widget.handle_command({ "retry", "off" })
      widget.handle_command({ "retry", "on" })
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = 1
      widget.update()
      assert.are.same({ CURE }, env.commands)
    end)

    --[[ CB9 and CB10 both watch a press, and must never both claim the
         same one: a spell press is never a countdown, and a travel press
         drops what the retry was holding exactly as any other press does. ]]
    it("drops what it was watching when a travel press counts down instead", function()
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mr" }
      build_world({
        store_files = files,
        tune_config = function(tuned)
          tuned.retry.enabled = true
        end,
      })
      env.key_items = { 3000 }
      widget.update("chunk", 0x055)
      cast()
      cast(DIK_SLOT[2])
      assert.are.same({ CURE }, env.commands, "the travel press has fired nothing yet")
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = 2
      widget.update()
      assert.are.same({ CURE }, env.commands, "and the cure is not re-sent: a newer press replaced it")
      env.now = 5
      widget.update()
      assert.are.same({ CURE, 'input /mount "chocobo"' }, env.commands)
    end)

    it("never watches the countdown's own send", function()
      -- What fires five seconds late is a mount, not a spell, so a refusal
      -- arriving after it belongs to nobody here.
      local files = war_bindings()
      files.WAR.sets[1].left[2] = { type = "mr" }
      build_world({
        store_files = files,
        tune_config = function(tuned)
          tuned.retry.enabled = true
        end,
      })
      env.key_items = { 3000 }
      widget.update("chunk", 0x055)
      cast(DIK_SLOT[2])
      env.now = 5
      widget.update()
      assert.are.equal(1, #env.commands)
      widget.update("chunk", 0x29, refusal(env.player.id))
      env.now = 7
      widget.update()
      assert.are.equal(1, #env.commands, "nothing is re-sent")
    end)

    it("costs the settled tick nothing", function()
      -- The per-frame budget: with the feature on and nothing pending, the
      -- tick must be the same two identical frames it was without it.
      live()
      widget.update()
      local before = 0
      for _, prim in ipairs(prims.all) do
        before = before + #prim.calls
      end
      env.player_reads, env.spell_reads, env.ability_reads = 0, 0, 0
      -- get_info() is a client call like any other, and chat_open() is a
      -- wrapper over it: a settled frame with nothing pending must not ask.
      env.chat_reads, env.layout_reads = 0, 0
      widget.update()
      local after = 0
      for _, prim in ipairs(prims.all) do
        after = after + #prim.calls
      end
      assert.are.equal(before, after)
      assert.are.equal(0, env.player_reads + env.spell_reads + env.ability_reads, "and no client read of its own")
      assert.are.equal(0, env.chat_reads + env.layout_reads, "not even to ask whether chat is open")
    end)
  end)

  describe("commands", function()
    it("reports job, set, weapon state and views bare", function()
      build_world()
      local reply = widget.handle_command({})
      local text = table.concat(reply, "\n")
      assert.is_not_nil(text:find("WAR"), text)
      assert.is_not_nil(text:find("set 1"), text)
      assert.is_not_nil(text:find("sheathed"), text)
      assert.is_not_nil(text:find("wxhb%-L"), text)
    end)

    it("folds verb case like the rest of the framework", function()
      build_world()
      widget.handle_command({ "SET", "2" })
      assert.are.equal(2, env.store_files.WAR.active_set)
    end)

    it("switches sets with set <n> and validates it", function()
      build_world()
      widget.handle_command({ "set", "2" })
      assert.are.equal(2, env.store_files.WAR.active_set)
      local hint = widget.handle_command({ "set", "9" })
      assert.is_string(hint)
      hint = widget.handle_command({ "set" })
      assert.is_string(hint)
    end)

    it("advances the rotation with bare cycle and hints with args", function()
      build_world()
      local reply = widget.handle_command({ "cycle" })
      assert.are.equal(2, env.store_files.WAR.active_set)
      assert.is_not_nil(reply:find("2"), reply)
      local hint = widget.handle_command({ "cycle", "2", "drawn" })
      assert.is_string(hint)
      assert.are.equal(2, env.store_files.WAR.active_set, "the authoring overload must not advance")
    end)

    it("lists the open targets bare", function()
      build_world()
      local reply = widget.handle_command({ "open" })
      local text = table.concat(reply, "\n")
      assert.is_not_nil(text:find("equipment"), text)
      assert.is_not_nil(text:find("map"), text)
    end)

    it("composes setkey edges for a chord opener", function()
      build_world()
      widget.handle_command({ "open", "equipment" })
      assert.are.same({
        "setkey ctrl down",
        "setkey e down",
        "setkey e up",
        "setkey ctrl up",
      }, env.commands)
    end)

    it("matches open targets case-insensitively", function()
      build_world()
      widget.handle_command({ "open", "EQUIPMENT" })
      assert.are.equal("setkey ctrl down", env.commands[1], "the framework convention covers arguments too")
    end)

    it("hints on an unknown open target", function()
      build_world()
      local reply = widget.handle_command({ "open", "bogus" })
      assert.is_string(reply)
      assert.are.same({}, env.commands)
    end)

    it("rides mount roulette as a command", function()
      build_world()
      env.player.buffs = { 252 }
      widget.handle_command({ "mr" })
      assert.are.same({ "input /dismount" }, env.commands)
    end)

    it("runs the draw toggle as a command", function()
      build_world()
      widget.handle_command({ "draw" })
      assert.are.same({}, env.commands, "entering drawn sends nothing")
      assert.is_true(sword_icon().visible, "the sword is what says it worked")
      widget.handle_command({ "draw" })
      assert.are.same({ "input /attack off" }, env.commands)
    end)

    it("routes an authoring verb to the store and repaints the slot", function()
      build_world()
      local reply = widget.handle_command({ "bind", "1L1", "ja", "Berserk", "me" })
      assert.is_string(reply)
      assert.are.same({ type = "ja", action = "Berserk", target = "me" }, env.store_files.WAR.sets[1].left[1], reply)
      assert.are.equal("Berserk", text_of("xhb_left", 1, "name").last.text, "the bar shows the new binding")
      assert.is_nil(env.config_saves, "a binding write persists through the store, not the config")
    end)

    it("checks its built-in names against the authoring verbs at construction", function()
      -- actions.lua promises the check happens "at load, like the registry
      -- validates component names"; CB7 is what made the verb list
      -- available to check against. A collision is said, never thrown.
      build_world()
      assert.are.equal(0, #env.chat, "no collision today, and nothing said about it")
      local actions = require("components/crossbar/actions")({})
      local commands = require("components/crossbar/commands")({})
      assert.are.same({}, actions.check_collisions(commands.verbs()))
      -- The check is real: a verb that DID collide would be reported.
      assert.are.same({ "draw", "mr" }, actions.check_collisions({ "draw", "mr", "bind" }))
    end)

    it("reports each view once, from the CLI's own map", function()
      build_world()
      local text = table.concat(widget.handle_command({}), "\n")
      local commands = require("components/crossbar/commands")({})
      assert.are.equal(4, #commands.views)
      for _, view in ipairs(commands.views) do
        assert.is_not_nil(text:find(view.cli, 1, true), view.cli .. " missing from: " .. text)
      end
    end)

    it("checks a swallowed trailing word against the client's own resources", function()
      -- The CLI's second-guess runs on the live resource tables: "Savage
      -- Blade" is a weaponskill, "Savage Blade Kevin" is not, so the bind
      -- is refused rather than stored as a command that can never fire.
      build_world()
      local reply = widget.handle_command({ "bind", "1L1", "ws", "Savage", "Blade", "Kevin" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("Kevin", 1, true), reply)
      assert.is_nil(env.store_files.WAR.sets[1].left[1])
      -- And a name it does know binds with no caution at all.
      reply = widget.handle_command({ "bind", "1L1", "ws", "Savage", "Blade" })
      assert.is_string(reply, "a known name needs no second line")
      assert.equal("Savage Blade", env.store_files.WAR.sets[1].left[1].action)
    end)

    it("saves the component config when a verb changes it", function()
      build_world()
      local reply, _ = widget.handle_command({ "wxhb", "on" })
      assert.is_string(reply)
      assert.is_true(config.always_show_wxhb)
      assert.are.equal(1, env.config_saves)
    end)

    it("answers list and context as lines", function()
      build_world()
      for _, words in ipairs({ { "list" }, { "context", "list" }, { "help" } }) do
        local reply = widget.handle_command(words)
        assert.is_table(reply, words[1])
      end
      local text = table.concat(widget.handle_command({ "list" }), "\n")
      assert.is_not_nil(text:find("Savage Blade", 1, true), text)
    end)

    it("points an unknown verb at help, which really answers", function()
      -- The CLI's own "try //hud crossbar help" is unreachable: the widget
      -- routes on handles() first, so its hint is the only one an unknown
      -- verb ever sees.
      build_world()
      local reply = widget.handle_command({ "bogus" })
      assert.is_string(reply)
      assert.is_not_nil(reply:find("help", 1, true), reply)
      assert.is_table(widget.handle_command({ "help" }), "and help is a real verb")
    end)

    it("answers authoring verbs and unknown input with hints", function()
      build_world()
      for _, words in ipairs({ { "bind" }, { "edit" }, { "bogus" } }) do
        local reply = widget.handle_command(words)
        assert.is_string(reply, words[1])
        assert.are.same({}, env.commands, words[1])
      end
    end)
  end)

  -- CB8: the mouse-driven binder. The widget owns the toggle, the mouse
  -- dispatch and the teardown; binder.lua owns the surfaces themselves.
  describe("edit mode", function()
    local MOUSE_MOVE, MOUSE_LEFT_DOWN, MOUSE_LEFT_UP = 0, 1, 2

    -- The centre of a drawn slot, through the same geometry the bar uses.
    local function slot_point(side, slot)
      local render = require("components/crossbar/render")({
        config = config,
        icon_for = require("components/crossbar/actions")({}).icon_for,
      })
      local x, y = render.slot_pos("xhb", side, slot)
      local size = render.metrics().slot
      return 100 + x + size / 2, 900 + y + size / 2
    end

    local function click(x, y)
      widget.on_mouse(MOUSE_LEFT_DOWN, x, y, 0, false)
      return widget.on_mouse(MOUSE_LEFT_UP, x, y, 0, false)
    end

    --[[ The binder draws with prims like everything else in this widget, so
         its surfaces are read the same way the bar's are: by the text they
         put on screen. Its prims are built when edit mode opens, so they
         start after the widget's own 40 x 3, and a click two pixels inside
         a line's own origin lands in the row that line belongs to. ]]
    local WIDGET_TEXTS = 40 * 3

    local function binder_line(pattern)
      for index = WIDGET_TEXTS + 1, #prims.texts do
        local prim = prims.texts[index]
        if prim.visible and type(prim.last.text) == "string" and prim.last.text:find(pattern) then
          return prim
        end
      end
      return nil
    end

    local function click_line(pattern)
      local prim = binder_line(pattern)
      assert.is_not_nil(prim, "no binder line matching " .. pattern)
      return click(prim.x + 2, prim.y + 2)
    end

    it("toggles with the edit verb and says which way it went", function()
      build_world()
      local on = widget.handle_command({ "edit" })
      assert.is_string(on)
      assert.is_not_nil(on:lower():find("on", 1, true), on)
      local off = widget.handle_command({ "edit" })
      assert.is_not_nil(off:lower():find("off", 1, true), off)
      assert.are.same({}, env.commands, "the binder fires nothing at the game")
    end)

    it("refuses to open with no job scoped and no bar to hide behind", function()
      build_world({ player = { id = 1, buffs = {}, vitals = {} } })
      local reply = widget.handle_command({ "edit" })
      assert.is_not_nil(reply:lower():find("job", 1, true), reply)
      build_world()
      widget.hide()
      reply = widget.handle_command({ "edit" })
      assert.is_not_nil(reply:lower():find("hidden", 1, true), reply)
    end)

    it("refuses to open while layout mode owns the mouse", function()
      build_world()
      env.layout = true
      local reply = widget.handle_command({ "edit" })
      assert.is_not_nil(reply:lower():find("layout", 1, true), reply)
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, slot_point("left", 3)))
    end)

    it("stands down when layout mode takes over", function()
      -- Core calls set_preview(true) on every component as layout mode
      -- opens; the two must never contend for the mouse.
      build_world()
      widget.handle_command({ "edit" })
      widget.set_preview(true)
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, slot_point("left", 3)))
      local reply = widget.handle_command({ "edit" })
      assert.is_not_nil(reply:lower():find("on", 1, true), "and it really was off: " .. reply)
    end)

    it("toggles from the shortcut chord and exits on any press of that key", function()
      -- CB8 retires the "binder not yet available" placeholder: the Select
      -- chord is the pad's way into the binder, and while edit mode is on
      -- ANY press of that key is the way out.
      build_world()
      press(LEFT)
      press(SHORTCUT)
      assert.is_not_nil(said():lower():find("edit mode on"), "said: " .. said())
      release(SHORTCUT)
      release(LEFT)
      env.chat = {}
      press(SHORTCUT)
      assert.is_not_nil(said():lower():find("edit mode off"), "a bare tap exits: " .. said())
    end)

    it("fires nothing from a slot key while the binder is open", function()
      build_world()
      widget.handle_command({ "edit" })
      assert.is_true(press(LEFT), "the five dedicated keys stay ours - an unblocked side key opens the chat log")
      assert.is_false(press(DIK_SLOT[3]), "slot keys fall through to the game in edit mode")
      assert.are.same({}, env.commands, "the crossbar's own keys are inert in edit mode")
    end)

    it("leaves the mouse alone until it is open", function()
      build_world()
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, slot_point("left", 3)), "the game's click")
      assert.is_false(widget.on_mouse(MOUSE_MOVE, slot_point("left", 3)))
    end)

    it("takes a slot click through the framework's mouse dispatch", function()
      build_world()
      widget.handle_command({ "edit" })
      local x, y = slot_point("left", 3)
      assert.is_true(click(x, y), "the binder claims the click")
      assert.is_false(click(4, 4), "and hands back what is not on one of its surfaces")
    end)

    it("binds by mouse into the layer the stack panel names", function()
      build_world()
      env.known_spells = { [1] = true }
      widget.handle_command({ "edit" })
      click(slot_point("left", 1))
      local rows = widget.handle_command({ "list" })
      assert.is_table(rows, "the CLI still answers with the binder up")
      -- Slot 1 left of set 1 is empty in the fixture; bind Cure into the
      -- base layer by walking the window's three steps.
      assert.is_not_nil(binder_line("^1L1"), "the click opened the window on step one")
      click_line("base:")
      assert.is_not_nil(binder_line("^pick an action"), "step two, behind the layer row")
      click_line("^Cure$")
      -- A spell takes a target, so the third step asks for one; the first
      -- row binds none, which is what a mouse bind produced before it
      -- existed.
      assert.is_not_nil(binder_line("^pick a target"), "step three")
      click_line("^%(no target%)$")
      assert.are.same(
        { type = "ma", action = "Cure" },
        env.store_files.WAR.sets[1].left[1],
        "written through the same store the CLI writes"
      )
      assert.are.equal("Cure", text_of("xhb_left", 1, "name").last.text, "and the bar repainted")
    end)

    it("tags each slot with the layer its winner came from", function()
      local files = war_bindings()
      files.WAR.sub = { NIN = { [1] = { left = { [4] = { type = "ja", action = "Berserk" } } } } }
      build_world({ store_files = files })
      env.player.buffs = { 358 }
      widget.update("gain buff", 358)
      assert.are.equal("Penury", text_of("xhb_left", 2, "name").last.text, "the live context wins")
      widget.handle_command({ "edit" })
      assert.are.equal("* Penury", text_of("xhb_left", 2, "name").last.text, "a context is marked")
      assert.are.equal("+ Berserk", text_of("xhb_left", 4, "name").last.text, "a subjob layer another way")
      assert.are.equal("Cure", text_of("xhb_left", 5, "name").last.text, "and the job base wears nothing")
      widget.handle_command({ "edit" })
      assert.are.equal("Cure", text_of("xhb_left", 5, "name").last.text, "the tags leave with edit mode")
    end)

    it("previews a context's world without touching the live buff state", function()
      build_world()
      widget.handle_command({ "edit" })
      click(slot_point("left", 2))
      click_line("light%-arts:")
      assert.are.equal("* Penury", text_of("xhb_left", 2, "name").last.text, "the bar is that layer's world")
      widget.handle_command({ "edit" })
      assert.are.equal("", text_of("xhb_left", 2, "name").last.text, "and the live state - an empty slot - comes back")
    end)

    it("holds the preview through a live buff event, and re-reads the client on the way out", function()
      -- The preview and the live buff sync write the same model state, so
      -- one of them has to own it: a buff landing mid-preview must not
      -- silently revert the bar while the header still says LIGHT ARTS.
      build_world()
      widget.handle_command({ "edit" })
      click(slot_point("left", 2))
      click_line("light%-arts:")
      assert.are.equal("* Penury", text_of("xhb_left", 2, "name").last.text)
      env.player.buffs = { 359 }
      widget.update("gain buff", 359)
      assert.are.equal("* Penury", text_of("xhb_left", 2, "name").last.text, "the preview survived the buff")
      assert.is_not_nil(binder_line("viewing: LIGHT ARTS"), "and the header still means it")
      widget.handle_command({ "edit" })
      assert.are.equal("", text_of("xhb_left", 2, "name").last.text, "leaving re-reads the client, not a stale list")
    end)

    it("re-reads the client's buffs after a preview even when nothing else changed", function()
      -- The handover is the only place the live list is re-read, so it has
      -- to read it fresh rather than replay whatever it saw at open.
      local files = war_bindings()
      files.WAR.contexts["dark-arts"] = { [1] = { left = { [5] = { type = "ja", action = "Berserk" } } } }
      build_world({ store_files = files })
      widget.handle_command({ "edit" })
      click(slot_point("left", 2))
      click_line("light%-arts:")
      env.player.buffs = { 359 }
      widget.update("gain buff", 359)
      widget.handle_command({ "edit" })
      assert.are.equal("Berserk", text_of("xhb_left", 5, "name").last.text, "dark arts really is up now")
    end)

    it("keeps a resting details column's recast moving from the tick", function()
      -- The column is filled on a mouse move, but a recast counts down
      -- whether or not the cursor does anything.
      build_world()
      env.ability_recasts[5] = 30
      widget.handle_command({ "edit" })
      -- The column lives in the window, so a slot has to be open for there
      -- to be anywhere to draw it.
      click(slot_point("left", 1))
      widget.on_mouse(MOUSE_MOVE, slot_point("left", 4))
      assert.is_not_nil(binder_line("recast: 30s left"), "the column filled in on the hover")
      env.ability_recasts[5] = 9
      env.now = env.now + 1
      widget.update()
      assert.is_not_nil(binder_line("recast: 9s left"), "and counts down though the cursor never moved")
    end)

    it("still cycles and jumps sets while the binder is up", function()
      --[[ Edit mode makes the bar inert to SIDES and slots, but the set is
           what you are choosing to edit (Kevin, live client, 2026-08-22):
           binding across eight sets without leaving edit mode to change
           which one is on screen is the whole point of the mode. ]]
      local files = war_bindings()
      files.WAR.sets[2] = { left = { [1] = { type = "ja", action = "Berserk" } } }
      build_world({ store_files = files })
      widget.handle_command({ "edit" })
      local function active_set()
        return tonumber(tostring(widget.handle_command({})[1]):match("set (%d+)"))
      end
      assert.are.equal(1, active_set())
      press(SWITCH)
      release(SWITCH)
      assert.are.equal(2, active_set(), "the tap cycled")
      press(SWITCH)
      press(DIK_SLOT[1])
      release(DIK_SLOT[1])
      release(SWITCH)
      assert.are.equal(1, active_set(), "and the chord jumped back")
    end)

    it("saves the binder window's position into the component's own config", function()
      --[[ Edit-mode furniture, so it lives beside the other preferences
           rather than in a framework layout slot - those are for placed
           widget anchors, and the binder is not one. ]]
      build_world()
      widget.handle_command({ "edit" })
      click(slot_point("left", 3))
      -- The title sits in the drag strip, so its own prim is both the
      -- handle to grab and the marker for where the window ended up.
      local title = binder_line("^pick a layer")
      assert.is_not_nil(title)
      local from_x, from_y = title.x + 10, title.y
      local before = env.config_saves or 0
      widget.on_mouse(MOUSE_LEFT_DOWN, from_x, from_y, 0, false)
      widget.on_mouse(MOUSE_MOVE, from_x - 300, from_y - 100, 0, false)
      widget.on_mouse(MOUSE_LEFT_UP, from_x - 300, from_y - 100, 0, false)
      assert.is_table(config.binder_pos, "written to the component's own config")
      assert.is_true((env.config_saves or 0) > before, "and the config was saved")
      local moved = binder_line("^pick a layer")
      assert.are.same({ from_x - 310, from_y - 100 }, { moved.x, moved.y }, "the window went with the cursor")

      -- Closing and reopening edit mode reads it back rather than
      -- recentring.
      widget.handle_command({ "edit" })
      widget.handle_command({ "edit" })
      click(slot_point("left", 3))
      local reopened = binder_line("^pick a layer")
      assert.are.same({ from_x - 310, from_y - 100 }, { reopened.x, reopened.y })
    end)

    it("puts the window away when a JOB CHANGE moves the set under it", function()
      --[[ The fourth producer of an active-set change, and the one that
           was missed: `set_job` reloads `active_set` from the incoming
           job's own file, so a job change usually lands on a different
           set. The window kept the address it was opened on, and the next
           bind would have written into that set of the NEW job's file. ]]
      local files = {
        WAR = { active_set = 3, sets = { [3] = { left = { [4] = { type = "ja", action = "Berserk" } } } } },
        NIN = { active_set = 1, sets = { [1] = { left = { [4] = { type = "ma", action = "Utsusemi: Ichi" } } } } },
      }
      build_world({ store_files = files })
      widget.handle_command({ "edit" })
      click(slot_point("left", 4))
      assert.is_not_nil(binder_line("^3L4"), "open on the job's own set")

      env.player = war_player()
      env.player.main_job = "NIN"
      env.player.main_job_id = 13
      env.player.sub_job_id = 49
      widget.update("job change", 13, 99, 49, 49)
      widget.update()
      assert.is_nil(binder_line("^3L4"), "the window went with the set")
    end)

    it("leaves the window alone when the set did not actually move", function()
      -- `jump` answers the set it was given whether or not that was already
      -- the one on screen, so "it answered" is not "it changed" - and
      -- dismissing the window for a no-op is a click the player has to
      -- redo for nothing.
      build_world()
      widget.handle_command({ "edit" })
      click(slot_point("left", 3))
      assert.is_not_nil(binder_line("^1L3"))
      widget.handle_command({ "set", "1" })
      assert.is_not_nil(binder_line("^1L3"), "already on set 1, so nothing moved")
    end)

    it("puts the window away when the set changes from the COMMAND LINE too", function()
      --[[ The CLI stays live in edit mode, and `set`/`cycle` repainted
           without deselecting - so the window went on showing the address
           it was opened on while the bar showed another set, and the next
           bind wrote where the player was no longer looking. Exactly the
           failure the keyboard path's deselect was added for; only the
           keyboard path had it. ]]
      local files = war_bindings()
      files.WAR.sets[2] = { left = { [1] = { type = "ja", action = "Berserk" } } }
      build_world({ store_files = files })
      widget.handle_command({ "edit" })
      click(slot_point("left", 3))
      assert.is_not_nil(binder_line("^1L3"), "a window is open on set 1")
      widget.handle_command({ "set", "2" })
      assert.is_nil(binder_line("^1L3"), "the window went away with the set")

      -- And the same for the bare `cycle` overload.
      click(slot_point("left", 3))
      assert.is_not_nil(binder_line("^2L3"), "reopened on the new set")
      widget.handle_command({ "cycle" })
      assert.is_nil(binder_line("^2L3"), "cycle deselects as well")
    end)

    it("puts an open binder window away when the set changes under it", function()
      --[[ The window remembers the address it was opened on, so a set
           change with one open would write the next bind into a set the
           player is no longer looking at. Edit mode itself stays on -
           changing set is how you bind across several without leaving. ]]
      local files = war_bindings()
      files.WAR.sets[2] = { left = { [1] = { type = "ja", action = "Berserk" } } }
      build_world({ store_files = files })
      widget.handle_command({ "edit" })
      click(slot_point("left", 3))
      assert.is_not_nil(binder_line("^1L3"), "a window is open on set 1")
      press(SWITCH)
      release(SWITCH)
      assert.is_nil(binder_line("^1L3"), "the window went away with the set")
      assert.is_not_nil(widget.handle_command({ "edit" }), "and edit mode is still on to be turned off")
    end)

    it("clears the held side when edit mode opens", function()
      --[[ Edit mode is entered by holding a side and pressing Select, so
           the side that opened it was lit at the moment the display froze
           and stayed lit for as long as the mode was on - long after the
           key was released (Kevin, live client, 2026-08-22). Sides are
           inert in edit mode, so a lit one says something untrue. ]]
      build_world()
      press(LEFT)
      assert.is_true(prims.images[1].visible, "the side panel is up before the mode opens")
      widget.handle_command({ "edit" })
      assert.is_false(prims.images[1].visible, "and down as it opens, held or not")
      release(LEFT)
      assert.is_false(prims.images[1].visible)
    end)

    it("holds the bar still while the binder is up", function()
      -- The input machine keeps tracking every key (CB0's contract), but
      -- the widget stops reacting: the wiki's reading is that no side
      -- activates in edit mode, and a bar that swapped itself for the
      -- Expanded view would move the slots out from under an open panel.
      build_world()
      widget.handle_command({ "edit" })
      click(slot_point("left", 3))
      press(LEFT)
      press(RIGHT)
      assert.is_true(image_of("xhb_left", 1, "background").visible, "the XHB stays up")
      assert.is_false(image_of("expanded", 1, "background").visible, "Expanded never replaces it")
      assert.is_false(prims.images[1].visible, "and no side panel lights")
      click(slot_point("left", 4))
      assert.is_not_nil(binder_line("^1L4"), "the slots stayed put under the cursor")
    end)

    it("resyncs the bar to the keys really held when edit mode ends", function()
      build_world()
      widget.handle_command({ "edit" })
      press(LEFT)
      widget.handle_command({ "edit" })
      assert.is_true(prims.images[1].visible, "the side held through edit mode is panelled on the way out")
      release(LEFT)
      assert.is_false(prims.images[1].visible)
    end)

    it("keeps a previewed context through a job change", function()
      build_world()
      widget.handle_command({ "edit" })
      click(slot_point("left", 2))
      click_line("light%-arts:")
      assert.are.equal("* Penury", text_of("xhb_left", 2, "name").last.text)
      -- Same main job, a new subjob: the model reloads and clears its
      -- active contexts, so the preview has to be re-asserted or the bar
      -- reverts under a header still claiming the simulated view.
      env.player.sub_job, env.player.sub_job_id = "WAR", 2
      widget.update("job change", 1, 99, 2, 49)
      assert.are.equal("* Penury", text_of("xhb_left", 2, "name").last.text, "the preview survived the job change")
      assert.is_not_nil(binder_line("viewing: LIGHT ARTS"))
      widget.handle_command({ "edit" })
      assert.are.equal("", text_of("xhb_left", 2, "name").last.text, "and the client's own state comes back")
    end)

    it("shows every empty slot while the binder is up, whatever the config says", function()
      -- An invisible slot is still a drop target, which is the one thing
      -- edit mode cannot have.
      build_world({
        tune_config = function(tuned)
          tuned.hide.empty_slots = true
        end,
      })
      assert.is_false(image_of("xhb_left", 8, "background").visible, "hidden in play")
      widget.handle_command({ "edit" })
      assert.is_true(image_of("xhb_left", 8, "background").visible, "and back for the binder")
      widget.handle_command({ "edit" })
      assert.is_false(image_of("xhb_left", 8, "background").visible)
    end)

    it("draws both WXHB halves so every side can be edited", function()
      build_world()
      widget.set_pos(400, 100, "wxhb_left")
      widget.set_pos(800, 100, "wxhb_right")
      assert.is_false(image_of("wxhb_left", 1, "background").visible)
      widget.handle_command({ "edit" })
      assert.is_true(image_of("wxhb_left", 1, "background").visible, "all sides render in edit mode")
      assert.is_true(image_of("wxhb_right", 1, "background").visible)
    end)

    it("tears the binder down on hide, detach and destroy", function()
      build_world()
      widget.handle_command({ "edit" })
      local built = #prims.all
      widget.hide()
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, slot_point("left", 3)), "a hidden crossbar has no binder")
      widget.show()
      widget.handle_command({ "edit" })
      widget.detach()
      assert.is_false(widget.on_mouse(MOUSE_LEFT_DOWN, slot_point("left", 3)))
      assert.is_true(#prims.all > built, "the binder really did build prims")
      widget.destroy()
      for _, prim in ipairs(prims.all) do
        assert.are.equal(1, prim.destroyed, "every prim, the binder's included")
      end
    end)
  end)
end)
