# Status bar (statusbar / sb) — component plan

Status: DONE bar the in-client pass. SB0 merged as PR #40 (5bcca8d) and
SB1-SB4 as PR #42 (213c09f), both into dev on 2026-09-05; the worktree and
both branches are gone. SB5 - verification in a live client - is the only
milestone outstanding, and its list is below. Scope as built: new
`src/components/statusbar/`, partylist's buff order/filter machinery promoted
into `src/lib/`, the registration block in `src/XIVHud.lua`, the `0x063`
pre-parse in the chunk handler with the crossbar's skillchain engine and
expbar switched to the parsed table, and specs. Framework (`lib/core`,
`lib/layout*`, `lib/registry`) untouched: no contract change was needed -
multi-anchor, per-anchor visibility and scale, `handle_command`, chunk
dispatch, `on_mouse` and preview all existed already.

Two things landed after the plan was written, both on Kevin's ask: the
`enhancements` filter is named `buffs`, and hovering an icon names its buff
while a right-click on one sends `cancel <id>` to the cancel addon
(`//hud statusbar tooltips on|off`).

Reference for the anchored-component shape: `src/components/partylist/` (three
anchors, per-anchor variant, per-anchor `visible` seeded off) and the
partylist-anchors plan beside this one.

## Goal

The FFXIV status display for FFXI's own buff/debuff icons: the player's active
status effects as icon grids with the remaining time overlaid under each icon,
as the in-game display draws it. One component, three independently placed
bars (XIV's "split into multiple elements"), each configurable to 1–4 rows
(20x1 / 10x2 / 7x3 / 5x4). Bar 1 defaults to the predefined `All` filter and
on; bars 2 and 3 default to `Debuffs` and `Other`, off. `Other` is food and
system buffs (Signet, Sanction, Sigil, dedication, etc.).

## Decisions taken before writing anything (2026-09-04, from the user)

1. **Categories are curated tables in the component.** `res.buffs` carries no
   category field. The debuff id set is transcribed from the debuff section of
   the shipped buff order (currently delimited only by comments); the `Other`
   set (food, Signet/Sanction/Sigil, EXP/CP boosts, dedication…) is hand-curated
   against `res.buffs`; `Enhancements` is everything in neither set; `All` is no
   category restriction at all.
2. **Overflow cuts at capacity.** A shape holds 20/20/21/20 icons; XI allows 32
   buffs. Priority order decides who survives, exactly partylist's icon-cap
   rule, and the `buff` show-verbs reach past the cap so a hidden buff stays
   promotable.
3. **Timer text is XIV style, under the icon.** One token: seconds under a
   minute (`59`), then minutes (`12m`), then hours (`2h`). No text when the
   remaining time is unknown (see the 0x063 facts below).
4. **The order+filter engine promotes to `lib/`** — and, widened by decision 5,
   the buff command machinery with it. Partylist passes its own config
   (priority overrides, filter list, mode); each statusbar bar passes its
   assigned filter. The two components' settings stay separate; nothing is
   shared at runtime but code and the shipped data.
5. **Full editing verbs in v1.** Statusbar gets its own `buff
   top|up|down|rank|reset`, `buff list|find`, and per-bar `filter
   add|remove|clear|list` / `filter mode` from day one, served by the same lib
   the partylist verbs delegate to.
6. From the opening ask: three sub-anchors always, bars 2 and 3 off by default.
   **Per-bar on/off is the framework's per-anchor `visible`** (PR #37,
   2026-08-31 - merged after the first draft of this plan, which had a
   component-owned `enabled`): bar2/bar3 seed `visible = false` on their
   anchors exactly as partylist's alliance lists do, the switch is `//hud
   show|hide statusbar <bar>` or SHIFT + right-click in layout mode, and the
   widget implements `show(anchor)`/`hide(anchor)`. No component-owned flag -
   a second switch beside the framework's could only disagree with it.

## Open items (confirm before the affected milestone)

- **`0x063` has three readers - RESOLVED 2026-09-04 at Kevin's instruction.**
  The crossbar's skillchain engine (`skillchain.lua`, transcribed from the
  SkillChains addon) decoded the order-9 id array off the raw bytes, expbar
  ran `packets.parse` itself per chunk for order 2, and the status bar decoded
  order 9 from the raw bytes too. Now the entry point pre-parses the id once
  through `packets.parse` (its 0x063 definition switches on the order byte,
  and it stores raw values under `Buffs n` / `Time n` - both verified in the
  Windower sources) and all three read the table; `skillchain.on_chunk` grew
  a third argument, expbar's `update` a fourth, and the status bar's
  `packets.lua` interprets the parsed table rather than the bytes. expbar's
  seed at attach still calls `packets.parse` on `last_incoming` - that is a
  re-read, not the chunk stream.
- **One spec edits its require path (SB0).** `tests/components/partylist_buff_order_spec.lua:1`
  requires `components/partylist/buff_order`; moving the data to
  `lib/buff_order` breaks that line. Mechanical path fix (the spec's assertions
  are unchanged). DONE in SB0 under the "start implementing" sign-off; the spec
  moved to `tests/buff_order_spec.lua`. A second pinned test grew a line in
  SB1: `component_aliases_spec` lists the shipped aliases and now includes
  `sb`.

## Reference facts

Verified 2026-09-04 against `Windower/Lua@dev` `addons/libs/packets/fields.lua`:

- **`0x063` is a multi-type packet**, dispatched on the byte at offset 0x04
  (`data:byte(5)` in Lua's 1-indexing). **Type `0x09` is the self-buff
  duration packet**:

  ```
  func.incoming[0x063][0x09] = L{
      {ctype='unsigned short',    label='_unknown1',          const=0x00C4},      -- 06
      {ctype='unsigned short[32]',label='Buffs',              fn=buff},           -- 08
      {ctype='unsigned int[32]',  label='Time',               fn=bufftime},       -- 48
  }
  ```

  Offsets include the 4-byte header, i.e. they are offsets into the `original`
  string the chunk dispatch hands over. 32 buff ids (u16) at 0x08, 32
  timestamps (u32) at 0x48, slot-aligned.
- **The timestamp decode**, verbatim from `fields.lua`:

  ```lua
  bufftime = function(ts)
      return fn(1009810800 + (ts / 60) + 0x100000000 / 60 * 10) -- increment last number every 2.27 years
  end
  ```

  So the raw value is 60ths of a second since epoch 1009810800 (2002-01-01
  JST), wrapped at 32 bits (~2.27 years per wrap); Windower hardcodes the
  current wrap count (10). **Decision: resolve the wrap at runtime instead** —
  pick the wrap multiple that lands the expiry nearest `os.time()`. Buff
  durations are bounded far below 2.27 years, so "nearest now" is always the
  right wrap, and the component never needs the comment's biennial increment.
- The packet has a full field definition, but the entry point pre-parses only
  ids with **more than one reader** (CLAUDE.md). Statusbar is 0x063's only
  consumer, so it decodes the raw bytes in its own `packets.lua`, like
  partylist's 0x076 — two fixed-stride arrays, no `packets` library needed.

Repo facts:

- **Presence comes from `ctx.get_player().buffs`** (ids only, `255` = empty
  slot, KO = real id 0). The entry point already calls the keyed
  `invalidate("player")` on `gain buff`/`lose buff`, so the service answers a
  buff change promptly; nothing new is needed there. Timers come from the last
  0x063-09, held as an id→expiry map (duplicate ids assigned in slot order);
  presence and timers are matched by id, never by slot, because the two
  sources' slot orders are not vouched for.
- Rationale for two sources rather than 0x063 alone: after `//lua reload`
  nothing re-sends 0x063 until a buff changes, so a packet-only bar comes up
  empty; `get_player().buffs` is live immediately. The cost is icons without
  timers until the next 0x063, which is the honest state.
