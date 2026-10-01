# hud-config: the `//hud config` settings window

Status: all five phases built, 2026-10-01, in worktree `.claude/worktrees/hud-config`, branch
`work/claude/hud-config`: the pull, the chrome extraction, the framework and the `global` panel,
and the panels of all eight components. Not committed, and not verified in a live client.
Decisions settled with Kevin 2026-10-01 (below).

## Goal

A mouse-driven settings window opened with `//hud config`, in the style of the edit binder: a left
column listing every component that has settings plus a `global` entry, the selected entry's panel on
the right, and tabs across the top of a panel where one page cannot hold it (crossbar, hotbar,
partylist, invtracker). It covers exactly the command-settable surface that is neither slot authoring
(`bind`/`unbind`/`alias`/`icon`/`swap`), nor the layout engine's (`pos`/`scale`/`visible`,
`show`/`hide`), nor a one-shot action (`warp`, `reset`, `clear`, `icons probe`, `accuracy reset`).

Settled up front (Kevin, 2026-10-01):

- Plan name `hud-config`.
- Buff **list editors are out of v1** - the priority order and filter id-list verbs
  (`top|up|down|rank`, `filter add|remove|clear`, `find`, `list`). The statusbar's per-bar
  **category picker** (`all|buffs|debuffs|other`) stays in: it is a simple choice.
- Numerics are edited with **+/- steppers**, stepping within each setting's documented bounds.
  No text entry - the prim wrappers have no input widget, so typed values stay the CLI's.

## Non-goals

- Buff priority/filter list editing (a later feature of its own: search, paging, reordering).
- Anything the binder or layout mode already owns.
- File-only keys with no command surface (`retry.window/backoff/deadline/attempts`,
  `buffs.max_icons`, skillchain's colors) - except `snap`/`hideCutscene`, see Open questions.
- Text entry of any kind.

## Panel inventory

Everything below is verified against the current parsers and defaults (file refs are local `dev`
HEAD). "choice" renders as `[<] value [>]` cycling the options; "stepper" as `[-] value [+]`;
"toggle" flips on click.

### global (stored in `data/<Char>/core.lua`, core's own handlers, core.lua:1297-1441)

| Setting | Control | Bounds | Default |
|---|---|---|---|
| retry | toggle | | off |
| wsgate | toggle | | off |
| wsgate range | stepper | > 0, step 0.5 | 4 |
| wsgate pivot | stepper | >= 0, step 0.1 | 1.3 |
| delay | stepper | >= 0, step 1 (0 = off) | 5 |
| hidecutscene | toggle | | on |

`hidecutscene` is file-only today (`hideCutscene`, read only in `apply_settings` at login and after
`//hud copy`), so phase 2 adds `//hud hidecutscene on|off` and the handler re-applies visibility
immediately - a toggle that waited for the next login would read as broken. `snap` stays file-only
and out of the panel (Kevin, 2026-10-01).

### crossbar (shared roster: lib/actionbar/commands.lua:1003-1139; stored in its config.lua, not the job files)

- **Sets** tab - per set 1-8: `shared` toggle (off); `cycle` choice of `both|drawn|sheathed|none`
  (both).
- **Views** tab - per view `wxhb-L | wxhb-R | exp-LR | exp-RL`: choice of the sixteen `<set><L|R>`
  values (defaults 2L, 2R, 3L, 3R).
- **General** tab - `wxhb` always-show toggle (off).

### hotbar

- **Sets** tab - share + cycle per set, as the crossbar's (its own eight sets).
- **Rows** tab - per bar1..bar8: shape choice `10x1|5x2|2x5|1x10` (10x1); `hideempty` toggle. The
  per-row key is unseeded and falls back to the bar-wide `hide.empty_slots` (hotbar.lua:138-149):
  the panel shows the effective value and the first click writes the per-row key, exactly as the
  CLI does.
- **General** tab - `numbers` toggle (on).

### partylist (tabs per list: main / alliance1 / alliance2)

- Each list: `spacing` stepper >= 0 (0); `align` choice top|bottom (top); `emptyrows` toggle (off).
- Main only (the component refuses a list word on these, and the panel simply omits them from the
  alliance tabs): `hidesolo` toggle (off); range mode choice `num|icons` (icons); range `near`/`far`
  steppers >= 0 (0/0 - far >= near validation stays in the component, see Write path).

### statusbar (one page, no tabs - eight rows)

- Per bar1..3: `rows` choice 1-4 (1); filter category choice `all|buffs|debuffs|other`
  (all / debuffs / other). The category routes through `handle_buffs`, not `handle_command` -
  see Write path.
- Shared: `timers` toggle (on); `tooltips` toggle (on).

### targetbar (one page)

- Per bar main/subtarget: `mode` choice `auto|default|magic|ninjutsu|gun|bow|xbow` (auto).

### parambar (one page)

- `width` stepper >= 8 (132 / compact 116); `spacing` stepper >= 0 (18/16); `offset` stepper >= 0
  (0). These write the **active** mode's block (`bar` or `compact_bar`), exactly as the CLI does -
  the panel's values are read from whichever block `compact` selects.
- `compact` toggle (off); `accuracy` toggle (on); accuracy `window` stepper 1..600 (30).

### equipviewer (one page)

- `encumbrance` toggle (on); `ammocount` toggle (on).

### invtracker

- **Bags** tab - per group (equipment, inventory, safe, storage, locker, satchel, sack, case,
  wardrobe, temporary, treasure): enabled toggle + columns stepper 1..20, one row per bag.
- **General** tab - `sort` toggle (on); `labels` toggle (on); `spacing` stepper 3..32 (4);
  `blockspacing` stepper 0..64 (4); `align` choice top|bottom (bottom).

### No menu entry

giltracker, speedcheck, skillchain and expbar have no settings commands (expbar's `clear` is an
action), so they do not appear in the menu at all - the pattern `//hud list` set: the window cannot
offer what a component does not declare.

## Architecture

### One write path: the window emits the commands

The window never touches a config table. A click synthesizes the same words the CLI takes and routes
them through the same function core's passthrough calls:

- Component rows: `component.handle_command(args)` - validation, refusals, persistence and repaint
  all come for free, and the UI *cannot* set something the CLI couldn't (the `fire_at` rule: two
  ways in, one behaviour).
