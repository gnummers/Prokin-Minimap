-- Experimental Auction House upgrade scanner for WoW Forever.
-- Scans the modern Auction House for armor and weapons in a level range and lists the best
-- upgrade and best value per equipment slot.
-- Items are scored with Pawn scales or RestedXP Guides stat weights, read at runtime from those
-- addons when they are loaded. The Options button picks the weights, class, spec and level range.

local upgrades = _G.ProkinMinimapAuctionUpgrades or {}
_G.ProkinMinimapAuctionUpgrades = upgrades

-- Forever uses the modern Auction House (AuctionHouseFrame / C_AuctionHouse).
-- Clients with the legacy AuctionFrame are covered by RestedXP Guides' own scanner.
if _G.QueryAuctionItems or type(C_AuctionHouse) ~= 'table' or not C_AuctionHouse.SendBrowseQuery then
	return
end

local TAB_ID = 'ProkinUpgrades'
-- Short name: Auctionator and TSM already fill most of the Auction House tab strip
local TAB_TEXT = 'Prokin'
local PANEL_TITLE = 'Prokin Minimap - Auction House Upgrades (experimental)'
local SCAN_TIMEOUT = 20
local ROW_HEIGHT = 24
local REANALYZE_DELAY = 0.3
local MAX_LEVEL = 60

local SOURCE_PAWN = 'pawn'
local SOURCE_RXP = 'rxp'
local SOURCE_LABELS = { [SOURCE_PAWN] = 'Pawn', [SOURCE_RXP] = 'RestedXP Guides' }

local GetItemInfoCompat = (type(C_Item) == 'table' and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstantCompat = (type(C_Item) == 'table' and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemStatsCompat = (type(C_Item) == 'table' and C_Item.GetItemStats) or GetItemStats

-- Equip location -> inventory slots it can occupy
local SLOTS_BY_EQUIP_LOC = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 },
	INVTYPE_RELIC = { 18 },
}

local QUERY_CLASSES = { Enum.ItemClass.Armor, Enum.ItemClass.Weapon }

local SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

local SLOT_NAMES = {
	[1] = 'HEADSLOT', [2] = 'NECKSLOT', [3] = 'SHOULDERSLOT', [5] = 'CHESTSLOT', [6] = 'WAISTSLOT',
	[7] = 'LEGSSLOT', [8] = 'FEETSLOT', [9] = 'WRISTSLOT', [10] = 'HANDSSLOT', [11] = 'FINGER0SLOT',
	[12] = 'FINGER1SLOT', [13] = 'TRINKET0SLOT', [14] = 'TRINKET1SLOT', [15] = 'BACKSLOT',
	[16] = 'MAINHANDSLOT', [17] = 'SECONDARYHANDSLOT', [18] = 'RANGEDSLOT',
}

-- Talent specializations per class, so every spec can be chosen even where a weight source
-- has no table of its own for it
local CLASS_SPECS = {
	WARRIOR = { 'Arms', 'Fury', 'Protection' },
	PALADIN = { 'Holy', 'Protection', 'Retribution' },
	HUNTER = { 'Beast Mastery', 'Marksmanship', 'Survival' },
	ROGUE = { 'Assassination', 'Combat', 'Subtlety' },
	PRIEST = { 'Discipline', 'Holy', 'Shadow' },
	SHAMAN = { 'Elemental', 'Enhancement', 'Restoration' },
	MAGE = { 'Arcane', 'Fire', 'Frost' },
	WARLOCK = { 'Affliction', 'Demonology', 'Destruction' },
	DRUID = { 'Balance', 'Feral Combat', 'Restoration' },
}

local CLASS_ORDER = { 'WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID' }

-- Classic armor and weapon proficiencies, used when the Auction House "usable only" filter
-- cannot be (another class, or a level range above the character's level).
-- Armor subclasses: 0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem.
-- Weapon subclasses: 0/1 axes, 2 bows, 3 guns, 4/5 maces, 6 polearms, 7/8 swords, 10 staves,
-- 13 fist weapons, 14 miscellaneous, 15 daggers, 16 thrown, 18 crossbows, 19 wands.
local PROFICIENCY = {
	WARRIOR = { armor = { 0, 1, 2, 3, 6 }, plateAt = 40, weapons = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 14, 15, 16, 18 } },
	PALADIN = { armor = { 0, 1, 2, 3, 6, 7 }, plateAt = 40, weapons = { 0, 1, 4, 5, 6, 7, 8, 14 } },
	HUNTER = { armor = { 0, 1, 2 }, mailAt = 40, weapons = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 14, 15, 16, 18 } },
	ROGUE = { armor = { 0, 1, 2 }, weapons = { 2, 3, 4, 7, 13, 14, 15, 16, 18 } },
	PRIEST = { armor = { 0, 1 }, weapons = { 4, 10, 14, 15, 19 } },
	SHAMAN = { armor = { 0, 1, 2, 6, 9 }, mailAt = 40, weapons = { 0, 1, 4, 5, 10, 13, 14, 15 } },
	MAGE = { armor = { 0, 1 }, weapons = { 7, 10, 14, 15, 19 } },
	WARLOCK = { armor = { 0, 1 }, weapons = { 7, 10, 14, 15, 19 } },
	DRUID = { armor = { 0, 1, 2, 8 }, weapons = { 4, 5, 10, 13, 14, 15 } },
}

local RANGED_EQUIP_LOCS = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- GetItemStats keys that RestedXP's weight tables name differently
local STAT_ALIASES = {
	ITEM_MOD_SPELL_POWER_SHORT = 'STAT_SPELLDAMAGE',
	ITEM_MOD_SPELL_DAMAGE_DONE = 'STAT_SPELLDAMAGE',
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 'STAT_SPELLDAMAGE',
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = 'ITEM_MOD_SPELL_HEALING_DONE',
}

