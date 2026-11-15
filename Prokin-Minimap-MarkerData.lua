-- Dungeon data for smart marking: which NPCs are 5-player dungeon bosses, and which trash is
-- dangerous enough to kill first. Keyed by NPC ID, the sixth field of a creature GUID, so it works
-- on every client language. Heroic versions of TBC mobs have their own IDs and are listed too.
--
-- Sources:
--   Vanilla and WoW Forever boss names: AKForeverTargeter by Purrdee (MIT License),
--     https://github.com/ajkatz/AKForeverTargeter. TBC boss names compiled for Prokin.
--   Dangerous trash: compiled for Prokin from dungeon guides (Wowpedia, quissy.tv, mmojugg):
--     healers, summoners, fears and hard-hitting casters.
--   NPC IDs: Wowhead, cross-checked with the AzerothCore creature database.
-- Bosses of dungeons only WoW Forever has are not in those databases, so they are matched by
-- their English names instead.
--
-- The AKForeverTargeter boss names are used under this license:
--   MIT License
--
--   Copyright (c) 2026 Purrdee
--
--   Permission is hereby granted, free of charge, to any person obtaining a copy
--   of this software and associated documentation files (the "Software"), to deal
--   in the Software without restriction, including without limitation the rights
--   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--   copies of the Software, and to permit persons to whom the Software is
--   furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in all
--   copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--   SOFTWARE.

local Marker = _G.ProkinMinimapMarker or {}
_G.ProkinMinimapMarker = Marker

