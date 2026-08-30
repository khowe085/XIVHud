# Crossbar — in-client test plan

Tick one box per row and write anything odd in the last column. Blank rows
are "not tested". If a row fails, say what you saw rather than what you
expected — that is the part I cannot guess.

**The sections build on each other.** Section C binds a set of slots that
every later section reuses, and the job changes are deliberately near the
end so nothing before them has to be redone. Work top to bottom; if a row
says "as above", it depends on the row before it.

If **A** fails, stop — nothing after it will mean anything.

---

## A. Load

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| A1 | `//lua load xivhud`, then `//hud` | The command list prints | [x] | [ ] |  |
| A2 | Open `<addon>/load.log` | It ends without an error line | [x] | [ ] |  |
| A3 | Watch the load for texture warnings | No `missing texture` lines | [x] | [ ] |  |
| A4 | `//hud list` | `crossbar` is listed with four anchor lines | [x] | [ ] |  |
| A5 | Look at the screen | The bar is drawn, sixteen empty slots | [x] | [ ] |  |
| A6 | Look at the bar's bottom edge | Gold `Set 1` sits between the two crosses | [x] | [ ] |  |

## B. Keys — before anything is bound

Uses the `Set N` label as the only visible proof a key did something —
with one exception: **cycle deliberately skips empty sets**, so on a bar
with nothing bound it correctly stays put. Cycling proper is D5a.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| B1 | Press `;` on its own | Nothing happens — no chat line opens | [x] | [ ] |  |
| B2 | Press `'` on its own | Nothing happens | [x] | [ ] |  |
| B3 | Press `\` on its own | Nothing happens | [x] | [ ] |  |
| B4 | Press `=` on its own | Nothing happens, and no map | [x] | [ ] |  |
| B5 | Tap `` ` `` | Nothing moves — cycle skips EMPTY sets, and they all are. Proper cycling is D5a, after things are bound | [x] | [ ] | Test was wrong, not the addon: written before I remembered cycle skips empty sets. Jump (B7) has no such rule, which is why it works here. |
| B6 | Hold `` ` `` and press `3` | The label jumps straight to `Set 3` | [x] | [ ] |  |
| B7 | `//hud crossbar set 1` | Back to `Set 1` | [x] | [ ] |  |
| B8 | Press `1`–`8` with nothing held | Your game macros fire as usual | [x] | [ ] | Confirmed. Game macros need Ctrl or Alt + 1-8; the bare number row is the game's own hotbar, unaffected either way. |
| B9 | Hold `;` | A panel lights behind the left eight slots | [x] | [ ] |  |
| B10 | Hold `'` | A panel lights behind the right eight | [x] | [ ] |  |
| B11 | Hold `\` then `;` | The WXHB's left half appears | [x] | [ ] |  |
| B12 | Hold `\` then `'` | The WXHB's right half appears | [x] | [ ] |  |
| B13 | Hold `;` and `'` together | Expanded Hold replaces both bars | [x] | [ ] |  |
| B14 | Release one of the two | It drops to the side still held | [x] | [ ] |  |
| B15 | Hold `\` and tap `` ` `` with no side held | A sword lights above `Set N` and nothing is said in chat; again and it clears, disengaging you | [x] | [ ] |  |
| B16 | Press Enter, then type `;` `'` `\` `` ` `` `=` and `1`–`8` | Every character lands in the message | [x] | [ ] | Game macros require holding ctrl or alt + number row 1-8 |
| B17 | Close the chat line | The keys go back to doing B1–B15 | [x] | [ ] |  |
| B18 | Hold `;`, alt-tab away, come back, release | Nothing is stuck lit or stuck down | [x] | [ ] |  |

## C. Binding from the console

