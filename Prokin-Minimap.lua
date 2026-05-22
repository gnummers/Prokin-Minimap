local ADDON_NAME = ...
local HYBRID_MINIMAP_ADDON = 'Blizzard_HybridMinimap'
local AUTOMARKASSIST_ADDON = 'AutoMarkAssist'
local MINIMAPBUTTONBUTTON_ADDON = 'MinimapButtonButton'
local TIME_MANAGER_ADDON = 'Blizzard_TimeManager'
local DEFAULT_SIZE = 400
local MIN_SIZE = 100
local MAX_SIZE = 800
local DEFAULT_STEP = 25
local ZONE_HEADER_SPACING = 4
local BORDER_SIZE = 1
local WIDGET_EDGE_PADDING = 0
local WIDGET_BORDER_OVERLAP = 12
local CLOCK_BOTTOM_OFFSET = -5
local ADDON_BUTTON_DEFAULT_ANGLE = 180
local PROXY_BUTTON_SIZE = 33
local PROXY_BACKGROUND_SIZE = 30
local PROXY_ICON_SIZE = 24
local PROXY_BORDER_SIZE = 64
local PROXY_ICON_OFFSET_X = 2
local PROXY_ICON_OFFSET_Y = -2
local ADDON_MINIMAP_BUTTON_SIZE = 31
local ADDON_MINIMAP_BACKGROUND_SIZE = 27
local ADDON_MINIMAP_ICON_SIZE = 20
local ADDON_MINIMAP_BORDER_SIZE = 53
local ADDON_MINIMAP_ICON_OFFSET_X = 0
local ADDON_MINIMAP_ICON_OFFSET_Y = 0
local ADDON_MINIMAP_EDGE_OFFSET = 7
local ADDON_MINIMAP_ANCHOR_OFFSET_X = 3
local ADDON_MINIMAP_ANCHOR_OFFSET_Y = 0
local ADDON_BUTTON_NAME = 'ProkinMinimapButton'
local SQUARE_MASK = [[Interface\ChatFrame\ChatFrameBackground]]
local HIDDEN_TEXTURES = {
	'MinimapBorder',
	'MinimapBorderTop',
	'MiniMapTrackingBorder'
}
local WIDGET_DEFAULT_POSITIONS = {
	tracking = { edge = 'top', coord = -0.8 },
	lfg = { edge = 'top', coord = 0.8 },
	clock = { edge = 'bottom', coord = 0 },
	mail = { edge = 'bottom', coord = -0.8 },
	battlefield = { edge = 'bottom', coord = 0.8 }
}
local hooksInstalled
local adjustingZoneLayout
local minimapBorder
local zoneHeaderFrame
local zoneHeaderText
local hiddenZoneHeaderParent
local eventFrame
local loadAnnouncementPending
local loadAnnouncementShown
local loadAnnouncementDelay = 0
local zoneTimeElapsed = 0
local mailVisibilityElapsed = 0
local lastZoneTimeSuffix
local autoMarkAssistHookInstalled
local timeManagerLoadAttempted
local adjustingWidgetLayout
local minimapRefreshPending
local addonMinimapButton
local addonButtonDragging
local optionsFrame
local trackingProxyButton
local lfgProxyButton
local battlefieldProxyButton
local activeWidgetDrag
local pendingTrackingMenuAnchor
local GetDatabase
local RefreshMinimap
local SetMinimapSize
local OpenOptionsWindow
local ApplyBlizzardWidgetLayout
local widgetMethods = setmetatable({}, { __mode = 'k' })
local WIDGET_BLACKLIST_NAMES = {
	'MiniMapTracking',
	'MiniMapTrackingFrame',
	'MiniMapTrackingButton',
	'MinimapToggleButton',
	'QueueStatusMinimapButton',
	'GameTimeFrame',
	'TimeManagerClockButton',
	'MiniMapMailFrame',
	'MiniMapBattlefieldFrame',
	'QueueStatusButton',
	'MiniMapLFGFrame',
	'LFGMinimapFrame',
	ADDON_BUTTON_NAME,
	'ProkinMinimapTrackingProxy',
	'ProkinMinimapLFGProxy',
	'ProkinMinimapBattlefieldProxy'
}

local function Noop() end

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(string.format('|cff33ff99%s|r: %s', ADDON_NAME, message))
end

local function ShouldShowLoadAnnouncement()
	return GetDatabase().showLoadAnnouncement ~= false
end

local function GetAddonVersion()
	if type(C_AddOns) == 'table' and type(C_AddOns.GetAddOnMetadata) == 'function' then
		return C_AddOns.GetAddOnMetadata(ADDON_NAME, 'Version') or 'unknown'
	end

	if type(GetAddOnMetadata) == 'function' then
		return GetAddOnMetadata(ADDON_NAME, 'Version') or 'unknown'
	end

	return 'unknown'
end

local function TryShowLoadAnnouncement()
	if loadAnnouncementShown or not loadAnnouncementPending or not DEFAULT_CHAT_FRAME then
		return
	end

	if not ShouldShowLoadAnnouncement() then
		loadAnnouncementPending = nil
		return
	end

	if loadAnnouncementDelay > 0 then
		return
	end

	if DEFAULT_CHAT_FRAME.IsShown and not DEFAULT_CHAT_FRAME:IsShown() then
		return
	end

	loadAnnouncementPending = nil
	loadAnnouncementShown = true
	DEFAULT_CHAT_FRAME:AddMessage(string.format(
		'|cffffff00Prokin Minimap v%s by |r|cff33ff99<I Pull Mob>|r|cffffff00 loaded. Please use /pkm for help.|r',
		GetAddonVersion()
	))
end

local function IsTrackingDebugEnabled()
	return GetDatabase().debugTracking == true
end

local function PrintTrackingDebug(message)
	if not IsTrackingDebugEnabled() then
		return
	end

	Print(string.format('[tracking-debug] %s', message))
end

local function GetFrameDebugName(frame)
	if not frame then
		return 'nil'
	end

	if frame.GetName then
		local name = frame:GetName()
		if name and name ~= '' then
			return name
		end
	end

	return tostring(frame)
end

local function HasFrameScript(frame, scriptName)
	if not frame or not frame.HasScript or not frame.GetScript then
		return false
	end

	return frame:HasScript(scriptName) and frame:GetScript(scriptName) ~= nil
end

local function DescribeFrame(frame)
	if not frame then
		return 'nil'
	end

	local parentName = 'nil'
	local parent = frame.GetParent and frame:GetParent()
	if parent then
		parentName = GetFrameDebugName(parent)
	end

	local shown = frame.IsShown and frame:IsShown() and 'true' or 'false'
	local mouseEnabled = frame.IsMouseEnabled and frame:IsMouseEnabled() and 'true' or 'false'

	return string.format(
		'%s shown=%s mouse=%s openMenu=%s onMouseUp=%s onClick=%s parent=%s',
		GetFrameDebugName(frame),
		shown,
		mouseEnabled,
		frame.OpenMenu and 'true' or 'false',
		HasFrameScript(frame, 'OnMouseUp') and 'true' or 'false',
		HasFrameScript(frame, 'OnClick') and 'true' or 'false',
		parentName
	)
end

local function HideTexture(name)
	local texture = _G[name]
	if texture then
		texture:Hide()
	end
end

local function HideTextureObject(texture)
	if texture then
		texture:SetTexture(nil)
		texture:Hide()
	end
end

local function NormalizeSize(size)
	size = tonumber(size)
	if not size then
		return nil
	end

	size = math.floor(size + 0.5)

	if size < MIN_SIZE then
		size = MIN_SIZE
	elseif size > MAX_SIZE then
		size = MAX_SIZE
	end

	return size
end

local function NormalizeStep(step)
	step = tonumber(step)
	if not step then
		return DEFAULT_STEP
	end

	step = math.floor(math.abs(step) + 0.5)
	return math.max(step, 1)
end

local function NormalizeAngle(angle)
	angle = tonumber(angle) or ADDON_BUTTON_DEFAULT_ANGLE
	angle = angle % 360
	if angle < 0 then
		angle = angle + 360
	end

	return angle
end

GetDatabase = function()
	if type(ProkinMinimapDB) ~= 'table' then
		ProkinMinimapDB = {}
	end

	ProkinMinimapDB.size = NormalizeSize(ProkinMinimapDB.size) or DEFAULT_SIZE
	if type(ProkinMinimapDB.widgetPositions) ~= 'table' then
		ProkinMinimapDB.widgetPositions = {}
	end
	if type(ProkinMinimapDB.debugTrackingConfigured) ~= 'boolean' then
		ProkinMinimapDB.debugTracking = false
		ProkinMinimapDB.debugTrackingConfigured = false
	end
	if type(ProkinMinimapDB.minimapButtonAngle) ~= 'number' then
		ProkinMinimapDB.minimapButtonAngle = ADDON_BUTTON_DEFAULT_ANGLE
	end
	ProkinMinimapDB.minimapButtonAngle = NormalizeAngle(ProkinMinimapDB.minimapButtonAngle)
	if type(ProkinMinimapDB.showAddonButton) ~= 'boolean' then
		ProkinMinimapDB.showAddonButton = true
	end
	if type(ProkinMinimapDB.showLoadAnnouncement) ~= 'boolean' then
		ProkinMinimapDB.showLoadAnnouncement = true
	end
	if type(ProkinMinimapDB.showServerTime) ~= 'boolean' then
		ProkinMinimapDB.showServerTime = true
	end
	if type(ProkinMinimapDB.showMinimapBorder) ~= 'boolean' then
		ProkinMinimapDB.showMinimapBorder = true
	end
	return ProkinMinimapDB
end

local function ApplySquareMinimap()
	if not Minimap then
		return
	end

	local db = GetDatabase()

	Minimap:SetMaskTexture(SQUARE_MASK)
	Minimap:SetSize(db.size, db.size)

	for _, textureName in ipairs(HIDDEN_TEXTURES) do
		HideTexture(textureName)
	end

	if _G.MinimapBackdrop then
		_G.MinimapBackdrop:Hide()
	end
end

local function EnsureMinimapBorder()
	if minimapBorder or not Minimap then
		return
	end

	minimapBorder = CreateFrame('Frame', nil, Minimap)
	minimapBorder:SetAllPoints(Minimap)
	minimapBorder:SetFrameLevel(Minimap:GetFrameLevel() + 10)

	minimapBorder.top = minimapBorder:CreateTexture(nil, 'OVERLAY')
	minimapBorder.top:SetColorTexture(0, 0, 0, 1)
	minimapBorder.top:SetPoint('TOPLEFT', Minimap, 'TOPLEFT', -BORDER_SIZE, BORDER_SIZE)
	minimapBorder.top:SetPoint('TOPRIGHT', Minimap, 'TOPRIGHT', BORDER_SIZE, BORDER_SIZE)
	minimapBorder.top:SetHeight(BORDER_SIZE)

	minimapBorder.bottom = minimapBorder:CreateTexture(nil, 'OVERLAY')
	minimapBorder.bottom:SetColorTexture(0, 0, 0, 1)
	minimapBorder.bottom:SetPoint('BOTTOMLEFT', Minimap, 'BOTTOMLEFT', -BORDER_SIZE, -BORDER_SIZE)
	minimapBorder.bottom:SetPoint('BOTTOMRIGHT', Minimap, 'BOTTOMRIGHT', BORDER_SIZE, -BORDER_SIZE)
	minimapBorder.bottom:SetHeight(BORDER_SIZE)

	minimapBorder.left = minimapBorder:CreateTexture(nil, 'OVERLAY')
	minimapBorder.left:SetColorTexture(0, 0, 0, 1)
	minimapBorder.left:SetPoint('TOPLEFT', Minimap, 'TOPLEFT', -BORDER_SIZE, BORDER_SIZE)
	minimapBorder.left:SetPoint('BOTTOMLEFT', Minimap, 'BOTTOMLEFT', -BORDER_SIZE, -BORDER_SIZE)
	minimapBorder.left:SetWidth(BORDER_SIZE)

	minimapBorder.right = minimapBorder:CreateTexture(nil, 'OVERLAY')
	minimapBorder.right:SetColorTexture(0, 0, 0, 1)
	minimapBorder.right:SetPoint('TOPRIGHT', Minimap, 'TOPRIGHT', BORDER_SIZE, BORDER_SIZE)
	minimapBorder.right:SetPoint('BOTTOMRIGHT', Minimap, 'BOTTOMRIGHT', BORDER_SIZE, -BORDER_SIZE)
	minimapBorder.right:SetWidth(BORDER_SIZE)
