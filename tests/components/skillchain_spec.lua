local new_skillchain = require("components/skillchain/skillchain")
local fakes = require("tests/support/fakes")

-- A weaponskill landing on the target, as the entry point's parse hands it
-- to the service: Dragon Kick (8) opens Fragmentation with a 3s delay.
local function ws_act(ws_id)
  return {
    category = 3,
    param = ws_id,
    actor_id = 1234,
    targets = { { id = 99, actions = { { message = 185 } } } },
  }
end

describe("the skillchain indicator", function()
  local env, ctx, prims, widget, service

  local function build(opts)
    opts = opts or {}
    env = { now = 0, target = { id = 99, hpp = 75 }, player = { id = 777, buffs = {} } }
    prims = fakes.prims()
    ctx = {
      screen = function()
        return 1920, 1080
      end,
      new_image = prims.new_image,
      new_text = prims.new_text,
      asset = function(path)
        return "addon/" .. path
      end,
      now = function()
        return env.now
      end,
      get_player = function()
        return env.player
      end,
      get_mob_by_target = function()
        return env.target
      end,
    }
    if not opts.no_service then
      ctx.actions = fakes.action_service(ctx)
      service = ctx.actions
    end
    widget = new_skillchain(ctx)
    widget.attach(widget.defaults)
    widget.set_pos(1000, 500)
    widget.set_scale(1)
    widget.show()
  end

  local function open_chain()
    service.on_chunk(0x028, "raw action bytes", ws_act(8))
  end

  local function tick()
    service.tick()
    widget.update()
  end

  it("is a single-anchor widget named for its engine, with the crossbar's old alias", function()
    build()
    assert.are.equal("skillchain", widget.name)
    assert.are.equal("sc", widget.alias)
    assert.is_nil(widget.anchors)
    assert.is_nil(widget.handle_command, "on/off is the framework's, the colours are config")
    assert.are.same(
      { opacity = 220, waiting_color = { r = 237, g = 28, b = 36 }, open_color = { r = 15, g = 205, b = 5 } },
      {
        opacity = widget.defaults.opacity,
        waiting_color = widget.defaults.waiting_color,
        open_color = widget.defaults.open_color,
      }
    )
  end)

  it("seeds itself centred, 431 up from the bottom, and survives a zero screen", function()
    build()
    assert.are.same({ x = (1920 - 604) / 2, y = 1080 - 431 }, widget.defaults.layout.pos)
    assert.is_true(widget.defaults.layout.visible)
    ctx.screen = function()
      return 0, 0
    end
    local zero = new_skillchain(ctx)
    assert.are.same({ x = 0, y = 0 }, zero.defaults.layout.pos)
  end)

  it("answers the open bar's box at the origin it was given", function()
    build()
    assert.are.same({ 1000, 500, 604, 14 }, { widget.get_bounds() })
    widget.set_scale(2)
    assert.are.same({ 1000, 500, 1208, 28 }, { widget.get_bounds() })
  end)

  it("builds two prims, the fill over the backdrop, hidden", function()
    build()
    assert.are.equal(2, #prims.images)
    assert.are.same({ 0, 0, 0 }, prims.images[1].last.color)
    assert.are.equal(150, prims.images[1].last.alpha)
    assert.is_false(prims.images[1].visible)
    assert.is_false(prims.images[2].visible)
  end)

  it("tracks a chain: red and thin while waiting, green and thick while open, then gone", function()
    build()
    local bg, fill = prims.images[1], prims.images[2]
    open_chain()
    env.now = 1.5
    tick()
    assert.is_true(fill.visible)
    assert.is_true(bg.visible)
    assert.are.same({ 237, 28, 36 }, fill.last.color, "the waiting colour")
    assert.are.equal(220, fill.last.alpha)
    assert.are.same({ 1152, 505, 300, 4 }, { fill.x, fill.y, fill.width, fill.height })
    assert.are.same({ 1150, 503, 304, 8 }, { bg.x, bg.y, bg.width, bg.height })
    env.now = 4
    tick()
    assert.are.same({ 15, 205, 5 }, fill.last.color, "the open colour")
    assert.are.same({ 1045, 502, 514, 10 }, { fill.x, fill.y, fill.width, fill.height })
    assert.are.same({ 1043, 500, 518, 14 }, { bg.x, bg.y, bg.width, bg.height })
    env.now = 12
    tick()
    assert.is_false(fill.visible)
    assert.is_false(bg.visible)
  end)

  it("writes only what changed: a settled state pushes no colour, a hidden bar nothing at all", function()
    build()
    local bg, fill = prims.images[1], prims.images[2]
    open_chain()
    env.now = 1.5
    tick()
    local colour_writes = 0
    for _, call in ipairs(fill.calls) do
      if call.name == "color" then
        colour_writes = colour_writes + 1
      end
    end
    env.now = 2
    tick()
    local after = 0
    for _, call in ipairs(fill.calls) do
      if call.name == "color" then
        after = after + 1
      end
    end
    assert.are.equal(colour_writes, after)
    widget.hide()
    local settled = #bg.calls + #fill.calls
    widget.update()
    widget.update()
    assert.are.equal(settled, #bg.calls + #fill.calls)
  end)

  it("goes down with hide, comes back with show against an origin that moved meanwhile", function()
    build()
    local fill = prims.images[2]
    open_chain()
    env.now = 1.5
    tick()
    widget.hide()
    assert.is_false(fill.visible)
    widget.set_pos(1200, 700)
    widget.show()
    tick()
    assert.is_true(fill.visible)
    assert.are.same({ 1200 + 152, 700 + 5 }, { fill.x, fill.y })
  end)

  it("scales with its anchor", function()
    build()
    widget.set_scale(2)
    local fill = prims.images[2]
    open_chain()
    env.now = 1.5
    tick()
    assert.are.same({ 1000 + 152 * 2, 500 + 5 * 2, 600, 8 }, { fill.x, fill.y, fill.width, fill.height })
  end)

  it("stays down with no target or a dead one", function()
    build()
    local fill = prims.images[2]
    open_chain()
    env.now = 1.5
    env.target = nil
    tick()
    assert.is_false(fill.visible)
    env.target = { id = 99, hpp = 0 }
    tick()
    assert.is_false(fill.visible)
  end)

  it("takes its colours and opacity from the config, falling back to the shipped ones", function()
    build()
    widget.attach({ opacity = 100, waiting_color = { r = 1, g = 2, b = 3 }, open_color = "garbage" })
    local fill = prims.images[2]
    open_chain()
    env.now = 1.5
    tick()
    assert.are.same({ 1, 2, 3 }, fill.last.color)
    assert.are.equal(100, fill.last.alpha)
    env.now = 4
    tick()
    assert.are.same({ 15, 205, 5 }, fill.last.color, "the shipped open colour over a broken one")
  end)

  it("previews its full open footprint for layout placement", function()
    build()
    local bg, fill = prims.images[1], prims.images[2]
    widget.set_preview(true)
    assert.is_true(fill.visible)
    assert.are.same({ 1000, 500, 604, 14 }, { bg.x, bg.y, bg.width, bg.height })
    widget.set_preview(false)
    assert.is_false(fill.visible)
  end)

  it("drops the chain with the service's logout, and draws nothing without the service", function()
    build()
    local fill = prims.images[2]
    open_chain()
    env.now = 1.5
    tick()
    assert.is_true(fill.visible)
    service.on_logout()
    widget.detach()
    assert.is_false(fill.visible)
    widget.attach(widget.defaults)
    widget.show()
    tick()
    assert.is_false(fill.visible)

    build({ no_service = true })
    widget.update()
    assert.is_false(prims.images[2].visible)
  end)

  it("destroys both prims", function()
    build()
    widget.destroy()
    assert.are.equal(1, prims.images[1].destroyed)
    assert.are.equal(1, prims.images[2].destroyed)
  end)
end)
