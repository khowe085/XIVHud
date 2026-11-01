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
- **A press while free sends at once**, exactly as it did. A cursor slot still opens
  its cursor at once, over `/ta`.
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

- **A second press of an action still unanswered is swallowed.** Held, it would
  spend a weaponskill's TP or an item again, and sent, it could only be refused,
  which GearSwap takes for the end of the cast and swaps out of the midcast set.
  Pressed again once the first is on its way it is an ordinary press, so mashing
  one through the lock still uses it a second time. It went out as it always did
  until Kevin said he mashes `<t>` slots.
- **The lock lengths were constants, and are settings now** (Kevin, reversing this
  the same day): `//hud queue lock [<kind> <seconds>]`, 0 to 5 in tenths, with a
  stepper row each on the settings window's `global` panel. The original worry was
  a stored default outliving a measured one, since nothing migrates, so `queue_locks`
  is unseeded: it holds only what has been set, and a kind never touched follows
  the shipped length.

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
- `<st>` and its kin are judged at OK, not at the press (below).
- Everything else goes out as it always did: `<ft>` cannot be pinned, and `<pN>`
  is whoever stands there at the release (Kevin's own rule from the cast retry,
  2026-08-19). Pinning `<pN>` by id would let them back in, and needs
  `get_mob_by_target("p3")` read in a client first.
- A `sneak`, `invisible` or `reraise` slot walks its ladder at the press, and the
  rung it picks is held as a slot of that action, with that action's recast and pin.
  They were not held at first, on the grounds that what the ladder found would be
  stale by the release, until an Invisible pressed in Sneak's lock was refused
  (Kevin, 2026-10-31). A rung gone stale, say to silence, is the game's to refuse.
  A gear rung runs its own equip and wait and is not held.

## Cursor slots: judged at OK (Kevin, 2026-10-31)

The first live logs held nothing he cared about: his buffs are `<stpc>` slots, he
pre-selects a target and presses OK when the cast is done, and every OK inside
the lock went straight out and was refused (message 17). Being judged at the press
also said "on recast" of a slot whose recast was up by OK.

The hold has to happen when the command is sent, which is the hard part. GearSwap
acts on a `/ma` inside its `outgoing text` handler, gear and packet together, so:

- **Blocking the packet** leaves its registry entry `midaction` until it ages out,
  which stops Selindrile's idle gear, and the set stays on through the hold.
- **Catching the `/ma` text first** needs XIVHud ahead of GearSwap in an event
  order Windower does not document, and fails silently behind it.
- **Asking GearSwap to cancel** means changing the fork and a protocol between two
  addons.

What ships uses `/ta`, which GearSwap ignores. Byrth's account of the cursor: the
game sends `/ta <your id>` at once, which raises the arrow, then `/ta <chosen id>`
on OK. GearSwap's `st_flag` skips the first of these the same way. So a cursor slot
opens the same cursor over `/ta <token>`, free or busy, and the queue counts the
numbers: the first goes through, the second is OK. That line is blocked, so the
target never moves, and the real `/ma "..." <id>` is held, or sent at once when the
lock has cleared or the recast is running. If the second number ever failed to
come, the `/ta` would run: the target moves and nothing casts.

**Free counts too.** It went as it always did until a run showed the hole: a Sleep II
opened while free, then GearSwap sent a weaponskill, and the OK went out at +1.80 and
was refused. The cost is `pretarget`, which no longer runs for a cursor slot while
the queue is on.

**An arrow already up.** The double-tap failure was real (row 20): Kevin's Dia III and
Sleep II, where a second press raised no arrow, OK was counted as one, the `/ta` ran
and nothing cast. A press 1.8s later did raise one, because that cursor had gone.
So a press asks `get_mob_by_target("st")`, which Kevin confirmed answers nothing with
no cursor (the subtarget bar disappears): with an arrow up nothing is sent, and the
press only changes what OK will cast. That also ends the game's "You cannot perform
that action on the selected sub-target", which is what the resent token drew.

## The state machine

`lib/actionbar/queue.lua`, pure. Three facts, each cleared by its own packet:

