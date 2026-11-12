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
  component settings under `data/<Character>/`: the general settings written
  at first login, the rest as you change them.
- **Layout slots.** Several named arrangements per character, switched with
  one command - one for solo play and one for events, say.
- **Copy between characters.** One command copies a character's whole
  configuration onto another.
- **Auto-hide.** The HUD hides itself during cutscenes, while zoning and while
  logged out, and comes back on its own.
- **Short names.** Every component answers to a short alias wherever its
  name is taken (`//hud show pb`).
- **Gamepad.** XIVHud can read an Xbox-style pad itself and play the crossbar
  from it, with what every button and chord does changed by command (see
  [Gamepad](gamepad.md)). It is on by default, and `//hud gamepad off`
  switches it off.

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

To update, close the game and unzip the new release over the old folder:
Windows will not replace `bin/_LuaXInput.dll` while the game has it loaded.
Your settings (`data/`),
your own art (`icons/custom/`) and the icon cache (`cache/`) are not in the zip
and survive the update.

The HUD appears once you are logged in on a character. Type `//hud` at any
time to see the command list.

## Getting started

1. Log in on a character. Every component that is on by default comes up in
   its shipped position.
2. Type `//hud layout` to enter layout mode. Every component gets a
   highlight box with its name on it - one per piece for a component made of
   several, labelled `partylist:alliance1` and the like - and draws sample
   content, so an empty widget can still be placed. The ones you have switched
   off show as a dark box marked `(hidden)` so they can be found and switched
   back on. Where boxes overlap, the one drawn later takes the mouse; a click
   that misses every box is the game's.
   - **Left-drag** a box to move it. Movement snaps to a grid; hold **CTRL**
     to move freely.
   - **Mouse wheel** over a box to scale it up or down, no smaller than a
     quarter of its size.
   - **Right-click** a box to switch that component off or on.
   - **SHIFT + right-click** switches one piece of a component that has
     several off or on: a party list, a status bar, a hotbar row, a target bar
     or a crossbar piece. On a component with one piece it is a plain
     right-click.
3. Type `//hud layout` again to leave layout mode (logging out leaves it
   too). Everything you changed is already saved, and every widget is kept
   fully on screen - a placement from a hand edit or a smaller screen is
   pulled back inside it.

