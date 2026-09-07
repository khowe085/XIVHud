# Global buff verbs (`//hud buffs`) - plan

Status: DONE. Merged into dev as PR #44 (6d22342) on 2026-09-05; the worktree and branch are gone.
Two deviations from the design below, both flagged in the summary to Kevin:
the bare `//hud buffs statusbar` keeps listing EVERY bar (the existing
behaviour - a bar word narrows it) rather than defaulting to bar1, and the
status bar's `filter <category>` assignment moved under `//hud buffs` with
the filter-list edits, since splitting one verb across two paths is worse
than a category choice sitting beside the list it filters.

## Goal

Move the buff order/filter verbs out from under the two components that draw
buffs and behind one framework verb, so the same grammar reaches either:

```
//hud buffs                                   -- the grammar below, as a hint
//hud buffs active                            -- the player's buffs right now, all of them
//hud buffs <component> [<anchor>]            -- what that anchor draws, past its cap
//hud buffs <component> [<anchor>] list [page] | find <text>
//hud buffs <component> [<anchor>] top|up|down <id|name> | rank <id|name> <n> | reset
//hud buffs <component> [<anchor>] filter add|remove|clear|list [<id|name>] | filter mode blacklist|whitelist
//hud buffs partylist [<list>] active [<member>]   -- partylist's own extra verb, moved with the rest
```

`<component>` takes a name or alias exactly as `show|hide|reset` do. The
old paths (`//hud partylist [<list>] buff ...`, `//hud statusbar buff ...`,
`//hud statusbar [<bar>] filter ...`) are REMOVED, not kept beside the new
one: a second path to the same setting is the "two switches that can only
disagree" shape this repo has removed twice already.

## Decisions taken before writing anything (Kevin, 2026-09-05)

1. **Old paths go away, with no pointer.** `buff` (and statusbar's
   `filter`) simply stop being verbs of `handle_command`, and fall to each
   component's ordinary unknown-verb hint like any other word.
2. **`//hud buffs active` is core's, from the player service, no ranks.**
   Option 2 of the three offered: core lists the player's own buffs (id and
   name, sorted by the SHIPPED order - the per-component ranks are the
   components' and core does not hold them). It takes no member name: a
   name after `active` is refused with a pointer at
   `//hud buffs partylist active <member>`, which is where partylist's
   0x076-backed reader lands under the new routing.
3. **The sub word is the anchor name, defaulting to the first anchor.**
   `main` on partylist, `bar1` on statusbar. Kevin's words were "use
   `main`", which only exists on partylist; read as "the primary anchor",
   which is what both components already default to. **Open** - confirm.

## Interpretation flagged open

- `active [<Name>]` in the ask was read as a MEMBER name (partylist's
  existing meaning), not a buff name to test for. If it meant "is Haste
  up", say so: that is a `find`-shaped verb over the player's list and
  belongs in core beside `active`.

## Reference

- `src/lib/commands.lua` - the parser; `RESERVED` is what the registry
  refuses as a component name or alias, so adding `buffs` there covers the
  registry for free (`deps.reserved` at `registry.lua:50`).
- `src/lib/core.lua:1188` - the `component` action, the model for routing.
  Core's `get_player` is the RAW read (deliberately, for the login retry);
  one read per typed command is fine. Core has no `resources` dep today.
- `src/lib/buffs.lua` - the shared engine. Every message paths through
  `NAME`, `BUFF_PATH`, `FILTER_PATH`; the page hint at line 308 hardcodes
  `'//hud %s buff list <page>'` and must move onto `BUFF_PATH`.
- `src/components/partylist/logic.lua:1033` - `buff_command`, and
  `active_buffs` above it; `partylist.lua:1031` routes `[<list>] <verb>`.
- `src/components/statusbar/logic.lua:500` - `buff_command`; `filter` is
  per bar under `command` at 575, the order verbs refuse a bar word at 559.

## Design

**Contract.** One new opt-in widget member, `handle_buffs(args) -> lines`,
detected as a member and never by convention (the `anchors()` rule). `args`
is everything after the component word, untouched: only the component knows
its anchors, so the default anchor resolves inside it. Core answers "X draws
no buffs" for a component without the member. Parambar, crossbar and the
rest need no edit.

