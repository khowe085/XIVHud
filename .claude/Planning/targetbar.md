# Target Bar — component plan

Status: draft, 2026-08-07. Scope: one component, `src/components/targetbar/`.
**The framework is already built and merged** — plan against the live contract in
CLAUDE.md and `src/lib/core.lua`, not the design doc
[xivhud-implementation.md](xivhud-implementation.md). Sibling precedent: `giltracker`
for the widget-contract shape ([giltracker.md](giltracker.md)), `partylist` for the
xiv-themed bar art and the "read the target every frame" pattern
(`src/components/partylist/partylist.lua`, `src/components/partylist/layout.lua`).

## Goal

A big FFXIV-style current-target health bar for FFXI: name and HP% above a
health bar, re-implemented from the Windower `enemybar` addon (`targetBar.lua`) but
restyled to this HUD's own look rather than the reference's art — plus a
DistancePlus-style color-coded distance readout (TB3) and a cast/readying progress
bar beneath it (TB4; new scope, not a port — see their sections). Decisions
(2026-08-07):

- Component key **`targetbar`**, one registration (no variant).
- **Subtarget bar is out of scope.** The reference bundles a subtarget bar hardcoded
  at a fixed offset from the target bar; that becomes a future, independently
  positioned component (`subtargetbar` or similar) — not built here. Backlogged
  below.
- **Bar animation:** parambar's continuous exponential ease-out (`EASE = 0.1`), not
  the reference's combat-only "damage ghost" two-layer lag effect. One eased fill,
  consistent with every other bar in the HUD.
- **Visual style: the partylist HP bar, not the reference's art.** Background/fill/
  foreground three-layer bar reused from `src/components/partylist/layout.lua`'s
  `main_bar` (`assets/xiv/BarBG.png` / `Bar.png` / `BarFG.png`, 128×64, XIVParty's
  `xiv` theme, BSD 3-clause © 2024 Tylas) — copied into `targetbar`'s own `assets/`
  per the component-isolation rule (no cross-component asset reuse, only cross-file
  duplication with its own license notice). The reference's own `bg_cap.png` /
  `bg_body.png` / `fg_body.png` are **not used**.
- **The fill is tinted by claim state** (decided 2026-08-07, superseding the
  fixed `#B03030` first specified — that color is dropped). The reference's
  six-state claim palette colors its **text** (`t_text:color(...)` in every
  branch; its fills are fixed reds); here the same palette moves to the **bar
  fill**, the name text stays uncolored, and the HP%/distance texts keep their
  own coloring. States and colors, ported in the reference's priority order:
  dead (`hpp == 0`) gray `155,155,155` — visible for the ~30 frames the fill
  eases down to zero, then hidden with it; **claimed by us** (see `check_claim`
  below) light red `255,204,204`; a targeted **party member** (`in_party` and not
  self) cyan `102,255,255`; any other **PC** (`is_npc == false`) white
  `255,255,255`; **unclaimed** (`claim_id == 0`) pale yellow `230,230,138`;
  **claimed by someone else** purple `153,102,255`. Tinting works because the
  xiv `Bar.png` fill art is neutral — partylist draws HP, MP and TP from the
  same texture untinted (~90%; if a live client shows a hue baked in, the art
  gets a desaturated copy, not a palette change).
