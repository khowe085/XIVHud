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
| C1 | `//hud crossbar bind 1 l 1 ma "Cure" me` | Slot 1 shows Cure with its icon | [x] | [ ] |  |
| C2 | Hold `;` and press `1` | Cure is cast on you | [x] | [ ] |  |
| C3 | Watch slot 1 straight after | A dark sweep wipes round it until the recast is up | [x] | [ ] |  |
| C4 | Look at slot 1's corner | Cure's MP cost is written there | [x] | [ ] |  |
| C5 | Let your MP drop below that cost | The slot dims | [x] | [ ] |  |
| C6 | `//hud crossbar bind 1 l 2 ja "Provoke" t` | Bound, and it fires on a target | [x] | [ ] |  |
| C7 | `//hud crossbar bind 1 l 3 ws "Savage Blade" t` | Bound; fires with TP and a target | [x] | [ ] |  |
| C8 | `//hud crossbar bind 1 l 4 item "Echo Drops" me` | Bound, and the corner shows how many you carry | [x] | [ ] |  |
| C9 | Use Echo Drops until you have none | The count reaches 0, a red X covers the slot, it dims | [x] | [ ] | Initially failed - count only moved when the stack emptied; fixed by refreshing off the 0x01E inventory packet (a40952f) |
| C10 | `//hud crossbar bind 1 r 1 ra t` | Bound; fires a ranged attack | [x] | [ ] |  |
| C11 | `//hud crossbar bind 1 r 2 ct "sea all linkshell"` | Bound; fires the search command | [x] | [ ] |  |
| C12 | `//hud crossbar bind 1 r 3 ex "echo hello"` | Bound; the console echoes | [x] | [ ] |  |
| C13 | `//hud crossbar bind 1 r 4 open map` | Bound; pressing it opens the map | [x] | [ ] |  |
| C14 | `//hud crossbar bind 1 r 5 draw` | Bound; pressing it draws/sheathes | [x] | [ ] |  |
| C15 | `//hud crossbar bind 1 r 6 mount "Chocobo"` | Bound; pressing it summons after a countdown | [x] | [ ] |  |
| C16 | `//hud crossbar bind 1 l 5 ma "Cure IV" Zeid` | Refused, with advice to quote or use a token | [x] | [ ] | Refused as designed. Bare player names as targets requested as a feature - filed as #20 |
| C17 | `//hud crossbar list` | Every slot above is listed, with its layer | [x] | [ ] |  |
| C18 | `//hud crossbar alias 1 l 1 "Heal"` | Slot 1's label reads `Heal` | [x] | [ ] |  |
| C19 | `//hud crossbar icon 1 l 1 map` | Slot 1's icon changes | [ ] | [ ] |  |
| C20 | `//hud crossbar alias 1 l 1` then `icon 1 l 1` | Both revert to Cure's own | [ ] | [ ] |  |
| C21 | `//hud crossbar swap 1 l 1 1 l 2` | Cure and Provoke exchange slots | [ ] | [ ] |  |
| C22 | `//hud crossbar swap 1 l 1 1 l 2` again | They swap back | [ ] | [ ] |  |
| C23 | `//hud crossbar bind 1 l 8 ma "Dia" t` then `unbind 1 l 8` | Bound, then the slot empties | [ ] | [ ] |  |
| C24 | `//hud crossbar bind 1 l 1 y ma "Cure" me` | The button name `y` works like slot 1 | [ ] | [ ] |  |
| C25 | Type `/ma "Cure" <YourName>` straight into the game | It casts — a name in angle brackets IS a target | [ ] | [ ] |  |

