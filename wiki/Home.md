# XIVHud

## Description

XIVHud is a Windower 4 addon for Final Fantasy XI that gives the game a HUD in
the style of Final Fantasy XIV. It is a set of independent on-screen
components - a parameter bar, a party list, a target bar, a cross hotbar, a
status display and more - that you switch on or off, move and resize
individually, and that remember their placement per character.

Everything is arranged in game. There is no configuration file you have to
edit by hand to get started.

## Features

- **Twelve components**, each one optional and placed on its own (listed below).
- **Layout mode** (`//hud layout`): drag any component with the mouse, resize
  it with the wheel, switch it on or off with a right-click. Changes save at
  once.
- **Per-character settings.** Every character keeps its own placements and
  component settings, created the first time that character logs in.
- **Layout slots.** Several named arrangements per character, switched with
  one command - one for solo play and one for events, say.
- **Copy between characters.** One command copies a character's whole
  configuration onto another.
- **Auto-hide.** The HUD hides itself during cutscenes, while zoning and while
  logged out, and comes back on its own.
- **Short names.** Every component answers to a short alias wherever its
  name is taken (`//hud show pb`).

## Installation

1. Download the latest `XIVHud-<version>.zip` from the project's Releases
   page.
2. Unzip it into your Windower `addons` folder. You should end up with
   `Windower4/addons/XIVHud/XIVHud.lua`.
3. In game, load it from the console:

   ```
   //lua load xivhud
   ```

4. To load it every time you start the game, add the line `lua load xivhud`
   to `Windower4/scripts/init.txt`.

To update, unzip the new release over the old folder. Your settings (`data/`)
and your icons (`icons/`) are not in the zip and survive the update.

The HUD appears once you are logged in on a character. Type `//hud` at any
time to see the command list.

## Getting started

1. Log in on a character. Every component that is on by default comes up in
   its shipped position.
2. Type `//hud layout` to enter layout mode. Every component gets a
   highlight box with its name on it.
   - **Left-drag** a box to move it. Movement snaps to a grid; hold **CTRL**
     to move freely.
   - **Mouse wheel** over a box to scale it up or down.
   - **Right-click** a box to switch that component off or on.
   - **SHIFT + right-click** switches one piece of a component that has
     several off or on: a party list, a status bar, a hotbar row, the subtarget
     bar or a crossbar piece.
3. Type `//hud layout` again to leave layout mode. Everything you changed is
   already saved.

The crossbar and hotbar come up empty. Type `//hud crossbar edit` or
`//hud hotbar edit`, click a slot, pick which layer, then pick an action (and a target if it takes one); their pages
explain the rest. To unload the addon, type `//lua unload xivhud`. If the HUD
does not appear at all, type `//hud`: it reports what went wrong if the addon
failed to load.

Two components take over keys while a character is loaded. The crossbar
claims `;` `'` `\` `` ` `` and `=`, and the hotbar the bare number row `1`
to `0`. If you would rather keep those keys, switch the component off with
`//hud hide crossbar` or `//hud hide hotbar`.

Components can also be switched from the console: `//hud hide giltracker`,
`//hud show partylist alliance1`.

## Components

| Component | Alias | On by default | What it shows |
| --- | --- | --- | --- |
| [Crossbar](components/crossbar.md) | `cb` | yes | FFXIV's cross hotbar: sixteen slots per set, driven by held keys or a controller |
| [Hotbar](components/hotbar.md) | `hb` | yes (row 1) | FFXIV's hotbar: ten slots in a row on the number keys, up to eight rows, with the same kinds of binding and the same commands as the crossbar |
| [Parameter bar](components/parambar.md) | `pb` | yes | HP, MP and TP bars with numbers |
| [Party list](components/partylist.md) | `pl` | yes (main party) | your party and both alliance parties, with HP/MP/TP, jobs, buffs and distance |
| [Target bar](components/targetbar.md) | `tb` | yes | your target's HP, name, distance and cast bar, plus a smaller copy for the subtarget cursor |
| [Status bar](components/statusbar.md) | `sb` | yes (bar 1) | your buffs and debuffs as icons with timers |
| [Experience bar](components/expbar.md) | `eb` | yes | experience, limit points or exemplar points toward the next step |
| [Equipment viewer](components/equipviewer.md) | `ev` | yes | your equipped gear as a 4x4 icon grid |
| [Gil tracker](components/giltracker.md) | `gt` | yes | your current gil |
| [Inventory tracker](components/invtracker.md) | `inv` | yes | how full each bag is, as a grid of coloured squares |
| [Speed check](components/speedcheck.md) | `spd` | yes | your movement speed bonus as a percentage |
| [Skillchain indicator](components/skillchain.md) | `sc` | yes | whether a skillchain window is open on your target and how long it has left |

