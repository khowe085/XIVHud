# Keyboard map

## Description

The **keyboard map** is the keyboard's half of the [gamepad bridge](gamepad.md):
each key you name in it does something - a key for the game, an action fired
as a crossbar or hotbar slot would fire it, or one of the crossbar's own
moves - and the crossbar can no longer tell whether a key or a pad button
asked for it.

As it ships, the map holds the crossbar's own keys and nothing else, so
switching it on changes nothing you can see: `;` and `'` still raise the
crossbar's sides, `\` its WXHB, `` ` `` still switches sets, the number row
still fires slots, and `=` still opens the binder under a raised side and
leaves edit mode alone. It is
the same keys reaching the crossbar a new way.

It is **off until you switch it on**, with `//hud keyboard on` or the
`Keyboard map` switch on the settings window's `global` panel. While it is
off, the crossbar reads its own keys, as it always has.

None of it has been run in a live client yet.

## The shipped map

| Key | Name in the map | Does |
| --- | --- | --- |
| `;` | `semicolon` | `crossbar.left`: raises the left side while held |
| `'` | `apostrophe` | `crossbar.right`: raises the right side while held |
| `\` | `backslash` | `crossbar.layer`: with a side held, raises that side's WXHB half |
| `` ` `` | `grave` | `crossbar.switch`: the set switch |
| `1` to `8` | `1` to `8` | `crossbar.slot1` to `crossbar.slot8`: the raised bar's slots, or with the switch held a jump to that set |
| `=` | `equals` | `crossbar.select`: under a raised side, opens or closes the binder; alone it only leaves edit mode, and the key is still kept from the game |

These are the keys the crossbar's own `input` settings ship with. Every key
the crossbar kept from the game before, the map keeps from it now, and the
number row is still the game's whenever the crossbar is not using it.

## Commands

None of these needs a character logged in: one map serves every character.

| Command | What it does |
| --- | --- |
| `//hud keyboard` | says whether the map is on, then anything wrong with it |
| `//hud keyboard on` / `off` | switches the map on or off. Off lets go of every key it is holding |
| `//hud keyboard list` | every key the map binds and what it does |

## Settings

The map lives in one file shared by every character, beside their folders:

```
Windower4/addons/XIVHud/data/keyboard.lua
```

| Option | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | the map is on only when this is exactly `true` (`//hud keyboard on\|off`) |
| `map` | the crossbar's keys | each key and what it does; `false` leaves a key to the game |

There is no `bind` for the keyboard yet, so the map is changed in this file.
A key is written by its name in the map:

```lua
return {
  enabled = true,
  map = {
    semicolon = "crossbar.left",
    f9 = "crossbar.draw",
    f10 = { key = "numpad*" },
    f11 = { type = "open", action = "map" },
  },
}
```

- **A key does what a pad gesture does**: a [named behaviour](gamepad.md#what-a-gesture-can-do),
  `{ key = "<setkey name>" }` for a game key, or an action as a slot would
  hold it.
- **Key names** are `a` to `z`, `0` to `9`, `f1` to `f12`, `semicolon`,
  `apostrophe`, `grave`, `backslash`, `equals`, `minus`, `comma`, `period`,
  `slash`, `lbracket`, `rbracket`, `space`, `tab`, `enter`, `escape`,
  `backspace`, `up`, `down`, `left`, `right`, `home`, `end`, `pageup`,
  `pagedown`, `insert`, `delete`, `numpad0` to `numpad9`, `numpad+`,
  `numpad-`, `numpad*`, `numpad/` and `numpad.`, and the modifiers and
  locks by name (`lshift`, `rctrl`, `lalt`, `capslock` ...).
- **One key per entry.** The keyboard reads no chords yet: `semicolon+1` is
  reported and left out. The crossbar's own chords - a side and a number, the
  switch and a number, `\` and `` ` `` to draw - work as they always have,
  since the crossbar puts those together itself.
- `//hud keyboard` names anything it could not read - a key with no such
  name, a behaviour that does not exist, one key written twice - and the
  rest of the map works.

Every `//hud keyboard` command reads the file again first. Switching refuses
a file it cannot read, rather than write the shipped map over yours.

## Things to know

- **With the chat line open**, a key bound to a game key or an action types
  instead, as any key does. The crossbar's keys follow the crossbar's own
  rules there, as they always did.
- **A key another addon has already taken** never reaches the map. The
  crossbar used to raise its side on such a key while firing nothing; now it
  does nothing at all.
- **Losing focus** lets go of every key the map holds, as it does for the pad.
- **Switching the map off while you hold a crossbar key** drops that side at
  once; switching it on while you hold one leaves the side up until you let
  go, as before.
- **The crossbar's `input` settings** are not read while the map is on. A
  shortcut key you added there beyond Select has nothing in the map to stand
  for it yet.
