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
local PLAYER_COORDS_OFFSET = 4
local MIN_ZONE_TEXT_SIZE = 8
local MAX_ZONE_TEXT_SIZE = 32
local ALIGNED_BUTTON = { SIZE = 31, SPACING = 36, MIN_SPACING = 26, MAX_SPACING = 64, BORDER_SIZE = 50, BACKGROUND_SIZE = 24, ICON_SIZE = 18 }
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
local INTERFACE_VERSION = select(4, GetBuildInfo()) or 0
-- Forever is 1.60+ (TOC 16001). Classic Era is also 1.x, but stays below 16000.
local IS_FOREVER = INTERFACE_VERSION >= 16000 and INTERFACE_VERSION < 20000
local FOREVER_TRACKING_ATLAS = 'ui-hud-minimap-tracking-button'
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
local zoneTextFont
local zoneTextFlags
local zoneTextDefaultSize
local appliedZoneTextSize
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

-- Secret values (Forever) cannot be compared, tested, or used as table keys by addon code.
local function IsSecret(value)
	return type(issecretvalue) == 'function' and issecretvalue(value)
end

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

local function NormalizeZoneTextSize(size)
	size = tonumber(size)
	if not size then
		return nil
	end

	size = math.floor(size + 0.5)
	return math.max(MIN_ZONE_TEXT_SIZE, math.min(size, MAX_ZONE_TEXT_SIZE))
end

GetDatabase = function()
	if type(ProkinMinimapDB) ~= 'table' then
		ProkinMinimapDB = {}
	end

	ProkinMinimapDB.size = NormalizeSize(ProkinMinimapDB.size) or DEFAULT_SIZE
	if type(ProkinMinimapDB.widgetPositions) ~= 'table' then
		ProkinMinimapDB.widgetPositions = {}
	end
	if type(ProkinMinimapDB.goldTracker) ~= 'table' then
		ProkinMinimapDB.goldTracker = {}
	end
	if type(ProkinMinimapDB.goldTracker.goldTrackingEnabled) ~= 'boolean' then
		ProkinMinimapDB.goldTracker.goldTrackingEnabled = true
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
	if type(ProkinMinimapDB.alignAddonButtons) ~= 'boolean' then
		ProkinMinimapDB.alignAddonButtons = true
	end
	ProkinMinimapDB.zoneTextSize = NormalizeZoneTextSize(ProkinMinimapDB.zoneTextSize)
	local addonButtonSpacing = math.floor((tonumber(ProkinMinimapDB.addonButtonSpacing) or ALIGNED_BUTTON.SPACING) + 0.5)
	ProkinMinimapDB.addonButtonSpacing = math.max(ALIGNED_BUTTON.MIN_SPACING, math.min(addonButtonSpacing, ALIGNED_BUTTON.MAX_SPACING))
	local buffFramePosition = ProkinMinimapDB.buffFramePosition
	if type(buffFramePosition) ~= 'table' or type(buffFramePosition.x) ~= 'number' or type(buffFramePosition.y) ~= 'number' then
		ProkinMinimapDB.buffFramePosition = nil
	end
	local dayNightPosition = ProkinMinimapDB.dayNightPosition
	if type(dayNightPosition) ~= 'table' or type(dayNightPosition.x) ~= 'number' or type(dayNightPosition.y) ~= 'number' then
		ProkinMinimapDB.dayNightPosition = nil
	end
	return ProkinMinimapDB
end

-- Forever anchors the zoom buttons at fixed offsets for its 198px round minimap,
-- which would strand them in the middle of a resized square map.
local function ApplyForeverZoomLayout()
	if not IS_FOREVER or not Minimap.ZoomIn or not Minimap.ZoomOut or not Minimap.ZoomHitArea then
		return
	end

	Minimap.ZoomHitArea:ClearAllPoints()
	Minimap.ZoomHitArea:SetPoint('BOTTOMRIGHT', Minimap, 'BOTTOMRIGHT', 0, 0)
	Minimap.ZoomOut:ClearAllPoints()
	Minimap.ZoomOut:SetPoint('BOTTOMRIGHT', Minimap, 'BOTTOMRIGHT', -4, 4)
	Minimap.ZoomIn:ClearAllPoints()
	Minimap.ZoomIn:SetPoint('BOTTOMRIGHT', Minimap, 'BOTTOMRIGHT', -4, 15)
end

-- Blizzard leaves the coordinates 18px below the map with their top edge floating,
-- so pin them directly under the bottom border and centered on the map.
local function ApplyPlayerCoordsLayout()
	local cluster = _G.MinimapCluster
	local container = cluster and cluster.MinimapContainer
	local coords = container and container.PlayerCoords
	if not coords then
		return
	end

	coords:ClearAllPoints()
	coords:SetPoint('TOP', Minimap, 'BOTTOM', 0, -PLAYER_COORDS_OFFSET)
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

	ApplyForeverZoomLayout()
	ApplyPlayerCoordsLayout()
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

	zoneTextFont, zoneTextDefaultSize, zoneTextFlags = zoneHeaderText:GetFont()
end

local function GetZoneTextSize()
	EnsureCustomZoneHeader()
	return GetDatabase().zoneTextSize or NormalizeZoneTextSize(zoneTextDefaultSize) or 12
end

