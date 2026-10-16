--[[
Copyright © 2026, Azureblood2
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of XIVHud nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Azureblood2 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ Every job ability a SUBJOB can use, by job, at the level it is learned:
     what the binder offers on a subjob layer (Kevin, 2026-10-12), where the
     client lists only the abilities of the pair you are wearing and
     `res.job_abilities` carries no job or level at all.

     Ported from each job's BG Wiki page, read 2026-10-12: the job ability
     table and the family tables beside it (rolls, dances, runes, wards,
     effusions, stratagems, blood pacts, pet commands), every name matched
     to its id in Windower's job_abilities resource. Where a table carries
     the page's markers they are BRACKETS - a "v Sub-Job Accessible v" row
     opens a reachable section and the matching "^" row closes it, the
     master-level section likewise - and a row outside every bracket is
     main-job only (GEO's luopan abilities, Velocity Shot, BST's Ready).
     A table with no markers at all is all reachable, bar an ability whose
     own page says "Not available via support job" (Innin, Yonin). Kept to
     level 59, the highest a support job reaches (49 + one level per five
     master levels). Left out besides: the SP abilities, Composure and Call
     Wyvern, and the Astral Flow pacts, which need an SP ability. Added by
     hand where a page gives no level in text: the eight runes at 5 (drawn
     as icons) and the eight Quick Draw shots at 40.

     `name` is the resource's own, so a drifted id can be caught rather than
     offered as something else. ]]
