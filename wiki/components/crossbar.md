# Crossbar

Alias: `cb`

## Description

FFXIV's Cross Hotbar, for FFXI. A bar of sixteen slots sits on your HUD,
arranged as four-slot crosses — D-pad clusters and face-button clusters, eight
slots on its **left side** and eight on its **right**. Each slot shows what is
bound to it, whether it is ready, and what it costs.

Each side has two states. Hold one of two **side keys** and that side is
**active**: a panel is drawn behind it, and its eight buttons fire what they
show. Let go and it is inactive again.

Those sixteen slots are a **set**, and you have eight sets. Tapping the
**switch key** moves to the next one; holding it and pressing a button jumps
straight to a numbered set; tapping it while the **layer key** is held draws
or sheathes your weapon.

Two more bars exist beyond that. The **WXHB** is a second sixteen slots,
reached by holding the **layer key** with a side — you can keep it on screen
permanently or have it appear only when you reach for it. **Expanded Hold** is
a third, though only eight slots rather than sixteen: hold **both** side keys
at once and it takes over the screen from the other two for as long as you do,
with which of the two Expanded Hold views you get depending on which side key
you pressed first. Both point at whatever set and side you tell them to, so
they are extra bars rather than extra storage.

Sets can be **shared** across every job or kept to one, and individual slots
can be overridden for a particular subjob.

Slots can also change themselves while a buff is up. A Scholar can put
**Accession** on a slot for when Light Arts is active and **Manifestation** on
that same slot for Dark Arts: one button, the right stratagem under each art,
with nothing to switch by hand.

The crossbar shares its binder and its commands with the
[hotbar](hotbar.md), a plain row of ten slots driven by the number keys. Each
keeps its own bindings; what you learn on one applies to the other.

Bindings are made with the mouse: `//hud crossbar edit` opens a binder, you
click a slot, pick which layer you are editing, and pick an action.

Everything is driven by keys, so **a controller is optional**. Pad support is
a Steam Input layout that presses those keys for you; from a keyboard you
press them yourself.

## Features

- **Sixteen slots per set, eight sets**, drawn as two four-button crosses.
  Hold a side key and that side's eight buttons are live.
- **Two more bars**: the WXHB (another sixteen slots, held up with the layer
  key) and Expanded Hold (eight more, both side keys at once).
- **Bind anything**: spells, job abilities, weaponskills, items, enchanted
  gear, pet commands, mounts, ranged attack, chat lines, Windower commands,
  and built-ins for drawing your weapon, mount roulette, warping home, sneak,
  invisible and reraise.
- **A mouse binder** (`//hud crossbar edit`): click a slot, pick a layer, pick
  an action from what your character actually knows.
- **Layers**: a job's own base bindings, overrides for a particular subjob,
  overrides for the weapon class in your main hand, buff contexts that swap
  slots in while a buff is up (Light Arts, Addendum, Unbridled Learning), and
  sets shared by every job.
- **Rotations**: each set can belong to a drawn-weapon rotation, a sheathed
  one, both or neither, and the switch key cycles the one that applies.
- **On the slots**: recast arcs, MP and TP costs, item and ninja tool counts,
  stratagem counts, and the skillchain property each weaponskill would make
  while a chain is open.
- **Optional extras**: a countdown before travel actions - a setting shared
  with the hotbar. A left-click on the sword draws or sheathes.
- **Controller friendly**: everything is a key, so a Steam Input layout that
  presses those keys gives you a full pad cross hotbar.

## Configuration options

Bindings are stored per job in the addon's data folder (`<JOB>.lua` and
`SHARED.lua`) and are edited with the binder or the commands below.
`config.lua` beside them holds the settings; the ones marked with a
command are also set from the console.

| Option | Default | What it does |
| --- | --- | --- |
| `always_show_wxhb` | `false` | keep the WXHB on screen at rest (`wxhb on\|off`) |
| `views.wxhb_left` / `wxhb_right` | set 2, left / right | which set and side each WXHB half shows (`view`) |
| `views.expanded_lr` / `expanded_rl` | set 3, left / right | the same for the two Expanded Hold orders (`view`) |
| `set_flags[n].shared` | `false` | set `n` is shared by every job (`share`) |
| `set_flags[n].cycle.drawn` / `.sheathed` | `true` / `true` | which rotations set `n` belongs to (`cycle`) |
| `hide.empty_slots` | `false` | leave empty slots undrawn |
| `hide.action_name` | `false` | hide the name under each slot |
| `hide.cost` | `false` | hide MP and TP costs |
| `hide.recast_animation` | `false` | hide the recast arc |
| `hide.recast_text` | `false` | hide the recast countdown text |
| `hide.skillchain_icon` | `false` | do not swap in skillchain property icons |
| `slot_spacing` | `6` | pixels between slots |
| `bar_spacing` | `56` | pixels between the two crosses |
| `slot_alpha` | `100` | opacity of a slot's backing |
| `button_bg_alpha` | `150` | opacity of the panel behind an active side |
| `disabled_alpha` | `100` | opacity of an action you cannot use right now |
| `feedback.alpha` / `speed` | `150` / `30` | the flash when a slot fires |
| `font` / `font_size` | `"sans-serif"` / `7` | the slot label font |
| `text_offset.x` / `.y` | `0` / `0` | nudge the labels |
| `text_color` / `text_stroke` | white / dark, width 2 | label colour and outline |
| `mp_cost_color` / `tp_cost_color` | pink / yellow | the cost text colours |
| `binder_pos` | none | where you last left the binder window; written by the binder, not by hand |
| `input.*` | see below | the keys the bar reads, as DirectInput key codes |