local function ApplyZoneTextSize()
	if not zoneHeaderText or not zoneTextFont then
		return
	end

	local size = GetZoneTextSize()
	if size ~= appliedZoneTextSize then
		zoneHeaderText:SetFont(zoneTextFont, size, zoneTextFlags or '')
		appliedZoneTextSize = size
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

	ApplyZoneTextSize()

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

		-- Must run first: clearing the mask while masking is on calls AddMaskTexture(nil),
		-- and SetUseMaskTexture raises an error once no mask is set.
		if mapCanvas.SetUseMaskTexture and mapCanvas.GetMaskTexture and mapCanvas:GetMaskTexture() then
			mapCanvas:SetUseMaskTexture(false)
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

local function KeepFrameHidden(frame)
	if not frame then
		return
	end

	if frame.Hide then
		frame:Hide()
	end

	if not frame.__ProkinHideHooked and frame.HookScript then
		frame:HookScript('OnShow', function(self)
			self:Hide()
		end)
		frame.__ProkinHideHooked = true
	end
end

-- The zone label already shows the time, so neither Blizzard clock is displayed.
local function HideBlizzardClocks()
	KeepFrameHidden(_G.GameTimeFrame)
	KeepFrameHidden(_G.TimeManagerClockButton)
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

	if mail.__ProkinMailVisibilityUpdating then
		return
	end

	mail.__ProkinMailVisibilityUpdating = true

	if HasNewMail and HasNewMail() then
		if mail.SetAlpha then
			mail:SetAlpha(1)
		end

		if mail.Show and not mail:IsShown() then
			mail:Show()
		end

		-- Forever hides this icon whenever the frame hides and only restores it from
		-- UPDATE_PENDING_MAIL, so re-showing the frame alone would leave it invisible.
		if mail.MailIcon and mail.MailIcon.Show then
			mail.MailIcon:Show()
		end
	elseif mail.Hide and mail:IsShown() then
		mail:Hide()
	end

	mail.__ProkinMailVisibilityUpdating = nil
end

local function GetLFGFrame()
	return _G.QueueStatusMinimapButton or _G.QueueStatusButton or _G.MiniMapLFGFrame or _G.LFGMinimapFrame
end

local function GetBattlefieldFrame()
	return _G.MiniMapBattlefieldFrame
end

local function GetAssignedRole(unit)
	local role = type(UnitGroupRolesAssigned) == 'function' and UnitGroupRolesAssigned(unit) or nil
	if IsSecret(role) then
		return 'NONE'
	end

	if role == nil or role == '' then
		role = 'NONE'
	end

	local isMainTank = type(GetPartyAssignment) == 'function' and GetPartyAssignment('MAINTANK', unit, true)
	if role == 'NONE' and not IsSecret(isMainTank) and isMainTank then
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
	local name
	if type(GetUnitName) == 'function' then
		name = GetUnitName(unit, true)
	else
		name = UnitName(unit)
	end

	if IsSecret(name) then
		return name
	end

	return name or UNKNOWN
end

local function AddRoleTooltipLine(tooltip, unit)
	if not tooltip or not unit or not UnitExists(unit) then
		return
	end

	local name = GetUnitDisplayName(unit)
	local classToken = select(2, UnitClass(unit))
	local classColor = NORMAL_FONT_COLOR
	if not IsSecret(classToken) then
		classColor = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classToken]) or RAID_CLASS_COLORS[classToken] or NORMAL_FONT_COLOR
	end
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

local function AddGoldTrackerTooltipLine(tooltip)
	if not tooltip then
		return
	end

	local tracker = _G.ProkinMinimapGoldTracker
	if not tracker then
		return
	end

	local lines = type(tracker.GetTooltipLines) == 'function' and tracker:GetTooltipLines() or nil
	if type(lines) == 'table' then
		if #lines == 0 then
			return
		end

		tooltip:AddLine(' ')
		for _, line in ipairs(lines) do
			tooltip:AddLine(line, 1, 0.82, 0)
		end
		return
	end

	if type(tracker.GetTooltipLine) ~= 'function' then
		return
	end

	local line = tracker:GetTooltipLine()
	if not line then
		return
	end

	tooltip:AddLine(' ')
	tooltip:AddLine(line, 1, 0.82, 0)
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
		return coord * horizontalRange, -outsideY
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

	local offsetX = button.__ProkinIconCentered and 0 or PROXY_ICON_OFFSET_X
	local offsetY = button.__ProkinIconCentered and 0 or PROXY_ICON_OFFSET_Y

	button.icon:ClearAllPoints()
	if pressed then
		button.icon:SetPoint('CENTER', button, 'CENTER', offsetX + 1, offsetY - 1)
		button.overlay:Show()
	else
		button.icon:SetPoint('CENTER', button, 'CENTER', offsetX, offsetY)
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
		GameTooltip:SetText(TRACKING or 'Tracking', 1, 1, 1)
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

local function GetTrackingTypeCount()
	if type(C_Minimap) == 'table' and C_Minimap.GetNumTrackingTypes then
		return C_Minimap.GetNumTrackingTypes() or 0
	end

	return GetNumTrackingTypes and GetNumTrackingTypes() or 0
end

-- Returns texture, active, category, spellID. C_Minimap returns a table on Forever,
-- while older clients return separate values.
local function GetTrackingDetails(id)
	local name, texture, active, category
	if type(C_Minimap) == 'table' and C_Minimap.GetTrackingInfo then
		name, texture, active, category = C_Minimap.GetTrackingInfo(id)
	elseif GetTrackingInfo then
		name, texture, active, category = GetTrackingInfo(id)
	end

	if type(name) == 'table' then
		return name.texture, name.active, name.type, name.spellID
	end

	return texture, active, category
end

