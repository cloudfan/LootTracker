local addonName, ns = ...
local API = ns.API

-- The auction house scanner: the Loot Tracker's Auction Value. At the
-- auction house, C_AuctionHouse.ReplicateItems asks for every auction on the
-- realm (the game allows it once every 15 minutes); when the list arrives
-- (REPLICATE_ITEM_LIST_UPDATE) it is read a slice at a time, so the game
-- does not stall, and each item's lowest buyout per unit is kept. Prices are
-- kept per realm, account-wide, in LootTrackerPrices, with the
-- time of the scan. A list another addon asked for is read the same way.
-- Browsing (a setting, on) updates the prices it shows without a full scan:
-- the Buy page's results (lowest price per unit), and the listings of an
-- item or commodity opened from them, each item with the time it was seen.
-- A Scan button of ours sits on the Buy page's search bar.

local S = "lootTracker"
local COOLDOWN = 15 * 60 -- seconds between full scans, the game's own limit
local BUDGET = 4         -- milliseconds of reading per frame, so the game keeps its frame rate
local SLICE = 250        -- auctions read between looks at the clock
local TIMEOUT = 90       -- seconds to wait for the list before giving up

local function Setting(key)
	return API.Get(S, key)
end

local function Realm()
	return (GetRealmName and GetRealmName()) or "?"
end

local function Store()
	LootTrackerPrices = LootTrackerPrices or {}
	local realm = Realm()
	local store = LootTrackerPrices[realm]
	if not store then
		store = { prices = {}, time = 0 }
		LootTrackerPrices[realm] = store
	end
	store.times = store.times or {} -- by item ID: when browsing last saw it
	return store
end

-- The lowest buyout for one of an item on this realm at the last scan, or nil.
function ns.AuctionPrice(link)
	local id = ns.ItemID(link)
	if not id or type(LootTrackerPrices) ~= "table" then
		return nil
	end
	local store = LootTrackerPrices[Realm()]
	return store and store.prices[id]
end

-- When an item's price was last seen: browsing's time for it, else the
-- full scan's; nil with neither.
function ns.AuctionTime(link)
	local id = ns.ItemID(link)
	local store = id and type(LootTrackerPrices) == "table" and LootTrackerPrices[Realm()]
	if not store then
		return nil
	end
	local seen = store.times and store.times[id]
	if seen and seen > (store.time or 0) then
		return seen
	end
	return store.time ~= 0 and store.time or seen
end

local function Available()
	return C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems
		and C_AuctionHouse.GetReplicateItemInfo and true or false
end

local atAuctionHouse = false
local scanning = false
local requestedAt -- GetTime() of the last scan asked for this session
local reading = false -- a list is being read

-- Seconds until a full scan may run again (0: now).
function ns.ScanWait()
	if not requestedAt then
		return 0
	end
	return math.max(0, math.ceil(requestedAt + COOLDOWN - GetTime()))
end

function ns.ScanState()
	if scanning then
		return "scanning"
	elseif not Available() then
		return "unavailable"
	elseif not atAuctionHouse then
		return "closed"
	elseif ns.ScanWait() > 0 then
		return "waiting"
	end
	return "ready"
end

function ns.ScanInfo()
	local store = type(LootTrackerPrices) == "table" and LootTrackerPrices[Realm()]
	if not store or (store.time == 0 and not next(store.prices)) then
		return nil
	end
	if not store.count then -- counted once, then kept up to date
		local count = 0
		for _ in pairs(store.prices) do
			count = count + 1
		end
		store.count = count
	end
	return store.time ~= 0 and store.time or nil, store.count
end

-- Ask for every auction. Only at the auction house, once per cooldown.
function ns.Scan(quiet)
	if ns.ScanState() ~= "ready" then
		if not quiet then
			local state = ns.ScanState()
			API.Print(state == "waiting" and ("the next auction house scan can run in %d:%02d."):format(ns.ScanWait() / 60, ns.ScanWait() % 60)
				or state == "closed" and "open the auction house to scan it."
				or state == "scanning" and "the auction house scan is still running."
				or "this game build has no auction house scan (C_AuctionHouse.ReplicateItems).")
		end
		return
	end
	requestedAt = GetTime()
	scanning = true
	local asked = requestedAt
	API.Fire("LootTrackerScan")
	API.Print("scanning the auction house...")
	C_AuctionHouse.ReplicateItems()
	-- The game may send nothing (another addon scanned in the last 15
	-- minutes): stop waiting rather than stay "scanning".
	C_Timer.After(TIMEOUT, function()
		if scanning and requestedAt == asked and not reading then
			scanning = false
			API.Print("the auction house sent no list (another scan may have run in the last 15 minutes); try again later.")
			API.Fire("LootTrackerScan")
		end
	end)