return {
  WAR = {
    { id = 35, name = "Provoke", level = 5 },
    { id = 31, name = "Berserk", level = 15 },
    { id = 33, name = "Defender", level = 25 },
    { id = 32, name = "Warcry", level = 35 },
    { id = 34, name = "Aggressor", level = 45 },
  },
  MNK = {
    { id = 39, name = "Boost", level = 5 },
    { id = 37, name = "Dodge", level = 15 },
    { id = 36, name = "Focus", level = 25 },
    { id = 38, name = "Chakra", level = 35 },
    { id = 82, name = "Chi Blast", level = 41 },
    { id = 40, name = "Counterstance", level = 45 },
  },
  WHM = {
    { id = 74, name = "Divine Seal", level = 15 },
  },
  BLM = {
    { id = 75, name = "Elemental Seal", level = 15 },
  },
  RDM = {
    { id = 83, name = "Convert", level = 40 },
  },
  THF = {
    { id = 41, name = "Steal", level = 5 },
    { id = 44, name = "Sneak Attack", level = 15 },
    { id = 42, name = "Flee", level = 25 },
    { id = 76, name = "Trick Attack", level = 30 },
    { id = 45, name = "Mug", level = 35 },
    { id = 43, name = "Hide", level = 45 },
  },
  PLD = {
    { id = 47, name = "Holy Circle", level = 5 },
    { id = 46, name = "Shield Bash", level = 15 },
    { id = 48, name = "Sentinel", level = 30 },
    { id = 79, name = "Cover", level = 35 },
  },
  DRK = {
    { id = 50, name = "Arcane Circle", level = 5 },
    { id = 51, name = "Last Resort", level = 15 },
    { id = 77, name = "Weapon Bash", level = 20 },
    { id = 49, name = "Souleater", level = 30 },
    { id = 389, name = "Consume Mana", level = 55 },
  },
  BST = {
    { id = 52, name = "Charm", level = 1 },
    { id = 69, name = "Fight", level = 1 },
    { id = 53, name = "Gauge", level = 10 },
    { id = 70, name = "Heel", level = 10 },
    { id = 78, name = "Reward", level = 12 },
    { id = 73, name = "Stay", level = 15 },
    { id = 387, name = "Bestial Loyalty", level = 23 },
    { id = 85, name = "Call Beast", level = 23 },
    { id = 72, name = "Sic", level = 25 },
    { id = 54, name = "Tame", level = 30 },
    { id = 71, name = "Leave", level = 35 },
  },
  BRD = {
    { id = 229, name = "Pianissimo", level = 20 },
  },
  RNG = {
    { id = 59, name = "Sharpshot", level = 1 },
    { id = 56, name = "Scavenge", level = 10 },
    { id = 58, name = "Camouflage", level = 20 },
    { id = 60, name = "Barrage", level = 30 },
    { id = 57, name = "Shadowbind", level = 40 },
    { id = 86, name = "Unlimited Shot", level = 51 },
  },
  SAM = {
    { id = 64, name = "Warding Circle", level = 5 },
    { id = 62, name = "Third Eye", level = 15 },
    { id = 173, name = "Hasso", level = 25 },
    { id = 63, name = "Meditate", level = 30 },
    { id = 174, name = "Seigan", level = 35 },
    { id = 230, name = "Sekkanoki", level = 40 },
  },
  NIN = {},
  DRG = {
    { id = 87, name = "Dismiss", level = 1 },
    { id = 65, name = "Ancient Circle", level = 5 },
    { id = 66, name = "Jump", level = 10 },
    { id = 80, name = "Spirit Link", level = 25 },
    { id = 67, name = "High Jump", level = 35 },
    { id = 68, name = "Super Jump", level = 50 },
  },
  SMN = {
    { id = 88, name = "Assault", level = 1 },
    { id = 608, name = "Axe Kick", level = 1 },
    { id = 576, name = "Barracuda Dive", level = 1 },
    { id = 91, name = "Blood Pact: Rage", level = 1 },
    { id = 172, name = "Blood Pact: Ward", level = 1 },
    { id = 656, name = "Camisado", level = 1 },
    { id = 592, name = "Claw", level = 1 },
    { id = 512, name = "Healing Ruby", level = 1 },
    { id = 544, name = "Punch", level = 1 },
    { id = 521, name = "Regal Scratch", level = 1 },
    { id = 90, name = "Release", level = 1 },
    { id = 89, name = "Retreat", level = 1 },
    { id = 560, name = "Rock Throw", level = 1 },
    { id = 624, name = "Shock Strike", level = 1 },
    { id = 961, name = "Welt", level = 1 },
    { id = 528, name = "Moonlit Charge", level = 5 },
    { id = 513, name = "Poison Nails", level = 5 },
    { id = 593, name = "Aero II", level = 10 },
    { id = 609, name = "Blizzard II", level = 10 },
    { id = 529, name = "Crescent Fang", level = 10 },
    { id = 545, name = "Fire II", level = 10 },
    { id = 561, name = "Stone II", level = 10 },
    { id = 625, name = "Thunder II", level = 10 },
    { id = 577, name = "Water II", level = 10 },
    { id = 963, name = "Lunatic Voice", level = 15 },
    { id = 525, name = "Raise II", level = 15 },
    { id = 627, name = "Thunderspark", level = 19 },
    { id = 657, name = "Somnolence", level = 20 },
    { id = 530, name = "Lunar Cry", level = 21 },
    { id = 562, name = "Rock Buster", level = 21 },
    { id = 546, name = "Burning Strike", level = 23 },
    { id = 514, name = "Shining Ruby", level = 24 },
    { id = 596, name = "Aerial Armor", level = 25 },
    { id = 522, name = "Mewing Lullaby", level = 25 },
    { id = 964, name = "Roundhouse", level = 25 },
    { id = 578, name = "Tail Whip", level = 26 },
    { id = 610, name = "Frost Armor", level = 28 },
    { id = 658, name = "Nightmare", level = 29 },
    { id = 547, name = "Double Punch", level = 30 },
    { id = 526, name = "Reraise II", level = 30 },
    { id = 962, name = "Katabatic Blades", level = 31 },
    { id = 626, name = "Rolling Thunder", level = 31 },
    { id = 531, name = "Lunar Roar", level = 32 },
    { id = 580, name = "Slowga", level = 33 },
    { id = 563, name = "Megalith Throw", level = 35 },
    { id = 594, name = "Whispering Wind", level = 36 },
    { id = 659, name = "Ultimate Terror", level = 37 },
    { id = 548, name = "Crimson Howl", level = 38 },
    { id = 611, name = "Sleepga", level = 39 },
    { id = 965, name = "Chinook", level = 42 },
    { id = 628, name = "Lightning Armor", level = 42 },
    { id = 532, name = "Ecliptic Growl", level = 43 },
    { id = 515, name = "Glittering Ruby", level = 44 },
    { id = 564, name = "Earthen Ward", level = 46 },
    { id = 579, name = "Spring Water", level = 47 },
    { id = 595, name = "Hastega", level = 48 },
    { id = 660, name = "Noctoshield", level = 49 },
    { id = 966, name = "Bitter Elegy", level = 50 },
    { id = 612, name = "Double Slap", level = 50 },
    { id = 232, name = "Elemental Siphon", level = 50 },
    { id = 533, name = "Ecliptic Howl", level = 54 },
    { id = 250, name = "Avatar's Favor", level = 55 },
    { id = 523, name = "Eerie Eye", level = 55 },
    { id = 516, name = "Meteorite", level = 55 },
    { id = 661, name = "Dream Shroud", level = 56 },
  },
  BLU = {
    { id = 95, name = "Burst Affinity", level = 25 },
    { id = 94, name = "Chain Affinity", level = 40 },
  },
  COR = {
    { id = 114, name = "Corsair's Roll", level = 5 },
    { id = 123, name = "Double-Up", level = 5 },
    { id = 97, name = "Phantom Roll", level = 5 },
    { id = 110, name = "Ninja Roll", level = 8 },
    { id = 108, name = "Hunter's Roll", level = 11 },
    { id = 105, name = "Chaos Roll", level = 14 },
    { id = 113, name = "Magus's Roll", level = 17 },
    { id = 100, name = "Healer's Roll", level = 20 },
    { id = 111, name = "Drachen Roll", level = 23 },
    { id = 107, name = "Choral Roll", level = 26 },
    { id = 99, name = "Monk's Roll", level = 31 },
    { id = 106, name = "Beast Roll", level = 34 },
    { id = 109, name = "Samurai Roll", level = 37 },
    { id = 132, name = "Dark Shot", level = 40 },
    { id = 128, name = "Earth Shot", level = 40 },
    { id = 112, name = "Evoker's Roll", level = 40 },
    { id = 125, name = "Fire Shot", level = 40 },
    { id = 126, name = "Ice Shot", level = 40 },
    { id = 131, name = "Light Shot", level = 40 },
    { id = 124, name = "Quick Draw", level = 40 },
    { id = 129, name = "Thunder Shot", level = 40 },
    { id = 130, name = "Water Shot", level = 40 },
    { id = 127, name = "Wind Shot", level = 40 },
    { id = 103, name = "Rogue's Roll", level = 43 },
    { id = 102, name = "Warlock's Roll", level = 46 },
    { id = 98, name = "Fighter's Roll", level = 49 },
    { id = 133, name = "Random Deal", level = 50 },
    { id = 115, name = "Puppet Roll", level = 52 },
    { id = 104, name = "Gallant's Roll", level = 55 },
    { id = 101, name = "Wizard's Roll", level = 58 },
  },
  PUP = {
    { id = 136, name = "Activate", level = 1 },
    { id = 148, name = "Dark Maneuver", level = 1 },
    { id = 139, name = "Deactivate", level = 1 },
    { id = 138, name = "Deploy", level = 1 },
    { id = 144, name = "Earth Maneuver", level = 1 },
    { id = 141, name = "Fire Maneuver", level = 1 },
    { id = 142, name = "Ice Maneuver", level = 1 },
    { id = 147, name = "Light Maneuver", level = 1 },
    { id = 145, name = "Thunder Maneuver", level = 1 },
    { id = 146, name = "Water Maneuver", level = 1 },
    { id = 143, name = "Wind Maneuver", level = 1 },
    { id = 140, name = "Retrieve", level = 10 },
    { id = 137, name = "Repair", level = 15 },
  },
  DNC = {
    { id = 184, name = "Drain Samba", level = 5 },
    { id = 190, name = "Curing Waltz", level = 15 },
    { id = 204, name = "Animated Flourish", level = 20 },
    { id = 201, name = "Quickstep", level = 20 },
    { id = 187, name = "Aspir Samba", level = 25 },
    { id = 195, name = "Divine Waltz", level = 25 },
    { id = 196, name = "Spectral Jig", level = 25 },
    { id = 202, name = "Box Step", level = 30 },
    { id = 191, name = "Curing Waltz II", level = 30 },
    { id = 205, name = "Desperate Flourish", level = 30 },
    { id = 185, name = "Drain Samba II", level = 35 },
    { id = 194, name = "Healing Waltz", level = 35 },
    { id = 206, name = "Reverse Flourish", level = 40 },
    { id = 203, name = "Stutter Step", level = 40 },
    { id = 192, name = "Curing Waltz III", level = 45 },
    { id = 189, name = "Haste Samba", level = 45 },
    { id = 207, name = "Violent Flourish", level = 45 },
    { id = 208, name = "Building Flourish", level = 50 },
    { id = 384, name = "Contradance", level = 50 },
    { id = 197, name = "Chocobo Jig", level = 55 },
  },
  SCH = {
    { id = 234, name = "Addendum: White", level = 10 },
    { id = 212, name = "Dark Arts", level = 10 },
    { id = 211, name = "Light Arts", level = 10 },
    { id = 219, name = "Parsimony", level = 10 },
    { id = 215, name = "Penury", level = 10 },
    { id = 220, name = "Alacrity", level = 25 },
    { id = 216, name = "Celerity", level = 25 },
    { id = 235, name = "Addendum: Black", level = 30 },
    { id = 233, name = "Sublimation", level = 35 },
    { id = 218, name = "Accession", level = 40 },
    { id = 222, name = "Manifestation", level = 40 },
    { id = 221, name = "Ebullience", level = 55 },
    { id = 217, name = "Rapture", level = 55 },
  },
  GEO = {
    { id = 348, name = "Collimated Fervor", level = 40 },
    { id = 349, name = "Life Cycle", level = 50 },
  },
  RUN = {
    { id = 360, name = "Flabra", level = 5 },
    { id = 359, name = "Gelus", level = 5 },
    { id = 358, name = "Ignis", level = 5 },
    { id = 364, name = "Lux", level = 5 },
    { id = 362, name = "Sulpor", level = 5 },
    { id = 361, name = "Tellus", level = 5 },
    { id = 365, name = "Tenebrae", level = 5 },
    { id = 363, name = "Unda", level = 5 },
    { id = 366, name = "Vallation", level = 10 },
    { id = 367, name = "Swordplay", level = 20 },
    { id = 368, name = "Lunge", level = 25 },
    { id = 344, name = "Swipe", level = 25 },
    { id = 369, name = "Pflug", level = 40 },
    { id = 371, name = "Valiance", level = 50 },
  },
}
