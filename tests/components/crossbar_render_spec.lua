local new_render = require("components/crossbar/render")
local build_defaults = require("components/crossbar/defaults")
local kebab = require("components/crossbar/kebab")

-- The upstream constants render.lua transcribes (decided: port xivcrossbar's
-- drawing verbatim, don't re-derive): 40px slots on a 40+6 column pitch, a
-- 56px bar spacing halved to 28 by compact, sides 300 apart, and the active
-- panel art at 330x180 drawn 30 left of and 35 above a side's top-left slot.
local COL = 46 -- 40 + slot_spacing
local ROW = 28 -- bar_spacing / 2 (compact)
local PAD_X, PAD_Y = 30, 35 -- panel overhang left/above the slot grid
local SIDE_GAP = 300 -- upstream h2 base - h1 base
local PANEL_W, PANEL_H = 330, 180

local function make(overrides)
  local config = build_defaults(1920, 1080)
  for key, value in pairs(overrides or {}) do
    config[key] = value
  end
  return new_render({ config = config }), config
end

describe("crossbar render", function()
  describe("slot geometry", function()
    -- Our slot map (not upstream's): face cluster right, dpad cluster left,
    -- both clockwise from the top. Side-local columns 1..6, rows measured
    -- down from the panel top.
    local expected = {
      -- slot = { column, y offset }
      [1] = { 5, PAD_Y }, -- Y: face top
      [2] = { 6, PAD_Y + ROW }, -- B: face right
      [3] = { 5, PAD_Y + 2 * ROW }, -- A: face bottom
      [4] = { 4, PAD_Y + ROW }, -- X: face left
      [5] = { 2, PAD_Y }, -- Up: dpad top
      [6] = { 3, PAD_Y + ROW }, -- R: dpad right
      [7] = { 2, PAD_Y + 2 * ROW }, -- Dn: dpad bottom
      [8] = { 1, PAD_Y + ROW }, -- L: dpad left
    }

    it("lays out all 8 slots of the XHB's left side as a double cross", function()
      local render = make()
      for slot = 1, 8 do
        local x, y = render.slot_pos("xhb", "left", slot)
        assert.are.equal(PAD_X + (expected[slot][1] - 1) * COL, x, "slot " .. slot .. " x")
        assert.are.equal(expected[slot][2], y, "slot " .. slot .. " y")
      end
    end)

    it("shifts the right side one side gap over", function()
      local render = make()
      for slot = 1, 8 do
        local left_x, left_y = render.slot_pos("xhb", "left", slot)
        local right_x, right_y = render.slot_pos("xhb", "right", slot)
        assert.are.equal(left_x + SIDE_GAP, right_x, "slot " .. slot)
        assert.are.equal(left_y, right_y, "slot " .. slot)
      end
    end)

    it("draws a WXHB side at its own anchor's origin", function()
      local render = make()
      -- Either side: each WXHB half owns an anchor, so both start at the pad.
      local x, y = render.slot_pos("wxhb", "left", 8)
      assert.are.same({ PAD_X, PAD_Y + ROW }, { x, y })
      x, y = render.slot_pos("wxhb", "right", 8)
      assert.are.same({ PAD_X, PAD_Y + ROW }, { x, y })
    end)

    it("centres the Expanded side across the main anchor's sixteen", function()
      local render = make()
      -- (main width - side width) / 2 = 150, upstream's own +150.
      local x = render.slot_pos("expanded", "left", 8)
      assert.are.equal(PAD_X + 150, x)
    end)

    it("honours the configured slot spacing", function()
      local render = make({ slot_spacing = 10 })
      local x = render.slot_pos("xhb", "left", 8) -- column 1
      local x2 = render.slot_pos("xhb", "left", 6) -- column 3
      assert.are.equal((40 + 10) * 2, x2 - x)
    end)

    it("rejects a slot or side it does not know", function()
      local render = make()
      assert.is_nil(render.slot_pos("xhb", "left", 9))
      assert.is_nil(render.slot_pos("xhb", "middle", 1))
      assert.is_nil(render.slot_pos("hotbar", "left", 1))
    end)
  end)

  describe("panel placement", function()
    it("places the active-side panel around each bar's slot grid", function()
      local render = make()
      local plans = {
        { bar = "xhb", side = "left", x = 0 },
        { bar = "xhb", side = "right", x = SIDE_GAP },
        { bar = "expanded", side = "left", x = 150 },
        { bar = "wxhb", side = "left", x = 0 },
        { bar = "wxhb", side = "right", x = 0 },
      }
      for _, case in ipairs(plans) do
        local panel = render.panel_pos(case.bar, case.side)
        assert.are.equal(case.x, panel.x, case.bar .. " " .. case.side)
        assert.are.equal(0, panel.y)
        assert.are.equal(PANEL_W, panel.width)
        assert.are.equal(PANEL_H, panel.height)
      end
    end)
  end)

  describe("bounds", function()
    it("reports the real footprint per anchor", function()
      local render = make()
      local width, height = render.bounds("main")
      -- Two 330-wide side panels whose origins sit 300 apart.
      assert.are.same({ SIDE_GAP + PANEL_W, PANEL_H }, { width, height })
      width, height = render.bounds("wxhb_left")
      assert.are.same({ PANEL_W, PANEL_H }, { width, height })
      width, height = render.bounds("wxhb_right")
      assert.are.same({ PANEL_W, PANEL_H }, { width, height })
      width, height = render.bounds("indicator")
      -- The skillchain bg at its widest displayed state (open: 604 x 14).
      assert.are.same({ 604, 14 }, { width, height })
    end)

    it("scales a footprint by the anchor's scale", function()
      local render = make()
      local width, height = render.bounds("main", 2)
      assert.are.same({ (SIDE_GAP + PANEL_W) * 2, PANEL_H * 2 }, { width, height })
    end)

    it("grows with hand-edited spacing so the slots stay inside", function()
      -- The config keys are not clamped (partylist's spacing behaves the
      -- same way): the footprint derives from the configured pitches, so a
      -- widened grid stays inside get_bounds and core's clamp keeps holding.
      local render = make({ slot_spacing = 16, bar_spacing = 100 })
      local width, height = render.bounds("main")
      -- side: 30 pad + 5 * (40 + 16) + 40 + 30 pad = 380; main: 300 + 380.
      -- height: 35 pad + 2 * 50 + 40 + the art's 49px bottom band.
      assert.are.same({ 300 + 380, 35 + 100 + 40 + 49 }, { width, height })
      local wxhb_width, wxhb_height = render.bounds("wxhb_left")
      assert.are.same({ 380, 224 }, { wxhb_width, wxhb_height })
      local panel = render.panel_pos("xhb", "right")
      assert.are.same({ 380, 224 }, { panel.width, panel.height })
      for slot = 1, 8 do
        local x, y = render.slot_pos("xhb", "right", slot)
        assert.is_true(x + 40 <= width, "slot " .. slot .. " x inside")
        assert.is_true(y + 40 <= height, "slot " .. slot .. " y inside")
      end
    end)

    it("answers nil for an unknown anchor", function()
      local render = make()
      assert.is_nil(render.bounds("wxhb"))
    end)
  end)

  describe("metrics", function()
    it("derives the drawing constants from the config", function()
      local render = make()
      local metrics = render.metrics()
      assert.are.equal(40, metrics.slot)
      assert.are.equal(COL, metrics.column_pitch)
      assert.are.equal(ROW, metrics.row_pitch)
      assert.are.equal(PANEL_W, metrics.panel_width)
      assert.are.equal(PANEL_H, metrics.panel_height)
    end)

    it("never mutates its input", function()
      -- Upstream defect (2): setup_metrics wrote derived values back into the
      -- settings table, shrinking spacing cumulatively on every re-setup.
      local render, config = make()
      local before_bar, before_slot = config.bar_spacing, config.slot_spacing
      render.metrics()
      render.metrics()
      render.slot_pos("xhb", "left", 1)
      render.bounds("main")
      assert.are.equal(before_bar, config.bar_spacing)
      assert.are.equal(before_slot, config.slot_spacing)
    end)
  end)

  describe("visibility", function()
    it("draws the XHB inactive and nothing else at rest", function()
      local render = make()
      local plan = render.visible("none")
      assert.is_true(plan.xhb)
      assert.is_false(plan.wxhb_left)
      assert.is_false(plan.wxhb_right)
      assert.is_nil(plan.expanded)
      assert.is_nil(plan.panel)
    end)

    it("keeps the WXHB on screen at rest when always_show_wxhb is set", function()
      local render = make({ always_show_wxhb = true })
      local plan = render.visible("none")
      assert.is_true(plan.wxhb_left)
      assert.is_true(plan.wxhb_right)
      assert.is_nil(plan.panel)
    end)

    it("panels the held XHB side", function()
      local render = make()
      local plan = render.visible("xhb_left")
      assert.is_true(plan.xhb)
      assert.are.same({ bar = "xhb", side = "left" }, plan.panel)
      plan = render.visible("xhb_right")
      assert.are.same({ bar = "xhb", side = "right" }, plan.panel)
    end)

    it("summons a WXHB side on its gesture and panels it", function()
      local render = make()
      local plan = render.visible("wxhb_left")
      assert.is_true(plan.xhb, "the XHB stays on screen, inactive")
      assert.is_true(plan.wxhb_left)
      assert.is_false(plan.wxhb_right, "the other half stays hidden at rest")
      assert.are.same({ bar = "wxhb", side = "left" }, plan.panel)
    end)

    it("keeps the resting WXHB half up during the other half's gesture when configured", function()
      local render = make({ always_show_wxhb = true })
      local plan = render.visible("wxhb_right")
      assert.is_true(plan.wxhb_left)
      assert.is_true(plan.wxhb_right)
      assert.are.same({ bar = "wxhb", side = "right" }, plan.panel)
    end)

    it("replaces everything with Expanded Hold while both sides are held", function()
      local render = make({ always_show_wxhb = true })
      for _, state in ipairs({ "expanded_lr", "expanded_rl" }) do
        local plan = render.visible(state)
        assert.is_false(plan.xhb, state)
        assert.is_false(plan.wxhb_left, state .. ": always_show_wxhb loses to Expanded")
        assert.is_false(plan.wxhb_right, state)
        assert.are.equal(state, plan.expanded)
        -- The panel names the side whose view is up, rl meaning right.
        local side = state == "expanded_rl" and "right" or "left"
        assert.are.same({ bar = "expanded", side = side }, plan.panel)
      end
    end)

    it("restores the resting bars when the hold releases", function()
      local render = make()
      render.visible("expanded_lr")
      local plan = render.visible("none")
      assert.is_true(plan.xhb)
      assert.is_nil(plan.expanded)
      assert.is_nil(plan.panel)
    end)

    it("draws nothing and activates nothing while hidden", function()
      local render = make({ always_show_wxhb = true })
      local plan = render.visible("xhb_left", { hidden = true })
      assert.is_false(plan.xhb)
      assert.is_false(plan.wxhb_left)
      assert.is_false(plan.wxhb_right)
      assert.is_nil(plan.expanded)
      assert.is_nil(plan.panel)
    end)
  end)

  describe("recast sweep", function()
    local render

    before_each(function()
      render = make()
    end)

    it("forgets a slot's observed maximum when told the content changed", function()
      -- The maxima key by prim slot and would otherwise outlive the slot's
      -- action: a set switch putting a 30s recast where a 300s one sat
      -- would draw the fresh sweep nearly done.
      assert.are.equal(32, render.sweep("changed", 300))
      render.clear_sweep("changed")
      assert.are.equal(32, render.sweep("changed", 25), "a fresh action re-learns its own denominator")
    end)

    it("sweeps 32 frames from full to done across a full recast", function()
      assert.are.equal(32, render.sweep("main/left/1", 100), "the first sighting is the maximum: full")
      assert.are.equal(16, render.sweep("main/left/1", 50))
      assert.are.equal(1, render.sweep("main/left/1", 1), "never below frame 1 while running")
      assert.is_nil(render.sweep("main/left/1", 0), "hidden at zero")
    end)

    it("uses the observed maximum, not an assumed full recast", function()
      -- Loaded mid-cooldown: the first value seen becomes the denominator, so
      -- the fraction is 1 and cannot exceed it (upstream defect 7 cannot recur).
      assert.are.equal(32, render.sweep("k", 30))
      -- A larger value raises the maximum...
      assert.are.equal(32, render.sweep("k", 60))
      -- ...and the old value now reads as halfway.
      assert.are.equal(16, render.sweep("k", 30))
    end)

    it("clears the maximum when the recast ends", function()
      render.sweep("k", 100)
      assert.is_nil(render.sweep("k", 0))
      -- A fresh, shorter cooldown starts full again rather than at 30/100.
      assert.are.equal(32, render.sweep("k", 30))
    end)

    it("tracks each slot independently", function()
      render.sweep("a", 100)
      assert.are.equal(32, render.sweep("b", 10), "b's maximum is its own")
      assert.are.equal(16, render.sweep("a", 50))
    end)

    it("rounds the frame to nearest, not down", function()
      -- 90/100 of 32 frames: floor(0.9 * 32 + 0.5) = 29. Without the +0.5
      -- the same fraction lands on 28 - the formula is round-to-nearest.
      assert.are.equal(32, render.sweep("k", 100))
      assert.are.equal(29, render.sweep("k", 90))
    end)

    it("treats a missing remaining as ended", function()
      render.sweep("k", 100)
      assert.is_nil(render.sweep("k", nil))
      assert.are.equal(32, render.sweep("k", 40))
    end)
  end)

  describe("chain frame animation", function()
    it("holds each of the 8 steps for five ticks, then wraps", function()
      local render = make()
      for step = 1, 8 do
        for _ = 1, 5 do
          assert.are.equal(step, render.chain_tick())
        end
      end
      assert.are.equal(1, render.chain_tick(), "tick 41 wraps to the first frame")
    end)
  end)

  describe("slot dressing", function()
    local render, config

    before_each(function()
      render, config = make()
    end)

    it("offsets the slot texts as upstream does, slot-relative", function()
      -- Name -2,+40 from the slot origin; cost +46/+28
      -- and recast +36/+14 (upstream's right-edge x + 16, then +30/+20).
      -- Cost and recast are right-justified, so the WIDGET subtracts the
      -- screen width from their x - after scaling, which is why it cannot
      -- happen here - the texts gotcha giltracker documents.
      local offsets = render.text_offsets(100, 200)
      assert.are.same({ x = 98, y = 240 }, offsets.name)
      assert.are.same({ x = 146, y = 228 }, offsets.cost)
      assert.are.same({ x = 136, y = 214 }, offsets.recast)
    end)

    it("falls back to the shipped cost colours when the config's are garbage", function()
      -- merge_defaults lets a user scalar beat a table default, and this
      -- feeds the per-frame path: a throw here repeats sixty times a second
      -- under the shared prerender guard.
      config.mp_cost_color = 5
      local cost = render.cost({ mp_cost = 24 }, { mp = 100 })
      assert.are.same({ r = 230, g = 91, b = 151 }, cost.color)
      config.tp_cost_color = "x"
      cost = render.cost({ tp_cost = 1000 }, { tp = 2000 })
      assert.are.same({ r = 254, g = 222, b = 0 }, cost.color)
    end)

    it("prices a spell in MP and says whether the player can afford it", function()
      local cost = render.cost({ mp_cost = 24 }, { mp = 100, tp = 0 })
      assert.are.equal("24", cost.text)
      assert.are.same(config.mp_cost_color, cost.color)
      assert.is_true(cost.affordable)
      cost = render.cost({ mp_cost = 24 }, { mp = 23, tp = 0 })
      assert.is_false(cost.affordable)
    end)

    it("prices a weaponskill in TP", function()
      local cost = render.cost({ tp_cost = 1000 }, { mp = 0, tp = 1000 })
      assert.are.equal("1000", cost.text)
      assert.are.same(config.tp_cost_color, cost.color)
      assert.is_true(cost.affordable)
      cost = render.cost({ tp_cost = 1000 }, { mp = 0, tp = 999 })
      assert.is_false(cost.affordable)
    end)

    it("prices nothing without a cost", function()
      assert.is_nil(render.cost({}, { mp = 100, tp = 100 }))
      assert.is_nil(render.cost({ mp_cost = 0 }, { mp = 100, tp = 100 }))
      assert.is_nil(render.cost(nil, { mp = 100, tp = 100 }))
    end)

    it("prices MP over TP when a record carries both", function()
      local cost = render.cost({ mp_cost = 10, tp_cost = 1000 }, { mp = 50, tp = 0 })
      assert.are.equal("10", cost.text)
      assert.are.same(config.mp_cost_color, cost.color)
    end)

    it("survives vitals the client has not filled in yet", function()
      -- Vitals arrive piecemeal (parambar's lesson): a vital we have no
      -- number for must not dim the slot - dimming on ignorance reads as
      -- unusable at every login.
      local cost = render.cost({ mp_cost = 24 }, nil)
      assert.are.equal("24", cost.text)
      assert.is_true(cost.affordable)
      cost = render.cost({ mp_cost = 24 }, { tp = 0 })
      assert.is_true(cost.affordable)
      cost = render.cost({ tp_cost = 1000 }, {})
      assert.is_true(cost.affordable)
    end)

    it("treats a spent flash as spent", function()
      assert.is_nil(render.feedback_fade(nil))
    end)

    it("dims an unusable slot to the configured alpha", function()
      assert.are.equal(255, render.slot_alpha(true))
      assert.are.equal(config.disabled_alpha, render.slot_alpha(false))
    end)

    it("fades the press flash out by the configured speed", function()
      -- Upstream's show_feedback: opacity walks down by `speed` each frame
      -- and the flash hides when it runs out.
      local alpha = config.feedback.alpha
      alpha = render.feedback_fade(alpha)
      assert.are.equal(config.feedback.alpha - config.feedback.speed, alpha)
      -- Exactly ceil(alpha / speed) steps from full to spent: the bound
      -- is zero, and must not drift negative.
      local steps = 1 -- the first step above
      while alpha ~= nil do
        alpha = render.feedback_fade(alpha)
        steps = steps + 1
        assert.is_true(steps < 100, "the fade must terminate")
      end
      assert.are.equal(math.ceil(config.feedback.alpha / config.feedback.speed), steps)
    end)

    it("fades on the shipped speed when the feedback config is garbage", function()
      -- Config files are hand-editable; a per-frame path must not do
      -- arithmetic on a missing table.
      config.feedback = "garbage"
      assert.are.equal(70, render.feedback_fade(100))
      config.feedback = {}
      assert.are.equal(70, render.feedback_fade(100), "a table without a speed falls back the same way")
    end)
  end)

  describe("icon resolution", function()
    local ASSETS = "components/crossbar/assets/"
    local render

    before_each(function()
      local config = build_defaults(1920, 1080)
      render = new_render({
        config = config,
        -- The built-in table's type default, actions.icon_for's contract:
        -- answers a pack-relative name or nil. icon_for deliberately ignores
        -- record.icon - the override belongs here, in the render-side
        -- resolution.
        icon_for = function(record, state)
          if record.type == "draw" then
            return (state or {}).mounted and "dismount" or "attack"
          end
          if record.type == "mr" then
            return "mount"
          end
          if record.type == "open" then
            -- Mirrors actions.icon_for: the opener entry's own icon or nil.
            return ({ map = "map", inventory = "item" })[record.action]
          end
          return nil
        end,
      })
    end)

    local function paths(candidates)
      local list = {}
      for _, candidate in ipairs(candidates) do
        list[#list + 1] = candidate.path
      end
      return list
    end

    it("resolves a spell: the override pair, then custom name art, then the pack name, then the id", function()
      local candidates = render.icon_candidates(
        { type = "ma", action = "Utsusemi: Ichi", icon = "heal" },
        { category = "Ninjutsu", recast_id = 338 }
      )
      assert.are.same({
        "icons/custom/heal.png",
        ASSETS .. "icons/heal.png",
        "icons/custom/utsusemi-ichi.png",
        ASSETS .. "icons/ninjutsu/utsusemi-ichi.png",
        ASSETS .. "icons/spells/00338.png",
      }, paths(candidates))
      -- The override example must itself be resolvable art.
      local file = io.open("src/" .. candidates[2].path, "rb")
      assert.is_not_nil(file, "the icon override example must ship")
      file:close()
    end)

    it("puts the record-level icon override ahead of everything, custom art first", function()
      -- The plan's icon-verb contract: an override name resolves under
      -- <addon>/icons/custom/ before the shipped pack, so a player's own
      -- art wins without renaming anything.
      local candidates = render.icon_candidates({ type = "mr", icon = "mounts/crab" }, nil)
      -- A pack-relative override keeps its path on the shipped side, but the
      -- custom side flattens to the basename: the plan promises users a FLAT
      -- icons/custom/ folder, so no override may demand subfolders there.
      assert.are.same({
        "icons/custom/crab.png",
        ASSETS .. "icons/mounts/crab.png",
        "icons/custom/mr.png",
        ASSETS .. "icons/mount.png",
      }, paths(candidates))
      candidates = render.icon_candidates({ type = "ma", action = "Cure", icon = "myart" }, { recast_id = 1 })
      assert.are.same({
        "icons/custom/myart.png",
        ASSETS .. "icons/myart.png",
        "icons/custom/cure.png",
        ASSETS .. "icons/spells/00001.png",
      }, paths(candidates))
    end)

    it("maps a display-form category onto its pack directory", function()
      -- The meta.category contract: the DISPLAY form ("Blue Magic"), which
      -- kebab maps onto the pack directory (blue-magic). A raw resource
      -- type like "BlueMagic" would kebab to "bluemagic" and silently miss
      -- the whole directory.
      local candidates = render.icon_candidates(
        { type = "ma", action = "Cocoon" },
        { category = "Blue Magic", recast_id = 93 }
      )
      assert.are.equal(ASSETS .. "icons/blue-magic/cocoon.png", candidates[2].path)
      local file = io.open("src/" .. candidates[2].path, "rb")
      assert.is_not_nil(file, "the display-form mapping must resolve on disk")
      file:close()
    end)

    it("resolves a job ability through the pack then the zero-padded recast id", function()
      local candidates = render.icon_candidates(
        { type = "ja", action = "Provoke" },
        { category = "Abilities", recast_id = 5 }
      )
      assert.are.same({
        "icons/custom/provoke.png",
        ASSETS .. "icons/abilities/provoke.png",
        ASSETS .. "icons/abilities/00005.png",
      }, paths(candidates))
    end)

    it("resolves an SP ability through its job-suffixed sheet", function()
      -- The shipped sheet stores the SP abilities job-suffixed
      -- (00000.02.png, 00254.01.png, ...; no plain 00000.png exists) -
      -- upstream's resource_generator builds the same suffix. The job id
      -- arrives in meta (CB5's ctx knows the main job).
      local candidates = render.icon_candidates(
        { type = "ja", action = "Hundred Fists" },
        { category = "Abilities", recast_id = 0, job_id = 2 }
      )
      assert.are.equal(ASSETS .. "icons/abilities/00000.02.png", candidates[#candidates].path)
      -- The candidate must resolve against the shipped tree.
      local file = io.open("src/" .. candidates[#candidates].path, "rb")
      assert.is_not_nil(file, "shipped SP icon missing on disk")
      file:close()
      candidates = render.icon_candidates(
        { type = "ja", action = "Brazen Rush" },
        { category = "Abilities", recast_id = 254, job_id = 1 }
      )
      assert.are.equal(ASSETS .. "icons/abilities/00254.01.png", candidates[#candidates].path)
      file = io.open("src/" .. candidates[#candidates].path, "rb")
      assert.is_not_nil(file, "shipped SP icon missing on disk")
      file:close()
    end)

    it("skips the SP sheet when the job is unknown rather than guessing", function()
      -- Without a job id no suffixed file can be named correctly; the custom
      -- and pack-name candidates remain, and CB5's ctx closes the gap.
      local candidates = render.icon_candidates(
        { type = "ja", action = "Hundred Fists" },
        { category = "Abilities", recast_id = 0 }
      )
      assert.are.same({
        "icons/custom/hundred-fists.png",
        ASSETS .. "icons/abilities/hundred-fists.png",
      }, paths(candidates))
    end)

    it("never invents art for the four SP icons the sheet is missing", function()
      -- 00000.01/.16/.21/.22 do not exist (Mighty Strikes, Azure Lore,
      -- Bolster, Elemental Sforzo) - upstream's sheet has the same holes.
      -- The candidates fall through to icons/custom/ alone, the user's
      -- route, exactly as upstream draws blank.
      local holes = {
        { ja = "Mighty Strikes", job = 1 },
        { ja = "Azure Lore", job = 16 },
        { ja = "Bolster", job = 21 },
        { ja = "Elemental Sforzo", job = 22 },
      }
      for _, hole in ipairs(holes) do
        local missing = ("src/components/crossbar/assets/icons/abilities/00000.%02d.png"):format(hole.job)
        assert.is_nil(io.open(missing, "rb"), missing .. " is expected to be a sheet hole")
        local candidates = render.icon_candidates(
          { type = "ja", action = hole.ja },
          { recast_id = 0, job_id = hole.job }
        )
        assert.are.same({ "icons/custom/" .. kebab(hole.ja) .. ".png" }, paths(candidates), hole.ja)
      end
    end)

    it("dresses a blood pact from the ability sheet", function()
      -- Blood pacts are `pet` records (they fire as /pet), and most of the
      -- pet family has shipped id art: the same non-SP chain as ja.
      local candidates = render.icon_candidates({ type = "pet", action = "Flaming Crush" }, { recast_id = 173 })
      assert.are.same({
        "icons/custom/flaming-crush.png",
        ASSETS .. "icons/abilities/00173.png",
      }, paths(candidates))
      local file = io.open("src/" .. candidates[#candidates].path, "rb")
      assert.is_not_nil(file, "00173.png must ship")
      file:close()
    end)

    it("never dresses a recast-0 blood pact in SP art", function()
      -- Recast 0 is shared by the 20 Astral Flow blood pacts: a pet record
      -- takes the plain-sheet branch, so Perfect Defense on job 15 must not
      -- borrow Astral Flow's job-suffixed 00000.15 art. The protection is
      -- the branch split by record type, not any category value.
      local candidates = render.icon_candidates(
        { type = "pet", action = "Perfect Defense" },
        { recast_id = 0, job_id = 15 }
      )
      for _, candidate in ipairs(candidates) do
        assert.is_nil(candidate.path:find("00000.15", 1, true), candidate.path)
      end
      -- The plain id candidate is the same dead end upstream has: no
      -- 00000.png ships, and custom art remains the route.
      assert.are.equal(ASSETS .. "icons/abilities/00000.png", candidates[#candidates].path)
    end)

    it("resolves the GEO and RUN lv96 SP2s through their own recast ids", function()
      -- Widened Compass and Odyllic Subterfuge are the lv96 SP2s that got
      -- their own recast ids (130/131) instead of sharing 254.
      local cases = {
        { ja = "Widened Compass", recast = 130, job = 21, file = "00130.21.png" },
        { ja = "Odyllic Subterfuge", recast = 131, job = 22, file = "00131.22.png" },
      }
      for _, case in ipairs(cases) do
        local candidates = render.icon_candidates(
          { type = "ja", action = case.ja },
          { recast_id = case.recast, job_id = case.job }
        )
        assert.are.equal(ASSETS .. "icons/abilities/" .. case.file, candidates[#candidates].path, case.ja)
        local file = io.open("src/" .. candidates[#candidates].path, "rb")
        assert.is_not_nil(file, case.file .. " must ship")
        file:close()
      end
    end)

    it("resolves a weaponskill through its weapon directory then the weapon type", function()
      local candidates = render.icon_candidates({ type = "ws", action = "Expiacion" }, { weapon = "Sword" })
      assert.are.same({
        "icons/custom/expiacion.png",
        ASSETS .. "icons/weaponskills/sword/expiacion.png",
        ASSETS .. "icons/weapons/sword.png",
      }, paths(candidates))
    end)

    it("resolves an item through the pack, the extracted cache, then the generic art", function()
      local candidates = render.icon_candidates(
        { type = "item", action = "Echo Drops", target = "me" },
        { item_id = 4157 }
      )
      assert.are.same({
        "icons/custom/echo-drops.png",
        ASSETS .. "icons/items/echo-drops.png",
        "icons/4157.bmp",
        ASSETS .. "icons/usable-item.png",
      }, paths(candidates))
    end)

    it("falls back to the plain item art without a self target", function()
      local candidates = render.icon_candidates({ type = "item", action = "Tsurara" }, {})
      assert.are.equal(ASSETS .. "icons/item.png", candidates[#candidates].path)
    end)

    it("resolves a mount by name then the generic mount art", function()
      local candidates = render.icon_candidates({ type = "mount", action = "Crab" }, nil)
      assert.are.same({
        "icons/custom/crab.png",
        ASSETS .. "icons/mounts/crab.png",
        ASSETS .. "icons/mount.png",
      }, paths(candidates))
    end)

    it("asks the built-in table for a state-aware icon", function()
      local candidates = render.icon_candidates({ type = "draw" }, nil, { mounted = true })
      assert.are.same({
        "icons/custom/draw.png",
        ASSETS .. "icons/dismount.png",
      }, paths(candidates))
      candidates = render.icon_candidates({ type = "draw" }, nil, {})
      assert.are.equal(ASSETS .. "icons/attack.png", candidates[#candidates].path)
    end)

    it("gives a ranged attack the shipped ranged art", function()
      local candidates = render.icon_candidates({ type = "ra" }, nil)
      assert.are.same({
        "icons/custom/ra.png",
        ASSETS .. "icons/ranged.png",
      }, paths(candidates))
      local file = io.open("src/" .. candidates[2].path, "rb")
      assert.is_not_nil(file, "ranged.png must ship")
      file:close()
    end)

    it("leaves ct and ex to custom art and the record override", function()
      -- Nothing shipped depicts an arbitrary chat line or console command,
      -- so these types resolve only through icons/custom/ and a
      -- record-level override. (pet left this list when the blood pacts
      -- gained the ability sheet.)
      for _, kind in ipairs({ "ct", "ex" }) do
        local candidates = render.icon_candidates({ type = kind, action = "Sic" }, nil)
        assert.are.same({ "icons/custom/sic.png" }, paths(candidates), kind)
        candidates = render.icon_candidates({ type = kind, action = "Sic", icon = "attack" }, nil)
        assert.are.same({
          "icons/custom/attack.png",
          ASSETS .. "icons/attack.png",
          "icons/custom/sic.png",
        }, paths(candidates), kind)
      end
    end)

    it("keeps the opener glyph without an icon_for dep", function()
      -- The glyph keys on the record and the nil answer, not on whether the
      -- dep was wired: a render built without icon_for still glyphs open.
      local bare = new_render({ config = build_defaults(1920, 1080) })
      local candidates = bare.icon_candidates({ type = "open", action = "equipment" }, nil)
      assert.are.equal(ASSETS .. "icons/check.png", candidates[#candidates].path)
    end)

    it("gives an opener without art the generic opener glyph", function()
      -- The plan pins a render-time fallback for opener entries with no
      -- single of their own (equipment, quests, linkshell): a generic
      -- opener glyph. The shipped magnifier (check.png) is that glyph.
      local candidates = render.icon_candidates({ type = "open", action = "equipment" }, nil)
      assert.are.same({
        "icons/custom/equipment.png",
        ASSETS .. "icons/check.png",
      }, paths(candidates))
      local file = io.open("src/" .. candidates[2].path, "rb")
      assert.is_not_nil(file, "check.png must ship")
      file:close()
      -- An opener with its own single keeps it.
      candidates = render.icon_candidates({ type = "open", action = "map" }, nil)
      assert.are.equal(ASSETS .. "icons/map.png", candidates[#candidates].path)
    end)

    it("maps the ranged weaponskill types onto the art the sheet actually has", function()
      -- The weapons sheet has no archery/marksmanship/throwing files;
      -- upstream inherits that hole. Archery and marksmanship map to their
      -- weapon art, throwing to the generic ranged single.
      local cases = {
        { weapon = "Archery", ws = "Empyreal Arrow", sheet = "icons/weapons/bow.png" },
        { weapon = "Marksmanship", ws = "Detonator", sheet = "icons/weapons/gun.png" },
        { weapon = "Throwing", ws = "Blitzstrahl", sheet = "icons/ranged.png" },
        -- Two words: the sheet keeps its spaces, so the file is reached by
        -- case-folding alone - kebab would look for great-katana.png.
        { weapon = "Great Katana", ws = "Tachi: Fudo", sheet = "icons/weapons/great katana.png" },
      }
      for _, case in ipairs(cases) do
        local candidates = render.icon_candidates({ type = "ws", action = case.ws }, { weapon = case.weapon })
        assert.are.equal(ASSETS .. case.sheet, candidates[#candidates].path, case.weapon)
        local file = io.open("src/" .. candidates[#candidates].path, "rb")
        assert.is_not_nil(file, case.sheet .. " must ship")
        file:close()
      end
    end)

    it("centres the 32px id and extracted icons and leaves pack art at the origin", function()
      local candidates = render.icon_candidates(
        { type = "ma", action = "Cure" },
        { category = "White Magic", recast_id = 1 }
      )
      -- Name-resolved pack art draws at the slot origin; the id-based 32x32
      -- sheets sit +4/+4 to centre in the 40px slot, as upstream does.
      assert.are.same({ x = 0, y = 0 }, candidates[1].offset)
      assert.are.same({ x = 0, y = 0 }, candidates[2].offset)
      assert.are.same({ x = 4, y = 4 }, candidates[3].offset)
    end)

    it("centres the extracted item bitmaps and the weapon sheet", function()
      -- Both are 32x32 sheets like the spell ids: +4/+4 in the 40px slot;
      -- the pack's own item art is 40px and stays at the origin.
      local candidates = render.icon_candidates({ type = "item", action = "Echo Drops" }, { item_id = 4157 })
      for _, candidate in ipairs(candidates) do
        if candidate.path == "icons/4157.bmp" then
          assert.are.same({ x = 4, y = 4 }, candidate.offset, "extracted bitmap")
        elseif candidate.path == ASSETS .. "icons/items/echo-drops.png" then
          assert.are.same({ x = 0, y = 0 }, candidate.offset, "pack item art")
        end
      end
      candidates = render.icon_candidates({ type = "ws", action = "Expiacion" }, { weapon = "Sword" })
      assert.are.same({ x = 4, y = 4 }, candidates[#candidates].offset, "weapon sheet")
    end)

    it("skips malformed record fields instead of throwing", function()
      -- Hand-edited binding files reach this path at CB5: a wrong-typed
      -- field costs its own candidate, never the frame.
      local candidates = render.icon_candidates({ type = "ma", action = "Cure", icon = true }, { recast_id = 1 })
      assert.are.same({
        "icons/custom/cure.png",
        ASSETS .. "icons/spells/00001.png",
      }, paths(candidates))
      candidates = render.icon_candidates({ type = "ja", action = 5 }, { recast_id = 5 })
      assert.are.same({ ASSETS .. "icons/abilities/00005.png" }, paths(candidates))
      candidates = render.icon_candidates({ type = "ws", action = "Expiacion" }, { weapon = 5 })
      assert.are.same({ "icons/custom/expiacion.png" }, paths(candidates))
    end)

    it("skips a degenerate override string instead of throwing", function()
      -- "" and "items/" have no basename: the override pair is skipped
      -- entirely (treated as no override), never a concat throw in the
      -- per-frame path.
      for _, degenerate in ipairs({ "", "items/" }) do
        local candidates = render.icon_candidates(
          { type = "ma", action = "Cure", icon = degenerate },
          { recast_id = 1 }
        )
        assert.are.same({
          "icons/custom/cure.png",
          ASSETS .. "icons/spells/00001.png",
        }, paths(candidates), "icon = '" .. degenerate .. "'")
      end
    end)

    it("flattens the action-derived custom name the same way", function()
      -- kebab keeps '/' (it round-trips it for real action names), so a
      -- pathological action must not smuggle slashes into icons/custom/:
      -- the candidate takes the slash-free basename, or is skipped when
      -- nothing survives.
      local candidates = render.icon_candidates({ type = "ct", action = "//hud layout" }, nil)
      assert.are.same({ "icons/custom/hud-layout.png" }, paths(candidates))
      candidates = render.icon_candidates({ type = "ct", action = "///" }, nil)
      assert.are.same({}, paths(candidates))
    end)

    it("answers nothing for an empty slot", function()
      assert.are.same({}, render.icon_candidates(nil))
    end)
  end)
end)
