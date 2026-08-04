# XIVHud implementation plan — framework

Status: draft, 2026-08-04. Scope: the widget **framework** only. Individual widgets
(party list, target bar, …) get their own planning docs later and are non-goals here.

## Goal

An internal framework for composable HUD widgets in the style of FFXIV's HUD system:
a widget contract + registry, a layout system with an FFXIV-style **drag layout mode**
(`//xh layout`), settings persistence, and event plumbing — all structured per the
repo's DI conventions so everything except the entry point is unit-testable.

Non-goals (decided 2026-08-04):

- Widget implementations — separate planning docs per widget. This plan ships only a
  throwaway placeholder widget to prove the loop end-to-end.
- Public plugin API — the widget contract is internal; third-party extensibility can
  be revisited once the contract stabilizes.
- Copying FFXIV assets — style-alike only, original/derived art.

## Platform facts (verified 2026-08-04 against Windower/Lua `dev`)

- **`texts` library implements dragging natively**: `default_settings.flags.draggable = true`
  (drag is ON by default — must be explicitly disabled), internal `'mouse'` handler moves
  the object on type 0 and fires `'drag'`/`'right_drag'` object events
  (`texts.register_event(t, key, fn)`). Position via `texts.pos/pos_x/pos_y`; hit-testing
  via `texts.hover(t, x, y)` (uses `windower.text.get_location()` + `get_extents()`).
- **Global `'mouse'` event**: `(type, x, y, delta, blocked)`; types: 0 move, 1/2 left
  down/up, 4/5 right down/up, 10 wheel (wiki + XIVParty production use). Returning
  `true` blocks the input from reaching the game; bail out early when `blocked` is set.
- **Global `'keyboard'` event** `(key, down, ...)` exposes modifier state (DIK codes,
  29 = CTRL) — XIVParty uses it for snap-while-dragging.
- **`windower.register_event` returns an id** for `windower.unregister_event(id)` —
  register mouse/keyboard handlers on layout-mode enter, unregister on exit, so normal
  play has zero input-handling overhead.
- Screen bounds for clamping: `windower.get_windower_settings().ui_x_res/ui_y_res`.

## Key design decision: central drag, not native drag

A widget is a *group* of prims (texts + images). Native per-object drag would move one
prim and leave the rest behind. Therefore:

- The framework sets `draggable = false` on **every** prim it creates (overriding the
  texts default).
- Layout mode registers one global `'mouse'` handler: hit-test against widget bounding
  boxes (topmost wins), drag moves the whole widget as a unit, handled events return
  `true` to block the game. Outside layout mode the handler is inert.
- This makes drag logic a pure, testable state machine fed `(type, x, y)` tuples.
- Precedent: XIVParty's setup mode works exactly this way — central `'mouse'` handler,
  grab-offset on left-down, move on type 0, `return true` to swallow handled input.

## Reference implementation: XIVParty setup mode

`//xp setup` (Tylas11/XIVParty, `uiPartyList.lua`) is the model for our layout mode.
Patterns adopted:

- **Invisible overlay image per widget**, sized to its bounds: the drag hit-surface,
  and (alpha raised) the FFXIV-style highlight box in layout mode.
- **Drag**: left-down over the overlay stores the grab offset (`x - overlay_pos.x`);
  each type-0 move applies `pos(x - grab.x, y - grab.y)`.
- **CTRL modifier** while dragging (via `'keyboard'`) — adopted *inverted*: XIVParty
  snaps while CTRL is held; we snap by default and CTRL frees (decided 2026-08-04).
- **Mouse wheel over a widget = scale** (`scale + delta / 100`, floor 0.25).
- **Save on every drag-release / scale change**, not on mode exit — crash-safe.
- **Sample data**: setup swaps in a dummy model so empty UI renders fully while
  positioning. Our widget contract needs the same (a layout-preview mode).
- **Reason-tagged visibility**: `view:visible(bool, reason)` with independent reasons
  (`visCutscene`, `visZoning`, `visSolo`) — generalized here into the framework
  suppression set (see Auto-hide below).

Note: official XIVBar (live and dev branches, and docs.windower.net) has **no**
setup/drag mode — positioning is settings.xml offsets only, and no GitHub fork adds
one. The remembered `//xb setup` likely belongs to another addon or a private fork;
XIVParty is the strongest in-community precedent for the UX. XIVBar remains a good
reference for bar rendering (eased width animation), its themes system, and
cutscene auto-hide (`status change` id 4).

## Architecture