end

local function ApplyMinimapBorderVisibility()
	if not minimapBorder then
		return
	end

	minimapBorder:SetShown(GetDatabase().showMinimapBorder ~= false)
end

local function EnsureCustomZoneHeader()
	if zoneHeaderFrame or not Minimap then
		return
	end

	zoneHeaderFrame = CreateFrame('Frame', nil, Minimap)
	zoneHeaderFrame:SetFrameStrata('MEDIUM')
	zoneHeaderFrame:SetFrameLevel(Minimap:GetFrameLevel() + 20)

	zoneHeaderText = zoneHeaderFrame:CreateFontString(nil, 'OVERLAY')
	zoneHeaderText:SetPoint('CENTER', zoneHeaderFrame, 'CENTER', 0, 0)
	zoneHeaderText:SetJustifyH('CENTER')
	zoneHeaderText:SetJustifyV('MIDDLE')

	local defaultText = _G.MinimapZoneText
	if defaultText and defaultText.GetFont then
		local font, size, flags = defaultText:GetFont()
		if font then
			zoneHeaderText:SetFont(font, size, flags)
		end
	end

	if not zoneHeaderText:GetFont() then
		zoneHeaderText:SetFontObject(GameFontNormalSmall)
	end
end

local function EnsureHiddenZoneHeaderParent()
	if hiddenZoneHeaderParent then
		return
	end

	hiddenZoneHeaderParent = CreateFrame('Frame')
	hiddenZoneHeaderParent:Hide()
end

local function GetServerTimeSuffix()
	local hour, minute = GetGameTime()
	if type(hour) ~= 'number' or type(minute) ~= 'number' then
		return ''
	end

	local meridiem = hour >= 12 and 'PM' or 'AM'
	hour = hour % 12

	if hour == 0 then
		hour = 12
	end

	return string.format('[%02d:%02d %s]', hour, minute, meridiem)
end

local function GetZoneHeaderText()
	local zoneText = GetMinimapZoneText and GetMinimapZoneText() or ''
	if zoneText == '' then
		return ''
	end

	local timeSuffix = GetDatabase().showServerTime ~= false and GetServerTimeSuffix() or ''
	if timeSuffix ~= '' then
		return string.format('%s %s', zoneText, timeSuffix)
	end

	return zoneText
end

local function UpdateZoneHeaderText()
	EnsureCustomZoneHeader()
	if not zoneHeaderFrame or not zoneHeaderText then
		return
	end

	local text = GetZoneHeaderText()
	zoneHeaderText:SetText(text)
	lastZoneTimeSuffix = GetServerTimeSuffix()

	local textHeight = math.ceil(zoneHeaderText:GetStringHeight() or 0)
	if textHeight < 1 then
		textHeight = 12
	end

	zoneHeaderFrame:SetHeight(textHeight)
	zoneHeaderFrame:SetShown(text ~= '')
end

local function ApplyZoneLayout()
	local cluster = _G.MinimapCluster
	if not Minimap or not cluster or adjustingZoneLayout then
		return
	end

	adjustingZoneLayout = true
	UpdateZoneHeaderText()

	local headerHeight = zoneHeaderFrame and zoneHeaderFrame:IsShown() and zoneHeaderFrame:GetHeight() or 0
	Minimap:ClearAllPoints()
	Minimap:SetPoint('TOPRIGHT', cluster, 'TOPRIGHT', 0, -(headerHeight + ZONE_HEADER_SPACING))

	if zoneHeaderFrame then
		zoneHeaderFrame:ClearAllPoints()
		zoneHeaderFrame:SetPoint('BOTTOMLEFT', Minimap, 'TOPLEFT', 0, ZONE_HEADER_SPACING)
		zoneHeaderFrame:SetPoint('BOTTOMRIGHT', Minimap, 'TOPRIGHT', 0, ZONE_HEADER_SPACING)
	end

	adjustingZoneLayout = false
end

local function HideFrameChrome(frame)
	if not frame then
		return
	end

	if frame.GetNormalTexture then
		local texture = frame:GetNormalTexture()
		if texture then
			texture:SetTexture(nil)
			texture:Hide()
		end
	end

	if frame.GetPushedTexture then
		local texture = frame:GetPushedTexture()
		if texture then
			texture:SetTexture(nil)
			texture:Hide()
		end
	end

	if frame.GetHighlightTexture then
		local texture = frame:GetHighlightTexture()
		if texture then
			texture:SetTexture(nil)
			texture:Hide()
		end
	end

	if frame.GetDisabledTexture then
		local texture = frame:GetDisabledTexture()
		if texture then
			texture:SetTexture(nil)
			texture:Hide()
		end
	end

	if frame.GetRegions then
		for _, region in ipairs({ frame:GetRegions() }) do
			if region and region.GetObjectType and region:GetObjectType() == 'Texture' then
				region:SetTexture(nil)
				region:Hide()
			end
		end
	end

	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			if child and child.Hide then
				child:Hide()
			end
		end
	end

	if frame.EnableMouse then
		frame:EnableMouse(false)
	end
end

local function SuppressFrame(frame, clearText)
	if not frame then
		return
	end

	if frame.__ProkinSuppressed then
		if clearText and frame.SetText then
			frame:SetText('')
		end

		return
	end

	frame.__ProkinSuppressed = true
	HideFrameChrome(frame)

	if frame.UnregisterAllEvents then
		frame:UnregisterAllEvents()
	end

	if frame.ClearAllPoints then
		frame:ClearAllPoints()
	end

	if frame.SetParent then
		frame:SetParent(hiddenZoneHeaderParent)
	end

	if frame.SetAlpha then
		frame:SetAlpha(0)
	end

	if clearText and frame.SetText then
		frame:SetText('')
		frame.SetText = Noop
	end

	if frame.SetScript and frame.Hide then
		frame:SetScript('OnShow', frame.Hide)
	end

	if frame.Hide then
		frame:Hide()
	end

	if frame.Show then
		frame.Show = Noop
	end

	if frame.SetShown then
		frame.SetShown = Noop
	end
end

local function HideDefaultZoneHeader()
	EnsureHiddenZoneHeaderParent()

	local cluster = _G.MinimapCluster

	if cluster then
		SuppressFrame(cluster.ZoneTextButton)
		SuppressFrame(cluster.BorderTop)
	end

	SuppressFrame(_G.MiniMapWorldMapButton)
	SuppressFrame(_G.MiniMapWorldMapButtonCloseButton)
	SuppressFrame(_G.MinimapZoneTextButton)
	SuppressFrame(_G.MinimapZoneText, true)
end

local function HandleMinimapMouseWheel(_, delta)
	local zoomIn = Minimap and (Minimap.ZoomIn or _G.MinimapZoomIn)
	local zoomOut = Minimap and (Minimap.ZoomOut or _G.MinimapZoomOut)

	if delta > 0 then
		if zoomIn then
			zoomIn:Click()
		end
	elseif delta < 0 then
		if zoomOut then
			zoomOut:Click()
		end
	end
end

local function ApplyHybridMinimap()
	local hybridMinimap = _G.HybridMinimap
	if not hybridMinimap then
		return
	end

	local mapCanvas = hybridMinimap.MapCanvas
	if mapCanvas then
		if mapCanvas.EnableMouseWheel then
			mapCanvas:EnableMouseWheel(true)
		end

		if mapCanvas.SetMaskTexture then
			mapCanvas:SetMaskTexture()
		end

		if mapCanvas.SetScript then
			mapCanvas:SetScript('OnMouseWheel', HandleMinimapMouseWheel)
		end
	end

	local circleMask = hybridMinimap.CircleMask
	if circleMask then
		if circleMask.SetTexture then
			circleMask:SetTexture(nil)
		end

		circleMask:Hide()
	end
end

local function GetSquareMinimapShape()
	return 'SQUARE'
end

local function GetTrackingFrame()
	local cluster = _G.MinimapCluster
	if cluster then
		if cluster.Tracking and cluster.Tracking.Button then
			return cluster.Tracking.Button
		end

		return cluster.Tracking or cluster.TrackingFrame
	end

	return _G.MiniMapTrackingButton or _G.MinimapToggleButton or _G.MiniMapTrackingFrame or _G.MiniMapTracking
end

local function GetTrackingButton()
	local cluster = _G.MinimapCluster
	local candidates = {}
	local seen = {}

	local function AddCandidate(frame)
		if frame and not seen[frame] then
			seen[frame] = true
			table.insert(candidates, frame)
		end
	end

	if cluster then
		if cluster.Tracking and cluster.Tracking.Button then
			AddCandidate(cluster.Tracking.Button)
		end

		AddCandidate(cluster.Tracking)
		AddCandidate(cluster.TrackingFrame)
	end

	AddCandidate(_G.MiniMapTracking)
	AddCandidate(_G.MiniMapTrackingButton)
	AddCandidate(_G.MinimapToggleButton)
	AddCandidate(_G.MiniMapTrackingFrame)

	if IsTrackingDebugEnabled() then
		for index, frame in ipairs(candidates) do
			PrintTrackingDebug(string.format('candidate[%d]: %s', index, DescribeFrame(frame)))
		end
	end

	for _, frame in ipairs(candidates) do
		if frame.OpenMenu then
			PrintTrackingDebug(string.format('selected tracking frame via OpenMenu: %s', DescribeFrame(frame)))
			return frame
		end

		if frame.HasScript then
			if frame:HasScript('OnMouseUp') and frame:GetScript('OnMouseUp') then
				PrintTrackingDebug(string.format('selected tracking frame via OnMouseUp: %s', DescribeFrame(frame)))
				return frame
			end

			if frame:HasScript('OnClick') and frame:GetScript('OnClick') then
				PrintTrackingDebug(string.format('selected tracking frame via OnClick: %s', DescribeFrame(frame)))
				return frame
			end
		end
	end

	if candidates[1] then
		PrintTrackingDebug(string.format('falling back to first tracking candidate: %s', DescribeFrame(candidates[1])))
	else
		PrintTrackingDebug('no tracking candidates were found')
	end

	return candidates[1]
end

local function EnsureDigitalClockMode()
	local sundialClock = _G.GameTimeFrame
	if sundialClock then
		if sundialClock.Hide then
			sundialClock:Hide()
		end

		if not sundialClock.__ProkinHideHooked and sundialClock.HookScript then
			sundialClock:HookScript('OnShow', function(self)
				self:Hide()
			end)
			sundialClock.__ProkinHideHooked = true
		end
	end

	if _G.TimeManagerClockButton or timeManagerLoadAttempted then
		return
	end

	if type(LoadAddOn) ~= 'function' then
		return
	end

	timeManagerLoadAttempted = true
	if type(IsAddOnLoaded) ~= 'function' or not IsAddOnLoaded(TIME_MANAGER_ADDON) then
		LoadAddOn(TIME_MANAGER_ADDON)
	end