- **`check_claim` is ported with one upgrade and one bug fix.** The reference
  compares `claim_id` against the player and `p1`–`p5` via five
  `get_mob_by_target` calls per frame — and misses that an *alliance* member's
  claim counts as yours. Here the id set comes from `ctx.get_party()` (all
  eighteen members) on a **200ms throttle** — the same `due_for_poll` cadence
  partylist already polls `get_party()` at (`DEFAULT_POLL_INTERVAL_MS = 200`),
  cited as the precedent it actually is — while the target's own `claim_id` is
  still read every frame. **The walk iterates the eighteen member keys
  explicitly** (`p0`–`p5`, `a10`–`a15`, `a20`–`a25` — partylist's `PARTY_KEYS`
  approach) with a `type(member) == "table"` guard on each: `get_party()`
  returns scalar keys too (`party1_count`, leader ids), and a bare `pairs()`
  walk would index a number and throw inside the guarded prerender path, which
  disables the handler after five failures. **Id extraction is the guarded half
  of partylist's read** — `member.mob and member.mob.id`, without its
  packet-built `ids_by_name` fallback (that map exists for out-of-zone members,
  machinery this component does not carry): `.mob` is nil for any member whose
  index is not loaded, so those members simply drop out of the roster for that
  window (their claim shows purple until the client loads them; a documented
  degradation, not a crash — CLAUDE.md's nil-mob rule). A member who joins and
  claims inside the same window shows purple for at most 200ms; negligible. The
  player's own id rides `set_self` on the same poll — and since `due_for_poll`
  is true on its very first call (partylist's behavior, kept), both the id and
  the roster are populated on the first tick after attach: "mine" resolves from
  the first frame not because anything skips the throttle, but because the
  throttle starts open — and **`attach` resets the poll gate**, because logic
  is constructed once per widget while attach happens on every login: without
  the reset, only the session's *first* attach would get the open-gate
  behavior, and a relog would eat a 200ms purple window. **The bug fix: "mine" requires `claim_id ~= 0` and a
  known self id.** The reference initializes `player_id = 0` and its
  `check_claim` matches `player_id == claim_id`, so before its `load` handler
  resolves the player, every *unclaimed* mob (`claim_id == 0`) reads as
  claimed-by-us. **The fix lives in the ownership test, not the branch order**:
  the reference's state order is kept exactly (dead → mine → member → pc →
  unclaimed → claimed — party members and other PCs carry `claim_id == 0` too,
  so testing "unclaimed" any earlier would eat the cyan and white states), and
  it is `check_claim` itself that returns false when `claim_id == 0` or the
  self id is unknown — an unclaimed mob falls through "mine" and reaches the
  `unclaimed` branch in its proper fifth position. The **member branch needs
  the same guard**: the reference's `in_party and id ~= player_id` with an
  unknown self id would call *yourself* a party member (`id ~= nil` is true),
  so "member" additionally requires a known self id — while the id is unknown
  (at most one 200ms window), any in-party target, yourself included, degrades
  to `pc` white rather than miscoloring. `claim_id` itself is normalized at
  `set_target` (`tonumber(...) or 0`), so a mob table missing the field reads
  as unclaimed, not as someone else's claim.
- **Layout: a text row above the bar reading `HP% | distance | name`** (decided
  2026-08-07, superseding the first-drafted `"<hpp>% <name>"` single line) — three
  **separate text prims at fixed offsets**: HP% in a fixed-width reserve, the
  distance to the mob in a fixed-width reserve after it, then the name, **capped at
  `name_max_chars = 17`** (partylist's own main-row cap) so the row — and therefore the
  widget's bounding box — has a fixed width. Fixed reserves are what make three
  prims workable at all — Windower prims do not report their rendered width, so a
  flowing layout would need glyph estimation; a reserved slot per segment needs
  none (giltracker's reserved-width precedent). Three prims
  because each segment colors independently: HP% by band (partylist's thresholds:
  red <25, orange <50, yellow <75, else the HUD's off-white — the one piece of
  "styled like the partylist HP bar" carried over from its *text* treatment now
  that the bar fill no longer bands), distance by DistancePlus's job-aware scheme
  (see the Distance section), the name never colored.

## Reference facts (verified 2026-08-07 against Windower/Lua `dev`)

Source: `addons/enemybar/{enemybar,targetBar,subtargetBar,gui_settings}.lua`
(Copyright © 2015, Mike McKee, BSD 3-clause). Only the target-bar behavior below is
relevant; the subtarget bar and the settings/art it shares are out of scope (see
above).

- **Data source:** `windower.ffxi.get_mob_by_target('t')`, read every `prerender`.
  `nil` when nothing is targeted — the reference gates visibility separately on the
  `target change` event's `index` argument (`index == 0` → hide), but since the mob
  read already happens every frame, this plan drops the extra event and treats
  `target == nil` as the sole occupancy signal (see Deviations).
- **Bar width driver:** `target.hpp / 100`, floored against a configured pixel width.
  Two widths are pushed per frame in the reference: an immediate foreground
  (`tfg_body`) and a lagging "ghost" foreground (`tfgg_body`) that only trails on
  *shrink while `player.in_combat`* — snaps instantly on heal or out-of-combat. (It
  branches purely on width and combat state, so an in-combat switch to a lower-HP
  target lags exactly as a hit would — nothing keys off target identity.) Dropped
  per the animation decision above; the ease all lives in `logic.lua` the same way
  parambar's does — except that, unlike parambar's one player, targets *change*:
  the ease resets on a target identity (id) change, snapping straight to the new
  target's width, partylist's own "next occupant restarts the animation" precedent.
- **Claim/party coloring (ported, moved to the fill):** `check_claim(claim_id)` —
  true if `claim_id` equals the player's own id or any of up to 5
  `get_mob_by_target('p'..i)` ids — then a six-branch `if` on `hpp == 0` /
  claimed-by-us-or-party / `in_party and id ~= player_id` / `is_npc == false` /
  `claim_id == 0` / `claim_id ~= 0`, each mapped to a fixed RGB **on the text**
  (`t_text:color`), the fills staying fixed red. Ported here with the same states,
  colors and priority order, but applied to the bar fill instead, with the id set
  widened to the alliance and throttled — see Deviations.
- **Mob table fields** (`hpp`, `claim_id`, `in_party`, `is_npc`, `id`,
  `target_index`, `distance`, `model_size`) confirmed present on the
  `get_mob_by_target`/`get_mob_by_id` result per the Windower Lua wiki's FFXI
  Functions page — this component reads `name`, `hpp`, `id` (ease reset + cast
  actor matching), `claim_id`/`in_party`/`is_npc` (claim state), `distance` and
  `model_size` (the Distance section).
- **Settings:** the reference persists only `pos` and `font`/`font_size` via
  Windower's `config` (XML); bar width/height and every color are hardcoded Lua
  constants in `gui_settings.lua`, rebuilt into prims inside `config.register`'s
  callback (an unusual construction — prims are created only once settings load, not
  at top level). None of that XML/`config` machinery applies here; this repo's own
  `lib/settings` scheme owns persistence (see Settings below).
- **Lifecycle defects noted, not ported:** no `unload` handler (prims leak on
  `//lua reload`); every value (`visible`, `target`, `player_id`, all prim
  variables, `check_claim`, `target_change`) is an implicit global; `logout` reloads
  the whole addon via `windower.send_command("input //lua r enemybar")` as, in the
  source's own words, "a super cheap fix" — this repo's `attach`/`detach` lifecycle
  replaces it outright, no reload needed. `tbg_body:width(targetBarWidth)` is reset
  every frame with the comment "I still have no idea why removing this breaks the
  bg." — a cargo-cult workaround not carried forward; our fill/bg are separate prims
  and the bg's width is set once in `apply_layout`, not every tick.

## Deviations from the reference (decided 2026-08-07)

- **Position/scale/visibility belong to the framework**, exactly as giltracker and
  parambar: no fixed screen anchor, no `pos`/`font` XML keys — layout slots own it,
  the wheel in `//hud layout` scales the whole widget (text + bar) uniformly.
- **No stretching the bar art wider than its authored size.** The reference's own
  bar art is a 1×12px strip stretched to its drawn 598px width (`targetBarWidth`) —
  stretchable by construction. The xiv `BarBG`/`Bar`/`BarFG` art is a single
  beveled texture drawn at 128×64 (per `layout.lua`'s `main_bar`; the files are
  256×128 / 204×128, drawn at half), with the **fill region `{13, 0}` sized
  `102×64` inside the frame** — the eased width runs 0..102, not 0..128, from a
  13px inset, exactly as partylist drives it. Stretching the frame past its
  authored width would warp the bevel — the party list's row frame survives
  stretching only because its horizontal gradient was *remapped in the art itself*
  (fade-in kept, solid band stretched, tail compressed; see `layout.lua`'s
  background note), which is regenerated art, not a property this bar texture has.
  So the bar is drawn at its authored footprint and the framework's uniform `scale`
  is the only way to make it bigger. Revisit with a stretch-safe regenerated frame
  only if a live client shows the authored size reads too small as a "big health
  bar."
- **The visible bar band sits 25px down inside the 64px texture footprint** —
  measured from the art (and matching `layout.lua`'s own "the bar frame's opaque
  band is box y 25..39"): in drawn pixels, extent convention throughout, the
  FG's non-transparent band spans y 25.0–39.0 (fully opaque 27.5–36.5), the
  fill's 28.0–36.0; everything above and below is transparent padding. All vertical layout is computed from the **band**, not the texture
  rectangle — **with every art constant scaled**: the frame prim is placed at
  `text_height + effective_gap - BAND_TOP * scale` where
  `effective_gap = max(gap * scale, BAND_TOP * scale - text_height)`
  (constants `BAND_TOP = 25`, `BAND_BOTTOM = 39` in `logic.lua`; `text_height`
  is already at scale via the rounded drawn font, so mixing it with an
  *unscaled* 25 would detach the band from the text at every scale other than
  1 — at scale 0.25 the correct frame top is +1.75, not the 0-with-19px-gap an
  unscaled formula produces). The frame prim's top must stay at or below the
  origin — transparent art must not reach above the origin either
  (giltracker's "nothing is ever drawn above the origin" rule) — and since
  `font_size` and `gap` are both user-editable config keys, this is a **clamp
  in `geometry`, not a hope about defaults**, with spec cases at scale 1
  (`font_size = 12`, `gap = 0` — text row 18, 7 short of `BAND_TOP` — clamp
  engaged, frame at y = 0) *and* at the 0.25 scale floor. Text height is
  `drawn_font * TEXT_HEIGHT_RATIO` (1.5, the drawn glyph box — see the scaling
  bullet below): at the defaults (`font_size = 14` -> 21, `gap = 8`, scale 1)
  the clamp is inactive, frame top at y = +4.
- **Origin is the text row's top-left, and the box is the full text row** (decided
  2026-08-07 after review, superseding the first-drafted 128px-wide box). Bounds
  width is `ROW_WIDTH(scale) = max(hp_reserve + distance_reserve +
  name_reserve, 128 * scale)` — reserves already at scale (see the scaling
  bullet), the floor at the HP frame's **drawn** width `128 * scale`, because
  the frame is drawn at that width no matter what the text reserves compute to
  (an unscaled 128 floor would over-report the box by ~47px at scale 0.25),
  and `font_size` / `name_max_chars` are user-editable keys that can shrink
  the row below it
  (`font_size = 6` computes a 123px row — 23 + 23 + 77 with the 5-char HP
  reserve; hostile config degrades the layout, never the contract — same policy
  as every other clamp here, with its own hostile-value spec cases). Each reserve is `ceil(chars * font_size * RATIO)`
  with **`RATIO = 0.75`** — giltracker's *measured* Arial width, not its
  deliberately-low 0.6 reserve constant (0.6 exists there to trade a bounded
  overlap inside its own box against a floating gap; here the name is the
  **last** segment with no neighbour to lap into, so an undersized reserve walks
  straight off the box's right edge). The HP% reserve is sized for **5**
  characters, not `"100%"`'s four: the `%` glyph is ~0.89em against digits'
  ~0.556, so the true render of `"100%"` (~2.56em ≈ 48px at 14pt) overruns a
  4-char reserve deterministically — the extra character absorbs it. At font
  14: 53 (HP%, 5 chars) + 53 (`"99.99"`, 5) + 179 (`name_max_chars = 17`) =
  **285px**. **Text scaling uses the rounded drawn font** — reserves and text
  offsets are computed from `max(1, floor(font_size * scale + 0.5))` (the
  repo's whole-pixel font rule, `max(1, ...)` included — both partylist and
  giltracker floor it, and without the floor a tiny font at scale 0.25 rounds
  to an undrawable 0) at the current scale, so `geometry` and `bounds` track
  what the prim actually draws even at the 0.25 scale floor, where a linear
  `* scale` under-reserves against the rounded-up font by ~8px; art offsets
  scale linearly (art has no rounding). **Reserves computed this way are
  already at scale — `bounds` must not multiply them by `scale` again**
  (giltracker's `bounds` returns its at-scale reserve unmultiplied;
  double-scaling under-reports the box by ~61px at scale 0.25 — the reserves
  sum to 81 there, not 81 × 0.25). One convention, shared by `geometry` and
  `bounds`, or the containment assertion tests nothing. The `max(1, ...)`
  floor is partylist's (`giltracker` rounds without it — the floor is adopted,
  not universal precedent). **Vertical text extents use
  `TEXT_HEIGHT_RATIO = 1.5`** (giltracker's measured ascender-to-descender
  multiple), not the 4/3 points-to-pixels em conversion — 4/3 gives the em
  size, which undershoots the drawn glyph box by ~12% and would leave
  descenders below any height derived from it. At font 14 the text row is 21px
  tall. **A glyph estimate can bound nothing absolutely — and the units bite**:
  `RATIO = 0.75` is pixels per point of font size, ≈ 0.56 em once the 4/3
  point-to-pixel conversion is applied. A wide Arial capital (`W` ≈ 0.94 em)
  therefore draws ≈ 1.26 × font size — a 17-character all-capitals name is
  ~300px against the 179px reserve, not a near miss. 0.75 covers realistic
  FFXI mob names because their *average* advance (mixed case, spaces) sits
  near 0.5 em ≈ 0.67 px/pt, under the reserve's 0.75 (~85%); the worst case is
  *documented as only verifiable in-client* — the unit containment assertion
  derives geometry and bounds from the same constant, so it checks internal
  consistency, and TB2's smoke includes a deliberately long, capital-heavy name
  for the real answer.
  The bar sits left-aligned under the text inside the box. Every drawn element
  stays inside the box — footprints included, transparent padding and all — so
  layout mode's drag hit-test covers everything the eye sees and nothing crosses
  left of or above the origin. (A first draft made the box the bar's width and
  called name overflow "giltracker's compromise" — inverted: giltracker's fixed
  reserve exists precisely to *prevent* overflow, and enemy names have no cap to
  reserve for. The cap plus full-row box is what actually satisfies the
  contract.)
- **Occupancy folds into visibility the way partylist's rows do**, not via a
  `target change` event. `logic.lua` computes `occupied = target ~= nil`; the widget
  ANDs that with the framework's own `show()`/`hide()` state before touching any
  prim, mirroring `partylist.lua`'s `want()` helper. No new Windower event is
  registered for this — the mob is read fresh every `update()` tick, same as
  partylist already does for `'t'`/`'st'`.
- **`set_preview(on)` shows a sample name and HP%** (parambar/giltracker precedent)
  so layout mode always has a fixed box to drag even with nothing targeted.
- **HP%-band coloring on the number, claim coloring on the fill — two independent
  channels.** Band thresholds are partylist's own (`< 25` red, `< 50` orange,
  `< 75` yellow, else normal off-white) — duplicated as a small local table rather
  than required from `components/partylist/`, per the "never require a sibling
  component" rule. The claim palette (see the fill bullet in Goal) never touches
  the texts, and the band never touches the fill. The name text is never colored
  by either.
- **Assets are duplicated, not shared.** `assets/xiv/BarBG.png`, `Bar.png`,
  `BarFG.png` are copied byte-for-byte from `components/partylist/assets/xiv/` into
  `components/targetbar/assets/xiv/`, with their own `assets/LICENSE.txt` (Tylas'
  BSD 3-clause notice) — component isolation forbids a code `require` across
  components, and the same principle is applied to assets so `targetbar` remains a
  self-contained directory a user could in principle delete without breaking
  `partylist`.

## Distance (TB3, decided 2026-08-07)

The distance to the target, between the HP% and the name in the text row, colored
by a full port of **DistancePlus**'s job-aware range coding (Windower/Lua `dev`,
`addons/DistancePlus/DistancePlus.lua`, © 2017 Sammeh of Quetzalcoatl, BSD
3-clause — read in full 2026-08-07; facts below are from that source).

- **Value:** `math.sqrt(target.distance)` — the mob table's `distance` field is
  squared — formatted `%.2f`, DistancePlus's default, **clamped to 99.99** so the
  reserve sized for `"99.99"` is never overrun (a kept target followed at range can
  exceed two digits; every mode is long past "out of range" white by then, so the
  clamp costs nothing). The prim itself is drawn from TB1 (plain white, `default`
  mode; TB0 specs its formatting and reserve); TB3 adds the coloring machinery.
- **Modes and colors, ported verbatim** (each is a pure function of the distance,
  both parties' `model_size`, and per-mode constants):
  - `default` — always white. What every job not named below gets.
  - `magic` (auto for RDM/BLM/GEO/SCH/WHM/BRD) — green when
    `dist < MaxDistance + t.model_size + s.model_size`, white beyond:
    can/cannot cast. `MaxDistance` is 20 with **magic's own fudge — not the
    ranged 1.6 rule**: an `elseif` chain in which `t.model_size > 2` → +0.1
    comes first, making **both** special-case branches (`floor(m*10) == 44` →
    `20.0666`, `== 53` → 20) unreachable dead code — any qualifying model_size
    is ≥ 4.4 and already took the `> 2` branch. Ported **in the source's branch
    order** so the effective behavior matches (a 4.4 model_size yields 20.1,
    never 20.0666); the dead branches are kept only as commented parity notes,
    not live code.
  - `ninjutsu` (auto for NIN) — same shape, base 16.1, same `> 2` fudge, same
    dead special-case branches.
  - `gun` (auto for COR) / `bow` / `xbow` (manual) — four states from per-weapon
    constants, **ported as the source's branch structure, not a summary**:
    yellow requires `dist < 25` *and* outside both sweet-spot bands; green and
    blue are the "square shot" and "true shot" bands, whose bounds add both
    model sizes and can therefore exceed 25; white is the residual `else`. No
    prose boundary claims — where a boundary lands depends on which branch
    evaluates first at those model sizes (with large models `dist == 25` can be
    green, not white), so the spec's expected values are derived by executing
    the source's branch order, never from a paraphrase. Constants copied
    digit-for-digit, including the ranged-only **`t.model_size > 1.6`** +0.1
    adjustment — keyed on the *target's* size alone, like magic's `> 2`, even
    though both sizes feed the band constants.
  - **RNG auto-resolves to `default`** — DistancePlus itself gives RNG `Default`
    plus a chat nudge to pick a weapon mode manually; same here, with the nudge
    living in the `mode` command's status output rather than login chat.
- **Mode selection:** derived from `main_job`, re-read on the 200ms poll that
  feeds `set_self` (no `job change` event registration needed; DistancePlus
  sleeps 2s around that event to dodge a race we simply never enter — polling is
  at most 200ms stale instead), overridable and persisted via the component's
  first command:
  **`//hud targetbar mode auto|default|magic|ninjutsu|gun|bow|xbow`** (`auto`
  is the default and follows the job). This makes TB3 the milestone that
  introduces `handle_command`.
- **Self model size** comes from `get_mob_by_target('me')` on the same 200ms
  poll — nil-guarded like every mob read; an unresolvable `me` falls back to
  `default` coloring rather than guessing a threshold. Only the target itself
  (`'t'`) is read every frame.
- **Not ported:** the pet-distance readout, the height/`z`-delta readout, and the
  JA range list — separate DistancePlus features nobody asked for here.

## Cast bar (TB4, decided 2026-08-07)

A second, subordinate bar showing what the target is casting or readying. Built
**after** TB2 verifies the base widget in-client; specified here so TB0–TB2 leave
room for it (bounds, prim budget, config keys).

- **Placement:** below the HP bar, **right-aligned to the widget box's right
  edge** (`origin.x + ROW_WIDTH`, ~285px — decided 2026-08-07 after review,
  superseding the HP bar's 128px edge: a leftward-growing text anchored at 128px
  had less room than a glyph-width estimate could guarantee; the full row's width
  is the most room the widget has to give). Size **50% of the HP bar's,
  uniformly** (`cast.scale = 0.5`: 64×32 from the authored 128×64 — one factor,
  both axes, so the key cannot underdetermine the height), accepted as visually
  subordinate. At 0.5 the frame's band is ~7px tall and the **fill's — the part
  that actually conveys progress — is ~4px** (its band is 8px at full size);
  whether that reads as
  a bar at all is a TB4 in-client check, with the fallback being a larger
  factor. The spell/ability name sits **below the cast bar** at `cast.font_size`
  (10), styled by the widget's `text_color`/`text_stroke`, right-aligned to the
  same box edge. **Its character cap is derived, not fixed:**
  `floor(ROW_WIDTH * 0.9 / (cast.font_size * RATIO))` at the current config
  values — the 0.9 keeps a deliberate tenth of the row as margin, since a cap
  derived from the *whole* row hands the estimate's entire error budget to the
  contract edge; an edited font size shrinks the cap instead of walking the
  text out of the box, and `cast.name_max_chars` (20) is an additional
  ceiling, not the guarantee. `cast.font_size` itself is clamped to a whole
  number >= 1 before the division (0 would yield an infinite cap that silently
  defers to the ceiling; a negative one, a negative cap fed to a substring);
  `cast.name_gap` and `cast.gap` clamp at 0 (a hostile negative would hoist
  the name row above the origin, which no frame-position floor reaches), and
  the main `name_max_chars` clamps to a whole number >= 1, same
  negative-substring hazard as the cast cap.
  **Every `cast.*` key is clamped in `geometry`, same policy as `gap`:**
  `cast.scale` to (0, 1] — which, with `ROW_WIDTH` floored at the HP frame's
  128px, guarantees the right-anchored cast frame (at most 128 wide) fits
  between the origin and the box edge — and the cast frame's computed x and y
  each floored at the origin besides. Hostile config values degrade the layout,
  never the contract.
  Vertical geometry gets its own config keys — `cast.gap` (4; HP band bottom to
  cast frame band top, same band-offset clamp as the HP bar) and `cast.name_gap`
  (2; cast band bottom to name top) — so TB0's bounds/containment assertions
  have concrete numbers, not placeholders. Full stack, top to bottom:
  `HP% | distance | name` row (left-aligned) → HP bar (left-aligned) → cast bar
  (right-aligned to the box edge) → cast name (right-aligned to the box edge).
  The box's height runs from the origin to the cast name row's bottom **or the
  lowest prim footprint, whichever is lower** — at the defaults the name row is
  lower and the HP frame's transparent tail is covered; the formula, not the
  coincidence, is what the spec asserts.
- **Fill color: the unclaimed pale yellow, `230,230,138`** (decided 2026-08-07,
  superseding the `#BFA34C` first specified) — the same value as the claim
  palette's unclaimed state, but a separate config key: the cast fill is fixed,
  never claim-driven.
- **Data source: the `action` event**, which Windower pre-parses from the `0x028`
  action packet — no raw bit-unpacking. For an action whose actor is the current
  target: spell cast start (category 8) carries the spell id; TP-move readying
  (category 7) the ability id; completion (categories 4 / 11) closes the bar.

  **Verification, 2026-08-07 (this is what TB4 was gated on):**
  - *Confirmed* against the Events / Action Event wiki: the action table carries
    `actor_id`, `category`, `param`, `target_count` and a `targets` array (each
    with `id` and an `actions` array). Category meanings are documented exactly
    as assumed — **4** "Finish spell casting", **7** "Begin weapon skill or TP
    move", **8** "Begin spell casting **or interrupt casting**", **11** "Finish
    TP move".
  - *Confirmed*: `cast_time` is a real field on a spell resource entry and is in
    **seconds** — `addons/shortcuts/shortcuts.lua:387` and
    `addons/GearSwap/helper_functions.lua:1054` both test
    `r_line.cast_time == 8` and halve it for Pianissimo, which is the 8-second
    bard song cast.
  - **Blocking finding: the `action` event is deprecated.** The Events wiki
    marks it *"Deprecated! Use incoming chunk with ID 0x028."* Whether it still
    fires cannot be settled here. The documented replacement is the raw
    `0x028` chunk — which is the variable-length bit-packed packet this design
    chose the event specifically to avoid, and which Windower's `fields.lua`
    does not usefully define.
  - **Still unverified: how to tell a begin from an interrupt inside category
    8.** The `param 28787` figure remains community lore with no source
    backing. *A design that does not need it* is available and preferred: treat
    a category 8 from the current caster whose `param` does not resolve to a
    known spell as the interrupt, and give every bar a duration timeout so an
    unclosed cast expires on its own rather than sticking.

  **Superseded, 2026-08-08 - TB4 is implemented on a different data source.**
  The enemybar2 fork (AkadenTK/enemybar2, `actionTracking.lua`) settled every
  open question by example, each fact then confirmed against Windower's own
  API definitions or library users (GearSwap, Debuffed, battlemod):

  - **Route:** not the deprecated `action` event at all -
    `windower.packets.parse_action(data)` on the raw `0x028` chunk, a
    Windower-provided parser (definitions/windower.lua:1178). This repo's
    entry point already dispatches every incoming chunk to every component,
    so the cast bar needs no new event registration whatsoever.
  - **Ids:** on a *start* packet (categories 7/8; 9 is an item start, which
    monsters never send and this component does not track) the acting id is
    `targets[1].actions[1].param`; on a finish (3/4/5/6/11) it is the root
    `param`. Spells resolve via `res.spells`, an NPC's category-7 readying via
    `res.monster_abilities` **indexed directly, no offset**.
  - **Interrupts are structural, not a magic number:**
    `targets[1].actions[1].message == 0` with `targets[1].id == actor_id`
    on a start-shaped packet is the interrupt. `param 28787` is not needed.
  - Belt kept anyway: every bar carries an expiry (duration plus grace), so a
    close the packet stream never delivers still times out.

  The paragraph below records the state before this was known.

  **Consequence: TB4 is not implemented.** Its data source is deprecated with an
  unverified replacement, and the plan's own ordering puts it after TB2's
  live-client pass, which has not happened.

  **And its reservation was dropped too** (2026-08-07, after the first review
  round). This section had TB0 reserve the cast rows in `bounds` and the
  `cast.*` keys in `defaults`, so the box would not change size when TB4
  landed. With TB4 deferred indefinitely that inverts: the shipped widget would
  carry a drag box ~28px taller than anything it draws, and write six config
  keys nothing reads into every character's file. Neither is recoverable from
  the user's side, and re-adding both alongside the feature is one bounds
  change. So the widget's box now describes exactly what it draws, and TB4
  brings its own geometry, keys and containment cases with it - including the
  requirement above that the box not grow mid-cast, which only has meaning once
  something casts.
- **Fill progress is an estimate:** the server never sends cast duration.
  `res.spells[id].cast_time` drives the fill for spells — **the field's existence
  and units are unverified**, same footing as the category/param numbers below:
  confirm in the resources library before trusting it. Completion/interrupt snaps
  the bar closed whatever the estimate said. TP moves have no duration data at
  all — their bar shows the name with a fixed-duration sweep (~2s, tuned
  in-client), which is honest about being an animation rather than a measurement.
- **Names** come from `res.spells` / `res.monster_abilities`, making the *cast
  feature* dependent on the `resources` library. **The component still registers
  under `libraries_error`** — unlike the party list (useless without resources,
  so the entry point skips it wholesale), targetbar's HP bar, name and distance
  need no resources, and a missing spell-name lookup must not cost the user the
  whole widget. Instead the ctx's `resources` is nil in that case and the cast
  bar simply never shows; everything else works.
- **Right-aligned text is new ground for this repo.** Every existing text prim is
  deliberately left-justified because `texts.pos` adds `ui_x_res` to `x` when the
  right flag is set. For the cast name that behavior is *used* rather than avoided:
  `right_justified(true)` plus `pos(right_edge - screen_width, y)` cancels the
  offset. Giltracker's plan weighed this mechanism and rejected it *because its
  text would have grown leftward past the origin* — the same hazard exists here,
  and two things neutralize it together: the anchor is the box's right edge (the
  full `ROW_WIDTH` of room, not the bar's 128px), and the character cap is
  *derived from that room at the current font* (see Placement), so the estimated
  worst case always fits with margin. ~85% — the offset behavior is documented
  in CLAUDE.md from real debugging, but this exact compensation must be verified
  in a live client during TB4 smoke before it is trusted. Screen width reaches
  the geometry as `geometry`'s `screen_width` parameter — logic is pure and
  holds no `ctx`; the widget reads `ctx.screen()` and passes it in.
- **State machine** (`logic.lua`): `idle → casting(spell, started_at, duration) →
  idle`, cleared on completion, interrupt, target switch, **target loss**
  (`clear_target` — a deselect mid-cast must not leave a bar for the next
  acquire, mirroring the ease's clear-then-reacquire rule), target death and
  detach. Zone change needs no trigger of its own: the framework forwards no
  zone event to components, and none is needed — zoning drops the target, so
  the next tick's `get_mob_by_target('t')` returns nil and `clear_target`
  fires. Subsumed, not missing.
  A cast by anything other than the current target id is ignored. Progress is
  driven by a `now` **parameter** on the tick — logic holds no clock, same
  convention as `due_for_poll(now)`; the widget passes `ctx.now()` (`os.clock`
  in the entry point, a fake clock in specs).
- **Bounds include the cast rows permanently**, target casting or not: a drag box
  that grows when the mob happens to cast would make layout mode's hit test
  unpredictable. Preview mode shows a sample cast ("Fire IV", mid-fill) so the
  full footprint is visible while arranging.

## Architecture

Mirrors `src/components/giltracker/` and `src/components/partylist/`'s split: pure
state in `logic.lua`, prims in `targetbar.lua`.

```
src/components/targetbar/
  targetbar.lua        -- widget factory new(ctx): owns prims, implements the contract
  logic.lua             -- pure: ease, HP% band, text formatting, layout math, occupancy
  defaults.lua           -- returns function(screen_width, screen_height) -> defaults
  assets/
    xiv/
      BarBG.png          -- copied from partylist's xiv theme, unmodified
      Bar.png
      BarFG.png
    LICENSE.txt           -- BSD 3-clause notice, © 2024 Tylas (ships in the package)
tests/components/
  targetbar_spec.lua
  targetbar_logic_spec.lua
```

- **`logic.lua`** (the testable core), shaped like parambar's:
  - `set_target(mob)` / `clear_target()` — the frame's raw facts in, as one table
    carrying everything downstream needs: `id` (ease reset on identity change, TB4
    cast-actor matching), `name`, `hpp`, `claim_id`, `in_party`, `is_npc` (claim
    state), `distance`, `model_size` (TB3). A `nil` mob or non-number `hpp` is
    "not occupied" (`windower.ffxi.get_player()`-style `nil` guarding from
    CLAUDE.md); a changed `id` snaps the ease to the new target's width instead
    of sliding.
  - `set_self(id, model_size, main_job)` — the player's own id (claim ownership
    and the self-vs-member branch), the `'me'` model size and the job for TB3's
    auto mode; nil-tolerant (a missing id degrades the "mine" and "member"
    branches gracefully, a missing model size falls back to `default` coloring).
    Fed on the 200ms poll, not per frame — `main_job` and `model_size` change
    rarely, and parambar's own per-frame `get_player()` read is deliberately
    bounded, a discipline this component keeps.
  - `set_party_ids(ids)` — the claim-ownership roster, fed from
    `ctx.get_party()` on the same 200ms `due_for_poll` cadence; nil-tolerant (an
    unknown roster means only the player's own claim reads as "mine").
  - `due_for_poll(now)` — the 200ms gate itself (partylist's pattern, true on
    the first call), owned by logic so the cadence is spec-testable.
  - `set_config(config)` — config ingress on every attach (parambar's shape:
    `attach` hands logic the freshly loaded table). **It also resets the poll
    gate** — the "attach resets the poll gate" requirement in Goal needs an
    owner, and this is it: partylist has no such reset (its `next_poll` is a
    construction-time local), so this is new surface, not inherited.
  - `set_preview(on)` / `preview()` — the layout-mode sample toggle
    (parambar/giltracker precedent), consumed by `texts()` and the preview
    spec cases.
  - `resolve_mode(configured, main_job)` — maps `"auto"` plus the job to an
    effective mode (RNG → `default`); explicit modes pass through.
  - `command(args)` — the `//hud targetbar mode ...` parser (TB3), returning the
    reply line and whether config changed, parambar's `command` shape.
  - `claim_state()` → `"dead" | "mine" | "member" | "pc" | "unclaimed" |
    "claimed"`, the reference's six branches in its priority order, driving the
    fill tint.
  - `ease(target_width, fill_width)` — parambar's exact algorithm (`EASE = 0.1`,
    `math.ceil` convergence), single bar, running 0..102 (the fill region's
    authored width), not 0..128. Returns `width, hidden` like parambar's — a
    fill eased to exactly 0 (death) is *hidden*, not drawn at zero width; the
    widget gates the fill prim on it, partylist's `not entry.hidden` pattern.
    Parity caveat, kept: parambar's `hidden` goes true on the frame *after* the
    width converges to 0, so death draws one frame at zero width before hiding
    — invisible in practice, and the spec asserts the parity behavior, not an
    idealized same-frame hide.
  - `band_for(hpp)` → `"red" | "orange" | "yellow" | "normal"`.
  - `texts()` → the three row segments (`"63%"`, `"12.40"`, capped name), or the
    preview sample when `set_preview(true)`; each carries its own color state.
  - `range_state(mode, dist, self_size, target_size)` → the DistancePlus color
    state (TB3; `default`/white until then).
  - `occupied()` → boolean.
  - `geometry(x, y, scale, screen_width)` → text pos/size, bar bg/fill/fg
    pos+size (band-offset
    maths per the Deviations section), mirroring `giltracker.lua`'s `apply_layout`
    pattern of one function that returns every prim's placement for a given origin
    and scale. Every placement stays inside `bounds` — that containment is a spec
    assertion, not a hope.
  - `bounds(x, y, scale)` → `x, y, width, height`, computed exactly as the
    Deviations section specifies — restated here because a stale formula in
    this bullet has already survived one review round: `width` is
    `max(sum of the three reserves, 128 * scale)` with reserves computed from
    the rounded drawn font at the current scale (**already at scale — no
    further `* scale`**); `height` runs from the origin to the cast name row's
    bottom **or the lowest prim footprint, whichever is lower** (at a small
    `cast.font_size` the HP frame's transparent tail is the lower edge). The
    TB4 rows are reserved from TB0 (the Cast bar section requires bounds
    include them permanently), so the box never changes size when a mob casts.
  - Preview sample: a mid-length name, 40% HP (mid-range, landing in the orange
    band under the strictly-less-than thresholds — 63 would be yellow), and the
    `mine` claim tint on the fill (the state a player is looking at most while
    actually fighting).
- **`targetbar.lua`**: builds **three text prims** (HP%, distance, name) and three
  image prims (bg/fill/fg) via `ctx.new_text`/`ctx.new_image` — every image with
  `fit(false)` before `size()`, non-negotiable here since the textures are 2× their
  drawn size and `fit(true)` would defeat both the halving and the widget scale
  (CLAUDE.md's own trap list); every text with `bg_visible(false)` and
  `bg_alpha(0)` at construction, partylist's `text()` helper verbatim — a text
  background is a drawn element with its own footprint, and the containment
  promise covers it (no `bg` config key, matching partylist rather than
  giltracker). On each `update()` (no arguments — the per-frame
  tick) calls `ctx.get_mob_by_target('t')`, feeds `logic.set_target`/
  `clear_target`, and pushes the eased fill width plus each text's color, same
  "only write what changed" discipline `partylist.lua`'s `push`/`want` helpers use
  (worth copying literally rather than re-deriving, given it is the one component
  here with a per-frame prim write). **`update(event, ...)` for anything it does
  not want — `chunk`, `add item`, `remove item`, `status`, the vital changes — is
  an explicit no-op** (with a spec case): `core.dispatch` feeds every component
  every forwarded event, and guard disables a throwing handler after five
  failures, so "ignore gracefully" is load-bearing, not politeness. Implements
  the full widget contract: `name`, `defaults`, `attach`, `detach`, `set_pos`,
  `set_scale`, `set_preview`, `show`/`hide`, `get_bounds`, `update`, `destroy`.
  `handle_command` arrives with TB3 (`//hud targetbar mode ...` — see the
  Distance section); TB0–TB2 ship without one. TB4 adds four prims: the cast
  bar's three layers plus the cast name text.

### Framework integration (what TB1 must change outside the component)

Smaller than giltracker's, since this component is poll-driven like partylist, not
packet-driven:

1. `src/XIVHud.lua`: one more `core.register(new_targetbar({...}))` step, `ctx` gains
   `get_mob_by_target`, `get_party` (the claim-ownership roster), `get_player`
   (own id for `check_claim`; TB3 reuses it for `main_job`) and `now` (the party
   throttle clock) alongside the existing `new_text`/`new_image`/`screen`/`asset`.
   The partylist versions of `get_mob_by_target` and `get_party` are inline
   closures built *inside its registration loop*, not module-level locals like
   `get_player`/`screen`/`asset` — sharing them means **hoisting both to
   module-level locals first**, a small named step of TB1, not a free reuse.
   **No new `windower.register_event` in TB1**: the mob is read inside `update()`
   on the existing `prerender` tick, exactly as partylist already reads
   `'t'`/`'st'` there. (TB4 adds one event — `action`, dispatched as
   `core.dispatch("action", act)`, gated on **`safe_mode` alone** like
   `prerender` — NOT on `libraries_error`, which gates the packet/item block:
   folding `action` in there would kill the cast bar's whole degrade path,
   since a resources failure is exactly when the component runs with the cast
   feature off. The vital/status/zone registrations are deliberately
   unconditional in the entry point. Plus `resources` in the ctx; see the Cast
   bar section.)
2. The registration step opens with `if safe_mode then return end` —
   parambar's form. The other two component steps gate on
   `safe_mode or libraries_error`; targetbar deliberately does **not** take
   `libraries_error` (see the Cast bar section's degrade path).
3. `check_assets()`'s hardcoded texture list gains
   `components/targetbar/assets/xiv/BarBG.png` (and the other two) — a missing
   texture fails silently per CLAUDE.md, so the load-time check is what catches an
   incomplete install.

## Settings (`defaults.lua` → `data/<Character>/targetbar.lua`)

snake_case keys; no XML/`config` — this repo's `lib/settings` owns persistence, as
everywhere else.

```lua
{
  font = "Arial", font_size = 14,
  text_color  = { a = 255, r = 240, g = 255, b = 255 },   -- partylist's off-white
  text_stroke = { width = 2, a = 200, r = 6, g = 45, b = 84 }, -- partylist's stroke
  bands = {                                                 -- HP% band colors, number only
    red    = { r = 252, g = 129, b = 130, a = 255 },
    orange = { r = 248, g = 186, b = 128, a = 255 },
    yellow = { r = 243, g = 243, b = 124, a = 255 },
    -- "normal" (>= 75%) deliberately absent: it falls back to text_color,
    -- partylist's own arrangement (normal = TEXT_COLOR in its palette).
  },
  fill_colors = {                                            -- claim palette, on the fill
    dead      = { a = 255, r = 155, g = 155, b = 155 },      -- hpp == 0 (mostly moot at width 0)
    mine      = { a = 255, r = 255, g = 204, b = 204 },      -- claimed by us (party/alliance)
    member    = { a = 255, r = 102, g = 255, b = 255 },      -- targeting a party member
    pc        = { a = 255, r = 255, g = 255, b = 255 },      -- any other player
    unclaimed = { a = 255, r = 230, g = 230, b = 138 },      -- free to pull
    claimed   = { a = 255, r = 153, g = 102, b = 255 },      -- someone else's
  },
  name_max_chars = 17,                                       -- partylist's main-row cap
  gap = 8,                                                   -- text-bottom-to-visible-band spacing;
                                                             -- default keeps the frame prim's
                                                             -- transparent top at/below the origin
  distance = {                                               -- TB3; reserve drawn from TB1
    mode = "auto",                                           -- auto|default|magic|ninjutsu|gun|bow|xbow
    colors = {                                               -- DistancePlus's four states
      out    = { r = 255, g = 255, b = 255, a = 255 },       -- white
      capable = { r = 255, g = 255, b = 0, a = 255 },        -- yellow (ranged, no sweet spot)
      good   = { r = 0, g = 255, b = 0, a = 255 },           -- green (square shot / in casting range)
      best   = { r = 0, g = 0, b = 255, a = 255 },           -- blue (true shot)
    },
  },
  cast = {                                                   -- TB4; keys reserved now
    fill_color = { a = 255, r = 230, g = 230, b = 138 },     -- the unclaimed pale yellow; fixed
    scale = 0.5,                                             -- uniform, both axes, of the HP bar
    font_size = 10,                                          -- cast name row
    gap = 4,                                                 -- HP band bottom to cast band top
    name_gap = 2,                                            -- cast band bottom to name top
    name_max_chars = 20,
    tp_move_sweep = 2,                                       -- seconds; no real duration exists
  },
  slots = {
    default = {
      -- Centered on the full row-width box, near the reference's y = 50 anchor.
      -- ROW_WIDTH duplicated locally in defaults.lua (giltracker's precedent:
      -- its RESERVED_WIDTH is a local re-derivation) - logic's value needs a
      -- config that does not exist yet when defaults are built.
      pos = { x = math.max(0, (screen_width - ROW_WIDTH) / 2), y = 50 },
      scale = 1, visible = true,
    },
  },
}
```

Dropped from the reference entirely: the `target change` event gate and every
`bg_*_settings`/`tbg_cap_*` prim constant (superseded by the xiv art's own bg/fg
layers and per-frame occupancy). The claim palette is **not** dropped — it moved
to the fill (`fill_colors` above).

## Testing strategy

All against `logic.lua` with plain tables; prim fakes (`tests/support/fakes.lua`'s
`M.prims()`/`M.prim()`) only for the widget layer, following giltracker's split:

- **Occupancy**: `set_target` then `clear_target` flips `occupied()`; a `nil` mob
  or non-number `hpp` is treated as unoccupied rather than crashing the band lookup.
- **Easing**: table-driven against parambar's own cases — converges from 0 to a
  target, converges from a target back down, `math.ceil` reaches exactly 0 and
  exactly the fill width (102) rather than asymptoting forever; a target **identity
  change snaps** to the new width instead of sliding (12%-mob to 100%-mob in one
  frame), and so does **clear-then-reacquire of the same mob** — a deselect and
  retarget must not resume a hidden mid-slide.
- **Banding**: `hpp` at 0, 24, 25, 49, 50, 74, 75, 100 — boundary-exact, matching
  partylist's `<` (strictly less than) semantics.
- **Claim state**: all six branches in priority order — dead outranks "mine",
  "mine" via own id, via a party id, via an *alliance* id (the upgrade over the
  reference); a targeted party member vs. self (`in_party` with own id is not
  "member" — and with `set_self` never called, self degrades to "pc" rather than
  miscoloring); unclaimed vs. claimed-by-other; **`claim_id == 0` is never
  "mine", even with a nil or 0 self id** (the reference's `player_id = 0`
  default bug, fixed here) — and a party member with `claim_id == 0` is still
  "member", not "unclaimed" (the branch order matters); a mob table missing
  `claim_id` entirely normalizes to unclaimed, not someone-else's-claim;
  unknown roster (`set_party_ids` never called) still
  resolves "mine" from `set_self`'s id; a roster entry without a loaded mob is
  skipped, not crashed on; the poll asks for the roster at most once per 200ms
  window.
- **Text**: name with spaces, an empty string (should not happen from
  `get_mob_by_target`, guarded anyway), a name past `max_chars` truncated,
  formatting at 0% and 100%, distance clamped at 99.99.
- **Layout math**: `geometry`/`bounds` at scale 1 and non-1 (including the 0.25
  floor, where the rounded-font convention matters); the eased width is capped
  at the fill region's 102, not the frame's 128; **the origin invariant
  directly** — `bounds(x, y, s)` returns exactly `x, y`, and every placement
  `geometry` emits (text, frame, fill, and the TB4 rows once present) lies inside
  the bounds box, at scale 1 and non-1. This is the invariant core's clamp and
  layout mode's drag both assume; it gets its own assertions, not an in-client
  eyeball. **Hostile config values** get their own containment cases: tiny
  `font_size` (the `ROW_WIDTH` floor), `name_max_chars = 3` and negative,
  oversized/zero/negative `cast.font_size`, oversized `cast.scale`, negative
  `gap`, negative `cast.gap` and `cast.name_gap` (the above-origin hoist) —
  each clamps rather than escaping the box.
- **Preview**: sample text/band in, cleared target's last real value restored on
  exit (giltracker's `set_preview` precedent).
- **Distance/mode** (TB3): `range_state` table-driven across all six modes with
  DistancePlus's own constants — boundary-exact at each band edge, the
  `model_size > 1.6` adjustment, distance 0 (white in the source), and a nil
  `me` mob falling back to `default`; mode auto-derivation per job; the mode
  command round-trips through config and rejects unknown modes with a hint.
- **Cast state machine** (TB4): a cast from the target's id starts the bar; one
  from any other actor is ignored; completion, interrupt, target switch, target
  death and detach each clear it; fill progress at 0%, mid-cast, and past the
  estimate (clamped at full until the server closes it); a TP move runs the fixed
  sweep; an unknown spell/ability id degrades to a generic label, not a crash.
- **Widget level**: `attach`/`detach` show and hide correctly; `destroy` disposes
  every prim (three texts + three bar layers in the base widget); a frame with no
  target hides the bar and all three texts (not just some); fill width write is
  skipped when unchanged (partylist's `push` discipline), asserted via the fake
  prim's `calls` log.

In-client smoke (Windows/Windower): bar appears on `/target`, tracks HP down and up
smoothly, snaps (not slides) on a target switch, clears on target loss, band color
changes crossing 75/50/25%, the fill turns yellow on an unclaimed mob, light red
the moment the party claims it, purple on someone else's claim, and cyan targeting
a party member (and confirms the neutral-art assumption — the tints must render
true, not muddied by a baked-in hue), drag/scale in `//hud layout` persists,
`//lua reload xivhud` leaves no prims, a long **capital-heavy** enemy name (the
0.75 glyph ratio's worst case — the one thing the unit suite cannot check)
truncates at the cap, stays inside the drag box, and
the drag box covers everything drawn.

## Milestones

The framework (M0–M3) and the partylist xiv art it borrows from are both merged, so
nothing here is blocked.

- **TB0 — pure logic**: `logic.lua` + `defaults.lua` + spec for the TB0 surface
  (occupancy, ease, banding, claim state, formatting, geometry/bounds,
  preview), green locally. `range_state`/`resolve_mode`/`command` are TB3
  additions to the same file, the cast machine TB4 — "full" spec only for what
  each milestone lands.
- **TB1 — widget + assets + wiring**: `targetbar.lua`, the three xiv PNGs +
  `LICENSE.txt` copied in, the three entry-point changes above, registered with
  `core.register`; in-client smoke.
- **TB2 — layout integration**: drag/scale/preview/bounds verified in `//hud
  layout`, in particular that `get_bounds()` returns the text row's origin, not the
  bar's, and that the drag box covers the full drawn footprint (capped name, cast
  row reserve included).
- **TB3 — distance coloring** (see the Distance section): the DistancePlus mode
  port in `logic.range_state` + spec, `main_job` auto-selection, the
  `//hud targetbar mode` command (the component's first `handle_command`);
  in-client smoke against DistancePlus itself running side by side — same
  number, same color transitions. (The ctx already has everything it needs from
  TB1.)
- **TB4 — cast bar** (see the Cast bar section): verify the `action` event's
  category/param semantics **and** `res.spells[].cast_time` against the library
  sources first; then the cast state machine + spec in `logic.lua`, the four extra
  prims (three bar layers + name text), the `action` registration in the entry
  point (`core.dispatch("action", act)`), the resources-degrade path (component
  registered, cast bar off), and in-client smoke — including the right-justified
  compensation, the ~7px band's legibility at `cast.scale = 0.5`, spell casts, TP
  moves, interrupts, and a mid-cast target switch.
- **Backlog** (2026-08-07, order TBD): a `subtargetbar` component, independently
  positioned (the reference's fixed offset is not worth preserving once layout slots
  exist); an "out of range" or distance-based treatment (the reference has none —
  would be new scope, not a port); ~~a stretch-safe regenerated bar frame if the
  authored 128px footprint reads too small in a live client~~ — **it did**
  (TB2's first in-client look, 2026-08-08), and the frame is now regenerated at
  4x width by cap-preserving centre-column replication, with the claimed-by-us
  red deepened to FF1414 in the same pass; component commands to retint the
  claim palette or resize the bar without hand-editing the config file.
- **Rejected** (2026-08-07): target buff/debuff icons. The server never tells the
  client a monster's status effects — there is no mob equivalent of the party-only
  `0x076` — so the only route is inferring state from the `0x028` action and `0x029`
  message packets, which misses anything applied before the addon was watching,
  cannot know real durations, and needs per-message-ID resist/wear-off mapping.
  Judged too unreliable to ship; not backlogged.

## License & attribution

The bar art (`BarBG.png`/`Bar.png`/`BarFG.png`) is XIVParty's `xiv` theme, BSD
3-clause © 2024 Tylas, already redistributed once under
`components/partylist/assets/LICENSE.txt` — this component ships its own
`assets/LICENSE.txt` per the duplication decision above, **written for the
three files it actually contains**: the BSD notice plus their attribution, not
a byte copy of partylist's 98-line notice, most of which documents job icons,
buff icons and a background-art remap this directory does not carry. The reference addon's own art (`bg_cap.png`/`bg_body.png`/`fg_body.png`) is
**not used or redistributed** — only its behavioral approach (read the current
target, drive a bar off `hpp`) is re-implemented, the same "notice covers it either
way" reasoning giltracker's plan used for the `giltracker` addon's refresh state
machine. The distance mode thresholds and per-weapon constants are ported from
**DistancePlus** (BSD 3-clause © 2017 Sammeh of Quetzalcoatl) — behavioral
re-implementation, no assets redistributed, same reasoning. Our source files keep
the repo's own BSD header (**© 2026, Azureblood2**) — `tests/sources_spec.lua`
fails the build without it.

## References

- enemybar source: https://github.com/Windower/Lua/tree/dev/addons/enemybar
  (facts above verified against `dev`, 2026-08-07)
- DistancePlus source:
  https://github.com/Windower/Lua/blob/dev/addons/DistancePlus/DistancePlus.lua
  (mode thresholds, weapon constants and colors read in full, 2026-08-07)
- **Live contract** (authoritative): [CLAUDE.md](../../CLAUDE.md) "Modular design &
  testing" + `src/lib/core.lua` (`dispatch`, `on_prerender`) and
  `src/components/partylist/` as the working example for xiv-themed bar art and
  per-frame target reads.
- Gil Tracker plan: [giltracker.md](giltracker.md) — sibling component, widget
  contract precedent and asset-attribution phrasing.
- FFXI Functions (`get_mob_by_target`, mob table fields):
  https://github.com/Windower/Lua/wiki/FFXI-Functions
- xiv theme geometry and license: `src/components/partylist/layout.lua`,
  `src/components/partylist/assets/LICENSE.txt`

## Post-plan iteration (2026-08-08, in-client)

The shipped widget deviates from the sizes first specified above, tuned live:

- The health bar art is regenerated at **4x width** (drawn 512x64) by
  cap-preserving centre-column replication; never stretched at runtime.
- The cast bar draws its **own art at 2x width** (drawn 256x64, the same
  transform) at `cast.scale = 0.67` - about a third of the health bar, not
  the half-scale-of-512 first specified - with the name at 12pt below it.
- The claimed-by-us fill red is `255,20,20` (#FF1414), not the reference's
  pale pink; the cast fill keeps the unclaimed pale yellow.
- The text row is inset one character from the bar's left edge.
- The cast bar takes four extra prims (three art layers + the name text),
  six images and four texts in all.
