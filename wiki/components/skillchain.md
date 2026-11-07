# Skillchain indicator

Alias: `sc`

## Description

A small bar that shows the skillchain window on your target: whether the
next step of a chain is allowed yet, and how long the window has left. It
uses the same skillchain detection the crossbar and hotbar use for their
property icons.

## Features

- **Red and thin** while a chain-capable action has landed but the next step
  is not yet allowed - the game's wait before a chain can continue, three
  seconds for most actions - growing to full width over the last three seconds
  of that wait. Anyone's weaponskill, job ability, pet ability or monster move
  with skillchain properties opens a chain, as does a spell under Chain
  Affinity, Immanence or Azure Lore, and the Chainbound effect.
- **Green and thick** while the window is open, shrinking toward its centre
  as the window closes. The window is seven seconds after the opener and a
  second shorter at each later step, so the bar starts narrower each time.
- Nothing is drawn when no chain is in progress on your current target (or
  your battle target, with nothing targeted), when that target is dead, or
  once the chain is closed - after a level-4 finisher (Light on Light,
  Darkness on Darkness) or its fifth step. Zoning and logging out forget every
  chain. Layout mode shows the full green bar.
- Ships on, centred near the bottom of the screen above where the crossbar's
  WXHB sits. Move and resize it in `//hud layout` like any other component.

## Configuration options

`config.lua` in the component's folder, a file you create yourself (see
[where settings are kept](../Home.md#where-settings-are-kept)). There are no
console commands; these are set by editing the file.

| Option | Default | What it does |
| --- | --- | --- |
| `opacity` | `220` | opacity of the coloured fill (0-255); the black backdrop behind it is fixed |
| `waiting_color` | red | bar colour while the next step is not yet allowed |
| `open_color` | green | bar colour while the window is open |

## Commands

None. Switch it on and off with `//hud show sc` and `//hud hide sc`, and
place it in `//hud layout`.