## D. Sets and layers

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| D1 | `//hud crossbar set 2` | Label reads `Set 2` and the slots go empty | [ ] | [ ] |  |
| D2 | `//hud crossbar bind 2 l 1 ma "Dia" t` | Bound on set 2 only | [ ] | [ ] |  |
| D3 | `//hud crossbar set 1` | Cure is back on slot 1 | [ ] | [ ] |  |
| D4 | `//hud crossbar cycle 2 none` then tap `` ` `` repeatedly | Set 2 is skipped by the rotation | [ ] | [ ] |  |
| D5 | `//hud crossbar cycle 2 both` | Set 2 is visited again | [ ] | [ ] |  |
| D5a | With sets 1 and 2 both bound, tap `` ` `` | The label moves between them — this is B5's real test | [ ] | [ ] |  |
| D5b | Bind nothing to sets 3–8 and keep tapping `` ` `` | The empty sets are skipped, never landed on | [ ] | [ ] |  |
| D6 | `//hud crossbar share 2 on` | Reported as shared | [ ] | [ ] |  |
| D7 | `//hud crossbar list 2` | Shows set 2's contents and that it is shared | [ ] | [ ] |  |
| D8 | `//hud crossbar share 2 off`, then `list 2` | Reported as job-specific again | [ ] | [ ] |  |
| D9 | `//hud crossbar share 2 on` | Back to shared — leave it this way for section M | [ ] | [ ] |  |
| D10 | `//hud crossbar share 1 on` then `share 1 off` | Set 1 is untouched by set 2's flag either way | [ ] | [ ] |  |
| D11 | `//hud crossbar bind sub:1 l 6 ma "Stone" t` | Bound to the subjob layer | [ ] | [ ] |  |
| D12 | Look at slot 6 in edit mode later (F-section) | It is tagged as a subjob override | [ ] | [ ] |  |
| D13 | `//hud crossbar context list` | Lists the four Scholar contexts and which are live | [ ] | [ ] |  |
| D14 | On SCH: `//hud crossbar bind ctx:light-arts:1 l 7 ja "Accession"` | Bound to that context | [ ] | [ ] |  |
| D15 | On SCH: use Light Arts | Slot 7 changes to Accession by itself | [ ] | [ ] |  |
| D16 | On SCH: use Dark Arts | Slot 7 changes back | [ ] | [ ] |  |

## E. The other two bars

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| E1 | `//hud crossbar` (no arguments) | Reports job, active set, and where each bar points | [ ] | [ ] |  |
| E2 | `//hud crossbar view wxhb-l 2 l` | Reported as changed | [ ] | [ ] |  |
| E3 | Hold `\`+`;` | The WXHB's left half now shows set 2's left side | [ ] | [ ] |  |
| E4 | With it held, press a slot key | It fires what the WXHB shows, not the XHB | [ ] | [ ] |  |
| E5 | `//hud crossbar wxhb on` | Both WXHB halves stay on screen at rest | [ ] | [ ] |  |
| E6 | `//hud crossbar wxhb off` | They only appear while held | [ ] | [ ] |  |
| E7 | Hold both sides, press a slot key | Expanded Hold fires from the set its view points at | [ ] | [ ] |  |

## F. The mouse binder

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| F1 | Hold `;` and press `=` | The binder opens | [ ] | [ ] |  |
| F2 | Look at the bar | Slots show `+` for subjob and `*` for context sources | [ ] | [ ] |  |
| F3 | Click an empty slot | Its layer stack opens beside it | [ ] | [ ] |  |
| F4 | Click the action list before picking a layer | Nothing binds — the list is locked | [ ] | [ ] |  |
| F5 | Click a layer row | The action list unlocks | [ ] | [ ] |  |
| F6 | Click a context layer row | The bar previews itself as if that buff were up | [ ] | [ ] |  |
| F7 | Click an action | It binds, echoes, and the panel refreshes in place | [ ] | [ ] |  |
| F8 | Hover an action in the list | A panel shows name, cost, recast and chain property | [ ] | [ ] |  |
| F9 | Hover a bound slot | It also says which layer the entry comes from | [ ] | [ ] |  |
| F10 | Look for **Refresh III** (or any merit spell you know) | It is listed and binds | [ ] | [ ] |  |
| F11 | Look for an **Enchanted** group | It exists and lists your enchanted gear | [ ] | [ ] |  |
| F12 | Drag an action onto a slot | It binds there | [ ] | [ ] |  |
| F13 | Drag one slot onto another | The two swap entirely | [ ] | [ ] |  |
| F14 | Drag a slot onto empty screen | It clears that layer only | [ ] | [ ] |  |
| F15 | Drag a slot and drop it on the binder's own panel | Nothing changes | [ ] | [ ] |  |
| F16 | Click a slot, then click far away | The choice resets, nothing is bound | [ ] | [ ] |  |
| F17 | While the binder is open, hold `;` | The bar does not activate | [ ] | [ ] |  |
| F18 | Press `=` | The binder closes | [ ] | [ ] |  |
| F19 | Open and close it a few times, watching the frame it opens on | No stutter or hitch as it appears | [ ] | [ ] |  |