- Statusbar category rows: `component.handle_buffs({bar, "filter", cat})` - the only path that
  verb has (statusbar logic.lua:422-442).
- Global rows: core's `retry`/`wsgate`/`delay` handlers, factored so each returns its message and
  both `//hud` and the window call the one function.

The returned message is shown in a **status line inside the window**, not said to chat - the window
calls the handler directly, so nothing goes through `say_lines`.

### Reading current values: a new opt-in widget member

`config_panel() -> panel`, detected by presence exactly as `handle_buffs` is (core.lua:828-834).
A component builds the panel fresh each time it is asked, so values are always current. Shape:

```lua
{ tabs = { { name = "sets", rows = {
    { label = "Set 1 shared", kind = "toggle",  value = false, command = {"share", "1"} },
    { label = "Set 1 cycle",  kind = "choice",  value = "both",
      options = {"both","drawn","sheathed","none"}, command = {"cycle", "1"} },
    { label = "Window",       kind = "stepper", value = 30, min = 1, max = 600, step = 1,
      command = {"accuracy", "window"} },
} } } }
```

The window appends the new value as the final word(s) (`on`/`off` for a toggle). An optional
`route = "buffs"` on a row sends it through `handle_buffs` instead. A single-page panel is
`{ rows = ... }` with no tabs. A widget declaring no `config_panel` gets no menu entry and sees
nothing new - the existing contract rule.

The `global` panel is core's own, built beside its tuning handlers; it is not a component.

### Window chrome: extracted from the binder

The binder's chrome is all closures inside `new(deps)` - nothing is exported (binder.lua) - and
about half of it is generic: the prim factories, backdrop, `build_frame`, `clamp_to_screen`, row
drawing with hide-the-rest, `paged`, the window-region hit order, and the mouse machine
(press/drag threshold, header drag with save-on-drop, wheel paging), plus open/close/destroy.

