# Keyboard map

## Description

The **keyboard map** is how keys reach the crossbar and the hotbar: each key,
or each Ctrl/Alt/Shift chord over a key, names something to do - one of the
bars' moves, a key for the game, or an action fired as a slot would fire it.
It is the keyboard's half of the [gamepad bridge](gamepad.md), and the bars
cannot tell whether a key or a pad button asked.

It ships **on**, holding the keys the two bars have always used: `;` and `'`
raise the crossbar's sides, `\` its WXHB, `` ` `` switches sets, the number
row fires the raised side's slots, `=` opens the binder under a raised side,
and Ctrl, Alt and Shift over the number row fire the hotbar's rows - which now
win over a raised crossbar side (see [Things to know](#things-to-know)).

The bars read **no key of their own**. Switch the map off
(`//hud keyboard off`, or the `Keyboard map` switch on the settings window's
`global` panel) and no key reaches either bar: only the gamepad and the mouse
do.

None of it has been run in a live client yet.

## The shipped map

The crossbar:

| Key | Name in the map | Does |
| --- | --- | --- |
| `;` | `semicolon` | `crossbar.left`: raises the left side while held |
| `'` | `apostrophe` | `crossbar.right`: raises the right side while held |
| `\` | `backslash` | `crossbar.layer`: with a side held, raises that side's WXHB half |
| `` ` `` | `grave` | `crossbar.switch`: the set switch |
| `1` to `8` | `1` to `8` | `crossbar.slot1` to `crossbar.slot8`: the raised bar's slots, or with the switch held a jump to that set |
| `=` | `equals` | `crossbar.select`: under a raised side, opens or closes the binder; alone it only leaves edit mode, and the key is still kept from the game |

The hotbar, `1` to `0` being slots 1 to 10:

| Chord | Row |
| --- | --- |
| `ctrl+1` .. `ctrl+0` | `hotbar.bar1_slot1` .. `hotbar.bar1_slot10` |
| `alt+1` .. `alt+0` | row 2 |
| `shift+1` .. `shift+0` | row 3 |
| `ctrl+shift+1` .. | row 4 |
| `alt+shift+1` .. | row 5 |
| `ctrl+alt+shift+1` .. | row 6 |
| `ctrl+up` / `ctrl+down` | `hotbar.cycle` / `hotbar.cycle_back`: the next or previous set |

Rows 7 and 8 have behaviours (`hotbar.bar7_slot1` ...) but no keys shipped.
A key is kept from the game when its behaviour says so: the crossbar keeps its
five keys always and the number row only while a side or the switch is up, the
hotbar keeps a chord it fires, and neither keeps anything while the chat line
is open or the bar is hidden.

## Commands

None of these needs a character logged in: one map serves every character.

| Command | What it does |
| --- | --- |
| `//hud keyboard` | says whether the map is on, then anything wrong with it |
| `//hud keyboard on` / `off` | switches the map on or off. Off lets go of every key it is holding, and no key reaches the bars until it is on again |
| `//hud keyboard list` | every key the map binds and what it does |

## Settings

The map lives in one file shared by every character, beside their folders:

```
Windower4/addons/XIVHud/data/keyboard.lua
```

| Option | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | the map is on only when this is exactly `true` (`//hud keyboard on\|off`) |
| `map` | the bars' keys | each key or chord and what it does; `false` removes one: a key then goes to the game, and a chord does what its key alone does |

There is no `bind` for the keyboard yet, so the map is changed in this file.
An entry is written by its name in the map:

```lua
return {
  enabled = true,
  map = {
    semicolon = "crossbar.left",
    f9 = "crossbar.draw",
    ["ctrl+f10"] = { type = "ma", action = "Cure IV", target = "t" },
    f11 = { type = "open", action = "map" },
  },
}
```

- **An entry does what a pad gesture does**: a [named behaviour](gamepad.md#what-a-gesture-can-do),
  `{ key = "<setkey name>" }` for a game key, or an action as a slot would
  hold it.
- **Key names** are `a` to `z`, `0` to `9`, `f1` to `f12`, `semicolon`,
  `apostrophe`, `grave`, `backslash`, `equals`, `minus`, `comma`, `period`,
  `slash`, `lbracket`, `rbracket`, `space`, `tab`, `enter`, `escape`,
  `backspace`, `up`, `down`, `left`, `right`, `home`, `end`, `pageup`,
  `pagedown`, `insert`, `delete`, `numpad0` to `numpad9`, `numpad+`,
  `numpad-`, `numpad*`, `numpad/` and `numpad.`, and the modifiers and locks
  by name (`lshift`, `rctrl`, `lalt`, `capslock` ...).
- **A chord** is `ctrl`, `alt` and `shift`, in any order, over one key:
  `ctrl+shift+1`. Either side's modifier counts, and the modifiers must match
  exactly - `ctrl+1` is not Ctrl+Alt+1. A key pressed under modifiers no entry
  of it names does what the key alone does (Shift+`;` still raises the left
  side). Any other chord, such as `semicolon+1`, is reported and left out; the
  crossbar's own combinations - a side and a number, the switch and a number,
  `\` and `` ` `` to draw - need none, since it puts those together itself.
- `//hud keyboard` names anything it could not read - a key with no such
  name, a behaviour that does not exist, one key or chord written twice - and
  the rest of the map works.

Every `//hud keyboard` command reads the file again first. Switching refuses
a file it cannot read, rather than write the shipped map over yours.

## Things to know

- **Ctrl, Alt or Shift and a number is the hotbar's**, even with a crossbar
  side or the switch held: the chord is the more particular entry, and the
  crossbar does not see it. Under the switch, the switch then cycles as it
  comes up. On a hidden row - rows 2 to 8 ship hidden - the chord fires
  nothing and goes to the game.
- **With the chat line open**, a key bound to a game key or an action types
  instead, as any key does. The bars' own keys follow the bars' own rules
  there.
- **A key another addon has already taken** never reaches the map.
- **A key held as a modifier comes down under it** - Ctrl pressed while an
  arrow is already held - and the arrow's repeats stay what they were: a
  key fires only when it goes down.
- **Losing focus** lets go of every key the map holds, as it does for the pad.
- **Mouse clicks** on the bars' slots are not keys, and work with the map on
  or off.
- **The crossbar's `input` settings** in an older `config.lua` are no longer
  read. A shortcut key you had added there can be given the same action in
  the map.
