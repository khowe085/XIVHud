# Hotbar

Alias: `hb`

## Description

FFXIV's hotbar for FFXI: a plain row of ten slots fired by the number keys,
with up to eight rows on screen at once. It is the [crossbar](crossbar.md)
with a different face - the two take the same kinds of binding, one mouse binder
and one set of commands - so anything you can bind to the crossbar you can
bind here, and the same layers, contexts, sets and rotations apply.

## Features

- **Ten slots per row, eight rows** (`bar1` to `bar8`), each placed and
  resized on its own. Row 1 ships on; rows 2 to 8 ship off.
- **Row 1 follows the active set**, the one the cycle keys move through.
  Rows 2 to 8 are locked to sets 2 to 8, so a row you switch on always shows
  the same set.
- **Four shapes per row**: 10x1, 5x2, 2x5 or 1x10. Slots are numbered left
  to right, top to bottom, so a binding stays on the same slot whatever the
  shape.
- **Keyboard driven, no configuration**: the bare number row `1` to `0` fires
  row 1, and the modifiers pick the row - CTRL for `bar2`, ALT for `bar3`,
  SHIFT for `bar4`, CTRL+SHIFT for `bar5`, ALT+SHIFT for `bar6`,
  CTRL+ALT+SHIFT for `bar7`. `bar8` has no keys and is mouse only.
  **CTRL+Up** and **CTRL+Down** cycle the active set (the game's own macro set
  changes on the same chord).
- **Left-click a slot** to fire it.
- The same slot art as the crossbar: icon, name, recast arc, MP or TP cost,
  item and tool counts, and the skillchain property a weaponskill would make
  while a chain is open.
- **A mouse binder** (`//hud hotbar edit`): click a slot, pick a layer, pick an
  action from what your character knows.
- **Sets, sharing and rotations** work exactly as on the crossbar: eight
  sets per job, any of them shared across jobs, each in the drawn rotation,
  the sheathed one, both or neither.

Keys fire a row whether or not it is on screen. The game's own CTRL and ALT
macro palette still fires on those chords, so if you use rows 2, 3 and 5 to
7, leave the matching in-game macros empty.

## Configuration options

Bindings are stored per job in the addon's data folder (`<JOB>.lua` and
`SHARED.lua`), separate from the crossbar's, and are edited with the binder
or the commands below. `config.lua` beside them holds the settings.

**`//hud reset hotbar` deletes every job's hotbar bindings** in the active
layout slot, along with the settings - there is no undo and no confirmation
step. To start one job over, unbind its slots or `copy` another job's bindings
over it.

| Option | Default | What it does |
| --- | --- | --- |
| `bars.<bar>.rows` | `1` | that row's shape: `1` (10x1), `2` (5x2), `5` (2x5) or `10` (1x10) (`rows`) |
| `set_flags[n].shared` | `false` | set `n` is shared by every job (`share`) |
| `set_flags[n].cycle.drawn` / `.sheathed` | `true` / `true` | which rotations set `n` belongs to (`cycle`) |
| `hide.empty_slots` | `false` | leave empty slots undrawn |
| `hide.action_name` | `false` | hide the name under each slot |
| `hide.cost` | `false` | hide MP and TP costs |
| `hide.recast_animation` | `false` | hide the recast arc |
| `hide.recast_text` | `false` | hide the recast countdown text |
| `hide.skillchain_icon` | `false` | do not swap in skillchain property icons |
| `slot_spacing` | `6` | pixels between slots |
| `slot_alpha` | `100` | opacity of a slot's backing |
| `disabled_alpha` | `100` | opacity of an action you cannot use right now |
| `feedback.alpha` / `speed` | `150` / `30` | the flash when a slot fires |
| `font` / `font_size` | `"sans-serif"` / `7` | the slot label font |
| `text_offset.x` / `.y` | `0` / `0` | nudge the labels |
| `text_color` / `text_stroke` | white / dark, width 2 | label colour and outline |
| `mp_cost_color` / `tp_cost_color` | pink / yellow | the cost text colours |
| `game_path` | `""` | where FFXI is installed, if item icons stay blank (see the [equipment viewer](equipviewer.md)) |

The cast retry, the weaponskill gate and the travel countdown are settings
shared with the crossbar: `//hud retry`, `//hud wsgate` and
`//hud delay`, listed on the [home page](../Home.md#action-commands). Which
rows are on is stored with the placement: `//hud show hotbar bar2` switches
one on, or SHIFT + right-click it in layout mode.

## Commands

All commands are `//hud hotbar ...` (`hb` for short). **An address is one
word**, `<set>:<slot>` - `3:7` is set 3, slot 7, and `3:10` its last slot -
and the layer prefixes go in front as on the crossbar: `sub:3:7`, `wpn:3:7`,
`ctx:light-arts:3:7`.

| Command | What it does |
| --- | --- |
| `//hud hotbar` | the job, active set and weapon state, then one line per row: on or off, shape, the set it shows |
| `//hud hotbar <bar>` | the head line and that row alone |
| `//hud hotbar [<bar>] rows <1\|2\|5\|10>` | set a row's shape (row 1 when no row is named) |
| `//hud hotbar help` | list every command |
| `//hud hotbar edit` | toggle the mouse binder |
| `//hud hotbar set <1-8>` | switch the active set (and so row 1) |
| `//hud hotbar cycle` / `cycle back` | move to the next or previous set in the rotation |
| `//hud hotbar list [<set>]` | list what is bound on this job, layer by layer |
| `//hud hotbar bind <address> <type> [<action>] [<target>] [alias=<name>] [icon=<name>]` | bind a slot |
| `//hud hotbar unbind <address>` | clear a slot in one layer |
| `//hud hotbar alias <address> [<name>]` | change the label under a slot; omit the name to clear it |
| `//hud hotbar icon <address> [<icon>]` | change a slot's icon; omit it to clear |
| `//hud hotbar swap <address> <address>` | swap two slots, every layer at once |
| `//hud hotbar share <set> on\|off` | share a set across every job, or keep it to this one |
| `//hud hotbar cycle <set> drawn\|sheathed\|both\|none` | choose which rotations a set belongs to |
| `//hud hotbar copy <JOB>` | replace this job's hotbar bindings with another job's |
| `//hud hotbar context list` | list the buff contexts and which are live |
| `//hud hotbar open [<name>]` | list the game screens you can bind, or open one |
| `//hud show hotbar <bar>` / `//hud hide hotbar <bar>` | switch one row on or off |

A set is a set whatever row draws it, so the binding verbs take no row word.
The `<type>`, `<target>`, `alias=` and `icon=` rules are the crossbar's,
described under [Binding](crossbar.md#binding) on its page.
