local contexts = require("components/crossbar/contexts")

local function find(name)
  for index, context in ipairs(contexts) do
    if context.name == name then
      return context, index
    end
  end
end

describe("crossbar contexts", function()
  it("ships the v1 roster in stack order, arts under addenda", function()
    local names = {}
    for _, context in ipairs(contexts) do
      names[#names + 1] = context.name
    end
    assert.same({ "light-arts", "dark-arts", "addendum-white", "addendum-black" }, names)
  end)

  it("keeps light-arts active on the Addendum: White buff alone", function()
    -- Using an Addendum fires a spurious arts `lose buff` while arts is still
    -- active; 401 in the arts predicate is half the defence (the other half is
    -- re-syncing from the full buff list, which is bindings' job).
    assert.same({ 358, 401 }, find("light-arts").any_of)
  end)

  it("keeps dark-arts active on the Addendum: Black buff alone", function()
    assert.same({ 359, 402 }, find("dark-arts").any_of)
  end)

  it("activates each addendum on its own buff only", function()
    assert.same({ 401 }, find("addendum-white").any_of)
    assert.same({ 402 }, find("addendum-black").any_of)
  end)

  it("labels every entry with its in-game name", function()
    assert.equal("Light Arts", find("light-arts").label)
    assert.equal("Dark Arts", find("dark-arts").label)
    assert.equal("Addendum: White", find("addendum-white").label)
    assert.equal("Addendum: Black", find("addendum-black").label)
  end)

  it("carries an icon per entry", function()
    for _, context in ipairs(contexts) do
      assert.is_string(context.icon, context.name .. " has no icon")
    end
  end)
end)
