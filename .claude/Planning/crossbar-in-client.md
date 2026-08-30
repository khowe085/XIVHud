# Crossbar — in-client verification

Everything the devcontainer cannot prove. `busted`, `luacheck` and `stylua` are
green, and none of them exercise Windower's `require`, the real `texts`/`images`
libraries, the prim layer, the keyboard/mouse hooks, the DAT reader, or FFXI
itself. This is the list that has to be walked in a live Windower/FFXI client
before the component can be called done.

Gathered from the milestone acceptance lines and the per-milestone open items in
[crossbar.md](crossbar.md); organised by what a player would do in one sitting,
not by milestone.

**The behavioural half of this list now lives in
[crossbar-testplan.md](crossbar-testplan.md)**, as tick-boxes ordered so the
sections build on each other. Every BLOCK check below has a row there, and
its section O carries the readings that settle the open questions. This
file stays as the reasoning: what each answer would mean, and what the code
does in the meantime.

Items marked **BLOCK** are blocking: if one of them fails the addon is unusable and
nothing further on the list is worth running. Everything else is a confirmation —
a failure is a defect to fix, not a stop-the-world.

---

## 1. Load and smoke test

| # | Do | Correct looks like | If it fails |
| --- | --- | --- | --- |
| 1.1 **BLOCK** | `//lua load xivhud`, then `//hud` | The command list prints. `<addon>/load.log` records every load step, `addon_path`, and each `create_dir` result | The main chunk died part way and no handler after it registered. Read `load.log`; drop an empty `safe_mode` file beside it to load the framework and commands without components or the render loop, and bisect from there |
| 1.2 **BLOCK** | Watch the load for the asset check | No `missing texture` lines. The crossbar samples ~35 of its ~1,300 icons | A texture path that does not exist fails **silently** — the prim draws nothing. A missing sample means the packaged `assets/` tree is incomplete |
| 1.3 **BLOCK** | `//lua reload xivhud` while the crossbar is up | Bar comes back, keys still blocked, no orphan prims left behind, no keybind lost | CB2's acceptance. A handler that does not survive a reload means every code change costs a client restart |
| 1.4 | `//hud list` | `crossbar` listed with a headline plus one line per anchor (`main`, `wxhb_left`, `wxhb_right`, `indicator`) | The multi-anchor path in `core.describe` is not being taken |
| 1.5 | Log in, check `data/<Character>/crossbar/` | `<MAIN>.lua` written on the first binding; `SHARED.lua` when a shared set is written. `data/<Character>/crossbar.lua` holds the component config | The directory store (touchpoint 5) is not reaching disk. Note `files.new():write()` is **not** what writes here — plain `io.open` is |
| 1.6 | **Prim budget.** Play normally with the crossbar shown, then `//hud hide crossbar`, and compare frame rate | No measurable difference | The resting inventory is 365 prims (244 images + 121 texts), built in the factory at `core.register` time - before login, not at attach - and merely hidden, so the cost is there from load whether or not the bar is shown. Edit mode adds to it: the binder builds its own prims on open and destroys them on close, so measure with the binder shut. Its window grew on 2026-08-22 (920x600 at 18pt, ~20 rows a column) and its three steps SHARE one set of row prims rather than holding one each. If the resting cost is real, the fallback is destroy-when-off, confined to the widget's build/refresh |
| 1.7 | Trigger a cutscene (status 4) and a zone change **while holding a side key** | HUD hides; on the way back nothing is stranded — no side lit, no trigger stuck down, no key still swallowed | The suppression re-enable handshake (`show()` re-reads `hold_state()`) is not firing. A stranded "down" makes the bar unusable until a reload |
| 1.8 | Log out and back in; log in as a second character | Bindings and layout follow the character; nothing renders while logged out | Character scoping is per name only — the component waits for the rest itself |

## 2. Input map

The keys were verified free and takeable in the 2026-08-16 spike. What is
unverified is the **wired component** behaving the same way.

