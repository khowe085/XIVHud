local new_weapon = require("components/crossbar/weapon")

-- The client's own shapes, cut down to what the resolver reads: an equipment
-- table of <slot> / <slot>_bag pairs, whole-bag reads keyed by bag and index,
-- and the two resource tables the skill name is walked through.
-- `nil` cannot ride in an overrides table - pairs would skip the key and the
-- default would stand - so absence is spelled.
local NONE = {}

local function deps(overrides)
  local built = {
    equipment = { main = 3, main_bag = 0 },
    items = { [0] = { [3] = { id = 17040 } } },
    resources = {
      items = { [17040] = { skill = 4 }, [17800] = { skill = 0 }, [18000] = {} },
      -- Skill 0 carries a NAME here on purpose: every non-weapon item reads
      -- as skill 0, and a fixture with no [0] row would let the guard
      -- against it be deleted without a test noticing.
      skills = {
        [0] = { en = "(None)" },
        [1] = { en = "Hand-to-Hand" },
        [4] = { en = "Sword" },
        [9] = { en = "Great Katana" },
      },
    },
  }
  for key, value in pairs(overrides or {}) do
    built[key] = value ~= NONE and value or nil
  end
  local calls = {}
  return {
    get_equipment = function()
      return built.equipment
    end,
    get_items = function(bag, index)
      calls[#calls + 1] = { bag = bag, index = index }
      local held = built.items[bag]
      return held and held[index] or nil
    end,
    resources = built.resources,
    -- What the reads were actually asked for. Windower drops a nil argument
    -- without complaint, so "it answered nil anyway" is not the same fact as
    -- "it was never asked".
    calls = calls,
  }
end

describe("crossbar weapon", function()
  it("names the main hand's weapon skill", function()
    local name, known = new_weapon(deps()).resolve()
    assert.equal("Sword", name)
    assert.is_true(known)
  end)

  it("reads the bag the equipment table names, not a fixed one", function()
    local weapon = new_weapon(deps({
      equipment = { main = 2, main_bag = 8 },
      items = { [8] = { [2] = { id = 17040 } } },
    }))
    assert.equal("Sword", weapon.resolve())
  end)

  -- Unarmed IS hand-to-hand in game terms, so it shares the layer a pair of
  -- Republic Kicks would use (Kevin, 2026-09-04).
  it("answers Hand-to-Hand for an empty main hand", function()
    local name, known = new_weapon(deps({ equipment = { main = 0, main_bag = 0 } })).resolve()
    assert.equal("Hand-to-Hand", name)
    assert.is_true(known)
  end)

  it("answers Hand-to-Hand when the table names other slots but no main", function()
    assert.equal("Hand-to-Hand", new_weapon(deps({ equipment = { head = 4, head_bag = 0 } })).resolve())
  end)

  --[[ A table with no slot key in it at all is a client that has not filled
       one in yet, not a character wearing nothing anywhere: the read is
       whole-inventory and the client answers it whole. Reading it as unarmed
       would LATCH Hand-to-Hand at login and clear the dirty flag with it,
       and nothing would ask again until the player next changed gear. ]]
  it("answers nothing at all for an equipment table with no slots in it", function()
    local name, known = new_weapon(deps({ equipment = {} })).resolve()
    assert.is_nil(name)
    assert.is_false(known)
  end)

  --[[ The two nils are different facts, and the second return tells them
       apart: an unread equipment table is the ordinary state for the first
       frames of a login and must leave the layer alone, while an item that
       resolves to nothing IS an answer - there is no weapon layer - and
       clears it. A wrong layer is worse than none. ]]
  it("answers nothing at all while the client cannot be read", function()
    local name, known = new_weapon(deps({ equipment = NONE })).resolve()
    assert.is_nil(name)
    assert.is_false(known)
  end)

  it("answers nothing at all without the resources library", function()
    local name, known = new_weapon(deps({ resources = NONE })).resolve()
    assert.is_nil(name)
    assert.is_false(known)
  end)

  it("clears the layer when the equipped item cannot be read", function()
    local name, known = new_weapon(deps({ items = {} })).resolve()
    assert.is_nil(name)
    assert.is_true(known)
  end)

  it("clears the layer when the index carries no bag beside it", function()
    local built = deps({ equipment = { main = 3 } })
    local name, known = new_weapon(built).resolve()
    assert.is_nil(name)
    assert.is_true(known)
    -- And the nil never rode into the client call: Lua drops a missing
    -- argument silently, so the read would have gone out asking for
    -- whatever bag 0 happened to hold.
    assert.are.same({}, built.calls)
  end)

  it("clears the layer for an item the resources do not know", function()
    local name, known = new_weapon(deps({ items = { [0] = { [3] = { id = 65535 } } } })).resolve()
    assert.is_nil(name)
    assert.is_true(known)
  end)

  it("clears the layer for an item that carries no weapon skill", function()
    assert.is_nil(new_weapon(deps({ items = { [0] = { [3] = { id = 17800 } } } })).resolve())
    assert.is_nil(new_weapon(deps({ items = { [0] = { [3] = { id = 18000 } } } })).resolve())
  end)

  it("clears the layer for a skill the resources cannot name", function()
    local name, known = new_weapon(deps({
      resources = { items = { [17040] = { skill = 41 } }, skills = { [41] = {} } },
    })).resolve()
    assert.is_nil(name)
    assert.is_true(known)
  end)

  it("survives a client that answers a scalar where a table belongs", function()
    assert.is_nil(new_weapon(deps({ equipment = "nope" })).resolve())
    assert.is_nil(new_weapon(deps({ items = { [0] = { [3] = 17040 } } })).resolve())
  end)

  it("cannot answer without the two reads it is built on", function()
    local name, known = new_weapon({}).resolve()
    assert.is_nil(name)
    assert.is_false(known)
  end)
end)
