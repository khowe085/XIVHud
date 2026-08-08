# Equip Viewer - component plan

Status: draft, 2026-08-08. Scope: one component, `src/components/equipviewer/`, plus a
small set of entry-point deps. The framework and four components are shipped - plan
against the live contract in CLAUDE.md and `src/lib/core.lua`. Sibling precedent and
the model to copy: `src/components/giltracker/` and [giltracker.md](giltracker.md)
(packet-driven, no polling, icon + text prims, asset redistribution).

Decisions (2026-08-08): component key **`equipviewer`**; icons cache under
**`data/icons/`**; keep **encumbrance Xs, ammo count text and the background panel**;
commands limited to the **two feature toggles**.

## Goal

The equipped-gear grid: a 4x4 arrangement of item icons for all sixteen equipment
slots, with an X over slots locked by encumbrance and the ammo count over the ammo
slot - a re-implementation of the Windower `equipviewer` addon (v3.3.1, (c) 2021
Tako/Rubenator) as a framework component, so it can be dragged and scaled in
`//hud layout` alongside the rest of the HUD.

## The part that is not easy

**No icons ship with the addon.** The reference reads the client's own
`ROM/*.DAT` files at runtime, decodes a 32x32 palette-indexed bitmap out of the
item record, and writes it to disk as a `.bmp`, once per item ever equipped.
Everything else here is ordinary component work; this is the risk, and it is the
one part that cannot be exercised in this container at all (no DAT files, no
client). The mitigation is the split in `icons.lua` below: the byte-level decode
is a pure function that a spec can drive with a synthetic record, so only the
*io* is unverifiable locally.

## Reference facts (verified 2026-08-08 against Windower/Lua `dev`)

Source read in full: `addons/equipviewer/equipviewer.lua` (743 lines),
`icon_extractor.lua` (266), `README.md`. Packet fields verified against
`addons/libs/packets/fields.lua`; `images.lua` read for the prim semantics below.

### What it draws

- One background image, `size * 4` square, translucent black, at the configured pos.
- Sixteen 32x32 item icons on a 4x4 grid. The grid order is **not** slot id order -
  each slot carries a `display_pos` and lands at
  `x = pos.x + (display_pos % 4) * size`, `y = pos.y + floor(display_pos / 4) * size`:

  | row | col 0 | col 1 | col 2 | col 3 |
  |-----|-------|-------|-------|-------|
  | 0   | main (0) | sub (1) | range (2) | ammo (3) |
  | 1   | head (4) | neck (9) | l.ear (11) | r.ear (12) |
  | 2   | body (5) | hands (6) | l.ring (13) | r.ring (14) |
  | 3   | back (15) | waist (10) | legs (7) | feet (8) |

  (slot id in parentheses; `display_pos` is the cell index reading left-to-right.)
- Sixteen `encumbrance.png` overlays, one per cell, shown per the 0x01B bitfield.
- One ammo-count text, shown only when the ammo count is > 1.

### Data flow

- **Equip/unequip:** incoming `0x050` = {`Inventory Index`, `Equipment Slot`,
  `Inventory Bag`} - gives the bag+index of the newly equipped item, not its id.
  The id comes from `windower.ffxi.get_items(bag, index).id`.
- **Item updates:** incoming `0x01E` {`Count`, `Bag`, `Index`, `Status`},
  `0x01F` {`Count`, `Item`, `Bag`, `Index`, `Status`}, `0x020` {`Count`, `Bazaar`,
  `Item`, `Bag`, `Index`, `Status`, `ExtData`}. Matched against the cached bag+index
  per slot; drive ammo count, and clear a slot when `Status ~= 5 and Count == 0`.
  Note `0x01E` carries **no `Item` field** - it can only clear or recount a slot
  already known by bag+index.
- **Encumbrance:** incoming `0x01B` (Job Info), field `Encumbrance Flags`, an
  unsigned int whose low sixteen bits are slot ids 0..15 (fields.lua comments the
  order: main, sub, range, ammo, head, body, hands, legs, feet, neck, waist,
  l.ear, r.ear, l.ring, r.ring, back - i.e. bit n == slot id n).
- **Full read:** `windower.ffxi.get_items('equipment')` returns `<slot_name>` (index)
  and `<slot_name>_bag` per slot. Empty slot: index `0`; empty/invalid item id: `0`
  or `65535`.
