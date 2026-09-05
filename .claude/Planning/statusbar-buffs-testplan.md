# Status bar + buffs library — in-client test plan

Covers **PR #40** (`lib/buffs`: partylist's buff order and filter engine promoted
into the framework) and **PR #42** (`statusbar`: the player's buffs and debuffs on
three timed bars) in one session.

**They are one stack.** #42's branch already contains all of #40 — `src/lib/buffs.lua`,
`src/lib/buff_order.lua` and the 424 lines taken out of `partylist/logic.lua` — so
testing #42's build tests both. If #40 merges first and #42 later, section B is the
whole of #40 and can be run on its own.

Tick one box per row and write anything odd in the last column. Blank rows are
"not tested". If a row fails, say what you saw rather than what you expected — that
is the part I cannot guess.

**Sections build on each other.** A and B come first (nothing after them means
anything if the addon does not load or the party list has regressed). C–E are the
status bar as shipped; F–H are its settings; I is the packet all three readers now
share; J is the list of things the code is still guessing at, and is the most
valuable section to fill in.

If **A** fails, stop.

---

## A. Load and registration

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| A1 | `//lua load xivhud`, then `//hud` | The command list prints | [x] | [ ] |  |
| A2 | Open `<addon>/load.log` | It ends without an error line, and no step reports a failure | [x] | [ ] |  |
| A3 | Watch the load for texture warnings | No `missing texture` lines | [x] | [ ] |  |
| A4 | `//hud list` | `statusbar` is listed with **three** anchor lines (`bar1`, `bar2`, `bar3`), and the alias `sb` beside the name | [x] | [ ] |  |
| A5 | `//hud list` | `bar1` reads `shown`; `bar2` and `bar3` read `hidden` - two empty strips on screen would read as a bug, so they ship off | [x] | [ ] |  |
| A6 | `//hud list` | Every other component is still listed - `partylist`, `crossbar`, `expbar`, `speedcheck`, `parambar`, `targetbar`, `giltracker`, `equipviewer` | [x] | [ ] |  |
| A7 | `//hud sb` | Answers as `//hud statusbar` does - the alias works wherever the name is taken | [x] | [ ] |  |

## B. Party list regression — the whole of PR #40

The engine moved out of the component; **nothing about it should have changed.**
Every row here is a thing that worked before. Run these on a party with buffs
visible, and ideally against a party list you had already customised.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| B1 | Look at the party list with buffs on several members | Icons draw as they always did - same art, same order, same twelve-icon cap | [x] | [ ] |  |
| B2 | `//hud partylist buff` | Lists the icon slots that actually get drawn | [x] | [ ] |  |
| B3 | `//hud partylist buff list` then `//hud partylist buff list 2` | The shipped priority order, and page 2 of it | [x] | [ ] |  |
| B4 | `//hud partylist buff find haste` | Finds it by name, not just by id | [x] | [ ] |  |
| B5 | `//hud partylist buff active` | The buffs actually up on the party right now - **this verb is partylist's own, not the lib's**, since it reads the roster | [x] | [ ] |  |
| B6 | `//hud partylist buff active <a member's name>` | That member alone | [x] | [ ] |  |
| B7 | `//hud partylist buff top doom` then `buff list` | Doom is first | [x] | [ ] |  |
| B8 | `//hud partylist buff up doom` / `down doom` / `rank doom 3` | Each moves it as named | [x] | [ ] |  |
| B9 | `//hud partylist buff filter add haste` then `filter list` | Haste is listed | [x] | [ ] |  |
| B10 | Look at the party list | Haste is **not** drawn (blacklist is the default mode) | [x] | [ ] |  |
| B11 | `//hud partylist buff filter mode whitelist` | Only Haste is drawn now - the mode inverts | [x] | [ ] |  |
| B12 | `//hud partylist buff filter mode blacklist`, then `filter remove haste`, then `filter clear` | Back to everything drawn, and `filter list` is empty | [x] | [ ] |  |
| B13 | `//hud partylist buff reset` | The shipped order is back | [x] | [ ] |  |
| B14 | `//lua reload`, then `//hud partylist buff list` | Your reordering and filters survived - they persist in `lists.main.buffs` exactly as before | [x] | [ ] |  |
| B15 | `//hud partylist alliance1 buff` | **Refused**, naming that buffs are main-list only - the alliance row draws no icons | [x] | [ ] |  |
| B16 | Open `data/<Character>/<slot>/partylist/config.lua` | The buff settings are still under `lists.main.buffs` - the promotion moved code, not storage | [x] | [ ] |  |