Marker.DUNGEON_BOSSES = {
	-- Scarlet Monastery
	[3983] = true, -- Interrogator Vishas
	[4543] = true, -- Bloodmage Thalnos
	[3974] = true, -- Houndmaster Loksey
	[6487] = true, [20352] = true, -- Arcanist Doan
	[3975] = true, -- Herod
	[4542] = true, -- High Inquisitor Fairbanks
	[3976] = true, -- Scarlet Commander Mograine
	[3977] = true, -- High Inquisitor Whitemane
	-- Razorfen Downs
	[7355] = true, -- Tuten'kash
	[7357] = true, -- Mordresh Fire Eye
	[8567] = true, -- Glutton
	[7356] = true, -- Plaguemaw the Rotting
	[7358] = true, -- Amnennar the Coldbringer
	-- Uldaman
	[6910] = true, -- Revelosh
	[6906] = true, -- Baelog
	[6907] = true, -- Eric "The Swift"
	[6908] = true, -- Olaf
	[7228] = true, -- Ironaya
	[7023] = true, -- Obsidian Sentinel
	[7206] = true, -- Ancient Stone Keeper
	[7291] = true, -- Galgann Firehammer
	[4854] = true, -- Grimlok
	[2748] = true, -- Archaedas
	-- Ragefire Chasm
	[11517] = true, -- Oggleflint
	[11520] = true, -- Taragaman the Hungerer
	[11518] = true, -- Jergosh the Invoker
	[11519] = true, -- Bazzalan
	-- Stratholme
	[10516] = true, -- The Unforgiven
	[10808] = true, -- Timmy the Cruel
	[11032] = true, -- Malor the Zealous
	[10997] = true, -- Cannon Master Willey
	[10811] = true, -- Archivist Galford
	[10813] = true, -- Balnazzar
	[10436] = true, -- Baroness Anastari
	[10437] = true, -- Nerub'enkan
	[10438] = true, -- Maleki the Pallid
	[10435] = true, -- Magistrate Barthilas
	[10439] = true, -- Ramstein the Gorger
	[10440] = true, -- Baron Rivendare
	-- Zul'Farrak
	[8127] = true, -- Antu'sul
	[7272] = true, -- Theka the Martyr
	[7271] = true, -- Witch Doctor Zum'rah
	[7796] = true, -- Nekrum Gutchewer
	[7275] = true, -- Shadowpriest Sezz'ziz
	[7604] = true, -- Sergeant Bly
	[7795] = true, -- Hydromancer Velratha
	[7273] = true, -- Gahz'rilla
	[7267] = true, -- Chief Ukorz Sandscalp
	[7797] = true, -- Ruuzlu
	-- Gnomeregan
	[7361] = true, -- Grubbis
	[7079] = true, -- Viscous Fallout
	[6235] = true, -- Electrocutioner 6000
	[6229] = true, -- Crowd Pummeler 9-60
	[7800] = true, -- Mekgineer Thermaplugg
	-- Shadowfang Keep
	[3914] = true, -- Rethilgore
	[3886] = true, -- Razorclaw the Butcher
	[3887] = true, -- Baron Silverlaine
	[4278] = true, -- Commander Springvale
	[4279] = true, -- Odo the Blindwatcher
	[4274] = true, -- Fenrus the Devourer
	[3927] = true, -- Wolf Master Nandos
	[4275] = true, -- Archmage Arugal
	-- The Stockade
	[1696] = true, -- Targorr the Dread
	[1666] = true, -- Kam Deepfury
	[1717] = true, -- Hamhock
	[1716] = true, -- Bazil Thredd
	[1663] = true, -- Dextren Ward
	-- The Deadmines
	[644] = true, -- Rhahk'Zor
	[642] = true, -- Sneed's Shredder
	[643] = true, -- Sneed
	[1763] = true, -- Gilnid
	[646] = true, -- Mr. Smite
	[647] = true, -- Captain Greenskin
	[639] = true, -- Edwin VanCleef
	[645] = true, -- Cookie
	-- Scholomance
	[10506] = true, -- Kirtonos the Herald
	[10503] = true, -- Jandice Barov
	[11622] = true, -- Rattlegore
	[10433] = true, -- Marduk Blackpool
	[10432] = true, -- Vectus
	[10508] = true, -- Ras Frostwhisper
	[10505] = true, -- Instructor Malicia
	[11261] = true, -- Doctor Theolen Krastinov
	[10901] = true, -- Lorekeeper Polkelt
	[10507] = true, -- The Ravenian
	[10504] = true, -- Lord Alexei Barov
	[10502] = true, -- Lady Illucia Barov
	[1853] = true, -- Darkmaster Gandling
	-- Blackrock Spire
	[9196] = true, -- Highlord Omokk
	[9236] = true, -- Shadow Hunter Vosh'gajin
	[9237] = true, -- War Master Voone
	[10596] = true, -- Mother Smolderweb
	[10584] = true, -- Urok Doomhowl
	[9736] = true, -- Quartermaster Zigris
	[10220] = true, -- Halycon
	[10268] = true, -- Gizrul the Slavener
	[9568] = true, -- Overlord Wyrmthalak
	[9816] = true, -- Pyroguard Emberseer
	[10264] = true, -- Solakar Flamewreath
	[10899] = true, -- Goraluk Anvilcrack
	[10429] = true, -- Warchief Rend Blackhand
	[10339] = true, -- Gyth
	[10430] = true, -- The Beast
	[10363] = true, -- General Drakkisath
	-- Blackrock Depths
	[9025] = true, -- Lord Roccor
	[9018] = true, -- High Interrogator Gerstahn
	[9319] = true, -- Houndmaster Grebmar
	[9016] = true, -- Bael'Gar
	[9017] = true, -- Lord Incendius
	[9056] = true, -- Fineous Darkvire
	[9041] = true, -- Warder Stilgiss
	[9042] = true, -- Verek
	[9024] = true, -- Pyromancer Loregrain
	[9033] = true, -- General Angerforge
	[8983] = true, -- Golem Lord Argelmach
	[9537] = true, -- Hurley Blackbreath
	[9502] = true, -- Phalanx
	[9543] = true, -- Ribbly Screwspigot
	[9499] = true, -- Plugger Spazzring
	[9156] = true, -- Ambassador Flamelash
	[9938] = true, -- Magmus
	[9019] = true, -- Emperor Dagran Thaurissan
	[8929] = true, -- Princess Moira Bronzebeard
	-- Wailing Caverns
	[3671] = true, -- Lady Anacondra
	[3669] = true, -- Lord Cobrahn
	[3653] = true, -- Kresh
	[3670] = true, -- Lord Pythas
	[3674] = true, -- Skum
	[3673] = true, -- Lord Serpentis
	[5775] = true, -- Verdan the Everliving
	[3654] = true, -- Mutanus the Devourer
	-- The Temple of Atal'Hakkar
	[8580] = true, -- Atal'alarion
	[5721] = true, -- Dreamscythe
	[5720] = true, -- Weaver
	[5710] = true, -- Jammal'an the Prophet
	[5711] = true, -- Ogom the Wretched
	[5719] = true, -- Morphaz
	[5722] = true, -- Hazzas
	[8443] = true, -- Avatar of Hakkar
	[5709] = true, -- Shade of Eranikus
	[5712] = true, -- Zolo
	[5713] = true, -- Gasher
	[5714] = true, -- Loro
	[5715] = true, -- Hukku
	[5716] = true, -- Zul'Lor
	[5717] = true, -- Mijan
	-- Razorfen Kraul
	[6168] = true, -- Roogug
	[4424] = true, -- Aggem Thorncurse
	[4428] = true, -- Death Speaker Jargba
	[4420] = true, -- Overlord Ramtusk
	[4422] = true, -- Agathelos the Raging
	[4421] = true, -- Charlga Razorflank
	-- Blackfathom Deeps
	[4887] = true, -- Ghamoo-ra
	[4831] = true, -- Lady Sarevess
	[6243] = true, -- Gelihast
	[12902] = true, -- Lorgus Jett
	[12876] = true, -- Baron Aquanis
	[4832] = true, -- Twilight Lord Kelris
	[4830] = true, -- Old Serra'kis
	[4829] = true, -- Aku'mai
	-- Dire Maul
	[14354] = true, -- Pusillin
	[11490] = true, -- Zevrim Thornhoof
	[13280] = true, -- Hydrospawn
	[14327] = true, -- Lethtendris
	[11492] = true, -- Alzzin the Wildshaper
	[11489] = true, -- Tendris Warpwood
	[11488] = true, -- Illyanna Ravenoak
	[11487] = true, -- Magister Kalendris
	[11496] = true, -- Immol'thar
	[11486] = true, -- Prince Tortheldrin
	[14326] = true, -- Guard Mol'dar
	[14322] = true, -- Stomper Kreeg
	[14321] = true, -- Guard Fengus
	[14323] = true, -- Guard Slip'kik
	[14325] = true, -- Captain Kromcrush
	[14324] = true, -- Cho'Rush the Observer
	[11501] = true, -- King Gordok
	-- City of Dalaran
	[16488] = true, -- Arcane Anomaly
	[18864] = true, -- Mana Wraith
	[14689] = true, -- Mana Elemental
	-- Maraudon
	[13282] = true, -- Noxxion
	[12258] = true, -- Razorlash
	[12236] = true, -- Lord Vyletongue
	[12225] = true, -- Celebras the Cursed
	[12203] = true, -- Landslide
	[13601] = true, -- Tinkerer Gizlock
	[13596] = true, -- Rotgrip
	[12201] = true, -- Princess Theradras
	-- Hellfire Ramparts
	[17306] = true, [18436] = true, -- Watchkeeper Gargolmar
	[17308] = true, [18433] = true, -- Omor the Unscarred
	[17537] = true, [18434] = true, -- Vazruden
	[17536] = true, [18432] = true, -- Nazan
	-- The Blood Furnace
	[17381] = true, [18621] = true, -- The Maker
	[17380] = true, [18601] = true, -- Broggok
	[17377] = true, [18607] = true, -- Keli'dan the Breaker
	-- The Shattered Halls
	[16807] = true, [20568] = true, -- Grand Warlock Nethekurse
	[20923] = true, [20993] = true, -- Blood Guard Porung
	[16809] = true, [20596] = true, -- Warbringer O'mrogg
	[16808] = true, [20597] = true, -- Warchief Kargath Bladefist
	-- The Slave Pens
	[17941] = true, [19893] = true, -- Mennu the Betrayer
	[17991] = true, [19895] = true, -- Rokmar the Crackler
	[17942] = true, [19894] = true, -- Quagmirran
	-- The Underbog
	[17770] = true, [20169] = true, -- Hungarfen
	[18105] = true, [20168] = true, -- Ghaz'an
	[17826] = true, [20183] = true, -- Swamplord Musel'ek
	[17882] = true, [20184] = true, -- The Black Stalker
	-- The Steamvault
	[17797] = true, [20629] = true, -- Hydromancer Thespia
	[17796] = true, [20630] = true, -- Mekgineer Steamrigger
	[17798] = true, [20633] = true, -- Warlord Kalithresh
	-- Mana-Tombs
	[18341] = true, [20267] = true, -- Pandemonius
	[18343] = true, [20268] = true, -- Tavarok
	[18344] = true, [20266] = true, -- Nexus-Prince Shaffar
	[22930] = true, -- Yor
	-- Auchenai Crypts
	[18371] = true, [20318] = true, -- Shirrak the Dead Watcher
	[18373] = true, [20306] = true, -- Exarch Maladaar
	-- Sethekk Halls
	[18472] = true, [20690] = true, -- Darkweaver Syth
	[18473] = true, [20706] = true, -- Talon King Ikiss
	[23035] = true, -- Anzu
	-- Shadow Labyrinth
	[18731] = true, [20636] = true, -- Ambassador Hellmaw
	[18667] = true, [19300] = true, [19301] = true, [19302] = true, [19303] = true, [19304] = true, [20637] = true, -- Blackheart the Inciter
	[18732] = true, [20653] = true, -- Grandmaster Vorpil
	[18708] = true, [20657] = true, -- Murmur
	-- Old Hillsbrad Foothills
	[17848] = true, [20535] = true, -- Lieutenant Drake
	[17862] = true, [20521] = true, -- Captain Skarloc
	[18096] = true, [20531] = true, -- Epoch Hunter
	-- The Black Morass
	[17879] = true, [20738] = true, -- Chrono Lord Deja
	[17880] = true, [20745] = true, -- Temporus
	[17881] = true, [20737] = true, -- Aeonus
	-- The Mechanar
	[19219] = true, [21533] = true, -- Mechano-Lord Capacitus
	[19221] = true, [21536] = true, -- Nethermancer Sepethrea
	[19220] = true, [21537] = true, -- Pathaleon the Calculator
	[19218] = true, [21525] = true, -- Gatewatcher Gyro-Kill
	[19710] = true, [21526] = true, -- Gatewatcher Iron-Hand
	-- The Botanica
	[17976] = true, [21551] = true, -- Commander Sarannis
	[17975] = true, [21558] = true, -- High Botanist Freywinn
	[17978] = true, [21581] = true, -- Thorngrin the Tender
	[17980] = true, [21559] = true, -- Laj
	[17977] = true, [21582] = true, -- Warp Splinter
	-- The Arcatraz
	[20870] = true, [21626] = true, -- Zereketh the Unbound
	[20885] = true, [21590] = true, -- Dalliah the Doomsayer
	[20886] = true, [21624] = true, -- Wrath-Scryer Soccothrates
	[20912] = true, [21466] = true, [21467] = true, [21599] = true, [21600] = true, [21601] = true, -- Harbinger Skyriss
	-- Magisters' Terrace
	[24723] = true, [25562] = true, -- Selin Fireheart
	[24744] = true, [25573] = true, -- Vexallus
	[24560] = true, [25560] = true, -- Priestess Delrissa
	[19622] = true, [23054] = true, [24664] = true, [24857] = true, -- Kael'thas Sunstrider
}

