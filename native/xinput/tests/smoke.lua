--[[ The real DLL on a Windows CI runner, which has no pad: run by
     `build.cmd test`, under a stock Lua 5.1.5 with the test build on its
     cpath. What a pad answers is luaxinput_spec.lua's, over the fake. ]]

local xinput = require("_LuaXInput")

local function check(condition, message)
  if not condition then
    error(message, 2)
  end
end

local function raises(call, ...)
  return not pcall(call, ...)
end

check(type(xinput) == "table", "the module is a table")
check(rawget(_G, "_LuaXInput") == nil, "it sets no global")
check(xinput.MAX_PADS == 4 and xinput.ANY == 255, "it carries XInput's constants")

local libraries = { ["xinput1_4.dll"] = true, ["xinput1_3.dll"] = true, ["xinput9_1_0.dll"] = true }
check(libraries[xinput.library()], "it found an XInput library, not " .. tostring(xinput.library()))

for index = 0, xinput.MAX_PADS - 1 do
  local state, reason, code = xinput.get_state(index)
  check(state == nil and reason == "not_connected" and code == 1167, "no pad in slot " .. index)
end

local _, vibration = xinput.set_vibration(0, 0, 0)
check(vibration == "not_connected", "nothing to vibrate, got " .. tostring(vibration))

local _, capabilities = xinput.get_capabilities(0)
check(capabilities == "not_connected", "no capabilities, got " .. tostring(capabilities))

-- xinput9_1_0.dll has neither call, so there both answer not_supported.
local oldest = xinput.library() == "xinput9_1_0.dll"

-- Windows may answer an empty slot's battery either way.
local battery, battery_reason = xinput.get_battery(0)
check(
  (battery and battery.type == "disconnected")
    or battery_reason == "not_connected"
    or (oldest and battery_reason == "not_supported"),
  "no battery, got " .. tostring(battery and battery.type or battery_reason)
)

-- And an empty queue on no pads either way too.
local _, keystroke = xinput.get_keystroke(xinput.ANY)
check(
  keystroke == "empty" or keystroke == "not_connected" or (oldest and keystroke == "not_supported"),
  "no keystroke, got " .. tostring(keystroke)
)

check(raises(xinput.get_state, 4), "slot 4 raises")
check(raises(xinput.get_state, 0, 5), "an out that is not a table raises")
check(raises(xinput.set_vibration, 0, 65536, 0), "a motor over 65535 raises")
check(raises(xinput.get_battery, 0, "keyboard"), "an unknown device raises")
check(raises(xinput.get_keystroke, 254), "an index that is neither a pad nor ANY raises")

print("smoke ok - " .. xinput.library())
