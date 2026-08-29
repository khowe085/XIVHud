# Crossbar

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
a third, though only eight slots rather than sixteen: hold **both** side keys
at once and it takes over the screen from the other two for as long as you do,
with the order you pressed them choosing between two of these. Both point at whatever set and side you
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

**An address is one word**: `<set><L|R><slot>`, so `1L1` is set 1, left side,
slot 1, and `2R8` is set 2, right side, slot 8. Four verbs — `bind`, `unbind`,
`alias` and `icon` — also take a layer prefix in front: `sub:1L6`,
`ctx:light-arts:1L3`.

The side is written in capitals on purpose: a lower-case `l` next to digits is
impossible to tell from a `1` in the game's font. You may type either case.

Slots are `1`–`8`, numbered clockwise from the top of each cluster — the
left-hand cross is slots 1–4 and the right-hand cross 5–8.

### Everyday

| Command | What it does |
| --- | --- |
| `//hud crossbar` | report the current job, the XHB's active set and weapon state, and where each view points |
| `//hud crossbar help` | list every command |
| `//hud crossbar edit` | toggle the mouse binder |
| `//hud crossbar set <1-8>` | switch the XHB's active set |
| `//hud crossbar cycle` | advance the XHB to the next set in the rotation |
| `//hud crossbar list [<set>]` | list what is bound on this job, layer by layer, marking which one wins |
| `//hud crossbar retry [on\|off]` | retry a spell, ability or weaponskill the game refused as too soon, off by default — omit the argument to report the setting |

### Binding

| Command | What it does |
| --- | --- |
| `//hud crossbar bind <address> <type> [<action>] [<target>]` | bind a slot |
| `//hud crossbar unbind <address>` | clear a slot in one layer — the one you addressed |
| `//hud crossbar alias <address> [<name>]` | change the label under a slot — omit `<name>` to clear it |
| `//hud crossbar icon <address> [<icon>]` | change a slot's icon — omit `<icon>` to clear it |
| `//hud crossbar swap <address> <address>` | swap two slots, everything about them — every layer at once, so no layer prefix applies |
| `//hud crossbar copy <JOB>` | replace this job's bindings with another job's |

**`<type>`** says what kind of thing you are binding, and decides what the
rest of the line means:

| `<type>` | `<action>` is | Example |
| --- | --- | --- |
| `ma` | a spell — including trusts and blue magic | `bind 1L1 ma "Cure IV" t` |
| `ja` | a job ability | `bind 1L2 ja "Divine Seal"` |
| `ws` | a weaponskill | `bind 1R1 ws "Savage Blade" t` |
| `item` | a usable item | `bind 2L1 item "Echo Drops" me` |
| `enchanteditem` | enchanted gear — equips it, waits out the warmup, uses it | `bind 2L2 enchanteditem "Vocation Ring"` |
| `pet` | a pet command | `bind 2R1 pet "Fight" t` |
| `mount` | one specific mount — counts down before it summons, like `mr` | `bind 3L1 mount "Chocobo"` |
| `ra` | *nothing* — ranged attack takes a target only | `bind 1R4 ra t` |
| `ct` | a chat command, without its slash | `bind 4L1 ct "sea all linkshell"` |
| `ex` | a Windower command, run as typed | `bind 4L2 ex "exec pull.txt"` |
| `open` | the name of a game screen | `bind 5L1 open map` |
| `draw` | *nothing* — sheathe / unsheathe | `bind 1L5 draw` |
| `mr` | *nothing* — mount roulette | `bind 3L2 mr` |
| `warp` | *nothing* — best available warp | `bind 6L1 warp` |

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

**Wrap `<action>` in quotes** if it contains a space — and quote it whenever
its last word could be mistaken for something else, because the quotes settle
the question outright. Unquoted, the last word is a target only when it is one
of the tokens above; anything else is taken as part of the action's name, so
`ws Savage Blade Zeid` binds a weaponskill called "Savage Blade Zeid". Where
the addon can tell the shorter name is a real action and the longer one is
not, it refuses instead of binding something that could never fire, and where
it cannot tell it says which reading it took.

