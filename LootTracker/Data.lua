local addonName, ns = ...
local API = ns.API

-- The Loot Tracker's settings and what the window shows: the tracked
-- records (Tracking.lua) turned into entries by source, in the chosen
-- scope, grouping and order, with their values; item tooltips; export.
-- The window itself is Window.lua.

local S = "lootTracker"

local DEFAULTS = {
	-- Tracking
	grouping = "grouped",        -- "grouped" (merged by ID) or "individual" (one entry per loot)
	scope = "all",               -- "all", "session" (this login) or "instance" (the current instance run)
	trackCreatures = true,
	skinningMerge = false,       -- skinning loot in the creature's own entry
	pickpocketMerge = false,     -- pickpocketing loot in the creature's own entry
	trackChests = true,
	trackLockboxes = true,
	trackDisenchant = true,      -- disenchanting's loot, in one "Disenchanted" entry
	confirmLoot = true,          -- an item counts once the game says you received it
	trackNodes = true,
	trackFishing = true,
	fishingGrouping = "zone",    -- "zone" (all of a zone's fishing) or "separated" (schools by type)
	-- Value
	itemValue = "auction",       -- "auction" (the last scan's lowest buyout, else vendor), "vendor" or "none"
	auctionAutoScan = false,     -- a full scan when the auction house opens (it can stall the game a moment)
	auctionBrowse = true,        -- browsing the auction house updates the prices it shows
	auctionButton = true,        -- a Scan button on the auction house's Buy page
	valueFallback = true,        -- items without an auction price at vendor value
	tooltipAuction = true,       -- item tooltip: auction price under Sell Price
	tooltipAuctionStack = true,  -- item tooltip: the looted stack's auction price too (x4)
	tooltipScanAge = true,       -- item tooltip: how old the price is
	tooltipEverywhere = false,   -- those lines in every item tooltip (bags, links, ...), not only ours
	-- The window
	itemSort = "quality",        -- a source's items: "quality", "newest" or "value"
	entrySort = "newest",        -- the sources: "newest" or "value"
	portraits = true,            -- the creature's model beside its name
	collapsed = false,           -- the window hidden (its close button)
	locked = false,              -- no dragging by the title, no resizing
	width = 300,
	height = 420,
}
API.RegisterDefaults(S, DEFAULTS)

local function Setting(key)
	return API.Get(S, key)
end

-- Entries ----------------------------------------------------------------------------

local QUALITY_ORDER = function(a, b)
	if (a.quality or 0) ~= (b.quality or 0) then
		return (a.quality or 0) > (b.quality or 0)
	end
	return (a.name or "") < (b.name or "")
end

local SUFFIX = { skinning = " (Skinning)", pickpocket = " (Pickpocketing)" }
local KILLS = { creature = true }

-- Where a record goes in the view, and the name it shows under.
local function Place(record)
	local kind, id = record.kind, record.id
	if kind == "creature" or kind == "skinning" or kind == "pickpocket" then
		-- The name learned for its ID, else "Creature <id>" until it is.
		local name = ns.CreatureName and ns.CreatureName(id, record.name)
		record = { kind = kind, id = id, name = name or ("Creature " .. tostring(id)) }
	elseif (kind == "chest" or kind == "node") and type(id) == "number" then
		-- The name learned for the object's ID, over a placeholder.
		local recorded = record.name
		if not recorded or recorded:find("^Chest %d+$") or recorded:find("^Node %d+$") then
			local name = ns.ObjectName and ns.ObjectName(id)
			if name then
				record = { kind = kind, id = id, name = name }
			end
		end
	end
	if kind == "skinning" or kind == "pickpocket" then
		local merge = Setting(kind == "skinning" and "skinningMerge" or "pickpocketMerge")
		if merge then
			return "creature:" .. tostring(id), record.name, "creature"
		end
		return kind .. ":" .. tostring(id), (record.name or "?") .. SUFFIX[kind], kind
	elseif kind == "fishing" then
		if record.school and Setting("fishingGrouping") == "separated" then
			return "school:" .. record.school, record.school, kind
		end
		return "fishing:" .. (record.zone or "?"), "Fishing: " .. (record.zone or "?"), kind
	end
	return kind .. ":" .. tostring(id), record.name or "?", kind
end

local function NewEntry(key, name, kind, record)
	return { key = key, name = name, kind = kind, id = record.id, count = 0, money = 0, items = {}, byKey = {}, last = 0 }
end

local function AddItem(entry, item, when)
	local key = ns.ItemID(item.link) or item.link or item.name
	local have = entry.byKey[key]
	if not have then
		have = { link = item.link, name = item.name, icon = item.icon, quality = item.quality, count = 0, last = 0 }
		entry.byKey[key] = have
		entry.items[#entry.items + 1] = have
	end
	have.count = have.count + item.count
	have.last = math.max(have.last, when or item.last or 0)
end

local SortView -- below, once item values can be read

-- The totals the chosen scope shows, and whether an event is in it.
local function ScopeTotals(db)
	local scope = Setting("scope")
	if scope == "session" then
		return db.sessionTotals or {}
	elseif scope == "instance" then
		return db.runTotals or {}
	end
	return db.totals
end

local function InScope(db, event)
	local scope = Setting("scope")
	if scope == "session" then
		return event.session ~= nil and event.session == db.session
	elseif scope == "instance" then
		return event.run ~= nil and db.run ~= nil and event.run == db.run.id
	end
	return true
end

-- The entries to show, newest first.
function ns.Entries()
	local db = ns.db
	local entries = {}
	if not db then
		return entries
	end
	if Setting("grouping") == "individual" then
		for i = #db.events, 1, -1 do
			local event = db.events[i]
			if InScope(db, event) then
			local key, name, kind = Place(event)
			local entry = NewEntry(key .. "#" .. i, name, kind, event)
			entry.event = event
			entry.money, entry.last = event.money, event.time or 0
			for _, item in ipairs(event.items) do
				AddItem(entry, item, event.time)
			end
			entries[#entries + 1] = entry
			end
		end
		SortView(entries, true)
		return entries
	end
	local byKey = {}
	for _, record in pairs(ScopeTotals(db)) do
		local key, name, kind = Place(record)
		local entry = byKey[key]
		if not entry then
			entry = NewEntry(key, name, kind, record)
			byKey[key] = entry
			entries[#entries + 1] = entry
		end
		if record.kind == entry.kind or not (record.kind == "skinning" or record.kind == "pickpocket") then
			entry.count = entry.count + record.count
		end
		entry.money = entry.money + record.money
		entry.last = math.max(entry.last, record.last or 0)
		for _, item in pairs(record.items) do
			AddItem(entry, item)
		end
	end
	SortView(entries)
	return entries
end

-- Deleting an entry (its X): grouped, every record and event it is made of,
-- in every scope; per loot, that one loot, taken out of the totals too.
local function GroupKey(record)
	return (Place(record))
end

function ns.DeleteEntry(entry)
	local db = ns.db
	if not (db and entry) then
		return
	end
	if entry.event then
		local event = entry.event
		for i = #db.events, 1, -1 do
			if db.events[i] == event then
				table.remove(db.events, i)
			end
		end
		ns.Subtract(db.totals, event)
		if event.session and event.session == db.session then
			ns.Subtract(db.sessionTotals, event)
		end
		if event.run and db.run and event.run == db.run.id then
			ns.Subtract(db.runTotals, event)
		end
	else
		for _, totals in ipairs({ db.totals, db.sessionTotals or {}, db.runTotals or {} }) do
			for key, record in pairs(totals) do
				if GroupKey(record) == entry.key then
					totals[key] = nil
				end
			end
		end
		for i = #db.events, 1, -1 do
			if GroupKey(db.events[i]) == entry.key then
				table.remove(db.events, i)
			end
		end
	end
	if db.folded then
		db.folded[entry.key] = nil
	end
	API.Fire("LootTrackerChanged")
end

-- Money and value --------------------------------------------------------------------

local function Money(copper)
	copper = math.floor(copper or 0)
	if GetMoneyString then
		return GetMoneyString(copper, true)
	elseif C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper)
	end
	return ("%dg %ds %dc"):format(copper / 10000, (copper / 100) % 100, copper % 100)
end

-- Short money: the largest coin only (12g, 34s, 56c); 10g and up rounded.
local function ShortMoney(copper)
	copper = math.floor(copper or 0)
	if copper >= 10000 then
		local gold = copper / 10000
		if gold >= 10 then
			return ("%dg"):format(math.floor(gold + 0.5))
		end
		return (("%.1fg"):format(math.floor(gold * 10) / 10):gsub("%.0g$", "g"))
	elseif copper >= 100 then
		return ("%ds"):format(math.floor(copper / 100))
	end
	return ("%dc"):format(copper)
end

-- An entry's value: its money, and with Vendor Value its items' sell price.
local function Value(entry)
	local value = entry.money
	local mode = Setting("itemValue")
	if mode == "vendor" or mode == "auction" then
		for _, item in ipairs(entry.items) do
			-- Auction Value: the last scan's lowest buyout, else what a vendor pays
			-- (soulbound and unlisted items).
			local price = mode == "auction" and ns.AuctionPrice and ns.AuctionPrice(item.link) or ns.SellPrice(item.link)
			if price then
				value = value + price * item.count
			end
		end
	end
	return value
end

-- One item stack's value: its count at the chosen price (auction, else
-- vendor); 0 with Item Value None or no price known.
local function ItemValue(item)
	local mode = Setting("itemValue")
	local price = mode == "auction" and ns.AuctionPrice and ns.AuctionPrice(item.link) or ns.SellPrice(item.link)
	return (price or 0) * (item.count or 0)
end

-- The items of each source as Item Sort says (Quality, Newest, Value), then
-- the sources as Source Sort says (Newest, Value). Per loot, sources stay
-- newest first unless sorted by value.
SortView = function(entries, perLoot)
	local itemSort = Setting("itemSort")
	for _, entry in ipairs(entries) do
		if itemSort == "value" then
			for _, item in ipairs(entry.items) do
				item.sortValue = ItemValue(item)
			end
			table.sort(entry.items, function(a, b)
				if a.sortValue ~= b.sortValue then
					return a.sortValue > b.sortValue
				end
				return QUALITY_ORDER(a, b)
			end)
		elseif itemSort == "newest" then
			table.sort(entry.items, function(a, b)
				if (a.last or 0) ~= (b.last or 0) then
					return (a.last or 0) > (b.last or 0)
				end
				return QUALITY_ORDER(a, b)
			end)
		else
			table.sort(entry.items, QUALITY_ORDER)
		end
	end
	if Setting("entrySort") == "value" then
		for _, entry in ipairs(entries) do
			entry.sortValue = Value(entry)
		end
		table.sort(entries, function(a, b)
			if a.sortValue ~= b.sortValue then
				return a.sortValue > b.sortValue
			end
			return a.last > b.last
		end)
	elseif not perLoot then
		table.sort(entries, function(a, b)
			if a.last ~= b.last then
				return a.last > b.last
			end
			return a.name < b.name
		end)
	end
end

local function QualityColor(quality)
	if quality and C_Item and C_Item.GetItemQualityColor then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if r then
			return r, g, b
		end
	end
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

-- Values on lines ---------------------------------------------------------------------

local function AuctionEach(link)
	local price = ns.AuctionPrice and ns.AuctionPrice(link)
	if price then
		return price, true
	end
	if Setting("valueFallback") then
		price = ns.SellPrice(link)
		if price and price > 0 then
			return price, false
		end
	end
	return nil
end

-- The value text for a line or an icon (its color: gold, or gray at
-- vendor value), or nil.
local function ValueText(link, count, each)
	local price, auction = AuctionEach(link)
	if not price then
		return nil
	end
	local copper = each and price or price * (count or 1)
	local text = Setting("valueShort") and ShortMoney(copper) or Money(copper)
	return text, auction
end

local function AgeText(seconds)
	if seconds < 3600 then
		return ("%d min ago"):format(math.max(1, math.floor(seconds / 60)))
	elseif seconds < 86400 then
		return ("%d h ago"):format(math.floor(seconds / 3600))
	end
	return ("%d days ago"):format(math.floor(seconds / 86400))
end

-- The auction price in an item's tooltip, styled as the game's own Sell
-- Price line and put right under it: a line post-call for
-- the Sell Price line, on tooltips of our item lines and icons only. An item
-- the game shows no sell price for gets it at the end instead.
local added = {} -- tooltips the lines went into while the game builds them

-- A money line like the Sell Price one: the label in white, then the coins
-- straight after it (as text with coin icons; a money frame of the game's
-- set its coins apart from the label).
local function MoneyLine(tooltip, label, copper)
	tooltip:AddLine(label .. " " .. Money(copper), 1, 1, 1)
end

-- The item a tooltip shows, and its count: our item lines and icons, or with
-- Every Item Tooltip any item tooltip (one item: other tooltips' stacks are
-- not ours to know).
local function TooltipItem(tooltip)
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	if type(owner) == "table" and owner.lootTrackerItem == true and type(owner.link) == "string" then
		return owner.link, owner.itemCount or 1
	end
	if Setting("tooltipEverywhere") and tooltip.GetItem then
		local ok, _, link = pcall(tooltip.GetItem, tooltip)
		if ok and link and not API.IsSecret(link) then
			return link, 1
		end
	end
end

local function AddAuctionLines(tooltip)
	local link, count = TooltipItem(tooltip)
	if not link then
		return
	end
	added[tooltip] = true
	local price = ns.AuctionPrice and ns.AuctionPrice(link)
	if not Setting("tooltipAuction") then
		-- (Last scan's age alone, below.)
	elseif price then
		MoneyLine(tooltip, "Auction Price:", price)
		if count > 1 and Setting("tooltipAuctionStack") then
			MoneyLine(tooltip, ("Auction Price (x%d):"):format(count), price * count)
		end
	else
		tooltip:AddLine("Auction Price: |cff999999" .. (ns.ScanInfo and ns.ScanInfo() and "not listed" or "no scan yet") .. "|r", 1, 1, 1)
	end
	if Setting("tooltipScanAge") and ns.ScanInfo then
		-- The price's own age (browsing sees items one by one), else the scan's.
		local seen = price and ns.AuctionTime and ns.AuctionTime(link) or ns.ScanInfo()
		if seen then
			tooltip:AddLine((price and "Price seen: " or "Last scan: ") .. AgeText(math.max(0, time() - seen)), 0.6, 0.6, 0.6)
		end
	end
end

local function OurTooltip(tooltip)
	return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

-- Right under the Sell Price line (a line post-call); an item the game shows
-- no sell price for gets them at the end (the item tooltip's post-call).
local hooked = false
if TooltipDataProcessor and TooltipDataProcessor.AddLinePostCall and Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice then
	hooked = pcall(TooltipDataProcessor.AddLinePostCall, Enum.TooltipDataLineType.SellPrice, function(tooltip) -- RETEST
		if OurTooltip(tooltip) then
			AddAuctionLines(tooltip)
		end
	end) and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType and Enum.TooltipDataType.Item and pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip) -- RETEST
		if OurTooltip(tooltip) then
			if not added[tooltip] then
				AddAuctionLines(tooltip)
			end
			added[tooltip] = nil
		end
	end) or false
end

local function ShowItemTooltip(self)
	if not self.link then
		return
	end
	self.lootTrackerItem = true
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	added[GameTooltip] = nil
	GameTooltip:SetHyperlink(self.link)
	if not hooked and not added[GameTooltip] then
		AddAuctionLines(GameTooltip)
	end
	added[GameTooltip] = nil
	GameTooltip:Show()
end

local PORTRAIT_ICONS = {
	chest = [[Interface\Icons\INV_Box_01]],
	node = [[Interface\Icons\Trade_Mining]],
	fishing = [[Interface\Icons\Trade_Fishing]],
	skinning = [[Interface\Icons\INV_Misc_Pelt_Wolf_01]],
	pickpocket = [[Interface\Icons\INV_Misc_Bag_11]],
	lockbox = [[Interface\Icons\INV_Misc_OrnateBox]],
	disenchant = [[Interface\Icons\INV_Enchant_Disenchant]],
	creature = [[Interface\Icons\INV_Misc_QuestionMark]],
}

local function Freeze(model)
	if model.FreezeAnimation then
		model:FreezeAnimation(0, 0, 0)
	elseif model.SetAnimation then
		model:SetAnimation(0)
		if model.SetPaused then
			model:SetPaused(true)
		end
	end
end

-- Entries whose loot is folded away (a click on the name), by entry key.
local function Folded(key)
	return ns.db and ns.db.folded and ns.db.folded[key] or false
end


-- Export: the entries as shown (scope, grouping) as plain text in a copy box.
local function PlainMoney(copper)
	copper = math.floor(copper or 0)
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local SCOPE_NAMES = { all = "All time", session = "This session", instance = "This instance" }

function ns.Export()
	local out = {}
	local scope = Setting("scope")
	local heading = "Loot Tracker: " .. (SCOPE_NAMES[scope] or scope)
	if scope == "instance" and ns.db and ns.db.run and ns.db.run.name then
		heading = heading .. " (" .. ns.db.run.name .. ")"
	end
	out[#out + 1] = heading
	local grand = 0
	for _, entry in ipairs(ns.Entries()) do
		local value = Value(entry)
		grand = grand + value
		local count = (Setting("grouping") ~= "individual" and entry.count > 1) and (" x" .. entry.count) or ""
		out[#out + 1] = ""
		out[#out + 1] = ("%s%s - money %s, value %s"):format(entry.name, count, PlainMoney(entry.money), PlainMoney(value))
		for _, item in ipairs(entry.items) do
			out[#out + 1] = ("  %s x%d"):format(item.name or (item.link and item.link:match("%[(.-)%]")) or "?", item.count)
		end
	end
	out[#out + 1] = ""
	out[#out + 1] = "Total value: " .. PlainMoney(grand)
	API.ShowCopyBox("Loot Tracker export", table.concat(out, "\n"))
end

if StaticPopupDialogs then
StaticPopupDialogs["LOOTTRACKER_RESET"] = {
	text = "Forget everything the Loot Tracker has tracked on this character?",
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function()
		ns.Reset()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}
end


local function SetScope(scope)
	API.Set(S, "scope", Setting("scope") == scope and "all" or scope)
end

-- For Window.lua.
ns.Setting, ns.Money, ns.ShortMoney, ns.Value, ns.ItemValue = Setting, Money, ShortMoney, Value, ItemValue
ns.QualityColor, ns.ValueText, ns.ShowItemTooltip = QualityColor, ValueText, ShowItemTooltip
ns.PORTRAIT_ICONS, ns.Freeze, ns.Folded, ns.SetScope = PORTRAIT_ICONS, Freeze, Folded, SetScope
