# One read of the client per frame - the player service

Status: PS0-PS7 built, 2026-08-30. 2564 specs green, luacheck and stylua clean. **Thirteen blind review
rounds** (Kevin lifted the three-round cap to ten more); rounds 5, 6, 8, 9, 11, 12 and 13 returned CLEAN,
and the last five found nothing blocking. Every blocking finding across all thirteen was real - six of
them defects this change introduced, the rest coverage gaps where a test claimed something it could not
fail on. Not verified in a live client - that is the whole of what is left.

**Scope note:** `src/lib/core.lua` was listed out of scope and is now in it. Round 10 found a regression
that could only be fixed there - see below. Worktree `.claude/worktrees/player-service`, branch
`work/claude/player-service`, branched from `work/claude/parambar-vitals-drift` at
70548ff (the parambar vitals fix, itself off dev at a43d71f). Stacked deliberately:
this rewrites parambar's vitals path, so landing it on top of the bugfix avoids a
conflict in the same two files.

Scope: a new `src/lib/player.lua` and its spec, `src/XIVHud.lua`, and the vitals or
poll path in `parambar`, `partylist`, `targetbar` and `crossbar`. `src/lib/core.lua`
is deliberately **not** in scope - see Decisions.

## The problem

Two of them, and only the second one matters much.

**Duplicate reads.** Per 200ms window the client is currently asked:

| Read | Callers | Calls |
| --- | --- | --- |
| `get_player()` | 3 partylist variants, targetbar, parambar | 5 |
| `get_party()` | 3 partylist variants, targetbar | 4 |
| `get_info()` | 3 partylist variants | 3 |

and per *frame*, `get_mob_by_target` runs about 13 times - partylist does four
lookups per list (`partylist.lua:557`) across three registered lists, plus
targetbar's `"t"`, plus crossbar's `("t", "bt")` on a press. Only **six** distinct
call signatures exist across the whole addon: `("t")`, `("t", "bt")`, `("me")`,
`("st")`, `("stpt")`, `("stal")`.

**Divergent reconciliation, which is the real defect.** Three components answer
"what is the player's HP right now" three different ways:

- `parambar` - polled the client, or rather did not, until 70548ff. It read the
  `hp change` stream alone after a ten-second window closed, and a wrong value in
  that stream stuck for the session. That was the bug.
- `partylist` - polls `get_party()`, overlays the change events on top, and drops
  the overlay on every poll (`logic.lua:336`). Correct, and the model everything
  else should follow.
- `targetbar` - polls only, and ignores the change events entirely, so the player's
  own row in a claim check is up to 200ms behind what parambar is drawing.

One of those three was wrong for months, and nothing structural would have caught
it. Consolidating the policy is the point of this change; the read reduction is a
side effect worth having.

## Decisions taken before writing anything (2026-08-30, from the user)

1. **Cache plus reconciliation in one pass**, not the cache alone. `ctx.get_player()`
   returns vitals that already have the change events applied, and the components'
   own reconciliation comes out.
2. **`get_mob_by_target` is cached too**, memoized within a frame and cleared at the
   top of every `prerender`. No caller can observe a difference: the value cannot go
   stale inside one frame, because nothing advances the client between two reads in
   the same frame.
3. **No subscription layer.** Components keep their existing `update()` tick and ask
   the service; they do not register callbacks. A missed `subscribe` would be a
   silently dead component, and Windower fails silently by design - which is the
   failure mode this repo has already shipped once.

## Design

### `src/lib/player.lua`

Pure, factory style, `new(deps) -> service`, in the `lib/` convention. `deps` is
`{ get_player, get_party, get_info, get_mob_by_target, now }` - every one of them a
plain function, so a spec passes stubs.

```
service.begin_frame()             -- clears the per-frame memo; called once per prerender
service.get_player()              -- cached, TTL 200ms, vitals reconciled
service.get_party()               -- cached, TTL 200ms
service.get_info()                -- cached, TTL 200ms
service.get_mob_by_target(...)    -- memoized for the frame, keyed by its arguments
service.generation()              -- bumps on every real read of player/party/info
service.set_vital(kind, value)    -- from an `hp change` / `hpp change` / ... event
service.invalidate()              -- drop the TTL now: status change, zone, login
```

