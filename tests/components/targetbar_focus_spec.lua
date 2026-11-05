local new_focus = require("components/targetbar/focus")

local function mob(fields)
  local result = { id = 300, name = "Colibri", hpp = 100, status = 1, distance = 100 }
  for key, value in pairs(fields or {}) do
    result[key] = value
  end
  return result
end

local function u32(value)
  return string.char(
    value % 256,
    math.floor(value / 256) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 16777216) % 256
  )
end

-- 0x038 laid out as Windower's fields.lua has it: Mob at 0x04, the animation
-- name at 0x0C.
local function despawn(id)
  return "\56\0\0\0" .. u32(id) .. u32(id) .. "kesu\0\0\0\0"
end

describe("targetbar focus", function()
  local focus

  before_each(function()
    focus = new_focus()
  end)

  it("holds nothing until it is given a mob", function()
    assert.is_nil(focus.id())
    assert.is_nil(focus.name())
  end)

  describe("taking a mob", function()
    it("holds its id and its name", function()
      assert.is_true(focus.take(mob(), "colibri"))
      assert.are.equal(300, focus.id())
      assert.are.equal("Colibri", focus.name())
    end)

    it("names it as typed when the mob carries no name", function()
      focus.take(mob({ name = false }), "colibri")
      assert.are.equal("colibri", focus.name())
    end)

    it("refuses what cannot be focused, and keeps what it held", function()
      local unnumbered = mob()
      unnumbered.id = nil
      focus.take(mob({ id = 1 }), "first")
      for _, refused in ipairs({
        false,
        unnumbered,
        mob({ hpp = 0 }),
        mob({ status = 2 }),
        mob({ status = 3 }),
        mob({ valid_target = false }),
      }) do
        assert.is_false(focus.take(refused or nil, "x"))
        assert.are.equal(1, focus.id())
      end
    end)
  end)

  describe("tokens", function()
    it("maps each token it takes to the client's word, in any case", function()
      assert.are.equal("t", focus.token("<t>"))
      assert.are.equal("st", focus.token("<ST>"))
      assert.are.equal("bt", focus.token("<bt>"))
    end)

    it("reads anything else as a name", function()
      assert.is_nil(focus.token("Colibri"))
      assert.is_nil(focus.token("t"))
    end)

    -- No mob's name is wrapped in angle brackets.
    it("tells a token it does not take from a name", function()
      assert.is_true(focus.unknown_token("<pet>"))
      assert.is_true(focus.unknown_token("<P1>"))
      assert.is_false(focus.unknown_token("<t>"))
      assert.is_false(focus.unknown_token("Colibri"))
    end)

    it("lists the tokens it takes, in order", function()
      assert.are.same({ "<t>", "<st>", "<bt>" }, focus.tokens())
    end)
  end)

  describe("finding a mob by name", function()
    it("matches the whole name in any case, never a part of it", function()
      local array = { mob() }
      assert.are.equal(300, focus.find("COLIBRI", nil, array).id)
      assert.is_nil(focus.find("colib", nil, array))
    end)

    -- Distance is squared in the mob table; ordering is all that matters.
    it("takes the nearest of several with the name", function()
      local array = {
        mob({ id = 1, distance = 400 }),
        mob({ id = 2, distance = 100 }),
        mob({ id = 3, distance = 900 }),
      }
      assert.are.equal(2, focus.find("Colibri", nil, array).id)
    end)

    it("passes over a mob that cannot be focused", function()
      local array = {
        mob({ id = 1, distance = 1, valid_target = false }),
        mob({ id = 2, distance = 4, hpp = 0 }),
        mob({ id = 3, distance = 9 }),
      }
      assert.are.equal(3, focus.find("Colibri", nil, array).id)
    end)

    it("takes the target over a nearer mob of the same name", function()
      local target = mob({ id = 2, distance = 900 })
      local array = { mob({ id = 1, distance = 1 }), target }
      assert.are.equal(2, focus.find("colibri", target, array).id)
    end)

    it("passes over a target of another name", function()
      local array = { mob({ id = 1 }) }
      assert.are.equal(1, focus.find("Colibri", mob({ id = 2, name = "Bat" }), array).id)
    end)

    it("passes over a target that cannot be focused", function()
      local array = { mob({ id = 1, distance = 400 }) }
      assert.are.equal(1, focus.find("Colibri", mob({ id = 2, distance = 1, hpp = 0 }), array).id)
    end)

    it("ranks a mob of unknown distance behind one it can measure", function()
      local array = { mob({ id = 1, distance = false }), mob({ id = 2, distance = 900 }) }
      assert.are.equal(2, focus.find("Colibri", nil, array).id)
    end)

    it("finds nothing in an array it was not given", function()
      assert.is_nil(focus.find("Colibri", nil, nil))
    end)
  end)

  describe("each frame", function()
    before_each(function()
      focus.take(mob(), "Colibri")
    end)

    it("draws nothing while nothing is held", function()
      focus.clear()
      assert.is_nil(focus.resolve(mob()))
    end)

    it("draws the mob the client answers for the held id", function()
      assert.are.equal(300, focus.resolve(mob({ hpp = 55 })).id)
    end)

    it("lets go when the client no longer has it", function()
      assert.is_nil(focus.resolve(nil))
      assert.is_nil(focus.id())
    end)

    it("lets go when it dies", function()
      for _, dead in ipairs({ mob({ hpp = 0 }), mob({ status = 2 }), mob({ status = 3 }) }) do
        focus.take(mob(), "Colibri")
        assert.is_nil(focus.resolve(dead))
        assert.is_nil(focus.id())
      end
    end)

    -- Out of draw range is not gone: nothing is drawn and the focus is kept.
    it("only hides one that cannot be targeted", function()
      assert.is_nil(focus.resolve(mob({ valid_target = false })))
      assert.are.equal(300, focus.id())
    end)
  end)

  describe("chunks", function()
    before_each(function()
      focus.take(mob(), "Colibri")
    end)

    it("lets go on a zone", function()
      focus.on_chunk(0x00A, "zone bytes")
      assert.is_nil(focus.id())
    end)

    it("lets go when its mob despawns", function()
      focus.on_chunk(0x038, despawn(300))
      assert.is_nil(focus.id())
    end)

    it("keeps it through another mob's despawn", function()
      focus.on_chunk(0x038, despawn(301))
      assert.are.equal(300, focus.id())
    end)

    it("shrugs off a chunk it cannot read", function()
      focus.on_chunk(0x038, nil)
      focus.on_chunk(0x038, "\56\0")
      focus.on_chunk(0x028, despawn(300))
      assert.are.equal(300, focus.id())
    end)
  end)
end)