-- Stats the options can filter on. Each lists the C_Item.GetItemStats keys and Pawn's stat names
-- (Pawn also reads equip lines such as +12 Attack Power from the tooltip).
local MAX_STAT_FILTERS = 6
local STAT_FILTERS = {
	{ id = 'strength', label = 'Strength', keys = { 'ITEM_MOD_STRENGTH_SHORT' }, pawn = { 'Strength' } },
	{ id = 'agility', label = 'Agility', keys = { 'ITEM_MOD_AGILITY_SHORT' }, pawn = { 'Agility' } },
	{ id = 'stamina', label = 'Stamina', keys = { 'ITEM_MOD_STAMINA_SHORT' }, pawn = { 'Stamina' } },
	{ id = 'intellect', label = 'Intellect', keys = { 'ITEM_MOD_INTELLECT_SHORT' }, pawn = { 'Intellect' } },
	{ id = 'spirit', label = 'Spirit', keys = { 'ITEM_MOD_SPIRIT_SHORT' }, pawn = { 'Spirit' } },
	{ id = 'armor', label = 'Armor', keys = { 'RESISTANCE0_NAME' }, pawn = { 'Armor' } },
	{ id = 'attackPower', label = 'Attack Power', keys = { 'ITEM_MOD_ATTACK_POWER_SHORT' }, pawn = { 'Ap' } },
	{ id = 'rangedAttackPower', label = 'Ranged Attack Power', keys = { 'ITEM_MOD_RANGED_ATTACK_POWER_SHORT' }, pawn = { 'Rap' } },
	{ id = 'spellDamage', label = 'Spell Damage', keys = { 'ITEM_MOD_SPELL_POWER_SHORT', 'ITEM_MOD_SPELL_DAMAGE_DONE', 'ITEM_MOD_SPELL_DAMAGE_DONE_SHORT' }, pawn = { 'SpellDamage', 'SpellPower' } },
	{ id = 'healing', label = 'Healing', keys = { 'ITEM_MOD_SPELL_HEALING_DONE', 'ITEM_MOD_SPELL_HEALING_DONE_SHORT' }, pawn = { 'Healing' } },
	{ id = 'hit', label = 'Hit', keys = { 'ITEM_MOD_HIT_RATING_SHORT' }, pawn = { 'HitRating' } },
	{ id = 'crit', label = 'Critical Strike', keys = { 'ITEM_MOD_CRIT_RATING_SHORT' }, pawn = { 'CritRating' } },
	{ id = 'spellHit', label = 'Spell Hit', keys = { 'ITEM_MOD_HIT_SPELL_RATING_SHORT' }, pawn = { 'SpellHitRating' } },
	{ id = 'spellCrit', label = 'Spell Critical Strike', keys = { 'ITEM_MOD_CRIT_SPELL_RATING_SHORT' }, pawn = { 'SpellCritRating' } },
	{ id = 'defense', label = 'Defense', keys = { 'ITEM_MOD_DEFENSE_SKILL_RATING_SHORT' }, pawn = { 'DefenseRating' } },
	{ id = 'dodge', label = 'Dodge', keys = { 'ITEM_MOD_DODGE_RATING_SHORT' }, pawn = { 'DodgeRating' } },
	{ id = 'parry', label = 'Parry', keys = { 'ITEM_MOD_PARRY_RATING_SHORT' }, pawn = { 'ParryRating' } },
	{ id = 'block', label = 'Block', keys = { 'ITEM_MOD_BLOCK_RATING_SHORT', 'ITEM_MOD_BLOCK_VALUE_SHORT' }, pawn = { 'BlockRating', 'BlockValue' } },
	{ id = 'mp5', label = 'Mana per 5 sec', keys = { 'ITEM_MOD_POWER_REGEN0_SHORT', 'ITEM_MOD_MANA_REGENERATION_SHORT' }, pawn = { 'Mp5' } },
	{ id = 'hp5', label = 'Health per 5 sec', keys = { 'ITEM_MOD_HEALTH_REGEN_SHORT' }, pawn = { 'Hp5' } },
	{ id = 'dps', label = 'Weapon DPS', keys = { 'ITEM_MOD_DAMAGE_PER_SECOND_SHORT' }, pawn = { 'Dps', 'MeleeDps', 'RangedDps' } },
	{ id = 'fireResist', label = 'Fire Resistance', keys = { 'RESISTANCE2_NAME' }, pawn = { 'FireResist', 'AllResist' } },
	{ id = 'natureResist', label = 'Nature Resistance', keys = { 'RESISTANCE3_NAME' }, pawn = { 'NatureResist', 'AllResist' } },
	{ id = 'frostResist', label = 'Frost Resistance', keys = { 'RESISTANCE4_NAME' }, pawn = { 'FrostResist', 'AllResist' } },
	{ id = 'shadowResist', label = 'Shadow Resistance', keys = { 'RESISTANCE5_NAME' }, pawn = { 'ShadowResist', 'AllResist' } },
	{ id = 'arcaneResist', label = 'Arcane Resistance', keys = { 'RESISTANCE6_NAME' }, pawn = { 'ArcaneResist', 'AllResist' } },
}
local STAT_FILTERS_BY_ID = {}
for _, stat in ipairs(STAT_FILTERS) do
	STAT_FILTERS_BY_ID[stat.id] = stat
end

local eventFrame = CreateFrame('Frame')
local panel
local tabButton
local selectingTab
local scan = {
	active = false,
	sentQuery = false,
	stopRequested = false,
	generation = 0,
	resultCount = 0,
	queryIndex = 1,
	queryBaseCount = 0,
	lastEventAt = 0,
	items = {},
}
local results = {}
-- Active scoring setup, built from the saved options by ResolveScorer
local scorer
local scorerProblem
local reanalyzeQueued

local function IsSecret(value)
	return type(issecretvalue) == 'function' and issecretvalue(value)
end

local function GetSlotName(slotID)
	return _G[SLOT_NAMES[slotID] or ''] or ('Slot ' .. slotID)
end

local function GetClassLabel(classToken)
	local names = _G.LOCALIZED_CLASS_NAMES_MALE
	return names and names[classToken] or classToken
end

local function FormatMoney(copper)
	if type(GetMoneyString) == 'function' then
		return GetMoneyString(copper, true)
	end
	return string.format('%dg %ds %dc', math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function Contains(list, value)
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Saved options (per character)
---------------------------------------------------------------------------

local function GetOptions()
	if type(ProkinMinimapDB) ~= 'table' then
		ProkinMinimapDB = {}
	end
	if type(ProkinMinimapDB.auctionUpgrades) ~= 'table' then
		ProkinMinimapDB.auctionUpgrades = {}
	end

	local name, realm = UnitName('player'), GetRealmName()
	local key = tostring(name) .. '-' .. tostring(realm)
	local options = ProkinMinimapDB.auctionUpgrades[key]
	if type(options) ~= 'table' then
		options = {}
		ProkinMinimapDB.auctionUpgrades[key] = options
	end
	return options
end

---------------------------------------------------------------------------
-- Weight sources
---------------------------------------------------------------------------

-- Pawn keeps its own PawnIsInitialized flag local, so check for its loaded scale table instead
local function IsPawnReady()
	return type(PawnGetItemData) == 'function' and type(PawnGetSingleValueFromItem) == 'function'
		and type(PawnGetAllScalesEx) == 'function' and type(PawnCommon) == 'table' and type(PawnCommon.Scales) == 'table'
		and next(PawnCommon.Scales) ~= nil
end

local function GetPawnScales()
	local ok, scales = pcall(PawnGetAllScalesEx)
	return ok and type(scales) == 'table' and scales or {}
end

local function GetRestedXP()
	local aceAddon = LibStub and LibStub('AceAddon-3.0', true)
	local rxp = aceAddon and aceAddon:GetAddon('RXPGuides', true)
	if rxp and type(rxp.statWeights) == 'table' then
		return rxp
	end
end

local function GetAvailableSources()
	local sources = {}
	if IsPawnReady() then
		table.insert(sources, SOURCE_PAWN)
	end
	if GetRestedXP() then
		table.insert(sources, SOURCE_RXP)
	end
	return sources
end

-- Pawn's built-in scales are named like '"Classic":WARRIOR1'; custom scales have no class
local function GetPawnScaleClass(scaleName)
	return type(scaleName) == 'string' and scaleName:match('^"[^"]+":(%u+)%d*$') or nil
end

local function GetPawnClasses()
	local found = {}
	for _, scale in ipairs(GetPawnScales()) do
		local classToken = GetPawnScaleClass(scale.Name)
		if classToken then
			found[classToken] = true
		end
	end
	local classes = {}
	for _, classToken in ipairs(CLASS_ORDER) do
		if found[classToken] then
			table.insert(classes, classToken)
		end
	end
	return classes
end

-- Spec choices for Pawn: that class's scales first, then custom scales
local function GetPawnSpecs(classToken)
	local classScales, customScales = {}, {}
	for _, scale in ipairs(GetPawnScales()) do
		local scaleClass = GetPawnScaleClass(scale.Name)
		local entry = { id = scale.Name, label = scale.LocalizedName or scale.Name, visible = scale.IsVisible }
		if scaleClass == classToken then
			table.insert(classScales, entry)
		elseif not scaleClass and not scale.IsProvider then
			entry.label = entry.label .. ' (custom)'
			table.insert(customScales, entry)
		end
	end
	table.sort(classScales, function(a, b)
		return a.id < b.id
	end)
	for _, entry in ipairs(customScales) do
		table.insert(classScales, entry)
	end
	return classScales
end

local function GetRxpKind(rxp)
	local profile = rxp.settings and rxp.settings.profile or {}
	return profile.hardcore and 'Hardcore' or 'Speedrun'
end

local function GetRxpClasses(rxp)
	local found = {}
	local kind = GetRxpKind(rxp)
	for _, weights in pairs(rxp.statWeights) do
		if type(weights) == 'table' and type(weights.Class) == 'string' and weights.Kind == kind then
			found[weights.Class:upper()] = true
		end
	end
	local classes = {}
	for _, classToken in ipairs(CLASS_ORDER) do
		if found[classToken] then
			table.insert(classes, classToken)
		end
	end
	return classes
end

-- Spec choices for RestedXP: every talent spec of the class. RestedXP only ships weights for some
-- specs, so the others use the class's general weights (or another spec's) and say so.
-- Weights come from the level bracket containing `level` (or the highest bracket starting below it).
local function GetRxpSpecs(rxp, classToken, level)
	local kind = GetRxpKind(rxp)
	local bySpec = {}
	for _, weights in pairs(rxp.statWeights) do
		if type(weights) == 'table' and type(weights.Class) == 'string' and weights.Class:upper() == classToken
			and weights.Kind == kind and (weights.MIN_LEVEL or 0) <= level then
			local specKey = type(weights.Spec) == 'string' and weights.Spec:match('^%s*(.-)%s*$') or ''
			local current = bySpec[specKey]
			local inBracket = level <= (weights.MAX_LEVEL or 999)
			if not current or (inBracket and not current.inBracket)
				or (inBracket == current.inBracket and (weights.MIN_LEVEL or 0) > (current.weights.MIN_LEVEL or 0)) then
				bySpec[specKey] = { weights = weights, inBracket = inBracket }
			end
		end
	end
	if not next(bySpec) then
		return {}
	end

	local ownSpecs = {}
	for specKey in pairs(bySpec) do
		if specKey ~= '' then
			table.insert(ownSpecs, specKey)
		end
	end
	table.sort(ownSpecs)
	local fallbackKey = bySpec[''] and '' or ownSpecs[1]
	local fallbackName = fallbackKey == '' and 'general' or fallbackKey

	local specs, listed = {}, {}
	for _, specName in ipairs(CLASS_SPECS[classToken] or {}) do
		local match = bySpec[specName]
		if match then
			table.insert(specs, { id = specName, label = specName, weights = match.weights })
		else
			table.insert(specs, {
				id = specName,
				label = string.format('%s (RestedXP %s weights)', specName, fallbackName),
				weights = bySpec[fallbackKey].weights,
			})
		end
		listed[specName] = true
	end
	-- Extra RestedXP tables such as the Mage AOE leveling weights
	for _, specName in ipairs(ownSpecs) do
		if not listed[specName] then
			table.insert(specs, { id = specName, label = specName .. ' (RestedXP)', weights = bySpec[specName].weights })
		end
	end
	return specs
