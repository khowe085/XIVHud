# Party List — component plan

Status: **implemented 2026-08-06** on `work/claude/party-list` (plan drafted 2026-08-05). Scope: one component directory, `src/components/partylist/`,
registering **three** widgets (`partylist`, `alliancelist1`, `alliancelist2`) on the framework from
[xivhud-implementation.md](xivhud-implementation.md). Depends on framework M1 (render loop)
and M2 (layout mode) — both landed in PR #1 — plus **one new framework touchpoint**:
`incoming chunk` forwarding (see Framework touchpoints).

## Goal

The FFXIV **party list** for FFXI: the main party (6 rows) and both alliance parties, each
independently positioned. The target is **XIVParty 2.2.0 re-implemented as XIVHud
components**, not a reduced version of it.

Decisions (2026-08-05, Kevin):

- **Full XIVParty parity** is the goal, minus mouse targeting (backlogged).
- **Reuse XIVParty's `xiv` theme art** — `assets/xiv/*`, `assets/jobIcons/*`,
  `assets/buffIcons/*` (BSD 3-clause © 2024 Tylas; notice must ship with them).
- **Hardcode the `xiv` layout now**, keeping the geometry in one table shaped so a
  file loader can replace it. XML/Lua layout files and the `ffxi` theme go to the backlog.
- **Three registered components sharing one row module** (rather than one component
  owning three lists, which would need framework multi-instance support).
- **Tweak — buff icons must not overflow the row**: cap at **10**, laid out **2 rows × 5**,
  both rows left-aligned (no `offsetByRow`-style indent on the second).
- **Tweak — commands to change buff icon priority**, instead of hand-editing a source file.
- **No bar glow — performance over parity.** Use parambar's easing, not XIVParty's
  lerp-plus-animated-glow. Saves 3 prims per bar (~126 across a full alliance).
- **Arial everywhere**; XIVParty's `Grammara` for the numeric values is dropped, so nothing
  depends on an FFXI-supplied font resolving.
- **Ship all 640 buff icons**, not just the ids the default order references.
- Component keys: **`partylist`, `alliancelist1`, `alliancelist2`**.

## XIVParty reference facts (verified 2026-08-05 against Tylas11/XIVParty HEAD, v2.2.0)

### Data flow

- `windower.ffxi.get_party()` returns keys `p0..p5`, `a10..a15`, `a20..a25`; each member is
  `{ name, hp, hpp, mp, mpp, tp, zone, mob }`, and **`mob` is absent when the member is not
  in the zone**. Also `party1_leader`/`party2_leader`/`party3_leader`, `party*_count`,
  `alliance_leader`, `alliance_count`. (Verified against the Windower FFXI-Functions wiki,
  2026-08-05, and against XIVParty's use of it in `model:updatePlayers`.)
- **XIVParty polls everything** — one `prerender` gate at `updateIntervalMsec` (default
  30 ms, `defaults.lua:46`) in front of *both* `model:updatePlayers()` and `view:update()`,
  so the poll rate and the bar animation rate are the same number. It parses `0x0DD`/`0x0DF`
  for job info only and **discards the HP/MP/TP those packets carry**. This is a choice, not
  a constraint — see the push/poll split under Deviations.
- `tpp = math.min(member.tp / 10, 100)` — identical to parambar's formula.
- `mob.distance` is **squared**; XIVParty applies `:sqrt()`. `castRange = 20.79`,
  `targetRange = 50` (`const.lua`).
- Out-of-zone is `member.zone ~= windower.ffxi.get_info().zone`. Out-of-zone rows show the
  zone name and blank/`?` everything else.
- The **main player's** buffs and job come from `get_player()` (`buffs`, `main_job_id`,
  `main_job_level`, `sub_job_id`, `sub_job_level`) — they are *not* in the party packets.
- Trusts: `member.mob.is_npc`; job/subjob resolved from a name + model-id table
  (`jobs:getTrustInfo`), level copied from the party leader, sub level
  `max(1, floor(leaderLvl / 2))`.

### Packets (`incoming chunk`)

| ID | Purpose | Fields used |
| --- | --- | --- |
| `0xC8` | alliance update | `ID i` / `Flags i` for i = 1..18; flag bit **4** = party leader, **8** = alliance leader, **16** = quartermaster |
| `0xDD` | party member update | `ID`, `Index`, `Name`, `Zone`, jobs — **and `HP`, `MP`, `TP`, `HP%`, `MP%`** |
| `0xDF` | char update | `ID`, `Index`, jobs — **and `HP`, `MP`, `TP`, `HPP`, `MPP`** |
| `0x076` | party buffs | 5 × 48-byte blocks from offset 5 |
| `0x0B` | zoning start (also fires on logout) | — |
| `0x0A` | zone-in complete (also on login) | — |

`0x076` layout, per block `k = 0..4` (XIVParty credits Kenshi/PartyBuffs and Byrth/GearSwap):
player id = `original:unpack('I', k*48+5)`; buff `i` (1..32) =
`byte(k*48+5+16+i-1) + 256 * (floor(byte(k*48+5+8+floor((i-1)/4)) / 4^((i-1)%4)) % 4)`;
`255` means empty. **The main player's own buffs are not in this packet** — and neither are
alliance members', which is why the alliance layout has no buff icons.

