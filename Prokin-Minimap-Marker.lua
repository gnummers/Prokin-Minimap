-- Smart dungeon marking. When the player leads a 5-player dungeon group, Prokin gives each pack
-- a kill order and crowd-control icons that suit the group:
--   Skull and Cross go to the most dangerous mobs: bosses, elites, healers and casters first,
--   then mobs above the player's level, with lower health breaking ties.
--   Moon, Square, Circle, Diamond, Triangle and Star go to mobs the group's crowd control can
--   hold (Polymorph, Freezing Trap, Shackle Undead, Banish, Hibernate, Sap).
-- In combat the kill icons cascade: when Skull dies, Cross becomes Skull and the next mob gets
-- Cross. Icons other players placed are never taken or moved.
--
-- The Burning Crusade Anniversary lets addons place icons, so packs are marked automatically as
-- the leader approaches them. WoW Forever only lets the game place icons from a key press, so
-- there the Mark Mob key binding gives the hovered or targeted mob the icon Prokin picks.

local ADDON_NAME = ...
local Marker = _G.ProkinMinimapMarker or {}
_G.ProkinMinimapMarker = Marker

local INTERFACE_VERSION = select(4, GetBuildInfo()) or 0
Marker.IS_FOREVER = INTERFACE_VERSION >= 16000 and INTERFACE_VERSION < 20000

local STAR, CIRCLE, DIAMOND, TRIANGLE, MOON, SQUARE, CROSS, SKULL = 1, 2, 3, 4, 5, 6, 7, 8
Marker.ICONS = { STAR = STAR, CIRCLE = CIRCLE, DIAMOND = DIAMOND, TRIANGLE = TRIANGLE, MOON = MOON, SQUARE = SQUARE, CROSS = CROSS, SKULL = SKULL }
Marker.ICON_NAMES = { 'Star', 'Circle', 'Diamond', 'Triangle', 'Moon', 'Square', 'Cross', 'Skull' }

-- Crowd control in the order Prokin prefers to use it, with the creature types each can hold.
-- A nil type list means any type. Sap only works before the pull.
Marker.CROWD_CONTROL = {
	{ class = 'MAGE', icon = MOON, spell = 'Polymorph', types = { Humanoid = true, Beast = true } },
	{ class = 'HUNTER', icon = SQUARE, spell = 'Freezing Trap' },
	{ class = 'PRIEST', icon = CIRCLE, spell = 'Shackle Undead', types = { Undead = true } },
	{ class = 'WARLOCK', icon = DIAMOND, spell = 'Banish', types = { Demon = true, Elemental = true } },
	{ class = 'DRUID', icon = TRIANGLE, spell = 'Hibernate', types = { Beast = true, Dragonkin = true } },
	{ class = 'ROGUE', icon = STAR, spell = 'Sap', types = { Humanoid = true }, prePullOnly = true },
}

local SKIPPED_TYPES = { Critter = true, Totem = true, ['Non-combat Pet'] = true, ['Gas Cloud'] = true, ['Wild Pet'] = true }
local HEALER_CLASSES = { PALADIN = true, PRIEST = true, SHAMAN = true, DRUID = true }

-- Kill priority for the known dangerous mobs in Prokin-Minimap-MarkerData.lua. These outrank the
-- guesses from an NPC's class, so a listed healer dies before an unlisted elite.
Marker.DANGER_WEIGHTS = { healer = 50, summoner = 45, fear = 45, dangerous = 40, caster = 35 }
local CASTER_CLASSES = { MAGE = true, WARLOCK = true }

Marker.SCAN_INTERVAL = 0.25
Marker.MAX_MARKS_PER_SCAN = 2
Marker.FORGET_AFTER = 90
Marker.PULL_RANGE_INDEX = 4 -- CheckInteractDistance index for about 28 yards

-- GUID -> { icon, seen } for icons Prokin placed. Icons are forgotten when the mob dies, when
-- another player changes them, or when the mob has not been seen for FORGET_AFTER seconds.
Marker.assigned = Marker.assigned or {}

local function IsSecret(value)
	return type(issecretvalue) == 'function' and issecretvalue(value)
end

local function Wipe(list)
	for key in pairs(list) do
		list[key] = nil
	end
end

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(string.format('|cff33ff99%s|r: %s', ADDON_NAME or 'Prokin-Minimap', message))
end

local function SafeCall(fn, ...)
	if type(fn) ~= 'function' then
		return nil
	end

	local ok, a, b, c = pcall(fn, ...)
	if not ok or IsSecret(a) or IsSecret(b) or IsSecret(c) then
		return nil
	end
	return a, b, c
end

function Marker.GetSettings()
	if type(ProkinMinimapDB) ~= 'table' then
		ProkinMinimapDB = {}
	end

	local settings = ProkinMinimapDB.marker
	if type(settings) ~= 'table' then
		settings = {}
		ProkinMinimapDB.marker = settings
	end
	if type(settings.enabled) ~= 'boolean' then
		settings.enabled = true
	end
	if type(settings.priority) ~= 'table' then
		settings.priority = {}
	end
	if type(settings.ignore) ~= 'table' then
		settings.ignore = {}
	end
	return settings
end

