# Gil tracker

Alias: `gt`

## Description

Your current gil, drawn as a number beside the gil icon in the bottom right
of the screen, in the style of FFXIV's currency display.

## Features

- Updates the moment your gil changes - a sale, a purchase, a reward, a
  trade.
- The number is formatted with thousands separators.
- The icon stays put as the digits change.
- The icon can be switched off, leaving the number alone.

## Configuration options

`config.lua` in the component's folder. There are no console commands; these
are set by editing the file.

| Option | Default | What it does |
| --- | --- | --- |
| `font` | `"sans-serif"` | font for the number |
| `font_size` | `9` | font size |
| `italic` | `true` | italic number |
| `bold` | `false` | bold number |
| `text_color` | white | number colour |
| `text_stroke` | dark grey, width 2 | outline around the number |
| `text_y_offset` | `4` | vertical nudge for the number |
| `bg.visible` | `false` | draw a backing box behind the number |
| `bg` colour | black, `a = 100` | the backing box colour and opacity |
| `icon.visible` | `true` | draw the gil icon |
| `icon.size` | `23` | icon size in pixels (square) |
| `icon.gap` | `1` | gap between icon and number |
| `icon.color` | white | tint applied to the icon |

## Commands

None. The component is switched on and off with `//hud show gt` and
`//hud hide gt`, and placed in `//hud layout`.