- **Job change:** outgoing `0x100` clears every slot.
- **Zone / cutscene:** incoming `0x00A` shows, `0x00B` hides; `status change` 4 hides.

### Icon extraction (`icon_extractor.lua`)

- Item id -> DAT file by range, eleven ranges (`118/106` general, `118/107` usable,
  `118/109` armor, `118/108` weapons, `301/115`, `286/73`, `217/21`, `288/80`,
  `288/67`, `118/110`, `174/48` gil). Only the general-items range carries an
  `offset` of `-1`.
- Record stride `0xC00` (3072) bytes; the icon lives at `+0x2BD` for `0x800` bytes:
  `0x400` of palette (256 x RGBA) then `0x400` of palette indices (32x32).
- Both the palette bytes and the index bytes are **bit-rotated**:
  `n = (i % 0x20) * 8 + floor(i / 0x20)`. Alpha is additionally doubled and clamped
  to 255. The decode builds two 256-entry lookup tables once, then two `gsub` passes.
- Output is a hand-built 122-byte BITMAPV4-style BMP header (32bpp, `BI_BITFIELDS`,
  32x32, sRGB) concatenated with the expanded pixel data - so the file is written
  with plain `io.open(path, 'wb')`, no image library involved.
- Game path is `windower.ffxi_path`, overridable by a `game_path` setting.
- DAT handles are cached open for the addon's lifetime and closed on `unload`.
- `item_by_id` calls `coroutine.yield()` between `f:write` and `f:close()`.

### Prim semantics confirmed (`libs/images.lua`)

- `images.path()` calls `windower.prim.set_texture` directly - **no `update()` needed**.
  The reference's `image:update()` calls after `path()` are unnecessary, and its
  `image:clear()` wipes the lib's key/value store, which images do not use for the
  texture - it does not blank the prim. **Hide the prim to blank a slot.**
- A texture path that does not exist fails silently (CLAUDE.md), so the file must
  exist *before* `path()` is called.

### Defects to fix, not port

1. **`get_equipped_item` calls `windower.ffxi.get_items('equipment')` per slot** -
   a full item push x16 on every setup. Read it once per refresh.
2. Every helper is a global (`show`, `hide`, `position`, `destroy`,
   `display_ammo_count`, `find_item_dat_map`, `open_dat`, `convert_item_icon_to_bmp`,
   `close_dats`, `bmp`, `filename`, `evdebug`, ...), polluting the shared addon
   environment. `bmp`, `filename` and `err` in the extractor are accidental globals.
2b. `display_ammo_count` is called from `update_equipment_slot` **above its own
   definition** - it resolves only because it is a global, which is the same defect
   viewed from the other side.
3. `setup_ui` -> `destroy()` -> rebuild happens on **every** command, including pure
   toggles; sixteen prims are torn down and recreated to change an alpha.
4. `display_ammo_count(count)` writes `equipment_data[3].count = count` even when
   `count` is nil, so a nil argument erases the cached count.
5. `error()` is used for user-facing "not enough arguments" messages, and the `log()`
   line after it is unreachable in some branches.
6. No guard on `windower.ffxi.get_items(bag, index)` returning nil (CLAUDE.md rule).
7. `transparency` command math: `math.floor((255-alpha)/255)*100` - the `*100` is
   outside the floor, so it always reports 0 or 100.
8. The extractor's `error(err)` in `open_dat` is followed by `return` with no value,
   so a missing DAT propagates as a nil handle into `:seek`.

## Deviations from the reference

- **Position, scale and visibility belong to the framework.** Drop `pos`, `size`
  as a positioning input, `left_justify`, and the `position`/`size`/`scale` commands.
  The default slot puts the grid where the reference's default put it (500, 500),
  clamped to the screen.
- **Auto-hide is framework-owned.** Drop `hide_on_zone`, `hide_on_cutscene` and the
  `0x00A`/`0x00B`/`status change` handling. The framework's `event`, `zoning` and
  `logged_out` suppressions already cover all of it, and cover it better.
- **Origin is the top-left of the 4x4 grid**, which is also the background panel and
  `get_bounds`. Every cell is at a non-negative offset from it, so the contract
  (`get_bounds()` returns the origin `set_pos` was given) holds without special care.