These bindings are used by every later section — leave them in place.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| C1 | `//hud crossbar bind 1L1 ma "Cure" me` | Slot 1 shows Cure with its icon | [x] | [ ] |  |
| C2 | Hold `;` and press `1` | Cure is cast on you | [x] | [ ] |  |
| C3 | Watch slot 1 straight after | A dark sweep wipes round it until the recast is up | [x] | [ ] |  |
| C4 | Look at slot 1's corner | Cure's MP cost is written there | [x] | [ ] |  |
| C5 | Let your MP drop below that cost | The slot dims | [x] | [ ] |  |
| C6 | `//hud crossbar bind 1L2 ja "Provoke" t` | Bound, and it fires on a target | [x] | [ ] |  |
| C7 | `//hud crossbar bind 1L3 ws "Savage Blade" t` | Bound; fires with TP and a target | [x] | [ ] |  |
| C8 | `//hud crossbar bind 1L4 item "Echo Drops" me` | Bound, and the corner shows how many you carry | [x] | [ ] |  |
| C9 | Use Echo Drops until you have none | The count reaches 0, a red X covers the slot, it dims | [x] | [ ] | Initially failed - count only moved when the stack emptied; fixed by refreshing off the 0x01E inventory packet (a40952f) |
| C10 | `//hud crossbar bind 1R1 ra t` | Bound; fires a ranged attack | [x] | [ ] |  |
| C11 | `//hud crossbar bind 1R2 ct "sea all linkshell"` | Bound; fires the search command | [x] | [ ] |  |
| C12 | `//hud crossbar bind 1R3 ex "echo hello"` | Bound; the console echoes | [x] | [ ] |  |
| C13 | `//hud crossbar bind 1R4 open map` | Bound; pressing it opens the map | [x] | [ ] |  |
| C14 | `//hud crossbar bind 1R5 draw` | Bound; pressing it lights the sword with nothing said, and clears it on the second press | [x] | [ ] |  |
| C15 | `//hud crossbar bind 1R6 mount "Chocobo"` | Bound; pressing it summons after a countdown - and dismounts at once if you are already mounted | [x] | [ ] |  |
| C16 | `//hud crossbar bind 1L5 ma "Cure IV" Zeid` | Refused, with advice to quote or use a token | [x] | [ ] | Refused as designed. Bare player names as targets requested as a feature - filed as #20 |
| C17 | `//hud crossbar list` | Every slot above is listed, with its layer | [x] | [ ] |  |
| C18 | `//hud crossbar alias 1L1 "Heal"` | Slot 1's label reads `Heal` | [x] | [ ] |  |
| C19 | `//hud crossbar icon 1L1 map` | Slot 1's icon changes | [x] | [ ] | Initially failed - accepted but drew the old art; the icon memo keyed on record identity and the verb mutates in place (22f7b23) |
| C20 | `//hud crossbar alias 1L1` then `icon 1L1` | Both revert to Cure's own | [x] | [ ] |  |
| C21 | `//hud crossbar swap 1L1 1L2` | Cure and Provoke exchange slots | [x] | [ ] |  |
| C22 | `//hud crossbar swap 1L1 1L2` again | They swap back | [x] | [ ] |  |
| C23 | `//hud crossbar bind 1L8 ma "Dia" t` then `unbind 1L8` | Bound, then the slot empties | [x] | [ ] |  |
| C24 | `//hud crossbar bind 1Ly ma "Cure" me` | **Refused** - a slot is 1-8. The controller button names went with the address change (2026-08-22): there is no controller for them to name | [x] | [ ] |  |
| C25 | Type `/ma "Cure" <YourName>` straight into the game | It casts — a name in angle brackets IS a target | [x] | [ ] | Confirmed - the game accepts a bare player name in angle brackets as a target, so #20 is a parser change and not a non-feature |
| C26 | `//hud crossbar bind 2L1 ma "Cure IV" me alias=Cure 4 icon=heal` | Bound with the label `Cure 4` and the pack's `heal` art. **This is the row that settled how Windower splits an addon command** | [x] | [ ] | ANSWERED 2026-08-30, against the assumption: Windower GROUPS a quoted run into one argument and STRIPS the quote characters. The positional quote-delimited grammar could therefore never fire in a client - `//hud crossbar bind 1R1 ex "jc RDM/DRK" "RDM/DRK" "jobs/rdm"` bound an action called `jc RDM/DRK RDM/DRK jobs/rdm` with no label at all, reported as a success. Grammar re-based on the `alias=` / `icon=` markers; the row above is the new spelling |
| C27 | `//hud crossbar bind 2L2 ja "Berserk" icon=attack` | Bound with the pack's `attack` art and Berserk's own name under it - an icon with no alias needs no empty slot held open now | [ ] | [ ] |  |
| C28 | `//hud crossbar bind 2L3 ma "Cure IV" icon=nosuchart` | **Refused**, naming `icons/custom/nosuchart.png`, and slot 3 stays empty - a bad icon refuses the whole bind | [ ] | [ ] |  |
| C29 | `//hud crossbar bind 2R1 ct p pulling alias=Pull` | Bound; the slot reads `Pull` and pressing it says `/p pulling` - and NOT `/p pulling alias=Pull`. The line is stored without its leading slash, which `actions` adds | [ ] | [ ] |  |
| C30 | `//hud crossbar list 2` then retype one listed row at a free address | The two slots hold identical records - a listed row is what you would type to reproduce it | [ ] | [ ] |  |
| C31 | `//hud crossbar bind 2R2 ex "jc RDM/DRK" alias=RDM/DRK icon=jobs/rdm` | Bound; the slot reads `RDM/DRK` over the job icon, and pressing it runs `jc RDM/DRK` and nothing more - the reported defect, in the form that replaced it | [ ] | [ ] |  |
| C32 | `//hud crossbar bind 2R3 ma "Cure IV" alias=Big Heal` | Bound with the label `Big Heal`: a marker's value runs to the next marker or the end of the line, so an alias with spaces needs no quotes | [ ] | [ ] |  |
| C33 | `//hud crossbar bind 2R4 ma "Cure IV" alias=Heal p1` | **Refused**, naming `p1` - a target after the labels would vanish into the alias and bind a cure aimed at nothing | [ ] | [ ] |  |
| C34 | `//hud crossbar bind 2R5 ct ma "Cure IV" <t>` then press it | It CASTS: a word reaches the addon with a space in it only where the user quoted it, so the quotes are put back and the line says `/ma "Cure IV" <t>` rather than `/ma Cure IV <t>` | [ ] | [ ] |  |