| # | Do | Correct looks like | If it fails |
| --- | --- | --- | --- |
| 2.1 **BLOCK** | Press each of `;` `'` `\` `` ` `` `=` in normal play | Nothing reaches the game — no chat line opens, no game function fires | Blocking is `return true` on an unchorded key; if one leaks, that key cannot be one of ours and the map moves again (two designs already died here) |
| 2.2 **BLOCK** | Press `1`–`8` with nothing held | The number row reaches the game exactly as usual (macro palette, menus) | The slot keys are being latched when they should not be. This makes the game unplayable, not just the addon |
| 2.3 **BLOCK** | Open the chat box and type `;`, `'`, `\`, `` ` ``, `=`, `1`–`8` | Every character lands in the message; no slot fires, no side lights | The `chat_open` guard is not reading. `windower.ffxi.get_info()` is called inside a `pcall` for exactly this reason |
| 2.4 **BLOCK** | Reach every hold state: `;` / `'` / `\`+`;` / `\`+`'` / `;`then`'` / `'`then`;` | Six distinct states; the panel moves to match | The whole input model. Include the **re-press** case: `;`↓ `'`↓ `;`↑ `;`↓ must land on `expanded_rl` — "first" means first of the *currently held* pair |
| 2.5 | Hold `` ` `` and press a slot button | Jumps to that set (1–8). Tap `` ` `` alone cycles instead | Jump asks only that no side is held at the slot key's press edge; cycle dies if a side overlapped the hold at any point |
| 2.6 | Hold a side, then tap `` ` `` | Nothing happens — the switch is inert while a side is held | |
| 2.7 | Hold `\` and tap `` ` `` with no side held | The draw toggle fires (sword on / disengage / dismount) | |
| 2.8 | Alt-tab away mid-hold, come back | No side is lit, nothing is stuck down, the next press behaves | `focus_lost` clears held state and latches; without it the client returns with a phantom hold |
| 2.9 | Enter `//hud layout`, press the five dedicated keys, then `1`–`8` | The five stay blocked (no chat log opening while placing anchors); the number row falls through; nothing fires; CTRL still frees the drag | Pinned 2026-08-16: core keeps *delivering* keyboard events during layout mode and the component is what goes inert |
| 2.10 | `//setkey e down`, `//setkey ctrl down`, `//setkey 1 down` (release each) | The client reacts as if the key were pressed | The **key-name spellings** residue — the docs say "most key names can be easily guessed" and link no mapping. Wrong spellings silently do nothing, which is how the `open` chord entries would fail |
| 2.11 | Fire an `open equipment` slot and watch the chat/console | The equipment window opens and nothing echoes | The injected-key echo residue (open question 1a). An echo is cosmetic but noisy |

## 3. Display and layout

| # | Do | Correct looks like | If it fails |
| --- | --- | --- | --- |
| 3.1 **BLOCK** | Log in with the crossbar visible | The XHB sits on screen, correctly laid out, inactive | CB4's acceptance |
| 3.2 **BLOCK** | Hold a side key | A panel draws behind that side's eight slots; releasing clears it | |
| 3.3 | `//hud crossbar wxhb on` / `off` | On: both bars rest on screen. Off: the WXHB appears only while its gesture is held — and it still appears on the gesture either way | |
| 3.4 | Hold both side keys | Expanded Hold replaces the XHB and WXHB, centred on the XHB's anchor; releasing one drops straight to the side still held | Expanded replaces rather than adds, so a leak here doubles what is on screen |
| 3.5 | `//hud layout`, then drag and wheel-scale each of the four anchors | Each moves and scales independently; right-click toggles the whole widget, not one anchor; everything persists immediately and survives a reload | CB3's acceptance. **Watch for stutter while dragging** - the crossbar is the only widget where a drag is expensive: core's per-move apply pushes scale and position for all four anchors, then the preview flag, then `show()`. The widget lays out only the moved anchor's groups and no-ops every push that changes nothing (an unchanged pos or scale, a preview flag that has not flipped, a `show()` on a widget already visible), and `refresh()` writes visibility only where it changed. That takes one mouse move from 8530 prim calls to 433 - all of it the moved anchor's own slots being laid out - but only a live client can say whether 433 a move is smooth. Also confirm parambar, giltracker, targetbar, equipviewer and the partylist trio still drag exactly as before |
| 3.6 | Put an action with a long recast on a slot and use it | The radial sweep tracks the recast; the number reads down; the slot dims while unusable | The denominator is the largest recast *observed* for that slot, so a bar that loads mid-cooldown starts full rather than guessing |
| 3.7 | Bind an item you have never had on screen before | The icon appears within a frame or two; `<addon>/icons/<item_id>.bmp` is written | Extraction is queued one icon per frame and a failure is abandoned for the session. A wrong `game_path` looks exactly like "no icons ever appear" — `//hud crossbar` cannot report it, so check the file |
| 3.8 | Press a bound slot | The press flash draws; the action fires | |
| 3.9 | Look at the whole thing at default scale | Labels, costs and counts are legible; the panel placement is sane | Panel placement is a **draft to tune in-client** (CB8), not a settled number |

