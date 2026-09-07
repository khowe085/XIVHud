# Equipment viewer

Alias: `ev`

## Description

Your equipped gear as a 4x4 grid of item icons on a dark panel, one cell per
equipment slot, so you can see at a glance what you are wearing without
opening the equipment menu.

## Features

- Sixteen slots in the game's own arrangement, each showing the icon of the
  item in it.
- Updates as you change gear, including GearSwap swaps.
- Draws an **X** over any slot that encumbrance has locked.
- Shows your **ammo count** over the ammo slot.
- Icons are read straight out of the game's data files the first time an
  item is seen, then cached in `addons/XIVHud/icons/` for every character.
  No icon pack to download.

## Configuration options

`config.lua` in the component's folder. The two toggles are also set by
command.

| Option | Default | What it does |
| --- | --- | --- |
| `show_encumbrance` | `true` | draw an X over locked slots |
| `show_ammo_count` | `true` | draw the ammo count over the ammo slot |
| `icon_size` | `32` | size of each slot in pixels |
| `icon` colour | white, `a = 230` | tint and opacity of the item icons |
| `bg.visible` | `true` | draw the panel behind the grid |
| `bg` colour | black, `a = 72` | the panel colour and opacity |
| `encumbrance_alpha_factor` | `0.8` | opacity of the encumbrance X relative to the icon |
| `ammo_text.font` | `"sans-serif"` | font for the ammo count |
| `ammo_text.size_factor` | `0.27` | ammo count size as a fraction of the slot size |
| `ammo_text.y_factor` | `0.58` | where in the slot the count sits, top to bottom |
| `ammo_text.bold` / `italic` | `true` / `true` | ammo count style |
| `ammo_text` colour | white, `a = 230` | ammo count colour |
| `ammo_text.stroke` | black, width 1 | outline around the count |
| `game_path` | `""` | where FFXI is installed, if the addon cannot find it on its own (the folder containing `ROM`) |

If icons stay blank, the addon could not find your FFXI install. Set
`game_path` to the game's folder, for example
`"C:\\Program Files (x86)\\PlayOnline\\SquareEnix\\FINAL FANTASY XI"`.

## Commands

| Command | What it does |
| --- | --- |
| `//hud equipviewer` | print both toggles as they stand |
| `//hud equipviewer encumbrance on\|off` | show or hide the X over locked slots |
| `//hud equipviewer ammocount on\|off` | show or hide the ammo count |
