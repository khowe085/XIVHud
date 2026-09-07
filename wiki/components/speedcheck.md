# Speed check

Alias: `spd`

## Description

Your movement speed bonus as a signed percentage - `+12%`, `-50%` - drawn
under a running-figure icon. Handy for seeing whether a mount, a movement
speed buff or a piece of gear is actually doing something.

## Features

- Reads your speed from the game and shows it relative to normal walking
  speed: `+0%` on foot with nothing on, more with speed gear or a mount,
  less while slowed or weighed down.
- Shows `--%` until the first reading arrives after login.
- Keeps the last value through a zone rather than blanking.
- The icon can be switched off.

## Configuration options

`config.lua` in the component's folder. There are no console commands; these
are set by editing the file.

| Option | Default | What it does |
| --- | --- | --- |
| `font` | `"sans-serif"` | font for the number |
| `font_size` | `10` | font size |
| `bold` | `true` | bold number |
| `italic` | `false` | italic number |
| `text_color` | white | number colour |
| `text_stroke` | black, width 2 | outline around the number |
| `text_offset.x` / `.y` | `0` / `0` | nudge the number against the icon |
| `text_gap` | `-1` | vertical gap between icon and number |
| `bg.visible` | `false` | draw a backing box behind the number |
| `bg` colour | black, `a = 100` | the backing box colour and opacity |
| `icon.visible` | `true` | draw the icon above the number |
| `icon.size` | `32` | icon size in pixels (square) |
| `icon.color` | white | tint applied to the icon |

## Commands

None. The component is switched on and off with `//hud show spd` and
`//hud hide spd`, and placed in `//hud layout`.