`0xDD`/`0xDF` job fields can be non-zero garbage when the member is out of zone, and are
always non-zero when the character has no subjob; XIVParty drops the update unless
`mJobLvl > 0`. The vitals in both packets are verified against Windower's own
`libs/packets/fields.lua@dev` (`incoming[0x0DD]`, `incoming[0x0DF]`), read 2026-08-06.

**There is no party event of any kind.** The Windower Events list documents
`hp/mp/tp/hpp/mpp change` — which fire for the **local player only** (~90%; they are what
already feeds parambar, and no per-member variant is documented) — and nothing for party
membership, roster order, or member state. Anything about *who is in the party* can only
come from polling `get_party()`.

### Geometry — main list (`layouts/xiv.xml`)

- List: `columnWidth 410`, `columns 1`, `rowHeight 46`, `rows 6`. Background is
  BgTop/BgMid/BgBottom (377 wide; 21 / 12 / 21 tall) at `0,-21`, mid stretched to the row count.
- Row, HP/MP/TP bar groups at `19,-7` / `150,-7` / `281,-7`. Each bar group:
  `imgBg` 128×64, `imgBar` 102×64 at `13,0`, `imgFg` 128×64, `imgGlow` 6×64 at `13,0`,
  two `imgGlowSides` 2×64 at `11,0`; value text right-aligned at `120,35`, Grammara 11,
  stroke `#062D54C8` width 2.
- `txtName` `95,1` Arial 15 (`maxChars 17`); `txtZone` `292,1` Arial 13;
  `txtJob` `30,0` Arial 8; `txtSubJob` `39,9` Arial 8.
- `jobIcon` at `-11,-2`: bg / gradient / icon / frame 36×36, highlight 62×62 at `-13,-13`.
- `leader` at `-24,-8`: party / alliance-leader / quartermaster icons 24×24 stacked at y 0/12/24.
- `range` at `30,28.5`: near + far icons 14×12, `txtDistance` Grammara 6.
- `buffIcons` at `293,0`: 20×20, spacing `0,1`, `numIconsByRow 19,13`, `offsetByRow 0,6`,
  left-aligned. **This is the overflow**: 19 icons × 20 px from x = 293 reaches x = 673 on a
  410-wide row.
- `hover` / `cursor` 390×60 at `20,-8`.

### Geometry — alliance list (`layouts/xiv_alliance.xml`)

A genuinely different, smaller row, not a scaled copy: `columnWidth 105`, `columns 3`,
`rowHeight 42`, `rows 2` (a 3×2 grid of 6). The only elements present are **hp, mp, jobIcon,
leader, txtName, txtZone, hover, cursor** — no TP bar, no range, no buff icons, no job text.
Uses the `AllyBar*` textures: `AllyBarBG`/`AllyBarFG` 64×64, `AllyBarHP` 56×64 at `4,0`,
`AllyBarGlowHP` 8×64, `AllyBarGlowSidesHP` 3×64.

### Rendering behaviour

- **Bar animation** (`uiBar:update`): `exact = exact + (target - exact) * animSpeed` with
  `animSpeed = 0.1`, clamped 0..1, rounded to 3 dp. When the glow is enabled and the bar is
  not dimmed the **bar snaps to the target instantly and the glow animates the difference**;
  when dimmed or glow-disabled the bar itself animates. Glow width =
  `barWidth * |target - current|`, positioned at the smaller of the two, capped either side
  by `imgGlowSides` (the right one flipped by negative width). This is a different feel from
  parambar's integer `ceil` easing.
- **HP colour bands** (text *and* bar tint): `< 25` red `#FC8182`, `< 50` orange `#F8BA80`,
  `< 75` yellow `#F3F37C`, strict `<` on the percent. **TP full** at `tp >= 1000` → `#50B4FA`.
  MP has no bands.
- **Distance dimming**: bar opacity 1.0 in casting range, 0.5 in targeting range, 0.25 beyond.
- **Cursor**: opacity 1 when the member is the target, 0.5 when subtarget, 0 otherwise.
- **Job icon**: role colour on `imgBg` — tanks PLD/PUP/RUN `#364597`, healers WHM/RDM/SCH
  `#3B6529`, support BRD/COR/GEO `#DAB200`, everything else (incl. MON) dd `#663535`;
  `special #FF9700` is defined but unused by `jobs.roles`. Highlight shows only when targeted.
- **List sizing**: `rowCount = floor((count-1)/columns) + 1`, or all rows when
  `showEmptyRows`; `contentHeight = rowCount*rowHeight + (rowCount-1)*itemSpacing`;
  `alignBottom` shifts the whole list up by `rowCount * rowHeight`.
- **Buff ordering**: `bufforder.lua` is a hand-ordered list of ~626 buff entries collapsed at
  load into `id -> rank`; unranked buffs sort last. Filtering is a single id list used as
  either a blacklist or a whitelist. Sort runs on the filtered list.
