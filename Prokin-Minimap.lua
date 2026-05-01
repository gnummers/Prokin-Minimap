local ADDON_NAME = ...
local HYBRID_MINIMAP_ADDON = 'Blizzard_HybridMinimap'
local AUTOMARKASSIST_ADDON = 'AutoMarkAssist'
local DEFAULT_SIZE = 400
local MIN_SIZE = 100
local MAX_SIZE = 800
local DEFAULT_STEP = 25
local HEADER_SPACING = 4
local BORDER_SIZE = 1
local SQUARE_MASK = [[Interface\ChatFrame\ChatFrameBackground]]
local HIDDEN_TEXTURES = {
	'MinimapBorder',
	'MinimapBorderTop',
	'MiniMapTrackingBorder'
}
local hooksInstalled
local adjustingZoneLayout
local minimapBorder
local zoneHeaderFrame
local zoneHeaderText
local hiddenZoneHeaderParent
local eventFrame
local zoneTimeElapsed = 0
local lastZoneTimeSuffix
local autoMarkAssistHookInstalled

local function Noop() end

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage(string.format('|cff33ff99%s|r: %s', ADDON_NAME, message))
end

local function HideTexture(name)
	local texture = _G[name]
	if texture then
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

local function GetDatabase()
	if type(ProkinMinimapDB) ~= 'table' then
		ProkinMinimapDB = {}
	end

	ProkinMinimapDB.size = NormalizeSize(ProkinMinimapDB.size) or DEFAULT_SIZE
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
	Minimap:SetPoint('TOPRIGHT', cluster, 'TOPRIGHT', 0, -(headerHeight + HEADER_SPACING))

	if zoneHeaderFrame then
		zoneHeaderFrame:ClearAllPoints()
		zoneHeaderFrame:SetPoint('BOTTOMLEFT', Minimap, 'TOPLEFT', 0, HEADER_SPACING)
		zoneHeaderFrame:SetPoint('BOTTOMRIGHT', Minimap, 'TOPRIGHT', 0, HEADER_SPACING)
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

local function RefreshMinimap()
	_G.GetMinimapShape = GetSquareMinimapShape
	ApplySquareMinimap()
	EnsureMinimapBorder()
	ApplyZoneLayout()
	HideDefaultZoneHeader()
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
	Print(string.format('Current size: %dx%d. Use /pkm size <number>, /pkm larger [step], /pkm smaller [step], or /pkm reset.', GetDatabase().size, GetDatabase().size))
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
	end

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
		elseif arg1 == HYBRID_MINIMAP_ADDON then
			ApplyHybridMinimap()
		elseif arg1 == AUTOMARKASSIST_ADDON then
			InstallAutoMarkAssistCompatibility()
		else
			return
		end
	elseif event == 'PLAYER_LOGIN' then
		InstallHooks()
	end

	RefreshMinimap()
end)
eventFrame:SetScript('OnUpdate', function(_, elapsed)
	zoneTimeElapsed = zoneTimeElapsed + elapsed
	if zoneTimeElapsed < 1 then
		return
	end

	zoneTimeElapsed = 0

	local timeSuffix = GetServerTimeSuffix()
	if timeSuffix ~= lastZoneTimeSuffix then
		UpdateZoneHeaderText()
	end
end)
