local addonName, ns = ...
local API = ns.API

-- Loot Tracker: what you loot and from what. No combat log: a kill is a
-- corpse you looted. When the loot window opens, each slot's sources
-- (GetLootSourceInfo: a GUID and a quantity, the copper for money) say what
-- it came from:
--   Creature   a kill; after a Skinning cast, its skinning loot; after a
--              Pick Pocket cast, its pickpocketing loot
--   GameObject a resource node (the gathering casts, or a node ID below), or
--              a chest; while IsFishingLoot(), fishing (a fishing school
--              when it is not the bobber)
--   Item       a lockbox or other container you opened from your bags;
--              after a Disenchant cast, a disenchanted item (one entry,
--              "Disenchanted")
-- With Only What You Receive (on), an item counts once the game says you
-- received it (CHAT_MSG_LOOT: "You receive loot: ..."), so what someone else
-- took, won the roll for or what you left behind is not counted; a roll you
-- win later still goes to its source. Gold counts as your purse grows: your
-- share in a group.
-- Each loot is kept as an event (the newest LOG_LIMIT, for the
-- Individualized view) and added into totals by source, so nothing is lost
-- when old events go. Totals are kept fine-grained (kind, ID, zone, school);
-- the view merges them as the settings say. Per character, in
-- LootTrackerDB.

local S = "lootTracker"
local LOG_LIMIT = 300
local CAST_WINDOW = 4      -- seconds a gathering, skinning or opening cast counts for
local TOOLTIP_WINDOW = 10  -- seconds a world object's tooltip name counts for (an opening cast takes up to 5)
local BOBBERS = { [35591] = true } -- the fishing bobber

-- Resource nodes that share a name across IDs, by the owner's choice.
local NODE_GROUPS = {
	[1731] = "Copper Vein", [2055] = "Copper Vein", [3763] = "Copper Vein", [103713] = "Copper Vein",
	[562111] = "Copper Vein", -- Poor Copper Vein
	[1618] = "Peacebloom", [3724] = "Peacebloom", [657382] = "Peacebloom", [657456] = "Peacebloom",
	[656160] = "Peacebloom", [657454] = "Peacebloom", -- Wilted Peacebloom
}
ns.NODE_GROUPS = NODE_GROUPS

local function Setting(key)
	return API.Get(S, key)
end

local db -- LootTrackerDB, once loaded

local function Changed()
	API.Fire("LootTrackerChanged")
end

-- Names ------------------------------------------------------------------------------
-- Creatures' names by GUID (target, mouseover, nameplates) and by NPC ID
-- (kept); world objects' names from the tooltip shown just before a loot.

local guidNames = {}
local lastObject -- { name, time }

local function Plain(value)
	if value == nil or API.IsSecret(value) then
		return nil
	end
	return value
end

local function GuidParts(guid)
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind, tonumber(id)
end

-- The name database, account-wide (LootTrackerNames): every NPC
-- ID's name once learned, on any character; where each was looted inside an
-- instance; and the IDs still waiting for a name (kept across sessions, so a
-- name secret in an instance is filled in later, on any character). Names.lua
-- ships a fallback list (ns.KNOWN_NAMES) for IDs never learned here.
local nameDB

local function InstanceName()
	if IsInInstance and IsInInstance() then
		return Plain((GetInstanceInfo())) or "Instance"
	end
end

local function KnownName(id)
	if type(id) ~= "number" then
		return nil
	end
	return (nameDB and nameDB.names[id]) or (ns.KNOWN_NAMES and ns.KNOWN_NAMES[id])
end

local function Remember(id, name)
	if not (nameDB and type(id) == "number" and name) then
		return
	end
	nameDB.names[id] = name
	local instance = InstanceName()
	if instance then
		nameDB.instanced[id] = instance
	end
	nameDB.pending[id] = nil
end

-- World objects (chests, containers, nodes, schools, other spawns) have no
-- name lookup by ID: their names are learned from what is seen, by object
-- ID, account-wide (nameDB.objects, with the zone in nameDB.objectZones):
-- the soft-interact target (UnitName / UnitGUID "softinteract"), a tooltip
-- whose data carries the object's GUID, and the object tooltip shown just
-- before a loot. Names.lua's ns.KNOWN_OBJECTS is the shipped fallback.
local function Zone()
	return Plain(GetRealZoneText and GetRealZoneText()) or Plain(GetZoneText()) or "Unknown"