function Marker.IsOtherMarkerLoaded()
	local isLoaded = (type(C_AddOns) == 'table' and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	return SafeCall(isLoaded, 'AutoMarkAssist') and true or false
end

-- Returns whether Prokin should mark, and a reason when it should not.
function Marker.GetActiveState()
	local settings = Marker.GetSettings()
	if not settings.enabled then
		return false, 'turned off'
	end
	if Marker.IsOtherMarkerLoaded() then
		return false, 'AutoMarkAssist is loaded'
	end
	if not IsInGroup() or IsInRaid() then
		return false, 'not in a 5-player group'
	end

	local inInstance, instanceType = IsInInstance()
	if IsSecret(inInstance) or not inInstance or instanceType ~= 'party' then
		return false, 'not in a dungeon'
	end

	local isLeader = UnitIsGroupLeader('player')
	if IsSecret(isLeader) or (not isLeader and not settings.anyMember) then
		return false, 'you are not the group leader'
	end
	return true
end

function Marker.IsActive()
	return (Marker.GetActiveState())
end

-- The NPC ID is the sixth field of a creature GUID.
function Marker.GetNpcID(guid)
	if type(guid) ~= 'string' then
		return nil
	end
	local kind, npcID = string.match(guid, '^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)')
	if kind == 'Creature' or kind == 'Vehicle' then
		return tonumber(npcID)
	end
end

-- Reads one unit into a plain table, or returns nil when it should not be marked.
function Marker.ReadUnit(unit)
	if not SafeCall(UnitExists, unit) or SafeCall(UnitIsDead, unit) then
		return nil
	end
	if not SafeCall(UnitCanAttack, 'player', unit) or SafeCall(UnitIsPlayer, unit) or SafeCall(UnitPlayerControlled, unit) then
		return nil
	end
	if SafeCall(UnitIsTapDenied, unit) then
		return nil
	end

	local guid = SafeCall(UnitGUID, unit)
	local npcID = Marker.GetNpcID(guid)
	if not npcID then
		return nil
	end

	local settings = Marker.GetSettings()
	if settings.ignore[npcID] then
		return nil
	end

	local classification = SafeCall(UnitClassification, unit) or 'normal'
	if classification == 'trivial' or classification == 'minus' then
		return nil
	end

	local creatureType = SafeCall(UnitCreatureType, unit)
	if creatureType and SKIPPED_TYPES[creatureType] then
		return nil
	end

	local level = SafeCall(UnitLevel, unit) or 0
	local name = SafeCall(UnitName, unit)
	local _, class = SafeCall(UnitClass, unit)
	local powerType = SafeCall(UnitPowerType, unit)
	local info = {
		unit = unit,
		guid = guid,
		npcID = npcID,
		icon = SafeCall(GetRaidTargetIndex, unit),
		creatureType = creatureType,
		health = SafeCall(UnitHealthMax, unit) or 0,
		combat = SafeCall(UnitAffectingCombat, unit) and true or false,
		-- Dungeon bosses usually show an ordinary level, so they are recognised from the boss list.
		boss = level == -1 or classification == 'worldboss' or Marker.IsDungeonBoss(npcID, name),
		danger = Marker.DANGEROUS_MOBS and Marker.DANGEROUS_MOBS[npcID] or nil,
		elite = classification == 'elite' or classification == 'rareelite',
	}
	info.score = Marker.Score(info, classification, class, powerType, level)
	return info
end

function Marker.IsDungeonBoss(npcID, name)
	if Marker.DUNGEON_BOSSES and npcID and Marker.DUNGEON_BOSSES[npcID] then
		return true
	end
	return type(name) == 'string' and Marker.DUNGEON_BOSS_NAMES ~= nil and Marker.DUNGEON_BOSS_NAMES[name] == true
end

-- Higher scores die first.
function Marker.Score(info, classification, class, powerType, level)
	local score = 0
	if info.boss then
		score = score + 100
	elseif classification == 'rareelite' then
		score = score + 35
	elseif classification == 'elite' then
		score = score + 30
	elseif classification == 'rare' then
		score = score + 15
	end

	if info.danger then
		score = score + (Marker.DANGER_WEIGHTS[info.danger] or 35)
	elseif class and HEALER_CLASSES[class] then
		score = score + 25
	elseif class and CASTER_CLASSES[class] then
		score = score + 20
	elseif powerType == 0 then
		score = score + 15
	end

	local playerLevel = SafeCall(UnitLevel, 'player') or 0
	if level and level > 0 and playerLevel > 0 then
		score = score + math.max(-12, math.min(12, (level - playerLevel) * 4))
	end

	if Marker.GetSettings().priority[info.npcID] then
		score = score + 60
	end
	return score
end

-- The group's crowd control, one entry per class present.
function Marker.GetGroupCrowdControl()
	local classes = {}
	local units = { 'player', 'party1', 'party2', 'party3', 'party4' }
	if IsInRaid() then
		units = { 'player' }
		for index = 1, (SafeCall(GetNumGroupMembers) or 0) do
			units[#units + 1] = 'raid' .. index
		end
	end
	for _, unit in ipairs(units) do
		if SafeCall(UnitExists, unit) then
			local _, class = SafeCall(UnitClass, unit)
			if class then
				classes[class] = true
			end
		end
	end

	local available = {}
	for _, cc in ipairs(Marker.CROWD_CONTROL) do
		if classes[cc.class] then
			available[#available + 1] = cc
		end
	end
	return available
end

local function SortByKillOrder(a, b)
	if a.score ~= b.score then
		return a.score > b.score
	end
	if a.health ~= b.health then
		return a.health < b.health
	end
	return a.guid < b.guid
end

local function CanHold(cc, mob)
	return not mob.boss and (cc.types == nil or (mob.creatureType ~= nil and cc.types[mob.creatureType] == true))
end

-- Works out which icon each mob should carry. mobs is a list from ReadUnit; assigned maps GUIDs
-- to icons Prokin placed. Returns a GUID -> icon table for mobs whose icon should change.
-- Before the pull the whole pack is re-planned. In combat only the kill icons move.
function Marker.Plan(mobs, assigned, crowdControl, inCombat)
	local taken, free, changes = {}, {}, {}
	local holders = {}

	for _, mob in ipairs(mobs) do
		if mob.icon and assigned[mob.guid] ~= mob.icon then
			taken[mob.icon] = true -- another player's icon
		elseif not mob.icon then
			free[#free + 1] = mob
		elseif inCombat then
			holders[mob.icon] = mob
		else
			free[#free + 1] = mob
		end
	end

	-- Icons Prokin placed on mobs that are out of sight but alive are still in use.
	for guid, icon in pairs(assigned) do
		local visible
		for _, mob in ipairs(mobs) do
			if mob.guid == guid then
				visible = true
				break
			end
		end
		-- Before the pull, icons on mobs left behind move to the pack ahead.
		if not visible and inCombat then
			taken[icon] = true
		end
	end

	table.sort(free, SortByKillOrder)
	local function Give(mob, icon)
		taken[icon] = true
		if mob.icon ~= icon then
			changes[mob.guid] = icon
		end
	end

	if inCombat then
		-- Keep crowd control in place and only cascade the kill icons.
		for icon in pairs(holders) do
			taken[icon] = true
		end

		local candidates = {}
		for _, mob in ipairs(free) do
			if mob.combat then
				candidates[#candidates + 1] = mob
			end
		end

		if not taken[SKULL] then
			local cross = holders[CROSS]
			if cross then
				changes[cross.guid] = SKULL
				taken[SKULL] = true
				taken[CROSS] = nil
			elseif candidates[1] then
				Give(table.remove(candidates, 1), SKULL)
			end
		end
		if not taken[CROSS] and candidates[1] then
			Give(table.remove(candidates, 1), CROSS)
		end
		return changes
	end

	local remaining = {}
	for _, mob in ipairs(free) do
		remaining[#remaining + 1] = mob
	end

	for _, icon in ipairs({ SKULL, CROSS }) do
		if not taken[icon] and remaining[1] then
			Give(table.remove(remaining, 1), icon)
		end
	end

	-- Crowd control goes to the most dangerous mobs left that it can hold.
	for _, cc in ipairs(crowdControl or {}) do
		if not taken[cc.icon] then
			for index, mob in ipairs(remaining) do
				if CanHold(cc, mob) then
					Give(table.remove(remaining, index), cc.icon)
					break
				end
			end
		end
	end

	-- Mobs left without an icon lose any icon Prokin gave them earlier.
	for _, mob in ipairs(remaining) do
		if mob.icon and assigned[mob.guid] == mob.icon then
			changes[mob.guid] = 0
		end
	end
	return changes
end

local function AddUnit(list, seen, unit, inCombat)
	-- A dead mob gives its icon back. This also covers WoW Forever, where addons cannot read the
	-- combat log for deaths.
	if Marker.assigned and next(Marker.assigned) and SafeCall(UnitIsDead, unit) then
		local deadGUID = SafeCall(UnitGUID, unit)
		if deadGUID and Marker.assigned[deadGUID] then
			Marker.assigned[deadGUID] = nil
		end
	end

	local mob = Marker.ReadUnit(unit)
	if not mob or seen[mob.guid] then
		return
	end

	-- Before the pull, only mobs near the player belong to the pack being marked.
	if not inCombat and not mob.combat and unit ~= 'target' and unit ~= 'mouseover' then
		local near = SafeCall(CheckInteractDistance, unit, Marker.PULL_RANGE_INDEX)
		if near == false then
			return
		end
	end

	seen[mob.guid] = true
	list[#list + 1] = mob
end

function Marker.CollectMobs(inCombat)
	local list, seen = {}, {}
	AddUnit(list, seen, 'target', inCombat)
	AddUnit(list, seen, 'mouseover', inCombat)

	local plates = type(C_NamePlate) == 'table' and SafeCall(C_NamePlate.GetNamePlates)
	if type(plates) == 'table' then
		for _, plate in ipairs(plates) do
			local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if type(unit) == 'string' then
				AddUnit(list, seen, unit, inCombat)
			end
		end
	else
		for index = 1, 40 do
			AddUnit(list, seen, 'nameplate' .. index, inCombat)
		end
	end
	return list
end

-- Forgets icons that were changed by someone else or belong to mobs no longer around.
function Marker.Tidy(mobs)
	local now = GetTime()
	for _, mob in ipairs(mobs) do
		local entry = Marker.assigned[mob.guid]
		if entry then
			if mob.icon ~= entry.icon then
				Marker.assigned[mob.guid] = nil
			else
				entry.seen = now
			end
		end
	end
	for guid, entry in pairs(Marker.assigned) do
		if now - entry.seen > Marker.FORGET_AFTER then
			Marker.assigned[guid] = nil
		end
	end
end

function Marker.GetAssignedIcons()
	local icons = {}
	for guid, entry in pairs(Marker.assigned) do
		icons[guid] = entry.icon
	end
	return icons
end

function Marker.Remember(guid, icon)
	for otherGUID, entry in pairs(Marker.assigned) do
		if entry.icon == icon then
			Marker.assigned[otherGUID] = nil
		end
	end
	if icon and icon > 0 then
		Marker.assigned[guid] = { icon = icon, seen = GetTime() }
	else
		Marker.assigned[guid] = nil
	end
end

-- Whether this client lets addons place icons themselves.
function Marker.CanMarkDirectly()
	return not Marker.IS_FOREVER and not Marker.directBlocked
end

function Marker.Scan()
	local direct = Marker.IsActive() and Marker.CanMarkDirectly()
	if not direct and not Marker.CanUsePack() then
		return
	end

	local inCombat = SafeCall(UnitAffectingCombat, 'player') and true or false
	local mobs = Marker.CollectMobs(inCombat)
	Marker.Tidy(mobs)
	if not direct then
		Marker.UpdateKeyButton(mobs, inCombat)
		Marker.UpdatePackButton(mobs, inCombat)
		return
	end

	local changes = Marker.Plan(mobs, Marker.GetAssignedIcons(), Marker.GetGroupCrowdControl(), inCombat)
	local placed = 0
	-- Kill icons first, so a throttled scan still gets Skull and Cross out.
	for _, icon in ipairs({ SKULL, CROSS, MOON, SQUARE, CIRCLE, DIAMOND, TRIANGLE, STAR, 0 }) do
		for _, mob in ipairs(mobs) do
			if changes[mob.guid] == icon and placed < Marker.MAX_MARKS_PER_SCAN then
				local ok = pcall(SetRaidTarget, mob.unit, icon)
				if not ok then
					Marker.directBlocked = true
					Print('The game refused a raid icon. Use the Mark Mob key binding to mark instead.')
					return
				end
				Marker.Remember(mob.guid, icon)
				placed = placed + 1
			end
		end
	end
end

-- Picks the icon for one mob, for the Mark Mob key: what the pack plan gives it, or else the
-- first free kill icon.
function Marker.PickIcon(mob, mobs, inCombat)
	if not mob then
		return nil
	end

	local list = { mob }
	for _, other in ipairs(mobs or {}) do
		if other.guid ~= mob.guid then
			list[#list + 1] = other
		end
	end

	local changes = Marker.Plan(list, Marker.GetAssignedIcons(), Marker.GetGroupCrowdControl(), inCombat)
	local icon = changes[mob.guid]
	if icon and icon > 0 then
		return icon
	end
	if mob.icon then
		return nil
	end

	local used = {}
	for _, other in ipairs(list) do
		if other.icon then
			used[other.icon] = true
		end
	end
	for _, entry in pairs(Marker.assigned) do
		used[entry.icon] = true
	end
	for _, candidate in ipairs({ SKULL, CROSS, MOON, SQUARE, CIRCLE, DIAMOND, TRIANGLE, STAR }) do
		if not used[candidate] then
			return candidate
		end
	end
end

-- The Mark Mob key presses this secure button, which places the icon through the game's own
-- raidtarget action. Its unit and icon can only change out of combat.
function Marker.EnsureKeyButton()
	if Marker.keyButton or type(CreateFrame) ~= 'function' then
		return Marker.keyButton
	end

	local button = CreateFrame('Button', 'ProkinMinimapMarkButton', UIParent, 'SecureActionButtonTemplate')
	button:SetAttribute('type', 'raidtarget')
	button:SetAttribute('action', 'set-unmarked')
	button:SetAttribute('unit', 'mouseover')
	button:SetAttribute('marker', SKULL)
	button:RegisterForClicks('AnyDown', 'AnyUp')
	button:SetScript('PostClick', function(self)
		if self.pendingGUID and self.pendingIcon then
			Marker.Remember(self.pendingGUID, self.pendingIcon)
		end
	end)
	Marker.keyButton = button

	local clear = CreateFrame('Button', 'ProkinMinimapClearMarksButton', UIParent, 'SecureActionButtonTemplate')
	clear:SetAttribute('type', 'raidtarget')
	clear:SetAttribute('action', 'clear-all')
	clear:RegisterForClicks('AnyDown', 'AnyUp')
	clear:SetScript('PostClick', function()
		Wipe(Marker.assigned)
	end)
	Marker.clearButton = clear
	return button
end

function Marker.UpdateKeyButton(mobs, inCombat)
	local button = Marker.EnsureKeyButton()
	if not button or (type(InCombatLockdown) == 'function' and InCombatLockdown()) then
		return
	end

	local unit, mob
	for _, candidate in ipairs({ 'mouseover', 'target' }) do
		for _, other in ipairs(mobs or {}) do
			if other.unit == candidate then
				unit, mob = candidate, other
				break
			end
		end
		if mob then
			break
		end
	end

	local icon = Marker.PickIcon(mob, mobs, inCombat)
	button.pendingGUID = mob and icon and mob.guid or nil
	button.pendingIcon = icon
	button:SetAttribute('unit', unit or 'mouseover')
	button:SetAttribute('marker', icon or SKULL)
end

-- Mark Pack: one key press marks the whole pack. The game's /tm command takes a unit, so a
-- secure macro with one /tm line per mob places every icon from that single press. The macro
-- is rewritten as the pack changes, but only out of combat, so this is for marking before the
-- pull; the Mark Mob key handles single mobs in a fight.
Marker.PACK_BINDING = 'CLICK ProkinMinimapMarkPackButton:LeftButton'
Marker.DEFAULT_PACK_KEY = '5'
Marker.PACK_MACRO_NAME = 'Prokin Mark Pack'
Marker.PACK_ICON_ORDER = { SKULL, CROSS, MOON, SQUARE, CIRCLE, DIAMOND, TRIANGLE, STAR, 0 }

function Marker.EnsurePackButton()
	if Marker.packButton or type(CreateFrame) ~= 'function' then
		return Marker.packButton
	end

	local button = CreateFrame('Button', 'ProkinMinimapMarkPackButton', UIParent, 'SecureActionButtonTemplate')
	button:SetAttribute('type', 'macro')
	button:SetAttribute('macrotext', '')
	button:RegisterForClicks('AnyDown', 'AnyUp')
	button:SetScript('PostClick', function(self, _, down)
		-- With both press and release registered, only count the press.
		if down == false then
			return
		end
		local pending = self.pending
		if pending and #pending > 0 then
			for _, entry in ipairs(pending) do
				Marker.Remember(entry.guid, entry.icon)
			end
			self.pending = nil
		elseif not self.fallthrough and not (type(InCombatLockdown) == 'function' and InCombatLockdown()) then
			-- Said at most every 30 seconds, so a key pressed often does not flood chat.
			local now = GetTime()
			if not Marker.idleNoticeAt or now - Marker.idleNoticeAt > 30 then
				Marker.idleNoticeAt = now
				local ready, reason = Marker.CanUsePack()
				Print(ready and 'Nothing to mark: no unmarked mobs are in range. Turn on enemy nameplates (V) so Prokin can see the pack.' or ('Mark Pack is idle: ' .. reason .. '.'))
			end
		end
	end)
	Marker.packButton = button
	return button
end

-- Builds the /tm lines for the planned changes, kill icons first. Returns the macro text and the
-- icons it will place.
function Marker.BuildPackMacro(mobs, changes)
	local lines, pending = {}, {}
	for _, icon in ipairs(Marker.PACK_ICON_ORDER) do
		for _, mob in ipairs(mobs) do
			if changes[mob.guid] == icon and type(mob.unit) == 'string' and mob.unit:match('^[%a]+%d*$') then
				-- "!" keeps /tm from toggling an icon off when the mob already has it.
				lines[#lines + 1] = string.format('/tm [@%s] %s', mob.unit, icon == 0 and '0' or ('!' .. icon))
				pending[#pending + 1] = { guid = mob.guid, icon = icon }
			end
		end
	end
	return table.concat(lines, '\n'), pending
end

function Marker.UpdatePackButton(mobs, inCombat)
	local button = Marker.EnsurePackButton()
	if not button or (type(InCombatLockdown) == 'function' and InCombatLockdown()) then
		return
	end

	local text, pending = '', nil
	if mobs and not inCombat and Marker.CanUsePack() then
		local changes = Marker.Plan(mobs, Marker.GetAssignedIcons(), Marker.GetGroupCrowdControl(), false)
		text, pending = Marker.BuildPackMacro(mobs, changes)
	end

	-- With nothing to mark, and all through combat, the key does its usual job.
	button.fallthrough = nil
	if text == '' then
		button.fallthrough = Marker.GetFallthroughMacro(Marker.boundPackKey)
		text = button.fallthrough or ''
	end
	if button:GetAttribute('macrotext') ~= text then
		button:SetAttribute('macrotext', text)
	end
	button.pending = pending
end

-- Whether Mark Pack may mark here: alone anywhere, as a party's leader (or any member with
-- /pkm mark anyone), or as a raid's leader or assistant, who are the only raid members the game
-- lets place icons.
function Marker.CanUsePack()
	local settings = Marker.GetSettings()
	if not settings.enabled then
		return false, 'smart marking is turned off'
	end
	if Marker.IsOtherMarkerLoaded() then
		return false, 'AutoMarkAssist is loaded'
	end

	if IsInRaid() then
		local leader = SafeCall(UnitIsGroupLeader, 'player')
		local assistant = SafeCall(UnitIsGroupAssistant, 'player')
		if not leader and not assistant then
			return false, 'only the raid leader and assistants can mark'
		end
	elseif IsInGroup() and not settings.anyMember and not SafeCall(UnitIsGroupLeader, 'player') then
		return false, 'you are not the group leader (/pkm mark anyone allows it)'
	end
	return true
end

-- Action bar bindings and the buttons they press, so a key Mark Pack holds can still use its
-- action button through /click.
Marker.BAR_BUTTONS = {
	ACTIONBUTTON = 'ActionButton',
	MULTIACTIONBAR1BUTTON = 'MultiBarBottomLeftButton',
	MULTIACTIONBAR2BUTTON = 'MultiBarBottomRightButton',
	MULTIACTIONBAR3BUTTON = 'MultiBarRightButton',
	MULTIACTIONBAR4BUTTON = 'MultiBarLeftButton',
	MULTIACTIONBAR5BUTTON = 'MultiBar5Button',
	MULTIACTIONBAR6BUTTON = 'MultiBar6Button',
	MULTIACTIONBAR7BUTTON = 'MultiBar7Button',
}

-- A /click line that does what the key normally does, or nil when that cannot be pressed for it.
function Marker.GetFallthroughMacro(key)
	if not key or type(GetBindingAction) ~= 'function' then
		return nil
	end

	local action = SafeCall(GetBindingAction, key)
	if type(action) ~= 'string' or action == '' then
		return nil
	end

	local frameName, mouseButton
	local prefix, index = action:match('^(%u[%u%d]-BUTTON)(%d+)$')
	if prefix and Marker.BAR_BUTTONS[prefix] then
		frameName, mouseButton = Marker.BAR_BUTTONS[prefix] .. index, 'LeftButton'
	else
		frameName, mouseButton = action:match('^CLICK ([^:]+):(.+)$')
	end
	if not frameName or not _G[frameName] then
		return nil
	end

	-- Action buttons act on key down or key up, following the player's setting.
	local onKeyDown = type(GetCVarBool) == 'function' and GetCVarBool('ActionButtonUseKeyDown')
	return string.format('/click %s %s%s', frameName, mouseButton, onKeyDown and ' 1' or '')
end

-- Whether the key already does something Mark Pack cannot pass on.
function Marker.KeyHasOtherAction(key)
	local action = type(GetBindingAction) == 'function' and SafeCall(GetBindingAction, key)
	return type(action) == 'string' and action ~= '' and not Marker.GetFallthroughMacro(key)
end

-- The key Mark Pack uses: one the player bound in Key Bindings wins, otherwise Prokin's setting.
function Marker.GetPackKey()
	local bound = type(GetBindingKey) == 'function' and GetBindingKey(Marker.PACK_BINDING)
	if bound then
		return bound, true
	end

	local key = Marker.GetSettings().packKey
	if key == false then
		return nil
	end
	return key or Marker.DEFAULT_PACK_KEY, false
end

-- Prokin's key is an override binding, so the player's saved bindings never change. It is held
-- wherever Mark Pack can mark, except where The Burning Crusade Anniversary marks on its own.
-- When there is nothing to mark, and in combat, it passes the press on to the key's action
-- button. A key bound to something it cannot pass on is only held inside instances. Bindings
-- cannot change in combat, so a change waits for combat to end.
function Marker.ApplyPackBinding()
	local button = Marker.EnsurePackButton()
	if not button or type(SetOverrideBindingClick) ~= 'function' then
		return
	end
	if type(InCombatLockdown) == 'function' and InCombatLockdown() then
		Marker.bindingPending = true
		return
	end
	Marker.bindingPending = nil

	local key, fromKeyBindings = Marker.GetPackKey()
	local wanted = not fromKeyBindings and key and Marker.CanUsePack() and not (Marker.IsActive() and Marker.CanMarkDirectly()) and key or nil
	if wanted and Marker.KeyHasOtherAction(wanted) and not SafeCall(IsInInstance) then
		wanted = nil
	end
	if wanted == Marker.boundPackKey then
		return
	end

	ClearOverrideBindings(button)
	Marker.boundPackKey = nil
	if wanted then
		SetOverrideBindingClick(button, true, wanted, 'ProkinMinimapMarkPackButton', 'LeftButton')
		Marker.boundPackKey = wanted
		local settings = Marker.GetSettings()
		if not settings.packKeyFallthroughNoticeShown then
			settings.packKeyFallthroughNoticeShown = true
			Print(string.format('Mark Pack is on %s: near unmarked mobs, press %s once to mark the pack. With nothing to mark, and in combat, %s still uses its action button. /pkm mark key <key> changes it, /pkm mark key none turns it off.', wanted, wanted, wanted))
		end
	end
	Marker.UpdatePackButton(nil, false)
end

-- An account-wide macro that presses Mark Pack, so every character can put it on an action bar.
-- Created once per account; if the player deletes it, Prokin leaves it deleted.
function Marker.EnsurePackMacro()
	local settings = Marker.GetSettings()
	if settings.packMacroCreated or type(CreateMacro) ~= 'function' or type(GetMacroIndexByName) ~= 'function' then
		return
	end
	if type(InCombatLockdown) == 'function' and InCombatLockdown() then
		return
	end

	local existing = SafeCall(GetMacroIndexByName, Marker.PACK_MACRO_NAME)
	if existing and existing > 0 then
		settings.packMacroCreated = true
		return
	end

	local ok, index = pcall(CreateMacro, Marker.PACK_MACRO_NAME, 'INV_Misc_QuestionMark', '#showtooltip\n/click ProkinMinimapMarkPackButton LeftButton 1', nil)
	if ok and index and index ~= 0 then
		settings.packMacroCreated = true
		Print('Created the account macro "' .. Marker.PACK_MACRO_NAME .. '" (Esc > Macros > General). Drag it to an action bar to mark packs with a click.')
	end
end

function Marker.SetPackKey(argument)
	local settings = Marker.GetSettings()
	local key = string.upper(string.match(argument or '', '^%s*(%S*)') or '')
	if key == '' then
		local current, fromKeyBindings = Marker.GetPackKey()
		Print(current and string.format('Mark Pack key: %s%s.', current, fromKeyBindings and ' (set in Key Bindings)' or '') or 'Mark Pack has no key. /pkm mark key <key> sets one.')
		return
	end

	if key == 'NONE' or key == 'OFF' then
		settings.packKey = false
		Print('Mark Pack key turned off. You can still bind it in Key Bindings > AddOns > Prokin Minimap, or use the "' .. Marker.PACK_MACRO_NAME .. '" macro.')
	elseif key == 'DEFAULT' or key == 'RESET' then
		settings.packKey = nil
		Print('Mark Pack key reset to ' .. Marker.DEFAULT_PACK_KEY .. '.')
	elseif key:match('^[%w%-]+$') then
		settings.packKey = key
		Print('Mark Pack key set to ' .. key .. '.')
	else
		Print('Usage: /pkm mark key <key>, for example /pkm mark key F or /pkm mark key SHIFT-5. /pkm mark key none turns it off.')
		return
	end

	Marker.boundPackKey = Marker.boundPackKey and '' or nil
	Marker.ApplyPackBinding()
	if Marker.bindingPending then
		Print('The key changes when combat ends.')
	end
end

function Marker.OnUnitDied(guid)
	if guid and Marker.assigned[guid] then
		Marker.assigned[guid] = nil
		if Marker.IsActive() and Marker.CanMarkDirectly() then
			Marker.Scan()
		end
	end
end

function Marker.AnnounceState()
	local active, reason = Marker.GetActiveState()
	if active == Marker.lastActive then
		return
	end
	Marker.lastActive = active

	if active then
		if Marker.CanMarkDirectly() then
			Print('Smart marking is on: you lead this dungeon group, so packs are marked as you approach them. /pkm mark off turns it off.')
		else
			Print('Smart marking is on. WoW Forever only lets the game place icons from a key press: hover a mob and press your Mark Mob key (Key Bindings > AddOns > Prokin Minimap).')
		end
	elseif reason == 'AutoMarkAssist is loaded' then
		Print('Smart marking is paused because AutoMarkAssist is loaded.')
	end
end

function Marker.PrintStatus()
	local settings = Marker.GetSettings()
	local active, reason = Marker.GetActiveState()
	Print(string.format('Smart marking: %s%s. Marks for: %s. Mode: %s.',
		settings.enabled and 'on' or 'off',
		active and ', marking now' or (settings.enabled and (' (' .. reason .. ')') or ''),
		settings.anyMember and 'any group member' or 'group leader only',
		Marker.CanMarkDirectly() and 'automatic' or 'Mark Pack and Mark Mob keys'))
	local key = Marker.GetPackKey()
	local packReady, packReason = Marker.CanUsePack()
	Print(string.format('Mark Pack key: %s. %s', key or 'none',
		packReady and 'Near unmarked mobs, press it once to mark the whole pack; otherwise it uses its usual action.' or ('Idle: ' .. packReason .. '.')))

	local crowdControl = Marker.GetGroupCrowdControl()
	local names = {}
	for _, cc in ipairs(crowdControl) do
		names[#names + 1] = cc.spell .. ' = ' .. Marker.ICON_NAMES[cc.icon]
	end
	Print('Kill order: Skull, then Cross. Crowd control: ' .. (#names > 0 and table.concat(names, ', ') or 'none in this group') .. '.')
end

-- Adds or removes the target's NPC ID from a settings list, returning the new state.
local function ToggleTargetNpc(listName, label)
	local guid = SafeCall(UnitGUID, 'target')
	local npcID = Marker.GetNpcID(guid)
	if not npcID then
		Print('Target an NPC first.')
		return
	end

	local list = Marker.GetSettings()[listName]
	list[npcID] = not list[npcID] or nil
	local name = SafeCall(UnitName, 'target') or ('NPC ' .. npcID)
	Print(string.format('%s %s %s.', name, list[npcID] and 'is now' or 'is no longer', label))
end

function Marker.HandleSlash(argument)
	local action = string.lower(string.match(argument or '', '^(%S*)') or '')
	local settings = Marker.GetSettings()

	if action == 'on' or action == 'off' then
		settings.enabled = action == 'on'
		if not settings.enabled then
			Wipe(Marker.assigned)
		end
		Marker.lastActive = nil
		Marker.ApplyPackBinding()
		Print('Smart marking turned ' .. action .. '.')
	elseif action == 'leader' or action == 'anyone' then
		settings.anyMember = action == 'anyone'
		Marker.lastActive = nil
		Marker.ApplyPackBinding()
		Print(settings.anyMember and 'Smart marking now marks for any group member, not only the leader.' or 'Smart marking now only marks when you lead the group.')
	elseif action == 'key' then
		Marker.SetPackKey(string.match(argument or '', '^%S*%s*(.-)%s*$'))
	elseif action == 'priority' then
		ToggleTargetNpc('priority', 'a kill priority')
	elseif action == 'ignore' then
		ToggleTargetNpc('ignore', 'ignored by smart marking')
	elseif action == 'clear' then
		Wipe(Marker.assigned)
		if Marker.CanMarkDirectly() and type(RemoveRaidTargets) == 'function' and pcall(RemoveRaidTargets) then
			Print('Cleared all raid icons.')
		else
			Print('Forgot the icons Prokin placed. Use the Clear All Marks key binding to remove them from mobs.')
		end
	else
		Marker.PrintStatus()
		Print('Commands: /pkm mark [on|off], /pkm mark key <key|none|default>, /pkm mark leader|anyone, /pkm mark priority (target), /pkm mark ignore (target), /pkm mark clear.')
	end
end

function Marker.OnEvent(_, event, ...)
	if event == 'COMBAT_LOG_EVENT_UNFILTERED' then
		if type(CombatLogGetCurrentEventInfo) == 'function' then
			local _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
			if not IsSecret(subevent) and subevent == 'UNIT_DIED' and not IsSecret(destGUID) then
				Marker.OnUnitDied(destGUID)
			end
		end
		return
	end

	-- A refused call does not raise a Lua error, so watch for the game blocking one.
	if event == 'ADDON_ACTION_FORBIDDEN' or event == 'ADDON_ACTION_BLOCKED' then
		local addon, fn = ...
		if addon == ADDON_NAME and type(fn) == 'string' and fn:find('SetRaidTarget', 1, true) and not Marker.directBlocked then
			Marker.directBlocked = true
			Print('The game refused a raid icon. Use the Mark Mob key binding to mark instead.')
		end
		return
	end

	if event == 'PLAYER_ENTERING_WORLD' or event == 'GROUP_ROSTER_UPDATE' or event == 'PARTY_LEADER_CHANGED' then
		if event == 'PLAYER_ENTERING_WORLD' then
			Wipe(Marker.assigned)
			if Marker.IS_FOREVER and type(C_Timer) == 'table' and C_Timer.After then
				C_Timer.After(3, Marker.EnsurePackMacro)
			end
		end
		Marker.AnnounceState()
		Marker.ApplyPackBinding()
	end

	if event == 'UPDATE_BINDINGS' or (event == 'PLAYER_REGEN_ENABLED' and Marker.bindingPending) then
		Marker.ApplyPackBinding()
	end

	-- Combat lockdown starts after this event, so the key is switched to its usual action now.
	if event == 'PLAYER_REGEN_DISABLED' then
		Marker.UpdatePackButton(nil, true)
		return
	end

	if Marker.IsActive() or Marker.CanUsePack() then
		Marker.Scan()
	elseif Marker.packButton and Marker.packButton.pending then
		Marker.UpdatePackButton(nil, false)
	end
end

if type(CreateFrame) == 'function' then
	BINDING_HEADER_PROKINMINIMAP = 'Prokin Minimap'
	_G['BINDING_NAME_CLICK ProkinMinimapMarkButton:LeftButton'] = 'Mark Mob (smart marking)'
	_G['BINDING_NAME_CLICK ProkinMinimapClearMarksButton:LeftButton'] = 'Clear All Marks'
	_G['BINDING_NAME_CLICK ProkinMinimapMarkPackButton:LeftButton'] = 'Mark Pack (smart marking)'

	Marker.EnsureKeyButton()
	Marker.EnsurePackButton()
	local events = CreateFrame('Frame')
	for _, event in ipairs({ 'PLAYER_ENTERING_WORLD', 'GROUP_ROSTER_UPDATE', 'PARTY_LEADER_CHANGED', 'UPDATE_MOUSEOVER_UNIT', 'PLAYER_TARGET_CHANGED', 'NAME_PLATE_UNIT_ADDED', 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED', 'ADDON_ACTION_FORBIDDEN', 'ADDON_ACTION_BLOCKED', 'UPDATE_BINDINGS' }) do
		events:RegisterEvent(event)
	end
	-- WoW Forever restricts the combat log: registering it is a forbidden action there, even inside
	-- pcall. Marking on Forever comes from key presses, and deaths are seen on the mobs instead.
	if not Marker.IS_FOREVER then
		events:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
	end
	events:SetScript('OnEvent', Marker.OnEvent)

	local elapsedSinceScan = 0
	events:SetScript('OnUpdate', function(_, elapsed)
		elapsedSinceScan = elapsedSinceScan + elapsed
		if elapsedSinceScan >= Marker.SCAN_INTERVAL then
			elapsedSinceScan = 0
			-- Holds or releases the Mark Pack key as marking turns on and off.
			if not Marker.bindingPending then
				Marker.ApplyPackBinding()
			end
			if Marker.IsActive() or Marker.CanUsePack() then
				Marker.Scan()
			end
		end
	end)
end