## Commands

All commands start with `//hud` (`//xivhud` also works). Verbs and component
names are not case-sensitive, and a component's alias stands in for its name
anywhere: `//hud reset tb` is `//hud reset targetbar`.

| Command | What it does |
| --- | --- |
| `//hud` or `//hud help` | print the command list |
| `//hud layout` (or `setup`) | toggle layout mode |
| `//hud list` | list every component with its state, position and scale |
| `//hud show <component> [<piece>]` | switch a component on, or one piece of it |
| `//hud hide <component> [<piece>]` | switch a component off, or one piece of it |
| `//hud reset <component>` | restore that component's settings and placement to defaults |
| `//hud reset all` | restore every component |
| `//hud slot <name>` | switch to a layout slot |
| `//hud slot list` | list your layout slots, marking the active one |
| `//hud slot create <name>` | create a new slot as a copy of the active one |
| `//hud slot delete <name>` | delete a slot (`default` and the active slot cannot be deleted) |
| `//hud copy <from> <to>` | replace character `<to>`'s configuration with character `<from>`'s |
| `//hud buffs active` | list every buff on you right now, with ids |
| `//hud buffs <component> ...` | a component's buff order and filter settings (see below) |
| `//hud draw`, `mr`, `warp`, `sneak`, `invisible` | actions on the game itself (see Action commands below) |
| `//hud retry`, `wsgate`, `delay` | settings shared by the crossbar and hotbar (see Action commands below) |
| `//hud <component> ...` | a command belonging to that component (see its page) |

**`show` and `hide` take a piece name** for components made of several
independently placed parts: `//hud hide partylist alliance2`,
`//hud show statusbar bar2`, `//hud hide targetbar subtarget`. `//hud list`
prints the piece names each component has.

**`reset` and `copy` have no undo and no confirmation step.** `reset` acts on
the active slot only; `copy` replaces every slot the destination character
has.

### Buff order and filters

The party list and the status bar both draw buff icons, and they share one
grammar for choosing which buffs are drawn and in what order. Every buff has a
priority; when there is not room for all of them, the highest-priority buffs
win. A filter list hides buffs (blacklist mode) or shows only the listed ones
(whitelist mode).

```
//hud buffs <component> [<piece>]                     what that piece draws (party list: the top of its priority order; status bar: your current buffs)
//hud buffs <component> [<piece>] list [<page>]       the full priority order, a page at a time
//hud buffs <component> [<piece>] find <text>         search buffs by name
//hud buffs <component> [<piece>] top <id|name>       move a buff to the top of the order
//hud buffs <component> [<piece>] up <id|name>        move it up one place
//hud buffs <component> [<piece>] down <id|name>      move it down one place
//hud buffs <component> [<piece>] rank <id|name> <n>  put it at position n
//hud buffs <component> [<piece>] reset               back to the shipped order
//hud buffs <component> [<piece>] filter add <id|name>
//hud buffs <component> [<piece>] filter remove <id|name>
//hud buffs <component> [<piece>] filter clear
//hud buffs <component> [<piece>] filter list
//hud buffs <component> [<piece>] filter mode blacklist|whitelist
```

A buff can be named by its id or by its name (`//hud buffs partylist top
haste`). `//hud buffs active` shows the ids of everything currently on you.
See the [party list](components/partylist.md) and [status bar](components/statusbar.md)
pages for what each one adds.

