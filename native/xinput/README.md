# _LuaXInput

XInput for Lua 5.1: Xbox-protocol pads - and anything Steam Input presents as
one - read from a Windower 4 addon, which has no ffi to call XInput with. A
32-bit DLL with a Lua interface, loaded the way XIPivot loads `_XIPivot`.

## Loading it

Put `_LuaXInput.dll` in the addon's `libs/` and put that folder at the front
of `package.cpath`, so another addon's copy earlier on the path cannot stand
in for yours. XIPivot writes the path with forward slashes, saying
`package.cpath` does not take backslashes - untested here, but the safe way:

```lua
local path = windower.addon_path:gsub("\\", "/")
package.cpath = path .. "libs/?.dll;" .. package.cpath
local xinput = require("_LuaXInput")
```

It returns a table and sets no global.

## Reference

```lua
xinput.VERSION                      -- "1.0.0"
xinput.library()                    -- the XInput DLL in use, or nil for none
xinput.MAX_PADS                     -- 4: a pad index is 0 to 3
xinput.ANY                          -- 255: any pad, for get_keystroke alone
xinput.buttons                      -- { dpad_up = 0x0001, dpad_down, dpad_left, dpad_right,
                                    --   start, back, left_thumb, right_thumb,
                                    --   left_shoulder, right_shoulder, a, b, x, y }
xinput.TRIGGER_THRESHOLD            -- 30
xinput.LEFT_THUMB_DEADZONE          -- 7849
xinput.RIGHT_THUMB_DEADZONE         -- 8689

xinput.get_state(index [, out])
-- { packet, buttons, left_trigger, right_trigger, thumb_lx, thumb_ly, thumb_rx, thumb_ry }
-- `buttons` is a bitmask of xinput.buttons; triggers are 0 to 255, sticks
-- -32768 to 32767. Given `out`, it fills that table and returns it, so a
-- caller reading every frame allocates nothing.

xinput.set_vibration(index, left, right)    -- true; each motor 0 to 65535

xinput.get_capabilities(index [, out])
-- { type, subtype, flags, buttons, left_trigger, right_trigger,
--   thumb_lx, thumb_ly, thumb_rx, thumb_ry, left_motor, right_motor }
-- XInput's own numbers, for a device of any type; the gamepad fields say
-- which controls the device has and their resolution.

xinput.get_battery(index [, device])        -- device "gamepad" (default) or "headset"
-- { type = "disconnected" | "wired" | "alkaline" | "nimh" | "unknown",
--   level = "empty" | "low" | "medium" | "full" | "unknown" }

xinput.get_keystroke(index)                 -- a pad, or xinput.ANY
-- { key, unicode, user_index, hid_code, down, up, repeating }
-- XInput's queue of presses, repeats and releases: one per call.
```

A call that cannot answer returns `nil, reason`, plus the Windows error code
where there is one:

| reason | when |
| --- | --- |
| `not_connected` | no pad in that slot (1167) |
| `empty` | `get_keystroke` with nothing waiting (4306) |
| `error` | any other failure, with its code |
| `not_supported` | the XInput DLL in use lacks the call |
| `no_xinput` | no XInput DLL was found |

A bad argument - an index outside 0 to 3, a motor speed outside 0 to 65535,
an unknown device, an `out` that is not a table - raises, as the Lua API's
own argument checks do.

## Notes

- It tries `xinput1_4.dll`, `xinput1_3.dll` and `xinput9_1_0.dll`, from the
  system directory only, and keeps the first with `XInputGetState` loaded for
  the life of the process. `xinput9_1_0.dll` has no battery or keystroke
  calls: those answer `not_supported` there.
- Asking an empty slot is slow on some systems. A caller polling every frame
  should not look for a pad in every slot every frame.
- It holds no state of its own beyond the DLL it found: no throttling, no
  edge detection, no mapping. Those are the caller's.

## Building and testing

`build.cmd` (Visual Studio's C++ tools, found through vswhere) builds
`build\windower\_LuaXInput.dll`: 32-bit, static CRT, linked against
Windower's `LuaCore.dll` through an import library made from `luacore.def`.
`luacore.def` is the only Windower-specific piece: another Lua 5.1 host needs
another `.def` naming its DLL.

- `make -C native/xinput test` (Linux, gcc, busted) builds the binding against
  the scripted XInput in `tests/fake_loader.c` and runs
  `tests/luaxinput_spec.lua`: everything a pad can answer.
- `build.cmd test <lua-5.1.5\src>` (Windows) also builds a copy against a stock
  Lua 5.1.5 and runs `tests/smoke.lua` with it: the real loader, on a machine
  with no pad.

`src/xinput_abi.h` writes out XInput's structures so the binding needs no
Windows header; `src/loader.h` is the seam between the binding
(`src/luaxinput.c`) and XInput (`src/loader_windows.c`, or the fake).

## Licence

BSD 3-clause, in `LICENSE.txt`. The Lua headers in `include/` are Lua's, under
the MIT licence in `include/LUA-COPYRIGHT.txt`.
