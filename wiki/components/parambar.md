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

## Commands

| Command | What it does |
| --- | --- |
| `//hud parambar` | print the current width, spacing, offset and compact state |
| `//hud parambar width <px>` | set the bar width |
| `//hud parambar spacing <px>` | set the gap between bars |
| `//hud parambar offset <px>` | shift the bar fills sideways |
| `//hud parambar compact on\|off` | switch compact mode |

`width`, `spacing` and `offset` change the metrics of whichever mode is on:
with compact mode on they change the compact set.