## 4. Binding — CLI and binder

| # | Do | Correct looks like | If it fails |
| --- | --- | --- | --- |
| 4.1 **BLOCK** | Bind all eight slots of one side and press each | Each fires the action it shows | CB5's acceptance |
| 4.2 **BLOCK** | Make a binding, change job, change back, `//lua reload xivhud` | The binding is exactly where it was | CB7's acceptance. The whole model is per main job and lives in the directory store |
| 4.3 | `//hud crossbar list` | Every stored layer for the job, with its source tag, the live one marked where more than one exists | |
| 4.4 | `//hud crossbar share 6 on` on a job whose set 6 already holds bindings | The shared copy takes over and the reply says this job's own set 6 is dormant; `share 6 off` brings it back unchanged | Dormancy is by design — nothing is merged and nothing is deleted |
| 4.5 | `//hud crossbar copy <JOB>` | This job's bindings are replaced wholesale, no undo | Destructive by design; confirm it does not touch the shared store |
| 4.6 | Cycle with `` ` `` after `//hud crossbar cycle <set> drawn\|sheathed\|both\|none` | Empty sets are skipped; engaging in game brings up the drawn rotation; a mob dying does **not** drop it; `draw` returns you to sheathed | Weapon state is the component's own state machine with a one-way game trigger |
| 4.7 | Fire `draw` from a slot, from `//hud crossbar draw`, and from the `\`+`` ` `` gesture | Identical behaviour: sword on with no command sent, disengage, dismount when mounted | **The disengage spelling is unverified** — `/attack off` is the expected form (~80%); `/attack` bare may also toggle. Type both by hand first. Whichever proves reliable wins |
| 4.8 **BLOCK** | `//hud crossbar edit`, then build the SCH layout entirely by mouse | Click a slot → one window opens dead centre on `pick a layer`; click a layer row → `pick an action`, and a context row previews that context; click an action → `pick a target` (or a bind outright, for a type that takes none); click a target → bound, echoed, back to `pick a layer` | CB8's acceptance: the binder is the primary authoring surface. Rewritten as one window over three steps 2026-08-22 |
| 4.9 **BLOCK** | In the binder, look for **Refresh III** and the other merit spells | They are listed and they bind | The defect that drove Kevin off the reference fork. Merit spells encode their requirement above the level cap; ours admits them on the **main** job |
| 4.10 | Hover a slot and a catalog entry | The window's right-hand **details column** gives name, type, target, MP/TP cost, recast remaining, SC property; a slot adds its owning layer and what it covers. It re-reads as the cursor moves between them | Resolves from known data only — no game description text exists to show. It was a floating tooltip until 2026-08-22 and is now part of the one window |
| 4.11 | The two surviving drag gestures: slot→slot, slot→empty screen | Whole-stack swap, and clear-the-cursor's-layer-only. A drop on the window cancels quietly. With no layer selected, slot→empty does nothing. A catalog entry dragged onto a slot does **nothing** - drag-to-bind went with the wizard | The asymmetry is deliberate: moving a button takes everything, deleting touches one plane |
| 4.11a | Drag the window by its title strip, push it at each screen edge, then reload and reopen | It moves, stays fully on screen, and opens where you left it | Stored per character in the component's own config as `binder_pos`; clamped both when dragged and when read, since a position saved at another resolution would strand it |
| 4.11b | With the binder open, tap `` ` `` and then hold it over a number | The set cycles and jumps - edit mode lets the switch through - and an open window is put away as the set changes | The window remembers the address it was opened on, so it must not survive a set change |
| 4.12 | While the binder is up, hold a side key and press slot keys | Nothing happens — no side lights, no slot fires, the bar holds still under the window. The set switch is the one exception (4.11b) | The machine keeps tracking keys; only the widget's reaction is suppressed |
| 4.13 | Enter `//hud layout` with the binder open | Edit mode closes and layout mode takes the mouse; `//hud crossbar edit` is refused while layout mode is on | The two must never contend for the mouse |
| 4.14 | Gain Light Arts, then Addendum: White | The overridden slots swap as each context activates, and swap back when it drops | CB7's acceptance, the scenario the layer stack exists for |

