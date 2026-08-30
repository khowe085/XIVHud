# Slot-scoped configuration on disk - restructure plan

Status: SU1-SU5 built, 2026-08-29/30. 2504 specs green, luacheck and stylua clean. Three blind review rounds, clean verdict at round 3 (see Review findings). Worktree `.claude/worktrees/slot-update`, branch
`work/claude/slot-update`, branched from dev at 0948b95 (the commit that landed the
party list drag fix and its plan, #26). Scope: `src/lib/settings.lua`,
`src/lib/layout.lua`, `src/lib/core.lua`, the six components' `defaults.lua`, their
specs, `tests/support/fakes.lua`, and CLAUDE.md. `src/XIVHud.lua` needs nothing -
`ensure_dir` (`XIVHud.lua:292`) already builds arbitrary depth, and every file dep it
hands core is path-agnostic.

**No migration.** The user has waived it: everyone starts from a fresh configuration.
Nothing reads the old shape, and nothing warns about it.

## Goal

Make the layout slot a **directory** rather than a table key, and give every component
its own directory inside it:

```
data/
  <Character>/
    core.lua                    -- snap, hideCutscene, slot  (character-wide)
    <slot>/
      <component>/
        config.lua              -- the component's own settings
        layout.lua              -- pos / scale / visible, or anchors + visible
        <name>.lua              -- whatever else the component needs (the store)
```

against today's

```
data/
  <Character>/
    core.lua
    <component>.lua             -- settings at the top level + a `slots` table
    <component>/<name>.lua      -- the store, for a component that declares one
```

## Decisions taken before writing anything (2026-08-29, from the user)

1. **A slot scopes everything, not just layout.** This is the substantive change, and
   it is a new feature wearing the old name: today a slot scopes pos/scale/visible
   only, and behaviour (partylist spacing, targetbar mode, the crossbar's eight sets
   and its per-job bindings) is character-wide. After this, switching slots switches
   all of it. Crossbar's `set_flags` carries a comment calling itself "character-wide
   by definition"; that comment becomes wrong and is corrected in SU4.
2. **Core stays at character level.** `data/<Character>/core.lua`, holding `snap`,
   `hideCutscene` and `slot`. The active-slot pointer cannot live inside a slot, and
   the other two are not worth splitting off from it.
3. **Fixed file names.** `config.lua` and `layout.lua`, both core-created. A component
   may add files beside them through the store; `config` and `layout` become reserved
   store names so a store write cannot clobber either.
4. **Reset resets the current scope.** `//hud reset <component>` empties that
   component's directory *in the active slot*; `//hud reset all` does it for every
   component in the active slot. Neither touches another slot, and neither touches
   `core.lua` (which `reset all` already left alone, core not being in the registry).
5. **A slot switch re-reading disk is acceptable.** It now means re-attaching every
   component, which on the crossbar re-reads the per-job binding store and rebuilds
   its state.

Assumed, stated to the user and not contradicted:

6. **`//hud slot create <name>` copies the active slot's tree**, files and all -
   today's seeding behaviour, now a real file copy. A new slot starting from bare
   defaults would mean re-binding the crossbar from scratch every time.
7. **`wants_store` stays.** Every component now has a directory, so the flag is
   vestigial as a *capability* signal, but keeping it means a widget that ignores
   `store` keeps the exact three-argument contract it has today.

## What this deletes

The slot machinery in `lib/layout` exists only because slots were table keys inside a
file every component shared. With a directory per slot it all goes:

- `layout.slot(config, slot_name, defaults)` -> the *repair* half survives as
  `layout.repair(state, defaults)`; the create-on-first-use half is gone (a missing
  file is just defaults).
- `layout.create_slot` -> a tree copy in core.
- `layout.delete_slot` -> a tree delete in core.
- `layout.slot_names(config)` -> a directory listing in core.
- `core.slot_names()`'s union walk over every component's config (`core.lua:698-725`)
  -> `deps.list_dir("data/<char>")` filtered by `deps.is_dir`.

`layout` keeps exactly its maths: `snap`, `clamp`, `resolve`, `clamp_scale`, plus
`repair`.

## Design

### The settings service becomes slot-aware

Today `lib/settings` knows the character; the slot lives in core's config and
`lib/layout` indexes into `config.slots`. Now the *path* depends on the slot, so the
service has to know it - and there are two kinds of handle:

- **character-scoped** (`core` alone): `data/<Character>/core.lua`. One file, one
  table. `path()`, `get()`, `save()`, `reset()`.
- **slot-scoped** (every component): `data/<Character>/<slot>/<name>/`. Two tables,
  plus the store.

New surface:

```
settings.register_character(name, defaults)  -> character handle   (core)
settings.register(name, defaults)            -> component handle
settings.set_character(name)                 -- loads character-scoped handles only
settings.set_slot(name)                      -- loads slot-scoped handles
settings.reload()                            -- both, from disk (//hud copy)
settings.character() / settings.slot()

handle.config_path()   data/<char>/<slot>/<name>/config.lua
handle.layout_path()   data/<char>/<slot>/<name>/layout.lua
handle.dir()           data/<char>/<slot>/<name>
handle.get()           -- the config table  (nil while unscoped)
handle.layout()        -- the layout table  (nil while unscoped)
handle.save_config() / handle.save_layout() / handle.save()
handle.store_load(file) / handle.store_save(file, value)
handle.reset()
```

**Defaults are split at registration.** `component.defaults.layout` seeds `layout.lua`
and is removed from what seeds `config.lua`, so a component never sees its own layout
in `handle.get()` and `merge_defaults` cannot re-add it. That is the one rename each
component's `defaults.lua` needs: `slots = { default = X }` becomes `layout = X`.

**Ordering, and the chicken-and-egg.** The active slot is read from `core.lua`, which
is read once the character is known. So `set_character` must not eagerly load the
slot-scoped handles - it loads the character-scoped ones and leaves the rest unloaded;
core then reads `config.slot` and calls `set_slot`, which loads them. `set_slot`
always loads when called, rather than short-circuiting on an unchanged name, because
the character may have changed underneath it. Core calls the two in that order every
time, so each handle is read from disk exactly once per login.

### Core

- `default_state_of(component)` reads `component.defaults.layout` instead of
  `defaults.slots.default`.
- `state_of(component)` returns `handle.layout()` repaired by `layout.repair(...)`
  instead of `layout.slot(config, active_slot(), ...)`. Everything downstream -
  `placement_of`, `apply_placement`, `apply_overlay`, `describe`, `set_visible`, the
  `layout_mode` drag and wheel paths - is unchanged: they were already handed a state
  table and never knew where it came from.
- `persist(component)` becomes `handle.save_layout()` (core owns layout);
  `saver_for(component)` becomes `handle.save_config()` (the component owns its
  config). Today both are `handle.save()`, because both lived in one file. Anywhere
  core needs both (a slot switch persisting the seed) calls `handle.save()`.
- `set_character(name)` registers the core handle as character-scoped, then calls
  `settings.set_slot(active_slot())` before `apply_settings`.
- Slot verbs:
  - `slot_names()` -> directories under `data/<char>`, plus `default` and the active
    slot whether or not they exist yet, `default` first then alphabetical. Same
    output contract as today.
  - `slot_switch(name)` -> write `core.slot`, save core, `settings.set_slot`,
    re-`attach` every component, `apply_all()`.
  - `slot_create(name)` -> persist the active slot (so the files exist to copy), then
    `copy_tree("data/<char>/<active>", "data/<char>/<name>")`. Still refuses when no
    component is registered: a slot with no component directory has no directory at
    all, so it would not survive the listing.
  - `slot_delete(name)` -> `delete_tree("data/<char>/<slot>")`, same refusals as today
    (`default`, and the active slot).
- `reset(component)` -> `handle.reset()` empties the component's directory in the
  active slot (non-recursive; nothing nests inside it) and rewrites `config.lua` and
  `layout.lua` from defaults.
- `//hud copy` is untouched: `copy_tree`/`delete_tree` already recurse, and
  `character_dirs()` still lists `data/`. The tree is simply one level deeper.

### What a slot switch now costs

`attach` on every component, i.e. what `//hud reset` and the `//hud copy` reload
already do. The crossbar re-reads its binding store and rebuilds; the party list
rebuilds its rows. Accepted in decision 5.

## Phases

Each phase is test-first and self-contained: specs written and failing, then the code,
then `busted` + `luacheck .` + `stylua --check .` green before the next.

- **SU1 - `lib/settings`.** The two handle kinds, the config/layout split, the
  defaults split at registration, `set_slot`, reserved store names, `reset` over the
  component directory. `tests/settings_spec.lua` largely rewritten (paths, the split,
  the new ordering contract).
- **SU2 - `lib/layout`.** Delete `slot`, `create_slot`, `delete_slot`, `slot_names`;
  add `repair`, carrying over the anchored-entry repair and the stray top-level
  pos/scale shed. `tests/layout_spec.lua` trimmed and extended.
- **SU3 - `lib/core`.** Wire the two-step scoping, the layout defaults key, the split
  savers, and the four slot verbs onto the filesystem. `tests/core_spec.lua`: slot
  list/create/delete/switch against the fake fs, the reset scope, and that a slot
  switch re-attaches.
- **SU4 - components.** `slots = { default = X }` -> `layout = X` in all six
  `defaults.lua` (partylist, parambar, targetbar, equipviewer, giltracker, crossbar -
  crossbar assigns `config.slots` at the end of its builder). Fix the now-wrong
  "character-wide by definition" comment on `set_flags`. Update whichever component
  specs index `.slots`.
- **SU5 - docs and the gate.** CLAUDE.md: the Settings section, the layout-slots
  bullet, the `data/` tree in Modular design, the reset wording under Commands, and
  the per-component bullets that name `data/<Character>/<component>.lua`. Then the
  full run and the blind independent review gate.

## Risks

1. **PR #26 (`partylist-anchors`) is in flight over the same files.** It rewrites
   `src/components/partylist/defaults.lua` - the file SU4 renames `slots` in - and its
   plan records "the three config files merge into one
   `data/<Character>/partylist.lua`", a path this change deletes. Whichever lands
   second carries the conflict. It is small and mechanical either way, but it is real:
   flagged to the user rather than resolved here.
2. **Nothing here is exercised by Windower.** The new tree is four levels deep and
   every write goes through `ensure_dir`, which is proven for three. It builds
   segment by segment, so depth is not a new code path - but "green locally does not
   mean it loads" applies, and a first login writing
   `data/Char/default/crossbar/config.lua` is the in-client check to run first.
3. **A slot switch mid-combat now re-attaches the crossbar.** Cheap in prims, but it
   is a state rebuild where it used to be a table index. Worth watching in a live
   client.

## Review findings applied

Round 1 (all three real, and two invisible to the suite as it stood):

1. **`//hud slot delete` did not delete the slot.** `os.remove` refuses a directory
   on Windows, so the delete emptied the tree and left every directory standing -
   and `slot_names` asked `dir_exists`, so the slot went on being listed, could not
   be re-created, and switched into a slot of nothing but defaults. Fixed by making
   existence not the test: a slot is a directory holding at least one component
   directory **with a file in it** (`core.is_slot_dir`). The same rule answers the
   third finding.
2. **The active slot was composed into a path unvalidated.** `core.lua` is
   hand-editable and `//hud copy` imports another character's; `slot = '../Bravo'`
   reached `data/<Char>/../Bravo/...`, which `//hud reset` deletes inside.
   `active_slot()` now checks `^[%w_]+$` like every other slot-name entry point.
3. **A pre-slot install's `data/<Character>/<component>/` was offered as a slot** -
   every crossbar user's binding directory would have shown up in `//hud slot list`.
   Covered by the rule in 1 (loose files, no component directory).
4. `//hud slot create` ignored the result of the saves it makes before copying, so a
   failed write reported success and created nothing.

The fake file system could not represent an emptied directory (it derived
directories from file paths), which is exactly why 1 and 3 were green. It now tracks
directories separately and never removes one, matching `os.remove` on Windows.

Round 2 was mutation-tested and found no production defect, but four real coverage
gaps - the `set_slot` after `//hud copy`'s reload, `slot_create`'s failure guard (its
assertion passed on lib/settings' own write warning), and both halves of the
config/layout write split. All four now fail under the reviewer's mutations. Its one
optional finding was taken as well: slot names are compared case-insensitively
throughout (`same_slot`), since a hand-edited `core.lua` disagreeing with the
directory's casing listed one slot twice and made the active one deletable.

Round 3 returned CLEAN (12 mutations, all caught). Three of its four optional
findings were taken anyway: the `default`-first hoist missed a `Default/`
directory; the new "already active" early return meant an invalid `slot` in a
hand-edited `core.lua` could never be corrected from in-game, since `active_slot`
answers `default` for it and the switch returned before writing; and `slot_create`
claimed success when the copy read nothing at all. The fourth - `copy_tree` calling
`deps.list_dir` unguarded where its neighbours guard it - is left as it was: the
entry point always supplies the dep, and the guard would be for a caller that does
not exist.

## Carried, not fixed

`tests/components/crossbar_spec.lua` arrives with ~160 lines of pure re-indentation.
That file is **not `stylua --check` clean on dev** (it is the only one), and the
repo-wide format run in this branch fixed it. Reverting it would leave the branch
failing the repo's own bar, so it rides along; it is mechanical and unrelated.
