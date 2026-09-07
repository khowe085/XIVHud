# Crossbar weaponskill gate

Move the weaponskill guard out of the GearSwap file (`Vanar_Blu_Gear.lua`,
`user_job_filter_precast`) and into the crossbar, so a press the game could
never honour is never sent to Windower at all.

## Why

The GearSwap guard runs *after* the press has already gone out - the crossbar
sends `/ws "Savage Blade" <t>`, the chat queue carries it, GearSwap's precast
filter cancels it. That works, but it costs a round trip per press, it only
protects a character whose gear file carries the guard, and a spammed macro
still fills Windower's chat queue on the way to being dropped.

Refusing at the press is also the rule this component already follows
everywhere else: the mount slot's dim and its dead press are one rule
(CLAUDE.md, roulette), and a weaponskill slot is *already drawn dimmed* below
1000 TP (`crossbar.lua:2615`, `render.lua:437`) while still firing. This closes
that gap.

## What does NOT move

`ws_buff_lock` in the GearSwap file guards GearSwap's own queued ability -> WS
chain, which the crossbar cannot see. The crossbar-side in-flight lock
substitutes for it only because the spammed presses never reach GearSwap in the
first place; GearSwap's own scheduled re-fire goes out through
`windower.chat.input` and bypasses the crossbar entirely, so it is unaffected.
The `player.tp < 1000` half of `user_job_filter_precast` becomes redundant once
this ships and can come out of the gear file; the lock half should stay until a
live client says otherwise, since it also covers presses from game macros.

## Decisions (Kevin, 2026-09-05)

- Gate on: **TP below 1000**, **a weaponskill already in flight**, **nothing
  targeted**, **not engaged**, **the target is not an enemy**, and **out of
  melee range**.
- **Weaponskills only.** An unaffordable spell still sends and the game refuses
  it, exactly as today - the MP read is up to 200ms stale and a locally refused
  cast you could just afford would read as a dead button.
- A refused press is a **silent no-op**: nothing sent, nothing said, no flash.
  The slot is already visibly dimmed, which is the signal - the same posture an
  empty slot press has.
- **A setting, default on**: `//hud crossbar wsgate [on|off]`. The melee range
  was a config key only at first, edited by hand, on the grounds that it is a
  calibration knob rather than something to flip mid-fight - **reversed by
  Kevin the same day**: `//hud crossbar wsgate range <yalms>` sets it, because
  it is settled by walking in on a mob a step at a time (testplan K2.6) and
  alt-tabbing to a text file between steps is the wrong loop. The CLI refuses
  a value the module would fall back over, rather than storing one the player
  would believe.
- Melee range: `distance < melee_range + your model size + the target's`,
  the shape `targetbar/logic.lua`'s `casting_state` uses, shipping at
  **6** - a guess, flagged as such in the file, to be settled in a live
  client the way expbar's `text_width_ratio` was. It ships LOOSE on purpose
  (Kevin, 2026-09-05, after review round 3): the directions are not symmetric,
  so row O10 records the closest distance actually refused and the value is
  tightened to that rather than raised to it. It was 3.0 in the first draft,
  which put the cutoff around real melee reach rather than past it.

### Settled during implementation (Kevin, 2026-09-05)

Wiring the gate in broke 20 existing tests, none of them about weaponskill
legality - they press the Savage Blade slot whenever they want to fire
something. Three calls came out of that:

- **The shared fixture describes a legal world.** `war_player()` is engaged
  (status 1, the resource fixture's own number) and `build_world`'s target mob
  carries `hpp`, `is_npc`, `distance` and `model_size` where it carried an id
  alone. Every assertion in those tests is untouched; only the world changes.
  Without the extra fields every gate rule reads as unknown and allows, so the
  fixture would have described a world the target and range rules could never
  fire in.
- **`in_flight` ships at 1s, not 3.** It is the one rule that can kill a button
  that would have worked, and the finish match rests on an actor id nobody has
  read in a live client. A second covers the stale-TP window many times over.
  The cost, taken knowingly: it does NOT cover a GearSwap ability chain's 1.1s
  re-fire, so `ws_buff_lock` should stay in the gear file.
- **`get_mob_by_target("me")` is allowed.** One existing test asserted the
  crossbar asks the client for `"t"` and `"bt"` alone; the token is vetted
  repo-wide (speedcheck ships it, CLAUDE.md documents it) and the crossbar's
  own list was simply narrower. That test's list gained `"me"`, with the
  reason written beside it.
- Three of the weapon-layer tests fire the same weaponskill twice half a second
  apart to prove a layer moved. Their clocks now advance past the lock as well
  as past the client interval - a press no player could make inside the lock's
  own second.

## Unverified, and needing a live client

1. **`melee_range` is a guess.** Nothing in this repo and nothing offline
   gives an authoritative weaponskill reach. The targetbar ports DistancePlus'
   magic/ninjutsu/gun/bow/xbow bands and has no melee band at all. Config, with
   the comment saying so.
2. **Ranged weaponskills get no range gate.** Archery and Marksmanship
   weaponskills reach far past any melee number; porting their band would mean
   promoting the targetbar's DistancePlus code to `lib/` (cross-component
   `require` is forbidden), which is scope of its own. A ranged weaponskill is
   therefore gated on TP, engagement, target and the in-flight lock, never on
   distance. Its skill is read off the resources the same way `catalog.lua`
   filters the picker.
3. **`mob.valid_target` is not read.** I have not confirmed the field exists,
   so the enemy test uses only fields this repo already reads in anger:
   `is_npc`, `in_party`, `hpp`.
4. **The in-flight lock's backstop timeout** (3s) is a first guess. It must
   outlast a GearSwap ability chain's re-fire delay (1.1s in the attached gear
   file) or the lock releases before the weaponskill it is waiting on goes out.

## Shape

### New pure module: `src/components/crossbar/wsgate.lua`

`new(deps) -> self`, the shape `retry.lua` and `travel.lua` already use.
Pure: no client reads, no globals; the caller hands it facts.

```
self.defaults()          -- the config block defaults.lua seeds `config.wsgate` from
self.enabled()           -- settings().enabled ~= false: ships ON, so an absent
                         -- key reads as on (retry reads `== true` because it
                         -- ships off - the two are deliberately opposite)
self.allow(record, facts) -> boolean, reason
self.sent(record)        -- arm the in-flight lock when a `ws` press goes out
self.resolved()          -- our own weaponskill landed; drop the lock
self.clear()             -- zone, death, logout, detach
self.locked()            -- for the spec, and for a future dim
```

`facts` = `{ tp, status, engaged_status, target, self_size, now, ranged }`.

**`allow` refuses when, and only when, it is CONFIDENT:**

| condition | refuse | unknown reads as |
| --- | --- | --- |
| `record.type ~= "ws"` | never - not our business | n/a |
| the in-flight lock is up | yes | n/a |
| `tp < 1000` | yes | `tp == nil` -> allow |
| `status ~= engaged` | yes | `status == nil` -> allow |
| `target == nil` | yes | n/a |
| `target.is_npc == false` (a PC) | yes | `nil` -> allow |
| `target.in_party == true` | yes | `nil` -> allow |
| `target.hpp == 0` | yes | `nil` -> allow |
| `sqrt(distance) >= melee_range + sizes` | yes | either size or the distance `nil` -> allow |

Ignorance is never a refusal - the cost corner's rule, and the one that keeps a
login's first frames from reading as a dead bar. `distance` is the **square** of
the distance (`targetbar/logic.lua:451`); the sqrt is taken here.

Defaults:

```lua
enabled = true,       -- unlike retry, this ships on
melee_range = 3.0,    -- UNVERIFIED, see above
in_flight = 3,        -- backstop seconds; the lock's real release is the
                      -- weaponskill landing
```

### `crossbar.lua`

- Build `wsgate` beside `retry`, reading its config through the same closure
  idiom so `//hud crossbar wsgate off` lands immediately.
- `fire_slot`: for `record.type == "ws"`, gather the facts and ask
  `wsgate.allow` **before** `flash()` and before `actions.resolve`. A refusal
  returns having done nothing at all except `retry.sent(nil)` - a refused press
  is still a newer press, and nothing may outlive the moment it belonged to.
  (Same reasoning as the empty-slot branch immediately above it.)
- Facts come from the player service, never raw: `get_player()` for `tp` and
  `status`, `ctx.get_mob_by_target("t")` for the target and
  `ctx.get_mob_by_target("me")` for our model size - both memoized for the
  frame by `lib/player`, so the party list and the targetbar asking for the
  same mob costs nothing.