The crossbar and hotbar come up empty. Type `//hud crossbar edit` or
`//hud hotbar edit`, click a slot, pick which layer, then pick an action (and
a target if it takes one); their pages explain the rest. To unload the addon,
type `//lua unload xivhud`. If the HUD does not appear at all, type `//hud`:
it reports what went wrong if the addon failed to load (see
[Troubleshooting](#troubleshooting)).

Two components take over keys while a character is loaded. The crossbar
claims `;` `'` `\` `` ` `` and `=`, and the number row `1` to `8` while a side
key or `` ` `` is held. The hotbar claims the number row `1` to `0` under CTRL
(row 1), ALT (row 2), SHIFT (row 3), CTRL+SHIFT (row 4), ALT+SHIFT (row 5) and
CTRL+ALT+SHIFT (row 6); the bare keys stay the game's, and the game's own macro
palette still fires on those chords, so leave the matching in-game macros
empty. It also changes set on CTRL+Up and CTRL+Down, which the game still sees.
The bars also take a left-click on a drawn slot or the sword, and the status
bar a click on one of its icons. If you would
rather keep those keys, switch the component off with `//hud hide crossbar`
or `//hud hide hotbar`; a hotbar row you hide gives its chord back too. Both
bars get their keys through the [keyboard map](keyboard.md), so
`//hud keyboard off` gives every one of them back.

Components can also be switched from the console: `//hud hide giltracker`,
`//hud show partylist alliance1`.

## Components

| Component | Alias | On by default | What it shows |
| --- | --- | --- | --- |
| [Crossbar](components/crossbar.md) | `cb` | yes | FFXIV's cross hotbar: sixteen slots per set, driven by held keys or a [gamepad](gamepad.md) |
| [Hotbar](components/hotbar.md) | `hb` | yes (row 1) | FFXIV's hotbar: ten slots in a row on the number keys, up to eight rows, with the same kinds of binding and the same commands as the crossbar |
| [Parameter bar](components/parambar.md) | `pb` | yes | HP, MP and TP bars with numbers, plus melee accuracy and multi-attack rows |
| [Party list](components/partylist.md) | `pl` | yes (main party) | your party (HP/MP/TP, jobs, buffs, distance) and both alliance parties (HP and MP) |
| [Target bar](components/targetbar.md) | `tb` | yes | your target's HP, name, distance and cast bar, plus smaller copies for the subtarget cursor and a focus target |
| [Status bar](components/statusbar.md) | `sb` | yes (bar 1) | your buffs and debuffs as icons with timers |
| [Experience bar](components/expbar.md) | `eb` | yes | experience, limit points or exemplar points toward the next step |
| [Equipment viewer](components/equipviewer.md) | `ev` | yes | your equipped gear as a 4x4 icon grid |
| [Gil tracker](components/giltracker.md) | `gt` | yes | your current gil |
| [Inventory tracker](components/invtracker.md) | `inv` | yes | how full each bag is, as a grid of coloured squares |
| [Speed check](components/speedcheck.md) | `spd` | yes | your movement speed bonus as a percentage |
| [Skillchain indicator](components/skillchain.md) | `sc` | yes | whether a skillchain window is open on your target and how long it has left |

## Commands

All commands start with `//hud` (`//xivhud` is registered as a second name).
Verbs and component names are not case-sensitive, and a component's alias
stands in for its name anywhere: `//hud reset tb` is `//hud reset targetbar`.
Settings are per character, so until one is loaded everything but `help`,
`list`, `copy` and `gamepad` answers `log in first - XIVHud configuration is
per character`.

| Command | What it does |
| --- | --- |
| `//hud` or `//hud help` | print the command list |
| `//hud layout` (or `setup`) | toggle layout mode |
| `//hud list` | list every component with its state, position and scale |
| `//hud show <component> [<piece>]` | switch a component on, or one piece of it |
| `//hud hide <component> [<piece>]` | switch a component off, or one piece of it |
| `//hud reset <component>` | restore that component's settings and placement to defaults (for the crossbar and hotbar, every job's bindings go too) |
| `//hud reset all` | restore every component |
| `//hud slot <name>` | switch to a layout slot |
| `//hud slot list` | list your layout slots, marking the active one |
| `//hud slot create <name>` | create a new slot as a copy of the active one |
| `//hud slot delete <name>` | delete a slot (`default` and the active slot cannot be deleted) |
| `//hud copy <from> <to>` | replace character `<to>`'s configuration with character `<from>`'s |
| `//hud buffs active` | list every buff on you right now, with ids, in the shipped priority order |
| `//hud buffs <component> ...` | a component's buff order and filter settings (see below) |
| `//hud draw`, `mr`, `warp`, `sneak`, `invisible`, `reraise` | the bars' built-in actions (see Action commands below) |
| `//hud delay [<seconds>]` | the mount and warp countdown, shared by the crossbar and hotbar; without a number it prints the current value (see Action commands below) |
| `//hud queue [on\|debug\|off]` | hold a bar press made during a cast or the moment after it, and send it when you can act; on by default. Without a word it prints the current setting (see [The action queue](#the-action-queue)) |
| `//hud queue lock [<kind> [<seconds>]]` | how long the queue waits after each kind of action |
| `//hud hidecutscene [on\|off]` | hide the HUD during cutscenes; on by default, and a change applies at once. Without a word it prints the current setting |
| `//hud gamepad [on\|off]` | the [gamepad bridge](gamepad.md): which pad it reads, or switch it on or off; on by default |
| `//hud gamepad list`, `bind`, `unbind` | what each button and chord of the pad does, changed in game (see [Gamepad](gamepad.md#commands)) |
| `//hud keyboard [on\|off]`, `list` | the [keyboard map](keyboard.md): the keys that drive the crossbar and the hotbar, handed to them the way the pad's buttons are; on by default, and off no key reaches either bar |
| `//hud config [<component>\|global]` | open the settings window, to change settings with the mouse (see below) |
| `//hud <component> ...` | a command belonging to that component (see its page) |

**`show` and `hide` take a piece name** for components made of several
independently placed parts: `//hud hide partylist alliance2`,
`//hud show statusbar bar2`, `//hud hide targetbar subtarget`. `//hud list`
prints the piece names each component has; a wrong one is answered with the
right ones, and a successful switch prints nothing. A piece and its component
are separate switches: a piece you show stays hidden while the whole component
is hidden (the command warns you), and `//hud show <component>` brings the
component back without changing which of its pieces are off.

**`reset` and `copy` have no undo and no confirmation step.** `reset` acts on
the active slot only, deletes every file in the component's folder there and
writes fresh ones; `reset all` does that for every component and leaves the
general settings (`core.lua`) alone. `copy` replaces every slot the
destination character has, and its general settings with them. It works from
character select, the destination need not exist yet, names are matched
regardless of case, and the reply counts the files copied. Only a destination
that is the character you are playing is reloaded at once; one logged in on
another client keeps its old settings in memory and writes them back over the
copy as it saves.

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
//hud buffs <component> [<piece>] filter list                 (a bare filter lists it too)
//hud buffs <component> [<piece>] filter mode blacklist|whitelist
```

A buff can be named by its id or by its whole name, in any case (`//hud buffs
partylist top haste`); a name several buffs share, such as `sleep`, is refused
with their ids listed, and a name nothing matches points you at `find`, which
searches by part of a name. The shipped order puts debuffs first, then
abilities and ordinary buffs, with system effects (food, signets,
restrictions) last; buffs it does not rank sort after everything else, by id,
and `list` prints them under a divider, twenty to a page, with a mark where
the icon cap falls. `rank` past the end lands on the last place, and `up` on
an unranked buff pulls it into the ranked order. A whitelist with nothing in
it shows nothing. `//hud buffs active` shows the ids of everything currently
on you.
The party list's buff settings belong to the main party alone, so its only
piece name here is `main`, and it adds one verb of its own,
`//hud buffs partylist active [<member>]`, for a party member's buffs. The
status bar's order is one list for all three of its bars, so its order verbs
take no piece word either; only its `filter` verb does.
`//hud statusbar partyorder on` makes the party list follow the status bar's
order. See the [party list](components/partylist.md) and
[status bar](components/statusbar.md) pages for what each one adds.

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

Every change is saved as you make it. The line under the title shows the first
line of what the matching command would have answered, including a refusal
(any further lines go to chat) - the window sets exactly what the commands
set, with the same limits, so anything you change here you can also type. A
control at its limit does nothing, and a press that slides off a control
before release does nothing either.

`global` holds the travel delay, the action queue and its waits (see
[Action commands](#action-commands)), whether the HUD hides during cutscenes,
the [gamepad bridge](gamepad.md)'s switch, unless `//hud gamepad` says the
bridge is unavailable, and the [keyboard map](keyboard.md)'s switch. The components with a page of their own are the parameter bar,
target bar, party list, status bar, equipment viewer, inventory tracker,
crossbar and hotbar; each one's page says what is on it. A number that needs a
value the steps do not land on, the buff order and filter lists, and anything
about a single action-bar slot are still typed.

- **Move it** by dragging its title bar. It reopens where you left it.
- **Close it** with `[ X ]`, or `//hud config` again; the next bare
  `//hud config` reopens it on the panel you last used.
- **Open it on one panel** with `//hud config <component>`, for example
  `//hud config global`. If the window is already open, that switches panel.

While the window is open the mouse belongs to it: a left-click or the wheel
on the window never reaches the game (a right-click does), a click anywhere
else does, and no component answers the mouse - the bars' clicks and the
status bar's hover, right-click and drag are off until it closes. Your keys
still work. Opening it closes the action bars' edit mode, which cannot be
opened again until the window is closed, and
cancels a mount or warp that is counting down, and an enchanted item's wait
(the piece stays on). It cannot be opened in layout
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
| `//hud draw` | flip the bars' weapon state, which picks the set rotation they cycle through: drawing sends nothing to the game, sheathing disengages you, and mounted it dismounts |
| `//hud mr` | mount roulette: summon a random mount you own, or dismount |
| `//hud warp [all]` | warp home by the best means you have (a Warp spell, a Warp Ring, an Instant Warp, ...); `all` sends your other characters running XIVHud too |
| `//hud sneak` / `//hud invisible` | the cheapest sneak or invisible this character can manage: the spell, then Spectral Jig, then the ninjutsu, then an oil or powder. Silenced or muted, the spells and ninjutsu are passed over |
| `//hud reraise` | the best reraise you can get right now: Reraise IV, III, II or I if you can cast it (a scholar needs Addendum: White or Enlightenment up), then a Super Reraiser, Hi-Reraiser, Reraiser or Instant Reraise from your inventory, then a Reraise Ring, Earring, Hairpin or Gorget your job can wear, equipped and waited out for you the way an enchanted item is. Refused while Reraise is already on, since the game cannot say which tier you have. No countdown. |
| `//hud delay [<seconds>]` | how long a mount or warp counts down before it goes; fractions are fine, there is no upper limit, and `0` switches the countdown off |
| `//hud queue [on\|debug\|off]` | [the action queue](#the-action-queue); without a word it prints the current setting. `debug` also writes each step to `debug.log` in the addon's folder |
| `//hud queue lock [<kind> [<seconds>]]` | how long the queue waits after each kind of action, 0 to 5 seconds in tenths. Alone it lists them all; with only a kind it prints that one |

`mr`, `warp` and a bound mount count down in chat before they act, so a
mis-press costs a few seconds rather than a trip home. A warp that first has to
equip a ring and wait for its charge waits for that instead, and never for less
than the countdown. Getting off a mount
(`mr` or `draw` while mounted) and `draw` itself never wait. Resting (`/heal`)
cancels the countdown. The crossbar page describes each of these in detail
under [Built-in actions](components/crossbar.md#built-in-actions) and
[Extras](components/crossbar.md#extras).

### The action queue

After a spell, a weaponskill, a job ability, an item or a ranged attack the
game refuses your next action for a moment, and a press made in that moment is
lost. With the queue on, which is the default, a crossbar or hotbar press made
during a cast or that moment is held, and goes by itself as soon as you can
act, as in FFXIV. A press made while you are free goes at once. With the queue
off, every press goes at once and the game decides.

- **What is held:** spells, job abilities, pet commands, weaponskills, items
  and ranged attacks. A `sneak`, `invisible` or `reraise` slot picks its best
  way when you press it and holds that, unless the best way is gear to put on,
  which has a wait of its own. Every other kind of slot goes at once: chat and
  Windower commands, game screens, job changes, mounts, warps, `draw` and
  enchanted gear.
- **One press.** Only one press is held, across both bars, and a newer one
  replaces it. A held press is sent once, and not again if the game refuses
  it. Nothing is said in chat when a press is held or dropped.
- **Pressing again.** While the game has yet to answer a press, pressing the
  same action at the same target again does nothing, so mashing a slot cannot
  spend a weaponskill or an item twice.
- **Recasts.** A held press waits on its own recast for two seconds at most: a
  spell, job ability or pet command whose recast ends within two seconds of when
  you could act is held until it ends, and one further off is dropped. A press
  made while you are locked out after an action is held if its recast ends no
  more than two seconds after the lockout; one made during a cast, only if its
  recast has two seconds or less to run. Otherwise it goes out at once, as does one
  made while nothing is going on, recast or not. While a held press waits on its
  recast, a newer press replaces it, as during a cast. Stratagems, Quick Draw and Ready have charges, so their recast
  does not count.
- **Weaponskills.** A weaponskill you have under 1000 TP for does nothing at
  all, not even the game's usual message, and one held is dropped if the TP is
  gone when you could act.
- **Targets.** A held press aimed at `<t>` or `<bt>` stays on the target you
  had when you pressed, and with nothing targeted it is not held. A slot bound
  with no target takes whatever the game gives it when it goes, and `<me>` and
  `<pet>` are held as they are. `<ft>`, party targets and the other tokens are
  not held and go at once.
- **Cursor slots.** A slot that opens a cursor (`<st>`, `<stpc>` and the like)
  is decided when you press OK rather than when you press the slot, so you can
  pick your target during a cast and press OK whenever you like. OK is then
  judged as a press is: a weaponskill under 1000 TP sends nothing, an action
  whose recast outlasts the lockout by more than two seconds goes at once, and
  otherwise it is held or goes
  at once as the queue stands. Pressing another cursor slot while the arrow is
  up sends nothing and only changes what OK will cast. Under an arrow XIVHud
  did not raise (a macro's), a cursor slot does nothing at all, and OK still
  casts the macro's spell. GearSwap's `pretarget` does not run for such a slot.
- **Macros and typed commands** are not held, but they do count towards the
  wait, as does anything another addon sends. A press made before the game has
  answered the last one is held too.
- **What drops a held press:** zoning, dying, changing job or logging out; a
  cutscene that hides the HUD; opening `//hud layout`, `//hud config` or edit
  mode; anything that reloads a bar - a reset, a slot switch, a copy, a login;
  switching the queue off or unloading the addon; and 30 seconds passing, held
  or waiting for a ranged attack or an unknown action to end. A press made
  while `//hud config` is open goes at once; in layout or edit mode, or while
  the HUD is hidden, the bars fire nothing anyway.
- **Lag.** The game tells the queue when a cast starts and when it finishes,
  and lag can lose either message. If the finish never comes, a spell counts
  as finished at its cast time plus 0.4 seconds, a weaponskill after 1.2 seconds
  and an item at its cast time plus 1 second; the wait for that kind then runs
  and a held press goes. If the start is lost, a spell you sent waits for an
  answer as long as its cast time plus 0.4 seconds, so its finish still starts
  the wait. A spell the server drops with no answer at all holds the bar that
  long. A cast slowed past these times by a debuff can let a held press go
  early, and the game then refuses it.

If you use Selindrile's GearSwap files, leave their MiniQueue off.

The wait after each kind of action is its own setting, read when that action
finishes:

| Kind | Shipped wait | After |
| --- | --- | --- |
| `spell` | 2.7 seconds | a spell |
| `weaponskill` | 2.4 seconds | a weaponskill, or your own monster skill in Monstrosity |
| `ability` | 0.5 seconds | a job ability |
| `item` | 1 second | an item |
| `ranged` | 1 second | a ranged attack; an estimate, since nobody has measured this one |
| `interrupted` | 2.7 seconds | a spell, weaponskill, item or ranged attack that was interrupted |

A wait you set yourself is kept in `core.lua` (below), and stays yours even if
it equals the shipped one. To follow the shipped wait again, remove that kind's
entry from `queue_locks` with the game closed.

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

A slot name is one word of letters, digits and underscores, is not
case-sensitive (it is stored in lower case), and cannot be `list`, `create` or
`delete`. `create` writes the active slot to disk first and does not switch to
the new one; switch to another slot before deleting the one you are in. A
deleted slot's empty folders stay behind, and are neither listed nor in the
way of reusing the name. A folder you make yourself under `data/<Character>/`
counts as a slot once it holds a component folder with a file in it.

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
Windower4/addons/XIVHud/data/<Character>/<slot>/crossbar/SHARED.lua    the bindings of the sets marked shared across jobs
Windower4/addons/XIVHud/data/gamepad.lua                                the gamepad map, one for every character
Windower4/addons/XIVHud/data/keyboard.lua                               the keyboard map, one for every character
Windower4/addons/XIVHud/cache/items/                                    item icons read from the game (a cache: delete it only with the addon unloaded)
Windower4/addons/XIVHud/cache/packets/<Character>/                      the last character-stats packet per job, for the experience bar and the binder's subjob level cap (a cache)
Windower4/addons/XIVHud/icons/custom/                                   your own crossbar and hotbar art
```

The files are plain Lua tables (`return { ... }`) and can be edited in a text
editor while the game is closed (or reload the addon afterwards with `//lua
reload xivhud`). A key the file leaves out keeps its shipped value, and a
shipped default that changes later does not replace a value already in your
file. Colours are written as `{ r = , g = , b = , a = }`, each 0-255; `a` is
the opacity, a colour written without one keeps its shipped opacity, and some
colours take none. Each component's page lists the options its `config.lua`
holds.

A component's `config.lua` is written when it saves a setting, when it is
reset, and when a slot is created, so one that has no setting command - the
gil tracker, speed check, experience bar and skillchain indicator - has none
until you reset it. To change their options, create the file yourself, holding
just the keys you want (a reset writes every shipped value into it, after
which later shipped defaults no longer reach it).

`layout.lua` is `{ pos = { x = , y = }, scale = , visible = }`, or
`{ anchors = { <piece> = { pos = , scale = , visible = } }, visible = }` for
a component with several pieces. `visible` must be exactly `true` to count as
on; a piece is on unless its own `visible` is `false`; the scale cannot go
below 0.25; and a position or scale that is not a number falls back to the
shipped placement. If a file cannot be read, chat says
so and the component runs on its defaults; the next setting it saves overwrites
the broken file (see [Troubleshooting](#troubleshooting)).

### General settings (`core.lua`)

| Option | Default | What it does |
| --- | --- | --- |
| `snap` | `10` | the grid, in pixels, that dragging snaps to in layout mode; `0` switches the grid off. File-only |
| `slot` | `"default"` | the active layout slot |
| `hideCutscene` | `true` | hide the HUD during cutscenes and the NPC conversations that lock your character (`//hud hidecutscene on\|off`) |
| `config_pos` | centred | where you last dragged the settings window to |
| `delay` | `5` | seconds a mount or warp counts down before it goes |
| `queue` | `"on"` | the action queue: `"off"`, `"on"` or `"debug"` (`//hud queue`) |
| `queue_locks` | none | your own queue waits, by kind (`//hud queue lock`); a kind not listed uses the shipped length |

## Auto-hide

The whole HUD hides during cutscenes (unless you turn that off with
`//hud hidecutscene off`), while
zoning and for three seconds after, and while logged out. It comes back by
itself. Layout mode does not override this.

## Troubleshooting

Everything XIVHud says in chat starts with `[XIVHud]`. When it loads it says
`loaded - type //hud for commands`.

**Nothing appears, or `//hud` says `did not load`.** The addon loads in steps
and stops at the first that fails; `//hud` then answers `did not load - <step>:
<error>` and nothing is drawn. `load.log`, beside `XIVHud.lua`, is rewritten on
every load and records each step, so its last line is the last thing that ran.
Send that file with a report.

**Bisecting a crash.** An empty file named `safe_mode` beside `XIVHud.lua`
makes the addon load its framework and commands and nothing else: no component,
no drawing, none of the action commands. Nothing in chat says it is on - only
`load.log` does - and `//hud list` answers `no components registered`. Delete
the file to go back.

**`N texture(s) are missing from this install`.** Some of the addon's own art
is not where it should be. Re-copy every file and folder from the release zip
(the chat line says `src/`, which is the same folder in the repository).

**`the party list is off: Windower's resource or packet library did not load`.**
Windower's own `resources` or `packets` library failed, and more than the party
list goes with it: the gil tracker, equipment viewer, experience bar and
inventory tracker are not loaded, the status bar draws no timers, the target
bar has no cast bar or Treasure Hunter level, the parameter bar's accuracy and
multi-attack rows never count, the skillchain indicator never draws, the bars' slots show no
recast arcs, costs, icons or counts, their weapon layers never come up (so
`bind ... ws` needs `context=wpn:`), their binder offers only General and
Open, mount roulette and mount slots do nothing, `warp` finds no items, and
the action queue is off whatever `core.lua` says. The line under it is the
library's own error. A failure of Windower's `extdata` library is quieter -
only `load.log` records it - and costs `warp` its item rungs and enchanted gear
its charge readings.

**`could not parse <file> ... (using defaults)`** (or `could not read`,
`ignoring`, `could not merge`). A settings file under `data/` is broken, usually
from a hand edit. The component runs on its defaults, in memory only: the next
setting it saves overwrites the file. A broken `core.lua` puts you on the
`default` slot with every general setting at its default; a broken bar
bindings file loads as no bindings, and the next bind writes a file holding
only the new one, so the old bindings are gone. Fix the file with the game
closed, or `//hud reset <component>` to start it over. An empty file is read
as absent, silently.

**`could not write <file>`.** A settings file could not be saved, usually
because a folder under `data/` could not be created or the addon folder is
read-only. The HUD carries on, but the change is lost on the next reload; check
that Windower can write to `addons/XIVHud/data/`.

**`error in the <name> handler: ...`.** An error inside the addon; it is said
when the message changes, not every frame. After five errors in one handler
over the session chat says `the <name> handler has been disabled after 5
failures - '//lua reload xivhud' to try again` and that part of the addon
stops: a disabled mouse or keyboard handler hands your input back to the game,
a disabled `prerender` handler freezes the whole HUD, a disabled `command`
handler leaves `//hud` silent, and a disabled `gamepad` handler stops the pad,
leaving any key it held down until the game next loses focus. Reload to try again, and report the message.

**`item icons are not being read: the game's item data has changed`.** A game
update has moved the item icons and XIVHud needs an update. It applies to the
equipment viewer and both action bars, which share one icon cache; the
[equipment viewer](components/equipviewer.md) page has `icons probe` and the
rest.

**The gamepad does nothing.** `//hud gamepad` says why; the
[gamepad page](gamepad.md#troubleshooting) lists its answers.

**`crossbar: DIK <n> is bound to more than one thing`.** A hand-edited key map
in the crossbar's `config.lua` gives one key two jobs; the first keeps it.

**A press the action queue dropped or held.** `//hud queue debug` writes every
step to `debug.log` beside `XIVHud.lua`, appended and never trimmed, so switch
it back to `on` and delete the file when you are done.

**Two clients on one addon folder** share these files: `load.log` holds only
the last client to load, and both write to `debug.log` with nothing to tell
their lines apart.
