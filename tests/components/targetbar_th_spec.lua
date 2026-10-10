local new_th = require("components/targetbar/th")

-- A parsed 0x028 the way windower.packets.parse_action shapes it, with one
-- target and one action unless the test says otherwise.
local function action(category, target_id, fields)
  local first = {}
  for key, value in pairs(fields or {}) do
    first[key] = value
  end
  return {
    actor_id = 1,
    category = category,
    targets = { { id = target_id, actions = { first } } },
  }
end

local function melee_proc(target_id, level)
  return action(
    1,
    target_id,
    { message = 1, has_add_effect = true, add_effect_message = 603, add_effect_param = level }
  )
end

local function ability_proc(target_id, level)
  return action(3, target_id, { message = 608, param = level })
end

local function u32(value)
  return string.char(
    value % 256,
    math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 16777216) % 256
  )
end

-- Raw chunks, header included, laid out as Windower's fields.lua has them:
-- 0x038 Mob at 0x04 and the animation name at 0x0C; 0x00E NPC at 0x04, HP %
-- at 0x1E and Status at 0x1F.
local function animation(mob_id, name)
  return "\56\0\0\0" .. u32(mob_id) .. u32(mob_id) .. name .. "\0\0\0\0"
end

local function npc_update(mob_id, hpp, status)
  return "\14\0\0\0" .. u32(mob_id) .. ("\0"):rep(0x1E - 8) .. string.char(hpp, status) .. ("\0"):rep(0x14)
end

local MOB = 0x0100A0B1

describe("targetbar th tracker", function()
  local th

  before_each(function()
    th = new_th()
  end)

  it("knows nothing about a mob it has seen no proc on", function()
    assert.is_nil(th.level(MOB))
  end)

  describe("a proc", function()
    it("on a melee round's added effect sets the level", function()
      th.on_action(melee_proc(MOB, 4))
      assert.are.equal(4, th.level(MOB))
    end)

    it("from a weaponskill's message 608 sets the level", function()
      th.on_action(ability_proc(MOB, 9))
      assert.are.equal(9, th.level(MOB))
    end)

    it("replaces the level the mob had", function()
      th.on_action(melee_proc(MOB, 4))
      th.on_action(melee_proc(MOB, 5))
      assert.are.equal(5, th.level(MOB))
    end)

    it("is kept per mob", function()
      th.on_action(melee_proc(MOB, 4))
      th.on_action(melee_proc(MOB + 1, 7))
      assert.are.equal(4, th.level(MOB))
      assert.are.equal(7, th.level(MOB + 1))
    end)
  end)

  describe("what is not a proc", function()
    it("an added effect with another message", function()
      th.on_action(action(1, MOB, { has_add_effect = true, add_effect_message = 163, add_effect_param = 4 }))
      assert.is_nil(th.level(MOB))
    end)

    it("message 603 without the added-effect flag", function()
      th.on_action(action(1, MOB, { has_add_effect = false, add_effect_message = 603, add_effect_param = 4 }))
      assert.is_nil(th.level(MOB))
    end)

    it("message 608 outside category 3", function()
      th.on_action(action(1, MOB, { message = 608, param = 4 }))
      assert.is_nil(th.level(MOB))
    end)

    it("an added effect 603 outside category 1", function()
      th.on_action(action(3, MOB, { has_add_effect = true, add_effect_message = 603, add_effect_param = 4 }))
      assert.is_nil(th.level(MOB))
    end)

    -- The reference reads Target 1 Action 1 alone.
    it("a proc past the first action", function()
      local act = melee_proc(MOB, 4)
      table.insert(act.targets[1].actions, 1, { message = 1, has_add_effect = false })
      th.on_action(act)
      assert.is_nil(th.level(MOB))
    end)

    it("a proc on a second target", function()
      local act = ability_proc(MOB, 4)
      table.insert(act.targets, 1, { id = MOB + 1, actions = { { message = 110, param = 0 } } })
      th.on_action(act)
      assert.is_nil(th.level(MOB))
      assert.is_nil(th.level(MOB + 1))
    end)

    it("a level that is not a number", function()
      th.on_action(melee_proc(MOB, nil))
      assert.is_nil(th.level(MOB))
    end)
  end)

  -- Windower fails silently, and a handler that throws is disabled for the
  -- session: every malformed shape must be a no-op.
  it("ignores malformed actions", function()
    assert.has_no.errors(function()
      th.on_action(nil)
      th.on_action("bytes")
      th.on_action({ category = 1 })
      th.on_action({ category = 1, targets = {} })
      th.on_action({ category = 1, targets = { {} } })
      th.on_action({ category = 1, targets = { { id = MOB, actions = { "x" } } } })
    end)
    assert.is_nil(th.level(MOB))
  end)

  describe("forgetting", function()
    before_each(function()
      th.on_action(melee_proc(MOB, 4))
      th.on_action(melee_proc(MOB + 1, 6))
    end)

    it("a mob that despawns", function()
      th.on_chunk(0x038, animation(MOB, "kesu"))
      assert.is_nil(th.level(MOB))
      assert.are.equal(6, th.level(MOB + 1))
    end)

    it("not on any other animation", function()
      th.on_chunk(0x038, animation(MOB, "deru"))
      assert.are.equal(4, th.level(MOB))
    end)

    it("a mob reset to full health and idle", function()
      th.on_chunk(0x00E, npc_update(MOB, 100, 0))
      assert.is_nil(th.level(MOB))
      assert.are.equal(6, th.level(MOB + 1))
    end)

    it("not while it is still hurt or engaged", function()
      th.on_chunk(0x00E, npc_update(MOB, 99, 0))
      th.on_chunk(0x00E, npc_update(MOB, 100, 1))
      assert.are.equal(4, th.level(MOB))
    end)

    it("everything on a zone", function()
      th.on_chunk(0x00A, "zone in bytes")
      assert.is_nil(th.level(MOB))
      assert.is_nil(th.level(MOB + 1))
    end)

    it("everything on clear", function()
      th.clear()
      assert.is_nil(th.level(MOB))
      assert.is_nil(th.level(MOB + 1))
    end)

    it("nothing on a packet it does not read", function()
      th.on_chunk(0x0D2, animation(MOB, "kesu"))
      assert.are.equal(4, th.level(MOB))
    end)

    it("nothing on a truncated chunk", function()
      assert.has_no.errors(function()
        th.on_chunk(0x038, "\56\0")
        th.on_chunk(0x00E, "\14\0\0\0" .. u32(MOB))
        th.on_chunk(0x038, nil)
      end)
      assert.are.equal(4, th.level(MOB))
    end)
  end)
end)