end

local function GetClockFrame()
	EnsureDigitalClockMode()
	return _G.TimeManagerClockButton
end

local function GetMailFrame()
	local cluster = _G.MinimapCluster
	local indicator = cluster and cluster.IndicatorFrame
	return (indicator and indicator.MailFrame) or _G.MiniMapMailFrame
end

local function RefreshMailVisibility()
	local mail = GetMailFrame()
	if not mail then
		return
	end

	if HasNewMail and HasNewMail() then
		if mail.SetAlpha then
			mail:SetAlpha(1)
		end

		if mail.Show and not mail:IsShown() then
			mail:Show()
		end
	elseif mail.Hide and mail:IsShown() then
		mail:Hide()
	end
end

local function GetLFGFrame()
	return _G.QueueStatusMinimapButton or _G.QueueStatusButton or _G.MiniMapLFGFrame or _G.LFGMinimapFrame
end

local function GetBattlefieldFrame()
	return _G.MiniMapBattlefieldFrame
end

local function GetAssignedRole(unit)
	local role = type(UnitGroupRolesAssigned) == 'function' and UnitGroupRolesAssigned(unit) or nil
	if role == nil or role == '' then
		role = 'NONE'
	end

	if role == 'NONE' and type(GetPartyAssignment) == 'function' and GetPartyAssignment('MAINTANK', unit, true) then
		return 'TANK'
	end

	return role
end

local function GetRoleLabel(role)
	if role == 'TANK' then
		return TANK or 'Tank'
	elseif role == 'HEALER' then
		return HEALER or 'Healer'
	elseif role == 'DAMAGER' then
		return 'DPS'
	end

	return 'None'
end

local function GetRoleColor(role)
	if role == 'TANK' then
		return 0.3, 0.6, 1
	elseif role == 'HEALER' then
		return 0.2, 0.85, 0.3
	elseif role == 'DAMAGER' then
		return 1, 0.35, 0.35
	end

	return 0.7, 0.7, 0.7
end

local function GetUnitDisplayName(unit)
	if type(GetUnitName) == 'function' then
		return GetUnitName(unit, true) or UNKNOWN
	end

	local name = UnitName(unit)
	return name or UNKNOWN
end

local function AddRoleTooltipLine(tooltip, unit)
	if not tooltip or not unit or not UnitExists(unit) then
		return
	end

	local name = GetUnitDisplayName(unit)
	local classToken = select(2, UnitClass(unit))
	local classColor = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classToken]) or RAID_CLASS_COLORS[classToken] or NORMAL_FONT_COLOR
	local role = GetAssignedRole(unit)
	local roleR, roleG, roleB = GetRoleColor(role)
	tooltip:AddDoubleLine(name, GetRoleLabel(role), classColor.r or 1, classColor.g or 1, classColor.b or 1, roleR, roleG, roleB)
end

local function GetGroupRoleCounts()
	local counts = {
		TANK = 0,
		HEALER = 0,
		DAMAGER = 0,
		NONE = 0
	}

	local function CountUnit(unit)
		if not unit or not UnitExists(unit) then
			return
		end

		local role = GetAssignedRole(unit)
		if counts[role] == nil then
			role = 'NONE'
		end

		counts[role] = counts[role] + 1
	end

	if not IsInGroup() then
		return counts
	end

	if IsInRaid() then
		local total = type(GetNumGroupMembers) == 'function' and GetNumGroupMembers() or 0
		for index = 1, total do
			CountUnit('raid' .. index)
		end
		return counts
	end

	CountUnit('player')
	local partyMembers = type(GetNumSubgroupMembers) == 'function' and GetNumSubgroupMembers() or math.max((GetNumGroupMembers() or 1) - 1, 0)
	for index = 1, partyMembers do
		CountUnit('party' .. index)
	end

	return counts
end

local function PrintRaidRoleSummary()
	local counts = GetGroupRoleCounts()
	Print(string.format('Tank: %d', counts.TANK or 0))
	Print(string.format('Healers: %d', counts.HEALER or 0))
	Print(string.format('DPS: %d', counts.DAMAGER or 0))
end

local function AddGroupRoleTooltipLines(tooltip)
	if not tooltip then
		return
	end

	tooltip:AddLine(' ')
	tooltip:AddLine('Group Roles', 1, 0.82, 0)

	if not IsInGroup() then
		tooltip:AddLine('Not in a party or raid.', 0.7, 0.7, 0.7)
		return
	end

	if IsInRaid() then
		local counts = GetGroupRoleCounts()
		tooltip:AddDoubleLine('Tank', tostring(counts.TANK or 0), 0.85, 0.85, 0.85, GetRoleColor('TANK'))
		tooltip:AddDoubleLine('Healers', tostring(counts.HEALER or 0), 0.85, 0.85, 0.85, GetRoleColor('HEALER'))
		tooltip:AddDoubleLine('DPS', tostring(counts.DAMAGER or 0), 0.85, 0.85, 0.85, GetRoleColor('DAMAGER'))
		return
	end

	AddRoleTooltipLine(tooltip, 'player')
	local partyMembers = type(GetNumSubgroupMembers) == 'function' and GetNumSubgroupMembers() or math.max((GetNumGroupMembers() or 1) - 1, 0)
	for index = 1, partyMembers do
		AddRoleTooltipLine(tooltip, 'party' .. index)
	end
end

local function TriggerRoleCheck()
	if type(InitiateRolePoll) ~= 'function' then
		Print('Role checks are unavailable on this client.')
		return
	end

	if not IsInGroup() or (type(GetNumGroupMembers) == 'function' and GetNumGroupMembers() < 2 and not IsInRaid()) then
		Print('Role check requires a party or raid.')
		return
	end

	local result = InitiateRolePoll()
	if result == false then
		Print('Unable to start a role check right now.')
		return
	end

	if IsInRaid() then
		PrintRaidRoleSummary()
	end
end

local function ClampWidgetCoord(coord)
	coord = tonumber(coord) or 0

	if coord < -1 then
		return -1
	elseif coord > 1 then
		return 1
	end

	return coord
end

local function IsValidWidgetEdge(edge)
	return edge == 'top' or edge == 'right' or edge == 'bottom' or edge == 'left'
end

local function GetWidgetPosition(widgetId)
	local db = GetDatabase()
	local defaultPosition = WIDGET_DEFAULT_POSITIONS[widgetId] or WIDGET_DEFAULT_POSITIONS.clock
	local savedPosition = db.widgetPositions[widgetId]

	if type(savedPosition) ~= 'table' then
		savedPosition = {
			edge = defaultPosition.edge,
			coord = defaultPosition.coord
		}
		db.widgetPositions[widgetId] = savedPosition
	end

	if not IsValidWidgetEdge(savedPosition.edge) then
		savedPosition.edge = defaultPosition.edge
	end

	savedPosition.coord = ClampWidgetCoord(savedPosition.coord or defaultPosition.coord)
	return savedPosition.edge, savedPosition.coord
end

local function SetWidgetPosition(widgetId, edge, coord)
	local db = GetDatabase()
	local defaultPosition = WIDGET_DEFAULT_POSITIONS[widgetId] or WIDGET_DEFAULT_POSITIONS.clock

	if not IsValidWidgetEdge(edge) then
		edge = defaultPosition.edge
	end

	db.widgetPositions[widgetId] = {
		edge = edge,
		coord = ClampWidgetCoord(coord)
	}
end

local function GetWidgetAnchorOffsets(frame, widgetId, edge, coord)
	local halfWidth = (Minimap:GetWidth() or DEFAULT_SIZE) * 0.5
	local halfHeight = (Minimap:GetHeight() or DEFAULT_SIZE) * 0.5
	local frameHalfWidth = ((frame.GetWidth and frame:GetWidth()) or 32) * 0.5
	local frameHalfHeight = ((frame.GetHeight and frame:GetHeight()) or 32) * 0.5
	local horizontalRange = math.max(halfWidth - frameHalfWidth, 0)
	local verticalRange = math.max(halfHeight - frameHalfHeight, 0)
	local outsideX = halfWidth + frameHalfWidth + WIDGET_EDGE_PADDING - WIDGET_BORDER_OVERLAP
	local outsideY = halfHeight + frameHalfHeight + WIDGET_EDGE_PADDING - WIDGET_BORDER_OVERLAP

	coord = ClampWidgetCoord(coord)

	if edge == 'top' then
		return coord * horizontalRange, outsideY
	elseif edge == 'right' then
		return outsideX, coord * verticalRange
	elseif edge == 'bottom' then
		local yOffset = -outsideY
		if widgetId == 'clock' then
			yOffset = yOffset + CLOCK_BOTTOM_OFFSET
		end

		return coord * horizontalRange, yOffset
	end

	return -outsideX, coord * verticalRange
end

local function UpdateWidgetPositionFromCursor(frame, widgetId)
	local scale = Minimap:GetEffectiveScale() or 1
	local cursorX, cursorY = GetCursorPosition()
	local centerX, centerY = Minimap:GetCenter()
	if not centerX or not centerY then
		return
	end

	local relativeX = (cursorX / scale) - centerX
	local relativeY = (cursorY / scale) - centerY
	local halfWidth = (Minimap:GetWidth() or DEFAULT_SIZE) * 0.5
	local halfHeight = (Minimap:GetHeight() or DEFAULT_SIZE) * 0.5
	local frameHalfWidth = ((frame.GetWidth and frame:GetWidth()) or 32) * 0.5
	local frameHalfHeight = ((frame.GetHeight and frame:GetHeight()) or 32) * 0.5
	local horizontalRange = math.max(halfWidth - frameHalfWidth, 1)
	local verticalRange = math.max(halfHeight - frameHalfHeight, 1)
	local horizontalRatio = math.abs(relativeX) / horizontalRange
	local verticalRatio = math.abs(relativeY) / verticalRange
	local edge
	local coord

	if verticalRatio >= horizontalRatio then
		edge = relativeY >= 0 and 'top' or 'bottom'
		coord = relativeX / horizontalRange
	else
		edge = relativeX >= 0 and 'right' or 'left'
		coord = relativeY / verticalRange
	end

	SetWidgetPosition(widgetId, edge, coord)
end

local function AnchorProxy(frame, widgetId)
	if not frame or not Minimap then
		return
	end

	local edge, coord = GetWidgetPosition(widgetId)
	local xOffset, yOffset = GetWidgetAnchorOffsets(frame, widgetId, edge, coord)
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', Minimap, 'CENTER', xOffset, yOffset)
end

local function PreserveWidgetMethods(frame)
	if not frame or widgetMethods[frame] then
		return
	end

	widgetMethods[frame] = {
		ClearAllPoints = frame.ClearAllPoints,
		SetPoint = frame.SetPoint,
		SetParent = frame.SetParent,
		SetScale = frame.SetScale,
		Show = frame.Show
	}
end

local function CallWidgetMethod(frame, methodName, ...)
	local methods = widgetMethods[frame]
	local method = methods and methods[methodName]
	if not method then
		method = frame and frame[methodName]
	end

	if method then
		return method(frame, ...)
	end
end

