# Hotbar, and the action bar engine under both bars - plan

Status: BUILT 2026-09-06 on `work/claude/hotbar` (worktree
`.claude/worktrees/hotbar`, cut from `origin/dev` at 02ca3b4), every phase
green, awaiting the review gate and the PR. One PR at the end (Kevin,
2026-09-05); the phases were built in order with the crossbar green after
each. Deviations from what is written below are listed under "As built".

Scope: `src/components/crossbar/` (shrinks), new `src/lib/actionbar/`, new
`src/lib/warp.lua` / `roulette.lua` / `skillchain.lua` / `stealth.lua`, new
`src/components/hotbar/`, and the framework - `lib/commands.lua`,
`lib/core.lua`, `src/XIVHud.lua` - for the new top-level verbs and the shared
action service. Precedents: `lib/player` (a service built in the entry point,
ticked by core, handed to components through ctx), `lib/buffs` and `//hud
buffs` in #44 (a framework verb over an engine several components consume),
`partylist.lua` / `statusbar.lua` (inner factory per anchor under an outer
widget).

## Goal

A `hotbar` component (alias `hb`): the FFXIV hotbar, ten slots in a row, one
row per set - eight anchors. The first row follows the ACTIVE set, the other
seven are locked to sets 2-8, so row 1 duplicates one of them whenever the
active set is not 1 - deliberately: row 1 is the one placed where it is easiest
to reach.

It is the crossbar with a different face, and the two must not drift: sets,
cycling, the layer stack, the binder, edit mode, the authoring CLI, the
per-slot draw discipline and action execution move into `lib/actionbar/` and
both bars consume it. The four player-facing features that were only ever
crossbar-hosted by accident - warp, mount roulette, skillchains, sneak and
invisible - become libs of their own, run by ONE framework-level action
service, and are invoked as `//hud warp`, not `//hud crossbar warp`.

## Reference

The crossbar itself, in this repository, as it stands at 02ca3b4. Nothing is
ported from xivhotbar or xivcrossbar that is not already here. The map of what
moves, read 2026-09-05:

- The feature modules are already pure and standalone. `warp`, `roulette`,
  `skillchain`, `stealth`, `travel`, `retry`, `wsgate`, `enchanted`,
  `enchanteditem` require nothing from `lib/` and only three edges between
  them (`warp -> enchanted`, `enchanteditem -> enchanted`, `stealth ->
  counters`). Their 23 specs stand alone. Moving them is a path change.
- **The work is the glue in `crossbar.lua`**, 4078 lines, of which roughly
  600 are execution: `run_item_plan` / `abort_pending` / `tick_pending`
  (1756-2082, the equip-wait-use scheduler with its GearSwap holds and spoken
  countdown), `execute` / `delay_travel` / `fire_at` (2107-2348), and the
  travel, retry and skillchain steps inside `tick()` (3144-3271). That glue is
  covered only by `crossbar_spec.lua` (389 cases), through the widget.
- `bindings.lua` is hardwired to 8 sets x 2 sides x 8 slots and the `1L1`
  grammar (`SIDES`, `SET_COUNT`, `SLOT_COUNT`, `parse_address` at 48-182).
  Cycle and shared flags live in the component CONFIG (`set_flags`), not the
  store; the store is `<MAIN>.lua` + `SHARED.lua`.
- `render.lua` is two things in one file: geometry-free per-slot logic
  (`slot_label`, `text_offsets`, `cost`, `slot_alpha`, `feedback_fade`,
  `sweep` / `clear_sweep`, `chain_tick`, `icon_candidates`, and `slot_rects` /
  `slot_at` given rects) and the cross itself (`SLOT_GRID`, `BAR_OFFSETS`,
  `metrics`, `slot_pos`, `panel_pos`, `footprint_of`, `bounds`, `visible`, the
  set label and sword placements, the six anchor names).
- Fifteen ctx members are crossbar-only in `XIVHud.lua` (927-1030): `say`,
  `chat_open`, `zone`, `suppressed`, `component_visible`, `layout_active`,
  `send_ipc`, `get_spell_recasts`, `get_ability_recasts`, `get_key_items`,
  `get_spells`, `get_abilities`, `set_equip`, `decode_extdata`, `random`.
