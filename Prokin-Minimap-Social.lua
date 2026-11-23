-- Friends and guild roster details for the Prokin minimap button tooltip.
-- Follows the useful behavior of ElvUI's Friends and Guild datatexts without requiring ElvUI.
local Social = {}
_G.ProkinMinimapSocial = Social

local MAX_TOOLTIP_MEMBERS = 18
local unpack = unpack or table.unpack

local function IsSecret(value)
	if type(issecretvalue) ~= 'function' then
		return false
	end
	local ok, secret = pcall(issecretvalue, value)
	return not ok or secret == true
end

local function Pack(...)
	return { n = select('#', ...), ... }
end

local function SafeCall(fn, ...)
	if type(fn) ~= 'function' then
		return nil
	end
	local values = Pack(pcall(fn, ...))
	if not values[1] then
		return nil
	end
	for index = 2, values.n do
		if IsSecret(values[index]) then
			return nil
		end
	end
	return unpack(values, 2, values.n)
end

local function Field(object, key)
	if type(object) ~= 'table' or IsSecret(object) then
		return nil
	end
	local ok, value = pcall(function()
		return object[key]
	end)
	if not ok or IsSecret(value) then
		return nil
	end
	return value
end

local function Display(value, fallback)
	if value == nil or IsSecret(value) then
		return fallback
	end
	local ok, result = pcall(tostring, value)
	if not ok or type(result) ~= 'string' or result == '' then
		return fallback
	end
	return result
end

local function Count(value)
	if type(value) == 'number' and not IsSecret(value) and value >= 0 then
		return math.floor(value)
	end
end

local function IsOnline(value)
	return not IsSecret(value) and value == true
end

local function ResolveClassColorCode(className)
	className = Display(className, nil)
	if not className then
		return nil
	end

	local classColors = RAID_CLASS_COLORS
	if type(classColors) ~= 'table' then
		return nil
	end

	local token = className:upper():gsub('[^A-Z]', '')
	if not classColors[token] then
		local function FindLocalizedClassToken(localizedNames)
			if type(localizedNames) ~= 'table' then
				return nil
			end
			for classToken, localizedName in pairs(localizedNames) do
				if localizedName == className then
					return classToken
				end
			end
		end
		token = FindLocalizedClassToken(LOCALIZED_CLASS_NAMES_MALE)
			or FindLocalizedClassToken(LOCALIZED_CLASS_NAMES_FEMALE)
			or token
	end

	local color = classColors[token]
	if type(color) ~= 'table' then
		return nil
	end

	local colorCode = Display(color.colorStr, nil)
	if colorCode then
		colorCode = colorCode:gsub('^|c', '')
		if #colorCode == 6 then
			colorCode = 'ff' .. colorCode
		end
		if colorCode:match('^%x%x%x%x%x%x%x%x$') then
			return colorCode
		end
	end

	local red, green, blue = tonumber(color.r), tonumber(color.g), tonumber(color.b)
	if red and green and blue then
		return string.format('ff%02x%02x%02x', math.floor(red * 255 + 0.5), math.floor(green * 255 + 0.5), math.floor(blue * 255 + 0.5))
	end
end