- **`icon_size` is a config key; the framework's uniform `scale` multiplies it.**
  The reference conflated the two (`scale` just wrote `size`). Effective cell size is
  `icon_size * scale`; box is `4 * icon_size * scale` square. Default 32 -> 128px.
- **Ammo count is left-justified**, positioned over the ammo cell. Same trap
  giltracker documented: `texts.pos` adds `ui_x_res` to `x` when the right flag is
  set, so right-justification cannot be had without making the coordinate
  screen-relative. The reference's right-justified default and its `justify` toggle
  both go.
- **Encumbrance bits are decoded with arithmetic, not the `bit` library.**
  `floor(flags / 2^slot) % 2 == 1`. LuaJIT's `bit` is not part of `std = "lua51"`
  and is not available to busted here; the arithmetic form is testable and the
  values are 16-bit. (~95% - the only risk is a flags value large enough to lose
  precision, and it is 32-bit at most.)
- **DAT handles are opened and closed per read**, not cached open for the session.
  A cache miss is rare (only an item never equipped before), and a per-read open
  removes both the unload-time leak and the question of holding a handle into the
  client's install directory. Revisit if a live client shows the open cost.
- **Icon extraction is queued, not inline.** The reference extracts inside the packet
  handler; a first login with sixteen uncached items would do sixteen DAT opens,
  decodes and file writes in one frame, on the packet path. Instead a cache miss
  pushes the item id onto a queue and the **per-frame tick drains at most one per
  frame**. Bounded, and empty in the steady state - unlike the render-loop trace
  CLAUDE.md warns about, which ran every frame forever. (~85%; if a live client
  shows a visible fill-in delay, raise the per-frame budget.)
- **No `coroutine.yield()` between write and close.** The reference yields inside
  what is effectively an event handler; ours writes and closes in one go from the
  tick.
- **Job change: no outgoing chunk handler.** The entry point registers none today,
  and adding one would dispatch *every* outgoing packet to *every* component to
  serve one id. `0x01B` (Job Info) arrives on a job change and is already being
  read for encumbrance - treat it as a full-refresh signal instead. (~80%: it is
  structurally certain that 0x01B follows a job change, less certain that the
  equipment table is already updated when it lands. If a live client shows stale
  icons after a job change, add the outgoing handler.)
- **Bug fixes 1-8**, and: the whole equipment table is read once per refresh; a
  toggle re-styles the existing prims instead of rebuilding them; nil guards at
  every dep boundary.
- **Parity kept:** the grid order, the background panel, the encumbrance overlay,
  the ammo count, the icon colour/alpha settings, and the extraction algorithm
  itself byte for byte.

## Architecture

```
src/components/equipviewer/
  equipviewer.lua     -- widget factory new(ctx): owns 34 prims, implements the contract
  logic.lua           -- pure: slot state machine, packet routing, layout math, commands
  icons.lua           -- pure: item id -> DAT path/offset, and DAT record -> BMP string
  defaults.lua        -- function(screen_width, screen_height) -> defaults
  assets/
    encumbrance.png   -- from the reference addon
    LICENSE.txt       -- BSD 3-clause, (c) 2021 Rubenator (ships in the package)
tests/components/
  equipviewer_spec.lua
  equipviewer_logic_spec.lua
  equipviewer_icons_spec.lua
```

- **`logic.lua`** (pure, the bulk of the tests). Holds the sixteen slots
  (`item_id`, `bag`, `index`, `count`), the encumbrance bitfield, and the icon
  request queue. Inputs are raw event facts; outputs are *intents* - it never reads
  items or touches disk:
  - `on_chunk(id, packet)` -> a list of intents: `refresh_all`, `read_slot(slot)`,
    `clear_slot(slot)`, `set_count(slot, n)`, `set_encumbrance(flags)`.
  - `wants_chunk(id)` - a five-id lookup, so the common case costs one table index.
  - `set_equipment(table)` / `set_item(slot, id, count)` - the results coming back.
  - `cell(slot, x, y, scale)` -> pixel position; `bounds(x, y, scale)`.
  - `encumbered(slot)`; `ammo_text()`; `parse_command(args)`; preview state.