## G. Counters and the skillchain indicator

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| G1 | On NIN, bind `ma "Utsusemi: Ichi"` to a slot | The corner shows your Shihei count | [ ] | [ ] |  |
| G2 | Spend them all | The count reads 0 and the slot crosses out | [ ] | [ ] |  |
| G3 | On a job without NIN, view that same slot | No count, no red X | [ ] | [ ] |  |
| G4 | On SCH, bind `ja "Accession"` | The corner shows your stratagem charges | [ ] | [ ] |  |
| G5 | Spend one | The number drops and climbs back over time | [ ] | [ ] |  |
| G6 | Use a weaponskill on a mob | The skillchain indicator appears | [ ] | [ ] |  |
| G7 | Watch a bound weaponskill during that window | Its icon changes to the chain it would make | [ ] | [ ] |  |
| G8 | Let the window lapse | The indicator disappears | [ ] | [ ] |  |

## H. Built-ins

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| H1 | `//hud crossbar draw` | Weapon draws; again and it sheathes | [ ] | [ ] |  |
| H2 | Engage a mob without using `draw` | The bar switches to its drawn rotation | [ ] | [ ] |  |
| H3 | Let the mob die | It stays on the drawn rotation | [ ] | [ ] |  |
| H4 | `//hud crossbar mr` | A five-second countdown prints, then you mount | [ ] | [ ] |  |
| H5 | `//hud crossbar mr` while mounted | You dismount immediately, with no countdown | [ ] | [ ] |  |
| H6 | `//hud crossbar mr`, then `/heal` during the countdown | It cancels and says so | [ ] | [ ] |  |
| H7 | `//hud crossbar mr`, then zone during the countdown | It cancels silently | [ ] | [ ] |  |
| H8 | `//hud crossbar open` | Lists the screens it can open | [ ] | [ ] |  |
| H9 | `//hud crossbar open equipment` | The equipment window opens | [ ] | [ ] |  |
| H10 | `//hud crossbar help` | Prints the command list | [ ] | [ ] |  |
| H11 | If you own a trainer's whistle, run `//hud crossbar mr` a dozen times | It is never picked as a mount | [ ] | [ ] |  |

## I. Warp

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| I1 | With no warp item and no Warp spell, `//hud crossbar warp` | Says what you are missing, rung by rung | [ ] | [ ] |  |
| I2 | Holding an **Instant Warp** only, `//hud crossbar warp` | It is used | [ ] | [ ] |  |
| I3 | Holding a **Warp Ring** in your bag, `//hud crossbar warp` | It equips the ring, waits, then warps | [ ] | [ ] |  |
| I4 | Straight after I3 | Your gear swapping still works normally | [ ] | [ ] |  |
| I5 | Wearing a charged **Warp Ring** already, `//hud crossbar warp` | It warps without a refusal message | [ ] | [ ] |  |
| I6 | Wearing one you just put on, `//hud crossbar warp` | It waits out the warm-up rather than failing | [ ] | [ ] |  |
| I7 | Holding a **Tavnazian Ring** only, `//hud crossbar warp` | It warps after about thirty seconds | [ ] | [ ] |  |
| I8 | On BLM with Warp known and MP, `//hud crossbar warp` | It casts Warp instead of using an item | [ ] | [ ] |  |
| I9 | `//hud crossbar warp all` with another character running XIVHud | Both go home | [ ] | [ ] |  |
| I10 | `//hud crossbar warp`, then `/heal` during the countdown | It cancels, and no alt is sent | [ ] | [ ] |  |