- Rows are created and disposed as membership changes (`uiPartyList:update`), not preallocated.

### Assets and licence

640 buff icon PNGs totalling ~1.1 MB; 22 job icons plus bg/frame/gradient/highlight;
~20 `xiv` theme textures. XIVParty's **code** is BSD 3-clause © 2024 Tylas via per-file
headers (there is no repo `LICENSE` file); the **assets carry no separate licence**, so the
code licence is our basis — the same reasoning already applied to XIVBar's art in parambar.
`bufforder.lua` is derived from Windower's generated `resources/buffs.lua` and carries the
Windower BSD 3-clause notice (© 2013-2020 Windower) in addition.

### Rough edges to fix, not port (~90% — read from source, not reproduced in a client)

1. **A `'mouse'` handler per list item.** `uiListItem:init` registers one, and each
   `uiPartyList` registers another — 21 live handlers with a full alliance, running on every
   mouse move during normal play. Our framework registers mouse **only** in layout mode.
2. `player:update` calls `windower.ffxi.get_player()` **once per member per frame** (18×)
   purely to compare the name against the main player's.
3. `uiListItem:updateZone` indexes `res.zones[zone]` unguarded — an unrecognised zone id is a
   hard error inside the render loop.
4. `model:getPlayer` linear-scans `allPlayers` for every member every frame, and that list is
   only cleared on zoning, so it grows for the length of a session.
5. `uiPartyList` reads `ui_x_res`/`ui_y_res` into file-scope locals at load — a resolution
   change needs a reload.
6. Buff icons overflow the row (see geometry above) — the reason for Kevin's tweak.

## Deviations from XIVParty (decided 2026-08-05)

- **Position, scale, visibility and enable are framework-owned.** No `//xp setup`, no
  per-party `pos`/`scale`/out-of-bounds fixups, no `hideCutscene` and no keyboard hide-key in
  the component: `//xh layout` drags/scales/toggles, state lives in layout slots, and
  `lib/visibility` already covers cutscene (`event`), `zoning` and `logged_out`.
  `hideSolo` has no framework equivalent and stays a component setting.
- **Config is our per-component `.lua` handle**, not XML settings plus XML layout files.
  Geometry lives in `layout.lua` as a plain table (main + alliance variants); a loader that
  reads it from a file is a backlog item, and the table is shaped for that.
- **Push where a push path exists; poll at 200 ms for the rest** (Kevin, 2026-08-06).
  XIVParty polls everything at 30 ms; we invert that. The split:

  | Data | Source | Rate |
  | --- | --- | --- |
  | Local player vitals | `hp/hpp/mp/mpp/tp change` events (already wired for parambar) | push |
  | Party member vitals | `0x0DD` / `0x0DF` | push |
  | Jobs / subjobs | `0x0DD` / `0x0DF` | push |
  | Leader / alliance-leader / quartermaster | `0x0C8` | push |
  | Buffs | `0x076` | push — **no poll path exists at all** (`get_party()` returns no buffs; `get_player().buffs` covers only you) |
  | Current zone id | `zone change` event | push |
  | **Roster** — who occupies which slot, joins, leaves | `get_party()` | **200 ms poll** |
  | **Distance**, trust flag, mob presence | `get_party()` member `mob` | **200 ms poll** |
  | **Target / subtarget** | `get_mob_by_target('t'/'st'/…)` | **every frame** (see below) |

  Two caveats found while specifying this, both worth honouring rather than papering over:

  1. **The poll call is indivisible.** `get_party()` returns whole member tables — you
     cannot ask it for the roster without also receiving `hp/hpp/mp/mpp/tp`. So "only poll
     what can't be pushed" reduces to "don't build a *second* poll for anything push
     covers". The vitals that arrive free in the roster poll are still **used, as a
     reconciliation pass**: the poll is authoritative (it reads the client's own state,
     which is downstream of the very packets we parse) and push is a latency accelerator on
     top. Ignoring them would cost nothing to skip but would reintroduce two failure modes —
     a member who joined before the addon loaded shows a blank bar until they take damage,
     and a dropped or addon-blocked packet leaves a bar stale forever instead of for one
     tick. Same reconciliation principle parambar already applies to its two vital streams.
  2. **Target/subtarget must not ride the 200 ms poll.** It drives the row cursor, so
     throttling it puts up to 200 ms of visible lag between pressing a target key and the
     cursor moving — 6× worse than XIVParty. `get_mob_by_target` is a single cheap lookup,
     not 18 table allocations, so it stays on the frame loop while `get_party()` throttles.

  The poll interval is a setting (`poll_interval_ms`, default 200), so it can be tuned
  in-client without a rebuild. Confidence that 200 ms is visually fine for roster changes,
  distance and range indicators: ~85% — the bars ease off logic state rather than poll
  freshness, so poll rate and animation rate are independent for us (they are the *same*
  number in XIVParty). Only a client run settles how a 5 Hz numeric distance readout feels.
