# Keyboard map

Kevin, 2026-11-09: "implement the keyboard equivalent of gamepad.lua. The end
result should function exactly like it was before this change." He is going
back to a Steam Input layout that types the crossbar's keys while the D-pad
question is open, and wants the keyboard half of the behaviour model done
while he does.

Written while Kevin was away, so every call below marked **(open)** is the
smallest option, picked to be undone - not a settled convention. This file's
path was picked the same way, beside `gamepad.md`.

## Kevin's calls after testing (2026-11-09)

- **The old key path goes.** With the keyboard map and the gamepad both off,
  no key reaches the crossbar or the hotbar ("nothing should trigger
  crossbar / actions"). Mouse clicks on slots are not keys and stay.
- **The map ships ON**, so keys work out of the box.
- **The hotbar moves behind the map too**, and the map learns Ctrl/Alt/Shift
  chords for it.
- **Old key tests**: port each scenario the behaviour and map tests do not
  already cover, drop the rest.

### Modifier chords

- A gesture is `[ctrl+][alt+][shift+]<key>`, the modifiers in any order. They
  are tracked from their own key edges, either side (the hotbar's technique),
  and matched EXACTLY: `ctrl+1` is not Ctrl+Alt+1.
- A key pressed with modifiers held and no exact gesture falls back to its
  bare gesture, since the crossbar always ignored modifiers (Shift+`;` still
  raises the left side; Ctrl+Alt+1 reaches the crossbar's slot 1, which keeps
  it only while a side is up - as before).
- Any other chord (`semicolon+1`) is still reported and skipped.
- A key already down delivers nothing until it comes up, mapped or not, taken
  or not: Ctrl arriving under a held arrow must not make its repeats
  `ctrl+up` (the hotbar's rule).

### The hotbar

- Behaviours `bar1_slot1` .. `bar8_slot10` (the anchors' names), `cycle` and
  `cycle_back` (the CLI's words). A slot fires and keeps its key unless a
  guard is up (chat, suppressed, layout, edit, disabled) or its row is
  hidden; the cycle pair fire and keep neither edge, as Ctrl+Up/Down did.
- Shipped: Ctrl, Alt, Shift, Ctrl+Shift, Alt+Shift and Ctrl+Alt+Shift over
  `1`..`0` are rows 1-6; `ctrl+up`/`ctrl+down` cycle. Rows 7 and 8 are
  declared and unbound, so the pad or a hand edit can reach them.

### What changes from before

- **Ctrl, Alt or Shift + number with a crossbar side or the switch up is the
  hotbar's**: the chord is the more specific gesture. It used to be the
  crossbar's, registered first. Kevin kept the chord first (2026-11-09) over
  giving the crossbar the number row first again, knowing what follows from
  it (Deviations, below).
- The crossbar's `input` settings leave its defaults; a stored block is dead
  weight.

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
- **Core** offers each key to the map before every component; a key the map takes reaches any component that
  still reads raw keys as `blocked`. None shipped does: the crossbar and the
  hotbar read behaviours alone (Kevin's call, above).
- **The crossbar** declares `layer` and `select`; its machine lost `on_key`,
  its DIK lists, its conflict report and its latch, and `on_behavior` answers
  the keep verdict with the rules the keys used to.
- **The hotbar** declares `bar1_slot1` .. `bar8_slot10`, `cycle` and
  `cycle_back`; its machine lost its key tracking (modifiers, repeats,
  latches - now the map's).
- **`//hud keyboard [on|off]`** and **`//hud keyboard list`**: the switch,
  the map's problems, the map. A row on the settings window's `global` panel
  beside the gamepad's.

## Calls made while Kevin was away (still open)

- **No `bind`/`unbind` yet**: the map is a file edit until the verbs are
  built, `//hud gamepad bind`'s grammar being the model.
- **Key names** are DirectInput's, lowercased, with `numpad*`, `numpad+`,
  `numpad-`, `enter` and `escape` spelled as `setkey` spells them. A `;`
  cannot be typed in a Windower command (it separates commands), which is why
  `semicolon` is a word.
- **Custom crossbar shortcuts** (`config.input.shortcuts` beyond Select) have
  no behaviour of their own; their verbs can be the map's actions instead.
  Nothing migrates, as ever.

(Settled by Kevin since: the map ships on, the old paths go, the hotbar
moves behind the map and the map reads Ctrl/Alt/Shift chords - above.)

## Deviations from the crossbar's own keys

- **A key another addon swallowed is ignored outright.** The crossbar used to
  track it - a `;` some other addon took still raised the side, though the
  key itself fired nothing - where the map never delivers a press that
  arrives blocked (a release is still delivered for a press it did).
- **A game key or an action on a key does nothing while the chat line is
  open**, and the key types. Component behaviours are delivered as ever and
  decide for themselves, as the crossbar does.
- **Switching the map off while a crossbar key is held** drops that side at
  once (the map lets go of what it holds), and from then on no key reaches
  either bar.
- **Ctrl, Alt or Shift + number with a crossbar side or the switch up is the
  hotbar's** (the more particular entry), where registration order used to
  give it to the crossbar - Kevin's call, 2026-11-09. The crossbar never sees
  it, so under the switch the switch's release cycles as well, where it used
  to jump to that set; and on a HIDDEN hotbar row (2-8 ship hidden), or with
  the whole hotbar hidden or not loaded, the chord fires nothing and goes to
  the game, where Alt+1 under a raised side used to fire the crossbar's slot
  1. Found by review (rounds 1-3 of the keys gate).

## A handler the guard switched off (review, 2026-11-12)

Fixed 2026-11-12 (Kevin: "Yes, fix it"). When `lib/guard` switched the
`keyboard` handler off after five failures, no key's up was heard again, so
whatever the map held - a raised side, a game key down through `setkey` -
stayed held until the next focus loss or unload. The entry point's `keyboard`
guard now takes the `on_disable` the pad's does and lets go through
`core.release_keyboard`, cancelled, as a lost focus does. The gap is older
than the pad's; the review of the pad's fix found it.

## Unverified in a live client

All of it - in particular that a release Windower delivers after the map was
switched off still reaches the map, and the key names beyond the ones the
crossbar already used.
