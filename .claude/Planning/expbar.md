# Exp Bar - component plan

Status: draft, 2026-09-04. Scope: one component, `src/components/expbar/`, plus its
art under `src/assets/barfiller/` and four entry-point edits. The framework is
shipped - plan against the live contract in [CLAUDE.md](../../CLAUDE.md) and
`src/lib/core.lua`, not against any design doc. Sibling precedent and the model to
copy: `src/components/parambar/` (a bar that eases) and
`src/components/giltracker/` (a component whose whole world arrives as packets).

## Goal

The FFXIV experience bar for FFXI: one filling bar with a status line above it.
It is [pointwatch](https://github.com/Windower/Lua/tree/live/addons/pointwatch)'s
readout with the point totals drawn as a bar the way
[barfiller](https://github.com/Windower/Lua/tree/live/addons/barfiller) draws them,
and with everything pointwatch carries for Abyssea, Dynamis, sparks, accolades and
unity left out.

Decided with Kevin, 2026-09-04:

- component key **`expbar`**, alias **`eb`** (legal: 2 letters, no clash with a
  reserved verb, `all`, or `cb`/`pb`/`gt`/`ev`/`tb`/`pl`).
- art: **barfiller's own**, imported verbatim (see License below).
- the header carries **job levels**, plain (non-fractional) JP and merit counts,
  and pointwatch's `k`-formatted rate.
- the rate field **follows what the bar is filling with**, so a sub-99 character
  reads EXP/hr rather than a CP/hr stuck at zero.
- **three** bar modes, not two: a capped job without Master Levels fills with limit
  points toward the next merit, which is what the game's own bar does there.

## What it draws

```
+----+ WAR99/SAM49 (ML23) JP: 342 MP: 12 EP/hr: 12.6k
|icon|
+----+ [==============================----------]
```

**Settled in a live client** (Kevin, 2026-09-04). The header and the bar share a
left edge; the icon stands to the left of both and SPANS them, square and as tall
as the two rows together. The widget's origin is the icon's left, so the box core
clamps against is the bar plus that icon, and nothing draws left of the origin.
The font is 8pt: 11 drew far too large.

Two measures are DERIVED rather than chosen, both in `measure.lua`. The bar stops
a little past the longest line the header can print - the widest header at
`font_size * text_width_ratio` per character, plus an overhang - and the icon is
the height of the two rows it spans (`text_height + gap + bar height`), so it
grows with the font instead of being written down beside it and drifting. At the
shipped 8pt the bar is 286, the icon 18 and the widget 305, and `expbar_logic_spec` drives the real header to its longest
and measures it against the sample the sum is built on, so the two cannot drift.
`text_width_ratio` (0.68) and `text_height_ratio` (1.3) are estimates - Windower
cannot be asked how wide or how tall a string draws - and are config precisely so
a live client can settle them. The height one places the bar under the header and
sizes the icon, so it is the one to nudge if the rows sit wrong.

The icon's own art carries a gap of its own, and a different one per job: of its
64px square WHM's glyph starts 18px in and WAR's 4px, about 5px against 1px of
apparent space at this size. `job_icon.gap` is 1 because of that - nothing here
can even it out without cropping the art per job.

One text and three images: the main job's glyph, the bar frame and its fill. The
header is one of three strings; the bar is one of three fills; both come from the
same mode. The glyph is XivParty's own (`assets/xiv/jobIcons/<job>.png`), drawn
bare - it is gold with a dark outline, so it needs none of the tinted backing the
party list puts under the same art for its role colours. **The three are one
colour** (Kevin, 2026-09-04): the glyph's gold, the crossbar's gold `255,215,0`
for the text, and barfiller's fill art, which is already a gold gradient
(255,245,191 down to 214,111,0).

| mode    | when                                     | bar fills with              | rate shown |
| ------- | ---------------------------------------- | --------------------------- | ---------- |
| `exp`   | main job below the level cap             | `Current EXP / Required EXP`| EXP/hr     |
| `limit` | main job at the cap, no Master Breaker   | `Limit Points / 10000`      | CP/hr      |
| `ep`    | main job at the cap **and** Master Breaker | `Current EP / Required EP` | EP/hr      |

Header strings (`(ML%d)` appears in `ep` mode only, which is the whole difference
between Kevin's two templates):

```
exp    WAR75/SAM37 JP: 0 MP: 0 EXP/hr: 31.2k
limit  WAR99/SAM49 JP: 500 MP: 30 CP/hr: 8.1k
ep     WAR99/SAM49 (ML23) JP: 342 MP: 12 EP/hr: 12.5k
```

No subjob prints as `WAR99/---` (pointwatch prints `(---)`; the slash form is the
one Kevin's template asks for). `{MasterLevel}` is 0x061's `Master Level` byte,
shown plain - see Unverified below.

## Reference facts (verified 2026-09-04 against Windower/Lua `live`)

**`windower.ffxi.get_player()` carries no experience and no master level.** Verified
against the FFXI-Functions wiki page: it has `main_job`, `sub_job`,
`main_job_level`, `sub_job_level`, `merits` (allocations per category, *not* the
unspent count) and `job_points[<job>] = {jp, cp, jp_spent, ...}`. Everything else
this widget needs comes from packets.

**`0x061` (Char Stats)** - fields verified in `libs/packets/fields.lua`:
`Current EXP`, `Required EXP`, `Main Job`, `Main Job Level`, `Sub Job`,
`Sub Job Level`, `Master Level` (unsigned char at 0x65), `Master Breaker`
(a `boolbit` at 0x66 - the key item that unlocks Master Levels),
`Current Exemplar Points`, `Required Exemplar Points`.

**`0x063` order 2** - `Limit Points`, `Merit Points` (bit[7]), `Max Merit Points`,
plus `Limit Breaker`, `EXP Capped` and `Limit Point Mode` flags. Order 5 carries
per-job `Capacity Points`/`Job Points`, which we do **not** need: `get_player()`
answers both.

**`0x02D` (Action Message)** - `Param 1`, `Param 2`, `Message`. Every point gain
arrives here. Message ids verified against the Windower `action_messages` resource:

| id  | text                                                                | amount is  |
| --- | ------------------------------------------------------------------- | ---------- |
| 8   | `${actor} gains ${number} experience points.`                        | Param 1    |
| 105 | `${actor} gains ${number2} experience points.`                       | **Param 2**|
| 253 | `EXP chain #${number2}!${lb}${actor} gains ${number} experience points.` | Param 1 |
| 371 | `${actor} gains ${number} limit points.`                             | Param 1    |
| 372 | `Limit chain #${number2}!${lb}${actor} gains ${number} limit points.` | Param 1    |
| 718 | `${actor} gains ${number} capacity points.`                          | Param 1    |
| 735 | `Capacity chain #${number}!${lb}${actor} gains ${number2} capacity points.` | **Param 2** |
| 809 | exemplar points (pointwatch)                                         | Param 1    |
| 810 | exemplar chain (pointwatch)                                          | ? Param 2  |

**`windower.packets.last_incoming(id)`** returns the last packet with that id and
its timestamp, both nil if none has arrived - core API, documented on the
Packet-Functions wiki page. pointwatch uses it at load to seed itself from packets
that arrived before the addon did; this component needs the same, because `attach`
happens at login and on every `//hud slot` switch, and nothing re-sends 0x061.

**barfiller's art**: `bar_bg.png` is 472x5 RGBA, `bar_fg.png` is 1x5 stretched to
468 at `bg.x + 2`.

**pointwatch's rate**: a `{timestamp = points}` registry per point type, pruned at
600s; `rate = floor(total / oldest_sample_age * 3600)`, and 0 until some surviving
sample is more than 30s old. It counts idle time inside the window, so the rate
decays while you are not earning - keep that, it is the behaviour people read these
addons for.

## Reference defects - fixed here, not ported

1. **Message 105 reads the wrong parameter.** Its resource template puts the amount
   in `${number2}` (Param 2); pointwatch and barfiller both pass `Param 1`. Same
   shape for **735** (capacity chain), where `${number}` is the chain number and
   `${number2}` is the points - so pointwatch's CP/hr records the chain counter as
   the gain. ~75%: the `number`/`number2` -> `Param 1`/`Param 2` mapping is inferred
   from the templates and confirmed only for the ids the references get right.
   **Live check before EB2 ships**: log both params for 8/105/253/718/735 and see
   which one carries the number the chat line printed.
2. **pointwatch misses EXP chains entirely** (no 253), which in a party is most of
   the exp earned. barfiller has it; we take barfiller's set.
3. **pointwatch never advances `ep.current` from a message** - its 809/810 branch
   registers the sample for the rate and then only wraps at the master level. So its
   EP figure moves only when a 0x061 arrives. Ours advances all three counters the
   way barfiller advances exp, so the bar moves per kill.
4. **barfiller's `local last_update = 0` is declared inside the loop body**, so its
   throttle can never fire and `update_strings` runs every frame it animates. Ours
   throttles the rate recomputation on a real stored timestamp.
5. **barfiller sizes its foreground from `foreground_image:width()`** - a getter
   that reads back the prim - and eases against it. We keep the width in the logic
   module, as parambar does, so the animation is testable without a prim.
6. **No unload path in either** - prims leak on `//lua reload`. `destroy()` disposes
   all three.
7. **Every function and every state table is a global** in both (`xp`, `cp`, `ep`,
   `initialize`, `update_strings`, ...). Pure module, no globals.
8. **pointwatch's `eval` command** `loadstring`s user input into the addon
   environment. Not reproduced.
9. barfiller's `os.time()` registry has 1-second granularity and is wall-clock;
   ours uses `ctx.now()` (`os.clock`), the monotonic frame clock the crossbar and
   target bar already take.

## Deviations from the references (by decision)

- **Position, scale and visibility are framework-owned.** No `pos` settings, no
  `AllowDecenter`, no `visible` command, no mog-house moon icon (barfiller's rested
  bonus - out of scope; it is not part of what Kevin asked for and would need its
  own art and notice).
- **No Abyssea, Dynamis, sparks, accolades or unity.** That is the bulk of
  pointwatch and all of its `message_ids` table, its zone-change string swapping and
  its granule key-item scanning. None of it ships.
- **No user-authored format string.** pointwatch's headline feature is a
  `loadstring`-ed format expression in settings.xml. Ours has three fixed strings;
  a config file that is code we `loadstring` in an empty environment is already the
  repo's settings format, and inviting arbitrary expressions into it is a different
  risk with no request behind it.
- **Rates are computed once a second, not once per frame** and not once per 30
  frames of an animation that may not be running (pointwatch ties its refresh to a
  frame counter). The registry walk is O(samples in 600s).
- **The header is rebuilt only when its text changes**, compared as a string before
  it reaches the prim - the same discipline as parambar's per-bar dirty flags.

## Architecture

Three files, mirroring `src/components/parambar/` exactly - same require form
(**slashes**), same BSD header (c) 2026, Azureblood2.

```
src/components/expbar/
  expbar.lua      -- widget factory new(ctx): prims, ctx reads, the contract
  logic.lua       -- pure: mode selection, the three registries, header text,
                     bar geometry, easing, the command
  measure.lua     -- pure: the widest line the header can print, and the bar
                     width derived from it
  defaults.lua    -- function(screen_width, screen_height) -> defaults
src/assets/barfiller/
  bar_bg.png      -- 472x5, verbatim
  bar_fg.png      -- 1x5, verbatim
  LICENSE.txt     -- BSD 3-clause, (c) 2015 Morath86
tests/components/
  expbar_logic_spec.lua
  expbar_spec.lua
```

`logic.lua` holds no Windower and no prims. Its inputs are facts; its outputs are a
render plan:

- `on_packet(id, packet)` - `0x061`, `0x063` (order 2 only) and `0x02D` in, a
  boolean "something changed" out. Unknown ids and a nil packet are no-ops.
- `set_player(player)` - main/sub job and level, and
  `job_points[<job>].jp`/`.cp`, pushed every frame from `ctx.get_player()`.
- `tick(now)` - prunes and recomputes the three rates at most once a second, eases
  the fill one step (parambar's `ceil`-guarded exponential ease-out, so it
  converges), and returns `{ mode, header, width, dirty, hidden }`.
- `reset()` - drops every counter, the rate history and the eased width. The
  widget calls it when the CHARACTER changes, which it decides from the name
  `ctx.get_player()` answers at attach: everything the module holds belongs to
  one player, and a second would otherwise be drawn with the first's merit count
  and experience. It is deliberately not called on every attach - `//hud slot`
  and `//hud reset expbar` re-attach the same character, and the numbers cannot
  be re-read to make up for it: `last_incoming` is keyed by packet id and 0x063
  is multiplexed over five orders, so the merit seed only lands when order 2
  happened to be the last one sent. Clearing there would put a zero on screen
  that nothing could fill back in. For the same reason `add_points` reads a
  merit cap of zero as *not yet known* rather than as a cap of none - reading it
  as a cap parks the limit bar at 9999/10000 until the first order-2 packet.
  (Added 2026-09-04, from blind review rounds 1 and 2.)
- `mode()`, `header()`, `geometry(x, y, scale)`, `bounds(x, y, scale)`,
  `set_preview(on)`, `command(args)`.
- A `registry` helper local to the module - `add(now, points)` / `rate(now)` -
  instantiated three times (exp, cp, ep). Limit points feed the merit count and the
  `limit` bar but no rate: nothing in either header shows LP/hr.

**Mode selection** is a pure function of `(main_job_level, master_breaker)`:

```
LEVEL_CAP = 99
master_breaker and level >= LEVEL_CAP  -> "ep"
level >= LEVEL_CAP                     -> "limit"
otherwise                              -> "exp"
```

with one defensive fallback: an `exp` mode whose `Required EXP` is <= 0 draws an
empty bar rather than dividing by it. Level is taken from `get_player()`, not from
0x061's `Main Job Level`, so it tracks a job change without waiting for a packet.
Under level sync `main_job_level` reports the synced level (unverified), which is
the answer we want anyway: a synced character earns exp, and the exp bar is right.

`expbar.lua` owns the three prims - one text, one background image, one fill image -
built once in the factory and hidden, disposed in `destroy()`. It implements
`name`, `alias`, `defaults`, `attach`, `detach`, `set_pos`, `set_scale`,
`set_preview`, `show`, `hide`, `get_bounds`, `update`, `handle_command`, `destroy`.
Single anchor: the header and the bar move together, so no `anchors()` member - and
per CLAUDE.md the absence of the member *is* the detection.

**Origin and bounds.** The origin is the top-left of the header text; the bar sits
at `origin.y + header_height + gap`. `get_bounds` returns that same origin with
`472 * scale` by `(header_height + gap + 5) * scale`, so the contract holds
("`get_bounds()` must return the same origin `set_pos` was given"). The header is
left-justified at the origin - never `right_justified(true)`, which makes the
coordinate screen-relative (parambar:92-97 and the giltracker plan both route around
this).

**Both images must set `fit(false)`** and an explicit `size()`: barfiller sets
`Texture.Fit = true` on its background, and per CLAUDE.md that defeats `size()` and
would make the framework's scale silently do nothing. Alpha is set with
`alpha`/`stroke_alpha` (0-255), never `transparency` (0-1).

### Entry-point changes (`src/XIVHud.lua`)

1. A `step("building the expbar component", ...)` gated on `safe_mode or
   libraries_error` - the giltracker/equipviewer gate, since everything this
   component learns arrives through `parse_packet`.
2. Its ctx: `new_text`, `new_image`, `screen`, `asset`, `now = os.clock`,
   `get_player = read_player` (the player service, never the raw read),
   `parse_packet`, and a new **`last_incoming`** dep wrapping
   `windower.packets.last_incoming(id)`. Wrapped like `parse_action`, with the index
   *inside* the pcall closure so a missing `windower.packets` cannot throw.
3. `check_assets()` gains `assets/barfiller/bar_bg.png` and `bar_fg.png` - a missing
   texture fails silently and would look like a working addon drawing nothing.
4. `tests/support/entry_point.lua` gains the `components/expbar/expbar` stub, and
   `tests/entry_point_spec.lua` a case for the new ctx (in particular that
   `get_player` is the service's and that `last_incoming` is pcall-wrapped).
   `tests/component_aliases_spec.lua` gains `eb = "expbar"`.

No new dispatch: `incoming chunk` already reaches every component as
`update("chunk", id, original, parsed)`, and none of 0x061/0x063/0x02D is in the
entry point's pre-parse set - so the component parses its own three ids behind
`wants_chunk`, exactly as giltracker does for its five.

## Settings (`defaults.lua` -> `data/<Character>/<slot>/expbar/config.lua`)

```lua
{
  font = "sans-serif", font_size = 11,
  text_color  = { a = 255, r = 255, g = 215, b = 0 },     -- the crossbar's gold
  text_stroke = { width = 2, a = 150, r = 80, g = 70, b = 30 },
  header_height = 16,        -- the band the text is drawn in; the bar sits under it
  gap = 2,                   -- header foot to bar top
  bar = { width = 472, height = 5, inset = 2 },  -- barfiller's own geometry
  job_icon = { size = 16, gap = 4 },  -- the glyph, left of the header
  fill_color = { r = 255, g = 255, b = 255 },   -- barfiller's own gold (see below)
  layout = {
    -- centred along the bottom of the screen, where FFXIV draws this bar and
    -- where barfiller centres its own. The widget is 23px tall at scale 1.
    pos = { x = max(0, floor(screen_width / 2 - 236)),
            y = max(0, screen_height - 32) },
    scale = 1, visible = true,
  },
}
```

**One fill colour, not one per mode** (revised twice during implementation,
2026-09-04). The prim MODULATES its texture by `color` and barfiller's fill is an
opaque gold gradient, so a cool tint cannot come out cool - the blue first drafted
here for exemplar mode renders as muddy grey-green. Kevin's call settled it: the
glyph, the text and the fill are all the one gold, and the modes are told apart by
the line above the bar rather than by a tint the art could not carry. White here
modulates barfiller's art to itself; the key stays so the fill can be recoloured.

The header band is as tall as the taller of the text and the glyph, so a
`job_icon.size` past `header_height` pushes the bar down rather than drawing over
it, and `bounds` grows with it. The header's x always clears the glyph, drawn or
not: a client that has not named a job yet must not slide the line left and back
again as it fills the player in.

## Commands

```
//hud expbar          -- two lines: mode, the numbers behind the bar and the
                         three rates; then what was read for the master levels
//hud expbar clear    -- drop the rate registries (barfiller's `clear`)
```

The second line (added 2026-09-04, from blind review round 3) is the diagnostic
for this component's unverified half: `Master Breaker` and `Master Level` are
read as false and 0 if those are not Windower's spellings, and the only symptom
is a bar pinned in `limit` mode with nothing anywhere to say why. It reports the
breaker, the master level and the merit count with its cap, so one command in a
live client settles items 1, 3 and 4 of Unverified below.

`clear` rather than `reset`: `//hud reset expbar` is the framework's own verb and
means something else (restore defaults), and two words that differ only in position
would be read wrong.

## Testing strategy (TDD - specs first, per the `tdd-workflow` skill)

`logic.lua`, with plain tables and an injected clock:

- **Mode selection**: sub-cap -> `exp`; cap without Master Breaker -> `limit`; cap
  with it -> `ep`; a job change moves the mode without a packet; `exp` with
  `Required EXP` 0 draws empty rather than dividing.
- **Packet handling**: 0x061 fills exp/EP/master level/Master Breaker; 0x063
  order 2 fills LP and merits and order 5 is ignored; 0x02D for each of the nine
  message ids advances the right counter by the right *param*, including the two
  that read Param 2; an unrelated message id and a nil packet are no-ops.
- **Counters between packets**: exp advances per message and wraps at
  `Required EXP`; LP wraps at 10000 and increments the merit count, capped at
  `Max Merit Points`; EP wraps at `Required Exemplar Points` (the pointwatch
  defect, as a regression test).
- **Registries**: nothing older than 600s survives; the rate is 0 until a sample is
  >30s old; two samples in the same second sum; a rate decays as the window ages
  with no new samples.
- **Header text**: all three modes; no subjob; the `k` formatting at 0, 999, 1000,
  12,500 and a rate large enough to need rounding; the string is unchanged between
  two ticks with no new facts (so the widget can skip the prim write).
- **Geometry/ease/bounds**: fill width at 0%, 50%, 100%; the ease converges from
  both directions; bounds are the full 472-wide box at scale 1 and non-1 and return
  the origin they were given.
- **Preview** in and out; **command** for both verbs and an unknown one, and
  the master-level line reporting what the packet was read as.
- **A negative width never reaches a prim**: unreachable from the gain messages,
  which are all unsigned, but a prim sized negatively is a silent failure.
- **A second character**: a re-attach under a new name with nothing to seed
  from draws that character's zeroes rather than the previous one's numbers and
  rate - and a re-attach under the SAME name keeps everything.
- **The config the framework hands over** drives every measure and colour: the
  widget is attached a deep copy, as `lib/settings` gives it, never its own
  defaults table.

`expbar.lua`, against the fake prim recorder in `tests/support/fakes.lua`:
a `show()` outside the render path leaves an empty fill hidden;
`attach` seeds from `ctx.last_incoming` for both 0x061 and 0x063 (and survives both
returning nil); a chunk the logic does not want is never parsed; `destroy` disposes
all three prims; `set_scale` re-pushes geometry; `hide` hides the fill as well as
the background.

**In-client smoke** (Windows/Windower - nothing above proves the addon loads):
bar moves on a kill at sub-99 and the EXP/hr settles; the header switches at a job
change to a capped job; EP mode on a Master Breaker character; `//lua reload xivhud`
leaves no prims; drag/scale in `//hud layout` persists; and the Param 1/Param 2 log
in defect 1 above.

## Milestones

- **EB0** - `logic.lua` + `defaults.lua` + both specs, green `busted` / `luacheck` /
  `stylua --check`.
- **EB1** - `expbar.lua`, the two images and their notice, the four entry-point
  edits, registered with `core.register`.
- **EB2** - in-client smoke, including the parameter check, then the blind
  independent review gate before any PR.

## Follow-ups (not built)

- **Merit points read 0 until the server re-sends 0x063 order 2.** It comes when
  limit points move and in the bursts sent for a zone or the status menu, never
  on request; `last_incoming` is keyed by id alone, so the seed at attach nearly
  always catches order 5 or 9 instead. A merit-capped character earning no limit
  points reads 0 for the whole session until they zone or open the status menu.
  Seen in a live client 2026-09-04 (75 merits shown as 0, corrected the moment
  the status menu opened). **pointwatch behaves identically**, and Kevin's call
  was to leave it: the fix is to hold the two state packets from before the
  attach and adopt them after it, which is real machinery for a display that
  self-corrects on the next zone.

- **Listen on the `action message` event instead of parsing every 0x02D.** The
  component parses each one to read nine message ids out of it, and action
  messages are among the highest-frequency inbound packets in an alliance zone.
  Windower delivers `action message` already decoded as
  `(actor_id, target_id, actor_index, target_index, message_id, param_1, ...)`,
  which is what pointwatch itself listens on. Raised by blind review round 3 and
  deliberately deferred: it is a change to the entry point's event wiring, it
  rests on ~70% confidence that the event is current (the deprecated one is
  `action`, which is a different event), and the cost it saves is one worth
  measuring in a live client before paying for.

## Unverified - needs a live client

1. **Message ids 809/810** (exemplar points) are absent from the Windower
   `action_messages` resource, which tops out at 806. pointwatch is the only
   evidence for them, and for 810 being a chain variant whose amount is Param 2.
   EP/hr rests on this.
2. **The `number`/`number2` -> Param 1/Param 2 mapping** (defect 1). If it turns out
   the references are right and the resource templates are not, the fix is two table
   entries.
3. **`Master Breaker` reads true** on a character who has the key item, and 0x061 is
   sent often enough that a job change to a mastered job flips the mode promptly.
4. **`Master Level`** is the character's real ML, not the synced one. pointwatch
   calls this field `synced_master_level` and derives its own from a 50-entry table
   of required-EP values. Kevin chose the plain byte; if it follows level sync,
   swapping in that table is a one-place change.
5. **The `job_points` key form** - the wiki shows `job_points.war`, i.e. the short
   name lowercased, while pointwatch indexes the 0x063 packet by `main_job_full`.
   The reader tries `main_job:lower()` then `main_job_full:lower()` and answers 0
   for neither, so a wrong guess costs a zero rather than a crash.
6. **`main_job_level` under level sync** reports the synced level (assumed above).
7. **Whether a 0x02D point-gain message ever arrives about somebody else.** All
   seven tracked templates render `${actor}`, and the packet carries `Actor` /
   `Actor Index`, but nothing here compares them to the player - so if the
   server broadcasts a party member's gain, the bar advances and all three
   rates inflate with points nobody here earned. Both reference addons behave
   the same way, which is the only evidence either way, and adding the filter
   blind is the worse risk: if `Actor` is not the player's id for one's own
   gains, a filter kills the whole component silently rather than
   over-counting. Raised by blind review round 4 (~55% it is a real defect).
   **Live check**: sit in a party, let someone else get a kill you have no
   claim on, and watch whether the bar moves.
8. **`windower.packets.last_incoming` returns `(data, timestamp)`** in that
   order - the entry point keeps the first return only. Documented on the
   Packet-Functions wiki page, but if it is really `(id, data)` the seed
   degrades to a failed parse and a no-op rather than erring, so the symptom
   would be a bar that reads zero at login until the first gain.
9. **`get_player().sub_job` for a character with no subjob.** Read as either
   absent or the resources' job id 0 (`NON`); both spell `---` in the header.

## License & attribution

`bar_bg.png` and `bar_fg.png` are verbatim copies from the Windower `barfiller`
addon, which ships no separate asset licence - so its source licence is the basis,
as with `assets/gil/`. `src/assets/barfiller/LICENSE.txt` reproduces the BSD
3-clause notice, (c) 2015 Morath86, and ships with the addon.

The point-tracking approach (the 0x061/0x063/0x02D reads and the rate registry) is
re-implemented from pointwatch, BSD 3-clause (c) 2014 Byrthnoth; that notice belongs
in the component's own source header alongside the repo's, the way equipviewer
carries Rubenator's. Our files keep the repo's BSD header ((c) 2026, Azureblood2) -
`tests/sources_spec.lua` fails the build without it.

## References

- pointwatch: https://github.com/Windower/Lua/tree/live/addons/pointwatch
- barfiller: https://github.com/Windower/Lua/tree/live/addons/barfiller
- packet fields (0x061, 0x063, 0x02D):
  https://github.com/Windower/Lua/blob/live/addons/libs/packets/fields.lua
- action messages (ids 8/105/253/371/372/718/735):
  https://github.com/Windower/Resources/blob/master/resources_data/action_messages.lua
- `get_player` fields: https://github.com/Windower/Lua/wiki/FFXI-Functions
- `windower.packets.last_incoming`:
  https://github.com/Windower/Lua/wiki/Packet-Functions
- live contract: [CLAUDE.md](../../CLAUDE.md), `src/lib/core.lua`,
  `src/components/parambar/`, `src/components/giltracker/`
- sibling plans: [parameter-bar.md](parameter-bar.md), [giltracker.md](giltracker.md)
