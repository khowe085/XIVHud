# Crossbar

> **Not built yet.** This page describes the component as planned, so the
> design can be read and argued with before it exists. Nothing here works in
> a client today.

## What it is

FFXIV's Cross Hotbar, for FFXI. A bar of sixteen slots sits on your HUD,
arranged as four-slot crosses — D-pad clusters and face-button clusters, eight
slots on its **left side** and eight on its **right**. Each slot shows what is
bound to it, whether it is ready, and what it costs.

Each side has two states. Hold one of two **side keys** and that side is
**active**: a panel is drawn behind it, and its eight buttons fire what they
show. Let go and it is inactive again.

Those sixteen slots are a **set**, and you have eight sets. Tapping the
**switch key** moves to the next one; holding it and pressing a button jumps
straight to a numbered set.

Two more bars exist beyond that. The **WXHB** is a second sixteen slots,
reached by holding the **layer key** with a side — you can keep it on screen
permanently or have it appear only when you reach for it. **Expanded Hold** is
a third, reached by holding **both** side keys at once, and it takes over the
screen from the other two for as long as you hold them; the order you press
them in chooses between two of these. Both point at whatever set and side you
tell them to, so they are extra bars rather than extra storage.

Sets can be **shared** across every job or kept to one, and individual slots
can be overridden for a particular subjob.

Slots can also change themselves while a buff is up. A Scholar can put
**Accession** on a slot for when Light Arts is active and **Manifestation** on
that same slot for Dark Arts: one button, the right stratagem under each art,
with nothing to switch by hand.

Bindings are made with the mouse: `//hud crossbar edit` opens a binder, you
click a slot, pick which layer you are editing, and pick an action.

Everything is driven by keys, so **a controller is optional**. Pad support is
a Steam Input layout that presses those keys for you; from a keyboard you
press them yourself.

## Commands

All commands are `//hud crossbar …`. Verbs and names are case-insensitive.
`<slot>` accepts `1`–`8` or button names (`y`, `b`, `a`, `x`, `up`, `right`,
`down`, `left`). `<side>` is `l` or `r`.

### Everyday

| Command | What it does |
| --- | --- |
| `//hud crossbar` | report the current job, the XHB's active set, and where each view points |
| `//hud crossbar edit` | toggle the mouse binder |
| `//hud crossbar set <1-8>` | switch the XHB's active set |
| `//hud crossbar cycle` | advance the XHB to the next set in the rotation |
| `//hud crossbar list [<set>]` | list what is bound on this job |

### Binding

| Command | What it does |
| --- | --- |
| `//hud crossbar bind <set> <l\|r> <slot> <type> <action> [<target>]` | bind a slot |
| `//hud crossbar unbind <set> <l\|r> <slot>` | clear a slot |
| `//hud crossbar alias <set> <l\|r> <slot> [<name>]` | change the label under a slot — omit `<name>` to clear it |
| `//hud crossbar icon <set> <l\|r> <slot> [<icon>]` | change a slot's icon — omit `<icon>` to clear it |
| `//hud crossbar swap <set> <l\|r> <slot> <set> <l\|r> <slot>` | swap two slots, everything about them |
| `//hud crossbar copy <JOB>` | seed this job's bindings from another job |

**`<type>`** says what kind of thing you are binding, and decides what the
rest of the line means:

| `<type>` | `<action>` is | Example |
| --- | --- | --- |
| `ma` | a spell — including trusts and blue magic | `bind 1 l 1 ma "Cure IV" t` |
| `ja` | a job ability | `bind 1 l 2 ja "Divine Seal"` |
| `ws` | a weaponskill | `bind 1 r 1 ws "Savage Blade" t` |
| `item` | a usable item | `bind 2 l 1 item "Echo Drops" me` |
| `pet` | a pet command | `bind 2 r 1 pet "Fight" t` |
| `mount` | one specific mount | `bind 3 l 1 mount "Chocobo"` |
| `ra` | *nothing* — ranged attack takes a target only | `bind 1 r 4 ra t` |
| `ct` | a chat command, without its slash | `bind 4 l 1 ct "sea all linkshell"` |
| `ex` | a Windower command, run as typed | `bind 4 l 2 ex "exec pull.txt"` |
| `open` | the name of a game screen | `bind 5 l 1 open map` |
| `draw` | *nothing* — sheathe / unsheathe | `bind 1 l 5 draw` |
| `mr` | *nothing* — mount roulette | `bind 3 l 2 mr` |
| `warp` | *nothing* — best available warp | `bind 6 l 1 warp` |

