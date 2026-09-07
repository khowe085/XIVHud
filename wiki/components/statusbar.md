# Status bar

Alias: `sb`

## Description

FFXIV's status display for FFXI: your active buffs and debuffs as a row of
icons with the time remaining under each, on up to **three bars** you place
independently - one for everything, or one for buffs, one for debuffs and
one for the rest.

## Features

- Every effect on you as its icon, with the remaining time beneath it in
  FFXIV's style: seconds under a minute (`59`), then minutes (`12m`), then
  hours (`2h`).
- **Three bars** (`bar1`, `bar2`, `bar3`), each placed on its own and each
  showing one **category**: `all`, `buffs`, `debuffs` or `other` (food, the
  mount, signets, restrictions and the like). Bar 1 ships on with `all`;
  bars 2 and 3 ship off, set to `debuffs` and `other`.
- Each bar is **1 to 4 rows** deep: 20x1, 10x2, 7x3 or 5x4 icons.
- When there are more effects than a bar can hold, the highest-priority ones
  are drawn. The order and a per-bar filter list are yours to edit.
- **Hover** an icon to see the buff's name and id; **right-click** one to
  cancel it (this uses the Windower `cancel` addon, and does nothing if that
  addon is not loaded).
- Timers can be switched off, leaving the icons alone.

## Configuration options

`config.lua` in the component's folder. All of these are set by command.

| Option | Default | What it does |
| --- | --- | --- |
| `bars.<bar>.filter` | `"all"` / `"debuffs"` / `"other"` | the category that bar shows |
| `bars.<bar>.rows` | `1` | rows on that bar (1-4) |
| `bars.<bar>.filters` | `{}` | that bar's own filter list of buff ids |
| `bars.<bar>.filter_mode` | `"blacklist"` | whether the list hides those buffs or shows only them |
| `priority` | `{}` | your changes to the buff order, shared by every bar |
| `timers` | `true` | draw the remaining time under each icon |
| `tooltips` | `true` | name the buff under the cursor |

Which bars are on is stored with the placement: `//hud show statusbar bar2`
switches one on, or SHIFT + right-click it in layout mode.

## Commands

Per-bar commands take an optional bar word in front of the verb: `bar1` (the
default), `bar2` or `bar3`.

| Command | What it does |
| --- | --- |
| `//hud statusbar` | print all three bars and the two switches |
| `//hud statusbar [<bar>]` | print one bar's settings |
| `//hud statusbar [<bar>] rows <1-4>` | set how many rows the bar has |
| `//hud statusbar timers on\|off` | show or hide the timers on every bar |
| `//hud statusbar tooltips on\|off` | name the buff under the cursor, or not |
| `//hud show statusbar <bar>` / `//hud hide statusbar <bar>` | switch one bar on or off |

`timers` and `tooltips` apply to every bar and refuse a bar word.

### Buffs

Which category a bar shows, its filter list, and the priority order are set
through `//hud buffs statusbar` - the shared grammar described on the
[home page](../Home.md#buff-order-and-filters):

| Command | What it does |
| --- | --- |
| `//hud buffs statusbar` | what every bar draws right now, including anything past its capacity |
| `//hud buffs statusbar <bar>` | the same for one bar |
| `//hud buffs statusbar [<bar>] filter all\|buffs\|debuffs\|other` | set the bar's category |
| `//hud buffs statusbar [<bar>] filter add\|remove <id\|name>` | edit the bar's own filter list |
| `//hud buffs statusbar [<bar>] filter clear\|list` | empty or print it |
| `//hud buffs statusbar [<bar>] filter mode blacklist\|whitelist` | hide the listed buffs, or show only them |
| `//hud buffs statusbar list [<page>]` | the full priority order |
| `//hud buffs statusbar find <text>` | search buffs by name |
| `//hud buffs statusbar top\|up\|down <id\|name>` | move a buff in the order |
| `//hud buffs statusbar rank <id\|name> <n>` | put a buff at position `n` |
| `//hud buffs statusbar reset` | back to the shipped order |

The priority order is one list shared by all three bars, so the order verbs
take no bar word. The category and the filter list belong to one bar each.