local function EnsureMinimapButtonButtonBlacklist()
	if type(_G.MinimapButtonButtonOptions) ~= 'table' then
		_G.MinimapButtonButtonOptions = {}
	end

	if type(_G.MinimapButtonButtonOptions.blacklist) ~= 'table' then
		_G.MinimapButtonButtonOptions.blacklist = {}
	end

	for _, frameName in ipairs(WIDGET_BLACKLIST_NAMES) do
		_G.MinimapButtonButtonOptions.blacklist[frameName] = true
	end
end

local function AnchorWidget(frame, point, relativePoint, xOffset, yOffset)
	if not frame or not Minimap or adjustingWidgetLayout then
		return
	end

	PreserveWidgetMethods(frame)

	adjustingWidgetLayout = true
	CallWidgetMethod(frame, 'SetParent', Minimap)
	CallWidgetMethod(frame, 'SetScale', 1)
	CallWidgetMethod(frame, 'ClearAllPoints')
	CallWidgetMethod(frame, 'SetPoint', point, Minimap, relativePoint, xOffset, yOffset)
	adjustingWidgetLayout = false
end

local function AnchorStoredWidget(frame, widgetId)
	if not frame or not Minimap or adjustingWidgetLayout then
		return
	end

	PreserveWidgetMethods(frame)

	local edge, coord = GetWidgetPosition(widgetId)
	local xOffset, yOffset = GetWidgetAnchorOffsets(frame, widgetId, edge, coord)

	adjustingWidgetLayout = true
	CallWidgetMethod(frame, 'SetParent', Minimap)
	CallWidgetMethod(frame, 'SetScale', 1)
	CallWidgetMethod(frame, 'ClearAllPoints')
	CallWidgetMethod(frame, 'SetPoint', 'CENTER', Minimap, 'CENTER', xOffset, yOffset)
	adjustingWidgetLayout = false
end

local function HookWidgetPosition(frame)
	if not frame or frame.__ProkinWidgetHooked or not frame.SetPoint then
		return
	end

	frame.__ProkinWidgetHooked = true
	hooksecurefunc(frame, 'SetPoint', function()
		ApplyBlizzardWidgetLayout()
	end)
end

local function SetProxyButtonPressed(button, pressed)
	if not button or not button.icon or not button.overlay then
		return
	end

	button.icon:ClearAllPoints()
	if pressed then
		button.icon:SetPoint('CENTER', button, 'CENTER', PROXY_ICON_OFFSET_X + 1, PROXY_ICON_OFFSET_Y - 1)
		button.overlay:Show()
	else
		button.icon:SetPoint('CENTER', button, 'CENTER', PROXY_ICON_OFFSET_X, PROXY_ICON_OFFSET_Y)
		button.overlay:Hide()
	end
end

local function CreateProxyButton(name)
	local button = CreateFrame('Button', name, _G.UIParent)
	button:SetFrameStrata('MEDIUM')
	button:SetFrameLevel(Minimap:GetFrameLevel() + 25)
	button:SetSize(PROXY_BUTTON_SIZE, PROXY_BUTTON_SIZE)
	button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')

	button.background = button:CreateTexture(nil, 'BACKGROUND')
	button.background:SetTexture([[Interface\Minimap\UI-Minimap-Background]])
	button.background:SetSize(PROXY_BACKGROUND_SIZE, PROXY_BACKGROUND_SIZE)
	button.background:SetPoint('CENTER', button, 'CENTER', 0, 0)
	button.background:SetVertexColor(1, 1, 1, 0.6)

	button.icon = button:CreateTexture(nil, 'ARTWORK')
	button.icon:SetSize(PROXY_ICON_SIZE, PROXY_ICON_SIZE)
	button.icon:SetPoint('CENTER', button, 'CENTER', PROXY_ICON_OFFSET_X, PROXY_ICON_OFFSET_Y)

	button.overlay = button:CreateTexture(nil, 'OVERLAY')
	button.overlay:SetAllPoints(button.icon)
	button.overlay:SetColorTexture(0, 0, 0, 0.5)
	button.overlay:Hide()

	button.border = button:CreateTexture(nil, 'BORDER')
	button.border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
	button.border:SetSize(PROXY_BORDER_SIZE, PROXY_BORDER_SIZE)
	button.border:SetPoint('TOPLEFT', button, 'TOPLEFT', 0, 0)

	button:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]], 'ADD')
	local highlight = button:GetHighlightTexture()
	if highlight then
		highlight:SetAllPoints(button)
	end

	button:SetScript('OnMouseDown', function(self, mouseButton)
		SetProxyButtonPressed(self, true)
		if self.__ProkinMouseDownHandler then
			self:__ProkinMouseDownHandler(mouseButton)
		end
	end)
	button:SetScript('OnMouseUp', function(self, mouseButton)
		SetProxyButtonPressed(self, false)
		if self.__ProkinMouseUpHandler then
			self:__ProkinMouseUpHandler(mouseButton)
		end
	end)

	return button
end

local function BeginWidgetDrag(frame, widgetId, useStoredAnchor)
	if not frame or not widgetId then
		return
	end

	if frame == trackingProxyButton then
		local trackingButton = GetTrackingButton()
		if trackingButton and trackingButton.CloseMenu and trackingButton.IsMenuOpen and trackingButton:IsMenuOpen() then
			trackingButton:CloseMenu()
			PrintTrackingDebug(string.format('closed tracking menu before dragging %s', GetFrameDebugName(frame)))
		end
	end

	activeWidgetDrag = {
		frame = frame,
		widgetId = widgetId,
		useStoredAnchor = useStoredAnchor
	}

	GameTooltip_Hide()
end

local function StopWidgetDrag(frame)
	if not activeWidgetDrag or activeWidgetDrag.frame ~= frame then
		return false
	end

	UpdateWidgetPositionFromCursor(frame, activeWidgetDrag.widgetId)

	if activeWidgetDrag.useStoredAnchor then
		AnchorStoredWidget(frame, activeWidgetDrag.widgetId)
	else
		AnchorProxy(frame, activeWidgetDrag.widgetId)
	end

	if frame.overlay then
		SetProxyButtonPressed(frame, false)
	end

	if frame == trackingProxyButton then
		PrintTrackingDebug(string.format('tracking drag stopped; suppressing next click on %s', GetFrameDebugName(frame)))
	end

	frame.__ProkinSuppressClick = true
	activeWidgetDrag = nil
	return true
end

local function UpdateWidgetDrag()
	if not activeWidgetDrag then
		return
	end

	local frame = activeWidgetDrag.frame
	if not frame then
		activeWidgetDrag = nil
		return
	end

	UpdateWidgetPositionFromCursor(frame, activeWidgetDrag.widgetId)

	if activeWidgetDrag.useStoredAnchor then
		AnchorStoredWidget(frame, activeWidgetDrag.widgetId)
	else
		AnchorProxy(frame, activeWidgetDrag.widgetId)
	end
end

local function WrapWidgetScript(frame, scriptName)
	if not frame or not scriptName or not frame.GetScript or not frame.SetScript then
		return
	end

	if not frame.HasScript or not frame:HasScript(scriptName) then
		return
	end

	if not frame.__ProkinWrappedScripts then
		frame.__ProkinWrappedScripts = {}
	elseif frame.__ProkinWrappedScripts[scriptName] then
		return
	end

	local originalScript = frame:GetScript(scriptName)
	if originalScript then
		frame:SetScript(scriptName, function(self, ...)
			if self.__ProkinSuppressClick then
				if self == trackingProxyButton then
					PrintTrackingDebug(string.format('suppressed tracking proxy %s after drag on %s', scriptName, GetFrameDebugName(self)))
				end
				self.__ProkinSuppressClick = nil
				return
			end

			return originalScript(self, ...)
		end)
	end

	frame.__ProkinWrappedScripts[scriptName] = true
end

local function WrapWidgetClicks(frame)
	if not frame then
		return
	end

	WrapWidgetScript(frame, 'OnClick')
	WrapWidgetScript(frame, 'OnMouseUp')
end

local function MakeWidgetDraggable(frame, widgetId, useStoredAnchor)
	if not frame or frame.__ProkinDragEnabled then
		return
	end

	if frame.EnableMouse then
		frame:EnableMouse(true)
	end

	if frame.RegisterForDrag then
		frame:RegisterForDrag('LeftButton')
	end

	WrapWidgetClicks(frame)

	if frame.HookScript then
		frame:HookScript('OnDragStart', function(self)
			BeginWidgetDrag(self, widgetId, useStoredAnchor)
		end)
		frame:HookScript('OnDragStop', function(self)
			StopWidgetDrag(self)
		end)
	end

	frame.__ProkinDragEnabled = true
end

local function ReanchorTrackingMenu(anchor)
	local dropDown = _G.DropDownList1
	if not anchor or not dropDown or not dropDown.IsShown or not dropDown:IsShown() then
		PrintTrackingDebug(string.format('reanchor skipped; anchor=%s dropdownShown=%s', GetFrameDebugName(anchor), dropDown and dropDown.IsShown and dropDown:IsShown() and 'true' or 'false'))
		return false
	end

	dropDown:ClearAllPoints()
	dropDown:SetPoint('TOPRIGHT', anchor, 'BOTTOMRIGHT', 0, -2)
	pendingTrackingMenuAnchor = nil
	PrintTrackingDebug(string.format('reanchored dropdown %s to %s', GetFrameDebugName(dropDown), GetFrameDebugName(anchor)))
	return true
end

local function QueueTrackingMenuReanchor(anchor)
	if not anchor then
		return
	end

	pendingTrackingMenuAnchor = anchor

	local dropDown = _G.DropDownList1
	if dropDown and dropDown.HookScript and not dropDown.__ProkinTrackingReanchorHooked then
		dropDown:HookScript('OnShow', function()
			PrintTrackingDebug(string.format('dropdown shown: %s pendingAnchor=%s', GetFrameDebugName(dropDown), GetFrameDebugName(pendingTrackingMenuAnchor)))
			if pendingTrackingMenuAnchor then
				ReanchorTrackingMenu(pendingTrackingMenuAnchor)
			end
		end)
		dropDown:HookScript('OnHide', function()
			PrintTrackingDebug(string.format('dropdown hidden: %s', GetFrameDebugName(dropDown)))
		end)
		dropDown.__ProkinTrackingReanchorHooked = true
		PrintTrackingDebug(string.format('hooked dropdown debug handlers on %s', GetFrameDebugName(dropDown)))
	end

	if ReanchorTrackingMenu(anchor) then
		return
	end

	if type(C_Timer) == 'table' and type(C_Timer.After) == 'function' then
		C_Timer.After(0, function()
			if pendingTrackingMenuAnchor == anchor then
				if not ReanchorTrackingMenu(anchor) then
					PrintTrackingDebug(string.format('next-frame reanchor failed for anchor=%s', GetFrameDebugName(anchor)))
					pendingTrackingMenuAnchor = nil
				end
			end
		end)
	else
		PrintTrackingDebug('C_Timer.After is unavailable; clearing pending tracking menu anchor')
		pendingTrackingMenuAnchor = nil
	end
end

local function IsModernTrackingDropdownButton(button)
	return button
		and button.OpenMenu
		and button.SetMenuAnchor
		and not _G.MiniMapTrackingDropDown
end

local function RetargetTrackingMenuAnchor(button, anchor)
	if not button or not anchor or not button.SetMenuAnchor then
		return false
	end

	if type(AnchorUtil) ~= 'table' or type(AnchorUtil.CreateAnchor) ~= 'function' then
		PrintTrackingDebug('AnchorUtil.CreateAnchor is unavailable for modern tracking menu retargeting')
		return false
	end

	local menuAnchor = AnchorUtil.CreateAnchor(
		button.menuPoint or 'TOPLEFT',
		anchor,
		button.menuRelativePoint or 'BOTTOMLEFT',
		button.menuPointX or 0,
		button.menuPointY or 0
	)

	button:SetMenuAnchor(menuAnchor)
	PrintTrackingDebug(string.format('retargeted modern tracking menu anchor to %s', GetFrameDebugName(anchor)))
	return true
