# Party list on the multi-anchor abstraction - migration plan

Status: draft, 2026-08-29. Worktree `.claude/worktrees/partylist-anchors`, branch
`work/claude/partylist-anchors`, branched from dev at d6ed15c (the commit that landed
crossbar, #25). Scope: `src/components/partylist/`, the registration block in
`src/XIVHud.lua`, and the partylist specs. **No framework change** - `src/lib/` is
touched only if a decision below says so, and none currently does.

Reference for the abstraction: `src/components/crossbar/` (the only current user) and
CLAUDE.md's paragraph on it. Framework side: `core.lua:157-343`, `layout.lua:104-184`,
`layout_mode.lua:79-219`.

## Goal

Collapse the three registered components - `partylist`, `alliancelist1`,
`alliancelist2` - into **one** registered `partylist` component exposing **three
anchors** (`main`, `alliance1`, `alliance2`), so the three lists are positioned and
scaled independently through one widget instead of three.

## Decisions taken before writing anything (2026-08-29, from the user)

1. **Per-list visibility becomes component-owned.** The framework's `visible` is per
   *widget*, not per anchor - `layout_mode.lua:209-219` deliberately drops the anchor
   on right-click, and CLAUDE.md states the rule. So a right-click toggles all three
   lists together, and the per-list on/off that `//hud hide alliancelist1` provides
   today moves into partylist's own config plus a new verb.
2. **One config file.** `data/<Character>/partylist.lua`, with the per-list settings
   namespaced by hand. `alliancelist1.lua` / `alliancelist2.lua` stop existing.
3. **No back-compat.** The user has waived it explicitly. Saved positions in the three
   existing files are discarded; nothing migrates them. (`layout.lua:144` would shed a
   top-level `pos` anyway, and the three old positions live in files the merged
   component never opens.)
4. **The drag-cost fix lands first, as its own commit,** on the current
   three-component shape - see Phase PA0. It is a prerequisite, not a follow-up.

## Why PA0 is a prerequisite, not a nice-to-have

Measured on 2026-08-29 by driving the real component under `tests/support/fakes`
(which records every prim call) and replaying exactly what `core.apply` does:

| | prims | prim calls per mouse-move event |
|---|---|---|
| `partylist` (main, 6 rows) | 267 | **2882** |
| `alliancelist1` | 105 | **1066** |
| idle render frame | - | **0** |

The idle figure is the point: partylist's write cache is already perfect, and the
entire cost is the drag path. It decomposes exactly:

- `core.lua:296` `set_scale(scale)` -> `apply_layout()` = 959 calls. **The scale has
  not changed.**
- `core.lua:297` `set_pos(x, y)` -> `apply_layout()` = 959 calls. The only necessary one.
- `core.lua:331` `set_preview(on)` -> `apply_layout()` = 959 calls. **The preview state
  has not changed.**

`apply_layout` (`partylist.lua:602`) calls `logic.invalidate()` and sets
`row.written = {}` on every row - deliberately clearing the write cache, which is why
every one of the 267 prims takes a full set of property writes - then runs `place_row`
+ `draw_row` across all of them. **Two thirds of the cost is two no-op rebuilds.**

The multiplier: `layout_mode.lua:179` calls `move_to` on every raw mouse-move event,
unthrottled and with no unchanged-position check. Windower forwards these from the
window proc at the mouse's polling rate, not at the frame rate. (That last claim is
inference from how Windower hooks input, ~70% - it is not verified in a client, and it
does not change what the fix is.)

**And the migration makes it worse untouched.** `core.apply` (`core.lua:317-327`) fans
`apply_placement` out over *every* anchor on *every* call, so dragging one anchor of a
merged partylist would rebuild all three lists: roughly 2882 + 1066 + 1066 = ~5000
calls per mouse-move event, ~70% worse than today. Crossbar hit this exact wall and
recorded the fix at `crossbar.lua:1166-1175` - "one mouse move costs 433 prim calls
where it once cost 8530" - by no-op-guarding the setters and scoping the re-layout to
the moved anchor. partylist needs the same defences before it grows anchors.

## Phases

### PA0 - Change-gate the placement setters (prerequisite, own commit)

On the **current** three-component shape, so it can be reviewed, verified and reverted
independently of the restructure.

- `set_scale(s)`: return early when `s == scale`.
- `set_pos(x, y)`: return early when the position is unchanged.
- `set_preview(on)`: return early when the preview flag is unchanged. Note the existing
  comment at `partylist.lua:693-696` - core reads `get_bounds` straight after
  `set_preview` and both reads must land before the next render, so the *first* call
  with a changed value must still do the full work synchronously. Only the repeat is
  skipped.
