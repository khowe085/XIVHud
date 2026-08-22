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
| **XHB** | the bar showing the active set, permanently on screen. Holding a side key activates that side — FFXIV: LT → left, RT → right; ours: `;` → left, `'` → right. |
| **WXHB** | "double cross hotbar" — a second bar; FFXIV reaches it by double-tapping a trigger, ours by the `\\` layer key (v4, 2026-08-08). |
| **Expanded Hold** | a further **single side** (8 slots, not a full bar) reached by holding *both* activators (FFXIV: both triggers; ours: `;`+`'`); the press orders are distinct. |
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
  that toggles the weapon state.
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
  | XHB left | `;` | 39 |
  | XHB right | `'` | 40 |
  | W-layer | `\` | 43 |
  | Slots 1–8 | `1`–`8` | 2–9 |
  | Set switch | `` ` `` | 41 |
  | Shortcut (Select) | `=` | 13 |

  **All six verified in-client 2026-08-16**: each is silent under blocking,
  and the model itself — hold states, the layer, slot firing, auto-repeat and
  the chat guard — was exercised on them and behaved. The map is settled.

  - **`;` → XHB left, `'` → XHB right**; **both held = Expanded Hold**,
    order-sensitive as in FFXIV (`;` first → `expanded_lr`, `'` first →
    `expanded_rl`).
  - **`\` is the W-layer**: `;`+`\` → WXHB left, `'`+`\` → WXHB right. A
    dedicated layer *replaces* FFXIV's double-tap, which Kevin has always found
    cumbersome and which xivcrossbar implements with a confirmed-buggy window
    (defect ⑧). `\` alone activates nothing.
  - **Set switch `` ` ``**: held + slot key jumps to that set, tapped alone
    cycles. **Draw gesture** = `\` held + `` ` `` tapped with no side active.
  - **"It opens the chat log" is not evidence a key is free** (learned the
    hard way, 2026-08-16, and the reason two maps died). `[` and `]` passed
    that test and were adopted as the side keys; in fact `]` hides the game
    UI and `[` takes a screenshot, and **blocking stops neither** — the same
    class of failure as the macro chords that killed v3. The only test worth
    running is: with blocking on, does the game still react? Every key in the
    table above has now passed it.
    They are ours exclusively while the crossbar is live; the chat guard hands
    them back the moment the chat box has focus, so they remain typeable.
  - **FFXI's macro palette is untouched** — Ctrl/Alt+1–0 keep working, and the
    game no longer flashes its macro bar on every crossbar hold, since we hold
    no modifier. Both were costs of v3 that v4 simply removes.
  - The map ships as **config** (a DIK table per role) with the above as
    defaults — which is what made this pivot a table edit rather than a
    redesign: the state machine, guards, blocking latch and press-order logic
    carried over from v3 untouched.
  - The bridge is Steam Input's job (AHK is out): LT/RT emit `;`/`'`, bumper
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
| `draw` | sheathe/unsheathe — state-aware, the XIV draw-weapon button | mounted → dismount; drawn → disengage; sheathed → flip to drawn, silently (see below) |

### The `draw` toggle

State-aware, in priority order (mounted first — you cannot engage while mounted,
and Kevin wants the same gesture to dismount, decided 2026-08-06):

1. **Mounted** (buff 252, already tracked for roulette) → `input /dismount`;
   the weapon-state machine does not advance.
2. **Weapon state "drawn"** → disengage, and the state machine flips to
   sheathed.
3. **Weapon state "sheathed"** → flip to drawn and send **nothing at all**
   (revised 2026-08-22; see "No command on the way in" below). No target is
   read, no `/attack` goes out, and no hint is printed — the sword beside the
   set label is the feedback.

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
the vendored lib's commented-out `_addon.commands`), `warp` (MyHome's own `mh` alias was
dropped 2026-08-19 - one name per built-in, and the machinery with it), and
`open <name>` for each entry in `openers.lua`. An entry carries
everything both frontends need: the execution, the command name, **and the
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

Owned mounts = key items of category `Mounts`, matched against
`resources.mounts` names. A mount KI's name carries a music-note prefix,
written as **byte escapes** (`"\226\153\170"`) in our source:
`tests/sources_spec.lua:42-56` forbids non-ASCII bytes outside comments in
`src/` — FFXI chat is not UTF-8. Upstream matches with `windower.wc_match`, a
Windower global; our pure port does a plain **prefix match** — upstream's
pattern carries a trailing wildcard, so equality-after-strip would drop any
KI name with a suffix. Refreshed on **incoming chunk `0x055`** (KI update).

**The quest-only trainer's whistle is excluded by that prefix match, not by
name** (2026-08-19). Upstream tests the name; we do not, because the whistle
carries no note prefix and the match therefore rejects it already. The name
test was removed rather than kept as belt and braces: it is a string literal
that has to track a resource file to stay true, and would go quietly dead the
day the name changed, with nothing failing. It rests entirely on the
whistle's name lacking that prefix — an assumption only our fixture has ever
confirmed, and **in-client question H**. If the whistle does carry the
prefix, it prefix-matches a mount and becomes a rideable entry, and the name
test goes back with a comment saying why it is not redundant.

If buff **252** (Mounted) is up, `/dismount`; if no mounts, no-op; else
`/mount "<random pick>"`. Ported as a pure module with injected KI list,
buff list, mount resources and RNG.

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

### Travel delay (decided 2026-08-19, Kevin)

`mount`, `mr` and `warp` do not fire the moment you press them. They arm a
**five-second countdown**, say so in chat once a second, and then act — so a
mis-press costs you five seconds of reading rather than a trip to your Mog
House. The delay is the point of the feature, not a side effect.

- **Applies to `mount`, `mr` and `warp`**, in both frontends: the typed command
  and a bound slot resolve through one path by design, so they cannot behave
  differently.
- **Not `draw`.** Dismounting is how you get *out* of something; it stays
  instant.
- **`delay = 5` is config, in seconds. Zero means no delay** — the setting is
  the off switch, so no separate verb is needed.

**The countdown speaks every second** (Kevin's call over a quieter opening line
only): the first line names the action, the span and the way out, and the rest
are the seconds remaining.

```
crossbar: Mount roulette in 5 seconds. /heal to cancel.
4...
3...
2...
1...
```

**The named lines carry the component's prefix, the counts do not** (decided
2026-08-19): every other line the crossbar says is prefixed, so the line that
arms a countdown and the one that cancels it are too - but a bare count reads
as a continuation of the line that named it, and five prefixed lines per mount
is the chat spam this repo treats as a defect elsewhere.

**Resting cancels it.** `/heal` is the idiom, but the trigger is the *status*,
not the command text — `Sel-Include.lua:2313` does exactly this, cancelling a
pending item on a status change away from Idle or Engaged, and it catches
resting however you entered it. Ours cancels on resting and on the transitions
CB9 already treats as the end of a moment: zone, death, logout, job change and
suppression. A cancel says so (`Mount roulette cancelled.`) rather than going
quiet.

**And on the config modes** (Kevin, 2026-08-19): `//hud layout` and the binder
(`//hud crossbar edit`) each call a countdown off, on CB9's own reasoning - a
late action fires only where a fresh press would, and opening a config mode
means you are not playing just now. Both directions are covered, from one
`config_mode()` test used twice: a mode opened while a trip counts down is
cancelled on the tick, and a trip pressed while a mode is already open is
**refused where it is pressed** rather than armed and cancelled a frame later -
the outcome is the same and it is one line to read instead of two that
contradict each other (`Mount roulette - not while //hud layout is open`). An
instant trip is unaffected: a dismount is the press itself, not a late action.
**An open chat line is deliberately NOT one of these**, unlike the cast retry's
gate: answering a tell while you wait to warp is playing, and a re-send is a
keypress where this is not.

**A re-attach clears it too, silently** (2026-08-19): core re-attaches without
detaching for `//hud reset crossbar` and for the reload `//hud copy` does, so a
countdown armed beforehand would otherwise fire holding a record from the
configuration just thrown away - and unlike the cast retry there is no `bound`
identity guard here to notice. Silent because a reset is not a cancellation the
player needs told about.