local function UpdateTrackingProxy()
	EnsureTrackingProxy()
	if not trackingProxyButton then
		return
	end

	local texturePath = [[Interface\Minimap\Tracking\None]]
	local left, right, top, bottom = 0, 1, 0, 1
	local hasActiveTracking

	for id = 1, GetTrackingTypeCount() do
		local texture, active, category, spellID = GetTrackingDetails(id)
		-- Forever keeps always-on filters such as quest POIs active, so only a tracking
		-- spell should replace the default icon there.
		if active and (not IS_FOREVER or category == 'spell' or spellID) then
			hasActiveTracking = true
			texturePath = texture or texturePath
			if category == 'spell' or spellID then
				left, right, top, bottom = 0.0625, 0.9, 0.0625, 0.9
			end
			break
		end
	end

	if IS_FOREVER and not hasActiveTracking and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(FOREVER_TRACKING_ATLAS) then
		trackingProxyButton.icon:SetAtlas(FOREVER_TRACKING_ATLAS)
		return
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

-- Forever anchors its day/night indicator to the center of the minimap container, so it
-- floats inside a resized map. Blizzard also re-anchors it whenever the Edit Mode scale
-- changes, so ApplyLayout runs with the regular widget layout. The frame deliberately keeps
-- its own inverse scale, so offsets are converted from Minimap units. The default Y offset
-- leaves room for the addon compartment above it.
local DayNightIndicator = { OFFSET_X = -2, OFFSET_Y = -28, BORDER_ATLAS = 'UI-HUD-Minimap-Frame-Cycle' }

function DayNightIndicator.GetFrame()
	local cluster = _G.MinimapCluster
	return cluster and cluster.DielFrame
end

-- Matches the aligned addon icons. Blizzard resets the moon or sun texture to its full atlas
-- size each time the day/night cycle changes, so this is also hooked to its OnEvent.
function DayNightIndicator.ApplySize()
	local indicator = DayNightIndicator.GetFrame()
	if not indicator or GetDatabase().alignAddonButtons == false or not C_Texture or not C_Texture.GetAtlasInfo then
		return
	end

	local borderInfo = C_Texture.GetAtlasInfo(DayNightIndicator.BORDER_ATLAS)
	if not borderInfo or not borderInfo.width or borderInfo.width <= 0 then
		return
	end

	local scaleRatio = Minimap:GetEffectiveScale() / indicator:GetEffectiveScale()
	local fraction = (ALIGNED_BUTTON.SIZE * scaleRatio) / borderInfo.width
	indicator:SetSize(borderInfo.width * fraction, borderInfo.height * fraction)

	local background = indicator.Background
	local backgroundAtlas = background and background.GetAtlas and background:GetAtlas()
	local backgroundInfo = backgroundAtlas and C_Texture.GetAtlasInfo(backgroundAtlas)
	if backgroundInfo then
		background:SetSize(backgroundInfo.width * fraction, backgroundInfo.height * fraction)
	end
end

function DayNightIndicator.ApplyLayout()
	local indicator = DayNightIndicator.GetFrame()
	if not indicator then
		return
	end

	DayNightIndicator.ApplySize()

	-- Blizzard's frame level can leave it under the Minimap for mouse input.
	indicator:SetFrameLevel(Minimap:GetFrameLevel() + 5)

	-- While aligned, ApplyAddonButtonLayout places it in the icon column instead.
	if GetDatabase().alignAddonButtons ~= false then
		return
	end

	indicator:RegisterForDrag('LeftButton')

	local scaleRatio = Minimap:GetEffectiveScale() / indicator:GetEffectiveScale()
	local position = GetDatabase().dayNightPosition
	indicator:ClearAllPoints()
	if position then
		-- Saved as a fraction of the map's half-size so it follows minimap resizing.
		indicator:SetPoint(
			'CENTER',
			Minimap,
			'CENTER',
			position.x * Minimap:GetWidth() * 0.5 * scaleRatio,
			position.y * Minimap:GetHeight() * 0.5 * scaleRatio
		)
	else
		indicator:SetPoint('TOPRIGHT', Minimap, 'TOPRIGHT', DayNightIndicator.OFFSET_X * scaleRatio, DayNightIndicator.OFFSET_Y * scaleRatio)
	end
end

function DayNightIndicator.UpdateDrag()
	if not DayNightIndicator.dragging then
		return
	end

	local scale = Minimap:GetEffectiveScale() or 1
	local cursorX, cursorY = GetCursorPosition()
	local centerX, centerY = Minimap:GetCenter()
	if not centerX or not centerY then
		return
	end

	GetDatabase().dayNightPosition = {
		x = ClampWidgetCoord(((cursorX / scale) - centerX) / (Minimap:GetWidth() * 0.5)),
		y = ClampWidgetCoord(((cursorY / scale) - centerY) / (Minimap:GetHeight() * 0.5))
	}
	DayNightIndicator.ApplyLayout()
end

function DayNightIndicator.EnableDragging()
	local indicator = DayNightIndicator.GetFrame()
	if not indicator or indicator.__ProkinDragEnabled then
		return
	end

	indicator.__ProkinDragEnabled = true
	indicator:EnableMouse(true)
	indicator:RegisterForDrag('LeftButton')
	indicator:HookScript('OnDragStart', function()
		DayNightIndicator.dragging = true
		GameTooltip_Hide()
	end)
	indicator:HookScript('OnDragStop', function()
		DayNightIndicator.UpdateDrag()
		DayNightIndicator.dragging = nil
	end)
	indicator:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
		GameTooltip:AddLine('Day/Night', 1, 1, 1)
		if GetDatabase().alignAddonButtons == false then
			GameTooltip:AddLine('Left-Drag: Move icon', 0.85, 0.85, 0.85)
			GameTooltip:AddLine('/pkm resetmoon: Restore position', 0.85, 0.85, 0.85)
		end
		GameTooltip:Show()
	end)
	indicator:HookScript('OnLeave', GameTooltip_Hide)
	indicator:HookScript('OnEvent', DayNightIndicator.ApplySize)
