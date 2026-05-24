local tracker = _G.ProkinMinimapGoldTracker or {}
_G.ProkinMinimapGoldTracker = tracker

local eventFrame = CreateFrame('Frame')
local sessionStartedAt = 0
local sessionIncomeCopper = 0
local lastMoneyCopper
local trackedInventoryCounts = {}
local pendingItemIncome = {}
local pendingInventoryScanAt
local mailHooksInstalled
local VALUE_PRICE_SOURCE = 'dbmarket'
local dailyResetElapsed = 0

local function GetTrackerDB()
	if type(ProkinMinimapDB) ~= 'table' then
		ProkinMinimapDB = {}
	end

	if type(ProkinMinimapDB.goldTracker) ~= 'table' then
		ProkinMinimapDB.goldTracker = {}
	end

	return ProkinMinimapDB.goldTracker
end

local function GetServerDayKey()
	local serverTime = type(GetServerTime) == 'function' and GetServerTime() or time()
	return date('%Y-%m-%d', serverTime)
end

local function GetCharacterKey()
	local name, realm = UnitName('player')
	if not name or name == '' then
		return 'unknown'
	end

	realm = realm or GetRealmName() or ''
	if realm ~= '' then
		return name .. '-' .. realm
	end

	return name
end

local function GetCharacterState()
	local db = GetTrackerDB()
	if type(db.characters) ~= 'table' then
		db.characters = {}
	end

	local key = GetCharacterKey()
	local state = db.characters[key]
	if type(state) ~= 'table' then
		state = {}
		db.characters[key] = state
	end

	if not db.__legacyDailyTotalMigrated
		and (type(db.dailyTotalCopper) == 'number' or type(db.dailyTotalDayKey) == 'string') then
		state.dailyTotalCopper = state.dailyTotalCopper or db.dailyTotalCopper or 0
		state.dailyTotalDayKey = state.dailyTotalDayKey or db.dailyTotalDayKey or GetServerDayKey()
		db.dailyTotalCopper = nil
		db.dailyTotalDayKey = nil
		db.__legacyDailyTotalMigrated = true
	end

	return db, state
end

local function EnsureDailyState()
	local db, state = GetCharacterState()
	if type(db.goldTrackingEnabled) ~= 'boolean' then
		db.goldTrackingEnabled = true
	end

	local dayKey = GetServerDayKey()
	if state.dailyTotalDayKey ~= dayKey then
		state.dailyTotalDayKey = dayKey
		state.dailyTotalCopper = 0
	end

	if type(state.dailyTotalCopper) ~= 'number' then
		state.dailyTotalCopper = 0
	end

	return db, state
end

local function IsGoldTrackingEnabled()
	return EnsureDailyState().goldTrackingEnabled ~= false
end

local function FormatCopperValue(copper)
	copper = math.max(math.floor((copper or 0) + 0.5), 0)

	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local bronze = copper % 100

	if gold > 0 then
		return string.format('%dg %ds %dc', gold, silver, bronze)
	end

	if silver > 0 then
		return string.format('%ds %dc', silver, bronze)
	end

	return string.format('%dc', bronze)
end

local function GetNumBagSlots()
	return NUM_BAG_SLOTS or 4
end

