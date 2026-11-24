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
`cast_time / 4 + 3`, has no equivalent here: a cast time only bounds how long a
spell or a start may go unanswered when lag loses its packet (below, 2026-11-06).

## Decisions (Kevin, 2026-10-31)

- **Bar presses only.** Macros and typed commands are never held, but their
  packets count towards the lock. Catching them would mean competing with
  GearSwap for `outgoing text`.
- **Held through the whole cast and the lock**, not FFXIV's last half second.
- **One held action**, the newest press replacing it.
- **A press while free sends at once**, exactly as it did. A cursor slot still opens
  its cursor at once, over `/ta`.
- **One shot.** A release is never re-sent, refused or not.
- **Never held long on a recast.** A press whose own recast runs more than two
  seconds past the lock goes out as it always did, and the game refuses it. An
  action whose recast is that far off when the lock clears is dropped. A press
  whose recast ends inside
  the lock running is held (Kevin, 2026-11-01), since it waits on the lock alone,
  and so is one whose recast ends within two seconds after it (Kevin, 2026-11-07;
  a second until 2026-11-08).
- **An interrupted cast keeps the held action**, released after the interrupt's
  lock.
- **No highlight on a held slot** in the first version.
- **`//hud queue on|debug|off`, shipping on** (it shipped off until 2026-11-01, Kevin),
  in `core.lua` beside `delay`.
  `debug` is `on` plus a line per edge, which is what replaced the
  `queue.log` probe proposed first (Kevin). The lines go only to `debug.log`
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
  going quiet is the opposite of the trips' "a cancel is never silent". The log
  is what `debug` is for.
- **A charged family's shared ability recast reads as no recast**: 231 stratagems,
  195 Quick Draw, 102 and 255 Ready, the ids Selindrile's `check_recast` skips. It
  relaxes "never held long on a recast". The timer running there says a charge was
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
lock has cleared (and no held press waits on its recast) or the recast outlasts it by
more than two seconds. If the second number ever failed to
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
| `sent`: something went out, nothing back yet | a bar press or release, outgoing `0x01A` (3 magic, 7 ws, 9 ja, 16 ranged, 25 monster skill), outgoing `0x037` (item) | any `0x028` start or finish of ours, a refusal | 0.6s until the packet is seen, 2s after, or a spell's `cast_time` + 0.4s where longer (2026-11-06) |
| `acting`: a cast is running | `0x028` 7, 8, 9, 12 of ours | a finish, an interrupt (the same category with param 28787), and while a weaponskill's start runs a 4 naming no spell (2026-11-10) | a spell's `cast_time` + 0.4s, a weaponskill 1.2s (3s until 2026-11-10), an item's `cast_time` + 1s, else 30s; a finish is still read as one for 30s (2026-11-06) |
| `lock_until`: the lock's end | a finish (2, 3, 5, 6, 11, 14, 15 of ours, and 4 naming a spell while a cast is running (2026-11-08), within 30s of a start of ours when it names that start's spell or the start named none, or naming a spell that went out and is unanswered (2026-11-07), or naming no spell while a weaponskill's start runs, which takes the weaponskill lock (2026-11-10)), an interrupt, the end of a start's wait | time | none needed |

Busy is any of the three. A held press goes on the first tick nothing is busy, or once
its recast ends if that is within two seconds (2026-11-07, a second until 2026-11-08).

`sent` is set by the press itself as well as by the packet because nothing says
how soon after a press `outgoing chunk` fires: if it waits for the client's next
send, a second press inside that gap would go straight out. A press gets 0.6s to
be seen leaving, and 2s for its answer once it has. The short one exists because
GearSwap filters cancel a press with no packet at all (Selindrile's
`filter_precast` does, on a recast, a cost or silence), and the next press must
not wait out an answer that cannot come. It is a guess past the client's send
cadence: too short, a press held behind one still leaving is released early and
refused. A press on its own recast sets nothing, for the same reason. A finish that never
arrives is bounded by the start's own length (2026-11-06, below), or 30s where
nothing names one, and a held press older than 30s is dropped.

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
below, `interrupted` is bracketed by them, `ability` sits a step above a tested 0.4 and
`item` rests on two samples;
**`ranged` is unverified**,
Selindrile's figure rounded up to a second.
`//hud queue lock` and the settings window override any of them.

| After | bg-wiki | Selindrile's aftercast | Shipped |
| --- | --- | --- | --- |
| spell | 3.0 | 2.9 | 2.7, measured |
| weaponskill | 2.0 | 2.7 | 2.4, measured |
| ability | 1.0, 2.0 before auto-attack | 0.8 | 0.5, a step above 9 of 9 held spells at 0.4 |
| item | none | 1.5 | 1.0, above two accepted sends at +0.64 and +0.86 |
| ranged | none | 0.85 | 1.0 |
| interrupted | none | 1.75 | 2.7, the spell's: refused up to +2.23, accepted from +2.01 |

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
- **Row 27 passes:** a Cure IV cursor stayed up for 49s, its OK was caught, and Kevin's
  main target stayed locked.
- **Row 19 passes on the numbers:** held spells cast as fast as free ones (Cure IV
  0.84s against 0.82s, Refresh III 1.22s against 1.21s), so the Fast Cast set goes on.
- **`no TP` works on any weaponskill**, Black Halo as well as Savage Blade.
- **One release went nowhere:** Cure IV at 22:04:55, cause unknown, and re-pressed 4s
  later.
- Rows 20 and 23 are still open: no press met an arrow already up.
- **The biggest gap:** all 322 releases in the last three logs were spells or
  weaponskills. No ability, item, ranged shot or pet command has been held, so the
  bare id on `/ja` and `/item` (row 8), `0x037` and category 5 have never run live.

**The crash:** `pol.exe`, fault in `Hook.dll` at `0xc739a`, code `0xc0000409`, on
stable 4.7.9.3 with the client up 27 hours. Windower/Issues#1116 documents that exact
offset as `abort()`'s fast-fail, so the record says only that Hook aborted. Lua runs in
`LuaCore.dll`, not `Hook.dll`. That issue shows the same record from plainly closing
POL with no addons loaded, so it could be the tail of POL exiting for another reason,
though Kevin saw the game freeze for a second and vanish with no error, which reads
more like an abort in the middle of play. The
queue was idle: the last line is a weaponskill finish at 22:11:18 and the `lock over`
due 2.4s later never came. Only a dump can say more, by showing whether `ExitProcess`
is on the stack.

## A run through the checklist (Kevin, 2026-10-31, on `f877c49`)

12 minutes and 32 releases, all started, on a client restarted after the crash.

- **Rows 20 and 23 pass:** 33 presses met an arrow already up and each changed what OK
  cast, a mash of Dia III and a change to Dispel on one arrow among them.
- **Row 21 passes, if those were his macro:** three cursors ended 3.5s, 5.4s and 7s
  after opening, which only a `/ta` token with no arrow up can do, and nothing cast.
- **Row 17 passes:** Cure IV pressed during its own cast at 22:32:06, OK 2s after the
  finish, held and cast with no `on recast`.
- **`interrupted` at 2.7:** 4 of 4 releases started.

Still open: a held ability and a held item, a lock changed in `//hud config`, and rows
9 and 13. Rows 8 and 24 cannot be read from a log and need Kevin's word.

## The in-game checklist (Kevin, 2026-10-31, on `f877c49`)

46 minutes on RDM and BLU, 12 releases, none refused.

- **Row 2:** Composure and Holy Water were each held through a Stoneskin and went at
  +2.72 and +2.74. `out item`, `start item` and `finish item, lock 1.50s` all read
  right, so `0x037` and category 5 work.
- **Rows 8, 21 and 24 pass**, on Kevin's word. Row 21 covers the three short cursors
  of the checklist run.
- **Row 9:** a press held through Warp was released before the zone, and `cleared:
  zone` came during its cast. With the `dropped ...: suppressed` of the first full run,
  both ways out of a zone have been seen. A death has not.
- **Row 13:** a weaponskill refused with 219 (`You cannot see`) took no lock. The next
  one started, then took a category 4 finish, which is how atom0s says an out of range
  weaponskill ends and explains 19:44:41 and 19:48:17 in the first full run. It gets
  the 2.7 lock because a start was running. That costs one held press a moment at
  worst, so it stands.
- **The lock settings work:** one click printed `finish spell, lock 2.80s`, and the long
  labels clear their `[-]` by 1-2px.
- **The ladders fall through:** `hold Silent Oil` and `hold Spectral Jig` on BLU.
- **Rows 10 to 12 on other jobs:** Kevin has none of RNG, COR, SMN or BST, so `/ra`, its
  lock and pet commands stay unverified.
- **Row 26:** still not reproduced.

**The item lock is shorter than 1.5.** After an item's finish a spell at +0.64 started
and an ability at +0.86 went. Sends at +0.32 and +0.59 got no answer, but each came
within 0.3s of a refusal, and the message 18 run shows a send that soon after a refusal
gets none whatever the lock (+6.13, +15.00, +22.71 and +32.65, each under 0.9s after
one), so neither says anything. Held releases at +1.54 all went. It ships at 1.0 (Kevin),
above the two accepted sends rather than at them, and that length has yet to run live.

The ability lock is no better known: three releases at +1.03 went and nothing shorter
was tried. The Provoke mash was refused with 446 for having no valid target.

## A BLU run with a death (Kevin, 2026-10-31, on `f877c49`, before the 1.0 item lock)

33 minutes, mostly BLU, 13 releases, none refused by a lock, and no crash.

- **`ability` looks too long.** Twelve sends +0.23 to +0.38 after Berserk, Warcry,
  Aggressor, Unbridled Learning and Diffusion were all accepted: eight weaponskills,
  three spells and an ability. A thirteenth left 0.07s before the finish arrived and
  started at +0.43. All were GearSwap's, since a bar press in a lock is held. Each
  weaponskill left 1.08 to 1.10 after its ability did, 9 of 9, so that is a timer and
  none of them probes the edge. An ability's finish arrives 0.69 to 1.20 after it
  leaves (28 samples), so a 0.4 lock sends 1.12 after it at the earliest, later than
  any of those. No held press has gone at under +1.03.
- **`interrupted` is a coin toss too.** Refused at +1.22 and +1.67, accepted at +2.01
  and +2.17, where +2.23 was refused in the first full run. 2.7 stays.
- **The first interrupted item:** `interrupted item`, then `refused, message 62`, on
  an item used from the menu. The next one left at +1.82 and started, so 2.7 may be
  long for an item. One sample.
- **Row 9, a death:** `cleared: death` came at 23:45:11, and the next `out` printed
  no `+` figure, so everything was forgotten. What it cleared was a free press on its
  way, so a press HELD through a death is still unseen.
- **The hold rescued a weaponskill.** GearSwap's at 23:38:01 got no answer, and the
  held press went when the 2s ran out and started. That and the one at 23:34:41 had
  no refusal or lock near them, so why they went unanswered is unknown.
- **A send soon after a refusal, counted.** Across all six logs 7 of 24 sends under
  0.9s after a refusal got no answer, against 9 of 1163 after that. The effect is
  real, but "often" overstated it. One here was a bar press at +2.72, 0.29s after a
  refusal of GearSwap's own weaponskill, which stalled that bar for 2s.
- **The TP check:** 522 presses swallowed and 35 dropped at a release. The only
  `nothing went out` was the press after the death.
- A cast ended with `finish spell` and `interrupted spell` in one frame at 23:43:27,
  while Kevin was paralyzed. Both lock 2.7, so nothing turns on it.