end

local function GuessSpecFromTalents(specs)
	if type(GetNumTalentTabs) ~= 'function' or type(GetTalentTabInfo) ~= 'function' then
		return nil
	end

	local bestName, bestPoints = nil, 0
	for tabIndex = 1, GetNumTalentTabs() do
		local first, second, third, _, fifth = GetTalentTabInfo(tabIndex)
		-- Classic returns (name, icon, pointsSpent); newer clients return (id, name, description, icon, pointsSpent)
		local tabName = type(third) == 'number' and first or second
		local points = type(third) == 'number' and third or fifth
		if type(tabName) == 'string' and type(points) == 'number' and points > bestPoints then
			for _, spec in ipairs(specs) do
				if spec.id == tabName or spec.label:find(tabName, 1, true) or tabName:find(spec.id, 1, true) then
					bestName, bestPoints = spec.id, points
				end
			end
		end
	end
	return bestName
end

local function FindEntry(list, id)
	for _, entry in ipairs(list) do
		if entry.id == id then
			return entry
		end
	end
end

-- Builds the scorer from the saved options, falling back to the character's own class and level.
-- Returns the scorer plus the lists the options panel cycles through.
local function ResolveScorer()
	local options = GetOptions()
	local _, playerClass = UnitClass('player')
	local playerLevel = UnitLevel('player')

	local sources = GetAvailableSources()
	if #sources == 0 then
		return nil, 'Install Pawn or RestedXP Guides: the upgrade scan scores items with their stat weights.', {}
	end
	local source = Contains(sources, options.source) and options.source or sources[1]

	local rxp = source == SOURCE_RXP and GetRestedXP() or nil
	local classes = source == SOURCE_PAWN and GetPawnClasses() or GetRxpClasses(rxp)
	local classToken = options.class
	if not Contains(classes, classToken) then
		classToken = Contains(classes, playerClass) and playerClass or classes[1]
	end
	if not classToken then
		return nil, SOURCE_LABELS[source] .. ' has no weights for any class.', { sources = sources, source = source }
	end
	local ownClass = classToken == playerClass

	local minLevel = tonumber(options.minLevel)
	local maxLevel = tonumber(options.maxLevel) or playerLevel
	maxLevel = math.max(1, math.min(MAX_LEVEL, maxLevel))
	if minLevel then
		minLevel = math.max(0, math.min(maxLevel, minLevel))
	end

	local specs = source == SOURCE_PAWN and GetPawnSpecs(classToken) or GetRxpSpecs(rxp, classToken, maxLevel)
	local lists = { sources = sources, source = source, classes = classes, class = classToken, specs = specs }
	if #specs == 0 then
		return nil, string.format('%s has no weights for a level %d %s.', SOURCE_LABELS[source], maxLevel, GetClassLabel(classToken)), lists
	end

	local spec = FindEntry(specs, options.spec)
	if not spec then
		if source == SOURCE_PAWN then
			-- Pawn enables the character's own class scale by default
			for _, entry in ipairs(specs) do
				if ownClass and entry.visible then
					spec = entry
					break
				end
			end
		else
			local profile = rxp.settings and rxp.settings.profile or {}
			spec = FindEntry(specs, profile.itemUpgradeSpec) or (ownClass and FindEntry(specs, GuessSpecFromTalents(specs)))
		end
		spec = spec or specs[1]
	end
	lists.spec = spec.id

	local label
	if source == SOURCE_PAWN then
		label = 'Pawn: ' .. spec.label
	else
		label = string.format('RestedXP %s - %s', tostring(spec.weights.Title or GetClassLabel(classToken)), spec.label)
	end

	return {
		source = source,
		classToken = classToken,
		ownClass = ownClass,
		specId = spec.id,
		weights = spec.weights,
		minLevel = minLevel,
		maxLevel = maxLevel,
		-- Blizzard's filter checks the character, so only use it when that matches the options
		usableFilter = ownClass and maxLevel <= playerLevel,
		label = label,
	}, nil, lists
end

---------------------------------------------------------------------------
-- Item scoring
---------------------------------------------------------------------------

local function ScoreWithRxp(itemLink, equipLoc)
	local stats = GetItemStatsCompat(itemLink)
	if type(stats) ~= 'table' then
		return 0
	end

	local score = 0
	for key, value in pairs(stats) do
		if type(value) == 'number' then
			local weightKey = STAT_ALIASES[key] or key
			if weightKey == 'ITEM_MOD_DAMAGE_PER_SECOND_SHORT' and RANGED_EQUIP_LOCS[equipLoc] then
				weightKey = 'ITEM_MOD_DAMAGE_PER_SECOND_SHORT_RANGED'
			end
			local weight = scorer.weights[weightKey]
			if type(weight) == 'number' then
				score = score + weight * value
			end
		end
	end
	return score
end

local function ScoreWithPawn(itemLink)
	local item = PawnGetItemData(itemLink)
	if not item then
		return 0
	end
	local value = PawnGetSingleValueFromItem(item, scorer.specId)
	return type(value) == 'number' and value or 0
end

-- Returns the item's weighted score, or nil while item data is still loading
local function ScoreItem(itemLink, equipLoc)
	if not itemLink or IsSecret(itemLink) or not scorer then
		return nil
	end
	local _, fullLink = GetItemInfoCompat(itemLink)
	if not fullLink then
		return nil
	end

	if scorer.source == SOURCE_PAWN then
		return ScoreWithPawn(fullLink)
	end
	return ScoreWithRxp(fullLink, equipLoc)