## D. Sets and layers

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| D1 | `//hud crossbar set 2` | Label reads `Set 2` and the slots go empty | [x] | [ ] |  |
| D2 | `//hud crossbar bind 2L1 ma "Dia" t` | Bound on set 2 only | [x] | [ ] |  |
| D3 | `//hud crossbar set 1` | Cure is back on slot 1 | [x] | [ ] |  |
| D4 | `//hud crossbar cycle 2 none` then tap `` ` `` repeatedly | Set 2 is skipped by the rotation | [x] | [ ] |  |
| D5 | `//hud crossbar cycle 2 both` | Set 2 is visited again | [x] | [ ] |  |
| D5a | With sets 1 and 2 both bound, tap `` ` `` | The label moves between them — this is B5's real test | [x] | [ ] |  |
| D5b | Bind nothing to sets 3–8 and keep tapping `` ` `` | The empty sets are skipped, never landed on | [x] | [ ] |  |
| D6 | `//hud crossbar share 2 on` | Reported as shared, **and** warns that this job's own set-2 bindings are dormant while it is | [x] | [ ] |  |
| D7 | `//hud crossbar list 2` | Set 2 reads empty - the shared store has nothing in it yet, and Dia is dormant rather than lost. The flag itself is not reported back anywhere (Kevin: leave it that way, 2026-08-22) | [x] | [ ] | Row expectation was wrong, not the code - a shared set reads the empty SHARED store, which is exactly what `share` warns about |
| D8 | `//hud crossbar share 2 off`, then `list 2` | Reported as job-specific again, **and Dia is back** - the dormancy was reversible | [x] | [ ] |  |
| D9 | `//hud crossbar share 2 on` | Back to shared — leave it this way for section M | [x] | [ ] |  |
| D10 | `//hud crossbar share 1 on` then `share 1 off` | Set 1 is untouched by set 2's flag either way | [x] | [ ] |  |
| D11 | `//hud crossbar bind sub:1L6 ma "Stone" t` | Bound to the subjob layer | [x] | [ ] |  |
| D12 | Look at slot 6 in edit mode later (F-section) | It is tagged as a subjob override | [x] | [ ] | Verified in F2 - slot 6 carries the subjob mark |
| D13 | `//hud crossbar context list` | Lists the four Scholar contexts and which are live | [x] | [ ] |  |
| D14 | On SCH: `//hud crossbar bind ctx:light-arts:1L7 ja "Accession"` | Bound to that context | [x] | [ ] |  |
| D15 | On SCH: use Light Arts | Slot 7 changes to Accession by itself | [x] | [ ] |  |
| D16 | On SCH: use Dark Arts | Slot 7 changes back | [x] | [ ] |  |

