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

| Kind | Stored | Does |
| --- | --- | --- |
| game key | `{ key = "<setkey name>" }` | `setkey <name> down` while held, `setkey <name> up` when let go |
| action | the record a slot would store (`{ type = "ma", action = "Cure IV", target = "t" }`) | on the press, runs that action through the action service as a slot holding it would (`service.fire`), with no slot involved |
| component | declared by the component, named `<component>.<name>` | the component's `on_behavior(name, down)` |

A gesture names one of the SHIPPED behaviours, or a component's, or carries a
game key or an action of its own, bound with `//hud gamepad bind` (Commands,
below). The shipped ones are fixed:

```lua
accept       = { key = "enter" },
cancel       = { key = "escape" },
cycle_window = { key = "numpad+" },
main_menu    = { key = "numpad-" },
lockon       = { key = "numpad*" },
autorun      = { key = "r" },
open_map     = { type = "open", action = "map" },
```

- **`data/behaviors.lua` is gone** (Kevin, 2026-11-06): nothing else in the
  addon needs a hand edit, and a gesture carrying its own key or action is
  everything the file was for. A copy left on disk is never read (nothing
  migrates). A named-behaviour file can come back with the keyboard mapper if
  that needs one.
- **An action is anything a slot can hold** (Kevin), read by `bind`'s own
  parser (`lib/actionbar/commands`). It needs a character and the action
  service: without either, the press does nothing. Nor does it go where a
  slot's press would not - suppressed, in layout mode, the settings window or
  a binder open (review, round 2) - while a game key goes regardless.
- A game key two behaviours share is counted by the key: it comes up when
  both have let go. A gesture's own key or action is held by that gesture
  alone; a shipped or component behaviour two gestures name is counted
  across them.

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
name, a `{ key = }` or an action's record. Shipped (Kevin, 2026-11-05):

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
- A key is named with `//hud gamepad learn <name>` (below), never typed as a
  number.

## Commands (Kevin, 2026-11-06)

Nothing else in the addon needs a hand edit, so neither does the pad:

```
//hud gamepad                       status, then what is wrong with the map
//hud gamepad on|off
//hud gamepad list                  every gesture and what it does
//hud gamepad bind <gesture> <type> [<action>] [<target>]
//hud gamepad bind <gesture> <behavior>
//hud gamepad bind <gesture> key <key name>
//hud gamepad unbind <gesture>
//hud gamepad learn <name> [off]    the next key pressed is that button's
```

- **`bind` is a slot's `bind` with a gesture where the address goes** (Kevin):
  ONE word, buttons joined by `+`, the trigger last - `b+a` is A pressed with
  B held - in any case, with no spaces. A spaced one (`lt + y`) arrives as
  several words and is refused, naming the form. What follows is one of three
  (Kevin):
  - a shipped behaviour's name or a component's, alone: `bind a accept`,
    `bind lt crossbar.left`;
  - `key <name>`, a game key held for as long as the gesture is: `bind l3 key
    numpad*`;
  - anything a slot can hold, read by `bind`'s own record parser and validated
    as a slot's is: `bind lt+l4 ma "Cure IV" <t>`, `bind back open map`.
    `alias=`, `icon=` and `context=` need a slot and are refused.
  No behaviour name is a slot type, and a spec pins that, so the three cannot
  be mistaken for each other. A word that is none of them is refused, naming
  the behaviours.
- The binding replaces whatever the gesture held, under every spelling: one
  gesture is stored once, under the shipped spelling where there is one, so
  the settings merge cannot put a second copy back.
- A gesture naming a button nothing has learned is refused, pointing at
  `learn`.
- `unbind <gesture>` removes it. A shipped gesture is written `false`, which
  the settings merge would otherwise put back.
- `list` prints each gesture and what it does in the words `bind` takes, so a
  row retyped after `bind` binds the same thing - a `jc` record keeps no
  alias for it (review) - then the names given keys.