- **Icon art**: `assets/xiv/buffIcons/<id>.png`, 640 files, 32x32 native
  (partylist draws them 20x20). Statusbar draws at 32 (native, no resample);
  the framework's per-anchor scale resizes beyond that. A missing id draws
  nothing (silent-texture fact) — acceptable, and what partylist lives with.
- The engine being promoted is `logic.lua:620–755` (settings shape guard,
  override merge with the descending-id insert order, filter set, sort with id
  tie-break, cap) plus the command half at `logic.lua:1091+` (`resolve_buff`
  with the multi-hit disambiguation, listing/paging, priority and filter
  mutation). `buff_order.lua` is the 621-entry shipped data, already carrying
  its XIVParty/Windower attribution, which travels with the move.

Unverified — needs a live client (SB5):

- The empty-slot marker in 0x063's Buffs array (0xFF expected, matching
  `get_player().buffs`; possibly 0, which would collide with KO). Both 0xFF
  and 0xFFFF are read as empty; the array is 16-bit, so if id 255 is ever a
  real status its timer would vanish while its icon stayed - `lib/buff_order`
  skips 255 between 254 and 256, so the risk is small.
- What Time holds for a timerless buff (Signet et al.) — expected to be a
  sentinel; until verified, any expiry that decodes absurdly far out or
  non-positive draws no text.