local function GetContainerSlotCount(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end

	if type(GetContainerNumSlots) == 'function' then
		return GetContainerNumSlots(bag) or 0
	end

	return 0
end

local function GetBagItemInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then
			return info.itemID, info.stackCount or 1, info.hyperlink
		end
	end

	if type(GetContainerItemInfo) == 'function' then
		local _, stackCount, _, _, _, _, link = GetContainerItemInfo(bag, slot)
		if not link then
			return nil, 0, nil
		end

		return tonumber(link:match('item:(%d+)')), stackCount or 1, link
	end

	return nil, 0, nil
end

local function GetSessionElapsed()
	if sessionStartedAt == 0 then
		return 0
	end

	return math.max(GetTime() - sessionStartedAt, 0)
end

local function AddIncome(copper)
	if not IsGoldTrackingEnabled() then
		return
	end

	copper = math.floor((copper or 0) + 0.5)
	if copper <= 0 then
		return
	end

	local _, state = EnsureDailyState()
	sessionIncomeCopper = sessionIncomeCopper + copper
	state.dailyTotalCopper = (state.dailyTotalCopper or 0) + copper
end

local function GetTrackedItemLink(itemRef)
	if type(itemRef) == 'string' then
		return itemRef
	end

	if type(itemRef) == 'number' then
		return select(2, GetItemInfo(itemRef))
	end

	return nil
end

local function GetTrackedItemID(itemRef)
	if type(itemRef) == 'number' then
		return itemRef
	end

	if type(itemRef) == 'string' then
		return tonumber(itemRef:match('item:(%d+)'))
	end

	return nil
end

local function GetTrackedItemValue(itemRef)
	local itemLink = GetTrackedItemLink(itemRef)
	if not itemLink then
		return nil
	end

	local _, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemLink)
	if quality == 0 then
		return sellPrice
	end

	if itemLink and type(TSM_API) == 'table' and type(TSM_API.ToItemString) == 'function' and type(TSM_API.GetCustomPriceValue) == 'function' then
		local itemString = TSM_API.ToItemString(itemLink)
		if itemString then
			return TSM_API.GetCustomPriceValue(VALUE_PRICE_SOURCE, itemString)
		end
	end

	return sellPrice
end

local function UpdateMoneySnapshot()
	local currentMoney = GetMoney() or 0
	if lastMoneyCopper ~= nil then
		local delta = currentMoney - lastMoneyCopper
		if delta > 0 then
			AddIncome(delta)
		end
	end

	lastMoneyCopper = currentMoney
end

local function QueueItemIncome(itemID, quantity)
	if not itemID or quantity <= 0 or not IsGoldTrackingEnabled() then
		return
	end

	local value = GetTrackedItemValue(itemID)
	if value ~= nil then
		AddIncome(value * quantity)
		return
	end

	pendingItemIncome[itemID] = (pendingItemIncome[itemID] or 0) + quantity
end

local function ResolvePendingItemIncome(itemID)
	local quantity = pendingItemIncome[itemID]
	if not quantity then
		return
	end

	if not IsGoldTrackingEnabled() then
		pendingItemIncome[itemID] = nil
		return
	end

	local value = GetTrackedItemValue(itemID)
	if value == nil then
		return
	end

	AddIncome(value * quantity)

	pendingItemIncome[itemID] = nil
end

local function SnapshotInventory()
	local counts = {}

	for bag = 0, GetNumBagSlots() do
		local slotCount = GetContainerSlotCount(bag)
		for slot = 1, slotCount do
			local itemID, stackCount = GetBagItemInfo(bag, slot)
			if itemID and stackCount and stackCount > 0 then
				counts[itemID] = (counts[itemID] or 0) + stackCount
			end
		end
	end

	return counts
end

local function ApplyInventorySnapshot()
	local currentCounts = SnapshotInventory()
	if not IsGoldTrackingEnabled() then
		trackedInventoryCounts = currentCounts
		return
	end

	for itemID, currentCount in pairs(currentCounts) do
		local previousCount = trackedInventoryCounts[itemID] or 0
		if currentCount > previousCount then
			QueueItemIncome(itemID, currentCount - previousCount)
		end
	end

	trackedInventoryCounts = currentCounts
end

local function QueueInventoryScan()
	pendingInventoryScanAt = GetTime()
end

local function InstallMailHooks()
	if mailHooksInstalled or type(hooksecurefunc) ~= 'function' then
		return
	end

	if type(TakeInboxMoney) == 'function' then
		hooksecurefunc('TakeInboxMoney', function()
			UpdateMoneySnapshot()
		end)
	end

	if type(TakeInboxItem) == 'function' then
		hooksecurefunc('TakeInboxItem', function()
			QueueInventoryScan()
		end)
	end

	if type(TakeInboxTextItem) == 'function' then
		hooksecurefunc('TakeInboxTextItem', function()
			QueueInventoryScan()
		end)
	end

	if type(AutoLootMailItem) == 'function' then
		hooksecurefunc('AutoLootMailItem', function()
			QueueInventoryScan()
		end)
	end

	mailHooksInstalled = true
