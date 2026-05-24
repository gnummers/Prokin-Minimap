local tracker = _G.ProkinMinimapGoldTracker or {}
_G.ProkinMinimapGoldTracker = tracker

local eventFrame = CreateFrame('Frame')
local sessionStartedAt = 0
local sessionIncomeCopper = 0
local sessionExpenseCopper = 0
local lastMoneyCopper
local trackedInventoryCounts = {}
local pendingItemIncome = {}
local pendingItemExpense = {}
local pendingInventoryScanAt
local mailHooksInstalled
local VALUE_PRICE_SOURCE = 'dbmarket'
local dailyResetElapsed = 0
local lastMailCost = 0

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

	if type(state.dailyExpenses) ~= 'table' then
		state.dailyExpenses = {}
	end

	if type(state.expenses) ~= 'table' then
		state.expenses = {}
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
		state.dailyExpenseCopper = 0
		state.dailyExpenses = {}
	end

	if type(state.dailyTotalCopper) ~= 'number' then
		state.dailyTotalCopper = 0
	end

	if type(state.dailyExpenseCopper) ~= 'number' then
		state.dailyExpenseCopper = 0
	end

	if type(state.dailyExpenses) ~= 'table' then
		state.dailyExpenses = {}
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

local function AddExpense(copper, category)
	if not IsGoldTrackingEnabled() then
		return
	end

	copper = math.floor((copper or 0) + 0.5)
	if copper <= 0 then
		return
	end

	category = category or 'other'
	local _, state = EnsureDailyState()
	sessionExpenseCopper = sessionExpenseCopper + copper
	state.dailyExpenseCopper = (state.dailyExpenseCopper or 0) + copper

	local timestamp = GetTime()
	table.insert(state.expenses, {
		timestamp = timestamp,
		copper = copper,
		category = category
	})

	if type(state.dailyExpenses) ~= 'table' then
		state.dailyExpenses = {}
	end
	state.dailyExpenses[category] = (state.dailyExpenses[category] or 0) + copper
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

local function ProcessLootMessage(message)
	if not IsGoldTrackingEnabled() then
		return
	end

	if message:find("Disenchant") or message:find("disenchant") then
		QueueInventoryScan()
	end
end

local function UpdateMoneySnapshot()
	local currentMoney = GetMoney() or 0
	if lastMoneyCopper ~= nil then
		local delta = currentMoney - lastMoneyCopper
		if delta > 0 then
			AddIncome(delta)
		elseif delta < 0 then
			local absDelta = math.abs(delta)
			local repairCost = 0
			if type(GetRepairAllCost) == 'function' then
				repairCost = GetRepairAllCost() or 0
			end
			if repairCost > 0 and repairCost == absDelta then
				AddExpense(absDelta, 'repair')
			elseif absDelta > 0 and lastMailCost == 0 then
				AddExpense(absDelta, 'other_expense')
			end
			lastMailCost = 0
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

local function QueueItemExpense(itemID, quantity, category)
	if not itemID or quantity <= 0 or not IsGoldTrackingEnabled() then
		return
	end

	category = category or 'item_loss'
	local value = GetTrackedItemValue(itemID)
	if value ~= nil then
		AddExpense(value * quantity, category)
		return
	end

	if not pendingItemExpense[itemID] then
		pendingItemExpense[itemID] = {}
	end
	pendingItemExpense[itemID].quantity = (pendingItemExpense[itemID].quantity or 0) + quantity
	pendingItemExpense[itemID].category = category
end

