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
| `sent`: something went out, nothing back yet | a bar press or release, outgoing `0x01A` (3 magic, 7 ws, 9 ja, 16 ranged, 25 monster skill), outgoing `0x037` (item) | any `0x028` start or finish of ours, a refusal | 0.6s until the packet is seen, 2s after, or a spell's `cast_time` + 0.8s where longer (2026-11-06; 0.4s until 2026-11-26) |
| `acting`: a cast is running | `0x028` 7, 8, 9, 12 of ours | a finish, an interrupt (the same category with param 28787), and while a weaponskill's start runs a 4 naming no spell (2026-11-10) | a spell's `cast_time` + 0.8s (0.4s until 2026-11-26), a weaponskill 1.2s (3s until 2026-11-10), an item's `cast_time` + 1s, else 30s; a finish is still read as one for 30s (2026-11-06) |
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
| 8 | Hold a `<t>` nuke, tab to another mob | It lands on the first mob | The pin, and that `/ja`, `/ws`, `/ra` and `/item` take a bare id as `/ma` does. It is GearSwap that takes one, not the game (row 49) |
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
| 24 | Press a cursor slot during a macro's own `<st>` cursor and OK it, then press and OK the slot | `swallowed ..., another arrow is up` and no "You cannot perform that action on the selected sub-target", the macro's spell on its OK, then `cursor`, `arrow`, `OK` and the slot's spell, with no "A command error occurred" | An arrow this did not open is left alone, and GearSwap is never sent a token the game refuses (2026-11-10). Seen on `3c91c54` (2026-11-24): swallowed twice, each slot's next press and OK cast, and neither chat line came |
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
| 34 | Cast Shell V on one target, then OK it on the next as soon as the arrow can be raised, several times over | `hold Shell V`, `Shell V waits ...s on its recast` where its recast outlasts the lock, then `release`, and it casts, with no refusal | The recast grace (2026-11-07). At one second it missed Shell V without haste, 11 of 11 ending 1.28 to 1.31s past the lock (2026-11-08); unverified at two. One more inside it on `15738b7` (2026-11-26): a Stun pressed in a weaponskill's lock, its recast 0.73s past the lock's end, waited and cast |
| 35 | Start a weaponskill on a mob as it moves out of range, then mash a macro through | `finish weaponskill naming no spell, message 78, lock 2.40s`, then `refused` lines, then a `start` | The lock after a too-far. 2.4 is the weaponskill's, unverified there: the 2026-11-10 run brackets it between +1.07 refused and +2.57 accepted |
| 36 | Mash a weaponskill MACRO on a mob that dies while the weaponskill is readying (a bar press is held through the lock and cannot test it) | `the target died, no finish to come, lock 2.40s`, then `refused` lines and a `start`, each with its time after that finish | How long the game locks after a weaponskill its target died under. The line never came on `dd6753a` (2026-11-12, once of once), the death asked of the client's table alone. On `a93e3ec` it came fourteen times and each was early, off that table and under the player's own killing blow; the table is not asked since (2026-11-16). Answered on `b6714b3` (2026-11-17, twice of twice): the game locks. Freed at the death, the next weaponskill went unanswered 0.88s after the one start and was refused 2.45s after the other, and one sent 2.95s after a start was accepted. The weaponskill's lock runs from the death since (2026-11-18), unverified at that length. Three more on `3c91c54` (2026-11-25), the death 0.36 to 0.48s after the start, and nothing was sent inside the lock. One more on `15738b7` that night, the death 0.02s after the start, and again nothing sent inside it |
| 37 | Mash a weaponskill slot as a mob dies with the next one in reach | `the target died, no answer to come`, then `out weaponskill` and its `start` inside a second | The wait a dead target cost was 2s; whether GearSwap holds the press back itself is unknown. The line never came on `dd6753a` (2026-11-12, nine of nine); the game's death messages are read since. Confirmed on `a93e3ec` (weekend of 2026-11-14): 44 times, and the next weaponskill landed 17 times of the 39 one was pressed. Such a press is swallowed since (row 44). Again on `b6714b3` (2026-11-17): 12 times, none early, and the next weaponskill left 0.19 to 0.48s after the wait ended and started, three of three, so nothing locks there |
| 38 | Press a cursor slot where no arrow can be raised, wait 2s, then run a `/ta <stnpc>` macro and OK it | `no arrow for <name>`, and the macro's cursor works with nothing cast | A cursor that raised no arrow must not take another's OK |
| 39 | Start a ranged attack on a mob that dies before the shot | Whether an interrupt or a finish follows the `start ranged`, or nothing for 30s | Whether a ranged start needs the dead-target rule too (review, 2026-11-12) |
| 40 | With 1000 TP, press a weaponskill slot under Amnesia, and again stunned or asleep | `swallowed <name>, amnesia` (or `stun`, `sleep`), no `out weaponskill`, and no `Abort:` line in chat | That the press no longer reaches GearSwap. Failed on `dd6753a` (2026-11-12): three stuns were never seen, asked of the client's list. The `0x063` is read since, and `(not in the client's list)` after the status says the client's list still lacks it, `(in the client's list, where ipairs does not reach)` that it holds it off its array. Confirmed on `a93e3ec` (weekend of 2026-11-14): 211 swallowed, none through, and neither note was ever written. Again on `b6714b3` (2026-11-17): 114 swallowed, and no `Abort:` for a weaponskill in chat |
| 41 | Mash a weaponskill slot through a lock while the party kills the mob, then stop pressing | `dropped <name>: the target died`, and no `out weaponskill` at the corpse | The held drop, and that the game's death messages reach the client for someone else's kill. Confirmed on `a93e3ec` (weekend of 2026-11-14): an Expiacion dropped, and 859 `fell` lines, others' kills among them |
| 42 | OK a Sleepga's cursor on a mob during a lock, and have the mob die before the lock ends | `dropped Sleepga: the target died`, and the next Sleepga goes at once | The held drop for a spell, and that a monster's id is never under 0x01000000. Seen once on `a93e3ec` (weekend of 2026-11-14), a Dia III, dropped rightly |
| 43 | With the party full, let AutoTrust cast a Trust, and another with enmity held | `refused, system message 298 (param <n>)` for the full party and `300` for the enmity, each right after the `out spell`, and a press held behind it goes at once. `no spell was waiting` after one means it freed nothing. 296 or 297, should either come, reads the same | That these are what the game sends and free the bar, and that 298 and 300 are those two lines, as LandSandBoat's table has them. Not seen on `b6714b3` (2026-11-17): no Trust was refused. 298 seen once on `3c91c54` (2026-11-24, 23:14:23): a Trust cast with five out drew it 0.23s after the `out spell`, with "You have called forth your maximum number of alter egos." in chat, and the wait ended there. Twice more on `15738b7` (2026-11-25, 23:07:16 and 23:07:18), 0.57 and 0.59s after GearSwap's own Joachim left. 300 and the other four are not seen |
| 44 | Mash a weaponskill slot on a mob as it dies, and keep mashing until the next one is targeted | `swallowed <name>, the target died (<id> fell <n>s ago)` for each press in the three seconds after that mob's `fell` line, no `out weaponskill` at it then, and the first press on the next target goes | The press at a fallen target (2026-11-16), and that nothing alive is taken for one. Confirmed at two seconds on `b6714b3` (2026-11-17): 52 presses swallowed over 11 deaths and no `out weaponskill` at a corpse the game had reported, the ages 0.00 to 1.76s. Three seconds since (2026-11-18): an `out weaponskill` at a corpse later than that, with `the target died, no answer to come` after it, is one the window missed. At three seconds on `3c91c54` (2026-11-25): 41 swallowed, the ages 0.01 to 1.77s, and the nine that left at a corpse all left in the frames around its `fell` |
| 45 | With Auto Buff Mode on and a buff down, mash a weaponskill slot from its own lock on, and again with Berserk, Warcry or Aggressor ready | `out spell <buff>` and `standing aside for spell <buff>`, `hold` lines through that cast and the first of its lock, then in the lock's last second `not held: <name>, standing aside` and an `out`, each `refused` until one `start`s, and `no longer standing aside: the bar's own went`, with no second `out` of GearSwap's before that start. With a buff ready the first `out` is the buff's, and `out weaponskill` follows it by 1.1s and starts | Standing aside (2026-11-22). That a mash has a press in the last second ahead of GearSwap's next cast, that the press holds that cast back, and that the WS buff's second send lands after the lock. Unverified. Not exercised on `524150f` (2026-11-23): it stood aside 11 times, for items used by hand, Erratic Flutter, Cocoon and Unbridled Learning, each ending at `nothing is busy`, and no press came in a last second. In a Sortie the same night it let its first press go, a Silence OK'd in the last second of the lock after a Fire Kevin cast from the game's menu: refused, and cast again by hand 3s later, with nothing automatic sending. Exercised on `3c91c54` (2026-11-24): 13 presses let go, nine went, three refused (one by the lock, a weaponskill 1.73s after a spell's finish) and one lost its target; the WS buff's second send landed after the lock and started twice. That the press holds GearSwap's next cast back is not shown either way. Later that night, with GearSwap handling nothing (row 49): 12 let go, seven weaponskills started, one was refused 2.15s after an interrupted spell ("Unable to use weapon skill."), and four never left the client. On 2026-11-25, still `3c91c54`: six let go after a Stonega cast from outside the bar, four went and two Sleepga OKs were refused (sent 2.03 and 2.12s after its finish), the first single presses thrown away; and three Cure IVs each waited 3.4 to 3.9s behind a Trust GearSwap summoned 0.14 to 0.20s ahead of the release, none of them pressed in a last second while it stood aside. On `15738b7` (2026-11-25): one let go, a Black Halo 2.63s into a lock, which started; later that night four Guillotines, one started and three refused by the lock (sent 1.89, 2.38 and 2.42s after a spell's finish), each going on the mash's next press 0.5 to 1.7s later. On 2026-11-26, still `15738b7`: three let go, a Guillotine and a Drain II starting and an Absorb-ACC refused (sent 2.28s after a Sleep II's finish), which went on his next press 0.72s later. On `b7499d0` that evening: one let go, an Expiacion, which started |
| 46 | In a crowded fight, when you are left engaged with nothing targeted, press a weaponskill slot before targeting anything | `no target for <name>, status 1` (or `target <id> fell <n>s ago for <name>, status 1`) for each press until a target is back, under the `fell` of the mob you were on, and either no `auto-target` after that `fell` or an `auto-target <id>` whose `<id>` then `fell`; no `status 0` in between | The status and target lines (2026-11-23). Whether the client still reads engaged, whether `<t>` is empty or on a corpse, and whether the game auto-targeted. A `status 0` there means the client was told it disengaged. Seen on `524150f` (2026-11-23, Walk of Echoes): the lines are written, 47 `auto-target` to the chat log's 47. Of 70 deaths of his target 20 went to `status 0` instead, a median 0.87s on, and three kept status 1 with no `auto-target`, each the death of a mob an `auto-target` had named 1.6 to 6.7s before; one press among them read `no target for Savage Blade, status 1`. Whether the server had a target for him then is open |
| 47 | In a crowded fight, let the party kill the mob the game has just auto-targeted for you, and when no target comes back switch to one by hand as you usually do | Under that mob's `fell`, with no `auto-target` after it: either a `swing at <id>, <t> none` (or `out of range of`, `unable to see`) with no `out engage` or `out switch target` before it, or an `out switch target <id>` ahead of the first `swing at`; and a `server target <id>` after every `auto-target` | Who moved the target (2026-11-23). A swing with `<t> none` and no targeting packet of yours before it is the server moving you untold; your own packet first is you. Also when the game sends a `0x058`: with each auto-target, and in answer to your own switch or not. Answered on `3c91c54` (2026-11-24): a `0x058` came with 118 of 120 auto-targets, in the same frame, and in answer to his own engage, switch and assist. Of 177 deaths of the mob he was on, five drew nothing: in four the server sent nothing until he switched by hand 3.0 to 6.6s on, and in one it had him on a new mob it never named to the client (`unable to see 17981445, <t> 17981442`). Later that night: 129 of 129 auto-targets with a `0x058`, and of 215 deaths of the mob he was on, 129 drew an auto-target and 86 a `status 0`, none nothing. On 2026-11-25: of 80, four drew nothing until a line had him on a mob no packet had named, 0.9 to 6.7s on, once with `<t> none` |
| 48 | With each slot flagged `tier=auto` (it was `//hud autospelltier on` until 2026-11-25) and the queue in `debug`: mash one tier V nuke slot through three casts; sleep one mob with a Sleep II `<stnpc>` slot and press it again for a second mob; press Shell V on target after target; and as a Scholar press a tier IV nuke without Addendum: Black | `at the press: <spell> on recast <n>s, casting; down to <tier>` (or `at the release: ... <n>s, free; ...`) before each cast after the first, each lower tier's `start` following and none `refused` for its recast; after the second Sleep II's `OK`, `at OK: Sleep II on recast <n>s, lock <n>s; down to Sleep` (`free` in place of the lock if the OK came after it); for Shell V no `down to` at all: `Shell V on recast <n>s, lock <n>s; near enough ready, kept`, then `Shell V waits <n>s on its recast` where its OK came in the lock, `not held: Shell V on recast` and a `refused` where it came after; `at the press: Fire IV needs Addendum: Black (on SCH 99...); down to Fire III` | AutoSpellTier (2026-11-24). That a step down lands at each of the three places it is made, and which of them catches a mash - the line says which: `at the press` if a spell's recast runs from its cast's start, `at the release` if it runs from the finish. That the two-second grace still waits. Partly seen on `3c91c54` (2026-11-24), in its first wording: four step-downs, each lower tier cast - at an OK in a lock, at an OK with nothing busy twice, and at a release, the last OK'd 1.3s into its own cast with no recast far off, so the client counts the recast from the finish. Of 18 presses two seconds or less from ready with nothing busy, the 12 at 0.73s or less went and the six at 0.97s or more never left the client, GearSwap aborting a spell more than 0.8s from ready (corrected 2026-11-25: the first reading had 16 starting). On 2026-11-25 two more of three went that way, and two more step-downs were cast: Refresh III to Refresh II at an OK in a lock, Haste II to Haste with nothing busy. This row's wording, `a8b5b5d`'s, was written once on `625391e` and then on `15738b7` (both 2026-11-25), where twelve more were settled, ten at an OK and two at a release (Fire V down to Fire II through a mash); Haste II went to Haste twice on one player in a round of Haste II, the second for "No effect", and Kevin wants the step-down opt-in per binding (open). Not seen: a plain press, an unavailable spell |
| 49 | With GearSwap's user file off (a bare `gs disable`), press a `<t>` weaponskill slot in the half second after a job ability | As it stands: `hold`, `release`, then `>> /ws "<name>" <id>` and "...A command error occurred." in chat, `nothing went out for the last press` 0.6s on, and the next press going as typed | A pinned id is GearSwap's to read and the game cannot (2026-11-25). Seen four times of four on `3c91c54`, on a DRK whose gear file was missing, GearSwap handling nothing of the bar's. A cursor's OK is sent the same way. Closed the same day: no id is sent any more, a pinned press going under a word of the game's own (rows 50 and 51) |
| 50 | With GearSwap off (a bare `gs disable`, or not loaded) and the queue in `debug`: press a `<t>` weaponskill slot in the half second after a job ability; press a `<t>` spell in a lock and tab to another mob before it goes, once at a monster and once at a party member; then all of it again with GearSwap on | `hold`, `release`, and the weaponskill starting: no id in the `>>` line and no "A command error occurred". For the press tabbed away from a monster, `dropped <name>: nothing names <id> (<t> <the new id>, <lastst> ...)` and nothing cast; from a party member, `<name> aimed at <p1>` (their own word) and the cast landing on them. With GearSwap on, the same lines, the release's packet within 0.04s and its precast gear on | A word in place of the id (2026-11-25). That the game reads a release for itself, that nothing regressed where GearSwap reads the word instead of the id (its `pretarget` now runs for a held press), and what moving off a target costs. With GearSwap on, on `625391e` (2026-11-25): 28 releases, 23 cast and none drew a command error. GearSwap off, and a target changed before the release, were not exercised. A target changed before the release once on `b7499d0` (2026-11-26): `dropped Anvil Lightning: nothing names 17489975 (<t> none, <lastst> none)`, the mob alive and let go of during a 1.68s wait on the recast. GearSwap off is still not exercised |
| 51 | The same on cursor slots, with GearSwap off and then on: OK a `<stnpc>` spell at a mob that is NOT your target, once free and once in a lock; OK a `<stpc>` spell on a party member, on yourself, and on a player outside the party | After `OK <name> at <id>`: `<name> aimed at <lastst>` and the cast landing on the pick, your own target unmoved. Or `nothing names <id> yet` first and the `aimed at` line a frame later. Or `dropped <name>: nothing names <id> (<t> ..., <lastst> ...)` and no cast. A party member's cast lands whatever `<lastst>` does: `aimed at <lastst>` where that names them, otherwise `<t>` or their own `<p1>`-`<p5>`. `aimed at <me>` for yourself either way | The open one (2026-11-25): whether the game takes a pick for `<lastst>` from a `/ta` line the queue kept from it, and whether before or after the line comes through. If it is the drop line, a cursor cast at anyone outside the party cannot go without an id, and that needs another way: Kevin chose the drop knowing it. On `625391e` (2026-11-25): a pick of yourself went under `<me>` and landed, six of six. No pick of anyone else, so `<lastst>` is still open. Answered on `15738b7` (2026-11-25), GearSwap on: 67 sends under `<lastst>` each landed on its pick, 19 of them a pick other than the one before. The game takes a pick once the handler has answered: inside the OK `<lastst>` still names the pick before, so a new pick goes at once under `<t>` or the party member's own word (`<p1>`, once), and one no word names (a mob not targeted, once) is `nothing names <id> yet` and goes a frame later. GearSwap off, and a player outside the party, were not exercised |
| 52 | After a `//lua reload hud`, press an `assist` slot or pad button; then `//hud assist <name>` and press again, and check `//alias` for one called `assist` | First `assist pressed, ...` in the log, `assist has no target yet - //hud assist <target>` in chat and no packet. Then `assist target set: /assist <name>`, and per press `assist pressed, ...` and `out assist <id>`, your target moving to theirs. No alias called `assist` unless you made one | Assist without the alias (2026-11-25): `input /assist <name>` sent straight from `send_command`, where the alias ran that same line (seen 24 times of 24 on `3c91c54`). Seen on `625391e` (2026-11-25): the hint and no packet 13 times of 13 before a target, `assist target set: /assist zaon`, then six `out assist` for 25 presses in seven seconds, 1.21s apart. On `15738b7`: 59 presses and 26 `out assist`. `//alias` was not checked |
| 53 | With nothing going on, press a spell slot (and OK a `<stpc>` one) about a second after that spell's last cast came off its lock, so its recast has 0.8 to 2s left; then one with half a second left; then one with five | `hold <name>`, `<name> waits <n>s on its recast` and `release <name> after <n>s`, an `out spell` within 0.04s and its `start`, with no `Abort: [<name>] waiting on recast.` in chat. At half a second: `not held: <name> on recast 0.5xs, lock 0.00s`, `out spell` and a `start`. At five: `not held`, and GearSwap's `Abort:` line or the game's refusal, as before. A Sleep II pressed 1 to 2s from ready is held and cast as Sleep II, where GearSwap used to cast Sleep in its place | The hold with nothing busy (2026-11-25). That a press 0.7 to 2s from ready now casts on its one press, that one 0.7s or less still goes at once and is taken, and that the release at a recast reading zero is taken too. Seen on `15738b7` (2026-11-25), for a cursor's OK: three of Haste II 1.18 to 1.62s from ready were held, two going when the recast read ready (5.00 and 5.01s after the last finish) and starting, the third replaced by a second OK 0.05s from ready, which went 0.05s on; three 0.57s or less from ready went as pressed and started; and the chat log has no `waiting on recast` abort for a spell in the hour. A plain press at the short end on 2026-11-26: a Dread Spikes 0.23s from ready went as pressed and started. On `b7499d0` the same day a plain press was held, `Anvil Lightning waits 1.68s on its recast`, and dropped at the release for its target (row 50), so its cast was not seen. Not seen: a plain press held and cast, an ability, a spell in GearSwap's `spell_stepdown` |
| 54 | In edit mode click a slot holding Fire V (or any spell with a tier under it) and click `auto tier [ off ]` at the end of its row; leave edit mode and mash the slot through a cast, the queue in `debug`. Do the same mash on a Haste II slot left unflagged. Then `//hud crossbar list`, `//hud crossbar tier <address> off`, and a `//lua reload hud` between any two of them | The row then reads `auto tier [ on ]` and chat says `crossbar: auto tier on for Fire V -> base / set <n> / <side> / slot <n>`; the mash logs `at the press` / `at OK` / `at the release: Fire V ...; down to Fire IV` and Fire IV casts. The Haste II slot writes no `down to` line and is never replaced. `list` shows `tier=auto` on the flagged binding, after a reload too, and not after `tier ... off` | The tier flag on the binding (2026-11-25). That the toggle sits clear of the row's own text and takes its click, that only a flagged binding steps down, and that the flag is saved with the binding. Unverified |
| 55 | With no Fast Cast on (a naked set, or GearSwap's precast off), cast a few spells of two seconds and over from anywhere, the queue in `debug` | No `no finish yet for the last start` line ahead of a `finish spell`: each cast's `start spell` is followed by its own `finish spell`, and the next bar press goes when that lock ends | The lost-finish margin at 0.8s (2026-11-26). At 0.4s the count ran out before the real finish 27 times of 27, by 0.02 to 0.37s. That two beats covers a cast with no Fast Cast; what a slow (Addle) lengthens it by is still unknown. On `b7499d0` (2026-11-26), Fast Cast on: of 77 spell starts none was counted ahead of a finish that came, and the two that were counted never had one. Unverified with no Fast Cast |

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

**A menu cast cannot be told from GearSwap's by its packet.** It was first written here
that the `injected` flag of `outgoing chunk` would split them, a menu cast leaving as the
client built it. Kevin: "Even if I cast from the menu, gearswap will still cancel it, do
the swaps and then send it correct?" It does. GearSwap's one way in for a player's own
action is its `outgoing text` handler, which blocks the text and injects the packet
itself (`triggers.lua`, `flow.lua`); it has no handler for an outgoing `0x01A`, and its
incoming one makes an entry for a pet alone. It swaps gear for a menu cast all the same,
so a menu choice must reach it as text, as a macro does, and every action packet is
injected while GearSwap is loaded, the menu's included. Read in its source, unverified
in a client.

**What does differ in the log is when the packet left.** GearSwap's automatic casts
leave 2.3s after a weaponskill's finish, 2.5 after a spell's and 0.4 after an ability's:
inside the lock, which is how they beat a release. The thirteen outside spells of this
log left 3.86 to 18.56s after the last finish, with no lock running and nothing held. A
bar that stood aside only for a packet leaving while it was busy would have stood aside
for none of those thirteen, and still for the automatic ones. Not built: Kevin's call.

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

## AutoSpellTier (Kevin, 2026-11-24)

The one switch this section asks for lasted a day: on 2026-11-25 it became a flag on each
binding, and the ladders stopped stepping down (see "The tier flag on the binding"). The
walk itself is as written here.

"AutoSpellTier is an on / off global setting (config menu or `//hud autospelltier
on|off`). When enabled, if I try to use a tiered spell (Fire V / Sleep II) and that
spell is on cooldown or unavailable (like due to level restrictions), walk down the
teir list to the next castable spell and send that. If no spell is available, send the
original spell and let the game refuse it. Never walk up the ladder from a lower tier."

**His calls, asked before it was built:**

- It ships **off** ("Off").
- MP is **not** checked ("No"), for the reason the ladders do not check it.
- Ninjutsu counts, San to Ni to Ichi ("Yes").
- In a lock, a spell whose recast ends inside the two-second grace is **waited for**
  ("Wait for it"), as the recast grace section has it.

**Told to him at the same time, and not objected to:** it applies to what the action
service fires (bar slots, pad and keyboard actions) and to no macro, menu cast or typed
command; a tier is a Roman numeral on the spell's name, songs included, and never a
Trust; "unavailable" is not learned, or out of both jobs' reach at their level now, or a
Scholar without the Addendum; a cursor slot is judged at OK; nothing in chat and a line
in `debug.log`; the slot's icon and recast unchanged; `core.lua` and the settings
window's global panel.

**As built:**

- `lib/actionbar/spell_tier` (new, pure): `lower(record, where)` answers the record to
  press in its place, the same table where nothing changes. It reads the tier off the
  resource's own spelling of the name.
- `lib/actionbar/castable` (new): the ladders' level and Addendum test, moved out of
  `lib/stealth` so the walk and the ladders cannot disagree. The black-side Addendum
  (402) is mapped there now; only the white was, no ladder casting black magic.
- "On cooldown" is two answers of the queue's, made public for it. `queue.far_off` sends
  the walk down: a recast running more than the two-second grace past the lock, or past
  now with nothing locked. `queue.refused_on_recast` is what it passes by: a tier the
  game would refuse if it were settled on now.
- **A spell nearly ready is never traded for a lower tier** (Kevin, after the first
  review: "Send it as pressed"). As first built, any recast running with nothing busy
  stepped down, so a Shell V OK'd just after its lock, a second short of its recast, cast
  Shell IV. Now it goes as pressed and the game refuses it, as it did before the
  setting; in a lock it is waited for, as it was.
- **It is walked in three places**, wherever a spell's command is settled: at the press
  (`service.fire`), at a cursor's OK (`queue.on_text`, through `deps.lower`), and at a
  held press's release (`queue.step`).
- **The release was not in what he was told**, and he kept it when asked ("Yes, step
  down"). A spell pressed inside its own cast may show no recast until the cast
  finishes; held, it was then dropped at the release for its recast, which is the mash
  the setting is for. So where a held spell would be dropped on its recast a lower tier
  takes its place, at the target the press was pinned to, and waits out its own recast
  as any held press does. With no tier to stand in it is dropped, as before. Whether the
  recast runs from the cast's start or its finish is unverified; the press covers the
  one and the release the other.
- A ladder's pick (`reraise`, `invisible`) is walked as a slot bound to that spell would
  be. `//hud reraise` typed is not: nothing typed takes the press path.
- **A tier that cannot be aimed where the pressed spell can never stands in** (second
  review): Warp for a Warp II cast at someone else, Phalanx for Phalanx II. It was left
  to the game at first; an id-pinned `/ma "Warp"` at a party member is most likely
  refused, but the other outcome is a trip home. The resource's `targets` is compared as
  a subset, in either shape: Windower's resources library hands a set of names
  (`S{'Self', 'Party'}`, read in its `resources.lua`), the raw data a bitfield. Where
  the two cannot be compared the tier stands in.
- **Open, Kevin's call:** a press made inside another spell's cast is measured from the
  press, the queue's own rule that only a lock counts. A spell three seconds from
  ready, pressed 1.5s before a cast ends, steps down though it would have been ready by
  its turn. With the setting off that press is sent and refused, so nothing is worse
  than it was; counting the cast's expected end would change the queue's rule too.
- **Found on the way, not fixed here:** `lib/stealth`'s `suffix` reads `targets` with
  `tonumber`, so with the library's set it always answers `<me>`, and a sneak or
  invisible ladder would never land on a targeted party member in a client. Flagged to
  Kevin as a task of its own.

**The debug line and the ladder table (Kevin, 2026-11-24, after the push):** "Make sure
that there is enough debug lines that you can accurately determine when it was decided to
go down a tier and why the requested spell wasn't available ... include a table that lists
the ladders for each spell that AutoSpellTier effects, sorted by job > spell type > spell
name. Double check the spell lists against the Windower resources file."

- **One line for each decision**, where there were three bare ones (`Fire V on recast,
  down to Fire IV`, `Fire V unavailable, ...`, `... no tier under it can go`), which said
  neither which of the three places decided nor what "unavailable" meant:
  `at the press: Fire V on recast 9.87s, lock 1.20s; Fire IV on recast 4.10s; down to
  Fire III`. The moment is the caller's word (`at the press` from `service.fire`, `at OK`
  and `at the release` from the queue, a fourth argument of `deps.lower`); the seconds
  are the service's `recast_left`, and after them comes what the queue was busy with in
  its own words (`queue.doing()`: `lock <n>s`, `casting`, `unanswered`, `free`) - both
  new deps of the walk that decide nothing; the reason a spell cannot be cast is `not
  learned` or `castable.why_not`'s words, which name the level, the Addendum or the gift
  a job of the pair still wants and the pair it was asked of.
- **A spell kept says so** (`near enough ready, kept`), mine and not asked for: without
  it a spell on its recast that was not stepped down reads the same as the setting being
  off.
- **Each tier passed by is in the line**, with its reason: the same words, or `cannot be
  aimed as <spell>`, or `no such spell`.
- **From the review's notes, taken after its clean verdict and not reviewed again:**
  `casting` in place of `lock 0.00s` for a press made inside another action, which read
  the same as a press made free and is the very case row 48 mashes; the level named
  beside the Addendum where a Scholar is short of both (`needs Addendum: Black and SCH
  73`); and `no such spell` for `not in the resources`, since the name lookup also
  leaves out an entry that is in them and unlearnable.
- **The table** is `wiki/autospelltier.md`: 167 rows over ten jobs (BLM 23, BRD 23, DRK
  12, GEO 14, NIN 10, PLD 6, RDM 32, RUN 3, SCH 30, WHM 14), jobs in alphabetical order.
  Produced by driving `lib/actionbar/spell_tier` itself for each job as a main job at 99
  that knows every spell, Enlightenment up, over Windower's `resources_data/spells.lua`
  as fetched on 2026-11-24 (commit `c82df42`, "November 10, 2026 FFXI Update"), with the
  service's own name lookup (`learnable.usable`, the lower id winning). A second read of
  the file as text, sharing no code with the first, gave the same 167 rows. Both name
  the same two families the target guard keeps out: Warp II (BLM) and Phalanx II (RDM).
  No job's tiers have a gap, and no two usable entries share a name.
- **Found on the way, not fixed here:** that update marks **Impact** (503)
  `unlearnable`, where the copy of 2026-10-21 did not. `lib/actionbar/learnable` leaves
  every such entry out of the name lookups and the binder's catalog bar Dispelga, so on
  current resources a slot bound to Impact reads no recast and the binder does not offer
  it. Impact is cast off a cloak, as Dispelga is off a club. Flagged to Kevin.

**Review.** Round 1 found the walk stepping down a spell nearly ready with nothing
busy, against the wiki and row 48, and Kevin chose to send it as pressed. Round 2 found
no spec holding the press away from a cursor slot, and raised Warp II. Round 3 was
clean; of its notes, a spec for a lower tier waited for at the release, the queue's
question renamed `refused_on_recast` (every other `on_` member of the queue is an
event), and the Warp wording were taken, and not reviewed again.

**Unverified in a live client:** all of it. Row 48.

## A run on `3c91c54` (Kevin, 2026-11-24, 17:50 to 21:04)

One session, 14,897 lines of `debug.log` with the chat log beside it: Dynamis [D], then an
instanced event. The first run with AutoSpellTier (in its first debug wording), with assist
and with the lines of row 47, and the first to exercise standing aside.

- **AutoSpellTier stepped down four times, and each lower tier was cast** (row 48).
  - At an OK in a lock, 20:08:53: Haste II cast on one player and OK'd on the next 0.02s
    before its lock ended. `Haste II on recast, down to Haste`, held, released at +2.73,
    started.
  - At an OK with nothing busy, 20:30:14 and 20:30:53: `Fire V on recast, down to Fire
    IV`, sent at once, started both times.
  - At a held press's release, 20:51:13: Gravity II OK'd again 1.30s into its own cast was
    held as Gravity II, and `Gravity II on recast, down to Gravity` came as its lock
    cleared; Gravity went at +2.73 and started.
- **The client counts a spell's recast from its finish** (one sample, that Gravity II): 1.3s
  into the cast the walk at OK saw no recast far off, and at the release it did. So the
  release is what catches a mash, and the press or OK what catches a spell cast a moment
  ago.
- **A spell 0.73s or less from ready went as pressed, and the game took it** (corrected
  2026-11-25: this read "two seconds or less", with 16 of 18 starting). Of 18 presses
  with nothing busy and 0.08 to 1.97s of recast left (Haste II 14, Sleepga 3, Dispel 1),
  the 12 with 0.73s or less went and started. The six with 0.97 to 1.97s never left the
  client: GearSwap aborts a spell with more than 0.8s of recast left, and each was OK'd
  again. The first reading took that second press's start for the first's. None was refused for
  its recast by the game.
- **Nothing tiered was dropped or refused on a recast** with a tier under it to go. What
  was dropped on a recast had none: Stun, Sleepga, Cocoon, Mighty Guard, Nat. Meditation.
  When the setting was switched on is not in the log: `3c91c54` writes nothing of a spell
  it keeps, and the settings window answers on its own status line.
- **Not exercised:** a step-down at a plain press (no cursor), and a spell that was
  unavailable rather than on its recast.
- **Assist works** (gamepad plan). `//hud gamepad bind y assist` at 19:47:17 and `//hud
  assist zaon` at 19:53:42, by the chat log. 24 presses, one `out assist` packet each: the
  alias takes the line, a press runs it, and one named after the command it wraps does
  not call itself. 22 named that player, and the game answered 15 of them with a target
  (`server target`, a median 0.36s on), which he then cast at or engaged. Seven drew none,
  four of them in a row at 20:21:46 to 20:21:54 before a fifth did. The first two, at
  20:09:46, named another entity (21001010), two seconds before an event began.
- **Who moved the target** (row 47).
  - A `0x058` comes with an auto-target: 118 of 120 `auto-target` lines have a `server
    target` naming the same mob in the same frame, a line ahead of the message.
  - It also answers his own engage (87 of 101, the same id, a median 0.78s on), his own
    switch (34 of 46) and an assist (15 of 24, naming the mob). Five of 283 followed none
    of those.
  - Of 177 deaths of the mob he was swinging at while engaged: 110 drew an auto-target and
    its message, 2 a `server target` with no message (the client's `<t>` followed), 60 a
    `status 0`, and 5 nothing.
  - In four of those five nothing came from the server until his own `out switch target`
    3.0 to 6.6s later, once with `no target for Expiacion, status 1` in between: engaged,
    with `<t>` empty.
  - **In one the server had him on a new mob and never said so.** At 18:05:10 his
    weaponskill killed 17981442, and 0.40s later the game answered `unable to see
    17981445, <t> 17981442`: a mob no packet had named, with the client still on the
    corpse. He switched to it by hand 7.5s after the death. That is the server moving him
    untold, once in 177.
- **Standing aside let 13 presses go** (row 45), each in a lock's last second.
  - Nine went. Two spells OK'd at +2.56 and +2.66 of a spell's lock started. Weaponskills
    sent 1.82, 1.85 and 1.86s after a spell's finish (the second after an interrupt) went,
    three of three, and one 2.26s after an interrupted item. One went 0.11s after an
    ability's finish. And twice GearSwap sent its WS buff in the press's place (Berserk)
    and the weaponskill 1.1s on, after the lock, where it started.
  - Three were refused: a weaponskill sent 1.73s after a spell's finish, by the lock
    ("Unable to use weapon skill."); one behind Aggressor for sight ("You cannot see");
    and one sent 0.18s after a Diffusion GearSwap had put between the buff and it.
  - One lost its target before an answer.
  - No single press was thrown away for it in this run: the two OKs both started.
  - Not shown either way: that the press holds GearSwap's next cast back.
- **The game takes a weaponskill sooner after a spell than it takes a spell.** Those three
  at +1.82 to +1.86 went where a spell is refused up to about +2.6, and +1.73 was refused.
  The queue's lock after a spell is 2.7 for whatever is held, and nothing was changed.
- **The locks held.** Of 292 releases 272 started. Seven were refused, none by a lock:
  sight twice, range, a job ability the game would not use, "unable to cast spells", "cannot
  perform that action", and a weaponskill GearSwap sent behind its own job ability. Twelve
  presses never left the client (`nothing went out`: Sleep II, Poisona and others GearSwap
  cancels), each freeing the bar after its 0.6s.
- **The rest read as built.** 4,010 presses swallowed for TP and 101 for amnesia; 37
  weaponskills swallowed at a corpse and four held presses dropped at one; nine
  weaponskills whose target died unanswered, and one that had started (19:21:50, lock 2.40s
  from the death, nothing sent inside it, so no new sample for row 36). No cursor was left
  without its arrow (row 38), and no Trust was refused by a system message (row 43): one
  Trust cast was refused with message 17, "Unable to cast spells at this time", 2.43s
  after another.
- **A press under another's arrow was swallowed twice** (row 24): Cure IV at 18:19:03 and
  Silence at 18:25:27, `swallowed <name>, another arrow is up`. Each was pressed again
  within 2.5s, opened its own cursor, was OK'd and cast, and the chat log has no "A
  command error occurred" and no sub-target refusal at either. Its one sub-target refusal
  (20:12:13) and two command errors (19:22:55, a spell pressed with nothing targeted, and
  19:31:14) came with nothing of the bar's under an arrow.

## The rest of that session: DRK with no gear file (Kevin, 2026-11-24 21:12 to 2026-11-25 02:19)

The same `debug.log`, 19,391 lines on from the run above and still `3c91c54`: job changes,
then two hours of scythe skill-ups as DRK/SAM in a party. Kevin: "Had some oddities happen
when I started playing DRK later on in the night. Probably gearswap related. I saw a couple
instances where the game refused a WS and the target ID was in the log not the name."

- **Four held weaponskills reached the game with the id still in them, and it refused each
  as a command.** `>> /ws "Slice" 17555873` and "...A command error occurred." at 00:33:06,
  Vorpal Scythe at 01:25:28, Guillotine at 01:29:44 and at 01:41:26. Each was a press held
  through the 0.5s after an ability (Hasso twice, Meditate twice) and released pinned, the
  chat line in the second of its `release`. `nothing went out for the last press` came 0.6s
  on, and the next mash went as typed 0.85 to 0.91s after the release. They are every
  weaponskill the queue released on DRK, four of four.
- **A bare id is GearSwap's to read, and GearSwap was handling nothing of the bar's on
  DRK.** It takes a command naming an id off `outgoing text` and sends the packet itself
  (`triggers.lua`); the game cannot read one.
  - The chat log has `GearSwap: Cannot find the include file (vanar_drk_gear.lua).` at
    21:33:52, 22:47:39 and 23:50:34 (and `vanar_sam_gear.lua` at 22:47:13 and 23:29:16).
    Sel-Include goes on to call `init_gear_sets()`, which only a gear file defines, so the
    load most likely stopped there with its tick already registered: Hasso kept going out
    on its own.
  - A release's packet left within 0.04s of it 284 times of 286 before the job changes,
    GearSwap sending it. On DRK the 32 that left took 0.01 to 0.40s, a median 0.12s: the
    client's own beat, the game reading `<me>` and `<t>` for itself.
  - Which call fails for each action is not known. GearSwap's errors go to the console,
    which is in neither log.
- **So a held `<t>` or `<bt>` press, and every cursor's OK, goes only where GearSwap is
  handling commands.** With its user file off - no gear file, a bare `gs disable`, his
  fork's `gs naked` or a `gs test` hold - or with no GearSwap at all, each is lost to a
  command error. Row 8 took "`/ws` takes a bare id as `/ma` does" for the game's doing.
  Open, Kevin's call (row 49).
- **The other oddities are most likely the same cause.** Hasso was sent into a lock and
  refused 42 times of 164 ("Unable to use job ability."), the tick having none of
  GearSwap's own precast to wait on, and at 01:25:26 it put Hasso back up 1.23s after his
  Seigan.
- **"Unable to use weapon skill." at 01:43:28 was standing aside** (row 45). A Drain cast
  from the menu was interrupted, the Guillotine he mashed through its lock was let go in
  the last second, 2.15s after the interrupt, and refused. The next left 1.07s after the
  lock.
- **Standing aside let 12 presses go**, 11 of them in the 0.5s after a Hasso of GearSwap's.
  Seven weaponskills went and started, six of them sent 0.53 to 0.61s after the ability's
  finish. Four never left the client - three weaponskills pressed 0.01 to 0.11s after
  that finish, and a Third Eye - and a later mash went. That is the game reading the line
  for itself, which no run with GearSwap handling it has shown.
- **A Trust refused by a system message, once** (row 43): Qultada at 23:14:23, with five
  out. `refused, system message 298 (param 0)` came 0.23s after its `out spell`, the chat
  log's "You have called forth your maximum number of alter egos." in the same second,
  and the wait ended there.
- **A weaponskill whose target died** (rows 36, 37 and 44). 41 presses swallowed at a
  corpse, 0.01 to 1.77s after its `fell`. Nine left in the frames around the death and
  were never answered, each freeing the bar at once. Three had started, the death message
  0.36 to 0.48s after the start, and each locked 2.40s with nothing sent inside it, so no
  new sample for row 36. Three held presses were dropped at a corpse.
- **Who moved the target** (row 47): all 129 auto-targets came with a `server target` in
  the same frame. Of 215 deaths of the mob he was swinging at while engaged, 129 drew an
  auto-target and 86 a `status 0`. None drew nothing.
- **Assist**: four presses (00:25:05, then three at 00:26:28 to 00:26:32), one `out assist`
  each at the same player, one answered with a target.
- **The rest read as built.** 549 weaponskills left: 532 started (528 finished, a median
  0.37s on), seven were refused for sight ("You cannot see"), one by that lock, and nine
  went unanswered at a dead target. 10,886 presses were swallowed for TP and 482 held ones
  dropped for it.
- **Not in this run:** `a8b5b5d`'s lines. With the build still `3c91c54` there is no
  `assist pressed` line and no tier line in the new wording, and nothing tiered was cast
  from the bar.

## A word in place of the id (Kevin, 2026-11-25)

Kevin, on the run above: "I want to remove the dependence on GearSwap for target ids. I
should be able use XIVHud both with and without gs disabled". Row 49 closed.

**The rule.** Nothing the bar sends names a target by its id. A press is still pinned to
the id under its token at the press (`service.pin_target`), since the dead-target rules
and the tier walk judge by it, but what is held is the command AS TYPED, and at the send
`service.aimed_command` puts it under a word of the game's own that names that mob now.
A word is read by the game and by GearSwap alike, as a macro's is, so nothing has to
know whether GearSwap is up.

- **Which word.** The one it was typed with while that still names the mob (`<t>`,
  `<bt>`). Otherwise the first of `<me>`, `<lastst>`, `<t>`, `<pet>`, `<p1>`-`<p5>`,
  `<a10>`-`<a15>`, `<a20>`-`<a25>` that does, steadiest first.
- **Never `<bt>` or `<ht>` as a stand-in.** The wiki's FFXI Functions page says
  Windower's reading of each is "not guaranteed to return the same mob" as the game's. A
  slot typed with `<bt>` still goes under it.
- **No word, no press** (Kevin's pick of three). The others were the id as a last
  resort, which only GearSwap reads, and following the token to whatever it names at the
  send, FFXIV's way, by which a held Cure can land on a mob tabbed to. He chose the drop
  knowing what it costs if `<lastst>` does not hold a pick (below).
- **Where it applies.** A held `<t>` or `<bt>` press at its release; a cursor's pick at
  OK or at its release; an enchanted item's deferred use (`<item> lost its target`, its
  GearSwap hold released). A press that goes at once was always sent as typed.

**A cursor's pick.** The game hands the pick back as an id on a `/ta` line the queue
keeps from it, and the cast then needs a word for that id. `<lastst>` is the game's own
for the last sub-target; a party member has their own, and yourself `<me>`.

- **Nothing says when the game takes a pick for `<lastst>`**, or whether it does at all
  from a line it never gets: before the line comes through `outgoing text`, once the
  handler has answered, or only as it runs the command. So a pick no word names at OK is
  judged on the next frame's `step` instead (`nothing names <id> yet`), which covers the
  second case, and is dropped there if none names it still.
- **If it is the third**, every cursor cast at a mob that is neither your target, your
  pet nor in your party or alliance goes nowhere, with GearSwap or without. `debug` says
  which it was (row 51), and that would need another way to aim.

**What changes with GearSwap up.** It reads `<t>` where it read an id, so its
`pretarget` runs for a held press and for a cursor's cast, as it does for a macro. A
press whose target was moved off and that no word names is dropped where it used to land.

**Every read of a word is behind a `pcall`.** They are asked under the frame tick's guard
and the text handler's, where five errors switch the handler off, and of words no live
client had been asked for (`lastst`, `me`, `pet`, the party's and the alliance's). The
wiki lists each as valid for `get_mob_by_target` and says nothing of what a wrong one
does.

**Specs that predate the branch.** Kevin's go-ahead covered the id assertions in
`queue_spec` and `service_spec`. One more was found by the full run, in `crossbar_spec`
("pins a target token at the press, so a deferred use cannot wander"): it asserted the id
form of the deferred item use, and now asserts that nothing is used at the new mob. It
was changed on the same go-ahead, being outside the two files named, and Kevin kept it
when asked (2026-11-25: "Keep it").

**Unverified in a live client:** all of it (rows 50 and 51).

## Assist without the alias (Kevin, 2026-11-25)

Kevin: "instead of creating and binding to a WIndower alias, send the command directly
via the windower API. there is no need to remember the target between sessions.
Essentially, store the string that was the alias, and send that every time `assist` is
invoked."

- `//hud assist <target>` keeps `input /assist <target>` with the action service and
  sends nothing. A press sends that line. No alias is written, so one of the player's own
  called `assist` is left alone, and `//assist` is no longer XIVHud's.
- The target is the session's: a reload or a restart forgets it.
- **A press with no target given** sends nothing and says `assist has no target yet -
  //hud assist <target>`. The author's pick with Kevin away, his to change: it is how
  every other refused press answers, where the alias gave a console "unknown command".
- The debug line for a target is `assist target set: /assist <target>` (it was `assist
  alias set`), and a bare `//hud assist` with no target now writes its `assist pressed`
  line as a slot's press does.

**Unverified in a live client** (row 52): the direct send. The alias ran the same line,
24 times of 24.

## A Dynamis [D] run on `3c91c54`, before the word change (Kevin, 2026-11-25, 18:30 to 19:29)

Kevin: "Updated Debug log in the logs dir from before the update". One hour as RDM, 4,742
lines of `debug.log` with the chat log beside it. Nothing of `8e4a72a` is in it, so rows 50
to 52 are untouched.

- **A correction to the run of 2026-11-24: a spell more than 0.8s from ready never leaves
  the client.** With nothing busy a press on its own recast goes as pressed, and GearSwap
  aborts a spell with more than 0.8s of recast left: `check_recast` in his
  `Sel-Utility.lua` tests `spell_recasts[...] > spell_latency`, which is `latency * 60 +
  18`, 48 sixtieths, and says `Abort: [<spell>] waiting on recast.` in chat.
  - This run: Refresh III at 0.68s went and started. Sleepga at 0.85s and Haste II at
    1.03s never left, each with its `Abort:` line, and each was OK'd again 1.5 and 2.5s
    later. Sleepga at 7.03 and 20.43s was aborted too.
  - The 2026-11-24 run, read again: of its 18 presses two seconds or less from ready, the
    12 with 0.08 to 0.73s left went and started, and the six with 0.97 to 1.97s left never
    left. The first reading had 16 of them starting: it took the start of the press made
    again for the first press's.
  - Over both runs 13 of 13 at 0.8s or less went, and eight of eight between 0.8 and 2s
    cost a second press. That the game takes a spell up to two seconds from ready is not
    shown: none reached it.
  - Whether such a press is held for its recast, as one in a lock is, had been passed
    over on the figure corrected here. Kevin took it the same day: see "A press near
    ready with nothing busy" below.
- **Standing aside threw two single presses away** (row 45), the first seen. Kevin cast
  Stonega from outside the bar 18 times from 19:11 on, and five times OK'd the bar's
  Sleepga in the last second of its lock.
  - Sent 2.18, 2.24 and 2.43s after the Stonega's finish, it started, two of the three
    about 0.4s sooner than a release at 2.70 would have.
  - Sent 2.03s (19:19:16) and 2.12s (19:28:25) after, it was refused, "Unable to cast
    spells at this time.", and the Sleepga OK'd again left 3.76 and 2.08s after the lost
    one: 3.1 and 1.5s later than a held release.
  - A Saboteur let go 1.80s after a Stonega's finish went.
  - Nothing automatic was sending at any of the six.
- **Three cures in a row each waited behind a Trust GearSwap summoned**, which standing
  aside does not reach. 18:36:24 to 18:36:43, curing two Trusts with three down: Qultada,
  Ulmia and Joachim each left 2.51 to 2.56s after the finish before it, 0.14 to 0.20s
  ahead of the release, and the Cure IV held there went 3.9, 3.4 and 3.7s late. None of
  the three was let go: the first was OK'd before any packet of GearSwap's, the second
  after standing aside had ended at `nothing is busy`, and the third 0.69s into a lock.
  Each automatic cast is a first one, and the first always gets in.
- **The locks held.** Of 109 releases 105 were cast, the packet leaving within 0.04s of the
  release for 107 of the 108 that left. None was refused. Two went unanswered (a Stun at
  19:13:18, a Sleepga at 19:20:59), a Sanguine Blade's target died 0.56s after it left,
  and one never left the client: a Dia III OK'd at a mob 2.05s dead went unanswered, the
  next Dia III waited its two seconds out, and GearSwap dropped it (`nothing went out for
  the last press`).
- **AutoSpellTier stepped down twice more, each lower tier cast** (row 48): Refresh III to
  Refresh II at an OK in a lock (19:07:21, held, released at +2.72, started) and Haste II
  to Haste at an OK with nothing busy (19:08:23). Both in the first wording. Not seen
  still: a plain press and an unavailable spell.
- **Who moved the target** (row 47). Of 80 deaths of the mob he was fighting while engaged,
  50 drew an auto-target, one a `server target` with no message, 21 a `status 0` and four
  his own switch (one in the frame of the death, three 3.8 to 5.0s on). Four drew nothing:
  the next line had him on a mob no packet had named, 0.9 to 6.7s after the death - at
  18:51:48 with `<t> none`, at 19:13:40 and 19:19:53 with `<t>` still on the corpse.
- **The rest read as built.** 749 presses swallowed for TP and 45 held ones dropped for it;
  28 weaponskills swallowed at a corpse, 0.02 to 1.57s after its `fell`; two that left as
  the mob died were never answered and freed the bar at once, the next starting 0.93s
  after the death at 19:19:58. Of 105 weaponskills that left, 101 were answered with a
  start or a finish (four with the start lost, one too far, message 78) and one was
  refused for sight. A Stun mashed through its own cast was let go on its recast eight
  times: four left, two refused and two unanswered. Six starts had no finish by the cast
  time plus 0.4s: two Stuns whose finish came 0.3 and 0.4s later, and four that never
  came (a weaponskill, a Sleepga and two Stonega). No cursor was left without its arrow
  (row 38), nothing was pressed under another's arrow (row 24), and no Trust was refused
  by a system message (row 43): two of GearSwap's own Trust casts were refused with
  message 17, sent 2.44 and 2.45s after a Trust's finish, where seven sent 2.51 to 2.56s
  after went. Nothing was held at his death at 18:58:13: no cure had been pressed, and his
  Trusts fell in the same second.

## A press near ready with nothing busy (Kevin, 2026-11-25)

Asked "Hold a nothing-busy press that is under two seconds from ready?" on the corrected
figures above, Kevin: "Yes, hold it".

- **With nothing busy and nothing held on its recast, a press is judged against a lock of
  nothing.** One whose recast has 0.7 to 2s to run is held, and released when the recast
  reads ready, as a press waiting past a lock is. A cursor's OK is judged the same way.
  Until now it went as pressed at any recast, and GearSwap aborted it above 0.8s.
- **One 0.7s or less from ready still goes as it is** (Kevin: "Leave 0.7s and under",
  over holding every press on its recast until it reads ready). 13 of 13 with 0.08 to
  0.73s left went and started, and held they would each have waited that out.
  `NEAR_READY` in `queue.lua`. The cost: a press at 0.8s waits 0.8s where one at 0.7s
  goes at once.
- **One more than two seconds from ready goes out as before**, for GearSwap or the game
  to refuse.
- **GearSwap no longer steps such a press down itself** (found by review). For the 37
  spells in its `spell_stepdown` table (`Sel-Mappings.lua`: Sleep II, Sleepga II, Gravity
  II, Aspir II and III, the Raises and Reraises, the -ra bar spells, the Lullaby and
  Threnody IIs, Tonko: Ni) its `check_recast` casts the next tier down in place of
  aborting. So with nothing busy a Sleep II pressed 0.8 to 2s from ready went as Sleep
  at once, and held it now waits for Sleep II, as one pressed in a lock always did. The
  eight presses the decision rested on were Sleepga and Haste II, which that table does
  not hold. Kevin was told in the report, his to overturn.
- **While it waits** the queue is engaged though `busy()` stays false, as it was for a
  wait past a lock: a re-press replaces it and sends nothing, however near ready by
  then, and a newer press that is ready takes its place and goes on the next frame.
- **The spell tier walk is unchanged** (Kevin: "Keep passing it by"). With nothing
  engaged it still walks past a lower tier with any recast running, for one that is
  ready now: `refused_on_recast` keeps its test, and only the press path's own changed.
  The spell that was pressed, kept as "near enough ready", is now held where it was sent
  to be refused.
- **Debug** writes the lines a held press always wrote: `hold <name>`, `<name> waits
  <n>s on its recast`, `release <name> after <n>s`. A press that goes within 0.7s of
  ready writes `not held: <name> on recast <n>s, lock 0.00s`, as it did.
- **Two specs that predate the branch were changed, with Kevin's go-ahead** ("Yes,
  change both"): `queue_spec`'s "is not held with no lock running" now asserts the press
  is held, and the first press of `service_spec`'s "sends the next press at once after
  one on its own recast" moved from 2s to 3s from ready, where it still goes as pressed.

**Unverified in a live client** (row 53): all of it, and an ability. GearSwap aborts an
ability with more than 0.5s of recast left, so one 0.5 to 0.7s from ready is still lost
as it was; the 13 samples behind 0.7 are all spells.

## The first run on `625391e`: the words and assist (Kevin, 2026-11-25, 19:43 to 20:38)

Kevin: "new log in the directory. Commit hash at the top of the file". 5,152 lines of
`debug.log` with the chat log beside it, on `625391e`: `8e4a72a`'s target words and
assist, without `15738b7`'s hold. Buffing as RDM in Port Jeuno, the assist presses in
Rabao, then Walk of Echoes [P1] as BLU with GearSwap's own buffs running.

- **A press Kevin did not mean to make**: "I saw `/ma "Anvil lightning"  <t>` in the
  log... and my finger was no where near that button to press it". The bar did take a
  press of that slot, `no target for Anvil Lightning, status 1` at 20:34:12, the only one
  of it in the run. Nothing was cast: nothing was targeted, GearSwap passed the line on
  with its two spaces, and the game answered "A command error occurred".
  - That line is written only for a press the action service fires, so it is neither
    the queue sending something again nor GearSwap acting on its own.
  - It came 3.68s after his mob fell, with `<t>` empty, 1.26s after his last Expiacion
    press and 0.53s before his own `out switch target`: he was picking a target.
  - **What pressed it is not in the log.** Only an `assist` press says. In the shipped
    map the D-pad under either trigger is the crossbar's slots 5 to 8, so a D-pad press
    for the game's targeting made with the trigger still down fires one; a click on the
    slot and a key through the keyboard map are the other ways in. Open: where that slot
    is bound, and a debug line for what pressed a slot.
- **A release under its word goes, with GearSwap handling it** (row 50). Of 28 releases 23
  cast, and the packet left within 0.05s of each of the 25 that left. Three left none,
  each a mash's repeat GearSwap dropped behind its own WS buff with the weaponskill
  already sent and started; one went unanswered (Erratic Flutter, 20:21:42) and one lost
  its target. No release drew "A command error occurred": the four in the chat log were
  presses made with nothing under `<t>` (Expiacion twice, Black Halo, Anvil Lightning),
  sent as typed. Not exercised: GearSwap off, and a target changed before the release -
  there is no `aimed at` but `<me>`'s, and no `nothing names`.
- **A cursor's pick of yourself goes under `<me>`** (row 51): six of six, each `<name>
  aimed at <me>` and each cast landing on him. No pick of anyone else, so `<lastst>` is
  still open.
- **Assist without the alias works** (row 52). 13 presses before any target each wrote
  `assist pressed, a gesture or a key`, with "assist has no target yet - //hud assist
  <target>" in chat and no packet. `//hud assist zaon` at 19:59:03 wrote `assist target
  set: /assist zaon`. The 25 presses after it, in seven seconds, drew six `out assist`
  packets 1.21s apart: the game sends one no more often than that. One `out assist`
  before the target was set (19:58:56) followed no press, his own typed command most
  likely. `//alias` was not checked.
- **AutoSpellTier wrote its one line** (row 48): `at OK: Refresh III on recast 2.63s, lock
  0.44s; down to Refresh II`, held, released under `<me>` and cast - for "No effect",
  Refresh III being on him already, its recast 0.19s past the grace.
- **Standing aside with GearSwap's buffs running** (row 45): it stood aside 23 times
  (Cocoon, Nat. Meditation, Erratic Flutter, Unbridled Learning, an item) and let nine
  presses go. Five started, two were refused by the lock (message 90), and for two
  GearSwap sent its WS buff in the press's place.
  - **One Expiacion took 13s to go** (20:27:24 to 20:27:39). Let go 0.13s after Unbridled
    Learning's finish, it became GearSwap's Berserk and a weaponskill 1.09s on, which was
    refused: GearSwap's own Diffusion had left 0.18s before it. Held again, it lost the
    next window to Mighty Guard, sent 0.38s after the ability and counted as the bar's
    own for leaving within two seconds of that weaponskill, so nothing stood aside in
    its lock; and the one after to Nat. Meditation, sent 2.54s after the finish, 0.18s
    ahead of the release. It went behind Aggressor at 20:27:39.
- **Who moved the target** (row 47): of 98 deaths of the mob he was fighting while engaged,
  69 drew an auto-target, 24 a `status 0`, two his own switch, and three nothing until a
  line had him on a mob no packet had named, 0.4 to 2.9s on.
- **The locks held**: no release was refused.

## The first run on `15738b7`: the hold with nothing busy, and `<lastst>` (Kevin, 2026-11-25, 20:54 to 21:54)

Kevin: "There is a new log in the logs directory". 3,830 lines of `debug.log` with the
chat log beside it, on `15738b7`, the hash on the file's first line. RDM in a party of
six with GearSwap on: buffs in Kamihr Drifts, then a Sortie (Outer Ra'Kaznar [U2]) from
20:56 to a wipe at Aita at 21:52.

- **A press near ready with nothing busy is held, and goes** (row 53). Three OKs of Haste
  II came 1.18, 1.52 and 1.62s from ready with nothing busy: `at OK: Haste II on recast
  1.62s, free; near enough ready, kept`, `hold Haste II`, `Haste II waits 1.60s on its
  recast`.
  - Two were released when the recast read ready, 1.18 and 1.51s on. Each packet left
    5.00 and 5.01s after the last Haste II's finish, and each started (0.36 and 0.71s
    later): a release at a recast reading zero is taken.
  - The third (21:11:50) he OK'd again 1.56s on, with 0.05s left. That one was held in
    the first's place, released 0.05s later and started. Nothing shows a held press on
    the bar, which is the likeliest reason for the second OK.
  - Three with 0.08, 0.40 and 0.57s left went as pressed, and each started.
  - The chat log has no `Abort: [...] waiting on recast.` for a spell in the hour. Its
    one is Saboteur's, pressed 150s from ready, which goes out as before.
  - Not exercised: a plain press (all six were a cursor's OK), and an ability.
- **`<lastst>` takes a pick from the line the queue keeps, once the handler has
  answered** (row 51), with GearSwap on. 116 sends wrote an `aimed at` line: 67 under
  `<lastst>`, 35 under `<t>`, 13 under `<me>` and one under `<p1>`. By the chat log's own
  cast lines each landed on its pick, as far as a name can say: every id drew one name
  throughout, the six players' among them.
  - Of the 57 under `<lastst>` with a pick of their own (the other ten were a lower tier
    standing in), 19 picked someone other than the pick before: 18 at a release and one
    a frame after its OK. The plainest is a round of Shell V at 20:54:58, five party
    members picked one after another, each released under `<lastst>` and each landing on
    its own.
  - **Inside the OK it still names the pick before.** The ten sent under it there were
    each the same id as the pick before. A new pick went under `<t>` where he had it
    targeted, under `<p1>` once (Refresh III on Zaon, 21:32:39, cast at once), and once
    nothing named it: `nothing names 21000866 yet` for a Bind at a mob that was not his
    target (21:49:16), sent a frame later under `<lastst>` and cast.
  - So a cursor cast at a mob that is not your target costs one frame, and at anyone in
    the party nothing. Not exercised: GearSwap off, and a player outside the party.
- **AutoSpellTier stepped down twelve times, and twice where it was not wanted** (row
  48). Ten at an OK and two at a release, ten casts in all.
  - Fire V through a mash, as meant: `at OK: Fire V on recast 9.08s, lock 1.45s; Fire IV
    on recast 8.83s; down to Fire III`, and at 21:31:45 to 21:31:55 Fire IV, III and II
    one after another, two of them settled `at the release` of a tier held in a cast.
  - **Haste II to Haste, twice, both on Llara** (21:00:28 and 21:22:25): a round of Haste
    II on the party, the next one OK'd inside the last one's lock, its recast 4.43 and
    4.57s off. The first cast gave Haste; the second had "No effect", and he cast Haste II
    on Llara 10s later.
  - Gravity II to Gravity once (15.83s off, nothing busy), which landed.
  - Kevin, the same evening, of Refresh III on the run before: "I don't want Refresh III
    being downgraded to Refresh II, but I also don't want to build in a bunch of
    exceptions which are my preference", and that it should be opt-in per binding rather
    than one global switch. Open: how the binder sets it.
- **Standing aside** (row 45): 17 times, nine for a Fire sent from outside the bar and
  eight for an item. One press was let go for it (Black Halo, 21:51:03, 2.63s into the
  lock) and started.
- **Assist** (row 52): 59 presses, 26 `out assist`. `//hud assist zaon` and `//hud assist
  Zaon` each wrote its `assist target set:` line.
- **Dead, the bar still takes a press**: seven presses of Temper II and Gain-INT after the
  wipe (21:52:36 to 21:52:43) each went to GearSwap, which answered `Abort: You are
  dead.`, and four of them were held 0.5 to 0.6s behind the one before. Nothing was lost
  by it.
- **The locks held**: 80 releases, 76 cast (two with their start packet lost, both
  landing by the chat log), the other four those presses while dead. 12 of 12 deaths of
  the mob he was on drew a `status 0`.

## The rest of that session on `15738b7` (Kevin, 2026-11-25, 22:10 to 23:50)

Kevin: "new log in the logs directory". The same `debug.log` grown by 2,185 lines, its
first line still naming `15738b7`: BLU in a Domain Invasion in Reisenjima, then DRK in
Bibiki Bay with GearSwap casting Absorb-ACC, Absorb-TP, Hasso and Trusts of its own. No
tiered spell was pressed and the only cursors were three Glutinous Darts at his target,
so it says nothing of rows 48, 51, 53 or 54.

- **Nothing new went wrong.** Six releases, each cast, and GearSwap wrote no `Abort:` in
  the hundred minutes.
- **Standing aside** (row 45): 64 times, for Absorb-ACC (19), an item (13), Hasso (11),
  a Trust (12), Absorb-TP (6), Bio (2) and Drain II (1). Four Guillotine presses were let
  go in a spell lock's last second. One started; three were refused by the lock (message
  90), sent 1.89, 2.38 and 2.42s after the spell's finish, and each went on the mash's
  next press 0.5 to 1.7s later.
- **System message 298, twice more** (row 43): GearSwap's Joachim with five alter egos
  out, at 23:07:16 and 23:07:18, 0.57 and 0.59s after it left and beside "You have
  called forth your maximum number of alter egos." Three sightings now, none of the
  other five.
- **The spell lock's bracket, again**: GearSwap's own Trust casts sent 2.04, 2.27 and
  2.55s after a spell's finish were refused ("Unable to cast spells at this time."), and
  each from 3.14s on started. Inside what was measured (refused up to 2.58s).
- **A weaponskill whose target died as it started** (row 36): Expiacion at 22:26:25, the
  mob falling 0.02s after the start. `the target died, no finish to come, lock 2.40s`,
  the lock over 2.81s after the start, and nothing sent inside it.
- **Anvil Lightning** at 22:26:10 was a cast he made, at a Domain Invasion's pack; its
  mash's second press was held and dropped at 18s of recast. No press he did not make
  shows in this part.
- **A mash past the fight**: ten Expiacion presses with nothing targeted and status 0
  went to the game, which answered "You can only use that command during battle." three
  times.

## A night on `15738b7` beside a -ga loop (Kevin, 2026-11-26, 00:25 to 03:50)

Kevin: "Another log to look at, I haven't updated the code yet". The same `debug.log`,
9,014 lines on and still `15738b7`, the queue's clock starting over at a restart. DRK/BLM
in Escha - Zi'Tah, an hour in Bibiki Bay, then Zi'Tah twice more with Blizzaga and
Thundaga cast in a loop from outside the bar. No cursor slot and no tiered spell of the
bar's, so it says nothing of rows 48, 51 or 54.

- **The bar's own sends were clean.** 93 releases: 91 cast, and two weaponskills' targets
  died before an answer. 330 weaponskills started, and no release was refused.
- **About a hundred refused spells, all but one from outside the bar.** "Unable to cast
  spells at this time." (message 17) 101 times: Thundaga 43, Blizzaga 34, Firaga 3, a
  Trust 12. They left about every 1.2s whether a cast was running or a lock was on, the
  queue stood aside 119 times, and what sent them is not in the log: GearSwap's own
  casting or a macro.
- **Standing aside** (row 45): three presses let go. A Guillotine and a Drain II started;
  an Absorb-ACC, sent 2.28s after a Sleep II's finish, was refused and went on his next
  press 0.72s later.
- **Recast waits** (rows 34 and 53). A Stun pressed in a weaponskill's lock with its recast
  0.73s past the lock's end waited, was released when the recast read ready and started
  0.47s later. A Dread Spikes pressed 0.23s from ready with nothing busy went as pressed
  and started. No plain press met the hold with nothing busy.
- **GearSwap aborted six presses for their recast**, each an ability far from ready, which
  goes out by design: Third Eye five times in a two-second mash at 28 to 30s, Meditate at
  9s.
- **The finish backstop runs ahead of a cast with no Fast Cast.** 27 times a spell was
  counted finished at `cast_time` plus 0.4s and the real finish came 0.02 to 0.37s later,
  median 0.21s, three of them an interrupt: a 3s cast counted at 3.41s and finished at 3.6
  to 3.8, the 2s -ga spells at 2.41 against 2.4 to 2.6, a 1.5s cast at 1.91 against 2.0
  to 2.1. No release fell between the two and each real finish replaced the counted lock, so
  nothing was lost. Where the finish itself is lost the lock would end that much early.
  **Kevin: "Yes, 0.8s"**: the margin (`SPELL_SLACK`) is two of the server's beats now,
  which would have covered all 27, at 0.4s more wait when a finish never comes. The
  constant is shared with the wait on a spell sent and never answered, which moves with
  it ("Both at 0.8s"): a spell the server drops in silence holds the bar 0.4s longer.
  Sixteen specs that predate the branch stepped the clock by the old margin and were
  moved to the new one with his go-ahead ("Yes, change them", "Yes, move them too"),
  three of them renamed from one beat to two ("Reword them"), and a seventeenth, which
  the review found no longer told a late finish taken from one ignored, was re-timed
  ("Yes, re-time it"). In-client row 55.
  - **What 0.8s does not cover** (from review): the wait on a spell sent and never
    answered runs from the send, a median 0.59s ahead of the start, so with no Fast
    Cast its finish comes about 1.0 to 1.4s past the cast time and that wait still
    ends first. It moved for the cost alone. And the worst of the 27 was 0.77s against
    the 0.8, two frames to spare, so a rare `no finish yet` in row 55's run would not
    by itself say the margin is wrong.
- **He died at 03:34:16 with nothing of the bar's held.**
- **Who moved the target** (row 47): of 48 deaths of the mob he was on, 32 drew a `status
  0` and 16 an auto-target.

## The first run on `b7499d0` (Kevin, 2026-11-26, 18:33 to 19:48)

Kevin: "new debug log in the directory". 1,117 lines, the first on `b7499d0`, with the
tier flag and the 0.8s margin in. BLU pulling packs in Kuftal Tunnel with Anvil Lightning,
then a melee job in Bibiki Bay. No tier line was written and no spell he cast has a tier,
so it says nothing of row 54.

- **The bar's own sends were clean.** 12 releases, each cast; 77 spells and 22
  weaponskills started.
- **Two finishes never reached the queue, and each kept the bar busy 9.5s.** Anvil
  Lightning at 18:43:36 and 18:52:28, the two largest pulls of 27 (19 Records of Eminence
  kill lines apiece): a `start spell`, then nothing until `no finish yet for the last
  start` 6.8s later, and its 2.7s lock after that. No `fell` line either. The chat log
  has no damage line and no `defeats` line for those two, where it has both for every
  other cast, so another addon missed them too. The cast itself took about a second and a
  half, the kills being in chat a second after the start: the wait is the resource's cast
  time, 6s, plus the 0.8, and with Fast Cast the real cast is a quarter of that.
  - He pressed nothing in either window, so nothing was held. A press there would have
    waited up to 8s.
  - A finish seen another way, by the recast it begins, was built and dropped the same
    day: the client's recast does not move without the finish packet. See "A recast for
    a lost finish" below.
- **A send the server never answered kept the bar busy 6.8s** (18:48:28): an Anvil
  Lightning left and drew no start and no refusal, and the wait ran the 6s cast time plus
  0.8. One press of it 1.6s on was swallowed as `already going`. Nothing in the client
  says a cast did not start, so that wait stands.
- **The hold with nothing busy on a plain press, and a target changed before the
  release** (rows 53 and 50), in one press: an Anvil Lightning 1.68s from ready was held
  (`Anvil Lightning waits 1.68s on its recast`) and dropped as its recast read ready,
  `dropped Anvil Lightning: nothing names 17489975 (<t> none, <lastst> none)`. That mob
  was alive; he had let go of it, and cast at another 0.5s later. Before the hold the
  press went out and GearSwap aborted it, so either way it cost one more press.
- **A press 9.5s from ready went as pressed** and GearSwap aborted it, by design.
- **The 0.8s margin** (row 55): of 77 spell starts none was counted finished ahead of a
  finish that then came; the two it counted never had one. Fast Cast was on, which is
  not the case the row asks for.
- **Standing aside** (row 45): 40 times, for a spell 18, a weaponskill 12, an item 5 and
  an ability 5. One press was let go, an Expiacion, which started.
- **Cursors**: seven OKs, five Glutinous Darts at his target and two Plenilune Embraces at
  himself, sent under `<t>` and `<me>`.
- **GearSwap's own**: ten Trust casts refused by the lock, sent 2.52 to 2.53s after a
  finish, and `Abort: You don't have access to [Ground Strike].` five times for a slot
  pressed on a job that lacks it.

## A recast for a lost finish, built and dropped (Kevin, 2026-11-26)

Offered after the run above: a spell's recast begins at its finish (row 48), so while a
start waits for its finish, a recast beginning on that spell would say the cast is over
whatever became of the packet. I put it at 75% that the client's table moves for a
finish no addon was shown, and said that was unverified. **Kevin: "Yes, build it".**

- **What was built**, under TDD and never committed: the started spell's recast read at
  the start and ten times a second after (a new `spell_recast(id)` dep, off the client's
  table by the spell's `recast_id`); a reading above the one before it taken for the
  finish, since what is still running at a start only falls; the spell's lock from that
  tick; the start left open, as when its wait runs out, so the finish itself would
  replace the lock; and a `debug` line.
- **Why it cannot work**, found while building it:
  - The finish packet is what carries the recast: `Recast` is a field of the incoming
    `0x028` in Windower's `fields.lua` (`func.incoming[0x028].base`), and GearSwap reads
    it as `act.recast` on a category 4 (`helper_functions.lua`). `0x119` lists ability
    recasts alone. So a client that never gets the finish has nothing to start one from.
  - One event says the same, read three times: his Sleepga of 2026-11-25 on `3c91c54`
    (the Dynamis [D] run, 19:20:53; clock 3100.62). The start came and no finish, in
    the queue's log and the chat log alike. The cast landed all the same: the Sleepga
    at 19:21:05 drew "No effect" from the Mender it was aimed at and from a Wyvern and a
    Shadowstalker, all three hit at 19:20:48 and so awake then, with no other sleep in
    the chat log between. Its end is taken 1.22s
    after its start, as the next Sleepga's was, and its recast about 9s (`not held:
    Sleepga on recast 8.67s` 0.31s after a later finish). Against that the client's
    figure read **2s or less** at +1.4s (`OK Sleepga`, `hold Sleepga` with the cast
    still counted as running, where more than 2s is `not held`), **3.5s or less** at
    +3.4s (`hold Sleepga, replacing Sleepga`, 1.49s of the counted lock left) and
    **nothing** at +4.9s (`release Sleepga after 1.50s`, with no `waits` line). That
    release drew `no answer to the last send`; the next Sleepga, sent at +9.1s, started.
  - Nothing in the other logs reads a lost finish's recast: no press of the same spell
    followed either Anvil Lightning inside its recast.
  - My 75% was wrong; with this it is about 10% that the read would ever have fired.
- **Kevin: "Drop it".** The four files were restored and nothing of it is in the tree.
- **Other starts with no finish**, seen in that Dynamis run while looking, and not
  acted on:
  - A Stonega started at clock 2666.21, the mob under `<t>` `fell` 1.19s on, and neither
    a finish nor an interrupt came. Stonega was sent again 2.0s after the counted finish
    and started, so the first never finished.
  - A Stonega started at 3089.30, message 5 ("Unable to see") came 0.87s on, and again
    nothing more; the one sent 2.78s after that message started. Whether the message was
    the spell's or a swing's is not known: the queue reads messages 4 and 5 only for who
    the server has you fighting.
- **Open, Kevin's call: the cast time actually seen.** The 19 Anvil Lightnings that did
  finish in the `b7499d0` run did so 1.53 to 1.69s after their start, against the
  resource's 6s. Waiting the longest recent start-to-finish seen for a spell plus the
  0.8s, capped at the resource's time, would have kept the bar busy about 5.2s in place
  of 9.5s. The risk is a cast longer than any seen (Fast Cast gear missing, a slow):
  the wait ends early, as it does now when a cast overruns the resource's time. Not
  built.
- Set aside: MP falling as the sign of a finish. GearSwap's midcast swap moves max MP
  at the start of a cast, so a fall there says nothing.

## The tier flag on the binding (Kevin, 2026-11-25)

Kevin, after the two runs above: "I don't want Refresh III being downgraded to Refresh II,
but I also don't want to build in a bunch of exceptions which are my preference. I'm
trying to think of a way that AutoSpellTier can be opt-in per spell rather than a global.
setting." His own two ideas he did not like: another step in the binder wizard, and a
pseudo-spell `Fire V (Auto)` for every spell that can tier. A list of spells in the config
and switches by kind of magic he ruled out: "I want it tied specifically to the binding,
not the slot."

What a lower tier does on a target that already has the higher one is the whole case
for it: Refresh III to Refresh II and Haste II to Haste were each cast for "No effect",
where Fire V to Fire IV is the point of the thing.

Decided, each Kevin's:

- **A toggle on the binding's own row** in the binder's layer step ("Yes, build it"),
  over one on the target step: the window opens on that step and comes back to it after
  every bind, and each row there already is a binding.
- **`tier=auto`** on `bind` and `tier <address> [auto|off]` as the verb.
- **The global switch goes**: `//hud autospelltier`, its row on the settings window's
  `global` panel and `core.lua`'s key. Never released, and nothing migrates.
- **A ladder never steps down**: a `sneak`, `invisible` or `reraise` slot's pick goes as
  the ladder picked it.

Built:

- `spell_tier.lower` reads the record's `tier == "auto"` in place of the setting, and
  the tier that stands in carries it on, so a release can step a held lower tier down
  again, as row 48 saw under the switch. `spell_tier.has_lower(record)` says whether
  anything under a binding's spell could stand in, off the resources alone: true, false,
  or nil for a name they do not know.
- `commands`: `tier=` is a fourth marker. `bind` reads it and so does `parse_action`, a
  gesture's, which still refuses the three that need a slot. The `tier` verb is
  `override`'s one-field write, and bare it says how the binding stands. `list` and
  `describe_action` print `tier=auto`. Refused on anything but a spell, and where
  `has_lower` answers false; taken where it answers nil.
- `binder`: a leaf row whose record `has_lower` gets a toggle rect at its far end, hit
  before the row it lies on, and a click writes that layer's entry back with the flag
  flipped. **It is drawn on the category column's prims**, which the layer step has no
  other use for: two specs that predate the branch pin the window's prim inventory, and
  a pool of its own would have changed both.
- `core` and `lib/commands`: the verb, its help lines, the reserved word and the
  settings row are gone. `//hud autospelltier` is an unknown command now.

From review (round 1, clean; these were its optional notes):

- The binder shows the toggle on a binding that ALREADY carries the flag, whatever is
  under its spell: the CLI takes the flag for a name the resources do not know, and it
  could not be seen or cleared on the row otherwise.
- A bare `tier <address>` on an empty slot says only that nothing is bound, where it
  read as a refused write.
- `//hud gamepad bind`'s form names `[tier=auto]`.
- The word `auto` is held by three modules (the walk, the CLI, the binder). Rather than
  one shared constant - the walk's module is a constructor - a bar spec presses a slot
  the CLI flagged and one the binder flagged, so a drift between writer and reader
  fails.

Round 2, on the change with those in, was clean too. Its one note worth a live look:
**a long row can run under its toggle.** The row's own text is not cut before the
toggle, which leaves it about 418px at a 1080-line UI, some 40 characters, and the
toggle is hit first, so a click on the end of such a row would flip the flag in place
of opening the catalog. A layer's name and a long alias together can reach that
(`* > addendum-black: ma "Thunder Burst Nuke"`). Open, Kevin's call once he has seen
it: cutting the row's text with a `.` where a toggle is drawn, as a slot's label is
cut, is the fix on offer. Left as they are: `tier <address> maybe` answers the verb's
form without naming the word, and `list` prints `tier=auto` for a hand-edited record
that is no spell, which `bind` would refuse.

Not built, and nobody asked: a mark on the bar for a flagged slot (`list` and the
binder's row say), and a way to flag several bindings at once.

In-client row 54. The toggle's width (`BASE_TIER_WIDTH`, 190 at a 1080-line UI) is an
estimate of how wide `auto tier [ off ]` draws.