- Whether 0x063-09 arrives on zone-in/login without a buff change (expected
  yes; affects only how soon timers appear after a reload).
- The tooltip (2026-09-05: a hover names the buff under the cell, a right-click
  sends `cancel <id>`) sits under the cell's timer band, which for the last
  row is the bar's bottom edge: a bar clamped to the bottom of the screen
  draws its tip off screen, and bar1's tip overlaps bar2's icons under the
  shipped 56px stacking. Whether to flip it above the cell near the bottom
  edge is a live-client call.
- That 0x063 in the live client is not blocked/reshaped by the dispatch path —
  the usual "green locally does not mean it loads" caveat.

## Architecture

```
src/lib/
  buff_order.lua        -- the 621-entry shipped priority, moved verbatim from
                           components/partylist/ (attribution intact)
  buffs.lua             -- new(deps) -> engine + CLI helpers:
                           order(overrides) -> ranks, ordered   (memoized; invalidate())
                           plan(ids, {ranks, filter, whitelist, cap, category_set})
                           resolve(text) -> id | lines           (name/id lookup, multi-hit)
                           priority verbs (top/up/down/rank/reset over an overrides table)
                           filter verbs (add/remove/clear/list/mode over a filters table)
                           listing/paging
src/components/statusbar/
  statusbar.lua         -- prims and every ctx read; outer widget routing the
                           contract by anchor over three inner bar instances
  logic.lua             -- pure state machine: grid plan per bar, timer tokens,
                           dirty tracking, the command parser
  packets.lua           -- the 0x063-09 decode (raw bytes -> {id, expiry} pairs)
  categories.lua        -- curated DEBUFFS and OTHER id sets; buffs =
                           neither; all = no restriction
  defaults.lua          -- config + layout defaults (three anchors)
```

- **Anchors** `bar1`, `bar2`, `bar3` — names not roles, since any filter can be
  assigned to any bar. Report order 1→3; layout mode hit-tests reversed for
  free. Visibility is the framework's, per widget and per anchor; layout mode
  force-shows a hidden anchor so it stays draggable, with sample buffs + fake
  timers in preview.