end

local function GetEquippedScore(slotID)
	local link = GetInventoryItemLink('player', slotID)
	if not link then
		return 0
	end
	local _, _, _, equipLoc = GetItemInfoInstantCompat(link)
	return ScoreItem(link, equipLoc) or 0
end

-- How much better the item is than what it would replace, and which slot it goes in
local function GetUpgradeForItem(score, equipLoc)
	local slots = SLOTS_BY_EQUIP_LOC[equipLoc]
	if not slots then
		return nil
	end

	-- Another class's gear is not compared with what this character is wearing
	if not scorer.ownClass then
		return score, slots[1]
	end

	if equipLoc == 'INVTYPE_2HWEAPON' then
		return score - (GetEquippedScore(16) + GetEquippedScore(17)), 16
	end

	-- Rings and trinkets replace the weaker of the two
	local bestSlot, lowestEquipped
	for _, slotID in ipairs(slots) do
		local equippedScore = GetEquippedScore(slotID)
		if not lowestEquipped or equippedScore < lowestEquipped then
			bestSlot, lowestEquipped = slotID, equippedScore
		end
	end
	return score - lowestEquipped, bestSlot
end

local function IsProficient(itemClassID, subClassID)
	local proficiency = PROFICIENCY[scorer.classToken]
	if not proficiency or type(subClassID) ~= 'number' then
		return true
	end
	if itemClassID == Enum.ItemClass.Armor then
		if Contains(proficiency.armor, subClassID) then
			return true
		end
		if subClassID == 3 and proficiency.mailAt and scorer.maxLevel >= proficiency.mailAt then
			return true
		end
		return subClassID == 4 and proficiency.plateAt ~= nil and scorer.maxLevel >= proficiency.plateAt
	end
	if itemClassID == Enum.ItemClass.Weapon then
		return Contains(proficiency.weapons, subClassID)
	end
	return true
end

-- Valid saved stat filters, in the order they were added
local function GetStatFilters()
	local filters = {}
	for _, filter in ipairs(GetOptions().statFilters or {}) do
		if type(filter) == 'table' and STAT_FILTERS_BY_ID[filter.stat] then
			table.insert(filters, filter)
		end
	end
	return filters
end

-- Largest amount of the stat found on the item, from Pawn's reading and the game's stat list
local function GetItemStatAmount(stat, gameStats, pawnStats)
	local amount = 0
	for _, key in ipairs(stat.keys) do
		local value = gameStats and gameStats[key]
		if type(value) == 'number' and value > amount then
			amount = value
		end
	end
	for _, key in ipairs(stat.pawn) do
		local value = pawnStats and pawnStats[key]
		if type(value) == 'number' and value > amount then
			amount = value
		end
	end
	return amount
end

local function PassesStatFilters(itemLink, filters)
	if #filters == 0 then
		return true
	end

	local gameStats = GetItemStatsCompat(itemLink)
	local pawnStats
	if IsPawnReady() then
		local item = PawnGetItemData(itemLink)
		pawnStats = item and item.Stats
	end

	local matchAll = GetOptions().statMatch == 'all'
	for _, filter in ipairs(filters) do
		local amount = GetItemStatAmount(STAT_FILTERS_BY_ID[filter.stat], gameStats, pawnStats)
		local passes = amount > 0 and amount >= (tonumber(filter.min) or 0)
		if passes and not matchAll then
			return true
		end
		if not passes and matchAll then
			return false
		end
	end
	return matchAll
end

local function DescribeStatFilters()
	local filters = GetStatFilters()
	if #filters == 0 then
		return nil
	end
	local parts = {}
	for _, filter in ipairs(filters) do
		local label = STAT_FILTERS_BY_ID[filter.stat].label
		if tonumber(filter.min) then
			label = string.format('%s %d+', label, tonumber(filter.min))
		end
		table.insert(parts, label)
	end
	local joiner = GetOptions().statMatch == 'all' and ' and ' or ' or '
	return table.concat(parts, joiner)
end

---------------------------------------------------------------------------
-- Analysis
---------------------------------------------------------------------------

local RefreshPanel

local function Analyze()
	results = {}
	local pending = 0
	if not scorer then
		return pending
	end

	local statFilters = GetStatFilters()
	for itemID, entry in pairs(scan.items) do
		local itemLink = 'item:' .. itemID
		local _, _, _, equipLoc, icon, itemClassID, subClassID = GetItemInfoInstantCompat(itemID)
		local name, fullLink, _, _, requiredLevel = GetItemInfoCompat(itemLink)

		if not name then
			pending = pending + 1
			if type(C_Item) == 'table' and C_Item.RequestLoadItemDataByID then
				C_Item.RequestLoadItemDataByID(itemID)
			end
		elseif IsProficient(itemClassID, subClassID)
			and (requiredLevel or 0) <= scorer.maxLevel and (requiredLevel or 0) >= (scorer.minLevel or 0)
			and PassesStatFilters(fullLink or itemLink, statFilters) then
			local score = ScoreItem(itemLink, equipLoc)
			if score == nil then
				pending = pending + 1
			elseif score > 0 then
				local gain, slotID = GetUpgradeForItem(score, equipLoc)
				if gain and gain > 0 and slotID then
					local slot = results[slotID] or {}
					results[slotID] = slot
					local candidate = {
						itemID = itemID,
						itemLink = fullLink or itemLink,
						name = name,
						icon = icon,
						gain = gain,
						price = entry.price,
						valuePerGold = gain / math.max(entry.price / 10000, 0.01),
						browseResult = entry.browseResult,
					}
					if not slot.best or candidate.gain > slot.best.gain then
						slot.best = candidate
					end
					if not slot.value or candidate.valuePerGold > slot.value.valuePerGold then
						slot.value = candidate
					end
				end
			end
		end
	end

	return pending
end

local function CountResultSlots()
	local count = 0
	for _ in pairs(results) do
		count = count + 1
	end
	return count
end

local function QueueReanalyze()
	if reanalyzeQueued or scan.active then
		return
	end
	reanalyzeQueued = true
	C_Timer.After(REANALYZE_DELAY, function()
		reanalyzeQueued = nil
		if scan.active or not next(scan.items) then
			return
		end
		Analyze()
		if RefreshPanel then
			RefreshPanel()
		end
	end)
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

local function SetStatus(text)
	if panel then
		panel.Status:SetText(text or '')
	end
end

local function UpdateScanButton()
	if not panel then
		return
	end
	if scan.active then
		panel.ScanButton:SetText(scan.stopRequested and 'Stopping...' or 'Stop')
		panel.ScanButton:SetEnabled(not scan.stopRequested)
	else
		panel.ScanButton:SetText('Scan')
		panel.ScanButton:SetEnabled(scorer ~= nil)
	end
end

local function FinishScan(stopped)
	scan.active = false
	scan.sentQuery = false
	scan.stopRequested = false
	scan.generation = scan.generation + 1
	scan.hasScanned = true

	local pending = Analyze()
	local status = string.format('%s %d items, upgrades for %d slot(s).', stopped and 'Stopped after' or 'Scanned', scan.resultCount, CountResultSlots())
	if pending > 0 then
		status = status .. string.format(' Loading %d item(s)...', pending)
	end
	SetStatus(status)
	UpdateScanButton()
	if RefreshPanel then
		RefreshPanel()
	end
end

local function AddBrowseResults(browseResults)
	if type(browseResults) ~= 'table' then
		return
	end
	for _, browseResult in ipairs(browseResults) do
		local itemKey = browseResult.itemKey
		local itemID = itemKey and itemKey.itemID
		local price = browseResult.minPrice
		if itemID and type(price) == 'number' and price > 0 then
			local entry = scan.items[itemID]
			if not entry or price < entry.price then
				scan.items[itemID] = { price = price, browseResult = browseResult }
			end
		end
	end
