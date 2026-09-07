# Experience bar

Alias: `eb`

## Description

FFXIV's experience bar for FFXI: a thin gold bar with your job's icon at its
left and a status line above it, filling toward your next level, merit or
master level.

## Features

- **Three modes**, picked automatically from your job level:
  - below the level cap, the bar fills with **experience** toward the next
    level;
  - at the cap, with **limit points** toward the next merit;
  - at the cap once you hold the Master Breaker key item, with **exemplar
    points** toward the next master level.
- The status line reads like `WAR99/SAM49 (ML23) JP: 342 MP: 12 EP/hr: 12.6k`:
  your job pair, your master level where you have one, job points, merit
  points, and the rate you are earning at - `EXP/hr` below the cap, `CP/hr`
  for limit points, `EP/hr` for exemplar points.
- The fill eases toward each new value.
- Your job's icon is drawn beside the bar.

The game only reports merit totals when they change or when you zone, so a
merit-capped character who is earning nothing may read 0 merits until they
zone or open the status menu.

## Configuration options

`config.lua` in the component's folder. There are no settings commands; these
are set by editing the file.

| Option | Default | What it does |
| --- | --- | --- |
| `font` | `"sans-serif"` | font for the status line |
| `font_size` | `6` | font size (changing it also wants `bar.width` changed, or `//hud reset expbar` to recompute it) |
| `text_color` | gold | status line colour |
| `text_stroke` | dark, width 2 | outline around the text |
| `gap` | `3` | gap between the status line and the bar |
| `job_icon.gap` | `1` | gap between the job icon and the text |
| `job_icon.size` | computed | the icon's size; derived from the font size |
| `bar.height` | `5` | bar height in pixels |
| `bar.width` | computed | bar width; derived from the font size |
| `bar.inset` | `2` | how far the fill sits inside the frame |
| `bar.overhang` | `8` | how far the bar runs past the longest status line |
| `fill_color` | white | tint over the gold fill art (white leaves it gold) |
| `text_width_ratio` / `text_height_ratio` | `0.68` / `1.3` | how wide and tall the text is assumed to draw per point of font size |

## Commands

| Command | What it does |
| --- | --- |
| `//hud expbar` | print the mode, the current and required points, all three rates, and what was read for the master level |
| `//hud expbar clear` | drop the rate history and start the per-hour figures over |