end

local function OpenModernTrackingMenuOnProxy(button, anchor)
	if not button or not anchor then
		return false
	end

	if button.IsMenuOpen and button:IsMenuOpen() then
		PrintTrackingDebug(string.format('modern tracking menu already open on %s; closing it', GetFrameDebugName(button)))
		if button.CloseMenu then
			button:CloseMenu()
			return true
		end
	end

	if type(AnchorUtil) ~= 'table' or type(AnchorUtil.CreateAnchor) ~= 'function' then
		PrintTrackingDebug('AnchorUtil.CreateAnchor is unavailable for proxy-owned modern tracking menu')
		return false
	end

	if not button.GenerateMenu or not button.GetMenuDescription then
		PrintTrackingDebug(string.format('modern tracking button %s cannot generate a menu description', GetFrameDebugName(button)))
		return false
	end

	button:GenerateMenu()
	local menuDescription = button:GetMenuDescription()
	if not menuDescription then
		PrintTrackingDebug(string.format('modern tracking button %s generated no menu description', GetFrameDebugName(button)))
		return false
	end

	if type(Menu) ~= 'table' or not Menu.GetManager then
		PrintTrackingDebug('Menu.GetManager is unavailable for proxy-owned modern tracking menu')
		return false
	end

	local menuAnchor = AnchorUtil.CreateAnchor(
		button.menuPoint or 'TOPLEFT',
		anchor,
		button.menuRelativePoint or 'BOTTOMLEFT',
		button.menuPointX or 0,
		button.menuPointY or 0
	)

	local menuManager = Menu.GetManager()
	local menu = menuManager and menuManager:OpenMenu(anchor, menuDescription, menuAnchor)
	button.menu = menu
	if menu then
		if button.onMenuClosedCallback then
			menu:SetClosedCallback(button.onMenuClosedCallback)
		end

		if button.OnMenuOpened then
			button:OnMenuOpened(menu)
		end
	end

	PrintTrackingDebug(string.format(
		'opened modern tracking menu on proxy owner=%s menu=%s menuOpen=%s',
		GetFrameDebugName(anchor),
		menu and GetFrameDebugName(menu) or 'nil',
		button.IsMenuOpen and button:IsMenuOpen() and 'true' or 'false'
	))
	return menu ~= nil
end

local function OpenTrackingMenu(anchor)
	local button = GetTrackingButton()
	if not button then
		PrintTrackingDebug('OpenTrackingMenu aborted because no tracking button was found')
		return
	end

	PrintTrackingDebug(string.format(
		'OpenTrackingMenu anchor=%s resolvedButton=%s dropdownExists=%s minimapTracking=%s',
		GetFrameDebugName(anchor),
		DescribeFrame(button),
		_G.MiniMapTrackingDropDown and 'true' or 'false',
		_G.MiniMapTracking and DescribeFrame(_G.MiniMapTracking) or 'nil'
	))

	if IsModernTrackingDropdownButton(button) then
		if OpenModernTrackingMenuOnProxy(button, anchor) then
			return
		end

		RetargetTrackingMenuAnchor(button, anchor)

		local onMouseDown = button.GetScript and button:GetScript('OnMouseDown')
		if onMouseDown then
			PrintTrackingDebug(string.format('opening tracking menu via OnMouseDown script on %s', GetFrameDebugName(button)))
			onMouseDown(button, 'LeftButton')
			PrintTrackingDebug(string.format(
				'post-modern-script menuOpen=%s menu=%s',
				button.IsMenuOpen and button:IsMenuOpen() and 'true' or 'false',
				button.menu and GetFrameDebugName(button.menu) or 'nil'
			))
			return
		end

		PrintTrackingDebug('modern tracking button detected, but no mouse-down opener was available')
	end

	if _G.MiniMapTrackingDropDown and _G.MiniMapTracking then
		if GameTooltip.GetOwner and GameTooltip:GetOwner() == _G.MiniMapTracking then
			GameTooltip:Hide()
		end

		PrintTrackingDebug('opening tracking menu via ToggleDropDownMenu anchored to MiniMapTracking')
		ToggleDropDownMenu(1, nil, _G.MiniMapTrackingDropDown, 'MiniMapTracking', 0, -5)
		PrintTrackingDebug(string.format('post-toggle dropdown shown=%s', _G.DropDownList1 and _G.DropDownList1.IsShown and _G.DropDownList1:IsShown() and 'true' or 'false'))
		QueueTrackingMenuReanchor(anchor)
		return
	end

	if button.OpenMenu then
		PrintTrackingDebug(string.format('opening tracking menu via OpenMenu on %s', GetFrameDebugName(button)))
		button:OpenMenu()
		if button.menu and button.menu.ClearAllPoints and button.menu.SetPoint then
			button.menu:ClearAllPoints()
			button.menu:SetPoint('TOPRIGHT', anchor, 'BOTTOMRIGHT', 0, -2)
		end
		return
	end

	local onMouseUp = button.GetScript and button:GetScript('OnMouseUp')
	if onMouseUp then
		PrintTrackingDebug(string.format('opening tracking menu via OnMouseUp on %s', GetFrameDebugName(button)))
		onMouseUp(button, 'LeftButton')
		PrintTrackingDebug(string.format('post-OnMouseUp dropdown shown=%s', _G.DropDownList1 and _G.DropDownList1.IsShown and _G.DropDownList1:IsShown() and 'true' or 'false'))
		QueueTrackingMenuReanchor(anchor)
		return
	end

	local onClick = button.GetScript and button:GetScript('OnClick')
	if onClick then
		PrintTrackingDebug(string.format('opening tracking menu via OnClick on %s', GetFrameDebugName(button)))
		onClick(button, 'LeftButton')
		PrintTrackingDebug(string.format('post-OnClick dropdown shown=%s', _G.DropDownList1 and _G.DropDownList1.IsShown and _G.DropDownList1:IsShown() and 'true' or 'false'))
		QueueTrackingMenuReanchor(anchor)
		return
	end

	if _G.MiniMapTrackingDropDown then
		PrintTrackingDebug(string.format('opening tracking menu via fallback ToggleDropDownMenu anchored to %s', GetFrameDebugName(anchor)))
		ToggleDropDownMenu(1, nil, _G.MiniMapTrackingDropDown, anchor, 0, -5)
		PrintTrackingDebug(string.format('post-fallback toggle dropdown shown=%s', _G.DropDownList1 and _G.DropDownList1.IsShown and _G.DropDownList1:IsShown() and 'true' or 'false'))
		QueueTrackingMenuReanchor(anchor)
		return
	end

	PrintTrackingDebug('OpenTrackingMenu exhausted all paths without opening a dropdown')
end