## 5. Skillchains

| # | Do | Correct looks like | If it fails |
| --- | --- | --- | --- |
| 5.1 | Open a real skillchain window on a mob | The indicator tracks it — waiting colour, then open colour, then gone | CB6's acceptance. Fed by parsed `0x028` packets on the existing chunk dispatch; the deprecated `action` event is deliberately not used |
| 5.2 | With a window open, look at a bound weaponskill | Its icon becomes the property it *would* form right now; a WS you cannot pay for shows it dimmed with the TP cost still up | |
| 5.3 | Same for a bound job ability and a bound pet ability (blood pact) | Same behaviour | The fork addresses these by recast id and its JA slots can never light; ours keys by ability id |
| 5.4 | Let the window close without using it | The indicator clears itself | Every bar carries a duration+grace expiry, so a finish the stream never delivers still clears |

## 6. Warp, roulette, counters and openers

| # | Do | Correct looks like | If it fails |
| --- | --- | --- | --- |
| 6.1 | `//hud crossbar warp` with a Warp Ring in inventory | The press names the item and says it is equipping first; the ring goes on (re-sent about once a second if something else swaps it off first - `gs disable` cannot stop a swap already in flight); once the extdata gives a real reading it says the wait's length, counts only the last five seconds, and the ring fires; the GearSwap slot is re-enabled | Test **all four exits**: success, the 30-second give-up, `/heal` mid-wait (now cancels the warm-up too and releases the slot - it never used to), and a zone or logout mid-wait (a logout now says `warp dropped - <item>` rather than going silent). A leaked `gs disable` silently breaks the player's gear swaps |
| 6.2 | `//hud crossbar warp` as BLM with MP, and with nothing at all | Casts Warp / Warp II; with nothing available it says what is missing rather than failing silently | |
| 6.3 | `//hud crossbar warp all` on two characters running XIVHud | Both warp; the receiver does not re-broadcast | The IPC message is namespaced so a real MyHome neither triggers nor is triggered by us |
| 6.4 | `//hud crossbar mr`, twice | Mounts a mount you actually own, then dismounts | |
| 6.5 | Main SCH and RDM/SCH | The stratagem count draws on the sixteen stratagem abilities and reads correctly, including the job-point sixth charge on main SCH only | The fork read SCH level from the main job only, so /SCH never drew |
| 6.6 | Main NIN and a job with /NIN, with and without master tools | Counts read; green above fifty of the plain tool, yellow when the master tools get you there, red otherwise; a zero count crosses the slot out. On /NIN the master tools are **not** counted | |
| 6.7 | COR with cards and Trump Cards | Same behaviour on the Quick Draw shots | See open question B below before trusting the /COR case |
| 6.8 | Bind and fire every `open` target: `map`, `equipment`, `inventory`, `case`, `sack`, `satchel`, `wardrobe`…`wardrobe8`, `quests`, `linkshell` | Each opens its screen | Two are key-event entries (`equipment` = Ctrl+E, `inventory` = Ctrl+I) and assume the client's default keyboard bindings; Kevin has only gotten *some* game UI to open this way. The slash entries (`/map`, `/quest`, `/sea all linkshell`) fail **silently** if the command word is wrong |
| 6.9 | `//hud crossbar mr`, then (separately) `warp`, resting with `/heal` before each fires | Each says `... in 5 seconds. /heal to cancel.` then `4...` down to `1...`, fires on the fifth second, and resting instead cancels it with `<action> cancelled.` and fires nothing | The resting cancel keys off the **player status number**, which is question G below. If `/heal` does not cancel, that number is wrong - nothing else in the feature depends on it |
| 6.10 | The same countdown against a zone, a death, a job change and a cutscene, and a second press mid-count | Every one of them cancels and says so; a second press replaces the first, and only the newer action goes | A countdown that survives any of these fires into a moment that has gone - the defect the whole feature exists to prevent |
| 6.11 | `//hud crossbar warp` with a ready Warp Ring, then again as BLM with MP | The ring goes straight to the equip-and-wait with **no countdown** (its own enchantment is the wait) - narrated by the poll instead: which item at the press, its length once the extdata gives a positive reading, then the last five seconds; the spell counts down first, and names only the trip (`Warp in 5 seconds...` - the spell rung carries no name of its own, so it never says `Warp II` even when that is the one cast) | The skip is decided from the ladder's rung, so a ring that suddenly counts down means the rung is being misread. A GearSwap set landing on the ring's slot in the same breath as the press (`gs equip sets.engaged; hud crossbar warp`) used to leave the ring un-equipped forever while the wait read a bagged ring's stale extdata; the poll now checks the item is actually EQUIPPED before reading anything off it and re-sends the equip about once a second until the give-up deadline |

