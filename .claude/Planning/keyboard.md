# Keyboard map

Kevin, 2026-11-09: "implement the keyboard equivalent of gamepad.lua. The end
result should function exactly like it was before this change." He is going
back to a Steam Input layout that types the crossbar's keys while the D-pad
question is open, and wants the keyboard half of the behaviour model done
while he does.

Written while Kevin was away, so every call below marked **(open)** is the
smallest option, picked to be undone - not a settled convention. This file's
path was picked the same way, beside `gamepad.md`.

## What it is

`lib/keyboard` is to keys what `lib/gamepad` is to the pad: each key names a
BEHAVIOUR in a machine-wide map, `data/keyboard.lua`, and the key's edges go
through `lib/behaviors` exactly as a pad gesture's do. Nothing downstream of
a behaviour knows a key was pressed.

The shipped map is the crossbar's own keys, as `config.input` ships them, so
with the map on the crossbar answers its keys as it always did:

| Key | DIK | Behaviour | As `config.input` |
| --- | --- | --- | --- |
| `semicolon` | 39 | `crossbar.left` | `xhb_left` |
| `apostrophe` | 40 | `crossbar.right` | `xhb_right` |
| `backslash` | 43 | `crossbar.layer` (new) | `w_layer` |
| `grave` | 41 | `crossbar.switch` | `set_switch` |
| `1` .. `8` | 2 .. 9 | `crossbar.slot1` .. `crossbar.slot8` | `slot_keys` |
| `equals` | 13 | `crossbar.select` (new) | `shortcuts[13] = { chorded = "edit" }` |

## The parts

- **`lib/keyboard`** (new, pure) - `on_key(dik, down, blocked) -> taken`,
  `release()`, `enabled()`, `problems()`, `bindings()`, `config_defaults()`.
  A key's press is delivered once; its OS repeats change nothing and answer
  what the press answered; its release is delivered whatever else has
  changed since, and answers the same - the crossbar's latch rule ("whatever
  the game saw go down, it must see come up"), moved here.
- **The verdict comes from the behaviour.** `behaviors.edge` answers whether
  the press is taken: a component's `on_behavior` says (the crossbar keeps
  its five dedicated keys always and the number row only while it uses it -
  its own rules, unchanged), a game key or an action always is (a remapped
  key must not reach the game too), nothing that cannot work is. A
  behaviour already held by another key answers what its first press did.
- **Core** offers each key to the map after `learn` and the pad's named keys
  and before every component; a key the map takes reaches the components as
  `blocked`, the same accumulation that lets the crossbar's number row keep
  the hotbar quiet today. While the map is on, a component that declares
  `behaviors()` hears no raw presses - its keys come as behaviours, and both
  at once would hold every side twice and never cycle the set (the release
  of one would arrive blocked). It still hears the raw releases, which do
  nothing for a key it never saw go down. Today that is the crossbar alone.
- **The crossbar** declares `layer` and `select`, and `on_behavior` answers
  the verdict `on_key` would have given that key. One function decides both,
  so the two cannot drift.
- **`//hud keyboard [on|off]`** and **`//hud keyboard list`**: the switch,
  the map's problems, the map. A row on the settings window's `global` panel
  beside the gamepad's.

## Calls made while Kevin was away (open)

- **Ships off.** With it off nothing changes: the crossbar reads its own keys
  from `config.input` as before. `//hud keyboard on` hands them to the map.
  The gamepad bridge shipped off too; flipping the default is one line.
- **One key per behaviour edge, no chords yet.** A `+` in a key's name is
  reported and skipped. The pad's chord engine could be shared later; the
  crossbar's own chording (side + number, switch + number, layer + switch)
  stays in its input machine, where it is today.
- **No `bind`/`unbind` yet**: the map is a file edit until the verbs are
  built, `//hud gamepad bind`'s grammar being the model.
- **Key names** are DirectInput's, lowercased, with `numpad*`, `numpad+`,
  `numpad-`, `enter` and `escape` spelled as `setkey` spells them. A `;`
  cannot be typed in a Windower command (it separates commands), which is why
  `semicolon` is a word.
- **Custom crossbar shortcuts** (`config.input.shortcuts` beyond Select) have
  no behaviour, so the map cannot reach them; neither can a `config.input`
  edited away from the shipped keys. Nothing migrates, as ever.

## Deviations from the crossbar's own keys

- **A key another addon swallowed is ignored outright.** The crossbar used to
  track it - a `;` some other addon took still raised the side, though the
  key itself fired nothing - where the map never delivers a press that
  arrives blocked (a release is still delivered for a press it did).
- **A game key or an action on a key does nothing while the chat line is
  open**, and the key types. Component behaviours are delivered as ever and
  decide for themselves, as the crossbar does.
- **Switching the map off while a crossbar key is held** drops that side at
  once (the map lets go of what it holds). Switching it on mid-hold strands
  nothing: a behaviour-speaking component still gets the raw releases
  (review, round 2), so the side held raw lets go raw.

## Unverified in a live client

All of it - in particular that a release Windower delivers after the map was
switched off still reaches the map, and the key names beyond the ones the
crossbar already used.