end

local SendQuery

local function ContinueScan()
	scan.lastEventAt = GetTime()
	SetStatus(string.format('Scanning... %d items', scan.resultCount))

	if scan.stopRequested then
		FinishScan(true)
	elseif not C_AuctionHouse.HasFullBrowseResults() then
		C_AuctionHouse.RequestMoreBrowseResults()
	elseif scan.queryIndex < #QUERY_CLASSES then
		-- Armor done, now weapons
		scan.queryIndex = scan.queryIndex + 1
		scan.queryBaseCount = scan.resultCount
		scan.sentQuery = false
		SendQuery(scan.generation)
	else
		FinishScan(false)
	end
end

local function BuildBrowseQuery(classID)
	local filters = {}
	local filterEnum = Enum.AuctionHouseFilter or {}
	-- White items included: at low levels most usable gear on the Auction House is common quality
	local filterKeys = { 'CommonQuality', 'UncommonQuality', 'RareQuality', 'EpicQuality' }
	if scorer.usableFilter then
		table.insert(filterKeys, 1, 'UsableOnly')
	end
	for _, key in ipairs(filterKeys) do
		if filterEnum[key] then
			table.insert(filters, filterEnum[key])
		end
	end

	local sorts = {}
	if Enum.AuctionHouseSortOrder then
		sorts[1] = { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false }
	end

	return {
		searchString = '',
		sorts = sorts,
		filters = filters,
		-- One item class per query
		itemClassFilters = { { classID = classID } },
		-- No minimum by default: low level rings, cloaks and items without a level requirement can be upgrades
		minLevel = scorer.minLevel and scorer.minLevel > 0 and scorer.minLevel or nil,
		maxLevel = scorer.maxLevel,
	}
end

local function WatchScanTimeout(generation)
	C_Timer.After(2, function()
		if not scan.active or scan.generation ~= generation then
			return
		end
		if GetTime() - scan.lastEventAt > SCAN_TIMEOUT then
			FinishScan(true)
			return
		end
		WatchScanTimeout(generation)
	end)
end

SendQuery = function(generation)
	if not scan.active or scan.generation ~= generation then
		return
	end
	if scan.stopRequested then
		FinishScan(true)
		return
	end
	if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		C_Timer.After(0.5, function()
			SendQuery(generation)
		end)
		return
	end

	scan.sentQuery = true
	scan.lastEventAt = GetTime()
	C_AuctionHouse.SendBrowseQuery(BuildBrowseQuery(QUERY_CLASSES[scan.queryIndex]))
end

function upgrades:StartScan()
	if scan.active then
		scan.stopRequested = true
		UpdateScanButton()
		return
	end

	scorer, scorerProblem = ResolveScorer()
	if not scorer then
		SetStatus(scorerProblem)
		UpdateScanButton()
		return
	end

	scan.active = true
	scan.stopRequested = false
	scan.sentQuery = false
	scan.generation = scan.generation + 1
	scan.resultCount = 0
	scan.queryIndex = 1
	scan.queryBaseCount = 0
	scan.minLevel = scorer.minLevel
	scan.maxLevel = scorer.maxLevel
	scan.usableFilter = scorer.usableFilter
	scan.items = {}
	results = {}
	if RefreshPanel then
		RefreshPanel()
	end

	SetStatus('Scanning...')
	UpdateScanButton()
	SendQuery(scan.generation)
	WatchScanTimeout(scan.generation)
end

---------------------------------------------------------------------------
-- Panel UI
---------------------------------------------------------------------------

local function ShowAuction(candidate)
	local frame = _G.AuctionHouseFrame
	if not (candidate and frame and frame:IsShown()) then
		return
	end

	-- Opens Blizzard's buy view for the listing, the purchase is confirmed there by the player
	if candidate.browseResult and frame.SelectBrowseResult then
		frame:SelectBrowseResult(candidate.browseResult)
	elseif frame.SearchBar and frame.SearchBar.SearchBox and candidate.name then
		if _G.AuctionHouseFrameDisplayMode then
			frame:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
		end
		frame.SearchBar.SearchBox:SetText(candidate.name)
		frame.SearchBar:StartSearch()
	else
		return
	end

	if frame.Tabs and frame.numTabs then
		PanelTemplates_SetTab(frame, 1)
	end
end