## J. Enchanted gear

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| J1 | `//hud crossbar bind 1 l 6 enchanteditem "<a ring you own>"` | Bound, with the item's own icon | [ ] | [ ] |  |
| J2 | Look at that slot's corner | It shows how many of that item you have | [ ] | [ ] |  |
| J3 | Press it with the ring in your bag | It equips, pauses, then uses it | [ ] | [ ] |  |
| J4 | Straight after J3 | Your gear swapping still works | [ ] | [ ] |  |
| J5 | Press it with the ring already worn and charged | It fires straight away | [ ] | [ ] |  |
| J6 | Press it with the charge spent | It says `no charges left` | [ ] | [ ] |  |
| J7 | Press it while a warp countdown is running | It says something is already in progress | [ ] | [ ] |  |
| J8 | Bind one with a target (`enchanteditem "X" t`) and press with nothing targeted | It refuses rather than firing later | [ ] | [ ] |  |
| J9 | Bind an enchanted item worn somewhere that is **not** a ring — an earring, a cape, a body piece | It equips into the right slot and uses | [ ] | [ ] |  |
| J10 | Straight after J9 | Your gear swapping works, with nothing left locked | [ ] | [ ] |  |

## K. The cast retry (the queue)

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| K1 | `//hud crossbar retry` | Reports it as off | [ ] | [ ] |  |
| K2 | `//hud crossbar retry on` | Reports it as on | [ ] | [ ] |  |
| K3 | Cast two spells back to back from the bar so the second is refused | The refused one goes out again a moment later | [ ] | [ ] |  |
| K4 | Do the same, then immediately press something else | The held spell is dropped, not fired late | [ ] | [ ] |  |
| K5 | Press a spell that is still on recast | Nothing is held — it fails as it always did | [ ] | [ ] |  |
| K6 | Retry a spell aimed at `t`, then tab to another mob | It lands on the first mob, not the new one | [ ] | [ ] |  |
| K7 | Get silenced, then press a spell that is refused | Nothing is retried while silenced | [ ] | [ ] |  |
| K8 | `//hud crossbar retry off` mid-hold | The held spell is dropped | [ ] | [ ] |  |
| K9 | Whatever K3 did, write the game's refusal message **word for word** in the notes | — (this is a reading, not a pass) | [ ] | [ ] |  |
| K10 | Roughly how long after the refusal did the re-send succeed? | — (a rough number in the notes is enough) | [ ] | [ ] |  |
| K11 | Try the same with a job ability, then a weaponskill | Both are retried the way a spell is | [ ] | [ ] |  |

## L. Layout mode

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| L1 | `//hud layout` | Highlight boxes and names appear over each anchor | [ ] | [ ] |  |
| L2 | Count them | Four: main, both WXHB halves, and the indicator | [ ] | [ ] |  |
| L3 | Drag the main box | It moves and snaps to the grid | [ ] | [ ] |  |
| L4 | Drag with CTRL held | It moves freely | [ ] | [ ] |  |
| L5 | Wheel over one box | Only that anchor scales | [ ] | [ ] |  |
| L6 | Right-click a box | The whole crossbar toggles off, then on | [ ] | [ ] |  |
| L7 | Press `;` while in layout mode | Nothing reaches the game and nothing fires | [ ] | [ ] |  |
| L8 | Press `1`–`8` while in layout mode | They reach the game as usual | [ ] | [ ] |  |
| L9 | `//hud layout` again, then reload | Everything is where you left it | [ ] | [ ] |  |

## M. Persistence, jobs, and lifecycle