## E. The other two bars

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| E1 | `//hud crossbar` (no arguments) | Reports job, active set, and where each bar points | [x] | [ ] |  |
| E2 | `//hud crossbar view wxhb-L 1R` | Reported as changed. **Not** `2L` - that is already the default, so it would prove nothing (Kevin, 2026-08-22) | [x] | [ ] | Original row set it to its own default and proved nothing - reworked to 1 r |
| E3 | Hold `\`+`;` | The WXHB's left half now shows set 1's **right** side - the ranged/search/echo/map slots, not set 2's Dia | [x] | [ ] |  |
| E3a | `//hud crossbar view wxhb-L 2L`, then hold `\`+`;` again | It goes back to the default view | [x] | [ ] |  |
| E4 | With it held, press slot key `4` | The map opens - set 1 right slot 4, what the **WXHB** shows, not the XHB's slot 4. Slot 4 rather than a console echo because the map is unmissable (Kevin, 2026-08-22) | [x] | [ ] |  |
| E5 | `//hud crossbar wxhb on` | Both WXHB halves stay on screen at rest | [x] | [ ] |  |
| E6 | `//hud crossbar wxhb off` | They only appear while held | [x] | [ ] |  |
| E7 | Hold both sides, press a slot key | Expanded Hold fires from the set its view points at - set 3, unbound, so nothing fires | [x] | [ ] | Weak on its own - nothing bound to set 3; E8/E9 added as the real test |
| E8 | `//hud crossbar bind 3L1 ma "Cure" me` and `//hud crossbar bind 3R1 ja "Provoke" t` | Both bound on set 3 | [x] | [ ] |  |
| E9 | Hold `;` **then** `'` and press `1`; then hold `'` **then** `;` and press `1` | The first casts Cure (exp-lr, set 3 left), the second fires Provoke (exp-rl, set 3 right) - the hold ORDER picks the side | [x] | [ ] |  |

## F. The mouse binder

**Rewritten 2026-08-22.** The binder was three surfaces drawn beside each
other; it is now ONE window that walks three steps. Every row below except
F2, F7 and F14 is new or changed, so the passes recorded against the old
binder are gone - they were answers about code that no longer exists.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| F1 | Hold `;` and press `=` | Edit mode says so in chat. Nothing is drawn yet - the window appears when you click a slot | [x] | [ ] |  |
| F2 | Look at the bar | Slots show `+` for subjob and `*` for context sources | [x] | [ ] | Unchanged by the rewrite; D12 covered here too |
| F3 | Click an empty slot | One window opens **dead centre**, titled `pick a layer`, listing the whole stack | [x] | [ ] |  |
| F4 | Look at the top left of it | A button reading `[ close ]` - on the first step there is nothing to go back to | [x] | [ ] |  |
| F5 | Read the line under the title | It names the slot you clicked in the form you would type - `1L3` | [x] | [ ] |  |
| F6 | Click a layer row | The **same** window becomes `pick an action`: categories down the left, actions on the right, and the subhead now names the layer | [x] | [ ] |  |
| F7 | Go back and click a **context** layer row instead | The bar previews itself as if that buff were up, and the subhead says which | [x] | [ ] | Unchanged by the rewrite |
| F8 | Click a spell or ability | The window becomes `pick a target`, listing every FFXI token with `(no target)` first | [x] | [ ] |  |
| F9 | Click `<t>` | It binds with that target, echoes in chat, and the window returns to `pick a layer` | [x] | [ ] |  |
| F10 | `//hud crossbar list` | That slot shows the target you picked - the mouse never wrote one before | [x] | [ ] |  |
| F11 | Bind something from the **General** category (`draw`, `warp`, `mr`) | No target step at all - it binds straight away | [x] | [ ] |  |
| F12 | Hover an action in the list | The right-hand column fills in: name, type, cost, recast, chain property | [x] | [ ] |  |
| F13 | Hover a bound slot on the bar | The same column, plus the layer the entry comes from and what it covers | [ ] | [x] | Details text still overruns the backdrop - the wrap budget is an estimate and too generous. Filed as #21 |
| F14 | Look for **Refresh III**, or any merit spell you know | It is listed and binds | [x] | [ ] | Unchanged by the rewrite - the catalog content did not move |
| F15 | Look for an **Enchanted** category | It exists and lists your enchanted gear | [x] | [ ] |  |
| F16 | Open a long category and scroll to its last page, then keep scrolling down | It **stops** on the last page. It must not wrap round to the top | [x] | [ ] |  |
| F17 | Scroll up past the first page | It stops there too | [x] | [ ] |  |
| F18 | Get to the target step, then press back | Back to the action list | [x] | [ ] |  |
| F19 | Press back again | Back to the layer list, with the layer choice released | [x] | [ ] |  |
| F20 | Press back once more | The window closes. **Edit mode is still on** | [x] | [ ] |  |
| F21 | Click a slot, then drag the window by its **title strip** | It moves with the cursor, keeping the grab point under it | [x] | [ ] |  |
| F22 | Try to push it off each edge of the screen | It stays fully on screen | [x] | [ ] |  |
| F23 | Leave it somewhere off-centre, close edit mode, reopen it and click a slot | It opens where you left it, not back in the middle | [x] | [ ] |  |
| F24 | Press the back button and drag from it | The window does not move - back is checked first, so a slip onto it is still back | [x] | [ ] |  |
| F25 | With no window open, tap `` ` `` | The set changes, in edit mode | [x] | [ ] |  |
| F26 | Hold `` ` `` and press a number | It jumps to that set | [x] | [ ] |  |
| F27 | Click a slot, then change set | The window is put away - it remembered the old set's address - and edit mode stays on | [x] | [ ] |  |
| F28 | Drag one slot onto another | The two swap entirely | [x] | [ ] |  |
| F29 | Drag a slot onto genuinely empty screen | It clears that layer only | [x] | [ ] |  |
| F30 | Drag a slot and drop it on the window | Nothing changes, and nothing is said | [x] | [ ] |  |
| F31 | Drag an action from the list onto a slot | **Nothing happens.** Drag-to-bind went with the wizard | [x] | [ ] |  |
| F32 | While the binder is open, hold `;` and press slot keys | The bar does not activate and nothing fires | [x] | [ ] | Nothing fires, binder open or closed. Note: the side held to open edit mode stays lit, since the widget freezes the display when the mode opens |
| F33 | Press `=` | Edit mode closes | [x] | [ ] |  |
| F34 | Open and close it a few times, watching the frame it opens on | No stutter or hitch as it appears | [x] | [ ] |  |
| F35 | Read the window at arm's length | 18pt is comfortably readable, and 920x600 fits your resolution | [x] | [ ] |  |

