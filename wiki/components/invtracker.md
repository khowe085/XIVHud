# Inventory tracker

Alias: `inv`

## Description

FFXIV's inventory grid for FFXI: every slot of the bags you choose drawn as a
small coloured square, so you can see how full each bag is without opening a
menu. Bags sit side by side as blocks, each with its short name under it.

## Features

- One block per bag, in your choice of bags and column counts.
- **Square colours** tell you what is in a slot: teal for an ordinary item,
  red for a full stack, white for equipment, green for something equipped
  (or a worn linkshell), orange for an item in your bazaar, pink for a
  temporary item, dark for an empty slot.
- Updates whenever something moves - a pickup, a drop, a sale, a swap.
- A **sort** option orders each bag by kind and fullness so the picture is
  easy to read.
- The temporary items bag and the treasure pool show only what they hold and
  disappear when empty.
- Bags that share a purpose are one word: `safe` covers both Mog Safes and
  `wardrobe` covers all eight wardrobes.

## Configuration options

`config.lua` in the component's folder. Everything in the first table is
also set by command.

| Option | Default | What it does |
| --- | --- | --- |
| `bags.<bag>.enabled` | see below | draw that bag |
| `bags.<bag>.columns` | see below | how many squares wide its block is (1-20) |
| `sort` | `true` | sort each bag for display |
| `spacing` | `4` | pixels from one square to the next (at least `slot_size`, at most 32) |
| `block_spacing` | `4` | pixels between bag blocks (0-64) |
| `align` | `"bottom"` | whether blocks of different heights line up along their bottom or top edge |
| `labels.enabled` | `true` | draw each bag's short name under its block |

Bags and their shipped state:

| Bag word | Covers | Drawn by default | Columns |
| --- | --- | --- | --- |
| `equipment` | equipped gear | no | 4 |
| `inventory` | your inventory | yes | 5 |
| `safe` | Mog Safe and Mog Safe 2 | no | 5 |
| `storage` | Storage | no | 4 |
| `locker` | Mog Locker | no | 5 |
| `satchel` | Mog Satchel | yes | 5 |
| `sack` | Mog Sack | yes | 5 |
| `case` | Mog Case | yes | 5 |
| `wardrobe` | Wardrobes 1-8 | no | 5 |
| `temporary` | temporary items | yes | 1 |
| `treasure` | the treasure pool | yes | 1 |

Appearance options, set by editing the file:

| Option | Default | What it does |
| --- | --- | --- |
| `slot_size` | `3` | size of a square's shadow, in pixels |
| `box_size` | `2` | size of the square itself |
| `labels.font` / `font_size` | `"sans-serif"` / `6` | the label font |
| `labels.bold` / `italic` | `false` / `false` | label style |
| `labels.gap` | `1` | gap between block and label |
| `labels.color` / `stroke` | light grey / black, width 1 | label colour and outline |
| `colours.default` | teal | an ordinary item |
| `colours.full_stack` | red | a full stack |
| `colours.equipment` | white | a piece of equipment |
| `colours.equipped` / `linkshell_equipped` | green | something equipped |
| `colours.bazaar` | orange | an item in your bazaar |
| `colours.temp_item` | pink | a temporary item |
| `colours.empty` | dark | an empty slot |

Each colour has a `box` (the square) and a `shadow` (the 1px relief behind
it).

## Commands

| Command | What it does |
| --- | --- |
| `//hud invtracker` | list every bag with its on/off state and columns, then sort, labels, spacing and alignment |
| `//hud invtracker <bag>` | print one bag's on/off state and column count |
| `//hud invtracker <bag> on\|off` | draw or hide a bag |
| `//hud invtracker <bag> columns <1-20>` | set a bag's width in squares |
| `//hud invtracker sort on\|off` | sort each bag for display |
| `//hud invtracker labels on\|off` | show or hide the bag names |
| `//hud invtracker spacing <px>` | pixels between squares |
| `//hud invtracker blockspacing <px>` | pixels between bags |
| `//hud invtracker align top\|bottom` | line blocks up along their top or bottom edge |

`<bag>` is one of the words in the table above.
