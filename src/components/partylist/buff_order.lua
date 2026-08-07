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

--[[ The shipped buff priority: buff ids in the order they claim an icon slot,
     so rank 1 is the first thing you want to see on a party member. Only the
     top few survive the icon cap, which is what makes the order matter.

     Ported from XIVParty's bufforder.lua (BSD 3-clause (c) 2024 Tylas), which
     is itself derived from Windower's generated resources/buffs.lua:

       Copyright (c) 2013-2020, Windower. All rights reserved. Redistribution
       and use in source and binary forms, with or without modification, are
       permitted provided that the conditions of the BSD 3-clause licence
       reproduced in assets/LICENSE.txt are met.

     The names in the trailing comments are for the reader only -- nothing
     resolves a buff by the name in this file, and `//hud partylist buff` reads
     names from res.buffs. A buff id absent from this list is not an error: it
     simply sorts after everything ranked here. ]]

return {

  --[[ debuffs / negative effects ]]

  -- common debuffs
  0, -- KO
  1, -- weakness
  15, -- doom
  632, -- Black Sanctus
  633, -- animated
  14, -- charm
  17, -- charm
  2, -- sleep
  19, -- sleep
  10, -- stun
  28, -- terror
  11, -- bind
  12, -- weight
  567, -- weight
  177, -- encumbrance
  13, -- slow
  565, -- slow
  3, -- poison
  540, -- poison
  630, -- taint
  4, -- paralysis
  566, -- paralysis
  5, -- blindness
  156, -- Flash
  6, -- silence
  29, -- mute
  7, -- petrification
  18, -- gradual petrification
  8, -- disease
  31, -- plague
  9, -- curse
  20, -- curse
  631, -- haunt
  16, -- amnesia
  21, -- addle
  22, -- intimidate
  30, -- bane
  -- misc debuffs
  299, -- Overload
  473, -- muddle
  575, -- gestation
  576, -- Doubt
  -- dots
  128, -- Burn
  129, -- Frost
  130, -- Choke
  131, -- Rasp
  132, -- Shock
  133, -- Drown
  134, -- Dia
  135, -- Bio
  186, -- Helix
  23, -- Kaustra
  -- song debuffs
  192, -- Requiem
  193, -- Lullaby
  194, -- Elegy
  217, -- Threnody
  -- downs
  146, -- Accuracy Down
  561, -- Accuracy Down
  147, -- Attack Down
  557, -- Attack Down
  148, -- Evasion Down
  562, -- Evasion Down
  149, -- Defense Down
  558, -- Defense Down
  174, -- Magic Acc. Down
  563, -- Magic Acc. Down
  175, -- Magic Atk. Down
  559, -- Magic Atk. Down
  404, -- Magic Evasion Down
  564, -- Magic Evasion Down
  167, -- Magic Def. Down
  560, -- Magic Def. Down
  298, -- critical hit evasion down
  572, -- Avoidance Down
  144, -- Max HP Down
  145, -- Max MP Down
  189, -- Max TP Down
  168, -- Inhibit TP
  -- attribute downs
  136, -- STR Down
  137, -- DEX Down
  138, -- VIT Down
  139, -- AGI Down
  140, -- INT Down
  141, -- MND Down
  142, -- CHR Down
  -- pathos?
  258, -- Illusion
  259, -- encumbrance
  260, -- Obliviscence
  261, -- impairment
  262, -- Omerta
  263, -- debilitation
  264, -- Pathos

  --[[ buffs / positive effects ]]

  -- 2hrs / 1hrs / SPs
  44, -- Mighty Strikes
  46, -- Hundred Fists
  47, -- Manafont
  48, -- Chainspell
  49, -- Perfect Dodge
  50, -- Invincible
  51, -- Blood Weapon
  52, -- Soul Voice
  53, -- Eagle Eye Shot
  54, -- Meikyo Shisui
  55, -- Astral Flow
  126, -- Spirit Surge
  163, -- Azure Lore
  166, -- Overdrive
  376, -- Trance
  377, -- Tabula Rasa
  490, -- Brazen Rush
  491, -- Inner Strength
  492, -- Asylum
  493, -- Subtle Sorcery
  494, -- Stymie
  496, -- Intervene
  497, -- Soul Enslavement
  498, -- Unleash
  499, -- Clarion Call
  500, -- Overkill
  501, -- Yaegasumi
  502, -- Mikage
  503, -- Fly High
  504, -- Astral Conduit
  505, -- Unbridled Wisdom
  507, -- Grand Pas
  513, -- Bolster
  508, -- Widened Compass
  509, -- Odyllic Subterfuge
  522, -- Elemental Sforzo
  -- copy image
  66, -- Copy Image
  444, -- Copy Image (2)
  445, -- Copy Image (3)
  446, -- Copy Image (4+)
  -- common buffs
  33, -- Haste
  580, -- Haste
  265, -- Flurry
  581, -- Flurry
  36, -- Blink
  37, -- Stoneskin
  40, -- Protect
  41, -- Shell
  39, -- Aquaveil
  42, -- Regen
  539, -- Regen
  43, -- Refresh
  541, -- Refresh
  116, -- Phalanx
  113, -- Reraise
  69, -- Invisible
  70, -- Deodorize
  71, -- Sneak
  -- barspells
  100, -- Barfire
  101, -- Barblizzard
  102, -- Baraero
  103, -- Barstone
  104, -- Barthunder
  105, -- Barwater
  106, -- Barsleep
  107, -- Barpoison
  108, -- Barparalyze
  109, -- Barblind
  110, -- Barsilence
  111, -- Barpetrify
  112, -- Barvirus
  286, -- Baramnesia
  -- spikes
  34, -- Blaze Spikes
  35, -- Ice Spikes
  38, -- Shock Spikes
  173, -- Dread Spikes
  153, -- Damage Spikes
  573, -- Deluge Spikes
  605, -- Gale Spikes
  606, -- Clod Spikes
  607, -- Glint Spikes
  -- enspells
  94, -- Enfire
  95, -- Enblizzard
  96, -- Enaero
  97, -- Enstone
  98, -- Enthunder
  99, -- Enwater
  274, -- Enlight
  288, -- Endark
  277, -- Enfire II
  278, -- Enblizzard II
  279, -- Enaero II
  280, -- Enstone II
  281, -- Enthunder II
  282, -- Enwater II
  487, -- Endrain
  488, -- Enaspir
  275, -- Auspice
  -- scholar spells
  228, -- Embrava
  407, -- Klimaform
  178, -- Firestorm
  179, -- Hailstorm
  180, -- Windstorm
  181, -- Sandstorm
  182, -- Thunderstorm
  183, -- Rainstorm
  184, -- Aurorastorm
  185, -- Voidstorm
  589, -- Firestorm
  590, -- Hailstorm
  591, -- Windstorm
  592, -- Sandstorm
  593, -- Thunderstorm
  594, -- Rainstorm
  595, -- Aurorastorm
  596, -- Voidstorm
  -- avatar buffs
  154, -- Shining Ruby
  458, -- Earthen Armor
  624, -- Wind's Blessing
  283, -- Perfect Defense
  -- other spell buffs
  169, -- Potency
  170, -- Regain
  171, -- Pax
  172, -- Intension
  150, -- Physical Shield
  151, -- Arrow Shield
  152, -- Magic Shield
  289, -- Enmity Boost
  290, -- Subtle Blow Plus
  291, -- Enmity Down
  -- songs
  195, -- Paeon
  196, -- Ballad
  197, -- Minne
  198, -- Minuet
  199, -- Madrigal
  200, -- Prelude
  201, -- Mambo
  202, -- Aubade
  203, -- Pastoral
  204, -- Hum
  205, -- Fantasia
  206, -- Operetta
  207, -- Capriccio
  208, -- Serenade
  209, -- Round
  210, -- Gavotte
  211, -- Fugue
  212, -- Rhapsody
  213, -- Aria
  214, -- March
  215, -- Etude
  216, -- Carol
  218, -- Hymnus
  219, -- Mazurka
  220, -- Sirvente
  221, -- Dirge
  222, -- Scherzo
  223, -- Nocturne
  231, -- Marcato
  -- corsair / rolls
  601, -- Crooked Cards
  308, -- Double-Up Chance
  310, -- Fighter's Roll
  311, -- Monk's Roll
  312, -- Healer's Roll
  313, -- Wizard's Roll
  314, -- Warlock's Roll
  315, -- Rogue's Roll
  316, -- Gallant's Roll
  317, -- Chaos Roll
  318, -- Beast Roll
  319, -- Choral Roll
  320, -- Hunter's Roll
  321, -- Samurai Roll
  322, -- Ninja Roll
  323, -- Drachen Roll
  324, -- Evoker's Roll
  325, -- Magus's Roll
  326, -- Corsair's Roll
  327, -- Puppet Roll
  328, -- Dancer's Roll
  329, -- Scholar's Roll
  330, -- Bolter's Roll
  331, -- Caster's Roll
  332, -- Courser's Roll
  333, -- Blitzer's Roll
  334, -- Tactician's Roll
  335, -- Allies' Roll
  336, -- Miser's Roll
  337, -- Companion's Roll
  338, -- Avenger's Roll
  339, -- Naturalist's Roll
  600, -- Runeist's Roll
  309, -- Bust
  -- boosts
  90, -- Accuracy Boost
  553, -- Accuracy Boost
  91, -- Attack Boost
  549, -- Attack Boost
  92, -- Evasion Boost
  554, -- Evasion Boost
  93, -- Defense Boost
  550, -- Defense Boost
  555, -- Magic Acc. Boost
  190, -- Magic Atk. Boost
  551, -- Magic Atk. Boost
  556, -- Magic Evasion Boost
  611, -- Magic Evasion Boost
  191, -- Magic Def. Boost
  552, -- Magic Def. Boost
  88, -- Max HP Boost
  89, -- Max MP Boost
  -- attribute boosts
  80, -- STR Boost
  81, -- DEX Boost
  82, -- VIT Boost
  83, -- AGI Boost
  84, -- INT Boost
  85, -- MND Boost
  86, -- CHR Boost
  119, -- STR Boost
  120, -- DEX Boost
  121, -- VIT Boost
  122, -- AGI Boost
  123, -- INT Boost
  124, -- MND Boost
  125, -- CHR Boost
  542, -- STR Boost
  543, -- DEX Boost
  544, -- VIT Boost
  545, -- AGI Boost
  546, -- INT Boost
  547, -- MND Boost
  548, -- CHR Boost
  -- abilities
  45, -- Boost
  56, -- Berserk
  57, -- Defender
  58, -- Aggressor
  59, -- Focus
  60, -- Dodge
  61, -- Counterstance
  62, -- Sentinel
  63, -- Souleater
  64, -- Last Resort
  65, -- Sneak Attack
  87, -- Trick Attack
  67, -- Third Eye
  68, -- Warcry
  72, -- Sharpshot
  73, -- Barrage
  76, -- Hide
  77, -- Camouflage
  78, -- Divine Seal
  79, -- Elemental Seal
  114, -- Cover
  115, -- Unlimited Shot
  164, -- Chain Affinity
  165, -- Burst Affinity
  227, -- Store TP
  229, -- Manawell
  230, -- Spontaneity
  233, -- Auto-Regen
  234, -- Auto-Refresh
  266, -- Concentration
  340, -- Warrior's Charge
  341, -- Formless Strikes
  342, -- Assassin's Charge
  343, -- Feint
  344, -- Fealty
  345, -- Dark Seal
  346, -- Diabolic Eye
  347, -- Nightingale
  348, -- Troubadour
  349, -- Killer Instinct
  350, -- Stealth Shot
  351, -- Flashy Shot
  352, -- Sange
  355, -- Convergence
  356, -- Diffusion
  357, -- Snake Eye
  371, -- Velocity Shot
  403, -- Reprisal
  405, -- Retaliation
  406, -- Footwork
  408, -- Sekkanoki
  409, -- Pianissimo
  419, -- Composure
  432, -- Multi Strikes
  433, -- Double Shot
  434, -- Transcendency
  435, -- Restraint
  436, -- Perfect Counter
  437, -- Mana Wall
  438, -- Divine Emblem
  439, -- Nether Void
  440, -- Sengikori
  455, -- Tenuto
  447, -- Multi Shots
  453, -- Divine Caress
  454, -- Saboteur
  456, -- Spur
  457, -- Efflux
  459, -- Divine Caress
  460, -- Blood Rage
  461, -- Impetus
  462, -- Conspirator
  463, -- Sepulcher
  464, -- Arcane Crest
  465, -- Hamanoha
  466, -- Dragon Breaker
  467, -- Triple Shot
  474, -- Prowess
  476, -- Ensphere
  477, -- Sacrosanctity
  478, -- Palisade
  479, -- Scarlet Delirium
  480, -- Scarlet Delirium
  482, -- Decoy Shot
  483, -- Hagakure
  484, -- Issekigan
  485, -- Unbridled Learning
  486, -- Counter Boost
  582, -- Contradance
  583, -- Apogee
  584, -- Entrust
  586, -- Curing Conduit
  587, -- TP Bonus
  597, -- Inundation
  598, -- Cascade
  599, -- Consume Mana
  604, -- Mighty Guard
  613, -- Mumor's Radiance
  614, -- Ullegore's Gloom
  615, -- Boost
  616, -- Artisanal Knowledge
  617, -- Sacrifice
  619, -- Spirit Bond
  620, -- Awaken
  622, -- Guarding Rate Boost
  623, -- Rampart
  628, -- Hover Shot
  -- dancer
  368, -- Drain Samba
  369, -- Aspir Samba
  370, -- Haste Samba
  378, -- Drain Daze
  379, -- Aspir Daze
  380, -- Haste Daze
  381, -- Finishing Move 1
  382, -- Finishing Move 2
  383, -- Finishing Move 3
  384, -- Finishing Move 4
  385, -- Finishing Move 5
  588, -- Finishing Move (6+)
  386, -- Lethargic Daze 1
  387, -- Lethargic Daze 2
  388, -- Lethargic Daze 3
  389, -- Lethargic Daze 4
  390, -- Lethargic Daze 5
  391, -- Sluggish Daze 1
  392, -- Sluggish Daze 2
  393, -- Sluggish Daze 3
  394, -- Sluggish Daze 4
  395, -- Sluggish Daze 5
  396, -- Weakened Daze 1
  397, -- Weakened Daze 2
  398, -- Weakened Daze 3
  399, -- Weakened Daze 4
  400, -- Weakened Daze 5
  448, -- Bewildered Daze 1
  449, -- Bewildered Daze 2
  450, -- Bewildered Daze 3
  451, -- Bewildered Daze 4
  452, -- Bewildered Daze 5
  375, -- Building Flourish
  443, -- Climactic Flourish
  468, -- Striking Flourish
  472, -- Ternary Flourish
  410, -- Saber Dance
  411, -- Fan Dance
  442, -- Presto
  -- scholar abilities
  187, -- Sublimation: Activated
  188, -- Sublimation: Complete
  358, -- Light Arts
  359, -- Dark Arts
  401, -- Addendum: White
  402, -- Addendum: Black
  360, -- Penury
  361, -- Parsimony
  362, -- Celerity
  363, -- Alacrity
  364, -- Rapture
  365, -- Ebullience
  366, -- Accession
  367, -- Manifestation
  412, -- Altruism
  413, -- Focalization
  414, -- Tranquility
  415, -- Equanimity
  416, -- Enlightenment
  469, -- Perpetuance
  470, -- Immanence
  -- ninja
  471, -- Migawari
  420, -- Yonin
  421, -- Innin
  441, -- Futae
  -- geomancer
  569, -- Blaze of Glory
  515, -- Lasting Emanation
  516, -- Ecliptic Attrition
  517, -- Collimated Fervor
  518, -- Dematerialize
  519, -- Theurgic Focus
  612, -- Colure Active
  -- rune fencer
  568, -- Foil
  532, -- Swordplay
  534, -- Embolden
  533, -- Pflug
  570, -- Battuta
  571, -- Rayke
  574, -- Fast Cast
  535, -- Valiance
  531, -- Vallation
  536, -- Gambit
  537, -- Liement
  538, -- One for All
  523, -- Ignis
  524, -- Gelus
  525, -- Flabra
  526, -- Tellus
  527, -- Sulpor
  528, -- Unda
  529, -- Lux
  530, -- Tenebrae
  -- pup maneuvers
  300, -- Fire Maneuver
  301, -- Ice Maneuver
  302, -- Wind Maneuver
  303, -- Earth Maneuver
  304, -- Thunder Maneuver
  305, -- Water Maneuver
  306, -- Light Maneuver
  307, -- Dark Maneuver
  -- resistance buffs
  74, -- Holy Circle
  75, -- Arcane Circle
  117, -- Warding Circle
  118, -- Ancient Circle
  -- negates
  293, -- Negate Petrify
  294, -- Negate Terror
  295, -- Negate Amnesia
  296, -- Negate Doom
  297, -- Negate Poison
  608, -- Negate Virus
  609, -- Negate Curse
  610, -- Negate Charm
  626, -- Negate Sleep
  -- rema
  270, -- Aftermath: Lv.1
  271, -- Aftermath: Lv.2
  272, -- Aftermath: Lv.3
  273, -- Aftermath
  489, -- Afterglow
  -- restrictions / costumes
  284, -- Egg
  127, -- Costume
  585, -- Costume
  155, -- medicine
  143, -- Level Restriction
  157, -- SJ Restriction
  269, -- Level Sync
  -- stances
  417, -- Afflatus Solace
  418, -- Afflatus Misery
  353, -- Hasso
  354, -- Seigan
  621, -- Majesty
  -- avatar favors
  431, -- Avatar's Favor
  422, -- Carbuncle's Favor
  423, -- Ifrit's Favor
  424, -- Shiva's Favor
  425, -- Garuda's Favor
  426, -- Titan's Favor
  427, -- Ramuh's Favor
  428, -- Leviathan's Favor
  429, -- Fenrir's Favor
  430, -- Diabolos's Favor
  577, -- Cait Sith's Favor
  625, -- Siren's Favor
  -- crafting / HELM
  235, -- Fishing Imagery
  236, -- Woodworking Imagery
  237, -- Smithing Imagery
  238, -- Goldsmithing Imagery
  239, -- Clothcraft Imagery
  240, -- Leathercraft Imagery
  241, -- Bonecraft Imagery
  242, -- Alchemy Imagery
  243, -- Cooking Imagery
  578, -- Fishy Intuition
  -- exp/cp
  249, -- Dedication
  579, -- Commitment
  -- movement speed
  32, -- Flee
  176, -- quickening
  -- food / mount
  250, -- EF Badge
  251, -- Food
  252, -- Mounted
  -- signets
  253, -- Signet
  256, -- Sanction
  268, -- Sigil
  512, -- Ionis
  -- battlefields / instances
  254, -- Battlefield
  257, -- Besieged
  267, -- Allied Tags
  510, -- Ergon Might
  511, -- Reive Mark
  475, -- Voidwatcher
  276, -- Confrontation
  285, -- Visitant
  292, -- Pennant
  627, -- Mobilization
  -- ballista
  160, -- preparations
  158, -- Provoke
  159, -- penalty
  161, -- Sprint
  162, -- enchantment
  -- zone buffs
  287, -- Atma
  602, -- Vorseal
  603, -- Elvorseal
  506, -- Grace
  -- 72hr buffs
  481, -- Abdhaljs Seal
  629, -- Moogle Amplifier
  618, -- Emporox's Gift
  -- unused?
  24, -- ST24
  25, -- ST25
  26, -- ST26
  27, -- ST27
  224, -- ST224
  225, -- ST225
  226, -- ST226
  232, -- (N/A)
}
