--[[ The entry point cannot be *run* here — it reads Windower globals — but it
     can be parsed, and until now nothing checked that it even compiled. A
     syntax error in src/XIVHud.lua would have reached the client untouched by
     the suite, which is precisely the file hardest to debug there. ]]

local function lua_sources()
  local handle = assert(io.popen("find src -name '*.lua' | sort"))
  local paths = {}
  for line in handle:lines() do
    paths[#paths + 1] = line
  end
  handle:close()
  return paths
end

describe("sources", function()
  local paths = lua_sources()

  it("finds the addon's source files", function()
    assert.is_true(#paths >= 12, "expected the whole addon, found " .. #paths)
  end)

  it("compiles every source file, including the entry point", function()
    for _, path in ipairs(paths) do
      local chunk, err = loadfile(path)
      assert.is_not_nil(chunk, path .. " does not compile: " .. tostring(err))
    end
  end)

  it("carries the BSD licence header on every source file", function()
    for _, path in ipairs(paths) do
      local file = assert(io.open(path, "r"))
      local head = file:read(2000) or ""
      file:close()
      assert.is_not_nil(head:find("Redistribution and use in source", 1, true), path .. " has no licence header")
    end
  end)

  -- FFXI's chat is not UTF-8, so a multi-byte character reaches the player as
  -- mojibake: an em dash arrives as "â€”". Comments are exempt -- they are never
  -- displayed, and the licence headers must keep their "Copyright ©".
  it("keeps source outside comments to plain ASCII, because chat is not UTF-8", function()
    for _, path in ipairs(paths) do
      local file = assert(io.open(path, "r"))
      local body = file:read("*a")
      file:close()

      local without_comments = body:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
      local offset = without_comments:find("[\128-\255]")
      if offset then
        local line = select(2, without_comments:sub(1, offset):gsub("\n", "")) + 1
        error(("%s has a non-ASCII byte outside a comment, around line %d of the stripped source"):format(path, line))
      end
    end
  end)

  it("requires internal modules with slashes, the form Windower resolves", function()
    for _, path in ipairs(paths) do
      local file = assert(io.open(path, "r"))
      local body = file:read("*a")
      file:close()
      for name in body:gmatch('require%("([%w_%./]+)"%)') do
        if name:find("^lib%.") or name:find("^components%.") then
          error(path .. " uses dot-form require('" .. name .. "'); use slashes")
        end
      end
    end
  end)
end)
