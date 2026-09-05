# Crossbar contexts: a weapon-type layer, Unbridled Learning, and a job gate

Status: BUILT AND CLEARED 2026-09-04 in worktree `.claude/worktrees/crossbar-contexts`, branch
`work/claude/crossbar-contexts`, branched from dev at 5773707. CX1-CX9 done; 2740 specs
green, luacheck and stylua clean. SEVEN blind review rounds - R1-R6 ISSUES, every
blocking finding real, and R7 **CLEAN**. See the round log at the end. Ready for a PR. Not verified in a live client.
Scope: `src/components/crossbar/`, the crossbar registration block in `src/XIVHud.lua`,
the crossbar specs, CLAUDE.md and `.claude/Planning/crossbar-testplan.md`.
**No framework change** - `src/lib/` is not touched.

## Goal

Three changes to the crossbar's binding stack, from Kevin (2026-09-04):

1. A **weapon-type layer**, working the way the subjob layer works: overrides that apply
   while a given class of weapon is in the main hand.
2. A context for **Unbridled Learning**.
3. **Job-specific contexts only appear on their job** - and the SCH arts family counts a
   SCH *subjob* too.

## Decisions taken before writing anything (2026-09-04, from Kevin)

1. **Weapon type outranks the subjob** where both hold an entry at one address. The two
   are "the same tier" in intent, but `resolve` has to pick one, and the weapon is the
   more situational of the two. Stack becomes:

   ```
   context layers   buff-conditioned, roster order - later wins   (sparse)
   weapon layer     overrides for the equipped main-hand class    (sparse)
   subjob layer     overrides for the current MAIN/SUB pair       (sparse)
   job base         the MAIN job's sets - or the shared store
   ```

2. **The layer is keyed by the main hand's weapon skill** - `res.items[id].skill` ->
   `res.skills[skill].en`, so "Sword", "Great Katana", "Staff". The ranged slot is not
   consulted at all.
3. **Unarmed is Hand-to-Hand.** An empty main hand keys the same layer a pair of
   Republic Kicks would, because unarmed *is* H2H in game terms.
4. **The address word is `wpn:`** - `bind wpn:1L1 ws "Savage Blade"`. Deliberately not
   `weapon:`, which is already the word for the drawn/sheathed state and the sword
   anchor. Like `sub:`, it carries no name: it addresses whatever is equipped *now*.
5. **Unbridled Learning and Unbridled Wisdom are ONE context.** `any_of = { 485, 505 }`,
   the way `light-arts` already counts its addendum. Ids read off this repo's own ported
   data (`src/components/partylist/buff_order.lua:482` and `:182`), not from memory.
6. **The job gate is hidden AND inert.** Off-job a context is absent from
   `//hud crossbar context list` and from the binder's layer step, and never activates in
   `resolve` even if the buff id somehow appears. Stored overrides stay on disk untouched.

## The weapon layer

### Storage

`job_data.weapons[<skill name>]` - a sets tree per weapon class, beside `job_data.sub`
and `job_data.contexts` in the same per-main-job file. Per main job, deliberately: a
Sword bar on PLD is not a Sword bar on WAR. `sanitize_tree_map` already handles the
shape; `set_job`, `copy_from` and `swap` each grow one line for it.

Keys are the skill's english name verbatim, spaces included ("Great Katana").
`lib/serialize` quotes a non-identifier key already (`serialize.lua:112-115`), so the
stored file reads `weapons = { ["Great Katana"] = { ... } }`.

### Resolution (new pure module `weapon.lua`)

`new(deps) -> resolve()` answering the skill name, over `deps.get_equipment`,
`deps.get_items(bag, index)` and `deps.resources`:

| the client says | answer |
| --- | --- |
| equipment table is nil (client not ready) | `nil`, and the caller LEAVES the current value alone |
| `equipment.main` is 0/nil (empty hand) | `"Hand-to-Hand"` |
| item read or `res.items[id].skill` unresolvable | `nil`, and the caller CLEARS the layer |

The two nils are told apart by a second return value, because they are different facts:
the first is "ask again next frame", the second is "there is no weapon layer". A wrong
layer is worse than none, so an unreadable *item* clears rather than sticks - but an
unread *equipment table* is the ordinary state for the first frames of a login and must
not churn the layer.

### When it is read

Never per frame. A dirty flag, coalesced onto the tick the way `counts_dirty` is:

- `chunk 0x050` (Equip) - the packet equipviewer already keys off (`logic.lua:85`).
- `chunk 0x01D` (Finish Inventory) - the login/zone-in bag dump, without which the first
  read of the session finds an empty bag.
