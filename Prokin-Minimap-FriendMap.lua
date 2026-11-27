-- Friends and guild members on Blizzard's world map.
--
-- Everyone online on your friends list, your Battle.net friends playing this game on your faction
-- and realm pool, and your guild show on the world map by zone, as the game's own lists report it:
-- a badge on the zone, with who is there in its tooltip. Anyone who shares their position shows
-- as a class-coloured dot where they stand instead.
--
-- Positions travel as addon messages in OpenMap's format, so Prokin Minimap and OpenMap users see
-- each other: prefix "OpenMapLoc", "L1 map x y class level" (tab-separated; a uiMapID and x, y on
-- it from 0 to 1), "L0" (stopped sharing), and the hellos "H1"/"H2" that tell friends you can
-- receive. Sharing your own position is on by default and can be turned off in Options; it never
-- happens inside an instance or while Battle.net's Appear Offline is on, and is left to OpenMap when
-- it is loaded.
--
-- Adapted from OpenMap's Map/Friends.lua (MIT License, Copyright (c) 2026 OpenMap contributors).
-- The notice is in README.md's Credits.

local ADDON_NAME = ...
local FriendMap = _G.ProkinMinimapFriendMap or {}
_G.ProkinMinimapFriendMap = FriendMap

FriendMap.PREFIX = 'OpenMapLoc'
FriendMap.TICK = 2               -- seconds between looks at where you are, while sharing
FriendMap.SEND_EVERY = 10        -- seconds between positions sent while you move
FriendMap.STILL_EVERY = 60       -- ... and while you stand still
FriendMap.GONE_AFTER = 150       -- seconds without word before a shared position is dropped
FriendMap.MOVED = 0.002          -- a smaller move on a zone's map is not a move
FriendMap.SEND_GAP = 0.5         -- seconds between messages sent
FriendMap.LIST_MAX = 25          -- names in a zone badge's tooltip
FriendMap.DOT_SIZE = 12
FriendMap.BADGE_SIZE = 20

local roster = {}        -- full name -> { name, class, level, area, guild, friend, guid }: online now
local friends = {}       -- full name -> { whisper = name } or { bn = gameAccountID }
local known = {}         -- full name -> true: friends whose addon answered a hello
local live = {}          -- full name -> { map, x, y, class, level, guild, at }: positions heard
FriendMap.roster, FriendMap.friends, FriendMap.known, FriendMap.live = roster, friends, known, live

local realm, zoneByName, classByName
local last = { at = -math.huge }
local sharing = false

local function IsSecret(value)
	if type(issecretvalue) ~= 'function' then
		return false
	end
	local ok, secret = pcall(issecretvalue, value)
	return not ok or secret == true
end

local function Value(value)
	if IsSecret(value) then
		return nil
	end
	return value
end

local function SafeCall(fn, ...)
	if type(fn) ~= 'function' then
		return nil
	end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Value(a), Value(b), Value(c), Value(d)
end

local function Settings()
	if type(ProkinMinimapDB) ~= 'table' then
		ProkinMinimapDB = {}
	end
	local db = ProkinMinimapDB
	if type(db.friendMap) ~= 'table' then
		db.friendMap = {}
	end
	local settings = db.friendMap
	if type(settings.friends) ~= 'boolean' then settings.friends = true end
	if type(settings.guild) ~= 'boolean' then settings.guild = true end
	-- Sharing is on until the player turns it off. shareChosen marks a choice made in Options, so a
	-- value saved by an earlier default never counts as turning it off.
	if settings.shareChosen ~= true then settings.share = true end
	return settings
end
FriendMap.Settings = Settings

