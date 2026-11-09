# Parameter bar

Alias: `pb`

## Description

FFXIV's parameter bar for FFXI: your HP, MP and TP as three filled bars with
the number beside each, sitting at the bottom centre of the screen.

## Features

- Three bars - HP, MP, TP - that ease smoothly toward the new value rather
  than jumping.
- The HP and MP numbers change colour as they drop: yellow, then orange, then
  red.
- The TP number turns blue at 1000 or more, and the TP bar is dimmed below
  that and full from there to 3000. An HP or MP number reads 0 whenever its
  percentage does.
- A **compact** mode with narrower bars and tighter spacing.
- A **melee accuracy** row above the TP bar - how many of your swings landed
  over the last thirty seconds, with your measured attack delay on the end;
  `//hud parambar accuracy reset` starts a fresh count.
- A **multi-attack** row above that - how often your rounds carried an extra
  attack, over the same window.

## The accuracy row

`Acc: 78% (7/9) - 2.4s` above the TP bar: the percentage, the hits and swings
it was measured over, and your attack delay, all on a rolling window. It reads
the same action packets the game prints your attacks from, counting the two
hit messages (a hit and a critical hit) and the two miss messages, for your
own swings only - your pet's do not count, and neither do your ranged
attacks, which are a different stat.

Only those four messages count. A swing the game reports any other way - a
parry, a counter, a Third Eye evasion - is **neither** a hit nor a miss and
never reaches the total, since none of them is your accuracy failing. The
figure is "of the swings that landed or missed", the same rule the `scoreboard`
addon uses.

**The delay is measured, not calculated.** It is the median time between
your melee rounds over the same window - what your swings are actually
landing at, after gear, haste, songs, dual wield and everything else. It has
to be measured, because nothing in the game tells an addon your haste: gear
haste only exists as item description text, and a march's strength depends on
the bard's own skill and instrument, which your client cannot see. It reads
`--s` until two rounds have landed; before any swing has landed the whole row
reads `Acc: --% (0/0) - --s`.

The figure is the **median** gap rather than the average, so that a
weaponskill, a cast or a step out of range does not drag it. That needs a
handful of gaps to work, which is half of why the window is thirty seconds:
at a four-second delay it holds six or seven. Shorten the window much and the
delay gets jumpy.

Both rounds have to fall inside the window for a gap to be measured, so a
very slow weapon can sit at `--s`. Widen the window if it does.

**The sample is small, and the counts are there so you can see how small.**
Thirty seconds is eight or ten swings with one weapon - more with dual wield
or a multi-attack proc - so the percentage still moves in visible steps and a
couple of misses swing it. Widen the window with `//hud parambar accuracy
window 60` if you want a steadier number, or read the `(7/9)` rather than the
percentage.

`//hud parambar accuracy reset` empties the window, so you can start a fresh
count on a new fight or after a gear change; logging out empties it too. The
row is text only - there is nothing on it to click, and the parameter bar takes
no part in the mouse at all.

Switching the row on or off changes how tall the widget is, so the bars move
down or up by the height of the row; drag the parameter bar back where you
want it in `//hud layout` afterwards. The count keeps running while the row is
off, so switching it back on shows the full window rather than a fresh one.

## The multi-attack row

`Multi. Attk: 30%` above the accuracy row: the share of your melee rounds in
the accuracy window that carried an extra attack - more than one hand swing
with one weapon, more than two when dual wielding (or fighting hand-to-hand,
which swings twice a round). A round is dual wield when it holds an off-hand
swing, so nothing reads your gear. Every hand swing counts, parried or not; a
Kick Attack or a Daken is not a multi-attack and is left out (a Zanshin
repeat is one, and counts), and a round of
kicks alone (Footwork) is left out of the share altogether. A round whose every
swing was parried or hit a shadow still counts - leaving those out would
make the figure read high, since one swing is stopped more often than two. A round that kills the
target on its first swing ends there, so on fast kills the figure reads a
little low. It
reads `--%`
until a round has landed, and shares the accuracy row's window, reset, font
and placement; with the accuracy row off it takes that row's place.

Turning it on or off moves the bars, as the accuracy row does - and because it
ships on, an existing parameter bar drops about thirteen pixels the first time
it loads with it (seventeen if the accuracy row was off). Drag it back in `//hud layout`.

## Configuration options

`config.lua` in the component's folder. Everything here can be left alone;
`compact`, `accuracy.enabled`, `accuracy.window_seconds` and `multi_attack`
are also set by command.

The bars' width, spacing and position are not settings: the troughs and the
HP/MP/TP labels are part of the background image, so the fills are fixed to
it. A `bar` or `compact_bar` block left in an older `config.lua` is ignored.

| Option | Default | What it does |
| --- | --- | --- |
| `compact` | `false` | use the compact bar art, with narrower bars and tighter spacing |
| `dim_tp_bar` | `true` | draw the TP bar dimmed until TP reaches 1000 |
| `font` | `"sans-serif"` | font for the numbers and both rows |
| `font_size` | `14` | font size |
| `text_offset` | `0` | shifts the numbers sideways, in pixels |
| `text_color` | white | colour of the numbers and both rows |
| `text_stroke` | dark, width 2 | outline around the numbers and both rows |
| `full_tp_color` | blue | TP number colour at 1000 or more |
| `low_hp_colors` | yellow / orange / red | HP number colour under 75% / 50% / 25% |
| `low_mp_colors` | yellow / orange / red | the same for MP |
| `accuracy.enabled` | `true` | draw the accuracy row above the TP bar |
| `accuracy.window_seconds` | `30` | how many seconds of swings the row counts (1 to 600) |
| `accuracy.font_size` | `8` | font size for both rows - smaller than the numbers |
| `accuracy.bar_gap` | `7` | clearance between the row and the bars - raise it if the line sits on the bar art |
| `accuracy.line_gap` | `2` | clearance between the multi-attack row and the accuracy row - raise it if the two touch |
| `accuracy.offset` | `0` | shifts both rows sideways, in pixels |
| `accuracy.text_width_ratio` | `0.68` | how wide a character is assumed to draw - sets how much room the row reserves for its longest line |
| `accuracy.text_height_ratio` | `1.3` | how tall a line is assumed to draw - sets the row's height |
| `multi_attack` | `true` | draw the multi-attack row above the accuracy row |

## Commands

Every setting below can also be changed with the mouse: `//hud config parambar`
opens the [settings window](../Home.md#settings-window) on this component,
where the window length steps five seconds a click. (`accuracy reset` is an
action rather than a setting, so it is not there.)

| Command | What it does |
| --- | --- |
| `//hud parambar` | print the compact, accuracy and multi-attack state, with the window length |
| `//hud parambar compact on\|off` | switch compact mode |
| `//hud parambar accuracy` | print the row's state, window and current reading |
| `//hud parambar accuracy on\|off` | show or hide the accuracy row |
| `//hud parambar accuracy reset` | empty the window and start a fresh count |
| `//hud parambar accuracy window <seconds>` | set how much history the row counts (1 to 600) |
| `//hud parambar multiattack` | print the multi-attack row's state and current reading |
| `//hud parambar multiattack on\|off` | show or hide the multi-attack row |
