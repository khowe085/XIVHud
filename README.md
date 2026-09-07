# XIVHud

A Final Fantasy XIV style HUD for Final Fantasy XI, as a
[Windower 4](https://www.windower.net/) addon.

## Description

XIVHud replaces pieces of FFXI's on-screen display with widgets drawn the way
FFXIV draws them: a parameter bar, a party list, a target bar, a cross hotbar
driven by held keys or a controller, a keyboard hotbar, a status display
with timers, an experience bar, a skillchain indicator, and small trackers
for gil, inventory, equipment and movement speed. Every widget is switched on
or off, moved and resized in an in-game layout mode, and every character
keeps its own arrangement.

**Two things you should know before using or reading this project.**

- **It is built on other people's work.** Almost every component is a
  re-implementation of an existing Windower addon, and much of the art is
  redistributed from those addons. The party list is XivParty's; the parameter
  bar is XIVBar's; the cross hotbar is xivcrossbar's and xivhotbar's; the
  equipment viewer, gil tracker, inventory tracker, target bar, experience bar
  and speed check each come from a Windower addon of the same purpose. What
  XIVHud adds is what makes them one HUD: shared placement,
  per-character settings, layout slots, and a common command line. The
  [Credits](#credits) section at the end names every project, and each
  directory that carries borrowed code or art carries that project's licence
  beside it.
- **It was written with AI.** The code, the tests and the documentation were
  produced by an AI assistant (Anthropic's Claude, through Claude Code),
  working from the author's direction, with the author reviewing the results
  and testing them in a live game client. If that matters to how you judge or
  use the code, you now know.

Both are stated here so there is no misunderstanding about how this project
came to be.

## Installation

1. Download the latest `XIVHud-<version>.zip` from the
   [Releases](https://github.com/khowe085/XIVHud/releases) page.
2. Unzip it into your Windower `addons` folder, so that
   `Windower4/addons/XIVHud/XIVHud.lua` exists.
3. In game, type `//lua load xivhud`. To load it automatically, add
   `lua load xivhud` to `Windower4/scripts/init.txt`.
4. Type `//hud layout` to arrange the HUD: drag to move, mouse wheel to
   resize, right-click to switch a widget off or on. Type it again to finish.

The [wiki home page](wiki/Home.md) has the full walkthrough, the command list
and where settings are stored.

## Components

| Component | Alias | What it shows | Wiki |
| --- | --- | --- | --- |
| Crossbar | `cb` | FFXIV's cross hotbar: sixteen slots per set, eight sets, held-key or controller driven, with a mouse binder | [crossbar](wiki/components/crossbar.md) |
| Hotbar | `hb` | FFXIV's hotbar: ten slots in a row on the number keys, up to eight rows, with the same kinds of binding and the same commands as the crossbar | [hotbar](wiki/components/hotbar.md) |
| Parameter bar | `pb` | HP, MP and TP bars with numbers | [parambar](wiki/components/parambar.md) |
| Party list | `pl` | your party and both alliance parties: HP/MP/TP, jobs, buffs, distance | [partylist](wiki/components/partylist.md) |
| Target bar | `tb` | your target's HP, name, distance, claim colour and cast bar, with a second smaller bar for the subtarget cursor | [targetbar](wiki/components/targetbar.md) |
| Status bar | `sb` | your buffs and debuffs as icons with timers, on up to three bars | [statusbar](wiki/components/statusbar.md) |
| Experience bar | `eb` | experience, limit points or exemplar points toward the next step | [expbar](wiki/components/expbar.md) |
| Equipment viewer | `ev` | your equipped gear as a 4x4 icon grid | [equipviewer](wiki/components/equipviewer.md) |
| Gil tracker | `gt` | your current gil | [giltracker](wiki/components/giltracker.md) |
| Inventory tracker | `inv` | how full each bag is, as coloured squares | [invtracker](wiki/components/invtracker.md) |
| Speed check | `spd` | your movement speed bonus as a percentage | [speedcheck](wiki/components/speedcheck.md) |
| Skillchain indicator | `sc` | whether a skillchain window is open on your target and how long it has left | [skillchain](wiki/components/skillchain.md) |

## Commands

Everything is under `//hud`. The most used:

```
//hud                          command list
//hud layout                   toggle layout mode
//hud list                     every component, its state, position and scale
//hud show|hide <component>    switch one on or off
//hud reset <component|all>    back to defaults
//hud slot <name>              switch to a named layout
//hud draw | mr | warp | sneak | invisible   act on the game (the same actions a bar slot can hold)
//hud retry | wsgate | delay   settings shared by the crossbar and hotbar
//hud <component> ...          that component's own settings
```

A component's alias stands in for its name anywhere (`//hud hide gt`). See
the [wiki](wiki/Home.md#commands) for the full set, including layout slots,
copying settings between characters, and the buff order and filter commands.

## Development

The addon's source is in [src/](src/); a GitHub Action packages it into the
release zip. Logic is kept apart from the Windower API so it can be tested
outside the game with [busted](https://lunarmodules.github.io/busted/):

```
busted            run the tests
luacheck .        lint
stylua --check .  formatting
```

Nothing here can run the addon itself. That needs Windower and a live FFXI
client on Windows. [CLAUDE.md](CLAUDE.md) describes the architecture and the
platform rules in detail.

## License

XIVHud's own code is released under the BSD 3-clause licence, © 2026
Azureblood2; the notice is at the top of every source file. Borrowed code and
art keep their original licences, listed below and reproduced in the
`LICENSE.txt` beside each.

## Credits

XIVHud would not exist without these projects. Each is used under its own
licence.

| Project | Author | Licence | What XIVHud takes from it |
| --- | --- | --- | --- |
| [XivParty](https://github.com/Tylas11/XivParty) | Tylas | BSD 3-clause | the party list: its geometry, job and role tables and buff priority order; the `xiv` art, job icons and buff icons used by the party list, target bar, status bar, experience bar and speed check |
| [XIVBar](https://github.com/Windower/Lua/tree/live/addons/xivbar) | SirEdeonX | BSD 3-clause | the parameter bar and its theme art |
| [xivcrossbar](https://github.com/AliekberFFXI/xivcrossbar) | AliekberFFXI | MIT | the cross hotbar: its design, the icon pack and UI art, the ninja tool, master tool and Quick Draw card tables, the stratagem list |
| xivhotbar | SirEdeonX | BSD 3-clause | the hotbar xivcrossbar grew from; its cross geometry and drawing constants, and the per-file notices xivcrossbar inherits |
| [xivcrossbar (khowe085 fork)](https://github.com/khowe085/xivcrossbar) | AliekberFFXI, SirEdeonX | MIT / BSD 3-clause | the stratagem charge counter |
| [XIVhotbar2 Petit Trois Edition](https://github.com/WGINC/XIVhotbar2-Petit_Trois_Edition) | WG Incorporated | BSD 3-clause | the radial recast sweep and the cooldown frames |
| SkillChains | Ivaar | BSD 3-clause | the skillchain property and chain-resolution tables and window logic |
| Mount Roulette | Dean James (Xurion of Bismarck) | BSD 3-clause | the mount roulette |
| MyHome (Icydeath/ffxi-addons) | from20020516 | BSD 3-clause | the automatic warp ladder |
| [EquipViewer](https://github.com/Windower/Lua/tree/dev/addons/equipviewer) | Rubenator, Tako (base icon extraction credited to Trv) | BSD 3-clause | the equipment viewer, the item icon extractor shared with the crossbar, the encumbrance art |
| [giltracker](https://github.com/Windower/Lua/tree/live/addons/giltracker) | sylandro | BSD 3-clause | the gil tracker and the gil icon |
| invtracker | sylandro | BSD 3-clause | the inventory tracker |
| [enemybar](https://github.com/Windower/Lua/tree/dev/addons/enemybar) | Mike McKee | BSD 3-clause | the target bar's claim colouring |
| [enemybar2](https://github.com/AkadenTK/enemybar2) | AkadenTK | see project | the target bar's cast tracking and its subtarget bar |
| [DistancePlus](https://github.com/Windower/Lua/tree/dev/addons/DistancePlus) | Sammeh of Quetzalcoatl | BSD 3-clause | the target bar's range bands |
| SpeedChecker | Windower | BSD 3-clause | the speed check |
| pointwatch | Byrthnoth | BSD 3-clause | the experience bar: which packets and messages carry experience, limit and exemplar points |
| [barfiller](https://github.com/Windower/Lua/tree/live/addons/barfiller) | Morath86 | BSD 3-clause | the experience bar's art and its bar |
| [Windower](https://github.com/Windower/Lua) | Windower | BSD 3-clause | the platform, its Lua libraries, and the generated resources the buff order is derived from |

Final Fantasy XI and Final Fantasy XIV are the property of Square Enix. The
icon artwork derived from the game remains theirs; the notices in
`src/assets/` say so.