Leave the job change until here so nothing above has to be redone.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| M1 | `//lua reload xivhud` | The bar returns with every binding intact | [ ] | [ ] |  |
| M2 | Check `data/<Character>/crossbar/` | A `<JOB>.lua` file is there, and `SHARED.lua` | [ ] | [ ] |  |
| M3 | Change job | The bar reloads to that job's own bindings | [ ] | [ ] |  |
| M4 | Look at set 2 (shared, from D9) | Its contents are the same on this job | [ ] | [ ] |  |
| M5 | On this job: `//hud crossbar bind 2 l 4 ma "Dia" t` | Bound into the shared set from the second job | [ ] | [ ] |  |
| M6 | Change back to the first job, look at set 2 slot 4 | Dia is there — sharing carries both ways | [ ] | [ ] |  |
| M7 | Look at set 1 on both jobs | Set 1 still differs per job — only set 2 is shared | [ ] | [ ] |  |
| M8 | `//hud crossbar share 2 off`, then check both jobs | Each job keeps its own set 2 again | [ ] | [ ] |  |
| M9 | `//hud crossbar copy SHARED` | Refused — shared sets belong to no job | [ ] | [ ] |  |
| M10 | `//hud crossbar copy <the other job>` | This job's bindings are replaced wholesale | [ ] | [ ] |  |
| M11 | Watch a cutscene start | The whole HUD hides | [ ] | [ ] |  |
| M12 | Press `;` during the cutscene | It does not open a chat line | [ ] | [ ] |  |
| M13 | Let the cutscene end | The bar comes back, nothing stranded | [ ] | [ ] |  |
| M14 | Zone | It hides while zoning and returns after | [ ] | [ ] |  |
| M15 | Log out to character select | Nothing is drawn | [ ] | [ ] |  |
| M16 | Log back in | The bar returns with this character's bindings | [ ] | [ ] |  |
| M17 | Log in as a different character | That character's own bindings load, and the shared set is that character's own | [ ] | [ ] |  |

## N. Last — destructive

Run these only when everything above is done.

| # | Do this | Passes if | Pass | Fail | What went wrong |
| --- | --- | --- | --- | --- | --- |
| N1 | `//hud hide crossbar` | The bar disappears and its keys go back to the game | [ ] | [ ] |  |
| N2 | `//hud show crossbar` | It returns | [ ] | [ ] |  |
| N3 | `//hud reset crossbar` | Settings and every job's bindings are wiped | [ ] | [ ] |  |
| N4 | `//lua unload xivhud` | No keybind is left broken behind it | [ ] | [ ] |  |

## O. Facts the code is still guessing at

These are not really pass/fail — they are **readings**. Tick Pass if you
managed to look, and put what you saw in the notes. Each one settles a
question the code currently guesses at, listed in
[crossbar-in-client.md](crossbar-in-client.md).

| # | Do this | What I need | Pass | Fail | What you saw |
| --- | --- | --- | --- | --- | --- |
| O1 | Look at an enchanted ring's entry in `res.items` | Does it have a `slots` field, and is it a set, a list, or a number? | [ ] | [ ] |  |
| O2 | Look at `res.bags` | Is there a bag whose name contains `temporary`, and what exactly is it called? | [ ] | [ ] |  |
| O3 | Look at `res.statuses` | Is there an entry whose english name is `Resting`, and what is its id? | [ ] | [ ] |  |
| O4 | Sit with `/heal` and read your own status number | Does it match what O3 said? | [ ] | [ ] |  |
| O5 | Type `/ma "Cure IV"` with a mob selected, then with nothing selected | What happens each time — does it use the target, prompt, or fail? | [ ] | [ ] |  |
| O6 | Type `/item "Echo Drops" <a real mob id>` using a number, not a token | Does the game accept a bare numeric target? | [ ] | [ ] |  |
| O7 | On a job with /COR, try to spend a **master** card (Trump Card) | Can a subjob COR burn one? | [ ] | [ ] |  |
| O8 | If you own a trainer's whistle, look at its name in your key items | Does it start with the same music-note character the mounts do? | [ ] | [ ] |  |

---

## Anything else

Write down anything that felt wrong but has no row above — sluggishness,
a flicker, a message that read oddly, art that looked out of place.
