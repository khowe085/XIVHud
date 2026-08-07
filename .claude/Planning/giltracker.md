# Gil Tracker — component plan

Status: draft, 2026-08-05; reconciled against the shipped framework (`dev` @ 2792b9f,
PR #1) the same day. Scope: one component, `src/components/giltracker/`. **The
framework is already built and merged** — plan against the live contract in CLAUDE.md
and `src/lib/core.lua`, not the design doc
[xivhud-implementation.md](xivhud-implementation.md). Sibling precedent and the model
to copy: `src/components/parambar/` and [parameter-bar.md](parameter-bar.md).

## Goal

The FFXIV **Gil** HUD widget equivalent for FFXI: the current gil total with a gil
icon, bottom-right by default — a re-implementation of the Windower `giltracker`
addon as a framework component. Decisions (2026-08-05): component key
**`giltracker`**; **parity** with the reference addon (current gil only — no session
totals, no gil/hour, no per-source attribution); **reuse its `gil.png`** (BSD
3-clause, © 2017 sylandro — notice must ship with it).

## Reference facts (verified 2026-08-05 against Windower/Lua `live`)

What it renders: one 23×23 `gil.png` image + one right-justified italic text
(sans-serif 9, comma-grouped number), anchored bottom-right. Not draggable, no
commands, configured only via settings.xml.

- **Anchoring:** text `pos = {x = -285, y = -35}` with `flags.right`/`flags.bottom`.
  `flags.right` does *two* things (verified in `texts.lua`): `texts.pos` adds
  `ui_x_res` to `x`, **and** the text is set right-justified — so the number grows
  *leftward* from the anchor. The icon is placed at
  `(xRes + pos.x + 1, yRes + pos.y - icon_height/6)`, i.e. immediately right of the
  same anchor. Net layout: `[ number ][icon]`. (`flags.bottom` only offsets `y`; the
  `bottom_justified` call is commented out in the lib.)
- **Value read:** `windower.ffxi.get_items('gil')`, formatted by a `gsub` loop that
  inserts thousands separators.
- **Data flow: event-driven, never polled — and that is the load-bearing design
  choice.** `get_items()` forces a full item push (the wiki says so explicitly, and
  recommends `get_bag_info()` when only counts are wanted — but `get_bag_info()`
  carries no gil). So gil is re-read only when a packet says it may have changed.
  Two state flags drive it:
  - `inventory_loaded` — cleared on incoming `0x00A` (zone-in/login), set by
    `initialize()`.
  - `ready` — "something happened that could touch gil", set by `add item` /
    `remove item` for item id **65535**, and by any `0x0D2` with `Count > 0`
    (not just gil - narrowed in ours).
  - Chunk dispatch: `0x00A` → invalidate; `0x0D2` (Found Item) → maybe-ready;
    `0x01F` (Item Assign) and `0x020` (Item Updates) → update if
    `Item == 65535 and Count >= 0`; `0x01D` (Finish Inventory) → `refresh_gil()`:
    update + clear `ready` when `ready and inventory_loaded`, else `initialize()`.
- **Packet fields verified** against `libs/packets/fields.lua`: `0x01D`
  {`Flag` (1 = all bags finished), `Bag`, bag bits}; `0x01F` {`Count`, `Item`, `Bag`,
  `Index`, `Status`}; `0x020` {`Count`, `Bazaar`, `Item`, `Bag`, `Index`, `Status`,
  `ExtData`}; `0x0D2` {`Dropper`, `Count`, `Item`, `Dropper Index`, …}. `parse`
  returns raw numbers (the `fn=item`/`fn=gil` hooks are display formatters only) —
  hence the numeric `== 65535` comparison works.
- **Item events** `add item` / `remove item` are `(bag, index, id, count)` (Events
  wiki, verified).
- **Lifecycle:** `load` → initialize if `get_info().logged_in`; `login` → text
  `'Loading...'`; `logout` → invalidate + hide; `status change` 4 → hide, any other
  status → show; `keyboard` DIK 70 (Scroll Lock) → toggle hide. No `unload` handler,
  no zone-change handling beyond the `0x00A` cache invalidation.
- **Defects to fix, not port:**
  1. **No `unload` handler** — the text and image prims leak on `//lua reload`.
  2. `comma_value` leaks an implicit global `k` (second return of `string.gsub`).
  3. Every function is a global (`initialize`, `update_gil`, `show`, `hide`, …),
     polluting the shared addon environment.
  4. `toggle_display_if_cutscene` calls `show()` on *any* non-4 status change with
     no `inventory_loaded` / logged-in guard, so a stale or `'Loading...'` display
     can be un-hidden by unrelated status churn (~85% — structurally evident in
     source; exact trigger needs a live client).
  5. `p.Count >= 0` is a dead guard — `Count` is an unsigned int.
  6. ~~`0x01D` fires once per bag, so a full inventory load reads repeatedly.
     Gate on `Flag == 1`.~~ **Withdrawn 2026-08-05 — this was wrong twice
     over.** The reference's own `inventory_loaded` flag already collapses a
     multi-bag load, so there was no bug; and `Flag == 1` means *all* bags
     finished, which the server only sends on a zone in, so gating on it would
     leave a pending change unread until the player next zoned. Both flag values
     are acted on; `inventory_loaded` and `pending` do the deduplication.
     Narrow `0x0D2` to gil instead (see below) — that is where the wasted reads
     actually were.
  7. The icon's position is derived from the *text's* `pos` with magic `+1` and
     `height/6` constants, so it can't be adjusted independently; and
     `config.save(settings)` is called unconditionally at load.

## Deviations from the reference (decided 2026-08-05)

- **Position/scale/visibility belong to the framework.** Drop the fixed anchor and
  the `pos` settings: the widget is dragged in `//xh layout`, state lives in layout
  slots. Default slot position ≈ the reference anchor (bottom-right, computed from
  screen size in `defaults.lua`, as parambar does).
- **Origin is the top-left of a reserved box, not the text anchor.** The contract is
  explicit: *`get_bounds()` must return the same origin `set_pos` was given* — core
  clamps and layout mode's drag offsets both assume it. So a right-justified text
  anchored at the origin (the reference's arrangement, growing leftward into negative
  space) is not allowed. Instead:
  - the widget box is `reserved_width + gap + icon_size` wide and `icon_size` tall,
    with its top-left at the origin;
  - the number is **left-justified at the origin** inside that reserved width, so
    the icon never moves as digits change (decided 2026-08-05, superseding the
    right-justified anchor first drafted here — see below);
  - the icon sits at `origin.x + reserved_width + gap`, flush with the origin's top;
  - the reference's negative icon offset (`-size/6`) is inverted into a positive
    `text.y_offset` (+4) that nudges the smaller text down to centre against the
    23px icon — everything stays inside the box, nothing draws above the origin.
  **Why not right-justified** (decided 2026-08-05, after the framework merge):
  `texts.pos` adds `ui_x_res` to `x` when the right flag is set, so the lib cannot
  give right-justification without also making the coordinate screen-relative —
  `parambar.lua:92-97` routes around exactly this. Three options were weighed:
  left-justified (chosen), manual right-alignment from a glyph-width estimate, and
  `right_justified(true)` with `x - screen_width` to cancel the offset. The
  accepted cost of the chosen one: as the value shrinks, the gap between the
  number and the icon grows (at the default font, ~16px at eight digits, ~55px at
  one). Revisit by putting the icon *first* — `[icon][number]`, icon at the
  origin, number at `origin.x + icon_size + gap` — which is adjacent and
  jitter-free and satisfies the same constraints, if the floating gap looks wrong
  in a live client.
- **Auto-hide is framework-owned.** The `event` suppression reason already covers the
  status-4 hide; `zoning` and `logged_out` are an upgrade (the reference only
  invalidated its cache on `0x00A`). The component implements no hide logic.
- **Scroll Lock hide key dropped entirely** (decided 2026-08-05) — no component key
  handler, and no framework backlog item. `//xh show|hide giltracker` covers it.
- **No component commands.** Nothing here is worth a tuning verb (font/colors are
  config keys); the framework's `show`/`hide`/`reset` and layout mode suffice.
  `handle_command` is left unimplemented — it's optional in the contract.
- **Bug fixes 1–7.** Notably: `destroy()` disposes both prims; the state machine is a
  pure module with no globals; `0x0D2` arms a read only for gil, not for every
  party drop; `0x00A` is acted on without being parsed at all; the icon gets
  its own `gap`/`y_offset` config keys seeded from the reference's magic constants.
- **Scale** (contract requirement, new): multiplies icon size, font size, `gap`, and
  `y_offset`.
- **Bounds** (contract requirement, new): the reserved box above, sized from the gil
  cap (999,999,999 → 11 characters with separators) at the current font size × scale.
  Chosen over calling `windower.text.get_extents` so the hit-target doesn't jitter as
  digits change and doesn't collapse at `0` — and because the fixed box is what makes
  the origin contract satisfiable at all. `reserved_width ≈ 11 × font_size × ratio`
  as a tunable constant, `0.6`. **The true width is nearer `0.75`** — verified in
  `//xh layout` on 2026-08-05, where a capped value runs about two characters under
  the icon. `0.6` is kept anyway (decided 2026-08-05): reserving the true width
  parks the icon ~75px from a single-digit value, and that gap at every ordinary
  balance is worse than an overlap that cannot appear below 100,000,000 gil. The
  trade is the cost of left-justifying inside a fixed reserve — icon-first would
  remove both (see above).
- **The icon must set `fit(false)` and an explicit `size`.** The reference sets
  `texture.fit = true` *and* a 23×23 size; per CLAUDE.md `image:fit(true)` sizes the
  prim to its texture and defeats `size()`, so scale would silently do nothing. Also
  use `alpha`/`stroke_alpha` (0–255), never `transparency`/`stroke_transparency`
  (0–1) — the two are easy to confuse and the wrong one produces a negative alpha.
- **Value read:** use the documented `windower.ffxi.get_items().gil` rather than the
  reference's `get_items('gil')` — the wiki types the `bag` argument as an integer,
  so the string form is undocumented behavior (it evidently works, ~75%, by indexing
  the result table). Same cost either way, since either form pushes all items.
  Nil-guarded at the dep boundary (`get_player`-style rule from CLAUDE.md).
- **Parity kept:** comma grouping, italic sans-serif styling, stroke, optional
  background, `[ number ][icon]` layout, and the packet-driven refresh state machine
  (the whole point of the addon).

## Architecture

Mirrors `src/components/parambar/` exactly — same three files, same require form
(**slashes, not dots**: `require("components/giltracker/logic")`), same BSD header
(© 2026, Azureblood2).

```
src/components/giltracker/
  giltracker.lua      -- widget factory new(ctx): owns prims, implements the contract
  logic.lua           -- pure: refresh state machine, formatting, layout math
  defaults.lua        -- returns function(screen_width, screen_height) -> defaults
  assets/
    gil.png           -- 23×23, from the Windower giltracker addon
    LICENSE.txt       -- BSD 3-clause notice, © 2017 sylandro (ships in the package)
tests/components/
  giltracker_spec.lua
  giltracker_logic_spec.lua
```

- **`logic.lua`** (the testable core). Holds `inventory_loaded` / `ready` / the last
  displayed value. Inputs are the raw event facts, outputs are *intents* — it never
  reads gil itself:
  - `on_zone_in()`, `on_item_event(id)`, `on_treasure(count)`,
    `on_item_packet(item, count)`, `on_inventory_finish(flag)` →
    `'refresh'` | `'initialize'` | `nil`.
  - `format_gil(n)` → comma-grouped string (nil/negative guarded).
  - Layout helpers: icon/text offsets and reserved bounds under scale.
  - Preview sample (`123,456,789` — the max-width case, so layout mode shows the
    widest the widget ever gets; toggling preview restores the live value).
- **`giltracker.lua`**: builds the text + image prims via `ctx.new_text`/`ctx.new_image`,
  applies the intents (`ctx.get_gil()` on `'refresh'`/`'initialize'`), and implements
  the shipped contract: `name`, `defaults`, `attach(config, save)`, `detach()`,
  `set_pos`, `set_scale`, `set_preview`, `show`/`hide`, `get_bounds`, `update`,
  `destroy`. No `handle_command`.
  - **`update()` with no arguments is the per-frame tick and is a no-op here** —
    there is nothing to ease, and core calls it sixty times a second for every
    registered component. Only `update(event, ...)` does work.

### Framework integration (what GT1 must change outside the component)

`core.dispatch(event, ...)` already broadcasts any forwarded game event to every
component, so no framework change is needed for the *routing* — but `src/XIVHud.lua`
hardcodes which Windower events it registers (currently `hp/hpp/mp/mpp/tp change`).
GT1 adds:

1. `windower.register_event("incoming chunk", …)` → `core.dispatch("chunk", id, original)`.
   **The handler must return nothing** — `incoming chunk` treats a returned value as a
   modified/blocked packet, and `guard.wrap`'s error fallback returns `false` for the
   mouse and keyboard handlers; confirm the chunk path returns `nil` on both the happy
   and the guarded-error path before shipping.
2. `add item` / `remove item` → `core.dispatch("add item", bag, index, id, count)` and
   the `remove item` equivalent.
3. `ctx` for the component gains a gil reader (`get_gil`), alongside the existing
   `new_text`/`new_image`/`screen`/`get_player`/`asset`.
4. `check_assets()`'s hardcoded texture list gains
   `components/giltracker/assets/gil.png` — textures fail *silently*, so an install
   missing the icon would otherwise look like a working addon drawing nothing.

Broadcast cost is worth a note: `incoming chunk` fires for **every** packet, and
dispatch walks every component, so parambar's `update` is called once per packet too.
That is one table walk and one function call per packet — acceptable, and the
alternative (filtering to giltracker's five packet ids in the entry point) would put
component knowledge back in `XIVHud.lua`. Keep the filter inside `logic.lua` as a
single id lookup, and revisit only if a live client shows it costing frames (~85%
it does not).

## Settings (`defaults.lua` → `data/<Character>/giltracker.lua`)

`defaults.lua` returns `function(screen_width, screen_height) -> table`, exactly as
parambar's does, so the default slot can reproduce the reference's bottom-right
anchor on first run. snake_case keys; reference names in parentheses.

```lua
{
  font = "sans-serif", font_size = 9,                    -- (gilText.text.font/size)
  italic = true, bold = false,                           -- (gilText.flags.*)
  text_color  = { a = 255, r = 253, g = 252, b = 250 },  -- (gilText.text.*)
  text_stroke = { width = 2, a = 200, r = 50, g = 50, b = 50 },
  text_y_offset = 4,                                     -- centres the text on the icon
  bg = { visible = false, a = 100, r = 0, g = 0, b = 0 },-- (gilText.bg.*)
  icon = {
    visible = true,                                      -- (gilImage.visible)
    size    = 23,                                        -- (gilImage.size.*), square
    gap     = 1,                                         -- was the magic "+1"
    color   = { a = 255, r = 255, g = 255, b = 255 },    -- (gilImage.color.*)
  },
  slots = {
    default = {
      -- reference anchor: text right-edge at xRes - 285, top at yRes - 35.
      -- Origin is the box's top-left, so the reserved width comes off the x.
      pos = { x = max(0, screen_width - 285 - RESERVED_WIDTH),
              y = max(0, screen_height - 35) },
      scale = 1, visible = true,
    },
  },
}
```

Dropped from the reference: `hideKey` (no key handler), `gilText.pos` and
`gilText.flags.right/bottom` (framework layout slots), `gilText.text.fonts`
(fallback list — reinstate only if the single `font` key proves insufficient).

## Testing strategy

All against `logic.lua` with plain tables; prim fakes only for the widget layer:

- **State machine** (table-driven): zone-in invalidates; `add`/`remove item` for
  65535 readies, other ids no-op; treasure gil vs a party member's item, and
  `Count` 0 vs > 0; `0x01F`/`0x020` with `Item ≠ 65535` ignored, `== 65535`
  updates immediately; `0x01D` acted on at either `Flag` value; refresh while
  `ready and loaded` clears `ready`; refresh while not loaded reads; zone-in and
  logout invalidate, and logout drops the value so it cannot be shown to the
  next character.
- **Formatting**: `0`, `999`, `1000`, `999999`, `1234567`, `999999999` (the cap),
  plus `nil` and negative input → guarded, no crash (bug 2 regression is luacheck's
  job; the behavior test is the grouping itself).
- **Layout math**: icon/text offsets and reserved bounds at scale 1 and non-1;
  bounds width driven by the 11-char cap, not the current value.
- **Preview**: sample value in, live value restored on exit.
- **Widget level** (fake prim recorder from `tests/support/fakes.lua`): group move
  keeps the icon at `anchor + gap`; `destroy` disposes *both* prims (bug 1
  regression); intent → prim calls, including that `'refresh'` calls `ctx.get_gil`
  exactly once and a nil return leaves the last good value on screen.

In-client smoke (Windows/Windower): value updates on NPC sale, AH sale/purchase,
treasure-pool gil, and player trade; survives a zone change; hidden during an NPC
cutscene; drag/scale in `//xh layout` persists; `//lua reload xivhud` leaves no
prims.

## Milestones

The framework (M0–M3) is merged, so nothing here is blocked on it.

- **GT0 — pure logic**: `logic.lua` + `defaults.lua` + full spec, green locally.
- **GT1 — widget + asset + wiring**: `giltracker.lua`, `gil.png` + `LICENSE.txt`
  copied in, the four entry-point changes above, registered with `core.register`;
  in-client smoke.
- **GT2 — layout integration**: drag/scale/preview/bounds verified in `//xh layout`
  and persisted to the active slot — in particular that `get_bounds()` returns the
  origin `set_pos` was handed, since the reserved-box design exists to satisfy that.
- **Backlog** (2026-08-05, order TBD): session delta / gil-per-hour readout;
  gain/loss flash on change; icon-left layout variant; `gilText.text.fonts` fallback
  list if the single-font key bites.

## License & attribution

`gil.png` comes from the Windower `giltracker` addon, BSD 3-clause © 2017 sylandro —
no separate asset license exists, so the code license is our basis, as with parambar.
`assets/LICENSE.txt` reproduces the notice and is packaged with the addon. The
refresh state machine is a re-implementation of the same approach; the notice covers
it either way. Our source files keep the repo's own BSD header (**© 2026,
Azureblood2**) — `tests/sources_spec.lua` fails the build without it.

## References

- giltracker source: https://github.com/Windower/Lua/tree/live/addons/giltracker
  (facts above verified against `live`, 2026-08-05)
- **Live contract** (authoritative): [CLAUDE.md](../../CLAUDE.md) "Modular design &
  testing" + `src/lib/core.lua` (`dispatch`, `on_prerender`) and
  `src/components/parambar/` as the working example.
  [xivhud-implementation.md](xivhud-implementation.md) is the framework's *design*
  doc — historical once it shipped; prefer the source where they disagree.
- Parameter Bar plan: [parameter-bar.md](parameter-bar.md) — sibling component,
  asset-reuse and deviation precedent.
- Packet fields (`0x01D`/`0x01F`/`0x020`/`0x0D2`):
  https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua
- Events (`add item` / `remove item` signatures):
  https://github.com/Windower/Lua/wiki/Events
- FFXI functions (`get_items`, `get_bag_info`, `get_info`):
  https://github.com/Windower/Lua/wiki/FFXI-Functions
- texts lib (`flags.right` anchoring + justification):
  https://github.com/Windower/Lua/blob/dev/addons/libs/texts.lua
```