**Warp skips the delay only when using the item actually entails a wait**
(corrected 2026-08-19: the first wording said "when the rung is an enchanted
item", which lost the condition Kevin actually stated — *"if it uses an item
that requires a cooldown then it can skip the delay"*). A Warp Ring that must
be equipped and warmed up already makes you wait, with `gs disable` held over
the slot (see **Auto-warp**), and that wait *is* the window this feature exists
to give you — five more seconds on top buys nothing. **An already-equipped,
charged ring entails no wait at all**, so it takes the countdown like a spell:
skipping there would fire an instant warp with no window, which is the
rationale inverted. Spell rungs (Warp, Teleport,
Retrace) take the countdown. The plan is computed at the press to decide which
of the two applies, and **re-computed when the countdown ends** so it acts on
the state you are actually in five seconds later; the two can legitimately
disagree, and the later one wins.

**`warp all` broadcasts when the warp goes, not when it is pressed** (decided
2026-08-19, with the countdown): MyHome's own shape sends first and warps
second, which under a countdown would leave a cancelled press with every other
character already sent home. The IPC message therefore rides the moment the
local warp **commits**, which is three different moments by rung (corrected
2026-08-19, second pass): with the command for a spell, a consumable or a ring
already charged; with the *deferred* use for a ring being equipped and warmed
up - that rung skips the countdown but is not a warp until the item fires, so a
warm-up later abandoned ("took too long", "went missing", suppression) sends
nobody; and at once when the ladder found nothing at all, the alts' own ladders
being independent of ours. A receiver still warps immediately, since the
sender's countdown was the window and a second one on every alt buys nothing.

**Open, on the in-client list**: the numeric player status for *Resting*. The
component works in numbers where GearSwap works in names, and this repo does
not hardcode a platform fact from memory - resolve it from `res.statuses` by
name where the resources library is present, keep a named fallback constant,
and confirm the number in a client.

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
every ability that spends one. Not in upstream xivcrossbar: `strat_charge_time` appears **only** in Kevin's
fork, not in Petit Trois either, and that fork's README reads "Forked off of
AliekberFFXI's xivcrossbar!" and lists the counter under its own Additions.
So it originates there, under that repository's own notices (MIT © 2020
AliekberFFXI, and the BSD © 2017 SirEdeonX header on `ui.lua`) — **not** WG
Incorporated's, whose code does not contain the feature (corrected 2026-08-15).
Wanted here (Kevin, 2026-08-08). Mechanics, read from
`kevin-xivcrossbar/ui.lua:1207-1228`:

- **Charges are one shared pool** on ability recast id **231**; there is no
  per-stratagem timer to read.
- **Max charges** = `floor((sch_level - 10) / 20) + 1` → 1 at L10, 2 at L30,
  3 at L50, 4 at L70, 5 at L90. **Below SCH 10 there are no stratagems**, so
  the formula's zero is not a charge count: the counter draws nothing at all
  rather than indexing `charge_time[0]` (which is nil — an arithmetic error in
  a per-frame path).
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
  framework already forwards — but those carry **only the item id** (the
  quantity is dropped, `XIVHud.lua:862-868`), so each one triggers a
  `get_items()` re-read for the affected tool, giltracker's pattern
  (`giltracker.lua:210`). No new touchpoint, but no count in the payload
  either.

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

### Cast retry (decided 2026-08-19, Kevin)

Casting several spells back to back, FFXI refuses one sent too soon after the
last with **"Unable to cast spells at this time"** and the press is simply
lost. The gap is "usually 1-2 seconds, but" — Kevin's words — and it is worst
exactly when it hurts most, with a lot to get out quickly.

**This is deliberately not a port of Selindrile's MiniQueue** (read at
`Selindrile/GearSwap@77d52f5`, `libs/Sel-Utility.lua`, `libs/Sel-Include.lua`).
Kevin ran it and turned it off. Two things about it decide our shape:

- **It queues on recast, and never expires.** An action blocked by a cooldown
  is held with no timestamp and fired whenever the tick next runs — after you
  have moved on, at whatever you are now pointed at. That is the fighting he
  describes. **We never queue on recast**, and everything we hold has a
  deadline.
- **Its real signal is dead code.** Its `0x029` handler compares
  `action.message`, but Windower's field label is `Message` and the packets
  library declares no aliases (`fields.lua:1919-1927`, `packets.lua:38-41`),
  so the branch never runs. Everything therefore falls back to blind timers —
  a hardcoded per-action-type pacing guess and a 5-second recast heuristic —
  which is where the queue's bad behaviour comes from. **We use the signal it
  intended to use.**

**React, do not predict.**

- A slot press **sends immediately, exactly as now**. A press that would have
  worked is never delayed. This is the reason not to port the pacing model as
  well: a predicted window is wrong in both directions, and a varying gap is
  precisely what a predictor gets wrong and a reactor does not notice.
- The record we sent is remembered with its timestamp.
- An "unable to cast" for us, arriving within a short window of that send,
  makes that record **pending**.
- The tick re-sends after a backoff, bounded by a small attempt cap and a
  short deadline.
- **Any newer slot press replaces pending outright**; zone, death, logout, job
  change and suppression clear it. Nothing can outlive the moment it belonged
  to.

**The target is pinned at press time** (Kevin, 2026-08-19, correcting a first
implementation that got this backwards). A record bound with a volatile token —
`<t>`, `<bt>` — has that token resolved to a **concrete mob id the moment you
press**, and the retry sends the id in place of the token. The cast then lands
on what you were aiming at when you pressed, however far your cursor has
wandered since.

- The **first send is unchanged**: it goes out with the token exactly as it
  always did, so nothing about an accepted press differs.
- **Party and alliance slots are not retried at all** (Kevin, 2026-08-19).
  `<p3>` is whoever is standing third, not a person: a member leaving or
  zoning inside the deadline shifts everyone below them, and the re-send would
  land on someone the press never meant. Pinning them by id would need
  `get_mob_by_target("p3")` to work, which nobody here has read for, so the
  honest answer is not to hold them. `<me>` and `<pet>` stay watched and
  re-send verbatim.
- Only the **re-send** substitutes. Fixed tokens (`<me>` and friends) need no
  pinning; sub-target prompts (`<st>`, `<stpc>`, `<stnpc>`) are never retried,
  since re-opening a selection cursor is not a thing to do behind the player.
- If the pinned target is gone by re-send time the cast simply fails and costs
  one attempt. We do not spend a second client read proving what the server
  will say anyway.
- **This is the one thing the reference implementation got structurally right
  and we first got wrong.** MiniQueue stores `spell.target.id` and re-sends
  `/ma "Fire IV" 16941234` — the raw id. Our first pass instead *dropped* the
  retry when the target changed, which solves the problem backwards: the point
  is to fire what you meant at what you meant it for, not to give up because
  you looked elsewhere.
- **Costs one `get_mob_by_target` per press of a token-targeted spell** — on
  the keypress path, never per frame, and not at all while the feature is off.
  That is the one new client read this milestone sanctions, and it buys the
  behaviour the whole feature exists for.
- **Open, on the in-client list**: whether FFXI accepts a bare numeric target
  id in a command. Selindrile's files depend on it and are widely used, which
  is good evidence and not observation.

**Guards before every retry**, from state the widget already holds:

