# Target bar

Alias: `tb`

## Description

Your current target's health bar, drawn top centre of the screen in the party
list's art: a row reading `HP% | distance | name` above a bar that fills to
the target's HP, with a smaller cast bar beneath it while the target is
casting or readying a TP move. A second, smaller copy of the whole bar follows
the game's **subtarget cursor** - the `<st>` selection you move through the
party or the nearby mobs while choosing a target for a spell or ability.

## Features

- **Two bars**, placed separately: `main` follows your target and
  `subtarget` follows the `<st>` cursor. The subtarget bar is the same bar at
  60% size, seeded directly under the main one, and shows only while a
  subtarget cursor is up.
- HP percentage, distance and name for whatever is targeted - a monster, a
  player or an NPC.
- The **HP number** turns yellow, orange and red as the target drops below
  75%, 50% and 25%.
- The **bar fill colour** shows claim: red for a monster you or your alliance
  have claimed, purple for one claimed by someone else, yellow-green for an
  unclaimed one, cyan for a party member, white for another player, grey
  for a dead one.
- The **distance** is coloured by whether you are in range for the range mode
  below. In `magic` and `ninjutsu` it is white out of range and green in
  range. For the `gun`, `bow` and `xbow`
  modes it also marks the sweet spot: yellow in range, green inside the Square
  Shot band, blue inside the True Shot band.
- A **cast bar** rises while the target winds up a spell or TP move, with the
  name of what is coming. It clears when the cast finishes or is interrupted.
- Long names are cut to fit.

## Configuration options

Every option is per bar, under `bars.main` and `bars.subtarget` in
`config.lua`. Only `distance.mode` is set by command.

| Option | Default | What it does |
| --- | --- | --- |
| `distance.mode` | `"auto"` | which range table colours the distance (see Commands) |
| `distance.colors.out` / `capable` / `good` / `best` | white / yellow / green / blue | the four distance colours |
| `font` | `"Arial"` | font for the row |
| `font_size` | `14` | font size |
| `text_color` | white | row text colour |
| `text_stroke` | dark blue, width 2 | outline around the text |
| `bands.yellow` / `orange` / `red` | yellow / orange / red | the HP number colours under 75% / 50% / 25% |
| `fill_colors.mine` | red | bar colour for a monster claimed by your alliance |
| `fill_colors.claimed` | purple | claimed by someone else |
| `fill_colors.unclaimed` | yellow-green | unclaimed |
| `fill_colors.member` | cyan | a party member |
| `fill_colors.pc` | white | another player |
| `fill_colors.dead` | grey | a dead target |
| `name_max_chars` | `17` | longest name drawn before it is cut |
| `gap` | `8` | gap between the text row and the bar |
| `cast.scale` | `0.67` | size of the cast bar relative to the health bar |
| `cast.font_size` | `12` | font size of the cast name |
| `cast.fill_color` | yellow-green | cast bar fill colour |
| `cast.gap` | `4` | gap between the health bar and the cast bar |
| `cast.name_gap` | `2` | gap between the cast bar and its name |
| `cast.name_max_chars` | `20` | longest cast name drawn before it is cut |
| `cast.tp_move_sweep` | `2` | seconds a TP move's bar takes to fill (the game reports no duration for them) |

The subtarget bar's smaller size is its scale in layout mode (0.6 out of the
box), so resize it there with the mouse wheel like any other piece. Which
bars are on is stored with the placement: `//hud hide targetbar subtarget`
switches one off, or SHIFT + right-click it in layout mode.

## Commands

Every command takes an optional bar word in front of the verb: `main` (the
default) or `subtarget`.

| Command | What it does |
| --- | --- |
| `//hud targetbar` | print both bars and the range mode each is in |
| `//hud targetbar [<bar>]` | print one bar's range mode |
| `//hud targetbar [<bar>] mode auto` | pick the range table from your main job |
| `//hud targetbar [<bar>] mode default` | no range colouring; the distance stays white |
| `//hud targetbar [<bar>] mode magic` | spell range |
| `//hud targetbar [<bar>] mode ninjutsu` | ninjutsu range |
| `//hud targetbar [<bar>] mode gun` | gun range |
| `//hud targetbar [<bar>] mode bow` | bow range |
| `//hud targetbar [<bar>] mode xbow` | crossbow range |
| `//hud show targetbar <bar>` / `//hud hide targetbar <bar>` | switch one bar on or off |

`auto` picks `magic` for RDM, BLM, WHM, SCH, GEO and BRD, `ninjutsu` for NIN
and `gun` for COR. Every other job gets `default`, which colours nothing;
a Ranger should pick `gun`, `bow` or `xbow` by hand, since the game does not
say which ranged weapon is equipped.