local function ResolvePendingItemExpense(itemID)
	local pending = pendingItemExpense[itemID]
	if not pending then
		return
	end

	if not IsGoldTrackingEnabled() then
		pendingItemExpense[itemID] = nil
		return
	end

	local value = GetTrackedItemValue(itemID)
	if value == nil then
		return
	end

	AddExpense(value * pending.quantity, pending.category)
	pendingItemExpense[itemID] = nil
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
		elseif currentCount < previousCount then
			QueueItemExpense(itemID, previousCount - currentCount, 'crafting_material')
		end
	end

	for itemID, previousCount in pairs(trackedInventoryCounts) do
		if not currentCounts[itemID] then
			QueueItemExpense(itemID, previousCount, 'crafting_material')
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

	if type(SendMail) == 'function' and type(GetSendMailPrice) == 'function' then
		hooksecurefunc('SendMail', function()
			local postagePrice = GetSendMailPrice() or 0
			if postagePrice > 0 then
				AddExpense(postagePrice, 'postage')
				lastMailCost = postagePrice
			end
		end)
	end

	if type(RepairAllItems) == 'function' then
		hooksecurefunc('RepairAllItems', function()
			UpdateMoneySnapshot()
		end)
	end

	if type(GetRepairAllCost) == 'function' then
		local originalGetRepairAllCost = GetRepairAllCost
		function GetRepairAllCost()
			return originalGetRepairAllCost()
		end
	end

	mailHooksInstalled = true
end

function tracker:GetSessionElapsed()
	return GetSessionElapsed()
end

function tracker:GetSessionIncome()
	return sessionIncomeCopper
end

function tracker:GetSessionExpense()
	return sessionExpenseCopper
end

function tracker:GetSessionNetIncome()
	return sessionIncomeCopper - sessionExpenseCopper
end

function tracker:GetDailyTotal()
	local _, state = EnsureDailyState()
	return state.dailyTotalCopper or 0
end

function tracker:GetDailyExpense()
	local _, state = EnsureDailyState()
	return state.dailyExpenseCopper or 0
end

function tracker:GetDailyNetIncome()
	return self:GetDailyTotal() - self:GetDailyExpense()
end

function tracker:GetDailyExpenseBreakdown()
	local _, state = EnsureDailyState()
	return state.dailyExpenses or {}
end

function tracker:GetInventoryWorth()
	local worth = 0
	for bag = 0, GetNumBagSlots() do
		local slotCount = GetContainerSlotCount(bag)
		for slot = 1, slotCount do
			local itemID, stackCount = GetBagItemInfo(bag, slot)
			if itemID and stackCount and stackCount > 0 then
				local value = GetTrackedItemValue(itemID)
				if value then
					worth = worth + (value * stackCount)
				end
			end
		end
	end
	return worth
end

function tracker:GetCharacterExpenseHistory(limit)
	limit = limit or 50
	local _, state = EnsureDailyState()
	local expenses = state.expenses or {}
	local result = {}
	for i = math.max(1, #expenses - limit + 1), #expenses do
		table.insert(result, expenses[i])
	end
	return result
end

function tracker:GetExpenseByCategory(category)
	local _, state = EnsureDailyState()
	return state.dailyExpenses and state.dailyExpenses[category] or 0
end

function tracker:ResetSessionTracking()
	sessionIncomeCopper = 0
	sessionExpenseCopper = 0
	sessionStartedAt = GetTime()
	lastMoneyCopper = GetMoney() or 0
	trackedInventoryCounts = SnapshotInventory()
end

function tracker:GetSessionGPH()
	local elapsed = GetSessionElapsed()
	if elapsed <= 0 then
		return 0
	end

	return math.floor((self:GetSessionNetIncome() / elapsed) * 3600 + 0.5)
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
		string.format('Session: %s', FormatCopperValue(self:GetSessionNetIncome())),
		string.format('Daily: %s', FormatCopperValue(self:GetDailyNetIncome()))
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
		sessionExpenseCopper = 0
		lastMoneyCopper = GetMoney() or 0
		trackedInventoryCounts = SnapshotInventory()
		wipe(pendingItemIncome)
		wipe(pendingItemExpense)
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
		if event == 'CHAT_MSG_LOOT' then
			ProcessLootMessage(arg1)
		end
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
			ResolvePendingItemExpense(arg1)
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