| Fact | Set by | Cleared by | Backstop |
| --- | --- | --- | --- |
| `sent`: something went out, nothing back yet | a bar press or release, outgoing `0x01A` (3 magic, 7 ws, 9 ja, 16 ranged, 25 monster skill), outgoing `0x037` (item) | any `0x028` start or finish of ours, a refusal | 0.6s until the packet is seen, 2s after |
| `acting`: a cast is running | `0x028` 7, 8, 9, 12 of ours | a finish, an interrupt (the same category with param 28787) | 30s |
| `lock_until`: the lock's end | a finish (2, 3, 5, 6, 11, 14, 15 of ours, and 4 while a cast is running), an interrupt | time | none needed |

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

The shipped lengths, at the top of `queue.lua`, because too long costs a moment and
too short loses the press. `spell` and `weaponskill` are measured from Kevin's logs
below and `interrupted` is bracketed by them; **the other three are unverified**,
the longer of two sources with ranged rounded up from its one.
`//hud queue lock` and the settings window override any of them.

| After | bg-wiki | Selindrile's aftercast | Shipped |
| --- | --- | --- | --- |
| spell | 3.0 | 2.9 | 2.7, measured |
| weaponskill | 2.0 | 2.7 | 2.4, measured |
| ability | 1.0, 2.0 before auto-attack | 0.8 | 1.0 |
| item | none | 1.5 | 1.5 |
| ranged | none | 0.85 | 1.0 |
| interrupted | none | 1.75 | 2.7, the spell's, bracketed at +2.23 to +2.37 |

bg-wiki's spell lock runs from the cast finishing at 75% of the gauge, and its
example lands the effect 0.33s later, so the finish packet comes after the lock
has started. Kevin's logs of 2026-10-31 agree. Of about 70 sends:

- Answers arrive on a 0.4s beat: near +2.8, +3.2 and +3.6 after the finish.
- A send that makes the +2.8 beat is a coin toss: refused at +2.45, 2.48, 2.52,
  2.54 and 2.58, accepted at +2.48, 2.49, 2.50, 2.51, 2.52 and 2.53. Which one
  depends on where the cast finished inside its beat.
- Nothing from +2.66 up was refused: those make the +3.2 beat.
- A release at 3.0 went out at +3.03 and often missed that beat too, starting at
  +3.6 instead.

2.7 sits inside the safe range, not at its edge. A release leaves 0.02-0.03s after
it is sent, in six of six samples, so it goes out at about +2.73. Everything up to
about +3.0 makes the same beat, which is why nothing is gained by shaving it.

One thing the logs leave open: of seven releases, one (Stoneskin, straight after a
refused Shell V) printed `nothing went out for the last press`. Whatever dropped
it is outside this queue, and the case behind it, a held press waiting behind a
cursor OK that goes out and is refused, is gone now that OK is held too.

## First live session at 2.7 (Kevin, 2026-10-31: "This felt good")

- **29 releases, none refused.** 27 went out at +2.72 to +2.74 and started by +3.4,
  so the +3.6 starts the 3.0 lock kept losing are gone.
- **15 cursor OKs**, on `<stpc>` and `<stnpc>`: all caught, held and cast. Row 14
  passes, and `outgoing text` does bring two numbers.
- **The mash works** (row 18): a run of twelve `hold` lines then one cast, with
  `swallowed` while it was unanswered.
- **The other two releases were Savage Blade**, which sent nothing. Both came
  straight after a weaponskill, so GearSwap's TP guard is the likely cause, and no
  TP was spent. Not confirmed.
- **Cursors with no OK** were ones Kevin cancelled.
- **Weaponskill and ability hints:** a spell went out +2.32 after a weaponskill finish
  and was accepted, once in each of two sessions, as an ability did at +1.28 after
  an ability. Not enough to move either constant. The weaponskills in these runs
  were GearSwap's own, not bar presses. Item, ranged and interrupted have no data.

The second session added 23 releases, none refused, and 24 OKs, 3 of them after the
lock had cleared (row 15).