## A long RDM run on the 1.0 item lock (Kevin, 2026-11-01, on `ebb8088`)

65 minutes, 57 releases, none refused by a lock, and no crash. `ability` ran at 1.0, so
this is the baseline for trying it at 0.4.

- **The baseline:** five held spells went at +1.02 to +1.04 after an ability and started
  at +1.63 to +1.65. Stymie held behind Saboteur went at +1.02 and finished. Nothing
  was sent under +1.02.
- **`item` at 1.0 is in force and still untested:** `lock 1.00s` printed twice, and
  nothing was sent inside either lock.
- **A weaponskill held across another went, the first to do so.** With TP left, Black
  Halo stayed held through the finish, went at +2.42 and started at +2.86 (00:32:55), so
  the TP check lets one through when it should.
- **A refused item takes a false lock.** A menu item +0.47 after a weaponskill was
  refused with 56, and the packet beside the refusal read as an interrupt, so a 2.7 from
  there replaced the 2.4, 1.62s longer. It stands, as row 13's does: only a menu item
  reaches it, a bar's being held, and it costs one held press a moment. An interrupt
  with no start cannot simply be ignored, since the one at 23:45:04 was a real cast.
- **Two stretches of `nothing went out`,** at 00:23:41 (five, 3.9s to the next send) and
  00:24:05 (six, 5.8s): Black Halo pressed at 1000 TP and no packet left, and GearSwap's
  own weaponskill, which usually goes as TP reaches 1000, did not go either. Then a
  press went and started. No target in reach would fit, a dead mob or a disengage. The
  queue adds at most 0.6s to the first press that can go.
- **Two weaponskills went unanswered** at 00:33:13 and 00:33:15, GearSwap's and the
  press released behind it, then nothing for 22s. The mob dying would fit.
- **A send soon after a refusal,** recounted over seven logs: 8 of 25 under 0.9s got no
  answer, against 12 of 1399 after that.

## A short RDM run (Kevin, 2026-11-01, on `ebb8088`, `ability` still at 1.0)

12 minutes, 49 releases, all answered and none refused by a lock, and no send went
unanswered. Kevin cannot say whether a mob was in reach for the two stretches of
`nothing went out` in the run before, so those stay open.

- **A held press rescued a refused weaponskill (01:24:19).** GearSwap's Black Halo at
  +2.13 was refused with 90, the longest send after a weaponskill refused so far. The
  press held behind it went 0.03s after the refusal and started at +3.40. It dated
  from before the last weaponskill, whose TP had come back by the release.
- **A second death, nothing held.** `cleared: death` came with a free press on its way,
  then four `nothing went out` while Kevin stayed down, TP still reading 1000 or more.
  That is the same shape as those two stretches, so a client that cannot act fits them
  as well as a target out of reach. A press held through a death is still unseen.
- **One slow exchange.** Composure took 1.68s to finish at 01:16:51, the slowest of 43
  abilities, and Haste II held behind it went at +1.02 and started at +2.08 rather than
  +1.65. The next such pair, at 01:21:37, started at +1.64.
- **`item` at 1.0 is still untested.** Eight items, and the soonest send after one was
  +1.72.

## `ability` at 0.4 (Kevin, 2026-11-01, on `ebb8088`, set with `//hud queue lock`)

3 minutes on BLU, with the length set by hand rather than shipped.

- **0.4 passes for spells.** All 9 held spells went at +0.43 to +0.45 after an ability
  and started at +0.68 to +0.91, median +0.82, after eight different abilities. At 1.0
  they started at +1.63 to +1.66 bar one at +2.08, so a spell after an ability starts
  about 0.8s sooner.
- **Going lower looks like no gain.** GearSwap's sends at +0.23 to +0.38 started at +0.87
  to +1.64, median +1.21, later than these. They were mostly weaponskills, so that is a
  hint only.
- **Untested at 0.4:** a held ability or weaponskill. GearSwap's sends cover those from
  below, 8 of 8 weaponskills at +0.23 to +0.36 and one ability at +0.37.
- **The seven message 17s were a mash.** Each was a spell pressed again once its own
  recast was running, which goes out by the rule and is refused. Each lock ran on as
  it was, and no held press was lost to them.
- **`ability` ships at 0.5** (Kevin), on the safe side of what was tested. A stored
  `queue_locks.ability` still overrides it.

## `item` at 1.0 held (Kevin, 2026-11-01, on `ebb8088`)

4 minutes on BLU. No ability was used, so this says nothing about 0.5.

- **Row 29 passes.** All 6 spells held behind an item went at +1.02 to +1.04 and started
  at +1.29 to +1.68.
- **Row 31 is still open.** Both cursors printed `<stpc>`. A `<st>` slot would print
  `cursor ... <st>`, and none of the 600-odd cursors in these logs has been one.
- **Row 30 is dropped.** GearSwap's own sends already put 8 weaponskills and an ability
  behind an ability at +0.23 to +0.37, all accepted, which is shorter than 0.5.
- **Plenilune Embrace went out at 01:03:19 with no `OK` line,** 24s after a cursor that
  then timed out, so it came from outside that cursor: the menu, a macro or GearSwap.
- **One slow cast.** A held Nat. Meditation took 2.96s from start to finish at 01:00:38,
  against a median of 0.44. Of 917 casts across the logs, 362 of them held, the only
  other one that slow was a free Cure IV, so nothing ties it to the hold.

## `ability` at 0.5 (Kevin, 2026-11-01)

17 minutes on RDM, 37 releases, all answered and none refused by a lock.

- **0.5 works.** The one spell held behind an ability, Cure IV after Convert, went at
  +0.53 and started at +0.78. The other two abilities were followed by cursors OK'd
  after the lock had ended, so they held nothing.
- **`item` at 1.0, twice more:** both went at +1.02 and started at +1.66, which makes 8 of
  8.
- **Four Trust summons went unanswered.** Yoran-Oran (UC) at 01:21:03 to 01:21:16, none of
  them held, with no refusal the queue knows, and the same summon worked at 01:24:19.
  The cost is the 2s a press behind one would wait.
- **Row 32 has not been run,** and nothing else testable is left.

## A second RDM run at 0.5 (Kevin, 2026-11-01)

10 minutes, 22 releases, all started, and nothing unanswered. No press was held behind
an ability or an item, so it adds nothing to those two lengths.

- **Newest wins cost a Protect V (01:28:37).** It was held for one Trust when the OK for
  Shell V arrived as the lock ended, so Shell V went and that Trust got no Protect V.
  That is the one-held-press rule working as written.
- **A second `suppressed` drop (01:33:18),** a held Savage Blade, with 20s of nothing
  after it. `cleared: zone` did not print, so that is status 4, a cutscene. The mob ids
  decode to zone 165, the Throne Room. Kevin confirms a mid-fight cutscene.
- **An OK became an item (01:33:38).** `OK Dia III` was followed 0.04s later by `out
  item`, and Dia III went 4s later. Kevin confirms Echo Drops for silence.
- **Cherukiki at 01:26:58** came from the menu, so that refusal was never the queue's.
- **The false lock again (01:33:18).** An item 0.82s before the cutscene read as an
  interrupt with no start, and its 2.7 ran 0.73s past the weaponskill's lock.

## A third RDM run at 0.5 (Kevin, 2026-11-01)

10 minutes, 45 releases, all answered, none refused by a lock. Nothing went unanswered,
and the second cutscene dropped a held Savage Blade at 01:45:57 as the first did.

- **`ability` at 0.5, 2 of 2:** Haste II went at +0.53 and started at +1.21.
- **An arrow survives a bar press.** At 01:44:53 Utsusemi: Ni went out and cast with a
  Cure IV arrow up, and OK then held and released the Cure IV.
- **Kevin is pressing ahead of the one held press,** by his account. Cure IV replaced a
  held Convert at 01:41:38, so it went first and he pressed Convert again.

## Holding a press behind a short recast (Kevin, 2026-11-01)

From a 50-minute RDM run at 0.5, with 118 releases and none refused by a lock. Spells
held behind an ability now stand at 7 of 7, and behind an item at 11 of 11.

**All 16 presses of Cure IV made in its own lock were refused with 17**, 10 of them in
that run. The recast was asked first, so a press on recast went out whatever the lock
was doing, and the lock refused it, though Cure IV has started again from +2.72 every
time. A press is now held when its recast ends inside the lock running, at the press
or at OK. That takes a lock: nothing says when a cast will end, so a press on recast
during a cast goes out as before. The release still asks the recast and drops one still
running, and a longer recast, Utsusemi: Ni or Cocoon, is refused as it was. `recast_left`
answers in seconds now, a spell's coming in sixtieths.

## The recast hold in a client (Kevin, 2026-11-01, on `2e4fb77`)

Row 33 passes. All 10 presses of Cure IV OK'd in its own lock, from +0.34 to +2.10 after
its finish, were held, went at +2.72 to +2.74 and started at +3.18 to +3.31, with no `not
held` and no refusal. One replaced a held Convert, newest wins. Utsusemi: Ni, whose recast
outlasts the lock, was `not held` and refused with 17, 2 of 2, and a third press, past the
lock, sent nothing. The six OKs before those went nowhere because a GearSwap feature of
Kevin's was stopping self-cures, which is the `nothing went out` the 0.6s exists for.

## A long BLU run at 0.5 (Kevin, 2026-11-01, before `2e4fb77`)

1 hour 45 minutes. With the run above, 45 releases, none refused.

- **A cast that never finished stalled the bar (16:08:31).** Tail Slap, after Chain
  Affinity and Efflux, started at 7132.43 and nothing ended it. There was no finish or
  interrupt, no `cleared`, so no death or zone, and no `suppressed`, so no cutscene.
  Nothing left the client for 69s, GearSwap's sends included. Six presses from 7132.86 to
  7143.90 were held, the seventh found no `<t>`, and the last held one was dropped at the
  30s backstop. Tail Slap's casts take under 0.8s, and this is the first such stall in 17
  logs. What ended the cast is unknown. Kevin left the backstop at 30s rather than bound
  it by the cast's own length, and bounded it on 2026-11-06 (below).
- **`ability` at 0.5 is safe rather than tight.** GearSwap put 26 more sends inside it,
  from +0.14 to +0.39, and all were accepted. The one refusal, at +0.13, was Efflux's own
  recast (88).
- **Automated Trust sends at +2.48 to +2.64:** 7 accepted, 6 refused with 17, each of those
  accepted at about +6.15. That is the spell lock's coin toss, and none was a bar press.
- **Four of 321 sends went unanswered,** against a slowest answer of 1.08s. One cost
  something (16:05:36): a Burst Affinity held behind an unanswered Black Halo was replaced
  by Anvil Lightning inside the 2s, so the spell went without it.

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

An eighth round, over the whole feature after the recast hold, came back clean. Two
tests it said could not fail and a line of wording the hold left stale were fixed after
it. Its note that stands: a token that raises no arrow leaves a cursor open, so a
macro's numeric `/ta` could read as ours for up to 30s, which it put at 50% reachable.

A ninth round, over `debug` leaving chat alone, came back clean. Its note that stands:
a failed write to `debug.log` now leaves no trace, chat having been the only other place.

A tenth round, over shipping on, made the seventh round's note on the libraries
blocking: a fresh character on a broken install would have lost every cursor slot, OK
running as a plain `/ta`. The queue now reads as off with no packets coming, whatever
the file says, and `//hud queue` answers with the mode in force. The wiki now says a
cursor slot costs `pretarget`. Its notes that stand: a value that is not a mode reads as
off where other settings read as shipped, kept so a typo cannot hold presses back, and
core's specs seed no `queue`, so they still start from off.