end

-- Read the list a slice per frame; each item's lowest buyout per unit.
local function Read()
	reading = true
	scanning = true
	local total = C_AuctionHouse.GetNumReplicateItems() or 0
	local lowest = {}
	local items = 0
	local index = 0 -- the list is 0-based
	local function Step()
		if not atAuctionHouse then
			scanning = false
			reading = false
			API.Print("the auction house closed before the scan was read; it was not kept.")
			API.Fire("LootTrackerScan")
			return
		end
		local start = debugprofilestop and debugprofilestop()
		repeat
			local last = math.min(total - 1, index + SLICE - 1)
			for i = index, last do
				local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
				if itemID and buyout and not API.IsSecret(buyout) and buyout > 0 then
					local each = math.floor(buyout / math.max(1, count or 1))
					if not lowest[itemID] or each < lowest[itemID] then
						if not lowest[itemID] then
							items = items + 1
						end
						lowest[itemID] = each
					end
				end
			end
			index = last + 1
		until index >= total or not start or debugprofilestop() - start >= BUDGET
		if index < total then
			C_Timer.After(0, Step)
			return
		end
		local store = Store()
		store.prices = lowest
		store.time = time()
		store.times = {}
		store.count = items
		scanning = false
		reading = false
		API.Print(("auction house scanned: %d auctions, lowest prices for %d items."):format(total, items))
		API.Fire("LootTrackerScan")
		API.Fire("LootTrackerChanged")
	end
	Step()
end

-- Ours, or one another addon asked for (it counts against the same 15
-- minutes).
API.On("REPLICATE_ITEM_LIST_UPDATE", function()
	if reading or not atAuctionHouse then
		return
	end
	if not scanning then
		requestedAt = GetTime()
	end
	Read()
end)

API.On("AUCTION_HOUSE_SHOW", function()
	atAuctionHouse = true
	API.Fire("LootTrackerScan")
	ns.CreateScanButton()
	if Setting("auctionAutoScan") then
		C_Timer.After(1, function()
			if ns.ScanState() == "ready" then
				ns.Scan(true)
			end
		end)
	end
end)

API.On("AUCTION_HOUSE_CLOSED", function()
	atAuctionHouse = false
	API.Fire("LootTrackerScan")
end)

-- Browsing ----------------------------------------------------------------------------

local changedSoon = false
local function Changed()
	if changedSoon then
		return
	end
	changedSoon = true
	C_Timer.After(0.5, function()
		changedSoon = false
		API.Fire("LootTrackerChanged")
	end)
end

local seenCount = 0 -- prices taken from browsing this session

-- New lowest prices per unit by item ID, from what the auction house shows.
local function Keep(found)
	local store, now = Store(), time()
	for id, each in pairs(found) do
		if store.count and not store.prices[id] then
			store.count = store.count + 1
		end
		store.prices[id] = each
		store.times[id] = now
		seenCount = seenCount + 1
	end
	if next(found) then
		Changed()
	end
end

local function Plain(value)
	if value == nil or API.IsSecret(value) or type(value) ~= "number" or value <= 0 then
		return nil
	end
	return value
end

local function Lower(found, id, each)
	id, each = Plain(id), Plain(each)
	if id and each and (not found[id] or each < found[id]) then
		found[id] = math.floor(each)
	end
end

local function Browsing()
	return atAuctionHouse and Setting("auctionBrowse")
end

-- The Buy page's results: each item's lowest price per unit.
local function ReadBrowse(results)
	if not Browsing() or not C_AuctionHouse then
		return
	end
	results = type(results) == "table" and results or (C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults())
	if type(results) ~= "table" then
		return
	end
	local found = {}
	for _, result in ipairs(results) do
		local key = result.itemKey
		Lower(found, key and key.itemID, result.minPrice)
	end
	Keep(found)
end

API.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	ReadBrowse()
end)
API.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(_, added)
	ReadBrowse(added)
end)

-- An item's own listings (gear and the like): the lowest buyout of one.
API.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, itemKey)
	if not Browsing() or type(itemKey) ~= "table" or not (C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo) then
		return
	end
	local found = {}
	for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0 do
		local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		if info then
			local quantity = Plain(info.quantity) or 1
			local buyout = Plain(info.buyoutPrice)
			Lower(found, itemKey.itemID, buyout and buyout / quantity)
		end
	end
	Keep(found)
