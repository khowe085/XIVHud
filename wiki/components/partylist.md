# Party list

Alias: `pl`

## Description

FFXIV's party list for FFXI: your party as a column of rows, each with the
member's name, job, level, HP/MP/TP bars, buff icons and distance. Both
alliance parties are available as two further lists,
off by default, that you place separately.

## Features

- One row per party member: name, main and sub job with levels, HP, MP and
  TP as bars with numbers.
- The HP number changes colour as HP drops: yellow, then orange, then red
  under 75%, 50% and 25%. A full TP bar is marked.
- A **job icon** on each row, coloured by role (tank, healer, damage,
  support).
- Up to sixteen **buff icons** per member, ordered by priority and filtered
  to your liking (see Buffs below).
- Members out of range are **dimmed**, and a **range indicator** can mark who
  is within a chosen distance of you - as icons, or as the distance in yalms.
- The targeted member is highlighted.
- The **alliance lists** (`alliance1`, `alliance2`) show the other two
  parties in a compact row layout, each placed on its own.
- Optional: hide the list while solo, show empty rows, align rows to the
  bottom instead of the top, set the row spacing.

## Configuration options

Every option below is per list, under `lists.main`, `lists.alliance1` and
`lists.alliance2` in `config.lua`. All but `buffs.max_icons` are also set by command.

| Option | Default | What it does |
| --- | --- | --- |
| `item_spacing` | `0` | extra pixels between rows |
| `align_bottom` | `false` | grow the list upward from its bottom edge rather than down from the top |
| `show_empty_rows` | `false` | draw the rows of empty party slots |

The main list only:

| Option | Default | What it does |
| --- | --- | --- |
| `hide_solo` | `false` | hide the list while you are not in a party |
| `range.numeric` | `false` | show the distance as a number instead of icons |
| `range.near` | `0` | distance for the near indicator, in yalms (0 is off) |
| `range.far` | `0` | distance for the far indicator (0 is off) |
| `buffs.max_icons` | `16` | how many buff icons a row draws at most (the art holds 16) |
| `buffs.filter_mode` | `"blacklist"` | whether `filters` hides the listed buffs or shows only them |
| `buffs.filters` | `{}` | the filtered buff ids |
| `buffs.priority` | `{}` | your changes to the buff order |

Which lists are on is stored with the placement: `//hud show partylist
alliance1` switches one on, or SHIFT + right-click it in layout mode.

## Commands

Every command takes an optional list word in front of the verb: `main` (the
default), `alliance1` or `alliance2`.

| Command | What it does |
| --- | --- |
| `//hud partylist` | print all three lists' settings |
| `//hud partylist [<list>]` | print one list's settings |
| `//hud partylist [<list>] spacing <px>` | set the extra space between rows |
| `//hud partylist [<list>] align top\|bottom` | grow the list down from the top or up from the bottom |
| `//hud partylist [<list>] emptyrows on\|off` | draw or hide empty party slots |
| `//hud partylist range num\|icons` | show distance as a number or as indicator icons |
| `//hud partylist range <near> <far>` | the two distances, in yalms, that the indicators mark |
| `//hud partylist hidesolo on\|off` | hide the list while solo |
| `//hud show partylist <list>` / `//hud hide partylist <list>` | switch one list on or off |

`range` and `hidesolo` apply to the main party only and refuse a list word.

### Buffs

Buff icons are drawn on the main party only. The order they draw in, and
which are hidden, are set through `//hud buffs partylist` - the shared
grammar described on the [home page](../Home.md#buff-order-and-filters) - plus
one verb of the party list's own:

| Command | What it does |
| --- | --- |
| `//hud buffs partylist` | the first sixteen buffs of the priority order - the ones a row would draw if a member had them; use `active` for what is on someone now |
| `//hud buffs partylist list [<page>]` | the full priority order |
| `//hud buffs partylist find <text>` | search buffs by name |
| `//hud buffs partylist active [<member>]` | the buffs on you, or on a named party member |
| `//hud buffs partylist top\|up\|down <id\|name>` | move a buff in the order |
| `//hud buffs partylist rank <id\|name> <n>` | put a buff at position `n` |
| `//hud buffs partylist reset` | back to the shipped order |
| `//hud buffs partylist filter add\|remove <id\|name>` | edit the filter list |
| `//hud buffs partylist filter clear\|list` | empty or print it |
| `//hud buffs partylist filter mode blacklist\|whitelist` | hide the listed buffs, or show only them |

The word `main` may be written after `partylist` on any of these; the
alliance lists are refused, since they draw no buff icons.