- **The easing constant is ours, not XIVParty's.** Because we decouple the poll from the
  animation, XIVParty's `animSpeed = 0.1` would converge roughly twice as fast on our
  per-frame loop as on its 33 Hz tick. Moot in practice since we dropped the glow and use
  parambar's integer `ceil` easing, but it means the feel must be tuned in-client, not
  copied from a constant.
- **No bar glow; parambar's easing instead** (Kevin, 2026-08-05 — performance over parity).
  XIVParty snaps the bar to its target and animates a glow across the difference, which
  needs `imgGlow` + two `imgGlowSides` per bar. We drop all three and ease the bar itself
  with parambar's integer `ceil` steps, so the two XIVHud components share one easing
  implementation and one feel. The glow is a visible part of the XIVParty look; this is a
  deliberate cosmetic loss, and it takes ~126 prims out of a full-alliance render.
- **Arial for every text**, dropping `Grammara` for the numeric values. Removes the risk
  that an FFXI-supplied font fails to resolve, at the cost of the FFXIV-ish numerals.
- **All 640 buff icons ship**, so a buff never renders as a blank slot just because it was
  outside the default priority order.
- **Both buff rows left-aligned**, unlike XIVParty's `offsetByRow` indent on row 2.
- **Three registered components out of one directory.** `partylist.lua` exports
  `new(ctx)` and the entry point registers it three times under `partylist`,
  `alliancelist1`, `alliancelist2`, each getting its own config file, layout slots, drag box and
  `//xh show|hide|reset` for free. *Convention wrinkle*: the framework plan says a
  component's code lives in `components/<component>/` matching its name. Three directories
  would instead force a cross-component `require`, which the convention forbids outright —
  so one directory backing three names is the smaller deviation. Worth a line in CLAUDE.md
  when this lands.
- **Buff icons capped at 10, in 2 rows of 5** (Kevin). At 20 px + 0 spacing that is 100 px
  wide from x = 293 → ends at 393, inside the 410 row. Row height grows by one icon row
  (20 + 1 spacing); the second row keeps `offsetByRow`-style indenting if it looks better
  in-client. XIVParty's `numIconsByRow`/`offsetByRow` machinery is kept as the mechanism —
  only the numbers change — so the cap is one config value, not a rewrite.
- **Buff priority is user-editable via commands** rather than by editing `bufforder.lua`.
  The shipped order is ported as the default; the user's changes persist as a sparse
  override so a future change to the default order does not stomp them.
- **Mouse targeting → backlog** (Kevin). This keeps the framework's "no mouse handler
  outside layout mode" guarantee, which is also fix #1 above.
- **Buff settings live only in `partylist`'s config.** `0x076` carries main-party members
  only, and the alliance layout has no buff icons (verified) — so there is nothing for
  `alliancelist1`/`alliancelist2` to configure.
- **`swapSingleAlliance` dropped.** It exists to move a lone alliance party into the second
  list's screen position; with independently draggable components you just put
  `alliancelist1` where you want it.
- **Kept as-is**: the 3-column alliance row, `alignBottom`, `showEmptyRows`, `itemSpacing`,
  range indicator + numeric mode, the HP bands and full-TP colour, distance dimming, target
  cursor, job icon role colours, trust job inference, out-of-zone handling.

## Architecture

```
src/components/partylist/
  partylist.lua    -- widget factory new(ctx): owns prims, implements the contract
  layout.lua        -- hardcoded xiv geometry, main + alliance variants (data only)
  logic.lua         -- pure: party model, row render plans, easing, bands, buff ordering,
                    --       command parsing. No prims, no Windower.
  packets.lua       -- pure parsers for 0xC8 / 0xDD / 0xDF / 0x076 (bytes in, tables out)
  buff_order.lua    -- default buff priority ported from bufforder.lua: id -> rank
  jobs.lua          -- job -> role map, trust name/model -> job table
  defaults.lua      -- config defaults (per list variant)
  assets/
    xiv/  jobIcons/  buffIcons/  LICENSE.txt
tests/components/
  partylist_logic_spec.lua  partylist_packets_spec.lua  partylist_spec.lua
```

`logic.lua` is the testable core, following parambar's shape: it takes a `get_party()`-style
table plus accumulated packet data and returns an ordered list of **row render plans**
(`{ name, hp = {width, text, color, alpha}, mp = …, tp = …, job, sub_job, zone_text,
job_icon, leader_flags, range, buffs = {ids}, hidden }`). `partylist.lua` owns prims and
applies plans, touching only rows/fields the plan marks dirty.

### Framework touchpoints (new work, not in M0–M3)

1. **`incoming chunk` forwarding.** The entry point must register
   `windower.register_event('incoming chunk', …)` and dispatch `(id, original)` to
   components — the first use of the framework plan's "packet pushes added later
   per-widget" clause. `packets = require('packets')` for `0xC8`/`0xDD`/`0xDF`; `0x076` is
   parsed by hand from the raw string. `packets` is already whitelisted in `.luacheckrc`.
2. **New `ctx` deps**: `get_party`, `get_mob_by_target` (for target/subtarget), `get_info`
   (current zone id), a resources accessor for `res.zones` / `res.jobs` / `res.buffs`, and
   a clock (`ctx.now`, which core already builds from `os.clock`) for the 200 ms poll gate.