**`<target>`** is optional and takes the game's own target strings — `t` for
your target, `me`, `p1`, `stnpc` and so on. Leave it off for anything that
does not need one. Wrap `<action>` in quotes if it contains a space.

### Labels and icons

A slot shows the action's own name and icon. **`alias`** and **`icon`**
override either for one slot, which is worth it when the real name is too long
to read at a glance, or when the slot holds a `ct` or `ex` command that has no
icon of its own:

```
//hud crossbar alias 1 l 3 "AW"           -- Addendum: White, shortened
//hud crossbar icon 4 l 1 map             -- give a custom command an icon
//hud crossbar alias 1 l 3                -- back to the action's own name
```

`<icon>` is a name from the icons that ship with the addon, or a path to your
own PNG under the addon folder. Both follow the same layer prefixes as `bind`,
so aliasing `ctx:light-arts:1` relabels only what that context puts in the
slot.

`bind` and `unbind` take an optional layer prefix on the set number —
`sub:<set>` for the current subjob, `ctx:<name>:<set>` for a buff context. With
no prefix you are editing the job's base layer. See
[Layers](#layers-how-a-slot-decides-what-to-show).

```
//hud crossbar bind 1 l 3 ma "Cure IV" t
//hud crossbar bind sub:1 l 4 ja "Utsusemi: Ichi"
//hud crossbar bind ctx:light-arts:1 l 3 ja "Addendum: White"
```

Everything above is also bindable by mouse in `//hud crossbar edit`, which is
usually easier — the binder lists what you actually know rather than asking
you to spell it. See [What you can bind](#what-you-can-bind) for the fuller
picture.

### Sets

| Command | What it does |
| --- | --- |
| `//hud crossbar share <set> on\|off` | share a set across every job, or keep it to this one |
| `//hud crossbar cycle <set> drawn\|sheathed\|both\|none` | choose which rotations a set belongs to |
| `//hud crossbar view <wxhb-l\|wxhb-r\|exp-lr\|exp-rl> <set> <l\|r>` | point a view at a set and side |
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
| `//hud crossbar draw` | sheathe / unsheathe — or dismount, if mounted |
| `//hud crossbar mr` | summon a random mount you own, or dismount if you are on one |
| `//hud crossbar warp [all]` | warp home by the best means you have; `all` warps every character you are running |
| `//hud crossbar open <name>` | open a game screen (`map`, `equipment`, …) |

---

## Steam Input mapping

The addon reads keys. Turning a controller into those keys is Steam Input's
job, so nothing here is enforced by the addon — any layout that emits the
right keys works, and a keyboard player can press them directly.

Six keys drive everything, chosen because FFXI does nothing with them:

| Key | Role |
| --- | --- |
| `[` | left side — hold to show it |
| `]` | right side |
| `\` | the W-layer — hold with a side for its WXHB bar |
| `` ` `` | set switch — tap to cycle, hold and press a button to jump; ignored while a side is held |
| `=` | Select — opens your map; with a side held, opens the binder |
| `1`–`8` | the eight slots |

**No modifiers are used**, deliberately. FFXI's own macros live on Ctrl and
Alt plus the number row, and the game acts on those chords by a route addons
cannot intercept — so a crossbar built on them would fire a macro every time
you pressed a slot. Using keys the game ignores leaves your macro palette
completely alone.

A controller layout that produces them:

| Pad input | Emits | You get |
| --- | --- | --- |
| **LT** held | `[` | activates the XHB's left side |
| **RT** held | `]` | activates its right side |
| **LT + RT** | both | Expanded Hold takes over the screen — which one depends on the order you pressed them |
| **LT + LB** | `\` | activates the WXHB's left side (bringing it on screen if it was not) |
| **RT + RB** | `\` | the WXHB's right side |
| **LB** tapped | `R` | autorun, native game functionality — the crossbar does not read it |
| **LB** long-pressed | `\` | held for the draw gesture below |
| **RB** | `` ` `` | tap cycles sets; hold and press a face button to jump to one (no trigger held) |
| **Select** | `=` | your map; with a side held, the binder |
| **face / D-pad** while LT, RT or RB is held | `1`–`8` | the eight slots |

### Button chords

Several controls mean different things depending on what else is held, and
setting those up is most of the work of building the layout. All of it is done
with **button chords** — a binding that only fires while another button is
held. Nothing here uses action sets or mode shifts.

**The face buttons and D-pad carry the eight slots — but only while you are
reaching for the crossbar.** The rest of the time they have to be your normal
game buttons, or you cannot play.

| Control | Nothing held | LT, RT **or RB** held |
| --- | --- | --- |
| Y / B / A / X | your usual bindings | `1` `2` `3` `4` — face cluster |
| D-pad ↑ → ↓ ← | your usual bindings | `5` `6` `7` `8` — D-pad cluster |

Each of the eight buttons gets its normal binding plus **three chords** — one
for LT held, one for RT, one for RB — each emitting the same number:

```
Y     → normal binding
      + chord (LT held) → 1
      + chord (RT held) → 1
      + chord (RB held) → 1
B, A, X, D-pad ↑ → ↓ ←   ... the same, for 2 through 8
```

Twenty-four chords in total. It is repetitive to enter, but each one is
explicit and independent of the others.

**RB needs its chords too, not just the triggers.** Jumping to a set is
`` ` `` held plus a slot button — leave RB out and you have a switch key with
no numbers to press against it, and set jumping does nothing at all.

**The bumpers each carry two or three meanings**, so they need a regular
press, a long press, and a chord rather than one plain binding:

| Control | Regular press | Long press | While its trigger is held |
| --- | --- | --- | --- |
| LB | `R` (autorun) | `\` — the draw-gesture hold | `\` — WXHB left |
| RB | `` ` `` — cycle / jump | — | `\` — WXHB right |

Two more things:

- **Set switching only works when no side is held.** Holding a side means you
  are using the crossbar, so the switch key is ignored until you let go — on
  the pad this falls out naturally, since RB is `\` while RT is held.
- **Nothing should chord Select.** It is `=` in every state, so the binder and
  the map stay reachable no matter what you are holding.

**Sheathe / unsheathe** is a gesture: hold **LB**, tap **RB**. Mounted, the
same gesture dismounts.

---

## What is on screen

While the component is visible, this is what you see:

| While you hold | XHB | WXHB | Expanded Hold |
| --- | --- | --- | --- |
| nothing | on screen, inactive | on screen, if configured | hidden |
| an XHB side | **that side active** | as above | hidden |
| a WXHB side | on screen, inactive | **on screen, that side active** | hidden |
| both side keys | hidden | hidden | **on screen, active** |

The active side is marked with a panel drawn behind it, so it is obvious
which eight buttons are live.

Whether the WXHB rests on screen is up to you — `//hud crossbar wxhb on|off`.
Off, it appears only while you are holding for it, which keeps the resting HUD
to sixteen slots; on, both bars sit there permanently, thirty-two slots, with
nothing appearing or disappearing as you play.

**Expanded Hold takes the screen over.** It is up only while both side keys
are down, and it hides the XHB and WXHB for that time; release either key and
you are back to whatever you had before.

Each of these bars is positioned separately in `//hud layout`, along with the
skillchain indicator, so a permanently-visible WXHB can live somewhere the
XHB is not.

## Layers: how a slot decides what to show

A slot holds a small stack rather than a single action, and the topmost layer
with something in it wins:

```
buff contexts    ← Light Arts, Addendum: White, …   (only while the buff is up)
subjob overrides ← just for RDM/NIN, say
job base         ← every subjob shares this
shared sets      ← the same on every job
```

The point is that **you only say a thing once**. A slot that should be the
same on RDM/NIN and RDM/WHM is set on the job base and left alone. Only the
slots that genuinely differ get a subjob override.

### Buff contexts

Some abilities only exist while a buff is up, which FFXIV has no equivalent
for — so this part is ours. A **context** is a buff the addon watches; while
that buff is on you, the context's overrides win.

Scholar is the case this was built for:

- Your base slot is a weaponskill. On Scholar, an override makes it **Light Arts**.
- Use Light Arts, and the `light-arts` context activates — the same slot
  becomes **Addendum: White**.
- Use that, and the `addendum-white` context activates — a whole WXHB side
  turns into the spells it unlocks.
- Your four stratagem slots hold the light stratagems under Light Arts and
  the dark ones under Dark Arts, automatically.

Contexts ship with the addon; you fill in what goes in them.
`//hud crossbar context list` shows them and which are live.

### Editing without guessing

The reason the binder is mouse-driven is that layers are easy to get lost in.
In edit mode:

- Every slot is **tagged with where its content comes from**, before you click
  anything.
- Clicking a slot opens its **whole stack** — every layer, what each holds,
  and which one is currently winning.
- **You must pick a layer before the action list unlocks.** Nothing is
  assumed, and the layer you are editing is on screen the whole time.
- Clicking a layer row also **previews the crossbar as if that buff were up**, so
  you can build your Addendum side while looking at your Addendum side.
- Nothing is remembered between slots. Click elsewhere and the choice resets.

You can also **drag**: from the action list onto a slot to bind it, from a
slot onto another slot to swap them entirely, or from a slot onto empty space
to clear it — which removes it from the layer you are editing, and leaves
every other layer alone.

---

## Sets, sharing, and cycling

There are **eight sets in memory**, always. Cycling puts one of them on the
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
back when the mob dies. Only sheathing yourself takes you out of combat mode,
so a set rotation does not lurch back mid-pull.

---

## What you can bind

### Game actions

| Type | For |
| --- | --- |
| `ma` | spells — including trusts and blue magic |
| `ja` | job abilities |
| `ws` | weaponskills |
| `item` | usable items |
| `pet` | pet commands |
| `mount` | a specific mount |
| `ra` | ranged attack |

### Text and scripts

| Type | For |
| --- | --- |
| `ct` | a single chat command, e.g. `ct "sea all linkshell"` |
| `ex` | a raw Windower command — including `exec <script>`, which runs a multi-line Windower script. This is the closest thing to a macro. |

FFXI's own macro palette cannot be triggered by an addon, so `ex` with a
script is the way to put a sequence on a slot.

### Built-ins

| Type | What it does |
| --- | --- |
| `draw` | sheathe / unsheathe, and dismount when mounted. Its icon follows the state. |
| `mr` | mount roulette — picks at random from the mounts you actually own, and dismounts if you are already up |
| `warp` | picks the best warp you have: Warp, Warp II, Warp Ring, Warp Cudgel, Instant Warp. Equips the ring or cudgel for you and waits out the enchantment. `warp all` sends every character you have running home. |
| `open <name>` | opens a game screen |

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

`//hud crossbar open` prints this list in game.

Most of these are chat commands the game already has, so they are reliable.
**`equipment` and `inventory` are the exceptions**: FFXI has no command for
them, so those two work by pressing Ctrl+E and Ctrl+I for you. If you have
rebound either of those in the game's own keyboard settings, that opener will
not work until the table is updated to match.

---

## Extras

**Recasts** sweep as a radial arc around the slot, the way FFXIV draws them.
**Costs** show MP or TP in the corner. Actions you cannot use dim.

**Skillchains** get two things: a window indicator you can position anywhere,
and — while a skillchain window is open on your target — every bound
weaponskill swaps its icon for the skillchain property it *would* make right
now.

**Stratagem counts** show on the Scholar abilities that spend them.

**Ninja tool counts** show on ninjutsu slots — how many of that tool you are
carrying, with the slot crossed out when you have none. On main Ninja the
count includes your master tools; on `/NIN`, which cannot use them, it does
not. Corsair cards work the same way, counting Trump Cards.

**Positioning.** The XHB, the WXHB and the skillchain indicator each move and
scale independently in `//hud layout`.