end

local function ObjectName(id)
	if type(id) ~= "number" then
		return nil
	end
	return (nameDB and nameDB.objects[id]) or (ns.KNOWN_OBJECTS and ns.KNOWN_OBJECTS[id])
end
ns.ObjectName = ObjectName

local function RememberObject(id, name)
	if not (nameDB and type(id) == "number" and type(name) == "string" and name ~= "") then
		return
	end
	nameDB.objects[id] = name
	nameDB.objectZones[id] = InstanceName() or Zone()
end

local function Learn(unit)
	local guid, name = Plain(UnitGUID(unit)), Plain(UnitName(unit))
	if guid and name then
		guidNames[guid] = name
		local kind, id = GuidParts(guid)
		if id and (kind == "Creature" or kind == "Vehicle") then
			Remember(id, name)
		elseif id and kind == "GameObject" then
			RememberObject(id, name)
		end
	end
end

-- The object the interact key would use (soft targeting).
API.On("PLAYER_SOFT_INTERACT_CHANGED", function()
	Learn("softinteract")
end)

-- A tooltip whose data names a world object's GUID.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip, data)
		local guid = type(data) == "table" and Plain(data.guid)
		if type(guid) ~= "string" then
			return
		end
		local kind, id = GuidParts(guid)
		local line = type(data.lines) == "table" and data.lines[1]
		local name = line and Plain(line.leftText)
		if kind == "GameObject" and id and name then
			RememberObject(id, name)
		end
	end)
end

API.On("PLAYER_TARGET_CHANGED", function()
	Learn("target")
end)
API.On("UPDATE_MOUSEOVER_UNIT", function()
	Learn("mouseover")
end)
API.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
	Learn(unit)
end)

-- A world object's tooltip (a chest, a vein, a school): its first line.
GameTooltip:HookScript("OnShow", function(self)
	if self:GetUnit() or self:GetItem() then
		return
	end
	local line = _G.GameTooltipTextLeft1
	local text = line and Plain(line:GetText())
	if text and text ~= "" then
		lastObject = { name = text, time = GetTime() }
	end
end)

-- A creature's name from its ID alone: the game's own tooltip for a unit
-- link (C_TooltipInfo.GetHyperlink), its first line. In an instance names
-- can be secret, and the game may not have the name cached yet: what is not
-- found is tried again later (a zone change, leaving the instance, a timer),
-- from nameDB.pending.

local function CreatureLink(id)
	return ("unit:Creature-0-0-0-0-%d-0000000000"):format(id)
end

local function LookUpName(id)
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, CreatureLink(id))
	local line = ok and type(data) == "table" and type(data.lines) == "table" and data.lines[1]
	local text = line and Plain(line.leftText)
	if type(text) == "string" and text ~= "" and text ~= _G.UNKNOWNOBJECT and text ~= _G.UNKNOWN then
		return text
	end
end

local resolving
local function ResolveNames(tries)
	if not nameDB then
		return
	end
	local found, left = false, false
	for id in pairs(nameDB.pending) do
		if nameDB.names[id] then
			nameDB.pending[id] = nil
		else
			local name = LookUpName(id)
			if name then
				-- Looked up outside, it keeps the instance it was looted in.
				nameDB.names[id] = name
				nameDB.pending[id] = nil
				found = true
			else
				left = true
			end
		end
	end
	if found then
		Changed()
	end
	-- The game fetches names it has not cached: look again shortly.
	tries = tries or 0
	if left and tries < 5 and not resolving then
		resolving = true
		C_Timer.After(3, function()
			resolving = nil
			ResolveNames(tries + 1)
		end)
	end
end

local function NeedName(id)
	if nameDB and type(id) == "number" and not nameDB.names[id] then
		nameDB.pending[id] = true
		local instance = InstanceName()
		if instance then
			nameDB.instanced[id] = instance
		end
	end
end

-- The name a creature record shows: the one learned for its ID, else the
-- one it was recorded with (nil while it is not known yet).
function ns.CreatureName(id, recorded)
	if nameDB and nameDB.names[id] then
		return nameDB.names[id]
	end
	if recorded and not recorded:find("^Creature %d+$") then
		return recorded
	end
	NeedName(id)
	return KnownName(id)
