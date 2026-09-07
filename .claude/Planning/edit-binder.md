# Edit binder: the parent-menu ability families

Bind the actions that live *behind* a menu entry - stratagems, phantom rolls,
quick draw shots, runes, wards, effusions, blood pacts, ready moves - which
the picker cannot currently reach.

## The defect

Kevin, 2026-09-07, live client: clicking a slot, picking `/SCH`, then
`Job Abilities`, then `Stratagems`, went straight to the target step. There was
no way to reach `Accession`.

`Stratagems` is not an ability. `res.job_abilities[223]` is
`en="Stratagems", recast_id=233, prefix="/jobability", type="JobAbility"` - the
**menu parent**, and the game opens a submenu from it. The sixteen real
stratagems are `type="Scholar"`, all on `recast_id=231`. Binding 223 writes
`/ja "Stratagems" <t>`, which the game refuses: a dead slot.

`catalog.lua:180-189` walks `windower.ffxi.get_abilities().job_abilities` and
turns every id into one flat `Job Abilities` entry. It has no concept of a
parent, so the parent is offered and the children are not.

This was not ported. Upstream handles it (`action_binder.lua:1304-1314`,
`get_stratagems` at 2023) by skipping nine categories out of the flat list and
supplying each family's children behind a dedicated selector.

## The families

Read off `Windower/Resources/resources_data/job_abilities.lua` (fetched
2026-09-07), so these ids and type names are the resource's own, not recalled:

| Parent | id | prefix | Children (`type`) | n |
| --- | --- | --- | --- | --- |
| Stratagems | 223 | `/jobability` | `Scholar` | 16 |
| Phantom Roll | 97 | `/jobability` | `CorsairRoll` | 31 |
| Quick Draw | 124 | `/jobability` | `CorsairShot` | 8 |
| Rune Enchantment | 357 | `/jobability` | `Rune` | 8 |
| Ward | 379 | `/jobability` | `Ward` | 5 |
| Effusion | 380 | `/jobability` | `Effusion` | 4 |
| Blood Pact: Rage | 91 | `/pet` | `BloodPactRage` | 91 |
| Blood Pact: Ward | 172 | `/pet` | `BloodPactWard` | 47 |
| Ready | 251 | `/pet` | `Monster` | 120 |
| Waltzes | 183 | `/jobability` | `Waltz` | 8 |
| Sambas | 182 | `/jobability` | `Samba` | 6 |
| Jigs | 198 | `/jobability` | `Jig` | 3 |
| Steps | 199 | `/jobability` | `Step` | 4 |
| Flourishes I / II / III | 200 / 213 / 263 | `/jobability` | `Flourish1` / `2` / `3` | 3 each |

Each parent's OWN type is `JobAbility` for the six `/jobability` rows and
`PetCommand` for the three `/pet` ones (`Sic` (72) is `PetCommand` too). That
matters: **no parent's type is any family's child type**, so a parent can never
be collected into its own submenu - which, because a client-listed child beats
the whole-family fallback, would otherwise leave a submenu holding one wrong
row. Read off the resource data 2026-09-07, not recalled.

One entry deliberately NOT treated as a parent: **Sic (72)** is directly
usable - `/pet "Sic" <t>` is a real command, and its moves are the same
`Monster` pool Ready fires. Only Ready gets the submenu. (Kevin, 2026-09-07.)

**The seven DNC rows were missed on the first pass** and added the same day,
caught in review round 3. The plan originally recorded "the DNC families have
no parent entry in the resource at all" and concluded they needed nothing. That
was wrong, and wrong for a specific reason worth keeping: the resource names
them in the **plural** - `Waltzes`, `Sambas`, `Jigs`, `Steps`, `Flourishes I`
- so a search for `Waltz`/`Samba`/`Jig` found the children and no parent. All
seven are `JobAbility`, several share the family recast id the way `Stratagems`
(223) shares 233 (`Jigs` carries Spectral Jig's 218, `Steps` Quickstep's 220),
and `/ja "Waltzes"` is the same dead bind. Upstream skips its `dances` category
for exactly this reason - which is corroboration the first pass read as mere
reorganisation.

## Where children come from - ONE rule, not upstream's three

Upstream is inconsistent, and each shape has a cost:

| Family | Upstream's source | Cost |
| --- | --- | --- |
| Phantom Roll, Quick Draw | the client's list, filtered by category | none - correct |
| Stratagems, Dances, Wards, Effusions, Rune Enchantment | hardcoded id+level tables | transcribed data that goes stale and cannot be verified here |
| Ready, Blood Pact: Rage/Ward | every matching `res.job_abilities` entry, **no job and no level gate** | a WAR sees all 91 blood pacts |

**`res.job_abilities` carries no `levels` table.** Zero occurrences in the whole
file, and no other resource file supplies them - which is *why* upstream
hardcodes levels. It also means `catalog.available()` has never gated an
ability on level and cannot: the guard at `catalog.lua:128-130` (a record with
no `levels` is included) takes every job ability. That is harmless while the
client's list is the source, because that list is already level-filtered by the
client - but it is exactly what breaks the moment we synthesize entries the
client did not list.

The rule for this work, applied identically to all nine families:

> Children are the `res.job_abilities` entries of the family's `type`. A child
> the client's `get_abilities().job_abilities` lists is included. If the client
> lists **none** of a family's children while listing its parent, the whole
> family is offered unfiltered.