The third added 73 releases, none refused by the lock. Its two message 17s were both
sent on recast. Its other refusals were range (78, 313, 219) and one interrupt (16).
It showed three more things:

- **A false lock, now fixed.** `finish spell` with no `out` or `start`, a melee round
  apart (82602.79, 82604.42, 82605.64) while Kevin was paralyzed. That it is a
  paralyzed round is inferred: the new debug line prints the message, which should
  read 84 or 29. Sends +0.68, +1.23 and +1.49 after one were accepted, so nothing
  locks, and each was starting a false 2.7s that held bar presses for nothing. A
  category 4 with no cast running is now ignored, which also means the interrupt's
  lock stands when an interrupt's finish arrives just after it. That covers
  atom0s' weaponskill-out-of-range category 4 too (row 13): no lock.
- **The weaponskill lock is 2.4.** All four sends at +2.32 after a weaponskill were
  accepted. The exact figure is Selindrile's timing, 2.7 - .5 + a .1 tick, so these
  were GearSwap's own actions, and it means nothing was tried shorter. bg-wiki says
  2.0. It should turn the +3.2 starts after a weaponskill into +2.8.
- **After an interrupt** the shortest accepted send was +2.36, and nothing was tried
  between that and 1.75, so `interrupted` stays as it was.

Two releases of Savage Blade sent nothing, as before. One Stun at 82180.65 went out
and got no answer at all.

Two more runs on the same day, the second on the 2.4 lock:

- **No release refused** in 34 more, 30 of which went out. The 4 that sent nothing
  were all Savage Blade straight after a weaponskill, which makes 8 of 8 across every
  run, while the one that followed a spell went out. GearSwap's TP guard, almost
  certainly.
- **The first release at 2.4:** a Sleep II went out at +2.43 and started at +2.78, a
  beat earlier than the 2.7 lock gave. One sample.
- **`interrupted` was too short.** A Sleepga went out +2.23 after a real interrupt,
  once the 1.75 lock had cleared, and was refused. A weaponskill +2.35 after a
  paralyzed cast's interrupt was accepted, so it lies around there. It takes the
  spell's 2.7 until someone measures it, since too short loses the press.
- A weaponskill +2.12 after a spell finish was refused (message 90), which agrees
  with the spell lock.

## A full run of endgame content (Kevin, 2026-10-31, on `f8f1a0e`)

71 minutes, 165 releases that went out, and the first run long enough to bracket
more than the spell lock.

- **163 of the 165 started.** 136 after a spell, at +2.71 to +2.74, and 27 after a
  weaponskill, from +2.42. The other two went +1.78 after an interrupt on the old
  1.75 lock and were refused, which `8bb87b2` already answers.
- **`spell` stays 2.7.** Sends the queue never held were refused at +1.83, 1.85, 1.86,
  2.36 and 2.38 and accepted at +2.19, 2.21, 2.51, 2.57 and 2.65. The coin toss is
  wider than the first logs said, and nothing from +2.66 up has been refused in any
  run.
- **`weaponskill` stays 2.4, now measured.** Refused at +1.44, 1.51, 1.76, 1.80 and
  2.09, accepted at +2.09, and one at +2.01 got no answer. Every release from +2.42
  was accepted.
- **`interrupted` is bracketed.** Refused at +1.78 twice and +2.23, accepted at +2.37,
  2.56, 2.65 and 2.69. 2.7 is safe and may be long.
- **`ability` has its first edge:** +1.04 after Convert was accepted, and nothing
  shorter was tried. Item and ranged have no data.
- **The nukes came from the in-game menu**, quicker than switching bars, so the queue
  never saw them. Kevin wants that left as it is. The Trust summons went unheld too.
- **A weaponskill held across a weaponskill never went: 73 of 73**, after 8 of 8 in
  the runs before. No packet left, so the queue sat out its 0.6s for one, and the next
  action went late 6 times (+3.03 to +3.05 rather than +2.43). A free press with no
  TP armed the same wait 11 times.
- **142 OKs were caught.** Two double-tapped `<stnpc>` OKs reached the game as `/ta`,
  at 18:50:44 and 18:53:26, which `8bb87b2` answers.