end

local function RecentObjectName()
	if lastObject and GetTime() - lastObject.time <= TOOLTIP_WINDOW then
		return lastObject.name
	end
end

-- Casts and containers ---------------------------------------------------------------
-- The last profession cast (by its name), and the last item used from the
-- bags (a lockbox about to open).

local lastCast -- { kind, time }
local CASTS = {
	{ "skinning", "skinning" },
	{ "pick pocket", "pickpocket" },
	{ "mining", "gather" },
	{ "herb gathering", "gather" },
	{ "herbalism", "gather" },
	{ "opening", "opening" },
	{ "pick lock", "opening" },
	{ "fishing", "fishing" },
	{ "disenchant", "disenchant" },
}

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then
		return Plain(C_Spell.GetSpellName(spellID))
	end
end

API.OnPlayer("UNIT_SPELLCAST_SUCCEEDED", function(_, _, _, spellID)
	local name = spellID and not API.IsSecret(spellID) and SpellName(spellID)
	if not name then
		return
	end
	name = name:lower()
	for _, cast in ipairs(CASTS) do
		if name:find(cast[1], 1, true) then
			lastCast = { kind = cast[2], time = GetTime() }
			return
		end
	end
end)

local function RecentCast()
	if lastCast and GetTime() - lastCast.time <= CAST_WINDOW then
		return lastCast.kind
	end
end

local lastUsed -- { id, name, time }
local function NoteUsed(bag, slot)
	local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
	if info and info.itemID then
		local name = info.hyperlink and info.hyperlink:match("%[(.-)%]")
		lastUsed = { id = info.itemID, name = name, time = GetTime() }
	end
end
if C_Container and C_Container.UseContainerItem then
	hooksecurefunc(C_Container, "UseContainerItem", NoteUsed)
end

-- Items ------------------------------------------------------------------------------

local function ItemID(link)
	return link and tonumber(link:match("item:(%d+)"))
end
ns.ItemID = ItemID

-- What one of an item sells to a vendor for, or nil until the game has it.
local requested = {}
function ns.SellPrice(link)
	if not link or not (C_Item and C_Item.GetItemInfo) then
		return nil
	end
	local price = select(11, C_Item.GetItemInfo(link))
	if price == nil then
		local id = ItemID(link)
		if id and not requested[id] and C_Item.RequestLoadItemDataByID then
			requested[id] = true
			C_Item.RequestLoadItemDataByID(id)
		end
	end
	return price
end

local loadPending = false
API.On("ITEM_DATA_LOAD_RESULT", function()
	if not loadPending then
		loadPending = true
		C_Timer.After(0.3, function()
			loadPending = false
			Changed()
		end)
	end
end)

-- Recording --------------------------------------------------------------------------

-- Fine-grained totals key.
local function TotalKey(event)
	return table.concat({ event.kind, tostring(event.id), event.zone or "", event.school or "" }, "|")
end

local function AddItems(into, items, when)
	for _, item in ipairs(items) do
		local key = ItemID(item.link) or item.link or item.name
		local entry = into[key]
		if not entry then
			entry = { link = item.link, name = item.name, icon = item.icon, quality = item.quality, count = 0 }
			into[key] = entry
		end
		entry.count = entry.count + item.count
		-- When it was last looted, for sorting by Newest.
		if when then
			entry.last = math.max(entry.last or 0, when)
		end
	end
end

ns.TotalKey = TotalKey

local function AddTo(totals, event)
	local key = TotalKey(event)
	local total = totals[key]
	if not total then
		total = { kind = event.kind, id = event.id, name = event.name, zone = event.zone, school = event.school,
			count = 0, money = 0, items = {} }
		totals[key] = total
	end
	total.name = event.name or total.name
	total.count = total.count + 1
	total.money = total.money + event.money
	total.last = event.time
	AddItems(total.items, event.items, event.time)
end