- Split the position-only path off the full rebuild. A pure move changes nothing
  `draw_row` writes - not a text, colour, alpha, path, visibility or fill width; only
  `place_row`'s coordinates move. So a position change should re-place without
  re-drawing and without clearing `row.written`. A **scale** change must keep today's
  behaviour in full, including the cache clear: the comment at `partylist.lua:596-601`
  records why (the bar fill's width is written by `render()`, not `place_row`, so a
  scale change that only re-placed would leave every fill at the old scale until that
  member's HP happened to move). Do not weaken that.

Test first: a spec that counts prim calls across a simulated drag and asserts an upper
bound, so the regression cannot come back silently. `tests/support/fakes.lua:111-161`
already records every call; the harness in `tests/components/partylist_spec.lua:62-110`
already builds the widget. Assert the shape (a no-op setter costs 0; a move costs
strictly less than a scale change), not the exact number - an exact count would fail on
any innocent layout tweak.

**Expected result:** a drag drops from ~2880 calls to the cost of one `place_row` pass.
Measure it and put the real number in the commit message.

### PA1 - Restructure partylist.lua into an outer widget over three inner lists

The minimum-churn shape, and the one that keeps `logic.lua` untouched:

- Today `partylist.lua` is one closure holding `rows`, `background`, `pos`, `scale`,
  `visible`, `suppressed`, `box` and one `logic` instance, all selected by
  `ctx.variant` (`partylist.lua:60-68`).
- Make that closure an **inner factory** taking a variant, and have the outer `new(ctx)`
  build three of them. Each inner list keeps its own logic instance, its own prims and
  its own `box` - so `logic.lua`, `packets.lua`, `layout.lua`, `jobs.lua` and
  `buff_order.lua` need no changes at all, and `PARTY_KEYS` / `NAMES` keep working.
- The outer widget implements the contract and routes by anchor:
  - `anchors()` -> `{ "main", "alliance1", "alliance2" }` (order matters: it is the
    hit-test priority, reversed at `layout_mode.lua:88-95`, and the `//hud list` order).
  - `set_pos(x, y, anchor)`, `set_scale(s, anchor)`, `get_bounds(anchor)` delegate to
    the named inner list. Follow crossbar's guard (`crossbar.lua:1025-1035`): an unknown
    or nil anchor is a **complete no-op**, not a crash, and `get_bounds` on an anchor
    never positioned returns nil so core skips the clamp and hides its overlay.
  - `show()` / `hide()` / `set_preview(on)` / `attach` / `detach` / `destroy` fan out to
    all three.
  - `update(event, ...)` fans out to all three. Note `handle_chunk` already skips the
    0x076 buff decode on a layout with no buff icons (`partylist.lua:625-633`), so the
    alliance lists stay cheap; keep that.
- Carry PA0's guards into the inner list unchanged - they now matter three times over.

**`get_bounds` must still return the exact origin `set_pos` was given**, per anchor.
CLAUDE.md calls this out and core's clamp and layout mode's drag offsets both depend
on it.

### PA2 - Merge the defaults and the config namespace

`defaults.lua` currently returns one variant's defaults (`defaults.lua:56-105`). It
becomes one merged table:

- `slots.default.anchors = { main = {pos, scale}, alliance1 = {...}, alliance2 = {...} }`,
  seeded from the existing `ANCHORS` fractions and the same autoscale. **No top-level
  `pos` / `scale`** - `layout.lua:135-160` keys the anchored branch off the *defaults*,
  and would shed a stray pair anyway.
- `slots.default.visible = true` stays top-level - it governs the widget.
- **Per-list `shown`** replaces the old per-variant `visible`: alliance1/alliance2 ship
  off, main ships on, matching today's first-run behaviour (`defaults.lua:78-80`).
  Delete the comment at `defaults.lua:35-37` claiming `hideAlliance` needs no port -
  after this change it does, and this flag is it.
- The per-list display settings (`item_spacing`, `align_bottom`, `show_empty_rows`,
  `range`) are per variant today and must stay per list, so namespace them under the
  list key. `hide_solo` and `buffs` remain **main only** - 0x076 carries the main party
  and the alliance layout has no buff icons (`defaults.lua:85-89`).

`lib/settings.lua` needs nothing: `merge_defaults` (`settings.lua:59-69`) recurses into
nested tables generically, so a stored file that has never seen an anchor or a list key
gets it filled in.

**Open, non-blocking:** the exact nesting of the per-list settings (`lists.alliance1.item_spacing`
vs `alliance1.item_spacing`). Either works; going with a single `lists` table keyed by
anchor name, so the anchor name is the one key across code, config, command word and
overlay label - the same rule the component name already follows.

### PA3 - Commands

`logic.command` (`logic.lua:1437-1462`) is per-instance and keeps working as-is; the
outer widget gains a thin router in front of it.

- `//hud partylist [<list>] <verb> ...` where `<list>` is `main` (default),
  `alliance1` or `alliance2`. Leading rather than trailing, so it reads the same as the
  new on/off verb and so the existing verb grammar is untouched behind it.
- `//hud partylist <list> on|off` - the replacement for `//hud show|hide alliancelist1`.
- `//hud partylist` with no args prints all three lists' status (today each component
  printed its own).