---

## Open questions — answers, not checks

These are not pass/fail runs; they are facts the code is currently guessing at,
and the answer changes what ships. C and D gate the CB9 cast-retry feature and
are worth collecting while you are casting anyway.

**A. Does FFXI accept a bare player name as a target, and does `<Name>` work?**
The CLI refuses a trailing unrecognised word and names the two readings that
work - a target token, or `alias="<word>"` (quoting the whole name stopped
being advice there on 2026-08-30: it binds a name the refusal has just
established is not an action); the wiki says a player's name is not a target. If
`<Name>` does work in a macro line, the parser can stop refusing it, the hint
can teach it, and the wiki gains a row. Test by hand first: `/ma "Cure" <Kevin>`
typed straight into the client, then the same as a bound slot.

**B. Can /COR burn master cards?** `counters.tool_display` counts Trump Cards
only on **main** COR, under the unified main-job rule that master tools follow
for NIN. The reference fork's COR branch predates its own master-tool gate, so
it is no evidence either way. If a /COR *can* spend a Trump Card, the rule needs
a per-family exception rather than the one main-job test.

**C. What does a too-soon action actually send?** (gates CB9.) **Three
refusals to collect, not one**, because the retry covers all three kinds and
keys on the message per kind. Take each back to back, with a packet viewer or
a scratch handler, and note the packet and the message id: a **spell** cast
too soon (believed `0x029` message **17 or 18**), a **job ability** used too
soon (believed **71**), and a **weaponskill** used too soon (believed **72**).
The ability and weaponskill ids are the weaker guess of the three - the spell
pair at least has the reference addon's citation behind it. Note also whether
the packet identifies you as the actor in
a field we can match. Everything CB9 triggers on rests on this, and the
reference addon's own handler for it has never once executed, so the ids come
from a resource table rather than from anyone's observation. If the ids differ,
CB9 uses whatever you see; if the refusal turns out to be client-side with no
packet at all, CB9 cannot be built as designed and falls back to predicting the
window — which is the design Kevin rejected, so say so rather than quietly
switching.

While you have the packet open, also note **whether it carries the spell** (Param 1
is the candidate). As shipped, a refusal is attributed to our last send by actor
and timing alone, so a refusal caused by a game macro or by GearSwap inside the
window would re-send *our* spell instead. Reading the spell out of the packet
closes that, and nothing is decoded on a guess until someone has seen the bytes.

