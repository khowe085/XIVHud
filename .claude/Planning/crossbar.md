# Crossbar — component plan

Status: draft, 2026-08-07 (post blind-review round 10; all open questions
resolved). Scope: one component, `src/components/crossbar/`, on the
framework from [xivhud-implementation.md](xivhud-implementation.md). Depends on
framework M1 (render loop), M2 (layout mode) — **and on framework changes that do not exist
yet** — always-on keyboard and mouse dispatch that can block input, a
multi-anchor widget contract, new ctx deps and event forwarding, and a
directory config store (six touchpoints, see Framework touchpoints). This
is the first component that consumes input rather than only rendering, and the first
whose widget occupies more than one place on screen.

## Goal

FFXIV's **Cross Hotbar (XHB)** for FFXI: a persistent sixteen-slot bar of
four-slot crosses — D-pad and face-button clusters, eight slots a side —
showing each bound action's icon, name, cost, recast and skillchain property.
Holding a side key makes that side **active** (panel behind it, its eight
buttons live); the bar itself is on screen either way. See the visibility
table under Deviations.

**The spec is Square Enix's XHB.** The FFXIV UI guide and the akhmorning controller
guide (References) define the behaviour.
[xivcrossbar](https://github.com/AliekberFFXI/xivcrossbar) is prior art for *how to do
this inside Windower* and the source of the artwork — it is **not** the spec, and its
input model is explicitly rejected (below).

Vocabulary, from SE's guide, used consistently from here on:

| Term | Meaning |
| --- | --- |
| **set** | 16 slots — a left side and a right side. 8 sets = 128 actions per job. |
| **side** | 8 slots activated by one key: the D-pad cross (4) + the face cross (4). Both sides of a bar are drawn; one at a time is active. |
| **XHB** | the bar showing the active set, permanently on screen. Holding a side key activates that side — FFXIV: LT → left, RT → right; ours: `[` → left, `]` → right. |
| **WXHB** | "double cross hotbar" — a second bar; FFXIV reaches it by double-tapping a trigger, ours by the `\\` layer key (v4, 2026-08-08). |
| **Expanded Hold** | a further **single side** (8 slots, not a full bar) reached by holding *both* activators (FFXIV: both triggers; ours: `[`+`]`); the press orders are distinct. |
| **view** | where WXHB / Expanded Hold get their contents: each is *pointed at* a (set, side). Bindings live only in sets. |

### Decisions (2026-08-05, Kevin)

- Component key **`crossbar`**. **Render *and* activate** — the component owns the
  bindings and executes them.
- **Nothing is copied wholesale, and none of xivcrossbar's input paradigms are
  adopted.** Taken from it: the **artwork**, the verified **geometry constants**, the
  **skillchain tables**, and the **mount roulette** behaviour. Not taken: the
  Ctrl+F1–F12 proxy map, the `unbind`-twelve-keys-at-load approach,
  `function_key_bindings.lua`, the minus/plus menu-button UI, the "bar 1–6" model,
  and the `environments` axis.
- **Slot map is ours** (below): slots **1–4 = Y, B, A, X**; slots **5–8 = D-pad Up,
  Right, Down, Left**. Both clusters clockwise from the top.
- **Hold mode only.** Toggle and Mixed activation are not implemented — not backlog,
  not planned.
- **Core features, not backlog**: **8 sets with set switching** (change-set and
  cycle), and **positioning the WXHB separately** from the XHB — via a multi-anchor
  extension to the widget contract (one widget, N draggable anchors), not a second
  registered widget.
- **Shared sets and per-weapon-state cycle lists are core** (Kevin, 2026-08-05,
  from FFXIV's hotbar settings): each set can be marked **shared** (character-wide,
  same contents on every job) or left job-specific, and each set is independently
  included in or excluded from the **cycle rotation for weapon-drawn and
  weapon-sheathed states**. Kevin's own XIV layout is the motivating example: sets
  6–8 shared + sheathed-cycle only (non-combat), sets 1–2 drawn-cycle (combat
  swapping), sets 3–4 job-specific and in no rotation — reachable only through the
  WXHB/Expanded views or a direct jump.
- **Binding model is FFXIV's**: bindings live in sets; WXHB and Expanded Hold are
  *views* configured to point at a (set, side). LT/RT show the active set.
- **Mount roulette must be bindable.**
- **Auto-warp must be bindable** (Kevin, 2026-08-08): vendor the **MyHome**
  addon as a library and expose it as the `warp` built-in — one button that
  picks the best available warp method.
- **Sheathe/unsheathe must be bindable** (Kevin, 2026-08-05): a `draw` action type
  that toggles engagement.
- **Built-in actions are dual-frontend** (Kevin, 2026-08-05): every built-in
  action is *both* a slot type *and* an `//hud crossbar <action>` command routed
  through the same execution path — `//hud crossbar draw`, `//hud crossbar mr`
  (mount roulette), `//hud crossbar open <name>` — so a plain Windower keybind
  (`//bind ^z hud crossbar draw`) or macro can trigger any of them. This is **the
  framework for bindable actions**: adding one means adding a named entry to the
  action table, and the slot frontend and command frontend both pick it up.
  Decided over an addon-owned hotkey table.
- **Open actions must be bindable** (renamed from "menu" 2026-08-06 — the list
  outgrew menus): named openers for game UI — equipment, inventory, map,
  wardrobes… — each a chat command where one exists, else key up/down events
  (Ctrl+E for equipment, via Windower's `setkey` console command — the
  mechanism Kevin validated; confirmed 2026-08-08), behind
  an extensible table so new entries are a small code addition.
- **UI**: the **ffxiv** theme, the **default** icon pack, **compact layout only**.
- **Skillchain integration is core**: the window indicator (own anchor,
  confirmed 2026-08-07) and per-slot **chain-result** icons — a bound WS/JA
  shows the skillchain it would trigger against the current resonation,
  xivcrossbar's shipped behaviour.
- **Bindings are layered (decided 2026-08-06, resolving what was Q4):**
  per slot, topmost active layer wins: buff-conditioned **context layers** over a
  sparse **subjob layer** over the **job base** (all subjobs share it) over the
  shared-set store. **Context definitions and their stack order are code** — a
  curated roster (v1: the SCH arts/addendum family from Kevin's fork), activated
  by buff-list predicates; users author only the overrides. This is the fix for
  Kevin's fork's overlay system — right model, but free-floating overlays made
  it "cumbersome and hard to wrap my head around"; here nothing about a context
  is user-defined except its contents, and every edit goes through a slot with
  its full stack visible.
- **The binder is mouse-driven (decided 2026-08-06):** `//hud crossbar edit`,
  click a slot, pick an action, bound — to the layer you chose from that slot's
  stack. Catalog v1: spells/JA/WS known to job+level (main and sub merged),
  items, mounts, trusts, and our built-ins; `ct`/`ex` stay command-line-only.
- **Input model (v4, decided 2026-08-08 after the second spike): no modifiers
  anywhere.** Two earlier designs died in-client, each to a platform fact no
  amount of reading would have given us:
  - **v1/v2** keyed the six hold states to left/right modifier variants.
    Windower delivers left and right modifiers as the *same* DIK, so the map
    could not tell them apart.
  - **v3** merged them — Ctrl/Alt as the sides, Shift as the W-layer, the
    number row as slots. It rested on `return true` blocking a key from the
    game, which the spike then disproved **for modified keys only**: with
    blocking on, `blocked` climbs on Ctrl+3 and FFXI's macro 3 fires anyway,
    while a bare 3 is swallowed cleanly. The game reads its macro chords by a
    route Windower's keyboard hook does not sit in front of. (This is also why
    xivcrossbar never hit it: Ctrl+F1–F12 are chords FFXI ignores, so it never
    needed to block a key the game wanted.)
  - **v4 draws the conclusion**: an activator never had to *be* a modifier — it
    only has to be a key the game ignores and the bridge can hold. Every slot
    press is then unchorded, and therefore blockable.

  | Role | Key | DIK |
  | --- | --- | --- |
  | XHB left | `[` | 26 |
  | XHB right | `]` | 27 |
  | W-layer | `\` | 43 |
  | Slots 1–8 | `1`–`8` | 2–9 |
  | Set switch | `` ` `` | 41 |
  | Shortcut (Select) | `=` | 13 |

  - **`[` → XHB left, `]` → XHB right**; **both held = Expanded Hold**,
    order-sensitive as in FFXIV (`[` first → `expanded_lr`, `]` first →
    `expanded_rl`).
  - **`\` is the W-layer**: `[`+`\` → WXHB left, `]`+`\` → WXHB right. A
    dedicated layer *replaces* FFXIV's double-tap, which Kevin has always found
    cumbersome and which xivcrossbar implements with a confirmed-buggy window
    (defect ⑧). `\` alone activates nothing.
  - **Set switch `` ` ``**: held + slot key jumps to that set, tapped alone
    cycles. **Draw gesture** = `\` held + `` ` `` tapped with no side active.
  - All six of these keys were verified in-client (2026-08-08) to have **no
    game function** — each merely opens the chat log, and each is blockable.
    They are ours exclusively while the crossbar is live; the chat guard hands
    them back the moment the chat box has focus, so they remain typeable.
  - **FFXI's macro palette is untouched** — Ctrl/Alt+1–0 keep working, and the
    game no longer flashes its macro bar on every crossbar hold, since we hold
    no modifier. Both were costs of v3 that v4 simply removes.
  - The map ships as **config** (a DIK table per role) with the above as
    defaults — which is what made this pivot a table edit rather than a
    redesign: the state machine, guards, blocking latch and press-order logic
    carried over from v3 untouched.
  - The bridge is Steam Input's job (AHK is out): LT/RT emit `[`/`]`, bumper
    chords emit `\`, RB emits `` ` ``, Select emits `=`. With no modifiers in
    play, Steam Input's lack of modifier reference-counting stops mattering —
    the shared-Shift release race recorded against v3 is gone.
  - Motivating pain points (Kevin, 2026-08-06, from living with xivcrossbar):
    losing F1–F12 to the proxy map while other addons want them; the Steam Input
    ref-counting trap; and double-tap misfires (tap-tap, release, tap → WXHB
    again — root-caused as defect ⑧).

## Slot map (decided 2026-08-05)

Screen layout is FFXIV-standard — the D-pad cross draws on the **left**, the face
cross on the **right**, matching the physical controller. Slot *numbers* are the
binding index within a side and start on the face cluster:

```
        [5] Up                      [1] Y
  [8] L      [6] R           [4] X       [2] B
        [7] Dn                      [3] A

   D-pad cluster                face cluster
   (left of screen)             (right of screen)
```

Both clusters run **clockwise from the top**. This differs from xivcrossbar on both
counts (it indexes the D-pad first and orders each cluster left, bottom, right, top),
so its `trigger_action` mapping is *not* reusable; only its pixel geometry is.

## What can be bound

Answering "are macros FFXI macros or Windower scripts?" — **FFXI's in-game macro
book cannot be invoked programmatically**: neither the game nor Windower exposes a
command that triggers a macro-palette slot (~90%; would be raised by finding such a
command in the Windower console command list — none is documented). The macro
equivalent here is Windower-side. The bindable types:

| Type | What it is | How it fires |
| --- | --- | --- |
| `ma` `ja` `ws` `item` `pet` `mount` | FFXI game actions — the type *is* the command word | `input /<type> "<action>" <target>` |
| — | trusts (round 7: **`/trust` is not a command word** — upstream maps its trust category to `ma`, `action_binder.lua:116`) | bound as `ma`; the catalog groups them under Trusts with trust icons |
| `ra` | ranged attack | `input /ra <target>` — no action name; `/ra` takes only a target |
| `mr` | mount roulette (see below) | dismount if mounted, else `/mount` a random owned mount |
| `warp` | auto-warp, from the vendored MyHome lib (see below) | best available of Warp / Warp II / Warp Ring / Warp Cudgel / Instant Warp |
| `ct` | a single chat/text command line | `input /<line> <target>` |
| `ex` | a raw Windower console command — **including `exec <script>`, which runs a multi-line Windower script; this is the "macro" answer** | sent as-is, no `input` prefix |
| `open` | a named game-UI opener from the extensible table | its command, or key up/down events (e.g. Ctrl+E) |
| `draw` | sheathe/unsheathe — state-aware, the XIV draw-weapon button | mounted → dismount; engaged → disengage; idle → engage the current target (see below) |

### The `draw` toggle

State-aware, in priority order (mounted first — you cannot engage while mounted,
and Kevin wants the same gesture to dismount, decided 2026-08-06):

1. **Mounted** (buff 252, already tracked for roulette) → `input /dismount`;
   the weapon-state machine does not advance.
2. **Weapon state "drawn"** → disengage, and the state machine flips to
   sheathed.
3. **Weapon state "sheathed"** → `input /attack <t>` and flip to drawn — FFXI
   has no draw-without-engage, so "unsheathe" means engage; no target → a chat
   hint, not a command error, and no state flip.

Case 2 covers the sticky-exit path: if the game already disengaged you (mob
died) the state is still drawn, so `draw` sends a disengage the game ignores
and flips you to sheathed — which is exactly the "I am done" intent.

The weapon state here is the component's own toggle (see "Weapon state is OUR
state machine" above) — the game's status is never consulted for it. The exact disengage form needs in-client verification (typing the
candidates by hand works any time; wired verification lands with CB5):
`/attack off` is the expected spelling (~80%; `/attack` bare may also toggle —
whichever proves reliable wins). Three frontends, identical behaviour: a slot, the
`//hud crossbar draw` command (for Windower binds and macros), and the
**layer-hold + switch-tap gesture** (`\\` then `` ` ``; see the hold-state
model — hold-LB + tap-RB on the pad) — so the gesture dismounts when mounted for free. Icons from the built-in action table:
`dismount` / `disengage` / `attack` by state, all in the default pack's singles.
Note the interplay: firing `draw` flips the weapon state, which flips which cycle
rotation the switch key walks — same as FFXIV.

### Built-in actions as commands

`actions.lua` keeps a table of **named built-in actions** — currently `draw`,
`mr` (renamed from `roulette` 2026-08-08 so the bind type and the command
verb are one name — `mr` is Xurion's own Mount Roulette alias, surviving in
the vendored lib's commented-out `_addon.commands`), `warp` (aliases
`mh`/`warp`, MyHome's own), and
`open <name>` for each entry in `openers.lua`. An entry carries
everything both frontends need: the execution, the command alias(es), **and the
icon a slot shows when the action is bound** — a fixed path for most (the default
pack's singles cover them: `mount` for `mr`, `items/warp-ring` for warp,
`item`/`map`/etc. for openers), or a
state-dependent choice where it matters (`draw` shows `attack` idle,
`disengage` engaged, `dismount` mounted). A slot of that type and the `//hud crossbar <name>` command
are two frontends over the same table entry, so behaviour and appearance can never
diverge, and adding a bindable action is one table entry both frontends pick up. Built-in names share the `//hud crossbar` verb space
with the authoring verbs (`bind`, `set`, `list`, …), so name collisions are
validated at load the same way the registry validates component names against
reserved command words — with one deliberate, documented exception: `open` is
both the built-in action prefix (`open <name>`) and, bare, the list verb;
likewise `cycle` — bare advances the rotation, with args it edits rotation
membership (args missing a mode → validation hint, never a silent advance).

### Mount roulette (from `libs/mountroulette/`, verified 2026-08-05)

Owned mounts = key items of category `Mounts` (excluding "trainer's whistle"),
matched against `resources.mounts` names (the KI name carries a music-note
prefix, written as **byte escapes** (`"\226\153\170"`) in our source:
`tests/sources_spec.lua:42-56` forbids non-ASCII bytes outside comments in
`src/` — FFXI chat is not UTF-8. Upstream matches with `windower.wc_match`, a
Windower global; our pure port does a plain **prefix match** — upstream's
pattern carries a trailing wildcard, so equality-after-strip would drop any
KI name with a suffix);
refreshed on **incoming chunk `0x055`** (KI update). If buff **252** (Mounted) is
up, `/dismount`; if no mounts, no-op; else `/mount "<random pick>"`. Ported as a
pure module with injected KI list, buff list, mount resources and RNG.

### Auto-warp (from `MyHome`, verified 2026-08-08 against Icydeath/ffxi-addons)

MyHome (123 lines, BSD 3-clause © 2018 from20020516) picks the best available
warp and fires it. Vendored as a library and exposed as the `warp` built-in
(Kevin, 2026-08-08). Its priority ladder, read from source:

1. **Warp** — `/ma "Warp" <me>`, requires job id 4 (BLM) main *or* sub, spell
   261 known, MP >= 100.
2. **Warp II** — spell 262, MP >= 150.
3. **Warp Ring** (item 28540, equip slot 13) — enchanted equipment.
4. **Warp Cudgel** (item 17040, equip slot 0) — enchanted equipment.
5. **Instant Warp** (item 4181) — a plain consumable (`ext.type == 'General'`).

Item search walks every **equippable** bag (`resources.bags:equippable(true)`
x `get_items(bag_id)`), skips bags whose `enabled` flag is false (with a chat
notice), and reads charges/recast through the **`extdata`** library:
`charges_remaining > 0` and `max(next_use_time + 18000 - os.time(), 0)`.

The enchanted path is the fiddly part: if the item is not already equipped it
`set_equip`s it, then polls `activation_time + 18000 - os.time()` until the
enchantment is ready, then sends `/item "<name>" <me>`. The give-up is **not
a timer** (mis-read in an earlier draft): `until ext.usable or delay > 30`
aborts when the *remaining* enchant delay exceeds 30 s — an item that needs
more than 30 s more is abandoned at once; one inside 30 s is waited out.
Blocked entirely while `player.status > 1`.

**Our deviations** (decided 2026-08-08):

- **GearSwap-safe equips.** MyHome calls `set_equip` with no coordination, so
  a running GearSwap can swap the ring straight back off before it fires. We
  adopt xivcrossbar's enchanted-item pattern instead: `gs disable <slot>`,
  equip, use, `gs enable`. **The pending-warp state machine lives in
  `crossbar.lua`** (round 11 — same ownership shape as the opener queue:
  `warp.lua` stays pure and plans; the widget schedules), and **`gs enable`
  fires on every exit path** — success, the give-up, suppression, zone,
  detach/logout — so no path leaves the slot disabled. Harmless when GearSwap
  is absent.
- **`warp all` kept**: MyHome broadcasts the bare string `'myhome'` over IPC;
  ours is namespaced — the message is **`xivhud crossbar warp`**, matched
  exactly by the receiver, so a real MyHome instance on another character
  neither triggers nor is triggered by us. Needs `send_ipc` and an
  `ipc message` forward — neither wired today.
- **English only.** MyHome carries JP item/spell names and `to_shift_jis`
  conversion; JP literals are non-ASCII, which `sources_spec` forbids in
  `src/` outside comments. English names only unless Kevin asks otherwise.
- **No `coroutine.sleep` polling.** The wait becomes framework-scheduled
  (`now` + the prerender tick), not a blocking sleep loop.
- **Bugs not to port:** `pairs(item_info)` iterates the priority list with
  `pairs`, so the documented Ring -> Cudgel -> Instant order is not actually
  guaranteed (use `ipairs`); and `log_flag` is a module-level global set once
  and never reset, so its progress message prints at most once per session.

### Recast animation: the radial sweep (decided 2026-08-08)

Kevin prefers XIVHotbar2's recast animation to xivcrossbar's, so we take the
former. Verified in the Petit Trois descendant (`lib/ui.lua:2015-2054`):

- **32 pre-rendered frames** of a radial arc (`images/cooldown/frame_01.png`
  through `frame_32.png`, 64x64 each; a `frame_00` also ships), drawn as an
  overlay sized to the slot with `fit(false)`.
- `frame = max(1, floor(fraction * 32 + 0.5))`, hidden at zero.
- **The denominator is observed, not looked up**: `cooldown_initials[row][slot]`
  remembers the largest recast value yet seen for that slot, and the fraction
  is `remaining / that`. It is raised whenever a larger value arrives, and
  cleared when the recast ends.

**Why this is also a bug fix, not just a preference.** xivcrossbar's wipe
divides by an *assumed* full recast, which is exactly why it needs the two
`> 40` clamps its author labelled "temporary bug fix" (defect ⑦) — the
assumption and reality disagree. The observed-maximum approach cannot exceed 1
by construction, since the maximum is by definition never smaller than the
current value. It also survives the addon loading mid-cooldown, which a
table-driven denominator does not.

Two consequences for us: **defect ⑦ disappears** rather than being clamped
around, and the plan needs 32 more asset files (~small, single-channel art) in
the CB4 import. **The seventh licence notice — BSD 3-clause (c) 2026 WG
Incorporated — is required regardless of the art** (round 11): `render.lua`
transcribes the sweep algorithm (observed-maximum denominator, the frame
formula) from BSD source, the same derived-source test skillchain/roulette/
warp already meet, so the notice goes in-file and in `assets/LICENSE.txt`
either way. **The frames import from Petit Trois** (decided 2026-08-08) —
the notice already covers them, so generating our own would save nothing.

### Stratagem charge counter (from Kevin's fork, verified 2026-08-08)

A count of **available SCH stratagems**, drawn in the slot's cost position on
every ability that spends one. Not in upstream xivcrossbar (`strat_charge_time` appears only in the fork
chain). Kevin's fork README lists it under Additions and its sub-SCH fix under
Fixes, but that branch is a fork of a fork, so an intermediate fork may be the
origin — attribution unconfirmed, mechanics below read from the code. Wanted
here (Kevin, 2026-08-08). Mechanics, read from
`kevin-xivcrossbar/ui.lua:1207-1228`:

- **Charges are one shared pool** on ability recast id **231**; there is no
  per-stratagem timer to read.
- **Max charges** = `floor((sch_level - 10) / 20) + 1` → 1 at L10, 2 at L30,
  3 at L50, 4 at L70, 5 at L90.
- **Job Point gift**: main SCH with `job_points.sch.jp_spent >= 550` has a
  sixth charge. Sub-SCH never does — job point gifts require the main job.
- **Recharge time depends on the charge total**:
  `{[1]=240, [2]=120, [3]=80, [4]=60, [5]=48, [6]=33}` seconds.
- **Available** (corrected round 11 — the fork's own display is buggy here):
  the fork computes `used = ceil(recast_231 / charge_time[max + gift])` but
  then displays `max - used`, leaving the gift out of the minuend — with all
  six spent that prints **−1**. Ours is
  `available = max(0, (max + gift) - ceil(recast_231 / charge_time[max + gift]))`
  — gift in both places, clamped at zero. (~85% this is what the fork meant;
  the formula stands on its own arithmetic either way.)
- Drawn only on the **sixteen** abilities that consume a charge
  (`requires_strategem`, `consumables.lua:124-141`): Addendum: White,
  Addendum: Black, Penury, Celerity, Accession, Rapture, Altruism,
  Tranquility, Perpetuance, Parsimony, Alacrity, Manifestation, Ebullience,
  Focalization, Equanimity, Immanence. **Light Arts and Dark Arts are not in
  the list** — they cost nothing, and drawing a count on them (as an earlier
  draft's "the four arts/addendum" implied) would be wrong.

**The /SCH lesson, generalised.** The bug Kevin fixed was reading the SCH level
from the main job only, so on `RDM/SCH` the level was nil and the counter never
drew. The plan already leans on main-or-sub resolution elsewhere (catalog
filtering, the arts contexts, `warp`'s BLM check), so this is stated once as a
rule: **anything keyed to a job must resolve main *and* sub, and anything keyed
to job points must resolve main only.** `crossbar_render_spec` carries the
sub-job case for the counter specifically.

### Ninja tool counts (verified 2026-08-15)

How many of a ninjutsu's tool you are carrying, drawn in the slot's cost
position — the same prim the stratagem counter uses, and never both at once,
since a ninjutsu is not a stratagem ability. Corsair Quick Draw cards ride the
same machinery. Upstream has the feature (`consumables.lua:125`); the fork
chain fixed its master-tool half ("Fixed Ninja Tools not showing a count if
using master tools").

- **Each ninjutsu maps to a tool**: `ninja_tool_lookup[spell_id] -> item id`.
- **Master tools substitute for a whole family**
  (`master_tool_lookup[tool_id] -> master id`): **Inoshishinofuda** (2971)
  covers Uchitake, Tsurara, Kawahori-Ogi, Makibishi, Hiraishin, Mizu-Deppo;
  **Shikanofuda** (2972) covers Shihei, Shinobi-Tabi, Sanjaku-Tenugui,
  Kabenro, Furusumi, Mokujin, Ranka, Ryuno; **Chonofuda** (2973) covers
  Jusatsu, Kaginawa, Kodoku, Sairui-Ran, Soshi; **Trump Card** (2974) covers
  the eight Corsair element cards.
- **Master tools count only on main NIN** — sub-NIN sums the plain tool alone
  (`ui.lua:1136-1141`). Another instance of the main-only rule already stated
  for the stratagem JP gift.
- **Display**: the total, or `99+` above ninety-nine.
- **Colour**: green when the plain tool count alone exceeds 50; yellow when
  only the total (with master tools) does; red otherwise.
- **At zero**: a red X over the slot and the recast text hidden.
- **Counts stay fresh** from the `add item` / `remove item` events the
  framework already forwards, seeded by an inventory read — no new touchpoint.

### Open actions (renamed from "menu", 2026-08-06)

A code table in the component (`openers.lua`), `name → { opener, icon }`, where
the opener is either a **chat command** (trivial — `input /...`, no key events
at all) or a **key sequence** (for game UI with no slash command). The v1 list
(Kevin, 2026-08-06):

| Name | Opener | Kind |
| --- | --- | --- |
| `equipment` | Ctrl+E | key events |
| `inventory` | Ctrl+I | key events |
| `wardrobe` … `wardrobe8` | `/wardrobe` … `/wardrobe8` | command |
| `case` / `sack` / `satchel` | `/case` `/sack` `/satchel` | command |
| `quests` | `/quest` | command |
| `linkshell` | `/sea all linkshell` | command |
| `map` | `/map` | command |

Command-based entries have none of the chord-timing complexity below — they go
through the ordinary `send_command` path and fire instantly from any side. Only
the key-event entries (equipment, inventory) need the queueing. The table grows
by small code updates.

Icons are **per entry**, not per type: `map` and the bag family have obvious
matches in the default pack's singles (`map`, `item`); equipment/quests/
linkshell have none (the `ui/` folder is chrome only — verified round 6), so
they take the fallback from day one (the pack's `ui/` folder was inventoried in round 6: chrome only — bar
backgrounds, frame steps, button glyphs — no menu icons there). Entries without a match fall back to a generic opener
glyph + the slot's name label.
The key events are sent through a `ctx.send_key_events(sequence)` dep the
entry point implements with **Windower's `setkey` console command** (named by
Kevin and **verified against docs.windower.net/commands/input, 2026-08-08**:
`setkey [keyname] [state]`, states `down`/`up`):
`windower.send_command('setkey <keyname> down')` / `('... up')`, one call per
edge, injecting only the chord keys not already physically held. The one
residue is **key-name spellings** — the docs' own text says "most key names
can be easily guessed" and links no official mapping — so `ctrl`/`e`/the
number row get a ten-second `//setkey e down` check in-client before CB2.

**Chord timing: the problem disappeared with v4** (2026-08-08). Under v3 the
crossbar held real modifiers, so firing a Ctrl+E opener from a WXHB side —
where Ctrl *and* Shift were down — would have injected into Ctrl+Shift+E, and
the plan carried an arm-and-fire-on-release queue to dodge it. **v4 holds no
modifiers at all**: the activators are punctuation, which do not participate
in chords, so an injected `ctrl`+`e` reaches the game exactly as typed no
matter what the crossbar is holding. Openers **fire immediately**, always.

That deletes the whole armed-queue mechanism — the single-arm rule, the
release-edge firing, the drop-on-suppression case, and the modifier-delta
computation with it. `actions.lua` simply emits the full `setkey` sequence.

Two recorded caveats: Kevin has only gotten *some* game UI to open via key
events, so each new key-event entry needs in-client verification, and the
sequences assume the client's default keyboard bindings (~85% that's acceptable;
a per-entry override in config would cover rebinds if it ever matters).

## XHB reference facts (from SE's UI guide + akhmorning, read 2026-08-05)

The target behaviour. SE's guide is authoritative on inputs and settings, akhmorning
on counts and practical detail.

- **Shape.** 8 sets × 16 slots = 128 actions. One side = 4 D-pad + 4 face buttons;
  both crosses draw together. LT shows the active set's left side, RT its right.
- **WXHB** in FFXIV is reached by **double-tapping** a trigger (Hold mode only),
  with a user-adjustable **WXHB input timer**. **We deviate**: WXHB is the `\\`
  layer over the XHB keys, so the double-tap, its timer, and its failure modes
  don't exist here. Each WXHB half is still configured to display a chosen
  set/side.
- **Expanded Hold** in FFXIV is reached by pressing **both triggers**; **press
  order matters**: LT→RT and RT→LT are configured separately and may point at
  different set/sides. Ours is `[`+`]` with the same order sensitivity. SE's
  advice for order-insensitivity is to point both at the same place, which the
  views config allows.
- **Set switching**, both core. FFXIV's switch button is RB/R1; ours is
  backtick (pad: RB):
  1. **Change set** — hold the switch button and press a slot button: buttons
     1–8 jump straight to sets 1–8. Jump can reach *any* set, including ones
     outside the cycle rotation.
  2. **Cycle** — press and release the switch button alone: advance to the next set
     that is **non-empty** (SE: "will ignore sets which have no registered
     actions") **and flagged for the current weapon state** (below). No timing
     window needed — the two are distinguished by whether a slot button was chorded
     during the hold.
- **Sharing and cycle lists** (FFXIV Character Config → Hotbar Settings; described
  by Kevin 2026-08-05, not re-verified against the UI guide): each set has a
  **shared** flag — shared sets show the same contents on every job, unshared sets
  are job-specific — and two cycle flags, one per weapon state, controlling whether
  the cycle rotation visits it while the weapon is drawn / sheathed.
- **Weapon state is our own state machine, with a one-way game trigger**
  (decided 2026-08-07, revised the same day after Kevin noted he usually
  engages and switches targets manually). Two transitions in, one out:

  | Event | Effect |
  | --- | --- |
  | `draw` action (command, slot, or gesture) while sheathed | → **drawn** |
  | Player engages in game (status 1 / 3, via the framework's `status` dispatch) | → **drawn** |
  | `draw` action while drawn | → **sheathed** |
  | Player disengages in game (mob dies, zoning, knocked out of engagement) | **no effect — state stays drawn** |

  The asymmetry is the point: engaging by any means should bring the combat
  rotation up, but a mob dying between pulls must not flap the bar back to the
  sheathed rotation. **Only an explicit `draw` returns you to sheathed** — it
  means "I am done fighting", and it is harmless when the game already
  disengaged you (the disengage command is a no-op, and the state still
  flips). **Initial value and lifetime** (confirmed by Kevin 2026-08-08):
  session-only, never persisted;
  starts **sheathed** on attach, login, job change and reload — and
  self-corrects on the next engagement.
- **Deferred to backlog**: auto-switch on drawing/sheathing the weapon, "return to
  XHB after WXHB input", face-buttons-only WXHB.

### The hold-state model

v4, decided 2026-08-08 — no modifiers; punctuation activators, `\` as the
W-layer, backtick as the switch. `input.lua` owns it. Rows resolve by
**most-specific held-set wins** (`[`+`\` beats `[`; `[`+`]` beats either),
with one ordering rule: the draw-gesture row outranks the bare-cycle row. The
prose rules below are normative where they elaborate:

| Input (default DIKs) | Result |
| --- | --- |
| nothing held | XHB on screen, no side active |
| `[` (26) held | XHB **left side active** |
| `]` (27) held | XHB **right side active** |
| `[` + `\` (43) held | WXHB shown if hidden, **left side active** |
| `]` + `\` held | WXHB shown if hidden, **right side active** |
| `[`+`]` held, `[` first | XHB and WXHB hidden; **`expanded_lr` shown, active** |
| `[`+`]` held, `]` first | XHB and WXHB hidden; **`expanded_rl` shown, active** |
| `\` held + `` ` `` (41) tapped, **no side active**, no slot key chorded | fire the `draw` toggle |
| `` ` `` held + slot key *n*, **no side held** | jump to set *n* (any set) |
| `` ` `` tapped, **no side held** | cycle to the next non-empty set in the current weapon state's rotation |
| slot keys `1`–`8` (DIK 2–9) with a hold state active | fire that slot |
| shortcut key (`=` 13) tapped | its `tap` verb bare / its `chorded` verb with a side held (blocked as ours, subject to the guards — in edit mode only the `edit`-verb key is live) |
| nothing held | no hold state active — every key falls through to the game (the switch and shortcut keys excepted: always ours, always blocked) |

Resolution rules:

- **The active hold state is a pure function of what is held**: nothing → none;
  `[` → XHB left; `]` → XHB right; both → the Expanded view chosen by press
  order (release one → the survivor's XHB side). **"First" means first of the
  currently-held pair** — re-pressing a released side into a still-held one
  makes the *held* one first (caught in-client 2026-08-08: `[`→`]`, release
  `[`, hold `[` again must give `expanded_rl`).
- **`\` is a layer, not a side**: with `[` → WXHB left, with `]` → WXHB right,
  in either press order; releasing it drops back to the XHB side. Alone it
  activates nothing. **`[`+`]`+`\` = Expanded unchanged** (normative: the
  layer over an Expanded pair is a no-op; Expanded has no W variant).
- **All six hold states are always available in v1** — there is no per-state
  disable (backlog if ever wanted). **Canonical hold-state ids** (CB0's intent
  payload): `xhb_left`, `xhb_right`, `wxhb_left`, `wxhb_right`, `expanded_lr`,
  `expanded_rl`. The last four deliberately share their spelling with the
  views they display; the XHB pair displays the active set directly.
  Terminology: the six activator states are **hold states** (an earlier draft
  called them "sides", colliding with *side* = a set's left/right half, the
  meaning `views`, the CLI and `bindings.resolve(set, side, slot)` all use);
  **views** are only the four configurable (set, side) pointers — config keys
  `wxhb_left`, `wxhb_right`, `expanded_lr`, `expanded_rl`, with
  `wxhb-l`/`wxhb-r`/`exp-lr`/`exp-rl` as their CLI spellings (normative).
- **The switch key is ours exclusively**: always blocked, and **inert while
  any side is held** (Kevin, 2026-08-15 — holding a side means you are using
  the crossbar, not changing sets). With no side held: tap alone = `cycle`;
  held + slot key = `jump n`; tapped while `\` is held (no slot key chorded)
  = the `draw` toggle instead of cycle. Because sides and the switch can
  never both be live, slot keys need no precedence rule between firing and
  jumping — the two cases are disjoint. On the pad this falls out of the
  layout anyway: RB is `\` while RT is held, so no switch key is emitted.
- **Shortcut keys**: dedicated keys, always blocked, that fire
  `//hud crossbar` verbs — one verb on a bare tap, another while a side is
  held. The first entry is the pad's **Select** button: bare tap → `open map`,
  tap with a side held → `edit` (toggle the binder); while edit mode is on,
  any press of this key exits it (see the edit mode guard). Default `=` (13).
- **Blocking**: per-key, **latched at press** — whether a key's press was
  blocked decides its release too (a `3` pressed unblocked whose release
  arrives after a side went down must still reach the game, or FFXI sees a key
  held forever; likewise across guard transitions). Blocked at press: slot keys
  while a hold state is active **or while the switch is held** (the set-jump
  chord must not leak bare numbers to the game), the switch always — including
  while a side is held, where it does nothing but is still ours — and shortcut
  keys always; nothing else is ever blocked. **Verified
  in-client**: an unchorded key returns cleanly to us and never reaches the
  game — the property v3 assumed and did not have.

Guards, all mandatory (tightened after blind review, 2026-08-06):

- **Chat**: while `windower.ffxi.get_info().chat_open`, emit no *action*
  intents (`fire`/`jump`/`cycle`/`draw`/`shortcut`) and block nothing —
  **`activate` is exempt** (round 8): it mirrors state, and suppressing it
  strands an active side when an activator is released mid-chat
  (`activate none` is what clears it). Consequence, accepted: pressing an
  activator while chat is open draws an inert bar over the screen — **backtick and the shortcut keys included** (round 4: they
  must be typeable into chat; "always blocked" everywhere else means "always,
  subject to these guards") — but **keep tracking key state, slot-key
  down/latch bookkeeping included** (round 11): releasing an activator while
  typing strands the hold state "active" when chat closes, and a slot key
  released during chat must clear its down-state or the next press reads as
  an auto-repeat and never fires.
- **Focus**: reset all held-state on `lose focus` (alt-tab mid-hold must not
  strand an activator "down").
- **Edge detection**: all transitions fire on state *change* only — Windows
  key auto-repeat delivers repeated `pressed=true` events for held keys, and a
  held slot key must fire its action exactly once (upstream defends with
  `just_pressed` checks; ours is structural).
- **Suppression / disabled**: while the framework suppresses the component
  (cutscene, zoning) or it is disabled, input is fully inert — nothing fires,
  nothing is blocked, every key falls through (including backtick).
- **Inbound `blocked`**: the keyboard event's own `blocked` argument (another
  addon already consumed the key) short-circuits action intents and blocking —
  **all state still tracks** (activators, slot-key down/latch bookkeeping) and
  **`activate` passes** (round 9/11: the display must mirror the physical
  keyboard even when another addon ate the key, or a blocked Ctrl-down leaves
  the model reading `none` while a side key is held and every later key
  routes wrong) (round 7; `core.on_mouse` already does this on
  its path, `core.lua:459`).
- **Edit mode** (sixth guard — the state flag ships at CB0, exercised at CB8;
  until CB8 lands, the `edit` verb and Select-chord reply "binder not yet
  available" instead of setting the flag): the exit key is **any shortcut key
  one of whose verbs is `edit`** (zero such keys → edit mode only via the
  verb; other shortcut keys are inert and unblocked in edit mode); while edit mode is on, activators, slot keys and backtick
  are inert and unblocked; the only live input is **a press of the shortcut
  key that toggles edit** (bare or chorded), which exits — that is what "any
  press exits it" means.

### Verification spike — results (run by Kevin, 2026-08-06)

Two throwaway addons, both under [spikes/](spikes/):

- **[dikecho](spikes/dikecho/dikecho.lua)** — answers *what DIKs arrive*
  (`//lua load dikecho`; `//dik echo`).
- **[inputspike](spikes/inputspike/inputspike.lua)** — added 2026-08-08,
  answers *does the model work and does blocking hold*. A working prototype of
  `input.lua`: the full v3 hold-state resolution with an on-screen readout,
  selective blocking with the latch-at-press rule, and every guard (chat,
  focus, auto-repeat edge detection, inbound `blocked`). Blocking starts OFF;
  the handler is wrapped so an error disables blocking rather than swallowing
  the keyboard, and `//is panic` kills it from the chat box. It closes spike
  items 2 and 6 outright and item 4 partially (held-state booleans, not an
  ordered event log); item 5 (injected-key echo) still needs dikecho plus
  Kevin's send tool, since inputspike injects nothing. De-risks CB0 by
  proving the design before a spec is written against it. (Round 11 reviewed
  the spike itself and caught three model bugs — stale Expanded press-order on
  re-press, no state tracking under inbound-`blocked`, slot down-state lost
  across the chat guard — all fixed in the spike and folded into CB0's
  acceptance.)
Results, now platform facts:

- **Left/right modifiers arrive MERGED** — no distinction between L and R
  variants of Ctrl/Alt/Shift. This killed the v1/v2 activator maps. (Bare
  modifier events per se do fire; v0.1's silence was a spike bug, an
  unguarded `get_info()` in the handler.)
- **Blocking works for unchorded keys and NOT for modified ones** (2026-08-08,
  the finding that killed v3). With blocking on, the handler returns `true`
  for Ctrl+3 — the `blocked` counter climbs — and FFXI's macro 3 fires
  regardless; a bare `3` under the same code is swallowed cleanly. The game
  reads its macro chords by a route Windower's keyboard hook does not sit in
  front of. **Consequence**: no key the crossbar wants may be a game-bound
  chord, which is what v4's modifier-free map delivers.
- **`[` `]` `\` `` ` `` `=` are all free** — each opens the chat log and does
  nothing else in game, and each blocks cleanly. They are v4's activators,
  layer, switch and shortcut.
- **`setkey` is the injection mechanism** and its key names parse as guessed:
  `//setkey e down` answers `Setting key code "e" to state: down`.
- **The `flags` parameter is populated**: Ctrl+3 arrives with `flags=4` on the
  slot key's event (a modifier bitmask, by appearance). Unused by v4.
- **Focus events fire** (`lose focus` observed on alt-tab), and **auto-repeat,
  chat and focus guards all behave** as specified.
- **The macro-palette flash is moot** — v4 holds no modifier, so FFXI never
  draws its macro bar during crossbar use. (It was judged acceptable anyway.)

Still to record before CB2 wires anything:

1. **Injected-key echo** — whether `setkey`-injected events re-enter the
   `keyboard` handler, which decides whether the component must ignore its
   own injections. Run `//setkey 3 down` / `up` with a spike loaded and watch
   whether `events` moves.

Also ruled out: the F13–F15 dead-key namespace — **Steam Input cannot emit
extended F-keys** (Kevin, 2026-08-06).

### Reference Steam Input layout (Kevin, 2026-08-06; reworked for the v3 map)

The bridge side of the contract — how the pad produces the DIKs above. Not
enforced by the addon (any layout emitting the right keys works), recorded so the
two halves stay designed as a pair. Every output key has exactly one source, which
is what sidesteps Steam Input's lack of modifier reference-counting.

| Physical control | Condition (Steam Input layer) | Emits (DIK) | Crossbar meaning |
| --- | --- | --- | --- |
| LT | held | `[` (26) | XHB Left |
| RT | held | `]` (27) | XHB Right |
| LT + RT | both held | `[`+`]` | Expanded Hold — press order picks LR vs RL |
| LB | chord while LT held | `\` (43) | `[`+`\` = WXHB Left (release LB → XHB Left) |
| LB | long press, no LT | `\` (43) | draw-gesture hold (with an RB tap) |
| LB | regular press | `R` (19) | not mapped — falls through as autorun |
| RB | chord while RT held | `\` (43) | `]`+`\` = WXHB Right (release RB → XHB Right) |
| RB | press, no RT | backtick (41) | tap = cycle (incl. inside WXHB *Left* — with RT held RB is `\` instead, see caveats); held + slot button = set jump; tap with LB long-press `\` and no side = draw |
| Select | press | `=` (13) | bare = open map; with a side held = toggle the binder |
| Y / B / A / X | chorded with LT, RT, or RB | `1` `2` `3` `4` (2–5) | face cluster, slots 1–4 |
| D-pad ↑ / → / ↓ / ← | chorded with LT, RT, or RB | `5` `6` `7` `8` (6–9) | D-pad cluster, slots 5–8 |
| Y/B/A/X, D-pad | no activator held | (base config) | normal game functions — crossbar ignores them |

Three caveats on the Steam side (the third accepted by Kevin in discussion,
recorded here in round 3):

- **The shared-emitter release race** (accepted against v3, now much smaller):
  both bumpers emit `\` in their chord/long-press roles, so holding both
  W-layer states at once and releasing one drops the layer for the other.
  Steam's lack of reference-counting applies to any shared output, not just
  modifiers — but with no real modifiers left in the map, this is the only
  place it can bite, and the escape hatches stand (single-emitter
  LB-chords-both-triggers, or a second key folded into `w_layer`, which the
  config's DIK lists support).
- The layout is built **entirely from button chords** (Kevin, 2026-08-15 —
  neither action sets nor mode shifts, both of which he finds too buggy to
  rely on): each of the eight slot buttons carries its normal binding plus one
  chord per activator, **LT, RT and RB**. Twenty-four
  chord bindings, each explicit and independent of any layer applying and
  releasing cleanly. Leave RB out and set jumps have no numbers to chord with.
- **No switch key reaches the addon while a trigger is held**, since RB is
  `\\` in that chord. This agrees with the model rather than limiting it: the
  switch is inert while any side is held either way.

Known edge, accepted: a bare-key output pressed while a modifier is physically
down reaches the game modified — e.g. LB's `R` tapped while RT is held arrives as
Alt+R, not R. Same class as the opener-chord issue; arrange Steam Input
accordingly.

`input.lua` emits *intents* (`activate <hold-state id or none>` — release back
to nothing emits `activate none`, the widget's cue to drop the active
panel — the bar itself stays drawn — `fire slot`,
`jump n`, `cycle`, `draw`, `shortcut <verb>`). Per keyboard event it returns
**(intents, block)** — the intent list, possibly empty, plus the latched block
decision for that key. (An earlier revision also demanded a held-modifier
query surface for the opener queue; v4 removed the queue, and that
requirement with it.) Which set
is actually next in a cycle is `bindings.lua`'s answer, since only it knows which
sets are empty, which are in the current weapon state's rotation, and which store
(shared vs job) each reads from.

## xivcrossbar reference facts (verified 2026-08-05 against `AliekberFFXI/xivcrossbar@master`)

Read from a local clone of `master` on 2026-08-05. This section exists so the parts we
*do* take are traceable, and so the parts we reject are rejected on evidence.

### There is no gamepad — the one input fact that carries over

Windower exposes **no** gamepad/controller event (checked the full event list on the
[Events wiki](https://github.com/Windower/Lua/wiki/Events): 48 events, none for
controllers). xivcrossbar's "gamepad" DIKs 59–68/87/88 are literally **F1–F12**, with
Ctrl (DIK 29) as a gate; an external bridge turns controller input into keystrokes.
That constraint is real and ours too; its *specific* map is not adopted (Q1).

Also load-bearing: it intercepts raw DIKs off the global `keyboard` event and
`return true`s to swallow them — evidence that event-level blocking works (Q2).

### Slot geometry — a true cross, and the numbers we keep

Verified in `ui:get_slot_x` / `ui:get_slot_y` (`ui.lua:131–186`). Each cluster is a
plus/diamond of four **40×40** slots around an empty centre.

- Column math: `base + (40 + slot_spacing) * (column - 1)`; the vertical slots of a
  cluster sit in its centre column, and the right cluster shifts one column left so
  the crosses sit closer.
- Row math: `base - (row - 1) * bar_spacing`, rows 1/2/3 = bottom/middle/top.
- `hotbar_width = 400 + slot_spacing * 9`; anchored centred at `y = ui_y_res - 120`
  (we drop the anchor — see Deviations).
- Text offsets from the slot origin: element `+28, -4`; name `-2, +40`. Cost and
  recast text are positioned from the **screen's right edge**
  (`slot_x - ui_x_res + 16`, then `+30, +28` and `+20, +14`) because those texts are
  right-justified — the same `texts` gotcha giltracker documents.
- Recast animation, **xivcrossbar's**: overlay height
  `40 * (remaining / full_recast)`, drawn from the bottom
  (`y + (40 - height)`), clamped at 40 — a rectangular wipe. **Not what we
  ship** (decided 2026-08-08, see the radial sweep below).
- **Bar background** (round 8, previously unrecorded): compact draws
  `bar_bg_compact.png` at `size(330, 180)`, `alpha(button_bg_alpha)`,
  positioned `get_slot_x(h,1) - 30, get_slot_y(h,4) - 35`
  (`ui.lua:257-264, 488`) — it scales with the anchor, unlike the fixed 40 px
  slot maths.
- **Compact mode** halves the vertical bar spacing and swaps in `bar_bg_compact.png`;
  the cluster-centre button icons and the binder/environment chrome are non-compact
  only, so compact-only costs us nothing we want.

### Activation

`player:execute_action` builds a chat command in which `action.type` **is the FFXI
command word** — the basis of the bindable-types table above:

```lua
-- paraphrased; see defect ⑨ for what the real code does with a nil target
windower.send_command('input /' .. type .. ' "' .. action .. '" <' .. target .. '>')
```

The actual code (`player.lua:434-451`) builds `target_string = '" <'..target..'>'`
and appends it — so **a no-target action emits an unterminated quote**
(`input /ma "Cure`), listed as defect ⑨ below; our `actions.lua` closes the
quote always and adds the target suffix only when present.

Special cases verified in source: `ct`, `ex` (no `input` prefix), `ta`
(upstream's Switch Target — **not carried across**, see Deviations),
`enchanteditem` (equip → scheduled `/item` after `0.5 s + warmup` → re-enable the
GearSwap slot 2 s later; the machinery lands at CB1 as `warp`'s dependency,
arbitrary enchanted binds stay backlog), mount roulette. An action record is `{type,
action, target, alias, icon, equip_slot, warmup, cooldown, usable}`.

### Skillchains (`libs/skillchain/`, © 2017 Ivaar)

- `skills.weapon_skills[id] = {en = 'Dragon Kick', skillchain = {'Fragmentation'},
  aeonic = ..., weapon = ...}` — every weaponskill's ordered SC properties
  (round 10: **the whole 839-line file transcribes** — `weapon_skills`,
  `job_abilities`, `spells`, monster abilities; resonation *detection* indexes
  the same tables for whatever action opened the chain, so a WS-only cut
  would miss chains opened by JAs and by SCH Immanence spells — the earlier
  WS-only scope cut is withdrawn); worth transcribing rather than rederiving. (`skills.lua` also
  carries SC-property tables for spells, job abilities and monster abilities —
  **v1 transcribes weapon skills only**, a stated scope cut; bound spells show
  no SC property until the backlog picks the rest up.)
- 14 properties, each shipped as `.png` + `.svg` in the default pack: compression,
  darkness, detonation, distortion, fragmentation, fusion, gravitation, impaction,
  induration, light, liquefaction, reverberation, scission, transfixion.
- Window timing: on a resonation, `delay = clock + delay` (default 3 s) and the window
  closes at `delay + 8 - step`. `get_skillchain_window()` returns
  `(remaining_delay, remaining_window)`; both 0/absent when nothing is open.
- Target resolved with `get_mob_by_target('t', 'bt')`, gated on `hpp > 0`.
- The indicator prims are *created* 604×14 (bg) and 600×10 (fill) but
  *displayed* per state (round 8 — both branches): **waiting** at
  `base_width×4`, bg `base_width+4 × 8`, fraction `delay/3.0`
  (`ui.lua:788-803`); **open** at `base_width×10`, bg `base_width+4 × 14`,
  fraction `window/7.0` (`ui.lua:808-823`) — the thin-red vs thick-green
  distinction CB6 must keep — **and the fill is centre-anchored, with both
  width formulas** (rounds 10/11): waiting draws width
  `round(600 * (1 - fraction))` at offset `round(300 * fraction)` — it
  **grows from the centre** as the delay burns down — and open draws width
  `round(600 * fraction)` at offset `round(300 * (1 - fraction))`, shrinking
  back into it as the window closes (`ui.lua:788-823`; an earlier draft had
  the offsets without the widths and the waiting direction backwards). Above the bar, coloured
  "waiting" (237,28,36) then "open" (15,205,5) at opacity 220.
- **Per-slot icons are live chain results, not static properties** (clarified
  2026-08-07 — this is xivcrossbar's shipped behaviour and what Kevin wants):
  while a resonation window is open on the current target,
  `skillchains.get_skillchain_result(id, resource)` (`skillchains.lua:112-136`)
  runs `check_props` against the active resonation for each bound WS **and
  JA** (by `recast_id`), and the slot swaps its action icon for the resulting
  property's icon (`ui.lua:946-1197`) — with the `frame_step1-8` border
  animation and alpha gated on TP ≥ 1000 (our port gates the TP alpha on WS
  slots only — meaningless for JA slots, a knowingly dropped upstream quirk). The **chain-resolution tables**
  (`sc_info`, the combo maps, `check_props`) transcribe along with the
  property lists. **Aeonic paths are dead code upstream** (round 10: the `AM`
  global in `result = AM and aeonic or prop` is never assigned anywhere, and
  `aeonic_prop`'s guard is unsatisfiable) — the aeonic *data* transcribes with
  the tables, but no aeonic behaviour is ported or specced.

Caveat: the lib calls `windower.prim.*` and `windower.ffxi.*` directly. In our shape
those become `ctx` deps, and the indicator draws with `new_image`, not raw prims.

### State sources

- Recasts: `windower.ffxi.get_spell_recasts()` / `get_ability_recasts()`, read during
  the render pass.
- Events used: `action`, `time change`, `mp change`, `tp change`, `status change`,
  `job change`, `incoming chunk`, `zone change`, `prerender`, `login`, `logout`.

### Assets

~1,460 files (1,433 PNG, 16 JPG, 14 SVG, one Thumbs.db at last count), 6.5 MB, mostly 32×32 and 40×40 (counts corrected again in round 3).

| Path | Count | What |
| --- | --- | --- |
| `images/icons/spells/` | 870 | spell icons |
| `images/icons/abilities/` | 228 | job-ability icons |
| `images/icons/iconpacks/default/` | 304 | trusts (41), ui (31 top-level; 86 incl. binding_icons/), ninjutsu (30), skillchain (28), jobs (23), blue-magic (21), mounts (16), elements (10), weaponskills (22, in dagger/katana/sword subdirs), items/abilities (3 each), **21 top-level "singles"** — attack, disengage, dismount, mount, item, map, ranged, check, assist, switchtarget, … — the built-in action icons |
| `images/icons/weapons/` | 29 | weapon-type icons |
| `images/icons/skillchain/`, `elements/` | 22 | 14 + 8 |
| `themes/ffxiv/` | 3 | `slot.png` 40×40, `frame.png` 40×40, `notice.png` 103×21 |

**Packaging consideration (added after review):** importing the needed subset
(~1,100 PNGs, ~6 MB) into `src/` grows the repo and the release zip ~30× over
today's 208 KB — acceptable for an asset-heavy component, but decide the subset
deliberately at CB4 (the asset-importing milestone) rather than copying the tree. Post-merge, the repo already settled the verification convention for large
asset sets: `check_assets` ([XIVHud.lua:698-743](../../src/XIVHud.lua#L698-L743))
**samples** a handful of partylist's ~680 textures rather than enumerating
("680 file opens to learn what a handful already tells us"). CB4 follows that
convention: extend (not replace) `check_assets` with a hand-listed sample —
a few icons from each imported category (spells, abilities, weaponskills,
theme, skillchain, singles) plus every `openers.lua`/`contexts.lua` icon,
since those tables exist from CB1 (the catalog does not exist until CB8 and
is not a dependency).

Item icons are **not** shipped, and **the repo already solves this** (merged
2026-08-08 with the Equip Viewer component): `src/components/equipviewer/icons.lua`
is a pure, spec'd re-implementation of Rubenator's `icon_extractor` — DAT
ranges, record layout, palette rotation, bitmap header — with the entry point
already providing `read_dat`, `write_binary`, `game_path` and `file_exists`
deps. The crossbar needs the same capability for item slots.

**CLAUDE.md forbids requiring a sibling component**, so the crossbar cannot
reach into `components/equipviewer/`. Touchpoint 6 (below) promotes the
extractor to `lib/` so both components share one copy — the alternative,
duplicating 216 lines of byte-level DAT parsing, is exactly what the isolation
rule exists to prevent, but it cuts the other way here.

### Known defects (do not reproduce)

| # | Defect | Confidence |
| --- | --- | --- |
| ① | Load `unbind`s `^f1`–`^f12` and **never restores them**; the main addon has no `unload` handler at all, so prims survive `//lua unload` too. | 95% — grepped every `bind`/`unbind`/`register_event('unload')`; only the unbinds exist. |
| ② | `setup_metrics` *mutates* its settings table (`hotbar_spacing = ... - 10`, gated on `hide_action_names`), so with that option on, re-running setup shrinks spacing cumulatively. | 90% — structurally plain; depends on setup running more than once per session. |
| ③ | `ui_dirty` is **assigned**, not or-ed, on every keyboard event, so a later key before the next `prerender` clears a pending redraw. | 70% — needs a live client to confirm the dropped frame is visible. |
| ④ | `split_hotbar` is declared without `local`, leaking into `_G`. | 100% — read directly. |
| ⑤ | `buttonmapping:write()` ships debug `send_command('[XIVCrossbar] here')` calls that are not valid commands. | 100% — read directly. |
| ⑥ | `save_hotbar` calls `error(...)` on a missing file (with an unreachable `return` after), turning a save into a hard failure. | 100% — read directly. |
| ⑦ | Two `if new_height > 40` clamps commented "temporary bug fix" — the recast fraction can exceed 1, so the recast source and the assumed full recast disagree somewhere. **Moot for us since 2026-08-08**: the radial sweep divides by an observed maximum, which cannot be exceeded. | 80% — the clamp is real; the cause is not identified, and no longer needs to be. |
| ⑧ | **The double-tap misfire Kevin lives with** (mechanism corrected 2026-08-06 by blind review — an earlier draft wrongly said the flags were never reset; `close_*_doublepress_window`, `xivcrossbar.lua:91–99`, clears them 0.5 s after the first press): the **first release** sets `*_lifted_during_doublepress_window`; the second press's double-press branch closes the window but never clears that flag, and only the scheduled 0.5 s close does — so a **third press before the original window expires** re-opens a window and instantly satisfies the double-press test against the stale flag: fast tap-tap, release, tap → WXHB again. Outside the 0.5 s window the flags are clean. | 85% — mechanism re-traced in review round 2; matches the observed fast-tapping symptom; not client-verified. |
| ⑩ | **Merit spells can never be bound** — the defect Kevin actually hit, and the reason he abandoned the Petit Trois fork ("it just wouldn't bind Refresh III"). `get_spells_for_job` gates on `spell.levels[job_id] <= job_level` (`action_binder.lua:1868`; function head at 1860), but merit spells encode their requirement as a sentinel level far above the 99 cap — in the Horizon-server resource copy shipped by the Petit Trois fork, Refresh III is `levels = { [5] = 1200 }`, alongside Death, Fira III, the -helix IIs and 14 others. `1200 <= 99` is false, so the spell is filtered out **even though `is_known` is true**. Merits are not a level gate, so no level ever satisfies it. The same shape applies to merit job abilities. | 95% on the mechanism (read directly, and it explains the reported symptom exactly); the sentinel *values* come from a Horizon-server resource copy, so retail's exact numbers want confirming — the fix below does not depend on them. |
| ⑨ | **No-target actions emit an unterminated quote**: `execute_action` (`player.lua:434-451`) appends `'" <target>'` only when a target exists, so the opening quote before the action name is never closed without one — `input /ma "Cure`. Works only because the game tolerates it. | 95% — read directly (found in blind review). |

## Deviations

Beyond the wholesale rejection of its input model and slot order:

- **Position, scale and visibility belong to the framework.** Drop `Style.OffsetX/Y`
  and the `ui_y_res - 120` anchor; the widget is dragged in `//hud layout` and its
  state lives in layout slots. Scale multiplies the 40 px slot, the spacing, the font
  and every offset. **Three** anchors — `main` (the XHB), `wxhb`,
  `indicator` (skillchain) — each independently positioned (touchpoint 2).
  **Expanded Hold has no anchor of its own** (decided 2026-08-15): it is the
  only bar that *replaces* rather than coexists, so it draws **centred on the
  `main` anchor's footprint** — eight slots centred across the XHB's sixteen,
  which is where the reader is already looking. Upstream does the same, its
  Expanded bars sitting at `+150` between the XHB halves at `0` and `+300`.
- **The bar is persistent, not hold-to-show** (corrected 2026-08-15 by Kevin;
  earlier revisions of this plan had it appearing on a held key, which was
  wrong). While the component is visible, something is always on screen; the
  held keys choose which part is **active**, not whether anything is drawn.

  | State | XHB | WXHB | Expanded |
  | --- | --- | --- | --- |
  | nothing held | visible, **inactive** | visible only if `always_show_wxhb` | hidden |
  | an XHB side held | visible, **that side active** | as above | hidden |
  | a WXHB side held | visible, inactive | **visible, that side active** | hidden |
  | both side keys held | **hidden** | **hidden** | **visible, active** |

  So the WXHB appears on demand when `always_show_wxhb` is off, and Expanded
  Hold always replaces the others for as long as it is held — drawing centred
  on the `main` anchor, where the XHB it replaced was. **Active** is
  drawn as a panel behind that side (the reference's
  `bar_bg_compact.png`, repositioned onto whichever bar is active,
  `ui.lua:862-866`); inactive sides render normally, undimmed.
  `show()`/`hide()` remain framework-owned and mean what they do for every
  other component.
- **Auto-hide is framework-owned.** The `event` / `zoning` / `logged_out` suppression
  set replaces the addon's own `status change` handling. Interaction to verify
  in-client: a trigger held across a cutscene boundary must not strand a side on
  screen or a trigger "down".
- **No stolen keybinds** (defect ①): the component consumes only the DIKs it
  cares about, through the framework's keyboard dispatch — slot keys only
  while a hold state is active or the switch is held; the punctuation keys
  (`[` `]` `\` `` ` `` `=`) are ours outright while it runs. **FFXI's own
  macro palette is untouched**, unlike v3 which would have shadowed
  Ctrl/Alt+1–8. Nothing is `unbind`ed.
- **Unload is clean** — every prim disposed, nothing left bound.
- **Config is ours**: `.lua` through the framework's config service, snake_case keys,
  no XML, no `data/hotbar/<Server>/<Character>/` tree.
- **Sets are storage, sides are views** — the FFXIV model, where xivcrossbar instead
  gave each of its six bars independent slots and had no sets at all.
- **Compact only.** The full-size metrics are not built. A real narrowing — reversing
  it is new work, not a config flip.
- **One theme, one icon pack.** `ffxiv` + `default`, no folder resolution.
- **Not carried across at all**: `action_binder.lua` (in-game binder, 2,437 lines),
  `gamepad_mapper.lua`, `buttonmapping.lua` + `config.ini`, the `.ahk`/`.py`/`.sh`
  bridge scripts, `libs/xml2.lua`, `libs/md5.lua`, `libs/ordered_pairs.lua`,
  the battle notice (`notice.png` + `HideBattleNotice`), and **Switch Target**
  (upstream's `ta` type — dropped 2026-08-08, see Q9: not a game command word,
  and the game's own targeting controls cover it).
  Consumables and enchanted items are backlog. Trusts need no special support —
  they cast as `ma` (corrected round 7; `/trust` is not a command word), and
  the default pack has the icons.

## Architecture

```
src/components/crossbar/
  crossbar.lua        -- widget factory new(ctx): owns prims, implements the contract
  input.lua           -- pure input state machine: DIK stream -> intents
  bindings.lua        -- pure binding model: sets/views, layer stack resolution, cycle
  actions.lua         -- pure action -> command string / key sequence / roulette call
  roulette.lua        -- pure mount roulette: owned-mount tracking + pick
                      --   (module keeps the descriptive name; the action is `mr`,
                      --    as openers.lua backs `open`)
  warp.lua            -- pure auto-warp (MyHome port): priority ladder ->
                      --   a plan {spell|equip-then-item|item}, no I/O
  enchanted.lua       -- pure enchanted-item state: charges, warmup, recast
  openers.lua         -- the extensible open-action table (commands / key sequences)
  kebab.lua           -- upstream's kebab_casify (5 lines, taken): icon files
                      --   resolve as <category>/<kebab_casify(name)>.png
  contexts.lua        -- the code-defined context roster: names, buff predicates, order
  catalog.lua         -- pure binder catalog: known spells/JA/WS/items/etc from injected data
  binder.lua          -- edit-mode UI: slot picking, stack panel, catalog panel (prims + mouse)
  skillchain.lua      -- pure: WS/JA -> properties, resonation x action ->
                      --   chain result, window state -> indicator plan
  render.lua          -- pure geometry + per-frame render plan (compact cross, recast)
  defaults.lua        -- config defaults
  assets/
    slot.png frame.png                       -- xivcrossbar ffxiv theme
    cooldown/frame_01-32.png                 -- radial recast sweep, imported
                                             --   from Petit Trois (decided)
    bar_bg_compact.png feedback.png          -- default pack, ui/ (press flash);
    black-square.png frame_step1-8.png       --   recast overlay + frame anim -
                                             --   import-or-synthesise decided at CB4
    icons/...                                -- the CB4-chosen subset: spells, abilities,
                                             --   weapons, elements, skillchain, mounts,
                                             --   trusts, weaponskills, ninjutsu,
                                             --   blue-magic, ui singles
    LICENSE.txt                              -- MIT + BSD notices (see License)
tests/components/
  crossbar_input_spec.lua      crossbar_bindings_spec.lua
  crossbar_actions_spec.lua    crossbar_roulette_spec.lua
  crossbar_warp_spec.lua       crossbar_enchanted_spec.lua
  crossbar_skillchain_spec.lua crossbar_render_spec.lua
  crossbar_catalog_spec.lua    crossbar_commands_spec.lua
  crossbar_binder_spec.lua     crossbar_spec.lua
  -- contexts.lua (data) and defaults.lua are exercised through
  -- bindings/actions/render specs rather than own files
```

Everything except `crossbar.lua` and `binder.lua` is pure — plain tables in, plain tables out, no
prims, no Windower globals. `input.lua` is a state machine fed `(dik, pressed, blocked)`
tuples (the event's inbound `blocked` flag feeds guard 5), which is the only reason the held-set resolution, press-order and
tap-vs-chord logic is testable at all.

### Framework touchpoints (new work outside the component)

1. **Always-on keyboard dispatch that can block.** Today `keyboard` is registered only
   while layout mode is on ([XIVHud.lua:189-210](../../src/XIVHud.lua#L189-L210)),
   `core.on_keyboard` hard-returns `false`
   ([core.lua:465-468](../../src/lib/core.lua#L465-L468)), and `core.dispatch`
   discards component return values
   ([core.lua:446-455](../../src/lib/core.lua#L446-L455)). The crossbar needs the
   handler registered whenever a component asks for it, a dispatch path where a
   component returning `true` propagates out to Windower, **and the full event
   signature forwarded** (round 8): today's wrapper passes only `(key, down)` —
   `flags` and inbound `blocked` are dropped before dispatch, and guard 5
   needs `blocked`. The guard's `false`
   fallback stays — a dead handler must never keep swallowing the keyboard.
2. **Multi-anchor widget contract (decided 2026-08-05: extend the contract, not a
   second widget).** A widget may expose N named anchors — here `main` (the XHB,
   and Expanded Hold when it replaces it), `wxhb`, and `indicator`
   (skillchain — Q5, resolved; provisioned at CB3, populated at CB6) — each
   with its own pos, scale and layout-mode bounds. Touches: the layout-slot schema
   (per-anchor `pos`/`scale` nested under the component's slot entry),
   `layout_mode` hit-testing and drag (per anchor, not per widget), `overlay`
   (one highlight per anchor), the contract members
   (`get_bounds`/`set_pos`/`set_scale` grow an anchor dimension). Detection,
   pinned in round 4: a multi-anchor widget declares an optional contract
   member `anchors() -> {names}`; when absent, core takes the existing
   single-anchor path with today's signatures untouched — Lua's silent
   nil-tolerance makes an implicit convention too dangerous here. **Also —
   added after review — the two other consumers of the single-anchor shape:
   `core.describe` (`//hud list` output formats one pos/scale,
   [core.lua:478-491](../../src/lib/core.lua#L478-L491)) and `core.apply`'s
   off-screen clamp repair
   ([core.lua:203-224](../../src/lib/core.lua#L203-L224)), both of which must
   iterate anchors** — the overlay pusher (round 9): `core.apply_overlay` (`core.lua:186-198`)
   feeds one `get_bounds()` box to `overlay.show`, which is keyed by component
   name — per-anchor highlights need per-anchor keys there too — and the
   *writer* (round 7): `layout.slot`
   (`layout.lua:101-134`) unconditionally repairs top-level `pos`/`scale` on
   every slot entry it touches (a crossbar entry holding only `anchors` would
   get spurious `pos`/`scale` written back), `layout.create_slot` seeds new
   slots through the same path, and `core.lua:164` re-clamps `state.scale`. `visible` stays **per component** — right-click in layout
   mode toggles the whole widget, all anchors (explicit decision; per-anchor
   visibility is not provided). Single-anchor widgets keep working unchanged —
   parambar, giltracker, and the partylist trio must not need edits. This updates the framework
   plan's contract table when it lands. (Shipped counter-precedent, noted
   2026-08-07: partylist registers three components from one dir; the decision
   here stands, and a backlog item *evaluates* migrating partylist after CB3 —
   see the backlog for its per-anchor-visibility prerequisite.)
3. **Component mouse dispatch (edit mode).** The `mouse` event is likewise
   layout-mode-only today. The binder needs it dispatched to a component while
   edit mode is on — same shape as the keyboard touchpoint: registered while a
   component asks, a component's `true` propagates out, guard fallback `false`.
   Precedence (round 9): **entering layout mode exits edit mode** (and the
   `edit` verb is refused while layout mode is on) — the two never contend for
   the mouse.
4. **New `ctx` deps** (the entry point builds each `ctx` by hand): `send_command`,
   `send_key_events` (key-event open actions — `setkey` down/up via
   `send_command`),
   `get_spell_recasts`, `get_ability_recasts`, `get_key_items` + mount/KI resource
   tables and `random` (`mr`), `job_points` off the player table (the SCH
   stratagem gift), item counts kept from the already-forwarded
   `add item`/`remove item` events (ninja tool counts), `get_items` per bag + the `bags` resource +
   `extdata.decode` + `set_equip` + `send_ipc` (warp; `ipc message` also needs
   forwarding), `get_player` (main/sub job, buffs),
   `get_spells` + `get_abilities` + spell/ability resource tables and
   `get_items` (binder catalog — usable-item entries need the inventory), `get_mob_by_target` (skillchain), **parsed `0x028` action packets on the
   existing chunk dispatch** plus the chainbound/aftermath chunk ids
   `0x29`/`0x63` on the same path, and a bound-action name→id/recast_id lookup
   (round 11: the `action` *event* is deprecated and deliberately unused per
   CLAUDE.md — the entry point already wraps `windower.packets.parse_action`
   for targetbar, and the skillchain feed rides that, keeping the component
   Windower-free), `chat_open` (input guard — **nil-tolerant by construction**: it runs per key
   event inside a guarded handler, and the spike's v0.1 died on exactly this
   kind of unguarded `get_info()` call), a
   monotonic `now` (skillchain window machine, feedback animation),
   `file_exists` (icon fallback), and — added in round 3, nothing provides it
   today — **`say(lines)`**: **component-initiated** chat output with the standard
   prefix. Narrowed in round 7: the partylist merge taught the passthrough to
   relay table replies line by line (`core.lua:810-818`), so `list` output
   rides the existing reply path — the dep is needed only where no command is
   in flight: the binder's bind echoes (mouse-initiated) and `draw`'s
   no-target hint (keypress-initiated). The entry point also needs to forward
   `gain focus` / `lose focus` (input reset on alt-tab) and
   `gain buff` / `lose buff` (context-layer re-resolution), `job change`
   (per-job binding reload — the whole model is per-main-job) into
   `core.dispatch` — none currently wired. (Skillchain resonation needs no
   new event: round 11 corrected an earlier `action`-event request — that
   event is deprecated per CLAUDE.md, and `0x028` already arrives parsed on
   the chunk dispatch via the entry point's `windower.packets.parse_action`
   wrapper, the same way targetbar consumes it.)
5. **Directory config namespace.** Per-job bindings need
   `data/<Character>/crossbar/<MAIN>.lua`, which the framework plan already permits.
   Whether `lib/settings` implements the directory form needs checking before CB2
   Corrected after review: `lib/settings` today exposes `handle.dir()` but no
   read/write inside it (`settings.lua:147-152`, `save()` writes only the
   single component file), and no component receives file I/O deps — so this is
   a **definite** small API addition (e.g. `handle.file(name)` returning a
   sub-handle with the same get/save shape), spec'd in `settings_spec` at CB2.
   Delivery route (pinned in round 2 — a sub-handle alone has no path into a
   component): the widget contract's `attach` gains an optional third argument,
   a `store` accessor (`load(name)` / `save(name, table)`) passed only to
   components whose config claims the directory form — a contract change
   recorded alongside touchpoint 2's, invisible to parambar/giltracker. Two
   corollaries, both spec'd at CB2: `settings.reload()` after `//hud copy`
   ([core.lua:742](../../src/lib/core.lua#L742)) must also rebuild directory
   stores, or copied bindings go stale in memory; and `merge_defaults`
   (`settings.lua:59-69`) fills nil keys from defaults, so **config entries can
   be replaced but never removed** — removal of a shortcut or a role's DIK uses
   an explicit `false` sentinel, documented as a comment in the `input` config
   block and ignored by `input.lua` (array-valued roles shrink the same way:
   a `false` element is skipped). Round 3 adds the mirror of the copy
   corollary: `//hud reset crossbar` today resets and rewrites **only** the
   single component file (`core.lua:500-505` → `settings.lua:182-188`) — the
   per-job files under `crossbar/` would silently survive; reset must clear
   the directory store and rebuild, and all **three** `attach` call sites
   (`core.lua:276`, `:305`, `:503`) must pass the new `store` argument, not
   just registration.
6. **Promote the item-icon extractor to `lib/`** (new 2026-08-08, after the
   Equip Viewer merge; scope corrected the same day by Kevin). The reusable
   surface is **two halves, and the crossbar needs both** or it duplicates the
   pipeline:

   | Half | Where it lives now | What it is |
   | --- | --- | --- |
   | pure | `components/equipviewer/icons.lua` (216 lines, spec'd) | `locate(item_id)`, `dat_path(game_path, dat)`, `to_bmp(slice)` — DAT ranges, record layout, palette rotation, bitmap header |
   | pipeline | inside `equipviewer.lua` | `cached_icon` (resolved-cache → `abandoned` short-circuit → `file_exists`), `request_icon` (dedup into a pending queue off the packet path), `drain_queue` (**one icon per frame**, one attempt per item, `abandoned` on failure), and `game_path()` (config override beating Windower's registry answer) |

   The pipeline half is the part with the hard-won behaviour — the comments
   record that extracting inside the packet handler meant sixteen DAT opens,
   decodes and writes in one frame on a cold login. Promoting only the pure
   half would leave the crossbar to re-derive exactly that.

   Shape: `lib/icons.lua` keeps the pure functions; a new `lib/icon_cache.lua`
   takes `new(deps)` (`asset`, `file_exists`, `read_dat`, `write_binary`,
   `game_path`) and returns the `cached_icon` / `request_icon` / `drain_queue`
   trio plus the per-character reset.

   **The shared cache already exists** (checked 2026-08-08, correcting an
   earlier note in this plan that claimed otherwise): `ICON_CACHE_DIR` is
   `"icons/"` (`equipviewer.lua:62`) and `asset()` is
   `windower.addon_path .. path` (`XIVHud.lua:495-497`), so the cache is
   **addon-level** at `<addon>/icons/<item_id>.bmp` — not per component.
   `.gitignore` already covers `/src/icons/`, and `write_binary` calls
   `ensure_dir` on first write (`XIVHud.lua:282-292`). Both components
   therefore share one directory by construction: an item equipviewer has
   already extracted is on disk for the crossbar and never re-extracted, which
   is the point. The promotion moves code, not the cache location. Equipviewer is repointed at both and
   **must stay green untouched otherwise** — that is the acceptance; its
   existing specs move with the pure half.

   Ordering, and now satisfied: the crossbar branch was two commits behind and
   predated equipviewer, so the lib would have had no second caller. Merging
   `origin/dev` into this worktree on 2026-08-08 (HEAD `12cdd4c`) brought
   equipviewer in, so the promotion can be authored here with both callers
   present.
7. **Prim budget** (revised 2026-08-15, after the persistent-bar correction —
   the earlier figure assumed one bar on screen at a time and was far too
   low). A *bar* is two sides = 16 slots; at ~9 prims a slot that is ~144
   prims per bar; Expanded Hold is a single side, so half that. Worst resting
   case is XHB + WXHB both drawn = **~290 prims**, plus the active panel and
   the skillchain indicator; Expanded replaces rather than adds, so the
   ceiling is unchanged. Sets are data — switching sets repaints existing
   prims rather than allocating more, and the six hold states share
   2.5 bars' worth (16 + 16 + 8 slots). Whether the WXHB's
   prims are destroyed or merely hidden when `always_show_wxhb` is off is a
   CB5 measurement, not a guess. The binder adds its own in edit mode only.

## Settings (defaults, in `data/<Character>/crossbar.lua`)

Bindings live in the per-job files (below), not here.

```lua
{
  -- defaults.lua is a factory `function(screen_width, screen_height)` like the
  -- shipped components' — the three anchor defaults are computed from screen
  -- size. `false` disables an entry (merge_defaults refills nil, never false).
  input = {                        -- DIK codes per role; the bridge emits these
    xhb_left  = { 26 },            -- [
    xhb_right = { 27 },            -- ]
    w_layer   = { 43 },            -- backslash; + a side = the WXHB views
    set_switch = { 41 },           -- backtick; tap cycle, chord jump, ours always
    slot_keys = { 2, 3, 4, 5, 6, 7, 8, 9 },  -- positional: index = slot number;
                                             -- false = "slot n has no key";
                                             -- renamed from `slots` round 11 -
                                             -- three meanings of that word was
                                             -- two too many
    shortcuts = {                  -- dedicated keys -> //hud crossbar verbs
      [13] = { tap = "open map", chorded = "edit" },  -- '=' ; pad Select
    },
  },
  always_show_wxhb = false,        -- WXHB on screen at rest, or only while its
                                   -- own gesture is held (FFXIV's own option)
  views = {                        -- what WXHB / Expanded Hold display: set + side
    -- one set per bar, so nothing duplicates what is already on screen: the
    -- XHB starts on set 1, so the WXHB takes set 2 and Expanded set 3
    wxhb_left   = { set = 2, side = 'left' },
    wxhb_right  = { set = 2, side = 'right' },
    expanded_lr = { set = 3, side = 'left' },
    expanded_rl = { set = 3, side = 'right' },
  },
  -- per-set flags; character-wide by definition (a set's shared-ness cannot vary
  -- by job or two jobs would disagree about where set n lives)
  set_flags = {
    [1] = { shared = false, cycle = { drawn = true, sheathed = true } },
    -- ... [2]..[8] same defaults: unshared, cycled in both states (matches an
    -- untouched FFXIV install; Kevin's layout is config, not the default)
  },
  slot_spacing = 6,
  bar_spacing = 56,                -- upstream's HotbarSpacing verbatim; compact
                                   -- halves it AT RENDER TIME exactly as
                                   -- upstream does (decided 2026-08-07: port
                                   -- xivcrossbar's drawing, don't re-derive)
  slot_alpha = 100,
  button_bg_alpha = 150,
  disabled_alpha = 100,            -- unusable action
  hide = { empty_slots = false, action_name = false, cost = false,
           element = true, recast_animation = false, recast_text = false,
           skillchain_icon = false },
  feedback = { alpha = 150, speed = 30 },      -- press flash
  font = 'sans-serif', font_size = 7, text_offset = { x = 0, y = 0 },
  text_color  = { a = 255, r = 255, g = 255, b = 255 },
  text_stroke = { width = 2, a = 200, r = 20, g = 20, b = 20 },
  mp_cost_color = { r = 230, g = 91,  b = 151 },
  tp_cost_color = { r = 254, g = 222, b = 0 },
  skillchain = {
    indicator = true,
    opacity = 220,
    waiting_color = { r = 237, g = 28, b = 36 },
    open_color    = { r = 15,  g = 205, b = 5 },
  },
  -- framework-owned; per-anchor under the multi-anchor contract (touchpoint 2)
  slots = { default = { anchors = { main = { pos = ..., scale = 1 },
                                    wxhb = { pos = ..., scale = 1 },
                                    indicator = { pos = ..., scale = 1 } },
                        visible = true } },  -- visible is per component, not per anchor
}
```

### Binding layers (decided 2026-08-06)

A slot's content is resolved through a stack; **the topmost active layer that has
an entry for the slot wins**:

```
context layers  buff-conditioned, ordered — later in the list wins   (sparse)
subjob layer    overrides for the current MAIN/SUB combination       (sparse)
job base        the MAIN job's sets — every subjob shares these
shared store    sets flagged shared in set_flags (whole-set granularity)
```

- **Context definitions live in code, not user data** (decided 2026-08-06 —
  "contexts that unlock other abilities are rare"). A curated roster in
  `contexts.lua`, each entry `{ name, label, any_of = {buff ids}, icon }`, in a
  fixed code-defined stack order. The v1 roster, ported from Kevin's fork:

  | Context | Active when any of | Notes |
  | --- | --- | --- |
  | `light-arts` | 358 (Light Arts), 401 (Addendum: White) | 401 implies LA |
  | `dark-arts` | 359 (Dark Arts), 402 (Addendum: Black) | 402 implies DA |
  | `addendum-white` | 401 | stacks above `light-arts` |
  | `addendum-black` | 402 | stacks above `dark-arts` |

  Adding a context (BST charm? SMN avatar?) is one table entry. Users author
  only the **overrides** — sparse `set/side/slot → action` entries per context —
  stored **per main job** in `<MAIN>.lua` (decided 2026-08-06, matching Kevin's
  fork over a character-wide store): each main job carries its own contents for
  a context, so SCH main and RDM/SCH can lay out the same buff differently, at
  the cost of binding per job.
- **Activation is re-synced from the authoritative buff list**
  (`get_player().buffs`), with `gain buff`/`lose buff` as mere triggers and a
  no-change short-circuit — **never** tracked from the deltas alone. Platform
  gotcha, documented in Kevin's fork and preserved here: using an Addendum makes
  FFXI re-evaluate the arts status and fire a **spurious arts `lose buff` while
  arts is still active**; delta-tracking would drop the Light Arts layer
  mid-Addendum. The `any_of` implication sets above are the second half of the
  same defence.
- **The motivating example (Kevin's SCH setup):** base slot = a weaponskill; a
  `Light Arts` context overrides it to Addendum: White; an `Addendum: White`
  context overrides a WXHB side with the unlocked spells; `Light Arts` / `Dark
  Arts` contexts override the same four stratagem slots with their respective
  stratagems.
- **Subjob layer** exists so common slots need *no* syncing across subjobs — the
  job base is defined once; RDM/NIN differs from RDM/WHM only where it says so.
- Sharing keeps whole-set granularity via `set_flags` (a shared set's *base*
  comes from SHARED.lua); layers above apply uniformly regardless of the base's
  store.

Storage: shared sets in `data/<Character>/crossbar/SHARED.lua`, everything
job-scoped — base, subjob overrides, context overrides — in
`data/<Character>/crossbar/<MAIN>.lua`. Flipping a set's shared flag switches
which store its base reads from — the other store's contents stay on disk,
dormant, so toggling back loses nothing. `copy <JOB>` copies the whole
job-scoped file: base, subjob layers, and context overrides (shared sets are
already everywhere).

```lua
-- <MAIN>.lua (SHARED.lua carries only a `sets` table)
{
  active_set = 1,                  -- persisted per job
  sets = {                         -- the job base
    [1] = { left = { [1] = { type = 'ws', action = 'Savage Blade', target = 't' },
                     ... },        -- slots 1-8
            right = { ... } },
    -- [2]..[8] as populated; missing = empty set (skipped by cycle)
  },
  sub = {                          -- sparse subjob overrides
    NIN = { [1] = { left = { [2] = { type = 'ja', action = 'Provoke', target = 't' } } } },
  },
  contexts = {                     -- overrides keyed by the code-defined roster names
    ['light-arts'] = { [1] = { left = { [3] = { type = 'ja', action = 'Addendum: White' } } } },
    ['addendum-white'] = { ... },
  },
}
```

No `compact` key — compact is the only layout. No `FrameSkip` — the framework owns
the prerender throttle. No `iconpack` — one pack ships. `sets` count is fixed at 8.

## Commands (`//hud crossbar`)

Through the framework's `handle_command(args)` passthrough; parsing is a pure
function. Framework conventions apply: case-insensitive verbs, unknown input →
one-line hint, consistent chat prefix.

```
//hud crossbar                                     -- job, XHB's active set, view mapping
//hud crossbar set <1-8>                           -- switch the XHB's active set
//hud crossbar cycle                               -- bare: advance the rotation (for //bind; the gesture's command twin)
//hud crossbar bind <set> <l|r> <slot> <type> <action> [<target>]
//hud crossbar unbind <set> <l|r> <slot>
//hud crossbar alias <set> <l|r> <slot> [<name>]   -- relabel a slot; omit <name> to clear
//hud crossbar icon <set> <l|r> <slot> [<icon>]    -- re-icon a slot; omit <icon> to clear
//hud crossbar list [<set>]                        -- bindings on this job
//hud crossbar view <wxhb-l|wxhb-r|exp-lr|exp-rl> <set> <l|r>   -- repoint a view
//hud crossbar wxhb [on|off]                      -- WXHB on screen at rest; no argument reports
//hud crossbar share <set> on|off                  -- shared (all jobs) vs job-specific
//hud crossbar cycle <set> drawn|sheathed|both|none -- with args: rotation membership per weapon state
//hud crossbar swap <set> <l|r> <slot> <set> <l|r> <slot>  -- swap two slots' ENTIRE stacks
//hud crossbar open                                -- list open-action names
//hud crossbar copy <JOB>                          -- seed this job's bindings from another
//hud crossbar edit                                -- toggle edit mode (mouse binder)

-- contexts (roster is code-defined; this inspects it):
//hud crossbar context list                        -- roster in stack order, active ones marked

-- built-in actions (same table the slots use; for //bind and macros):
//hud crossbar draw                                -- sheathe/unsheathe toggle
//hud crossbar mr                                  -- mount roulette
//hud crossbar warp [all]                          -- auto-warp; `all` broadcasts over IPC
//hud crossbar open <name>                         -- open named game UI
```

- `<slot>` accepts `1`–`8` or the button names (`y`, `b`, `a`, `x`, `up`, `right`,
  `down`, `left`) — nobody should have to memorise the indices.
- **`alias` and `icon` are per-entry overrides** (added 2026-08-15), not
  separate state: the action record already carries `alias` and `icon`
  (upstream's own fields, see Activation), so these write those two and
  nothing else. They therefore follow the same layer prefixes as `bind` — a
  an `alias` on `ctx:light-arts:1` relabels only the entry that context
  supplies. **Omitting the final argument clears the override**, restoring the
  action's own name or the icon the catalog would have chosen. Aliasing or
  re-iconing an empty slot is an error, not a silent no-op: there is no entry
  to carry it.
  `<icon>` is a name from the shipped pack (`mount`, `attack`, …) or a path
  to a PNG under the addon folder for your own art; an unresolvable one is
  rejected at entry rather than drawing nothing later.
- **`swap` moves the whole stack** (decided 2026-08-06): for the two addresses,
  every layer's entry — base (whichever store the set's flag selects), each
  subjob override, each context override — is exchanged in one operation. No
  layer prefix applies; a "move" is a swap with an empty stack. Addresses may
  cross sets and sides within the current job's view.
- `bind`/`unbind` accept an optional layer prefix on the set argument:
  `sub:<set>` targets the current subjob's layer, `ctx:<name>:<set>` a context's
  overrides; no prefix targets the job base (or the shared store, per the set's
  flag). `//hud crossbar bind ctx:light-arts:1 l 3 ja "Addendum: White"`.
- Validation rejects unknown types, unknown open targets, unknown layers,
  out-of-range sets/slots; every accepted change persists immediately and
  re-renders.

## Edit mode & the binder (`//hud crossbar edit`, decided 2026-08-06)

Mouse-driven replacement for xivcrossbar's gamepad-navigated `action_binder.lua`
(2,437 lines — the largest thing we are *not* porting). Its catalog logic is the
part worth mining; its navigation is not.

- **Flow — three surfaces** (confirmed 2026-08-06): the **bar** (slots
  clickable, source-tagged), the **stack panel** (opens adjacent to the clicked
  slot), and the **catalog** (opens centered above the bar once a layer row is
  clicked). `//hud crossbar edit` toggles edit mode — all sides render, input
  activators go inert, the mouse takes over. Click a slot → stack panel; click
  a layer row → preview + catalog unlocks; click an action → bound, chat echo,
  catalog closes, stack panel refreshes in place (unbind / relayer / next slot
  from there). Exiting edit mode tears everything down. Panel placement is a
  draft — tune in-client at CB8.
- **The stack panel is the overlay fix.** Kevin's fork failed because the edit
  target was sticky global state, set elsewhere and invisible at bind time. Here
  the target is chosen at the slot, at bind time, on screen — with these rules
  (defaults decided 2026-08-06):
  1. In edit mode **every slot carries a source tag** on the bar itself (none =
     job base, one mark = subjob, another = context), so "where is this coming
     from" is answered before any click.
  2. Clicking a slot opens its **full stack** — shared/base, subjob, every
     roster context — each row showing its entry or `-` (ASCII only — see the
     sources_spec constraint in Mount roulette). The winning row
     carries only a `*` marker (decided 2026-08-06 — no "WINS" text column);
     the winner's *content* is already visible on the bar slot itself, which
     always renders the resolved action.
  3. **No default target: the catalog stays locked until a row is clicked.**
     Every bind is an explicit two-step (slot → layer → action); nothing is
     ever inferred (chosen over edit-what-you-see).
  4. Clicking a row moves an always-visible `EDITING -> <layer>` cursor (ASCII) **and
     re-renders the whole bar as that layer's world** — the mode header flips
     (`viewing: LIGHT ARTS` vs `viewing: LIVE`), so simulated state is
     unmissable. **Preview = a simulated buff list through the live resolver**,
     not a hand-toggled layer: picking `dark-arts` resolves as buffs `{359}`
     (Light Arts correctly drops out even if actually up — the arts are
     mutually exclusive in preview exactly as in the game), picking
     `addendum-white` resolves as `{401}`, which lights both addendum-white
     *and* light-arts via `any_of` — the preview always shows the true stacked
     result. Inactive contexts are editable this way at any time.
  5. **Nothing is sticky**: closing the panel or **clicking** another slot
     clears the layer cursor; there is no mode to forget. A **drag** is not a
     click (the threshold in Drag and drop separates them): dropping on
     another slot uses the cursor as it stood when the drag began, which is
     what makes filling a context across several slots quick — round 11 made
     this explicit because rule 5 and the drag matrix otherwise read as
     contradicting.
  6. Every bind echoes its full address to chat:
     `bound Addendum: White -> light-arts / set 1 / left / slot 3` (ASCII only
     — FFXI chat renders multi-byte glyphs as mojibake).
- **Rename and re-icon in the binder** (added 2026-08-15): the stack panel's
  row for the layer being edited carries that entry's label and icon, both
  changeable in place — the mouse equivalent of the `alias` and `icon`
  commands, writing the same `alias` and `icon` fields on the same entry.
- **Hover tooltips, edit mode only** (decided 2026-08-08). XIVHotbar2 shows a
  description panel when the cursor rests on a slot; the played crossbar is
  hold-a-trigger with no cursor on screen, so tooltips belong to the binder or
  nowhere. Hovering a **catalog entry or a slot** in edit mode opens a small
  panel beside it carrying **only what the component already knows** - name,
  type, target, MP/TP cost, recast, skillchain property, and for a slot, which
  layer the entry comes from and which layers below it are covered.

  **No game description text** (explicit scope decision): Windower's resources
  carry item descriptions but not spell or ability ones, which is why the
  reference vendors 3,256 lines of them (`priv_res/spell_descriptions.lua`,
  `ability_descriptions.lua`). Vendoring costs another licence notice and goes
  stale with every content update; extracting from the client's DATs is
  architecturally plausible now that `read_dat` exists, but those offsets are
  unresearched. Neither is worth it for data we mostly hold already - and the
  owning-layer line, which no reference has, is the part a binder actually
  needs. Backlog if it is ever missed.
- **Drag and drop** (specified 2026-08-08; reference implementation is
  [XIVhotbar2-Petit_Trois_Edition](https://github.com/WGINC/XIVhotbar2-Petit_Trois_Edition),
  a descendant of xivcrossbar's ancestor — Kevin does not use its drag/drop
  because of the defects called out below). Four gestures, and nothing else is
  a drag:

  | From | To | Result |
  | --- | --- | --- |
  | catalog entry | a slot | bind it there, in the layer under the `EDITING ->` cursor |
  | catalog entry | anywhere else | **no-op** — the drag is abandoned silently |
  | a slot | another slot | whole-stack swap (the mouse frontend of `swap`) |
  | a slot | anywhere else | **unbind the cursor's layer only** — never the whole stack; no-op when no layer row is selected |

  Because the catalog only unlocks after a layer row is clicked, a catalog
  drag always has an explicit layer already — the drop inherits it, so
  drag-to-bind cannot bypass the two-step safeguard. The cursor stays on
  screen throughout, and dropping onto a *different* slot than the one whose
  stack is open binds into **the same named layer** on that slot, which is
  what makes filling a context across several slots quick.

  **Three defects designed out of the reference**, each verified in its source:

  1. **One hit-test, not two.** The reference resolves picker drops with
     `ui:get_slot_at` (`get_slot_xy` + `image_width/height`) and slot-drag
     releases with `move_boxes:check_slot` (`icon_lib:get_slot_x/y` +
     `icon_lib:get_width/height`) — two implementations of the same question,
     from different sources, so the drop zones can disagree. Ours resolves
     every drop through the single `render.lua` slot-geometry function that
     already draws them.
  2. **A drag threshold.** The reference has none: mouse-down on a slot arms
     the drag and any release resolves it, so a plain click is a
     zero-distance drag whose fate depends entirely on the hit-test agreeing
     with itself. Ours: a press becomes a drag only after the cursor leaves
     the origin slot's bounds; below that it is a click and opens the stack
     panel, exactly as before.
  3. **Replace in place, never remove-then-insert.** The reference removes
     the occupant and then inserts, non-atomically — its own debug string
     concedes the remove can succeed while the insert fails, losing the
     original. Ours writes the new entry over the old in one operation.
- **Contexts in the binder**: the stack panel lists the code-defined roster —
  there is nothing to add, remove, or reorder (definitions and order are code).
  A context row shows its overrides for the clicked slot and previews the bar
  under that context when clicked.
- **Catalog** (v1 scope decided): spells, job abilities and weaponskills
  actually available — `windower.ffxi.get_abilities().job_abilities` /
  `.weapon_skills`, `windower.ffxi.get_spells()` filtered by job and level with
  main and sub merged. xivcrossbar's `get_spells_for_job`
  (`action_binder.lua:1416/1860`) is the reference for the *shape* of the
  filter but **not for its level test** — see defect ⑩. Ours: include a spell
  when it is **known** (`get_spells()`), the job **can** know it
  (`levels[job_id] ~= nil`), and either the level requirement is met **or it
  exceeds the level cap (99) and the job in question is the MAIN job** — an
  above-cap value means the spell is gated by merits or job points, which
  only apply to the main job (round 11; same main-only rule as the stratagem
  JP gift, ~85% on the game semantics), and having learned it is proof the
  gate was passed. On the sub job the strict level test stands, so merit
  spells are correctly absent from a merged sub list. The same rule applies
  to job abilities —
  plus items, mounts, trusts, and our built-ins (`draw`, `mr`, the open actions).
  Scope notes: **`warp`** appears as a single "Warp" entry
  (`items/warp-ring` icon) - the ladder is resolved at fire time, not bound;
  **`ra`** appears in the catalog as a single "Ranged Attack"
  entry (upstream precedent, `ranged` icon); **`pet`** commands stay CLI-only
  in v1 (pet command coverage varies too much by job to catalog blind —
  backlog). The catalog's **"Attack" entry is the `draw` built-in** (decided 2026-08-06) —
  picking Attack binds the state-aware sheathe/dismount toggle, not a bare
  `/attack` line. `ct`/`ex` stay CLI-only in v1.
- **Mouse precedent**: xivcrossbar's selector grid already click-selects
  (press/release on the same cell submits; handler registered at `action_binder.lua:2407`); our binder
  generalises that to the whole flow.
- **Framework touchpoint**: edit mode needs mouse dispatch to a component
  outside layout mode — same shape as the keyboard touchpoint (registered while
  a component asks, blocking decisions propagate). Added to the touchpoint list.

## Testing strategy

Pure modules with plain tables; the fake prim recorder in `tests/support/fakes.lua`
covers the widget level.

- **`input.lua`** — the bulk of the value. Scripted `(dik, pressed, blocked)` streams:
  every row of the hold-state table (asserting the canonical ids); the
  held-set → hold-state function for
  every enumerable state, Expanded in each press order with release of either
  falling back to the survivor's XHB side; the layer key in both press orders
  (`\`-then-`[` and `[`-then-`\` both = WXHB left), layer release dropping
  back to the XHB side, the layer alone → no intent, both sides + layer →
  Expanded unchanged (the normative no-op);
  the draw gesture (layer held, no side active: switch tap → `draw` intent and
  no `cycle`; switch chorded with a slot key → `jump n`); **the switch inert
  while any side is held** — no `cycle`, no `jump`, no `draw`, while still
  blocked, and slot keys in that state firing their slot rather than jumping; switch-chord vs switch-tap (a chord followed by
  release emits no cycle); backtick always blocked, held or tapped, hold state active
  or not; shortcut keys (bare tap → its `tap` verb, tap with any activator held
  → its `chorded` verb, always blocked, any press exiting edit mode while edit
  mode is on); slot keys with no hold state active and backtick up never firing and
  never blocked; the block decision exactly per the Blocking rule (slot keys
  blocked while a hold state is active OR backtick held; backtick and shortcut keys
  always; nothing else ever); chat_open suppressing action intents but passing `activate` (an activator
  released mid-chat emits `activate none` — the widget-visible assertion, not
  just internal state);  auto-repeat
  streams firing each action exactly once; inbound-`blocked` events producing
  no action intent and no block while still updating state and `activate`; `lose focus` clearing all held
  state; suppression/disabled full inertness (nothing blocked, backtick
  included); an
  activator still "held" across a suppression transition or reload not stranding
  state.
- **`bindings.lua`** — per-job load, defaults merge, sets/views resolution (a view
  pointing at any set+side, both Expanded views at the same side resolving
  identically), `active_set` persistence; **shared-store resolution**: a shared set
  reads/writes `SHARED.lua` from any job, a job set never does, flipping the flag
  swaps stores without destroying the dormant contents, and `copy <JOB>` copies job
  sets only; **cycle**: skips empty sets *and* sets outside the current weapon
  state's rotation — where weapon state is the component's machine: `draw`
  toggles both ways, in-game engagement enters drawn, in-game disengagement
  is ignored, initial state sheathed on attach/job change/reload (wrap-around,
  all-excluded → no-op, drawn vs sheathed producing
  Kevin's example rotations from his flag layout), while **jump** reaches any set
  including empty and non-rotation ones; unknown job; and that one job's bindings
  can never be written into another job's file. **Layer resolution**: topmost
  active wins per slot; sparse subjob overrides only where present; context
  activation computed **from a full buff list, never deltas** — the spurious
  arts-`lose buff`-during-Addendum scenario must NOT drop the arts layer
  (predicate `any_of` implication: 401 alone keeps `light-arts` active); the
  no-change short-circuit skips rebuilds; stacked contexts resolve by roster
  order (arts under addendum); an inactive context never contributes; context
  overrides come from the current main job's file only (SCH's Light Arts layout
  does not leak onto RDM/SCH until bound there);
  layer-targeted writes (`sub:`, `ctx:`) land in the right structure and never
  touch the base; **whole-stack swap**: every layer's entry exchanged between
  two addresses, including across a shared-set/job-set store boundary, swap
  with an empty stack (= move), same-address no-op, persistence of both files
  when the stores differ; the full SCH scenario end-to-end (stratagem slots
  swapping between Light/Dark Arts contexts, Addendum overriding a WXHB side).
- **`catalog.lua`** — from injected known-spell/ability tables and resources:
  main+sub spell merge, category grouping, items/mounts/trusts inclusion,
  built-ins present, `ct`/`ex` absent (v1), unknown/empty inputs → empty
  categories rather than errors. **Level filtering, with defect ⑩ as a named
  regression**: a known spell at or under the job level is included; a known
  spell above it is excluded; **a known spell with an above-cap requirement
  (merit spells — Refresh III at 1200 is the fixture) is included**; an
  unknown spell is excluded whatever its level; a spell the current job cannot
  know is excluded even when known; and the same four cases for job
  abilities.
- **`actions.lua`** — command string per type (`ma`—incl. trusts/`ja`/`ws`/
  `item`/`pet`/`mount`/`ra`—no action name/`ct`/`ex`),
  target suffix present and absent, quoting of names with spaces and apostrophes
  (`Ascetic's Fury` is a real weaponskill),
  `ex` *not* prefixed with `input`, `open` resolving through `openers.lua`
  (command entries → `send_command`, key entries → sequences) with unknown
  names rejected at bind time, and `draw` resolving
  mounted → dismount, engaged → disengage, idle → engage by that priority (a
  mounted-and-somehow-engaged state dismounts) with the no-target hint covered. Openers emit
  their full `setkey` down/up sequence immediately and unconditionally — v4
  holds no modifiers, so nothing can contaminate an injected chord. Built-in
  dual-frontend: the command form and the slot form of `draw`/`mr`/`open` resolve
  to the same execution, each entry resolves an icon (including `draw`'s
  state-dependent swap), and a built-in name colliding with an authoring verb is
  rejected at load.
- **`warp.lua`** — the priority ladder resolving to the right plan for every
  rung: BLM main vs sub vs neither, spell known/unknown, MP at 99/100 and
  149/150, ring present but bag disabled, ring with zero charges, ring on
  recast vs ready, cudgel fallback, Instant Warp as a plain consumable,
  nothing available -> a hint not a crash; `status > 1` blocking items;
  priority order asserted **deterministically** (the upstream `pairs` bug);
  English naming.
- **`enchanted.lua`** — charges/recast maths from injected extdata
  (`next_use_time + 18000 - now`, `activation_time + 18000 - now`), warmup
  fraction for the slot overlay, ready/not-ready boundaries, and the
  equip -> wait -> use plan including the give-up rule (abandon when the
  remaining delay exceeds 30 s; 29 s waits, 31 s aborts).
- **`roulette.lua`** — KI list → owned mounts (category filter, whistle exclusion,
  music-note-prefix matching via the byte-escape literal), chunk `0x055` refresh, mounted-buff → dismount, empty list →
  no-op, pick uses the injected RNG and stays in range.
- **`skillchain.lua`** — WS → property list for single-, double- and triple-property
  skills and an aeonic; unknown WS → no icon, not a crash; **chain resolution**:
  active resonation × bound action → resulting property (combo-table entries,
  JA-by-recast_id, closed window → none, level rules; no aeonic behaviour —
  dead upstream); window
  state machine across waiting → open → expired with an injected clock; no
  target / dead target → no indicator and no chain results.
- **Ninja tool counts** (pure): spell -> tool -> master tool resolution for
  each family; **master tools counted on main NIN and ignored on sub**; the
  `99+` cap at 99/100; the colour bands at 50/51 for plain and total; the
  zero state producing the crossed-out slot; a ninjutsu whose tool the player
  has none of, and a non-ninjutsu spell producing no count at all; Corsair
  cards resolving through Trump Card the same way.
- **Stratagem counter** (in `render.lua`'s plan or its own pure helper): max
  charges at each level boundary (9/10, 29/30, 49/50, 69/70, 89/90), the JP
  gift at 549/550 **for main SCH only**, available = `max - ceil(recast /
  charge_time[max])` across a full recast sweep, zero and full states, and —
  the named regression — **the counter drawing on `RDM/SCH` as well as `SCH`**
  (Kevin's own fix), while a non-SCH job draws nothing. Only the sixteen
  stratagem-consuming abilities carry the number.
- **Visibility and activation** (`render.lua`'s plan): the full state table —
  XHB always drawn, WXHB drawn on `always_show_wxhb` or its own gesture,
  Expanded replacing both while held, drawn centred on the `main` anchor,
  and restoring them on release; the active-side panel following the held key and clearing when nothing is held;
  no side active while the component is suppressed or hidden.
- **`render.lua`** — compact cross geometry for all 8 slots against the constants in
  Reference facts **using our slot map**; per-anchor scale; per-anchor bounds; the radial recast sweep — observed-maximum
  denominator (raised when a larger value arrives, cleared at zero, correct
  when first seen mid-cooldown), `frame = max(1, floor(fraction * 32 + 0.5))`
  across a full sweep, frame 32 at the start and hidden at the end, and the
  fraction structurally never exceeding 1 (defect ⑦ cannot recur); right-justified
  cost/recast offsets; the metrics function never mutates its input (defect ②).
- **Framework (multi-anchor)** — in `layout_spec`/`layout_mode_spec`/`overlay_spec`
  plus `core_spec`: hit-testing picks the right anchor, dragging one anchor does
  not move the other, per-anchor persistence, per-anchor overlay highlights,
  `//hud list` output and the off-screen clamp repair iterating anchors (the
  file-local `describe`/`apply` helpers in `core.lua`), right-click toggling
  the whole component (all anchors), and single-anchor widgets unchanged
  through the same paths.
- The shared fake widget (`tests/support/fakes.lua`) grows the optional
  `anchors()` member and the `attach` third argument alongside CB2/CB3.
- **Framework (input dispatch)** — in `core_spec`: a component's `true` return
  propagating out of the keyboard/mouse dispatch, the guard's `false` fallback
  on a dead handler, dispatch inert while layout mode is on, and registration
  released on unload.
- **`crossbar_commands_spec.lua`** (added after review — the CLI previously had
  no spec): every verb happy-path, the layer prefixes (`sub:`, `ctx:<name>:`),
  slot-name aliases, `swap` addressing, `wxhb` toggling and reporting
  `always_show_wxhb`, `alias`/`icon` writing only the
  `alias`
  and `icon` on the addressed entry, honouring layer prefixes, clearing when
  the final argument is omitted, and refusing an empty slot or an
  unresolvable icon; the `open` and `cycle` bare-vs-args overloads, and every validation rejection with its hint line.
- **`crossbar_binder_spec.lua`** (added after review): the binder's pure state
  machine against fake prims — catalog locked until a layer row is clicked,
  target cleared on slot change and panel close, preview resolving through a
  simulated buff list (dark-arts preview deactivates light-arts; addendum
  preview activates both), source-tag derivation per slot, edit-mode teardown
  leaving no prims; and the **drag matrix**: catalog->slot binds into the
  cursor's layer (including onto a slot other than the one whose stack is
  open), catalog->elsewhere is a silent no-op, slot->slot swaps whole stacks,
  slot->elsewhere clears **only the cursor's layer** (other layers survive,
  and with no layer selected nothing is cleared); hover tooltips resolving
  from known data only (name/type/target/cost/recast/SC property, plus the
  owning layer and what it covers for a slot), following the cursor between
  targets and clearing when it leaves; a press that never leaves the origin slot resolves
  as a click and opens the panel, not as a drag; every drop resolves through
  the same slot-geometry function `render.lua` draws with; a bind over an
  occupied slot replaces in one write and never clears first.
- **Widget level** — per-anchor group move, destroy disposes every prim, render plan
  → prim calls, preview mode showing sample sides and restoring live state on exit.

In-client smoke (Windows/Windower, per milestone): the XHB sits on screen with
nothing lit, a held side key lights that side and releasing unlights it, the
WXHB obeys `always_show_wxhb` and appears on its own gesture regardless,
Expanded replaces both while held and restores them on release; each of the 8
slot keys fires the right action; both side press orders reach the right
Expanded view;
typing in chat fires nothing and the number keys reach the chat box; jump reaches
any set while cycle skips empties and visits the drawn vs sheathed rotation
(engage manually -> combat rotation; kill the mob -> it stays; press draw ->
sheathed);
a shared set follows a job change while a job set does not; a bound open action
opens the equipment screen;
mount roulette mounts and dismounts; the draw toggle engages and disengages from
both a slot and `//bind`; gaining Light Arts swaps the overridden slots and
losing it swaps them back; edit mode binds a clicked slot to a chosen layer and
the stack panel shows the winner; recasts sweep; the number row reaches the
game when no hold state is active (and the dead keys never do, blocked as
ours); the skillchain indicator tracks a real chain; XHB and
WXHB drag independently in `//hud layout` and both persist; cutscene hide;
`//lua reload xivhud` leaves no prims and no lost keybinds.

## Milestones

Each lands green (`busted` + `luacheck` + `stylua --check`) before the next.

- **CB0 — input state machine.** `input.lua` + spec — fed `(dik, pressed,
  blocked)` plus injected state accessors per the repo's `new(deps)` shape
  (`chat_open`, suppressed/disabled, edit-mode flag). No framework dependency; can
  start immediately and is the highest-risk piece. *Accepts when* every row of
  the hold-state table, every enumerable held-set state, the Expanded
  press-order and release-fallback cases **including re-press** (`[`↓ `]`↓
  `[`↑ `[`↓ = `expanded_rl` — "first" means first of the *currently held*
  pair; caught live in the spike 2026-08-08), every
  switch-chord/tap and shortcut case, every Blocking-rule case, and **all six
  mandatory guards** are covered by passing specs — the full input list in
  Testing strategy, not a subset, plus the round-11 guard cases: state
  tracking under inbound-`blocked`, and slot-key down-state cleared by a
  release during chat.
- **CB1 — binding model + activation** *(entry gate cleared 2026-08-07: Q10
  and Q11 resolved)*. `bindings.lua` (**layer-aware from day
  one** — retrofitting the stack into flat storage later would be a rewrite),
  `actions.lua`, `roulette.lua`, `warp.lua`, `enchanted.lua`, `openers.lua`,
  `contexts.lua` (the roster), `defaults.lua` + specs. Still no
  framework dependency. *Accepts when* a `(job, set, side, slot)` address
  resolves through the full layer stack to the exact command string / key
  sequence / roulette behaviour specified, for every bindable type; the
  shared/cycle model reproduces Kevin's example layout (6–8 shared +
  sheathed-only, 1–2 drawn-only, 3–4 job-specific and jump/view-only); and the
  SCH context scenario (Light Arts → Addendum → stratagem swap) resolves
  end-to-end in specs.
- **CB2 — framework: input + config plumbing.** The always-on blocking-capable
  keyboard dispatch (touchpoint 1), component mouse dispatch (3), the new `ctx`
  deps **and the event-forwarding mechanism** (4 — the entry-point wiring; the
  crossbar *consuming* those events goes live at CB5), and the directory config
  namespace (5), with specs in `core_spec`/`settings_spec`; touchpoint 6 (the
  `lib/` icon-extractor promotion) is **authored in this branch** (decided
  2026-08-08) as its own commit, landing with CB4 — the first icon consumer —
  with equipviewer green throughout. Ships behind a
  component that only logs what it would have fired. *Accepts when* a component
  can block a key in-client and the handler survives `//lua reload xivhud`.
- **CB3 — framework: multi-anchor contract** (touchpoint 2) + specs across
  `layout`/`layout_mode`/`overlay`, plus the `core.describe`/`core.apply`
  anchor iteration. *Accepts when* a three-anchor test widget drags,
  scales and persists each anchor independently in-client, and
  parambar/giltracker/partylist-trio pass untouched.
- **CB4 — render.** `render.lua` + `crossbar.lua`, the deliberate asset-subset
  import with `LICENSE.txt` and the sampling extension of `check_assets`
  (a few icons per imported category, hand-listed per the partylist
  convention, `XIVHud.lua:698-743` — see Packaging consideration), and the
  `lib/` extractor promotion (touchpoint 6) if item slots are to show real
  item art, registered, XHB anchor only — **the persistent 16-slot XHB with
  its active-side panel**, no recast/cost yet. **Until CB7 lands, milestone verification authors bindings
  by hand-editing `data/<Character>/crossbar/<MAIN>.lua` (and `SHARED.lua` for
  the shared-set acceptance)** — the file format is
  deliberately readable for exactly this. *Accepts when* the XHB sits on screen
  in-client, correctly laid out and inactive; a held side key panels that side
  and releasing clears it; and `//hud layout` drags and scales it.
- **CB5 — activation + all sides + sets + live state.** **Slot presses execute
  their bound actions from this milestone on** (CB2's log-only stand-in
  retires — added in round 3, execution previously had no milestone home);
  WXHB (own anchor) and Expanded Hold wired; set jump/cycle; the crossbar
  consuming the `job change`/buff events with per-job reload live (CB5's own
  acceptance depends on them); recast sweep and
  animation, MP/TP cost, unusable dimming, press feedback, the SCH stratagem counter,
  ninja tool counts;
  the prim-budget measurement (touchpoint 7); in-client verification of the opener entries and
  the `draw` disengage spelling. *Accepts when* each of the 8 slot keys fires
  the right action in-client, every hold state is reachable with the documented
  inputs, cycle honours emptiness and the drawn/sheathed rotation flags
  (engaging in game brings up the combat rotation; a mob dying does not drop
  it; `draw` returns to sheathed), a shared set
  shows identical contents after a job change, and recasts visibly track.
- **CB6 — skillchain.** `skillchain.lua` with the property tables **and
  chain-resolution tables** transcribed, live per-slot chain-result icons
  (with the frame animation), the window indicator on its own anchor.
  *Accepts when* the indicator tracks a real chain in-client and a bound WS
  shows the property it would actually form against the open resonation.
- **CB7 — authoring (CLI).** The `//hud crossbar` command set including layer
  prefixes and `context list`, `copy <JOB>`. *Accepts when* a binding made in-client survives a job
  change and a reload, and the SCH scenario works in play (Light Arts up →
  slots swap, Addendum up → WXHB side swaps).
- **CB8 — edit mode + the binder.** `catalog.lua`, `binder.lua`, the mouse
  touchpoint exercised, stack panel + context preview, source tags, the
  explicit two-step target rule, hover tooltips. *Accepts when* Kevin can build his SCH layout
  in-client entirely by mouse — binding into the arts and addendum contexts —
  without once editing a layer he didn't mean to, every slot's source is
  identifiable without clicking it, and **Refresh III and the other merit
  spells appear in the catalog and bind** — the defect that drove him off the
  reference fork; **and the drag matrix and tooltips behave as specified**
  (all four gestures, the layer-only unbind, tooltips from known data).
- **Backlog** (order TBD): auto-switch on draw/sheathe; "return to XHB after WXHB
  input"; face-buttons-only WXHB (note: "always display WXHB" left the backlog
  2026-08-15 — it is core config now that the bar is persistent); non-compact layout; theme + icon-pack resolution;
   consumables, and the rest of the enchanted-item
  surface beyond what `warp` needs (xivcrossbar's `enchanteditem` bind type
  for arbitrary items — `enchanted.lua` lands at CB1 as warp's dependency, so
  this becomes a binding/catalog question, not new machinery); `ct`/`ex` entry in the binder (needs keyboard text
  capture in edit mode; xivcrossbar's `environment_chooser` proves it possible);
  **evaluate migrating partylist onto the multi-anchor contract** (Kevin,
  2026-08-07). Round 7 caveats recorded: partylist's alliance lists default
  hidden and toggle independently (`//hud show|hide alliancelist1`), which
  the contract cannot express while `visible` stays per-component — the
  migration therefore *requires* per-anchor visibility as a contract
  follow-on — and CLAUDE.md records one-dir-many-names as a deliberate
  convention, so the migration is a decision to revisit post-CB3 with the
  anchor work in hand, not a foregone conclusion; more context condition types (level, weapon, zone);
  `pet` catalog entries;
  per-hold-state disable.

## Open questions

1. **Input map: v4 decided 2026-08-08 and verified in-client** — no
   modifiers; `[`/`]` sides, `\` layer, backtick switch, `=` shortcut, number
   row slots, all config-with-defaults. Every key confirmed free and
   blockable. Residue: **(a)** injected-key echo (one console command, before
   CB2); **(b)** the layout-mode interaction — layout mode uses plain CTRL for
   free-drag, which v4 no longer touches at all, but component keyboard
   dispatch (touchpoint 1) is still built **inert-during-layout-mode** so the
   two can never contend. Verified in-client at CB4.
2. **Does event-level blocking suffice without `unbind`? Answered
   2026-08-08: yes for unchorded keys, no for modified ones.** `return true`
   swallows a bare key completely but does not stop FFXI acting on a Ctrl/Alt
   chord. v4 takes only unchorded keys, so blocking suffices and no
   `bind`/`unbind` pair is needed — the deviation stands as written.
3. **Authoring: resolved 2026-08-06** — the mouse-driven binder (CB8) is the
   primary authoring surface; the CLI (with layer prefixes) and the
   hand-editable per-job `.lua` are the fallbacks.
4. **Per-job granularity: resolved 2026-08-06** — the layer stack (shared store
   < job base < sparse subjob overrides < buff contexts) replaces xivcrossbar's
   MAIN-SUB / MAIN-DEFAULT / ALL-JOBS-DEFAULT file fallbacks. See Binding layers.
5. **Resolved 2026-08-07** — the indicator gets its own anchor, and the
   per-slot icons are live chain results (see the skillchain facts).
6. **Compact metrics: resolved 2026-08-07** — "XIVCrossbar already draws the
   crossbars exactly how I want them"; CB4 transcribes upstream's rendering
   (`ui.lua` metrics, spacing, and compact halving) verbatim rather than
   re-deriving, with defaults kept at upstream's values — "verbatim" scoped
   to the drawing constants; our slot map, the framework anchor (no
   `ui_y_res - 120`), and anchor scaling remain the stated deviations.
7. **Icon licensing: accepted as-is (Kevin, 2026-08-07 — "ignore").** The
   SE-derived-artwork risk stays recorded here for honesty; `assets/LICENSE.txt`
   still names every upstream party.
8. **Open-target coverage: v1 list decided 2026-08-06** (see Open actions) — most
   entries turned out to be slash commands, leaving only equipment/inventory on
   key events. Remaining: in-client verification of each entry once wired, at
   CB5 (Kevin
   reports some game UI resists key events; the command ones should be safe), and
   the table grows entry-by-entry after that.
9. **Resolved 2026-08-08 — drag-to-empty clears only the cursor's layer.**
   Option (b): the unbind removes the slot's entry in the layer under the
   `EDITING ->` cursor and leaves every other layer intact, so the gesture can
   never wipe a stack. Deliberately *asymmetric* with slot-to-slot drag, which
   stays a whole-stack swap: moving a button should take everything about it,
   while deleting should only ever affect the one plane being edited. With no
   layer selected there is nothing to clear, so the drag is a no-op.
10. **Resolved 2026-08-08 — `ta` dropped entirely.** It turned out not to be
   an FFXI command word at all but xivcrossbar's label for a feature it built
   (`SWITCH_TARGET` → `'ta'`, `action_binder.lua:57-126`, hardcoded to
   `<stnpc>` and intercepted at `player.lua:442`). Kevin switches and attacks
   targets with the game's own controls, so the button earns no slot. This
   also removed a live-game-status consumer (the remaining ones are the
   weapon-state entry trigger and `warp`'s `status > 1` item gate).
11. **Resolved 2026-08-07, in Kevin's words**: "There are 8 sets in memory,
    period. Cycling puts one of those 8 sets on the XHB. Those sets are
    saved/loaded from either the job file or the shared file based on
    configuration flags" — e.g. shared = true on 6/7/8 loads those three from
    `SHARED.lua` and 1–5 from the current job's file. That is exactly the
    plan's storage model; the flags (`shared` + the drawn/sheathed cycle
    flags) and the `views` pointers are **one character-wide configuration**,
    as written.
12. **Resolved 2026-08-07** — weapon state is the component's own state
   machine with a one-way game trigger: `draw` toggles it both ways, in-game
   engagement also enters drawn, and in-game disengagement never leaves it.
   See "Weapon state is our own state machine" in the XHB reference facts.

## License & attribution

Seven notices apply and all must land in `assets/LICENSE.txt` (re-verified
2026-08-06 after blind review caught a missing one):

- **MIT, © 2020 AliekberFFXI** — the xivcrossbar repository `LICENSE`.
- **BSD 3-clause, © 2017 SirEdeonX** — per-file headers throughout, inherited from
  xivhotbar; the same author as XIVBar, whose notice parambar already ships.
- **BSD 3-clause, © 2017 Ivaar** — `libs/skillchain/`, from the SkillChains addon.
  Required by CB6, since the property tables are transcribed from it.
- **BSD 3-clause, © 2020 Dean James (Xurion of Bismarck)** —
  `libs/mountroulette/`, carrying its own per-file header. Required by CB1's
  `roulette.lua` port. (An earlier draft wrongly claimed this lib had no header.)
- **BSD 3-clause, © 2026 WG Incorporated** — the radial recast sweep
  (algorithm transcribed into `render.lua`, in-file header + this file;
  the 32 frame images too if imported rather than generated — CB4 decides
  the art, not the notice). From XIVhotbar2 Petit Trois Edition, a fork
  chain descending from SirEdeonX's xivhotbar; intermediate fork authors'
  contributions arrive under that chain's licences, which is also the basis
  for the stratagem-counter port (origin in the chain unconfirmed).
- **BSD 3-clause, © 2018 from20020516** — `MyHome`, vendored as the auto-warp
  library (Icydeath/ffxi-addons). Required by CB1's `warp.lua`, and — like
  the skillchain and roulette ports — its notice goes **in the derived source
  file** as well as `assets/LICENSE.txt`.
- **BSD 3-clause, © 2021 Rubenator** — the icon extractor, from EquipViewer.
  Already reproduced in-repo at
  `src/components/equipviewer/assets/LICENSE.txt`, but that file must stay
  with the component (it also covers `encumbrance.png`), and the extractor
  source today carries only a pointer to it. **If touchpoint 6 promotes the
  code to `lib/`, `lib/icons.lua` gains the Rubenator header in-file** (round
  11 — same derived-source rule as skillchain/roulette/warp), so nothing in
  `lib/` depends on a notice living in a component directory.

Square Enix's underlying rights in the icon artwork are unaddressed by any of
these — see Q7. Our own source files keep the repo's BSD headers, holder
**Azureblood2** — with two exceptions pinned in round 3, because BSD clause 1
wants the original notice retained in derived *source*: `skillchain.lua`
(transcribed tables) carries Ivaar's header, `roulette.lua` (ported module)
carries Dean James's, and `warp.lua` carries from20020516's — each alongside
ours.

## References

- **FFXIV UI guide — the spec** (read 2026-08-05):
  [how to use the XHB](https://na.finalfantasyxiv.com/uiguide/know/know-xhb/xhb_how_to.html),
  [expanded hold controls](https://na.finalfantasyxiv.com/uiguide/know/know-xhb/xhb_hold.html),
  [changing sets](https://na.finalfantasyxiv.com/uiguide/know/know-xhb/xhb_change.html),
  [auto-switching on draw/sheathe](https://na.finalfantasyxiv.com/uiguide/know/know-xhb/xhb_switching.html).
- **akhmorning controller guide — the cross hotbar** (read 2026-08-05):
  https://www.akhmorning.com/resources/controller-guide/the-cross-hotbar/ — source for
  8 sets × 16 slots = 128, the WXHB settings list, and set-switching behaviour.
- **Kevin's xivcrossbar fork** (read 2026-08-06, re-read 2026-08-08): https://github.com/khowe085/xivcrossbar
  — source of the context roster (buff IDs 358/359/401/402), the
  sync-from-buff-list pattern with the spurious-`lose buff` gotcha
  (`sync_arts_overlays`, `xivcrossbar.lua:1135-1178`), and the edit-target
  lineage the binder's stack panel descends from — and, added 2026-08-08, the
  **stratagem charge counter** (`ui.lua:1207-1228`, `consumables.lua:124-142`),
  which is the fork's own addition rather than anything upstream carries.
- xivcrossbar source (artwork, geometry, skillchain tables, roulette):
  https://github.com/AliekberFFXI/xivcrossbar — facts verified against `master`,
  2026-08-05, by reading a local clone. The scratchpad clone is ephemeral; re-clone
  to re-check.
- Upstream lineage: https://github.com/SirEdeonX/FFXIAddons/tree/master/xivhotbar,
  and the XIVHotbar2 forks (aregowe, Technyze) — not read yet; worth a look before
  CB4 for their icon-matching work.
- **XIVhotbar2 Petit Trois Edition** (drag-and-drop reference, read 2026-08-08
  from a local clone): https://github.com/WGINC/XIVhotbar2-Petit_Trois_Edition
  — a descendant of xivcrossbar's ancestor. Source of the drag gestures and of
  the three defects the spec designs out (`lib/move_box.lua:261-290`,
  `lib/ui.lua` `get_slot_at`, `xivhotbar2.lua:653-694`). Kevin does not use its
  drag/drop for these reasons. Also the source of the **radial recast sweep**
  (`lib/ui.lua:2015-2054`, `images/cooldown/`), which we adopt over
  xivcrossbar's wipe. Licensed BSD 3-clause (c) 2026 WG Incorporated.
- MyHome source (auto-warp ladder, extdata usage, IPC broadcast):
  https://github.com/Icydeath/ffxi-addons/tree/master/MyHome — verified
  2026-08-08 from a local clone.
- Windower `setkey` (key injection; syntax verified 2026-08-08):
  https://docs.windower.net/commands/input/ — `setkey [keyname] [state]`,
  states `down`/`up`; the docs publish no official key-name mapping.
- Windower events (no gamepad event exists): https://github.com/Windower/Lua/wiki/Events
- Framework plan: [xivhud-implementation.md](xivhud-implementation.md) — widget
  contract (to be amended by CB3), visibility resolver, settings service, layout slots.
- Sibling component plans for the established shape:
  [parameter-bar.md](parameter-bar.md), [giltracker.md](giltracker.md).