## C. The status bar as it ships

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| C1 | Look at the top-left of the screen with a buff up | One row of buff icons, near the corner but clear of XI's own display | [x] | [ ] |  |
| C2 | Count what it draws | One row, up to 20 icons - `rows 1` is the shipped shape | [x] | [ ] |  |
| C3 | Look under an icon | The remaining time, in XI's own font, under the icon rather than over it | [x] | [ ] |  |
| C4 | `//hud statusbar` | Reports all three bars - each one's filter, rows and on/off - plus the timer switch | [x] | [ ] |  |
| C5 | `//hud statusbar bar1` | That bar alone | [x] | [ ] |  |
| C6 | Cast something with a short buff (Sneak, a Cure's Regen, Protect) | The icon appears **at once**, before any timer does - presence comes from the player read, the timer from a packet that follows | [x] | [ ] |  |
| C7 | Let a buff wear off | The icon goes at once | [x] | [ ] |  |
| C8 | Compare with the party list's own icons for yourself | Same art at the same size - both draw `assets/xiv/buffIcons/` at 32px | [x] | [ ] |  |

## D. Timers

The format is XIV's: bare seconds under a minute, then minutes, then hours.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| D1 | Put up a buff with a few minutes on it (Protect, Shell) | The timer reads `Nm` - e.g. `28m` | [x] | [ ] |  |
| D2 | Watch one count under a minute | It switches to bare seconds - `59`, `58`, ... - with no `m` and no colon | [x] | [ ] |  |
| D3 | Put up something long (a Signet, a food item, a 2-hour Trust) | Reads `Nh` - e.g. `2h` | [x] | [ ] |  |
| D4 | Watch a timer for ten seconds | It ticks down once a second, smoothly, with no flicker and no jumping | [x] | [ ] |  |
| D5 | Watch a buff expire | The number reaches 0 and the icon goes; no negative number is ever drawn | [x] | [ ] |  |
| D6 | Find a buff with **no** duration (a job trait effect, Signet in some zones, a costume) | The icon draws with **no timer under it** at all - not `0`, not a stuck number | [ ] | [ ] | Not tested 2026-09-05 - no timerless buff to hand. Try again while MOUNTED (the Mounted status carries no expiry) or in a costume. |
| D7 | `//hud statusbar timers off` | Every timer disappears; the icons stay | [x] | [ ] |  |
| D8 | `//hud statusbar timers on` | They come back | [x] | [ ] |  |
| D9 | `//hud statusbar bar1 timers off` | **Refused** - `timers` is one switch for all three bars, and a bar word silently dropped would read as a per-bar setting that does not exist | [x] | [ ] |  |
| D10 | Get KO'd (or watch someone else's KO if you would rather not) | The KO icon draws - its buff id is a real `0`, which the packet's own empty-slot marker must not swallow | [ ] | [ ] | Not tested 2026-09-05. |

## E. Reload and login — where the timers come from

