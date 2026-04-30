local ADDON_NAME = ...
local HYBRID_MINIMAP_ADDON = 'Blizzard_HybridMinimap'
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

local function ApplyZoneLayout()
	local button = _G.MinimapZoneTextButton
	local cluster = _G.MinimapCluster
	if not Minimap or not cluster or adjustingZoneLayout then
		return
	end

	adjustingZoneLayout = true

	local headerHeight = button and button:GetHeight() or 0
	Minimap:ClearAllPoints()
	Minimap:SetPoint('TOPRIGHT', cluster, 'TOPRIGHT', 0, -(headerHeight + HEADER_SPACING))

	if button then
		button:ClearAllPoints()
		button:SetPoint('BOTTOMLEFT', Minimap, 'TOPLEFT', 0, HEADER_SPACING)
		button:SetPoint('BOTTOMRIGHT', Minimap, 'TOPRIGHT', 0, HEADER_SPACING)
	end

	adjustingZoneLayout = false
end

local function ApplyHybridMinimap()
	local hybridMinimap = _G.HybridMinimap
	if not hybridMinimap then
		return
	end

	local mapCanvas = hybridMinimap.MapCanvas
	if mapCanvas and mapCanvas.SetMaskTexture then
		mapCanvas:SetMaskTexture()
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

local function RefreshMinimap()
	_G.GetMinimapShape = GetSquareMinimapShape
	ApplySquareMinimap()
	EnsureMinimapBorder()
	ApplyZoneLayout()
	ApplyHybridMinimap()
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

	if Minimap and Minimap.HookScript then
		Minimap:HookScript('OnShow', RefreshMinimap)
	end

	if Minimap then
		hooksecurefunc(Minimap, 'SetPoint', ApplyZoneLayout)
	end

	if _G.MinimapZoneTextButton then
		hooksecurefunc(_G.MinimapZoneTextButton, 'SetPoint', ApplyZoneLayout)
	end

	hooksInstalled = true
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:SetScript('OnEvent', function(_, event, arg1)
	if event == 'ADDON_LOADED' then
		if arg1 == ADDON_NAME then
			GetDatabase()
			InstallHooks()
		elseif arg1 == HYBRID_MINIMAP_ADDON then
			ApplyHybridMinimap()
		else
			return
		end
	elseif event == 'PLAYER_LOGIN' then
		InstallHooks()
	end

	RefreshMinimap()
end)