local function AddMemberRows(tooltip, rows)
	local visible = math.min(#rows, MAX_TOOLTIP_MEMBERS)
	for index = 1, visible do
		local row = rows[index]
		local status = row.status and (' [' .. row.status .. ']') or ''
		local detail = row.detail and ('  ' .. row.detail) or ''
		local zone = row.zone or 'Location unavailable'
		local name = row.classColor and ('|c' .. row.classColor .. row.name .. '|r') or row.name
		local zoneR, zoneG, zoneB = 0.72, 0.72, 0.72
		if row.zone and row.zone == Social.currentZone then
			zoneR, zoneG, zoneB = 0.35, 1, 0.35
		end
		tooltip:AddDoubleLine(name .. status .. detail, zone, 0.9, 0.9, 0.9, zoneR, zoneG, zoneB)
	end
	if #rows > visible then
		tooltip:AddLine(string.format('... and %d more', #rows - visible), 0.7, 0.7, 0.7)
	end
end

local function AddFriends(tooltip, leadingSpace)
	local friendList = type(C_FriendList) == 'table' and C_FriendList or nil
	local getCount = friendList and friendList.GetNumFriends or GetNumFriends
	local getInfo = friendList and friendList.GetFriendInfoByIndex
	local totalFriends = Count(SafeCall(getCount)) or 0
	local rows = {}

	for index = 1, totalFriends do
		if getInfo then
			local info = SafeCall(getInfo, index)
			if info then
				local connected = Field(info, 'connected')
				if IsOnline(connected) then
					local name = Display(Field(info, 'name'), nil)
					if name then
						local afk, dnd = IsOnline(Field(info, 'afk')), IsOnline(Field(info, 'dnd'))
						local level = Field(info, 'level')
						local className = Field(info, 'className')
						local classFileName = Field(info, 'classFileName')
						local classLabel = className or classFileName
						local detail = level and ('Lv ' .. Display(level, '?')) or ''
						if classLabel then
							detail = detail .. ' ' .. Display(classLabel, '')
						end
						rows[#rows + 1] = {
							name = name,
							classColor = ResolveClassColorCode(classFileName or className),
							zone = Display(Field(info, 'area'), Display(Field(info, 'zone'), nil)),
							detail = detail ~= '' and detail or nil,
							status = afk and 'AFK' or (dnd and 'DND' or nil),
						}
					end
				end
			end
		elseif type(GetFriendInfo) == 'function' then
			local name, level, className, area, connected, status = SafeCall(GetFriendInfo, index)
			if IsOnline(connected) and name then
				local displayClass = Display(className, nil)
				rows[#rows + 1] = {
					name = Display(name, 'Unknown'),
					classColor = ResolveClassColorCode(displayClass),
					zone = Display(area, nil),
					detail = (level and ('Lv ' .. Display(level, '?')) or '') .. (displayClass and (' ' .. displayClass) or ''),
					status = type(status) == 'string' and status ~= '' and status or nil,
				}
			end
		end
	end

	local onlineBattleNet = 0
	local totalBattleNet, countFromLegacy = SafeCall(BNGetNumFriends)
	totalBattleNet = Count(totalBattleNet) or 0
	local battleNet = type(C_BattleNet) == 'table' and C_BattleNet or nil
	local getAccount = battleNet and battleNet.GetFriendAccountInfo
	local getGameCount = battleNet and battleNet.GetFriendNumGameAccounts
	local getGameInfo = battleNet and battleNet.GetFriendGameAccountInfo
	if getAccount and getGameInfo then
		for index = 1, totalBattleNet do
			local account = SafeCall(getAccount, index)
			local gameCount = Count(SafeCall(getGameCount, index)) or 0
			local added = false
			for gameIndex = 1, gameCount do
				local info = SafeCall(getGameInfo, index, gameIndex)
				if info and IsOnline(Field(info, 'isOnline')) then
					local character = Display(Field(info, 'characterName'), nil)
					local client = Display(Field(info, 'clientProgram'), nil)
					local name = character or Display(Field(account, 'accountName'), 'Battle.net friend')
					local zone = Display(Field(info, 'areaName'), nil)
					if not zone and client and client ~= 'WoW' then
						zone = client
					end
					local level = Field(info, 'characterLevel')
					local class = Field(info, 'className')
					local classFileName = Field(info, 'classFileName')
					local classLabel = class or classFileName
					rows[#rows + 1] = {
						name = name,
						classColor = ResolveClassColorCode(classFileName or class),
						zone = zone,
						detail = (level and ('Lv ' .. Display(level, '?')) or '') .. (classLabel and (' ' .. Display(classLabel, '')) or ''),
						status = IsOnline(Field(info, 'isGameAFK')) and 'AFK' or (IsOnline(Field(account, 'isAFK')) and 'AFK' or nil),
					}
					onlineBattleNet = onlineBattleNet + 1
					added = true
				end
			end
			if not added and account and IsOnline(Field(account, 'isOnline')) then
				rows[#rows + 1] = {
					name = Display(Field(account, 'accountName'), 'Battle.net friend'),
					zone = 'Online on Battle.net',
				}
				onlineBattleNet = onlineBattleNet + 1
			end
		end
	else
		onlineBattleNet = Count(countFromLegacy) or 0
	end

	table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
	if leadingSpace then
		tooltip:AddLine(' ')
	end
	tooltip:AddDoubleLine('Friends', string.format('%d online / %d', #rows, totalFriends + totalBattleNet), 1, 0.82, 0, 1, 0.82, 0)
	if #rows == 0 then
		tooltip:AddLine('No friends online.', 0.7, 0.7, 0.7)
	else
		tooltip:AddLine(' ')
		AddMemberRows(tooltip, rows)
	end
end

local function GetGuildRows()
	if type(IsInGuild) ~= 'function' or not IsInGuild() then
		return nil, 0, 0, 'Not in a guild.'
	end

	local total, online = SafeCall(GetNumGuildMembers)
	total, online = Count(total), Count(online)
	local rows = {}
	local totalMembers = total or 0
	if type(GetGuildRosterInfo) == 'function' then
		for index = 1, totalMembers do
			local name, rank, _, level, classDisplayName, zone, _, _, connected, status, classFileName = SafeCall(GetGuildRosterInfo, index)
			if name and IsOnline(connected) then
				local classLabel = Display(classDisplayName, nil) or Display(classFileName, nil)
				local afk = status == 1 or status == 'AFK'
				local dnd = status == 2 or status == 'DND'
				rows[#rows + 1] = {
					name = Display(name, 'Unknown'),
					classColor = ResolveClassColorCode(classFileName or classDisplayName),
					zone = Display(zone, nil),
					detail = (level and ('Lv ' .. Display(level, '?')) or '')
						.. (classLabel and (' ' .. classLabel) or '')
						.. (rank and (' — ' .. Display(rank, '')) or ''),
					status = afk and 'AFK' or (dnd and 'DND' or nil),
				}
			end
		end
	end

	local guildName = SafeCall(GetGuildInfo, 'player')
	return rows, online or #rows, totalMembers, Display(guildName, 'Guild')
end

local lastRosterRequest = -math.huge
local function RequestGuildRoster()
	if type(IsInGuild) ~= 'function' or not IsInGuild() then
		return
	end
	if type(InCombatLockdown) == 'function' and InCombatLockdown() then
		return
	end
	local now = SafeCall(GetTime) or 0
	if now - lastRosterRequest < 60 then
		return
	end
	lastRosterRequest = now
	local guildInfo = type(C_GuildInfo) == 'table' and C_GuildInfo or nil
	if guildInfo and type(guildInfo.GuildRoster) == 'function' then
		SafeCall(guildInfo.GuildRoster)
	elseif type(GuildRoster) == 'function' then
		SafeCall(GuildRoster)
	end
end

local function AddGuild(tooltip, leadingSpace)
	if not tooltip then
		return
	end
	RequestGuildRoster()

	local rows, online, total, guildName = GetGuildRows()
	if leadingSpace then
		tooltip:AddLine(' ')
	end
	if not rows then
		tooltip:AddDoubleLine('Guild', '—', 1, 0.82, 0, 1, 0.82, 0)
		tooltip:AddLine(guildName, 0.7, 0.7, 0.7)
		return
	end
	tooltip:AddDoubleLine(guildName, string.format('%d online / %d', online, total), 1, 0.82, 0, 1, 0.82, 0)
	if #rows == 0 then
		tooltip:AddLine(total == 0 and 'Roster loading...' or 'No guild members online.', 0.7, 0.7, 0.7)
	else
		tooltip:AddLine(' ')
		table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
		AddMemberRows(tooltip, rows)
	end
end

function Social.AddFriendsTooltipLines(tooltip, leadingSpace)
	if not tooltip then
		return
	end
	local currentZone = SafeCall(GetRealZoneText) or SafeCall(GetZoneText)
	Social.currentZone = Display(currentZone, nil)
	AddFriends(tooltip, leadingSpace)
end

function Social.AddGuildTooltipLines(tooltip, leadingSpace)
	local currentZone = SafeCall(GetRealZoneText) or SafeCall(GetZoneText)
	Social.currentZone = Display(currentZone, nil)
	AddGuild(tooltip, leadingSpace)
end

function Social.AddTooltipLines(tooltip)
	if not tooltip then
		return
	end
	Social.AddFriendsTooltipLines(tooltip, true)
	Social.AddGuildTooltipLines(tooltip, true)
end

local function CreateSocialButton(name, letter, red, green, blue, tooltipLines)
	if type(CreateFrame) ~= 'function' or not _G.UIParent then
		return nil
	end
	local button = CreateFrame('Button', name, _G.UIParent)
	button:SetSize(31, 31)
	button:SetFrameStrata('MEDIUM')
	button:SetFrameLevel(Minimap and Minimap:GetFrameLevel() + 30 or 30)
	button.background = button:CreateTexture(nil, 'BACKGROUND')
	button.background:SetTexture([[Interface\Minimap\UI-Minimap-Background]])
	button.background:SetSize(24, 24)
	button.background:SetPoint('CENTER')
	button.icon = button:CreateTexture(nil, 'ARTWORK')
	if name == 'ProkinMinimapGuildButton' then
		button.icon:SetTexture([[Interface\AddOns\Prokin-Minimap\Media\ProkinGuildButton]])
		button.icon:SetSize(24, 24)
	else
		button.icon:SetColorTexture(red, green, blue, 1)
		button.icon:SetSize(18, 18)
	end
	button.icon:SetPoint('CENTER')
	button.border = button:CreateTexture(nil, 'BORDER')
	button.border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
	button.border:SetSize(50, 50)
	button.border:SetPoint('TOPLEFT')
	button.label = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	button.label:SetPoint('CENTER', button, 'CENTER', 0, 0)
	button.label:SetText(letter)
	button.label:SetTextColor(1, 1, 1)
	if name == 'ProkinMinimapGuildButton' then
		button.label:Hide()
	end
	button:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]], 'ADD')
	local highlight = button:GetHighlightTexture()
	if highlight then
		highlight:SetAllPoints(button)
	end
	button:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		tooltipLines(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript('OnLeave', GameTooltip_Hide)
	return button
end

Social.Buttons = {
	Friends = CreateSocialButton('ProkinMinimapFriendsButton', 'F', 0.18, 0.48, 0.95, Social.AddFriendsTooltipLines),
	Guild = CreateSocialButton('ProkinMinimapGuildButton', 'G', 0.82, 0.58, 0.12, Social.AddGuildTooltipLines),
}

if type(CreateFrame) == 'function' then
	local events = CreateFrame('Frame')
	for _, event in ipairs({
		'PLAYER_ENTERING_WORLD', 'PLAYER_GUILD_UPDATE', 'GUILD_ROSTER_UPDATE',
		'FRIENDLIST_UPDATE', 'FRIENDS_LIST_UPDATE', 'BN_FRIEND_ACCOUNT_ONLINE',
		'BN_FRIEND_ACCOUNT_OFFLINE', 'BN_FRIEND_INFO_CHANGED'
	}) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript('OnEvent', function(_, event)
		if event == 'PLAYER_ENTERING_WORLD' or event == 'PLAYER_GUILD_UPDATE' then
			RequestGuildRoster()
		end
	end)
end
