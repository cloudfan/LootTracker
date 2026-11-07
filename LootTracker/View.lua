local addonName, ns = ...
local API = ns.API

-- What the Loot Tracker shows: one entry per source (grouped by ID, or one
-- per loot), the source's name with its money (and the items' vendor value)
-- inline, and its items as a list (colored by quality, count on the right)
-- or a grid of icons; every item shows its tooltip on hover.
--
-- It lives in a frame of its own (LootTracker, on a mover) with an
-- arrow beside it that pops it out and hides it, or in a tab of the Data
-- Box (API.RegisterBoxPanel) while the Data Box module is on.

local S = "lootTracker"

API.RegisterDefaults(S, {
	-- Tracking
	grouping = "grouped",        -- "grouped" (merged by ID) or "individual" (one entry per loot)
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
	-- View
	itemValue = "vendor",        -- "vendor", "auction" (the last scan's lowest buyout) or "none"
	auctionAutoScan = false,     -- a full scan when the auction house opens (it can stall the game a moment)
	auctionBrowse = true,        -- browsing the auction house updates the prices it shows
	auctionButton = true,        -- a Scan button on the auction house's Buy page
	-- Per-item auction value, each a toggle.
	lineValue = true,            -- List view: each line's stack at its auction price
	lineValueEach = false,       -- List view: one item's auction price on each line
	iconValue = false,           -- Icons view: the stack's auction value on each icon
	valueShort = true,           -- those in short form (12g, 34s, 56c) instead of coins
	valueFallback = true,        -- items without an auction price at vendor value, in gray
	tooltipAuction = true,       -- item tooltip: auction price (each, and the stack), under Sell Price
	tooltipAuctionStack = true,  -- item tooltip: the looted stack's auction price too (x4)
	tooltipScanAge = true,
	tooltipEverywhere = false,   -- those lines in every item tooltip (bags, links, ...), not only ours       -- item tooltip: how old the last scan is
	-- Text: "global" (and size 0) follow Global Settings.
	font = "global",
	fontSize = 0,                -- 0: the tracker's own sizes; else the lines' size, the rest in step
	fontShadow = "global",
	view = "list",               -- "list" or "icons"
	listIcons = true,
	scrollBar = true,            -- a scroll bar while the list is longer than the frame
	scrollBarWidth = 6,
	itemSort = "quality",        -- a source's items: "quality", "newest" or "value"
	entrySort = "newest",        -- the sources: "newest" or "value"
	-- List view: bars behind the item lines and the source rows.
	lineBars = false,
	lineBarTexture = "global",   -- a SharedMedia statusbar, or "global" (Global Settings' Bar Texture)
	lineBarColorMode = "quality", -- "quality" (the item's) or "custom" (Line Bar Color)
	lineBarColor = { preset = "custom", r = 0.5, g = 0.5, b = 0.5, a = 1 },
	lineBarAlpha = 0.25,
	lineBarLength = "full",      -- "full", or "count" (by the item's count against the entry's most)
	headerBars = false,          -- in both views
	headerBarTexture = "global",
	headerBarColor = { preset = "custom", r = 0.55, g = 0.42, b = 0.2, a = 1 },
	headerBarAlpha = 0.35,
	iconSize = 28,
	portraits = false,           -- experimental: the source's portrait before its name
	-- Placement
	placement = "own",           -- "own" (a frame of its own) or "databox" (a tab of the Data Box)
	collapsed = false,
	scope = "all",               -- "all", "session" (this login) or "instance" (the current instance run)
	arrowSide = "RIGHT",         -- the side of the frame its arrow sits on
	width = 260,
	height = 320,
	border = true,
	background = "global",
	backgroundAlpha = 0.8,
})

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

-- Frames -----------------------------------------------------------------------------

-- In the Data Box only while the Data Box module is on.
local function InBox()
	return Setting("placement") == "databox" and API.IsModuleLoaded("DataBox")
end

function ns.OwnFrame()
	return not InBox()
end


local panel = CreateFrame("Frame", "LootTracker", UIParent)
panel:SetFrameStrata("MEDIUM")
panel:SetSize(260, 320)
panel:SetClampedToScreen(true)
panel.border = API.CreateInsetBorder(panel, { gap = 0 })
API.RegisterAnchor("lootTracker:frame", "Loot Tracker", "Loot Tracker", function()
	return panel
end)
local mover = API.RegisterMover(panel, S, "Loot Tracker", { "RIGHT", UIParent, "RIGHT", -40, 0 }, ns.OwnFrame)

-- What moves into the Data Box: the title, the total and the list.
local content = CreateFrame("Frame", "LootTrackerContent", panel)
local title = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOPLEFT", 4, -2)
title:SetText("Loot")
-- The title's arrow: a menu to reset, choose the scope and export.
local menuButton = CreateFrame("Button", "LootTrackerMenu", content)
menuButton:SetSize(16, 16)
menuButton:SetPoint("LEFT", title, "RIGHT", 2, 0)
menuButton.arrow = menuButton:CreateTexture(nil, "ARTWORK")
menuButton.arrow:SetSize(12, 12)
menuButton.arrow:SetPoint("CENTER")
menuButton.arrow:SetAtlas("common-dropdown-icon-next")
menuButton.arrow:SetRotation(-math.pi / 2)
menuButton.highlight = menuButton:CreateTexture(nil, "HIGHLIGHT")
menuButton.highlight:SetAllPoints()
menuButton.highlight:SetColorTexture(1, 1, 1, 0.12)
local scopeText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scopeText:SetPoint("LEFT", menuButton, "RIGHT", 2, 0)
local total = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
total:SetPoint("TOPRIGHT", -4, -2)
total:SetJustifyH("RIGHT")
local scroll = CreateFrame("ScrollFrame", nil, content)
scroll:SetPoint("TOPLEFT", 0, -20)
scroll:SetPoint("BOTTOMRIGHT", 0, 0)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(1, 1)
scroll:SetScrollChild(list)
local empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
empty:SetPoint("TOPLEFT", 4, -4)
empty:SetText("Nothing looted yet.")

-- The arrow that pops the frame out and hides it.
local toggle = CreateFrame("Button", "LootTrackerToggle", UIParent)
toggle:SetFrameStrata("MEDIUM")
toggle.arrow = toggle:CreateTexture(nil, "ARTWORK")
toggle.arrow:SetSize(14, 14)
toggle.arrow:SetPoint("CENTER")
toggle.arrow:SetAtlas("common-dropdown-icon-next")
toggle.highlight = toggle:CreateTexture(nil, "HIGHLIGHT")
toggle.highlight:SetAllPoints()
toggle.highlight:SetColorTexture(1, 1, 1, 0.12)
toggle:SetScript("OnClick", function()
	API.Set(S, "collapsed", not Setting("collapsed"))
end)
toggle:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, "Loot Tracker")
	GameTooltip_AddNormalLine(GameTooltip, Setting("collapsed") and "Click to show." or "Click to hide.")
	GameTooltip:Show()
end)
toggle:SetScript("OnLeave", GameTooltip_Hide)

-- Pools of rows.
local headers, lines, icons = {}, {}, {}

-- Text in the chosen font, size and shadow ("global": Global Settings').
-- Sizes are given at the lines' size of 12; Text Size moves them all.
local function Font(fontString, size)
	local font, shadow, lineSize = Setting("font"), Setting("fontShadow"), Setting("fontSize")
	API.ApplyFont(fontString, {
		font = font ~= "global" and font or nil,
		size = lineSize > 0 and math.max(6, size + lineSize - 12) or size,
		shadow = shadow ~= "global" and shadow or nil,
		color = false,
	})
end

-- One item's auction price, and whether it is one (false: the vendor
-- price standing in with Vendor Fallback); nil with neither.
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
	hooked = pcall(TooltipDataProcessor.AddLinePostCall, Enum.TooltipDataLineType.SellPrice, function(tooltip)
		if OurTooltip(tooltip) then
			AddAuctionLines(tooltip)
		end
	end) and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType and Enum.TooltipDataType.Item and pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip)
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

