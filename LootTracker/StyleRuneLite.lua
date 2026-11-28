local addonName, ns = ...
local API = ns.API

-- Style "runelite": in the look of RuneLite's Loot Tracker panel. Flat
-- grays (RuneLite's own: the panel 40, its boxes 30, their title bars 21),
-- no title bar: a row of small controls on the right (collapse or expand
-- all, By Source, Each Loot, the menu), an overall box (a loot bag, "Total
-- count", "Total value"), then a box per source: its title bar (name, "x 13",
-- its value) over a grid of five slots a row, each item with its count in
-- yellow in the top left (white from 100K, green from 10M, as the game's
-- stacks), money as a slot of coins, empty slots filling the last row.
-- A click on a title bar folds the box; a right-click forgets it.

local Setting = ns.Setting
local API_Set = API.Set

local function Gray(value)
	return value / 255, value / 255, value / 255
end

local PANEL, BOX, TITLE_BAR = 40, 30, 21
local LIGHT_GRAY = { Gray(165) }
local WHITE = { 1, 1, 1 }
local PAD, BAR_HEIGHT, OVERALL_HEIGHT, TITLE_HEIGHT, COLUMNS = 6, 22, 42, 22, 5

local FONT = "Arial Narrow"

local boxes, slots

-- RuneScape's stack text: yellow, white from 100K (as "123K"), green from
-- 10M (as "12M").
local function Stack(count)
	count = count or 0
	if count >= 10000000 then
		return math.floor(count / 1000000) .. "M", 0, 1, 0.5
	elseif count >= 100000 then
		return math.floor(count / 1000) .. "K", 1, 1, 1
	end
	return tostring(count), 1, 1, 0
end

-- The controls: small glyphs made of bars, white when chosen, gray when not.
local function Control(parent, tooltip, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(20, BAR_HEIGHT)
	button.parts = {}
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		self.hover = true
		self:Paint()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(type(tooltip) == "function" and tooltip() or tooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self.hover = false
		self:Paint()
		GameTooltip:Hide()
	end)
	function button:Bar(width, height, x, y, rotation)
		local part = ns.Fill(self, "ARTWORK", 1, 1, 1, 1)
		part:SetSize(width, height)
		part:SetPoint("CENTER", x or 0, y or 0)
		if rotation and part.SetRotation then
			pcall(part.SetRotation, part, rotation)
		end
		self.parts[#self.parts + 1] = part
		return part
	end
	function button:Paint()
		local on = self.chosen and self.chosen()
		local shade = (on or self.hover) and 1 or 0.4
		for _, part in ipairs(self.parts) do
			part:SetColorTexture(shade, shade, shade, 1)
		end
	end
	return button
end

local function AllFolded(entries)
	for _, entry in ipairs(entries) do
		if not ns.Folded(entry.key) then
			return false
		end
	end
	return #entries > 0
end

local function FoldAll()
	local db = ns.db
	if not db then
		return
	end
	local entries = ns.Entries()
	local fold = not AllFolded(entries)
	db.folded = db.folded or {}
	for _, entry in ipairs(entries) do
		db.folded[entry.key] = fold or nil
	end
	ns.RenderStyle()
end

local function NewBox()
	local box = CreateFrame("Frame", nil, boxes.content)
	local title = CreateFrame("Button", nil, box)
	title:SetPoint("TOPLEFT")
	title:SetPoint("TOPRIGHT")
	title:SetHeight(TITLE_HEIGHT)
	title.bg = ns.Fill(title, "BACKGROUND", Gray(TITLE_BAR))
	title.bg:SetAllPoints()
	title.name = title:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title.name:SetPoint("LEFT", 7, 0)
	title.name:SetJustifyH("LEFT")
	title.name:SetWordWrap(false)
	title.kills = title:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title.kills:SetPoint("LEFT", title.name, "RIGHT", 5, 0)
	title.value = title:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title.value:SetPoint("RIGHT", -7, 0)
	ns.SourceScripts(title, function(self, inside)
		self.bg:SetColorTexture(Gray(inside and 30 or TITLE_BAR))
	end)
	box.title = title
	return box
end

local function NewSlot()
	local slot = CreateFrame("Button", nil, slots.content)
	slot.bg = ns.Fill(slot, "BACKGROUND", Gray(BOX))
	slot.bg:SetAllPoints()
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetPoint("CENTER", 0, -2)
	slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	slot.count = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	slot.count:SetPoint("TOPLEFT", 2, -1)
	slot.count:SetJustifyH("LEFT")
	ns.ItemScripts(slot)
	return slot
end

local function Build()
	local frame = ns.NewStyleFrame("runelite", 6)
	local box, thumb = BOX / 255, 77 / 255
	ns.PaintScrollBar(frame.bar, box, box, box, 1, thumb, thumb, thumb, 1)
	frame:EnableMouse(true)
	frame.bg = ns.Fill(frame, "BACKGROUND", Gray(PANEL))
	frame.bg:SetAllPoints()

	-- The controls' row.
	local actions = CreateFrame("Frame", nil, frame)
	actions:SetPoint("TOPLEFT", PAD, -PAD)
	actions:SetPoint("TOPRIGHT", -PAD, -PAD)
	actions:SetHeight(BAR_HEIGHT)
	ns.Fill(actions, "BACKGROUND", Gray(BOX)):SetAllPoints()
	ns.DragHandle(frame, actions)

	local menu = Control(actions, "Loot Tracker menu", function(self)
		if ns.ShowMenu then
			ns.ShowMenu(self)
		end
	end)
	menu:SetPoint("RIGHT", -4, 0)
	menu:Bar(3, 3, 0, 5)
	menu:Bar(3, 3, 0, 0)
	menu:Bar(3, 3, 0, -5)

	local single = Control(actions, "Each Loot", function()
		API_Set("lootTracker", "grouping", "individual")
	end)
	single:SetPoint("RIGHT", menu, "LEFT", -6, 0)
	single.chosen = function()
		return Setting("grouping") == "individual"
	end
	single:Bar(12, 2, 0, 4)
	single:Bar(12, 2, 0, 0)
	single:Bar(12, 2, 0, -4)

	local grouped = Control(actions, "By Source", function()
		API_Set("lootTracker", "grouping", "grouped")
	end)
	grouped:SetPoint("RIGHT", single, "LEFT", -6, 0)
	grouped.chosen = function()
		return Setting("grouping") ~= "individual"
	end
	grouped:Bar(12, 4, 0, 3)
	grouped:Bar(12, 4, 0, -3)

	local collapse = Control(actions, function()
		return AllFolded(ns.Entries()) and "Expand all" or "Collapse all"
	end, FoldAll)
	collapse:SetPoint("RIGHT", grouped, "LEFT", -6, 0)
	collapse.chosen = function()
		return true
	end
	-- A chevron, pointing down: two short bars at 45 degrees.
	collapse.left = collapse:Bar(7, 2, -2, 0, -math.pi / 4)
	collapse.right = collapse:Bar(7, 2, 2, 0, math.pi / 4)
	frame.controls = { menu, single, grouped, collapse }

	-- The overall box.
	local overall = CreateFrame("Frame", nil, frame)
	overall:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -PAD)
	overall:SetPoint("TOPRIGHT", actions, "BOTTOMRIGHT", 0, -PAD)
	overall:SetHeight(OVERALL_HEIGHT)
	ns.Fill(overall, "BACKGROUND", Gray(BOX)):SetAllPoints()
	ns.DragHandle(frame, overall)
	overall.icon = overall:CreateTexture(nil, "ARTWORK")
	overall.icon:SetSize(30, 30)
	overall.icon:SetPoint("LEFT", 8, 0)
	overall.icon:SetTexture([[Interface\Icons\INV_Misc_Bag_10]])
	overall.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	overall.count = overall:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	overall.count:SetPoint("BOTTOMLEFT", overall.icon, "RIGHT", 10, 1)
	overall.value = overall:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	overall.value:SetPoint("TOPLEFT", overall.icon, "RIGHT", 10, -1)
	frame.overall = overall

	frame.scroll:SetPoint("TOPLEFT", overall, "BOTTOMLEFT", 0, -PAD)
	frame.scroll:SetPoint("BOTTOMRIGHT", -(PAD + 8), PAD)
	frame.bar:SetPoint("TOPRIGHT", overall, "BOTTOMRIGHT", 0, -PAD)
	frame.bar:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	frame.empty = frame.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.empty:SetPoint("TOP", 0, -12)
	frame.empty:SetText("No loot yet.")

	-- The resize grip: a few dots in the corner.
	local grip = ns.ResizeGrip(frame, 12)
	for i, spot in ipairs({ { 8, 0 }, { 4, 0 }, { 0, 0 }, { 8, 4 }, { 4, 4 }, { 8, 8 } }) do
		local dot = ns.Fill(grip, "ARTWORK", Gray(120))
		dot:SetSize(2, 2)
		dot:SetPoint("BOTTOMLEFT", spot[1] + 1, spot[2] + 1)
	end

	boxes = ns.Pool(NewBox)
	boxes.content = frame.content
	slots = ns.Pool(NewSlot)
	slots.content = frame.content
	return frame
end

local function Refresh(frame)
	frame.grip:SetShown(not ns.Locked())
	for _, control in ipairs(frame.controls) do
		control:Paint()
	end
end

-- The overall box's lines: the label gray, the number white.
local function Labeled(fontString, label, value)
	fontString:SetText(("|cffa5a5a5%s|r%s"):format(label, value))
end

local function Render(frame, entries, width)
	for _, control in ipairs(frame.controls) do
		control:Paint()
	end
	local grouped = Setting("grouping") ~= "individual"
	local kills, value = 0, 0
	for _, entry in ipairs(entries) do
		kills = kills + (grouped and (entry.count or 0) > 0 and entry.count or 1)
		value = value + ns.Value(entry)
	end
	local overall = frame.overall
	ns.StyleFont(overall.count, 12, FONT, "soft")
	ns.StyleFont(overall.value, 12, FONT, "soft")
	Labeled(overall.count, "Total count: ", kills)
	Labeled(overall.value, "Total value: ", ns.ShortMoney(value))

	local slotWidth = math.max(16, math.floor((width - (COLUMNS - 1)) / COLUMNS))
	local slotHeight = math.floor(slotWidth * 0.9 + 0.5)
	local iconSize = math.floor(slotHeight * 0.62 + 0.5)
	local y, boxCount, slotCount = 0, 0, 0

	local function Slot(index, top)
		slotCount = slotCount + 1
		local slot = slots:Get(slotCount)
		local col, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", col * (slotWidth + 1), -(top + row * (slotHeight + 1)))
		slot:SetSize(slotWidth, slotHeight)
		slot.icon:SetSize(iconSize, iconSize)
		ns.StyleFont(slot.count, math.max(9, math.floor(slotHeight * 0.3)), FONT, "soft")
		slot.link, slot.itemCount, slot.money = nil, nil, nil
		slot:Show()
		return slot
	end

	for _, entry in ipairs(entries) do
		boxCount = boxCount + 1
		local box = boxes:Get(boxCount)
		local title = box.title
		title.entry = entry
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", 0, -y)
		box:SetPoint("RIGHT")
		box:SetHeight(TITLE_HEIGHT)
		ns.StyleFont(title.name, 12, FONT, "soft")
		ns.StyleFont(title.kills, 12, FONT, "soft")
		ns.StyleFont(title.value, 12, FONT, "soft")
		local folded = ns.Folded(entry.key)
		title.name:SetText(entry.name or "?")
		title.name:SetTextColor(unpack(folded and LIGHT_GRAY or WHITE))
		title.kills:SetText(grouped and (entry.count or 0) > 1 and ("x " .. entry.count) or "")
		title.kills:SetTextColor(unpack(LIGHT_GRAY))
		local entryValue = ns.Value(entry)
		title.value:SetText(entryValue > 0 and ns.ShortMoney(entryValue) or "")
		title.value:SetTextColor(unpack(LIGHT_GRAY))
		-- The name gives way to the value.
		title.name:SetWidth(0)
		local room = width - 14 - title.value:GetStringWidth() - title.kills:GetStringWidth() - 12
		if title.name:GetStringWidth() > room then
			title.name:SetWidth(math.max(20, room))
		end
		box:Show()
		y = y + TITLE_HEIGHT
		if not folded then
			local top, index = y + 1, 0
			if (entry.money or 0) > 0 then
				index = index + 1
				local slot = Slot(index, top)
				slot.icon:SetTexture([[Interface\Icons\INV_Misc_Coin_01]])
				slot.icon:Show()
				slot.money = entry.money
				slot.count:SetText(ns.ShortMoney(entry.money))
				slot.count:SetTextColor(1, 1, 0)
			end
			for _, item in ipairs(entry.items) do
				index = index + 1
				local slot = Slot(index, top)
				slot.link, slot.itemCount = item.link, item.count
				slot.icon:SetTexture(item.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
				slot.icon:Show()
				if (item.count or 0) > 1 then
					local text, r, g, b = Stack(item.count)
					slot.count:SetText(text)
					slot.count:SetTextColor(r, g, b)
				else
					slot.count:SetText("")
				end
			end
			-- The last row filled out with empty slots.
			local rows = math.ceil(index / COLUMNS)
			for i = index + 1, rows * COLUMNS do
				local slot = Slot(i, top)
				slot.icon:Hide()
				slot.count:SetText("")
			end
			if rows > 0 then
				y = top + rows * (slotHeight + 1) - 1
			end
		end
		y = y + 8
	end
	boxes:HideFrom(boxCount + 1)
	slots:HideFrom(slotCount + 1)
	ns.StyleFont(frame.empty, 12, FONT, "soft")
	frame.empty:SetTextColor(unpack(LIGHT_GRAY))
	frame.empty:SetShown(boxCount == 0)
	return y
end

ns.RegisterStyle("runelite", {
	Build = Build,
	Refresh = Refresh,
	Render = Render,
})
