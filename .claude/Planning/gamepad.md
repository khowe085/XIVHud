# Gamepad bridge (XInput through a native Lua module)

Takes the chord logic out of Steam Input. The addon reads an XInput pad itself
and maps each **gesture** - a button, or a chord of buttons - to a named
**behaviour**: a key sent to the game, an action run as a bar slot would run
it, or something a component does (raise a side of the crossbar, fire a
slot). Nothing downstream of a behaviour knows which device, button or chord
triggered it (Kevin, 2026-11-05). This first pass maps the gamepad alone; the
keyboard keeps working as it does now, and a keyboard-to-behaviour mapper is a
later pass that reuses the same behaviours.

## Controller (Kevin, 2026-10-20)

Kevin plays on a Steam controller (`controller_triton`: two trackpads, four
back buttons), which XInput cannot see without Steam Input. So Steam Input
**stays, cut down**: a plain Xbox-pad passthrough (sticks, triggers, bumpers,
face, D-pad, Start, Back, stick clicks as XInput) plus single keys for what
XInput has no names for, with **no chords** - the back buttons, the left
trackpad's F9-F12 and the right stick click. The bridge reads Steam's virtual
pad, and takes the back buttons as the keys Steam types for them (`extra`,
below).

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

## Behaviours (Kevin, 2026-11-05)

Three kinds:

| Kind | Defined | Does |
| --- | --- | --- |
| game key | `data/behaviors.lua`: `{ key = "<setkey name>" }` | `setkey <name> down` while held, `setkey <name> up` when let go |
| action | `data/behaviors.lua`: `{ action = "<bind grammar>" }` | on the press, runs that action through the action service as a slot holding it would (`service.fire`), with no slot involved |
| component | declared by the component, named `<component>.<name>` | the component's `on_behavior(name, down)` |

**`data/behaviors.lua`** - machine-wide, beside `data/gamepad.lua` (Kevin),
read before any login so a game key works at the character screen. Shipped:

```lua
accept       = { key = "enter" },
cancel       = { key = "escape" },
cycle_window = { key = "numpad+" },
main_menu    = { key = "numpad-" },
lockon       = { key = "numpad*" },
autorun      = { key = "r" },
open_map     = { action = "open map" },
```

- A name is a plain word (`^[%l%d_]+$`), so it can never be mistaken for a
  component's (`crossbar.left`). `false` removes a shipped one.
- The file is seeded with nothing and never merged with the shipped
  behaviours: a name it leaves out IS the shipped behaviour, and one it names
  is its own entry, whole, so `open_map = { key = "m" }` makes Back a key with
  no shipped `action` mixed in (found by review, round 1).
- **An action is anything a slot can hold** (Kevin): written as `bind` takes
  it after the address - `open map`, `ma "Cure IV" <t>`, `ct /echo hi` - and
  parsed by the same code (`bind`'s record parse, pulled out of
  `lib/actionbar/commands` into a function both call, its behaviour and specs
  untouched). It is parsed when the file is read; one that does not parse is
  reported and does nothing. `alias=`, `icon=` and `context=` mean nothing
  without a slot and are refused. It needs a character and the action service:
  without either, the press does nothing. Nor does it go where a slot's press
  would not - suppressed, in layout mode, the settings window or a binder open
  (review, round 2) - while a game key goes regardless.
- A game key two behaviours share is counted by the key: it comes up when
  both have let go.

**The crossbar's behaviours** (built in, declared by the widget):