local Render -- below

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

menuButton:SetScript("OnClick", function(self)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	MenuUtil.CreateContextMenu(self, function(_, root)
		root:CreateTitle("Loot Tracker")
		root:CreateCheckbox("Track This Session Only", function()
			return Setting("scope") == "session"
		end, function()
			SetScope("session")
		end)
		root:CreateCheckbox("Track This Instance Only", function()
			return Setting("scope") == "instance"
		end, function()
			SetScope("instance")
		end)
		root:CreateDivider()
		root:CreateButton("Export...", function()
			ns.Export()
		end)
		root:CreateButton("Export Name Database...", function()
			ns.ExportNames()
		end)
		root:CreateButton("|cffff5040Reset All...|r", function()
			StaticPopup_Show("LOOTTRACKER_RESET")
		end)
	end)
end)
menuButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, "Loot Tracker")
	GameTooltip_AddNormalLine(GameTooltip, "Reset, track this session or this instance only, or export.")
	GameTooltip:Show()
end)
menuButton:SetScript("OnLeave", GameTooltip_Hide)

local function Header(i)
	local header = headers[i]
	if header then
		return header
	end
	header = CreateFrame("Button", nil, list)
	header.name = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	header.name:SetJustifyH("LEFT")
	header.name:SetWordWrap(false)
	header.value = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	header.value:SetJustifyH("RIGHT")
	header.bar = header:CreateTexture(nil, "BACKGROUND")
	header.bar:SetAllPoints()
	header.bar:Hide()
	header.line = header:CreateTexture(nil, "ARTWORK")
	header.line:SetPoint("BOTTOMLEFT")
	header.line:SetPoint("BOTTOMRIGHT")
	header.line:SetHeight(1)
	header.line:SetColorTexture(API.BRONZE[1], API.BRONZE[2], API.BRONZE[3], 0.5)
	-- The portrait (experimental): a round icon, or the creature's model
	-- in the unit frames' ring.
	header.portrait = CreateFrame("Frame", nil, header)
	header.portrait:SetSize(20, 20)
	header.portrait:SetPoint("LEFT", 0, 0)
	header.icon = header.portrait:CreateTexture(nil, "ARTWORK")
	header.icon:SetAllPoints()
	header.mask = header.portrait:CreateMaskTexture()
	header.mask:SetAllPoints()
	header.mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	header.icon:AddMaskTexture(header.mask)
	header.model = CreateFrame("PlayerModel", nil, header.portrait)
	header.model:SetPoint("TOPLEFT", 3, -3)
	header.model:SetPoint("BOTTOMRIGHT", -3, 3)
	-- Still, not animated: frozen on its first frame once loaded.
	header.model:SetScript("OnModelLoaded", Freeze)
	header.ring = header.portrait:CreateTexture(nil, "OVERLAY")
	header.ring:SetTexture([[Interface\AddOns\LootTracker\Media\PortraitRing]])
	header.ring:SetAllPoints()
	header:SetScript("OnEnter", function(self)
		local entry = self.entry
		if not entry then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, entry.name)
		-- Its ID: an NPC's, a world object's or a container item's.
		local id = entry.id
		if type(id) == "number" and id > 0 then
			local label = (entry.kind == "creature" or entry.kind == "skinning" or entry.kind == "pickpocket") and "NPC ID"
				or entry.kind == "lockbox" and "Item ID" or "Object ID"
			GameTooltip:AddDoubleLine(label, tostring(id), 0.6, 0.6, 0.6, 1, 1, 1)
		elseif type(id) == "string" and ns.NODE_GROUPS then
			local ids = {}
			for objectID, group in pairs(ns.NODE_GROUPS) do
				if group == id then
					ids[#ids + 1] = objectID
				end
			end
			table.sort(ids)
			if #ids > 0 then
				GameTooltip:AddDoubleLine("Object IDs", table.concat(ids, ", "), 0.6, 0.6, 0.6, 1, 1, 1)
			end
		end
		if Setting("grouping") ~= "individual" then
			GameTooltip_AddNormalLine(GameTooltip, (KILLS[entry.kind] and "Kills: %d" or "Times looted: %d"):format(entry.count))
		end
		GameTooltip:AddDoubleLine("Money", Money(entry.money), 1, 0.82, 0, 1, 1, 1)
		if Setting("itemValue") == "vendor" then
			GameTooltip:AddDoubleLine("Vendor Value", Money(Value(entry)), 1, 0.82, 0, 1, 1, 1)
		elseif Setting("itemValue") == "auction" then
			GameTooltip:AddDoubleLine("Auction Value", Money(Value(entry)), 1, 0.82, 0, 1, 1, 1)
		end
		GameTooltip_AddInstructionLine(GameTooltip, Folded(entry.key) and "Click to show its loot." or "Click to hide its loot.")
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	-- The X: deletes the entry.
	header.close = CreateFrame("Button", nil, header)
	header.close:SetSize(14, 14)
	header.close:SetPoint("RIGHT", header, "RIGHT", -1, 0)
	header.close.text = header.close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	header.close.text:SetPoint("CENTER", 0, 0)
	header.close.text:SetText("x")
	header.close.text:SetTextColor(0.6, 0.6, 0.6)
	header.close:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 0.25, 0.2)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, "Delete")
		GameTooltip_AddNormalLine(GameTooltip, Setting("grouping") == "individual" and "Forget this loot." or "Forget this entry and all its loot.")
		GameTooltip:Show()
	end)
	header.close:SetScript("OnLeave", function(self)
		self.text:SetTextColor(0.6, 0.6, 0.6)
		GameTooltip_Hide()
	end)
	header.close:SetScript("OnClick", function(self)
		GameTooltip_Hide()
		ns.DeleteEntry(self:GetParent().entry)
	end)
	-- A click folds the entry's loot away, or opens it again.
	header:SetScript("OnClick", function(self)
		local entry, db = self.entry, ns.db
		if not (entry and db) then
			return
		end
		db.folded = db.folded or {}
		db.folded[entry.key] = not db.folded[entry.key] or nil
		Render()
		if self:IsMouseOver() then
			self:GetScript("OnEnter")(self)
		end
	end)
	headers[i] = header
	return header
