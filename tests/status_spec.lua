local new_status = require("lib.status")
local fakes = require("tests.support.fakes")

describe("status", function()
  local function status_for(player)
    return new_status(fakes.status_deps(player))
  end

  it("returns nil when not logged in", function()
    assert.is_nil(status_for(nil).player_status())
  end)

  it("maps known status codes", function()
    assert.are.equal("Idle", status_for({ status = 0 }).player_status())
    assert.are.equal("Engaged", status_for({ status = 1 }).player_status())
  end)

  it("falls back to Unknown for unmapped codes", function()
    assert.are.equal("Unknown", status_for({ status = 99 }).player_status())
  end)
end)