| Behaviour | Kind | Does |
| --- | --- | --- |
| `crossbar.left`, `crossbar.right` | hold | raise that side, as `;` / `'` do; both held is Expanded, in the order they went down |
| `crossbar.wxhb_left`, `crossbar.wxhb_right` | hold | raise that WXHB half, as `\` with a side does |
| `crossbar.switch` | hold | the set switch, as backtick: a tap cycles the set; held, a slot press jumps to that set |
| `crossbar.slot1` .. `crossbar.slot8` | press | slot N of whatever bar is raised (Kevin) - or, with the switch held, a jump to set N |
| `crossbar.binder` | press | open or close the binder (edit mode), as Select chorded with a side |

- One state machine serves keys and behaviours: `input.lua` gains
  `on_behavior` beside `on_key`, sharing the hold state, so a side held on
  the keyboard and one held through a behaviour combine as two keys of one
  role do, and letting go of one leaves the other held.
- With a WXHB behaviour held its half is up, whatever else is held; with both,
  the newer wins.
- They pass the crossbar's own guards exactly as its keys do - suppressed,
  user-hidden, layout mode, edit mode's two live inputs (the binder toggle and
  the switch), and the chat line open. Nothing is blocked: a behaviour is not
  a Windower key event.
- A let-go is `cancelled` when it ends a hold without being a release - focus
  lost, the pad gone, the bridge switched off - and the switch's tap does not
  cycle on one.

## The gamepad map

`data/gamepad.lua`: `enabled` (ships `false`; only an explicit `true` turns it
on), `trigger_threshold`, `extra` (below) and `map`, a gesture to a behaviour
name. Shipped (Kevin, 2026-11-05):

| Gesture | Behaviour |
| --- | --- |
| A / B / X / Y | `accept` / `cancel` / `cycle_window` / `main_menu` |
| LB | `autorun` |
| RB | `crossbar.switch` |
| LT / RT | `crossbar.left` / `crossbar.right` |
| LT+LB / RT+RB | `crossbar.wxhb_left` / `crossbar.wxhb_right` |
| LT+Start, RT+Start | `crossbar.binder` |
| Back | `open_map` |
| L3 | `lockon` |
| LT, RT or RB, + Y B A X up right down left | `crossbar.slot1` .. `crossbar.slot8` |
| Start, R3, the D-pad alone | nothing |

```lua
map = {
  a = "accept", b = "cancel", x = "cycle_window", y = "main_menu",
  lb = "autorun", rb = "crossbar.switch",
  lt = "crossbar.left", rt = "crossbar.right",
  ["lt+lb"] = "crossbar.wxhb_left", ["rt+rb"] = "crossbar.wxhb_right",
  ["lt+start"] = "crossbar.binder", ["rt+start"] = "crossbar.binder",
  back = "open_map", l3 = "lockon",
  ["lt+y"] = "crossbar.slot1", ["lt+b"] = "crossbar.slot2", -- ... lt+left = slot8
  ["rt+y"] = "crossbar.slot1", -- ... the same eight under RT
  ["rb+y"] = "crossbar.slot1", -- ... and under RB, the set jump
},
```

- **A gesture** is buttons joined by `+`: the last is the trigger, the rest
  held before it, so `lt+y` is Y pressed with LT held. Buttons: `a b x y lb
  rb lt rt back start l3 r3 up down left right`, and the `extra` names.
- **Resolved at the press**, against what is held at that moment: of the
  gestures the button triggers whose other buttons are all held, the one
  naming the most buttons wins (`lt+y` over `y`); on a tie, the one whose
  newest button went down last.
- **A chord lasts while all its buttons are held** (Kevin, 2026-11-06): the
  first of them up lets its behaviour go, so letting go of LT lowers WXHB
  left with LB still down - where it used to stay up while Y read bare. The
  trigger of a broken chord holds nothing until it comes up and goes down
  again, so LB does not turn into `autorun` on the way.
- **Slots of the raised bar** (Kevin): `lt+y` also covers WXHB left (LT+LB
  held) and Expanded (LT+RT), and `rb+y` is the set jump through the same
  behaviour. A gesture that raises the crossbar on its own (L4 alone, say)
  needs its own eight slot gestures (`l4+y` ...).
- **A modifier's own behaviour stays held**: LT holds `crossbar.left` while
  `lt+y` fires slot 1. So a button used as a modifier wants a hold behaviour
  or none - a press behaviour on one (LB = `autorun` with `lb+y` bound) fires
  the moment it goes down.
- **Reference counted per behaviour**: LT+Start and RT+Start both hold
  `crossbar.binder`, and a game key comes up only when every gesture holding
  it has let go.
- `false` removes a shipped gesture. A gesture naming no button, or a
  behaviour that does not exist, is said once in chat when the map is read and
  listed by `//hud gamepad`; the rest of the map works.