An eleventh round, over shipping on with that fix, came back clean. Its notes that
stand: `//hud queue on` on a broken install answers off with no reason, and shipping on
puts rows 26 and 31 on everyone's path, so row 31 is worth running before a release.

## Measuring in a live client

`//hud queue debug`, then cast back to back and mash an in-game **macro** through
the lock: bar presses are held and so never test the edge, macros are not. Each
action going out prints how long after the last finish it left, and the next
line says whether it started or was refused. The last refusal and the first
start bracket the true lock. Every line is in `debug.log`.

| # | Do | Expect | Why |
| --- | --- | --- | --- |
| 1 | Cure, then a macro repeatedly through the lock | `refused` lines, then `start` | The spell lock, and whether refusals are `0x029` at all (question C of the old retry) |
| 2 | Repeat after a weaponskill, a job ability, an item and `/ra` | The same | Each constant above |
| 3 | Move during a cast, then repeat | `interrupted`, then the bracket | The interrupted constant |
| 4 | Bar press during a cast, `queue on` | One `hold`, one `release`, the spell goes with no chat refusal | The feature |
| 5 | Bar press during the lock, then another | The second replaces the first | Newest wins |
| 6 | Bar press of a spell on its own recast | `not held`, the game's usual refusal | Never held long on a recast |
| 7 | Press a spell during its own cast | `dropped ... on recast` at the release, unless its recast ends within two seconds of the lock (row 34) | Same, from the other end |
| 8 | Hold a `<t>` nuke, tab to another mob | It lands on the first mob | The pin, and that `/ja`, `/ws`, `/ra` and `/item` take a bare id as `/ma` does |
| 9 | Hold, then zone or die | `cleared`, nothing goes | Nothing outlives its moment |
| 10 | Macro casts in `queue on` | Lines only in `debug`, bar presses hold behind them | Packets count whoever sent them |
| 11 | Mash a bar press faster than the ping, then watch for `nothing went out for the last press` on a press that did go | The line never appears on a press that went | Whether 0.6s covers the gap between a press and `outgoing chunk`, which may fire at the client's next send |
| 12 | A pet command and a blood pact | A `sent` that ends on an answer, not the 2s backstop | Which packet answers `/pet` |
| 13 | A weaponskill out of range | Before its start, `ignored a finish with no cast running` and no lock; after its start, `finish weaponskill naming no spell, message 78, lock 2.40s` | atom0s says that failure arrives as category 4. Kevin's 2026-11-10 run had three after a start |
| 14 | During a cast press a `<stpc>` slot, pick a target and press OK inside the lock | `cursor`, `OK ... at <id>`, `hold`, `release`, and the cast lands on who you picked with your target unchanged | The whole of the cursor path |
| 15 | The same, pressing OK after the lock clears | `OK`, then `out` at once, no `hold` | OK while free |
| 16 | Press a `<stpc>` slot during a lock, then ESC | Nothing goes, the next press works | A cursor abandoned |
| 17 | During a cast, a `<stpc>` slot whose recast is up by OK | No `on recast` line, it casts | Judged at OK |
| 18 | Mash a `<t>` slot from before the press lands | One cast, `swallowed` lines, the midcast set stays on | The mash |
| 19 | Precast gear on a cursor slot held through a lock | The spell casts in Fast Cast gear | GearSwap's numeric path runs precast at the release |
| 20 | Double-tap a `<stpc>` slot during a lock, then OK | `cursor up, OK takes ...`, one `OK`, cast at who you picked, target unchanged | FAILED before the fix, as predicted. A second press raised no arrow, OK read as one and the `/ta` ran |
| 22 | Press a `<stpc>` slot while free, let a weaponskill go, press OK in its lock | `hold`, then `release` at the lock's end | The refused Sleep II |
| 23 | Keep the cursor up and press a different cursor slot, then OK | The newer spell casts | The press only changes what OK casts |
| 24 | Press a cursor slot during a macro's own `<st>` cursor and OK it, then press and OK the slot | `swallowed ..., another arrow is up` and no "You cannot perform that action on the selected sub-target", the macro's spell on its OK, then `cursor`, `arrow`, `OK` and the slot's spell, with no "A command error occurred" | An arrow this did not open is left alone, and GearSwap is never sent a token the game refuses (2026-11-10) |
| 21 | ESC a cursor, then run a `/ta <stnpc>` macro | The macro's cursor works, and nothing casts | A closed cursor must not take another's line as its OK |
| 25 | Mash a weaponskill through its own lock, then press a spell as the lock ends | `swallowed ... no TP` or `dropped ... no TP`, no `nothing went out`, and the spell goes at about +2.43 | The TP check |
| 26 | Hold a `<stpc>` arrow on a Trust as your target dies, opening it during a lock. Repeat with `//hud queue off` | Which run leaves you on the Trust | Whether a `/ta` arrow is what strands you |
| 27 | Hold a cursor up past 30s, then OK | It casts at who you picked, target unchanged | A long pre-select |
| 28 | Press a `sneak` slot, then an `invisible` slot inside its cast or lock | `hold Invisible`, `release`, and it casts with no refusal | A ladder slot held |
| 29 | Use an item, then press a bar spell at once | `finish item, lock 1.00s`, `release`, `out` at about +1.02, then `start` | Whether `item` at 1.0 can hold a press |
| 30 | Dropped: an ability or weaponskill held behind an ability | | GearSwap's own sends put 35 there at +0.14 to +0.39, all accepted |
| 31 | Press a `<st>` slot, pick a target, press OK | `cursor`, `arrow`, `OK`, the cast lands on who you picked, target unchanged | Only `<stpc>` and `<stnpc>` have run live |
| 32 | Press a bar spell during a cast, then type `//hud layout` | `dropped ...: //hud layout`, nothing goes | Only `suppressed` has dropped a press for this reason |
| 33 | Press Cure IV again late in its own lock, about +1.8 after its finish | `hold Cure IV`, `release`, and it casts at about +2.72, with no `not held` and no refusal | A short recast inside a lock is held. Passes, 10 of 10 on `2e4fb77` |
| 34 | Cast Shell V on one target, then OK it on the next as soon as the arrow can be raised, several times over | `hold Shell V`, `Shell V waits ...s on its recast` where its recast outlasts the lock, then `release`, and it casts, with no refusal | The recast grace (2026-11-07). At one second it missed Shell V without haste, 11 of 11 ending 1.28 to 1.31s past the lock (2026-11-08); unverified at two |
| 35 | Start a weaponskill on a mob as it moves out of range, then mash a macro through | `finish weaponskill naming no spell, message 78, lock 2.40s`, then `refused` lines, then a `start` | The lock after a too-far. 2.4 is the weaponskill's, unverified there: the 2026-11-10 run brackets it between +1.07 refused and +2.57 accepted |
| 36 | Mash a weaponskill MACRO on a mob that dies while the weaponskill is readying (a bar press is held through the lock and cannot test it) | `the target died, no finish to come, lock 2.40s`, then `refused` lines and a `start`, each with its time after that finish | How long the game locks after a weaponskill its target died under. The line never came on `dd6753a` (2026-11-12, once of once), the death asked of the client's table alone. On `a93e3ec` it came fourteen times and each was early, off that table and under the player's own killing blow; the table is not asked since (2026-11-16). Answered on `b6714b3` (2026-11-17, twice of twice): the game locks. Freed at the death, the next weaponskill went unanswered 0.88s after the one start and was refused 2.45s after the other, and one sent 2.95s after a start was accepted. The weaponskill's lock runs from the death since (2026-11-18), unverified at that length |
| 37 | Mash a weaponskill slot as a mob dies with the next one in reach | `the target died, no answer to come`, then `out weaponskill` and its `start` inside a second | The wait a dead target cost was 2s; whether GearSwap holds the press back itself is unknown. The line never came on `dd6753a` (2026-11-12, nine of nine); the game's death messages are read since. Confirmed on `a93e3ec` (weekend of 2026-11-14): 44 times, and the next weaponskill landed 17 times of the 39 one was pressed. Such a press is swallowed since (row 44). Again on `b6714b3` (2026-11-17): 12 times, none early, and the next weaponskill left 0.19 to 0.48s after the wait ended and started, three of three, so nothing locks there |
| 38 | Press a cursor slot where no arrow can be raised, wait 2s, then run a `/ta <stnpc>` macro and OK it | `no arrow for <name>`, and the macro's cursor works with nothing cast | A cursor that raised no arrow must not take another's OK |
| 39 | Start a ranged attack on a mob that dies before the shot | Whether an interrupt or a finish follows the `start ranged`, or nothing for 30s | Whether a ranged start needs the dead-target rule too (review, 2026-11-12) |
| 40 | With 1000 TP, press a weaponskill slot under Amnesia, and again stunned or asleep | `swallowed <name>, amnesia` (or `stun`, `sleep`), no `out weaponskill`, and no `Abort:` line in chat | That the press no longer reaches GearSwap. Failed on `dd6753a` (2026-11-12): three stuns were never seen, asked of the client's list. The `0x063` is read since, and `(not in the client's list)` after the status says the client's list still lacks it, `(in the client's list, where ipairs does not reach)` that it holds it off its array. Confirmed on `a93e3ec` (weekend of 2026-11-14): 211 swallowed, none through, and neither note was ever written. Again on `b6714b3` (2026-11-17): 114 swallowed, and no `Abort:` for a weaponskill in chat |
| 41 | Mash a weaponskill slot through a lock while the party kills the mob, then stop pressing | `dropped <name>: the target died`, and no `out weaponskill` at the corpse | The held drop, and that the game's death messages reach the client for someone else's kill. Confirmed on `a93e3ec` (weekend of 2026-11-14): an Expiacion dropped, and 859 `fell` lines, others' kills among them |
| 42 | OK a Sleepga's cursor on a mob during a lock, and have the mob die before the lock ends | `dropped Sleepga: the target died`, and the next Sleepga goes at once | The held drop for a spell, and that a monster's id is never under 0x01000000. Seen once on `a93e3ec` (weekend of 2026-11-14), a Dia III, dropped rightly |
| 43 | With the party full, let AutoTrust cast a Trust, and another with enmity held | `refused, system message 298 (param <n>)` for the full party and `300` for the enmity, each right after the `out spell`, and a press held behind it goes at once. `no spell was waiting` after one means it freed nothing. 296 or 297, should either come, reads the same | That these are what the game sends and free the bar, and that 298 and 300 are those two lines, as LandSandBoat's table has them. Not seen on `b6714b3` (2026-11-17): no Trust was refused |
| 44 | Mash a weaponskill slot on a mob as it dies, and keep mashing until the next one is targeted | `swallowed <name>, the target died (<id> fell <n>s ago)` for each press in the three seconds after that mob's `fell` line, no `out weaponskill` at it then, and the first press on the next target goes | The press at a fallen target (2026-11-16), and that nothing alive is taken for one. Confirmed at two seconds on `b6714b3` (2026-11-17): 52 presses swallowed over 11 deaths and no `out weaponskill` at a corpse the game had reported, the ages 0.00 to 1.76s. Three seconds since (2026-11-18): an `out weaponskill` at a corpse later than that, with `the target died, no answer to come` after it, is one the window missed |
| 45 | With Auto Buff Mode on and a buff down, mash a weaponskill slot from its own lock on, and again with Berserk, Warcry or Aggressor ready | `out spell <buff>` and `standing aside for spell <buff>`, `hold` lines through that cast and the first of its lock, then in the lock's last second `not held: <name>, standing aside` and an `out`, each `refused` until one `start`s, and `no longer standing aside: the bar's own went`, with no second `out` of GearSwap's before that start. With a buff ready the first `out` is the buff's, and `out weaponskill` follows it by 1.1s and starts | Standing aside (2026-11-22). That a mash has a press in the last second ahead of GearSwap's next cast, that the press holds that cast back, and that the WS buff's second send lands after the lock. Unverified. Not exercised on `524150f` (2026-11-23): it stood aside 11 times, for items used by hand, Erratic Flutter, Cocoon and Unbridled Learning, each ending at `nothing is busy`, and no press came in a last second. In a Sortie the same night it let its first press go, a Silence OK'd in the last second of the lock after a Fire Kevin cast from the game's menu: refused, and cast again by hand 3s later, with nothing automatic sending |
| 46 | In a crowded fight, when you are left engaged with nothing targeted, press a weaponskill slot before targeting anything | `no target for <name>, status 1` (or `target <id> fell <n>s ago for <name>, status 1`) for each press until a target is back, under the `fell` of the mob you were on, and either no `auto-target` after that `fell` or an `auto-target <id>` whose `<id>` then `fell`; no `status 0` in between | The status and target lines (2026-11-23). Whether the client still reads engaged, whether `<t>` is empty or on a corpse, and whether the game auto-targeted. A `status 0` there means the client was told it disengaged. Seen on `524150f` (2026-11-23, Walk of Echoes): the lines are written, 47 `auto-target` to the chat log's 47. Of 70 deaths of his target 20 went to `status 0` instead, a median 0.87s on, and three kept status 1 with no `auto-target`, each the death of a mob an `auto-target` had named 1.6 to 6.7s before; one press among them read `no target for Savage Blade, status 1`. Whether the server had a target for him then is open |
| 47 | In a crowded fight, let the party kill the mob the game has just auto-targeted for you, and when no target comes back switch to one by hand as you usually do | Under that mob's `fell`, with no `auto-target` after it: either a `swing at <id>, <t> none` (or `out of range of`, `unable to see`) with no `out engage` or `out switch target` before it, or an `out switch target <id>` ahead of the first `swing at`; and a `server target <id>` after every `auto-target` | Who moved the target (2026-11-23). A swing with `<t> none` and no targeting packet of yours before it is the server moving you untold; your own packet first is you. Also when the game sends a `0x058`: with each auto-target, and in answer to your own switch or not. Unverified |

## The finish backstop, bounded (Kevin, 2026-11-06)

A laggy event's log showed seven starts whose finish never arrived, each holding every
bar press for 11 to 30s (four ran the full 30s backstop, three were freed by a macro).
A start now keeps the bar busy for its spell's resource `cast_time` plus one 0.4s server
beat (Fast Cast only shortens the cast), 3s for a weaponskill, an item's `cast_time` plus
1s, and the old 30s for a ranged attack or anything the resources cannot name. That
end is taken for the lost finish: it starts the kind's lock, since the server locked
from the real finish, and a press held through both is then sent, not dropped. A
finish arriving later is still read as one, so it still locks, for the full 30s -
a spell finish only if it names the spell the start named (2026-11-07).
The weaponskill and item figures are
unverified, and so is the items resource's `cast_time` and that a category 9 start
names its item in `targets[1].actions[1].param`.

## A lost start, answered by its finish (Kevin, 2026-11-06)

The same log lost seven spell STARTS whose finishes arrived (messages 230, 75, 236,
236, 236, 230, 7), 1.2 to 2.4s after each spell went out. Each finish was ignored as
the paralysis kind, so nothing locked, and the next send went into the server's lock:
Refresh III at 20:07:18 was refused with 17, a Cure IV at 6764.73 went unanswered, and
a Refresh III at 5692 never left. Both of the run's other ignored finishes carried
message 0 and followed no send. Now a spell that goes out, from anything, waits for an
answer for its `cast_time` plus 0.4s where that is longer than 2s, and a spell finish
inside that wait is the spell's own and locks. A refusal still ends the wait at once,
and a finish after a non-spell send (row 13) is still ignored. Losing both the start
and the finish leaves the bar free once the wait runs out, and the next send can be
refused: one re-press, which Kevin accepted. The cost: a spell the server drops
without an answer (4 of 321 sends in the BLU run) holds the bar for its cast time
plus 0.4s rather than 2s.

Done 2026-11-07 (Kevin): a finish answers the wait only when its `param` names the
spell that went out. His log at 20:07:58 had a Cure IV go out while paralyzed and a
finish arrive 0.49s later, ahead of its start, which locked; the real finish came 0.8s
after and replaced it. A send with no spell id (param 0) waits as before but takes no
finish as its own. The same day, the same rule for a start whose wait has locked: the
bar is idle by then, so a spell finish inside the rest of the 30s counts only if it
names the spell the start named. While the cast runs, or when the start named no id,
any spell finish still counts, except one naming no spell (param 0): that is a
paralysis round, and inside a cast it would start the lock early and close the window
on the real finish (Kevin, 2026-11-08). The debug line says which case ignored a
finish: `with no cast running`, `naming no spell` or `naming another spell`.

## The recast grace (Kevin, 2026-11-07)

Done 2026-11-07 (Kevin): a press whose own recast ends within a second after the lock
is held, and its release waits for the recast (`RECAST_GRACE`). Shell V cast on target
after target ended its recast just past each lock, and the press at 40043.44, sent at
+2.45 on a recast that outlasted 0.27s of lock, was refused with 17; a re-press 2.2s
later started. A held press whose recast is still more than a second off when the lock
clears is dropped as before, and a press on recast with nothing busy goes out as before.
A cast still running counts as no lock at all, so a press on a recast under a second is
held through it. Review found the wait read as idle, so a mash of the slot went out
beside it and could be accepted, the held press then going into the cast: the wait
counts as busy for a press (Kevin, 2026-11-08), so a newer one replaces it as in a
lock, and one on a recast more than a second off still goes out. **Unverified in a
live client.**

Raised to two seconds 2026-11-08 (Kevin). The `not held` and `dropped ... on recast`
lines now say the recast and lock left. Shell V without haste, OK'd on target after
target, ran its recast 1.28 to 1.31s past the lock eleven times of eleven, so every
press was sent and refused with 17 at one second. Two covers that with 0.7s over for
other gear; the margin moves with fast cast and haste, which cut cast and recast
differently.

## A weaponskill's too-far, and its lost finish (Kevin, 2026-11-10)

Done 2026-11-10 (Kevin), after a run that held weaponskill presses about 5.4s:

- **A weaponskill that started and could not land** is answered with a spell finish
  naming no spell (category 4, param 0, message 78, too far) 0.02 to 0.44s after its
  start. The 2026-11-08 rule read it as a paralysis round, so the start waited out its
  3s and locked 2.4s on top, three times in the run. While a weaponskill's start runs,
  such a finish now ends it and locks as its finish would. Its own finish is a
  category 3, never ignored, and replaces that lock if it comes after all. The run
  brackets the real lock after a too-far: a Cocoon sent +1.07 after one was refused
  (17), an Unbridled Learning sent +2.57 after another was accepted. A run on
  2026-11-11 narrowed it: GearSwap's Nat. Meditation, sent +2.03 after a too-far, was
  refused (17). The 2.4 it takes is unverified there (row 35). Any finish naming no spell ends the start, a
  paralysis round's too: either it was the weaponskill's own end, or the category 3
  finish that follows replaces the lock. Should that finish be lost as well, the lock
  starts up to 1.2s early and a held press can be refused: one re-press, and rare.
- **A weaponskill's lost finish** now waits 1.2s, three of the server's 0.4s beats,
  not 3: about 80 weaponskills in the run each finished within 0.89s of starting, and
  one whose finish never came (its mob died under it) held the bar 5.4s. A late
  finish still replaces the lock.

## A press under another's arrow (Kevin, 2026-11-10)

Done 2026-11-11 (Kevin), after Dia III would not go in Al Zahbi:

- At 23:14:08 a cursor slot was pressed under an arrow the queue had not opened. It
  went out as typed, as row 24 had it, and the game refused it ("You cannot perform
  that action on the selected sub-target"), which wrote no queue line. GearSwap had
  set its `st_flag` for the token, and with the line refused no number came to clear
  it. At 23:14:10 the next press opened its cursor as usual, and its OK went out as
  `/ma "Dia III" 16974022`, which GearSwap passed to the game as typed, clearing the
  flag: "A command error occurred", then `nothing went out for the last press`. The
  press after that cast.
- Under an arrow it did not open a press now sends nothing, says
  `swallowed <name>, another arrow is up` in `debug`, and leaves that arrow's OK to
  whoever opened it. It could do nothing there anyway: the token raises no arrow
  while one is up.
- Not covered (review, 2026-11-11): suppression and the config modes are checked
  first, and there the queue leaves the press alone, so a cursor press under any arrow goes as
  typed. Covering them means deciding what a press under the queue's own arrow does
  while it holds nothing.
- Unverified: that GearSwap's flag is what broke the OK. It is read off GearSwap's
  source (`flow.lua` sets it in pretarget for an `<st>` token, `triggers.lua` clears it
  on the next outgoing text and passes that line through) and the log. Row 24.

## A weaponskill whose target dies (Kevin, 2026-11-11)

Done 2026-11-12 (Kevin: "Fix both cases"), after a BLU run on `a947c86` where a
weaponskill's target died under it thirteen times:

- **Sent as the mob died**, ten times. The server answers nothing, and the bar sat out
  its 2s each time; four of those delayed the next weaponskill by 1.4 to 2s, and the
  rest had nothing in reach. A weaponskill that left for a target the client now shows
  dead - no HP, or status 2 or 3 - is no longer waited on. Nothing started, so nothing
  locks. This is the likely cause of the weaponskills left unanswered in the runs of
  2026-11-01 above.
- **Started, then the mob died**, three times, and once more in an RDM run that night.
  No finish comes and the TP is kept; the bar waited 1.2s and then locked 2.4s. The
  start now ends at the death with no lock. **Unverified: that the game locks nothing
  there** (row 36). Should it, what goes out at the death is refused, and the refusals
  bracket the real lock. It does lock (the run on `b6714b3`, below), and the start
  locks as its finish would since 2026-11-18.
- Weaponskills alone. A Raise is aimed at a corpse, and a cast cut short has its
  interrupt.
- A target the client no longer has reads as alive: by then the wait is over anyway.
- Unknown: whether GearSwap holds back a press sent that soon after a weaponskill of
  its own (row 37).
- A death the client shows only after the 1.2s a start is waited on lifts nothing: the
  lock the lost finish was given stands (review, 2026-11-12). A lost finish followed by
  a kill looks the same, so row 36 decides whether it should. It should: the game
  locks after a start its target died under (2026-11-17).
- A weaponskill HELD while its target lived is pinned to that mob, so at the death it
  was released at the corpse - GearSwap's precast ran and nothing answered (review,
  2026-11-12). Kevin, 2026-11-12: "yes. Drop a held weaponskill when its pinned target
  has died". Done, below.
- Unverified: that the client never shows 0% for a mob still alive. Dead is `hpp` 0 or
  status 2 or 3, the focus target's own test; were a sliver of HP rounded down, the wait
  would end early and a held press go out into the weaponskill (review, 2026-11-12).
  The live runs below say the opposite failure is the real one: the table showed no
  death in time, ten times of ten. The same reading drops a held weaponskill or spell
  now, so a living mob shown at 0% would lose every press held for it.

## A cursor that raised no arrow (review, 2026-11-11)

Done 2026-11-12. A cursor slot's token can raise no arrow at all: the game refuses it
with the chat log open, for one. The cursor was kept for its 30s all the same, with no
number counted, so the next `/ta` cursor anyone opened had its arrow taken for this
one's and its OK for this one's OK: the line was blocked and the stale spell cast at
that target. Two reviewers found it by reading; no run has shown it.

- A cursor that has counted no number 2s after it opened, with no arrow up, is given
  up, saying `no arrow for <name>` in `debug`. The arrow's number comes back within a
  frame or two of the token in every run so far.
- It is timed, not counted off a second token as the reviewers proposed: another addon
  that blocks and re-sends `/ta` lines would put this cursor's own token through twice.
- Inside those 2s the hole is still open: another cursor's arrow number is counted as
  this one's, and its OK is then taken (review, 2026-11-12).
- A client that stalls more than 2s between the token and its arrow's number has a live
  cursor given up, and its OK would then move the target and cast nothing (review,
  2026-11-12). No run has shown a number that late.
- Row 38.

## A weaponskill you cannot use (Kevin, 2026-11-12)

Done 2026-11-12, after an Ambuscade run where every weaponskill pressed under Amnesia
drew GearSwap's `Abort: You have Amnesia.` in chat. Kevin: "silently drop WS presses
where I don't have TP, Amnesia, or am stunned. The same conditions as what selindrile's
gearswap aborts on. Do not drop based on range".

- The conditions are read off Kevin's GearSwap (`libs/Sel-Include.lua` `filter_precast`,
  `libs/Sel-Utility.lua` `check_disable` and `check_amnesia`, `libs/Sel-Mappings.lua`
  `disable_list`): terror, sleep, Lullaby, stun, Animated, Charm, petrification; 0 HP; a
  status that is neither Idle nor Engaged; amnesia; impairment. The TP test is his own
  `user_filter_precast`, and the queue already had it.
- The ids are Windower's buffs resource's for those names: sleep 2 and 19, petrification
  7, stun 10, charm 14 and 17, amnesia 16, terror 28, Lullaby 193, impairment 261,
  animated 633.
- It rides the TP rule: judged at the press, at a cursor's OK and at the release, a
  press that shows nothing, and only while the queue is on. `debug` names what stopped
  it.
- Weaponskills alone, as asked. An ability under Amnesia, and a spell or an ability
  while stunned, still reach GearSwap and draw its `Abort:` line.
- No range test (Kevin): the weaponskill gate removed on 2026-10-16 had one, and it
  misjudged some monsters' hitboxes. Selindrile's precast filters have none on a
  weaponskill either: only his AutoWS and his `smartws` command judge range.
- Not his `check_doom`, which sends a Cursna or a Holy Water in the press's place, nor
  his `just_acted`, which is his MiniQueue.
- Row 40.

## The first live runs of `dd6753a` (Kevin, 2026-11-12)

Two runs in `debug`, each with its chat log: an hour of Dynamis [D] on RDM with Trusts,
then 27 minutes of Sheol C on BLU in a party.

**What held.** About 115 weaponskills on RDM and over a hundred on BLU, each `out`,
`start`, `finish`; the TP rule swallowed several hundred mashed presses and drew no
chat line.
`cleared: death`, `dropped ...: suppressed` at the zone and the cursor lines read as
designed. Nobody was under Amnesia, petrified, charmed or terrorized, no cursor raised
no arrow, and nothing ranged was fired, so rows 38 and 39 saw nothing.

**What `dd6753a` added and never fired.**

- **The statuses** (row 40). Three stuns - Seismostomp at 20:07:59, Aerial Wheel at
  20:32:52, Tail Slap at 21:29:47 - and through each, presses with the TP for a
  weaponskill went on to GearSwap: fifteen in all, not one `swallowed ..., stun`. Under
  the third GearSwap printed `Abort: You are stunned.` eight times. (Under the first two
  its `just_acted` cancelled the presses first and in silence, since the weaponskill
  sent as the stun landed was never answered and stayed its `prepared_action`.) One
  press as a sleep wore off drew `Abort: You are asleep.` the same way.
  - GearSwap's `player.buffs` is the `0x063` order 9 and nothing else
    (`packet_parsing.lua`; its `0x037` read is commented out). The queue asked the
    client's `get_player().buffs`, through `lib/player`, with `ipairs`.
  - So the queue reads that packet too now, off the entry point's one parse of it (its
    fourth reader), and the client's list only until one has come - after a `//lua
    reload` until the next buff change, and after a zone, a death, a job change or a
    logout until the next one. Why the client's
    list failed is NOT known: it may lack the status, or not be a plain array. It is
    read with `pairs` now, over its numeric keys alone so that a count is no status, and
    `debug` says how the client's list holds the status the packet named: `(not in the
    client's list)`, `(in the client's list, where ipairs does not reach)`, or nothing
    where an array walk finds it. Everything else in the addon that reads that list with
    `ipairs` (the status bar, the context layers, the mounted check, the stealth ladders'
    silence test) is open to the same question until a log answers it: the second note
    is the one that would implicate them. The status bar shows the same thing sooner -
    a stun with no icon on it is a list that lacks the status.
  - GearSwap skips the blank order-9 `0x063` that follows a zone (a flag set on `0x00A`,
    `packet_parsing.lua`). The queue takes it, so until the real one comes it sees no
    status; that can only let a press through (review, 2026-11-12).
- **The dead target** (rows 36 and 37). Nine weaponskills left for a mob the party
  killed that moment and each waited out its 2s; one had started, and sat 1.2s and
  then a 2.4s lock. `the target died` was never written, the death asked of the
  client's mob table alone (`hpp` 0, or status 2 or 3). What that table showed is not
  known.
  - The game's own word is read now: a `0x029` whose message is one of 6, 20, 113,
    406, 605, 646 (the Debuffed addon's `Unit died` list, checked against Windower's
    action messages), its target at 0x08. A death is remembered 30s - as long as a
    press is held - or until that id acts again, and forgotten on a clear. A cast cut
    short is no act: dying cuts one short, and whether that packet comes before the
    death or after is not known. The table is still asked beside it.
  - The remembered death outranks a table that shows the mob alive, so one back up
    under the same id inside 30s - a reraise, a respawn - reads as dead until it acts:
    a weaponskill at it is not waited on, and a press held for it is dropped (review,
    2026-11-12; left as it is, the table having shown no death in time either).
  - `debug` writes `fell <id>, message <n>` for each death and `no answer to the last
    send, a weaponskill at <id>` when one is waited out, so the next log can say
    whether the deaths came, and for which ids, if the rule is silent again.
  - A Trust called again takes a new id - 17983489, then 17983493, then 17983497 for
    Valaineral in the RDM run - so a death should not outlive its id onto the next
    one (review, 2026-11-12, asked).
  - Kevin's game filters must be off for those to reach the client, as they are for
    his damage parse. Unverified (row 41).

**Held presses at a corpse** (Kevin, 2026-11-12: yes to the weaponskill, and "Yes,
monsters only" to a spell). A held Expiacion pinned at 21:42:34 went out at 21:42:35 at
a Rarab killed in between, unanswered. On RDM a Sleepga OK'd at 20:20:52 on a statue
whose death blow had landed was held 1.2s, released at the corpse and never answered;
the Sleepga OK'd on the pack meanwhile waited that out, was then cancelled in silence
by GearSwap (the first still its `prepared_action`), and went on a third press, 4.0s
after its OK.

- At the release, a held weaponskill whose pinned target is dead is dropped, and a held
  spell whose pinned target is a dead monster: `dropped <name>: the target died`.
- A monster is an id from 0x01000000 up. A player's is below it, so a held Raise goes.
- An ability, an item and a ranged attack are released as before.
- The id rides the pin: `pinned_command` answers it beside the command, and a cursor's
  OK carries its own.
- Not done: a spell SENT as its target dies is still waited on for its cast time plus
  0.4s - Sleepga 3.4s, three times in the RDM run. GearSwap keeps such a spell as its
  `prepared_action` for 3.4s or more and cancels the same spell sent again, so an
  earlier release of the bar would buy little.
- Rows 41 and 42.

**Trust casts the server refuses** (Kevin, 2026-11-12: "Yes, log them"). AutoTrust cast
a Trust eleven times with the party full or enmity held. The game answered "You have
called forth your maximum number of alter egos" or "You cannot use Trust magic while
having gained enmity", the queue saw no refusal for either, and ten of them held the
bar 2.4s: a Silence went 2.08s late and Utsusemi went up first, two Dia III went 1.84s
and 1.30s late and were pressed again, and a Stun pressed at 20:35:00 was never cast.

- Neither line is in Windower's action messages, so they are taken to be `0x053`
  system messages. Unverified here, but GearSwap agrees for one of them: its own
  `parse.i[0x053]` takes messages 298-301 (0x12A-0x12D) for a Trust cast refused - by
  its comment a caster neither solo nor the party leader, a full party, an alter ego
  already out - and runs aftercast on its newest command (review, 2026-11-12).
- LandSandBoat's system message table names them (`scripts/enum/msg.lua`, `base`
  branch, read 2026-11-12): 296 seeking a party, 297 "While inviting a party member,
  you must wait a while", 298 "You have called forth your maximum number of alter
  egos", 299 already called, 300 "You cannot use Trust magic while having gained
  enmity", 301 neither solo nor the party leader. So BOTH lines of that run are among
  GearSwap's four, whatever its comment leaves out. 296 and 297 are not GearSwap's.
- `debug` names a `0x053` that comes while a send is unanswered, id and parameter.
  Row 43.
- Kevin, 2026-11-12, on GearSwap's four: "Yes, add them". A `0x053` 298-301 ends the
  wait for whatever spell went out and is unanswered, and `debug` writes `refused,
  system message <id> (param <n>)`. A spell's wait alone: one arriving late frees
  neither a weaponskill's wait nor a press that has not left the client, and `debug`
  then adds `no spell was waiting`. Nothing locks, no cast having happened.
- Kevin, 2026-11-13, of the two GearSwap does not take: "Add 296 and 297 first". All
  six of LandSandBoat's are refusals now, the first two on that table alone.
- It does not ask whether that spell IS a Trust: another spell sent before the refusal
  came would have its wait ended instead, and a press held behind it would go out into
  its cast. GearSwap blocks a second command while the first is unanswered, so it
  would take a macro sent past it; left as it is (review, 2026-11-12).
- Not known: whether the game ever refuses at the END of a Trust's cast, the party
  having filled meanwhile. That refusal would come after the start, with no send
  waiting, and free nothing - the start would run to its backstop and lock 2.7s. The
  log would show `no spell was waiting` (review, 2026-11-12).
- A `0x029` the queue does not know for a refusal was dropped in silence, so those two
  logs cannot say none came. `debug` names one of your own that comes while a send is
  unanswered too (`unlisted message <id>`), whichever packet it turns out to be.

**Seen, and left alone.**

- A second "You cannot see" inside about 1.4s of the first is not seen by the queue at
  all: 20:42:05 and 21:29:13, each chat line with no `refused` beside it, and the send
  then waited out its 2s. One 1.6s after the first is seen (twice). The handler drops
  nothing, so the packet never reached the addon. My guess, at 70%: the two chunks are
  byte for byte the same, and Windower takes the second for the first one's resend.
- 20:07:54, `not held: Sleepga on recast 1.52s, lock 0.00s`: an OK with nothing busy
  goes out on its recast, and GearSwap printed `Abort: [Sleepga] waiting on recast.`
- A spell pressed while resting drew `Abort: You can't act while your status is:
  Resting.` (20:43:19). Weaponskills alone are judged, as asked.
- Three times a slot was mashed that opened Blind's cursor - 13, 3 and 30 presses -
  each just before Sanguine Blade went out (20:28:59, 20:31:14, 20:41:55). Whether that
  was the wrong slot under the thumb or the bar resolving the wrong one is Kevin's to
  say.

## A third run of `dd6753a` (Kevin, 2026-11-12, 21:53 to 23:02)

RDM in Sortie with a party of six and no Trusts, so nothing here speaks to row 43.
Still `dd6753a`: none of the fixes above were in it.

- **Amnesia** (row 40). Triboulex's at 22:59:51. The weaponskill already out was
  refused (191, 90); one more left 0.09s later, before GearSwap knew of it either, and
  was never answered (2.02s); the next four presses went on to GearSwap and each drew
  `Abort: You have Amnesia.` So the client's list failed for amnesia as it had for
  stun: it is not one status.
- **Stuns.** Two, and each caught a held Dia III at its release rather than a
  weaponskill: `Abort: You are stunned.` at 22:33:57 and 22:58:57, each pressed again.
  A Dia III sent as a third stun landed (22:59:00) was never answered, 2.4s. Spells
  are not judged, as asked.
- **Dead targets** (row 36). Two weaponskills left as the mob died - 22:47:12, Kevin's
  own melee kill, and 22:51:08 - and each waited out its 2s, `the target died` never
  written. The first printed "Vanar defeats the Abject Obdella", so its `0x029` came.
- **Whose kills print.** Kevin's own print a "defeats" line and nobody else's does,
  and no party member's attack prints at all. If that is Battlemod's filter the death
  messages still reach the addon; if it is the game's, row 41 fails for a kill that is
  not his. The `fell` lines will say.
- **The locks held.** Over fifty held spells were released at +2.72 to +2.74 and every
  one started, two of them after an interrupt; a held weaponskill released at +2.45
  and one sent at +2.42 both started.
- **A recast with nothing busy**, five times: three drew GearSwap's `waiting on
  recast` (0.83s to 1.13s left) and were pressed again, two went (0.80s and 0.03s).
- **Two slots inside three frames** (22:41:27): Frazzle III's cursor, then 0.05s later
  a Dispel press that took its OK. The same question as Blind above.
- A weaponskill sent with the TP for it was refused "not enough TP" (192) once,
  22:24:39, a monster's move landing in between. Nothing to do.

## A weekend on `a93e3ec` (Kevin, 2026-11-14 and 2026-11-15)

One `debug.log` holding three sessions, told apart by the clock starting over, with the
chat logs beside it. The first (2026-11-13 20:00 to 02:31) was NOT `a93e3ec`: it writes
the bare `no answer` after a weaponskill, no `fell` line and no status swallow, and 36
presses under a status went on to GearSwap. The other two (2026-11-14 17:56 to 00:37 and
2026-11-15 15:01 to 21:40) were, and everything below is theirs.

**What held.**

- **The statuses** (row 40). 211 weaponskill presses swallowed - amnesia 174 over ten
  episodes, stun 24 over three, sleep 10, terror 3 - and none reached GearSwap. The
  client's list agreed with the packet every time: neither note was ever written. So
  that list most likely never failed (my reading, at 80%): the runs of 2026-11-12 that
  showed it failing were probably on the build before `dd6753a`, as this weekend's
  first session was.
- **The locks.** 715 held presses released and none refused by a lock; seven were
  refused for range or line of sight. A macro after a weaponskill was refused at +2.17
  and accepted at +2.33; after a spell, refused up to +2.58.
- **The death messages** (row 41). 859 `fell` lines, message 6 for 849 of them and 20
  for ten, other players' kills among them.
- **Held presses at a corpse** (rows 41 and 42). Two, an Expiacion and a Dia III, each
  dropped rightly.

**What the mob table got wrong.** 65 waits ended on a dead target. 44 were real: a
weaponskill sent at a mob whose death message had already come, the wait ending a
median 0.02s after the send. 21 were early: the client's table showed the mob dead 0.33
to 0.5s before the start or the finish of the player's OWN killing weaponskill arrived,
no death message having come yet, and the bar read free in mid-weaponskill. All
fourteen `no finish to come` were among them. No press is seen going out into one.
Kevin, 2026-11-16: "Yes, fix both".

- The table is not asked any more. A death is the `0x029` alone, which came for every
  one of the 44. The service's `dead` dep is gone, and the `get_mob_by_id` the entry
  point handed it for that.
- Row 36 is therefore still open: no weaponskill has been seen to start and then lose
  its target to someone else's blow.
- The remembered death has no table left to outrank (the review note of 2026-11-12
  above): a mob back up under the same id reads as dead until it acts, or 30s.

**Weaponskills sent at a corpse.** After those 44 the next press went out and landed 17
times, went out at a corpse again 11 times, was cancelled by GearSwap nine times (the
one before it still its `prepared_action`), was refused once and was another kind of
send once; five times nothing was pressed.

- A weaponskill pressed within two seconds of the game saying its target fell goes
  nowhere now, at the press, free or busy, and at a cursor's OK: `swallowed <name>, the
  target died (<id> fell <n>s ago)` in `debug`, nothing in chat. Weaponskills alone. A
  press nothing can pin (`<ft>`, `<pN>`) goes as before, and so does a slot bound with
  no target, the binder's default: nothing names who it is aimed at, so neither this
  rule nor the held drop can judge it (review, 2026-11-16).
- **It stops about 13 of the 44, not all of them** (measured after the review,
  2026-11-16). Set against the newest `fell` line before each: 17 left BEFORE the
  message came, and their wait ends when it does; 27 left at or after it, every one
  within 0.48s. A press takes 0.01 to 0.04s to leave as a packet (1,160 releases, mean
  0.019s), so the 14 that left within 0.04s were pressed before the message or in its
  frame, and the 13 from 0.05s to 0.48s after it are the ones a rule at the press can
  see. Nobody mashed at a corpse for longer than half a second. (Wrong as a ceiling:
  the presses after the first that went out were hidden behind it. The run on
  `b6714b3`, below, shows them to 1.76s.)
- The target is the pin's, so the pin is asked at every press that names a target,
  where it was asked only at a hold.
- **Two seconds, not the 30 a death is remembered for** (review, 2026-11-16; Kevin:
  "Yes, 2 seconds"). On the 30s memory, a mob back up under the id that fell and not
  yet acting - an NM popped again at once, a mob that reraises - would take no
  weaponskill from the bar until it acted, a press that silently does nothing where a
  death wrongly remembered used to cost a wait ended early or a held press. No id fell
  twice inside 30s in these logs; nine did inside two minutes, the nearest two deaths
  of one id 42.7s apart, so a respawn inside 30s is not ruled out. Two seconds is four
  times the latest press seen at a corpse. (Three seconds since 2026-11-18, below.)
- From two seconds on the press goes as it always did, and the wait for it ends at once
  if the mob is still a corpse. Held instead, it is dropped at the release while the
  death is remembered: the wait and the held drop keep the 30s.
- The line's id and age are there to show a swallow at a mob that is up, and how long
  after a death presses come. Row 44.
- With the table gone a death the game sends no message for is never seen. Whether a
  chat filter on other players' battle messages withholds one is unverified; Kevin's
  are off (review, 2026-11-16).

**Seen, and left alone.**

- A spell SENT as its target dies still waits its cast time plus 0.4s: Thunder V, Fire
  V and Blizzard V 7.9s each, Silence 3.4s. Kevin's call, not asked for.
- 21 Stonega and Diaga from a macro, sent inside a lock, were never answered: the
  server dropped them with no refusal.
- Row 43 saw nothing. The one Trust refused was for enmity gained in mid-cast, which
  came as a start and then `interrupted spell`.
- Unlisted `0x029` messages 4, 5, 204, 206 and 234 came with a send unanswered. None is
  a refusal.
- 71 lines of `Abort: You have Amnesia.` inside three seconds (2026-11-14 21:05:52),
  the framerate near zero. Not the bar's: the queue had swallowed all 29 Expiacion
  presses of that episode and logged no press through the burst, which began as Mighty
  Guard wore off and ended in `out ability Unbridled Learning` and `out ability
  Diffusion`. GearSwap's own BLU auto-buff chain (`Vanar_Blu_Gear.lua`), at 85%.

## A run on `b6714b3` (Kevin, 2026-11-17)

One session, 21:17 to 00:22, with the chat logs beside it.

**What held.**

- **Deaths by the message alone.** 14 waits ended on a dead target and none early (21
  of 65 on `a93e3ec`): each weaponskill had left 0.30 to 1.32s before its target's
  `fell` line. 227 `fell` lines.
- **The press at a corpse** (row 44). 52 presses swallowed over 11 deaths, Expiacion
  nine times and Savage Blade twice, and no weaponskill went out at a corpse the game
  had reported.
- **The statuses** (row 40). 114 presses swallowed - amnesia 101 over two episodes,
  stun 13 over two - and no `Abort:` for a weaponskill in chat. Five `Abort:` lines all
  night: three recasts, an Unbridled Learning not active, and `You are stunned.` for a
  held Distract III released into a stun, a spell not being judged.
- **The locks.** 156 held presses released: 149 started, one was refused for range
  (message 78), GearSwap cancelled four, and two went unanswered, a Provoke and a
  Distract III under a stun. None was refused by a lock. The earliest send accepted
  came +2.32 after a weaponskill, +2.40 after a spell and +2.72 after an interrupt.
- Row 43 saw nothing: no Trust was refused.

**A weaponskill that started and lost its target** (row 36). Twice, and the bar was
freed at the death both times, as it then did:

- 21:27:03. `fell` 0.76s after the start. The held Expiacion, pinned to that mob, was
  dropped; the next, at another mob, left 0.88s after the start and was never answered
  (2.01s), and one sent at 2.95s started.
- 21:38:13. `fell` (message 20) 0.44s after the start. The next weaponskill left at
  2.45s and was refused, message 90, "Unable to use weapon skill."; one at 3.11s
  started. The server was slow: that refusal took 0.53s to come and that start 1.62s.
- So the game locks there, until somewhere between 2.45 and 2.95s after the start. An
  ordinary weaponskill's finish follows its start by 0.44s at the median (233 of them:
  p90 0.46, max 0.89, and 0.01 where lag bunched the two), and its 2.4s then ends at
  2.84.
- Kevin, 2026-11-18: "Yes, both". The death is taken for the finish: the weaponskill's
  lock as set, from the death message or from 0.4s after the start, whichever is
  later. `the target died, no finish to come, lock 2.40s`. On those two it would have
  ended 3.16 and 2.84s after the start.
- The death message can trail the finish that never came, so the lock can run long by
  that much, 0.32s on the first. Whether it can run SHORT is unverified: 0.4s is the
  server's beat, under the 0.44s the client sees, and the second sample's lock ends
  inside its own bracket (refused at 2.45s, accepted at 3.11s, the lock to 2.84s).
  Anchored 0.44s after the start alone it would fit both samples and be tighter. Not
  done on two samples (my call, open): a release into a lock loses the press, and a
  bar press is held through the lock, so only a macro tests it.
- A start that comes after its target's death was already reported - the wait for the
  answer ended at the death - locks the same way, from 0.4s after that start. It ended
  with no lock before.
- `debug`'s time after the finish is signed now: a send ahead of a finish a death was
  taken for reads `-0.20s after finish`.
- A third start had no finish and no death inside its 1.2s (21:38:09; a `fell` came
  3.40s after it). It locked off the lost finish, as before, and the release 3.63s
  after the start was accepted.

**Sent as the target died locks nothing** (row 37). Twelve times; where a weaponskill
followed inside half a second - 0.19, 0.43 and 0.48s after the wait ended - it started,
three of three.

**The corpse window, three seconds** (Kevin, 2026-11-18: "Yes, both").

- Two seconds caught all 52, the latest 1.76s after the death: median 0.52s, nine past
  a second, two past 1.5s.
- The half second measured on `a93e3ec` was no ceiling. There the first press after a
  death went OUT at the corpse and the rest hid behind it, `already going` or
  cancelled by GearSwap; swallowed, every press shows.
- The longest (21:36:40, 11 presses) was at the last mob of a pull, where nothing moves
  the target off the corpse, and it ended when Kevin stopped pressing.
- Three is a tenth of the memory, and the nearest two deaths of one id are still the
  weekend's 42.7s.

**Seen, and left alone.**

- Spells under a stun (23:47:23 to 23:47:38): a Distract III took five tries over 15s.
  Two sends went unanswered 3.41s each, GearSwap aborted one release, and one never
  left. Spells are not judged under a status, by decision.
- GearSwap's own ability-then-weaponskill sent an Expiacion 0.02s after its Aggressor
  finished (21:18:38). The server dropped it unanswered (2.02s), and GearSwap cancelled
  the held press released behind it. Its other sends that soon after an ability were
  accepted.
- 47 unlisted `0x029` messages with a send unanswered: 4, 5, 204 and 206 again. None is
  a refusal.
- Two cursors were given up after their 30s (`no OK for` Dia III and Haste II).

## Standing aside (Kevin, 2026-11-22)

Three sessions on `7f166fb`: 2026-11-18 (RDM), 11-19 (BLU) and 11-21 (BLU, then RDM),
the first two with their chat logs.

**What was wrong.** Kevin: "There were a few instances of me trying to get a WS off and
it wouldn't go off." With Auto Buff Mode or AutoWS on, GearSwap's own casts took every
window from a held press.

- Its tick fires a hair ahead of the release: `default_aftercast` less `latency = .5`,
  plus a tenth (Sel-Include, and Sel-Utility's `add_next_cast_delay`). That is 2.3s after
  a weaponskill's finish against the lock's 2.4, 2.5 after a spell's against 2.7 and 0.4
  after an ability's against 0.5. In the logs: +2.32 to +2.35, +2.52 to +2.53 and +0.36
  to +0.37.
- 851 presses were held, and 62 had a packet that was not the bar's leave meanwhile. A
  weaponskill held with nothing else sent went after 0.75s at the median (48 of them, at
  most 3.73s); one held while something else was sent, after 4.35s (45, at most 17.60s).
- Ten weaponskills waited 3.4 to 17.6s. On 11-19: 21:38:54 (6.4s, 29 presses), 21:39:21,
  21:42:08, 21:42:20, 21:55:50, 22:04:19, 22:04:31 and 22:17:31 (13.2s, 73 presses,
  behind Nat. Meditation, Cocoon, Unbridled Learning and Mighty Guard). On 11-21:
  20:20:26 and 20:32:04 (17.6s, 30 presses).
- 11-19 21:42:25, a death. A cure OK'd at 21:42:13 was held 6.5s and the Sanguine Blade
  that replaced it 5.9s, while Erratic Flutter left 2.34s after the weaponskill's finish,
  again after its interrupt, and Nat. Meditation after that. Neither press went out.
- With automation off the queue did little wrong: on the two RDM stretches 282 of 292
  weaponskills started inside 2s of the first press.

**Why GearSwap wins.** A command that reaches its `default_precast` pushes its tick back:
2.75s for a weaponskill, `cast_time / 4 + 3` for a spell, .85 for an ability. That is how
a mash kept its automation off before the queue. A held press never reaches it.

**The rule** (Kevin: "Stand aside", then "Any outside packet", "Hold it" and "Last second
only").

- It starts on any action packet the bar did not send: one that leaves two seconds or
  more after the bar last sent anything - a press it let through, a release, an OK's
  cast.
- While it stands, a press or a cursor's OK made in the last second of a lock, with no
  cast running and nothing unanswered, is not held. It goes as pressed, in place of what
  was held, and `debug` says `not held: <name>, standing aside`.
- It ends when one of the bar's own is accepted or nothing is busy, and a clear forgets
  it.
- A press made sooner is held as ever. Mid-cast it could only be refused, and GearSwap
  takes that refusal for the end of the cast it is in. Earlier in the lock it would meet
  Kevin's WS buff (his User-Globals): a weaponskill is answered by Berserk, Warcry or
  Aggressor in its place, the weaponskill is sent again 1.1s later (1.08 to 1.12s, 69 of
  69) and every other weaponskill press is dropped for 5s. Sent early in a lock the buff
  and the second send are both refused - an ability sent 0.5s after a spell's finish was,
  once of once - and the mash goes nowhere for five seconds.
- A press still on its own recast is held as ever too (from review, 2026-11-22; Kevin's
  call, 2026-11-23). Sent, it could not go at the lock's end either, and once GearSwap's
  own wait is over its `check_recast` aborts the press unseen, with a line of chat.
- The two seconds are what keep that second send from counting as somebody else's.

**What it costs**, accepted.

- A single press made in that second is refused and lost where it was held, a cursor's
  OK included. After an ability or an item, whose lock is a second or less, that second
  is the whole lock.
- A macro's packet, or another addon's, stands the bar aside as GearSwap's does, so the
  last second of the lock after one no longer queues.
- The first automatic cast always gets in. So does one within two seconds of a bar send
  (0.4s after an ability the bar sent), and GearSwap's retry of a cast of its own that
  was interrupted, which its source puts 1.35s after the interrupt.
- What the service sends without asking the queue - an enchanted item's use, at the
  press or after its warm-up, a reraise slot's gear, a warp's cast - is not counted as
  the bar's. A hook the service calls as it sends would close that (review, 2026-11-22).
  Not built.

**Not done.** Beating GearSwap by timing alone, its 2.5s after a spell being at the edge
of what the server accepts. Blocking its packet, which would leave it mid-action in the
wrong gear. Sending a held press now and again at the lock's end, a retry like the one
removed on 2026-10-16. And anything in GearSwap itself (Kevin: "We are not modifying
gearswap for this addon").

**Review.** Two blind rounds, clean on the second. The first found no spec proving that
a release or an OK's cast counts as the bar's own send - two were added, and shown red
with that line removed - and that a press on its own recast was being sent in the last
second. The second's notes that stand: the hook above, and that after an outside
ability or item every press in the lock goes as pressed, the lock being that short.

**Unverified in a live client** (row 45), all of it.

**Its first press in a live client was thrown away** (a Sortie, 2026-11-23, on
`524150f`). Kevin: "On the skeletons in Sortie, I tried to cast silence immediately after
manually casting fire from the menu, and it never went off. I had to input it a second
time and then it went off." At 22:52:55 his Fire left, made by the game's own menu, and
the bar stood aside for it as for any packet it did not send. He OK'd a Silence 2.29s
after the Fire's finish, in the lock's last second: `not held: Silence, standing aside`,
out at +2.31s, `refused, message 17`. Held, it would have gone 0.41s later. He cast it
again three seconds on. At 22:53:41 another Silence missed the same fate by 0.04s. The
bar stood aside 19 times in that log, for thirteen spells it did not send - the
skeletons' six Fires among them - and six items used by hand, and nothing automatic was
racing it at any of them.

**A menu cast can be told from GearSwap's.** GearSwap answers every action that is typed,
bound or sent by an addon, its own automatic casts among them, by blocking the text and
injecting the packet itself (`triggers.lua`, `flow.lua`), and it has no handler for an
outgoing `0x01A` at all: one made from the game's menu leaves as the client built it. So
the `injected` flag of `outgoing chunk`, which the entry point drops today, is false for
a menu cast and true for all GearSwap sends. A macro or a typed line is injected too,
and cannot be told from the automation. Read in GearSwap's source, unverified in a
client, and not built: Kevin's call.

## Engaged with no battle target (Kevin, 2026-11-23)

One log on `7f166fb`, 2026-11-22 11:40 to 11-23 01:23, with its chat logs: eleven
visits to Dynamis, two of them Divergence (San d'Oria [D] 18:00 to 18:59 and Jeuno [D]
23:23 to 01:23), a Walk of Echoes and two Sorties.

**What was wrong.** Kevin, of the second Divergence run: "quite a few times I had
instances where I was engaged but didn't have a battle target", put right each time by
targeting a mob and attacking it by hand. His read: "I think it is packets getting lost
under high load."

**What the logs say.**

- That run was the laggiest in the file. A weaponskill started 1.02s after it left at
  the median and 2.02s at the worst (334 of them), against 0.72s and 1.55s in the first
  Divergence run (122) and a median of 0.34 to 0.56s in the old Dynamis zones. 129 of its
  329 weaponskills had their start and their finish arrive together.
- It lost packets. Eight of his own spells started and were neither finished nor
  interrupted, with no death near. The first run had two, both finished late, and no
  other run had more than two.
- The game auto-targeted from 87 of the 175 kills that were his own there, against 57 of
  80 in the first run. Where it did not, the next mob he hit was no statue 56 times
  against 9.
- Seven auto-targets there were followed by 9 to 50s with no swing and no range or sight
  message, where the first run's six ran 7 to 8s. At 00:41:04 the game auto-targeted a
  Regiment Vandal, which fell four seconds later, and he did not swing for 21s.
- Nothing ties it to the bar, which never touches the battle target. No cursor's arrow
  was up at any of those, and a kill with one up was auto-targeted at least as often as
  one without (16% of the auto-targeted kills there had one up, 5% of the rest).
- Neither log says his status or his target. A press under 1000 TP is swallowed with no
  line saying what `<t>` held, so two presses in the file show an empty `<t>` (00:33:56,
  0.2 and 0.4s after a death, a target back by 0.6s).

**What was built** (Kevin: "Yes, add them"). Three lines in `debug`, each written on an
event, and nothing acts on any of them:

- `status <n>` at each change of status the client reports, off the service's
  `on_status`.
- `auto-target <id>` for each `0x029` message 234 with him as its actor, in place of the
  `unlisted message 234` a send then unanswered used to draw. Ten of ten of those in
  this log came the second the chat log said "Auto-targeting the <mob>.".
- For each bar press aimed at `<t>`: `no target for <name>, status <n>` with nothing
  under it, or `target <id> fell <n>s ago for <name>, status <n>` with a mob there the
  game has said fell, for as long as the queue remembers the death. The last mob of a
  pull leaves the target on its corpse. In any status, since which status is the
  question, and ahead of the line that says what became of the press. A press aimed
  anywhere else says nothing, or every buff cast with nothing targeted would write a
  line. That extra read of `<t>` is made in `debug` alone.

**Seen in the same log, and nothing built.**

- Eight held presses waited 4.5 to 11.6s behind casts the bar did not send: Haste II
  11.6s behind two Trust summons (18:22), Cure IV 11.5s behind three -ga nukes (22:41),
  Expiacion 9.5s behind Nat. Meditation and Cocoon (20:02). That is standing aside's
  case, on a client that did not have it yet.
- Twice a weaponskill was answered "too far" (message 78) with no start seen:
  `ignored a finish with no cast running, message 78`, then `no answer to the last send`
  once its 2s were up. At 23:28:16 a held Dia III was released into that weaponskill's
  lock and refused.

**Unverified in a live client** (row 46), all of it: that `status change` fires on every
change, and that `<t>` is empty or on a corpse when it happens. A corpse the game sent
no death message for draws no line: the client's own mob table is not asked, here as
everywhere else in the queue.

**A third Divergence run, with its chat log** (Bastok [D], 2026-11-23 18:30 to 19:29, RDM
with Trusts, still on `7f166fb`). The queue's own figures were ordinary: a weaponskill
started 0.69s after it left at the median and 1.60s at the worst (122), three spell
finishes came late and none was lost, and none of the bar's 144 releases was refused.

- The game auto-targeted from 52 of his 74 kills. Of the 22 it did not, 16 had no mob
  known asleep beside him, most of them the last of a pull. Six had one and still drew
  none: 18:45:30, 18:46:54, 18:53:57, 19:01:06, 19:18:29 and 19:27:33. After each he
  picked the next mob with a `<stnpc>` Dia III, Silence or Sleepga, and his next swing
  came 10 to 23s after the kill (median 13s), against 7s after an auto-target.
- **It follows the killing blow.** With another mob known asleep at the kill, a plain
  melee kill of his own was auto-targeted 19 of 19 times here and 10 of 10 in the San
  d'Oria run; a kill by a weaponskill or a spell 25 of 30 and 34 of 40. That is none
  missed of 29 against 11 of 70, about 2% likely by chance. A melee kill with a
  weaponskill or a spell on its way out missed once in three (18:53:57). In the Jeuno
  run, where nothing was asleep to count by, weaponskill kills missed 80 of 139 and melee
  kills 7 of 34.
- **Not sleep and not range.** 40 of the 52 auto-targets picked a mob that was asleep, and
  40 were answered "out of range" before any swing.
- **Nothing was lost on the way to him in this run.** The death message came at all six,
  and the killing weaponskill took the server as long where the auto-target came as
  where it did not (1.11s against 1.17s from the send to the finish, at the median).
- **Not the bar, as far as this shows.** At four of the six nothing of the bar's was on
  its way out and no arrow was up; one had a Savage Blade sent 0.6s before the mob fell
  and never answered, one a Sleepga arrow up for 3s. Kills with an arrow up were
  auto-targeted twice in the same hour (18:40:59, 18:56:12).
- **What others say of it.** Addon authors on FFXIAH, as fetched on 2026-11-23 and not
  checked line by line (the ATA targeting addon's thread of 2023,
  `ffxiah.com/forum/topic/57302`, and page 4 of the November 2024 update thread,
  `ffxiah.com/forum/topic/58073`): the server picks the auto-target and sends it apart
  from the death ("Hp=0, target defeated, and target change ... are all separate
  commands"), in a `0x058`; it marks you disengaged the moment the target's HP is 0; the
  client is never told which mob you are engaged to; and the miss is "a server driven
  race condition" that is "only a problem when instance performance is dipping". None of
  them ties it to the killing blow, which is these logs alone.

So the read above moves: lost packets were not needed to explain that run, and the miss
is the game's own, whatever the bar does.

**The first run on `524150f`** (Walk of Echoes [P1], 2026-11-23 21:58 to 22:26, BLU in a
party of six, with its chat log; the debug log starts at 19:51). The three lines are
there: 157 `status`, 47 `auto-target` against the chat log's 47 "Auto-targeting" lines,
135 presses at a corpse and 14 with nothing under `<t>`.

- **What the game did when his target died**, 70 times while he was engaged. It
  auto-targeted 47 times, the line 0.00 to 0.77s after the `fell` (median 0.01s). It
  disengaged him 20 times, `status 0` coming 0.00 to 1.74s after the `fell` (median
  0.87s) and `<t>` left on the corpse. Three times it did neither.
- **A disengage is what a missed auto-target looks like**, wherever a mob was left. Seven
  times he was engaged again within 8s (22:02:32, 22:04:40, 22:04:49, 22:04:57, 22:05:25,
  22:18:44, 22:20:16), four after his own weaponskill's kill and three after somebody
  else's. Twelve more took 10 to 80s, most of them the last of a group, and one was the
  end of the run. His own weaponskill's kills: 27 auto-targeted, 11 disengaged. Somebody
  else's kills: 18, 9 and the three below.
- **Engaged with nothing, three times** (22:17:01, 22:18:14, 22:18:29). Each was the
  death, at somebody else's hand, of a mob the game had auto-targeted 1.6 to 6.7s before.
  No `auto-target` followed and no `status 0`: he read as engaged for another 15 to 31s.
  Chat has a battle line of his 2 to 4s on ("Unable to see the Nostos Funguar.", a swing
  at a Nostos Bat), and his first press came 3.3 to 8.5s after the death. At 22:18:32 it
  was `no target for Savage Blade, status 1`, in the second a swing of his landed on a
  bat and the game called that bat out of range. That is the state Kevin described.
  Whether the server had moved him to that bat without telling the client, which is his
  lost packet, or he had switched by hand a moment after the press, the chat log's whole
  seconds cannot say.
- **An empty `<t>` is mostly nothing.** Four of the six runs of `no target for` lines came
  0.1 to 0.5s BEFORE a `fell` and the `auto-target` after it, and a fifth before a `fell`
  and its `status 0`: the client lets go of the target a moment before the death message
  arrives. Only 22:18:32 is the other kind.
- **Standing aside was raised 11 times and let no press go**: six items used by hand,
  Erratic Flutter and Cocoon twice each and Unbridled Learning once, ten over at `nothing
  is busy` and one at a zone. No press came in a last second, so row 45 is where it was.
  An item's line names no item, as its `out item` never has.
- **The rest read as built.** Two `swallowed Expiacion, stun`, two weaponskills answered
  too far (`finish weaponskill naming no spell, message 78`), two refused "You cannot
  see" (219), and a Cocoon sent on an 11.9s recast and refused. None of the bar's 32
  releases was refused by a lock.

**Row 46, as far as this goes.** `status` is written on the changes that matter here: 1
to 0 on a death the game did not auto-target from, 0 to 1 on engaging, 4 around every
zone. `<t>` stays on the corpse for the second or so until `status 0`, and is empty only
in the moment before a death message and at 22:18:32. Still open: whether the server had
a target for him in those three. By Thorny's account the target update is a `0x058`,
which nothing here reads; a `debug` line for it, and the target of an "out of range" or
"unable to see" (messages 4 and 5), would say.

**What was built for that** (Kevin: "Yes, add it", and both lines offered beside it).
Three more things in `debug`, and nothing acts on any of them:

- `server target <id>` for each incoming `0x058`, with ` for <player>` after it where the
  packet's player is not known to be him. Windower's packets library has it as an assist
  response: the player at 0x04, the target at 0x08.
- `out engage <id>`, `out switch target <id>`, `out assist <id>` and `out disengage <id>`,
  the id left off where the packet names none, for the outgoing `0x01A` categories 2, 15,
  12 and 4, as that library names them. They are no actions: nothing waits on one, and
  nothing stands aside for one. Without them a `server target` could not be told from the
  answer to his own switch.
- The mob the server has him fighting, each time it changes, with what the client holds
  under `<t>` beside it: `swing at <id>, <t> <id>` off his own melee round (`0x028`
  category 1), and `out of range of <id>, <t> <id>` and `unable to see <id>, <t> <id>` off
  `0x029` messages 4 and 5, which no longer draw `unlisted message`: one that comes with a
  send unanswered is said every time and ends `with the last send unanswered`, as that
  line did, since nobody has watched a ranged attack refused and it may be the answer. In
  the log above those two came the second the chat log said so, four times of four and
  six of six. It is said afresh after anything that may have moved his target - a change
  of status, a targeting packet of his own, an auto-target, the server's target packet -
  so a swing back on the mob last named is never taken for none, and `<t>` reads `none`
  for nothing. This is the only sight of a target the server holds and the client was
  never told of.

**Reading it** (row 47). After the `fell` of his target with no `auto-target`: a `swing at
<id>, <t> none`, or one of the other two, with no `out engage` or `out switch target` of
his before it is the server moving him untold. His own `out switch target` ahead of the
first `swing at` is him. A `server target` there with no packet of his before it is an
auto-target whose message was lost.

**Review.** Three blind rounds, each clean. The first asked that a message 4 or 5 coming
with a send unanswered keep saying so, every time, since it may be that send's answer,
and for specs on a round naming no mob and a client naming no player. The second found
that a swing back on the mob last named, after a switch of target, read as no swing at
all: what was last said is now forgotten at every targeting packet, auto-target and
target packet, and with `debug` off. Left as it is, from the third: a `0x058` arriving
with `debug` off forgets nothing, which no log can show.

**Unverified in a live client** (row 47), all of it: when the game sends a `0x058`,
whether his own switch draws one, and that messages 4 and 5 name their mob at 0x08.

## A Sortie and an Ambuscade on `524150f` (Kevin, 2026-11-23)

One log, 22:29 to 23:52, with its chat log: Outer Ra'Kaznar [U2] on RDM (22:35 to 23:35)
and an Ambuscade on BLU (23:41 to 23:44). Kevin, of it: "Couple times in here I think we
lost the 'spell complete' packet. I was still in the spell animation but got the effect
already. May have caused some issues".

- **One spell finish was lost**, of 152 starts: Erratic Flutter at 23:41:29, eight
  seconds into the Ambuscade's zone. 149 finished and two were interrupted. Its start's
  wait ran out 2.4s on (`no finish yet for the last start, lock 2.70s`), and an Unbridled
  Learning pressed in that lock was released 0.48s later and went. The Walk of Echoes log
  of the same night had one too (22:12:47), with a Cocoon held 4.32s behind it.
- **One finish came 0.07s after its start's wait ran out**, a Fire at 22:54:22, 0.98s
  after its start where the wait was 0.9s, and replaced the lock that wait had begun. The
  server answers on its 0.4s beat: seven other finishes came a beat later than that
  spell's usual, and none later than that.
- **What a lost finish costs** is the gap between the book's cast time and the cast as
  it ran, plus the 0.4s of slack, since the wait is the book's. Under a second on BLU
  here. On RDM, where Haste II ran 0.87s, it would be about 2.5s if the book says 3s;
  none was lost on RDM.
- A spell started 0.59s after it left at the median and 1.85s at the worst (152), a
  weaponskill 0.72s and 1.98s (60). None of the bar's 66 releases was refused.
- **Standing aside threw a press away**, its first in a live client: see that section.
- **Five Haste II OKs went out on their recast with nothing busy**, as built (22:39:04,
  23:12:40, 23:12:58, 23:26:16, 23:26:22; 1.08, 1.05, 0.32, 1.60 and 1.72s left), and
  GearSwap answered four of them `Abort: [Haste II] waiting on recast.` He opened the
  cursor again each time.
- 107 Expiacion presses were swallowed under amnesia in the Ambuscade, over 68s, and no
  `Abort:` for a weaponskill reached chat. The chat log has the amnesia wear off twice
  (23:43:41, 23:44:26), so it was put back between.
- Of 15 deaths of his target the game auto-targeted from two and disengaged him after
  thirteen, with nothing left to fight. None left him engaged.