-- Adds the item link to the open chat box, or opens chat with it
local function LinkItemInChat(candidate)
	local link = candidate and candidate.itemLink
	if type(link) ~= 'string' or not link:find('|H', 1, true) then
		return
	end
	-- Chat can be locked down on the modern engine; linking then is not allowed
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return
	end

	-- Newer clients moved these into ChatFrameUtil
	local insertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or _G.ChatEdit_InsertLink
	if insertLink and insertLink(link) then
		return
	end

	-- No chat box open: open one with the link in it
	local openChat = (ChatFrameUtil and ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat
	if openChat then
		openChat(link)
	end
end

local function CreateRow(parent, index)
	local row = CreateFrame('Button', nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint('TOPLEFT', 0, -(index - 1) * ROW_HEIGHT)
	row:SetPoint('RIGHT', parent, 'RIGHT')

	local highlight = row:CreateTexture(nil, 'HIGHLIGHT')
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)

	row.Slot = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	row.Slot:SetPoint('LEFT', 4, 0)
	row.Slot:SetWidth(110)
	row.Slot:SetJustifyH('LEFT')

	row.Icon = row:CreateTexture(nil, 'ARTWORK')
	row.Icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
	row.Icon:SetPoint('LEFT', row.Slot, 'RIGHT', 4, 0)

	row.Name = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	row.Name:SetPoint('LEFT', row.Icon, 'RIGHT', 6, 0)
	row.Name:SetWidth(250)
	row.Name:SetJustifyH('LEFT')

	row.Gain = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	row.Gain:SetPoint('LEFT', row.Name, 'RIGHT', 6, 0)
	row.Gain:SetWidth(110)
	row.Gain:SetJustifyH('LEFT')

	row.ShowButton = CreateFrame('Button', nil, row, 'UIPanelButtonTemplate')
	row.ShowButton:SetSize(70, ROW_HEIGHT - 2)
	row.ShowButton:SetPoint('RIGHT', -4, 0)
	row.ShowButton:SetText('Show')
	row.ShowButton:SetScript('OnClick', function()
		ShowAuction(row.candidate)
	end)

	row.Price = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	row.Price:SetPoint('RIGHT', row.ShowButton, 'LEFT', -8, 0)
	row.Price:SetJustifyH('RIGHT')

	row:SetScript('OnEnter', function(self)
		if self.candidate and self.candidate.itemLink then
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			GameTooltip:SetHyperlink(self.candidate.itemLink)
			GameTooltip:Show()
		end
	end)
	row:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	-- Shift+Right-click puts the item link into chat
	row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	row:SetScript('OnClick', function(self, button)
		if button == 'RightButton' and IsShiftKeyDown() then
			LinkItemInChat(self.candidate)
		end
	end)

	return row
end

local function SetRow(row, slotLabel, candidate, tag)
	row.candidate = candidate
	row.Slot:SetText(slotLabel)
	row.Icon:SetTexture(candidate.icon)
	row.Name:SetText(candidate.itemLink and candidate.itemLink:find('|H') and candidate.itemLink or (candidate.name or ('item:' .. candidate.itemID)))
	row.Gain:SetText(string.format('|cff33ff99+%.1f|r %s', candidate.gain, tag))
	row.Price:SetText(FormatMoney(candidate.price))
	row.Icon:Show()
	row.ShowButton:Show()
	row:Show()
end

-- Slot with nothing better on the Auction House than what is equipped
local function SetEmptyRow(row, slotLabel)
	row.candidate = nil
	row.Slot:SetText(slotLabel)
	row.Icon:Hide()
	row.Name:SetText('|cff808080No upgrade on the Auction House|r')
	row.Gain:SetText('')
	row.Price:SetText('')
	row.ShowButton:Hide()
	row:Show()
end

RefreshPanel = function()
	if not panel then
		return
	end

	local rowIndex = 0
	local function NextRow()
		rowIndex = rowIndex + 1
		local row = panel.rows[rowIndex]
		if not row then
			row = CreateRow(panel.Content, rowIndex)
			panel.rows[rowIndex] = row
		end
		return row
	end

	for _, slotID in ipairs(SLOT_ORDER) do
		local slot = results[slotID]
		if slot and slot.best then
			SetRow(NextRow(), GetSlotName(slotID), slot.best, scorer and scorer.ownClass and '(best)' or '(top)')
			if slot.value and slot.value.itemID ~= slot.best.itemID then
				SetRow(NextRow(), '', slot.value, '(value)')
			end
		elseif scan.hasScanned and not scan.active then
			SetEmptyRow(NextRow(), GetSlotName(slotID))
		end
	end

	for index = rowIndex + 1, #panel.rows do
		panel.rows[index]:Hide()
	end
	panel.Content:SetHeight(math.max(rowIndex * ROW_HEIGHT, 1))

	if scorer then
		local levels = scorer.minLevel and string.format('%d-%d', scorer.minLevel, scorer.maxLevel) or string.format('up to %d', scorer.maxLevel)
		local line = string.format('%s | %s | level %s', scorer.label, GetClassLabel(scorer.classToken), levels)
		local filterText = DescribeStatFilters()
		if filterText then
			line = line .. ' | needs ' .. filterText
		end
		panel.Weights:SetText(line)
	else
		panel.Weights:SetText('')
	end
	panel.Empty:SetShown(rowIndex == 0 and not scan.active)
end

---------------------------------------------------------------------------
-- Options panel
---------------------------------------------------------------------------

local RefreshOptions

-- Called after any option changes: rebuild the scorer and re-score the last scan
local function ApplyOptions()
	scorer, scorerProblem = ResolveScorer()
	if not scan.active then
		if scorer and next(scan.items) then
			local pending = Analyze()
			local status = string.format('Re-scored %d items, upgrades for %d slot(s).', scan.resultCount, CountResultSlots())
			-- The Auction House was only searched for the previous range and filter
			local searchedLevels = (scorer.minLevel or 0) >= (scan.minLevel or 0) and scorer.maxLevel <= (scan.maxLevel or 0)
			if not searchedLevels or (scan.usableFilter and not scorer.usableFilter) then
				status = status .. ' Scan again to search the new options.'
			elseif pending > 0 then
				status = status .. string.format(' Loading %d item(s)...', pending)
			end
			SetStatus(status)
		elseif not scorer then
			results = {}
			SetStatus(scorerProblem)
		else
			SetStatus('')
		end
	end
	UpdateScanButton()
	RefreshPanel()
	if RefreshOptions then
		RefreshOptions()
	end
end

-- A label with < and > buttons that cycles through a list of { id, label } entries
local function CreateSelector(parent, labelText, anchor)
	local selector = CreateFrame('Frame', nil, parent)
	selector:SetSize(460, 24)
	selector:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, -10)

	selector.Label = selector:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	selector.Label:SetPoint('LEFT', 0, 0)
	selector.Label:SetWidth(110)
	selector.Label:SetJustifyH('LEFT')
	selector.Label:SetText(labelText)

	selector.Prev = CreateFrame('Button', nil, selector, 'UIPanelButtonTemplate')
	selector.Prev:SetSize(26, 22)
	selector.Prev:SetPoint('LEFT', selector.Label, 'RIGHT', 4, 0)
	selector.Prev:SetText('<')

	selector.Value = selector:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	selector.Value:SetPoint('LEFT', selector.Prev, 'RIGHT', 8, 0)
	selector.Value:SetWidth(270)
	selector.Value:SetJustifyH('CENTER')

	selector.Next = CreateFrame('Button', nil, selector, 'UIPanelButtonTemplate')
	selector.Next:SetSize(26, 22)
	selector.Next:SetPoint('LEFT', selector.Value, 'RIGHT', 8, 0)
	selector.Next:SetText('>')

	selector.entries = {}
	function selector:SetEntries(entries, selectedID)
		self.entries = entries or {}
		self.index = 1
		for index, entry in ipairs(self.entries) do
			if entry.id == selectedID then
				self.index = index
			end
		end
		local current = self.entries[self.index]
		self.Value:SetText(current and current.label or '|cff808080None available|r')
		local canCycle = #self.entries > 1
		self.Prev:SetEnabled(canCycle)
		self.Next:SetEnabled(canCycle)
	end

	local function Step(delta)
		local count = #selector.entries
		if count < 2 then
			return
		end
		local index = (selector.index - 1 + delta) % count + 1
		if selector.OnChange then
			selector.OnChange(selector.entries[index].id)
		end
	end
	selector.Prev:SetScript('OnClick', function()
		Step(-1)
	end)
	selector.Next:SetScript('OnClick', function()
		Step(1)
	end)

	return selector
end

local function CreateLevelBox(parent)
	local box = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
	box:SetSize(36, 20)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(2)
	box:SetJustifyH('CENTER')
	box:SetScript('OnEnterPressed', function(self)
		self:ClearFocus()
	end)
	box:SetScript('OnEscapePressed', function(self)
		self:ClearFocus()
	end)
	return box
end