- still off cooldown (the recast tables the dimming already uses),
- still affordable (`render.cost`'s MP/TP),
- not silenced or amnesia'd (the buff list the contexts already re-sync),
- the slot still holds that record.

A target that has *changed* is deliberately **not** a guard — see the pinning
rule above.

**Recorded limit (2026-08-19): a slot bound in the binder is never retried.**
`catalog.lua` builds its records as `{ type = 'ma', action = <name> }` with no
target word, so CB8’s mouse path — the *primary* authoring surface — produces
exactly the records the pin cannot hold, and the retry ignores them. Only a
binding made from the CLI with an explicit target (`bind 1 l 5 ma "Cure IV" t`)
is watched. This is deliberately **not** patched by having the retry invent
`<t>` for a targetless record: what a bare `/ma "Cure IV"` does in game is
unobserved (in-client question F), and the real question it raises — should
the binder be writing an explicit target at all? — belongs to CB8, not here.

A failed guard **drops** pending rather than spending an attempt: "unable to
cast" has non-timing causes (silence, an area that forbids it, no MP), and a
blind retry would hammer a doomed spell until its deadline.

**Scope: spells, abilities and weaponskills** (Kevin, 2026-08-19 — the
"spells only in v1" line is lifted). Each is refused in its own words, so the
trigger is **per kind** and the message ids are not shared: 17/18 for a spell,
71 for an ability, 72 for a weaponskill. The ability and weaponskill ids are
the weaker guess of the three — the spell pair at least carries the reference
addon's citation — and in-client question C now asks for all three to be
collected in one sitting. A kind with no refusal message is never watched at
all, which is what keeps items, `ct`, `ex` and the built-ins out. **`pet` is
deliberately out too**: a blood pact is an ability by every other measure here,
but it goes out as its own command word and nobody has seen which message
refuses it.

**Blocking buffs are per kind as well**, and pooling them would be wrong:
**silence (6) and mute (29)** stop spells, **amnesia (16)** stops abilities and
weaponskills, and neither set touches the other — a silenced player can still
Provoke, and throwing that retry away would be a defect, not caution.

**No new plumbing.** `0x29` is already dispatched to the component and already
parsed by `skillchain.lua:1281` (message 206, the buff wear-off); this reads
the same chunk for a different message.

Two things are **open, and on the in-client list** — both cheap to observe,
neither answerable from here:

1. **Confirm 17/18 on `0x029`** really are what a too-soon cast produces, and
   that the packet carries an actor we can match to the player. The reference's
   handler has never executed, so nobody has verified this in practice, and a
   trigger built on an unverified id is a guess wearing a citation.
2. **The backoff.** Too fast and the retry collects another refusal. A few
   minutes of casting settles it. It ships configurable and is **tuned
   in-client, not shipped as settled**.

**Off by default until (1) is confirmed**, and switchable at any time with
`//hud crossbar retry off` - which drops a pending cast rather than letting a
last one through. After confirmation the default is Kevin's call — the feature is
low-risk by construction, but its trigger is the one part nobody has seen fire.

**Interaction with GearSwap**: if Selindrile's files are loaded with MiniQueue
on, both systems retry the same press on different timers. `gs c toggle
MiniQueue` off plus this on is the combination that gives the behaviour Kevin
asked for; the wiki should say so when this ships.

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
  different set/sides. Ours is `;`+`'` with the same order sensitivity. SE's
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
  | `draw` action (command, slot, or gesture) while sheathed | → **drawn**, whether or not anything is targeted |
  | Player engages in game (status 1 / 3, via the framework's `status` dispatch) | → **drawn** |
  | `draw` action while drawn | → **sheathed** |
  | Player disengages in game (mob dies, zoning, knocked out of engagement) | **no effect — state stays drawn** |

  **No command on the way in** (Kevin, 2026-08-22, from a live client, in two
  steps). It used to answer "No target to engage." and leave the state alone,
  on the reasoning that `/attack` needs something to attack; that refusal went
  first. Then the `/attack <t>` it sent *with* a target went too, because the
  state is OURS - it picks which rotation is live and lights the sword - and
  asking for the combat rotation is not asking to swing at anything. The
  player engages and picks targets himself, so entering drawn reads no target
  at all and sends nothing. Nothing is said about it either, because the
  **sword beside the set label** is the feedback, which is why the two landed
  together.

  Leaving drawn is deliberately not symmetric: it still sends `/attack off`,
  because an explicit `draw` while drawn means "I am done fighting" - the rule
  the one-way machine above is built on.

  The asymmetry is the point: engaging by any means should bring the combat
  rotation up, but a mob dying between pulls must not flap the bar back to the
  sheathed rotation. **Only an explicit `draw` returns you to sheathed** — it
  means "I am done fighting", and it is harmless when the game already
  disengaged you (the disengage command is a no-op, and the state still
  flips). **Initial value and lifetime** (confirmed by Kevin 2026-08-08):
  session-only, never persisted;
  starts **sheathed** on attach, login, job change and reload — and
  self-corrects on the next engagement.
- **Deferred**: "return to XHB after WXHB input"
  ([#15](https://github.com/khowe085/XIVHud/issues/15)). (This line once also
  carried face-buttons-only WXHB, dropped 2026-08-20 as not wanted, and
  "auto-switch on drawing/sheathing the weapon";
  the table above superseded that on 2026-08-07 — the drawing half shipped as
  the one-way game trigger, and the sheathing half is rejected, not deferred.)

### The hold-state model

v4, decided 2026-08-08 — no modifiers; punctuation activators, `\` as the
W-layer, backtick as the switch. `input.lua` owns it. Rows resolve by
**most-specific held-set wins** (`;`+`\` beats `;`; `;`+`'` beats either),
with one ordering rule: the draw-gesture row outranks the bare-cycle row. The
prose rules below are normative where they elaborate:

| Input (default DIKs) | Result |
| --- | --- |
| nothing held | XHB on screen, no side active |
| `;` (39) held | XHB **left side active** |
| `'` (40) held | XHB **right side active** |
| `;` + `\` (43) held | WXHB shown if hidden, **left side active** |
| `'` + `\` held | WXHB shown if hidden, **right side active** |
| `;`+`'` held, `;` first | XHB and WXHB hidden; **`expanded_lr` shown, active** |
| `;`+`'` held, `'` first | XHB and WXHB hidden; **`expanded_rl` shown, active** |
| `\` held + `` ` `` (41) tapped, **no side active**, no slot key chorded | fire the `draw` toggle |
| `` ` `` held + slot key *n*, **no side held** | jump to set *n* (any set) |
| `` ` `` tapped, **no side held** | cycle to the next non-empty set in the current weapon state's rotation |
| slot keys `1`–`8` (DIK 2–9) with a hold state active | fire that slot |
| shortcut key (`=` 13) tapped | its `tap` verb bare / its `chorded` verb with a side held (blocked as ours, subject to the guards — in edit mode only the `edit`-verb key is live) |
| nothing held | no hold state active — the number row falls through to the game; **our five dedicated keys never do** (see Blocking) |

Resolution rules:

- **The active hold state is a pure function of what is held**: nothing → none;
  `;` → XHB left; `'` → XHB right; both → the Expanded view chosen by press
  order (release one → the survivor's XHB side). **"First" means first of the
  currently-held pair** — re-pressing a released side into a still-held one
  makes the *held* one first (caught in-client 2026-08-08 on the keys of the
  day: side-1 then side-2, release side-1, hold it again must give
  `expanded_rl`).
- **`\` is a layer, not a side**: with `;` → WXHB left, with `'` → WXHB right,
  in either press order; releasing it drops back to the XHB side. Alone it
  activates nothing. **`;`+`'`+`\` = Expanded unchanged** (normative: the
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
  held. The first entry is the pad's **Select** button. It carried a bare
  tap of `open map` until 2026-08-21, when Kevin took it out in a live
  client: a key the component owns outright should not act on its own, and
  the map is one keystroke away in the game anyway. The entry now carries
  only its chord, which is what proves the shortcut mechanism does not need
  a `tap` - the key stays blocked because the ENTRY exists, not because it
  has a verb. What remains: tap with a side held → `edit` (toggle the
  binder); while edit mode is on,
  any press of this key exits it (see the edit mode guard). Default `=` (13).
- **Blocking**: per-key, **latched at press** — whether a key's press was
  blocked decides its release too (a `3` pressed unblocked whose release
  arrives after a side went down must still reach the game, or FFXI sees a key
  held forever). **The latch outranks every guard** (pinned 2026-08-16): if a
  press was blocked, its release is blocked as well, even if chat has since
  opened, suppression has started, edit mode has been entered, the component
  has been **disabled**, or the release arrives with an inbound `blocked`
  flag. **Auto-repeats follow the latch too**, in both directions (pinned
  2026-08-16): a latched `;` repeating into a chat line that has since opened
  must not type, and an unlatched `3` repeating after a side went down must
  keep reaching the game. Disabling mid-hold is the one case where a key we no
  longer want is still swallowed once, on its way up. Releasing a key the game never saw
  pressed is the one outcome none of the guards is worth. Blocked at press: **our five dedicated
  keys — both sides, the layer, the switch and the shortcut — whenever the
  component is enabled**, plus
  slot keys while a hold state is active or the switch is held (the set-jump
  chord must not leak bare numbers to the game). Nothing else is ever blocked.

  The sides and layer are blocked for the same reason as the rest, and it is
  not optional (corrected 2026-08-15 after blind review found the rule
  excluded them): every one of these keys **opens FFXI's chat log** if the
  game sees it, so an unblocked side key would open the chat box on the way to
  activating a side, `chat_open` would go true, and the chat guard would make
  the crossbar inert for as long as the line stayed up. The keys are ours
  outright; the chat guard hands them back once the box already has focus, so
  they stay typeable.

  **Verified in-client**: an unchorded key returns cleanly to us and never
  reaches the game — the property v3 assumed and did not have. Verified for
  every key in the map — see the spike results for which test covered which.

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
  strand an activator "down"). **The latch clears too** (pinned 2026-08-16):
  this trades "never release a key the game never saw pressed" for one stray
  key-up after an alt-tab, which is harmless — a latch surviving into the
  refocused session and swallowing a fresh key's release is not. The spike
  shipped this and it was verified in-client.
- **Edge detection**: all transitions fire on state *change* only — Windows
  key auto-repeat delivers repeated `pressed=true` events for held keys, and a
  held slot key must fire its action exactly once (upstream defends with
  `just_pressed` checks; ours is structural).
- **Suppression**: while the framework suppresses the component (cutscene,
  zoning) nothing fires, but **our five keys stay blocked and state still
  tracks** (corrected 2026-08-16 — an earlier revision had them fall through,
  which by the rationale above would open the chat log mid-cutscene and leave
  the component inert once suppression lifted). Slot keys do fall through:
  they are the game's the moment we are not using them.
- **Disabled**: `visible = false` for the component — `//hud hide crossbar`,
  or right-click in layout mode (2026-08-16: the framework has no separate
  "disabled" state, only visibility and suppression, so this is what the word
  means here). Every key falls through, ours included: the crossbar is off,
  so the keys go back to the game. Only a latched release is still swallowed.
  **Disabled outranks suppressed** (pinned 2026-08-19): a user-hidden
  crossbar keeps its keys with the game through cutscenes and zoning -
  suppression must never re-block keys for a component the player turned
  off. The widget therefore needs the truth about user visibility, not an
  inference from hide/show calls, which core issues for both reasons.
  State keeps tracking, so re-enabling mid-hold resumes correctly — but no
  `activate` is re-emitted until the next state *change*; the widget must read
  `hold_state()` when it comes back (CB5 handshake). A second CB5 handshake:
  **detach calls the focus reset** (or rebuilds the machine on attach) — a key
  released while detached, with core no longer delivering events, would
  otherwise strand held/down/latch state and make the next press read as an
  auto-repeat.
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
  verb; other shortcut keys are inert but **still blocked**, like the rest of
  ours); while edit mode is on, sides, the layer, the switch and
  slot keys fire nothing **though their state still tracks**; our five keys
  stay blocked (same reason as the suppression guard — an unblocked side key would
  open the chat log over the binder), while slot keys fall through. The only
  live input is **a press of the shortcut key that toggles edit** (bare or
  chorded), which exits — that is what "any press exits it" means.

### Verification spike — results (run by Kevin, 2026-08-06)

Two throwaway addons, both under [spikes/](spikes/):

- **[dikecho](spikes/dikecho/dikecho.lua)** — answers *what DIKs arrive*
  (`//lua load dikecho`; `//dik echo`).
- **[inputspike](spikes/inputspike/inputspike.lua)** — added 2026-08-08,
  answers *does the model work and does blocking hold*. A working prototype of
  `input.lua`: the v4 hold-state resolution with an on-screen readout,
  selective blocking with the latch-at-press rule, and **four of the six
  guards** — chat, focus, auto-repeat edge detection and inbound `blocked`.
  Suppression and edit mode need the framework, so they are the component's
  to prove rather than the spike's. Blocking starts OFF;
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
- **Which keys the game will give up** (2026-08-16). Three different tests
  contributed, and it matters which, because each answers a different
  question:

  | Key | Verdict | How it was established |
  | --- | --- | --- |
  | `;` `'` | ours | pressed unblocked: they do nothing in game at all, so there is nothing to take |
  | `\` `/` | ours | `//is probe` — blocked on sight, and silent |
  | `` ` `` `=` | ours | `//is block` — they open the chat log unblocked, nothing when blocked |
  | `1`–`8` | ours while held | `//is block` and `//is bare` — a bare `3` is swallowed |
  | `[` `]` | **not ours** | `//is probe` — `]` still hides the game UI, `[` still screenshots |
  | `-` `,` `.` | **not ours** | `//is probe` — still act in game |

  `/` is spare. `[` and `]` were in the probe run as a control: they
  misbehaved as expected, which is how we know the probe was live.
- **Known art gaps, inherited from upstream's icon sheet** (recorded at CB4
  review, 2026-08-18): four lv1 SP abilities have no id-sheet art anywhere
  (Mighty Strikes, Azure Lore, Bolster, Elemental Sforzo - the files
  `00000.01/.16/.21/.22.png` do not exist upstream either), and (re-counted at
  CB4 round 5 with per-school attribution) **81 spells** - **60 of them the
  entire Geomancy school** (every Indi-/Geo-; recast ids 768+ have no
  id-sheet file and no pack dir, upstream included), 12 trusts, and a
  handful of Blue/Black/White Magic strays - plus **42 non-SP job
  abilities** (Vallation, Rayke, Entrust, the Waltzes, ...), plus **20
  recast-0 pet abilities** (the Astral Flow blood pacts - Perfect Defense,
  Zantetsuken, Chronoshift, Deconstruction - and the wyvern breaths), which
  land on the nonexistent plain `00000.png` by design rather than wear a
  lv1 SP's art. A GEO player should expect blank spell slots out of the
  box, and a SMN binding Astral Flow blood pacts blank ability slots;
  `icons/custom/` or a future pack addition is the route. Those slots
  draw no icon; `icons/custom/` is the user's route. We do not invent art.
  Two semantics to carry into CB5: **`meta.category` is the display form**
  ("Blue Magic", not the raw resource type "BlueMagic") - kebab maps it to
  the pack dir, and a raw type would silently miss the whole directory; and
  the SP sheet's job suffix wants the
  ability's **owning** job, which coincides with the main job for your own SP
  but diverges on a shared set viewed cross-job - the ctx hands render the
  main job, so a cross-job SP slot may draw the viewing job's art. Accepted;
  same behaviour as binding it fresh.
- **The model itself was exercised on the final keys and behaved**: `;`+`\`
  plus a slot key fired the slot exactly once while `repeats` climbed
  separately for as long as the key was held (the auto-repeat guard), and
  with the chat box open `;` typed into it normally (the chat guard handing
  our keys back).
- **Every key stays typeable in chat, `\` included** (confirmed 2026-08-16).
  An earlier revision recorded backslash as untypeable in FFXI; that was the
  spike's probe mode blocking ahead of its own chat guard, not the game. With
  the probe standing down while the chat box has focus, the key types
  normally — which is the chat guard doing what it exists for.
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
two halves stay designed as a pair. Most output keys have one source; the two that do not are called out in the
caveats below (`\` from either bumper, and each slot key from three chords).
With no modifiers left in the map, a shared output at worst drops a key the
edge detection then re-reads — not the stuck-modifier failure v3 risked.

| Physical control | Condition (Steam Input layer) | Emits (DIK) | Crossbar meaning |
| --- | --- | --- | --- |
| LT | held | `;` (39) | XHB Left |
| RT | held | `'` (40) | XHB Right |
| LT + RT | both held | `;`+`'` | Expanded Hold — press order picks LR vs RL |
| LB | chord while LT held | `\` (43) | `;`+`\` = WXHB Left (release LB → XHB Left) |
| LB | long press, no LT | `\` (43) | draw-gesture hold (with an RB tap) |
| LB | regular press | `R` (19) | not mapped — falls through as autorun |
| RB | chord while RT held | `\` (43) | `'`+`\` = WXHB Right (release RB → XHB Right) |
| RB | press, no RT | backtick (41) | tap = cycle, hold + slot button = set jump — **both only with no side held**; tap with LB long-press `\` and no side = draw |
| Select | press | `=` (13) | bare = nothing (still blocked); with a side held = toggle the binder |
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
  chord naming **LT, RT and RB** together, since a Steam chord fires on any of
  the buttons listed in it (Kevin, 2026-08-16 — **not independently verified**,
  and worth five minutes in the Steam UI before CB5: if a chord takes one
  button, this is 24 slot chords rather than 8, and both documents are wrong
  about the count). Ten chords in all, the eight slot buttons plus the two
  bumper-to-trigger pairs that emit `\\`. Leave RB out of the slot chords and
  set jumps have no numbers to chord with.
- **Set switching is unavailable while a side is held** — the model makes the
  switch inert there (see the hold-state rules). On the pad this is belt and
  braces from RT, where RB emits `\\` rather than backtick; from **LT** the
  backtick does still arrive and the addon is what ignores it.

(An earlier revision recorded a "bare key pressed under a held modifier
arrives modified" edge here. v4 holds no modifiers, so it no longer exists.)

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
  WS-only scope cut is withdrawn); worth transcribing rather than rederiving.
  (A leftover sentence restating the withdrawn WS-only cut was removed
  2026-08-15 — the two had been sitting next to each other.)
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
  and every offset. **Four** anchors (revised 2026-08-15) — `main` (the XHB,
  both sides as one unit), `wxhb_left` and `wxhb_right` (**the WXHB's two
  sides move independently**, so it can sit split across the screen where the
  XHB cannot), and `indicator` (skillchain) — each independently positioned
  (touchpoint 2). **Layout mode draws every anchor regardless of config**
  (2026-08-16): with `always_show_wxhb` off the WXHB is invisible in play, so
  without this its two anchors would have no bounds to hit-test and could
  never be placed. `set_preview(true)` shows all four.
  **Expanded Hold has no anchor of its own** (decided 2026-08-15): it is the
  only bar that *replaces* rather than coexists, so it draws **centred on the
  `main` anchor's footprint** — which stays meaningful because `main` remains
  one undivided bar; only the WXHB splits. `get_bounds('main')` reports that footprint —
  the XHB's — **whatever is currently drawn in it**; it must not narrow to the
  eight-slot Expanded box, or an `apply_all()` while both sides are held
  (a cutscene starting, a zone change, `//hud copy`) would clamp against the
  transient box and shift the anchor. CLAUDE.md's "`get_bounds()` must return
  the same origin `set_pos` was given" makes this a contract requirement — eight slots centred across the XHB's sixteen,
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
  (`;` `'` `\` `` ` `` `=`) are ours outright while it runs. **FFXI's own
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
  counters.lua        -- pure: SCH stratagem charges and NIN/COR tool counts
                      --   (lookup tables, main/sub rules, colour bands)
  render.lua          -- pure geometry + per-frame render plan (compact cross, recast)
  defaults.lua        -- config defaults
  assets/
    slot.png frame.png                       -- xivcrossbar ffxiv theme
    cooldown/frame_01-32.png                 -- radial recast sweep, imported
                                             --   from Petit Trois (decided)
    red-x.png                                -- ui/, drawn over a slot whose
                                             --   ninja tool count is zero
    bar_bg_compact.png feedback.png          -- default pack, ui/ (press flash);
    black-square.png frame_step1-8.png       --   recast overlay + frame anim -
                                             --   import-or-synthesise decided at CB4
    icons/...                                -- the CB4-chosen subset: spells, abilities,
                                             --   weapons, elements, skillchain, mounts,
                                             --   trusts, weaponskills, ninjutsu,
                                             --   blue-magic, ui singles
    LICENSE.txt                              -- MIT + BSD notices (see License)
-- and, outside the package, written at runtime beside the addon:
--   <addon>/icons/<item_id>.bmp     extracted item icons (shared, see tp 6)
--   <addon>/icons/custom/<name>.png the player's own slot art
tests/components/
  crossbar_input_spec.lua      crossbar_bindings_spec.lua
  crossbar_actions_spec.lua    crossbar_roulette_spec.lua
  crossbar_warp_spec.lua       crossbar_enchanted_spec.lua
  crossbar_skillchain_spec.lua crossbar_counters_spec.lua
  crossbar_render_spec.lua
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
   both sides together, and Expanded Hold when it replaces it), `wxhb_left`
   and `wxhb_right` (one per side, deliberately splittable), and `indicator`
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
   single component file), and, when this was written, no component received file I/O deps (stale
   since the equipviewer merge — `XIVHud.lua:632-635` hands it `file_exists`,
   `read_dat` and `write_binary`; the conclusion stands, the premise does not) — so this is
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
   prims per bar — the WXHB's two sides are separately anchored but still one
   bar's worth of prims; Expanded Hold is a single side, so half that. Worst resting
   case is XHB + WXHB both drawn = **~290 prims**, plus the active panel and
   the skillchain indicator; Expanded replaces rather than adds, so the
   ceiling is unchanged. Sets are data — switching sets repaints existing
   prims rather than allocating more, and the six hold states share
   2.5 bars' worth (16 + 16 + 8 slots). CB5 settled the shape (2026-08-19):
   **the resting inventory is 363 prims, constructed up front and merely
   hidden when not shown** - 243 images + 120 texts: nine prims a slot (six images, three
   texts) across the forty slots of the three bars, plus the panel and the
   skillchain indicator's pair, pinned by the widget spec's inventory test.
   They are built in the factory `new(ctx)`, at `core.register` time and so
   before login; attach only dresses and lays them out. Whether that resting cost is
   acceptable in the client remains the in-client measurement; if it is not,
   destroy-when-off is the fallback, and the change is confined to the
   widget's build/refresh. The binder is on top of that and never resident: it
   builds its own prims when edit mode opens and destroys them when it closes.

