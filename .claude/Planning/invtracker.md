# Inventory tracker (invtracker / inv) - component plan

Status: BUILT 2026-09-05 in worktree `.claude/worktrees/invtracker`, branch
`work/claude/invtracker` off origin/dev (085d0c8, #41), fast-forwarded to
ceecd58 on 2026-09-05 with the statusbar (#40, #42) in - one trivial conflict,
the alias line in CLAUDE.md. 3374 specs green, luacheck and stylua clean. The plan below was written first, from the
reference source alone; Kevin approved it by instructing the build, and the
"Decisions to take" section is kept as written with what actually shipped
recorded under "Deviations taken while building" at the foot.

Scope as built: `src/components/invtracker/` (logic, defaults, widget,
LICENSE.txt), one entry-point dep and a registration block, two component
specs, the alias spec, the entry-point spec and its harness, CLAUDE.md. No
framework change was needed: single anchor, `handle_command`, chunk dispatch,
`add item`/`remove item`, `job change` and preview all existed.

Sibling precedent and the model to copy: `src/components/giltracker/` (same
author's addon, same packet-driven no-polling posture, `wants_chunk` gating)
and `src/components/equipviewer/` (a grid of slots, reads `get_items`, catches
equipment changes on the incoming `0x050`). Plans beside this one:
[giltracker.md](giltracker.md), [equipviewer.md](equipviewer.md).

Branch from **origin/dev** (`085d0c8`, #41) - the local `dev` checkout is seven
commits behind it and not mine to move. In flight and to merge cleanly around:
#40 (`lib/buffs`) and #42 (statusbar), which touch the entry point's
registration block and `tests/component_aliases_spec.lua` - the two files this
work also edits.

## Goal

The FFXIV Inventory Grid HUD widget for FFXI: every slot of the chosen bags
drawn as a tiny coloured square, empty slots dim, occupied ones coloured by
status (plain / full stack / equipped / linkshell / bazaar / temporary), one
block per bag laid side by side - a re-implementation of the Windower
`invtracker` addon (1.0.0, BSD 3-clause, (c) 2017 sylandro, from
`azamorapl/windower-lua` `personal`) as a framework component, dragged and
scaled in `//hud layout` with the rest.

## Reference facts (verified 2026-09-05 against the source; 700 lines read in full)

### What it draws

- Per slot, TWO `images` prims at the same position: a 3x3 `background` and a
  2x2 `box` on top of it, both `slot.png` (a 1x1 RGBA pixel) with `fit=false`,
  tinted per status. So a slot is a 2px square with a 1px darker L on its
  right and bottom, on a 4px pitch (`spacing = 4`) - a 1px gap.
- One block per bag; blocks run left to right, `blockSpacing = 4` apart.
  Inside a block slots go left to right for `maxColumns`, then the next row
  goes UP (`y - (row-1)*spacing`): the whole thing is anchored bottom-left of
  the first block at `(xRes - 365, yRes - 50)` and grows upward. Blocks are
  bottom-aligned with one another.
- The block x offset is `(sum of previous blocks' columns)*spacing +
  (block-1)*blockSpacing`, BUT the column sum is only advanced when a block's
  last slot lands on a full row (`update_indexes`: `current_slot ==
  last_index` inside the `% max_columns == 0` branch). Every default bag is 80
  slots in 4 or 5 columns and equipment is 16 in 4, so it never bites there;
  a bag of 81 or 30 columns would overlap the next block. Ours computes block
  width as `columns * spacing` outright.
- Bags, in draw order, with default `visible` / `maxColumns`: equipment
  (on, 4, the sixteen slots in a fixed order), inventory (on, 5), safe + safe2
  (off, 5, one setting for both), storage (off, 4), locker (off, 5), satchel
  (on, 5), sack (on, 5), case (on, 5), wardrobe 1-4 (off, 5, one setting for
  all four; wardrobes 5-8 do not exist to it), temporary (on, 1 column),
  treasury (on, 1 column).
- Ordinary bags draw `bag.max` slots, occupied or empty. The temporary bag and
  the treasure pool draw only their occupied slots (tempItem colour), then
  blank the rest by alpha 0 - and both blocks are laid out as though they had
  `bag.max` (temporary) or 80 (treasure) slots, which at 1 column means the
  block is ONE slot wide and the grid height is the tallest block's anyway.
- Status colours (rgb, alpha) and their darker backgrounds:
  default `0,170,170` / `0,60,60`; fullStack `245,40,40` / `100,0,0`;
  equipment `253,252,250` / `50,50,50`; equipped `150,255,150` / `0,100,0`;
  linkshellEquipped same as equipped; bazaar `225,160,30` / `100,100,0`;
  tempItem `255,130,255` / `100,0,100`; empty `0,0,0` at alpha 150 both.
  Item status ids: 0 none, 5 equipped, 19 linkshell equipped, 25 bazaar
  (wiki confirms the four). Full stack is `count == res.items[id].stack`.
  Any other status draws as EMPTY (a defect: a status the addon does not know
  makes an occupied slot vanish).
- `sort = true` sorts each bag in place before drawing: status descending,
  then closest to a full stack first, then count descending. The README says
  why: "there is no way to get the inventory sort order". With sort off the
  slots draw in `get_items` index order.

### Data flow: event-driven, never polled

`windower.ffxi.get_items()` (the whole table, every bag, every time) is read
by `setup_indexes()` and only when a flag says something changed:

- `add item` / `remove item` for any id but 0 and 65535 (gil) -> `refresh_items`.
- outgoing `0x050`/`0x051` (equip / equipset) and `job change` -> `refresh_all`;
  outgoing `0x10A` (bazaar price) -> `refresh_inventory`; outgoing `0x0C4`
  (linkshell equip) arms a flag that `linkshell change` turns into
  `refresh_inventory`.
- incoming `0x01C` (Inventory Size) -> `refresh_all` if any VISIBLE, ENABLED
  bag's size differs from what was drawn (`(max+1) ~= packet size`).
- incoming `0x01D` (Finish Inventory) is the ONLY place a flag turns into a
  read: `initialize()` on the first one after a zone, else the highest flag
  set wins (`all` > `items` > `inventory`). A change whose packets are not
  followed by a `0x01D` waits for the next one.
- incoming `0x0D2`/`0x0D3` (treasure find / lot) re-count the pool at once.
- incoming `0x00A` (zone in) clears `inventory_loaded` and shows; `0x00B`
  (zone out) hides; status 4 hides; Scroll Lock toggles.

`get_items()` per-bag tables carry `max` and `enabled` (the reference reads
`items.storage.max`, `items.safe.enabled`, `items.temporary.max`) as well as
the top-level `max_<bag>` / `enabled_<bag>` pair the wiki documents, and
`get_bag_info()` answers `count`/`max`/`enabled` per bag without pushing the
items (wiki: "much more efficient if only these values are desired"). Bag ids
and their `get_items` keys come from `res.bags[id].api` (0 inventory, 1 safe,
2 storage, 3 temporary, 4 locker, 5 satchel, 6 sack, 7 case, 8 wardrobe,
9 safe2, 10-16 wardrobe2-8, 17 recycle).

Packet fields verified against `libs/packets/fields.lua`: `0x01C` is one
`unsigned char` size per bag (`Inventory Size` ... `Wardrobe 8 Size`,
`Recycle Bin Size`); `0x01D` is `Flag` (1 = every bag loaded) + `Bag`;
`0x01E` (Item Count) carries `Count`/`Bag`/`Index`/`Status` and no item id.

### Defects to fix, not port

1. **No `unload` handler** - prims leak on reload (giltracker's, again).
2. Every function and `xBase`/`yBase`/`current_x`/`current_y`/`full_stack_a`
   are globals.
3. An unknown item status draws the slot as empty.
4. Wardrobes 5-8 and the recycle bin are invisible to it.
5. The block-offset bug above (harmless at its defaults).
6. Treasure/temporary rows lay out as if 80 / `max` slots wide - harmless at 1
   column, wrong at any other.
7. A pending change is not drawn until a `0x01D` happens to arrive.
8. `config.save(settings)` at load and the whole colour table in settings.xml -
   framework-owned here.
9. Drops for free: the hide key, cutscene/zoning hiding, `pos`, `visible`
   (framework-owned, as with every port).

## Decisions to take (each is a proposal; none is built)

1. **Key `invtracker`, alias `inv`.** Matches the reference addon's name like
   every other port; `inv` is free (`cb pb gt ev tb pl sc eb sb` taken) and is
   what a player types. Alternatives: `inventory` / `iv`. (Confidence the alias
   rule accepts `inv`: 95%, it is 2-4 letters starting with a letter.)
2. **Plan file name `invtracker.md`** - the sibling convention
   (`giltracker.md`, `equipviewer.md`). Rename if you want another.
3. **Read policy: dirty flag, one `get_items` on the next tick, held while a
   load is in flight.** Any of `add item`/`remove item` (non-gil), incoming
   `0x01E`/`0x01F`/`0x020` (item count/assign/update - equip status, bazaar
   flag and linkshell status all arrive as `0x020` Status changes, which is why
   the reference's four OUTGOING triggers are not needed and the entry point
   does not forward outgoing chunks), `0x050`, `0x01C`, `0x0D2`/`0x0D3` and
   `job change` mark dirty; the frame tick reads once and clears it. Between
   `0x00A` and `0x01D Flag == 1` (the zone-in bulk load, hundreds of `0x01F`)
   the read waits for the finish, giltracker's `inventory_loaded` rule. This
   drops defect 7 and the four-flag maze. Cost: one whole-inventory push per
   frame that saw a change, which a burst of stack changes (crafting, a big
   bazaar sale) would make one per frame for as long as it lasts. If that is
   too dear in a live client, the fallback is a floor of 200ms between reads
   (the player service's interval, already precedent). Confidence `0x020`
   carries equip/bazaar/linkshell status changes: 80% - from the field
   definition (`Status` with `fn=itemstat`) and equipviewer reading it for
   equip state; a live client settles it.
4. **Sizing and enabled-ness come from `get_bag_info()`, not the `0x01C`
   parse** - it is the documented cheap read, so `0x01C` needs no
   `parse_packet` and the component needs no `packets` library; a size or
   enabled change just marks dirty and the read rebuilds the block. That also
   drops the reference's "only if visible and enabled" size filter, which
   existed to avoid a full read for a bag it would not draw - ours draws
   nothing for a disabled bag either, but the read is per dirty frame, not per
   bag, so the filter buys nothing.
5. **Default bags on: inventory, satchel, sack, case, temporary, treasure -
   equipment OFF.** The reference has equipment on; `equipviewer` already
   shows what is worn, and every slot costs two resident prims (below). Every
   bag is switchable at the command line, wardrobes 5-8 included (grouped as
   `wardrobe`, the reference's one setting for all of them; safe covers
   safe2). The recycle bin stays out - nobody tracks its fill. Open: whether
   you want equipment on for parity.
6. **Prim budget.** Two prims per slot at the reference's defaults is 16+80x4+
   ~10+~10 slots = ~700 prims resident; every bag on is ~1,500 slots, ~3,000
   prims; decision 5's defaults are ~360 slots, ~720 prims. The crossbar's 365
   resident prims are "a cost only a live client can price" (CLAUDE.md), and
   this is double. Prims are created per block on first use and kept, never
   per read (the reference's `slot_images[block][slot]` cache, done right).
   The one-prim alternative - drop the 3x3 background and draw a 2x2 tinted
   square on nothing - halves it and loses the L-shaped shadow, which at 1px
   on a 4px pitch is nearly invisible anyway. **Proposal: start with two
   prims for parity and measure in-client; the fallback is a config flag.**
   Confidence that ~700 image prims is fine: 60% - Windower draws each prim
   as its own quad and nothing here has run that many.
7. **Origin is TOP-left and rows go DOWN**, with an `align top|bottom` setting
   (partylist's precedent) defaulting to `bottom` so blocks of different
   heights sit on a common baseline as the reference draws them. Rows growing
   upward from the origin would draw above it, which the framework's clamp
   and `get_bounds` contract forbid. The default placement reproduces the
   reference's footprint: x = W - 365, y = H - 50 - grid height (64px at the
   defaults: 16 rows of a 5-column 80-slot bag on a 4px pitch).
8. **Sort stays, as `sort on|off`, default on** (parity), sorting a COPY of the
   bag rather than the client's table in place. Unverified either way: whether
   the game's own /sort reorders the server slot indices `get_items` returns,
   which would make `sort off` show the real in-game arrangement (the README's
   "no way to get the sort order" suggests not). Live-client question.
9. **Colours are config-only** (`config.lua`, keys per status as giltracker
   does for its text), no colour verbs. An unknown status draws as `default`,
   not empty (defect 3).
10. **`res.items[id].stack` is the only `resources` use**; without the library
    the full-stack colour degrades to `default` and everything else runs
    (targetbar's posture, not giltracker's all-or-nothing gate).
11. **Art: reuse `assets/own/panel.png`** (the 8x8 white square, tinted at
    runtime, `fit(false)`) instead of redistributing a 1x1 pixel. The
    reference's licence still travels: its notice goes in the component's
    `LICENSE.txt` beside the transcribed logic (expbar's precedent), since no
    art of its own is shipped. Confidence a tinted 8x8 drawn at 3x3 and 2x2
    looks identical to a tinted 1x1: 90% - both are flat white with
    `fit(false)`.

## Commands (proposal)

```
//hud invtracker                          -- every bag with on|off and columns, then sort/spacing/align
//hud invtracker <bag> on|off             -- bag: equipment inventory safe storage locker satchel sack case wardrobe temporary treasure
//hud invtracker <bag> columns <n>        -- 1..20
//hud invtracker sort on|off
//hud invtracker spacing <px> | blockspacing <px>
//hud invtracker align top|bottom
```

`<bag>` words are the reference's setting names lowercased; `safe` covers
safe2 and `wardrobe` covers 1-8 as the reference grouped them. Unknown input
answers with the verb list, never silence. Every change persists through
`save` and repaints from the last read without a new one (the read is only
for the data).

## Shape

```
src/components/invtracker/
  invtracker.lua   -- widget: prims per block, the dirty flag, the one read, io none
  logic.lua        -- pure: bag catalogue (id, api key, setting group, draw order),
                      slot classification (status -> colour key), the sort comparator,
                      block geometry + bounds, size-change detection, the dirty
                      policy (which ids, the loading gate), preview, command parser
  defaults.lua     -- per-bag {enabled, columns}, spacing, block_spacing, sort, align,
                      the colour table, layout {pos, scale, visible}
  LICENSE.txt      -- sylandro's notice (no art shipped)
tests/components/invtracker_logic_spec.lua
tests/components/invtracker_spec.lua
```

Entry point: three deps on the ctx - `get_items` (whole table, no arguments;
giltracker's `get_gil` wraps the same call), `get_bag_info` (new, one line,
same `windower.ffxi` shape) and `resources` (nil when the library failed) -
plus `screen`, `asset`, `new_image`, `new_text` (preview label only, if any).
Gated on `safe_mode` alone (decision 10). `tests/entry_point_spec.lua` gains
the registration; `tests/component_aliases_spec.lua` gains `inv`.

Preview (layout mode): the widget must be draggable with nothing loaded, so
`set_preview(true)` draws every enabled bag at its configured size as
alternating default/empty slots (partylist's preview roster precedent).

## Test plan (TDD, spec first per unit)

logic: bag catalogue covers ids 0-16 with the right group and key; status ->
colour for 0/5/19/25/unknown, full stack against a stack size, temporary and
treasure always tempItem; sort comparator on status, then stack gap, then
count, and the input table untouched; geometry: block widths, block x offsets
with gaps, bottom vs top alignment, bounds origin == pos, scale applied to
pitch and sizes; 1-column bags one slot wide; occupied-only blocks blank the
rest; dirty policy: each id/event marks, gil and id 0 do not, loading holds
until `0x01D Flag 1`, `0x00A` re-arms the hold, a read clears; size change
detection from two `get_bag_info` answers; command parser: every verb, bad
bag word, bad number, the report text.

widget: prims created once per block and reused across reads; a disabled bag
creates none; colours and alpha applied per status; hide/show/detach clear
and the prim recorder shows nothing left after `destroy`; the read happens on
the tick after a dirty mark and not on the mark itself, exactly once per dirty
frame, never while loading; treasure/temporary draw occupied count only;
`get_bounds` matches `set_pos`; preview with no read; persistence through
`save` on a command.

## Not verifiable here (needs a live client)

- The resident prim count (decision 6).
- Whether `0x020` carries equip/bazaar/linkshell status flips (decision 3);
  if not, the incoming `0x050` covers equip and the other two need a trigger.
- Whether `get_bag_info()` answers before `0x01D Flag 1` on a fresh zone-in.
- Whether the in-game /sort reorders `get_items` indices (decision 8).
- Whether `get_items()` per frame during a crafting burst is felt.

## Deviations taken while building (2026-09-05)

Five, each a change from the draft above and each cheaper than what it
replaced:

1. **`get_bag_info` is not used at all** (against decision 4). A dirty read
   calls `get_items()` anyway, and that table already carries `max_<bag>` and
   `enabled_<bag>` for every bag. A second call would be a second read that
   could disagree with the first - the grid sized from one answer and filled
   from another - so the capacities ride the same read as the items. The
   component takes one client dep, not two.
2. **The equipment block draws in the equip viewer's 4x4 arrangement**, not
   the reference's. The reference lists its sixteen slots bottom-up because
   its grid grew upward; ours grows downward, and matching the sibling
   component beats matching an inverted list.
3. **`0x01D`'s Flag is read as byte 5 of the raw chunk**, so the component
   needs no `parse_packet` dep and no packets library, and is gated on
   `safe_mode` alone. It is the only field any of its packets carries that it
   wants; every other id means "read everything again" on its own.
4. **The load hold is bounded at 600 ticks.** The draft held reads until the
   settle with nothing to release them if it never came, which would freeze
   the grid on the previous zone's inventory for the session. Windower fails
   silently, so the fallback is to read one frame late rather than never.
5. **The display sort breaks ties on the client's own slot order.**
   `table.sort` is not stable, so slots tying on status, stack gap and count
   could swap between two reads and make a settled grid twitch with nothing
   changed.

Decisions 1, 2, 5, 6, 7, 8, 9, 10 and 11 shipped as drafted, commands
included. Decision 3's read policy shipped as drafted bar items 3 and 4 above.

## Still not verified (needs a live client)

- The resident prim count: about 720 at the shipped defaults, double the
  crossbar's 365, and ~3,000 with every bag switched on.
- Whether `0x020` carries the bazaar and linkshell status flips. Equip is
  covered by `0x050` either way.
- Whether `0x01D` Flag 1 always follows a zone. The bounded hold is the
  fallback if it does not.
- Whether `get_items()` per changed frame is felt during a crafting burst, and
  what `0x050` costs on a GearSwap user: it fires once per slot swapped on
  every cast, so a swap-heavy job marks the grid dirty on many frames. The
  crossbar narrows the same packet to the main hand for that reason; narrowing
  here would cost the other fifteen slots' equipped colour, so it wants a live
  client first.
- Whether the in-game /sort reorders the indices `get_items` returns, which
  would make `sort off` show the real in-game arrangement.

## Review gate

Two blind rounds, both ISSUES, every blocking finding real and taken:

- **R1**: a command enabling a bag repainted from stale data and showed
  nothing until an unrelated packet arrived (which bags are drawn is decided
  at the READ); the bounded hold never re-opened the gate, so the fallback it
  exists for delayed every later change by the full count; and bag capacity
  was read only from the top-level `max_<bag>`/`enabled_<bag>` pair with no
  fallback to the per-bag fields the reference also uses. Four optionals taken
  besides: the preview building squares for eight wardrobes nobody owns, an
  empty grid with no box to drag, a treasure entry carrying no count, and a
  misleading comment about packet byte offsets.
- **R2**: the component was gated on `safe_mode` alone while the chunk and
  item handlers it depends on are gated on the libraries too, so a library
  failure would have left it drawing a frozen grid for the session. Three
  optionals taken: a full repaint on every placement push (layout mode sends
  three per drag event, against hundreds of prims), a sort comparator that was
  not a strict weak ordering when only some items resolved (which `table.sort`
  can raise on, inside prerender, where guard disables the shared handler),
  and the `0x01D` reading that runs opposite to giltracker's, now documented
  in both.
- **R3**: the repaint guard covered only `set_pos`/`set_scale`, while core's
  apply pushes preview and visibility beside them on every mouse-move of a
  drag - measured at 1920 prim calls per redundant apply on a 160-prim grid.
  Four optionals taken: a dead `id` field and `bags()` accessor pinned by
  tests nothing else read (the catalogue is now tested through `layout`, which
  actually consumes it), a comment naming a case that cannot happen, column
  and pitch ceilings enforced only at the command and not on a stored file,
  and a bare bag word answering usage rather than that bag's state. R3's
  blocking finding was fixed but NOT re-reviewed: three rounds is the cap.
- **R4** (Kevin authorised up to five more rounds): CLEAN. Three optionals,
  two taken - the block gap was the one geometry value not clamped on the way
  out of a stored file, and the report printed the stored pitch rather than
  the one drawn. The third is left as is and noted: a hidden or suppressed
  widget still takes its reads, which is giltracker's behaviour too, and
  gating them on visibility would need a dirty mark on show or the grid comes
  back stale.

## Labels (2026-09-05, after PR #43 opened)

Kevin asked for the bag name under each block at 6pt. Decided with him:
SHORT names (`Inv`, `Safe`, `Safe2`, `Stor`, `Lock`, `Sat`, `Sack`, `Case`,
`W1`-`W8`, `Temp`, `Pool`, `Equip`), since a 5-column block is 19px wide and
"inventory" at 6pt is about 40 and would overlap the next block; switchable
with `labels on|off`, on by default. One text prim per block, left-aligned
under its last row, sharing a line across bottom-aligned blocks; the bounds
grow by the gap and the line box. The widget gained `new_text` on its ctx.

Two blind rounds on the delta. R1 ISSUES, real and taken: a label's WIDTH was
ignored, so under the 1-column temporary and pool blocks "Temp" and "Pool"
overlapped and the last label drew outside the bounds - a block is now as
wide as its columns or its label, whichever is more, and the bounds take the
label in; a labels toggle no longer buys a client read (`command` answers
whether a change needs one); the labelled height is pinned. R2 CLEAN, two
optionals taken (one width fallback, one comment). The pre-existing bare
bounds test was scoped to labels-off rather than re-numbered, which R2 noted
against the ground rule; the labelled number is pinned in its own test.