end

-- Moves Blizzard's buff icons with a drag handle. Nothing here touches the frames until the
-- player has saved a position. Forever's buff and debuff frames are separate Edit Mode systems,
-- so debuffs are anchored under the buffs to keep them from being left on the map. The Base
-- methods skip Edit Mode's snap tracking, which addon code should not disturb.
local BuffIcons = { MIN_WIDTH = 200, MIN_HEIGHT = 40 }

function BuffIcons.CanMove()
	if type(InCombatLockdown) == 'function' and InCombatLockdown() then
		return false
	end

	local editMode = _G.EditModeManagerFrame
	return not (editMode and editMode.IsEditModeActive and editMode:IsEditModeActive())
end

function BuffIcons.Anchor(frame, point, relativeTo, relativePoint, x, y)
	local clearAllPoints = frame.ClearAllPointsBase or frame.ClearAllPoints
	local setPoint = frame.SetPointBase or frame.SetPoint
	clearAllPoints(frame)
	setPoint(frame, point, relativeTo, relativePoint, x, y)
end

function BuffIcons.ApplyLayout()
	local buffs = _G.BuffFrame
	local position = GetDatabase().buffFramePosition
	if not buffs or not position or not BuffIcons.CanMove() then
		return
	end

	local scaleRatio = _G.UIParent:GetEffectiveScale() / buffs:GetEffectiveScale()
	BuffIcons.Anchor(buffs, 'TOPRIGHT', _G.UIParent, 'TOPRIGHT', position.x * scaleRatio, position.y * scaleRatio)

	if _G.DebuffFrame then
		BuffIcons.Anchor(_G.DebuffFrame, 'TOPRIGHT', buffs, 'BOTTOMRIGHT', -13, -5)
	end
end

function BuffIcons.UpdateMoverSize()
	local mover, buffs = BuffIcons.mover, _G.BuffFrame
	if mover and buffs then
		mover:SetSize(
			math.max(buffs:GetWidth() or 0, BuffIcons.MIN_WIDTH),
			math.max(buffs:GetHeight() or 0, BuffIcons.MIN_HEIGHT)
		)
	end
end

-- Positions are saved as the frame's top-right corner, in UIParent units from the screen's
-- top-right corner, and kept on screen.
function BuffIcons.UpdateDrag()
	local grab = BuffIcons.grab
	if not grab then
		return
	end

	local scale = _G.UIParent:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	local width, height = _G.UIParent:GetWidth(), _G.UIParent:GetHeight()
	GetDatabase().buffFramePosition = {
		x = math.max(-width, math.min((cursorX / scale) - grab.x - width, 0)),
		y = math.max(-height, math.min((cursorY / scale) - grab.y - height, 0))
	}
	BuffIcons.ApplyLayout()
end

function BuffIcons.StartDrag()
	local buffs = _G.BuffFrame
	local right, top = buffs and buffs:GetRight(), buffs and buffs:GetTop()
	if not right or not top then
		return
	end

	local scale = _G.UIParent:GetEffectiveScale()
	local frameScale = buffs:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	BuffIcons.grab = {
		x = (cursorX / scale) - (right * frameScale / scale),
		y = (cursorY / scale) - (top * frameScale / scale)
	}
end

function BuffIcons.EnsureMover()
	if BuffIcons.mover or not _G.BuffFrame then
		return BuffIcons.mover
	end

	local mover = CreateFrame('Frame', 'ProkinMinimapBuffMover', _G.UIParent)
	mover:SetFrameStrata('HIGH')
	mover:SetPoint('TOPRIGHT', _G.BuffFrame, 'TOPRIGHT', 0, 0)
	mover:EnableMouse(true)
	mover:RegisterForDrag('LeftButton')
	mover:SetClampedToScreen(true)
	mover:Hide()

	mover.background = mover:CreateTexture(nil, 'BACKGROUND')
	mover.background:SetAllPoints(mover)
	mover.background:SetColorTexture(0.1, 0.5, 0.9, 0.45)

	mover.label = mover:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	mover.label:SetPoint('CENTER', mover, 'CENTER', 0, 0)
	mover.label:SetText('Buff Icons: drag to move')

	mover:SetScript('OnDragStart', BuffIcons.StartDrag)
	mover:SetScript('OnDragStop', function()
		BuffIcons.UpdateDrag()
		BuffIcons.grab = nil
	end)
	mover:SetScript('OnHide', function()
		BuffIcons.grab = nil
	end)

	BuffIcons.mover = mover
	return mover
end

function BuffIcons.SetUnlocked(unlocked)
	local mover = BuffIcons.EnsureMover()
	if not mover then
		return false
	end

	BuffIcons.UpdateMoverSize()
	mover:SetShown(unlocked)
	return true
end

function BuffIcons.IsUnlocked()
	return BuffIcons.mover ~= nil and BuffIcons.mover:IsShown()
end

function BuffIcons.Reset()
	GetDatabase().buffFramePosition = nil
	BuffIcons.SetUnlocked(false)
	Print('Buff icon position cleared. Type /reload to return them to Blizzard\'s position.')
