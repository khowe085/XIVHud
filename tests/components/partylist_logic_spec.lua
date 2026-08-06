local new_logic = require("components/partylist/logic")
local build_defaults = require("components/partylist/defaults")

-- Stand-ins for the Windower resource tables the entry point injects. Only the
-- fields the component reads are present.
local RESOURCES = {
  jobs = {
    [1] = { ens = "WAR" },
    [4] = { ens = "WHM" },
    [5] = { ens = "BLM" },
    [7] = { ens = "PLD" },
    [20] = { ens = "SCH" },
  },
  zones = {
    [230] = { name = "Southern San d'Oria", search = "San d'Oria" },
    [50] = { name = "Port Bastok", search = "Bastok" },
  },
  buffs = {
    [0] = { en = "KO" },
    [1] = { en = "weakness" },
    [15] = { en = "doom" },
    [2] = { en = "sleep" },
    [33] = { en = "haste" },
    [40] = { en = "protect" },
    [253] = { en = "max hp boost" },
  },
}

-- One entry of windower.ffxi.get_party(). `mob` is absent for a member who is
-- not in the zone, which is how the client says so.
local function member(fields)
  local entry = {
    name = fields.name,
    hp = fields.hp or 1000,
    hpp = fields.hpp or 100,
    mp = fields.mp or 500,
    mpp = fields.mpp or 100,
    tp = fields.tp or 0,
    zone = fields.zone or 230,
  }
  if fields.mob ~= false then
    entry.mob = {
      id = fields.id or 1,
      -- get_party() reports distance squared.
      distance = (fields.distance or 5) ^ 2,
      is_npc = fields.is_npc or false,
      models = { fields.model or 0 },
    }
  end
  return entry
end