The client only ever reports durations in one packet, and after a reload nothing
re-sends it until a buff changes. This section is about that gap.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| E1 | With several timed buffs up, `//lua reload` | Icons come back **immediately** | [x] | [ ] |  |
| E2 | Straight after E1, before doing anything else | The timers are back too, and counting - the attach seeds them from the last packet the client sent | [x] | [ ] |  |
| E3 | If E2 showed no timers: cast anything that changes a buff | The timers appear then. **Note in the last column whether E2 or E3 is what happened** - this is the one behaviour the seed is there for | [ ] | [ ] | Not applicable - E2 passed: the timers came back with the icons on reload, so the seed landed. |
| E4 | Log out to character select and back in | Icons and timers both come up, with no stale buff from the previous character | [ ] | [ ] | Not tested 2026-09-05. |
| E5 | Zone | Icons survive; timers keep counting rather than restarting | [x] | [ ] |  |
| E6 | Compare a timer against the in-game buff display (`Ctrl` + status menu, or a party member's) | They agree to within a second or two | [x] | [ ] |  |

## F. Filters and categories

Four predefined filters. The categories are curated tables in the addon, since the
game's own resources carry no such field — so what lands where is a judgment call
worth checking against your own buffs.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| F1 | `//hud show statusbar bar2` | Bar 2 appears, below bar 1, showing **debuffs only** | [x] | [ ] |  |
| F2 | Take a debuff (Poison, Slow, Weakness) | It draws on bar 2 as well as bar 1 | [x] | [ ] |  |
| F3 | `//hud show statusbar bar3` | Bar 3 appears below bar 2, showing the `other` category | [x] | [ ] |  |
| F4 | Eat food and look at bar 3 | The food icon is there - food is `other`, not an enhancement | [x] | [ ] |  |
| F5 | Look at bar 3 with a Signet / mount / EXP campaign buff up | Each lands on bar 3 | [x] | [ ] |  |
| F6 | `//hud statusbar bar2 filter enhancements` | Bar 2 switches to enhancements; your Protect/Shell move onto it | [x] | [ ] |  |
| F7 | With a movement-speed buff up (Flee, Bolter's Roll, gear speed) | It is an **enhancement**, not `other` - a deliberate call, so say if it reads wrong to you | [x] | [ ] |  |
| F8 | With a stance up (Berserk, Hasso, Sublimation) | Enhancement, same rule | [x] | [ ] |  |
| F9 | With a REMA aftermath or an avatar's favour up | Enhancement, same rule | [x] | [ ] |  |
| F10 | `//hud statusbar bar2 filter all` then `bar2 filter debuffs` | Both assign, and `//hud statusbar` reports the change | [x] | [ ] |  |
| F11 | `//hud statusbar bar1 filter add protect` then look at bar 1 | Protect is no longer drawn **on bar 1** | [x] | [ ] |  |
| F12 | Look at bar 2 | Protect is unaffected there - each bar's filter list is its own | [x] | [ ] |  |
| F13 | `//hud statusbar bar1 filter mode whitelist` | Bar 1 draws Protect and nothing else | [x] | [ ] |  |
| F14 | `//hud statusbar bar1 filter mode blacklist`, `bar1 filter clear` | Back to everything | [x] | [ ] |  |
| F15 | `//hud statusbar buff filter add doom` | **Refused**, and points you at the per-bar verb - a filter belongs to one bar | [x] | [ ] |  |

## G. Shapes, priority and the buff verbs

XI allows up to 32 buffs and no shape holds that many, so the overflow is cut by
priority — the same shipped order the party list uses, and the `buff` verbs reach
past the cap so a buff you cannot see is still one you can promote.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| G1 | `//hud statusbar bar1 rows 2` | Bar 1 becomes two rows of 10 | [x] | [ ] |  |
| G2 | `//hud statusbar bar1 rows 3` | Three rows of 7 (capacity 21) | [x] | [ ] |  |
| G3 | `//hud statusbar bar1 rows 4` | Four rows of 5 | [x] | [ ] |  |
| G4 | `//hud statusbar bar1 rows 5` | **Refused**, naming 1-4 | [x] | [ ] |  |
| G5 | `//hud statusbar bar1 rows 1` | Back to one row of 20 | [x] | [ ] |  |
| G6 | Get more buffs up than the shape holds (a party buff stack, or `rows 1` on a busy character) | The bar fills to capacity and no further; nothing overlaps or draws off the end | [ ] | [ ] | Not tested 2026-09-05 - could not exceed a bar's capacity solo (every shape holds ~20). Needs a full party buff dump or event content. |
| G7 | `//hud statusbar buff` | Lists what each bar draws **and what it cut** - the ones past capacity are marked `(not drawn)` | [ ] | [ ] | Not tested 2026-09-05 - could not exceed a bar's capacity solo (every shape holds ~20). Needs a full party buff dump or event content. |
| G8 | `//hud statusbar buff bar2` | That bar alone | [ ] | [ ] | Not tested 2026-09-05 - could not exceed a bar's capacity solo (every shape holds ~20). Needs a full party buff dump or event content. |
| G9 | Pick something cut in G7 and `//hud statusbar buff top <name>` | It is now drawn | [ ] | [ ] | Not tested 2026-09-05 - could not exceed a bar's capacity solo (every shape holds ~20). Needs a full party buff dump or event content. |
| G10 | `//hud statusbar buff up <name>` / `down <name>` / `rank <name> 5` | Each moves it | [x] | [ ] |  |
| G11 | `//hud statusbar buff list` and `buff find <text>` | The order, and a search of it | [x] | [ ] |  |
| G12 | `//hud statusbar bar1 buff top doom` | **Refused** - the priority order is shared by all three bars, so a bar word here would be a lie | [x] | [ ] |  |
| G13 | After G9, `//hud partylist buff list` | The party list's order is **unchanged** - one engine, two separate stored orders | [x] | [ ] |  |
| G14 | `//hud statusbar buff reset` | The shipped order is back on all three bars | [x] | [ ] |  |

## H. Layout mode, anchors and slots

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| H1 | `//hud layout` with all three bars shown | Each bar has its own highlight box and its own name label | [x] | [ ] |  |
| H2 | Drag bar 2 | Only bar 2 moves | [x] | [ ] |  |
| H3 | Wheel-scale bar 3 | Only bar 3 scales; its icons and timers scale together | [x] | [ ] |  |
| H4 | SHIFT + right-click bar 3 | Bar 3 alone switches off | [x] | [ ] |  |
| H5 | Plain right-click any bar | The **whole component** goes off - all three bars | [x] | [ ] |  |
| H6 | Right-click again | The widget comes back, and each anchor returns to ITS OWN stored state - so a bar switched off with SHIFT stays off | [x] | [ ] | 2026-09-05: the row's original expectation was wrong, not the product. `lib/core.lua` states the bare `show()` and then restates each anchor from its stored flag, so a SHIFT-hidden anchor stays hidden; layout mode force-shows it regardless, and Kevin confirmed its box is still there and SHIFT + right-click brings it back. Kevin prefers this behaviour and it is what the framework already does - no code or doc change needed. |
| H7 | `//hud hide statusbar bar2` then `//hud list` | Bar 2 reads `hidden`, the others `shown` | [x] | [ ] |  |
| H8 | `//hud show statusbar bar2` | Back, and `//hud list` agrees | [x] | [ ] |  |
| H9 | Exit layout mode, `//lua reload` | Every position, scale and on/off survived | [x] | [ ] |  |
| H10 | `//hud slot create test`, move a bar, `//hud slot default` | The default slot's placement is untouched | [x] | [ ] |  |
| H11 | `//hud reset statusbar` | Defaults are back: bar 1 top-left and on, bars 2 and 3 off | [x] | [ ] |  |
| H12 | Zone, and watch during the load screen | The bars hide with everything else and come back after the settle | [x] | [ ] |  |
| H13 | Watch a cutscene | Auto-hide takes the bars down too | [x] | [ ] |  |

## I. The packet three components now share

`0x063` is decoded **once** by the entry point and handed to all three readers. Two
of them worked before this change and must still work.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| I1 | Fight something and watch the crossbar's skillchain indicator | Chains still resolve and display as they did - the engine reads this packet for which of your buffs affect a chain | [x] | [ ] |  |
| I2 | Open a skillchain window and check the per-slot chain marks | Unchanged | [x] | [ ] |  |
| I3 | Gain experience and watch the exp bar | It fills and reports as before | [x] | [ ] |  |
| I4 | At level 99, gain limit points / merits | The exp bar still tracks them (it reads a **different order** of the same packet) | [x] | [ ] |  |
| I5 | With all three on screen at once, take a buff mid-fight | Nothing stutters, and all three keep working | [x] | [ ] |  |

## J. Facts the code is still guessing at

**The most valuable section.** Each of these is a decision made from reading
Windower's sources with no way to confirm it here. A wrong guess is silent.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| J1 | With **few** buffs up (1-2), look at the bar | Exactly that many icons - no phantom cells from the packet's 32 slots. The empty-slot marker is assumed to be `0xFF`/`0xFFFF` | [x] | [ ] |  |
| J2 | With a **timerless** buff up (see D6) | No timer under it, and no timer that counts down for a while and then behaves oddly. A raw `0` and `0xFFFFFFFF` are both read as "no expiry" rather than decoded | [ ] | [ ] | Not tested 2026-09-05 - same blocker as D6, no timerless buff to hand. Try while MOUNTED or in a costume. |
| J3 | Leave the addon running for an hour with a long buff up | Its timer is still right - the packet's 32-bit wrap is resolved against the wall clock rather than a hardcoded count | [ ] | [ ] | Not tested 2026-09-05 - wants an hour of uptime with a long buff up. |
| J4 | Put up a **recently added** buff (anything from the last few years of updates) | It takes a cell and draws its timer, with a blank where the icon would be - the shipped art covers ids 0-639 | [ ] | [ ] | Not tested 2026-09-05 - no recently added buff to hand. |
| J5 | Compare a long timer (`2h`) against the game's own display after ten minutes | Both have moved by ten minutes - no drift | [ ] | [ ] | Not tested 2026-09-05 - paired with J3, wants the same wait. |
| J6 | Anything on any bar that reads as the **wrong category** to you | Note the buff and where you would put it - the category tables are hand-curated and this is the only way to find a miss | [x] | [ ] |  |

## K. Persistence and lifecycle

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| K1 | Set filters, rows and an order on all three bars, then `//lua reload` | Everything survived | [ ] | [ ] |  |
| K2 | Open `data/<Character>/<slot>/statusbar/config.lua` | Per-bar settings under `bars.<bar1\|bar2\|bar3>`, and `priority` / `timers` beside them rather than inside a bar | [ ] | [ ] |  |
| K3 | Change job | The bars carry on; nothing resets | [ ] | [ ] |  |
| K4 | `//hud copy <this character> <another>` then log in as the other | The status bar's settings came across | [ ] | [ ] |  |
| K5 | Play normally for a while with all three bars up | No memory growth, no slowdown in busy content, no error in the console | [ ] | [ ] |  |

## Anything else

Anything that looked wrong, felt wrong, or that you expected to be able to do and
could not — write it here even if no row above covers it.