- **Still unexplained:** five sends got no answer at all, and twice (19:44:41 and
  19:48:17) a weaponskill's start was followed by a category 4 finish, so it took the
  2.7 lock. Paralysis would fit.

**So a weaponskill under 1000 TP goes nowhere** (Kevin, on this run). At the press,
free or busy, nothing is sent and what is held stays. A cursor's is judged the same
way at OK. Held, it is dropped at the release, since the TP only reads as spent by
then. The trade is a press that shows nothing, not even the game's refusal, and only
while the queue is on.

## A shorter run on the TP check (Kevin, 2026-10-31, on `faf53c6`)

24 minutes and 37 releases, none refused by a lock.

- **The TP check holds.** `nothing went out` went from 89 lines to none, with 46
  presses swallowed and 8 dropped at a release.
- **`ability` has a release:** Haste II at +1.04 after Composure started at +1.66.
- **Message 84 is confirmed:** five `ignored` lines while Kevin was paralyzed.
- **Invisible straight after Sneak was refused**, at +0.83 and +1.80, from the ladder
  slots, which were not held then. That is what changed the rule under Targets.
- **One real finish was ignored.** A Sleep released at 21:22:13 finished with message
  236 and no start was seen, so it took no lock, and a weaponskill 0.5s later was
  refused. It is the only ignored finish in two runs that was not paralysis, so the
  rule stands.
- The range refusals (78, 313) were the mob moving, and the nukes were the menu again.
- **The free press works** (row 22): 73 OKs, all caught, some with a weaponskill's
  lock beginning after the press. Rows 20 and 23 are still open: no press met an
  arrow already up.

## A run on the held ladder (Kevin, 2026-10-31, on `f877c49`: "felt the best")

23 minutes and 42 releases, none refused by a lock, ending in a client crash.

- **Row 28 passes:** Invisible straight after Sneak was held and cast, 3 of 3.
- **Row 27 passes:** a Cure IV cursor stayed up for 49s and its OK was caught.
- **`no TP` works on any weaponskill**, Black Halo as well as Savage Blade.
- **One release went nowhere:** Cure IV at 22:04:55, cause unknown, and re-pressed 4s
  later.
- Rows 20 and 23 are still open: no press met an arrow already up.

**The crash:** `pol.exe`, fault in `Hook.dll` at `0xc739a`, code `0xc0000409`, on
stable 4.7.9.3 with the client up 27 hours. Windower/Issues#1116 documents that exact
offset as `abort()`'s fast-fail, so the record says only that Hook aborted. Lua runs in
`LuaCore.dll`, not `Hook.dll`. That issue shows the same record from plainly closing
POL with no addons loaded, so it may be the tail of POL exiting for another reason. The
queue was idle: the last line is a weaponskill finish at 22:11:18 and the `lock over`
due 2.4s later never came. Only a dump can say more, by showing whether `ExitProcess`
is on the stack.

## Open: left targeting a Trust

Kevin, in that run: locked onto a Trust with weapons out, swinging at a monster he
could not target, with no Switch Target or Disengage in the menu, until the crossbar's
disengage (`/attack off`) and a re-engage. He thinks his target died while he was
picking a cure target. It happened before the queue too, though he usually ended up
on a battle target then.

- **Likely moment, 19:17:55.** Savage Blade was refused twice with message 446, "You
  cannot attack that target", the only two of the run, then 23s with nothing sent,
  then it worked. Two Trust cursors came before it, at 19:17:24 and 19:17:27, but Fire
  V started at 19:17:40, so it may have begun after them.
- **Ruled out:** his pick reaching the game as a `/ta`. Every `<stpc>` OK was caught.
- **Not ruled out:** what the game does with a `/ta` arrow up as the target dies. A
  `/ma` arrow cannot set your target and a `/ta` one can, which would fit landing on a
  Trust rather than a battle target. `8bb87b2` opens every cursor over `/ta`, so if
  that is the cause it now happens more often. Row 26 settles it.
- **Not reproduced.** Kevin tried on `faf53c6` and could not get it to stick, which
  he is clear is no evidence that it is fixed.