3. **Three instances of one factory** — confirm `lib/registry` accepts that (it keys by
   `component.name`, so it should; verify in PL1).

### Prim budget

Counted from the geometry above, with the glow dropped (each bar is `imgBg` + `imgBar` +
`imgFg` + its value text = **4**, not 7):

| | per row | × 6 rows |
| --- | --- | --- |
| main row — 3 bars (12), job icon (5), 4 texts, leader (3), range (3), buffs (10), hover, cursor | **39** | 234 |
| alliance row — 2 bars (8), job icon (5), 2 texts, leader (3), hover, cursor | **20** | 120 each |

**~474 prims** with a full alliance, against ~600 had we kept the glow, and ~1260 for stock
XIVParty. Still two orders of magnitude past parambar's 7, and the main performance risk of
this component.

There is **no documented cap** on text/image objects — `texts.new`/`images.new` generate a
unique name per object (`<addon>_gensym_<ptr>_<rand>`) and hand it to
`windower.text.create` / `windower.prim.create`, and neither Lua library counts or limits
them (verified 2026-08-05 against `Windower/Lua@dev` `libs/texts.lua`, `libs/images.lua`).
Whatever limit exists is in the closed C++ core and is undocumented; the cost is a
per-frame draw and the per-object bookkeeping, i.e. a gradient, not a cliff (~80% — the
absence of a Lua-side limit is verified, the absence of a core-side one is inferred from
XIVParty running ~1260 in production).

Two mitigations, both already XIVParty practice: build a row's prims only when the row is
occupied and destroy them when it empties, and apply only the fields a plan marks dirty.
If PL2 shows a frame-time problem, the next lever is dropping `imgFg` and folding the frame
into the background texture (−6 per main row).

## Settings (defaults, in `data/<Character>/{partylist,alliancelist1,alliancelist2}.lua`)

Shared by all three (alliance variants default `enabled`-off in their slot):

```lua
{
  poll_interval_ms = 200,    -- get_party() roster/distance poll; target polls per frame
  item_spacing = 0,          -- (party.itemSpacing) px between rows
  align_bottom = false,      -- (party.alignBottom) grow the list upward
  show_empty_rows = false,   -- (party.showEmptyRows)
  hide_solo = false,         -- (hideSolo) main list only
  range = { numeric = false, near = 0, far = 0 },  -- (rangeNumeric/rangeIndicator/…)
  slots = { default = { pos = …, scale = 1, visible = true } },  -- framework-owned
}
```

`partylist` only:

```lua
  buffs = {
    max_icons = 12,          -- the tweak; 2 rows x 6 at 16px, left-aligned, from layout.lua
    filter_mode = 'blacklist',
    filters = {},            -- buff ids
    priority = {},           -- sparse user overrides on top of buff_order.lua
  },
```

Colours and fonts stay in `layout.lua` for now (the layout-file backlog item is what makes
them user-editable) — every text is Arial, at XIVParty's sizes. Scale is framework-owned; XIVParty's resolution-based autoscale
(`round(resY / 1440, 2)`) is worth reproducing as the **default slot scale** so a 1080p user
gets a sane first render rather than a 1440p-sized list.

## Commands

Via the framework's `handle_command(args)` passthrough; parsing is pure in `logic.lua`.
Framework conventions apply: case-insensitive verbs, unknown input → one-line hint.

```
//xh partylist                          -- current settings summary
//xh partylist spacing <px>
//xh partylist align top|bottom
//xh partylist emptyrows on|off
//xh partylist hidesolo on|off
//xh partylist range num|icons          -- numeric vs indicator mode
//xh partylist range <near> <far>       -- indicator distances, 0/off to disable
```

Same set on `alliancelist1` / `alliancelist2`, minus `hidesolo`.

Buff priority (design proposal, 2026-08-05 — the tweak Kevin asked for):

```
//xh partylist buff                     -- the icon slots currently shown, in order
//xh partylist buff list [page]         -- the WHOLE priority order, 20 per page
//xh partylist buff find <text>         -- search all buffs by name -> rank + id
//xh partylist buff active [<member>]   -- buffs live on a party member right now
//xh partylist buff top <id|name>       -- move to rank 1
//xh partylist buff up|down <id|name>   -- move one rank
//xh partylist buff rank <id|name> <n>  -- move to rank n
//xh partylist buff reset               -- back to the shipped order
//xh partylist buff filter add|remove|clear|list [<id|name>]
//xh partylist buff filter mode blacklist|whitelist
```

**Discovery is the point** (Kevin, 2026-08-05): only 10 icons render, so every command that
*shows* you buffs must reach past those 10 — otherwise a buff you want promoted is
invisible and unpromotable.

- `buff list` walks the **entire** order, not a top-N slice: ~626 ranked ids plus every
  `res.buffs` id that has no rank (those sort last, listed after the ranked ones under an
  "unranked" heading). Paged 20 per line-group with a `page 3/34` footer, because dumping
  ~700 lines into FFXI's chat log scrolls itself off screen. `buff list <page>` jumps.