-- Forever-only dungeons, by English name.
Marker.DUNGEON_BOSS_NAMES = {
	-- Krol'dok Stronghold
	["Slavecrusher Grox"] = true,
	["Twilight Commander Zarmok"] = true,
	["War Handler Ashka"] = true,
	["Nar'gurk"] = true,
	["Bossman Toof"] = true,
	["Overlord Mugg"] = true,
	-- The Drowned City
	["Zul'Alai"] = true,
	["Var'Taka"] = true,
	["Primeval Elemental"] = true,
	["Captain Dreadrise"] = true,
	["Deathless Marrow"] = true,
	["Min'loth the Serpent"] = true,
	-- Alcaz Prison
	["Overseer Wrex"] = true,
	["The Questioner"] = true,
	["Tidemistress Ca'zass"] = true,
	["Katerina the Cleaner"] = true,
	["Blazeroar"] = true,
	-- Ruins of Lordaeron
	["The Baron"] = true,
	["Witherfang"] = true,
	["The Abandoned"] = true,
	["Bjork"] = true,
	["Rath'mael"] = true,
	["Viktor the Vile"] = true,
	-- Blackmaw Hold
	["Withermaw"] = true,
	["Impaan the Imprisoner"] = true,
	["Elder Shaman Bloodmane"] = true,
	["Bonesnout the Unbroken"] = true,
	["Varrox Bleakhoof"] = true,
	["Blackmaw Behemoth"] = true,
	["Unbound Spirit"] = true,
	-- City of Dalaran
	["Atrexis the Grave Knight"] = true,
	["Fel Ancient"] = true,
	["Unstable Sentinel"] = true,
	["Shade of the Archmage"] = true,
	["Mana Devourer"] = true,
	["Arcanic Enigma"] = true,
	-- Shaper's Terrace
	["Titanosaur"] = true,
	["Thunderhoof"] = true,
	["Venomridge"] = true,
	["Direhorn Matriarch"] = true,
	["Cinder"] = true,
	["King Op"] = true,
	["Snowtalon"] = true,
	["Bolt"] = true,
	["Vitrix"] = true,
	["Nanaya"] = true,
	-- Hall of Thanes
	["Faldrim Anvilmar"] = true,
	["Magmatus"] = true,
	["Plunder"] = true,
	["Durgen Dirgehammer"] = true,
	-- Excavation Site: Wetlands
	["Saltspine"] = true,
	["Shadetooth"] = true,
	["Highland Horror"] = true,
	["Relic Guardian"] = true,
}