## Settings (defaults, in `data/<Character>/crossbar.lua`)

Bindings live in the per-job files (below), not here.

```lua
{
  -- defaults.lua is a factory `function(screen_width, screen_height)` like the
  -- shipped components' — the four anchor defaults are computed from screen
  -- size. `false` disables an entry (merge_defaults refills nil, never false).
  input = {                        -- DIK codes per role; the bridge emits these
    xhb_left  = { 39 },            -- ;
    xhb_right = { 40 },            -- '
    w_layer   = { 43 },            -- backslash; + a side = the WXHB views
    set_switch = { 41 },           -- backtick; tap cycle, chord jump, ours always
    slot_keys = { 2, 3, 4, 5, 6, 7, 8, 9 },  -- positional: index = slot number;
                                             -- false = "slot n has no key";
                                             -- renamed from `slots` round 11 -
                                             -- three meanings of that word was
                                             -- two too many
    shortcuts = {                  -- dedicated keys -> //hud crossbar verbs
      [13] = { chorded = "edit" },  -- '=' ; pad Select, chord only
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
  delay = 5,                       -- seconds mount / mr / warp count down before
                                   -- they go (Travel delay); 0 is the off switch,
                                   -- seeded from travel.lua like retry's block
  -- framework-owned; per-anchor under the multi-anchor contract (touchpoint 2)
  slots = { default = { anchors = { main       = { pos = ..., scale = 1 },
                                    wxhb_left  = { pos = ..., scale = 1 },
                                    wxhb_right = { pos = ..., scale = 1 },
                                    indicator  = { pos = ..., scale = 1 } },
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
//hud crossbar bind <set> <l|r> <slot> <type> [<action>] [<target>]
                                                  -- ra/draw/mr/warp take no <action>
//hud crossbar unbind <set> <l|r> <slot>
//hud crossbar alias <set> <l|r> <slot> [<name>]   -- relabel a slot; omit <name> to clear
//hud crossbar icon <set> <l|r> <slot> [<icon>]    -- re-icon a slot; omit <icon> to clear
//hud crossbar list [<set>]                        -- bindings on this job
//hud crossbar view <wxhb-l|wxhb-r|exp-lr|exp-rl> <set> <l|r>   -- repoint a view
//hud crossbar wxhb [on|off]                      -- WXHB on screen at rest; no argument reports
//hud crossbar retry [on|off]                     -- cast retry (CB9); no argument reports
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
  **Icon resolution** (pinned 2026-08-15 — the plan previously said only "a
  path under the addon folder", which is not something a user can act on):
  `<icon>` is a bare name, resolved in order —

  1. `<addon>/icons/custom/<name>.png` — the player's own art;
  2. the shipped pack, by the relative name **as typed** — `items/warp-ring`,
     not a kebab of a display name (corrected 2026-08-19 at CB7 review: both
     `render.icon_candidates` and the `icon` verb take the name verbatim; the
     kebab rule applies to names the component derives from game actions, not
     to what a user types here)
     the catalog uses, so `mount`, `attack`, `map` and the other singles work
     by name.

  User art wins, so dropping `attack.png` into `icons/custom/` re-skins every
  slot using it without renaming anything. The folder sits beside the
  extracted item cache (`<addon>/icons/`), for the same reason that cache is
  not under `data/`: `//hud copy` enumerates `data/` directories as
  characters. Both are outside the package, so neither is touched by an
  update. Any size loads (prims are `fit(false)` + explicit `size`), 40x40
  matches the slots. An unresolvable name is rejected at entry rather than
  drawing nothing later.
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
  **Deferred out of v1 at CB8 (2026-08-19), to the same backlog item as
  `ct`/`ex` binder entry.** Showing the label and icon lands; changing them
  does not. Both values are free text - a rename is an arbitrary string and an
  icon override an arbitrary path fragment - so neither can be a click target
  the way a catalog entry is, and enumerating every shipped icon as a second
  picker would still leave `alias` unreachable. Taking text means a keyboard
  capture mode: `input.lua` would stop resolving DIKs into crossbar intents
  and start accumulating characters, with shift state, backspace,
  enter/escape, and a blocking policy that keeps every typed key off the game
  while a field has focus and returns them the instant it closes. That is
  precisely the machinery the `ct`/`ex` backlog item already needs, so the two
  belong together rather than half-built here. `//hud crossbar alias` and
  `//hud crossbar icon` write the identical fields on the identical entry
  meanwhile, and the binder's panel shows the result immediately.
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
  needs.

  **Reopened and settled 2026-08-20 (Kevin): the tooltip should show what
  XIVHotbar2 shows, and the text is vendored from XIVHotbar2.** The scope
  decision above therefore stands only for what shipped at CB8. Vendoring wins
  over DAT extraction because the offsets are unresearched and the tables are
  right there; the two costs it carries are accepted rather than avoided - a
  further upstream licence notice in `assets/LICENSE.txt`, and description text
  that goes stale on a content update until the tables are refreshed. The DAT
  route stays available if staleness ever bites.
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
  | a slot | genuinely empty space | **unbind the cursor's layer only** — never the whole stack; no-op when no layer row is selected |
  | a slot | any binder surface (stack panel, catalog, pager) | **cancel, silently** — corrected 2026-08-19 at CB8 review: the stack panel opens 8px from its slot, so "anywhere else" made an accidental unbind a routine mis-drag with no undo. The wiki's "onto empty space to clear it" was always the safer reading and is now the rule |

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
  [#19](https://github.com/khowe085/XIVHud/issues/19)). The catalog's **"Attack" entry is the `draw` built-in** (decided 2026-08-06) —
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
  (`\`-then-`;` and `;`-then-`\` both = WXHB left), layer release dropping
  back to the XHB side, the layer alone → no intent, both sides + layer →
  Expanded unchanged (the normative no-op);
  the draw gesture (layer held, no side active: switch tap → `draw` intent and
  no `cycle`; switch chorded with a slot key → `jump n`); **the switch inert
  while any side is held** — no `cycle`, no `jump`, no `draw`, while still
  blocked, and slot keys in that state firing their slot rather than jumping; switch-chord vs switch-tap (a chord followed by
  release emits no cycle); backtick always blocked, held or tapped, hold state active
  or not; shortcut keys (bare tap → its `tap` verb, tap with **a side** held → its `chorded`
  verb (the layer and switch do not count — the pad chord is trigger+Select),
  always blocked, any press exiting edit mode while edit mode is on); slot keys with no hold state active and backtick up never firing and
  never blocked; the block decision exactly per the Blocking rule — **all five dedicated
  keys blocked at press whenever the component is enabled**, slot keys only
  while a hold state is active or the switch is held, nothing else ever; **a
  latched release blocked even when a guard has since become active**
  (crossing into chat, suppression, edit mode, or an inbound-`blocked`
  release); chat_open suppressing action intents but passing `activate` (an activator
  released mid-chat emits `activate none` — the widget-visible assertion, not
  just internal state);  auto-repeat
  streams firing each action exactly once; inbound-`blocked` events producing
  no action intent and no block while still updating state and `activate`; `lose focus` clearing all held
  state; **disabled** full inertness (nothing fires, nothing blocked, ours
  included) against **suppression**, where our five keys stay blocked and only
  firing stops; a latched release swallowed even after the component is
  disabled mid-hold; an
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
- **`roulette.lua`** — KI list → owned mounts (category filter and
  music-note-prefix matching via the byte-escape literal; the whistle is
  excluded by that prefix match, with no name test of its own), chunk `0x055` refresh, mounted-buff → dismount, empty list →
  no-op, pick uses the injected RNG and stays in range.
- **`skillchain.lua`** — WS → property list for single-, double- and triple-property
  skills and an aeonic; unknown WS → no icon, not a crash; **chain resolution**:
  active resonation × bound action → resulting property (combo-table entries,
  JA-by-recast_id, closed window → none, level rules; no aeonic behaviour —
  dead upstream); window
  state machine across waiting → open → expired with an injected clock; no
  target / dead target → no indicator and no chain results.
- **`counters.lua`, ninja tools** — spell -> tool -> master tool resolution for
  each family; **master tools counted on main NIN and ignored on sub**; the
  `99+` cap at 99/100; the colour bands at 50/51 for plain and total; the
  zero state producing the crossed-out slot; a ninjutsu whose tool the player
  has none of, and a non-ninjutsu spell producing no count at all; Corsair
  cards resolving through Trump Card the same way.
- **`counters.lua`** — stratagem charges: max
  charges at each level boundary (9/10, 29/30, 49/50, 69/70, 89/90), the JP
  gift at 549/550 **for main SCH only**, available = `max(0, (max + gift) -
  ceil(recast / charge_time[max + gift]))` across a full recast sweep — gift
  in **both** places and the zero clamp, which is the fork's own bug (it can
  print -1) — plus zero and full states, and —
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
  the final argument is omitted, refusing an empty slot or an unresolvable
  icon, and resolving `icons/custom/` ahead of the shipped pack; the `open` and `cycle` bare-vs-args overloads, and every validation rejection with its hint line.
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
mount roulette mounts and dismounts; **`warp` picks the right rung, equips
and fires the ring, and re-enables the GearSwap slot on every exit — success,
the 30 s give-up, and a zone or logout mid-wait**; the stratagem and ninja
counters read correctly on main and sub; the draw toggle engages and
disengages from both a slot and `//bind`; gaining Light Arts swaps the overridden slots and
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
  press-order and release-fallback cases **including re-press** (`;`↓ `'`↓
  `;`↑ `;`↓ = `expanded_rl` — "first" means first of the *currently held*
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
  `contexts.lua` (the roster), `kebab.lua`, `defaults.lua` + specs. Still no
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
  anchor iteration. *Accepts when* a four-anchor test widget drags,
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
  WXHB (its two anchors) and Expanded Hold wired; set jump/cycle; the crossbar
  consuming the `job change`/buff events with per-job reload live (CB5's own
  acceptance depends on them); recast sweep and
  animation, MP/TP cost, unusable dimming, press feedback, and `counters.lua` — the SCH
  stratagem counter and ninja tool counts;
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
- **CB9 — cast retry.** `retry.lua` + spec (the pending record, the guard set,
  the attempt cap and deadline), a branch on the `0x29` the component already
  receives, a check on the tick that already runs, and a
  **`//hud crossbar retry [on|off]`** toggle (no argument reports, `wxhb`'s
  shape) that must be able to switch the feature off outright at any time,
  including with a cast already pending - which it drops rather than firing.
  **The wiki page is a deliverable of this milestone, not a follow-up**: the
  command row and the Extras entry land with the code. Adds no touchpoint, and
  the only new client read is the target pin on a token-targeted press. See
  **Cast retry** above for the design and the two open in-client questions;
  **it must never hold an action blocked by a recast** — that is the whole
  reason the reference's version was abandoned. *Accepts when* Kevin can cast
  several spells back to back at his own pace with none lost to "unable to
  cast", and nothing ever fires after he has moved on to something else.
- **CB10 — travel delay.** The five-second countdown on `mount`, `mr` and
  `warp`, its per-second chat, the resting cancel, and the skip for a warp rung
  whose use entails a wait. Config `delay` in seconds, zero for off. See **Travel delay** above.
  The wiki page is a deliverable of this milestone, not a follow-up. *Accepts
  when* a mis-pressed mount can be called off with `/heal` before it fires, a
  Warp Ring still goes the moment its own warmup is done, and nothing counts
  down after a zone, a death or a logout.
- **CB11 — consumables and enchanted items** (built 2026-08-20; scope settled
  with Kevin before any code). Three pieces, one milestone:
  1. **Item counts.** A slot bound `item` (or `enchanteditem`) shows how many
     the bag holds, capped at `99+`, with the red X at zero — the display the
     ninja-tool counter already had, minus the two things that are tool facts
     rather than item facts: master-tool substitution and the `>50` colour
     bands. Plain white, because there is no defined "low" for an arbitrary
     consumable and inventing one would be inventing a preference. The bag
     re-read stays gated: `counters.tracked_item(id)` **or** an id some
     painted slot is bound to, walked from the contents rather than cached,
     so an unrelated item moving still costs nothing and no cache has to be
     invalidated on every bind, set switch, context flip and job change.
  2. **The `enchanteditem` bind type.** `enchanteditem.lua` is warp's ladder
     with the ladder taken out: one named piece of gear, searched for across
     every equippable bag, resolved into warp's own three plan shapes so the
     widget's equip → wait → use scheduler runs either without knowing which
     asked. The bag walk itself moved into `enchanted.collect` and warp now
     calls it, so there is one implementation of "which copy is reachable".
     `GS_SLOT_NAMES` grew from two entries to all sixteen, since a binding
     can name any worn piece rather than only a ring or a main hand.
     **No travel countdown** (Kevin, 2026-08-20): the warmup already is the
     wait, which is the same reasoning that makes a warp skip its countdown
     for a rung it has to warm up. One wait of any kind at a time, so a
     pending warp blocks an enchanted item and the reverse.
  3. **Catalog.** An **Enchanted** group in the binder, walking the
     equippable bags rather than inventory alone, decoding only items the
     resources say can be worn — a wardrobe pass that decoded every stack
     would be hundreds of extdata reads on the click that opens the binder.
     Without the extdata library the group simply does not appear.

  Deliberate calls worth recording: an item that is readable and simply not
  enchanted **fires as a plain `/item`** (binding a Prism Powder as an
  enchanteditem is a mistake that should still fire the powder), but an
  extdata we cannot read at all **refuses with a message** rather than
  sending a command that would silently do nothing. That distinction needs
  enchanteditem to get the **raw** decode: the widget's shared `decode_ext`
  substitutes `{ type = "unavailable" }` for a nil, which is right for the
  ladder (note the rung, walk on) and wrong here (there is no next rung, and
  the substitute reads as "a plain item"). `validate` never runs a plan, so
  binding costs no bag read.

  **Every copy is considered, not just the best-ranked one.**
  `enchanted.candidates` returns each copy of an item ranked - reachable
  before locked away, the one on your hand before a spare, then bag order -
  and the plan walks that list until a copy yields something firable.
  Ranking alone is not enough: two Warp Rings with the worn one spent would
  otherwise answer "no charges" for the rest of the day while the charged
  spare sat in the bag, which is worse than the built-in `warp` ladder that
  has no worn preference at all. `enchanted.collect` (one copy per id, what
  the ladder wants) deliberately does NOT rank worn first for that same
  reason - it reads charges off its single copy and then walks to the next
  RUNG, with no way back to another copy.

  **Counting is per type and uses two tallies, because the two are not
  carried in the same places.** A consumable counts from the **inventory and
  the Temporary bag** - a potion in a wardrobe is not one the game will let
  you drink, so counting it would promise a press that cannot fire, but an
  item held temporarily is one `/item` can use - while gear counts across
  every equippable bag, the same ones `enchanteditem` searches. The
  temporary bag is found by NAME out of the resources, never by a remembered
  id, and read only when something is actually bound to an item id.

  A **repaint re-derives the bound-id set and marks the counts dirty only
  when it CHANGED**. Marking every repaint dirty was the first attempt and
  is the thing being avoided: a hold state, a view change or a set switch
  onto the same contents would each re-read up to ten bags for nothing. The
  invalidation is needed at all because without it a freshly bound slot read
  0, crossed itself out and dimmed until an unrelated inventory event
  happened along - the path the mouse binder takes every time.

  **Known limitation, recorded rather than fixed**: a bag's runtime
  `enabled` flag flipping - walking out of a Mog House - dirties nothing, so
  a gear count can sit stale until the next repaint that changes the bound
  ids, an item event, or a job change. The press stays honest ("You cannot
  access X from Wardrobe 2 at this time"), so the corner disagrees with it
  for a while rather than lying about a press that would work. Fixing it
  means either polling bag flags or finding an event for them, and neither
  is worth a client read per frame for a corner that self-corrects.

  **The deferred command's target is resolved at the PRESS** (Kevin,
  2026-08-21), which the first pass only half did. The command goes when the
  enchantment comes up, as much as a minute later, so a token carried that
  far resolves then: `<t>` lands on whatever has been tabbed to since and
  `<st>` opens a selection cursor long after the button was released.
  Neither is the press's target. So the press either resolves the token to a
  concrete id or does not happen - refused before anything is held, so no
  GearSwap slot is left disabled behind a press that will not fire. A fixed
  target needs no pin, and a binding with no target word has nothing to
  resolve.

  **Known interaction, left as it stands**: pressing an enchanted item while
  a travel countdown is running means the warp, when it fires, meets "already
  in progress" and is swallowed - and `warp all`'s IPC broadcast goes with
  it. That is the existing rule (the broadcast rides the LOCAL commit, so a
  warp that did not happen sends nobody), and it is said in chat rather than
  silent, but it is a corner nobody has pressed in a client.

  **One reading of "is it ready", not two** (Kevin, 2026-08-20, after review
  round 3). `enchanted.step` answers it and `enchanteditem`'s plan asks
  `step` rather than deciding for itself: the plan chooses between firing
  now and arming the wait that `step` then drives, so a rule only the plan
  knew armed waits that never fired and died at the 45s deadline, while the
  same press a second later worked.

  **And the rule is conditional, which round 4 caught the hard way.** `step`
  reads an elapsed warmup as ready **only when told the piece is already
  worn**. `activation_time` is written at the equip, so on an item that is
  *not* worn it is a leftover from some previous one - and an unconditional
  version of the rule made the first poll fire the `/item` one frame after
  `set_equip`, before the equip had reached the server. That was a
  regression in the shipped **warp ladder**, not just the new type, and it
  would have broadcast `warp all` on a commit that never happened. The
  fixture that hid it (an unworn ring given a *future* warmup, which only an
  equip can produce) was reverted rather than kept; the guard that now
  catches it presses with the extdata the client actually still holds, which
  is what every other equip-path test rewrites before the first poll.

  **The GearSwap hold covers every slot the piece fits** when the item is
  found already worn, because which one it is on is not knowable from the
  resources - a ring is a coin flip, and the losing side is GearSwap
  swapping the warming ring off and the wait dying at the deadline. When the
  component does the equipping itself it knows the slot and holds only that
  one. Reading the worn slot out of `get_items().equipment` would be exact,
  but its key names are not the ones GearSwap takes and nobody here has
  verified the mapping.

  Found by the CB11 review gate and fixed there: an `enchanteditem` slot drew
  **no icon at all** (`render.lua` gated the item art on `type == "item"`, so
  the record fell through to the built-in defaults, which have nothing for
  it) while still paying for the DAT extraction; an already-worn item was
  called ready on its **recast alone**, firing an `/item` seconds before the
  enchantment went live; gear in a **disabled bag** was counted as available
  though the press refuses it; ordinary armour bound here sent `/item` at a
  Rope Belt; and a **re-attach** (`//hud reset crossbar`, `//hud copy`'s
  reload) left a wait in flight holding a GearSwap slot, carrying a command
  from the configuration just replaced - the argument the travel countdown's
  own clear had always made, never applied to the wait beside it.

  *Open in client*: two things, and the first is question I.

  **What shape is `res.items[].slots`?** Nothing in this repo had read the
  field before CB11. Three shapes are accepted - a set (`{[13]=true}`), a
  list of ids, and a bitfield - and anything else answers "cannot tell which
  slot", which the ladder walks past and `enchanteditem` refuses. The
  bitfield branch is deliberately **restricted to numbers above 15**: a bare
  slot id is 0..15, and so is a bitfield naming nothing above ammo, so down
  there the two cannot be told apart - and guessing wrong is not a quiet
  failure, since reading `13` as a bitfield answers slots 0, 2 and 3 and
  equips a RING into the main hand. A dead feature is the better wrong
  answer, and the in-client read settles it.

  **Do the sixteen GearSwap slot NAMES match?** The slot ids themselves are
  already attested in-repo - `equipviewer/logic.lua` carries all sixteen as
  the client's own equipment-table keys. What is unverified is only
  GearSwap's vocabulary for four of them: `ear1`/`ear2`/`ring1`/`ring2`
  against the client's `left_ear`/`right_ear`/`left_ring`/`right_ring`.
### Queue (Kevin, 2026-08-20, in order) - BOTH BUILT 2026-08-20

1. **CB12 - the warp ladder's worn-means-ready defect.** See the follow-up
   below. The fix is built and sitting in `enchanted.step`: the ladder's
   `type = "use"` branch wants `enchanted.step(ext, now, true)` rather than
   `entry.item.status == EQUIPPED` alone. Needs its own red-green pass
   because it changes what an existing warp test describes.
2. **CB13 - Tavnazian Ring as the warp ladder's last rung.** Decisions
   already taken with Kevin (2026-08-20):
   - it is a **ring like the Warp Ring, with a 30 second EQUIP WARMUP**;
   - it goes **last**, below Warp Ring, Warp Cudgel and Instant Warp, as the
     item of last resort;
   - it is **resolved by NAME through the resources**, not by a hardcoded
     item id - nobody here knows its id, and writing one down from memory is
     exactly the unverified constant this repo keeps getting bitten by;
   - and its 30s warmup sits **exactly on** `enchanted.step`'s
     `GIVE_UP_SECONDS` bound, so any slop in the poll timing or the equip
     latency tips it into "abandon". The bound therefore has to become
     **per-rung** rather than the single module constant it is now.

- **CB12 - the ladder's worn-means-ready defect (built 2026-08-20).** The
  worn branch now asks `enchanted.step(ext, now, true)`, the same question
  `enchanteditem` asks, so a ring put on by hand no longer fires an `/item`
  the game refuses seconds early. Two calls made in the building:
  - a rung on RECAST is one to walk past - the cudgel below it may be ready
    right now - but a rung merely still WARMING UP is one to wait out
    (revised at review round 22): walking past it left the press doing
    nothing at all when no rung sat below, which is exactly what equipping a
    ring by hand and pressing warp a moment later meets. It now arms the
    same wait an `enchanteditem` binding on that ring would, which is what
    makes "both callers put the same question to `step`" true of the answer
    and not only the question. A warmup longer than the item's own bound is
    still walked past, since there is nothing worth waiting for;
  - a decode with **no `activation_time` at all** degrades to the behaviour
    that shipped rather than refusing, because losing a warp that works over
    a reading we do not have is the worse trade.

    No existing warp test needed changing, for two different reasons worth
    keeping straight: `crossbar_warp_spec`'s ring fixture carries no
    `activation_time` at all and lands on that degrade path, while
    `crossbar_spec`'s `RING_EXT_READY` does carry an elapsed one and simply
    never reaches the new call, because its ring is not worn.
- **CB13 - Tavnazian Ring as the last rung (built 2026-08-20).** A fourth
  rung below Instant Warp, and the first one **resolved by name**: a rung
  carries either an `id` (MyHome's three, attested by the port) or nothing,
  in which case `deps.find_item` answers it from the resources at plan time.
  Absent resources, the rung simply is not a rung today - and it is passed
  over **in silence** rather than noted as missing, since "an item I cannot
  name is absent" is not something a player can act on. Its equip slot is
  read off the resource's own `slots` (lowest first, as `enchanteditem`
  does) rather than written down.

  **The give-up bound is now per ITEM, not per rung** (moved there at
  review round 20: a slot bound `enchanteditem "Tavnazian Ring"` has to wait
  exactly as long as the ladder rung does, or the ring works from one and
  "randomly refuses" from the other). Its warmup is about thirty seconds and
  the test is `warm > bound`, so thirty exactly still waits - what does not
  is thirty plus anything, and equip latency, a late poll or a rounded
  timestamp each supply the plus. On the default bound those turn into
  "needs more than 30 sec". The item carries `give_up = 40`: ten seconds of
  headroom for the slop, not for the warmup.

  **The widget's wall-clock deadline is measured from the plan's bound**
  (`bound + 15`) rather than a fixed 45, or the deadline would end the very
  wait the longer bound was granted for.

  **Confirmed (Kevin, 2026-08-21): the thirty seconds is the equip warmup,
  and the ring otherwise behaves like a Warp Ring.** So the reading this was
  built on holds - it is enchanted equipment with charges, worn in a ring
  slot, and the wait is the warmup rather than a recast between uses. The
  40-second bound stands: ten seconds of headroom over a thirty-second
  warmup, for the slop that `warm > bound` would otherwise turn into "needs
  more than 30 sec".

  Still open for this rung: only the shape of `res.items[].slots` (question
  I), which is what resolves the ring's own slot ids - the rung carries no
  hardcoded `equip_slot`.

- ~~**Follow-up, found at the CB11 review gate: the warp ladder treats
  "worn" as "ready".**~~ **Done as CB12, 2026-08-20** - kept here for the
  record of how it was found. Original note:** `warp.lua`'s equip branch is gated on
  `entry.item.status ~= EQUIPPED`, so a Warp Ring already on your finger and
  off recast falls straight through to `type = "use"` with **no warmup
  test** - press `warp` right after equipping the ring by hand and it fires
  an `/item` the game refuses. It is exactly the defect `enchanteditem`
  fixes on its own side, and the fix is now built and sitting there: pass
  `enchanted.step(ext, now, true)` the way the plan does. Deliberately NOT
  done inside CB11, which had no business rewriting the ladder mid-gate.
  Note it changes what an existing warp test describes, so it wants its own
  red-green pass rather than a drive-by.
- **Backlog** (order TBD; items with an issue number are tracked on GitHub and
  are listed here only so the plan stays a complete record):
  - ~~consumables, and the rest of the enchanted-item surface~~ — **built as
    CB11, 2026-08-20**; see the milestone below;
  - hover tooltips carrying the same information XIVHotbar2 shows, its
    description tables **vendored** from that addon (Kevin, 2026-08-20 —
    superseding the "no game description text" scope decision above, and
    settling the vendor-vs-DAT question in favour of vendoring);
  - more context condition types (level, weapon, zone).
  - **Filed as issues, 2026-08-20**: `pet` catalog entries — the type binds
    from the console already, so the gap is the binder's catalog
    ([#19](https://github.com/khowe085/XIVHud/issues/19)); `ct`/`ex` entry in the binder, together
    with rename and re-icon — one item, since all three need the same keyboard
    text-capture mode, and **all three already work from the console**, so the
    gap is mouse convenience only
    ([#18](https://github.com/khowe085/XIVHud/issues/18)); "return to XHB after WXHB input"
    ([#15](https://github.com/khowe085/XIVHud/issues/15)); non-compact layout
    **merged with** theme + icon-pack resolution, which are one piece of work
    ([#16](https://github.com/khowe085/XIVHud/issues/16)); evaluating the
    partylist migration onto the multi-anchor contract, with its per-anchor
    visibility prerequisite ([#17](https://github.com/khowe085/XIVHud/issues/17)).
  - **Dropped, 2026-08-20**: "auto-switch on draw/sheathe" was stale residue —
    it predates the 2026-08-07 revision that gave the weapon state its one-way
    game trigger. Auto-*unsheathe* shipped (`bindings.on_status`); auto-sheathe
    is a rejected design, not a deferral, because a mob dying between pulls
    would flap the bar back to the sheathed rotation.

## Open questions

1. **Input map: settled and fully verified in-client (2026-08-16)** — no
   modifiers; `;`/`'` sides, `\` layer, backtick switch, `=`
   shortcut, number row slots, all config-with-defaults. Every key confirmed free and confirmed
   takeable from the game. Residue: **(a)** injected-key
   echo — one console command, before CB2; **(b)** the layout-mode interaction — layout mode uses plain CTRL for
   free-drag, which v4 no longer touches at all, but component keyboard
   dispatch (touchpoint 1) **fires nothing during layout mode** so the two can
   never contend, while **our five keys stay blocked there** (pinned
   2026-08-16) — otherwise placing the four anchors would open the chat log
   with every `;`. Core therefore keeps **delivering** keyboard events during
   layout mode: the inertness lives inside the component's input module, which
   still sees every event and answers block-but-no-fire — not in the dispatch
   going quiet, which would make blocking impossible (pinned 2026-08-16, CB2
   must land this reading). Slot keys fall through in layout mode as they do
   under suppression — only the five dedicated keys stay blocked (pinned
   2026-08-16). Verified in-client at CB4. One CB2 residue for CB3's TP2:
   the CB2 stand-in registers with the multi-anchor slot schema before the
   framework understands it, so `layout.slot` fabricates and persists a
   spurious top-level `pos = {0, 0}` in crossbar config written during CB2 —
   CB3 must tolerate that key and drop it on its first write.
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
- **BSD 3-clause, © 2026 WG Incorporated** — the radial recast sweep: the
  algorithm transcribed into `render.lua` **and** the 32 frame images, which
  are imported rather than generated (decided 2026-08-08 — an earlier
  "CB4 decides the art" hedge elsewhere was removed 2026-08-15). In-file header
  plus this file. From XIVhotbar2 Petit Trois Edition. It covers the sweep
  and nothing else — the stratagem counter and ninja tool counts come from
  Kevin's xivcrossbar fork and travel under that repository's notices, listed
  above.
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
wants the original notice retained in derived *source*, five files carry an
upstream header alongside ours: `skillchain.lua` (Ivaar's, for the transcribed
tables), `roulette.lua` (Dean James's), `warp.lua` (from20020516's),
`render.lua` (WG Incorporated's, for the sweep algorithm) and, if touchpoint 6
promotes it, `lib/icons.lua` (Rubenator's).

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