- The engaged status number is resolved from `res.statuses` by english name
  with a fallback constant, the way `travel.lua` resolves resting - never a
  hardcoded number alone.
- On a `ws` press that DOES go out, `wsgate.sent(record)` arms the lock.
- The `0x028` branch already handed to `skillchain.on_action` also feeds
  `wsgate`: our own actor id with `category == 3` is the weaponskill landing,
  so `wsgate.resolved()`. (`CATEGORY_RESOURCES` in `skillchain.lua:1056`
  documents the numbering.)
- `wsgate.clear()` on the zone-out chunk, on a dead status and on detach,
  beside the existing `retry.clear()` calls.

### `defaults.lua`

`wsgate = new_wsgate({}).defaults()`, the line `retry` already has, so there is
one place to tune.

### `commands.lua`

`wsgate [on|off]`, modelled on `retry` verbatim: no argument reports, the write
goes through `config_table("wsgate").enabled` so flipping the switch never
discards the tuned `melee_range`. One help line. The verb joins `VERBS`.

## Tests (TDD, spec first)

- `tests/components/crossbar_wsgate_spec.lua` - new. Every row of the table
  above, both directions; the unknown-reads-as-allow cases stated one by one;
  the lock arming, releasing on `resolved()`, releasing on the backstop, and
  surviving right up to it; `enabled()` reading an absent config as on and an
  explicit `false` as off; a non-`ws` record never refused.
- `tests/components/crossbar_commands_spec.lua` - the verb: report, on, off,
  a bad argument hinting, and the tuning surviving an off/on round trip.
- `tests/components/crossbar_defaults_spec.lua` - the block is seeded.
- `tests/components/crossbar_spec.lua` - the wiring: a refused press sends no
  command and does not flash; an allowed one is unchanged; the lock blocks the
  second of two presses and the `0x028` finish releases it.

Green means `busted` + `luacheck .` + `stylua --check .`.

## Review gate

Three blind rounds. Round 1 caught the gate reading `<t>` whatever the bind
aimed at (a weaponskill bound `<bt>` or `<st>` was silently refused), round 2
caught `Throwing` missing from the ranged skills, round 3 caught `now =
frame_now` defeating the module's own no-clock guard by turning a missing
clock into a frozen zero. All fixed, each with a failing test first.

Left open for Kevin at the cap:

1. **RESOLVED (Kevin, 2026-09-05): it ships ON**, and the engagement half of
   the risk is now closed - Kevin confirmed the same day that the game does
   not allow a weaponskill while not engaged (in-client question P, testplan
   row O9), so that rule refuses only what the game refuses anyway. The reach
   is the one guess left, and row O10 settles it. The reasoning, and the fact that this is a call rather
   than a safety claim, is written into `defaults()` itself. Original text:
   **The ship-ON posture against two unverified rules.** `defaults()` ships
   `enabled = true`, but the engagement rule is an assumption and
   `melee_range` is a guess - either can silently refuse a press that would
   have worked, on a button pressed constantly. The cast retry's precedent is
   to ship off until a client answers. Options: keep it on and settle it with
   rows K2.4/K2.6/O9/O10; drop the engagement rule until O9 answers; or ship
   the whole feature off.
2. **SETTLED IN A CLIENT (Kevin, 2026-09-05): `melee_range` is 4, expressed
   as the distance the target bar prints.** Three readings: a weaponskill
   landed at 3 and at 4, and at 6 it FIRED AND SPENT THE WHOLE 3000 TP.

   Both halves of the original design were wrong. The model-size term (copied
   from targetbar's `casting_state`) made the number unsettable - what the
   player reads is not what the setting meant, which is how a reach of 6 let
   a press go at a target bar 6 - so it is gone, and a huge mob is now
   measured like a small one. And the direction: the gate shipped loose
   because a press let through was believed to reach a game that refuses it
   harmlessly. It does not. Too loose costs 3000 TP, too tight costs a dead
   button, so this is the most valuable of the six rules rather than the most
   expendable. The comparison is strictly greater, so the number watched
   working is the number to type.
3. **LEFT AS IS (Kevin, 2026-09-05). The cast retry's re-send bypasses the
   gate.** `retry.step` -> 
   `send_command` never consults `wsgate.allow`, so a refused weaponskill can
   be re-sent a second later after you have disengaged or the mob has died,
   and the re-send arms no lock. Low impact (retry ships off) but the two
   features now disagree about the same press.