## G. Counters and the skillchain indicator

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| G1 | On NIN, bind `ma "Utsusemi: Ichi"` to a slot | The corner shows your Shihei count | [x] | [ ] |  |
| G2 | Spend them all | The count reads 0 and the slot crosses out | [x] | [ ] |  |
| G3 | On a job without NIN, view that same slot | No count, no red X | [x] | [ ] |  |
| G4 | On SCH, bind `ja "Accession"` | The corner shows your stratagem charges | [x] | [ ] |  |
| G5 | Spend one | The number drops and climbs back over time | [x] | [ ] |  |
| G6 | Use a weaponskill on a mob | The skillchain indicator appears | [x] | [ ] |  |
| G7 | Watch a bound weaponskill during that window | Its icon changes to the chain it would make | [x] | [ ] |  |
| G8 | Let the window lapse | The indicator disappears | [x] | [ ] |  |

## H. Built-ins

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| H1 | `//hud crossbar draw` | The sword lights above `Set N` and nothing is said in chat - the state is the addon's, and entering it sends no command; again and it clears, disengaging you | [x] | [ ] |  |
| H2 | Engage a mob without using `draw` | The bar switches to its drawn rotation | [x] | [ ] |  |
| H3 | Let the mob die | It stays on the drawn rotation | [x] | [ ] |  |
| H4 | `//hud crossbar mr` | A five-second countdown prints, then you mount | [x] | [ ] |  |
| H5 | `//hud crossbar mr` while mounted | You dismount immediately, with no countdown | [x] | [ ] |  |
| H6 | `//hud crossbar mr`, then `/heal` during the countdown | It cancels and says so | [x] | [ ] |  |
| H7 | `//hud crossbar mr`, then zone during the countdown | It cancels, and says so - every cancel path speaks, resting included, and consistency beats silence here (row corrected 2026-08-22; the code never cancelled quietly) | [x] | [ ] |  |
| H8 | `//hud crossbar open` | Lists the screens it can open | [x] | [ ] |  |
| H9 | `//hud crossbar open equipment` | The equipment window opens | [ ] | [x] | open equipment does nothing; open map works. The chord-based openers (equipment, inventory) are broken - filed as #22 |
| H10 | `//hud crossbar help` | Prints the command list | [x] | [ ] |  |
| H11 | If you own a trainer's whistle, run `//hud crossbar mr` a dozen times | It is never picked as a mount | [ ] | [x] | Do not own a trainer's whistle |