- **`icons.lua`** (pure, and the reason the risky part is testable):
  - `dat_for(item_id)` -> `{path = '118/109', offset = ...}` or nil.
  - `record_offset(item_id, dat)` -> byte offset and length to read.
  - `to_bmp(record)` -> a 4218-byte BMP string, or nil on a short record.
  A spec builds a synthetic 0x800 record with a known palette and known indices and
  asserts the header bytes, the file length, and a handful of decoded pixels -
  including the bit rotation and the alpha doubling, which are exactly the parts a
  transcription error would break silently.
- **`equipviewer.lua`**: 1 background + 16 icon + 16 encumbrance images + 1 text =
  **34 prims**, all created once at construction so `destroy` can always dispose
  them. Applies intents, drains the icon queue on the tick, implements the contract.
  `handle_command` returns the toggle confirmations.

### Framework integration (what EV1 changes outside the component)

`core.dispatch` already broadcasts `chunk`, so routing needs nothing. `src/XIVHud.lua`
gains, in the `step("building the equipviewer component", ...)` block:

1. `get_equipment()` -> `windower.ffxi.get_items().equipment` (nil-guarded).
   The documented signature takes an integer bag id, so the reference's
   `get_items('equipment')` is the undocumented string form - giltracker set the
   precedent of preferring the documented table index.
2. `get_item(bag, index)` -> `windower.ffxi.get_items(bag, index)`, nil-guarded.
3. `file_exists(path)` -> `windower.file_exists` (documented; absolute path).
4. `read_dat(absolute_path, offset, length)` -> a byte string or nil.
   `io.open(path, 'rb')`, `seek`, `read`, `close`, all inside a `pcall` - it reads
   from outside the addon directory and a bad install must not throw into a handler.
5. `write_binary(relative_path, bytes)` -> ok - the existing `write_file` opens `"w"`
   (text mode), which on Windows would mangle every `\n` byte in a bitmap. This one
   opens `"wb"` and reuses `ensure_dir`. **Do not reuse `write_file`.**
6. `game_path()` -> `windower.ffxi_path`. Undocumented (the wiki documents
   `windower.pol_path`, "path to playonline and ffxi install directory"), but it is
   what the reference uses and what the whole extractor is built on; fall back to
   `windower.pol_path` when nil, and let a `game_path` config key override both.
7. `asset` (existing) composes the cache path: `asset("data/icons/" .. id .. ".bmp")`.
8. `check_assets()` gains `components/equipviewer/assets/encumbrance.png`.

Gated on `safe_mode or libraries_error` like giltracker - without the `packets`
library there is nothing useful to do with a chunk.

No `.gitignore` or packaging change: `*/data/` is already ignored and the workflow
already does `rm -rf "dist/${name}/data"`, so `data/icons/` is covered by both.
No `.luacheckrc` change either - `windower.ffxi_path` is an index on an
already-whitelisted global, and `bit` is deliberately not used.

## Settings (`defaults.lua` -> `data/<Character>/equipviewer.lua`)

```lua
{
  icon_size = 32,                                        -- (settings.size)
  icon  = { a = 230, r = 255, g = 255, b = 255 },        -- (settings.icon)
  bg    = { visible = true, a = 72, r = 0, g = 0, b = 0 },-- (settings.bg)
  show_encumbrance = true,                               -- (settings.show_encumbrance)
  encumbrance_alpha_factor = 0.8,                        -- was icon.alpha * 0.8 inline
  show_ammo_count = true,                                -- (settings.show_ammo_count)
  ammo_text = {
    size_factor = 0.27, y_factor = 0.58,                 -- both from the reference
    bold = true, italic = true,
    a = 230, r = 255, g = 255, b = 255,
    stroke = { width = 1, a = 127, r = 0, g = 0, b = 0 },
  },
  game_path = nil,                                       -- (settings.game_path) override
  slots = { default = { pos = { x = 500, y = 500 }, scale = 1, visible = true } },
}
```

Dropped: `pos`, `size`-as-position-input, `hide_on_zone`, `hide_on_cutscene`,
`left_justify`.

## Commands

```
//hud equipviewer                        -- current state of both toggles
//hud equipviewer encumbrance on|off
//hud equipviewer ammocount on|off
```

Parsed in `logic.lua`, applied by re-styling the existing prims (not a rebuild).
No `alpha`, `background`, `position`, `size`, `scale`, `justify`, `game_path`,
`testenc` or `debug` verbs - the framework covers the layout ones and the rest are
config keys.