**A player's name is not a target.** Use a token above — `t` for whoever you
have targeted, `p1`–`p5` for a party member.

**`copy` replaces.** `//hud crossbar copy WHM` puts WHM's bindings on this job
wholesale — its sets, its subjob overrides and its contexts, over the top of
whatever this job had. There is no undo and no confirmation step. Shared sets
are not involved either way: they belong to no job, which is why `copy` takes
a job and refuses `SHARED`.

**`reset` deletes every job's bindings, not just this one's.** `//hud reset
crossbar` restores the component's own settings *and* empties its store —
every `<JOB>.lua` file and `SHARED.lua` with them, for every job you have ever
bound, on the character you are playing. `//hud reset all` does the same to
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

Both follow the same layer prefixes as `bind`, so aliasing
`ctx:light-arts:1` relabels only what that context puts in the slot. Both need
something in the slot to act on — on an empty one they report an error rather
than doing nothing quietly, and `icon` says so too if it cannot find the name
you gave it.

**`<icon>` is the name of a picture, not an action.** The addon's own icons are
named by their path inside its icon pack, so a top-level one is a bare word —
`map`, `mount`, `attack` — and one in a folder keeps the folder:
`items/warp-ring`, `mounts/chocobo`, `weapons/sword`.

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
a file after a built-in one replaces it everywhere: an `icons/custom/attack.png`
becomes the picture on every Attack slot without you re-pointing anything.

The folder is **flat**, and that is how it is searched: only the last part of a
name is looked for there. `icon 6L1 items/warp-ring` checks
`icons/custom/warp-ring.png` first and the addon's own `items/warp-ring` after
— you never make an `items` folder of your own.