- One gesture spelled twice - another case, spaces, its modifiers in another
  order, a `false` among them - is reported, and the first in order kept,
  which is the user's: the merge puts back the shipped spelling, lowercase and
  unspaced, and any other spelling sorts ahead of it.

### Buttons XInput cannot see (Kevin, 2026-11-05)

The back buttons (L4, L5, R4, R5) have no XInput name, so Steam Input types a
key for each and `extra` names them: `extra = { l4 = <DIK>, l5 = , r4 = ,
r5 = }`, shipped `false` (none). A named key is then a pad button like any
other - `l4` alone, `lt+l4` and `l4+y` are all gestures - so whether WXHB left
is LT+LB, L4 or LT+L4 is the user's map. Any name works (a trackpad region
too), but it may not shadow an XInput button.

- While the bridge is on, a named key is the bridge's: core offers every key
  to it before any component, and both edges of a named one are swallowed, so
  neither the bars nor the game see it - from any keyboard. Not while the
  game is out of focus, where nothing would poll what it took.
- A key edge is taken at the next poll, the keys in the order they came,
  after the pad's releases and its triggers' presses and before its other
  presses, so LT and L4 on one frame read as LT+L4. A tap between two polls is
  held for one, or a game key's down and up would leave in one frame, which
  the client never samples. A repeat of a held key is ignored.
- A named key is taken only while the polls are running: one taken after the
  pump's guard switched it off would wait for a poll that never comes.
- Pick keys nothing else uses. Steam's current `;`+`\` / `'`+`\` back buttons
  would raise the crossbar through its own keys and never reach the map.

## Behaviour of the bridge

- **Probe throttle.** `XInputGetState` on an empty slot is known to stall, so
  with no pad it probes ONE slot a second, round the four, starting from the
  slot a lost pad was in.
- **Disconnect or switch-off** lets go of every held behaviour.
- **Focus.** XInput reads the pad whichever window has focus, so the pump
  stops while the game is out of focus (a second client would otherwise act
  on the same presses); losing focus lets go of everything held, the `extra`
  keys included, whose ups never arrive. The starting state is asked of the
  client (`windower.has_focus`) so an addon reloaded in the background starts
  out of focus. Unload lets go too.
- **Its own guard.** The entry point drives `core.pump_gamepad` under a guard
  named `gamepad`: a component throwing on a behaviour is reported there and
  never counts against the frame tick. Every edge is delivered regardless.
- Triggers press above `trigger_threshold` (30, XInput's own) and let go only
  at 10 under it, so a finger resting near it cannot flicker a cross.
- Logged out, game keys still go (the character screen); component and action
  behaviours have nothing attached to reach and do nothing.
- `//hud gamepad` says `looking for a pad` until every slot has been asked,
  and only then `no pad connected`; switching off forgets the pad, so
  switching on starts the search over. It lists the map's problems after.
- `//hud gamepad` re-reads both files first, so a hand edit applies at once;
  switching saves the whole of `data/gamepad.lua`, so it refuses to switch
  over a file it could not read rather than write the defaults over it
  (review, round 2).
- Errors from a component on the release paths (focus loss, unload) are
  swallowed: those paths must finish. The same component's error surfaces on
  the pump or the keyboard handler, which report through their guards.

## Code

