local new_render = require("lib/actionbar/render")

local function make(overrides)
  local config = {
    slot_alpha = 100,
    disabled_alpha = 100,
    feedback = { alpha = 150, speed = 30 },
    mp_cost_color = { r = 1, g = 2, b = 3 },
    tp_cost_color = { r = 4, g = 5, b = 6 },
  }
  for key, value in pairs(overrides or {}) do
    config[key] = value
  end
  return new_render({ config = config }), config
end

local function rect(x, y, size, extra)
  local entry = { x = x, y = y, width = size, height = size }
  for key, value in pairs(extra or {}) do
    entry[key] = value
  end
  return entry
end

describe("the shared slot render", function()
  it("draws every slot forty pixels square", function()
    assert.are.equal(40, new_render({ config = {} }).slot_size())
  end)

  describe("the hit-test over rects", function()
    it("answers the rect under a point, later rects over earlier ones", function()
      local render = make()
      local rects = { rect(100, 100, 40, { slot = 1 }), rect(120, 120, 40, { slot = 2 }) }
      assert.are.equal(1, render.slot_at(rects, 105, 105).slot)
      assert.are.equal(2, render.slot_at(rects, 130, 130).slot, "the overlap goes to the later rect")
      assert.is_nil(render.slot_at(rects, 99, 100))
      assert.is_nil(render.slot_at(rects, 160, 160), "the far edge is exclusive")
    end)

    it("looks past a rect the caller turns down, and refuses a non-point", function()
      local render = make()
      local rects = { rect(100, 100, 40, { slot = 1 }), rect(100, 100, 40, { slot = 2 }) }
      local hit = render.slot_at(rects, 110, 110, function(candidate)
        return candidate.slot == 1
      end)
      assert.are.equal(1, hit.slot)
      assert.is_nil(render.slot_at(rects, nil, 110))
      assert.is_nil(render.slot_at(nil, 110, 110))
    end)
  end)

  describe("the recast sweep", function()
    it("indexes the frame off the largest recast it has seen for the key", function()
      local render = make()
      assert.are.equal(32, render.sweep("a", 60))
      assert.are.equal(16, render.sweep("a", 30))
      assert.is_nil(render.sweep("a", 0), "a spent recast ends the sweep")
      assert.are.equal(32, render.sweep("a", 10), "and forgets the maximum with it")
      render.sweep("b", 100)
      render.clear_sweep("b")
      assert.are.equal(32, render.sweep("b", 5))
    end)

    it("steps the chain border animation once per five calls, over eight steps", function()
      local render = make()
      local steps = {}
      for _ = 1, 41 do
        steps[#steps + 1] = render.chain_tick()
      end
      assert.are.equal(1, steps[1])
      assert.are.equal(1, steps[5])
      assert.are.equal(2, steps[6])
      assert.are.equal(8, steps[40])
      assert.are.equal(1, steps[41], "and wraps")
    end)
  end)

  describe("the slot's dressing", function()
    it("prices MP over TP and says whether the vitals afford it", function()
      local render = make()
      local cost = render.cost({ mp_cost = 8, tp_cost = 1000 }, { mp = 4 })
      assert.are.equal("8", cost.text)
      assert.are.same({ r = 1, g = 2, b = 3 }, cost.color)
      assert.is_false(cost.affordable)
      cost = render.cost({ tp_cost = 1000 }, {})
      assert.are.equal("1000", cost.text)
      assert.is_true(cost.affordable, "a vital the client has not filled in affords everything")
      assert.is_nil(render.cost({ mp_cost = 0 }, {}))
      assert.is_nil(render.cost(nil, {}))
    end)

    it("reads a recast in the client's own units and labels it", function()
      local render = make()
      assert.are.equal(1.5, render.remaining_for({ kind = "spell", recast_id = 1 }, { [1] = 90 }, {}))
      assert.are.equal(30, render.remaining_for({ kind = "ability", recast_id = 5 }, {}, { [5] = 30 }))
      assert.are.equal(0, render.remaining_for({ kind = "spell" }, {}, {}))
      assert.are.equal(0, render.remaining_for(nil))
      assert.are.equal("2h", render.recast_label(7500))
      assert.are.equal("1m", render.recast_label(90))
      assert.are.equal("2s", render.recast_label(1.2))
    end)

    it("dims an unusable slot to the configured alpha", function()
      local render = make({ disabled_alpha = 60 })
      assert.are.equal(255, render.slot_alpha(true))
      assert.are.equal(60, render.slot_alpha(false))
    end)

    it("walks the press flash down by the configured speed", function()
      local render = make()
      assert.are.equal(120, render.feedback_fade(150))
      assert.is_nil(render.feedback_fade(20))
      assert.is_nil(render.feedback_fade(nil))
    end)

    it("cuts a long label to seven characters and a dot, whole glyphs only", function()
      local render = make()
      assert.are.equal("Cure", render.slot_label("Cure"))
      assert.are.equal("Utsusem.", render.slot_label("Utsusemi: Ichi"))
      assert.are.equal("", render.slot_label(nil))
      -- A three-byte note taken mid-sequence is dropped whole.
      assert.are.equal("Choco.", render.slot_label("Choco\226\153\170bo"))
    end)

    it("places the three texts relative to the slot", function()
      local render = make()
      local offsets = render.text_offsets(10, 20)
      assert.are.same({ x = 8, y = 60 }, offsets.name)
      assert.are.same({ x = 56, y = 48 }, offsets.cost)
      assert.are.same({ x = 46, y = 34 }, offsets.recast)
    end)

    it("resolves icon candidates, the player's override first", function()
      local render = make()
      local candidates = render.icon_candidates({ type = "ma", action = "Cure", icon = "spells/00001" }, {
        category = "White Magic",
        recast_id = 1,
      })
      assert.are.equal("icons/custom/00001.png", candidates[1].path)
      assert.are.equal("assets/icons/spells/00001.png", candidates[2].path)
      assert.are.equal("icons/custom/cure.png", candidates[3].path)
      assert.are.equal("assets/icons/white-magic/cure.png", candidates[4].path)
      assert.are.same({ x = 4, y = 4 }, candidates[5].offset, "the id sheet centres in the slot")
      assert.are.same({}, render.icon_candidates(nil))
    end)
  end)
end)