**The reconciliation policy, stated once.** A real read of the client replaces the
vitals wholesale and clears the event overlay - the client is never staler than an
event, because the events are read out of the same client state. Between reads,
`set_vital` layers onto a copy, so an event still lands the frame it arrives and a
bar is never a poll behind. This is exactly what 70548ff settled for parambar and
what partylist has always done; it moves into one file.

The merged table is **rebuilt only when the overlay changes or a fresh read
happens**, not per call - five consumers a window must not each pay for a copy. The
client's own returned table is never mutated: the merge writes into a table the
service owns.

**`generation()` is how a consumer tells a fresh read from a cached one.** Consumers
call every frame and let the service own the cadence - their own `due_for_poll`
throttles come out - but partylist's `set_roster` also *resets* its packet-pushed
overlay, so calling it sixty times a second would throw away the `0x0DD` / `0x0DF`
pushes it exists to hold. It runs only when the generation moved. Without this, a
consumer keeping its own throttle could sit up to 200ms out of phase with the
service's and see 400ms-stale data - a real regression, and the reason the throttles
move rather than stack.

**The per-frame memo is separate from the TTL.** `get_mob_by_target` is keyed by its
arguments and cleared by `begin_frame`; it never has a TTL. The wrapper stays
variadic - `XIVHud.lua:546` already notes that narrowing its arity would break the
skillchain engine's `("t", "bt")` fallback pair.

### `src/XIVHud.lua`

One service is built beside the existing accessors and its getters are handed into
every `ctx` **in place of** the raw functions. Components need no edit to benefit
from the deduplication - the reconciliation work in PS3-PS6 is what needs edits.

`begin_frame()` is called at the top of the `prerender` handler, inside the existing
`guard.wrap`, before `core.on_prerender()`. The vitals events already dispatch
through the entry point (`XIVHud.lua:757-767`); they now also feed
`service.set_vital` before `core.dispatch`. `status change` and `zone change` call
`service.invalidate()`.

### What core does not do

`core.lua` keeps the raw `deps.get_player`. Its two reads are login scoping
(`core.lua:489`) and the status seed on re-attach (`core.lua:436`), and the login
search deliberately polls at 20Hz while a login is under way - putting a 200ms TTL
in front of it would add up to 200ms of blank HUD at every login for no saving,
since it makes no calls at all once a character is scoped.

## Phases

- **PS0** - this document.
- **PS1** - `src/lib/player.lua` and `tests/player_spec.lua`. Not wired to anything.
  TTL, per-frame memo, generation, the vitals merge, and the no-mutation guarantee.
- **PS2** - wire it in `src/XIVHud.lua`: build one, hand its getters into every ctx,
  `begin_frame` on prerender, `set_vital` from the vitals events, `invalidate` on
  status and zone. **No component changes.** `tests/entry_point_spec.lua` covers the
  wiring. This is the safe checkpoint: every read is deduplicated and every
  component still reconciles for itself.
- **PS3** - `parambar` onto the reconciled read. `logic.poll`, `logic.set_vital` and
  `logic.due_for_poll` collapse into a plain read plus a generation check; the
  widget stops handling the vitals events at all.
- **PS4** - `partylist` onto it. Drops its own `get_player` / `get_party` /
  `get_info` polls, its `due_for_poll`, and `live.own_vitals`. **Keeps** `live.pushed`
  - the `0x0DD` / `0x0DF` per-member vitals are packet data about *other* people,
  which the service has no view of.
- **PS5** - `targetbar` onto it. Gains event-rate player vitals it does not have
  today, at no cost.
- **PS6** - `crossbar` onto it. It only wraps `ctx.get_player` in a nil guard
  (`crossbar.lua:307`), so this is close to free.
- **PS7** - CLAUDE.md: the new `lib/player` line in the module map, and the
  reconciliation policy stated once where the three components used to state it
  three ways.

