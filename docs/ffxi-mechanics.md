# FFXI gearing mechanics

How the game handles casting time, recast, haste, accuracy, attack, magic accuracy, enhancing and enfeebling magic, magic damage, Cure, blue magic, weapon skills and the other numbers gear sets are built around. This page records how things work, not which gear any job file uses. It was written while building BLU and RDM job files, so the examples come from those two jobs.

**Sources.** bg-wiki is the main source. Its pages were read directly with curl, as wikitext: `https://www.bg-wiki.com/ffxi/<Title>?action=raw`, or `https://www.bg-wiki.com/api.php?action=parse&page=<Title>&prop=wikitext&format=json` when the raw URL is rate limited. FFXIclopedia was read directly through its API. Rules that came from the player are marked **(player)**. Where sources disagree, both sides are given, and where bg-wiki itself is unsure (estimates, unverified values, talk-page tests) the text says so. Links are at the end.

## Building a set

A checklist for building or changing a set. Each step names the section that has the numbers.

**1. Put each stat in the set that is on when the game reads it.**

| Read when | Set | Stats |
|---|---|---|
| The cast starts | Precast | Fast Cast, and spell- or school-specific casting time (Casting time). Haste here does nothing (Recast) |
| The spell goes off or lands | Midcast | Skill, potency, duration, magic accuracy, magic damage, magic burst damage, Cure potency, enfeebling effect+, spell interruption rate down, the Saboteur hands, Lethargy and Artifact set pieces (Where enhancing gear goes, Where enfeebling gear goes, Where it counts). For physical blue magic: Accuracy, Attack, WSC stats and Chain Affinity and Efflux gear (Blue magic). Also the Fast Cast, haste and Blue magic recast that shorten recast (Recast) |
| Every melee round | Engaged | Accuracy, attack, haste, Dual Wield, Store TP, multi-attack, critical hit rate; tier II enspell damage, every enspell's magic accuracy and "Sword enhancement spell damage +n" (Enspells) |
| The weapon skill goes off | Weapon skill | Everything for that weapon skill, TP Bonus included (Weapon skills) |
| A hit lands on you | Idle, engaged or DT | DT, PDT, MDT, Magic Defense Bonus, evasion, shield block (Damage taken, Defensive skills and shield block) |
| The job ability is used | Job ability | Gear that enhances the ability, such as Azure Lore's duration; general practice, not stated on bg-wiki. Chain Affinity, Burst Affinity and Efflux gear is the exception: it changes the next spell, so it goes in that spell's midcast set (Chain Affinity, Burst Affinity, Efflux and Azure Lore) |
| The spell lands on someone else | The target's own gear | "Received" gear: Phalanx+, the Refresh duration seconds pieces, Cure potency received (Where enhancing gear goes) |

- Fast Cast worn only in precast shortens the cast, not the recast. To shorten recast it has to stay on in midcast (Recast).
- A Quick Magic proc may land the spell in precast gear; not checked against a source (Quick Magic).
- Tier I enspell damage is fixed by the skill worn at the cast, so its skill gear only has to be on while casting (Enspells).

**2. Fill hard caps first, and stop at them.** Anything past a cap does nothing; give the slot to the next stat.

| Stat | Cap | What counts toward it | Section |
|---|---|---|---|
| Casting time | −80% | Fast Cast from traits, job point gifts and gear. Spell- and school-specific casting time shares the cap by bg-wiki; the player disputes this | Casting time; Does anything break the 80% cap? (disputed) |
| Recast | −80% in total | Haste, Fast Cast (half its value, rounded down, so at most 40%), Blue magic recast. The ways past 80% are Scholar-only | Recast cap |
| Gear haste | 256/1024 (25%); about 26% as listed on gear **(player)** | "Haste +X%" on equipment | Haste |
| Magic haste | 448/1024 (43.75%) | Haste, Haste II, Erratic Flutter, marches, Geo-Haste and the like | Haste |
| Job ability haste | 256/1024 (25%) | Haste Samba, Hasso, Desperate Blows | Haste |
| Delay | −80% from all haste and Dual Wield together | Dual Wield past the cap lowers TP per hit and makes rounds no faster | Dual Wield |
| Physical damage taken | −50% | DT + PDT. A shield block, Phalanx and Barrier Tusk still cut damage past it | Damage taken caps |
| Magic damage taken | −50% | DT + MDT. Magic Defense Bonus divides on top and has no known cap | Damage taken caps |
| Breath damage taken | −50% | DT + BDT + augmented MDT | Magic and breath damage |
| All damage reduction | −87.5% | Effects allowed past the 50% caps. RDM and BLU have no DT II gear. Shield block is disputed: bg-wiki's Shield Skill page puts it outside this cap, its Damage Taken page inside | Damage taken caps |
| Melee hit rate | 99% main hand (accuracy = target evasion + 48); 95% off hand (evasion + 40) | Each hand caps on its own | Hit rate and the accuracy cap |
| Physical blue magic hit rate | 95% for a single-hit spell (evasion + 40) | Main-hand weapon accuracy, DEX and Accuracy | Physical blue magic |
| Magic hit rate | 95%, at magic accuracy 45 over the target's magic evasion | All magic accuracy: skill in the spell's school, dSTAT, main-hand Magic Accuracy skill, and Magic Accuracy from gear, traits, job points, merits and food | Magic accuracy formula; Magic hit rate |
| pDIF, one-handed | 3.25 normal and 4.25 critical; RDM 3.35 and 4.35 | Physical damage limit raises the cap | Ratio and pDIF; Physical damage limit |
| Critical hit damage | +100% | Gear, traits and abilities together | Critical hits |
| Subtle Blow, Subtle Blow II | 50% each, 75% together | Gear, plus the Subtle Blow trait from /NIN or /DNC; RDM and BLU have none of their own | Subtle Blow |
| TP Bonus | 3000 effective TP | Actual TP plus all TP Bonus | TP Bonus |
| Cure potency | 50% | All "Cure potency" gear, weapons included (Bunzi's Rod +30%) | Cure potency caps |
| Cure potency II | 30% | Adds on top of Cure potency, outside its 50% | Cure potency caps |
| Cure potency received | 30% | The target's own gear | Cure potency caps |
| Magic burst damage | 40% from gear | Magic burst damage II and the Magic Burst Bonus trait go past it | Burst damage |
| Quick Magic | 10% | Gear, under either item wording: "Occ. quickens spellcasting" and "Quick Magic" | Quick Magic |
| Stoneskin | 350 from skill and MND (skill + 3 × MND = 540); 475 with Stoneskin+ gear | Stoneskin+ adds past 350 | Stoneskin |
| Spell interruption rate down | −102% | Gear plus SIRD merits (−2% a level, up to −10%) | Spell interruption |
| Day & Weather term | ×1.4 | Obi or Hachirin-no-Obi make it apply every time | Day, weather and obis |

Where skill or a stat stops adding potency:

| Spell | Potency stops at | Section |
|---|---|---|
| Phalanx, Phalanx II | 500 enhancing skill (−35). Only the steps count | Phalanx |
| Elemental barspells | 500 (+150) | Gain, Boost and barspells |
| Gain and Boost spells | 500 (+25) | Gain, Boost and barspells |
| Aquaveil | 501 (3 blocks) | Aquaveil |
| Temper II | 700 (40%) | Temper and Temper II |
| Temper, Enspells | no known cap | Temper and Temper II; Enspells |
| Stoneskin | skill + 3 × MND = 540 | Stoneskin |
| Refresh, Regen | Skill does nothing; "Refresh" or "Regen" potency gear first, then duration | Refresh; Regen |
| Haste, Flurry, Protect, Shell, Blink, Sneak, Invisible, bar-status spells | Skill does nothing; build for duration | Spells skill doesn't affect |
| Frazzle III, Distract III | 625 and 610 enfeebling skill, plus +50 dMND | Potency by spell |
| Frazzle II, Distract II | 350 enfeebling skill, plus +50 dMND | What each spell scales with |
| Poison, Poison II | 500 enfeebling skill; Poison II has no known cap | What each spell scales with |
| Slow, Slow II | +75 dMND | What each spell scales with |
| Paralyze, Paralyze II | +40 dMND | What each spell scales with |
| Addle, Addle II | +100 dMND | What each spell scales with |
| Blind, Blind II | +120 dINT | What each spell scales with |
| Elemental nukes | dINT 100 × the spell's tier (500 for tier V) | D: Magic Damage and INT |

- Past these points MND or INT still adds magic accuracy, and effect+ gear still adds enfeebling potency (Choosing a land-rate or potency set).

**3. Check slot, hand and job restrictions.**

- Changing the main, sub or range slot resets TP, so a weapon swap in any set costs all TP (TP reset).
- Main hand only: "Main hand:" effects, native TP Bonus, Magic Accuracy skill, Parrying skill and Ultimate Weapon stats. A weapon's own combat skill, DMG, Enspell damage and critical hit rate count only for that weapon's hits (Which hand a weapon's stats work from).
- A weapon in the sub slot needs Dual Wield (RDM gets it only from /NIN or /DNC); a shield or a grip doesn't (Dual Wield).
- Leth. Earring +1 and Hashi. Earring +1 work only in the right ear (Gear and GearSwap).
- Ullr in the range slot needs the ammo slot empty or holding an arrow. This is general game behavior; no bg-wiki page read states it (Which hand a weapon's stats work from).
- Rare items allow one copy, such as Earthcry Earring and the Dual Wield accessories.
- The tables mark which pieces RDM or BLU can't wear. Check the job before placing a piece.
- Two identical unaugmented copies are safest swapped as a pair; a set wearing both should not directly follow a set wearing one (Gear and GearSwap).

**4. Look up the piece.**

- `docs/gear-notes.md` records what an item's text and the export don't show: hidden values, set bonuses, conditions and slot or hand restrictions.
- `docs/rank-augments.md` gives path items' augments at every rank, from bg-wiki's rank tables. `//gs export` shows the path but not the rank, so a rank has to come from the player. The character's `data/<Character>/<Character>_rank_augments.md` gives the path and rank of each of the character's copies, with the augments at that rank. A copy that exports with no augments is rank 0, with base stats only. When a rank isn't recorded, ask the player.
- The character's `data/<Character>/<Character>_notes.md` records what else only the player knows: the player's rules for the sets, the merits, job points, Master Levels and nation, and what the formulas here give at those values. Merits matter in many places below. RDM's Group 2 merits (Accuracy, Magic Accuracy, Enhancing and Enfeebling Magic Duration, Immunobreak Chance, En-spell Damage) share 10 levels in all, at most 5 per category (bg-wiki, Merit Points), so the levels in one category come out of another's.
- Values that guides or bg-wiki quote at rank 30 overstate an Odyssey piece below that rank (Odyssey augments below rank 30).
- bg-wiki's simulated sets are a starting point, not an answer. They assume Odyssey gear at rank 30 and Nyame Path B at rank 25. Each weapon skill and nuke set is scored by one damage number with no DT or utility; the TP sets by time to the weapon skill under a DT limit. Put in the character's own ranks before copying a piece ("Simulated sets (bg-wiki All Jobs Gear Sets)").
- wsdist, the simulator behind those sets, can compare two sets, but it has known formula and item-data errors; correct them before trusting a number ("wsdist (Kastra's damage simulator)").

**5. Apply the player's priorities.** They are in the character's notes, `data/<Character>/<Character>_notes.md`, under "Rules for these sets".

## Casting time

### What goes where

| Stat | What it shortens | Set it must be in | Cap |
|---|---|---|---|
| Fast Cast (traits, job point gifts, gear) | Casting time by its %; recast by half its %, rounded down | Precast for casting time. Midcast as well if it is to shorten recast | 80% casting time, so at most 40% recast |
| Spell- or school-specific casting time (Cure, Healing, Song, Enhancing, Stoneskin, Blue magic, Enfeebling) | Casting time of that spell or school only; never recast | Precast | Shares the 80% with Fast Cast by bg-wiki; disputed, see below |
| Haste (gear and magic) | Recast only | Midcast | 80% recast in total |
| Blue magic recast −X% | Blue magic recast only | Midcast (inferred) | 80% recast in total |
| Quick Magic | Chance of an instant cast with no recast | See Quick Magic | 10% activation rate |

### Fast Cast

- Fast Cast shortens casting time by its percentage. All sources add together: job traits, job point gifts and gear.
- Casting time reduction caps at 80% (bg-wiki, Fast Cast).
- Casting time is set when the cast starts, so for casting time, Fast Cast only has to be worn in the precast set. bg-wiki says it can be swapped out before the spell goes off and still shortens the cast. Recast is different; see Recast.
- After a spell finishes, a fixed 3-second delay blocks spells, abilities and items. Fast Cast doesn't shorten it (bg-wiki, Casting Time Gauge). At the 80% cap, Cure IV's 2.5-second cast takes 0.5 seconds, so the next action can start 3.5 seconds after the cast began (bg-wiki, Cure IV). Fast Cast gains less on short spells than its percentage suggests.

| Source | Fast Cast |
|---|---|
| RDM trait, Fast Cast I to V (levels 15, 35, 55, 76, 89) | 10, 15, 20, 25, 30% |
| RDM job point gifts, Fast Cast VI to IX (150, 500, 1125 and 2000 job points spent) | 2% more each: 32, 34, 36, 38%. Each also shortens recast by 1%, which is half its 2% through the recast formula, not extra: 38% gives 19% recast (Recast) |
| RDM as subjob (/RDM) | 15% below Master Level 30, 20% from Master Level 30 |
| BLU trait from set blue magic, tiers 0 to IV | 5, 10, 15, 20, 25% |

- A mastered RDM has Fast Cast IX, 38% before gear, so 42% from gear reaches the cap. A RDM short of 2000 job points needs 2% more from gear for each missing tier (bg-wiki, Red Mage).
- /RDM: subjob level is 49 + floor(main job Master Level ÷ 5), up to 59. Fast Cast III (20%) comes at subjob level 55, so it needs Master Level 30. Below that, /RDM gives Fast Cast II (15%) and 65% from gear reaches the cap (bg-wiki, Support Job and Fast Cast).

### BLU's Fast Cast trait

- BLU has no Fast Cast of its own. It gets the trait from set blue magic. Each tier takes 8 trait points: Erratic Flutter gives 8, and Bad Breath, Sub-zero Smash, Auroral Drape and Wind Breath give 4 each. Points past a multiple of 8 do nothing.
- The Job Trait Bonus gifts, at 100 and 1200 BLU job points spent, each raise the tier by one (bg-wiki, Blue Mage Job Traits). Tier III needs the 100 gift and tier IV needs both.

| Trait points from set spells | No gifts | 100 gift | Both gifts |
|---|---|---|---|
| 8 (Erratic Flutter alone, or two of the 4-point spells) | 5% | 10% | 15% |
| 16 | 10% | 15% | 20% |
| 24 (all five) | 15% | 20% | 25% |

- bg-wiki hedges how the gifts work ("seems to" add 8 points), and its Fast Cast page footnotes the tiers differently. The tier changes with the spell set, so check the job traits list in game.
- A trait from set blue magic doesn't stack with the same trait from the subjob. Only the higher tier applies (bg-wiki, Blue Mage Job Traits). On BLU/RDM below Master Level 30, /RDM already gives 15%, so Fast Cast blue magic only helps at tier III (20%) or IV (25%). From Master Level 30, /RDM gives 20% and only tier IV helps.
- At Master Level 25 a BLU's /RDM is level 54 and gives 15% (Combat skill). Master Levels mean job mastery, so such a BLU has both gifts (Job points and merits): 16 trait points of Fast Cast spells give 20%, and all five give 25%.

### Fast Cast the item text doesn't show

Some item text only says `Enhances "Fast Cast" effect`, with no number. A scan of item descriptions misses these pieces. bg-wiki gives the values in each item's notes:

| Item | Fast Cast | RDM | BLU |
|---|---|---|---|
| Augur's Gaiters | 3% | yes | no |
| Chelona Boots / +1 | 4% / 5% | yes | yes |
| Swith Cape / +1 | 3% / 4% | yes | yes |
| Estoqueur's Earring | 2% | yes | no |
| Witful Belt | 3% (also Haste 31/1024, Quick Magic 3%) | yes | yes |

- The +1 values come only from bg-wiki's Fast Cast equipment table. That table is incomplete (it leaves out Atrophy Chapeau +4, Vitiation Tabard +4, Amalric Coif +1 and Leth. Earring +1) and marks some values unverified (Ebon, Ebur and Furia Talar 5%, Euxine Gloves, Tethyan Cap, Pi Ring). Read each item's own page.
- Fi Follet Cape +1 (back, RDM and BLU) gets Fast Cast from its rank augment: +1% a rank up to 5% at rank 5, then +1% every second rank up to 10% at rank 15. From rank 6 it also adds Spell interruption rate −1 to −5%. Its base stats are MP +45, Enhancing magic skill +9 and Conserve MP +5 (bg-wiki, Fi Follet Cape +1).

### Spell-specific and school casting time

Separate stats shorten the casting time of one spell or one school of magic. For casting time, each adds one for one with Fast Cast: 1% Cure spellcasting time is worth 1% Fast Cast on a Cure (bg-wiki, Category:Cure Spell). None of them shortens recast; bg-wiki says so for Song spellcasting time, Blue magic spellcasting time and Elemental Celerity. They belong in precast sets only.

- "Cure spellcasting time −X%". Some pieces that have it: Doyen Pants −15%, Vanya Clogs (Path D) −15%, Pahtli Cape −8%, Serenity (augmented) −8%, Vanya Cuffs (Path B) −7% and Mendi. Earring −5%. Of these, Vanya Clogs, Vanya Cuffs and Serenity are RDM-only; Doyen Pants, Pahtli Cape and Mendi. Earring fit BLU too (bg-wiki, each item's page). Serenity is a staff, which needs both hands, so swapping it in resets TP. The values come from the item pages, since the Cure page's own table leaves out Doyen Pants and Mendi. Earring. Serenity's and Vanya Cuffs' values weren't checked against bg-wiki, only their jobs. It belongs in the precast set a Cure spell wears: under Selindrile's framework, `sets.precast.FC.Cure`, which a spell whose map is a Cure or Curaga wears when no set is named for the spell itself ([frameworks/sel.md](frameworks/sel.md#how-sel-picks-a-set)).
- "Healing magic casting time −X%" is broader: all healing magic, including Cures, Raise and the -na spells (bg-wiki, Category:Healing Magic). RDM can wear Heka's Kalasiris −15%, Iaso Bliaut −5% and Paean Bliaut −2%. Vejovis Wand +1 −4% and Vejovis Wand −3% fit RDM and BLU; they are clubs, so swapping one in resets TP. bg-wiki's three tables disagree on Heka's Kalasiris (Cure spellcasting time 15%, Healing magic casting time −15%, or Fast Cast 5%).
- "Song spellcasting time −X%". Doyen Pants has −6%.
- "Enhancing magic casting time −X%" covers every enhancing spell. The only piece for RDM or BLU is Siegel Sash −8%; the other gear with it is RUN-only (bg-wiki, Category:Enhancing Magic).
- "Blue magic spellcasting time −X%" works like the same % of Fast Cast for blue magic only. bg-wiki says the only gear with it is Hashishin Mintan, +1, +2 and +3 (−13, −14, −15 and −16%), Mavi Mintan +1 and +2 (−6 and −12%) and Iris (−7%). Mintan +3 in place of Luhlaza Jubbah +1 (Fast Cast 7%) is a net +9% for blue magic casting time (bg-wiki, Hashishin Mintan +3 and Category:Blue Magic).
- "Enfeebling magic casting time −X%". RDM pieces: Lethargy Chappel, +1, +2 and +3 (−14, −15, −16 and −17%), Estoqueur's Chappel +1 and +2 (−8 and −12%) and Wikyo Cloak (−7%) (bg-wiki, Category:Enfeebling Magic).
- "Stoneskin casting time −X%". Stoneskin's base cast is 7 seconds (bg-wiki, Stoneskin). The pieces:

| Piece | Slot | Stoneskin casting time | RDM | BLU |
|---|---|---|---|---|
| Umuthi Hat | head | −15% | yes | no |
| Carapacho Cuffs | hands | −15% | yes | no |
| Pukulatmuj +1 / Pukulatmuj | sword | −11% / −10% | yes | yes |
| Doyen Pants | legs | −10% | yes | yes |
| Querkening Brais | legs | −10% | yes | disputed |
| Siegel Sash (Enhancing magic casting time) | waist | −8% | yes | yes |

- RDM's most is 51% (Pukulatmuj +1, Umuthi Hat, Carapacho Cuffs and one pair of legs), or 59% with Siegel Sash. BLU's most is 21% (Pukulatmuj +1 and Doyen Pants), or 29% with Siegel Sash.
- Doyen Pants and Querkening Brais share the legs slot. bg-wiki's Stoneskin table lists BLU for Querkening Brais but its item page doesn't; it changes nothing for BLU, since Doyen Pants takes the slot.
- Pukulatmuj is a weapon. Swapping it in for precast resets TP.

Light Arts and Dark Arts are different. Light Arts, a level 10 SCH ability usable from a SCH subjob, shortens white magic casting time and recast by 10% and lengthens black magic casting time and recast by 20% (bg-wiki, Light Arts). Dark Arts does the reverse. Its own page gives the values as approximate and names only casting time for the white magic penalty; the Community Scholar Guide says the penalty is +20% to both casting time and recast for either Arts.

- Whether Light Arts' 10% counts inside the 80% casting time cap is not settled. The Cure page lists it among the effects that share the cap; if so, RDM/SCH under Light Arts has 38% + 10% = 48% before gear for white magic, and 32% from gear reaches the cap. The Scholar gear pages treat the Arts term as a separate multiplier.

### Does anything break the 80% cap? (disputed)

- **(player)** School and spell-specific casting time gear breaks the 80% Fast Cast cap.
  - **(player, 2026-10-02)** Leave this as it is, with both positions shown.
- **bg-wiki** says they share the 80% cap with Fast Cast. Every page that states a cap agrees:
  - The Cure page: Cure spellcasting time, Healing magic casting time, Light Arts and Fast Cast together can't pass the 80% hard cap.
  - The Song Spellcasting Time page: song spellcasting time and Fast Cast share the 80% cap. It cites no test.
  - The Enfeebling Magic page: enfeebling casting time reduction adds to Fast Cast and doesn't break the 80% cap.
  - The Elemental Celerity page (BLM and GEO trait): it counts toward the 80% cap and doesn't shorten recast. This is the only one of these statements backed by a cited test, of the trait combined with Fast Cast.
  - The Blue Magic page doesn't say either way.
  - The only stat bg-wiki puts past 80% is Scholar's "Grimoire: Spellcasting time" (Pedagogy Mortarboard +3 −13%, Academic Loafers +3 −12%). It is SCH-only gear and works as a separate multiplier in the Scholar ability term, up to 90%, only for spells that match the active Arts, and not under Celerity, Alacrity, Accession or Manifestation. RDM and BLU can't wear any gear that bg-wiki says goes past 80%.
- Under bg-wiki's reading, spell-specific casting time adds nothing to a precast set that already reaches 80% with Fast Cast. It only helps by replacing a Fast Cast piece in a set that would otherwise fall short.
- A precast set that reaches 80% with Fast Cast alone, and adds spell-specific pieces only in slots that cost no Fast Cast, is correct under either reading.

### Quick Magic

- Quick Magic gives a chance to cast any magic instantly with no recast: songs, ninjutsu, summoning and blue magic included. Its activation rate caps at 10% (bg-wiki, Occasionally Quickens Spellcasting).
- Item text names it two ways: `Occ. quickens spellcasting +X%` and `"Quick Magic"+X%`. A scan for Quick Magic pieces has to search for both.
- With GearSwap, an instant cast can go off before the midcast set is on, so the spell may land in precast gear. This is common GearSwap advice, not checked against a source. The only bg-wiki statement found, in the Community Scholar Guide, says that without add-on "tools" you likely won't get the full benefit of precast and midcast sets when Quick Magic procs, and that Quick Magic gear does best in a set that serves as both. It doesn't describe GearSwap's behavior.

Quick Magic gear RDM or BLU can wear (bg-wiki, Occasionally Quickens Spellcasting):

| Piece | Quick Magic | Also |
|---|---|---|
| Weather. Ring +1 | 4% | Fast Cast 6% |
| Weather. Ring | 3% | Fast Cast 5% |
| Perimede Cape | 4% | |
| Witful Belt | 3% | Fast Cast 3%, Haste 31/1024 |
| Ogapepo Cape +1 / Ogapepo Cape | 3% / 2% | |
| Moonshade Earring (augmented) | 3% | |
| Lebeche Ring | 2% | |
| Impatiens | 2% | |
| Veneficium Ring | 1% (2% in Legion) | |
| Dalmatica +1 (RDM) | 1 to 3% by augment | Fast Cast up to 6% |
| Dalmatica (RDM) | 1 to 2% by augment | |

## Recast

bg-wiki, Spell Recast:

```
Recast = initial recast
       × (1 − Haste/1024 + Slow/1024)
       × (1 − floor(Fast Cast % / 2) / 100)
       × job ability modifiers (Composure, Hasso, Scholar abilities)
```

- The terms multiply. The haste term covers magic and equipment haste (and Slow); bg-wiki doesn't name job ability haste in it.
- Fast Cast shortens recast by half its value, rounded down to a whole percent. 80% Fast Cast gives 40% recast. The floor applies to the total, so an odd total wastes half a point: 38% + 3% = 41% still gives 20%.
- The Fast Cast trait and job point gifts shorten recast too, all the time. A mastered RDM's 38% gives 19% recast with no gear; midcast Fast Cast gear adds 1% recast per 2%, up to 42% from gear.
- **(player)** For recast, 2% Fast Cast is worth 1% haste. This matches the formula.
  - From bg-wiki's formula: because the terms multiply, a point off one term is worth the value of the other term. 2% Fast Cast and 1% haste (about 10/1024) are equal only when the two terms are equal. Example: under Haste II (307/1024) with 10% gear haste, the haste term is about 0.60; with only RDM's 38% trait, the Fast Cast term is 0.81. Then 1% more gear haste cuts recast about 1.3 times as much as 2% more Fast Cast, until gear haste caps.
  - **(player, 2026-10-02)** Leave this as it is.
- Gear haste shortens recast but not casting time. Haste lowers recast by an amount that depends on its source (bg-wiki, Attack Speed). No source read lists haste among the things that shorten casting time, so haste gear belongs in midcast sets, not precast.
- Recast is set when the spell goes off, so the haste and Fast Cast in the **midcast** set are what count. bg-wiki (Spell Recast, Fast Cast) and FFXIclopedia both say Fast Cast gear has to stay equipped through the cast to shorten recast. Fast Cast that is only in the precast set speeds up the cast, not the recast. A midcast set trades recast against potency and accuracy pieces. bg-wiki states the stay-equipped rule for Fast Cast; for haste it follows from the same timing.

### Recast cap

- Recast reduction caps at 80% in total (recast × 0.2).
- The ways past 80% are all Scholar-only, so for RDM and BLU the cap is 80%. Spell Recast names Celerity or Alacrity with Argute or Pedagogy Loafers under matching weather, up to 90%. The Celerity page names any version of the relic feet with no weather condition. The Pedagogy Mortarboard +3 and Academic Loafers +3 pages say Light Arts with Grimoire gear reaches 90%.
- Chainspell, Spontaneity and Quick Magic leave the spells they affect with no recast at all (bg-wiki, Chainspell, Spontaneity and Occasionally Quickens Spellcasting).
- Spell Recast doesn't say whether the attack-speed haste caps (gear 256/1024, magic 448/1024) also bound its haste term. An old level-75-era page (bg-wiki, Haste: In Depth by Kirschy) says equipment plus magic haste can cut recast by at most 50%, with Fast Cast applied on top of that. The current Spell Recast page gives only the overall 80%. Unverified; if it still holds, a BLU under Haste II or Erratic Flutter (about 30%) gets no more recast from midcast gear haste past about 20%.
- FFXIclopedia's Fast Cast page still gives older caps: recast 50%, and 25% from Fast Cast. bg-wiki's 80% and 40% are current.

### Other recast modifiers

- Composure multiplies the recast of all magic by 1.25 while it is active (bg-wiki, Composure); FFXIclopedia adds that this covers songs and ninjutsu. It lasts 2 hours with a 5-minute recast, so a RDM that keeps it up has every recast ×1.25, and midcast haste and Fast Cast are worth more for recast. It is one of the job ability modifiers in the formula. A RDM subjob can't use it.
- Light Arts and Dark Arts: their −10% for their own school sits in the Scholar job ability term, a separate multiplier from the haste and Fast Cast terms, so it doesn't count against Fast Cast's 40% (bg-wiki, Spell Recast). Celerity and Alacrity (−40%) sit in the same term. Under Light Arts, black magic recast is ×1.2 (bg-wiki, Light Arts). The 80% overall cap still applies.
- "Blue magic recast −X%" shortens the recast of all blue magic and stacks with haste and Fast Cast (bg-wiki, Category:Blue Magic). bg-wiki says the only gear with it is Hashishin Bazubands, +1, +2 and +3 (−13, −14, −15 and −16%) and Mavi Bazubands +1 and +2 (−6 and −12%). BLU only. bg-wiki doesn't say when it is read; by analogy with Fast Cast's recast part it should be worn at midcast, but that is an inference.
- The Community Blue Mage Guide says 40% Fast Cast from traits and midcast gear caps blue magic recast, given capped gear and magic haste and Hashishin Bazubands +3. By the formula: (1 − 704/1024) × 0.80 × 0.84 = 0.21, about 79%. That assumes the Bazubands' −16% is its own multiplier and that the attack-speed haste caps apply to recast; neither is stated. Past that point about 1% is left to the cap.
- Gear with both Fast Cast and haste, such as Witful Belt (Fast Cast 3%, Haste 31/1024), helps recast through both terms if it stays on in the midcast set (bg-wiki, Witful Belt).

## Haste and Dual Wield

Haste and Dual Wield shorten the delay between attack rounds, so for melee they belong in the set worn while engaged. For spells, haste only shortens recast (see Recast).

### Haste

Haste comes in three kinds. Each is counted in 1/1024 units and capped on its own (bg-wiki, Attack Speed):

| Kind | Cap | Sources |
|---|---|---|
| Gear | 256/1024 (25%) | "Haste +X%" on equipment |
| Magic | 448/1024 (43.75%) | Haste 150/1024 (14.6%), Haste II 307/1024 (30%), Hastega 153/1024, Hastega II 30%; BLU spells Erratic Flutter (gives Haste II, 307/1024), Animating Wail 15%, Mighty Guard 15% (unverified on its own page) and Refueling 10%; Bard marches, Indi-/Geo-Haste, Embrava |
| Job ability | 256/1024 (25%) | Haste Samba, Hasso, Desperate Blows |

```
delay after haste = delay × (1024 − gear − magic − JA) ÷ 1024      (each term no higher than its cap)
```

- Haste past a kind's cap does nothing. Unlike extra Dual Wield, it doesn't cost anything either.
- **(player)** In practice, the haste listed on gear has to add up to about 26% to reach the cap. Haste past that does nothing.
  - bg-wiki (Attack Speed) agrees and gives the reason: the 1/1024 value behind gear haste is usually a little under the listed percent (Witful Belt's 3% is 31/1024). It calls this well verified on gear, but a few pieces round up, so 26% is a rule of thumb rather than an exact threshold.
- Magic haste you actually receive picks the column of the Dual Wield table below. Self Haste II or Erratic Flutter alone is the 30% column. Bard and Geomancer buffs fall in ranges: Advancing March about 10.6 to 19%, Victory March 15.9 to 28.6%, Honor March 12.3 to 17%, Indi-/Geo-Haste 2.4 to 40.9%, Embrava up to 25.9%. All of it shares the one 448/1024 cap.
- Haste Samba gives job ability haste to anyone who hits the dazed target: 51/1024 (5%), or up to 101/1024 (10%) from a main-job Dancer with merits. DNC learns it at 45, so /DNC can use the 5% version (bg-wiki, Haste Samba).
- All delay reduction (every kind of haste, Dual Wield and Martial Arts) shares an 80% cap:

```
(1 − DW%) × (1024 − gear − magic − JA) ÷ 1024 ≥ 0.20
```

- Capped gear and magic haste leave 320/1024 (31.25%) of the delay. Dual Wield or job ability haste has to close the rest of the gap to 20%.
- Haste also shortens spell recast. It doesn't shorten casting time, so haste in a precast set does nothing for a spell (see Recast). Spell Recast doesn't say whether the caps above also limit its haste term.

### Dual Wield

A weapon in the sub slot needs the Dual Wield trait (bg-wiki, Dual Wield):

| Tier | I | II | III | IV | V | VI |
|---|---|---|---|---|---|---|
| Delay reduction | 10% | 15% | 25% | 30% | 35% | 40% (disputed) |

- Tier VI: the Dual Wield page now gives 40%, from the Japanese wiki. It said about 37% for years, and Blue Mage Job Traits still says 37%.
- RDM has no Dual Wield of its own. It needs /NIN (DW III, 25%, from NIN 45) or /DNC (DW II, 15%, from DNC 40). On any other support job the sub slot holds a shield or nothing.
- Thief has Dual Wield of its own, from level 83, and tier III (25%) from 98, so a level 99 Thief dual wields on any support job (FFXIclopedia, Thief, through a search extract).
- Support job level = 49 + floor(Master Level ÷ 5): 53 at Master Level 20 to 24, 54 at 25 to 29. DW IV needs NIN 65 and DW III needs DNC 60, so Master Level doesn't raise either tier (bg-wiki, Master Levels).
- BLU gets Dual Wield from set blue magic: up to DW IV from the spells alone, V and VI with the job point gifts (bg-wiki, Blue Mage Job Traits). It doesn't stack with the support job's Dual Wield; the higher tier applies. BLU/NIN already has DW III, so blue magic Dual Wield only matters at DW IV or higher. The tier changes with the spell set, so check the job traits list in game. The spells and their trait points are under Traits from set spells.

Dual Wield cuts the two weapons' combined delay:

```
delay per hand = (main delay + sub delay) × (1 − DW%) ÷ 2
```

- Both hands swing at this delay, even when the weapons' delays differ. Naegling (240) with Thibron (238) is 179.25 per hand at 25% Dual Wield and 152.96 at 36%.
- TP per hit comes from this lower delay, so more Dual Wield means less TP per hit (see TP gain and Store TP).
- Dual Wield past the 80% delay cap lowers TP per hit without making rounds any faster. Cap haste first, then wear only the gear Dual Wield the table calls for.

Gear Dual Wield needed to reach the 80% cap, assuming capped gear haste (bg-wiki, Dual Wield). Columns are the magic haste received:

| Trait Dual Wield | 0% | 10% | 15% | 30% | capped |
|---|---|---|---|---|---|
| 10% (DW I) | 64 | 60 | 57 | 46 | 26 |
| 15% (DW II, /DNC) | 59 | 55 | 52 | 41 | 21 |
| 25% (DW III, /NIN) | 49 | 45 | 42 | 31 | 11 |
| 30% (DW IV) | 44 | 40 | 37 | 26 | 6 |
| 35% (DW V) | 39 | 35 | 32 | 21 | 1 |
| 40% (DW VI) | 34 | 30 | 27 | 16 | 0 (4 over) |
| 15% plus Haste Samba from /DNC (5%) | 57 | 52 | 49 | 35 | 9 |
| 25% plus Haste Samba from /DNC (5%) | 47 | 42 | 39 | 25 | 0 |

- With gear haste under the cap, more Dual Wield is needed than the table shows. For any haste total, solve the 80% rule for Dual Wield:

```
gear DW needed = 1 − 0.2 × 1024 ÷ (1024 − gear − magic − JA) − trait DW
```

Dual Wield gear on bg-wiki's Dual Wield page that RDM and BLU can wear, with each item's jobs checked on its own page:

| Slot | Item | Dual Wield |
|---|---|---|
| Waist | Reiki Yotai | +7 |
| Waist | Shetal Stone | +6 |
| Ring | Haverton Ring +1 | +6 |
| Ring | Haverton Ring | +5 |
| Ear | Suppanomimi | +5 |
| Ear | Eabani Earring | +4 |
| Back | the job's Ambuscade cape, augmented | +1 to +10 |
| Body | Adhemar Jacket +1 (BLU, not RDM) | +6 |
| Head | Thurandaut Chapeau +1 (BLU, not RDM) | +5 |

- The accessories are all Rare, so one of each. Sarashi gives Dual Wield +1 only on /NIN.
- RDM's level 99 total is about 37: one waist (7), both Haverton rings (6 and 5), both earrings (5 and 4) and the cape (10).
- Dual Wield gear the Dual Wield page doesn't list wasn't checked.

## TP gain and Store TP

TP per melee hit comes from the delay after Dual Wield (bg-wiki, Tactical Points). It is read on every hit, so Store TP belongs in the engaged set.

| Delay D (after Dual Wield) | Base TP per hit |
|---|---|
| 180 or less | 61 + (D − 180) × 63/360 |
| 181 to 540 | 61 + (D − 180) × 88/360 |
| 541 to 630 | 149 + (D − 540) × 20/360 |
| 631 to 720 | 154 + (D − 630) × 28/360 |
| 721 to 900 | 161 + (D − 720) × 24/360 |
| over 900 | 173 + (D − 900) × 28/360 |

```
TP per hit = floor(floor(base TP) × (100 + Store TP) ÷ 100)
```

- Naegling alone (240) gives 75 TP a hit. Naegling with Thibron gives 60 a hit at 25% Dual Wield and 56 at 36%. 56 with Store TP +18 is floor(56 × 1.18) = 66.
- Store TP has no known cap (bg-wiki, Store TP).
- Tactical Points writes the rounding as floor(base TP) + floor(base TP × Store TP ÷ 100). The two forms can differ by 1 TP a hit.
- Store TP also raises the TP gained from being hit. Tactical Points states this as fact; the Store TP page rests it on one observation.
- Outside weapon skills, every hit of a multi-attack proc gives full TP. During a weapon skill most hits give a flat 10 TP, so Store TP does little in a weapon skill set (see TP from a weapon skill).
- The Store TP trait gives +10, +15, +20, +25 and +30 at tiers I to V. RDM has none. SAM gets tiers I to III at 10, 30 and 50, so /SAM at 53 or 54 gives Store TP +20, but no Dual Wield. BLU gets it from set blue magic, so its tier changes with the spell set and job point gifts (see Blue magic).
- Store TP on Bunzi's Hat and Gleti's Gauntlets is a rank augment. A rank 0 copy has none of it (rank-augments.md has every rank).

## Multi-attack

Double, Triple and Quadruple Attack are rolled on melee rounds and on weapon skills, so they belong in both the engaged set and weapon skill sets.

- Checks run in a fixed order: Virtue, Raetic and Su4/Su5 follow-up weapons first, then Quadruple Attack (+3 hits), Triple Attack (+2), Double Attack (+1), "Occasionally attacks X times" (+1 to +7), then Hasso and Zanshin. Once a higher check procs, that weapon gets no lower check that round (bg-wiki, Category:Multi-Attack).
  - So Double Attack is worth a little less when stacked with high Quadruple or Triple Attack.
  - Mythic Aftermath Level 3's extra attacks (twice 40% of the time, thrice 20%) are a fifth-order check, so a Double, Triple or Quadruple Attack proc replaces them that round; the category page says Double Attack interferes with Mythic Aftermath for this reason. A Double Attack proc then adds 1 hit where Level 3 would have added 0.8 on average (0.4 × 1 + 0.2 × 2, taking the two rates as one roll), so under Level 3 Double Attack is worth about a fifth of its usual value on that hand; Triple and Quadruple Attack keep more of theirs. That figure is arithmetic from the two pages, not a sourced one (bg-wiki, Category:Multi-Attack and Mythic Aftermath).
- Dual Wield and multi-attack together are limited to 8 hits per round.
- On weapon skills, Double, Triple and Quadruple Attack can all proc. Double Attack can proc at most twice per weapon skill, and so can Triple Attack, within the 8-hit limit. When dual wielding, each hand rolls separately (bg-wiki, Double Attack and Triple Attack).
  - Extra hits matter most on fTP-replicating weapon skills, where they carry the full fTP (see Weapon skills).
- "Occasionally attacks X times" procs on weapon skills only from Mythic AM3 (bg-wiki, Category:Multi-Attack). wsdist rolls it on every weapon skill, so it overrates OA off hands there, such as Kraken Club, Blurred Knife +1 and Demersal Degen +1 (see Where wsdist and bg-wiki disagree).
- BLU gets Double Attack (7%) from set blue magic. Setting enough for a second tier gives Triple Attack (5%, from BLU 92) instead of Double Attack. A /WAR support job gives a higher Double Attack rate than the spell trait: WAR has tier I (10%) at 25 and tier II (12%) at 50, so /WAR at 53 or 54 gives 12% (bg-wiki, Double Attack and Blue Mage Job Traits).
- RDM's own multi-attack comes from Temper and Temper II (see Enhancing magic).
- THF has Triple Attack of its own: 5% from level 55 and 6% (tier II) from 95, plus 1% a level of its Triple Attack Rate merit (Group 1, up to 5) and 2% at each of 125, 450, 1050 and 1900 job points spent, 19% in all (bg-wiki, Triple Attack and Thief).

Quadruple Attack has no job trait; it comes only from gear. Pieces RDM or BLU can wear (bg-wiki, Quadruple Attack):

| Item | Jobs | Quadruple Attack |
|---|---|---|
| Crepuscular Knife | RDM | 5% |
| Twilight Knife | RDM | 3%, that knife's own hits only |
| Bunzi's Hat | RDM | 3% at rank 30, from its augment; none at rank 0 |
| Zantetsuken | BLU | 3% |
| Thaumas Coat | BLU | 3% |
| Enif Corazza | BLU | 2% |
| Euxine Coat +2 / +3 | BLU | 1% / 2% |
| Windbuffet Belt / +1 | both | 1% / 2% |
| Balder Earring +1 | both | 1% |

- Quadruple Attack procs on either hand when dual wielding, except Twilight Knife's.
- Odyssey pieces get some of their multi-attack from rank. Nyame Path B's Double Attack starts at rank 16. Bunzi's Hat's Quadruple Attack, Gleti's Cuirass's Double Attack and Gleti's Breeches' Triple Attack are rank augments, so a rank 0 copy has none. Bunzi's Gloves keep their base Double Attack +8% at rank 0 (bg-wiki, Bunzi's Gloves; rank-augments.md has every rank).

## Critical hits

Critical hit rate is rolled per hit, so it belongs in the engaged set and in the sets for weapon skills that can crit (bg-wiki, Critical Hit Rate).

```
melee crit rate = 5% base + gear (0 to 100%) + merits (0 to 5%) + buffs + weapon skill modifier + dDEX bonus (0 to 15%)
```

- There is no cap; enough gives a critical on every hit. The rate only takes whole percentages.
- Critical hit rate on a weapon counts only for that weapon's own hits (bg-wiki, Dual Wield).

dDEX = your DEX − the target's AGI:

| dDEX | Critical hit rate |
|---|---|
| 0 to 6 | +0% |
| 7 to 13 | +1% |
| 14 to 19 | +2% |
| 20 to 29 | +3% |
| 30 to 39 | +4% |
| 40 to 50 | +(dDEX − 35)% |
| 50 and up | +15% |

- DEX only buys much critical rate when it pushes dDEX into the 40 to 50 band. Elsewhere, each 1% takes 6 to 10 dDEX.

Weapon skills:

- A weapon skill can only crit if its description says the chance of a critical hit varies with TP, or an effect enables it. Chant du Cygne, Vorpal Blade and Evisceration can crit. Savage Blade, Black Halo, Expiacion and Requiescat can't, so critical hit rate and critical hit damage gear does nothing in their sets.
- bg-wiki notes exceptions: some "varies with TP" weapon skills don't get base or gear critical rate (Blade: Rin).

Critical hit damage:

- Critical hit damage is (base damage + fSTR) × critical pDIF, raised by the direct modifiers. Those ("Crit. hit damage +X%", Critical Attack Bonus and the like, from abilities, traits, gear and atma) add together and cap at +100% in total.
- The Critical Attack Bonus trait gives +5, +8, +11 or +14% by tier, on melee hits and weapon skills, inside that +100% cap. BLU gets +5% from setting Sinker Drill, +8% with the 100 job point gift and +11% with the 1,200 job point gift. RDM doesn't get it (bg-wiki, Crit. Atk. Bonus).

## Subtle Blow

Subtle Blow cuts the TP an enemy gets from your hits, so it works from the set worn when the hit lands (bg-wiki, Subtle Blow).

```
enemy TP per hit = monster TP gain × (monster Store TP − Inhibit TP) × (1 − SB − SB II)
```

- Subtle Blow and Subtle Blow II each cap at 50%, and together at 75%. Past 50% of one kind, only the other kind helps.
- It also cuts the TP enemies get from your damaging spells.
- RDM and BLU have no Subtle Blow trait. The tiers are 5, 10, 15, 20 and 25%. NIN gets them at 15, 30, 45, 60 and 75; DNC at 25, 45, 65, 86 and 99 (80 job points). At support level 53 or 54, /NIN gives 15% and /DNC 10%.
- Subtle Blow II comes from level 99 gear, Siren's Avatar's Favor and BST's Tandem Blow. bg-wiki's gear list (whether RDM or BLU can wear each piece wasn't checked):

| Item | Subtle Blow II |
|---|---|
| Moonbow Belt +1 | 15 |
| Moonbow Belt | 10 |
| Dagon Breastplate | 10 |
| Sherida Earring | 5 |
| Niqmaddu Ring | 5 |
| Mpaca's Hose | 5 |
| Ikenga's Hat | augment, up to 5 |
| Gleti's Knife | augment, +1 from rank 21 to +10 at rank 30; none at rank 0 |

- Gleti's Knife's Subtle Blow II and Gleti's Breeches' Subtle Blow are rank augments, so a rank 0 copy has neither (rank-augments.md has every rank).

## Damage taken

Damage taken stats count when the hit lands, so they go in whatever set is worn then: idle, engaged or a DT set (bg-wiki, Damage Taken).

Evasion, parrying and shield block are under Defensive skills and shield block.

### Damage taken caps

- Damage taken caps at −50%. Physical damage counts DT + PDT and magic damage counts DT + MDT, each capped at 50%. Anything past the cap does nothing.
- Breath damage counts DT + BDT + augmented MDT, also capped at 50% (see below).
- All damage reduction together caps at −87.5%, including the effects allowed past the 50% caps (bg-wiki, Damage Taken). Shield block is disputed: bg-wiki's Shield Skill page says block reduction isn't held by the −87.5% cap; the Damage Taken page puts every source that passes the other caps under it.
- "Damage taken II" stats (PDT II, MDT II and the like) apply on top of the 50% caps, up to −87.5%. Every DT II item found on bg-wiki is for other jobs (PLD and RUN weapons and shields, and Domain Invasion items for other jobs). For RDM and BLU, −50% is the ceiling on DT + PDT and DT + MDT from gear.
- These still cut damage in a set already at −50%:
  - A shield block (see Shield block).
  - Phalanx, whose flat reduction comes after damage taken gear (bg-wiki, Phalanx).
  - BLU's Barrier Tusk, −15% applied after damage taken gear and past the 50% cap (bg-wiki, Barrier Tusk).
  - Magic Defense Bonus, against magic (see below).

### Magic and breath damage

```
magic damage taken = floor(damage × (1 − MDT% − DT%)) ÷ (1 + MDB ÷ 100)
```

- The (1 − MDT − DT) term stops at 50%. Magic Defense Bonus divides separately and has no known cap, so once DT + MDT reach −50%, MDB is the stat that still lowers magic damage.
- The Magic Defense Bonus trait gives RDM +10, +12 and +14 at 25, 45 and 96. BLU gets tiers I to III from set blue magic, and IV and V with the job point gifts. The same trait from main and support job doesn't stack. MDB doesn't reduce breath damage (bg-wiki, Magic Defense Bonus).

```
breath damage taken = damage × (1 − BDT% − DT% − augmented MDT%)      (the term can't go below 0.5)
```

- Ordinary MDT gear doesn't reduce breath damage; most, if not all, augmented MDT does. bg-wiki notes that little testing has been done.
- So a set that reaches −50% magic through ordinary MDT can fall short against breath attacks.

## Skill and accuracy

Accuracy and attack come from the gear on when the hit happens: the engaged (TP) set for melee rounds, the weapon skill set for weapon skill hits. Each hand has its own accuracy and attack, because each uses the skill of the weapon type it holds.

### Combat skill

A hand's combat skill is the sum of:

- the job's skill at level 99 for that weapon type (table below);
- +1 per Master Level, for skills the job learns natively. Only mastered jobs earn Master Levels (bg-wiki, Master Levels, which words it as +1 to the skill cap);
- +2 per Combat Skills merit level, up to 8 levels (+16, 21 merit points). Merits are kept across jobs, so sword merits count on both RDM and BLU (bg-wiki, Merit Points);
- the weapon's own `<type> skill +N`. Only item-level weapons have it;
- `<type> skill +N` and "Combat skills +N" on armor.

RDM, BLU and THF job point gifts add no combat skill; they add flat accuracy, attack and evasion instead (see Accuracy from set bonuses and abilities).

| Skill at 99, before Master Levels and merits | RDM | BLU | THF |
|---|---|---|---|
| Sword | 398 (B) | 424 (A+) | 334 (D) |
| Dagger | 398 (B) | none | 424 (A+) |
| Club | 334 (D) | 388 (B−) | 300 (E) |
| Evasion | 334 (D) | 368 (C−) | 424 (A+) |
| Parrying | 300 (E) | 334 (D) | 417 (A) |
| Shield | 265 (F) | none | 265 (F) |

(bg-wiki, Red Mage, Blue Mage and Thief.) Master Level 50 adds 50 (RDM sword 448, BLU sword 474). Job mastery itself adds no combat skill. On RDM a club hand starts 64 below a sword or dagger hand; on BLU, 36 below; on THF a sword hand starts 90 below a dagger hand.

- Each Master Level adds 1 to every skill in the table: at Master Level 25, RDM sword and dagger are 423 and BLU sword 449, before merits and the weapon's own skill. Master Levels also add +1 to every base stat per level, and the support job is level 49 + floor(Master Level ÷ 5), 54 at Master Level 25 (bg-wiki, Master Levels).
  - Only a mastered job earns Master Levels, so a job with any Master Level is mastered: 2,100 job points spent. Each job has 10 categories at 210 points each, so that is every category at 20 and every gift (arithmetic, as under Job points and merits).
- Combat Skills merits add +2 a level, up to 8 levels (+16) a skill. Skill at Master Level 25 with 8/8 merits, before the weapon's own skill and gear (level 99 + 25 + 16; accuracy from skill by the bands below):

| Master Level 25, 8/8 merits | RDM | BLU |
|---|---|---|
| Sword | 398 + 25 + 16 = 439 (411 accuracy) | 424 + 25 + 16 = 465 (432) |
| Dagger | 398 + 25 + 16 = 439 (411) | none: BLU has no dagger skill, so dagger merits do nothing there |
| Club | 334 + 25 + 16 = 375 (357) | 388 + 25 + 16 = 429 (403) |

Weapon-type skill on item-level weapons (bg-wiki, each weapon's page):

| Weapon | Skill |
|---|---|
| Tizona (Level 119 III) | Sword +269 |
| Almace | Sword +242 at Level 119 and 119 II, +269 at 119 III |
| Naegling | Sword +250 |
| Colada, Pukulatmuj +1, Malignance Sword | Sword +242 |
| Tauret | Dagger +250 |
| Gleti's Knife | Dagger +255 |
| Maxentius | Club +250 |
| Bunzi's Rod | Club +242 |
| Thibron | none (level 99, no item level) |

- Each of these also has the same amount of Parrying skill.
- These are base stats, so a rank 0 copy has them. The rank augments of Bunzi's Rod and Gleti's Knife add DMG; MAB (Rod) or Attack (Knife); Accuracy and Magic Accuracy from rank 16; Enmity − (Rod) or Subtle Blow II (Knife) from rank 21; never skill (rank-augments.md).
- Only Level 119 III ultimate weapons take Oboro's augments, which `//gs export` shows as "Path: A". A Tizona that exports "Path: A" is 119 III (bg-wiki, BGWiki:Ultimate Weapon Augments).
  - The export prints the same "Almace" for nine stages, Level 80 up to 119 III, so it doesn't show which one a character has (gear-notes.md, Almace). Only the item-level stages have Sword skill (+242 or +269); the Level 99 stage has none (bg-wiki, Almace (Level 99)). Check its item text before counting any.
- Item-level 119 swords run from Sword skill +215 (Tokko Sword) to +277 (Caliburnus III) (bg-wiki, Category:Sword).
- The in-game Skills menu leaves the weapon's own skill out. It still counts toward attack (bg-wiki says so outright) and toward accuracy (implied by the same page and by Item Level) (bg-wiki, Attack).

Accuracy from combat skill (bg-wiki, as pasted by the player; matches bg-wiki, Accuracy):

| Skill | Accuracy from skill |
|---|---|
| up to 200 | skill |
| 201 to 400 | floor((skill − 200) × 0.9) + 200 |
| 401 to 600 | floor((skill − 400) × 0.8) + 380 |
| 601 and up | floor((skill − 600) × 0.9) + 540 |

- So a point of skill on gear is worth 0.8 accuracy for a hand at 401 to 600 skill, and 0.9 past 600. Find the hand's real skill total first. Flat Accuracy+ is always 1 for 1.
- Combat skill also adds to attack (see Attack). bg-wiki's formula adds it one point for one point, but the same page says skill converts to attack in tiers like accuracy and gives no tier values, so 1 for 1 is not settled (bg-wiki, Attack).
- "Combat skills +N" raises every combat skill at once, defensive ones included: Combatant's Torque +15 (with Store TP +4), Hoxne Torque +30 (with Magic skills +30 and Slow +5%, which costs haste).

Which hand a weapon stat helps is under Which hand a weapon's stats work from (Weapons and TP). In short, a weapon's own `<type> skill` helps only that weapon's hits, while Accuracy, Attack and base stats on either weapon help both hands. Tizona's Path A augments work only with Tizona in the main hand.

- A combat skill only helps attacks with that weapon type. Sword skill gear does nothing while a club is in hand. With a club in one hand and a sword in the other, club skill gear helps only the club's hits and sword skill gear only the sword's.
- bg-wiki doesn't say outright whether "Sword skill +N" on armor reaches the off hand when both weapons are swords. The worked numbers below assume it does.

### Sword skill past 600 (disputed)

- **(player)** At Master Level 25, BLU and RDM sword skill is past 600. Each point of sword skill on gear is then worth about 0.9 accuracy and 1 attack, so Sword skill +30 is about Acc +27 and Att +30.
- **bg-wiki** puts the cause on the weapon, not the Master Level:
  - Without the weapon's own skill, RDM sword at Master Level 25 with 8/8 merits is 398 + 25 + 16 = 439, and BLU's is 424 + 25 + 16 = 465. Both are below 600 (bg-wiki, Category:Combat Skills).
  - An item-level weapon puts its hand past 600. Even the lowest item-level 119 sword (+215) takes a RDM with no Master Levels to 613.
  - A weapon with no item level, such as Thibron, leaves the hand at 439 (RDM) or 465 (BLU), in the 0.8 band.
- Both readings agree for the hand that holds an item-level weapon: there, Sword skill +30 (Hashishin Kavuk +3) is about Acc +27. BLU at Master Level 25 with 8/8 sword merits, Naegling hand: 424 + 25 + 16 + 250 = 715 → 745 skill, 643 → 670 accuracy from skill (+27). The same +30 on a Thibron hand: 465 → 495 skill, 432 → 456 (+24). Attack +30 depends on the unsettled 1-for-1 rate above.
- Main hand and off hand can end up far apart. RDM at Master Level 25 with 8/8 sword merits, Naegling and Thibron: Naegling hand 398 + 25 + 16 + 250 = 689 skill (620 accuracy from skill), Thibron hand 439 (411), so the off hand is 209 accuracy behind. No armor closes that. An item-level off-hand sword does: with the same Master Level and merits, Almace gives an off hand of 708 skill (637) at Level 119 III (+269), or 681 (612) at 119 or 119 II (+242). Both figures assume an Almace of at least Level 119; a lower stage adds no skill, like Thibron.
- These figures use 8/8 sword merits (Combat skill).
- The worked numbers here use Master Level 25 (Combat skill). The **(player)** line under Enhancing skill gives 480 enhancing skill at Master Level 24; at 25 that count is 481.

### Accuracy

bg-wiki, Accuracy:

```
Accuracy = floor(DEX × 0.75)
         + accuracy from skill (that hand's weapon type, table above)
         + Accuracy from traits, abilities, gear, food and buffs
```

- DEX gives 3 accuracy per 4 DEX, worked out on total DEX, for every weapon class since July 2013 (bg-wiki, Dexterity). A DEX+X piece is worth about 0.75 × X accuracy, less than Accuracy+X in the same slot.
- Each Master Level adds +1 DEX (about 0.75 accuracy) along with its +1 skill (bg-wiki, Master Levels).
- Accuracy doesn't show on the status or equipment screens. `/checkparam <me>` shows it (FFXIclopedia, Accuracy). Ask the player for `/checkparam` numbers in the set rather than adding up gear by hand.

### Hit rate and the accuracy cap

bg-wiki, Hit Rate:

```
Hit rate % = 75 + floor((Accuracy − target Evasion) ÷ 2) − 2 × dLVL
dLVL = target level − your level, only in zones with level correction
```

| Hit | Hit rate cap | Accuracy that reaches it, no level correction |
|---|---|---|
| One-handed weapon, main hand | 99% | target evasion + 48 |
| One-handed weapon, off hand | 95% | target evasion + 40 |
| Two-handed weapon | 95% | target evasion + 40 |
| Ranged | 95% (99% under Sharpshot) | target evasion + 40 |

- The accuracy column is worked out from the formula; bg-wiki doesn't print it. Past these points accuracy does nothing for melee hits.
- Each hand caps on its own, with its own skill. A skill-less off-hand weapon such as Thibron can fall well short even though its goal is 8 lower.
- Below the cap, 2 accuracy is 1% hit rate. Hit rate takes whole numbers only, so one odd point of accuracy can change nothing.
- Melee hit rate never drops below 20%.
- FFXIclopedia still gives 95% as the cap for everything. bg-wiki's 99% for a main-hand one-handed weapon is current.
- wsdist gives +0.5% hit rate for every accuracy point, unfloored, with no level term. The average per point is the same, so it only misleads when aiming at an exact accuracy target or in a level-corrected zone (see Where wsdist and bg-wiki disagree).

Level correction:

- It costs 2% hit rate per level, the same as 4 accuracy. bg-wiki, Level Difference Penalty, says it starts when the enemy is 2 or more levels above you (since March 2013); the Hit Rate page's formula counts from 1 level. No bonus is confirmed for outleveling the target. Neither page says whether Master Levels count as your level.
- Many zones have none: Adoulin areas, Escha Zi'Tah, Escha Ru'Aun, Reisenjima, Ambuscade and Legion (Maquette Abdhaljs-Legion), Odyssey and high-tier battlefields (Walk of Echoes [P]), East Ulbuka, the zones that hold Apex and Locus monsters (such as Crawlers' Nest [S], Bhaflau Thickets, King Ranperre's Tomb and Bibiki Bay), and a growing list of Voracious Resurgence and Peculiar Foes zones. Content level 100+ fights in old zones are level 99 enemies with bonus stats, so no penalty there either (bg-wiki, Level Difference Penalty).
- For endgame targets, leave the level term out and gear against the target's evasion.

Finding the target's evasion:

- `/check` on a monster that isn't a notorious monster: "Low Evasion" means your accuracy is at least 10 above its evasion (80% or more); "High Evasion" means more than 30 below it (under 60%). Swapping gear until the message changes gives its exact evasion. This doesn't work on NMs (bg-wiki, Accuracy).
- From a parse: extra accuracy needed ≈ (desired hit rate − current hit rate) × 2. bg-wiki calls it an estimate only.

Lowering the target's evasion works like adding accuracy to both hands. Distract III (RDM, job point spell at 550 JP) takes off floor((6/21) × (enfeebling skill − 190)) + floor(dMND ÷ 5), with the dMND term held to 0 to 10: 120 at 610 skill, capped at 130 before enfeebling potency gear. While it is up, the main-hand goal drops from evasion + 48 to as low as evasion − 82 (bg-wiki, Distract III).

- wsdist's Distract III toggle is a flat −280 evasion. That fits only a normal monster under Saboteur with potency gear; an NM test measured 132 to 152 (Potency by spell), so wsdist overstates hit rate against bosses (see Where wsdist and bg-wiki disagree).

### Accuracy from set bonuses and abilities

- Artifact set bonus: Atrophy (RDM) and Assimilator's (BLU) +2, +3 and +4 pieces, with Regal Earring counting as a piece, give Accuracy, Ranged Accuracy and Magic Accuracy +15, +30, +45 and +60 for 2, 3, 4 and 5 pieces worn. It counts the pieces on at that moment. Which pieces count: see Artifact set bonus (bg-wiki, Category:Reforged Artifact Armor +3).

Other sources:

| Source | Accuracy | Notes |
|---|---|---|
| Composure (RDM) | +50 at level 99, plus 1 per level of the Composure Effect job point category, up to +70 | floor((24 × level + 74) ÷ 49) (bg-wiki, Composure) |
| RDM job point gifts | +3, +5, +6, +8 at 45, 320, 845, 1620 JP spent: +22 | Always on (bg-wiki, Red Mage) |
| BLU job point gifts | +5, +8, +10, +13 at 30, 280, 780, 1530 JP spent: +36 | Always on (bg-wiki, Blue Mage) |
| THF job point gifts | +5, +8, +10, +13 at 30, 280, 780, 1530 JP spent: +36 | Always on, ranged accuracy too. THF has no Accuracy Bonus trait (bg-wiki, Thief) |
| RDM Group 2 merit, Accuracy | +5 per level, up to 5 levels (+25) | Shares the group's 10 levels with Enfeebling and Enhancing Magic Duration, Magic Accuracy, Immunobreak Chance and En-spell Damage (bg-wiki, Merit Points). |
| Accuracy Bonus trait | +10, +22, +35, +48, +60, +73 for tiers I to VI | Also ranged accuracy. See below |
| Aggressor (/WAR) | +25, with Evasion −25 | 3 minutes, 5-minute recast; no longer ranged accuracy (bg-wiki, Aggressor) |
| Blade Madrigal (bard) | +60 at +0 song gear to +114 at +9 | +5 per Madrigal merit after the percentage; Marcato ×1.5, Soul Voice ×2 (bg-wiki, BGWiki:SongPotency) |
| Sword Madrigal (bard) | +45 at +0 to +85 at +9 | As above |

- The job point gift tiers are listed one by one. bg-wiki doesn't say they add up; the +22 and +36 totals assume they do, as it does for the capacity point gifts.
- THF's other combat gifts, by job points spent: Attack +7, +11, +14, +18 at 10, 210, 660, 1360 (+50); Triple Attack +2% at 125, 450, 1050 and 1900 (+8%, see Multi-attack); Dual Wield Effect, 5% less delay, at 550; Critical hit damage +2% at 150, 500, 1125 and 2000 (bg-wiki, Thief).
- Accuracy Bonus trait (bg-wiki, Accuracy Bonus and Blue Mage Job Traits):
  - RDM has none of its own. As a support job at level 53 or 54 (49 + floor(Master Level ÷ 5)), /DNC and /DRG give tier I (+10; tier II needs 60) and /RUN tier I.
  - BLU gets it only from set blue magic, up to tier IV, with tiers V and VI from job point gifts. Each tier needs 8 trait points. Spells (set points / trait points): Dimensional Death 5/4, Frenetic Rip 3/4, Disseverment 5/4, Vanity Dive 2/4, Nature's Meditation 6/8, Anvil Lightning 8/8.
  - The Job Trait Bonus gifts at 100 and 1200 JP seem to add 8 trait points to each set trait (bg-wiki hedges this), but a trait needs its first 8 points from spells. With 1200+ JP, the cheapest sets are 5 set points for tier III (+35, Frenetic Rip and Vanity Dive), 11 for IV, 19 for V and 29 for VI. With no Accuracy Bonus spell set, BLU gets nothing.
  - A BLU's spell tier and the support job's tier don't add; the higher applies.
  - Tier VI is +73 on the Accuracy Bonus page and +72 on Blue Mage Job Traits.
- Madrigal: one Blade Madrigal lowers the accuracy a set needs by 60 to 119; with Sword Madrigal too, by 105 to 209 before Marcato or Soul Voice. Category:Madrigal's own note (potency cap 60, "+59" with Marcato) doesn't match the SongPotency table.

### Accuracy from food

bg-wiki, Category:Accuracy Food:

| Food | Accuracy | Also |
|---|---|---|
| Sublime Sushi +1 | +11% (cap 105) | DEX +8, STR +7 |
| Sublime Sushi | +10% (cap 100) | DEX +7 |
| Oceanfin Soup | +15% (cap 95) | Attack +19% (cap 85) |
| Prime Marine Stewpot | +95 flat | Ranged Accuracy and Magic Accuracy +95 |
| Marine Stewpot | +90 flat | Ranged Accuracy and Magic Accuracy +90 |
| Miso Soup +1 | +11% (cap 45) | |
| Grape Daifuku | +10% (cap 80) | Attack +10% (cap 50), STR +2, VIT +3, Magic Atk. Bonus +3 (bg-wiki, Grape Daifuku) |
| Oden | +15% (cap 70) | DEX +5, INT +5, Magic Accuracy +15% (cap 70) (bg-wiki, Oden) |

- Percentage food multiplies total accuracy after every other source, up to its cap (FFXIclopedia, Accuracy; bg-wiki gives the percentages and caps but not how they apply). It pays its full cap only once accuracy before food reaches: Sublime Sushi +1 955, Sublime Sushi 1000, Oceanfin Soup 634, Grape Daifuku 800, Oden 467.
- Oden's DEX +5 adds 3 or 4 more accuracy, so at the caps it gives 6 or 7 less accuracy than Grape Daifuku and no Attack, but 70 more magic accuracy (Magic accuracy food).
- Grape Daifuku is the food bg-wiki's simulated sets assume (Buffs, under Simulated sets). Crepe B. Helene, a magic accuracy food, adds no Accuracy: INT +2, Magic Accuracy +21% (cap 50), Magic Def. Bonus +1 (bg-wiki, Crepe B. Helene).
- Above 955, Sublime Sushi +1 is worth about 111 (105, plus about 6 from DEX +8). Below those totals the flat Stewpots can give more, and they add magic accuracy for sets that must also land spells.

## Attack and pDIF

What decides gear: below the attack cap, a percent of attack is about a percent of physical damage. Once the ratio caps, more attack does nothing, and physical damage limit (PDL), weapon skill damage and critical hit damage are what still add damage.

### Attack

bg-wiki, Attack:

```
Attack (main hand, ranged) = 8 + combat skill + STR
Attack (off hand)          = 8 + combat skill + floor(STR ÷ 2)
```

- STR counts 1 for 1 for main-hand and ranged weapons since December 2018, and half for off-hand hits, including the extra off-hand hit on a weapon skill.
- Combat skill is that hand's total, weapon's own skill included (see Combat skill).
- Flat attack:
  - Attack Bonus trait: +10, +22, +35 and +48 for tiers I to IV; V (+60) and VI (+72) come only from job point gifts. BLU reaches tier IV with set blue magic. RDM has none of its own. With the support job at level 54 (Master Level 25), /DRK gives tier III (+35; IV needs 70) and /WAR tier I (+10; II needs 65). On BLU the spell tier and the support job's tier don't add; the higher applies (bg-wiki, Attack Bonus and Blue Mage Job Traits).
  - BLU job point gifts: Attack +10, +15, +20, +25 at 10, 210, 660, 1360 JP spent (+70 if they add up) (bg-wiki, Blue Mage).
  - Sroda Ring: Attack and Ranged Attack +10 per trust in the party, worked out per hit and not shown in `/checkparam`. It also has STR +15, DEX −20 and PDL +3% (bg-wiki, Sroda Ring).
- Percentage attack:
  - Berserk (WAR): +25% (64/256) and Defense −25%. The bonus grows 5/256 at WAR levels 50, 60, 70, 80 and 90, to 89/256 (about 35%). A level 54 /WAR (Master Level 25) would have 69/256 (about 27%) if the steps use the support job's level; bg-wiki doesn't say (bg-wiki, Berserk).
    - wsdist gives /WAR a flat 25%, about 2% short if the steps do count (see Where wsdist and bg-wiki disagree).
  - Warcry (WAR): floor(WAR level ÷ 4 + 4.75) ÷ 256, from the level of the job that uses it: 29/256 (about 11.3%) at 99, 18/256 (about 7.0%) from a level 54 /WAR (floor(13.5 + 4.75) = 18). It doesn't snapshot; it scales with the gear worn. bg-wiki says this for Warcry only (bg-wiki, Warcry).
  - Nat. Meditation (BLU): +20% (52/256) for 90 seconds. Stacks with Berserk and Warcry (bg-wiki, Nat. Meditation).
  - Oceanfin Soup: +19% (cap 85).
  - With a percentage buff up, each flat Attack+ on gear is worth that much more, and the cap comes sooner.
- STR also adds base damage through fSTR: about (STR − target VIT + 4) ÷ 4 once the gap is 12 or more. fSTR caps at Weapon Rank + 8, where Weapon Rank = floor(weapon DMG ÷ 9) counting DMG augments, reached at STR − VIT = (14 + 2 × rank) × 2. Naegling (DMG 166) is rank 18, so its fSTR caps at 26 at STR 100 above the target's VIT. Past that, STR adds only attack and weapon skill modifiers (bg-wiki, FSTR and Weapon Rank).

### Ratio and pDIF

bg-wiki, PDIF:

```
ratio  = your attack ÷ target defense
cRatio = ratio − 0.05 × (target level − your level)   melee; ranged −0.025 a level; only with level correction
wRatio = cRatio + 1 on a critical hit, cRatio on a normal hit
pDIF   = random between a lower and an upper limit set by wRatio, then clipped to the cap
damage = floor(floor(base damage × pDIF) × random 1.00 to 1.05)
```

- The upper limit is wRatio + 0.375 from wRatio 1.5; the lower limit is wRatio − 0.375 from wRatio 2.44. The caps below are before the 1.00 to 1.05 randomizer.
- Target defense = base defense × (1 − (Dia + Box Step + Defense Down + Frailty)), at least 1. Those four add together, but Defense Down effects (Angon, Acid Bolt, weapon skill and blue magic effects) don't stack with each other. Defense down lowers the attack needed to cap by the same percentage (bg-wiki, Defense Down).
- wsdist adds every defense-down toggle together, Angon, Armor Break, Corrosive Ooze and Swooping Frenzy included. Turn on at most one of those four (see Where wsdist and bg-wiki disagree).
- Level correction generally doesn't apply in content added after 2013 (Adoulin, Ambuscade, Escha, Reisenjima). Where it does, bg-wiki disagrees with itself: PDIF subtracts it from the ratio before the cap, so attack can make it up; Level Difference Penalty lists −5% melee pDIF per level and cites tests suggesting the ratio is capped before correction.

One-handed weapons (dagger, sword, axe, katana, club), level 99:

| | Normal hit | Critical hit |
|---|---|---|
| Base cap, BLU | 3.25 | 4.25 |
| RDM, with its Damage Limit+ I trait | 3.35 | 4.35 |

- The effective ratio cap is the cap + 0.375: 3.625 for the base 1H cap, about 3.725 for RDM. There even the lowest roll reaches the cap. Attack needed to fully cap ≈ 3.625 × target defense after defense down (RDM about 3.725 ×), plus 0.05 × defense per level the target is above you where correction applies.
- Returns start to shrink near a ratio of 2.875, where the highest roll first reaches the cap (derived).
- bg-wiki marks this pDIF model as incomplete. It notes a later validated upper limit of wRatio + 0.25, which would move 2.875 to 3.0, and says no model explains average pDIF (bg-wiki, PDIF and Talk:PDIF).
- Below the cap, raising attack by a percent raises damage by about that percent: a bit more on normal hits, less on crits (bg-wiki, Byrth's WS Damage Guide; its 2012 cap values are outdated).
- Weapon skill damage, critical hit damage, Critical Attack Bonus and similar bonuses are assumed to apply after pDIF, so the pDIF cap doesn't limit them (bg-wiki, Byrth's WS Damage Guide).
- A critical hit adds 1.0 to the ratio, and the crit caps are 1.0 above the normal ones, so without PDL both cap at the same ratio. PDL multiplies the bigger crit cap by more (×1.20 turns RDM's 3.35 and 4.35 into 4.02 and 5.22), so with PDL, crits need a higher ratio to cap (derived; untested).
- wsdist adds the crit's +1 twice: to the ratio, and again to pDIF after clipping at the normal cap. At cRatio 1.5 a one-handed crit averages 3.5 pDIF in wsdist against 2.5 here (+40%), and the two meet only at a ratio of 3.625. So wsdist overvalues crit rate for Chant du Cygne, Evisceration and melee crits (see Where wsdist and bg-wiki disagree).
- The crit cap matters only for melee crits and weapon skills that can crit: Chant du Cygne, Vorpal Blade and Evisceration. Which weapon skills can crit, and the +100% cap on critical hit damage: see Critical hits.

### Physical damage limit

```
pDIF cap = (weapon type base cap + Damage Limit+ trait)
         × (1 + listed PDL % from gear and effects, added together)
         × (1 + augmented PDL %)
```

- PDL raises only the cap, not pDIF. It is worth nothing until pDIF reaches the cap, then it is the main gain (bg-wiki, PDIF).
- Damage Limit+ trait: +26/256 (about +0.10) per tier, added to the cap. RDM gets tier I at 60. BLU can't get it, not even from blue magic. It also applies to physical and hybrid weapon skills (bg-wiki, Damage Limit+).
- Support jobs that have it at level 54 (Master Level 25): WAR, SAM (40), BST, PUP, DNC (45), THF and NIN (50) give tier I; DRK gives tier II (+51/256, about +0.20) at 40. bg-wiki doesn't say how a support job's tier combines with the main job's. If only the higher counts, BLU/DNC or BLU/NIN would cap at 3.35 and 4.35 and RDM/DRK at 3.45 and 4.45 (unverified).
- Listed PDL on gear adds together into one multiplier. Augmented PDL (JSE neck augments, and probably the Nyame Path A and Bunzi's Robe augments) multiplied separately on top in player tests. The tests were on capped ranged damage; the crit test was inconclusive, and melee is assumed to work the same (bg-wiki, Talk:Damage Limit+).
- wsdist adds all PDL, listed and augmented, into one (1 + PDL). Unsettled, and small: 14% listed with a 6% neck is ×1.20 in wsdist against ×1.208 (see Where wsdist and bg-wiki disagree).
- Prime Aftermath and Aria of Passion multiply the cap too.
- bg-wiki's Damage Limit+ gear table is incomplete; check the item's own page.

| Item | PDL | Jobs | Kind |
|---|---|---|---|
| Malignance head, body, hands, legs, feet | 3, 6, 4, 5, 2% (20% for 5) | RDM, BLU | listed |
| Gleti's Mask, Cuirass, Gauntlets, Breeches, Boots | 6, 9, 7, 8, 5% (35% for 5) | BLU, not RDM | listed |
| Ephramad's Ring | 10%, with STR, DEX and AGI +10 and Accuracy and Attack +20 | all | listed |
| Telopanos Saber, Daduchos Saber, Auge Saber | 5, 4, 3% | Telopanos: RDM, BLU, COR | listed |
| Crepuscular Pebble (ammo) | 3% | all | listed |
| Sroda Ring | 3% | RDM, BLU | listed |
| Nyame, Path A only | up to 7% (body) at rank 30 | RDM, BLU | augment |
| Bunzi's Robe | 1% at rank 1, up to 8% at rank 29 and 30 | WHM, RDM, BRD, SMN | augment |

- Gleti's PDL is a base stat, so a rank 0 Gleti's piece has it in full. It has none of the rank augments: Attack and a piece-specific line from rank 1 (Counter, Double Attack, Store TP, Subtle Blow, Evasion), Accuracy and Magic Accuracy from rank 16, and a fourth line from rank 21 (Regen, status resistance, DEX, Triple Attack, STR). rank-augments.md has the values.
- Bunzi's Robe's PDL is a rank augment, so a rank 0 copy has none. Nyame Path B adds Attack, weapon skill damage and Double Attack, and no PDL at any rank. Per-rank values for both are in rank-augments.md.
- Worked caps (derived): RDM in five Malignance pieces, 3.35 × 1.20 = 4.02, which needs a ratio near 4.4 to fill. BLU in five Gleti's pieces, 3.25 × 1.35 ≈ 4.39, near a ratio of 4.76.

## Defensive skills and shield block

Evasion and shield block work whether or not you are engaged, so they count in idle sets. Parrying and Guard only work while engaged.

### Evasion

bg-wiki, Evasion:

```
Evasion = floor(AGI ÷ 2) + evasion from skill + Evasion from traits, abilities and gear
Evasion from skill = skill, up to 200; floor((skill − 200) × 0.9) + 200 above it
```

- Evasion works against attacks from any direction.
- Evading melee caps at 80%, the attacker's 20% floor. Evading ranged attacks has no cap.
- Evasion+N on gear is worth N; Evasion skill +N about 0.9 × N. Evasion skill is rare on current gear (bg-wiki, Evasion Skill).
- bg-wiki only assumes the skill bands follow accuracy: testing showed 0.9 per point above 255, and the page leaves out accuracy's 0.8 band for 401 to 600.
- Evasion skill at 99: BLU 368, RDM 334, +1 per Master Level and up to +16 from merits. BLU job point gifts add Evasion +5, +8, +10, +13 at 20, 245, 720, 1445 JP (+36).

### Parrying and Guard

- Parrying works only while engaged, against attacks from the front. Its formula, and how skill feeds into it, are unknown. On most content the parry rate sits at its 5% floor, and skill would take hundreds of points to matter. Flat parry-rate effects such as Inquartata raise it; BLU can get Inquartata from set blue magic (Saurian Slide) (bg-wiki, Parrying Skill and Inquartata).
- Only the main-hand weapon's Parrying skill counts. Parrying skill at 99: RDM 300 (E), BLU 334 (D).
- Parrying skill on armor (for example Atro. Gloves +4 +22, Assim. Bazu. +3 +19, Eurus' Ledelsens +8) is worth nothing in idle sets and next to nothing while engaged. Value those pieces for their other stats.
- Guard skill works only with a hand-to-hand weapon while engaged, and only MNK and PUP have it. "Guarding skill +N" (Boxer's Mantle +10) does nothing on RDM or BLU (bg-wiki, Guard Skill).

### Shield block

bg-wiki, Shield Skill:

```
Block rate %      = size base rate + (your shield skill − attacker's combat skill) × 0.2325
Block reduction % = size reduction + shield DEF ÷ ((max(item level, 99) − 99) ÷ 10 + 2)
Damage            = (base damage − Shield Def. Bonus) × (1 − block reduction) × (1 − PDT)
```

| Shield size | Base block rate | Size reduction |
|---|---|---|
| 1 | 55% | 20% |
| 2 | 40% | 40% |
| 3 | 45% | 50% |
| 4 | 30% | 65% |

- A shield blocks physical attacks from the front, engaged or not.
- The DEF divisor is 4 for item level 119 shields and 2 for shields with no item level. Only the shield's own listed DEF and its augments count.
- 10 shield skill is about 2.3 points of block rate. 0.2325 is an average; the real tiers are unknown (0.25 at some skill levels, 0.2 at others).
- PDT here is PDT + DT from gear, capped at 50%. The block reduction applies on top of it, so a shield cuts physical damage further even when a set is already at the 50% cap. Whether it is held by the −87.5% total cap is disputed: bg-wiki's Shield Skill page says no, its Damage Taken page says the total cap covers everything (see Damage taken caps).
- Shield Def. Bonus is a PLD, WAR and WHM trait, so that term is 0 on RDM (bg-wiki, Shield Def. Bonus).
- RDM shield skill is 265 (F) at 99, +1 per Master Level, up to +16 from merits, plus the shield's own skill and gear: Boxer's Mantle +10, Buckler Earring +3, Combatant's Torque +15. BLU has no shield skill, so a shield on BLU gives only its other stats.
- Shield Mastery (RDM; I at 87, +10 TP per block; II at 97, +20 TP): a blocked physical hit doesn't interrupt a spell. If the enemy hits more than once during the cast, every hit has to be blocked. A shield in the sub slot while casting gives a chance to cast through melee hits; dual wielding gives that up (bg-wiki, Shield Mastery).

Shields RDM can use, worked out from the item pages and the formulas above (BLU can equip none of the first three):

| Shield | Size | DEF | Shield skill | Base block rate | Blocks of a hit | Damage cut at equal skill | Other |
|---|---|---|---|---|---|---|---|
| Forfend +1 | 1 | 142 | +107 | 55%, or 60% if its "Chance of successful block +5" adds 5 points (unknown) | 55.5% | 30.5 to 33.3% | PDT −4% |
| Archduke's Shield | 2 | 110 | +102 | 40% | 67.5% | 27.0% | Refresh +1 |
| Ammurapi Shield | 1 | 94 | +107 | 55% | 43.5% | 23.9% | magic stats |
| Genbu's Shield | 1 | 24, no item level | none | 55% | 32% | 17.6% | PDT −10%, Evasion +10 |

- Damage cut at equal skill = block rate × share of the hit blocked, against frontal physical hits, when your total shield skill (the shield's own included) equals the attacker's skill.
- Genbu's adds no shield skill, so on the same character its block rate is about 25 points below Forfend +1's or Ammurapi's.
- Forfend +1 out-blocks Archduke's unless your skill is about 150 above the attacker's. Ammurapi beats Archduke's once your skill with Archduke's is about 46 or more below the attacker's.
- Genbu's extra PDT helps only while the set is under the 50% cap. Its job list includes BLU, but BLU can't block with it.
- Forfend +1's Path A augments (Accuracy, Magic Accuracy, then enhancing skill) add no DEF or shield skill (rank-augments.md).

## Weapons and TP

### TP reset

- Equipping anything in the main, sub or range slot resets TP to 0, and so does taking off the main or sub weapon (bg-wiki, Tactical Points). A weapon swap in any set costs all TP.
- Changing ammo doesn't reset TP, but ammo that doesn't fit the ranged weapon (anything but an arrow with a bow) unequips the weapon, which does. This is general game behavior with no source read: bg-wiki's Tactical Points page doesn't cover ammo, and Ullr's page doesn't mention it.
- Trying a weapon skill while out of range also wipes all TP (bg-wiki, Tactical Points).

### Which hand a weapon's stats work from

While dual wielding, each stat on a weapon falls into one of three groups (bg-wiki, Dual Wield; the page says the first group applies "generally"):

| Group | Stats |
|---|---|
| Both hands, from either weapon | Base stats (STR, DEX and so on), Accuracy, Attack, Evasion, plain Magic Accuracy, Magic Attack Bonus, Subtle Blow, weapon skill damage, critical hit damage, job ability duration bonuses |
| That weapon's own hits only | DMG, the weapon's combat skill ("Sword skill +250"), Enspell damage, critical hit rate |
| Main hand only | Effects marked "Main hand:", native TP Bonus, Parrying skill, Magic Accuracy skill, an Ultimate Weapon's unique stats (Mythic job bonuses, Aftermath), every augment on an Ultimate Weapon-class weapon (Su5 included) |

- "Main hand:" effects include Maxentius's Black Halo +50% and Naegling's Savage Blade +15%. Tizona's Expiacion +30% and its Aftermath are Mythic stats, so they are main hand only too.
- An Ultimate Weapon in the off hand, such as Almace, adds its combat skill to its own hits but gives none of its unique stats or Aftermath.
- An Ultimate Weapon's augment works only with the weapon in the main hand, but Accuracy from it counts for both hands: in-game `/checkparam` records (2026-10-10) read Tizona's Path A Accuracy +30 on the off hand too ([gear-notes.md](gear-notes.md#tizona)).
- TP Bonus on a weapon works only from the main hand, unless it is an augment. Trial of the Magians, Odyssey and Unity weapons whose TP Bonus is an augment give it to every weapon skill from the sub or range slot too (bg-wiki, TP Bonus). The Dual Wield page names only Magian and Odyssey weapons as exceptions.
- wsdist pools crit rate and TP Bonus from both weapons. The crit pooling matters with a crit weapon in the off hand: with Gleti's Knife there, wsdist gives its Crit Rate +5 to the main-hand hits too. The TP Bonus pooling is harmless for Thibron, whose +1000 is an augment (see Where wsdist and bg-wiki disagree).
- Thibron is a Trial of the Magians sword (DMG 55, Delay 238; RDM, PLD and BLU). TP Bonus +1000 is one of its three augment options; the others are DMG +3 with weapon skill damage +10%, and DMG +3 with Store TP +17. Only a copy with the TP Bonus augment gives +1000 from the sub slot (bg-wiki, Thibron).
- bg-wiki doesn't say whether an off-hand weapon's "Magic Damage" counts (Bunzi's Rod +248, Maxentius +232). It matters for magical weapon skills.
- Examples in the sub slot:
  - Bunzi's Rod (RDM and BLU): Accuracy +40, Magic Accuracy +40 and Magic Attack Bonus +35 count for both hands. Club skill +242 helps only its own hits. Magic Accuracy skill +255 does nothing. These are base stats. rank-augments.md lists its augments by rank (DMG and MAB first, Accuracy and Magic Accuracy from rank 16).
  - Gleti's Knife (RDM, not BLU): Accuracy +40 and Magic Accuracy +40 count for both hands. Dagger skill +255 helps only its own hits. These are base stats. rank-augments.md lists its augments by rank (DMG and Attack first, Accuracy and Magic Accuracy from rank 16).
  - Neither Bunzi's Rod nor Gleti's Knife has TP Bonus at any rank (rank-augments.md).
- Other plain Magic Accuracy on off-hand and ranged items: Maxentius +40 (either job, with Dual Wield), Ammurapi Shield +38 and Ullr +40 (RDM only). Ullr needs the ammo slot empty or holding an arrow, so it nets 40 minus the Magic Accuracy of the ammo it displaces (bg-wiki, Dual Wield and each item's page for the Magic Accuracy; the ammo rule is general game behavior, not on Ullr's page; see TP reset).
- A weapon in the sub slot needs Dual Wield. RDM has none of its own and gets it from /NIN or /DNC. BLU gets it from set blue magic or from /NIN or /DNC; the two don't stack, and the higher tier wins (bg-wiki, Blue Mage Job Traits). Tiers and gear: see Dual Wield. BLU's Dual Wield spells: see Traits from set spells.

## Weapon skills

### What each kind of weapon skill wants

| Kind | Weapon skills | Stats that help | Stats wasted |
|---|---|---|---|
| Physical, first hit carries the damage | Savage Blade, Black Halo, Expiacion | WSD, TP Bonus, WSC stats, attack, accuracy for the later hits | Critical hit rate and critical hit damage (these can't crit) |
| Physical, fTP-replicating, many hits | Requiescat, Chant du Cygne, Vorpal Blade, Evisceration | WSC stats, attack, multi-attack, gorget and belt, accuracy on every hit; critical hit rate and damage on Chant du Cygne, Vorpal Blade and Evisceration | WSD helps only the first hit; critical stats on Requiescat |
| Magical | Seraph Blade, Red Lotus Blade, Sanguine Blade, Aeolian Edge, Flash Nova | MAB, Magic Damage, WSD (on the whole skill), WSC stats, INT where dSTAT uses it, elemental affinity, obi or Orpheus, magic accuracy | Accuracy, weapon skill accuracy, attack, Warcry |

- Only a weapon skill whose description says its critical hit chance varies with TP, or one an effect lets crit, can crit (bg-wiki, Critical Hit Rate).
- All weapon skill gear is read when the weapon skill goes off, so it goes in the weapon skill set.

### Physical weapon skill damage

bg-wiki, Weapon Skill Damage:

```
Each hit = floor((weapon DMG + fSTR + WSC) × fTP) × pDIF
WSC      = floor(stat A × A% + stat B × B%)
```

- Each hit uses its own hand's weapon DMG and its own pDIF roll. WSC is added to every swing, Double Attack hits included. Attack in a weapon skill set helps every hit.
- Only the first hit gets the skill's fTP. Every later hit, from multi-attack or from a multi-hit skill, has fTP 1.0 unless the skill replicates fTP (bg-wiki, TP Multiplier). Chant du Cygne, Requiescat, Vorpal Blade and Evisceration replicate fTP (bg-wiki, Category:FTP Replicating WS).
- While dual wielding, every weapon skill gets one extra hit from the off-hand weapon beyond its listed hits. That hit has fTP 1.0, or the main hits' fTP on a replicating skill, and it can proc multi-attack within the 8-hit limit (bg-wiki, Dual Wield). Dual wielding adds most to replicating skills.
- bg-wiki assumes WSD, damage-type bonuses, critical hit damage and Overwhelm all apply after pDIF, so the pDIF cap doesn't limit them. Once attack is capped, WSD and critical hit damage still add damage and more attack doesn't (bg-wiki, Byrth's WS Damage Guide).

### Magical weapon skill damage

bg-wiki, Weapon Skill Damage:

```
Base   = floor((152 + floor((weapon item level − 99) × 2.45) + WSC) × fTP) + dSTAT + Magic Damage
       = floor((201 + WSC) × fTP) + dSTAT + Magic Damage            (item level 119 weapon)

Damage = Base × affinity × staff × resist × resistance rank × day and weather
       × (100 + MAB) / (100 + target MDB) × TMDA × magic crit II (1.25 on a proc) × WSD × named weapon skill bonuses
       (floored after each step)
```

- dSTAT and Magic Damage are added after fTP, so TP doesn't scale them. There is no magic burst term.
- bg-wiki writes the MAB term as MAB ÷ MDB and links it to Magic Damage's MAB/MDB term, which is (100 + MAB) / (100 + target MDB); see Magic Attack Bonus.
- Magical weapon skills never miss, but they can be resisted like spells (½, ¾, ⅞), so magic accuracy still adds damage. Accuracy, weapon skill accuracy, attack, pDIF, Warcry and Sneak Attack do nothing for them (bg-wiki, Weapon Skill and Category:Elemental Weapon Skill). bg-wiki assumes, without confirmation, that they get a magic accuracy bonus like the physical first-swing bonus.
- `<Element> "Magic Atk. Bonus" +X` gear, such as Pixie Hairpin +1 (Dark +28) or Archon Ring (Dark +5), is elemental affinity, not MAB. It multiplies that element's final damage: Pixie Hairpin +1 makes Sanguine Blade ×1.28, not +28 MAB (bg-wiki, Community Red Mage Guide). It does nothing for other elements.
- Day and weather (and so an obi) and Orpheus's Sash work on elemental weapon skills as they do on spells. Values, and when to wear which: see Day, weather and obis, Elemental affinity and Orpheus's Sash, and Orpheus's Sash or an obi.
- Crocea Mors's Path C "Ele. weapon skill damage +100%" doubles the (152 + item level term + WSC) × fTP part only, not dSTAT or Magic Damage (bg-wiki, Crocea Mors). wsdist places it the same way (see Formulas wsdist adds).
- wsdist multiplies magical weapon skills by (1 − Magic DT%) where spells get (1 + Magic DT%), so against a target that takes less magic damage it raises the weapon skill instead of lowering it (see Where wsdist and bg-wiki disagree).
- wsdist leaves out the forced 1/2 resist that a 50% or stronger resistance rank puts on a magical weapon skill (see Where wsdist and bg-wiki disagree).

### fTP and TP

bg-wiki, TP Multiplier. The anchors are 1000, 2000 and 3000 TP, and TP here is effective TP (actual TP plus TP Bonus, at most 3000):

```
fTP = fTP(anchor below) + (TP − anchor below) ÷ 1000 × (fTP(anchor above) − fTP(anchor below))
```

- Savage Blade's fTP rises 6.25 per 1000 TP from 1000 to 2000, and 3.5 from 2000 to 3000. TP Bonus adds the most per point while effective TP is between 1000 and 2000.

### TP Bonus

- All TP Bonus adds together and is added to actual TP when the weapon skill goes off. Effective TP can't go above 3000; the excess is lost (bg-wiki, TP Bonus).
- A weapon skill still needs 1000 actual TP to start (bg-wiki, Moonshade Earring). Aftermath level uses actual TP only, so TP Bonus doesn't raise an Almace or Tizona Aftermath.
- TP Bonus raises whatever the weapon skill's description says varies with TP (bg-wiki, TP Bonus):

| "... varies with TP" | TP Bonus raises | RDM and BLU weapon skills |
|---|---|---|
| Damage | fTP | Savage Blade, Black Halo, Expiacion, Seraph Blade, Red Lotus Blade, Aeolian Edge |
| Attack | Attack for the skill | Requiescat (shrinks its attack penalty) |
| Critical hit rate | Critical hit rate of all hits | Chant du Cygne, Vorpal Blade, Evisceration |
| Accuracy | Accuracy of all hits (amounts unknown) | Swift Blade, Realmrazer |
| Chance of effect | Magic accuracy of the added effect | Flash Nova, Death Blossom |
| Amount drained (also duration, radius, amount restored) | That amount | Sanguine Blade |

- So TP Bonus adds no damage to Sanguine Blade or Flash Nova.
- Where it counts: TP Bonus on armor and accessories (Moonshade Earring, Mpaca's Cap) works for every weapon skill. On a weapon it works only from the main hand, unless it is an augment (see Which hand a weapon's stats work from).
- TP Bonus is wasted once actual TP plus all TP Bonus reaches 3000. With Thibron's +1000 also worn, Moonshade Earring's +250 counts in full up to 1750 TP, in part from 1750 to 2000, and not at all from 2000 TP up (bg-wiki, Moonshade Earring). At high TP another earring does more in that slot.
- Whether TP Bonus gear helps physical blue magic is disputed; see Physical blue magic.

### Weapon skill damage (WSD)

- WSD from gear, job point gifts and Gyudon adds together. It applies only to the first hit of a physical weapon skill (and the magical part of a hybrid one), but to the whole of a magical weapon skill (bg-wiki, Weapon Skill Damage).
- Elemental gorgets and belts are not WSD, whatever their text says; they add fTP (see below).
- WSD counts from an off-hand weapon too (bg-wiki, Dual Wield).
- bg-wiki calls WSD inconsistently implemented. Some first-hit sources apply to both hits of certain skills (Sturmwind, Atonement), and Magian weapons with "Weapon Skill Damage +n%" apply to every hit. First hit only is the usual rule, not a universal one.
- Cap: bg-wiki gives no figure. A reference link on the Weapon Skill Damage page is titled "WSD's cap is >+100%". No known cap limits stacking WSD in a set.
- WSD is worth most where the first hit carries most of the fTP (Savage Blade, Black Halo, Expiacion), and least on replicating multi-hit skills (Requiescat, Chant du Cygne, Vorpal Blade, Evisceration).
- Nyame Path B's WSD is a rank augment. At rank 20, for example, the Mail has +10% and the Sollerets +8%, and at rank 10 the Gauntlets have +5%. rank-augments.md has every rank.
- Bonuses that apply to every hit, each as its own multiplier with flooring between steps: Dragoon's WSD trait, Overwhelm, Building Flourish, and bonuses for one named weapon skill, such as "Savage Blade damage +15%". An augmented named bonus, such as a Magian "Burning Blade: DMG +10%", is another separate multiplier; it doesn't add to an unaugmented one (bg-wiki, Weapon Skill Damage).

### Elemental gorgets and belts

- A gorget or belt whose element matches one of the weapon skill's skillchain properties adds 25/256 fTP (about +0.098). It goes on the first hit, or on every hit of a replicating skill. It also gives Accuracy +10 on all hits. Gorget and belt together add 50/256 (bg-wiki, Category:Elemental Gorgets, Category:Elemental Belts and Weapon Skill Damage).
- Fotia Gorget and Fotia Belt match any weapon skill that has a skillchain property, and each adds a 1% chance to keep all TP. Their text says "Weapon skill damage +10%", but that is the same 25/256 fTP, not WSD (bg-wiki, Fotia Gorget and Expiacion). Fotia Belt's +10 accuracy counts as magic accuracy on a magical weapon skill (bg-wiki, Fotia Belt).
- wsdist's set optimizer multiplies the two pieces' 1% chances together, so it counts almost none of the TP kept, and it leaves Fotia's +10 out of a magical weapon skill's magic accuracy (see Where wsdist and bg-wiki disagree).
- Sanguine Blade has no skillchain property, so no gorget or belt does anything for it.
- wsdist gives Fotia's +25/256 fTP to Sanguine Blade too. bg-wiki's simulated Sanguine Blade sets don't wear Fotia, so they're unaffected (see Where wsdist and bg-wiki disagree).
- What +25/256 fTP is worth, worked out from each skill's fTP (one piece; double it for gorget and belt):

| Weapon skill | fTP the bonus adds to | Gain |
|---|---|---|
| Requiescat | 1.0, every hit | about +10% per hit |
| Evisceration | 1.25, every hit | about +8% per hit |
| Vorpal Blade | 1.375, every hit | about +7% per hit |
| Chant du Cygne | 1.63, every hit | about +6% per hit |
| Black Halo | 3.0 to 9.75, first hit only | +3.3% to +1.0% of the first hit |
| Expiacion | 3.8 to 12.2, first hit only | +2.6% to +0.8% of the first hit |
| Savage Blade | 4.0 to 13.75, first hit only | +2.4% to +0.7% of the first hit |

### Weapon skill accuracy

- The first swing of a physical weapon skill gets about +100 accuracy; bg-wiki gives only the approximate figure. Later swings get no bonus, and ranged weapon skills get none (bg-wiki, Category:Weapon Skills).
- The extra off-hand hit while dual wielding isn't the first swing, so it gets no bonus, and as an off-hand hit it caps at 95% (bg-wiki, Dual Wield and Hit Rate).
  - wsdist gives that hit the +100 too, so it overrates the off-hand hit and undervalues accuracy in dual-wield Savage Blade, Black Halo and Expiacion sets, most with a skill-less off hand such as Thibron (see Where wsdist and bg-wiki disagree).
- So a weapon skill set needs the TP set's accuracy, not less. With Dual Wield, Savage Blade, Black Halo and Expiacion (2 hits plus the off-hand hit) have 2 of 3 swings without the bonus. Chant du Cygne (3 hits), Vorpal Blade (4), Requiescat (5) and Evisceration (5) need it on every swing after the first.
- "Weapon skill accuracy +X" is ordinary accuracy that applies to every hit of a physical weapon skill and nothing else; a developer post confirmed it does nothing for non-physical weapon skills (bg-wiki, Accuracy). In a physical weapon skill set it is worth the same as Accuracy +X.
- Elemental gorgets and belts add Accuracy +10 to all hits (above).
- Only weapon skills whose description says "Accuracy varies with TP" gain accuracy from TP and TP Bonus (amounts unknown). Of RDM and BLU weapon skills, that is Swift Blade (needs a Hepatizon Rapier on RDM or a Hepatizon Sapara on BLU) and Realmrazer (club, BLU). None of the weapon skills in the reference below do, so TP Bonus never stands in for accuracy there (bg-wiki, TP Bonus).
  - wsdist gives Realmrazer and Swift Blade +0/+20/+40 accuracy at 1000/2000/3000 TP, values its own code calls made up. Treat any accuracy result for either as a guess (see Where wsdist and bg-wiki disagree).
- Magical weapon skills never miss; magic accuracy is their only hit-rate stat (above).

### TP from a weapon skill

- During a weapon skill, only the first main-hand hit and the first off-hand hit give full TP. Every other hit gives a flat 10 TP (bg-wiki, Tactical Points). Store TP in a weapon skill set only raises those two hits, so it is rarely worth a slot there.
- wsdist also lets Store TP raise the flat 10. bg-wiki doesn't say whether it does; unsettled, and at most a few TP a hit (see Where wsdist and bg-wiki disagree).

### Weapon bonuses for weapon skills

- A bonus for one named weapon skill works from the main hand only and applies to every hit of that skill, as its own multiplier:
  - Naegling or Kaja Sword: Savage Blade +15% (bg-wiki, Savage Blade).
  - Maxentius or Kaja Rod: Black Halo +50% (bg-wiki, Black Halo).
  - Tauret or Kaja Knife: Evisceration +50% (bg-wiki, Evisceration).
  - Tizona at level 99 or higher: Expiacion +30%, plus Mythic Aftermath (bg-wiki, Expiacion).
- Naegling in the main hand also gives Attack +1% per buff on you during weapon skills: every melee weapon skill, not only Savage Blade, but no ranged ones. That comes from the page's notes (Fwahm's testing); its item description instead says the bonus depends on the number of upgrades (bg-wiki, Naegling). With many buffs up, attack reaches the ratio cap sooner.
- A Rank 15 Ultimate Weapon augment multiplies the hidden bonus: Tizona's Expiacion +30% becomes +49.5% (1.3 × 1.15), and Almace gains Chant du Cygne +10%. Like every one-handed Ultimate Weapon augment, it works from the main hand only (bg-wiki, BGWiki:Ultimate Weapon Augments). wsdist applies these the same way (see Formulas wsdist adds).
- Mythic Aftermath gives Accuracy, Magic Accuracy or MAB 30 to 49, or Attack 40 to 99, at AM1 and AM2 (Tizona: Accuracy, then Magic Accuracy), and at AM3 attacks twice 40% and three times 20% of the time (bg-wiki, Mythic Aftermath). wsdist uses 85% of each range, its own choice (see Formulas wsdist adds).
- The Hashishin set bonus raises a blue magic spell's WSC, not a weapon skill's; see BLU set bonuses.

### Weapon skill reference (RDM and BLU)

Physical weapon skills. "Replicated" means every hit, the off-hand hit included, gets the listed fTP; otherwise later hits use 1.0.

| Weapon skill | Weapon | Hits | fTP at 1000 / 2000 / 3000 TP | Later hits | WSC | TP raises | Can crit |
|---|---|---|---|---|---|---|---|
| Savage Blade | Sword | 2 | 4.0 / 10.25 / 13.75 | 1.0 | 50% STR, 50% MND | Damage | No |
| Black Halo | Club | 2 | 3.0 / 7.25 / 9.75 | 1.0 | 70% MND, 30% STR | Damage | No |
| Expiacion | Sword | 2 | 3.796875 / 9.390625 / 12.1875 | 1.0 | 30% STR, 30% INT, 20% DEX | Damage | No |
| Requiescat | Sword | 5 | 1.0 at any TP | Replicated | 73 to 85% MND | Attack: −20% / −10% / none | No |
| Chant du Cygne | Sword | 3 | 1.6328125 at any TP | Replicated | 80% DEX | Critical hit rate: +15 / +25 / +40% | Yes |
| Vorpal Blade | Sword | 4 | 1.375 at any TP | Replicated | 60% STR | Critical hit rate (amounts unknown) | Yes |
| Evisceration | Dagger | 5 | 1.25 at any TP | Replicated | 50% DEX | Critical hit rate: +10 / +25 / +50% (2000 and 3000 unverified) | Yes |

- Savage Blade: Fragmentation and Scission (bg-wiki, Savage Blade).
- Black Halo: RDM can use it only with Maxentius or Kaja Rod in the main hand (bg-wiki, Black Halo).
- Expiacion: BLU main job only. Distortion and Scission (bg-wiki, Expiacion).
- Requiescat: its damage is neither physical nor magical, but it uses the physical formulas. WSC is 73% MND with the first merit and 3% more for each of merits 2 to 5. The attack penalty follows TP; a June 2024 test noted on the page puts the 3000 TP modifier at 0%, which matches the table. TP Bonus shrinks the penalty, by about 10% attack per 1000 TP if it is linear between the table's points (derived) (bg-wiki, Requiescat).
- Chant du Cygne: Light and Distortion. RDM, PLD and BLU can use it with Almace, Badelaire (+1 to +3) or Brunello; only Almace gives Aftermath (bg-wiki, Chant du Cygne).
  - Almace's Empyrean Aftermath gives main-hand melee hits, multi-attack hits included, a 30/40/50% chance (AM1/2/3) of double damage, or triple at Level 119 III. It never procs on weapon skills (bg-wiki, Empyrean Aftermath). wsdist always triples, so it overstates an Almace below 119 III (see Formulas wsdist adds).
- Death Blossom and Imperator are also physical, so they use attack. Death Blossom can't crit, and TP raises the chance of its added effect (bg-wiki, Death Blossom and Critical Hit Rate).
  - Death Blossom (Murgleis): 3 hits, fTP 4.0 at any TP, 50% MND and 30% STR. TP only raises its magic evasion down chance, so TP Bonus adds no damage (bg-wiki, Death Blossom). wsdist has the same values (see Formulas wsdist adds).
- Realmrazer (club, BLU main job): 7 hits, fTP 0.9 replicated, 73 to 85% MND by merits (bg-wiki, Realmrazer). wsdist uses 85% (see Formulas wsdist adds).
- wsdist has no data for Vorpal Blade or Flash Nova, so it can't build their sets; use this section (see What it models).

Magical weapon skills (one hit each; all never miss and ignore attack):

| Weapon skill | Weapon | Element | fTP at 1000 / 2000 / 3000 TP | WSC | dSTAT | TP raises |
|---|---|---|---|---|---|---|
| Seraph Blade | Sword | Light | 1.125 / 2.625 / 4.125 | 40% STR, 40% MND | 0 | Damage |
| Red Lotus Blade | Sword | Fire | 1.0 / 2.38 (2 + 98/256) / 3.75 | 40% STR, 40% INT | (INT − target INT) ÷ 2 + 8, cap 32 | Damage |
| Sanguine Blade | Sword | Dark | 2.75 at any TP | 50% MND, 30% STR | (INT − target INT) × 2, no cap | HP drained: 50 / 100 / 160% of damage |
| Aeolian Edge | Dagger | Wind | 2.0 / 3.0 / 4.5 | 40% DEX, 40% INT | (INT − target INT) ÷ 2 + 8, cap 32 | Damage |
| Flash Nova | Club | Light | 3.0 at any TP | 50% STR, 50% MND | (INT − target INT) ÷ 2 + 8, cap 32 | Flash's chance to land (amounts unknown) |

- Seraph Blade: Scission. INT adds nothing (bg-wiki, Seraph Blade).
- Sanguine Blade: TP Bonus adds no damage. INT is worth 2 base damage a point with no cap. It has no skillchain property, so it doesn't close a skillchain or end a magic burst window, and gorgets and belts do nothing for it. Dark affinity gear and a dark obi or Orpheus apply (bg-wiki, Sanguine Blade).
- Aeolian Edge: area of effect; Scission, Detonation and Impaction. Unlike Cyclone it needs melee range. Its dSTAT caps at 32 when INT is 48 over the target's; past that INT adds only through WSC (bg-wiki, Aeolian Edge).
- Flash Nova: TP Bonus adds no damage. The page's note limits it to players with WAR, WHM, PLD, DRK, SAM, BLU or GEO as main or support job, but its job table also lists RDM at level 92 (bg-wiki, Flash Nova).
- FFXIclopedia gives older values for Seraph Blade (fTP 1.0 / 2.5 / 3.0), Aeolian Edge (2.75 / 3.5 / 4.0) and Sanguine Blade (drain 50 / 75 / 100%). bg-wiki's values follow the June 2014 weapon skill update and later tests.

## Magic accuracy

Magic accuracy (macc) decides whether a spell cast on an enemy is resisted, and how badly.

### Where it counts

- Macc is compared with the target's magic evasion when a spell is cast on an enemy. bg-wiki describes resists only for offensive spells, and none of its pages describes a resist roll for enhancing or healing magic cast on yourself or allies, so macc does nothing in Enhancing, Refresh, Regen, Phalanx, Stoneskin or Cure sets. Use those slots for skill, duration or potency (bg-wiki, Magic Accuracy and Resist).
- Like potency, macc is read when the spell lands, so it goes in the midcast set.
- Physical blue magic hits with melee accuracy: the main-hand weapon's accuracy, DEX and Accuracy. Magical blue magic, and the added effects of all blue spells, use macc and blue magic skill (bg-wiki, Category:Blue Magic).
- Magical weapon skills (Sanguine Blade, Seraph Blade, Red Lotus Blade) never miss, but they can be partly resisted like a nuke, so macc, not Accuracy, is the hit stat in their weapon skill set. bg-wiki assumes, unconfirmed, that they get a macc bonus like a physical weapon skill's first-swing bonus (bg-wiki, Category:Elemental Weapon Skill).
  - wsdist builds their macc from Magic Accuracy, main-hand Magic Accuracy skill and a dINT term (dINT even for MND skills such as Seraph Blade), with no skill term, no first-hit bonus and no Fotia +10. Neither model is confirmed (see Where wsdist and bg-wiki disagree).
- Enspells roll macc every attack round from the gear worn then: Magic Accuracy, the main weapon's Magic Accuracy skill and, on a RDM main job, enhancing skill. The engaged set, not the casting set, decides how often they land (bg-wiki, Category:Enspell).

### Magic accuracy formula

bg-wiki, Magic Accuracy:

```
Magic accuracy = skill in the spell's magic type          (1 skill = 1 macc)
               + dSTAT term                                (−30 to +30)
               + main-hand weapon's Magic Accuracy skill  (1:1)
               + Magic Accuracy from gear, traits, job points, merits, abilities, food and Atma
```

- +1 skill in the spell's own school, +1 Magic Accuracy on gear and +1 main-hand Magic Accuracy skill are worth the same. An INT or MND point is worth 1 at most; see dSTAT.
- Frazzle, Frazzle II, Frazzle III, Distract, Distract II and Distract III each add +150 of their own (bg-wiki, Frazzle III).
- Each Master Level adds +1 to every base stat, INT and MND included, and +1 to the cap of every combat and magic skill the job learns itself (bg-wiki, Master Levels). At Master Level 25 that is 25 more macc in every school the job has, plus up to 25 through dSTAT.

### Magic hit rate

bg-wiki, Magic Hit Rate:

```
dMAcc    = magic accuracy − target's magic evasion
Hit rate = 50% + dMAcc%              when dMAcc ≥ 0
         = 50% + floor(dMAcc ÷ 2)%   when dMAcc < 0
Cap: 95%
```

- Hit rate caps when macc is 45 over the target's magic evasion. Macc past that is wasted; those slots can go to potency, duration or damage.
- Below 50%, +1 macc is worth +0.5% hit rate. From 50% to the cap it is worth +1%.
- bg-wiki calls the 50% anchor arbitrary, the simplest fit. It gives no general floor; FFXIclopedia puts a 5% floor at 90 or more below magic evasion.
- wsdist uses the same formula and 95% cap, but rounds toward zero, so an odd negative dMAcc comes out 1% higher (−45 gives 28%, not 27%). No gear choice changes (see Where wsdist and bg-wiki disagree).

Resists are rolled one state at a time against hit rate p (bg-wiki, Resist):

| Spell | Outcomes |
|---|---|
| Damage spell | full p; 1/2 damage p(1−p); 1/4 p(1−p)²; 1/8 (1−p)³ |
| Fixed-duration enfeeble | full duration p; half duration p(1−p); resisted (1−p)² |

- At the 95% cap, Sleep lands 99.75% of the time but at full duration only 95%. Going from 80% to 90% hit rate lifts the land rate only from 96% to 99%, but full duration from 80% to 90%. Macc buys duration as well as landing. (The page draws the enfeeble curve as a graph; this formula fits its numbers.)
- A magic burst raises the spell's macc if its element matches the skillchain. For an enfeeble or other spell with no damage, macc is all a burst raises. The amount is disputed: the Magic Burst page speculates +100 (unverified), and the Resist page gives +50 for spells on negative-status ranks (an estimate). Don't count on a set number.

### Macc needed to cap

The target's magic evasion depends on its level, its resistance rank (below), dINT and level correction, so no single number caps hit rate. bg-wiki's estimates of the total macc needed for 95%, good to about ±10 (bg-wiki, Magic Hit Rate):

| Foe level | 100% rank | 50% rank | 30% rank |
|---|---|---|---|
| 128 | 854 | 955 | 1,154 |
| 135 | 1,028 | 1,172 | 1,402 |
| 140 | 1,152 | | |
| 145 | 1,276 | | |
| 150 | 1,400 | | 1,943 |

- Compare the whole total with the table: skill, dSTAT, main-hand Magic Accuracy skill, gear, job bonuses and food. The page doesn't say what dINT or level correction the estimates assume, and the 20% and 25% ranks had no data, so a total within a few dozen of the line is uncertain.
- Example: a RDM at Master Level 25 with 8 Magic Skills merit levels has 460 + 25 + 16 = 501 enfeebling skill. A weapon with 255 Magic Accuracy skill brings that to 756. A level 135 foe at a 100% rank then needs about 272 more (1,028 − 756), or about 157 after an always-on +115 (272 − 115; see Job sources). At a 30% rank it needs about 531 after the +115 (1,402 − 756 − 115). An Ice or Earth spell needs 10 to 15 less again with 5 levels of that element's Group 1 merit (Job sources).
- A burst moves the target one rank weaker (see Resistance ranks). bg-wiki's example: a V20 Ongo needs 1,222 macc for a bursted earth spell and 1,365 for a free nuke (bg-wiki, Magic Accuracy Skill).
- Every wsdist enemy preset has Magic Evasion 0, "BG Wiki sets" included, so wsdist lands every spell unresisted. Its nuke, burst, enspell and magical weapon skill sets aren't evidence that macc can be dropped; enter a real magic evasion before trusting a wsdist magic number (see Where wsdist and bg-wiki disagree).

### Skill by magic type

| Spells | Skill that sets macc | Level 99 | Job mastery | With Master Levels |
|---|---|---|---|---|
| Enfeebling | Enfeebling magic (RDM A+) | 424 | 460 | 510 at 50 |
| Elemental | Elemental magic (RDM C+) | 378 | 378 | 428 at 50 |
| Dark | Dark magic (RDM E) | 300 | 300 | 350 at 50 |
| Divine (RDM gets the spells only from a subjob) | Divine magic (RDM E) | 300 | 300 | 350 at 50 |
| Magical blue magic, and added effects of blue spells | Blue magic (BLU) | 424 | 460 | 500 at 40 |
| Physical blue magic | none: melee accuracy | | | |

Sources: bg-wiki, Red Mage, Category:Enfeebling Magic, Category:Elemental Magic, Category:Dark Magic, Category:Divine Magic and Category:Blue Magic.

- Skill caps rise 1 per Master Level. At Master Level 25, RDM has enfeebling 485, elemental 403, and dark and divine 325 (each table figure + 25), and BLU has blue magic 485, all before merits.
- With 8 Magic Skills merit levels in a skill (+16), before gear: enfeebling 485 + 16 = 501, elemental 403 + 16 = 419, dark 325 + 16 = 341. Without merits, divine stays 325 and blue magic 485. Enhancing (481) and healing (409) are under Enhancing skill and Cure formula.
- The job mastery figures come from four skill gifts, +5, +8, +10 and +13 (RDM enfeebling at 60, 360, 910 and 1,710 job points). They leave out merits.
- The general merit Magic Skills adds +2 a level to one skill, up to 8 levels (+16) per skill (bg-wiki, Merit Points). Merited skill is 1:1 macc for that school, so 8 levels add 16 macc to that school's spells.
- "Enfeebling magic skill +X" adds X macc to enfeebles only, and nothing to dark or divine spells. "All magic skills +X" counts for every school.
- Elemental skill sets elemental spells' macc and interruption rate, not their damage (Meteor excepted). In a nuke set it competes with Magic Accuracy+, not Magic Attack Bonus.
- Dark skill also sets the potency of some dark spells.

### dSTAT

dSTAT is the caster's stat minus the target's. INT and MND from gear raise it (bg-wiki, Intelligence and Magic Hit Rate). Which stat:

- INT for black magic: Blind, Sleep, Bind, Gravity, Poison, Break, Dispel, elemental nukes and dark magic.
- MND for white magic: Paralyze, Slow, Silence, Addle, Dia, Inundation and divine magic.
- Frazzle I to III and Distract I to III are black magic but use MND (bg-wiki, Frazzle III). Cast them in the MND set.
- CHR for songs, AGI for Quick Draw, none for ninjutsu.

bg-wiki, Magic Accuracy:

| dSTAT | Macc per stat point | Macc at the end of the band |
|---|---|---|
| −10 to +10 | 1 | ±10 |
| ±10 to ±30 | 0.5 | ±20 |
| ±30 to ±70 | 0.25 | ±30 |
| beyond ±70 | 0 | ±30 (cap) |

- A stat point is worth a full macc only while caster and target are within 10 of each other. Endgame foes run high in INT: Apex Blazer Elytra (level 136, PLD) 241, Apex Soldier Lugcrawler (136, WAR) 261, Locus Colibri (135, RDM) 340, Apex Water Elemental (133, BLM) 354, Ongo V0 and V20 (134) 345 and 425, Mireu (150) 474, Triboulex (145, DRK/BLM) 504. BLM-job foes have the most, MNK and PLD types the least (bg-wiki, Intelligence).
- Against those foes dINT can sit well below −10, where an INT point is worth 0.5 macc or less. Magic Accuracy+ or skill then beats INT or MND for landing a spell.
- FFXIclopedia gives 1:1 to +10, then 0.5 a point with no known limit. bg-wiki's Intelligence page draws the same curve as the Magic Accuracy page on a 0 to +60 scale; use the signed values above.

### Magic Accuracy skill on weapons

- Item level weapons list "Magic Accuracy skill +X", for example +255 on Bunzi's Rod and +250 on Maxentius and Naegling. It adds to magic accuracy one for one **(player, bg-wiki)**.
  - A 2016 developer post put it at 0.5 a point; bg-wiki's Magic Accuracy Skill page rejects that from player tests.
- Every item level weapon that can go in the main hand has it. It isn't tied to a school, so it counts for every spell. A weapon without item level gives up about 250 macc in the main hand.
- Only the main hand's Magic Accuracy skill counts. An offhand weapon's does nothing, so when dual wielding only its plain "Magic Accuracy +X" helps (bg-wiki, Magic Accuracy Skill and Dual Wield).
- Plain Magic Accuracy+ counts in full from the sub and range slots (bg-wiki, Dual Wield).

Main hand (bg-wiki, each weapon's page):

| Weapon | Magic Accuracy skill | Magic Accuracy+ | Main-hand macc |
|---|---|---|---|
| Bunzi's Rod | 255 | 40 | 295 |
| Naegling, Maxentius, Tauret | 250 | 40 | 290 |
| Colada | 201 | 15, plus any augment | 216 |
| Pukulatmuj +1 | 188 | 0 | 188 |

Bunzi's Rod, Naegling, Maxentius and Tauret also have INT+15 and MND+15. Bunzi's Rod in the main hand gains only 5 over Naegling, Maxentius or Tauret, so a casting weapon swap gains macc mostly from the sub and range slots:

| Item | Slot | Magic Accuracy+ | Who can use it |
|---|---|---|---|
| Bunzi's Rod | sub | 40 | RDM and BLU, with Dual Wield |
| Maxentius | sub | 40 | RDM and BLU, with Dual Wield |
| Gleti's Knife | sub | 40 | RDM, not BLU |
| Ammurapi Shield | sub | 38 | RDM, not BLU |
| Ullr | range | 40 | RDM, not BLU |

- Ullr needs the ammo slot empty or holding an arrow, so it nets 40 minus the macc of the ammo it displaces. The ammo rule is general game behavior, not stated on a bg-wiki page read (see TP reset).
- Changing main, sub or range resets TP (see Weapons and TP).
- The Bunzi's Rod and Gleti's Knife values above are base stats. A rank 0 copy has them, and no augments; see Odyssey augments below rank 30.

### Resistance ranks

Each monster has a resistance rank for each element, and a separate negative-status rank for each status effect. A monster's base magic evasion is C rank, like a combat skill at its level (players have G), and the rank multiplies it (bg-wiki, Resist and Magic Evasion):

| Rank | Magic evasion × | What else changes |
|---|---|---|
| 150% (weak) | 0.95 | |
| 130% | 0.96019 | |
| 115% | 0.98 | |
| 100% | 1 | |
| 85% | 1.023 | |
| 70% | 1.049 | |
| 60% | 1.0905 | |
| 50% | 1.126 | Elemental: every spell takes at least a 1/2 resist. Negative-status: no forced resist |
| 40% | 1.2075 | as 50% |
| 30% | 1.3475 | as 50%; negative-status ranks can also be Immunobroken from here down |
| 25% | 1.70065 | as 30% |
| 20% | 2.141 | as 30% |
| 15% | 2.65 | as 30% |
| 10% | 5 (unverified) | hit rate fixed at 5% whatever the macc |
| 5% | 10 (unverified) | always fully resisted; an enfeeble landed with Stymie gets through at half duration |

- The macc needed climbs steeply past 30%. Beyond that, an element or status the foe is weaker to does more than extra gear macc.
- On an element ranked 50% or stronger, no amount of macc gets full damage.
- Negative-status ranks cover Amnesia, Bind, Blindness, Charm, light and dark Sleep, player Elegy, Gravity, Paralysis, Petrification, Poison, Silence, Slow, Stun and Terror. They use the same macc table and the same 10% and 5% limits, but have no forced 1/2 resist, so these enfeebles can land at full duration even at strong ranks.
- Elementals have +50 magic evasion on top, not multiplied by rank. Expect to need up to about 50 more than the requirement table shows; the table page doesn't say whether it includes this.
- A skillchain lowers the rank of each of its elements one step for the burst window, never past 150% and not at all from 5%. That clears the forced 1/2 resist only from exactly 50% (to 60%). Rayke clears it if it brings the rank to 60% or weaker, and Subtle Sorcery ignores that resist state for elemental magic.
- Skillchains, Rayke and Threnody don't lower negative-status ranks. Only Immunobreak does.
- Immunobreak lowers a negative-status rank of 30% or stronger one step at a time when certain enfeebles are resisted, never past 50%. The spells, the chance and "Immunobreak"+1: see Immunobreak.

### Level correction

- Where level correction applies, it starts when the foe is 2 or more levels above you. bg-wiki estimates −4 macc per level, and −4 to your magic evasion against its spells, and marks the value as needing information (bg-wiki, Level Difference Penalty). The Magic Hit Rate page calls it a guess.
- Many zones have none; the list is under Hit rate and the accuracy cap.
- Where it does apply, content level 100+ fights are built as level 99 foes with added stats instead.
- The Master Levels page says each Master Level effectively raises your level by 1, but not whether level correction counts it.
- So the gap a raw 99 against 135 count suggests (about −140 macc) is unlikely to be real. Gear against the requirement table.

### Artifact set bonus

Reforged Artifact +2, +3 and +4 pieces give Accuracy, Ranged Accuracy and Magic Accuracy for the pieces worn together. It is the same for every job's set: Atrophy for RDM, Assimilator's for BLU (bg-wiki, Category:Reforged Artifact Armor +3, Atrophy Armor Set and Assimilator's Attire Set).

| Pieces | Accuracy, Ranged Accuracy and Magic Accuracy |
|---|---|
| 2 | +15 |
| 3 | +30 |
| 4 | +45 |
| 5 or more | +60 |

- NQ and +1 pieces count for nothing. One piece gives nothing, and a sixth adds nothing.
- +2 and +3 pieces count together. The Regal pages say the bonus works with +2, +3 and +4, which implies +4 pieces count alongside them; no page says so outright.
- Regal Earring counts as a piece. RDM and BLU can wear it (MP+20, INT, MND and CHR +10, Magic Atk. Bonus +7). Regal Ring counts too but is for melee jobs only, and Regal Belt (SMN) gives the bonus to the avatar only. Regal Cuffs and Regal Gem have no set bonus (bg-wiki, Regal Earring, Regal Ring and Regal Belt).
- The bonus counts the pieces worn when the spell lands. A midcast set that swaps all four Artifact pieces for other gear loses 45 macc, or 60 with a Regal Earring, and has to make it up elsewhere.
- wsdist counts the bonus only while a Regal Ring or Regal Earring is worn (+15 per AF piece, up to 5) and gives 0 without one. Its item list also has only Atrophy Chapeau and Gloves and Assimilator's Jubbah and Shalwar. So wsdist, and bg-wiki's simulated sets with it, undervalue 2 to 4 AF pieces worn without Regal Earring (see Where wsdist and bg-wiki disagree).

### Job sources

RDM (bg-wiki, Red Mage, unless noted):

| Source | Magic accuracy |
|---|---|
| Job point gifts at 30, 280, 780 and 1,530 spent | +10, +15, +20, +25; +70 if they add |
| Job point category Magic Accuracy Bonus | +1 a level, +20 at 20 |
| Group 2 merit Magic Accuracy | +5 a level, +25 at 5 |
| Viti. Chapeau relic augment, while worn | +3 per level of that merit, +15 at 5 (bg-wiki, Viti. Chapeau +4) |
| Group 1 merits, one per element | +3 a level (Red Mage page and the community guide) or +2 (Merit Points page); that element's spells only |
| Saboteur (1 minute, 3-minute recast) | a level-scaled amount for all spells, with no number given; plus +2 enfeebling macc per level of the Saboteur Effect job point category, +40 at 20 |
| Stymie (SP ability, 1-hour recast) | next enfeeble 100% |

- No page says outright that the gift tiers add up. RDM's and BLU's skill gifts do (424 + 5 + 8 + 10 + 13 = 460), and bg-wiki totals the Capacity Point gifts the same way, so they most likely do.
- A mastered RDM then has +115 always on (gifts 70, job points 20, merits 25), if 5 of its Group 2 merit levels are in Magic Accuracy. Group 2 allows 10 levels in all (bg-wiki, Merit Points).
- With 5 levels in Magic Accuracy, a RDM's always-on total is the full 70 + 20 + 5 × 5 = +115.
- Count Viti. Chapeau +4 as Magic Accuracy 42 + 15 = 57 only with 5 levels in that merit.
- The community guide recommends 5/5 Ice and 5/5 Wind (Ice covers Distract, Paralyze and Bind; Wind covers Gravity and Silence) and 5/5 Group 2 Magic Accuracy (bg-wiki, Community Red Mage Guide).
- A Group 1 merit adds magic accuracy to one element's spells:
  - Group 1 allows 10 levels, at most 5 a category (bg-wiki, Merit Points).
  - At 5 levels: +10 (5 × 2, Merit Points page) or +15 (5 × 3, Red Mage page) to Ice spells (Paralyze, Paralyze II, Bind, Distract to Distract III, the Blizzard nukes) and Earth spells (Slow, Slow II, Break, the Stone nukes). Elements: bg-wiki, each spell's page.
  - So on those spells the always-on total is 115 + 10 = 125 to 115 + 15 = 130. A spell of an element with no merit levels gets only the 115.
- Composure's accuracy bonus is physical only; it adds no magic accuracy (bg-wiki, Composure).
- Stymie: what it can't get past, and how long it lasts, is under Stymie. While it is up, the enfeebling set can trade macc pieces for potency and duration (bg-wiki, Stymie).

BLU (bg-wiki, Blue Mage, unless noted):

| Source | Magic accuracy |
|---|---|
| Job point gifts at 125, 450, 1,050 and 1,900 spent | +5, +8, +10, +13; +36 if they add, as BLU's skill gifts do |
| Job point category Magic Accuracy Bonus | +1 a level, +20 at 20 |
| Group 1 merit Magical Accuracy | +2 a level, magical blue magic only; +10 at 5 |
| Convergence (Group 2 merit ability) | next magical blue spell +5 per merit level, +25 at 5; that spell becomes single-target (bg-wiki, Convergence) |
| Magic Accuracy Bonus trait, from setting Tenebral Crush (8 trait points) | +10 at tier I; +22 at tier II, which needs the Job Trait Bonus gift at 100 job points; tier III, at 1,200 job points, has no known value (bg-wiki, Blue Mage Job Traits) |

- Tenebral Crush is BLU's only macc trait. A blue magic trait doesn't stack with the same trait from the subjob; the higher tier applies.
- A mastered BLU with 5 Magical Accuracy merits has, on magical blue magic: 36 (gifts, if they add) + 20 (category) + 10 (merits) = +66 always on, plus the Tenebral Crush trait when it is set.
- wsdist gives BLU a fixed +36 macc, equal to the gifts. It leaves out the +20 job point category and set-spell traits such as Tenebral Crush's, and it can't model blue magic or Cures at all (see Where wsdist and bg-wiki disagree).

### Magic accuracy food

Percentage macc foods multiply only Magic Accuracy+ and main-hand Magic Accuracy skill, not skill or dSTAT (bg-wiki, Category:Magic Accuracy Food).

| Food | Magic accuracy | Cap | Magic Accuracy+ plus main-hand skill that reaches the cap |
|---|---|---|---|
| Crepe des Rois | +21% | 95 | 453 |
| Tropical Crepe | +20% | 90 | 450 |
| Oden | +15% | 70 | 467 |
| Crepe B. Helene | +21% | 50 | 239 |
| Pear Crepe | +20% | 45 | 225 |
| Prime Marine Stewpot | +95, also Accuracy and Ranged Accuracy +95 | | |
| Marine Stewpot | +90, also Accuracy and Ranged Accuracy +90 | | |
| Rolanberry Daifuku, +1 | +50, +55 | | |

- A 290 or 295 main-hand weapon alone caps Crepe B. Helene and Pear Crepe. Crepe des Rois needs about 160 more Magic Accuracy+ from the rest of the set.

### Odyssey augments below rank 30

- Every Bunzi's and Gleti's piece, Bunzi's Rod and Gleti's Knife included, gains "Accuracy+1 Mag. Acc.+1" at rank 16, rising 1 a rank to +15 at rank 30. Nyame Path B has no Mag. Acc. line at any rank; Paths A and D have one on every piece, and Path C on the Helm only (Mag. Acc.+10 at rank 30). Every rank's values: rank-augments.md.
- So a Bunzi's or Gleti's piece below rank 16, and a Nyame Path B piece at any rank, has no augment macc; count base stats only. A set or total quoted at rank 30 overstates each such Bunzi's or Gleti's piece by 15 macc.

### Elemental affinity, day and weather

- "Elemental Affinity: Magic Accuracy +X" (Magian staves, Atma) gives (X + 1) × 5 macc to that element's spells: +1 is +10, +2 is +15. It is assumed to give the same penalty to the element that element is strong against; an Ice staff penalises Wind (bg-wiki, Magic Affinity). FFXIclopedia gives 10 + 10X.
- The level 51 elemental staves have a hidden +20 (NQ) or +30 (HQ) for their element, and the same minus for the element theirs is strong against (bg-wiki, Category:Elemental Staves). The Magic Affinity page gives Aquilo's Staff (HQ) only +15.
- Those staves have no item level, so in the main hand they give up about 250 Magic Accuracy skill and Magic Accuracy+40. RDM and BLU can ignore affinity gear.
- A matching day or weather raises macc as well as damage, by an unknown amount, and Hachirin-no-Obi's page says the same of the obi. It is no reason to drop macc elsewhere (bg-wiki, Weather).

## Enhancing magic

### Where enhancing gear goes

- Skill, potency and duration are read when the spell lands, so they go in the midcast set. Casting time gear goes in precast.
- Enhancing skill never lengthens duration (bg-wiki, Category:Enhancing Magic). For a spell whose potency ignores skill or is already capped, every slot skill would take is better spent on duration.
- Some effects are read later, every melee round: tier II enspell damage, every enspell's magic accuracy, and "Sword enhancement spell damage +n". See Enspells.
- "Received" gear counts only on the person the spell lands on, and only if that person wears it when it lands: Phalanx+, the Refresh duration seconds pieces, and Brachyura Earring or Sheltered Ring for Protect and Shell. A caster's own copies do nothing for a spell cast on someone else.

### Enhancing skill

What skill does, by spell (bg-wiki, each spell's page; Community Red Mage Guide for the spells skill doesn't affect):

| Spell | What skill raises | Skill past which nothing improves |
|---|---|---|
| Phalanx, Phalanx II | damage cut per hit, in steps | 500 (−35) |
| Elemental barspells | resistance | 500 (+150) |
| Gain and Boost spells | the stat | 500 (+25) |
| Aquaveil | interruptions blocked | 501 (3 blocks) |
| Stoneskin | absorption, together with MND | skill + 3 × MND reaching 540 (350 absorbed) |
| Temper | Double Attack | not known; see Temper |
| Temper II | Triple Attack | 700 (40%) |
| Enspells | damage, and magic accuracy every round | none known |
| Refresh, Regen, Haste, Flurry, Protect, Shell, Blink, Sneak, Invisible, bar-status spells | nothing | none |

RDM enhancing skill without gear (bg-wiki, Red Mage; Merit Points; Master Levels):

| Step | Skill |
|---|---|
| Level 99 | 404 |
| + Magic Skills merits at 8/8 (+2 a level) | 420 |
| + the four job point gifts (+36): job mastery | 456 |
| + 1 per Master Level | 480 at Master Level 24; 481 at 25 |

- The gifts add +5, +8, +10 and +13 at 80, 405, 980 and 1805 job points spent. RDM has no job point category for enhancing skill.
- Each Master Level raises the cap of every skill the job learns natively by 1.
- bg-wiki's Red Mage table gives 404 at level 99, 440 at job mastery and 490 at Master Level 50. Those columns leave out merits.
- **(player)** A RDM 99 at Master Level 24 has 480 enhancing skill without gear, 24 more than bg-wiki's job mastery figure.
  - bg-wiki's numbers give the same 480: 404 + 16 (merits) + 36 (gifts) + 24 (Master Levels). The 24 is counted from 456, which includes merits; bg-wiki's own mastery column (440) leaves them out.
  - At Master Level 25 the same count is 404 + 16 + 36 + 25 = 481. The 16 is 8 enhancing skill merit levels.
- From 481 (Master Level 25), reaching 500 skill takes +19 from gear and reaching 501 takes +20. Each further Master Level lowers that by 1.
- Skill on gear shows as "Enhancing magic skill +X" or "All magic skills +X". Weapons and shields carry it too: Pukulatmuj +1 +11, Forfend +1 Path A +10 at max rank and Secespita +10. Gada +18 can't be worn by RDM or BLU (bg-wiki, Gada). Forfend +1's skill is a rank augment, +2 a rank from rank 11 to +10 at rank 15; rank-augments.md has every rank. Leth. Houseaux +3 has +35 and Shedir Seraweels +15.
- As a subjob, RDM has 144 enhancing skill at level 49, WHM 139 and SCH 133 (144 under Light Arts) (bg-wiki, Category:Enhancing Magic). Master Levels raise the subjob to level 49 + floor(Master Level ÷ 5), at most 59, so it is 54 at Master Level 25. bg-wiki gives no skill figures for subjob levels 50 to 59.
- That is far below 500, so on another job skill still raises potency, but slowly. At 144 skill Phalanx cuts 12 a hit and each 10 more skill adds 1, while one Phalanx+ piece adds up to 3 (Taeon) or 5 (Sakpata's Sword, Herculean). Phalanx+ gear comes before skill. Aquaveil stays at 1 block from skill.

### Phalanx

- Phalanx is self only, 180 s base. Phalanx II targets a party member, 240 s base. Both use the same formula (bg-wiki, Phalanx; Phalanx II):

```
skill 300 or less:  damage cut = floor(skill / 10) − 2
skill above 300:    damage cut = 28 + floor((skill − 300.5) / 28.5), capped at 35 (500 skill)
```

| Skill | 300 | 329 | 358 | 386 | 415 | 443 | 472 | 500 |
|---|---|---|---|---|---|---|---|---|
| Damage cut | 28 | 29 | 30 | 31 | 32 | 33 | 34 | 35 |

- Skill between steps does nothing: 410 still gives 31. A Phalanx set should land exactly on a step.
- "Phalanx +X" gear (bg-wiki lists it as "Phalanx" received) adds X to the cut. It counts only if the target wears it when the spell lands, and the bonus stays after it comes off (bg-wiki, Phalanx II; Phalanx (Status)). The caster's Phalanx+ does nothing for Phalanx II on someone else, so that set needs only 500 skill and duration.
- The cut is applied after damage taken gear has reduced the hit.
- Phalanx+ gear RDM or BLU can wear: Sakpata's Sword +5 (RDM, PLD, BLU) and Egeking +2 (RDM). Augments: Taeon, all five pieces, +1 to 3 each (RDM and BLU); Chironic and Merlinic, +1 to 5 each (RDM); Herculean, +1 to 5 each (BLU). A weapon swap resets TP.
- Taeon's Phalanx augment and its Regen potency augment come from the same Dusk augment slot, so one piece carries one or the other (bg-wiki, Category:Alluvion Skirmish Armor). A Phalanx set and a Regen set need separate copies.
- BLU's Barrier Tusk (−15% damage taken, applied after DT gear and able to pass the 50% cap) gains nothing from Phalanx+ gear. Phalanx overwrites it, and it can't overwrite Phalanx (bg-wiki, Barrier Tusk). bg-wiki's Phalanx (Status) page counts Barrier Tusk as raised by Phalanx+; the Barrier Tusk page says it isn't.

### Temper and Temper II

Both are self only, 180 s base (bg-wiki, Temper; Temper II):

```
Temper:     Double Attack = 5%                            below 360 skill
                          = floor((skill − 300) / 10)%    at 360 skill or more
Temper II:  Triple Attack = floor((skill − 300) / 10)%,   capped at 700 skill (40%)
```

- Temper's Double Attack adds to other Double Attack. Its page says it is no longer capped at 500 but marks that as needing information, and the talk page's data stops at 471 skill.
- Temper II's 700 cap was confirmed in 2025. Category:Enhancing Magic still says Temper, Temper II and the enspells have no known cap. Skill past 700 in a Temper II set does nothing.
- **(player, 2026-10-02)** 700 skill is hard to reach, so Temper II is in effect uncapped.
- Only the skill worn at the cast counts, and both pages say skill gear can come off afterwards. The Talk:Temper tester (2011) says he assumed that rather than tested it.

### Gain, Boost and barspells

- Gain spells are RDM, self only, 300 s base, and can't be used with Accession (bg-wiki, Category:Gain Spell):

```
stat bonus = floor((skill − 300) / 10) + 5, at least 5, capped at 25 (500 skill)
```

- Boost spells also give +25 at 500 skill or more.
- Vitiation Gloves +2, +3 and +4 list Gain +20, +30 and +30. No page says whether that is points or percent, or whether it goes past the 25 cap.
- Elemental barspells (bg-wiki, Category:Barspell):

```
resistance = 40 + floor(skill / 5)    up to 300 skill
           = 25 + floor(skill / 4)    above 300, capped at 150 (500 skill)
```

- Each 4 skill short of 500 costs 1 resistance: 480 skill gives 145.
- Gear adds on top of the 150. The only piece RDM or BLU can wear is Shedir Seraweels (+15).
- Base duration is 8 min whatever the skill. RDM's barspells target only the caster. A new barspell overwrites the old one whatever their potencies.
- Bar-status spells ignore skill: +30 resistance for the self-target versions and +20 for the area versions. Sroda Necklace (WHM, RDM) adds +20 for every recipient, but it also has Enhancing magic duration −50%, which counts in the native duration term. Keep it out of every other enhancing set (bg-wiki, Sroda Necklace).

### Enspells

- Base damage comes from enhancing skill: floor(skill ÷ 9) + 5 below 180 skill, and floor((skill − 180) ÷ 8) + 25 above it.

bg-wiki, Category:Enspell:

```
damage = (base + merits + job point gifts + Sword enhancement spell damage +n)
       × (Composure + the weapon's +n%)
       × staff or affinity × resist × resistance rank × day and weather × TMDA × other potency multipliers
```

- The Composure term is 3 while Composure is up (it triples, +200%; bg-wiki, Composure) and 1 without it; the 1 is inferred, since the pages give only the tripling. A weapon's "+n%" adds n/100 to that term, for that weapon's hits only. Staff, affinity, resist, resistance rank, day and weather, TMDA and the potency multipliers are the Magic damage terms (What multiplies with what).
- Tier I adds damage to every physical melee hit of a round: main hand, off hand and extra hits from multi-attack. Its damage is fixed at the cast, from the skill worn then. Skill gear, weapons included, only has to be on while casting.
- Tier II adds damage to the round's first hit only. Its damage is worked out again every attack round from the skill worn at that moment, and it rises by 1 a round up to twice that base. Casting gear does nothing for it. Its hits lower the target's resistance by 10 to the element strong against the enspell's element (Enblizzard II: −10 fire).
- Tier II overwrites tier I; tier I can't overwrite tier II. With high multi-attack (Temper II) and Dual Wield, tier I does more damage.
- Both tiers work out magic accuracy every attack round, from magic accuracy, the main weapon's Magic Accuracy skill and, on a RDM main job only, the enhancing skill worn at that moment. Magic Attack Bonus and Magic Damage do nothing for enspell damage.
- wsdist builds enspell damage the same way but never rolls a resist, so its enspell sets put no value on magic accuracy or on enhancing skill as accuracy (see Where wsdist and bg-wiki disagree).
- "Sword enhancement spell damage +n" works during melee rounds, so it has to be worn while attacking. On armor it applies to both hands; on a weapon, only to that weapon. Ghostfyre Cape's +5 is this kind, so in a casting set only its duration augment counts.
- A weapon's "+n%" adds to Composure's multiplier, for that weapon's hits only: Crocea Mors +500%, Vitiation Sword +400% and Duelist's Sword +300% (each a Path C augment), Pukulatmuj +1 +150% and Demersal Degen +1 +50%. Demersal Degen +1's is a rank augment that starts at rank 11 (+10% a rank) (rank-augments.md). Pukulatmuj +1's +150% is its rank 15 Unity augment (rank-augments.md, Oboro rank augments).
- Composure triples base Enspell damage and any Enspell +n.
- Merits and gifts add to the base, before the multiplier, for both hands. The En-spell Damage merit (RDM Group 2, up to 5 levels) adds +3 a level to tier I and +6 to tier II. The job point gifts add +5, +5, +6 and +7 at 125, 450, 1050 and 1900 job points spent, +23 in all. A mastered RDM with 5/5 merits adds +38 to a tier I base and +53 to tier II (bg-wiki, Merit Points; Job Points). Vitiation Tights boost the En-spell merit.
- With 0 En-spell Damage merits, the base gets only the gifts' +23, on both tiers, and the Vitiation Tights' En-spell merit augment adds nothing.

### Enhancing duration

bg-wiki, Enhancing Magic (also on the Lethargy set page):

```
Duration = (base + 6s × RDM Group 2 merit + 3s × relic hands merit augment + RDM job points + gear seconds)
         × Composure bonus from the Lethargy set (spells on others)
         × (1 + duration % listed on gear + Naturalist's Roll)
         × (1 + augmented duration %)
         × Rune Fencer gifts
         × Perpetuance
         × 3 for a RDM's self-cast under Composure, result capped at 1800 s
```

- bg-wiki states the Composure ×3 and its 30-minute cap in the text under the formula, not in it. A spell that already lasts more than 1800 s without Composure keeps its own duration (bg-wiki, Category:Enhancing Magic; Composure).

| Term | Size |
|---|---|
| RDM Group 2 merit, Enhancing Magic Duration | +6 s a level, up to 5 levels: +30 s |
| Relic hands merit augment (Vitiation Gloves; +3 and +4 checked) | +3 s per level of that merit: +15 s |
| RDM job points, Enhancing Magic Duration | +1 s a level, up to 20 levels: +20 s |
| Lethargy set, spells on others only | ×1.10, 1.20, 1.35, 1.50 for 2, 3, 4, 5 pieces |
| Rune Fencer gifts | RUN's own job point gifts, so always 1 on a RDM or BLU main job. A /RUN subjob gets no gifts; general game behavior, not stated on the pages read |
| Perpetuance | always 1 on RDM and BLU (see Accession and Perpetuance) |

- With 5 levels of Enhancing Magic Duration: 5 × 6 = 30 s from the merit, and 5 × 3 = 15 s more from Vitiation Gloves while worn. With the job point category at 20 (job mastery; Combat skill), the flat seconds are 30 + 20 = 50 s, or 50 + 15 = 65 s with the gloves.

- Duration that an item lists natively adds together. Augmented duration, such as Telchine's "Enh. Mag. eff. dur. +10", adds together in its own multiplier. So once some native duration is worn, +20% from an augment is worth more than +20% listed natively. Two native +25% pieces give +50%; a native +25% and an augmented +25% give 1.25 × 1.25, +56% (bg-wiki, Community Red Mage Guide).

Native duration gear RDM can wear (bg-wiki, Category:Enhancing Magic and item pages):

| Piece | Slot | Native duration |
|---|---|---|
| Lethargy Houseaux NQ, +1, +2, +3 | feet | 25, 30, 35, 40% |
| Estoqueur's Houseaux +1, +2 | feet | 10, 20% |
| Atrophy Gloves NQ, +1, +2, +3, +4 | hands | 15, 16, 18, 20, 20% |
| Vitiation Tabard +2, +3, +4 | body | 10, 15, 15% |
| Sucellos's Cape, any augments | back | 20% |
| Estoqueur's Cape | back | 10% |
| Ammurapi Shield | sub | 10% |
| Oranyan | main | 10% |
| Embla Sash | waist | 10% |
| Lethargy Earring, +1, +2 | right ear only | 7, 8, 9% |
| Sroda Necklace | neck | −50% |

Augmented duration gear, all in the second multiplier:

| Piece | Slot | Augmented duration |
|---|---|---|
| Duelist's Torque, +1, +2 | neck | up to 15, 20, 25%; an Oboro rank augment, full at rank 15, 20, 25 |
| Ghostfyre Cape | back | 10 to 20% |
| Telchine Cap, Chasuble, Gloves, Braconi, Pigaches | each | 1 to 10% |
| Grioavolr | main | 1 to 10% |
| Colada | main or sub | 1 to 4% |

- BLU can wear only the Telchine set and Colada from these lists. BLU has no native duration term to fill (bg-wiki, Category:Enhancing Magic).
- Telchine's duration augment shares its Dusk augment slot with its Regen potency augment, so one piece carries one or the other.
- Ghostfyre Cape (augmented 20%) against Sucellos's Cape (native 20%): Ghostfyre gives more when the set's other native duration is larger than its other augmented duration. Ghostfyre's edge in the total multiplier is 0.2 × (other native − other augmented), both as fractions (from the formula; bg-wiki, Ghostfyre Cape).
- Vitiation Gloves (+15 s in the base, with 5/5 duration merits) against Atrophy Gloves +3 or +4 (native 20%): the Atrophy Gloves win when the base seconds (spell base + merits + job points + gear seconds) are more than 75 × the native multiplier worn without the hands piece. With about +100% native already worn, that is about 150 s, so Atrophy Gloves win for 180 s spells and for Refresh. The more native duration is worn, the closer it gets. This is arithmetic from the formula, not stated on a page.
  - With 5 merit levels the gloves give the full +15 s (5 × 3), so the line above holds in full: 75 × the native multiplier (15 ÷ 0.2), about 150 s with +100% native worn. Atrophy Gloves still win for 180 s spells and for Refresh.
- Gear that lists seconds adds to the base before any multiplier:

| Piece | Seconds | Spell | Counts on |
|---|---|---|---|
| Telchine Chasuble | +12 s | Regen | not stated |
| Grapevine Cape | +30 s | Refresh I to III | wearer (received); RDM and BLU can wear it |
| Gishdubar Sash | +20 s | Refresh I to III | wearer (received); tested on self-casts only |
| Inspirited Boots | +15 s | Refresh | wearer (received); not BLU |

- The Refresh seconds pieces belong in a self-Refresh set only. Only the Grapevine Cape page says it can come off after the spell lands (bg-wiki, Refresh; Grapevine Cape).
- Naturalist's Roll adds to the native term: rolls 1 to 11 give 6, 7, 15, 8, 9, 10, 5, 11, 12, 13 and 20%, a bust −5%, and a GEO in the party adds 5% more. Under it each native piece is worth relatively less and each augmented piece relatively more.
- Duration and potency gear is read when the spell lands, so it goes in the midcast set.

### Composure and the Lethargy set

- Composure triples the duration of enhancing magic a RDM casts on itself, up to 30 minutes. A spell that would last longer than 30 minutes without Composure keeps that duration, and Composure does nothing for it (bg-wiki, Composure).
- Composure can't be used from a RDM subjob, even one above level 49 through Master Levels. BLU/RDM gets neither the ×3 nor the Lethargy bonus.
- FFXIclopedia says Protect, Shell and Reraise aren't tripled. bg-wiki lists no exceptions.
- On a self-cast under Composure, duration gear stops helping once the duration before the ×3 reaches 600 s. With 5 duration merit levels and 20/20 job points (5 × 6 + 20 = 30 + 20 = 50 s; Enhancing duration), the native and augmented multipliers together reach that at 600 ÷ (base + 50):

| Base | Spells | Multiplier that reaches 30 min |
|---|---|---|
| 150 s | Refresh I to III | 3.00 (600 ÷ 200) |
| 180 s | Phalanx, Temper, Temper II, enspells, Haste | 2.61 (600 ÷ 230) |
| 300 s | Gain spells, Blink, Stoneskin | 1.71 (600 ÷ 350) |
| 480 s | barspells | 1.13 (600 ÷ 530) |
| 600 s | Aquaveil | 1.0: capped with no gear (600 + 50 = 650 s) |

- Past that point, a self-cast set can spend its slots on skill, potency or recast. Casts on others have no such cap. The table is arithmetic from the formula. Vitiation Gloves' +15 s (5 × 3) lowers each multiplier a little more.
- Self-only spells: Phalanx, Temper, Temper II, the Gain spells, RDM's barspells, Aquaveil, Blink, Stoneskin and the enspells. They get Composure's ×3 and never the Lethargy bonus. Spells that can go on others: Phalanx II, Refresh I to III, Regen I and II, Haste, Haste II, Flurry, Flurry II, Protect, Shell, Sneak and Invisible. Only the second group needs a variant set for casting on others (bg-wiki, each spell's target field).
- The Lethargy set bonus gives Composure's bonus to enhancing magic cast on others and to enfeebling magic: +10, +20, +35 and +50% for 2, 3, 4 and 5 pieces. It counts Estoqueur's +2 and Lethargy NQ, +1, +2 and +3 pieces, mixed. Spells you cast on yourself get nothing from it. It counts the pieces worn during the cast, and it multiplies separately from the native and augmented totals (bg-wiki, Lethargy Armor Set).
- Whether Composure must be active for the set bonus on enhancing magic isn't stated: the set page only says it augments Composure. Category:Enfeebling Magic ties the enfeebling bonus to Composure being used.
- Leth. Houseaux +3's native +40% works on enhancing magic cast on anyone, unlike the set bonus.

### Refresh

- Refresh gives 3 MP a tick, Refresh II 6 and Refresh III 9, each for 150 s base. All three can target party members (bg-wiki, Refresh).
- "Refresh" potency gear adds MP a tick:

| Piece | Slot | "Refresh" potency |
|---|---|---|
| Lethargy Fuseau NQ, +1, +2, +3 | legs | +1, +2, +3, +4 |
| Estoqueur's Fuseau +2 | legs | +1 |
| Amalric Coif, Amalric Coif +1 | head | +1, +2 |
| Atrophy Tabard +2, +3, +4 | body | +1, +2, +2 |

- If the three slots add together, Refresh III reaches 9 + 8 = 17 MP a tick. No page states the stacking outright, and none says whether the potency works on Refresh cast on others.
- "Refresh"+N without the word potency is the wearer's own MP a tick, not spell potency. Atrophy Tabard +4 lists both: "Refresh" potency +2 and "Refresh"+3 (bg-wiki, Atrophy Tabard +4). Vitiation Chapeau's "Refresh"+2 or +3 and Lethargy Sayon +3's "Refresh"+4 have the passive wording. They belong in idle sets, not the Refresh midcast set.
- **(player, 2026-10-02)** "Refresh +X" is MP the wearer receives passively each tick while the item is equipped. "Refresh potency" is a bonus to the recipients of a Refresh spell the player casts.
  - This doc uses the two terms that way. By the player's definition the potency reaches party members the spell lands on, not only the caster; no bg-wiki page read says so.
- Refresh duration seconds pieces are all "received"; see Enhancing duration.

### Regen

- Regen gives 5 HP a tick for 75 s and Regen II 12 HP a tick for 60 s, ticking every 3 s. Both can target party members. Light Arts' Regen bonus works only on a SCH main job, so RDM/SCH gets none (bg-wiki, Regen II; Category:Regen Spell).

```
HP a tick = (base + base × % bonus) × Embolden + flat "Regen" potency +X
```

- Flat "Regen" potency is added after the percentages, so on Regen II it is worth far more than percentage gear.
- Regen potency gear RDM or BLU can wear:
  - Telchine augment, +1 to 3 a piece, five pieces. It shares a slot with Telchine's duration augment.
  - Taeon augment, +1 to 3 a piece, five pieces. It shares a slot with Taeon's Phalanx augment. Category:Regen Spell doesn't list it.
  - Bolelabunga (club), +10%: 10% of the base, floored, plus 1, so +1 on Regen and +2 on Regen II. A main-hand swap resets TP (bg-wiki, Bolelabunga).
  - Bunzi's Sabots (WHM, RDM, BRD, SMN): Path A gains "Regen" potency with rank. A rank 0 pair adds none; rank-augments.md has every rank's value.
- Telchine Chasuble adds +12 s (4 ticks) to Regen's base.

### Stoneskin

- On a RDM main job, base absorption reaches the 350 cap with little or no help: in the top band it caps when skill + 3 × MND reaches 540, so 480 skill needs only 20 MND. Enhancing skill and MND gear add nothing to a RDM Stoneskin. Only "Stoneskin +X" gear raises it, past the cap (bg-wiki, Category:Enhancing Magic; Stoneskin).
- Stoneskin, as pasted by the player from bg-wiki, where S = skill ÷ 3 + MND:

| S | Damage absorbed |
|---|---|
| below 80 | skill ÷ 3 + MND (bg-wiki says this is likely wrong, since it doesn't meet the next line) |
| 80 to 130 | 2 × skill ÷ 3 + 2 × MND − 60 |
| 130 and up | skill + 3 × MND − 190 |

- At level 99 every RDM or BLU Stoneskin is in the top band, where 1 MND is worth 3 skill.
- Stoneskin caps at 350. "Stoneskin +X" gear goes past the cap, up to 475: 350 plus the best piece in each of the five slots that have one. Every piece counts in full.

| Piece | Slot | Stoneskin+ | Jobs |
|---|---|---|---|
| Shedir Seraweels | legs | +35 | WHM, BLM, RDM, BRD, SMN, BLU, SCH, GEO |
| Haven Hose | legs | +20 | all |
| Stone Mufflers | hands | +30 | WAR, RDM, PLD, DRK, BST, RNG, SAM, DRG, BLU, RUN |
| Nodens Gorget | neck | +30 | WHM, BLM, RDM, BRD, SMN, SCH, GEO (not BLU) |
| Stone Gorget | neck | +30 | all |
| Siegel Sash | waist | +20 | includes RDM and BLU |
| Earthcry Earring | ear | +10 | all; Rare, so one ear only |

- Both jobs can reach 475: Shedir Seraweels, Stone Mufflers, Siegel Sash, Earthcry Earring, and Nodens or Stone Gorget (Stone Gorget on BLU).
- The bg-wiki Stone Mufflers and Earthcry Earring pages word their bonus as raising the Stoneskin cap. Read literally, that would do nothing for a caster below 350. The Stoneskin and Siegel Sash pages say it adds a flat amount. It only matters for a subjob caster under the cap.
- Siegel Sash's +20 only has to be worn during the cast, and it only works on the Stoneskin spell, not Diamondhide, Metallic Body or Earthen Ward (FFXIclopedia). bg-wiki's Metallic Body and Diamondhide pages say the same for those two. Its casting time −8% belongs in precast, so it helps in both sets.
- FFXIclopedia says the same for Stone Gorget: Stoneskin+ only has to be worn during the cast. bg-wiki says nothing about timing.
- Stoneskin costs 29 MP, casts in 7 s, recasts in 30 s, lasts 300 s and targets the caster only. WHM learns it at 28, RDM 34, SCH 44 and RUN 55. BLU has none of its own and casts it from a subjob; /RUN reaches level 55 only at Master Level 30 (bg-wiki, Stoneskin; Master Levels).
- From a subjob, the cap needs (540 − skill) ÷ 3 MND: about 132 as /RDM (144 skill) and 134 as /WHM (139 skill), a little less for a subjob raised above 49 by Master Levels. Each 3 skill on gear lowers that by 1 MND. Below it, MND and skill gear still raise absorption; at or above it they do nothing.
- Stoneskin doesn't overwrite an active Stoneskin, so a stronger cast can't replace a weaker one until the old one breaks or wears off. It does overwrite Metallic Body, Diamondhide, Earthen Ward and Afflatus Solace's Stoneskin, and they can't overwrite it (FFXIclopedia, Stoneskin; bg-wiki, Metallic Body).
- With Accession, the caster's Stoneskin+ gear only raises the caster's own Stoneskin. The party gets only the skill and MND part, capped at 350.
- Under Composure a RDM self-cast Stoneskin lasts 15 minutes before duration gear. BLU/RDM's lasts 300 s plus duration gear.

### Spells skill doesn't affect

Skill does nothing for these. Apart from Spikes, their pages give fixed values and list no gear that changes potency, so their sets are duration (and recast).

- Haste: 14.6% magic haste (150/1024). Haste II: 30% (307/1024). Each 180 s base, single target, no Accession (bg-wiki, Haste II).
- Flurry II: 30% Snapshot, 180 s base. Haste, Haste II and Slow overwrite it. Flurry's value was never published; bg-wiki's Snapshot page says most believe 15%. Neither works with Accession (bg-wiki, Flurry II).
- Protect and Shell: 30 min base, fixed per tier (Protect V +220 defense, Shell V −75/256 magic damage, about −29%). The only gear is Brachyura Earring or Sheltered Ring worn by the recipient (+10 defense and −5/256 at tier V). The two don't stack, and the bonus stays after they come off (bg-wiki, Category:Protect Spell; Category:Shell Spell).
- Blink: self only, 300 s or until its shadows are used. 2 shadows a cast. It overwrites itself.
- Sneak and Invisible: 450 to 600 s base, at random. Skulker's Cape (WHM, BLM, RDM, SMN, BLU, SCH, GEO) adds 30 s to each. Dream Boots +1 (Sneak) and Dream Mittens +1 (Invisible) add 30 s, which the page says applies only once the duration timer is maxed out (bg-wiki, Sneak).
- Spikes scale with INT, not skill, and with Magic Attack Bonus against the target's magic defense. Blaze Spikes: floor((INT + 50) ÷ 12), up to 25. Ice and Shock Spikes: floor((INT + 50) ÷ 20), up to 15. 180 s base. Vitiation Tights (every tier) list "Spikes" spell damage +30; how it combines isn't stated (bg-wiki, Community Red Mage Guide).

### Accession and Perpetuance

- Accession is a SCH level 40 ability, so RDM/SCH and BLU/SCH have it. It doubles the MP cost and, by its description, the casting time; its notes say recast instead. From a SCH subjob it triples the recast (bg-wiki, Accession).
- Its spell list names Phalanx, Stoneskin, Blink, Aquaveil, barspells, enspells, Regen I to V, Refresh (only the first tier is named), Protect, Shell, Sneak and Invisible. Haste and Flurry are excluded, and Gain spells can't be used with it. The page adds that it usually doesn't work on spells only another main job can use while subbing SCH. Whether Refresh II, Refresh III or Phalanx II work isn't stated.
- The caster's Aquaveil+ gear carries to every target. Phalanx+ and Stoneskin+ don't: each recipient needs their own Phalanx+, and the caster's Stoneskin+ only raises their own.
- Perpetuance is a SCH level 87 ability. A subjob reaches at most level 59, so RDM and BLU never have it, and the formula's Perpetuance term is 1 (bg-wiki, Perpetuance; Master Levels).

## Spell interruption

- Spell interruption rate down (SIRD) is checked against each enemy attack during the cast, so it only works in the midcast set. SIRD in precast does nothing (bg-wiki, Spell Interruption Rate).
- At −102% SIRD, physical damage can no longer interrupt a cast. SIRD past −102% does nothing.
- SIRD merits give −2% a level, up to −10%.
- Fi Follet Cape +1 Path A carries SIRD as a rank augment: −1% from rank 6, rising to −5% at rank 15.
- Shield Mastery (RDM trait at 87 and 97, +10 and +20 TP a block): a blocked attack can't interrupt a spell, but every attack of a multi-attack round has to be blocked. It needs a shield in the sub slot (bg-wiki, Shield Mastery; see Shield block).

### Aquaveil

- Self only. Lasts 10 min base, or until its blocks are used. Under Composure its 600 s already reaches 30 min, so duration gear does nothing for a RDM self-cast.

| Enhancing skill | Interruptions blocked |
|---|---|
| 300 or less | 1 |
| 301 to 500 | 2 |
| 501 or more | 3 |

- 500 is one short of the third block. A 2026 test at 701 skill found no fourth step, so skill past 501 does nothing (bg-wiki, Aquaveil; Talk:Aquaveil).
- bg-wiki's Community Red Mage Guide and FFXIclopedia say skill gives at most 2 blocks, reached at 355 skill. The Aquaveil page cites tests for 1/2/3 and is used here.
- "Aquaveil +X" gear adds blocks:

| Piece | Slot | Aquaveil+ | BLU can wear it |
|---|---|---|---|
| Amalric Coif +1 | head | +2 | yes |
| Amalric Coif | head | +1 | yes |
| Chironic Hat | head | +1 | no |
| Regal Cuffs | hands | +2 | yes |
| Emphatikos Rope | waist | +1 | yes |
| Shedir Seraweels | legs | +1 | yes |

- RDM can wear all six. Vadose Rod and Nibiru Faussar are also +1, but neither RDM nor BLU can equip them.
- The most gear gives is +6 (head 2, hands 2, waist 1, legs 1). A RDM at 501 skill blocks 9. BLU casting from a subjob gets 1 from skill, so 7.

## Enfeebling magic

### Where enfeebling gear goes

- Everything that decides whether an enfeeble lands, how strong it is and how long it lasts goes in the **midcast** set: magic accuracy, enfeebling skill, MND or INT, "Enfeebling magic effect +", enfeebling duration, the Saboteur hands, Lethargy set pieces and "Immunobreak"+1.
- bg-wiki doesn't say whether enfeebling gear is read when the cast finishes or when the effect lands. It does say the Lethargy Gantherots' Saboteur bonus needs them on during midcast, and the Composure set bonus counts the pieces worn when the spell is cast (bg-wiki, Leth. Ganth. +3 and Composure). Either way the midcast set is the one that counts. Nothing in the precast set or the job ability set counts.
- Precast takes Fast Cast and "Enfeebling magic casting time −X%": Lethargy Chappel −14, −15, −16 and −17% (NQ to +3), Estoqueur's Chappel +1 and +2 −8 and −12%, Wikyo Cloak −7%. bg-wiki says this shares the 80% cap with Fast Cast (bg-wiki, Category:Enfeebling Magic). For the dispute, see "Does anything break the 80% cap?".
- Saboteur multiplies only the base part of potency and duration. Effect+ gear multiplies the whole potency. Duration gear multiplies the whole duration.
- Effect+ gear only works on the spells in the "Effect+" column below. It does nothing for Sleep, Bind, Silence, Break, Dispel or Inundation, and for Dia it adds damage over time but no defense down.

### What each spell scales with

Each value is read from the spell's own bg-wiki page. "Stops improving at" is where skill or dSTAT stops adding potency, before Saboteur and effect+ gear.

| Spell | Potency set by | Stops improving at | Effect+ | Innate magic accuracy | Base duration | Can Immunobreak |
|---|---|---|---|---|---|---|
| Frazzle, Distract | skill, dMND | 125 skill (25) + 50 dMND (10): 35 | yes | +150 | 5 min | no |
| Frazzle II, Distract II | skill, dMND | 350 skill (40) + 50 dMND (10): 50 | yes | +150 | 5 min | no |
| Frazzle III | skill, dMND | 625 skill (120) + 50 dMND (10): 130 magic evasion down | yes | +150 | 5 min | no |
| Distract III | skill, dMND | 610 skill (120) + 50 dMND (10): 130 evasion down | yes | +150 | 5 min | no |
| Poison | skill | 500 skill: 55 HP a tick | yes | none listed | 90 s | yes |
| Poison II | skill | no known cap | yes | +30 | 120 s | yes |
| Slow | dMND | +75 dMND: 300/1024 (29.3%) | yes | +10 | 180 s | yes |
| Slow II | dMND | +75 dMND: about 39.1% | yes | +10 | 180 s | yes |
| Paralyze | dMND | +40 dMND: 25% | yes | −10 | 120 s | yes |
| Paralyze II | dMND | +40 dMND: 34% | yes | +10 | 120 s | yes |
| Addle | dMND | +100 dMND: −40 magic accuracy | yes | +20 | 3 min | no |
| Addle II | dMND | +100 dMND: −70 magic accuracy | yes | +20 | 3 min | no |
| Blind | dINT | +120 dINT: −50 accuracy | yes | none listed | 180 s | yes |
| Blind II | dINT | +120 dINT: −94 accuracy | yes | +10 | 180 s | yes |
| Gravity | fixed, about −26% movement | — | yes | none listed | 30 to 120 s | yes |
| Gravity II | fixed, −32% movement | — | yes | none listed | 60 to 120 s | yes |
| Dia, Dia II, Dia III | fixed defense down | — | damage over time only | resisted only by Magic Shield or immunity | 60, 120, 180 s | no |
| Sleep, Sleep II | none | — | no | none listed | 60, 90 s | yes |
| Silence | none | — | no | none listed | 120 s | yes |
| Break | none | — | no | none listed | 30 s | yes |
| Bind | none | — | no | none listed | 0 to 60 s | yes |
| Dispel | none | — | no | +175 | — | no |
| Inundation | none | — | no | resisted only by full magic immunity | 5 min | no |

- Frazzle and Distract (all tiers) are black magic but use dMND, not dINT, for both potency and magic accuracy.
- Effect+ also works on Diaga and Poisonga. Breakga, Poisonga, Sleepga and Sleepga II can Immunobreak (bg-wiki, Category:Enfeebling Magic).

### Enfeebling potency

bg-wiki, Poison II and Category:Enfeebling Magic (the Community Red Mage Guide gives the same):

```
Potency  = floor( floor(base × Saboteur + dSTAT part) × (1 + enfeebling magic effect %) )
Saboteur = 2.00 on normal monsters, 1.25 on Notorious Monsters, plus the Saboteur % on the hands
```

- Saboteur multiplies only the base: the skill part for Frazzle and Distract, the fixed part for Addle and Gravity. It never multiplies the dMND or dINT part (bg-wiki, Saboteur).
- Effect+ multiplies everything, dSTAT part included, so it is worth more with Saboteur up.
- bg-wiki gives Slow, Paralyze and Blind as a single function of dMND or dINT and doesn't split them into a base and a dSTAT part. The Community Red Mage Guide does: Slow II = base × Saboteur + 0.15% × (75 + dMND), and Paralyze II = base × Saboteur + 0.25% × (40 + dMND). The guide's bases (12.5% and 10%) predate the August 2019 merit change, which raised them to 16.5% and 14% (bg-wiki, Slow II and Paralyze II). With those bases the guide's form matches the spell pages' end points.

### Enfeebling magic effect + gear

bg-wiki, Category:Enfeebling Magic, and each item's page:

| Item | Effect + |
|---|---|
| Lethargy Sayon, +1, +2, +3 | 12, 14, 16, 18% |
| Estoqueur's Sayon +2 | 10% |
| Regal Gem (ammo) | 10% |
| Sucellos's Cape (base stat, so every augment version has it) | 10% |
| Vitiation Boots +2, +3, +4 | 5, 10, 10% |
| Duelist's Torque, +1, +2 | 5, 7, 10% |
| Uk'uxkaj Boots | 6% |

- The pieces are treated as adding into one multiplier. No page says so outright; the formula has one effect+ term, and Gravity II's test table lists combined totals (+10, +14, +24). Sayon +3, Regal Gem, Sucellos's Cape, Vitiation Boots +4 and Duelist's Torque +2 together give +58%.

### Potency by spell

```
Frazzle III  = floor(6/21 × (enfeebling skill − 205)) + floor(dMND ÷ 5)    skill part tops out at 120 (625 skill)
Distract III = floor(6/21 × (enfeebling skill − 190)) + floor(dMND ÷ 5)    skill part tops out at 120 (610 skill)
               dMND part held to 0 to 10 (+50 dMND)
Frazzle II   = (enfeebling skill − 150) ÷ 5, 40 at 350 skill, + up to 10 from dMND (Community Red Mage Guide)
```

- Each 3.5 skill is worth one point of Frazzle III or Distract III, up to 625 or 610.
- Distract III's −130 cap applies before potency gear (bg-wiki, Distract III). Frazzle III's page gives the same −130 cap with no qualifier. A Distract III test on an NM measured 132 with Saboteur and 152 with Saboteur and +12% gloves, both past 130, and both fit the formula (bg-wiki, Talk:Saboteur). So Saboteur and effect+ go past the cap, at least for Distract III.

```
Poison, 400+ skill     = (skill − 225) ÷ 5 HP a tick; 55 at 500 skill, nothing more past 500
Poison II, 400 to 500  = 82 − floor(129/430 × (500 − skill))
Poison II, above 500   = 82 + floor(180/783 × (skill − 500)); no known cap
```

```
Slow     = (2 × dMND + 150) ÷ 1024 for dMND ≥ 0, (dMND + 150) ÷ 1024 below; held to 75/1024 to 300/1024
Addle    = 20 + floor(dMND ÷ 5) magic accuracy down; dMND part up to 20 (+100 dMND)
Addle II = 50 + floor(dMND ÷ 5), up to 70; also lengthens the target's casting time 25 to 40%
Blind    = (dINT + 80) ÷ 4 above about −40 dINT, (dINT + 120) ÷ 8 below; held to 5 to 50 accuracy down
```

- Slow II runs from about 16.5% at −75 dMND to 39.1% at +75. Paralyze runs from 5% at −40 dMND to 25% at +40; Paralyze II from 14% to 34%. Blind II runs from 19 at −80 dINT to 94 at +120 (bg-wiki, Slow, Slow II, Paralyze, Paralyze II, Blind, Blind II).
- The Addle pages say skill does nothing for their potency. The Slow, Paralyze and Blind pages use only dMND or dINT.
- MND past +40 dMND does nothing for Paralyze's potency, past +75 for Slow and past +100 for Addle; INT past +120 dINT does nothing for Blind. After that, effect+ gear is the only potency left. dSTAT still adds magic accuracy past these points; see "Choosing a land-rate or potency set".

**Fixed-potency spells.**

- Gravity is about −26% movement speed and Gravity II −32%. Skill and stats don't change them; only Saboteur and effect+ do (bg-wiki, Gravity and Gravity II).
- Gravity II tests: effect +24 alone gave −38 to −39%, Saboteur alone −62%, effect +24 with Saboteur −76%, and with Saboteur +12% hands as well −80% (bg-wiki, Gravity II). These run a few points under the formula, and the page doesn't say why.
- Dia, Dia II and Dia III lower defense by a fixed 104, 156 and 208/1024 (10.16, 15.23 and 20.31%) and deal 1, 2 and 3 HP a tick. Effect+ adds 1 HP a tick per 1% and nothing to the defense down (bg-wiki, Category:Enfeebling Magic).

### Enfeebling skill

- Enfeebling skill sets every enfeeble's magic accuracy and interruption rate, and raises the Immunobreak chance. It adds potency only to Frazzle, Distract, Poison and Poison II (bg-wiki, Category:Enfeebling Magic).
- RDM enfeebling skill without gear is 424 at level 99, 460 at job mastery and 510 at Master Level 50. The job point gifts add +5, +8, +10 and +13 at 60, 360, 910 and 1710 job points spent; each Master Level adds 1. The Magic Skills merit category adds +2 a level, up to 8 levels (bg-wiki, Red Mage, Master Levels and Merit Points).
- At Master Level 25 with 8 enfeebling skill merit levels, that is 460 + 25 + 16 = 501. Gear then needs +109 skill for Distract III's 610 (610 − 501) and +124 for Frazzle III's 625 (625 − 501).
- Obstinate Sash (MND +5, enfeebling duration +5%) is an Odyssey item. Its augment reaches Magic Accuracy +15, enfeebling skill +15 and Enmity −5 at rank 30 (bg-wiki, Obstin. Sash). At rank 20 it has Magic Accuracy +15 and enfeebling skill +5, and no Enmity; rank-augments.md has every rank.

### Saboteur

- Saboteur doubles (+100%) the base potency and base duration of enfeebling magic on normal monsters, and adds only +25% on Notorious Monsters (bg-wiki, Saboteur).
- It lasts 60 seconds with a 3-minute recast. Since February 2019 casting an enfeeble doesn't end it, so every enfeeble cast in that minute gets it.
- It also raises magic accuracy. The base amount scales with level, and bg-wiki gives no number. The Saboteur Effect job point category adds +2 a level, +40 at 20 levels. bg-wiki's notes say the bonus works on all spells; the job point line and the Job Points table call it enfeebling magic accuracy.
- It raises the Immunobreak chance.

The hands add their % to Saboteur's bonus, in full on NMs too:

| Hands | Saboteur + | Saboteur on normal monsters | On NMs |
|---|---|---|---|
| Estoqueur's Gantherots +1, +2 | 5, 10% | ×2.05, ×2.10 | ×1.30, ×1.35 |
| Lethargy Gantherots, +1, +2, +3 | 11, 12, 13, 14% | ×2.11 to ×2.14 | ×1.36 to ×1.39 |

- The hands only count if worn in midcast. They don't need to be on when Saboteur is used (bg-wiki, Leth. Ganth. +3).
- Leth. Ganth. +3's Saboteur bonus is a confirmed bug on Dia and doesn't apply correctly (bg-wiki, Category:Enfeebling Magic, linking a Square Enix forum report). The page names only the +3. On Dia the hands still count as a Lethargy set piece.

### Stymie

- Stymie gives the next enfeeble 100% magic accuracy. Forced resist states, complete immunity and "Resist!" traits still win. It lasts until an enfeeble lands or 60 seconds pass, with a 1-hour recast (bg-wiki, Stymie).
- The Resist page adds an exception: at the 5% negative-status rank, which is otherwise a guaranteed full resist, an enfeeble landed with Stymie gets through at half duration.
- Each level of the Stymie Effect job point category adds 1 second to that spell's duration, +20 at 20 levels.

### Enfeebling duration

bg-wiki, Category:Enfeebling Magic (the Community Red Mage Guide gives the same):

```
Duration = ceil( (base × Saboteur
                  + 6s × "Enfeebling Magic Duration" merits
                  + 3s × relic head augment
                  + enfeebling duration job points
                  + Stymie job points, only for a spell cast under Stymie)
               × Composure bonus from the Lethargy set
               × (1 + duration % listed on gear)
               × (1 + augmented duration %) )
```

- Saboteur multiplies only the spell's base seconds. The set bonus and duration gear multiply the whole sum. The Category page's summary says duration gear raises the base duration, but its own formula and the tests below apply it to the whole sum.
- Native duration (listed on the item) adds together into one factor. Augmented duration (the Duelist's Torque) is a separate factor, as with enhancing magic.
- The result rounds up (bg-wiki, Talk:Distract III).

| Item | Enfeebling duration | Factor |
|---|---|---|
| Regal Cuffs | 20% | native |
| Kishar Ring (also Fast Cast +4%) | 10% | native |
| Snotra Earring (RDM only; there is no Snotra Ring) | 10% | native |
| Obstinate Sash | 5% | native |
| Duelist's Torque, +1, +2 | 15, 20, 25% at max rank (15, 20, 25) | augmented |

- Sucellos's Cape has enhancing duration +20% but no enfeebling duration. A Talk:Distract III editor once listed it at +20% enfeebling and Snotra at 25%; both were corrected there.
- `//gs export` doesn't show the torque's rank.

Flat seconds, added before the multipliers:

- The Group 2 merit "Enfeebling Magic Duration" gives +6 s a level, +30 s at 5 levels.
- Duelist's Chapeau +2 and Vitiation Chapeau (NQ to +4) add +3 s per level of that merit, +15 s at 5 (bg-wiki, Viti. Chapeau +4).
- The RDM job point category "Enfeebling Magic Duration" adds +1 s a level, up to +20 s.
- Group 2 allows 5 levels per category and 10 levels in all (bg-wiki, Merit Points), so the relic head's duration and the relic boots' Immunobreak augments compete with the other Group 2 merits.
- With 0 levels of Enfeebling Magic Duration: 0 s from the merit and 0 s from the relic head, worn or not. With the job point category at 20 (job mastery), that is 20 s, with or without the relic head. Dia's flat sum uses the same seconds.

### Lethargy set on enfeebles

- The Composure set bonus is +10, +20, +35 and +50% for 2, 3, 4 and 5 pieces. Any mix of Estoqueur's +2 and Lethargy NQ, +1, +2 and +3 pieces counts, and NQ Lethargy pieces count too (bg-wiki, Lethargy Armor Set).
- For enfeebling magic it works through Composure, so Composure must be up. bg-wiki's Category:Enfeebling Magic ties the bonus to Composure; the Lethargy set page only says the set augments Composure.
- Composure lasts 2 hours and raises the recast of all magic by 25% while it is up (bg-wiki, Composure; see Other recast modifiers).

### Duration examples

bg-wiki, Talk:Distract III (Kriz's test on a test dummy, which took the NM Saboteur rate): Distract III (300 s) with Saboteur and Leth. Ganth. +3 (×1.39), 30 s of merits, 15 s from the relic head, 20 s of job points, 4 Lethargy pieces (×1.35), 25% native duration (Snotra, Kishar, Obstinate) and 25% augmented (Duelist's Torque +2):

```
((300 × 1.39) + 30 + 15 + 20) × 1.35 × 1.25 × 1.25 = 1016.7 → 1017 s
with Stymie's 20 s: 1059 s, against 17:40 (1060 s) tested
```

The same formula reproduces the page's other four tests to the second.

**Saboteur hands or Regal Cuffs.**

- In a tested Distract III with Saboteur and 5 Lethargy pieces, swapping Leth. Ganth. +3 for Regal Cuffs cut the duration from 18:15 to 17:20 (bg-wiki, Talk:Distract III). The hands' Saboteur +14% and fifth set piece beat the cuffs' 20%.
- Without Saboteur the same formula favours Regal Cuffs (about 856 s against 820 s for that set). That is arithmetic from the formula, not a test.
- A page editor warns that dropping the relic head, relic boots and Empyrean hands for duration costs Distract III a lot of potency on a spell that already lasts long.

### Dia duration

Dia's duration is worked out in a different order (bg-wiki, Category:Enfeebling Magic):

```
Dia duration = (base + enfeebling duration job points + 6s × merits + 3s × relic head augment)
             × Saboteur × Composure set bonus × (1 + native duration %) × (1 + augmented duration %)
             + Stymie job points × (1 + native duration %) × (1 + augmented duration %)
```

- For Dia, Saboteur multiplies the whole flat sum, not just the base. The Stymie seconds get no Saboteur or set bonus.

### Immunobreak

- When one of the spells marked "Can Immunobreak" above is resisted, it may Immunobreak: the monster's negative-status resistance rank for that effect drops one step until that effect lands (bg-wiki, Category:Enfeebling Magic).
- Frazzle, Distract, Addle, Dia, Dispel and Inundation can't trigger it. The Community Red Mage Guide says Addle II can; bg-wiki's list leaves it out.
- It only happens from a starting rank of 5% to 30% (the high-resistance ranks), and never takes the rank past 50%. The page's wording here reads as contradictory; read with its rank table, this is what it means.
- "Immunobreak"+1 makes each Immunobreak drop the rank two steps. Only Chironic Hose has it, as a base stat, and it works while equipped.
- The chance rises with enfeebling skill, the number of resists, Saboteur, the Group 2 "Immunobreak Chance" merit (+3% a level, up to +15%) and the relic boots' augment (Duelist's Boots +2 to Vitiation Boots +4: +1% per level of that merit, up to +5%; bg-wiki, Viti. Boots +4).
- So Chironic Hose and the relic boots belong in the midcast sets of Immunobreak spells against high-resistance targets, and do nothing for Frazzle, Distract, Addle, Dia or Dispel. The relic boots' augment does nothing without Immunobreak Chance merits.
- With 0 Immunobreak Chance levels, the merit's +3% a level and the relic boots' augment are both 0. The chance then comes from enfeebling skill, the number of resists and Saboteur. Chironic Hose still makes each Immunobreak drop two steps.

### Choosing a land-rate or potency set

**Resist states.**

- Enfeebles with a fixed duration have two resist states: full duration and half (Sleep: 60 s or 30 s). At the 95% magic hit-rate cap, bg-wiki gives 99.75% to land but only 95% to land for full duration, so 4.75% half and 0.25% resisted (bg-wiki, Resist). Magic accuracy short of the cap costs duration as well as land rate.
- On at least some NMs, each resisted Silence adds a point to a hidden counter, and the Silence that lands loses about 3.5% of its duration per point. The counter drains about one point every 70 seconds and is kept per spell (bg-wiki, Silence).
- dSTAT still adds magic accuracy after it stops adding potency. The Community Red Mage Guide says accuracy-only enfeebles have no dSTAT that matters; a Talk page editor calls that wrong (bg-wiki, Talk:Community Red Mage Guide). So MND or INT still helps Sleep, Bind, Silence, Break and Gravity land.

**By spell.**

- **No potency** (Sleep, Sleep II, Silence, Break, Bind): magic accuracy and duration. Effect+ does nothing. On NMs, lean further toward magic accuracy for Silence. bg-wiki says INT may lower the chance that Bind wears off when the bound monster is hit; the page only says "may" (bg-wiki, Bind).
- **dSTAT potency** (Slow, Paralyze, Addle, Blind): MND or INT to the spell's cap, then effect+. Skill only helps them land. Paralyze's −10 innate magic accuracy is the lowest of these.
- **Skill potency** (Frazzle III, Distract III, Poison, Poison II): skill to the spell's cap, MND to +50 dMND for Frazzle and Distract, then effect+. The Community Red Mage Guide prefers enfeebling skill over magic accuracy for these, because skill is also magic accuracy. Poison stops at 500 skill, so effect+ beats skill past that. Poison II has no known cap, but the guide says effect+ still beats skill for it "for now". The +150 innate magic accuracy of Frazzle and Distract lets their sets lean on skill and potency.
- **Frazzle II, Distract II and Dispel**: the guide casts them in a full magic accuracy set. Its usage: Frazzle II first in that set, then Frazzle III in the potency set; if Frazzle III misses, Frazzle II stays on. Distract II and III work the same way. RDM is past 350 skill without gear.
- **Gravity, Gravity II**: magic accuracy and effect+. INT (dINT, since they are black magic; see dSTAT) and skill only help them land. The guide says Gravity II at full potency with Saboteur passes −100% movement speed on a normal monster; the Gravity II tests above stop at −80% with less gear.
- **Dispel**: +175 innate magic accuracy. Every Duelist's Torque tier (NQ, +1, +2) carries "Dispel"+1, which removes one extra effect, so the torque goes in the Dispel set (bg-wiki, Dispel and Dls. Torque +1).
- **Dia**: duration only. Only Magic Shield or immunity resists it, and effect+ doesn't raise its defense down.
- **Inundation**: duration only. Only full magic immunity resists it, and effect+ doesn't touch it. Its debuff multiplies skillchain damage by 1.2 for each different weapon type, only when the weapon skills come from different players, NPCs or trusts (bg-wiki, Inundation). The guide adds Treasure Hunter to its Inundation set.

**With Saboteur or Stymie up.**

- Saboteur: wear the Saboteur hands in midcast for every enfeeble cast during its minute (except Dia, where Leth. Ganth. +3's bonus is bugged). Saboteur's magic accuracy makes a potency set safer than it is without it. On NMs Saboteur is only +25%, so dSTAT and effect+ carry more of the potency there.
- Stymie: magic accuracy is already 100%, so wear a full potency and duration set with no magic accuracy pieces.

## Magic damage

How damaging spells are scaled: elemental nukes, divine nukes and magical blue magic. Magical weapon skills use most of the same multipliers on a different base; see Weapon skills.

### What multiplies with what

bg-wiki, Magic Damage:

```
Damage = D
       × MTDR (area spells that hit more than one target)
       × Staff (old elemental staves only) × Affinity
       × Resist × resistance-rank reduction
       × MB × MBB (magic bursts only)
       × Day & Weather
       × (100 + MAB) / (100 + target MDB)
       × TMDA (the target's magic damage taken)
       × other potency multipliers

D = Magic Damage stat + V + dINT × M
```

- The result is floored after each multiplication. Every term after D starts at 1.0.
- Stats that feed the same term add together. Stats in different terms multiply. So a term that is still at 1.0 gains more from a point than MAB does once MAB is in the hundreds.
- Damage is set when the spell lands, so damage gear goes in the midcast set (standard GearSwap practice; the bg-wiki formula pages don't discuss timing).
- Magic Critical Hit II is a ×1.25 proc on nukes, enspells and magical weapon skills, separate from Magic Critical Hit I, so on average it adds its rate × 25%. Sroda Tathlum and Amin Turban have 10% each (bg-wiki, Magic Critical Hit). wsdist models it the same way (see Formulas wsdist adds).

| Stat on gear | Term | Cap |
|---|---|---|
| Magic Damage, INT | D | INT stops adding at the spell's dINT cap |
| "Magic Atk. Bonus" | MAB | none; the target's divisor can't fall below 0.5 |
| An element's "Magic Atk. Bonus" (for example Dark), Orpheus's Sash, Magian staff affinity | Affinity | none listed |
| Elemental obi, Hachirin-no-Obi | Day & Weather | term at most 1.4 |
| Magic burst damage | MBB | 40% from gear; Magic burst damage II and traits go past it |
| Magic accuracy, elemental magic skill | Resist (the odds of a resist) | — |

### D: Magic Damage and INT

- dINT is your INT minus the target's. Each spell has a V and an M for the dINT bands 0–49, 50–99, 100–199, 200–299 and up. Take V at the band's lower edge and multiply only the dINT above that edge: dINT 134 gives V(100) + 34 × M(100–199). Negative dINT uses smaller M values and can bring D to 0.
- wsdist clamps negative dINT to 0, so it overstates nukes when the target's INT is above yours. bg-wiki gives no M values for negative dINT either (see Where wsdist and bg-wiki disagree).
- INT stops adding damage where M reaches 0: at dINT 100 for tier I nukes, 200 for tier II, 300 for tier III, 400 for tier IV and 500 for tier V. Tier VI has M 1 from 500 to 599 and caps at 600.
- RDM gets the tier V nukes from a job point gift at 100 job points spent (bg-wiki, Red Mage). On them INT keeps adding up to dINT 500, which in practice is never reached.
- "Magic Damage +X" adds X straight to D, before any multiplier (bg-wiki, Magic Damage (Statistic)). It is a different stat from "Magic Atk. Bonus". As a share of the total it counts most on spells with a low base, such as low-tier nukes and helixes.
- One INT is worth M Magic Damage: about 3.75 to 5 on a tier V nuke at dINT 50 to 199.
- With a few hundred Magic Damage from gear and weapon, a tier V nuke's D at dINT 100–199 is roughly 1,600 to 2,100, so +20 Magic Damage adds about 1% (arithmetic from the table below, not stated by bg-wiki).
- bg-wiki doesn't say whether an offhand weapon's Magic Damage counts, for example Maxentius's +232 or Bunzi's Rod's +248 in the sub slot.
- Bunzi's armor gains Attack and Magic Damage with rank, up to +30 each at rank 30. A rank 0 piece has only its base stats. The other ranks are in `docs/rank-augments.md`.
  - Those base stats include Magic Atk. Bonus +30 and Magic Damage +30 on every Bunzi's armor piece, so five rank 0 pieces still carry +150 MAB and +150 Magic Damage. Only the augment's extra Attack and Magic Damage is missing (bg-wiki, Bunzi's Hat, Robe, Gloves, Pants and Sabots).

Tier V values (bg-wiki, Magic Damage). Each cell is V / M for the band starting at that dINT; the last column is the damage cap.

| Spell | 0 | 50 | 100 | 200 | 300 | 400 | 500+ |
|---|---|---|---|---|---|---|---|
| Stone V | 650 / 6 | 950 / 5 | 1200 / 4 | 1600 / 3 | 1900 / 2 | 2100 / 1 | 2200 |
| Water V | 700 / 5.6 | 980 / 4.74 | 1217 / 3.95 | 1612 / 2.99 | 1911 / 1.99 | 2110 / 1 | 2210 |
| Aero V | 750 / 5.2 | 1010 / 4.5 | 1235 / 3.9 | 1625 / 2.98 | 1923 / 1.98 | 2121 / 1 | 2221 |
| Fire V | 800 / 4.8 | 1040 / 4.24 | 1252 / 3.85 | 1637 / 2.97 | 1934 / 1.97 | 2131 / 1 | 2231 |
| Blizzard V | 850 / 4.4 | 1070 / 4 | 1270 / 3.8 | 1650 / 2.96 | 1946 / 1.96 | 2142 / 1 | 2242 |
| Thunder V | 900 / 4 | 1100 / 3.74 | 1287 / 3.75 | 1662 / 2.95 | 1957 / 1.95 | 2152 / 1 | 2252 |

INT is worth the most on Stone V and the least on Thunder V.

- wsdist's dINT 50 values for Aero, Fire, Blizzard and Thunder V are each 100 too high (1110, 1140, 1170, 1200); every other cell matches. It matters only while dINT is 50 to 99 (see Where wsdist and bg-wiki disagree).

### Magic Attack Bonus

```
MAB term = (100 + your MAB) / (100 + target MDB)
```

- All MAB adds together before the ratio: gear, traits, job points and gifts. It raises every kind of magic damage, elemental weapon skills included.
- The divisor can't fall below 0.5, so Magic Defense Down stops helping at −50 MDB.
- Ordinary monsters seem to have no MDB unless they are NMs or have an MDB trait (bg-wiki, Magic Defense Bonus). The MDB trait also cuts magical weapon skill damage, and bg-wiki knows no cap for it.
- Returns shrink. At 400 MAB, +10 more is ×1.02. bg-wiki advises giving up MAB in a slot that can carry another multiplier (affinity, obi, weapon skill damage), most of all against targets with MDB.

MAB before gear:

| Source | MAB |
|---|---|
| Magic Attack Bonus trait, tiers I to VI | +20, +24, +28, +32, +36, +40 |
| RDM trait: tiers I, II and III at levels 20, 40 and 86 | +28 at 99 |
| RDM job point category "Magic Atk. Bonus" | +1 per level, +20 at mastery |
| RDM gifts at 10, 210, 660 and 1360 job points | +4, +6, +8, +10 |
| BLU trait from set blue magic | tiers I to IV (from levels 32, 62, 74 and 87); V and VI need the Job Trait Bonus gifts |
| BLU gifts at 60, 360, 910 and 1710 job points | +5, +8, +10, +13 |

- bg-wiki doesn't say whether each gift value is a step or the running total. A mastered RDM has 28 (trait) + 20 (category) + 10 or 28 (gifts) before gear.
- BLU's Job Trait Bonus gifts, at 100 and 1200 job points spent, each raise the traits from set blue magic one tier (bg-wiki: they seem to add 8 trait points each) and unlock tiers V and VI. From set points alone, traits stop at tier IV. The gifts don't affect Gilfinder, Double Attack or Auto Refresh. BLU's MAB and Magic Burst Bonus tiers therefore depend on its job points as well as its spell set; check the trait list in game. A BLU with any Master Level has both gifts (Job points and merits).
- Two job point categories add damage only while their ability is up: RDM's Chainspell Effect (+2 elemental magic damage per level, during Chainspell) and BLU's Burst Affinity Bonus (+2 blue magic damage per level, during Burst Affinity).

### Elemental affinity and Orpheus's Sash

- Gear that names an element, such as `Dark "Magic Atk. Bonus"+28`, gives elemental affinity, not MAB. Affinity is its own multiplier and only helps spells and weapon skills of that element, for example dark for Sanguine Blade.
- Affinity sources add together inside the term. Pixie Hairpin +1 (dark +28%) and Archon Ring (dark +5%) make 1.33. Magian staves' affinity +1 to +6 gives 1.10 to 1.35.
- With no other affinity worn, a 10% affinity piece is a flat ×1.10 for its element, worth far more than +10 MAB when MAB is already high.
- Orpheus's Sash gives affinity to every element: +15% at 1.93' or closer to the target, falling to +1% at 13' or more (bg-wiki, Orpheus's Sash). bg-wiki gives no values in between, and the item page flags the numbers as unverified.
  - It works on damaging elemental, divine and blue magic, Enspells, elemental weapon skills and skillchain damage.
  - It adds into the same Affinity term as element gear. Over Pixie Hairpin +1 and Archon Ring (1.33), its +0.15 is only ×1.11.

### Day, weather and obis

- The Day & Weather term starts at 1.0. When the bonus applies, a matching day adds 0.10, single weather 0.10, double weather 0.25, and double weather on a matching day 0.35. An opposing day or weather subtracts the same amounts. The term can't go above 1.4.
- Without an obi the bonus is random. Weather says matching weather boosts a spell about 1 time in 3; Days of the Week says about 1 in 5 for the day bonus (the pages disagree).
- An elemental obi or Hachirin-no-Obi makes the bonus apply every time, and the penalty from an opposing day or weather as well. Hachirin covers every element: +10% on the day, +10% in single weather, +20% for single weather and the day, +25% in double weather and +35% for double weather and the day.
- With no matching day or weather, an obi adds nothing. It can cost damage: a fire spell on Firesday in double water weather always takes −15% with Hachirin (bg-wiki, Category:Elemental Obi). Wear one only when the element matches and nothing opposes it.
- A matching day or weather also raises magic accuracy, by an amount bg-wiki doesn't know.
- The day and weather bonus, and so an obi, also applies to elemental weapon skills and to skillchain damage. For skillchain damage, the obi has to be worn on the weapon skill that closes the skillchain (bg-wiki, Weather).

### Orpheus's Sash or an obi

Both are waist pieces, so only one can be worn. Choose per cast (derived from the formula, not stated by bg-wiki):

- With no other affinity gear, Orpheus within 1.93' (×1.15) beats a +10% obi match. The obi wins at +20% or more, or when you stand back (Orpheus is about ×1.01 at 13').
- With Pixie Hairpin +1 and Archon Ring on, Orpheus is worth about ×1.11, the same as a +10% obi match.
- Never wear an obi when the day or weather opposes the element.

### Resists and elemental skill

- A damaging spell lands unresisted (×1.0), or 1/2, 3/4 or 7/8 resisted (×0.5, ×0.25, ×0.125). The odds come from your magic accuracy against the target's magic evasion.
- A monster whose resistance rank in that element is 50% or lower adds a forced 1/2 resist on top.
- A half resist halves the spell, and making that back with MAB would take doubling (100 + MAB). Against targets that resist often, magic accuracy comes before MAB (arithmetic from the formula).
- Elemental magic skill sets elemental spells' accuracy and interruption rate, not their damage; Meteor is the only exception (bg-wiki, Category:Elemental Magic). Elemental skill gear is a magic accuracy stat for nukes. RDM's elemental magic is rated C+, 378 at level 99.

## Magic burst

### Magic burst window

- A spell magic bursts if it lands within 10 seconds of the weapon skill that closes a skillchain whose element matches the spell (bg-wiki, Magic Burst).
- Another weapon skill on the target ends the window, except one with no skillchain property, such as Sanguine Blade.

### Burst damage

A burst adds two separate terms to the damage formula, MB and MBB.

- **MB**: +35% after a two-step skillchain, and 10% more for each further step (+45% after three, +55% after four). No gear changes it.
  - bg-wiki's Magic Damage page gives conflicting two-step values (1.25, 1.3, 1.35 and 1.45 in different places). Magic Burst's +35% is the figure used here.
  - Resist adds a further burst bonus from the target's resistance rank (+60% at a 100% rank, +85% at 115%). The Magic Burst page carries the same table and adds it to the +35% (35% + 85% = 120% at a 115% rank). Magic Damage's formula leaves it out, and no reference backs the table (bg-wiki, Resist and Magic Burst).
  - wsdist uses it, after lowering the rank one step for the skillchain, so a 100% target bursts at 1 + 0.35 + 0.85 = 2.20. That is why its RDM Fire V burst set shows 62,098 damage against 17,930 for the free nuke. It multiplies the whole spell, so it doesn't change which gear is best inside a burst set. About 70% confident the term is real (see Where wsdist and bg-wiki disagree).
- **MBB**, the term gear feeds:

```
MBB = 1 + min(Magic burst damage, 0.40) + bonuses outside the cap
```

- Inside the 40% cap: "Magic burst damage +X" on gear, atma and atmacite, and BLM's Ancient Magic II merits.
- Outside the cap: the Magic Burst Bonus trait, magic burst job points and gifts, and gear that says "Magic burst damage II". bg-wiki knows no cap for II. A piece's II value counts even when its plain magic burst damage is wasted past 40%.
- bg-wiki's Magic Damage page caps MBB at 1.40 before the trait, 1.53 at most. The Magic Burst page's uncapped sources go past that.
- Worth: with MAB in the hundreds, +10% magic burst damage is about ×1.07 while +10 MAB is about ×1.02. Fill magic burst damage to 40% first, then MAB.

| Magic Burst Bonus trait | I | II | III | IV | V |
|---|---|---|---|---|---|
| Magic burst damage, outside the cap | +5% | +7% | +9% | +11% | +13% |

- RDM gets I at 85 and II at 95, so +7% at 99. A RDM with 40% from gear bursts at MBB 1.47.
- BLU gets I to III from set blue magic (Leafstorm, Cimicine Discharge, Reaving Wind, Rail Cannon). IV also needs the 100 job point Job Trait Bonus gift and V the 1200 job point one (bg-wiki, Blue Mage Job Traits).

Magic burst damage (inside the 40% cap) on gear (bg-wiki, Magic Burst, unless noted):

| Piece | Magic burst damage | Notes |
|---|---|---|
| Bunzi's Rod | +10% | |
| Bunzi's Hat, Robe, Gloves, Pants, Sabots | +7, +10, +8, +9, +6% (40% for 5) | RDM, not BLU. Base stats, so rank 0 copies have them (bg-wiki, each item's page; the Magic Burst table lists only the Robe) |
| Mizukage-no-Kubikazari | +10% | |
| Atro. Chapeau +4 | +10% | bg-wiki, Atrophy Armor Set +4 |
| Leth. Fuseau +3 | +15% | also MAB +58 and Magic Damage +33 (bg-wiki, Leth. Fuseau +3) |
| Ea Houppelande | +8% | also Magic burst damage II +8, outside the cap. RDM, not BLU (its item text) |
| Hashishin Basmak +3 | +15% | BLU only |
| Nyame Helm, Mail, Gauntlets, Flanchard, Sollerets | +5, +7, +5, +6, +5% | base stats |
| Maxentius | +4% per skillchain in the chain (+12% by the third) | main hand only (bg-wiki, Maxentius) |
| Jhakri Ring | +2% | its item page; the Magic Burst table leaves it out |
| Jhakri Pigaches +2 | +7% | its item text |

- bg-wiki's Magic Burst table lags current gear (it lists Leth. Fuseau +2, not +3). Check an item's own page.
- The five Bunzi's armor pieces reach the 40% gear cap by themselves (derived from their item pages). With all five on, magic burst damage on any other piece, Bunzi's Rod included, is wasted; the other slots can go to MAB, Magic Damage, magic burst damage II or affinity.
- Magic burst damage II: Nyame gets it only from Path C augments, and Bunzi's Gloves from their augments, up to +5 to +7 per piece at rank 30 (`docs/rank-augments.md`). A Path B Nyame piece and a rank 0 Bunzi's piece have none.
- Ea Houppelande's Magic burst damage II +8 is a base stat, so any copy has it, and it counts even when the 40% cap is already full (its item text).

### Bursting a spell that deals no damage

- A burst on a spell with no direct damage, such as an enfeeble, raises only its magic accuracy, not its potency. Magic Burst puts the bonus at about +100, unverified. Resist says +50 for spells on negative-status resistance ranks, among them Paralyze, Slow, Silence, Bind, Gravity and the blind, sleep and poison effects.
- Magic burst damage gear does nothing for these spells. An enfeeble cast into a burst keeps its enfeebling set.

## Cure potency

Cure spellcasting time is under Casting time. Blue magic heals are under Blue magic.

### Cure potency caps

| Stat | Cap | How it combines |
|---|---|---|
| "Cure potency +X%" (also written `"Cure" potency`) | 50% | adds together |
| "Cure potency II +X%" | 30% | adds on top of Cure potency and isn't held by its 50% cap; the caster side tops out at ×1.8 |
| "Potency of cure effect received" | 30% | the target's gear (or Healer's Roll); multiplies with the caster side, ×2.34 at most |

(bg-wiki, Category:Cure Spell)

- Cure potency past 50% is wasted. Cure potency II is the next stat to add.
- Healing is set when the spell lands, so potency gear goes in the Cure midcast set (standard GearSwap practice; bg-wiki doesn't discuss timing).
- Cure potency received is the target's gear. It only helps cures you cast on yourself, and then only if it is in the Cure midcast set (inferred; bg-wiki doesn't say so outright).
- Category:Cure Spell's gear tables lag current gear (they list Atrophy Tights +1 but no +3 or +4). Check an item's own page.

Cure potency II that RDM or BLU can wear: Janniston Ring +1 6%, Janniston Ring 5%, Naji's Loop 1% (all jobs), and the Kaykaus set for RDM (4 to 10% augmented; the Kaykaus +1 set bonus gives up to +10% with five pieces worn).

Cure potency received that RDM or BLU can wear: Buremte Gloves 13%, Sanus Ensis 10% (also Cure potency 13%), Corybant Pearl 10%, Chuq'aba Belt 5%, Kunaji Ring 5%, Phalaina Locket 4% (also Cure potency 4%), Asklepian Ring 3%, Shedir Manteel 3%.

Bunzi's Rod has "Cure" potency +30%, 30 of the 50% cap on its own (bg-wiki, Bunzi's Rod). It is a main-hand club, and changing the main weapon resets TP. These are base stats. Its augments by rank (DMG, MAB, Accuracy and Magic Accuracy, Enmity −) are in `docs/rank-augments.md`.

Bunzi's Robe (RDM, not BLU) has "Cure" potency +15% as a base stat, so a rank 0 copy has it (its item text). With Bunzi's Rod that is 45 of the 50% cap.

### Cure formula

bg-wiki, Cure Formula:

```
HP healed = floor(floor(floor((Base + JP + Raetic) × Cure potency) × Cure potency received) × Day & Weather)
```

- JP is flat Cure potency from job points and gifts (bg-wiki's example is WHM's Afflatus Solace). Raetic is Raetic Rod +1's flat "Cure" +50.
- Multi-target cures and blue magic heals use the same final step and the same potency caps.

Single-target Cure to Cure VI:

```
Power = floor(MND / 2) + floor(VIT / 4) + healing magic skill      (gear included)
Base  = floor((Power − bracket's power) / bracket's rate) + bracket's HP
```

- One healing magic skill = 2 MND = 4 VIT. Because of the flooring, MND only counts in steps of 2 and VIT in steps of 4.

| Spell | Bracket from power | Rate | HP at bracket start |
|---|---|---|---|
| Cure IV | 70 | 1 | 270 |
| Cure IV | 200 | 2 | 400 |
| Cure IV | 300 | 1.43 | 450 |
| Cure IV | 400 | 2.5 | 520 |
| Cure IV | 700 (hard cap) | — | 640 |
| Cure III | 70 | 2.2 | 130 |
| Cure III | 125 | 1.15 | 155 |
| Cure III | 200 | 2.5 | 220 |
| Cure III | 300 | 5 | 260 |
| Cure III | 700 (hard cap) | — | 340 |

- RDM's healing magic skill is rated C−: 368 at level 99 before merits, job points and gear (bg-wiki, Category:Healing Magic). Healing skill also sets healing magic's interruption rate.
- RDM healing skill before gear at Master Level 25 with 8 Magic Skills merit levels: 368 + 25 + 16 = 409. RDM has no healing skill gifts; bg-wiki's Red Mage table gives 368 at job mastery too.
- With MND/2 and VIT/4 on top, a RDM's Cure IV power falls in the 400–699 bracket. There each point of power adds 0.4 HP to Cure IV and 0.2 HP to Cure III.
- On a Cure IV base near 570 HP, 1% Cure potency adds about 5.7 HP, as much as about 14 healing skill or 28 MND. Potency comes first; skill and MND only fill slots that offer no potency (arithmetic from the table).

Curaga, Cura and the blue magic heals use a different power:

```
Power = 3 × MND + VIT + 3 × floor(healing magic skill / 5)
Base  = floor(Power / 2) / Rate + Const
```

- Here one MND = 3 VIT = 5 healing magic skill, and skill only counts in steps of 5. MND matters far more than for Cure I to IV.

### Cure day and weather

- Cures get +10% on Lightsday, +10% in light weather and +25% in double light weather. They lose 10% on Darksday, 10% in dark weather and 25% in double dark weather.
- The day and weather bonuses add together and cap at +35%. Gear can't raise them past that.
- Neither cure page says whether the cure bonus is random the way the damage bonus is, so bg-wiki doesn't establish that an obi helps cures.

### Cures on undead

- Cast on undead monsters, cures deal damage like a nuke. They then ignore Cure potency gear and use MAB and dMND instead (Cure IV: base 140, multiplier 1.5; bg-wiki, Cure IV).

## Blue magic

Each kind of blue magic lands and scales on different stats, so one blue magic set can't serve them all.

| Kind | Lands with | Amount rises with | Does nothing |
|---|---|---|---|
| Physical | Accuracy, DEX, main-hand weapon accuracy | Attack, the spell's stat modifiers (WSC), fSTR to its cap, an item-level main-hand weapon, Blue Magic skill up to the spell's base damage cap, Chain Affinity and Efflux gear | Magic Attack; held TP outside Chain Affinity, Efflux and Azure Lore; critical hit rate outside Chain Affinity, Efflux and Sneak Attack |
| Added effect of a physical spell | Magic accuracy and Blue Magic skill | — | — |
| Magical | Magic accuracy and Blue Magic skill | Magic Attack, the spell's WSC stat, dINT, Burst Affinity gear, Convergence | — |
| Breath | Magic accuracy and Blue Magic skill | Current HP, "Breath damage" gear, Convergence | Magic Attack |
| Pollen, Healing Breeze, Wild Carrot, Magic Fruit, Exuviation, Plenilune Embrace | — | MND, VIT, Cure potency | Blue Magic skill |
| White Wind | — | Maximum HP, Cure potency | MND, Healing magic skill |
| Restoral | — | Blue Magic skill, MND, VIT, Cure potency | — |
| Occultation, Magic Barrier, Diamondhide, Metallic Body | — | Blue Magic skill | Enhancing duration gear, Stoneskin gear |
| Drains | Magic accuracy and Blue Magic skill | Blue Magic skill | Magic Attack, dINT, Drain potency gear |

- Everything that sets a spell's effect is read when the spell goes off, so it goes in the midcast set. Casting time gear goes in precast; recast gear goes in midcast (see Recast). Breath HP is the exception; see Breath blue magic.
- Several of these spells scale with one secondary stat: WSC stats and dINT for nukes, MND and VIT for the cure-formula heals. bg-wiki's formulas say those stats do add damage or healing to these spells.

### Casting time and recast

- "Blue magic spellcasting time −X%" (Hashishin Mintan −13 to −16%, Mavi Mintan +1 and +2 −6 and −12%, Iris −7%) adds to Fast Cast for blue magic only and goes in the blue magic precast set. It doesn't shorten recast. Details and the 80% cap: see Spell-specific and school casting time and "Does anything break the 80% cap? (disputed)".
- "Blue magic recast −X%" (Hashishin Bazubands −13 to −16%, Mavi Bazubands +1 and +2 −6 and −12%) shortens the recast of all blue magic and stacks with haste and Fast Cast. It belongs in the midcast set, by analogy with Fast Cast's recast part; no page says when it is read. The Community Blue Mage Guide's 40% Fast Cast recast target, and the arithmetic behind it, are under Other recast modifiers.

### Blue Magic skill

| Point | Blue Magic skill before gear and merits |
|---|---|
| Level 49 | 150 |
| Level 99 | 424 |
| Job mastery | 460 (424 + 36 from gifts) |
| Master Level n | 460 + n: 485 at ML25, 500 at ML40, 510 at ML50 |

- The Blue Magic Skill Bonus gifts add +5, +8, +10 and +13 at 150, 500, 1125 and 2000 job points spent, +36 in all (bg-wiki, Blue Mage).
- Magic Skills merits add +2 per merit, up to 8 merits (+16). The 460 figure is 424 + 36, so it leaves merits out (bg-wiki, Merit Points).
- Each Master Level adds 1 to the skill cap (bg-wiki, Master Levels). A BLU at Master Level 25 (Combat skill) has 460 + 25 = 485 without gear or merits. Check the in-game value before adding skill gear for a spell that stops at a skill cap.
- What skill does (bg-wiki, Category:Blue Magic):
  - It is the skill term in magic accuracy for magical spells and for the added effects of blue spells.
  - It sets physical spells' base damage, up to each spell's cap (see Physical blue magic). It doesn't decide whether a physical spell hits.
  - It sets blue magic's spell interruption rate.
  - The page also says it sets the potency of magical spells, but the (outdated) magical damage formula has no skill term.
  - It sets the amount for Occultation, Magic Barrier, Diamondhide, Metallic Body, drains and Restoral.
- It does nothing for the cure-formula heals, White Wind, breath damage or Barrier Tusk.
- bg-wiki's skill gear table on Category:Blue Magic lists only the Magus and Assimilator Jubbahs and Njordr Earring, so it is incomplete. Skill is also on Hashishin Tayt, Mirage Stole +2 (+20), Luhlaza Keffiyeh and Charuqs, Cornflower Cape, Deceiver's Torque (+10), Mavi Scarf (+4) and Hashi. Earring +1 (+11). Every stat on Hashi. Earring +1, its augments included, works only in the right ear (bg-wiki, Hashi. Earring +1).

### Job points and merits

A job point category goes to 20 levels, and level n costs n points, so a category costs 210. BLU has 10 categories, and job mastery takes 2,100 job points, so a mastered BLU has every category at 20 and every gift. Master Levels need job mastery on that job, so a BLU with any Master Level has all of this (bg-wiki, Master Levels and Job Points; the "every category" step is arithmetic).

| Source | At maximum |
|---|---|
| Blue Magic Skill Bonus gifts | Blue Magic skill +36 |
| Job Trait Bonus gifts (100 and 1200 job points spent) | One trait tier each; see Traits from set spells |
| Blue Magic Effect gift (550 job points spent) | Stats that set a blue spell's potency count as 5% higher while casting it |
| Magic Accuracy Bonus category | Magic accuracy +20 (+1 per level) |
| Magic accuracy gifts | +5, +8, +10 and +13 at 125, 450, 1050 and 1900 job points spent; most likely +36 in all, as the skill gifts add up |
| Magic Attack Bonus gifts | +5, +8, +10 and +13 at 60, 360, 910 and 1710 job points spent; whether they add up isn't stated |
| Physical Blue Magic Effect Accuracy category | +20% (+1% per level) to the chance a physical spell's added effect lands |
| Efflux category | Efflux TP bonus +200 (+10 per level) |
| Burst Affinity category | Damage +2 per level, during Burst Affinity only. The Community Blue Mage Guide reads it as +2% (+40%) |
| Azure Lore category | +1 per level; the guide reads it as +1% (+20%) |
| Unbridled Learning Effect and Effect II | Unbridled spell damage +1% and duration +1% per level |
| Blue Magic Point Bonus category | +20 set points |
| Merit, Physical Potency (Group 1) | Blue magic accuracy +2 and attack +4/256 per merit. The Community guide gives only the attack |
| Merit, Magical Accuracy (Group 1) | Magic accuracy +2 per merit for magical blue magic (+10 at 5/5). The Community guide says it also helps physical spells' added effects |
| Merit, Assimilation | +5 set points |
| Merit, Convergence (Group 2) | The ability, then +5 a level; see Convergence, Diffusion and Unbridled Learning |
| Merit, Diffusion (Group 2) | The ability, then +5% duration a level after the first; same section |
| Merit, Enchainment (Group 2) | Chain Affinity TP Bonus +100 a level (bg-wiki, Merit Points and Enchainment); see Chain Affinity, Burst Affinity, Efflux and Azure Lore |

- BLU's merit categories, at 5 levels each:
  - Physical Potency: blue magic accuracy +10 (5 × 2) and attack +20/256, about 7.8% (5 × 4/256).
  - Magical Accuracy: magic accuracy +10 (5 × 2) on magical blue magic.
  - Diffusion: +20% duration, +45% with Luhlaza Charuqs +1 (Convergence, Diffusion and Unbridled Learning).
  - Enchainment: Chain Affinity TP Bonus +500 (5 × 100), +750 with Luhlaza Jubbah +1 (Chain Affinity, Burst Affinity, Efflux and Azure Lore).
  - Group 1 and Group 2 each allow 10 levels, at most 5 a category (bg-wiki, Merit Points), so 5 + 5 fills a group and leaves its other categories at 0. Besides the two above, Group 1 has Chain Affinity Recast, Burst Affinity Recast and Monster Correlation, and Group 2 has Convergence and Assimilation.
  - A Group 2 ability needs a merit level to unlock (bg-wiki, Merit Points), so a BLU with no Convergence merits has no Convergence. With no Assimilation merits the set points are 55 + 20 = 75 (Traits from set spells).

### Physical blue magic

- Whether a physical spell hits depends on the main-hand weapon's accuracy, DEX and Accuracy (bg-wiki, Category:Blue Magic). That main-hand sword skill also counts is an inference; the page names only weapon accuracy. Physical Potency merits add blue magic accuracy: +10 and attack +20/256 at 5 levels (Job points and merits).
- A single-hit physical spell's accuracy caps at 95% (bg-wiki, Sudden Lunge).
- Damage works like a weapon skill (bg-wiki, Calculating Blue Magic Damage, tagged outdated):

```
D       = floor(Blue Magic skill × 0.11) × 2 + 3, capped per spell
per hit = floor(D + fSTR + WSC) × the spell's multiplier × pDIF
WSC     = floor(stat A × A% + stat B × B%)
```

- "Like a weapon skill" covers the formula's terms only. No bg-wiki page read says weapon skill damage, elemental gorgets and belts, Double/Triple Attack procs, physical damage limit or critical hit damage apply to blue magic; the Weapon Skill Damage page names WSC, not WSD, for blue magic. Count them as unverified, and value pieces such as Nyame for their Attack and STR, not their WSD or Double Attack.
- On multi-hit spells, the page says the hits after the first most likely use multiplier 1.00, unconfirmed.
- Skill gives about 2 base damage per 9 skill, only below the spell's D cap. Spells above level 75 have no known D cap; many D caps on the page are blank. The page predates the main-hand weapon term below.
- Attack counts. Since the August 2014 update, attack from gear, food, job abilities and magic raises physical spell damage (bg-wiki, Category:Blue Magic). The page's older "Attack = Blue Magic skill + 8 + STR × 0.5" and the Sabishii guide's "attack doesn't affect physical spells" are out of date.
- The main-hand weapon counts. Since July 2013, physical spell damage rises with a main-hand weapon that shows an item level and has a weapon skill attribute modifier (bg-wiki, Version Update (07/08/2013)). The skill and item level parts both stop at the spell's D cap (bg-wiki, Chain Affinity). Swapping a low item level or caster weapon into the main hand for a physical spell lowers its damage and accuracy, and the swap resets TP.
- fSTR grows with STR minus target VIT: 8 at +28, then +1 per 4 more. It caps at 26 at level 99 for melee physical spells, about +100 STR over the target's VIT, except Smite of Rage and Grand Slam. Ranged physical spells use fSTR2, capped at 52. Once fSTR is capped, STR only helps through the spell's WSC.
- Held TP does nothing for a physical spell except under Chain Affinity, Efflux or Azure Lore. Only then do its "varies with TP" effects (damage, accuracy, critical hit rate, effect duration) apply (bg-wiki, Sabishii guide, Efflux and Azure Lore).
- Spells whose text says "Chance of critical varies with TP" can't land a critical hit unless Sneak Attack or Chain Affinity is up (Calculating Blue Magic Damage, outdated). The newer Efflux page says Efflux also turns on critical hit rate. Critical hit rate gear helps only those casts.
- A physical spell's added effect, such as Sudden Lunge's stun, rolls separately from the hit. Magic accuracy and Blue Magic skill raise its chance (bg-wiki, Sudden Lunge). A spell cast for its effect needs accuracy to hit and magic accuracy to land the effect.
  - Bilgestorm (Unbridled Learning only) adds Defense Down 25%, Attack Down 25% and Accuracy Down 10, each rolled and resisted on its own and lasting 30 to 60 seconds. Its WSC and fTP aren't known (bg-wiki, Bilgestorm).
  - Sub-zero Smash's Paralysis is 10% for 3 minutes. Paralyze and Jubaku: Ichi overwrite it, and it doesn't overwrite them. The hit is one strike, 60% VIT, fTP 2.0 at any TP (bg-wiki, Sub-zero Smash).
  - Paralyzing Triad: three hits at fTP 1.125, and Paralysis at 20% potency for 60 seconds (bg-wiki, Paralyzing Triad).
  - Disseverment: five hits at fTP 1.5 at any TP, with an attack penalty of 10%, and Poison of level ÷ 5 + 3 HP a tick, at most 22, for 3 minutes (bg-wiki, Disseverment).
  - Delta Thrust: three hits at fTP 1.09375 (20% STR, 50% VIT), and Plague, −6 MP and −100 TP a tick, for 40 to 60 seconds (bg-wiki, Delta Thrust).
  - Tourbillion (Unbridled Learning only): one area hit at fTP 4.0 (25% STR, 25% MND), and Defense Down of about 33% for 60 to 120 seconds, longer with TP. Magic accuracy and Blue Magic skill raise its chance. It doesn't stack with other Defense Down effects such as Sweeping Gouge or Tenebral Crush, but does with Dia, Box Step and Geo-Frailty (bg-wiki, Tourbillion).
  - Bloodrake (Unbridled Learning only): three hits that absorb 100% of the damage dealt as HP, except from undead, so its drain rises with its damage (bg-wiki, Bloodrake). Ram Charge and Helldive add only knockback (bg-wiki, Ram Charge and Helldive).
- TP Bonus gear (disputed):
  - The TP Bonus page says TP Bonus gear such as Moonshade Earring does nothing for physical blue magic, even under Chain Affinity or Azure Lore, and that Efflux is the only TP bonus that applies.
  - The Moonshade Earring page says its TP Bonus +250 can work on blue magic when an ability such as Chain Affinity consumes TP.
  - Neither page says it helps an Efflux cast without Chain Affinity, which uses no TP.

### Magical blue magic

- A magical spell lands with magic accuracy and Blue Magic skill.
- Damage, from an outdated page (bg-wiki, Calculating Blue Magic Damage):

```
damage = [(D + ST) × multiplier × Convergence + dSTAT × tier multiplier] × MAB and the other magic damage terms
D  = BLU level + 2, capped
ST = WSC from the spell's stat modifiers, doubled by Burst Affinity
```

- Magic Attack raises it. The page doesn't name the Magic Damage stat; that it adds as it does for other nukes is an assumption.
- Burst Affinity doubles the WSC, so it raises damage even without a magic burst.
- The Blue Magic Effect gift makes the potency stats count 5% higher.
- Each spell's stat modifiers come from its own page (bg-wiki, Weapon Skill Damage and the spell pages):

| Spell | WSC | fTP and dSTAT |
|---|---|---|
| Spectral Floe | 80% INT | 4.0, dINT × 2.0 |
| Searing Tempest | 80% STR | 4.0, dINT × 2.0 |
| Anvil Lightning | 80% DEX | 4.0, dINT × 2.0 |
| Silent Storm | 80% AGI | 4.0, dINT × 2.0 |
| Entomb | 80% VIT | 4.0, dINT × 2.0 |
| Scouring Spate | 80% MND | 4.0, dINT × 2.0 |
| Tenebral Crush | 30% INT, MND and VIT | 4.0, dINT × 2.0 |
| Blinding Fulgor | 30% STR, DEX and AGI | 4.0, dINT × 2.0 |
| Uproot | 40% VIT | 4.0, dINT × 2.0 |
| Polar Roar | 20% STR and INT | 5.0, dINT × 2.0 |
| Rail Cannon | 40% MND | 6.0, dINT × 2.0 |
| Diffusion Ray | 40% MND | 5.0, no dSTAT listed |
| Mind Blast | 30% MND | 2.07 (531/256), dMND × 1.5 |
| Magic Hammer | 30% MND | dMND × 1.0, D cap 35 |
| Subduction | 10% STR and VIT | not recorded here |

- INT adds through dINT to every nuke in the table with a dINT term, on top of each spell's own WSC stat; Mind Blast and Magic Hammer take dMND instead (bg-wiki, Calculating Blue Magic Damage). The level 99 nukes use different WSC stats, so one nuke set can't cover them all.
- Added effects that bear on which set a cast is for: Mind Blast's Paralysis is 20% for 1.5 minutes, Polar Roar adds Bind, and Uproot also removes every debuff from the caster. Uproot and Polar Roar need Unbridled Learning (bg-wiki, Mind Blast, Polar Roar and Uproot).
- Self-Destruct is magical (fire). Its damage is limited by current HP, it drops you to 1 HP, and it leaves 5 minutes of weakness. Nothing else is known to affect it, so it needs no damage set (bg-wiki, Self-Destruct).

### Breath blue magic

- Breath damage is a fraction of HP plus a level term (bg-wiki, Calculating Blue Magic Damage). The spell pages give these, with the level term where they state it:

| Spell | Damage |
|---|---|
| Bad Breath | current HP ÷ 8 + level ÷ 3 |
| Frost Breath | current HP ÷ 3 + level ÷ 0.625 |
| Heat Breath | current HP ÷ 2 |
| Poison Breath | current HP ÷ 10 |
| Hecatomb Wave | current HP ÷ 4 + level ÷ 1.5 |
| Radiant Breath | current HP ÷ 5 |
| Flying Hip Press | current HP ÷ 3 |
| Wind Breath | HP ÷ 4 |
| Thunder Breath | HP ÷ 2 on its own page; 27/40 on the Calculating page |
| Vapor Spray | HP ÷ 2 |
| Magnetite Cloud | HP ÷ 6 times level ÷ 1.875 on its own page; the Calculating page adds the two |

- Magic Attack and the target's Magic Defense Bonus don't apply. A magic burst raises a breath's accuracy but not its damage, and resists still apply.
- A breath lands with magic accuracy and Blue Magic skill.
- "Breath damage dealt +X%" is on Luhlaza Keffiyeh: +18% NQ, +20% +1, +22% +2, +24% +3 and +4. Mirage Keffiyeh (NQ, +1, +2) has an unquantified breath damage bonus (bg-wiki, Luhlaza Attire Set and Mirage Keffiyeh). Convergence also raises breath damage (bg-wiki, Bad Breath, Frost Breath and Heat Breath).
- Current HP, not maximum HP, sets the damage. The Sabishii guide says HP gear adds breath damage only at full HP with it on (bg-wiki, Sabishii guide, Heat Breath). The reason is an inference (about 75% confident): putting on HP gear raises maximum HP but not current HP, so the HP has to be on and filled before the cast, from the idle or engaged set. HP gear in the midcast set then mostly keeps maximum HP from dropping below current HP. Test in game.

### Blue magic healing

- White Wind heals floor(maximum HP ÷ 7) × 2. It uses maximum HP, so HP in the midcast set counts in full. Cure potency gear, Divine Seal, wind weather and obis raise it; Healing magic skill and MND don't (bg-wiki, White Wind).
- Pollen, Healing Breeze, Wild Carrot, Magic Fruit, Exuviation and Plenilune Embrace use the multi-target cure formula, with Power = 3 × MND + VIT + 3 × floor(Healing magic skill ÷ 5) and soft caps per spell (bg-wiki, Cure Formula). The whole formula is under Cure formula.
- One MND is worth 3 VIT or 5 Healing magic skill. Blue Magic skill does nothing for these six spells.
- Cure potency caps at 50%, Cure potency II adds up to 30% on top, and Cure potency received caps at 30%; see Cure potency caps.
- Caps per spell:

| Spell | Soft cap | Hard cap | Day, weather, obis |
|---|---|---|---|
| Magic Fruit | 550 | 610 | No |
| Plenilune Embrace | 650 (100 more than Magic Fruit) | 710 | Yes |
| Wild Carrot, Healing Breeze | 180 | — | — |
| Pollen | 36 | — | — |

- Once MND reaches a spell's soft cap, Cure potency is what still adds healing.
- Restoral heals only the caster. Base 640, soft cap 1040 HP. Unlike the other blue cures it uses Blue Magic skill (2 skill = 1 HP), with MND and VIT, and day, weather and obis affect it. The full formula is marked Information Needed (bg-wiki, Restoral).

### Skill-based and support spells

- Occultation gives floor(Blue Magic skill ÷ 50) blink shadows, for example 12 at 600. They absorb about 75% of the time, and area TP moves remove them. Skill only matters up to the next multiple of 50 (bg-wiki, Occultation).
- Magic Barrier absorbs magic damage equal to total Blue Magic skill, gear included. bg-wiki names no cap. Stoneskin effects and Rampart overwrite it (bg-wiki, Magic Barrier).
- Diamondhide (area) absorbs (Blue Magic skill ÷ 3) × 2, capped at 500 skill. The Calculating page instead gives a cap of 200 (bg-wiki, Diamondhide).
- Metallic Body absorbs Blue Magic skill × 0.375 + 12.5, capped at 500 skill (200). The Calculating page gives level ÷ 3 + skill ÷ 3 capped at 125, and the Diffusion page 127 (bg-wiki, Metallic Body).
- Siegel Sash and other "Stoneskin +" gear don't affect Diamondhide or Metallic Body. Skill past 500 does nothing for either.
- Barrier Tusk cuts damage taken by 15%. It applies after damage taken gear and outside the 50% cap, so at the cap it takes total reduction to 57.5%. "Phalanx +" gear doesn't affect it, and Phalanx overwrites it. bg-wiki gives a flat 15% with no skill term; that skill does nothing for it is inferred from that silence (bg-wiki, Barrier Tusk).
- Drains: Atra. Libations drains (Blue Magic skill × 0.11) × 9, and Drain potency gear doesn't raise it. The older Calculating page gives Blood Drain floor(skill × 0.11) × 3, Digest × 5 and Blood Saber × 3.5, and says Magic Attack and dINT don't change drain amounts (bg-wiki, Atra. Libations).
- Enhancing magic duration gear doesn't lengthen blue magic buffs: Erratic Flutter stays 5 minutes, and the Mighty Guard page says the same, because they are blue magic (bg-wiki, Sabishii guide and Mighty Guard).

### Chain Affinity, Burst Affinity, Efflux and Azure Lore

| Ability | Lasts | Recast | Next spell | Gear |
|---|---|---|---|---|
| Chain Affinity | 30 s or the next blue spell | 2 min | A physical spell can skillchain; its WSC doubles; current TP drives its "varies with TP" effects, then all TP is used | "Chain Affinity +N": N base damage on every hit, not limited by the spell's D cap. Hashishin Kavuk +22/+24/+26/+28 (NQ to +3), Assim. Charuqs +3 and +4 +24, Iris +25. It doesn't raise skillchain damage |
| Burst Affinity | 30 s or the next blue spell | 2 min | A magical spell can magic burst; its WSC doubles, which raises damage even without a burst | "Burst Affinity +N" adds N/100 to the WSC multiplier: Hashi. Basmak +12/+15/+18/+21 (NQ to +3), Assim. Shalwar +12/+14/+16 (+1 to +3) and +4 +16 |
| Efflux | 1 min or the next blue spell | 3 min | A physical spell gets a 1000 TP bonus without using your TP, and its base damage × 1.5. Stacks with Chain Affinity; TP past 3000 is lost | "Efflux" TP bonus: Hashishin Tayt +650/+700/+750/+800 (NQ to +3), Rosmerta's Cape +250 |
| Azure Lore | 30 s | — | Physical spells act as if cast at 3500 TP without using TP; magical spells get a bigger multiplier; spells can skillchain or burst without Chain or Burst Affinity, but without those abilities' damage bonuses | Luhlaza Bazubands (NQ to +3) and augmented Mirage Bazubands +2: +10 s |

- Chain Affinity, Burst Affinity and Efflux gear changes the spell, so it goes in the spell's midcast set. Azure Lore's duration gear has to be on when the ability is used; that is general job ability practice, not stated on its page.
- Vertical Cleave's page says extra TP under Chain Affinity doesn't raise its fTP, an exception to the Chain Affinity rule.
- Rosmerta's Cape carries "Efflux" TP bonus +250 and Monster correlation effects +10 in its base text, so every augmented copy has them (bg-wiki, Rosmerta's Cape).
- With Hashishin Tayt +3, Rosmerta's Cape and the 20-level Efflux category, an Efflux cast has 1000 + 800 + 250 + 200 = 2250 TP bonus (Community Blue Mage Guide).
- Enchainment (BLU Group 2 merit) gives Chain Affinity TP Bonus +100 a level. Luhlaza Jubbah (NQ to +3) and Mirage Jubbah +2 add +50 a level more, +750 in all at 5 (bg-wiki, Enchainment).
  - At 5 levels: 5 × 100 = +500, and 5 × 150 = +750 with Luhlaza Jubbah +1 on.
  - When the Jubbah is read isn't stated, so wear it for Chain Affinity and in the spell's midcast (gear-notes.md, Luhlaza Jubbah +1).
  - The Efflux page says, marked for verification, that Efflux's TP bonus doesn't stack with Enchainment; the higher applies.
- Hashi. Basmak +3 also has Magic burst damage +15 (bg-wiki, Hashishin Attire Set).

### Convergence, Diffusion and Unbridled Learning

- Convergence (merit ability, 10-minute recast) makes the next magical spell single-target. Per merit it adds +5% magic damage and +5 magic accuracy, up to +25% and +25. Luhlaza Keffiyeh (NQ to +3) and Mirage Keffiyeh +2 add +2% more per merit, up to +35% damage. The damage bonus is its own multiplier (bg-wiki, Convergence). The Bad Breath, Frost Breath and Heat Breath pages say it raises breath damage too.
  - The Blue Mage and Merit Points pages give the merit as +5 Magic Attack Bonus and +5 magic accuracy per merit instead of +5% damage. The Calculating page gives a multiplier of 1.05, 1.10 and 1.15 for merits 1 to 3.
  - Luhlaza Keffiyeh's Convergence bonus only counts on a Convergence cast. Its breath damage and Blue Magic skill count on any cast.
- Diffusion (merit ability, 10-minute recast) spreads the next self-target support spell to party members within 9 yalms at full potency. Each merit after the first adds 5% duration (+20% at 5/5). Luhlaza Charuqs (NQ to +3, and augmented Mirage Charuqs +2) add 5% per merit (+25%), for +45% in all (bg-wiki, Diffusion). The Diffusion page's own wording ("+5% per merit, up to +45%") doesn't add up on its own; Mighty Guard's 3:36 becoming 5:13 (× 1.45) fits this split.
  - When to wear the Charuqs isn't settled: the Sabishii guide says when Diffusion is used, and the Diffusion and Charuqs pages give no timing. Wearing them for the Diffusion job ability and in the diffused spell's midcast covers both readings.
  - With 5 Diffusion levels and Luhlaza Charuqs +1: 20 + 25 = +45%. Mighty Guard then lasts the 5:13 below (216 s × 1.45 = 313 s).
- Unbridled Learning lasts 60 seconds, has a 5-minute recast and ends after one Unbridled spell. Unbridled Wisdom lasts 60 seconds, has a 1-hour recast and allows any number of them. No gear enhances either; Unbridled spells use the normal physical, magical or buff gear (bg-wiki, Unbridled Learning and Unbridled Wisdom).
- Mighty Guard needs Unbridled Learning or Unbridled Wisdom. It lasts 3 minutes, 3:36 with the 20-level Unbridled Learning Effect II category, and 5:13 with 5/5 Diffusion merits and Luhlaza Charuqs. It gives Defense +25% (the Diffusion page's table says +15%), Magic Defense Bonus +15, Regen 30 HP a tick and magic haste +15% (marked unverified). Its only duration gear is the Charuqs under Diffusion (bg-wiki, Mighty Guard).

### BLU set bonuses

- Hashishin: 2 or more pieces from Mavi +2 or any Hashishin tier, mixed freely, occasionally triple a blue spell's WSC, or quadruple it under Chain Affinity or Burst Affinity. The chance is 1% per piece: 2% with two pieces, up to 5% with five (bg-wiki, Hashishin Attire Set). At 5% at most, it is a small bonus, not worth a clearly worse piece.
- Assimilator +2, +3 and +4 pieces give the same set bonus as Atrophy: Accuracy, Ranged Accuracy and Magic Accuracy +15, +30, +45 and +60 for 2, 3, 4 and 5 pieces. NQ and +1 pieces have no set bonus, and one piece alone gives nothing. Regal Earring counts toward it; see Artifact set bonus (bg-wiki, Assimilator's Attire Set).

### Traits from set spells

- Set points: 55 at level 91 to 99, plus 1 per Assimilation merit (up to +5) and 1 per Blue Magic Point Bonus level (up to +20), so 80 at most. At most 20 spells can be set (bg-wiki, Blue Mage).
  - With no Assimilation merits and the Blue Magic Point Bonus category at 20 (Job points and merits): 55 + 0 + 20 = 75 set points.
- Each set spell gives 4, 6 or 8 trait points toward its trait, and every tier takes 8 trait points (bg-wiki, Blue Mage Job Traits). The page's "TierCosts" and "Min. Pts" figures are the cheapest set-point cost of a tier, not trait points.
- From spells alone, a trait reaches tier IV at most.
- The Job Trait Bonus gifts, at 100 and 1200 job points spent, each add 8 trait points to every set trait and unlock tiers V and VI. bg-wiki hedges the 8-point mechanism ("seems to"). Since a hotfix they don't complete a half-set trait: a trait needs its first 8 points from spells. They don't work for Auto Refresh, Double Attack, Gilfinder, Rapid Shot or Zanshin; Killer and Resist traits are unverified.
- A trait from set spells doesn't add to the same trait from the support job; the higher tier applies.
- Traits change with the spell set and with job points spent. Read the in-game trait list before counting a trait in a set's totals.

| Trait | Spells (trait points) | Tiers | From the spells listed |
|---|---|---|---|
| Fast Cast | Erratic Flutter (8); Bad Breath, Sub-zero Smash, Auroral Drape, Wind Breath (4 each) | 0 to IV: 5, 10, 15, 20, 25% at 8, 16, 24, 32, 40 points | All five: 24 points, 15%; 20% with one gift, 25% with both. Erratic Flutter alone: 5%, 10% or 15% with no, one or both gifts |
| Dual Wield | Animating Wail, Blazing Bound, Quad. Continuum, Delta Thrust, Mortal Ray, Barbed Crescent (4 each); Molting Plumage (8) | I to VI: 10, 15, 25, 30, 35% and 37% (Blue Mage Job Traits) or 40% (Dual Wield page) | All seven (26 set points; the page's summary table says 24 for tier IV): 32 points, tier IV (30%); VI with both gifts. Cheapest tier I: Delta Thrust and Barbed Crescent, 4 set points |
| Store TP | Sickle Slash, Tail Slap, Fantod, Sudden Lunge (4 each); Diffusion Ray (8) | I to V: +10, 15, 20, 25, 30 | All five: 24 points, tier III (+20); IV and V with the gifts. The Store TP page says IV needs the 1200 gift; Blue Mage Job Traits says the 100 gift |
| Double Attack, Triple Attack | Acrid Stream, Demoralizing Roar, Empty Thrash, Heavy Strike (4 each); Thrashing Assault (8) | Double Attack 7% at 8 points; Triple Attack 5% at 16, replacing Double Attack | Gifts don't raise Double Attack. Whether they count toward Triple Attack isn't stated |
| Accuracy Bonus | Dimensional Death, Frenetic Rip, Disseverment, Vanity Dive (4 each); Nature's Meditation, Anvil Lightning (8 each) | I to VI: +10, 22, 35, 48, 60, 72 (the Accuracy Bonus page gives VI as +73). Accuracy and ranged accuracy | V and VI need gifts |
| Attack Bonus | Battle Dance, Uppercut, Death Scissors, Spinal Cleave, Temporal Shift, Thermal Pulse (4 each); Embalming Earth, Searing Tempest (8 each) | I to VI: flat Attack +10, 22, 35, 48, 60, 72 | V and VI need gifts (the page's summary table lists V without them) |
| Critical Attack Bonus | Sinker Drill (8) | Critical hit damage +5%; +8% and +11% with the gifts | — |
| Magic Attack Bonus | several (see Blue Mage Job Traits) | I to VI: +20, 24, 28, 32, 36, 40 | I to IV from spells; V and VI need gifts |
| Magic Burst Bonus | Leafstorm, Cimicine Discharge, Reaving Wind (6 each); Rail Cannon (8) | I to V: +5, 7, 9, 11, 13% | All four: tier III (+9%); IV and V with the gifts. Outside the 40% gear magic burst damage cap (bg-wiki, Magic Burst) |
| Magic Accuracy Bonus | Tenebral Crush (8) | +10; +22 with the 100 gift; tier III unknown | — |

## Treasure Hunter

- A monster's Treasure Hunter level comes from the TH you have when you act on it. Melee rounds, ranged attacks, weapon skills, job abilities and spells all count, misses included: anything that puts you on its enmity list.
- On a main job other than Thief, TH from gear and traits caps at 4.
- When TH gear goes on, and which actions count a monster as tagged, is the GearSwap framework's choice, not the game's. GearSwap gets no event before an auto-attack, so a framework can only cover the first melee round by wearing TH gear while engaged. Selindrile's framework puts `sets.TreasureHunter` on over a weapon skill or a job ability against a monster it hasn't tagged while its treasure mode is on ([frameworks/sel.md](frameworks/sel.md#sets-laid-over-the-chosen-set)).

## Dancer abilities from a DNC subjob

- A Step lands on melee hit rate, capped at 95%, with its own Accuracy +10. Step accuracy gear, the Step accuracy merits and Presto are Dancer's (bg-wiki, Step).
- Desperate Flourish and Violent Flourish have to hit. Violent Flourish's stun is then resisted on the user's magic accuracy (bg-wiki, Violent Flourish).
- HP cured by a Waltz = (1 + Waltz potency + Waltz potency received) × (M × (user's CHR + target's VIT) + B + 2 × Waltz job point tiers), floored at each step. M is the tier's slope and B its base. M is halved when Dancer is the subjob. Waltz potency from gear caps at 50%, and Waltz potency received at 30% (bg-wiki, Waltz).
- Of the gear these notes cover that RDM can wear, only Gleti's Knife names a dancer ability: Waltz potency +10%. Jig and Samba durations change only with Dancer gear.
- Thief can also wear Gleti's Cuirass, which has Waltz potency +10% too.

## Gear and GearSwap

- Leth. Earring +1 and Hashi. Earring +1: their item text says their bonuses only work in the right ear.
- `//gs export` shows a path augment ("Path: A") but not its rank.
- Odyssey path augments rise with rank, up to rank 30. A copy that exports with no augments is rank 0; for any other copy the rank has to come from the player, since the export doesn't show it. `docs/rank-augments.md` lists every rank's values, generated from bg-wiki's rank tables. A character's ranks are in `data/<Character>/<Character>_rank_augments.md`.
- This repo's GearSwap makes `//gs export all` write one table for each bag and then one for each storage slip, `slip1` to `slip33`, holding the items a porter moogle keeps on it (`export.lua` at the root). A piece on a slip is owned, but GearSwap can't equip it: it has to come back from a porter moogle into the inventory or a wardrobe first. A slip records no augments.
- When you own more than one copy of an item, name each copy by its augments, exactly as `//gs export` printed them.
- Which set a spell or action wears, which sets are laid over it, and whether a set's weapons go on at all (the weapon lock) are the GearSwap framework's rules, not the game's. Selindrile's are in [frameworks/sel.md](frameworks/sel.md). A weapon swap resets TP whatever the framework.
- This repo is the GearSwap addon itself, so changes to GearSwap's own `//gs` commands go in `gearswap.lua` at the root, not in a framework's files or a gear file. Its `addon command` handler maps `e`, `x`, `t` and `n` to `equip`, `export`, `test` and `naked`. `naked` equips the naked set as `equip naked` does, then disables the user file until the next `naked`.
- Windower's `in_combat` flag is on whenever battle music plays, so it is on while you fight a monster without engaging it, for example while nuking it. A framework rule that follows it follows the music, not whether your weapons are drawn.
- Two identical copies with no augments, such as two Stikini Rings, are safest swapped as a pair. A set may wear one copy, but a set wearing both should not directly follow a set wearing one: GearSwap's copy matching (`unpack_equip_list` in equip_processing.lua) can then try to move the copy already worn in the other slot. Pinning each to its bag, for example `{ bag = "wardrobe" }`, also fixes it.
- Moving items between bags: the client sends outgoing packet 0x029 (count, from bag, to bag, from slot, and slot 0x52, which lets the server pick the first empty one). One of the two bags must be the inventory, so a move between two other bags takes two hops and a free inventory slot. Wardrobes hold only weapons and armor, and equipped or bazaar items don't move. Safe, Safe 2, Storage and Locker are reachable only in the Mog House, or, all but Storage, at a Nomad or Pilgrim Moogle within six yalms once you have talked to it. Windower's organizer addon talks to the moogle for you and hides the menu that opens. `gs stash` and `gs pull` (`wardrobe.lua` at the root) move gear the same way.
- Windower's texts library sets `_meta.Text`, the metatable every text box shares, as it loads. A second copy of the library loaded into GearSwap's Lua state with GearSwap's `_meta` takes over every existing box, and the boxes then fail in that copy's `texts.destroy` (`texts.lua:609`, attempt to index a nil value) because it has no record of them. `gs stash` and `gs pull` load their own copy to read job files, so they give it a `_meta` of its own.
- The game refuses an equip it won't carry out, such as a weapon in sub without Dual Wield, and never confirms it. **(player, 2026-10-02)** It also prints an error about Dual Wield in chat. GearSwap treats each equip it sends as worn until the server confirms it. Before this repo's fix, a refused equip counted as worn forever, so GearSwap never sent that item again until a different item went to that slot. On BLU/WAR the sword stayed off until the weapon mode was cycled. An equipset, which GearSwap sends when three or more slots change, never had this problem, because the server's reply lists everything worn. GearSwap here now drops a slot's request after 3 seconds without confirmation (`equip_confirm_window` in `statics.lua`), so the next build sends the item again.
- Dual Wield from set blue magic shows up as trait 18 in `windower.ffxi.get_abilities().job_traits` once AzureSets has set the spells, which takes about 0.65 seconds per spell. A framework that reads the trait to pick dual-wield sets sees it only after that. Selindrile's reads it into `can_dual_wield`, which decides whether its `DW` sets apply ([frameworks/sel.md](frameworks/sel.md#how-sel-picks-a-set)).

## Community Red Mage Guide sets

bg-wiki's Community Red Mage Guide groups RDM spells into sets by the stat that decides each one. These are community recommendations, not mechanics. Where a mechanics section of this doc disagrees, the mechanics section wins. Lines with no other source are the guide's.

### What the guide assumes

- Its sets and expected values assume 2100 job points, full merits and Master Level 30. A RDM short of that needs more skill and magic accuracy from gear than the sets carry.
- It marks path items with path and rank (Contemplator +1 A R15, Dls. Torque +2 R25) and counts those augments. A lower-rank copy has smaller augments. rank-augments.md lists every rank.
- The only Odyssey gear in its sets is Nyame Flanchard (the Aquaveil heavy-fire swap), Nyame Sollerets (a non-Stoneskin slot in the Stoneskin set) and Sakpata's Sword (the Stoneskin set's main hand, an HP-dip and recast slot). None is there for a path augment. No Nyame path carries a player DT augment; Path D's is Pet: Damage taken (bg-wiki, Nyame Flanchard and Nyame Sollerets). So a Path B copy gives the same DT as any copy, whatever its rank.
- No guide set uses Bunzi's or Gleti's gear. The guide names Bunzi's Rod and Gleti's Knife only as Odyssey weapons to get, with no rank.
- Merits it recommends. These bonuses exist only if the merits are bought:
  - Group 1: 5/5 Ice and 5/5 Wind magic accuracy, +3 a level (+15 for each element; the Merit Points page says +2 a level, see Job sources). Ice covers Distract, Paralyze and Bind; Wind covers Gravity and Silence.
  - Group 2: 5/5 Magic Accuracy (+5 a level, +3 more a level with the relic head) and 5/5 Immunobreak Chance (+3% a level, +1% more a level with the relic boots).
  - It calls the En-spell merit not worth buying. The talk page disagrees for Enspell-based content.
- Gaps. Its only sets are the seven enfeebling sets, Aquaveil, Stoneskin, two enhancing duration sets, TP, Enspell-only, Seraph Blade and Sanguine Blade. It has no fast cast, Cure, idle, DT, nuking, Refresh, Regen, Phalanx, Gain, Temper or physical weapon skill set. Its Lethargy piece notes are blank.

### Enfeebling sets

Every guide enfeebling set wears Contemplator +1 (A R15) with Enki Strap, Viti. Chapeau +4, Dls. Torque +2, Snotra Earring, Viti. Boots +4, and a Sucellos's Cape with Fast Cast +10% and PDT −10%. The cape's MND or INT and magic accuracy augments change by set.

| Guide set | Spells | Priority | Pieces beyond the common ones |
|---|---|---|---|
| Skill Potency Hybrid | Frazzle III, Distract III, Poison, Poison II | Enfeebling skill over magic accuracy, since skill also adds magic accuracy. Effect+ over skill for Poison (capped at 500 skill) and, "for now", Poison II | Regal Gem, Vor Earring, Atrophy Tabard +4, Kaykaus Cuffs +1 (A R15), two Stikini Ring +1, MND cape, Obstin. Sash, Psycloth Lappas (B R15) |
| MAcc & Duration | Sleep, Sleep II, Bind, Break, Silence | Magic accuracy and duration. Potency does nothing | Ullr, Regal Earring, Lethargy Sayon +3, Regal Cuffs, Kishar Ring, Stikini Ring +1, INT cape, Luminary Sash, Psycloth Lappas |
| MAcc + Potency Hybrid | Gravity, Gravity II | Magic accuracy and effect+ (no dSTAT in potency). The MAcc & Duration set when landing matters more | Regal Gem, Vor Earring, Lethargy Sayon +3, Kaykaus Cuffs +1, Kishar Ring, Stikini Ring +1, MND cape (conflicts with dSTAT: Gravity is black magic, so INT sets its dSTAT macc), Obstin. Sash, Psycloth Lappas |
| Pure MAcc | Frazzle II, Distract II, Dispel | Magic accuracy only | As MAcc & Duration, but Atrophy Tabard +4, Kaykaus Cuffs +1 and two Stikini Ring +1 |
| Full MND + Potency | Paralyze, Addle, Slow (all tiers) | MND to the spell's dMND cap, then effect+ | Regal Gem, Regal Earring, Lethargy Sayon +3, Kaykaus Cuffs +1, Metamor. Ring +1 (A R15), Stikini Ring +1, MND cape, Obstin. Sash, Chironic Hose (MND +10 to 15, MAcc +30 to 40) |
| Full INT + Potency | Blind, Blind II | INT to the dINT cap, then effect+ | Marin Staff +1 (A R15) with Enki Strap, Regal Gem, Regal Earring, Lethargy Sayon +3, Regal Cuffs, Metamor. Ring +1, Kishar Ring, INT cape, Acuity Belt +1 (A R15), Psycloth Lappas (A R15) |
| Full Duration & TH | Inundation | Duration and Treasure Hunter | Per. Lucky Egg, Volte Cap, Jupon, Hose and Boots, Regal Cuffs, Kishar Ring, Obstin. Sash |

Targets (the guide's figures, checked on bg-wiki; formulas under Enfeebling magic):

- Frazzle III caps at 625 enfeebling skill and Distract III at 610, each with +50 dMND (bg-wiki, Frazzle III and Distract III). At Master Level 25 with 8/8 enfeebling merits, 501 skill (Enfeebling skill), that is +124 skill from gear for Frazzle III (625 − 501) and +109 for Distract III (610 − 501).
- dMND stops adding potency at ±40 for Paralyze II, ±75 for Slow II and ±100 for Addle II. The guide has no current formula for Blind II; its old one capped dINT at ±120 with no skill term, and its Blind II values are its own estimates. bg-wiki's Blind II page gives 19 at −80 dINT to 94 at +120 (see Potency by spell).
- Frazzle II caps at 350 skill, which RDM passes without gear, so its set is all magic accuracy. Cast it first, then Frazzle III in the Skill Potency set: if Frazzle III misses, Frazzle II stays on. Distract II and III work the same way.
- Dispel: Dls. Torque +1 or +2 ("Dispel"+1) removes one more effect (bg-wiki, Dls. Torque +1).
- Inundation: +4 Treasure Hunter in total is enough, the non-Thief cap (see Treasure Hunter).
- The MAcc & Duration set's duration: Regal Cuffs +20%, Kishar Ring +10% and Snotra Earring +10% native, and Dls. Torque +2 R25 +25% augmented, a separate multiplier. Its one Lethargy piece (Sayon +3, there for magic accuracy) gives no set bonus. The Lethargy hands under Saboteur make two, +10% with Composure up.

Notes:

- Saboteur hands. The guide puts Lethargy Gantherots +1 (Saboteur +12%) in hands for any enfeeble cast under Saboteur. That is out of date: Leth. Ganth. +3 gives +14%. The hands only count in the midcast set, and the +3's bonus is bugged on Dia (bg-wiki, Leth. Ganth. +3 and Category:Enfeebling Magic).
- Murgleis. The guide leaves Murgleis III out. Its 108 magic accuracy and INT and MND +12 come within a fraction of a percent of Contemplator +1's 80 magic accuracy, enfeebling skill +20, MND +32 and INT +22, so it isn't worth making for magic accuracy sets alone.
- **(disputed)** The guide says the magic accuracy spells have no dSTAT, or one too small to matter. The talk page calls this wrong: dSTAT always adds magic accuracy, so MND or INT still helps those spells land (bg-wiki, Talk:Community Red Mage Guide).

### Enhancing sets

- The guide's split: Haste, Flurry, Refresh, Regen, Protect and Shell are duration spells, and skill does nothing for them. The rest are skill spells that cap between 350 and 500 skill, except Temper and the Enspells, which have no cap. bg-wiki puts Aquaveil's last tier at 501.
- In buff sets it ranks full duration, 30 to 50% PDT and little HP dip from swaps above Conserve MP. Conserve MP is worth a look only for Protect V, Shell V and Reraise.
- Spikes: INT and magic attack bonus, not skill. Viti. Tights (any tier) add "Spikes" spell damage +30 (bg-wiki, Vitiation Armor Set).

**Duration sets** (Barspells, Blink, Haste, Haste II, Flurry, Flurry II). A % with no mark is native; augmented duration multiplies separately (see Enhancing duration).

| Slot | Self | Others |
|---|---|---|
| Main, sub | Colada (+4% augmented), Ammurapi Shield | same |
| Head | Telchine Cap (+10% augmented) | Leth. Chappel +3 |
| Neck | Dls. Torque +2 R25 (+25% augmented) | same |
| Ear | Leth. Earring +2 | same |
| Body | Viti. Tabard +4 (+15%) | Lethargy Sayon +3 |
| Hands | Atro. Gloves +4 (+20%) | same |
| Back | Sucellos's Cape (+20%, native even unaugmented) | same |
| Waist | Embla Sash | same |
| Legs | Telchine Braconi (+10% augmented) | Leth. Fuseau +3 |
| Feet | Leth. Houseaux +3 (+40%, enhancing skill +35) | same |

- The others set wears four Lethargy pieces, for +35% from the set bonus on spells cast on others. Self casts get no set bonus, so the self set spends those three slots on duration instead.
- Ghostfyre or Sucellos's. The guide's text says a fully augmented Ghostfyre Cape gives more duration than Sucellos's, because native and augmented duration multiply: two native +25% pieces give +50%, a native and an augmented +25% give +56%. Its self set still wears Sucellos's. A Ghostfyre at +20% augmented beats Sucellos's +20% native by 0.2 × (native − augmented) of the duration before gear, counting the rest of the set (bg-wiki, Ghostfyre Cape). The rest of the self set has 104% native (Tabard 15, Gloves 20, Houseaux 40, Ammurapi Shield 10, Embla Sash 10, Leth. Earring +2 9) against 49% augmented, so Ghostfyre would give 0.2 × 0.55 = 0.11 on a 2.24 × 1.49 base, about 3% more duration. That is arithmetic from the formula, using the native duration table under Enhancing duration. Sucellos's stays the enfeebling cape.
- Barspells sit in the duration sets, but the guide's Barspell note says skill gear is needed to reach 500: +44 before Master Levels (456 skill), +14 at ML30 (486). At 480 (player, ML24) that is +20, one less for each Master Level gained.
  - At Master Level 25 the skill is 481 (Enhancing skill), so it is +19.
- Under Composure, self Barspells (8 minutes base) reach the 30-minute cap at +25% duration (480 s × 3 × 1.25 = 1800 s), or at ×1.13 with 5 duration merit levels and 20/20 job points (600 ÷ 530 s, from 480 + 5 × 6 + 20; see Composure and the Lethargy set). Duration past that does nothing, so those slots can go to skill (bg-wiki, Composure).

**Aquaveil SIRD set.**

- Full spell interruption rate down plus every Aquaveil+ piece. No duration gear: 10 minutes base already reaches 30 under Composure. No Conserve MP: it saves 6 MP at most.
- Pieces: Grioavolr (SIRD +10% augment) with Magic Strap, Staunch Tathlum +1, Amalric Coif +1 (Aquaveil +2), Dls. Torque +2, Halasz Earring, Magnetic Earring, Ros. Jaseran +1, Regal Cuffs (Aquaveil +2), Freke Ring, Defending Ring, Sucellos's Cape (PDT −10%), Emphatikos Rope (Aquaveil +1), Shedir Seraweels (Aquaveil +1) and Amalric Nails +1.
- It has 28% PDT. Under heavy fire, Loricate Torque +1 and Nyame Flanchard take it to 42% for one block less. The lost block is Shedir Seraweels, which the Flanchard replaces in legs (inferred from the slots). With 5/5 SIRD merits, Gelatinous Ring +1 in place of Freke Ring gives 49% PDT and more HP.
- **(disputed)** Blocks. The guide counts 2 from skill, capped at 355, for 8 in all. bg-wiki's Aquaveil page gives 1 block at 300 skill or less, 2 at 301 or more and 3 at 501 or more, so the same gear at 501 skill blocks 9. From 480 (player), that takes +21 enhancing skill from gear.
  - From 481 at Master Level 25 (Enhancing skill), it takes +20.

**Stoneskin.** Only the Stoneskin+ pieces are mandatory; the other slots limit HP dip and recast. A RDM 99 already reaches the 350 base cap without gear (456 or more skill and MND 28 or more), so enhancing skill and MND gear add nothing (bg-wiki, Stoneskin; see Stoneskin).

### Melee and weapon skill sets

- TP: Crocea Mors (C) with Daybreak; Malignance head, body, legs and feet; Aya. Manopolas +2; Anu Torque; Sherida and Dedition earrings; Hetairoi Ring and Chirich Ring +1; Orpheus's Sash; Sucellos's Cape DEX+20, Acc+30/Atk+20, Dual Wield +10.
- Enspell damage only: Aern Dagger with Qutrub Knife, Ullr, Dls. Torque +2, Telos Earring and two Chirich Ring +1, keeping the TP set's cape and Orpheus's Sash. It is worn while meleeing.
- Orpheus's Sash (elemental affinity +15% at 1.93' or closer, +1% at 13' or more) applies to Enspells, elemental weapon skills and skillchain damage, so it pays only at melee range; see Elemental affinity and Orpheus's Sash.
- Seraph Blade and Sanguine Blade: Amalric +1 body, legs and feet; Jhakri Cuffs +2; Freke Ring; Orpheus's Sash; Sucellos's Cape MND+30, MAcc/MDmg+20, WSD+10%. Sanguine Blade adds Pixie Hairpin +1 and Archon Ring. The talk page dates both sets to July 2020, so they predate current gear.
- Elemental "Magic Atk. Bonus", such as Pixie Hairpin +1's Dark +28 or Archon Ring's Dark +5, is an affinity, not MAB, so it belongs only in sets for that element (bg-wiki, Pixie Hairpin +1 and Archon Ring; see Elemental affinity and Orpheus's Sash).

### Single pieces

The guide's notes on its job gear (stats from bg-wiki, Atro. Chapeau +4, Atro. Gloves +4 and Vitiation Armor Set):

- Atro. Chapeau +4 (Fast Cast +16%, magic burst damage +10): the strongest fast cast piece.
- Atro. Gloves +4 (enhancing duration +20%, WSD +9%): the AF piece to upgrade first.
- Atrophy Tabard +4: Refresh potency, and enfeebles that only need magic accuracy.
- Atro. Tights +4: enhancing skill.
- Atro. Boots +4: shield tanking only.
- Viti. Tabard +4 (enhancing skill +24, duration +15%, Fast Cast +15%): both skill and duration sets.
- Viti. Gloves +4 ("Gain" effects +30): Gain spells.
- Viti. Boots +4 (enfeebling skill +17, effect +10): every enfeebling set.

## Simulated sets (bg-wiki All Jobs Gear Sets)

bg-wiki's All Jobs Gear Sets pages give a computed damage set for the main weapon skills of each job, plus a few nuke, Enspell and TP sets (list under "Sets on each page"). A program picked every piece. These are simulation results, not mechanics. Where a mechanics section of this doc disagrees, the mechanics section wins. Lines with no other source are from the main page (bg-wiki, All Jobs Gear Sets).

### How the sets were made

- Kastra (Asura) built them with wsdist, an open-source Python damage simulator (IzaKastra/wsdist_beta; see "wsdist (Kastra's damage simulator)"). The player calls its quality unknown.
- Each set is scored by one number: the average damage of the weapon skill or spell. TP sets are scored by seconds per weapon skill, under a damage taken limit of −50% or −25%.
- The search starts from a random set, tries every one- and two-piece swap in random order, keeps any swap that raises the number, and stops when a full pass finds nothing better (IzaKastra/wsdist_beta, wsdist.py). That's a local search, so it can stop short of the best set.
- The wsdist code cited in these sections (the search here, the enemy preset, TP before TP Bonus, Orpheus's Sash at a flat +15%) is the current code, commit d12ac59 of 2026-07-12. That postdates the sets (2026-04-28 and 2026-05-03), and an older gui_wsdist.py printed them (IzaKastra/bg_job_guides, README), so the code that made them may differ.
- The page's disclaimer: the code must name one "best" set even when it wins by 0.1%. In play, a set with more defense, or one that takes weapon skill damage (WSD) over PDL for fights where buffs or debuffs may drop, can be the better choice. The code can also list the next-best piece in each slot.
- IzaKastra/bg_job_guides keeps the wiki markup of every page as a backup, formatted by the simulator (IzaKastra/bg_job_guides).
- Live pages against that backup (checked 2026-10-02; the backup's last commit is 2026-05-03):
  - Red Mage: same sets, last updated 2026-05-03. The live page only adds a guide tag and a category.
  - Blue Mage: same sets, last updated 2026-04-28. The live page adds a paragraph on trait points (2026-05-19, below).
  - Main page: the backup predates edits of 2025-07-10 and 2026-04-19. Live, the WHM buffs are Haste, Shell V and Dia II (backup: Dia II only), the untested Nyame is "Paths A and C" (backup: Path A), Hoxne Ampulla is also untested, and a new list gives the augment levels used. This section follows the live page.

### Test enemy

- 1350 Evasion, 1500 Defense, 340 VIT, 340 AGI, 280 INT and 280 MND: about a level 140 Apex monster.
- The page gives no magic evasion or magic defense. The simulator's "BG Wiki sets" enemy preset has the same six numbers and sets both to 0 (IzaKastra/wsdist_beta, enemies.py). If the pages used it, the nuke and magic weapon skill sets assume every spell lands unresisted, and they undervalue magic accuracy for a real target (inference).

### Buffs

Mid-buff sets are for fights where you are neither attack capped nor far below the cap; PDL does nothing there. High-buff sets are for fights near the attack cap, where some PDL pays.

| Buff | Mid buff | High buff |
|---|---|---|
| Food | Grape Daifuku | Grape Daifuku |
| WHM | Haste, Shell V, Dia II with Light Shot | same |
| BRD, songs +7 | Honor March, Victory March, Valor Minuet V and IV | same, with Marcato on Honor March |
| COR, rolls +7, job bonus on | Chaos Roll 10 (Crooked Cards), Samurai Roll 9 | same |
| GEO, bubbles +10 | none | Indi-Fury, Geo-Frailty (Blaze of Glory, 20% potency) |

A job page can override these.

### Red Mage page assumptions

All from (bg-wiki, All Jobs Gear Sets/Red Mage):

- Master Level 30.
- Melee sets: RDM/NIN with Grape Daifuku, Dia III, Composure, Temper II, Distract III and Gain-STR.
- Casting sets: RDM/SCH with Tropical Crepe, Gain-INT, Wizard's Roll 10 (Crooked Cards) and Warlock's Roll 9 with job bonuses, Indi-Acumen and Geo-Malaise (Blaze of Glory, 20% potency). They leave out Orpheus's Sash. The nukes are Fire V on a target with a neutral (100%) resist rank.
- Odyssey gear at rank 30. Nyame alone at rank 25, Path B.
- Flametongue, Ice Brand and Wizard's Rod were left out. The page says Flametongue was clearly the best off-hand for nearly every physical weapon skill. At high buffs it even beat Naegling as the Savage Blade main hand, with Naegling counted at 15 buffs for its attack bonus.
- Weapon skills at 1200 TP (1000 for Knights of Round and Mercy Stroke), before TP Bonus is added (IzaKastra/wsdist_beta, actions.py). Aftermath: AM3 for Death Blossom, AM2 for Imperator and Ruthless Stroke, AM1 for Knights of Round and Mercy Stroke. The TP set starts at 1000 TP.
- The Enspell sets suggest elemental damage pieces on top: Levante Dagger, Quanpur Necklace, Hachirin-no-Obi.

### Blue Mage page assumptions

All from (bg-wiki, All Jobs Gear Sets/Blue Mage):

- Master Level 30, BLU/WAR. The page lists no food or buffs, so the main page's apply.
- Odyssey gear at rank 30. Nyame alone at rank 25, Path B.
- Thibron (TP Bonus +1000) allowed in every set. Ice Brand and Flametongue are off unless stated. Sanguine Blade and Red Lotus Blade also have an Ice Brand version.
- Traits come from the "Zahak Reborn" spell list in an FFXIAH BLU guide: Accuracy and Ranged Accuracy +48, Magic Accuracy +36, Triple Attack +5%, critical hit damage +11%, Store TP +30, Dual Wield +25, STR +11, DEX +37, VIT +15, AGI +8, INT +6, MND +3, CHR +4. Its Skillchain Bonus +16% isn't used. Another spell set gives other traits, so compare the character's own spell set first, Dual Wield, Triple Attack and crit damage above all.
- The live page adds: 8 trait points unlock a trait and each 8 more raise it a tier. A mastered BLU gets Trait Tier +2 from job point gifts, so unlocked traits start at tier 3, with the exceptions the gifts list.
- Weapon skills at 1200 TP before TP Bonus. Aftermath: AM3 for Expiacion, AM1 for Chant du Cygne and Imperator. TP sets start at 1000 TP.

### What the main page left out

- Not tested: Nyame rank 30; Nyame Paths A and C; Sortie Empyrean +2 earrings (the +1s were tested); stage 5 Prime weapons (stage 4 was tested); Voracious Resurgence rings; Karieyh Ring +1 and Balder Earring +1; Hoxne Ampulla.
- Augment levels used: Odyssey rank 30, except Nyame at rank 25; Limbus armor and accessories rank 30; Hoxne Earring at Mastery Rank 7.
- So the simulated Nyame is rank 25 Path B, not rank 30.

### Sets on each page

- RDM: Savage Blade, Chant du Cygne, Death Blossom, Knights of Round, Imperator, Requiescat, Mercy Stroke, Ruthless Stroke, Evisceration and Black Halo (mid and high); Sanguine Blade, Seraph Blade, Red Lotus Blade and Aeolian Edge (mid only); Fire V free nuke and magic burst; Enspell with Crocea Mors or Archduke's Sword; Naegling + Thibron TP at −50% and −25% DT (the same set).
- BLU: Expiacion, Chant du Cygne, Requiescat, Imperator and Savage Blade (mid and high); Sanguine Blade and Red Lotus Blade (mid, plus an Ice Brand version); Tizona + Thibron (AM3) and Caliburnus + Thibron (AM1) TP at −50% and −25% DT. No blue magic sets.

### What this means for a character below those ranks

- The pages overvalue an Odyssey piece held at a lower rank than the sims'. A substitution needs the lost values from rank-augments.md weighed against the next piece; the page totals can't be corrected by hand. The simulator has rank 0, 15, 20, 25 and 30 versions of each Nyame, Bunzi's and Gleti's piece and of Coiste Bodhar, and each Nyame path (IzaKastra/wsdist_beta, gear.py), so a run at the character's own ranks is the clean check. It has no entry for a Nyame piece between rank 0 and rank 15, and Alabaster Earring and Murky Ring (R30), Sailfi Belt +1 (R15), Mirage Stole +2 (R25) and Dls. Torque +1 (R20) have only their max-rank entry, so each of those needs an edited dict (wsdist data errors).
- Gleti's pieces keep their PDL and crit rate at rank 0, since those are base stats, but a rank 0 piece is 30 Attack and 15 Accuracy short of the sims' rank 30 copy.
- A data error, as one sign of the unknown quality: the simulator's rank 0 Bunzi's Rod has DMG 152 (144+8), but the item's own text says DMG 144 (IzaKastra/wsdist_beta, gear.py; bg-wiki, Bunzi's Rod; the item's help text). More under wsdist data errors.
- What a character's own copies lack next to the sims', and which of the sims' pieces the character doesn't own, are in that character's `data/<Character>/<Character>_notes.md` and `<Character>_gear_notes.md`.

Utility the sets ignore:

- Each set maximizes one number. The weapon skill and nuke sets carry no damage taken, enmity or other utility. Only the TP sets have a DT limit.
- The casting sets leave out Orpheus's Sash, whose bonus falls with distance: +15% within 1.93' of the target, +1% at 13' or more (bg-wiki, Orpheus's Sash). The magic weapon skill and Enspell sets do wear it, and the simulator counts it at a flat +15% (IzaKastra/wsdist_beta, gear.py), so those sets assume you stand close.
- The Enspell set only pays while meleeing, since Enspell damage lands on melee hits.
- The sims take pieces for STR, DEX, MND and other base stats whenever those add damage. Hoxne Earring has only base stats, by Mastery Rank (bg-wiki, Hoxne Earring); the sim counts +15 to each at Mastery Rank 7. It is in every physical weapon skill set on both jobs.

The pages assume upgraded relic, mythic and empyrean weapons ("Level 119 III") and stage 4 primes. A Tizona that exports "Path: A" is Level 119 III like the sims' (Combat skill). The export can't show the stage of an Almace or Mpu Gandring; ask the player.

### What the simulated sets favour

Simulation results, not mechanics. Counts are sets out of the group.

**RDM physical, non-crit** (Savage Blade, Death Blossom, Knights of Round, Imperator, Requiescat, Mercy Stroke, Ruthless Stroke, Black Halo):

- Both buff levels: Nyame Flanchard 16/16, Hoxne Earring 16/16, a WSD back 16/16 (Sucellos's or Alabaster Mantle), Leth. Houseaux +3 14/16 and Epaminondas's Ring 14/16 (Requiescat takes neither), Viti. Chapeau +4 12/16.
- Mid buff, attack and WSD: Coiste Bodhar 8/8, Nyame Mail 8/8, Rep. Plat. Medal 7/8, Sailfi Belt +1 7/8, Nyame Gauntlets 6/8.
- High buff, PDL in place of attack: Crepuscular Pebble 8/8 and Sroda Ring 7/8 (already in 4 of the mid-buff sets, likely for its STR +15). Hands leave Nyame Gauntlets in all 8, for Atro. Gloves +4 (WSD, 4) or Malignance Gloves (PDL, 4). Body splits between Bunzi's Robe (4) and Nyame Mail (4). The neck leaves Rep. Plat. Medal in 7 of 8. Dls. Torque +2 takes 4 of those, for its MND +15; it has no PDL (bg-wiki, Dls. Torque +2).
- The pattern: head, legs, feet, one ring and the back stay WSD at high buff. The ammo turns to PDL in every set, the second ring only in Death Blossom, Requiescat and Ruthless Stroke. Hands and body split by weapon skill. Attack-only pieces drop out.

**RDM crit** (Chant du Cygne, Evisceration): nearly the same set at both levels, with no WSD pieces: Yetshila +1, Blistering Sallet +1, Fotia Gorget and Fotia Belt, Malignance Gloves, Zoar Subligar +1 and a DEX/crit cape. Body is Sworn Platemail at mid buff and Malignance Tabard (PDL) at high.

**RDM magic weapon skills** (mid only): Sroda Tathlum, Malignance Earring, Nyame Mail, Epaminondas's Ring, Orpheus's Sash and Leth. Houseaux +3 in all four, and a WSD cape in all four. Leth. Chappel +3 in three; Sanguine Blade takes Pixie Hairpin +1.

**RDM nukes**: the free nuke wears Lethargy +3 head, body, hands and legs. The magic burst set swaps to Ea +1 head, body and legs, Bunzi's Gloves and Mujin Band. Both wear Bunzi's Rod, Ammurapi Shield, Sibyl Scarf, Malignance and Regal Earrings, Freke Ring, an INT/Magic Attack cape, Skrymir Cord +1 and Viti. Boots +4.

**BLU physical, non-crit** (Expiacion, Savage Blade, Imperator, Requiescat):

- Both buff levels: Hoxne Earring 8/8, Hashishin Kavuk +3 7/8, and Mirage Stole +2, Nyame Sollerets and Epaminondas's Ring 6/8 each (Requiescat takes none of the three).
- Mid buff: Coiste Bodhar, Nyame Mail and Nyame Flanchard 4/4, Nyame Gauntlets and Beithir Ring 3/4.
- High buff: Crepuscular Pebble 4/4 and Sroda Ring 3/4. Body leaves Nyame Mail in all 4, for Assim. Jubbah +4 (WSD; Expiacion, Imperator) or Gleti's Cuirass (PDL; Savage Blade, Requiescat). Legs split between Nyame Flanchard and Gleti's Breeches, 2 each. Nyame Gauntlets stay in 2.
- The pattern is less uniform than RDM's. Only ammo and body change in every high-buff set.

**BLU Chant du Cygne**: Gleti's Cuirass and Breeches at both levels; high buff adds Gleti's Gauntlets and Boots. Also Adhemar Bonnet +1, Mirage Stole +2, Odr Earring, a DEX/crit cape and Fotia Belt.

**BLU magic weapon skills**: Ghastly Tathlum +1, Hashishin Kavuk +3, Regal Earring, Nyame Mail, Jhakri Cuffs +2, Epaminondas's Ring, an INT/WSD cape, Orpheus's Sash, Luh. Shalwar +4 and Hashi. Basmak +3 in all four. Ice Brand adds about 11% to Sanguine Blade (21,070 against 18,911) and about 4.5% to Red Lotus Blade (14,968 against 14,325).

**TP sets, both jobs**: Sworn Platemail and Sworn Sabatons in all six, and Sworn Brais in all but BLU's two −25% DT sets. BLU also wears Sworn Crown in all four of its sets.

### Sources for the simulated sets

bg-wiki:
[All Jobs Gear Sets](https://www.bg-wiki.com/ffxi/All_Jobs_Gear_Sets),
[All Jobs Gear Sets/Red Mage](https://www.bg-wiki.com/ffxi/All_Jobs_Gear_Sets/Red_Mage),
[All Jobs Gear Sets/Blue Mage](https://www.bg-wiki.com/ffxi/All_Jobs_Gear_Sets/Blue_Mage),
[Bunzi's Rod](https://www.bg-wiki.com/ffxi/Bunzi%27s_Rod),
[Dls. Torque +2](https://www.bg-wiki.com/ffxi/Dls._Torque_%2B2),
[Hoxne Earring](https://www.bg-wiki.com/ffxi/Hoxne_Earring),
[Orpheus's Sash](https://www.bg-wiki.com/ffxi/Orpheus%27s_Sash).

GitHub:
[IzaKastra/bg_job_guides](https://github.com/IzaKastra/bg_job_guides) (README.md, main_page.md, rdm.md, blu.md; last commit 2026-05-03),
[IzaKastra/wsdist_beta](https://github.com/IzaKastra/wsdist_beta) (wsdist.py, actions.py, gear.py, enemies.py; read as text, not run).

## wsdist (Kastra's damage simulator)

wsdist is Kastra's (Asura) open-source FFXI damage simulator and gear-set optimizer, written in Python (https://github.com/IzaKastra/wsdist_beta). It ships as a Tkinter GUI, run as gui_main.py or as the prebuilt gui_main.exe. The simulated sets on bg-wiki's All Jobs Gear Sets pages came from it (see "Simulated sets (bg-wiki All Jobs Gear Sets)"). The bg_job_guides README says an earlier version printed them (gui_wsdist.py), so the current code may not match what built those sets. The player calls it "of unknown quality". This section is for an agent thinking of using it as a calculator: what it computes, how to call it, and what to correct before believing a number.

Everything here comes from reading the source as text at commit d12ac59 (2026-07-12). Nothing was installed, imported or run. File:line references are to that commit. The checks behind the disagreement and data-error lists compared wsdist with bg-wiki item by item, re-reading both:

- Physical: 73 checks. 42 agree, 13 differ, 18 exist only in wsdist.
- Magical: 39 checks. 17 agree, 13 differ, 9 exist only in wsdist.
- Gear: 25 of wsdist's item entries checked against bg-wiki and one character's export. 21 have a data error or differ from that character's copy. The other 4 (Gleti's Knife, Tauret, Fotia Belt, Carmine Cuisses +1) have correct data but an engine problem tied to them.

Rule: wsdist is a second opinion. Where it disagrees with a mechanics section of this doc, the mechanics section wins.

### What it is

- One physical and magical damage model (actions.py and the get_*.py helpers), a player builder that adds up gear, job, merit and buff stats (create_player.py), an item database (gear.py, about 1,900 lines of Python dicts), enemy presets (enemies.py) and a set optimizer (wsdist.py: build_set).
- It computes the average damage and TP return of one weapon skill, one spell or one melee round. It can also run a random-roll TP-to-WS simulation and plot DPS (actions.py:67, run_simulation).
- The enemy presets are mostly Apex monsters, with stats from a Japanese wiki (enemies.py:3), plus a "BG Wiki sets" preset matching the bg-wiki test enemy (Test enemy): Defense 1500, Evasion 1350, VIT/AGI 340, INT/MND/CHR 280 (enemies.py:23).

### Running it (untested here)

Nothing below was run in this repo. Treat it as a reading of the code.

**Setup.** Use Python 3. The pins (numpy 2.2.6, numba 0.63.0, matplotlib 3.10.7, pillow 12.0.0) suggest 3.10 to 3.13; that range is unverified. Run `pip install -r requirements.txt`. requirements.txt is UTF-16 LE with a byte-order mark (bytes FF FE). pip should decode it from the mark; if not, re-save it as UTF-8 first. It also pins PyInstaller, pefile and pywin32-ctypes, which only matter for building the exe. The damage code needs numba (get_pdif.py:7, @njit), numpy and matplotlib (actions.py:9). The GUI also needs tkinter and Pillow. Run everything with the wsdist_beta folder as the working directory, because the modules import each other by bare name and the GUI reads defaults.pkl, item_list.csv and icons32 from the current folder.

**GUI.** `python gui_main.py`, or double-click gui_main.exe. The README recommends downloading the exe from the repo's Actions page, and says the exe only picks up edits to gear.py and enemies.py. Tabs: Quicklook, Optimize, Simulations, Player Stats. Inputs:

- Main job, support job and Master Level (default 30).
- Buffs: BRD songs, COR rolls, GEO bubbles, WHM spells and a storm, and food. The numbers come from buffs.py.
- "Special toggles": job abilities (Composure, Temper II, EnSpell, Chainspell, Magic Burst, Berserk, and so on), plus the target debuffs Angon, Armor Break, Box Step, Corrosive Ooze, Swooping Frenzy and Distract III (gui_main.py:1728-1785; buffs.py:131-140).
- Enemy: a preset, or typed Evasion, Defense, VIT, AGI, INT, MND, CHR, Magic Evasion, Magic Defense, Magic DT% and resist rank.
- Weapon skill and TP (default 1900), spell, enhancing skill (default 500), aftermath level, Odyssey rank (default 30).
- Optimize tab: a PDT and MDT requirement (default 0), the metric, and a "similar results" percentage.

**Headless.** The GUI's Optimize button calls one function (gui_main.py:1106-1110):

`build_set(main_job, sub_job, master_level, buffs, abilities, enemy, ws_name, spell_name, action_type, min_tp, check_gear, starting_gearset, pdt_requirement, mdt_requirement, input_metric, print_swaps, next_best_percent)` (wsdist.py:144)

| Parameter | What to pass |
|---|---|
| main_job, sub_job | Lowercase job codes, "rdm", "nin". The job checks compare against item "Jobs" lists as given (wsdist.py:308), so case matters. |
| master_level | Int. Clamped to 0-50; support job level = 49 + ML/5, floored (create_player.py:46-49). |
| buffs | Dict of sources, each a flat {stat: value} dict summed into the player (create_player.py:216-221), e.g. {"food": {...}, "brd": {...}}. Food "Attack" and "Ranged Attack" must be renamed "Food Attack" and "Food Ranged Attack" so they apply after Attack% (gui_main.py:956-959; create_player.py:126-128). gui_main.py:862-974 shows how songs, rolls and bubbles become numbers. |
| abilities | Dict of the GUI toggle names set True or False ("Composure", "Temper II", "EnSpell", "Magic Burst", ...), plus "Enhancing Skill" (int), "Aftermath" (0-3), "Storm spell" (a name such as "Firestorm II", or "None"), "Enemy Resist Rank" ("100%" and so on), "99999" (bool) and optional "Verbose Swaps" (gui_main.py:993-998, 1097). |
| enemy | create_enemy(preset_enemies["BG Wiki sets"]), with two fixes the GUI makes: add stats["Base Defense"] = stats["Defense"] (every weapon skill reads it, weaponskill_info.py:32, so it fails without it), and rename "Magic DT%" to "Magic Damage Taken" (gui_main.py:1014-1017; otherwise target MDT is silently 0). Apply defense-down and evasion-down debuffs to enemy.stats yourself (gui_main.py:1007-1013). |
| ws_name, spell_name | Pass both. Weapon skill names must appear in wsdist.py:155-169. Spell names follow the table at actions.py:1330-1353 ("Fire V"); "EnSpell" selects the enspell path (actions.py:1126). Pass "None" for the unused one. |
| action_type | "weapon skill", "spell cast" or "attack round" (wsdist.py:449-470). The docstring's "ranged attack" and "tp round" aren't accepted. |
| min_tp | Weapon skill TP before TP Bonus; for "attack round", the TP at which you weapon skill. |
| check_gear | Dict of all 16 slots (main, sub, ranged, ammo, head, neck, ear1, ear2, body, hands, ring1, ring2, back, waist, legs, feet), each a list of item dicts to try. An empty list freezes the slot at starting_gearset's item (wsdist.py:232). At least one slot needs two or more items, or the final print fails (the GUI asserts this, gui_main.py:1085). |
| starting_gearset | Dict of all 16 slots, each an item dict. Only frozen slots keep their item; every other slot starts from a random pick (wsdist.py:226-234). |
| pdt_requirement, mdt_requirement | Negative numbers, e.g. -50. 0 means no constraint. |
| input_metric | Case-sensitive. Weapon skill: "Damage dealt", "TP return" or "Magic accuracy"; anything else falls back to damage (actions.py:2371-2390). Spell: "Damage dealt" or "TP return" (actions.py:1453-1461). Attack round: "Time to WS", "Damage dealt", "TP return", "DPS", "TP > Damage" or "Damage > TP"; anything else falls back to Time to WS (actions.py:1077-1097). |
| print_swaps, next_best_percent | Whether to print single-slot alternatives within that percent of the best (not main, sub, ranged or back). |

It returns (best_player, best_output). best_player.gearset[slot]["Name2"] is the chosen item and best_player.stats the summed stats. best_output is [damage, TP return, invert] for weapon skills and spells, and [damage, TP per round, seconds per round, invert] for melee rounds (wsdist.py:577).

A minimal weapon skill run, untested:

```python
# Untested. Working directory: wsdist_beta.
import numpy as np
from gear import all_gear, all_food
from enemies import preset_enemies       # enemies.py:36
from create_player import create_enemy
from wsdist import build_set

enemy = create_enemy(preset_enemies["BG Wiki sets"])
enemy.stats["Base Defense"] = enemy.stats["Defense"]
enemy.stats["Magic Damage Taken"] = enemy.stats.pop("Magic DT%")

food = {k: v for k, v in all_food["Grape Daifuku +1"].items() if k not in ("Name", "Type")}
food["Food Attack"] = food.pop("Attack")
food["Food Ranged Attack"] = food.pop("Ranged Attack")

slots = ["main", "sub", "ranged", "ammo", "head", "neck", "ear1", "ear2",
         "body", "hands", "ring1", "ring2", "back", "waist", "legs", "feet"]
start = {s: all_gear["Empty"] for s in slots}
start["main"], start["sub"] = all_gear["Naegling"], all_gear["Gleti's Knife R0"]
cands = {s: [] for s in slots}           # [] = frozen at start[s]
cands["body"] = [all_gear[n] for n in ["Nyame Mail R20B", "Empty"]]
cands["feet"] = [all_gear[n] for n in ["Nyame Sollerets R20B", "Empty"]]

np.random.seed(1)                         # the search starts from a random set
player, out = build_set("rdm", "nin", 30, {"food": food},
                        {"Composure": True, "Temper II": True, "Enhancing Skill": 500,
                         "Storm spell": "None", "Enemy Resist Rank": "100%"},
                        enemy, "Savage Blade", "None", "weapon skill", 1200,
                        cands, start, 0, 0, "Damage dealt", True, 1)
print({s: player.gearset[s]["Name2"] for s in slots}, out)
```

build_set shuffles the check_gear lists in place (wsdist.py:299-300) and overwrites starting_gearset (wsdist.py:234). Pass copies if you reuse them.

The `__main__` block of wsdist.py is stale and can't run as written. It needs three command-line arguments and calls create_enemy(apex_toad), which nothing defines (wsdist.py:579-616).

**How gear is named.** Each item is a Python dict in gear.py:

- "Name" is the in-game name, used for the item id and icon.
- "Name2" is unique per augment path or rank. The set lists, the GUI and the gear.all_gear lookup are keyed by it (gear.py:3-4, 1953). Items without one get Name2 = Name (gear.py:1930-1935).
- Odyssey pieces have one entry per rank, for example "Gleti's Knife R0", "Gleti's Knife R15", "Gleti's Knife R20", "Gleti's Knife R25" and "Gleti's Knife R30" (gear.py:54-58), with a "Rank" key. Nyame has one per rank and path: "Nyame Flanchard R0", "R15A" ... "R30C".
- Other forms: "Almace" and "Almace R15" (REMA augment), "Almace (sub)" and "Almace R15 (sub)" (off-hand entries without main-hand-only stats), "Crocea Mors R25C", "Mpu Gandring IV" and "V" (prime stages), "Hoxne Earring MR07", "Amalric Coif +1A" (Nolan path), "Merlinic Crackows (Occult Acumen)" (one augment roll).
- Ambuscade capes are generated as `<cape> <stat> <main stat>`, e.g. "Sucellos's Cape STR Weapon Skill Damage", "Sucellos's Cape DEX Crit Rate", "Sucellos's Cape INT Magic Attack" and "Sucellos's Cape MND Weapon Skill Damage (Magic)". Every physical cape is Accuracy and Attack +20, stat +30, main stat +10 and PDT -10 (gear.py:1162-1225). A cape with Haste or Fast Cast has no entry.
- Names are the long in-game names ("Vitiation Chapeau +4"), not GearSwap's short ones ("Viti. Chapeau +4"). item_list.csv maps id, long name and short name.
- Stat keys must spell one of gear.py's available_stats exactly (gear.py:1916). gear.py checks its own lists at import, but a dict built in your own script isn't checked, so a misspelled stat silently counts as nothing.

**Getting a character's gear into the GUI.** Two import buttons on the Optimize tab:

- "Import selections" reads lines of the form slot="Name2", the same format "Export selections" writes, and selects exactly those entries, with no filters (gui_main.py:391-425). This is the reliable way to run mixed ranks.
- "Select all File" reads a `//gs export` file, maps short names through item_list.csv, then selects every Name2 whose Name matches. After that it deselects by rules (gui_main.py:428-524), and those rules misfire for a character with mixed ranks:
  - Odyssey pieces whose Rank differs from the one rank setting are dropped (gui_main.py:476-477).
  - Nyame entries not ending in "B" are dropped (gui_main.py:480-482), which includes every "R0" entry, and so every Nyame piece below rank 15.
  - Relic, mythic and empyrean weapons are dropped unless their Name2 has "R15" (gui_main.py:490-491). An unaugmented Almace would be simmed as "Almace R15": DMG +5, DEX and MND +20, and Chant du Cygne +10%.
  - Stage V primes, Kraken Club, Empyrean +2 earrings and Balder Earring +1 are dropped too.
  - Items with only one entry, such as the R15-only ones under "wsdist data errors", get that entry whatever the character's copy is.

### What it models

- Physical weapon skills: per-hit hit rate, pDIF, fSTR, WSC, fTP, WSD on the first hit, named weapon bonuses on every hit, crits for crit weapon skills, multi-attack on weapon skills (two checks), dual-wield off-hand hit, TP return (get_phys_damage.py:19, 28; actions.py:1625-2404).
- Magical and hybrid weapon skills: the bg-wiki base damage formula with weapon level fixed at 119, dSTAT, MAB/MDB, affinity, obi, Magic Crit II, WSD (actions.py:2312-2364).
- Elemental nukes: tier I to VI and -ja tables, Magic Damage, dINT bands, resist-state averaging, magic burst with the resistance-rank bonus, burst gear caps, RDM traits (actions.py:1159-1463; get_dint_m_v.py). Also ninjutsu, Quick Draw, ranged attacks, and tier I enspells.
- Melee rounds: hit rates per hand, multi-attack chains up to 8 hits, delay with haste caps, dual wield and the 80% delay cap, Store TP and TP per hit, enspell damage per hit, Empyrean and Mythic aftermath (actions.py:184-1099).
- Buffs from BRD, COR, GEO, WHM, food and about 60 job ability toggles; defense, evasion and magic-defense debuffs; a PDT and MDT requirement as a hard constraint.

Built-in assumptions that a result inherits:

- 5/5 crit rate merits (create_player.py:915) and 8/8 merits in every combat and magic skill, +16 (create_player.py:860, 871, 879-880, 918-920). RDM Accuracy merits 0.
  - That matches a character with 8/8 merits in each of those skills. It also covers divine and blue magic skill and evasion, merited or not. wsdist has no enfeebling skill.
- RDM magic: MAB +28 trait, +48 from job points and gifts, Magic Accuracy +90 from job points and gifts, +40 from merits. 15 of the merit 40 are five Group 1 elemental-accuracy merits, which in game apply to one element; wsdist applies them to every spell and magical WS (create_player.py:277-283, 814-815, 892, 932). So the 15 overstates every element a character has no merit levels in, and at +2 a level it is 5 high on a merited element too (Job sources). The other 25 are 5/5 Group 2 Magic Accuracy (Job sources). The same line gives RDM 5/5 En-spell Damage merits (+15).
- BLU is always the "Zahak Reborn" spell set: Accuracy +48, Magic Accuracy +36, Store TP +30, Dual Wield +25, Triple Attack +5%, crit damage +11%, plus fixed stat bonuses. No Attack Bonus, no Double Attack (create_player.py:972-987). Compare with the character's own spell set before trusting a BLU result.
- Requiescat at 5/5 merits (85% MND). Naegling at +13% attack, as if 13 buffs were up (weaponskill_info.py:54-63).
  - 85% assumes 5/5 Requiescat merits (73% + 4 × 3%), so ask the player for the merit level before trusting a Requiescat result.
- Orpheus's Sash always at its +15% maximum. Hachirin-no-Obi only with a SCH storm, and no day bonus or random weather (actions.py:1380-1382, 1415, 2341-2349).
- Magic burst: a two-step skillchain always (actions.py:1184), and +100 magic accuracy, which bg-wiki also gives only as unverified (actions.py:1179-1180).
- Mythic aftermath at 85% of each range (create_player.py:526-560). Base stats by job with no race (create_player.py:747-796).
- No level correction anywhere. No follow-up attack on weapon skills. A 20% hit-rate floor on ranged as well as melee, which the code says is there to keep the optimizer from getting stuck at 0%.
- Dual wield only for NIN, DNC, THF or BLU main, or /NIN or /DNC (wsdist.py:391). RDM needs /NIN or /DNC.

What it doesn't model:

- Enfeebling, enhancing (apart from Temper II and enspell damage), Cure and healing, and every blue magic spell, BLU nukes included.
- Fast cast, recast, enmity, and skillchain damage itself.
- Target magic evasion: every preset has 0 (see "Where wsdist and bg-wiki disagree").
- Vorpal Blade and Flash Nova: neither is in its weapon skill lists or data (wsdist.py:158, 161), so it can't build sets for them.
- The named weapon skill bonuses of Kaja Sword, Kaja Rod and Kaja Knife; the Carmine +1 set bonus; Aeolian Edge's area effect; Sanguine Blade's HP drain.
- The 5% hit-rate cap at a 10% resistance rank, and the full resist at a 5% rank.

### How it picks the "best" set

- One number, set by input_metric. For a weapon skill, the average damage of one weapon skill at the given TP plus TP Bonus. For a spell, average damage after resist averaging. For a TP set, by default the average seconds to reach the weapon skill TP (scored as 1/time). Accuracy counts only through expected damage, and nothing counts DT beyond the hard requirement, nor enmity or any other utility.
- Search (wsdist.py:264-531): build a random starting set from the candidates. Try every pair of slots and every pair of items in them, in random order, keeping any change that raises the number at once. Stop after a full pass with no change, or after 10 passes (wsdist.py:150-151, 271-498). If a DT requirement is set, an outer loop tightens a temporary PDT/MDT limit by 1 point per round until the requirement is met, or until 3 rounds bring no change (wsdist.py:434-444, 500-531). PDT plus DT is capped at -50 before PDT II is added.
- This is a local search. The file's own header says crit weapon skills (and Shining One) can have two optima, a crit build and a WSD build, and the search can stick in whichever it starts near (wsdist.py:8-9). The start is random and unseeded, so run it several times, or seed numpy, and compare.
- The "Magic Accuracy" weapon skill metric in the GUI's list (gui_main.py:2344) doesn't match the engine's "Magic accuracy" (actions.py:2377), so picking it in the GUI optimizes damage instead.
- The "similar results" list uses best % metric where it means best - metric (wsdist.py:487). An item scoring about half or a third of the best can appear as "within 1%". This is rare and affects only that printout.
- The bg-wiki output formatter is switched off with `if False:` (wsdist.py:574).

### Where wsdist and bg-wiki disagree

"bg-wiki right" means bg-wiki's page holds and wsdist is wrong. Biggest gear effects first.

Physical and melee:

- **Crit pDIF counted twice** (get_pdif.py:34, 62-71 per roll; 103-104, 132-140 averaged). wsdist adds 1 to the attack ratio for a crit, clips at the non-crit cap, then adds 1 to pDIF again. bg-wiki's PDIF page adds 1.0 to the ratio only, with one-hand caps of 3.25 (non-crit) and 4.25 (crit). Effect: at cRatio 1.5 a one-hand crit averages 3.5 pDIF in wsdist against 2.5 on bg-wiki (+40%; +51% at cRatio 1.0, +33% at 2.0). The two meet only at a ratio of 3.625. Below that, each point of crit rate is worth about twice as much pDIF as it should, and with PDL gear the crit cap becomes (3.25+t)(1+p)+1 instead of (4.25+t)(1+p). Verdict: bg-wiki right. It inflates Chant du Cygne, Evisceration and auto-attack crits more than anything else in these jobs. If the older version that printed the bg-wiki sets shared it, those crit sets lean too hard on crit rate.
- **Off-hand weapon skill hit gets the first-swing +100 accuracy** (actions.py:1765-1768). bg-wiki (Category:Weapon_Skills) gives the roughly +100 bonus to the first swing only. No page addresses the off-hand hit directly, so "no bonus" is a reading of "additional swings" (about 75% confident). Effect: overrates the off-hand hit's hit rate, damage, TP and multi-attack, and undervalues accuracy in dual-wield Savage Blade, Black Halo and Expiacion sets. Worst with a skill-less off hand such as Thibron, about 200 accuracy behind Naegling. Verdict: bg-wiki right.
- **"Occasionally attacks X times" on weapon skills** (get_ma_rate.py:234-235, 261-267, 273-274; actions.py:1696-1705). wsdist rolls OA2/OA3 on the main weapon and OA2 to OA8 on the sub during weapon skills: Kraken Club, Blurred Knife +1 and Demersal Degen +1 (OA2 45%) among RDM off hands. bg-wiki: these proc on weapon skills only from Mythic AM3. Double, Triple and Quad Attack can proc at most twice per weapon skill, which wsdist gets right. Verdict: bg-wiki right. For Tizona or Murgleis AM3, wsdist is right, except that it can roll AM3 twice on a single-wielded multi-hit weapon skill.
- **Crit rate and TP Bonus pooled across hands** (create_player.py:671-672; actions.py:244, 1645). Every weapon stat except DMG, delay, skill, OA, follow-up and enspell damage goes into one pool. bg-wiki (Dual_Wield, TP_Bonus): crit rate counts only for its own weapon's hits, and TP Bonus counts from the main hand only, except on Magian, Odyssey and augmented TP Bonus weapons. Effect: with Gleti's Knife in the off hand, wsdist credits its Crit Rate +5 to the main-hand hits too. Thibron's +1000 is an augment, so the TP Bonus pooling is harmless for it. Verdict: bg-wiki right.
- **Average pDIF** (wsdist-only; get_pdif.py:79-144). The optimizer uses the midpoint of the pDIF range, clipped to the cap, with crits blended in linearly. bg-wiki's average (Motenten's model, marked "Verification Needed") adds a spike at pDIF = 1 for wRatio 0.5 to 1.5. Against it, wsdist runs about 9% low at wRatio 0.77, matches at 1.0 and runs up to 6% high at 1.2, so between 0.8 and 1.2 it values attack about 1.5 times as much (derived). From 1.5 up it matches, and near the cap it is within 1%. Verdict: unconfirmed either way; distrust its attack-versus-other-stat calls against high-defense targets.
- **Defense Down effects stacked** (gui_main.py:962-972, 1007-1015; buffs.py:110-137). wsdist sums every defense-down toggle into one Defense × (1 - sum), minimum 1. bg-wiki (Defense_Down): Dia, Box Step and Frailty add, plus at most one Defense Down effect (Angon, Armor Break, Corrosive Ooze, Swooping Frenzy, weapon skill effects); those don't stack with each other. The code comment at actions.py:1721 says "multiplicative", but the code adds. Verdict: bg-wiki right. Enable at most one of those four toggles.
- **Distract III fixed at -280 evasion** (buffs.py:138). bg-wiki: potency = floor(6/21 × (enfeebling skill - 190)) + floor(dMND/5) (0 to 10), capped at 130 before potency gear. Saboteur doubles the base on normal monsters and adds 25% on NMs, and NM tests showed about 130 to 152. Verdict: bg-wiki right. 280 fits only a non-NM with Saboteur and potency gear, so wsdist overstates hit rate against bosses.
- **Hit rate not floored, no level term** (get_hit_rate.py:15). wsdist gives +0.5% per accuracy point. bg-wiki: 75 + floor((Acc - Eva)/2) - 2 × dLVL, in whole percent, with dLVL only in level-corrected zones. Verdict: bg-wiki right, but the average value per point is the same. It matters only when aiming at an exact accuracy target. Ignoring dLVL is right only in zones without level correction.
- **Berserk as a support job** (create_player.py:232-235). wsdist: a flat 25% for /WAR. bg-wiki: 25%, plus 5/256 at WAR levels 50, 60, 70, 80 and 90, but it doesn't say whether a support job's level counts. If it does, as with Warcry's formula, /WAR at 54 gets 69/256, about 27% (derived). Verdict: bg-wiki right if that reading holds; wsdist would be 2% short.
- **Fotia TP retention in averaged mode** (actions.py:1849). The optimizer multiplies the two 1% chances, so it is near zero even with both pieces on. bg-wiki: Fotia Gorget and Fotia Belt each give a 1% chance to keep TP. The random-roll path (actions.py:2212-2214) is right. Verdict: bg-wiki right. The optimizer ignores about 1% of TP spent per piece.
- **TP-scaled accuracy invented** (weaponskill_info.py:123-127, 1001-1005). Realmrazer and Swift Blade get +0/+20/+40 accuracy at 1000/2000/3000 TP; the code comment says the numbers were made up. bg-wiki: accuracy varies with TP, amounts unknown. Treat any accuracy result for either as a guess.
- **Listed and augmented PDL** (get_pdif.py:26, 96). wsdist sums all PDL into one (1 + PDL). bg-wiki's Talk page finds augmented PDL (the JSE necks) multiplies separately on non-crits, and the crit tests were inconclusive. Verdict: unsettled, and small: 14% listed with a 6% neck is ×1.20 in wsdist against ×1.208.
- **Store TP on the flat 10 TP of extra weapon skill hits** (actions.py:1844-1848, 1916). wsdist gives each hit after the first main and first off-hand hit 10 × (1 + Store TP). bg-wiki says a flat 10 and doesn't say whether Store TP raises it. Verdict: unsettled, at most a few TP per hit.

Magic:

- **Every preset enemy has Magic Evasion 0 and Magic Defense 0** (enemies.py:13-23), including "BG Wiki sets". With meva 0, wsdist skips the hit-rate step and uses 1.0, not even the 95% cap (actions.py:1212, 1262, 1409, 2314). bg-wiki (Resist, Magic_Hit_Rate): monsters generally have C-rank magic evasion for their level times a resistance-rank multiplier, and a level 135 foe needs about 1,028 magic accuracy at a 100% rank to reach the cap. Verdict: bg-wiki right. If the bg_job_guides sets used this preset, every RDM/BLU nuke, burst, enspell and magical weapon skill set there gave magic accuracy zero value (inference); they aren't evidence that magic accuracy can be dropped. Enter a real Magic Evasion before using any magic result.
- **Enspells never resisted** (actions.py:312-331, 982-989, 1131-1157). wsdist builds enspell damage the way bg-wiki does: base plus Enspell Damage, times (1 + Enspell Damage%), Composure +200%, merits +15, gifts +23, no MAB or Magic Damage. But it never checks magic accuracy. bg-wiki (Category:Enspell): each hit rolls magic accuracy and resist, using Magic Accuracy, the main hand's Magic Accuracy skill and enhancing skill (RDM main only). Verdict: bg-wiki right. wsdist's enspell sets put no value on magic accuracy, or on enhancing skill as accuracy.
- **Sign of Magic Damage Taken on magical weapon skills** (actions.py:1219, 1319, 1443, 2358; gui_main.py:1017). Spells multiply by (1 + Magic DT%/100), but magical weapon skills and Quick Draw by (1 - Magic DT%/100). Presets store reductions as negatives (Apex Toad -25), so a magical weapon skill gets ×1.25 where a spell gets ×0.75. bg-wiki (Magic_Damage, Weapon_Skill_Damage): one TMDA term for both, base 1.0. Verdict: bg-wiki right. The "BG Wiki sets" enemy has Magic DT 0, so its sets are unaffected.
- **Reforged AF set bonus** (create_player.py:681-735). wsdist applies it only while a Regal Ring or Regal Earring is worn, then +15 Accuracy, Ranged Accuracy and Magic Accuracy per AF piece, up to 5 per Regal item. With Regal Earring and 5 AF pieces that's +75; without a Regal piece it's 0. bg-wiki: +15/30/45/60 for 2/3/4/5+ pieces, with a Regal accessory counting as one piece. wsdist's item list has only Atrophy Chapeau and Gloves and Assimilator's Jubbah and Shalwar. Verdict: bg-wiki right. wsdist, and so the bg-wiki sims, undervalue 2 to 4 AF pieces worn without Regal Earring, and never consider the other AF pieces.
- **BLU magic stats** (create_player.py:871, 903, 943, 972-987). No blue magic, Cure or healing at all. BLU's only non-gear magic accuracy is the spell-set block's +36, which equals the four Magic Accuracy gifts (5 + 8 + 10 + 13). Missing: the job point Magic Accuracy category (+20) and the MAB, magic burst and magic accuracy traits from set spells. A "Blue Magci Skill" typo at line 871 loses BLU's base 424 Blue Magic skill, though nothing reads it. Verdict: bg-wiki right. For BLU magical weapon skills, add the +20 and any traits by hand.
- **Negative dINT clamped to 0** (actions.py:1162; get_dint_m_v.py:61-67). bg-wiki (Magic_Damage): negative dINT uses reduced M and can drive D below V, even to 0, but gives no M values for it. wsdist's own comment doubts the clamp. Verdict: bg-wiki right; wsdist overstates nukes when the target's INT is higher than yours.
- **Tier V base damage at dINT 50-99** (get_dint_m_v.py:112-117). wsdist's V50: Aero V 1110, Fire V 1140, Blizzard V 1170, Thunder V 1200. bg-wiki: 1010, 1040, 1070, 1100, each equal to V0 + 50 × M0, so wsdist's are +100 typos. Stone V and Water V and every other tier V cell match. Verdict: bg-wiki right. The bg-wiki RDM Fire V set most likely sits in the dINT 100-199 band, where wsdist is right (about 75% confident).
- **Tier IV table** (wsdist-only; get_dint_m_v.py:106-111). At dINT 0-49 wsdist has M of 4.1 for Fire IV, 4.8 for Blizzard IV and 4.5 for Thunder IV; bg-wiki has 4.2, 3.9 and 3.6, each of which lands exactly on the next band's V. wsdist's Thunder IV V at dINT 300 is 1325; bg-wiki's is 1425. Effect: Blizzard IV and Thunder IV up to 44 base damage too high at dINT 49, Fire IV about 5 low, Thunder IV 100 low at dINT 300-399. Tier VI and the -ja rows are also off, but RDM and BLU can't cast them. Verdict: take tier IV from bg-wiki.
- **No resistance-rank forced 1/2 resist on magical weapon skills** (actions.py:2332-2358). The spell path has it; the magical weapon skill path doesn't. bg-wiki (Weapon_Skill_Damage) includes resistance-rank reduction for magical weapon skills. Verdict: bg-wiki right. Matters only against an element the target resists at 50% or stronger.
- **Magical weapon skill magic accuracy** (actions.py:1739, 2312-2314). wsdist: Magic Accuracy + main-hand Magic Accuracy skill + a dINT term, dINT even for MND-based weapon skills such as Seraph Blade (a TODO says dMND probably applies). No skill term, no first-hit bonus, and no Fotia +10. bg-wiki assumes a bonus like the physical first swing's, unconfirmed, and its Fotia Belt page says the belt's accuracy counts on magical weapon skills (citing a developer post). Verdict: unsettled, except Fotia's +10, which counts per bg-wiki.
- **Fotia fTP on Sanguine Blade** (actions.py:1670; weaponskill_info.py:147). wsdist adds Fotia's +25/256 fTP to every weapon skill. bg-wiki: the latent needs a weapon skill with a skillchain property, and Sanguine Blade has none. Verdict: bg-wiki right. The bg-wiki Sanguine Blade sets don't wear Fotia.
- **Klimaform** (wsdist-only; create_player.py:424-426). wsdist: +15 magic accuracy to every spell and magical weapon skill. bg-wiki: +15 only for spells whose element matches the weather. Verdict: bg-wiki right.
- **Resistance-rank magic burst bonus** (actions.py:1109-1116, 1182). wsdist lowers the target's rank one step for the skillchain, then adds a rank bonus to the burst term: 150% +150, 130% +115, 115% +85, 100% +60, 85% +50, 70% +40, 60% +15, 50% +5, 40% and below 0. A default 100% target becomes 115%, so the burst multiplier is 1 + 0.35 + 0.85 = 2.20. bg-wiki's Resist and Magic_Burst pages carry the same table and call it additive with the +35%, but no reference covers it, and the Magic_Damage page still gives 1.35. Verdict: wsdist right as bg-wiki currently reads, about 70% confident the term is real. It explains why wsdist's RDM Fire V burst set shows 62,098 damage against 17,930 for the free nuke. It multiplies the whole spell, so it doesn't change which gear is best inside a burst set.
- **Magic hit rate rounding** (nuking.py:254-266). wsdist truncates toward zero, so an odd negative dMAcc comes out 1% higher than bg-wiki's floor (dMAcc -45 gives 28% instead of 27%). Same 95% cap. No gear effect.

### wsdist data errors

From the gear checks. Correct these in a copy of the item dict before trusting a run with them.

Entries that exist only at a higher rank or path than a character's copy may be, or only at max rank. Without a substitute, the sim uses the stronger one:

| Item | wsdist entry | What it adds over an unaugmented copy | Conf. |
|---|---|---|---|
| Tanmogayi +1 | "Tanmogayi +1 R15", gear.py:310 | DMG +11, Accuracy, Magic Accuracy and Attack +40 each. | 95% |
| Pukulatmuj +1 | "Pukulatmuj +1 R15", gear.py:133 | DMG +36, Accuracy and Magic Accuracy +30, enspell damage +150%. The R15 DMG itself should be +38 (75%). | 95% |
| Marin Staff +1 | "Marin Staff +1 R15", gear.py:100 | Magic Accuracy +40, MAB +40, INT and MND +10, and Unity INT +14 assumed. Leaves out R15's Accuracy +40. | 95% |
| Kentarch Belt +1 | "Kentarch Belt +1 R15", gear.py:1246 | STR and DEX +10. Store TP at the Unity maximum, 5. | 90% |
| Demersal Degen +1 | "Demersal Degen +1 R15", gear.py:316 | Accuracy and Magic Accuracy +45, DEX +10, enspell damage +50%. | 95% |
| Alabaster Earring | "Alabaster Earring R30", gear.py:790 | Rank 30 augments: Accuracy, Ranged Accuracy and Magic Accuracy +15, all attributes +10, Store TP +5. Max rank only: against a rank 2 copy, for example, it overstates Accuracy and Magic Accuracy by 13 and adds 10 attributes and 5 Store TP. | 95% |
| Murky Ring | "Murky Ring R30", gear.py:1154 | Rank 30 augments: Accuracy, Ranged Accuracy and Magic Accuracy +15, Evasion and Magic Evasion +10, crit rate +5%. Max rank only. | 95% |
| Sailfi Belt +1 | "Sailfi Belt +1 R15", gear.py:1249 | Rank 15 augments: STR +15, Double Attack +5%. Max rank only: against a rank 14 copy only STR is 1 over. | 95% |
| Mirage Stole +2 | "Mirage Stole +2 R25", gear.py:691 | Rank 25 augments: STR and DEX +25, Store TP +7, crit rate +5%. Max rank only. | 95% |
| Dls. Torque +1 | "Duelist's Torque +1 R20", gear.py:661 | Rank 20 augments: INT and MND +12 (the duration augments aren't modeled). Max rank only. | 95% |
| Mpu Gandring | "Mpu Gandring IV" and "V", gear.py:359-360 | Only the 119 II and 119 III stages exist. The export gives only the name, and four items share it (DMG 117, 124, 130 and 137; Windower resources, items 21587-21590). The import keeps "IV" (DMG 130). Against the Incomplete dagger (DMG 117, skills +252, nothing else) it adds DMG +13, dagger and Magic Accuracy skill +17, DEX/AGI/CHR +30, Accuracy and Magic Accuracy +30, Triple Attack 4%, a +30% hidden damage proc every main-hand round (actions.py:371-377) and, given an aftermath level, prime aftermath PDL (create_player.py:568-600). So "IV" overstates any stage below 119 II, matches 119 II and understates 119 III. Ask the player. | 95% |
| Almace | "Almace", "Almace R15" and "(sub)" entries, gear.py:107-110 | Only the 119 III stage (DMG 158, DEX +50, skill 269). No 119 or 119 II entry (DMG 114, DEX +20, skill 242, Magic Accuracy skill 215); the export can't show the stage. "Almace R15 (sub)" keeps the REMA DMG +5, which works in the main hand only (should be 158). | 90% |
| Akademos | "Akademos R15C", gear.py:131 | INT, Magic Accuracy and MAB +15. SCH only, so never in a RDM or BLU run. | 95% |
| Kustawi +1 | "Kustawi +1 R25", gear.py:174 | Labeled R25, but the item only ranks to 15; the values are R15's. RDM and BLU can't equip it. | 95% |

Wrong numbers:

| Item | wsdist entry | Error | Conf. |
|---|---|---|---|
| Bunzi's Rod | "Bunzi's Rod R0", gear.py:102 | DMG 152 (144 + 8); base is 144, +8 is the R15 augment. Affects physical hits only. | 97% |
| Hashishin Kavuk +3 | gear.py:593 | Missing Sword skill +30. On a sword hand already above 600 skill that's 30 Attack and 27 Accuracy short. | 95% |
| Sanctity Necklace | gear.py:653 | No Accuracy key; the necklace has Accuracy +10. | 95% |
| Coiste Bodhar | "Coiste Bodhar R30", gear.py:456 | DEX +5; rank 30 is DEX +10. R0 to R25 are right, so a copy at rank 25 or below is unaffected. | 95% |
| Nyame Flanchard | "Nyame Flanchard R15B", gear.py:1581 | Attack +19, which is R14; R15 is +20. Every other Nyame rank-15 to 30 row on paths A, B and C checks out. | 95% |
| Jhakri Robe +2 | gear.py:903 | Gear Haste 4; the item has Haste +1%. | 97% |
| Gleti's Breeches | "Gleti's Breeches R0", gear.py:1689 | Subtle Blow 8, the R15 value; base has none. The engine never reads Subtle Blow. | 97% |
| Merlinic Crackows | gear.py:1554 | Magic Evasion 116; the item has 118. Unused by the damage code. | 95% |

A different augment roll from the copy checked:

| Item | wsdist entry | wsdist's roll | The copy checked | Conf. |
|---|---|---|---|---|
| Moonshade Earring | gear.py:728 | Accuracy +4, TP Bonus +250 | Attack +4, TP Bonus +250 | 95% |
| Samnuha Tights | gear.py:1363 | STR +10, DEX +10, DA +3%, TA +3% | STR +9, DEX +8, DA +2%, TA +2% | 95% |
| Merlinic Crackows | "(Occult Acumen)", gear.py:1554 | Occult Acumen +11 | Magic Accuracy +35, MAB +30, CHR +9, Enmity -2; wsdist is 35 Magic Accuracy and 30 MAB short for nukes | 95% |
| Merlinic Dastanas | "(Occult Acumen)", gear.py:1086 | Occult Acumen +11 | STR +12, DEX +6, Quad Attack +2%, Accuracy and Attack +11, Magic Accuracy and MAB +18 | 95% |
| Amalric Coif +1 | "Amalric Coif +1A", gear.py:620 | Path A max: Magic Accuracy +20, MAB +20 | Path C below max: INT +11, Elemental and Dark Magic skill +17. wsdist is 20 MAB high and 11 INT low; Magic Accuracy is 3 high on nukes and 20 high on magical weapon skills (no Elemental skill there). Its set-bonus code is right. | 95% |

Engine problems tied to an item (the data is right; editing the dict won't fix them):

| Item | Problem | Conf. |
|---|---|---|
| Gleti's Knife (sub) | Its Crit Rate +5 goes into the shared pool and raises main-hand melee and Chant du Cygne crits (create_player.py:651-675; actions.py:244; weaponskill_info.py:176). Stats match at every rank. | 90% |
| Tauret | The low-TP crit bonus (+50% × (1 - TP/3000)) goes into the crit rate for every hit in a melee round: off hand, Daken, kicks (actions.py:248, 455, 1050-1051). bg-wiki: Tauret's own hits only. Correctly off during weapon skills. | 90% |
| Maxentius | Its burst bonus is a flat Magic Burst Damage 4, which also counts from the sub slot. bg-wiki: main hand only, 4% per skillchain. | 90% |
| Fotia Belt and Gorget | Their accuracy is stored as Weapon Skill Accuracy, added only to physical and ranged weapon skills (actions.py:1759-1760, 2244), never to magical weapon skill magic accuracy. | 85% |
| Carmine +1 set | No set bonus code at all, though gear.py has four Carmine +1 pieces. bg-wiki: Accuracy +20/30/40/50 for 2 to 5 pieces. | 95% |
| Pukulatmuj +1 (enspell) | The random-roll path gives off-hand enspell hits the main hand's Enspell Damage% (actions.py:331). The optimizer's averaged path (actions.py:983-984) is right. | 95% |

Before trusting a wsdist result:

1. Set the target's Magic Evasion (and Magic Defense) for any magic number, and enable at most one Defense Down effect. Replace Distract III's 280 with about 130 to 150 for an NM, by lowering enemy evasion.
2. Swap in the character's actual copies for every item in the four tables above. Select items by Name2 ("Import selections" in the GUI, or a hand-built check_gear headless), never through "Select all File".
3. For Chant du Cygne, Evisceration and crit-heavy TP sets, discount crit rate (the pDIF double count, plus Gleti's Knife pooling). Check a WSD build against the crit build by hand.
4. For dual-wield weapon skills, remember the off-hand hit is too accurate and OA off hands are overrated.
5. Check the BLU spell-set traits and the AF set bonus by hand.
6. Run more than once; the start is random.

### Formulas wsdist adds

wsdist-only items: formulas the research didn't have, each re-checked against bg-wiki.

- **pDIF range** (get_pdif.py:36-67, 106-137). Upper limit: wRatio + 0.5 below 0.5; 1 from 0.5 to 0.7; wRatio + 0.3 from 0.7 to 1.2; 1.25 × wRatio from 1.2 to 1.5; wRatio + 0.375 from 1.5. Lower limit: 0 below 0.38; (1176 × wRatio - 448)/1024 from 0.38 to 1.25; 1 from 1.25 to 1.51; (1176 × wRatio - 755)/1024 from 1.51 to 2.44; wRatio - 0.375 from 2.44. pDIF is uniform between the two, clipped to [0, cap], then × 1.00 to 1.05. bg-wiki: same tables (PDIF, Motenten's model, marked "Verification Needed"). The page notes a later check found wRatio + 0.25 where the table has + 0.3.
- **fSTR** (get_fstr.py:14-30). (dSTR + k)/4 with k = 13 at dSTR -22 or less, 12 at -21 to -16, 10 at -15 to -8, 9 at -7 to -3, 8 at -2 to 0, 7 at 1 to 5, 6 at 6 to 11, 4 at 12 or more. bg-wiki (FSTR): identical.
- **Time per melee round** (get_delay_timing.py:23-30). (Delay1 + Delay2 - Martial Arts) × (1 - DW) × (1 - haste) / 60 seconds, Delay2 = 0 single-wielding, floored at 20% of delay. bg-wiki (Delay): 58.6 to 60.4 delay per second, usually rounded to 60. Its Tactical Points example: two 227-delay weapons with 30% DW is 317.8 delay, about 5.3 s a round. Confirms.
- **Weapon skill forced delay and Regain** (actions.py:115, 135-136, 1002). 2.0 s after each weapon skill; Regain ticks every 3 s. bg-wiki (Forced_Delay, Regain): confirms.
- **Mythic aftermath** (create_player.py:526-560). AM1 and AM2 at 85% of the level 95-119 ranges: Accuracy, Magic Accuracy or MAB about 46, Attack about 90. Tizona: AM1 Accuracy, AM2 Magic Accuracy. Murgleis: AM1 Magic Accuracy, AM2 MAB. AM3: attacks twice 40%, thrice 20%. bg-wiki (Mythic_Aftermath): confirms the ranges (Accuracy, Magic Accuracy and MAB 30-49, Attack 40-99) and AM3. The 85% is wsdist's own choice.
- **Empyrean aftermath** (actions.py:349-355, 1015). AM1/2/3: 30/40/50% chance of triple damage on main-hand melee hits, multi-attack hits included, never on weapon skills. bg-wiki (Empyrean_Aftermath): confirms the rates and the weapon skill exclusion, but the damage is doubled below 119 III and tripled only at 119 III. wsdist always triples.
- **Relic, mythic, empyrean and aeonic weapon skill bonuses** (weapon_bonus.py:33-130). Excalibur Knights of Round +40% (R15 +68%), Mandau Mercy Stroke +40% (R15 +68%), Murgleis Death Blossom +30% (R15 +49.5%), Tizona Expiacion +30% (R15 +49.5%), Almace R15 Chant du Cygne +10%, Sequence R15 Requiescat +10%, Tishtrya R15 Realmrazer +10%. bg-wiki confirms: the R15 augment multiplies the hidden bonus (1.4 × 1.2 = 1.68; 1.3 × 1.15 = 1.495), and one-hand augments work in the main hand only, as wsdist applies them. Also confirmed and already under Weapon bonuses for weapon skills: Naegling Savage Blade +15%, Maxentius Black Halo +50%, Tauret Evisceration +50%, as separate multipliers on every hit.
- **Magic Critical Hit II** (actions.py:330, 1167, 1441, 2316-2358). × (1 + 0.25 × rate) on nukes, enspells and magical weapon skills; Sroda Tathlum and Amin Turban have 10% each. bg-wiki (Magic_Critical_Hit): a proc is × 1.25 on damage spells, enspells and magical weapon skills, separate from Magic Critical Hit I. Confirms.
- **Elemental weapon skill damage +100% (Crocea Mors Path C)** (actions.py:2324; gear.py:132). Multiplies the (152 + floor((weapon level - 99) × 2.45) + WSC) × fTP part, before dSTAT and Magic Damage are added. bg-wiki (Crocea_Mors): same placement. Confirms. It's why the bg-wiki RDM Sanguine Blade set mains Crocea Mors.
- **Enspell base damage** (nuking.py:9-22). Kastra's fit to his own 500-650 skill data: int((skill - 223)/7.70) + 29 below 600, int((skill - 202.5)/8.05) + 29 from 600. That's 64 at 500, 78 at 600, 84 at 650. bg-wiki (Category:Enspell): floor((skill - 180)/8) + 25 above 180 skill, giving 65, 77 and 83. Not confirmed, but within 1 point from 500 to 650; prefer bg-wiki's.
- **Food attack after Attack%** (create_player.py:122-128; gui_main.py:954-957). (8 + skill + STR + flat Attack) × (1 + summed Attack%), then food Attack. Grape Daifuku +1 is entered at its caps (Attack 55, Accuracy 85), which is right whenever attack is at least 500 and accuracy at least 773, always true at 99. bg-wiki doesn't give the order; unconfirmed. If food applied first, Berserk, Warcry and the like would scale the 55 too.
- **Base stats by job** (create_player.py:747-796). Level 99 RDM: STR 90, DEX 90, VIT 87, AGI 87, INT 93, MND 93, CHR 90. BLU: 87 in every stat. Plus a support-job table and Master Level, no race. bg-wiki has race-dependent starting stats but no level 99 job table; unconfirmed. Use the player's /checkparam numbers when a stat margin matters.

Weapon skill data for RDM and BLU (weaponskill_info.py). fTP is interpolated linearly between the 1000, 2000 and 3000 TP values, at TP + TP Bonus clamped to 1000-3000 (weaponskill_info.py:51; actions.py:1648). "Repl." means every hit uses the fTP; otherwise later hits use 1.0. Physical unless an element is given.

| Weapon skill | Who | Hits | fTP 1000/2000/3000 | Repl. | WSC | Other | Lines | bg-wiki |
|---|---|---|---|---|---|---|---|---|
| Savage Blade | RDM, BLU | 2 | 4.0 / 10.25 / 13.75 | no | 50% STR, 50% MND | | 133-139 | agrees |
| Black Halo | RDM, BLU | 2 | 3.0 / 7.25 / 9.75 | no | 70% MND, 30% STR | | 994-1000 | agrees |
| Requiescat | RDM, BLU | 5 | 1.0 | yes | 85% MND (5/5 merits; 73-85%) | Attack -20/-10/0% | 149-167 | agrees |
| Chant du Cygne | RDM, BLU | 3 | 1.6328125 | yes | 80% DEX | Crit +15/25/40% plus gear and dDEX | 174-185 | agrees; crit pDIF bug inflates it |
| Expiacion | BLU (Tizona) | 2 | 3.796875 / 9.390625 / 12.1875 | no | 30% STR, 30% INT, 20% DEX | | 192-198 | agrees |
| Evisceration | RDM | 5 | 1.25 | yes | 50% DEX | Crit +10/25/50% plus gear and dDEX | 396-407 | agrees (2000/3000 crit values unverified) |
| Death Blossom | RDM (Murgleis) | 3 | 4.0 at any TP | no | 50% MND, 30% STR | TP only raises its magic evasion down chance | 186-191 | confirms |
| Knights of Round | RDM (Excalibur) | 1 | 5.0 | no | 40% STR, 40% MND | | 168-173 | confirms |
| Mercy Stroke | RDM (Mandau and others) | 1 | 5.0 | no | 80% STR | | 424-429 | confirms |
| Ruthless Stroke | RDM (Mpu Gandring 119+) | 4 | 5.375 / 14.0 / 23.0 | no | 25% DEX, 25% AGI | | 468-474 | confirms (5.375 tagged for verification) |
| Imperator | RDM, BLU (Caliburnus) | 1 | 3.75 / 7.5 / 11.75 | no | 70% DEX, 70% MND | | 206-212 | differs: 6.6 / 13.35 / 20.1 with 27% DEX, 27% MND, all tagged for verification. Similar totals, but wsdist weighs DEX and MND about 1.5× as much (0.7 × 3.75 vs 0.27 × 6.6). Trust neither for stat priority. |
| Realmrazer | BLU (main job) | 7 | 0.9 | yes | 85% MND (73-85%) | Accuracy +0/20/40 by TP, invented | 1001-1010 | fTP and WSC confirm |
| Judgment | BLU | 1 | 3.5 / 8.75 / 12.0 | no | 50% STR, 50% MND | | 975-981 | confirms |
| Seraph Blade | RDM, BLU | 1, light | 1.125 / 2.625 / 4.125 | no | 40% STR, 40% MND | dSTAT 0 | 107-116 | agrees |
| Red Lotus Blade | RDM, BLU | 1, fire | 1.0 / 2.3828125 / 3.75 | no | 40% STR, 40% INT | dSTAT min(32, dINT/2 + 8) | 87-96 | agrees |
| Sanguine Blade | RDM, BLU | 1, dark | 2.75 at any TP | no | 50% MND, 30% STR | dSTAT 2 × dINT, no cap; no skillchain property | 140-148 | agrees (but no Fotia, see above) |
| Aeolian Edge | RDM | 1, wind | 2.0 / 3.0 / 4.5 | no | 40% DEX, 40% INT | dSTAT min(32, dINT/2 + 8) | 408-417 | agrees |

Vorpal Blade and Flash Nova have no entry; take them from Weapon skill reference (RDM and BLU).

### Sources for wsdist

GitHub:
[IzaKastra/wsdist_beta](https://github.com/IzaKastra/wsdist_beta) at d12ac59 (README.md, requirements.txt, wsdist.py, create_player.py, gui_main.py, actions.py, enemies.py, gear.py, buffs.py, weaponskill_info.py, weapon_bonus.py, nuking.py, get_pdif.py, get_hit_rate.py, get_fstr.py, get_dint_m_v.py, get_delay_timing.py, get_ma_rate.py, item_list.csv; read as text, not run),
[IzaKastra/bg_job_guides](https://github.com/IzaKastra/bg_job_guides) (README.md, main_page.md).

bg-wiki:
[PDIF](https://www.bg-wiki.com/ffxi/PDIF),
[Critical Hit Rate](https://www.bg-wiki.com/ffxi/Critical_Hit_Rate),
[Hit Rate](https://www.bg-wiki.com/ffxi/Hit_Rate),
[Category:Weapon Skills](https://www.bg-wiki.com/ffxi/Category:Weapon_Skills),
[Dual Wield](https://www.bg-wiki.com/ffxi/Dual_Wield),
[TP Bonus](https://www.bg-wiki.com/ffxi/TP_Bonus),
[Category:Multi-Attack](https://www.bg-wiki.com/ffxi/Category:Multi-Attack),
[Double Attack](https://www.bg-wiki.com/ffxi/Double_Attack),
[Mythic Aftermath](https://www.bg-wiki.com/ffxi/Mythic_Aftermath),
[Empyrean Aftermath](https://www.bg-wiki.com/ffxi/Empyrean_Aftermath),
[Defense Down](https://www.bg-wiki.com/ffxi/Defense_Down),
[Distract III](https://www.bg-wiki.com/ffxi/Distract_III),
[Berserk](https://www.bg-wiki.com/ffxi/Berserk),
[Talk:Damage Limit+](https://www.bg-wiki.com/ffxi/Talk:Damage_Limit%2B),
[Tactical Points](https://www.bg-wiki.com/ffxi/Tactical_Points),
[Delay](https://www.bg-wiki.com/ffxi/Delay),
[Forced Delay](https://www.bg-wiki.com/ffxi/Forced_Delay),
[Regain (Status)](https://www.bg-wiki.com/ffxi/Regain_(Status)),
[FSTR](https://www.bg-wiki.com/ffxi/FSTR),
[BGWiki:Ultimate Weapon Augments](https://www.bg-wiki.com/ffxi/BGWiki:Ultimate_Weapon_Augments),
[Magic Hit Rate](https://www.bg-wiki.com/ffxi/Magic_Hit_Rate),
[Resist](https://www.bg-wiki.com/ffxi/Resist),
[Magic Burst](https://www.bg-wiki.com/ffxi/Magic_Burst),
[Magic Damage](https://www.bg-wiki.com/ffxi/Magic_Damage),
[Weapon Skill Damage](https://www.bg-wiki.com/ffxi/Weapon_Skill_Damage),
[Category:Elemental Weapon Skill](https://www.bg-wiki.com/ffxi/Category:Elemental_Weapon_Skill),
[Magic Critical Hit](https://www.bg-wiki.com/ffxi/Magic_Critical_Hit),
[Category:Enspell](https://www.bg-wiki.com/ffxi/Category:Enspell),
[Klimaform](https://www.bg-wiki.com/ffxi/Klimaform),
[Category:Reforged Artifact Armor +3](https://www.bg-wiki.com/ffxi/Category:Reforged_Artifact_Armor_%2B3),
[Blue Mage](https://www.bg-wiki.com/ffxi/Blue_Mage),
[Fotia Gorget](https://www.bg-wiki.com/ffxi/Fotia_Gorget),
[Fotia Belt](https://www.bg-wiki.com/ffxi/Fotia_Belt),
[Imperator](https://www.bg-wiki.com/ffxi/Imperator),
[Realmrazer](https://www.bg-wiki.com/ffxi/Realmrazer),
[Crocea Mors](https://www.bg-wiki.com/ffxi/Crocea_Mors),
[Tauret](https://www.bg-wiki.com/ffxi/Tauret),
[Maxentius](https://www.bg-wiki.com/ffxi/Maxentius),
[Carmine Armor Set](https://www.bg-wiki.com/ffxi/Carmine_Armor_Set),
[Nolan](https://www.bg-wiki.com/ffxi/Nolan),
and the item pages named in the data-error tables.

## Sources

bg-wiki, read directly:
[Acad. Loafers +3](https://www.bg-wiki.com/ffxi/Acad._Loafers_%2B3),
[Accession](https://www.bg-wiki.com/ffxi/Accession),
[Accuracy](https://www.bg-wiki.com/ffxi/Accuracy),
[Accuracy Bonus](https://www.bg-wiki.com/ffxi/Accuracy_Bonus),
[Addle](https://www.bg-wiki.com/ffxi/Addle),
[Addle II](https://www.bg-wiki.com/ffxi/Addle_II),
[Adhemar Jacket +1](https://www.bg-wiki.com/ffxi/Adhemar_Jacket_%2B1),
[Aeolian Edge](https://www.bg-wiki.com/ffxi/Aeolian_Edge),
[Aggressor](https://www.bg-wiki.com/ffxi/Aggressor),
[Akademos](https://www.bg-wiki.com/ffxi/Akademos),
[All Jobs Gear Sets](https://www.bg-wiki.com/ffxi/All_Jobs_Gear_Sets),
[All Jobs Gear Sets/Blue Mage](https://www.bg-wiki.com/ffxi/All_Jobs_Gear_Sets/Blue_Mage),
[All Jobs Gear Sets/Red Mage](https://www.bg-wiki.com/ffxi/All_Jobs_Gear_Sets/Red_Mage),
[Almace (Level 119 II)](https://www.bg-wiki.com/ffxi/Almace_(Level_119_II)),
[Almace (Level 119 III)](https://www.bg-wiki.com/ffxi/Almace_(Level_119_III)),
[Almace (Level 119)](https://www.bg-wiki.com/ffxi/Almace_(Level_119)),
[Amalric Coif +1](https://www.bg-wiki.com/ffxi/Amalric_Coif_%2B1),
[Ammurapi Shield](https://www.bg-wiki.com/ffxi/Ammurapi_Shield),
[Anvil Lightning](https://www.bg-wiki.com/ffxi/Anvil_Lightning),
[Aquaveil](https://www.bg-wiki.com/ffxi/Aquaveil),
[Archduke's Shield](https://www.bg-wiki.com/ffxi/Archduke%27s_Shield),
[Archon Ring](https://www.bg-wiki.com/ffxi/Archon_Ring),
[Aria of Passion](https://www.bg-wiki.com/ffxi/Aria_of_Passion),
[Assim. Bazu. +3](https://www.bg-wiki.com/ffxi/Assim._Bazu._%2B3),
[Assimilator's Attire Set](https://www.bg-wiki.com/ffxi/Assimilator%27s_Attire_Set),
[Atra. Libations](https://www.bg-wiki.com/ffxi/Atra._Libations),
[Atro. Chapeau +4](https://www.bg-wiki.com/ffxi/Atro._Chapeau_%2B4),
[Atro. Gloves +4](https://www.bg-wiki.com/ffxi/Atro._Gloves_%2B4),
[Atrophy Armor Set](https://www.bg-wiki.com/ffxi/Atrophy_Armor_Set),
[Atrophy Armor Set +4](https://www.bg-wiki.com/ffxi/Atrophy_Armor_Set_%2B4),
[Atrophy Tabard +4](https://www.bg-wiki.com/ffxi/Atrophy_Tabard_%2B4),
[Attack](https://www.bg-wiki.com/ffxi/Attack),
[Attack Bonus](https://www.bg-wiki.com/ffxi/Attack_Bonus),
[Attack Speed](https://www.bg-wiki.com/ffxi/Attack_Speed),
[Auge Saber](https://www.bg-wiki.com/ffxi/Auge_Saber),
[Augur's Gaiters](https://www.bg-wiki.com/ffxi/Augur%27s_Gaiters),
[Azure Lore](https://www.bg-wiki.com/ffxi/Azure_Lore),
[Azure Tomes: Blue Magic Guide by Sabishii](https://www.bg-wiki.com/ffxi/Azure_Tomes:_Blue_Magic_Guide_by_Sabishii),
[Bad Breath](https://www.bg-wiki.com/ffxi/Bad_Breath),
[Barrier Tusk](https://www.bg-wiki.com/ffxi/Barrier_Tusk),
[Berserk](https://www.bg-wiki.com/ffxi/Berserk),
[BGWiki:SongPotency](https://www.bg-wiki.com/ffxi/BGWiki:SongPotency),
[BGWiki:Ultimate Weapon Augments](https://www.bg-wiki.com/ffxi/BGWiki:Ultimate_Weapon_Augments),
[Bind](https://www.bg-wiki.com/ffxi/Bind),
[Black Halo](https://www.bg-wiki.com/ffxi/Black_Halo),
[Blind](https://www.bg-wiki.com/ffxi/Blind),
[Blind II](https://www.bg-wiki.com/ffxi/Blind_II),
[Blinding Fulgor](https://www.bg-wiki.com/ffxi/Blinding_Fulgor),
[Blink](https://www.bg-wiki.com/ffxi/Blink),
[Blue Mage](https://www.bg-wiki.com/ffxi/Blue_Mage),
[Blue Mage Job Traits](https://www.bg-wiki.com/ffxi/Blue_Mage_Job_Traits),
[Bolelabunga](https://www.bg-wiki.com/ffxi/Bolelabunga),
[Boxer's Mantle](https://www.bg-wiki.com/ffxi/Boxer%27s_Mantle),
[Break](https://www.bg-wiki.com/ffxi/Break),
[Buckler Earring](https://www.bg-wiki.com/ffxi/Buckler_Earring),
[Bunzi's Gloves](https://www.bg-wiki.com/ffxi/Bunzi%27s_Gloves),
[Bunzi's Hat](https://www.bg-wiki.com/ffxi/Bunzi%27s_Hat),
[Bunzi's Pants](https://www.bg-wiki.com/ffxi/Bunzi%27s_Pants),
[Bunzi's Robe](https://www.bg-wiki.com/ffxi/Bunzi%27s_Robe),
[Bunzi's Rod](https://www.bg-wiki.com/ffxi/Bunzi%27s_Rod),
[Bunzi's Sabots](https://www.bg-wiki.com/ffxi/Bunzi%27s_Sabots),
[Burst Affinity](https://www.bg-wiki.com/ffxi/Burst_Affinity),
[Byrth's WS Damage Guide](https://www.bg-wiki.com/ffxi/Byrth%27s_WS_Damage_Guide),
[Calculating Blue Magic Damage](https://www.bg-wiki.com/ffxi/Calculating_Blue_Magic_Damage),
[Carapacho Cuffs](https://www.bg-wiki.com/ffxi/Carapacho_Cuffs),
[Carmine Armor Set](https://www.bg-wiki.com/ffxi/Carmine_Armor_Set),
[Casting Time Gauge](https://www.bg-wiki.com/ffxi/Casting_Time_Gauge),
[Category:Accuracy Food](https://www.bg-wiki.com/ffxi/Category:Accuracy_Food),
[Category:Alluvion Skirmish Armor](https://www.bg-wiki.com/ffxi/Category:Alluvion_Skirmish_Armor),
[Category:Barspell](https://www.bg-wiki.com/ffxi/Category:Barspell),
[Category:Blue Magic](https://www.bg-wiki.com/ffxi/Category:Blue_Magic),
[Category:Boost Spell](https://www.bg-wiki.com/ffxi/Category:Boost_Spell),
[Category:Combat Skills](https://www.bg-wiki.com/ffxi/Category:Combat_Skills),
[Category:Cure Spell](https://www.bg-wiki.com/ffxi/Category:Cure_Spell),
[Category:Dark Magic](https://www.bg-wiki.com/ffxi/Category:Dark_Magic),
[Category:Divine Magic](https://www.bg-wiki.com/ffxi/Category:Divine_Magic),
[Category:Elemental Belts](https://www.bg-wiki.com/ffxi/Category:Elemental_Belts),
[Category:Elemental Gorgets](https://www.bg-wiki.com/ffxi/Category:Elemental_Gorgets),
[Category:Elemental Magic](https://www.bg-wiki.com/ffxi/Category:Elemental_Magic),
[Category:Elemental Obi](https://www.bg-wiki.com/ffxi/Category:Elemental_Obi),
[Category:Elemental Staves](https://www.bg-wiki.com/ffxi/Category:Elemental_Staves),
[Category:Elemental Weapon Skill](https://www.bg-wiki.com/ffxi/Category:Elemental_Weapon_Skill),
[Category:Enfeebling Magic](https://www.bg-wiki.com/ffxi/Category:Enfeebling_Magic),
[Category:Enhancing Magic](https://www.bg-wiki.com/ffxi/Category:Enhancing_Magic),
[Category:Enspell](https://www.bg-wiki.com/ffxi/Category:Enspell),
[Category:FTP Replicating WS](https://www.bg-wiki.com/ffxi/Category:FTP_Replicating_WS),
[Category:Gain Spell](https://www.bg-wiki.com/ffxi/Category:Gain_Spell),
[Category:Healing Magic](https://www.bg-wiki.com/ffxi/Category:Healing_Magic),
[Category:JSE Necks](https://www.bg-wiki.com/ffxi/Category:JSE_Necks),
[Category:Madrigal](https://www.bg-wiki.com/ffxi/Category:Madrigal),
[Category:Magic Accuracy Food](https://www.bg-wiki.com/ffxi/Category:Magic_Accuracy_Food),
[Category:Multi-Attack](https://www.bg-wiki.com/ffxi/Category:Multi-Attack),
[Category:Protect Spell](https://www.bg-wiki.com/ffxi/Category:Protect_Spell),
[Category:Reforged Artifact Armor +3](https://www.bg-wiki.com/ffxi/Category:Reforged_Artifact_Armor_%2B3),
[Category:Regen Spell](https://www.bg-wiki.com/ffxi/Category:Regen_Spell),
[Category:Shell Spell](https://www.bg-wiki.com/ffxi/Category:Shell_Spell),
[Category:Sword](https://www.bg-wiki.com/ffxi/Category:Sword),
[Category:Weapon Skills](https://www.bg-wiki.com/ffxi/Category:Weapon_Skills),
[Celerity](https://www.bg-wiki.com/ffxi/Celerity),
[Chain Affinity](https://www.bg-wiki.com/ffxi/Chain_Affinity),
[Chainspell](https://www.bg-wiki.com/ffxi/Chainspell),
[Chant du Cygne](https://bg-wiki.com/bg/Chant_du_Cygne),
[Chelona Boots](https://www.bg-wiki.com/ffxi/Chelona_Boots),
[Chironic Hose](https://www.bg-wiki.com/ffxi/Chironic_Hose),
[Coiste Bodhar](https://www.bg-wiki.com/ffxi/Coiste_Bodhar),
[Colada](https://www.bg-wiki.com/ffxi/Colada),
[Combatant's Torque](https://www.bg-wiki.com/ffxi/Combatant%27s_Torque),
[Community Blue Mage Guide](https://www.bg-wiki.com/ffxi/Community_Blue_Mage_Guide),
[Community Red Mage Guide](https://www.bg-wiki.com/ffxi/Community_Red_Mage_Guide),
[Community Scholar Guide](https://www.bg-wiki.com/ffxi/Community_Scholar_Guide),
[Composure](https://www.bg-wiki.com/ffxi/Composure),
[Convergence](https://www.bg-wiki.com/ffxi/Convergence),
[Crepuscular Pebble](https://www.bg-wiki.com/ffxi/Crepuscular_Pebble),
[Crit. Atk. Bonus](https://www.bg-wiki.com/ffxi/Crit._Atk._Bonus),
[Critical Hit Rate](https://www.bg-wiki.com/ffxi/Critical_Hit_Rate),
[Crocea Mors](https://www.bg-wiki.com/ffxi/Crocea_Mors),
[Cure Formula](https://www.bg-wiki.com/ffxi/Cure_Formula),
[Cure IV](https://www.bg-wiki.com/ffxi/Cure_IV),
[Daduchos Saber](https://www.bg-wiki.com/ffxi/Daduchos_Saber),
[Damage Limit+](https://www.bg-wiki.com/ffxi/Damage_Limit%2B),
[Damage Taken](https://www.bg-wiki.com/ffxi/Damage_Taken),
[Dark Arts](https://www.bg-wiki.com/ffxi/Dark_Arts),
[Days of the Week](https://www.bg-wiki.com/ffxi/Days_of_the_Week),
[Death Blossom](https://www.bg-wiki.com/ffxi/Death_Blossom),
[Defense Down](https://www.bg-wiki.com/ffxi/Defense_Down),
[Delay](https://www.bg-wiki.com/ffxi/Delay),
[Demers. Degen +1](https://www.bg-wiki.com/ffxi/Demers._Degen_%2B1),
[Dexterity](https://www.bg-wiki.com/ffxi/Dexterity),
[Dia](https://www.bg-wiki.com/ffxi/Dia),
[Dia II](https://www.bg-wiki.com/ffxi/Dia_II),
[Dia III](https://www.bg-wiki.com/ffxi/Dia_III),
[Diamondhide](https://www.bg-wiki.com/ffxi/Diamondhide),
[Diffusion](https://www.bg-wiki.com/ffxi/Diffusion),
[Diffusion Ray](https://www.bg-wiki.com/ffxi/Diffusion_Ray),
[Dispel](https://www.bg-wiki.com/ffxi/Dispel),
[Distract](https://www.bg-wiki.com/ffxi/Distract),
[Distract II](https://www.bg-wiki.com/ffxi/Distract_II),
[Distract III](https://www.bg-wiki.com/ffxi/Distract_III),
[Dls. Torque +1](https://www.bg-wiki.com/ffxi/Dls._Torque_%2B1),
[Dls. Torque +2](https://www.bg-wiki.com/ffxi/Dls._Torque_%2B2),
[Double Attack](https://www.bg-wiki.com/ffxi/Double_Attack),
[Doyen Pants](https://www.bg-wiki.com/ffxi/Doyen_Pants),
[Dual Wield](https://www.bg-wiki.com/ffxi/Dual_Wield),
[Duelist's Torque](https://www.bg-wiki.com/ffxi/Duelist%27s_Torque),
[Eabani Earring](https://www.bg-wiki.com/ffxi/Eabani_Earring),
[Earthcry Earring](https://www.bg-wiki.com/ffxi/Earthcry_Earring),
[Efflux](https://www.bg-wiki.com/ffxi/Efflux),
[Elemental Celerity](https://www.bg-wiki.com/ffxi/Elemental_Celerity),
[Empyrean Aftermath](https://www.bg-wiki.com/ffxi/Empyrean_Aftermath),
[Entomb](https://www.bg-wiki.com/ffxi/Entomb),
[Ephramad's Ring](https://www.bg-wiki.com/ffxi/Ephramad%27s_Ring),
[Erratic Flutter](https://www.bg-wiki.com/ffxi/Erratic_Flutter),
[Estq. Earring](https://www.bg-wiki.com/ffxi/Estq._Earring),
[Estq. Ganthrt. +1](https://www.bg-wiki.com/ffxi/Estq._Ganthrt._%2B1),
[Estq. Ganthrt. +2](https://www.bg-wiki.com/ffxi/Estq._Ganthrt._%2B2),
[Eurus' Ledelsens](https://www.bg-wiki.com/ffxi/Eurus%27_Ledelsens),
[Evasion](https://www.bg-wiki.com/ffxi/Evasion),
[Evasion Skill](https://www.bg-wiki.com/ffxi/Evasion_Skill),
[Evisceration](https://www.bg-wiki.com/ffxi/Evisceration),
[Expiacion](https://www.bg-wiki.com/ffxi/Expiacion),
[Fast Cast](https://www.bg-wiki.com/ffxi/Fast_Cast),
[Fi Follet Cape +1](https://www.bg-wiki.com/ffxi/Fi_Follet_Cape_%2B1),
[Flash Nova](https://www.bg-wiki.com/ffxi/Flash_Nova),
[Flurry II](https://www.bg-wiki.com/ffxi/Flurry_II),
[Flying Hip Press](https://www.bg-wiki.com/ffxi/Flying_Hip_Press),
[Forced Delay](https://www.bg-wiki.com/ffxi/Forced_Delay),
[Forfend +1](https://www.bg-wiki.com/ffxi/Forfend_%2B1),
[Fotia Belt](https://www.bg-wiki.com/ffxi/Fotia_Belt),
[Fotia Gorget](https://www.bg-wiki.com/ffxi/Fotia_Gorget),
[Frazzle](https://www.bg-wiki.com/ffxi/Frazzle),
[Frazzle II](https://www.bg-wiki.com/ffxi/Frazzle_II),
[Frazzle III](https://www.bg-wiki.com/ffxi/Frazzle_III),
[Frost Breath](https://www.bg-wiki.com/ffxi/Frost_Breath),
[FSTR](https://www.bg-wiki.com/ffxi/FSTR),
[Gada](https://www.bg-wiki.com/ffxi/Gada),
[Genbu's Shield](https://www.bg-wiki.com/ffxi/Genbu%27s_Shield),
[Ghostfyre Cape](https://www.bg-wiki.com/ffxi/Ghostfyre_Cape),
[Gleti's Armor Set](https://www.bg-wiki.com/ffxi/Gleti%27s_Armor_Set),
[Gleti's Breeches](https://www.bg-wiki.com/ffxi/Gleti%27s_Breeches),
[Gleti's Cuirass](https://www.bg-wiki.com/ffxi/Gleti%27s_Cuirass),
[Gleti's Gauntlets](https://www.bg-wiki.com/ffxi/Gleti%27s_Gauntlets),
[Gleti's Knife](https://www.bg-wiki.com/ffxi/Gleti%27s_Knife),
[Grapevine Cape](https://www.bg-wiki.com/ffxi/Grapevine_Cape),
[Gravity](https://www.bg-wiki.com/ffxi/Gravity),
[Gravity II](https://www.bg-wiki.com/ffxi/Gravity_II),
[Guard Skill](https://www.bg-wiki.com/ffxi/Guard_Skill),
[Hachirin-no-Obi](https://www.bg-wiki.com/ffxi/Hachirin-no-Obi),
[Hashi. Earring +1](https://www.bg-wiki.com/ffxi/Hashi._Earring_%2B1),
[Hashishin Attire Set](https://www.bg-wiki.com/ffxi/Hashishin_Attire_Set),
[Hashishin Kavuk +3](https://www.bg-wiki.com/ffxi/Hashishin_Kavuk_%2B3),
[Hashishin Mintan](https://www.bg-wiki.com/ffxi/Hashishin_Mintan),
[Hashishin Mintan +3](https://www.bg-wiki.com/ffxi/Hashishin_Mintan_%2B3),
[Haste II](https://www.bg-wiki.com/ffxi/Haste_II),
[Haste Samba](https://www.bg-wiki.com/ffxi/Haste_Samba),
[Haste: In Depth by Kirschy](https://www.bg-wiki.com/ffxi/Haste:_In_Depth_by_Kirschy),
[Haven Hose](https://www.bg-wiki.com/ffxi/Haven_Hose),
[Haverton Ring](https://www.bg-wiki.com/ffxi/Haverton_Ring),
[Haverton Ring +1](https://www.bg-wiki.com/ffxi/Haverton_Ring_%2B1),
[Healing Breeze](https://www.bg-wiki.com/ffxi/Healing_Breeze),
[Heat Breath](https://www.bg-wiki.com/ffxi/Heat_Breath),
[Hecatomb Wave](https://www.bg-wiki.com/ffxi/Hecatomb_Wave),
[Hit Rate](https://www.bg-wiki.com/ffxi/Hit_Rate),
[Hoxne Earring](https://www.bg-wiki.com/ffxi/Hoxne_Earring),
[Hoxne Torque](https://www.bg-wiki.com/ffxi/Hoxne_Torque),
[Imperator](https://www.bg-wiki.com/ffxi/Imperator),
[Inquartata](https://www.bg-wiki.com/ffxi/Inquartata),
[Intelligence](https://www.bg-wiki.com/ffxi/Intelligence),
[Inundation](https://www.bg-wiki.com/ffxi/Inundation),
[Item Level](https://www.bg-wiki.com/ffxi/Item_Level),
[Jhakri Ring](https://www.bg-wiki.com/ffxi/Jhakri_Ring),
[Jhakri Robe +2](https://www.bg-wiki.com/ffxi/Jhakri_Robe_%2B2),
[Job Points](https://www.bg-wiki.com/ffxi/Job_Points),
[Kentarch Belt +1](https://www.bg-wiki.com/ffxi/Kentarch_Belt_%2B1),
[Kishar Ring](https://www.bg-wiki.com/ffxi/Kishar_Ring),
[Klimaform](https://www.bg-wiki.com/ffxi/Klimaform),
[Kustawi +1](https://www.bg-wiki.com/ffxi/Kustawi_%2B1),
[Leth. Earring +1](https://www.bg-wiki.com/ffxi/Leth._Earring_%2B1),
[Leth. Fuseau +3](https://www.bg-wiki.com/ffxi/Leth._Fuseau_%2B3),
[Leth. Ganth. +3](https://www.bg-wiki.com/ffxi/Leth._Ganth._%2B3),
[Leth. Houseaux +3](https://www.bg-wiki.com/ffxi/Leth._Houseaux_%2B3),
[Lethargy Armor Set](https://www.bg-wiki.com/ffxi/Lethargy_Armor_Set),
[Lethargy Sayon +3](https://www.bg-wiki.com/ffxi/Lethargy_Sayon_%2B3),
[Level Difference Penalty](https://www.bg-wiki.com/ffxi/Level_Difference_Penalty),
[Light Arts](https://www.bg-wiki.com/ffxi/Light_Arts),
[Luhlaza Attire Set](https://www.bg-wiki.com/ffxi/Luhlaza_Attire_Set),
[Luhlaza Jubbah +1](https://www.bg-wiki.com/ffxi/Luhlaza_Jubbah_%2B1),
[Mag. Burst Bonus](https://www.bg-wiki.com/ffxi/Mag._Burst_Bonus),
[Magic Accuracy](https://www.bg-wiki.com/ffxi/Magic_Accuracy),
[Magic Accuracy Skill](https://www.bg-wiki.com/ffxi/Magic_Accuracy_Skill),
[Magic Affinity](https://www.bg-wiki.com/ffxi/Magic_Affinity),
[Magic Attack Bonus](https://www.bg-wiki.com/ffxi/Magic_Attack_Bonus),
[Magic Barrier](https://www.bg-wiki.com/ffxi/Magic_Barrier),
[Magic Burst](https://www.bg-wiki.com/ffxi/Magic_Burst),
[Magic Critical Hit](https://www.bg-wiki.com/ffxi/Magic_Critical_Hit),
[Magic Damage](https://www.bg-wiki.com/ffxi/Magic_Damage),
[Magic Damage (Statistic)](https://www.bg-wiki.com/ffxi/Magic_Damage_(Statistic)),
[Magic Defense Bonus](https://www.bg-wiki.com/ffxi/Magic_Defense_Bonus),
[Magic Evasion](https://www.bg-wiki.com/ffxi/Magic_Evasion),
[Magic Fruit](https://www.bg-wiki.com/ffxi/Magic_Fruit),
[Magic Hammer](https://www.bg-wiki.com/ffxi/Magic_Hammer),
[Magic Hit Rate](https://www.bg-wiki.com/ffxi/Magic_Hit_Rate),
[Magnetite Cloud](https://www.bg-wiki.com/ffxi/Magnetite_Cloud),
[Malignance Attire Set](https://www.bg-wiki.com/ffxi/Malignance_Attire_Set),
[Malignance Sword](https://www.bg-wiki.com/ffxi/Malignance_Sword),
[Marin Staff +1](https://www.bg-wiki.com/ffxi/Marin_Staff_%2B1),
[Master Levels](https://www.bg-wiki.com/ffxi/Master_Levels),
[Maxentius](https://www.bg-wiki.com/ffxi/Maxentius),
[Mendi. Earring](https://www.bg-wiki.com/ffxi/Mendi._Earring),
[Merit Points](https://www.bg-wiki.com/ffxi/Merit_Points),
[Merlinic Crackows](https://www.bg-wiki.com/ffxi/Merlinic_Crackows),
[Merlinic Dastanas](https://www.bg-wiki.com/ffxi/Merlinic_Dastanas),
[Metallic Body](https://www.bg-wiki.com/ffxi/Metallic_Body),
[Mighty Guard](https://www.bg-wiki.com/ffxi/Mighty_Guard),
[Mirage Keffiyeh](https://www.bg-wiki.com/ffxi/Mirage_Keffiyeh),
[Moonshade Earring](https://www.bg-wiki.com/ffxi/Moonshade_Earring),
[Mpu Gandring (Incomplete)](https://www.bg-wiki.com/ffxi/Mpu_Gandring_(Incomplete)),
[Mpu Gandring (Level 119 II)](https://www.bg-wiki.com/ffxi/Mpu_Gandring_(Level_119_II)),
[Mpu Gandring (Level 119 III)](https://www.bg-wiki.com/ffxi/Mpu_Gandring_(Level_119_III)),
[Mythic Aftermath](https://www.bg-wiki.com/ffxi/Mythic_Aftermath),
[Naegling](https://www.bg-wiki.com/ffxi/Naegling),
[Nat. Meditation](https://www.bg-wiki.com/ffxi/Nat._Meditation),
[Naturalist's Roll](https://www.bg-wiki.com/ffxi/Naturalist%27s_Roll),
[Nodens Gorget](https://www.bg-wiki.com/ffxi/Nodens_Gorget),
[Nolan](https://www.bg-wiki.com/ffxi/Nolan),
[Nyame Armor Set](https://www.bg-wiki.com/ffxi/Nyame_Armor_Set),
[Nyame Flanchard](https://www.bg-wiki.com/ffxi/Nyame_Flanchard),
[Nyame Gauntlets](https://www.bg-wiki.com/ffxi/Nyame_Gauntlets),
[Nyame Helm](https://www.bg-wiki.com/ffxi/Nyame_Helm),
[Nyame Mail](https://www.bg-wiki.com/ffxi/Nyame_Mail),
[Nyame Sollerets](https://www.bg-wiki.com/ffxi/Nyame_Sollerets),
[Obstin. Sash](https://www.bg-wiki.com/ffxi/Obstin._Sash),
[Occasionally Quickens Spellcasting](https://www.bg-wiki.com/ffxi/Occasionally_Quickens_Spellcasting),
[Occultation](https://www.bg-wiki.com/ffxi/Occultation),
[Oden](https://www.bg-wiki.com/ffxi/Oden),
[Orpheus's Sash](https://www.bg-wiki.com/ffxi/Orpheus%27s_Sash),
[Pahtli Cape](https://www.bg-wiki.com/ffxi/Pahtli_Cape),
[Paralyze](https://www.bg-wiki.com/ffxi/Paralyze),
[Paralyze II](https://www.bg-wiki.com/ffxi/Paralyze_II),
[Parrying Skill](https://www.bg-wiki.com/ffxi/Parrying_Skill),
[PDIF](https://www.bg-wiki.com/ffxi/PDIF),
[Peda. M.Board +3](https://www.bg-wiki.com/ffxi/Peda._M.Board_%2B3),
[Perpetuance](https://www.bg-wiki.com/ffxi/Perpetuance),
[Phalanx](https://www.bg-wiki.com/ffxi/Phalanx),
[Phalanx (Status)](https://www.bg-wiki.com/ffxi/Phalanx_(Status)),
[Phalanx II](https://www.bg-wiki.com/ffxi/Phalanx_II),
[Pixie Hairpin +1](https://www.bg-wiki.com/ffxi/Pixie_Hairpin_%2B1),
[Plenilune Embrace](https://www.bg-wiki.com/ffxi/Plenilune_Embrace),
[Poison](https://www.bg-wiki.com/ffxi/Poison),
[Poison Breath](https://www.bg-wiki.com/ffxi/Poison_Breath),
[Poison II](https://www.bg-wiki.com/ffxi/Poison_II),
[Pollen](https://www.bg-wiki.com/ffxi/Pollen),
[Prime Aftermath](https://www.bg-wiki.com/ffxi/Prime_Aftermath),
[Pukulatmuj](https://www.bg-wiki.com/ffxi/Pukulatmuj),
[Pukulatmuj +1](https://www.bg-wiki.com/ffxi/Pukulatmuj_%2B1),
[Quadruple Attack](https://www.bg-wiki.com/ffxi/Quadruple_Attack),
[Querkening Brais](https://www.bg-wiki.com/ffxi/Querkening_Brais),
[Radiant Breath](https://www.bg-wiki.com/ffxi/Radiant_Breath),
[Rail Cannon](https://www.bg-wiki.com/ffxi/Rail_Cannon),
[Realmrazer](https://www.bg-wiki.com/ffxi/Realmrazer),
[Red Lotus Blade](https://www.bg-wiki.com/ffxi/Red_Lotus_Blade),
[Red Mage](https://www.bg-wiki.com/ffxi/Red_Mage),
[Refresh](https://www.bg-wiki.com/ffxi/Refresh),
[Refresh III](https://www.bg-wiki.com/ffxi/Refresh_III),
[Regain (Status)](https://www.bg-wiki.com/ffxi/Regain_(Status)),
[Regal Belt](https://www.bg-wiki.com/ffxi/Regal_Belt),
[Regal Cuffs](https://www.bg-wiki.com/ffxi/Regal_Cuffs),
[Regal Earring](https://www.bg-wiki.com/ffxi/Regal_Earring),
[Regal Gem](https://www.bg-wiki.com/ffxi/Regal_Gem),
[Regal Ring](https://www.bg-wiki.com/ffxi/Regal_Ring),
[Regen II](https://www.bg-wiki.com/ffxi/Regen_II),
[Reiki Yotai](https://www.bg-wiki.com/ffxi/Reiki_Yotai),
[Requiescat](https://www.bg-wiki.com/ffxi/Requiescat),
[Resist](https://www.bg-wiki.com/ffxi/Resist),
[Restoral](https://www.bg-wiki.com/ffxi/Restoral),
[Rosmerta's Cape](https://www.bg-wiki.com/ffxi/Rosmerta%27s_Cape),
[Saboteur](https://www.bg-wiki.com/ffxi/Saboteur),
[Sakpata's Sword](https://www.bg-wiki.com/ffxi/Sakpata%27s_Sword),
[Samnuha Tights](https://www.bg-wiki.com/ffxi/Samnuha_Tights),
[Sanctity Necklace](https://www.bg-wiki.com/ffxi/Sanctity_Necklace),
[Sanguine Blade](https://www.bg-wiki.com/ffxi/Sanguine_Blade),
[Sarashi](https://www.bg-wiki.com/ffxi/Sarashi),
[Savage Blade](https://www.bg-wiki.com/ffxi/Savage_Blade),
[Scouring Spate](https://www.bg-wiki.com/ffxi/Scouring_Spate),
[Searing Tempest](https://www.bg-wiki.com/ffxi/Searing_Tempest),
[Self-Destruct](https://www.bg-wiki.com/ffxi/Self-Destruct),
[Seraph Blade](https://www.bg-wiki.com/ffxi/Seraph_Blade),
[Serenity](https://www.bg-wiki.com/ffxi/Serenity),
[Shedir Seraweels](https://www.bg-wiki.com/ffxi/Shedir_Seraweels),
[Shetal Stone](https://www.bg-wiki.com/ffxi/Shetal_Stone),
[Shield Def. Bonus](https://www.bg-wiki.com/ffxi/Shield_Def._Bonus),
[Shield Mastery](https://www.bg-wiki.com/ffxi/Shield_Mastery),
[Shield Skill](https://www.bg-wiki.com/ffxi/Shield_Skill),
[Siegel Sash](https://www.bg-wiki.com/ffxi/Siegel_Sash),
[Silence](https://www.bg-wiki.com/ffxi/Silence),
[Silent Storm](https://www.bg-wiki.com/ffxi/Silent_Storm),
[Skill Caps/Blue Mage](https://www.bg-wiki.com/ffxi/Skill_Caps/Blue_Mage),
[Skill Caps/Red Mage](https://www.bg-wiki.com/ffxi/Skill_Caps/Red_Mage),
[Sleep](https://www.bg-wiki.com/ffxi/Sleep),
[Sleep II](https://www.bg-wiki.com/ffxi/Sleep_II),
[Slow](https://www.bg-wiki.com/ffxi/Slow),
[Slow II](https://www.bg-wiki.com/ffxi/Slow_II),
[Snapshot](https://www.bg-wiki.com/ffxi/Snapshot),
[Sneak](https://www.bg-wiki.com/ffxi/Sneak),
[Snotra Earring](https://www.bg-wiki.com/ffxi/Snotra_Earring),
[Song Spellcasting Time](https://www.bg-wiki.com/ffxi/Song_Spellcasting_Time),
[Spectral Floe](https://www.bg-wiki.com/ffxi/Spectral_Floe),
[Spell Interruption Rate](https://www.bg-wiki.com/ffxi/Spell_Interruption_Rate),
[Spell Recast](https://www.bg-wiki.com/ffxi/Spell_Recast),
[Spontaneity](https://www.bg-wiki.com/ffxi/Spontaneity),
[Sroda Necklace](https://www.bg-wiki.com/ffxi/Sroda_Necklace),
[Sroda Ring](https://www.bg-wiki.com/ffxi/Sroda_Ring),
[Stone Gorget](https://www.bg-wiki.com/ffxi/Stone_Gorget),
[Stone Mufflers](https://www.bg-wiki.com/ffxi/Stone_Mufflers),
[Stoneskin](https://www.bg-wiki.com/ffxi/Stoneskin),
[Store TP](https://www.bg-wiki.com/ffxi/Store_TP),
[Stymie](https://www.bg-wiki.com/ffxi/Stymie),
[Subduction](https://www.bg-wiki.com/ffxi/Subduction),
[Subtle Blow](https://www.bg-wiki.com/ffxi/Subtle_Blow),
[Sucellos's Cape](https://www.bg-wiki.com/ffxi/Sucellos%27s_Cape),
[Sudden Lunge](https://www.bg-wiki.com/ffxi/Sudden_Lunge),
[Suppanomimi](https://www.bg-wiki.com/ffxi/Suppanomimi),
[Support Job](https://www.bg-wiki.com/ffxi/Support_Job),
[Swith Cape](https://www.bg-wiki.com/ffxi/Swith_Cape),
[Tactical Points](https://www.bg-wiki.com/ffxi/Tactical_Points),
[Talk:Aquaveil](https://www.bg-wiki.com/ffxi/Talk:Aquaveil),
[Talk:Community Red Mage Guide](https://www.bg-wiki.com/ffxi/Talk:Community_Red_Mage_Guide),
[Talk:Damage Limit+](https://www.bg-wiki.com/ffxi/Talk:Damage_Limit%2B),
[Talk:Distract III](https://www.bg-wiki.com/ffxi/Talk:Distract_III),
[Talk:Inundation](https://www.bg-wiki.com/ffxi/Talk:Inundation),
[Talk:PDIF](https://www.bg-wiki.com/ffxi/Talk:PDIF),
[Talk:Saboteur](https://www.bg-wiki.com/ffxi/Talk:Saboteur),
[Talk:Temper](https://www.bg-wiki.com/ffxi/Talk:Temper),
[Tanmogayi +1](https://www.bg-wiki.com/ffxi/Tanmogayi_%2B1),
[Tauret](https://www.bg-wiki.com/ffxi/Tauret),
[Telopanos Saber](https://www.bg-wiki.com/ffxi/Telopanos_Saber),
[Temper](https://www.bg-wiki.com/ffxi/Temper),
[Temper II](https://www.bg-wiki.com/ffxi/Temper_II),
[Tenebral Crush](https://www.bg-wiki.com/ffxi/Tenebral_Crush),
[Thibron](https://www.bg-wiki.com/ffxi/Thibron),
[Thunder Breath](https://www.bg-wiki.com/ffxi/Thunder_Breath),
[Thurandaut Chapeau +1](https://www.bg-wiki.com/ffxi/Thurandaut_Chapeau_%2B1),
[Tizona (Level 119 III)](https://www.bg-wiki.com/ffxi/Tizona_(Level_119_III)),
[Tizona (Level 119)](https://www.bg-wiki.com/ffxi/Tizona_(Level_119)),
[TP Bonus](https://www.bg-wiki.com/ffxi/TP_Bonus),
[TP Multiplier](https://www.bg-wiki.com/ffxi/TP_Multiplier),
[Treasure Hunter](https://www.bg-wiki.com/ffxi/Treasure_Hunter),
[Triple Attack](https://www.bg-wiki.com/ffxi/Triple_Attack),
[Ullr](https://www.bg-wiki.com/ffxi/Ullr),
[Umuthi Hat](https://www.bg-wiki.com/ffxi/Umuthi_Hat),
[Unbridled Learning](https://www.bg-wiki.com/ffxi/Unbridled_Learning),
[Unbridled Wisdom](https://www.bg-wiki.com/ffxi/Unbridled_Wisdom),
[Vanya Clogs](https://www.bg-wiki.com/ffxi/Vanya_Clogs),
[Vanya Cuffs](https://www.bg-wiki.com/ffxi/Vanya_Cuffs),
[Vapor Spray](https://www.bg-wiki.com/ffxi/Vapor_Spray),
[Version Update (07/08/2013)](https://www.bg-wiki.com/ffxi/Version_Update_(07/08/2013)),
[Vertical Cleave](https://www.bg-wiki.com/ffxi/Vertical_Cleave),
[Viti. Boots +4](https://www.bg-wiki.com/ffxi/Viti._Boots_%2B4),
[Viti. Chapeau +4](https://www.bg-wiki.com/ffxi/Viti._Chapeau_%2B4),
[Viti. Gloves +4](https://www.bg-wiki.com/ffxi/Viti._Gloves_%2B4),
[Vitiation Armor Set](https://www.bg-wiki.com/ffxi/Vitiation_Armor_Set),
[Vorpal Blade](https://www.bg-wiki.com/ffxi/Vorpal_Blade),
[Warcry](https://www.bg-wiki.com/ffxi/Warcry),
[Weapon Rank](https://www.bg-wiki.com/ffxi/Weapon_Rank),
[Weapon Skill](https://www.bg-wiki.com/ffxi/Weapon_Skill),
[Weapon Skill Damage](https://www.bg-wiki.com/bg/Weapon_Skill_Damage),
[Weather](https://www.bg-wiki.com/ffxi/Weather),
[White Wind](https://www.bg-wiki.com/ffxi/White_Wind),
[Wild Carrot](https://www.bg-wiki.com/ffxi/Wild_Carrot),
[Witful Belt](https://www.bg-wiki.com/ffxi/Witful_Belt).

FFXIclopedia, read directly:
[Accuracy](https://ffxiclopedia.fandom.com/wiki/Accuracy),
[Cast Time](https://ffxiclopedia.fandom.com/wiki/Cast_Time),
[Composure](https://ffxiclopedia.fandom.com/wiki/Composure),
[Doyen Pants](https://ffxiclopedia.fandom.com/wiki/Doyen_Pants),
[Fast Cast](https://ffxiclopedia.fandom.com/wiki/Fast_Cast),
[Hit Rate](https://ffxiclopedia.fandom.com/wiki/Hit_Rate),
[Magic Accuracy](https://ffxiclopedia.fandom.com/wiki/Magic_Accuracy),
[Magic Evasion](https://ffxiclopedia.fandom.com/wiki/Magic_Evasion),
[Magic Hit Rate](https://ffxiclopedia.fandom.com/wiki/Magic_Hit_Rate),
[Nyame Flanchard](https://ffxiclopedia.fandom.com/wiki/Nyame_Flanchard),
[Nyame Gauntlets](https://ffxiclopedia.fandom.com/wiki/Nyame_Gauntlets),
[Nyame Helm](https://ffxiclopedia.fandom.com/wiki/Nyame_Helm),
[Nyame Mail](https://ffxiclopedia.fandom.com/wiki/Nyame_Mail),
[Nyame Sollerets](https://ffxiclopedia.fandom.com/wiki/Nyame_Sollerets),
[Siegel Sash](https://ffxiclopedia.fandom.com/wiki/Siegel_Sash),
[Stone Gorget](https://ffxiclopedia.fandom.com/wiki/Stone_Gorget),
[Stoneskin](https://ffxiclopedia.fandom.com/wiki/Stoneskin).

Windower, read directly: [organizer addon](https://github.com/Windower/Lua/tree/live/addons/organizer) (`items.lua` and `organizer.lua`), on moving items between bags.

Forums, through search extracts: [Treasure hunter (FFXIAH)](https://www.ffxiah.com/forum/topic/26401/treasure-hunter), [TH Procing (Square Enix)](https://forum.square-enix.com/ffxi/threads/27974).

Thief's Dual Wield, through search extracts: [Thief (FFXIclopedia)](https://ffxiclopedia.fandom.com/wiki/Thief), [Dual Wield (bg-wiki)](https://www.bg-wiki.com/ffxi/Dual_Wield).

Windower: [Scoreboard pull request 1264](https://github.com/Windower/Lua/pull/1264), on `in_combat`, through a search extract.

GitHub, read as text, not run: [IzaKastra/bg_job_guides](https://github.com/IzaKastra/bg_job_guides) (backups of the All Jobs Gear Sets pages; last commit 2026-05-03), [IzaKastra/wsdist_beta](https://github.com/IzaKastra/wsdist_beta) (at d12ac59). The files read are listed under Sources for the simulated sets and Sources for wsdist.

**Reading the wikis from an automated session.** bg-wiki can be read with curl: `https://www.bg-wiki.com/ffxi/<Title>?action=raw` returns a page's wikitext, and `https://www.bg-wiki.com/api.php?action=parse&page=<Title>&prop=wikitext&format=json` returns the same when the raw URL answers 429 (rate limited). FFXIclopedia's MediaWiki API works the same way: `https://ffxiclopedia.fandom.com/api.php?action=parse&page=<Page_Name>&prop=wikitext&format=json`.