```
src/
  XIVHud.lua            -- entry point: builds deps, wires events/commands (thin)
  lib/                  -- framework core (not a component)
    registry.lua        -- component registration + lifecycle (init/destroy/enumerate)
    widget.lua          -- the widget contract (doc + shared helpers)
    layout.lua          -- pure layout state: pos/visible per widget, snap math, clamp
    layout_mode.lua     -- pure drag state machine (enter/exit, hit test, drag, save)
    visibility.lua      -- pure suppression-set resolver (cutscene/zoning/logout x enabled)
    commands.lua        -- pure //xh subcommand parser -> action tables
    settings.lua        -- per-component config service: data/<Character>/<component> handles
  components/
    <component>/        -- ALL of a component's code, isolated per component
tests/
  *_spec.lua            -- one spec per lib module
  components/           -- specs mirroring src/components/ (busted recurses ROOT)
  support/fakes.lua     -- extend: fake prim recorder, scripted mouse streams
```

**Code isolation (decided 2026-08-04), parallel to config isolation:** each
component's code lives entirely in `src/components/<component>/` — its entry module
plus any private helpers. A component may require `lib/` (the framework) but never a
sibling component; cross-component needs go through the framework. Enforced by
convention/review (luacheck can't express it). The component name is the shared key
across code dir, config namespace, registry, and future command namespacing.
Components are wired explicitly (entry point requires and registers each) — no
directory scanning. Component entry file: `components/<name>/<name>.lua` (decided
2026-08-04; resolves with existing require paths in both busted and Windower, and
mirrors Windower's own addon-folder rule).

### Widget contract (draft — refine in first widget doc)

Factory style per CLAUDE.md: `new(ctx) -> widget` where `ctx` bundles injected deps
(prim constructors, data getters) plus the widget's own config handle. A widget exposes:

| Member | Purpose |
| --- | --- |
| `name` | stable key used in settings + commands |
| `defaults` | defaults for the widget's own config file |
| `show()` / `hide()` | visibility (layout mode forces show) |
| `set_pos(x, y)` | move all owned prims as a group |
| `set_scale(s)` | apply scale factor to owned prims (fonts, sizes, offsets) |
| `set_preview(on)` | render sample data for layout mode (FFXIV-style full preview) |
| `get_bounds() -> x, y, w, h` | bounding box for layout-mode hit testing |
| `update(...)` | data refresh (event-driven and/or prerender-throttled) |
| `handle_command(args)` | *optional*: receives `//xh <name> ...` passthrough args |
| `destroy()` | dispose prims (unload/reload safety) |

### Entry point & data flow

`XIVHud.lua` is the only file touching Windower globals. It builds `deps`
(`get_player`, `get_mob_by_index`, `texts_new`, `add_to_chat`, `config`, screen size, …),
instantiates the core, and forwards events: `'addon command'` → `commands` parser →
actions; `'mouse'` → `layout_mode`; `'prerender'` → throttled widget updates;
`'load'/'unload'/'login'/'logout'` → lifecycle; `'status change'`/`'zone change'` →
the visibility suppression set. Widget data in FFXI is
mostly *polled* (`get_player()` etc. on a prerender throttle) with packet/event pushes
added later per-widget.

### Layout mode (`//xh layout`)

FFXIV HUD-Layout equivalent, per the XIVParty patterns above. On enter: force-show
**all** widgets (including disabled ones) in preview mode with overlay highlights,
register mouse+keyboard handlers. Interactions (topmost hit wins; handled events
return `true`):

- **Left-drag** moves a widget; **grid snap is on by default** (`snap` px in core
  config, default 10) — hold CTRL for free-form movement (decided 2026-08-04,
  inverting the XIVParty convention); positions clamped to screen.
- **Wheel** over a widget scales it (floor 0.25).
- **Right-click** (right-down over a widget; right-up swallowed too) toggles the
  widget enabled/disabled (decided 2026-08-04). The overlay changes visibly by state
  — e.g. highlight + name label when enabled, dimmed/darker + "hidden" marker when
  disabled. Disabled widgets remain visible and draggable in layout mode so they can
  be positioned and re-enabled.

Persist through the widget's own config handle on every drag-release, scale change,
and enable-toggle. On exit (`//xh layout` again): unregister handlers, restore live
data, show enabled widgets only.

### Auto-hide (decided 2026-08-04)

**Framework-owned, applies to every visible component** — components never implement
their own hide logic. A pure resolver (`lib/visibility`) computes
`rendered = enabled(active slot) AND suppression set empty`, with suppression reasons:

- **`event`** — player status 4 ("Event"): NPC conversations that lock the player,
  and cutscenes. This is the signal XIVParty (`hideCutscene`) and XIVBar both use;
  plain dialog boxes don't set it, matching "certain NPCs". Trigger: `'status change'`.
- **`zoning`** — hide on `'zone change'`; re-show **delayed ~3s** after zone-in
  (XIVParty does this to avoid stale-data flicker).
- **`logged_out`** — no character → nothing renders (also gates config, see Settings).

Suppression wins over layout mode too (XIVParty precedent: cutscene-hide overrides
setup mode). The framework applies show/hide to all components on suppression
transitions; a core-config toggle (`hideCutscene`, default on — named after
XIVParty's equivalent) can disable the event reason for users who want the HUD
during dialogue. Component-specific policies (e.g.
XIVParty's hide-while-solo) stay per-component features, layered on top.

### Commands (`//xh`, decided 2026-08-04)

Aliases: `_addon.command = "xh"` plus `xivhud` via `_addon.commands` (both free).

```
//xh                       -- help (safe, discoverable; layout stays explicit)
//xh help
//xh layout | setup        -- toggle layout mode ("setup" = community-convention alias)
//xh list                  -- components with enabled state, pos, scale
//xh show|hide <component> -- explicit pair (idempotent, macro-safe; no bare toggle verb)
//xh reset <component|all> -- restore config defaults
//xh slot <name>           -- switch layout slot (unknown name -> error + slot list)
//xh slot create <name>    -- new slot, seeded from the active one
//xh slot list             -- slots with the active one marked
//xh slot delete <name>    -- refuse for "default" and for the active slot
//xh copy <character> confirm -- copy another character's config dir (post-M3)
//xh <component> [...]     -- passthrough to the component's optional handle_command
```

- **Reserved verbs** (`help`, `layout`, `setup`, `list`, `show`, `hide`, `reset`,
  `slot`, `copy`) are validated at registration — a component cannot take a reserved
  name. Each component owns its command namespace from day one, matching code/config
  isolation.
- **Parser** (`lib/commands`) is pure: verb and component name match
  case-insensitively; remaining args pass through raw (character names keep case).
  Unknown input → one-line hint plus `//xh help` pointer, never silence (Windower
  fails silently enough on its own).
- Chat feedback uses one consistent prefix/color everywhere.

### Settings

**Per-component isolation (decided 2026-08-04):** every component owns its own
configuration and must never touch another component's. Storage namespace:
`data/{Character}/{component}` relative to the addon root (runtime-generated; `data/`
is already gitignored and stripped from the package, so the scheme is packaging-safe).

- **Config service** (`lib/settings`): given a component name + defaults, returns a
  handle bound to `data/<Character>/<component>.lua`. Isolation is by construction —
  a component only ever receives its own handle. A component needing more than one
  file may claim the directory `data/<Character>/<component>/` as its namespace
  instead ("free to do what it needs" within it).
- **Format: `.lua`, not XML (decided 2026-08-04)** — Windower's config-lib is XML-only
  on write (`settings_xml` is its sole serializer; its JSON support is read-only) and
  the bundled `json` lib is a parser with no encoder, so JSON would require
  hand-writing an encoder anyway (both verified against live libs sources). The
  config service owns persistence itself: files read via `loadfile` in an **empty
  sandbox env** (config files are code — never give them access to globals), written
  by a small pure serializer in `lib/` (stable key order for clean diffs), `files`
  lib for I/O. Defaults merge is our own pure function (user values win, new default
  keys added). config-lib is not used.
- **Character scoping**: the character name isn't known until login (`get_player()` is
  nil before then) — component configs initialize on `'login'` / `'load'`-while-logged-in
  (XIVBar's `get_info().logged_in` gate) and rebuild on character switch; widgets stay
  hidden until then.
- **Widget layout state** (pos/scale/visible) lives in each widget's own config,
  nested under **named layout slots** (decided 2026-08-04):
  `slots = { default = { pos = {x, y}, scale = 1, visible = true }, <user-name> = … }`.
  The first slot is named `default`; it always exists and cannot be deleted. Slot
  names are user-provided, matched case-insensitively, stored lowercase. The active
  slot name lives in core's config; **all layout writes (drag-release, wheel-scale,
  right-click toggle) persist into the active slot** through the widget's own handle —
  no explicit save step. Switching slots re-applies that slot's values; a missing
  entry for a component falls back to its defaults. The nesting ships at M2 (zero
  installed configs → no migration) with only `default` exercised until the slot
  commands land.
- Framework-level options (snap px, active slot, …) live in the core's own namespace
  (`data/<Character>/core.lua`).
- New-key defaults merge into existing files; each component versions its own schema
  as needed.

## Testing strategy

Pure modules tested with busted + fakes; no Windower client needed:

- `layout`: snap rounding, clamping, defaults merge.
- `layout_mode`: scripted mouse/keyboard streams → expected grabs/moves/releases/no-ops
  (misses, overlapping widgets, drag past screen edge, enter/exit mid-drag,
  CTRL-snap engage/release mid-drag, wheel scaling with floor, right-click toggle:
  hit toggles + persists / miss no-ops / ignored mid-drag / disabled stays draggable).
- `commands`: parse table for every subcommand + bad input.
- `registry`: double-register, destroy-all order, unknown lookups.
- `visibility`: every suppression-reason combination × enabled/disabled → rendered
  state; zone re-show delay; suppression overriding layout mode.
- `settings`: namespace path resolution (character/component), handle isolation,
  defaults merge, character-switch rebuild, serializer round-trip (nested tables,
  strings needing escaping, stable key order), sandboxed load (no global access,
  malformed file → defaults + warning, not a crash).

Fake prim recorder in `tests/support/fakes.lua`: a `texts_new`-shaped stub recording
`pos/show/hide/text` calls so widget group-move logic is assertable.

In-client smoke checklist (manual, Windows/Windower — per milestone): load clean,
`//xh layout` drag + snap, positions survive `//lua reload xivhud`, unload leaves no prims.

## Milestones

- **M0 — core skeleton**: `commands`, `registry`, `settings` (config service:
  sandboxed `.lua` load, serializer, defaults merge) + specs; `//xh help` working
  in-client. BSD headers on new source files — holder: **Azureblood2** (decided
  2026-08-04).
- **M1 — render loop**: prim deps wrappers, login-gated init (no character → no
  config → hidden), placeholder widget as the first `src/components/<name>/` proving
  the layout + persisting its own config, prerender throttle, clean unload/reload,
  and the visibility resolver wired (`event`/`zoning`/`logged_out` suppression
  verified in-client against an NPC conversation). Verify busted picks up
  `tests/components/` (~85% it recurses as-is).
- **M2 — layout mode**: `layout` + `layout_mode` + persistence; drag/CTRL-snap/
  wheel-scale/right-click-toggle/clamp verified in client, incl. the per-state
  overlay visuals.
- **M3 — polish**: per-widget `//xh show|hide|reset`, the `hideCutscene` core toggle,
  update CLAUDE.md architecture section —
  including the per-component settings convention, which supersedes the template's
  single-`settings.xml` bullet — and remove the template `status` module + spec
  (CLAUDE.md says it stays only until real modules exist).
- **Post-M3 backlog** (decided 2026-08-04, order TBD):
  - `//xh slot` command set — switch / `create` (seeded from active) / `list` /
    `delete` (refused for `default` and the active slot). Schema is already
    slot-shaped from M2, so this is command + apply logic only.
  - `//xh copy <character> confirm` — copies `data/<Other>/*` over the current
    character's dir, then rebuilds configs (hook exists for login). Destructive →
    `confirm` required; unknown source → list available character dirs. Directory
    enumeration probably `windower.get_dir` (~70% — verify then).
- **Then**: first real widget — new planning doc.

Each milestone lands green (`busted` + `luacheck` + `stylua --check`) before the next.

## Open questions

None as of 2026-08-04 — all decisions are recorded inline with their dates (slots:
named, `default` first, schema at M2, commands post-M3; snap: on by default, CTRL
frees; cross-character: `//xh copy` post-M3).

## References

- Windower events: https://github.com/Windower/Lua/wiki/Events (mouse payload verified)
- XIVParty setup mode (drag/snap/scale reference): https://github.com/Tylas11/XIVParty
  — `uiPartyList.lua:handleWindowerMouse`. License (verified 2026-08-04): code is BSD
  3-clause via per-file headers (© 2024 Tylas; no repo LICENSE file) — patterns and
  even literal code are reusable with notice. 
- XIVBar (bar rendering, themes, cutscene hide; no setup mode):
  https://github.com/Windower/Lua/tree/live/addons/xivbar
- texts source (drag internals): https://github.com/Windower/Lua/blob/dev/addons/libs/texts.lua
- Libraries overview: https://github.com/Windower/Lua/wiki/Libraries
- Local Lua guide: docs/lua-guide-for-programmers.md