end

local function Line(i)
	local line = lines[i]
	if line then
		return line
	end
	line = CreateFrame("Button", nil, list)
	-- The background bar (List view, a setting).
	line.bar = line:CreateTexture(nil, "BACKGROUND")
	line.bar:SetPoint("TOPLEFT")
	line.bar:SetPoint("BOTTOMLEFT")
	line.bar:Hide()
	line.icon = line:CreateTexture(nil, "ARTWORK")
	line.icon:SetPoint("LEFT")
	line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	line.name = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line.name:SetJustifyH("LEFT")
	line.name:SetWordWrap(false)
	line.count = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line.count:SetPoint("RIGHT", -2, 0)
	line.count:SetJustifyH("RIGHT")
	line.value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line.value:SetPoint("RIGHT", line.count, "LEFT", -6, 0)
	line.value:SetJustifyH("RIGHT")
	line.name:SetPoint("RIGHT", line.count, "LEFT", -6, 0)
	line.highlight = line:CreateTexture(nil, "HIGHLIGHT")
	line.highlight:SetAllPoints()
	line.highlight:SetColorTexture(1, 1, 1, 0.08)
	line:SetScript("OnEnter", ShowItemTooltip)
	line:SetScript("OnLeave", GameTooltip_Hide)
	lines[i] = line
	return line
