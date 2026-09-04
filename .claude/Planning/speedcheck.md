# Speed Check — component plan

Status: built, 2026-09-04. Scope: one component, `src/components/speedcheck/`, branched
from `dev` at 5773707. Sibling precedent and the model copied: `src/components/giltracker/`
— one icon, one number, no commands, no store, no anchors.

## Goal

The player's **movement speed** as a signed percentage, drawn **under** Bolter's Roll's
status icon. (It was drawn *over* the icon as first built and through PR #38's review; Kevin
moved it below the art on 2026-09-04, from a live client.) A re-implementation of the Windower `SpeedChecker` addon (BSD © 2013-2014
Windower) as a framework component.

Kevin's decisions, 2026-09-04, before any code:

- **Its own registered component**, named `speedcheck` — not an anchor on parambar or the
  crossbar. Alias `sc` (the two-letter form every other component takes).
- **Art: `assets/xiv/buffIcons/330.png`**, Bolter's Roll's own status icon, already shipped
  under XivParty's notice. Checked visually rather than assumed: it is a purple orb with a
  running figure and a speed arrow, not one of the roll dice its neighbours are — which is
  what makes it read as a speed widget at a glance. `partylist/buff_order.lua:343` is what
  says 330 is Bolter's Roll.
- **Always on, signed percent** (`+12%`, `+0%`, `-25%`) — the reference's own format, and a
  widget that never disappears is one that can always be found in layout mode.

## Reference facts (SpeedChecker, read 2026-09-04)

The whole addon is a `prerender` handler and one text:

```lua
local me = windower.ffxi.get_mob_by_target('me')
if me then speed:text('%+.0f %%':format(100*(me.movement_speed / 5 - 1))) ...
```

- The reading is `movement_speed` on the **mob** table. `get_player()` does not carry it,
  and nothing cheaper does either, so there is no packet-driven equivalent of giltracker's
  "never poll" rule available here: it is read on the tick.
- Walking speed is **5**, so the percentage is `100 * (speed / 5 - 1)`.
- **Unverified, needs a live client:** whether the field reports a *capability* (constant
  while standing still) or a *current velocity* (0 whenever you stop). The reference's
  design — a static percentage, redrawn every frame — assumes the former, and this port
  inherits the assumption. If it turns out to be velocity, the widget will read `-100%`
  whenever the player stands still and the fix is a hold-the-maximum rule, not a redesign.
- It has no layout, no visibility handling and no unload path — all of which are the
  framework's here, so none of it is ported.

## What was built

```
src/components/speedcheck/
  defaults.lua    -- config defaults + the first-run anchor
  logic.lua       -- the percentage and the layout maths (pure)
  speedcheck.lua  -- the widget: two prims and the ctx reads
tests/components/speedcheck_logic_spec.lua
tests/components/speedcheck_spec.lua
```

Decisions taken while building, none of them the reference's:

- **The tick polls on `ctx.generation()`, not on the frame.** The first cut read every frame
  and justified it with the mob memo in `lib/player` - which is wrong: that memo is cleared by
  `begin_frame`, so it only saves a call when two consumers ask in the *same* frame, and the
  only other `me` reader (targetbar) is itself counter-gated. Reading per frame would have been
  ~60 client calls a second for a number that moves when a buff, a mount or a piece of gear
  does. Gating on the shared counter is CLAUDE.md's own rule for exactly this, and asking for
  the counter is what opens the next interval, so the widget keeps its cadence even if no other
  component reads the client. It also reads nothing while it is off screen, and `hide()` drops
  the remembered counter so the first tick after it comes back always reads - the value it holds
  is as old as the cutscene it sat out. An absent `ctx.generation` falls back to reading every
  frame rather than never, since a wiring slip must not silently freeze the widget.
- **The number prim is written only when the string changes**, so a settled speed costs nothing.
- **A nil mob keeps the last value.** The client hands back no mob for a frame or two of
  every zone load, and that is not a change of speed. `detach` clears it, so a logout does not carry one
  character's speed into the next. A character switch with no logout event does not detach at all
  (core re-attaches over it), but the attach reads immediately and core has already announced the
  scope change to the player service by then, so nothing stale is drawn; before the first read the text is `--%`, which is
  deliberately not `+0%` — the widget would otherwise claim base speed on the strength of
  never having looked.
- **The two are stacked, icon over number**, held apart by `text_gap` (2px, scaled). The box
  is as tall as both of them and as wide as the wider, and the default anchor sits far enough up
  that the whole stack clears the gil tracker's row.
- **The BOX is a reserved width; the NUMBER is centred on what it actually draws.** The box is
  measured against the widest string the number ever takes (`-100%`), which is what keeps the
  icon and the origin still as digits come and go — giltracker's rule, applied to an overlay
  rather than a row. But giltracker's number sits *beside* its icon and is left-justified inside
  that reserved box; this one sits *on* the icon, so a left-justified `+0%` would draw ~7px left
  of the orb's centre and slide as the value changed width. The glyphs are centred on their own
  estimated width instead, inside the reserved box. (Round 2 of review found this: the first cut
  copied giltracker's placement wholesale, and the test that claimed to pin the centring compared
  the reserved width against itself.) The widget re-places the number whenever the string it
  draws changes, behind the same unchanged-value guard that keeps a settled speed free — core
  pushes `set_pos` on an attach, a drag and a slot switch, never on a value change, so nothing
  else would. (Round 3 of review found that half missing: logic re-centred, the widget never
  asked it to, and every widget test looked at the text and not the position.)
- **The centring is an estimate.** No prim can be measured, so text width is
  `characters * font_size * 0.75` (the ratio measured for giltracker's number in
  `//hud layout`). `config.text_offset` is the knob for correcting it in a live client: it moves
  the number against the icon, and the box grows to cover wherever that puts it - a negative
  correction pads the box's left edge and shifts both prims across instead, so nothing is ever
  drawn outside the bounds core clamps against and layout mode highlights.
- Rounding is half-up on **both** signs (`math.floor(p + 0.5)`), so a -12.5% reading does not
  become a -13% the player does not have.

## Not built, deliberately

- **No commands.** There is nothing to configure that layout mode does not already own, and
  giltracker's precedent is a component with none.
- **No auto-hide at base speed.** Kevin's call: a widget that vanishes is one that cannot be
  dragged, and preview would have to force it back on for layout mode anyway.
- **No colour bands** on the number. Nothing in the reference has them, and a speed penalty
  is not a threshold the way HP is.

## Verification

2724 specs green, `luacheck` clean, `stylua --check` clean. Two blind review rounds so far, both
ISSUES, every blocking finding real and taken. R1: three - the false per-frame-read justification
above (which had reached CLAUDE.md), `apply_style` pinned by nothing at all (deleting the whole
function left the suite green), and `text_offset` unpinned in the same way. R2: the number was left-justified in the reserved box
rather than centred on its glyphs (above), and `number.size` was pinned by nothing - deleting the
call left the suite green while the framework's scale silently stopped scaling the font. Both
mutation-verified after the fix. R3: the widget never re-laid the number out when the value
changed width, so everything but `+0%` drew off-centre and layout mode's `+100%` preview drew
past the box core clamps against. **Not verified in a live
client** — the `movement_speed` semantics above and the centring estimate are both things
only the client can settle.
