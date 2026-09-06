local new_slot = require("lib/actionbar/slot")
local new_render = require("lib/actionbar/render")
local fakes = require("tests/support/fakes")

local function world(overrides)
  local env = {
    config = {
      slot_alpha = 100,
      disabled_alpha = 60,
      feedback = { alpha = 150, speed = 30 },
      font = "serif",
      font_size = 7,
      text_color = { a = 255, r = 255, g = 255, b = 255 },
      text_stroke = { width = 2, a = 200, r = 20, g = 20, b = 20 },
      hide = {},
    },
    screen_width = 1920,
  }
  for key, value in pairs(overrides or {}) do
    env[key] = value
  end
  local prims = fakes.prims()
  local render = new_render({ config = env.config })
  local slot = new_slot({
    new_image = prims.new_image,
    new_text = prims.new_text,
    asset = function(path)
      return "addon/" .. path
    end,
    config = function()
      return env.config
    end,
    render = function()
      return render
    end,
    screen_width = function()
      return env.screen_width
    end,
    hide = function(key)
      return env.config.hide[key] == true
    end,
    key = "xhb_left:3",
  })
  return slot, prims, env, render
end

local function paint(slot, record, meta, opts)
  opts = opts or {}
  opts.resolve_icon = opts.resolve_icon
    or function()
      return { path = "assets/icons/x.png", offset = { x = 4, y = 4 } }
    end
  return slot.paint(record, meta, opts)
end

local function facts(overrides)
  local f = {
    player = { main_job = "WAR", sub_job = "NIN" },
    vitals = { mp = 100, tp = 1000 },
    spell_recasts = {},
    ability_recasts = {},
    chain_step = nil,
    counter = function()
      return nil
    end,
    chain_result = function()
      return nil
    end,
    mount = function()
      return nil
    end,
  }
  for key, value in pairs(overrides or {}) do
    f[key] = value
  end
  return f
end