end)

-- A commodity's listings (cloth, herbs, ore): the cheapest unit price.
API.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, itemID)
	if not Browsing() or not (C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetCommoditySearchResultInfo) then
		return
	end
	local found = {}
	for i = 1, math.min(3, C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0) do
		local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		if info then
			Lower(found, itemID, info.unitPrice)
		end
	end
	Keep(found)
end)

-- The older auction house list (AuctionFrame): each listing's buyout per unit.
API.On("AUCTION_ITEM_LIST_UPDATE", function()
	if not Browsing() or not (GetNumAuctionItems and GetAuctionItemInfo) then
		return
	end
	local found = {}
	for i = 1, GetNumAuctionItems("list") or 0 do
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
		buyout, count = Plain(buyout), Plain(count) or 1
		Lower(found, itemID, buyout and buyout / count)
	end
	Keep(found)
end)

-- The Scan button on the Buy page -------------------------------------------------------

local scanButton

local function UpdateScanButton()
	if not scanButton then
		return
	end
	local state = ns.ScanState()
	if state == "scanning" then
		scanButton:SetText("Scanning...")
		scanButton:Disable()
	elseif state == "waiting" then
		local wait = ns.ScanWait()
		scanButton:SetText(("Scan %d:%02d"):format(wait / 60, wait % 60))
		scanButton:Disable()
	else
		scanButton:SetText("Scan AH")
		scanButton:SetEnabled(state == "ready")
	end
end

-- Made when the auction house first opens (its UI loads on demand): a child
-- of the Buy page's search bar, so it shows only there, left of its Search
-- button; or above the older browse frame's Search button.
function ns.CreateScanButton()
	if scanButton or not Setting("auctionButton") then
		UpdateScanButton()
		return
	end
	local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	local parent, anchor = bar, bar and bar.SearchButton
	if not parent and AuctionFrameBrowse then
		parent, anchor = AuctionFrameBrowse, BrowseSearchButton
	end
	if not parent or not Available() then
		return
	end
	scanButton = CreateFrame("Button", "LootTrackerScanButton", parent, "UIPanelButtonTemplate")
	scanButton:SetSize(96, 22)
	if anchor and parent == bar then
		scanButton:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
	elseif anchor then
		scanButton:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
	else
		scanButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -40)
	end
	scanButton:SetFrameLevel(parent:GetFrameLevel() + 5)
	scanButton:SetScript("OnClick", function()
		ns.Scan()
	end)
	scanButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, "Loot Tracker: Scan the Auction House")
		GameTooltip_AddNormalLine(GameTooltip, "Reads every auction on the realm for the lowest price of each item (the game allows one scan every 15 minutes).")
		local scanned, items = ns.ScanInfo()
		if scanned then
			GameTooltip_AddHighlightLine(GameTooltip, ("Prices for %d items; last full scan %s."):format(items, date("%Y-%m-%d %H:%M", scanned)))
		end
		GameTooltip:Show()
	end)
	scanButton:SetScript("OnLeave", GameTooltip_Hide)
	-- The cooldown counts down while it shows.
	local elapsed = 0
	scanButton:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 1 then
			elapsed = 0
			UpdateScanButton()
		end
	end)
	UpdateScanButton()
end

API.Listen("LootTrackerScan", UpdateScanButton)
API.Listen("SettingChanged", function(section, key)
	if section == S and key == "auctionButton" and scanButton then
		scanButton:SetShown(Setting("auctionButton") and true or false)
	elseif section == S and key == "auctionButton" and atAuctionHouse then
		ns.CreateScanButton()
	end
end)

API.RegisterProbe(function()
	local scanned, items = ns.ScanInfo()
	return "Loot Tracker: auctions", ("ReplicateItems %s, GetReplicateItemInfo %s, browse %s, %d prices from browsing this session, last scan %s"):format(
		(C_AuctionHouse and C_AuctionHouse.ReplicateItems) and "yes" or "MISSING",
		(C_AuctionHouse and C_AuctionHouse.GetReplicateItemInfo) and "yes" or "MISSING",
		(C_AuctionHouse and C_AuctionHouse.GetBrowseResults) and "modern" or GetAuctionItemInfo and "classic" or "MISSING",
		seenCount,
		scanned and (date("%Y-%m-%d %H:%M", scanned) .. ", " .. items .. " prices") or "never")
end)
