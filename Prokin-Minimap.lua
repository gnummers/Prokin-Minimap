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
local PROXY_BUTTON_SIZE = 33
local PROXY_BACKGROUND_SIZE = 30
local PROXY_ICON_SIZE = 24
local PROXY_BORDER_SIZE = 64
local PROXY_ICON_OFFSET_X = 2
local PROXY_ICON_OFFSET_Y = -2
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
local lastZoneTimeSuffix
local autoMarkAssistHookInstalled
local adjustingWidgetLayout
local trackingProxyButton
local lfgProxyButton
local battlefieldProxyButton
local activeWidgetDrag
local pendingTrackingMenuAnchor
local GetDatabase
local RefreshMinimap
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
	'ProkinMinimapTrackingProxy',
	'ProkinMinimapLFGProxy',
	'ProkinMinimapBattlefieldProxy'
}

local function Noop() end

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(string.format('|cff33ff99%s|r: %s', ADDON_NAME, message))
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

	local timeSuffix = GetServerTimeSuffix()
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

local function GetClockFrame()
	return _G.TimeManagerClockButton or _G.GameTimeFrame
end

local function GetMailFrame()
	local cluster = _G.MinimapCluster
	local indicator = cluster and cluster.IndicatorFrame
	return (indicator and indicator.MailFrame) or _G.MiniMapMailFrame
end

local function GetLFGFrame()
	return _G.QueueStatusMinimapButton or _G.QueueStatusButton or _G.MiniMapLFGFrame or _G.LFGMinimapFrame
end

local function GetBattlefieldFrame()
	return _G.MiniMapBattlefieldFrame
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
			if button == 'RightButton' and _G.MiniMapBattlefieldDropDown then
				ToggleDropDownMenu(1, nil, _G.MiniMapBattlefieldDropDown, self, 0, -5)
			elseif IsShiftKeyDown() and type(ToggleBattlefieldMinimap) == 'function' then
				ToggleBattlefieldMinimap()
			elseif type(ToggleWorldStateScoreFrame) == 'function' then
				ToggleWorldStateScoreFrame()
			end
		elseif button == 'RightButton' and _G.MiniMapBattlefieldDropDown then
			ToggleDropDownMenu(1, nil, _G.MiniMapBattlefieldDropDown, self, 0, -5)
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
		if HasNewMail and HasNewMail() then
			mail:Show()
		elseif mail.Hide then
			mail:Hide()
		end
	end

	local battlefield = GetBattlefieldFrame()
	local battlefieldStatus = GetBattlefieldStatusInfo()
	EnsureBattlefieldProxy()
	if battlefieldProxyButton then
		AnchorProxy(battlefieldProxyButton, 'battlefield')
		if battlefieldStatus ~= nil then
			battlefieldProxyButton:Show()
		else
			battlefieldProxyButton:Hide()
		end
	end

	if battlefield then
		PreserveWidgetMethods(battlefield)
		HookWidgetPosition(battlefield)
		if battlefield.SetAlpha then
			battlefield:SetAlpha(0)
		end
	end
end

local function PositionButtonOnSquareEdge(button, angle)
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

	button:ClearAllPoints()
	button:SetPoint('CENTER', Minimap, 'CENTER', (xUnit / divisor) * halfWidth, (yUnit / divisor) * halfHeight)
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
	_G.GetMinimapShape = GetSquareMinimapShape
	EnsureMinimapButtonButtonBlacklist()
	ApplySquareMinimap()
	EnsureMinimapBorder()
	ApplyZoneLayout()
	HideDefaultZoneHeader()
	ApplyBlizzardWidgetLayout()
	ApplyHybridMinimap()
	InstallAutoMarkAssistCompatibility()
	ApplyAutoMarkAssistCompatibility()
end

local function SetMinimapSize(size)
	local normalized = NormalizeSize(size)
	if not normalized then
		return nil
	end

	GetDatabase().size = normalized
	RefreshMinimap()

	return normalized
end

local function ShowHelp()
	Print(string.format('Current size: %dx%d. Use /pkm size <number>, /pkm larger [step], /pkm smaller [step], /pkm reset, or /pkm trackingdebug [on|off].', GetDatabase().size, GetDatabase().size))
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
	elseif event == 'PLAYER_LOGIN' then
		InstallHooks()
	end

	if event == 'PLAYER_LOGIN' or event == 'PLAYER_ENTERING_WORLD' then
		loadAnnouncementDelay = 2
	end

	RefreshMinimap()
end)
eventFrame:SetScript('OnUpdate', function(_, elapsed)
	UpdateWidgetDrag()

	if loadAnnouncementPending then
		loadAnnouncementDelay = math.max((loadAnnouncementDelay or 0) - elapsed, 0)
		TryShowLoadAnnouncement()
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
