local ledger = _G.ProkinMinimapLedger or {}
_G.ProkinMinimapLedger = ledger

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

local function GetCharacterLedger(characterKey)
	characterKey = characterKey or GetCharacterKey()
	local db = GetTrackerDB()
	if type(db.characters) ~= 'table' then
		return nil
	end

	return db.characters[characterKey]
end

local function GetAllCharacters()
	local db = GetTrackerDB()
	if type(db.characters) ~= 'table' then
		return {}
	end

	local characters = {}
	for key, state in pairs(db.characters) do
		if type(state) == 'table' then
			table.insert(characters, {
				key = key,
				state = state
			})
		end
	end
	return characters
end

function ledger:PrintCharacterLedger(characterKey)
	characterKey = characterKey or GetCharacterKey()
	local charState = GetCharacterLedger(characterKey)
	
	if not charState then
		print('No ledger data for ' .. characterKey)
		return
	end

	print('\n=== ' .. characterKey .. ' Ledger ===')
	print('Daily Total Income: ' .. FormatCopperValue(charState.dailyTotalCopper or 0))
	print('Daily Total Expense: ' .. FormatCopperValue(charState.dailyExpenseCopper or 0))
	print('Daily Net Income: ' .. FormatCopperValue((charState.dailyTotalCopper or 0) - (charState.dailyExpenseCopper or 0)))

	local breakdown = charState.dailyExpenses or {}
	if next(breakdown) then
		print('\n--- Expense Breakdown ---')
		for category, amount in pairs(breakdown) do
			print(string.format('  %s: %s', category, FormatCopperValue(amount)))
		end
	end
end

function ledger:PrintAllCharacters()
	local characters = GetAllCharacters()
	if #characters == 0 then
		print('No character ledger data available.')
		return
	end

	print('\n=== Cross-Character Ledger ===')
	local totalIncome = 0
	local totalExpense = 0

	for _, charData in ipairs(characters) do
		local state = charData.state
		local income = state.dailyTotalCopper or 0
		local expense = state.dailyExpenseCopper or 0
		local net = income - expense

		totalIncome = totalIncome + income
		totalExpense = totalExpense + expense

		print(string.format('%s: %s income, %s expense, %s net',
			charData.key,
			FormatCopperValue(income),
			FormatCopperValue(expense),
			FormatCopperValue(net)
		))
	end

	print('\n--- Totals ---')
	print('Total Income: ' .. FormatCopperValue(totalIncome))
	print('Total Expense: ' .. FormatCopperValue(totalExpense))
	print('Total Net: ' .. FormatCopperValue(totalIncome - totalExpense))
end

function ledger:PrintExpenseHistory(characterKey, limit)
	characterKey = characterKey or GetCharacterKey()
	limit = limit or 10
	
	local charState = GetCharacterLedger(characterKey)
	if not charState then
		print('No ledger data for ' .. characterKey)
		return
	end

	local expenses = charState.expenses or {}
	if #expenses == 0 then
		print('No expense history for ' .. characterKey)
		return
	end

	print('\n=== Recent Expenses for ' .. characterKey .. ' ===')
	for i = math.max(1, #expenses - limit + 1), #expenses do
		local expense = expenses[i]
		print(string.format('  [%s] %s: %s',
			expense.category,
			FormatCopperValue(expense.copper),
			date('%H:%M:%S', math.floor(expense.timestamp))
		))
	end
end

function ledger:GetCharacterNetWorth(characterKey)
	characterKey = characterKey or GetCharacterKey()
	local tracker = _G.ProkinMinimapGoldTracker
	
	if not tracker then
		return 0
	end

	local charState = GetCharacterLedger(characterKey)
	if not charState then
		return 0
	end

	local income = charState.dailyTotalCopper or 0
	local expense = charState.dailyExpenseCopper or 0
	return income - expense
end

function ledger:GetAllCharactersNetWorth()
	local characters = GetAllCharacters()
	local totalWorth = 0

	for _, charData in ipairs(characters) do
		local state = charData.state
		local income = state.dailyTotalCopper or 0
		local expense = state.dailyExpenseCopper or 0
		totalWorth = totalWorth + (income - expense)
	end

	return totalWorth
end

function ledger:ExportLedger(characterKey)
	characterKey = characterKey or GetCharacterKey()
	local charState = GetCharacterLedger(characterKey)
	
	if not charState then
		return '{}'
	end

	local export = {
		character = characterKey,
		dayKey = charState.dailyTotalDayKey or GetServerDayKey(),
		income = charState.dailyTotalCopper or 0,
		expense = charState.dailyExpenseCopper or 0,
		expenseBreakdown = charState.dailyExpenses or {},
		expenses = charState.expenses or {}
	}

	return export
end
