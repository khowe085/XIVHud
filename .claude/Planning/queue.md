# Action queue

FFXIV's queue for FFXI: a bar press made during the cast or the lock after it
is held, and goes as invoked the moment the lock clears. Its only job is to
smooth the gap between back to back actions (Kevin, 2026-10-31).

## Why this shape

**No packet says the lock is over** (90%). atom0s' `0x0028` notes list start,
finish and interrupt and nothing else; none of LandSandBoat's server packets
fits, and its magic state ends without sending anything. The server simply
stops refusing. So one fixed length per action kind stays, and everything else
comes from packets.

**That length needs no latency term.** The lock starts on the server no later
than the finish packet leaves it (85%: bg-wiki starts it at the cast finishing,
LandSandBoat pushes the packet in that same update), so "finish packet + the
lock" reaches the server after the lock has ended whatever the connection is
doing. Latency can only make the release late, by about a round trip, never
early.

Selindrile's MiniQueue starts from the same packet (its aftercast) and then
subtracts a guessed `latency = .5` to aim early, which is the race. Its safety
net never runs: the `0x029` handler compares `action.message`, the field is
`Message`, and the packets library holds no alias for it. Its precast estimate,
`cast_time / 4 + 3`, has no equivalent here: nothing computes a cast time.

## Decisions (Kevin, 2026-10-31)

- **Bar presses only.** Macros and typed commands are never held, but their
  packets count towards the lock. Catching them would mean competing with
  GearSwap for `outgoing text`.
- **Held through the whole cast and the lock**, not FFXIV's last half second.
- **One held action**, the newest press replacing it.
- **A press while free sends at once**, exactly as it did.
- **One shot.** A release is never re-sent, refused or not.
- **Never held on a recast.** A press whose own recast is running goes out as
  it always did, and the game refuses it. An action whose recast is running
  when the lock clears is dropped, never waited on.
- **An interrupted cast keeps the held action**, released after the interrupt's
  lock.
- **No highlight on a held slot** in the first version.
- **`//hud queue on|debug|off`, shipping off**, in `core.lua` beside `delay`.
  `debug` is `on` plus a chat line per edge, which is what replaced the
  `queue.log` probe proposed first (Kevin). The same lines go to `debug.log`
  beside `load.log`, dated and never truncated, because the client runs on
  another computer (Kevin).

Four that came out of building it, all kept by Kevin the same day:

- **A second press of an action still unanswered is not held.** It goes out as
  it always did and the game refuses it. A weaponskill or an item has no recast
  to stop a double tap, and held, the second tap would spend the TP or the item
  again. Pressed again once the first is on its way, it is an ordinary press, so
  mashing one through the lock still uses it a second time.
- **The lock lengths are constants, not settings.** Debug mode brackets them with
  a macro, so nothing needs changing in game to measure them, and a stored default
  would outlive the measured one: nothing migrates.

- **A dropped press is silent outside `debug`.** It flashed when pressed, and
  going quiet is the opposite of the trips' "a cancel is never silent". Chat lines
  are what `debug` is for.
- **A charged family's shared ability recast reads as no recast**: 231 stratagems,
  195 Quick Draw, 102 and 255 Ready, the ids Selindrile's `check_recast` skips. It
  relaxes "never held on a recast". The timer running there says a charge was
  spent, not that none is left, the slot stays bright under it, and a chain of
  stratagems is the case the queue is for. With no charge left the press is held
  and the game refuses its release: nothing waits on the recast, and the counts
  are only known for stratagems. Spells number their recasts apart, so a spell on
  one of those numbers is an ordinary recast.

### Targets

- `<t>` and `<bt>` are pinned to the mob id at the press, with the
  `pinned_command` the enchanted use already has. `<me>` and `<pet>` need no pin.
- A slot with **no target** is held and sent verbatim, so whatever the game does
  with a bare command it does at the release. `(no target)` is the binder's
  default row, so refusing these would leave most mouse-bound slots unqueued.