**Parser** (`lib/commands`). `buffs` joins `RESERVED`. Actions:

| input | action |
|---|---|
| `//hud buffs` | `error` with the grammar hint |
| `//hud buffs active` | `{ action = "buffs", op = "active" }` |
| `//hud buffs active <x>` | `error`: pointer at `//hud buffs partylist active <x>` |
| `//hud buffs <component> ...` | `{ action = "buffs", component = <resolved>, args = {...} }` |
| `//hud buffs <unknown>` | `error`: no component named |

**Core.** Both ops behind `require_character()`. `active` reads
`deps.get_player().buffs`, drops `255`, sorts through `lib/buffs`'s
`order({})` + `sort` (shipped ranks) and prints `id  name` per line, or
"you have no buffs". Naming needs `res.buffs`, so core gains a `resources`
dep (nil without the libraries: `lib/buffs` already falls back to
`buff 33`). The component op calls `handle_buffs` and says the lines the way
the `component` action does. `HELP` grows the `buffs` lines.

**lib/buffs.** Default `BUFF_PATH` becomes `"buffs " .. NAME` and
`FILTER_PATH` `"buffs " .. NAME .. " filter"`; the hardcoded page hint uses
`BUFF_PATH`. No grammar change: `command(settings, words, cap)` still takes
the words after the anchor.

**partylist.** `handle_buffs`: strip an optional list word (default `main`);
a non-main list is refused as today (buffs are `lists.main`'s, and the
refusal names the new path); `active [<member>]` stays partylist's extra
verb, everything else to the engine. `handle_command` drops `buff`; it falls
to the unknown-verb hint. Engine paths: `buffs partylist`.

**statusbar.** `handle_buffs`: strip an optional bar word (default `bar1`);
bare = that bar's `active` view (what it draws, past capacity - the current
bare `buff <bar>`); `filter ...` edits THAT bar's list (the current
`[<bar>] filter`); the order verbs are component-wide, so a bar word in
front of one is REFUSED as today rather than dropped. `handle_command` keeps
`rows`, `timers`, `tooltips`; `buff` and `filter` fall to the unknown-verb hint.
Engine paths: `buffs statusbar` / `buffs statusbar <bar> filter`.

## Phases (strict TDD, one PR)

- **GB1 parser + registry.** `commands_spec`: the five rows above, alias
  resolution, `buffs` listed in the reserved set. `component_aliases_spec`
  still green (nothing is called `buffs`).
- **GB2 core.** `core_spec`: `active` with buffs / without / logged out;
  routing to `handle_buffs` and the "draws no buffs" refusal; help lists the
  verb. `entry_point_spec`: core is built with `resources`.
- **GB3 lib/buffs paths.** `buffs_spec`: every message names the new path;
  the page hint follows `BUFF_PATH`.
- **GB4 partylist.** `partylist_logic_spec` / `partylist_spec`: rewrite the
  `buff` cases onto `handle_buffs`, the list default, the non-main refusal
  naming the new path, `active` still there, `handle_command buff` is an unknown verb.
- **GB5 statusbar.** Same shape: bare/`<bar>` active view, per-bar filter,
  order verbs shared and bar-word refused, `buff`/`filter` unknown to `handle_command`.
- **GB6 docs.** CLAUDE.md Commands section (the partylist block, the new
  `buffs` block, the alias sentence), the component bullets that name
  `//hud partylist buff`, `.claude/Planning/statusbar.md` decision 5.

Roughly 60 existing spec lines rewritten across three specs, plus new ones.

## Testing

`busted` + `luacheck .` + `stylua --check .`. `tests/sources_spec.lua`
guards ASCII in every new message.

## Unverified - needs a live client

- The `buffs` word routing through Windower's argument split (no reason to
  expect trouble: it is one more reserved verb beside `show`).

## What this plan does not do

- No migration, compatibility shim or pointer message for the old paths.
- No ranks in core's `active`; no member lookup in core.
- No change to what either component draws.
