# Auto spell tier

`//hud autospelltier on` makes a tiered spell fall back to a lower tier when
it cannot be cast. The rules are under
[Auto spell tier](Home.md#auto-spell-tier) on the home page. This page has
what to look for in the debug log, and the ladders it walks.

## Reading the debug log

With `//hud queue debug`, every decision is one line in `debug.log`, in the
addon's folder:

```
2026-11-24 21:14:07 queue 512.31: at the press: Fire V on recast 9.87s, lock 1.20s; Fire IV on recast 4.10s; down to Fire III
```

After the date, the time and the queue's own clock, it reads left to right:

1. **When it was decided:** `at the press`, `at OK` (you confirmed the target
   of a slot that asks for one) or `at the release` (a press the queue was
   holding had its turn).
2. **The spell you pressed, and why it could not go:**

   | It says | Meaning |
   | --- | --- |
   | `on recast 9.87s, lock 1.20s` | its cooldown had that long left, and the wait after your last action had that long left. In place of the lock it says `casting` if another action was still in progress, `unanswered` if one had been sent and not yet answered, or `free` |
   | `not learned` | you have not learned it |
   | `needs BLM 86 (on BLM 70/WHM 35)` | the level a job you are on still needs, then the jobs and levels you were on |
   | `needs Addendum: Black (on SCH 99/RDM 49)` | a Scholar without that Addendum up; `needs Addendum: Black and SCH 73` if the level is short too |
   | `needs BLM 99 as the main job (on RDM 99/BLM 49)` | a tier bought with merit or job points, on a sub job or under a level sync |
   | `no spell of NIN 99/WAR 49` | neither job has the spell |

3. **Each tier it passed by**, for one of the reasons above (a tier's cooldown
   reads `on recast 4.10s`), or because it `cannot be aimed as` the spell you
   pressed, or there is `no such spell` a player can cast.
4. **What it settled on:** `down to <tier>`; `no tier under it can go`, where
   the spell you pressed is sent as it was, or dropped if the queue was
   holding it; or `near enough ready, kept`, where its cooldown was running
   but inside the two seconds that are waited for.

A tiered spell that was ready when you pressed it writes nothing.

## Ladders

Each row is one family of spells for one job, highest tier first. A press of
any spell in a row can fall back to the spells on its right, and never to one
on its left.

- A row holds only the tiers that job can cast. With a sub job, a tier counts
  if either job can cast it at its level right now.
- A Scholar's rows assume the Addendum is up. Without it, the tiers that need
  one are passed by.
- A tier bought with merit or job points counts only on your main job, at
  level 99.
- Warp II and Phalanx II have no row: Warp and Phalanx can only be cast on
  yourself, so neither ever goes in their place.
- Jobs are in alphabetical order, then the kind of magic, then the spell. A
  job that is not listed has no tiered spells.

The rows were produced by running the addon's own tier walk for every job
over Windower's spell list as of the 10 November 2026 game update, and
checked against a second, independent read of that file.

| Job | Type | Spell | Ladder |
| --- | --- | --- | --- |
| BLM | Black magic | Aero | Aero VI > Aero V > Aero IV > Aero III > Aero II > Aero |
| BLM | Black magic | Aeroga | Aeroga III > Aeroga II > Aeroga |
| BLM | Black magic | Aspir | Aspir III > Aspir II > Aspir |
| BLM | Black magic | Bio | Bio II > Bio |
| BLM | Black magic | Blizzaga | Blizzaga III > Blizzaga II > Blizzaga |
| BLM | Black magic | Blizzard | Blizzard VI > Blizzard V > Blizzard IV > Blizzard III > Blizzard II > Blizzard |
| BLM | Black magic | Burst | Burst II > Burst |
| BLM | Black magic | Firaga | Firaga III > Firaga II > Firaga |
| BLM | Black magic | Fire | Fire VI > Fire V > Fire IV > Fire III > Fire II > Fire |
| BLM | Black magic | Flare | Flare II > Flare |
| BLM | Black magic | Flood | Flood II > Flood |
| BLM | Black magic | Freeze | Freeze II > Freeze |
| BLM | Black magic | Poison | Poison II > Poison |
| BLM | Black magic | Quake | Quake II > Quake |
| BLM | Black magic | Sleep | Sleep II > Sleep |
| BLM | Black magic | Sleepga | Sleepga II > Sleepga |
| BLM | Black magic | Stone | Stone VI > Stone V > Stone IV > Stone III > Stone II > Stone |
| BLM | Black magic | Stonega | Stonega III > Stonega II > Stonega |
| BLM | Black magic | Thundaga | Thundaga III > Thundaga II > Thundaga |
| BLM | Black magic | Thunder | Thunder VI > Thunder V > Thunder IV > Thunder III > Thunder II > Thunder |
| BLM | Black magic | Tornado | Tornado II > Tornado |
| BLM | Black magic | Water | Water VI > Water V > Water IV > Water III > Water II > Water |
| BLM | Black magic | Waterga | Waterga III > Waterga II > Waterga |
| BRD | Song | Army's Paeon | Army's Paeon VI > Army's Paeon V > Army's Paeon IV > Army's Paeon III > Army's Paeon II > Army's Paeon |
| BRD | Song | Dark Carol | Dark Carol II > Dark Carol |
| BRD | Song | Dark Threnody | Dark Threnody II > Dark Threnody |
| BRD | Song | Earth Carol | Earth Carol II > Earth Carol |
| BRD | Song | Earth Threnody | Earth Threnody II > Earth Threnody |
| BRD | Song | Fire Carol | Fire Carol II > Fire Carol |
| BRD | Song | Fire Threnody | Fire Threnody II > Fire Threnody |
| BRD | Song | Foe Lullaby | Foe Lullaby II > Foe Lullaby |
| BRD | Song | Foe Requiem | Foe Requiem VII > Foe Requiem VI > Foe Requiem V > Foe Requiem IV > Foe Requiem III > Foe Requiem II > Foe Requiem |
| BRD | Song | Horde Lullaby | Horde Lullaby II > Horde Lullaby |
| BRD | Song | Ice Carol | Ice Carol II > Ice Carol |
| BRD | Song | Ice Threnody | Ice Threnody II > Ice Threnody |
| BRD | Song | Knight's Minne | Knight's Minne V > Knight's Minne IV > Knight's Minne III > Knight's Minne II > Knight's Minne |
| BRD | Song | Light Carol | Light Carol II > Light Carol |
| BRD | Song | Light Threnody | Light Threnody II > Light Threnody |
| BRD | Song | Lightning Carol | Lightning Carol II > Lightning Carol |
| BRD | Song | Ltng. Threnody | Ltng. Threnody II > Ltng. Threnody |
| BRD | Song | Mage's Ballad | Mage's Ballad III > Mage's Ballad II > Mage's Ballad |
| BRD | Song | Valor Minuet | Valor Minuet V > Valor Minuet IV > Valor Minuet III > Valor Minuet II > Valor Minuet |
| BRD | Song | Water Carol | Water Carol II > Water Carol |
| BRD | Song | Water Threnody | Water Threnody II > Water Threnody |
| BRD | Song | Wind Carol | Wind Carol II > Wind Carol |
| BRD | Song | Wind Threnody | Wind Threnody II > Wind Threnody |
| DRK | Black magic | Aero | Aero III > Aero II > Aero |
| DRK | Black magic | Aspir | Aspir II > Aspir |
| DRK | Black magic | Bio | Bio II > Bio |
| DRK | Black magic | Blizzard | Blizzard III > Blizzard II > Blizzard |
| DRK | Black magic | Drain | Drain III > Drain II > Drain |
| DRK | Black magic | Endark | Endark II > Endark |
| DRK | Black magic | Fire | Fire III > Fire II > Fire |
| DRK | Black magic | Poison | Poison II > Poison |
| DRK | Black magic | Sleep | Sleep II > Sleep |
| DRK | Black magic | Stone | Stone III > Stone II > Stone |
| DRK | Black magic | Thunder | Thunder III > Thunder II > Thunder |
| DRK | Black magic | Water | Water III > Water II > Water |
| GEO | Black magic | Aera | Aera III > Aera II > Aera |
| GEO | Black magic | Aero | Aero V > Aero IV > Aero III > Aero II > Aero |
| GEO | Black magic | Aspir | Aspir III > Aspir II > Aspir |
| GEO | Black magic | Blizzara | Blizzara III > Blizzara II > Blizzara |
| GEO | Black magic | Blizzard | Blizzard V > Blizzard IV > Blizzard III > Blizzard II > Blizzard |
| GEO | Black magic | Fira | Fira III > Fira II > Fira |
| GEO | Black magic | Fire | Fire V > Fire IV > Fire III > Fire II > Fire |
| GEO | Black magic | Sleep | Sleep II > Sleep |
| GEO | Black magic | Stone | Stone V > Stone IV > Stone III > Stone II > Stone |
| GEO | Black magic | Stonera | Stonera III > Stonera II > Stonera |
| GEO | Black magic | Thundara | Thundara III > Thundara II > Thundara |
| GEO | Black magic | Thunder | Thunder V > Thunder IV > Thunder III > Thunder II > Thunder |
| GEO | Black magic | Water | Water V > Water IV > Water III > Water II > Water |
| GEO | Black magic | Watera | Watera III > Watera II > Watera |
| NIN | Ninjutsu | Doton | Doton: San > Doton: Ni > Doton: Ichi |
| NIN | Ninjutsu | Hojo | Hojo: Ni > Hojo: Ichi |
| NIN | Ninjutsu | Huton | Huton: San > Huton: Ni > Huton: Ichi |
| NIN | Ninjutsu | Hyoton | Hyoton: San > Hyoton: Ni > Hyoton: Ichi |
| NIN | Ninjutsu | Katon | Katon: San > Katon: Ni > Katon: Ichi |
| NIN | Ninjutsu | Kurayami | Kurayami: Ni > Kurayami: Ichi |
| NIN | Ninjutsu | Raiton | Raiton: San > Raiton: Ni > Raiton: Ichi |
| NIN | Ninjutsu | Suiton | Suiton: San > Suiton: Ni > Suiton: Ichi |
| NIN | Ninjutsu | Tonko | Tonko: Ni > Tonko: Ichi |
| NIN | Ninjutsu | Utsusemi | Utsusemi: San > Utsusemi: Ni > Utsusemi: Ichi |
| PLD | White magic | Banish | Banish II > Banish |
| PLD | White magic | Cure | Cure IV > Cure III > Cure II > Cure |
| PLD | White magic | Enlight | Enlight II > Enlight |
| PLD | White magic | Holy | Holy II > Holy |
| PLD | White magic | Protect | Protect V > Protect IV > Protect III > Protect II > Protect |
| PLD | White magic | Shell | Shell IV > Shell III > Shell II > Shell |
| RDM | Black magic | Aero | Aero V > Aero IV > Aero III > Aero II > Aero |
| RDM | Black magic | Bio | Bio III > Bio II > Bio |
| RDM | Black magic | Blind | Blind II > Blind |
| RDM | Black magic | Blizzard | Blizzard V > Blizzard IV > Blizzard III > Blizzard II > Blizzard |
| RDM | Black magic | Distract | Distract III > Distract II > Distract |
| RDM | Black magic | Fire | Fire V > Fire IV > Fire III > Fire II > Fire |
| RDM | Black magic | Frazzle | Frazzle III > Frazzle II > Frazzle |
| RDM | Black magic | Gravity | Gravity II > Gravity |
| RDM | Black magic | Poison | Poison II > Poison |
| RDM | Black magic | Sleep | Sleep II > Sleep |
| RDM | Black magic | Stone | Stone V > Stone IV > Stone III > Stone II > Stone |
| RDM | Black magic | Thunder | Thunder V > Thunder IV > Thunder III > Thunder II > Thunder |
| RDM | Black magic | Water | Water V > Water IV > Water III > Water II > Water |
| RDM | White magic | Addle | Addle II > Addle |
| RDM | White magic | Cure | Cure IV > Cure III > Cure II > Cure |
| RDM | White magic | Dia | Dia III > Dia II > Dia |
| RDM | White magic | Enaero | Enaero II > Enaero |
| RDM | White magic | Enblizzard | Enblizzard II > Enblizzard |
| RDM | White magic | Enfire | Enfire II > Enfire |
| RDM | White magic | Enstone | Enstone II > Enstone |
| RDM | White magic | Enthunder | Enthunder II > Enthunder |
| RDM | White magic | Enwater | Enwater II > Enwater |
| RDM | White magic | Flurry | Flurry II > Flurry |
| RDM | White magic | Haste | Haste II > Haste |
| RDM | White magic | Paralyze | Paralyze II > Paralyze |
| RDM | White magic | Protect | Protect V > Protect IV > Protect III > Protect II > Protect |
| RDM | White magic | Raise | Raise II > Raise |
| RDM | White magic | Refresh | Refresh III > Refresh II > Refresh |
| RDM | White magic | Regen | Regen II > Regen |
| RDM | White magic | Shell | Shell V > Shell IV > Shell III > Shell II > Shell |
| RDM | White magic | Slow | Slow II > Slow |
| RDM | White magic | Temper | Temper II > Temper |
| RUN | White magic | Protect | Protect IV > Protect III > Protect II > Protect |
| RUN | White magic | Regen | Regen IV > Regen III > Regen II > Regen |
| RUN | White magic | Shell | Shell V > Shell IV > Shell III > Shell II > Shell |
| SCH | Black magic | Aero | Aero V > Aero IV > Aero III > Aero II > Aero |
| SCH | Black magic | Anemohelix | Anemohelix II > Anemohelix |
| SCH | Black magic | Aspir | Aspir II > Aspir |
| SCH | Black magic | Blizzard | Blizzard V > Blizzard IV > Blizzard III > Blizzard II > Blizzard |
| SCH | Black magic | Cryohelix | Cryohelix II > Cryohelix |
| SCH | Black magic | Fire | Fire V > Fire IV > Fire III > Fire II > Fire |
| SCH | Black magic | Geohelix | Geohelix II > Geohelix |
| SCH | Black magic | Hydrohelix | Hydrohelix II > Hydrohelix |
| SCH | Black magic | Ionohelix | Ionohelix II > Ionohelix |
| SCH | Black magic | Luminohelix | Luminohelix II > Luminohelix |
| SCH | Black magic | Noctohelix | Noctohelix II > Noctohelix |
| SCH | Black magic | Pyrohelix | Pyrohelix II > Pyrohelix |
| SCH | Black magic | Sleep | Sleep II > Sleep |
| SCH | Black magic | Stone | Stone V > Stone IV > Stone III > Stone II > Stone |
| SCH | Black magic | Thunder | Thunder V > Thunder IV > Thunder III > Thunder II > Thunder |
| SCH | Black magic | Water | Water V > Water IV > Water III > Water II > Water |
| SCH | White magic | Aurorastorm | Aurorastorm II > Aurorastorm |
| SCH | White magic | Cure | Cure IV > Cure III > Cure II > Cure |
| SCH | White magic | Firestorm | Firestorm II > Firestorm |
| SCH | White magic | Hailstorm | Hailstorm II > Hailstorm |
| SCH | White magic | Protect | Protect V > Protect IV > Protect III > Protect II > Protect |
| SCH | White magic | Rainstorm | Rainstorm II > Rainstorm |
| SCH | White magic | Raise | Raise III > Raise II > Raise |
| SCH | White magic | Regen | Regen V > Regen IV > Regen III > Regen II > Regen |
| SCH | White magic | Reraise | Reraise III > Reraise II > Reraise |
| SCH | White magic | Sandstorm | Sandstorm II > Sandstorm |
| SCH | White magic | Shell | Shell V > Shell IV > Shell III > Shell II > Shell |
| SCH | White magic | Thunderstorm | Thunderstorm II > Thunderstorm |
| SCH | White magic | Voidstorm | Voidstorm II > Voidstorm |
| SCH | White magic | Windstorm | Windstorm II > Windstorm |
| WHM | White magic | Banish | Banish III > Banish II > Banish |
| WHM | White magic | Banishga | Banishga II > Banishga |
| WHM | White magic | Cura | Cura III > Cura II > Cura |
| WHM | White magic | Curaga | Curaga V > Curaga IV > Curaga III > Curaga II > Curaga |
| WHM | White magic | Cure | Cure VI > Cure V > Cure IV > Cure III > Cure II > Cure |
| WHM | White magic | Dia | Dia II > Dia |
| WHM | White magic | Holy | Holy II > Holy |
| WHM | White magic | Protect | Protect V > Protect IV > Protect III > Protect II > Protect |
| WHM | White magic | Protectra | Protectra V > Protectra IV > Protectra III > Protectra II > Protectra |
| WHM | White magic | Raise | Raise III > Raise II > Raise |
| WHM | White magic | Regen | Regen IV > Regen III > Regen II > Regen |
| WHM | White magic | Reraise | Reraise IV > Reraise III > Reraise II > Reraise |
| WHM | White magic | Shell | Shell V > Shell IV > Shell III > Shell II > Shell |
| WHM | White magic | Shellra | Shellra V > Shellra IV > Shellra III > Shellra II > Shellra |