- `lib/xinput.lua` - unchanged: `new(module) -> reader | nil, reason`.
- `lib/behaviors.lua` (new, pure) - `new(deps)` over `config()`
  (`data/behaviors.lua`), `send_key(key, down)`, `parse_action(text) -> record
  | nil, complaint`, `fire_action(record)`, `components()` (every registered
  component's behaviour, qualified) and `deliver(name, down, cancelled)`.
  Answers `edge(name, down, cancelled)` (reference counted, let go as it went
  down), `known(name)` and `problems()`, the shipped behaviours its own.
- `lib/gamepad.lua` - the reader half stays (probe, triggers, focus, status);
  the DIK half becomes the gesture resolver. `poll()` answers this frame's
  behaviour edges, `{ behavior, down, cancelled }`, in order - `cancelled` on
  the ups of a lost pad or a switch-off; `on_key(dik, down) -> taken` takes
  the `extra` keys; `release()` answers the ups, cancelled, for everything
  held; `problems()` names the map's dead entries, asking `known(name)`. Its
  deps lose `inject` and `key_held`.
- core - builds `lib/behaviors` where there is a bridge; `pump_gamepad` hands
  each edge to it; the keyboard handler offers each key to `gamepad.on_key`
  before any component and blocks one it takes; `core.key_held` and the
  synthetic keys go; `core.behavior_known(name)` answers the bridge. Two
  opt-in widget members, detected by the member as `on_keyboard` is:
  `behaviors() -> { <name>, ... }` and `on_behavior(name, down, cancelled)`.
  The behaviours file is a second machine-wide handle
  (`settings.register_global`). New deps: `send_key` and
  `parse_behavior_action` (the entry point's `parse_action` is the action
  packet's).
- crossbar - `behaviors()` and `on_behavior`, through `input.on_behavior`, its
  intents applied by the code `on_keyboard` already uses. The input machine's
  key path and behaviour path share one step; a cancelled let-go of the switch
  does not cycle.
- `lib/actionbar/commands` - `bind`'s record parse pulled into a function,
  and `parse_action(text)` over it: the words split as a client splits them,
  labels refused, the record validated by the action service's `validate`.
- entry point - hands core `send_key` (`setkey <name> down|up`) and
  `parse_behavior_action` (an actionbar commands instance over the service's
  `validate`), and the bridge `known` from core; the rest of the bridge's
  wiring as now (the module on `package.cpath`, the trace, the guard, focus).
- CLAUDE.md - the widget contract's two members, the Gamepad bridge
  paragraph, `data/behaviors.lua` under Settings.
- Tests, test first: `tests/behaviors_spec.lua` (new); `tests/gamepad_spec.lua`
  rewritten (written on this branch); core, entry point and the crossbar's
  specs gain cases - none written before this branch changes.
- Gone: `buttons`, `chords`, `bare`, `activators` and the bars' DIKs from the
  pad. A `data/gamepad.lua` still holding them carries dead weight (nothing
  migrates; the bridge ships off and has not run in a client).

## Unverified in a live client

Everything: that `_LuaXInput.dll` loads from the addon's `libs/` (XIPivot's
route), that one of the three XInput DLLs is found, that Steam's virtual pad
answers XInputGetState inside the game process, the probe and per-frame cost,
the `setkey` spellings `enter`, `escape`, `numpad+`, `numpad-`, `numpad*` and
`r` (a wrong spelling silently does nothing), whether a key held down through
`setkey` repeats, that keys Steam types reach Windower's keyboard event and can
be swallowed like typed ones, and that `/map` opens the map (the opener's own
open row). `//hud gamepad` and load.log say which step failed.

## Open

- The chat line open stops crossbar behaviours, as it stops the crossbar's
  keys. The pad does not type, so lifting that for behaviours is Kevin's call.
- Draw/sheathe has no pad gesture now that LB is `autorun`; `//hud draw` and
  the sword click remain, and a `crossbar.draw` behaviour is small if wanted.
- If the `gamepad` guard switches the pump off after five failures, a game key
  held through `setkey ... down` stays down until the next focus loss or
  unload. An error path only.