-- Takes one event back out of a totals table (its X in the per-loot view).
function ns.Subtract(totals, event)
	local key = TotalKey(event)
	local total = totals and totals[key]
	if not total then
		return
	end
	total.count = total.count - 1
	total.money = math.max(0, total.money - (event.money or 0))
	for _, item in ipairs(event.items or {}) do
		local itemKey = ItemID(item.link) or item.link or item.name
		local have = total.items[itemKey]
		if have then
			have.count = have.count - item.count
			if have.count <= 0 then
				total.items[itemKey] = nil
			end
		end
	end
	if total.count <= 0 then
		totals[key] = nil
	end
end

-- Scopes: every loot also goes into this login session's totals and, inside
-- an instance, the current run's (db.sessionTotals, db.runTotals), so the
-- view can show only those. Events carry the session and run they were in.
local function Record(event)
	event.session = db.session
	event.run = db.run and db.run.id or nil
	db.events[#db.events + 1] = event
	while #db.events > LOG_LIMIT do
		table.remove(db.events, 1)
	end
	AddTo(db.totals, event)
	AddTo(db.sessionTotals, event)
	if db.run and db.run.inside then
		AddTo(db.runTotals, event)
	end
	Changed()
end

-- Only what you receive ------------------------------------------------------------
-- Items from a loot window wait (by item ID, with their event) for the game's
-- "You receive loot" line; a received line with no item waiting is kept a
-- moment, for autoloot's lines that come before the window is read. A wait
-- ends after PENDING_TIME (a roll can take a minute or two).

local PENDING_TIME = 300
local RECEIPT_TIME = 3
local pending = {}  -- { id, item, event, left, until }
local receipts = {} -- { id, count, until }
-- While the game hides loot lines (secret text), bag counts stand in: what
-- an item waiting for its line gains in the bags is what was received.
local secretLines = false
local baseline = {} -- item ID -> its count in the bags when it started waiting

local function BagCount(id)
	if C_Item and C_Item.GetItemCount then
		return Plain(C_Item.GetItemCount(id)) or 0
	end
	return 0
end

-- The game's own "You receive ..." lines as patterns: the item's link, and
-- the count when there is one.
local SELF_LINES = {}
for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
	local text = _G[key]
	if type(text) == "string" then
		local pattern = text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
		SELF_LINES[#SELF_LINES + 1] = "^" .. pattern
	end
end

ns.waiting = pending
function ns.SecretLines()
	return secretLines
end

function ns.Confirming()
	return Setting("confirmLoot") and #SELF_LINES > 0
end

-- Adds a received item to its event and to the totals the event is in.
local function AddReceived(event, item, count)
	local got = {}
	for k, v in pairs(item) do
		got[k] = v
	end
	got.locked, got.count = nil, count
	local items = { got }
	-- An event's items are a list: the same item adds to its line.
	local merged = false
	for _, have in ipairs(event.items) do
		if have.link == got.link then
			have.count = have.count + count
			merged = true
			break
		end
	end
	if not merged then
		event.items[#event.items + 1] = got
	end
	for _, totals in ipairs({ db.totals, db.sessionTotals, (db.run and db.run.inside and db.run.id == event.run) and db.runTotals or nil }) do
		local total = totals[TotalKey(event)]
		if total then
			AddItems(total.items, items, event.time)
		end
	end
	Changed()
end

-- One received line: the oldest waiting item of that ID takes it.
local function Receive(id, count)
	local now = GetTime()
	for i = 1, #pending do
		local wait = pending[i]
		if wait.id == id and wait["until"] >= now then
			local take = math.min(count, wait.left)
			AddReceived(wait.event, wait.item, take)
			if baseline[id] then
				baseline[id] = baseline[id] + take -- (the bags' count follows)
			end
			wait.left = wait.left - take
			count = count - take
			if wait.left <= 0 then
				table.remove(pending, i)
			end
			break
		end
	end
	return count
end

function ns.Await(event, item)
	local id = ItemID(item.link)
	if not id then
		return
	end
	local now = GetTime()
	pending[#pending + 1] = { id = id, item = item, event = event, left = item.count or 1, ["until"] = now + PENDING_TIME }
	if not baseline[id] then
		baseline[id] = BagCount(id)
	end
	-- A line that came first (autoloot).
	for i = #receipts, 1, -1 do
		local receipt = receipts[i]
		if receipt["until"] < now then
			table.remove(receipts, i)
		elseif receipt.id == id then
			receipt.count = Receive(id, receipt.count)
			if receipt.count <= 0 then
				table.remove(receipts, i)
			end
		end
	end
end

local function DropExpired()
	local now, waiting = GetTime(), {}
	for i = #pending, 1, -1 do
		if pending[i]["until"] < now then
			table.remove(pending, i)
		else
			waiting[pending[i].id] = true
		end
	end
	for id in pairs(baseline) do
		if not waiting[id] then
			baseline[id] = nil
		end
	end
end

-- Gold: what the purse gains (GetMoney, on PLAYER_MONEY) goes to the gold
-- waiting, oldest first, up to what each corpse showed: your share in a
-- group, nothing for what someone else took. A gain with nothing waiting is
-- kept a moment (autoloot can take it before the window is read).
local MONEY_TIME = 15
local moneyWaits = {}   -- { event, left, until }
local moneyReceipt = { amount = 0, ["until"] = 0 }
local purse = GetMoney and Plain(GetMoney()) or nil

local function AddMoney(event, copper)
	event.money = (event.money or 0) + copper
	for _, totals in ipairs({ db.totals, db.sessionTotals, (db.run and db.run.inside and db.run.id == event.run) and db.runTotals or nil }) do
		local total = totals[TotalKey(event)]
		if total then
			total.money = total.money + copper
		end
	end
	Changed()
end

local function GiveMoney(amount)
	local now = GetTime()
	local i = 1
	while amount > 0 and i <= #moneyWaits do
		local wait = moneyWaits[i]
		if wait["until"] < now then
			table.remove(moneyWaits, i)
		else
			local take = math.min(amount, wait.left)
			AddMoney(wait.event, take)
			amount = amount - take
			wait.left = wait.left - take
			-- In a group the share is less than the corpse showed: one gain
			-- settles a corpse.
			table.remove(moneyWaits, i)
		end
	end
	return amount
end

function ns.AwaitMoney(event, copper)
	moneyWaits[#moneyWaits + 1] = { event = event, left = copper, ["until"] = GetTime() + MONEY_TIME }
	if moneyReceipt.amount > 0 and moneyReceipt["until"] >= GetTime() then
		moneyReceipt.amount = GiveMoney(moneyReceipt.amount)
	end
end

API.On("PLAYER_MONEY", function()
	local now = GetMoney and Plain(GetMoney())
	if not now then
		return
	end
	local gained = purse and (now - purse) or 0
	purse = now
	if gained > 0 and db and ns.Confirming() then
		local left = GiveMoney(gained)
		moneyReceipt = { amount = left, ["until"] = GetTime() + RECEIPT_TIME }
	end
end)

API.On("PLAYER_ENTERING_WORLD", function()
	purse = GetMoney and Plain(GetMoney()) or purse
end)

API.On("BAG_UPDATE_DELAYED", function()
	if not db or not secretLines or not ns.Confirming() then
		return
	end
	DropExpired()
	for id, before in pairs(baseline) do
		local now = BagCount(id)
		if now > before then
			Receive(id, now - before)
		end
		baseline[id] = now
	end
end)

API.On("CHAT_MSG_LOOT", function(_, text)
	if not db or not ns.Confirming() then
		return
	end
	if API.IsSecret(text) then
		secretLines = true
		return
	end
	if type(text) ~= "string" then
		return
	end
	secretLines = false
	for _, pattern in ipairs(SELF_LINES) do
		local link, count = text:match(pattern)
		if link then
			local id = ItemID(link)
			count = tonumber(count) or 1
			if id then
				DropExpired()
				local left = Receive(id, count)
				if left > 0 then
					receipts[#receipts + 1] = { id = id, count = left, ["until"] = GetTime() + RECEIPT_TIME }
				end
			end
			return
		end
	end
end)

-- Sources already recorded this session (a corpse opened twice, a chest
-- left half looted), by kind and GUID. A gathering node is recorded again
-- after each gathering cast on it (OnLootOpened).
local recorded = {}


-- What a source GUID is, as an event's kind, ID and name; nil to skip.
local function Classify(guid, fishing, cast)
	local unitType, id = GuidParts(guid)
	if fishing then
		if not Setting("trackFishing") then
			return nil
		end
		local school
		if unitType == "GameObject" and id and not BOBBERS[id] then
			school = ObjectName(id) or RecentObjectName()
			if school then
				RememberObject(id, school)
			end
			school = school or ("School " .. id)
		end
		return "fishing", school or "zone", nil, school
	end
	if unitType == "Creature" or unitType == "Vehicle" then
		if not Setting("trackCreatures") then
			return nil
		end
		local name = guidNames[guid] or (nameDB and nameDB.names[id])
		if id and InstanceName() and nameDB then
			nameDB.instanced[id] = InstanceName()
		end
		if not name and id then
			name = LookUpName(id)
			if name then
				Remember(id, name)
			else
				NeedName(id)
				name = KnownName(id)
			end
		end
		if cast == "pickpocket" then
			return "pickpocket", id, name
		elseif cast == "skinning" then
			return "skinning", id, name
		end
		return "creature", id, name
	elseif unitType == "GameObject" then
		if NODE_GROUPS[id] or cast == "gather" then
			if not Setting("trackNodes") then
				return nil
			end
			local name = NODE_GROUPS[id] or ObjectName(id) or RecentObjectName()
			if name and not NODE_GROUPS[id] then
				RememberObject(id, name)
			end
			return "node", NODE_GROUPS[id] or id, name or ("Node " .. tostring(id))
		end
		if not Setting("trackChests") then
			return nil
		end
		-- A name known for the ID wins over the last tooltip, which may be
		-- some other object's.
		local name = ObjectName(id) or RecentObjectName()
		if name then
			RememberObject(id, name)
		end
		return "chest", id, name or ("Chest " .. tostring(id))
	elseif unitType == "Item" or cast == "disenchant" then
		-- A disenchanted item: every disenchant in one entry.
		if cast == "disenchant" then
			if not Setting("trackDisenchant") then
				return nil
			end
			return "disenchant", 0, "Disenchanted"
		end
		if not Setting("trackLockboxes") then
			return nil
		end
		if lastUsed and GetTime() - lastUsed.time <= 10 then
			return "lockbox", lastUsed.id, lastUsed.name or ("Container " .. lastUsed.id)
		end
		return "lockbox", 0, "Container"
	end
end

local MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or (LOOT_SLOT_MONEY) or 2

-- "1 Gold 2 Silver 3 Copper" (a money slot's text) in copper, when a
-- source's quantity does not say.
local function ParseMoney(text)
	if type(text) ~= "string" then
		return 0
	end
	local copper = 0
	for amount, unit in text:gmatch("(%d+)%s*(%a+)") do
		unit = unit:lower()
		if unit:find("^g") then
			copper = copper + amount * 10000
		elseif unit:find("^s") then
			copper = copper + amount * 100
		elseif unit:find("^c") then
			copper = copper + amount
		end
	end
	return copper
end

local function OnLootOpened()
	if not db then
		return
	end
	local fishing = IsFishingLoot and Plain(IsFishingLoot()) or false
	local cast = RecentCast()
	local buckets, order = {}, {}
	local function Bucket(guid)
		local bucket = buckets[guid]
		if not bucket then
			bucket = { money = 0, items = {} }
			buckets[guid] = bucket
			order[#order + 1] = guid
		end
		return bucket
	end
	for slot = 1, GetNumLootItems() do
		local slotType = GetLootSlotType(slot)
		local icon, name, quantity, _, quality, locked = GetLootSlotInfo(slot)
		locked = Plain(locked) and true or false
		local link = GetLootSlotLink(slot)
		local sources = { GetLootSourceInfo(slot) }
		if #sources == 0 then
			-- No source given (open water fishing on some builds): one pseudo source.
			sources = { fishing and "Fishing" or "Unknown", quantity or 1 }
		end
		for i = 1, #sources, 2 do
			local guid, amount = Plain(sources[i]), Plain(sources[i + 1])
			if guid then
				local bucket = Bucket(guid)
				if slotType == MONEY then
					bucket.money = bucket.money + ((amount and amount > 0) and amount or ParseMoney(name))
				else
					bucket.items[#bucket.items + 1] = {
						link = link, name = Plain(name), icon = icon, quality = Plain(quality),
						count = (#sources > 2 and amount) or quantity or 1,
						locked = locked,
					}
				end
			end
		end
	end
	local now = time()
	for _, guid in ipairs(order) do
		local kind, id, sourceName, school
		if guid == "Fishing" then
			if Setting("trackFishing") then
				kind, id = "fishing", "zone"
			end
		elseif guid ~= "Unknown" then
			kind, id, sourceName, school = Classify(guid, fishing, cast)
		end
		local seenKey = kind and (kind .. guid)
		-- A node is gathered again and again (an ore vein gives three or
		-- four loots): each loot after a gathering cast of its own is a
		-- new one. Without a fresh cast it is the same loot window opened
		-- again, and is not counted twice.
		local again = kind == "node" and cast == "gather"
		if kind and (guid == "Fishing" or again or not recorded[seenKey]) then
			recorded[seenKey] = true
			local bucket = buckets[guid]
			local items, waiting, money = bucket.items, nil, bucket.money
			if ns.Confirming() then
				-- Items and gold wait for the game to say you received them
				-- (your share of the gold, in a group).
				items, waiting, money = {}, bucket.items, 0
			end
			local event = {
				kind = kind, id = id, name = sourceName, school = school,
				zone = kind == "fishing" and Zone() or nil,
				money = money, items = items, time = now,
			}
			Record(event)
			for _, item in ipairs(waiting or {}) do
				ns.Await(event, item)
			end
			if waiting and bucket.money > 0 then
				ns.AwaitMoney(event, bucket.money)
			end
		end
	end
	lastCast = nil
end

API.On("LOOT_OPENED", function(...)
	OnLootOpened(...)
	ResolveNames()
end)

-- Names secret in an instance read plainly after it: look again on each
-- zone change.
-- The session and the instance run new loot belongs to.
local function UpdateScopes(isInitialLogin)
	if not db then
		return
	end
	-- A new login (not a reload) starts a new session: told by when this
	-- login began (GetSessionTime runs on across reloads), else the event's
	-- isInitialLogin.
	local loginAt = GetSessionTime and (time() - GetSessionTime()) or nil
	local newLogin
	if loginAt then
		newLogin = not db.sessionLogin or math.abs(db.sessionLogin - loginAt) > 120
	else
		newLogin = isInitialLogin
	end
	if newLogin or not db.session then
		db.session = time()
		db.sessionLogin = loginAt
		db.sessionTotals = {}
	end
	-- Entering an instance other than the last run's starts a new run; going
	-- back into the same one (a corpse run) carries on with it.
	local inInstance = IsInInstance and IsInInstance()
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	if inInstance then
		if not (db.run and db.run.instanceID == instanceID) then
			db.run = { id = time(), instanceID = instanceID, name = Plain(name) }
			db.runTotals = {}
		end
		db.run.inside = true
	elseif db.run then
		db.run.inside = false
	end
	Changed()
end

API.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
	C_Timer.After(2, ResolveNames)
	UpdateScopes(isInitialLogin)
end)
API.On("ZONE_CHANGED_NEW_AREA", function()
	C_Timer.After(2, ResolveNames)
end)

-- Saved data -------------------------------------------------------------------------

API.On("ADDON_LOADED", function(_, name)
	if name ~= addonName then
		return
	end
	LootTrackerDB = LootTrackerDB or {}
	db = LootTrackerDB
	db.events = db.events or {}
	db.totals = db.totals or {}
	db.names = db.names or {}
	LootTrackerNames = LootTrackerNames or {}
	nameDB = LootTrackerNames
	nameDB.names = nameDB.names or {}
	nameDB.instanced = nameDB.instanced or {}
	nameDB.pending = nameDB.pending or {}
	nameDB.objects = nameDB.objects or {}
	nameDB.objectZones = nameDB.objectZones or {}
	ns.nameDB = nameDB
	-- This character's names from before the database, moved into it.
	for id, name in pairs(db.names) do
		if not nameDB.names[id] then
			nameDB.names[id] = name
		end
	end
	wipe(db.names)
	db.sessionTotals = db.sessionTotals or {}
	db.runTotals = db.runTotals or {}
	ns.db = db
	-- Creatures recorded without a name (by their ID) are looked up again.
	local CREATURE = { creature = true, skinning = true, pickpocket = true }
	for _, list in ipairs({ db.totals, db.events }) do
		for _, record in pairs(list) do
			if CREATURE[record.kind] then
				ns.CreatureName(record.id, record.name)
			end
		end
	end
	C_Timer.After(2, ResolveNames)
	UpdateScopes(false)
	Changed()
end)

-- The instanced names as Names.lua lines, to ship as the fallback list.
function ns.ExportNames()
	local ids = {}
	for id in pairs(nameDB and nameDB.instanced or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		local ia, ib = nameDB.instanced[a], nameDB.instanced[b]
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	local out = { "-- Paste into LootTracker/Names.lua, inside ns.KNOWN_NAMES." }
	local known, waiting = 0, 0
	for _, id in ipairs(ids) do
		local name = nameDB.names[id]
		if name then
			known = known + 1
			out[#out + 1] = ("\t[%d] = %q, -- %s"):format(id, name, nameDB.instanced[id])
		else
			waiting = waiting + 1
			out[#out + 1] = ("\t-- [%d] = ?, -- %s (no name yet)"):format(id, nameDB.instanced[id])
		end
	end
	out[#out + 1] = ("-- %d named, %d waiting for a name."):format(known, waiting)
	-- World objects, by zone.
	local objects = {}
	for id in pairs(nameDB and nameDB.objects or {}) do
		objects[#objects + 1] = id
	end
	table.sort(objects, function(a, b)
		local za, zb = nameDB.objectZones[a] or "", nameDB.objectZones[b] or ""
		if za ~= zb then
			return za < zb
		end
		return a < b
	end)
	out[#out + 1] = ""
	out[#out + 1] = "-- Paste into LootTracker/Names.lua, inside ns.KNOWN_OBJECTS."
	for _, id in ipairs(objects) do
		out[#out + 1] = ("\t[%d] = %q, -- %s"):format(id, nameDB.objects[id], nameDB.objectZones[id] or "?")
	end
	out[#out + 1] = ("-- %d world objects."):format(#objects)
	API.ShowCopyBox("Loot Tracker: name database", table.concat(out, "\n"))
end

function ns.Reset()
	if not db then
		return
	end
	wipe(db.events)
	wipe(db.totals)
	wipe(db.sessionTotals)
	wipe(db.runTotals)
	wipe(recorded)
	Changed()
end

API.RegisterProbe(function()
	local totals = 0
	for _ in pairs(db and db.totals or {}) do
		totals = totals + 1
	end
	local named, instanced, pending = 0, 0, 0
	for _ in pairs(nameDB and nameDB.names or {}) do named = named + 1 end
	for _ in pairs(nameDB and nameDB.instanced or {}) do instanced = instanced + 1 end
	for _ in pairs(nameDB and nameDB.pending or {}) do pending = pending + 1 end
	local objects = 0
	for _ in pairs(nameDB and nameDB.objects or {}) do objects = objects + 1 end
	API.Print(("Loot Tracker: only what you receive %s: %d loot line patterns, %d items waiting, loot lines %s"):format(
		ns.Confirming() and "on" or "off", #SELF_LINES, #ns.waiting, ns.SecretLines() and "SECRET (bag counts stand in)" or "readable"))
	API.Print(("Loot Tracker: world objects: %d named; softinteract unit %s"):format(objects, (UnitExists and UnitExists("softinteract")) and "now" or "none now"))
	API.Print(("Loot Tracker: names: %d known, %d looted in instances, %d waiting; C_TooltipInfo.GetHyperlink %s"):format(
		named, instanced, pending, (C_TooltipInfo and C_TooltipInfo.GetHyperlink) and "yes" or "MISSING"))
	return "Loot Tracker", ("%d sources, %d events kept; GetLootSourceInfo %s, IsFishingLoot %s, C_Spell.GetSpellName %s, C_Item.GetItemInfo %s, C_Container.UseContainerItem %s"):format(
		totals, db and #db.events or 0,
		GetLootSourceInfo and "yes" or "MISSING",
		IsFishingLoot and "yes" or "MISSING",
		(C_Spell and C_Spell.GetSpellName) and "yes" or "MISSING",
		(C_Item and C_Item.GetItemInfo) and "yes" or "MISSING",
		(C_Container and C_Container.UseContainerItem) and "yes" or "MISSING")
end)