- **One real way into that state is closed.** The sixth review round found that an
  arrow held past 30s lost its cursor, so OK ran as a `/ta` and moved the target. That
  was not this run's cause: no `<stpc>` cursor timed out.

## Review gate

Four blind rounds, clean on the fourth. Round 1 caught a stratagem with charges in
hand reading as on recast, the GearSwap notice, and `going` surviving its answer.
Round 2 caught the charged recasts applying to spells on the same numbers. Round 3
caught a press GearSwap cancels stalling the next one for the full 2s, which is
what the 0.6s and the recast check at the top of `press` are for. A fifth round
over the whole feature, after the cursor work and `debug.log`, was clean; its note
on a closed cursor taking the next `/ta` as its OK is why a token line after the
arrow now ends one.

A sixth round, over the whole feature after the TP check, reported an arrow held past
30s losing its cursor, so OK ran as a `/ta`, and the give-up reading any token at all
as our arrow gone. A cursor now outlives the 30s for as long as its arrow is up, and
a token only ends one with no arrow up, since the game refuses a token while one is.
Two optional notes stand: a second press in the frames before `<st>` answers still
reads as a fresh cursor (row 20 will show it), and a press with an arrow up changes
what OK casts even if its token differs, as row 23 intends.

A seventh round came back clean. Its optional notes that stand: with the libraries
failed the bars still load but `outgoing text` does not, so a cursor press would lose
its OK with the queue on, and `Weaponskill lock (seconds)` may overrun its label
column by about 18px at 18pt (an estimate, to check in `//hud config`).

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
| 13 | A weaponskill out of range | `ignored a finish with no cast running` and no lock | atom0s says that failure arrives as category 4 |
| 14 | During a cast press a `<stpc>` slot, pick a target and press OK inside the lock | `cursor`, `OK ... at <id>`, `hold`, `release`, and the cast lands on who you picked with your target unchanged | The whole of the cursor path |
| 15 | The same, pressing OK after the lock clears | `OK`, then `out` at once, no `hold` | OK while free |
| 16 | Press a `<stpc>` slot during a lock, then ESC | Nothing goes, the next press works | A cursor abandoned |
| 17 | During a cast, a `<stpc>` slot whose recast is up by OK | No `on recast` line, it casts | Judged at OK |
| 18 | Mash a `<t>` slot from before the press lands | One cast, `swallowed` lines, the midcast set stays on | The mash |
| 19 | Precast gear on a cursor slot held through a lock | The spell casts in Fast Cast gear | GearSwap's numeric path runs precast at the release |
| 20 | Double-tap a `<stpc>` slot during a lock, then OK | `cursor up, OK takes ...`, one `OK`, cast at who you picked, target unchanged | FAILED before the fix, as predicted. A second press raised no arrow, OK read as one and the `/ta` ran |
| 22 | Press a `<stpc>` slot while free, let a weaponskill go, press OK in its lock | `hold`, then `release` at the lock's end | The refused Sleep II |
| 23 | Keep the cursor up and press a different cursor slot, then OK | The newer spell casts | The press only changes what OK casts |
| 24 | Press a cursor slot during a macro's own `<st>` cursor | The game's usual answer, and the macro's spell on OK | An arrow this did not open is left alone |
| 21 | ESC a cursor, then run a `/ta <stnpc>` macro | The macro's cursor works, and nothing casts | A closed cursor must not take another's line as its OK |
| 25 | Mash a weaponskill through its own lock, then press a spell as the lock ends | `swallowed ... no TP` or `dropped ... no TP`, no `nothing went out`, and the spell goes at about +2.43 | The TP check |
| 26 | Hold a `<stpc>` arrow on a Trust as your target dies, opening it during a lock. Repeat with `//hud queue off` | Which run leaves you on the Trust | Whether a `/ta` arrow is what strands you |
| 27 | Hold a cursor up past 30s, then OK | It casts at who you picked, target unchanged | A long pre-select |
| 28 | Press a `sneak` slot, then an `invisible` slot inside its cast or lock | `hold Invisible`, `release`, and it casts with no refusal | A ladder slot held |