## Action commands

A few commands act on the game directly rather than on the HUD. They are the
same actions the [crossbar](components/crossbar.md) and
[hotbar](components/hotbar.md) can bind to a slot, so they work from a macro
or the console too, and their settings are shared by both bars.

| Command | What it does |
| --- | --- |
| `//hud draw` | sheathe or unsheathe, which also picks the set rotation the bars cycle through; dismounts if you are mounted |
| `//hud mr` | mount roulette: summon a random mount you own, or dismount |
| `//hud warp [all]` | warp home by the best means you have (a Warp spell, a Warp Ring, an Instant Warp, ...); `all` sends your other characters running XIVHud too |
| `//hud sneak` / `//hud invisible` | the cheapest sneak or invisible this character can manage: the spell, then Spectral Jig, then the ninjutsu, then an oil or powder |
| `//hud retry [on\|off]` | re-send a spell, ability or weaponskill the game refused as "too soon"; off by default |
| `//hud wsgate [on\|off]` | drop a weaponskill press the game would refuse (too little TP, not engaged, out of reach, or under a status that blocks weaponskills); off by default |
| `//hud wsgate range <yalms>` / `pivot <yalms>` | tune the gate's idea of melee reach |
| `//hud delay [<seconds>]` | how long a mount or warp counts down before it goes; `0` switches the countdown off |

`mr`, `warp` and a bound mount count down in chat before they act, so a
mis-press costs a few seconds rather than a trip home. Resting (`/heal`)
cancels the countdown. The crossbar page describes each of these in detail
under [Built-in actions](components/crossbar.md#built-in-actions) and
[Extras](components/crossbar.md#extras).

## Layout slots

A slot is a complete, named arrangement: every component's position, scale,
on/off state and settings. Each character starts with one slot, `default`.

```
//hud slot create events      make a new slot, copied from the current one
//hud slot events             switch to it
//hud slot list               see what you have
//hud slot default            switch back
//hud slot delete events      remove it
```
A slot name is one word of letters, digits and underscores, and cannot be
`list`, `create` or `delete`. Switch to another slot before deleting the one
you are in.


Switching slots re-reads everything, so a component's own settings - the
crossbar's bindings included - follow the slot.

## Where settings are kept

Everything lives under the addon's own folder, so backing up or moving your
setup is a matter of copying a directory:

```
Windower4/addons/XIVHud/data/<Character>/core.lua                      general settings
Windower4/addons/XIVHud/data/<Character>/<slot>/<component>/config.lua  the component's settings
Windower4/addons/XIVHud/data/<Character>/<slot>/<component>/layout.lua  its position, scale and on/off state
Windower4/addons/XIVHud/data/<Character>/<slot>/crossbar/<JOB>.lua     the crossbar's bindings for that job (the hotbar's sit beside it in hotbar/)
Windower4/addons/XIVHud/icons/                                          item icons read from the game, plus your own in icons/custom/
```

The files are plain Lua tables and can be edited in a text editor while the
game is closed (or reload the addon afterwards with `//lua reload xivhud`).
Colours are written as `{ r = , g = , b = , a = }`, each 0-255; `a` is the
opacity and may be left out, which means fully opaque. Each component's page
lists the options its `config.lua` holds. If a
file is damaged the component falls back to its defaults and says so in chat.

### General settings (`core.lua`)

| Option | Default | What it does |
| --- | --- | --- |
| `snap` | `10` | the grid, in pixels, that dragging snaps to in layout mode |
| `slot` | `"default"` | the active layout slot |
| `hideCutscene` | `true` | hide the HUD during cutscenes and the NPC conversations that lock your character |
| `retry` | off | the cast retry for the crossbar and hotbar |
| `wsgate` | off, range 4, pivot 1.3 | the weaponskill gate and its reach |
| `delay` | `5` | seconds a mount or warp counts down before it goes |

## Auto-hide

The whole HUD hides during cutscenes (unless `hideCutscene` is off), while
zoning and for a few seconds after, and while logged out. It comes back by
itself. Layout mode does not override this.