- Everything else goes out as it always did: `<st>` and its kin are a cursor,
  `<ft>` cannot be pinned, and `<pN>` is whoever stands there at the release
  (Kevin's own rule from the cast retry, 2026-08-19). Pinning `<pN>` by id would
  let them back in, and needs `get_mob_by_target("p3")` read in a client first.
- The `sneak`, `invisible` and `reraise` built-ins are not held: each walks a
  ladder at the press, and what it found would be stale by the release.

## The state machine

`lib/actionbar/queue.lua`, pure. Three facts, each cleared by its own packet:

| Fact | Set by | Cleared by | Backstop |
| --- | --- | --- | --- |
| `sent`: something went out, nothing back yet | a bar press or release, outgoing `0x01A` (3 magic, 7 ws, 9 ja, 16 ranged, 25 monster skill), outgoing `0x037` (item) | any `0x028` start or finish of ours, a refusal | 0.6s until the packet is seen, 2s after |
| `acting`: a cast is running | `0x028` 7, 8, 9, 12 of ours | a finish, an interrupt (the same category with param 28787) | 30s |
| `lock_until`: the lock's end | a finish (2, 3, 4, 5, 6, 11, 14, 15 of ours), an interrupt | time | none needed |

Busy is any of the three. A held press goes on the first tick nothing is busy.

`sent` is set by the press itself as well as by the packet because nothing says
how soon after a press `outgoing chunk` fires: if it waits for the client's next
send, a second press inside that gap would go straight out. A press gets 0.6s to
be seen leaving, and 2s for its answer once it has. The short one exists because
GearSwap filters cancel a press with no packet at all (Selindrile's
`filter_precast` does, on a recast, a cost or silence), and the next press must
not wait out an answer that cannot come. It is a guess past the client's send
cadence: too short, a press held behind one still leaving is released early and
refused. A press on its own recast sets nothing, for the same reason. The 30s
backstop bounds a finish that never arrives, and a held press older than that is
dropped.

Zone, death, job change, logout, unload and `off` forget everything, since
nothing tracks packets while off. A config mode, suppression and a bar's
re-attach drop what is held and leave the lock.

A newer finish replaces a lock rather than extending it: an action the server
accepted proves the old lock is over.

Refusals are GearSwap's own `unable_to_use` list (`statics.lua`), which has been
deciding "that action did not happen" off `0x029` for years; 94 stays out, as it
does there. It replaces the retry's guesses of 71 and 72 for abilities and
weaponskills, which are probably the wrong ids: 87-90 are "Unable to use job
ability" and "Unable to use weapon skill". A refusal ends `sent` and nothing else:
the lock is still running.

## Lock lengths

Constants in `queue.lua`, the longer of two sources, with ranged rounded up from
its one source, because too long costs a moment and too short loses the press.
**Every one is unverified.**

| After | bg-wiki | Selindrile's aftercast | Shipped |
| --- | --- | --- | --- |
| spell | 3.0 | 2.9 | 3.0 |
| weaponskill | 2.0 | 2.7 | 2.7 |
| ability | 1.0, 2.0 before auto-attack | 0.8 | 1.0 |
| item | none | 1.5 | 1.5 |
| ranged | none | 0.85 | 1.0 |
| interrupted | none | 1.75 | 1.75 |

bg-wiki's spell lock runs from the cast finishing at 75% of the gauge, and its
example lands the effect 0.33s later. If the finish packet comes with the
effect, the true remainder is nearer 2.7. Kevin's own "usually 1-2 seconds"
disagrees with all of it.

## Review gate

Four blind rounds, clean on the fourth. Round 1 caught a stratagem with charges in
hand reading as on recast, the GearSwap notice, and `going` surviving its answer.
Round 2 caught the charged recasts applying to spells on the same numbers. Round 3
caught a press GearSwap cancels stalling the next one for the full 2s, which is
what the 0.6s and the recast check at the top of `press` are for.

## Measuring in a live client

`//hud queue debug`, then cast back to back and mash an in-game **macro** through
the lock: bar presses are held and so never test the edge, macros are not. Each
action going out prints how long after the last finish it left, and the next
line says whether it started or was refused. The last refusal and the first
start bracket the true lock. Every line is in `debug.log` too.

| # | Do | Expect | Why |
| --- | --- | --- | --- |
| 1 | Cure, then a macro repeatedly through the lock | `refused` lines, then `start` | The spell lock, and whether refusals are `0x029` at all (question C of the old retry) |
| 2 | Repeat after a weaponskill, a job ability, an item and `/ra` | The same | Each constant above |
| 3 | Move during a cast, then repeat | `interrupted`, then the bracket | The interrupted constant |
| 4 | Bar press during a cast, `queue on` | One `hold`, one `release`, the spell goes with no chat refusal | The feature |
| 5 | Bar press during the lock, then another | The second replaces the first | Newest wins |
| 6 | Bar press of a spell on its own recast | `not held`, the game's usual refusal | Never held on a recast |
| 7 | Press a spell during its own cast | `dropped ... on recast` at the release | Same, from the other end |
| 8 | Hold a `<t>` nuke, tab to another mob | It lands on the first mob | The pin, and that `/ja`, `/ws`, `/ra` and `/item` take a bare id as `/ma` does |
| 9 | Hold, then zone or die | `cleared`, nothing goes | Nothing outlives its moment |
| 10 | Macro casts in `queue on` | Lines only in `debug`, bar presses hold behind them | Packets count whoever sent them |
| 11 | Mash a bar press faster than the ping, then watch for `nothing went out for the last press` on a press that did go | The line never appears on a press that went | Whether 0.6s covers the gap between a press and `outgoing chunk`, which may fire at the client's next send |
| 12 | A pet command and a blood pact | A `sent` that ends on an answer, not the 2s backstop | Which packet answers `/pet` |
| 13 | A weaponskill out of range | `finish spell` for category 4 and a 3s lock | atom0s says that failure arrives as category 4; if the lock is wrong it needs its own case |
