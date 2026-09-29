local contexts = require("lib/actionbar/contexts")

local function find(name)
  for index, context in ipairs(contexts) do
    if context.name == name then
      return context, index
    end
  end
end

describe("crossbar contexts", function()
  it("ships the roster in stack order, arts under addenda", function()
    local names = {}
    for _, context in ipairs(contexts) do
      names[#names + 1] = context.name
    end
    assert.same({
      "klimaform",
      "sandstorm",
      "rainstorm",
      "windstorm",
      "firestorm",
      "hailstorm",
      "thunderstorm",
      "voidstorm",
      "aurorastorm",
      "composure",
      "light-arts",
      "dark-arts",
      "addendum-white",
      "addendum-black",
      "unbridled",
    }, names)
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

  --[[ Composure (Kevin, 2026-09-13). It sits under the arts family: `jobs`
       counts the sub job for arts, so a RDM/SCH can hold Composure and Light
       Arts at once, and Kevin's call is that the arts layer wins there.
       Unbridled is BLU-main and Composure RDM-main, so those two can never
       co-occur and their relative order says nothing. ]]
  it("activates composure on its own buff", function()
    assert.same({ 419 }, find("composure").any_of)
  end)

  -- The storm family went in under it (Kevin, 2026-09-29): a RDM/SCH can
  -- hold Composure and a storm at once, and Composure wins there.
  it("puts composure above the storm family, under the arts family", function()
    local _, index = find("composure")
    local _, storm = find("aurorastorm")
    local _, arts = find("light-arts")
    assert.equal(storm + 1, index)
    assert.equal(index + 1, arts)
  end)

  --[[ The storm family (Kevin, 2026-09-29): one context per storm, each
       counting its Storm II buff too, the way an arts context counts its
       addendum - the II spell raises a buff id of its own, and the bar wants
       the same slots for either. The ids are each spell's own `status` in
       Windower's spells resource, read 2026-09-29, and agree with
       lib/buff_order. ]]
  local STORMS = {
    { name = "sandstorm", label = "Sandstorm", any_of = { 181, 592 }, spell = 99 },
    { name = "rainstorm", label = "Rainstorm", any_of = { 183, 594 }, spell = 113 },
    { name = "windstorm", label = "Windstorm", any_of = { 180, 591 }, spell = 114 },
    { name = "firestorm", label = "Firestorm", any_of = { 178, 589 }, spell = 115 },
    { name = "hailstorm", label = "Hailstorm", any_of = { 179, 590 }, spell = 116 },
    { name = "thunderstorm", label = "Thunderstorm", any_of = { 182, 593 }, spell = 117 },
    { name = "voidstorm", label = "Voidstorm", any_of = { 185, 596 }, spell = 118 },
    { name = "aurorastorm", label = "Aurorastorm", any_of = { 184, 595 }, spell = 119 },
  }

  it("activates each storm on its Storm I or Storm II buff", function()
    for _, storm in ipairs(STORMS) do
      assert.same(storm.any_of, find(storm.name).any_of, storm.name)
    end
  end)

  it("activates klimaform on its own buff", function()
    assert.same({ 407 }, find("klimaform").any_of)
  end)

  -- Klimaform and a storm are usually up together (one storm at a time, so
  -- the storms' order among themselves says nothing), and the storm wins.
  it("puts klimaform first, under the storms", function()
    local _, index = find("klimaform")
    local _, storm = find("sandstorm")
    assert.equal(1, index)
    assert.equal(2, storm)
  end)

  -- Every storm is SCH 41-48 and Klimaform SCH 46, all inside /SCH's reach.
  it("scopes the storm family to SCH, subjob included", function()
    local names = { "klimaform" }
    for _, storm in ipairs(STORMS) do
      names[#names + 1] = storm.name
    end
    for _, name in ipairs(names) do
      assert.same({ "SCH" }, find(name).jobs, name .. " is not scoped to SCH")
      assert.is_nil(find(name).main_only, name .. " is main-only")
    end
  end)

  --[[ The art the BAR draws for the spell (Kevin): a slot bound to `ma
       Sandstorm` finds no `white-magic/sandstorm.png` in the pack and falls
       to the spell sheet, keyed by recast id, which is the spell id for all
       nine. ]]
  it("draws each storm and klimaform with its spell's own sheet art", function()
    for _, storm in ipairs(STORMS) do
      assert.equal(("spells/%05d"):format(storm.spell), find(storm.name).icon, storm.name)
    end
    assert.equal("spells/00287", find("klimaform").icon)
  end)

  --[[ BG wiki, read 2026-09-13: obtained at RDM 50, and "this ability is not
       accessible if Red Mage is set as a sub job" - stated outright rather
       than inferred from the level cap. ]]
  it("scopes composure to a RDM main job alone", function()
    assert.same({ "RDM" }, find("composure").jobs)
    assert.is_true(find("composure").main_only)
  end)

  it("labels every entry with its in-game name", function()
    assert.equal("Light Arts", find("light-arts").label)
    assert.equal("Dark Arts", find("dark-arts").label)
    assert.equal("Addendum: White", find("addendum-white").label)
    assert.equal("Addendum: Black", find("addendum-black").label)
    assert.equal("Composure", find("composure").label)
    assert.equal("Klimaform", find("klimaform").label)
    for _, storm in ipairs(STORMS) do
      assert.equal(storm.label, find(storm.name).label)
    end
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

  -- A texture path that does not exist fails SILENTLY - the prim draws
  -- nothing (CLAUDE.md) - so every name is opened on disk.
  it("names art that actually ships, on every entry", function()
    for _, context in ipairs(contexts) do
      local path = "src/assets/icons/" .. context.icon .. ".png"
      local art = io.open(path, "rb")
      assert.is_not_nil(art, path .. " does not ship")
      art:close()
    end
  end)

  -- The entry point load-checks every icon the roster names outright, so a
  -- file lost from a package says so at load rather than drawing nothing.
  it("has the entry point's load check name every entry's art", function()
    local source = assert(io.open("src/XIVHud.lua", "r"))
    local body = source:read("*a")
    source:close()
    for _, context in ipairs(contexts) do
      local texture = '"icons/' .. context.icon .. '.png"'
      assert.is_not_nil(body:find(texture, 1, true), context.name .. ": " .. texture .. " is not load-checked")
    end
  end)
end)