- **Grid**: rows 1–4 map to 20x1 / 10x2 / 7x3 / 5x4 (capacity 20/20/21/20).
  Fill left-to-right, top row first, in priority order; left-justified inside
  the full-shape width so `get_bounds` returns the origin `set_pos` was given
  as icons come and go (giltracker's rule). Cell = 32px icon + timer text
  band beneath (exact band height tuned at SB2).
- **Per frame**: read `ctx.get_player().buffs`, run each shown bar's plan,
  repaint only when a bar's id list or any displayed timer token changed —
  token granularity means at most one text write per icon per second, and a
  settled bar with no timers costs nothing.
- **Timers**: remaining = expiry − `os.time()`; ≤ 0 or unknown draws no text
  (presence alone governs the icon — the client removes the buff, not the
  clock).
- **Priority overrides are component-wide** (one order across the three bars,
  like partylist's one order across six members); filters are per bar.

## Settings (`defaults.lua` → `data/<Character>/<slot>/statusbar/config.lua`)

```lua
{
  priority = {},                      -- id -> wanted rank, shared by all bars
  bars = {
    bar1 = { filter = "all",     rows = 1, filters = {}, filter_mode = "blacklist" },
    bar2 = { filter = "debuffs", rows = 1, filters = {}, filter_mode = "blacklist" },
    bar3 = { filter = "other",   rows = 1, filters = {}, filter_mode = "blacklist" },
  },
  timers = true,
}
```

Layout defaults: three anchors seeded resolution-relative (partylist's ANCHORS
pattern), bar1 top-left per the ask, bar2/bar3 stacked beneath it and carrying
`visible = false` (absent means shown, so bar1 says nothing).

## Commands

Registered `statusbar`, alias `sb` (free: cb/pb/gt/ev/tb/pl taken; validated at
registration and by `component_aliases_spec` as usual). The bar word is
optional and defaults to `bar1`, partylist's optional-list-word grammar:

```
//hud statusbar                          -- all three bars: filter, rows
//hud statusbar [<bar>]                  -- one bar
//hud statusbar [<bar>] filter all|buffs|debuffs|other
//hud statusbar [<bar>] filter add|remove|clear|list [<id|name>]
//hud statusbar [<bar>] filter mode blacklist|whitelist
//hud statusbar [<bar>] rows <1-4>
//hud statusbar timers on|off
//hud statusbar buff                     -- what each bar draws, past the cap
//hud statusbar buff list [page] | find <text>
//hud statusbar buff top|up|down <id|name> | rank <id|name> <n> | reset
```

`filter` is deliberately one verb: a category name and an edit sub-verb cannot
collide (`all|buffs|debuffs|other` vs `add|remove|clear|list|mode` share
no word). `buff` verbs take no bar word — priority is component-wide — and a
bar word in front of one is refused, partylist's refuse-don't-ignore rule for
a structurally wrong scope.

## Testing strategy

busted + `tests/support/fakes.lua`, TDD per the workflow skill.

- `tests/buffs_spec.lua` — the promoted lib: override merge (including the
  descending-id insert order), filter/mode, cap, resolve disambiguation,
  paging. Seeded from the existing partylist assertions for these behaviours.
- `tests/buff_order_spec.lua` — the moved data spec (621 entries, no
  duplicates, KO/weakness/doom first); relocated from
  `tests/components/partylist_buff_order_spec.lua`.
- `tests/components/statusbar_logic_spec.lua` — grid plans per shape, category
  filters, layering, timer tokens (59/12m/2h boundaries), dirty rules, parser.
- `tests/components/statusbar_packets_spec.lua` — 0x063-09 decode against
  hand-built byte strings, wrap resolution around `now`.
- `tests/components/statusbar_spec.lua` — the widget over the prim recorder:
  contract, three anchors, show/hide per anchor, preview, get_bounds stability.
- Partylist's existing specs stay green through SB0 **unchanged** except the
  relocated buff_order spec (see Open items).
- `component_aliases_spec` gains `sb`; `sources_spec` covers the new files.

## Milestones

- **SB0 — lib promotion, no behaviour change.** Move `buff_order.lua` to lib;
  extract the engine + CLI helpers into `lib/buffs.lua`; partylist delegates.
  Every partylist spec green (one require-path edit, pre-approved). Own PR.
- **SB1 — skeleton.** Registration, three anchors (bar2/bar3 hidden by
  default), defaults, rows + predefined filter verbs, preview. Draws icons from
  `get_player().buffs` through the lib with category sets stubbed minimal.
- **SB2 — categories + render polish.** The curated tables; grid geometry
  tuned; dirty rules.
- **SB3 — timers.** `packets.lua`, the expiry map, the token renderer,
  `timers on|off`.
- **SB4 — editing verbs.** Priority verbs, per-bar filter editing (layering
  semantics confirmed first), `buff` listings.
- **SB5 — in-client verification.** The unverified list above, plus the usual
  load/safe-mode pass.

## License & attribution

`lib/buff_order.lua` keeps its XIVParty (BSD 3-clause © 2024 Tylas) /
Windower-resources attribution block as-is. `categories.lua` is derived the
same way the order data was (ids from Windower's generated resources, grouping
informed by XIVParty's ordering) and carries the same note. No new art: the
bars draw partylist's existing `assets/xiv/buffIcons/`.