**Proposal: extract that half into `lib/window.lua`** and refactor the binder onto it, as a pure
refactor with the binder specs staying green, before the config window is built on the same module.
The drag/press/wheel machine is subtle and worth one copy (the repo's "the two cannot drift" rule).
The fallback, if the refactor fights the binder's closures too hard, is to imitate the chrome in the
config window for v1 and extract later - accepted duplication, flagged, not silent.

~70% confident extraction is the right first move; the main risk is churn against upstream #58,
which is why pulling comes first (below).

**As built (phase 1, 2026-10-01).** `lib/window.lua` holds nothing binder-specific: the mouse type
constants and `inside`, the frame and its geometry (`frame`, `position`, `metrics`), the prim
`pool`, `paged` (one page of a list laid into a column), `draw_rows`, `draw_frame`/`hide_frame`,
`control_at` (close, back, title strip, in that order) and a **press tracker**
(`press`/`pressed`/`motion`/`release`/`cancel`: the drag threshold and the title-strip drag with its
clamp). It owns no position, page, hover or open flag - those stay each client's. The binder is its
only client until phase 2.

One deviation from the proposal above: the *composed* mouse machine is not shared, only the tracker
under it. The binder's `mouse()` sequencing stays in the binder, because that is where the ghost,
the stranded-press read and the cross-bar arbitration live; the config window writes its own short
`mouse` over the same tracker, and phase 2 adds a parity test running one event script through both.
Wheel handling stays the binder's: the config window lays its lists out with `paged` but shows one
page (no shipped panel overflows; a cross-component spec pins that). The seam was settled by a
three-design judge panel. Five characterisation tests went into `binder_spec` BEFORE the refactor -
prim creation order and roles, the title-strip slip, the details standing down on a window drag, a
press dropped by close/open - each mutation-checked against the unrefactored binder.

Carried forward from the API-edge review, for the config window to honour: every target handed to
`press` carries a rect; `draw_frame` is always given strings (a nil reaches the texts library as a
READ); every close path calls `cancel`. One pre-existing behaviour, unchanged here and Kevin's to
call: a window drag starts only once the cursor LEAVES the title strip, so a purely sideways drag
along it moves nothing until it exits.

### Core: a third config mode

- **Verb**: `config` joins RESERVED (lib/commands.lua:39-59) with a parse branch and a `run` branch
  + HELP entry in core. The registry refusal for a clashing component name follows automatically
  (core.lua:140); no shipped name or alias collides. (`config` is already reserved as a *store file*
  name, settings.lua:60 - unrelated, no conflict.)
- **Requires a character**, like every settings verb (the panels read per-character config).
  Logout closes the window.
- **Mouse ownership**: `core.on_mouse` routes every event to the window while it is open, right
  where the layout-mode branch sits (core.lua:709-726) - no component sees the mouse, layout mode's
  rule. Keyboard is untouched: still delivered to components (the pinned 2026-08-16 design).
- **Mutual exclusion**, following the binder's precedents exactly:
  - `//hud config` while layout mode is on: **refused** with a hint (`toggle_edit`'s rule,
    bar.lua:977-979).
  - `//hud config` while a binder is open: closes the binder(s) and opens the window (upstream
    `close_edit_all` on the service once dev is pulled).
  - `//hud layout` while the window is open: closes the window and enters layout mode (the
    entering-layout-exits-edit-mode rule).
- **Trip cancel**: the service gains a third config-mode source - `service.set_config_ui(open)`,
  reported by `config_mode()` as `"//hud config"` - so an armed trip is cancelled on open and
  arming is refused while open (service.lua:429-457, 984-988). Deliberately **not** via
  `set_edit_mode("config", ...)`: upstream makes every bar dress as a drop target whenever
  `edit_owner()` is non-nil, and the bars must not dress up for a settings window.
- **Suppression outranks the window**, as it does layout mode: hidden during cutscene/zoning, and
  `core.on_mouse` already drops events while suppressed.
- **Prims**: built on open, destroyed on close - the binder's lifecycle, zero resting cost.
- **Window position**: draggable by the header, saved on drop to core.lua (e.g. `config_ui.pos`) -
  character-wide, the same move as `binder_pos` but in core's file since the window is core's.
- **Entry point**: core's deps gain `asset` (it currently receives none) so the window can resolve
  the backdrop texture; injected in `src/XIVHud.lua` beside `overlay_texture`.

**As built (phase 2, 2026-10-01).** As above, with these differences and additions:

- **The service is ASKED, not told**: `deps.settings_open()` (the entry point wires it to
  `core.config_active()`), exactly as `deps.layout_active` is, instead of the `set_config_ui(open)`
  setter proposed above. A flag kept in the service would be a second opinion of whether the window
  is open, and a logout would have to remember to clear it.
- **The position key is `config_pos`** in core.lua, by analogy with each bar's `binder_pos`, not
  `config_ui.pos`. Unseeded: absent means centred.
- **`global` is reserved** beside `config`: a component of that name could never be opened by
  `//hud config <name>`.
- **A click outside the window is the game's and does not close it** (the binder dismisses its
  panel on one; this window is the whole mode). **The bars' KEYS still fire while it is open**:
  keyboard delivery is untouched, as planned, and nothing makes a bar inert for this mode. The trip
  refusal and the retry clear do apply (the service counts it as a config mode), so a warp or mount
  pressed from a bar key while the window is open is refused, while an ordinary action goes. Both
  are Kevin's to overturn.
