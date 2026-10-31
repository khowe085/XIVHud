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

To update, unzip the new release over the old folder. Your settings (`data/`),
your own art (`icons/custom/`) and the icon cache (`cache/`) are not in the zip
and survive the update.

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
claims `;` `'` `\` `` ` `` and `=`, and the hotbar the number row `1` to `0`
under CTRL, ALT and SHIFT (the bare keys stay the game's). If you would
rather keep those keys, switch the component off with `//hud hide crossbar`
or `//hud hide hotbar`; a hotbar row you hide gives its chord back too.

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
| `//hud draw`, `mr`, `warp`, `sneak`, `invisible`, `reraise` | actions on the game itself (see Action commands below) |
| `//hud delay` | setting shared by the crossbar and hotbar (see Action commands below) |
| `//hud queue [on\|debug\|off]` | hold a bar press made during a cast, and send it when you can act (see Action commands below); off by default |
| `//hud hidecutscene [on\|off]` | hide the HUD during cutscenes; on by default |
| `//hud config [<component>]` | open the settings window, to change settings with the mouse (see below) |
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

## Settings window

`//hud config` opens a window for changing settings with the mouse instead of
typing them. Down its left side is a menu: `global`, for the settings that
belong to no one component, and one entry for each component that has
settings there. Click an entry to see its settings on the right.

| Control | How it works |
| --- | --- |
| `[ on ]` / `[ off ]` | a switch: click it to flip it |
| `[-] 5 [+]` | a number: `[-]` steps it down, `[+]` steps it up, one step per click |
| `[<] magic [>]` | one of a list: the arrows step through the choices and wrap round |

A component with more settings than one page holds splits them across tabs
along the top; click a tab to see its page.

Every change is saved as you make it. The line under the title shows what the
matching command would have answered, including a refusal - the window sets
exactly what the commands set, with the same limits, so anything you change
here you can also type.

`global` holds the travel delay and the action queue (see
[Action commands](#action-commands)) and whether the HUD hides during cutscenes. The components with a page of their own are the
parameter bar, target bar, party list, status bar, equipment viewer, inventory
tracker, crossbar and hotbar; each one's page says what is on it. A number that
needs a value the steps do not land on, the buff order and filter lists, and
anything about a single action-bar slot are still typed.

- **Move it** by dragging its title bar. It reopens where you left it.
- **Close it** with `[ X ]`, or `//hud config` again.
- **Open it on one panel** with `//hud config <component>`, for example
  `//hud config global`. If the window is already open, that switches panel.

While the window is open the mouse belongs to it: a click on the window never
reaches the game, a click anywhere else does, and the action bars do not
answer the mouse. Your keys still work. Opening it closes the action bars'
edit mode, which cannot be opened again until the window is closed, and
cancels a mount or warp that is counting down. It cannot be opened in layout
mode, and entering layout mode closes it. Like the rest of
the HUD it hides during a cutscene and comes back afterwards.

Position, size and on/off are not in this window: those are layout mode's
(`//hud layout`). Neither are an action bar's slots, which are edited in the
bars' own edit mode (`//hud crossbar edit`, on the
[crossbar](components/crossbar.md) page).

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
| `//hud sneak` / `//hud invisible` | the cheapest sneak or invisible this character can manage: the spell, then Spectral Jig, then the ninjutsu, then an oil or powder. Silenced or muted, the spells and ninjutsu are passed over |
| `//hud reraise` | the best reraise you can get right now: Reraise IV, III, II or I if you can cast it (a scholar needs Addendum: White or Enlightenment up), then a Super Reraiser, Hi-Reraiser, Reraiser or Instant Reraise from your inventory, then a Reraise Ring, Earring, Hairpin or Gorget your job can wear, equipped and waited out for you the way an enchanted item is. Refused while Reraise is already on, since the game cannot say which tier you have. No countdown. |
| `//hud delay [<seconds>]` | how long a mount or warp counts down before it goes; `0` switches the countdown off |
| `//hud queue [on\|debug\|off]` | the action queue, below; `debug` also says each step in chat and adds it to `debug.log` in the addon's folder |

**The action queue.** After a spell, a weapon skill or a job ability the game
refuses your next action for a moment, and a press made in that moment is lost.
With the queue on, a crossbar or hotbar press made during a cast or that moment
is held, and goes by itself as soon as you can act, as in FFXIV. Only one press
is held, and a newer one replaces it. A press made while you are free goes at
once. A held press is sent once, and is never waiting on a recast: if the action
is still on its own recast when you could act, it is dropped. A held press aimed
at `<t>` or `<bt>` stays on the target you had when you pressed, and a slot bound
with no target takes whatever the game gives it when it goes; `<st>`, `<ft>` and
party targets are not held and go at once, as they always did, and so do the
`sneak`, `invisible` and `reraise` slots. Macros and
typed commands are not held, but they do count towards the wait. If you use
Selindrile's GearSwap files, leave their MiniQueue off.

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
Windower4/addons/XIVHud/cache/items/                                    item icons read from the game (a cache: delete it only with the addon unloaded)
Windower4/addons/XIVHud/icons/custom/                                   your own crossbar and hotbar art
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
| `hideCutscene` | `true` | hide the HUD during cutscenes and the NPC conversations that lock your character (`//hud hidecutscene on\|off`) |
| `config_pos` | centred | where you last dragged the settings window to |
| `delay` | `5` | seconds a mount or warp counts down before it goes |
| `queue` | `"off"` | the action queue: `"off"`, `"on"` or `"debug"` (`//hud queue`) |

## Auto-hide

The whole HUD hides during cutscenes (unless you turn that off with
`//hud hidecutscene off`), while
zoning and for a few seconds after, and while logged out. It comes back by
itself. Layout mode does not override this.