local function CreateOptionsPanel(anchorFrame)
	local options = CreateFrame('Frame', nil, panel)
	options:SetPoint('TOPLEFT', anchorFrame, 'TOPLEFT')
	options:SetPoint('BOTTOMRIGHT', anchorFrame, 'BOTTOMRIGHT', 20, 0)
	options:SetFrameLevel(panel:GetFrameLevel() + 20)
	options:EnableMouse(true)
	options:Hide()
	panel.Options = options

	local background = options:CreateTexture(nil, 'BACKGROUND')
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.05, 0.05, 0.97)

	options.Title = options:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	options.Title:SetPoint('TOPLEFT', 16, -14)
	options.Title:SetText('Upgrade scan options')

	options.Help = options:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	options.Help:SetPoint('TOPLEFT', options.Title, 'BOTTOMLEFT', 0, -6)
	options.Help:SetText('Saved for this character. Changes re-score the last scan.')

	options.Source = CreateSelector(options, 'Weights', options.Help)
	options.Source:SetPoint('TOPLEFT', options.Help, 'BOTTOMLEFT', 0, -16)
	options.Source.OnChange = function(id)
		local saved = GetOptions()
		saved.source = id
		-- Spec names differ between Pawn and RestedXP
		saved.spec = nil
		ApplyOptions()
	end

	options.Class = CreateSelector(options, 'Class', options.Source)
	options.Class.OnChange = function(id)
		local saved = GetOptions()
		saved.class = id
		saved.spec = nil
		ApplyOptions()
	end

	options.Spec = CreateSelector(options, 'Specialization', options.Class)
	options.Spec.OnChange = function(id)
		GetOptions().spec = id
		ApplyOptions()
	end

	local levels = CreateFrame('Frame', nil, options)
	levels:SetSize(460, 24)
	levels:SetPoint('TOPLEFT', options.Spec, 'BOTTOMLEFT', 0, -14)
	options.Levels = levels

	levels.Label = levels:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	levels.Label:SetPoint('LEFT', 0, 0)
	levels.Label:SetWidth(110)
	levels.Label:SetJustifyH('LEFT')
	levels.Label:SetText('Required level')

	levels.Min = CreateLevelBox(levels)
	levels.Min:SetPoint('LEFT', levels.Label, 'RIGHT', 10, 0)
	levels.To = levels:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	levels.To:SetPoint('LEFT', levels.Min, 'RIGHT', 8, 0)
	levels.To:SetText('to')
	levels.Max = CreateLevelBox(levels)
	levels.Max:SetPoint('LEFT', levels.To, 'RIGHT', 12, 0)
	levels.Hint = levels:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	levels.Hint:SetPoint('LEFT', levels.Max, 'RIGHT', 10, 0)
	levels.Hint:SetText('Blank: no minimum, up to your level')

	local function SaveLevels()
		local saved = GetOptions()
		saved.minLevel = tonumber(levels.Min:GetText())
		saved.maxLevel = tonumber(levels.Max:GetText())
		if saved.minLevel and saved.maxLevel and saved.minLevel > saved.maxLevel then
			saved.minLevel, saved.maxLevel = saved.maxLevel, saved.minLevel
		end
		ApplyOptions()
	end
	levels.Min:SetScript('OnEditFocusLost', SaveLevels)
	levels.Max:SetScript('OnEditFocusLost', SaveLevels)

	-- Stat filters: pick a stat, Add it, optionally give each a minimum amount
	options.StatPicker = CreateSelector(options, 'Stat filters', levels)
	options.StatPicker:SetPoint('TOPLEFT', levels, 'BOTTOMLEFT', 0, -18)
	options.StatPicker.OnChange = function(id)
		options.StatPicker.pending = id
		RefreshOptions()
	end

	options.AddStat = CreateFrame('Button', nil, options, 'UIPanelButtonTemplate')
	options.AddStat:SetSize(60, 22)
	options.AddStat:SetPoint('LEFT', options.StatPicker.Next, 'RIGHT', 10, 0)
	options.AddStat:SetText(_G.ADD or 'Add')
	options.AddStat:SetScript('OnClick', function()
		local entry = options.StatPicker.entries[options.StatPicker.index]
		if not entry then
			return
		end
		local saved = GetOptions()
		saved.statFilters = GetStatFilters()
		if #saved.statFilters >= MAX_STAT_FILTERS then
			return
		end
		table.insert(saved.statFilters, { stat = entry.id })
		options.StatPicker.pending = nil
		ApplyOptions()
	end)

	options.MatchMode = CreateFrame('Button', nil, options, 'UIPanelButtonTemplate')
	options.MatchMode:SetSize(150, 22)
	options.MatchMode:SetPoint('LEFT', options.AddStat, 'RIGHT', 10, 0)
	options.MatchMode:SetScript('OnClick', function()
		local saved = GetOptions()
		saved.statMatch = saved.statMatch == 'all' and 'any' or 'all'
		ApplyOptions()
	end)

	-- Two columns of active filters
	options.FilterRows = {}
	for index = 1, MAX_STAT_FILTERS do
		local row = CreateFrame('Frame', nil, options)
		row:SetSize(330, 24)
		local column = (index - 1) % 2
		local line = math.floor((index - 1) / 2)
		row:SetPoint('TOPLEFT', options.StatPicker, 'BOTTOMLEFT', 20 + column * 340, -8 - line * 26)

		row.Label = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		row.Label:SetPoint('LEFT', 0, 0)
		row.Label:SetWidth(150)
		row.Label:SetJustifyH('LEFT')

		row.AtLeast = row:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
		row.AtLeast:SetPoint('LEFT', row.Label, 'RIGHT', 4, 0)
		row.AtLeast:SetText('at least')

		row.Min = CreateLevelBox(row)
		row.Min:SetMaxLetters(3)
		row.Min:SetPoint('LEFT', row.AtLeast, 'RIGHT', 10, 0)
		row.Min:SetScript('OnEditFocusLost', function(self)
			local filters = GetStatFilters()
			local filter = filters[index]
			if filter then
				filter.min = tonumber(self:GetText())
				GetOptions().statFilters = filters
				ApplyOptions()
			end
		end)

		row.Remove = CreateFrame('Button', nil, row, 'UIPanelButtonTemplate')
		row.Remove:SetSize(70, 20)
		row.Remove:SetPoint('LEFT', row.Min, 'RIGHT', 8, 0)
		row.Remove:SetText(_G.REMOVE or 'Remove')
		row.Remove:SetScript('OnClick', function()
			local filters = GetStatFilters()
			table.remove(filters, index)
			GetOptions().statFilters = filters
			ApplyOptions()
		end)

		row:Hide()
		options.FilterRows[index] = row
	end

	options.Note = options:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	options.Note:SetPoint('TOPLEFT', options.StatPicker, 'BOTTOMLEFT', 0, -92)
	options.Note:SetWidth(620)
	options.Note:SetJustifyH('LEFT')

	options.Reset = CreateFrame('Button', nil, options, 'UIPanelButtonTemplate')
	options.Reset:SetSize(130, 22)
	options.Reset:SetPoint('BOTTOMLEFT', 16, 14)
	options.Reset:SetText('My character')
	options.Reset:SetScript('OnClick', function()
		local saved = GetOptions()
		saved.class, saved.spec, saved.minLevel, saved.maxLevel = nil, nil, nil, nil
		ApplyOptions()
	end)

	options.Done = CreateFrame('Button', nil, options, 'UIPanelButtonTemplate')
	options.Done:SetSize(90, 22)
	options.Done:SetPoint('BOTTOMRIGHT', -16, 14)
	options.Done:SetText(_G.DONE or 'Done')
	options.Done:SetScript('OnClick', function()
		options:Hide()
	end)

	options:SetScript('OnShow', function()
		RefreshOptions()
	end)
end