## I. Warp

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| I1 | With no warp item and no Warp spell, `//hud crossbar warp` | Says what you are missing, one rung at a time, in ladder order: Warp Ring, Instant Warp, Warp Cudgel, Treat Staff II, Tavnazian Ring. A rung it cannot even name is skipped silently rather than reported | [x] | [ ] | Initially failed - wrong ladder order and Treat Staff II missing; fixed and re-run (5dd2ad3) |
| I2 | Holding an **Instant Warp** only, `//hud crossbar warp` | Counts down naming the item - `Instant Warp in 5 seconds. /heal to cancel.`, then `4...` down to `1...` - then uses it | [x] | [ ] |  |
| I3 | Holding a **Warp Ring** in your bag (not worn), `//hud crossbar warp` | No countdown up front: says `warping with Warp Ring - equipping it first.` and puts it on, then once it can read the warm-up says `Warp Ring ready in N seconds. /heal to cancel.`, counts only the last five (`5...` down to `1...`), then fires | [x] | [ ] |  |
| I4 | Straight after I3 | Your gear swapping still works normally | [x] | [ ] |  |
| I5 | With a Warp Ring in your bag and GearSwap running, fire `gs equip sets.engaged` and `//hud crossbar warp` together so the set-equip lands the same moment as the press | The ring still ends up on your finger and the warp still fires - the poll checks the ring actually equipped and re-sends the equip roughly once a second until it does, rather than reading a bagged ring's stale data and hanging until the give-up | [x] | [ ] |  |
| I6 | Wearing a charged, off-recast **Warp Ring** already, `//hud crossbar warp` | Counts down naming it, same as I2 - `Warp Ring in 5 seconds. /heal to cancel.` - then warps without a refusal message | [x] | [ ] |  |
| I7 | Wearing a **Warp Ring** you just put on (still warming), `//hud crossbar warp` | Same pattern as I3 - `warping with Warp Ring - equipping it first.` even though it is already on - then the length, then the last five, then it waits out the warm-up rather than failing | [x] | [ ] |  |
| I8 | Holding a **Tavnazian Ring** only, `//hud crossbar warp` | Same announce-then-wait as I3, but the length comes back near thirty seconds; only the last five are spoken, so expect a long quiet stretch before it fires | [x] | [ ] |  |
| I9 | On BLM with Warp known and MP, `//hud crossbar warp` | Counts down with the bare word - `Warp in 5 seconds. /heal to cancel.` (the spell rung carries no name of its own, so this never says "Warp II" even when that is the one cast) - then casts it | [x] | [ ] |  |
| I10 | `//hud crossbar warp all` with another character running XIVHud | Both go home; the second character's own warp starts at once with no countdown of its own, whatever its ladder picks | [ ] | [x] | No second character running XIVHud available |
| I11 | `//hud crossbar warp`, then `/heal` during the five-second countdown | Cancels and says so - `<rung> cancelled.` - and fires nothing | [x] | [ ] |  |
| I12 | Holding a bagged ring, `//hud crossbar warp`, then `/heal` once it says "ready in N seconds" | The warm-up cancels too - `warp cancelled - Warp Ring` - and the GearSwap slot is released at once rather than at the deadline | [x] | [ ] |  |
| I13 | Holding a bagged ring, `//hud crossbar warp`, then log out to character select while it is still equipping or warming | Says `warp dropped - Warp Ring` before you reach the character screen instead of going silent, and gear swapping is not left disabled (log back in after - nothing here is lost) | [ ] | [x] | Skipped - would have required logging out mid-warm-up |