Each phase ends green (`busted`, `luacheck .`, `stylua --check .`). PS2 and PS7 are
the two the blind review gate most needs to see.

## Risks

- **The entry point is the least testable file in the repo**, and this adds to it.
  `tests/entry_point_spec.lua` covers wiring only, over a fake `windower`; nothing
  here exercises the real client. Mitigated by keeping the service pure and the
  entry-point change to construction plus four call sites.
- **A shared cached table is a shared mutable table.** If any consumer writes to what
  `get_player()` or `get_party()` returns, it now corrupts every other consumer
  instead of itself. Verified before PS1: a grep for writes into a `player.*`,
  `member.*` or `party[...].*` field across `src/components/` and `src/lib/` finds
  none, so every consumer today is read-only. The spec pins that the service hands
  back a table it owns for the player, so a future writer cannot reach the client's.
- **Staleness by phase**, addressed by `generation()` and by the throttles moving
  rather than stacking - but that is the class of bug most likely to survive review
  here, because it is invisible in a spec where the clock is driven by hand.
- **Blast radius.** This is a framework change: a defect leaves the whole HUD wrong
  rather than one widget. PS2 is deliberately a standalone checkpoint that could ship
  alone if PS3-PS6 turn out worse than they look.
- **The load claim is unmeasured.** Nothing here can profile a client call, so
  "5 -> 1 per window" and "about 13 -> about 5 per frame" are call *counts*, not
  time. Whether that is worth anything in a live client is unknown, and the
  correctness argument is the one this change should be judged on.
- **`get_info` is currently a partylist-only inline closure** (`XIVHud.lua:757`), not
  a module-level accessor like the other three. PS2 promotes it, which is a trivial
  change that is easy to forget.

## Not in scope

- Push or subscription of any kind (decision 3).
- Caching `get_items`, recasts, spells or abilities - crossbar's reads, on their own
  cadences, with their own reasons. A later pass if the shape proves out.
- `core.lua`'s own reads (see above).
- The partylist multi-anchor migration - #26 landed the perf fix and the plan only,
  so partylist is still three registrations. This change makes that migration
  smaller, not larger, and does not depend on it.

## Review findings applied (round 1, 2026-08-30)

Three blocking, four optional. All seven acted on.

1. **`generation()` never advanced for a consumer that gated every read behind it.** The counter only
   moved as a side effect of `get_player` / `get_party` / `get_info` opening an interval, and targetbar
   gates *all* of its TTL'd reads on the counter - so its loop was self-closing. It looked right only
   because parambar and partylist call `ctx.get_player()` unconditionally earlier in the same frame and
   dragged the counter forward for it: an undocumented cross-component ordering dependency, and a dead
   widget the day parambar stopped reading per frame. Reading the counter now opens the interval itself,
   which costs nothing (the reads stay lazy). Pinned by "moves for a caller that reads nothing else".
2. **Nothing pinned the `generation` wiring.** Deleting it from both ctxs left the whole suite green while
   silently turning both widgets into per-frame roster rebuilders - which for partylist means throwing
   away its packet pushes every frame. `entry_point_spec` now pins it, which is exactly the kind of
   invisible-to-a-component-spec decision CLAUDE.md says that file exists for. The component fakes were
   also clock-driven, which is not the counter's contract, so they would have passed over a stalled
   service; both now mimic the real open-on-read behaviour.
3. **Core's `get_player` had been put behind the cache**, which this plan explicitly says not to do - a
   blanket edit caught it. Its login scoping retries at 20Hz and a 200ms TTL made resolution 200ms-
   granular, up to ~150ms of extra blank HUD per login. Reverted to the raw read and pinned.

Optional, all taken: the crossbar's per-frame `zone()` was still reading `get_info` raw and now goes
through the service (`chat_open` deliberately does not - it is asked per key event); the "same reads"
entry-point test was tautological and is now named for what it proves; the `or` fallbacks on the four
readers were dead (a nil service hard-errors at the first `invalidate()` regardless) and are gone; and
two CLAUDE.md sentences overstated the invariant - `get_info` is not universally cached, and the party
list keeps its own overlay for *other* members' vitals, which the service has no view of.

