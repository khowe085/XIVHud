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
    assert.same({ "light-arts", "dark-arts", "addendum-white", "addendum-black", "unbridled" }, names)
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

  --[[ One context over both, the way light-arts counts its addendum: Wisdom
       is the merit upgrade of Learning and the bar wants the same slots for
       either. Ids off this repo's own ported table
       (src/components/partylist/buff_order.lua), never from memory. ]]
  it("activates unbridled on Learning or its merit upgrade Wisdom", function()
    assert.same({ 485, 505 }, find("unbridled").any_of)
  end)

  it("puts unbridled last, above the arts family", function()
    local _, index = find("unbridled")
    assert.equal(#contexts, index)
  end)

  it("labels every entry with its in-game name", function()
    assert.equal("Light Arts", find("light-arts").label)
    assert.equal("Dark Arts", find("dark-arts").label)
    assert.equal("Addendum: White", find("addendum-white").label)
    assert.equal("Addendum: Black", find("addendum-black").label)
  end)

  --[[ The job gate (Kevin, 2026-09-04): a context belongs to the job whose
       buff it watches, and off that job it is neither listed nor live.
       `jobs` counts the SUB job too - Light Arts is a level 10 ability and
       Addendum: White level 20, both inside a subjob's reach - except where
       `main_only` says otherwise. ]]
  it("scopes the arts family to SCH, subjob included", function()
    for _, name in ipairs({ "light-arts", "dark-arts", "addendum-white", "addendum-black" }) do
      assert.same({ "SCH" }, find(name).jobs, name .. " is not scoped to SCH")
      assert.is_nil(find(name).main_only, name .. " is main-only")
    end
  end)

  -- Unbridled Learning is learned at BLU 96, so no subjob can ever hold it.
  it("scopes unbridled to a BLU main job alone", function()
    assert.same({ "BLU" }, find("unbridled").jobs)
    assert.is_true(find("unbridled").main_only)
  end)

  it("names a job for every entry it ships", function()
    for _, context in ipairs(contexts) do
      assert.is_table(context.jobs, context.name .. " names no job")
      assert.is_true(#context.jobs > 0, context.name .. " names no job")
    end
  end)

  it("carries an icon per entry", function()
    for _, context in ipairs(contexts) do
      assert.is_string(context.icon, context.name .. " has no icon")
    end
  end)
end)