- **A row's words are `command .. value .. suffix`**: the optional `suffix` exists for a command
  whose value is not its last word (partylist's `range <near> <far>`).
- **Kinds built so far: toggle and stepper** (all `global` needs). `choice` lands with the first
  panel that needs one, in phase 3.
- **No paging**: a panel's rows are laid into the column and anything past the last row is not
  drawn. Phase 3 adds the cross-component spec that pins every shipped panel inside it.
- **A typed command refreshes an open window** (core re-reads the panel after every `//hud`
  command), and a change of character closes it.
- The tuners (`retry`, `wsgate`, `delay`, `hidecutscene`) now ANSWER their line; `//hud` says it
  and the window writes it on its status line.
- A parity test in `binder_spec` runs one mouse script through the binder and the settings window
  and compares every verdict the two share.

## Phasing

Each phase is independently green (`busted` + `luacheck` + `stylua --check`) and reviewable.

0. **Pull `origin/dev` first.** Done 2026-10-01 (8a5eff6 -> 6c4a45a): #58 reshapes
   binder/service/bar (ghost drag, `close_edit_all`, `register_bar`), all of which this touches.
   Line refs above for binder.lua and service.lua were taken at the pre-pull HEAD and will have
   shifted; the rest (core, commands, settings, component logic) are untouched by the pull.
1. **Chrome extraction**: `lib/window.lua`, binder refactored onto it, binder specs green,
   no behaviour change. Built 2026-10-01 - see "As built (phase 1)" above for the one deviation.
2. **Framework**: `config` reserved verb; core's config mode (mouse ownership, exclusivity, trip
   cancel, suppression); the window shell (menu, empty panel, status line,
   drag + persist); the **global** panel; the new `//hud hidecutscene on|off` verb (re-applying
   visibility at once); the `//hud config <component>` deep link. Built 2026-10-01 - see
   "As built (phase 2)" above.
3. **`config_panel` member** + the simple panels: equipviewer, targetbar, statusbar, parambar.
4. **partylist + invtracker**: tabs and steppers at volume.
5. **crossbar + hotbar**: Sets / Views / Rows / General tabs.

Phases 3-5 built 2026-10-01 - see "As built (phases 3-5)" below.

Docs (CLAUDE.md Commands block, wiki, README) update in phase 2 for the verb, then as panels land.
Implementation per tdd-workflow, in its own worktree under `.claude/worktrees`, recorded in
`work.md`.

## As built (phases 3-5, 2026-10-01)

The `choice` control landed first (`[<] value [>]`, wrapping; `options` plus optional `labels`; a
stored value off the list is shown as it stands and steps onto the list), then
`config_window.capacity()` and `tests/support/panels.lua` - `problems` for a panel's shape and
`exercise`, which stands the real window over the attached widget and clicks every control once.
equipviewer was built by hand as the worked example; the other seven were built test-first by one
agent per component in disjoint files, each to that example and those two helpers.

Where the panels differ from the inventory above:

- **invtracker is three tabs, not two**: `bags` (eleven switches), `columns` (eleven steppers) and
  `general`. A row is one control, so "one row per bag with both" would be twenty-two rows on a page
  that holds nineteen.
- **partylist's range rows bound each other.** `range <near> <far>` refuses a far ring inside the
  near one, so near's max is far and far's min is near - a click cannot produce a refusal. The cost:
  the far ring cannot be switched OFF (0) from the window while the near one is on; that is typed.
  A far ring that is off under a near one steps straight onto the near distance, the first value
  the command accepts.
- **A value shown is the one in force, not the one stored**, on every panel: the status bar's rows
  through `shape`, a non-category filter as `all`, targetbar's mode through `configured_mode`,
  invtracker's columns clamped as the grid draws them, the hotbar's `hide_empty` through the
  bar-wide fallback. For a hand-broken file this can differ from what the component's status line
  prints (invtracker prints the stored column count); they agree for every value a command can set.