- `try_scope` - a job change swaps gear, and the layer belongs to the new job's file.

On the tick: resolve, compare with what the model holds, and only on a change call
`bindings.set_weapon_type(name)` and `repaint()`.

### Entry point

The crossbar's ctx grows `get_equipment` (the entry point already has the accessor at
`XIVHud.lua:614`, built for equipviewer). `get_items` is already argument-agnostic there,
so `ctx.get_items(bag, index)` needs no change. `tests/entry_point_spec.lua` grows a row.

### Surfaces

- `parse_address`: `^wpn:(%d+)$` -> `{ layer = "wpn" }`. Refuses with
  "no weapon equipped yet" when nothing is resolved, mirroring `sub`'s
  "no subjob to target".
- `layers_at`: a `wpn:<name>` row per stored weapon class, sorted, `worn` on the equipped
  one - exactly the shape the subjob rows have. `//hud crossbar list` prints
  `layer.source` generically (`commands.lua:933`), so it needs no edit.
- `binder.lua`: one more row in `stack_rows` between base and sub... **above** sub, since
  the list is in stack order and weapon outranks it; `address_for` grows the `wpn:` case;
  `STACK_ROWS` grows by one. No preview - like the subjob row, the weapon layer is
  whatever is actually equipped, so there is nothing to simulate.
- `binder.mark`: MARKS is `{ sub = "+", ctx = "*" }`; the weapon layer needs a third
  glyph. **Proposed `^`, open for Kevin** - it has to survive the game's font at 7
  characters plus the mark.
- `commands.lua`: `ADDRESS_FORM` and the help line grow `wpn:`.

## The job gate

`contexts.lua` entries grow two optional fields:

```lua
jobs = { "SCH" },              -- eligible when this is the MAIN or the SUB job
jobs = { "BLU" }, main_only = true,   -- main job only
```

- The four SCH arts contexts: `jobs = { "SCH" }`. Light Arts is a level 10 ability and
  Addendum: White level 20, so a level 49 subjob reaches all four.
- The unbridled context: `jobs = { "BLU" }, main_only = true`. Unbridled Learning is
  learned at BLU 96 and can never come from a subjob.