-- Why each mob is dangerous: 'healer', 'summoner', 'fear', 'caster' or 'dangerous' (hits hard or
-- has a nasty ability). Marker.DANGER_WEIGHTS turns these into kill priority.
Marker.DANGEROUS_MOBS = {
	-- Ragefire Chasm
	[11324] = 'summoner', -- Searing Blade Warlock
	[11322] = 'caster', -- Searing Blade Cultist
	-- Wailing Caverns
	[3840] = 'healer', -- Druid of the Fang
	-- The Deadmines
	[1729] = 'caster', -- Defias Evoker
	[1732] = 'healer', -- Defias Squallshaper
	-- Shadowfang Keep
	[3855] = 'caster', -- Shadowfang Darksoul
	[3851] = 'caster', -- Shadowfang Whitescalp
	[2529] = 'dangerous', -- Son of Arugal
	-- Blackfathom Deeps
	[4803] = 'healer', -- Blackfathom Oracle
	[4802] = 'healer', -- Blackfathom Tide Priestess
	[4809] = 'healer', -- Twilight Acolyte
	[4811] = 'caster', -- Twilight Aquamancer
	[4813] = 'caster', -- Twilight Shadowmage
	[4814] = 'caster', -- Twilight Elementalist
	-- Gnomeregan
	[7849] = 'summoner', -- Mobile Alert System
	[6232] = 'dangerous', -- Arcane Nullifier X-21
	-- Razorfen Kraul
	[4515] = 'healer', -- Death's Head Acolyte
	[4520] = 'caster', -- Razorfen Geomancer
	[4440] = 'summoner', -- Razorfen Totemic
	-- Scarlet Monastery
	[4303] = 'healer', -- Scarlet Abbot
	[4299] = 'healer', -- Scarlet Chaplain
	[4296] = 'healer', -- Scarlet Adept
	[4540] = 'dangerous', -- Scarlet Monk
	[4300] = 'caster', -- Scarlet Wizard
	[4294] = 'caster', -- Scarlet Sorcerer
	[4291] = 'caster', -- Scarlet Diviner
	[4297] = 'summoner', -- Scarlet Conjuror
	[4289] = 'caster', -- Scarlet Evoker
	[4302] = 'dangerous', [29080] = 'dangerous', -- Scarlet Champion
	-- Razorfen Downs
	[7337] = 'summoner', -- Death's Head Necromancer
	[7342] = 'summoner', -- Skeletal Summoner
	-- Uldaman
	[4852] = 'healer', -- Stonevault Oracle
	[4848] = 'caster', -- Shadowforge Darkcaster
	[4853] = 'caster', -- Stonevault Geomancer
	-- Zul'Farrak
	[5650] = 'healer', -- Sandfury Witch Doctor
	[5648] = 'caster', -- Sandfury Shadowcaster
	[7247] = 'caster', -- Sandfury Soul Eater
	-- Maraudon
	[11793] = 'caster', -- Celebrian Dryad
	-- The Temple of Atal'Hakkar
	[5269] = 'healer', -- Atal'ai Priest
	[5259] = 'summoner', -- Atal'ai Witch Doctor
	[5273] = 'healer', -- Atal'ai High Priest
	-- Blackrock Depths
	[8894] = 'healer', -- Anvilrage Medic
	[8900] = 'caster', -- Doomforge Arcanasmith
	[9956] = 'caster', -- Shadowforge Flame Keeper
	-- Blackrock Spire
	[9240] = 'healer', -- Smolderthorn Shadow Priest
	[9239] = 'healer', -- Smolderthorn Mystic
	[9198] = 'healer', -- Spirestone Mystic
	[9261] = 'caster', -- Firebrand Darkweaver
	[9262] = 'caster', -- Firebrand Invoker
	[9818] = 'summoner', -- Blackhand Summoner
	[9817] = 'fear', -- Blackhand Dreadweaver
	[10083] = 'caster', -- Rage Talon Flamescale
	-- Dire Maul
	[11466] = 'summoner', -- Highborne Summoner
	[11444] = 'caster', -- Gordok Mage-Lord
	[11457] = 'caster', -- Wildspawn Hellcaller
	-- Scholomance
	[11582] = 'summoner', -- Scholomance Dark Summoner
	[10477] = 'summoner', -- Scholomance Necromancer
	[10469] = 'caster', -- Scholomance Adept
	[10470] = 'caster', -- Scholomance Neophyte
	[10471] = 'healer', -- Scholomance Acolyte
	-- Stratholme
	[10423] = 'healer', -- Crimson Priest
	[10425] = 'caster', -- Crimson Battle Mage
	[10422] = 'caster', -- Crimson Sorcerer
	[10419] = 'summoner', -- Crimson Conjuror
	[10426] = 'dangerous', -- Crimson Inquisitor
	[10398] = 'caster', -- Thuzadin Shadowcaster
	[10400] = 'summoner', -- Thuzadin Necromancer
	-- Hellfire Ramparts
	[17269] = 'caster', [18049] = 'caster', -- Bleeding Hollow Darkcaster
	[17259] = 'dangerous', [18053] = 'dangerous', -- Bonechewer Hungerer
	-- The Blood Furnace
	[17395] = 'summoner', [18617] = 'summoner', -- Shadowmoon Summoner
	[17414] = 'dangerous', [18618] = 'dangerous', -- Shadowmoon Technician
	[17371] = 'caster', [18619] = 'caster', -- Shadowmoon Warlock
	-- The Slave Pens
	[17961] = 'caster', [19887] = 'caster', -- Coilfang Enchantress
	[21128] = 'fear', [21841] = 'fear', -- Coilfang Ray
	[17959] = 'dangerous', [19889] = 'dangerous', -- Coilfang Slavehandler
	-- The Underbog
	[17730] = 'healer', [20177] = 'healer', -- Murkblood Healer
	[17771] = 'caster', [20179] = 'caster', -- Murkblood Oracle
	-- Mana-Tombs
	[18317] = 'healer', [20257] = 'healer', -- Ethereal Priest
	[18331] = 'caster', [20256] = 'caster', -- Ethereal Darkcaster
	[18315] = 'caster', [20261] = 'caster', -- Ethereal Theurgist
	[18313] = 'summoner', [20259] = 'summoner', -- Ethereal Sorcerer
	[18312] = 'caster', [20260] = 'caster', -- Ethereal Spellbinder
	-- Auchenai Crypts
	[18493] = 'healer', [20301] = 'healer', -- Auchenai Soulpriest
	[18503] = 'dangerous', [20309] = 'dangerous', -- Phantasmal Possessor
	-- Sethekk Halls
	[18327] = 'summoner', [20691] = 'summoner', -- Time-Lost Controller
	[18328] = 'caster', [20694] = 'caster', -- Sethekk Oracle
	[18325] = 'fear', [20695] = 'fear', -- Sethekk Prophet
	-- Shadow Labyrinth
	[18633] = 'healer', [20638] = 'healer', -- Cabal Acolyte
	[18637] = 'healer', [20646] = 'healer', -- Cabal Shadow Priest
	[18639] = 'dangerous', [20647] = 'dangerous', -- Cabal Spellbinder
	[18634] = 'summoner', [20648] = 'summoner', -- Cabal Summoner
	[18640] = 'caster', [20649] = 'caster', -- Cabal Warlock
	[18848] = 'fear', [20656] = 'fear', -- Malicious Instructor
	-- Old Hillsbrad Foothills
	[17833] = 'healer', [20530] = 'healer', -- Durnholde Warden
	[18934] = 'caster', [20525] = 'caster', -- Durnholde Mage
	-- The Black Morass
	[21104] = 'caster', [21148] = 'caster', [22170] = 'caster', [22171] = 'caster', -- Rift Keeper
	[17892] = 'caster', [20741] = 'caster', [21136] = 'caster', [22165] = 'caster', -- Infinite Chronomancer
	-- The Steamvault
	[17801] = 'fear', [20623] = 'fear', -- Coilfang Siren
	[17803] = 'healer', [20622] = 'healer', -- Coilfang Oracle
	[17722] = 'caster', [20625] = 'caster', -- Coilfang Sorceress
	-- The Shattered Halls
	[16700] = 'summoner', [20589] = 'summoner', -- Shattered Hand Legionnaire
	[16594] = 'healer', [20576] = 'healer', -- Shadowmoon Acolyte
	[17694] = 'caster', [20577] = 'caster', -- Shadowmoon Darkcaster
	[16523] = 'dangerous', [20591] = 'dangerous', -- Shattered Hand Savage
	-- The Mechanar
	[20990] = 'healer', [21523] = 'healer', -- Bloodwarder Physician
	[19168] = 'caster', [21539] = 'caster', -- Sunseeker Astromage
	[20059] = 'summoner', [21541] = 'summoner', -- Sunseeker Netherbinder
	[19716] = 'dangerous', [21531] = 'dangerous', -- Mechanar Tinkerer
	-- The Botanica
	[19633] = 'healer', [21547] = 'healer', -- Bloodwarder Mender
	[18421] = 'caster', [21577] = 'caster', -- Sunseeker Researcher
	[19486] = 'caster', [21572] = 'caster', -- Sunseeker Chemist
	[19505] = 'healer', [21571] = 'healer', -- Sunseeker Channeler
	-- The Arcatraz
	[21702] = 'healer', [22346] = 'healer', -- Ethereum Life-Binder
	[20883] = 'dangerous', [21615] = 'dangerous', -- Spiteful Temptress
	[20879] = 'caster', [21595] = 'caster', -- Eredar Soul-Eater
	-- Magisters' Terrace
	[24687] = 'healer', [25570] = 'healer', -- Sunblade Physician
	[24686] = 'caster', [25572] = 'caster', -- Sunblade Warlock
	[24685] = 'caster', [25569] = 'caster', -- Sunblade Magister
	[24696] = 'caster', [25547] = 'caster', -- Coilskar Witch
	[24697] = 'dangerous', [25563] = 'dangerous', -- Sister of Torment
}