end

function tracker:GetSessionElapsed()
	return GetSessionElapsed()
end

function tracker:GetSessionIncome()
	return sessionIncomeCopper
end

function tracker:GetDailyTotal()
	local _, state = EnsureDailyState()
	return state.dailyTotalCopper or 0
end

function tracker:GetSessionGPH()
	local elapsed = GetSessionElapsed()
	if elapsed <= 0 then
		return 0
	end

	return math.floor((sessionIncomeCopper / elapsed) * 3600 + 0.5)
end

function tracker:GetTooltipLine()
	if sessionStartedAt == 0 or not IsGoldTrackingEnabled() then
		return nil
	end

	return string.format('GPH: %s', FormatCopperValue(self:GetSessionGPH()))
end

function tracker:GetTooltipLines()
	if sessionStartedAt == 0 then
		return nil
	end

	if not IsGoldTrackingEnabled() then
		return nil
	end

	return {
		string.format('GPH: %s', FormatCopperValue(self:GetSessionGPH())),
		string.format('Session Total: %s', FormatCopperValue(sessionIncomeCopper)),
		string.format('Daily Total: %s', FormatCopperValue(self:GetDailyTotal()))
	}
end

eventFrame:RegisterEvent('PLAYER_LOGIN')
eventFrame:RegisterEvent('PLAYER_MONEY')
eventFrame:RegisterEvent('CHAT_MSG_LOOT')
eventFrame:RegisterEvent('MAIL_INBOX_UPDATE')
eventFrame:RegisterEvent('QUEST_TURNED_IN')
eventFrame:RegisterEvent('BAG_UPDATE_DELAYED')
eventFrame:RegisterEvent('TRADE_CLOSED')
eventFrame:RegisterEvent('GET_ITEM_INFO_RECEIVED')

eventFrame:SetScript('OnEvent', function(_, event, arg1, arg2)
	if event == 'PLAYER_LOGIN' then
		EnsureDailyState()
		sessionStartedAt = GetTime()
		sessionIncomeCopper = 0
		lastMoneyCopper = GetMoney() or 0
		trackedInventoryCounts = SnapshotInventory()
		wipe(pendingItemIncome)
		pendingInventoryScanAt = nil
		InstallMailHooks()
		return
	end

	if event == 'PLAYER_MONEY' or event == 'TRADE_CLOSED' then
		UpdateMoneySnapshot()
		if event == 'TRADE_CLOSED' then
			ApplyInventorySnapshot()
			pendingInventoryScanAt = nil
		end
		return
	end

	if event == 'CHAT_MSG_LOOT' or event == 'QUEST_TURNED_IN' then
		QueueInventoryScan()
		return
	end

	if event == 'MAIL_INBOX_UPDATE' then
		if (_G.MailFrame and _G.MailFrame:IsShown()) or (_G.InboxFrame and _G.InboxFrame:IsShown()) then
			QueueInventoryScan()
		end
		return
	end

	if event == 'BAG_UPDATE_DELAYED' then
		if pendingInventoryScanAt and (GetTime() - pendingInventoryScanAt) <= 3 then
			ApplyInventorySnapshot()
		end
		pendingInventoryScanAt = nil
		return
	end

	if event == 'GET_ITEM_INFO_RECEIVED' then
		if arg2 then
			ResolvePendingItemIncome(arg1)
		end
	end
end)

eventFrame:SetScript('OnUpdate', function(_, elapsed)
	dailyResetElapsed = dailyResetElapsed + elapsed
	if dailyResetElapsed < 30 then
		return
	end

	dailyResetElapsed = 0
	EnsureDailyState()
end)