- An entry with no `jobs` is eligible everywhere (nothing ships that way yet, but the
  absent field must not mean "eligible nowhere" - Lua's nil tolerance again).

`bindings` owns the predicate, since it is the one module that knows the scoped job:

- `update_buffs` skips an ineligible context outright, so it can never enter `active`.
- `active_contexts()` and a new `available_contexts()` answer eligible entries only;
  `commands.context` and `binder.stack_rows` read the latter.
- A **new** binding into an ineligible `ctx:` address is **refused**, with the job named
  in the hint: a layer that can never fire on this job is a binding with no possible
  effect. Everything about an entry that already exists is ungated - review round 3
  caught that gating `unbind`/`entry_at` made an entry put out of reach by a subjob
  change undeletable from inside the game (overrides live in the main job's file), and
  round 4 that gating a `bind` over an occupied address made the same entry
  unrenameable, since `alias` and `icon` are a read of an entry followed by a write of
  it back.
- `layers_at` is deliberately **left unfiltered**, and consistently with the above: it is
  the disk-inspection read, and a context layer that arrived by `//hud crossbar copy
  <JOB>` (or that a subjob change put out of reach) must stay visible in
  `//hud crossbar list` rather than vanishing unexplained. It already marks `live` off
  the active set, which the gate makes false.

## The new context entry

```lua
{
  name = "unbridled",
  label = "Unbridled Learning",
  any_of = { 485, 505 },   -- Unbridled Learning; Unbridled Wisdom
  icon = "jobs/blu",
  jobs = { "BLU" },
  main_only = true,
},
```

Roster position: **last**, so it wins over the arts family where a slot somehow holds
both - which no single job can produce, the two families being BLU-main and SCH.
`icon = "jobs/blu"`: the shipped ability sheet is keyed by RECAST id
(`render.lua:585`), and Unbridled Learning's recast id is not something this container
can look up, so the job icon is used rather than a guessed number. It joins the entry
point's preload list beside the two book icons (`XIVHud.lua:1002`).

## Build order (strict TDD, red first each step)

| # | Step | Specs |
| --- | --- | --- |
| CX1 | `weapon.lua`, the pure resolver | `crossbar_weapon_spec.lua` (new) |
| CX2 | `contexts.lua`: the unbridled entry + `jobs`/`main_only` on all five | `crossbar_contexts_spec.lua` |
| CX3 | `bindings.lua`: the weapon layer - storage, `wpn:` address, resolve order, `layers_at`, `swap`, `copy_from`, `set_job` | `crossbar_bindings_spec.lua` |
| CX4 | `bindings.lua`: the job gate - eligibility, `update_buffs`, `active_contexts`, `available_contexts`, the write refusal | `crossbar_bindings_spec.lua` |
| CX5 | `binder.lua`: the weapon row, its address, its mark, the gated context rows | `crossbar_binder_spec.lua` |
| CX6 | `commands.lua`: help/ADDRESS_FORM, `context list` gating | `crossbar_commands_spec.lua` |
| CX7 | `crossbar.lua`: the dirty flags, the tick read, `set_weapon_type` | `crossbar_spec.lua` |
| CX8 | `XIVHud.lua`: `get_equipment` on the crossbar ctx, the icon preload | `entry_point_spec.lua` |
| CX9 | CLAUDE.md + `crossbar-testplan.md` rows | - |

Then: full `busted` + `luacheck .` + `stylua --check .`, then the blind review gate
(`code-reviewer`, fresh instance per round, up to 3).

## Not verified in a live client

Everything here. Specifically unverified and needing a real client:

- That `res.items[id].skill` indexes `res.skills` for every equippable main-hand item
  (a non-weapon in the main slot, if the game permits one, has no skill).
- That `0x050` is delivered for every equipment change the bar should follow, and that
  `0x01D` arrives before the first weapon read of a session is meaningful.
- The two buff ids, which come from XivParty's ported table rather than from the client.
- Whether the mark glyph reads at slot size.

## Review rounds (2026-09-04)

**R1 ISSUES** - four blocking, all mutation-proven and all on the test side, on exactly
the integration rules the change is about: the packet-driven re-read was entirely
unpinned (both tests sent their packet before the widget had ever ticked, so the attach
flag did the work); `refresh_weapon`'s "unreadable client leaves the layer alone" rule
was unpinned, which is the sole reason `weapon.lua` returns two values; nothing asserted
the bar REPAINTS on a class change (every test asserted through a key press, which
resolves live); and the nil-`main_bag` test was hollow, the fake absorbing the nil the
guard exists to stop reaching the client. Optional findings taken: a `skills[0]` fixture
(the skill-0 guard was mutation-survivable without one), a note that an equipment table
naming no `main` is an empty hand rather than an unread client, and a stale MARKS
comment left standing above its replacement. The attach re-arm turned out to be
genuinely redundant - every attach clears the scope, so the next tick re-arms through
try_scope - and was removed rather than tested.

**R2 ISSUES** - two blocking. (1) A pre-existing regression test had been silently
disarmed: the announced sub id in "keeps a previewed context through a job change" was
changed to agree with the default fixture, but that test sets its own player, so the
rescope gate short-circuited and no job change was processed at all - the reviewer
proved it by deleting the `apply_buffs()` line the test exists to guard and watching it
pass. Reverted, and the test split in two (one job change that still reaches the
context, one that does not). (2) The real defect behind it: the job gate stranded the
binder's cursor, preview and header - a subjob change could take the previewed context
out of reach while the bar went on showing that layer's world under a header naming it,
and only the write said no. `binder.refresh` now revalidates the cursor against the
model (contexts, the weapon row, the subjob row) and walks back to the layer step.
Optional taken: an empty `jobs = {}` now reads the same as an absent one.

**R3 ISSUES** - two blocking, both taken. (1) The gate was refusing `unbind` and
`entry_at` as well as `bind`, which made an entry that a subjob change put out of reach
visible in `//hud crossbar list` and impossible to delete from inside the game. (2) The
`weapon_layer == nil` path - the one degraded-operation claim this change adds to
CLAUDE.md - had no test, and a regression there is an index error in the per-frame tick,
which guard disables after five failures. Both fixed and mutation-verified.

**R4 ISSUES** - one blocking, two optional taken. The blocking one is the same defect
R2 found, one step further in: `cursor_offered` asked whether the row still EXISTED,
never whether it still named the same thing, so swapping weapons with the binder open
left the header and the bind confirmation naming the class you were holding when you
clicked while the write followed the hand ("bound Berserk -> wpn:Great Axe" with Berserk
in the Sword layer, reproduced by the reviewer). The cursor is now validated AND renamed
off the live stack rows, so the panel and the cursor cannot hold different opinions of
what a row is called. Taken with it: the creation-only gate above, and `weapon.lua`
reading an equipment table with NO slot in it as an unread client rather than as an
empty hand - the latch it would otherwise put on Hand-to-Hand at login clears the dirty
flag with it, so nothing would ask again until the player next changed gear.

**R5 ISSUES** - one blocking, and it is the item R3 raised as optional and this plan had
left for Kevin: `set_job` lands the bar on the first non-empty set BEFORE the class in
hand is known (the widget re-reads the client on the next interval), so a set whose only
content is a weapon override is invisible to that landing - and "set 2 is my Sword bar,
set 3 is my Great Axe bar", exactly the arrangement this layer invites, lands somewhere
else on every login and every job change. Reproduced by the reviewer. The first class to
arrive after a job load now re-lands, ONCE: a later swap does not, because a weapon
change is not a weapon-state transition and the set the player is on is theirs. Optional
taken: two stale docstrings in `bindings.lua` (resolve's source list, layers_at's stack
order) and the entry point's claim that the unbridled icon is "worn" by anything.

**R6 ISSUES** - one blocking, four optional taken. Blocking: every `0x050` armed the
whole-inventory read, whatever slot moved - GearSwap fires one per slot it swaps on every
cast, so a character with no weapon layer at all paid a full `get_items()` per client
interval for the whole of combat. The packet is now DECODED (via the same `parse_packet`
equipviewer reads it with, added to the crossbar's ctx) and only a main-hand slot arms
the read; an undecodable packet still arms it, since a failed decode must not freeze the
layer. Taken with it: an explicit `set`/`cycle` now stands the blind re-land down (the
bags can take seconds to fill at login, and a set the player picked in that window is
theirs); the re-land deselects an open binder, being a fifth producer of an active-set
change; `no weapon equipped to target` became `no weapon class read from the client yet`
(unarmed resolves to Hand-to-Hand, so the old wording could only ever appear to someone
holding a weapon); and the bare `//hud crossbar` status line now names the class in hand,
which nothing else reported - `list` prints a `wpn` row only where one is already bound.

**R7 CLEAN** - three optional findings, two taken without touching behaviour: a comment
in `weapon.lua` claimed parity with equipviewer over an index with no bag beside it,
where the two deliberately differ (equipviewer reads it as an empty slot, this reads it
as "could not tell", which must not key a layer), and `context list` had no unscoped
case though every other CLI path does. The third is the hidden-bar item below. The
reviewer also confirmed by reading that `ctx.parse_packet` cannot be nil where it is
called: the entry point gates the whole `incoming chunk` registration on the library
load, so no `0x050` reaches the widget in an install without `packets`.

Left for Kevin (all raised by reviewers, none blocking):

- `bindings.weapon_state()` (drawn/sheathed) sits three lines from `weapon_type()` (the
  equipped class), and there is an anchor called `weapon` as well. `wpn:` was chosen for
  the address to dodge exactly that collision; the accessors walked back into it. A
  rename to `equipped_class()` is a one-liner if it bothers you.
- `land_on_first_set` runs with the weapon class still nil (set_job clears it and the
  client is not re-read until the next interval), so a set whose ONLY content is a
  weapon-layer override reads as empty at job-load time and is skipped by the landing.
  Same shape as the pre-existing context-layer case.
- `refresh_weapon` sits behind the tick's visibility gate, so while the bar is hidden
  (`//hud hide crossbar`) the class never resolves at all: a `//hud crossbar bind
  wpn:...` then answers "no weapon class read from the client yet" and the status line
  omits the class, with a weapon plainly in hand. Self-corrects the moment it is shown,
  and the binder is already refused while hidden, so only CLI authoring is affected.
- A client that keeps answering an empty equipment table is asked once per interval for
  as long as it does - deliberately, since that is how the layer lands at all without a
  second packet, and the visibility gate bounds it. There is no give-up cap.
- The equip re-read is still armed whether or not the job has any weapon layer bound,
  unlike `counts_dirty`, which is gated on whether a painted slot draws a bag-fed number.
  Raised three times (R3, R4, R6) and only half taken: R6's main-hand gate cuts the
  GearSwap case, but a player with no weapon layer still pays one read per main-hand
  change. The obvious further gate (`next(weapons) ~= nil`) makes the FIRST weapon bind
  impossible, since `wpn:` refuses an address with no class resolved.
- A weapon swap between two classes can leave the bar on a set that now resolves to
  nothing (Great Axe lands set 1; swapping to a Sword whose layer is set 2 leaves you on
  the empty set 1). Deliberate - a swap is not a weapon-state transition - but it is the
  failure mode the "set 2 is my Sword bar" arrangement invites, and pinned as a test.
