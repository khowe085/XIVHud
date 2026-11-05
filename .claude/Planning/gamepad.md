# Gamepad bridge (XInput through a native Lua module)

Takes the chord logic out of Steam Input. The addon reads an XInput pad itself
and does what the Steam profile's chords did: a face or D-pad press with a side
held goes to the bars as a **synthetic key event** through `core.on_keyboard`,
and a bare face press goes to the **game** as a real key through Windower's
`setkey`. The crossbar's input machine, its claim/conflict rules and the
hotbar's arbitration are untouched.

## Controller (Kevin, 2026-10-20)

Kevin plays on a Steam controller (`controller_triton`: two trackpads, four
back buttons), which XInput cannot see without Steam Input. So Steam Input
**stays, cut down**: a plain Xbox-pad passthrough (sticks, triggers, bumpers,
face, D-pad, Start, Back, stick clicks as XInput) plus single keys for what
XInput has no names for, with **no chords** - the back buttons (F1, F8, and the
upper pair's one-press WXHB `;`+`\` / `'`+`\`), the left trackpad's F9-F12 and
the right stick click. The bridge reads Steam's virtual pad.

The game's own pad bindings for the buttons are blanked (Kevin, 2026-10-19);
the sticks stay bound in game. Nothing here keeps a press from the game.

## The reader: a native module (Kevin, 2026-11-04)

The first reader called XInputGetState through LuaJIT's ffi. **Windower 4 has
no ffi** (the Windower devs, to Kevin, 2026-11-04), so it could never load.
Of the three routes the devs offered - the deprecated `windower/helper` (an
external libzmq API, last touched 2014), IPC from an external program (a
proof of concept in their Discord), or a DLL with a Lua interface - the DLL is
the one proven in an addon today: XIPivot appends
`<addon_path with / for \>libs/?.dll` to `package.cpath` and
`require('_XIPivot')`, its DLL exporting `luaopen__XIPivot` and linking
against Windower's `LuaCore.dll`, which exports the Lua 5.1 C API; XICamera
does the same with `_WindowerMemory`. It also runs inside the game process,
where Steam's virtual pad is likeliest to answer, and needs no second program.

### `_LuaXInput`: a generic module (Kevin, 2026-11-04)

Not XIVHud's: any addon can `require` it, and it may move to a repo of its
own, so it knows nothing of the bridge and holds no policy (no probe
throttle, no chords - those stay in `lib/gamepad`).

```lua
local xinput = require('_LuaXInput')        -- _LuaXInput.dll, luaopen__LuaXInput

xinput.VERSION                -- "1.0.0"
xinput.library()              -- "xinput1_4.dll" | "xinput1_3.dll" | "xinput9_1_0.dll" | nil
xinput.MAX_PADS               -- 4; a pad index is 0..3
xinput.ANY                    -- 255, XUSER_INDEX_ANY, for get_keystroke alone
xinput.buttons                -- { dpad_up = 0x0001, ... a = 0x1000, b, x, y }
xinput.TRIGGER_THRESHOLD, xinput.LEFT_THUMB_DEADZONE, xinput.RIGHT_THUMB_DEADZONE

xinput.get_state(index [, out])
  -> { packet, buttons, left_trigger, right_trigger,
       thumb_lx, thumb_ly, thumb_rx, thumb_ry }       -- `out` filled when given
xinput.set_vibration(index, left, right) -> true       -- motors 0..65535
xinput.get_capabilities(index [, out])
  -> { type, subtype, flags, buttons, left_trigger, right_trigger,
       thumb_lx, thumb_ly, thumb_rx, thumb_ry, left_motor, right_motor }
xinput.get_battery(index [, device])                    -- "gamepad" | "headset"
  -> { type, level }    -- "disconnected" | "wired" | "alkaline" | "nimh" | "unknown",
                        -- "empty" | "low" | "medium" | "full"
xinput.get_keystroke(index)                             -- index 0..3 or xinput.ANY
  -> { key, unicode, user_index, hid_code, down, up, repeating }
```

- Every call that cannot answer returns `nil, reason, code`: `"not_connected"`,
  `"empty"` (no keystroke waiting), `"not_supported"` (the XInput DLL found
  lacks the call - battery and keystrokes are not in `xinput9_1_0.dll`),
  `"no_xinput"`, or `"error"` with the Win32 code. A bad index or argument
  raises, as the Lua API's own checks do.
- At open it tries `xinput1_4.dll`, `xinput1_3.dll`, then `xinput9_1_0.dll`
  and resolves each call separately with `GetProcAddress`; the DLL is never
  freed, so nothing unloads under a read. It returns a table and sets no
  global.
- Plain C, 32-bit, linked against Windower's `LuaCore.dll` through an import
  library made from `luacore.def` - the one Windower-specific piece, so
  another host means another `.def`. Headers: Lua 5.1.5's own `lua.h`,
  `luaconf.h`, `lauxlib.h`, vendored with Lua's MIT notice (the API Windower's
  headers declare, as XIPivot's copy shows).
- `native/xinput/` holds all of it - `src/`, `include/`, `luacore.def`,
  `build.cmd` (finds MSVC through vswhere, so it builds the same on a PC and in
  CI, no third-party action), `tests/`, `README.md`, `LICENSE.txt` (the repo's
  BSD 3-clause) - so `git subtree split` can lift it out whole.
- **Tested here** (Kevin, 2026-11-04): the binding (`src/luaxinput.c`) and
  the loader (`src/loader_windows.c`) meet at `src/loader.h`, and
  `src/xinput_abi.h` writes XInput's structures out so the binding needs no
  Windows header. `make -C native/xinput test` builds the binding with gcc
  against `tests/fake_loader.c`, a scripted XInput whose control module the
  spec reaches through `package.loadlib`, and runs
  `tests/luaxinput_spec.lua` under busted - everything a pad can answer.
- **Tested on Windows CI**: a second build links the same source against a stock
  Lua 5.1.5 compiled from the pinned lua.org tarball, and `tests/smoke.lua`
  runs it with that `lua.exe` - the constants, argument checks, an XInput DLL
  found, and the `not_connected` answers of a runner with no pad. Reading a
  real pad stays a live-client test.
- CI (Kevin, 2026-11-04: CI builds it, no binary in the repo):
  `.github/workflows/xinput.yml` builds and smoke-tests on every pull request
  touching `native/xinput/`, and is called by `package.yml`, which drops the
  LuaCore build into the zip's `libs/`.

### XIVHud's side

- `lib/xinput.lua` - `new(module) -> reader | nil, reason`: nil without the
  module ("_LuaXInput not loaded") or without an XInput DLL; `read(index)`
  pcalls `module.get_state(index, reused)` and answers the state or nil. The
  module's field names are the ones `lib/gamepad` already reads. The ffi path
  goes - it can never run.
- `lib/gamepad.lua` - pure. `new(deps)` over `read(index)`, `now()`,
  `config()`, `inject(name, down)` (a real key to the game),
  `key_held(dik)` (core's view of the keyboard) and `unavailable` (why there
  is no reader). Answers `config_defaults()`, `poll()` (the bars' edges, in
  order; game keys go out through `inject` as a side effect), `release()`
  (the ups for everything held, game keys let go too), `available()`,
  `enabled()` and `status()`.
- core: optional `deps.gamepad`, its settings a machine-wide handle
  (`settings.register_global`, `core.gamepad_config()`). `core.pump_gamepad()`
  polls it and hands each edge to the same dispatch a real key takes; it runs
  logged out, as keyboard delivery does, but not out of focus
  (`core.on_focus`, seeded from `deps.has_focus`). `core.key_held` is the
  keyboard's keys alone. Verb `//hud gamepad [on|off]`, needing no
  character; the settings window's `global` panel gets a toggle row when the
  bridge has a reader.
- entry point: puts `<addon_path>libs/?.dll` (forward slashes) at the FRONT of
  `package.cpath`, traces `loading _LuaXInput` before the require (a native
  crash is not something pcall catches) and keeps the require's error in
  load.log,
  `pcall(require, "_LuaXInput")`, `xinput(module)`, `gamepad(...)` with
  `config` and `key_held` late-bound to core, `inject` as
  `setkey <name> down|up`; drives `core.pump_gamepad` every prerender under a
  guard of its own, forwards focus to `core.on_focus` and hands core
  `windower.has_focus`. Not in safe mode.

## Behaviour

- **Bare or chorded, decided at the press.** A press is CHORDED while any
  `activators` key is held - the two sides and the set switch, `; ' `` ` by
  default - whether the pad or the keyboard holds it, so a back button sending
  `;` counts. Chorded, a button sends its bar key. Bare, a button with a game
  key (`bare`) sends that to the game and nothing to the bars; one without
  sends its bar key, which the bars ignore unchorded. The choice holds until
  the button comes up.
- **Probe throttle.** `XInputGetState` on an empty slot is known to stall, so
  with no pad it probes ONE slot a second, round the four, starting from the
  slot a lost pad was in.
- **Disconnect or switch-off** releases every held key, bar and game alike.
- **Focus.** XInput reads the pad whichever window has focus, so the pump
  stops while the game is out of focus (a second client would otherwise act
  on the same presses); losing focus releases what the pad held and forgets
  the keyboard's keys, whose ups never arrive. The starting state is asked of
  the client (`windower.has_focus`) so an addon reloaded in the background
  starts out of focus. Unload releases too.
- **Its own guard.** The entry point drives `core.pump_gamepad` under a guard
  named `gamepad`: a component throwing on a pad key is reported there and
  never counts against the frame tick. Every edge is delivered regardless.
- **`core.key_held` is the keyboard's alone.** The pad's own keys are the
  bridge's to know; reading them back through core put them a frame late (a
  side released and a face button pressed on one frame read as chorded).
