# Parameter Bar — component plan

Status: draft, 2026-08-04. First real component (the framework plan's "first real
widget"). Scope: one component, `src/components/parambar/`, on the framework from
[xivhud-implementation.md](xivhud-implementation.md). Depends on framework M1
(render loop) for display and M2 (layout mode) for positioning.

## Goal

The FFXIV **Parameter Bar** equivalent for FFXI: HP / MP / TP bars with numeric
values, bottom-center by default — a re-implementation of the XIVBar addon as a
framework component. Decisions (2026-08-04): component key **`parambar`**; **core
parity** with XIVBar (its theme *system* is deferred); **reuse XIVBar's assets**
(BSD 3-clause, © 2017 SirEdeonX — notice must ship with them).

## XIVBar reference facts (verified 2026-08-04 against Windower/Lua `live`)

What it renders: one background strip image + three fill images (HP, MP, TP,
left→right) + three right-justified numeric texts, anchored bottom-center
(`y = ui_y_res - 60`), not draggable, no commands, configured only via settings.xml.

- **Fill width:** `floor((pp / 100) * bar_width)`; HP/MP use `hpp`/`mpp`;
  TP uses `tpp = math.min(current_tp / 10, 100)` (TP range 0–3000, bar full at 1000).
- **Easing** (every prerender frame while a dirty flag is set; exponential
  ease-out, converges via `ceil`):
  ```lua
  x = old + math.ceil((new - old) * 0.1)   -- growing,  clamp min(x, bar_width)
  x = old - math.ceil((old - new) * 0.1)   -- shrinking, clamp max(x, 0)
  ```
  Fill image hidden when converged at width 0. Animation is `image:size(x, 8)` —
  stretching a 142×8 fill texture; background drawn first, fills over it, texts on top.
- **Full-TP highlight:** at `tp >= 1000` the TP text turns `FullTpColor`
  (default 80,180,250) and, with `DimTpBar`, the TP bar goes alpha 255 (else 180).
- **No low-HP/MP color logic exists** — the full-TP highlight is XIVBar's *only*
  conditional coloring (confirmed by reading every file).
- **Data flow:** event-driven, not polled — `hp/hpp/mp/mpp/tp change` events write
  values + set a per-bar dirty flag; `prerender` eases until converged. `get_player()`
  is called only at initialize (fields `vitals.hp/hpp/mp/mpp/tp`), gated on
  `get_info().logged_in`; `login`/`logout` show/hide; `status change` hides on
  status id 4 (event/cutscene). No zone-change handling, no unload handler.
- **Assets per theme** (folders `themes/ffxi|ffxiv|ffxiv-legacy`, same dimensions):
  `bar_bg.png` 472×24, `bar_compact.png` 421×24, `hp_fg.png`/`mp_fg.png`/`tp_fg.png`
  142×8. Positioning bakes frame padding into magic offsets (fills at x+15/25/35,
  texts at x+65/80/90, both stepped by `bar_width + spacing`; fills at y+2).
- **Known bugs** (we fix, not port): ① dirty-flag typo (`hp_update` vs `update_hp`)
  makes the HP bar re-ease every frame forever; ② the `DimTpBar` else-branch runs for
  *all* bars, dimming HP/MP to alpha 180 as a side effect — intended behavior is
  TP-bar-only dimming; ③ compact `total_width = 422` vs a 421px image; ④ bar and
  number can disagree on death (empty bar, max-HP number — user-observed): the bar
  renders from the percent stream (`hpp change`) and the text from the absolute
  stream (`hp change`) into two fields that are never reconciled, so if one stream
  skips or reports stale/max on death they diverge (mechanism ~90% — structurally
  evident in source; exact upstream trigger needs a live client).

## Deviations from XIVBar (decided 2026-08-04)

- **Position/scale/visibility belong to the framework.** Drop `OffsetX`/`OffsetY`
  and the fixed anchor: the widget is dragged in `//hud layout`, state lives in
  layout slots. Default slot position ≈ XIVBar's anchor (bottom-center: computed
  from screen size at first init). Scale is new (contract requirement): multiplies
  image sizes, font size, and the padding offsets.
- **Auto-hide is framework-owned** — the `event` suppression reason already covers
  XIVBar's status-4 hide; `zoning` and `logged_out` are an upgrade over XIVBar
  (which ignored zoning). The component implements no hide logic.
