# Target bar: a subtarget anchor - plan

Status: BUILT 2026-09-05 in worktree `.claude/worktrees/targetbar-anchors`,
branch `work/claude/targetbar-anchors` off dev (a316cc6, #43). 3433 specs green,
luacheck and stylua clean; the blind review gate returned ISSUES on round 1 and
CLEAN on round 2. What actually shipped is recorded under "Decisions taken while
building" at the foot; the phases below are as planned.

Scope as built: `src/components/targetbar/` (defaults, logic, widget), the two
targetbar specs, and CLAUDE.md. **No framework change** - `src/lib/` is not touched, and neither
is `src/XIVHud.lua` (core routes anchors generically; targetbar's registration
block carries no anchor knowledge). Precedent to follow throughout:
`.claude/Planning/partylist-anchors.md` and `src/components/partylist/partylist.lua`.

## Goal

Give `targetbar` a second anchor, `subtarget`, drawing
`get_mob_by_target('st')` - the `<st>` selection cursor - on its own bar,
independently placed and scaled, alongside the existing target bar (`main`).

## Reference

[AkadenTK/enemybar2](https://github.com/AkadenTK/enemybar2). The live path is
`enemybar2.lua` - `bars.new(settings.subtarget_bar)` fed each prerender from
`update_bar(subtarget_bar, windower.ffxi.get_mob_by_target('st'), ...)` - a
second, smaller frame (width 300 against the target bar's 600, font 12 against
14) at its own position, wearing the same claim palette. The repository also
carries a legacy `subtargetBar.lua` from enemybar 1.0, which is dead code: it
hides the bar when `subtarget.id == target.id`. That rule is **not**
reproduced; see decision 3.

Everything the reference's subtarget bar shows, this component already draws
for the target. `logic.lua` is entirely mob-agnostic (`set_target(mob)`), and
the frame is a fixed 512 scaled by the framework - so "smaller" is a per-anchor
scale, not a second geometry.

## Decisions taken before writing anything (Kevin, 2026-09-05)

1. **Per-anchor config, partylist's scheme.** The component's display settings
   move under `bars.<anchor>` (`bars.main.*`, `bars.subtarget.*`), so each bar
   carries its own font, colours, name cap, range mode and cast block.
2. **Breaking, and nothing migrates.** A stored `targetbar/config.lua` has its
   keys at the top level; they are not read after this and are left in the file
   as dead weight (the settings merge preserves what the defaults do not
   mention), exactly as partylist's merge did on 2026-08-30. A user's range
   mode comes back on the shipped default.
3. **No `st == t` suppression.** The bar draws whenever `st` resolves, matching
   enemybar2's current unified code rather than enemybar 1.0's comparison. A
   subtarget cursor sitting on the current target therefore draws the same mob
   twice, which is accepted.
4. **Full parity.** The subtarget bar draws the same row (`hp% | distance |
   name`), the same health bar and the same cast bar as the main one. No
   feature flags through logic or geometry.
5. **Shipped defaults:** `subtarget` is **visible** out of the box, seeded under
   the main bar, at scale **0.6** (roughly the reference's 300/600 ratio).

## Phases

### TB1 - Restructure targetbar.lua into an outer widget over two inner bars

`partylist.lua`'s shape: an inner factory per anchor, each holding its own
logic instance, its own prims, its own geometry and its own `written` cache;
an outer widget that routes the contract by anchor.

- `local ANCHORS = { "main", "subtarget" }` and `local TOKEN = { main = "t",
  subtarget = "st" }`. The token is the only thing that differs between the two
  instances - the inner factory takes the variant and reads its own.
- `anchors()` returns `ANCHORS`. Order is what `//hud list` prints, and layout
  mode hit-tests it reversed, so `subtarget` wins an overlap.
- `set_pos`/`set_scale`/`get_bounds` take the trailing anchor and route through
  a `bar_at(anchor)` guard: an anchor that is not ours costs nothing rather
  than crashing core's apply (partylist's `list_at`, same reason).
- `show(anchor)`/`hide(anchor)`: a name addresses one bar; **bare fans to
  both**, and a bare `show()` must undo every per-anchor hide - it is what
  layout mode force-shows with.
- `set_preview`, `update`, `destroy` fan out to both. The `0x028` chunk reaches
  both cast trackers; each bar tracks the mob it is drawing.
- **Hoist the per-generation client read to the outer widget.** Both bars want
  the same `set_self` / `set_party`, and running it twice would walk eighteen
  member tables twice per interval for an identical answer. The outer widget
  holds `last_generation`, refreshes once at the top of the per-frame tick and
  pushes into both logics; `attach` resets it (the relog defence the current
  code already carries). The target read stays inner - the token differs, and
  `lib/player` memoizes both for the frame.

### TB2 - Defaults and the config namespace

- `defaults.lua` returns `{ bars = { main = {...}, subtarget = {...} },
  layout = { anchors = { main = {...}, subtarget = {...} }, visible = true } }`
  with **no top-level `pos`/`scale`** - `layout.repair` keys the anchored
  branch off the defaults and would shed a stray pair anyway.
- Each bar's block is the current flat set verbatim (font, font_size,
  text_color, text_stroke, bands, fill_colors, name_max_chars, gap, distance,
  cast). The two ship identical: the subtarget's smaller size is its anchor
  scale, not a smaller font.
- `main`'s seeded position is what it is today (centred, y 50). `subtarget` is
  seeded directly under it, centred on its own drawn width at 0.6.
- **Proposal, for review:** derive both seeds by constructing a logic instance
  over the bar's own config and calling `logic.bounds(0, 0, scale)`, rather
  than the hand-copied row arithmetic `defaults.lua` carries today - whose own
  comment calls the duplication latent drift, and which a second bar at a
  second scale doubles. An intra-component require, which the isolation rule
  allows. If that is unwanted, the fallback is to copy the height arithmetic
  beside the width arithmetic and keep the two comments matched.
- `attach` splits `config.bars.<anchor>` per bar, replacing an unusable entry
  with a **fresh** copy of the defaults and writing it back into the config -
  partylist's defence, and for its reason: handing a bar `self.defaults` would
  have every later command write where `save()` does not serialise.

### TB3 - Commands

The bar word leads, so the verb grammar behind it is untouched:

```
//hud targetbar                            -- both bars
//hud targetbar <bar>                      -- that bar alone
//hud targetbar [<bar>] mode auto|default|magic|ninjutsu|gun|bow|xbow
```

- `<bar>` is `main` or `subtarget`; absent means `main`, so every line that
  worked before this still means what it meant.
- A first word that is not a bar falls through to the verb parser unchanged.
- `logic` is told its variant at construction so its replies and its hint name
  the bar; `status()` gains the bar's name. One config file and one saver, so
  a change in either bar saves the same way it does now.

### TB4 - Change-gate the placement setters

`core.apply` fans `set_scale`, `set_pos` and `set_preview` over **every**
anchor on **every** call, and layout mode calls it per raw mouse-move event -
the defect partylist's PA0 measured at ~5000 prim calls per event. This
component is ten prims a bar rather than 267, so the cost here is small, but
the guard is three lines: return early when the value has not changed, and
scope the re-layout to the bar addressed. Cheap, and it stops the second
anchor making the drag path twice what it was.

### TB5 - Docs

- CLAUDE.md: "Two components are multi-anchor" becomes three, with targetbar's
  `main` / `subtarget` listed beside partylist's and crossbar's.
- The targetbar paragraph: the subtarget bar and where it comes from, the
  per-anchor config namespace, the breaking change and that nothing migrates,
  the `st == t` decision, and the shipped defaults.
- The Commands block: targetbar's optional bar word.

## Testing

TDD throughout, per the `tdd-workflow` skill; a blind review gate before the PR.

- `tests/components/targetbar_spec.lua`: `anchors()`; per-anchor
  `set_pos`/`set_scale`/`get_bounds` routing and the unknown-anchor no-op;
  bare `show()` undoing a per-anchor hide; per-anchor attach seeding a fresh
  defaults copy over an unusable entry and writing it back; the subtarget
  instance reading `'st'` and the main one `'t'`; the chunk reaching both cast
  trackers; **one** roster rebuild per generation across both bars; command
  routing with and without the bar word; both bars destroyed.
- `tests/components/targetbar_logic_spec.lua`: replies and hints naming the
  bar. The rest of logic is unchanged - it never knew which mob it held.
- Defaults: no top-level `pos`/`scale`; `subtarget` seeded below `main` at
  0.6; no `visible` key on either anchor (absent means shown, and the
  subtarget ships on).
- Green means `busted` + `luacheck .` + `stylua --check .`.

## Unverified - needs a live client

- Whether `get_mob_by_target('st')` returns nil when no subtarget cursor is
  up, and whether it mirrors `'t'` while the cursor rests on your current
  target (~70% that it is nil with no cursor). Decision 3 makes a mirrored
  `'st'` draw the same mob twice; worth an eye in-client.
- Whether the seeded subtarget position clears the main bar at both scales on
  a real screen. The box includes the art's bottom padding, so the gap will
  read larger than it measures.

## What this plan does not do

Nothing else from enemybar2: no focus-target frame, no aggro stack, no action
or debuff tracking, no target-of-target enmity readout.

## Decisions taken while building (2026-09-05)

Six, each either Kevin's call at the moment it came up or a fix the review gate
forced:

1. **A placement naming no anchor is a no-op** (Kevin), partylist's `list_at`
   rule rather than a shorthand for the main bar: core names an anchor for every
   placement it makes on an anchored widget, so a nil is a wiring slip, and one
   that quietly moved the main bar would leave the slip looking like success.
   The cost was ~25 spec call sites gaining a `"main"` argument.
2. **`defaults.lua` measures through `logic.bounds`** rather than the hand-kept
   copy of the row arithmetic that stood there under a comment calling its own
   drift latent - the plan's proposal, taken. A second bar at a second scale
   would have doubled that copy. logic holds no ctx and reads no client, so
   building one to ask it a question costs nothing.
3. **Two bars walk the party twice** (Kevin). `get_party()` - the call that
   allocates eighteen member tables - is made once per interval by the outer
   widget and pushed into both bars, but each bar walks those eighteen keys for
   its own claim set. The spec that pinned 18 now pins 36, restated to say what
   it holds: one client read per interval, one roster per bar. The alternative
   was moving `PARTY_KEYS` out of logic's privacy for 18 table lookups.
4. **The roster is pushed only into a bar that could draw with it** (review
   round 1), which is `ready()`: attached, placed, laid out. Note it does NOT
   consider `visible`, so in production both bars are permanently ready once
   attached - see the open item below.
5. **`set_pos`'s change gate compares the SCREEN as well as the origin** (review
   round 1). `apply_layout` re-reads `ctx.screen()` because the cast name is
   right justified and its x pre-subtracts the width the library adds back, so
   a resolution change moves that text without moving the origin - and core
   re-pushes the same origin afterwards, which a gate on the origin alone would
   swallow, leaving the name off screen by the delta until something else moved
   the bar.
6. **logic takes a `variant`** and names its bar in every reply
   (`targetbar subtarget range mode set to bow`), defaulting to `main`: two bars
   answering identically would leave the user unable to tell which one they had
   just changed.

### Open, and deliberately not done

- **A hidden bar still costs a read.** `ready()` does not consider `visible`, so
  `//hud hide targetbar subtarget` still pays a `get_mob_by_target('st')` and a
  `logic.tick` every frame, plus its 18-key roster walk per interval. That is
  exactly what the main bar has always done while hidden, so gating on `visible`
  is a change to both bars' behaviour and is Kevin's call, not a bugfix.
- **The `'st'` token is still unverified** (the plan's own open item), and the
  failure mode is worth stating: `lib/player` does not `pcall` the client call
  and `render` runs inside the shared guarded `prerender`, so if `'st'` were a
  token `windower.ffxi.get_mob_by_target` rejects by raising rather than by
  answering nil, `lib/guard` would disable the prerender handler after five
  frames and take the whole HUD down with it. Confidence the token is valid:
  ~80%; it is the first thing to check in a client.