## J. Enchanted gear

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| J1 | `//hud crossbar bind 1L6 enchanteditem "<a ring you own>"` | Bound, with the item's own icon | [x] | [ ] |  |
| J2 | Look at that slot's corner | It shows how many of that item you have | [x] | [ ] |  |
| J3 | Press it with the ring in your bag | It equips, pauses, then uses it | [x] | [ ] |  |
| J4 | Straight after J3 | Your gear swapping still works | [x] | [ ] | A sub-slot GearSwap hold looked stuck once and cleared on its own; not reproducible |
| J5 | Press it with the ring already worn and charged | It fires straight away | [x] | [ ] |  |
| J6 | Press it with the charge spent | It says `no charges left` | [x] | [ ] |  |
| J7 | Press it while a warp countdown is running | It says something is already in progress | [x] | [ ] |  |
| J8 | Bind one with a target (`enchanteditem "X" t`) and press with nothing targeted | It refuses rather than firing later | [ ] | [x] | Own no enchanted item that takes a target |
| J9 | Bind an enchanted item worn somewhere that is **not** a ring — an earring, a cape, a body piece | It equips into the right slot and uses | [x] | [ ] |  |
| J10 | Straight after J9 | Your gear swapping works, with nothing left locked | [x] | [ ] |  |

## K. The cast retry (the queue)

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| K1 | `//hud crossbar retry` | Reports it as off | [x] | [ ] |  |
| K2 | `//hud crossbar retry on` | Reports it as on | [x] | [ ] |  |
| K3 | Cast two spells back to back from the bar so the second is refused | The refused one goes out again a moment later | [x] | [ ] |  |
| K4 | Do the same, then immediately press something else | The held spell is dropped, not fired late | [x] | [ ] |  |
| K5 | Press a spell that is still on recast | Nothing is held — it fails as it always did | [x] | [ ] |  |
| K6 | Retry a spell aimed at `t`, then tab to another mob | It lands on the first mob, not the new one | [x] | [ ] |  |
| K7 | Get silenced, then press a spell that is refused | Nothing is retried while silenced | [ ] | [x] | Could not get silenced |
| K8 | `//hud crossbar retry off` mid-hold | The held spell is dropped | [ ] | [x] | Not run |
| K9 | Whatever K3 did, write the game's refusal message **word for word** in the notes | — (this is a reading, not a pass) | [x] | [ ] | Refusal reads 'Unable to cast spells at this time.' - the code matches on message id, and K3 passing confirms that text carries id 17 or 18 |
| K10 | Roughly how long after the refusal did the re-send succeed? | — (a rough number in the notes is enough) | [x] | [ ] | Re-sent 1-2 seconds after the refusal, about the usual gap between spells |
| K11 | Try the same with a job ability, then a weaponskill | Both are retried the way a spell is | [ ] | [x] | Not run - the ability (71) and weaponskill (72) message ids remain unverified |

## L. Layout mode

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| L1 | `//hud layout` | Highlight boxes and names appear over each anchor | [x] | [ ] |  |
| L2 | Count them | Four: main, both WXHB halves, and the indicator | [x] | [ ] |  |
| L3 | Drag the main box | It moves and snaps to the grid | [x] | [ ] |  |
| L4 | Drag with CTRL held | It moves freely | [x] | [ ] |  |
| L5 | Wheel over one box | Only that anchor scales | [x] | [ ] |  |
| L6 | Right-click a box | The whole crossbar toggles off, then on | [x] | [ ] | Toggles the whole widget as designed; per-anchor toggling requested as a feature - filed as #23 |
| L7 | Press `;` while in layout mode | Nothing reaches the game and nothing fires | [x] | [ ] |  |
| L8 | Press `1`–`8` while in layout mode | They reach the game as usual | [x] | [ ] |  |
| L9 | `//hud layout` again, then reload | Everything is where you left it | [x] | [ ] |  |

## M. Persistence, jobs, and lifecycle