## Review findings applied (round 2, 2026-08-30)

One blocking, five optional. All six acted on.

1. **`gain buff` / `lose buff` did not invalidate.** The crossbar flips its context layers exactly once,
   from the event, and `bindings.update_buffs` is a pure diff of the list it is handed. `ctx.get_player`
   is now the service's, so at event time it returned a snapshot taken up to 200ms BEFORE the buff landed
   - a list that by construction does not contain it. The diff saw no change, nothing re-syncs per frame,
   and the layer would have stayed wrong until the next buff event: minutes, on a SCH Light Arts flip.
   The mounted-buff draw icon had the same lag. Both events now invalidate.
2. **The crossbar had its own 200ms gate stacked in front of the service's** - the very double-throttle
   this change removed from parambar, partylist and targetbar, and which the new CLAUDE.md bullet says the
   design avoids. Its cadence now rides the service's counter (falling back to its clock if the counter is
   absent), which fixes the phase drift AND keeps its deliberate "a settled frame costs zero client reads"
   property, which reading the player per frame would have broken. Found a second consumer while fixing
   it: `retry_facts` took the player off that same snapshot, so the cast retry's MP and silence guards
   were checking state up to two intervals old - they now read live, which the service makes free, and
   which is the point of a guard evaluated at the re-send.
3. **`stale` was cleared before the read**, so a client read that threw counted as the interval's and
   every later call in it was served the pre-throw value silently. Reachable today: the crossbar's zone
   read is a `pcall` that swallows the error. The flag is now cleared after the assignment.
4. **The mob memo was cleared only from `prerender`.** Key presses and packets keep arriving when
   rendering has stopped - a minimised client, or guard having disabled the handler after five failures -
   and a press resolved against a frozen target sends an action at the wrong mob. The memo now expires on
   its own after 0.1s as a backstop: far longer than a frame, far shorter than a person.
5. **partylist's `last_generation = nil` on attach was untested** while targetbar's identical guard had a
   spec. Mirror test added.
6. **The `get_info` dedup was unpinned**, and so was the more consequential half of that rule - that
   `chat_open` deliberately stays raw. Both now have entry-point specs, along with the crossbar's counter.

## Review findings applied (round 3, 2026-08-30)

Two blocking, five optional. Both blocking findings were **coverage gaps rather than defects** - the
shipped behaviour was right, but nothing tested it.

1. **The crossbar's generation-gated read path had no coverage, and the covered path was unreachable.**
   No crossbar spec supplied `ctx.generation`, so all ~330 of them ran the `generation == nil` clock
   fallback - while in a live client the counter is always present (a nil one means the service's load
   step failed, and nothing is built at all then). Inverted coverage: the branch that ships was untested,
   the branch that was tested can never run. Both sibling components had added the fake for exactly this
   reason and the largest component skipped it. The fake is now there, with a hold so a spec can prove the
   COUNTER gates the read rather than the clock.
2. **The crossbar's relog reset had no test**, while the identical guard in both siblings had one.

Optional, three taken: the service was the one construction in the entry point outside a `step(...)`, so a
throw would have died before the `addon command` handler registers - the exact failure CLAUDE.md's
diagnosability rule exists to prevent; a comment in `lib/player` claimed a missing `vitals` always stays
missing when an overlay deliberately builds one; and `entry_point_spec`'s header still said the file was
only about the chunk dispatch.

### Carried, not fixed

- **`invalidate()` is all-or-nothing** (`src/XIVHud.lua`). `gain buff` / `lose buff` are much the most
  frequent of the six triggers and each drops the whole interval, so the next tick also re-reads
  `get_party()` and `get_info()` and pushes partylist through a full `set_roster` and targetbar through an
  eighteen-member walk - when only the player is stale for a buff diff. A keyed form
  (`invalidate("player")`) would protect the dedup win under buff churn. Deliberately NOT done at round 3:
  it is new API surface added after the last review, which is how three of the earlier defects got in.
  Reviewer's own confidence that it is measurable in a live client: low.