end

local function IsAddonButtonAlignmentEnabled()
	return GetDatabase().alignAddonButtons ~= false
end

-- Addons embed different LibDBIcon versions, and buttons built by older ones use other
-- sizes and offsets. Older versions also keep their border and background in unnamed
-- textures, so those have to be found by draw layer.
local NormalizeAddonButton
do
	local function FindTextureInLayer(button, drawLayer)
		for _, region in ipairs({ button:GetRegions() }) do
			if region:GetObjectType() == 'Texture' and region:GetDrawLayer() == drawLayer then
				return region
			end
		end
	end

	NormalizeAddonButton = function(button)
		button.__ProkinIconCentered = true
		button:SetScale(1)
		button:SetSize(ALIGNED_BUTTON.SIZE, ALIGNED_BUTTON.SIZE)

		local border = button.border or FindTextureInLayer(button, 'OVERLAY')
		if border then
			border:ClearAllPoints()
			border:SetPoint('TOPLEFT', button, 'TOPLEFT', 0, 0)
			border:SetSize(ALIGNED_BUTTON.BORDER_SIZE, ALIGNED_BUTTON.BORDER_SIZE)
		end

		local background = button.background or FindTextureInLayer(button, 'BACKGROUND')
		if background then
			background:ClearAllPoints()
			background:SetPoint('CENTER', button, 'CENTER', 0, 0)
			background:SetSize(ALIGNED_BUTTON.BACKGROUND_SIZE, ALIGNED_BUTTON.BACKGROUND_SIZE)
		end

		if button.icon then
			button.icon:ClearAllPoints()
			button.icon:SetPoint('CENTER', button, 'CENTER', 0, 0)
			button.icon:SetSize(ALIGNED_BUTTON.ICON_SIZE, ALIGNED_BUTTON.ICON_SIZE)
		end
	end
end

local function ApplyAddonButtonLayout()
	if not Minimap or not IsAddonButtonAlignmentEnabled() then
		return
	end

	local entries = {}
	if addonMinimapButton then
		table.insert(entries, { key = '', button = addonMinimapButton })
	end

	local libDBIcon = _G.LibStub and _G.LibStub('LibDBIcon-1.0', true)
	if libDBIcon and type(libDBIcon.objects) == 'table' then
		for name, button in pairs(libDBIcon.objects) do
			table.insert(entries, { key = tostring(name), button = button })
		end
	end

	table.sort(entries, function(a, b)
		return a.key < b.key
	end)

	-- Blizzard's controls follow the addon icons. The moon is sized by DayNightIndicator,
	-- because its border is stretched across the whole frame.
	if trackingProxyButton then
		table.insert(entries, { button = trackingProxyButton })
	end

	if lfgProxyButton and not IS_FOREVER then
		table.insert(entries, { button = lfgProxyButton })
	end

	local dayNightFrame = DayNightIndicator.GetFrame()
	if dayNightFrame then
		table.insert(entries, { button = dayNightFrame, keepSize = true })
	end

	-- The first icon and the gap between columns stay fixed, so the slider only changes
	-- the distance between icons in a column.
	local spacing = GetDatabase().addonButtonSpacing
	local topOffset = ALIGNED_BUTTON.SPACING * 0.5
	local rowCount = math.max(math.floor(((Minimap:GetHeight() or DEFAULT_SIZE) - (topOffset * 2)) / spacing) + 1, 1)
	local index = 0
	for _, entry in ipairs(entries) do
		local button = entry.button
		if button:IsShown() then
			local row = index % rowCount
			local column = math.floor(index / rowCount)
			index = index + 1

			if not entry.keepSize then
				NormalizeAddonButton(button)
			end

			-- A dragged button would only snap back here, so turn dragging off.
			button:RegisterForDrag()
			button:ClearAllPoints()
			-- These have different parents, so convert the offsets from Minimap units.
			local scaleRatio = Minimap:GetEffectiveScale() / button:GetEffectiveScale()
			button:SetPoint(
				'CENTER',
				Minimap,
				'TOPLEFT',
				column * ALIGNED_BUTTON.SPACING * scaleRatio,
				-(topOffset + (row * spacing)) * scaleRatio
			)
		end
	end
end

-- Forever anchors the addon compartment to GameTimeFrame, which anchors to the suppressed
-- zone header, so it would be left with no valid position without this.
local function ApplyForeverAddonCompartmentLayout()
	local compartment = _G.AddonCompartmentFrame
	if not IS_FOREVER or not compartment then
		return
	end

	PreserveWidgetMethods(compartment)
	HookWidgetPosition(compartment)
	AnchorWidget(compartment, 'TOPRIGHT', 'TOPRIGHT', -2, -2)
end