`bind`, `unbind`, `alias` and `icon` take an optional layer prefix on the set
number — `sub:<set>` for the current subjob, `ctx:<name>:<set>` for a buff
context. With no prefix you are editing the job's base layer. See
[Layers](#layers-how-a-slot-decides-what-to-show).

```
//hud crossbar bind 1L3 ma "Cure IV" t
//hud crossbar bind sub:1L4 ja "Utsusemi: Ichi"
//hud crossbar bind ctx:light-arts:1L3 ja "Addendum: White"
```

Most of this is also bindable by mouse in `//hud crossbar edit`, which is
usually easier — the binder lists what you actually know rather than asking
you to spell it. `ct`, `ex` and `pet` are the exceptions: those three are
command-only. Enchanted gear the binder does list, under **Enchanted** — it
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
| `//hud crossbar draw` | sheathe / unsheathe — or dismount, if mounted |
| `//hud crossbar mr` | summon a random mount you own, or dismount if you are on one. Summoning waits five seconds first — see **Travel waits five seconds** below |
| `//hud crossbar warp [all]` | warp home by the best means you have, after the same five-second wait; `all` warps your other characters running XIVHud, and sends them only when this character's own warp actually goes |
| `//hud crossbar sneak` | picks the cheapest way this character has to get the effect and fires it: the ninjutsu first (Monomi: Ichi / Tonko: Ichi, if you have the tool), then Spectral Jig, then the spell, then a Silent Oil / Prism Powder. The order is the same on every job, so the press behaves the same wherever it is bound; what changes is which rungs you qualify for, which is read from the client - the spells you know and the levels your main and sub actually have. Self-only rungs stay on you; the spell and the item go to a targeted party member if you have one selected. |
| `//hud crossbar invisible` | the same ladder for invisible |
| `//hud crossbar open <name>` | open a game screen (`map`, `equipment`, …) |

---

## Steam Input mapping

The addon reads keys. Turning a controller into those keys is Steam Input's
job, so nothing here is enforced by the addon — any layout that emits the
right keys works, and a keyboard player can press them directly.

Six keys drive everything, chosen because the crossbar can take them cleanly
— the game either does nothing with them or gives them up when asked:

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

**No modifiers are used**, deliberately. FFXI's own macros live on Ctrl and
Alt plus the number row, and the game acts on those chords by a route addons
cannot intercept — so a crossbar built on them would fire a macro every time
you pressed a slot. Using keys the game ignores leaves your macro palette
completely alone.

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
WXHB as two halves you can place apart from each other, and the skillchain
indicator — so a permanently-visible WXHB can live wherever the XHB is not.

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

- On Scholar the slot holds **Light Arts** — the job's own base, since sets
  are per job unless you share them.
- Use Light Arts, and the `light-arts` context activates — the same slot
  becomes **Addendum: White**.
- Use that, and the `addendum-white` context activates — a whole WXHB side
  turns into the spells it unlocks.
- Your four stratagem slots hold the light stratagems under Light Arts and
  the dark ones under Dark Arts, automatically.

Contexts ship with the addon; you fill in what goes in them. The list today is
Scholar's four — `light-arts`, `dark-arts`, `addendum-white`, `addendum-black`
— and `//hud crossbar context list` shows them and which are live.

### Editing without guessing

The reason the binder is mouse-driven is that layers are easy to get lost in.
In edit mode:

- Every slot is **tagged with where its content comes from**, before you click
  anything: `+` for a subjob override, `*` for a buff context, nothing at all
  for the job base or a shared set. The tags leave with edit mode.
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
you are editing, and leaves every other layer alone. Dragging an action out
of the list does nothing; the three steps are the way to bind. Empty means
empty: a drop that lands on any part of the binder — the window, the bar
itself — cancels quietly and changes nothing. Empty screen really is the
whole rest of the display, so a near miss is the easiest mistake to make, and
it must never be the one that deletes.

**One window, three steps.** Edit mode draws nothing until you click a slot.
Then a single window opens dead centre and walks you through:

1. **Pick a layer** — base (or shared), your worn subjob, and every context.
   Picking a context previews the bar as if that buff were up.
2. **Pick an action** — categories down the left, one page of actions on the
   right, the wheel to page through them.
3. **Pick a target** — every FFXI token, with `(no target)` first. Actions
   that cannot take a target skip this step and bind straight away.

A **details column** on the right shows whatever the cursor is over: name,
cost, recast, skillchain property, and for a slot the layer its binding comes
from. **Back**, in the top left, steps back one screen — and closes the window
from the first, so you never have to click empty space to get out.

Binding lands you back on step one, ready for the next edit on the same slot.

**Moving it.** Drag the window by its title strip — the top row, to the right
of the back button. Where you leave it is remembered per character, so it opens
there next time rather than back in the middle. It is always kept fully on
screen, including a position saved at a resolution you no longer play at.

The window does not dodge the bar. If you have put the bar in the middle of
the screen the window will cover it, and slots underneath cannot be clicked or
dropped onto while the binder is open.

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
`//hud layout` is up.

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

Sharing a set that already holds job-specific bindings does not merge the two.
The shared copy takes the slots over, and this job's own bindings for that set
go **dormant** — they stay in the file and come back the moment you share the
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
job was left — on a setup whose low sets are combat-only, arriving on set 1
meant arriving outside the sheathed rotation entirely. The consequence is that
the active set is not remembered per job: a job always resumes at the front of
the rotation its current weapon state belongs to.

If **no** set is flagged for the state you are entering — or every set that is
happens to be empty — the active set is left where it is. There is nowhere to
land, and stranding the bar on nothing would be worse than staying put.

Going *in* sends nothing to the game: `draw` while sheathed only flips the
addon's state and lights the sword, so it never picks a fight for you and
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
it and the crossbar equips the piece, holds GearSwap off that slot so it
cannot be swapped straight back out, waits for the enchantment to come up,
uses it, and releases the slot again. If the piece is already on when you
press it, the crossbar cannot tell *which* slot it is on — a ring could be
either — so it holds **both**, and releases both afterwards. If you keep a
slot disabled in GearSwap yourself, that release will re-enable it.
If the item is already worn and charged it simply fires.

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
If you press one while a `warp` countdown is running, the warp is dropped
when its countdown ends rather than queued behind the item, and `warp all`
does not send your other characters.
Unlike `mount`, `mr` and `warp`, an enchanted item takes **no** five-second
countdown: the warmup already is the wait.

**Its target is settled when you press it**, not when it fires. Gear is
normally worn by you and needs no target at all, but if you do bind one —
`enchanteditem "X" t` — the press pins whatever you had targeted and sends
that, so a wait of half a minute cannot land the item on something you
tabbed to since. A target the press cannot settle is refused outright
rather than left to resolve later: pressing with nothing targeted says so,
and a pick-a-target cursor (`st` and friends) cannot be bound to one of
these at all.

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

| Type | What it does |
| --- | --- |
| `draw` | sheathe / unsheathe, and dismount when mounted. Its icon follows the state. |
| `mr` | mount roulette — picks at random from the mounts you actually own, and dismounts if you are already up. In the binder it is filed at the head of **Mounts** rather than under General, and it only appears if you own something to ride. |
| `mount <name>` | summons that mount, or dismounts if you are already up |
| `warp` | picks the best warp you have, in order: the Warp or Warp II spell, then a Warp Ring, an Instant Warp, a Warp Cudgel, a Treat Staff II, and a Tavnazian Ring as the last resort. The scroll sits above the two weapons because it costs no swap and no warm-up. Equips the ring or cudgel for you and waits out the enchantment — though if it has more than about 30 seconds left to charge it gives up rather than waiting. The Tavnazian Ring is allowed longer, because its own warm-up is roughly that. A piece already on your finger is not assumed to be ready either: if its enchantment is still coming up, the crossbar waits it out for you, the same as it would for a ring it equipped itself. `warp all` sends your other characters running XIVHud home — when this character's warp actually fires, so calling the countdown off, or a ring warm-up that gets abandoned, leaves them where they are. |
| `sneak` / `invisible` | picks the cheapest way this character has to get the effect and fires it: the ninjutsu first (Monomi: Ichi / Tonko: Ichi, if you have the tool), then Spectral Jig, then the spell, then a Silent Oil / Prism Powder. The order is the same on every job, so the press behaves the same wherever it is bound; what changes is which rungs you qualify for, which is read from the client - the spells you know and the levels your main and sub actually have. Self-only rungs stay on you; the spell and the item go to a targeted party member if you have one selected. Both take the White Magic icon whichever rung fires, so the slot's face does not change with your subjob. |
| `open <name>` | opens a game screen |

`mr` and `warp` count five seconds down before they go, and so does the
`mount` type above — see **Travel waits five seconds** under Extras.

**A mount slot greys out when you cannot ride.** Two things put it down: a
zone that forbids mounting — a city, a dungeon — and the minute after you
summon one, which sweeps round as a recast like anything else. Neither
applies while you are already mounted, because then the press dismounts you,
and getting off is never held up.

The minute is counted by the addon rather than read from the game: FFXI
exposes recasts by ability, and mounting is not an ability, so there is no
timer to read. It starts when the summon is sent. That means a summon the
game turns down for a reason the addon cannot see will still grey the slot
for the minute — and a zone it cannot identify never greys it at all, since
a slot wrongly greyed is worse than a press the game refuses out loud.

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

`//hud crossbar open` prints this list in game.

Most of these are chat commands the game already has, so they are reliable.
**`equipment` and `inventory` are the exceptions**: FFXI has no command for
them, so those two work by pressing Ctrl+E and Ctrl+I for you — and the keys
are *held* for a quarter second, because the game reads the keyboard once a
frame and a press released inside that frame is never seen at all. That makes
them the fragile pair — they stop working if you have rebound those keys in
the game's own settings, and not every FFXI window can be opened this way.

---

## Extras

**Recasts** sweep as a radial arc around the slot.
**Costs** show MP or TP in the corner. Actions you cannot use dim.

**Skillchains** get two things: a window indicator you can position anywhere,
and — while a skillchain window is open on your target — every bound
weaponskill, job ability and pet ability swaps its icon for the skillchain
property it *would* make right now. A weaponskill you cannot yet pay for shows
the property dimmed, with its TP cost still up.

**Stratagem counts** show on the Scholar abilities that spend them.

**Ninja tool counts** show on ninjutsu slots — how many of that tool you are
carrying, and the slot crossed out when you have none. The colour tells you
where the count is coming from: **green** when you have more than fifty of the
tool itself, **yellow** when it takes your master tools to get there, **red**
when even together they are under fifty. On main Ninja the
count includes your master tools; on `/NIN` it counts the plain tool only.
Corsair cards are counted the same way, including Trump Cards.

**Cast retry** smooths back-to-back casting. Cast two spells in quick
succession and the game sometimes answers *"Unable to cast spells at this
time"*, and that press is gone. With retry on, the crossbar sends the spell
again a moment later, giving up after a few tries. **Abilities and
weaponskills are retried the same way**, each on the refusal the game answers
it with. It only ever reacts to
that refusal, so a press the game accepted is never delayed, and it holds
nothing for more than a few seconds — press something else, change job, zone,
die, or take a cutscene, and the held spell is dropped rather than fired at
whatever you are pointed at by then.

**It fires at the target you pressed against.** A spell bound to `<t>` or
`<bt>` has that target remembered as you press, and the retry addresses it
directly rather than re-reading `<t>` — so tabbing to something else in
between changes nothing, and the retry can never wander onto a new mob. It also drops the spell rather than
retrying it if the ground has moved under it: the slot has been rebound, the
MP has gone, or you have been silenced — and it will not re-send into an open
chat line, the binder, or `//hud layout`. **A spell on cooldown is never
held**; that press fails as it always did.

**What it will not retry.** Items, chat lines, console commands and the
built-ins — nothing refuses those in words the crossbar reads. Pet abilities:
a blood pact goes out as its own command and nobody has seen how the game
refuses one. Anything bound to a subtarget (`<stpc>` and the rest), which
would re-open the selection cursor after you had already answered it. Anything
aimed at a **party or alliance slot** (`<p3>`, `<a13>`) — a position is
whoever is standing in it, and someone leaving or zoning would send the retry
at the wrong person. The retry only ever holds a slot aimed at **`<t>`,
`<bt>`, `<me>` or `<pet>`**; the other target words (`<ft>`, `<r>`, `<scan>`,
`<lastst>`, `<stal>`) are left alone too. And **a slot bound in the binder**: `//hud crossbar edit`
writes the action without a target word, and with no target on the press there
is nothing to pin the re-send to. To get the retry on a slot, bind it from the
command line with a target — `//hud crossbar bind 1L5 ma "Cure IV" t`.

It **ships off**: the refusal it listens for has not yet been confirmed in a
live client, so turn it on with `//hud crossbar retry on`. Switching it off
takes effect at once, dropping a spell already held rather than letting a last
one through. If you run Selindrile's GearSwap files, turn **MiniQueue** off
(`gs c toggle MiniQueue`) before turning this on — otherwise both systems
retry the same press on different timers.

**Travel waits five seconds.** `mount`, `mr` and `warp` do not go the moment
you press them. They count five seconds down in chat, and only then act — so a
mis-pressed warp costs you five seconds of reading rather than a trip back from
your Mog House. It reads:

```
crossbar: Mount roulette in 5 seconds. /heal to cancel.
4...
3...
2...
1...
```

The line that names the trip and the one that cancels it are prefixed like
everything else the crossbar says; the bare counts are not.

**Resting calls it off**, and `/heal` is the way in — but it is your *status*
that is watched, not the command, so sitting down by any other means stops it
just as well. So does zoning, dying, changing job, and anything that takes the
bar off screen while it counts — a cutscene, or hiding it yourself. Each of
them says `crossbar: Mount roulette cancelled.` rather than going quiet. Nothing survives
the moment it was pressed in.

**So does opening a config mode.** `//hud layout` and `//hud crossbar edit`
each call a pending trip off, and one you ask for while either is already open
is refused outright — `crossbar: Mount roulette - not while //hud layout is
open` — rather than counting down to nothing. A late action goes only where a
fresh press would, and you are not playing while you are arranging the HUD.
`//hud reset crossbar` drops a countdown too, quietly: after a reset there is
nothing left of the setup that armed it. Dismounting still works in either mode,
being instant rather than late.

**Typing in chat does not stop it.** Answering a tell while you wait to warp is
playing, so the countdown runs on — only resting, the transitions above and the
config modes call it off.

Other slots carry on as normal while it counts — curing something is not a
change of mind, and it neither cancels the trip nor waits for it. **A second
trip does replace the first**, though: press `warp` while a mount is counting
down and only the warp goes, on a fresh five seconds.

**Two things deliberately do not wait.** Getting *off* a mount is instant —
`mr` while you are mounted — and a slot bound to a **named** mount does the
same, dismounting rather than summoning — and `draw`, which dismounts as its
first job.

The countdown tells you **which** way you are going home — `Warp Ring in 5
seconds`, not a bare `Warp` — and only the last five seconds are counted out
loud. A warp that has to put a ring on and wait for it to charge is announced
the same way: the item at the press, how long once the game will say, then the
last five seconds. `/heal` calls any of it off, warm-up included.

The ladder is walked **once**, when you press. Whatever it names is what
fires, even if something better turns up during the countdown — a line that
promised one thing while another went would be worse.

And
`warp` skips the countdown when the warp it picks is one it has to **equip and
warm up** — a Warp Ring or Warp Cudgel you are not already wearing. Putting it
on and waiting out its enchantment is the same window this feature exists to
give you, so five more seconds on top buys nothing. Everything else counts
down, including a ring you are already wearing with its charge ready: that one
fires the moment it is asked, so the countdown is the only window it has.

**The plan is worked out once, when you press** — and the countdown names it,
so what you were told is what fires. Lose the MP for Warp during those five
seconds and it will still try to cast it and fail, rather than quietly
spending an item you were not offered. `mr` works the same way: the mount is
picked at the press.

A mount bound from `//hud crossbar edit` reads back lowercase — `Mount chocobo
in 5 seconds.` — because the mount list the binder is built from is lowercase
all the way to the command it sends.

**The five seconds are a setting**, `delay`, in `data/<Character>/crossbar.lua`
— in seconds, and **zero turns the wait off** for all three actions. That is
the off switch, so there is no separate toggle.

The **active set** is written between the two crosses — `Set 3`, in gold,
level with the slots. It is there whether or not a side is held, so a set
switch is visible even on a bar you have not bound anything to yet.

**Long names are shortened on the bar**, to seven characters and a `.` — so
`Utsusemi: Ichi` reads `Utsusem.`. Only the label is cut: the binding keeps
its full name, which is what `//hud crossbar list` shows you and what the game
is sent when you press it.

A **sword** appears above it while your weapon is drawn. That is the
crossbar's own idea of drawn, the one that picks which set rotation is
live — so `//hud crossbar draw` lights it even with nothing targeted, which
is the point: you can put yourself in the combat rotation without picking a
fight.

**Positioning.** In `//hud layout` you place six things independently: the
XHB, the WXHB's **left and right sides separately**, the **set label**, the
**weapon sword**, and the skillchain indicator. Splitting the WXHB lets it
sit at the edges of the screen, or wherever the XHB is not. Expanded Hold
follows the XHB, since it only ever appears in the XHB's place.

The set label and the sword used to be pinned to the XHB at a fixed offset,
so the only way to move either was to move the whole bar. They are now
placed like anything else — drag one and the bar stays where it is. Out of
the box they land where they always drew, except that the sword sits higher
and is half again as big: its foot rests just above the middle slot row,
well clear of the label below it. Both are still one widget for visibility — a right-click toggles
the crossbar entire, not a piece of it.