- `hidesolo` and every `buff` verb stay main-only and must **reject a list argument**
  rather than silently applying to main - `logic.lua:1002-1006` already builds the verb
  list per variant; keep the asymmetry visible in the error text.
- `//hud show|hide alliancelist1` **stops existing** - `commands.lua` never addresses an
  anchor (`parse_target`, `commands.lua:94-110`), and this was decision 1's accepted cost.

Layout-mode overlay labels become `partylist:main`, `partylist:alliance1`,
`partylist:alliance2` via `overlay_key` (`core.lua:250-252`). Anchor names are
user-visible strings; these are the ones.

### PA4 - Preview must outrank the per-list flag

A list switched off by `shown = false` must still be draggable, or it can never be
positioned again. Core force-shows the *component* in layout mode
(`core.lua:334-341`), but it knows nothing about partylist's own flag.

So: `set_preview(true)` forces all three lists to draw, ignoring `shown`, and
`get_bounds` returns real bounds for all three while preview is on. This is the
component's half of the force-show and it must be a spec'd behaviour, not an accident.

### PA5 - Entry point and docs

- `src/XIVHud.lua:735-762`: one `core.register(new_partylist({...}))`, no variant loop.
  Drop `variant` from the ctx (the outer widget owns the three now); keep `name`.
- Drop `alias` from the ctx at the same time and hardcode `alias = "pl"` in the
  factory beside the name (PR #28 added it). It is only per-registration data
  because ONE factory backs three registrations: hardcoding it today has all
  three claim `pl`, and the second registration aborts the load. With one
  registration that reason is gone and the ctx field is dead weight.
- CLAUDE.md: the partylist bullet, the Commands block, and the line at CLAUDE.md:85
  stating partylist needed no edits when crossbar landed - all three go stale here.
- `wiki/` - check for a partylist page and the framework/positioning prose.
- Note in passing: CLAUDE.md:205 already says crossbar has "four anchors" when it has
  six. Not this change's job; leave it or fix it in a separate commit, do not bundle.

## Testing

Strict TDD per the `tdd-workflow` skill, then the blind independent review gate before
any PR.

- `tests/components/partylist_spec.lua` (844 lines) drives the widget through
  `build(variant)` and `widget.set_pos(100, 200)`. Every call site of the contract in
  that file changes shape. Expect this to be the bulk of the diff.
- `tests/components/partylist_logic_spec.lua` (1461 lines) should be **untouched** -
  `logic.lua` is not changing. If it needs edits, PA1's split is wrong; stop and
  reconsider rather than editing the spec.
- New coverage: the three anchor names and their order; per-anchor origin round-trip;
  independent scaling; nil/unknown anchor is a no-op; bounds nil before placement;
  preview outranks `shown` (PA4); the command router including the main-only
  rejections; and PA0's prim-call budget.
- `tests/sources_spec.lua` enforces the licence headers, the `require('a/b')` slash
  form and the ASCII rule - all still apply to anything new.

Green means `busted` + `luacheck .` + `stylua --check .`. **Green is not loaded**:
nothing here exercises Windower's require resolution, the real prims, or the mouse
path, so the drag-cost improvement and the layout-mode behaviour both want an
in-client check before this is called done.

## What this plan does not do

- Does not add per-anchor visibility to the framework. That was offered and not chosen;
  if it is ever wanted, it changes `layout.lua`, `layout_mode.lua`, `core.lua` and
  crossbar's semantics together.
- Does not touch the other components. parambar, targetbar, equipviewer and giltracker
  stay single-anchor.
- Does not migrate anyone's saved config.