ApplyBlizzardWidgetLayout = function()
	if type(InCombatLockdown) == 'function' and InCombatLockdown() then
		minimapRefreshPending = true
		return
	end

	local tracking = GetTrackingFrame()
	EnsureTrackingProxy()
	UpdateTrackingProxy()
	if trackingProxyButton then
		if not IsAddonButtonAlignmentEnabled() then
			trackingProxyButton:RegisterForDrag('LeftButton')
			AnchorProxy(trackingProxyButton, 'tracking')
		end

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

		-- Forever draws a background on the parent of the tracking button.
		local cluster = _G.MinimapCluster
		if IS_FOREVER and cluster and cluster.Tracking and cluster.Tracking.SetAlpha then
			cluster.Tracking:SetAlpha(0)
		end
	end

	-- Forever's native queue eye anchors to the Minimap by itself and appears only while
	-- queued. Clicking it from addon code would taint its leave-queue menu, so leave it alone.
	if not IS_FOREVER then
		local lfg = GetLFGFrame()
		EnsureLFGProxy()
		UpdateLFGProxy()
		if lfgProxyButton then
			if not IsAddonButtonAlignmentEnabled() then
				lfgProxyButton:RegisterForDrag('LeftButton')
				AnchorProxy(lfgProxyButton, 'lfg')
			end

			lfgProxyButton:Show()
		end

		if lfg then
			PreserveWidgetMethods(lfg)
			HookWidgetPosition(lfg)
			if lfg.SetAlpha then
				lfg:SetAlpha(0)
			end
		end
	end

	ApplyForeverAddonCompartmentLayout()
	BuffIcons.ApplyLayout()
	DayNightIndicator.EnableDragging()
	DayNightIndicator.ApplyLayout()
	ApplyAddonButtonLayout()
	HideBlizzardClocks()

	local mail = GetMailFrame()
	if mail then
		-- Forever's mail frame calls GetParent():Layout() on UPDATE_PENDING_MAIL. It is about
		-- to be parented to the Minimap, which has no Layout method and would raise an error.
		local mailParent = mail.GetParent and mail:GetParent()
		if mailParent and mailParent.Layout and not Minimap.Layout then
			Minimap.Layout = Noop
		end

		MakeWidgetDraggable(mail, 'mail', true)
		PreserveWidgetMethods(mail)
		HookWidgetPosition(mail)
		AnchorStoredWidget(mail, 'mail')
		if not mail.__ProkinMailVisibilityHooksInstalled then
			mail.__ProkinMailVisibilityHooksInstalled = true
			if mail.HookScript then
				mail:HookScript('OnShow', RefreshMailVisibility)
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

	if IsAddonButtonAlignmentEnabled() then
		ApplyAddonButtonLayout()
		return
	end

	addonMinimapButton:RegisterForDrag('LeftButton')
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

	addonMinimapButton:Show()
	AnchorAddonMinimapButton()
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
		if IsAddonButtonAlignmentEnabled() then
			NormalizeAddonButton(self)
		end
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
		if not IsAltKeyDown() or IsAddonButtonAlignmentEnabled() then
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
		if not IsAddonButtonAlignmentEnabled() then
			GameTooltip:AddLine('Alt-Left-Drag: Move button', 0.85, 0.85, 0.85)
		end
		-- Only add colorized gold tracker lines, avoid duplicates
		AddGoldTrackerTooltipLine(GameTooltip)
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