local function EnsureTrackingProxy()
	if trackingProxyButton or not Minimap then
		return
	end

	trackingProxyButton = CreateProxyButton('ProkinMinimapTrackingProxy')
	trackingProxyButton.__ProkinMouseDownHandler = function(self, mouseButton)
		PrintTrackingDebug(string.format(
			'tracking proxy mouse down button=%s activeDrag=%s suppressClick=%s self=%s',
			tostring(mouseButton),
			activeWidgetDrag and 'true' or 'false',
			self.__ProkinSuppressClick and 'true' or 'false',
			DescribeFrame(self)
		))
		if mouseButton == 'LeftButton' then
			OpenTrackingMenu(self)
		end
	end
	trackingProxyButton.__ProkinMouseUpHandler = function(self, mouseButton)
		PrintTrackingDebug(string.format(
			'tracking proxy mouse up button=%s activeDrag=%s suppressClick=%s self=%s',
			tostring(mouseButton),
			activeWidgetDrag and 'true' or 'false',
			self.__ProkinSuppressClick and 'true' or 'false',
			DescribeFrame(self)
		))
	end
	trackingProxyButton.HandlesGlobalMouseEvent = function(_, buttonName, event)
		local handled = event == 'GLOBAL_MOUSE_DOWN' and buttonName == 'LeftButton'
		if handled then
			PrintTrackingDebug(string.format('tracking proxy handled global mouse event button=%s event=%s', tostring(buttonName), tostring(event)))
		end
		return handled
	end
	trackingProxyButton:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:SetText(TRACKING, 1, 1, 1)
		GameTooltip:AddLine(MINIMAP_TRACKING_TOOLTIP_NONE, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	trackingProxyButton:SetScript('OnLeave', GameTooltip_Hide)
	MakeWidgetDraggable(trackingProxyButton, 'tracking')
end

local function EnsureLFGProxy()
	if lfgProxyButton or not Minimap then
		return
	end

	lfgProxyButton = CreateProxyButton('ProkinMinimapLFGProxy')
	lfgProxyButton.__ProkinMouseUpHandler = function(self, button)
		local lfg = GetLFGFrame()
		local queueButton = _G.QueueStatusMinimapButton or _G.QueueStatusButton
		if lfg and lfg.Click then
			lfg:Click(button or 'LeftButton')
			return
		end

		if queueButton and type(QueueStatusMinimapButton_OnClick) == 'function' then
			QueueStatusMinimapButton_OnClick(queueButton, button or 'LeftButton')
			return
		end

		if type(ToggleLFGParentFrame) == 'function' then
			ToggleLFGParentFrame()
			return
		end

		if type(ToggleLFDParentFrame) == 'function' then
			ToggleLFDParentFrame()
			return
		end

		if type(ToggleFriendsFrame) == 'function' then
			ToggleFriendsFrame(4)
		end
	end
	lfgProxyButton:SetScript('OnEnter', function(self)
		local queueButton = _G.QueueStatusMinimapButton or _G.QueueStatusButton
		if queueButton and type(QueueStatusMinimapButton_OnEnter) == 'function' then
			QueueStatusMinimapButton_OnEnter(queueButton)
			return
		end

		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetText(LOOKING_FOR_GROUP or DUNGEONS_BUTTON or 'Looking For Group', 1, 1, 1)
		GameTooltip:Show()
	end)
	lfgProxyButton:SetScript('OnLeave', function(self)
		local queueButton = _G.QueueStatusMinimapButton or _G.QueueStatusButton
		if queueButton and type(QueueStatusMinimapButton_OnLeave) == 'function' then
			QueueStatusMinimapButton_OnLeave(queueButton)
			return
		end

		GameTooltip_Hide(self)
	end)
	MakeWidgetDraggable(lfgProxyButton, 'lfg')
end

local function GetBattlefieldStatusInfo()
	local battlefield = GetBattlefieldFrame()
	if type(BattlefieldFrame_UpdateStatus) == 'function' then
		BattlefieldFrame_UpdateStatus(1)
	end

	if battlefield and battlefield.status and battlefield.status ~= 'none' then
		return battlefield.status, battlefield.tooltip
	end

	local maxBattlefieldId = type(GetMaxBattlefieldID) == 'function' and GetMaxBattlefieldID() or 0
	local bestStatus
	local bestIndex
	local bestMapName

	for index = 1, maxBattlefieldId do
		local status, mapName = GetBattlefieldStatus(index)
		if status and status ~= 'none' then
			if status == 'active' or
				(status == 'confirm' and bestStatus ~= 'active') or
				(status == 'queued' and not bestStatus) then
				bestStatus = status
				bestIndex = index
				bestMapName = mapName
			end
		end
	end

	if not bestStatus then
		return nil
	end

	local tooltip
	if bestStatus == 'active' then
		if bestMapName and BATTLEFIELD_IN_BATTLEFIELD then
			tooltip = string.format(BATTLEFIELD_IN_BATTLEFIELD, bestMapName)
		else
			tooltip = bestMapName or BATTLEFIELDS
		end
	elseif bestStatus == 'confirm' then
		local expiration = type(GetBattlefieldPortExpiration) == 'function' and GetBattlefieldPortExpiration(bestIndex) or 0
		if bestMapName and BATTLEFIELD_QUEUE_CONFIRM then
			tooltip = string.format(BATTLEFIELD_QUEUE_CONFIRM, bestMapName, SecondsToTime((expiration or 0) / 1000))
		else
			tooltip = bestMapName or BATTLEFIELD_ALERT
		end
	elseif bestStatus == 'queued' then
		local waitTime = type(GetBattlefieldEstimatedWaitTime) == 'function' and GetBattlefieldEstimatedWaitTime(bestIndex) or 0
		local timeInQueue = type(GetBattlefieldTimeWaited) == 'function' and GetBattlefieldTimeWaited(bestIndex) or 0
		local waitText = QUEUE_TIME_UNAVAILABLE or UNKNOWN
		if waitTime and waitTime > 0 then
			if waitTime < 60000 then
				waitText = LESS_THAN_ONE_MINUTE or waitText
			else
				waitText = SecondsToTime(waitTime / 1000, 1)
			end
		end

		if bestMapName and BATTLEFIELD_IN_QUEUE then
			tooltip = string.format(BATTLEFIELD_IN_QUEUE, bestMapName, waitText, SecondsToTime((timeInQueue or 0) / 1000))
		else
			tooltip = bestMapName or BATTLEFIELDS
		end
	end

	return bestStatus, tooltip
end

local function ClickBattlefieldFrame(mouseButton)
	local battlefield = GetBattlefieldFrame()
	if not battlefield then
		return false
	end

	if battlefield.Click then
		battlefield:Click(mouseButton or 'LeftButton')
		return true
	end

	local onClick = battlefield.GetScript and battlefield:GetScript('OnClick')
	if onClick then
		onClick(battlefield, mouseButton or 'LeftButton')
		return true
	end

	return false
end

local function EnsureBattlefieldProxy()
	if battlefieldProxyButton or not Minimap then
		return
	end

	battlefieldProxyButton = CreateProxyButton('ProkinMinimapBattlefieldProxy')
	battlefieldProxyButton.icon:SetTexture([[Interface\BattlefieldFrame\UI-Battlefield-Icon]])
	battlefieldProxyButton.icon:SetTexCoord(0, 1, 0, 1)
	battlefieldProxyButton.__ProkinMouseUpHandler = function(self, button)
		local status = GetBattlefieldStatusInfo()
		GameTooltip_Hide()

		if status == 'active' then
			if button == 'RightButton' then
				ClickBattlefieldFrame('RightButton')
			elseif button == 'LeftButton' and ClickBattlefieldFrame('LeftButton') then
				return
			elseif IsShiftKeyDown() and type(ToggleBattlefieldMinimap) == 'function' then
				ToggleBattlefieldMinimap()
			elseif type(ToggleWorldStateScoreFrame) == 'function' then
				ToggleWorldStateScoreFrame()
			end
		elseif status == 'queued' or status == 'confirm' then
			if button == 'LeftButton' or button == 'RightButton' then
				ClickBattlefieldFrame('RightButton')
			end
		end
	end
	battlefieldProxyButton:SetScript('OnEnter', function(self)
		local _, tooltip = GetBattlefieldStatusInfo()
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:SetText(tooltip or (BATTLEFIELDS or PVP))
		GameTooltip:Show()
	end)
	battlefieldProxyButton:SetScript('OnLeave', GameTooltip_Hide)
	MakeWidgetDraggable(battlefieldProxyButton, 'battlefield')
end

local function UpdateTrackingProxy()
	EnsureTrackingProxy()
	if not trackingProxyButton then
		return
	end

	local texturePath = [[Interface\Minimap\Tracking\None]]
	local left, right, top, bottom = 0, 1, 0, 1
	local count = GetNumTrackingTypes and GetNumTrackingTypes() or 0

	for id = 1, count do
		local _, texture, active, category = GetTrackingInfo(id)
		if active then
			texturePath = texture or texturePath
			if category == 'spell' then
				left, right, top, bottom = 0.0625, 0.9, 0.0625, 0.9
			end
			break
		end
	end

	trackingProxyButton.icon:SetTexture(texturePath)
	trackingProxyButton.icon:SetTexCoord(left, right, top, bottom)
end

local function UpdateLFGProxy()
	EnsureLFGProxy()
	if not lfgProxyButton then
		return
	end

	local texturePath = [[Interface\LFGFrame\LFG-Eye]]
	local left, right, top, bottom = 0, 0.125, 0, 0.25
	local lfg = GetLFGFrame()
	local eye = lfg and lfg.Eye
	local eyeTexture = eye and eye.texture

	if eyeTexture and eyeTexture.GetTexture then
		texturePath = eyeTexture:GetTexture() or texturePath
		if eyeTexture.GetTexCoord then
			left, right, top, bottom = eyeTexture:GetTexCoord()
		end
	end

	lfgProxyButton.icon:SetTexture(texturePath)
	lfgProxyButton.icon:SetTexCoord(left, right, top, bottom)
end

ApplyBlizzardWidgetLayout = function()
	local tracking = GetTrackingFrame()
	EnsureTrackingProxy()
	UpdateTrackingProxy()
	if trackingProxyButton then
		AnchorProxy(trackingProxyButton, 'tracking')
		trackingProxyButton:Show()
	end

	if tracking then
		PreserveWidgetMethods(tracking)
		HookWidgetPosition(tracking)
		if tracking.SetAlpha then
			tracking:SetAlpha(0)
		end

		if _G.MiniMapTracking and _G.MiniMapTracking.SetAlpha then
			_G.MiniMapTracking:SetAlpha(0)
		end
	end

	local lfg = GetLFGFrame()
	EnsureLFGProxy()
	UpdateLFGProxy()
	if lfgProxyButton then
		AnchorProxy(lfgProxyButton, 'lfg')
		lfgProxyButton:Show()
	end

	if lfg then
		PreserveWidgetMethods(lfg)
		HookWidgetPosition(lfg)
		if lfg.SetAlpha then
			lfg:SetAlpha(0)
		end
	end

	local clock = GetClockFrame()
	if clock then
		MakeWidgetDraggable(clock, 'clock', true)
		PreserveWidgetMethods(clock)
		HookWidgetPosition(clock)
		AnchorStoredWidget(clock, 'clock')
		if clock.Show then
			clock:Show()
		end
	end

	local mail = GetMailFrame()
	if mail then
		MakeWidgetDraggable(mail, 'mail', true)
		PreserveWidgetMethods(mail)
		HookWidgetPosition(mail)
		AnchorStoredWidget(mail, 'mail')
		if not mail.__ProkinMailVisibilityHooksInstalled then
			mail.__ProkinMailVisibilityHooksInstalled = true
			if mail.HookScript then
				mail:HookScript('OnShow', RefreshMailVisibility)
				mail:HookScript('OnHide', RefreshMailVisibility)
			end
			if hooksecurefunc then
				hooksecurefunc(mail, 'Hide', RefreshMailVisibility)
				if mail.SetShown then
					hooksecurefunc(mail, 'SetShown', RefreshMailVisibility)
				end
			end
		end
		RefreshMailVisibility()
	end

	local battlefield = GetBattlefieldFrame()
	local battlefieldStatus = GetBattlefieldStatusInfo()
	if battlefieldProxyButton then
		battlefieldProxyButton:Hide()
	end

	if battlefield then
		PreserveWidgetMethods(battlefield)
		HookWidgetPosition(battlefield)
		AnchorStoredWidget(battlefield, 'battlefield')
		if battlefield.SetAlpha then
			battlefield:SetAlpha(1)
		end

		if battlefieldStatus ~= nil then
			if battlefield.Show then
				battlefield:Show()
			end
		elseif battlefield.Hide then
			battlefield:Hide()
		end
	end
end

local function PositionButtonOnSquareEdge(button, angle, edgeOffset, xOffset, yOffset)
	if not Minimap or not button then
		return
	end

	angle = tonumber(angle)
	if not angle then
		return
	end

	local radians = math.rad(angle)
	local xUnit = math.cos(radians)
	local yUnit = math.sin(radians)
	local divisor = math.max(math.abs(xUnit), math.abs(yUnit), 0.0001)
	local halfWidth = (Minimap:GetWidth() or DEFAULT_SIZE) * 0.5
	local halfHeight = (Minimap:GetHeight() or DEFAULT_SIZE) * 0.5
	edgeOffset = tonumber(edgeOffset) or 0
	xOffset = tonumber(xOffset) or 0
	yOffset = tonumber(yOffset) or 0

	button:ClearAllPoints()
	button:SetPoint(
		'CENTER',
		Minimap,
		'CENTER',
		((xUnit / divisor) * (halfWidth + edgeOffset)) + xOffset,
		((yUnit / divisor) * (halfHeight + edgeOffset)) + yOffset
	)
end

local function GetAddonButtonAngle()
	return GetDatabase().minimapButtonAngle or ADDON_BUTTON_DEFAULT_ANGLE
end

local function SetAddonButtonAngle(angle)
	GetDatabase().minimapButtonAngle = NormalizeAngle(angle)
end

local function UpdateAddonButtonAngleFromCursor()
	if not Minimap then
		return
	end

	local scale = Minimap:GetEffectiveScale() or 1
	local cursorX, cursorY = GetCursorPosition()
	local centerX, centerY = Minimap:GetCenter()
	if not centerX or not centerY then
		return
	end

	local relativeX = (cursorX / scale) - centerX
	local relativeY = (cursorY / scale) - centerY
	if relativeX == 0 and relativeY == 0 then
		return
	end

	SetAddonButtonAngle(math.deg(math.atan2(relativeY, relativeX)))
end

local function AnchorAddonMinimapButton()
	if not addonMinimapButton then
		return
	end

	PositionButtonOnSquareEdge(
		addonMinimapButton,
		GetAddonButtonAngle(),
		ADDON_MINIMAP_EDGE_OFFSET,
		ADDON_MINIMAP_ANCHOR_OFFSET_X,
		ADDON_MINIMAP_ANCHOR_OFFSET_Y
	)
end

local function StopAddonButtonDrag(button)
	if addonButtonDragging ~= button then
		return false
	end

	UpdateAddonButtonAngleFromCursor()
	AnchorAddonMinimapButton()
	addonButtonDragging = nil
	button.__ProkinSuppressClick = true
	return true
end

local function UpdateAddonButtonDrag()
	if addonButtonDragging ~= addonMinimapButton then
		return
	end

	UpdateAddonButtonAngleFromCursor()
	AnchorAddonMinimapButton()
end

local function UpdateAddonButtonVisibility()
	if not addonMinimapButton then
		return
	end

	if GetDatabase().showAddonButton == false then
		addonMinimapButton:Hide()
		return
	end

	AnchorAddonMinimapButton()
	addonMinimapButton:Show()
end

local function EnsureAddonMinimapButton()
	if addonMinimapButton or not Minimap then
		return
	end

	local button = CreateFrame('Button', ADDON_BUTTON_NAME, _G.UIParent)
	button:SetSize(ADDON_MINIMAP_BUTTON_SIZE, ADDON_MINIMAP_BUTTON_SIZE)
	button:SetFrameStrata('MEDIUM')
	button:SetFrameLevel(Minimap:GetFrameLevel() + 30)
	button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	button:RegisterForDrag('LeftButton')

	button.background = button:CreateTexture(nil, 'BACKGROUND')
	button.background:SetTexture([[Interface\Minimap\UI-Minimap-Background]])
	button.background:SetSize(ADDON_MINIMAP_BACKGROUND_SIZE, ADDON_MINIMAP_BACKGROUND_SIZE)
	button.background:SetPoint('CENTER', button, 'CENTER', 0, 0)
	button.background:SetVertexColor(1, 1, 1, 0.75)

	button.icon = button:CreateTexture(nil, 'ARTWORK')
	button.icon:SetTexture([[Interface\AddOns\Prokin-Minimap\Media\ProkinFaceIcon.png]])
	button.icon:SetSize(ADDON_MINIMAP_ICON_SIZE, ADDON_MINIMAP_ICON_SIZE)
	button.icon:SetPoint('CENTER', button, 'CENTER', ADDON_MINIMAP_ICON_OFFSET_X, ADDON_MINIMAP_ICON_OFFSET_Y)

	button.overlay = button:CreateTexture(nil, 'OVERLAY')
	button.overlay:SetAllPoints(button.icon)
	button.overlay:SetColorTexture(0, 0, 0, 0.5)
	button.overlay:Hide()

	button.border = button:CreateTexture(nil, 'BORDER')
	button.border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
	button.border:SetSize(ADDON_MINIMAP_BORDER_SIZE, ADDON_MINIMAP_BORDER_SIZE)
	button.border:SetPoint('TOPLEFT', button, 'TOPLEFT', 0, 0)

	button:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]], 'ADD')
	local highlight = button:GetHighlightTexture()
	if highlight then
		highlight:SetAllPoints(button)
	end

	button:SetScript('OnMouseDown', function(self)
		SetProxyButtonPressed(self, true)
	end)
	button:SetScript('OnMouseUp', function(self)
		SetProxyButtonPressed(self, false)
	end)
	button:SetScript('OnClick', function(self, mouseButton)
		if self.__ProkinSuppressClick then
			self.__ProkinSuppressClick = nil
			return
		end

		if mouseButton == 'LeftButton' then
			TriggerRoleCheck()
		elseif mouseButton == 'RightButton' then
			OpenOptionsWindow()
		end
	end)
	button:SetScript('OnDragStart', function(self)
		if not IsAltKeyDown() then
			return
		end

		addonButtonDragging = self
		GameTooltip_Hide()
	end)
	button:SetScript('OnDragStop', StopAddonButtonDrag)
	button:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:AddLine('Prokin Minimap', 1, 1, 1)
		GameTooltip:AddLine('Left-Click: Start a role check', 0.85, 0.85, 0.85)
		GameTooltip:AddLine('Right-Click: Open options', 0.85, 0.85, 0.85)
		GameTooltip:AddLine('Alt-Left-Drag: Move button', 0.85, 0.85, 0.85)
		AddGroupRoleTooltipLines(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript('OnLeave', GameTooltip_Hide)
	button.HandlesGlobalMouseEvent = function(_, buttonName, event)
		return event == 'GLOBAL_MOUSE_DOWN' and (buttonName == 'LeftButton' or buttonName == 'RightButton')
	end

	addonMinimapButton = button
	UpdateAddonButtonVisibility()
end

local function ApplyAutoMarkAssistCompatibility()
	local button = _G.AMA_MinimapButton
	local db = _G.AutoMarkAssistDB
	if not button or not db then
		return
	end

	PositionButtonOnSquareEdge(button, db.minimapAngle or 225)
end

local function InstallAutoMarkAssistCompatibility()
	if autoMarkAssistHookInstalled then
		return
	end

	local autoMarkAssist = _G.AutoMarkAssist
	if not autoMarkAssist or type(autoMarkAssist.UpdateMinimapPosition) ~= 'function' then
		return
	end

	hooksecurefunc(autoMarkAssist, 'UpdateMinimapPosition', ApplyAutoMarkAssistCompatibility)
	autoMarkAssistHookInstalled = true
	ApplyAutoMarkAssistCompatibility()
end

RefreshMinimap = function()
	if type(InCombatLockdown) == 'function' and InCombatLockdown() then
		minimapRefreshPending = true
		return
	end

	minimapRefreshPending = nil
	_G.GetMinimapShape = GetSquareMinimapShape
	EnsureMinimapButtonButtonBlacklist()
	ApplySquareMinimap()
	EnsureMinimapBorder()
	ApplyMinimapBorderVisibility()
	EnsureAddonMinimapButton()
	UpdateAddonButtonVisibility()
	ApplyZoneLayout()
	HideDefaultZoneHeader()
	ApplyBlizzardWidgetLayout()
	ApplyHybridMinimap()
	InstallAutoMarkAssistCompatibility()
	ApplyAutoMarkAssistCompatibility()
end

SetMinimapSize = function(size)
	local normalized = NormalizeSize(size)
	if not normalized then
		return nil
	end

	GetDatabase().size = normalized
	RefreshMinimap()

	return normalized
end

local function CreateOptionsCheckbox(parent, label, tooltipText)
	local check = CreateFrame('CheckButton', nil, parent, 'UICheckButtonTemplate')
	check.text = check:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	check.text:SetPoint('LEFT', check, 'RIGHT', 2, 1)
	check.text:SetJustifyH('LEFT')
	check.text:SetWidth(360)
	check.text:SetWordWrap(true)
	check.text:SetText(label)

	if tooltipText then
		check:SetScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tooltipText, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		check:SetScript('OnLeave', GameTooltip_Hide)
	end

	return check
end

local OPTION_SLIDER_BACKDROP = {
	bgFile = [[Interface\Buttons\UI-SliderBar-Background]],
	edgeFile = [[Interface\Buttons\UI-SliderBar-Border]],
	tile = true,
	tileSize = 8,
	edgeSize = 8,
	insets = { left = 3, right = 3, top = 6, bottom = 6 }
}

local function UpdateOptionsSliderVisuals(slider, value)
	if not slider or not slider.fill then
		return
	end

	local minValue, maxValue = slider:GetMinMaxValues()
	local range = maxValue - minValue
	local width = slider:GetWidth() or 0
	local normalized = 0
	if range > 0 then
		normalized = (value - minValue) / range
	end

	if normalized < 0 then
		normalized = 0
	elseif normalized > 1 then
		normalized = 1
	end

	slider.fill:SetWidth(math.floor((width - 6) * normalized + 0.5))
end

local function SyncOptionsWindow()
	if not optionsFrame then
		return
	end

	local db = GetDatabase()

	optionsFrame.sizeSlider.__ProkinSyncing = true
	optionsFrame.sizeSlider:SetValue(db.size)
	optionsFrame.sizeSlider.__ProkinSyncing = nil
	optionsFrame.sizeSlider.valueText:SetText(string.format('%d', db.size))

	optionsFrame.showAddonButton:SetChecked(db.showAddonButton ~= false)
	optionsFrame.showServerTime:SetChecked(db.showServerTime ~= false)
	optionsFrame.showMinimapBorder:SetChecked(db.showMinimapBorder ~= false)
	optionsFrame.showLoadAnnouncement:SetChecked(db.showLoadAnnouncement ~= false)
end

local function ApplyOptionChange(callback)
	if callback then
		callback(GetDatabase())
	end

	RefreshMinimap()
	SyncOptionsWindow()
end

local function EnsureOptionsWindow()
	if optionsFrame then
		return
	end

	local frame = CreateFrame('Frame', 'ProkinMinimapOptionsFrame', _G.UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
	frame:SetSize(440, 470)
	frame:SetPoint('CENTER')
	frame:SetFrameStrata('DIALOG')
	frame:SetFrameLevel(200)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag('LeftButton')
	frame:SetClampedToScreen(true)
	frame:SetScript('OnDragStart', frame.StartMoving)
	frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
	frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	frame:Hide()

	frame.title = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightLarge')
	frame.title:SetPoint('TOPLEFT', frame, 'TOPLEFT', 16, -16)
	frame.title:SetText('Prokin Minimap Options')

	frame.subtitle = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	frame.subtitle:SetPoint('TOPLEFT', frame.title, 'BOTTOMLEFT', 0, -8)
	frame.subtitle:SetWidth(392)
	frame.subtitle:SetJustifyH('LEFT')
	frame.subtitle:SetText('Configure the minimap, addon button, and announcement behavior.')

	frame.closeButton = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
	frame.closeButton:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -4, -4)

	frame.sizeLabel = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	frame.sizeLabel:SetPoint('TOPLEFT', frame.subtitle, 'BOTTOMLEFT', 0, -18)
	frame.sizeLabel:SetText('Minimap Size')

	frame.sizeSliderBackground = CreateFrame('Frame', nil, frame, BackdropTemplateMixin and 'BackdropTemplate' or nil)
	frame.sizeSliderBackground:SetPoint('TOPLEFT', frame.sizeLabel, 'BOTTOMLEFT', -4, -10)
	frame.sizeSliderBackground:SetSize(396, 86)
	frame.sizeSliderBackground:SetBackdrop({
		bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	frame.sizeSliderBackground:SetBackdropColor(0.02, 0.02, 0.02, 0.8)
	frame.sizeSliderBackground:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

	local sizeSlider = CreateFrame('Slider', 'ProkinMinimapOptionsSizeSlider', frame, BackdropTemplateMixin and 'BackdropTemplate' or nil)
	sizeSlider:SetOrientation('HORIZONTAL')
	sizeSlider:SetPoint('TOPLEFT', frame.sizeSliderBackground, 'TOPLEFT', 18, -22)
	sizeSlider:SetWidth(250)
	sizeSlider:SetHeight(15)
	sizeSlider:SetHitRectInsets(0, 0, -10, 0)
	sizeSlider:SetBackdrop(OPTION_SLIDER_BACKDROP)
	sizeSlider:SetThumbTexture([[Interface\Buttons\UI-SliderBar-Button-Horizontal]])
	sizeSlider:SetMinMaxValues(MIN_SIZE, MAX_SIZE)
	sizeSlider:SetValueStep(10)
	if sizeSlider.SetObeyStepOnDrag then
		sizeSlider:SetObeyStepOnDrag(true)
	end

	sizeSlider.fill = sizeSlider:CreateTexture(nil, 'BACKGROUND')
	sizeSlider.fill:SetColorTexture(0.85, 0.72, 0.12, 1)
	sizeSlider.fill:SetPoint('LEFT', sizeSlider, 'LEFT', 3, 0)
	sizeSlider.fill:SetHeight(9)

	sizeSlider.lowText = frame:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
	sizeSlider.lowText:SetPoint('TOPLEFT', sizeSlider, 'BOTTOMLEFT', 2, 3)
	sizeSlider.lowText:SetText(tostring(MIN_SIZE))

	sizeSlider.highText = frame:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
	sizeSlider.highText:SetPoint('TOPRIGHT', sizeSlider, 'BOTTOMRIGHT', -2, 3)
	sizeSlider.highText:SetText(tostring(MAX_SIZE))

	sizeSlider.valueText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	sizeSlider.valueText:SetPoint('LEFT', sizeSlider, 'RIGHT', 24, 0)

	sizeSlider:SetScript('OnValueChanged', function(self, value)
		local normalized = NormalizeSize(value)
		UpdateOptionsSliderVisuals(self, normalized)
		if self.__ProkinSyncing then
			self.valueText:SetText(string.format('%d', normalized))
			return
		end

		if math.abs((self:GetValue() or 0) - normalized) > 0.01 then
			self.__ProkinSyncing = true
			self:SetValue(normalized)
			self.__ProkinSyncing = nil
		end

		self.valueText:SetText(string.format('%d', normalized))
		SetMinimapSize(normalized)
	end)

	local thumb = sizeSlider.GetThumbTexture and sizeSlider:GetThumbTexture()
	if thumb and thumb.SetVertexColor then
		thumb:SetVertexColor(1, 1, 1, 1)
	end

	frame.sizeSlider = sizeSlider

	frame.resetSizeButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	frame.resetSizeButton:SetSize(132, 22)
	frame.resetSizeButton:SetPoint('TOPLEFT', frame.sizeSliderBackground, 'BOTTOMLEFT', 0, -14)
	frame.resetSizeButton:SetText('Reset Size')
	frame.resetSizeButton:SetScript('OnClick', function()
		SetMinimapSize(DEFAULT_SIZE)
		SyncOptionsWindow()
	end)

	frame.resetButtonButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	frame.resetButtonButton:SetSize(174, 22)
	frame.resetButtonButton:SetPoint('LEFT', frame.resetSizeButton, 'RIGHT', 12, 0)
	frame.resetButtonButton:SetText('Reset Button Position')
	frame.resetButtonButton:SetScript('OnClick', function()
		SetAddonButtonAngle(ADDON_BUTTON_DEFAULT_ANGLE)
		UpdateAddonButtonVisibility()
	end)

	frame.showAddonButton = CreateOptionsCheckbox(frame, 'Show Prokin minimap button', 'Show or hide the Prokin minimap button around the square minimap border.')
	frame.showAddonButton:SetPoint('TOPLEFT', frame.resetSizeButton, 'BOTTOMLEFT', 0, -18)
	frame.showAddonButton:SetScript('OnClick', function(self)
		ApplyOptionChange(function(db)
			db.showAddonButton = self:GetChecked() and true or false
		end)
	end)

	frame.showServerTime = CreateOptionsCheckbox(frame, 'Show server time in the zone label', 'Append the server time to the custom zone text shown above the minimap.')
	frame.showServerTime:SetPoint('TOPLEFT', frame.showAddonButton, 'BOTTOMLEFT', 0, -12)
	frame.showServerTime:SetScript('OnClick', function(self)
		ApplyOptionChange(function(db)
			db.showServerTime = self:GetChecked() and true or false
		end)
	end)

	frame.showMinimapBorder = CreateOptionsCheckbox(frame, 'Show the 1px minimap border', 'Show or hide the custom black border drawn around the square minimap.')
	frame.showMinimapBorder:SetPoint('TOPLEFT', frame.showServerTime, 'BOTTOMLEFT', 0, -12)
	frame.showMinimapBorder:SetScript('OnClick', function(self)
		ApplyOptionChange(function(db)
			db.showMinimapBorder = self:GetChecked() and true or false
		end)
	end)

	frame.showLoadAnnouncement = CreateOptionsCheckbox(frame, 'Show the load announcement after /reload', 'Control whether Prokin Minimap announces itself in chat after loading or reloading the UI.')
	frame.showLoadAnnouncement:SetPoint('TOPLEFT', frame.showMinimapBorder, 'BOTTOMLEFT', 0, -12)
	frame.showLoadAnnouncement:SetScript('OnClick', function(self)
		local enabled = self:GetChecked() and true or false
		ApplyOptionChange(function(db)
			db.showLoadAnnouncement = enabled
		end)
		if not enabled then
			loadAnnouncementPending = nil
		end
	end)

	frame.helpText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	frame.helpText:SetPoint('TOPLEFT', frame.showLoadAnnouncement, 'BOTTOMLEFT', 4, -18)
	frame.helpText:SetWidth(392)
	frame.helpText:SetJustifyH('LEFT')
	frame.helpText:SetText('Button controls: Left-click starts a role check, right-click opens these options, and Alt-Left-Drag repositions the button.')
	frame.helpText:SetHeight(36)

	frame:SetScript('OnShow', SyncOptionsWindow)
	optionsFrame = frame
end

OpenOptionsWindow = function()
	EnsureOptionsWindow()
	SyncOptionsWindow()
	optionsFrame:Show()
	optionsFrame:Raise()
end

local function ShowHelp()
	Print(string.format('Current size: %dx%d. Use /pkm size <number>, /pkm larger [step], /pkm smaller [step], /pkm reset, /pkm options, or /pkm trackingdebug [on|off].', GetDatabase().size, GetDatabase().size))
end

local function HandleSlashCommand(message)
	local command, remainder = string.match(message or '', '^(%S*)%s*(.-)%s*$')
	command = string.lower(command or '')

	if command == '' then
		ShowHelp()
		return
	end

	if command == 'size' then
		local size = SetMinimapSize(remainder)
		if not size then
			Print('Enter a size between 100 and 800, for example: /pkm size 400')
			return
		end

		Print(string.format('Minimap size set to %dx%d.', size, size))
		return
	end

	if command == 'larger' or command == 'bigger' or command == 'increase' then
		local size = SetMinimapSize(GetDatabase().size + NormalizeStep(remainder))
		Print(string.format('Minimap size set to %dx%d.', size, size))
		return
	end

	if command == 'smaller' or command == 'decrease' then
		local size = SetMinimapSize(GetDatabase().size - NormalizeStep(remainder))
		Print(string.format('Minimap size set to %dx%d.', size, size))
		return
	end

	if command == 'reset' or command == 'default' then
		local size = SetMinimapSize(DEFAULT_SIZE)
		Print(string.format('Minimap size reset to %dx%d.', size, size))
		return
	end

	if command == 'options' or command == 'config' then
		OpenOptionsWindow()
		return
	end

	if command == 'trackingdebug' then
		local state = string.lower(remainder or '')
		if state == 'off' or state == 'disable' or state == 'disabled' then
			GetDatabase().debugTracking = false
		elseif state == 'on' or state == 'enable' or state == 'enabled' then
			GetDatabase().debugTracking = true
		else
			GetDatabase().debugTracking = not GetDatabase().debugTracking
		end
		GetDatabase().debugTrackingConfigured = true

		Print(string.format('Tracking debug is now %s.', GetDatabase().debugTracking and 'enabled' or 'disabled'))
		return
	end

	ShowHelp()
end

SLASH_PROKINMINIMAP1 = '/prokinminimap'
SLASH_PROKINMINIMAP2 = '/pkm'
SlashCmdList.PROKINMINIMAP = HandleSlashCommand

local function InstallHooks()
	if hooksInstalled then
		return
	end

	if Minimap then
		if Minimap.EnableMouseWheel then
			Minimap:EnableMouseWheel(true)
		end

		Minimap:SetScript('OnMouseWheel', HandleMinimapMouseWheel)
	end

	if Minimap and Minimap.HookScript then
		Minimap:HookScript('OnShow', RefreshMinimap)
	end

	if Minimap then
		hooksecurefunc(Minimap, 'SetPoint', ApplyZoneLayout)
	end

	if _G.MinimapZoneTextButton then
		if _G.MinimapZoneTextButton.SetPoint then
			hooksecurefunc(_G.MinimapZoneTextButton, 'SetPoint', ApplyZoneLayout)
		end
		if _G.MinimapZoneTextButton.HookScript then
			_G.MinimapZoneTextButton:HookScript('OnShow', HideDefaultZoneHeader)
		end
	end

	if _G.MiniMapWorldMapButton and _G.MiniMapWorldMapButton.HookScript then
		_G.MiniMapWorldMapButton:HookScript('OnShow', HideDefaultZoneHeader)
	end

	if _G.MinimapCluster then
		if _G.MinimapCluster.ZoneTextButton and _G.MinimapCluster.ZoneTextButton.HookScript then
			_G.MinimapCluster.ZoneTextButton:HookScript('OnShow', HideDefaultZoneHeader)
		end

		if _G.MinimapCluster.BorderTop and _G.MinimapCluster.BorderTop.HookScript then
			_G.MinimapCluster.BorderTop:HookScript('OnShow', HideDefaultZoneHeader)
		end
	end

	if type(SetLookingForGroupUIAvailable) == 'function' then
		hooksecurefunc('SetLookingForGroupUIAvailable', HideDefaultZoneHeader)
		hooksecurefunc('SetLookingForGroupUIAvailable', ApplyBlizzardWidgetLayout)
	end

	EnsureMinimapButtonButtonBlacklist()
	ApplyBlizzardWidgetLayout()
	InstallAutoMarkAssistCompatibility()

	for _, event in ipairs({
		'MAIL_INBOX_UPDATE',
		'UPDATE_PENDING_MAIL',
		'ZONE_CHANGED',
		'ZONE_CHANGED_INDOORS',
		'ZONE_CHANGED_NEW_AREA'
	}) do
		eventFrame:RegisterEvent(event)
	end
end

eventFrame = CreateFrame('Frame')
eventFrame:RegisterEvent('ADDON_LOADED')
eventFrame:RegisterEvent('PLAYER_LOGIN')
eventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
eventFrame:SetScript('OnEvent', function(_, event, arg1)
	if event == 'ADDON_LOADED' then
		if arg1 == ADDON_NAME then
			GetDatabase()
			InstallHooks()
			loadAnnouncementPending = true
			loadAnnouncementDelay = 0
		elseif arg1 == HYBRID_MINIMAP_ADDON then
			ApplyHybridMinimap()
		elseif arg1 == MINIMAPBUTTONBUTTON_ADDON then
			EnsureMinimapButtonButtonBlacklist()
			ApplyBlizzardWidgetLayout()
		elseif arg1 == TIME_MANAGER_ADDON then
			ApplyBlizzardWidgetLayout()
		elseif arg1 == AUTOMARKASSIST_ADDON then
			InstallAutoMarkAssistCompatibility()
		else
			return
		end
	elseif event == 'MAIL_INBOX_UPDATE' or event == 'UPDATE_PENDING_MAIL' then
		ApplyBlizzardWidgetLayout()
	elseif event == 'PLAYER_LOGIN' then
		InstallHooks()
	elseif event == 'PLAYER_REGEN_ENABLED' then
		if minimapRefreshPending then
			RefreshMinimap()
		end
		return
	end

	if event == 'PLAYER_LOGIN' or event == 'PLAYER_ENTERING_WORLD' then
		loadAnnouncementDelay = 2
	end

	RefreshMinimap()
end)
eventFrame:SetScript('OnUpdate', function(_, elapsed)
	UpdateWidgetDrag()
	UpdateAddonButtonDrag()

	if loadAnnouncementPending then
		loadAnnouncementDelay = math.max((loadAnnouncementDelay or 0) - elapsed, 0)
		TryShowLoadAnnouncement()
	end

	mailVisibilityElapsed = mailVisibilityElapsed + elapsed
	if mailVisibilityElapsed >= 1 then
		mailVisibilityElapsed = 0
		RefreshMailVisibility()
	end

	zoneTimeElapsed = zoneTimeElapsed + elapsed
	if zoneTimeElapsed < 1 then
		return
	end

	zoneTimeElapsed = 0

	local timeSuffix = GetServerTimeSuffix()
	if timeSuffix ~= lastZoneTimeSuffix then
		UpdateZoneHeaderText()
	end

	ApplyBlizzardWidgetLayout()
end)