end

local function Icon(i)
	local button = icons[i]
	if button then
		return button
	end
	button = CreateFrame("Button", nil, list)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.edge = button:CreateTexture(nil, "OVERLAY")
	button.edge:SetTexture([[Interface\Common\WhiteIconFrame]])
	button.edge:SetAllPoints()
	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.count:SetPoint("BOTTOMRIGHT", -1, 2)
	button.count:SetJustifyH("RIGHT")
	button.value = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.value:SetPoint("TOPLEFT", 1, -2)
	button.value:SetJustifyH("LEFT")
	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.highlight:SetAllPoints()
	button.highlight:SetColorTexture(1, 1, 1, 0.15)
	button:SetScript("OnEnter", ShowItemTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	icons[i] = button
	return button
end

local function SetPortrait(header, entry)
	local on = Setting("portraits") and true or false
	header.portrait:SetShown(on)
	if not on then
		return 0
	end
	local creature = (entry.kind == "creature" or entry.kind == "skinning" or entry.kind == "pickpocket") and type(entry.id) == "number"
	header.icon:SetShown(not creature)
	header.ring:SetShown(creature)
	if creature then
		if header.modelID ~= entry.id then
			header.modelID = entry.id
			header.model:Hide() -- shown again, with its creature, by ClipModels
		end
	else
		header.modelID = nil
		local texture = PORTRAIT_ICONS[entry.kind]
		if entry.kind == "lockbox" and type(entry.id) == "number" and entry.id > 0 and C_Item and C_Item.GetItemIconByID then
			texture = C_Item.GetItemIconByID(entry.id) or texture
		elseif entry.kind == "node" and entry.items[1] then
			texture = entry.items[1].icon or texture
		end
		header.icon:SetTexture(texture)
	end
	return 24
end

-- Models draw outside a scroll frame's bounds: each shows only while its
-- whole row is in view.
local function ClipModels()
	local top, bottom = scroll:GetTop(), scroll:GetBottom()
	for _, header in ipairs(headers) do
		local wanted = header:IsShown() and header.portrait:IsShown() and header.ring:IsShown() and header.modelID
		local inside = wanted and top and bottom and header:GetTop() and header:GetTop() <= top + 0.5
			and header:GetBottom() >= bottom - 0.5
		if inside and not header.model:IsShown() then
			header.model:Show()
			header.model:SetCreature(header.modelID)
			header.model:SetPortraitZoom(1)
			Freeze(header.model)
		elseif not inside then
			header.model:Hide()
		end
	end
end

-- Lay the list out ------------------------------------------------------------------

local HEADER_H, LINE_H, GAP = 20, 16, 6

local scrollBar -- below: the list's scroll bar

-- The bars' texture: the chosen statusbar, or Global Settings' Bar Texture.
local function BarTexturePath(key)
	local texture = Setting(key or "lineBarTexture")
	if texture == "global" then
		texture = API.Get("global", "barTexture")
	end
	return API.Fetch(API.MEDIA.STATUSBAR, texture) or [[Interface\TargetingFrame\UI-StatusBar]]
end

Render = function()
	local width = math.max(60, scroll:GetWidth())
	list:SetWidth(width)
	Font(title, 14)
	title:SetTextColor(1, 0.82, 0)
	Font(total, 12)
	Font(scopeText, 10)
	scopeText:SetTextColor(0.7, 0.7, 0.7)
	local scope = Setting("scope")
	local runName = scope == "instance" and ns.db and ns.db.run and ns.db.run.name
	scopeText:SetText(scope == "all" and "" or (runName or SCOPE_NAMES[scope] or ""))
	local entries = ns.Entries()
	local grand = 0
	local y = 0
	local h, l, c = 0, 0, 0
	local size = Setting("iconSize")
	local listView = Setting("view") ~= "icons"
	local withIcons = Setting("listIcons")
	for _, entry in ipairs(entries) do
		local value = Value(entry)
		grand = grand + value
		h = h + 1
		local header = Header(h)
		header.entry = entry
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
		header:SetSize(width, HEADER_H)
		local left = SetPortrait(header, entry)
		Font(header.name, 12)
		local folded = Folded(entry.key)
		local items = folded and {} or entry.items
		header.name:SetTextColor(1, 0.82, 0)
		local count = (Setting("grouping") ~= "individual" and entry.count > 1) and (" |cffb0b0b0x%d|r"):format(entry.count) or ""
		header.name:SetText((folded and "|cff909090+|r " or "") .. entry.name .. count)
		Font(header.value, 11)
		header.value:SetTextColor(1, 1, 1)
		header.value:SetText(value > 0 and Money(value) or "")
		header.value:ClearAllPoints()
		header.value:SetPoint("RIGHT", header.close, "LEFT", -3, 0)
		header.name:ClearAllPoints()
		header.name:SetPoint("LEFT", header, "LEFT", left + 2, 0)
		header.name:SetPoint("RIGHT", header.value, "LEFT", -6, 0)
		local headerBars = Setting("headerBars")
		if headerBars then
			header.bar:SetTexture(BarTexturePath("headerBarTexture"))
			local r, g, b = API.ResolveColor(Setting("headerBarColor"))
			header.bar:SetVertexColor(r, g, b, Setting("headerBarAlpha"))
		end
		header.bar:SetShown(headerBars and true or false)
		header:Show()
		y = y + HEADER_H + 2
		local lineBars = listView and Setting("lineBars")
		local barPath, most, byCount, customR, customG, customB
		if lineBars then
			barPath = BarTexturePath()
			byCount = Setting("lineBarLength") == "count"
			most = 1
			for _, item in ipairs(items) do
				most = math.max(most, item.count or 0)
			end
			if Setting("lineBarColorMode") == "custom" then
				customR, customG, customB = API.ResolveColor(Setting("lineBarColor"))
			end
		end
		local showStack, showEach = Setting("lineValue"), Setting("lineValueEach")
		if listView then
			for _, item in ipairs(items) do
				l = l + 1
				local line = Line(l)
				line.link = item.link
				line:ClearAllPoints()
				line:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -y)
				line:SetSize(width - 8, LINE_H)
				line.icon:SetShown(withIcons and true or false)
				line.icon:SetSize(LINE_H - 2, LINE_H - 2)
				line.icon:SetTexture(item.icon)
				Font(line.name, 12)
				Font(line.count, 12)
				line.name:SetTextColor(QualityColor(item.quality))
				line.name:SetText(item.name or item.link or "?")
				line.name:ClearAllPoints()
				line.name:SetPoint("LEFT", line, "LEFT", withIcons and LINE_H + 2 or 0, 0)
				line.count:SetTextColor(1, 1, 1)
				line.count:SetText("x" .. item.count)
				line.itemCount = item.count
				-- Auction value: the stack's, one item's, or both ("1.2g (12s)").
				local text, auction
				if showStack or showEach then
					local stack, each
					stack, auction = ValueText(item.link, item.count, false)
					each = ValueText(item.link, item.count, true)
					if stack and showStack and showEach and (item.count or 1) > 1 then
						text = ("%s (%s)"):format(stack, each)
					elseif stack then
						text = showStack and stack or each
					end
				end
				Font(line.value, 11)
				if text then
					line.value:SetText(text)
					if auction then
						line.value:SetTextColor(1, 0.82, 0)
					else
						line.value:SetTextColor(0.6, 0.6, 0.6)
					end
					line.value:Show()
					line.name:SetPoint("RIGHT", line.value, "LEFT", -6, 0)
				else
					line.value:SetText("")
					line.value:Hide()
					line.name:SetPoint("RIGHT", line.count, "LEFT", -6, 0)
				end
				if lineBars then
					line.bar:SetTexture(barPath)
					local r, g, b = customR, customG, customB
					if not r then
						r, g, b = QualityColor(item.quality)
					end
					line.bar:SetVertexColor(r, g, b, Setting("lineBarAlpha"))
					local share = byCount and math.max(0.02, (item.count or 0) / most) or 1
					line.bar:SetWidth(math.max(1, (width - 8) * share))
				end
				line.bar:SetShown(lineBars and true or false)
				line:Show()
				y = y + LINE_H
			end
		else
			local iconValue = Setting("iconValue")
			local perRow = math.max(1, math.floor((width - 8) / (size + 3)))
			for index, item in ipairs(items) do
				c = c + 1
				local button = Icon(c)
				button.link = item.link
				local col, row = (index - 1) % perRow, math.floor((index - 1) / perRow)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", list, "TOPLEFT", 8 + col * (size + 3), -(y + row * (size + 3)))
				button:SetSize(size, size)
				button.icon:SetTexture(item.icon)
				button.edge:SetVertexColor(QualityColor(item.quality))
				Font(button.count, math.max(9, math.floor(size * 0.4)))
				button.count:SetTextColor(1, 1, 1)
				button.count:SetText(item.count > 1 and item.count or "")
				button.itemCount = item.count
				local text, auction
				if iconValue then
					text, auction = ValueText(item.link, item.count, false)
				end
				if text then
					Font(button.value, math.max(8, math.floor(size * 0.32)))
					button.value:SetText(text)
					if auction then
						button.value:SetTextColor(1, 0.82, 0)
					else
						button.value:SetTextColor(0.6, 0.6, 0.6)
					end
				else
					button.value:SetText("")
				end
				button.value:SetShown(text and true or false)
				button:Show()
			end
			if #items > 0 then
				y = y + math.ceil(#items / perRow) * (size + 3)
			end
		end
		y = y + GAP
	end
	for i = h + 1, #headers do
		headers[i]:Hide()
		headers[i].entry = nil
	end
	for i = l + 1, #lines do
		lines[i]:Hide()
	end
	for i = c + 1, #icons do
		icons[i]:Hide()
	end
	Font(empty, 12)
	empty:SetTextColor(0.7, 0.7, 0.7)
	empty:SetShown(#entries == 0)
	list:SetHeight(math.max(1, y))
	total:SetText(grand > 0 and Money(grand) or "")
	scrollBar:Update(y)
	if not Setting("scrollBar") then
		scrollBar:Hide()
	end
	ClipModels()
end

-- The scroll bar (ns.API's): it takes the mouse wheel too, and the
-- portraits are clipped again whenever it moves.
scrollBar = API.NewScrollBar(content, scroll, 6, 40, function()
	ClipModels()
end)

local function PlaceScrollBar()
	local shown = Setting("scrollBar") and true or false
	local width = Setting("scrollBarWidth")
	scrollBar:SetWidth(width)
	scrollBar.thumb:SetWidth(width)
	scrollBar:ClearAllPoints()
	scrollBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -20)
	scrollBar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
	-- The list keeps room for the bar while it is on, so a bar coming and
	-- going never changes the list's width.
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -20)
	scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", shown and -(width + 3) or 0, 0)
end
scroll:SetScript("OnSizeChanged", function()
	if content:IsVisible() then
		Render()
	end
end)
content:SetScript("OnShow", function()
	Render()
end)

local renderPending = false
local function RenderSoon()
	if renderPending then
		return
	end
	renderPending = true
	C_Timer.After(0.1, function()
		renderPending = false
		if content:IsVisible() then
			Render()
		end
	end)
end

-- Placement --------------------------------------------------------------------------

local previewing = false

local function OwnPlacement()
	content:SetParent(panel)
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
	content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
	content:Show()
end

-- The arrow on the frame's chosen side, pointing out while hidden and back
-- while shown.
local ROTATION = { RIGHT = 0, LEFT = math.pi, TOP = math.pi / 2, BOTTOM = -math.pi / 2 }
local OPPOSITE = { RIGHT = "LEFT", LEFT = "RIGHT", TOP = "BOTTOM", BOTTOM = "TOP" }
local REACH = API.InsetBorderReach(0)

local function PlaceToggle()
	local side = Setting("arrowSide")
	local vertical = side == "LEFT" or side == "RIGHT"
	toggle:SetSize(vertical and 16 or 40, vertical and 40 or 16)
	toggle:ClearAllPoints()
	local dx = side == "RIGHT" and REACH + 4 or side == "LEFT" and -(REACH + 4) or 0
	local dy = side == "TOP" and REACH + 4 or side == "BOTTOM" and -(REACH + 4) or 0
	toggle:SetPoint(OPPOSITE[side], panel, side, dx, dy)
	local rotation = ROTATION[side] or 0
	toggle.arrow:SetRotation(Setting("collapsed") and rotation or rotation + math.pi)
end

local function Apply()
	-- Unlocked (/loot unlock): shown, even folded away, so it can be dragged.
	previewing = not API.Get("loot", "locked")
	if ns.standingDown then
		panel:Hide()
		toggle:Hide()
		return
	end
	PlaceScrollBar()
	panel:SetSize(Setting("width"), Setting("height"))
	panel.border:SetShown(Setting("border") and true or false)
	panel.border:SetBackground(Setting("background"), Setting("backgroundAlpha"))
	if InBox() then
		panel:Hide()
		toggle:Hide()
	else
		OwnPlacement()
		panel:SetShown((previewing or not Setting("collapsed")) and true or false)
		PlaceToggle()
		toggle:Show()
	end
	API.RefreshMover(mover)
	API.Fire("BoxPanelsChanged")
	RenderSoon()
end

API.RegisterBoxPanel({
	key = "lootTracker",
	label = "Loot",
	frame = content,
	wanted = InBox,
	attach = function(parent)
		content:SetParent(parent)
		content:ClearAllPoints()
		content:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
		content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
		RenderSoon()
	end,
	detach = function()
		OwnPlacement()
		Apply()
	end,
})

API.OnReady(Apply)
API.Listen("SettingChanged", function(section, key)
	if section == S then
		Apply()
	elseif section == "global" then
		RenderSoon()
	end
end)
API.Listen("ProfileChanged", Apply)
API.Listen("LootTrackerChanged", RenderSoon)
API.Listen("StandDown", function()
	panel:Hide()
	toggle:Hide()
end)
API.Listen("MoversShown", function(shown)
	shown = shown and true or false
	if previewing ~= shown then
		previewing = shown
		Apply()
	end
end)