local function SetZoneTextSize(size)
	GetDatabase().zoneTextSize = NormalizeZoneTextSize(size)
	RefreshMinimap()
	return GetZoneTextSize()
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

	local zoneTextSize = GetZoneTextSize()
	optionsFrame.zoneTextSlider.__ProkinSyncing = true
	optionsFrame.zoneTextSlider:SetValue(zoneTextSize)
	optionsFrame.zoneTextSlider.__ProkinSyncing = nil
	optionsFrame.zoneTextSlider.valueText:SetText(string.format('%d', zoneTextSize))

	optionsFrame.showAddonButton:SetChecked(db.showAddonButton ~= false)
	optionsFrame.alignAddonButtons:SetChecked(db.alignAddonButtons ~= false)

	local spacingSlider = optionsFrame.addonSpacingSlider
	spacingSlider.__ProkinSyncing = true
	spacingSlider:SetValue(db.addonButtonSpacing)
	spacingSlider.__ProkinSyncing = nil
	spacingSlider.valueText:SetText(string.format('%d', db.addonButtonSpacing))
	spacingSlider:SetEnabled(db.alignAddonButtons ~= false)
	optionsFrame.resetAddonSpacingButton:SetEnabled(db.alignAddonButtons ~= false)

	optionsFrame.unlockBuffsButton:SetText(BuffIcons.IsUnlocked() and 'Lock Buff Icons' or 'Unlock Buff Icons')
	optionsFrame.showServerTime:SetChecked(db.showServerTime ~= false)
	optionsFrame.showMinimapBorder:SetChecked(db.showMinimapBorder ~= false)
	optionsFrame.showLoadAnnouncement:SetChecked(db.showLoadAnnouncement ~= false)
	optionsFrame.enableGoldTracking:SetChecked(db.goldTracker and db.goldTracker.goldTrackingEnabled ~= false)
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
	frame:SetSize(440, 690)
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

	-- Builds a labelled slider with a value readout and a reset button.
	local function CreateLabelledSlider(label, name, minValue, maxValue, onValueChanged, onReset)
		local slider = CreateFrame('Slider', name, frame, BackdropTemplateMixin and 'BackdropTemplate' or nil)
		slider:SetOrientation('HORIZONTAL')
		slider:SetPoint('TOPLEFT', label, 'BOTTOMLEFT', 14, -10)
		slider:SetWidth(220)
		slider:SetHeight(15)
		slider:SetHitRectInsets(0, 0, -10, 0)
		slider:SetBackdrop(OPTION_SLIDER_BACKDROP)
		slider:SetThumbTexture([[Interface\Buttons\UI-SliderBar-Button-Horizontal]])
		slider:SetMinMaxValues(minValue, maxValue)
		slider:SetValueStep(1)
		if slider.SetObeyStepOnDrag then
			slider:SetObeyStepOnDrag(true)
		end

		slider.fill = slider:CreateTexture(nil, 'BACKGROUND')
		slider.fill:SetColorTexture(0.85, 0.72, 0.12, 1)
		slider.fill:SetPoint('LEFT', slider, 'LEFT', 3, 0)
		slider.fill:SetHeight(9)

		slider.lowText = frame:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
		slider.lowText:SetPoint('TOPLEFT', slider, 'BOTTOMLEFT', 2, 3)
		slider.lowText:SetText(tostring(minValue))

		slider.highText = frame:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
		slider.highText:SetPoint('TOPRIGHT', slider, 'BOTTOMRIGHT', -2, 3)
		slider.highText:SetText(tostring(maxValue))

		slider.valueText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		slider.valueText:SetPoint('LEFT', slider, 'RIGHT', 14, 0)

		slider:SetScript('OnValueChanged', function(self, value)
			local rounded = math.floor(value + 0.5)
			UpdateOptionsSliderVisuals(self, rounded)
			self.valueText:SetText(string.format('%d', rounded))
			if not self.__ProkinSyncing then
				onValueChanged(rounded)
			end
		end)

		local resetButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
		resetButton:SetSize(70, 22)
		resetButton:SetPoint('LEFT', slider, 'RIGHT', 44, 0)
		resetButton:SetText('Reset')
		resetButton:SetScript('OnClick', function()
			onReset()
			SyncOptionsWindow()
		end)

		return slider, resetButton
	end

	frame.zoneTextLabel = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	frame.zoneTextLabel:SetPoint('TOPLEFT', frame.resetSizeButton, 'BOTTOMLEFT', 0, -14)
	frame.zoneTextLabel:SetText('Zone Text Size')

	frame.zoneTextSlider, frame.resetZoneTextButton = CreateLabelledSlider(
		frame.zoneTextLabel,
		'ProkinMinimapOptionsZoneTextSlider',
		MIN_ZONE_TEXT_SIZE,
		MAX_ZONE_TEXT_SIZE,
		SetZoneTextSize,
		function()
			SetZoneTextSize(nil)
		end
	)

	frame.addonSpacingLabel = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	frame.addonSpacingLabel:SetPoint('TOPLEFT', frame.zoneTextLabel, 'BOTTOMLEFT', 0, -48)
	frame.addonSpacingLabel:SetText('Addon Icon Spacing')

	local function SetAddonButtonSpacing(spacing)
		GetDatabase().addonButtonSpacing = spacing
		RefreshMinimap()
	end

	frame.addonSpacingSlider, frame.resetAddonSpacingButton = CreateLabelledSlider(
		frame.addonSpacingLabel,
		'ProkinMinimapOptionsAddonSpacingSlider',
		ALIGNED_BUTTON.MIN_SPACING,
		ALIGNED_BUTTON.MAX_SPACING,
		SetAddonButtonSpacing,
		function()
			SetAddonButtonSpacing(ALIGNED_BUTTON.SPACING)
		end
	)

	frame.showAddonButton = CreateOptionsCheckbox(frame, 'Show Prokin minimap button', 'Show or hide the Prokin minimap button around the square minimap border.')
	frame.unlockBuffsButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	frame.unlockBuffsButton:SetSize(150, 22)
	frame.unlockBuffsButton:SetPoint('TOPLEFT', frame.addonSpacingLabel, 'BOTTOMLEFT', 0, -48)
	frame.unlockBuffsButton:SetScript('OnClick', function()
		BuffIcons.SetUnlocked(not BuffIcons.IsUnlocked())
		SyncOptionsWindow()
	end)

	frame.resetBuffsButton = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	frame.resetBuffsButton:SetSize(150, 22)
	frame.resetBuffsButton:SetPoint('LEFT', frame.unlockBuffsButton, 'RIGHT', 12, 0)
	frame.resetBuffsButton:SetText('Reset Buff Icons')
	frame.resetBuffsButton:SetScript('OnClick', function()
		BuffIcons.Reset()
		SyncOptionsWindow()
	end)

	frame.showAddonButton:SetPoint('TOPLEFT', frame.unlockBuffsButton, 'BOTTOMLEFT', 0, -10)
	frame.showAddonButton:SetScript('OnClick', function(self)
		ApplyOptionChange(function(db)
			db.showAddonButton = self:GetChecked() and true or false
		end)
	end)

	frame.showServerTime = CreateOptionsCheckbox(frame, 'Show server time in the zone label', 'Append the server time to the custom zone text shown above the minimap.')
	frame.alignAddonButtons = CreateOptionsCheckbox(frame, 'Align addon minimap buttons on the left border', 'Give the Prokin button, LibDBIcon addon buttons, Blizzard tracking button, and day/night icon the same size and line them up along the left border. These cannot be dragged while this is on.')
	frame.alignAddonButtons:SetPoint('TOPLEFT', frame.showAddonButton, 'BOTTOMLEFT', 0, -8)
	frame.alignAddonButtons:SetScript('OnClick', function(self)
		local enabled = self:GetChecked() and true or false
		ApplyOptionChange(function(db)
			db.alignAddonButtons = enabled
		end)
		if not enabled then
			Print('Type /reload to return other addons\' buttons to their saved positions.')
		end
	end)

	frame.showServerTime:SetPoint('TOPLEFT', frame.alignAddonButtons, 'BOTTOMLEFT', 0, -8)
	frame.showServerTime:SetScript('OnClick', function(self)
		ApplyOptionChange(function(db)
			db.showServerTime = self:GetChecked() and true or false
		end)
	end)

	frame.showMinimapBorder = CreateOptionsCheckbox(frame, 'Show the 1px minimap border', 'Show or hide the custom black border drawn around the square minimap.')
	frame.showMinimapBorder:SetPoint('TOPLEFT', frame.showServerTime, 'BOTTOMLEFT', 0, -8)
	frame.showMinimapBorder:SetScript('OnClick', function(self)
		ApplyOptionChange(function(db)
			db.showMinimapBorder = self:GetChecked() and true or false
		end)
	end)

	frame.showLoadAnnouncement = CreateOptionsCheckbox(frame, 'Show the load announcement after /reload', 'Control whether Prokin Minimap announces itself in chat after loading or reloading the UI.')
	frame.showLoadAnnouncement:SetPoint('TOPLEFT', frame.showMinimapBorder, 'BOTTOMLEFT', 0, -8)
	frame.showLoadAnnouncement:SetScript('OnClick', function(self)
		local enabled = self:GetChecked() and true or false
		ApplyOptionChange(function(db)
			db.showLoadAnnouncement = enabled
		end)
		if not enabled then
			loadAnnouncementPending = nil
		end
	end)

	frame.enableGoldTracking = CreateOptionsCheckbox(frame, 'Enable gold tracking', 'Track gold income and item values in the Prokin Minimap tooltip.')
	frame.enableGoldTracking:SetPoint('TOPLEFT', frame.showLoadAnnouncement, 'BOTTOMLEFT', 0, -8)
	frame.enableGoldTracking:SetScript('OnClick', function(self)
		ApplyOptionChange(function(db)
			if type(db.goldTracker) ~= 'table' then
				db.goldTracker = {}
			end
			db.goldTracker.goldTrackingEnabled = self:GetChecked() and true or false
		end)
	end)

	frame.helpText = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	frame.helpText:SetPoint('TOPLEFT', frame.enableGoldTracking, 'BOTTOMLEFT', 4, -14)
	frame.helpText:SetWidth(392)
	frame.helpText:SetJustifyH('LEFT')
	frame.helpText:SetText('Button controls: Left-click starts a role check, right-click opens these options, and Alt-Left-Drag repositions the button when alignment is off.\nGold tracking uses TradeSkillMaster-style pricing when available, with vendor fallback when TSM is not installed. Thanks to the TradeSkillMaster authors.')
	frame.helpText:SetHeight(58)

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
	Print(string.format('Current size: %dx%d. Commands: /pkm size <number>, /pkm larger [step], /pkm smaller [step], /pkm reset, /pkm zonetext <number|reset>, /pkm resetmoon, /pkm buffs [unlock|lock|reset], /pkm options, /pkm ledger [character], /pkm expenses, or /pkm trackingdebug [on|off].', GetDatabase().size, GetDatabase().size))
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

	if command == 'buffs' then
		local action = string.lower(remainder or '')
		if action == 'reset' then
			BuffIcons.Reset()
		elseif action == 'unlock' or action == 'lock' or action == '' then
			local unlock = action == 'unlock' or (action == '' and not BuffIcons.IsUnlocked())
			if BuffIcons.SetUnlocked(unlock) then
				Print(unlock and 'Buff icons unlocked. Drag the blue box to move them.' or 'Buff icons locked.')
			else
				Print('Buff icons are unavailable on this client.')
			end
		else
			Print('Usage: /pkm buffs [unlock|lock|reset]')
		end

		SyncOptionsWindow()
		return
	end

	if command == 'resetmoon' then
		GetDatabase().dayNightPosition = nil
		DayNightIndicator.ApplyLayout()
		Print('Day/night icon position reset.')
		return
	end

	if command == 'zonetext' then
		local value = string.lower(remainder or '')
		if value == 'reset' or value == 'default' then
			Print(string.format('Zone text size reset to %d.', SetZoneTextSize(nil)))
		elseif NormalizeZoneTextSize(value) then
			Print(string.format('Zone text size set to %d.', SetZoneTextSize(value)))
		else
			Print(string.format('Enter a size between %d and %d, for example: /pkm zonetext 14', MIN_ZONE_TEXT_SIZE, MAX_ZONE_TEXT_SIZE))
		end

		SyncOptionsWindow()
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

	if command == 'ledger' then
		local ledger = _G.ProkinMinimapLedger
		if ledger and type(ledger.PrintCharacterLedger) == 'function' then
			if remainder and remainder ~= '' then
				ledger:PrintCharacterLedger(remainder)
			else
				ledger:PrintCharacterLedger()
			end
		else
			Print('Ledger system not loaded.')
		end
		return
	end

	if command == 'expenses' then
		local ledger = _G.ProkinMinimapLedger
		if ledger and type(ledger.PrintExpenseHistory) == 'function' then
			local limit = tonumber(remainder) or 10
			ledger:PrintExpenseHistory(nil, limit)
		else
			Print('Ledger system not loaded.')
		end
		return
	end

	if command == 'allcharacters' or command == 'all' then
		local ledger = _G.ProkinMinimapLedger
		if ledger and type(ledger.PrintAllCharacters) == 'function' then
			ledger:PrintAllCharacters()
		else
			Print('Ledger system not loaded.')
		end
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
		-- Forever restores its round mask here when the rotateMinimap setting changes.
		if type(_G.MinimapCluster.UpdateMinimapConfig) == 'function' then
			hooksecurefunc(_G.MinimapCluster, 'UpdateMinimapConfig', function()
				RefreshMinimap()
			end)
		end

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
	DayNightIndicator.UpdateDrag()
	BuffIcons.UpdateDrag()

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
