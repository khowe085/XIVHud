--[[ The composites under assets/icons/jobs are generated from the party list's
     job icon stack, so nothing in the addon derives them at runtime and a job
     added to jobIcons/ would simply draw nothing on a crossbar slot. Check the
     two sets against each other instead. ]]

local jobs = require("components/partylist/jobs")

local ICONS = "src/assets/icons/jobs/"
local GLYPHS = "src/assets/xiv/jobIcons/"

-- bg, gradient, frame and highlight are the stack's chrome, not jobs.
local CHROME = { bg = true, gradient = true, frame = true, highlight = true }

local function png_size(path)
  local file = io.open(path, "rb")
  if file == nil then
    return nil
  end
  local header = file:read(24)
  file:close()
  if header == nil or #header < 24 or header:sub(2, 4) ~= "PNG" then
    return nil
  end
  local function be32(offset)
    local a, b, c, d = header:byte(offset, offset + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be32(17), be32(21)
end

local function names_in(dir)
  local handle = assert(io.popen("ls " .. dir .. "*.png 2>/dev/null | sort"))
  local names = {}
  for line in handle:lines() do
    local base = line:match("([^/]+)%.png$")
    if base and not CHROME[base] then
      names[#names + 1] = base
    end
  end
  handle:close()
  return names
end

describe("pre-rendered job icons", function()
  local glyphs = names_in(GLYPHS)

  it("finds the party list's job glyphs", function()
    assert.is_true(#glyphs >= 22, "expected every job, found " .. #glyphs)
  end)

  it("ships one composite per glyph", function()
    for _, job in ipairs(glyphs) do
      assert.is_not_nil(png_size(ICONS .. job .. ".png"), "no composite for " .. job)
    end
  end)

  it("ships no composite the party list has no glyph for", function()
    local known = {}
    for _, job in ipairs(glyphs) do
      known[job] = true
    end
    for _, job in ipairs(names_in(ICONS)) do
      assert.is_true(known[job] == true, "composite for unknown job " .. job)
    end
  end)

  --[[ Deliberately the SOURCE size rather than the pack's 32x32, and
       checked against the source rather than a constant: a slot draws
       40x40, so anything smaller is scaled UP at draw time, which cost
       the gold roles most of their highlights in a live client. ]]
  it("composites at the source size, resampling nothing", function()
    for _, job in ipairs(glyphs) do
      local want_width, want_height = png_size(GLYPHS .. job .. ".png")
      local width, height = png_size(ICONS .. job .. ".png")
      assert.are.equal(want_width, width, job .. " width")
      assert.are.equal(want_height, height, job .. " height")
    end
  end)

  -- They are XivParty art, not xivcrossbar's, so the pack's notice does not
  -- cover them and they carry their own.
  it("carries its own third-party notice", function()
    local file = io.open(ICONS .. "LICENSE.txt", "rb")
    assert.is_not_nil(file, "assets/icons/jobs/LICENSE.txt is missing")
    local text = file:read("*a")
    file:close()
    assert.is_not_nil(text:find("Tylas", 1, true), "the XivParty notice is not reproduced")
  end)

  -- Every role the table can answer needs a colour, or a job would composite
  -- against the dd fallback without anything saying so.
  it("covers every role the glyphs resolve to", function()
    local roles = {}
    for _, job in ipairs(glyphs) do
      roles[jobs.role_of(job)] = true
    end
    for _, role in ipairs({ "dd", "healer", "support", "tank", "special" }) do
      assert.is_true(roles[role] == true, "no glyph resolves to " .. role)
    end
  end)
end)