-- OpenMap handles its own sending; Prokin then only listens and draws on Blizzard's map.
function FriendMap.OpenMapLoaded()
	local isLoaded = (type(C_AddOns) == 'table' and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	return SafeCall(isLoaded, 'OpenMap') and true or false
end

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

local function Plain(name)
	return (name:gsub("[%s%-']", '')):lower()
end

local function Realm()
	if not realm then
		local name = SafeCall(GetNormalizedRealmName)
		if type(name) ~= 'string' or name == '' then
			name = (SafeCall(GetRealmName) or ''):gsub('[%s%-]', '')
		end
		if name == '' then
			return ''
		end
		realm = name
	end
	return realm
end

-- WoW Forever's numbered realms share one world: CAMWOWUS1Realm3PvE and CAMWOWUS2Realm8PvE are
-- the same pool. The region and ruleset still tell pools apart.
function FriendMap.RealmPool(name)
	local key = Plain(name)
	return (key:gsub('%d+realm', 'realm'):gsub('realm%d+', 'realm'))
end

local function SamePool(full)
	local _, otherRealm = full:match('^([^%-]+)%-(.+)$')
	local mine = Realm()
	return otherRealm ~= nil and mine ~= '' and FriendMap.RealmPool(otherRealm) == FriendMap.RealmPool(mine)
end

-- "Name-Realm"; names on your own realm come without one.
local function Full(name, otherRealm)
	if IsSecret(name) or type(name) ~= 'string' or name == '' then
		return nil
	end
	if name:find('-', 1, true) then
		return name
	end
	if type(otherRealm) == 'string' and otherRealm ~= '' then
		return name .. '-' .. otherRealm:gsub('[%s%-]', '')
	end
	return name .. '-' .. Realm()
end
FriendMap.Full = Full

-- The name shown: never the realm (Forever's realm names are long), marked (*) when it is another.
local function Shown(full)
	local name, otherRealm = full:match('^([^%-]+)%-?(.*)$')
	if otherRealm ~= '' and Realm() ~= '' and Plain(otherRealm) ~= Plain(Realm()) then
		return name .. (FOREIGN_SERVER_LABEL or ' (*)')
	end
	return name
end

local function IsMe(full)
	local me = SafeCall(UnitName, 'player')
	return type(full) == 'string' and type(me) == 'string' and (full == me or full:match('^([^%-]+)') == me and SamePool(full))
end

local function ClassFile(name)
	if type(name) ~= 'string' then
		return nil
	end
	if name:match('^%u+$') then
		return name
	end
	if not classByName then
		classByName = {}
		for file, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classByName[localized] = file end
		for file, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classByName[localized] = file end
	end
	return classByName[name]
end

local function ClassColor(class)
	local color = type(class) == 'string' and ((type(C_ClassColor) == 'table' and SafeCall(C_ClassColor.GetClassColor, class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if type(color) == 'table' and color.r then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end
FriendMap.ClassColor = ClassColor

-- A zone's uiMapID from its name, as the friends list and guild roster give it.
function FriendMap.ZoneMap(area)
	if IsSecret(area) or type(area) ~= 'string' or area == '' or type(C_Map) ~= 'table' then
		return nil
	end
	if not zoneByName then
		local found = {}
		local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
		for _, root in ipairs({ 947, 946 }) do
			local children = SafeCall(C_Map.GetMapChildrenInfo, root, zoneType, true)
			for _, info in ipairs(type(children) == 'table' and children or {}) do
				if type(info.name) == 'string' and not found[info.name] then
					found[info.name] = info.mapID
				end
			end
			if next(found) then
				break
			end
		end
		if not next(found) then
			return nil
		end
		zoneByName = found
	end
	return zoneByName[area]
end

--------------------------------------------------------------------------------
-- Who is online
--------------------------------------------------------------------------------

local function AddPerson(full, level, area, className, how, guid, isGuild)
	if not full or IsMe(full) then
		return
	end
	local person = roster[full]
	if not person then
		if not isGuild and not SamePool(full) then
			return -- a friend in another realm pool is not on your map
		end
		person = { name = Shown(full), level = tonumber(Value(level)), area = Value(area), class = ClassFile(Value(className)) }
		roster[full] = person
	end
	person.guid = person.guid or Value(guid)
	if isGuild then
		person.guild = true
	else
		person.friend = true
		if how and (how.bn or not friends[full]) then
			friends[full] = how
		end
	end
end

local function SameFaction(game)
	local mine = SafeCall(UnitFactionGroup, 'player')
	return type(mine) == 'string' and mine ~= '' and Value(game.factionName) == mine
end

function FriendMap.Scan()
	local before = {}
	for full in pairs(friends) do before[full] = true end
	for _, list in ipairs({ roster, friends }) do
		for key in pairs(list) do list[key] = nil end
	end

	if IsInGuild and IsInGuild() and type(GetGuildRosterInfo) == 'function' then
		for index = 1, tonumber(SafeCall(GetNumGuildMembers)) or 0 do
			local ok, name, _, _, level, _, area, _, _, online, _, class, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, index)
			if ok and Value(online) then
				AddPerson(Full(Value(name)), level, area, class, nil, guid, true)
			end
		end
	end

	local friendList = type(C_FriendList) == 'table' and C_FriendList or nil
	if friendList and friendList.GetNumFriends and friendList.GetFriendInfoByIndex then
		for index = 1, tonumber(SafeCall(friendList.GetNumFriends)) or 0 do
			local info = SafeCall(friendList.GetFriendInfoByIndex, index)
			if type(info) == 'table' and Value(info.connected) then
				AddPerson(Full(Value(info.name)), info.level, info.area, info.className, { whisper = Value(info.name) }, info.guid)
			end
		end
	end

	local battleNet = type(C_BattleNet) == 'table' and C_BattleNet or nil
	if battleNet and battleNet.GetFriendAccountInfo and type(BNGetNumFriends) == 'function' then
		for index = 1, tonumber(SafeCall(BNGetNumFriends)) or 0 do
			local account = SafeCall(battleNet.GetFriendAccountInfo, index)
			local game = type(account) == 'table' and account.gameAccountInfo
			if type(game) == 'table' and Value(game.isOnline) and Value(game.clientProgram) == (BNET_CLIENT_WOW or 'WoW')
				and (not WOW_PROJECT_ID or Value(game.wowProjectID) == WOW_PROJECT_ID) and SameFaction(game) then
				AddPerson(Full(Value(game.characterName), Value(game.realmName)), game.characterLevel, game.areaName,
					game.className, { bn = Value(game.gameAccountID) }, game.playerGuid)
			end
		end
	end

	-- A friend who just came online gets a hello, so their addon learns we can receive.
	if not FriendMap.OpenMapLoaded() then
		for full in pairs(friends) do
			if not before[full] then
				FriendMap.ToFriend(full, 'H1')
			end
		end
	end
	FriendMap.dirty = true
end

--------------------------------------------------------------------------------
-- Sending, one message every SEND_GAP seconds; a newer one to the same place replaces it
--------------------------------------------------------------------------------

local outbox, order = {}, {}

-- Battle.net's Appear Offline: friends are told you are offline, so your position is not sent.
function FriendMap.AppearOffline()
	if type(BNGetInfo) ~= 'function' or type(C_BattleNet) ~= 'table' or not C_BattleNet.GetAccountInfoByID then
		return false
	end
	local _, _, account = SafeCall(BNGetInfo)
	local info = account and SafeCall(C_BattleNet.GetAccountInfoByID, account)
	if type(info) ~= 'table' then
		return false
	end
	local game = type(info.gameAccountInfo) == 'table' and info.gameAccountInfo or nil
	return Value(info.appearOffline) == true or (game and Value(game.isAppearOffline) == true) or false
end

function FriendMap.SendNext()
	local key = table.remove(order, 1)
	if not key then
		return false
	end
	local message = outbox[key]
	outbox[key] = nil
	if message.text:sub(1, 2) == 'L1' and (not Settings().share or FriendMap.AppearOffline()) then
		return true
	end
	if message.bn then
		if type(BNSendGameData) == 'function' then pcall(BNSendGameData, message.bn, FriendMap.PREFIX, message.text) end
	elseif type(C_ChatInfo) == 'table' and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, FriendMap.PREFIX, message.text, message.channel, message.target)
	end
	return true
end

local function Send(key, text, channel, target, bn)
	if not outbox[key] then
		order[#order + 1] = key
	end
	outbox[key] = { text = text, channel = channel, target = target, bn = bn }
	if FriendMap.sender then
		FriendMap.sender:Show()
	end
end
FriendMap.Send = Send

function FriendMap.ToFriend(full, text)
	local how = friends[full]
	if not how then
		return
	end
	if how.bn then
		Send(full, text, nil, nil, how.bn)
	elseif how.whisper then
		Send(full, text, 'WHISPER', how.whisper)
	end
end

local function Broadcast(text)
	local inGuild = IsInGuild and IsInGuild()
	if inGuild then
		Send('GUILD', text, 'GUILD')
	end
	for full in pairs(known) do
		local person = roster[full]
		if friends[full] and not (inGuild and person and person.guild) then
			FriendMap.ToFriend(full, text)
		end
	end
end

-- Where you are: a zone's uiMapID and x, y on it; nil inside an instance or when unknown.
function FriendMap.Here()
	if SafeCall(IsInInstance) or type(C_Map) ~= 'table' then
		return nil
	end
	local mapID = SafeCall(C_Map.GetBestMapForUnit, 'player')
	if type(mapID) ~= 'number' then
		return nil
	end
	local position = SafeCall(C_Map.GetPlayerMapPosition, mapID, 'player')
	if not position then
		return nil
	end
	local x, y
	if position.GetXY then
		x, y = SafeCall(position.GetXY, position)
	else
		x, y = Value(position.x), Value(position.y)
	end
	if type(x) ~= 'number' or type(y) ~= 'number' or (x <= 0 and y <= 0) then
		return nil
	end
	return mapID, x, y
end

-- Said once per account, at the first login with sharing on, so no one shares without knowing.
function FriendMap.AnnounceSharing()
	local settings = Settings()
	if not settings.share or settings.shareNoticeShown or FriendMap.OpenMapLoaded() then
		return
	end
	settings.shareNoticeShown = true
	DEFAULT_CHAT_FRAME:AddMessage(string.format('|cff33ff99%s|r: Your location is shared with your guild and with friends who use Prokin Minimap or OpenMap, so you show on their world map. It is never sent inside dungeons, raids or battlegrounds, or while you appear offline. Turn it off with "Share my location with friends and guild" in Options (right-click the Prokin minimap button).', ADDON_NAME or 'Prokin-Minimap'))
end

function FriendMap.Tick()
	if FriendMap.OpenMapLoaded() then
		return
	end
	local stop = not Settings().share or FriendMap.AppearOffline()
	local mapID, x, y
	if not stop then
		mapID, x, y = FriendMap.Here()
		stop = not mapID
	end
	if stop then
		if sharing then
			sharing = false
			last.at, last.text = -math.huge, nil
			Broadcast('L0')
		end
		return
	end

	local moved = mapID ~= last.map or math.abs(x - (last.x or 0)) > FriendMap.MOVED or math.abs(y - (last.y or 0)) > FriendMap.MOVED
	if GetTime() - last.at < (moved and FriendMap.SEND_EVERY or FriendMap.STILL_EVERY) then
		return
	end
	local _, class = SafeCall(UnitClass, 'player')
	last.map, last.x, last.y, last.at = mapID, x, y, GetTime()
	last.text = string.format('L1\t%d\t%.4f\t%.4f\t%s\t%d', mapID, x, y, type(class) == 'string' and class or '', tonumber(SafeCall(UnitLevel, 'player')) or 0)
	sharing = true
	Broadcast(last.text)
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

function FriendMap.Heard(full, text, fromGuild)
	local kind, mapID, x, y, class, level = strsplit('\t', text, 6)
	if friends[full] then
		known[full] = true
	end
	if kind == 'H1' or kind == 'H2' then
		-- A hello is answered, with our position too when we share it.
		if kind == 'H1' and friends[full] and not FriendMap.OpenMapLoaded() then
			FriendMap.ToFriend(full, sharing and Settings().share and last.text or 'H2')
		end
		return
	end
	if not fromGuild and not friends[full] then
		return -- a whisper only counts from a friend
	end
	if kind == 'L0' then
		live[full] = nil
		FriendMap.dirty = true
	elseif kind == 'L1' then
		mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
		if not (mapID and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then
			return
		end
		local person = roster[full]
		live[full] = { map = mapID, x = x, y = y, class = class and class:match('^%u+$') or (person and person.class),
			level = tonumber(level) or (person and person.level), guild = fromGuild or (person and person.guild) or false, at = GetTime() }
		FriendMap.dirty = true
	end
end

function FriendMap.OnAddonMessage(prefix, text, channel, from)
	if prefix ~= FriendMap.PREFIX or IsSecret(text) or IsSecret(from) or IsSecret(channel) or type(text) ~= 'string' then
		return
	end
	if channel ~= 'GUILD' and channel ~= 'WHISPER' then
		return
	end
	local full = Full(from)
	if not full or IsMe(full) then
		return
	end
	FriendMap.Heard(full, text, channel == 'GUILD')
end

function FriendMap.OnBattleNetMessage(prefix, text, gameAccountID)
	if prefix ~= FriendMap.PREFIX or IsSecret(text) or IsSecret(gameAccountID) or type(text) ~= 'string' or type(gameAccountID) ~= 'number' then
		return
	end
	local game = type(C_BattleNet) == 'table' and SafeCall(C_BattleNet.GetGameAccountInfoByID, gameAccountID)
	local full = type(game) == 'table' and Full(Value(game.characterName), Value(game.realmName))
	if not full or IsMe(full) or not SameFaction(game) then
		return -- the other faction's position is never shown
	end
	friends[full] = friends[full] or { bn = gameAccountID }
	FriendMap.Heard(full, text, false)
end

--------------------------------------------------------------------------------
-- On Blizzard's world map
--------------------------------------------------------------------------------

-- Where a point on one map falls on the map being viewed, as 0..1 x and y, or nil.
function FriendMap.Project(fromMap, x, y, shownMap)
	if fromMap == shownMap then
		return x, y
	end
	if type(C_Map) ~= 'table' or not C_Map.GetMapRectOnMap then
		return nil
	end
	local left, right, top, bottom = SafeCall(C_Map.GetMapRectOnMap, fromMap, shownMap)
	if type(left) ~= 'number' or type(right) ~= 'number' or right <= left or bottom <= top then
		return nil
	end
	local px, py = left + x * (right - left), top + y * (bottom - top)
	if px < 0 or px > 1 or py < 0 or py > 1 then
		return nil
	end
	return px, py
end

-- What to draw for the map being viewed: dots for shared positions, and one badge per zone for
-- everyone else online. Pure, so it can be tested.
function FriendMap.BuildMarks(shownMap, now)
	local settings = Settings()
	local dots, badges, placed = {}, {}, {}
	local function Wanted(person)
		return person and ((person.guild and settings.guild) or (person.friend and settings.friends))
	end

	for full, place in pairs(live) do
		local person = roster[full]
		if now - place.at > FriendMap.GONE_AFTER or not person then
			if now - place.at > FriendMap.GONE_AFTER then live[full] = nil end
		elseif Wanted(person) then
			local x, y = FriendMap.Project(place.map, place.x, place.y, shownMap)
			if x then
				dots[#dots + 1] = { full = full, name = person.name, class = place.class or person.class, level = place.level or person.level, guild = person.guild, area = person.area, x = x, y = y }
			end
			placed[full] = true
		end
	end

	local byZone = {}
	for full, person in pairs(roster) do
		if not placed[full] and Wanted(person) then
			local zone = FriendMap.ZoneMap(person.area)
			if zone then
				byZone[zone] = byZone[zone] or {}
				table.insert(byZone[zone], { full = full, name = person.name, class = person.class, level = person.level, guild = person.guild, friend = person.friend })
			end
		end
	end
	for zone, people in pairs(byZone) do
		local x, y
		if zone == shownMap then
			x, y = 0.5, 0.06 -- the zone itself is on screen: a badge along its top edge
		else
			x, y = FriendMap.Project(zone, 0.5, 0.5, shownMap)
		end
		if x then
			table.sort(people, function(a, b) return a.name < b.name end)
			badges[#badges + 1] = { zone = zone, people = people, x = x, y = y }
		end
	end
	return dots, badges
end

local pins = {}

local function WorldCanvas()
	local worldMap = _G.WorldMapFrame
	local scroll = worldMap and worldMap.ScrollContainer
	return worldMap, scroll and scroll.Child
end

local function ShowDotTooltip(pin)
	local mark = pin.mark
	if not mark then return end
	GameTooltip:SetOwner(pin, 'ANCHOR_RIGHT')
	local r, g, b = ClassColor(mark.class)
	GameTooltip:AddLine(mark.name, r, g, b)
	GameTooltip:AddLine(string.format('%s%s', mark.level and ('Level ' .. mark.level .. '  ') or '', mark.guild and 'Guild' or 'Friend'), 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function ShowBadgeTooltip(pin)
	local mark = pin.mark
	if not mark then return end
	GameTooltip:SetOwner(pin, 'ANCHOR_RIGHT')
	local info = type(C_Map) == 'table' and SafeCall(C_Map.GetMapInfo, mark.zone)
	GameTooltip:AddLine(type(info) == 'table' and info.name or 'Friends here', 1, 0.82, 0)
	for index, person in ipairs(mark.people) do
		if index > FriendMap.LIST_MAX then
			GameTooltip:AddLine(string.format('and %d more', #mark.people - FriendMap.LIST_MAX), 0.7, 0.7, 0.7)
			break
		end
		local r, g, b = ClassColor(person.class)
		GameTooltip:AddDoubleLine(person.name .. (person.level and (' (' .. person.level .. ')') or ''), person.guild and 'Guild' or 'Friend', r, g, b, 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

local function AcquirePin(index, canvas)
	local pin = pins[index]
	if not pin then
		pin = CreateFrame('Frame', nil, canvas)
		pin.icon = pin:CreateTexture(nil, 'OVERLAY')
		pin.icon:SetAllPoints(pin)
		pin.count = pin:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		pin.count:SetPoint('CENTER', pin, 'BOTTOMRIGHT', -2, 3)
		pin:EnableMouse(true)
		pin:SetScript('OnLeave', function() GameTooltip:Hide() end)
		pins[index] = pin
	end
	pin:SetParent(canvas)
	pin:SetFrameLevel((canvas:GetFrameLevel() or 0) + 500)
	return pin
end

-- An atlas when the client has it, otherwise a plain texture (OpenMap's choice of looks).
local function SetLook(texture, atlas, file)
	local hasAtlas = atlas and texture.SetAtlas and type(C_Texture) == 'table' and C_Texture.GetAtlasInfo and SafeCall(C_Texture.GetAtlasInfo, atlas)
	if hasAtlas then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(file)
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

-- Pins keep the same size on screen at any zoom: sizes and offsets are in canvas units.
function FriendMap.Redraw()
	local worldMap, canvas = WorldCanvas()
	local used = 0
	if worldMap and canvas and worldMap:IsShown() and worldMap.GetMapID then
		local shownMap = worldMap:GetMapID()
		local width, height = canvas:GetWidth(), canvas:GetHeight()
		local scale = (canvas.GetScale and canvas:GetScale()) or 1
		if type(shownMap) == 'number' and width and width > 0 and scale > 0 then
			local dots, badges = FriendMap.BuildMarks(shownMap, GetTime())
			for _, badge in ipairs(badges) do
				used = used + 1
				local pin = AcquirePin(used, canvas)
				local size = FriendMap.BADGE_SIZE / scale
				pin:SetSize(size, size)
				SetLook(pin.icon, 'socialqueuing-icon-group', [[Interface\FriendsFrame\UI-Toast-FriendOnlineIcon]])
				pin.icon:SetVertexColor(1, 1, 1)
				pin.count:SetText(#badge.people > 1 and tostring(#badge.people) or '')
				pin.mark = badge
				pin:SetScript('OnEnter', ShowBadgeTooltip)
				pin:ClearAllPoints()
				pin:SetPoint('CENTER', canvas, 'TOPLEFT', badge.x * width, -badge.y * height)
				pin:Show()
			end
			for _, dot in ipairs(dots) do
				used = used + 1
				local pin = AcquirePin(used, canvas)
				local size = FriendMap.DOT_SIZE / scale
				pin:SetSize(size, size)
				SetLook(pin.icon, 'WhiteCircle-RaidBlips', [[Interface\COMMON\Indicator-Gray]])
				pin.icon:SetVertexColor(ClassColor(dot.class))
				pin.count:SetText('')
				pin.mark = dot
				pin:SetScript('OnEnter', ShowDotTooltip)
				pin:ClearAllPoints()
				pin:SetPoint('CENTER', canvas, 'TOPLEFT', dot.x * width, -dot.y * height)
				pin:Show()
			end
		end
	end
	for index = used + 1, #pins do
		pins[index]:Hide()
		pins[index].mark = nil
	end
	FriendMap.dirty = false
	FriendMap.drawnScale = canvas and canvas.GetScale and canvas:GetScale()
	return used
end

function FriendMap.AskRosters()
	if IsInGuild and IsInGuild() then
		if type(C_GuildInfo) == 'table' and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
	end
	if type(C_FriendList) == 'table' and C_FriendList.ShowFriends then
		pcall(C_FriendList.ShowFriends)
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

if type(CreateFrame) == 'function' then
	FriendMap.sender = CreateFrame('Frame')
	FriendMap.sender:Hide()
	local wait = 0
	FriendMap.sender:SetScript('OnUpdate', function(self, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = FriendMap.SEND_GAP
		if not FriendMap.SendNext() then
			self:Hide()
		end
	end)

	local events = CreateFrame('Frame')
	for _, event in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'FRIENDLIST_UPDATE', 'GUILD_ROSTER_UPDATE', 'BN_FRIEND_INFO_CHANGED', 'BN_FRIEND_ACCOUNT_ONLINE', 'BN_FRIEND_ACCOUNT_OFFLINE', 'CHAT_MSG_ADDON', 'BN_CHAT_MSG_ADDON' }) do
		pcall(events.RegisterEvent, events, event)
	end

	local scanQueued = false
	local function QueueScan()
		if scanQueued then return end
		scanQueued = true
		local worldMap = _G.WorldMapFrame
		local delay = (worldMap and worldMap:IsShown()) and 1 or 10
		C_Timer.After(delay, function()
			scanQueued = false
			pcall(FriendMap.Scan)
		end)
	end
	FriendMap.QueueScan = QueueScan

	events:SetScript('OnEvent', function(_, event, ...)
		if event == 'CHAT_MSG_ADDON' then
			local prefix, text, channel, from = ...
			FriendMap.OnAddonMessage(prefix, text, channel, from)
		elseif event == 'BN_CHAT_MSG_ADDON' then
			local prefix, text, _, gameAccountID = ...
			FriendMap.OnBattleNetMessage(prefix, text, gameAccountID)
		elseif event == 'PLAYER_LOGIN' then
			if type(C_ChatInfo) == 'table' and C_ChatInfo.RegisterAddonMessagePrefix then
				pcall(C_ChatInfo.RegisterAddonMessagePrefix, FriendMap.PREFIX)
			end
			FriendMap.AnnounceSharing()
			if C_Timer and C_Timer.NewTicker then
				C_Timer.NewTicker(FriendMap.TICK, FriendMap.Tick)
			end
			QueueScan()
		else
			QueueScan()
		end
	end)

	-- While the world map is open: rescan on opening, redraw when the zone or zoom changes and
	-- every couple of seconds, so new positions appear.
	local function HookWorldMap()
		local worldMap = _G.WorldMapFrame
		if not worldMap or FriendMap.hooked then
			return
		end
		FriendMap.hooked = true
		worldMap:HookScript('OnShow', function()
			FriendMap.AskRosters()
			pcall(FriendMap.Scan)
			FriendMap.Redraw()
		end)
		worldMap:HookScript('OnHide', function()
			for _, pin in ipairs(pins) do pin:Hide() end
		end)
		if type(worldMap.OnMapChanged) == 'function' then
			hooksecurefunc(worldMap, 'OnMapChanged', function() FriendMap.Redraw() end)
		end
		local elapsedSinceDraw = 0
		worldMap:HookScript('OnUpdate', function(_, elapsed)
			elapsedSinceDraw = elapsedSinceDraw + elapsed
			local _, canvas = WorldCanvas()
			local zoomed = canvas and canvas.GetScale and canvas:GetScale() ~= FriendMap.drawnScale
			if zoomed or FriendMap.dirty or elapsedSinceDraw > 2 then
				elapsedSinceDraw = 0
				FriendMap.Redraw()
			end
		end)
	end

	if _G.WorldMapFrame then
		HookWorldMap()
	else
		local loader = CreateFrame('Frame')
		loader:RegisterEvent('ADDON_LOADED')
		loader:SetScript('OnEvent', function(self)
			if _G.WorldMapFrame then
				HookWorldMap()
				self:UnregisterAllEvents()
			end
		end)
	end
end