- **Step sizes**: parambar's width steps by 4 and its accuracy window by 5; every other stepper by
  1 (the gate's reach by 0.5 and pivot by 0.1). A value between steps is typed.
- **The two bars' `sets` tab is one function** (`lib/actionbar/commands.config_tabs`), which also
  carries the crossbar's `views` and `general`; the hotbar appends its own `rows` and `general`.
  `bindings.cycles(set, state)` and `render.shapes()` were added for it to read through.
- **The `cycle <set> <mode>` verb now writes a table of the set's own** rather than the shared
  mode table - behaviour-preserving, and needed once the modes became a module-level list.
- Not on any panel, by design: buff order and filter lists, `accuracy reset`, `expbar clear`,
  `icons probe`, slot authoring, and the bars' active set.

**Fonts are left as they are** (Kevin, 2026-10-01). The settings window draws in the chrome's
default `sans-serif`; a binder draws in its own bar's `font`. The three match at the shipped
defaults and diverge only if a bar's `font` is changed. A single font in core, used globally, was
raised and set aside for now - it would touch every component's own font key and is its own piece
of work.

Review found one hole in phase 2 after it was built: a bar's `edit` could still be opened under
the open settings window, where no click could reach it. `bar.toggle_edit` now refuses while the
window is open (`service.settings_open()`), as it does under layout mode. And a row routed to the
buff verbs no longer falls back to `handle_command` on a widget with no `handle_buffs`: it answers
"draws no buffs", as `//hud buffs <component>` does.

**Review gate.** Round 1 (phases 1-2): ISSUES - the binder-under-the-window hole above, plus a
stepper that stepped the wrong way from a value stored outside its bounds, both fixed behind
failing tests. Round 2 (all five phases): CLEAN, with five optional findings. Three taken, each
behind a failing test: a panel or a command that throws no longer throws through the window (it
runs inside the mouse handler, where five errors make the guard switch that handler off for every
component - both calls are `pcall`'d and the error goes on the status line); a command's lines
past the first are said in chat rather than dropped (`share <set> on` warns on its second line);
and each component is sent one move to `-1, -1` as the window opens, so the status bar's tooltip
is not left up under it. Two left, for a live client to settle: a right-click over the window
reaches the game (as it does over the binder), and the X releases input capture from inside the
mouse handler, which in `safe_mode` alone would unregister that handler mid-dispatch.

Round 3 (run because production code changed after round 2's clean verdict - the optionals above
and the verification fixes below): CLEAN, four optional notes. Two taken: a stepper row whose
stored value is not a number is drawn as it stands and sends nothing (the panel READ was guarded,
drawing its rows was not), and the `hidecutscene` help line is back in column. Two left: a long
reply may run past the status line's right edge at 18pt (cosmetic, needs a live client), and
targetbar copies its option list per call where the other panels hand out a module-level one
(harmless - the window only reads them).

**Independent verification of the panels** (one verifier per panel, on a frozen snapshot: the real
window driven over the attached widget across stored states, a base-versus-new differential of
each component's existing commands, and mutation testing). All eight came back sound for every
state a command can produce - zero refusals over thousands of driven clicks each, zero differences
in any existing command. What it changed:

- **A crossbar view row showed the wrong side for a hand-written `side = "L"`** (`2R` shown, `2L`
  drawn). `commands.view_word` now folds the side through `grammar.sides`, as the binding model
  does, and says `none` for a side the model cannot read.
- **A whole step lands on a whole number** (`config_window.stepped`). Three verifiers independently
  found a stepper left dead by a fraction stored in a hand-edited file - every click sent another
  fraction, which a whole-number command refuses.
- The survivors' kill tests are in each spec (statusbar 3, partylist 3, invtracker 3, the action
  bars' 3, parambar 2), each run against the real code and against its mutants.
- Left as it is, hand-edit only: a fractional or negative partylist range distance, and an
  invtracker `slot_size` above the spacing ceiling. Both answer with the command's own refusal.

## Testing

- `tests/window_spec.lua` + `tests/config_window_spec.lua`, headless on the binder_spec pattern:
  build with `fakes.prims()`, click via `mouse(1,x,y,0)` / `mouse(2,...)` at coordinates taken from
  the window's own descriptors, assert through `shown_text` / recorded prim calls, destroyed-on-close.
- `core_spec`: verb routing, require-character, exclusivity with layout mode and binders, mouse
  ownership while open, trip cancel against the fake service, suppression.
- Component specs: each `config_panel` pinned (labels, kinds, bounds, defaults) and round-tripped -
  click-synthesized words through `handle_command` change the config, and a fresh panel shows the
  new value.
- `commands_spec` / `core_spec` reserved + HELP pins updated; `component_aliases_spec` confirms no
  shipped name collides with `config`.
- New source files clear `sources_spec` (BSD header, ASCII outside comments, slash requires,
  no process spawn).

## Decisions (Kevin, 2026-10-01)

1. **`hideCutscene` goes in the global panel**, behind a new `//hud hidecutscene on|off` verb so the
   window stays a command front-end. **`snap` is left out** - no verb, no panel row.
2. **The Views picker** ships as the `[<] [>]` cycle over the sixteen values, as proposed.
3. **`//hud config <component>`** deep link approved (name or alias; opens with that panel
   selected). Phase 2.
4. **No hold-to-repeat on steppers**: one write per click.