- **Reference counting**, per bar key and per game key: two buttons sharing
  one release it only when both are up (LB and RT+RB both send `\`).
- **Chord resolved at press.** RB sends backtick, or `\` with RT held, and the
  key it went down with is the key released.
- Ordering inside one poll: releases, then presses, each in the fixed button
  order (triggers first), so LT+RT on one frame is LR.
- Triggers press above `trigger_threshold` (30, XInput's own) and let go only
  at 10 under it, so a finger resting near it cannot flicker a cross.
- A button whose bar key is itself a side is never bare.
- A whole section set to `false` (`bare`, `chords`, `buttons`,
  `activators`) is off; a missing key in a section falls back to its default.
- `//hud gamepad` says `looking for a pad` until every slot has been asked,
  and only then `no pad connected`; switching off forgets the pad, so
  switching on starts the search over.
- Errors from a component on the release paths (focus loss, unload) are
  swallowed: those paths must finish. The same component's error surfaces on
  the pump or the keyboard handler, which report through their guards.

## Default map (matches Kevin's Steam profile)

| Button | Bar key | Game key, bare |
| --- | --- | --- |
| LT / RT | 39 `;` / 40 `'` | - |
| LB | 43 `\` | - |
| RB | 41 backtick; 43 while RT held | - |
| Back | 13 `=` | - |
| Y B A X | 2 3 4 5 (slots 1-4) | `numpad-` `escape` `enter` `numpad+` |
| D-pad up right down left | 6 7 8 9 (slots 5-8) | none (open) |
| Start, L3, R3 | none | - |

Config (`data/gamepad.lua`, one file for every character, read before any
login - Kevin, 2026-10-20; ships with `enabled = false`, and only an explicit
`true` turns it on): `enabled`, `trigger_threshold`,
`buttons = { <name> = <dik>|false }`, `chords = { rb = { rt = 43 } }`,
`bare = { <name> = <setkey name>|false }`, `activators = { <dik>, ... }`
(false removes an entry: the settings merge refills nil, never false).

## Unverified in a live client

Everything: that `_LuaXInput.dll` loads from the addon's `libs/` (XIPivot's
route), that one of the three XInput DLLs is found, that Steam's virtual pad
answers XInputGetState inside the game process, the probe and per-frame cost, the `setkey` spellings `enter`,
`escape`, `numpad+` and `numpad-` (a wrong spelling silently does nothing),
and whether a key held down through `setkey` repeats. `//hud gamepad` and
load.log say which step failed.

## Open

- What a bare D-pad press should send the game (nothing, for now).
- If the `gamepad` guard switches the pump off after five failures, a game key
  held through `setkey ... down` stays down until the next focus loss or
  unload. An error path only.
- Holding the same key from the pad and the keyboard at once (LT and a back
  button mapped to `;`): releasing either releases the side in the bars.
