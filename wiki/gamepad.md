# Gamepad

## Description

XIVHud can read a gamepad itself: the **gamepad bridge**. Every frame it
reads an XInput pad - an Xbox controller, or anything that presents itself as
one - and turns each button you press, or each chord of buttons, into
something to do: a key for the game, an action fired as a crossbar or hotbar
slot would fire it, or one of the crossbar's own moves. The chords live in
XIVHud, so Steam Input, where you need it at all, only passes the pad through.

It is **on by default**, so set up the
[game's own gamepad settings](#the-games-gamepad-settings) before you play
with a pad. What each button does is changed with `//hud gamepad` commands,
without editing a file.

The bridge has not yet been run in a live client; see
[Not yet checked in a live client](#not-yet-checked-in-a-live-client).

## Features

- **The crossbar on the pad.** The triggers raise its sides, LT+LB and RT+RB
  its WXHB halves, and both triggers Expanded Hold. The face buttons and D-pad
  fire the slots under a trigger, RB cycles sets or jumps to one, LB+RB draws
  or sheathes, and a trigger with Start opens the binder.
- **The game's menu keys** on the face buttons and Start - A is Enter, B is
  Escape - with autorun, lock-on, targeting and the map beside them.
- **Any button or chord can carry an action**: a spell, an ability, an item, a
  chat line - anything a slot can hold, in the same words as a slot's `bind`.
- **One map for every character**, which works at the character screen too.

## What you need

- **An XInput pad.** An Xbox controller, or any pad Windows treats as one,
  works as it is. A PlayStation or Switch pad, or a Steam Controller, is not
  one on its own: run it through Steam Input set up as an Xbox pad (or another
  tool that presents it as one), with no chords - the bridge does those.
  The bridge reads the Xbox pad's buttons and no others, so a Steam
  Controller's back buttons and trackpads have to press one of those, or type
  a key for the [keyboard map](keyboard.md).
- **`bin/_LuaXInput.dll`**, which comes in the release zip, and the XInput
  Windows itself provides (`xinput1_4.dll`, `xinput1_3.dll` or
  `xinput9_1_0.dll`). `//hud gamepad` says if either is missing.
- **The game's own gamepad settings set up as below.** FFXI reads the pad
  itself, and nothing an addon does can keep a press from it, so a button the
  game still has bound does two things at once.

### The game's gamepad settings

Set these in FFXI's own gamepad configuration. All six are required:

1. **Menus on the D-pad.**
2. **Camera on the right stick.**
3. **Movement on the left stick.**
4. **The macro bars on the buttons that raise the crossbar** - LT and RT in
   the shipped map. With a trigger held, the D-pad then moves the game's
   macro bar instead of changing your target. It is not pretty, but it keeps
   the D-pad slots under a trigger from retargeting you.
5. **The WXHB halves on a chord with those buttons** - LT+LB and RT+RB in the
   shipped map. A WXHB on a button of its own would reach the game bare.
6. **Every other button unbound.** The bridge reads the stick clicks (L3,
   R3) but never where a stick points.

These follow from the game reading the pad itself: with the macro bars on LT
and RT, a D-pad press under a trigger moves the game's macro bar rather than
your target, which is why the crossbar can use the D-pad only under LT or RT.
The shipped set jumps under RB (RB + D-pad for sets 5 to 8) reach the game's
D-pad as well.

## Turning it on and off

It is on out of the box. Type `//hud gamepad` to see which pad it is
reading - `gamepad: on - pad 1 connected` - or why it is reading none (see
[Troubleshooting](#troubleshooting)), then anything wrong with the map.

`//hud gamepad off` switches it off and `//hud gamepad on` back on, as does
the `Gamepad` switch on the settings window's `global` panel
(`//hud config global`, with a character logged in). Either way the choice
holds for every character. Without a pad, switching it off also spares the
search for one, which asks one XInput slot a second.

## The shipped map

| Press | Does | Behaviour |
| --- | --- | --- |
| A | Enter | `accept` |
| B | Escape | `cancel` |
| X | numpad `+` | `cycle_window` |
| Y | `F1`, target yourself | `target_self` |
| Start | numpad `-` | `main_menu` |
| LB, tapped | `R`, as you let go | `autorun` |
| L3 | numpad `*` | `lockon` |
| R3 | `F8`, target an NPC | `target_npc` |
| Back | opens the map | `open_map` |
| LT / RT, held | raise the crossbar's left / right side; both at once is Expanded Hold | `crossbar.left` / `crossbar.right` |
| LT+LB / RT+RB, held | raise the WXHB's left / right half | `crossbar.wxhb_left` / `crossbar.wxhb_right` |
| RB | the set switch: tap it for the next set, or hold it and press a slot button to jump to that set | `crossbar.switch` |
| Y, B, A, X, D-pad ↑ → ↓ ←, with LT, RT or RB held | slots 1 to 8 of whichever bar is raised - or, under RB alone, sets 1 to 8 | `crossbar.slot1` - `crossbar.slot8` |
| LT+Start or RT+Start | open or close the binder (edit mode) | `crossbar.binder` |
| LB+RB, either order | draw or sheathe, as `//hud draw` does, while no crossbar side or WXHB half is up (see [Things to know](#things-to-know)) | `crossbar.draw` |
| The D-pad alone | nothing | |

A key is held down for as long as you hold the button, and comes up when you
let go - except on a button you also chord with, LB here, whose key is tapped
as you let go (see [Gestures](#gestures)). The crossbar's behaviours are
described on
[its page](components/crossbar.md#gamepad).

## Commands

None of these needs a character logged in: one map serves every character.

| Command | What it does |
| --- | --- |
| `//hud gamepad` | which pad is read, or why none is, then anything wrong with the map |
| `//hud gamepad on` / `off` | switch the bridge on or off |
| `//hud gamepad list` | every gesture and what it does, written the way `bind` takes it |
| `//hud gamepad bind <gesture> <behaviour>` | give a gesture a named behaviour: `bind a accept`, `bind lt crossbar.left` |
| `//hud gamepad bind <gesture> key <key>` | have it hold a key for as long as it is held: `bind lt+l3 key f9` |
| `//hud gamepad bind <gesture> <type> [<action>] [<target>]` | give it an action, in a slot's words: `bind lt+r3 ma "Cure IV" t` |
| `//hud gamepad unbind <gesture>` | take a gesture off the map, a shipped one included |

`bind` replaces whatever the gesture did before. Every change is saved at once
and takes effect at once. There is no command to put the shipped map back:
`bind` a gesture to its shipped behaviour again, from the table above.

### Gestures

A **gesture** is a button, or a chord: buttons joined by `+`, with the one you
press last at the end. `lt+y` is Y pressed while LT is held, and `b+a` is A
pressed while B is held. It is one word, with no spaces, in any case.

The buttons are `a` `b` `x` `y` `lb` `rb` `lt` `rt` `back` `start` `l3` `r3`
`up` `down` `left` `right`.

- **The last button is the one that counts.** `lt+lb` is LB pressed with LT
  already held. Press LB first and you get LB's own gesture, `autorun`, tapped
  when you let go; LT after it is LT alone.
- **The longest chord wins.** When a button goes down, of the gestures it ends
  whose other buttons are all held, the one naming the most buttons is used:
  with LT held, Y is `lt+y`, not `y`. On a tie, the gesture whose held button
  went down last wins.
- **A chord lasts while all of its buttons are held.** Let go of any one and it
  ends: release LT and the WXHB's left half drops even with LB still down, and
  LB does nothing until you press it again.
- **A button you chord with taps its own key or action.** When a chord holds a
  button before its last, that button's own key or action waits for its
  release, and goes only if you let go within a quarter of a second without
  pressing a chord with it. So a quick LB autoruns, and LB held for RB only
  draws. Only the button's own gesture waits: a chord ending in it, such as
  `rt+lb`, still goes at once. A crossbar behaviour on such a button still goes the moment the
  button goes down - LT holds the left side while `lt+y` fires slot 1 - since
  the crossbar settles its own taps, as the set switch does.

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
| `target_self` | holds `F1` |
| `target_npc` | holds `F8` |
| `open_map` | opens the map, as an `open map` slot does |

**A key.** `bind <gesture> key <key>` holds that key down for as long as the
gesture is held - or, on a button you also chord with, taps it as you let go
(see [Gestures](#gestures)); the shipped keys above work the same way. Keys
are named the way Windower's `setkey` names them:
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

## Things to know

- **Nothing is read while the game is out of focus**, since XInput reads the
  pad for every window - a second client included. Losing focus lets go of
  everything the pad was holding.
- **Unplugging the pad** lets go of everything too. XIVHud then looks for a
  pad again, asking one XInput slot a second.
- **Triggers** count as pressed past 30 (of 255) and let go only at 20 or
  below, so a finger resting on one cannot flicker a crossbar side. The 30 is
  `trigger_threshold`, below.
- **LB autoruns on a tap**, as you let go: within a quarter of a second, with
  no RB in between. Held longer, LB alone does nothing, so LB+RB only draws,
  in either order. The quarter second is `tap_seconds`, below.
- **LB+RB can turn up in the middle of a WXHB move.** Going from one WXHB half
  to the other, if the old trigger lets go and the new bumper goes down before
  the new trigger, with the old bumper still held, that is LB+RB with nothing
  up: it draws - or, with your weapon out, disengages, and on a mount
  dismounts. And a bumper pressed with its own trigger held is LB+RB rather
  than its WXHB half when the other bumper is held too and went down after
  that trigger.
- **The [keyboard map](keyboard.md) works alongside the pad.** A crossbar
  side held on the keyboard and the same side held on the pad are one side:
  it drops when both have let go.

## Settings

The map lives in one file shared by every character, beside their folders:

```
Windower4/addons/XIVHud/data/gamepad.lua
```

It belongs to no character, so it works at the character screen, and
`//hud copy` and `//hud reset` never touch it.

| Option | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | the bridge is on only when this is exactly `true` (`//hud gamepad on\|off`) |
| `map` | the shipped map | each gesture and what it does (`bind`, `unbind`); a shipped gesture you unbind is kept as `false`, or the next load would put it back |
| `trigger_threshold` | `30` | how far, 0 to 255, a trigger must be pulled to count as pressed; it lets go 10 below that. File only |
| `tap_seconds` | `0.25` | how long a button you also chord with can be held and still tap its own key or action as you let go. File only |

Every `//hud gamepad` command reads the file again first, so after a hand edit
type `//hud gamepad` and the edit applies. A command that changes the file
refuses one it cannot read, rather than write the shipped map over yours.
Deleting the file with the game closed puts the shipped map back, with the
bridge on.

An update that changes the shipped map does not change yours. The first
command that saved the file wrote every gesture into it, and the file wins: a
gesture the update moved keeps what it did before, and only gestures new to
the map are added, as is a setting new to the file, such as `tap_seconds`. `bind` a moved gesture to its new behaviour from
[the shipped map](#the-shipped-map), or delete the file with the game closed.

## Troubleshooting

`//hud gamepad` answers with one of these:

| It says | Meaning |
| --- | --- |
| `gamepad: off` | switched off: `//hud gamepad on` |
| `gamepad: on - pad <n> connected` | it is reading pad `<n>` |
| `gamepad: on - looking for a pad` | it is still asking the four XInput slots, one a second |
| `gamepad: on - no pad connected` | every slot was asked and none answered: the pad is unplugged, is not an XInput pad, or Steam Input is not presenting it as one |
| `... - paused - the game is not in focus` | another window has focus; nothing is read until the game has it back |
| `gamepad: unavailable - _LuaXInput not loaded` | `bin/_LuaXInput.dll` is missing or would not load: copy the release zip in again. `load.log` holds the error |
| `gamepad: unavailable - no XInput library found` | Windows has none of the three XInput DLLs |
| `the gamepad bridge did not load` | the bridge itself failed to load, or `safe_mode` is on; `load.log` holds the error |

Any lines after it each name a gesture and what is wrong with it - a button
the pad does not have, a behaviour that does not exist, one gesture written
twice. The rest of the map works. The same lines are said in chat once, when
the bridge first runs. Fix them with `bind` and `unbind`.

**A button does two things.** The game still has it bound: clear it in the
game's own gamepad settings.

## Not yet checked in a live client

So far the bridge has only run against the tests. In particular: that
`_LuaXInput.dll` loads from `bin/`; that Steam Input's virtual pad answers
inside the game; the key names behind the shipped behaviours (`enter`,
`escape`, `numpad+`, `numpad-`, `numpad*`, `r`, `f1`, `f8`), where a wrong one silently
does nothing; whether a key held by a gesture repeats; whether the game sees a
tapped key, which is down for one frame only (LB's autorun depends on it); and
that `open_map` opens the map. `//hud gamepad` and `load.log` say whether the
module loaded and whether a pad answers; most of the rest would fail without a
word.