RefreshOptions = function()
	local options = panel and panel.Options
	if not (options and options:IsShown()) then
		return
	end

	local _, problem, lists = ResolveScorer()
	lists = lists or {}

	local sourceEntries = {}
	for _, id in ipairs(lists.sources or {}) do
		table.insert(sourceEntries, { id = id, label = SOURCE_LABELS[id] })
	end
	options.Source:SetEntries(sourceEntries, lists.source)

	local classEntries = {}
	for _, classToken in ipairs(lists.classes or {}) do
		table.insert(classEntries, { id = classToken, label = GetClassLabel(classToken) })
	end
	options.Class:SetEntries(classEntries, lists.class)
	options.Spec:SetEntries(lists.specs or {}, lists.spec)

	local saved = GetOptions()
	if not options.Levels.Min:HasFocus() then
		options.Levels.Min:SetText(saved.minLevel and tostring(saved.minLevel) or '')
	end
	if not options.Levels.Max:HasFocus() then
		options.Levels.Max:SetText(saved.maxLevel and tostring(saved.maxLevel) or '')
	end

	local _, playerClass = UnitClass('player')
	local notes = {}
	if problem then
		table.insert(notes, '|cffff6060' .. problem .. '|r')
	end
	if lists.class and lists.class ~= playerClass then
		table.insert(notes, 'Another class: items are ranked on their own, not against what you are wearing.')
	end
	if lists.source == SOURCE_RXP then
		table.insert(notes, 'RestedXP weights follow the level bracket of the maximum level.')
	end
	if not IsPawnReady() then
		table.insert(notes, 'Pawn is not loaded, so only RestedXP Guides weights are available.')
	end
	-- Stat filters
	local filters = GetStatFilters()
	local used = {}
	for _, filter in ipairs(filters) do
		used[filter.stat] = true
	end
	local pickerEntries = {}
	for _, stat in ipairs(STAT_FILTERS) do
		if not used[stat.id] then
			table.insert(pickerEntries, { id = stat.id, label = stat.label })
		end
	end
	options.StatPicker:SetEntries(pickerEntries, options.StatPicker.pending)
	options.AddStat:SetEnabled(#filters < MAX_STAT_FILTERS and #pickerEntries > 0)
	options.MatchMode:SetText(saved.statMatch == 'all' and 'Match: all stats' or 'Match: any stat')
	options.MatchMode:SetEnabled(#filters > 1)
	for index, row in ipairs(options.FilterRows) do
		local filter = filters[index]
		if filter then
			row.Label:SetText(STAT_FILTERS_BY_ID[filter.stat].label)
			if not row.Min:HasFocus() then
				row.Min:SetText(filter.min and tostring(filter.min) or '')
			end
			row:Show()
		else
			row:Hide()
		end
	end
	if #filters == 0 then
		table.insert(notes, 'No stat filters: every item is considered. Add stats to only list items that have them.')
	end

	options.Note:SetText(table.concat(notes, '\n'))
end

local function CreatePanel(attachment)
	panel = CreateFrame('Frame', 'ProkinMinimapAuctionUpgradesPanel', attachment)
	panel:SetPoint('TOPLEFT', attachment, 'TOPLEFT', 8, -28)
	panel:SetPoint('BOTTOMRIGHT', attachment, 'BOTTOMRIGHT', -8, 30)
	panel:SetFrameLevel(attachment:GetFrameLevel() + 10)
	panel:Hide()
	panel.rows = {}

	local background = panel:CreateTexture(nil, 'BACKGROUND')
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.55)

	-- The Auction House header already shows PANEL_TITLE, and its portrait covers the top-left corner
	panel.ScanButton = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
	panel.ScanButton:SetSize(90, 22)
	panel.ScanButton:SetPoint('TOPLEFT', 60, -8)
	panel.ScanButton:SetScript('OnClick', function()
		if panel.Options then
			panel.Options:Hide()
		end
		upgrades:StartScan()
	end)

	panel.OptionsButton = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
	panel.OptionsButton:SetSize(80, 22)
	panel.OptionsButton:SetPoint('LEFT', panel.ScanButton, 'RIGHT', 4, 0)
	panel.OptionsButton:SetText(_G.OPTIONS or 'Options')
	panel.OptionsButton:SetScript('OnClick', function()
		panel.Options:SetShown(not panel.Options:IsShown())
	end)

	panel.Status = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	panel.Status:SetPoint('LEFT', panel.OptionsButton, 'RIGHT', 10, 0)
	panel.Status:SetPoint('RIGHT', panel, 'RIGHT', -10, 0)
	panel.Status:SetJustifyH('LEFT')

	panel.Weights = panel:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	panel.Weights:SetPoint('TOPLEFT', panel.ScanButton, 'BOTTOMLEFT', 0, -6)
	panel.Weights:SetJustifyH('LEFT')

	local scrollFrame = CreateFrame('ScrollFrame', nil, panel, 'UIPanelScrollFrameTemplate')
	scrollFrame:SetPoint('TOPLEFT', panel.Weights, 'BOTTOMLEFT', 0, -8)
	scrollFrame:SetPoint('BOTTOMRIGHT', -28, 8)
	panel.Content = CreateFrame('Frame', nil, scrollFrame)
	panel.Content:SetSize(1, 1)
	scrollFrame:SetScrollChild(panel.Content)
	scrollFrame:SetScript('OnSizeChanged', function(self, width)
		panel.Content:SetWidth(width)
	end)

	panel.Empty = panel:CreateFontString(nil, 'OVERLAY', 'GameFontDisable')
	panel.Empty:SetPoint('CENTER', scrollFrame, 'CENTER')
	panel.Empty:SetText('Press Scan to look for upgrades for every equipment slot.')

	CreateOptionsPanel(scrollFrame)

	panel:SetScript('OnShow', function()
		if not scan.active then
			scorer, scorerProblem = ResolveScorer()
			if not scorer then
				SetStatus(scorerProblem)
			end
		end
		UpdateScanButton()
		RefreshPanel()
	end)
end

-- Adds the tab to the Auction House. Shares the LibAHTab-1-0 tab strip when another addon
-- (for example TradeSkillMaster) has loaded it, so tabs never overlap.
local function CreateTab(attachment)
	local LibAHTab = LibStub and LibStub('LibAHTab-1-0', true)
	if LibAHTab then
		if not LibAHTab:DoesIDExist(TAB_ID) then
			LibAHTab:CreateTab(TAB_ID, panel, TAB_TEXT, PANEL_TITLE)
		end
		return
	end

	local ok, button = pcall(CreateFrame, 'Button', 'ProkinMinimapAuctionHouseTab', attachment, 'AuctionHouseFrameDisplayModeTabTemplate')
	if not ok then
		button = CreateFrame('Button', 'ProkinMinimapAuctionHouseTab', attachment, 'UIPanelButtonTemplate')
		button:SetSize(120, 22)
	end
	tabButton = button
	tabButton:SetText(TAB_TEXT)
	if ok then
		PanelTemplates_TabResize(tabButton, 20, nil, 70)
		PanelTemplates_DeselectTab(tabButton)
	end

	-- Sit after RestedXP's own Forever tab when it exists, otherwise after Blizzard's tabs
	local anchor = _G.RXPGuidesAuctionHouseTab or (attachment.Tabs and attachment.Tabs[#attachment.Tabs])
	if anchor then
		tabButton:SetPoint('TOPLEFT', anchor, 'TOPRIGHT', WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and 3 or -14, 0)
	else
		tabButton:SetPoint('TOPLEFT', attachment, 'BOTTOMLEFT', 0, 2)
	end

	tabButton:SetScript('OnClick', function()
		selectingTab = true
		attachment:SetDisplayMode({})
		attachment.displayMode = nil
		selectingTab = false

		if attachment.Tabs then
			for _, tab in ipairs(attachment.Tabs) do
				PanelTemplates_DeselectTab(tab)
			end
		end
		if _G.RXPGuidesAuctionHouseTab then
			PanelTemplates_DeselectTab(_G.RXPGuidesAuctionHouseTab)
		end
		if ok then
			PanelTemplates_SelectTab(tabButton)
		end
		if attachment.SetTitle then
			attachment:SetTitle(PANEL_TITLE)
		end
		panel:Show()
	end)

	-- Any other tab (Blizzard's, or another addon clearing the display mode for its own tab) hides this panel
	hooksecurefunc(attachment, 'SetDisplayMode', function()
		if selectingTab then
			return
		end
		panel:Hide()
		if ok then
			PanelTemplates_DeselectTab(tabButton)
		end
	end)
end

local function SetupAuctionHouse()
	local attachment = _G.AuctionHouseFrame
	if panel or not attachment then
		return
	end
	CreatePanel(attachment)
	CreateTab(attachment)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

eventFrame:RegisterEvent('AUCTION_HOUSE_SHOW')
eventFrame:RegisterEvent('AUCTION_HOUSE_CLOSED')
eventFrame:RegisterEvent('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
eventFrame:RegisterEvent('AUCTION_HOUSE_BROWSE_RESULTS_ADDED')
eventFrame:RegisterEvent('GET_ITEM_INFO_RECEIVED')

eventFrame:SetScript('OnEvent', function(_, event, arg1, arg2)
	if event == 'AUCTION_HOUSE_SHOW' then
		-- Wait a frame so the Auction House UI (load-on-demand) and other addons' tabs exist first
		C_Timer.After(0, SetupAuctionHouse)
		return
	end

	if event == 'AUCTION_HOUSE_CLOSED' then
		if scan.active then
			FinishScan(true)
		end
		return
	end

	if event == 'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' then
		if not (scan.active and scan.sentQuery) then
			return
		end
		local browseResults = C_AuctionHouse.GetBrowseResults()
		AddBrowseResults(browseResults)
		scan.resultCount = scan.queryBaseCount + (type(browseResults) == 'table' and #browseResults or 0)
		ContinueScan()
		return
	end

	if event == 'AUCTION_HOUSE_BROWSE_RESULTS_ADDED' then
		if not (scan.active and scan.sentQuery) then
			return
		end
		AddBrowseResults(arg1)
		scan.resultCount = scan.resultCount + (type(arg1) == 'table' and #arg1 or 0)
		ContinueScan()
		return
	end

	if event == 'GET_ITEM_INFO_RECEIVED' then
		if arg2 and scan.items[arg1] then
			QueueReanalyze()
		end
	end
end)