describe("partylist logic", function()
  local config, logic

  local function build(variant, overrides)
    config = build_defaults(1920, 1080, variant or "main")
    for key, value in pairs(overrides or {}) do
      config[key] = value
    end
    logic = new_logic({ variant = variant or "main", config = config, resources = RESOURCES })
    logic.set_zone(230)
    return logic
  end

  -- Runs frames until no bar is still easing, so assertions describe the
  -- settled picture rather than a frame mid-animation.
  local function settle(limit)
    local plan
    for _ = 1, limit or 300 do
      plan = logic.tick()
      local moving = false
      for _, row in ipairs(plan.rows) do
        for _, bar in pairs(row.bars or {}) do
          moving = moving or bar.dirty
        end
      end
      if not moving then
        return plan
      end
    end
    error("bars never converged")
  end

  before_each(function()
    build("main")
  end)

  describe("the roster", function()
    it("reads the main party from the p0..p5 keys", function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11 }), p2 = member({ name = "Volker", id = 22 }) })
      local plan = settle()
      assert.are.equal("Ayame", plan.rows[1].name)
      assert.is_false(plan.rows[2].occupied)
      assert.are.equal("Volker", plan.rows[3].name)
    end)

    it("reads the first alliance party from the a10..a15 keys", function()
      build("alliance1")
      logic.set_roster({
        p0 = member({ name = "Ayame", id = 11 }),
        a10 = member({ name = "Zeid", id = 33 }),
        a20 = member({ name = "Naji", id = 44 }),
      })
      local plan = settle()
      assert.are.equal("Zeid", plan.rows[1].name)
    end)

    it("reads the second alliance party from the a20..a25 keys", function()
      build("alliance2")
      logic.set_roster({ a10 = member({ name = "Zeid", id = 33 }), a20 = member({ name = "Naji", id = 44 }) })
      assert.are.equal("Naji", settle().rows[1].name)
    end)

    it("always plans six rows, occupied or not", function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11 }) })
      assert.are.equal(6, #settle().rows)
    end)

    it("treats a member with no name as an empty slot", function()
      logic.set_roster({ p0 = { hp = 100 } })
      assert.is_false(settle().rows[1].occupied)
    end)

    it("copes with no party at all", function()
      logic.set_roster(nil)
      local plan = settle()
      assert.are.equal(6, #plan.rows)
      assert.is_false(plan.rows[1].occupied)
    end)

    it("empties a row when its member leaves", function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11 }) })
      settle()
      logic.set_roster({})
      assert.is_false(settle().rows[1].occupied)
    end)
  end)

  describe("list sizing", function()
    it("counts only the rows up to the last occupied one", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1 }), p1 = member({ name = "B", id = 2 }) })
      assert.are.equal(2, settle().row_count)
    end)

    it("counts every row when the empty ones are shown", function()
      config.show_empty_rows = true
      logic.set_roster({ p0 = member({ name = "A", id = 1 }) })
      assert.are.equal(6, settle().row_count)
    end)

    it("counts one row for an empty party, so the list never collapses to nothing", function()
      logic.set_roster({})
      assert.are.equal(1, settle().row_count)
    end)

    it("adds the row spacing between rows but not after the last", function()
      config.item_spacing = 4
      logic.set_roster({ p0 = member({ name = "A", id = 1 }), p1 = member({ name = "B", id = 2 }) })
      local plan = settle()
      assert.are.equal(2 * plan.row_height + 4, plan.content_height)
    end)

    it("offsets each row by the row height plus the spacing", function()
      config.item_spacing = 4
      logic.set_roster({ p0 = member({ name = "A", id = 1 }), p1 = member({ name = "B", id = 2 }) })
      local plan = settle()
      assert.are.equal(0, plan.rows[1].offset_y)
      assert.are.equal(plan.row_height + 4, plan.rows[2].offset_y)
    end)

    --[[ alignBottom grows the list upward as members join. XIVParty does that
         by shifting the whole list's origin, which cannot work here: the widget
         contract has get_bounds report the origin set_pos was given, so a
         shifted origin would have core clamp against a box the list is not in
         and walk the list off screen a step per frame. Placing the rows at the
         bottom of a full-height box looks the same and keeps the box honest. ]]
    it("packs the rows to the bottom of a full-height box when aligned to the bottom", function()
      config.align_bottom = true
      logic.set_roster({ p0 = member({ name = "A", id = 1 }) })
      local plan = settle()
      assert.are.equal(6 * plan.row_height, plan.box_height)
      assert.are.equal(5 * plan.row_height, plan.rows[1].offset_y)
    end)

    it("keeps the box no taller than the rows it draws when not aligned to the bottom", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1 }) })
      local plan = settle()
      assert.are.equal(plan.content_height, plan.box_height)
      assert.are.equal(0, plan.rows[1].offset_y)
    end)

    it("reports the width of the whole list", function()
      assert.are.equal(410, settle().width)
      build("alliance1")
      assert.are.equal(315, settle().width)
    end)
  end)

  describe("hiding while solo", function()
    it("asks for nothing to be drawn when the player is alone", function()
      config.hide_solo = true
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
      assert.is_true(settle().hidden)
    end)

    it("asks for nothing to be drawn when there is no party at all", function()
      config.hide_solo = true
      logic.set_roster({})
      assert.is_true(settle().hidden)
    end)

    it("draws as soon as a second member arrives", function()
      config.hide_solo = true
      logic.set_roster({ p0 = member({ name = "A", id = 1 }), p1 = member({ name = "B", id = 2 }) })
      assert.is_false(settle().hidden)
    end)

    it("draws a solo party when the setting is off", function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
      assert.is_false(settle().hidden)
    end)
  end)

  describe("the poll gate", function()
    it("is due on the very first frame", function()
      assert.is_true(logic.due_for_poll(0))
    end)

    it("is not due again until the interval has passed", function()
      logic.due_for_poll(0)
      assert.is_false(logic.due_for_poll(0.1))
      assert.is_false(logic.due_for_poll(0.19))
      assert.is_true(logic.due_for_poll(0.2))
    end)

    it("takes the interval from configuration", function()
      config.poll_interval_ms = 500
      logic.due_for_poll(0)
      assert.is_false(logic.due_for_poll(0.4))
      assert.is_true(logic.due_for_poll(0.5))
    end)

    -- os.clock does not go backwards, but a hand-edited interval of zero would
    -- otherwise make the gate meaningless rather than merely fast.
    it("polls every frame when the interval is zero or nonsense", function()
      config.poll_interval_ms = 0
      logic.due_for_poll(0)
      assert.is_true(logic.due_for_poll(0))
      config.poll_interval_ms = "soon"
      assert.is_true(logic.due_for_poll(0))
    end)
  end)

  describe("the bars", function()
    local function only(fields)
      logic.set_roster({ p0 = member(fields) })
      return settle().rows[1]
    end

    it("fills each bar in proportion to its percent", function()
      local row = only({ name = "A", id = 1, hpp = 50, mpp = 25, tp = 1000 })
      assert.are.equal(51, row.bars.hp.width)
      assert.are.equal(25, row.bars.mp.width)
      assert.are.equal(102, row.bars.tp.width)
    end)

    -- TP runs 0..3000 but the bar is full at 1000, exactly as parambar has it.
    it("derives the TP bar from tenths of TP, capped at a full bar", function()
      assert.are.equal(51, only({ name = "A", id = 1, tp = 500 }).bars.tp.width)
      assert.are.equal(102, only({ name = "A", id = 1, tp = 3000 }).bars.tp.width)
    end)

    it("prints the absolute value, not the percent", function()
      local row = only({ name = "A", id = 1, hp = 1234, hpp = 50, mp = 99, tp = 1500 })
      assert.are.equal("1234", row.bars.hp.text)
      assert.are.equal("99", row.bars.mp.text)
      assert.are.equal("1500", row.bars.tp.text)
    end)

    it("hides a bar that has eased to nothing", function()
      assert.is_true(only({ name = "A", id = 1, hpp = 0, hp = 0 }).bars.hp.hidden)
      assert.is_false(only({ name = "A", id = 1, hpp = 1 }).bars.hp.hidden)
    end)

    it("stops marking a bar dirty once it has converged", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hpp = 60 }) })
      settle()
      assert.is_false(logic.tick().rows[1].bars.hp.dirty)
    end)

    it("eases towards a new value rather than snapping to it", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hpp = 100 }) })
      settle()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hpp = 0 }) })
      local moving = logic.tick().rows[1].bars.hp.width
      assert.is_true(moving > 0 and moving < 102)
    end)

    -- A slot whose occupant changes must not ease the newcomer's bar down from
    -- the previous member's value.
    it("restarts the animation when a different member takes the slot", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hpp = 100 }) })
      settle()
      logic.set_roster({ p0 = member({ name = "B", id = 2, hpp = 100 }) })
      assert.is_true(logic.tick().rows[1].bars.hp.width < 102)
    end)

    describe("colour bands", function()
      local function band(hpp)
        return only({ name = "A", id = 1, hpp = hpp }).bars.hp.band
      end

      it("bands HP strictly below each threshold", function()
        assert.are.equal("red", band(24))
        assert.are.equal("orange", band(25))
        assert.are.equal("orange", band(49))
        assert.are.equal("yellow", band(50))
        assert.are.equal("yellow", band(74))
        assert.are.equal("normal", band(75))
      end)

      it("leaves MP unbanded, as XIVParty does", function()
        assert.are.equal("normal", only({ name = "A", id = 1, mpp = 5 }).bars.mp.band)
      end)

      it("highlights TP only once it is full", function()
        assert.are.equal("normal", only({ name = "A", id = 1, tp = 999 }).bars.tp.band)
        assert.are.equal("full_tp", only({ name = "A", id = 1, tp = 1000 }).bars.tp.band)
        assert.are.equal("full_tp", only({ name = "A", id = 1, tp = 1001 }).bars.tp.band)
      end)
    end)

    describe("distance dimming", function()
      local function alpha(distance)
        return only({ name = "A", id = 1, distance = distance }).bars.hp.alpha
      end

      it("draws a member in casting range at full opacity", function()
        assert.are.equal(255, alpha(20.78))
      end)

      it("dims a member only in targeting range", function()
        assert.are.equal(128, alpha(20.79))
        assert.are.equal(128, alpha(49.9))
      end)

      it("dims a member beyond targeting range further", function()
        assert.are.equal(64, alpha(50))
        assert.are.equal(64, alpha(200))
      end)

      it("dims a member whose distance is unknown", function()
        assert.are.equal(64, only({ name = "A", id = 1, mob = false }).bars.hp.alpha)
      end)
    end)
  end)

  describe("a member outside the zone", function()
    local function elsewhere()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11, zone = 50, mob = false, hpp = 80 }) })
      return settle().rows[1]
    end

    it("is still an occupied row", function()
      assert.is_true(elsewhere().occupied)
    end)

    it("names the zone it is in", function()
      assert.are.equal("(Port Bastok)", elsewhere().zone_text)
    end)

    it("uses the short zone name where the layout asks for one", function()
      build("alliance1")
      logic.set_roster({ a10 = member({ name = "Ayame", id = 11, zone = 50, mob = false }) })
      assert.are.equal("(Bastok)", settle().rows[1].zone_text)
    end)

    -- res.zones is generated from the client, so an id it has never heard of
    -- means a game update. XIVParty indexes it unguarded and dies mid-render.
    it("survives a zone id the resources do not know", function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11, zone = 9999, mob = false }) })
      assert.are.equal("(?)", settle().rows[1].zone_text)
    end)

    it("empties its bars and reads their values as unknown", function()
      local row = elsewhere()
      assert.are.equal(0, row.bars.hp.width)
      assert.are.equal("?", row.bars.hp.text)
    end)

    it("says so rather than printing nil when the zone entry has no name", function()
      RESOURCES.zones[9998] = {}
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11, zone = 9998, mob = false }) })
      local text = settle().rows[1].zone_text
      RESOURCES.zones[9998] = nil
      assert.are.equal("(?)", text)
    end)

    it("says nothing about the zone for a member who is in it", function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11 }) })
      assert.are.equal("", settle().rows[1].zone_text)
    end)
  end)

  describe("long names", function()
    -- The alliance column is 105px wide and its name font is 8pt; XIVParty
    -- caps the text at 9 characters there and 17 in the main list, because a
    -- name that overruns is drawn straight over the next column.
    it("cuts a name to the length the layout allows", function()
      build("alliance1")
      logic.set_roster({ a10 = member({ name = "Rughadjeen", id = 1 }) })
      assert.are.equal("Rughadjee", settle().rows[1].name)
    end)

    it("leaves a name that fits alone", function()
      build("alliance1")
      logic.set_roster({ a10 = member({ name = "Ayame", id = 1 }) })
      assert.are.equal("Ayame", settle().rows[1].name)
    end)

    it("allows a longer name in the main list", function()
      logic.set_roster({ p0 = member({ name = "Rughadjeen", id = 1 }) })
      assert.are.equal("Rughadjeen", settle().rows[1].name)
    end)
  end)

  describe("a member the client gives no mob for", function()
    --[[ get_party() drops the mob table for a member outside the zone, and the
         mob is where the id lives. 0x0DD carries both the name and the id, so
         the id is recoverable -- without it an out-of-zone member can never be
         matched to their 0x0C8 leader flags, and two different members
         occupying one slot in turn would share an eased bar. ]]
    it("remembers the id a party packet gave for a name", function()
      logic.apply_member_identity(77, "Ayame")
      logic.apply_alliance_flags({ [77] = { leader = true, alliance_leader = false, quartermaster = false } })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 77, zone = 50, mob = false }) })
      assert.is_true(settle().rows[1].leader.party)
    end)

    it("prefers the mob's id when there is one", function()
      logic.apply_member_identity(77, "Ayame")
      logic.apply_alliance_flags({ [11] = { leader = true, alliance_leader = false, quartermaster = false } })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11 }) })
      assert.is_true(settle().rows[1].leader.party)
    end)

    -- The poll keeps running while layout mode previews, and the preview bag
    -- knows none of the real name/id pairings. Resolving ids through it would
    -- have the prune decide every out-of-zone member had left.
    it("keeps that job through a poll that lands during a preview", function()
      logic.apply_member_identity(77, "Ayame")
      logic.apply_job(77, { main = 4, main_level = 99, sub = 5, sub_level = 49 })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 77 }) })
      settle()
      logic.set_preview(true)
      logic.set_roster({ p0 = member({ name = "Ayame", id = 77, zone = 50, mob = false }) })
      settle()
      logic.set_preview(false)
      logic.set_roster({ p0 = member({ name = "Ayame", id = 77 }) })
      assert.are.equal("WHM 99", settle().rows[1].job_text)
    end)

    it("keeps an out-of-zone member's job rather than pruning it away", function()
      logic.apply_member_identity(77, "Ayame")
      logic.apply_job(77, { main = 4, main_level = 99, sub = 5, sub_level = 49 })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 77 }) })
      settle()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 77, zone = 50, mob = false }) })
      settle()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 77 }) })
      assert.are.equal("WHM 99", settle().rows[1].job_text)
    end)
  end)

  describe("push and poll reconciliation", function()
    it("shows a pushed vital immediately, without waiting for a poll", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hp = 1000, hpp = 100 }) })
      settle()
      logic.apply_vitals(1, { hp = 400, hpp = 40 })
      local row = settle().rows[1]
      assert.are.equal("400", row.bars.hp.text)
      assert.are.equal(40, row.bars.hp.width)
    end)

    -- The poll reads the client's own state, which is downstream of the very
    -- packets we parse, so it settles any disagreement.
    it("lets the next poll overrule a pushed value", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hp = 1000, hpp = 100 }) })
      logic.apply_vitals(1, { hp = 400, hpp = 40 })
      settle()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hp = 900, hpp = 90 }) })
      assert.are.equal("900", settle().rows[1].bars.hp.text)
    end)

    -- A member who joined before the addon loaded pushes nothing until they
    -- take damage; the poll is what puts a number on their bar.
    it("renders a member no packet has ever mentioned", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hp = 750, hpp = 75 }) })
      assert.are.equal("750", settle().rows[1].bars.hp.text)
    end)

    it("ignores a push for someone who is not in this list", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hp = 1000, hpp = 100 }) })
      logic.apply_vitals(999, { hp = 1, hpp = 1 })
      assert.are.equal("1000", settle().rows[1].bars.hp.text)
    end)

    it("takes only the vitals a push actually carries", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, hp = 1000, hpp = 100, mp = 500 }) })
      logic.apply_vitals(1, { hp = 400, hpp = 40 })
      assert.are.equal("500", settle().rows[1].bars.mp.text)
    end)
  end)

  describe("the player's own vitals", function()
    -- Your own HP arrives as a change event, the same stream parambar reads.
    -- Without it your row is the only one in the list updating at 5Hz while
    -- the parameter bar beside it moves instantly.
    it("shows a change event before the next poll", function()
      logic.set_main_player({ name = "Ayame" })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1, hp = 1000, hpp = 100 }) })
      settle()
      logic.set_own_vital("hp", 250)
      logic.set_own_vital("hpp", 24)
      local row = settle().rows[1]
      assert.are.equal("250", row.bars.hp.text)
      assert.are.equal("red", row.bars.hp.band)
    end)

    it("takes TP from the change event, which is unambiguously 0..3000", function()
      logic.set_main_player({ name = "Ayame" })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
      logic.set_own_vital("tp", 2000)
      local row = settle().rows[1]
      assert.are.equal("2000", row.bars.tp.text)
      assert.are.equal("full_tp", row.bars.tp.band)
    end)

    it("lets the next poll overrule it, exactly as a packet push is overruled", function()
      logic.set_main_player({ name = "Ayame" })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1, hp = 1000, hpp = 100 }) })
      logic.set_own_vital("hp", 250)
      settle()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1, hp = 900, hpp = 90 }) })
      assert.are.equal("900", settle().rows[1].bars.hp.text)
    end)

    it("never puts the player's vitals on somebody else's row", function()
      logic.set_main_player({ name = "Ayame" })
      logic.set_roster({
        p0 = member({ name = "Ayame", id = 1, hp = 1000, hpp = 100 }),
        p1 = member({ name = "Volker", id = 2, hp = 800, hpp = 100 }),
      })
      logic.set_own_vital("hp", 250)
      logic.set_own_vital("hpp", 24)
      assert.are.equal("800", settle().rows[2].bars.hp.text)
    end)

    it("ignores a vital it does not know", function()
      assert.has_no.errors(function()
        logic.set_own_vital("wisdom", 5)
      end)
    end)
  end)

  describe("the target cursor", function()
    before_each(function()
      logic.set_roster({ p0 = member({ name = "A", id = 1 }), p1 = member({ name = "B", id = 2 }) })
    end)

    it("marks the targeted row", function()
      logic.set_target(1, nil)
      local plan = settle()
      assert.are.equal(1, plan.rows[1].cursor)
      assert.are.equal(0, plan.rows[2].cursor)
    end)

    it("half-marks the subtargeted row", function()
      logic.set_target(nil, 2)
      assert.are.equal(0.5, settle().rows[2].cursor)
    end)

    it("prefers the target over the subtarget when both are the same row", function()
      logic.set_target(1, 1)
      assert.are.equal(1, settle().rows[1].cursor)
    end)

    it("marks nobody when nothing is targeted", function()
      logic.set_target(nil, nil)
      assert.are.equal(0, settle().rows[1].cursor)
    end)

    it("never marks a member who is outside the zone", function()
      logic.set_roster({ p0 = member({ name = "A", id = 1, zone = 50, mob = false }) })
      logic.set_target(1, nil)
      assert.are.equal(0, settle().rows[1].cursor)
    end)
  end)

  describe("leader markers", function()
    before_each(function()
      logic.set_roster({ p0 = member({ name = "A", id = 1 }), p1 = member({ name = "B", id = 2 }) })
    end)

    it("marks each role on the member holding it", function()
      logic.apply_alliance_flags({
        [1] = { leader = true, alliance_leader = false, quartermaster = true },
        [2] = { leader = false, alliance_leader = true, quartermaster = false },
      })
      local plan = settle()
      assert.are.same({ party = true, alliance = false, quartermaster = true }, plan.rows[1].leader)
      assert.are.same({ party = false, alliance = true, quartermaster = false }, plan.rows[2].leader)
    end)

    it("marks nobody before any alliance packet has arrived", function()
      assert.are.same({ party = false, alliance = false, quartermaster = false }, settle().rows[1].leader)
    end)

    -- The flags are a whole-alliance snapshot, so a member who lost a role is
    -- simply absent from the next packet's set for that bit.
    it("clears a role the newest packet no longer grants", function()
      logic.apply_alliance_flags({ [1] = { leader = true, alliance_leader = false, quartermaster = false } })
      settle()
      logic.apply_alliance_flags({ [2] = { leader = true, alliance_leader = false, quartermaster = false } })
      local plan = settle()
      assert.is_false(plan.rows[1].leader.party)
      assert.is_true(plan.rows[2].leader.party)
    end)
  end)

  describe("jobs", function()
    before_each(function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
    end)

    it("names the job and subjob a packet reported", function()
      logic.apply_job(1, { main = 4, main_level = 99, sub = 5, sub_level = 49 })
      local row = settle().rows[1]
      assert.are.equal("WHM 99", row.job_text)
      assert.are.equal("BLM 49", row.sub_job_text)
    end)

    it("names the icon and the role from the main job", function()
      logic.apply_job(1, { main = 4, main_level = 99, sub = 5, sub_level = 49 })
      local row = settle().rows[1]
      assert.are.equal("WHM", row.job_icon)
      assert.are.equal("healer", row.role)
    end)

    it("says nothing about a job it has not been told", function()
      local row = settle().rows[1]
      assert.are.equal("", row.job_text)
      assert.are.equal("", row.sub_job_text)
      assert.is_nil(row.job_icon)
    end)

    it("keeps quiet about a job id the resources do not know", function()
      logic.apply_job(1, { main = 99, main_level = 99, sub = 99, sub_level = 49 })
      assert.are.equal("", settle().rows[1].job_text)
    end)

    -- The subjob slot reads MON while in monstrosity, which is not a subjob.
    it("leaves the subjob blank for monstrosity", function()
      logic.apply_job(1, { main = 4, main_level = 99, sub = 4, sub_level = 49 })
      RESOURCES.jobs[99] = { ens = "MON" }
      logic.apply_job(1, { main = 4, main_level = 99, sub = 99, sub_level = 49 })
      local row = settle().rows[1]
      assert.are.equal("WHM 99", row.job_text)
      assert.are.equal("", row.sub_job_text)
      RESOURCES.jobs[99] = nil
    end)

    it("says nothing about the job of a member outside the zone", function()
      logic.apply_job(1, { main = 4, main_level = 99, sub = 5, sub_level = 49 })
      settle()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1, zone = 50, mob = false }) })
      local row = settle().rows[1]
      assert.are.equal("", row.job_text)
      assert.is_nil(row.job_icon)
    end)

    it("takes the main player's own job from the player, not from a packet", function()
      logic.set_main_player({
        name = "Ayame",
        main_job_id = 20,
        main_job_level = 99,
        sub_job_id = 1,
        sub_job_level = 49,
      })
      local row = settle().rows[1]
      assert.are.equal("SCH 99", row.job_text)
      assert.are.equal("WAR 49", row.sub_job_text)
    end)

    it("leaves the subjob blank for a main player who has none", function()
      logic.set_main_player({ name = "Ayame", main_job_id = 20, main_job_level = 99 })
      assert.are.equal("", settle().rows[1].sub_job_text)
    end)

    describe("trusts", function()
      before_each(function()
        logic.set_roster({
          p0 = member({ name = "Leader", id = 1 }),
          p1 = member({ name = "Mnejing", id = 2, is_npc = true }),
        })
        logic.apply_alliance_flags({ [1] = { leader = true, alliance_leader = false, quartermaster = false } })
        logic.apply_job(1, { main = 4, main_level = 90, sub = 5, sub_level = 45 })
      end)

      -- A trust reports no job in any packet, so its job comes from the name.
      it("looks the job up by name", function()
        local row = settle().rows[2]
        assert.are.equal("PLD 90", row.job_text)
        assert.are.equal("WAR 45", row.sub_job_text)
      end)

      -- XIVParty's rule: a trust is the party leader's level, sub half of it.
      it("borrows the party leader's level, and half of it for the subjob", function()
        logic.apply_job(1, { main = 4, main_level = 75, sub = 5, sub_level = 37 })
        local row = settle().rows[2]
        assert.are.equal("PLD 75", row.job_text)
        assert.are.equal("WAR 37", row.sub_job_text)
      end)

      it("never gives a trust a subjob below level one", function()
        logic.apply_job(1, { main = 4, main_level = 1, sub = 5, sub_level = 1 })
        assert.are.equal("WAR 1", settle().rows[2].sub_job_text)
      end)

      it("names the job with no level when nothing knows one", function()
        logic.apply_alliance_flags({})
        logic.set_main_player(nil)
        assert.are.equal("PLD", settle().rows[2].job_text)
      end)

      -- Solo with trusts is the common case, and there you are the leader:
      -- your own job never arrives in a party packet, so the level has to come
      -- from get_player() or every trust renders with no level at all.
      it("borrows the level from the leader even when the leader is the player", function()
        logic.set_main_player({
          name = "Leader",
          main_job_id = 4,
          main_job_level = 80,
          sub_job_id = 5,
          sub_job_level = 40,
        })
        logic.apply_job(1, nil)
        assert.are.equal("PLD 80", settle().rows[2].job_text)
        assert.are.equal("WAR 40", settle().rows[2].sub_job_text)
      end)

      -- 0x0C8 has not necessarily arrived when the first trust is called.
      it("falls back to the player's own level when no leader is known", function()
        logic.apply_alliance_flags({})
        logic.set_main_player({ name = "Leader", main_job_id = 4, main_job_level = 60 })
        assert.are.equal("PLD 60", settle().rows[2].job_text)
      end)

      it("separates trust variants by model id", function()
        logic.set_roster({ p0 = member({ name = "Iroha", id = 3, is_npc = true, model = 3112 }) })
        assert.are.equal("WHM", settle().rows[1].sub_job_text)
      end)

      it("leaves a real player with the same name as a trust alone", function()
        logic.set_roster({ p0 = member({ name = "Mnejing", id = 2, is_npc = false }) })
        assert.are.equal("", settle().rows[1].job_text)
      end)
    end)
  end)

  describe("the range indicator", function()
    local function range(distance, settings)
      config.range = settings
      logic.set_main_player({ name = "Me" })
      logic.set_roster({ p0 = member({ name = "Other", id = 2, distance = distance }) })
      return settle().rows[1].range
    end

    it("shows nothing at all when both distances are off", function()
      local shown = range(5, { numeric = false, near = 0, far = 0 })
      assert.is_false(shown.near)
      assert.is_false(shown.far)
      assert.are.equal("", shown.text)
    end)

    it("marks a member inside the near distance", function()
      local shown = range(5, { numeric = false, near = 6, far = 20 })
      assert.is_true(shown.near)
      assert.is_false(shown.far)
    end)

    it("marks a member inside the far distance but not the near one", function()
      local shown = range(10, { numeric = false, near = 6, far = 20 })
      assert.is_false(shown.near)
      assert.is_true(shown.far)
    end)

    it("marks a member beyond both with neither", function()
      local shown = range(30, { numeric = false, near = 6, far = 20 })
      assert.is_false(shown.near)
      assert.is_false(shown.far)
    end)

    it("includes a member exactly on the boundary", function()
      assert.is_true(range(6, { numeric = false, near = 6, far = 20 }).near)
    end)

    -- XIVParty lights the near icon on your own row too: the distance to
    -- yourself is zero, which is inside any near ring. Kept, because parity is
    -- the point and the numeric readout is the one that would be pure noise.
    it("marks the player themselves as near, exactly as XIVParty does", function()
      config.range = { numeric = false, near = 6, far = 20 }
      logic.set_main_player({ name = "Me" })
      logic.set_roster({ p0 = member({ name = "Me", id = 1, distance = 0 }) })
      assert.is_true(settle().rows[1].range.near)
    end)

    it("prints the distance to two places in numeric mode", function()
      assert.are.equal("12.50", range(12.5, { numeric = true, near = 6, far = 20 }).text)
    end)

    it("shows no icons in numeric mode", function()
      local shown = range(5, { numeric = true, near = 6, far = 20 })
      assert.is_false(shown.near)
      assert.is_false(shown.far)
    end)

    -- The distance to yourself is always zero, so printing it is just noise.
    it("prints no distance for the player themselves", function()
      config.range = { numeric = true, near = 0, far = 0 }
      logic.set_main_player({ name = "Me" })
      logic.set_roster({ p0 = member({ name = "Me", id = 1, distance = 0 }) })
      assert.are.equal("", settle().rows[1].range.text)
    end)

    it("prints a question mark for a member whose distance is unknown", function()
      config.range = { numeric = true, near = 0, far = 0 }
      logic.set_main_player({ name = "Me" })
      logic.set_roster({ p0 = member({ name = "Other", id = 2, mob = false, zone = 230 }) })
      assert.are.equal("?", settle().rows[1].range.text)
    end)

    it("says nothing for a member outside the zone", function()
      config.range = { numeric = true, near = 6, far = 20 }
      logic.set_main_player({ name = "Me" })
      logic.set_roster({ p0 = member({ name = "Other", id = 2, zone = 50, mob = false }) })
      assert.are.equal("", settle().rows[1].range.text)
    end)

    -- The alliance layout has no range section at all.
    it("is absent from an alliance row", function()
      build("alliance1")
      logic.set_roster({ a10 = member({ name = "Other", id = 2, distance = 5 }) })
      assert.is_nil(settle().rows[1].range)
    end)
  end)

  describe("buff icons", function()
    -- Ranks 1, 2 and 3 of the shipped order are KO, weakness and doom.
    local KO, WEAKNESS, DOOM = 0, 1, 15
    local UNRANKED, ALSO_UNRANKED = 9998, 9999

    local function shown(buffs)
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
      logic.apply_buffs(1, buffs)
      return settle().rows[1].buffs
    end

    it("orders a member's buffs by the shipped priority", function()
      assert.are.same({ KO, WEAKNESS, DOOM }, shown({ DOOM, KO, WEAKNESS }))
    end)

    it("sorts a buff the priority list has never heard of last", function()
      assert.are.same({ KO, UNRANKED }, shown({ UNRANKED, KO }))
    end)

    it("breaks a tie between two unranked buffs by id, so the order never flickers", function()
      assert.are.same({ UNRANKED, ALSO_UNRANKED }, shown({ ALSO_UNRANKED, UNRANKED }))
    end)

    it("shows nothing for a member no buff packet has covered", function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
      assert.are.same({}, settle().rows[1].buffs)
    end)

    -- 0x076 never carries the player's own buffs; get_player() does.
    it("takes the player's own buffs from the player", function()
      logic.set_main_player({ name = "Ayame", buffs = { DOOM, KO } })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
      assert.are.same({ KO, DOOM }, settle().rows[1].buffs)
    end)

    it("shows nothing for a member outside the zone", function()
      logic.apply_buffs(1, { KO })
      logic.set_roster({ p0 = member({ name = "Ayame", id = 1, zone = 50, mob = false }) })
      assert.are.same({}, settle().rows[1].buffs)
    end)

    -- The tweak: XIVParty's 19+13 icons run past the end of the row.
    it("never shows more icons than the cap", function()
      local many = {}
      for index = 1, 32 do
        many[index] = index
      end
      assert.are.equal(12, #shown(many))
      config.buffs.max_icons = 4
      assert.are.equal(4, #shown(many))
    end)

    it("keeps the highest priority buffs when the cap bites", function()
      config.buffs.max_icons = 2
      assert.are.same({ KO, WEAKNESS }, shown({ DOOM, WEAKNESS, KO }))
    end)

    -- The layout builds twelve icon prims. A hand-edited max_icons above that
    -- would silently drop the surplus while the commands claimed to draw them.
    it("never promises more icons than the layout has slots for", function()
      config.buffs.max_icons = 25
      local many = {}
      for index = 1, 32 do
        many[index] = index
      end
      assert.are.equal(12, #shown(many))
      assert.is_not_nil(table.concat(select(1, logic.command({ "buff" })), "\n"):find("first 12", 1, true))
    end)

    it("agrees with itself about the cap when max_icons is nonsense", function()
      config.buffs.max_icons = "ten"
      local many = {}
      for index = 1, 32 do
        many[index] = index
      end
      local drawn = #shown(many)
      assert.is_not_nil(table.concat(select(1, logic.command({ "buff" })), "\n"):find("first " .. drawn, 1, true))
    end)

    describe("filters", function()
      it("removes a blacklisted buff", function()
        config.buffs.filter_mode = "blacklist"
        config.buffs.filters = { WEAKNESS }
        assert.are.same({ KO, DOOM }, shown({ KO, WEAKNESS, DOOM }))
      end)

      it("keeps only the whitelisted buffs", function()
        config.buffs.filter_mode = "whitelist"
        config.buffs.filters = { WEAKNESS, DOOM }
        assert.are.same({ WEAKNESS, DOOM }, shown({ KO, WEAKNESS, DOOM }))
      end)

      it("shows everything when the blacklist is empty", function()
        config.buffs.filters = {}
        assert.are.same({ KO, WEAKNESS }, shown({ KO, WEAKNESS }))
      end)

      it("shows nothing when the whitelist is empty", function()
        config.buffs.filter_mode = "whitelist"
        config.buffs.filters = {}
        assert.are.same({}, shown({ KO, WEAKNESS }))
      end)
    end)

    describe("user priority overrides", function()
      it("moves an overridden buff to the rank it was given", function()
        config.buffs.priority = { [DOOM] = 1 }
        assert.are.same({ DOOM, KO, WEAKNESS }, shown({ KO, WEAKNESS, DOOM }))
      end)

      it("promotes a buff the shipped order does not rank at all", function()
        config.buffs.priority = { [UNRANKED] = 1 }
        assert.are.same({ UNRANKED, KO }, shown({ KO, UNRANKED }))
      end)

      it("orders two overrides by the ranks they were given", function()
        config.buffs.priority = { [DOOM] = 1, [WEAKNESS] = 2 }
        assert.are.same({ DOOM, WEAKNESS, KO }, shown({ KO, WEAKNESS, DOOM }))
      end)

      -- Two buffs asking for the same rank is a thing a user can type; the
      -- lower id taking it is arbitrary, but it has to be *decided* or the
      -- order depends on pairs() iteration order.
      it("gives a contested rank to the lower id", function()
        config.buffs.priority = { [DOOM] = 1, [WEAKNESS] = 1 }
        assert.are.same({ WEAKNESS, DOOM, KO }, shown({ KO, WEAKNESS, DOOM }))
      end)

      it("picks up a change to the overrides without a restart", function()
        assert.are.same({ KO, DOOM }, shown({ KO, DOOM }))
        config.buffs.priority = { [DOOM] = 1 }
        logic.invalidate_buff_order()
        assert.are.same({ DOOM, KO }, shown({ KO, DOOM }))
      end)
    end)

    -- 0x076 carries the main party only, and the alliance row has no buff
    -- icons, so there is nothing to show and nothing to configure.
    it("is absent from an alliance row", function()
      build("alliance1")
      logic.apply_buffs(2, { KO })
      logic.set_roster({ a10 = member({ name = "Other", id = 2 }) })
      assert.is_nil(settle().rows[1].buffs)
    end)
  end)

  describe("preview data", function()
    -- Layout mode force-shows every widget so it can be dragged. An empty
    -- party would leave nothing but a background to grab, and no way to see
    -- what a scale change did to the rows.
    it("fills every row while previewing", function()
      logic.set_roster({})
      logic.set_preview(true)
      local plan = settle()
      for slot = 1, 6 do
        assert.is_true(plan.rows[slot].occupied, "row " .. slot .. " is empty in preview")
        assert.is_true(#plan.rows[slot].name > 0)
      end
    end)

    it("shows a job, bars and buffs, so a scale change is visible", function()
      logic.set_preview(true)
      local row = settle().rows[1]
      assert.is_not_nil(row.job_icon)
      assert.are_not.equal("", row.job_text)
      assert.is_true(row.bars.hp.width > 0)
      assert.is_true(#row.buffs > 0)
    end)

    it("shows the same thing every time, so a drag does not make it jump", function()
      logic.set_preview(true)
      local first = settle().rows[1].name
      build("main")
      logic.set_preview(true)
      assert.are.equal(first, settle().rows[1].name)
    end)

    it("gives the real party back when previewing stops", function()
      logic.set_roster({ p0 = member({ name = "Ayame", id = 11 }) })
      logic.set_preview(true)
      settle()
      logic.set_preview(false)
      local plan = settle()
      assert.are.equal("Ayame", plan.rows[1].name)
      assert.is_false(plan.rows[2].occupied)
    end)

    -- The alliance row has no buff icons even in preview.
    it("previews an alliance list too", function()
      build("alliance1")
      logic.set_preview(true)
      local plan = settle()
      assert.is_true(plan.rows[6].occupied)
      assert.is_nil(plan.rows[1].buffs)
    end)
  end)

  describe("commands", function()
    -- handle_command answers with a list of lines; a spec cares about the text
    -- far more often than about which line it landed on.
    local function say(...)
      local lines, changed = logic.command({ ... })
      return table.concat(lines, "\n"), changed
    end

    it("summarises the settings when given no verb", function()
      local said = say()
      assert.is_not_nil(said:find("partylist", 1, true))
      assert.is_not_nil(said:find("spacing 0", 1, true))
    end)

    it("answers an unknown verb with a hint rather than silence", function()
      local said, changed = say("wobble")
      assert.is_false(changed)
      assert.is_not_nil(said:find("wobble", 1, true))
      assert.is_not_nil(said:find("spacing", 1, true))
    end)

    it("matches verbs case-insensitively", function()
      assert.is_true(select(2, say("SPACING", "4")))
    end)

    describe("spacing", function()
      it("sets the gap between rows", function()
        local _, changed = say("spacing", "6")
        assert.is_true(changed)
        assert.are.equal(6, config.item_spacing)
      end)

      it("accepts zero", function()
        assert.is_true(select(2, say("spacing", "0")))
      end)

      it("rejects a negative gap", function()
        local said, changed = say("spacing", "-2")
        assert.is_false(changed)
        assert.is_not_nil(said:find("whole number", 1, true))
      end)

      it("rejects something that is not a number", function()
        assert.is_false(select(2, say("spacing", "wide")))
        assert.is_false(select(2, say("spacing")))
      end)
    end)

    describe("align", function()
      it("grows the list upward", function()
        say("align", "bottom")
        assert.is_true(config.align_bottom)
      end)

      it("grows the list downward again", function()
        config.align_bottom = true
        say("align", "top")
        assert.is_false(config.align_bottom)
      end)

      it("rejects any other direction", function()
        local said, changed = say("align", "sideways")
        assert.is_false(changed)
        assert.is_not_nil(said:find("top", 1, true))
      end)
    end)

    describe("the on/off settings", function()
      it("shows and hides the empty rows", function()
        say("emptyrows", "on")
        assert.is_true(config.show_empty_rows)
        say("emptyrows", "off")
        assert.is_false(config.show_empty_rows)
      end)

      it("hides the list while solo", function()
        say("hidesolo", "on")
        assert.is_true(config.hide_solo)
      end)

      it("rejects anything that is not on or off", function()
        local said, changed = say("emptyrows", "maybe")
        assert.is_false(changed)
        assert.is_not_nil(said:find("on or off", 1, true))
      end)

      -- Solo hiding is about the main party; an alliance list has no say in it.
      it("has no hidesolo on an alliance list", function()
        build("alliance1")
        assert.is_false(select(2, say("hidesolo", "on")))
      end)
    end)

    describe("range", function()
      it("switches to the numeric readout", function()
        say("range", "num")
        assert.is_true(config.range.numeric)
      end)

      it("switches back to the icons", function()
        config.range.numeric = true
        say("range", "icons")
        assert.is_false(config.range.numeric)
      end)

      it("sets both indicator distances", function()
        local _, changed = say("range", "6", "20")
        assert.is_true(changed)
        assert.are.equal(6, config.range.near)
        assert.are.equal(20, config.range.far)
      end)

      it("turns an indicator off with a zero", function()
        say("range", "0", "0")
        assert.are.equal(0, config.range.near)
      end)

      it("rejects a far distance nearer than the near one", function()
        local said, changed = say("range", "20", "6")
        assert.is_false(changed)
        assert.is_not_nil(said:find("further", 1, true))
      end)

      it("rejects a distance that is not a number", function()
        assert.is_false(select(2, say("range", "close", "far")))
        assert.is_false(select(2, say("range")))
      end)
    end)

    describe("buff priority", function()
      local KO, WEAKNESS, DOOM = 0, 1, 15

      it("lists the icon slots that actually get drawn", function()
        local said = say("buff")
        assert.is_not_nil(said:find("KO", 1, true))
        -- Ten slots plus a heading, not the whole 621-entry order.
        assert.is_true(select(2, said:gsub("\n", "")) < 15)
      end)

      it("pages the whole order rather than only the visible slots", function()
        local said = say("buff", "list")
        assert.is_not_nil(said:find("page 1/", 1, true))
      end)

      it("jumps to a page", function()
        local first = say("buff", "list", "1")
        local third = say("buff", "list", "3")
        assert.are_not.equal(first, third)
        assert.is_not_nil(third:find("page 3/", 1, true))
      end)

      it("clamps a page number that is off either end", function()
        local pages = say("buff", "list"):match("page %d+/(%d+)")
        assert.is_not_nil(pages)
        assert.is_not_nil(say("buff", "list", "9999"):find("page " .. pages .. "/" .. pages, 1, true))
        assert.is_not_nil(say("buff", "list", "0"):find("page 1/" .. pages, 1, true))
      end)

      it("marks where the icon cap cuts the order", function()
        assert.is_not_nil(say("buff", "list", "1"):find("cut", 1, true))
      end)

      it("finds a buff by part of its name", function()
        local said = say("buff", "find", "weak")
        assert.is_not_nil(said:find("weakness", 1, true))
        assert.is_not_nil(said:find("1", 1, true))
      end)

      it("finds a buff whose name has spaces", function()
        assert.is_not_nil(say("buff", "find", "max", "hp"):find("max hp boost", 1, true))
      end)

      it("says so when a search matches nothing", function()
        local said, changed = say("buff", "find", "zzzz")
        assert.is_false(changed)
        assert.is_not_nil(said:find("no buff", 1, true))
      end)

      it("moves a buff to the top by name", function()
        local _, changed = say("buff", "top", "doom")
        assert.is_true(changed)
        assert.are.equal(1, config.buffs.priority[DOOM])
      end)

      it("moves a buff to the top by id", function()
        say("buff", "top", "15")
        assert.are.equal(1, config.buffs.priority[DOOM])
      end)

      it("moves a buff one place up", function()
        say("buff", "up", "doom")
        assert.are.equal(2, config.buffs.priority[DOOM])
      end)

      it("moves a buff one place down", function()
        say("buff", "down", "0")
        assert.are.equal(2, config.buffs.priority[KO])
      end)

      it("will not move the top buff any higher", function()
        local said, changed = say("buff", "up", "0")
        assert.is_false(changed)
        assert.is_not_nil(said:find("already", 1, true))
      end)

      it("moves a buff to a given rank", function()
        say("buff", "rank", "doom", "1")
        assert.are.equal(1, config.buffs.priority[DOOM])
      end)

      it("reports the rank a buff actually landed on, not the one asked for", function()
        local said = say("buff", "rank", "doom", "9999")
        assert.is_nil(said:find("9999", 1, true))
      end)

      it("rejects a rank that is not a positive whole number", function()
        assert.is_false(select(2, say("buff", "rank", "doom", "0")))
        assert.is_false(select(2, say("buff", "rank", "doom", "half")))
        assert.is_false(select(2, say("buff", "rank", "doom")))
      end)

      it("re-sorts the icons as soon as a rank changes", function()
        logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
        logic.apply_buffs(1, { KO, DOOM })
        assert.are.same({ KO, DOOM }, settle().rows[1].buffs)
        say("buff", "top", "doom")
        assert.are.same({ DOOM, KO }, settle().rows[1].buffs)
      end)

      -- Promoting one buff and then another is an ordinary thing to do, and
      -- the second has to win: two overrides both claiming rank 1 otherwise
      -- leaves the tie-break deciding, and the command reports a move that
      -- did not happen.
      it("lets a later promotion take the rank from an earlier one", function()
        say("buff", "top", "0")
        say("buff", "top", "doom")
        logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
        logic.apply_buffs(1, { KO, WEAKNESS, DOOM })
        assert.are.same({ DOOM, KO, WEAKNESS }, settle().rows[1].buffs)
      end)

      it("pushes the buff that held a rank down rather than dropping it", function()
        say("buff", "rank", "doom", "2")
        say("buff", "rank", "1", "2")
        logic.set_roster({ p0 = member({ name = "Ayame", id = 1 }) })
        logic.apply_buffs(1, { KO, WEAKNESS, DOOM })
        assert.are.same({ KO, WEAKNESS, DOOM }, settle().rows[1].buffs)
      end)

      it("drops every override on reset", function()
        say("buff", "top", "doom")
        local _, changed = say("buff", "reset")
        assert.is_true(changed)
        assert.are.same({}, config.buffs.priority)
      end)

      it("refuses a name it cannot resolve, and changes nothing", function()
        local said, changed = say("buff", "top", "nonsense")
        assert.is_false(changed)
        assert.is_not_nil(said:find("no buff", 1, true))
      end)

      -- Several buffs share a name -- sleep is both 2 and 19 -- so the id is
      -- the only way to say which one, and guessing would be worse than asking.
      it("refuses an ambiguous name and lists the candidates", function()
        RESOURCES.buffs[19] = { en = "sleep" }
        local said, changed = say("buff", "top", "sleep")
        RESOURCES.buffs[19] = nil
        assert.is_false(changed)
        assert.is_not_nil(said:find("2", 1, true))
        assert.is_not_nil(said:find("19", 1, true))
      end)

      describe("the live buffs on a member", function()
        before_each(function()
          logic.set_main_player({ name = "Ayame", buffs = { WEAKNESS } })
          logic.set_roster({
            p0 = member({ name = "Ayame", id = 1 }),
            p1 = member({ name = "Volker", id = 2 }),
          })
          logic.apply_buffs(2, { KO, DOOM })
        end)

        it("defaults to the player themselves", function()
          assert.is_not_nil(say("buff", "active"):find("weakness", 1, true))
        end)

        it("names a member's buffs, cap or no cap", function()
          config.buffs.max_icons = 1
          local said = say("buff", "active", "volker")
          assert.is_not_nil(said:find("KO", 1, true))
          assert.is_not_nil(said:find("doom", 1, true))
        end)

        it("says so for a member no buff packet has covered", function()
          logic.apply_buffs(2, {})
          assert.is_not_nil(say("buff", "active", "volker"):find("no buffs", 1, true))
        end)

        it("says so for a name that is not in the party", function()
          assert.is_not_nil(say("buff", "active", "nobody"):find("not in", 1, true))
        end)
      end)

      describe("filters", function()
        it("adds a buff to the filter list", function()
          local _, changed = say("buff", "filter", "add", "doom")
          assert.is_true(changed)
          assert.are.same({ DOOM }, config.buffs.filters)
        end)

        it("does not add the same buff twice", function()
          say("buff", "filter", "add", "doom")
          local _, changed = say("buff", "filter", "add", "doom")
          assert.is_false(changed)
          assert.are.equal(1, #config.buffs.filters)
        end)

        it("removes a buff from the filter list", function()
          say("buff", "filter", "add", "doom")
          say("buff", "filter", "remove", "15")
          assert.are.same({}, config.buffs.filters)
        end)

        it("says so when removing a buff that was never filtered", function()
          local said, changed = say("buff", "filter", "remove", "doom")
          assert.is_false(changed)
          assert.is_not_nil(said:find("not filtered", 1, true))
        end)

        it("empties the filter list", function()
          say("buff", "filter", "add", "doom")
          say("buff", "filter", "clear")
          assert.are.same({}, config.buffs.filters)
        end)

        it("lists the filtered buffs", function()
          say("buff", "filter", "add", "doom")
          assert.is_not_nil(say("buff", "filter", "list"):find("doom", 1, true))
        end)

        it("says so when nothing is filtered", function()
          assert.is_not_nil(say("buff", "filter", "list"):find("nothing", 1, true))
        end)

        it("switches the list between a blacklist and a whitelist", function()
          say("buff", "filter", "mode", "whitelist")
          assert.are.equal("whitelist", config.buffs.filter_mode)
          say("buff", "filter", "mode", "blacklist")
          assert.are.equal("blacklist", config.buffs.filter_mode)
        end)

        it("rejects a mode that is neither", function()
          assert.is_false(select(2, say("buff", "filter", "mode", "greylist")))
        end)

        it("answers an unknown filter verb with a hint", function()
          local said, changed = say("buff", "filter", "wobble")
          assert.is_false(changed)
          assert.is_not_nil(said:find("add", 1, true))
        end)
      end)

      -- Config files are hand-editable Lua, so `buffs` can be anything. A
      -- broken one should cost the user a hint, not an error in the guard.
      it("complains rather than erroring when the buff settings are not a table", function()
        config.buffs = "nonsense"
        local said, changed = say("buff", "top", "doom")
        assert.is_false(changed)
        assert.is_not_nil(said:find("reset", 1, true))
        assert.is_false(select(2, say("buff", "filter", "list")))
      end)

      -- The alliance row has no buff icons, so it has nothing to configure.
      it("is absent from an alliance list", function()
        build("alliance1")
        local said, changed = say("buff", "top", "doom")
        assert.is_false(changed)
        assert.is_not_nil(said:find("buff", 1, true))
      end)
    end)
  end)
end)