## Testing strategy

Pure modules with plain tables; prim fakes from `tests/support/fakes.lua` for the
widget layer.

- **Icons** (`icons.lua`): id -> DAT mapping at every range boundary, including the
  `-1` offset on general items and an out-of-range id -> nil; record offset maths;
  `to_bmp` against a synthetic record - header length and magic, total file size,
  bit-rotation of a palette entry, alpha doubling and its clamp at 255, index
  expansion, and a truncated record -> nil.
- **Slot state machine** (`logic.lua`): `0x050` sets bag+index and requests a read;
  `0x01F`/`0x020` matched by bag+index -> update, unmatched -> ignored;
  `Status ~= 5 and Count == 0` -> clear; `0x01E` recounts a known slot and cannot
  set an item; ammo count drives the text only for slot 3 and only above 1;
  item id `0` and `65535` both mean empty; `0x01B` sets encumbrance and requests a
  full refresh; an unwanted id costs one lookup and returns nothing.
- **Encumbrance decode**: `0x0000`, `0xFFFF`, and single bits at slots 0, 7, 8, 15.
- **Layout maths**: every cell's position at scale 1 and non-1 against the table
  above; bounds is the 4x`icon_size` square at the origin `set_pos` was given;
  ammo text position tracks the ammo cell.
- **Commands**: both toggles on/off, case-insensitivity, bare verb reports state,
  unknown input answers a hint.
- **Widget level**: 34 prims created and all 34 destroyed; a cache hit calls
  `path()` without touching `read_dat`; a cache miss queues and drains one per tick;
  a failed extraction leaves the slot hidden and does not retry every frame; a nil
  from `get_item` leaves the previous icon alone.

**In-client smoke** (Windows/Windower, the only place the extractor can be proven):
first login with an empty `data/icons/` fills all sixteen cells; equip and unequip
each slot type; fire ranged ammo and watch the count fall and the slot clear at 0;
become encumbered and see the Xs; change jobs; zone; NPC cutscene hides the widget;
drag and scale in `//hud layout` persist; `//lua reload xivhud` leaves no prims.

## Milestones

- **EV0 - pure**: `icons.lua`, `logic.lua`, `defaults.lua` + full specs, green
  locally. The whole decode is provable here; nothing is blocked.
- **EV1 - widget + wiring**: `equipviewer.lua`, `encumbrance.png` + `LICENSE.txt`,
  the eight entry-point changes, `core.register`. First in-client smoke - and the
  first time the extractor touches a real DAT, so expect this to be where the
  surprises are.
- **EV2 - layout integration**: drag/scale/preview/bounds in `//hud layout`,
  persisted to the active slot.
- **Backlog**: per-slot tooltips or item names; a "clear icon cache" verb;
  raising the per-frame extraction budget if the fill-in reads as slow.

## License & attribution

`encumbrance.png` and the extraction algorithm come from the Windower `equipviewer`
addon, BSD 3-clause (c) 2021 Rubenator (base extraction code credited to Trv);
`_addon.author` also lists Tako. No separate asset licence exists, so the code
licence is the basis, as with parambar, giltracker and the party list.
`assets/LICENSE.txt` reproduces the notice and ships in the package. Our own source
files carry the repo's BSD header ((c) 2026, Azureblood2) - `tests/sources_spec.lua`
fails the build without it.

## References

- equipviewer source (verified 2026-08-08 against `dev`):
  https://github.com/Windower/Lua/tree/dev/addons/equipviewer
- Packet fields (`0x01B`/`0x01E`/`0x01F`/`0x020`/`0x050`):
  https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua
- images lib (`path` -> `set_texture`, `clear` semantics):
  https://github.com/Windower/Lua/blob/dev/addons/libs/images.lua
- Functions (`file_exists`, `dir_exists`, `create_dir`, `pol_path`):
  https://github.com/Windower/Lua/wiki/Functions
- **Live contract** (authoritative): [CLAUDE.md](../../CLAUDE.md) + `src/lib/core.lua`,
  with `src/components/giltracker/` as the working example.
- Gil Tracker plan: [giltracker.md](giltracker.md) - packet-driven precedent, the
  right-justification trap, asset redistribution.
