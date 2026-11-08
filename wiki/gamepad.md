# Gamepad

## Description

XIVHud can read a gamepad itself: the **gamepad bridge**. Every frame it
reads an XInput pad - an Xbox controller, or anything that presents itself as
one - and turns each button you press, or each chord of buttons, into
something to do: a key for the game, an action fired as a crossbar or hotbar
slot would fire it, or one of the crossbar's own moves. The chords live in
XIVHud, so Steam Input, where you need it at all, only passes the pad through.

It is **off until you switch it on**, and what each button does is changed
with `//hud gamepad` commands, without editing a file.

The bridge has not yet been run in a live client; see
[Not yet checked in a live client](#not-yet-checked-in-a-live-client).

## Features

- **The crossbar on the pad.** The triggers raise its sides, LT+LB and RT+RB
  its WXHB halves, and both triggers Expanded Hold. The face buttons and D-pad
  fire the slots under a trigger, RB cycles sets or jumps to one, and a
  trigger with Start opens the binder.
- **The game's menu keys** on the face buttons - A is Enter, B is Escape - with
  autorun, lock-on and the map beside them.
- **Any button or chord can carry an action**: a spell, an ability, an item, a
  chat line - anything a slot can hold, in the same words as a slot's `bind`.
- **Buttons XInput cannot see**, such as a Steam Controller's back buttons,
  work too, as keys Steam Input types that XIVHud learns with one command.
- **One map for every character**, which works at the character screen too.

## What you need

- **An XInput pad.** An Xbox controller, or any pad Windows treats as one,
  works as it is. A PlayStation or Switch pad, or a Steam Controller, is not
  one on its own: run it through Steam Input set up as an Xbox pad (or another
  tool that presents it as one), with no chords - the bridge does those.
- **`libs/_LuaXInput.dll`**, which comes in the release zip, and the XInput
  Windows itself provides (`xinput1_4.dll`, `xinput1_3.dll` or
  `xinput9_1_0.dll`). `//hud gamepad` says if either is missing.
- **The game's own pad buttons cleared.** FFXI reads the pad itself, and
  nothing an addon does can keep a press from it, so a button the game still
  has bound does two things at once. Clear the buttons in the game's own
  gamepad settings and leave the sticks bound: the bridge reads the stick
  clicks (L3, R3) but never where a stick points.

## Turning it on

1. Type `//hud gamepad on`, or, with a character logged in, click the
   `Gamepad` switch on the settings window's `global` panel
   (`//hud config global`).
2. Type `//hud gamepad`. It says which pad it is reading -
   `gamepad: on - pad 1 connected` - or why it is reading none (see
   [Troubleshooting](#troubleshooting)), then anything wrong with the map.

`//hud gamepad off` switches it off again. Either way the choice holds for
every character.

## The shipped map

| Press | Does | Behaviour |
| --- | --- | --- |
| A | Enter | `accept` |
| B | Escape | `cancel` |
| X | numpad `+` | `cycle_window` |
| Y | numpad `-` | `main_menu` |
| LB | `R` | `autorun` |
| L3 | numpad `*` | `lockon` |
| Back | opens the map | `open_map` |
| LT / RT, held | raise the crossbar's left / right side; both at once is Expanded Hold | `crossbar.left` / `crossbar.right` |
| LT+LB / RT+RB, held | raise the WXHB's left / right half | `crossbar.wxhb_left` / `crossbar.wxhb_right` |
| RB | the set switch: tap it for the next set, or hold it and press a slot button to jump to that set | `crossbar.switch` |
| Y, B, A, X, D-pad ↑ → ↓ ←, with LT, RT or RB held | slots 1 to 8 of whichever bar is raised - or, under RB alone, sets 1 to 8 | `crossbar.slot1` - `crossbar.slot8` |
| LT+Start or RT+Start | open or close the binder (edit mode) | `crossbar.binder` |
| Start, R3, the D-pad alone | nothing | |

A key is held down for as long as you hold the button, and comes up when you
let go. The crossbar's behaviours are described on
[its page](components/crossbar.md#gamepad).

## Commands

None of these needs a character logged in: one map serves every character.

| Command | What it does |
| --- | --- |
| `//hud gamepad` | which pad is read, or why none is, then anything wrong with the map |
| `//hud gamepad on` / `off` | switch the bridge on or off |
| `//hud gamepad list` | every gesture and what it does, written the way `bind` takes it, then the keys you have taught it |
| `//hud gamepad bind <gesture> <behaviour>` | give a gesture a named behaviour: `bind a accept`, `bind lt crossbar.left` |
| `//hud gamepad bind <gesture> key <key>` | have it hold a key for as long as it is held: `bind l3 key numpad*` |
| `//hud gamepad bind <gesture> <type> [<action>] [<target>]` | give it an action, in a slot's words: `bind r3 ma "Cure IV" t` |
| `//hud gamepad unbind <gesture>` | take a gesture off the map, a shipped one included |
| `//hud gamepad learn <name>` | the next key you press becomes the button `<name>` (see [Buttons XInput cannot see](#buttons-xinput-cannot-see)) |
| `//hud gamepad learn <name> off` | give that button's key back to the game |

`bind` replaces whatever the gesture did before. Every change is saved at once
and takes effect at once. There is no command to put the shipped map back:
`bind` a gesture to its shipped behaviour again, from the table above.

### Gestures

A **gesture** is a button, or a chord: buttons joined by `+`, with the one you
press last at the end. `lt+y` is Y pressed while LT is held, and `b+a` is A
pressed while B is held. It is one word, with no spaces, in any case.

The buttons are `a` `b` `x` `y` `lb` `rb` `lt` `rt` `back` `start` `l3` `r3`
`up` `down` `left` `right`, and any name you have taught a key with `learn`.

- **The last button is the one that counts.** `lt+lb` is LB pressed with LT
  already held. Press LB first and you get LB's own gesture, `autorun`; LT
  after it is LT alone.
- **The longest chord wins.** When a button goes down, of the gestures it ends
  whose other buttons are all held, the one naming the most buttons is used:
  with LT held, Y is `lt+y`, not `y`. On a tie, the gesture whose held button
  went down last wins.
- **A chord lasts while all of its buttons are held.** Let go of any one and it
  ends: release LT and the WXHB's left half drops even with LB still down, and
  LB does nothing until you press it again.
- **A button you chord with still does its own thing.** LT holds the
  crossbar's left side while `lt+y` fires slot 1. So a button you chord with
  should hold something (a side, the set switch) or nothing: give it an action
  and the action fires the moment the button goes down, before you press
  anything with it.

### What a gesture can do

**A named behaviour.** One of the shipped behaviours below, or one a component
declares, written `<component>.<name>` with the component's full name -
`crossbar.left`, never `cb.left`. Only the crossbar declares any so far; they
are on [its page](components/crossbar.md#gamepad).

| Behaviour | Does |
| --- | --- |
| `accept` | holds Enter |
| `cancel` | holds Escape |
| `cycle_window` | holds numpad `+` |
| `main_menu` | holds numpad `-` |
| `lockon` | holds numpad `*` |
| `autorun` | holds `R` |
| `open_map` | opens the map, as an `open map` slot does |

**A key.** `bind <gesture> key <key>` holds that key down for as long as the
gesture is held. Keys are named the way Windower's `setkey` names them:
`enter`, `escape`, `f9`, `numpad*`. A name Windower does not know does nothing,
without a word.

**An action.** Anything a crossbar or hotbar slot can hold, in the same words
as a slot's `bind` - see the crossbar's
[binding commands](components/crossbar.md#binding) and
[what you can bind](components/crossbar.md#what-you-can-bind). It fires once,
when the gesture is pressed, exactly as a slot holding it would: the
[action queue](Home.md#the-action-queue) holds it through a cast, and a mount
or a warp counts down first. `alias=`, `icon=` and `context=` belong to slots
and are refused. As on a slot, the action's name is not checked: a misspelt one
binds, and the game refuses it when pressed.

The three differ in when they go. A key always goes - at the character
screen, in a cutscene, with the chat line open - since that is where Enter and
Escape are wanted. An action needs a character, and does nothing while the HUD
is hidden, in layout mode, or with the settings window or the binder open. The
crossbar's behaviours follow the crossbar's own rules, exactly as its keys do:
nothing while the HUD or the crossbar is hidden, in layout mode or with the
chat line open, and in edit mode only the binder and the set switch.

### Buttons XInput cannot see

XInput knows a standard pad's buttons and nothing more, so a Steam
Controller's back buttons or trackpads never reach the bridge as buttons.
Instead:

1. In Steam Input, bind the button to a keyboard key nothing else uses.
2. Type `//hud gamepad learn l4` and press that button. XIVHud answers
   `gamepad: l4 is key <number>`.
3. `l4` is now a button like any other: `//hud gamepad bind l4
   crossbar.wxhb_left`, `//hud gamepad bind lt+l4 ma "Cure IV" t`.

While the bridge is on and the game has focus, a learned key belongs to the
bridge, from any keyboard: neither the game nor the HUD sees it.

- `learn` takes the next key pressed. Escape cancels it. Enter, Ctrl, Shift,
  Alt and the Windows keys are let through while it goes on waiting, so none
  of those can be learned.
- A key another name already had moves to the new one, and the reply says
  which name lost it.
- Any lowercase name of letters, digits and underscores that is not a pad
  button will do: `l4`, `r5`, `pad_up`.
- `learn` works with the bridge off, so the keys can be set up first.
- `//hud gamepad learn l4 off` gives the key back to the game.
- A button that raises a crossbar bar on its own needs slot chords of its own:
  `l4+y`, `l4+b` and so on to `l4+left`, bound to `crossbar.slot1` to
  `crossbar.slot8`. The shipped slot chords are under LT, RT and RB only.

## Things to know

- **Nothing is read while the game is out of focus**, since XInput reads the
  pad for every window - a second client included. Losing focus lets go of
  everything the pad was holding.
- **Unplugging the pad** lets go of everything too. XIVHud then looks for a
  pad again, asking one XInput slot a second.
- **Triggers** count as pressed past 30 (of 255) and let go only at 20 or
  below, so a finger resting on one cannot flicker a crossbar side. The 30 is
  `trigger_threshold`, below.
- **Draw and sheathe** have no gesture in the shipped map, LB being autorun.
  `draw` is an action like any other, so `//hud gamepad bind r3 draw` gives
  it one; `//hud draw` and a click on the crossbar's sword still work.
- **The keyboard still works** alongside the pad. A crossbar side held on the
  keyboard and the same side held on the pad are one side: it drops when both
  have let go.

## Settings

The map lives in one file shared by every character, beside their folders:

```
Windower4/addons/XIVHud/data/gamepad.lua
```

It belongs to no character, so it works at the character screen, and
`//hud copy` and `//hud reset` never touch it.

| Option | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | the bridge is on only when this is exactly `true` (`//hud gamepad on\|off`) |
| `map` | the shipped map | each gesture and what it does (`bind`, `unbind`); a shipped gesture you unbind is kept as `false`, or the next load would put it back |
| `extra` | `l4`, `l5`, `r4`, `r5`, all `false` | the key each learned button arrives as, a DirectInput scan code (`learn`) |
| `trigger_threshold` | `30` | how far, 0 to 255, a trigger must be pulled to count as pressed; it lets go 10 below that. File only |

Every `//hud gamepad` command reads the file again first, so after a hand edit
type `//hud gamepad` and the edit applies. A command that changes the file
refuses one it cannot read, rather than write the shipped map over yours.
Deleting the file with the game closed puts the shipped map back, with no
learned keys and the bridge off.

## Troubleshooting

`//hud gamepad` answers with one of these:

| It says | Meaning |
| --- | --- |
| `gamepad: off` | switched off: `//hud gamepad on` |
| `gamepad: on - pad <n> connected` | it is reading pad `<n>` |
| `gamepad: on - looking for a pad` | it is still asking the four XInput slots, one a second |
| `gamepad: on - no pad connected` | every slot was asked and none answered: the pad is unplugged, is not an XInput pad, or Steam Input is not presenting it as one |
| `... - paused - the game is not in focus` | another window has focus; nothing is read until the game has it back |
| `gamepad: unavailable - _LuaXInput not loaded` | `libs/_LuaXInput.dll` is missing or would not load: copy the release zip in again. `load.log` holds the error |
| `gamepad: unavailable - no XInput library found` | Windows has none of the three XInput DLLs |
| `the gamepad bridge did not load` | the bridge itself failed to load, or `safe_mode` is on; `load.log` holds the error |

Any lines after it each name a gesture or a learned button and what is wrong
with it - a button nothing has learned, a behaviour that does not exist, one
gesture written twice. The rest of the map works. The same lines are said in
chat once, when the bridge first runs. Fix them with `bind` and `unbind`, or
with `learn` where a button has no key.

**A button does two things.** The game still has it bound: clear it in the
game's own gamepad settings.

**A key stopped working on the keyboard.** You taught it to the bridge, which
takes it from every keyboard while it is on. `//hud gamepad list` names the
learned keys, and `//hud gamepad learn <name> off` gives one back.

## Not yet checked in a live client

So far the bridge has only run against the tests. In particular: that
`_LuaXInput.dll` loads from `libs/`; that Steam Input's virtual pad answers
inside the game; the key names behind the shipped behaviours (`enter`,
`escape`, `numpad+`, `numpad-`, `numpad*`, `r`), where a wrong one silently
does nothing; whether a key held by a gesture repeats; that `open_map` opens
the map; that keys Steam Input types reach XIVHud and can be kept from the
game; and whether a learned key arrives as the same number on every keyboard
layout. `//hud gamepad` and `load.log` say whether the module loaded and
whether a pad answers; most of the rest would fail without a word.