- **`learn <name>`** arms a capture: the next key pressed while the game has
  focus becomes that name's key in `extra`, both its edges swallowed, the
  file read again first (review: it waited on a keypress, and a write must
  not go over a hand edit or a broken file), saved and said - `l4 is key 88`.
  Escape cancels it; Enter (what sent the chat line) and the modifiers (Ctrl,
  Shift, Alt, Windows - the start of Alt-Tab, which learned would be kept
  from the game's macro chords; review) go through and it goes on waiting. A
  key another name already has MOVES to this one, and the reply says which
  name lost it (Kevin) - which is why core offers each key to `learn` before
  the bridge, which would otherwise take it as the old name (pinned by a
  spec, review). Any plain lowercase name that is not a pad button can be
  learned (Kevin), as `extra` allows. `learn <name> off` gives the key back
  to the game (Kevin). It works with the bridge off, so keys are set up before
  it goes on, and `core.wants_keyboard()` now counts the bridge, so the
  keyboard handler is registered for it - a review follow-up that `learn`
  makes load-bearing. A lost focus lets go of the keys it took, whose ups
  will not come (review).
- A refusal naming a button nothing knows lists the pad's buttons and the
  learned names.
- Every verb that edits re-reads `data/gamepad.lua` first and refuses one it
  could not read, as switching does.
- `trigger_threshold` stays a file edit, and there is no `reset` (Kevin).
- An action's name is not second-guessed against the resources as a slot's
  is (`ws Savage Blade Zeid`): the bar's lookup is its own, and the parse
  stays where `parse_action` had it. A follow-up.

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
- `//hud gamepad` re-reads the file first, so a hand edit applies at once;
  switching saves the whole of `data/gamepad.lua`, so it refuses to switch
  over a file it could not read rather than write the defaults over it
  (review, round 2).
- Errors from a component on the release paths (focus loss, unload) are
  swallowed: those paths must finish. The same component's error surfaces on
  the pump or the keyboard handler, which report through their guards.

## Code

As built on 2026-11-05, with `data/behaviors.lua`; what the commands changed
of it (the file gone, `check` for `known`, actions as records) follows the
list.

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

The commands (2026-11-06):

- `lib/behaviors` - no file: deps `validate` (a record -> true | nil, why)
  where `config` and `parse_action` were. `edge(value, ...)` takes a name or a
  gesture's own entry, each held by itself; `check(value) -> true | nil, why`
  replaces `problems`, while `known(name)` stays for `bind` to tell a
  behaviour's name from a type; `names()` lists the shipped and the
  components' for a refusal. `open_map` becomes a record.
- `lib/gamepad` - a map value may be a gesture's own entry; a `check` dep
  replaces `known`. Edits, each dropping the cached reading:
  `bind(text, value) -> spelling | nil, why`, `unbind(text)`, `bindings()`
  (in order, removals left out), `learnable(name)` and `set_key(name, dik |
  false) -> the name that lost it`.
- `lib/gamepad_commands` (new, pure) - the `//hud gamepad` grammar: the status
  and the switch (moved out of core), `bind`, `unbind`, `list`, `learn` and
  its capture (`on_key(dik, down) -> taken`), over the bridge, the behaviours,
  the action parser and labeller, `reload` / `save` / `say` and `focused`.
- `lib/actionbar/commands` - `parse_action(words)` over the words as the
  client hands them (the text splitter goes with the file) and
  `describe_action(record)`, the listing's label.
- core - builds `lib/gamepad_commands` and hands it `//hud gamepad`; offers
  each key to its `on_key` before the bridge's; drops the behaviours handle;
  `wants_keyboard()` counts the bridge; `behavior_check` replaces
  `behavior_known`.
- entry point - the bridge's `check`; the parser built over words, with
  `describe_action` beside it.
- CLAUDE.md - the commands block, the Gamepad bridge paragraph, Settings (one
  machine-wide file).

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