The travel countdown is a setting
shared with the [hotbar](hotbar.md): `//hud delay`, listed
on the [home page](../Home.md#action-commands).

The default keys (`input`):

| Setting | Key | Code |
| --- | --- | --- |
| `xhb_left` | `;` | 39 |
| `xhb_right` | `'` | 40 |
| `w_layer` | `\` | 43 |
| `set_switch` | `` ` `` | 41 |
| `slot_keys` | `1`-`8` | 2-9 |
| `shortcuts` | `=` (opens the binder while a side is held) | 13 |

The keys are not changed by command. To use different ones, edit the codes in
`config.lua` (they are DirectInput scan codes; a search for "DIK scan codes"
finds the table) and reload the addon.

The bar is placed in `//hud layout` as five pieces: `main` (the XHB),
`wxhb_left`, `wxhb_right`, `set` (the active set label) and `weapon` (the
drawn sword). Each can be moved and scaled on its own, and
`//hud hide crossbar <piece>` switches one off.

## Commands

All commands are `//hud crossbar …`. Verbs and names are case-insensitive.
`cb` is the crossbar's short name and stands in for `crossbar` anywhere it is
taken: `//hud cb set 3`, `//hud show cb`, `//hud reset cb`.

The settings that are not about one slot - which sets are shared, which
rotation each set is in, where the WXHB and Expanded Hold views point, and
whether the WXHB always shows - can also be changed with the mouse:
`//hud config crossbar` opens the [settings window](../Home.md#settings-window)
on this component, in three tabs: `sets` (each set's shared switch and
rotation), `views` (the four views) and `general` (Always show WXHB). Slots
themselves are edited in edit mode, not there.

**An address is one word**: `<set><L|R><slot>`, so `1L1` is set 1, left side,
slot 1, and `2R8` is set 2, right side, slot 8. To work on a layer other than
the job base, four verbs — `bind`, `unbind`, `alias` and `icon` — take
`context=`: `context=sub:whm`, `context=wpn:great-katana`,
`context=buf:light-arts` (below).

You may type the side in either case.

Slots are `1`–`8`, numbered clockwise from the top of each cluster — the
right-hand cross is slots 1–4 and the left-hand cross 5–8.

### Everyday

| Command | What it does |
| --- | --- |
| `//hud crossbar` | report the current job, the XHB's active set and weapon state, where each view points, and the weapon class in your main hand |
| `//hud crossbar help` | list every command |
| `//hud crossbar edit` | toggle the mouse binder, on the hotbar as well |
| `//hud crossbar set <1-8>` | switch the XHB's active set |
| `//hud crossbar cycle` | advance the XHB to the next set in the rotation |
| `//hud crossbar cycle back` | step the XHB back to the previous set in the rotation |
| `//hud crossbar list [<set>]` | list what is bound on this job, layer by layer, marking the live layer where a slot has more than one |

### Binding

| Command | What it does |
| --- | --- |
| `//hud crossbar bind <address> <type> [<action>] [<target>] [alias=<name>] [icon=<name>] [context=<layer>]` | bind a slot, labelling it in the same command if you want |
| `//hud crossbar unbind <address> [context=<layer>]` | clear a slot in one layer — the one `context=` names, or the job base without it |
| `//hud crossbar alias <address> [<name>] [context=<layer>]` | change the label under a slot — omit `<name>` to clear it |
| `//hud crossbar icon <address> [<icon>] [context=<layer>]` | change a slot's icon — omit `<icon>` to clear it |
| `//hud crossbar swap <address> <address>` | swap two slots, everything about them — every layer at once, so it takes no `context=` |
| `//hud crossbar copy <JOB>` | replace this job's bindings with another job's |

**`<type>`** says what kind of thing you are binding, and decides what the
rest of the line means:

| `<type>` | `<action>` is | Example |
| --- | --- | --- |
| `ma` | a spell — including trusts and blue magic | `bind 1L1 ma "Cure IV" t` |
| `ja` | a job ability — a subjob's on its subjob layer or under a buff context (below) | `bind 1L2 ja "Divine Seal"` |
| `ws` | a weaponskill — on a weapon layer only (below) | `bind 1R1 ws "Savage Blade" t` |
| `item` | a usable item | `bind 2L1 item "Echo Drops" me` |
| `enchanteditem` | enchanted gear — equips it, waits out the warmup, uses it | `bind 2L2 enchanteditem "Vocation Ring"` |
| `pet` | a pet command | `bind 2R1 pet "Fight" t` |
| `mount` | one specific mount — counts down before it summons, like `mr` | `bind 3L1 mount "Chocobo"` |
| `ra` | *nothing* — ranged attack takes a target only | `bind 1R4 ra t` |
| `ct` | a chat command, without its slash | `bind 4L1 ct "sea all linkshell"` |
| `ex` | a Windower command, run as typed | `bind 4L2 ex "exec pull.txt"` |
| `open` | the name of a game screen | `bind 5L1 open map` |
| `jc` | a main/sub job pair — needs the JobChange addon (see Built-ins) | `bind 5L2 jc WAR/BLM` |
| `draw` | *nothing* — sheathe / unsheathe | `bind 1L5 draw` |
| `mr` | *nothing* — mount roulette | `bind 3L2 mr` |
| `warp` | *nothing* — best available warp | `bind 6L1 warp` |
| `sneak` | *nothing* — the sneak ladder (see Built-in actions) | `bind 6L2 sneak` |
| `invisible` | *nothing* — the invisible ladder | `bind 6L3 invisible` |
| `reraise` | *nothing* — the reraise ladder | `bind 6L4 reraise` |

**`<target>`** is optional and takes the game's own target tokens. These are
the ones that work:

| Token | Means |
| --- | --- |
| `t` | your current target |
| `me` | yourself |
| `bt` | your battle target |
| `pet` | your pet |
| `p0`–`p5` | a party member by position (`p0` is you) |
| `a10`–`a15`, `a20`–`a25` | a member of the first or second alliance party |
| `st`, `stpc`, `stnpc`, `stal` | the game's pick-a-target cursors |
| `ft`, `lastst`, `scan`, `r` | the game's remaining tokens, meaning what they mean in a macro |

Leave it off for anything that does not need one. Each may be written bare or
in angle brackets — `t` and `<t>` are the same thing.

**Wrap `<action>` in quotes** if it contains a space. Unquoted, the last word
is a target only when it is one of the tokens above; anything else is taken as
part of the action's name, so `ws Savage Blade Zeid` binds a weaponskill
called "Savage Blade Zeid". Where the addon can tell the shorter name is a
real action and the longer one is not, it refuses instead of binding something
that could never fire, and where it cannot tell it says which reading it took.

**Quote a whole name to keep it whole.** `ws "Savage Blade Zeid"` binds that
three-word name outright. Quoting only part of a name settles nothing, and a
quote cannot mark a label — use `alias=` and `icon=` for labels.

**A player's name is not a target.** Use a token above — `t` for whoever you
have targeted, `p1`–`p5` for a party member.

**`copy` replaces.** `//hud crossbar copy WHM` puts WHM's bindings on this job
wholesale — its sets, its subjob, weapon and context layers, over the top of
whatever this job had. There is no undo and no confirmation step. It refuses
the job you are on, and a job that has no bindings to copy. Shared sets
are not involved either way: they belong to no job, which is why `copy` takes
a job and refuses `SHARED`.

**`reset` deletes every job's bindings, not just this one's.** `//hud reset
crossbar` restores the component's own settings *and* empties its store —
every `<JOB>.lua` file and `SHARED.lua` with them, for every job you have ever
bound, in the active layout slot. `//hud reset all` does the same to
the crossbar on its way through every component. There is no undo and no
confirmation step. To start one job over without touching the rest, unbind its
slots or `copy` another job's bindings over it.

### Labels and icons

A slot shows the action's own name and icon. **`alias`** and **`icon`**
override either for one slot, which is worth it when the real name is too long
to read at a glance, or when the slot holds a `ct` or `ex` command that has no
icon of its own:

```
//hud crossbar alias 1L3 "AW"           -- Addendum: White, shortened
//hud crossbar icon 4L1 map             -- give a custom command an icon
//hud crossbar alias 1L3                -- back to the action's own name
```

**`bind` takes both on the end**, so a slot can be labelled by the command
that binds it — each opened by its own marker:

```
//hud crossbar bind 1L3 ja "Addendum: White" alias=AW
//hud crossbar bind 4L1 ct heal alias=Rest icon=heal
//hud crossbar bind 2R1 item "Warp Ring" icon=items/warp-ring   -- an icon, no alias
//hud crossbar bind 1R1 ex "jc RDM/DRK" alias=RDM/DRK icon=jobs/rdm
```

A marker's value runs to the next marker or the end of the line, so an alias
with spaces needs no quotes of its own: `alias=Big Hit` is one alias. Both are
matched in any case, take either order, and either may be left out — an icon
with no alias is just `icon=<name>` with no `alias=` beside it. What follows
from that:

- **The marker ends the action name**, which is what lets a one-word name
  carry a label: `ma Cure alias=C` binds Cure under the label "C", where
  `ma Cure C` binds a spell called "Cure C".
- On a `ct` or `ex` line the marker is the only thing that ends the line, so
  the line keeps every word up to it: `ct p pulling alias=Pull` says
  `/p pulling` under the label "Pull". (A `ct` line is written without its
  leading slash — the addon adds it.) A line that needs a literal `alias=` or
  `icon=` in it must be quoted as a whole: `ct "p alias=x"` says `/p alias=x`,
  where the unquoted `ct p alias=x` says `/p` under the label "x".
- **A quoted phrase inside a `ct` or `ex` line is kept**: `ct ma "Cure IV" <t>`
  says `/ma "Cure IV" <t>`, and `ex gs c "set TP"` runs with its grouping
  intact. Quotes around a *single* word are not kept — `ct ma "Cure" <t>` says
  `/ma Cure <t>`, which the game reads the same way anyway.
- The other half of that: **a phrase you quote in a chat line is said with
  the quotes on it.** `ct p "Hello there"` says `/p "Hello there"`. Leave
  chat text unquoted — `ct p Hello there` says `/p Hello there` — and keep
  the quotes for the places the game itself wants them, like a spell name.
  Quotes around the *whole* line are the one exception and come off again:
  `ct "sea all linkshell"` says `/sea all linkshell`.
- A **target** goes in front of the labels. One that turns up after them as a
  word of its own is refused rather than quietly folded into the alias.
  An alias you really do want to end in `p1` can be quoted (`alias="Cure p1"`)
  or given with the `alias` verb.
- An icon the addon cannot find **refuses the whole bind**, rather than
  binding the action and dropping the art quietly.

The `alias` and `icon` verbs take the same `context=` as `bind`, so
`alias 1L3 Penury context=buf:light-arts` relabels only what that context puts
in the slot. Both need
something in the slot to act on — on an empty one they report an error rather
than doing nothing quietly, and `icon` says so too if it cannot find the name
you gave it.

**`<icon>` is the name of a picture, not an action.** The addon's own icons are
named by their path inside its icon pack, so a top-level one is a bare word —
`map`, `mount`, `attack` — and one in a folder keeps the folder:
`items/warp-ring`, `mounts/chocobo`, `weapons/sword`.

**Job icons.** The party list's job icons ship as pictures too, one per job
under `jobs/` — `jobs/whm`, `jobs/rdm`, `jobs/pld` — already drawn on their
role colour, so a slot can carry the job it belongs to:

```
//hud crossbar icon 3L1 jobs/whm
```

#### Using your own icons

Put PNGs in **`icons/custom/`** inside the addon folder, and name them
whatever you want to type:

```
Windower4/addons/XIVHud/icons/custom/pull.png
    → //hud crossbar icon 4L1 pull
```

Any size works, though 40x40 matches the slots exactly. The folder is yours —
it is not part of the addon download, so updating XIVHud leaves it alone.

Your icons are checked **before** the ones that ship with the addon, so naming
a file after an action replaces its picture everywhere: an
`icons/custom/cure.png` becomes the picture on every Cure slot without you
re-pointing anything. The built-ins are matched by their type word
(`draw.png`, `warp.png`, `mr.png`).

The folder is **flat**, and that is how it is searched: only the last part of a
name is looked for there. `icon 6L1 items/warp-ring` checks
`icons/custom/warp-ring.png` first and the addon's own `items/warp-ring` after
— you never make an `items` folder of your own.

`bind`, `unbind`, `alias` and `icon` take an optional `context=` naming the
layer — `context=sub:<job>` for a subjob (`context=sub:whm`, worn or not),
`context=wpn:<weapon type>` for a weapon type, written in lower case with
dashes for spaces (`context=wpn:great-katana`, `context=wpn:hand-to-hand`, and
for the ranged slot `context=wpn:marksmanship`), and `context=buf:<name>` for a
buff context (`context=buf:light-arts`). It can go anywhere among the labels.
With none you are editing the job's base layer — except that `bind` puts a
weaponskill on its own weapon type: `bind 1R1 ws "Leaden Salute" t` lands on
the Marksmanship layer whatever you are holding. A job ability (or pet
command) that belongs to a subjob goes to that subjob's layer the same way: on DNC, `bind 1L2 ja
Provoke` lands on `context=sub:war`, worn or not. A subjob's ability can also
go under a buff context (`context=buf:light-arts`), but never on the base or a
weapon layer. `unbind`, `alias` and `icon`
never guess, so name that layer to edit it afterwards (`alias 1R1 LS
context=wpn:marksmanship`); without it they say which layers the slot holds. See
[Layers](#layers-how-a-slot-decides-what-to-show).

```
//hud crossbar bind 1L3 ma "Cure IV" t
//hud crossbar bind 1L4 ja "Utsusemi: Ichi" context=sub:nin
//hud crossbar bind 1R1 ws "Savage Blade" t
//hud crossbar bind 1L4 ma Cure t context=sub:whm
//hud crossbar bind 1L3 ja "Addendum: White" context=buf:light-arts
```

Most of this is also bindable by mouse in `//hud crossbar edit`, which is
usually easier — the binder lists what you actually know rather than asking
you to spell it. `ct` and `ex` are the exceptions: those two are
command-only. Pet commands are in the binder, among the job abilities and in
menus such as Blood Pact and Ready. Enchanted gear the binder does list, under **Enchanted** — it
reads your wardrobes as well as your inventory to find it. See
[What you can bind](#what-you-can-bind) for the fuller picture.

### Sets

| Command | What it does |
| --- | --- |
| `//hud crossbar share <set> on\|off` | share a set across every job, or keep it to this one |
| `//hud crossbar cycle <set> drawn\|sheathed\|both\|none` | choose which rotations a set belongs to |
| `//hud crossbar view <wxhb-L\|wxhb-R\|exp-LR\|exp-RL> <set><L\|R>` | point a view at a set and side |
| `//hud crossbar wxhb [on\|off]` | keep the WXHB on screen at rest, or show it only while held — omit the argument to report the setting |

### Inspection

| Command | What it does |
| --- | --- |
| `//hud crossbar context list` | list the buff contexts in stack order, marking the active ones |
| `//hud crossbar open` | list the game screens you can bind |

### Built-in actions

These fire directly, and are also bindable to slots. Because they are
commands, they work with `//bind` and in in-game macros too.

| Command | What it does |
| --- | --- |
| `//hud draw` | sheathe / unsheathe — or dismount, if mounted |
| `//hud mr` | summon a random mount you own, or dismount if you are on one. Summoning counts down first — see **Travel counts down** below |
| `//hud warp [all]` | warp home by the best means you have, after the same countdown; `all` warps your other characters running XIVHud, and sends them when this character's own warp actually goes (or at once if this character has no way home) |
| `//hud sneak` | picks the first way this character has to get the effect, cheapest first: the spell (Sneak / Invisible), then Spectral Jig, then the ninjutsu if you have the tool (Tonko: Ni over Tonko: Ichi; Monomi: Ichi), then a Silent Oil / Prism Powder. Silenced or muted, the spell and the ninjutsu are passed over. The order is the same on every job; what changes is which rungs you qualify for, read from the spells you know and the levels your main and sub have. Self-only rungs stay on you and so does the oil or powder; the spell goes to a targeted party member if you have one selected. |
| `//hud invisible` | the same ladder for invisible |
| `//hud reraise` | the best reraise you can get right now: Reraise IV, III, II or I if you can cast it (a scholar needs Addendum: White or Enlightenment up), then a Super Reraiser, Hi-Reraiser, Reraiser or Instant Reraise from your inventory, then a Reraise Ring, Earring, Hairpin or Gorget your job can wear, equipped and waited out for you the way an enchanted item is. Refused while Reraise is already on, since the game cannot say which tier you have. No countdown. |
| `//hud crossbar open <name>` | open a game screen (`map`, `equipment`, …) |

---

## Steam Input mapping

The addon reads keys. Turning a controller into those keys is Steam Input's
job, so nothing here is enforced by the addon — any layout that emits the
right keys works, and a keyboard player can press them directly.

Six keys drive everything:

| Key | Role |
| --- | --- |
| `;` | left side — hold to activate it |
| `'` | right side |
| `\` | the W-layer — hold with a side for its WXHB bar |
| `` ` `` | set switch — tap to cycle, hold and press a button to jump; ignored while a side is held |
| `=` | Select — nothing on its own; with a side held, opens the binder |
| `1`–`8` | the eight slots — but only while a side or the switch is held; otherwise they reach the game as usual |

You can still type them: once the chat box has focus the crossbar hands every
key back, so they all reach your message normally.

**No modifiers are used.** The bar never uses Ctrl or Alt, so FFXI's own
macro palette on those chords is untouched.

A controller layout that produces them:

| Pad input | Emits | You get |
| --- | --- | --- |
| **LT** held | `;` | activates the XHB's left side |
| **RT** held | `'` | activates its right side |
| **LT + RT** | both | Expanded Hold takes over the screen — which one depends on the order you pressed them |
| **LT + LB** | `\` | activates the WXHB's left side (bringing it on screen if it was not) |
| **RT + RB** | `\` | the WXHB's right side |
| **LB** tapped | the pad's own button | whatever the game has that button doing — the crossbar never sees it |
| **LB** long-pressed | `\` | held for the draw gesture below |
| **RB** | `` ` `` | tap cycles sets; hold and press any slot button to jump to that set, 1 to 8 (no trigger held) |
| **Select** | `=` | nothing on its own; with a side held, the binder |
| **face / D-pad** while LT, RT or RB is held | `1`–`8` | the eight slots |

### Button chords

Several controls mean different things depending on what else is held. All of
it is done with **button chords** — a binding that only fires while another
button is held. Nothing here uses action sets or mode shifts.

The face buttons and D-pad carry the eight slots while you are reaching for
the crossbar, and are your normal game buttons the rest of the time. Steam
lets one chord list several trigger buttons and fire on **any of them**, so
each slot button needs one chord rather than three:

| Chord | Emits |
| --- | --- |
| Y + LT, RT or RB | `1` |
| B + LT, RT or RB | `2` |
| A + LT, RT or RB | `3` |
| X + LT, RT or RB | `4` |
| D-pad ↑ + LT, RT or RB | `5` |
| D-pad → + LT, RT or RB | `6` |
| D-pad ↓ + LT, RT or RB | `7` |
| D-pad ← + LT, RT or RB | `8` |
| LB + LT | `\` |
| RB + RT | `\` |
| Select + LT or RT | `=` |

Eleven chords. Everything else on the pad is a plain binding, listed in the
table above.

The Select chord is what opens the binder: `=` on its own does nothing, and
the crossbar only treats it as "open the binder" when a side is already held.
Select emits `=` as a plain binding too, so the chord is there to make sure it
still does while a trigger is down.

**RB belongs in the slot chords, not just the triggers.** Jumping to a set is
`` ` `` held plus a slot button — leave RB out and you have a switch key with
no numbers to press against it, and set jumping does nothing at all.

**The bumpers need more than one binding each.** LB carries **three**: the
pad's own button on a tap, `\` on a long press, and `\` again in the LT + LB
chord. RB is `` ` `` on a press. Their chords are in the table above.

**Mark the LT + LB chord as not interruptable in Steam Input.** Three
bindings on one button is what makes this necessary: left interruptable, the
chord gives way to LB's other two and the WXHB's left side does not come up
reliably. The RT + RB chord carries only two bindings on RB and does not need
it.

Two more things:

- **Set switching only works when no side is held.** Holding a side means you
  are using the crossbar, so the switch key is ignored until you let go. From
  RT the pad enforces it as well, since RB emits `\` in that chord; from LT
  the key still arrives and the crossbar is what ignores it.
- **Leave Select alone.** It is `=` in every state, chorded or not — the
  crossbar reads the chord itself, so the binder stays reachable whatever
  you are holding. On its own the key does nothing: it is still the
  crossbar's, so the game never sees it, but a key you cannot use for
  anything else should not fire something you did not ask for either.

**Sheathe / unsheathe** is a gesture: hold `\` and tap `` ` `` with no side
held — on the pad, hold **LB** and tap **RB**. Mounted, the same gesture
dismounts.

---

## What is on screen

While the component is visible, this is what you see:

| While you hold | XHB | WXHB | Expanded Hold |
| --- | --- | --- | --- |
| nothing | on screen, inactive | on screen, if configured | hidden |
| an XHB side | **that side active** | as above | hidden |
| a WXHB side | on screen, inactive | **that side active** — its other half only if you keep the WXHB on screen | hidden |
| both side keys | hidden | hidden | **on screen, active** |

The active side is marked with a panel drawn behind it, so it is obvious
which eight buttons are live.

Whether the WXHB rests on screen is up to you — `//hud crossbar wxhb on|off`,
**off to begin with**. Off, it appears only while you are holding for it,
which keeps the resting HUD to sixteen slots; on, both bars sit there
permanently, thirty-two slots, with nothing appearing or disappearing as you
play.

Each bar starts pointed at a different set, so nothing duplicates anything:
the XHB on set 1, the WXHB on set 2, Expanded Hold on set 3.

**Expanded Hold takes the screen over.** It is up only while both side keys
are down, and it hides the XHB and WXHB for that time; release one and you
drop straight to the XHB side you are still holding. Adding the layer key changes nothing
— there is no W version of Expanded Hold. Being eight slots rather than
sixteen, it draws centred on the XHB's position — the bar you were looking at
changes contents rather than moving.

These are positioned separately in `//hud layout` — the XHB as one bar, the
WXHB as two halves you can place apart from each other, the set label and
the sword — so a permanently-visible WXHB can live wherever the XHB is not.
The skillchain window indicator is its own component,
[skillchain](skillchain.md).

## Layers: how a slot decides what to show

A slot holds a small stack rather than a single action, and the topmost layer
with something in it wins:

```
buff contexts    ← Light Arts, Addendum: White, …   (only while the buff is up)
weapon overrides ← just while a sword is in your main hand, say
ranged overrides ← just while a gun is in your ranged slot, say
subjob overrides ← just for RDM/NIN, say
job base         ← every subjob shares this — or the shared copy, for a set
                   marked shared (the same on every job)
```

**Weapon overrides** are keyed by the class of weapon in your main hand —
Sword, Great Katana, Hand-to-Hand when unarmed — and are the place for
weaponskills, so swapping weapons swaps the slots with them. They sit above
subjob overrides where both hold the same slot. **Ranged overrides** work the
same way for the weapon in your ranged slot - Archery, Marksmanship or
Throwing - and sit just below the main hand's.

The point is that **you only say a thing once**. A slot that should be the
same on RDM/NIN and RDM/WHM is set on the job base and left alone. Only the
slots that genuinely differ get a subjob override.

### Buff contexts

Some abilities only exist while a buff is up, which FFXIV has no equivalent
for. A **context** is a buff the addon watches; while
that buff is on you, the context's overrides win.

Scholar is the clearest example:

- On Scholar the slot holds **Light Arts** — the job's own base, since sets
  are per job unless you share them.
- Use Light Arts, and the `light-arts` context activates — the same slot
  becomes **Addendum: White**.
- Use that, and the `addendum-white` context activates — a whole WXHB side
  turns into the spells it unlocks.
- Your four stratagem slots hold the light stratagems under Light Arts and
  the dark ones under Dark Arts, automatically.

Contexts ship with the addon; you fill in what goes in them. The list today,
lowest priority first (when two live contexts both fill a slot, the later one
wins):

- Scholar's `klimaform`, then one per storm — `sandstorm`, `rainstorm`,
  `windstorm`, `firestorm`, `hailstorm`, `thunderstorm`, `voidstorm`,
  `aurorastorm` (each also live under its Storm II)
- Red Mage's `composure`
- Scholar's `light-arts`, `dark-arts`, `addendum-white`, `addendum-black`
- Blue Mage's `unbridled` (Unbridled Learning or Unbridled Wisdom)

`//hud crossbar context list` shows them and which are live. A context only
fires on the job it belongs to: the Scholar contexts on SCH main or sub,
`composure` on RDM main, `unbridled` on BLU main; on any other job `context
list` leaves them out and they never turn on. You can still bind one there -
the edit window lists every job's contexts - and it is kept with this main
job's bindings: on WAR/NIN you can set up the Scholar slots you want for
when you switch to /SCH. `composure` and `unbridled` only ever turn on with
RDM or BLU as the main job, so binding one on any other main job does
nothing.

### Editing without guessing

In edit mode:

- Every slot is **tagged with where its content comes from**, before you click
  anything: `+` for a subjob override, `^` for a weapon override, `*` for a
  buff context, nothing at all for the job base or a shared set. The tags
  leave with edit mode.
- Clicking a slot opens its **whole stack** — every layer, what each holds,
  and which one is currently winning.
- **You must pick a layer before the action list appears.** Nothing is
  assumed, and the layer you are editing is named on screen the whole time.
- Picking a layer row also **previews the crossbar as if that buff were up**, so
  you can build your Addendum side while looking at your Addendum side.
- **Hovering** describes what is under the cursor in the window's own details
  column: a slot or an entry in the action list gives you its name, type and
  target, its MP or TP cost, how much of its recast is left, and the
  skillchain property it carries. A slot adds the layer its content is coming
  from and which layers that is covering. It is only what the addon already
  knows — there is no game description text.

**Dragging** does two things, both of them on the bar rather than in the
window: drag a slot onto another slot to swap them entirely, or drag a slot
onto **genuinely empty screen** to clear it — which removes it from the layer
you are editing, and leaves every other layer alone. Empty means clear of
everything: a drop that lands on a bar but misses its slots — between two of
them, on a name, on the set number — cancels and changes nothing, on the
crossbar and the hotbar alike. Dragging an action out
of the list does nothing; the steps are the way to bind. Dropping a slot
back where it came from changes nothing.

While a slot is in your hand the window steps out of the way and the slot's
icon and name follow the cursor, so you can see what you are carrying and
drop it on a slot the window was covering. The window comes back on the
drop. Letting go over the spot where the window stood, with no slot under
it, cancels quietly and changes nothing — it is never the empty screen that
clears a layer.

**Onto the hotbar, and back.** A slot can be dropped on a
[hotbar](hotbar.md) slot too, and a hotbar slot on a crossbar one. It is the
same swap: the two slots trade everything they hold, every layer of it,
between the two bars' own files. Where a slot of each bar sits on the same
spot, the hotbar's is the one on top, and it is the one a click or a drop
there reaches. Move one of the bars to get at the slot underneath. The one
exception is a hotbar that is on screen but not in edit mode, having been
hidden and shown again since: a click there reaches the crossbar's slot,
while a drop still lands on the hotbar's.

**Edit mode covers both bars.** `//hud crossbar edit` and `//hud hotbar edit`
do the same thing: each puts both bars in edit mode, and either takes both
out again. Both bars show every slot they have, empty ones included, and
either can be clicked or dragged from. There is still only one window: click
a slot on the other bar and the window moves over to it. A bar that is
hidden is left out, and the reply names the other bars in edit mode; its own `edit`
command answers that it is hidden, so use the other bar's to leave. A click
on the window is always the window's, whatever slot of the other bar is
under it.

**One window, three steps.** Edit mode draws nothing until you click a slot.
Then a single window opens dead centre - sized to your screen, the way the
rest of the HUD is - and walks you through:

1. **Pick a layer** — base (or shared) at the top, then three menus:
   **subjob** (every job but your main one), **weapon** (every main-hand
   weapon type, then Archery, Marksmanship and Throwing for your ranged
   slot - a ranged layer is live while that kind of ranged weapon is on, and
   where it and your main hand's layer both bind a slot the main hand wins)
   and **job specific** (RDM's Composure, BLU's Unbridled
   Learning, and SCH's Klimaform, a **Storms** menu, and the arts and
   addenda). The subjob or weapon doesn't have to be the one you have on.
   Picking a layer previews the bar as if it were in use - that subjob worn,
   that weapon held, that buff up. A `>` marks a menu; a `*` on one means the
   layer showing on the bar is inside it. `[ < back ]` climbs out of a menu.
   The actions offered next follow the layer. A weapon layer offers every
   weaponskill of that weapon type, as if you were holding it, and is the
   only layer that offers weaponskills at all - nor can `bind` put one
   anywhere else (a weaponskill you already have elsewhere keeps working).
   A subjob layer - the one you have on included - offers what that job can do
   as your subjob at the highest level your master level allows (59 at
   master level 50, 49 at 0, half your main job's level below 99), whatever
   level that job itself is: the spells you have learned up to that level,
   and its job abilities up to that level. A master level the addon has not
   read yet counts as 50. Your main job's own abilities are offered as
   always, minus the ones that belong to the subjob you are actually
   wearing - a WHM layer on WAR/SAM does not offer Hasso. The base and
   weapon layers leave the worn subjob's abilities out too: those are bound
   through the subjob menu, or under a buff context, which offers them.
   Inside the subjob and weapon menus the rows read just the job or the
   weapon type (`WHM`, `Great Axe`).
2. **Pick an action** — categories down the left, the actions on the right.
   The wheel scrolls them three at a time; clicking the page line under them
   jumps a whole page, and past the last one back to the top.
3. **Pick a target** — the common target tokens, with `(no target)` first (`stal`, `lastst`, `scan` and `r` are `bind`-command only). Actions
   that cannot take a target skip this step and bind straight away.

**Menus get a fourth step.** Some entries in the action list are the game's own
menus rather than actions — **Stratagems** on SCH, **Phantom Roll** and **Quick
Draw** on COR, **Waltzes**, **Sambas**, **Jigs**, **Steps** and **Flourishes
I/II/III** on DNC, **Rune Enchantment**, **Ward** and **Effusion** on RUN,
**Blood Pact: Rage** and **Blood Pact: Ward** on SMN, **Ready** on BST. Clicking
one opens what is behind it, and you pick the real action there: Stratagems
then Accession, Blood Pact: Rage then Volt Strike. **Job Change** under General
is a menu inside a menu: a main job, then a sub job. `[ < back ]` steps back out
of the list one menu at a time, and the categories down the left stay live — clicking one leaves
the menu.

Before this the picker offered the menu itself, and binding that does nothing
at all in game, so these were reachable only from `//hud crossbar bind`. How
many entries a menu holds depends on what the game reports: it may list
everything the job can ever learn rather than only what you can use yet, in
which case binding one you have not learned gives a slot the game refuses.

A **details column** on the right shows whatever the cursor is over: name,
cost, recast, skillchain property, and for a slot the layer its binding comes
from. A menu row is not an action and has nothing to describe, so the column
is blank over one. It still carries an icon: Stratagems shows the grimoire,
and every other menu shows its job's glyph. **`[ < back ]`**, in the top left, steps back one screen; it is absent
on the first step. **`[ X ]`**, in the top right, closes the window from any
step.

Binding lands you back on step one, ready for the next edit on the same slot.

**Moving it.** Drag the window by its title strip — the top row, to the right
of the back button. Where you leave it is remembered with the bar's settings (per layout slot), so it opens
there next time rather than back in the middle. It is always kept fully on
screen, including a position saved at a resolution you no longer play at.

The window does not dodge the bar. If you have put the bar in the middle of
the screen the window will cover it, and slots underneath cannot be clicked
while it is up. They can still be dropped onto: the window is out of the way
for as long as you are dragging a slot.

**Changing set.** The set switch still works in edit mode — tap `` ` `` to
cycle, or hold it and press a number to jump — because which set is on screen
is the thing you are editing. If a window is open when the set changes it is
put away, since it remembers the slot it was opened on and would otherwise
bind into a set you are no longer looking at. Edit mode itself stays on.

**Getting out.** While edit mode is on the crossbar otherwise does nothing — no
side activates, no slot fires, and the bar holds still under the binder. The
side you were holding to open it goes dark as the mode opens, since it is inert
from that moment; the display picks the real keys back up when you leave. Leave
it with `//hud crossbar edit` again, with **any press of the Select key**
(`=`), or by entering `//hud layout`, which takes over from it. Edit mode
needs the crossbar visible and a job loaded to open at all, and refuses while
`//hud layout` is up. Leaving takes the hotbar out of edit mode with it.

---

## Sets, sharing, and cycling

You always have **eight sets**. Cycling puts one of them on the
XHB. What differs between sets is where each one is *stored*:

- A set marked **shared** is the same on every job — one copy, edited from
  anywhere. Good for non-combat things you want everywhere.
- A set left **job-specific** is stored per job. Set 1 on WHM and set 1 on WAR
  are different sets that happen to share a number.

```
//hud crossbar share 6 on      -- sets 6, 7, 8 shared: the same everywhere
//hud crossbar share 7 on
//hud crossbar share 8 on
```

Sharing a set that already holds job-specific bindings does not merge the two.
The shared copy takes the slots over, and this job's own bindings for that set
go **dormant** — they are kept and come back the moment you share the
set off again. The command tells you when that has happened.

### Rotations

Cycling with `` ` `` walks a rotation you choose, not all eight. Each set can
be included in a **drawn** rotation, a **sheathed** one, both, or neither:

```
//hud crossbar cycle 1 drawn        -- combat sets, cycled with the weapon out
//hud crossbar cycle 2 drawn
//hud crossbar cycle 6 sheathed     -- utility sets, cycled with it away
//hud crossbar cycle 3 none         -- reachable only by jumping, or as a view
```

Empty sets are skipped, so the cycle is only as long as you have made it.
A set flagged `none` is still reachable — jump to it with `` ` ``+button, or
point a WXHB or Expanded view at it.

**"Drawn" is the addon's own idea, not the game's.** It flips when you use the
`draw` action, and it flips when you engage a mob — but it does *not* flip
back when the mob dies.

Changing it also **moves you to the first set of the mode you just entered** —
the lowest-numbered set you have flagged for that rotation. Draw and you land
on your first combat set; sheathe and you land on your first utility one, every
time, whatever you were on. Only sheathing yourself takes you out of combat mode,
so a set rotation does not lurch back mid-pull.

**Changing job lands you the same way.** A job change sheathes you, so you
arrive on the first set of your *sheathed* rotation rather than wherever that
job was left. The active set is not remembered per job: a job always resumes
at the front of the rotation its current weapon state belongs to.

If **no** set is flagged for the state you are entering — or every set that is
happens to be empty — the active set is left where it is.

Going *in* sends nothing to the game (unless you are mounted, when it dismounts): `draw` while sheathed only flips the
addon's state and flips the sword to its drawn glyph, so it never picks a fight for you and
never needs a target. Going *out* does disengage you — `draw` while drawn
means "I am done fighting".

---

## What you can bind

### Game actions

| Type | For |
| --- | --- |
| `ma` | spells — including trusts and blue magic |
| `ja` | job abilities |
| `ws` | weaponskills |
| `item` | usable items |
| `enchanteditem` | enchanted gear — a Vocation Ring, a Warp Cudgel, a charged cape |
| `pet` | pet commands |
| `mount` | a specific mount |
| `ra` | ranged attack |

**Enchanted gear** is the one type that does more than send a command. Press
it and the crossbar equips the piece, keeps GearSwap from swapping it straight
back out, waits for the enchantment to come up, uses it, and releases the slot
again (both ring slots, if it is a ring you were already wearing). If you keep
a slot disabled in GearSwap yourself, that release will re-enable it. If the
item is already worn and charged it simply fires.

Note that equipping the piece **displaces whatever was in that slot**,
and the crossbar does not put the old piece back — it only releases the
GearSwap hold. Your next gear swap will sort it out; a `//gs c` or a
manual re-equip will do it sooner. A wait needing more than about 30
further seconds is given up at once rather than sat through, and nothing
is held much beyond that — the bar says which, and why, in chat. A few
items whose enchantments take longer to come up are allowed a
correspondingly longer wait; the Tavnazian Ring is one.

A slot on recast says so instead of firing, and only one of these can be in
flight at a time (a warp counts as one too — there is one pair of hands).
If you press one while a `warp` countdown is running, the warp is refused
when its countdown ends (the bar says the enchanted item is still in progress)
rather than queued behind the item, and `warp all`
does not send your other characters.
Unlike `mount`, `mr` and `warp`, an enchanted item takes **no**
countdown: the warmup already is the wait.

**Its target is settled when you press it**, not when it fires. Gear is
normally worn by you and needs no target at all, but if you do bind one —
`enchanteditem "X" t` — the press pins whatever you had targeted and sends
that, so a wait of half a minute cannot land the item on something you
tabbed to since. A target the press cannot settle is refused outright
rather than left to resolve later: pressing with nothing targeted says so.
A bind aimed at a pick-a-target cursor (`st` and friends) is accepted, but
every press of it is refused with `cannot pin <st> at the press - bind <me>
or <t>`.

Both `item` and `enchanteditem` slots show **how many you carry** in the
corner, and cross themselves out at zero — enchanted gear always, and a plain item once the crossbar has found your temporary items, so that a slot is never crossed out on a guess. Consumables are counted from
your inventory and your temporary items; enchanted gear is counted
wherever you can reach it, wardrobes included. That is a count of the items
themselves, not of an enchantment's charges — a spent ring still reads `1`,
and pressing it answers `Vocation Ring: no charges left.`

### Text and scripts

| Type | For |
| --- | --- |
| `ct` | a single chat command, e.g. `ct "sea all linkshell"` |
| `ex` | a raw Windower command — including `exec <script>`, which runs a multi-line Windower script. This is the closest thing to a macro. |

FFXI's own macro palette cannot be triggered by an addon, so `ex` with a
script is the way to put a sequence on a slot.

### Built-ins

These are the same actions as the `//hud` commands under
[Built-in actions](#built-in-actions); the type word binds one to a slot.

| Type | What it does |
| --- | --- |
| `draw` | sheathe / unsheathe, and dismount when mounted. Its icon follows the state. |
| `mr` | mount roulette — picks at random from the mounts you actually own, and dismounts if you are already up. In the binder it is filed at the head of **Mounts** rather than under General, and it only appears if you own something to ride. |
| `mount <name>` | summons that mount, or dismounts if you are already up |
| `warp` | picks the best warp you have, in order: the Warp or Warp II spell (Black Mage main or sub, with the MP for it), then a Warp Ring, an Instant Warp, a Warp Cudgel, a Treat Staff II, and a Tavnazian Ring as the last resort. Equips the ring or cudgel for you and waits out the enchantment — though if it has more than about 30 seconds left to charge it gives up rather than waiting. The Tavnazian Ring is allowed longer, because its own warm-up is roughly that. A piece already on your finger is not assumed to be ready either: if its enchantment is still coming up, the crossbar waits it out for you, the same as it would for a ring it equipped itself. `warp all` sends your other characters running XIVHud home — when this character's warp actually fires, so calling the countdown off, or a ring warm-up that gets abandoned, leaves them where they are. If this character has no way home at all, they are sent at once. |
| `sneak` / `invisible` | the sneak and invisible ladders described under [Built-in actions](#built-in-actions). Both take the White Magic icon whichever rung fires, so the slot's face does not change with your subjob. |
| `reraise` | the reraise ladder described under [Built-in actions](#built-in-actions), with the Reraise icon whichever rung fires |
| `open <name>` | opens a game screen |
| `jc <MAIN>/<SUB>` | changes job to that pair through the Windower **JobChange** addon (`//jc war/blm`), which must be loaded — without it the press does nothing but print "unknown command" in the console. You still have to stand near a Moogle (or a Nomad Moogle), as JobChange requires. The slot shows the main job's icon and the sub job as its label. In the binder it is **General → Job Change**, then a main job, then a sub job. All 22 jobs are listed whether you have unlocked them or not; JobChange refuses a locked one when you press it. |

`mr` and `warp` count down before they go, and so does the `mount` type
above — see **Travel counts down** under Extras.

**A mount slot greys out for the minute after you summon one**, which sweeps
round as a recast like anything else. Where you are is not checked: the
game's data does not reliably say which zones allow riding, so in one that
forbids it the game turns the summon down itself.

**A press the addon knows will fail does nothing at all**: no
countdown, no command, no recast — a press while the recast from your last
summon is still running. It says so in the log, with the seconds left. The greyed icon and the
dead press follow the same rule, so what you see is what the button will do.

The recast keeps running once you are actually mounted, and keeps the slot
greyed until you could mount again — though the press is now a dismount,
which is never held up.

The minute starts when the summon is sent, which means a summon the
game turns down for a reason the addon cannot see — being in combat, say —
will still grey the slot for the minute.

#### What `open` can open

| `<name>` | Opens |
| --- | --- |
| `map` | your map |
| `equipment` | the equipment screen |
| `inventory` | your inventory |
| `case` | your Mog Case |
| `sack` | your Mog Sack |
| `satchel` | your Mog Satchel |
| `wardrobe`, `wardrobe2` … `wardrobe8` | that wardrobe |
| `quests` | your quest log |
| `linkshell` | a search listing your linkshell members |
| `linkshell2` | the same for your second linkshell |
| `flist` | your friend list |

`//hud crossbar open` prints this list in game.

Most of these are chat commands the game already has, so they are reliable.
**`equipment` and `inventory` are the exceptions**: FFXI has no command for
them, so those two press Ctrl+E and Ctrl+I for you. They stop working if you
have rebound those keys in the game's own settings, and not every FFXI window
can be opened this way.

---

## Extras

**Recasts** sweep as a radial arc around the slot.
**Costs** show MP or TP in the corner. Actions you cannot use dim.

**Skillchains**: the [skillchain](skillchain.md) component shows the window
itself; on the bar, while a skillchain window is open on your target, every bound
weaponskill, job ability and pet ability swaps its icon for the skillchain
property it *would* make right now. A weaponskill you cannot yet pay for shows
the property dimmed, with its TP cost still up.

**Stratagem counts** show on the Scholar abilities that spend them. The
countdown on those slots is the time until your **next** charge comes back, not
until all of them are, and the slot stays lit while you have a charge left.

**Ninja tool counts** show on ninjutsu slots — how many of that tool you are
carrying, and the slot crossed out when you have none. The colour tells you
where the count is coming from: **green** when you have more than fifty of the
tool itself, **yellow** when it takes your master tools to get there, **red**
when even together they are fifty or fewer. On main Ninja the
count includes your master tools; on `/NIN` it counts the plain tool only.
Corsair cards are counted the same way, including Trump Cards.

**Travel counts down.** `mount`, `mr` and `warp` do not go the moment you
press them. They count down in chat — five seconds out of the box, `//hud
delay` changes it — and only then act, so a
mis-pressed warp costs you five seconds of reading rather than a trip back from
your Mog House. It reads:

```
[XIVHud] Mount roulette in 5 seconds. /heal to cancel.
[XIVHud] 4...
[XIVHud] 3...
[XIVHud] 2...
[XIVHud] 1...
```

**Resting calls it off**, and `/heal` is the way in — but it is your *status*
that is watched, not the command, so sitting down by any other means stops it
just as well. So does zoning, dying, changing job, or a cutscene hiding the
HUD while it counts. Each of them says `[XIVHud] Mount roulette cancelled.`
rather than going quiet; a logout drops it silently. Hiding the crossbar
yourself (`//hud hide crossbar`) does not call it off.
A countdown never carries over a zone, a death or a job change.

**So does opening a config mode.** `//hud layout`, `//hud config` and
`//hud crossbar edit` each call a pending trip off, and one you ask for while
any of them is already open is refused outright — `[XIVHud] Mount roulette - not while //hud layout is
open` — rather than counting down to nothing. A late action goes only where a
fresh press would.
`//hud reset crossbar` drops a countdown too, quietly: after a reset there is
nothing left of the setup that armed it. Typing `//hud mr` still dismounts in
either mode, being instant rather than late.

**Typing in chat does not stop it.** Answering a tell while you wait to warp is
playing, so the countdown runs on — only resting, the transitions above and the
config modes call it off.

Other slots carry on as normal while it counts — curing something is not a
change of mind, and it neither cancels the trip nor waits for it. **A second
trip does replace the first**, though: press `warp` while a mount is counting
down and only the warp goes, on a fresh countdown.

**Two things do not wait.** Getting *off* a mount is instant —
`mr` while you are mounted — and a slot bound to a **named** mount does the
same, dismounting rather than summoning — and `draw`, which dismounts as its
first job.

The countdown tells you **which** way you are going home — `Warp Ring in 5
seconds`, not a bare `Warp` — and only the last five seconds are counted out
loud. A warp that has to put a ring on and wait for it to charge is announced
the same way: the item at the press, and how long it will take — at the
press too wherever the game's data names the item's warm-up (it does for the
warp items), otherwise as soon as the game will say — then the last five
seconds. If it comes up later than it said, it says so again. `/heal` calls
any of it off, warm-up included.

The ladder is walked **once**, when you press. Whatever it names is what
fires, even if something better turns up during the countdown.

`warp` skips the countdown when the warp it picks is one it has to **equip and
warm up** — a Warp Ring, Warp Cudgel, Treat Staff II or Tavnazian Ring,
including one you are already wearing whose enchantment is still coming up;
the warm-up is the wait. It is never a shorter wait than the countdown, though: a
warm-up that finishes early is held until `delay` seconds have passed since
the press. Everything else fires the moment it is asked, so the countdown is
its only window.

When a warp goes, the chat is about the one that goes: the rungs it passed
over on the way (a Warp Ring on recast, an Instant Warp you do not have) are
only listed when **nothing** could go, as the reason why.

**The plan is worked out once, when you press** — and the countdown names it,
so what you were told is what fires. Lose the MP for Warp during those five
seconds and it will still try to cast it and fail, rather than quietly
spending an item you were not offered. `mr` works the same way: the mount is
picked at the press.

**The countdown length is a setting**, `//hud delay <seconds>`, one setting for
every bar - and **zero turns the wait
off** for all three actions.

The **active set** is written between the two crosses — `Set 3`, in gold,
level with the bottom row. It is there whether or not a side is held, so a set
switch is visible even on a bar you have not bound anything to yet.

**Long names are shortened on the bar**, to seven characters and a `.` — so
`Utsusemi: Ichi` reads `Utsusem.`. Only the label is cut: the binding keeps
its full name, which is what `//hud crossbar list` shows you and what the game
is sent when you press it.

A **sword** sits above it and shows whether your weapon is drawn: the
attack glyph while it is, the disengage glyph while it is sheathed. That
is the crossbar's own idea of drawn, the one that picks which set rotation
is live — so `//hud draw` flips it even with nothing targeted,
which is the point: you can put yourself in the combat rotation without
picking a fight.

**Left-click the sword** to flip the weapon state: it sheathes while drawn
and draws while sheathed, like `//hud draw` except that it never dismounts. A left-click on a slot
fires it. Those clicks and the binder are the only things the crossbar does
with the mouse outside layout mode; the cost is that the game never sees a
left-click on a slot or on the sword.

**Positioning.** In `//hud layout` you place five things independently: the
XHB, the WXHB's **left and right sides separately**, the **set label** and
the **weapon sword**. Splitting the WXHB lets it
sit at the edges of the screen, or wherever the XHB is not. Expanded Hold
follows the XHB, since it only ever appears in the XHB's place.

The set label and the sword are placed like anything else — drag one and the
bar stays where it is. Out of the box the label sits between the two crosses
and the sword just above the middle slot row. A plain right-click in layout
mode toggles the whole crossbar; SHIFT + right-click toggles the one piece
under the cursor.