- `buff find <text>` is the fast path for exactly Kevin's case — case-insensitive substring
  over `res.buffs` names, printing `rank · id · name` per hit so the follow-up is a single
  `buff top <name>`. Capped at 20 hits with a "refine the search" line.
- `buff active [<member>]` is XIVParty's `//xp buffs <name>` — what is on this player *now*,
  with ids, including the ones past the icon cut. This is how you identify a buff you
  just saw rather than one you can name. Defaults to yourself; `?` for members whose buffs
  we have no packet for (alliance members, per `0x076`'s main-party-only scope).
- The first twelve entries of the order are marked in `buff list`/`buff find` output so the cut
  line is visible without counting.

Names resolve case-insensitively against `res.buffs`; unknown or ambiguous → an error line
listing candidates, no write. Every accepted change persists immediately and re-sorts the
displayed buffs on the next frame.

## Testing strategy

All against the pure modules, no client:

- **`packets.lua`**: `0x076` bit-packing reconstructed from a handcrafted byte string
  (including the 4-buffs-per-high-byte packing and the `255` empty marker); `0xC8` flag
  decoding for all three bits; `0xDD`/`0xDF` job extraction, incl. the `mJobLvl == 0` drop.
- **Push/poll reconciliation**: a pushed vital applied between polls shows immediately; the
  next poll's value wins when they disagree; a member present in the roster with no packet
  ever received still renders correct vitals from the poll alone (the seeding case); a
  member whose packets stop renders the poll value rather than freezing (the dropped-packet
  case); the poll clock is injected, so a spec drives it without real time passing.
- **`logic.lua`**: party-table → ordered rows for full/partial/empty parties and all three
  party indices; out-of-zone members (no `mob`, `?` values, hidden elements); trust job
  inference and leader-derived level; `tpp` incl. the 3000 cap; HP band boundaries
  24/25, 49/50, 74/75 (strict `<`) and full-TP at 999/1000/1001; distance dimming
  boundaries at `castRange`/`targetRange` (and `distance` arriving squared);
  bar easing — parambar's growth/shrink steps, convergence from 0→full and full→0, clamps
  at both ends, and the dirty flag clearing exactly on convergence (parambar's bug ①
  regression, since the implementation is shared);
  `rowCount`/`contentHeight`/`alignBottom` math;
  buff filter in both modes; buff ordering with sparse overrides, ties, and unranked ids;
  the 10-icon cut and the 2×5 left-aligned placement; preview/sample data in and live data
  restored.
- **Command parser**: every verb happy-path, buff name resolution (exact, case-insensitive,
  ambiguous, unknown), rank bounds, `range` argument forms, unknown verb → hint.
  For the discovery verbs specifically: `buff list` paging boundaries (first page, last
  partial page, page 0 / past the end), that the ranked + unranked sections together cover
  every `res.buffs` id exactly once, `buff find` hit capping and zero-hit wording, and
  `buff active` for a member with no buff data (alliance) versus a full 32-buff member.
- **Widget level** (fake prim recorder in `tests/support/fakes.lua`): group move re-derives
  every row's offsets; rows created on join and destroyed on leave; `destroy` disposes every
  prim; a plan with no dirty fields issues no prim calls.

In-client smoke (Windows/Windower, per milestone): rows track a real party; zone a member
out and back; a full 18-person alliance across three lists; drag/scale each list in
`//xh layout` and confirm persistence; cutscene hide; `//lua reload xivhud` leaves nothing
on screen.

## Milestones

- **PL0 — pure logic and packet parsers.** `packets.lua`, `logic.lua`, `buff_order.lua`,
  `jobs.lua` + full specs. No framework dependency; can start immediately.
  *Acceptance*: busted green, luacheck clean, `stylua --check` clean; the `0x076` parser
  reproduces a handcrafted packet; buff ordering is stable and deterministic.
- **PL1 — framework touchpoints.** `incoming chunk` forwarding, the new `ctx` deps,
  three-instance registration. *Acceptance*: in-client, a stub component logs parsed packets
  for all four ids, and `//xh list` shows `partylist`, `alliancelist1`, `alliancelist2`.
- **PL2 — the main list renders.** Assets copied in with `LICENSE.txt`, `layout.lua`
  geometry, rows built/destroyed with membership; bars + numbers + name + job/subjob text +
  job icon + leader markers + zone text + target cursor.
  *Acceptance*: 6 rows track a real party in-client; out-of-zone member renders correctly;
  unload leaves no prims.
- **PL3 — buff icons and range.** 640 icons packaged; the 2×5 grid with the 10-icon cap;
  filter + priority applied; range indicators and numeric mode.
  *Acceptance*: buffs appear/disappear with the packet stream, never exceed 10, and never
  extend past the row's 410 px.
- **PL4 — alliance lists.** The alliance geometry variant; `alliancelist1`/`alliancelist2`
  registered, independently draggable and enable-able.
  *Acceptance*: 18 members across three lists in-client, each list positioned separately and
  surviving `//lua reload xivhud`.
- **PL5 — commands and polish.** The `buff` command set, the per-list settings commands,
  `hide_solo`. *Acceptance*: every command exercised in-client, all writes persisted.
- **Backlog** (2026-08-05, order TBD):
  - **MP colour bands** — mirror the HP `<75/<50/<25` bands onto MP, as parambar already
    does, so the two components agree. Deferred rather than dropped (Kevin, 2026-08-05);
    XIVParty colours HP only, so shipping without it is the parity-correct starting point.
  - Mouse targeting (click a row to `/ta`) — needs a framework-level mouse capability
    outside layout mode.
  - Layout files + the `ffxi` theme, making colours/fonts/geometry user-editable.
  - Buff tooltips.

## Implementation notes (2026-08-06)

Everything below shipped except the backlog. 594 specs green, `luacheck` and
`stylua --check` clean. What changed against the plan while building it:

- **The widget's origin is the top-left of the art, not of the row grid.** The row
  overhangs its column rectangle -- the leader stack sits 24px left of it, the frame's
  caps 21px above and below -- so `layout.lua` carries a `margin` per variant and the
  widget places everything inside it. Without that the framework clamps the list
  against a box the art escapes, and at the screen edge the leader marker and the top
  cap are drawn at negative coordinates and vanish silently. XIVParty has that bug;
  its own drag box is the row rectangle alone.
- **Prim budget, measured**: 38 per main row (228 + 3 background = 231) and 17 per
  alliance row (105 each), **441 for a full alliance** against the plan's ~474. The
  difference is the `hover` prim, dropped with mouse targeting, and the alliance bars
  having no value text.
- **`align_bottom` is a full-height box, not a shifted origin.** XIVParty shifts the
  whole list up by its content height. That cannot work here: the widget contract has
  `get_bounds` report the origin `set_pos` was given, so a shifted origin would have
  core clamp against a box the list is not in and walk it off screen a step a frame.
  The box stays six rows tall and the rows pack to the bottom of it -- same look.
- **The row-height increase for the second buff row was not needed.** Two rows of
  20px icons at `293,0` with 1px spacing end at y=41 inside the 46px row.
- **Two framework touchpoints, not one.** `incoming chunk` forwarding as planned, plus
  `handle_command` may now answer with a **list of lines** -- `buff list` walks 621
  entries and FFXI's chat does not wrap on `\n`.
- **Your own vitals are pushed from the change events**, the stream parambar already
  reads -- no party packet carries the player. Poll-overruled like any other push.
- **TP is not pushed from packets.** Windower's field definition tags `0x0DD`/`0x0DF`
  TP with its `percent` formatter while `get_party()` reports TP on a 0..3000 scale,
  and nothing available here settles which the packet carries. Pushing it on the wrong
  scale would fight the poll five times a second, so TP comes from the 200ms poll
  alone. HP and MP are unambiguous and are pushed. **Worth one in-client check.**
- **`res`/`packets` are the party list's dependency, not the addon's.** They are
  required outside the `step` chain, because a step failure skips everything after it
  -- a broken resources install would otherwise cost the framework, parambar and every
  handler. If they fail, the three party lists are not registered and `//xh` says why.
- `special` is not an unused role after all: the trust table gives it to Darrcuiln,
  Monberaux, Selh'teus and Excenmille (S). The plan's reference note was wrong.
- Prims are built in the layout's `z_order` because Windower's libraries expose no
  depth control -- creation order is all there is. **Which way round the client
  actually draws them is unverified**; if the cursor turns out to be under the row art,
  reverse the build order in `new_row`, not the layout.

- **Buff ids above 639 draw a blank slot.** `assets/buffIcons/` covers 0-639 and the
  largest id in Windower's buff resource today is 635, so nothing is missing now; a
  future game update that adds one would consume an icon slot and draw nothing, since a
  bad texture path fails silently. Inherited from XIVParty.

- **The main row is 66px tall, not XIVParty's 46, and the bars sit 20px lower**
  (Kevin, 2026-08-06, after two rounds of this being wrong in a client).

  Measured against the textures rather than the XML: `BarFG`'s opaque band is box
  y 25..39, so at the shipped bar offset of -7 the frame lands at row y 18..32 and the
  only clear band in a 46px row is y 0..17. Seventeen pixels holds one row of icons,
  not two. XIVParty gets its second row by starting it at x=413, entirely off the row
  body -- which is the overflow this component exists to avoid, and the reason its
  second row never touches the bars.

  So the row is given the space instead. The bars, their value texts and the range
  indicator move down 20px, the row grows to 66, and the two icon rows occupy the band
  that opens above them: 6 x 16px per row, x 293..389, row y 0..16 and 17..33, with the
  bar frame starting at 38. Five pixels of clearance, verified against the art.

  **The art is 16-bit-per-channel PNG.** Two wrong fixes came from a measuring script
  that assumed 8-bit and read the alpha byte at the wrong offset, which put the bar
  band at the bottom of the texture instead of the middle. Anything that measures these
  files must read `IHDR` bit depth first.

- **The frame art is remapped, not stretched** (Kevin, 2026-08-06/07).
  `BgTop`/`BgMid`/`BgBottom` are a horizontal gradient, not a panel: across their 377px
  they fade in over the first 14, hold solid to x=240 -- 64% of the way -- and then take
  137 to fade away. At native width that put the TP bar, x 290..400, almost entirely in
  the falloff: about a sixteenth of it covered.

  Neither obvious fix works. Stretching scales the falloff with everything else, so the
  solid band always ends at 64% of the drawn width: reaching x=410 needs a 644px strip,
  which is still at 86% opacity 50px past the bar and 75% at 90px past -- solid black
  where the list should have ended. Drawing the strip twice, offset, keeps the fade
  short but composites two partly transparent layers, and the overlap reads as a seam.

  So the art is remapped instead, to `xiv/*Wide.png` at 450px: fade-in kept as it is,
  the flat solid section stretched to reach x=410, the tail compressed into 40px. Solid
  across the whole row, gone by 447. The transform is written up in
  `assets/LICENSE.txt`, and the unmodified originals are kept beside it as its basis.
  The alliance frame needs none of this: `AllyBgMid` is flat at a uniform alpha.
- **The row's text shares a bottom edge at row y 29** (Kevin, 2026-08-07). The name
  runs y 9..29, the subjob 18.33..29, the zone name 11.67..29, and the job line keeps
  XIVParty's 9px stack above the subjob. **Text sizes are points, drawn at 96dpi**, so a prim's height
  is 4/3 of its `size` -- 15pt of Arial is 20 pixels, not 15. `layout.lua` exports
  `points_to_pixels` for anything lining text up against art; the first attempt at this
  alignment assumed 1:1 and sat five pixels low.
- **The buff grid hangs from its bottom row** (Kevin, 2026-08-07). Six buffs or fewer
  sit in the lower row, against the bars; the seventh opens a row above rather than
  below, so the block never leaves a row of empty space between itself and the bar.
- **A list with nobody in it draws nothing at all, frame included** (found live,
  2026-08-07): an enabled alliance list you are not currently in showed an empty
  bordered box. `hidden` was only ever true from `hide_solo`, which alliance lists
  don't set, so an occupant count of zero was never checked on its own. XIVParty's
  own rule -- `background:visible(count > 0)` -- now applies to every variant
  regardless of settings; `hide_solo` still additionally covers the solo-with-one-
  member case for the main list. Enabling a list is unaffected: joining an alliance
  still does not auto-enable `alliancelist1`/`alliancelist2`, only whether an already-
  enabled one draws anything.

### Still unverified (needs a live Windower client)

Nothing here has run inside FFXI. The acceptance criteria for PL1-PL5 are all
in-client and none of them have been met yet: `//xh list` showing the three
components, rows tracking a real party, buff icons appearing with the packet stream,
18 members across three lists, drag/scale persistence, and `//lua reload` leaving
nothing on screen. Green locally does not mean it loads.

## Open questions

None as of 2026-08-05 — every decision is recorded inline with its date. Component keys are
`partylist` / `alliancelist1` / `alliancelist2`, unseparated, matching `parambar`
(confirmed by Kevin, 2026-08-05). Note that this planning file keeps its `party-list.md`
name to match the branch and worktree; the component key inside the addon is `partylist`.

## License & attribution

The reused art (`xiv` theme, job icons, buff icons) and any ported constants come from
XIVParty, BSD 3-clause © 2024 Tylas — no separate asset licence exists, so the code licence
is our basis, matching the decision already made for XIVBar's art in parambar.
`assets/LICENSE.txt` reproduces that notice and is packaged with the addon. `buff_order.lua`
additionally carries Windower's BSD 3-clause notice (© 2013-2020 Windower), since XIVParty's
`bufforder.lua` is derived from Windower's generated `resources/buffs.lua`. Our own source
files keep the repo's BSD headers (holder: Azureblood2).

## References

- XIVParty source: https://github.com/Tylas11/XIVParty — facts above verified against `HEAD`
  (v2.2.0) on 2026-08-05, specifically `model.lua`, `player.lua`, `const.lua`, `defaults.lua`,
  `jobs.lua`, `xivparty.lua`, `uiPartyList.lua`, `uiListItem.lua`, `uiStatusBar.lua`,
  `uiBar.lua`, `uiBuffIcons.lua`, `uiJobIcon.lua`, `uiRange.lua`, `bufforder.lua`,
  `layouts/xiv.xml`, `layouts/xiv_alliance.xml`. The session scratchpad mirror is ephemeral —
  re-fetch from the repo.
- Windower FFXI functions (`get_party` return shape verified 2026-08-05):
  https://github.com/Windower/Lua/wiki/FFXI-Functions
- Windower events: https://github.com/Windower/Lua/wiki/Events
- Framework plan: [xivhud-implementation.md](xivhud-implementation.md) — widget contract,
  visibility resolver, settings service, layout slots.
- Parameter Bar plan (the component-plan reference, and the XIVBar asset-licence precedent):
  [parameter-bar.md](parameter-bar.md)