Self-configuring: it discovers per family, at runtime, what this client
enumerates, so there is no level table to transcribe and no need to know in
advance which families the client answers for. Upstream's own asymmetry is
evidence the answer differs by family - phantom rolls and quick draw come from
the client, stratagems from a static table - and this rule reproduces the right
behaviour in both cases without our having to say which is which.

**The cost, and it is real:** on a family the client does not enumerate, a
level-10 SCH is offered all sixteen stratagems rather than the two they have.
Binding one produces a slot the game refuses. Accepted, on the rule
`catalog.lua:190-200` already states for weaponskills - ignorance rather than
knowledge, and an empty picker is a worse answer than a long one. It degrades
with level: at 99 the list is exactly right.

**Unverified, and only a live client can say** (`crossbar-in-client.md` row):
whether `get_abilities().job_abilities` returns the sixteen stratagem ids or
only the parent 223. The rule above is correct either way, which is the point
of it, but the *observed* behaviour differs and the answer belongs in the test
plan. Kevin's report - a `Stratagems` entry in the flat list - confirms only
that 223 is returned.

## Record type comes from the resource

`/jobability` -> `ja`, `/pet` -> `pet`. Read off each child's own `prefix`
rather than written down per family, so a family cannot be given the wrong
command word. `pet` already fires as `/pet "<name>" <target>`
(`actions.lua:56`), already resolves recast and icon through
`bar.meta_for` (`bar.lua:233`) and already takes the target step
(`binder.lua:135-143`), so **blood pacts and ready moves need no execution
work at all** - this is a catalog and picker change end to end.

The only hardcoded data in the change is the nine-row parent table above:
parent id -> child type. Everything else is derived.

## The picker: a nested fourth step (Kevin, 2026-09-07)

`Stratagems` stays where it is, in `Job Abilities`, and clicking it opens the
sixteen. That is what Kevin reached for, and it keeps the category column at
its current fifteen - the alternative, a top-level `Stratagems` category
alongside `White Magic`, was considered and rejected.

`binder.lua`'s machine becomes slot -> layer -> catalog -> **submenu** ->
target:

- A catalog entry carries either a `record` (bind it) or `children` (a list of
  entries), never both. `catalog.build()` emits one `children` entry per family
  whose parent the client lists.
- `STEP_SUBMENU` renders with the **same** `paged()` helper and the same entry
  rects as the catalog step, so the two cannot drift - the rule
  `binder.lua:551-553` already states for the catalog and target steps.
- `go_back()` walks `target -> submenu -> catalog -> layer` when the pending
  action was reached through a submenu, and `target -> catalog -> layer` when
  it was not.
- `commit()` still drops to `STEP_LAYER`, unchanged.
- The category column **stays live** during the submenu step; clicking another
  category leaves the submenu and switches category, exactly as on the catalog
  step (Kevin, 2026-09-07). A visible column that ignored clicks is the thing
  `binder.lua` avoids everywhere else.
- The parent's own entry is **removed from the flat `Job Abilities` list**, and
  so is every child the client happens to list there (phantom rolls, quick draw
  shots), or they would appear twice.

## Test plan

TDD, `tdd-workflow`, blind review gate before the PR.

`tests/actionbar/catalog_spec.lua` - new fixtures. Note the existing fixture
gives `job_abilities` a `levels` table, which **the real resource never has**;
the new fixtures must not repeat that, and the discrepancy should be called out
where the old ones stay.

- a family whose children the client lists -> exactly those children
- a family whose children the client does not list, parent listed -> all of them
- a parent the client does not list -> no entry at all, no children
- the parent never appears as a bindable entry
- a child the client lists is not ALSO in the flat `Job Abilities` list
- `prefix` picks the record type: `/pet` children bind as `pet`
- Sic stays a plain bindable ability, and `Pet commands` (55) is dropped with
  no submenu (its children are already bindable one by one)
- the seven plural DNC menus are parents like the rest

`tests/actionbar/binder_spec.lua`:

- clicking a `children` entry goes to `STEP_SUBMENU`, not `STEP_TARGET`
- clicking a child goes to `STEP_TARGET` (all these types take a target)
- back from target returns to the submenu, then the catalog, then the layer
- back from a target reached WITHOUT a submenu still returns to the catalog
- the submenu pages with the same rects the catalog uses
- the X closes from the submenu step
- committing from a submenu writes the child's record and drops to the layer

## Settled, not open

- The category column stays live during the submenu step (above).
- **The long lists ship as they are** (Kevin, 2026-09-07): a SMN is offered all
  91 blood pacts and a BST all 120 ready moves - the longest of the nine, and
  worse than the 91 first quoted - unfiltered by level, avatar or jug pet;
  six pages of wheel. Narrowing blood pacts by the avatar currently out
  would need a pact -> avatar map transcribed by hand and unverifiable here,
  which is the exact risk the runtime-discovery rule above exists to avoid.
  Upstream dumps all 91 too. Revisit only if a live client says it gets in the
  way.

## Status

Implemented 2026-09-07 on `work/claude/edit-binder`, cut from origin/dev at
0539d3f. Plan written after reading the upstream fork
(`khowe085/xivcrossbar@master`) and the Windower resource data. Review gate:
round 1 found a job-change strand, round 2 a second strand on the subjob path,
round 3 the seven missing DNC families - all fixed under TDD.