- **A key press resolves `<t>` from the frame memo**, so the cast retry's target pin is as of the last
  `prerender` rather than live - bounded at ~16ms, with `MEMO_MAX_SECONDS` covering a dead prerender.
  Reviewer does not think a human can reach it; neither do I.

## Review findings applied (rounds 4 and 5, 2026-08-30)

Round 4 - two blocking, both fixed:

1. **The `retry_facts` change had no test that could fail.** Moving the cast retry's guards from the
   tick's snapshot to a live read is a real behaviour change - a keyed `invalidate("player")` refreshes
   the player without moving the counter, so the snapshot stays a whole interval behind exactly when a
   silence has just landed. The two nearest specs mutate `env.player` in place, so both reads are the same
   object and pass either way. The first replacement test **was also vacuous** and only mutation-testing
   caught it: `build_world` does not tick, so `reads` was still nil and every read refreshed. One tick
   before the refusal makes the snapshot genuinely stale; the test now passes on the live read and fails
   on the snapshot read, checked both ways.
2. **`invalidate()` did not do what its comment said.** "Drops everything" left the mob memo standing, so
   a zone change followed by a key press before the next `prerender` would resolve `<t>` out of the zone
   just left - the exact failure `MEMO_MAX_SECONDS` exists to prevent. The bare form now clears the memo;
   the keyed form deliberately does not, since a buff moves nobody.

Optional taken: the partylist fallback comment called rebuilding-every-frame merely "costly" when it also
drops the packet pushes (still the better of two failures, but the comment now says so), and the job
change's once-per-interval rescope retry is recorded as a decision where the code makes it.

Round 5 - **CLEAN**. Three of its five optional findings taken anyway:

1. **An overlay-only `vitals` table would have blanked parambar.** The service synthesized
   `{ hp = 640 }` when the client had sent no vitals table but an event had landed; parambar treats what
   it is handed as a REPLACEMENT, so every vital the overlay did not mention went to zero - numbers blank,
   fills hidden - where the old per-vital path left them alone. That synthesis was invented here and no
   consumer wanted it. A missing vitals table now stays missing, full stop; the event is deferred, not
   lost, since the next read is at most an interval away.
2. **`logout` now invalidates**, completing the set. Cosmetic - core detaches every component - but it was
   the one hole.
3. A comment in `partylist.lua` sat above the player read while describing the gate two lines below it.

### Accepted, not fixed

- **A character switch that happens without a `login` event** would leave the service serving the previous
  character for up to one interval, and the three components' attach resets do not help because what they
  re-read is the service's cache. Accepted: the `login` event does fire on a switch (core's prerender
  search exists because it can fire *early*, before `get_player()` can name the player, not because it is
  absent), nothing is drawn during the switch, and the window is one interval.
- **The `ctx.generation == nil` fallback branches are unreachable and untested** in all three widgets.
  Kept deliberately: a wiring slip must degrade rather than freeze, which is this repo's standing habit
  with Lua's nil-tolerance. All three now take the same fallback - read every frame - after round 6 found
  the crossbar taking a different one through a clock of its own; that clock is gone.
- **The orphaned `poll_interval_ms` key** survives harmlessly in an existing config and the user is never
  told. `lib/settings` preserves keys the defaults do not mention, so it is inert.
- **parambar no longer moves its bars from a vitals event while `get_player()` returns nil.** A window in
  which core suppresses the HUD anyway; a spec pins the freeze deliberately.

## Review findings applied (rounds 6 and 7, 2026-08-30)

Round 6 - **CLEAN**, six of seven optional findings taken:

1. **The `begin_frame`-before-`core.on_prerender` ordering was load-bearing and untested** - move it after
   and every component reads the previous frame's target while the suite stays green. Writing that test
   found something worse: the harness's core stub had **no `on_prerender` at all**, so every existing
   spec's tick was calling a nil field, erroring inside `guard` and doing nothing but `begin_frame`. A
   real stub then still did not run, because a no-op loop further down the file overwrote it. Both fixed,
   and the result mutation-checked both ways.