**D. How long is the enforced gap, and how long should a retry wait?** (gates
CB9's default.) Cast back to back for a few minutes and note roughly how long
after a refusal a re-send succeeds. Kevin reports "usually 1-2 seconds, but".
A backoff shorter than the real gap just collects a second refusal and burns an
attempt; longer than it wastes the smoothing the feature exists for. This
number ships as a tuned default, not a guess.

**E. Does a command take a bare numeric target id, and does `<pN>` resolve?**
(gates CB9's pinning.) Two halves of the same question, both cheap while you
are casting anyway.

1. Type `/ma "Cure" 16941234` by hand, substituting a real mob id read from a
   packet viewer or `//hud` diagnostics, and see whether it lands. The cast
   retry re-sends exactly this shape - the token the slot was bound with,
   replaced by the id it pointed at when you pressed - which is what
   Selindrile's widely-used files do (`delayed_target = spell.target.id`).
   That is good evidence and it is not observation. If a bare id is *not*
   accepted, the pin cannot be sent as an id and CB9 needs another form
   (`<t>` re-resolved is the thing Kevin rejected, so say so rather than
   quietly reverting to it).
2. `windower.ffxi.get_mob_by_target("p3")` - does it answer the third party
   member? **Moot for correctness as of 2026-08-19**: party and alliance
   targets are no longer retried at all, so nothing can land on the wrong
   person. Kept on the list because the answer would let them back in - a
   `<p3>` cure pinned by id is strictly better than not retrying it, and
   back-to-back party curing is the case the feature exists for.

**F. What does a targetless spell command actually do?** (a CB8 question the
cast retry surfaced, not a CB9 one.) Type `/ma "Cure IV"` with a mob selected,
then with nothing selected, and note each outcome: does it use the current
target, open a prompt, or fail outright?

**Half answered, 2026-08-22.** This item existed because the binder wrote its
records **without a target word** (`catalog.lua:162`, `{ type = "ma", action =
<name> }`), so a mouse-bound slot handed the game a bare command - and that is
why the cast retry never watched one: with no target on the press there is
nothing to pin the re-send to.

The binder's third step now asks for a target, so a mouse binding can carry one
and every surface produces the same record. **The question still stands for the
default**: `(no target)` is the first row and is what a player who clicks
straight past it gets, which is the old behaviour exactly. Knowing what a bare
`/ma "Cure IV"` does decides whether that default is right, and whether a
targetless record is worth the retry watching at all.

**G. What number is the Resting player status?** (gates CB10's cancel.) Sit
down with `/heal` and read `windower.ffxi.get_player().status`, then stand and
read it again. The travel countdown cancels on resting, and it resolves that
number out of `res.statuses` by english name rather than trusting one from
memory - but nobody here has seen either the resource row or the live status,
so two things are worth a look at once:

1. Does `res.statuses` actually carry an entry whose `en` is `Resting`? If it
   does, the resolution is doing the work and the constant never runs.
2. Is that entry's id the number the client reports while resting? If the two
   disagree, the resource table is not the right source and the trigger needs
   another one.

`travel.lua`'s `RESTING_STATUS = 33` is the fallback, and it is **unconfirmed**
- written from the number GearSwap users cite, not from an observation.
Note that it is the live value in **two** cases, not one: resources that did
not load at all, and a `res.statuses` that carries no row named exactly
`Resting` (if the client's own word for it is something else - `Healing` is the
obvious candidate - the name match finds nothing and the constant stands). So
answer (1) by looking rather than assuming: read the row's spelling and its id
off the table itself. Correcting either the name or the number is an edit to
those few lines. Item 6.9 is the behavioural half of this: if `/heal` does not
cancel a countdown, this is why.

**H. Does the trainer's whistle key item really lack the music-note prefix?**
(gates the mount roulette exclusion.) Look at the key item list in game, or
read `res.key_items` for the whistle's entry, and check whether its name
starts with the note character the mount key items carry.

The whole exclusion now rests on this. Upstream excluded the whistle by name;
we removed that test on 2026-08-19 because the prefix match already rejects
it - but "already rejects it" is an assumption about the real resource that
only our fixture has ever confirmed. If the whistle DOES carry the prefix, it
prefix-matches a mount and becomes a rideable entry in the roulette, and the
name test goes back in with a comment saying why it is not redundant.

**I. Does `res.items[].slots` exist, and what shape is it?** (gates the whole
`enchanteditem` bind type.) Read one enchanted ring's entry out of
`windower.res.items` in a live client - a Vocation Ring, a Warp Ring, whatever
is to hand - and note whether it carries a `slots` field and whether that field
is a set (slot id -> true) or a list of ids.

Everything about the new bind type hangs off this field, twice over: it is how
the equip slot is chosen, and how the binder decides what belongs in its
Enchanted group. No other component in this repo has ever read it, so it is an
assumption rather than a fact. Three shapes are accepted - a set, a list of ids
and a bitfield - and a shape outside those degrades to "cannot tell which
slot X goes in", which both callers walk past. The bitfield reading is
restricted to numbers ABOVE 15, because a bare slot id is 0..15 and so is a
bitfield naming nothing above ammo: down there the two are the same number
and the code refuses rather than guess. What that costs, if `slots` really
is a bitfield, is any piece confined to main/sub/range/ammo - a weapon
bound as an `enchanteditem` would answer "cannot tell which slot". What it
avoids is equipping a ring into the main hand.

The one thing NO shape handling covers is a wrong field NAME: every bind
refuses and the binder's Enchanted group never appears at all.

**J. Do the sixteen GearSwap slot names match, and does the binder open without
a hitch?** Two cheap observations while the binder is up:

1. `GS_SLOT_NAMES` maps Windower's slot ids to the words `gs disable` takes.
   The IDS are already attested in this repo - `equipviewer/logic.lua`
   carries all sixteen as the client's own equipment-table keys - so what is
   unverified is only GearSwap's vocabulary for four of them:
   `ear1`/`ear2`/`ring1`/`ring2` where the client says
   `left_ear`/`right_ear`/`left_ring`/`right_ring`. A wrong word is silent:
   GearSwap goes on swapping the piece off mid-warmup and the wait dies at
   its deadline with "took too long".
2. Opening `//hud crossbar edit` decodes the extdata of every wearable item in
   every equippable bag, in one frame. A full set of wardrobes is several
   hundred decodes. Watch for a stutter on the frame the binder opens; if it
   is visible, the pass needs spreading over frames the way icon extraction
   already is.

**K. Does `/item` take a bare numeric target id?** (gates the enchanted
item's target pin.) The deferred `/item` is sent when the enchantment goes
live, so a `<t>` written into the binding is pinned at the press and re-sent
as the mob id - the same substitution the cast retry makes. Question E asks
this of `/ma`, where Selindrile's widely-used files are the evidence.
NOTHING vouches for the `/item` form. Only reachable when a binding names
`t` or `bt`, which is rare for enchanted gear (most of it is self-targeting),
so a failure here is narrow: the deferred use is refused and nothing else
misbehaves.

**L. Is `res.items[].category` a safer gate for the binder's Enchanted group
than `slots`?** The group currently appears only for items whose `slots`
field reads as a set, a list or a bitfield. `category` is a field this repo
already relies on (the Items group tests `category == "Usable"`), so
`"Armor"` / `"Weapon"` would be a gate with existing evidence behind it,
leaving `slots` used only where an actual slot id is needed. Worth reading
one piece of gear's resource entry and comparing the two fields while
answering question I.

**M. What is the Temporary bag actually called in `res.bags`?** A slot bound
to a temporary item counts out of that bag, found by a name match rather
than by a bag id nobody here has confirmed. (Note the item is NOT Instant
Warp, which question O settles as an ordinary inventory item.) The match is a `contains "temporary"`
so a spelling like `Temporary Items` still lands, but the string itself has
never been read. A miss is NOT harmless: the slot reads 0, crosses
itself out and dims, over a press that works. That is worse than what these
slots had before counts existed, which was a blank corner - `render.cost`
answers nothing for an item meta, so an `item` binding drew no number and no
X at all. Read `res.bags` and note the exact `en`.

**N. What does extdata's `usable` flag actually mean?** `enchanted.step`
short-circuits on it before any other test, so it outranks the `worn`
argument that exists precisely because the client's extdata lags a
`set_equip`. That reasoning was applied to `activation_time` and not to
`usable`. If the flag means "worn and warm" the current code is right; if it
means "charged and off recast" then on the equip path it can be true one
frame after `set_equip`, and the `/item` goes out before the ring is on.
Pre-existing on the warp path and apparently fine in a live client, which is
the only evidence either way - so this is a thing to watch while testing
question I rather than a defect claim.

**O. ANSWERED (Kevin, 2026-08-21): Instant Warp is an ordinary inventory
item, not a temporary one.** The suspected defect is therefore not one - the
warp ladder walks equippable bags, which reaches the inventory, so it has
always been able to see the scroll.

The temporary-bag tally stays: an item held there IS one `/item` can use,
and a slot can be bound to one from the CLI. What it loses is only its
motivating example. Note the fixture no longer uses Instant Warp as its
stand-in for a temporary item, since that would have written the wrong
classification into the tests.

---

## Not on this list, and why

- **Everything with a spec.** Over two thousand passing tests (2,059 as this was written, and the number moves with every commit) cover the pure modules: the
  input state machine, the layer stack, the command parser, the binder's state
  machine, the skillchain resolution, the warp ladder, the counters. A failure
  in-client that a spec already covers means the *spec's assumption* about the
  client is wrong — fix the assumption, not just the code.
- **The keys themselves.** Which keys are free and takeable was settled in the
  2026-08-16 spike; section 2 re-checks that the wired component behaves the way
  the spike did, not that the choice was right.
