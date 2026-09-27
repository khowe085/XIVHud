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
  that.
- A **compact** mode with narrower bars and tighter spacing.
- Width, spacing and offset can be changed from the console.
- A **melee accuracy** row above the TP bar - how many of your swings landed
  over the last fifteen seconds, with your measured attack delay on the
  end; `//hud parambar accuracy reset` starts a fresh count.

## The accuracy row

`Acc: 7 / 9 (78%) / 2.4s` above the TP bar: the hits, the swings, the
percentage and your attack delay, over a rolling window. It reads the same action packets the game
prints your attacks from, counting the two hit messages (a hit and a critical
hit) and the two miss messages, for your own swings only - your pet's do not
count, and neither do your ranged attacks, which are a different stat.

A parry, a block, a counter, a guard or a Third Eye evasion counts as
**neither** a hit nor a miss, so none of them reaches the total. None of them
is your accuracy failing. The figure is "of the swings that landed or missed",
and that is the same rule the `scoreboard` addon uses.

**The delay is measured, not calculated.** It is the median time between
your melee rounds over the same window - what your swings are actually
landing at, after gear, haste, songs, dual wield and everything else. It has
to be measured, because nothing in the game tells an addon your haste: gear
haste only exists as item description text, and a march's strength depends on
the bard's own skill and instrument, which your client cannot see. It reads
`--s` until two rounds have landed.

The figure is the **median** gap rather than the average, so that a
weaponskill, a cast or a step out of range does not drag it - but fifteen
seconds only holds two or three gaps, and over so few the median is barely
better than an average. Widen the window to about thirty seconds if you want
a number that holds still.

Both rounds have to fall inside the window for a gap to be measured, so a
very slow weapon can sit at `--s` at the shipped fifteen seconds. Widen the
window if it does.

**The sample is small, and the counts are there so you can see how small.**
Fifteen seconds is four or five swings with one weapon - more with dual wield
or a multi-attack proc - so the percentage moves in coarse steps and a single
miss swings it a long way. Widen the window with `//hud parambar accuracy
window 30` if you want a steadier number, or read the `7 / 9` rather than the
percentage.

`//hud parambar accuracy reset` empties the window, so you can start a fresh
count on a new fight or after a gear change. The row is text only - there is
nothing on it to click, and the parameter bar takes no part in the mouse at
all.

Switching the row on or off changes how tall the widget is, so the bars move
down or up by the height of the row; drag the parameter bar back where you
want it in `//hud layout` afterwards.

## Configuration options

`config.lua` in the component's folder. Everything here can be left alone;
the first four are also set by command.

| Option | Default | What it does |
| --- | --- | --- |
| `compact` | `false` | use the compact bar art and the `compact_bar` width, spacing and offset |
| `bar.width` | `132` | width of each bar, in pixels |
| `bar.spacing` | `18` | gap between bars |
| `bar.offset` | `0` | shifts the bar fills sideways, in pixels |
| `compact_bar.width` / `spacing` / `offset` | `116` / `16` / `0` | the same three, used while compact mode is on |
| `dim_tp_bar` | `true` | draw the TP bar dimmed until TP reaches 1000 |
| `font` | `"sans-serif"` | font for the numbers |
| `font_size` | `14` | font size |
| `text_offset` | `0` | shifts the numbers sideways, in pixels |
| `text_color` | white | number colour |
| `text_stroke` | dark, width 2 | outline around the numbers |
| `full_tp_color` | blue | TP number colour at 1000 or more |
| `low_hp_colors` | yellow / orange / red | HP number colour under 75% / 50% / 25% |
| `low_mp_colors` | yellow / orange / red | the same for MP |
| `accuracy.enabled` | `true` | draw the accuracy row above the TP bar |
| `accuracy.window_seconds` | `15` | how many seconds of swings the row counts (1 to 600) |
| `accuracy.font_size` | `8` | font size for the row - smaller than the numbers |
| `accuracy.bar_gap` | `7` | clearance between the row and the bars - raise it if the line sits on the bar art |
| `accuracy.offset` | `0` | shifts the whole row sideways, in pixels |
| `accuracy.text_width_ratio` | `0.68` | how wide a character is assumed to draw - sets how much room the row reserves for its longest line |
| `accuracy.text_height_ratio` | `1.3` | how tall a line is assumed to draw - sets the row's height |

## Commands

| Command | What it does |
| --- | --- |
| `//hud parambar` | print the current width, spacing, offset and compact state |
| `//hud parambar width <px>` | set the bar width |
| `//hud parambar spacing <px>` | set the gap between bars |
| `//hud parambar offset <px>` | shift the bar fills sideways |
| `//hud parambar compact on\|off` | switch compact mode |
| `//hud parambar accuracy` | print the row's state, window and current reading |
| `//hud parambar accuracy on\|off` | show or hide the accuracy row |
| `//hud parambar accuracy reset` | empty the window and start a fresh count |
| `//hud parambar accuracy window <seconds>` | set how much history the row counts (1 to 600) |

`width`, `spacing` and `offset` change the metrics of whichever mode is on:
with compact mode on they change the compact set.

`//hud parambar accuracy reset` is the only way to empty the window: the row
is text, with nothing on it to click.