- **Theme system deferred.** Bundle exactly one asset set — XIVBar's `ffxiv` theme
  (its default, and our addon's whole aesthetic) including `bar_compact.png`. The
  bar-metric settings stay configurable; multi-theme folder resolution goes to the
  backlog. The `ffxiv` theme's hardcoded stroke override (alpha 150, color 80,70,30)
  becomes our plain stroke *default* — user-overridable, not special-cased.
- **Bug fixes** ①–④ above. `dim_tp_bar` dims only the TP bar. For ④, vitals are
  reconciled instead of streamed blind: `hpp == 0` forces the displayed HP number
  to 0 (dead is dead, whatever the absolute stream said), likewise MP, and vitals
  re-seed from `get_player().vitals` on status transitions — fixes the symptom
  regardless of the upstream cause.
- **Conditional low-HP/MP coloring (added 2026-08-04 — beyond XIVBar, which has
  none).** Number **text only** (XIVParty's shipped default; bar-fill tinting →
  backlog): XIVParty's bands and colors — yellow `<75%` (243,243,124), orange
  `<50%` (248,186,128), red `<25%` (252,129,130), strict `<` on the percent value.
  MP mirrors the same thresholds and colors (decided 2026-08-04; no community/
  FFXIV/vanilla precedent exists for MP — mirroring HP chosen for consistency).
  Thresholds are hardcoded constants (XIVParty's approach); the colors are
  settings keys. Full-TP coloring is unchanged and unaffected.
- **Full parity kept:** compact mode, `dim_tp_bar`, full-TP text color, easing feel
  (0.1 + `ceil`), fill/text layout math, event-driven updates with prerender easing.

## Architecture

```
src/components/parambar/
  parambar.lua        -- widget factory new(ctx): owns prims, implements the contract
  logic.lua           -- pure per-frame state machine (no prims, no Windower)
  assets/
    bar_bg.png  bar_compact.png  hp_fg.png  mp_fg.png  tp_fg.png   -- from XIVBar ffxiv theme
    LICENSE.txt       -- BSD 3-clause notice, © 2017 SirEdeonX (ships in the package)
tests/components/
  parambar_spec.lua
```

- **`logic.lua`** (the testable core): holds vitals + eased widths + dirty flags.
  Inputs: `set_vitals(kind, value)` (from change events), `tick()` → a render plan
  per bar (`width`, `hidden`, `text`, `color_state`, `dirty` cleared on
  convergence), plus pure helpers for `tpp`, layout offsets under scale, and
  bounds. Preview mode swaps in sample vitals (e.g. HP 75%, MP 50%, TP 1500 —
  exercises the sub-full-TP dim state; toggling preview must restore live values).
- **`parambar.lua`**: builds prims via `ctx` constructors, applies each `tick()`
  render plan, implements `set_pos` (group move re-deriving the per-prim offsets),
  `set_scale`, `get_bounds` (background extents × scale), `set_preview`,
  `show/hide`, `handle_command` (metrics command set — see Commands),
  `destroy` (XIVBar had no unload path; we must dispose prims).
- **Framework touchpoint:** the entry point must forward `hp/hpp/mp/mpp/tp change`
  events into the widget's `update` — the first use of the framework plan's
  "packet/event pushes added later per-widget" clause. Initial vitals seed from
  `get_player().vitals` at login-gated init (nil-guarded).

## Settings (defaults, in `data/<Character>/parambar.lua`)

Our config service + snake_case keys; XIVBar names in parentheses for the mapping.

```lua
{
  compact = false,                    -- (Theme.Compact) use bar_compact.png + compact metrics
  bar  = { width = 132, spacing = 18, offset = 0 },          -- (Theme.Bar.*)
  compact_bar = { width = 116, spacing = 16, offset = 0 },   -- (Theme.Bar.Compact.*)
  dim_tp_bar = true,                  -- (Theme.DimTpBar) TP bar alpha 180 until TP >= 1000
  font = 'sans-serif', font_size = 14, text_offset = 0,      -- (Texts.*)
  text_color   = { a = 255, r = 253, g = 252, b = 250 },
  text_stroke  = { width = 2, a = 150, r = 80, g = 70, b = 30 },  -- ffxiv-theme values as defaults
  full_tp_color = { r = 80, g = 180, b = 250 },
  -- low-vitals text colors (thresholds <75/<50/<25% are hardcoded, XIVParty values)
  low_hp_colors = { yellow = { r = 243, g = 243, b = 124 },
                    orange = { r = 248, g = 186, b = 128 },
                    red    = { r = 252, g = 129, b = 130 } },
  low_mp_colors = { yellow = { r = 243, g = 243, b = 124 },   -- mirrors HP by default
                    orange = { r = 248, g = 186, b = 128 },
                    red    = { r = 252, g = 129, b = 130 } },
  slots = { default = { pos = ..., scale = 1, visible = true } },  -- framework-owned shape
}
```

## Commands (`//hud parambar`, added 2026-08-04)

Via the framework's `handle_command(args)` passthrough; parsing is a pure function
in `logic.lua`. Framework conventions apply: case-insensitive verbs, unknown input
→ one-line hint (never silence), consistent chat prefix.

```
//hud parambar                    -- show current metrics + compact state
//hud parambar width <px>         -- fill width at 100%
//hud parambar spacing <px>       -- gap between bars
//hud parambar offset <px>        -- fill x offset vs background
//hud parambar compact on|off     -- toggle compact mode
```

- `width`/`spacing`/`offset` write to the **active** metric set (`bar` or
  `compact_bar`, per the compact toggle) — what you see is what you tuned.
- Validation: integers only; `width` ≥ 8, `spacing`/`offset` ≥ 0; out-of-range or
  non-numeric → error line with the accepted range, no write.
- Every accepted change persists immediately through the component's config handle
  and triggers a re-layout of the prims (same path a settings load uses).

## Testing strategy

All against `logic.lua` with plain tables — no prim fakes needed until group-move:

- Easing: growth and shrink steps (0.1 + `ceil`), convergence from 0→full and
  full→0, clamps at both ends, dirty flag clears exactly on convergence (bug ①
  regression), hidden-at-zero.
- TP: `tpp` formula incl. cap at 3000; full-TP threshold at exactly 999/1000/1001 →
  text color state + TP alpha; `dim_tp_bar` affects only TP (bug ② regression).
- Low-vitals bands: boundary cases 24/25, 49/50, 74/75% → red/orange/yellow/normal
  for both HP and MP (strict `<`); band state carried in the render plan's
  `color_state`; TP never banded.
- Death reconciliation (bug ④ regression): `hpp = 0` with a stale/max absolute HP →
  displayed 0 (and red band); same for MP; status-transition re-seed overwrites
  both streams.
- Layout math: fill/text x-offsets per bar for normal + compact metrics, scale
  multiplication, bounds; compact uses the 421px width (bug ③).
- Preview: sample data in, live vitals restored on exit.
- Command parser: every verb happy-path, active-set routing (normal vs compact),
  integer/range rejection (7/8 width boundary, negatives, non-numeric), no-arg
  status output, unknown verb → hint.
- Widget level (fake prim recorder from `tests/support/fakes.lua`): group move,
  destroy disposes every prim, render plan → prim calls.

In-client smoke (Windows/Windower): bars track damage/rest ticks with the XIVBar
feel, TP highlight at 1000, drag/scale in `//hud layout` persists, cutscene hide,
`//lua reload xivhud` clean.

## Milestones

- **PB0 — pure logic**: `logic.lua` + full spec, green locally. No framework
  dependency — can start before framework M1 lands.
- **PB1 — widget + assets**: `parambar.lua`, assets copied in with LICENSE.txt,
  entry-point event wiring, registered in the framework; in-client smoke. Needs
  framework M1; replaces the M1 placeholder widget as the registry's occupant.
- **PB2 — layout integration + commands**: drag/scale/preview verified in
  `//hud layout` (needs framework M2); the `//hud parambar` metrics command set
  wired through `handle_command`; compact + dim toggles exercised in-client.
- **Backlog** (2026-08-04, order TBD): theme folder system (multi-theme resolution,
  custom user themes); optional bar-fill tinting at the low-vitals bands
  (XIVParty-style opt-in — needs in-client eyeballing of tint over the textures);
  hide/blank MP bar for MP-less jobs; further `//hud parambar` subcommands beyond
  the metrics set (e.g. font/color tweaking) if ever wanted.

## License & attribution

The five PNGs (and the easing/layout constants, if treated as ported code) come
from XIVBar, BSD 3-clause © 2017 SirEdeonX — no separate asset license exists, so
the code license is our basis. `assets/LICENSE.txt` reproduces the notice and is
packaged with the addon. Our source files keep the repo's own BSD headers.

## References

- XIVBar source: https://github.com/Windower/Lua/tree/live/addons/xivbar
  (facts above verified against `live`, 2026-08-04; re-fetch from there — the
  session scratchpad mirror is ephemeral)
- Framework plan: [xivhud-implementation.md](xivhud-implementation.md) — widget
  contract, visibility resolver, settings service, layout slots.
- XIVParty preview/setup precedent, and the low-HP/TP coloring reference
  (`uiStatusBar.lua` bands, `layout.lua` color defaults; verified 2026-08-04):
  https://github.com/Tylas11/XIVParty