Leave the job change until here so nothing above has to be redone.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| M1 | `//lua reload xivhud` | The bar returns with every binding intact | [x] | [ ] |  |
| M2 | Check `data/<Character>/crossbar/` | A `<JOB>.lua` file is there, and `SHARED.lua` | [x] | [ ] |  |
| M3 | Change job | The bar reloads to that job's own bindings | [x] | [ ] |  |
| M4 | Look at set 2 (shared, from D9) | Its contents are the same on this job | [x] | [ ] |  |
| M5 | On this job: `//hud crossbar bind 2L4 ma "Dia" t` | Bound into the shared set from the second job | [x] | [ ] |  |
| M6 | Change back to the first job, look at set 2 slot 4 | Dia is there — sharing carries both ways | [x] | [ ] |  |
| M7 | Look at set 1 on both jobs | Set 1 still differs per job — only set 2 is shared | [x] | [ ] |  |
| M8 | `//hud crossbar share 2 off`, then check both jobs | Each job keeps its own set 2 again | [x] | [ ] |  |
| M9 | `//hud crossbar copy SHARED` | Refused — shared sets belong to no job | [x] | [ ] |  |
| M10 | `//hud crossbar copy <the other job>` | This job's bindings are replaced wholesale | [x] | [ ] |  |
| M11 | Watch a cutscene start | The whole HUD hides | [x] | [ ] |  |
| M12 | Press `;` during the cutscene | It does not open a chat line | [x] | [ ] |  |
| M13 | Let the cutscene end | The bar comes back, nothing stranded | [x] | [ ] |  |
| M14 | Zone | It hides while zoning and returns after | [x] | [ ] |  |
| M15 | Log out to character select | Nothing is drawn | [x] | [ ] |  |
| M16 | Log back in | The bar returns with this character's bindings | [x] | [ ] |  |
| M17 | Log in as a different character | That character's own bindings load, and the shared set is that character's own | [ ] | [x] | Only one character available to test with |

## N. Last — destructive

Run these only when everything above is done.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| N1 | `//hud hide crossbar` | The bar disappears. To prove the keys really went back, `bind ; input /echo REACHED` in the Windower console first: shown, pressing `;` must NOT echo; hidden, it must. `unbind ;` after. (`;` opening the chat box proves nothing - it is not a chat key in FFXI. See #24) | [x] | [ ] | Hide/show works; whether the keys are truly released is unproven - the row asked for the wrong evidence, filed as #24 |
| N2 | `//hud show crossbar` | It returns | [x] | [ ] |  |
| N3 | `//hud reset crossbar` | Settings and every job's bindings are wiped | [x] | [ ] |  |
| N4 | `//lua unload xivhud` | No keybind is left broken behind it - proved the same way as N1, with `bind ; input /echo REACHED`: unloaded, pressing `;` must echo. Pressing the keys and seeing nothing proves nothing, since none of them do anything in FFXI natively (#24) | [x] | [ ] | Unloaded cleanly; whether the keys are released is unproven by the evidence asked for - same measurement problem as N1, filed as #24 |

## O. Facts the code is still guessing at

These are not really pass/fail — they are **readings**. Tick Pass if you
managed to look, and put what you saw in the notes. Each one settles a
question the code currently guesses at, listed in
[crossbar-in-client.md](crossbar-in-client.md).

| # | Do this | What I need | Pass | Fail | What you saw |
| --- | --- | --- | --- | --- | --- |
| O1 | Look at an enchanted ring's entry in `res.items` | Does it have a `slots` field, and is it a set, a list, or a number? | [ ] | [x] | Needs a resources-table read; no console recipe to hand |
| O2 | Look at `res.bags` | Is there a bag whose name contains `temporary`, and what exactly is it called? | [ ] | [x] | Needs a resources-table read |
| O3 | Look at `res.statuses` | Is there an entry whose english name is `Resting`, and what is its id? | [ ] | [x] | Needs a resources-table read |
| O4 | Sit with `/heal` and read your own status number | Does it match what O3 said? | [ ] | [x] | Needs a status read |
| O5 | Type `/ma "Cure IV"` with a mob selected, then with nothing selected | What happens each time — does it use the target, prompt, or fail? | [x] | [ ] | Answered by C25 - a bare name in angle brackets casts, so a target token is resolved by the game at send time |
| O6 | Type `/item "Echo Drops" <a real mob id>` using a number, not a token | Does the game accept a bare numeric target? | [x] | [ ] | Answered by K6 - the cast retry re-sends the pinned mob id in place of <t> and lands on the original mob, so the game does accept a bare numeric target |
| O7 | On a job with /COR, try to spend a **master** card (Trump Card) | Can a subjob COR burn one? | [ ] | [x] | Not run |
| O8 | If you own a trainer's whistle, look at its name in your key items | Does it start with the same music-note character the mounts do? | [ ] | [x] | Do not own a trainer's whistle |

---

## Anything else

Write down anything that felt wrong but has no row above — sluggishness,
a flicker, a message that read oddly, art that looked out of place.