2. CLAUDE.md said "two reads stay raw"; it is three - core's `logged_in` is a second uncached `get_info`.
3. The partylist comment claimed the per-frame player read is what keeps the row moving at event rate.
   It is not: the row's vitals come from `get_party()` with `set_own_vital` over them. The real gain is
   that a keyed `gain buff` reaches the player's own buff icons a frame later instead of a rebuild later.
4. The crossbar's clock fallback was dead in production AND in tests, and disagreed with the other two
   consumers. All three now tell one story - no counter means read every frame - which retired
   `READ_INTERVAL_SECONDS`. Removing it orphaned two `next_read` assignments into globals; luacheck caught
   that.
5. A test name asserted the opposite of what it said. 6. `get_party` / `get_info` re-arming had no
   coverage of its own.

Round 7 - one blocking, mutation-verified by the reviewer:

- **Hoisting `logic.set_main_player` out of the interval gate was untested.** Moving it back inside left
  the whole suite green. The first test written for it **was vacuous** - the fake returned a fresh player
  table per call, and once made mutable, `set_main_player` stores the table BY REFERENCE, so moving a
  field on it is visible whether or not the setter ran again. Replacing the table rather than mutating it
  is what gives the test teeth; checked both ways. That is the third vacuous test this change produced
  and the third caught only by mutation-testing it - the check is not optional here.

Its five optional findings all taken: a dead nil-check inside the service's `step`, the untested `logout`
invalidation, a comment that protected the client's table while saying nothing about the one every
consumer now shares for an interval, a drifted comment, and this document's own stale line about
`READ_INTERVAL_SECONDS`.

## Review findings applied (round 8, 2026-08-30)

**CLEAN.** The reviewer reverted six decisions in a scratch copy and confirmed the suite fails on each:
targetbar's attach reset, the `set_main_player` hoist, `generation()` opening the interval, the
`begin_frame` ordering, `retry_facts` reading live, and the overlay dropping on a read. That is the check
this change kept needing and kept not getting from its own author.

Its four optional findings all taken: a comment claiming the raw accessors are "handed to nothing else"
when core takes `get_player` (contradicting a second comment 130 lines away that says so); a dead
`merged = nil` inside the keyed invalidate, since the only consumer of `stale.player` clears it itself;
a partylist comment still saying "four client lookups a frame PER LIST" when the memo makes it four across
all three, which is one of this change's headline wins; and an entry-point spec header saying two reads
stay raw when it is three.

### Carried: buff-churn read amplification

`invalidate("player")` on every `gain buff` / `lose buff` means a burst of buff events can drive
`get_player()` to once per FRAME rather than five times a second, because parambar reads unconditionally
every frame. Bounded at one read per frame, still cheaper than the 25 reads/sec across five callers this
change replaced, and only reachable during genuine churn. Recorded as a known ceiling rather than fixed:
the reviewer would not change it without a live-client measurement, and neither would I.

## Review findings applied (rounds 9 and 10, 2026-08-30)

