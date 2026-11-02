local addonName, ns = ...
local API = ns.API

-- The auction house scanner: the Loot Tracker's Auction Value. At the
-- auction house, C_AuctionHouse.ReplicateItems asks for every auction on the
-- realm (the game allows it once every 15 minutes); when the list arrives
-- (REPLICATE_ITEM_LIST_UPDATE) it is read a slice at a time, so the game
-- does not stall, and each item's lowest buyout per unit is kept. Prices are
-- kept per realm, account-wide, in LootTrackerPrices, with the
-- time of the scan.

local S = "lootTracker"
local COOLDOWN = 15 * 60 -- seconds between full scans, the game's own limit
local SLICE = 2000       -- auctions read per frame

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

local function Available()
	return C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems
		and C_AuctionHouse.GetReplicateItemInfo and true or false
end

local atAuctionHouse = false
local scanning = false
local requestedAt -- GetTime() of the last scan asked for this session

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
	if not store or store.time == 0 then
		return nil
	end
	local count = 0
	for _ in pairs(store.prices) do
		count = count + 1
	end
	return store.time, count
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
	API.Fire("LootTrackerScan")
	API.Print("scanning the auction house...")
	C_AuctionHouse.ReplicateItems()
end

-- Read the list a slice per frame; each item's lowest buyout per unit.
local function Read()
	local total = C_AuctionHouse.GetNumReplicateItems() or 0
	local lowest = {}
	local index = 0 -- the list is 0-based
	local function Step()
		if not atAuctionHouse then
			scanning = false
			API.Print("the auction house closed before the scan was read; it was not kept.")
			API.Fire("LootTrackerScan")
			return
		end
		local last = math.min(total - 1, index + SLICE - 1)
		for i = index, last do
			local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
			if itemID and buyout and buyout > 0 and not API.IsSecret(buyout) then
				local each = math.floor(buyout / math.max(1, count or 1))
				if not lowest[itemID] or each < lowest[itemID] then
					lowest[itemID] = each
				end
			end
		end
		index = last + 1
		if index < total then
			C_Timer.After(0, Step)
			return
		end
		local store = Store()
		store.prices = lowest
		store.time = time()
		scanning = false
		local items = 0
		for _ in pairs(lowest) do
			items = items + 1
		end
		API.Print(("auction house scanned: %d auctions, lowest prices for %d items."):format(total, items))
		API.Fire("LootTrackerScan")
		API.Fire("LootTrackerChanged")
	end
	Step()
end

API.On("REPLICATE_ITEM_LIST_UPDATE", function()
	if scanning then
		Read()
	end
end)

API.On("AUCTION_HOUSE_SHOW", function()
	atAuctionHouse = true
	API.Fire("LootTrackerScan")
	if Setting("auctionAutoScan") and Setting("itemValue") == "auction" then
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

API.RegisterProbe(function()
	local scanned, items = ns.ScanInfo()
	return "Loot Tracker: auctions", ("ReplicateItems %s, GetReplicateItemInfo %s, last scan %s"):format(
		(C_AuctionHouse and C_AuctionHouse.ReplicateItems) and "yes" or "MISSING",
		(C_AuctionHouse and C_AuctionHouse.GetReplicateItemInfo) and "yes" or "MISSING",
		scanned and (date("%Y-%m-%d %H:%M", scanned) .. ", " .. items .. " items") or "never")
end)