- `//hud buffs` (#44) is the template for a framework verb: `RESERVED` in
  `lib/commands.lua:39-49`, a parse arm, a `run_*` in core (775-787), two help
  lines (core.lua:92-93). `lib/registry` already refuses a component name or
  alias that collides with a reserved word.
- No lib persists config today. `core.lua` (`data/<Character>/core.lua`,
  outside every slot) holds `snap`, `slot`, `hideCutscene`; `//hud reset`
  walks the registry only and never touches it; `//hud copy` carries it.

## Decisions taken before writing anything (Kevin, 2026-09-05 and -06)

1. **One shared action service**, built in the entry point like `lib/player`,
   ticked by core, handed to both bars as `ctx.actions`, and the thing
   `//hud warp` talks to. Not a headless component. The reason is an
   invariant, not taste: "only one wait of any kind is in flight" and the
   GearSwap hold are process-wide, and two bars each owning a scheduler could
   both issue `gs disable` and race the same ring.
2. **Top-level verbs**: `//hud warp [all]`, `//hud mr`, `//hud sneak`,
   `//hud invisible`, `//hud draw`. `//hud crossbar warp|mr|sneak|invisible|
   draw` are gone outright, no pointer - they fall to the crossbar's ordinary
   unknown-verb hint. Weapon state is the PLAYER's, so it lives in the service
   and both bars read it; `draw` from the console or from a slot on either bar
   flips the one state.
3. **Service config lives in `core.lua`** - `retry`, `wsgate`, `delay` join
   `snap` and `hideCutscene` - edited by `//hud retry [on|off]`, `//hud
   wsgate [on|off] | range <yalms> | pivot <yalms>` and `//hud delay
   <seconds>`. They were never meant to vary by slot (Kevin, 2026-09-06),
   and the alternative was a settings handle for something that is not a
   component. Costs accepted: they no longer follow `//hud slot`, and no
   `//hud reset` verb touches them. A stored crossbar `retry` / `wsgate` /
   `delay` block is dead weight the settings merge preserves; **nothing
   migrates**, the partylist and targetbar precedent.
4. **Directory shape**: everything shared goes in `lib/actionbar/` (the first
   directory under `lib/`); `lib/warp.lua`, `lib/roulette.lua`,
   `lib/skillchain.lua`, `lib/stealth.lua` are flat beside it. `travel`,
   `retry`, `wsgate`, `enchanted`, `enchanteditem`, `counters` are actionbar's.
5. **The two bars know nothing about each other.** A crossbar set and a hotbar
   set are different things (16 slots against 10), each bar has its own
   per-job files and its own `SHARED.lua` in its own directory, and "shared"
   keeps its meaning: shared across JOBS, never across bars.
6. **Row 1 follows the active set; rows 2-8 are locked to sets 2-8.** So the
   hotbar keeps `set <n>`, `cycle` and the drawn/sheathed cycle flags - they
   move row 1 - and the job-load landing applies to it exactly as to the
   crossbar.
7. **Hotbar address grammar is `<set>:<slot>`** - `3:7`, `3:10` - with the
   layer prefixes in front as on the crossbar: `sub:3:7`, `wpn:3:7`,
   `ctx:haste:3:7`. Digits with a colon cannot be misread in the game's font
   the way `1l1` could, and `3-7` reads as a range.
8. **The authoring CLI is common** to both bars in full: `set`, `cycle`,
   `cycle <set> <mode>`, `share`, `bind` / `unbind` / `alias` / `icon` /
   `swap`, `list`, `copy <JOB>`, `context list`, `edit`, `help`, the status
   line. Only `wxhb` and `view` stay crossbar-only, there being no WXHB or
   Expanded Hold view on a hotbar to point anywhere.
9. **Shipped defaults**: row 1 visible, rows 2-8 `visible = false` on their
   anchors (the statusbar pattern), stacked down from one origin.
10. **`warp all`'s IPC string changes** from `xivhud crossbar warp` to `xivhud
    warp`. An updated and a not-yet-updated alt stop hearing each other;
    acceptable, there has been no public release.
11. **The hotbar takes nothing from the crossbar's `input.lua`**, which stays
    the crossbar's. Its own keys are decision 13; the binder opens through
    `//hud hotbar edit` and a left-click fires, as on the crossbar.
12. **Each row has a shape** (Kevin, 2026-09-06): 10x1, 5x2, 2x5 or 1x10,
    per anchor. The statusbar's scheme verbatim: `bars.<anchor>.rows` in the
    config, `//hud hotbar [<bar>] rows <1|2|5|10>`, a columns-by-rows table
    (`{ [1] = 10, [2] = 5, [5] = 2, [10] = 1 }`) that refuses anything else,
    and the answer `bar3 now draws 2 rows (5x2)`. Shipped `rows = 1` on all
    eight.
13. **Hotbar keys** (Kevin, 2026-09-06). The bare number row `1234567890`
    fires slots 1-10 of `bar1` - the ACTIVE set, by decision 6. Modifiers
    pick the row: CTRL -> `bar2`, ALT -> `bar3`, SHIFT -> `bar4`, CTRL+SHIFT
    -> `bar5`, ALT+SHIFT -> `bar6`, CTRL+ALT+SHIFT -> `bar7`. `bar8` has no
    keys and is mouse-only. **The game's macro palette fires too on every
    CTRL or ALT chord**: `return true` swallows a bare key and does not stop
    FFXI acting on a CTRL/ALT chord (verified in-client, the fact two crossbar
    input designs died on), so a user of rows 2, 3 and 5-7 must keep the
    matching in-game macros inert. Kevin's call, made knowing that. Bare
    number keys and SHIFT chords are swallowed, both edges.
14. **The skillchain indicator becomes a component of its own** (Kevin,
    2026-09-06), so the two bars do not each carry one. Both bars keep their
    per-slot chain borders; the bar that shows the window is one
    single-anchor widget reading the service's engine. The crossbar loses its
    `skillchain_indicator` anchor and its `config.skillchain` block
    (`indicator`, `opacity`, `waiting_color`, `open_color` - every key in it
    is the indicator's; the per-slot `hide.skillchain_icon` stays). Breaking,
    and **nothing migrates**: a stored crossbar `layout.lua` with that anchor
    in it carries dead weight, and the indicator comes up at its own shipped
    default.

## Interpretations flagged open (mine, not Kevin's)

Picked as the smallest option each time; say so and I change it.

- **Anchor names `bar1`..`bar8`**, not `set1`..`set8`: row 1 is not set 1, so
  a set name on it would lie. `bar1` is also what the statusbar calls its
  rows.
- **The hotbar's store keys a single side, `"row"`**: `sets[3].row[7]`. The
  engine keeps its `(set, side, slot)` shape so the crossbar's stored files
  are untouched, and the hotbar's grammar simply never yields another side.
  The alternative - an abstract slot key - would change the crossbar's file
  shape, which is the most laborious thing a user has typed into this addon.
- **Module names**: `lib/actionbar/service.lua` (the execution service, after
  "player service"), `lib/actionbar/bar.lua` (the widget-independent state of
  one bar) and `lib/actionbar/slot.lua` (one slot's nine prims and their
  change-gated draw). `commands.lua` keeps its name inside `lib/actionbar/`;
  it is a different require path from `lib/commands` and renaming it would
  turn a move into a rewrite in the diff.
- **`//hud delay`** as the verb for the travel delay, which today is a config
  key with no verb at all.
- **Hotbar prims are built per anchor on first show**, not all 720 in the
  factory the way the crossbar builds its 365. Eight rows at 10 slots x 9
  prims is double the crossbar's resting inventory for a widget that ships
  with seven rows off. The crossbar keeps its own construction; only a live
  client can say whether either matters.
- **A set number before slot 1**, in the crossbar's set-label gold and size:
  left of it on the two wide shapes (10x1, 5x2), above it on the two tall
  ones (2x5, 1x10), which is where XIV puts a hotbar's number in each
  orientation. On row 1 it is the only place the active set shows on the
  hotbar.
- **Slots run row-major** in every shape: 5x2 is 1-5 across the top and 6-10
  across the bottom, 2x5 is 1-2, 3-4, ... down, 1x10 is 1 at the top. That
  is XIV's own numbering of a reshaped hotbar, and it means `3:7` names the
  same binding whatever shape bar 3 is drawn in.
- The hotbar's `hide` / cosmetic config takes the crossbar's block verbatim
  (minus `always_show_wxhb`, `views`, `input`), through a shared
  `lib/actionbar/defaults.lua` so the two cannot drift.
- **The key table is fixed**, not config: ten DIK codes and six modifier
  combinations in `components/hotbar/input.lua`. The crossbar's keys are
  config (`config.input`) because its punctuation keys were chosen to dodge
  the game's; the hotbar's ARE the game's row by design, so there is nothing
  to choose. Making them config is a later verb if wanted.
- **A modifier set matches exactly.** CTRL+ALT with no SHIFT is assigned to
  nothing, so it neither fires nor blocks and reaches the game whole.
- **Keys fire a row whether or not its anchor is shown.** XIV's own rule: a
  hidden hotbar's binds still work. Only the WIDGET's state gates them -
  hidden by the user (`//hud hide hotbar`), suppressed, layout mode, edit mode
  or an open chat line, and every key falls through to the game unblocked. No
  key of the hotbar's is worth protecting during a cutscene the way the
  crossbar's `;` is, so suppression is plain inertness here, not the
  crossbar's swallow-but-do-nothing.
- **Arbitration with the crossbar is registration order** (below), with the
  crossbar registered first. It is the smallest change that gives the two a
  rule; a priority member on the widget contract would be the next step if a
  third keyboard consumer ever appears.
- **The indicator component is named `skillchain`**, code in
  `components/skillchain/`, beside `lib/skillchain.lua` the engine - the same
  word for the thing and its engine, as `buffs` is for `lib/buffs` and `//hud
  buffs`. Its alias is **`sc`** (Kevin, 2026-09-06), which is speedcheck's
  today - `lib/registry` refuses a duplicate alias as a hard error at load,
  so **speedcheck takes the alias `spd` in the same PR** (Kevin, 2026-09-06).
  `component_aliases_spec` and CLAUDE.md's alias list change with it. The indicator takes no commands of its own; on/off is the
  framework's `//hud show|hide skillchain`, which replaces the crossbar's
  `config.skillchain.indicator` flag.

## Design

### `lib/actionbar/` - what moves and what changes

Moved unchanged but for the require path: `bindings`, `catalog`, `binder`,
`commands`, `actions`, `counters`, `openers`, `contexts`, `kebab`, `weapon`,
`enchanted`, `enchanteditem`, `retry`, `wsgate`, `travel`. Their specs move to
`tests/actionbar_<module>_spec.lua` (or `tests/actionbar/`; whichever
`.busted` needs least - check its `pattern` first). Licence headers travel;
`render.lua`'s upstream BSD notice (lines 29-60) must survive the split.

Then the changes, in the order the phases make them:

**`bindings.lua` takes a `geometry`.** `{ slot_count, sides, parse, format }`:
the crossbar's is today's `SIDES` / `SLOT_COUNT = 8` / `parse_address` /
`"1L1"`; the hotbar's is `slot_count = 10`, one side `"row"`, `3:7`. Every
`SET_COUNT` / `SLOT_COUNT` / `SIDES` reference and the address parser go
through it. Weapon STATE leaves: `set_weapon_state` / `weapon_state` /
`on_status` become `on_weapon_state(state)`, called by `bar.lua` when the
service's state changes, and the rotation and landing logic stay exactly as
they are. `set_job`'s reset to sheathed goes with it - the service owns that.

**`render.lua` splits.** The geometry-free functions become
`lib/actionbar/render.lua`; `slot_rects` / `slot_at` go with them, taking
rects rather than deriving them. The cross stays in
`components/crossbar/render.lua` and the row goes in
`components/hotbar/render.lua`, each answering `metrics`, `slot_pos`,
`panel_pos`, `footprint_of`, `bounds` and the label placement for its own
anchors.

**`slot.lua`** owns what `paint_slot` + `tick_slot` + the nine-prim slot set
+ the `written` / `sweep_key` / `flash` caches do today (crossbar.lua
979-1053, 1055-1087, 1360-1443, 1579-1702, 2084-2105, 2756-2911): `new(deps)
-> slot`, `slot.place(x, y)`, `slot.paint(record, meta, source_mark)`,
`slot.tick(facts)`, `slot.flash()`, `slot.show()` / `hide()` /
`destroy()`, `slot.rect()`. Facts are what `tick_slot` receives now (player,
vitals, recasts, chain step, counters). The prims' creation order is the
crossbar spec's z-order contract and is kept.

**`bar.lua`** is the widget-independent state of one bar: its `bindings`
(over the caller's geometry and store), job scoping (`try_scope`,
`rescope_want`, `apply_buffs` / `sync_buffs`), the weapon layer
(`refresh_weapon`), item counts (`recount_items`, `bound_item_ids`,
`temporary_seen`), the binder session (`toggle_edit` / `close_edit` /
`set_changed`, `editing()`), the authoring CLI (`commands` + the verbs the
widget answers itself: `set`, bare `cycle`, bare `open`, `edit`), and
`fire(set, side, slot)` - which resolves the record, asks the gate, and hands
the record to the service. A bar takes `{ geometry, store, get_config, save,
actions = service, catalog deps, binder deps, verb_roster }`. `verb_roster`
is how the crossbar keeps `wxhb` / `view` and the hotbar does not.

**`service.lua`** is the glue at crossbar.lua 1756-2348 plus the travel /
retry / skillchain / roulette steps of `tick()`, with the four feature libs,
`travel`, `retry`, `wsgate`, `actions` (the plan resolver) and `enchanted`'s
scheduler inside it. Public surface:

```
service.fire(record, opts)          -- a bar's press: gate, resolve, travel or execute, arm retry
service.builtin(name, arg)          -- `//hud warp|mr|sneak|invisible|draw`, and `warp all`
service.weapon_state() / set_weapon_state(state) / on_status(status)
service.skillchain                  -- the engine, for per-slot chain borders and the indicator
service.roulette                    -- owned mounts / blocked / cooldown, for the binder and dim
service.retry, service.wsgate, service.travel  -- for the three config verbs' state lines
service.tick(facts)                 -- once per frame, from core: config_mode, suppressed, chat_open
service.on_chunk(id, data, parsed)  -- 0x028 / 0x029 / 0x063 / zone-out / the roulette ids
service.on_status(status) / on_zone() / on_job_change() / on_ipc(message) / on_logout()
service.end_trip(reason)            -- layout mode, edit mode, re-attach
```

`retry.sent` today is keyed to a slot address and re-checks it through
`bindings.resolve`; a shared service cannot reach a bar's bindings, so the
bar passes a `still_bound()` closure in `opts` and the retry facts call it.
That is the one behavioural seam in the extraction; everything else is a move.

### Framework

- `lib/commands.lua`: `RESERVED` gains `warp`, `mr`, `sneak`, `invisible`,
  `draw`, `retry`, `wsgate`, `delay`; a parse arm per verb (the config three
  carry their words through). None collides with a shipped alias (`cb pb gt
  ev tb pl sc eb sb inv`) and `hb` is free.
- `lib/core.lua`: `deps.actions`; `run_action` / `run_service_config` arms;
  `CORE_DEFAULTS` gains `retry`, `wsgate`, `delay` seeded from the three
  modules' own `defaults()` (defaults.lua does this today at 128-137);
  `on_prerender` ticks the service after visibility resolves, so it can hand
  it `suppressed` and `layout_active`; `on_logout` calls `on_logout`; the
  help text gains the eight verbs.
- `src/XIVHud.lua`: builds the service from the fifteen crossbar-only members
  plus `send_command`, `get_items`, `get_equipment`, `parse_packet`,
  `resources`, `now`, `time`, and hands it to core and to both bars' ctx;
  forwards to it the chunk dispatch (the ids above), `status change`, `zone
  change`, `job change`, `ipc message`, `logout`. `math.randomseed` moves with
  roulette. Registers `hotbar` after `crossbar`.
- `//hud list`, `show|hide`, `reset`, layout mode: nothing changes; the hotbar
  is an ordinary eight-anchor widget to all of them.
- **`core.on_keyboard` accumulates the block** (core.lua:706-714). Today every
  component receives the INBOUND `blocked` unchanged, so the crossbar
  swallowing `1` during a hold state would not stop the hotbar firing slot 1
  off the same event - and the crossbar's `slot_keys` are DIK 2-9, exactly
  the row the hotbar wants bare. The walk becomes `blocked = component
  .on_keyboard(key, down, flags, blocked) == true or blocked`, so a later
  component sees a key an earlier one took as already blocked, and the hotbar
  refuses to fire on a blocked key exactly as it does on one a prior addon
  took. Delivery is unchanged - every component still hears every event, the
  pinned 2026-08-16 rule - only the flag carries more. The entry point
  registers `crossbar` before `hotbar`, and `entry_point_spec` pins the
  order, since the arbitration is that order and nothing else.

### `components/hotbar/`

`hotbar.lua` (the widget: prims by anchor, `on_mouse`, the contract routed by
anchor as `partylist.lua` routes it), `render.lua` (the grid: ten slots at
`SLOT = 40` and the crossbar's `slot_spacing`, laid out row-major in the
anchor's shape - `COLUMNS_BY_ROWS[rows]` columns - with the set-number label
before slot 1; `metrics(rows)` / `slot_pos(rows, slot)` / `bounds(rows)`,
so a reshape is a re-`layout` of the same prims and nothing is rebuilt),
`defaults.lua` (eight anchors stacked at the 10x1 row pitch from one origin,
`bar1` shown, `bars.<anchor>.rows = 1`, `set_flags` for eight sets, the shared
cosmetic block, `skillchain` colours, `hide`, `game_path`, `binder_pos`).
Row N's set: `bar1` -> `bindings.active_set()`, `barN` -> N. Store:
`hotbar/<MAIN>.lua`, `hotbar/SHARED.lua`.

`input.lua` is the hotbar's own pure key machine, `new(deps) -> machine`,
`on_key(dik, down, flags, blocked) -> intent, block`, `focus_lost()`. It
tracks CTRL (DIK 0x1D / 0x9D), ALT (0x38 / 0xB8) and SHIFT (0x2A / 0x36) from
their own down/up edges - the crossbar's and layout mode's technique, with the
same caveat that a modifier released while the client has no focus is stuck
until `lose focus` resets it, which the widget forwards as `focus_lost()` the
way the crossbar does at crossbar.lua:3720. A number-row down (DIK 0x02-0x0B,
`0` being slot 10) with the modifier set matching one of the six rows yields
`{ fire = { bar, slot } }`; the bare row and SHIFT chords answer `block =
true` on the down AND the matching up, so the game never sees half a key;
CTRL and ALT chords answer `block = true` too, knowing it does nothing to the
macro palette (decision 13) - blocking what can be blocked is still right. An
unassigned set, a key that arrived `blocked`, or any guard - `chat_open`,
`suppressed`, `layout_mode`, `edit_mode`, `disabled` - yields no intent and
no block. The widget turns `fire` into `bar.fire(set_of(bar), "row", slot)`,
where `set_of("bar1")` is the active set and `set_of("barN")` is N, and
flashes the slot's prim if that row is drawn.

### `components/skillchain/`

The crossbar's `draw_indicator` (crossbar.lua:2913-2970), its two prims
(`indicator.bg`, `indicator.fill`, the `assets/own/` white square tinted),
its `indicator_written` change-gate, the `SC_WAITING_COLOR` / `SC_OPEN_COLOR`
/ `SC_OPACITY` constants and the `config.skillchain` block, moved whole into
`skillchain.lua` as a single-anchor widget. Per frame it asks
`ctx.actions.skillchain.window()` for `delay, window` and draws
`indicator_plan(delay, window)`; in preview it draws `indicator_plan(0, 7)`,
the full open bar, so layout mode has the real footprint. It receives no
packets and reads no client: the engine is the service's, fed by the entry
point. `defaults.lua` seeds it where the crossbar seeds
`skillchain_indicator` today (centred, above the main bar) with the same
`opacity` and colours. `get_bounds` is the open bar's 604 x 14 at the origin
given. Without `ctx.actions` (the service failed to load) it draws nothing,
the way the crossbar's cast-dependent features sit out without resources.

Commands: `//hud hotbar` (job, active set, then one line per row: on/off and
its shape), `//hud hotbar <bar>` (that row alone), `//hud hotbar [<bar>] rows
<1|2|5|10>` (`bar1` when the bar word is absent, as on the statusbar), then
the common roster - which takes NO bar word, since a set is a set whatever
row draws it, and a bar word in front of `bind` or `set` is refused rather
than dropped. A reshape re-lays the anchor's prims in place from the same
origin, saves, and repaints - the statusbar's `answer(lines, changed)` path
exactly. Core is NOT told: there is no re-clamp hook, and the statusbar does
not have one either, so a row reshaped near the screen edge can hang off it
until it is next dragged or a placement is next applied, and `//hud list`
reads the new footprint the next time it asks. The same limitation the
statusbar ships with, accepted rather than grown a framework hook for.

## Phases (strict TDD, one PR)

### H1 - Move the modules

`git mv` the fifteen actionbar modules and the four feature libs with their
specs; fix every require path; `tests/sources_spec.lua` and `luacheck` stay
green. No behaviour change, no edit inside a module beyond its own requires.
Crossbar green.

### H2 - The action service

Extract `service.lua` from crossbar.lua as described; weapon state moves into
it; the crossbar consumes `ctx.actions` and drops its own scheduler, travel,
retry, roulette, warp, stealth, skillchain and wsgate instances. The entry
point builds it; core ticks it; `retry` / `wsgate` / `delay` move to
`CORE_DEFAULTS` and `//hud crossbar retry|wsgate` are removed from
`commands.lua`. The `execution`, `auto-warp`, `travel delay`, `cast retry`,
`skillchain` and `the weaponskill gate` describe blocks of `crossbar_spec.lua`
move to `tests/actionbar_service_spec.lua`, rewritten against the service's
surface; what stays in the widget spec is that a press reaches `fire` and a
plan's feedback reaches the prims. Crossbar green.

### H3 - The framework verbs

`//hud warp [all]`, `mr`, `sneak`, `invisible`, `draw`, `retry`, `wsgate`,
`delay` in `lib/commands` and core; the crossbar's `dispatch_command` loses
`warp` and the builtin fallthrough; the IPC string changes. `commands_spec`,
`core_spec` and `entry_point_spec` grow; `crossbar_commands_spec` shrinks.

### H4 - Make the engine geometry-generic

`bindings` over a `geometry`; `render` split; `slot.lua`; `bar.lua`; the
authoring CLI over the geometry's grammar and a verb roster; the binder over
rects. The crossbar is re-wired over all of it and its widget spec passes
unchanged wherever it can - a spec that had to change here is a behaviour
change to explain. Crossbar green.

### H5 - The hotbar

`components/hotbar/` as designed; registration; `component_aliases_spec`
(`hb`); `entry_point_spec` (what its ctx is built from); `hotbar_render_spec`
(each of the four shapes: slot N's position, row-major order, the label before
slot 1 in its orientation, `bounds` covering label and every slot from the
origin, the pitch shared with the 10x1 default so a stack of eight does not
overlap), `hotbar_defaults_spec` (eight anchors, `bar1` alone visible, `rows =
1` on all), `hotbar_spec` (routing by anchor, row 1 following the active set,
click-to-fire through every shape's rects, the binder session, per-anchor
show/hide, `rows` accepted for 1/2/5/10 and refused otherwise, a bar word
refused in front of a common verb, bounds equal to the origin given, a
reshape re-laying without rebuilding prims). `hotbar_input_spec` (every
modifier set to its row, `0` as slot 10, exact matching so CTRL+ALT is
nothing, both edges blocked on a bare key, no intent and no block under each
guard or on a `blocked` key, focus loss clearing a stuck modifier). In
`core_spec`: a second keyboard consumer sees `blocked = true` on a key the
first one took, and the inbound flag still reaches the first untouched.
`entry_point_spec` pins `crossbar` registered before `hotbar`.

### H6 - The skillchain indicator component

`components/skillchain/` as designed; the crossbar drops the
`skillchain_indicator` anchor from `ANCHORS`, `GROUPS`' neighbours,
`render.bounds`, `defaults.lua` and `set_preview`; `config.skillchain` goes
with it. Registration after `hotbar`; `component_aliases_spec` (`sc` here,
speedcheck re-aliased in `speedcheck.lua` the same phase);
`entry_point_spec`; `skillchain_spec` under `tests/components/` (the plan for
waiting and open states reaching the prims, the state-flip colour gate, the
preview plan, nothing drawn with no window or no service, bounds at the
origin given); the crossbar's `skillchain` describe block loses its indicator
cases and its anchor count drops to five. Crossbar green.

### H7 - Docs

CLAUDE.md: the module tree, the crossbar and hotbar entries, Commands (the
eight verbs, the hotbar's roster, `//hud crossbar warp` gone), Settings
(`core.lua`'s three new keys). `.claude/Planning/crossbar-in-client.md` gains
the rows a live client has to answer (below).

## As built (2026-09-06) - where the build departed from the plan above

- **H2 and H3 landed together.** The three tuning keys could not move to
  `core.lua` without their verbs moving with them, or one phase would have
  left `retry`/`wsgate`/`delay` unreachable.
- **The widget spec kept its execution blocks** rather than moving them to
  the service spec: they drive the widget through a `push` mirror of the
  entry point (service first, then the widget) and pass as integration
  tests, while `tests/actionbar/service_spec.lua` covers the service's own
  surface. Fifteen assertions lost the `crossbar: ` prefix the service's
  lines no longer carry (the entry point prefixes every line with the
  addon's); `retry`/`wsgate`/`delay` tuning is flipped in `env.service_config`
  where the widget's config used to hold it; and the widget's attach still
  drops a trip through `service.drop_trip()`, for parity.
- **`bindings` kept its weapon-state API** (`set_weapon_state`,
  `weapon_state`, `on_status`) rather than growing `on_weapon_state`: the
  service is the truth and the bar MIRRORS it in (`bar.sync_weapon`), which
  left the bindings spec untouched.
- **The retry probe** rides the press as `opts.retry_facts`, a closure the bar
  builds over the slot address, and reads the recasts live rather than off
  the tick's snapshot: the service steps the retry before the bar's tick
  refreshes that snapshot.
- **`open <name>` stayed on both bars**: it opens a game window, a bar's
  convenience rather than a press.
- **`core.on_keyboard` accumulates the block** exactly as decision 13's
  framework bullet describes, and `core.lua` gained `deps.get_mob_by_target`
  for `//hud wsgate`'s state line and `self.config()` for the service.
- **The hotbar builds a row's prims on the first TICK it is still shown**, not
  on the first `show`: core's apply sends the bare `show()` and then restates
  each anchor, so a build-on-show would have built all eight at every login.
- **The skillchain component** carries the placement as a constant (431 up
  from the screen bottom, centred) rather than reading the crossbar's
  geometry, which no component may reach.
- `lib/actionbar/defaults.lua` holds the slot cosmetics and set flags both
  bars ship; the crossbar's `defaults.lua` composes it.
- **Review round 1 (2026-09-06)** added four rules the plan had not spelled
  out: a built-in that went answers nil and core says nothing (the chat sink
  concatenates, so a nil there threw and would have disabled `//hud` after
  five presses - the core spec's chat fake now refuses a nil the way the
  client would); the service sheathes on a job change, as `set_job` does, or
  the mirror put the drawn rotation straight back; a held cast is keyed to
  the bar that PRESSED it (`opts.owner`), so one bar hiding drops only its
  own, and a countdown is the player's and goes only under suppression - a
  user switching one bar off no longer cancels a warp (a change from the
  single-bar crossbar, where any hide did); and a bar refuses to open its
  binder while another bar's is open. The hotbar grammar also stopped
  reading `wpn3:7` as a prefixed address.
- **Review rounds 2-4** added: the service is not built in safe mode (a
  service with no render loop to tick it would hold a GearSwap slot for the
  session on the first warp), and every ungated handler guards its absence;
  the crossbar's shortcut keys route `draw`/`mr`/`sneak`/`invisible`/`warp`
  to the service rather than dying with the verbs; `lib/actionbar/LICENSE.txt`
  carries the MIT and SirEdeonX notices for `kebab.lua` and `counters.lua`,
  whose headers point at it; a click or a number key on one bar is inert
  while the OTHER bar's binder is open (the shipped hotbar row sits inside
  the crossbar's binder window); the binder takes the bar's `name` and
  `grammar`, so the hotbar's window subheads `1:7` and speaks as the hotbar;
  the hotbar's bare `show()` is guarded against core's per-mouse-move
  apply, its set-number label is change-gated, and the crossbar's stale
  indicator comments are gone.
- **Review round 5** gave the hotbar's geometry the 10px name band the
  shared render draws a slot's name in (row pitch 56 inside a shape, 58
  between stacked rows, bounds include it), listed `rows` in `//hud hotbar
  help` (the CLI takes a bar's extra lines), scoped a bar's detach to its
  own held cast, and made the hotbar tear down the rows layout mode's
  force-show built once the preview ends. Not taken: a crossbar shortcut
  key bound to `retry`/`wsgate` (only `edit` ships bound), and two bars
  answering one click where a user drags one over the other - core does not
  arbitrate the mouse, and the shipped placements do not overlap.
- **Review round 6** moved that teardown to the TICK: core sends the preview
  flag before it restates each anchor, so a prune on `set_preview(false)`
  matched nothing; the hotbar spec now drives core's order. A whole-widget
  hide keeps a row's prims (the crossbar's posture), only a per-anchor hide
  tears one down.
- **Left as is, for Kevin**: a bar's re-attach (`//hud reset <bar>`, a slot
  switch) still drops the player's trip through `service.drop_trip()` -
  parity with the single-bar crossbar, which the widget spec pins
  ("drops the countdown on a re-attach, without a word") - even though a
  trip is the player's now and `//hud reset hotbar` therefore cancels a
  crossbar or console warp. Changing it means changing those tests.

## Testing

`busted` + `luacheck .` + `stylua --check .` at every phase. Moved specs move
whole; new specs are listed per phase. `tests/support/entry_point.lua` stubs
the hotbar factory and the service the way it stubs the crossbar's. The
widget spec's z-order contract (prim creation order) is asserted on the
crossbar only; the hotbar asserts its per-anchor build-on-show instead.

## Unverified - needs a live client

- `//hud draw` from the console against the engage transition: the sword and
  both bars' rotations should follow one state.
- Resting prim cost: crossbar 365 + hotbar `bar1` 90 + label; every row on is
  ~1,100. Whether that is felt.
- `warp all` after the IPC string change, between two updated clients.
- Text prims render above image prims; the hotbar's set-number label and the
  binder window must not fight the way the first binder design did.
- `//hud retry` and `//hud wsgate` state lines read from `core.lua` after a
  `//hud copy`.
- Whether the game binds anything to the BARE number row or to SHIFT+number
  outside the chat box. If it does, the hotbar's swallow takes it away, and
  that is a fact to document rather than a bug.
- That a crossbar hold plus `1` fires the crossbar alone once the block
  accumulates, and that a bare `1` with no hold fires the hotbar alone.
- Whether ALT chords reach the addon at all in a live client - the crossbar
  never used ALT, so the DIK stream for it is unobserved here.
- The crossbar's `layout.lua` after the indicator anchor leaves it: whether
  `layout.repair` sheds the stray `skillchain_indicator` entry or preserves it,
  and that the crossbar comes up clean either way. `//hud list` should show
  five crossbar anchors and one `skillchain` placement.

## What this plan does not do

- No keys for `bar8`, and no configurable key table (decision 13 and the
  flagged interpretation above). The crossbar's `input.lua` is untouched.
- No skillchain indicator on either bar (decision 14): per-slot chain
  borders only, the window bar is the `skillchain` component's.
- No migration of any stored file: crossbar `retry` / `wsgate` / `delay`
  blocks are left in place unread.
- No shapes beyond the four (decision 12) and no 12-slot XIV layout; the
  slot count is ten in every shape.
- No framework re-clamp when a row is reshaped; the statusbar's limitation,
  kept.
- No `//cb` / `//hb` console alias (decided 2026-08-30).
- No change to the crossbar's geometry, input, views or anchors.