Round 9 - **CLEAN**, all three optional findings taken: `begin_frame` clearing `mobs_stamp` had no
coverage (the reviewer's own mutation survived the suite); the mob memo key could collide across arities,
since one argument of `"a\0b"` joined to the same string as the pair `("a", "b")` - unreachable with the
six fixed tokens the addon passes, but `player_spec` states that separation as an invariant, so the count
now leads the key; and a comment was wrong on both halves.

Round 10 - one blocking, and a real regression this change introduced:

- **Core scopes a character from its own prerender search, not from the `login` event**, and only the
  event was invalidating. Between the two the OUTGOING character's components are still attached and still
  reading every frame, so they refill the cache with the character being left. The incoming character's
  first tick then reads it - and the crossbar's job scoping is one-shot, so it would load
  `data/<B>/crossbar/<A's job>.lua`, usually missing, and sit on an empty bar until a job change or a
  reload. Before this change `try_scope` read the client raw and could not see A there.
  Fixed by giving core an optional `deps.on_scope_change`, called in `set_character` **before**
  `apply_settings` attaches anything - pinned by a core spec that fails when the two are swapped. This is
  the one place the cache needed a signal no Windower event carries.

Its three optional findings: the shared party table now documents the hazard the player path already did;
the dead `ctx.now` scaffolding came out of the parambar and partylist specs (the widgets stopped reading
it and the entry point stopped passing it, but both specs still drove a clock, which read as though the
widget were throttled by one); and the `<t>` resolved from a ≤1-frame-old memo at key-press time stays
carried, as before.

## Review findings applied (round 11, 2026-08-30)

**CLEAN**, all three optional findings taken - two of them mutation gaps the reviewer found by reverting
behaviour the suite claimed to cover:

1. **The crossbar's attach reset was both uncovered and redundant.** Its spec drove `detach()` then
   `attach()`, and detach resets the same two locals, so the spec could not tell whether attach did
   anything - and attach already reset them further down, so the line this change ADDED was doing nothing.
   Line removed; the spec now re-attaches WITHOUT detaching, which is the path core actually takes on a
   `//hud copy` reload of the character being played, and it fails when attach's real reset is removed.
2. **`mobs_stamp = mobs_stamp or now` had no test.** Anchoring the memo's backstop to the latest insert
   rather than the first since the last clear left the suite green, and with prerender dead - the case the
   backstop exists for - lookups on different targets would keep pushing the deadline out and hold a
   frozen target past its budget. Now pinned, and the test fails against the latest-insert form.
3. A comment claiming two components read `get_mob_by_target` / `get_party` directly; neither does now.

## Review findings applied (round 12, 2026-08-30)

**CLEAN**, no blocking. Two of three optional findings taken:

1. **`status change` was using the bare `invalidate()`** where the keyed form does: engaging, resting, a
   death or a cutscene moves the player and neither the party nor the zone nor any mob, so the bare form
   was re-reading those too and moving the counter - putting the party list through a full roster rebuild,
   discarding its held packet pushes, for a fact it does not hold. Infrequent enough to hardly matter, and
   inconsistent enough with the buff handler two blocks below to read as an oversight rather than a
   choice. Now keyed and pinned.
2. **The memo key could still collide between a number and its string form** (`5` and `"5"`). Unreachable
   with the six fixed tokens the addon passes, but the block above it calls the separation "an invariant
   rather than an accident", and it was not one. The key is now typed.

Its third finding is a trade already on the record: a vitals event cannot move parambar's bars while the
client reports a player carrying no `vitals` table at all. That window is logged-out or zoning, where core
suppresses the HUD anyway, and the freeze is deliberately tested.

## Review findings applied (round 13, 2026-08-30)

**CLEAN**, no blocking, and the reviewer's own mutations confirmed the counter and overlay tests bite. One
note taken: the memo's comment claimed "the arity is not narrowed", which is true of the ARGUMENTS and
false of the RETURN - the memo boxes one value where the wrapper it replaced passed all of them. Nothing
reads past the first (the API answers a single mob table), so the comment was corrected rather than the
code.

Its other four notes are all trades already recorded here: the orphaned `poll_interval_ms`, parambar not
moving on an event while the client reports a player with no `vitals`, press-time reads being up to an
interval old (the keyed invalidations cover silence, subjob and job level; the residual is MP/TP at the
instant of a press, which this component already resolves in favour of sending), and `<t>` resolving from
the previous frame's memo.

## Where this stands

The gate is settled: thirteen rounds, seven CLEAN, nothing blocking outstanding. What no amount of review
here can establish:

- **Whether the deduplication is worth anything.** Every load claim in this document is a CALL COUNT, not
  a measurement. Nothing here can price a Windower client call.
- **Whether the original bug is actually fixed.** If `hp change` turns out to diff the same struct
  `get_player()` reads, the poll re-asserts the same wrong value and the HP number still sticks. That was
  unverified when the parambar fix landed and it is unverified now.
- **Whether any of it loads.** Green locally does not mean it loads - this repo has shipped a build that
  passed every check and registered no events.
