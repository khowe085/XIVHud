# Skillchain indicator

Alias: `sc`

## Description

A small bar that shows the skillchain window on your target: whether the
next step of a chain is allowed yet, and how long the window has left. It
uses the same skillchain detection the crossbar and hotbar use for their
property icons.

## Features

- **Red and thin** while a weaponskill has landed but the next step is not
  yet allowed.
- **Green and thick** while the window is open, shrinking as the window
  closes.
- Nothing is drawn when no chain is in progress.
- Ships on, centred near the bottom of the screen above where the crossbar's
  WXHB sits. Move and resize it in `//hud layout` like any other component.

## Configuration options

`config.lua` in the component's folder. There are no console commands; these
are set by editing the file.

| Option | Default | What it does |
| --- | --- | --- |
| `opacity` | `220` | opacity of the bar (0-255) |
| `waiting_color` | red | bar colour while the next step is not yet allowed |
| `open_color` | green | bar colour while the window is open |

## Commands

None. Switch it on and off with `//hud show sc` and `//hud hide sc`, and
place it in `//hud layout`.