describe("one slot", function()
  it("builds its nine prims in z-order, hidden, and destroys them all", function()
    local slot, prims = world()
    local kinds = {}
    for _, prim in ipairs(prims.all) do
      kinds[#kinds + 1] = prim.kind
    end
    assert.are.same({ "image", "image", "image", "image", "image", "image", "text", "text", "text" }, kinds)
    assert.are.equal("addon/assets/own/slot.png", prims.images[1].last.path)
    assert.are.equal("addon/assets/own/frame.png", prims.images[5].last.path)
    assert.are.equal("addon/assets/own/feedback.png", prims.images[6].last.path)
    for _, prim in ipairs(prims.all) do
      assert.is_false(prim.visible)
    end
    assert.are.equal(prims.images[3], slot.prims.icon)
    slot.destroy()
    for _, prim in ipairs(prims.all) do
      assert.are.equal(1, prim.destroyed)
    end
  end)

  it("dresses its texts and alphas from the live config", function()
    local slot, prims = world()
    slot.dress()
    assert.are.equal(100, prims.images[1].last.alpha, "the background carries slot_alpha")
    local name = prims.texts[1]
    assert.are.equal("serif", name.last.font)
    assert.are.equal(2, name.last.stroke_width)
    assert.is_false(name.last.bg_visible)
    assert.is_false(name.last.right_justified)
    assert.is_true(prims.texts[2].last.right_justified, "cost hangs off the right")
  end)

  it("places every prim from the anchor origin and scale, texts off the screen edge", function()
    local slot, prims = world()
    paint(slot, { type = "ma", action = "Cure" }, { kind = "spell" })
    slot.place(100, 900, 30, 35, 2)
    assert.are.same({ 160, 970 }, { prims.images[1].x, prims.images[1].y })
    assert.are.same({ 80, 80 }, { prims.images[1].width, prims.images[1].height })
    assert.are.same({ 168, 978 }, { prims.images[3].x, prims.images[3].y }, "the icon carries its candidate's offset")
    assert.are.same({ 64, 64 }, { prims.images[3].width, prims.images[3].height })
    local cost = prims.texts[2]
    assert.are.equal(100 + (30 + 16 + 30) * 2 - 1920, cost.x, "right-justified: screen width off after scaling")
    assert.are.equal(14, cost.font_size)
  end)

  it("paints a record's label and icon, and clears them for an empty slot", function()
    local slot, prims = world()
    paint(slot, { type = "ma", action = "Utsusemi: Ichi" }, { kind = "spell" })
    assert.are.equal("Utsusem.", prims.texts[1].last.text)
    assert.are.equal("addon/assets/icons/x.png", prims.images[3].last.path)
    assert.are.equal("Utsusemi: Ichi", slot.record().action)
    assert.is_true(slot.icon_found())
    paint(slot, nil, nil)
    assert.are.equal("", prims.texts[1].last.text)
    assert.is_nil(slot.record())
    assert.is_false(slot.icon_found())
  end)

  it("prefixes the edit-mode source mark after the cut, and prefers the alias", function()
    local slot, prims = world()
    paint(slot, { type = "ma", action = "Utsusemi: Ichi", alias = "Shadows" }, {}, { mark = "s" })
    assert.are.equal("s Shadows", prims.texts[1].last.text)
  end)

  it("resolves the icon once per record and again when the override or the builtin moves", function()
    local slot = world()
    local asked = 0
    local resolve = function()
      asked = asked + 1
      return nil
    end
    local record = { type = "ma", action = "Cure" }
    paint(slot, record, {}, { resolve_icon = resolve })
    paint(slot, record, {}, { resolve_icon = resolve })
    assert.are.equal(1, asked, "a settled repaint stats nothing")
    record.icon = "spells/00001"
    paint(slot, record, {}, { resolve_icon = resolve })
    assert.are.equal(2, asked, "the override changed under the same record")
    paint(slot, record, {}, { resolve_icon = resolve, builtin = "attack" })
    assert.are.equal(3, asked, "and so did the builtin's state-dependent art")
  end)

  it("queues an item icon it does not have and repaints while it waits", function()
    local slot = world()
    local requested = {}
    paint(slot, { type = "item", action = "Potion" }, { kind = "item", item_id = 4112 }, {
      item_icon = function(id)
        requested[#requested + 1] = id
        return "awaiting"
      end,
    })
    assert.are.same({ 4112 }, requested)
    assert.is_true(slot.awaiting_item_icon())
    local asked = 0
    paint(slot, slot.record(), slot.meta(), {
      item_icon = function()
        return nil
      end,
      resolve_icon = function()
        asked = asked + 1
        return nil
      end,
    })
    assert.are.equal(1, asked, "still awaiting, so the candidates are walked again")
    assert.is_false(slot.awaiting_item_icon())
  end)

  it("shows the static prims for a drawn slot and takes the dynamic ones down when hidden", function()
    local slot, prims = world()
    paint(slot, { type = "ma", action = "Cure" }, { kind = "spell", mp_cost = 8 })
    slot.tick(facts())
    slot.show(true, true)
    assert.is_true(prims.images[1].visible, "background")
    assert.is_true(prims.images[3].visible, "icon")
    assert.is_true(prims.texts[1].visible, "name")
    assert.is_true(prims.texts[2].visible, "cost, pushed by the tick")
    slot.show(false, false)
    for _, prim in ipairs(prims.all) do
      assert.is_false(prim.visible)
    end
  end)

  it("keeps the name down under hide.action_name and the icon down under a chain result", function()
    local slot, prims, env = world()
    env.config.hide.action_name = true
    paint(slot, { type = "ws", action = "Savage Blade" }, { kind = "ws", ws_id = 42 })
    slot.tick(facts({
      chain_step = 3,
      chain_result = function()
        return "Fusion"
      end,
    }))
    slot.show(true, true)
    assert.is_false(prims.texts[1].visible)
    assert.is_false(prims.images[3].visible, "the chain icon owns the slot")
    assert.is_true(prims.images[2].visible)
    assert.are.equal("addon/assets/icons/skillchain/fusion.png", prims.images[2].last.path)
    assert.are.equal("addon/assets/own/frame_step3.png", prims.images[5].last.path)
  end)

  it("forgets its content on reset, sweep maximum included", function()
    local slot, prims, _, render = world()
    paint(slot, { type = "ma", action = "Cure" }, { kind = "spell", recast_id = 1 })
    slot.tick(facts({ spell_recasts = { [1] = 60 * 100 } }))
    slot.reset()
    assert.is_nil(slot.record())
    assert.are.equal(32, render.sweep("xhb_left:3", 10), "the maximum was forgotten with the content")
    assert.is_false(slot.awaiting_item_icon())
    assert.is_not_nil(prims.texts[1])
  end)

  describe("the tick", function()
    it("prices the cost corner and dims what the vitals cannot afford", function()
      local slot, prims = world()
      paint(slot, { type = "ma", action = "Cure IV" }, { kind = "spell", mp_cost = 88 })
      slot.tick(facts({ vitals = { mp = 40 } }))
      assert.are.equal("88", prims.texts[2].last.text)
      assert.are.equal(60, prims.images[3].last.alpha, "dimmed to disabled_alpha")
      slot.tick(facts({ vitals = { mp = 100 } }))
      assert.are.equal(255, prims.images[3].last.alpha)
    end)

    it("draws a counter over the cost, and the red X when its zero is trustworthy", function()
      local slot, prims = world()
      paint(slot, { type = "item", action = "Potion" }, { kind = "item", item_id = 4112, mp_cost = 0 })
      slot.tick(facts({
        counter = function()
          return { text = "0", color = { 255, 255, 255 }, zero = true }
        end,
      }))
      assert.are.equal("0", prims.texts[2].last.text)
      assert.are.equal("addon/assets/own/red-x.png", prims.images[4].last.path)
      assert.is_true(prims.images[4].visible)
      assert.are.equal(60, prims.images[3].last.alpha)
    end)

    it("sweeps and labels a recast, in the client's own units", function()
      local slot, prims = world()
      paint(slot, { type = "ma", action = "Cure" }, { kind = "spell", recast_id = 1 })
      slot.tick(facts({ spell_recasts = { [1] = 60 * 90 } }))
      assert.are.equal("1m", prims.texts[3].last.text)
      assert.is_true(prims.texts[3].visible)
      assert.are.equal("addon/assets/cooldown/frame_32.png", prims.images[4].last.path)
      slot.tick(facts({ spell_recasts = { [1] = 60 * 45 } }))
      assert.are.equal("45s", prims.texts[3].last.text)
      assert.are.equal("addon/assets/cooldown/frame_16.png", prims.images[4].last.path)
      slot.tick(facts())
      assert.is_false(prims.images[4].visible)
      assert.is_false(prims.texts[3].visible)
    end)

    it("dims a mount the zone refuses and sweeps its own recast", function()
      local slot, prims = world()
      paint(slot, { type = "mr" }, nil)
      slot.tick(facts({
        mount = function()
          return { blocked = true, cooldown = 30 }
        end,
      }))
      assert.are.equal(60, prims.images[3].last.alpha)
      assert.are.equal("30s", prims.texts[3].last.text)
    end)

    it("walks the press flash down and puts it away", function()
      local slot, prims = world()
      paint(slot, { type = "ma", action = "Cure" }, {})
      slot.flash()
      assert.is_true(prims.images[6].visible)
      assert.are.equal(150, prims.images[6].last.alpha)
      slot.tick(facts())
      assert.are.equal(120, prims.images[6].last.alpha)
      for _ = 1, 5 do
        slot.tick(facts())
      end
      assert.is_false(prims.images[6].visible)
    end)

    it("takes everything dynamic down for an empty slot", function()
      local slot, prims = world()
      paint(slot, { type = "ma", action = "Cure" }, { kind = "spell", mp_cost = 8 })
      slot.tick(facts())
      assert.is_true(prims.texts[2].visible)
      paint(slot, nil, nil)
      slot.tick(facts())
      assert.is_false(prims.texts[2].visible)
      assert.is_false(prims.images[4].visible)
      assert.are.equal("addon/assets/own/frame.png", prims.images[5].last.path)
    end)
  end)
end)
